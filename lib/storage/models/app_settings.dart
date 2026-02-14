import 'package:hive/hive.dart';

/// Persisted application settings.
///
/// Stored as a single entry in the settings Hive box.
@HiveType(typeId: 0)
class AppSettings extends HiveObject {
  AppSettings({
    this.deviceName,
    this.saveDirectory,
    this.autoAcceptFromTrusted = false,
    this.maxConcurrentTransfers = 3,
    this.chunkSizeBytes = 65536,
    this.showNotifications = true,
    this.keepTransferHistory = true,
    this.darkMode = true,
  });

  /// Custom device name (null = use system hostname).
  @HiveField(0)
  String? deviceName;

  /// Default directory for received files (null = platform downloads).
  @HiveField(1)
  String? saveDirectory;

  /// Auto-accept incoming transfers from trusted devices.
  @HiveField(2)
  bool autoAcceptFromTrusted;

  /// Maximum concurrent transfers allowed.
  @HiveField(3)
  int maxConcurrentTransfers;

  /// Chunk size in bytes for file transfers.
  @HiveField(4)
  int chunkSizeBytes;

  /// Whether to show system notifications for incoming transfers.
  @HiveField(5)
  bool showNotifications;

  /// Whether to keep transfer history after completion.
  @HiveField(6)
  bool keepTransferHistory;

  /// Whether to use dark mode.
  @HiveField(7)
  bool darkMode;

  /// Creates a copy with updated fields.
  AppSettings copyWith({
    String? deviceName,
    String? saveDirectory,
    bool? autoAcceptFromTrusted,
    int? maxConcurrentTransfers,
    int? chunkSizeBytes,
    bool? showNotifications,
    bool? keepTransferHistory,
    bool? darkMode,
  }) {
    return AppSettings(
      deviceName: deviceName ?? this.deviceName,
      saveDirectory: saveDirectory ?? this.saveDirectory,
      autoAcceptFromTrusted:
          autoAcceptFromTrusted ?? this.autoAcceptFromTrusted,
      maxConcurrentTransfers:
          maxConcurrentTransfers ?? this.maxConcurrentTransfers,
      chunkSizeBytes: chunkSizeBytes ?? this.chunkSizeBytes,
      showNotifications: showNotifications ?? this.showNotifications,
      keepTransferHistory: keepTransferHistory ?? this.keepTransferHistory,
      darkMode: darkMode ?? this.darkMode,
    );
  }

  @override
  String toString() =>
      'AppSettings(deviceName: $deviceName, save: $saveDirectory, '
      'autoAccept: $autoAcceptFromTrusted, concurrent: $maxConcurrentTransfers)';
}

/// Hand-written Hive adapter for [AppSettings].
class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 0;

  @override
  AppSettings read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return AppSettings(
      deviceName: fields[0] as String?,
      saveDirectory: fields[1] as String?,
      autoAcceptFromTrusted: fields[2] as bool? ?? false,
      maxConcurrentTransfers: fields[3] as int? ?? 3,
      chunkSizeBytes: fields[4] as int? ?? 65536,
      showNotifications: fields[5] as bool? ?? true,
      keepTransferHistory: fields[6] as bool? ?? true,
      darkMode: fields[7] as bool? ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(8) // number of fields
      ..writeByte(0)
      ..write(obj.deviceName)
      ..writeByte(1)
      ..write(obj.saveDirectory)
      ..writeByte(2)
      ..write(obj.autoAcceptFromTrusted)
      ..writeByte(3)
      ..write(obj.maxConcurrentTransfers)
      ..writeByte(4)
      ..write(obj.chunkSizeBytes)
      ..writeByte(5)
      ..write(obj.showNotifications)
      ..writeByte(6)
      ..write(obj.keepTransferHistory)
      ..writeByte(7)
      ..write(obj.darkMode);
  }
}
