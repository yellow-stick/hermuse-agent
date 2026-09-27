---
name: hermuse
description: "Hermuse product layer: when to call feed_post, idea_propose, goal_track, goal_update, artifact_save and reflection_write, honouring PREFERENCES.md."
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

- `feed_post(title, body, topic?, sources?)` — a feed card. Use the daily worker
  or when the user asks "post this to my feed". Ground claims; link sources.
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
