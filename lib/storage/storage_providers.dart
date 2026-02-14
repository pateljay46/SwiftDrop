import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/storage_models.dart';
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// Storage service provider
// ---------------------------------------------------------------------------

/// Provides the singleton [StorageService].
///
/// Must be initialised before the app starts (see `main.dart`).
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService.instance;
});

// ---------------------------------------------------------------------------
// Settings providers
// ---------------------------------------------------------------------------

/// Notifier that exposes persistent [AppSettings] to the UI.
final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// Manages reading and writing [AppSettings].
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final storage = ref.read(storageServiceProvider);
    return storage.settings;
  }

  /// Updates one or more settings fields and persists.
  Future<void> update(
    AppSettings Function(AppSettings current) updater,
  ) async {
    final updated = updater(state);
    final storage = ref.read(storageServiceProvider);
    await storage.saveSettings(updated);
    state = updated;
  }

  /// Resets settings to defaults.
  Future<void> reset() async {
    final defaults = AppSettings();
    final storage = ref.read(storageServiceProvider);
    await storage.saveSettings(defaults);
    state = defaults;
  }
}

// ---------------------------------------------------------------------------
// Trusted devices providers
// ---------------------------------------------------------------------------

/// Notifier that manages the trusted devices list.
final trustedDevicesProvider =
    NotifierProvider<TrustedDevicesNotifier, List<TrustedDevice>>(
  TrustedDevicesNotifier.new,
);

/// Manages reading and writing trusted devices.
class TrustedDevicesNotifier extends Notifier<List<TrustedDevice>> {
  @override
  List<TrustedDevice> build() {
    final storage = ref.read(storageServiceProvider);
    return storage.trustedDevices;
  }

  StorageService get _storage => ref.read(storageServiceProvider);

  /// Adds or updates a trusted device.
  Future<void> trust(TrustedDevice device) async {
    await _storage.trustDevice(device);
    state = _storage.trustedDevices;
  }

  /// Removes a device from the trusted list.
  Future<void> untrust(String deviceId) async {
    await _storage.untrustDevice(deviceId);
    state = _storage.trustedDevices;
  }

  /// Checks whether a device ID is trusted.
  bool isTrusted(String deviceId) => _storage.isTrusted(deviceId);

  /// Toggles auto-accept for a trusted device.
  Future<void> toggleAutoAccept(String deviceId) async {
    final device = _storage.getTrustedDevice(deviceId);
    if (device == null) return;
    device.autoAccept = !device.autoAccept;
    await _storage.trustDevice(device);
    state = _storage.trustedDevices;
  }

  /// Clears all trusted devices.
  Future<void> clearAll() async {
    await _storage.clearTrustedDevices();
    state = [];
  }
}

// ---------------------------------------------------------------------------
// Transfer history providers
// ---------------------------------------------------------------------------

/// Notifier that manages the transfer history.
final transferHistoryProvider =
    NotifierProvider<TransferHistoryNotifier, List<TransferHistoryEntry>>(
  TransferHistoryNotifier.new,
);

/// Manages reading and writing transfer history.
class TransferHistoryNotifier extends Notifier<List<TransferHistoryEntry>> {
  @override
  List<TransferHistoryEntry> build() {
    final storage = ref.read(storageServiceProvider);
    return storage.transferHistory;
  }

  StorageService get _storage => ref.read(storageServiceProvider);

  /// Adds a history entry.
  Future<void> add(TransferHistoryEntry entry) async {
    await _storage.addHistoryEntry(entry);
    state = _storage.transferHistory;
  }

  /// Removes a history entry.
  Future<void> remove(String transferId) async {
    await _storage.removeHistoryEntry(transferId);
    state = _storage.transferHistory;
  }

  /// Clears all history.
  Future<void> clearAll() async {
    await _storage.clearHistory();
    state = [];
  }
}

/// Convenience provider: total history count.
final historyCountProvider = Provider<int>((ref) {
  final history = ref.watch(transferHistoryProvider);
  return history.length;
});
