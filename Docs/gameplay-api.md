# Saved gameplay API

All endpoints use the existing signed `__Host-aa-session` cookie and return JSON.
A fresh CSXL login provisions the player from verified Onyen/PID. PID and roles
are never accepted from gameplay requests or returned to the browser.

POST requests require `X-AA-Request: 1` and a matching Origin when supplied.
The server does not enable cross-origin access. Expired sessions receive 401;
the game asks the player to reload and sign in again.

| Endpoint | Behavior |
| --- | --- |
| `GET /api/me` | Onyen, active earned badges, progress, `is_staff`, `leaderboard_visible`, `nickname` (null until chosen), and `leaderboard_name` (the nickname, or `Player <number>`) |
| `GET /api/levels` | Availability, question counts, and completion flags |
| `POST /api/runs` | `{level_id: 1, telemetry_version: 1}` starts or resumes a run; omitting the telemetry version creates a legacy, unranked run |
| `POST /api/runs/{id}/attempts` | Records and grades an answer; requires question ID, request ID, response, and optional elapsed time |
| `POST /api/runs/{id}/finish` | Requires all questions correct; completes run and awards badge in one transaction |
| `POST /api/runs/{id}/events` | Saves an idempotent hint or walkthrough-choice event; mistakes do not cause strikes |
| `GET /api/leaderboard?level_id=1&week_offset=0` | Best completed run per visible player in an Eastern calendar week, each under its leaderboard `name`, never an Onyen; offsets from -104 through 0 |
| `POST /api/preferences` | `{leaderboard_visible: false}` hides the signed-in player's public current/historical entries |
| `POST /api/nickname` | `{nickname: "Bit Wizard"}` sets the signed-in player's nickname, and `""` clears it; returns `nickname` and `leaderboard_name`. A taken nickname returns 409 and an invalid one 422 (rules in [classroom features](classroom-features.md#nicknames)) |

Staff-only reads: `/api/admin/overview`, `/api/admin/levels/{id}`,
`/api/admin/questions/{uuid}`, `/api/admin/students?q=onyen&limit=50&offset=0`,
and `/api/admin/students/{uuid}`. The one staff change is
`POST /api/admin/students/{uuid}/clear-nickname`, which clears that student's
nickname and returns their `nickname` (null) and `leaderboard_name`; like every
POST, it needs `X-AA-Request: 1`. Both the browser page at `/admin` and these
endpoints require a signed session and `AA_STAFF_ONYENS` authorization. They never
return PID. See [classroom features](classroom-features.md) for metric definitions.

An event has `question_id`, `request_id`, and `kind`. Hint events use
`{"kind":"hint"}`; walkthrough events use
`{"kind":"walk_choice","moment":0,"choice":1}` with indexes into the frozen
question. The server validates and determines correctness. Retry the same event
with the same request ID; changing its payload returns 409. Events on another
player's run return 404. New events on finished runs or solved gates return 409.
Question statistics contain `mistakes`, `hint_used`, and `stars` (null until solved).
Runs return these keyed by question ID in `question_stats`, plus
`leaderboard_eligible`; attempts return the affected question's statistics and
stars. Finish returns total `stars`, `mistakes`, `max_stars`, and eligibility.

Starting a run returns `id`, `level_id`, `outcome`, `questions`,
`solved_question_ids`, and `strikes` (failed tries so far on unsolved puzzle
gates, keyed by question ID). The game skips solved questions when resuming. Each
question is an immutable snapshot with shuffled opaque option IDs. Solutions
stay in `aa.run_questions.solution`, which is never serialized by these routes.
A level with a draw rule (Levels 1 to 3) draws its questions from a bank when a run
starts. The run keeps that draw, in order, until it finishes, so resuming shows
the same rooms; the next run draws again.

Responses for each question type:

```json
{"selected_option_ids": ["opaque-option-id"]}
{"order": ["opaque-tile-id-1", "opaque-tile-id-2"]}
{"pairs": {"opaque-row-id": "opaque-choice-id"}}
```

Puzzle gates (`type: "puzzle"`) send the indexes of the instruction buttons the
player pressed, in order:

```json
{"moves": [2, 0]}
```

A gate's goal is public, since the player needs it to play. The server replays
the presses (`server/puzzles.py`), so any winning order passes. The game submits
by itself when the register matches the goal, and also when the player uses
every move without matching, which records a wrong attempt. Anything other than
1 to `max_moves` valid button indexes returns 422.

Level 2's maze rooms send the program the player wrote, one RISC-V line per
action, exactly as the game shows it. Registers use their ABI names (`a0`,
`t0`); the server also accepts x-names (`x10`, `x5`):

```json
{"program": ["loop:", "lw t0, 0(a0)", "sw t0, 28(a0)", "addi a0, a0, 4", "blt a0, a1, loop"]}
```

Every line must be one the room offers (a step to a neighbouring cell, a load
or store with one of its registers at an offset that lands in the room, or one
of its keys). The `loop:` label is a line but not
an instruction, so a program may hold `max_moves` instructions plus one label.
Any other line, more than one label, or a branch above the label returns 422. A
program that would fault (walking into a wall or a locked door, or a loop that
never ends) is graded as a wrong attempt; the game refuses those actions
itself, so it never sends one. Attempts keep the program, so instructors can
read what students wrote.

Level 2's code rooms send the line picked for each blank, in program order:

```json
{"blanks": ["slli t3, t2, 2", "lw t5, 4(t3)"]}
```

Each line must be one of that blank's choices, and every blank needs one;
anything else returns 422. The server runs the program on each of the room's
tests, and it is correct only if every test passes. A program that crashes (a
jump to where there is no code, a load or store outside the room's memory or
off a word boundary, or a loop that never ends) fails that test. Each run the
player starts is one attempt, so a wrong run is a strike.

Level 3's walkthroughs (graded in `server/call_stack.py`) send the option picked
at each of the room's moments, in code order:

```json
{"choices": [0]}
```

The server writes the picked moves into the program and runs every one of the
Chip Chomper's calls, which must return the expected value with `s0`-`s11` and
`sp` as the Chomper set them. A wrong set of moves is a miss like any other, but
the game records it as a `walk_choice` event instead of an answer: it plays a wrong move out and rewinds, so
students see what breaks without a strike. Anything that isn't one valid option
per moment returns 422.

Attempts on puzzle gates also return `strikes` and `setback_question_id`. A
wrong attempt is a strike, counted since the player arrived at the gate (when
the gate before it was solved, or when a setback sent them back to it). The
third strike is a setback: the gate before reopens and appears again in the
next run view, and `setback_question_id` names it. A first gate, with nothing
before it, restarts instead and names itself. A reopened gate is graded again,
but it earns its points only once.

```json
{"is_correct": false, "explanation": "…", "strikes": 3, "setback_question_id": "question-uuid"}
```

The same vocabulary is used for multi-select, ordering, and matching controls.
Matching presents separate rows and shuffled choices; it never sends the
original left/right pair mapping. Ordering uses up/down controls in this release.

`request_id` is a client-generated UUID. Retrying an uncertain request with the
same ID and answer returns the original result without adding an attempt or
points. Reusing it with a different answer returns 409. Player-row and run-row
locks serialize concurrent mutations; finishing and re-awarding are idempotent.
Client scores, correctness, player IDs, and badges are not accepted.

An incorrect answer is recorded and can be retried. Each question earns its
points at most once. The current rule is `all_correct`; other completion rules
are rejected until implemented. Finishing early returns 409 and leaves the run
open. Elapsed time is advisory and capped at one hour per answer.

Questions may be edited or retired for future runs without altering active or
historical runs. `db/seed/0003_questions.sql` is bootstrap data, not an update
script. The migration ledger prevents accidental reseeding on deployments.

## Attempt request example

Send this JSON to `POST /api/runs/{id}/attempts`, with the session cookie and
`X-AA-Request: 1`. Use IDs from the current run, not these placeholders:

```json
{
  "question_id": "00000000-0000-0000-0000-000000000001",
  "request_id": "00000000-0000-0000-0000-000000000002",
  "response": {"selected_option_ids": ["opaque-option-id"]},
  "elapsed_ms": 12000
}
```

A valid graded answer returns `is_correct` and `explanation`. An incorrect
answer still returns HTTP 200; it is a recorded attempt, not a transport error.
The finish response includes `passed`, badges, and progress. See
[developer setup](development.md) for integration tests and synthetic identities.

## Error handling

| Status | Meaning / client action |
| --- | --- |
| 401 | Missing, expired, or old session; reload and sign in |
| 403 | POST header/origin check failed; submit from the game origin |
| 404 | Unavailable level, unowned run, or question outside the run |
| 409 | State conflict, incomplete run, taken nickname, or reused request ID with different content |
| 422 | Invalid request or answer selection; allow the player to correct it |
| 429 | Per-question limit of 1,000 recorded attempts reached |
| 503 | Database/upstream failure or unsupported configuration; show the error and allow retry |

After a timeout or uncertain server error, retry with the **same request ID and
same answer** so a committed attempt is not counted twice. After editing an
answer, use a new request ID. The Godot client retains an uncertain submission
and locks its choices until retry resolves it.

Responses use private/no-store caching. The server does not expose Swagger or
OpenAPI routes. `/healthz` is public and returns `ok`; it is a process health
check, not a database connectivity check.
