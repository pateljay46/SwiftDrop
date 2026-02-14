import 'dart:async';
import 'dart:io';

/// Monitors network connectivity changes and reports WiFi availability.
///
/// Uses periodic polling of network interfaces since `dart:io` does not
/// provide native change events. On Android, the Flutter plugin
/// `network_info_plus` provides richer info (WiFi name, BSSID, etc.).
class NetworkMonitor {
  Timer? _pollTimer;
  bool _lastConnected = false;

  final StreamController<NetworkStatus> _statusController =
      StreamController<NetworkStatus>.broadcast();

  /// Stream of network status changes.
  Stream<NetworkStatus> get statusStream => _statusController.stream;

  /// Current cached network status.
  NetworkStatus _cachedStatus = const NetworkStatus(
    isConnected: false,
    type: NetworkType.none,
  );

  /// Current network status (last known).
  NetworkStatus get currentStatus => _cachedStatus;

  /// Start monitoring network changes (polls every [intervalSeconds]).
  Future<void> start({int intervalSeconds = 3}) async {
    _lastConnected = await _hasWifiInterface();
    _cachedStatus = await _checkNetwork();
    _emitStatus();

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _poll(),
    );
  }

  /// Stop monitoring.
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Dispose the monitor.
  Future<void> dispose() async {
    stop();
    await _statusController.close();
  }

  Future<void> _poll() async {
    final connected = await _hasWifiInterface();
    if (connected != _lastConnected) {
      _lastConnected = connected;
      _cachedStatus = await _checkNetwork();
      _emitStatus();
    }
  }

  void _emitStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(_cachedStatus);
    }
  }

  Future<NetworkStatus> _checkNetwork() async {
    final interfaces = await _getActiveInterfaces();
    if (interfaces.isEmpty) {
      return const NetworkStatus(
        isConnected: false,
        type: NetworkType.none,
      );
    }

    // Check for WiFi/Ethernet (non-loopback, non-link-local IPv4).
    final hasIpv4 = interfaces.any(
      (iface) => iface.addresses.any(
        (addr) =>
            addr.type == InternetAddressType.IPv4 && !addr.isLoopback,
      ),
    );

    if (hasIpv4) {
      return NetworkStatus(
        isConnected: true,
        type: NetworkType.wifi,
        localIp: _getLocalIpAddress(interfaces),
      );
    }

    return const NetworkStatus(
      isConnected: true,
      type: NetworkType.other,
    );
  }

  Future<bool> _hasWifiInterface() async {
    try {
      final interfaces = await _getActiveInterfaces();
      return interfaces.any(
        (iface) => iface.addresses.any(
          (addr) =>
              addr.type == InternetAddressType.IPv4 && !addr.isLoopback,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<List<NetworkInterface>> _getActiveInterfaces() async {
    try {
      return await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
    } catch (_) {
      return [];
    }
  }

  String? _getLocalIpAddress(List<NetworkInterface> interfaces) {
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return null;
  }
}

/// Represents the current network state.
class NetworkStatus {
  const NetworkStatus({
    required this.isConnected,
    required this.type,
    this.localIp,
  });

  final bool isConnected;
  final NetworkType type;
  final String? localIp;

  @override
  String toString() =>
      'NetworkStatus(connected: $isConnected, type: $type, ip: $localIp)';
}

/// Type of network connection.
enum NetworkType {
  wifi,
  ethernet,
  other,
  none,
}
