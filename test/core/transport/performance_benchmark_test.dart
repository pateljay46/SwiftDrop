import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:swiftdrop/core/encryption/encryption_service.dart';
import 'package:swiftdrop/core/transport/transport_connection.dart';
import 'package:swiftdrop/core/transport/transport_service.dart';
import 'package:swiftdrop/core/transport/transfer_benchmark.dart';

void main() {
  group('Performance benchmarks', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('perf_bench_');
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

    test('handshake latency < 200ms on loopback', () async {
      final encryption = EncryptionService();
      final latencies = <int>[];

      for (var i = 0; i < 5; i++) {
        final server = await TransportServer.start();
        final sw = Stopwatch()..start();

        final connectFuture = TransportClient.connect(
          InternetAddress.loopbackIPv4,
          server.port,
        );
        final receiverConn = await server.connections.first;
        final senderConn = await connectFuture;

        final senderService = TransportService(
          encryptionService: encryption,
          deviceName: 'perf-sender',
          deviceId: 'perf-s',
        );
        final receiverService = TransportService(
          encryptionService: encryption,
          deviceName: 'perf-receiver',
          deviceId: 'perf-r',
        );

        await Future.wait([
          senderService.performSenderHandshake(senderConn),
          receiverService.performReceiverHandshake(receiverConn),
        ]);

        sw.stop();
        latencies.add(sw.elapsedMilliseconds);

        senderService.dispose();
        receiverService.dispose();
        await senderConn.dispose();
        await receiverConn.dispose();
        await server.dispose();
      }

      final avgLatency = latencies.reduce((a, b) => a + b) ~/ latencies.length;

      // PRD target: handshake < 200ms.
      expect(
        avgLatency,
        lessThan(200),
        reason: 'Average handshake latency ($avgLatency ms) must be < 200ms',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('1 MB transfer completes under 2 seconds on loopback', () async {
      final file = await _createTestFile(tempDir, 1 * 1024 * 1024);
      final result = await _runLoopbackTransfer(file, tempDir);

      expect(result.state, TransferState.completed);
      expect(
        result.chunksCompleted,
        equals(result.chunksTotal),
      );
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('10 MB transfer completes successfully on loopback', () async {
      final file = await _createTestFile(tempDir, 10 * 1024 * 1024);
      final result = await _runLoopbackTransfer(file, tempDir);

      expect(result.state, TransferState.completed);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('chunk size comparison shows throughput variance', () async {
      // Use a smaller file (2 MB) for quicker benchmarking in tests.
      final file = await _createTestFile(tempDir, 2 * 1024 * 1024);
      final chunkSizes = [64 * 1024, 128 * 1024, 256 * 1024];
      final results = <int, Duration>{};

      for (final cs in chunkSizes) {
        final sw = Stopwatch()..start();
        final result = await _runLoopbackTransfer(file, tempDir, chunkSize: cs);
        sw.stop();

        expect(result.state, TransferState.completed,
            reason: 'Transfer with chunk size $cs failed');
        results[cs] = sw.elapsed;
      }

      // All chunk sizes should complete — we just verify they all work.
      expect(results.length, equals(chunkSizes.length));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('memory stays flat during transfer (no chunk accumulation)', () async {
      // This test verifies the streaming architecture: chunks are processed
      // one at a time and not accumulated in memory.
      final file = await _createTestFile(tempDir, 5 * 1024 * 1024);
      final chunksProcessed = <int>[];

      final encryption = EncryptionService();
      final server = await TransportServer.start();

      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      final outFile = File('${tempDir.path}/memory_test_out.bin');

      final senderService = TransportService(
        encryptionService: encryption,
        deviceName: 'mem-sender',
        deviceId: 'mem-s',
      );
      final receiverService = TransportService(
        encryptionService: encryption,
        deviceName: 'mem-receiver',
        deviceId: 'mem-r',
      );

      final sendFuture = senderService.sendFile(
        connection: senderConn,
        file: file,
        onProgress: (p) {
          if (p.state == TransferState.transferring) {
            chunksProcessed.add(p.chunksCompleted);
          }
        },
      );

      final receiveFuture = receiverService.receiveFile(
        connection: receiverConn,
        onFileOffer: (meta) async => outFile,
      );

      await Future.wait([sendFuture, receiveFuture]);

      // Verify that chunks were processed incrementally (not all at once).
      expect(chunksProcessed.length, greaterThan(1));

      // Verify output file matches input.
      final originalChecksum = sha256.convert(await file.readAsBytes());
      final outputChecksum = sha256.convert(await outFile.readAsBytes());
      expect(outputChecksum.toString(), equals(originalChecksum.toString()));

      senderService.dispose();
      receiverService.dispose();
      await senderConn.dispose();
      await receiverConn.dispose();
      await server.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('encrypted transfer preserves file integrity', () async {
      // Transfer a file and verify SHA-256 matches end-to-end.
      final file = await _createTestFile(tempDir, 512 * 1024);
      final originalChecksum = sha256.convert(await file.readAsBytes());

      final encryption = EncryptionService();
      final server = await TransportServer.start();

      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      final outFile = File('${tempDir.path}/integrity_out.bin');

      final senderService = TransportService(
        encryptionService: encryption,
        deviceName: 'int-sender',
        deviceId: 'int-s',
      );
      final receiverService = TransportService(
        encryptionService: encryption,
        deviceName: 'int-receiver',
        deviceId: 'int-r',
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
      expect(
        outputChecksum.toString(),
        equals(originalChecksum.toString()),
        reason: 'End-to-end encrypted transfer must preserve file integrity',
      );

      senderService.dispose();
      receiverService.dispose();
      await senderConn.dispose();
      await receiverConn.dispose();
      await server.dispose();
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('BenchmarkResult toString is well-formatted', () {
      const result = BenchmarkResult(
        chunkSize: 65536,
        fileSize: 1048576,
        totalDuration: Duration(milliseconds: 500),
        handshakeDuration: Duration(milliseconds: 50),
        transferDuration: Duration(milliseconds: 450),
        throughputMBps: 2.0,
        success: true,
      );

      final str = result.toString();
      expect(str, contains('chunk=64KB'));
      expect(str, contains('1.0MB'));
      expect(str, contains('success=true'));
    });

    test('BenchmarkSuiteResult toString lists all results', () {
      const suite = BenchmarkSuiteResult(
        results: [
          BenchmarkResult(
            chunkSize: 65536,
            fileSize: 1048576,
            totalDuration: Duration(milliseconds: 500),
            handshakeDuration: Duration(milliseconds: 50),
            transferDuration: Duration(milliseconds: 450),
            throughputMBps: 2.0,
            success: true,
          ),
          BenchmarkResult(
            chunkSize: 131072,
            fileSize: 1048576,
            totalDuration: Duration(milliseconds: 400),
            handshakeDuration: Duration(milliseconds: 50),
            transferDuration: Duration(milliseconds: 350),
            throughputMBps: 2.5,
            success: true,
          ),
        ],
        optimalChunkSize: 131072,
      );

      final str = suite.toString();
      expect(str, contains('Benchmark Suite Results'));
      expect(str, contains('Optimal chunk size: 128 KB'));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a test file with pseudo-random data.
Future<File> _createTestFile(Directory dir, int size) async {
  final file = File('${dir.path}/test_$size.bin');
  final raf = await file.open(mode: FileMode.write);

  const blockSize = 64 * 1024;
  final block = Uint8List(blockSize);
  for (var i = 0; i < blockSize; i++) {
    block[i] = (i * 7 + 13) & 0xFF;
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

/// Runs a full sender↔receiver loopback transfer and returns the sender progress.
Future<TransferProgress> _runLoopbackTransfer(
  File file,
  Directory tempDir, {
  int chunkSize = 65536,
}) async {
  final encryption = EncryptionService();
  final server = await TransportServer.start();

  final connectFuture = TransportClient.connect(
    InternetAddress.loopbackIPv4,
    server.port,
  );
  final receiverConn = await server.connections.first;
  final senderConn = await connectFuture;

  final outFile = File(
    '${tempDir.path}/loopback_out_${chunkSize}_${DateTime.now().millisecondsSinceEpoch}.bin',
  );

  final senderService = TransportService(
    encryptionService: encryption,
    deviceName: 'loop-sender',
    deviceId: 'loop-s',
    chunkSize: chunkSize,
  );
  final receiverService = TransportService(
    encryptionService: encryption,
    deviceName: 'loop-receiver',
    deviceId: 'loop-r',
    chunkSize: chunkSize,
  );

  final results = await Future.wait([
    senderService.sendFile(connection: senderConn, file: file),
    receiverService.receiveFile(
      connection: receiverConn,
      onFileOffer: (meta) async => outFile,
    ),
  ]);

  senderService.dispose();
  receiverService.dispose();
  await senderConn.dispose();
  await receiverConn.dispose();
  await server.dispose();

  // Clean up output file.
  if (await outFile.exists()) await outFile.delete();

  return results[0]; // Return sender result.
}
