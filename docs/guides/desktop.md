# Run Hermes on your computer with the desktop app

The Hermuse Agent desktop app works with Hermes Agent: it can install Hermes
Agent on your computer, keep it running, and add Hermuse to it. Nothing leaves
your computer except the requests to the AI models you connect.

To install Hermes and Hermuse on a server over SSH, or connect to a server
where Hermes already runs, see
[Set up Hermuse with Hermes on a server](server.md). The server requirements
are separate from the desktop app requirements below.

## Settings and instances

The menu button at the bottom of the navigation rail opens a pop-over:

- **Settings** opens appearance and account preferences. Choose **System**,
  **Light** or **Dark**; the choice applies immediately and is saved on this
  device. **Dark** is the default, including during startup. **System** follows
  your operating system's appearance only when explicitly selected.
- **Instances** opens the existing Hermes instance management page.

On narrow windows, the same menu is in the bottom navigation. Closing Settings
returns to the chat without discarding its draft. The **Yellow Stick account**
section is marked **Work in progress**: its sign-in button is disabled, and no
Yellow Stick account is needed to use Hermuse.

## Remove a server installation over SSH

In **Connect to a machine** (the server SSH setup form), choose **Uninstall
Hermes from a server**: it works even if setup stopped partway through and no
connection was saved. For a server already in **Hermes instances**, open the
**More actions** menu (**⋯**) of its row and choose **Uninstall from server…**.
This removes the server installation, not the desktop app, and not the saved
connection: **Remove from Hermuse** in the same menu forgets that one without
touching the server.

Enter the SSH host, port and a root or passwordless-sudo administrator account,
not the dedicated `hermes` account being removed. Use an SSH password or leave
it blank to use an existing key on your computer. As during installation, accept
the server's SSH fingerprint only after verifying its identity. Inspection is
read-only and closes its SSH connection. The confirmation reconnects with that
same pinned host key and checks that the inspected resources have not changed.

The preview lists what can be removed and what must be preserved, with a reason
for each. Choose explicitly:

- **Uninstall and keep data** stops/disables the exact managed dashboard service,
  removes proven managed runtimes, the Hermuse plugin and its background jobs,
  and the identified agent-computer container. It keeps configuration,
  credentials, sessions, Feed/Ideas/Goals data, caches, the computer's named home
  volume and the dedicated account. Only Hermuse plugin references and
  browser settings with a known original absence are removed from configuration;
  unrelated settings and jobs are preserved.
- **Uninstall and purge data** additionally removes only proven owned
  configuration/data/cache directories and an unshared, proven owned computer
  home volume. The dedicated account is removed only if its original UID/home
  identity is known, no processes or other services use it, and its home can be
  made empty without removing unrelated files. Modified shell startup files,
  extra home files, other service usage and unproven caches keep the account.

Removal never resets the firewall, prunes Docker, or deletes a shared broker,
another Caddy site or a preexisting system installation. Only an exact
manifest-matched Caddy fragment with the installer's internal route marker can
be removed. An exact import is removed only when its insertion was recorded;
preexisting imports retain an empty owned fragment so Caddy stays valid.
Unrelated imports/sites are left as they are, and Caddy validation failures
restore the changed configuration bytes.

Firewall reversal uses the recorded exact UFW additions and prior activation,
not a stale complete ruleset. A previously inactive firewall is disabled only
while its committed configuration is unchanged. If another administrator
changed it, active SSH ingress and potentially shared HTTP/HTTPS rules remain,
with an explanation. System packages, Docker/Caddy installations and Caddy
certificate storage are retained even if setup installed them: package origin
alone does not prove exclusive use.

Older installations without precise provenance are handled conservatively:
known managed service/plugin/checkout/container resources can be removed, but
unproven runtimes, data, volumes, accounts, firewall additions and Caddy routes
are retained and reported as **partial removal**, never as fully reversed.
An interrupted installation can also leave an unbound resource that must be
preserved. A nonsecret root-owned ownership audit remains under
`/var/lib/hermuse-provision/ownership.json` after normal removal or purge, so
another inspection and later purge do not lose the ownership evidence.

Setup and removal exclude each other with a process-held SSH/kernel lock;
pending firewall/Caddy rollback transactions also block removal. **Cancel**
closes the transport and stops later work; already completed removals are not
rolled back. After a failure, cancellation or partial removal, choose
**Inspect remaining resources** before confirming a retry.

The saved connection and its app-side credentials are retained in both modes.
Deleting that saved connection is a separate action.

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

On every system the installer is the official script of Hermes Agent 0.21.5
(`install.sh`, or `install.ps1` on Windows). Hermuse Agent downloads it from
GitHub (`raw.githubusercontent.com`, else `api.github.com`), tries again for
about a minute and a half while GitHub is busy, and runs it only if its SHA-256
matches the one built into the app.

### On Linux

Linux uses the same managed installation as [SSH setup](server.md): a dedicated
non-root `hermes` account, `/home/hermes/.hermes`, and
`hermuse-dashboard.service`. The desktop connects to `http://127.0.0.1:9119`
with a private token for a new installation, or the existing dashboard account
when that service already requires sign-in. Closing the app does **not** stop
Hermes, its scheduled jobs or the agent's computer.

**Set up this computer** first checks the desktop keyring and existing
installation. An existing canonical service takes the connection-only path
below. A new installation asks for administrator authorization and runs a
release-bound helper with the bundled plugin; it does not execute a script
supplied by the desktop. The shared installer prepares only its owned resources:

- missing system build packages and the pinned Hermes Agent **0.21.5** runtime;
- the dedicated account, plugin and four background jobs;
- the system Docker service and the agent's computer;
- the loopback dashboard service and authenticated readiness.

Docker access is granted to **`hermes`**, not your desktop account. Membership
of the `docker` group gives that account **root-equivalent access**. Existing
system Docker packages and unrelated containers, volumes and settings are
preserved; this service does not use your desktop's Docker context or rootless
daemon.

Local setup does **not** install or configure UFW, Caddy, a public hostname or
the web app. If SSH setup already created the canonical installation, local
setup reuses it without changing its dashboard password or public exposure.
Conversely, SSH setup can add authenticated HTTPS to the same installation.

An existing canonical service is connected without reinstalling its runtime,
plugin, jobs or agent's computer:

- If its dashboard already requires sign-in, **Connect to this computer**
  opens the normal dashboard login, fixed to `http://127.0.0.1:9119`. Enter the
  existing dashboard account, not your Linux administrator password. The username
  is prefilled with `admin`; change it if the dashboard uses another account.
  An empty username is rejected before any sign-in request. This path asks for
  no administrator authorization and does not restart the service or change its
  password, public URL, configuration or plugin.
- Otherwise, administrator authorization permits only connecting to the exact
  running canonical service. Its private token is reused, or established with
  the service's credential-file reference when absent. That first authorization
  can restart the dashboard once; healthy token reuse does not restart it.
- Unknown service definitions or unsafe resources are refused, not silently
  adopted. An unmanaged plugin does not block connection and remains unmanaged.
  Deliberately preparing additional components still uses the installer's
  ownership guards; do not fabricate markers to bypass them.

The dashboard password or private token is saved in the system keyring only
after authenticated access succeeds. The saved connection is **This computer**,
not a second remote installation. Once registered, ordinary app launches need
neither administrator authorization nor a dashboard restart. If the keyring is
locked, unlock it and choose **Check again**. Connecting to another machine
checks the keyring but does not install Hermes or Docker locally.

Cancellation stops before the next installation command; an active system
package transaction is allowed to finish. Completed stages remain available
for repair on the next attempt. Downloads come from the distribution's package
repositories, GitHub and `ghcr.io`.

#### Existing per-user installations

If only a legacy `~/.hermes` installation exists, setup asks you to review and
approve a migration before changing it. The review identifies the source,
canonical destination and private backup. Approval is bound to that exact
inventory: changed data requires a new review.

The installer verifies a root-only data backup under
`/var/lib/hermuse-provision/migration-<revision>/backup`, copies supported data
and credentials, and **retains the original**. Reproducible executable trees
are excluded from the backup and rebuilt from pinned sources; model caches,
profiles, conversations and schedules are preserved. Supported desktop
subscription credentials move to the plugin-managed bridge.
Migration stages the verified copy in a root-only directory under `/home` before
the atomic cutover. A separately mounted `/home/hermes` is refused: staging and
the canonical home must share a filesystem.

Existing canonical data is never merged or overwritten. When both installations
exist, setup reuses the canonical service and leaves the legacy home alone.
Active legacy processes, unsafe links, external data paths and unsupported
credential layouts stop migration with a reason. An existing agent-computer
runtime requires explicit volume export and manual restore before migration:
the installer does not guess ownership or replace its Docker volume.

Keep both the original and verified backup until you have checked the migrated
installation. Canceling the review leaves the source untouched.

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

In **Hermes instances** (bottom-left menu → **Instances**), choose
**Model accounts** on your Hermes and add the AI accounts and subscriptions you
already have, or your own OpenAI- or Anthropic-compatible endpoint (see
[Use your own endpoint](server.md#use-your-own-endpoint)). Hermuse Agent does
not come with a model account: you sign in or enter your API keys yourself.
Then send your agent a first task, for example:

> Plan a walk in Nantes for me: open OpenStreetMap centered on the Château des
> ducs de Bretagne, then open the Wikipedia page of the château in a new tab,
> and give me 3 things to see nearby.

See [The agent's computer](agent-computer.md) for the live viewer and **Take
control**, and [Activity, Approvals and Automations](profile-panel.md) for the
profile panel next to the chat.

## Undo an installation on its target machine

Removing the Hermuse app is different from undoing an installation it made.
Open **Instances**, then the target's **⋯** menu:

- **Uninstall from this computer…** reviews the local Linux installation.
- **Uninstall from server…** opens the existing SSH removal flow for a remote
  instance. It acts on that server, not on the computer running the app.
- **Remove from Hermuse** only forgets the saved connection; it is not an
  uninstall.

On Linux, the local page targets the canonical system service and first performs
a read-only inventory. Keep-data removal is the default. Choose purge explicitly
to include proven-owned data and caches, then type the requested confirmation.
The privileged helper uses the same removal engine and operation lock as SSH
setup, rechecks the inventory and refuses a changed plan. It stops the owned
system service, never an unrelated process. Hermuse Agent, its database, other
connections and their credentials stay installed.

Installation and removal show their steps or inventory separately from the
scrollable activity log and confirmation controls. New log lines follow the
bottom until you scroll back; scroll to the bottom to resume following. Select
text to copy a portion, or use the log's copy button for the retained output.

Local and SSH setup share the root-owned ownership journal
`/var/lib/hermuse-provision/ownership.json`. It records resource identities, not
just completed steps. Keep-data removal removes owned runtime/service resources
and the loopback token while retaining user data; reinstalling creates a new
token. The journal remains available for a later purge.

Purge does not sweep an arbitrary home or Docker store. Preexisting, shared,
replaced, unsafe or unproven resources remain listed with reasons. System
packages and shared Docker resources are retained. A dedicated account is
removed only when ownership is proven and no other service uses it. Dependency
checks include stopped services, loaded instances and template definitions;
ordinary system templates alone do not block removal. Legacy migration
originals and private backups are not a promise of complete erasure.

Only the removed local connection's credentials are forgotten after successful
removal. App-wide desktop bridge keyring entries remain because other saved
instances may use them. Missing ownership evidence is never reconstructed by
claiming existing resources.

### Command-line preview and removal

The repository supplies the same privileged Linux service helper as a Dart
command. Build the helper from the checkout first:

```bash
cd packages/hermuse_host
dart run tool/build_linux_service.dart
dart run tool/uninstall_local.dart --workspace-root ../..                 # preview
dart run tool/uninstall_local.dart --workspace-root ../.. --apply         # keep data
dart run tool/uninstall_local.dart --workspace-root ../.. --purge --apply # owned data too
```

The target is always `/home/hermes/.hermes`; arbitrary-home, journal and desktop
bridge removal flags are not supported. `--yes` skips typed confirmation and
requires `--apply`; it does not bypass administrator authorization. The command
does not remove app registrations or keyring entries; the app page handles the
selected local connection.

## Your data on Linux

| What | Where |
| --- | --- |
| App data (local database, saved connections) | `~/.local/share/com.yellowstick.hermuse_app/` |
| Managed Hermes Agent and Hermuse data | `/home/hermes/.hermes` |
| Desktop connection credentials | your system keyring |
| Private service token | `/var/lib/hermuse-provision/dashboard.env` (root-only) |
| Ownership journal and migration backups | `/var/lib/hermuse-provision/` |
| The agent's computer | Docker container `hermuse-computer-hermes` and volume `hermuse-computer-hermes-home` |

Updating, `sudo apt remove hermuse-agent` and `sudo apt purge hermuse-agent`
remove only the app itself (`/opt/hermuse-agent`, the `hermuse-agent` command,
the menu entry and icons). Everything in the table stays, and so do the system
packages installed during the preparation. Deleting the AppImage works the same
way. Use the target-specific removal page above to review the installation and
optionally purge its owned data before removing the app itself.
