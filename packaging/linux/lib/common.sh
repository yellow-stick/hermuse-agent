# shellcheck shell=bash
# shellcheck disable=SC2034 # the HERMUSE_* values are read by the sourcing scripts
# Shared helpers for the Linux release scripts. Sourced by build-release.sh,
# package-deb.sh and package-appimage.sh (bash, `set -euo pipefail`).
#
# Every external download is pinned in tool/release/toolchain.lock.json and
# refused on any SHA-256 drift.

HERMUSE_LINUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMUSE_REPO="$(cd "$HERMUSE_LINUX_DIR/../.." && pwd)"
HERMUSE_LOCK="$HERMUSE_REPO/tool/release/toolchain.lock.json"

# Identity shared by both formats.
HERMUSE_APP_ID="com.yellowstick.hermuse_app"
HERMUSE_BINARY="hermuse_app"
HERMUSE_DEB_PACKAGE="hermuse-agent"
HERMUSE_MAINTAINER="Yellow Stick <contact@yellow-stick.com>"
HERMUSE_ICON_SVG="$HERMUSE_REPO/packaging/icon/icon.svg"
HERMUSE_ICON_SIZES="48 128 256 512"

# Bundle slots copied after `flutter build linux`, never stripped/modified.
HERMUSE_BUNDLE_CLIPROXY="lib/cliproxy"
HERMUSE_BUNDLE_HELPER="libexec/hermuse-linux-setup"
HERMUSE_BUNDLE_SERVICE="libexec/hermuse-linux-service"

hermuse_log() { printf '==> %s\n' "$*" >&2; }
hermuse_warn() { printf 'warning: %s\n' "$*" >&2; }
hermuse_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

hermuse_require() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || hermuse_die "missing required tool: $tool"
  done
}

# lock_get <jq filter> — value from toolchain.lock.json; missing/null is fatal.
lock_get() {
  local value
  value="$(jq -er "$1" "$HERMUSE_LOCK")" || hermuse_die "toolchain.lock.json has no value for $1"
  printf '%s\n' "$value"
}

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

# verify_sha256 <file> <expected> <label>
verify_sha256() {
  local actual
  [ -f "$1" ] || hermuse_die "$3: missing file $1"
  actual="$(sha256_of "$1")"
  [ "$actual" = "$2" ] || hermuse_die "$3: SHA-256 drift for $1 (expected $2, got $actual)"
}

hermuse_tools_cache() {
  local dir="${HERMUSE_TOOLS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/hermuse-packaging}"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# fetch_pinned <url> <sha256> <dest> <label> — download once, verify on every use.
fetch_pinned() {
  local url="$1" sha="$2" dest="$3" label="$4"
  if [ -f "$dest" ] && [ "$(sha256_of "$dest")" = "$sha" ]; then
    return 0
  fi
  case "$url" in
    https://*) ;;
    *) hermuse_die "$label: refusing non-HTTPS URL $url" ;;
  esac
  mkdir -p "$(dirname "$dest")"
  rm -f "$dest.part"
  hermuse_log "downloading $label"
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 -o "$dest.part" "$url" ||
    hermuse_die "$label: download failed ($url)"
  verify_sha256 "$dest.part" "$sha" "$label"
  mv -f "$dest.part" "$dest"
}

# fetch_lock_entry <jq path of an object with url+sha256> <dest> — pinned download.
fetch_lock_entry() {
  fetch_pinned "$(lock_get "$1.url")" "$(lock_get "$1.sha256")" "$2" "$1"
}

# Versions from apps/hermuse_app/pubspec.yaml (`X.Y.Z+B` or `X.Y.Z-rc.N+B`,
# the only forms tool/release/release-metadata.sh accepts too):
#   HERMUSE_PUBSPEC_VERSION  0.1.0+1
#   HERMUSE_APP_VERSION      0.1.0        (AppImage name, AppStream)
#   HERMUSE_BUILD_NUMBER     1
#   HERMUSE_DEB_VERSION      0.1.0-1      (`X.Y.Z-rc.N+B` → `X.Y.Z~rc.N-B`)
#   HERMUSE_DEB_FILE         hermuse-agent_0.1.0-1_amd64.deb, named after the app
#                            version (`hermuse-agent_X.Y.Z-rc.N-B_amd64.deb`): GitHub
#                            renames a release asset whose name has a `~`
hermuse_load_versions() {
  local pubspec="$HERMUSE_REPO/apps/hermuse_app/pubspec.yaml" raw core pre
  raw="$(sed -n 's/^version:[[:space:]]*//p' "$pubspec" | head -n 1 | tr -d "\"' \r")"
  [ -n "$raw" ] || hermuse_die "no version in $pubspec"
  [[ "$raw" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-(rc\.[0-9]+))?\+([0-9]+)$ ]] ||
    hermuse_die "pubspec version '$raw' is not X.Y.Z+B or X.Y.Z-rc.N+B"
  core="${BASH_REMATCH[1]}"
  pre="${BASH_REMATCH[3]}"
  HERMUSE_PUBSPEC_VERSION="$raw"
  HERMUSE_BUILD_NUMBER="${BASH_REMATCH[4]}"
  if [ -n "$pre" ]; then
    HERMUSE_APP_VERSION="$core-$pre"
    HERMUSE_DEB_VERSION="$core~$pre-$HERMUSE_BUILD_NUMBER"
  else
    HERMUSE_APP_VERSION="$core"
    HERMUSE_DEB_VERSION="$core-$HERMUSE_BUILD_NUMBER"
  fi
  HERMUSE_DEB_FILE="${HERMUSE_DEB_PACKAGE}_$HERMUSE_APP_VERSION-${HERMUSE_BUILD_NUMBER}_amd64.deb"
  HERMUSE_APPIMAGE_NAME="Hermuse-Agent-$HERMUSE_APP_VERSION-linux-x86_64.AppImage"
}

# SOURCE_DATE_EPOCH defaults to the commit time so archives are reproducible.
hermuse_source_date_epoch() {
  if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    SOURCE_DATE_EPOCH="$(git -C "$HERMUSE_REPO" log -1 --format=%ct 2>/dev/null || date +%s)"
  fi
  export SOURCE_DATE_EPOCH
}

hermuse_release_date() { date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%d; }

is_elf() {
  [ -f "$1" ] && [ ! -L "$1" ] && [ "$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]
}

# list_elf_files <dir> — every regular ELF file below <dir>, NUL-free lines.
list_elf_files() {
  local file
  while IFS= read -r -d '' file; do
    if is_elf "$file"; then printf '%s\n' "$file"; fi
  done < <(find "$1" -type f -print0 | sort -z)
}

# check_elf_tree <dir> <lib path> — refuses a JVM link and unresolved deps.
# The JNI glue must never ship linked against a JDK: fail, never delete it.
check_elf_tree() {
  local dir="$1" libpath="$2" file needed deps unresolved=0
  while IFS= read -r file; do
    needed="$(readelf -d "$file" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\].*/\1/p')"
    if [[ $'\n'"$needed" == *$'\n'libjvm* ]]; then
      hermuse_die "$file links libjvm: the build picked up a JDK"
    fi
    [ -n "$needed" ] || continue
    deps="$(LD_LIBRARY_PATH="$libpath" ldd "$file" 2>&1 || true)"
    if [[ "$deps" == *"not found"* ]]; then
      printf 'unresolved dependencies in %s:\n%s\n' "$file" "$(grep 'not found' <<<"$deps")" >&2
      unresolved=1
    fi
  done < <(list_elf_files "$dir")
  [ "$unresolved" -eq 0 ] || hermuse_die "unresolved shared-library dependencies in $dir"
}

# check_bundle <bundle> — layout, modes and embedded-file digests.
# Digests come from HERMUSE_CLIPROXY_SHA256 / HERMUSE_LINUX_HELPER_SHA256
# when set (build-release.sh), otherwise from the lock/helper source.
check_bundle() {
  local bundle="$1" cliproxy_sha helper_sha service_sha path
  [ -x "$bundle/$HERMUSE_BINARY" ] || hermuse_die "$bundle/$HERMUSE_BINARY missing or not executable"
  [ -d "$bundle/data/flutter_assets" ] || hermuse_die "$bundle/data/flutter_assets missing"
  [ -f "$bundle/data/icudtl.dat" ] || hermuse_die "$bundle/data/icudtl.dat missing"
  [ -f "$bundle/lib/libapp.so" ] || hermuse_die "$bundle/lib/libapp.so missing (not a release bundle?)"
  [ -f "$bundle/lib/libflutter_linux_gtk.so" ] || hermuse_die "$bundle/lib/libflutter_linux_gtk.so missing"
  [ -f "$bundle/lib/libsqlite3.so" ] || hermuse_die "$bundle/lib/libsqlite3.so (sqlite3 hook, FTS5) missing"
  cliproxy_sha="${HERMUSE_CLIPROXY_SHA256:-$(jq -er '.platforms["linux-amd64"].binary_sha256' "$HERMUSE_REPO/packages/hermuse_host/cliproxy.lock")}"
  helper_sha="${HERMUSE_LINUX_HELPER_SHA256:-$(sha256_of "$HERMUSE_LINUX_DIR/hermuse-linux-setup")}"
  service_sha="${HERMUSE_LINUX_SERVICE_SHA256:-$(cat "$bundle/$HERMUSE_BUNDLE_SERVICE.sha256")}"
  [[ "$service_sha" =~ ^[0-9a-f]{64}$ ]] || hermuse_die "missing service-helper build digest"
  for path in "$HERMUSE_BUNDLE_CLIPROXY" "$HERMUSE_BUNDLE_HELPER" "$HERMUSE_BUNDLE_SERVICE"; do
    [ -f "$bundle/$path" ] && [ ! -L "$bundle/$path" ] || hermuse_die "$bundle/$path missing"
    [ "$(stat -c %a "$bundle/$path")" = 755 ] || hermuse_die "$bundle/$path must be mode 0755"
  done
  verify_sha256 "$bundle/$HERMUSE_BUNDLE_CLIPROXY" "$cliproxy_sha" "bundle $HERMUSE_BUNDLE_CLIPROXY"
  verify_sha256 "$bundle/$HERMUSE_BUNDLE_HELPER" "$helper_sha" "bundle $HERMUSE_BUNDLE_HELPER"
  verify_sha256 "$bundle/$HERMUSE_BUNDLE_SERVICE" "$service_sha" "bundle $HERMUSE_BUNDLE_SERVICE"
}

# render_icons <out dir> — hicolor PNGs + scalable SVG from the app icon.
render_icons() {
  local out="$1" size
  hermuse_require rsvg-convert
  for size in $HERMUSE_ICON_SIZES; do
    mkdir -p "$out/${size}x${size}/apps"
    rsvg-convert --width "$size" --height "$size" --format png \
      --output "$out/${size}x${size}/apps/$HERMUSE_APP_ID.png" "$HERMUSE_ICON_SVG"
  done
  mkdir -p "$out/scalable/apps"
  install -m 0644 "$HERMUSE_ICON_SVG" "$out/scalable/apps/$HERMUSE_APP_ID.svg"
}

# render_template <template> <output> KEY=VALUE... — replaces @KEY@.
render_template() {
  local template="$1" output="$2" pair key value content
  shift 2
  content="$(cat "$template")"
  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    content="${content//@$key@/$value}"
  done
  if [[ "$content" =~ @[A-Z_]+@ ]]; then
    hermuse_die "unresolved placeholder ${BASH_REMATCH[0]} in $template"
  fi
  printf '%s\n' "$content" >"$output"
}

# flutter_notices <bundle> <out file> — Flutter/Dart NOTICES (gzip) as plain text.
flutter_notices() {
  local notices="$1/data/flutter_assets/NOTICES.Z"
  [ -f "$notices" ] || hermuse_die "no Flutter NOTICES.Z in $1/data/flutter_assets"
  gzip -dc <"$notices" >"$2" || hermuse_die "cannot decompress $notices"
}

# write_app_notices <dir> <bundle> — licences shared by both formats.
write_app_notices() {
  local dir="$1" bundle="$2" archive
  mkdir -p "$dir"
  install -m 0644 "$HERMUSE_REPO/LICENSE" "$dir/hermuse-agent-AGPL-3.0.txt"
  install -m 0644 "$HERMUSE_REPO/packages/yellow_stick_ui/fonts/OFL.txt" "$dir/inter-OFL-1.1.txt"
  install -m 0644 "$HERMUSE_LINUX_DIR/notices/lucide-ISC.txt" "$dir/lucide-ISC.txt"
  install -m 0644 "$HERMUSE_LINUX_DIR/notices/sqlite-public-domain.txt" "$dir/sqlite-public-domain.txt"
  archive="$(cliproxy_archive)"
  tar -xzf "$archive" -O LICENSE >"$dir/cliproxyapi-MIT.txt" ||
    hermuse_die "no LICENSE in $archive"
  flutter_notices "$bundle" "$dir/flutter-NOTICES.txt"
  chmod 0644 "$dir"/*
}

# cliproxy_archive — the verified CLIProxyAPI release archive (licence source).
cliproxy_archive() {
  local lock="$HERMUSE_REPO/packages/hermuse_host/cliproxy.lock" asset sha version dest
  version="$(jq -er '.version' "$lock")"
  asset="$(jq -er '.platforms["linux-amd64"].asset' "$lock")"
  sha="$(jq -er '.platforms["linux-amd64"].archive_sha256' "$lock")"
  dest="$(hermuse_tools_cache)/cliproxy/$asset"
  fetch_pinned "https://github.com/router-for-me/CLIProxyAPI/releases/download/$version/$asset" "$sha" "$dest" "CLIProxyAPI $asset"
  printf '%s\n' "$dest"
}
