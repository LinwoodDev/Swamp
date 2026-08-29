import 'package:consoler/consoler.dart';
import 'package:swamp/src/server.dart';
import 'package:swamp_api/connection.dart';
import 'package:test/test.dart';

void main() {
  test('removing a peer keeps the shared relay connection open', () async {
    final server = SwampServer(
      '127.0.0.1',
      0,
      minLogLevel: LogLevel.error,
      withConsole: false,
    );
    SwampConnection? host;
    SwampConnection? guest;

    try {
      await server.init();
      final uri = Uri.parse('ws://127.0.0.1:${server.server!.port}');

      host = SwampConnection(server: uri);
      final hostRoomInfo = host.onRoomInfo.first;
      await host.init();
      final room = await hostRoomInfo;

      final peerJoined = host.clientChange.firstWhere(
        (peers) => peers.isNotEmpty,
      );
      guest = SwampConnection(server: uri, roomId: room.roomId);
      await guest.init();
      await peerJoined;

      final peerLeft = host.clientChange.firstWhere((peers) => peers.isEmpty);
      await guest.close();
      await peerLeft;

      expect(host.isOpen, isTrue);
    } finally {
      await guest?.close();
      await host?.close();
      await server.close();
    }
  });
}
