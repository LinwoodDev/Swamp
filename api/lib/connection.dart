library;

import 'dart:async';
import 'dart:typed_data';

import 'package:networker/networker.dart';
import 'package:networker_crypto/networker_crypto.dart';
import 'package:rxdart/rxdart.dart';
import 'package:swamp_api/models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

part 'info.dart';

class SwampConnection extends NetworkerPipe<Uint8List, RpcNetworkerPacket>
    with
        NetworkerBase<RpcNetworkerPacket>,
        RpcNetworkerPipeMixin,
        NetworkerServerMixin<SwampClientConnectionInfo, RpcNetworkerPacket>,
        NamedRpcNetworkerPipe<SwampEvent, SwampCommand> {
  final StreamController<void> _onOpen = StreamController<void>.broadcast(),
      _onClosed = StreamController<void>.broadcast();
  final BehaviorSubject<RoomInfo> _onRoomInfo = BehaviorSubject();
  final String Function(Uint8List) roomCodeEncoder;
  final Uri server;
  final Uint8List? roomId;
  final E2EENetworkerPipe? e2eePipe;
  final RawNetworkerPipe messagePipe;

  WebSocketChannel? _channel;

  @override
  bool get isServer => false;
  @override
  Channel? get receiverChannel => null;
  @override
  RpcConfig get config => RpcConfig(channelField: false);

  @override
  Uri get address {
    final id = roomInfo?.roomId ?? roomId;
    return server.replace(fragment: id == null ? null : roomCodeEncoder(id));
  }

  Stream<KickReason> get onKicked => registerNamedFunction(
    SwampEvent.kicked,
  ).read.map((packet) => KickReason.fromValue(packet.data[0]));

  Stream<JoinFailedReason> get onJoinFailed => registerNamedFunction(
    SwampEvent.roomJoinFailed,
  ).read.map((packet) => JoinFailedReason.fromValue(packet.data[0]));

  Stream<CreationFailedReason> get onCreationFailed => registerNamedFunction(
    SwampEvent.roomCreationFailed,
  ).read.map((packet) => CreationFailedReason.fromValue(packet.data[0]));

  Stream<RoomInfo> get onRoomInfo => _onRoomInfo.stream;

  RoomInfo? get roomInfo => _onRoomInfo.valueOrNull;

  SwampConnection({
    required this.server,
    this.roomId,
    this.roomCodeEncoder = encodeRoomCode,
    this.e2eePipe,
  }) : messagePipe = InternalChannelPipe(bytes: 2, channel: kAnyChannel) {
    if (e2eePipe != null) {
      registerNamedFunction(SwampEvent.message).connect(e2eePipe!);
    }
    (e2eePipe ?? registerNamedFunction(SwampEvent.message)).connect(
      messagePipe,
    );
    _initFunctions();
  }

  factory SwampConnection.build(
    Uri address, {
    String Function(Uint8List)? roomCodeDecoder,
    Uint8List Function(String) parseRoomCode = decodeRoomCode,
  }) {
    final roomId = address.hasFragment ? parseRoomCode(address.fragment) : null;
    return SwampConnection(
      server: address.replace(fragment: ''),
      roomId: roomId,
      roomCodeEncoder: roomCodeDecoder ?? encodeRoomCode,
    );
  }
  static Future<SwampConnection> buildSecure(
    Uri address,
    Cipher cipher, {
    String Function(Uint8List) roomCodeEncoder = encodeRoomCode,
    Uint8List Function(String) roomCodeDecoder = decodeRoomCode,
    String split = ':',
  }) async {
    var roomId = address.hasFragment ? address.fragment : null;
    SecretKey key;
    if (roomId != null) {
      var splitted = roomId.split(split);
      roomId = splitted[0];
      key = await cipher.newSecretKeyFromBytes(roomCodeDecoder(splitted[1]));
    } else {
      key = await cipher.newSecretKey();
    }
    final e2ee = E2EENetworkerPipe(cipher: cipher, secretKey: key);
    final connection = SwampConnection(
      server: address.replace(fragment: ''),
      roomId: roomId == null ? null : roomCodeDecoder(roomId),
      roomCodeEncoder: roomCodeEncoder,
      e2eePipe: e2ee,
    );
    return connection;
  }

  @override
  FutureOr<void> close() {
    super.close();
    _channel?.sink.close();
    _channel = null;
  }

  @override
  Future<void> init() async {
    if (isOpen) {
      return;
    }
    final channel =
        _channel = WebSocketChannel.connect(address, protocols: ['swamp-0']);
    channel.stream.listen(
      (event) {
        if (event is String) {
          event = Uint8List.fromList(event.codeUnits);
        }
        onMessage(event);
      },
      onDone: () {
        _onClosed.add(null);
      },
      onError: (error) {
        _onClosed.addError(error);
      },
      cancelOnError: true,
    );
    await channel.ready;
    _onOpen.add(null);
    return _sendRequest();
  }

  Future<void> _sendRequest() {
    if (roomId == null) {
      return sendMessage(
        RpcNetworkerPacket.named(
          name: SwampCommand.createRoom,
          data: Uint8List(0),
        ),
      );
    } else {
      return sendMessage(
        RpcNetworkerPacket.named(name: SwampCommand.joinRoom, data: roomId!),
      );
    }
  }

  @override
  Future<void> onMessage(
    Uint8List data, [
    Channel channel = kAnyChannel,
  ]) async {
    await super.onMessage(data, channel);
    runFunction(decode(data), channel: kAuthorityChannel);
  }

  @override
  bool get isClosed => _channel == null || _channel?.closeCode != null;

  @override
  Stream<void> get onClosed => _onClosed.stream;

  @override
  Stream<void> get onOpen => _onOpen.stream;

  void _initFunctions() {
    registerNamedFunction(SwampEvent.roomInfo).read.listen((packet) {
      print('room info');
      final data = packet.data;
      final flags = data[0];
      final maxPlayers = data[1] << 8 | data[2];
      final currentId = data[3] << 8 | data[4];
      final roomId = data.sublist(5);
      _onRoomInfo.add(
        RoomInfo(
          flags: flags,
          maxPlayers: maxPlayers,
          currentId: currentId,
          roomId: roomId,
        ),
      );
    });
    registerNamedFunction(SwampEvent.welcome).read.listen((packet) {
      final data = packet.data;
      final flags = data[0];
      final maxPlayers = data[1] << 8 | data[2];
      final currentId = data[3] << 8 | data[4];
      final roomId = data.sublist(5);
      _onRoomInfo.add(
        RoomInfo(
          flags: flags,
          maxPlayers: maxPlayers,
          currentId: currentId,
          roomId: roomId,
        ),
      );
    });
    registerNamedFunction(SwampEvent.kicked).read.listen((packet) => close());
    registerNamedFunction(
      SwampEvent.roomJoinFailed,
    ).read.listen((packet) => close());
    registerNamedFunction(
      SwampEvent.roomCreationFailed,
    ).read.listen((packet) => close());
    registerNamedFunction(SwampEvent.playerJoined).read.listen((packet) {
      final data = packet.data;
      final playerId = data[0] << 8 | data[1];
      addClientConnection(SwampClientConnectionInfo(this, playerId), playerId);
    });
    registerNamedFunction(SwampEvent.playerLeft).read.listen((packet) {
      final data = packet.data;
      final playerId = data[0] << 8 | data[1];
      removeConnection(playerId);
    });
    registerNamedFunction(SwampEvent.playerList).read.listen((packet) {
      final data = packet.data;
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
    });
  }

  @override
  void sendPacket(Uint8List data, Channel channel) => _channel?.sink.add(data);
}
