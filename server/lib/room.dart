import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:networker/networker.dart';
import 'package:swamp_api/models.dart';

final class SwampRoom {
  final Uint8List roomId;
  final RoomFlags roomFlags;
  // Key is the player, value is the channel.
  final Map<Channel, Channel> _playerChannels = {};

  SwampRoom._(this.roomId, {this.roomFlags = const RoomFlags(0)});

  @override
  String toString() => encodeRoomCode(roomId);

  @override
  int get hashCode => toString().hashCode;

  bool get isEmpty => _playerChannels.isEmpty;

  @override
  bool operator ==(Object other) {
    if (other is SwampRoom) {
      return roomId == other.roomId;
    }
    return false;
  }

  Channel? getChannel(Channel player) => _playerChannels[player];

  Set<Channel> get players => _playerChannels.keys.toSet();

  Channel? getPlayer(Channel channel) {
    for (final entry in _playerChannels.entries) {
      if (entry.value == channel) {
        return entry.key;
      }
    }
    return null;
  }
}

const kRoomIdLength = 8 * 4;

Uint8List generateRandomRoomId() {
  final random = Random.secure();
  return Uint8List.fromList(
    List.generate(kRoomIdLength, (_) => random.nextInt(256)),
  );
}

final class SwampRoomManager extends SimpleNetworkerPipe<RpcNetworkerPacket> {
  final Set<SwampRoom> _rooms = {};
  final Map<Channel, SwampRoom> _joined = {};

  SwampRoom addRoom(
    Channel owner, [
    Uint8List? roomId,
    RoomFlags roomFlags = const RoomFlags(0),
  ]) {
    leaveRoom(owner);
    roomId ??= generateRandomRoomId();
    final room = SwampRoom._(roomId, roomFlags: roomFlags);
    _rooms.add(room);
    _joined[owner] = room;
    room._playerChannels[owner] = kAuthorityChannel;
    return room;
  }

  FutureOr<void> removeRoom(Uint8List roomId) =>
      _rooms.remove(SwampRoom._(roomId));

  SwampRoom? getRoom(Uint8List roomId) => _rooms.lookup(SwampRoom._(roomId));

  SwampRoom? getChannelRoom(Channel channel) => _joined[channel];

  void _sendKickMessage(
    Channel channel,
    KickReason reason, [
    String message = '',
  ]) {
    final builder = BytesBuilder();
    builder.addByte(0x03);
    builder.addByte(reason.index);
    builder.add(Uint8List.fromList(message.codeUnits));
    sendMessage(
      RpcNetworkerPacket.named(
        name: SwampEvent.kicked,
        data: builder.toBytes(),
      ),
      channel,
    );
  }

  void sendRoomInfo(Channel channel) {
    final room = getChannelRoom(channel);
    if (room == null) {
      sendMessage(
        RpcNetworkerPacket.named(name: SwampEvent.welcome, data: Uint8List(0)),
      );
      return;
    }
    final player = room.getPlayer(channel);
    if (player == null) return;
    final info = RoomInfo(
      currentId: player,
      flags: room.roomFlags.value,
      maxPlayers: 0,
      roomId: room.roomId,
    );
    sendMessage(
      RpcNetworkerPacket.named(name: SwampEvent.roomInfo, data: info.toBytes()),
    );
  }

  void leaveRoom(Channel channel) {
    final room = _joined.remove(channel);
    if (room == null) return;
    final player = room.getPlayer(channel);
    if (player == null) return;
    room._playerChannels.remove(player);
    if (room.isEmpty) {
      _rooms.remove(room);
      return;
    }
    if (player == kAuthorityChannel) {
      for (final player in room.players) {
        _sendKickMessage(player, KickReason.roomClosed);
      }
      room.players.clear();
    }
  }

  void sendMessageToRoom(
    Uint8List roomId,
    Channel receiver,
    RpcNetworkerPacket data,
  ) {
    final room = getRoom(roomId);
    if (room == null) return;
    final receivers = <Channel>[];
    if (receiver == kAnyChannel) {
      receivers.addAll(room._playerChannels.keys);
    } else {
      final channel = room.getChannel(receiver);
      if (channel == null) return;
      receivers.add(channel);
    }
    for (final receiver in receivers) {
      sendMessage(data, receiver);
    }
  }
}
