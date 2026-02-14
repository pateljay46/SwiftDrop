import 'package:hive/hive.dart';

/// A previously-paired device that the user has marked as trusted.
///
/// Trusted devices can optionally auto-accept incoming transfers.
@HiveType(typeId: 1)
class TrustedDevice extends HiveObject {
  TrustedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    this.autoAccept = false,
    DateTime? firstPaired,
    DateTime? lastSeen,
  })  : firstPaired = firstPaired ?? DateTime.now(),
        lastSeen = lastSeen ?? DateTime.now();

  /// The unique 8-char device identifier.
  @HiveField(0)
  final String deviceId;

  /// Human-readable device name.
  @HiveField(1)
  String deviceName;

  /// Device type code (android, windows, linux, etc.).
  @HiveField(2)
  final String deviceType;

  /// Whether to auto-accept transfers from this device.
  @HiveField(3)
  bool autoAccept;

  /// When this device was first paired.
  @HiveField(4)
  final DateTime firstPaired;

  /// Last time a transfer was completed with this device.
  @HiveField(5)
  DateTime lastSeen;

  /// Updates [lastSeen] to now and optionally the name.
  void touch({String? name}) {
    lastSeen = DateTime.now();
    if (name != null) deviceName = name;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrustedDevice &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId;

  @override
  int get hashCode => deviceId.hashCode;

  @override
  String toString() =>
      'TrustedDevice(id: $deviceId, name: $deviceName, '
      'type: $deviceType, autoAccept: $autoAccept)';
}

/// Hand-written Hive adapter for [TrustedDevice].
class TrustedDeviceAdapter extends TypeAdapter<TrustedDevice> {
  @override
  final int typeId = 1;

  @override
  TrustedDevice read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return TrustedDevice(
      deviceId: fields[0] as String? ?? '',
      deviceName: fields[1] as String? ?? 'Unknown',
      deviceType: fields[2] as String? ?? 'unknown',
      autoAccept: fields[3] as bool? ?? false,
      firstPaired: fields[4] as DateTime?,
      lastSeen: fields[5] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, TrustedDevice obj) {
    writer
      ..writeByte(6) // number of fields
      ..writeByte(0)
      ..write(obj.deviceId)
      ..writeByte(1)
      ..write(obj.deviceName)
      ..writeByte(2)
      ..write(obj.deviceType)
      ..writeByte(3)
      ..write(obj.autoAccept)
      ..writeByte(4)
      ..write(obj.firstPaired)
      ..writeByte(5)
      ..write(obj.lastSeen);
  }
}
