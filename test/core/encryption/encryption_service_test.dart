import 'dart:typed_data';

import 'package:swiftdrop/core/encryption/encryption.dart';
import 'package:test/test.dart';

void main() {
  late EncryptionService service;

  setUp(() {
    service = EncryptionService();
  });

  group('Key pair generation', () {
    test('generates valid ECDH key pair', () {
      final keyPair = service.generateKeyPair();

      expect(keyPair.curveName, equals('prime256v1'));
      // Uncompressed P-256 public key is 65 bytes (0x04 || 32-byte x || 32-byte y)
      expect(keyPair.publicKey.length, equals(65));
      expect(keyPair.publicKey[0], equals(0x04)); // uncompressed point prefix
      expect(keyPair.privateKey.isNotEmpty, isTrue);
    });

    test('generates unique key pairs each time', () {
      final kp1 = service.generateKeyPair();
      final kp2 = service.generateKeyPair();

      expect(kp1.publicKey, isNot(equals(kp2.publicKey)));
      expect(kp1.privateKey, isNot(equals(kp2.privateKey)));
    });
  });

  group('Shared secret computation', () {
    test('both sides compute the same shared secret', () {
      final alice = service.generateKeyPair();
      final bob = service.generateKeyPair();

      final secretAlice = service.computeSharedSecret(
        privateKeyHex: alice.privateKey,
        remotePublicKeyBytes: bob.publicKey,
      );

      final secretBob = service.computeSharedSecret(
        privateKeyHex: bob.privateKey,
        remotePublicKeyBytes: alice.publicKey,
      );

      expect(secretAlice, equals(secretBob));
      expect(secretAlice.length, equals(32));
    });

    test('different key pairs produce different secrets', () {
      final alice = service.generateKeyPair();
      final bob = service.generateKeyPair();
      final charlie = service.generateKeyPair();

      final secretAB = service.computeSharedSecret(
        privateKeyHex: alice.privateKey,
        remotePublicKeyBytes: bob.publicKey,
      );

      final secretAC = service.computeSharedSecret(
        privateKeyHex: alice.privateKey,
        remotePublicKeyBytes: charlie.publicKey,
      );

      expect(secretAB, isNot(equals(secretAC)));
    });
  });

  group('Session key derivation', () {
    test('derives a 32-byte AES key from shared secret', () {
      final alice = service.generateKeyPair();
      final bob = service.generateKeyPair();

      final sharedSecret = service.computeSharedSecret(
        privateKeyHex: alice.privateKey,
        remotePublicKeyBytes: bob.publicKey,
      );

      final sessionKey = service.deriveSessionKey(sharedSecret);

      expect(sessionKey.length, equals(32));
    });

    test('same shared secret produces same session key', () {
      final alice = service.generateKeyPair();
      final bob = service.generateKeyPair();

      final sharedSecret = service.computeSharedSecret(
        privateKeyHex: alice.privateKey,
        remotePublicKeyBytes: bob.publicKey,
      );

      final key1 = service.deriveSessionKey(sharedSecret);
      final key2 = service.deriveSessionKey(sharedSecret);

      expect(key1, equals(key2));
    });

    test('different secrets produce different session keys', () {
      final alice = service.generateKeyPair();
      final bob = service.generateKeyPair();
      final charlie = service.generateKeyPair();

      final secret1 = service.computeSharedSecret(
        privateKeyHex: alice.privateKey,
        remotePublicKeyBytes: bob.publicKey,
      );
      final secret2 = service.computeSharedSecret(
        privateKeyHex: alice.privateKey,
        remotePublicKeyBytes: charlie.publicKey,
      );

      final key1 = service.deriveSessionKey(secret1);
      final key2 = service.deriveSessionKey(secret2);

      expect(key1, isNot(equals(key2)));
    });
  });

  group('Pairing code', () {
    test('derives a 6-digit pairing code', () {
      final alice = service.generateKeyPair();
      final bob = service.generateKeyPair();

      final sharedSecret = service.computeSharedSecret(
        privateKeyHex: alice.privateKey,
        remotePublicKeyBytes: bob.publicKey,
      );

      final code = service.derivePairingCode(sharedSecret);

      expect(code.length, equals(6));
      expect(int.tryParse(code), isNotNull);
    });

    test('both sides derive the same pairing code', () {
      final alice = service.generateKeyPair();
      final bob = service.generateKeyPair();

      final secretAlice = service.computeSharedSecret(
        privateKeyHex: alice.privateKey,
        remotePublicKeyBytes: bob.publicKey,
      );
      final secretBob = service.computeSharedSecret(
        privateKeyHex: bob.privateKey,
        remotePublicKeyBytes: alice.publicKey,
      );

      final codeAlice = service.derivePairingCode(secretAlice);
      final codeBob = service.derivePairingCode(secretBob);

      expect(codeAlice, equals(codeBob));
    });
  });

  group('Chunk encryption / decryption', () {
    late Uint8List sessionKey;

    setUp(() {
      final alice = service.generateKeyPair();
      final bob = service.generateKeyPair();
      final secret = service.computeSharedSecret(
        privateKeyHex: alice.privateKey,
        remotePublicKeyBytes: bob.publicKey,
      );
      sessionKey = service.deriveSessionKey(secret);
    });

    test('encrypts and decrypts a chunk correctly', () {
      final plaintext = Uint8List.fromList('Hello, SwiftDrop!'.codeUnits);

      final encrypted = service.encryptChunk(
        sessionKey: sessionKey,
        plaintext: plaintext,
      );

      final decrypted = service.decryptChunk(
        sessionKey: sessionKey,
        encrypted: encrypted,
      );

      expect(decrypted, equals(plaintext));
    });

    test('encrypts a 64KB chunk (default chunk size)', () {
      final plaintext = Uint8List(65536); // 64KB
      for (var i = 0; i < plaintext.length; i++) {
        plaintext[i] = i % 256;
      }

      final encrypted = service.encryptChunk(
        sessionKey: sessionKey,
        plaintext: plaintext,
      );

      final decrypted = service.decryptChunk(
        sessionKey: sessionKey,
        encrypted: encrypted,
      );

      expect(decrypted, equals(plaintext));
    });

    test('encrypts an empty chunk', () {
      final plaintext = Uint8List(0);

      final encrypted = service.encryptChunk(
        sessionKey: sessionKey,
        plaintext: plaintext,
      );

      final decrypted = service.decryptChunk(
        sessionKey: sessionKey,
        encrypted: encrypted,
      );

      expect(decrypted, equals(plaintext));
    });

    test('each encryption produces a unique IV', () {
      final plaintext = Uint8List.fromList('same data'.codeUnits);

      final enc1 = service.encryptChunk(
        sessionKey: sessionKey,
        plaintext: plaintext,
      );
      final enc2 = service.encryptChunk(
        sessionKey: sessionKey,
        plaintext: plaintext,
      );

      expect(enc1.iv, isNot(equals(enc2.iv)));
      // Ciphertexts should also differ because IV is different
      expect(enc1.ciphertext, isNot(equals(enc2.ciphertext)));
    });

    test('decryption fails with wrong session key', () {
      final plaintext = Uint8List.fromList('secret data'.codeUnits);

      final encrypted = service.encryptChunk(
        sessionKey: sessionKey,
        plaintext: plaintext,
      );

      // Generate a different session key
      final other = service.generateKeyPair();
      final self = service.generateKeyPair();
      final wrongSecret = service.computeSharedSecret(
        privateKeyHex: other.privateKey,
        remotePublicKeyBytes: self.publicKey,
      );
      final wrongKey = service.deriveSessionKey(wrongSecret);

      expect(
        () => service.decryptChunk(
          sessionKey: wrongKey,
          encrypted: encrypted,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('decryption fails with tampered ciphertext', () {
      final plaintext = Uint8List.fromList('important data'.codeUnits);

      final encrypted = service.encryptChunk(
        sessionKey: sessionKey,
        plaintext: plaintext,
      );

      // Tamper with the ciphertext
      if (encrypted.ciphertext.isNotEmpty) {
        encrypted.ciphertext[0] ^= 0xFF;
      }

      expect(
        () => service.decryptChunk(
          sessionKey: sessionKey,
          encrypted: encrypted,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('decryption fails with tampered tag', () {
      final plaintext = Uint8List.fromList('more data'.codeUnits);

      final encrypted = service.encryptChunk(
        sessionKey: sessionKey,
        plaintext: plaintext,
      );

      // Tamper with the tag
      encrypted.tag[0] ^= 0xFF;

      expect(
        () => service.decryptChunk(
          sessionKey: sessionKey,
          encrypted: encrypted,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('supports additional authenticated data (AAD)', () {
      final plaintext = Uint8List.fromList('aad test'.codeUnits);
      final aad = Uint8List.fromList('chunk-index:42'.codeUnits);

      final encrypted = service.encryptChunk(
        sessionKey: sessionKey,
        plaintext: plaintext,
        additionalData: aad,
      );

      // Decrypt with same AAD works
      final decrypted = service.decryptChunk(
        sessionKey: sessionKey,
        encrypted: encrypted,
        additionalData: aad,
      );
      expect(decrypted, equals(plaintext));

      // Decrypt with wrong AAD fails
      final wrongAad = Uint8List.fromList('chunk-index:99'.codeUnits);
      expect(
        () => service.decryptChunk(
          sessionKey: sessionKey,
          encrypted: encrypted,
          additionalData: wrongAad,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('EncryptionResult serialization', () {
    test('roundtrips through toBytes / fromBytes', () {
      final alice = service.generateKeyPair();
      final bob = service.generateKeyPair();
      final secret = service.computeSharedSecret(
        privateKeyHex: alice.privateKey,
        remotePublicKeyBytes: bob.publicKey,
      );
      final sessionKey = service.deriveSessionKey(secret);
      final plaintext = Uint8List.fromList('serialize me'.codeUnits);

      final encrypted = service.encryptChunk(
        sessionKey: sessionKey,
        plaintext: plaintext,
      );

      final bytes = encrypted.toBytes();
      final restored = EncryptionResult.fromBytes(bytes);

      expect(restored.iv, equals(encrypted.iv));
      expect(restored.ciphertext, equals(encrypted.ciphertext));
      expect(restored.tag, equals(encrypted.tag));

      // Verify decryption still works after roundtrip
      final decrypted = service.decryptChunk(
        sessionKey: sessionKey,
        encrypted: restored,
      );
      expect(decrypted, equals(plaintext));
    });

    test('fromBytes throws on buffer too small', () {
      expect(
        () => EncryptionResult.fromBytes(Uint8List(10)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Full end-to-end flow', () {
    test('simulates complete sender ↔ receiver handshake and transfer', () {
      // --- HANDSHAKE ---
      // Sender generates key pair
      final senderKP = service.generateKeyPair();

      // Receiver generates key pair
      final receiverKP = service.generateKeyPair();

      // Exchange public keys (simulated over network)
      // Sender computes shared secret
      final senderSecret = service.computeSharedSecret(
        privateKeyHex: senderKP.privateKey,
        remotePublicKeyBytes: receiverKP.publicKey,
      );

      // Receiver computes shared secret
      final receiverSecret = service.computeSharedSecret(
        privateKeyHex: receiverKP.privateKey,
        remotePublicKeyBytes: senderKP.publicKey,
      );

      // Both derive same secret
      expect(senderSecret, equals(receiverSecret));

      // Both derive same pairing code
      final senderCode = service.derivePairingCode(senderSecret);
      final receiverCode = service.derivePairingCode(receiverSecret);
      expect(senderCode, equals(receiverCode));

      // --- SESSION KEY ---
      final senderSessionKey = service.deriveSessionKey(senderSecret);
      final receiverSessionKey = service.deriveSessionKey(receiverSecret);
      expect(senderSessionKey, equals(receiverSessionKey));

      // --- FILE TRANSFER (simulated 3 chunks) ---
      final chunks = [
        Uint8List.fromList('chunk-0-data-here'.codeUnits),
        Uint8List.fromList('chunk-1-more-data'.codeUnits),
        Uint8List.fromList('chunk-2-end'.codeUnits),
      ];

      for (var i = 0; i < chunks.length; i++) {
        // Sender encrypts chunk
        final encrypted = service.encryptChunk(
          sessionKey: senderSessionKey,
          plaintext: chunks[i],
        );

        // Simulate wire transmission: serialize and deserialize
        final wireBytes = encrypted.toBytes();
        final received = EncryptionResult.fromBytes(wireBytes);

        // Receiver decrypts chunk
        final decrypted = service.decryptChunk(
          sessionKey: receiverSessionKey,
          encrypted: received,
        );

        expect(decrypted, equals(chunks[i]),
            reason: 'Chunk $i should decrypt correctly');
      }
    });
  });
}
