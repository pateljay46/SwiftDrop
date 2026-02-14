import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop/core/platform/permission_service.dart';
import 'package:swiftdrop/core/platform/platform_providers.dart';

/// Tests for provider-layer models: [PermissionState] and [FirewallState].
void main() {
  // ---------------------------------------------------------------------------
  // PermissionState
  // ---------------------------------------------------------------------------

  group('PermissionState', () {
    test('default state has all denied', () {
      const state = PermissionState();
      expect(state.nearbyDevices, PermissionOutcome.denied);
      expect(state.storage, PermissionOutcome.denied);
      expect(state.notification, PermissionOutcome.denied);
      expect(state.checked, isFalse);
      expect(state.allGranted, isFalse);
    });

    test('allGranted is true when all granted', () {
      const state = PermissionState(
        nearbyDevices: PermissionOutcome.granted,
        storage: PermissionOutcome.granted,
        notification: PermissionOutcome.granted,
        checked: true,
      );
      expect(state.allGranted, isTrue);
    });

    test('allGranted is true when all notApplicable', () {
      const state = PermissionState(
        nearbyDevices: PermissionOutcome.notApplicable,
        storage: PermissionOutcome.notApplicable,
        notification: PermissionOutcome.notApplicable,
        checked: true,
      );
      expect(state.allGranted, isTrue);
    });

    test('allGranted mixed granted and notApplicable', () {
      const state = PermissionState(
        nearbyDevices: PermissionOutcome.granted,
        storage: PermissionOutcome.notApplicable,
        notification: PermissionOutcome.granted,
        checked: true,
      );
      expect(state.allGranted, isTrue);
    });

    test('allGranted is false when any denied', () {
      const state = PermissionState(
        nearbyDevices: PermissionOutcome.granted,
        storage: PermissionOutcome.denied,
        notification: PermissionOutcome.granted,
      );
      expect(state.allGranted, isFalse);
    });

    test('hasPermanentlyDenied detects nearbyDevices', () {
      const state = PermissionState(
        nearbyDevices: PermissionOutcome.permanentlyDenied,
      );
      expect(state.hasPermanentlyDenied, isTrue);
    });

    test('hasPermanentlyDenied detects storage', () {
      const state = PermissionState(
        storage: PermissionOutcome.permanentlyDenied,
      );
      expect(state.hasPermanentlyDenied, isTrue);
    });

    test('hasPermanentlyDenied detects notification', () {
      const state = PermissionState(
        notification: PermissionOutcome.permanentlyDenied,
      );
      expect(state.hasPermanentlyDenied, isTrue);
    });

    test('hasPermanentlyDenied false when none permanently denied', () {
      const state = PermissionState(
        nearbyDevices: PermissionOutcome.denied,
        storage: PermissionOutcome.granted,
        notification: PermissionOutcome.notApplicable,
      );
      expect(state.hasPermanentlyDenied, isFalse);
    });

    test('copyWith updates individual fields', () {
      const state = PermissionState(
        nearbyDevices: PermissionOutcome.denied,
        storage: PermissionOutcome.denied,
        notification: PermissionOutcome.denied,
      );

      final updated = state.copyWith(
        nearbyDevices: PermissionOutcome.granted,
        checked: true,
      );

      expect(updated.nearbyDevices, PermissionOutcome.granted);
      expect(updated.storage, PermissionOutcome.denied);
      expect(updated.notification, PermissionOutcome.denied);
      expect(updated.checked, isTrue);
    });

    test('copyWith preserves unset fields', () {
      const state = PermissionState(
        nearbyDevices: PermissionOutcome.granted,
        storage: PermissionOutcome.granted,
        notification: PermissionOutcome.granted,
        checked: true,
      );

      final updated = state.copyWith();

      expect(updated.nearbyDevices, PermissionOutcome.granted);
      expect(updated.storage, PermissionOutcome.granted);
      expect(updated.notification, PermissionOutcome.granted);
      expect(updated.checked, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // FirewallState
  // ---------------------------------------------------------------------------

  group('FirewallState', () {
    test('default state', () {
      const state = FirewallState();
      expect(state.ruleActive, isFalse);
      expect(state.port, isNull);
      expect(state.lastError, isNull);
    });

    test('active state with port', () {
      const state = FirewallState(
        ruleActive: true,
        port: 42000,
      );
      expect(state.ruleActive, isTrue);
      expect(state.port, 42000);
      expect(state.lastError, isNull);
    });

    test('error state', () {
      const state = FirewallState(
        ruleActive: false,
        port: 42000,
        lastError: 'Access denied',
      );
      expect(state.ruleActive, isFalse);
      expect(state.lastError, 'Access denied');
    });
  });
}
