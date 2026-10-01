# Hermuse Agent web demo

A read-only build of the web app (`apps/hermuse_web`) that runs on any static
host: no Hermuse relay, no Hermes instance. Everything it shows is fictional.

- Two instances: **Ava** (personal) and **Otto** (work), each with a main
  chat and side chats (one pinned), reasoning and tool-call rows.
- Four everyday stories, backed by matching Feed, Goals, Ideas and Library
  entries so every panel tells the same story:
  - Ava's main chat: the agent compares her electricity renewal and switches
    her (€0.24 → €0.18/kWh, ~€22/month saved), then shows the morning Feed
    it wrote while she slept.
  - `Weekend in Annecy`: a trip for two under €400, priced line by line
    (trains, hotel, swim), hotel booked with free cancellation.
  - `Autumn half-marathon`: a 12-week plan with Sunday check-ins and a
    knee-aware week, tracked in Goals.
  - Otto's main chat: customer-interview synthesis → one-pager in the
    Library, plus which AI subscription the chat runs on.
- Nothing can be written: the composer is replaced by a note, and adding
  instances, new side chats, rename/archive/delete, reply and the agent's
  computer are hidden. Anything that still reaches the backend (feed reactions,
  idea feedback, goal edits, file saves) is refused with "This demo is
  read-only". Pins, reactions and panel options stay: they are local to the
  browser. No journey shows approvals or confirmations as a selling point.

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
netlify deploy --no-build --dir=demo/build/web --prod
```

`netlify.toml` holds the headers of the Netlify site (base directory `demo`).

To change the content, edit `lib/src/content.dart`, then run the tests:

```bash
cd demo && dart test
```
