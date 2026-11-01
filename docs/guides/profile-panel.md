# Agents, Activity, Approvals, Upcoming and Identity

The profile panel sits on the right of the chat (the avatar at the top right
opens it on narrow windows). Under the agent's name a status line says
**Connected** while the agent is idle and what it is doing while it works
("Searching the web", "Reading example.com", "Running a command"). Under
**Open computer** it has four tabs: **Activity**, **Approvals**, **Upcoming**
and **Identity**. The desktop app and the web app show the same thing.

## Several agents on one Hermes

The **Agent** menu in the chat header switches agents without changing the
Hermes instance. Each agent is a real Hermes profile, with its own **SOUL
prompt**, main chat and side chats. The app remembers the selected agent and
the last conversation for each profile on this device.

- Choose **Create agent…** on desktop or **Add agent** on the web, pick a
  portrait (or generate one, below), and edit the name and prompt before
  saving. Creating a profile uses the same server and shares its model
  credentials; it does not install another Hermes.
- Choose **Edit agent…**, or click the pencil on the profile portrait, to
  change the selected agent's name, portrait and prompt. The editor loads
  that profile's saved prompt. Picking another portrait never replaces an
  existing agent's prompt.
- A saved prompt applies to **new conversations**. Existing conversations
  retain the system prompt Hermes already captured for them.

Hermuse keeps the original profile. Noah, Aya, Oscar, Iris, Rusty, Bao, Olive,
Mint and Nova are static portrait choices with editable starting prompts.
Only the original Hermuse profile, while using its original portrait, and
agents with a generated, animated portrait play activity animations.
Reduced-motion preferences show the static portrait instead.

Feed, Ideas, Goals, Library, Activity, Upcoming, Identity and the computer view
follow the selected profile. Update the Hermuse plugin on existing servers
before using these profile-scoped surfaces; older plugins do not isolate
their data by profile. Profiles separate agent state, not operating-system
permissions: they are not security sandboxes.

### Custom agents with a generated portrait

When the server has image generation set up (**Settings → Image
generation**, see [the server guide](server.md#image-generation)), the agent
editor offers **Generate** next to the bundled portraits:

1. Describe the character (up to 1000 characters). The server generates four
   candidates in about 15 seconds; pick one. Generate again for others.
2. **Animate** creates the agent's animations from that portrait: idle,
   thinking, replying and working, one 4-second clip each, about 30 seconds
   per clip. The button shows what it costs at your provider ("4 animations ·
   28 credits"); each state shows its progress. You can save the agent with
   its portrait before the animations finish. A clip that failed shows
   **Failed**; **Retry failed** generates only those clips again.

Generation is stored per profile, so for a new agent **Generate portraits**
first creates the agent (with the bundled portrait chosen so far); saving
then edits that agent. Without an image service, **Generate** shows one line
saying portrait generation needs one, with **Open Settings** to set it up.

A generated agent shows its portrait wherever an agent appears and plays its
animations like Hermuse: thinking while it thinks, replying while it answers,
working while it searches, reads, codes or browses, idle while it waits for
you. A state without a clip falls back to the closest one, then to the
portrait. A clip the provider refuses is marked failed and is not retried
automatically (the credits may already be spent): animate that state again
when you want to. Removing the generated portrait brings back a bundled one.
The files live in the profile's `hermuse/avatar/` folder on the server.

## Activity

One row per task your agent ran: one request you made, or one scheduled run
(a reminder, a briefing, the heartbeat), from every surface (this app, the
web app, the CLI, Telegram, …). The Hermuse plugin titles and summarises each
task once it ends ("Set daily 8am briefing" — "Scheduled daily 8:00 AM Nantes
briefing"); a row shows the icon of the main tool it used, the title, the
summary and the time, newest first, grouped by day (**Today**, **Yesterday**,
the weekday, then the date). A row from the open chat or one of its side
chats opens that chat.

A task running now shows on top, under **Now**: your request (or the chat it
runs in), the agent's current step and a **Stop** button that interrupts it.

Tasks are kept on the server by the plugin (`/api/plugins/hermuse/tasks`), so
every device shows the same list; the tab refreshes when a turn ends and when
Hermes reports sessions written elsewhere. Without the plugin the tab stays
empty. Heartbeat runs that found nothing to tell you are not recorded.

In the chat itself, each tool call is a row with its icon, name, command or
query, duration and a check, or a red cross when it failed. A row that has
more opens on click: the full command, what it printed (the last 4,000
characters), Hermes' result line and why it failed (`Exit code 1`,
`Command denied by user`). After a reload Hermes no longer sends tool
outputs, so earlier rows show the command with a grey check: finished, but
not known to have worked.

## Approvals

The commands your agent wants to run and is waiting for you to allow:
**Approve this command?** cards nobody answered yet, in the main chat and its
side chats. A row opens the conversation; once you pick **Allow once**,
**Allow for this session**, **Always allow** or **Deny** (or Hermes gives up
waiting) the row goes away.

Requests appear automatically while you chat, including in side chats already
opened in this app session. Disconnecting hides unanswered cards until Hermes
confirms which requests are still pending on reconnect; it never approves
anything for you. After relaunch, open a previously unopened side chat to
recover its pending requests.

Which commands ask first is set in **Settings → Permissions** for the open
agent (Hermes' `approvals.mode`, written with `config.set`; it applies to the
next command, no restart needed):

| Choice | Value | What happens |
| --- | --- | --- |
| **Ask only when needed** (default) | `smart` | A small model judges each risky command; you are asked only when it is unsure. `rm -rf /tmp/test` usually runs without asking. |
| **Always ask for risky commands** | `manual` | Every command Hermes flags as risky (recursive delete, `sudo`, writes to system paths, …) asks you first. |
| **Never ask** | `off` | Nothing asks. |

## Upcoming

Everything scheduled for this agent, in sections: **Reminders** (one-shot,
with their date, "Oct 4, 9:15 AM"), **Daily**, **Weekly**, **Other
recurring** and **Heartbeat**. You create them by asking your agent, for
example:

> Remind me Saturday at 9 to call the plumber.
>
> Every day at 8 AM, send me a briefing.

The agent saves a real Hermes job that delivers into your main chat; it never
asks which platform to deliver to. The Hermuse plugin's own maintenance jobs
(daily feed, weekly ideas, goals check-in, nightly reflection) are not
listed. The list refreshes when the agent's scheduling tool finishes and when
the chat turn ends; changes are scoped to the current agent profile.

Tapping an item opens its sheet: the schedule in words (**Every weekday at
7:00 AM**), the next run, the **Run history** (time, how it went, and the
start of what it answered) and its actions:

- **Pause** / **Resume** stops or restarts the schedule.
- **Run now** runs it right away.
- **Delete** (after a confirmation) removes one of your items. The heartbeat
  cannot be deleted, only paused: the plugin registers it again whenever its
  schedule is turned on, and a pause sticks.

Schedule hours are the server's time zone, as the agent wrote them; the next
and past runs are shown in your device's time.

### Heartbeat

Every 30 minutes the agent reviews its memory, your goals and what is coming
up. It writes in the main chat only when something needs you ("your trip is
in 4 days and the flight is not booked"), often with quick replies to pick
from; otherwise it stays silent.

### The scheduler

Hermes runs scheduled jobs from its **gateway** (`hermes gateway`), which
servers set up by Hermuse run as a second service, `hermuse-gateway.service`
(**Scheduler** in the install steps). When no scheduler has ticked on that
Hermes, the tab says so: items then only run when you press **Run now**, until
the scheduler runs on that machine. Reminders and briefings arrive in the main
chat as agent messages, after a small **Scheduled: <name>** line.

## Identity

The agent's name with **Edit** (the agent editor: name, portrait, prompt),
then two cards:

- **SOUL** opens `SOUL.md`, the agent's persona, in a full-screen editor with
  a preview. It shapes every new conversation; saving writes the profile's
  `SOUL.md` on the server.
- **MEMORY** opens the agent's long-term memory: `MEMORY.md` (what it
  remembers about your life) and `USER.md` (your profile), one block per
  entry. Edit or delete entries, or **Add entry** (a new empty block, ready
  to type in), then **Save**; Hermes keeps them under
  `HERMES_HOME/memories/`. The card shows when the memory last changed. You
  can also ask your agent to forget something.

## Feed during chat

With the updated Hermuse plugin enabled, the agent is instructed to publish
useful discoveries, research results and completed-work summaries through
`feed_post`, respecting your feed prompt and proactive preferences. It should
not copy every reply into Feed or invent posts to fill an empty view.

A post's picture is the share image of its main source page (the picture a
link preview shows), copied onto your Hermes server when the post is written
and deleted with it. When there is none and image generation is set up with
**Illustrate Feed posts without an image** on, the post appears at once and an
illustration made from its title and "Why I created this" (no text, logos or
real people) is added a few seconds later. If generation fails, or the
option is off, the post stays without a picture.

Feed refreshes automatically after publication and at the end of a chat turn,
on both desktop and web. This requires working model credentials and the
plugin's tools; failed or unavailable tools do not create content. Scheduled
feed editions additionally require a running Hermes gateway.

## Connectors

Connectors live in **Settings → Connectors**. None are available yet; the
section says so.
