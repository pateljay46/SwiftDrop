import 'dart:io';

import 'package:test/test.dart';

import 'package:swiftdrop/storage/models/storage_models.dart';
import 'package:swiftdrop/storage/storage_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('swiftdrop_storage_test_');
  });

  tearDown(() async {
    try {
      // Dispose if initialised.
      if (StorageService.instance.isInitialised) {
        await StorageService.instance.dispose();
      }
    } catch (_) {
      // Not initialised — ignore.
    }
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('StorageService', () {
    test('init creates singleton', () async {
      final service = await StorageService.init(path: tempDir.path);
      expect(service, isNotNull);
      expect(service.isInitialised, isTrue);
      expect(StorageService.instance, same(service));
    });

    test('init is idempotent', () async {
      final s1 = await StorageService.init(path: tempDir.path);
      final s2 = await StorageService.init(path: tempDir.path);
      expect(identical(s1, s2), isTrue);
    });

    // ── Settings ──

    test('settings returns defaults initially', () async {
      await StorageService.init(path: tempDir.path);
      final settings = StorageService.instance.settings;

      expect(settings.deviceName, isNull);
      expect(settings.autoAcceptFromTrusted, isFalse);
      expect(settings.maxConcurrentTransfers, 3);
    });

    test('saveSettings persists and retrieves', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      await service.saveSettings(AppSettings(
        deviceName: 'TestPC',
        autoAcceptFromTrusted: true,
        maxConcurrentTransfers: 5,
      ));

      final loaded = service.settings;
      expect(loaded.deviceName, 'TestPC');
      expect(loaded.autoAcceptFromTrusted, isTrue);
      expect(loaded.maxConcurrentTransfers, 5);
    });

    test('updateSettings applies updater function', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      await service.saveSettings(AppSettings(deviceName: 'Before'));
      await service.updateSettings(
        (s) => s.copyWith(deviceName: 'After'),
      );

      expect(service.settings.deviceName, 'After');
    });

    // ── Device identity ──

    test('deviceId returns null initially', () async {
      await StorageService.init(path: tempDir.path);
      expect(StorageService.instance.deviceId, isNull);
    });

    test('saveDeviceId persists ID', () async {
      await StorageService.init(path: tempDir.path);
      await StorageService.instance.saveDeviceId('abc12345');
      expect(StorageService.instance.deviceId, 'abc12345');
    });

    test('getOrCreateDeviceId generates on first call', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      var callCount = 0;
      final id = await service.getOrCreateDeviceId(() {
        callCount++;
        return 'generated';
      });

      expect(id, 'generated');
      expect(callCount, 1);

      // Second call should not invoke generator.
      final id2 = await service.getOrCreateDeviceId(() => 'other');
      expect(id2, 'generated');
    });

    // ── Trusted devices ──

    test('trusted devices empty initially', () async {
      await StorageService.init(path: tempDir.path);
      expect(StorageService.instance.trustedDevices, isEmpty);
    });

    test('trustDevice adds device', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      await service.trustDevice(TrustedDevice(
        deviceId: 'dev1',
        deviceName: 'Phone',
        deviceType: 'android',
      ));

      expect(service.trustedDevices, hasLength(1));
      expect(service.isTrusted('dev1'), isTrue);
      expect(service.isTrusted('dev2'), isFalse);
    });

    test('getTrustedDevice returns device or null', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      await service.trustDevice(TrustedDevice(
        deviceId: 'x',
        deviceName: 'X',
        deviceType: 'linux',
      ));

      expect(service.getTrustedDevice('x'), isNotNull);
      expect(service.getTrustedDevice('y'), isNull);
    });

    test('untrustDevice removes device', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      await service.trustDevice(TrustedDevice(
        deviceId: 'a',
        deviceName: 'A',
        deviceType: 'windows',
      ));

      await service.untrustDevice('a');
      expect(service.isTrusted('a'), isFalse);
      expect(service.trustedDevices, isEmpty);
    });

    test('clearTrustedDevices removes all', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      for (var i = 0; i < 3; i++) {
        await service.trustDevice(TrustedDevice(
          deviceId: 'dev$i',
          deviceName: 'Device $i',
          deviceType: 'android',
        ));
      }

      expect(service.trustedDevices, hasLength(3));
      await service.clearTrustedDevices();
      expect(service.trustedDevices, isEmpty);
    });

    // ── Transfer history ──

    test('history empty initially', () async {
      await StorageService.init(path: tempDir.path);
      expect(StorageService.instance.transferHistory, isEmpty);
      expect(StorageService.instance.historyCount, 0);
    });

    test('addHistoryEntry adds and sorts by newest first', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      await service.addHistoryEntry(TransferHistoryEntry(
        transferId: 'tx-old',
        fileName: 'old.txt',
        fileSize: 100,
        deviceId: 'd1',
        deviceName: 'D1',
        deviceType: 'android',
        direction: 'outgoing',
        status: 'completed',
        timestamp: DateTime(2024),
      ));

      await service.addHistoryEntry(TransferHistoryEntry(
        transferId: 'tx-new',
        fileName: 'new.txt',
        fileSize: 200,
        deviceId: 'd2',
        deviceName: 'D2',
        deviceType: 'windows',
        direction: 'incoming',
        status: 'completed',
        timestamp: DateTime(2025),
      ));

      final history = service.transferHistory;
      expect(history, hasLength(2));
      expect(history.first.transferId, 'tx-new'); // newest first
      expect(history.last.transferId, 'tx-old');
    });

    test('recentHistory limits count', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      for (var i = 0; i < 10; i++) {
        await service.addHistoryEntry(TransferHistoryEntry(
          transferId: 'tx-$i',
          fileName: 'file$i.txt',
          fileSize: i * 100,
          deviceId: 'd',
          deviceName: 'D',
          deviceType: 'android',
          direction: 'outgoing',
          status: 'completed',
        ));
      }

      expect(service.recentHistory(count: 5), hasLength(5));
      expect(service.recentHistory(count: 20), hasLength(10));
    });

    test('removeHistoryEntry removes by ID', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      await service.addHistoryEntry(TransferHistoryEntry(
        transferId: 'remove-me',
        fileName: 'file.txt',
        fileSize: 100,
        deviceId: 'd',
        deviceName: 'D',
        deviceType: 'android',
        direction: 'outgoing',
        status: 'completed',
      ));

      expect(service.historyCount, 1);
      await service.removeHistoryEntry('remove-me');
      expect(service.historyCount, 0);
    });

    test('clearHistory removes all entries', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      for (var i = 0; i < 5; i++) {
        await service.addHistoryEntry(TransferHistoryEntry(
          transferId: 'tx-$i',
          fileName: 'f$i',
          fileSize: 0,
          deviceId: 'd',
          deviceName: 'D',
          deviceType: 'android',
          direction: 'outgoing',
          status: 'completed',
        ));
      }

      await service.clearHistory();
      expect(service.historyCount, 0);
    });

    // ── Lifecycle ──

    test('clearAll resets settings and data but keeps identity', () async {
      await StorageService.init(path: tempDir.path);
      final service = StorageService.instance;

      await service.saveDeviceId('keep-me');
      await service.saveSettings(AppSettings(deviceName: 'Gone'));
      await service.trustDevice(TrustedDevice(
        deviceId: 'gone',
        deviceName: 'Gone',
        deviceType: 'android',
      ));
      await service.addHistoryEntry(TransferHistoryEntry(
        transferId: 'gone',
        fileName: 'gone.txt',
        fileSize: 0,
        deviceId: 'x',
        deviceName: 'X',
        deviceType: 'android',
        direction: 'outgoing',
        status: 'completed',
      ));

      await service.clearAll();

      // Settings reset to defaults.
      expect(service.settings.deviceName, isNull);
      expect(service.trustedDevices, isEmpty);
      expect(service.historyCount, 0);
      // Identity preserved.
      expect(service.deviceId, 'keep-me');
    });

    test('dispose then instance throws', () async {
      await StorageService.init(path: tempDir.path);
      await StorageService.instance.dispose();

      expect(
        () => StorageService.instance,
        throwsA(isA<StateError>()),
      );
    });
  });
}
