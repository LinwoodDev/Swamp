import 'package:consoler/consoler.dart';
import 'package:swamp/src/options.dart';
import 'package:test/test.dart';

void main() {
  test('defaults disable interactive console for redirected input', () {
    final options = SwampServerOptions.parse(
      [],
      environment: {},
      hasTerminal: false,
    );
    expect(options.host, '0.0.0.0');
    expect(options.port, 8080);
    expect(options.configPath, 'swamp.json');
    expect(options.withConsole, isFalse);
    expect(options.logLevel, LogLevel.info);
    expect(
      SwampServerOptions.parse(
        [],
        environment: {},
        hasTerminal: true,
      ).withConsole,
      isTrue,
    );
  });

  test('command line overrides environment and terminal detection', () {
    final options = SwampServerOptions.parse(
      [
        '--host',
        '127.0.0.1',
        '--port',
        '9090',
        '--config',
        '/tmp/custom.json',
        '--no-console',
        '--log-level',
        'warning',
      ],
      environment: {
        'HOST': '0.0.0.0',
        'PORT': 'invalid',
        'SWAMP_CONFIG': 'old.json',
        'SWAMP_LOG_LEVEL': 'verbose',
      },
      hasTerminal: true,
    );
    expect(options.host, '127.0.0.1');
    expect(options.port, 9090);
    expect(options.configPath, '/tmp/custom.json');
    expect(options.withConsole, isFalse);
    expect(options.logLevel, LogLevel.warning);
    expect(
      SwampServerOptions.parse(
        ['--console'],
        environment: {},
        hasTerminal: false,
      ).withConsole,
      isTrue,
    );
  });

  test('help does not require a valid deployment environment', () {
    expect(
      SwampServerOptions.parse(
        ['--help'],
        environment: {'PORT': 'oops', 'SWAMP_LOG_LEVEL': 'oops'},
      ).help,
      isTrue,
    );
  });

  test('invalid options fail before startup', () {
    for (final args in [
      ['--port', '0'],
      ['--port', '65536'],
      ['--port', 'oops'],
      ['--host', ''],
      ['--config', ''],
      ['--log-level', 'oops'],
      ['unexpected'],
      ['--unknown'],
    ]) {
      expect(
        () => SwampServerOptions.parse(args, environment: {}),
        throwsFormatException,
      );
    }
  });
}
