import 'dart:io';

import 'package:swamp/server.dart';

final welcomeMessage = """
   _____      _____   __  ______ 
  / __/ | /| / / _ | /  |/  / _ \\
 _\\ \\ | |/ |/ / __ |/ /|_/ / ___/
/___/ |__/|__/_/ |_/_/  /_/_/    
                                 
Type 'help' for a list of commands.
""";

Future<void> main(List<String> args) async {
  print(welcomeMessage);
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = SwampServer(ip, port);
  await server.init();
  print('Server listening on port ${server.port}');
}
