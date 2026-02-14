import 'dart:convert';
import 'dart:typed_data';

import 'protocol_messages.dart';

/// Codec for encoding [ProtocolMessage] objects into wire-format bytes
/// and decoding raw bytes back into [ProtocolMessage] objects.
///
/// Wire envelope format (big-endian):
/// ```
/// [Length 4B][Type 1B][SeqNo 4B][Payload ...]
/// ```
/// Length covers Type + SeqNo + Payload (excludes the Length field itself).
class ProtocolCodec {
  const ProtocolCodec();

  /// Header size: Type (1) + SeqNo (4) = 5 bytes.
  static const int headerSize = 5;

  /// Length prefix size: 4 bytes.
  static const int lengthPrefixSize = 4;

  // ---------------------------------------------------------------------------
  // Encoding
  // ---------------------------------------------------------------------------

  /// Encodes a [ProtocolMessage] into a complete wire-format byte buffer
  /// including the length prefix.
  Uint8List encode(ProtocolMessage message) {
    final payload = _encodePayload(message);
    final totalLength = headerSize + payload.length;
    final buffer = ByteData(lengthPrefixSize + totalLength);

    // Length prefix (excludes itself).
    buffer.setUint32(0, totalLength, Endian.big);
    // Message type.
    buffer.setUint8(4, message.type.value);
    // Sequence number.
    buffer.setUint32(5, message.seqNo, Endian.big);

    // Payload.
    final bytes = buffer.buffer.asUint8List();
    bytes.setRange(lengthPrefixSize + headerSize, bytes.length, payload);

    return bytes;
  }

  Uint8List _encodePayload(ProtocolMessage message) {
    return switch (message) {
      final HandshakeMessage m => _encodeHandshake(m),
      final HandshakeConfirmMessage m => _encodeHandshakeConfirm(m),
      final FileMetaMessage m => _encodeFileMeta(m),
      FileAcceptMessage _ => Uint8List(0),
      final FileRejectMessage m => _encodeFileReject(m),
      final ChunkDataMessage m => _encodeChunkData(m),
      final ChunkAckMessage m => _encodeChunkAck(m),
      final ChunkNackMessage m => _encodeChunkNack(m),
      final TransferCompleteMessage m => _encodeTransferComplete(m),
      TransferVerifiedMessage _ => Uint8List(0),
      final ErrorMessage m => _encodeError(m),
      CancelMessage _ => Uint8List(0),
    };
  }

  Uint8List _encodeHandshake(HandshakeMessage m) {
    final nameBytes = utf8.encode(m.deviceName);
    final idBytes = utf8.encode(m.deviceId);
    // version(2) + pkLen(2) + pk(var) + nameLen(1) + name(var) + id(var, padded to 16)
    final idPadded = Uint8List(16);
    final idSrc = idBytes.length > 16 ? idBytes.sublist(0, 16) : idBytes;
    idPadded.setRange(0, idSrc.length, idSrc);

    final size = 2 + 2 + m.publicKey.length + 1 + nameBytes.length + 16;
    final bd = ByteData(size);
    var offset = 0;

    bd.setUint16(offset, m.protocolVersion, Endian.big);
    offset += 2;
    bd.setUint16(offset, m.publicKey.length, Endian.big);
    offset += 2;
    final bytes = bd.buffer.asUint8List();
    bytes.setRange(offset, offset + m.publicKey.length, m.publicKey);
    offset += m.publicKey.length;
    bd.setUint8(offset, nameBytes.length);
    offset += 1;
    bytes.setRange(offset, offset + nameBytes.length, nameBytes);
    offset += nameBytes.length;
    bytes.setRange(offset, offset + 16, idPadded);

    return bytes;
  }

  Uint8List _encodeHandshakeConfirm(HandshakeConfirmMessage m) {
    // 32-byte SHA-256 hash.
    assert(m.pairingHash.length == 32);
    return Uint8List.fromList(m.pairingHash);
  }

  Uint8List _encodeFileMeta(FileMetaMessage m) {
    final nameBytes = utf8.encode(m.fileName);
    // nameLen(2) + name(var) + fileSize(8) + chunkSize(4) + chunkCount(4) + checksum(32)
    final size = 2 + nameBytes.length + 8 + 4 + 4 + 32;
    final bd = ByteData(size);
    var offset = 0;

    bd.setUint16(offset, nameBytes.length, Endian.big);
    offset += 2;
    final bytes = bd.buffer.asUint8List();
    bytes.setRange(offset, offset + nameBytes.length, nameBytes);
    offset += nameBytes.length;
    // File size as uint64 big-endian (Dart doesn't have setUint64, use two uint32s).
    bd.setUint32(offset, (m.fileSize >> 32) & 0xFFFFFFFF, Endian.big);
    offset += 4;
    bd.setUint32(offset, m.fileSize & 0xFFFFFFFF, Endian.big);
    offset += 4;
    bd.setUint32(offset, m.chunkSize, Endian.big);
    offset += 4;
    bd.setUint32(offset, m.chunkCount, Endian.big);
    offset += 4;
    bytes.setRange(offset, offset + 32, m.fileChecksum);

    return bytes;
  }

  Uint8List _encodeFileReject(FileRejectMessage m) {
    final reasonBytes = utf8.encode(m.reason);
    final bd = ByteData(2 + reasonBytes.length);
    bd.setUint16(0, reasonBytes.length, Endian.big);
    final bytes = bd.buffer.asUint8List();
    bytes.setRange(2, 2 + reasonBytes.length, reasonBytes);
    return bytes;
  }

  Uint8List _encodeChunkData(ChunkDataMessage m) {
    // chunkIndex(4) + iv(12) + dataLen(4) + data(var) + tag(16) + checksum(32)
    final size = 4 + 12 + 4 + m.encryptedData.length + 16 + 32;
    final bd = ByteData(size);
    var offset = 0;

    bd.setUint32(offset, m.chunkIndex, Endian.big);
    offset += 4;
    final bytes = bd.buffer.asUint8List();
    bytes.setRange(offset, offset + 12, m.iv);
    offset += 12;
    bd.setUint32(offset, m.encryptedData.length, Endian.big);
    offset += 4;
    bytes.setRange(offset, offset + m.encryptedData.length, m.encryptedData);
    offset += m.encryptedData.length;
    bytes.setRange(offset, offset + 16, m.gcmTag);
    offset += 16;
    bytes.setRange(offset, offset + 32, m.plaintextChecksum);

    return bytes;
  }

  Uint8List _encodeChunkAck(ChunkAckMessage m) {
    final bd = ByteData(4);
    bd.setUint32(0, m.chunkIndex, Endian.big);
    return bd.buffer.asUint8List();
  }

  Uint8List _encodeChunkNack(ChunkNackMessage m) {
    final bd = ByteData(5);
    bd.setUint32(0, m.chunkIndex, Endian.big);
    bd.setUint8(4, m.errorCode.value);
    return bd.buffer.asUint8List();
  }

  Uint8List _encodeTransferComplete(TransferCompleteMessage m) {
    final bd = ByteData(4);
    bd.setUint32(0, m.totalChunks, Endian.big);
    return bd.buffer.asUint8List();
  }

  Uint8List _encodeError(ErrorMessage m) {
    final msgBytes = utf8.encode(m.message);
    // errorCode(2) + msgLen(2) + msg(var)
    final bd = ByteData(4 + msgBytes.length);
    bd.setUint16(0, m.errorCode.value, Endian.big);
    bd.setUint16(2, msgBytes.length, Endian.big);
    final bytes = bd.buffer.asUint8List();
    bytes.setRange(4, 4 + msgBytes.length, msgBytes);
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // Decoding
  // ---------------------------------------------------------------------------

  /// Decodes a complete wire-format message (including the length prefix)
  /// into a [ProtocolMessage].
  ///
  /// Returns the decoded message and the number of bytes consumed.
  /// Throws [ArgumentError] if the buffer is too small or malformed.
  ({ProtocolMessage message, int bytesConsumed}) decode(Uint8List data) {
    if (data.length < lengthPrefixSize) {
      throw ArgumentError('Buffer too small for length prefix: ${data.length}');
    }

    final bd = ByteData.sublistView(data);
    final messageLength = bd.getUint32(0, Endian.big);
    final totalLength = lengthPrefixSize + messageLength;

    if (data.length < totalLength) {
      throw ArgumentError(
        'Incomplete message: have ${data.length}, need $totalLength',
      );
    }

    final type = MessageType.fromValue(bd.getUint8(4));
    final seqNo = bd.getUint32(5, Endian.big);
    final payload = Uint8List.sublistView(
      data,
      lengthPrefixSize + headerSize,
      totalLength,
    );

    final message = _decodePayload(type, seqNo, payload);
    return (message: message, bytesConsumed: totalLength);
  }

  /// Checks whether [data] contains a complete message.
  /// Returns the total message size if complete, or `null` if more data needed.
  int? completeMessageSize(Uint8List data) {
    if (data.length < lengthPrefixSize) return null;
    final bd = ByteData.sublistView(data);
    final messageLength = bd.getUint32(0, Endian.big);
    final total = lengthPrefixSize + messageLength;
    return data.length >= total ? total : null;
  }

  ProtocolMessage _decodePayload(
    MessageType type,
    int seqNo,
    Uint8List payload,
  ) {
    return switch (type) {
      MessageType.handshakeInit => _decodeHandshake(type, seqNo, payload),
      MessageType.handshakeReply => _decodeHandshake(type, seqNo, payload),
      MessageType.handshakeConfirm => _decodeHandshakeConfirm(seqNo, payload),
      MessageType.fileMeta => _decodeFileMeta(seqNo, payload),
      MessageType.fileAccept => FileAcceptMessage(seqNo: seqNo),
      MessageType.fileReject => _decodeFileReject(seqNo, payload),
      MessageType.chunkData => _decodeChunkData(seqNo, payload),
      MessageType.chunkAck => _decodeChunkAck(seqNo, payload),
      MessageType.chunkNack => _decodeChunkNack(seqNo, payload),
      MessageType.transferComplete => _decodeTransferComplete(seqNo, payload),
      MessageType.transferVerified => TransferVerifiedMessage(seqNo: seqNo),
      MessageType.error => _decodeError(seqNo, payload),
      MessageType.cancel => CancelMessage(seqNo: seqNo),
    };
  }

  HandshakeMessage _decodeHandshake(
    MessageType type,
    int seqNo,
    Uint8List payload,
  ) {
    final bd = ByteData.sublistView(payload);
    var offset = 0;

    final protocolVersion = bd.getUint16(offset, Endian.big);
    offset += 2;
    final pkLen = bd.getUint16(offset, Endian.big);
    offset += 2;
    final publicKey = Uint8List.sublistView(payload, offset, offset + pkLen);
    offset += pkLen;
    final nameLen = bd.getUint8(offset);
    offset += 1;
    final deviceName = utf8.decode(payload.sublist(offset, offset + nameLen));
    offset += nameLen;
    final deviceId =
        utf8.decode(payload.sublist(offset, offset + 16)).replaceAll('\x00', '');

    return HandshakeMessage(
      type: type,
      seqNo: seqNo,
      protocolVersion: protocolVersion,
      publicKey: publicKey,
      deviceName: deviceName,
      deviceId: deviceId,
    );
  }

  HandshakeConfirmMessage _decodeHandshakeConfirm(
    int seqNo,
    Uint8List payload,
  ) {
    return HandshakeConfirmMessage(
      seqNo: seqNo,
      pairingHash: Uint8List.fromList(payload.sublist(0, 32)),
    );
  }

  FileMetaMessage _decodeFileMeta(int seqNo, Uint8List payload) {
    final bd = ByteData.sublistView(payload);
    var offset = 0;

    final nameLen = bd.getUint16(offset, Endian.big);
    offset += 2;
    final fileName = utf8.decode(payload.sublist(offset, offset + nameLen));
    offset += nameLen;
    // uint64 as two uint32s.
    final fileSizeHigh = bd.getUint32(offset, Endian.big);
    offset += 4;
    final fileSizeLow = bd.getUint32(offset, Endian.big);
    offset += 4;
    final fileSize = (fileSizeHigh << 32) | fileSizeLow;
    final chunkSize = bd.getUint32(offset, Endian.big);
    offset += 4;
    final chunkCount = bd.getUint32(offset, Endian.big);
    offset += 4;
    final fileChecksum = Uint8List.fromList(payload.sublist(offset, offset + 32));

    return FileMetaMessage(
      seqNo: seqNo,
      fileName: fileName,
      fileSize: fileSize,
      chunkSize: chunkSize,
      chunkCount: chunkCount,
      fileChecksum: fileChecksum,
    );
  }

  FileRejectMessage _decodeFileReject(int seqNo, Uint8List payload) {
    final bd = ByteData.sublistView(payload);
    final reasonLen = bd.getUint16(0, Endian.big);
    final reason = utf8.decode(payload.sublist(2, 2 + reasonLen));
    return FileRejectMessage(seqNo: seqNo, reason: reason);
  }

  ChunkDataMessage _decodeChunkData(int seqNo, Uint8List payload) {
    final bd = ByteData.sublistView(payload);
    var offset = 0;

    final chunkIndex = bd.getUint32(offset, Endian.big);
    offset += 4;
    final iv = Uint8List.fromList(payload.sublist(offset, offset + 12));
    offset += 12;
    final dataLen = bd.getUint32(offset, Endian.big);
    offset += 4;
    final encryptedData =
        Uint8List.fromList(payload.sublist(offset, offset + dataLen));
    offset += dataLen;
    final gcmTag = Uint8List.fromList(payload.sublist(offset, offset + 16));
    offset += 16;
    final plaintextChecksum =
        Uint8List.fromList(payload.sublist(offset, offset + 32));

    return ChunkDataMessage(
      seqNo: seqNo,
      chunkIndex: chunkIndex,
      iv: iv,
      encryptedData: encryptedData,
      gcmTag: gcmTag,
      plaintextChecksum: plaintextChecksum,
    );
  }

  ChunkAckMessage _decodeChunkAck(int seqNo, Uint8List payload) {
    final bd = ByteData.sublistView(payload);
    return ChunkAckMessage(seqNo: seqNo, chunkIndex: bd.getUint32(0, Endian.big));
  }

  ChunkNackMessage _decodeChunkNack(int seqNo, Uint8List payload) {
    final bd = ByteData.sublistView(payload);
    return ChunkNackMessage(
      seqNo: seqNo,
      chunkIndex: bd.getUint32(0, Endian.big),
      errorCode: NackErrorCode.fromValue(bd.getUint8(4)),
    );
  }

  TransferCompleteMessage _decodeTransferComplete(
    int seqNo,
    Uint8List payload,
  ) {
    final bd = ByteData.sublistView(payload);
    return TransferCompleteMessage(
      seqNo: seqNo,
      totalChunks: bd.getUint32(0, Endian.big),
    );
  }

  ErrorMessage _decodeError(int seqNo, Uint8List payload) {
    final bd = ByteData.sublistView(payload);
    final errorCode = ProtocolErrorCode.fromValue(bd.getUint16(0, Endian.big));
    final msgLen = bd.getUint16(2, Endian.big);
    final message = utf8.decode(payload.sublist(4, 4 + msgLen));
    return ErrorMessage(seqNo: seqNo, errorCode: errorCode, message: message);
  }
}
