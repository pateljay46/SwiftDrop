import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:swiftdrop/core/encryption/encryption_service.dart';
import 'package:swiftdrop/core/transport/transport_connection.dart';
import 'package:swiftdrop/core/transport/transport_service.dart';
import 'package:swiftdrop/core/discovery/device_model.dart';
import 'package:swiftdrop/core/controller/transfer_controller.dart';

void main() {
  group('Stress tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stress_test_');
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

    // -----------------------------------------------------------------------
    // Large file transfers
    // -----------------------------------------------------------------------

    test('50 MB file transfers successfully on loopback', () async {
      final file = await _createTestFile(tempDir, 50 * 1024 * 1024);
      final originalChecksum = sha256.convert(await file.readAsBytes());

      final result = await _runTransfer(file, tempDir);
      expect(result.senderProgress.state, TransferState.completed);
      expect(result.receiverProgress.state, TransferState.completed);

      // Verify file integrity.
      final outputChecksum = sha256.convert(
        await result.outputFile.readAsBytes(),
      );
      expect(outputChecksum.toString(), equals(originalChecksum.toString()));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('file exactly at chunk boundary transfers correctly', () async {
      // Exactly 4 chunks of 64KB.
      final file = await _createTestFile(tempDir, 65536 * 4);
      final originalChecksum = sha256.convert(await file.readAsBytes());

      final result = await _runTransfer(file, tempDir);
      expect(result.senderProgress.state, TransferState.completed);
      expect(result.senderProgress.chunksTotal, equals(4));

      final outputChecksum = sha256.convert(
        await result.outputFile.readAsBytes(),
      );
      expect(outputChecksum.toString(), equals(originalChecksum.toString()));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('file one byte over chunk boundary transfers correctly', () async {
      // 4 full chunks + 1 byte.
      final file = await _createTestFile(tempDir, 65536 * 4 + 1);
      final result = await _runTransfer(file, tempDir);

      expect(result.senderProgress.state, TransferState.completed);
      expect(result.senderProgress.chunksTotal, equals(5));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('very small file (1 byte) transfers correctly', () async {
      final file = File('${tempDir.path}/tiny.bin');
      await file.writeAsBytes([42]);

      final result = await _runTransfer(file, tempDir);
      expect(result.senderProgress.state, TransferState.completed);
      expect(result.senderProgress.chunksTotal, equals(1));

      final outputBytes = await result.outputFile.readAsBytes();
      expect(outputBytes, equals([42]));
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('empty file (0 bytes) transfers correctly', () async {
      final file = File('${tempDir.path}/empty.bin');
      await file.writeAsBytes([]);

      final result = await _runTransfer(file, tempDir);
      expect(result.senderProgress.state, TransferState.completed);
    }, timeout: const Timeout(Duration(seconds: 15)));

    // -----------------------------------------------------------------------
    // Multiple sequential transfers
    // -----------------------------------------------------------------------

    test('3 sequential transfers succeed', () async {
      for (var i = 0; i < 3; i++) {
        final file = await _createTestFile(tempDir, 256 * 1024);
        final result = await _runTransfer(
          file,
          tempDir,
          label: 'seq_$i',
        );
        expect(
          result.senderProgress.state,
          TransferState.completed,
          reason: 'Sequential transfer $i should complete',
        );
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('sequential transfers with different chunk sizes', () async {
      final chunkSizes = [64 * 1024, 128 * 1024, 256 * 1024];

      for (final cs in chunkSizes) {
        final file = await _createTestFile(tempDir, 512 * 1024);
        final result = await _runTransfer(
          file,
          tempDir,
          chunkSize: cs,
          label: 'cs_$cs',
        );
        expect(
          result.senderProgress.state,
          TransferState.completed,
          reason: 'Transfer with chunk size $cs should complete',
        );
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    // -----------------------------------------------------------------------
    // Concurrency / Transfer Controller
    // -----------------------------------------------------------------------

    test('TransferController enforces concurrency limit', () async {
      final encryption = EncryptionService();
      final controller = TransferController(
        encryptionService: encryption,
        deviceName: 'stress-test',
        deviceId: 'stress-id',
        maxConcurrentTransfers: 1,
      );

      final device = DeviceModel(
        id: 'test-device',
        name: 'Test Device',
        ipAddress: '127.0.0.1',
        port: 9999,
        deviceType: DeviceType.windows,
      );

      // Fill up the single concurrent slot by sending a file.
      final file = await _createTestFile(tempDir, 1024);
      await controller.sendFile(device: device, file: file);

      // Second send should throw due to concurrency limit.
      expect(
        () => controller.sendFile(device: device, file: file),
        throwsStateError,
      );

      await controller.dispose();
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('TransferController startReceiving returns valid port', () async {
      final encryption = EncryptionService();
      final controller = TransferController(
        encryptionService: encryption,
        deviceName: 'recv-test',
        deviceId: 'recv-id',
      );

      final port = await controller.startReceiving();
      expect(port, greaterThan(0));

      // Calling again returns same port.
      final samePort = await controller.startReceiving();
      expect(samePort, equals(port));

      await controller.stopReceiving();
      await controller.dispose();
    }, timeout: const Timeout(Duration(seconds: 10)));

    // -----------------------------------------------------------------------
    // Discovery with many devices
    // -----------------------------------------------------------------------

    test('DeviceModel handles 10+ devices without issues', () {
      final devices = List.generate(
        15,
        (i) => DeviceModel(
          id: 'device-$i',
          name: 'Device $i',
          ipAddress: '192.168.1.${10 + i}',
          port: 5000 + i,
          deviceType: DeviceType.values[i % DeviceType.values.length],
        ),
      );

      expect(devices.length, equals(15));
      // Unique IDs.
      final ids = devices.map((d) => d.id).toSet();
      expect(ids.length, equals(15));

      // No duplicate IP addresses.
      final ips = devices.map((d) => d.ipAddress).toSet();
      expect(ips.length, equals(15));
    });

    // -----------------------------------------------------------------------
    // Progress callback completeness
    // -----------------------------------------------------------------------

    test('progress events cover all states during transfer', () async {
      final file = await _createTestFile(tempDir, 200 * 1024);
      final senderStates = <TransferState>[];
      final receiverStates = <TransferState>[];

      final encryption = EncryptionService();
      final server = await TransportServer.start();

      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      final outFile = File('${tempDir.path}/progress_test_out.bin');

      final senderService = TransportService(
        encryptionService: encryption,
        deviceName: 'prog-sender',
        deviceId: 'prog-s',
      );
      final receiverService = TransportService(
        encryptionService: encryption,
        deviceName: 'prog-receiver',
        deviceId: 'prog-r',
      );

      await Future.wait([
        senderService.sendFile(
          connection: senderConn,
          file: file,
          onProgress: (p) => senderStates.add(p.state),
        ),
        receiverService.receiveFile(
          connection: receiverConn,
          onFileOffer: (meta) async => outFile,
          onProgress: (p) => receiverStates.add(p.state),
        ),
      ]);

      // Sender should see: handshaking → awaitingAccept → transferring → verifying → completed.
      expect(senderStates, contains(TransferState.handshaking));
      expect(senderStates, contains(TransferState.awaitingAccept));
      expect(senderStates, contains(TransferState.transferring));
      expect(senderStates, contains(TransferState.verifying));
      expect(senderStates, contains(TransferState.completed));

      // Receiver should see: handshaking → awaitingAccept → transferring → verifying → completed.
      expect(receiverStates, contains(TransferState.handshaking));
      expect(receiverStates, contains(TransferState.awaitingAccept));
      expect(receiverStates, contains(TransferState.transferring));
      expect(receiverStates, contains(TransferState.completed));

      senderService.dispose();
      receiverService.dispose();
      await senderConn.dispose();
      await receiverConn.dispose();
      await server.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    // -----------------------------------------------------------------------
    // Rapid server start/stop cycles
    // -----------------------------------------------------------------------

    test('rapid server start/stop cycles do not leak', () async {
      for (var i = 0; i < 10; i++) {
        final server = await TransportServer.start();
        expect(server.isListening, isTrue);
        expect(server.port, greaterThan(0));
        await server.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('multiple transfers with varying file sizes', () async {
      final fileSizes = [1024, 10 * 1024, 100 * 1024, 1 * 1024 * 1024];

      for (final size in fileSizes) {
        final file = await _createTestFile(tempDir, size);
        final result = await _runTransfer(file, tempDir, label: 'size_$size');

        expect(
          result.senderProgress.state,
          TransferState.completed,
          reason: 'Transfer of $size bytes should complete',
        );
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _TransferResult {
  const _TransferResult({
    required this.senderProgress,
    required this.receiverProgress,
    required this.outputFile,
  });

  final TransferProgress senderProgress;
  final TransferProgress receiverProgress;
  final File outputFile;
}

Future<_TransferResult> _runTransfer(
  File file,
  Directory tempDir, {
  int chunkSize = 65536,
  String label = 'default',
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
    '${tempDir.path}/stress_out_${label}_${DateTime.now().millisecondsSinceEpoch}.bin',
  );

  final senderService = TransportService(
    encryptionService: encryption,
    deviceName: 'stress-sender',
    deviceId: 'stress-s',
    chunkSize: chunkSize,
  );
  final receiverService = TransportService(
    encryptionService: encryption,
    deviceName: 'stress-receiver',
    deviceId: 'stress-r',
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

  return _TransferResult(
    senderProgress: results[0],
    receiverProgress: results[1],
    outputFile: outFile,
  );
}

Future<File> _createTestFile(Directory dir, int size) async {
  final file = File(
    '${dir.path}/test_${size}_${DateTime.now().millisecondsSinceEpoch}.bin',
  );
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
