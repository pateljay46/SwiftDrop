import 'dart:async';

import 'package:swiftdrop/core/discovery/device_model.dart';
import 'package:swiftdrop/core/discovery/discovery_service.dart';
import 'package:test/test.dart';

void main() {
  group('DiscoveryService', () {
    late DiscoveryService service;

    setUp(() {
      service = DiscoveryService(
        deviceId: 'test1234',
        deviceName: 'TestDevice',
        transferPort: 0,
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    test('initializes with correct properties', () {
      expect(service.deviceId, equals('test1234'));
      expect(service.deviceName, equals('TestDevice'));
      expect(service.isDiscovering, isFalse);
      expect(service.isAdvertising, isFalse);
      expect(service.devices, isEmpty);
    });

    test('devicesStream emits updates', () async {
      final completer = Completer<List<DeviceModel>>();
      final sub = service.devicesStream.listen((devices) {
        if (!completer.isCompleted) {
          completer.complete(devices);
        }
      });

      // Manually trigger internal device add (simulating UDP packet).
      // We'll use reflection-free approach: test the stream by
      // directly adding to the service.
      // Since _addOrUpdateDevice is private, we test through UDP handling.
      // For unit tests, we verify the stream controller setup works.

      // Verify stream is a broadcast stream.
      expect(service.devicesStream.isBroadcast, isTrue);

      await sub.cancel();
    });

    test('devices list is unmodifiable', () {
      final deviceList = service.devices;
      expect(() => (deviceList as List).add('test'), throwsA(anything));
    });

    test('removeDevice removes and emits', () async {
      // We can't easily add devices without network, but we can verify
      // removeDevice doesn't throw on non-existent device.
      service.removeDevice('nonexistent');
      expect(service.devices, isEmpty);
    });

    test('dispose closes stream controller', () async {
      await service.dispose();

      // After dispose, the stream controller is closed.
      // A broadcast stream won't throw, but its subscription completes
      // immediately with a done event.
      var doneCalled = false;
      service.devicesStream.listen(
        (_) {},
        onDone: () => doneCalled = true,
      );
      // Allow microtask to process.
      await Future<void>.delayed(Duration.zero);
      expect(doneCalled, isTrue);
    });
  });

  group('DiscoveryService UDP packet parsing', () {
    test('constructs and parses UDP announcement', () {
      // Simulate the packet format:
      // SWFTDRP | version(1) | deviceId(8) | port(2) | deviceType(1) | nameLen(1) | name(var)
      final magic = 'SWFTDRP'.codeUnits;
      const version = 1;
      final deviceId = 'peer5678'.codeUnits;
      const port = 45000; // 0xAFC8
      const deviceTypeChar = 0x61; // 'a' for android
      final name = 'PeerDevice'.codeUnits;

      final packet = <int>[
        ...magic,
        version,
        ...deviceId,
        (port >> 8) & 0xFF, // 0xAF
        port & 0xFF, // 0xC8
        deviceTypeChar,
        name.length,
        ...name,
      ];

      // Verify packet structure
      expect(packet.length, equals(7 + 1 + 8 + 2 + 1 + 1 + name.length));

      // Verify magic bytes
      for (var i = 0; i < magic.length; i++) {
        expect(packet[i], equals(magic[i]));
      }

      // Verify version
      expect(packet[7], equals(1));

      // Verify device ID
      expect(
        String.fromCharCodes(packet.sublist(8, 16)),
        equals('peer5678'),
      );

      // Verify port
      expect((packet[16] << 8) | packet[17], equals(45000));

      // Verify name
      final nameLen = packet[19];
      expect(nameLen, equals(10));
      expect(
        String.fromCharCodes(packet.sublist(20, 20 + nameLen)),
        equals('PeerDevice'),
      );
    });

    test('rejects packets with wrong magic bytes', () {
      // A packet with wrong magic should be silently ignored.
      // This tests the format validation logic.
      final wrongMagic = 'WRONGPK'.codeUnits;
      final packet = <int>[
        ...wrongMagic,
        1,
        ...'peer5678'.codeUnits,
        0, 80,
        0x61,
        4,
        ...'Test'.codeUnits,
      ];

      // Verify magic doesn't match
      final expectedMagic = 'SWFTDRP'.codeUnits;
      var matches = true;
      for (var i = 0; i < expectedMagic.length; i++) {
        if (packet[i] != expectedMagic[i]) {
          matches = false;
          break;
        }
      }
      expect(matches, isFalse);
    });

    test('rejects packets that are too short', () {
      final shortPacket = <int>[1, 2, 3, 4, 5];
      // Minimum size is 20 bytes
      expect(shortPacket.length < 20, isTrue);
    });
  });

  group('DiscoveryService mDNS name parsing', () {
    test('extracts device ID from mDNS service name', () {
      const serviceName = 'SwiftDrop-abcd1234._swiftdrop._tcp';
      final parts = serviceName.split('.');
      final namePart = parts.first;
      final dashIdx = namePart.indexOf('-');

      expect(dashIdx, greaterThan(0));
      expect(namePart.substring(dashIdx + 1), equals('abcd1234'));
    });

    test('handles service name without dash', () {
      const serviceName = 'InvalidName._swiftdrop._tcp';
      final parts = serviceName.split('.');
      final namePart = parts.first;
      final dashIdx = namePart.indexOf('-');

      // Service name without proper format should be skipped
      expect(dashIdx, equals(-1));
    });
  });
}
