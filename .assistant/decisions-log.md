# Decisions log

Running record of the choices that are too small for an ADR but worth remembering: what was
decided and why. Newest entries at the bottom. A choice that shapes the architecture gets an ADR
in `docs/adr/` and a one-line pointer here.

Format: `YYYY-MM-DD — what was decided — why (the trade-off)`.

Never rewrite history: if a choice is reversed, add a new line that says so.

- 2026-11-09 — Protocol is UTF-8 JSON, one object per line over TCP — readable in logs and parsable by the engine's own `HTTPLite::JSON`; never `Marshal`, which would execute what a peer sends (evidence: `protocol/PROTOCOL.md`).
- 2026-11-09 — The server runs all game logic on one hub goroutine — features need no locking (evidence: `server/internal/session/hub.go`).
- 2026-11-09 — Every overlay hook runs inside `Guard.run`, which disables only the failing site — an overlay bug must never end the player's session (evidence: `client/998_Multiplayer/core/002_log.rb`).
- 2026-11-09 — Duels use canonical battler indices on both clients — see ADR-0002.
- 2026-11-09 — Repository is public — the installers download from GitHub Releases.
- 2026-11-13 — One supported game version, 1.3.2 — see ADR-0001.
- 2026-11-13 — Servers are chosen from an in-game menu; one-command installer — see ADR-0003.
- 2026-11-13 — Game-build fingerprint excludes `Data/Scripts/DownloadedSettings.rb` — the game re-downloads it, so two identical installs could differ (evidence: `client/998_Multiplayer/core/006_game_build.rb`).
- 2026-11-15 — Engine tests are grouped into quick, world, duel and deep — the full suite took too long to run after every change (evidence: `tools/engine-test/suite.sh`).
- 2026-11-15 — Agent foundations added (CLAUDE.md, docs/, vendored skills, docs check in a git hook and CI) — so other agents can work on the project without the owner's personal setup.
