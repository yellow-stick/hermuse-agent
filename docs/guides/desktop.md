# Run Hermes on your computer with the desktop app

The Hermuse Agent desktop app works with Hermes Agent: it can install Hermes
Agent on your computer, keep it running, and add Hermuse to it. Nothing leaves
your computer except the requests to the AI models you connect.

To use a Hermes that runs on a server instead, see
[Set up Hermuse with Hermes on a server](server.md).

## Download for Linux

The Linux release comes as two files on the
[releases page](https://github.com/yellow-stick/hermuse-agent/releases). Pick
one:

- `hermuse-agent_0.1.0-1_amd64.deb`: installs Hermuse Agent with a menu entry;
- `Hermuse-Agent-0.1.0-linux-x86_64.AppImage`: one file you run without
  installing.

It runs on **Ubuntu 22.04, 24.04 and 26.04 LTS**, **Debian 12 and 13**, and
their derivatives on the same bases, such as Pop!\_OS and Linux Mint, on
**x86_64 (amd64)** only. Fedora, Arch and ARM64 are not supported by this
release. You need a regular desktop session: systemd, a D-Bus session bus and
the dialog your desktop shows when an app asks for the administrator password
(polkit).

### Check the download

Put `SHA256SUMS.txt` from the same release next to the file, then:

```bash
sha256sum -c --ignore-missing SHA256SUMS.txt
gh attestation verify hermuse-agent_0.1.0-1_amd64.deb --repo yellow-stick/hermuse-agent
```

The second command, with the [GitHub CLI](https://cli.github.com/), checks
that the file was built by this repository's release workflow. The release also
has `VERSION.json` (the versions inside the build) and the corresponding
sources.

### Install the `.deb`

```bash
sudo apt install ./hermuse-agent_0.1.0-1_amd64.deb
```

APT installs the system libraries it needs. Hermuse Agent then appears in your
applications menu; `hermuse-agent` also starts it from a terminal. To update,
install the newer `.deb` the same way.

### Or run the AppImage

Mark the file as executable (in the file manager: **Properties** → **Allow
executing as program**, or `chmod +x` in a terminal), then open it. No FUSE
setup is needed: at each launch the AppImage unpacks itself into a temporary
folder and removes it when the app closes, so keep about 210 MB free there. The
AppImage uses X11; on a Wayland desktop it runs through XWayland. To update,
replace the file with the newer one.

## What you need

- 8 GB of RAM or more, and a network connection during the setup.
- On Linux, nothing else: the first launch prepares what is missing (see
  below).
- On macOS: `git`, `curl` and `tar` (Hermuse tells you the exact command if one
  is missing). On Windows the installer fetches what it needs.
- For the agent's computer: **Docker**. On macOS and Windows install
  [Docker Desktop](https://docs.docker.com/get-started/get-docker/). Hermuse
  works without it, but then the agent has no browser you can watch.

## 1. Install Hermes

Open Hermuse Agent and choose **Install Hermes on this computer**.

### On Linux

Hermuse Agent first checks this computer and shows **Prepare this computer**
with the changes it needs. It lists only what is missing:

- the system packages Hermes Agent needs to build (`git`, `curl`, `tar`,
  `build-essential`, `python3-dev`, `libffi-dev`, `libatomic1`, `ripgrep`,
  `ffmpeg`);
- a system keyring (`gnome-keyring`), only when none is installed;
- Docker (the distribution's `docker.io`), only when there is no Docker at all
  on this computer, then starting it and adding you to the `docker` group.
  Members of the `docker` group control Docker without a password, which gives
  them **root-equivalent access** to this computer; the list says so before
  you accept.

Choose **Prepare**: your system asks **once** for the administrator password.
If you cancel or refuse, nothing is reported as done; steps that did finish are
listed under **Already done**, and **Prepare** stays available. Closing the app
or choosing **Cancel** never interrupts a package install: it finishes the
current step and stops before the next one.

A Docker you already have is used as it is: Docker CE, a rootless Docker or a
stopped service (Hermuse only offers to start it). It is never replaced, and
its containers, images, volumes and settings are left alone. If your Docker
context points to another machine, **Use this computer's Docker** makes only
the Hermes started by Hermuse Agent use the local Docker; your context stays
as it is.

Hermuse Agent keeps credentials only in the system keyring, never in plain
text. If the keyring is locked, unlock it when your system asks, then choose
**Check again**. **Connect to a Hermes** (a Hermes on a server) also checks the
keyring first, but installs neither Hermes nor Docker.

Then Hermuse Agent:

1. uses a Hermes Agent already installed if it is compatible (0.21.5 or a
   later 0.21 release). An incompatible one is left untouched: update or remove
   it yourself, then choose **Check again**;
2. otherwise installs Hermes Agent 0.21.5 into `~/.hermes` (`$HERMES_HOME` if
   set), showing each step. Its Python, uv and Node live in `~/.hermes/runtime`;
   your `~/.local/bin` and shell startup files are not changed. If the install
   stops (app closed, network down), the next launch resumes where it stopped,
   and **Retry this stage** repeats only the failed step;
3. starts Hermes, installs and enables the `hermuse` plugin, checks the bridge
   for your subscriptions, and prepares the agent's computer: it downloads the
   computer image from GitHub's registry (about 470 MB), starts it and checks
   that it answers before saying it is ready.

The setup downloads from your distribution's package repositories, GitHub and
`ghcr.io`.

### On macOS and Windows

Hermuse:

1. looks for a Hermes already installed and uses it if it finds one;
2. otherwise checks the prerequisites and runs the official Hermes installer
   (`install.sh`, or `install.ps1` on Windows), showing each step;
3. starts Hermes and keeps it running while Hermuse is open.

## 2. Install Hermuse on it

On Linux the preparation above already did this step.

On macOS and Windows, open Feed, Ideas or Goals: Hermuse offers **Install the
plugin**. It copies the `hermuse` plugin bundled with the app into Hermes,
enables it, schedules the background jobs and prepares the agent's computer.

If Docker is missing or stopped, a note appears under the page:

- **Install Docker to let Hermuse show the agent's browser.** with a **Get
  Docker** button;
- **Start Docker to let Hermuse show the agent's browser.**

Install or start Docker; the next time you open the agent's computer, Hermuse
finishes the setup. The first start downloads the computer image (about
470 MB). On Linux the note offers **Set up Docker**, which reopens the
preparation.

## 3. Connect your models

In **Connections**, add the AI accounts and subscriptions you already have.
Hermuse Agent does not come with a model account: you sign in or enter your
API keys yourself. Then send your agent a first task, for example:

> Plan a walk in Nantes for me: open OpenStreetMap centered on the Château des
> ducs de Bretagne, then open the Wikipedia page of the château in a new tab,
> and give me 3 things to see nearby.

See [The agent's computer](agent-computer.md) for the live viewer and **Take
control**.

## Your data on Linux

| What | Where |
| --- | --- |
| App data (local database, install progress) | `~/.local/share/com.yellowstick.hermuse_app/` |
| Hermes Agent, its runtime and the Hermuse data | `~/.hermes` |
| Credentials | your system keyring |
| The agent's computer | Docker container `hermuse-computer-hermes` and volume `hermuse-computer-hermes-home` (named after the last folder of `~/.hermes`) |

Updating, `sudo apt remove hermuse-agent` and `sudo apt purge hermuse-agent`
remove only the app itself (`/opt/hermuse-agent`, the `hermuse-agent` command,
the menu entry and icons). Everything in the table stays, and so do the system
packages installed during the preparation. Deleting the AppImage works the same
way. To remove your data too, delete these yourself.
