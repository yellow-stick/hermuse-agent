# Hermuse Agent web demo

Live at https://demo.hermuse.app.

A read-only build of the web app (`apps/hermuse_web`) that runs on any static
host: no Hermuse relay, no Hermes instance. Everything it shows is fictional.

- Two instances, **Ava** (personal) and **Otto** (work), each with a main chat
  and side chats (one pinned, one archived), reasoning and tool-call rows.
- Feed, Ideas, Goals and Library (artifacts, system files, reflections) filled
  from the same fictional content.
- Nothing can be written: the composer is replaced by a note, and adding
  instances, new side chats, rename/archive/delete, reply and the agent's
  computer are hidden. Anything that still reaches the backend (feed reactions,
  idea feedback, goal edits, file saves) is refused with "This demo is
  read-only". Pins, reactions and panel options stay: they are local to the
  browser.

## How it works

`package:hermuse_demo` (this folder) answers the app in the browser:

- `DemoTransport` replaces the Hermes WebSocket: `session.resume` returns the
  transcripts of `lib/src/content.dart`, every other call is refused.
- `demoPluginClient` answers the Hermuse plugin routes (`GET` only).
- `seedDemo` fills a separate browser database (`hermuse-demo`, never the
  app's own `hermuse`) with the instances, the chat index and the search
  cache, on every page load.

The web app switches to it at compile time: `jaspr build
--dart-define=HERMUSE_DEMO=true` sets `hermuseDemo` (`apps/hermuse_web/lib/scope.dart`).
Production builds leave it off and the demo code is compiled out.

Chat and record times count back from page load, so the demo always looks
recent.

## Build, preview, deploy

```bash
demo/build.sh                                        # → demo/build/web
python3 -m http.server -d demo/build/web 8090        # preview on http://localhost:8090
```

GitHub Actions deploys it to the Netlify project `hermuse-demo`
(https://demo.hermuse.app): production from `web-deploy.yml` on every push to
`main` that touches the web app or this folder, a `pr-<N>` preview from
`web-pr.yml` on pull requests. The root `netlify.toml` holds the project's
headers and the manual deploy commands (run from the repository root).

To change the content, edit `lib/src/content.dart`, then run the tests:

```bash
cd demo && dart test
```
