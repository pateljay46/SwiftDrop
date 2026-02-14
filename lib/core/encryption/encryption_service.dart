import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'encryption_result.dart';
import 'key_pair_model.dart';

/// Core encryption service implementing ECDH key exchange and AES-256-GCM
/// chunk encryption for secure file transfer.
///
/// Usage flow:
/// 1. Generate a key pair with [generateKeyPair]
/// 2. Exchange public keys with remote device
/// 3. Compute shared secret with [computeSharedSecret]
/// 4. Derive session key with [deriveSessionKey]
/// 5. Encrypt/decrypt chunks with [encryptChunk] / [decryptChunk]
class EncryptionService {
  EncryptionService() : _secureRandom = _createSecureRandom();

  /// ECDH curve used for key exchange.
  static const String _curveName = 'prime256v1';

  /// AES key length in bytes (256 bits).
  static const int _aesKeyLength = 32;

  /// GCM IV/nonce length in bytes (96 bits, recommended for GCM).
  static const int _ivLength = 12;

  /// GCM authentication tag length in bits.
  static const int _tagLengthBits = 128;

  /// HKDF info string for session key derivation.
  static final Uint8List _hkdfInfo =
      Uint8List.fromList('swiftdrop-session-v1'.codeUnits);

  /// HKDF salt (fixed for reproducibility; in production, could be random
  /// and exchanged alongside public keys).
  static final Uint8List _hkdfSalt =
      Uint8List.fromList('swiftdrop-salt-v1'.codeUnits);

  final SecureRandom _secureRandom;

  // ---------------------------------------------------------------------------
  // Key exchange
  // ---------------------------------------------------------------------------

  /// Generates an ECDH key pair on the P-256 curve.
  SwiftDropKeyPair generateKeyPair() {
    final domainParams = ECDomainParameters(_curveName);
    final keyParams = ECKeyGeneratorParameters(domainParams);
    final generator = ECKeyGenerator()
      ..init(ParametersWithRandom(keyParams, _secureRandom));

    final pair = generator.generateKeyPair();
    final ECPublicKey publicKey = pair.publicKey;
    final ECPrivateKey privateKey = pair.privateKey;

    return SwiftDropKeyPair(
      publicKey: publicKey.Q!.getEncoded(false),
      privateKey: privateKey.d!.toRadixString(16),
      curveName: _curveName,
    );
  }

  /// Computes the ECDH shared secret from our private key and the remote
  /// device's public key bytes.
  Uint8List computeSharedSecret({
    required String privateKeyHex,
    required Uint8List remotePublicKeyBytes,
  }) {
    final domainParams = ECDomainParameters(_curveName);
    final privateKey = ECPrivateKey(
      BigInt.parse(privateKeyHex, radix: 16),
      domainParams,
    );
    final remotePublicKey = ECPublicKey(
      domainParams.curve.decodePoint(remotePublicKeyBytes),
      domainParams,
    );

    final agreement = ECDHBasicAgreement()..init(privateKey);
    final sharedSecret = agreement.calculateAgreement(remotePublicKey);

    // Convert BigInt to fixed-length byte array (32 bytes for P-256).
    return _bigIntToBytes(sharedSecret, 32);
  }

  /// Derives a deterministic 6-digit pairing code from the shared secret.
  /// Both devices compute the same code so the user can verify visually.
  String derivePairingCode(Uint8List sharedSecret) {
    final digest = SHA256Digest();
    final hash = digest.process(sharedSecret);
    // Take first 4 bytes, interpret as unsigned int, mod 1_000_000.
    final value = (hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3];
    final code = (value.abs() % 1000000).toString().padLeft(6, '0');
    return code;
  }

  // ---------------------------------------------------------------------------
  // Session key derivation
  // ---------------------------------------------------------------------------

  /// Derives an AES-256 session key from the shared secret using HKDF-SHA256.
  Uint8List deriveSessionKey(Uint8List sharedSecret) {
    return _hkdfSha256(
      ikm: sharedSecret,
      salt: _hkdfSalt,
      info: _hkdfInfo,
      length: _aesKeyLength,
    );
  }

  // ---------------------------------------------------------------------------
  // Chunk encryption / decryption (AES-256-GCM)
  // ---------------------------------------------------------------------------

  /// Encrypts a single chunk using AES-256-GCM with a unique random IV.
  ///
  /// Returns an [EncryptionResult] containing the IV, ciphertext, and
  /// authentication tag.
  EncryptionResult encryptChunk({
    required Uint8List sessionKey,
    required Uint8List plaintext,
    Uint8List? additionalData,
  }) {
    final iv = _generateIV();

    final GCMBlockCipher cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(sessionKey),
          _tagLengthBits,
          iv,
          additionalData ?? Uint8List(0),
        ),
      );

    final output = Uint8List(cipher.getOutputSize(plaintext.length));
    var offset = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
    offset += cipher.doFinal(output, offset);

    // GCM appends the tag to the ciphertext. Split them.
    const tagSize = _tagLengthBits ~/ 8;
    final ciphertext = Uint8List.fromList(output.sublist(0, offset - tagSize));
    final tag = Uint8List.fromList(output.sublist(offset - tagSize, offset));

    return EncryptionResult(iv: iv, ciphertext: ciphertext, tag: tag);
  }

  /// Decrypts a single chunk using AES-256-GCM.
  ///
  /// Throws [ArgumentError] if authentication fails (tampered data).
  Uint8List decryptChunk({
    required Uint8List sessionKey,
    required EncryptionResult encrypted,
    Uint8List? additionalData,
  }) {
    // Re-combine ciphertext + tag for PointyCastle GCM.
    final input = Uint8List(encrypted.ciphertext.length + encrypted.tag.length);
    input.setRange(0, encrypted.ciphertext.length, encrypted.ciphertext);
    input.setRange(
        encrypted.ciphertext.length, input.length, encrypted.tag);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(sessionKey),
          _tagLengthBits,
          encrypted.iv,
          additionalData ?? Uint8List(0),
        ),
      );

    final output = Uint8List(cipher.getOutputSize(input.length));
    var offset = cipher.processBytes(input, 0, input.length, output, 0);

    try {
      offset += cipher.doFinal(output, offset);
    } catch (e) {
      throw ArgumentError(
          'GCM authentication failed – data may be tampered. ($e)');
    }

    return Uint8List.fromList(output.sublist(0, offset));
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Uint8List _generateIV() {
    final iv = Uint8List(_ivLength);
    for (var i = 0; i < _ivLength; i++) {
      iv[i] = _secureRandom.nextUint8();
    }
    return iv;
  }

  /// HKDF-SHA256 key derivation (RFC 5869).
  Uint8List _hkdfSha256({
    required Uint8List ikm,
    required Uint8List salt,
    required Uint8List info,
    required int length,
  }) {
    final hmac = HMac(SHA256Digest(), 64);

    // Extract
    hmac.init(KeyParameter(salt));
    final prk = Uint8List(hmac.macSize);
    hmac.update(ikm, 0, ikm.length);
    hmac.doFinal(prk, 0);

    // Expand
    final n = (length / hmac.macSize).ceil();
    final okm = Uint8List(n * hmac.macSize);
    var prev = Uint8List(0);

    for (var i = 1; i <= n; i++) {
      hmac.init(KeyParameter(prk));
      hmac.update(prev, 0, prev.length);
      hmac.update(info, 0, info.length);
      final counterByte = Uint8List.fromList([i]);
      hmac.update(counterByte, 0, 1);
      final block = Uint8List(hmac.macSize);
      hmac.doFinal(block, 0);
      okm.setRange((i - 1) * hmac.macSize, i * hmac.macSize, block);
      prev = block;
    }

    return Uint8List.sublistView(okm, 0, length);
  }

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  static SecureRandom _createSecureRandom() {
    final random = FortunaRandom();
    final seed = Uint8List(32);
    final dartRandom = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 32; i++) {
      seed[i] = (dartRandom + i * 7) & 0xFF;
    }
    random.seed(KeyParameter(seed));
    return random;
  }
}
