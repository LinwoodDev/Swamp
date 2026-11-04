import 'dart:convert';

import 'package:consoler/consoler.dart';
import 'package:swamp/src/server.dart';

class ConfigProgram extends ConsoleProgram {
  final SwampServer server;

  ConfigProgram(this.server);
  @override
  String getDescription() => "Show or reload the server configuration";

  @override
  String getUsage() => '[reload]';

  @override
  Future<void> run(String label, List<String> args) async {
    if (args.length > 1 || (args.isNotEmpty && args.single != 'reload')) {
      print('Usage: config ${getUsage()}');
      return;
    }
    if (args.isNotEmpty) {
      try {
        await server.configManager.load();
        print('Configuration reloaded from ${server.configManager.path}.');
      } catch (error) {
        print('Failed to reload configuration: $error');
        return;
      }
    }
    final config = server.config;
    print("""Configuration (${server.configManager.path}):
- Description: ${json.encode(config.description)}
- Max Players Per Room: ${config.maxPlayersPerRoom}
- Max Concurrent Players: ${config.maxConcurrentPlayers == 0 ? 'unlimited' : config.maxConcurrentPlayers}
- Max Rooms: ${config.maxRooms == 0 ? 'unlimited' : config.maxRooms}
- No Dark Rooms: ${config.noDarkRooms}""");
  }
}
