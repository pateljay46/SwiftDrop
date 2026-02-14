import '../discovery/device_model.dart';
import '../transport/transport_service.dart';

/// Direction of a file transfer.
enum TransferDirection {
  /// This device is sending the file.
  outgoing,

  /// This device is receiving the file.
  incoming,
}

/// A single file transfer record, tracking state from initiation to
/// completion. Used by the controller and UI layers.
class TransferRecord {
  TransferRecord({
    required this.id,
    required this.direction,
    required this.device,
    required this.fileName,
    required this.fileSize,
    this.filePath,
    this.savePath,
    this.state = TransferState.idle,
    this.chunksTotal = 0,
    this.chunksCompleted = 0,
    this.bytesTransferred = 0,
    this.errorMessage,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Unique identifier for this transfer.
  final String id;

  /// Whether we are sending or receiving.
  final TransferDirection direction;

  /// The remote peer device.
  final DeviceModel device;

  /// Name of the file being transferred.
  final String fileName;

  /// Total file size in bytes.
  final int fileSize;

  /// Local file path (for outgoing transfers — the source file).
  final String? filePath;

  /// Local save path (for incoming transfers — where to write).
  final String? savePath;

  /// Current transfer state.
  TransferState state;

  /// Total number of chunks.
  int chunksTotal;

  /// Number of chunks successfully transferred.
  int chunksCompleted;

  /// Bytes transferred so far.
  int bytesTransferred;

  /// Error message (set when [state] is [TransferState.failed]).
  String? errorMessage;

  /// When this transfer was created.
  final DateTime createdAt;

  /// Fractional progress from 0.0 to 1.0.
  double get progress => chunksTotal > 0 ? chunksCompleted / chunksTotal : 0;

  /// Whether the transfer is in a terminal state.
  bool get isFinished =>
      state == TransferState.completed ||
      state == TransferState.cancelled ||
      state == TransferState.failed;

  /// Whether the transfer is actively running.
  bool get isActive =>
      state == TransferState.handshaking ||
      state == TransferState.awaitingAccept ||
      state == TransferState.transferring ||
      state == TransferState.verifying;

  /// Updates fields from a [TransferProgress] emitted by the transport layer.
  void applyProgress(TransferProgress progress) {
    state = progress.state;
    chunksTotal = progress.chunksTotal;
    chunksCompleted = progress.chunksCompleted;
    bytesTransferred = progress.bytesTransferred;
    errorMessage = progress.errorMessage;
  }

  /// Creates a shallow copy with updated fields.
  TransferRecord copyWith({
    TransferState? state,
    int? chunksTotal,
    int? chunksCompleted,
    int? bytesTransferred,
    String? errorMessage,
    String? savePath,
  }) {
    return TransferRecord(
      id: id,
      direction: direction,
      device: device,
      fileName: fileName,
      fileSize: fileSize,
      filePath: filePath,
      savePath: savePath ?? this.savePath,
      state: state ?? this.state,
      chunksTotal: chunksTotal ?? this.chunksTotal,
      chunksCompleted: chunksCompleted ?? this.chunksCompleted,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransferRecord &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'TransferRecord(id: $id, ${direction.name}, $fileName, '
      '${state.name}, $chunksCompleted/$chunksTotal)';
}
