import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../constants.dart';
import '../discovery/device_model.dart';
import '../encryption/encryption_service.dart';
import '../transport/protocol_messages.dart';
import '../transport/transport_connection.dart';
import '../transport/transport_service.dart';
import 'transfer_record.dart';

/// Callback for incoming file transfer offers that the receiver must
/// accept or reject.
///
/// Return a [File] to accept (the file to write to), or `null` to reject.
typedef IncomingTransferCallback = Future<File?> Function(
  TransferRecord record,
  FileMetaMessage meta,
);

/// Central controller that orchestrates the full file transfer lifecycle.
///
/// Sits between the UI/provider layer and the transport/discovery layers.
/// Manages a queue of [TransferRecord]s, enforces concurrency limits,
/// and bridges [TransportService] events to UI-consumable state updates.
class TransferController {
  TransferController({
    required this.encryptionService,
    required this.deviceName,
    required this.deviceId,
    this.maxConcurrentTransfers = SwiftDropConstants.maxConcurrentTransfers,
    IncomingTransferCallback? onIncomingTransfer,
  }) : _onIncomingTransfer = onIncomingTransfer;

  final EncryptionService encryptionService;
  final String deviceName;
  final String deviceId;
  final int maxConcurrentTransfers;
  IncomingTransferCallback? _onIncomingTransfer;

  static const _uuid = Uuid();

  final _transfers = <String, TransferRecord>{};
  final _activeTransferIds = <String>{};
  final _transferStreamController =
      StreamController<List<TransferRecord>>.broadcast();
  final _singleTransferController =
      StreamController<TransferRecord>.broadcast();

  TransportServer? _receiveServer;
  StreamSubscription<PeerConnection>? _connectionSub;

  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Stream of the full transfer list (emitted on every change).
  Stream<List<TransferRecord>> get transfersStream =>
      _transferStreamController.stream;

  /// Stream of individual transfer updates.
  Stream<TransferRecord> get transferUpdates =>
      _singleTransferController.stream;

  /// Current snapshot of all transfers.
  List<TransferRecord> get transfers => List.unmodifiable(_transfers.values);

  /// Active (in-progress) transfer count.
  int get activeTransferCount => _activeTransferIds.length;

  /// Set the callback for incoming transfer offers.
  set onIncomingTransfer(IncomingTransferCallback? callback) {
    _onIncomingTransfer = callback;
  }

  /// Looks up a transfer by its ID.
  TransferRecord? getTransfer(String id) => _transfers[id];

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Sends a file to a discovered [device].
  ///
  /// Creates a [TransferRecord], starts a TCP server, waits for the
  /// receiver to connect, then runs the full transfer pipeline.
  ///
  /// Returns the transfer ID immediately — progress is streamed via
  /// [transfersStream] and [transferUpdates].
  Future<String> sendFile({
    required DeviceModel device,
    required File file,
  }) async {
    if (_disposed) throw StateError('TransferController is disposed');
    if (_activeTransferIds.length >= maxConcurrentTransfers) {
      throw StateError(
        'Max concurrent transfers ($maxConcurrentTransfers) reached',
      );
    }

    final fileName = file.uri.pathSegments.last;
    final fileSize = await file.length();
    final transferId = _uuid.v4();

    final record = TransferRecord(
      id: transferId,
      direction: TransferDirection.outgoing,
      device: device,
      fileName: fileName,
      fileSize: fileSize,
      filePath: file.path,
    );

    _transfers[transferId] = record;
    _activeTransferIds.add(transferId);
    _emitUpdate(record);

    // Fire-and-forget the transfer — progress comes via callbacks.
    unawaited(_executeSend(record, file));

    return transferId;
  }

  Future<void> _executeSend(TransferRecord record, File file) async {
    TransportServer? server;
    PeerConnection? connection;

    try {
      // Start TCP server on ephemeral port.
      server = await TransportServer.start();

      record.state = TransferState.handshaking;
      _emitUpdate(record);

      // Wait for receiver to connect.
      connection = await server.connections.first.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException(
          'No receiver connected within 30 seconds',
        ),
      );

      // Run the transport service send flow.
      final transportService = TransportService(
        encryptionService: encryptionService,
        deviceName: deviceName,
        deviceId: deviceId,
      );

      await transportService.sendFile(
        connection: connection,
        file: file,
        onProgress: (progress) {
          record.applyProgress(progress);
          _emitUpdate(record);
        },
      );

      transportService.dispose();
    } catch (e) {
      record.state = TransferState.failed;
      record.errorMessage = e.toString();
      _emitUpdate(record);
    } finally {
      _activeTransferIds.remove(record.id);
      await connection?.dispose();
      await server?.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Receiving
  // ---------------------------------------------------------------------------

  /// Starts listening for incoming transfers on an ephemeral TCP port.
  ///
  /// Returns the port number so the discovery layer can advertise it.
  Future<int> startReceiving() async {
    if (_disposed) throw StateError('TransferController is disposed');
    if (_receiveServer != null) return _receiveServer!.port;

    _receiveServer = await TransportServer.start();
    _connectionSub = _receiveServer!.connections.listen(_handleIncoming);

    return _receiveServer!.port;
  }

  /// Stops listening for incoming transfers.
  Future<void> stopReceiving() async {
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _receiveServer?.dispose();
    _receiveServer = null;
  }

  /// Port the receive server is listening on, or `null` if not listening.
  int? get receivePort => _receiveServer?.port;

  Future<void> _handleIncoming(PeerConnection connection) async {
    if (_activeTransferIds.length >= maxConcurrentTransfers) {
      // Reject — too many active transfers.
      connection.send(const ErrorMessage(
        errorCode: ProtocolErrorCode.internalError,
        message: 'Receiver busy — max concurrent transfers reached',
      ));
      await connection.dispose();
      return;
    }

    final transferId = _uuid.v4();
    final record = TransferRecord(
      id: transferId,
      direction: TransferDirection.incoming,
      device: DeviceModel(
        id: 'pending',
        name: connection.remoteAddress.address,
        ipAddress: connection.remoteAddress.address,
        port: connection.remotePort,
        deviceType: DeviceType.unknown,
      ),
      fileName: 'pending...',
      fileSize: 0,
    );

    _transfers[transferId] = record;
    _activeTransferIds.add(transferId);
    _emitUpdate(record);

    try {
      final transportService = TransportService(
        encryptionService: encryptionService,
        deviceName: deviceName,
        deviceId: deviceId,
      );

      await transportService.receiveFile(
        connection: connection,
        onFileOffer: (meta) async {
          // Update record with real metadata.
          record
            ..state = TransferState.awaitingAccept
            ..chunksTotal = meta.chunkCount;
          _emitUpdate(record);

          if (_onIncomingTransfer == null) return null;
          return _onIncomingTransfer!(record, meta);
        },
        onProgress: (progress) {
          record.applyProgress(progress);
          _emitUpdate(record);
        },
      );

      transportService.dispose();
    } catch (e) {
      record.state = TransferState.failed;
      record.errorMessage = e.toString();
      _emitUpdate(record);
    } finally {
      _activeTransferIds.remove(transferId);
      await connection.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Cancel
  // ---------------------------------------------------------------------------

  /// Cancels an in-progress transfer.
  ///
  /// Currently marks it as cancelled; in a future iteration the
  /// underlying TCP connection would also be torn down.
  void cancelTransfer(String transferId) {
    final record = _transfers[transferId];
    if (record == null || record.isFinished) return;

    record.state = TransferState.cancelled;
    _activeTransferIds.remove(transferId);
    _emitUpdate(record);
  }

  /// Removes a finished transfer from the list.
  void removeTransfer(String transferId) {
    final record = _transfers.remove(transferId);
    if (record != null) {
      _emitList();
    }
  }

  /// Clears all finished transfers.
  void clearFinished() {
    _transfers.removeWhere((_, r) => r.isFinished);
    _emitList();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Disposes all resources — stops receiving, cleans up streams.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopReceiving();
    await _transferStreamController.close();
    await _singleTransferController.close();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _emitUpdate(TransferRecord record) {
    if (_disposed) return;
    _singleTransferController.add(record);
    _emitList();
  }

  void _emitList() {
    if (_disposed) return;
    _transferStreamController.add(transfers);
  }
}
