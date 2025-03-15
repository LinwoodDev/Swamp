import 'dart:convert';

import 'package:swamp_api/connection.dart';
import 'package:swamp_api/models.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    print('Usage: host.dart <server> [<room>]');
    return;
  }
  final connection = SwampConnection(
    server: Uri.parse(args.elementAtOrNull(1) ?? 'ws://localhost:8080/ws'),
    roomId: decodeRoomCode(args[0]),
  );
  connection.onRoomInfo.listen((event) {
    print('Room joined');
  });
  connection.onJoinFailed.listen((event) {
    print('Failed to join room ($event)');
  });
  connection.onClosed.listen((event) {
    print('Connection closed');
  });
  connection.messagePipe.read.listen((event) {
    print('Received message: ${utf8.decode(event.data)}');
  });
  await connection.init();
  print('Connected to ${connection.server}');
}
