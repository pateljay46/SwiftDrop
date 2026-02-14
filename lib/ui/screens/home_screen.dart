import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controller/transfer_providers.dart';
import '../../core/discovery/device_model.dart';
import '../../core/discovery/discovery_providers.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_service.dart';
import '../widgets/widgets.dart';

/// Home screen — device discovery & quick-send.
///
/// Shows nearby discovered devices. Tap a device to pick a file and send.
/// The app bar has a scanning indicator, and a toggle for the receive
/// listener.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Start discovery automatically.
    Future.microtask(() {
      ref.read(discoveryControlProvider.notifier).startAll();
      ref.read(receiveListenerProvider.notifier).startListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(discoveredDevicesProvider);
    final discoveryState = ref.watch(discoveryControlProvider);
    final receiveState = ref.watch(receiveListenerProvider);
    final isScanning =
        discoveryState == DiscoveryState.discovering ||
        discoveryState == DiscoveryState.advertisingAndDiscovering;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SwiftDrop'),
        actions: [
          // Scanning indicator
          if (isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: ScanningIndicator(),
            ),

          // Receive toggle
          Tooltip(
            message: receiveState.isListening
                ? 'Receiving on port ${receiveState.port}'
                : 'Not receiving',
            child: IconButton(
              icon: Icon(
                receiveState.isListening
                    ? Icons.wifi_tethering_rounded
                    : Icons.wifi_tethering_off_rounded,
                color: receiveState.isListening
                    ? SwiftDropTheme.successColor
                    : SwiftDropTheme.mutedColor,
              ),
              onPressed: () {
                final notifier = ref.read(receiveListenerProvider.notifier);
                if (receiveState.isListening) {
                  notifier.stopListening();
                } else {
                  notifier.startListening();
                }
              },
            ),
          ),

          // Refresh discovery
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rescan',
            onPressed: () {
              ref.read(discoveryControlProvider.notifier).stopAll();
              ref.read(discoveryControlProvider.notifier).startAll();
            },
          ),

          const SizedBox(width: 4),
        ],
      ),
      body: devicesAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Scanning for nearby devices...',
                style: SwiftDropTheme.caption,
              ),
            ],
          ),
        ),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Discovery Error',
          subtitle: error.toString(),
          actionLabel: 'Retry',
          onAction: () {
            ref.read(discoveryControlProvider.notifier).startAll();
          },
        ),
        data: (devices) {
          if (devices.isEmpty) {
            return const EmptyState(
              icon: Icons.radar_rounded,
              title: 'No Devices Found',
              subtitle:
                  'Make sure other devices are on the same network\n'
                  'and running SwiftDrop.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 100),
            itemCount: devices.length + 1, // +1 for header
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    '${devices.length} device${devices.length != 1 ? 's' : ''} nearby',
                    style: SwiftDropTheme.caption.copyWith(fontSize: 13),
                  ),
                );
              }

              final device = devices[index - 1];
              return DeviceCard(
                device: device,
                onTap: () => _sendToDevice(device),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _sendToDevice(DeviceModel device) async {
    unawaited(HapticService.lightTap());
    final actions = ref.read(transferActionsProvider.notifier);
    final transferId = await actions.pickAndSend(device);

    if (!mounted) return;

    if (transferId != null) {
      unawaited(HapticService.mediumTap());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Transfer started to ${device.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Check for errors from the actions state.
    final actionsState = ref.read(transferActionsProvider);
    if (actionsState.lastError != null) {
      unawaited(HapticService.error());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(actionsState.lastError!)),
            ],
          ),
          backgroundColor: SwiftDropTheme.errorColor,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }
}
