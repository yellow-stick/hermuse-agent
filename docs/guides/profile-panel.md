# Activity, Approvals and Automations

The profile panel sits on the right of the chat (the avatar at the top right
opens it on narrow windows). Under **Open computer** it has four tabs; the
desktop app and the web app show the same thing.

## Activity

One row per tool your agent finished in a chat: a web search, a page it
opened, a command it ran, an automation it created. Each row shows the tool,
Hermes' one-line result and the time, grouped by day (**Today**,
**Yesterday**, the weekday, then the date).

Activity is kept on this device (the app's local database, the browser's
storage for the web app), up to the last 500 rows per Hermes, and survives a
restart. It only records what happened while the app was open: a chat held on
another device or surface (CLI, Telegram, …) does not show up here. A row from
the open chat or one of its side chats opens that chat.

## Approvals

The commands your agent wants to run and is waiting for you to allow:
**Approve this command?** cards nobody answered yet, in the main chat and its
side chats. A row opens the conversation; once you pick **Allow once**,
**Allow for this session**, **Always allow** or **Deny** (or Hermes gives up
waiting) the row goes away.

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
reflection, tagged **Hermuse**) and the ones you created by asking your
agent, for example:

> Every day at 6 PM, sum up my day.

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

## Connectors

Coming soon.
