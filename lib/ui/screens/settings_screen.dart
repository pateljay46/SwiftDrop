import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_providers.dart';
import '../../storage/storage_providers.dart';
import '../theme/app_theme.dart';

/// Settings screen — user preferences and device management.
///
/// Allows configuring device name, save directory, auto-accept,
/// concurrent transfers, trusted devices, and about info.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final trustedDevices = ref.watch(trustedDevicesProvider);
    final deviceId = ref.watch(deviceIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          // ── Device Identity ──
          const _SectionTitle('Device'),
          _InfoTile(
            icon: Icons.fingerprint_rounded,
            title: 'Device ID',
            subtitle: deviceId,
          ),
          _EditableTile(
            icon: Icons.badge_rounded,
            title: 'Device Name',
            value: settings.deviceName ?? 'System default',
            onEdit: () => _editDeviceName(context, ref, settings.deviceName),
          ),

          const Divider(),

          // ── Transfer Settings ──
          const _SectionTitle('Transfer'),
          _EditableTile(
            icon: Icons.folder_rounded,
            title: 'Save Directory',
            value: settings.saveDirectory ?? 'Downloads (default)',
            onEdit: () => _editSaveDir(context, ref),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.verified_user_rounded),
            title: const Text('Auto-accept from trusted'),
            subtitle: const Text('Skip confirmation for trusted devices'),
            value: settings.autoAcceptFromTrusted,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).update(
                    (s) => s.copyWith(autoAcceptFromTrusted: value),
                  );
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_rounded),
            title: const Text('Notifications'),
            subtitle: const Text('Show notification on incoming transfer'),
            value: settings.showNotifications,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).update(
                    (s) => s.copyWith(showNotifications: value),
                  );
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.history_rounded),
            title: const Text('Keep history'),
            subtitle: const Text('Save completed transfers to history'),
            value: settings.keepTransferHistory,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).update(
                    (s) => s.copyWith(keepTransferHistory: value),
                  );
            },
          ),
          ListTile(
            leading: const Icon(Icons.speed_rounded),
            title: const Text('Max concurrent transfers'),
            subtitle: Text('${settings.maxConcurrentTransfers}'),
            trailing: DropdownButton<int>(
              value: settings.maxConcurrentTransfers,
              underline: const SizedBox.shrink(),
              items: [1, 2, 3, 4, 5]
                  .map(
                    (v) => DropdownMenuItem(value: v, child: Text('$v')),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                ref.read(settingsProvider.notifier).update(
                      (s) => s.copyWith(maxConcurrentTransfers: value),
                    );
              },
            ),
          ),

          const Divider(),

          // ── Trusted Devices ──
          const _SectionTitle('Trusted Devices'),
          if (trustedDevices.isEmpty)
            const ListTile(
              leading: Icon(Icons.device_unknown_rounded),
              title: Text('No trusted devices'),
              subtitle: Text('Devices are trusted after successful pairing'),
            )
          else
            ...trustedDevices.map(
              (device) => ListTile(
                leading: const Icon(Icons.devices_rounded),
                title: Text(device.deviceName),
                subtitle: Text(
                  '${device.deviceType} • ID: ${device.deviceId}',
                  style: SwiftDropTheme.caption,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Auto-accept',
                      child: Switch(
                        value: device.autoAccept,
                        onChanged: (_) {
                          ref
                              .read(trustedDevicesProvider.notifier)
                              .toggleAutoAccept(device.deviceId);
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      color: SwiftDropTheme.errorColor,
                      tooltip: 'Remove trust',
                      onPressed: () {
                        ref
                            .read(trustedDevicesProvider.notifier)
                            .untrust(device.deviceId);
                      },
                    ),
                  ],
                ),
              ),
            ),

          const Divider(),

          // ── About ──
          const _SectionTitle('About'),
          const _InfoTile(
            icon: Icons.info_outline_rounded,
            title: 'SwiftDrop',
            subtitle: 'v0.1.0 — Zero-config file sharing',
          ),
          const _InfoTile(
            icon: Icons.shield_rounded,
            title: 'Encryption',
            subtitle: 'AES-256-GCM + ECDH P-256',
          ),

          const SizedBox(height: 24),

          // Reset
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => _confirmReset(context, ref),
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Reset to Defaults'),
              style: OutlinedButton.styleFrom(
                foregroundColor: SwiftDropTheme.errorColor,
                side: const BorderSide(color: SwiftDropTheme.errorColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  void _editDeviceName(
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) {
    final controller = TextEditingController(text: current ?? '');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter device name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              ref.read(settingsProvider.notifier).update(
                    (s) => s.copyWith(
                      deviceName: name.isEmpty ? null : name,
                    ),
                  );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editSaveDir(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(
      text: ref.read(settingsProvider).saveDirectory ?? '',
    );
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Directory'),
        content: TextField(
          controller: controller,
          decoration:
              const InputDecoration(hintText: 'Leave empty for default'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final dir = controller.text.trim();
              ref.read(settingsProvider.notifier).update(
                    (s) => s.copyWith(
                      saveDirectory: dir.isEmpty ? null : dir,
                    ),
                  );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text('Reset all settings to defaults?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(settingsProvider.notifier).reset();
              Navigator.pop(context);
            },
            child: const Text(
              'Reset',
              style: TextStyle(color: SwiftDropTheme.errorColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        title.toUpperCase(),
        style: SwiftDropTheme.caption.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, style: SwiftDropTheme.caption),
    );
  }
}

class _EditableTile extends StatelessWidget {
  const _EditableTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onEdit,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value, style: SwiftDropTheme.caption),
      trailing: IconButton(
        icon: const Icon(Icons.edit_rounded, size: 18),
        color: SwiftDropTheme.primaryColor,
        onPressed: onEdit,
      ),
    );
  }
}
