# Set up Hermuse with Hermes on a server

This guide connects Hermuse to a [Hermes Agent](https://github.com/NousResearch/hermes-agent)
that runs on a server (a VPS, a home server, a spare machine). Once it is done,
you chat with your agent from the Hermuse desktop app or the web app, and you
can watch and drive the agent's own computer from there.

You only need a terminal on the server for the first two steps. Everything
after that is done from Hermuse.

## What you need

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

In the Hermuse desktop app choose **Connect to a Hermes**; in the web app choose
**Add a Hermes**. Enter:

- **Hermes URL**: the HTTPS address from step 2.
- **Name**: anything you like, for example `Home server`.
- Then the dashboard **user name and password**.

Using the web app? It reaches your Hermes through the Hermuse relay; see
[Web app and relay](web-app-and-relay.md) first.

## 4. Install Hermuse on your Hermes (one click)

The first time you open Feed, Ideas, Goals or the agent's computer, Hermuse
offers **Install Hermuse on this Hermes**. Click it. Hermuse asks Hermes to
install the `hermuse` plugin from this repository, with no shell on the server.

Hermes reviews every plugin before installing it. Because the plugin can
install Docker with `sudo`, Hermes flags it for confirmation, and Hermuse shows
**Hermuse needs permission to install Docker with sudo on this server** with
the review report. Click **Allow and install**.

Hermuse then, on its own:

1. enables the plugin (no dashboard restart needed);
2. schedules the background jobs: daily feed, weekly ideas, weekly goals
   check-in and nightly reflection;
3. prepares the agent's computer (next step).

If Hermuse says **Restart the Hermes dashboard to finish installing Hermuse**,
run `systemctl --user restart hermes-dashboard` and click **Check again**.

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

## Without the one-click install

On the server, from a checkout of this repository:

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

## Troubleshooting

- **`400 Invalid Host header`**: set `dashboard.public_url` (step 2).
- **The install button answers `Security scan blocked plugin install`**: that
  is the confirmation step; click **Allow and install**.
- **`Docker is installed but not running`**: `sudo systemctl enable --now docker`.
- **The agent answers "Retrying in 10 min"**: your model provider refused the
  request (quota or rate limit). Switch model for this chat with
  `/model <name>`, or wait.
- **Logs**: `~/.hermes/hermuse/computer/build.log` for the image,
  `journalctl --user -u hermes-dashboard` for the dashboard.
