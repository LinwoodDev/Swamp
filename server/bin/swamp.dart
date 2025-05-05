import 'dart:io';

import 'package:consoler/consoler.dart';
import 'package:swamp/src/server.dart';

final welcomeMessage = """
   _____      _____   __  ______ 
  / __/ | /| / / _ | /  |/  / _ \\
 _\\ \\ | |/ |/ / __ |/ /|_/ / ___/
/___/ |__/|__/_/ |_/_/  /_/_/    

Universal Simple Web-Socket Application Messaging Proxy (Linwood SWAMP)

Website: https://swamp.linwood.dev

Type 'help' for a list of commands.
""";

Future<void> main(List<String> args) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  SecurityContext? securityContext;
  try {
    final privateKey = await File('certs/server.key').readAsBytes();
    final certificate = await File('certs/server.crt').readAsBytes();
    securityContext =
        SecurityContext()
          ..usePrivateKeyBytes(privateKey)
          ..useCertificateChainBytes(certificate);
  } on PathNotFoundException catch (_) {}
  final server = SwampServer(ip, port, securityContext: securityContext);
  server.log(welcomeMessage);
  if (securityContext != null) {
    server.log('Certificates found, using secure connection', LogLevel.info);
  } else {
    server.log(
      'No certificates found, using insecure connection',
      LogLevel.warning,
    );
  }
  await server.init();
  server.log('Server listening on port ${server.port}');
}
