# Database Schema

Assembly Adventures stores player progress and the question bank in PostgreSQL,
hosted on UNC cloud apps. This document explains the tables, why they are shaped
the way they are, and the rules the API tier has to follow.

- Initial DDL: [`db/migrations/0001_init.sql`](../db/migrations/0001_init.sql)
- Gameplay additions: [`db/migrations/0004_gameplay.sql`](../db/migrations/0004_gameplay.sql)
- Local setup: [developer guide](development.md)
- Seed data: [`db/seed/0002_levels_badges.sql`](../db/seed/0002_levels_badges.sql)
- One-time question bootstrap: [`db/seed/import_questions.py`](../db/seed/import_questions.py)

**The database is the source of truth for questions.** `questions.json` is a
temporary file that predates it and is kept only as reference context; the
importer exists to carry its 18 questions across once. After that bootstrap,
questions are authored in the database, and both `questions.json` and the
importer can be retired.

## Why this exists

Before this schema, the entire state model was `player_data.gd`: a single
in-memory `Array[String]` of earned badge names. Progress was lost on quit, the
question bank in `questions.json` was never loaded by any code, and the one
playable question was hardcoded in `levels/level_1/risc_v_level.gd`.

The schema exists to make three things possible:

1. Students log in with their Onyen and their progress follows them.
2. Questions are edited in the database, not shipped inside a game build.
3. Every answer is recorded, so we can see which questions students miss.

## Current implementation

The API and game implement levels 1 and 2, each with 10 puzzle gates, saved
attempts, resume, and badges. Other levels are inactive. CSXL verifies Onyen and
PID at login; no proxy identity headers are trusted. PID stays server-side.
See [gameplay-api.md](gameplay-api.md) for the implemented request contract.

Migration `0004_gameplay.sql` adds immutable `aa.run_questions` snapshots,
per-attempt request IDs, one active run per player/level, PID validation, and a
progress view that counts active badges consistently. Snapshot option IDs are
randomized so source IDs such as `t1`, `t2` cannot reveal answer order.

Apply migrations through `python -m server.database`, which tracks names and
checksums transactionally and never reapplies bootstrap seeds. The raw SQL
remains authoritative. Use the tracked runner on both empty and existing databases.

## Architecture

The game is a **Godot web export served from UNC CloudApps behind the
FastAPI server’s CSXL Onyen login and signed session cookie**. Because it runs in a browser tab, it can never hold database
credentials, so an API tier sits between the game and Postgres and is the only
thing that connects to the database.

```
Browser (Godot web export)  ──HTTPS──>  API tier  ──>  PostgreSQL (aa schema)
         │                                  ▲
         └── Secure session cookie ─────────┘
              (CSXL verifies identity at login)
```

The API tier is **FastAPI**. The raw SQL in `db/migrations/` remains the
authoritative DDL; the API reads and writes those tables rather than generating
its own schema.

Two rules are non-negotiable, because the browser is untrusted:

1. **Never send correct answers to the client.** `questions.json` ships answers
   inline, which was harmless when nothing was recorded. Now that answers are
   graded and badged, the endpoint that serves a question must strip
   `correct_option_ids`, `correct_order`, and each pair's `right` value.
2. **Grade and award server-side.** The client reports what the player did; the
   server decides whether it was right and whether a badge is earned.

## Tables

### `aa.players`

One row per authenticated UNC person, upserted from CSXL-verified attributes at
login. There is no password column — the app delegates Onyen login to CSXL.

| Column | Notes |
| --- | --- |
| `id` | `uuid`, the key used by every other table |
| `onyen` | `citext`, unique. Case-insensitive so lookups need no `LOWER()` |
| `pid` | 9-digit UNC person ID. **FERPA-sensitive** |
| `role` | `student` / `instructor` / `admin` — the classroom hook |

**Handling `pid`.** It is the only high-sensitivity column in the design. Never
return it from the API, never write it to logs, and `REVOKE` it from any
read-only reporting role. Everything downstream keys off `player_id` (the uuid),
so analytics queries never carry an identifier.

> PID is retained for the requested roster integration and never placed in the
> browser session cookie or returned by the gameplay API.

**Classrooms are deliberately not modelled.** `role` is the only hook. When an
instructor view is needed, it becomes `courses` and `enrollments` tables plus a
query — nothing already built has to change.

### `aa.levels`

| Column | Notes |
| --- | --- |
| `slug` | `level_1` … `level_challenge`, matching the question bank keys |
| `scene_path` | `res://levels/…`, replacing the hardcoded routing table |
| `completion_rule` | `jsonb` — what it takes to pass |
| `draw` | `jsonb`, optional — how a run picks its questions from the level's pools |
| `is_active` | `false` for levels that are still stubs |

`scene_path` is stored as metadata. The current client routes Levels 1 and 2
explicitly in `control_center.gd`; it does not dynamically load scenes from this
column.

The only implemented completion rule is `{"type": "all_correct"}`. Other rules
require server and client work before activation. Migration `0004_gameplay.sql`
left only Level 1 active, even though historical seeds contain additional
levels and questions; `0007` activates Level 2.

Without a `draw` rule, a run plays every active question in ordinal order. A
rule lists pools (`questions.pool`) in order. Each pool gives all its active
questions, or `take` of them chosen at random, kept in ordinal order. Level 2's
rule plays 10 of its 16 rooms: the four tutorial rooms, one memory, one
branches, and one loops room, both procedure rooms, and the race:

```json
[{"pool": "tutorial"}, {"pool": "memory", "take": 1}, {"pool": "branches", "take": 1},
 {"pool": "loops", "take": 1}, {"pool": "procedures"}, {"pool": "finale"}]
```

### `aa.badges`

Kept separate from `levels` rather than folded in as columns, for two reasons:

- Progress becomes `earned / count(active badges)`, which retires the hardcoded
  `/ 7` in `get_progress_ratio()`.
- An achievement that is not tied to a level (`level_id IS NULL`) needs no
  migration later.

`slug` deliberately matches the badge node names in `control_center.tscn`
(`badge_1` … `challenge_badge`), since that string is already the de-facto
progress key in the running game.

### `aa.questions`

One table for all four question types, with the type-specific parts in a
`payload jsonb` column. Shared columns cover `prompt`, `code_snippet`, `hint`,
`explanation`, `points`, `difficulty`, and `ordinal`. `pool` (added in `0007`)
names the group a level's draw rule picks from; it is null for levels without
one.

`code_snippet` exists because the source bank jams multi-line assembly into the
prompt with `\n`. Splitting it lets the UI monospace the code and leave the
prose alone.

**Every payload element carries a stable id.** This is the most important
change from `questions.json`, which grades by comparing *option text*. Text
comparison breaks on any copy-edit and makes "which wrong answer do students
pick" unanswerable.

```jsonc
// multiple_choice
{"multi_select": false,
 "options": [{"id": "o1", "text": "4"}, {"id": "o2", "text": "5"}],
 "correct_option_ids": ["o2"]}

// drag_and_drop
{"orientation": "vertical",
 "tiles": [{"id": "t2", "text": "loop:"}, {"id": "t1", "text": "addi x5, x0, 3"}],
 "correct_order": ["t1", "t2"]}

// matching — the bank's positional fixed[i] ↔ answer[i] made explicit
{"columns": ["Role", "Register"],
 "pairs": [{"id": "p1", "left": "Destination register", "right": "x7"}],
 "distractors": []}
```

```jsonc
// puzzle, Level 1 — each button is a fixed instruction; the player presses them in any order
{"kind": "moves", "width": 8, "display": "signed",
 "initial": {"x5": 0}, "goal": {"x5": -96},
 "buttons": [{"op": "addi", "rd": 5, "rs1": 5, "imm": 64},
             {"op": "addi", "rd": 5, "rs1": 5, "imm": 32}],
 "max_moves": 4, "par": 3}

// puzzle, Level 2 — a room of memory words the robot walks through, in row-major order
{"kind": "maze", "base": 16384,
 "map": ["S..D.E"],
 "values": {"0x4000": 5, "0x4004": 90, "0x4008": 100, "0x400c": 40, "0x4010": 11},
 "doors": {"0x400c": 8}, "hands": ["t2"], "registers": {"t2": 8},
 "arrays": [{"name": "arr", "at": "0x4000", "length": 5}],
 "goal": {},
 "max_moves": 8, "par": 6}

// puzzle, Level 2 — a short program with blanks to fill, run on every test
{"kind": "code",
 "code": [{"line": "slti t0, a0, 5"},
          {"blank": ["bne t0, x0, else", "beq t0, x0, else"]},
          {"line": "addi a1, a1, 3"},
          {"blank": ["j done", "addi x0, x0, 0", "j else"]},
          {"label": "else"}, {"line": "slli a1, a1, 1"}, {"label": "done"}],
 "names": {"a0": "x", "a1": "y"},
 "tests": [{"registers": {"a0": 3, "a1": 4}, "expect": {"registers": {"a1": 7}}},
           {"registers": {"a0": 7, "a1": 4}, "expect": {"registers": {"a1": 8}}}]}
```

Registers go by their ABI names (`a0`, `t1`, `sp`, `ra`; `x0` stays `x0`, as the
course writes it). The server also accepts x-names, which Level 1's payload keys
still use.

Puzzle goals are not secret: the whole payload is the public snapshot, and the
private `solution` is a copy that grading reads. `server/puzzles.py` replays the
pressed buttons on `width`-bit registers and checks every `goal` register, so
any winning order passes. `display` (`unsigned`, `signed` or `hex`) only changes
how the game shows values; goals may be negative. `par` is the fewest presses
that open the gate and earns full stars. The question's `hint` column is included
in run snapshots so the game can offer it. `server/test_puzzles.py`
brute-forces every gate to check that it opens within `max_moves` and that `par`
is the true minimum.

Maze rooms (`kind: "maze"`) are grids of 32-bit memory words in row-major
order: the word at row *r*, column *c* of `map` is at `base + 4*(r*width + c)`.
The map marks walls (`#`, protected memory), floor (`.`), the start (`S`), the
exit (`E`), doors (`D`, words that can be walked through only while they hold
their code in `doors`), and glass (`B`, words in reach that can't be stood on).
`values` (nonzero starting words), `doors`, and `goal.memory` are keyed by hex
address. `a0` is the robot's address. The player's actions are RISC-V lines: a
step (`addi a0, a0, ±4` or `±4*width`, one cell at a time), `lw`/`sw` with one
of the room's `hands` at any offset that lands on a word of the room (base +
offset, as a 12-bit offset would reach), and, in teaching rooms (`loop`), the
`loop:` label and the room's `repeat` branches, which jump back to it. `keys`
can add other instructions, and `registers` sets extra starting registers.
`arrays` (names for runs of words, like `arr[3]`) and `names` (nicknames for
registers, like `i`) only label the screen. In the race, `chomper` zeroes the first `words` words of its `row`,
one every `every` instructions from instruction `start`. A room is solved when
the robot ends on the exit (if there is one) and every `goal.registers` and
`goal.memory` value holds; `max_moves` and `par` count instructions, not the
label. A program that faults (walking into a wall, glass, a locked door, or out
of the room; loading or storing a wall or past the room; more than 200 executed
instructions) is graded wrong, and the game refuses such actions before they are
ever submitted. The rooms follow Lecture 4: they start at `0x4000` and reuse its
example array and sum loop.
The C a room translates is in `code_snippet`.

Code rooms (`kind: "code"`) are short programs with blank lines. `code` lists
the program in order: lines, `label`s, and `blank`s, each blank with the lines a
player can pick for it. Instructions are assembled from `0x100`, 4 bytes apart;
labels take the address of the next instruction. `data` blocks are laid out from
`data.base` (`0x2000`), each label naming its first word; `stack` gives `sp`'s
starting `top` (`0x7FF0`) and the number of `words` below it, which hold junk
(`0xDEADBEEF`) until something is saved there. `ra` starts at `0x400`, standing
for main's caller, so a program ends when it returns there or runs past its last
line. `registers` sets starting registers for every test (a data label's name
stands for its address), and each test adds its own `registers`. A test passes
when every `expect.registers` value and `expect.memory` word (named like
`arr[2]`, or `result` for a label's first word) holds, and, with
`expect.returned`, the program ended by returning to `0x400`. A jump to where
there is no code, a load or store outside the room's memory or off a word
boundary, or more than 500 executed instructions fails the test. `names` only
label the screen. `server/test_puzzles.py` checks that exactly one filling of
each room's blanks passes.

Level 1 is made entirely of puzzle gates (`0005_level1_puzzles.sql`); its
original 13 quiz questions are retired. Level 2, the Memory Maze
(`0007_level2_memory_maze.sql`), replaced the placeholder "Opcode" level.
`0008_abi_register_names.sql` rewrites the x-names in Level 1's prompts, hints,
and explanations to ABI names (`t0`, `t1`). Guest mode plays from copies in
`levels/level_1/guest_rooms.json` and `levels/level_2/guest_rooms.json` (Level
2's holds its whole bank and draw rule, and guest mode draws the same way),
which a gameplay test keeps in sync. Level
ideas are collected in [level-brainstorm.md](level-brainstorm.md).

Drag-and-drop tiles are **stored in a scrambled order** so the seed file does
not read as the solution top to bottom. The API must still shuffle per run —
storage order is not a shuffle.

A `CHECK` constraint validates the payload shape per type. It is written with
`->` rather than the `?&` operator on purpose: a bare `?` in DDL is treated as a
bind placeholder by several drivers, which makes the constraint painful to
re-emit from an ORM.

**Questions are retired, never hard-edited.** A substantive change inserts a new
row and sets `is_active = false, retired_at = now()` on the old one, so old
attempts still point at exactly what the student was shown. Typo fixes can be
edited in place. The unique index on `(level_id, ordinal)` is partial — it only
covers active rows, so a retired question does not block its replacement from
reusing the slot.

### `aa.level_runs`

One row per run through a level. A partial unique index permits only one
`in_progress` run per player/level. Starting again resumes that run; starting
after completion creates a new run. Wrong answers remain retryable and do not
end the run. `lives_remaining` and `hints_used` are reserved schema fields, not
implemented game mechanics in this release.

`questions_total` is captured at creation. Attempts record points once per
question. Finishing checks all snapshots were solved, computes `questions_correct`
and `score`, marks the run passed, and awards its badge.

### `aa.run_questions`

Added in migration `0004_gameplay.sql`. Each `(run_id, question_id)` stores an
immutable `public_question`, private `solution`, `explanation`, `points`, and
`ordinal`, the question's position in that run (1 to n): a drawn run skips part
of the bank, so it is not the bank's ordinal. Public options and matching
choices use fresh opaque IDs per run; source IDs and correct pair mappings are
not exposed. Editing the question bank does not alter an active run's text or
grading.

### `aa.question_attempts`

The full attempt log — one row per answer submitted, including retries within a
run (`attempt_no`). `response` mirrors the payload vocabulary, in ids:

```jsonc
{"selected_option_ids": ["opaque-option-id"]}          // multiple_choice
{"order": ["opaque-tile-id-2", "opaque-tile-id-1"]}            // drag_and_drop
{"pairs": {"opaque-row-id": "opaque-choice-id"}}      // matching
{"moves": [1, 0, 0]}                                  // puzzle, Level 1: buttons pressed, in order
{"program": ["loop:", "addi a0, a0, 4", "bne a0, a1, loop"]}  // puzzle, Level 2 maze room: the program, one line per action
{"blanks": ["beq t0, x0, else", "j done"]}           // puzzle, Level 2 code room: the line picked for each blank
```

`player_id` is redundant with `run_id → level_runs.player_id`. It is kept so
per-student analytics skips a join; the API sets it from the run, never from
client input.

`elapsed_ms` is measured client-side, so treat it as **advisory** — a browser
tab can be backgrounded, and browser timing is manipulable. It is a good signal
for "which question makes people hesitate" and a bad one for grading. The API
caps it at one hour before insert.

`request_id` is a client UUID with a unique `(run_id, request_id)` index. A retry
with the same question and answer returns the previous result; different content
under the same ID is rejected. Already-correct questions cannot earn more points.

`answered_at` defaults to `clock_timestamp()` (migration `0006_gate_setbacks.sql`)
rather than `now()`, so attempts sort in the order the server handled them under
the player lock. Setbacks rely on that ordering.

### `aa.run_setbacks`

Added in migration `0006_gate_setbacks.sql`. Three failed tries on a puzzle gate
reopen the gate before it; each row records one reopening (`question_id`) and
the failed attempt that caused it (`caused_by_attempt_id`, unique, so a retried
request finds its setback instead of adding another). Nothing is edited when a
gate reopens. `server/gameplay.py` replays attempts and setbacks in time order:
a question counts as solved only with a correct attempt after its latest
setback, and strikes are wrong attempts since the player last arrived at the
gate. Finishing a run requires every question to be solved in that sense.

### `aa.player_badges`

Composite primary key on `(player_id, badge_id)`, which makes re-awarding a
no-op. Awards are made by the server; `player_data.gd` only caches the profile
returned by the API.

## Views

| View | Purpose |
| --- | --- |
| `aa.player_progress` | `badges_earned`, `badges_total`, `progress_ratio` — replaces the `/ 7` denominator |
| `aa.question_stats` | Per question: attempts, distinct players, first-try correct rate, median time, hints used |

`question_stats` is where keeping a full attempt log pays off, and it answers
the instructor question without any instructor tables existing yet.

## Implemented API

All routes live under `/api` and require the signed session cookie. Player
registration happens in the verified CSXL login callback, not in `/api/me`.
See [the API contract](gameplay-api.md) for endpoint behavior, response formats,
request deduplication, and errors.

## Applying and evolving the schema

With the Python dependencies installed and database connection variables set:

```bash
python -m server.database
```

The runner applies migration and seed files in filename order under one
transaction and advisory lock. `public.aa_schema_migrations` records their
checksums. It skips applied files and rejects edits to them. `0001` needs the
`pgcrypto` and `citext` extensions; a managed database may require an administrator
to enable these first. See [local setup](development.md#local-server-and-database-tests).

Do not run `0003_questions.sql` manually or regenerate it for content updates:
it is a one-time bootstrap with deletion logic. Add new reviewed SQL migrations
for schema and question changes. Retire replaced questions instead of deleting
history. Keep applied scripts in version control so fresh installations and
existing deployments follow the same sequence.

There is no question-authoring UI or reporting endpoint yet. The database role
column does not itself grant instructor/admin API functionality.

## Known data issues in `questions.json`

The bootstrap importer fixes these automatically:

- The `"drap-and-drop"` key is misspelled in both `questions.json` and
  `questionBankDocs.md`. It maps to the `drag_and_drop` type.
- Two level 1 options have a stray trailing `]`
  (`"x6 is changed to 0]"`, `"…at address x5 + 12]"`). Both are distractors, so
  stripping them does not affect answer matching.
- `"loop: "` in a drag-and-drop answer has a trailing space, which is stripped.

These need **manual attention** and are reported as warnings by the importer:

- **Four questions have code interleaved with prose**, e.g. `"Suppose x5 and x6
  both contain 7.\nbne x5, x6, different\nWhat happens?"`. The importer leaves
  these in `prompt` with `code_snippet` NULL rather than guessing a split that
  would reorder the question. Splitting them properly needs a second prose field
  (something like `prompt_after_code`) or an edit to the question text.

Resolved in the current implementation:

- The first Level 1 question now has `addi x5, x0, 12` in `code_snippet`, added
  by `0004_gameplay.sql`. The historical JSON still lacks that instruction.
- Level 1 no longer uses its old hardcoded question; it renders API snapshots.
