import 'package:test/test.dart';

import 'package:swiftdrop/storage/models/trusted_device.dart';

void main() {
  group('TrustedDevice', () {
    test('creates with required fields', () {
      final device = TrustedDevice(
        deviceId: 'abc12345',
        deviceName: 'Pixel 7',
        deviceType: 'android',
      );

      expect(device.deviceId, 'abc12345');
      expect(device.deviceName, 'Pixel 7');
      expect(device.deviceType, 'android');
      expect(device.autoAccept, isFalse);
      expect(device.firstPaired, isNotNull);
      expect(device.lastSeen, isNotNull);
    });

    test('touch() updates lastSeen and optionally name', () {
      final device = TrustedDevice(
        deviceId: 'abc',
        deviceName: 'Old Name',
        deviceType: 'windows',
        lastSeen: DateTime(2020),
      );

      expect(device.lastSeen.year, 2020);

      device.touch(name: 'New Name');

      expect(device.deviceName, 'New Name');
      expect(device.lastSeen.year, greaterThanOrEqualTo(2025));
    });

    test('touch() without name keeps existing name', () {
      final device = TrustedDevice(
        deviceId: 'x',
        deviceName: 'Keep',
        deviceType: 'linux',
      );

      device.touch();
      expect(device.deviceName, 'Keep');
    });

    test('equality by deviceId', () {
      final a = TrustedDevice(
        deviceId: 'same',
        deviceName: 'A',
        deviceType: 'android',
      );
      final b = TrustedDevice(
        deviceId: 'same',
        deviceName: 'B',
        deviceType: 'windows',
      );
      final c = TrustedDevice(
        deviceId: 'different',
        deviceName: 'A',
        deviceType: 'android',
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains relevant info', () {
      final device = TrustedDevice(
        deviceId: 'test123',
        deviceName: 'TestDevice',
        deviceType: 'linux',
        autoAccept: true,
      );

      final str = device.toString();
      expect(str, contains('test123'));
      expect(str, contains('TestDevice'));
      expect(str, contains('linux'));
      expect(str, contains('true'));
    });
  });

  group('TrustedDeviceAdapter', () {
    test('has correct typeId', () {
      final adapter = TrustedDeviceAdapter();
      expect(adapter.typeId, 1);
    });
  });
}
