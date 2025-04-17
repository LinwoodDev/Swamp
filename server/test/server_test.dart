import 'dart:async';
import 'dart:typed_data';

import 'package:consoler/consoler.dart';
import 'package:swamp/server.dart';
import 'package:swamp_api/connection.dart';
import 'package:swamp_api/models.dart';
import 'package:test/test.dart';

void main() {
  final port = 8080;
  final host = '127.0.0.1';
  final uri = Uri.parse('ws://$host:$port');
  late SwampServer server;

  late RawSwampConnection client1, client2;

  setUp(() async {
    server = SwampServer(
      host,
      port,
      minLogLevel: LogLevel.verbose,
      withConsole: false,
    );
    await server.init();

    client1 = RawSwampConnection(server: uri);
    client2 = RawSwampConnection(server: uri);

    await client1.init();
    await client2.init();

    // Add a small delay to ensure connections are fully established
    await Future.delayed(const Duration(milliseconds: 500));
  });

  tearDown(() async {
    await client1.close();
    await client2.close();
    return server.close();
  });

  group('General Usage Tests', () {
    test('Create room', () async {
      final completer = Completer<void>();

      // Add debug print
      print('Setting up roomInfo listener');

      // Listen for the roomInfo event
      var subscription = client1
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            print('Received roomInfo event: ${packet.data.length} bytes');
            try {
              final roomInfo = RoomInfo.fromBytes(packet.data);
              print(
                'Room info parsed: roomId=${roomInfo.roomId}, currentId=${roomInfo.currentId}',
              );
              expect(roomInfo.roomId, isNotNull);
              expect(roomInfo.currentId, 1);
              expect(roomInfo.flags, 0);
              completer.complete();
            } catch (e) {
              print('Error parsing roomInfo: $e');
              completer.completeError(e);
            }
          });

      // Add debug print before sending command
      print('Sending createRoom command');

      // Send the command to create a room
      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      // Wait for the completer to complete or timeout
      try {
        await completer.future;
        print('Test completed successfully');
      } finally {
        subscription.cancel();
      }
    });
    test('Joining room', () async {
      final completer = Completer<Uint8List>();

      // Listen for the roomInfo event
      var subscription = client1
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            try {
              final roomInfo = RoomInfo.fromBytes(packet.data);
              expect(roomInfo.roomId, isNotNull);
              expect(roomInfo.currentId, 1);
              expect(roomInfo.flags, 0);
              completer.complete(roomInfo.roomId);
            } catch (e) {
              completer.completeError(e);
            }
          });

      // Send the command to create a room
      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      final joinedCompleter = Completer<void>();

      // Listen for joinRoom event
      var joinedSubscription = client1
          .registerNamedFunction(SwampEvent.playerJoined)
          .read
          .listen((packet) {
            try {
              final playerId = packet.data[0] << 8 | packet.data[1];
              expect(playerId, 2);
              joinedCompleter.complete();
            } catch (e) {
              joinedCompleter.completeError(e);
            }
          });

      // Wait for the completer to complete or timeout
      Uint8List? roomId;
      try {
        roomId = await completer.future;
      } finally {
        subscription.cancel();
      }
      expect(roomId, isNotNull);

      // Now join the room with client2
      final joinCompleter = Completer<void>();
      var joinSubscription = client2
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            try {
              final roomInfo = RoomInfo.fromBytes(packet.data);
              expect(roomInfo.roomId, roomId);
              expect(roomInfo.currentId, 2);
              expect(roomInfo.flags, 0);
              joinCompleter.complete();
            } catch (e) {
              joinCompleter.completeError(e);
            }
          });
      client2.sendNamedFunction(SwampCommand.joinRoom, roomId);
      // Wait for the join completer to complete or timeout
      try {
        await joinCompleter.future;
      } finally {
        joinSubscription.cancel();
      }

      // Wait for the joined completer to complete or timeout
      try {
        await joinedCompleter.future;
      } finally {
        joinedSubscription.cancel();
      }

      final messageReceived = Completer<void>();
      const message = 'Hello, World!';
      var messageSubscription = client1
          .registerNamedFunction(SwampEvent.message)
          .read
          .listen((packet) {
            try {
              final receivedMessage = String.fromCharCodes(
                packet.data.sublist(2),
              );
              expect(receivedMessage, message);
              messageReceived.complete();
            } catch (e) {
              messageReceived.completeError(e);
            }
          });
      client2.sendNamedFunction(
        SwampCommand.message,
        Uint8List.fromList([0, 0, ...message.codeUnits]),
      );
      // Wait for the message to be received or timeout
      try {
        await messageReceived.future;
      } finally {
        messageSubscription.cancel();
      }
    });
  });
}
