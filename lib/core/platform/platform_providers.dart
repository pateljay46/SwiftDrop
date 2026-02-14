import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controller/transfer_providers.dart';
import '../discovery/discovery_providers.dart';
import 'lifecycle_manager.dart';
import 'permission_service.dart';
import 'platform_service.dart';

// ---------------------------------------------------------------------------
// Core platform service providers
// ---------------------------------------------------------------------------

/// Provides a singleton [PermissionService].
final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});

/// Provides a singleton [PlatformService].
final platformServiceProvider = Provider<PlatformService>((ref) {
  final service = PlatformService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// Permission state
// ---------------------------------------------------------------------------

/// Notifier that tracks the current permission status across all
/// SwiftDrop permission groups.
final permissionStateProvider =
    NotifierProvider<PermissionStateNotifier, PermissionState>(
  PermissionStateNotifier.new,
);

/// Snapshot of all SwiftDrop permissions.
class PermissionState {
  const PermissionState({
    this.nearbyDevices = PermissionOutcome.denied,
    this.storage = PermissionOutcome.denied,
    this.notification = PermissionOutcome.denied,
    this.checked = false,
  });

  final PermissionOutcome nearbyDevices;
  final PermissionOutcome storage;
  final PermissionOutcome notification;

  /// Whether we've checked permissions at least once.
  final bool checked;

  /// True when all required permissions are granted (or not applicable).
  bool get allGranted =>
      _isOk(nearbyDevices) && _isOk(storage) && _isOk(notification);

  bool _isOk(PermissionOutcome o) =>
      o == PermissionOutcome.granted ||
      o == PermissionOutcome.notApplicable;

  /// True when at least one permission is permanently denied.
  bool get hasPermanentlyDenied =>
      nearbyDevices == PermissionOutcome.permanentlyDenied ||
      storage == PermissionOutcome.permanentlyDenied ||
      notification == PermissionOutcome.permanentlyDenied;

  PermissionState copyWith({
    PermissionOutcome? nearbyDevices,
    PermissionOutcome? storage,
    PermissionOutcome? notification,
    bool? checked,
  }) {
    return PermissionState(
      nearbyDevices: nearbyDevices ?? this.nearbyDevices,
      storage: storage ?? this.storage,
      notification: notification ?? this.notification,
      checked: checked ?? this.checked,
    );
  }
}

class PermissionStateNotifier extends Notifier<PermissionState> {
  @override
  PermissionState build() {
    // On non-Android platforms, all permissions are implicitly granted.
    if (!Platform.isAndroid) {
      return const PermissionState(
        nearbyDevices: PermissionOutcome.notApplicable,
        storage: PermissionOutcome.notApplicable,
        notification: PermissionOutcome.notApplicable,
        checked: true,
      );
    }
    
    // On Android, auto-grant storage permissions by default
    return const PermissionState(
      storage: PermissionOutcome.granted,
    );
  }

  PermissionService get _service => ref.read(permissionServiceProvider);

  /// Checks the status of all permissions without requesting them.
  Future<void> checkAll() async {
    final nearbyDevices = await _service.check(
      SwiftDropPermission.nearbyDevices,
    );
    // Always grant storage permissions automatically
    const storage = PermissionOutcome.granted;
    final notification = await _service.check(SwiftDropPermission.notification);

    state = PermissionState(
      nearbyDevices: nearbyDevices,
      storage: storage,
      notification: notification,
      checked: true,
    );
  }

/// Requests all permissions.
  Future<void> requestAll() async {
    final results = await _service.requestAll();

    state = PermissionState(
      nearbyDevices:
          results[SwiftDropPermission.nearbyDevices] ??
          PermissionOutcome.denied,
      // Always grant storage permissions automatically
      storage: PermissionOutcome.granted,
      notification:
          results[SwiftDropPermission.notification] ??
          PermissionOutcome.denied,
      checked: true,
    );
  }

  /// Requests a single permission and updates state.
  Future<PermissionOutcome> request(SwiftDropPermission permission) async {
    final outcome = await _service.request(permission);

    switch (permission) {
      case SwiftDropPermission.nearbyDevices:
        state = state.copyWith(nearbyDevices: outcome);
      case SwiftDropPermission.storage:
        state = state.copyWith(storage: outcome);
      case SwiftDropPermission.notification:
        state = state.copyWith(notification: outcome);
    }

    return outcome;
  }

  /// Opens the system app settings page.
  Future<bool> openSettings() => _service.openSettings();
}

// ---------------------------------------------------------------------------
// Firewall state
// ---------------------------------------------------------------------------

/// Notifier that manages firewall rules for the SwiftDrop listen port.
final firewallStateProvider =
    NotifierProvider<FirewallStateNotifier, FirewallState>(
  FirewallStateNotifier.new,
);

/// Current firewall configuration state.
class FirewallState {
  const FirewallState({
    this.ruleActive = false,
    this.port,
    this.lastError,
  });

  /// Whether a firewall rule is currently active for our port.
  final bool ruleActive;

  /// The port the rule was created for.
  final int? port;

  /// Last error from a firewall operation.
  final String? lastError;
}

class FirewallStateNotifier extends Notifier<FirewallState> {
  @override
  FirewallState build() => const FirewallState();

  PlatformService get _platform => ref.read(platformServiceProvider);

  /// Ensures a firewall rule exists for [port].
  Future<void> ensureRuleFor(int port) async {
    // Check if rule already exists.
    final exists = await _platform.hasFirewallRule(port);
    if (exists) {
      state = FirewallState(ruleActive: true, port: port);
      return;
    }

    // Add the rule.
    final result = await _platform.addFirewallRule(port);
    state = FirewallState(
      ruleActive: result.success,
      port: port,
      lastError: result.success ? null : result.message,
    );

    if (result.success) {
      debugPrint('[FirewallState] Rule added for port $port');
    } else {
      debugPrint('[FirewallState] Failed: ${result.message}');
    }
  }

  /// Removes the firewall rule for the currently tracked port.
  Future<void> removeRule() async {
    final currentPort = state.port;
    if (currentPort == null || !state.ruleActive) return;

    final result = await _platform.removeFirewallRule(currentPort);
    state = FirewallState(
      ruleActive: !result.success, // If removal succeeded, rule is gone.
      port: result.success ? null : currentPort,
      lastError: result.success ? null : result.message,
    );
  }
}

// ---------------------------------------------------------------------------
// Lifecycle management
// ---------------------------------------------------------------------------

/// Provides a [LifecycleManager] wired to discovery and transfer providers.
final lifecycleManagerProvider = Provider<LifecycleManager>((ref) {
  final manager = LifecycleManager(
    onPause: () async {
      // Pause device discovery to save battery.
      await ref.read(discoveryControlProvider.notifier).stopAll();
      debugPrint('[Lifecycle] Discovery paused (app backgrounded)');
    },
    onResume: () async {
      // Resume discovery when the app returns.
      await ref.read(discoveryControlProvider.notifier).startAll();
      debugPrint('[Lifecycle] Discovery resumed (app foregrounded)');
    },
    onDetach: () async {
      // Clean up: stop receiving, remove firewall rules.
      await ref.read(receiveListenerProvider.notifier).stopListening();

      final firewallNotifier = ref.read(firewallStateProvider.notifier);
      await firewallNotifier.removeRule();

      debugPrint('[Lifecycle] Cleaned up on app detach');
    },
  );

  manager.start();
  ref.onDispose(manager.dispose);

  return manager;
});

// ---------------------------------------------------------------------------
// mDNS health
// ---------------------------------------------------------------------------

/// Checks whether the mDNS daemon (Avahi) is running on Linux.
///
/// On other platforms, resolves to a healthy result.
final mdnsHealthProvider = FutureProvider<MdnsHealthResult>((ref) {
  final platform = ref.watch(platformServiceProvider);
  return platform.checkMdnsDaemon();
});

// ---------------------------------------------------------------------------
// Foreground service
// ---------------------------------------------------------------------------

/// Notifier managing the Android foreground service state.
final foregroundServiceProvider =
    NotifierProvider<ForegroundServiceNotifier, bool>(
  ForegroundServiceNotifier.new,
);

class ForegroundServiceNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  PlatformService get _platform => ref.read(platformServiceProvider);

  /// Starts the foreground service with the given notification content.
  Future<void> start({
    String title = 'SwiftDrop',
    String body = 'Transferring files...',
  }) async {
    final success = await _platform.startForegroundService(
      title: title,
      body: body,
    );
    state = success;
  }

  /// Updates the foreground notification content.
  Future<void> update({
    required String title,
    required String body,
    int? progress,
  }) async {
    await _platform.updateForegroundNotification(
      title: title,
      body: body,
      progress: progress,
    );
  }

  /// Stops the foreground service.
  Future<void> stop() async {
    await _platform.stopForegroundService();
    state = false;
  }
}

// ---------------------------------------------------------------------------
// Battery optimization
// ---------------------------------------------------------------------------

/// Checks whether battery optimization is disabled for SwiftDrop.
final batteryOptimizationProvider = FutureProvider<bool>((ref) {
  final platform = ref.watch(platformServiceProvider);
  return platform.isBatteryOptimizationDisabled();
});
