# Deploy Assembly Adventures to UNC CloudApps

The current release serves the Godot game behind CSXL Onyen login,
using the same upstream `/auth` and `/verify` contract as LearnWithAI.
PostgreSQL stores the level 1 to 3 questions, attempts, and earned badges. Unfinished runs
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

The release is about 41 MB, nearly all of it the Godot engine (`index.wasm`).
The image build (`infra/Dockerfile`) saves gzipped copies of `index.wasm`,
`index.pck`, and `index.js`, about 11 MB together, and the app sends those to
browsers that accept gzip. Browsers keep the game's files (`private, no-cache`)
and check on each visit whether they changed, so a returning player downloads
almost nothing, and a new deployment reaches everyone right away. API responses
are never cached (`private, no-store`).
See [Godot's web export requirements](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

## OpenShift terminal setup

CloudApps runs Red Hat OpenShift, which you control with its command-line tool,
`oc`. Run it in a terminal on your own computer: the CloudApps console has no
built-in terminal, and `deploy.sh` needs this repository and `build/web`. Off
campus, connect to the UNC VPN if `oc` times out.

Install `oc` once, from the console so it matches the cluster (Homebrew's
`openshift-cli` can be newer than CloudApps supports):

1. Sign into the [CloudApps console](https://console.apps.cloudapps.unc.edu/)
   with your Onyen. Not `console.apps.unc.edu`, which is a different cluster.
2. Open the **?** menu at the top right and choose **Command Line Tools**.
3. Download **oc for Mac for ARM 64** (Apple silicon) or **oc for Mac for
   x86_64** (Intel), and unzip it. Windows and Linux builds are listed too.
4. Install the `oc` file. Red Hat does not notarize it, so clear its download
   flag or macOS refuses to run it:

   ```bash
   sudo mkdir -p /usr/local/bin
   sudo mv ~/Downloads/oc /usr/local/bin/oc
   xattr -d com.apple.quarantine /usr/local/bin/oc
   oc version --client
   ```

Log in the first time, and again whenever `oc` reports `You must be logged in
to the server`. Website login alone does not authenticate `oc`.

1. In the console, click your Onyen at the top right and choose **Copy login
   command**. Sign in again if asked, then choose **Display Token**.
2. Run the `oc login --token=… --server=https://api.cloudapps.unc.edu:6443`
   command shown there. The token works like a password until it expires;
   never commit or share it.
3. Select the project and check the account; `oc whoami` prints your Onyen:

   ```bash
   oc project teddyt
   oc whoami
   ```

## Deployment

Log into `oc` first ([OpenShift terminal setup](#openshift-terminal-setup)).
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
build/venv/bin/python -m unittest server.test_app server.test_puzzles server.test_call_stack -v
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
login flow, verify that the game loads, and play through levels 1 to 3. Automated
tests mock CSXL verification; they do not substitute for this real SSO check.

## Staff dashboard access

Staff Onyens live in the ConfigMap `assembly-adventures-staff`, key
`AA_STAFF_ONYENS`, as a comma-separated list. Deployments do not create it.
Each update replaces the whole list, so include everyone who should keep access:

```bash
oc create configmap assembly-adventures-staff -n teddyt \
  --from-literal=AA_STAFF_ONYENS="teddyt,kakiryan" \
  --dry-run=client -o yaml | oc apply -n teddyt -f -
oc rollout restart deployment/assembly-adventures -n teddyt
oc rollout status deployment/assembly-adventures -n teddyt
```

The restart is required; the app reads the list only at startup. Check the
current list with:

```bash
oc get configmap assembly-adventures-staff -n teddyt -o jsonpath='{.data.AA_STAFF_ONYENS}'; echo
```

The Deployment must reference the ConfigMap, which the current template does.
If `AA_STAFF_ONYENS` is missing from
`oc get deployment assembly-adventures -n teddyt -o jsonpath='{.spec.template.spec.containers[0].env[*].name}'`,
run `deploy.sh` first. See [classroom features](../Docs/classroom-features.md#staff-access)
for what staff can see.

### Clearing a nickname

Staff clear an inappropriate leaderboard nickname themselves: search the
dashboard's Students page for it, open the student, and choose **Clear
nickname**. An operator can do the same from a terminal, with the student's Onyen
in place of `ONYEN`:

```bash
echo "UPDATE aa.players SET nickname=NULL WHERE onyen='ONYEN';" |
  oc exec -i -n teddyt deployment/assembly-adventures-postgres -- \
  sh -c 'PGPASSWORD="$POSTGRESQL_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRESQL_USER" -d "$POSTGRESQL_DATABASE"'
```

`UPDATE 1` confirms it. Either way, the student appears as `Player <number>` again
and can choose a new nickname; no restart is needed.

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
