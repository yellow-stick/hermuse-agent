#!/usr/bin/env bash
# Builds the read-only demo: apps/hermuse_web compiled with HERMUSE_DEMO=true,
# published from demo/build/web. Extra arguments go to `jaspr build`.
#
# jaspr always writes to apps/hermuse_web/build/jaspr; the demo output is moved
# out of it so that directory never holds a demo build someone could deploy as
# the real web app.
set -euo pipefail

demo="$(cd "$(dirname "$0")" && pwd)"
web="$demo/../apps/hermuse_web"

(cd "$web" && jaspr build --dart-define=HERMUSE_DEMO=true "$@")

# A cold first build has been seen to leave only index.html behind.
if [ ! -f "$web/build/jaspr/main.client.dart.js" ]; then
  echo "demo: jaspr build produced no client bundle; run demo/build.sh again" >&2
  exit 1
fi

rm -rf "$demo/build/web"
mkdir -p "$demo/build"
mv "$web/build/jaspr" "$demo/build/web"
echo "demo: built $demo/build/web"
