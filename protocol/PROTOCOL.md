# PIF Online protocol

Version: **1**

The client and the server exchange UTF-8 JSON objects over TCP, one object per
line (`\n`). A line never exceeds 16 KiB. Each object has a type `t` and an
optional payload `d`:

```json
{"t":"move","d":{"map":12,"x":4,"y":9,"dir":2,"speed":3}}
```

The first client message must be `hello`. Any invalid message closes the
connection, preceded by an `error` message when the reason is useful to the
client. Every client sends `ping` at least every 5 seconds; a connection silent
for 15 seconds is closed.

## Shared objects

`state`: `map` (1-9999), `x` and `y` (0-9999), `dir` (2, 4, 6 or 8),
`speed` (1-6).

`appearance`: `skin` (0-99); `clothes`, `hair`, `hat`, `hat2` (string or null,
at most 64 characters among letters, digits, space, `_`, `-`, `.`, and never
`..`); `clothes_color`, `hair_color`, `hat_color`, `hat2_color` (integers within
±1,000,000).

## Client to server

| Type | Payload | Meaning |
|---|---|---|
| `hello` | `v`, `name` (1-32 characters, no control character) | Opens the session |
| `ping` | none | Keeps the connection alive |
| `move` | `state` | Reports the local player's position |
| `appearance` | `appearance` | Reports the local player's look |
| `interest` | `maps` (at most 16 map ids) | Maps the client is displaying |

## Server to client

| Type | Payload | Meaning |
|---|---|---|
| `welcome` | `id` | Session accepted |
| `error` | `code`, `message` | Reason for an imminent close |
| `pong` | none | Reply to `ping` |
| `player_joined` | `id`, `name`, `appearance`, `state` | A player became visible |
| `player_moved` | `id`, `state` | A visible player moved |
| `player_appearance` | `id`, `appearance` | A visible player changed look |
| `player_left` | `id` | A player is no longer visible |

A player is visible to a client when the player's map is in that client's
`interest` list. Error codes are `version_mismatch`, `bad_message`,
`server_full` and `rate_limited`.

Any change to this file that breaks compatibility must increment the version,
in `server/internal/protocol` and in the client's `core/001_config.rb`.
