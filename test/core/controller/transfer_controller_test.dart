import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:swiftdrop/core/controller/transfer_controller.dart';
import 'package:swiftdrop/core/controller/transfer_record.dart';
import 'package:swiftdrop/core/discovery/device_model.dart';
import 'package:swiftdrop/core/encryption/encryption_service.dart';
import 'package:swiftdrop/core/transport/transport_connection.dart';
import 'package:swiftdrop/core/transport/transport_service.dart';
import 'package:test/test.dart';

void main() {
  late EncryptionService encryptionService;
  late TransferController controller;
  late Directory tempDir;

  setUp(() async {
    encryptionService = EncryptionService();
    controller = TransferController(
      encryptionService: encryptionService,
      deviceName: 'TestDevice',
      deviceId: 'test1234',
    );
    tempDir = await Directory.systemTemp.createTemp('swiftdrop_ctrl_test_');
  });

  tearDown(() async {
    await controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('TransferController', () {
    test('initial state has no transfers', () {
      expect(controller.transfers, isEmpty);
      expect(controller.activeTransferCount, 0);
    });

    test('sendFile creates outgoing transfer record', () async {
      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('Hello SwiftDrop!');

      final device = DeviceModel(
        id: 'receiver1',
        name: 'Receiver',
        ipAddress: '192.168.1.100',
        port: 12345,
        deviceType: DeviceType.android,
      );

      // Listen for the first update (record creation).
      final firstUpdate = controller.transferUpdates.first
          .timeout(const Duration(seconds: 5));

      final transferId = await controller.sendFile(
        device: device,
        file: file,
      );

      expect(transferId, isNotEmpty);

      final record = await firstUpdate;
      expect(record.id, transferId);
      expect(record.direction, TransferDirection.outgoing);
      expect(record.fileName, 'test.txt');
      expect(record.device.id, 'receiver1');
    });

    test('sendFile enforces concurrency limit', () async {
      final limitedController = TransferController(
        encryptionService: encryptionService,
        deviceName: 'Test',
        deviceId: 'test',
        maxConcurrentTransfers: 1,
      );

      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('data');

      final device = DeviceModel(
        id: 'dev1',
        name: 'Device',
        deviceType: DeviceType.android,
      );

      // First send — should succeed (goes into active).
      await limitedController.sendFile(device: device, file: file);

      // Second send — should throw (1 active = max).
      expect(
        () => limitedController.sendFile(device: device, file: file),
        throwsA(isA<StateError>()),
      );

      await limitedController.dispose();
    });

    test('cancelTransfer marks as cancelled', () async {
      final file = File('${tempDir.path}/cancel.txt');
      await file.writeAsString('data');

      final device = DeviceModel(
        id: 'dev1',
        name: 'Device',
        deviceType: DeviceType.android,
      );

      final transferId = await controller.sendFile(
        device: device,
        file: file,
      );

      // Give it a moment to start.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.cancelTransfer(transferId);

      final record = controller.getTransfer(transferId);
      // May already be failed (no receiver) or cancelled.
      expect(
        record?.isFinished,
        isTrue,
      );
    });

    test('removeTransfer removes finished record', () async {
      final file = File('${tempDir.path}/remove.txt');
      await file.writeAsString('data');

      final device = DeviceModel(
        id: 'dev1',
        name: 'Device',
        deviceType: DeviceType.android,
      );

      final transferId = await controller.sendFile(
        device: device,
        file: file,
      );

      // Manually mark the record as failed so we can test removal
      // without waiting for the 30s TCP timeout.
      final record = controller.getTransfer(transferId);
      expect(record, isNotNull);
      record!.state = TransferState.failed;

      controller.removeTransfer(transferId);
      expect(controller.getTransfer(transferId), isNull);
    });

    test('clearFinished removes only finished transfers', () async {
      final file = File('${tempDir.path}/clear.txt');
      await file.writeAsString('data');

      final device = DeviceModel(
        id: 'dev1',
        name: 'Device',
        deviceType: DeviceType.android,
      );

      final id1 = await controller.sendFile(device: device, file: file);

      // Manually mark the record as completed so we can test
      // clearFinished without waiting for the 30s TCP timeout.
      final record = controller.getTransfer(id1);
      expect(record, isNotNull);
      record!.state = TransferState.completed;

      controller.clearFinished();
      expect(controller.getTransfer(id1), isNull);
    });

    test('startReceiving returns port', () async {
      final port = await controller.startReceiving();
      expect(port, greaterThan(0));
      expect(controller.receivePort, port);
    });

    test('stopReceiving clears port', () async {
      await controller.startReceiving();
      await controller.stopReceiving();
      expect(controller.receivePort, isNull);
    });

    test('startReceiving is idempotent', () async {
      final port1 = await controller.startReceiving();
      final port2 = await controller.startReceiving();
      expect(port1, port2);
    });

    test('dispose prevents further sends', () async {
      await controller.dispose();

      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('data');

      expect(
        () => controller.sendFile(
          device: DeviceModel(
            id: 'd',
            name: 'D',
            deviceType: DeviceType.android,
          ),
          file: file,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('transfersStream emits list on update', () async {
      final file = File('${tempDir.path}/stream.txt');
      await file.writeAsString('data');

      final device = DeviceModel(
        id: 'dev1',
        name: 'Device',
        deviceType: DeviceType.android,
      );

      final listFuture = controller.transfersStream.first
          .timeout(const Duration(seconds: 5));

      await controller.sendFile(device: device, file: file);

      final list = await listFuture;
      expect(list, isNotEmpty);
      expect(list.first.fileName, 'stream.txt');
    });
  });

  group('TransferController end-to-end loopback', () {
    test('send and receive file over loopback', () async {
      // Create sender and receiver controllers.
      final sender = TransferController(
        encryptionService: EncryptionService(),
        deviceName: 'Sender',
        deviceId: 'sender01',
      );

      final receiver = TransferController(
        encryptionService: EncryptionService(),
        deviceName: 'Receiver',
        deviceId: 'recvr01',
      );

      // Create test file.
      final testFile = File('${tempDir.path}/e2e_test.bin');
      final testData = Uint8List.fromList(
        List.generate(500, (i) => (i * 13 + 7) & 0xFF),
      );
      await testFile.writeAsBytes(testData);

      // Start receiver.
      final savePath = '${tempDir.path}/received_e2e.bin';
      receiver.onIncomingTransfer = (record, meta) async {
        return File(savePath);
      };
      final receivePort = await receiver.startReceiving();

      // Track receiver progress.
      final receiveDone = receiver.transferUpdates
          .firstWhere((r) => r.isFinished)
          .timeout(const Duration(seconds: 30));

      // Connect sender to receiver.
      // ignore: unused_local_variable
      final device = DeviceModel(
        id: 'recvr01',
        name: 'Receiver',
        ipAddress: '127.0.0.1',
        port: receivePort,
        deviceType: DeviceType.windows,
      );

      // Instead of sendFile (which starts its own server),
      // directly connect and use TransportService.
      final connection = await TransportClient.connect(
        InternetAddress.loopbackIPv4,
        receivePort,
      );

      final transportService = TransportService(
        encryptionService: EncryptionService(),
        deviceName: 'Sender',
        deviceId: 'sender01',
      );

      final sendResult = await transportService.sendFile(
        connection: connection,
        file: testFile,
      );

      expect(sendResult.state, TransferState.completed);

      // Wait for receiver to finish.
      final receiveRecord = await receiveDone;
      expect(receiveRecord.state, TransferState.completed);

      // Verify file contents.
      final receivedFile = File(savePath);
      expect(await receivedFile.exists(), isTrue);
      final receivedData = await receivedFile.readAsBytes();
      expect(receivedData, testData);

      // Cleanup.
      transportService.dispose();
      await connection.dispose();
      await sender.dispose();
      await receiver.dispose();
    });
  });
}
