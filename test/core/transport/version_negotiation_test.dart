import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:swiftdrop/core/constants.dart';
import 'package:swiftdrop/core/encryption/encryption_service.dart';
import 'package:swiftdrop/core/transport/protocol_messages.dart';
import 'package:swiftdrop/core/transport/transport_connection.dart';
import 'package:swiftdrop/core/transport/transport_service.dart';

// Concurrent server/client tests deliberately fire futures that are awaited
// later, and PeerConnection.dispose() closes internal resources.
// ignore_for_file: close_sinks, unawaited_futures

void main() {
  group('Protocol version negotiation', () {
    late EncryptionService senderEncryption;
    late EncryptionService receiverEncryption;

    setUp(() {
      senderEncryption = EncryptionService();
      receiverEncryption = EncryptionService();
    });

    test('compatible versions complete handshake', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final senderService = TransportService(
        encryptionService: senderEncryption,
        deviceName: 'SenderV1',
        deviceId: 'sender01',
      );

      final receiverService = TransportService(
        encryptionService: receiverEncryption,
        deviceName: 'ReceiverV1',
        deviceId: 'recv0001',
      );

      // Run receiver handshake in parallel.
      Future<Uint8List> runReceiver() async {
        final socket = await server.first;
        final conn = PeerConnection(socket);
        final key = await receiverService.performReceiverHandshake(conn);
        conn.dispose();
        return key;
      }

      final receiverFuture = runReceiver();

      final clientSocket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
      );
      final clientConn = PeerConnection(clientSocket);
      final senderKey = await senderService.performSenderHandshake(clientConn);
      final receiverKey = await receiverFuture;

      expect(senderKey, equals(receiverKey));
      expect(senderKey.length, equals(32));

      clientConn.dispose();
      await server.close();
      senderService.dispose();
      receiverService.dispose();
    });

    test('sender rejects incompatible receiver version', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final senderService = TransportService(
        encryptionService: senderEncryption,
        deviceName: 'Sender',
        deviceId: 'sender01',
      );

      Future<ErrorMessage> runFakeReceiver() async {
        final socket = await server.first;
        final conn = PeerConnection(socket);

        await conn.waitFor(
          predicate: (m) => m is HandshakeMessage,
          timeout: const Duration(seconds: 5),
        );

        final keyPair = receiverEncryption.generateKeyPair();
        conn.send(HandshakeMessage(
          type: MessageType.handshakeReply,
          protocolVersion: 999,
          publicKey: keyPair.publicKey,
          deviceName: 'FutureDevice',
          deviceId: 'future01',
        ));

        final msg = await conn.waitFor(
          predicate: (m) => m is ErrorMessage,
          timeout: const Duration(seconds: 5),
        ) as ErrorMessage;

        conn.dispose();
        return msg;
      }

      final serverFuture = runFakeReceiver();

      final clientSocket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
      );
      final clientConn = PeerConnection(clientSocket);

      await expectLater(
        senderService.performSenderHandshake(clientConn),
        throwsStateError,
      );

      final errorMsg = await serverFuture;
      expect(errorMsg.errorCode, ProtocolErrorCode.versionMismatch);
      expect(errorMsg.message, contains('999'));

      clientConn.dispose();
      await server.close();
      senderService.dispose();
    });

    test('receiver rejects incompatible sender version', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final receiverService = TransportService(
        encryptionService: receiverEncryption,
        deviceName: 'Receiver',
        deviceId: 'recv0001',
      );

      Future<void> runReceiver() async {
        final socket = await server.first;
        final conn = PeerConnection(socket);
        try {
          await receiverService.performReceiverHandshake(conn);
          fail('Should have thrown');
        } on StateError catch (e) {
          expect(e.message, contains('Incompatible protocol version'));
        } finally {
          conn.dispose();
        }
      }

      final serverFuture = runReceiver();

      final clientSocket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
      );
      final clientConn = PeerConnection(clientSocket);
      final keyPair = senderEncryption.generateKeyPair();

      clientConn.send(HandshakeMessage(
        type: MessageType.handshakeInit,
        protocolVersion: 0,
        publicKey: keyPair.publicKey,
        deviceName: 'OldDevice',
        deviceId: 'old00001',
      ));

      final errorMsg = await clientConn.waitFor(
        predicate: (m) => m is ErrorMessage,
        timeout: const Duration(seconds: 5),
      ) as ErrorMessage;

      expect(errorMsg.errorCode, ProtocolErrorCode.versionMismatch);
      expect(errorMsg.message, contains('v0'));

      clientConn.dispose();
      await serverFuture;
      await server.close();
      receiverService.dispose();
    });

    test('protocol version constant matches mDNS TXT key', () {
      expect(SwiftDropConstants.protocolVersion, greaterThan(0));
      expect(SwiftDropConstants.txtKeyVersion, equals('v'));
      expect(
        SwiftDropConstants.minSupportedProtocolVersion,
        lessThanOrEqualTo(SwiftDropConstants.protocolVersion),
      );
    });

    test('sender handles ErrorMessage in place of HandshakeReply', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final senderService = TransportService(
        encryptionService: senderEncryption,
        deviceName: 'Sender',
        deviceId: 'sender01',
      );

      Future<void> runErrorServer() async {
        final socket = await server.first;
        final conn = PeerConnection(socket);
        await conn.waitFor(
          predicate: (m) => m is HandshakeMessage,
          timeout: const Duration(seconds: 5),
        );

        conn.send(const ErrorMessage(
          errorCode: ProtocolErrorCode.versionMismatch,
          message: 'Your version is not supported',
        ));

        await Future<void>.delayed(const Duration(milliseconds: 200));
        conn.dispose();
      }

      final serverFuture = runErrorServer();

      final clientSocket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
      );
      final clientConn = PeerConnection(clientSocket);

      await expectLater(
        senderService.performSenderHandshake(clientConn),
        throwsStateError,
      );

      clientConn.dispose();
      await serverFuture;
      await server.close();
      senderService.dispose();
    });
  });
}
