import 'package:flutter/material.dart';

import '../../core/discovery/device_model.dart';
import '../theme/app_theme.dart';

/// A card representing a discovered nearby device.
///
/// Shows the device name, type icon, connection info, and state badge.
/// Tapping triggers [onTap] (typically opens file picker to send).
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    required this.device,
    this.onTap,
    super.key,
  });

  final DeviceModel device;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Device icon
              _DeviceIcon(deviceType: device.deviceType),
              const SizedBox(width: 16),

              // Name & details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: SwiftDropTheme.heading3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          _connectionIcon(device.connectionType),
                          size: 14,
                          color: SwiftDropTheme.mutedColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          device.ipAddress ?? device.connectionType.name,
                          style: SwiftDropTheme.caption,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // State badge
              _StateBadge(state: device.state),

              const SizedBox(width: 8),
              const Icon(
                Icons.send_rounded,
                color: SwiftDropTheme.primaryColor,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _connectionIcon(ConnectionType type) {
    return switch (type) {
      ConnectionType.wifi => Icons.wifi_rounded,
      ConnectionType.bluetooth => Icons.bluetooth_rounded,
      ConnectionType.webrtc => Icons.language_rounded,
    };
  }
}

/// Circular icon with platform-specific device glyph.
class _DeviceIcon extends StatelessWidget {
  const _DeviceIcon({required this.deviceType});

  final DeviceType deviceType;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: SwiftDropTheme.primaryColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _iconFor(deviceType),
        color: SwiftDropTheme.primaryColor,
        size: 24,
      ),
    );
  }

  static IconData _iconFor(DeviceType type) {
    return switch (type) {
      DeviceType.android => Icons.phone_android_rounded,
      DeviceType.windows => Icons.desktop_windows_rounded,
      DeviceType.linux => Icons.computer_rounded,
      DeviceType.ios => Icons.phone_iphone_rounded,
      DeviceType.unknown => Icons.devices_other_rounded,
    };
  }
}

/// Small coloured badge showing device availability state.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final DeviceState state;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      DeviceState.available => (SwiftDropTheme.successColor, 'Ready'),
      DeviceState.busy => (SwiftDropTheme.warningColor, 'Busy'),
      DeviceState.offline => (SwiftDropTheme.errorColor, 'Offline'),
      DeviceState.trusted => (SwiftDropTheme.secondaryColor, 'Trusted'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
