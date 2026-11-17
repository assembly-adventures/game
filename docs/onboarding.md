# Start here: onboarding for new developers

Welcome. This page is a map. It tells you how Assembly Adventures fits
together, what to do on your first day, which document answers which question,
and the few rules that cause real trouble when they're broken. The details live
in the documents it links to; read those when a task calls for them.

## What you're working on

Assembly Adventures is a browser game for COMP 311 (Computer Organization) at
UNC. Students sign in with their Onyen and play levels of puzzle "gates" that
teach RISC-V assembly, the call stack, and timing and pipelining. The
[README](../README.md) describes each level as players see it.

| Level | Name | What the player does |
| --- | --- | --- |
| 1 | Basic RISC-V Commands | Presses instruction keys to turn one register value into another |
| 2 | Memory Maze | Walks memory with loads and stores, and fills in blank lines of code |
| 3 | Call Stack Tower | Follows calls and returns, and makes the moves that keep the stack right |
| 4 | Timing Lab | Draws waveforms, tunes clocks, places pipeline diagrams, and adds stalls |
| 5, 6, challenge | (placeholders) | Not built yet; see [what is left to build](adding-content.md#what-is-left-to-build) |

Staff (TAs and professors) get a dashboard with class and per-student
statistics; see [classroom features](classroom-features.md).

## How the pieces fit

- **The game** is a Godot 4.7.2 project (GDScript), exported to the web. Each
  level is `levels/gate_level.gd` running that level's gates.
- **The server** is FastAPI (`server/`) backed by PostgreSQL 16, hosted on UNC
  CloudApps (OpenShift). Players sign in through CSXL's Onyen login; the
  server never trusts identity sent by the game.
- **A question is data, not code.** Each gate is a row in `aa.questions` whose
  `payload.kind` picks two things: the room script that draws it in the game,
  and the grader that checks it on the server. The server replays every answer
  and has the final say on whether it is right and how many stars it earns.
- **Guest mode** plays the same gates without signing in. It reads them from
  `levels/level_<n>/guest_rooms.json` and grades in the game, with a copy of
  each grader written in GDScript. A test checks that the JSON files match the
  database.
- **The database changes only through migrations** in `db/migrations/`, which
  are applied in order and recorded with a checksum.

| Level | Payload kinds | Room script (game) | Grader (server) |
| --- | --- | --- | --- |
| 1 | `moves` | `levels/level_1/puzzle_room.gd` | `server/puzzles.py` |
| 2 | `maze`, `code` | `levels/level_2/maze_room.gd`, `code_room.gd` | `server/puzzles.py` |
| 3 | `walk` | `levels/level_3/walk_room.gd` | `server/call_stack.py` |
| 4 | `wave`, `table` | `levels/level_4/wave_room.gd`, `table_room.gd` | `server/timing.py` |

For the full file-by-file map and the path of a request, read the
[developer guide's code map](development.md#code-map-and-request-flow) and the
[schema's architecture section](schema.md#architecture).

## Your first day

1. **Get access.** You need the GitHub repository. You need CloudApps
   (OpenShift) access only if you will deploy; the live site runs in the
   original developer's namespace, `teddyt`, so ask the course staff who owns
   it now, or [move it to your own](../infra/README.md#moving-to-another-namespace).
2. **Install the tools** in the developer guide's
   [prerequisites](development.md#prerequisites): Godot 4.7.2 with its export
   templates, Python 3.12, and PostgreSQL 16 (Docker is easiest).
3. **Run the server tests** against a throwaway local database, as in
   [local server and database tests](development.md#local-server-and-database-tests).
   They should all pass before you change anything.
4. **Play the game.** Open `project.godot` in Godot, press F5, and choose
   **Play as guest** in the Control Center. Play a few gates of each level.
5. **Read [how content is stored](adding-content.md#how-content-is-stored).**
   Most work on this project is adding or changing gates.
6. **Make one small change end to end**, such as fixing a typo in a gate's
   prompt, following [replace or fix a question](adding-content.md#replace-or-fix-a-question):
   change the JSON, write the migration, run the tests, play it in guest mode.

## Where to look

| I want to… | Read |
| --- | --- |
| Understand what each level teaches, and why it is designed that way | [README](../README.md), [level brainstorm](level-brainstorm.md) |
| Set up, run tests, find a file, or fix a common error | [Developer guide](development.md) |
| Add, replace, or fix a question | [Adding content](adding-content.md#add-a-question-to-an-existing-level) |
| Add a new kind of room, or a new level | [Adding content](adding-content.md#add-a-new-kind-of-room) |
| Test the game from a script, without a browser | [Checking the game without a browser](adding-content.md#checking-the-game-without-a-browser) |
| Change the database or write a migration | [Schema](schema.md#applying-and-evolving-the-schema), [developer guide](development.md#questions-or-schema) |
| Know what the game sends the server and what comes back | [Gameplay API](gameplay-api.md) |
| Change scoring, the leaderboard, nicknames, or the staff dashboard | [Classroom features](classroom-features.md) |
| Build the web release, deploy, add staff, or back up the database | [Deployment and operations](../infra/README.md) |
| Add a font, sound, or image | [Asset credits](../assets/CREDITS.md) |
| Pick the next thing to build | [What is left to build](adding-content.md#what-is-left-to-build), [level brainstorm](level-brainstorm.md) |

## Rules that cause real trouble

- **Never edit a migration that has been applied anywhere.** The migration
  runner refuses a file whose checksum changed, and the deploy fails. Put the
  change in a new migration. If you only applied it to your own local
  database, recreate that database instead.
- **Author gates in `guest_rooms.json`, then generate the SQL** with
  `tools/rooms.py`. Never write the same gate by hand in both places.
- **Every grader exists twice**, on the server and in the game for guest mode.
  Change both, and compare them on many answers before trusting guest mode.
- **Export with `web_nothreads_release.zip`.** The threaded template leaves the
  loading bar stuck. A new level's `guest_rooms.json` must also be listed in
  `export_presets.cfg`, or the web build ships without it.
- **Don't run Python inside the live pod.** It has 128 MiB of memory, and
  running tests there has taken the site down. See
  [database operations](../infra/README.md#database-operations).
- **Keep private data out of git**: credentials, roster data (Onyens and
  PIDs), database dumps, `.godot/`, and `build/`. Do commit the `.uid` file
  Godot creates next to each new script.
- **The documentation folder is `docs/`, all lowercase.** On a Mac, `Docs/`
  opens the same folder, but git and GitHub treat them as two different
  folders, so links break. Check `git status` shows new files under `docs/`.
- **Gates are puzzles, not quizzes.** Keep each one short, hands-on, and
  without arithmetic that needs a calculator (students don't have one in
  class). The [level brainstorm](level-brainstorm.md#design-principles) and
  [adding content](adding-content.md#level-4-rooms) explain why.

## Course material

The COMP 311 calendar is in `docs/` and is what the
[level brainstorm](level-brainstorm.md) maps levels onto. The lecture slides and
in-class practice sheets that the gates are based on (Level 4 uses Lectures 15,
18, 20, 22, and 23) are course material and are not in this repository; ask the
course staff for them. The level brainstorm says which lectures each level
follows.

## Before you hand off

Follow the developer guide's
[checklist for handing off or deploying](development.md#before-handing-off-or-deploying).
If you add a document, add it to the table above and to the
[README's documentation list](../README.md#documentation).
