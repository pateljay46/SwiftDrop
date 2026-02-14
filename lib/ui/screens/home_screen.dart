import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controller/transfer_providers.dart';
import '../../core/discovery/discovery_providers.dart';
import '../../core/transport/transport_service.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

/// Home screen — the main entry point of SwiftDrop.
///
/// Presents two large action cards (Send / Receive) in a clean layout
/// similar to popular file-sharing apps. Below the cards, a quick
/// glance at active transfers is shown.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Ensure discovery is running so devices are found when user
    // navigates into Send or Receive.
    Future.microtask(() {
      ref.read(discoveryControlProvider.notifier).startAll();
      ref.read(receiveListenerProvider.notifier).startListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    final receiveState = ref.watch(receiveListenerProvider);
    final transfersAsync = ref.watch(transferListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SwiftDrop'),
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: receiveState.isListening
                  ? 'Online — Ready to receive'
                  : 'Offline',
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: receiveState.isListening
                      ? SwiftDropTheme.successColor
                      : SwiftDropTheme.errorColor,
                  boxShadow: [
                    if (receiveState.isListening)
                      BoxShadow(
                        color: SwiftDropTheme.successColor
                            .withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero Section ──
            const SizedBox(height: 8),
            Text(
              'Share files instantly',
              style: SwiftDropTheme.heading1.copyWith(fontSize: 26),
            ),
            const SizedBox(height: 6),
            Text(
              'No setup needed — just pick, tap, and send.',
              style: SwiftDropTheme.caption.copyWith(fontSize: 14),
            ),

            const SizedBox(height: 28),

            // ── Send & Receive Cards ──
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.upload_rounded,
                    label: 'Send',
                    description: 'Pick files and share\nwith nearby devices',
                    color: SwiftDropTheme.primaryColor,
                    onTap: () => _navigateToSend(context),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.download_rounded,
                    label: 'Receive',
                    description: 'Wait for files from\nnearby devices',
                    color: SwiftDropTheme.secondaryColor,
                    onTap: () => _navigateToReceive(context),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ── Nearby Devices Quick Count ──
            _NearbyDevicesBanner(
              onTap: () => _navigateToSend(context),
            ),

            const SizedBox(height: 28),

            // ── Active Transfers Summary ──
            transfersAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (transfers) {
                final active =
                    transfers.where((t) => t.isActive).toList();
                if (active.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Active Transfers'),
                    const SizedBox(height: 4),
                    ...active.map(
                      (record) => TransferTile(
                        record: record,
                        onCancel: record.isActive
                            ? () => ref
                                .read(transferActionsProvider.notifier)
                                .cancel(record.id)
                            : null,
                        onRemove: record.isFinished
                            ? () => ref
                                .read(transferActionsProvider.notifier)
                                .remove(record.id)
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToSend(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SendScreen()),
    );
  }

  void _navigateToReceive(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReceiveScreen()),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// Large tappable action card for Send / Receive.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: color.withValues(alpha: 0.15),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                label,
                style: SwiftDropTheme.heading2.copyWith(
                  color: color,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: SwiftDropTheme.caption.copyWith(
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner showing how many nearby devices are discovered.
class _NearbyDevicesBanner extends ConsumerWidget {
  const _NearbyDevicesBanner({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(discoveredDevicesProvider);

    return devicesAsync.when(
      loading: () => _buildBanner(
        context,
        icon: Icons.radar_rounded,
        label: 'Scanning for nearby devices...',
        trailing: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => _buildBanner(
        context,
        icon: Icons.wifi_off_rounded,
        label: 'Discovery unavailable',
        trailing: const Icon(Icons.error_outline,
            size: 18, color: SwiftDropTheme.errorColor),
      ),
      data: (devices) => _buildBanner(
        context,
        icon: devices.isEmpty
            ? Icons.radar_rounded
            : Icons.devices_rounded,
        label: devices.isEmpty
            ? 'No devices nearby'
            : '${devices.length} device${devices.length != 1 ? 's' : ''} nearby',
        trailing: devices.isNotEmpty
            ? const Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: SwiftDropTheme.mutedColor)
            : null,
        tappable: devices.isNotEmpty,
      ),
    );
  }

  Widget _buildBanner(
    BuildContext context, {
    required IconData icon,
    required String label,
    Widget? trailing,
    bool tappable = false,
  }) {
    return Material(
      color: SwiftDropTheme.cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: tappable ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: SwiftDropTheme.primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: SwiftDropTheme.body.copyWith(fontSize: 14),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}
