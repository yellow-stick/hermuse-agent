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
