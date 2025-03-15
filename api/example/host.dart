import 'dart:async';
import 'dart:convert';

import 'package:swamp_api/connection.dart';
import 'package:swamp_api/models.dart';

Future<void> main(List<String> args) async {
  final connection = SwampConnection.build(
    Uri.parse(args.elementAtOrNull(0) ?? 'ws://localhost:8080/ws'),
  );
  connection.onRoomInfo.listen((event) {
    print('Room created: ${encodeRoomCode(event.roomId)}');
  });
  connection.onCreationFailed.listen((event) {
    print('Failed to create room ($event)');
  });
  connection.onClosed.listen((event) {
    print('Connection closed');
  });
  await connection.init();
  print('Connected to ${connection.server}');
  await Future.delayed(Duration(seconds: 5));
  var i = 0;
  Timer.periodic(Duration(seconds: 2), (timer) {
    final message = 'Hello, World! ${i++}';
    connection.sendNamedFunction(SwampCommand.message, utf8.encode(message));
    print('Sent message: $message');
  });
}
