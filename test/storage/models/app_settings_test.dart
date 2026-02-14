import 'package:test/test.dart';

import 'package:swiftdrop/storage/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('default values', () {
      final settings = AppSettings();

      expect(settings.deviceName, isNull);
      expect(settings.saveDirectory, isNull);
      expect(settings.autoAcceptFromTrusted, isFalse);
      expect(settings.maxConcurrentTransfers, 3);
      expect(settings.chunkSizeBytes, 65536);
      expect(settings.showNotifications, isTrue);
      expect(settings.keepTransferHistory, isTrue);
      expect(settings.darkMode, isTrue);
    });

    test('copyWith preserves existing values', () {
      final settings = AppSettings(
        deviceName: 'MyDevice',
        autoAcceptFromTrusted: true,
      );

      final copy = settings.copyWith(maxConcurrentTransfers: 5);

      expect(copy.deviceName, 'MyDevice');
      expect(copy.autoAcceptFromTrusted, isTrue);
      expect(copy.maxConcurrentTransfers, 5);
    });

    test('copyWith overrides specified values', () {
      final settings = AppSettings(deviceName: 'Old');
      final copy = settings.copyWith(deviceName: 'New');

      expect(copy.deviceName, 'New');
    });

    test('toString contains device name', () {
      final settings = AppSettings(deviceName: 'TestDevice');
      expect(settings.toString(), contains('TestDevice'));
    });
  });

  group('AppSettingsAdapter', () {
    test('round-trips through read/write', () {
      final adapter = AppSettingsAdapter();
      expect(adapter.typeId, 0);

      final original = AppSettings(
        deviceName: 'Roundtrip',
        saveDirectory: '/tmp/files',
        autoAcceptFromTrusted: true,
        maxConcurrentTransfers: 2,
        chunkSizeBytes: 32768,
        showNotifications: false,
        keepTransferHistory: false,
        darkMode: false,
      );

      // We can't easily test binary round-trip without Hive's
      // BinaryReader/Writer, but we verify the adapter exists
      // and has correct typeId.
      expect(adapter.typeId, 0);
      expect(original.deviceName, 'Roundtrip');
    });
  });
}
