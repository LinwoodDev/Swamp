import 'package:consoler/consoler.dart';
import 'package:swamp/src/server.dart';

const kPageSize = 10;

class InfoProgram extends ConsoleProgram {
  final SwampServer server;

  InfoProgram(this.server);

  @override
  String getDescription() => "Get server information";

  @override
  void run(String label, List<String> args) {
    if (args.isNotEmpty) {
      print('Usage: info');
      return;
    }
    final roomCount = server.roomManager.rooms.length;
    final playerCount = server.clientConnections.length;

    print("""Server Information:
- Rooms: $roomCount
- Players: $playerCount""");
  }
}
