/// Shared models used across SwiftDrop layers.
///
/// Re-exports model classes from core and storage layers.
library;

export '../core/controller/transfer_record.dart';
export '../core/discovery/device_model.dart';
export '../core/platform/permission_service.dart'
    show SwiftDropPermission, PermissionOutcome;
export '../core/platform/platform_service.dart'
    show FirewallResult, MdnsHealthResult;
export '../storage/models/storage_models.dart';
