import 'dart:async';
import 'dart:convert';

import 'package:swamp_api/connection.dart';
import 'package:swamp_api/models.dart';

Future<void> main(List<String> args) async {
  final connection = SwampConnection.build(
    Uri.parse(args.elementAtOrNull(0) ?? 'ws://localhost:8080/ws'),
  );
  await Future.delayed(Duration(seconds: 5));
  Timer? timer;

  connection.onRoomInfo.listen((event) {
    print('Room created: ${encodeRoomCode(event.roomId)}');
    timer?.cancel();
    var i = 0;
    timer = Timer.periodic(Duration(seconds: 2), (timer) {
      final message = 'Hello, World! ${i++}';
      connection.messagePipe.sendMessage(utf8.encode(message));
      print('Sent message: $message');
    });
  });
  connection.onCreationFailed.listen((event) {
    print('Failed to create room ($event)');
  });
  connection.onClosed.listen((event) {
    print('Connection closed');
    timer?.cancel();
    timer = null;
  });
  connection.clientConnect.listen((event) {
    print('Client was connected: ${event.$1}');
  });
  connection.clientDisconnect.listen((event) {
    print('Client was disconnected: ${event.$1}');
  });
  await connection.init();
  print('Connected to ${connection.server}');
}
