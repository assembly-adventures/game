# Assembly Adventures

A Godot game for learning computer architecture, hosted on UNC CloudApps with
CSXL Onyen login and PostgreSQL-backed progress.

The current release includes two levels of ten puzzle gates each. Registers go
by their ABI names (`a0`, `t1`, `sp`, `ra`), with each x-name in small print:

- **Level 1 (registers):** binary and hex, signed values, overflow, logical
  operations, and shifts. Players press RISC-V instruction keys (`addi`, `slli`,
  `xori`, …) to make an 8-bit register match a target pattern of bulbs.
- **Level 2, Memory Maze:** addresses, row-major layout, `lw`/`sw` with offsets,
  arrays, branches, loops, and procedure calls, following Lecture 4. Each run
  draws ten rooms from a bank of sixteen: four tutorial rooms, then one memory,
  one branches, and one loops room at random, both procedure rooms, and a race
  against the Chip Chomper. Maze rooms are memory words seen from above: players
  steer the robot with the arrow keys and click words to load and store them,
  and every action is written as a real RISC-V line. Some rooms teach the robot
  one pass of a loop and let it repeat. Code rooms are short programs with blank
  lines: players pick a line for each blank and run the room's tests while the
  robot walks the code as the PC, and the registers, data, and stack change
  beside it.

On every gate, **Instruction guide** in the top bar (or the I key) spells out
each instruction's abbreviation, how it's written, and what it does, plus the
registers in play.

A gate opens by itself when its goal holds. The server grades by replaying what
the player did, so any valid solution passes. Running out of moves, or a code
room's run that fails a test, is a strike; on a gate's third strike the Chip
Chomper drags the player back one gate, which must be opened again. Players can
resume unfinished runs and earn a saved badge for each level. Other levels are
inactive. Verified Onyen and PID are retained for roster use; PID stays out of
game responses and session cookies. Grading and badge awards happen on the
server.

[Play the hosted game](https://assembly-adventures-teddyt.apps.cloudapps.unc.edu/)
(requires UNC login). The current CloudApps namespace is `teddyt`.

## Start developing

```bash
git clone https://github.com/godondi/assembly-adventures.git
cd assembly-adventures
```

Use **Godot 4.7.2**, matching web export templates, **Python 3.12**, and
**PostgreSQL 16** (Docker is convenient for a separate local database).
Import `project.godot` in Godot and wait for asset imports to finish.
`F5` starts the project at `start_page.tscn`; `F6` previews the current scene.
Desktop scene previews do not have a UNC browser session, so saved gameplay
requires the web build and authenticated API. When progress cannot load, the
Control Center offers **Play as guest**: Levels 1 and 2 run from
`levels/level_1/guest_rooms.json` and `levels/level_2/guest_rooms.json`, are graded
in the client, and reset on reload. Level 2's file holds its whole room bank and
draw rule, and guest runs draw the same way. Keep those files in sync with the
rows in the database (a gameplay test checks them).

Follow the [developer guide](Docs/development.md) for a runnable local database
setup, tests, environment variables, code map, and contribution workflow.

## Documentation

| Guide | Use it for |
| --- | --- |
| [Developer onboarding](Docs/development.md) | Local setup, architecture, testing, and common changes |
| [Deployment and operations](infra/README.md) | Exporting, CloudApps login, migrations, backups, and namespace moves |
| [Gameplay API](Docs/gameplay-api.md) | Authentication, answer formats, retries, and error responses |
| [Database schema](Docs/schema.md) | Tables, snapshots, question authoring, and migration rules |
| [Level brainstorm](Docs/level-brainstorm.md) | Puzzle ideas for every level, mapped to the COMP 311 calendar |
| [Asset credits](assets/CREDITS.md) | Sources and licenses for fonts, sounds, music, and sprites |
| [Legacy question bank](Docs/questionBankDocs.md) | Understanding the original `questions.json` import format |

The database is the runtime question source. `questions.json` is historical
bootstrap input, not the game's content feed. Apply database changes with
`python -m server.database`; never rerun seeds manually on an existing database
or edit migration files that have already been deployed.

Before submitting changes, run the checks relevant to your work in the developer
guide and review `git diff`. Keep credentials, roster data, database dumps,
`.godot/`, and generated `build/` output out of commits.
