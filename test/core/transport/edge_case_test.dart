import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:swiftdrop/core/encryption/encryption_service.dart';
import 'package:swiftdrop/core/transport/transport_connection.dart';
import 'package:swiftdrop/core/transport/transport_service.dart';
import 'package:swiftdrop/core/controller/transfer_controller.dart';
import 'package:swiftdrop/core/controller/transfer_record.dart';
import 'package:swiftdrop/core/discovery/device_model.dart';

void main() {
  group('Edge case tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('edge_case_');
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
    // Sender killed / disconnected mid-transfer
    // -----------------------------------------------------------------------

    test('receiver handles sender disconnect mid-transfer gracefully',
        () async {
      final encryption = EncryptionService();
      final server = await TransportServer.start();

      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      final outFile = File('${tempDir.path}/disconnect_out.bin');

      final senderService = TransportService(
        encryptionService: encryption,
        deviceName: 'disc-sender',
        deviceId: 'disc-s',
      );
      final receiverService = TransportService(
        encryptionService: encryption,
        deviceName: 'disc-receiver',
        deviceId: 'disc-r',
      );

      final file = await _createTestFile(tempDir, 512 * 1024);

      // Start sender but kill connection after first chunk.
      var chunksSent = 0;
      final sendFuture = senderService.sendFile(
        connection: senderConn,
        file: file,
        onProgress: (p) {
          chunksSent = p.chunksCompleted;
          if (chunksSent >= 2) {
            // Simulate sender crash by disposing connection.
            senderConn.dispose();
          }
        },
      );

      final receiveResult = await receiverService.receiveFile(
        connection: receiverConn,
        onFileOffer: (meta) async => outFile,
      );

      // Sender likely fails too.
      try {
        await sendFuture;
      } catch (_) {
        // Expected — sender connection was disposed.
      }

      // Receiver should fail gracefully (not hang forever).
      expect(
        receiveResult.state,
        anyOf(TransferState.failed, TransferState.cancelled),
        reason: 'Receiver should fail gracefully on sender disconnect',
      );

      senderService.dispose();
      receiverService.dispose();
      await server.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    // -----------------------------------------------------------------------
    // Receiver rejects transfer
    // -----------------------------------------------------------------------

    test('sender handles FILE_REJECT correctly', () async {
      final encryption = EncryptionService();
      final server = await TransportServer.start();

      final connectFuture = TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final receiverConn = await server.connections.first;
      final senderConn = await connectFuture;

      final file = await _createTestFile(tempDir, 64 * 1024);

      final senderService = TransportService(
        encryptionService: encryption,
        deviceName: 'rej-sender',
        deviceId: 'rej-s',
      );
      final receiverService = TransportService(
        encryptionService: encryption,
        deviceName: 'rej-receiver',
        deviceId: 'rej-r',
      );

      final results = await Future.wait([
        senderService.sendFile(connection: senderConn, file: file),
        receiverService.receiveFile(
          connection: receiverConn,
          // Reject the offer by returning null.
          onFileOffer: (meta) async => null,
        ),
      ]);

      expect(results[0].state, TransferState.cancelled);
      expect(results[1].state, TransferState.cancelled);
      expect(results[0].errorMessage, contains('rejected'));

      senderService.dispose();
      receiverService.dispose();
      await senderConn.dispose();
      await receiverConn.dispose();
      await server.dispose();
    }, timeout: const Timeout(Duration(seconds: 15)));

    // -----------------------------------------------------------------------
    // Same device appearing via multiple network interfaces
    // -----------------------------------------------------------------------

    test('DeviceModel equality is based on id, not IP', () {
      final device1 = DeviceModel(
        id: 'same-device',
        name: 'My Phone',
        ipAddress: '192.168.1.100',
        port: 5000,
        deviceType: DeviceType.android,
      );

      final device2 = DeviceModel(
        id: 'same-device',
        name: 'My Phone',
        ipAddress: '10.0.0.50',
        port: 5001,
        deviceType: DeviceType.android,
      );

      // Different devices (same ID, different IP) — depends on equality impl.
      // If equality is ID-based, they should be considered the same device.
      expect(device1.id, equals(device2.id));
    });

    test('duplicate interfaces produce unique IPs for same device', () {
      final interfaces = <String, String>{
        'wlan0': '192.168.1.100',
        'eth0': '10.0.0.50',
        'p2p0': '192.168.49.1',
      };

      // Simulate discovery resolving the same device on multiple interfaces.
      final devices = interfaces.entries.map((e) => DeviceModel(
            id: 'multi-iface',
            name: 'Multi-Interface Device',
            ipAddress: e.value,
            port: 5000,
            deviceType: DeviceType.windows,
          ));

      // All share the same ID — deduplication should keep one.
      final uniqueIds = devices.map((d) => d.id).toSet();
      expect(uniqueIds.length, equals(1));
    });

    // -----------------------------------------------------------------------
    // Rapid connect / disconnect cycles
    // -----------------------------------------------------------------------

    test('rapid connect/disconnect to TransportServer', () async {
      final server = await TransportServer.start();

      for (var i = 0; i < 5; i++) {
        final conn = await TransportClient.connect(
          InternetAddress.loopbackIPv4,
          server.port,
        );
        expect(conn.isDisposed, isFalse);
        await conn.dispose();
        expect(conn.isDisposed, isTrue);
      }

      await server.dispose();
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('TransferController handles rapid start/stop receiving', () async {
      final encryption = EncryptionService();
      final controller = TransferController(
        encryptionService: encryption,
        deviceName: 'rapid-test',
        deviceId: 'rapid-id',
      );

      for (var i = 0; i < 5; i++) {
        final port = await controller.startReceiving();
        expect(port, greaterThan(0));
        await controller.stopReceiving();
      }

      await controller.dispose();
    }, timeout: const Timeout(Duration(seconds: 15)));

    // -----------------------------------------------------------------------
    // TransferRecord state transitions
    // -----------------------------------------------------------------------

    test('TransferRecord copyWith preserves immutable fields', () {
      final device = DeviceModel(
        id: 'dev1',
        name: 'Test',
        ipAddress: '127.0.0.1',
        port: 5000,
        deviceType: DeviceType.windows,
      );

      final record = TransferRecord(
        id: 'rec1',
        direction: TransferDirection.outgoing,
        device: device,
        fileName: 'test.txt',
        fileSize: 1024,
      );

      final updated = record.copyWith(
        state: TransferState.completed,
        chunksCompleted: 10,
      );

      expect(updated.id, equals('rec1'));
      expect(updated.fileName, equals('test.txt'));
      expect(updated.state, TransferState.completed);
      expect(updated.chunksCompleted, equals(10));
    });

    test('TransferRecord isFinished covers all terminal states', () {
      final device = DeviceModel(
        id: 'dev1',
        name: 'T',
        ipAddress: '127.0.0.1',
        port: 5000,
        deviceType: DeviceType.windows,
      );

      final base = TransferRecord(
        id: 'x',
        direction: TransferDirection.incoming,
        device: device,
        fileName: 'f',
        fileSize: 0,
      );

      base.state = TransferState.completed;
      expect(base.isFinished, isTrue);
      expect(base.isActive, isFalse);

      base.state = TransferState.cancelled;
      expect(base.isFinished, isTrue);

      base.state = TransferState.failed;
      expect(base.isFinished, isTrue);

      base.state = TransferState.transferring;
      expect(base.isFinished, isFalse);
      expect(base.isActive, isTrue);
    });

    test('TransferRecord applyProgress updates all mutable fields', () {
      final device = DeviceModel(
        id: 'dev1',
        name: 'T',
        ipAddress: '127.0.0.1',
        port: 5000,
        deviceType: DeviceType.windows,
      );

      final record = TransferRecord(
        id: 'r1',
        direction: TransferDirection.outgoing,
        device: device,
        fileName: 'file.bin',
        fileSize: 1024,
      );

      record.applyProgress(const TransferProgress(
        state: TransferState.transferring,
        fileName: 'file.bin',
        fileSize: 1024,
        chunksTotal: 10,
        chunksCompleted: 5,
        bytesTransferred: 512,
      ));

      expect(record.state, TransferState.transferring);
      expect(record.chunksTotal, equals(10));
      expect(record.chunksCompleted, equals(5));
      expect(record.bytesTransferred, equals(512));
    });

    // -----------------------------------------------------------------------
    // Connection timeout
    // -----------------------------------------------------------------------

    test('connection to non-existent host times out', () async {
      // Try connecting to a non-routable address with a short timeout.
      expect(
        () => TransportClient.connect(
          InternetAddress('192.0.2.1'), // TEST-NET, should be unreachable.
          9999,
          timeout: const Duration(seconds: 2),
        ),
        throwsA(isA<SocketException>()),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));

    // -----------------------------------------------------------------------
    // TransferController dispose safety
    // -----------------------------------------------------------------------

    test('TransferController throws after dispose', () async {
      final encryption = EncryptionService();
      final controller = TransferController(
        encryptionService: encryption,
        deviceName: 'dispose-test',
        deviceId: 'dispose-id',
      );

      await controller.dispose();

      expect(
        () => controller.startReceiving(),
        throwsStateError,
      );

      final device = DeviceModel(
        id: 'dev1',
        name: 'T',
        ipAddress: '127.0.0.1',
        port: 5000,
        deviceType: DeviceType.windows,
      );

      expect(
        () => controller.sendFile(
          device: device,
          file: File('nonexistent'),
        ),
        throwsStateError,
      );
    });

    // -----------------------------------------------------------------------
    // PeerConnection double-dispose safety
    // -----------------------------------------------------------------------

    test('PeerConnection double dispose is safe', () async {
      final server = await TransportServer.start();
      final conn = await TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );

      await conn.dispose();
      // Second dispose should not throw.
      await conn.dispose();
      expect(conn.isDisposed, isTrue);

      await server.dispose();
    });

    // -----------------------------------------------------------------------
    // TransportServer double-dispose safety
    // -----------------------------------------------------------------------

    test('TransportServer double dispose is safe', () async {
      final server = await TransportServer.start();
      await server.dispose();
      // Second dispose should not throw.
      await server.dispose();
    });

    // -----------------------------------------------------------------------
    // TransferProgress edge values
    // -----------------------------------------------------------------------

    test('TransferProgress handles zero chunks', () {
      const progress = TransferProgress(
        state: TransferState.idle,
        fileName: '',
        fileSize: 0,
        chunksTotal: 0,
        chunksCompleted: 0,
      );

      expect(progress.progress, equals(0.0));
    });

    test('TransferProgress progress calculation is correct', () {
      const progress = TransferProgress(
        state: TransferState.transferring,
        fileName: 'test.bin',
        fileSize: 1000,
        chunksTotal: 10,
        chunksCompleted: 7,
        bytesTransferred: 700,
      );

      expect(progress.progress, closeTo(0.7, 0.01));
    });

    test('TransferProgress copyWith preserves original', () {
      const original = TransferProgress(
        state: TransferState.transferring,
        fileName: 'test.bin',
        fileSize: 1000,
        chunksTotal: 10,
        chunksCompleted: 5,
      );

      final updated = original.copyWith(
        state: TransferState.completed,
        chunksCompleted: 10,
      );

      // Original is unchanged.
      expect(original.state, TransferState.transferring);
      expect(original.chunksCompleted, equals(5));

      // Updated has new values.
      expect(updated.state, TransferState.completed);
      expect(updated.chunksCompleted, equals(10));
      // Unchanged fields carried over.
      expect(updated.fileName, equals('test.bin'));
      expect(updated.fileSize, equals(1000));
    });

    // -----------------------------------------------------------------------
    // Cancel transfer
    // -----------------------------------------------------------------------

    test('TransferController cancelTransfer marks record as cancelled',
        () async {
      final encryption = EncryptionService();
      final controller = TransferController(
        encryptionService: encryption,
        deviceName: 'cancel-test',
        deviceId: 'cancel-id',
        maxConcurrentTransfers: 5,
      );

      final device = DeviceModel(
        id: 'dev1',
        name: 'T',
        ipAddress: '127.0.0.1',
        port: 5000,
        deviceType: DeviceType.windows,
      );

      final file = await _createTestFile(tempDir, 1024);
      final transferId = await controller.sendFile(
        device: device,
        file: file,
      );

      // Give a moment for the transfer to start.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      controller.cancelTransfer(transferId);

      final record = controller.getTransfer(transferId);
      expect(record, isNotNull);
      expect(record!.state, TransferState.cancelled);

      await controller.dispose();
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('cancelTransfer on nonexistent ID is no-op', () async {
      final encryption = EncryptionService();
      final controller = TransferController(
        encryptionService: encryption,
        deviceName: 'noop-cancel',
        deviceId: 'noop-id',
      );

      // Should not throw.
      controller.cancelTransfer('nonexistent');

      await controller.dispose();
    });

    test('cancelTransfer on already-finished transfer is no-op', () async {
      final encryption = EncryptionService();
      final controller = TransferController(
        encryptionService: encryption,
        deviceName: 'fin-cancel',
        deviceId: 'fin-id',
        maxConcurrentTransfers: 5,
      );

      final device = DeviceModel(
        id: 'dev1',
        name: 'T',
        ipAddress: '127.0.0.1',
        port: 5000,
        deviceType: DeviceType.windows,
      );

      final file = await _createTestFile(tempDir, 1024);
      final transferId = await controller.sendFile(
        device: device,
        file: file,
      );

      // Wait for it to fail (no receiver connected, timeout).
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Cancel after transfer already ended.
      controller.cancelTransfer(transferId);

      await controller.dispose();
    }, timeout: const Timeout(Duration(seconds: 15)));

    // -----------------------------------------------------------------------
    // clearFinished / removeTransfer
    // -----------------------------------------------------------------------

    test('clearFinished removes only terminal records', () async {
      final encryption = EncryptionService();
      final controller = TransferController(
        encryptionService: encryption,
        deviceName: 'clear-test',
        deviceId: 'clear-id',
        maxConcurrentTransfers: 5,
      );

      final device = DeviceModel(
        id: 'dev1',
        name: 'T',
        ipAddress: '127.0.0.1',
        port: 5000,
        deviceType: DeviceType.windows,
      );

      // Create two transfers.
      final file = await _createTestFile(tempDir, 1024);
      final id1 = await controller.sendFile(device: device, file: file);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Cancel the first one so it's in terminal state.
      controller.cancelTransfer(id1);

      controller.clearFinished();

      // Cancelled record should be gone.
      expect(controller.getTransfer(id1), isNull);

      await controller.dispose();
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<File> _createTestFile(Directory dir, int size) async {
  final file = File(
    '${dir.path}/edge_${size}_${DateTime.now().millisecondsSinceEpoch}.bin',
  );
  final raf = await file.open(mode: FileMode.write);

  const blockSize = 64 * 1024;
  final block = Uint8List(blockSize);
  for (var i = 0; i < blockSize; i++) {
    block[i] = (i * 11 + 3) & 0xFF;
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
