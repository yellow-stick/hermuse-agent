---
name: hermuse
description: "Hermuse feed and automations during chat: publish useful grounded updates with feed_post, schedule requested work with Hermes cronjob_manage, and use Ideas, Goals, Library and Reflections, honouring PREFERENCES.md."
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
  `artifacts/files/<id>/…` (+ `index.json`), `reflections/<date>.md`.

## The one rule

Before composing anything proactive — a feed post, an idea, a goal update, a
reflection — read `HERMES_HOME/hermuse/PREFERENCES.md` and honour it.
"Never tell me about" is a veto. "When" bounds timing. "How" shapes format.
When nothing is worth writing, write nothing: silence beats noise.

## When to call each tool

- `feed_post(title, body, topic?, sources?)` — a real feed card. During chat,
  publish genuinely useful discoveries, research results or completed-work
  summaries worth keeping, without waiting for a separate "post this" request.
  Also use it for explicit posting requests and the daily worker. First read
  `FEED_PROMPT.md` as well as `PREFERENCES.md`, and check recent feed entries to
  avoid duplicates. Ground claims in actual conversation or tool results; link
  sources when applicable. Routine replies are not feed posts.
- `idea_propose(title, pitch, group, first_step?)` — a suggestion for the Ideas
  surface. Title in the first person when it reads well ("I can…"). Group must
  be a plain label such as Productivity, Health & Fitness, Relationships,
  Financial Management, Shopping. Only propose things you could actually do.
- `goal_track(title, category, why, target_date?)` — start tracking a goal.
  Category is one of health, relationships, finance, career, interests,
  productivity, something_else. `why` states what "done" looks like.
- `goal_update(goal_id, note, progress?)` — append to a goal's timeline (weekly
  check-in, heartbeat watch fired, milestone reached). Never invent progress.
- `artifact_save(title, kind, content?, path?, filename?, tags?)` — save a
  deliverable to the Library. Give exactly one of `content` (text for document
  or web kinds) or `path` (an existing file to copy in, for media). Kind is one
  of document, web, image, video, podcast, other.
- `reflection_write(date, body)` — the nightly journal entry, in your own voice:
  what helped today, what missed, what to do differently. One per date;
  writing again replaces the entry.

## Automations requested in conversation

Use Hermes' built-in `cronjob_manage` tool when the user asks for a reminder,
recurring task or automation. A promise in chat does not create a job.

- List existing jobs before creating a near-duplicate or changing a job; use
  the returned id for updates. Clarify missing timing, timezone or task details
  rather than inventing them. Follow the tool's schedule and delivery contract.
- Write a self-contained job prompt: scheduled runs do not inherit this chat.
  When the task should publish to Hermuse, include `skills: ["hermuse:hermuse"]`
  and explicitly require the relevant tool, such as `feed_post`, after reading
  the active profile's preferences. For feed-only jobs use `deliver: "local"`:
  the feed tool persists the card; local cron output alone is not a feed post.
- Confirm the actual schedule and job id only after the tool reports success.
  Relay scheduler/delivery warnings; a persisted job is not proof it has run.
- Never create schedules merely because a topic came up, auto-enable the
  maintenance jobs, or bypass approval requirements. Approvals belong to the
  user, not the agent.

All writes belong to the current profile's `HERMES_HOME`; never target another
profile's store. If a required tool is unavailable or fails, explain that the
post or automation was not created instead of pretending a chat reply saved it.

## Working with goals and the heartbeat

`HEARTBEAT.md` holds only the checklist, never results. Each line is a watch
("check whether X changed"). When a watch fires, report with `goal_update`
against the matching tracked goal — or `goal_track` first when the user asked
to watch something new. An empty checklist means nothing runs.

## What not to do

- Never write files under `HERMES_HOME/hermuse/` directly with file tools —
  always go through the Hermuse tools so the Markdown and the JSON indexes stay
  in sync.
- Never overwrite `FEED_PROMPT.md`, `PREFERENCES.md`, `IDENTITY.md`
  or `HEARTBEAT.md` — those are the user's (or your shared) files; if they
  need a change, ask or propose it in chat.
- Never publish to the feed to "fill space". A skipped day is fine.
