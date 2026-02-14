import 'package:flutter/material.dart';

import '../../core/controller/transfer_record.dart';
import '../../core/transport/transport_service.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_service.dart';

/// A list tile showing the status of a single file transfer.
///
/// Displays file name, device name, progress bar, size info, and
/// action buttons (cancel / remove) depending on state.
class TransferTile extends StatelessWidget {
  const TransferTile({
    required this.record,
    this.onCancel,
    this.onRemove,
    this.onRetry,
    super.key,
  });

  final TransferRecord record;
  final VoidCallback? onCancel;
  final VoidCallback? onRemove;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: icon + file name + actions
            Row(
              children: [
                _DirectionIcon(direction: record.direction),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.fileName,
                        style: SwiftDropTheme.heading3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${record.direction == TransferDirection.outgoing ? "To" : "From"} ${record.device.name}',
                        style: SwiftDropTheme.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _StatusChip(state: record.state),
              ],
            ),

            const SizedBox(height: 12),

            // Progress bar (only when transferring)
            if (record.isActive) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: record.progress,
                  minHeight: 6,
                  backgroundColor: SwiftDropTheme.dividerColor,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _progressColor(record.state),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Error message (only for failed transfers)
            if (record.state == TransferState.failed &&
                record.errorMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SwiftDropTheme.errorColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: SwiftDropTheme.errorColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: SwiftDropTheme.errorColor.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        record.errorMessage!,
                        style: SwiftDropTheme.caption.copyWith(
                          color: SwiftDropTheme.errorColor.withValues(
                            alpha: 0.9,
                          ),
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Bottom row: size info + actions
            Row(
              children: [
                Text(
                  _sizeText(record),
                  style: SwiftDropTheme.mono,
                ),
                const Spacer(),

                // Cancel button for active transfers
                if (record.isActive && onCancel != null)
                  _ActionButton(
                    icon: Icons.close_rounded,
                    label: 'Cancel',
                    color: SwiftDropTheme.errorColor,
                    onPressed: () {
                      HapticService.selectionClick();
                      onCancel!();
                    },
                  ),

                // Retry button for failed transfers
                if (record.state == TransferState.failed && onRetry != null) ...[
                  _ActionButton(
                    icon: Icons.refresh_rounded,
                    label: 'Retry',
                    color: SwiftDropTheme.warningColor,
                    onPressed: () {
                      HapticService.mediumTap();
                      onRetry!();
                    },
                  ),
                  const SizedBox(width: 8),
                ],

                // Remove button for finished transfers
                if (record.isFinished && onRemove != null)
                  _ActionButton(
                    icon: Icons.delete_outline_rounded,
                    label: 'Remove',
                    color: SwiftDropTheme.mutedColor,
                    onPressed: () {
                      HapticService.selectionClick();
                      onRemove!();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _sizeText(TransferRecord r) {
    if (r.fileSize == 0) return '';
    final total = _formatBytes(r.fileSize);
    if (r.isActive) {
      final transferred = _formatBytes(r.bytesTransferred);
      final pct = (r.progress * 100).toStringAsFixed(0);
      return '$transferred / $total  ($pct%)';
    }
    return total;
  }

  Color _progressColor(TransferState state) {
    return switch (state) {
      TransferState.verifying => SwiftDropTheme.secondaryColor,
      TransferState.handshaking ||
      TransferState.awaitingAccept =>
        SwiftDropTheme.warningColor,
      _ => SwiftDropTheme.primaryColor,
    };
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Direction arrow icon (upload / download).
class _DirectionIcon extends StatelessWidget {
  const _DirectionIcon({required this.direction});

  final TransferDirection direction;

  @override
  Widget build(BuildContext context) {
    final isOutgoing = direction == TransferDirection.outgoing;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: (isOutgoing ? SwiftDropTheme.primaryColor : SwiftDropTheme.successColor)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        isOutgoing ? Icons.upload_rounded : Icons.download_rounded,
        color: isOutgoing ? SwiftDropTheme.primaryColor : SwiftDropTheme.successColor,
        size: 22,
      ),
    );
  }
}

/// Small coloured chip showing transfer state.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});

  final TransferState state;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      TransferState.idle => (SwiftDropTheme.mutedColor, 'Queued'),
      TransferState.handshaking => (SwiftDropTheme.warningColor, 'Connecting'),
      TransferState.awaitingAccept => (SwiftDropTheme.warningColor, 'Waiting'),
      TransferState.transferring => (SwiftDropTheme.primaryColor, 'Sending'),
      TransferState.verifying => (SwiftDropTheme.secondaryColor, 'Verifying'),
      TransferState.completed => (SwiftDropTheme.successColor, 'Done'),
      TransferState.cancelled => (SwiftDropTheme.mutedColor, 'Cancelled'),
      TransferState.failed => (SwiftDropTheme.errorColor, 'Failed'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Small tappable text button used for cancel / remove / retry.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
