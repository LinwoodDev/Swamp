import 'package:consoler/consoler.dart';
import 'package:swamp/src/room.dart';
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
      print('Usage: rooms ${getUsage()}');
      return;
    }
    final page = args.isEmpty ? 1 : int.tryParse(args[0]);
    if (page == null || page < 1) {
      print("Invalid page number");
      return;
    }
    final allRooms = roomManager.rooms.toList();
    final pageCount = (allRooms.length / kPageSize).ceil();
    if (allRooms.isEmpty) {
      print("No rooms found");
      return;
    }
    if (page > pageCount) {
      print(
        "Page $page is out of range. Choose a page between 1 and $pageCount.",
      );
      return;
    }
    final offset = (page - 1) * kPageSize;
    final rooms = allRooms.skip(offset).take(kPageSize).toList();
    print(
      "${allRooms.length} room${allRooms.length == 1 ? '' : 's'} (Page $page/$pageCount):",
    );
    for (final room in rooms.asMap().entries.take(kPageSize)) {
      print(
        "${offset + room.key + 1}. ${encodeRoomCode(room.value.roomId)} (${room.value.players.length}/${room.value.maxPlayers} players)",
      );
    }
    if (page < pageCount) {
      print("More rooms available. Use 'rooms ${page + 1}' to see more.");
    }
  }
}
