# Staff statistics, settings, and weekly standings

The Control Center has adjacent trophy and settings buttons in its top-right
corner. The trophy opens the leaderboard; the gear opens settings over the current
screen. Every playable level also has the gear. F10 opens settings anywhere,
Escape closes them, and F11 toggles fullscreen. Settings pause the scene and
restore its previous pause state when closed.

## Settings and visibility

Mute, music volume, sound-effect volume, and hiding the leaderboard on this device
persist in Godot's `user://` storage. Fullscreen requires a user gesture.
The nickname and **Show me on the leaderboard** are account preferences; the
toggle is on by default. Turning it off removes public entries from current and
historical standings while preserving learning progress and staff statistics.
The player can still see their own hidden result. Guest play has audio/display
settings but no nickname or saved rankings.

## Nicknames

The leaderboard never shows Onyens. Each entry shows the player's nickname, or
`Player <number>` until they choose one. Players set a nickname in Settings; saving
a blank one goes back to their number. The server tidies spacing and accepts a
nickname only if it:

- is 3 to 20 letters, numbers, spaces, hyphens, or underscores;
- is not another player's nickname, ignoring case, or another player's Onyen, so
  nobody can pose as a classmate;
- does not look like `Player 12`, which is reserved for players without a nickname.

Without a roster, only the Onyens of players who have signed in can be checked.
So when someone signs in for the first time, any nickname matching their Onyen is
cleared, and whoever took it goes back to their number.

A player's number is assigned once, at their first sign-in; migration
`0014_leaderboard_nicknames.sql` numbered existing players. Past weeks show
players' current names. Staff see each student's leaderboard name beside their
Onyen and can search by either. To remove an inappropriate nickname, open the
student's page and choose **Clear nickname**; the student goes back to their
number and can choose again.

## Weekly leaderboard

All signed-in players form one group, with separate tabs for Levels 1–3. There is
no roster or section membership. Normal question draws remain random, so run
difficulty can vary. Competition has no effect on badges or level availability.

Weeks run Monday 00:00 to the following Monday 00:00 in `America/New_York`,
including daylight-saving changes. Runs count in the week they finish. Standings
are calculated from saved runs: no reset job or deletion is needed. The screen
refreshes on opening, on demand, and every minute, and offers previous weeks.

Each player's best completed run per level is selected by **highest stars, then
fewest mistakes in that same run**. Equal results share a rank; replay scores are
never summed. Stars follow existing room rules: at most three per gate, with
deductions for hints, exceeding instruction/frame par, or mistakes in code/tower
rooms. A mistake means a failed submitted answer or wrong walkthrough decision.
Undo, free planning, and unsubmitted maze actions are not mistakes. Hints and
mistakes survive reloads and setbacks within the run.

Migration `0013_reporting_leaderboard.sql` preserves existing runs with
`scoring_version=0`. Only clients starting a new run with `telemetry_version: 1`
produce eligible runs. Older clients and resumed legacy runs still save progress
and badges. Finishing an older run allows a fresh run to enter the board.

The game queues idempotent hint/walkthrough events on the device until the server
acknowledges them and flushes them before an answer or leaving a level. The server
validates each event against the owned run's frozen question and computes stars;
it accepts no client star/mistake totals. This telemetry is not proof of
interactions that a modified client fails to report.

## Staff access

`/admin` and every `/api/admin/*` route require the normal UNC session and an
Onyen in the comma-separated `AA_STAFF_ONYENS` environment variable. Matching is
case-insensitive and ignores surrounding spaces. An empty/missing list grants
nobody access. TAs and professors have identical access: everything is read-only
except clearing a student's nickname. The database's existing `role` field is not
an alternative authorization path.

Authorized users see a **Staff dashboard** link in the Control Center. The server
checks access independently of that link. Staff see all signed-in players,
including hidden leaderboard participants, but never PID. There are no roster,
question-authoring, or staff-management forms.

CloudApps reads the optional ConfigMap `assembly-adventures-staff`, key
`AA_STAFF_ONYENS`. An operator sets that key to approved staff Onyens and restarts
the application pods to load it; the exact commands are in
[deployment operations](../infra/README.md#staff-dashboard-access). `infra/deploy.sh` packages `server/admin.html` with the server modules.

## Reading statistics

- Overview shows sign-ins, completed runs, attempts, and completion among starters.
- Level details show question participation, first-encounter and eventual success,
  median attempts to first solve, and recorded mistakes.
- Question details show the question's code, the most common answers marked
  correct or incorrect, and individual progress.
- The student directory, searchable by Onyen or leaderboard name, opens run
  progress and recent answer history.

Answers appear as students saw them: option text, Level 1 instructions, Level 2
program lines, or Level 3 moves (`Move 2: …`). Recorded option IDs are random in
every run, so the server reads each answer through its run's snapshot and counts
identical answers together across runs. Answers it cannot read, such as those
from retired rooms, appear as recorded JSON.

First-encounter success uses each player's earliest recorded attempt per question,
not the first attempt in every replay. A level's sample size counts student–question
pairs; a question's counts students. Eventual success means solved at least once.
Median attempts includes only students who solved the question. Wrong Level 3
decisions count as mistakes without gameplay strikes. Legacy Level 3 encounters
without decision tracking are excluded from first-encounter measurements.

Question rates use students who attempted that question, and unattempted questions
have no rate. Without a roster, enrolled students who never signed in are unknown.
Timing is not used for ranking or presented as active learning time. Common
answers are limited to 25 groups, question student lists to 200 entries, and
student history to 100 runs/200 recent attempts, with totals/truncation indicators.
The student directory is paginated.

Run `server.test_reporting` and `server.test_admin_page` alongside the normal
backend suite with an isolated `TEST_DATABASE_URL`. They cover authorization,
privacy, nicknames, retries, setbacks, best-run selection, ties, weekly/DST
boundaries, legacy exclusion, and analytics denominators. See `development.md` for export
and browser checks.
