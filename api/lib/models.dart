import 'dart:typed_data';

import 'package:networker/networker.dart';

String encodeRoomCode(Uint8List data) {
  return data.map((e) => e.toRadixString(16)).join();
}

Uint8List decodeRoomCode(String code) {
  return Uint8List.fromList(
    code.split('').map((e) => int.parse(e, radix: 16)).toList(),
  );
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
  setApplication,
}

extension type RoomFlag(int value) {
  static const darkRoomFlag = 0x01;
  static const playerVisibilityFlag = 0x02;

  bool get isDarkRoom => value & darkRoomFlag != 0;
  bool get isPlayerVisibility => value & playerVisibilityFlag != 0;
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
