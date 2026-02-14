import 'package:swiftdrop/core/discovery/device_model.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceType', () {
    test('fromCode returns correct device type', () {
      expect(DeviceType.fromCode('android'), equals(DeviceType.android));
      expect(DeviceType.fromCode('windows'), equals(DeviceType.windows));
      expect(DeviceType.fromCode('linux'), equals(DeviceType.linux));
      expect(DeviceType.fromCode('ios'), equals(DeviceType.ios));
      expect(DeviceType.fromCode('ANDROID'), equals(DeviceType.android));
    });

    test('fromCode returns unknown for unrecognized codes', () {
      expect(DeviceType.fromCode('macos'), equals(DeviceType.unknown));
      expect(DeviceType.fromCode(''), equals(DeviceType.unknown));
    });

    test('displayName returns human-readable name', () {
      expect(DeviceType.android.displayName, equals('Android'));
      expect(DeviceType.windows.displayName, equals('Windows'));
    });
  });

  group('DeviceModel', () {
    test('creates a device with required fields', () {
      final device = DeviceModel(
        id: 'abcd1234',
        name: 'Test Device',
        deviceType: DeviceType.android,
      );

      expect(device.id, equals('abcd1234'));
      expect(device.name, equals('Test Device'));
      expect(device.deviceType, equals(DeviceType.android));
      expect(device.state, equals(DeviceState.available));
      expect(device.connectionType, equals(ConnectionType.wifi));
      expect(device.protocolVersion, equals(1));
    });

    test('creates a device with all fields', () {
      final device = DeviceModel(
        id: 'abcd1234',
        name: 'Full Device',
        ipAddress: '192.168.1.100',
        port: 45678,
        deviceType: DeviceType.windows,
        connectionType: ConnectionType.wifi,
        state: DeviceState.trusted,
        protocolVersion: 2,
      );

      expect(device.ipAddress, equals('192.168.1.100'));
      expect(device.port, equals(45678));
      expect(device.state, equals(DeviceState.trusted));
      expect(device.protocolVersion, equals(2));
    });

    test('touch updates lastSeen timestamp', () {
      final device = DeviceModel(
        id: 'abcd1234',
        name: 'Test',
        deviceType: DeviceType.android,
        lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final before = device.lastSeen;
      device.touch();

      expect(device.lastSeen.isAfter(before), isTrue);
    });

    test('isTimedOut returns true when device exceeds timeout', () {
      final device = DeviceModel(
        id: 'abcd1234',
        name: 'Old Device',
        deviceType: DeviceType.android,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 20)),
      );

      expect(device.isTimedOut(timeoutSeconds: 15), isTrue);
      expect(device.isTimedOut(timeoutSeconds: 30), isFalse);
    });

    test('isTimedOut returns false for fresh device', () {
      final device = DeviceModel(
        id: 'abcd1234',
        name: 'Fresh Device',
        deviceType: DeviceType.android,
      );

      expect(device.isTimedOut(timeoutSeconds: 15), isFalse);
    });

    test('copyWith creates modified copy', () {
      final original = DeviceModel(
        id: 'abcd1234',
        name: 'Original',
        ipAddress: '192.168.1.1',
        port: 1234,
        deviceType: DeviceType.android,
      );

      final copy = original.copyWith(
        name: 'Modified',
        ipAddress: '192.168.1.2',
        port: 5678,
      );

      expect(copy.id, equals('abcd1234'));
      expect(copy.name, equals('Modified'));
      expect(copy.ipAddress, equals('192.168.1.2'));
      expect(copy.port, equals(5678));
      expect(copy.deviceType, equals(DeviceType.android));
    });

    test('equality is based on id', () {
      final device1 = DeviceModel(
        id: 'abcd1234',
        name: 'Device 1',
        deviceType: DeviceType.android,
      );
      final device2 = DeviceModel(
        id: 'abcd1234',
        name: 'Device 2',
        deviceType: DeviceType.windows,
      );
      final device3 = DeviceModel(
        id: 'efgh5678',
        name: 'Device 1',
        deviceType: DeviceType.android,
      );

      expect(device1, equals(device2));
      expect(device1, isNot(equals(device3)));
    });

    test('hashCode is based on id', () {
      final device1 = DeviceModel(
        id: 'abcd1234',
        name: 'A',
        deviceType: DeviceType.android,
      );
      final device2 = DeviceModel(
        id: 'abcd1234',
        name: 'B',
        deviceType: DeviceType.windows,
      );

      expect(device1.hashCode, equals(device2.hashCode));
    });

    test('toString contains key info', () {
      final device = DeviceModel(
        id: 'abcd1234',
        name: 'Test',
        ipAddress: '192.168.1.5',
        port: 9999,
        deviceType: DeviceType.android,
      );

      final str = device.toString();
      expect(str, contains('abcd1234'));
      expect(str, contains('Test'));
      expect(str, contains('192.168.1.5'));
      expect(str, contains('Android'));
    });
  });
}
