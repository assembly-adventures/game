# Deploy Assembly Adventures to UNC CloudApps

The current release serves the Godot game behind CSXL Onyen login,
using the same upstream `/auth` and `/verify` contract as LearnWithAI.
PostgreSQL stores level 1 questions, attempts, and earned badges. Unfinished runs
resume after reload or login. Other levels remain inactive. Verified Onyen and PID
are stored for roster use; PID is never sent to the game or placed in its cookie.

For local setup and a code map, start with the [developer guide](../Docs/development.md).
Run these commands from the repository root.

## Browser release

Use Godot 4.7.2 with its matching export templates. On this Mac:

```bash
python3 infra/export_web.py --godot /Applications/Godot.app/Contents/MacOS/Godot
```

If templates are unpacked separately, add `--template /path/to/web_nothreads_release.zip`.
Use the single-threaded template: `web_release.zip` contains a threaded runtime
and will hang in browsers without cross-origin isolation, even when the export
preset has threads disabled.
Obtain the standard templates from the official
[Godot 4.7.2 release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)
and verify the archive against its published `SHA512-SUMS.txt`.

The exporter stages a clean copy under ignored `build/`, switches that copy to
Compatibility rendering, removes MCP editor/runtime services, and produces a
single-threaded release in `build/web/`. It does not modify the desktop project.
Database SQL and the reference question bank are not bundled in the release.
See [Godot's web export requirements](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

## Login and deployment

Sign into [CloudApps](https://console.apps.unc.edu/), choose **Copy login command**
from the user menu, and run that command in your local terminal. Website login
alone does not authenticate `oc`. Never commit or share the resulting token.

From the repository root, after exporting:

```bash
./infra/deploy.sh teddyt assembly-adventures-teddyt.apps.cloudapps.unc.edu
```

The script creates or reuses PostgreSQL with a 1 GiB persistent volume and
Secret-backed credentials, a persistent random session-signing Secret, a binary
BuildConfig, ImageStream, Deployment, Service, and TLS Route. It uploads only
the web release, server code, database SQL, and Dockerfile. Database SQL is
inside the server image only, outside the publicly served static directory. Subsequent runs preserve the
signing secret and build the latest exported game. Re-export after game edits.

An init container applies pending SQL transactionally before the app starts.
The migration ledger records each script and checksum; subsequent deployments
skip applied scripts and refuse changes to their contents. Bootstrap seeds run
only once. Add a new migration for future schema/data changes.

The Python server redirects unauthenticated visitors to CSXL and verifies the
callback token server-side. It uses a browser-bound, ten-minute login state and
passes CSXL a scheme-free callback host/path because CSXL adds `https://` itself.
`APP_ORIGIN` remains a full HTTPS origin. The app uses
an eight-hour Secure/HttpOnly cookie. All game assets require the session.
The public health endpoint contains no game or identity data. Access logging is
disabled to avoid recording callback tokens; responses prohibit caching and
referrer forwarding. PID stays in the database; no separate Shibboleth proxy is used.

CSXL must accept the deployed callback origin. Confirm this with a real UNC
login before considering launch complete. If it rejects the origin, coordinate
with the CSXL maintainers; do not bypass authentication to make the game load.

## Validation

```bash
python3 -m venv build/venv
build/venv/bin/pip install -r server/requirements.txt
build/venv/bin/python -m unittest server.test_app -v
# Use an isolated PostgreSQL database; tests create synthetic players.
TEST_DATABASE_URL=postgresql://... build/venv/bin/python -m unittest server.test_gameplay -v
bash -n infra/deploy.sh
oc process --local -f infra/app-template.yaml \
  -p NAMESPACE=teddyt -p APP_HOST=assembly-adventures-teddyt.apps.cloudapps.unc.edu
```

After changing the game export, also test it in Chrome (installed locally):

```bash
build/venv/bin/pip install playwright
build/venv/bin/python infra/browser_smoke.py
```

This starts a loopback-only static server and an isolated headless Chrome
session, checks that the loader clears without JavaScript exceptions, and saves
`build/browser-smoke.png` for visual inspection. It deliberately serves without
cross-origin isolation headers to catch accidentally threaded runtimes.

After deployment, check the rollout and open the site in a private browser:

```bash
oc rollout status deployment/assembly-adventures -n teddyt
curl -I https://assembly-adventures-teddyt.apps.cloudapps.unc.edu/
curl -I https://assembly-adventures-teddyt.apps.cloudapps.unc.edu/index.pck
```

Both unauthenticated requests should redirect to `/auth/login`. Follow the
login flow, verify that the game loads, and play through level 1. Automated
tests mock CSXL verification; they do not substitute for this real SSO check.

## Moving to another namespace

Run the same script with the new namespace and hostname. This creates an
independent session secret, so players will sign in again. Confirm CSXL accepts
the new callback origin before switching users over. Back up and restore PostgreSQL into the new namespace before cutover; running
the deployment script alone creates a new database and does not copy progress. Remove the old deployment only after validating
the new site and explicitly deciding to retire it.

## Database operations

The database Service is internal (`assembly-adventures-postgres:5432`), with no
public Route. The existing namespace network policies still apply; same-namespace
workloads may connect, but PostgreSQL always requires its generated credentials.
The app reads credentials through Secret references. Changing the Secret does
not rotate the password in an initialized database; coordinate both changes.

Before schema changes or moving namespaces, save a database backup:

```bash
mkdir -p build/backups
./infra/backup.sh teddyt build/backups/assembly-adventures.dump
```

Backups include roster identifiers and are created with owner-only permissions.
The helper refuses to overwrite an existing file. Only export roster data to an approved destination. No scheduled backup job is
configured in this repository. Keep durable backups somewhere
access-controlled outside the pod/PVC; persistent storage is not itself a backup.
Use `pg_restore` when planning a restore or namespace move, and verify the restore
in a separate database before replacing a live database.

Database deployment and schema logs:

```bash
oc get pvc,pods -n teddyt
oc logs deployment/assembly-adventures -c migrate -n teddyt
oc logs deployment/assembly-adventures-postgres -n teddyt
```

Desktop Godot launches do not contain UNC session cookies. Use the hosted web
build for authenticated gameplay. The standalone Chrome startup test checks the
welcome screen; database integration tests use a separate test PostgreSQL instance.
