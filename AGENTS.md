# AGENTS.md

Hermuse Agent (Yellow Stick) — personal AI agent on top of Hermes Agent.
Dart pub workspace (Melos 8.9), Flutter 3.47 + Jaspr 0.23. Public repo
`yellow-stick/hermuse-agent`, default branch `main`; outside contributions come
as pull requests from forks (`CONTRIBUTING.md`).

## Layout

- `apps/hermuse_app/` — Flutter app (iOS, Android, macOS, Windows, Linux).
- `apps/hermuse_web/` — Jaspr web app, static pre-render + `@client` hydration, PWA.
- `apps/hermuse_relay/` — same-origin relay from the web app to Hermes instances.
- `packages/yellow_stick_ui_core/` — design tokens, single source of truth.
- `packages/yellow_stick_ui/` + `yellow_stick_ui_web/` — Flutter / Jaspr kits (no shared widget code).
- `packages/hermes_contract/` — Hermes gateway JSON-RPC types, generated from OpenRPC.
- `packages/hermes_client/` — instances, secrets, dashboard REST + WebSocket transport.
- `packages/cliproxy_client/` — CLIProxyAPI management client (subscription bridge).
- `packages/hermuse_chat/` — chat models, state, Hermes-backed controller.
- `packages/hermuse_data/` — drift database (native file or WASM on web).
- `packages/hermuse_state/` — shared Riverpod state for both apps.
- `packages/hermuse_host/` — desktop only: Hermes install, supervision, bridge sidecar.
- `hermes-plugin/hermuse/` — Hermes plugin: Feed, Ideas, Goals, Library, Reflections, agent's computer. Python, stdlib-only store.
- `.agents/skills/` — 41 vendored skills (dart-*, flutter-*, jaspr-*, riverpod, …). Read the matching skill before working in its area.

## Architecture rules

- Hermes Agent instances are the only backend, multi-instance from day one. Never hardcode an instance; the user enters URL + credentials.
- Primary transport: Hermes dashboard `/api/ws` JSON-RPC, same as Hermes Desktop.
- Behaviour is shared: both apps render `hermuse_chat`'s `ChatState` and call the same `ChatController` — an action must not behave differently on web and native.
- Design tokens are the contract: both kits read values from `yellow_stick_ui_core` (Luna-vocabulary roles: `canvas`, `paper`, `content`, `primary`, `line`, …) and render their own way. Never hardcode a color, radius, spacing or icon in a widget; add it to the core package.
- Main/side chat model: one Main chat per Hermes instance, every other thread a side chat (parent = main session). Sessions from other surfaces (CLI, Telegram, …) are not listed.
- Product data lives as Markdown + JSON under `HERMES_HOME/hermuse/` (readable, editable, backed up with any tool).
- Naming: product is "Hermuse Agent" by Yellow Stick. Never "Muse"/"Hermes" in the product name; compatibility is phrased "works with Hermes Agent". Keep the README trademark disclaimer as-is.

## Setup and commands

```bash
dart pub global activate melos
flutter pub get          # resolves the whole workspace
melos run analyze        # dart analyze --fatal-infos .
melos run test           # dart + flutter tests (see below)
dart format --output=none --set-exit-if-changed .
```

Running:

```bash
cd apps/hermuse_app && flutter run -d linux   # or macos / windows / device
tool/serve-web.sh                             # jaspr serve; http://localhost:8080 in the main checkout
cd apps/hermuse_web && jaspr build            # static output in build/jaspr
cd hermes-plugin/hermuse && ~/.hermes/hermes-agent/venv/bin/python -m pytest tests/ -q
```

Web deploy: `.github/workflows/web.yml` builds `apps/hermuse_web` and deploys it
with the Netlify CLI to project `hermuse-agent` (https://hermuse.app): production
on push to `main`, draft alias `pr-<N>` on pull requests of this repository once
ready for review; merge groups only build. Netlify's Git builds
are stopped; `netlify.toml` (headers, manual deploy commands) is the only site
config. Secrets: `NETLIFY_AUTH_TOKEN`, `NETLIFY_SITE_ID`.

Worktrees (Orca): `orca.yaml` runs `tool/orca/setup-worktree.sh` on create
(`flutter pub get --enforce-lockfile`; codegen is committed, nothing shared with
the main checkout) and `tool/orca/archive-worktree.sh` on archive (stops every
process rooted in the tree). In a linked worktree `tool/serve-web.sh` picks a
port triple derived from the path (printed on start; `HERMUSE_WEB_PORT`
overrides). Jaspr always binds the Dart VM service to 8181: a second concurrent
`jaspr serve` logs a DDS "address already in use" error but keeps serving.

## Generated code — never edit by hand

- `packages/hermes_contract/lib/src/contract.g.dart` (`// GENERATED … do not edit`). Regenerate from `packages/hermes_contract`: `dart run tool/gen_hermes_contract.dart`. `test/drift_test.dart` fails when the committed output is stale.
- Desktop app bundles a copy of the plugin. After changing `hermes-plugin/hermuse`, refresh it from `apps/hermuse_app`: `dart run tool/sync_plugin_assets.dart` (covered by `plugin_assets_test.dart`).
- `jaspr_builder` 0.23.5 wants `analyzer ^12`, capped at `build_runner` 2.15.1 / `build_web_compilers` 4.8.5. The root `dependency_overrides` pins `analyzer ^13.3.0` (jaspr builds fine on 13.x). Bump these together with Jaspr.

## Commits, branches and PRs

Commit subject: `<Area>: <what changed>` — one line, English, present tense, lowercase after the colon (proper nouns excepted), no trailing period, no body needed.

- Area names the product surface or package, capitalized: `Chat`, `Hermuse computer`, `Onboarding`, `Relay`, `Web`, `Desktop`, `Host`, `Plugin`, `Contract`, `Data`, `UI`, `Release`, `Docs`, `Tooling` (build, CI, worktree scripts).
- The subject says what the product or repo does now, not how the work went: `Chat: hold slash commands refused as busy and replay when the session is idle`. Several changes: comma-separated (`Chat: provider retry status, server slash commands`); a distinct second group after `;` (`Hermuse computer: browser card, live viewer; one-click remote install`). Changes spanning unrelated areas belong in separate commits.
- Never mention `muse.ai`, renames, "fix typo", "cleanup", "WIP", "address review", agent or tool names, and no `Co-authored-by` trailers. Squash fixups locally before pushing.
- One logical change per commit; commit only files of that change. The main checkout often holds unrelated work in progress: never `git add -A` there — commit from a dedicated worktree or stage explicit paths.

Branches: `yellow-stick/<topic>` in kebab-case (`yellow-stick/docs-guides`, `yellow-stick/orca-worktrees`), cut from `origin/main`. Never commit to `main` directly.

Pull requests: target `main`. Title in the commit style, summarizing the whole branch. Description in English: what changes for the user or developer, then the validation that actually ran (see below). Open it as a draft while in progress: drafts run no CI; ready for review runs the checks and the builds of every platform, and the merge queue runs the installed-package smoke tests before merging (`CONTRIBUTING.md`). Merge through the merge queue with a merge commit (`Merge pull request #N from yellow-stick/<topic>`), not squash or rebase, then delete the branch.

## Validation per area

- Dart/Flutter change: `melos run analyze` + the package's tests (`melos run test:dart` / `test:flutter`).
- Web change: `jaspr build` in `apps/hermuse_web` on top of analyze + tests.
- Plugin change: `pytest tests/ -q` in `hermes-plugin/hermuse` plus `plugin_assets_test.dart` after re-syncing assets.
- Contract change: regenerate + `drift_test.dart`.
- Do not claim checks passed unless they ran; on failure report what failed.

## References

- User docs: `docs/guides/` (`server.md`, `desktop.md`, `web-app-and-relay.md`, `agent-computer.md`).
- Plans: `docs/plans/` (`hermes-backend.md`, `computer-surface.md`).
- Plugin install/test flow: `hermes-plugin/hermuse/README.md`.
- AGENTS.md conventions followed here: [GitHub docs on custom instructions](https://docs.github.com/en/copilot/concepts/prompting/response-customization), [VS Code guide to customizing agents](https://code.visualstudio.com/docs/agents/guides/customize-copilot-guide).
