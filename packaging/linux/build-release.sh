#!/usr/bin/env bash
# Hermuse Agent Linux release: one Flutter bundle, two artifacts.
#
#   docker build -f packaging/linux/builder.Dockerfile -t hermuse-linux-builder:<tag> tool/release
#   docker run --rm -v "$PWD:/src" -w /src hermuse-linux-builder:<tag> packaging/linux/build-release.sh
#
# Runs inside the builder image only. Builds from a copy of the checkout's
# tracked and untracked-unignored files in $HERMUSE_RELEASE_WORK_DIR (default
# /work), never in the checkout itself, and writes to dist/:
#   hermuse-agent_<debver>_amd64.deb
#   Hermuse-Agent-<version>-linux-x86_64.AppImage
#   hermuse-agent-<version>-corresponding-sources.tar.gz
#   SHA256SUMS.txt, VERSION.json
# The packaged bundle stays in $HERMUSE_RELEASE_WORK_DIR/bundle.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

[ -z "${HERMUSE_DEB_VERSION_OVERRIDE:-}" ] ||
  hermuse_die "HERMUSE_DEB_VERSION_OVERRIDE is for packaging fixtures (package-deb.sh on an existing bundle), never for a release"

# --- builder -------------------------------------------------------------------
builder_lock=/opt/hermuse-builder/toolchain.lock.json
[ -f "$builder_lock" ] ||
  hermuse_die "run inside the builder image (packaging/linux/builder.Dockerfile)"
cmp -s "$builder_lock" "$HERMUSE_LOCK" ||
  hermuse_die "the builder image was built from another toolchain.lock.json; rebuild it"
grep -qx "FROM $(lock_get .builder.image)@$(lock_get .builder.digest)" "$HERMUSE_LINUX_DIR/builder.Dockerfile" ||
  hermuse_die "builder.Dockerfile FROM differs from .builder in toolchain.lock.json"
# shellcheck disable=SC1091
[ "$(. /etc/os-release && printf '%s' "$ID-$VERSION_ID")" = ubuntu-22.04 ] || hermuse_die "builder must be Ubuntu 22.04"
[ "$(dpkg --print-architecture)" = amd64 ] || hermuse_die "builder must be amd64"
if command -v java >/dev/null 2>&1 || command -v javac >/dev/null 2>&1; then
  hermuse_die "a JDK is on PATH: the jni plugin would link libdartjni.so against libjvm"
fi
hermuse_require flutter dart jq git curl tar gzip readelf ldd dpkg-deb dpkg-shlibdeps \
  apt-get perl rsvg-convert desktop-file-validate appstreamcli
flutter_json="$(flutter --version --machine 2>/dev/null)"
[ "$(jq -r .frameworkVersion <<<"$flutter_json")" = "$(lock_get .flutter.version)" ] &&
  [ "$(jq -r .frameworkRevision <<<"$flutter_json")" = "$(lock_get .flutter.commit)" ] ||
  hermuse_die "Flutter on PATH is not $(lock_get .flutter.version) ($(lock_get .flutter.commit))"

# --- sources -------------------------------------------------------------------
work="${HERMUSE_RELEASE_WORK_DIR:-/work}"
case "$work" in
  /) hermuse_die "HERMUSE_RELEASE_WORK_DIR must not be /" ;;
  /*) ;;
  *) hermuse_die "HERMUSE_RELEASE_WORK_DIR must be absolute" ;;
esac
case "$work/" in
  "$HERMUSE_REPO"/*) hermuse_die "HERMUSE_RELEASE_WORK_DIR must be outside the checkout" ;;
esac
mkdir -p "$work"
# Keep only the download cache: every cached file is re-verified on use.
find "$work" -mindepth 1 -maxdepth 1 ! -name cache -exec rm -rf {} +
export HERMUSE_TOOLS_CACHE="$work/cache"

commit="$(git -C "$HERMUSE_REPO" rev-parse HEAD)"
dirty=false
[ -z "$(git -C "$HERMUSE_REPO" status --porcelain)" ] || dirty=true
hermuse_source_date_epoch
hermuse_load_versions
hermuse_log "Hermuse Agent $HERMUSE_PUBSPEC_VERSION (deb $HERMUSE_DEB_VERSION) from $commit (dirty: $dirty)"

# The exact file set that is built is also the application source published
# with the release (AGPL): tracked + untracked-unignored files.
src="$work/src"
app_source="$work/app-source.tar.gz"
mkdir -p "$src"
git -C "$HERMUSE_REPO" ls-files -z --cached --others --exclude-standard |
  (cd "$HERMUSE_REPO" && tar --null -T - --ignore-failed-read --sort=name \
    --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
    --transform "s,^,hermuse-agent-$HERMUSE_APP_VERSION/,SH" -cf -) | gzip -9n >"$app_source"
tar -xzf "$app_source" -C "$src" --strip-components=1

# --- build ---------------------------------------------------------------------
hermuse_log "flutter pub get --enforce-lockfile"
(cd "$src" && flutter pub get --enforce-lockfile)

hermuse_log "fetching CLIProxyAPI (frozen lockfile)"
fetch_out="$(cd "$src/packages/hermuse_host" &&
  dart run tool/fetch_cliproxy.dart --platform linux-amd64 --frozen-lockfile)" ||
  hermuse_die "fetch_cliproxy.dart --frozen-lockfile failed"
cliproxy_lock="$src/packages/hermuse_host/cliproxy.lock"
cliproxy="$src/packages/hermuse_host/build/cliproxy/linux-amd64/cliproxy"
HERMUSE_CLIPROXY_SHA256="$(sha256_of "$cliproxy")"
verify_sha256 "$cliproxy" "$(jq -er '.platforms["linux-amd64"].binary_sha256' "$cliproxy_lock")" "CLIProxyAPI binary"
grep -Fqx "$HERMUSE_CLIPROXY_SHA256  $cliproxy" <<<"$fetch_out" ||
  hermuse_die "fetch_cliproxy.dart did not report $cliproxy with $HERMUSE_CLIPROXY_SHA256"
cmp -s "$cliproxy_lock" "$HERMUSE_REPO/packages/hermuse_host/cliproxy.lock" ||
  hermuse_die "cliproxy.lock changed during the fetch"
cliproxy_asset="$(jq -er '.platforms["linux-amd64"].asset' "$cliproxy_lock")"
# Seed the verified archive into the tools cache (CLIProxyAPI licence source).
install -D -m 0644 "$src/packages/hermuse_host/build/cliproxy/linux-amd64/$cliproxy_asset" \
  "$HERMUSE_TOOLS_CACHE/cliproxy/$cliproxy_asset"
verify_sha256 "$HERMUSE_TOOLS_CACHE/cliproxy/$cliproxy_asset" \
  "$(jq -er '.platforms["linux-amd64"].archive_sha256' "$cliproxy_lock")" "CLIProxyAPI archive"

helper="$src/packaging/linux/hermuse-linux-setup"
[ -f "$helper" ] || hermuse_die "missing $helper"
HERMUSE_LINUX_HELPER_SHA256="$(sha256_of "$helper")"
export HERMUSE_CLIPROXY_SHA256 HERMUSE_LINUX_HELPER_SHA256
hermuse_log "cliproxy $HERMUSE_CLIPROXY_SHA256, helper $HERMUSE_LINUX_HELPER_SHA256"

hermuse_log "flutter build linux --release"
(cd "$src/apps/hermuse_app" && flutter build linux --release --no-pub \
  --dart-define=HERMUSE_APP_VERSION="$HERMUSE_PUBSPEC_VERSION" \
  --dart-define=HERMUSE_CLIPROXY_SHA256="$HERMUSE_CLIPROXY_SHA256" \
  --dart-define=HERMUSE_CLIPROXY_PLATFORM=linux-amd64 \
  --dart-define=HERMUSE_LINUX_HELPER_SHA256="$HERMUSE_LINUX_HELPER_SHA256")

bundle="$work/bundle"
cp -a "$src/apps/hermuse_app/build/linux/x64/release/bundle" "$bundle"
[ ! -e "$bundle/$HERMUSE_BUNDLE_CLIPROXY" ] && [ ! -e "$bundle/$HERMUSE_BUNDLE_HELPER" ] ||
  hermuse_die "the Flutter bundle already has $HERMUSE_BUNDLE_CLIPROXY or $HERMUSE_BUNDLE_HELPER"
install -m 0755 "$cliproxy" "$bundle/$HERMUSE_BUNDLE_CLIPROXY"
install -D -m 0755 "$helper" "$bundle/$HERMUSE_BUNDLE_HELPER"
check_bundle "$bundle"
check_elf_tree "$bundle" "$bundle/lib"

plugin_version="$(sed -n 's/^version:[[:space:]]*//p' "$src/hermes-plugin/hermuse/plugin.yaml" | tr -d "\"' \r")"
bundled_plugin="$bundle/data/flutter_assets/assets/hermes-plugin/hermuse/plugin.yaml"
[ -f "$bundled_plugin" ] || hermuse_die "the bundle has no Hermes plugin assets"
[ "$(sed -n 's/^version:[[:space:]]*//p' "$bundled_plugin" | tr -d "\"' \r")" = "$plugin_version" ] ||
  hermuse_die "bundled plugin assets are not hermes-plugin/hermuse $plugin_version (run tool/sync_plugin_assets.dart)"
hermes_commit="$(sed -n "s/^const hermesReleaseCommit = '\([0-9a-f]\{40\}\)';$/\1/p" \
  "$src/packages/hermuse_host/lib/src/installer.dart")"
[ -n "$hermes_commit" ] || hermuse_die "no hermesReleaseCommit in installer.dart"

# --- package -------------------------------------------------------------------
out="$work/out"
deb="$("$HERMUSE_LINUX_DIR/package-deb.sh" "$bundle" "$out")"
appimage="$("$HERMUSE_LINUX_DIR/package-appimage.sh" "$bundle" "$out")"
[ "$deb" = "$out/${HERMUSE_DEB_PACKAGE}_${HERMUSE_DEB_VERSION}_amd64.deb" ] || hermuse_die "unexpected package $deb"
[ "$appimage" = "$out/$HERMUSE_APPIMAGE_NAME" ] || hermuse_die "unexpected AppImage $appimage"

# Re-verify the embedded bridge and helper inside both finished artifacts.
hermuse_log "verifying the artifacts"
verify="$work/verify"
mkdir -p "$verify/deb" "$verify/appimage"
dpkg-deb -x "$deb" "$verify/deb"
check_bundle "$verify/deb/opt/$HERMUSE_DEB_PACKAGE"
(cd "$verify/appimage" && "$appimage" --appimage-extract >/dev/null)
extracted="$verify/appimage/squashfs-root"
check_bundle "$extracted/usr/bin"
for tree in "$verify/deb/opt/$HERMUSE_DEB_PACKAGE" "$extracted/usr/bin"; do
  diff -r "$bundle" "$tree" >/dev/null || hermuse_die "$tree differs from the bundle"
done
dpkg-deb --info "$deb" >"$work/deb-info.txt"
dpkg-deb --contents "$deb" >"$work/deb-contents.txt"
desktop-file-validate "$verify/deb/usr/share/applications/$HERMUSE_APP_ID.desktop"
desktop-file-validate "$extracted/$HERMUSE_APP_ID.desktop"
appstreamcli validate --no-net "$verify/deb/usr/share/metainfo/$HERMUSE_APP_ID.metainfo.xml"

# --- corresponding sources -----------------------------------------------------
sources_name="$HERMUSE_DEB_PACKAGE-$HERMUSE_APP_VERSION-corresponding-sources"
sources="$work/sources/$sources_name"
hermuse_log "collecting corresponding sources"
mkdir -p "$sources/app" "$sources/ubuntu" "$sources/appimage-runtime" "$sources/appimage-tools"
cp "$app_source" "$sources/app/hermuse-agent-$HERMUSE_APP_VERSION-src.tar.gz"

manifest="$extracted/usr/share/doc/$HERMUSE_DEB_PACKAGE/notices/system-packages.txt"
[ -f "$manifest" ] || hermuse_die "no system-packages.txt in $HERMUSE_APPIMAGE_NAME"
cp "$manifest" "$sources/ubuntu/system-packages.txt"
while read -r source_package source_version; do
  (cd "$sources/ubuntu" && apt-get source --download-only -qq "$source_package=$source_version") ||
    hermuse_die "apt-get source $source_package=$source_version failed"
done < <(grep -v '^#' "$manifest" | awk '{print $3, $4}' | LC_ALL=C sort -u)

fetch_lock_entry .tools.uruntime.source "$sources/appimage-runtime/uruntime-$(lock_get .tools.uruntime.commit).tar.gz"
count="$(jq -er '.runtime_embedded_sources | length' "$HERMUSE_LOCK")"
for ((i = 0; i < count; i++)); do
  fetch_lock_entry ".runtime_embedded_sources[$i]" \
    "$sources/appimage-runtime/$(lock_get ".runtime_embedded_sources[$i].name")-$(lock_get ".runtime_embedded_sources[$i].revision").tar.gz"
done
for tool in linuxdeploy linuxdeploy_plugin_gtk appimagetool; do
  fetch_lock_entry ".tools.$tool.source" \
    "$sources/appimage-tools/${tool//_/-}-$(lock_get ".tools.$tool.commit").tar.gz"
done
cp "$HERMUSE_LOCK" "$sources/toolchain.lock.json"
{
  printf 'Corresponding sources for Hermuse Agent %s (Linux, amd64)\n\n' "$HERMUSE_APP_VERSION"
  printf 'app/              Hermuse Agent source (AGPL-3.0-only), the exact files built\n'
  printf '                  (commit %s, uncommitted changes: %s)\n' "$commit" "$dirty"
  printf 'ubuntu/           Ubuntu 22.04 source packages of the libraries bundled in the\n'
  printf '                  AppImage (list: ubuntu/system-packages.txt), from %s/%s\n' \
    "$(lock_get .builder.apt_snapshot_url)" "$(lock_get .builder.apt_snapshot)"
  printf 'appimage-runtime/ uruntime %s and the helpers statically linked into it\n' "$(lock_get .tools.uruntime.revision)"
  printf '                  (squashfuse, squashfs-tools, libfuse, lzo, xz, zlib, lz4, zstd, mimalloc)\n'
  printf '                  with their build recipes (squashfuse-static, squashfs-tools-static)\n'
  printf 'appimage-tools/   linuxdeploy, linuxdeploy-plugin-gtk and appimagetool used to build\n'
  printf 'toolchain.lock.json  URLs, revisions and SHA-256 of every pinned input\n\n'
  printf 'The .deb bundles no copyleft system library: APT installs them from the\n'
  printf 'distribution, which publishes their sources.\n'
} >"$sources/README.txt"
(cd "$sources" && find . -type f ! -name SHA256SUMS -printf '%P\0' | LC_ALL=C sort -z | xargs -0 sha256sum) \
  >"$sources/SHA256SUMS"
sources_tar="$out/$sources_name.tar.gz"
tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
  -C "$work/sources" -cf - "$sources_name" | gzip -9n >"$sources_tar"

# --- dist ----------------------------------------------------------------------
dist="$HERMUSE_REPO/dist"
rm -rf "$dist"
mkdir -p "$dist"
cp "$deb" "$appimage" "$sources_tar" "$dist/"
chmod 0644 "$dist"/*
chmod 0755 "$dist/$HERMUSE_APPIMAGE_NAME"

artifact_json() {
  local file="$1"
  jq -n --arg name "$(basename "$file")" --arg sha "$(sha256_of "$file")" \
    --argjson size "$(stat -c %s "$file")" '{name: $name, sha256: $sha, size: $size}'
}
jq -n \
  --arg pubspec "$HERMUSE_PUBSPEC_VERSION" --arg version "$HERMUSE_APP_VERSION" \
  --arg build "$HERMUSE_BUILD_NUMBER" --arg deb "$HERMUSE_DEB_VERSION" \
  --arg commit "$commit" --argjson dirty "$dirty" --arg epoch "$SOURCE_DATE_EPOCH" \
  --arg plugin "$plugin_version" --arg hermes "$hermes_commit" \
  --arg cliproxy_version "$(jq -er .version "$cliproxy_lock")" --arg cliproxy_sha "$HERMUSE_CLIPROXY_SHA256" \
  --arg cliproxy_archive "$(jq -er '.platforms["linux-amd64"].archive_sha256' "$cliproxy_lock")" \
  --arg helper_sha "$HERMUSE_LINUX_HELPER_SHA256" \
  --slurpfile lock "$HERMUSE_LOCK" \
  --argjson artifacts "$(for f in "$deb" "$appimage" "$sources_tar"; do artifact_json "$f"; done | jq -s .)" \
  '{
    schema: 1,
    app: {name: "Hermuse Agent", id: "com.yellowstick.hermuse_app", version: $version,
          build: $build, pubspec_version: $pubspec, debian_version: $deb, architecture: "amd64"},
    source: {commit: $commit, dirty: $dirty, source_date_epoch: ($epoch | tonumber)},
    plugin: {name: "hermuse", version: $plugin},
    hermes: {commit: $hermes},
    cliproxy: {version: $cliproxy_version, platform: "linux-amd64", binary_sha256: $cliproxy_sha,
               archive_sha256: $cliproxy_archive, path: "lib/cliproxy"},
    linux_helper: {sha256: $helper_sha, path: "libexec/hermuse-linux-setup"},
    toolchain: {builder: $lock[0].builder, flutter: $lock[0].flutter, melos: $lock[0].melos,
                tools: $lock[0].tools},
    artifacts: $artifacts
  }' >"$dist/VERSION.json"
(cd "$dist" && sha256sum -- *.deb *.AppImage *.tar.gz VERSION.json >SHA256SUMS.txt)
if [ "$(id -u)" = 0 ]; then
  chown -R "$(stat -c %u:%g "$HERMUSE_REPO")" "$dist"
fi
hermuse_log "release artifacts in $dist:"
(cd "$dist" && ls -l && cat SHA256SUMS.txt) >&2