# Hermuse Agent web demo

Live at https://demo.hermuse.app.

A read-only build of the web app (`apps/hermuse_web`) that runs on any static
host: no Hermuse relay, no Hermes instance. Everything it shows is fictional.

- Two instances: **Ava** (personal) and **Otto** (work), each with a main
  chat and side chats (one pinned), reasoning and tool-call rows.
- Four everyday stories, backed by matching Feed, Goals, Ideas and Library
  entries so every panel tells the same story:
  - Ava's main chat: the agent compares her electricity renewal and switches
    her (€0.24 → €0.18/kWh, ~€22/month saved), then shows the morning Feed
    it wrote while she slept.
  - `Night pass — emails + code`: the 02:00 pass over the connected mailbox
    and the day's pushes (18 emails read, 6 commits reviewed on
    `lea/home-admin`, switch confirmed, school form pre-filled, dentist
    moved) — cron output lives in a side chat, the to-do list in the
    morning Feed post.
  - `Nightly to-do list`: the set-up in plain words ("go through my emails
    and what I pushed today, to-do list at 7") with the `cronjob`
    confirmation row — the way the real product schedules it (chat +
    Hermes cron job, no invented UI).
  - `Weekend in Annecy`: a trip for two under €400, priced line by line
    (trains, hotel, swim), hotel booked with free cancellation.
  - `Autumn half-marathon`: a 12-week plan with Sunday check-ins and a
    knee-aware week, tracked in Goals.
  - Otto's main chat: customer-interview synthesis → one-pager in the
    Library, plus which AI subscription the chat runs on.
- Its own computer. And you own it. The electricity and Annecy answers
  carry a Browser card: `browser_*` transcript rows render the card, and
  the demo serves it fictional stills. Open preview / Open computer shows
  the fake computer live: replayed frames of fictional sites
  (`demo/tool/frames/`, regenerated with `render.sh`), a Browser | Desktop
  switch, and working browser tabs. Take control shows but stays inert;
  nothing writes anywhere.
- Nothing else can be written: the composer is replaced by a note, and
  adding instances, new side chats, rename/archive/delete and reply are
  hidden. Anything that still reaches the backend (feed reactions,
  idea feedback, goal edits, file saves) is refused with "This demo is
  read-only". Pins, reactions and panel options stay: they are local to the
  browser. No journey shows approvals or confirmations as a selling point.

## How it works

`package:hermuse_demo` (this folder) answers the app in the browser:

- `DemoTransport` replaces the Hermes WebSocket: `session.resume` returns the
  transcripts of `lib/src/content.dart` (browser steps ride as `browser_*`
  tool rows with their page URLs), every other call is refused.
- `demoPluginClient` answers the Hermuse plugin routes: feed/ideas/goals/
  library/reflections/system files as before, plus the fake computer —
  `GET computer/status` (running), `GET computer/thumbnail` and
  `GET computer/snapshots/<toolId>` from the embedded frames of
  `lib/src/computer_frames.dart`, and the `POST computer/ticket` that opens
  the replayed stream. Every other write is refused.
- `demoComputerConnector` (injected as the `ComputerClient`'s socket)
  replays the computer's screen: geometry + state messages, then looping
  JPEG frames of the fictional sites, with local answers to take/release,
  mode and tab messages. Nothing leaves the browser.
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
