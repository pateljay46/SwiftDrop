import 'package:hive/hive.dart';

import 'models/storage_models.dart';

/// Central storage service backed by Hive.
///
/// Manages three boxes:
/// - **settings** — single [AppSettings] entry
/// - **trustedDevices** — keyed by device ID
/// - **transferHistory** — keyed by transfer ID
///
/// Also persists the unique device identity so it survives app restarts.
class StorageService {
  StorageService._();

  static StorageService? _instance;

  /// Returns the singleton instance. Must call [init] first.
  static StorageService get instance {
    if (_instance == null) {
      throw StateError('StorageService not initialised — call init() first');
    }
    return _instance!;
  }

  late final Box<AppSettings> _settingsBox;
  late final Box<TrustedDevice> _trustedBox;
  late final Box<TransferHistoryEntry> _historyBox;
  late final Box<String> _identityBox;

  bool _initialised = false;

  /// Whether the service has been initialised.
  bool get isInitialised => _initialised;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Initialises Hive, registers adapters, and opens all boxes.
  ///
  /// [path] is the directory where Hive stores its files. On Flutter this
  /// comes from `path_provider`; in tests you can pass a temp directory.
  static Future<StorageService> init({required String path}) async {
    if (_instance != null && _instance!._initialised) return _instance!;

    Hive.init(path);

    // Register adapters (safe to call multiple times — Hive ignores dupes).
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TrustedDeviceAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(TransferHistoryEntryAdapter());
    }

    final service = StorageService._();
    service._settingsBox = await Hive.openBox<AppSettings>('settings');
    service._trustedBox = await Hive.openBox<TrustedDevice>('trusted_devices');
    service._historyBox =
        await Hive.openBox<TransferHistoryEntry>('transfer_history');
    service._identityBox = await Hive.openBox<String>('identity');

    service._initialised = true;
    _instance = service;
    return service;
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  static const _settingsKey = 'app_settings';

  /// Returns the persisted [AppSettings], or a default instance.
  AppSettings get settings {
    return _settingsBox.get(_settingsKey) ?? AppSettings();
  }

  /// Persists updated [AppSettings].
  Future<void> saveSettings(AppSettings settings) async {
    await _settingsBox.put(_settingsKey, settings);
  }

  /// Updates a single setting field and persists.
  Future<void> updateSettings(
    AppSettings Function(AppSettings current) updater,
  ) async {
    final current = settings;
    final updated = updater(current);
    await saveSettings(updated);
  }

  // ---------------------------------------------------------------------------
  // Device identity
  // ---------------------------------------------------------------------------

  static const _deviceIdKey = 'device_id';

  /// Returns the persisted device ID, or `null` if none exists yet.
  String? get deviceId => _identityBox.get(_deviceIdKey);

  /// Persists the device ID (called once on first launch).
  Future<void> saveDeviceId(String id) async {
    await _identityBox.put(_deviceIdKey, id);
  }

  /// Returns the device ID, generating and saving one via [generator]
  /// if not yet persisted.
  Future<String> getOrCreateDeviceId(String Function() generator) async {
    final existing = deviceId;
    if (existing != null) return existing;
    final newId = generator();
    await saveDeviceId(newId);
    return newId;
  }

  // ---------------------------------------------------------------------------
  // Trusted devices
  // ---------------------------------------------------------------------------

  /// Returns all trusted devices.
  List<TrustedDevice> get trustedDevices => _trustedBox.values.toList();

  /// Checks whether a device is trusted.
  bool isTrusted(String deviceId) => _trustedBox.containsKey(deviceId);

  /// Returns a trusted device by ID, or `null`.
  TrustedDevice? getTrustedDevice(String deviceId) =>
      _trustedBox.get(deviceId);

  /// Adds or updates a trusted device.
  Future<void> trustDevice(TrustedDevice device) async {
    await _trustedBox.put(device.deviceId, device);
  }

  /// Removes a device from the trusted list.
  Future<void> untrustDevice(String deviceId) async {
    await _trustedBox.delete(deviceId);
  }

  /// Removes all trusted devices.
  Future<void> clearTrustedDevices() async {
    await _trustedBox.clear();
  }

  // ---------------------------------------------------------------------------
  // Transfer history
  // ---------------------------------------------------------------------------

  /// Returns all transfer history entries, newest first.
  List<TransferHistoryEntry> get transferHistory {
    final entries = _historyBox.values.toList();
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  /// Returns the [count] most recent history entries.
  List<TransferHistoryEntry> recentHistory({int count = 50}) {
    final all = transferHistory;
    return all.length > count ? all.sublist(0, count) : all;
  }

  /// Adds a transfer to history.
  Future<void> addHistoryEntry(TransferHistoryEntry entry) async {
    await _historyBox.put(entry.transferId, entry);
  }

  /// Removes a specific history entry.
  Future<void> removeHistoryEntry(String transferId) async {
    await _historyBox.delete(transferId);
  }

  /// Clears all transfer history.
  Future<void> clearHistory() async {
    await _historyBox.clear();
  }

  /// Returns the total number of history entries.
  int get historyCount => _historyBox.length;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Closes all Hive boxes. Call on app termination.
  Future<void> dispose() async {
    await _settingsBox.close();
    await _trustedBox.close();
    await _historyBox.close();
    await _identityBox.close();
    _initialised = false;
    _instance = null;
  }

  /// Deletes all persisted data (factory reset).
  Future<void> clearAll() async {
    await _settingsBox.clear();
    await _trustedBox.clear();
    await _historyBox.clear();
    // Intentionally keep identity box — device ID stays.
  }
}
