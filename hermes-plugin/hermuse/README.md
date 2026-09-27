# Hermuse plugin for Hermes

Product layer on top of Hermes Agent: **Feed, Ideas, Goals, Library**
(artifacts + system files), **Reflections**, and **proactive preferences**.
Data lives as human-readable Markdown + JSON under `HERMES_HOME/hermuse/` so
the user can read and edit it with any tool.

Requires Hermes `>=0.21,<0.22` (see `requires_hermes` in `plugin.yaml`).

## Layout

```text
hermes-plugin/hermuse/
├── plugin.yaml            # agent-plugin manifest (kind: standalone, provides_tools)
├── __init__.py            # register(ctx): 6 tools + skill + `hermes hermuse` CLI
├── store.py               # stdlib-only file store (shared by tools + dashboard backend)
├── agent_tools.py         # feed_post / idea_propose / goal_track / goal_update /
│                          #   artifact_save / reflection_write (toolset "hermuse")
├── cron_specs.py          # feed/ideas/goals/reflection job specs + idempotent registration
├── plugin_cli.py          # `hermes hermuse status|enable|disable|doctor`
├── skills/hermuse/SKILL.md  # skill `hermuse:hermuse`: when to call each tool
├── dashboard/
│   ├── manifest.json      # dashboard manifest (hidden tab, api: plugin_api.py)
│   ├── plugin_api.py      # FastAPI router mounted at /api/plugins/hermuse/
│   └── index.js           # stub bundle (API-only plugin; UI served by Hermuse app)
└── tests/                 # pytest suite (see below)
```

## Install

```bash
# 1. Copy the plugin into the user plugins dir (tests/ is inert, may be excluded).
cp -r hermes-plugin/hermuse ~/.hermes/plugins/hermuse

# 2. Enable it (opt-in: agent tools, dashboard backend and CLI all gate on this).
hermes plugins enable hermuse

# 3. Register the background jobs (daily feed, weekly ideas, weekly goals
#    check-in, nightly reflection). Re-running only refreshes the specs; a
#    paused job stays paused.
hermes hermuse enable

# 4. Verify.
hermes hermuse doctor
hermes hermuse status
```

Restart the gateway/dashboard after enabling so the new routes load.
Uninstall: `hermes hermuse disable && hermes plugins disable hermuse`, then
delete `~/.hermes/plugins/hermuse` (your data under `~/.hermes/hermuse/` is
left untouched).

## Agent tools (toolset `hermuse`)

| Tool | Params |
| --- | --- |
| `feed_post` | `title`, `body` (Markdown), `topic?`, `sources?[]` |
| `idea_propose` | `title`, `pitch` (Markdown), `group`, `first_step?` |
| `goal_track` | `title`, `category` (`health`\|`relationships`\|`finance`\|`career`\|`interests`\|`productivity`\|`something_else`), `why`, `target_date?` |
| `goal_update` | `goal_id`, `note`, `progress?` |
| `artifact_save` | `title`, `kind` (`document`\|`web`\|`image`\|`video`\|`podcast`\|`other`), exactly one of `content`/`path`, `filename?`, `tags?[]` |
| `reflection_write` | `date` (`YYYY-MM-DD`), `body` (Markdown) |

Results are `{"ok": true, "id": …}` (or `{"date": …}`); failures are
`{"error": …}`. The skill `hermuse:hermuse` tells the agent when to call each
tool and to honour `PREFERENCES.md` before anything proactive.

## REST reference (auth: Hermes' existing `/api/` gate)

Base: `/api/plugins/hermuse/`. All auth behaviour (session token header
`X-Hermes-Session-Token`, enabled-plugin gating) is enforced by Hermes core;
this router adds none of its own.

| Method | Path | Body → Result |
| --- | --- | --- |
| `GET` | `/feed?limit=` | → `{"posts": […]}` (newest first) |
| `POST` | `/feed` | `{title, body, topic?, sources?[]}` → post (`201`) |
| `GET` | `/feed/{id}` | → post / `404` |
| `POST` | `/feed/{id}/react` | `{reaction: love\|discuss}` → post (toggles) |
| `GET` | `/ideas?limit=` | → `{"ideas": […]}` |
| `POST` | `/ideas` | `{title, pitch, group, first_step?}` → idea (`201`) |
| `GET` | `/ideas/{id}` | → idea / `404` |
| `POST` | `/ideas/{id}/feedback` | `{feedback}` → idea (appends) |
| `GET` | `/goals?limit=` | → `{"goals": […]}` |
| `POST` | `/goals` | `{title, category, why, target_date?}` → goal (`201`) |
| `GET` | `/goals/{id}` | → goal / `404` |
| `POST` | `/goals/{id}/update` | `{note, progress?, status? (tracking\|done)}` → goal |
| `GET` | `/artifacts?limit=` | → `{"artifacts": […]}` |
| `GET` | `/artifacts/{id}` | → artifact / `404` |
| `GET` | `/artifacts/{id}/download` | → file bytes |
| `GET` | `/reflections?limit=` | → `{"reflections": […]}` |
| `GET` | `/reflections/{YYYY-MM-DD}` | → reflection / `404` |
| `GET` / `PUT` | `/preferences` | raw `PREFERENCES.md` (`{name, content}` / `{content}`) |
| `GET` | `/files` | → `{"files": ["FEED_PROMPT.md", …]}` |
| `GET` / `PUT` | `/files/{name}` | allow-listed system file (`{name, content}` / `{content}`); anything else → `404` (traversal impossible: exact allow-list match, no path joining) |
| `GET` | `/cron` | → `{"jobs": [{key, name, schedule, registered, job_id, enabled, next_run_at}]}` |
| `POST` | `/cron/enable` | register/refresh the 4 jobs → `{"jobs": […]}` |
| `POST` | `/cron/disable` | remove the 4 jobs → `{"removed": […]}` |

Shapes:

- post: `{id, title, topic, body, sources[], file, created_at, reactions: {love?: ts, discuss?: ts}}`
- idea: `{id, title, pitch, group, first_step, file, created_at, feedback: [{at, text}]}` — click an idea to start the task in chat; `feedback` is the "Idea feedback" affordance.
- goal: `{id, title, category, why, target_date, status, file, created_at, timeline: [{at, note, progress}]}` — `status` is `tracking` or `done` (the Tracking checkbox).
- artifact: `{id, title, kind, file, size, tags[], created_at}`
- reflection: `{date, file, written_at, body}`

Validation errors are `422` (pydantic), unknown ids/names are `404`.

## File layout under `HERMES_HOME/hermuse/`

```text
hermuse/
├── FEED_PROMPT.md            # editable feed brief (defaults created on first use)
├── PREFERENCES.md            # Tell me about / Never tell me about / When / How
├── IDENTITY.md               # Name / Character / Vibe / Emoji
├── HEARTBEAT.md              # recurring-check checklist (never results)
├── feed/<date>-<slug>-<id>.md   # front-matter + Markdown body
├── feed/index.json           # posts incl. reactions {love, discuss}
├── ideas/<id>.md  +  index.json
├── goals/<id>.md  +  index.json  # .md carries the appended timeline too
├── artifacts/files/<id>/<file>  +  index.json
└── reflections/<date>.md  +  index.json
```

Managed root files are created with sensible defaults on first load and never
overwritten afterwards (`ensure_defaults` only backfills missing files).
Writes are atomic (temp file + fsync + rename); ids are 12-hex random.

## Cron jobs

Four specs in `cron_specs.py`, authored through the real `cron.jobs` API
(same records the scheduler reads):

| Key | Schedule | What |
| --- | --- | --- |
| `feed` | `0 8 * * *` | daily feed edition from `FEED_PROMPT.md` + web/news |
| `ideas` | `0 9 * * 1` | weekly ideas refresh |
| `goals` | `0 9 * * 0` | weekly goal check-ins + `HEARTBEAT.md` watches |
| `reflection` | `0 2 * * *` | nightly reflection journal + memory pass |

Jobs run the `hermuse:hermuse` skill, deliver `local` (surfaces render from
the files), and are tagged `origin: {source: hermuse, key}` so registration
is idempotent. Installing the plugin never starts background work on its own;
registration is always an explicit `hermes hermuse enable` (or
`POST /cron/enable`).

## Tests

```bash
cd hermes-plugin/hermuse
~/.hermes/hermes-agent/venv/bin/python -m pytest tests/ -q
```

38 tests: store writes/round-trips, idempotent defaults that never clobber
edits, REST routes + `files/` traversal rejection, real-backend cron
registration idempotence, and entry-point wiring (tools + skill + CLI).
