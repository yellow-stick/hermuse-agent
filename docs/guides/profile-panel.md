# Agents, Activity, Approvals and Automations

The profile panel sits on the right of the chat (the avatar at the top right
opens it on narrow windows). Under **Open computer** it has four tabs; the
desktop app and the web app show the same thing.

## Several agents on one Hermes

The **Agent** menu in the chat header switches agents without changing the
Hermes instance. Each agent is a real Hermes profile, with its own **SOUL
prompt**, main chat and side chats. The app remembers the selected agent and
the last conversation for each profile on this device.

- Choose **Create agent…** on desktop or **Add agent** on the web, pick a
  portrait, and edit the name and prompt before saving. Creating a profile
  uses the same server and shares its model credentials; it does not install
  another Hermes or generate an image.
- Choose **Edit agent…**, or click the pencil on the profile portrait, to
  change the selected agent's name, portrait and prompt. The editor loads
  that profile's saved prompt. Picking another portrait never replaces an
  existing agent's prompt.
- A saved prompt applies to **new conversations**. Existing conversations
  retain the system prompt Hermes already captured for them.

Hermuse keeps the original profile. Noah, Aya, Oscar, Iris, Rusty, Bao, Olive,
Mint and Nova are static portrait choices with editable starting prompts.
Only the original Hermuse profile, while using its original portrait, plays
the bundled activity animations. Reduced-motion preferences show its static
portrait instead.

Feed, Ideas, Goals, Library, Activity, Automations and the computer view
follow the selected profile. Update the Hermuse plugin on existing servers
before using these profile-scoped surfaces; older plugins do not isolate
their data by profile. Profiles separate agent state, not operating-system
permissions: they are not security sandboxes.

## Activity

One row per tool your agent finished in a chat: a web search, a page it
opened, a command it ran, an automation it created. Each row shows the tool,
what it worked on (the command, the search, the address; Hermes' one-line
result when the call names nothing) and the time, grouped by day (**Today**,
**Yesterday**, the weekday, then the date).

In the chat itself, each tool call is a row with its icon, name, command or
query, duration and a check, or a red cross when it failed. A row that has
more opens on click: the full command, what it printed (the last 4,000
characters), Hermes' result line and why it failed (`Exit code 1`,
`Command denied by user`). After a reload Hermes no longer sends tool
outputs, so earlier rows show the command with a grey check: finished, but
not known to have worked.

Activity is kept on this device (the app's local database, the browser's
storage for the web app), up to the last 500 rows per agent profile, and survives a
restart. It only records what happened while the app was open: a chat held on
another device or surface (CLI, Telegram, …) does not show up here. A row from
the open chat or one of its side chats opens that chat.

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

Which commands ask first is Hermes' setting `approvals.mode` in
`config.yaml`:

| Value | What happens |
| --- | --- |
| `smart` (Hermes' default) | A small model judges each risky command; you are asked only when it is unsure. `rm -rf /tmp/test` usually runs without asking. |
| `manual` | Every command Hermes flags as risky (recursive delete, `sudo`, writes to system paths, …) asks you first. |
| `off` | Nothing asks. |

To be asked every time, on the machine that runs Hermes (as the user that
runs it):

```bash
hermes config set approvals.mode manual
```

It applies to the next command, no restart needed.

## Automations

Every task Hermes runs on a schedule: the four of the Hermuse plugin (the
daily feed, the weekly ideas, the weekly goals check-in and the nightly
reflection) and the ones you created by asking your agent, for example:

> Every day at 6 PM, sum up my day.

The list refreshes when the agent's scheduling tool finishes and when the chat
turn ends, without closing and reopening the panel. Changes are scoped to the
current agent profile. A promise in chat is not an automation: the agent must
successfully save a real Hermes job.

Each row shows the schedule in words (**Every day at 6:00 PM**), the next run
and, once it ran, the last run and how it went (**OK**, **Failed** with the
reason, or **Not delivered**). The soonest next run comes first; paused
automations go last.

- **Pause** / **Resume** stops or restarts the schedule.
- **Run now** runs it right away and waits for the result.
- **Delete** (after a confirmation) removes one of your automations. The
  Hermuse ones cannot be deleted, only paused: the plugin registers them again
  whenever its schedule is turned on, and a pause sticks.

Schedule hours are the server's time zone, as the agent wrote them; the next
and last runs are shown in your device's time.

Hermes runs automations from its **gateway** (`hermes gateway`). When no
scheduler has ticked on that Hermes, the tab says so: automations then only run
when you press **Run now**, until the gateway runs on that machine.

## Feed during chat

With the updated Hermuse plugin enabled, the agent is instructed to publish
useful discoveries, research results and completed-work summaries through
`feed_post`, respecting your feed prompt and proactive preferences. It should
not copy every reply into Feed or invent posts to fill an empty view.

Feed refreshes automatically after publication and at the end of a chat turn,
on both desktop and web. This requires working model credentials and the
plugin's tools; failed or unavailable tools do not create content. Scheduled
feed editions additionally require a running Hermes gateway.

## Connectors

Coming soon.
