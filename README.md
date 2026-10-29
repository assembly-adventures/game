# Assembly Adventures

A Godot game for learning computer architecture, hosted on UNC CloudApps with
CSXL Onyen login and PostgreSQL-backed progress.

The current release includes three levels of ten puzzle gates each. Registers
go by their ABI names (`a0`, `t1`, `sp`, `ra`), with each x-name in small print:

- **Level 1 (registers):** binary and hex, signed values, overflow, logical
  operations, and shifts. Players press RISC-V instruction keys (`addi`, `slli`,
  `xori`, …) to make an 8-bit register match a target pattern of bulbs. Each run
  draws ten gates from a bank of twenty-two: the four tutorial gates, then one
  gate on each topic (hex, masks, flips, signed values, overflow, and shifts).
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
- **Level 3, Call Stack Tower:** procedures, `jal` and `jalr`, the calling
  convention, stack frames, and recursion, following Lectures 6 and 7, as a
  story of eight walkthroughs students follow along. Each room is a short
  program played line by line: the code lights the line that ran, the stack
  hangs below as a tower of frames with the robot riding `sp`, the registers sit
  above the code, and a caption says what each line did, with its values. Play
  runs it at reading pace (each line stays up long enough to read its caption);
  Step and Back move a line at a time. When the walk reaches a move, the student
  makes it by dragging a block of code from a bank beside the program into the
  gold slot where it goes: the call (`jal` or `j`), what a frame saves (its
  prologue; the matching epilogue comes with it), where to keep a value across a
  call, the base case. A wrong move plays out, shows what breaks, and rewinds,
  costing a star but never a strike. The rooms go in order: a call, the
  way back, keeping a value, borrowed `s` registers, recursion down and up, the
  base case, two calls, and a race against the Chip Chomper climbing up from the
  heap.

Every gate starts with its goal in one line and the idea it turns on underneath,
and numbers its steps beside the controls they use; a hint, once asked for,
appears without moving anything.

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

The Control Center's trophy opens weekly per-level standings, ranked by highest
stars then fewest mistakes in each player's best completed run and listed by
unique nicknames, never Onyens. The adjacent gear opens audio, fullscreen,
nickname, and leaderboard visibility settings; it is also available during levels.
Approved TAs and professors can open a staff dashboard with class, question, and
individual statistics, where they can also clear inappropriate nicknames. See [classroom features](Docs/classroom-features.md)
for scoring, privacy, and staff access, and [deployment operations](infra/README.md#staff-dashboard-access)
to add or remove staff Onyens.

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
Control Center offers **Play as guest**: Levels 1 to 3 run from
`levels/level_<n>/guest_rooms.json`, are graded in the client, and reset on
reload. Each file holds its level's whole room bank and draw rule, and guest
runs draw the same way. Keep those files in sync with the rows in the database
(a gameplay test checks them).

Follow the [developer guide](Docs/development.md) for a runnable local database
setup, tests, environment variables, code map, and contribution workflow.

## Documentation

| Guide | Use it for |
| --- | --- |
| [Developer onboarding](Docs/development.md) | Local setup, architecture, testing, and common changes |
| [Deployment and operations](infra/README.md) | Installing and logging into `oc` (the OpenShift terminal), exporting, deploying, staff access, migrations, backups, and namespace moves |
| [Gameplay API](Docs/gameplay-api.md) | Authentication, answer formats, retries, and error responses |
| [Database schema](Docs/schema.md) | Tables, snapshots, question authoring, and migration rules |
| [Classroom features](Docs/classroom-features.md) | Staff statistics/access, settings, nicknames, and weekly standings |
| [Level brainstorm](Docs/level-brainstorm.md) | Puzzle ideas for every level, mapped to the COMP 311 calendar |
| [Asset credits](assets/CREDITS.md) | Sources and licenses for fonts, sounds, music, and sprites |

The database is the runtime question source. Apply database changes with
`python -m server.database`; never rerun seeds manually on an existing database
or edit migration files that have already been deployed.

Before submitting changes, run the checks relevant to your work in the developer
guide and review `git diff`. Keep credentials, roster data, database dumps,
`.godot/`, and generated `build/` output out of commits.
