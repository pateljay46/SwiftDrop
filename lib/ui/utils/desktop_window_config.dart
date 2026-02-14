import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Configures desktop-specific window properties.
///
/// Sets minimum window size, title, and other platform-specific
/// window management settings for Windows and Linux.
class DesktopWindowConfig {
  const DesktopWindowConfig._();

  /// Minimum window width in logical pixels.
  static const double minWidth = 400;

  /// Minimum window height in logical pixels.
  static const double minHeight = 600;

  /// Default window width in logical pixels.
  static const double defaultWidth = 420;

  /// Default window height in logical pixels.
  static const double defaultHeight = 760;

  /// Whether the current platform is a desktop platform.
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Applies desktop window configuration.
  ///
  /// Should be called early in `main()` after `WidgetsFlutterBinding`.
  /// On non-desktop platforms this is a no-op.
  static void apply() {
    if (!isDesktop) return;

    // Set preferred orientations — portrait-only for consistency.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Set system UI overlay style for a polished look.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Color(0xFF1E1E2E),
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }
}
