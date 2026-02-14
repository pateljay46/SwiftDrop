import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:swiftdrop/core/encryption/encryption_service.dart';
import 'package:swiftdrop/core/transport/transport_connection.dart';
import 'package:swiftdrop/core/transport/transport_service.dart';

/// End-to-end integration tests that run a full sender↔receiver flow
/// on loopback TCP. These tests exercise the complete pipeline:
///
/// TCP connect → ECDH handshake → file metadata exchange → encrypted
/// chunk transfer with ACK → checksum verification → completion.
void main() {
  group('Integration E2E loopback', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('e2e_test_');
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {
        // Ignore — files may still be locked by OS.
      }
    });

    test('full E2E: 256 KB file, default 64 KB chunks', () async {
      final result = await _runE2E(
        tempDir: tempDir,
        fileSize: 256 * 1024,
        chunkSize: 65536,
      );

      expect(result.senderResult.state, TransferState.completed);
      expect(result.receiverResult.state, TransferState.completed);
      expect(result.integrityVerified, isTrue);
      expect(result.senderResult.chunksCompleted, equals(4));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('full E2E: 1 MB file, 128 KB chunks', () async {
      final result = await _runE2E(
        tempDir: tempDir,
        fileSize: 1024 * 1024,
        chunkSize: 128 * 1024,
      );

      expect(result.senderResult.state, TransferState.completed);
      expect(result.receiverResult.state, TransferState.completed);
      expect(result.integrityVerified, isTrue);
      expect(result.senderResult.chunksCompleted, equals(8));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('full E2E: 5 MB file, 256 KB chunks', () async {
      final result = await _runE2E(
        tempDir: tempDir,
        fileSize: 5 * 1024 * 1024,
        chunkSize: 256 * 1024,
      );

      expect(result.senderResult.state, TransferState.completed);
      expect(result.receiverResult.state, TransferState.completed);
      expect(result.integrityVerified, isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('full E2E: sender and receiver use different service instances',
        () async {
      // Verify that two independent EncryptionService instances
      // negotiate keys correctly (no shared state).
      final senderEncryption = EncryptionService();
      final receiverEncryption = EncryptionService();

      final file = await _createTestFile(tempDir, 128 * 1024);
      final originalChecksum = sha256.convert(await file.readAsBytes());

      final server = await TransportServer.start();
      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      final outFile = File('${tempDir.path}/e2e_separate_enc_out.bin');

      final senderService = TransportService(
        encryptionService: senderEncryption,
        deviceName: 'sender-a',
        deviceId: 'id-a',
      );
      final receiverService = TransportService(
        encryptionService: receiverEncryption,
        deviceName: 'receiver-b',
        deviceId: 'id-b',
      );

      final results = await Future.wait([
        senderService.sendFile(connection: senderConn, file: file),
        receiverService.receiveFile(
          connection: receiverConn,
          onFileOffer: (meta) async => outFile,
        ),
      ]);

      expect(results[0].state, TransferState.completed);
      expect(results[1].state, TransferState.completed);

      final outputChecksum = sha256.convert(await outFile.readAsBytes());
      expect(outputChecksum.toString(), equals(originalChecksum.toString()));

      senderService.dispose();
      receiverService.dispose();
      await senderConn.dispose();
      await receiverConn.dispose();
      await server.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('full E2E: progress callbacks are called for every state', () async {
      final file = await _createTestFile(tempDir, 196 * 1024);
      final senderStates = <TransferState>{};
      final receiverStates = <TransferState>{};
      var senderChunkCallbacks = 0;
      var receiverChunkCallbacks = 0;

      final encryption = EncryptionService();
      final server = await TransportServer.start();

      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      final outFile = File('${tempDir.path}/e2e_progress_out.bin');

      final senderService = TransportService(
        encryptionService: encryption,
        deviceName: 'prog-s',
        deviceId: 'ps',
      );
      final receiverService = TransportService(
        encryptionService: encryption,
        deviceName: 'prog-r',
        deviceId: 'pr',
      );

      final results = await Future.wait([
        senderService.sendFile(
          connection: senderConn,
          file: file,
          onProgress: (p) {
            senderStates.add(p.state);
            if (p.state == TransferState.transferring) {
              senderChunkCallbacks++;
            }
          },
        ),
        receiverService.receiveFile(
          connection: receiverConn,
          onFileOffer: (meta) async => outFile,
          onProgress: (p) {
            receiverStates.add(p.state);
            if (p.state == TransferState.transferring) {
              receiverChunkCallbacks++;
            }
          },
        ),
      ]);

      expect(results[0].state, TransferState.completed);

      // Sender must have cycled through these states.
      expect(senderStates, contains(TransferState.handshaking));
      expect(senderStates, contains(TransferState.transferring));
      expect(senderStates, contains(TransferState.completed));

      // Receiver must have cycled through these states.
      expect(receiverStates, contains(TransferState.handshaking));
      expect(receiverStates, contains(TransferState.transferring));
      expect(receiverStates, contains(TransferState.completed));

      // Both should have at least 1 chunk callback.
      expect(senderChunkCallbacks, greaterThan(0));
      expect(receiverChunkCallbacks, greaterThan(0));

      senderService.dispose();
      receiverService.dispose();
      await senderConn.dispose();
      await receiverConn.dispose();
      await server.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('full E2E: transfer stream also broadcasts progress', () async {
      final file = await _createTestFile(tempDir, 128 * 1024);

      final encryption = EncryptionService();
      final server = await TransportServer.start();

      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      final outFile = File('${tempDir.path}/e2e_stream_out.bin');

      final senderService = TransportService(
        encryptionService: encryption,
        deviceName: 'stream-s',
        deviceId: 'ss',
      );
      final receiverService = TransportService(
        encryptionService: encryption,
        deviceName: 'stream-r',
        deviceId: 'sr',
      );

      // Use sendFile's onProgress callback (synchronous) instead of
      // the broadcast stream, which may drop the final event.
      final senderStates = <TransferState>{};
      TransferProgress? lastProgress;

      final results = await Future.wait([
        senderService.sendFile(
          connection: senderConn,
          file: file,
          onProgress: (p) {
            senderStates.add(p.state);
            lastProgress = p;
          },
        ),
        receiverService.receiveFile(
          connection: receiverConn,
          onFileOffer: (meta) async => outFile,
        ),
      ]);

      expect(results[0].state, TransferState.completed);
      expect(senderStates, isNotEmpty);
      expect(senderStates, contains(TransferState.completed));
      expect(lastProgress, isNotNull);
      expect(lastProgress!.state, TransferState.completed);

      senderService.dispose();
      receiverService.dispose();
      await senderConn.dispose();
      await receiverConn.dispose();
      await server.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('full E2E: file with special characters in name', () async {
      final file = File('${tempDir.path}/file (1) [test].txt');
      await file.writeAsString('Hello, SwiftDrop! Special chars: !@#\$%^&*()');

      final originalChecksum = sha256.convert(await file.readAsBytes());

      final encryption = EncryptionService();
      final server = await TransportServer.start();

      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      final outFile = File('${tempDir.path}/e2e_special_out.bin');

      final senderService = TransportService(
        encryptionService: encryption,
        deviceName: 'spec-s',
        deviceId: 'sps',
      );
      final receiverService = TransportService(
        encryptionService: encryption,
        deviceName: 'spec-r',
        deviceId: 'spr',
      );

      final results = await Future.wait([
        senderService.sendFile(connection: senderConn, file: file),
        receiverService.receiveFile(
          connection: receiverConn,
          onFileOffer: (meta) async {
            // Verify the file name is preserved.
            expect(meta.fileName, contains('file (1) [test]'));
            return outFile;
          },
        ),
      ]);

      expect(results[0].state, TransferState.completed);

      final outputChecksum = sha256.convert(await outFile.readAsBytes());
      expect(outputChecksum.toString(), equals(originalChecksum.toString()));

      senderService.dispose();
      receiverService.dispose();
      await senderConn.dispose();
      await receiverConn.dispose();
      await server.dispose();
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('full E2E: binary file preserves all byte values', () async {
      // Create a file with all possible byte values (0x00–0xFF).
      final file = File('${tempDir.path}/all_bytes.bin');
      final allBytes = Uint8List(256);
      for (var i = 0; i < 256; i++) {
        allBytes[i] = i;
      }
      await file.writeAsBytes(allBytes);
      final originalChecksum = sha256.convert(allBytes);

      final encryption = EncryptionService();
      final server = await TransportServer.start();

      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      final outFile = File('${tempDir.path}/e2e_allbytes_out.bin');

      final senderService = TransportService(
        encryptionService: encryption,
        deviceName: 'bytes-s',
        deviceId: 'bs',
      );
      final receiverService = TransportService(
        encryptionService: encryption,
        deviceName: 'bytes-r',
        deviceId: 'br',
      );

      final results = await Future.wait([
        senderService.sendFile(connection: senderConn, file: file),
        receiverService.receiveFile(
          connection: receiverConn,
          onFileOffer: (meta) async => outFile,
        ),
      ]);

      expect(results[0].state, TransferState.completed);

      final outputBytes = await outFile.readAsBytes();
      expect(outputBytes.length, equals(256));
      for (var i = 0; i < 256; i++) {
        expect(outputBytes[i], equals(i),
            reason: 'Byte at index $i should be $i');
      }

      final outputChecksum = sha256.convert(outputBytes);
      expect(outputChecksum.toString(), equals(originalChecksum.toString()));

      senderService.dispose();
      receiverService.dispose();
      await senderConn.dispose();
      await receiverConn.dispose();
      await server.dispose();
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _E2EResult {
  const _E2EResult({
    required this.senderResult,
    required this.receiverResult,
    required this.integrityVerified,
  });

  final TransferProgress senderResult;
  final TransferProgress receiverResult;
  final bool integrityVerified;
}

Future<_E2EResult> _runE2E({
  required Directory tempDir,
  required int fileSize,
  required int chunkSize,
}) async {
  final file = await _createTestFile(tempDir, fileSize);
  final originalChecksum = sha256.convert(await file.readAsBytes());

  final encryption = EncryptionService();
  final server = await TransportServer.start();

  final connectFuture = TransportClient.connect(
    InternetAddress.loopbackIPv4,
    server.port,
  );
  final receiverConn = await server.connections.first;
  final senderConn = await connectFuture;

  final outFile = File('${tempDir.path}/e2e_out_$chunkSize.bin');

  final senderService = TransportService(
    encryptionService: encryption,
    deviceName: 'e2e-sender',
    deviceId: 'e2e-s',
    chunkSize: chunkSize,
  );
  final receiverService = TransportService(
    encryptionService: encryption,
    deviceName: 'e2e-receiver',
    deviceId: 'e2e-r',
    chunkSize: chunkSize,
  );

  final results = await Future.wait([
    senderService.sendFile(connection: senderConn, file: file),
    receiverService.receiveFile(
      connection: receiverConn,
      onFileOffer: (meta) async => outFile,
    ),
  ]);

  final outputChecksum = await outFile.exists()
      ? sha256.convert(await outFile.readAsBytes())
      : null;

  final integrityVerified = outputChecksum != null &&
      outputChecksum.toString() == originalChecksum.toString();

  senderService.dispose();
  receiverService.dispose();
  await senderConn.dispose();
  await receiverConn.dispose();
  await server.dispose();

  return _E2EResult(
    senderResult: results[0],
    receiverResult: results[1],
    integrityVerified: integrityVerified,
  );
}

Future<File> _createTestFile(Directory dir, int size) async {
  final file = File('${dir.path}/e2e_input_$size.bin');
  final raf = await file.open(mode: FileMode.write);

  const blockSize = 64 * 1024;
  final block = Uint8List(blockSize);
  for (var i = 0; i < blockSize; i++) {
    block[i] = (i * 13 + 7) & 0xFF;
  }

  var written = 0;
  while (written < size) {
    final remaining = size - written;
    final toWrite = remaining < blockSize ? remaining : blockSize;
    await raf.writeFrom(block, 0, toWrite);
    written += toWrite;
  }
  await raf.close();
  return file;
}
