import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:networker/networker.dart';
import 'package:swamp/src/config.dart';
import 'package:swamp_api/models.dart';

/// Represents a room/lobby in the Swamp server.
final class SwampRoom {
  /// The unique identifier for the room.
  final Uint8List roomId;

  /// Flags configuring the room's behavior.
  final RoomFlags roomFlags;

  /// The maximum number of players allowed in the room.
  final Channel maxPlayers;

  /// The application identifier associated with the room.
  final Uint8List? application;
  // Key is the player, value is the channel.
  final Map<Channel, Channel> _playerChannels = {};
  // Key is the channel, value is the player.
  final Map<Channel, Channel> _channelToPlayer = {};

  SwampRoom._(
    this.roomId, {
    this.roomFlags = const RoomFlags(),
    this.application,
    required this.maxPlayers,
  });

  /// Creates a mock [SwampRoom] for testing or placeholder purposes.
  SwampRoom.mock(Uint8List roomId)
    : this._(roomId, maxPlayers: 0, application: null);

  @override
  String toString() => encodeRoomCode(roomId);

  @override
  int get hashCode => toString().hashCode;

  /// Checks if the room has no players.
  bool get isEmpty => _playerChannels.isEmpty;

  @override
  bool operator ==(Object other) {
    if (other is SwampRoom) {
      return encodeRoomCode(roomId) == encodeRoomCode(other.roomId);
    }
    return false;
  }

  /// Gets the channel ID for a player ID if present in the room.
  Channel? getChannel(Channel player) => _playerChannels[player];

  /// The set of player IDs currently in the room.
  Set<Channel> get players => _playerChannels.keys.toSet();

  /// The set of channel IDs currently in the room.
  Set<Channel> get channels => _channelToPlayer.keys.toSet();

  /// The player ID of the room's owner (host).
  Channel get owner => getPlayer(kAuthorityChannel) ?? kAnyChannel;

  /// Gets the player ID associated with a channel ID.
  Channel? getPlayer(Channel channel) => _channelToPlayer[channel];

  Channel _findAvailableChannel() {
    if (_playerChannels.length >= maxPlayers) {
      return kAnyChannel;
    }
    for (var i = 2; i < (1 << 16); i++) {
      if (!_channelToPlayer.containsKey(i)) {
        return i;
      }
    }
    return kAnyChannel;
  }

  void _addPlayer(Channel player, Channel channel) {
    _playerChannels[player] = channel;
    _channelToPlayer[channel] = player;
  }

  void _removePlayer(Channel player) {
    final channel = _playerChannels.remove(player);
    if (channel != null) {
      _channelToPlayer.remove(channel);
    }
  }

  void _clear() {
    _playerChannels.clear();
    _channelToPlayer.clear();
  }
}

/// The length of a room ID in bytes.
const kRoomIdLength = 8;
final random = Random.secure();

/// Generates a cryptographically secure random room ID.
Uint8List generateRandomRoomId() {
  return Uint8List.fromList(
    List.generate(kRoomIdLength, (_) => random.nextInt(256)),
  );
}

/// Manages the lifecycle and operations of rooms on the server.
final class SwampRoomManager extends SimpleNetworkerPipe<RpcNetworkerPacket> {
  /// The server configuration manager.
  final ConfigManager configManager;
  final Set<SwampRoom> _rooms = {};
  final Map<Channel, SwampRoom> _joined = {};
  final Map<Channel, Uint8List> _application = {};
  int _playerCount = 0;
  static const _listEquality = ListEquality<int>();

  /// The total number of players across all rooms.
  int get playerCount => _playerCount;

  /// The current server configuration.
  SwampConfig get config => configManager.config;

  SwampRoomManager(this.configManager);

  /// Attempts to add a player to a room.
  ///
  /// Returns the [SwampRoom] if successful, or `null` if the room wasn't found,
  /// is full, or the application ID doesn't match.
  SwampRoom? joinRoom(Uint8List roomId, Channel player) {
    final room = getRoom(roomId);
    if (room == null) {
      _sendJoinFailed(player, JoinFailedReason.roomNotFound);
      return null;
    }
    final application = _application[player];
    if (application != null &&
        room.application != null &&
        !_listEquality.equals(room.application!, application)) {
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
    room._addPlayer(player, id);
    _playerCount++;
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
      _sendCreationFailed(owner, CreationFailedReason.unsupportedFlags);
      return null;
    }
    if (maxPlayers == null ||
        maxPlayers == 0 ||
        maxPlayers > config.maxPlayers) {
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
    room._addPlayer(owner, kAuthorityChannel);
    _playerCount++;
    sendRoomInfo(owner);
    return room;
  }

  void removeRoom(Uint8List roomId) {
    final room = getRoom(roomId);
    if (room == null) return;
    for (final player in room.players) {
      _joined.remove(player);
    }
    _playerCount -= room.players.length;
    room._clear();
    _rooms.remove(room);
  }

  SwampRoom? getRoom(Uint8List roomId) => _rooms.lookup(SwampRoom.mock(roomId));

  SwampRoom? getChannelRoom(Channel channel) => _joined[channel];

  void _sendKickMessage(
    Channel channel,
    KickReason reason, [
    String message = '',
  ]) {
    final builder = BytesBuilder();
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
    if (roomId != null &&
        !_listEquality.equals(_joined[channel]?.roomId, roomId)) {
      return false;
    }
    final room = _joined[channel];
    if (room == null) return false;
    if (currentId != null && room.owner != currentId) return false;
    final roomChannel = room.getChannel(channel);
    if (roomChannel == null) return false;
    _joined.remove(channel);
    room._removePlayer(channel);
    _playerCount--;
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
      final players = room.players.toList();
      _playerCount -= players.length;
      for (final player in players) {
        _joined.remove(player);
        _sendKickMessage(player, KickReason.hostLeft);
      }
      room._clear();
      _rooms.remove(room);
    }
    return true;
  }

  bool kickPlayer(
    Channel requester,
    Channel targetPlayer, {
    String message = '',
  }) {
    final room = getChannelRoom(requester);
    if (room == null || room.getChannel(requester) != kAuthorityChannel) {
      return false;
    }
    if (targetPlayer == kAuthorityChannel) return false;
    final targetChannel = room.getPlayer(targetPlayer);
    if (targetChannel == null) return false;

    _joined.remove(targetChannel);
    room._removePlayer(targetChannel);
    _playerCount--;
    _sendKickMessage(targetChannel, KickReason.kicked, message);
    _sendPacketToRoom(
      room,
      RpcNetworkerPacket.named(
        name: SwampEvent.playerLeft,
        data: Uint8List.fromList([targetPlayer >> 8, targetPlayer & 0xFF]),
      ),
    );
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
      receivers = room.players.where((c) => c != sender).toList();
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
