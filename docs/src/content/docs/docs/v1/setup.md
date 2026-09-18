---
title: Setup
---

## Get the server

To get started with Swamp, first download the latest release from the [downloads page](/downloads/).
Docker is the recommended way to run the server, but you can also download the binaries for your platform.

## Run the server

Just run the server and it will start listening on port `8080` by default.
To change the port, use the `PORT` environment variable.

Please note that you need applications uses http/https ports, so you need to specify a the port (http: `80`, https: `443`) if you want to use these ports or use a reverse proxy like nginx or apache.

To run the server in https mode, you need to create a `certs` folder in the same directory (make sure to add a volume if you are using docker) and add your `server.key` (private key) and `server.crt` (certificate) files there.

## Configuration

You can configure certain aspects of the server using environment variables:

| Variable | Description | Default |
| :--- | :--- | :--- |
| `SWAMP_DESCRIPTION` | A description of the server, visible in the info endpoint. | `""` |
| `SWAMP_MAX_PLAYERS_PER_ROOM` | The maximum number of players allowed in one room. | `1024` |
| `SWAMP_MAX_CONCURRENT_PLAYERS` | The maximum number of players participating across all rooms. Set to `0` for unlimited. | `0` |
| `SWAMP_MAX_ROOMS` | The maximum number of active rooms. Set to `0` for unlimited. | `0` |
| `SWAMP_NO_DARK_ROOMS` | Set to `true` to disable the creation of "dark rooms" (rooms with limited visibility). | `false` |

## Authentication

Authentication is disabled when no authentication source is configured. The
standalone server supports a static JSON file, a REST API, or both (sources are
tried in that order):

| Variable | Description | Default |
| :--- | :--- | :--- |
| `SWAMP_AUTH_FILE` | Comma-separated paths to static JSON token files. | unset |
| `SWAMP_AUTH_URL` | Comma-separated REST endpoints used to validate bearer tokens. | unset |
| `SWAMP_AUTH_REQUIRE_CONNECTION` | Require authentication before the connection may use Swamp commands. | `true` |
| `SWAMP_AUTH_REQUIRE_CREATE` | Require an authenticated user with create permission to create rooms. | `true` |
| `SWAMP_AUTH_MAX_CONNECTIONS_PER_USER` | Maximum simultaneous connections for one user, for example `1`. | unlimited |

Multiple sources can be configured by separating values with commas. Sources
are tried until one authenticates the token: files first, followed by REST
endpoints, while preserving the order within each list.

```bash
SWAMP_AUTH_FILE=/run/secrets/team.json,/run/secrets/guests.json
SWAMP_AUTH_URL=https://auth.example.com/validate,https://backup.example.com/validate
```

The static file maps secret tokens to user IDs and optional room-creation
permission:

```json
{
  "tokens": {
    "secret-token": { "userId": "alice", "canCreateRooms": true },
    "guest-token": { "userId": "bob", "canCreateRooms": false }
  }
}
```

Protect this file with operating-system permissions; it contains credentials.
The server reloads it after it changes.

The REST source makes a JSON `POST` request and sends the bearer token in both
the `Authorization` header and the `token` property. A successful response is:

```json
{ "userId": "alice", "canCreateRooms": true }
```

Return HTTP `401` or `403` for invalid credentials. Other non-success responses
temporarily reject the connection with HTTP `503`.

Clients authenticate immediately after opening the WebSocket by sending the
token with the Swamp authentication command. The Dart client does this
automatically when `accessToken` is set. This is the recommended mechanism for
native and browser clients. Use `wss` in production so the token is encrypted
in transit.
