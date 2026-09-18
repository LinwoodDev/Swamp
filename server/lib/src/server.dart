import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:consoler/consoler.dart';
import 'package:networker/networker.dart';
import 'package:networker_socket/server.dart';
import 'package:swamp/src/programs/config.dart';
import 'package:swamp/src/programs/info.dart';
import 'package:swamp/swamp.dart';

/// The main Swamp server class.
///
/// This class handles client connections, manages rooms, and processes RPC commands.
/// It extends [NetworkerSocketServer] to provide TCP/socket server functionality.
class SwampServer extends NetworkerSocketServer {
  /// The configuration manager for the server.
  final ConfigManager configManager;

  /// Optional authentication and authorization configuration.
  final SwampAuthentication? authentication;

  late final SwampAuthenticationManager? _authenticationManager =
      authentication == null
      ? null
      : SwampAuthenticationManager(authentication!);

  /// The room manager responsible for handling room logic.
  late final SwampRoomManager roomManager = SwampRoomManager(configManager);

  final NamedRpcClientNetworkerPipe<SwampCommand, SwampEvent> _rpcPipe =
      NamedRpcClientNetworkerPipe(config: RpcConfig(channelField: false));
  final Consoler _consoler = Consoler(
    defaultProgramConfig: DefaultProgramConfiguration(
      description: 'Swamp Server',
    ),
  );

  final RateLimiterPipe<Uint8List> _spamLimiter = RateLimiterPipe(
    maxRequests: 200,
    duration: Duration(seconds: 10),
  );
  Future<void>? _closeFuture;

  /// The current server configuration.
  SwampConfig get config => configManager.config;

  /// Creates a new [SwampServer].
  ///
  /// [serverAddress] and [port] define where the server listens.
  /// [configManager] can be provided to use a custom configuration manager.
  /// [withConsole] determines if the server should run an interactive console.
  /// [minLogLevel] sets the minimum log level for the console.
  /// [securityContext] allows configuring SSL/TLS.
  SwampServer(
    super.serverAddress,
    super.port, {
    ConfigManager? configManager,
    this.authentication,
    bool withConsole = true,
    LogLevel? minLogLevel,
    super.securityContext,
  }) : configManager = configManager ?? ConfigManager() {
    connect(_spamLimiter);
    _spamLimiter.connect(_rpcPipe..connect(roomManager));

    _initFunctions();
    _consoler.registerPrograms({
      'stop': StopProgram(this),
      'rooms': RoomsProgram(roomManager),
      'room': RoomProgram(roomManager),
      'config': ConfigProgram(this),
      'info': InfoProgram(this),
    });
    _consoler.minLogLevel = minLogLevel ?? _consoler.minLogLevel;
    if (withConsole) _consoler.run();
  }

  @override
  Future<void> handleRequest(HttpRequest request) async {
    // On /info, we show server info
    if (request.uri.path == '/info') {
      showPublicInfo(this, request);
      return;
    }
    // Validate the Swamp protocol version on WebSocket upgrade requests.
    final protocols = request.headers['Sec-WebSocket-Protocol'];
    if (protocols != null && protocols.isNotEmpty) {
      final requested = protocols
          .expand((h) => h.split(','))
          .map((p) => p.trim())
          .toList();
      final match = requested.firstWhereOrNull((p) {
        final v = parseSwampSubprotocol(p);
        return v != null && kSwampSupportedProtocols.contains(v);
      });
      if (match == null) {
        log(
          'Client requested unsupported protocol(s): $requested',
          LogLevel.warning,
        );
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'error': 'unsupported_protocol',
            'supported': kSwampSupportedProtocols
                .map((v) => swampSubprotocol(v))
                .toList(),
          }),
        );
        request.response.close();
        return;
      }
    }
    return super.handleRequest(request);
  }

  @override
  Future<void> handleWebSocketUpgrade(HttpRequest request) async {
    final authenticationRequest = AuthenticationRequest.fromHttpRequest(
      request,
    );

    // Select the best matching Swamp subprotocol during the WS handshake.
    request.response.statusCode = HttpStatus.switchingProtocols;
    final socket = await WebSocketTransformer.upgrade(
      request,
      protocolSelector: (requestedProtocols) {
        return requestedProtocols.firstWhereOrNull((p) {
          final v = parseSwampSubprotocol(p);
          return v != null && kSwampSupportedProtocols.contains(v);
        });
      },
    );
    final info = request.connectionInfo;
    final connectionInfo = NetworkerSocketInfo(
      Uri(host: info?.remoteAddress.address, port: info?.remotePort),
      socket,
    );
    final id = addClientConnection(connectionInfo);
    if (id == kAnyChannel) {
      socket.close();
      return;
    }
    _authenticationManager?.connected(
      id,
      authenticationRequest,
      onTimeout: () => closeConnection(id),
    );
    handleWebSocketConnection(id, connectionInfo, socket);
  }

  bool _isConnectionAuthorized(Channel channel) {
    return _authenticationManager?.isConnectionAuthorized(channel) ?? true;
  }

  void _rejectUnauthorizedCommand(Channel channel) {
    _sendAuthenticationFailed(channel);
    closeConnection(channel);
  }

  void _sendAuthenticationFailed(Channel channel) {
    _rpcPipe.sendNamedFunction(
      SwampEvent.authenticationFailed,
      Uint8List(0),
      channel: channel,
    );
  }

  Future<void> _authenticateConnection(Channel channel, Uint8List data) async {
    final manager = _authenticationManager;
    if (manager == null) {
      _rpcPipe.sendNamedFunction(
        SwampEvent.authenticated,
        Uint8List(0),
        channel: channel,
      );
      return;
    }

    AuthenticationAttemptResult result;
    try {
      final token = utf8.decode(data, allowMalformed: true);
      result = await manager.authenticate(channel, token);
    } catch (error) {
      log('Authentication source failed: $error', LogLevel.error);
      result = AuthenticationAttemptResult.rejected;
    }

    switch (result) {
      case AuthenticationAttemptResult.authenticated:
        _rpcPipe.sendNamedFunction(
          SwampEvent.authenticated,
          Uint8List(0),
          channel: channel,
        );
        if (manager.requiresAuthentication) {
          roomManager.sendRoomInfo(channel);
        }
        return;
      case AuthenticationAttemptResult.rejected:
        _sendAuthenticationFailed(channel);
        closeConnection(channel);
        return;
      case AuthenticationAttemptResult.inProgress:
        return;
    }
  }

  /// Logs a message to the console.
  void log(Object? message, [LogLevel? level]) =>
      _consoler.print(message, level: level);

  void _initFunctions() {
    clientConnect.listen((event) {
      log('Client connected: ${event.$1}', LogLevel.info);
      if (_isConnectionAuthorized(event.$1)) {
        roomManager.sendRoomInfo(event.$1);
      }
    });
    clientDisconnect.listen((event) {
      log('Client disconnected: ${event.$1}', LogLevel.info);
      _authenticationManager?.disconnected(event.$1);
      roomManager.leaveRoom(event.$1);
      roomManager.setApplication(event.$1, null);
    });
    _rpcPipe
      ..registerNamedFunction(SwampCommand.message).read.listen((event) {
        if (!_isConnectionAuthorized(event.channel)) {
          _rejectUnauthorizedCommand(event.channel);
          return;
        }
        if (event.data.length < 2) {
          log('Invalid message packet from ${event.channel}', LogLevel.warning);
          return;
        }
        final sender = event.channel;
        final receiver = ByteData.sublistView(event.data, 0, 2).getUint16(0);
        final message = event.data.sublist(2);
        roomManager.sendMessageToRoom(sender, receiver, message);
      })
      ..registerNamedFunction(SwampCommand.createRoom).read.listen((event) {
        if (!_isConnectionAuthorized(event.channel)) {
          _rejectUnauthorizedCommand(event.channel);
          return;
        }
        if (_authenticationManager?.canCreateRooms(event.channel) == false) {
          roomManager.sendCreationFailed(
            event.channel,
            CreationFailedReason.unauthorized,
          );
          return;
        }
        final flags = RoomFlags(event.data.elementAtOrNull(0) ?? 0);
        final maxPlayers = event.data.length >= 3
            ? ByteData.sublistView(event.data, 1, 3).getUint16(0)
            : null;
        final room = roomManager.addRoom(
          event.channel,
          roomFlags: flags,
          maxPlayers: maxPlayers,
        );
        if (room != null) {
          log('Room created: $room', LogLevel.info);
        }
      })
      ..registerNamedFunction(SwampCommand.joinRoom).read.listen((event) {
        if (!_isConnectionAuthorized(event.channel)) {
          _rejectUnauthorizedCommand(event.channel);
          return;
        }
        final room = roomManager.joinRoom(event.data, event.channel);
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
        if (!_isConnectionAuthorized(event.channel)) {
          _rejectUnauthorizedCommand(event.channel);
          return;
        }
        roomManager.leaveRoom(event.channel);
        log('Client ${event.channel} left room', LogLevel.info);
      })
      ..registerNamedFunction(SwampCommand.kickPlayer).read.listen((event) {
        if (!_isConnectionAuthorized(event.channel)) {
          _rejectUnauthorizedCommand(event.channel);
          return;
        }
        if (event.data.length < 2) {
          log('Invalid kick packet from ${event.channel}', LogLevel.warning);
          return;
        }
        final player = ByteData.sublistView(event.data, 0, 2).getUint16(0);
        final message = event.data.length > 2
            ? utf8.decode(event.data.sublist(2), allowMalformed: true)
            : '';
        final kicked = roomManager.kickPlayer(
          event.channel,
          player,
          message: message,
        );
        if (kicked) {
          log(
            'Client ${event.channel} kicked player $player from room',
            LogLevel.info,
          );
        } else {
          log(
            'Client ${event.channel} failed to kick player $player',
            LogLevel.warning,
          );
        }
      })
      ..registerNamedFunction(SwampCommand.playerList).read.listen((event) {
        if (!_isConnectionAuthorized(event.channel)) {
          _rejectUnauthorizedCommand(event.channel);
          return;
        }
        final players =
            roomManager.getChannelRoom(event.channel)?.channels ?? <Channel>[];
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
        if (!_isConnectionAuthorized(event.channel)) {
          _rejectUnauthorizedCommand(event.channel);
          return;
        }
        roomManager.setApplication(event.channel, event.data);
        log('Application set for ${event.channel}', LogLevel.verbose);
      })
      ..registerNamedFunction(SwampCommand.authenticate).read.listen((event) {
        _authenticateConnection(event.channel, event.data);
      });
  }

  @override
  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) return pending;
    _consoler.dispose();
    _spamLimiter.dispose();
    final parentClose = super.close();
    return _closeFuture = _closeServer(parentClose);
  }

  Future<void> _closeServer(Future<void> parentClose) async {
    try {
      await parentClose;
    } finally {
      await _authenticationManager?.close();
    }
  }
}
