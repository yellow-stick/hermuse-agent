# Hermuse plugin for Hermes

Product layer on top of Hermes Agent: **Feed, Ideas, Goals, Library**
(artifacts + system files), **Reflections**, **proactive preferences**, and the
agent's **computer** (a Docker browser + desktop the user can watch and take
over from Hermuse). Data lives as human-readable Markdown + JSON under
`HERMES_HOME/hermuse/` so the user can read and edit it with any tool.

Requires Hermes `>=0.21.5,<0.22` (see `requires_hermes` in `plugin.yaml`).

## Layout

```text
hermes-plugin/hermuse/
├── plugin.yaml            # agent-plugin manifest (kind: standalone, provides_tools,
│                          #   provides_hooks, provides_browser_providers)
├── __init__.py            # register(ctx): 6 tools + skill + `hermes hermuse` CLI +
│                          #   `hermuse` browser provider + computer hooks + restart of
│                          #   a set-up subscription bridge + live mount of the
│                          #   dashboard routes (no restart after install)
├── store.py               # stdlib-only file store (shared by tools + dashboard backend)
├── subscription_bridge.py # pinned CLIProxyAPI next to Hermes (see "Subscription bridge")
├── dashboard_restart.py   # in-place restart of the dashboard (see "Restarting the dashboard")
├── agent_tools.py         # feed_post / idea_propose / goal_track / goal_update /
│                          #   artifact_save / reflection_write (toolset "hermuse")
├── cron_specs.py          # feed/ideas/goals/reflection job specs + idempotent registration
├── plugin_cli.py          # `hermes hermuse status|enable|disable|doctor|computer`
├── skills/hermuse/SKILL.md  # skill `hermuse:hermuse`: when to call each tool
├── computer/              # the agent's computer (see "The agent's computer")
│   ├── runtime.py         # ComputerRuntime seam + DockerComputerRuntime
│   ├── bootstrap.py       # detached Docker install + image pull (or local build)
│   ├── state.py           # stdlib-only state files + Take control lease + lifecycle lock
│   ├── provider.py        # `hermuse` BrowserProvider (CDP URL of the computer's Chromium)
│   ├── hooks.py           # pre_tool_call gate/readiness guard, transform_tool_result snapshots
│   ├── setup.py           # Hermes browser config + starts the bootstrap
│   └── image/             # Dockerfile, entrypoint.sh, cdp_relay.py (CDP 9222→9223),
│                          #   screend.py (JPEG stream + input); published to GHCR by
│                          #   .github/workflows/computer-image.yml
├── dashboard/
│   ├── manifest.json      # dashboard manifest (hidden tab, api: plugin_api.py)
│   ├── plugin_api.py      # FastAPI router mounted at /api/plugins/hermuse/
│   └── index.js           # stub bundle (API-only plugin; UI served by Hermuse app)
└── tests/                 # pytest suite (see below)
```

## Install

### One click from Hermuse (Hermes on a server)

The Hermuse app installs the plugin into a running Hermes dashboard through
Hermes' own plugin API (session token or dashboard login), with no shell on
the server:

1. `POST /api/dashboard/agent-plugins/install`
   `{"identifier": "yellow-stick/hermuse-agent/hermes-plugin/hermuse", "enable": true, "force": false}`.
   Hermes' install scan rates the plugin **caution** because it can install
   Docker with `sudo` (see "The agent's computer"), so this first call answers
   `400` with a `detail` mentioning `caution verdict`; after the user confirms,
   the app repeats it with `"force": true` (which also replaces an existing
   install). A `detail` containing `already exists` means it is installed:
   `POST /api/dashboard/agent-plugins/hermuse/enable` instead.
2. Enabling loads the plugin into the dashboard process, and `register(ctx)`
   mounts `/api/plugins/hermuse/*` there at once (Hermes itself only mounts
   plugin backends when the dashboard starts). The app polls
   `GET /api/plugins/hermuse/files` until it stops answering `404`; if it never
   does, restarting the dashboard finishes the install (see "Restarting the
   dashboard").
3. `POST /api/plugins/hermuse/cron/enable`, then
   `POST /api/plugins/hermuse/computer/setup`, which configures Hermes and starts
   the computer's background bootstrap: `/computer/status` reports `building`
   (`Installing Docker…`, `Downloading the computer image…` or
   `Building the computer image…`) until the computer is `stopped` (ready to
   start).

An update is the same install with `"force": true` over the installed copy.
The dashboard keeps serving the plugin code it loaded until it restarts, so
the app then restarts it through the running plugin (see "Restarting the
dashboard").

### From the Hermuse Agent desktop app (Hermes on this computer)

The desktop app bundles a copy of this plugin. It copies it into
`$HERMES_HOME/plugins/hermuse` (a `plugins/hermuse` that is not this plugin is
never overwritten), runs `hermes plugins enable hermuse` and
`hermes hermuse enable` (the background jobs), restarts the Hermes backend it
supervises and sets up the agent's computer. That backend and the
`computer setup` it runs get `HERMES_DESKTOP=1`: the plugin then never installs
Docker itself, never probes `sudo`, and reports a missing Docker as
`docker_missing` with `"hint": "desktop_setup"`. On Linux the app's setup
assistant installs or starts Docker after one administrator authorization and
runs the computer setup through the backend, which alone uses the Docker engine
the assistant chose (see "The agent's computer").

### By hand

```bash
# 1. Copy the plugin into the user plugins dir (tests/ is inert, may be excluded).
cp -r hermes-plugin/hermuse ~/.hermes/plugins/hermuse

# 2. Enable it (opt-in: agent tools, dashboard backend and CLI all gate on this).
hermes plugins enable hermuse

# 3. Register the background jobs (daily feed, weekly ideas, weekly goals
#    check-in, nightly reflection). Re-running only refreshes the specs; a
#    paused job stays paused.
hermes hermuse enable

# 4. Set up the agent's computer (see "The agent's computer").
hermes hermuse computer setup

# 5. Verify.
hermes hermuse doctor
hermes hermuse status
```

If a dashboard that was already running still answers `404` on
`/api/plugins/hermuse/…` after enabling, restart it so the routes load.
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

Base: `/api/plugins/hermuse/`. All HTTP auth behaviour (session token header
`X-Hermes-Session-Token`, enabled-plugin gating) is enforced by Hermes core;
this router adds none of its own. The one WebSocket (`/computer/ws`, which
that gate does not cover) takes a single-use ticket from `POST /computer/ticket`.

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
| `GET` | `/computer/status` | → `{state, detail, control: agent\|human, mode: browser\|desktop}` |
| `POST` | `/computer/setup` | configure Hermes + start the background bootstrap when Docker or the image is missing → `{state, detail}` |
| `POST` | `/computer/start` / `/computer/stop` | → status shape; start failure → `409 {detail}` |
| `GET` | `/computer/thumbnail` | → 640-wide JPEG of the screen / `409` when not running |
| `GET` | `/computer/snapshots/{tool_call_id}` | → JPEG saved after that browser call / `400` bad id / `404` |
| `POST` | `/computer/ticket` | → `{"ticket": …}` (30 s, single use) |
| `WS` | `/computer/ws?ticket=&fps=1..10` | live stream + Take control (see below); closes `4403` bad origin, `4401` bad ticket, `4001` computer unavailable / stream ended |
| `GET` | `/bridge/status` | → `{supported, platform, version, installed, running, base_url, accounts: [{name, provider, email, usable, status, status_message}], detail, sign_in}` (`sign_in`: subscriptions sign in here, plugin 0.4.0 and later) |
| `POST` | `/bridge/ensure` | download (pinned, checksummed) + start the bridge → `{base_url, api_key, version}`; `409` unsupported host / busy, `502` download or start failure |
| `POST` | `/bridge/login` | `{provider}` (`anthropic`, `codex`, `meta`, `antigravity`, `xai`, `kimi`, `kimi-ai`, `devin`) → `{status, url, state}`, plus `flow: "device"`, `user_code`, `expires_in` for device-code sign-ins; `400` unknown provider, `409` not set up |
| `GET` | `/bridge/login/status?state=` | → `{status: "wait" \| "ok" \| "error", error?}` |
| `POST` | `/bridge/login/callback` | `{redirect_url}` (the address the browser landed on after the sign-in, ≤ 8192 chars) → `{ok}`; `400` with CLIProxyAPI's reason when no sign-in waits for its `state` |
| `POST` | `/bridge/login/cancel` | `{state}` → `{cancelled}` |
| `DELETE` | `/bridge/accounts/{name}` | → `{ok, name}` / `404`; `400` bad name (traversal impossible: one `[A-Za-z0-9@._+=-]` segment ending `.json`, never hidden) |
| `GET` | `/bridge/models` | → `{object: "list", data: [{id, object, owned_by}]}` (models of usable accounts); `409` not set up |
| `GET` | `/dashboard` | → `{"boot": …}`: this start of the dashboard process (another value once it restarted) |
| `POST` | `/dashboard/restart` | restart the dashboard in place once the answer is out → `202 {"boot": …}`; `409` a restart is already on its way; `501` this process cannot restart in place (Windows, a backend a desktop app spawned, anything but `hermes dashboard`/`serve`) |

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
├── reflections/<date>.md  +  index.json
├── computer/                 # runtime.json, control.json, build.json + build.log,
│                             #   snapshots/<tool_call_id>.jpg (newest 200)
└── bridge/                   # subscription bridge (0700): bin/cliproxy-<version>,
                              #   keys.json + config.yaml (0600), auth/ (account files),
                              #   cliproxy.json + cliproxy.log, bridge.lock
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

## Restarting the dashboard

A dashboard serves the plugin routes it imported when it started, so an
updated plugin runs only once it restarts, and Hermes 0.21 has no API for
that. `POST /dashboard/restart` (`dashboard_restart.py`) answers `202`, then
about a second later:

1. runs Hermes' own exit teardown of its chat sessions (open transcripts are
   persisted; at most 15 s), since `atexit` does not run on `exec`;
2. re-executes the command line that started the process (`sys.orig_argv`:
   the venv Python and its flags, then the `hermes` launcher or console script
   or `-m hermes_cli.main`, `dashboard` and its options) with `os.execv`, in
   the same environment and working directory; every socket is closed on
   `exec`, so the new program binds the port again.

The PID does not change, so whatever runs the dashboard keeps it: a systemd
unit sees no exit (`Restart=on-failure` has nothing to do), a user unit, a
terminal. One restart at a time (`409`); `501` where it cannot run in place:
Windows (`exec` starts another process there), a backend a desktop app spawned
(it restarts it itself), any process but `hermes dashboard`/`hermes serve`.

The Hermuse app reads `GET /dashboard`, posts the restart, then polls
`GET /dashboard` until another `boot` answers. A plugin older than 0.3.0 has no
such route (`404`/`405`), nor does a plugin whose routes did not mount: the app
then shows the command that restarts the dashboard on that server, read from
the systemd unit its process runs in (`/proc/self/cgroup`, through Hermes'
authenticated file API): `sudo systemctl restart hermuse-dashboard` on a server
the desktop app set up, `systemctl --user restart hermes-dashboard` for the user
service of the server guide.

## Subscription bridge

Subscriptions (Claude Pro/Max, ChatGPT, …) reach a Hermes on a server through a
CLIProxyAPI next to it (`subscription_bridge.py`), the same pinned release the
desktop app bundles as its sidecar (v7.3.18, `packages/hermuse_host/cliproxy.lock`).
The sign-in itself runs on that CLIProxyAPI, so the account exists on the
server only and the Hermuse app (desktop, web or mobile) installs nothing on
the user's machine:

1. `POST /bridge/ensure` downloads the Linux x86-64 or ARM64 release from
   GitHub, checks the archive and binary sha256 against the pins, and starts it
   detached (no root) on `127.0.0.1:<port>`; the port, the `/v1` API key and
   the management key are generated once and kept in `bridge/keys.json`
   (0600), so the endpoint registered in Hermes stays valid across restarts;
2. `POST /bridge/login` starts the sign-in and returns the link the user opens
   in their browser. A device-code sign-in (Meta, xAI, Kimi) only needs the
   code typed there. A browser sign-in ends on a `http://localhost:<port>/…`
   address that cannot reach the server: the user pastes it into the app,
   which posts it to `POST /bridge/login/callback`; CLIProxyAPI reads `state`
   and `code` from it and saves the account. No callback port is ever opened
   on the server. The app polls `GET /bridge/login/status` meanwhile;
3. `GET /bridge/models` lists what the account can serve, and the app
   registers `<base_url>/v1` with the API key as a Hermes custom endpoint.

The management key never leaves the server and remote management stays off
(`allow-remote: false`). The bridge restarts on its own when a Hermes process
loads the plugin after a reboot or a crash, and when `/bridge/status` finds it
stopped. Other hosts answer `supported: false`.

## The agent's computer

Runs on **Docker** on the Hermes host (Docker Engine on Linux, Docker Desktop
on macOS/Windows). Each Hermes profile gets one long-lived container
`hermuse-computer-<profile>` (`<profile>` = last segment of `HERMES_HOME`
reduced to `[a-z0-9-]`) from the image `hermuse-computer:0.2.0`: Chromium with
CDP on an XFCE desktop, streamed as JPEG frames by `screend` (X screen grab +
Pillow JPEG, no ffmpeg). Its home (`/home/hermuse`: logins, cookies) is the
Docker volume `hermuse-computer-<profile>-home`; ports are published on
`127.0.0.1` only.

```bash
hermes hermuse computer setup   # config + background bootstrap; JSON on stdout
hermes hermuse computer status  # {state, detail}
hermes hermuse computer start   # create/start the container, wait for Chromium
hermes hermuse computer stop
```

`setup` sets `browser.cloud_provider: hermuse`,
`browser.auto_local_for_private_urls: false` and `browser.backend: off` (Hermes'
built-in `browser_*` tools drive the computer's Chromium), then starts the
**bootstrap** when something is missing: one detached process
(`computer/bootstrap.py`, output in `computer/build.log`, pid and current
`step` in `computer/build.json`) that

1. installs Docker when it is missing, on Linux only and only when
   `sudo -n true` succeeds: `apt-get install docker.io` (or the
   get.docker.com script without apt), `systemctl enable --now docker`, and
   adds the Hermes user to the `docker` group. Never under the Hermuse Agent
   desktop app (`HERMES_DESKTOP=1`): its setup assistant installs Docker with
   the administrator's consent, and sudo is not even probed;
2. pulls `ghcr.io/yellow-stick/hermuse-computer:0.2.0` (linux/amd64 and
   linux/arm64, published by `.github/workflows/computer-image.yml`) and tags it
   `hermuse-computer:0.2.0`;
3. builds the image locally from `computer/image/` when the pull fails.

Hermes processes started before the user joined the `docker` group reach the
Docker socket through `sg docker -c …` until they restart. Re-running `setup`
retries a failed bootstrap and does nothing while one runs or once the image
exists. Exit codes: `0` for `building`/`stopped`/`running`, `3`
`docker_missing`, `4` `daemon_down`, `1` otherwise (`image_missing`, `error`).

States (`{state, detail}`), in the order they are checked:

| State | Detail |
| --- | --- |
| `building` | the bootstrap runs: `Installing Docker…`, `Downloading the computer image…` or `Building the computer image…` |
| `docker_missing` | the command to run when Hermuse cannot install Docker itself: on Linux `curl -fsSL https://get.docker.com \| sudo sh && sudo usermod -aG docker <user>`, elsewhere `Install Docker Desktop: https://docs.docker.com/get-started/get-docker/`. Under the desktop app: `Open the Hermuse Agent setup to install Docker.`, with `"hint": "desktop_setup"` |
| `daemon_down` | the first line of the failing `docker version` |
| `error` / `image_missing` | the image is absent: `Computer image build failed: <last line of build.log>` after a failed pull and build, otherwise not prepared yet |
| `stopped` / `running` | the container is startable (absent, created or exited) / up |
| `error` | any other Docker failure |

`stopped` and `running` also say where the image came from, read from Docker
rather than from the bootstrap: `"image_source": "registry"` with
`"image_digest": "ghcr.io/yellow-stick/hermuse-computer@sha256:…"` when it was
pulled, `"image_source": "local"` when it was built on this host.

Before every `browser_*` call the
`pre_tool_call` hook blocks the tool while the user holds **Take control**, and
starts a stopped computer (or explains why it cannot) so the agent never falls
back to a browser the user cannot see. After every browser call the screen is
saved to `snapshots/<tool_call_id>.jpg` for the chat's Browser card.

Stream protocol (`/computer/ws`): binary messages are JPEG frames; text
messages are `{"t":"geometry","w","h","mode"}` and
`{"t":"state","control","mine","mode","tabs":[{id,url,title,active}]}`. The
client sends `{"t":"take"}` / `{"t":"release"}`, `{"t":"mode","mode"}`,
`{"t":"tab","action":"activate"|"close","id"}`, and input in frame
coordinates — `move {x,y}`, `down`/`up {x,y,b}`, `wheel {x,y,dy}`,
`key {k: X keysym, a: down|up}`, `text {s}` — which only reaches the computer
from the viewer holding the lease (the latest `take` wins; closing the socket
hands control back).

## Tests

```bash
cd hermes-plugin/hermuse
~/.hermes/hermes-agent/venv/bin/python -m pytest tests/ -q
```

Covers store writes/round-trips, idempotent defaults that never clobber
edits, REST routes + `files/` traversal rejection, the in-place dashboard
restart (the launch command re-executed after the session teardown, one at a
time, refused where it cannot run in place), real-backend cron
registration idempotence, entry-point wiring (tools + skill + CLI + browser
provider + hooks) and the live mount of the routes into a running dashboard,
and the computer: Take control lease, `pre_tool_call` gate and readiness
guard, snapshots, Docker states against a scripted `docker` (incl. the
`sg docker` wrapper), the bootstrap (Docker install through `sudo`, pull,
local-build fallback and its reported error) run for real against a fake
`docker` executable, the inter-process lifecycle lock and global deadlines,
the provider's fail-safe session, and the ticketed WebSocket bridge against a
fake `screend`; the subscription bridge: pins equal to the desktop lock, a
release off its checksums never installed, private files, the detached
process (reused, restarted on its persisted port at plugin load, moved off a
taken port, never confused with a recycled pid) and the account/model routes
with name validation, all against a fake CLIProxyAPI executable (no network).
