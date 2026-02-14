import 'package:flutter_test/flutter_test.dart';
import 'package:swiftdrop/core/platform/permission_service.dart';

/// Tests for permission service models and enums.
///
/// The actual permission requests require Android runtime, so we test
/// the enum values, [PermissionOutcome] mapping, and the service's
/// debug logging utility.
void main() {
  // ---------------------------------------------------------------------------
  // Enum coverage
  // ---------------------------------------------------------------------------

  group('SwiftDropPermission enum', () {
    test('has all expected values', () {
      expect(
        SwiftDropPermission.values,
        containsAll([
          SwiftDropPermission.nearbyDevices,
          SwiftDropPermission.storage,
          SwiftDropPermission.notification,
        ]),
      );
    });

    test('values count is 3', () {
      expect(SwiftDropPermission.values.length, 3);
    });
  });

  group('PermissionOutcome enum', () {
    test('has all expected values', () {
      expect(
        PermissionOutcome.values,
        containsAll([
          PermissionOutcome.granted,
          PermissionOutcome.denied,
          PermissionOutcome.permanentlyDenied,
          PermissionOutcome.notApplicable,
        ]),
      );
    });

    test('values count is 4', () {
      expect(PermissionOutcome.values.length, 4);
    });
  });

  // ---------------------------------------------------------------------------
  // PermissionService debug logging
  // ---------------------------------------------------------------------------

  group('PermissionService.debugLog', () {
    test('does not throw', () {
      // Verify the static debug utility does not error.
      PermissionService.debugLog('Test permission log');
    });
  });

  // ---------------------------------------------------------------------------
  // PermissionService instantiation
  // ---------------------------------------------------------------------------

  group('PermissionService instantiation', () {
    test('can be created', () {
      final service = PermissionService();
      expect(service, isNotNull);
    });
  });
}
