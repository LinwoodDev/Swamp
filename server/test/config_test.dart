import 'dart:io';

import 'package:swamp/src/config.dart';
import 'package:test/test.dart';

void main() {
  test('environment false and empty description override file values', () {
    final config = SwampConfig.withEnvironment(
      {'noDarkRooms': true, 'description': 'from file', 'maxRooms': 10},
      environment: {
        'SWAMP_NO_DARK_ROOMS': 'false',
        'SWAMP_DESCRIPTION': '',
        'SWAMP_MAX_ROOMS': '0',
      },
    );
    expect(config.noDarkRooms, isFalse);
    expect(config.description, isEmpty);
    expect(config.maxRooms, 0);
  });

  test('explicit overrides take precedence over environment values', () {
    final config = SwampConfig.withEnvironment(
      {'maxRooms': 10, 'noDarkRooms': false},
      environment: {
        'SWAMP_MAX_ROOMS': 'invalid',
        'SWAMP_NO_DARK_ROOMS': 'true',
      },
      maxRooms: 2,
      noDarkRooms: false,
    );
    expect(config.maxRooms, 2);
    expect(config.noDarkRooms, isFalse);
  });

  test('boolean environment accepts both values and numeric forms', () {
    for (final raw in ['true', '1', ' TRUE ']) {
      expect(
        SwampConfig.withEnvironment(
          {},
          environment: {'SWAMP_NO_DARK_ROOMS': raw},
        ).noDarkRooms,
        isTrue,
      );
    }
    for (final raw in ['false', '0', ' FALSE ']) {
      expect(
        SwampConfig.withEnvironment(
          {'noDarkRooms': true},
          environment: {'SWAMP_NO_DARK_ROOMS': raw},
        ).noDarkRooms,
        isFalse,
      );
    }
  });

  test('invalid environment values and protocol limits are rejected', () {
    for (final env in [
      {'SWAMP_MAX_ROOMS': 'lots'},
      {'SWAMP_MAX_ROOMS': '-1'},
      {'SWAMP_MAX_CONCURRENT_PLAYERS': '-1'},
      {'SWAMP_MAX_PLAYERS_PER_ROOM': '0'},
      {'SWAMP_MAX_PLAYERS_PER_ROOM': '65536'},
      {'SWAMP_NO_DARK_ROOMS': 'maybe'},
    ]) {
      expect(
        () => SwampConfig.withEnvironment({}, environment: env),
        throwsFormatException,
      );
    }
    expect(
      () => SwampConfig.withEnvironment({'maxRooms': -1}, environment: {}),
      throwsFormatException,
    );
    expect(
      SwampConfig.withEnvironment({
        'maxPlayersPerRoom': 65535,
      }, environment: {}).maxPlayersPerRoom,
      65535,
    );
  });

  group('configuration file loading', () {
    late Directory directory;
    late File file;
    late ConfigManager manager;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('swamp-config-test-');
      file = File('${directory.path}/swamp.json');
      manager = ConfigManager.withOptions(
        path: file.path,
        environment: {'SWAMP_MAX_ROOMS': '3'},
      );
    });
    tearDown(() => directory.delete(recursive: true));

    test(
      'reload merges environment and preserves config after failure',
      () async {
        await file.writeAsString('{"description":"first", "maxRooms":8}');
        await manager.load();
        expect(manager.config.description, 'first');
        expect(manager.config.maxRooms, 3);
        for (final invalid in ['[]', '{', '{"maxPlayersPerRoom":0}']) {
          await file.writeAsString(invalid);
          await expectLater(manager.load(), throwsFormatException);
          expect(manager.config.description, 'first');
        }
        await file.writeAsString('{"description":"second"}');
        await manager.load();
        expect(manager.config.description, 'second');
        await file.delete();
        await manager.load();
        expect(manager.config.description, isEmpty);
        expect(manager.config.maxRooms, 3);
        expect(manager.config.maxPlayersPerRoom, 1024);
      },
    );
  });
}
