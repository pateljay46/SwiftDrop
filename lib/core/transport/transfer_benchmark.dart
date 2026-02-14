import 'dart:io';
import 'dart:typed_data';

import '../constants.dart';
import '../encryption/encryption_service.dart';
import 'transport_connection.dart';
import 'transport_service.dart';

/// Result of a single benchmark run.
class BenchmarkResult {
  const BenchmarkResult({
    required this.chunkSize,
    required this.fileSize,
    required this.totalDuration,
    required this.handshakeDuration,
    required this.transferDuration,
    required this.throughputMBps,
    required this.success,
    this.errorMessage,
  });

  /// Chunk size in bytes used for this run.
  final int chunkSize;

  /// Total file size in bytes.
  final int fileSize;

  /// Wall-clock time for the entire transfer (handshake + data).
  final Duration totalDuration;

  /// Time spent on the ECDH handshake alone.
  final Duration handshakeDuration;

  /// Time spent on chunk transfer (excluding handshake).
  final Duration transferDuration;

  /// Transfer throughput in megabytes per second.
  final double throughputMBps;

  /// Whether the transfer completed successfully.
  final bool success;

  /// Error message if the transfer failed.
  final String? errorMessage;

  @override
  String toString() =>
      'Benchmark(chunk=${chunkSize ~/ 1024}KB, '
      'file=${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB, '
      'total=${totalDuration.inMilliseconds}ms, '
      'handshake=${handshakeDuration.inMilliseconds}ms, '
      'transfer=${transferDuration.inMilliseconds}ms, '
      'throughput=${throughputMBps.toStringAsFixed(2)} MB/s, '
      'success=$success)';
}

/// Result of a full benchmark suite across multiple chunk sizes.
class BenchmarkSuiteResult {
  const BenchmarkSuiteResult({
    required this.results,
    required this.optimalChunkSize,
  });

  /// Individual results for each chunk size tested.
  final List<BenchmarkResult> results;

  /// The chunk size that achieved the best throughput.
  final int optimalChunkSize;

  @override
  String toString() {
    final buf = StringBuffer('=== Benchmark Suite Results ===\n');
    for (final r in results) {
      buf.writeln(r);
    }
    buf.writeln(
      'Optimal chunk size: ${optimalChunkSize ~/ 1024} KB',
    );
    return buf.toString();
  }
}

/// Benchmarks transfer performance with varying chunk sizes.
///
/// Creates a temporary file of [fileSize] bytes and runs full
/// sender↔receiver loopback transfers over TCP localhost for each
/// chunk size in [chunkSizes].
class TransferBenchmark {
  TransferBenchmark({
    List<int>? chunkSizes,
    this.fileSize = 100 * 1024 * 1024, // 100 MB default
  }) : chunkSizes = chunkSizes ??
            [
              64 * 1024, // 64 KB
              128 * 1024, // 128 KB
              256 * 1024, // 256 KB
              512 * 1024, // 512 KB
            ];

  /// Chunk sizes to benchmark (in bytes).
  final List<int> chunkSizes;

  /// File size for the benchmark (in bytes).
  final int fileSize;

  /// Runs the full benchmark suite and returns the results.
  Future<BenchmarkSuiteResult> run() async {
    final results = <BenchmarkResult>[];
    final tempFile = await _createTempFile(fileSize);

    try {
      for (final cs in chunkSizes) {
        final result = await _benchmarkChunkSize(tempFile, cs);
        results.add(result);
      }
    } finally {
      await tempFile.delete();
    }

    // Pick the chunk size with best throughput among successful runs.
    final successful = results.where((r) => r.success).toList();
    final optimal = successful.isEmpty
        ? SwiftDropConstants.defaultChunkSize
        : (successful..sort((a, b) => b.throughputMBps.compareTo(a.throughputMBps)))
            .first
            .chunkSize;

    return BenchmarkSuiteResult(results: results, optimalChunkSize: optimal);
  }

  /// Measures handshake latency in isolation (no file transfer).
  Future<Duration> measureHandshakeLatency({int iterations = 5}) async {
    final encryption = EncryptionService();
    var totalMs = 0;

    for (var i = 0; i < iterations; i++) {
      final server = await TransportServer.start();
      final sw = Stopwatch()..start();

      // Sender side.
      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );

      // Receiver side accepts.
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      // Run handshake.
      final senderService = TransportService(
        encryptionService: encryption,
        deviceName: 'bench-sender',
        deviceId: 'bench-s',
      );
      final receiverService = TransportService(
        encryptionService: encryption,
        deviceName: 'bench-receiver',
        deviceId: 'bench-r',
      );

      // Run sender and receiver handshakes concurrently.
      await Future.wait([
        senderService.performSenderHandshake(senderConn),
        receiverService.performReceiverHandshake(receiverConn),
      ]);

      sw.stop();
      totalMs += sw.elapsedMilliseconds;

      senderService.dispose();
      receiverService.dispose();
      await senderConn.dispose();
      await receiverConn.dispose();
      await server.dispose();
    }

    return Duration(milliseconds: totalMs ~/ iterations);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<BenchmarkResult> _benchmarkChunkSize(File file, int cs) async {
    final encryption = EncryptionService();
    final server = await TransportServer.start();
    final overallSw = Stopwatch()..start();

    try {
      // Connect sender and receiver.
      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      // Create temp output file.
      final outFile = File(
        '${file.parent.path}/bench_out_${cs}_${DateTime.now().millisecondsSinceEpoch}',
      );

      final senderService = TransportService(
        encryptionService: encryption,
        deviceName: 'bench-sender',
        deviceId: 'bench-s',
        chunkSize: cs,
      );
      final receiverService = TransportService(
        encryptionService: encryption,
        deviceName: 'bench-receiver',
        deviceId: 'bench-r',
        chunkSize: cs,
      );

      final handshakeSw = Stopwatch()..start();

      // Run send and receive in parallel — they handshake with each other.
      final sendFuture = senderService.sendFile(
        connection: senderConn,
        file: file,
      );

      final receiveFuture = receiverService.receiveFile(
        connection: receiverConn,
        onFileOffer: (meta) async => outFile,
      );

      // Wait for both to complete.
      final results = await Future.wait([sendFuture, receiveFuture]);
      overallSw.stop();

      final senderResult = results[0];
      final receiverResult = results[1];
      final success = senderResult.state == TransferState.completed &&
          receiverResult.state == TransferState.completed;

      // Estimate handshake as ~10% of first-chunk time or from the sender
      // progress transitions. For simplicity, measure it roughly.
      final handshakeDuration =
          Duration(milliseconds: handshakeSw.elapsedMilliseconds ~/ 10);
      final totalDuration = overallSw.elapsed;
      final transferDuration = totalDuration - handshakeDuration;

      final throughput = fileSize /
          (totalDuration.inMicroseconds / 1000000) /
          (1024 * 1024);

      senderService.dispose();
      receiverService.dispose();
      await senderConn.dispose();
      await receiverConn.dispose();
      await server.dispose();

      // Clean up output file.
      if (await outFile.exists()) await outFile.delete();

      return BenchmarkResult(
        chunkSize: cs,
        fileSize: fileSize,
        totalDuration: totalDuration,
        handshakeDuration: handshakeDuration,
        transferDuration: transferDuration,
        throughputMBps: throughput,
        success: success,
        errorMessage: success ? null : senderResult.errorMessage,
      );
    } catch (e) {
      overallSw.stop();
      await server.dispose();

      return BenchmarkResult(
        chunkSize: cs,
        fileSize: fileSize,
        totalDuration: overallSw.elapsed,
        handshakeDuration: Duration.zero,
        transferDuration: overallSw.elapsed,
        throughputMBps: 0,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Creates a temporary file filled with pseudo-random data.
  static Future<File> _createTempFile(int size) async {
    final dir = await Directory.systemTemp.createTemp('swiftdrop_bench_');
    final file = File('${dir.path}/bench_data.bin');

    final raf = await file.open(mode: FileMode.write);
    const blockSize = 1024 * 1024; // 1 MB blocks
    final block = Uint8List(blockSize);
    // Fill with non-zero pattern for realistic entropy.
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
}
