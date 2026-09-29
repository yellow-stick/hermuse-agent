#!/usr/bin/env bash
# Builds Hermuse-Agent-<version>-linux-x86_64.AppImage from a complete release
# bundle (hermuse_app, data/, lib/ with lib/cliproxy, libexec/).
#
#   packaging/linux/package-appimage.sh <bundle-dir> <out-dir>
#
# linuxdeploy + its GTK plugin only prepare the AppDir (redistributable GTK
# libraries in usr/lib, resources in usr/share); the bundle itself stays
# byte-identical under usr/bin. appimagetool then packs the AppDir with the
# pinned uruntime, configured to always extract and run (no FUSE needed) and
# clean up on exit. Every tool is pinned in tool/release/toolchain.lock.json.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"
# stdout carries only the path of the built AppImage; tool output goes to stderr.
exec 3>&1 1>&2

[ "$#" -eq 2 ] || hermuse_die "usage: $0 <bundle-dir> <out-dir>"
[ -d "$1" ] || hermuse_die "no bundle directory $1"
bundle="$(cd "$1" && pwd)"
mkdir -p "$2"
out="$(cd "$2" && pwd)"

hermuse_require jq curl tar readelf ldd dpkg-query perl rsvg-convert \
  desktop-file-validate appstreamcli
hermuse_load_versions
hermuse_source_date_epoch
export ARCH=x86_64

# Variables the pinned GTK hook may export, besides APPDIR. Keep in sync with
# AppRun and hostEnvironment() (packages/hermuse_host/lib/src/host_environment.dart).
saved_env_names='LD_LIBRARY_PATH GTK_DATA_PREFIX GTK_THEME GDK_BACKEND XDG_DATA_DIRS GTK_EXE_PREFIX GTK_PATH GTK_IM_MODULE_FILE GDK_PIXBUF_MODULE_FILE GIO_MODULE_DIR GSETTINGS_SCHEMA_DIR GI_TYPELIB_PATH PATH'

check_bundle "$bundle"
check_elf_tree "$bundle" "$bundle/lib"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cache="$(hermuse_tools_cache)"
appdir="$tmp/AppDir"
appimage="$out/$HERMUSE_APPIMAGE_NAME"

# --- pinned tools ------------------------------------------------------------
tool_rev() { lock_get ".tools.$1.revision"; }
fetch_lock_entry .tools.linuxdeploy "$cache/linuxdeploy-$(tool_rev linuxdeploy)-x86_64.AppImage"
fetch_lock_entry .tools.appimagetool "$cache/appimagetool-$(tool_rev appimagetool)-x86_64.AppImage"
fetch_lock_entry .tools.linuxdeploy_plugin_gtk \
  "$cache/linuxdeploy-plugin-gtk-$(lock_get .tools.linuxdeploy_plugin_gtk.commit).sh"
fetch_lock_entry .tools.uruntime "$cache/$(lock_get .tools.uruntime.variant)-$(tool_rev uruntime)"

# Tool AppImages run extracted: no FUSE in the builder.
extract_tool() {
  local image="$1" dir="$2"
  mkdir -p "$dir"
  install -m 0755 "$image" "$dir/tool.AppImage"
  (cd "$dir" && ./tool.AppImage --appimage-extract >/dev/null) || hermuse_die "cannot extract $image"
  rm -f "$dir/tool.AppImage"
  [ -x "$dir/squashfs-root/AppRun" ] || hermuse_die "no AppRun in $image"
}
extract_tool "$cache/linuxdeploy-$(tool_rev linuxdeploy)-x86_64.AppImage" "$tmp/tools/linuxdeploy"
extract_tool "$cache/appimagetool-$(tool_rev appimagetool)-x86_64.AppImage" "$tmp/tools/appimagetool"
linuxdeploy="$tmp/tools/linuxdeploy/squashfs-root/AppRun"
appimagetool="$tmp/tools/appimagetool/squashfs-root/AppRun"
mkdir -p "$tmp/tools/bin"
install -m 0755 "$cache/linuxdeploy-plugin-gtk-$(lock_get .tools.linuxdeploy_plugin_gtk.commit).sh" \
  "$tmp/tools/bin/linuxdeploy-plugin-gtk.sh"

# uruntime launch policy: fixed-width, single-digit fields in the runtime ELF
# (docs/CONFIGURATION.md at the pinned commit). Verify the upstream bytes,
# configure, verify the configured bytes; nothing touches the runtime later.
runtime="$tmp/tools/runtime"
cp "$cache/$(lock_get .tools.uruntime.variant)-$(tool_rev uruntime)" "$runtime"
verify_sha256 "$runtime" "$(lock_get .tools.uruntime.sha256)" "uruntime (upstream)"
for key in URUNTIME_EXTRACT URUNTIME_UNSHARE URUNTIME_CLEANUP; do
  value="$(lock_get ".tools.uruntime.policy.$key")"
  [[ "$value" =~ ^[0-9]$ ]] || hermuse_die "uruntime policy $key must be one digit"
  [ "$(grep -a -o "$key=[0-9]" "$runtime" | wc -l)" -eq 1 ] ||
    hermuse_die "uruntime: expected exactly one $key field"
  sed -i "s|$key=[0-9]|$key=$value|" "$runtime"
done
verify_sha256 "$runtime" "$(lock_get .tools.uruntime.configured_sha256)" "uruntime (configured)"

# --- AppDir ------------------------------------------------------------------
hermuse_log "preparing AppDir"
mkdir -p "$appdir/usr/share/metainfo"
# linuxdeploy only analyses a scratch copy of the Flutter bundle, outside
# usr/bin and usr/lib (which it rescans and re-links on every plugin run):
# the real bundle, bridge and helper included, is copied in afterwards so
# nothing strips or patches it.
staging="$appdir/.hermuse-bundle"
cp -a "$bundle" "$staging"
rm -f "$staging/$HERMUSE_BUNDLE_CLIPROXY"
rm -rf "${staging:?}/$(dirname "$HERMUSE_BUNDLE_HELPER")"
# An existing AppRun keeps linuxdeploy from looking for the Exec binary.
install -m 0755 "$HERMUSE_LINUX_DIR/AppRun" "$appdir/AppRun"

desktop="$tmp/$HERMUSE_APP_ID.desktop"
render_template "$HERMUSE_LINUX_DIR/hermuse-agent.desktop.in" "$desktop" "EXEC=$HERMUSE_BINARY"
desktop-file-validate "$desktop"
render_icons "$tmp/icons"
render_template "$HERMUSE_LINUX_DIR/com.yellowstick.hermuse_app.metainfo.xml.in" \
  "$appdir/usr/share/metainfo/$HERMUSE_APP_ID.metainfo.xml" \
  "VERSION=$HERMUSE_APP_VERSION" "DATE=$(hermuse_release_date)"
appstreamcli validate --no-net "$appdir/usr/share/metainfo/$HERMUSE_APP_ID.metainfo.xml"

linuxdeploy_args=(
  --appdir "$appdir"
  --deploy-deps-only "$staging/$HERMUSE_BINARY"
  --deploy-deps-only "$staging/lib"
  --desktop-file "$desktop"
  --plugin gtk
)
for size in $HERMUSE_ICON_SIZES; do
  linuxdeploy_args+=(--icon-file "$tmp/icons/${size}x${size}/apps/$HERMUSE_APP_ID.png")
done
linuxdeploy_args+=(--icon-file "$tmp/icons/scalable/apps/$HERMUSE_APP_ID.svg")
# The bundle's own libraries stay where the Flutter engine expects them.
while IFS= read -r -d '' lib; do
  linuxdeploy_args+=(--exclude-library "$(basename "$lib")")
done < <(find "$bundle/lib" -maxdepth 1 -type f -print0 | sort -z)

hermuse_log "running linuxdeploy $(tool_rev linuxdeploy) with the GTK plugin"
DEPLOY_GTK_VERSION=3 PATH="$tmp/tools/bin:$PATH" "$linuxdeploy" "${linuxdeploy_args[@]}"

hook="$appdir/apprun-hooks/linuxdeploy-plugin-gtk.sh"
[ -f "$hook" ] || hermuse_die "GTK plugin did not install its AppRun hook"
# The host-environment contract covers every variable the hook exports.
while IFS= read -r name; do
  case " APPDIR $saved_env_names " in
    *" $name "*) ;;
    *) hermuse_die "GTK hook exports $name, missing from the AppRun/hostEnvironment() list" ;;
  esac
done < <(sed -n 's/^[[:space:]]*export[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$hook")

# Our AppRun saves the host environment before sourcing the GTK hook;
# linuxdeploy's generated wrapper would source it first.
rm -f "$appdir/AppRun" "$appdir/AppRun.wrapped"
install -m 0755 "$HERMUSE_LINUX_DIR/AppRun" "$appdir/AppRun"

# The untouched bundle, with lib/cliproxy and libexec/hermuse-linux-setup.
rm -rf "${staging:?}"
if [ -e "$appdir/usr/bin" ] && [ -n "$(find "$appdir/usr/bin" -mindepth 1 -print -quit)" ]; then
  hermuse_die "linuxdeploy put files in usr/bin: $(find "$appdir/usr/bin" -mindepth 1 -printf '%P ')"
fi
rm -rf "${appdir:?}/usr/bin"
cp -a "$bundle" "$appdir/usr/bin"
while IFS= read -r -d '' lib; do
  [ ! -e "$appdir/usr/lib/$(basename "$lib")" ] ||
    hermuse_die "linuxdeploy duplicated bundle library $(basename "$lib") into usr/lib"
done < <(find "$bundle/lib" -maxdepth 1 -type f -print0)
mkdir -p "$appdir/usr/lib/gio/modules"

check_elf_tree "$appdir" "$appdir/usr/lib:$appdir/usr/bin/lib"
check_bundle "$appdir/usr/bin"

# --- notices -----------------------------------------------------------------
notices="$appdir/usr/share/doc/$HERMUSE_DEB_PACKAGE/notices"
write_app_notices "$notices" "$bundle"

# License files of the runtime and of the helpers statically linked into it.
extract_licenses() {
  local archive="$1" dest="$2" member
  mkdir -p "$dest"
  while IFS= read -r member; do
    tar -xzf "$archive" -O "$member" >"$dest/$(printf '%s' "${member#*/}" | tr '/' '_')"
  done < <(tar -tzf "$archive" | grep -E '^[^/]+/([^/]+/)?(LICEN[CS]E[^/]*|COPYING[^/]*|NOTICE[^/]*|[^/]*GPL[^/]*\.txt)$')
  [ -n "$(find "$dest" -mindepth 1 -print -quit)" ] || hermuse_die "no licence file in $archive"
}
runtime_notices="$notices/appimage-runtime"
fetch_lock_entry .tools.uruntime.source "$cache/sources/uruntime-$(lock_get .tools.uruntime.commit).tar.gz"
extract_licenses "$cache/sources/uruntime-$(lock_get .tools.uruntime.commit).tar.gz" "$runtime_notices/uruntime"
install -m 0644 "$HERMUSE_LINUX_DIR/notices/uruntime-rust-crates.txt" "$runtime_notices/uruntime-rust-crates.txt"
count="$(jq -er '.runtime_embedded_sources | length' "$HERMUSE_LOCK")"
for ((i = 0; i < count; i++)); do
  name="$(lock_get ".runtime_embedded_sources[$i].name")"
  archive="$cache/sources/$name-$(lock_get ".runtime_embedded_sources[$i].revision").tar.gz"
  fetch_lock_entry ".runtime_embedded_sources[$i]" "$archive"
  extract_licenses "$archive" "$runtime_notices/$name"
done

# Ubuntu packages bundled by linuxdeploy: owner package of every file, its
# copyright file, and the source package to publish with the release.
hermuse_log "mapping bundled system files to Ubuntu packages"
multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
declare -A owner_of=()
candidates="$tmp/candidates"
: >"$candidates"
while IFS= read -r -d '' file; do
  rel="${file#"$appdir"/}"
  case "$rel" in
    usr/lib/*)
      sub="${rel#usr/lib/}"
      printf '%s\n' "/usr/lib/$multiarch/$sub" "/lib/$multiarch/$sub" "/usr/lib/$sub" "/lib/$sub" >>"$candidates"
      ;;
    usr/share/*) printf '/%s\n' "$rel" >>"$candidates" ;;
  esac
done < <(find "$appdir/usr/lib" "$appdir/usr/share" -type f -print0)
while IFS= read -r line; do
  pkg="${line%%: *}"
  path="${line#*: }"
  owner_of["$path"]="${pkg%%:*}"
done < <(xargs -d '\n' dpkg-query -S <"$candidates" 2>/dev/null | grep -v ', ' || true)

manifest="$notices/system-packages.txt"
generated="$tmp/generated"
: >"$generated"
declare -A packages=()
while IFS= read -r -d '' file; do
  rel="${file#"$appdir"/}"
  pkg=""
  case "$rel" in
    usr/lib/gio/*) continue ;;
    usr/share/doc/* | usr/share/metainfo/"$HERMUSE_APP_ID".* | usr/share/applications/"$HERMUSE_APP_ID".desktop) continue ;;
    usr/share/icons/hicolor/*/apps/"$HERMUSE_APP_ID".*) continue ;;
    usr/lib/*)
      sub="${rel#usr/lib/}"
      for path in "/usr/lib/$multiarch/$sub" "/lib/$multiarch/$sub" "/usr/lib/$sub" "/lib/$sub"; do
        pkg="${owner_of[$path]:-}"
        [ -z "$pkg" ] || break
      done
      ;;
    usr/share/*) pkg="${owner_of[/$rel]:-}" ;;
  esac
  if [ -n "$pkg" ]; then
    packages["$pkg"]=1
  elif is_elf "$file"; then
    hermuse_die "bundled ELF file $rel has no owning Ubuntu package"
  else
    printf '%s\n' "$rel" >>"$generated"
  fi
done < <(find "$appdir/usr/lib" "$appdir/usr/share" -type f -print0)
[ "${#packages[@]}" -gt 0 ] || hermuse_die "no bundled system package found"

{
  printf '# Ubuntu %s packages whose files are bundled in %s (usr/lib, usr/share).\n' \
    "$(. /etc/os-release && printf '%s' "$VERSION_ID")" "$HERMUSE_APPIMAGE_NAME"
  printf '# binary-package binary-version source-package source-version\n'
  for pkg in "${!packages[@]}"; do
    dpkg-query -W -f='${Package} ${Version} ${source:Package} ${source:Version}\n' "$pkg"
  done | LC_ALL=C sort
  printf '# Files generated at build time from the packages above:\n'
  LC_ALL=C sort "$generated" | sed 's/^/#   /'
} >"$manifest"
for pkg in "${!packages[@]}"; do
  if [ ! -f "$appdir/usr/share/doc/$pkg/copyright" ]; then
    [ -f "/usr/share/doc/$pkg/copyright" ] || hermuse_die "no copyright file for $pkg"
    install -D -m 0644 "/usr/share/doc/$pkg/copyright" "$appdir/usr/share/doc/$pkg/copyright"
  fi
done
mkdir -p "$notices/common-licenses"
cp -L /usr/share/common-licenses/* "$notices/common-licenses/"
chmod -R u=rwX,go=rX "$appdir/usr/share/doc"

# --- pack ----------------------------------------------------------------------
hermuse_log "packing $HERMUSE_APPIMAGE_NAME with appimagetool $(tool_rev appimagetool)"
rm -f "$appimage"
find "$appdir" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
"$appimagetool" --runtime-file "$runtime" "$appdir" "$appimage"
chmod 0755 "$appimage"

# The launch policy must be the configured one, and the packed tree must
# carry the bundle byte for byte.
for key in URUNTIME_EXTRACT URUNTIME_UNSHARE URUNTIME_CLEANUP; do
  [ "$(grep -a -o "$key=[0-9]" "$appimage")" = "$key=$(lock_get ".tools.uruntime.policy.$key")" ] ||
    hermuse_die "$HERMUSE_APPIMAGE_NAME does not carry $key=$(lock_get ".tools.uruntime.policy.$key")"
done
mkdir -p "$tmp/check"
(cd "$tmp/check" && "$appimage" --appimage-extract >/dev/null) || hermuse_die "cannot extract $appimage"
check_bundle "$tmp/check/squashfs-root/usr/bin"
diff -r "$bundle" "$tmp/check/squashfs-root/usr/bin" >/dev/null ||
  hermuse_die "usr/bin in $HERMUSE_APPIMAGE_NAME differs from the bundle"
cmp -s "$HERMUSE_LINUX_DIR/AppRun" "$tmp/check/squashfs-root/AppRun" ||
  hermuse_die "AppRun in $HERMUSE_APPIMAGE_NAME is not packaging/linux/AppRun"
hermuse_log "wrote $appimage"
printf '%s\n' "$appimage" >&3