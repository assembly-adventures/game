# Saved gameplay API

All endpoints use the existing signed `__Host-aa-session` cookie and return JSON.
A fresh CSXL login provisions the player from verified Onyen/PID. PID and roles
are never accepted from gameplay requests or returned to the browser.

POST requests require `X-AA-Request: 1` and a matching Origin when supplied.
The server does not enable cross-origin access. Expired sessions receive 401;
the game asks the player to reload and sign in again.

| Endpoint | Behavior |
| --- | --- |
| `GET /api/me` | Onyen, active earned badges, badge total, and progress ratio |
| `GET /api/levels` | Availability, question counts, and completion flags |
| `POST /api/runs` | `{level_id: 1}` starts or resumes the player's active level 1 run |
| `POST /api/runs/{id}/attempts` | Records and grades an answer; requires question ID, request ID, response, and optional elapsed time |
| `POST /api/runs/{id}/finish` | Requires all questions correct; completes run and awards badge in one transaction |

Starting a run returns `id`, `level_id`, `outcome`, `questions`, and
`solved_question_ids`. The game skips solved questions when resuming. Each
question is an immutable snapshot with shuffled opaque option IDs. Solutions
stay in `aa.run_questions.solution`, which is never serialized by these routes.

Responses for each question type:

```json
{"selected_option_ids": ["opaque-option-id"]}
{"order": ["opaque-tile-id-1", "opaque-tile-id-2"]}
{"pairs": {"opaque-row-id": "opaque-choice-id"}}
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
| 409 | State conflict, incomplete run, or reused request ID with different content |
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
