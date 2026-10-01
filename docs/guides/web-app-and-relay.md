# Web app and relay

The Hermuse web app runs in any browser and can be installed as an app (PWA).
Browsers do not let a web page talk directly to your Hermes dashboard on
another address, so the web app goes through **`hermuse_relay`**, a small
server you run next to it. The relay serves the web app and forwards its
requests, WebSockets included, to the Hermes instances you register.

Your Hermes sign-in stays on the relay: it keeps the dashboard cookie on the
server side and never hands it to the browser.

The desktop apps do not need the relay; they connect to Hermes directly.

## 1. Build the web app

```bash
cd apps/hermuse_web
jaspr build          # output in apps/hermuse_web/build/jaspr
```

## 2. Run the relay

```bash
cd apps/hermuse_relay
export HERMUSE_RELAY_ADMIN_TOKEN="$(openssl rand -base64 32)"   # keep it secret
export HERMUSE_RELAY_ORIGIN=https://chat.example.com             # public address of the web app
export HERMUSE_RELAY_STATIC_DIR=../hermuse_web/build/jaspr
export HERMUSE_RELAY_DB=/var/lib/hermuse/relay.db
dart run bin/server.dart          # or: dart compile exe bin/server.dart -o server
```

| Variable | Meaning |
| --- | --- |
| `HERMUSE_RELAY_ADMIN_TOKEN` | Required. Token for the `/admin/*` routes. |
| `HERMUSE_RELAY_ORIGIN` | Required. The exact public origin of the web app, used to refuse cross-site requests. For a local test: `http://127.0.0.1:8787`. |
| `HERMUSE_RELAY_STATIC_DIR` | The built web app, served on the same address. |
| `HERMUSE_RELAY_PORT` | Port, default `8787`. |
| `HERMUSE_RELAY_DB` | SQLite file with the registered Hermes instances. |

In production, put the relay behind HTTPS (Caddy, nginx, your platform's
ingress) at the address given in `HERMUSE_RELAY_ORIGIN`.

## 3. Register your Hermes

The relay only forwards to Hermes instances you allow:

```bash
curl -X POST https://chat.example.com/admin/upstreams \
  -H "Authorization: Bearer $HERMUSE_RELAY_ADMIN_TOKEN" \
  -H "Origin: https://chat.example.com" \
  -H 'Content-Type: application/json' \
  -d '{"base_url": "https://hermes.example.com", "label": "Home server"}'
```

Until you do, adding that Hermes in the web app answers **This Hermes is not
registered on this relay**.

## 4. Open the web app

Open `https://chat.example.com`, choose **Add a Hermes**, enter the Hermes URL,
a name and the dashboard user name and password. Once it is saved, the web app
shows **What's on** that Hermes: Hermes itself, the Hermuse plugin, its
background jobs, Docker, the agent's computer and a model provider, each found
or missing. Click **Install** on what is missing (or **Install everything
missing**), then **Continue**; where only the server can act, the row gives the
command to copy and **Check again**. The list opens again from **Components**
in **Instances**. [Install Hermuse on your Hermes](server.md#4-install-hermuse-on-your-hermes-one-click)
explains each part. SSH server provisioning is available in the desktop app,
not the web app; provision the server first, then register its HTTPS URL on
the relay.

To install the web app, use the install icon in the address bar
(Chrome, Edge) or **Share → Add to Home Screen** (Safari).

## Troubleshooting

- **`403` on every action**: the page's address differs from
  `HERMUSE_RELAY_ORIGIN` (for example `localhost` against `127.0.0.1`). Open the
  web app at exactly that origin.
- **`Storage unavailable`** on a local test: the browser kept a database from
  an older build at that address. Clear the site data, or use another port.
- **`GET /relay/health`** answers `{"ok": true}` when the relay is up.
