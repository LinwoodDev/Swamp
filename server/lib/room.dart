import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:networker/networker.dart';
import 'package:swamp_api/models.dart';

final class SwampRoom {
  final Uint8List roomId;
  final RoomFlags roomFlags;
  final Uint8List? application;
  // Key is the player, value is the channel.
  final Map<Channel, Channel> _playerChannels = {};

  SwampRoom._(
    this.roomId, {
    this.roomFlags = const RoomFlags(),
    this.application,
  });

  @override
  String toString() => encodeRoomCode(roomId);

  @override
  int get hashCode => toString().hashCode;

  bool get isEmpty => _playerChannels.isEmpty;

  @override
  bool operator ==(Object other) {
    if (other is SwampRoom) {
      return encodeRoomCode(roomId) == encodeRoomCode(other.roomId);
    }
    return false;
  }

  Channel? getChannel(Channel player) => _playerChannels[player];

  Set<Channel> get players => _playerChannels.keys.toSet();
  Set<Channel> get channels => _playerChannels.values.toSet();

  Channel get owner => getPlayer(kAuthorityChannel) ?? kAnyChannel;

  Channel? getPlayer(Channel channel) {
    for (final entry in _playerChannels.entries) {
      if (entry.value == channel) {
        return entry.key;
      }
    }
    return null;
  }

  Channel _findAvailableChannel() {
    final keys = _playerChannels.values.toList();
    for (var i = 2; i < 2 ^ 16; i++) {
      if (!keys.contains(i)) {
        return i;
      }
    }
    return kAnyChannel;
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
  final Map<Channel, Uint8List> _application = {};

  SwampRoom? joinRoom(Uint8List roomId, Channel player) {
    final room = getRoom(roomId);
    if (room == null) {
      _sendJoinFailed(player, JoinFailedReason.roomNotFound);
      return null;
    }
    final application = _application[player];
    if (application != null &&
        room.application != null &&
        encodeRoomCode(room.application!) != encodeRoomCode(application)) {
      _sendJoinFailed(player, JoinFailedReason.roomFull);
      return null;
    }
    final id = room._findAvailableChannel();
    if (id == kAnyChannel) {
      _sendJoinFailed(player, JoinFailedReason.roomFull);
      return null;
    }
    _joined[player] = room;
    room._playerChannels[player] = id;
    sendRoomInfo(player);
    _sendPacketToRoom(
      room,
      RpcNetworkerPacket.named(
        name: SwampEvent.playerJoined,
        data: Uint8List.fromList([id >> 8, id & 0xFF]),
      ),
    );
    return room;
  }

  SwampRoom addRoom(Channel owner, [RoomFlags roomFlags = const RoomFlags()]) {
    leaveRoom(owner);
    final roomId = generateRandomRoomId();
    final room = SwampRoom._(
      roomId,
      roomFlags: roomFlags,
      application: _application[owner],
    );
    _rooms.add(room);
    _joined[owner] = room;
    room._playerChannels[owner] = kAuthorityChannel;
    sendRoomInfo(owner);
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
    builder.addByte(reason.value);
    builder.add(Uint8List.fromList(message.codeUnits));
    sendMessage(
      RpcNetworkerPacket.named(
        name: SwampEvent.kicked,
        data: builder.toBytes(),
      ),
      channel,
    );
  }

  void _sendJoinFailed(Channel channel, JoinFailedReason reason) {
    final builder = BytesBuilder();
    builder.addByte(reason.value);
    sendMessage(
      RpcNetworkerPacket.named(
        name: SwampEvent.roomJoinFailed,
        data: builder.toBytes(),
      ),
      channel,
    );
  }

  void sendRoomInfo(Channel channel) {
    final room = getChannelRoom(channel);
    final player = room?.getChannel(channel);
    if (room == null || player == null) {
      sendMessage(
        RpcNetworkerPacket.named(name: SwampEvent.welcome, data: Uint8List(0)),
        channel,
      );
      return;
    }
    final info = RoomInfo(
      currentId: player,
      flags: room.roomFlags.value,
      maxPlayers: 0,
      roomId: room.roomId,
    );
    sendMessage(
      RpcNetworkerPacket.named(name: SwampEvent.roomInfo, data: info.toBytes()),
      channel,
    );
  }

  bool leaveRoom(Channel channel, {Channel? currentId, Uint8List? roomId}) {
    if (roomId != null && _joined[channel]?.roomId != roomId) return false;
    final room = _joined.remove(channel);
    if (room == null) return false;
    if (currentId != null && room.owner != currentId) return false;
    final roomChannel = room.getChannel(channel);
    if (roomChannel == null) return false;
    room._playerChannels.remove(channel);
    _sendPacketToRoom(
      room,
      RpcNetworkerPacket.named(
        name: SwampEvent.playerLeft,
        data: Uint8List.fromList([roomChannel >> 8, roomChannel & 0xFF]),
      ),
    );
    if (room.isEmpty) {
      _rooms.remove(room);
      return true;
    }
    if (roomChannel == kAuthorityChannel) {
      for (final player in room.players) {
        _sendKickMessage(player, KickReason.hostLeft);
      }
      room.players.clear();
    }
    return true;
  }

  void _sendPacketToRoom(
    SwampRoom room,
    RpcNetworkerPacket packet, [
    Channel receiver = kAnyChannel,
  ]) {
    final receivers = <Channel>[];
    if (receiver == kAnyChannel) {
      receivers.addAll(room._playerChannels.keys);
    } else {
      final channel = room.getPlayer(receiver);
      if (channel == null) return;
      receivers.add(channel);
    }
    for (final receiver in receivers) {
      sendMessage(packet, receiver);
    }
  }

  void sendMessageToRoom(Channel sender, Channel receiver, Uint8List data) {
    final room = getChannelRoom(sender);
    if (room == null) return;
    final senderChannel = room.getChannel(sender);
    if (senderChannel == null) return;
    final builder = BytesBuilder();
    builder.addByte(senderChannel >> 8);
    builder.addByte(senderChannel & 0xFF);
    builder.add(data);
    final bytes = builder.toBytes();
    final packet = RpcNetworkerPacket.named(
      name: SwampEvent.message,
      data: bytes,
    );
    _sendPacketToRoom(room, packet, receiver);
  }

  void setApplication(Channel channel, Uint8List? data) {
    if (data?.isEmpty ?? false) data = null;
    if (data == null) {
      _application.remove(channel);
    } else {
      _application[channel] = data;
    }
  }

  Iterable<SwampRoom> get rooms => _rooms;
}
