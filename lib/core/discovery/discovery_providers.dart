import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../constants.dart';
import 'device_model.dart';
import 'discovery_service.dart';
import 'network_monitor.dart';

// ---------------------------------------------------------------------------
// Device identity providers
// ---------------------------------------------------------------------------

/// Provides the unique device ID (8-char short form, persisted per install).
///
/// For MVP this generates a new ID each app launch. In Sprint 5 we'll
/// persist it via Hive.
final deviceIdProvider = Provider<String>((ref) {
  const uuid = Uuid();
  // Take first 8 chars of a v4 UUID (no hyphens).
  return uuid.v4().replaceAll('-', '').substring(0, 8);
});

/// Provides a human-readable device name.
final deviceNameProvider = Provider<String>((ref) {
  return '${SwiftDropConstants.serviceNamePrefix}-${Platform.localHostname}';
});

// ---------------------------------------------------------------------------
// Network monitor provider
// ---------------------------------------------------------------------------

/// Provides a singleton [NetworkMonitor] instance.
final networkMonitorProvider = Provider<NetworkMonitor>((ref) {
  final monitor = NetworkMonitor();
  // Fire-and-forget start — first status emitted once interfaces are checked.
  monitor.start();
  ref.onDispose(() => monitor.dispose());
  return monitor;
});

/// Stream provider for network status changes.
final networkStatusProvider = StreamProvider<NetworkStatus>((ref) {
  final monitor = ref.watch(networkMonitorProvider);
  return monitor.statusStream;
});

// ---------------------------------------------------------------------------
// Discovery service provider
// ---------------------------------------------------------------------------

/// Provides the singleton [DiscoveryService] instance.
final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final deviceId = ref.watch(deviceIdProvider);
  final deviceName = ref.watch(deviceNameProvider);

  final service = DiscoveryService(
    deviceId: deviceId,
    deviceName: deviceName,
  );

  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream provider for the list of discovered nearby devices.
///
/// The UI should watch this provider to get real-time device list updates.
/// Returns an empty list initially, then emits updates as devices are
/// found or lost.
final discoveredDevicesProvider = StreamProvider<List<DeviceModel>>((ref) {
  final service = ref.watch(discoveryServiceProvider);
  return service.devicesStream;
});

/// Provider to start/stop discovery. Read this to trigger discovery.
///
/// Usage in UI:
/// ```dart
/// ref.read(discoveryControlProvider.notifier).startAll();
/// ```
final discoveryControlProvider =
    NotifierProvider<DiscoveryControlNotifier, DiscoveryState>(
  DiscoveryControlNotifier.new,
);

/// State for the discovery control.
enum DiscoveryState {
  idle,
  discovering,
  advertising,
  advertisingAndDiscovering,
}

/// Notifier that controls discovery start/stop.
class DiscoveryControlNotifier extends Notifier<DiscoveryState> {
  @override
  DiscoveryState build() => DiscoveryState.idle;

  DiscoveryService get _service => ref.read(discoveryServiceProvider);

  /// Start advertising this device and discovering others.
  Future<void> startAll() async {
    await _service.startAdvertising();
    await _service.startDiscovery();
    state = DiscoveryState.advertisingAndDiscovering;
  }

  /// Start only discovery (browsing for other devices).
  Future<void> startDiscovery() async {
    await _service.startDiscovery();
    state = _service.isAdvertising
        ? DiscoveryState.advertisingAndDiscovering
        : DiscoveryState.discovering;
  }

  /// Start only advertising (making this device visible).
  Future<void> startAdvertising() async {
    await _service.startAdvertising();
    state = _service.isDiscovering
        ? DiscoveryState.advertisingAndDiscovering
        : DiscoveryState.advertising;
  }

  /// Stop everything.
  Future<void> stopAll() async {
    await _service.stopDiscovery();
    await _service.stopAdvertising();
    state = DiscoveryState.idle;
  }
}
