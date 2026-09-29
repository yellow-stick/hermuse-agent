#!/usr/bin/env bash
# Hermuse Agent macOS release (Apple Silicon): one signed app, one dmg.
#
#   packaging/macos/build-release.sh
#
# Runs on an arm64 Mac with the Xcode and the Flutter pinned in
# tool/release/toolchain.lock.json (`.macos.xcode`, `.flutter`), Flutter on
# PATH. Builds from a copy of the checkout's tracked and untracked-unignored
# files in $HERMUSE_RELEASE_WORK_DIR (default
# ${RUNNER_TEMP:-$TMPDIR}/hermuse-macos-release), never in the checkout, and
# writes:
#   dist/Hermuse-Agent-<version>-macos-arm64.dmg
#   dist/macos/VERSION.json    this build's release metadata
#   dist/macos/SHA256SUMS.txt  sha256sum line of the dmg
# The signed app stays in $HERMUSE_RELEASE_WORK_DIR/app and the evidence
# (signatures, entitlements, Gatekeeper, notarization) in .../evidence.
#
# Signing: with MACOS_DEVELOPER_ID_P12_BASE64, MACOS_DEVELOPER_ID_P12_PASSWORD,
# APPLE_TEAM_ID, APPLE_NOTARY_KEY_ID, APPLE_NOTARY_ISSUER_ID and
# APPLE_NOTARY_KEY_P8_BASE64 all set, every piece of code is signed with the
# Developer ID of APPLE_TEAM_ID (hardened runtime, secure timestamp), the app
# is notarized and stapled, then the dmg is signed, notarized and stapled.
# With none of them set everything is signed ad hoc (hardened runtime, no
# timestamp), nothing is notarized, and VERSION.json says why. Any other
# combination is an error.
#
# CLIProxyAPI is signed before the Flutter build: the app verifies
# Contents/MacOS/cliproxy against the SHA-256 compiled into it, so that
# digest is the one of the signed binary (the upstream binary it comes from
# is verified against packages/hermuse_host/cliproxy.lock first).
set -euo pipefail

log() { printf '==> %s\n' "$*" >&2; }
die() {
  printf 'build-release: %s\n' "$*" >&2
  exit 1
}

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
lock="$repo/tool/release/toolchain.lock.json"
app_name="Hermuse Agent"
app_id="com.yellowstick.hermuseApp"
platform=macos-arm64

# --- builder -------------------------------------------------------------------
[ "$(uname -s)" = Darwin ] || die "run on macOS"
[ "$(uname -m)" = arm64 ] || die "run on an Apple Silicon (arm64) Mac"
for tool in flutter dart jq git xcodebuild xcrun codesign hdiutil plutil lipo ditto shasum spctl security tar; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required on PATH"
done
lock_get() { jq -er "$1" "$lock" || die "no $1 in $lock"; }

xcode_version="$(xcodebuild -version)"
[ "$(printf '%s\n' "$xcode_version" | sed -n 's/^Xcode //p')" = "$(lock_get .macos.xcode.version)" ] &&
  [ "$(printf '%s\n' "$xcode_version" | sed -n 's/^Build version //p')" = "$(lock_get .macos.xcode.build)" ] ||
  die "Xcode is $(printf '%s' "$xcode_version" | tr '\n' ' '), not $(lock_get .macos.xcode.version) ($(lock_get .macos.xcode.build)); select $(lock_get .macos.xcode.path)"
flutter_json="$(flutter --version --machine 2>/dev/null | sed -n '/^{/,$p')"
[ "$(jq -r .frameworkVersion <<<"$flutter_json")" = "$(lock_get .flutter.version)" ] &&
  [ "$(jq -r .frameworkRevision <<<"$flutter_json")" = "$(lock_get .flutter.commit)" ] ||
  die "Flutter on PATH is not $(lock_get .flutter.version) ($(lock_get .flutter.commit))"

# --- signing mode --------------------------------------------------------------
secret_names="MACOS_DEVELOPER_ID_P12_BASE64 MACOS_DEVELOPER_ID_P12_PASSWORD APPLE_TEAM_ID APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID APPLE_NOTARY_KEY_P8_BASE64"
set_names=""
missing_names=""
for name in $secret_names; do
  if [ -n "${!name:-}" ]; then set_names="$set_names $name"; else missing_names="$missing_names $name"; fi
done
if [ -z "$set_names" ]; then
  signed=false
  signing_reason="no signing secrets: ad hoc signature, not notarized"
elif [ -z "$missing_names" ]; then
  signed=true
  signing_reason=""
else
  die "incomplete signing secrets; missing:$missing_names"
fi

# --- work directory ------------------------------------------------------------
work="${HERMUSE_RELEASE_WORK_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hermuse-macos-release}"
work="${work%/}"
case "$work" in
  "") die "HERMUSE_RELEASE_WORK_DIR must not be /" ;;
  /*) ;;
  *) die "HERMUSE_RELEASE_WORK_DIR must be absolute" ;;
esac
case "$work/" in
  "$repo"/*) die "HERMUSE_RELEASE_WORK_DIR must be outside the checkout" ;;
esac
case "$repo/" in
  "$work"/*) die "HERMUSE_RELEASE_WORK_DIR must not contain the checkout" ;;
esac
[ "$work" != "${HOME%/}" ] || die "HERMUSE_RELEASE_WORK_DIR must not be HOME"
rm -rf "$work"
mkdir -p "$work/evidence"
evidence="$work/evidence"
mount_point=""
keychain=""
original_keychains=""
cleanup() {
  if [ -n "$mount_point" ]; then hdiutil detach "$mount_point" -force >/dev/null 2>&1 || true; fi
  if [ -n "$keychain" ]; then
    # shellcheck disable=SC2086 # the saved search list, one quoted path each
    eval "security list-keychains -d user -s $original_keychains" >/dev/null 2>&1 || true
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
  fi
  rm -rf "$work/secrets"
}
trap cleanup EXIT

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
verify_sha256() { # <file> <expected> <label>
  local actual
  actual="$(sha256_of "$1")"
  [ "$actual" = "$2" ] || die "$3: sha256 $actual, expected $2 ($1)"
}
# Regular Mach-O files below <dir>, one path per line.
macho_files() {
  find "$1" -type f -print | while IFS= read -r file; do
    if lipo -archs "$file" >/dev/null 2>&1; then printf '%s\n' "$file"; fi
  done
}
deepest_first() { awk -F/ '{ print NF "\t" $0 }' | sort -rn | cut -f2-; }

# --- sources -------------------------------------------------------------------
commit="$(git -C "$repo" rev-parse HEAD)"
dirty=false
[ -z "$(git -C "$repo" status --porcelain)" ] || dirty=true
metadata="$("$repo/tool/release/release-metadata.sh" --pubspec "$repo/apps/hermuse_app/pubspec.yaml")"
meta() { printf '%s\n' "$metadata" | sed -n "s/^$1=//p"; }
pubspec_version="$(meta pubspec_version)"
app_version="$(meta app_version)"
build_number="$(meta build_number)"
dmg_name="Hermuse-Agent-$app_version-$platform.dmg"
log "$app_name $pubspec_version ($platform) from $commit (dirty: $dirty), signed: $signed"

src="$work/src"
mkdir -p "$src"
(cd "$repo" && git ls-files -z --cached --others --exclude-standard | COPYFILE_DISABLE=1 tar --null -T - -cf -) |
  tar -xf - -C "$src"

# --- CLIProxyAPI ---------------------------------------------------------------
log "flutter pub get --enforce-lockfile"
(cd "$src" && flutter pub get --enforce-lockfile)

log "fetching CLIProxyAPI (frozen lockfile)"
fetch_out="$(cd "$src/packages/hermuse_host" &&
  dart run tool/fetch_cliproxy.dart --platform "$platform" --frozen-lockfile)" ||
  die "fetch_cliproxy.dart --frozen-lockfile failed"
cliproxy_lock="$src/packages/hermuse_host/cliproxy.lock"
fetched_dir="$src/packages/hermuse_host/build/cliproxy/$platform"
cliproxy_upstream_sha="$(jq -er ".platforms[\"$platform\"].binary_sha256" "$cliproxy_lock")"
verify_sha256 "$fetched_dir/cliproxy" "$cliproxy_upstream_sha" "CLIProxyAPI binary"
grep -Fqx "$cliproxy_upstream_sha  $fetched_dir/cliproxy" <<<"$fetch_out" ||
  die "fetch_cliproxy.dart did not report $fetched_dir/cliproxy with $cliproxy_upstream_sha"
cmp -s "$cliproxy_lock" "$repo/packages/hermuse_host/cliproxy.lock" ||
  die "cliproxy.lock changed during the fetch"
cliproxy_archive="$fetched_dir/$(jq -er ".platforms[\"$platform\"].asset" "$cliproxy_lock")"
cliproxy_archive_sha="$(jq -er ".platforms[\"$platform\"].archive_sha256" "$cliproxy_lock")"
verify_sha256 "$cliproxy_archive" "$cliproxy_archive_sha" "CLIProxyAPI archive"
[ "$(lipo -archs "$fetched_dir/cliproxy")" = arm64 ] || die "the CLIProxyAPI binary is not arm64-only"

# --- signing identity ----------------------------------------------------------
codesign_flags=(--force --options runtime)
if [ "$signed" = true ]; then
  log "importing the Developer ID identity into a temporary keychain"
  mkdir -p "$work/secrets"
  chmod 0700 "$work/secrets"
  (umask 077 && printf '%s' "$MACOS_DEVELOPER_ID_P12_BASE64" | base64 -D >"$work/secrets/developer-id.p12") ||
    die "MACOS_DEVELOPER_ID_P12_BASE64 is not base64"
  (umask 077 && printf '%s' "$APPLE_NOTARY_KEY_P8_BASE64" | base64 -D >"$work/secrets/notary-key.p8") ||
    die "APPLE_NOTARY_KEY_P8_BASE64 is not base64"
  keychain_password="$(head -c 24 /dev/urandom | shasum -a 256 | cut -d' ' -f1)"
  original_keychains="$(security list-keychains -d user | sed 's/^[[:space:]]*//' | tr '\n' ' ')"
  keychain="$work/secrets/signing.keychain-db"
  security create-keychain -p "$keychain_password" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain"
  security import "$work/secrets/developer-id.p12" -k "$keychain" -f pkcs12 \
    -P "$MACOS_DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign >/dev/null ||
    die "cannot import MACOS_DEVELOPER_ID_P12_BASE64 (wrong password or not a PKCS#12 file)"
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
  # shellcheck disable=SC2086 # the saved search list, one quoted path each
  eval "security list-keychains -d user -s \"\$keychain\" $original_keychains"
  identities="$(security find-identity -v -p codesigning "$keychain" | grep '"Developer ID Application: ' || true)"
  [ "$(printf '%s\n' "$identities" | grep -c .)" -eq 1 ] ||
    die "MACOS_DEVELOPER_ID_P12_BASE64 must hold exactly one Developer ID Application identity"
  identity="$(printf '%s\n' "$identities" | awk '{ print $2 }')"
  identity_name="$(printf '%s\n' "$identities" | sed 's/^[^"]*"\(.*\)"$/\1/')"
  case "$identity_name" in
    *"($APPLE_TEAM_ID)") ;;
    *) die "the identity \"$identity_name\" is not of team $APPLE_TEAM_ID" ;;
  esac
  codesign_flags+=(--sign "$identity" --keychain "$keychain" --timestamp)
  log "signing as $identity_name"
else
  identity_name=""
  codesign_flags+=(--sign - --timestamp=none)
  log "signing ad hoc ($signing_reason)"
fi

log "signing CLIProxyAPI"
cliproxy="$work/cliproxy/cliproxy"
mkdir -p "$work/cliproxy"
install -m 0755 "$fetched_dir/cliproxy" "$cliproxy"
codesign "${codesign_flags[@]}" --identifier "$app_id.cliproxy" "$cliproxy"
cliproxy_sha="$(sha256_of "$cliproxy")"
log "CLIProxyAPI $cliproxy_upstream_sha (upstream) → $cliproxy_sha (signed)"

# --- build ---------------------------------------------------------------------
log "flutter build macos --release"
(cd "$src/apps/hermuse_app" && flutter build macos --release --no-pub \
  --dart-define=HERMUSE_CLIPROXY_SHA256="$cliproxy_sha" \
  --dart-define=HERMUSE_CLIPROXY_PLATFORM="$platform")
built="$src/apps/hermuse_app/build/macos/Build/Products/Release/$app_name.app"
[ -d "$built" ] || die "flutter build macos produced no $built"
app="$work/app/$app_name.app"
mkdir -p "$work/app"
ditto "$built" "$app"

info="$app/Contents/Info.plist"
plist() { plutil -extract "$1" raw -o - "$info" 2>/dev/null || die "no $1 in $info"; }
[ "$(plist CFBundleIdentifier)" = "$app_id" ] || die "CFBundleIdentifier is $(plist CFBundleIdentifier), not $app_id"
[ "$(plist CFBundleName)" = "$app_name" ] || die "CFBundleName is $(plist CFBundleName), not $app_name"
[ "$(plist CFBundleExecutable)" = "$app_name" ] || die "CFBundleExecutable is $(plist CFBundleExecutable), not $app_name"
[ "$(plist CFBundleShortVersionString)" = "$app_version" ] || die "CFBundleShortVersionString is not $app_version"
[ "$(plist CFBundleVersion)" = "$build_number" ] || die "CFBundleVersion is not $build_number"
minimum_system="$(plist LSMinimumSystemVersion)"
case "$(plist NSHumanReadableCopyright)" in *"Yellow Stick"*) ;; *) die "the copyright does not name Yellow Stick" ;; esac

flutter_assets="$app/Contents/Frameworks/App.framework/Resources/flutter_assets"
[ -f "$flutter_assets/NOTICES.Z" ] || die "no Flutter NOTICES.Z in $flutter_assets"
plugin_version="$(sed -n 's/^version:[[:space:]]*//p' "$src/hermes-plugin/hermuse/plugin.yaml" | tr -d "\"' \r")"
[ "$(sed -n 's/^version:[[:space:]]*//p' "$flutter_assets/assets/hermes-plugin/hermuse/plugin.yaml" | tr -d "\"' \r")" = "$plugin_version" ] ||
  die "bundled plugin assets are not hermes-plugin/hermuse $plugin_version (run tool/sync_plugin_assets.dart)"
hermes_commit="$(sed -n "s/^const hermesReleaseCommit = '\([0-9a-f]\{40\}\)';$/\1/p" \
  "$src/packages/hermuse_host/lib/src/installer.dart")"
[ -n "$hermes_commit" ] || die "no hermesReleaseCommit in installer.dart"

# Licences of what the app redistributes, sealed with the app.
notices="$app/Contents/Resources/Notices"
mkdir -p "$notices"
install -m 0644 "$src/LICENSE" "$notices/hermuse-agent-AGPL-3.0.txt"
install -m 0644 "$src/packages/yellow_stick_ui/fonts/OFL.txt" "$notices/inter-OFL-1.1.txt"
install -m 0644 "$src/packaging/linux/notices/lucide-ISC.txt" "$notices/lucide-ISC.txt"
install -m 0644 "$src/packaging/linux/notices/sqlite-public-domain.txt" "$notices/sqlite-public-domain.txt"
tar -xzf "$cliproxy_archive" -O LICENSE >"$notices/cliproxyapi-MIT.txt" || die "no LICENSE in $cliproxy_archive"
gzip -dc <"$flutter_assets/NOTICES.Z" >"$notices/flutter-NOTICES.txt" || die "cannot decompress NOTICES.Z"
chmod 0644 "$notices"/*

[ ! -e "$app/Contents/MacOS/cliproxy" ] || die "the Flutter build already has Contents/MacOS/cliproxy"
install -m 0755 "$cliproxy" "$app/Contents/MacOS/cliproxy"
verify_sha256 "$app/Contents/MacOS/cliproxy" "$cliproxy_sha" "bundled CLIProxyAPI"

# Apple Silicon only: every Mach-O in the app.
macho_files "$app" >"$work/macho.txt"
[ -s "$work/macho.txt" ] || die "no Mach-O file found in $app"
: >"$evidence/archs.txt"
while IFS= read -r file; do
  archs="$(lipo -archs "$file")"
  printf '%s\t%s\n' "$archs" "${file#"$work/app/"}" >>"$evidence/archs.txt"
  [ "$archs" = arm64 ] || die "$file is $archs, not arm64 only"
done <"$work/macho.txt"

# --- sign ----------------------------------------------------------------------
# Inside out: loose Mach-O files, then nested bundles (deepest first), then
# the app with its entitlements. CLIProxyAPI is already signed and stays
# byte-identical.
log "signing the app"
executable="$app/Contents/MacOS/$app_name"
{ grep -vxF -e "$executable" -e "$app/Contents/MacOS/cliproxy" "$work/macho.txt" || true; } | deepest_first |
  while IFS= read -r file; do
    codesign "${codesign_flags[@]}" "$file"
  done
find "$app/Contents" -type d \( -name '*.framework' -o -name '*.bundle' -o -name '*.xpc' -o -name '*.appex' -o -name '*.app' \) -print |
  deepest_first | while IFS= read -r bundle; do
  codesign "${codesign_flags[@]}" "$bundle"
done
entitlements="$src/apps/hermuse_app/macos/Runner/Release.entitlements"
codesign "${codesign_flags[@]}" --entitlements "$entitlements" "$app"
verify_sha256 "$app/Contents/MacOS/cliproxy" "$cliproxy_sha" "bundled CLIProxyAPI after signing"

check_signature() { # <app> <evidence prefix>
  local target="$1" prefix="$2" file details
  codesign --verify --deep --strict --verbose=2 "$target" >"$evidence/$prefix-verify.txt" 2>&1 ||
    die "codesign --verify failed for $target (see $evidence/$prefix-verify.txt)"
  codesign -d --entitlements :- "$target" >"$evidence/$prefix-entitlements.plist" 2>/dev/null || true
  for file in "$target/Contents/MacOS/$app_name" "$target/Contents/MacOS/cliproxy"; do
    details="$(codesign -dvvv "$file" 2>&1)"
    printf '%s\n\n' "$details" >>"$evidence/$prefix-codesign.txt"
    grep -Eq 'flags=0x[0-9a-f]+\([^)]*runtime' <<<"$details" ||
      die "$file is not signed with the hardened runtime"
    if [ "$signed" = true ]; then
      grep -qx "TeamIdentifier=$APPLE_TEAM_ID" <<<"$details" || die "$file is not signed by team $APPLE_TEAM_ID"
      grep -q '^Timestamp=' <<<"$details" || die "$file has no secure timestamp"
    else
      grep -qx 'Signature=adhoc' <<<"$details" || die "$file is not signed ad hoc"
    fi
  done
}
check_signature "$app" app

# --- notarize the app ------------------------------------------------------------
notarize() { # <file> <label>
  local file="$1" label="$2" out id status
  out="$evidence/notary-$label.json"
  log "notarizing $label (waits for Apple)"
  xcrun notarytool submit "$file" --key "$work/secrets/notary-key.p8" \
    --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID" \
    --wait --timeout 1h --output-format json >"$out" || true
  id="$(jq -r '.id // empty' "$out" 2>/dev/null || true)"
  status="$(jq -r '.status // empty' "$out" 2>/dev/null || true)"
  if [ -n "$id" ]; then
    xcrun notarytool log "$id" --key "$work/secrets/notary-key.p8" \
      --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID" \
      "$evidence/notary-$label-log.json" >/dev/null 2>&1 || true
  fi
  [ "$status" = Accepted ] || die "notarization of $label: ${status:-no result} (see $out)"
}
notarized=false
stapled=false
if [ "$signed" = true ]; then
  ditto -c -k --sequesterRsrc --keepParent "$app" "$work/app.zip"
  notarize "$work/app.zip" app
  xcrun stapler staple "$app" >"$evidence/staple-app.txt" 2>&1 || die "cannot staple the app"
  xcrun stapler validate "$app" >>"$evidence/staple-app.txt" 2>&1 || die "the app's ticket does not validate"
  spctl --assess --type execute -vv "$app" >"$evidence/gatekeeper-app.txt" 2>&1 ||
    die "Gatekeeper rejects the notarized app (see $evidence/gatekeeper-app.txt)"
  grep -q 'source=Notarized Developer ID' "$evidence/gatekeeper-app.txt" ||
    die "Gatekeeper does not see a notarized Developer ID app"
else
  # Expected to be rejected: recorded, not a gate.
  spctl --assess --type execute -vv "$app" >"$evidence/gatekeeper-app.txt" 2>&1 || true
fi
verify_sha256 "$app/Contents/MacOS/cliproxy" "$cliproxy_sha" "bundled CLIProxyAPI after stapling"

# --- dmg -----------------------------------------------------------------------
log "creating $dmg_name"
stage="$work/dmg-root"
mkdir -p "$stage"
ditto "$app" "$stage/$app_name.app"
ln -s /Applications "$stage/Applications"
dmg="$work/$dmg_name"
attempt=1
until hdiutil create -volname "$app_name" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg" >"$evidence/hdiutil-create.txt" 2>&1; do
  # hdiutil create fails transiently ("Resource busy") on busy machines.
  [ "$attempt" -lt 3 ] || die "hdiutil create failed (see $evidence/hdiutil-create.txt)"
  attempt=$((attempt + 1))
  sleep 5
done
if [ "$signed" = true ]; then
  codesign --force --sign "$identity" --keychain "$keychain" --timestamp --identifier "$app_id.dmg" "$dmg"
  notarize "$dmg" dmg
  xcrun stapler staple "$dmg" >"$evidence/staple-dmg.txt" 2>&1 || die "cannot staple the dmg"
  xcrun stapler validate "$dmg" >>"$evidence/staple-dmg.txt" 2>&1 || die "the dmg's ticket does not validate"
  spctl --assess --type open --context context:primary-signature -vv "$dmg" >"$evidence/gatekeeper-dmg.txt" 2>&1 ||
    die "Gatekeeper rejects the dmg (see $evidence/gatekeeper-dmg.txt)"
  notarized=true
  stapled=true
fi
hdiutil verify "$dmg" >"$evidence/hdiutil-verify.txt" 2>&1 || die "hdiutil verify failed"

# Re-check the app exactly as the dmg delivers it.
log "verifying the dmg"
mount_point="$work/mnt"
mkdir -p "$mount_point"
hdiutil attach "$dmg" -readonly -nobrowse -noautoopen -mountpoint "$mount_point" >/dev/null
[ "$(readlink "$mount_point/Applications")" = /Applications ] || die "the dmg has no Applications link"
mounted="$mount_point/$app_name.app"
[ -d "$mounted" ] || die "the dmg has no $app_name.app"
verify_sha256 "$mounted/Contents/MacOS/cliproxy" "$cliproxy_sha" "CLIProxyAPI in the dmg"
check_signature "$mounted" dmg-app
diff -r "$app" "$mounted" >/dev/null || die "the app in the dmg differs from the signed app"
if [ "$signed" = true ]; then
  xcrun stapler validate "$mounted" >/dev/null 2>&1 || die "the app in the dmg has no valid ticket"
fi
hdiutil detach "$mount_point" >/dev/null
mount_point=""

# --- dist ----------------------------------------------------------------------
dist="$repo/dist"
rm -rf "$dist/macos" "${dist:?}/$dmg_name"
mkdir -p "$dist/macos"
cp "$dmg" "$dist/$dmg_name"
chmod 0644 "$dist/$dmg_name"
dmg_sha="$(sha256_of "$dist/$dmg_name")"
jq -n \
  --arg name "$app_name" --arg id "$app_id" --arg version "$app_version" --arg build "$build_number" \
  --arg pubspec "$pubspec_version" --arg minimum "$minimum_system" \
  --arg commit "$commit" --argjson dirty "$dirty" \
  --arg plugin "$plugin_version" --arg hermes "$hermes_commit" \
  --arg cliproxy_version "$(jq -er .version "$cliproxy_lock")" --arg platform "$platform" \
  --arg cliproxy_sha "$cliproxy_sha" --arg cliproxy_upstream "$cliproxy_upstream_sha" \
  --arg cliproxy_archive "$cliproxy_archive_sha" \
  --argjson signed "$signed" --arg identity "$identity_name" \
  --arg team "${APPLE_TEAM_ID:-}" --argjson notarized "$notarized" --argjson stapled "$stapled" \
  --arg reason "$signing_reason" \
  --slurpfile lock "$lock" \
  --arg xcode "$(printf '%s' "$xcode_version" | sed -n 's/^Xcode //p')" \
  --arg xcode_build "$(printf '%s' "$xcode_version" | sed -n 's/^Build version //p')" \
  --arg macos "$(sw_vers -productVersion)" --arg macos_build "$(sw_vers -buildVersion)" \
  --arg dmg "$dmg_name" --arg dmg_sha "$dmg_sha" --argjson dmg_size "$(stat -f %z "$dist/$dmg_name")" \
  '{
    schema: 1,
    os: "macos",
    arch: "arm64",
    app: {name: $name, id: $id, version: $version, build: $build, pubspec_version: $pubspec,
          bundle: ($name + ".app"), executable: ("Contents/MacOS/" + $name),
          minimum_system_version: $minimum},
    source: {commit: $commit, dirty: $dirty},
    plugin: {name: "hermuse", version: $plugin},
    hermes: {commit: $hermes},
    cliproxy: {version: $cliproxy_version, platform: $platform, binary_sha256: $cliproxy_sha,
               upstream_binary_sha256: $cliproxy_upstream, archive_sha256: $cliproxy_archive,
               path: "Contents/MacOS/cliproxy"},
    signing: {signed: $signed, identity: (if $signed then $identity else null end),
              team_id: (if $signed then $team else null end), hardened_runtime: true,
              notarized: $notarized, stapled: $stapled,
              reason: (if $reason == "" then null else $reason end)},
    toolchain: {flutter: ($lock[0].flutter | {version, channel, commit, dart, archive: .archives["macos-arm64"]}),
                xcode: {version: $xcode, build: $xcode_build},
                macos: {version: $macos, build: $macos_build}},
    artifacts: [{name: $dmg, sha256: $dmg_sha, size: $dmg_size}]
  }' >"$dist/macos/VERSION.json"
printf '%s  %s\n' "$dmg_sha" "$dmg_name" >"$dist/macos/SHA256SUMS.txt"
log "release artifacts:"
(cd "$dist" && ls -l "$dmg_name" macos && cat macos/SHA256SUMS.txt) >&2
