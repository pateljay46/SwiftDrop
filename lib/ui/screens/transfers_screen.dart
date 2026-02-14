import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controller/transfer_providers.dart';
import '../../core/transport/transport_service.dart';
import '../../storage/models/transfer_history_entry.dart';
import '../../storage/storage_providers.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_service.dart';
import '../widgets/widgets.dart';

/// Transfers screen — shows active and completed transfers.
///
/// Active transfers stream in real-time with progress bars.
/// Completed transfers are loaded from Hive history.
class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  /// Tracks which transfer IDs we've already triggered haptics for.
  final _hapticTriggered = <String>{};

  @override
  Widget build(BuildContext context) {
    final transfersAsync = ref.watch(transferListProvider);
    final history = ref.watch(transferHistoryProvider);

    // Listen for transfer completions and trigger haptic feedback.
    ref.listen(transferUpdatesProvider, (_, next) {
      next.whenData((record) {
        if (_hapticTriggered.contains(record.id)) return;
        if (record.state == TransferState.completed) {
          _hapticTriggered.add(record.id);
          HapticService.heavyTap();
        } else if (record.state == TransferState.failed) {
          _hapticTriggered.add(record.id);
          HapticService.error();
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
        actions: [
          if (history.isNotEmpty)
            TextButton.icon(
              onPressed: () => _confirmClearHistory(context),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text('Clear'),
            ),
        ],
      ),
      body: transfersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Error',
          subtitle: error.toString(),
        ),
        data: (activeTransfers) {
          if (activeTransfers.isEmpty && history.isEmpty) {
            return const EmptyState(
              icon: Icons.swap_horiz_rounded,
              title: 'No Transfers',
              subtitle: 'Send or receive a file to see it here.',
            );
          }

          return CustomScrollView(
            slivers: [
              // Active transfers section
              if (activeTransfers.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: SectionHeader(title: 'Active'),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final record = activeTransfers[index];
                      return TransferTile(
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
                      );
                    },
                    childCount: activeTransfers.length,
                  ),
                ),
              ],

              // History section
              if (history.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: SectionHeader(title: 'History'),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final entry = history[index];
                      return _HistoryTile(
                        entry: entry,
                        onRemove: () {
                          ref
                              .read(transferHistoryProvider.notifier)
                              .remove(entry.transferId);
                        },
                      );
                    },
                    childCount: history.length,
                  ),
                ),
              ],

              // Bottom padding
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmClearHistory(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear History'),
        content:
            const Text('Remove all transfer history? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(transferHistoryProvider.notifier).clearAll();
              Navigator.pop(dialogContext);
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: SwiftDropTheme.errorColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact tile for a completed transfer from history.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    this.onRemove,
  });

  final TransferHistoryEntry entry;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final bool isOutgoing = entry.isOutgoing;
    final bool isSuccess = entry.isSuccess;

    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (isSuccess
                    ? SwiftDropTheme.successColor
                    : SwiftDropTheme.errorColor)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isSuccess
                ? (isOutgoing
                    ? Icons.upload_rounded
                    : Icons.download_rounded)
                : Icons.error_outline_rounded,
            color: isSuccess
                ? SwiftDropTheme.successColor
                : SwiftDropTheme.errorColor,
            size: 20,
          ),
        ),
        title: Text(
          entry.fileName,
          style: SwiftDropTheme.heading3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${isOutgoing ? "To" : "From"} ${entry.deviceName}  •  '
          '${entry.formattedSize}',
          style: SwiftDropTheme.caption,
        ),
        trailing: onRemove != null
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: SwiftDropTheme.mutedColor,
                onPressed: onRemove,
              )
            : null,
      ),
    );
  }
}
