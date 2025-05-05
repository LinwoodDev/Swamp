import 'dart:convert';

import 'package:consoler/consoler.dart';
import 'package:swamp/src/server.dart';

class StopProgram extends ConsoleProgram {
  final SwampServer server;

  StopProgram(this.server);
  @override
  String getDescription() => "Stop the server";

  @override
  void run(String label, List<String> args) {
    final config = server.config;
    print("""Configuration:
    - Description: ${json.encode(config.description)}
    - Max Players: ${config.maxPlayers}
    - No Dark Rooms: ${config.noDarkRooms}
    """);
  }
}
