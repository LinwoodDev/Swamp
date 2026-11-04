import 'dart:async';
import 'dart:io';

import 'package:swamp/src/config.dart';
import 'package:swamp/src/programs/config.dart';
import 'package:swamp/src/programs/room.dart';
import 'package:swamp/src/programs/rooms.dart';
import 'package:swamp/src/programs/stop.dart';
import 'package:swamp/src/room.dart';
import 'package:swamp/src/server.dart';
import 'package:swamp_api/models.dart';
import 'package:test/test.dart';

List<String> capture(void Function() action) {
  final output = <String>[];
  runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => output.add(line),
    ),
  );
  return output;
}

void main() {
  test('room pages report total, capacity, and continuous numbering', () {
    final manager = SwampRoomManager(ConfigManager(const SwampConfig()));
    for (var channel = 1; channel <= 11; channel++) {
      manager.addRoom(channel);
    }
    final program = RoomsProgram(manager);
    final first = capture(() => program.run('rooms', []));
    expect(first.first, '11 rooms (Page 1/2):');
    expect(first.where((line) => line.contains('(1/1024 players)')).length, 10);
    expect(first.last, contains('rooms 2'));
    final second = capture(() => program.run('rooms', ['2']));
    expect(second.first, '11 rooms (Page 2/2):');
    expect(second[1], startsWith('11. '));
    expect(second.length, 2);
    expect(
      capture(() => program.run('rooms', ['3'])).single,
      contains('out of range'),
    );
  });

  test('room details use the same code as the room list', () {
    final manager = SwampRoomManager(ConfigManager(const SwampConfig()));
    manager.addRoom(1);
    final code = encodeRoomCode(manager.rooms.single.roomId);
    final lines = capture(() => RoomProgram(manager).run('room', [code]));
    expect(lines.first, 'Room $code:');
    expect(lines.last, contains('Players (1/1024):'));
  });

  test('rooms usage names the correct command', () {
    final manager = SwampRoomManager(ConfigManager(const SwampConfig()));
    expect(
      capture(() => RoomsProgram(manager).run('rooms', ['1', '2'])).single,
      'Usage: rooms [<Page>]',
    );
  });

  test(
    'console reload reports failure and retains the active configuration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'swamp-console-test-',
      );
      final file = File('${directory.path}/swamp.json');
      final manager = ConfigManager.withOptions(
        path: file.path,
        environment: {},
      );
      final server = SwampServer(
        '127.0.0.1',
        0,
        configManager: manager,
        withConsole: false,
      );
      final output = <String>[];
      try {
        final program = ConfigProgram(server);
        await file.writeAsString('{"description":"reloaded"}');
        await runZoned(
          () => program.run('config', ['reload']),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => output.add(line),
          ),
        );
        expect(manager.config.description, 'reloaded');
        expect(output.first, contains('Configuration reloaded'));
        output.clear();
        await file.writeAsString('[]');
        await runZoned(
          () => program.run('config', ['reload']),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => output.add(line),
          ),
        );
        expect(output.single, contains('Failed to reload'));
        expect(manager.config.description, 'reloaded');
        final stop = StopProgram(server);
        await runZoned(
          () => stop.run('stop', ['extra']),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => output.add(line),
          ),
        );
        expect(output.last, 'Usage: stop');
      } finally {
        await server.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
