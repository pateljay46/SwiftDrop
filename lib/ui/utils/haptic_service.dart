import 'dart:io';

import 'package:flutter/services.dart';

/// Provides haptic feedback for key transfer events.
///
/// Only triggers haptic feedback on mobile platforms (Android/iOS).
/// Desktop platforms silently ignore calls.
class HapticService {
  const HapticService._();

  /// Whether haptic feedback is available on this platform.
  static bool get isAvailable =>
      Platform.isAndroid || Platform.isIOS;

  /// Light tap — file selected, device tapped.
  static Future<void> lightTap() async {
    if (!isAvailable) return;
    await HapticFeedback.lightImpact();
  }

  /// Medium tap — transfer started, transfer accepted.
  static Future<void> mediumTap() async {
    if (!isAvailable) return;
    await HapticFeedback.mediumImpact();
  }

  /// Heavy tap — transfer completed successfully.
  static Future<void> heavyTap() async {
    if (!isAvailable) return;
    await HapticFeedback.heavyImpact();
  }

  /// Error vibration — transfer failed or rejected.
  static Future<void> error() async {
    if (!isAvailable) return;
    await HapticFeedback.vibrate();
  }

  /// Selection click — UI element selection.
  static Future<void> selectionClick() async {
    if (!isAvailable) return;
    await HapticFeedback.selectionClick();
  }
}
