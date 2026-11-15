# Lessons

Mistakes made on this project (by a person or an AI agent) and what now prevents them. Read it
before starting work; add to it whenever review, CI or the user catches something.

Each entry: `YYYY-MM-DD — what went wrong — how it was caught — what now prevents it`.
"What now prevents it" must be concrete: a test, a lint rule, a hook, a rule in `CLAUDE.md`, a
check in CI. An entry with no prevention is an open problem; say so.

- 2026-11-13 — The party codec allowed dex numbers 1..501 while game 1.3.2 has more, so fusions with newer Pokémon broke the interaction menu — the owner, on a real save — `DEX_NUMBERS` now comes from `::Settings::NB_POKEMON`, and the `codec` test covers the whole dex.
- 2026-11-13 — `Settings::NB_POKEMON` inside `module Multiplayer` resolved to the overlay's own `Settings` and raised a NameError dialog that hung the tests; the agent first blamed the owner for closing windows — listing the test process's windows — rule in `docs/architecture.md` (`::Settings`) and `docs/technologies.md`; diagnose hangs by listing window text, never by guessing.
- 2026-11-13 — The agent took a full-screen capture that showed the owner's private apps — the owner — `CLAUDE.md` rule 5.
- 2026-11-13 — `pkill -f` matched the agent's own shell and killed it; killing processes by name also risks the owner's running games — exit code 144 — `CLAUDE.md` rule 4 (stop only recorded PIDs, as `tools/sandbox/two-games.sh stop` does).
- 2026-11-13 — The installer refused to run while any copy of the game was open, even another install — manual run — it now checks only processes whose path is inside the target folder.
- 2026-11-13 — The game-build fingerprint included a file the game re-downloads, so identical installs could refuse each other's duels — code review — the file is excluded (`RUNTIME_FILES`); no automated test yet (open).
- 2026-11-13 — A tool run from a game copy's `Data/Scripts` created `.claude-flow/`, which the game's loader would execute — noticed in the release zip — `tools/release/build.sh` packs only git-tracked files and `tools/sandbox/two-games.sh` deletes `.claude-flow`; `docs/technologies.md` says never to work there.
- 2026-11-13 — Updating the owner's real game with `git reset --hard` was blocked because it would destroy local files — permission classifier — `CLAUDE.md` rule 6 (only the public installer, after a save backup).
- 2026-11-13 — A lightweight `git tag` push failed (tag messages required here) — push error — `docs/release.md` says to use `git tag -a -m`.
