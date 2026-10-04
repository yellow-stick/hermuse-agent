# Proactive agent: tasks, reminders in the main chat, Identity

Goal: Hermuse behaves like a personal agent that works on its own between
messages, not a chat client over raw tool calls. Everything below runs on an
unpatched Hermes Agent 0.21.5 plus the Hermuse plugin; both apps (Flutter and
Jaspr) behave the same (`hermuse_chat` / `hermuse_state` own the behaviour).

## Target behaviour

| Surface | Behaviour |
| --- | --- |
| Main chat | Reminders, briefings, scheduled results and proactive nudges arrive here as agent turns. The agent never asks "which platform should I deliver to". |
| Scheduler | Scheduled jobs really fire on servers set up by Hermuse (the Hermes gateway runs as a service next to the dashboard). |
| Heartbeat | Every 30 min the agent reviews memory, goals and upcoming items; it writes in the main chat only when something needs the user (e.g. "your trip is in 4 days and the flight is unbooked"), with quick-reply choices; otherwise it stays silent. |
| Activity | One row per task (one user request or one scheduled run), titled and summarised by the auxiliary model ("Set daily 8am briefing — Scheduled daily 8:00 AM Nantes briefing"), across every surface, newest first, grouped by day. A running task shows live with a Stop button; the agent's current step shows under its name in the panel ("Searching the web"). |
| Approvals | Panel tab lists unanswered approval cards (usually empty). The mode lives in Settings → Permissions: "Ask only when needed" (`smart`, default), "Always ask for risky commands" (`manual`), "Never ask" (`off`). |
| Upcoming | Scheduled items grouped Reminders (one-shot), Daily, Weekly, Other recurring, Heartbeat. Hermuse maintenance jobs (feed, ideas, goals check-in, reflection) are hidden. Tapping an item opens a sheet: schedule, next run, run history (time, status, output excerpt), Pause/Resume, Run now, Delete. |
| Identity | Name + Edit (agent editor), then two cards: SOUL (opens SOUL.md editor) and MEMORY (opens the memory editor: MEMORY.md and USER.md entries). |
| Connectors | Moved to Settings → Connectors (honest empty state until real connectors exist). The panel has four tabs: Activity, Approvals, Upcoming, Identity. |
| Goals | Two sections: Tracking (goals the agent created itself, e.g. for a trip or a scheduled briefing) and Goals (asked by the user). Each shows a live status line. Menu: Complete, Add subgoal, Rename, Delete. |
| Feed | Fills itself daily from the user's context; each post can carry an image, sources, "Why I created this", Discuss, Delete; a Generate button runs an edition now. Bodies render as Markdown. |
| Ideas | A starter catalog grouped by theme is always present; the agent's own ideas join it. "Try it" seeds the main chat. In chat the agent offers options as quick replies (clarify). |

## Mechanisms (Hermes 0.21.5, no patch)

- **Main chat = Hermes "Bot Chat" session.** Hermes delivers `deliver: "bot-chat"`
  cron output into the profile's session titled exactly `Bot Chat`: through the
  live owner mailbox when a client holds the session (normal streaming turn),
  else via `hermes chat -c "Bot Chat"` (row written to state.db). Hermuse makes
  its main chat that session: on connect, `session.list {title: "Bot Chat"}`;
  if missing, rename the current main session with `session.title` (or create
  one with `session.create {title: "Bot Chat"}`). On `sessions.changed` and
  after a reconnect the lookup runs again: another session holding the title
  becomes the main chat (the previous one a side chat). When the main chat is
  not live, refetch its history on `sessions.changed`; a re-read merges into
  what is shown (streamed turns keep their tool outcomes, reasoning, request
  cards, clarify answers and `Stopped` notices; only rows nothing shows are
  inserted). A server-started turn reads the transcript once it streams, so
  its `Scheduled: <job>` notice shows before the reply (`message.start` has
  no payload). Clarify answers after a reload come from the session's stored
  tool results (`GET /api/sessions/{id}/messages`), absent from
  `session.resume`.
- **Scheduler.** `hermes gateway install --system --run-as-user hermes --start-now`
  (or a `hermuse-gateway.service` unit running `hermes gateway run`) next to
  `hermuse-dashboard.service`. Health: `scheduler_heartbeat_age_s` on
  `GET /api/cron/jobs`.
- **Agent behaviour.** Plugin `register_system_prompt_section("hermuse_behaviour")`:
  schedule reminders/recurring work with `cronjob` `deliver="bot-chat"`;
  never ask for a delivery platform; track multi-day commitments as agent
  goals (`goal_track source="agent"`) and keep their status current;
  offer choices with `clarify`; feed posts carry `why`.
- **Heartbeat.** Hermuse cron spec `heartbeat`, every 30 min,
  `deliver: "bot-chat"`, prompt: review MEMORY/USER, goals, upcoming jobs;
  reply exactly `NO_REPLY` when nothing needs the user (Bot Chat withholds it).
- **Tasks.** Plugin hook `post_llm_call` (kwargs: session_id, turn_id,
  user_message, assistant_response, conversation_history, model, platform)
  queues a summary job off-thread; title + one-line result from the auxiliary
  model (`ctx.llm.complete_structured`, or `agent.auxiliary_client.call_llm`
  with a plugin-registered auxiliary task `hermuse_task_summary`), fallback to a
  heuristic when the model fails. `on_session_end` records interrupted/failed.
- **Run history.** `GET /api/cron/jobs/{id}/runs?limit=` (run sessions) and
  `GET /api/sessions/{run_id}/messages`: the excerpt is the run's final answer
  (last assistant message without tool calls), minus a lead paragraph of
  narration before its first heading; jobs carry `last_output`,
  `last_status`, `last_delivery_error`.
- **SOUL.** `GET/PUT /api/profiles/{name}/soul` or `profiles.describe` /
  `profiles.configure {soul}`.
- **Memory.** New plugin routes over `HERMES_HOME/memories/{MEMORY,USER}.md`
  (entries separated by `\n§\n`, written under MemoryStore's lock).
- **Approvals mode.** `config.get` / `config.set` key `approvals.mode`.

## Plugin contract (prefix `/api/plugins/hermuse`)

All routes are profile-scoped like the existing ones. Timestamps are ISO-8601 UTC.

### Tasks
- `GET /tasks?limit=100&before=<iso>` →
  `{"tasks": [Task]}` newest first.
  `Task = {"id", "session_id", "turn_id", "title", "summary", "status": "completed"|"failed"|"interrupted", "source": "chat"|"cron"|"heartbeat"|"other", "started_at", "finished_at", "tools": ["web_search", ...]}`.
  Heartbeat turns that ended in `NO_REPLY` are not recorded.

### Memory
- `GET /memory/{target}` (`target` = `memory` | `user`) →
  `{"target", "entries": [str], "updated_at"}`.
- `PUT /memory/{target}` body `{"entries": [str]}` → `{"ok": true}`.

### Goals (extends existing records)
- Goal adds `"source": "user"|"agent"`, `"status_line": str` (latest
  progress, shown under the title), `"done": bool`, `"parent_id": str|null`,
  `"cron_job_id": str|null`. Existing records read as `source: "user"`,
  `done: status == "done"`.
- `PATCH /goals/{id}` body `{"title"?, "done"?}` → goal.
- `DELETE /goals/{id}` → `{"ok": true}` (also deletes subgoals).
- `POST /goals` accepts `{"title", "category", "why", "source"?, "parent_id"?}`.
- Tools: `goal_track` gains `source` (default `agent` when called by the
  agent on its own initiative, the prompt section explains) and `parent_id`,
  `cron_job_id`; `goal_update` gains `status_line`.

### Feed (extends existing records)
- Post adds `"why": str`, `"image_url": str|null`. `feed_post` tool gains
  `why` (required) and `image_url`.
- `DELETE /feed/{id}` → `{"ok": true}`.
- `POST /feed/generate` → triggers the feed job now → `{"job_id", "started": true}`.

### Ideas
- `GET /ideas` returns agent ideas plus the starter catalog:
  idea adds `"seeded": bool`, `"icon": str` (an icon key such as
  `workout`, `shopping`, `people`, `city`, `documents`, `returns`, `inbox`,
  `money`, `health`, `travel`). Seeded ideas are static data shipped with the
  plugin (not files), ids prefixed `seed-`.
- `POST /ideas/{id}/dismiss` hides an idea (seeded or not) → `{"ok": true}`.

### Cron
- `GET /cron` jobs add `"hidden": bool` (true for feed/ideas/goals/reflection
  maintenance jobs; false for heartbeat).

## Slices

1. **Plugin** (`hermes-plugin/hermuse`): contract above, hook, prompt
   section, heartbeat spec, seeds, pytest. Synced into the app assets.
2. **Host** (`packages/hermuse_host`, installer scripts, Linux service): the
   gateway service on SSH installs and the local Linux service; "What's
   installed" shows the scheduler.
3. **State** (`hermuse_chat`, `hermuse_state`, `hermes_client`): Bot Chat main
   chat, `sessions.changed` refresh, server tasks replacing the device-local
   activity, live running task + Stop, agent step label, approvals mode,
   Identity (soul, memory), goals/feed/ideas client calls, Upcoming grouping +
   run history.
4. **Desktop UI** (`apps/hermuse_app`) and 5. **Web UI** (`apps/hermuse_web`):
   the surfaces above on top of slice 3.

Docs: `docs/guides/profile-panel.md` and the product guides follow the change.
