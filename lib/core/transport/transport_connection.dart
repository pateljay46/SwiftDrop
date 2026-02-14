import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'protocol_codec.dart';
import 'protocol_messages.dart';

/// A callback invoked when a new peer connection is established.
typedef OnPeerConnected = void Function(PeerConnection connection);

/// Wraps a [Socket] to provide message-level send/receive over the
/// SwiftDrop wire protocol.
class PeerConnection {
  PeerConnection(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
    );
  }

  final Socket _socket;
  final ProtocolCodec _codec = const ProtocolCodec();
  final _buffer = BytesBuilder(copy: false);
  final _messageController = StreamController<ProtocolMessage>.broadcast();
  late final StreamSubscription<Uint8List> _subscription;

  bool _disposed = false;
  int _nextSeqNo = 0;

  /// Incoming message stream from the remote peer.
  Stream<ProtocolMessage> get messages => _messageController.stream;

  /// Remote address of the peer.
  InternetAddress get remoteAddress => _socket.remoteAddress;

  /// Remote port of the peer.
  int get remotePort => _socket.remotePort;

  /// Whether the connection has been disposed.
  bool get isDisposed => _disposed;

  /// Sends a [ProtocolMessage] to the peer.
  ///
  /// Automatically assigns a sequence number if [autoSeqNo] is true.
  void send(ProtocolMessage message, {bool autoSeqNo = true}) {
    if (_disposed) return;
    final msg = autoSeqNo ? _withSeqNo(message) : message;
    final bytes = _codec.encode(msg);
    _socket.add(bytes);
  }

  /// Sends a message and waits for a response matching [predicate].
  ///
  /// Times out after [timeout] (default 30 seconds).
  Future<ProtocolMessage> sendAndWait(
    ProtocolMessage message, {
    bool Function(ProtocolMessage)? predicate,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    send(message);
    final stream = predicate != null
        ? _messageController.stream.where(predicate)
        : _messageController.stream;
    return stream.first.timeout(timeout);
  }

  /// Waits for the next message matching [predicate].
  Future<ProtocolMessage> waitFor({
    bool Function(ProtocolMessage)? predicate,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final stream = predicate != null
        ? _messageController.stream.where(predicate)
        : _messageController.stream;
    return stream.first.timeout(timeout);
  }

  /// Flushes the socket output buffer.
  Future<void> flush() async {
    if (_disposed) return;
    await _socket.flush();
  }

  /// Closes the connection and releases resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    await _socket.close();
    await _messageController.close();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _onData(Uint8List data) {
    _buffer.add(data);
    _drainBuffer();
  }

  void _drainBuffer() {
    while (true) {
      final accumulated = _buffer.takeBytes();
      if (accumulated.isEmpty) return;

      final size = _codec.completeMessageSize(accumulated);
      if (size == null) {
        // Not enough data yet — put it back.
        _buffer.add(accumulated);
        return;
      }

      try {
        final result = _codec.decode(accumulated);
        _messageController.add(result.message);

        // Re-add leftover bytes.
        if (result.bytesConsumed < accumulated.length) {
          _buffer.add(
            Uint8List.sublistView(accumulated, result.bytesConsumed),
          );
        }
      } on ArgumentError catch (e) {
        _messageController.addError(e);
        return;
      }
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!_disposed) {
      _messageController.addError(error, stackTrace);
    }
  }

  void _onDone() {
    if (!_disposed) {
      _messageController.close();
    }
  }

  ProtocolMessage _withSeqNo(ProtocolMessage message) {
    final seq = _nextSeqNo++;
    return switch (message) {
      final HandshakeMessage m => HandshakeMessage(
          type: m.type,
          seqNo: seq,
          protocolVersion: m.protocolVersion,
          publicKey: m.publicKey,
          deviceName: m.deviceName,
          deviceId: m.deviceId,
        ),
      final HandshakeConfirmMessage m => HandshakeConfirmMessage(
          seqNo: seq,
          pairingHash: m.pairingHash,
        ),
      final FileMetaMessage m => FileMetaMessage(
          seqNo: seq,
          fileName: m.fileName,
          fileSize: m.fileSize,
          chunkSize: m.chunkSize,
          chunkCount: m.chunkCount,
          fileChecksum: m.fileChecksum,
        ),
      FileAcceptMessage _ => FileAcceptMessage(seqNo: seq),
      final FileRejectMessage m => FileRejectMessage(seqNo: seq, reason: m.reason),
      final ChunkDataMessage m => ChunkDataMessage(
          seqNo: seq,
          chunkIndex: m.chunkIndex,
          iv: m.iv,
          encryptedData: m.encryptedData,
          gcmTag: m.gcmTag,
          plaintextChecksum: m.plaintextChecksum,
        ),
      final ChunkAckMessage m => ChunkAckMessage(seqNo: seq, chunkIndex: m.chunkIndex),
      final ChunkNackMessage m => ChunkNackMessage(
          seqNo: seq,
          chunkIndex: m.chunkIndex,
          errorCode: m.errorCode,
        ),
      final TransferCompleteMessage m => TransferCompleteMessage(
          seqNo: seq,
          totalChunks: m.totalChunks,
        ),
      TransferVerifiedMessage _ => TransferVerifiedMessage(seqNo: seq),
      final ErrorMessage m => ErrorMessage(
          seqNo: seq,
          errorCode: m.errorCode,
          message: m.message,
        ),
      CancelMessage _ => CancelMessage(seqNo: seq),
    };
  }
}

/// TCP server that listens for incoming peer connections.
///
/// Used by the **sender** side — binds to an ephemeral port, advertises
/// that port via mDNS TXT records, and waits for the receiver to connect.
class TransportServer {
  TransportServer._();

  ServerSocket? _serverSocket;
  final _connections = <PeerConnection>[];
  // ignore: close_sinks
  final _connectionController =
      StreamController<PeerConnection>.broadcast();
  bool _disposed = false;

  /// Stream of incoming peer connections.
  Stream<PeerConnection> get connections => _connectionController.stream;

  /// The port the server is listening on. Only valid after [start].
  int get port => _serverSocket?.port ?? 0;

  /// Whether the server is currently listening.
  bool get isListening => _serverSocket != null && !_disposed;

  /// Creates and starts a [TransportServer] on an ephemeral port.
  ///
  /// Optionally bind to a specific [address] (defaults to any IPv4).
  static Future<TransportServer> start({
    InternetAddress? address,
    int port = 0,
  }) async {
    final server = TransportServer._();
    server._serverSocket = await ServerSocket.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    server._serverSocket!.listen(
      server._onConnection,
      onError: server._onError,
      onDone: server._onDone,
    );
    return server;
  }

  /// Closes the server and all active connections.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _serverSocket?.close();
    for (final conn in _connections) {
      await conn.dispose();
    }
    _connections.clear();
    await _connectionController.close();
  }

  void _onConnection(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final connection = PeerConnection(socket);
    _connections.add(connection);
    _connectionController.add(connection);
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!_disposed) {
      _connectionController.addError(error, stackTrace);
    }
  }

  void _onDone() {
    if (!_disposed) {
      _connectionController.close();
    }
  }
}

/// TCP client that connects to a remote [TransportServer].
///
/// Used by the **receiver** side — connects to the sender's advertised
/// IP + port after discovering it via mDNS.
class TransportClient {
  const TransportClient._();

  /// Connects to a remote transport server and returns a [PeerConnection].
  static Future<PeerConnection> connect(
    InternetAddress address,
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // ignore: close_sinks — socket is closed via PeerConnection.dispose()
    final socket = await Socket.connect(address, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return PeerConnection(socket);
  }
}
