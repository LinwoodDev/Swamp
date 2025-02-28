library;

import 'dart:async';
import 'dart:typed_data';

import 'package:networker/networker.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

String createRoomCode(Uint8List data) {
  return data.map((e) => e.toRadixString(16)).join();
}

Uint8List parseRoomCode(String code) {
  return Uint8List.fromList(
    code.split('').map((e) => int.parse(e, radix: 16)).toList(),
  );
}

final class RoomInfo {
  final int flags;
  final int maxPlayers;
  final int currentId;
  final Uint8List roomId;

  RoomInfo({
    required this.flags,
    required this.maxPlayers,
    required this.currentId,
    required this.roomId,
  });
}

final class SwampClientConnectionInfo extends ConnectionInfo {
  final SwampConnection parent;
  final Channel channel;

  SwampClientConnectionInfo(this.parent, this.channel);

  @override
  Uri get address => parent.address;

  @override
  Future<void> close([String? message]) async {
    final socketChannel = parent._channel;
    if (socketChannel == null) return;
    socketChannel.sink.add([
      0x04,
      channel >> 8,
      channel & 0xFF,
      ...?message?.codeUnits,
    ]);
    return socketChannel.sink.close();
  }

  @override
  bool get isClosed => parent.clientConnections.contains(channel);

  @override
  void sendMessage(Uint8List data) {
    final socketChannel = parent._channel;
    if (socketChannel == null) return;
    socketChannel.sink.add([0x06, channel >> 8, channel & 0xFF, ...data]);
  }
}

final class SwampConnection extends NetworkerServer {
  final StreamController<void> _onOpen = StreamController<void>.broadcast(),
      _onClosed = StreamController<void>.broadcast();
  final String Function(Uint8List) roomCodeGenerator;
  final Uri server;
  final Uint8List? roomId;

  WebSocketChannel? _channel;
  RoomInfo? _roomInfo;

  @override
  Uri get address {
    final id = _roomInfo?.roomId ?? roomId;
    return server.replace(fragment: id == null ? null : roomCodeGenerator(id));
  }

  SwampConnection({
    required this.server,
    this.roomId,
    this.roomCodeGenerator = createRoomCode,
  });

  factory SwampConnection.build(
    String address, {
    Uint8List? roomId,
    String Function(Uint8List)? roomCodeGenerator,
  }) {
    final uri = Uri.parse(address);
    return SwampConnection(
      server: uri.replace(fragment: ''),
      roomId: roomId,
      roomCodeGenerator: roomCodeGenerator ?? createRoomCode,
    );
  }

  @override
  FutureOr<void> close() {
    _channel?.sink.close();
    _channel = null;
    _roomInfo = null;
  }

  @override
  FutureOr<void> init() {
    _channel = WebSocketChannel.connect(address);
    _channel?.stream.listen(_onMessage);
  }

  @override
  bool get isClosed => _channel == null || _channel?.closeCode != null;

  @override
  Stream<void> get onClosed => _onClosed.stream;

  @override
  Stream<void> get onOpen => _onOpen.stream;

  void _onMessage(event) {
    final message = Uint8List.fromList(
      event is String ? event.codeUnits : event,
    );
    final eventCode = message[0] << 8 | message[1];
    final data = message.sublist(2);
    switch (eventCode) {
      case 0x00:
        final playerId = data[0] << 8 | data[1];
        final message = data.sublist(2);
        onMessage(message, playerId);
      case 0x01:
        final flags = data[0];
        final maxPlayers = data[1] << 8 | data[2];
        final currentId = data[3] << 8 | data[4];
        final roomId = data.sublist(5);
        _roomInfo = RoomInfo(
          flags: flags,
          maxPlayers: maxPlayers,
          currentId: currentId,
          roomId: roomId,
        );
      case 0x02:
        _roomInfo = null;
      case 0x03:
        final playerId = data[0] << 8 | data[1];
        addClientConnection(
          SwampClientConnectionInfo(this, playerId),
          playerId,
        );
      case 0x04:
        final playerId = data[0] << 8 | data[1];
        removeConnection(playerId);
      case 0x05:
        clearConnections();
        final playerIds = <Channel>{};
        for (var i = 0; i < data.length; i += 2) {
          playerIds.add(data[i] << 8 | data[i + 1]);
        }
        for (final id in playerIds) {
          if (clientConnections.contains(id)) continue;
          addClientConnection(SwampClientConnectionInfo(this, id), id);
        }
        for (final id in clientConnections) {
          if (playerIds.contains(id)) continue;
          removeConnection(id);
        }
    }
  }

  @override
  Future<void> sendMessage(
    Uint8List data, [
    Channel channel = kAnyChannel,
  ]) async {
    if (channel == kAnyChannel || channel < 0) {
      _channel?.sink.add([0, ...data]);
      await _channel?.sink.done;
    } else {
      getConnectionInfo(channel)?.sendMessage(data);
    }
  }
}
