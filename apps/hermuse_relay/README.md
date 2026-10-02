# hermuse_relay

Same-origin relay between the Hermuse web app and registered Hermes
dashboard instances.

Browsers cannot call a Hermes dashboard cross-origin (Hermes CORS allows
only localhost origins and the WS upgrade rejects mismatching `Origin`),
so the web app is served from — or proxied behind — this relay, and all
`/hermes/<id>/*` traffic is forwarded server-side to the registered
upstream.

## Run

```sh
HERMUSE_RELAY_ADMIN_TOKEN=<secret> dart run bin/server.dart
```

Or compiled: `dart compile exe bin/server.dart -o server && ./server`.

## Environment

| Variable                      | Required | Default             | Meaning                                                        |
| ----------------------------- | -------- | ------------------- | -------------------------------------------------------------- |
| `HERMUSE_RELAY_ADMIN_TOKEN`   | yes      | —                   | Bearer token for `/admin/*`. The server refuses to start without it. |
| `HERMUSE_RELAY_PORT`          | no       | `8787`              | TCP port to listen on.                                         |
| `HERMUSE_RELAY_DB`            | no       | `hermuse_relay.db`  | sqlite path holding the upstream registry.                     |
| `HERMUSE_RELAY_ORIGIN`        | yes      | —                   | Public origin of the web app (e.g. `https://chat.example.com`, or `http://127.0.0.1:8787` locally). Used for the CSRF `Origin` check on state-changing requests and the WS origin check. The relay refuses to start without it. |
| `HERMUSE_RELAY_STATIC_DIR`    | no       | —                   | Directory with the built Jaspr site; served same-origin with an `index.html` SPA fallback. |
| `HERMUSE_RELAY_UPSTREAMS`     | no       | —                   | Comma-separated Hermes base URLs registered at startup (normalised, idempotent, no label). A malformed entry makes the relay refuse to start. |

## Registering an upstream

```sh
export RELAY=https://relay.example.com ORIGIN=https://chat.example.com
curl -X POST "$RELAY/admin/upstreams" \
  -H "Authorization: Bearer $HERMUSE_RELAY_ADMIN_TOKEN" \
  -H "Origin: $ORIGIN" \
  -H 'Content-Type: application/json' \
  -d '{"base_url": "http://127.0.0.1:8000", "label": "office hermes"}'
# → {"id": "<opaque-id>"}
```

Notes:

- `base_url` is normalised (lowercase scheme/host, no trailing slash, no
  query) and registration is idempotent per URL.
- The web app maps a user-typed URL via
  `GET /relay/resolve?url=<url>` → `{"id", "label"}` (404 when unknown),
  then proxies `ANY /hermes/<id>/*` → `<base_url>/*` (query preserved,
  including WS upgrades on `/hermes/<id>/api/ws?...`).
- Upstream `Set-Cookie` headers are kept in a server-side jar keyed by the
  `hermuse_relay_sid` session cookie (HttpOnly, `SameSite=Strict`,
  `Secure` over https) and never reach the browser. Sessions expire after
  12h idle.
- State-changing requests (any non-GET/HEAD/OPTIONS, including admin
  writes) require `Origin: <HERMUSE_RELAY_ORIGIN>` (403 otherwise).
- `GET /relay/health` → `{"ok": true}`.

## Deployment

Put the relay behind TLS (reverse proxy or platform ingress) and serve the
built web app from the same origin — either via `HERMUSE_RELAY_STATIC_DIR`
or by proxying the static host through the same public origin — so fetch
and WebSocket traffic never cross origins. Keep
`HERMUSE_RELAY_ADMIN_TOKEN` in the environment (or secret store) only;
upstream Hermes credentials stay in the server-side cookie jar, never in
browser storage.

### Container image

`ghcr.io/yellow-stick/hermuse-web:<version>` (linux/amd64, linux/arm64) bundles
the relay with the `jaspr build` output of `apps/hermuse_web`. `<version>` is
the `version:` of `hermes-plugin/hermuse/plugin.yaml`: the web app ships with
the plugin version it works with. Published by
`.github/workflows/web-image.yml` from [`Dockerfile`](Dockerfile), which only
copies prebuilt artifacts. Layout and defaults:

- relay bundle in `/opt/hermuse-relay/` (`bin/server`, the entrypoint), site in
  `/opt/hermuse-relay/web` (`HERMUSE_RELAY_STATIC_DIR`);
- `HERMUSE_RELAY_DB=/tmp/hermuse_relay.db`, `HERMUSE_RELAY_PORT=8787`
  (exposed); runs as `65532:65532`.

The registry is declared through `HERMUSE_RELAY_UPSTREAMS`, so the container
needs no volume and runs with a read-only root:

```sh
docker run -d -p 127.0.0.1:9120:8787 --read-only --tmpfs /tmp:rw,size=16m \
  --cap-drop ALL --security-opt no-new-privileges \
  -e HERMUSE_RELAY_ADMIN_TOKEN=… \
  -e HERMUSE_RELAY_ORIGIN=https://app.hermuse.203-0-113-10.sslip.io \
  -e HERMUSE_RELAY_UPSTREAMS=https://hermuse.203-0-113-10.sslip.io \
  ghcr.io/yellow-stick/hermuse-web:0.3.0
```

The desktop app's SSH installer runs it this way (its `web` step) behind Caddy.
