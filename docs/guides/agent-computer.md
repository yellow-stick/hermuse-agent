# The agent's computer

Your Hermes agent has its own computer: a Linux desktop with Chromium, running
in a Docker container next to Hermes. When the agent browses the web, it does
it there, and Hermuse shows you its screen live. You can take the mouse and
keyboard at any time, then hand them back.

Setting it up is covered in [Set up Hermuse with Hermes on a server](server.md)
and [Run Hermes on your computer](desktop.md).

## The Browser card

When the agent uses its browser, a **Browser** card appears at the top of its
answer:

- while it works: a blue globe, the current step (`Opening en.wikipedia.org`,
  `Clicking`, `Typing`, `Reading page`…), a live thumbnail and **Open browser**;
- once done: a green globe, `Completed · <chat title>`, the last screen it saw
  and **Open preview**.

The card stays in the chat after a reload, with the screen as it was at the
end of the task.

![A finished answer with its Browser card](../readme/browser-card.jpg)

## The live viewer

**Open browser**, **Open preview**, or **Open computer** in the profile panel
opens the viewer in place of the chat:

- the header shows what the agent is doing (`Working · <site>`) or the task it
  finished;
- one tab per open browser window, with a raised active tab; scroll the strip
  horizontally when there are more windows than fit, click a tab to bring it
  to the front, or its × to close it;
- **Stop** (while the agent works) interrupts the current answer;
- the × at the top right goes back to the chat.

The viewer follows your light or dark theme. **Take control of the browser**
and **Done** use Hermuse's yellow primary color; **Browser | Desktop** stays
neutral. On narrow screens, the controls wrap below the title.

![The viewer showing the agent's browser](../readme/computer-browser.jpg)

## Take control

Click **Take control of the browser**. The header turns into **You're in
control**: your clicks, scrolls and keys go to the agent's computer, for
example to log in to a site, solve a captcha or accept cookies. The agent
cannot use its browser meanwhile; if it tries, it is told you have control and
waits.

Click **Done** to hand control back. Closing the viewer hands it back too.

If you take control from a second device, the latest one wins, and the first
one shows **Controlled from another device**.

![You're in control](../readme/computer-take-control.jpg)

## Browser or Desktop

The **Browser | Desktop** switch changes what you see:

- **Browser** shows only the Chromium window;
- **Desktop** shows the whole Linux desktop (XFCE): taskbar, other windows,
  terminal.

![The agent's full desktop](../readme/computer-desktop.jpg)

## Good to know

- **Logins stay.** The computer's home folder lives in a Docker volume, so
  sites you log into stay logged in, like on your own computer. Each Hermes
  profile has its own computer and its own volume.
- **Nothing is exposed.** The container only listens on `127.0.0.1` of the
  Hermes host. Its screen reaches you through the Hermes dashboard, behind the
  dashboard's login, over a one-time ticket per connection.
- **Isolation.** Chromium runs inside the container without Linux privileges
  (`--cap-drop ALL`, `no-new-privileges`, memory and process limits). The
  container, not Chromium's own sandbox, is the security boundary.
- **Resources.** Idle, the computer uses almost no CPU; the screen is only
  captured while someone watches. Plan about 1 GB of RAM while it browses.
- **Docker group.** On Linux, the Hermes user is added to the `docker` group so
  it can start the container. Members of that group can control Docker, which
  amounts to root on that machine: run Hermes under a user you trust with it.

## When the screen does not show

The viewer tells you what is missing:

| Message | What to do |
| --- | --- |
| `Docker is not installed on the Hermes computer.` + a command | Paste the command on the Hermes host, or install Docker Desktop on macOS/Windows. |
| `Docker is installed but not running. Start Docker to continue.` | Start Docker (`sudo systemctl start docker`, or open Docker Desktop). |
| `Preparing the agent's computer…` / `Downloading the computer image…` | Wait: the first start downloads about 470 MB. |
| An error with **Retry** | Retry. If it fails again, read `/home/hermes/.hermes/hermuse/computer/build.log` for app-managed Linux installations, or `$HERMES_HOME/hermuse/computer/build.log` on other hosts. |
| `Install the Hermuse plugin on this Hermes to see its browser.` | Install Hermuse on that Hermes (see the setup guides). |

From a terminal on the host:

```bash
hermes hermuse computer status
hermes hermuse computer start
hermes hermuse computer stop
```
