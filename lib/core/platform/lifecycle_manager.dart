import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Manages app lifecycle events to optimise resource usage.
///
/// Responsibilities:
/// - **Foreground → Background**: Pauses device discovery to conserve
///   battery. Active transfers continue (with optional foreground service
///   on Android).
/// - **Background → Foreground**: Resumes discovery scanning.
/// - **Detached (app closing)**: Cleans up firewall rules and stops the
///   TCP receive server.
///
/// Use via [LifecycleManager.instance] (singleton) or inject a custom
/// instance for testing.
class LifecycleManager with WidgetsBindingObserver {
  LifecycleManager({
    this.onPause,
    this.onResume,
    this.onDetach,
  });

  /// Called when the app moves to the background (inactive/paused/hidden).
  final AsyncCallback? onPause;

  /// Called when the app returns to the foreground (resumed).
  final AsyncCallback? onResume;

  /// Called when the app is being destroyed (detached).
  final AsyncCallback? onDetach;

  /// The last known lifecycle state.
  AppLifecycleState? _lastState;

  bool _registered = false;
  bool _isPaused = false;

  /// Whether the app is currently in the background.
  bool get isPaused => _isPaused;

  /// The last observed lifecycle state.
  AppLifecycleState? get lastState => _lastState;

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Starts observing lifecycle events.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  void start() {
    if (_registered) return;
    _registered = true;
    WidgetsBinding.instance.addObserver(this);
    debugLog('Lifecycle observer registered');
  }

  /// Stops observing lifecycle events.
  void stop() {
    if (!_registered) return;
    _registered = false;
    WidgetsBinding.instance.removeObserver(this);
    debugLog('Lifecycle observer removed');
  }

  // ---------------------------------------------------------------------------
  // WidgetsBindingObserver
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastState = state;
    debugLog('Lifecycle state changed: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        _handleResume();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _handlePause();
      case AppLifecycleState.detached:
        _handleDetach();
    }
  }

  // ---------------------------------------------------------------------------
  // Event handlers
  // ---------------------------------------------------------------------------

  Future<void> _handlePause() async {
    if (_isPaused) return; // Only fire once per transition.
    _isPaused = true;
    debugLog('App moving to background — pausing discovery');

    try {
      await onPause?.call();
    } catch (e) {
      debugLog('Error in onPause callback: $e');
    }
  }

  Future<void> _handleResume() async {
    if (!_isPaused) return; // Only fire once per transition.
    _isPaused = false;
    debugLog('App returning to foreground — resuming discovery');

    try {
      await onResume?.call();
    } catch (e) {
      debugLog('Error in onResume callback: $e');
    }
  }

  Future<void> _handleDetach() async {
    debugLog('App detaching — cleaning up');

    try {
      await onDetach?.call();
    } catch (e) {
      debugLog('Error in onDetach callback: $e');
    }

    stop();
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  /// Stops observing and clears all callback references.
  void dispose() {
    stop();
    debugLog('LifecycleManager disposed');
  }

  // ---------------------------------------------------------------------------
  // Debug logging
  // ---------------------------------------------------------------------------

  /// Logs lifecycle events in debug builds.
  @visibleForTesting
  static void debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[LifecycleManager] $message');
    }
  }
}
