import 'dart:typed_data';

/// Represents an ECDH key pair for SwiftDrop encryption handshake.
class SwiftDropKeyPair {
  const SwiftDropKeyPair({
    required this.publicKey,
    required this.privateKey,
    required this.curveName,
  });

  /// Uncompressed public key bytes (65 bytes for P-256: 0x04 || x || y).
  final Uint8List publicKey;

  /// Private key as a hex string (BigInt scalar).
  final String privateKey;

  /// The elliptic curve name (e.g. 'prime256v1').
  final String curveName;

  @override
  String toString() =>
      'SwiftDropKeyPair(curve: $curveName, publicKey: ${publicKey.length}B)';
}
