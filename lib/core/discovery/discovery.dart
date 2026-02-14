/// Discovery layer for SwiftDrop.
///
/// Handles mDNS service advertisement and browsing to find nearby devices
/// on the same WiFi/LAN network. Includes a UDP broadcast fallback for
/// platforms where mDNS is unreliable.
library;

export 'device_model.dart';
export 'discovery_providers.dart';
export 'discovery_service.dart';
export 'network_monitor.dart';
