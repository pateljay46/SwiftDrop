import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controller/transfer_providers.dart';
import '../../core/controller/transfer_record.dart';
import '../../core/transport/transport_service.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// Receive screen — shows a waiting state while this device is
/// discoverable and ready to accept incoming files.
///
/// Displays a radar-style animation, the device's visibility status,
/// and any active incoming transfers. This mirrors the "Receive"
/// flow in popular file-sharing apps.
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Ensure we're listening for incoming transfers.
    Future.microtask(() {
      final notifier = ref.read(receiveListenerProvider.notifier);
      final state = ref.read(receiveListenerProvider);
      if (!state.isListening) {
        notifier.startListening();
      }
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receiveState = ref.watch(receiveListenerProvider);
    final transfersAsync = ref.watch(transferListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive'),
        actions: [
          // Status indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: receiveState.isListening
                        ? SwiftDropTheme.successColor
                        : SwiftDropTheme.errorColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  receiveState.isListening ? 'Ready' : 'Offline',
                  style: SwiftDropTheme.caption.copyWith(
                    color: receiveState.isListening
                        ? SwiftDropTheme.successColor
                        : SwiftDropTheme.errorColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Radar Animation Area ──
          Expanded(
            flex: 3,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Radar / pulse animation
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: AnimatedBuilder(
                      animation: _radarController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _RadarPainter(
                            progress: _radarController.value,
                            isActive: receiveState.isListening,
                          ),
                          child: Center(
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (receiveState.isListening
                                        ? SwiftDropTheme.secondaryColor
                                        : SwiftDropTheme.mutedColor)
                                    .withValues(alpha: 0.15),
                              ),
                              child: Icon(
                                receiveState.isListening
                                    ? Icons.wifi_tethering_rounded
                                    : Icons.wifi_tethering_off_rounded,
                                size: 36,
                                color: receiveState.isListening
                                    ? SwiftDropTheme.secondaryColor
                                    : SwiftDropTheme.mutedColor,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Status text
                  Text(
                    receiveState.isListening
                        ? 'Waiting for files...'
                        : 'Not receiving',
                    style: SwiftDropTheme.heading2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    receiveState.isListening
                        ? 'Your device is visible to others\n'
                            'on the same Wi-Fi network.'
                        : 'Tap the button below to start receiving.',
                    style: SwiftDropTheme.caption.copyWith(fontSize: 13),
                    textAlign: TextAlign.center,
                  ),

                  if (receiveState.isListening &&
                      receiveState.port != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: SwiftDropTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Listening on port ${receiveState.port}',
                        style: SwiftDropTheme.mono,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Incoming Transfers ──
          Expanded(
            flex: 2,
            child: transfersAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (transfers) {
                final incoming = transfers
                    .where((t) =>
                        t.direction == TransferDirection.incoming)
                    .toList();

                if (incoming.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_rounded,
                          size: 40,
                          color: SwiftDropTheme.mutedColor
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No incoming transfers yet',
                          style: SwiftDropTheme.caption
                              .copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 16, 4),
                      child: SectionHeader(title: 'Incoming'),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 20),
                        itemCount: incoming.length,
                        itemBuilder: (context, index) {
                          final record = incoming[index];
                          return TransferTile(
                            record: record,
                            onCancel: record.isActive
                                ? () => ref
                                    .read(
                                        transferActionsProvider.notifier)
                                    .cancel(record.id)
                                : null,
                            onRemove: record.isFinished
                                ? () => ref
                                    .read(
                                        transferActionsProvider.notifier)
                                    .remove(record.id)
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // ── Toggle Receive Button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: receiveState.isListening
                  ? OutlinedButton.icon(
                      onPressed: () {
                        ref
                            .read(receiveListenerProvider.notifier)
                            .stopListening();
                      },
                      icon: const Icon(
                          Icons.stop_circle_outlined, size: 20),
                      label: const Text('Stop Receiving'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SwiftDropTheme.errorColor,
                        side: const BorderSide(
                            color: SwiftDropTheme.errorColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () {
                        ref
                            .read(receiveListenerProvider.notifier)
                            .startListening();
                      },
                      icon: const Icon(
                          Icons.wifi_tethering_rounded, size: 20),
                      label: const Text('Start Receiving'),
                      style: FilledButton.styleFrom(
                        backgroundColor: SwiftDropTheme.secondaryColor,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Radar painter
// ---------------------------------------------------------------------------

/// Custom painter that draws concentric pulse rings radiating outward,
/// creating a radar/sonar visual effect.
class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.progress,
    required this.isActive,
  });

  final double progress;
  final bool isActive;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final color =
        isActive ? SwiftDropTheme.secondaryColor : SwiftDropTheme.mutedColor;

    // Draw 3 concentric rings at different phases.
    for (int i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final radius = maxRadius * phase;
      final opacity = (1.0 - phase) * 0.35;

      if (opacity > 0.01) {
        final paint = Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

        canvas.drawCircle(center, radius, paint);
      }
    }

    // Draw a faint grid cross.
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;

    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      gridPaint,
    );

    // Draw a radar sweep line.
    if (isActive) {
      final sweepAngle = progress * 2 * math.pi;
      final sweepEnd = Offset(
        center.dx + maxRadius * math.cos(sweepAngle),
        center.dy + maxRadius * math.sin(sweepAngle),
      );

      final sweepPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            color.withValues(alpha: 0.3),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: center, radius: maxRadius),
        )
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      canvas.drawLine(center, sweepEnd, sweepPaint);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      progress != oldDelegate.progress || isActive != oldDelegate.isActive;
}
