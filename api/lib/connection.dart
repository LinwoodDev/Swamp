library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:networker/networker.dart';
import 'package:networker_crypto/e2ee.dart';
import 'package:rxdart/rxdart.dart';
import 'models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

export 'models.dart';

part 'src/info.dart';

const kDefaultSwampSplit = ':';
const kSwampSchemePrefix = 'swamp+';

class RawSwampConnection extends NetworkerPipe<Uint8List, RpcNetworkerPacket>
    with
        NetworkerBase<RpcNetworkerPacket>,
        RpcNetworkerPipeMixin,
        NetworkerServerMixin<SwampClientConnectionInfo, RpcNetworkerPacket>,
        NetworkerClientMixin<RpcNetworkerPacket>,
        NamedRpcNetworkerPipe<SwampEvent, SwampCommand> {
  static final List<String> supportedSchemes = List.unmodifiable(const [
    '${kSwampSchemePrefix}ws',
    '${kSwampSchemePrefix}wss',
  ]);
  final StreamController<void> _onOpen = StreamController<void>.broadcast(),
      _onClosed = StreamController<void>.broadcast();
  final Uri server;

  @override
  RpcConfig get config => RpcConfig(channelField: false);

  @override
  Uri get address => server;

  @override
  Channel? get receiverChannel => null;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Future<void>? _initFuture;
  Future<void>? _rawCloseFuture;
  bool _disposed = false;
  bool _closedNotified = false;

  /// The protocol version this client will use when connecting.
  final int protocolVersion;

  @override
  bool get isServer => false;

  RawSwampConnection({
    required this.server,
    this.protocolVersion = kSwampProtocolVersion,
  });

  @override
  Future<void> close() {
    final pending = _rawCloseFuture;
    if (pending != null) return pending;
    _disposed = true;
    final parentClose = super.close();
    return _rawCloseFuture = _closeRaw(parentClose);
  }

  Future<void> _closeRaw(Future<void> parentClose) async {
    final channel = _channel;
    _channel = null;
    try {
      await channel?.sink.close();
      await _channelSubscription?.cancel();
      _channelSubscription = null;
      await parentClose;
    } finally {
      _notifyClosed();
      await _onOpen.close();
      await _onClosed.close();
      dispose();
    }
  }

  @override
  Future<void> init() {
    if (_disposed) {
      return Future.error(StateError('Connection is closed'));
    }
    if (isOpen) return Future.value();
    return _initFuture ??= _init().whenComplete(() => _initFuture = null);
  }

  Future<void> _init() async {
    await _channelSubscription?.cancel();
    _closedNotified = false;
    var address = this.address;
    final scheme = address.scheme;
    if (scheme.startsWith(kSwampSchemePrefix)) {
      address = address.replace(
        scheme: scheme.substring(kSwampSchemePrefix.length),
      );
    }
    if (!address.hasScheme) {
      address = address.replace(scheme: 'wss');
    }
    final channel = _channel = WebSocketChannel.connect(
      address,
      protocols: [swampSubprotocol(protocolVersion)],
    );
    _channelSubscription = channel.stream.listen(
      (event) {
        if (event is String) {
          event = Uint8List.fromList(event.codeUnits);
        }
        onMessage(event);
      },
      onDone: () {
        _channel = null;
        _notifyClosed();
      },
      onError: (error) {
        _channel = null;
        _notifyClosed(error);
      },
    );
    try {
      await channel.ready;
      _onOpen.add(null);
    } catch (_) {
      _channel = null;
      await channel.sink.close();
      rethrow;
    }
  }

  void _notifyClosed([Object? error]) {
    if (_closedNotified || _onClosed.isClosed) return;
    _closedNotified = true;
    if (error == null) {
      _onClosed.add(null);
    } else {
      _onClosed.addError(error);
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

  @override
  void sendPacket(Uint8List data, Channel channel) => _channel?.sink.add(data);
}

class SwampConnection extends RawSwampConnection {
  final StreamController<void> _onWelcome = StreamController<void>.broadcast();
  final BehaviorSubject<RoomInfo> _onRoomInfo = BehaviorSubject();
  final String Function(Uint8List) roomCodeEncoder;
  final Uint8List Function(String) roomCodeDecoder;
  final Uint8List? roomId;
  final E2EENetworkerPipe? e2eePipe;
  final RawNetworkerPipe messagePipe;
  final String split;
  final RoomFlags flags;
  KickReason? _kickReason;
  Uint8List? _kickMessage;
  Future<void>? _swampCloseFuture;

  KickReason? get kickReason => _kickReason;
  Uint8List? get kickMessage => _kickMessage;

  @override
  bool get isServer => roomInfo?.currentId == kAuthorityChannel;

  @override
  Uri get address {
    final id = roomInfo?.roomId ?? roomId;
    return server.replace(fragment: id == null ? null : roomCodeEncoder(id));
  }

  Future<Uri> getSecureAddress() async {
    if (e2eePipe == null) return address;
    final id = roomInfo?.roomId ?? roomId;
    if (id == null) return server;
    final key = await e2eePipe!.secretKey.extractBytes();
    return server.replace(
      fragment:
          '${encodeRoomCode(id)}$split${encodeRoomCode(Uint8List.fromList(key))}',
      scheme: '$kSwampSchemePrefix${server.scheme}',
    );
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

  Stream<void> get onWelcome => _onWelcome.stream;

  SwampConnection({
    required super.server,
    super.protocolVersion,
    this.roomId,
    this.roomCodeEncoder = encodeRoomCode,
    this.roomCodeDecoder = decodeRoomCode,
    this.e2eePipe,
    this.split = kDefaultSwampSplit,
    this.flags = const RoomFlags(),
  }) : messagePipe = SimpleNetworkerPipe() {
    final channelPipe = InternalChannelPipe(bytes: 2, channel: kAnyChannel);
    if (e2eePipe != null) {
      registerNamedFunction(
        SwampEvent.message,
      ).connect(channelPipe..connect(e2eePipe!..connect(messagePipe)));
    } else {
      registerNamedFunction(
        SwampEvent.message,
      ).connect(channelPipe..connect(messagePipe));
    }
    _initFunctions();
  }

  factory SwampConnection.build(
    Uri address, {
    String split = kDefaultSwampSplit,
    String Function(Uint8List)? roomCodeEncoder,
    Uint8List Function(String)? roomCodeDecoder,
    RoomFlags flags = const RoomFlags(),
    int protocolVersion = kSwampProtocolVersion,
  }) {
    roomCodeDecoder ??= decodeRoomCode;
    final roomId = address.hasFragment
        ? roomCodeDecoder(address.fragment)
        : null;
    return SwampConnection(
      server: address.replace(fragment: ''),
      roomId: roomId,
      roomCodeEncoder: roomCodeEncoder ?? encodeRoomCode,
      roomCodeDecoder: roomCodeDecoder,
      split: split,
      flags: flags,
      protocolVersion: protocolVersion,
    );
  }

  @override
  Future<void> close() {
    final pending = _swampCloseFuture;
    if (pending != null) return pending;
    final parentClose = super.close();
    return _swampCloseFuture = _closeSwamp(parentClose);
  }

  Future<void> _closeSwamp(Future<void> parentClose) async {
    try {
      await parentClose;
    } finally {
      await _onWelcome.close();
      await _onRoomInfo.close();
    }
  }

  static Future<SwampConnection> buildSecure(
    Uri address,
    Cipher cipher, {
    String Function(Uint8List) roomCodeEncoder = encodeRoomCode,
    Uint8List Function(String) roomCodeDecoder = decodeRoomCode,
    String split = kDefaultSwampSplit,
    RoomFlags flags = const RoomFlags(),
    int protocolVersion = kSwampProtocolVersion,
  }) async {
    var roomId = address.hasFragment ? address.fragment : null;
    SecretKey key;
    if (roomId != null) {
      var splitted = roomId.split(split);
      if (splitted.length != 2 || splitted.any((part) => part.isEmpty)) {
        throw FormatException(
          'Secure Swamp addresses must include a room id and key',
        );
      }
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
      roomCodeDecoder: roomCodeDecoder,
      e2eePipe: e2ee,
      flags: flags,
      split: split,
      protocolVersion: protocolVersion,
    );
    return connection;
  }

  @override
  Future<void> init() async {
    await super.init();
    _kickMessage = null;
    _kickReason = null;
    return _sendRequest();
  }

  Future<void> _sendRequest() {
    if (roomId == null) {
      final data = Uint8List.fromList([flags.value]);
      return sendMessage(
        RpcNetworkerPacket.named(name: SwampCommand.createRoom, data: data),
      );
    } else {
      return sendMessage(
        RpcNetworkerPacket.named(name: SwampCommand.joinRoom, data: roomId!),
      );
    }
  }

  void _initFunctions() {
    registerNamedFunction(SwampEvent.roomInfo).read.listen((packet) {
      _onRoomInfo.add(RoomInfo.fromBytes(packet.data));
    });
    registerNamedFunction(SwampEvent.welcome).read.listen((packet) {
      _onWelcome.add(null);
    });
    registerNamedFunction(SwampEvent.kicked).read.listen((packet) {
      try {
        final data = packet.data;
        _kickReason = KickReason.fromValue(data[0]);
        if (data.length > 1) {
          _kickMessage = data.sublist(1);
        } else {
          _kickMessage = null;
        }
      } catch (e) {
        _kickReason = null;
        _kickMessage = null;
      }
      close();
    });
    registerNamedFunction(
      SwampEvent.roomJoinFailed,
    ).read.listen((packet) => close());
    registerNamedFunction(
      SwampEvent.roomCreationFailed,
    ).read.listen((packet) => close());
    registerNamedFunction(SwampEvent.playerJoined).read.listen((packet) {
      final data = packet.data;
      if (data.length < 2) return;
      final playerId = data[0] << 8 | data[1];
      addClientConnection(SwampClientConnectionInfo(this, playerId), playerId);
    });
    registerNamedFunction(SwampEvent.playerLeft).read.listen((packet) {
      final data = packet.data;
      if (data.length < 2) return;
      final playerId = data[0] << 8 | data[1];
      removeConnection(playerId).ignore();
    });
    registerNamedFunction(SwampEvent.playerList).read.listen((packet) {
      final data = packet.data;
      if (data.length < 2) return;
      final count = data[0] << 8 | data[1];
      final expectedLength = 2 + count * 2;
      if (data.length < expectedLength) return;
      final playerIds = <Channel>{};
      for (var i = 2; i < expectedLength; i += 2) {
        playerIds.add(data[i] << 8 | data[i + 1]);
      }
      for (final id in playerIds) {
        if (clientConnections.contains(id)) continue;
        addClientConnection(SwampClientConnectionInfo(this, id), id);
      }
      for (final id in clientConnections) {
        if (playerIds.contains(id)) continue;
        removeConnection(id).ignore();
      }
    });
  }
}
