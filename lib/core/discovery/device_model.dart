import 'dart:io';

/// Represents the type of device running SwiftDrop.
enum DeviceType {
  android('android', 'Android'),
  windows('windows', 'Windows'),
  linux('linux', 'Linux'),
  ios('ios', 'iOS'),
  unknown('unknown', 'Unknown');

  const DeviceType(this.code, this.displayName);

  final String code;
  final String displayName;

  /// Returns the [DeviceType] matching the given [code] string.
  static DeviceType fromCode(String code) {
    return DeviceType.values.firstWhere(
      (e) => e.code == code.toLowerCase(),
      orElse: () => DeviceType.unknown,
    );
  }

  /// Detects the current platform's device type.
  static DeviceType get current {
    if (Platform.isAndroid) return DeviceType.android;
    if (Platform.isWindows) return DeviceType.windows;
    if (Platform.isLinux) return DeviceType.linux;
    if (Platform.isIOS) return DeviceType.ios;
    return DeviceType.unknown;
  }
}

/// Represents the availability state of a discovered device.
enum DeviceState {
  /// Device is visible and ready to receive.
  available,

  /// Device is currently in an active transfer.
  busy,

  /// Device was previously seen but has gone offline.
  offline,

  /// Device was previously paired and is trusted.
  trusted,
}

/// Represents how the device was discovered / how data will be transported.
enum ConnectionType {
  /// Discovered via mDNS on the same WiFi/LAN.
  wifi,

  /// Discovered via Bluetooth LE.
  bluetooth,

  /// Connected via WebRTC (future).
  webrtc,
}

/// Model representing a discovered nearby device.
class DeviceModel {
  DeviceModel({
    required this.id,
    required this.name,
    this.ipAddress,
    this.port,
    required this.deviceType,
    this.connectionType = ConnectionType.wifi,
    this.state = DeviceState.available,
    this.protocolVersion = 1,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Unique identifier for this device (UUID-based, 8-char short form).
  final String id;

  /// Human-readable device name (e.g. "Pratham's Pixel").
  final String name;

  /// IP address on the local network (null for Bluetooth-only).
  final String? ipAddress;

  /// Port the device is listening on for transfers.
  final int? port;

  /// Type of device (Android, Windows, Linux, etc.).
  final DeviceType deviceType;

  /// How the device was discovered.
  final ConnectionType connectionType;

  /// Current availability state.
  DeviceState state;

  /// Protocol version reported by the device.
  final int protocolVersion;

  /// Last time this device was seen (for timeout/cleanup).
  DateTime lastSeen;

  /// Updates the [lastSeen] timestamp to now.
  void touch() {
    lastSeen = DateTime.now();
  }

  /// Whether this device has timed out (not seen within [timeoutSeconds]).
  bool isTimedOut({int timeoutSeconds = 15}) {
    return DateTime.now().difference(lastSeen).inSeconds > timeoutSeconds;
  }

  /// Creates a copy with updated fields.
  DeviceModel copyWith({
    String? id,
    String? name,
    String? ipAddress,
    int? port,
    DeviceType? deviceType,
    ConnectionType? connectionType,
    DeviceState? state,
    int? protocolVersion,
    DateTime? lastSeen,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      deviceType: deviceType ?? this.deviceType,
      connectionType: connectionType ?? this.connectionType,
      state: state ?? this.state,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'DeviceModel(id: $id, name: $name, ip: $ipAddress:$port, '
      'type: ${deviceType.displayName}, state: $state)';
}
