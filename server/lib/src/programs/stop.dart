import 'package:consoler/consoler.dart';
import 'package:swamp/server.dart';

class StopProgram extends ConsoleProgram {
  final SwampServer server;

  StopProgram(this.server);
  @override
  String getDescription() => "Stop the server";

  @override
  void run(String label, List<String> args) {
    print("Stopping server...");
    server.close();
  }
}
