import 'dart:io';

import 'package:args/args.dart';
import 'package:consoler/consoler.dart';

/// Startup options for the standalone server.
final class SwampServerOptions {
  final String host;
  final int port;
  final String configPath;
  final bool withConsole;
  final LogLevel logLevel;
  final bool help;

  const SwampServerOptions({
    required this.host,
    required this.port,
    required this.configPath,
    required this.withConsole,
    required this.logLevel,
    required this.help,
  });

  static ArgParser get parser => ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
    ..addOption('host', help: 'Bind address (HOST, default: 0.0.0.0).')
    ..addOption('port', abbr: 'p', help: 'Listen port (PORT, default: 8080).')
    ..addOption(
      'config',
      abbr: 'c',
      help: 'JSON configuration path (SWAMP_CONFIG, default: swamp.json).',
    )
    ..addFlag(
      'console',
      help: 'Enable the interactive console (default: terminal input only).',
    )
    ..addOption(
      'log-level',
      allowed: LogLevel.values.map((level) => level.name).toList(),
      help: 'Minimum log level (SWAMP_LOG_LEVEL, default: info).',
    );

  factory SwampServerOptions.parse(
    List<String> args, {
    Map<String, String>? environment,
    bool? hasTerminal,
  }) {
    final options = parser.parse(args);
    final env = environment ?? Platform.environment;
    if (options.rest.isNotEmpty) {
      throw const FormatException('Unexpected positional arguments.');
    }
    final help = options.flag('help');
    // Help should work even when the deployment environment is invalid.
    final rawPort = help
        ? '8080'
        : options.option('port') ?? env['PORT'] ?? '8080';
    final port = int.tryParse(rawPort);
    if (port == null || port < 1 || port > 65535) {
      throw const FormatException('PORT/--port must be between 1 and 65535.');
    }
    final rawLevel = help
        ? 'info'
        : options.option('log-level') ?? env['SWAMP_LOG_LEVEL'] ?? 'info';
    final logLevel = LogLevel.values
        .where((level) => level.name == rawLevel)
        .firstOrNull;
    if (logLevel == null) {
      throw const FormatException(
        'SWAMP_LOG_LEVEL must be verbose, info, warning, or error.',
      );
    }
    final host = options.option('host') ?? env['HOST'] ?? '0.0.0.0';
    final configPath =
        options.option('config') ?? env['SWAMP_CONFIG'] ?? 'swamp.json';
    if (!help && (host.trim().isEmpty || configPath.trim().isEmpty)) {
      throw const FormatException(
        'Host and configuration path must not be empty.',
      );
    }
    return SwampServerOptions(
      host: host,
      port: port,
      configPath: configPath,
      withConsole: options.wasParsed('console')
          ? options.flag('console')
          : hasTerminal ?? stdin.hasTerminal,
      logLevel: logLevel,
      help: help,
    );
  }
}
