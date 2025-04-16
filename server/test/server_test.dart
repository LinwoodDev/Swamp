import 'dart:async';
import 'dart:typed_data';

import 'package:networker/networker.dart';
import 'package:networker_socket/client.dart';
import 'package:swamp/server.dart';
import 'package:swamp_api/models.dart';
import 'package:test/test.dart';

void main() {
  final port = 8080;
  final host = '127.0.0.1';
  final uri = Uri.parse('ws://$host:$port');
  late SwampServer server;

  late NetworkerSocketClient client1, client2;
  late NamedRpcClientNetworkerPipe<SwampEvent, SwampCommand> pipe1, pipe2;

  setUpAll(() async {
    server = SwampServer(host, port);
    await server.init();

    client1 = NetworkerSocketClient(uri);
    client2 = NetworkerSocketClient(uri);
    pipe1 = NamedRpcClientNetworkerPipe<SwampEvent, SwampCommand>();
    pipe2 = NamedRpcClientNetworkerPipe<SwampEvent, SwampCommand>();
    client1.connect(pipe1);
    client2.connect(pipe2);

    await client1.init();
    await client2.init();
  });

  tearDownAll(() async {
    await client1.close();
    await client2.close();
    return server.close();
  });

  group('General Usage Tests', () {
    test('Create room', () async {
      final completer = Completer<void>();

      pipe1.registerNamedFunction(SwampEvent.roomInfo).read.listen((packet) {
        final roomInfo = RoomInfo.fromBytes(packet.data);
        expect(roomInfo.roomId, isNotNull);
        expect(roomInfo.currentId, 1);
        expect(roomInfo.flags, 0);
        completer.complete(); // Complete when the event is received
      });

      pipe1.sendNamedFunction(SwampCommand.createRoom, Uint8List(0));

      // Wait for the completer to complete or timeout after a small delay
      await completer.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => fail('roomInfo event was not received in time'),
      );
    });
  });
}
