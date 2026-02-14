import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import '../constants.dart';
import 'device_model.dart';

/// Service that discovers nearby SwiftDrop devices using mDNS (Zeroconf).
///
/// Advertises this device via a `_swiftdrop._tcp` service and browses for
/// other devices doing the same. Maintains a live map of discovered devices
/// and emits updates through [devicesStream].
///
/// Lifecycle:
/// 1. Call [startAdvertising] to make this device visible.
/// 2. Call [startDiscovery] to begin scanning for nearby devices.
/// 3. Listen to [devicesStream] for real-time device list updates.
/// 4. Call [stopDiscovery] / [stopAdvertising] / [dispose] when done.
class DiscoveryService {
  DiscoveryService({
    required this.deviceId,
    required this.deviceName,
    this.transferPort = 0,
  });

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// This device's unique short ID (8-char hex).
  final String deviceId;

  /// This device's display name.
  final String deviceName;

  /// The port this device will accept transfers on (set before advertising).
  int transferPort;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// All discovered devices, keyed by device ID.
  final Map<String, DeviceModel> _devices = {};

  /// Stream controller for broadcasting device list changes.
  final StreamController<List<DeviceModel>> _devicesController =
      StreamController<List<DeviceModel>>.broadcast();

  /// The mDNS client used for browsing.
  MDnsClient? _mdnsClient;

  /// Timer for periodic re-scanning.
  Timer? _scanTimer;

  /// Timer for cleaning up timed-out devices.
  Timer? _cleanupTimer;

  /// Whether we're currently advertising.
  bool _isAdvertising = false;

  /// Whether we're currently discovering.
  bool _isDiscovering = false;

  /// The server socket used for mDNS service registration (keeps port open).
  ServerSocket? _advertiseSocket;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Stream of discovered devices. Emits the full list on every change.
  Stream<List<DeviceModel>> get devicesStream => _devicesController.stream;

  /// Current snapshot of discovered devices.
  List<DeviceModel> get devices => List.unmodifiable(_devices.values.toList());

  /// Whether discovery is currently active.
  bool get isDiscovering => _isDiscovering;

  /// Whether advertising is currently active.
  bool get isAdvertising => _isAdvertising;

  /// Start advertising this device on the network via mDNS.
  ///
  /// On most platforms, the `multicast_dns` Dart package only supports
  /// *browsing*, not *registering* services. For true service registration
  /// we rely on platform channels (Android NSD, Avahi on Linux, Bonjour on
  /// Windows). This method opens a server socket on [transferPort] so the
  /// port is reserved, and the platform-specific advertising is handled
  /// separately.
  ///
  /// For MVP, we use a simple UDP broadcast fallback alongside mDNS browsing
  /// to announce presence.
  Future<void> startAdvertising() async {
    if (_isAdvertising) return;

    // Bind a TCP server socket to reserve the transfer port.
    _advertiseSocket = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      transferPort,
      shared: true,
    );
    transferPort = _advertiseSocket!.port;

    _isAdvertising = true;

    // Start the UDP announcement broadcaster.
    _startUdpBroadcast();
  }

  /// Stop advertising this device.
  Future<void> stopAdvertising() async {
    _isAdvertising = false;
    _udpBroadcastTimer?.cancel();
    _udpBroadcastTimer = null;
    _broadcastSocket?.close();
    _broadcastSocket = null;
    await _advertiseSocket?.close();
    _advertiseSocket = null;
  }

  /// Start discovering nearby SwiftDrop devices via mDNS + UDP broadcast.
  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    _isDiscovering = true;

    // Start mDNS client for browsing.
    _mdnsClient = MDnsClient();
    await _mdnsClient!.start();

    // Start listening for UDP announcements (fallback).
    _startUdpListener();

    // Do an initial scan immediately.
    await _performMdnsScan();

    // Set up periodic re-scanning.
    _scanTimer = Timer.periodic(
      const Duration(seconds: SwiftDropConstants.discoveryIntervalSeconds),
      (_) => _performMdnsScan(),
    );

    // Set up periodic cleanup of timed-out devices.
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _cleanupTimedOutDevices(),
    );
  }

  /// Stop discovering devices.
  Future<void> stopDiscovery() async {
    _isDiscovering = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _mdnsClient?.stop();
    _mdnsClient = null;
    _stopUdpListener();
  }

  /// Remove a device from the discovered list.
  void removeDevice(String deviceId) {
    if (_devices.remove(deviceId) != null) {
      _emitDevices();
    }
  }

  /// Dispose the service and release all resources.
  Future<void> dispose() async {
    await stopDiscovery();
    await stopAdvertising();
    await _devicesController.close();
  }

  // ---------------------------------------------------------------------------
  // mDNS scanning
  // ---------------------------------------------------------------------------

  Future<void> _performMdnsScan() async {
    if (_mdnsClient == null || !_isDiscovering) return;

    try {
      // Look up PTR records for our service type.
      await for (final ptr in _mdnsClient!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(SwiftDropConstants.serviceType),
      )) {
        // For each service, look up SRV records.
        await for (final srv in _mdnsClient!.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          // Resolve the hostname to an IP address.
          await for (final ip
              in _mdnsClient!.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            _handleMdnsDevice(
              serviceName: ptr.domainName,
              host: ip.address.address,
              port: srv.port,
            );
          }
        }
      }
    } catch (e) {
      // Silently handle mDNS errors — UDP fallback covers us.
    }
  }

  void _handleMdnsDevice({
    required String serviceName,
    required String host,
    required int port,
  }) {
    // Parse device info from service name.
    // Expected format: "SwiftDrop-<shortId>._swiftdrop._tcp"
    final parts = serviceName.split('.');
    if (parts.isEmpty) return;

    final namePart = parts.first; // "SwiftDrop-abcd1234"
    final dashIdx = namePart.indexOf('-');
    if (dashIdx < 0) return;

    final id = namePart.substring(dashIdx + 1);

    // Skip our own device.
    if (id == deviceId) return;

    _addOrUpdateDevice(
      id: id,
      name: namePart,
      ipAddress: host,
      port: port,
      connectionType: ConnectionType.wifi,
    );
  }

  // ---------------------------------------------------------------------------
  // UDP broadcast fallback
  // ---------------------------------------------------------------------------

  /// Port used for UDP broadcast discovery announcements.
  static const int _udpBroadcastPort = 41234;

  /// Magic bytes to identify SwiftDrop UDP packets.
  static final List<int> _udpMagic = 'SWFTDRP'.codeUnits;

  Timer? _udpBroadcastTimer;
  RawDatagramSocket? _broadcastSocket;
  RawDatagramSocket? _listenerSocket;

  void _startUdpBroadcast() {
    _udpBroadcastTimer?.cancel();
    _udpBroadcastTimer = Timer.periodic(
      const Duration(seconds: SwiftDropConstants.discoveryIntervalSeconds),
      (_) => _sendUdpAnnouncement(),
    );
    // Send one immediately.
    _sendUdpAnnouncement();
  }

  Future<void> _sendUdpAnnouncement() async {
    if (!_isAdvertising) return;

    try {
      _broadcastSocket ??= await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      _broadcastSocket!.broadcastEnabled = true;

      // Packet format:
      //   SWFTDRP | version(1) | deviceId(8) | port(2) | deviceType(1) | nameLen(1) | name(var)
      final deviceTypeCode = DeviceType.current.code.codeUnits.first;
      final nameBytes = deviceName.codeUnits;
      final packet = <int>[
        ..._udpMagic,
        SwiftDropConstants.protocolVersion,
        ...deviceId.codeUnits.take(8),
        (transferPort >> 8) & 0xFF,
        transferPort & 0xFF,
        deviceTypeCode,
        nameBytes.length,
        ...nameBytes,
      ];

      _broadcastSocket!.send(
        packet,
        InternetAddress('255.255.255.255'),
        _udpBroadcastPort,
      );
    } catch (_) {
      // Broadcast may fail on some networks — that's OK.
    }
  }

  void _startUdpListener() {
    _stopUdpListener();
    RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _udpBroadcastPort,
      reuseAddress: true,
      reusePort: !Platform.isWindows,
    ).then((socket) {
      _listenerSocket = socket;
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            _handleUdpPacket(datagram);
          }
        }
      });
    }).catchError((_) {
      // If we can't bind the listener, mDNS is our only fallback.
    });
  }

  void _stopUdpListener() {
    _listenerSocket?.close();
    _listenerSocket = null;
  }

  void _handleUdpPacket(Datagram datagram) {
    final data = datagram.data;
    final magic = _udpMagic;

    // Minimum packet size: magic(7) + version(1) + id(8) + port(2) + type(1) + nameLen(1) = 20
    if (data.length < 20) return;

    // Verify magic bytes.
    for (var i = 0; i < magic.length; i++) {
      if (data[i] != magic[i]) return;
    }

    var offset = magic.length;
    final version = data[offset++];
    final id = String.fromCharCodes(data.sublist(offset, offset + 8));
    offset += 8;
    final port = (data[offset] << 8) | data[offset + 1];
    offset += 2;
    // final deviceTypeChar = data[offset]; // We'll parse from the ID
    offset += 1;
    final nameLen = data[offset++];
    if (offset + nameLen > data.length) return;
    final name = String.fromCharCodes(data.sublist(offset, offset + nameLen));

    // Skip our own device.
    if (id == deviceId) return;

    _addOrUpdateDevice(
      id: id,
      name: name,
      ipAddress: datagram.address.address,
      port: port,
      connectionType: ConnectionType.wifi,
      protocolVersion: version,
    );
  }

  // ---------------------------------------------------------------------------
  // Device list management
  // ---------------------------------------------------------------------------

  void _addOrUpdateDevice({
    required String id,
    required String name,
    required String ipAddress,
    required int port,
    ConnectionType connectionType = ConnectionType.wifi,
    int protocolVersion = 1,
    DeviceType? deviceType,
  }) {
    final existing = _devices[id];
    if (existing != null) {
      // Update existing device.
      existing
        ..touch()
        ..state = DeviceState.available;
      // Update IP/port if changed.
      if (existing.ipAddress != ipAddress || existing.port != port) {
        _devices[id] = existing.copyWith(
          ipAddress: ipAddress,
          port: port,
        );
      }
    } else {
      // Add new device (respect max limit).
      if (_devices.length >= SwiftDropConstants.maxVisibleDevices) return;

      _devices[id] = DeviceModel(
        id: id,
        name: name,
        ipAddress: ipAddress,
        port: port,
        deviceType: deviceType ?? DeviceType.unknown,
        connectionType: connectionType,
        protocolVersion: protocolVersion,
      );
    }
    _emitDevices();
  }

  void _cleanupTimedOutDevices() {
    var changed = false;
    final toRemove = <String>[];

    for (final entry in _devices.entries) {
      if (entry.value.isTimedOut(
        timeoutSeconds: SwiftDropConstants.deviceTimeoutSeconds,
      )) {
        if (entry.value.state != DeviceState.offline) {
          entry.value.state = DeviceState.offline;
          changed = true;
        }
        // Remove devices that have been offline for 2x the timeout.
        if (entry.value.isTimedOut(
          timeoutSeconds: SwiftDropConstants.deviceTimeoutSeconds * 2,
        )) {
          toRemove.add(entry.key);
        }
      }
    }

    for (final id in toRemove) {
      _devices.remove(id);
      changed = true;
    }

    if (changed) _emitDevices();
  }

  void _emitDevices() {
    if (!_devicesController.isClosed) {
      _devicesController.add(devices);
    }
  }
}
