/// Encryption layer for SwiftDrop.
///
/// Provides ECDH key exchange, AES-256-GCM chunk encryption,
/// and session key derivation via HKDF-SHA256.
library;

export 'encryption_result.dart';
export 'encryption_service.dart';
export 'key_pair_model.dart';
