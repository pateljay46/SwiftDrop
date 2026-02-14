import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';

import '../constants.dart';

/// Represents a single file chunk with its index and plaintext data.
class FileChunk {
  const FileChunk({
    required this.index,
    required this.data,
    required this.checksum,
  });

  /// Zero-based chunk index.
  final int index;

  /// Raw plaintext chunk data.
  final Uint8List data;

  /// SHA-256 checksum of [data] (32 bytes).
  final Uint8List checksum;
}

/// Metadata computed during file preparation, before transfer begins.
class FilePrepareResult {
  const FilePrepareResult({
    required this.file,
    required this.fileName,
    required this.fileSize,
    required this.chunkSize,
    required this.chunkCount,
    required this.fileChecksum,
  });

  final File file;
  final String fileName;
  final int fileSize;
  final int chunkSize;
  final int chunkCount;

  /// SHA-256 hash of the entire file (32 bytes).
  final Uint8List fileChecksum;
}

/// Utility for chunking files for transfer, computing checksums,
/// and reassembling received chunks.
class FileChunker {
  const FileChunker({
    this.chunkSize = SwiftDropConstants.defaultChunkSize,
  });

  /// Size of each chunk in bytes.
  final int chunkSize;

  /// Prepares a file for sending by computing its metadata and checksum.
  Future<FilePrepareResult> prepare(File file) async {
    final fileSize = await file.length();
    final chunkCount = (fileSize / chunkSize).ceil();
    final fileChecksum = await _computeFileChecksum(file);

    return FilePrepareResult(
      file: file,
      fileName: file.uri.pathSegments.last,
      fileSize: fileSize,
      chunkSize: chunkSize,
      chunkCount: chunkCount == 0 ? 1 : chunkCount, // At least 1 chunk for empty file.
      fileChecksum: fileChecksum,
    );
  }

  /// Returns an async iterable of [FileChunk]s for the given file.
  ///
  /// Reads the file sequentially in [chunkSize] blocks. Each chunk
  /// includes its index and SHA-256 checksum.
  Stream<FileChunk> chunkFile(File file) async* {
    final raf = await file.open(mode: FileMode.read);
    try {
      var index = 0;
      while (true) {
        final data = await raf.read(chunkSize);
        if (data.isEmpty) break;

        final checksum = Uint8List.fromList(sha256.convert(data).bytes);
        yield FileChunk(
          index: index,
          data: data,
          checksum: checksum,
        );
        index++;
      }
    } finally {
      await raf.close();
    }
  }

  /// Reads a specific chunk from a file by index.
  ///
  /// Useful for retransmitting a single chunk after a NACK.
  Future<FileChunk> readChunk(File file, int chunkIndex) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      final offset = chunkIndex * chunkSize;
      await raf.setPosition(offset);
      final data = await raf.read(chunkSize);
      final checksum = Uint8List.fromList(sha256.convert(data).bytes);
      return FileChunk(
        index: chunkIndex,
        data: data,
        checksum: checksum,
      );
    } finally {
      await raf.close();
    }
  }

  /// Computes SHA-256 hash of the entire file by streaming through it.
  Future<Uint8List> _computeFileChecksum(File file) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);

    final stream = file.openRead();
    await for (final chunk in stream) {
      input.add(chunk);
    }
    input.close();

    return Uint8List.fromList(output.events.single.bytes);
  }

  /// Verifies a received chunk's integrity against its checksum.
  static bool verifyChunk(Uint8List data, Uint8List expectedChecksum) {
    final actual = sha256.convert(data).bytes;
    if (actual.length != expectedChecksum.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expectedChecksum[i]) return false;
    }
    return true;
  }

  /// Verifies the entire reassembled file against its expected checksum.
  static Future<bool> verifyFile(
    File file,
    Uint8List expectedChecksum,
  ) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);

    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();

    final actual = output.events.single.bytes;
    if (actual.length != expectedChecksum.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expectedChecksum[i]) return false;
    }
    return true;
  }
}
