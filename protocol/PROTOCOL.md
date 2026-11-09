# PIF Online protocol

Version: **4**

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

`rules`: `party_size` (1-6), `level` (0 keeps each Pokémon's level, otherwise
1-100), `held_items` (bool), `turn_seconds` (30-300), `clauses` (array of
distinct clause ids, possibly empty or null).

`pokemon`: `species`, `nature` (symbol: at most 32 letters, digits or `_`);
`level` (1-100), `form` (0-99), `personal_id` (0-4294967295), `gender` (0-2);
`ability`, `item`, `hidden_power_type`, `size_category` (symbol or null);
`ability_index` (0-5 or null); `happiness` (0-255); `iv` (6 integers 0-31),
`iv_maxed` (6 booleans), `ev` (6 integers 0-252 summing to at most 510);
`moves` (1-4 of `{id, pp 0-255, ppup 0-3}`, `id` a symbol); `name` (1-24
characters, no control character); `shiny`, `head_shiny`, `body_shiny`
(booleans); `pif_sprite` (string or null, at most 64 letters, digits, `_`, `.`,
`-`, never `..`). A party has exactly `party_size` members. If `held_items` is
false every `item` must be null; if `level` is set every Pokémon must have it.

Clause ids: `sleep`, `freeze`, `ohko`, `evasion`, `perish`, `skill_swap`,
`sonic_boom` change the simulation; `moody`, `no_legendary`, `species`, `item`,
`no_fusion` restrict teams. See "Duels" for who enforces what.

## Client to server

| Type | Payload | Meaning |
|---|---|---|
| `hello` | `v`, `name` (1-32 characters, no control character) | Opens the session |
| `ping` | none | Keeps the connection alive |
| `move` | `state` | Reports the local player's position |
| `appearance` | `appearance` | Reports the local player's look |
| `interest` | `maps` (at most 16 map ids) | Maps the client is displaying |
| `duel_challenge` | `target`, `rules` | Challenges a player |
| `duel_response` | `from`, `accept` | Answers a challenge from `from` |
| `duel_party` | `party` (array of `pokemon`), `appearance` | The player's team and look, after `duel_accepted` |
| `duel_choice` | `round`, `action` (`move` or `switch`), `index` | Action for a round |
| `duel_replacement` | `seq`, `index` | Replaces a fainted or U-turned Pokémon |
| `duel_hash` | `round`, `hash` (1-64 characters) | State hash after a resolved round |
| `duel_result` | `winner` (0, 1 or null) | The outcome this client simulated |
| `duel_forfeit` | none | Gives up the duel |
| `duel_replacing` | none | The sender must pick a replacement before the duel can go on |
| `duel_reject` | none | A team breaks the rules: cancels the duel, after `duel_accepted` and before round 1 resolves |

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
| `duel_invited` | `from`, `name`, `rules` | A player challenges you |
| `duel_declined` | `target`, `reason` | The challenge with player `target` is off |
| `duel_accepted` | `opponent` | Challenge accepted: send `duel_party` |
| `duel_start` | `seed`, `side`, `rules`, `players`, `parties` | The duel begins |
| `duel_turn` | `round`, `choices` | Both choices of a round, in side order |
| `duel_replaced` | `side`, `seq`, `index` | A side's replacement, sent to both |
| `duel_ended` | `winner` (0, 1 or null), `reason` | The duel is over |

A player is visible to a client when the player's map is in that client's
`interest` list. Error codes are `version_mismatch`, `bad_message`,
`server_full` and `rate_limited`.

## Duels

The server does not simulate battles: both clients simulate the same duel from
`seed` (uint32). `side` is the receiver's side, 0 for the challenger and 1 for
the challenged player. `players` (`{id, name, appearance}`) and `parties` are in
side order and identical for both clients. A `duel_party` without `appearance` draws
that player with an empty `appearance`.

A player is in at most one challenge or duel. `duel_declined` reasons are
`refused`, `busy`, `offline` and `expired`; its `target` is always the other
player, and it is sent to both players when a challenge expires. An unanswered
challenge expires after 30 seconds, and so do parties not received within 30
seconds of `duel_accepted`. `duel_start` is sent once both parties are valid.

Rules reach both clients unchanged through `duel_start`, and clauses apply to
the simulation only from there. Team legality has three layers. Whatever the
party payload proves is enforced by the server, which holds no game data, and a
party failing it closes the connection: `level`, `held_items`, `species` (no two
identical `species` ids, so head and body both match), `item` (no two identical
non-null items) and `no_fusion` (ids of the form `B<n>H<n>`). What needs game
data (`no_legendary`, `moody`, and triple fusions for `no_fusion`) is checked by
each client against the opponent's party on `duel_start`: an illegal party makes
it send `duel_reject`. Before sending its own party a client checks it under all
rules and, if the team became illegal since the challenge, sends `duel_reject`
instead. `duel_reject` ends the duel with `illegal_party` and no winner.

Round numbers start at 1. Round 1 has a `turn_seconds` timer from `duel_start`,
which is why `turn_seconds` is at least 30: longer than the battle intro. Later
rounds allow 60 extra seconds for animations after each `duel_turn` and
`duel_replaced`; the timer becomes exactly `turn_seconds` once both players sent
the `duel_hash` of the previous round, which they do just before choosing, or
when a player first sends `duel_replacing`. When it runs out the player who has
neither chosen nor sent `duel_result` loses by `timeout`; if both are missing
there is no winner. A side that sent `duel_replacing` and has not yet sent its
`duel_replacement` loses by `timeout` when the other side has not done the same;
this is an admission a client can only make against itself, so the server
trusts it. `duel_choice` must name the current round, once per player.
`index` is a move slot (0-3) or a party slot (below `party_size`).

`duel_replacing` and `duel_replacement` are only valid after round 1 resolved. `seq` starts at 0 or
more and must grow per side, gaps being allowed; at most 8 per side per round.

`duel_hash` is sent for each resolved round, in order. Hashes are compared per
round once both are in; a mismatch ends the duel with `desync` and no winner.
`duel_ended` reasons are `forfeit`, `disconnect`, `timeout`, `desync`,
`illegal_party` and `finished`. `finished` requires both clients to report the same `duel_result`
winner; disagreement ends with `desync`.

A duel message that cannot be valid closes the connection. Messages already in
flight when a match ended, within 15 seconds, are ignored, and so is any
`duel_response` for a challenge that no longer exists.

Any change to this file that breaks compatibility must increment the version,
in `server/internal/protocol` and in the client's `core/001_config.rb`.
