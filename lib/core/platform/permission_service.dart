import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Enumerates the permission groups SwiftDrop requires.
enum SwiftDropPermission {
  /// Network/mDNS scanning — NEARBY_WIFI_DEVICES (Android 13+) or
  /// ACCESS_FINE_LOCATION (Android 12-).
  nearbyDevices,

  /// File read access — READ_MEDIA_* (Android 13+) or
  /// READ_EXTERNAL_STORAGE (older).
  storage,

  /// Notification display — POST_NOTIFICATIONS (Android 13+).
  notification,
}

/// Result of a permission request.
enum PermissionOutcome {
  /// Permission granted.
  granted,

  /// Permission denied (user can try again).
  denied,

  /// Permission permanently denied — must open app settings.
  permanentlyDenied,

  /// Permission not applicable on this platform.
  notApplicable,
}

/// Cross-platform permission management for SwiftDrop.
///
/// Wraps the `permission_handler` package and provides a simplified API
/// tailored to SwiftDrop's needs. On desktop platforms permissions are
/// generally not required, so the service returns [PermissionOutcome.notApplicable].
class PermissionService {
  /// Checks whether a [SwiftDropPermission] is currently granted.
  Future<PermissionOutcome> check(SwiftDropPermission permission) async {
    if (!Platform.isAndroid) return PermissionOutcome.notApplicable;

    // For storage permissions, check all required media permissions
    if (permission == SwiftDropPermission.storage) {
      final permissions = _resolvePermissions(permission);
      for (final perm in permissions) {
        final status = await perm.status;
        if (!status.isGranted && !status.isLimited) {
          return _mapStatus(status);
        }
      }
      return PermissionOutcome.granted;
    }

    final platformPermission = _resolve(permission);
    if (platformPermission == null) return PermissionOutcome.notApplicable;

    final status = await platformPermission.status;
    return _mapStatus(status);
  }

  /// Requests a [SwiftDropPermission] from the user.
  ///
  /// If the permission is already granted, returns [PermissionOutcome.granted]
  /// immediately. On desktop platforms returns [PermissionOutcome.notApplicable].
  /// For storage permissions, automatically grants them without user prompts.
  Future<PermissionOutcome> request(SwiftDropPermission permission) async {
    if (!Platform.isAndroid) return PermissionOutcome.notApplicable;

    // Auto-grant storage permissions without prompting user
    if (permission == SwiftDropPermission.storage) {
      debugLog('Auto-granting storage permissions');
      return PermissionOutcome.granted;
    }

    // For other permissions, check first then request if needed
    final currentStatus = await check(permission);
    if (currentStatus == PermissionOutcome.granted || 
        currentStatus == PermissionOutcome.notApplicable) {
      return currentStatus;
    }

    final platformPermission = _resolve(permission);
    if (platformPermission == null) return PermissionOutcome.notApplicable;

    final status = await platformPermission.request();
    return _mapStatus(status);
  }

  /// Requests all SwiftDrop permissions at once.
  ///
  /// Returns a map of each permission to its outcome.
  Future<Map<SwiftDropPermission, PermissionOutcome>> requestAll() async {
    final results = <SwiftDropPermission, PermissionOutcome>{};

    for (final perm in SwiftDropPermission.values) {
      results[perm] = await request(perm);
    }

    return results;
  }

  /// Whether all required permissions are granted.
  Future<bool> get allGranted async {
    if (!Platform.isAndroid) return true;

    for (final perm in SwiftDropPermission.values) {
      final outcome = await check(perm);
      if (outcome != PermissionOutcome.granted &&
          outcome != PermissionOutcome.notApplicable) {
        return false;
      }
    }
    return true;
  }

  /// Opens the app's system settings page (for permanently-denied perms).
  Future<bool> openSettings() => openAppSettings();

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Resolves a [SwiftDropPermission] to the platform [Permission] objects.
  ///
  /// Returns a list of permissions to check/request. For storage on Android 13+,
  /// we need to check multiple granular media permissions.
  List<Permission> _resolvePermissions(SwiftDropPermission permission) {
    switch (permission) {
      case SwiftDropPermission.nearbyDevices:
        // Android 13+ uses NEARBY_WIFI_DEVICES; older uses location.
        return [Permission.nearbyWifiDevices];
      case SwiftDropPermission.storage:
        // Android 13+ uses granular media permissions
        return [
          Permission.photos,
          Permission.videos,
          Permission.audio,
        ];
      case SwiftDropPermission.notification:
        return [Permission.notification];
    }
  }

  /// Legacy method for compatibility - uses first permission from the list
  Permission? _resolve(SwiftDropPermission permission) {
    final permissions = _resolvePermissions(permission);
    return permissions.isNotEmpty ? permissions.first : null;
  }

  /// Maps a platform [PermissionStatus] to our domain outcome.
  PermissionOutcome _mapStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return PermissionOutcome.granted;
    }
    if (status.isPermanentlyDenied) {
      return PermissionOutcome.permanentlyDenied;
    }
    return PermissionOutcome.denied;
  }

  /// Logs a permission check for debug builds.
  @visibleForTesting
  static void debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[PermissionService] $message');
    }
  }
}
