library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:networker/networker.dart';

/// The current Swamp protocol version.
///
/// Increment this when making breaking changes to the wire protocol.
const kSwampProtocolVersion = 1;

/// All protocol versions the library understands.
///
/// The server advertises these via `/info` and accepts clients
/// that connect with any of these versions.
const kSwampSupportedProtocols = [kSwampProtocolVersion];

/// Prefix used to build WebSocket subprotocol identifiers.
///
/// A full subprotocol string looks like `swamp-1`.
const kSwampProtocolPrefix = 'swamp-';

/// Builds the WebSocket subprotocol string for a given [version].
///
/// Defaults to [kSwampProtocolVersion].
String swampSubprotocol([int version = kSwampProtocolVersion]) =>
    '$kSwampProtocolPrefix$version';

/// Parses a WebSocket subprotocol string (e.g. `swamp-1`) and returns
/// the protocol version number, or `null` if the format is invalid.
int? parseSwampSubprotocol(String subprotocol) {
  if (!subprotocol.startsWith(kSwampProtocolPrefix)) return null;
  return int.tryParse(subprotocol.substring(kSwampProtocolPrefix.length));
}

/// Encodes a room code (byte array) into a string representation.
///
/// This uses Base64 encoding.
String encodeRoomCode(Uint8List data) {
  return base64Encode(data);
}

/// Decodes a room code string into its byte array representation.
///
/// This uses Base64 decoding.
Uint8List decodeRoomCode(String code) {
  return base64Decode(code);
}

/// Events sent from the server to the client.
enum SwampEvent with RpcFunctionName {
  /// A general message.
  message,

  /// Information about a room.
  roomInfo,

  /// Welcome message upon connection.
  welcome,

  /// Notification that the client has been kicked.
  kicked,

  /// Notification that joining a room failed.
  roomJoinFailed,

  /// Notification that creating a room failed.
  roomCreationFailed,

  /// Notification that a player joined the room.
  playerJoined,

  /// Notification that a player left the room.
  playerLeft,

  /// List of players in the room.
  playerList,
}

/// Commands sent from the client to the server.
enum SwampCommand with RpcFunctionName {
  /// A general message.
  message,

  /// Request to join a room.
  joinRoom,

  /// Request to leave the current room.
  leaveRoom,

  /// Request to create a new room.
  createRoom,

  /// Request to kick a player.
  kickPlayer,

  /// Request for the list of players.
  playerList,

  /// Set the application identifier for the client.
  setApplication;

  @override
  RpcNetworkerMode get mode => RpcNetworkerMode.any;
}

/// Flags configuring the behavior of a room.
extension type const RoomFlags._(int value) {
  /// Flag indicating if the room is "dark" (e.g., specific visibility rules).
  static const darkRoomFlag = 0x01;

  /// Flag indicating if player visibility is enabled.
  static const playerVisibilityFlag = 0x02;

  /// Flag indicating if the host should switch when the current host leaves.
  static const switchHostOnLeaveFlag = 0x04;

  const RoomFlags([int value = 0]) : this._(value);

  /// Builds a [RoomFlags] instance with specified options.
  RoomFlags.build({
    bool darkRoom = false,
    bool playerVisibility = false,
    bool switchHostOnLeave = false,
  }) : this._(
         (darkRoom ? darkRoomFlag : 0) |
             (playerVisibility ? playerVisibilityFlag : 0) |
             (switchHostOnLeave ? switchHostOnLeaveFlag : 0),
       );

  /// Whether the room is a dark room.
  bool get isDarkRoom => value & darkRoomFlag != 0;

  /// Whether player visibility features are enabled.
  bool get isPlayerVisibility => value & playerVisibilityFlag != 0;

  /// Whether the host role switches when the host leaves.
  bool get isSwitchHostOnLeave => value & switchHostOnLeaveFlag != 0;

  /// Returns a new [RoomFlags] with updated values.
  RoomFlags withValues({
    bool? darkRoom,
    bool? playerVisibility,
    bool? switchHostOnLeave,
  }) => RoomFlags.build(
    darkRoom: darkRoom ?? isDarkRoom,
    playerVisibility: playerVisibility ?? isPlayerVisibility,
    switchHostOnLeave: switchHostOnLeave ?? isSwitchHostOnLeave,
  );
}

/// Information about a room, including its configuration and state.
final class RoomInfo {
  /// The flags configuration for the room.
  final int flags;

  /// The maximum number of players allowed in the room.
  final int maxPlayers;

  /// The current player ID (or similar identifier within the room context).
  final int currentId;

  /// The unique identifier of the room (byte array).
  final Uint8List roomId;

  RoomInfo({
    required this.flags,
    required this.maxPlayers,
    required this.currentId,
    required this.roomId,
  });

  /// Creates a [RoomInfo] instance from a byte array.
  factory RoomInfo.fromBytes(Uint8List data) {
    return RoomInfo(
      flags: data[0],
      maxPlayers: data[1] << 8 | data[2],
      currentId: data[3] << 8 | data[4],
      roomId: data.sublist(5),
    );
  }

  /// Serializes this [RoomInfo] to a byte array.
  Uint8List toBytes() {
    final bytes = Uint8List(5 + roomId.length);
    bytes[0] = flags;
    bytes[1] = maxPlayers >> 8;
    bytes[2] = maxPlayers & 0xFF;
    bytes[3] = currentId >> 8;
    bytes[4] = currentId & 0xFF;
    bytes.setAll(5, roomId);
    return bytes;
  }
}

enum KickReason {
  roomClosed,
  kicked,
  banned,
  hostLeft,
  unknown;

  int get value => this == unknown ? 0xFF : index;

  static KickReason fromValue(int value) =>
      KickReason.values.elementAtOrNull(value) ?? unknown;
}

enum JoinFailedReason {
  roomNotFound,
  roomFull,
  banned,
  applicationMismatch,
  unknown;

  int get value => this == unknown ? 0xFF : index;

  static JoinFailedReason fromValue(int value) =>
      JoinFailedReason.values.elementAtOrNull(value) ?? unknown;
}

enum CreationFailedReason {
  limitReached,
  inRoom,
  unknown,
  unsupportedFlags;

  int get value => this == unknown ? 0xFF : index;

  static CreationFailedReason fromValue(int value) =>
      CreationFailedReason.values.elementAtOrNull(value) ?? unknown;
}
