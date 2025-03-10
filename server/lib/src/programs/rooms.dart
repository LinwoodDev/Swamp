import 'package:consoler/consoler.dart';
import 'package:swamp/room.dart';
import 'package:swamp_api/models.dart';

const kPageSize = 10;

class RoomsProgram extends ConsoleProgram {
  final SwampRoomManager roomManager;

  RoomsProgram(this.roomManager);

  @override
  String getDescription() => "List all rooms";

  @override
  String getUsage() => '[<Page>]';

  @override
  void run(String label, List<String> args) {
    if (args.length > 1) {
      print('Usage: room ${getUsage()}');
      return;
    }
    final page = args.isEmpty ? 1 : int.tryParse(args[0]);
    if (page == null || page < 1) {
      print("Invalid page number");
      return;
    }
    final rooms =
        roomManager.rooms
            .skip((page - 1) * kPageSize)
            .take(kPageSize + 1)
            .toList();
    print("${rooms.length} room${rooms.length == 1 ? '' : 's'} (Page $page):");
    if (rooms.isEmpty) {
      print("No rooms found");
      return;
    }
    for (final room in rooms.asMap().entries.take(kPageSize)) {
      print(
        "${room.key + 1}. ${encodeRoomCode(room.value.roomId)} (${room.value.players.length} players)",
      );
    }
    if (rooms.length > kPageSize) {
      print("More rooms available. Use 'rooms ${page + 1}' to see more.");
    }
  }
}
