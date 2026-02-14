import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/permission_service.dart';
import '../../core/platform/platform_providers.dart';
import '../theme/app_theme.dart';

/// A screen shown when required runtime permissions have not been granted.
///
/// On Android, this prompts the user to grant nearby-devices, storage,
/// and notification permissions. On desktop platforms this screen is
/// never shown (permissions are not applicable).
class PermissionGateScreen extends ConsumerWidget {
  const PermissionGateScreen({required this.onGranted, super.key});

  /// Called when all required permissions are granted so the parent
  /// can switch to the main app shell.
  final VoidCallback onGranted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permState = ref.watch(permissionStateProvider);

    // If already granted, trigger callback on next frame.
    if (permState.allGranted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onGranted());
      return const SizedBox.shrink();
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              const Spacer(),
              Icon(
                Icons.shield_rounded,
                size: 80,
                color: SwiftDropTheme.primaryColor.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 24),
              Text(
                'Permissions Required',
                style: SwiftDropTheme.heading2.copyWith(
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'SwiftDrop needs a few permissions to discover '
                'nearby devices and transfer files securely.',
                style: SwiftDropTheme.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Permission rows.
              _PermissionRow(
                icon: Icons.wifi_find_rounded,
                label: 'Nearby Devices',
                description: 'Discover devices on your network',
                outcome: permState.nearbyDevices,
              ),
              const SizedBox(height: 12),
              _PermissionRow(
                icon: Icons.folder_rounded,
                label: 'Storage',
                description: 'Access files to send and save',
                outcome: permState.storage,
              ),
              const SizedBox(height: 12),
              _PermissionRow(
                icon: Icons.notifications_rounded,
                label: 'Notifications',
                description: 'Show transfer progress',
                outcome: permState.notification,
              ),

              const Spacer(),

              // Grant all button.
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () async {
                    await ref
                        .read(permissionStateProvider.notifier)
                        .requestAll();

                    final updated = ref.read(permissionStateProvider);
                    if (updated.allGranted) {
                      onGranted();
                    }
                  },
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Grant Permissions'),
                  style: FilledButton.styleFrom(
                    backgroundColor: SwiftDropTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              if (permState.hasPermanentlyDenied) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    ref
                        .read(permissionStateProvider.notifier)
                        .openSettings();
                  },
                  child: const Text(
                    'Open App Settings',
                    style: TextStyle(color: SwiftDropTheme.mutedColor),
                  ),
                ),
              ],

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single row showing a permission status.
class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.outcome,
  });

  final IconData icon;
  final String label;
  final String description;
  final PermissionOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final IconData statusIcon;

    switch (outcome) {
      case PermissionOutcome.granted:
      case PermissionOutcome.notApplicable:
        statusColor = SwiftDropTheme.successColor;
        statusIcon = Icons.check_circle_rounded;
      case PermissionOutcome.denied:
        statusColor = SwiftDropTheme.warningColor;
        statusIcon = Icons.radio_button_unchecked_rounded;
      case PermissionOutcome.permanentlyDenied:
        statusColor = SwiftDropTheme.errorColor;
        statusIcon = Icons.block_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SwiftDropTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SwiftDropTheme.dividerColor,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28, color: SwiftDropTheme.primaryColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SwiftDropTheme.body),
                Text(
                  description,
                  style: SwiftDropTheme.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(statusIcon, color: statusColor, size: 22),
        ],
      ),
    );
  }
}
