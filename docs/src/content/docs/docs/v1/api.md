---
title: API Reference
---

The current api version is `v0` and paths are prefixed with `/api/v0`.

:::note

The current swamp release doesn't support room flags currently.
You can only use the default room configuration currently, so dark room events get sent to all players.

:::

## `GET /info`

Returns information about the server like the name but no sensitive information.

### Response

```json
{
  "description": "A simple server",
  "application": "linwood-swamp",
  "max_players": 10,
  "protocols": [0]
}
```

The `protocols` field lists the protocol versions the server supports (e.g. `[0]`).

## Websocket: `GET`

Connect to the websocket to receive real-time updates.

### Protocol Version Negotiation

The client **must** specify its protocol version using the `Sec-WebSocket-Protocol` header during the upgrade handshake.
The subprotocol format is `swamp-<version>` (e.g. `swamp-0`).

If the server does not support the requested version, it responds with HTTP `400 Bad Request` and a JSON body:

```json
{
  "error": "unsupported_protocol",
  "supported": ["0"]
}
```

Clients should fetch `/info` first to discover supported protocol versions before connecting.

### Available Events

#### Message

|      |                  |                    |                  |
| ---- | ---------------- | ------------------ | ---------------- |
| 0x00 | Sender (2 Bytes) | Receiver (2 Bytes) | Message (String) |

#### Room Info Update

If we change a room or request a room info.

|      |                |                       |                   |                 |
| ---- | -------------- | --------------------- | ----------------- | --------------- |
| 0x01 | Flags (1 Byte) | Max Players (2 Bytes) | Your ID (2 Bytes) | Room ID (Bytes) |

See [Room Flags](#room-flags) for more information.

#### Welcome

If you join the server.

|      |
| ---- |
| 0x02 |

#### Kicked from room

If you are kicked from a room.

|      |               |                  |
| ---- | ------------- | ---------------- |
| 0x03 | Reason (Byte) | Message (String) |

##### Reasons

| Reason | Description      |
| ------ | ---------------- |
| 0x00   | Room closed      |
| 0x01   | Kicked from room |
| 0x02   | Banned from room |
| 0x03   | Host left        |
| 0xFF   | Unknown error    |

#### Room join failed

If you want to join a room but it fails.

|      |               |
| ---- | ------------- |
| 0x04 | Reason (Byte) |

##### Reasons

| Reason | Description          |
| ------ | -------------------- |
| 0x00   | Room does not exist  |
| 0x01   | Room is full         |
| 0x02   | Banned from room     |
| 0x03   | Application mismatch |
| 0xFF   | Unknown error        |

#### Room creation failed

If you create a room but it fails.

|      |               |
| ---- | ------------- |
| 0x05 | Reason (Byte) |

##### Reasons

| Reason | Description          |
| ------ | -------------------- |
| 0x00   | Room limit reached   |
| 0x01   | In room already      |
| 0x02   | Flags unsupported    |
| 0xFF   | Unknown error        |

#### Player Joined

*Dark Room Event*
Notification that a player has joined the room.

|      |                     |
| ---- | ------------------- |
| 0x06 | Player ID (2 Bytes) |

#### Player Left

*Dark Room Event*
Notification that a player has left the room.

|      |                     |
| ---- | ------------------- |
| 0x07 | Player ID (2 Bytes) |

#### Player List

*Dark Room Event (toggleable), but returns empty error if not permitted*
List of players currently in the room.

|      |                  |                     | ... |
| ---- | ---------------- | ------------------- | --- |
| 0x08 | Length (2 Bytes) | Player ID (2 Bytes) | ... |

### Available Commands

#### Send Message

|      |                     |                  |
| ---- | ------------------- | ---------------- |
| 0x00 | Player ID (2 Bytes) | Message (String) |

Send a message to the receiver.
There are some special player ids:

- `0` - Send to all players
- `1` - Send to the host

#### Join Room

|      |                 |
| ---- | --------------- |
| 0x01 | Room ID (Bytes) |

#### Leave Room

|      |                 |
| ---- | --------------- |
| 0x02 | Room ID (Bytes) |

#### Create Room

|      |                |                                 |
| ---- | -------------- | ------------------------------- |
| 0x03 | Flags (1 Byte) | Max Players (2 Bytes, optional) |

If Max Players is not set or set to `0`, the server will use the default value.

#### Kick Player

*Host only*

|      |                     |                 |
| ---- | ------------------- | --------------- |
| 0x04 | Player ID (2 Bytes) | Reason (String) |

#### Get Connected Players

|      |
| ---- |
| 0x05 |

#### Set Application

Allows you to restrict the supported rooms.
This is useful if you want to prevent users from joining rooms created by other applications (e.g. different games).
When set, you can only join rooms created by users with the same application identifier.

|      |                     |
| ---- | ------------------- |
| 0x06 | Application ID (Bytes) |

Send an empty byte array to remove the application restriction.

## Room Flags

*Currently not implemented*

| Flag | Description                                                                                          |
| ---- | ---------------------------------------------------------------------------------------------------- |
| 0x01 | Dark Room (Restrict some events to only be seen by the host)                                         |
| 0x02 | Toggle Player Visibility (On dark rooms, players can see each other, on normal rooms, they can't)    |
| 0x04 | Switch Host on Host Leave (If the host leaves, the host will be changed instead of closing the room) |
