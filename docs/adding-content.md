# Adding questions, rooms, and levels

A guide for the next developer. It covers the three jobs you are most likely to
be asked for, from smallest to largest: adding or replacing a question, adding a
new kind of room, and building a new level. Read
[development.md](development.md) first for setup and how to run the tests.

## How content is stored

Every question ("gate" or "room") lives in two places that must match:

| Place | Read by | Notes |
| --- | --- | --- |
| `aa.questions` in PostgreSQL | Signed-in runs | Changed only by a new migration in `db/migrations/` |
| `levels/level_<n>/guest_rooms.json` | Guest mode, and the puzzle tests | Holds the level's whole bank and its draw rule |

`server.test_gameplay.test_guest_rooms_match_the_database` fails if they differ,
so author in the JSON file and generate the SQL from it with `tools/rooms.py`.

A room has these fields:

| Field | Meaning |
| --- | --- |
| `ordinal` | Its place in the level's bank, counting from 1 with no gaps |
| `pool` | The group a draw rule picks from. Every level draws today: Levels 1 and 2 have topic pools, and in Levels 3 and 4 each gate is a pool of three versions. Omit it only in a level that plays every room in order |
| `prompt` | First line: the goal, shown large. After the first `\n`: the one idea the gate turns on. Leave out the controls ("press Race", "click a gold row"): the level's **How this level works** card in `ui/how_to_play.gd` explains them once |
| `code_snippet` | The C the room translates, or `null` |
| `hint` | Shown when the player asks; costs a star |
| `explanation` | Shown when the gate opens |
| `payload` | The puzzle itself; its `kind` picks the room script and the grader ([schema.md](schema.md#aaquestions)) |
| `answer` | One winning response, in the form the game submits it. **Show answer** displays it, and the tests use it |

## Add a question to an existing level

1. **Write the room** in `levels/level_<n>/guest_rooms.json`, at the next free
   ordinal, in an existing `pool` if the level draws. Copy a room of the same
   `kind` and change it. Include its `answer`.
2. **Check the design.** These need no database:

   ```bash
   python -m unittest server.test_puzzles server.test_call_stack server.test_timing -v
   ```

   They brute-force every room: a Level 1 gate's `par` must be the fewest
   presses, a maze's `par` the shortest program, a code room must have exactly
   one filling that passes, and a waveform room's answer must be what its
   circuit does. If a
   test names your room, the room is wrong, not the test. Some tests list
   ordinals or pool sizes (`range(1, 29)`, four gates per Level 1 pool); update
   those numbers when the bank grows.
3. **Generate the migration.** Use the next free number; never edit a file that
   has been deployed.

   ```bash
   { echo "BEGIN;"; python tools/rooms.py insert 2 21 --difficulty 2; echo "COMMIT;"; } \
     > db/migrations/0021_level2_another_room.sql
   ```

   Add a comment at the top saying what the room teaches and why it was added.
4. **Run the database tests** against a disposable database (they apply your
   migration): `server.test_gameplay` and `server.test_reporting`.
5. **Play it.** Guest mode (Control Center, **Play as guest**) plays straight
   from the JSON file with no server. A level that draws may not pick your room;
   [the headless harness notes](#checking-the-game-without-a-browser) show how
   to force it.
6. **Update the tables** in [level-brainstorm.md](level-brainstorm.md) and the
   counts in the [README](../README.md).

If the level draws rooms, check its `draw` rule (in the JSON file and
`aa.levels.draw`). A pool with `"take": 1` picks the room the player has played
least since signing in (in guest mode, since the page loaded); a tie avoids the
room from their previous run and is then broken at random. So a player sees every
room of a pool before any comes back, and a room you add to a pool is drawn next
by everyone who has already played the others. A pool with no `take` plays all
of its rooms every run. Level 2 always plays ten rooms; a test checks that.

## Replace or fix a question

A typo can be fixed in place: change the JSON, and write a migration with an
`UPDATE aa.questions SET prompt = … WHERE level_id = … AND ordinal = … AND is_active`.

Anything that changes what the question asks is a **replacement**: retire the
old row and insert a new one at the same ordinal, in one migration, so old
attempts keep pointing at what students actually saw.

```bash
{ echo "BEGIN;"
  python tools/rooms.py retire 2 11
  python tools/rooms.py insert 2 11 --difficulty 2
  echo "COMMIT;"; } > db/migrations/0021_level2_replace_room_11.sql
```

`0017_level2_room_changes.sql` is a worked example. Runs already in progress
keep the old room, because a run snapshots its questions when it starts.

### Keeping questions from being too alike

Before adding to a pool, read the whole level's table in
[level-brainstorm.md](level-brainstorm.md) and check the new room against:

- every room that always plays (the tutorial, Level 2's procedure rooms and
  finale), since a drawn room appears beside them in the same run;
- the other rooms of its own pool, since a replay draws again.

Two rooms are too alike when a player could carry the answer from one to the
other: the same C snippet, the same array and index, or the same function and
numbers. Migration `0017` replaced three Level 2 rooms for exactly this.

### Level 4 rooms

A waveform room needs no key: write the circuit, the inputs' `signals`, and the
`draw` list, and take the answer from the simulator, which is also how to check
that the picture is the one you meant:

```bash
python -c "import json; from server.timing import simulate, edges
room = json.load(open('levels/level_4/guest_rooms.json'))['rooms'][1]['payload']
print({name: edges(simulate(room)[name]) for name in room['draw']})"
```

A pipelining room's keys are in its payload (`chart.starts` or `chart.stalls`,
each clock's `path`, and each `blank`), and its `answer` is those keys in
order. Prefer the hands-on parts (a diagram to place or stall, a clock to tune)
to blanks: the level was reworked twice because lists of questions felt like a
quiz. If a room does need a blank, give it
`choices` (the key plus two or three mistakes students really make) so nothing
has to be typed, keep the arithmetic to what can be done in the head (no
division: ask for cycles or a time, and give a speedup in the explanation),
and keep a room to about six picks: the level is a study
game, and a room that takes a calculator and a page of blanks stops being one. [schema.md](schema.md#aaquestions)
describes both payloads.

## Add a new kind of room

A kind is a puzzle mechanic: `moves`, `maze`, `code`, `walk`, `wave`, `table`.
Adding one touches both sides, because the server grades and guest mode grades
again in the client. `wave` and `table` (Level 4) are the most recent examples;
search for `"wave"` to see every place.

| Step | Where |
| --- | --- |
| Grader: validate the response (422 if malformed), replay it, return true or false | A module in `server/`, called from `grade_puzzle` in `server/puzzles.py` |
| Star rule | `stars_for` in `server/scoring.py` |
| How staff read an answer | `answer_text` in `server/reporting.py` |
| Payload shape check | The `questions_payload_shape` constraint, recreated in your migration (copy `0018`) |
| Client copy of the grader, with a static `grade(room, response)` | A script under `levels/level_<n>/`, called from `_guest_attempt` in `player_data.gd` |
| The room on screen | A script registered in `ROOMS` in `levels/gate_level.gd` |
| Tests | A `server/test_<kind>.py` that checks the rules and every room's design |

The room script is a `RefCounted` that builds its controls into the box it is
given. `levels/gate_level.gd` expects this interface (the code room,
`levels/level_2/code_room.gd`, is the shortest complete example):

| Member | Purpose |
| --- | --- |
| `_init(payload, box, hint_text)` | Build the room inside `box` |
| `signal attempt` | Emit when the player has an answer to grade |
| `signal learning_event(kind, detail)` | Emit `"hint"` when the hint is shown |
| `answer() -> Dictionary` | The response to submit |
| `stars() -> int` | Stars for guest mode; the server computes its own |
| `solved()`, `failed()`, `reset()` | The gate opened; the server said no; the attempt never reached the server |
| `set_disabled(bool)` | Lock the controls while a request is in flight |
| `press(index)`, `undo()`, `restart()`, `handle_key(key)` | Keyboard: number keys, Backspace, R, and anything else the room claims |
| `guide() -> Dictionary` | Optional. What the guide panel (`ui/instruction_guide.gd`, the I key) shows: `lines` of assembly, whose instructions it explains (add an entry there for any new instruction), or a room's own `title`, `legend`, and `sections` of entries. Level 4 does the latter from `levels/level_4/timing_guide.gd`, which explains each gate with a drawing of it; add a new gate or term there. A room that sets `guide_title` renames the button |
| `miss_text()`, `retry_tip()` | The strike message |
| `show_hint()`, `fails`, `hint_used` | Restored by the runner when a run resumes |
| `static answer_lines(payload, answer) -> Array` | The reference answer in words, for **Show answer** |

The client and server graders must agree. For `wave` and `table` this was
checked by running both on a few hundred right and nearly right answers and
comparing the results; do the same for a new kind before trusting guest mode.

## Add a new level

The Control Center has six level chips and a core. Levels 5 and 6 and the
challenge are still placeholders; [level-brainstorm.md](level-brainstorm.md) has
designs for them.

1. Build the rooms (above) in `levels/level_<n>/guest_rooms.json`.
2. Create `levels/level_<n>/<name>.tscn` by copying
   `levels/level_4/timing_lab.tscn`: it is `levels/gate_level.gd` with a
   `level_id`, a `badge_icon`, and a `finish_line`.
3. Draw a badge in `images/` (an SVG at twice its on-screen size; text must be
   converted to paths, since the web build has no fonts for SVG text) and record
   it in `assets/CREDITS.md` if it is not your own.
4. In `control_center.gd`, give the level's entry in `LEVELS` its name, icon,
   and `scene`. A level without a `scene` stays locked. In `ui/how_to_play.gd`,
   add the level's card to `LEVELS`: what the player does, the controls, and
   how it scores.
5. In `player_data.gd`, add it to `GUEST_LEVELS`; in `ui/leaderboard.gd`, add
   its tab to `LEVEL_NAMES`; in `export_presets.cfg`, add its
   `guest_rooms.json` to `include_filter`, or the web build ships without it.
6. Write the migration: update `aa.levels` (name, `scene_path`, `is_active`,
   `draw`) and `aa.badges`, and insert the rooms. Copy `0018`.
7. Update the tests that count levels and badges (`test_gameplay` checks
   `badges_total` and the guest files of every level) and add a test that plays
   the level through to its badge.

Activating a level changes every player's progress bar, since progress is badges
earned out of active badges.

## Checking the game without a browser

There is no client test suite. Verify a change by driving the real scenes from a
throwaway script:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script /path/to/check.gd
```

In a `SceneTree` script, `load()` game scripts inside `_initialize()` (never
`preload`, which compiles before the autoloads exist), mount the level scene in
a 1280×720 `SubViewport`, and call `root.get_node("PlayerData").start_guest()`
first. Then `gate.puzzle` is the room on screen. To play a particular room of a
level that draws, set `PlayerData.guest_rooms[level]` to the rooms you want
before adding the scene. For screenshots, run windowed
(`--windowed --resolution 320x180`), set the viewport's
`render_target_update_mode` to `UPDATE_ALWAYS`, and save
`get_texture().get_image()` after `RenderingServer.frame_post_draw`.

After the scripts work, export and run the Chrome startup check
([development.md](development.md#game-ui-or-assets)); for a signed-in test, use
an approved deployment.

## What is left to build

| Idea | Notes |
| --- | --- |
| Levels 5 and 6, and the challenge | Placeholders. See the proposals in [level-brainstorm.md](level-brainstorm.md) (Decoder Vault, Circuit Foundry, Datapath Plumber, Memory Wall, the boss) |
| More timing and pipeline rooms | Setup and hold times, control hazards (flushes) in the pipeline diagram, and the full performance equation |
| More versions of a gate | Levels 3 and 4 have three versions of every gate. A fourth version is one room added to the gate's pool (copy a room of that pool); the tests check it like the others |
| Level 3 practice rooms | The retired Frame Builder and Code Lawyer rooms could return as practice |
| Question authoring for staff | Questions are still added by migration; the staff dashboard is read-only |
| Rosters and sections | Standings and statistics cover everyone who has signed in |
