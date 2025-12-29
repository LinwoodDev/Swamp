import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:networker/networker.dart';
import 'package:swamp/src/config.dart';
import 'package:swamp_api/models.dart';

final class SwampRoom {
  final Uint8List roomId;
  final RoomFlags roomFlags;
  final Channel maxPlayers;
  final Uint8List? application;
  // Key is the player, value is the channel.
  final Map<Channel, Channel> _playerChannels = {};

  SwampRoom._(
    this.roomId, {
    this.roomFlags = const RoomFlags(),
    this.application,
    required this.maxPlayers,
  });

  SwampRoom.mock(Uint8List roomId)
    : this._(roomId, maxPlayers: 0, application: null);

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
    if (keys.length >= maxPlayers) {
      return kAnyChannel;
    }
    for (var i = 2; i < (1 << 16); i++) {
      if (!keys.contains(i)) {
        return i;
      }
    }
    return kAnyChannel;
  }
}

const kRoomIdLength = 8;
final random = Random.secure();

Uint8List generateRandomRoomId() {
  return Uint8List.fromList(
    List.generate(kRoomIdLength, (_) => random.nextInt(256)),
  );
}

final class SwampRoomManager extends SimpleNetworkerPipe<RpcNetworkerPacket> {
  final ConfigManager configManager;
  final Set<SwampRoom> _rooms = {};
  final Map<Channel, SwampRoom> _joined = {};
  final Map<Channel, Uint8List> _application = {};

  SwampConfig get config => configManager.config;

  SwampRoomManager(this.configManager);

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
      _sendJoinFailed(player, JoinFailedReason.applicationMismatch);
      return null;
    }
    if (room.maxPlayers != 0 && room.players.length >= room.maxPlayers) {
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

  SwampRoom? addRoom(
    Channel owner, {
    Channel? maxPlayers,
    RoomFlags roomFlags = const RoomFlags(),
  }) {
    var room = getChannelRoom(owner);
    if (room != null) {
      _sendCreationFailed(owner, CreationFailedReason.inRoom);
      return null;
    }
    var roomId = generateRandomRoomId();
    while (_rooms.contains(SwampRoom.mock(roomId))) {
      roomId = generateRandomRoomId();
    }
    if (roomFlags.isDarkRoom && config.noDarkRooms) {
      _sendCreationFailed(owner, CreationFailedReason.unknown);
      return null;
    }
    if (maxPlayers == null || maxPlayers > config.maxPlayers) {
      maxPlayers = config.maxPlayers;
    }
    room = SwampRoom._(
      roomId,
      roomFlags: roomFlags,
      application: _application[owner],
      maxPlayers: maxPlayers,
    );
    _rooms.add(room);
    _joined[owner] = room;
    room._playerChannels[owner] = kAuthorityChannel;
    sendRoomInfo(owner);
    return room;
  }

  FutureOr<void> removeRoom(Uint8List roomId) =>
      _rooms.remove(SwampRoom.mock(roomId));

  SwampRoom? getRoom(Uint8List roomId) => _rooms.lookup(SwampRoom.mock(roomId));

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
    sendRoomInfo(channel);
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

  void _sendCreationFailed(Channel channel, CreationFailedReason reason) {
    final builder = BytesBuilder();
    builder.addByte(reason.value);
    sendMessage(
      RpcNetworkerPacket.named(
        name: SwampEvent.roomCreationFailed,
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
      maxPlayers: room.maxPlayers,
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
      final players = room._playerChannels.keys.toList();
      for (final player in players) {
        _joined.remove(player);
        _sendKickMessage(player, KickReason.hostLeft);
      }
      room._playerChannels.clear();
      _rooms.remove(room);
    }
    return true;
  }

  void _sendPacketToRoom(
    SwampRoom room,
    RpcNetworkerPacket packet, [
    Channel receiver = kAnyChannel,
    Channel sender = kAnyChannel,
  ]) {
    List<Channel> receivers;
    if (receiver == kAnyChannel) {
      receivers = room._playerChannels.keys.where((c) => c != sender).toList();
    } else {
      final channel = room.getPlayer(receiver);
      if (channel == null) return;
      receivers = [channel];
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
    _sendPacketToRoom(room, packet, receiver, sender);
  }

  void setApplication(Channel channel, Uint8List? data) {
    final Uint8List? newData = (data?.isEmpty ?? false) ? null : data;
    if (newData == null) {
      _application.remove(channel);
    } else {
      _application[channel] = newData;
    }
  }

  Iterable<SwampRoom> get rooms => _rooms;
}
