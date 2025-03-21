---
title: API Reference
---

# API

The current api version is `v0` and paths are prefixed with `/api/v0`.

## `GET /api/v0/info`

Returns information about the server like the name but no sensitive information.

### Response

```json
{
  "description": "A simple server",
  "application": "linwood-swamp",
  "max_players": 10
}
```

## Websocket: `GET /api/v0/ws`

Connect to the websocket to receive real-time updates.

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

| Reason | Description        |
| ------ | ------------------ |
| 0x00   | Room limit reached |
| 0xFF   | Unknown error      |

##### Types

| Type | Description             |
| ---- | ----------------------- |
| 0x00 | Joined websocket server |
| 0x01 | Kicked from room        |
| 0x02 | Room does not exist     |
| 0x03 | Room is full            |
| 0x04 | Room creation           |

#### Player Joined

*Dark Room Event*

|      |                     |
| ---- | ------------------- |
| 0x06 | Player ID (2 Bytes) |

#### Player Left

*Dark Room Event*

|      |                     |
| ---- | ------------------- |
| 0x07 | Player ID (2 Bytes) |

#### Connected Players

*Dark Room Event (toggleable), but returns empty error if not permitted*

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

|      |                       |
| ---- | --------------------- |
| 0x03 | Max Players (2 Bytes) |

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

You can use:

|      |                   |                      |
| ---- | ----------------- | -------------------- |
| 0x06 | Version (4 Bytes) | Application (String) |

to set the application or:

|      |
| ---- |
| 0x07 |

to remove the application restriction.

## Room Flags

| Flag | Description                                                                                          |
| ---- | ---------------------------------------------------------------------------------------------------- |
| 0x01 | Dark Room (Restrict some events to only be seen by the host)                                         |
| 0x02 | Toggle Player Visibility (On dark rooms, players can see each other, on normal rooms, they can't)    |
| 0x04 | Switch Host on Host Leave (If the host leaves, the host will be changed instead of closing the room) |
