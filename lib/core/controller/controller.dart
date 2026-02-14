/// Transfer controller for SwiftDrop.
///
/// Orchestrates the entire transfer pipeline: discovery → pairing →
/// encryption handshake → chunked transfer → completion/failure.
/// Manages the transfer state machine.
library;

export 'transfer_controller.dart';
export 'transfer_providers.dart';
export 'transfer_record.dart';
