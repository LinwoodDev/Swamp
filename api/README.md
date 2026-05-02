# Swamp API

> Swamp Connection Client to the Swamp Server

## Installation

You have two options to install the Swamp API by using the git dependency for this repository:

* Getting the latest commit hash as ref from the `api` directory
* Getting a specific tag from the `api` directory (e.g. `v1.0.0`)

## Usage

Create a room:

```dart
final connection = SwampConnection(server: Uri.parse('ws://localhost:8080'));

connection.onRoomInfo.listen((info) {
  print('Room code: ${encodeRoomCode(info.roomId)}');
});

await connection.init();
```

Join a room:

```dart
final connection = SwampConnection(
  server: Uri.parse('ws://localhost:8080'),
  roomId: decodeRoomCode('<room-code>'),
);

connection.messagePipe.read.listen((packet) {
  print(packet.data);
});

await connection.init();
```

Use `SwampConnection.build(Uri.parse('swamp+wss://host/#<room-code>'))`
to parse Swamp links. Use `SwampConnection.buildSecure` for links that
include an end-to-end encryption key in the fragment.

## Notes

Read more in the main [README](../README.md) file.
