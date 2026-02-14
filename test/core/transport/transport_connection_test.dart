import 'dart:io';
import 'dart:typed_data';

import 'package:swiftdrop/core/transport/protocol_messages.dart';
import 'package:swiftdrop/core/transport/transport_connection.dart';
import 'package:test/test.dart';

void main() {
  group('TransportServer + TransportClient', () {
    late TransportServer server;

    setUp(() async {
      server = await TransportServer.start();
    });

    tearDown(() async {
      await server.dispose();
    });

    test('server listens on ephemeral port', () {
      expect(server.port, greaterThan(0));
      expect(server.isListening, isTrue);
    });

    test('client connects to server', () async {
      final connectionFuture = server.connections.first;
      final clientConn = await TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );

      final serverConn = await connectionFuture;
      expect(serverConn, isNotNull);
      expect(clientConn, isNotNull);

      await clientConn.dispose();
      await serverConn.dispose();
    });

    test('messages flow client -> server', () async {
      final connectionFuture = server.connections.first;
      final clientConn = await TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final serverConn = await connectionFuture;

      final received = serverConn.messages.first;
      clientConn.send(
        const CancelMessage(seqNo: 42),
        autoSeqNo: false,
      );

      final msg = await received.timeout(const Duration(seconds: 5));
      expect(msg, isA<CancelMessage>());
      expect(msg.seqNo, 42);

      await clientConn.dispose();
      await serverConn.dispose();
    });

    test('messages flow server -> client', () async {
      final connectionFuture = server.connections.first;
      final clientConn = await TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final serverConn = await connectionFuture;

      final received = clientConn.messages.first;
      serverConn.send(
        const FileAcceptMessage(seqNo: 7),
        autoSeqNo: false,
      );

      final msg = await received.timeout(const Duration(seconds: 5));
      expect(msg, isA<FileAcceptMessage>());
      expect(msg.seqNo, 7);

      await clientConn.dispose();
      await serverConn.dispose();
    });

    test('complex message with payload survives loopback', () async {
      final connectionFuture = server.connections.first;
      final clientConn = await TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final serverConn = await connectionFuture;

      final iv = Uint8List.fromList(List.generate(12, (i) => i * 20));
      final data = Uint8List.fromList(List.generate(1024, (i) => i & 0xFF));
      final tag = Uint8List.fromList(List.generate(16, (i) => i + 100));
      final checksum = Uint8List.fromList(List.generate(32, (i) => i + 50));

      final received = serverConn.messages.first;
      clientConn.send(
        ChunkDataMessage(
          seqNo: 99,
          chunkIndex: 42,
          iv: iv,
          encryptedData: data,
          gcmTag: tag,
          plaintextChecksum: checksum,
        ),
        autoSeqNo: false,
      );

      final msg =
          await received.timeout(const Duration(seconds: 5)) as ChunkDataMessage;
      expect(msg.chunkIndex, 42);
      expect(msg.iv, iv);
      expect(msg.encryptedData.length, 1024);
      expect(msg.gcmTag, tag);
      expect(msg.plaintextChecksum, checksum);

      await clientConn.dispose();
      await serverConn.dispose();
    });

    test('multiple messages arrive in order', () async {
      final connectionFuture = server.connections.first;
      final clientConn = await TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final serverConn = await connectionFuture;

      final messages = <ProtocolMessage>[];
      final sub = serverConn.messages.listen(messages.add);

      for (var i = 0; i < 10; i++) {
        clientConn.send(
          ChunkAckMessage(seqNo: i, chunkIndex: i),
          autoSeqNo: false,
        );
      }

      await clientConn.flush();
      // Give time for all messages to arrive.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(messages.length, 10);
      for (var i = 0; i < 10; i++) {
        expect((messages[i] as ChunkAckMessage).chunkIndex, i);
      }

      await sub.cancel();
      await clientConn.dispose();
      await serverConn.dispose();
    });

    test('auto seqNo increments correctly', () async {
      final connectionFuture = server.connections.first;
      final clientConn = await TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final serverConn = await connectionFuture;

      final messages = <ProtocolMessage>[];
      final sub = serverConn.messages.listen(messages.add);

      clientConn.send(const CancelMessage());
      clientConn.send(const CancelMessage());
      clientConn.send(const CancelMessage());

      await clientConn.flush();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(messages.length, 3);
      expect(messages[0].seqNo, 0);
      expect(messages[1].seqNo, 1);
      expect(messages[2].seqNo, 2);

      await sub.cancel();
      await clientConn.dispose();
      await serverConn.dispose();
    });

    test('server dispose closes connections', () async {
      final connectionFuture = server.connections.first;
      final clientConn = await TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      await connectionFuture;

      await server.dispose();
      expect(server.isListening, isFalse);

      await clientConn.dispose();
    });

    test('handshake roundtrip over TCP', () async {
      final connectionFuture = server.connections.first;
      final clientConn = await TransportClient.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final serverConn = await connectionFuture;

      // Client sends handshake init.
      final serverMsg = serverConn.messages.first;
      clientConn.send(
        HandshakeMessage(
          type: MessageType.handshakeInit,
          seqNo: 0,
          protocolVersion: 1,
          publicKey: Uint8List(65),
          deviceName: 'Sender',
          deviceId: 'snd12345',
        ),
        autoSeqNo: false,
      );

      final init =
          await serverMsg.timeout(const Duration(seconds: 5)) as HandshakeMessage;
      expect(init.type, MessageType.handshakeInit);
      expect(init.deviceName, 'Sender');

      // Server sends handshake reply.
      final clientMsg = clientConn.messages.first;
      serverConn.send(
        HandshakeMessage(
          type: MessageType.handshakeReply,
          seqNo: 1,
          protocolVersion: 1,
          publicKey: Uint8List(65),
          deviceName: 'Receiver',
          deviceId: 'rcv12345',
        ),
        autoSeqNo: false,
      );

      final reply =
          await clientMsg.timeout(const Duration(seconds: 5)) as HandshakeMessage;
      expect(reply.type, MessageType.handshakeReply);
      expect(reply.deviceName, 'Receiver');

      await clientConn.dispose();
      await serverConn.dispose();
    });
  });
}
