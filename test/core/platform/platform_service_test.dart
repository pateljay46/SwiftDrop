import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop/core/platform/platform_service.dart';

/// Tests for [PlatformService].
///
/// Since platform channels require mock handlers, these tests verify
/// the Dart-side logic — argument marshalling, result parsing, and
/// fallback behaviour when the platform channel is not available.
///
/// Tests for Android- and Linux-only features are skipped when running
/// on the wrong platform (the PlatformService short-circuits on
/// non-applicable platforms).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late PlatformService service;
  final List<MethodCall> log = [];

  final bool isAndroid = Platform.isAndroid;
  final bool isLinux = Platform.isLinux;
  final bool isDesktop = Platform.isWindows || Platform.isLinux;

  setUp(() {
    log.clear();
    channel = const MethodChannel('com.swiftdrop/platform');
    service = PlatformService(channel: channel);
  });

  // Helper to register a mock handler.
  void mockHandler(
    Future<dynamic> Function(MethodCall call) handler,
  ) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      log.add(call);
      return handler(call);
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // ---------------------------------------------------------------------------
  // Firewall
  // ---------------------------------------------------------------------------

  group('Firewall management', () {
    test('addFirewallRule sends correct arguments', () async {
      mockHandler((call) async {
        return {'success': true, 'message': 'Rule added'};
      });

      final result = await service.addFirewallRule(42000);

      expect(result.success, isTrue);
      expect(result.message, 'Rule added');
      expect(log, hasLength(1));
      expect(log.first.method, 'addFirewallRule');
      expect(log.first.arguments, {'port': 42000});
    });

    test('addFirewallRule handles failure response', () async {
      mockHandler((call) async {
        return {
          'success': false,
          'message': 'Access denied',
          'requiresElevation': true,
        };
      });

      final result = await service.addFirewallRule(42000);

      expect(result.success, isFalse);
      expect(result.message, 'Access denied');
      expect(result.requiresElevation, isTrue);
    });

    test('addFirewallRule handles PlatformException', () async {
      mockHandler((call) async {
        throw PlatformException(
          code: 'ELEVATION_REQUIRED',
          message: 'Need admin',
        );
      });

      final result = await service.addFirewallRule(42000);

      expect(result.success, isFalse);
      expect(result.requiresElevation, isTrue);
      expect(result.message, 'Need admin');
    });

    test('removeFirewallRule sends correct arguments', () async {
      mockHandler((call) async {
        return {'success': true, 'message': 'Rule removed'};
      });

      final result = await service.removeFirewallRule(42000);

      expect(result.success, isTrue);
      expect(log.first.method, 'removeFirewallRule');
      expect(log.first.arguments, {'port': 42000});
    });

    test('hasFirewallRule returns boolean', () async {
      mockHandler((call) async => true);

      final result = await service.hasFirewallRule(42000);

      expect(result, isTrue);
      expect(log.first.method, 'hasFirewallRule');
    });

    test('hasFirewallRule returns false on PlatformException', () async {
      mockHandler((call) async {
        throw PlatformException(code: 'ERROR');
      });

      final result = await service.hasFirewallRule(42000);

      expect(result, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // mDNS health
  // ---------------------------------------------------------------------------

  group('mDNS daemon health', () {
    test('checkMdnsDaemon parses healthy response', () async {
      mockHandler((call) async {
        return {
          'available': true,
          'daemonName': 'avahi-daemon',
          'message': 'Running',
        };
      });

      final result = await service.checkMdnsDaemon();

      if (isLinux) {
        expect(result.available, isTrue);
        expect(result.daemonName, 'avahi-daemon');
        expect(result.message, 'Running');
      } else {
        // Non-Linux: short-circuits to available=true without channel.
        expect(result.available, isTrue);
      }
    });

    test('checkMdnsDaemon on non-Linux returns available', () async {
      final result = await service.checkMdnsDaemon();

      if (!isLinux) {
        expect(result.available, isTrue);
        expect(result.message, contains('not required'));
      }
    },
    skip: isLinux ? 'Linux-specific test' : null,
    );
  });

  // ---------------------------------------------------------------------------
  // Foreground service
  // ---------------------------------------------------------------------------

  group('Foreground service', () {
    test('startForegroundService returns true on non-Android', () async {
      final result = await service.startForegroundService(
        title: 'Sending',
        body: 'photo.jpg',
      );

      // Non-Android: short-circuits to true.
      if (!isAndroid) {
        expect(result, isTrue);
        expect(log, isEmpty); // Channel not called.
      }
    },
    skip: isAndroid ? 'Runs only on non-Android' : null,
    );

    test('stopForegroundService returns true on non-Android', () async {
      final result = await service.stopForegroundService();

      if (!isAndroid) {
        expect(result, isTrue);
        expect(log, isEmpty);
      }
    },
    skip: isAndroid ? 'Runs only on non-Android' : null,
    );

    test('updateForegroundNotification returns true on non-Android', () async {
      final result = await service.updateForegroundNotification(
        title: 'Sending',
        body: '50%',
        progress: 50,
      );

      if (!isAndroid) {
        expect(result, isTrue);
        expect(log, isEmpty);
      }
    },
    skip: isAndroid ? 'Runs only on non-Android' : null,
    );
  });

  // ---------------------------------------------------------------------------
  // Battery optimization
  // ---------------------------------------------------------------------------

  group('Battery optimization', () {
    test('isBatteryOptimizationDisabled returns true on non-Android', () async {
      final result = await service.isBatteryOptimizationDisabled();

      if (!isAndroid) {
        expect(result, isTrue);
        expect(log, isEmpty);
      }
    },
    skip: isAndroid ? 'Runs only on non-Android' : null,
    );

    test('requestBatteryOptimizationExemption returns true on non-Android',
        () async {
      final result = await service.requestBatteryOptimizationExemption();

      if (!isAndroid) {
        expect(result, isTrue);
        expect(log, isEmpty);
      }
    },
    skip: isAndroid ? 'Runs only on non-Android' : null,
    );
  });

  // ---------------------------------------------------------------------------
  // Desktop notifications
  // ---------------------------------------------------------------------------

  group('Desktop notifications', () {
    test('showDesktopNotification sends title and body on desktop', () async {
      mockHandler((call) async => true);

      final result = await service.showDesktopNotification(
        title: 'Transfer complete',
        body: 'photo.jpg received',
      );

      expect(result, isTrue);

      if (isDesktop) {
        expect(log.first.method, 'showDesktopNotification');
        expect(log.first.arguments, {
          'title': 'Transfer complete',
          'body': 'photo.jpg received',
        });
      }
    });

    test('showDesktopNotification handles failure on desktop', () async {
      mockHandler((call) async {
        throw PlatformException(code: 'ERROR');
      });

      final result = await service.showDesktopNotification(
        title: 'Test',
        body: 'test',
      );

      if (isDesktop) {
        expect(result, isFalse);
      } else {
        // On Android, short-circuits to true.
        expect(result, isTrue);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Result models
  // ---------------------------------------------------------------------------

  group('FirewallResult', () {
    test('toString includes all fields', () {
      const result = FirewallResult(
        success: true,
        message: 'OK',
        requiresElevation: false,
      );

      expect(result.toString(), contains('success: true'));
      expect(result.toString(), contains('message: OK'));
    });

    test('defaults requiresElevation to false', () {
      const result = FirewallResult(success: true);

      expect(result.requiresElevation, isFalse);
    });
  });

  group('MdnsHealthResult', () {
    test('toString includes all fields', () {
      const result = MdnsHealthResult(
        available: true,
        daemonName: 'avahi',
        message: 'running',
      );

      expect(result.toString(), contains('available: true'));
      expect(result.toString(), contains('daemon: avahi'));
    });
  });
}
