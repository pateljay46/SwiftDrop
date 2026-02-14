import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:swiftdrop/core/transport/file_chunker.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('swiftdrop_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FileChunker', () {
    test('prepare returns correct metadata', () async {
      final file = File('${tempDir.path}/test.bin');
      final data = Uint8List(65536 * 3 + 1000); // 3.something chunks
      for (var i = 0; i < data.length; i++) {
        data[i] = i & 0xFF;
      }
      await file.writeAsBytes(data);

      const chunker = FileChunker();
      final result = await chunker.prepare(file);

      expect(result.fileName, 'test.bin');
      expect(result.fileSize, data.length);
      expect(result.chunkSize, 65536);
      expect(result.chunkCount, 4); // ceil(197536 + 1000 / 65536) = 4
    });

    test('prepare computes correct SHA-256 checksum', () async {
      final file = File('${tempDir.path}/checksum_test.txt');
      await file.writeAsString('Hello, SwiftDrop!');

      const chunker = FileChunker();
      final result = await chunker.prepare(file);

      final expected =
          Uint8List.fromList(sha256.convert(await file.readAsBytes()).bytes);
      expect(result.fileChecksum, expected);
    });

    test('prepare handles empty file', () async {
      final file = File('${tempDir.path}/empty.bin');
      await file.writeAsBytes([]);

      const chunker = FileChunker();
      final result = await chunker.prepare(file);

      expect(result.fileSize, 0);
      expect(result.chunkCount, 1); // At least 1
    });

    test('chunkFile yields correct number of chunks', () async {
      final file = File('${tempDir.path}/multi.bin');
      final data = Uint8List(65536 * 2 + 100);
      await file.writeAsBytes(data);

      const chunker = FileChunker();
      final chunks = await chunker.chunkFile(file).toList();

      expect(chunks.length, 3);
      expect(chunks[0].index, 0);
      expect(chunks[1].index, 1);
      expect(chunks[2].index, 2);
    });

    test('chunks have correct sizes', () async {
      final file = File('${tempDir.path}/sizes.bin');
      final data = Uint8List(65536 + 500);
      await file.writeAsBytes(data);

      const chunker = FileChunker();
      final chunks = await chunker.chunkFile(file).toList();

      expect(chunks[0].data.length, 65536);
      expect(chunks[1].data.length, 500);
    });

    test('each chunk has a valid SHA-256 checksum', () async {
      final file = File('${tempDir.path}/checksums.bin');
      final data = Uint8List.fromList(List.generate(1000, (i) => i & 0xFF));
      await file.writeAsBytes(data);

      const chunker = FileChunker(chunkSize: 400);
      final chunks = await chunker.chunkFile(file).toList();

      for (final chunk in chunks) {
        final expected = sha256.convert(chunk.data).bytes;
        expect(chunk.checksum, Uint8List.fromList(expected));
      }
    });

    test('readChunk returns correct chunk at index', () async {
      final file = File('${tempDir.path}/random_access.bin');
      final data = Uint8List.fromList(List.generate(300, (i) => i & 0xFF));
      await file.writeAsBytes(data);

      const chunker = FileChunker(chunkSize: 100);

      final chunk0 = await chunker.readChunk(file, 0);
      expect(chunk0.index, 0);
      expect(chunk0.data.length, 100);
      expect(chunk0.data[0], 0);

      final chunk2 = await chunker.readChunk(file, 2);
      expect(chunk2.index, 2);
      expect(chunk2.data.length, 100);
      expect(chunk2.data[0], 200);
    });

    test('verifyChunk returns true for matching checksum', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final checksum = Uint8List.fromList(sha256.convert(data).bytes);

      expect(FileChunker.verifyChunk(data, checksum), isTrue);
    });

    test('verifyChunk returns false for mismatched checksum', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final badChecksum = Uint8List(32); // All zeros.

      expect(FileChunker.verifyChunk(data, badChecksum), isFalse);
    });

    test('verifyFile returns true for correct file', () async {
      final file = File('${tempDir.path}/verify.bin');
      final data = Uint8List.fromList(List.generate(500, (i) => i & 0xFF));
      await file.writeAsBytes(data);

      final checksum = Uint8List.fromList(sha256.convert(data).bytes);
      expect(await FileChunker.verifyFile(file, checksum), isTrue);
    });

    test('verifyFile returns false for corrupted file', () async {
      final file = File('${tempDir.path}/corrupt.bin');
      final data = Uint8List.fromList(List.generate(500, (i) => i & 0xFF));
      await file.writeAsBytes(data);

      final wrongChecksum = Uint8List(32);
      expect(await FileChunker.verifyFile(file, wrongChecksum), isFalse);
    });

    test('custom chunk size is respected', () async {
      final file = File('${tempDir.path}/custom.bin');
      await file.writeAsBytes(Uint8List(1000));

      const chunker = FileChunker(chunkSize: 200);
      final result = await chunker.prepare(file);

      expect(result.chunkCount, 5);
      expect(result.chunkSize, 200);
    });

    test('reassembled chunks match original file', () async {
      final file = File('${tempDir.path}/original.bin');
      final originalData = Uint8List.fromList(
        List.generate(1500, (i) => (i * 7 + 13) & 0xFF),
      );
      await file.writeAsBytes(originalData);

      const chunker = FileChunker(chunkSize: 500);
      final chunks = await chunker.chunkFile(file).toList();

      // Reassemble.
      final reassembled = BytesBuilder();
      for (final chunk in chunks) {
        reassembled.add(chunk.data);
      }

      expect(reassembled.toBytes(), originalData);
    });
  });
}
