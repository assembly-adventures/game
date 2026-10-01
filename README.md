# Assembly Adventures

A Godot game for learning computer architecture, hosted on UNC CloudApps with
CSXL Onyen login and PostgreSQL-backed progress.

The current release includes Level 1's 13 questions. Players can retry answers,
resume unfinished runs, and earn a saved badge after answering every question
correctly. Other levels are inactive. Verified Onyen and PID are retained for
roster use; PID stays out of game responses and session cookies. Grading and
badge awards happen on the server.

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
requires the web build and authenticated API.

Follow the [developer guide](Docs/development.md) for a runnable local database
setup, tests, environment variables, code map, and contribution workflow.

## Documentation

| Guide | Use it for |
| --- | --- |
| [Developer onboarding](Docs/development.md) | Local setup, architecture, testing, and common changes |
| [Deployment and operations](infra/README.md) | Exporting, CloudApps login, migrations, backups, and namespace moves |
| [Gameplay API](Docs/gameplay-api.md) | Authentication, answer formats, retries, and error responses |
| [Database schema](Docs/schema.md) | Tables, snapshots, question authoring, and migration rules |
| [Legacy question bank](Docs/questionBankDocs.md) | Understanding the original `questions.json` import format |

The database is the runtime question source. `questions.json` is historical
bootstrap input, not the game's content feed. Apply database changes with
`python -m server.database`; never rerun seeds manually on an existing database
or edit migration files that have already been deployed.

Before submitting changes, run the checks relevant to your work in the developer
guide and review `git diff`. Keep credentials, roster data, database dumps,
`.godot/`, and generated `build/` output out of commits.
