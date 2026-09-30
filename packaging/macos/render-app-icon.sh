#!/usr/bin/env bash
# Renders the macOS app icon (Runner/Assets.xcassets/AppIcon.appiconset, the
# committed PNGs) from the web icon apps/hermuse_web/web/icons/icon.svg on
# Apple's icon grid: the artwork clipped to an 824 px rounded rectangle
# centred in a 1024 px canvas, over a soft shadow. Run it after changing the
# icon (needs rsvg-convert from librsvg).
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
svg="$repo/apps/hermuse_web/web/icons/icon.svg"
out="$repo/apps/hermuse_app/macos/Runner/Assets.xcassets/AppIcon.appiconset"
command -v rsvg-convert >/dev/null 2>&1 || {
  echo "render-app-icon: rsvg-convert (librsvg) is required" >&2
  exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# The children of the source's root <svg> (its viewBox is 0 0 512 512).
artwork="$(tr -d '\n' <"$svg" | sed -e 's/^<svg [^>]*>//' -e 's,</svg>$,,')"
cat >"$tmp/icon.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
    <filter id="shadow" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
      <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000000" flood-opacity="0.35"/>
    </filter>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="#181819" filter="url(#shadow)"/>
  <g clip-path="url(#tile)">
    <svg x="100" y="100" width="824" height="824" viewBox="0 0 512 512">$artwork</svg>
  </g>
</svg>
SVG
for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$size" -h "$size" "$tmp/icon.svg" -o "$out/app_icon_$size.png"
done
