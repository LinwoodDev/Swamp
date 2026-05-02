import 'dart:async';
import 'dart:typed_data';

import 'package:consoler/consoler.dart';
import 'package:swamp/src/config.dart';
import 'package:swamp/src/server.dart';
import 'package:swamp_api/connection.dart';
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

  group('Room Creation Tests', () {
    test('Create room successfully', () async {
      final completer = Completer<RoomInfo>();

      print('Setting up roomInfo listener');
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
              completer.complete(roomInfo);
            } catch (e) {
              print('Error parsing roomInfo: $e');
              completer.completeError(e);
            }
          });

      print('Sending createRoom command');
      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      RoomInfo roomInfo;
      try {
        roomInfo = await completer.future;

        // Validate room creation
        expect(roomInfo.roomId, isNotNull);
        expect(roomInfo.currentId, 1);
        expect(roomInfo.flags, 0);

        print('Test completed successfully');
      } finally {
        subscription.cancel();
      }
    });
  });

  group('Room Joining Tests', () {
    late Uint8List roomId;

    setUp(() async {
      // Create a room first
      final completer = Completer<Uint8List>();
      var subscription = client1
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            final roomInfo = RoomInfo.fromBytes(packet.data);
            completer.complete(roomInfo.roomId);
          });

      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      try {
        roomId = await completer.future;
      } finally {
        subscription.cancel();
      }
    });

    test('Client can join an existing room', () async {
      final joinCompleter = Completer<RoomInfo>();

      var joinSubscription = client2
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            try {
              final roomInfo = RoomInfo.fromBytes(packet.data);
              joinCompleter.complete(roomInfo);
            } catch (e) {
              joinCompleter.completeError(e);
            }
          });

      // Join the room with client2
      client2.sendNamedFunction(SwampCommand.joinRoom, roomId);

      RoomInfo joinedRoomInfo;
      try {
        joinedRoomInfo = await joinCompleter.future;

        // Validate room joining
        expect(joinedRoomInfo.roomId, roomId);
        expect(joinedRoomInfo.currentId, 2);
        expect(joinedRoomInfo.flags, 0);
      } finally {
        joinSubscription.cancel();
      }
    });

    test('Host is notified when another client joins', () async {
      final joinedCompleter = Completer<int>();

      // Listen for player joined event on host client
      var joinedSubscription = client1
          .registerNamedFunction(SwampEvent.playerJoined)
          .read
          .listen((packet) {
            try {
              final playerId = packet.data[0] << 8 | packet.data[1];
              joinedCompleter.complete(playerId);
            } catch (e) {
              joinedCompleter.completeError(e);
            }
          });

      // Join the room with client2
      client2.sendNamedFunction(SwampCommand.joinRoom, roomId);

      try {
        final playerId = await joinedCompleter.future;

        // Validate player joined notification
        expect(playerId, 2);
      } finally {
        joinedSubscription.cancel();
      }
    });
  });

  group('Messaging Tests', () {
    late Uint8List roomId;

    setUp(() async {
      // Create a room first
      final roomCompleter = Completer<Uint8List>();
      var roomSubscription = client1
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            final roomInfo = RoomInfo.fromBytes(packet.data);
            roomCompleter.complete(roomInfo.roomId);
          });

      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      try {
        roomId = await roomCompleter.future;
      } finally {
        roomSubscription.cancel();
      }

      // Join the room with client2
      final joinCompleter = Completer<void>();
      var joinSubscription = client2
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            joinCompleter.complete();
          });

      client2.sendNamedFunction(SwampCommand.joinRoom, roomId);

      try {
        await joinCompleter.future;
      } finally {
        joinSubscription.cancel();
      }

      // Wait to ensure join is fully processed
      await Future.delayed(const Duration(milliseconds: 100));
    });

    test('Client can send message to room', () async {
      final messageReceived = Completer<String>();
      const message = 'Hello, World!';

      var messageSubscription = client1
          .registerNamedFunction(SwampEvent.message)
          .read
          .listen((packet) {
            try {
              final receivedMessage = String.fromCharCodes(
                packet.data.sublist(2),
              );
              messageReceived.complete(receivedMessage);
            } catch (e) {
              messageReceived.completeError(e);
            }
          });

      // Send message from client2 to the room
      client2.sendNamedFunction(
        SwampCommand.message,
        Uint8List.fromList([0, 0, ...message.codeUnits]),
      );

      try {
        final receivedMessage = await messageReceived.future;

        // Validate received message
        expect(receivedMessage, message);
      } finally {
        messageSubscription.cancel();
      }
    });

    test('Messages include correct sender ID', () async {
      final messageReceived = Completer<Map<String, dynamic>>();
      const message = 'Message from client 2';

      var messageSubscription = client1
          .registerNamedFunction(SwampEvent.message)
          .read
          .listen((packet) {
            try {
              final senderId = packet.data[0] << 8 | packet.data[1];
              final receivedMessage = String.fromCharCodes(
                packet.data.sublist(2),
              );
              messageReceived.complete({
                'senderId': senderId,
                'message': receivedMessage,
              });
            } catch (e) {
              messageReceived.completeError(e);
            }
          });

      // Send message from client2 to the room
      client2.sendNamedFunction(
        SwampCommand.message,
        Uint8List.fromList([0, 0, ...message.codeUnits]),
      );

      try {
        final result = await messageReceived.future;

        // Validate sender ID and message content
        expect(result['senderId'], 2);
        expect(result['message'], message);
      } finally {
        messageSubscription.cancel();
      }
    });
  });

  group('Disconnection Tests', () {
    late Uint8List roomId;
    late int client2Id;

    setUp(() async {
      // Create a room with client1
      final roomCompleter = Completer<Uint8List>();
      var roomSubscription = client1
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            final roomInfo = RoomInfo.fromBytes(packet.data);
            roomCompleter.complete(roomInfo.roomId);
          });

      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      try {
        roomId = await roomCompleter.future;
      } finally {
        roomSubscription.cancel();
      }

      // Join the room with client2
      final joinCompleter = Completer<int>();
      var joinSubscription = client1
          .registerNamedFunction(SwampEvent.playerJoined)
          .read
          .listen((packet) {
            final id = packet.data[0] << 8 | packet.data[1];
            joinCompleter.complete(id);
          });

      client2.sendNamedFunction(SwampCommand.joinRoom, roomId);

      try {
        client2Id = await joinCompleter.future;
      } finally {
        joinSubscription.cancel();
      }
    });

    test('Host receives notification when client disconnects', () async {
      final disconnectCompleter = Completer<int>();

      var disconnectSubscription = client1
          .registerNamedFunction(SwampEvent.playerLeft)
          .read
          .listen((packet) {
            final leftId = packet.data[0] << 8 | packet.data[1];
            disconnectCompleter.complete(leftId);
          });

      // Disconnect client2
      await client2.close();

      try {
        final leftId = await disconnectCompleter.future;

        // Validate the correct client ID was reported as disconnected
        expect(leftId, client2Id);
      } finally {
        disconnectSubscription.cancel();
      }

      // Recreate client2 for tearDown
      client2 = RawSwampConnection(server: uri);
      await client2.init();
    });
  });

  group('Room Closing Tests', () {
    late Uint8List roomId;

    setUp(() async {
      // Create a room with client1
      final roomCompleter = Completer<Uint8List>();
      var roomSubscription = client1
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            final roomInfo = RoomInfo.fromBytes(packet.data);
            roomCompleter.complete(roomInfo.roomId);
          });

      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      try {
        roomId = await roomCompleter.future;
      } finally {
        roomSubscription.cancel();
      }

      // Join with client2
      final joinCompleter = Completer<void>();
      var joinSubscription = client2
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            joinCompleter.complete();
          });

      client2.sendNamedFunction(SwampCommand.joinRoom, roomId);

      try {
        await joinCompleter.future;
      } finally {
        joinSubscription.cancel();
      }
    });

    test('Host can close a room', () async {
      final roomClosedCompleter = Completer<void>();

      var closedSubscription = client2
          .registerNamedFunction(SwampEvent.welcome)
          .read
          .listen((packet) {
            roomClosedCompleter.complete();
          });

      // Host closes the room
      client1.sendNamedFunction(SwampCommand.leaveRoom, Uint8List(0));

      try {
        await roomClosedCompleter.future;

        // Successfully received room closed event
        expect(true, isTrue);
      } finally {
        closedSubscription.cancel();
      }
    });
  });

  group('Error Handling Tests', () {
    test('Attempting to join non-existent room returns error', () async {
      final errorCompleter = Completer<int>();

      var errorSubscription = client1
          .registerNamedFunction(SwampEvent.roomJoinFailed)
          .read
          .listen((packet) {
            final errorCode = packet.data[0];
            errorCompleter.complete(errorCode);
          });

      // Try to join a non-existent room
      final nonExistentRoomId = Uint8List.fromList(List.filled(16, 42));
      client1.sendNamedFunction(SwampCommand.joinRoom, nonExistentRoomId);

      try {
        final errorCode = await errorCompleter.future;

        // Validate error code (assuming error code for room not found is 1)
        expect(errorCode, JoinFailedReason.roomNotFound.value);
      } finally {
        errorSubscription.cancel();
      }
    });

    test('Client cannot create room while already in a room', () async {
      // First create a room
      final roomCompleter = Completer<Uint8List>();
      var roomSubscription = client1
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            final roomInfo = RoomInfo.fromBytes(packet.data);
            roomCompleter.complete(roomInfo.roomId);
          });

      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      try {
        await roomCompleter.future;
      } finally {
        roomSubscription.cancel();
      }

      // Now try to create another room while still in the first one
      final errorCompleter = Completer<int>();
      var errorSubscription = client1
          .registerNamedFunction(SwampEvent.roomCreationFailed)
          .read
          .listen((packet) {
            final errorCode = packet.data[0];
            errorCompleter.complete(errorCode);
          });

      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      try {
        final errorCode = await errorCompleter.future;

        // Validate error code (assuming error code for already in room is 2)
        expect(errorCode, CreationFailedReason.inRoom.value);
      } finally {
        errorSubscription.cancel();
      }
    });
  });

  group('Direct Messaging Tests', () {
    late Uint8List roomId;

    setUp(() async {
      // Create and join room as in previous tests
      final roomCompleter = Completer<Uint8List>();
      var roomSubscription = client1
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            final roomInfo = RoomInfo.fromBytes(packet.data);
            roomCompleter.complete(roomInfo.roomId);
          });

      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      try {
        roomId = await roomCompleter.future;
      } finally {
        roomSubscription.cancel();
      }

      // Join with client2
      final joinCompleter = Completer<void>();
      var joinSubscription = client2
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            joinCompleter.complete();
          });

      client2.sendNamedFunction(SwampCommand.joinRoom, roomId);

      try {
        await joinCompleter.future;
      } finally {
        joinSubscription.cancel();
      }
    });

    test('Client can send direct message to another client', () async {
      final directMessageCompleter = Completer<Map<String, dynamic>>();
      const message = 'Direct message test';

      var messageSubscription = client1
          .registerNamedFunction(SwampEvent.message)
          .read
          .listen((packet) {
            try {
              final senderId = packet.data[0] << 8 | packet.data[1];
              final receivedMessage = String.fromCharCodes(
                packet.data.sublist(2),
              );
              directMessageCompleter.complete({
                'senderId': senderId,
                'message': receivedMessage,
              });
            } catch (e) {
              directMessageCompleter.completeError(e);
            }
          });

      // Client2 sends direct message to client1 (ID 1)
      final directMessageData = Uint8List.fromList(
        [0, 1, ...message.codeUnits], // First two bytes represent target ID (1)
      );
      client2.sendNamedFunction(SwampCommand.message, directMessageData);

      try {
        final result = await directMessageCompleter.future;

        // Validate sender ID and message content
        expect(result['senderId'], 2); // Client2's ID
        expect(result['message'], message);
      } finally {
        messageSubscription.cancel();
      }
    });
  });

  group('Player List Tests', () {
    late Uint8List roomId;

    setUp(() async {
      final roomCompleter = Completer<Uint8List>();
      final roomSubscription = client1
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            roomCompleter.complete(RoomInfo.fromBytes(packet.data).roomId);
          });

      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));
      try {
        roomId = await roomCompleter.future;
      } finally {
        await roomSubscription.cancel();
      }

      final joinCompleter = Completer<void>();
      final joinSubscription = client2
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) => joinCompleter.complete());

      client2.sendNamedFunction(SwampCommand.joinRoom, roomId);
      try {
        await joinCompleter.future;
      } finally {
        await joinSubscription.cancel();
      }
    });

    test('Player list returns room player IDs with a length prefix', () async {
      final listCompleter = Completer<List<int>>();
      final subscription = client1
          .registerNamedFunction(SwampEvent.playerList)
          .read
          .listen((packet) {
            final data = packet.data;
            final count = data[0] << 8 | data[1];
            final players = <int>[];
            for (var i = 0; i < count; i++) {
              final offset = 2 + i * 2;
              players.add(data[offset] << 8 | data[offset + 1]);
            }
            listCompleter.complete(players);
          });

      client1.sendNamedFunction(SwampCommand.playerList, Uint8List(0));

      try {
        expect(await listCompleter.future, unorderedEquals([1, 2]));
      } finally {
        await subscription.cancel();
      }
    });
  });

  group('Kick Tests', () {
    late Uint8List roomId;

    setUp(() async {
      final roomCompleter = Completer<Uint8List>();
      final roomSubscription = client1
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) {
            roomCompleter.complete(RoomInfo.fromBytes(packet.data).roomId);
          });

      client1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));
      try {
        roomId = await roomCompleter.future;
      } finally {
        await roomSubscription.cancel();
      }

      final joinCompleter = Completer<void>();
      final joinSubscription = client2
          .registerNamedFunction(SwampEvent.roomInfo)
          .read
          .listen((packet) => joinCompleter.complete());

      client2.sendNamedFunction(SwampCommand.joinRoom, roomId);
      try {
        await joinCompleter.future;
      } finally {
        await joinSubscription.cancel();
      }
    });

    test('Non-host cannot kick another player', () async {
      final kicked = Completer<void>();
      final subscription = client1
          .registerNamedFunction(SwampEvent.kicked)
          .read
          .listen((packet) => kicked.complete());

      client2.sendNamedFunction(
        SwampCommand.kickPlayer,
        Uint8List.fromList([0, 1]),
      );

      try {
        await expectLater(
          kicked.future.timeout(const Duration(milliseconds: 250)),
          throwsA(isA<TimeoutException>()),
        );
      } finally {
        await subscription.cancel();
      }
    });

    test('Host can kick a room-local player ID', () async {
      final kicked = Completer<KickReason>();
      final subscription = client2
          .registerNamedFunction(SwampEvent.kicked)
          .read
          .listen((packet) {
            kicked.complete(KickReason.fromValue(packet.data[0]));
          });

      client1.sendNamedFunction(
        SwampCommand.kickPlayer,
        Uint8List.fromList([0, 2]),
      );

      try {
        expect(await kicked.future, KickReason.kicked);
      } finally {
        await subscription.cancel();
      }

      client2 = RawSwampConnection(server: uri);
      await client2.init();
    });
  });

  group('Room Flag Tests', () {
    test('Creating a dark room can be rejected by configuration', () async {
      await client1.close();
      await client2.close();
      await server.close();

      server = SwampServer(
        host,
        port,
        minLogLevel: LogLevel.verbose,
        withConsole: false,
        configManager: ConfigManager(const SwampConfig(noDarkRooms: true)),
      );
      await server.init();
      client1 = RawSwampConnection(server: uri);
      client2 = RawSwampConnection(server: uri);
      await client1.init();
      await client2.init();

      final failure = Completer<int>();
      final subscription = client1
          .registerNamedFunction(SwampEvent.roomCreationFailed)
          .read
          .listen((packet) => failure.complete(packet.data[0]));

      client1.sendNamedFunction(
        SwampCommand.createRoom,
        Uint8List.fromList([RoomFlags.darkRoomFlag]),
      );

      try {
        expect(
          await failure.future,
          CreationFailedReason.unsupportedFlags.value,
        );
      } finally {
        await subscription.cancel();
      }
    });
  });
}
