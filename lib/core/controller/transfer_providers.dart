import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../discovery/device_model.dart';
import '../discovery/discovery_providers.dart';
import '../encryption/encryption_service.dart';
import '../transport/protocol_messages.dart';
import '../transport/transport_service.dart';
import 'transfer_controller.dart';
import 'transfer_record.dart';

// ---------------------------------------------------------------------------
// Core service providers
// ---------------------------------------------------------------------------

/// Provides a singleton [EncryptionService].
final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
});

/// Provides the singleton [TransferController].
///
/// Wires in the encryption service, device identity, and the incoming
/// transfer callback (which prompts the UI notifier).
final transferControllerProvider = Provider<TransferController>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  final deviceName = ref.watch(deviceNameProvider);
  final deviceId = ref.watch(deviceIdProvider);

  final controller = TransferController(
    encryptionService: encryption,
    deviceName: deviceName,
    deviceId: deviceId,
  );

  ref.onDispose(() => controller.dispose());
  return controller;
});

// ---------------------------------------------------------------------------
// Transfer list providers
// ---------------------------------------------------------------------------

/// Stream of all transfer records — drives the transfer list UI.
final transferListProvider = StreamProvider<List<TransferRecord>>((ref) {
  final controller = ref.watch(transferControllerProvider);
  return controller.transfersStream;
});

/// Stream of individual transfer updates — useful for detail views.
final transferUpdatesProvider = StreamProvider<TransferRecord>((ref) {
  final controller = ref.watch(transferControllerProvider);
  return controller.transferUpdates;
});

/// The number of active (in-progress) transfers.
final activeTransferCountProvider = Provider<int>((ref) {
  final controller = ref.watch(transferControllerProvider);
  return controller.activeTransferCount;
});

// ---------------------------------------------------------------------------
// Transfer actions notifier
// ---------------------------------------------------------------------------

/// Notifier that exposes transfer actions (send, cancel, etc.) to the UI.
///
/// Usage:
/// ```dart
/// ref.read(transferActionsProvider.notifier).pickAndSend(device);
/// ```
final transferActionsProvider =
    NotifierProvider<TransferActionsNotifier, TransferActionsState>(
  TransferActionsNotifier.new,
);

/// Lightweight state for the transfer actions notifier.
class TransferActionsState {
  const TransferActionsState({
    this.isPicking = false,
    this.lastError,
  });

  /// Whether the file picker is currently open.
  final bool isPicking;

  /// Last error message (cleared on next action).
  final String? lastError;
}

class TransferActionsNotifier extends Notifier<TransferActionsState> {
  @override
  TransferActionsState build() => const TransferActionsState();

  TransferController get _controller =>
      ref.read(transferControllerProvider);

  /// Opens the file picker and sends the selected file to [device].
  ///
  /// Returns the transfer ID if successful, or `null` if the user
  /// cancelled the picker.
  Future<String?> pickAndSend(DeviceModel device) async {
    state = const TransferActionsState(isPicking: true);

    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) {
        state = const TransferActionsState();
        return null;
      }

      final path = result.files.single.path;
      if (path == null) {
        state = const TransferActionsState(
          lastError: 'Could not resolve file path',
        );
        return null;
      }

      final file = File(path);
      final transferId = await _controller.sendFile(
        device: device,
        file: file,
      );

      state = const TransferActionsState();
      return transferId;
    } catch (e) {
      state = TransferActionsState(lastError: e.toString());
      return null;
    }
  }

  /// Sends a file at a known path to [device] (no picker needed).
  Future<String?> sendFile(DeviceModel device, File file) async {
    try {
      final transferId = await _controller.sendFile(
        device: device,
        file: file,
      );
      state = const TransferActionsState();
      return transferId;
    } catch (e) {
      state = TransferActionsState(lastError: e.toString());
      return null;
    }
  }

  /// Cancels an in-progress transfer.
  void cancel(String transferId) {
    _controller.cancelTransfer(transferId);
  }

  /// Removes a finished transfer from the list.
  void remove(String transferId) {
    _controller.removeTransfer(transferId);
  }

  /// Clears all finished transfers.
  void clearFinished() {
    _controller.clearFinished();
  }
}

// ---------------------------------------------------------------------------
// Receive listener notifier
// ---------------------------------------------------------------------------

/// Notifier that manages the receive-side listener.
///
/// The UI calls `startListening()` to begin accepting incoming transfers,
/// and `stopListening()` to stop.
final receiveListenerProvider =
    NotifierProvider<ReceiveListenerNotifier, ReceiveListenerState>(
  ReceiveListenerNotifier.new,
);

/// State for the receive listener.
class ReceiveListenerState {
  const ReceiveListenerState({
    this.isListening = false,
    this.port,
  });

  final bool isListening;
  final int? port;
}

class ReceiveListenerNotifier extends Notifier<ReceiveListenerState> {
  @override
  ReceiveListenerState build() => const ReceiveListenerState();

  TransferController get _controller =>
      ref.read(transferControllerProvider);

  /// Starts listening for incoming transfers and registers the
  /// accept/reject callback.
  Future<void> startListening() async {
    // Wire in the incoming transfer callback — default is auto-accept
    // to the downloads directory. Sprint 5 UI will replace this with
    // a dialog-based flow.
    _controller.onIncomingTransfer = _defaultIncomingHandler;

    final port = await _controller.startReceiving();
    state = ReceiveListenerState(isListening: true, port: port);
  }

  /// Stops listening for incoming transfers.
  Future<void> stopListening() async {
    await _controller.stopReceiving();
    state = const ReceiveListenerState();
  }

  /// Default incoming file handler — saves to the platform downloads
  /// directory with the original filename.
  Future<File?> _defaultIncomingHandler(
    TransferRecord record,
    FileMetaMessage meta,
  ) async {
    final dir = await _getSaveDirectory();
    final savePath = '${dir.path}/${meta.fileName}';

    // Avoid overwriting — append a counter if file exists.
    var file = File(savePath);
    var counter = 1;
    while (await file.exists()) {
      final ext = meta.fileName.contains('.')
          ? '.${meta.fileName.split('.').last}'
          : '';
      final base = meta.fileName.contains('.')
          ? meta.fileName.substring(0, meta.fileName.lastIndexOf('.'))
          : meta.fileName;
      file = File('${dir.path}/$base ($counter)$ext');
      counter++;
    }

    return file;
  }

  /// Returns the best save directory for the current platform.
  Future<Directory> _getSaveDirectory() async {
    // Try downloads first, fall back to app documents.
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    return getApplicationDocumentsDirectory();
  }
}

// ---------------------------------------------------------------------------
// Convenience selectors
// ---------------------------------------------------------------------------

/// Provider that returns the [TransferState] of a specific transfer.
final transferStateProvider =
    Provider.family<TransferState?, String>((ref, transferId) {
  final controller = ref.watch(transferControllerProvider);
  return controller.getTransfer(transferId)?.state;
});

/// Provider that returns the progress (0.0–1.0) of a specific transfer.
final transferProgressProvider =
    Provider.family<double, String>((ref, transferId) {
  final controller = ref.watch(transferControllerProvider);
  return controller.getTransfer(transferId)?.progress ?? 0;
});
