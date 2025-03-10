import 'package:consoler/consoler.dart';
import 'package:swamp/room.dart';
import 'package:swamp_api/models.dart';

class RoomProgram extends ConsoleProgram {
  final SwampRoomManager roomManager;

  RoomProgram(this.roomManager);

  @override
  String getDescription() => "Get room details";

  @override
  String getUsage() => '<RoomId>';

  @override
  void run(String label, List<String> args) {
    if (args.length != 1) {
      print("Usage: room ${getUsage()}");
      return;
    }
    final roomId = decodeRoomCode(args[0]);
    final room = roomManager.getRoom(roomId);
    if (room == null) {
      print("Room not found");
      return;
    }
    print("Room $roomId:");
    print("Flags: ${room.roomFlags.value.toRadixString(2).padLeft(32, '0')}");
    print(
      "Players (${room.players.length}): ${room.players.map((e) => e.toString()).join(', ')}",
    );
  }
}
