import 'dart:typed_data';

import 'package:consoler/consoler.dart';
import 'package:networker/networker.dart';
import 'package:networker_socket/server.dart';
import 'package:swamp/room.dart';
import 'package:swamp/src/programs/room.dart';
import 'package:swamp/src/programs/rooms.dart';
import 'package:swamp/src/programs/stop.dart';
import 'package:swamp_api/models.dart';

class SwampServer extends NetworkerSocketServer {
  final SwampRoomManager _roomManager = SwampRoomManager();
  final NamedRpcClientNetworkerPipe<SwampCommand, SwampEvent> _rpcPipe =
      NamedRpcClientNetworkerPipe(config: RpcConfig(channelField: false));
  final Consoler _consoler = Consoler(
    defaultProgramConfig: DefaultProgramConfiguration(
      description: 'Swamp Server',
    ),
  );

  SwampServer(
    super.serverAddress,
    super.port, {
    bool withConsole = true,
    LogLevel? minLogLevel,
  }) {
    connect(_rpcPipe..connect(_roomManager));

    _initFunctions();
    _consoler.registerPrograms({
      'stop': StopProgram(this),
      'rooms': RoomsProgram(_roomManager),
      'room': RoomProgram(_roomManager),
    });
    _consoler.minLogLevel = minLogLevel ?? _consoler.minLogLevel;
    if (withConsole) _consoler.run();
  }

  void log(Object? message, [LogLevel? level]) =>
      _consoler.print(message, level: level);

  void _initFunctions() {
    clientConnect.listen((event) {
      log('Client connected: ${event.$1}', LogLevel.info);
    });
    clientDisconnect.listen((event) {
      _roomManager.leaveRoom(event.$1);
      log('Client disconnected: ${event.$1}', LogLevel.info);
    });
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
        log(
          'Room created: ${_roomManager.getChannelRoom(event.channel)}',
          LogLevel.info,
        );
      })
      ..registerNamedFunction(SwampCommand.joinRoom).read.listen((event) {
        final room = _roomManager.joinRoom(event.data, event.channel);
        if (room == null) {
          log('Client ${event.channel} failed to join room', LogLevel.warning);
          return;
        }
        log(
          'Client ${event.channel} joined room ${encodeRoomCode(event.data)}',
          LogLevel.info,
        );
      })
      ..registerNamedFunction(SwampCommand.leaveRoom).read.listen((event) {
        _roomManager.leaveRoom(event.channel);
        log('Client ${event.channel} left room', LogLevel.info);
      })
      ..registerNamedFunction(SwampCommand.kickPlayer).read.listen((event) {
        final player = event.data
            .sublist(0, 2)
            .buffer
            .asByteData()
            .getUint16(0);
        _roomManager.leaveRoom(player);
        log('Client ${event.channel} kicked from room', LogLevel.info);
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
        log('Player list sent to ${event.channel}', LogLevel.verbose);
      })
      ..registerNamedFunction(SwampCommand.setApplication).read.listen((event) {
        _roomManager.setApplication(event.channel, event.data);
        log('Application set for ${event.channel}', LogLevel.verbose);
      });
  }

  @override
  Future<void> close() async {
    _consoler.dispose();
    return super.close();
  }
}
