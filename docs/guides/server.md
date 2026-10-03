# Set up Hermuse with Hermes on a server

This guide connects Hermuse to a [Hermes Agent](https://github.com/NousResearch/hermes-agent)
that runs on a server (a VPS, a home server, a spare machine). Once it is done,
you chat with your agent from the Hermuse desktop app or the web app, and you
can watch and drive the agent's own computer from there.

There are two ways to start:

- **Hermes is not installed**: the desktop app can set up a supported Linux
  server over SSH, including HTTPS and the agent's computer.
- **Hermes is already installed**: connect with its dashboard URL and sign-in
  details. Keep your existing installation; use the manual steps below if its
  dashboard is not ready yet.

The web app connects to an existing dashboard; it does not provision servers
over SSH.

## Install on a server from the desktop app

### Server requirements

Use a server you administer, with:

- **Ubuntu 24.04 or 26.04, or Debian 12 or 13**, on **x86-64 or ARM64**.
  The installer requires a running **systemd** and APT; other distributions,
  containers without systemd and other architectures are not supported by this
  flow.
- At least **4 GB RAM** and **10 GiB free disk under `/home`**.
- SSH reachable from your desktop, with SFTP and either password authentication
  or an existing SSH key authorized for the SSH account.
- A root SSH login, or a non-root administrator who **already has passwordless
  sudo**. Hermuse checks `sudo -n`; it does not reuse the SSH password for sudo
  or grant the SSH user new sudo rights.
- A **public IPv4 address**, with incoming **TCP 80 and 443** reaching this
  server, and outbound access to package repositories, GitHub, `ghcr.io`,
  `api.ipify.org` and certificate services. The generated `sslip.io` hostname
  must resolve from your desktop and the internet.

Allow the SSH port and TCP 80/443 in your hosting provider's firewall or
security group before starting. Behind a router, configure port forwarding
for 80/443 to this server; the address detected by `api.ipify.org` must lead
back to it. **UFW changes on the server cannot open a provider firewall,
configure NAT or make a private/CGNAT server publicly reachable.** For an
IPv6-only server or one that cannot receive public HTTP/HTTPS traffic, use the
manual dashboard path below with an appropriate HTTPS endpoint instead.

The automatic flow refuses an active `firewalld` or `nftables` service rather
than replacing it. If UFW was removed but left configuration behind, restore
that firewall manually first. It also refuses an unrelated existing `hermes`
account, `/home/hermes` directory, managed-service path or Hermuse plugin
directory. Use the existing-server path for installations you already manage.

### Choose SSH setup and give permission

1. Choose **Connect to a machine** in the desktop app. The SSH form opens
   directly: Hermuse detects what is already installed after connecting, without
   asking you to classify the machine first. If you only have its dashboard URL,
   choose **Connect with a dashboard URL** instead and follow
   [Add your Hermes in Hermuse](#3-add-your-hermes-in-hermuse).
2. Enter **Host or IP address** (not a dashboard URL), **SSH port** (default
   `22`) and **SSH user** (default `root`). **SSH password (optional)** can be
   left blank if an SSH key is already set up for this machine.
3. Answer **Publish the web app on this server?** with **Yes** or **No**; there
   is no default. **Yes** also serves the [web app](web-app-and-relay.md) at
   its own HTTPS address, `https://app.hermuse.<public-ip-with-dashes>.sslip.io`,
   so you can open Hermuse in any browser on your phone or computer. It adds a
   second address and one more certificate to the server.
4. Choose **Review setup**. Read **Allow server setup?** before choosing
   **Agree and connect**: this authorizes system package installation, a
   dedicated Hermes account, Docker access, firewall changes and publication
   of a password-protected dashboard on the internet (and of the web app, if
   you answered **Yes**).
5. At **Verify the SSH host key**, compare the displayed **SHA-256
   fingerprint** with the server console or your administrator through a
   separate trusted channel. Choose **Accept fingerprint** only if it matches.
   No SSH credentials have been sent yet; declining installs nothing.
   Reconnects during setup use the same authentication method and that accepted
   host key; a changed host key stops setup before authentication.

**Your SSH password is never saved.** An entered password is used for SSH
password authentication only, not as a key passphrase or dashboard password.
To retry with a password, enter it again; to retry with your key, leave it blank.

With a blank password, Hermuse first checks the existing SSH agent exposed to
the desktop app through **`SSH_AUTH_SOCK`** on Linux/macOS, then the unencrypted
default private key files **`~/.ssh/id_ed25519`**, **`~/.ssh/id_ecdsa`** and
**`~/.ssh/id_rsa`**. On Windows, the default files are under
**`%USERPROFILE%\\.ssh`**; the Windows OpenSSH named-pipe agent is not supported.
Ed25519, ECDSA (NIST P-256/P-384/P-521) and RSA keys are supported; agent RSA
signatures use SHA-256, not legacy SHA-1.

Encrypted private keys must already be unlocked in your existing SSH agent;
Hermuse does not ask for a key passphrase or import, generate or install keys.
The app must inherit access to the agent socket (an agent configured only in
a separate terminal may not be visible). No usable key produces a setup error
with the option to unlock/load your key or enter an SSH password; Hermuse never
tries an empty SSH password. SSH configuration aliases, custom `IdentityFile`
paths, certificates, FIDO/security-key files, DSA and agent forwarding are not
supported by this flow. Keys and agent signatures are used only after you
accept the server fingerprint; the agent is never forwarded to the server.

Docker group membership gives the dedicated `hermes` account
**root-equivalent control of the server**, even though Hermes runs as a
non-root user. Only authorize this on a machine where you accept that level
of access for the agent. The installer does not add a sudoers entry for that
account.

### What Hermuse installs

SSH setup and Linux **Install on this computer** use the same account,
`/home/hermes/.hermes`, system service, provisioning engine and ownership journal.
There is no separate desktop-owned Linux backend. Local setup keeps the service
private; SSH setup adds the authenticated public access described below.
Installing locally after SSH setup preserves the existing public configuration.
Closing a desktop client never stops this system-managed service.

If the SSH login account has a legacy per-user Hermes installation and no
canonical instance exists, setup requests explicit migration approval before
provisioning it. The reviewed inventory must still match when migration starts.
A verified private data backup and the original home are retained; executable
trees are rebuilt from pinned sources. Existing canonical data is never merged:
when both homes exist, setup reuses the canonical instance and preserves the
legacy home. Unsafe paths, active legacy processes and existing computer-volume
references require manual resolution; see
[legacy migration](desktop.md#existing-per-user-installations).

**Setting up your server** shows the current step, completed steps and
technical output under **Show details**:

| Step | What happens |
| --- | --- |
| SSH connection and server requirements | Connect using the accepted host key, check the OS, memory, disk and administrator rights, then inspect the existing installation without changing it. Install only missing prerequisite packages. |
| Guarded firewall setup | Install UFW if missing, keep existing rules, add the SSH port (including the server-side port if forwarded) and TCP 80/443 when needed, then enable UFW. A fresh SSH login checks that access still works. |
| Dedicated Hermes account | Create the non-root `hermes` user with home `/home/hermes`; store Hermes and its data in `/home/hermes/.hermes`. |
| Hermes Agent | Reuse the exact pinned checkout only when its bootstrap marker and launcher also pass inspection. Otherwise download the pinned Hermes Agent **0.21.5** installer, verify its SHA-256 and repair its non-interactive installation stages as `hermes`. Model setup is left for onboarding. |
| Hermuse plugin and jobs | Upload the plugin bundled with the desktop app, enable it, and register the daily feed, weekly ideas, weekly goals check-in and nightly reflection jobs, plus the 30-minute heartbeat. |
| Docker and agent's computer | Install the distribution's `docker.io` if Docker is missing; start its system service and add `hermes` to the `docker` group. Download the computer image, or build it on the server if the pull fails, then start the computer and check that it is ready. |
| Dashboard account | Generate a new random password for dashboard user `admin`, store its hash in Hermes configuration, and start `hermuse-dashboard.service` as the `hermes` user. The dashboard binds only to `127.0.0.1:9119`. |
| Scheduler | Install and start `hermuse-gateway.service`, which runs `hermes gateway run` as the `hermes` user next to the dashboard. It is Hermes' scheduler: it runs every scheduled job (your reminders and briefings, the heartbeat, the plugin's jobs) and delivers their results into your main chat. |
| Web app | Only when you answered **Yes**, or kept from an earlier setup. Download `ghcr.io/yellow-stick/hermuse-web:<plugin version>` (the web app and its relay, matching the bundled plugin) and run it as container `hermuse-web`, read-only, bound to `127.0.0.1:9120`. The relay allows only this server's dashboard. Answering **No** on a rerun keeps a healthy existing web app; **Uninstall** removes it. |
| Caddy and public HTTPS | Install Caddy if missing, add a dedicated reverse-proxy site, and obtain HTTPS for `https://hermuse.<public-ip-with-dashes>.sslip.io`, plus `https://app.hermuse.<public-ip-with-dashes>.sslip.io` for the web app. The `hermuse.` prefix keeps other services on the bare IP hostname separate. No domain purchase is needed. |
| Final readiness checks | From your desktop, verify HTTPS, Hermes compatibility, password login, protected plugin access, all four jobs and the running computer, and, with the web app, that its relay reaches the dashboard, before reporting success. |

Each attempt first checks the **actual server**, not a saved local checklist.
Healthy installer-managed steps are marked **Already installed** together, before
repairs begin, and are not started again. Inspection checks the account/home,
installed prerequisite packages, both UFW address families, pinned Hermes source
and bootstrap marker, every bundled plugin file's SHA-256, enabled plugin and
current job definitions, Docker image/container/runtime state and a real CDP
response, and Caddy's adapted routes, exact managed site, validation and service
state. A marker alone is not enough. Missing or drifted owned pieces are repaired;
unrelated resources stop setup before replacement. A dependency repaired earlier
in this attempt is checked again before downstream installers are run, so a
current plugin or computer is not unnecessarily uploaded, downloaded or built.

Hermes inspection verifies the pinned entrypoint, exact installer-generated
launcher and Python target, then imports only the pinned lightweight version
module in isolated Python with bytecode writes disabled. It deliberately does
not run `hermes --version` or load CLI/config/banner startup paths, which can
self-repair or write update caches. Node and npm must also execute successfully:
an upstream bootstrap completion marker does not excuse missing dashboard build
tools. Full dashboard readiness is still exercised after repairs.

SSH trust/authentication, administrator and ownership guards always run for the
current session. A firewall change still requires a fresh pinned-key SSH login.
The dashboard sign-in handoff and final authenticated checks from your desktop
also run again. The existing hash-only dashboard account cannot recover its old
password: it is not marked ready before a new sign-in is established for this
attempt. This may restart the dashboard, but does not reinstall healthy packages,
Hermes, the plugin, Docker or Caddy.

Existing UFW rules, unrelated Caddy sites and existing wildcard imports are
preserved, not reset. A route already serving the dedicated Hermuse hostname
from unrelated configuration is refused, even if it uses the dashboard port.
The installer backs up firewall/Caddy configuration and arms server-side
restoration timers **before** changing them. Firewall changes are committed
only after a fresh SSH login with the accepted host key; the Caddy site is
committed only after the desktop verifies the public dashboard. Unsupported
custom Caddy configuration paths, symlinked configuration or an unrelated
file at the Hermuse site path stop setup instead of being overwritten.
The managed fragment is adapted independently and must contain only the dedicated
Hermuse hosts (the dashboard and, when published, the web app). Adding an
unrelated site to that file makes setup stop without changing it, even when the
original Hermuse blocks and managed header remain.

Setup and server uninstall share a kernel-held operation lock, so they cannot
change the same installation concurrently. A root-owned, nonsecret
`/var/lib/hermuse-provision/ownership.json` records which resources already
existed and identifies resources this installer created for safe later removal.
It is not a completion checklist and does not contain dashboard or SSH passwords;
every setup still proves health from the current server.

### Save the dashboard, then connect a model

After verification, **Your Hermes is ready** shows the dashboard address and
its account: user **`admin`** and the generated **dashboard password**, hidden
until you choose **Show**, with **Copy**. Keep it: you need it to connect to
this Hermes from another computer or from the web app. **Continue** opens the
normal connection form with the **HTTPS URL**, user and password filled
in. Give the instance a name and choose **Save and connect**. When the server
publishes the web app, the form also shows its address under **Web app**, with
**Open web app**. Hermuse verifies
the login before storing these dashboard credentials in the operating system's
secure credential store (the system keyring on Linux), not in the app database or a
plaintext fallback. If secure storage is unavailable or locked, resolve that
error before saving. On Linux Hermuse checks the keyring before this flow.

The generated dashboard password is separate from your SSH password. Until
you save the instance it remains only in this app flow; the server holds its
hash, not a new plaintext recovery file. Keep the connection form open until
saving succeeds. A retry that needs the dashboard credential handoff explicitly
establishes a new password for this installer-managed account; previous sign-in
details then stop working.

Once saved, the account stays readable in the app: **Instances** shows the
username and the hidden password, with **Show** and **Copy**, on the row of
every password instance whose password this app holds. The web app keeps a
password for the open tab only and shows it while it holds one.

Next, **What's on <name>** lists the installed components. Choose
**Continue** to set up a model provider; sign in to a provider or enter your
API key in the model onboarding. No model account is supplied by the server
installation. Once a model answers, continue to chat and
[try the agent's computer](#6-try-it). The list can be reopened under
**Instances → What's installed**.

### If SSH setup stops

A failed step shows **Setup stopped**, its error and **Try again**. Read
**Show details**, correct the cause, then retry with your SSH key or re-enter your
SSH password. Retrying or reopening setup first inspects the server and marks
proven healthy managed steps ready, even when a later repair is still pending.
Only incomplete or drifted owned components are repaired; unrelated accounts and
configuration are never taken over. Current-session safety checks, credential
handoff and final external readiness are not skipped.

**Cancel** closes SSH and prevents later steps from starting. Packages,
accounts, Docker data and other work already installed remain on the server:
this is not an uninstall. Uncommitted firewall and Caddy changes are restored
immediately when possible, or by their independent server-side timers if SSH
is lost (within **180 seconds** for the firewall and **600 seconds** for
Caddy). A successfully checked firewall change remains if a later step fails.
If a previous restoration is still pending, wait for it before retrying.

For a failure at **Caddy and public HTTPS** or **Final readiness checks**,
check the provider firewall, router/NAT, public IPv4 address and `sslip.io`
DNS—not just UFW. For the automatic install's dashboard logs, use
`sudo journalctl -u hermuse-dashboard`, and for the scheduler
`sudo journalctl -u hermuse-gateway`; computer image logs are in
`/home/hermes/.hermes/hermuse/computer/build.log`.

A failure at **Web app** is usually the image download from `ghcr.io`
(`sudo docker logs hermuse-web` once it runs); for the web address, check
`sslip.io` DNS and the certificate of `app.hermuse.<public-ip-with-dashes>.sslip.io`
like the dashboard's.

## Connect an existing Hermes server

The rest of this guide keeps the manual server setup and dashboard-based
installation path. You only need a terminal on the server for the first two
steps; everything after that is done from Hermuse.

### What you need

- A Linux server (Ubuntu 24.04 and Debian 13 are tested; x86-64 or ARM64) with
  at least 4 GB of RAM and 10 GB of free disk for the agent's computer.
- **Hermes Agent 0.21.5 or newer (0.21.x)**, installed for a normal user (not
  root).
- An HTTPS address for the Hermes dashboard, reachable from where you use
  Hermuse.
- Optional: `sudo` without a password for the Hermes user, so Hermuse can
  install Docker by itself. Without it, Hermuse shows you one command to paste.

## 1. Run the Hermes dashboard

Hermuse talks to Hermes through its **dashboard** (the native web UI, port
`9119` by default). Run it as a service so it survives reboots. As the Hermes
user, create `~/.config/systemd/user/hermes-dashboard.service`:

```ini
[Unit]
Description=Hermes Agent Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/.hermes
ExecStart=%h/.local/bin/hermes dashboard --port 9119 --host 127.0.0.1 --no-open
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now hermes-dashboard
sudo loginctl enable-linger "$USER"   # keep it running when you log out
```

Turn on the dashboard's **password login**. Hermes 0.21.5 has no command for
it yet; this snippet stores only a hash of the password in
`~/.hermes/config.yaml` and reads the password from your keyboard, so it never
lands in your shell history:

```bash
read -rs -p "Dashboard password: " PW; echo
printf %s "$PW" | ~/.hermes/hermes-agent/venv/bin/python -c '
import secrets, sys
sys.path.insert(0, sys.prefix + "/..")
from plugins.dashboard_auth.basic import hash_password
from hermes_cli.config import load_config, save_config
from hermes_cli.plugins_cmd import ensure_basic_auth_plugin_enabled_in_config
pw = sys.stdin.read().strip()
cfg = load_config()
auth = cfg.setdefault("dashboard", {}).setdefault("basic_auth", {})
auth.update(username="admin", password_hash=hash_password(pw), password="",
            secret=secrets.token_urlsafe(32))
ensure_basic_auth_plugin_enabled_in_config(cfg)
save_config(cfg)
print("Dashboard password set.")'
unset PW
systemctl --user restart hermes-dashboard
```

Hermuse signs in with the user name `admin` and that password. The password
stays between Hermuse and your Hermes.

Scheduled jobs need Hermes' scheduler, its **gateway**, running next to the
dashboard: reminders, briefings, the 30-minute heartbeat and the plugin's
jobs only fire while it runs, and it delivers their results into your main
chat. Run it the same way, as `~/.config/systemd/user/hermes-gateway.service`
with `ExecStart=%h/.local/bin/hermes gateway run` (same `[Unit]` and
`[Install]` sections, `Description=Hermes Agent Gateway`), then
`systemctl --user enable --now hermes-gateway`. Without it the **Upcoming**
tab says the scheduler is not running, and items only run from **Run now**.

## 2. Give the dashboard an HTTPS address

The dashboard listens on `127.0.0.1` only. Put it behind HTTPS with either:

- **Tailscale Funnel** (no domain or certificate to manage):

  ```bash
  tailscale funnel --bg --yes http://127.0.0.1:9119
  ```

- **Your reverse proxy** (Caddy, nginx, Traefik…) forwarding a domain to
  `127.0.0.1:9119`, WebSockets included.

Then tell Hermes its public address, otherwise it answers
`400 Invalid Host header` behind the proxy:

```bash
hermes config set dashboard.public_url https://hermes.example.com
systemctl --user restart hermes-dashboard
```

Check it from your own computer: `https://hermes.example.com/api/status` should
answer `200`.

## 3. Add your Hermes in Hermuse

In the Hermuse desktop app choose **Connect to a machine**, then **Connect with
a dashboard URL**; in the web app choose **Connect to a machine**. Enter:

- **Hermes URL**: the HTTPS address from step 2.
- **Name**: anything you like, for example `Home server`.
- Then the dashboard **user name and password**.

Using the web app? It reaches your Hermes through the Hermuse relay; see
[Web app and relay](web-app-and-relay.md) first.

## 4. Install Hermuse on your Hermes (one click)

Once your Hermes is saved, Hermuse shows **What's on <name>**: a checklist of
what it needs there, each part found in place, missing or waiting on another:
Hermes Agent itself, the **Hermuse plugin**, its **background jobs** (daily
feed, weekly ideas, weekly goals check-in, nightly reflection), **Docker**, the
**agent's computer** and a **model provider**. You find it again under
**Instances → What's installed**.

Click **Install** on a row, or **Install everything missing** when several
parts are. Hermuse installs through the Hermes dashboard and the plugin, with
no shell on the server; a part that needs another (the jobs, Docker and the
computer need the plugin) keeps its button off until it is there.

Hermes reviews every plugin before installing it. Because the plugin can
install Docker with `sudo`, Hermes flags it for confirmation, and Hermuse shows
**Hermuse needs permission to install Docker with sudo on this server** with
the review report. Click **Allow and install**. The plugin runs right away, no
dashboard restart needed.

When only the server can do a step, the row shows the command with a **Copy**
button, then **Check again** once you ran it: installing Docker when the Hermes
user has no `sudo` without a password (step 5), or restarting the dashboard
when the plugin does not answer yet. The command is the one that works on that
server: Hermuse reads which systemd service runs the dashboard through its
own (signed-in) file API, so a server set up by the desktop app gets
`sudo systemctl restart hermuse-dashboard` and the user service of step 1
`systemctl --user restart hermes-dashboard`. When the server does not tell,
both are shown, each labelled. A failed install says why and offers **Try
again**.

**Update** replaces an older plugin. The dashboard runs the plugin it loaded
until it restarts, so Hermuse then restarts it through the running plugin
(plugin 0.3.0 and later; the dashboard keeps its process ID, so systemd and a
dashboard started by hand keep it), shows **Restarting the Hermes
dashboard…** and checks again once it answers. A plugin older than 0.3.0
cannot restart it: the row gives the restart command instead.

**Continue** opens the chat once a model provider answers, the model setup
before that.

## 5. The agent's computer gets ready

The agent's browser and desktop run in a Docker container on your server.
Open **Open computer** in the profile panel to follow the progress:

| You see | What happens |
| --- | --- |
| `Installing Docker…` | Hermuse installs Docker (needs `sudo` without a password). |
| `Downloading the computer image…` | The ready-made image (about 470 MB) is downloaded from `ghcr.io/yellow-stick/hermuse-computer`. |
| `Building the computer image…` | The download failed, so the image is built on the server (a few minutes). |
| A command with a **Copy** button | Hermuse could not install Docker itself. Paste the command in a terminal on the server; Hermuse notices when Docker is ready. |
| The live screen | Done. |

The command Hermuse shows when it cannot install Docker is:

```bash
curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker <your Hermes user>
```

Adding the Hermes user to `docker` gives that user root-equivalent control of
the server. Grant it only if you accept that level of access for the agent.

After Docker is installed, restart the Hermes services once (or reboot) so they
pick up the `docker` group. Until then everything works, but each Docker call
goes through `sg docker` and writes a line to the system journal:

```bash
sudo systemctl restart user@$(id -u)
```

## 6. Try it

Send your agent something that needs the web, for example:

> Plan a walk in Nantes for me: open OpenStreetMap centered on the Château des
> ducs de Bretagne, then open the Wikipedia page of the château in a new tab,
> and give me 3 things to see nearby.

A **Browser** card appears at the top of the answer with a live picture of the
agent's screen. See [The agent's computer](agent-computer.md) for everything
you can do with it.

Then ask for something later:

> Remind me in 5 minutes to stretch.

The reminder shows under **Upcoming** in the profile panel. When it fires, a
small **Scheduled: <name>** line and the agent's message arrive in your main
chat, whichever app is open, or the next time you open it. The heartbeat
writes there too, only when something needs you. See
[the profile panel](profile-panel.md#upcoming).

## Without the one-click install

**Server set up by the desktop app**: run **Connect to a machine** again. It
uploads the plugin bundled with the app, restarts `hermuse-dashboard` and
checks everything. Hermes runs there as the `hermes` user; to check it by
hand, sign in with your administrator account:

```bash
sudo -iu hermes hermes hermuse doctor
sudo systemctl restart hermuse-dashboard
```

**Hermes installed by hand** (step 1): as the user that runs Hermes, on the
server, from a checkout of this repository:

```bash
cp -r hermes-plugin/hermuse ~/.hermes/plugins/hermuse
hermes plugins enable hermuse
hermes hermuse enable            # background jobs
hermes hermuse computer setup    # the agent's computer
hermes hermuse doctor
systemctl --user restart hermes-dashboard
```

`hermes hermuse computer setup` exits with `3` when Docker is missing and `4`
when Docker is installed but not running. The full reference is in the
[plugin README](../../hermes-plugin/hermuse/README.md).

## Use your subscriptions

The **Model accounts** page of a server instance (desktop, web and mobile
apps) opens on every sign-in the subscription bridge (CLIProxyAPI) offers:
**Claude Code** (Claude Pro/Max), **Codex** (ChatGPT), **Muse Code** (Meta),
**Antigravity**, **Kimi**, **Kimi.ai**, **Devin** and **Grok**. The bridge is
run by the Hermuse plugin next to Hermes on the server, and the sign-in
happens there: nothing is installed or kept on your computer. The bridge needs
no root and listens on the server's `127.0.0.1` only; it is downloaded from
GitHub on first use (a pinned, checksum-verified release, Linux x86-64 or
ARM64). Hermes is then pointed at it, and **Disconnect** removes the account
from the server.

To sign in, open the link the row shows and approve in your browser:

- **Muse Code**, **Grok** and **Kimi** show a code to enter on that page;
  the row turns connected once you approve.
- The others end on a `http://localhost:…` page that does not load: your
  browser tries to return to your own computer, not to the server. Copy the
  address of that page, paste it in the row and choose **Finish**. A sign-in
  waits for its address about five minutes; after that, start it again.

This needs the Hermuse plugin 0.4.0 or later: with an older one these rows
offer **Update plugin**, which opens the instance's **What's installed** where
the update runs (accounts signed in with plugin 0.3.0 keep working). Using a
consumer subscription outside its official clients may breach the vendor's
terms: personal use only.

## Use your own endpoint

Any server that speaks the OpenAI chat API (LiteLLM, vLLM, Ollama, LM Studio,
a company gateway, …) or the Anthropic messages API can serve your Hermes. On
**Model accounts**, under **Your own endpoint**, choose **Add a connection**:

1. Pick the **API type**: **OpenAI-compatible**, **Anthropic-compatible**, or
   **Auto-detect** to let Hermes find out. Enter a name, the base URL (for
   example `https://llm.example.com/v1`) and the API key, then **Check**.
   Hermes reaches the endpoint from the server, lists its models and tries
   the route the API type uses; a refusal is shown in Hermes' words.
2. Pick the default model among the models found (or type its id when the
   endpoint lists none), then **Add**.

The connection then shows under **Connected** with its API type, its default
model and how many models it serves. **Manage** lists them and picks the two
offered in the chat's model menu (a large and a small one); **Use as default**
makes the large one Hermes' default model for new chats and the small one the
model of its side tasks (titles, approvals, summaries). When Hermes warns
about a model (an expensive one, or a tier that trains on your data) it says
why and asks before switching. The key is stored by Hermes on the server, not
in the app.

## Troubleshooting

- **`400 Invalid Host header`**: set `dashboard.public_url` (step 2).
- **The install button answers `Security scan blocked plugin install`**: that
  is the confirmation step; click **Allow and install**.
- **`Docker is installed but not running`**: `sudo systemctl enable --now docker`.
- **`Hermes may not use it`** (Docker): add the user that runs Hermes to the
  `docker` group, `sudo usermod -aG docker hermes` on a server set up by the
  desktop app; the plugin reaches Docker through `sg docker` until Hermes
  restarts.
- **The agent answers "Retrying in 10 min"**: your model provider refused the
  request (quota or rate limit). Switch model for this chat with
  `/model <name>`, or wait.
- **Logs**: `~/.hermes/hermuse/computer/build.log` for the image,
  `~/.hermes/hermuse/bridge/cliproxy.log` for the subscription bridge,
  `journalctl --user -u hermes-dashboard` for the dashboard of step 1
  (`sudo journalctl -u hermuse-dashboard` on a server set up by the desktop
  app).
