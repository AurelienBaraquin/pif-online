# CLAUDE.md

Operating guide for AI agents working in this repository. Read it first, every session. If it
conflicts with an older instruction, **this file and the documents it links win**.

## 1. Project

PIF Online is a multiplayer overlay for Pokémon Infinite Fusion 2 (Hoenn): players see each other
on a shared overworld and fight duels against each other. Two programs: a Ruby overlay installed
into the game (`client/998_Multiplayer/`), and a Go server one player hosts (`server/`). The game
itself is not in this repository.

- Brief — what to build, scope, priorities, success criteria: `docs/brief.md`. **Read it at the
  start of every session**; it is the source of truth for *what* to build.

## 2. Map

This file stays short. Details live in the documents below — link to them, do not copy them here.

| Topic | File |
|---|---|
| What to build: purpose, scope, priorities, success criteria | `docs/brief.md` |
| Index of all documentation: structure, protocol, tests, release, technologies… | `docs/README.md` |
| Code structure and flows | `docs/architecture.md` |
| Wire protocol between client and server | `protocol/PROTOCOL.md` |
| Decisions and their reasons | `docs/adr/` · `.assistant/decisions-log.md` |
| Mistakes already made, and what now prevents them | `.assistant/lessons.md` |
| Player and host instructions (French) | `README.md` |

## 3. Hard rules

1. Every piece of new logic ships with a test. `go test -race ./...` (in `server/`) and
   `tools/engine-test/suite.sh quick <game> <stage>` must pass before a change is done; run the
   category that covers what you touched (`docs/testing.md`).
2. Never commit secrets, credentials or `.env` files; secrets come from the environment. Validate
   all external input at the boundary.
3. Never deserialize network data with `Marshal`; the wire format is JSON lines
   (`protocol/PROTOCOL.md`), validated on both sides.
4. Never kill a process by name (`taskkill /IM`, `pkill -f`): the owner plays the game and other
   games meanwhile. Stop only the PIDs your own script started, after checking their path.
5. Never capture the full screen: the owner's private applications are open. Capture only a game
   window, or list its windows' text (`docs/testing.md`).
6. Never modify the owner's real game installation or its saves except through the public
   installer, after backing the saves up; tests and sandboxes use their own copies.
7. Commit directly to `main`, in small commits that each leave the tests green.
8. Commits follow Conventional Commits (`feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `ci`, `perf`, `build`).
9. Never add `Co-Authored-By` or "Generated with" lines to commits or pull requests; `.claude/settings.json` disables them.
10. The skills in `.claude/skills/` are copies of the claude-project-kit; update them with the kit's `install.sh --project .` and do not edit them in place.
11. The documentation check (`node scripts/check-docs.mjs`) runs before every commit, and fails when a surface has no document; fix what it reports instead of bypassing it.
12. The documentation check also runs in CI.
13. Enable the git hooks once per clone with `git config core.hooksPath .githooks`; Claude Code refuses `git commit` until they are active.
14. Working mode: act freely on reversible changes; stop on structural or irreversible ones. The owner can override it for a given task.
15. Always ask before: deleting files or data.
16. Autonomy: without asking you may edit documentation, write ADRs and decision-log entries,
    commit, push, and tag a release once its tests pass. Anything else that
    changes the repository or the outside world: ask first.
17. Documentation (`README.md`, `docs/`) is written in French, except this file; code, comments,
    commits and `protocol/PROTOCOL.md` are written in English.
18. Do what the task asks, nothing more.
19. Read a file fully before editing it.
20. Never state something about the code you have not verified in the code.
21. Documentation is part of done: a change is not finished until the documents that describe what
    it touched are updated, in the same change.
22. Everything that exists and that someone needs to build, run, test, ship, operate or use the
    project has one document, listed in `docs/README.md`. A new surface (interface, data model,
    service, technology, pipeline, environment, command, configuration variable) gets its document
    in the change that introduces it. Keep one home per fact: link, do not copy, and prefer a
    generated reference when the code is the source of truth.

## 4. Commands

```bash
git config core.hooksPath .githooks                      # once per clone
(cd server && go vet ./... && go test -race ./...)        # server
tools/engine-test/suite.sh quick <game-dir> <win-stage>   # client, in the real engine (~1 min)
tools/release/build.sh dist                               # every release file
node scripts/check-docs.mjs                               # documentation check
```

## 5. Living documentation protocol

The documentation is part of the product. You are **authorised, and expected, to keep it
current without asking**, in the same change as the code. Decisions are not final: they can be
superseded, but never silently.

| When | Do |
|---|---|
| You start on this project with no prior context (a new session, or you are a sub-agent) | Run the `project-onboard` skill before the task; it only reads |
| You make or notice a structural choice (dependency, pattern, data model, boundary, tool, process) | Run the `adr-new` skill: an ADR if it is architectural, otherwise one dated line in `.assistant/decisions-log.md` |
| Your change adds, moves, removes or alters anything that exists in the project — a module, API, command, data model, event, configuration variable, service, technology, pipeline, environment, test setup, deployment step or user-visible behaviour | Update the document that covers it (find it in `docs/README.md`), or create it if the surface is new — the `project-sync` skill describes what each kind of document must contain — and keep the index true, in the same change |
| The scope, priorities or success criteria change (the user says so, or the work shows the brief is wrong) | Propose the change, update `docs/brief.md` once the user agrees, and record it with `adr-new`; never edit the brief silently |
| A document, rule or past decision turns out to be wrong or stale | Fix the document; for a decision, write a new ADR that supersedes the old one |
| A mistake was caught by review, CI or the user | Add an entry to `.assistant/lessons.md`; if it can be enforced, propose a test, lint rule or hook |
| Before opening a PR, and at the end of a work session | Run the `project-sync` skill and fix what it reports |

Describe only what exists. If you do not know, write it under *Open questions* and ask the
user — never guess into a document. Keep this file under about 100 lines.

## 6. Open questions

See `.assistant/takeover-report.md` (second-PC invisibility, unverified two-PC duel and VPS install).
