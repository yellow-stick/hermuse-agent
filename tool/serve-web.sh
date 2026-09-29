#!/usr/bin/env bash
# `jaspr serve` for apps/hermuse_web with ports that never collide across
# worktrees. The main checkout keeps Jaspr's defaults (8080, 5467, 5567); a
# linked worktree gets a port triple derived from its path, stable across runs.
# HERMUSE_WEB_PORT overrides the base port. Extra arguments go to `jaspr serve`.
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
git_dir="$(git -C "$root" rev-parse --path-format=absolute --git-dir)"
common_dir="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)"

if [ -n "${HERMUSE_WEB_PORT:-}" ]; then
  port="$HERMUSE_WEB_PORT"
  web_port=$((port + 1))
  proxy_port=$((port + 2))
elif [ "$git_dir" = "$common_dir" ]; then
  port=8080
  web_port=5467
  proxy_port=5567
else
  slot=$(($(printf '%s' "$root" | cksum | cut -d' ' -f1) % 1000))
  port=$((20000 + slot * 3))
  web_port=$((port + 1))
  proxy_port=$((port + 2))
fi

echo "serve-web: http://localhost:$port (webdev $web_port, proxy $proxy_port)"
cd "$root/apps/hermuse_web"
exec jaspr serve --port "$port" --web-port "$web_port" --proxy-port "$proxy_port" "$@"
