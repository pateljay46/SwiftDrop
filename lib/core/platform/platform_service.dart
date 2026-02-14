import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of a firewall configuration operation.
class FirewallResult {
  const FirewallResult({
    required this.success,
    this.message,
    this.requiresElevation = false,
  });

  /// Whether the firewall rule was successfully applied.
  final bool success;

  /// Human-readable status message.
  final String? message;

  /// Whether the operation requires elevated privileges (UAC / sudo).
  final bool requiresElevation;

  @override
  String toString() =>
      'FirewallResult(success: $success, message: $message, '
      'requiresElevation: $requiresElevation)';
}

/// Result of an mDNS daemon health check (Linux only).
class MdnsHealthResult {
  const MdnsHealthResult({
    required this.available,
    this.daemonName,
    this.message,
  });

  /// Whether an mDNS daemon (Avahi) is running.
  final bool available;

  /// Name of the detected daemon (e.g. "avahi-daemon").
  final String? daemonName;

  /// Human-readable status message.
  final String? message;

  @override
  String toString() =>
      'MdnsHealthResult(available: $available, daemon: $daemonName, '
      'message: $message)';
}

/// Platform-specific services exposed through method channels.
///
/// Handles:
/// - **Windows**: Firewall rule management via PowerShell
/// - **Linux**: Firewall rule management (ufw/iptables/nftables) + Avahi check
/// - **Android**: Foreground service management + battery optimization
///
/// On unsupported platforms, methods return safe no-op results.
class PlatformService {
  PlatformService({
    @visibleForTesting MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('com.swiftdrop/platform');

  final MethodChannel _channel;

  // ---------------------------------------------------------------------------
  // Firewall management (Windows & Linux)
  // ---------------------------------------------------------------------------

  /// Adds a firewall inbound TCP rule for the given [port].
  ///
  /// - **Windows**: Runs `New-NetFirewallRule` via PowerShell.
  /// - **Linux**: Detects ufw/iptables/nftables and adds a rule.
  /// - **Android**: No-op (returns success).
  Future<FirewallResult> addFirewallRule(int port) async {
    if (Platform.isAndroid) {
      return const FirewallResult(
        success: true,
        message: 'Firewall not applicable on Android',
      );
    }

    if (!Platform.isWindows && !Platform.isLinux) {
      return const FirewallResult(
        success: true,
        message: 'Firewall not applicable on this platform',
      );
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'addFirewallRule',
        {'port': port},
      );
      return FirewallResult(
        success: result?['success'] as bool? ?? false,
        message: result?['message'] as String?,
        requiresElevation: result?['requiresElevation'] as bool? ?? false,
      );
    } on PlatformException catch (e) {
      return FirewallResult(
        success: false,
        message: e.message ?? 'Failed to add firewall rule',
        requiresElevation: e.code == 'ELEVATION_REQUIRED',
      );
    } on MissingPluginException {
      // Platform channel not implemented — running in test or unsupported.
      return const FirewallResult(
        success: false,
        message: 'Platform channel not available',
      );
    }
  }

  /// Removes any SwiftDrop firewall rules for the given [port].
  Future<FirewallResult> removeFirewallRule(int port) async {
    if (Platform.isAndroid) {
      return const FirewallResult(
        success: true,
        message: 'Firewall not applicable on Android',
      );
    }

    if (!Platform.isWindows && !Platform.isLinux) {
      return const FirewallResult(
        success: true,
        message: 'Firewall not applicable on this platform',
      );
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'removeFirewallRule',
        {'port': port},
      );
      return FirewallResult(
        success: result?['success'] as bool? ?? false,
        message: result?['message'] as String?,
      );
    } on PlatformException catch (e) {
      return FirewallResult(
        success: false,
        message: e.message ?? 'Failed to remove firewall rule',
      );
    } on MissingPluginException {
      return const FirewallResult(
        success: false,
        message: 'Platform channel not available',
      );
    }
  }

  /// Checks whether a firewall rule for [port] already exists.
  Future<bool> hasFirewallRule(int port) async {
    if (!Platform.isWindows && !Platform.isLinux) return true;

    try {
      final result = await _channel.invokeMethod<bool>(
        'hasFirewallRule',
        {'port': port},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // mDNS daemon health (Linux)
  // ---------------------------------------------------------------------------

  /// Checks whether the Avahi mDNS daemon is running (Linux only).
  ///
  /// On non-Linux platforms, returns [MdnsHealthResult.available] = true.
  Future<MdnsHealthResult> checkMdnsDaemon() async {
    if (!Platform.isLinux) {
      return const MdnsHealthResult(
        available: true,
        message: 'mDNS check not required on this platform',
      );
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'checkMdnsDaemon',
      );
      return MdnsHealthResult(
        available: result?['available'] as bool? ?? false,
        daemonName: result?['daemonName'] as String?,
        message: result?['message'] as String?,
      );
    } on PlatformException catch (e) {
      return MdnsHealthResult(
        available: false,
        message: e.message ?? 'Failed to check mDNS daemon',
      );
    } on MissingPluginException {
      return const MdnsHealthResult(
        available: false,
        message: 'Platform channel not available',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Android foreground service
  // ---------------------------------------------------------------------------

  /// Starts an Android foreground service for active file transfers.
  ///
  /// On non-Android platforms, this is a no-op.
  Future<bool> startForegroundService({
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await _channel.invokeMethod<bool>(
        'startForegroundService',
        {'title': title, 'body': body},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[PlatformService] Failed to start foreground service: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Stops the Android foreground service.
  Future<bool> stopForegroundService() async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await _channel.invokeMethod<bool>(
        'stopForegroundService',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[PlatformService] Failed to stop foreground service: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Updates the foreground service notification content.
  Future<bool> updateForegroundNotification({
    required String title,
    required String body,
    int? progress,
  }) async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await _channel.invokeMethod<bool>(
        'updateForegroundNotification',
        <String, Object>{
          'title': title,
          'body': body,
          'progress': ?progress,
        },
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Battery optimization (Android)
  // ---------------------------------------------------------------------------

  /// Checks whether battery optimization is disabled for SwiftDrop.
  Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await _channel.invokeMethod<bool>(
        'isBatteryOptimizationDisabled',
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Requests the user to disable battery optimization.
  Future<bool> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await _channel.invokeMethod<bool>(
        'requestBatteryOptimizationExemption',
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Desktop notifications (Windows & Linux)
  // ---------------------------------------------------------------------------

  /// Shows a system notification on desktop platforms.
  ///
  /// On Android, notifications are handled via foreground service.
  Future<bool> showDesktopNotification({
    required String title,
    required String body,
  }) async {
    if (Platform.isAndroid) return true;

    if (!Platform.isWindows && !Platform.isLinux) return true;

    try {
      final result = await _channel.invokeMethod<bool>(
        'showDesktopNotification',
        <String, String>{'title': title, 'body': body},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Disposes any native resources held by the platform channel.
  void dispose() {
    // Currently a no-op — placeholder for future native resource cleanup.
  }
}
