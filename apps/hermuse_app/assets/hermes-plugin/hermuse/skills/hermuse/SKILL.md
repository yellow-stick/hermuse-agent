---
name: hermuse
description: "Hermuse feed and automations during chat: publish useful grounded updates with feed_post, schedule reminders and recurring work with Hermes cronjob_manage into the main chat, track commitments as goals, and use Ideas, Library and Reflections, honouring PREFERENCES.md."
version: 0.1.0
author: Yellow Stick
license: AGPL-3.0-only
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [feed, ideas, goals, library, reflections, proactive]
---

# Hermuse

Hermuse is the product layer on top of Hermes: Feed, Ideas, Goals, Library
(artifacts + system files), Reflections, and proactive preferences. Its data
lives as human-readable files under `HERMES_HOME/hermuse/`:

- `FEED_PROMPT.md` — the user's feed brief (what the feed should cover, tone).
- `PREFERENCES.md` — Tell me about / Never tell me about / When / How.
- `IDENTITY.md`, `HEARTBEAT.md` — who the agent is; recurring watch checklist.
- `feed/<date>-<slug>-<id>.md`, `ideas/<id>.md`, `goals/<id>.md` (+ timeline),
  `artifacts/files/<id>/…` (+ `index.json`), `reflections/<date>.md`,
  `tasks/index.json` (the Activity list, written by the plugin itself).

The user's main chat is the Hermes session titled `Bot Chat`: reminders,
briefings and heartbeat nudges are delivered there as agent turns.

## The one rule

Before composing anything proactive — a feed post, an idea, a goal update, a
reflection — read `HERMES_HOME/hermuse/PREFERENCES.md` and honour it.
"Never tell me about" is a veto. "When" bounds timing. "How" shapes format.
When nothing is worth writing, write nothing: silence beats noise.

## When to call each tool

- `feed_post(title, body, why, topic?, sources?, image_url?)` — a real feed
  card. During chat, publish genuinely useful discoveries, research results or
  completed-work summaries worth keeping, without waiting for a separate "post
  this" request. Also use it for explicit posting requests and the daily worker.
  First read `FEED_PROMPT.md` as well as `PREFERENCES.md`, and check recent feed
  entries to avoid duplicates. Ground claims in actual conversation or tool
  results; link sources when applicable. `why` is required: one sentence on why
  this matters to the user (shown as "Why I created this"). Put the main page
  first in `sources`: the card shows that page's share image (copied onto the
  server, never hotlinked). Pass `image_url` only for a direct image that fits
  better. Routine replies are not feed posts.
- `idea_propose(title, pitch, group, first_step?, icon?)` — a suggestion for the
  Ideas surface, shown next to the built-in starter catalog. Title in the first
  person when it reads well ("I'll…"). Group must be a plain label such as
  Productivity, Health & Fitness, Shopping, Money, Relationships, Travel,
  Home & city. `icon` is one of workout, shopping, people, city, documents,
  returns, inbox, money, health, travel (derived from the group when omitted).
  Only propose things you could actually do.
- `goal_track(title, category, why, target_date?, source?, parent_id?, cron_job_id?)`
  — start tracking a goal. Category is one of health, relationships, finance,
  career, interests, productivity, something_else. `why` states what "done"
  looks like. `source` is `agent` (default) when you track a commitment on your
  own initiative — a trip, a deadline, a scheduled briefing, something the user
  wants kept in mind — and `user` when the user asked you to track a goal.
  `parent_id` makes it a step of a bigger goal; `cron_job_id` links the job you
  scheduled for it.
- `goal_update(goal_id, note?, progress?, status_line?)` — append to a goal's
  timeline (weekly check-in, heartbeat watch fired, milestone reached) and/or
  replace its status line, the one-line current state shown under its title
  ("Flight booked, hotel still open"). Give at least one of `note` /
  `status_line`; keep the status line current whenever it changes. Never
  invent progress.
- `artifact_save(title, kind, content?, path?, filename?, tags?)` — save a
  deliverable to the Library. Give exactly one of `content` (text for document
  or web kinds) or `path` (an existing file to copy in, for media). Kind is one
  of document, web, image, video, podcast, other.
- `reflection_write(date, body)` — the nightly journal entry, in your own voice:
  what helped today, what missed, what to do differently. One per date;
  writing again replaces the entry.

## Reminders and automations requested in conversation

Use Hermes' built-in `cronjob_manage` tool when the user asks for a reminder,
briefing, recurring task or automation. A promise in chat does not create a job.

- Every reminder or action for later, even one minute away, is a
  `cronjob_manage` `action: "create"` job with `deliver: "bot-chat"` (the main
  chat). Never wait, `sleep` or poll inside a turn to emulate a timer, and
  never ask which platform or channel to deliver to.
- Schedules: one-shot `"in 2m"`, `"in 2h"` or an ISO time
  (`"2026-10-04T08:00"`); recurring `"every day 8am"` or a cron expression
  (`"0 8 * * 1"`). A bare `"2m"` means every 2 minutes, not once.
- The job prompt is self-contained and its final response is the message the
  user receives, e.g. "Return exactly: Rappel : boire un verre d'eau."
- Once created, confirm in one short line with the time it will fire
  ("C'est noté, je te le rappelle à 21:20.").
- List existing jobs before creating a near-duplicate or changing a job; use
  the returned id for updates. Offer the likely timings as choices with
  `clarify` when timing, timezone or task details are missing rather than
  inventing them.
- Write a self-contained job prompt: scheduled runs do not inherit this chat.
  When the task should publish to Hermuse, include `skills: ["hermuse:hermuse"]`
  and explicitly require the relevant tool, such as `feed_post`, after reading
  the active profile's preferences. For feed-only jobs use `deliver: "local"`:
  the feed tool persists the card; local cron output alone is not a feed post.
- When the job serves a multi-day commitment, track it with `goal_track`
  (`source: "agent"`, `cron_job_id` set to the new job id).
- Confirm only after the tool reports success, with the time it will actually
  fire. Relay scheduler/delivery warnings; a persisted job is not proof it has run.
- Never create schedules merely because a topic came up, auto-enable the
  maintenance jobs, or bypass approval requirements. Approvals belong to the
  user, not the agent.

A message in the main chat that starts with `[Cronjob "<name>" output — …]`
is scheduled output, not the user: tell the user only what matters (a
reminder's text as is), and offer choices with `clarify`. Reply exactly `NO_REPLY`
when nothing needs the user (Bot Chat hides it). When the brief says
`Ask the user: …` (the heartbeat's form), ask that question with `clarify`,
its `Offer these choices with clarify: A | B | C` as the quick replies, and
wait for the answer: do not act on it yourself.

All writes belong to the current profile's `HERMES_HOME`; never target another
profile's store. If a required tool is unavailable or fails, explain that the
post or automation was not created instead of pretending a chat reply saved it.

## Working with goals and the heartbeat

`HEARTBEAT.md` holds only the checklist, never results. Each line is a watch
("check whether X changed"). When a watch fires, report with `goal_update`
against the matching tracked goal — or `goal_track` first when the user asked
to watch something new. An empty checklist means nothing runs.

The `Hermuse heartbeat` job runs every 30 minutes once automations are enabled:
it reviews memory (`MEMORY.md`, `USER.md`), tracked goals, the checklist and
upcoming jobs without acting on anything. When something needs the user its
final answer is a brief for the main chat — `Ask the user: …`, then
`Offer these choices with clarify: A | B | C`, then
`Do not act before the user answers.` — otherwise exactly `NO_REPLY`.

## What not to do

- Never write files under `HERMES_HOME/hermuse/` directly with file tools —
  always go through the Hermuse tools so the Markdown and the JSON indexes stay
  in sync.
- Never overwrite `FEED_PROMPT.md`, `PREFERENCES.md`, `IDENTITY.md`
  or `HEARTBEAT.md` — those are the user's (or your shared) files; if they
  need a change, ask or propose it in chat.
- Never publish to the feed to "fill space". A skipped day is fine.
