import 'dart:typed_data';

/// Holds the result of encrypting a single chunk with AES-256-GCM.
class EncryptionResult {
  const EncryptionResult({
    required this.iv,
    required this.ciphertext,
    required this.tag,
  });

  /// Deserializes from a byte buffer produced by [toBytes].
  ///
  /// [ivLength] defaults to 12 bytes (96-bit GCM nonce).
  /// [tagLength] defaults to 16 bytes (128-bit GCM tag).
  factory EncryptionResult.fromBytes(
    Uint8List bytes, {
    int ivLength = 12,
    int tagLength = 16,
  }) {
    if (bytes.length < ivLength + tagLength) {
      throw ArgumentError(
        'Buffer too small: ${bytes.length} bytes, '
        'need at least ${ivLength + tagLength}',
      );
    }
    return EncryptionResult(
      iv: Uint8List.sublistView(bytes, 0, ivLength),
      ciphertext:
          Uint8List.sublistView(bytes, ivLength, bytes.length - tagLength),
      tag: Uint8List.sublistView(bytes, bytes.length - tagLength),
    );
  }

  /// Initialization vector (nonce) used for this chunk. Unique per chunk.
  final Uint8List iv;

  /// The encrypted data.
  final Uint8List ciphertext;

  /// GCM authentication tag proving data integrity.
  final Uint8List tag;

  /// Total byte size of the encrypted payload (IV + ciphertext + tag).
  int get totalSize => iv.length + ciphertext.length + tag.length;

  /// Serializes to a single byte buffer: [iv | ciphertext | tag].
  /// Used when transmitting over the wire.
  Uint8List toBytes() {
    final buffer = Uint8List(totalSize);
    var offset = 0;
    buffer.setRange(offset, offset + iv.length, iv);
    offset += iv.length;
    buffer.setRange(offset, offset + ciphertext.length, ciphertext);
    offset += ciphertext.length;
    buffer.setRange(offset, offset + tag.length, tag);
    return buffer;
  }

  @override
  String toString() =>
      'EncryptionResult(iv: ${iv.length}B, ciphertext: ${ciphertext.length}B, tag: ${tag.length}B)';
}
