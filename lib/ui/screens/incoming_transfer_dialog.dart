import 'package:flutter/material.dart';

import '../../core/controller/transfer_record.dart';
import '../../core/transport/protocol_messages.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_service.dart';

/// Dialog shown when an incoming file transfer arrives.
///
/// Displays the file name, size, sender info, and Accept / Decline buttons.
/// Returns `true` if the user accepts, `false` if declined.
class IncomingTransferDialog extends StatelessWidget {
  const IncomingTransferDialog({
    required this.record,
    required this.meta,
    super.key,
  });

  final TransferRecord record;
  final FileMetaMessage meta;

  /// Shows the dialog and returns `true` (accepted) or `false` (declined).
  static Future<bool> show({
    required BuildContext context,
    required TransferRecord record,
    required FileMetaMessage meta,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => IncomingTransferDialog(record: record, meta: meta),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: SwiftDropTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.download_rounded,
              color: SwiftDropTheme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Incoming File'),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SwiftDropTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // File name
                Row(
                  children: [
                    Icon(
                      _fileIcon(meta.fileName),
                      size: 20,
                      color: SwiftDropTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        meta.fileName,
                        style: SwiftDropTheme.heading3,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Size
                _DetailRow(
                  icon: Icons.data_usage_rounded,
                  label: 'Size',
                  value: _formatBytes(meta.fileSize),
                ),

                const SizedBox(height: 6),

                // Chunks
                _DetailRow(
                  icon: Icons.view_module_rounded,
                  label: 'Chunks',
                  value: '${meta.chunkCount}',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Sender info
          Row(
            children: [
              const Icon(
                Icons.person_rounded,
                size: 18,
                color: SwiftDropTheme.mutedColor,
              ),
              const SizedBox(width: 8),
              Text(
                'From ${record.device.name}',
                style: SwiftDropTheme.caption.copyWith(fontSize: 13),
              ),
            ],
          ),

          if (record.device.ipAddress != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.wifi_rounded,
                  size: 18,
                  color: SwiftDropTheme.mutedColor,
                ),
                const SizedBox(width: 8),
                Text(
                  record.device.ipAddress!,
                  style: SwiftDropTheme.mono,
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            HapticService.selectionClick();
            Navigator.of(context).pop(false);
          },
          child: const Text(
            'Decline',
            style: TextStyle(color: SwiftDropTheme.errorColor),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            HapticService.mediumTap();
            Navigator.of(context).pop(true);
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Accept'),
        ),
      ],
    );
  }

  /// Returns an appropriate icon for the file extension.
  static IconData _fileIcon(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    return switch (ext) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' =>
        Icons.image_rounded,
      'mp4' || 'avi' || 'mkv' || 'mov' || 'wmv' =>
        Icons.movie_rounded,
      'mp3' || 'wav' || 'flac' || 'aac' || 'ogg' =>
        Icons.music_note_rounded,
      'pdf' => Icons.picture_as_pdf_rounded,
      'doc' || 'docx' || 'txt' || 'rtf' =>
        Icons.description_rounded,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' =>
        Icons.folder_zip_rounded,
      'apk' || 'exe' || 'msi' || 'deb' =>
        Icons.apps_rounded,
      _ => Icons.insert_drive_file_rounded,
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: SwiftDropTheme.mutedColor),
        const SizedBox(width: 6),
        Text(label, style: SwiftDropTheme.caption),
        const Spacer(),
        Text(value, style: SwiftDropTheme.mono),
      ],
    );
  }
}
