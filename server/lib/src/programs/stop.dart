import 'package:consoler/consoler.dart';
import 'package:swamp/src/server.dart';

class StopProgram extends ConsoleProgram {
  final SwampServer server;

  StopProgram(this.server);
  @override
  String getDescription() => "Stop the server";

  @override
  Future<void> run(String label, List<String> args) async {
    if (args.isNotEmpty) {
      print("Usage: stop");
      return;
    }
    print("Stopping server...");
    await server.close();
  }
}
