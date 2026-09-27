# Run Hermes on your computer with the desktop app

The Hermuse desktop app (macOS, Windows, Linux) can install Hermes Agent on
your computer, keep it running, and add Hermuse to it. Nothing leaves your
computer except the requests to the AI models you connect.

To use a Hermes that runs on a server instead, see
[Set up Hermuse with Hermes on a server](server.md).

## What you need

- macOS, Windows or Linux, 8 GB of RAM or more.
- On macOS and Linux: `git`, `curl` and `tar` (Hermuse tells you the exact
  command if one is missing). On Windows the installer fetches what it needs.
- For the agent's computer: **Docker**. On macOS and Windows install
  [Docker Desktop](https://docs.docker.com/get-started/get-docker/); on Linux,
  Docker Engine. Hermuse works without it, but then the agent has no browser
  you can watch.

## 1. Install Hermes

Open Hermuse and choose **Install Hermes on this computer**. Hermuse:

1. looks for a Hermes already installed and uses it if it finds one;
2. otherwise checks the prerequisites and runs the official Hermes installer
   (`install.sh`, or `install.ps1` on Windows), showing each step;
3. starts Hermes and keeps it running while Hermuse is open.

## 2. Install Hermuse on it

Open Feed, Ideas or Goals: Hermuse offers **Install the plugin**. It copies the
`hermuse` plugin bundled with the app into Hermes, enables it, schedules the
background jobs and prepares the agent's computer.

If Docker is missing or stopped, a note appears under the page:

- **Install Docker to let Hermuse show the agent's browser.** with a **Get
  Docker** button;
- **Start Docker to let Hermuse show the agent's browser.**

Install or start Docker; the next time you open the agent's computer, Hermuse
finishes the setup. The first start downloads the computer image (about
470 MB).

## 3. Connect your models

In **Connections**, add the AI accounts and subscriptions you already have.
Then send your agent a first task, for example:

> Plan a walk in Nantes for me: open OpenStreetMap centered on the Château des
> ducs de Bretagne, then open the Wikipedia page of the château in a new tab,
> and give me 3 things to see nearby.

See [The agent's computer](agent-computer.md) for the live viewer and **Take
control**.
