import 'dart:typed_data';

import 'package:swiftdrop/core/transport/protocol_codec.dart';
import 'package:swiftdrop/core/transport/protocol_messages.dart';
import 'package:test/test.dart';

void main() {
  const codec = ProtocolCodec();

  group('ProtocolCodec', () {
    // -----------------------------------------------------------------------
    // Handshake messages
    // -----------------------------------------------------------------------

    test('encodes and decodes HandshakeInit roundtrip', () {
      final publicKey = Uint8List.fromList(List.generate(65, (i) => i));
      final message = HandshakeMessage(
        type: MessageType.handshakeInit,
        seqNo: 1,
        protocolVersion: 1,
        publicKey: publicKey,
        deviceName: 'TestDevice',
        deviceId: 'dev12345',
      );

      final encoded = codec.encode(message);
      final result = codec.decode(encoded);
      final decoded = result.message as HandshakeMessage;

      expect(decoded.type, MessageType.handshakeInit);
      expect(decoded.seqNo, 1);
      expect(decoded.protocolVersion, 1);
      expect(decoded.publicKey, publicKey);
      expect(decoded.deviceName, 'TestDevice');
      expect(decoded.deviceId, 'dev12345');
      expect(result.bytesConsumed, encoded.length);
    });

    test('encodes and decodes HandshakeReply roundtrip', () {
      final publicKey = Uint8List.fromList(List.generate(65, (i) => 255 - i));
      final message = HandshakeMessage(
        type: MessageType.handshakeReply,
        seqNo: 42,
        protocolVersion: 1,
        publicKey: publicKey,
        deviceName: 'Receiver',
        deviceId: 'rcv98765',
      );

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as HandshakeMessage;

      expect(decoded.type, MessageType.handshakeReply);
      expect(decoded.seqNo, 42);
      expect(decoded.deviceName, 'Receiver');
      expect(decoded.deviceId, 'rcv98765');
    });

    test('HandshakeConfirm roundtrip', () {
      final hash = Uint8List.fromList(List.generate(32, (i) => i * 8));
      final message = HandshakeConfirmMessage(seqNo: 3, pairingHash: hash);

      final encoded = codec.encode(message);
      final decoded =
          codec.decode(encoded).message as HandshakeConfirmMessage;

      expect(decoded.seqNo, 3);
      expect(decoded.pairingHash, hash);
    });

    // -----------------------------------------------------------------------
    // File metadata messages
    // -----------------------------------------------------------------------

    test('FileMeta roundtrip', () {
      final checksum = Uint8List.fromList(List.generate(32, (i) => i));
      final message = FileMetaMessage(
        seqNo: 10,
        fileName: 'photo.jpg',
        fileSize: 1024 * 1024 * 5, // 5 MB
        chunkSize: 65536,
        chunkCount: 80,
        fileChecksum: checksum,
      );

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as FileMetaMessage;

      expect(decoded.seqNo, 10);
      expect(decoded.fileName, 'photo.jpg');
      expect(decoded.fileSize, 5242880);
      expect(decoded.chunkSize, 65536);
      expect(decoded.chunkCount, 80);
      expect(decoded.fileChecksum, checksum);
    });

    test('FileMeta with large file size (>4GB)', () {
      final checksum = Uint8List(32);
      final message = FileMetaMessage(
        seqNo: 0,
        fileName: 'big.iso',
        fileSize: 5368709120, // 5 GB
        chunkSize: 65536,
        chunkCount: 81920,
        fileChecksum: checksum,
      );

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as FileMetaMessage;

      expect(decoded.fileSize, 5368709120);
    });

    test('FileAccept roundtrip', () {
      const message = FileAcceptMessage(seqNo: 11);

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as FileAcceptMessage;

      expect(decoded.seqNo, 11);
    });

    test('FileReject roundtrip', () {
      const message = FileRejectMessage(
        seqNo: 12,
        reason: 'Storage full',
      );

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as FileRejectMessage;

      expect(decoded.seqNo, 12);
      expect(decoded.reason, 'Storage full');
    });

    // -----------------------------------------------------------------------
    // Chunk data messages
    // -----------------------------------------------------------------------

    test('ChunkData roundtrip', () {
      final iv = Uint8List.fromList(List.generate(12, (i) => i));
      final data = Uint8List.fromList(List.generate(256, (i) => i & 0xFF));
      final tag = Uint8List.fromList(List.generate(16, (i) => i + 100));
      final checksum = Uint8List.fromList(List.generate(32, (i) => i + 50));

      final message = ChunkDataMessage(
        seqNo: 20,
        chunkIndex: 5,
        iv: iv,
        encryptedData: data,
        gcmTag: tag,
        plaintextChecksum: checksum,
      );

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as ChunkDataMessage;

      expect(decoded.seqNo, 20);
      expect(decoded.chunkIndex, 5);
      expect(decoded.iv, iv);
      expect(decoded.encryptedData, data);
      expect(decoded.gcmTag, tag);
      expect(decoded.plaintextChecksum, checksum);
    });

    test('ChunkData with 64KB payload', () {
      final iv = Uint8List(12);
      final data = Uint8List(65536);
      final tag = Uint8List(16);
      final checksum = Uint8List(32);

      final message = ChunkDataMessage(
        seqNo: 0,
        chunkIndex: 0,
        iv: iv,
        encryptedData: data,
        gcmTag: tag,
        plaintextChecksum: checksum,
      );

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as ChunkDataMessage;

      expect(decoded.encryptedData.length, 65536);
    });

    test('ChunkAck roundtrip', () {
      const message = ChunkAckMessage(seqNo: 21, chunkIndex: 7);

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as ChunkAckMessage;

      expect(decoded.seqNo, 21);
      expect(decoded.chunkIndex, 7);
    });

    test('ChunkNack roundtrip', () {
      const message = ChunkNackMessage(
        seqNo: 22,
        chunkIndex: 3,
        errorCode: NackErrorCode.checksumMismatch,
      );

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as ChunkNackMessage;

      expect(decoded.seqNo, 22);
      expect(decoded.chunkIndex, 3);
      expect(decoded.errorCode, NackErrorCode.checksumMismatch);
    });

    test('ChunkNack decryptionFailure roundtrip', () {
      const message = ChunkNackMessage(
        seqNo: 0,
        chunkIndex: 10,
        errorCode: NackErrorCode.decryptionFailure,
      );

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as ChunkNackMessage;

      expect(decoded.errorCode, NackErrorCode.decryptionFailure);
    });

    // -----------------------------------------------------------------------
    // Transfer completion messages
    // -----------------------------------------------------------------------

    test('TransferComplete roundtrip', () {
      const message = TransferCompleteMessage(seqNo: 30, totalChunks: 100);

      final encoded = codec.encode(message);
      final decoded =
          codec.decode(encoded).message as TransferCompleteMessage;

      expect(decoded.seqNo, 30);
      expect(decoded.totalChunks, 100);
    });

    test('TransferVerified roundtrip', () {
      const message = TransferVerifiedMessage(seqNo: 31);

      final encoded = codec.encode(message);
      final decoded =
          codec.decode(encoded).message as TransferVerifiedMessage;

      expect(decoded.seqNo, 31);
    });

    // -----------------------------------------------------------------------
    // Control messages
    // -----------------------------------------------------------------------

    test('Error roundtrip', () {
      const message = ErrorMessage(
        seqNo: 99,
        errorCode: ProtocolErrorCode.versionMismatch,
        message: 'Unsupported protocol version',
      );

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as ErrorMessage;

      expect(decoded.seqNo, 99);
      expect(decoded.errorCode, ProtocolErrorCode.versionMismatch);
      expect(decoded.message, 'Unsupported protocol version');
    });

    test('Cancel roundtrip', () {
      const message = CancelMessage(seqNo: 100);

      final encoded = codec.encode(message);
      final decoded = codec.decode(encoded).message as CancelMessage;

      expect(decoded.seqNo, 100);
    });

    // -----------------------------------------------------------------------
    // Edge cases
    // -----------------------------------------------------------------------

    test('decode rejects incomplete buffer', () {
      // Only 3 bytes — not enough for the length prefix.
      expect(
        () => codec.decode(Uint8List(3)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('decode rejects truncated message', () {
      const message = CancelMessage(seqNo: 0);
      final encoded = codec.encode(message);
      // Trim last 2 bytes.
      final truncated = Uint8List.sublistView(encoded, 0, encoded.length - 2);
      expect(
        () => codec.decode(truncated),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('completeMessageSize returns null for partial data', () {
      const message = CancelMessage(seqNo: 0);
      final encoded = codec.encode(message);
      final partial = Uint8List.sublistView(encoded, 0, 5);
      expect(codec.completeMessageSize(partial), isNull);
    });

    test('completeMessageSize returns total for complete data', () {
      const message = CancelMessage(seqNo: 0);
      final encoded = codec.encode(message);
      expect(codec.completeMessageSize(encoded), encoded.length);
    });

    test('decode handles extra trailing bytes', () {
      const message = CancelMessage(seqNo: 7);
      final encoded = codec.encode(message);

      // Append extra garbage bytes.
      final withExtra = Uint8List(encoded.length + 10);
      withExtra.setRange(0, encoded.length, encoded);

      final result = codec.decode(withExtra);
      expect(result.bytesConsumed, encoded.length);
      expect((result.message as CancelMessage).seqNo, 7);
    });

    test('MessageType.fromValue throws on unknown type', () {
      expect(
        () => MessageType.fromValue(0xAA),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('NackErrorCode.fromValue throws on unknown code', () {
      expect(
        () => NackErrorCode.fromValue(0xFF),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ProtocolErrorCode.fromValue returns internalError for unknown', () {
      expect(
        ProtocolErrorCode.fromValue(0xFFFF),
        ProtocolErrorCode.internalError,
      );
    });

    test('all 13 message types survive encode-decode', () {
      final allMessages = <ProtocolMessage>[
        HandshakeMessage(
          type: MessageType.handshakeInit,
          seqNo: 0,
          protocolVersion: 1,
          publicKey: Uint8List(65),
          deviceName: 'A',
          deviceId: 'id1',
        ),
        HandshakeMessage(
          type: MessageType.handshakeReply,
          seqNo: 1,
          protocolVersion: 1,
          publicKey: Uint8List(65),
          deviceName: 'B',
          deviceId: 'id2',
        ),
        HandshakeConfirmMessage(seqNo: 2, pairingHash: Uint8List(32)),
        FileMetaMessage(
          seqNo: 3,
          fileName: 'f.txt',
          fileSize: 100,
          chunkSize: 50,
          chunkCount: 2,
          fileChecksum: Uint8List(32),
        ),
        const FileAcceptMessage(seqNo: 4),
        const FileRejectMessage(seqNo: 5, reason: 'no'),
        ChunkDataMessage(
          seqNo: 6,
          chunkIndex: 0,
          iv: Uint8List(12),
          encryptedData: Uint8List(50),
          gcmTag: Uint8List(16),
          plaintextChecksum: Uint8List(32),
        ),
        const ChunkAckMessage(seqNo: 7, chunkIndex: 0),
        const ChunkNackMessage(
          seqNo: 8,
          chunkIndex: 0,
          errorCode: NackErrorCode.outOfSequence,
        ),
        const TransferCompleteMessage(seqNo: 9, totalChunks: 2),
        const TransferVerifiedMessage(seqNo: 10),
        const ErrorMessage(
          seqNo: 11,
          errorCode: ProtocolErrorCode.storageFull,
          message: 'disk full',
        ),
        const CancelMessage(seqNo: 12),
      ];

      for (final msg in allMessages) {
        final encoded = codec.encode(msg);
        final result = codec.decode(encoded);
        expect(result.message.type, msg.type, reason: '${msg.type} type');
        expect(result.message.seqNo, msg.seqNo, reason: '${msg.type} seqNo');
        expect(result.bytesConsumed, encoded.length);
      }
    });

    test('sequential decode of multiple messages in one buffer', () {
      const msg1 = ChunkAckMessage(seqNo: 0, chunkIndex: 0);
      const msg2 = ChunkAckMessage(seqNo: 1, chunkIndex: 1);
      const msg3 = CancelMessage(seqNo: 2);

      final buf1 = codec.encode(msg1);
      final buf2 = codec.encode(msg2);
      final buf3 = codec.encode(msg3);

      final combined = Uint8List(buf1.length + buf2.length + buf3.length);
      combined.setRange(0, buf1.length, buf1);
      combined.setRange(buf1.length, buf1.length + buf2.length, buf2);
      combined.setRange(
        buf1.length + buf2.length,
        combined.length,
        buf3,
      );

      var offset = 0;

      final r1 = codec.decode(Uint8List.sublistView(combined, offset));
      expect(r1.message, isA<ChunkAckMessage>());
      expect((r1.message as ChunkAckMessage).chunkIndex, 0);
      offset += r1.bytesConsumed;

      final r2 = codec.decode(Uint8List.sublistView(combined, offset));
      expect(r2.message, isA<ChunkAckMessage>());
      expect((r2.message as ChunkAckMessage).chunkIndex, 1);
      offset += r2.bytesConsumed;

      final r3 = codec.decode(Uint8List.sublistView(combined, offset));
      expect(r3.message, isA<CancelMessage>());
      offset += r3.bytesConsumed;

      expect(offset, combined.length);
    });

    test('wire format has correct envelope structure', () {
      const message = CancelMessage(seqNo: 0x12345678);
      final encoded = codec.encode(message);
      final bd = ByteData.sublistView(encoded);

      // Length prefix: type(1) + seqNo(4) + payload(0) = 5
      expect(bd.getUint32(0, Endian.big), 5);
      // Type: cancel = 0xFF
      expect(bd.getUint8(4), 0xFF);
      // SeqNo
      expect(bd.getUint32(5, Endian.big), 0x12345678);
      // Total size = 4 (len) + 5 (header) = 9
      expect(encoded.length, 9);
    });
  });
}
