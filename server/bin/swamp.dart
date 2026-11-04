import 'dart:async';
import 'dart:io';

import 'package:consoler/consoler.dart';
import 'package:swamp/src/authentication.dart';
import 'package:swamp/src/server.dart';
import 'package:swamp/src/config.dart';
import 'package:swamp/src/options.dart';

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
  late final SwampServerOptions options;
  try {
    options = SwampServerOptions.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('Invalid startup options: ${error.message}');
    stderr.writeln("Use --help for usage.");
    exitCode = 2;
    return;
  }
  if (options.help) {
    stdout.writeln('Usage: swamp [options]');
    stdout.writeln(SwampServerOptions.parser.usage);
    return;
  }

  SwampServer? server;
  try {
    final configManager = ConfigManager.withOptions(path: options.configPath);
    await configManager.load();
    SecurityContext? securityContext;
    final key = File('certs/server.key');
    final certificate = File('certs/server.crt');
    final hasKey = await key.exists();
    final hasCertificate = await certificate.exists();
    if (hasKey != hasCertificate) {
      throw const FormatException(
        'TLS requires both certs/server.key and certs/server.crt.',
      );
    }
    if (hasKey) {
      securityContext = SecurityContext()
        ..usePrivateKeyBytes(await key.readAsBytes())
        ..useCertificateChainBytes(await certificate.readAsBytes());
    }
    server = SwampServer(
      options.host,
      options.port,
      configManager: configManager,
      withConsole: options.withConsole,
      minLogLevel: options.logLevel,
      securityContext: securityContext,
      authentication: swampAuthenticationFromEnvironment(Platform.environment),
    );
    server.log(options.withConsole ? welcomeMessage : 'Linwood Swamp');
    server.log(
      securityContext == null
          ? 'No certificates found, using insecure connection'
          : 'Certificates found, using secure connection',
      securityContext == null ? LogLevel.warning : LogLevel.info,
    );
    await server.init();
    server.log(
      'Server listening on ${options.host}:${server.port}',
      LogLevel.info,
    );
    final runningServer = server;
    final signals = <StreamSubscription<ProcessSignal>>[];
    void stop(ProcessSignal signal) {
      runningServer.log('Stopping server...', LogLevel.info);
      unawaited(runningServer.close());
    }

    signals.add(ProcessSignal.sigint.watch().listen(stop));
    if (!Platform.isWindows) {
      signals.add(ProcessSignal.sigterm.watch().listen(stop));
    }
    runningServer.onClosed.listen((_) {
      for (final signal in signals) {
        unawaited(signal.cancel());
      }
    });
  } catch (error) {
    stderr.writeln('Failed to start Swamp: $error');
    await server?.close();
    exitCode = 1;
  }
}
