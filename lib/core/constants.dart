/// Protocol-wide constants for SwiftDrop.
///
/// Centralizes service names, default ports, timeouts, and protocol
/// version info used across discovery, transport, and controller layers.
class SwiftDropConstants {
  SwiftDropConstants._();

  // ---------------------------------------------------------------------------
  // Protocol
  // ---------------------------------------------------------------------------

  /// Current wire protocol version.
  static const int protocolVersion = 1;

  /// Minimum protocol version this build can interoperate with.
  static const int minSupportedProtocolVersion = 1;

  /// mDNS service type for SwiftDrop device discovery.
  static const String serviceType = '_swiftdrop._tcp';

  /// mDNS service name prefix. Full name = "$prefix-$deviceId".
  static const String serviceNamePrefix = 'SwiftDrop';

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  /// How often (in seconds) to re-scan for mDNS services.
  static const int discoveryIntervalSeconds = 3;

  /// Seconds without a heartbeat before a device is considered offline.
  static const int deviceTimeoutSeconds = 15;

  /// Maximum number of devices to display in the UI.
  static const int maxVisibleDevices = 10;

  // ---------------------------------------------------------------------------
  // Transfer
  // ---------------------------------------------------------------------------

  /// Default chunk size in bytes (64 KB).
  static const int defaultChunkSize = 65536;

  /// Maximum retry attempts per chunk before aborting transfer.
  static const int maxChunkRetries = 3;

  /// Seconds to wait for a device to reappear after connection drop.
  static const int reconnectTimeoutSeconds = 60;

  /// Maximum number of concurrent transfers.
  static const int maxConcurrentTransfers = 3;

  // ---------------------------------------------------------------------------
  // mDNS TXT record keys
  // ---------------------------------------------------------------------------

  /// TXT record key for device name.
  static const String txtKeyDeviceName = 'dn';

  /// TXT record key for device type (android, windows, linux).
  static const String txtKeyDeviceType = 'dt';

  /// TXT record key for protocol version.
  static const String txtKeyVersion = 'v';

  /// TXT record key for device unique ID (short 8-char).
  static const String txtKeyDeviceId = 'id';

  /// TXT record key for transfer port.
  static const String txtKeyPort = 'tp';
}
