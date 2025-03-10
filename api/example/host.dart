import 'package:swamp_api/connection.dart';
import 'package:swamp_api/models.dart';

Future<void> main(List<String> args) async {
  final connection = SwampConnection.build(
    Uri.parse(args.elementAtOrNull(0) ?? 'ws://localhost:8080/ws'),
  );
  connection.onRoomInfo.listen((event) {
    print('Room ${encodeRoomCode(event.roomId)}');
  });
  connection.onCreationFailed.listen((event) {
    print('Failed to create room');
  });
  connection.onClosed.listen((event) {
    print('Connection closed');
  });
  await connection.init();
  print('Connected to ${connection.server}');
}
