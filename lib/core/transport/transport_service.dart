import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../constants.dart';
import '../encryption/encryption_result.dart';
import '../encryption/encryption_service.dart';
import 'file_chunker.dart';
import 'protocol_messages.dart';
import 'transport_connection.dart';

/// Transfer progress callback.
typedef TransferProgressCallback = void Function(TransferProgress progress);

/// High-level transfer state.
enum TransferState {
  idle,
  handshaking,
  awaitingAccept,
  transferring,
  verifying,
  completed,
  cancelled,
  failed,
}

/// Live transfer progress information.
class TransferProgress {
  const TransferProgress({
    required this.state,
    required this.fileName,
    required this.fileSize,
    required this.chunksTotal,
    required this.chunksCompleted,
    this.bytesTransferred = 0,
    this.errorMessage,
  });

  final TransferState state;
  final String fileName;
  final int fileSize;
  final int chunksTotal;
  final int chunksCompleted;
  final int bytesTransferred;
  final String? errorMessage;

  double get progress => chunksTotal > 0 ? chunksCompleted / chunksTotal : 0;

  TransferProgress copyWith({
    TransferState? state,
    int? chunksCompleted,
    int? bytesTransferred,
    String? errorMessage,
  }) {
    return TransferProgress(
      state: state ?? this.state,
      fileName: fileName,
      fileSize: fileSize,
      chunksTotal: chunksTotal,
      chunksCompleted: chunksCompleted ?? this.chunksCompleted,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Orchestrates the full send/receive file transfer flow:
///
/// 1. ECDH handshake (key exchange + pairing verification)
/// 2. File metadata exchange
/// 3. Encrypted chunked transfer with ACK/NACK + retry
/// 4. Transfer verification
class TransportService {
  TransportService({
    required this.encryptionService,
    required this.deviceName,
    required this.deviceId,
    this.chunkSize = SwiftDropConstants.defaultChunkSize,
    this.maxRetries = SwiftDropConstants.maxChunkRetries,
  });

  final EncryptionService encryptionService;
  final String deviceName;
  final String deviceId;
  final int chunkSize;
  final int maxRetries;

  final _progressController = StreamController<TransferProgress>.broadcast();

  /// Stream of transfer progress updates.
  Stream<TransferProgress> get progressStream => _progressController.stream;

  // ---------------------------------------------------------------------------
  // Sender flow
  // ---------------------------------------------------------------------------

  /// Sends a file to a receiver through an established [PeerConnection].
  ///
  /// Steps:
  /// 1. Handshake (ECDH key exchange)
  /// 2. Send FILE_META, wait for FILE_ACCEPT
  /// 3. Stream encrypted chunks with ACK/NACK handling
  /// 4. Send TRANSFER_COMPLETE, wait for TRANSFER_VERIFIED
  Future<TransferProgress> sendFile({
    required PeerConnection connection,
    required File file,
    TransferProgressCallback? onProgress,
  }) async {
    final chunker = FileChunker(chunkSize: chunkSize);
    final prepared = await chunker.prepare(file);

    var progress = TransferProgress(
      state: TransferState.handshaking,
      fileName: prepared.fileName,
      fileSize: prepared.fileSize,
      chunksTotal: prepared.chunkCount,
      chunksCompleted: 0,
    );
    _emitProgress(progress, onProgress);

    try {
      // --- Step 1: Handshake ---
      final sessionKey = await performSenderHandshake(connection);
      progress = progress.copyWith(state: TransferState.awaitingAccept);
      _emitProgress(progress, onProgress);

      // --- Step 2: File Metadata ---
      connection.send(FileMetaMessage(
        fileName: prepared.fileName,
        fileSize: prepared.fileSize,
        chunkSize: prepared.chunkSize,
        chunkCount: prepared.chunkCount,
        fileChecksum: prepared.fileChecksum,
      ));

      final response = await connection.waitFor(
        predicate: (m) => m is FileAcceptMessage || m is FileRejectMessage,
        timeout: const Duration(seconds: 60),
      );

      if (response is FileRejectMessage) {
        progress = progress.copyWith(
          state: TransferState.cancelled,
          errorMessage: 'Receiver rejected: ${response.reason}',
        );
        _emitProgress(progress, onProgress);
        return progress;
      }

      // --- Step 3: Chunk transfer ---
      progress = progress.copyWith(state: TransferState.transferring);
      _emitProgress(progress, onProgress);

      var bytesTransferred = 0;
      await for (final chunk in chunker.chunkFile(prepared.file)) {
        final sent = await _sendChunkWithRetry(
          connection: connection,
          sessionKey: sessionKey,
          chunk: chunk,
          file: prepared.file,
          chunker: chunker,
        );

        if (!sent) {
          progress = progress.copyWith(
            state: TransferState.failed,
            errorMessage: 'Chunk ${chunk.index} failed after $maxRetries retries',
          );
          _emitProgress(progress, onProgress);
          return progress;
        }

        bytesTransferred += chunk.data.length;
        progress = progress.copyWith(
          chunksCompleted: chunk.index + 1,
          bytesTransferred: bytesTransferred,
        );
        _emitProgress(progress, onProgress);
      }

      // --- Step 4: Transfer complete ---
      progress = progress.copyWith(state: TransferState.verifying);
      _emitProgress(progress, onProgress);

      connection.send(TransferCompleteMessage(
        totalChunks: prepared.chunkCount,
      ));

      await connection.waitFor(
        predicate: (m) => m is TransferVerifiedMessage,
        timeout: const Duration(seconds: 30),
      );

      progress = progress.copyWith(state: TransferState.completed);
      _emitProgress(progress, onProgress);
      return progress;
    } on TimeoutException {
      progress = progress.copyWith(
        state: TransferState.failed,
        errorMessage: 'Transfer timed out',
      );
      _emitProgress(progress, onProgress);
      return progress;
    } catch (e) {
      progress = progress.copyWith(
        state: TransferState.failed,
        errorMessage: e.toString(),
      );
      _emitProgress(progress, onProgress);
      return progress;
    }
  }

  // ---------------------------------------------------------------------------
  // Receiver flow
  // ---------------------------------------------------------------------------

  /// Receives a file from a sender through an established [PeerConnection].
  ///
  /// [onFileOffer] is called with the file metadata so the receiver can
  /// accept/reject. If it returns `null`, the transfer is rejected.
  /// If it returns a [File], the received data is written to that file.
  Future<TransferProgress> receiveFile({
    required PeerConnection connection,
    required Future<File?> Function(FileMetaMessage meta) onFileOffer,
    TransferProgressCallback? onProgress,
  }) async {
    var progress = const TransferProgress(
      state: TransferState.handshaking,
      fileName: '',
      fileSize: 0,
      chunksTotal: 0,
      chunksCompleted: 0,
    );
    _emitProgress(progress, onProgress);

    try {
      // --- Step 1: Handshake ---
      final sessionKey = await performReceiverHandshake(connection);

      // --- Step 2: Wait for FILE_META ---
      progress = progress.copyWith(state: TransferState.awaitingAccept);
      _emitProgress(progress, onProgress);

      final metaMsg = await connection.waitFor(
        predicate: (m) => m is FileMetaMessage,
        timeout: const Duration(seconds: 30),
      ) as FileMetaMessage;

      progress = TransferProgress(
        state: TransferState.awaitingAccept,
        fileName: metaMsg.fileName,
        fileSize: metaMsg.fileSize,
        chunksTotal: metaMsg.chunkCount,
        chunksCompleted: 0,
      );
      _emitProgress(progress, onProgress);

      final outputFile = await onFileOffer(metaMsg);
      if (outputFile == null) {
        connection.send(const FileRejectMessage(reason: 'User declined'));
        progress = progress.copyWith(state: TransferState.cancelled);
        _emitProgress(progress, onProgress);
        return progress;
      }

      connection.send(const FileAcceptMessage());

      // --- Step 3: Receive chunks ---
      progress = progress.copyWith(state: TransferState.transferring);
      _emitProgress(progress, onProgress);

      final raf = await outputFile.open(mode: FileMode.write);
      var bytesReceived = 0;

      try {
        for (var i = 0; i < metaMsg.chunkCount; i++) {
          final msg = await connection.waitFor(
            predicate: (m) =>
                m is ChunkDataMessage || m is TransferCompleteMessage,
            timeout: const Duration(seconds: 30),
          );

          if (msg is TransferCompleteMessage) break;
          final chunkMsg = msg as ChunkDataMessage;

          // Decrypt the chunk.
          final encrypted = EncryptionResult(
            iv: chunkMsg.iv,
            ciphertext: chunkMsg.encryptedData,
            tag: chunkMsg.gcmTag,
          );

          Uint8List plaintext;
          try {
            plaintext = encryptionService.decryptChunk(
              sessionKey: sessionKey,
              encrypted: encrypted,
            );
          } catch (e) {
            connection.send(ChunkNackMessage(
              chunkIndex: chunkMsg.chunkIndex,
              errorCode: NackErrorCode.decryptionFailure,
            ));
            // Wait for retransmit — loop will pick it up via the outer for.
            i--; // Retry the same index.
            continue;
          }

          // Verify chunk checksum.
          if (!FileChunker.verifyChunk(plaintext, chunkMsg.plaintextChecksum)) {
            connection.send(ChunkNackMessage(
              chunkIndex: chunkMsg.chunkIndex,
              errorCode: NackErrorCode.checksumMismatch,
            ));
            i--; // Retry the same index.
            continue;
          }

          // Write to file at correct position.
          await raf.setPosition(chunkMsg.chunkIndex * metaMsg.chunkSize);
          await raf.writeFrom(plaintext);
          bytesReceived += plaintext.length;

          connection.send(ChunkAckMessage(chunkIndex: chunkMsg.chunkIndex));

          progress = progress.copyWith(
            chunksCompleted: i + 1,
            bytesTransferred: bytesReceived,
          );
          _emitProgress(progress, onProgress);
        }
      } finally {
        await raf.close();
      }

      // --- Step 4: Wait for TRANSFER_COMPLETE, verify, reply ---
      // Sender may have already sent TRANSFER_COMPLETE above.
      // Wait for it if not already received.
      await connection.waitFor(
        predicate: (m) => m is TransferCompleteMessage,
        timeout: const Duration(seconds: 10),
      ).catchError((_) => const TransferCompleteMessage(totalChunks: 0));

      progress = progress.copyWith(state: TransferState.verifying);
      _emitProgress(progress, onProgress);

      // Verify whole file checksum.
      final verified = await FileChunker.verifyFile(
        outputFile,
        metaMsg.fileChecksum,
      );

      if (verified) {
        connection.send(const TransferVerifiedMessage());
        progress = progress.copyWith(state: TransferState.completed);
      } else {
        connection.send(const ErrorMessage(
          errorCode: ProtocolErrorCode.internalError,
          message: 'File checksum mismatch',
        ));
        progress = progress.copyWith(
          state: TransferState.failed,
          errorMessage: 'File checksum verification failed',
        );
      }
      _emitProgress(progress, onProgress);
      return progress;
    } on TimeoutException {
      progress = progress.copyWith(
        state: TransferState.failed,
        errorMessage: 'Transfer timed out',
      );
      _emitProgress(progress, onProgress);
      return progress;
    } catch (e) {
      progress = progress.copyWith(
        state: TransferState.failed,
        errorMessage: e.toString(),
      );
      _emitProgress(progress, onProgress);
      return progress;
    }
  }

  /// Releases resources.
  void dispose() {
    _progressController.close();
  }

  // ---------------------------------------------------------------------------
  // Handshake helpers
  // ---------------------------------------------------------------------------

  /// Sender initiates handshake: sends INIT, receives REPLY, sends CONFIRM.
  ///
  /// Validates that the receiver's protocol version is compatible before
  /// proceeding with key exchange.
  ///
  /// Public for benchmarking — prefer using [sendFile] for real transfers.
  Future<Uint8List> performSenderHandshake(PeerConnection connection) async {
    final keyPair = encryptionService.generateKeyPair();

    connection.send(HandshakeMessage(
      type: MessageType.handshakeInit,
      protocolVersion: SwiftDropConstants.protocolVersion,
      publicKey: keyPair.publicKey,
      deviceName: deviceName,
      deviceId: deviceId,
    ));

    final reply = await connection.waitFor(
      predicate: (m) => m is HandshakeMessage || m is ErrorMessage,
      timeout: const Duration(seconds: 15),
    );

    if (reply is ErrorMessage) {
      throw StateError('Handshake rejected: ${reply.message}');
    }

    final handshakeReply = reply as HandshakeMessage;

    // --- Version negotiation ---
    if (handshakeReply.protocolVersion <
            SwiftDropConstants.minSupportedProtocolVersion ||
        handshakeReply.protocolVersion >
            SwiftDropConstants.protocolVersion) {
      connection.send(ErrorMessage(
        errorCode: ProtocolErrorCode.versionMismatch,
        message: 'Unsupported protocol v${handshakeReply.protocolVersion}'
            ' (supported: v${SwiftDropConstants.minSupportedProtocolVersion}'
            '-v${SwiftDropConstants.protocolVersion})',
      ));
      throw StateError(
        'Incompatible protocol version: ${handshakeReply.protocolVersion}',
      );
    }

    final sharedSecret = encryptionService.computeSharedSecret(
      privateKeyHex: keyPair.privateKey,
      remotePublicKeyBytes: handshakeReply.publicKey,
    );

    final sessionKey = encryptionService.deriveSessionKey(sharedSecret);

    // Send pairing confirmation hash.
    final pairingHash = Uint8List.fromList(sha256.convert(sharedSecret).bytes);
    connection.send(HandshakeConfirmMessage(pairingHash: pairingHash));

    // Wait for receiver's confirm.
    await connection.waitFor(
      predicate: (m) => m is HandshakeConfirmMessage,
      timeout: const Duration(seconds: 30),
    );

    return sessionKey;
  }

  /// Receiver waits for INIT, validates protocol version, sends REPLY,
  /// exchanges CONFIRM.
  ///
  /// Public for benchmarking — prefer using [receiveFile] for real transfers.
  Future<Uint8List> performReceiverHandshake(PeerConnection connection) async {
    final init = await connection.waitFor(
      predicate: (m) => m is HandshakeMessage,
      timeout: const Duration(seconds: 15),
    ) as HandshakeMessage;

    // --- Version negotiation ---
    if (init.protocolVersion <
            SwiftDropConstants.minSupportedProtocolVersion ||
        init.protocolVersion > SwiftDropConstants.protocolVersion) {
      connection.send(ErrorMessage(
        errorCode: ProtocolErrorCode.versionMismatch,
        message: 'Unsupported protocol v${init.protocolVersion}'
            ' (supported: v${SwiftDropConstants.minSupportedProtocolVersion}'
            '-v${SwiftDropConstants.protocolVersion})',
      ));
      throw StateError(
        'Incompatible protocol version: ${init.protocolVersion}',
      );
    }

    final keyPair = encryptionService.generateKeyPair();

    connection.send(HandshakeMessage(
      type: MessageType.handshakeReply,
      protocolVersion: SwiftDropConstants.protocolVersion,
      publicKey: keyPair.publicKey,
      deviceName: deviceName,
      deviceId: deviceId,
    ));

    final sharedSecret = encryptionService.computeSharedSecret(
      privateKeyHex: keyPair.privateKey,
      remotePublicKeyBytes: init.publicKey,
    );

    final sessionKey = encryptionService.deriveSessionKey(sharedSecret);

    // Exchange confirmation hashes.
    final pairingHash = Uint8List.fromList(sha256.convert(sharedSecret).bytes);

    // Wait for sender's confirm.
    final senderConfirm = await connection.waitFor(
      predicate: (m) => m is HandshakeConfirmMessage,
      timeout: const Duration(seconds: 30),
    ) as HandshakeConfirmMessage;

    // Verify hashes match.
    var match = true;
    for (var i = 0; i < 32; i++) {
      if (senderConfirm.pairingHash[i] != pairingHash[i]) {
        match = false;
        break;
      }
    }

    if (!match) {
      connection.send(const ErrorMessage(
        errorCode: ProtocolErrorCode.pairingRejected,
        message: 'Pairing hash mismatch',
      ));
      throw StateError('Pairing verification failed — possible MITM attack');
    }

    // Send our confirm.
    connection.send(HandshakeConfirmMessage(pairingHash: pairingHash));

    return sessionKey;
  }

  // ---------------------------------------------------------------------------
  // Chunk transfer helpers
  // ---------------------------------------------------------------------------

  /// Sends a single chunk with retry logic on NACK.
  Future<bool> _sendChunkWithRetry({
    required PeerConnection connection,
    required Uint8List sessionKey,
    required FileChunk chunk,
    required File file,
    required FileChunker chunker,
  }) async {
    var currentChunk = chunk;

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      // Encrypt the chunk.
      final encrypted = encryptionService.encryptChunk(
        sessionKey: sessionKey,
        plaintext: currentChunk.data,
      );

      connection.send(ChunkDataMessage(
        chunkIndex: currentChunk.index,
        iv: encrypted.iv,
        encryptedData: encrypted.ciphertext,
        gcmTag: encrypted.tag,
        plaintextChecksum: currentChunk.checksum,
      ));

      final ack = await connection.waitFor(
        predicate: (m) =>
            (m is ChunkAckMessage && m.chunkIndex == currentChunk.index) ||
            (m is ChunkNackMessage && m.chunkIndex == currentChunk.index),
        timeout: const Duration(seconds: 30),
      );

      if (ack is ChunkAckMessage) return true;

      // NACK received — re-read chunk from disk for retry.
      currentChunk = await chunker.readChunk(file, currentChunk.index);
    }

    return false; // All retries exhausted.
  }

  void _emitProgress(
    TransferProgress progress,
    TransferProgressCallback? callback,
  ) {
    _progressController.add(progress);
    callback?.call(progress);
  }
}
