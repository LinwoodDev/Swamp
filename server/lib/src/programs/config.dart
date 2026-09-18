import 'dart:convert';

import 'package:consoler/consoler.dart';
import 'package:swamp/src/server.dart';

class ConfigProgram extends ConsoleProgram {
  final SwampServer server;

  ConfigProgram(this.server);
  @override
  String getDescription() => "Stop the server";

  @override
  void run(String label, List<String> args) {
    if (args.isNotEmpty) {
      print('Usage: config');
      return;
    }
    final config = server.config;
    print("""Configuration:
- Description: ${json.encode(config.description)}
- Max Players Per Room: ${config.maxPlayersPerRoom}
- Max Concurrent Players: ${config.maxConcurrentPlayers == 0 ? 'unlimited' : config.maxConcurrentPlayers}
- Max Rooms: ${config.maxRooms == 0 ? 'unlimited' : config.maxRooms}
- No Dark Rooms: ${config.noDarkRooms}""");
  }
}
