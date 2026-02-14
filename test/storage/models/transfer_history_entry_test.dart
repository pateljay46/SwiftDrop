import 'package:test/test.dart';

import 'package:swiftdrop/storage/models/transfer_history_entry.dart';

void main() {
  group('TransferHistoryEntry', () {
    TransferHistoryEntry makeEntry({
      String status = 'completed',
      String direction = 'outgoing',
      int fileSize = 1024,
    }) {
      return TransferHistoryEntry(
        transferId: 'tx-1',
        fileName: 'photo.jpg',
        fileSize: fileSize,
        deviceId: 'dev-1',
        deviceName: 'Pixel 7',
        deviceType: 'android',
        direction: direction,
        status: status,
        filePath: '/tmp/photo.jpg',
        durationMs: 1500,
      );
    }

    test('isSuccess returns true for completed', () {
      expect(makeEntry(status: 'completed').isSuccess, isTrue);
      expect(makeEntry(status: 'failed').isSuccess, isFalse);
      expect(makeEntry(status: 'cancelled').isSuccess, isFalse);
    });

    test('isOutgoing returns true for outgoing direction', () {
      expect(makeEntry(direction: 'outgoing').isOutgoing, isTrue);
      expect(makeEntry(direction: 'incoming').isOutgoing, isFalse);
    });

    test('formattedSize returns human-readable sizes', () {
      expect(makeEntry(fileSize: 500).formattedSize, '500 B');
      expect(makeEntry(fileSize: 2048).formattedSize, '2.0 KB');
      expect(makeEntry(fileSize: 5 * 1024 * 1024).formattedSize, '5.0 MB');
      expect(
        makeEntry(fileSize: 2 * 1024 * 1024 * 1024).formattedSize,
        '2.00 GB',
      );
    });

    test('timestamp defaults to now', () {
      final entry = makeEntry();
      final now = DateTime.now();
      expect(
        entry.timestamp.difference(now).inSeconds.abs(),
        lessThan(2),
      );
    });

    test('equality by transferId', () {
      final a = makeEntry();
      final b = TransferHistoryEntry(
        transferId: 'tx-1',
        fileName: 'other.txt',
        fileSize: 0,
        deviceId: 'dev-2',
        deviceName: 'Other',
        deviceType: 'windows',
        direction: 'incoming',
        status: 'failed',
      );
      final c = TransferHistoryEntry(
        transferId: 'tx-2',
        fileName: 'photo.jpg',
        fileSize: 1024,
        deviceId: 'dev-1',
        deviceName: 'Pixel 7',
        deviceType: 'android',
        direction: 'outgoing',
        status: 'completed',
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains direction and filename', () {
      final entry = makeEntry();
      final str = entry.toString();
      expect(str, contains('outgoing'));
      expect(str, contains('photo.jpg'));
      expect(str, contains('Pixel 7'));
      expect(str, contains('completed'));
    });
  });

  group('TransferHistoryEntryAdapter', () {
    test('has correct typeId', () {
      final adapter = TransferHistoryEntryAdapter();
      expect(adapter.typeId, 2);
    });
  });
}
