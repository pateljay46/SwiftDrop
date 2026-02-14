import 'dart:typed_data';

/// Wire protocol message types as defined in wire_protocol.md.
///
/// Each message on the wire follows the envelope:
/// ```
/// [Length 4B][Type 1B][SeqNo 4B][Payload ...]
/// ```
enum MessageType {
  // Handshake
  handshakeInit(0x01),
  handshakeReply(0x02),
  handshakeConfirm(0x03),

  // File metadata
  fileMeta(0x10),
  fileAccept(0x11),
  fileReject(0x12),

  // Chunk transfer
  chunkData(0x20),
  chunkAck(0x21),
  chunkNack(0x22),

  // Transfer completion
  transferComplete(0x30),
  transferVerified(0x31),

  // Control
  error(0xF0),
  cancel(0xFF);

  const MessageType(this.value);

  final int value;

  /// Lookup a [MessageType] from its byte value.
  static MessageType fromValue(int value) {
    return MessageType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError('Unknown message type: 0x${value.toRadixString(16)}'),
    );
  }
}

/// NACK error codes sent with CHUNK_NACK messages.
enum NackErrorCode {
  checksumMismatch(0x01),
  decryptionFailure(0x02),
  outOfSequence(0x03);

  const NackErrorCode(this.value);

  final int value;

  static NackErrorCode fromValue(int value) {
    return NackErrorCode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError('Unknown NACK error code: $value'),
    );
  }
}

/// Protocol-level error codes sent with ERROR messages.
enum ProtocolErrorCode {
  versionMismatch(0x0001),
  pairingRejected(0x0002),
  storageFull(0x0003),
  permissionDenied(0x0004),
  internalError(0x0005);

  const ProtocolErrorCode(this.value);

  final int value;

  static ProtocolErrorCode fromValue(int value) {
    return ProtocolErrorCode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ProtocolErrorCode.internalError,
    );
  }
}

// ---------------------------------------------------------------------------
// Message payload classes
// ---------------------------------------------------------------------------

/// Base class for all protocol messages.
sealed class ProtocolMessage {
  const ProtocolMessage({required this.type, this.seqNo = 0});

  final MessageType type;
  final int seqNo;
}

/// HANDSHAKE_INIT / HANDSHAKE_REPLY payload.
class HandshakeMessage extends ProtocolMessage {
  const HandshakeMessage({
    required super.type,
    super.seqNo,
    required this.protocolVersion,
    required this.publicKey,
    required this.deviceName,
    required this.deviceId,
  });

  final int protocolVersion;
  final Uint8List publicKey;
  final String deviceName;
  final String deviceId;
}

/// HANDSHAKE_CONFIRM payload.
class HandshakeConfirmMessage extends ProtocolMessage {
  const HandshakeConfirmMessage({
    super.seqNo,
    required this.pairingHash,
  }) : super(type: MessageType.handshakeConfirm);

  /// SHA-256 of the shared secret (32 bytes).
  final Uint8List pairingHash;
}

/// FILE_META payload.
class FileMetaMessage extends ProtocolMessage {
  const FileMetaMessage({
    super.seqNo,
    required this.fileName,
    required this.fileSize,
    required this.chunkSize,
    required this.chunkCount,
    required this.fileChecksum,
  }) : super(type: MessageType.fileMeta);

  final String fileName;
  final int fileSize;
  final int chunkSize;
  final int chunkCount;

  /// SHA-256 of the entire file (32 bytes).
  final Uint8List fileChecksum;
}

/// FILE_ACCEPT payload (empty).
class FileAcceptMessage extends ProtocolMessage {
  const FileAcceptMessage({super.seqNo})
      : super(type: MessageType.fileAccept);
}

/// FILE_REJECT payload.
class FileRejectMessage extends ProtocolMessage {
  const FileRejectMessage({
    super.seqNo,
    required this.reason,
  }) : super(type: MessageType.fileReject);

  final String reason;
}

/// CHUNK_DATA payload.
class ChunkDataMessage extends ProtocolMessage {
  const ChunkDataMessage({
    super.seqNo,
    required this.chunkIndex,
    required this.iv,
    required this.encryptedData,
    required this.gcmTag,
    required this.plaintextChecksum,
  }) : super(type: MessageType.chunkData);

  final int chunkIndex;

  /// 12-byte AES-256-GCM initialization vector.
  final Uint8List iv;

  /// Encrypted chunk data.
  final Uint8List encryptedData;

  /// 16-byte GCM authentication tag.
  final Uint8List gcmTag;

  /// SHA-256 of the plaintext chunk (32 bytes).
  final Uint8List plaintextChecksum;
}

/// CHUNK_ACK payload.
class ChunkAckMessage extends ProtocolMessage {
  const ChunkAckMessage({
    super.seqNo,
    required this.chunkIndex,
  }) : super(type: MessageType.chunkAck);

  final int chunkIndex;
}

/// CHUNK_NACK payload.
class ChunkNackMessage extends ProtocolMessage {
  const ChunkNackMessage({
    super.seqNo,
    required this.chunkIndex,
    required this.errorCode,
  }) : super(type: MessageType.chunkNack);

  final int chunkIndex;
  final NackErrorCode errorCode;
}

/// TRANSFER_COMPLETE payload.
class TransferCompleteMessage extends ProtocolMessage {
  const TransferCompleteMessage({
    super.seqNo,
    required this.totalChunks,
  }) : super(type: MessageType.transferComplete);

  final int totalChunks;
}

/// TRANSFER_VERIFIED payload (empty).
class TransferVerifiedMessage extends ProtocolMessage {
  const TransferVerifiedMessage({super.seqNo})
      : super(type: MessageType.transferVerified);
}

/// ERROR payload.
class ErrorMessage extends ProtocolMessage {
  const ErrorMessage({
    super.seqNo,
    required this.errorCode,
    required this.message,
  }) : super(type: MessageType.error);

  final ProtocolErrorCode errorCode;
  final String message;
}

/// CANCEL payload (empty).
class CancelMessage extends ProtocolMessage {
  const CancelMessage({super.seqNo})
      : super(type: MessageType.cancel);
}
