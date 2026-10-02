#!/usr/bin/env bash
# Renders the fictional computer frames: loads each HTML page in headless
# Chromium at the computer's resolution (1280x800) and captures JPEGs the
# demo serves as thumbnails, snapshots and live-stream frames.
set -euo pipefail
frames="$(cd "$(dirname "$0")" && pwd)"
out="$frames/../../lib/assets/computer"
chrome="${CHROME:-$HOME/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$out"
shot() { # $1 = jpg name, $2 = html file
  "$chrome" --headless --no-sandbox --disable-gpu --hide-scrollbars \
    --window-size=1280,800 --screenshot="$tmp/$1.png" \
    --virtual-time-budget=3000 "file://$frames/$2" 2>/dev/null
  ffmpeg -y -loglevel error -i "$tmp/$1.png" -q:v 6 "$out/$1.jpg"
  ls -la "$out/$1.jpg"
}
shot energy energy.html
shot energy-form energy-form.html
shot annecy annecy.html
shot desktop desktop.html
