# Developer guide

This guide describes the current Level 1 release. Run commands from the repository
root. See [deployment operations](../infra/README.md) for the hosted environment.

## Prerequisites

| Tool | Purpose |
| --- | --- |
| Git | Source control |
| Godot 4.7.2 and matching export templates | Scene editing and browser builds |
| Python 3.12 with venv | FastAPI server and tests; matches the production image |
| PostgreSQL 16, or Docker | Separate local database |
| Chrome and optional Python `playwright` package | Browser startup check |
| OpenShift `oc` CLI and namespace access | CloudApps operations only |

Opening `project.godot` imports the game. Its starting scene is `start_page.tscn`.
The editor project includes Godot MCP tooling, but no MCP client is required for
normal development. The web exporter removes those services from its staged copy.
It also uses Compatibility rendering without changing your editor project.

## Local server and database tests

Create a Python environment:

```bash
python3.12 -m venv build/venv
source build/venv/bin/activate
python -m pip install -r server/requirements.txt
```

The following database is for synthetic development data only. The example
password must never be used on CloudApps. Port 55433 avoids the default Postgres
port and the named volume preserves local data when the container stops.

```bash
docker run --name aa-dev-db \
  -e POSTGRES_USER=aa_dev \
  -e POSTGRES_PASSWORD=local-development-only \
  -e POSTGRES_DB=assembly_adventures_dev \
  -p 127.0.0.1:55433:5432 \
  -v aa-dev-data:/var/lib/postgresql/data \
  -d postgres:16

docker exec aa-dev-db pg_isready -U aa_dev -d assembly_adventures_dev
```

Wait until `pg_isready` reports that connections are accepted. On later sessions,
use `docker start aa-dev-db` instead of creating the container again. Use
`docker stop aa-dev-db` when finished; keep the volume if you want to keep data.

```bash
export DATABASE_URL='postgresql://aa_dev:local-development-only@127.0.0.1:55433/assembly_adventures_dev'
python -m server.database
export TEST_DATABASE_URL="$DATABASE_URL"
python -m unittest server.test_app server.test_gameplay -v
```

The runner applies the SQL files in filename order, including the two
bootstrap seeds. Repeating the command is safe: `public.aa_schema_migrations`
records filenames and checksums. `pgcrypto` and `citext` are required; the local
container's initial database user can create these extensions.

Authentication tests mock CSXL and need no database. Gameplay tests apply
migrations, create synthetic players, and clean them up. They cover grading,
resume, duplicate submissions, concurrent requests, ownership, early completion,
badges, and identity privacy. Always point `TEST_DATABASE_URL` at a disposable
local/test database, never the live database. If it is unset, gameplay tests
are **skipped**, not passed.

## What can run locally

There are three distinct development paths:

| Path | What it verifies | Limitation |
| --- | --- | --- |
| Godot editor, F5/F6 | Scenes, layout, animation | Native builds have no browser session; saved gameplay is unavailable |
| Export plus Chrome startup test | WebAssembly startup, welcome screen, asset loading | Static test server has no gameplay API or UNC login |
| Python tests with local PostgreSQL | Authentication contract and saved gameplay | CSXL is mocked; this does not prove real UNC SSO |

There is no development login endpoint or automatic `.env` loader. Export
variables in your shell. For an authenticated manual browser test, use an
approved HTTPS deployment and complete real CSXL login. The server protects
both the game files and `/api` routes; do not disable that protection to make
a local preview work.

The production server command is:

```bash
python -m uvicorn server.app:create_app --factory --host 0.0.0.0 --port 8080 --no-access-log --no-proxy-headers
```

This is a reference for how the container runs, not a complete local login setup:
it also needs the environment below, exported game files, a migrated database,
and HTTPS at the browser-facing origin. CloudApps terminates TLS at its Route.

## Environment variables

| Variable | Required by / meaning |
| --- | --- |
| `APP_ORIGIN` | Web server: full HTTPS origin, no path or trailing callback; e.g. `https://assembly-adventures-teddyt.apps.cloudapps.unc.edu` |
| `SESSION_SECRET` | Web server: random signing key of at least 32 characters; supplied through a CloudApps Secret |
| `STATIC_DIR` | Game files; defaults to `build/web`, set to `/app/static` in the image |
| `DATABASE_URL` | Local database connection; takes precedence over the individual DB variables |
| `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | Database connection when `DATABASE_URL` is absent; CloudApps uses these |
| `TEST_DATABASE_URL` | Integration tests only; explicitly selects their isolated database |
| `GODOT_BIN` | Optional exporter executable; `--godot` overrides it |

The migration command needs only database configuration. The server's factory
also needs `APP_ORIGIN`, `SESSION_SECRET`, and an existing static directory.
Never copy production session keys, CSXL tokens, or roster data into tests.

## Code map and request flow

| Location | Responsibility |
| --- | --- |
| `start_page.tscn`, `intro_animation.tscn` | Opening screens |
| `control_center.gd` | Loads saved profile and level availability; opens Level 1 |
| `player_data.gd` | Same-origin HTTP requests, profile cache, retry IDs, profile-change signal |
| `badges_container.gd` | Renders earned badges from the cached server profile |
| `levels/level_1/risc_v_level.gd` | Question controls, answer submission, resume, completion |
| `server/app.py` | CSXL callback verification, signed session, protected static files |
| `server/api.py` | Request validation, authenticated endpoints, POST origin/header checks |
| `server/gameplay.py` | Transactions, owned runs, attempt history, profile, badge awards |
| `server/grading.py` | Public question snapshots and private grading solutions |
| `server/database.py` | Connections and transactional migration ledger |
| `db/migrations/`, `db/seed/` | Schema evolution and one-time bootstrap |
| `infra/` | Exporter, container, OpenShift templates, deployment and backup scripts |

At login the server verifies the CSXL token, saves verified Onyen/PID, and sets
an eight-hour signed cookie containing Onyen and a session version, not PID or
the upstream token. CSXL prepends `https://` to its callback origin; therefore
the `/auth` query uses a **scheme-free host/path**, although `APP_ORIGIN` is a
full HTTPS origin. Login state is bound to the initiating browser for ten minutes.

The game loads `/api/me` and `/api/levels`, then starts or resumes `/api/runs`.
A new run freezes question text, shuffled opaque answer IDs, private solutions,
explanations, and points in `aa.run_questions`. The client submits IDs only.
The server grades and records each answer, and awards the badge transactionally
after all questions are correct. Profile data is reloaded after signing in;
the Godot cache is not durable storage. See the [API guide](gameplay-api.md).

## Making changes

### Game UI or assets

Edit source scenes and scripts, then export again. Do not edit generated
`build/web` files: the next export replaces them. The exporter copies selected
asset directories and root Godot files; when adding a new resource directory,
check `infra/export_web.py` so the release includes it. Keep solutions, SQL,
credentials, and the historical question bank out of the web export.

```bash
python infra/export_web.py --godot /path/to/godot \
  --template /path/to/web_nothreads_release.zip
python -m pip install playwright
python infra/browser_smoke.py
```

**Art, fonts, and audio.** The look is a flat-vector "neon circuit board":
palette, fonts, and drawing helpers live in `ui/style.gd`, and `GameTheme.tres` is
the project-wide theme, so new screens match without extra styling. Shared pieces
are in `ui/`: the circuit backdrop, the robot and Chip Chomper sprites
(`ui/characters.gd`, art in `assets/sprites/`), and the `Audio` autoload
(`ui/audio.gd`) for sound effects, music, and the sound switch. Fonts, sprites, and
sounds live in `assets/`. Record every third-party file in `assets/CREDITS.md` and
prefer CC0 or CC-BY licenses. Draw SVG art at twice its on-screen size so it stays
sharp when the game scales up. The background music is generated: edit and run
`tools/make_music.py` (needs `numpy` and `soundfile`) to change it.

Substitute your Godot executable and matching template paths. On macOS the
executable may be `/Applications/Godot.app/Contents/MacOS/Godot`. The template
must be `web_nothreads_release.zip`; the threaded `web_release.zip` can leave
Chrome stuck at a full loading bar. Inspect `build/import.log`, `build/export.log`,
and `build/browser-smoke.png`. The smoke test uses locally installed Chrome.

### Questions or schema

Add a new, uniquely numbered SQL migration after the existing files, for example
`db/migrations/0005_describe_change.sql`. Never edit applied files or regenerate
`0003_questions.sql`: checksum validation will reject them. Use the migration
runner for fresh databases as well as upgrades so both paths have the same ledger.

Prefer reviewed data migrations for question changes so local and deployed
content stay consistent. Retire substantive replacements and insert new rows;
keep historical attempts. Existing runs retain their snapshots, so only a new
run sees an edited question. There is no authoring/admin UI yet. The importer
is historical tooling; `--check` validates its original JSON without rewriting SQL.

Test the change against the previous local schema with an existing unfinished
run, as well as a fresh database when changing bootstrap behavior. Migration
failure rolls back the transaction and prevents the new app pod from starting.
Do not remove ledger rows to force changed SQL through.

### Enabling another level

Database activation alone is insufficient. Add the question content and badge,
implement and connect the scene from `control_center.gd`, and verify its question
types and completion rule. Only Level 1 is currently wired in the control center;
only `all_correct` is implemented by the server. Test resume, retries, completion,
and badge restoration before activating a level in production.

## Before handing off or deploying

1. Run relevant Python tests; use the isolated database for gameplay changes.
2. Re-export and run the Chrome startup check for game changes.
3. Review `git diff --check`, `git diff`, and `git status --short`; stage intended
   files explicitly, including Godot UID files associated with new scripts.
4. Follow [deployment operations](../infra/README.md). An application deployment
   uses the current `build/web` export; it does not export Godot for you.
5. Verify real UNC login, wrong-answer retry, resume after reload, all-correct
   completion, and the saved badge. Do not paste callback URLs or tokens into
   issues; report only the hostname and sanitized error text.

The current hosted namespace is `teddyt`. Changes to these docs do not redeploy
the app. Backups and namespace moves are separate operational work; see the
operations guide. Backups can contain Onyen/PID and need an approved,
access-controlled destination. There is no scheduled backup job in this repo.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `You must be logged in` from `oc` | Website login does not log in the CLI; run the console's copied login command locally |
| CloudApps API times out | Check required UNC network/VPN access before changing manifests |
| Browser callback starts `https://https//` | Keep CSXL's callback parameter scheme-free; keep `APP_ORIGIN` as HTTPS |
| Loading bar fills and stalls | Re-export with the matching non-threaded template; inspect Chrome Console without sharing tokens |
| Desktop says to open the hosted game | Expected: native Godot has no authenticated browser session |
| API returns 401 | Reload and sign in; older session versions are intentionally rejected |
| API returns 503 | Check database availability and migration logs; avoid logging identity-bearing exceptions |
| New questions do not appear in a resumed run | Expected: run snapshots are immutable; complete that run before starting another |
| Applied migration checksum changed | Restore the applied file and put the change in a new migration |
| Badge progress shows 100% after Level 1 | Only one badge is active; progress is based on active badges |
