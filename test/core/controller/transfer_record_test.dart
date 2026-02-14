import 'package:swiftdrop/core/discovery/device_model.dart';
import 'package:swiftdrop/core/transport/transport_service.dart';
import 'package:swiftdrop/core/controller/transfer_record.dart';
import 'package:test/test.dart';

void main() {
  group('TransferRecord', () {
    TransferRecord createRecord({
      TransferState state = TransferState.idle,
      int chunksTotal = 10,
      int chunksCompleted = 0,
    }) {
      return TransferRecord(
        id: 'test-id-123',
        direction: TransferDirection.outgoing,
        device: DeviceModel(
          id: 'dev1',
          name: 'Test Device',
          deviceType: DeviceType.android,
        ),
        fileName: 'photo.jpg',
        fileSize: 1024 * 1024,
        filePath: '/tmp/photo.jpg',
        state: state,
        chunksTotal: chunksTotal,
        chunksCompleted: chunksCompleted,
      );
    }

    test('initial state is correct', () {
      final record = createRecord();
      expect(record.state, TransferState.idle);
      expect(record.direction, TransferDirection.outgoing);
      expect(record.fileName, 'photo.jpg');
      expect(record.fileSize, 1048576);
      expect(record.progress, 0.0);
      expect(record.isFinished, isFalse);
      expect(record.isActive, isFalse);
    });

    test('progress returns correct fraction', () {
      final record = createRecord(chunksTotal: 10, chunksCompleted: 5);
      expect(record.progress, 0.5);
    });

    test('progress handles zero chunks', () {
      final record = createRecord(chunksTotal: 0, chunksCompleted: 0);
      expect(record.progress, 0.0);
    });

    test('isFinished for completed state', () {
      final record = createRecord(state: TransferState.completed);
      expect(record.isFinished, isTrue);
    });

    test('isFinished for cancelled state', () {
      final record = createRecord(state: TransferState.cancelled);
      expect(record.isFinished, isTrue);
    });

    test('isFinished for failed state', () {
      final record = createRecord(state: TransferState.failed);
      expect(record.isFinished, isTrue);
    });

    test('isActive for handshaking state', () {
      final record = createRecord(state: TransferState.handshaking);
      expect(record.isActive, isTrue);
    });

    test('isActive for transferring state', () {
      final record = createRecord(state: TransferState.transferring);
      expect(record.isActive, isTrue);
    });

    test('isActive for verifying state', () {
      final record = createRecord(state: TransferState.verifying);
      expect(record.isActive, isTrue);
    });

    test('isActive for awaitingAccept state', () {
      final record = createRecord(state: TransferState.awaitingAccept);
      expect(record.isActive, isTrue);
    });

    test('idle is neither finished nor active', () {
      final record = createRecord(state: TransferState.idle);
      expect(record.isFinished, isFalse);
      expect(record.isActive, isFalse);
    });

    test('applyProgress updates fields', () {
      final record = createRecord();
      record.applyProgress(const TransferProgress(
        state: TransferState.transferring,
        fileName: 'photo.jpg',
        fileSize: 1048576,
        chunksTotal: 16,
        chunksCompleted: 8,
        bytesTransferred: 524288,
      ));

      expect(record.state, TransferState.transferring);
      expect(record.chunksTotal, 16);
      expect(record.chunksCompleted, 8);
      expect(record.bytesTransferred, 524288);
      expect(record.progress, 0.5);
    });

    test('applyProgress with error', () {
      final record = createRecord();
      record.applyProgress(const TransferProgress(
        state: TransferState.failed,
        fileName: 'photo.jpg',
        fileSize: 0,
        chunksTotal: 10,
        chunksCompleted: 3,
        errorMessage: 'Connection lost',
      ));

      expect(record.state, TransferState.failed);
      expect(record.errorMessage, 'Connection lost');
      expect(record.isFinished, isTrue);
    });

    test('copyWith creates modified copy', () {
      final record = createRecord();
      final copy = record.copyWith(
        state: TransferState.completed,
        chunksCompleted: 10,
        bytesTransferred: 1048576,
      );

      expect(copy.id, record.id);
      expect(copy.direction, record.direction);
      expect(copy.fileName, record.fileName);
      expect(copy.state, TransferState.completed);
      expect(copy.chunksCompleted, 10);
      expect(copy.bytesTransferred, 1048576);
    });

    test('copyWith preserves unmodified fields', () {
      final record = createRecord(
        chunksTotal: 20,
        chunksCompleted: 5,
      );
      final copy = record.copyWith(state: TransferState.verifying);

      expect(copy.chunksTotal, 20);
      expect(copy.chunksCompleted, 5);
      expect(copy.filePath, '/tmp/photo.jpg');
    });

    test('equality is by id', () {
      final a = createRecord();
      final b = TransferRecord(
        id: 'test-id-123',
        direction: TransferDirection.incoming,
        device: DeviceModel(
          id: 'other',
          name: 'Other',
          deviceType: DeviceType.windows,
        ),
        fileName: 'different.txt',
        fileSize: 999,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different ids are not equal', () {
      final a = createRecord();
      final b = TransferRecord(
        id: 'different-id',
        direction: TransferDirection.outgoing,
        device: DeviceModel(
          id: 'dev1',
          name: 'Test Device',
          deviceType: DeviceType.android,
        ),
        fileName: 'photo.jpg',
        fileSize: 1048576,
      );

      expect(a, isNot(equals(b)));
    });

    test('toString includes key fields', () {
      final record = createRecord(
        state: TransferState.transferring,
        chunksTotal: 10,
        chunksCompleted: 3,
      );
      final str = record.toString();

      expect(str, contains('test-id-123'));
      expect(str, contains('outgoing'));
      expect(str, contains('photo.jpg'));
      expect(str, contains('transferring'));
      expect(str, contains('3/10'));
    });

    test('createdAt defaults to now', () {
      final before = DateTime.now();
      final record = createRecord();
      final after = DateTime.now();

      expect(record.createdAt.isAfter(before.subtract(
        const Duration(seconds: 1),
      )), isTrue);
      expect(record.createdAt.isBefore(after.add(
        const Duration(seconds: 1),
      )), isTrue);
    });

    test('incoming direction', () {
      final record = TransferRecord(
        id: 'incoming-1',
        direction: TransferDirection.incoming,
        device: DeviceModel(
          id: 'sender1',
          name: 'Sender Phone',
          deviceType: DeviceType.android,
        ),
        fileName: 'document.pdf',
        fileSize: 2048,
        savePath: '/downloads/document.pdf',
      );

      expect(record.direction, TransferDirection.incoming);
      expect(record.savePath, '/downloads/document.pdf');
      expect(record.filePath, isNull);
    });
  });
}
