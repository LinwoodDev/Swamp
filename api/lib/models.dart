import 'dart:convert';
import 'dart:typed_data';

import 'package:networker/networker.dart';

String encodeRoomCode(Uint8List data) {
  return base64Encode(data);
}

Uint8List decodeRoomCode(String code) {
  return base64Decode(code);
}

enum SwampEvent with RpcFunctionName {
  message,
  roomInfo,
  welcome,
  kicked,
  roomJoinFailed,
  roomCreationFailed,
  playerJoined,
  playerLeft,
  playerList,
}

enum SwampCommand with RpcFunctionName {
  message,
  joinRoom,
  leaveRoom,
  createRoom,
  kickPlayer,
  playerList,
  setApplication;

  @override
  RpcNetworkerMode get mode => RpcNetworkerMode.any;
}

extension type const RoomFlags._(int value) {
  static const darkRoomFlag = 0x01;
  static const playerVisibilityFlag = 0x02;
  static const switchHostOnLeaveFlag = 0x04;
  const RoomFlags([int value = 0]) : this._(value);
  RoomFlags.build({
    bool darkRoom = false,
    bool playerVisibility = false,
    bool switchHostOnLeave = false,
  }) : this._(
         (darkRoom ? darkRoomFlag : 0) |
             (playerVisibility ? playerVisibilityFlag : 0) |
             (switchHostOnLeave ? switchHostOnLeaveFlag : 0),
       );

  bool get isDarkRoom => value & darkRoomFlag != 0;
  bool get isPlayerVisibility => value & playerVisibilityFlag != 0;
  bool get isSwitchHostOnLeave => value & switchHostOnLeaveFlag != 0;

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

  factory RoomInfo.fromBytes(Uint8List data) {
    return RoomInfo(
      flags: data[0],
      maxPlayers: data[1] << 8 | data[2],
      currentId: data[3] << 8 | data[4],
      roomId: data.sublist(5),
    );
  }

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
  unknown;

  int get value => this == unknown ? 0xFF : index;

  static CreationFailedReason fromValue(int value) =>
      CreationFailedReason.values.elementAtOrNull(value) ?? unknown;
}
