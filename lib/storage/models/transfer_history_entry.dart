import 'package:hive/hive.dart';

/// A persisted transfer history entry.
///
/// Saved to Hive after a transfer completes (success or failure)
/// so the user can review past transfers.
@HiveType(typeId: 2)
class TransferHistoryEntry extends HiveObject {
  TransferHistoryEntry({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.direction,
    required this.status,
    this.filePath,
    this.errorMessage,
    DateTime? timestamp,
    this.durationMs = 0,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Unique transfer ID (matches TransferRecord.id).
  @HiveField(0)
  final String transferId;

  /// Name of the file transferred.
  @HiveField(1)
  final String fileName;

  /// File size in bytes.
  @HiveField(2)
  final int fileSize;

  /// Remote device ID.
  @HiveField(3)
  final String deviceId;

  /// Remote device name at the time of transfer.
  @HiveField(4)
  final String deviceName;

  /// Remote device type code.
  @HiveField(5)
  final String deviceType;

  /// 'outgoing' or 'incoming'.
  @HiveField(6)
  final String direction;

  /// Final status: 'completed', 'failed', or 'cancelled'.
  @HiveField(7)
  final String status;

  /// Local file path (source for outgoing, save path for incoming).
  @HiveField(8)
  final String? filePath;

  /// Error message if the transfer failed.
  @HiveField(9)
  final String? errorMessage;

  /// When the transfer finished.
  @HiveField(10)
  final DateTime timestamp;

  /// Transfer duration in milliseconds.
  @HiveField(11)
  final int durationMs;

  /// Whether the transfer was successful.
  bool get isSuccess => status == 'completed';

  /// Whether this was an outgoing transfer.
  bool get isOutgoing => direction == 'outgoing';

  /// Human-readable file size.
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransferHistoryEntry &&
          runtimeType == other.runtimeType &&
          transferId == other.transferId;

  @override
  int get hashCode => transferId.hashCode;

  @override
  String toString() =>
      'TransferHistoryEntry($direction $fileName → $deviceName, $status)';
}

/// Hand-written Hive adapter for [TransferHistoryEntry].
class TransferHistoryEntryAdapter extends TypeAdapter<TransferHistoryEntry> {
  @override
  final int typeId = 2;

  @override
  TransferHistoryEntry read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return TransferHistoryEntry(
      transferId: fields[0] as String? ?? '',
      fileName: fields[1] as String? ?? '',
      fileSize: fields[2] as int? ?? 0,
      deviceId: fields[3] as String? ?? '',
      deviceName: fields[4] as String? ?? 'Unknown',
      deviceType: fields[5] as String? ?? 'unknown',
      direction: fields[6] as String? ?? 'outgoing',
      status: fields[7] as String? ?? 'failed',
      filePath: fields[8] as String?,
      errorMessage: fields[9] as String?,
      timestamp: fields[10] as DateTime?,
      durationMs: fields[11] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, TransferHistoryEntry obj) {
    writer
      ..writeByte(12) // number of fields
      ..writeByte(0)
      ..write(obj.transferId)
      ..writeByte(1)
      ..write(obj.fileName)
      ..writeByte(2)
      ..write(obj.fileSize)
      ..writeByte(3)
      ..write(obj.deviceId)
      ..writeByte(4)
      ..write(obj.deviceName)
      ..writeByte(5)
      ..write(obj.deviceType)
      ..writeByte(6)
      ..write(obj.direction)
      ..writeByte(7)
      ..write(obj.status)
      ..writeByte(8)
      ..write(obj.filePath)
      ..writeByte(9)
      ..write(obj.errorMessage)
      ..writeByte(10)
      ..write(obj.timestamp)
      ..writeByte(11)
      ..write(obj.durationMs);
  }
}
