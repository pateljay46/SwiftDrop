import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controller/transfer_providers.dart';
import '../../core/discovery/device_model.dart';
import '../../core/discovery/discovery_providers.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_service.dart';
import '../widgets/widgets.dart';

/// Send screen — pick files first, then choose a nearby device.
///
/// Flow:
///  1. User picks one or more files via the system file picker.
///  2. The screen shows discovered nearby devices.
///  3. User taps a device → transfer starts immediately.
///
/// This mirrors the familiar Send flow in ShareIt / Xender.
class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  /// Selected file (null until user picks one).
  File? _selectedFile;
  String? _selectedFileName;
  int? _selectedFileSize;

  /// Whether the file picker is currently showing.
  bool _isPicking = false;

  /// Whether a transfer is currently in progress.
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Open file picker immediately when screen opens.
    Future.microtask(_pickFile);
  }

  Future<void> _pickFile() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) {
        // User cancelled — go back.
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final path = result.files.single.path;
      if (path == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      setState(() {
        _selectedFile = File(path);
        _selectedFileName = result.files.single.name;
        _selectedFileSize = result.files.single.size;
        _isPicking = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _sendToDevice(DeviceModel device) async {
    if (_selectedFile == null || _isSending) return;
    setState(() => _isSending = true);

    unawaited(HapticService.lightTap());

    try {
      final actions = ref.read(transferActionsProvider.notifier);
      final transferId =
          await actions.sendFile(device, _selectedFile!);

      if (!mounted) return;

      if (transferId != null) {
        unawaited(HapticService.mediumTap());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sending to ${device.name}...'),
            duration: const Duration(seconds: 2),
          ),
        );
        // Go back to home — user can see progress in Transfers tab.
        Navigator.of(context).pop();
      } else {
        // Check for errors.
        final actionsState = ref.read(transferActionsProvider);
        if (actionsState.lastError != null) {
          unawaited(HapticService.error());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(actionsState.lastError!),
              backgroundColor: SwiftDropTheme.errorColor,
            ),
          );
        }
        setState(() => _isSending = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Send failed: $e'),
            backgroundColor: SwiftDropTheme.errorColor,
          ),
        );
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Still picking a file.
    if (_isPicking || _selectedFile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Send')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Opening file picker...', style: SwiftDropTheme.caption),
            ],
          ),
        ),
      );
    }

    final devicesAsync = ref.watch(discoveredDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send'),
        actions: [
          // Change file button
          TextButton.icon(
            onPressed: _isSending ? null : _pickFile,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('Change'),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Selected File Card ──
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SwiftDropTheme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: SwiftDropTheme.primaryColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: SwiftDropTheme.primaryColor
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _fileIcon(_selectedFileName ?? ''),
                    color: SwiftDropTheme.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedFileName ?? 'Unknown file',
                        style: SwiftDropTheme.heading3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatBytes(_selectedFileSize ?? 0),
                        style: SwiftDropTheme.caption,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle_rounded,
                    color: SwiftDropTheme.successColor, size: 22),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Section Header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Select a device to send',
                  style: SwiftDropTheme.heading3.copyWith(fontSize: 15),
                ),
                const Spacer(),
                // Refresh button
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'Rescan',
                  onPressed: () {
                    ref.read(discoveryControlProvider.notifier).stopAll();
                    ref.read(discoveryControlProvider.notifier).startAll();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── Device List ──
          Expanded(
            child: devicesAsync.when(
              loading: () => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScanningIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Looking for nearby devices...',
                      style: SwiftDropTheme.caption,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Make sure the other device is\nrunning SwiftDrop on the same network.',
                      style: SwiftDropTheme.caption,
                      textAlign: TextAlign.center,
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
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ScanningIndicator(),
                        const SizedBox(height: 20),
                        const Text(
                          'Searching for devices...',
                          style: SwiftDropTheme.heading3,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Make sure the other device is on\n'
                          'the same Wi-Fi network and running SwiftDrop.',
                          style:
                              SwiftDropTheme.caption.copyWith(fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return DeviceCard(
                      device: device,
                      onTap: _isSending
                          ? null
                          : () => _sendToDevice(device),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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
      'apk' || 'exe' || 'msi' || 'deb' => Icons.apps_rounded,
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
