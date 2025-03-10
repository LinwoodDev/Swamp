import 'dart:typed_data';

import 'package:consoler/consoler.dart';
import 'package:networker/networker.dart';
import 'package:networker_socket/server.dart';
import 'package:swamp/room.dart';
import 'package:swamp/src/programs/stop.dart';
import 'package:swamp_api/models.dart';

final class SwampRoom {
  final int roomFlags;

  SwampRoom({required this.roomFlags});
}

class SwampServer extends NetworkerSocketServer {
  final SwampRoomManager _roomManager = SwampRoomManager();
  final NamedRpcClientNetworkerPipe<SwampCommand, SwampEvent> _rpcPipe =
      NamedRpcClientNetworkerPipe(config: RpcConfig(channelField: false));
  final Consoler _consoler = Consoler(
    defaultProgramConfig: DefaultProgramConfiguration(
      description: 'Swamp Server',
    ),
  );

  SwampServer(super.serverAddress, super.port) {
    connect(_rpcPipe..connect(_roomManager));

    _initFunctions();
    _consoler.registerPrograms({'stop': StopProgram(this)});
    _consoler.run();
  }

  void _initFunctions() {
    _rpcPipe
      ..registerNamedFunction(SwampCommand.message).read.listen((event) {
        final sender = event.channel;
        final receiver = event.data
            .sublist(0, 2)
            .buffer
            .asByteData()
            .getUint16(0);
        final message = event.data.sublist(2);
        _roomManager.sendMessageToRoom(sender, receiver, message);
      })
      ..registerNamedFunction(SwampCommand.createRoom).read.listen((event) {
        _roomManager.addRoom(event.channel);
      })
      ..registerNamedFunction(SwampCommand.joinRoom).read.listen((event) {
        _roomManager.joinRoom(event.data, event.channel);
      })
      ..registerNamedFunction(SwampCommand.leaveRoom).read.listen((event) {
        _roomManager.leaveRoom(event.channel);
      })
      ..registerNamedFunction(SwampCommand.kickPlayer).read.listen((event) {
        final player = event.data
            .sublist(0, 2)
            .buffer
            .asByteData()
            .getUint16(0);
        final reason = String.fromCharCodes(event.data.sublist(2));
        _roomManager.leaveRoom(player, reason: reason);
      })
      ..registerNamedFunction(SwampCommand.playerList).read.listen((event) {
        final players =
            _roomManager.getChannelRoom(event.channel)?.channels ?? <Channel>[];
        final builder = BytesBuilder();
        builder.addByte(players.length >> 8);
        builder.addByte(players.length & 0xFF);
        for (final player in players) {
          builder.addByte(player >> 8);
          builder.addByte(player & 0xFF);
        }
        _rpcPipe.sendNamedFunction(
          SwampEvent.playerList,
          builder.toBytes(),
          channel: event.channel,
        );
      })
      ..registerNamedFunction(SwampCommand.setApplication).read.listen((event) {
        _roomManager.setApplication(event.channel, event.data);
      });
  }
}
