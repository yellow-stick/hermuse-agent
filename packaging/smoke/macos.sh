#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# Scenario runner of the Hermuse Agent macOS release smoke.
#
# Runs on the GitHub-hosted macOS arm64 runner itself, as its desktop user:
# the VM is new for every job and has no nested virtualization, so there is
# no guest and no Docker. It exercises the PACKAGED artifact the way a user
# does: the .dmg verified and mounted, the app copied to /Applications and
# started through LaunchServices from an arbitrary directory (it gets
# launchd's environment, not this script's), a real window, real buttons
# (OCR + Quartz pointer events, see desktop/desktop.py), the real login
# keychain, the real Hermes install at the pin, the bundled plugin and bridge.
# Every acceptance criterion gets results/<id>.json, as linux.sh writes them:
#
#   {schema, id, criterion, guest, format, scenario, run, status, checks[],
#    gui_proof[]}      status: pass | fail | manual-gate | skipped-missing-prereq
#
# A manual gate is never a pass: its screenshots (gui_proof) wait for the
# release approver. The agent's computer needs Docker, which the hosted
# runner cannot run: criterion 7 is a manual gate with the app's own report.
#
# usage: macos.sh fresh --dist DIR --out DIR --run-id ID --runner LABEL [--timeout-scale N]
#
# --dist holds the .dmg and macos/VERSION.json (packaging/macos/build-release.sh).
set -uo pipefail
umask 022
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

SMOKE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# --- configuration ------------------------------------------------------------

APP_NAME='Hermuse Agent'
WINDOW_TITLE='Hermuse Agent'
BUNDLE_ID=com.yellowstick.hermuseApp
APP=/Applications/$APP_NAME.app
APP_SUPPORT=$HOME/Library/Application Support/$BUNDLE_ID
KEYCHAIN=$HOME/Library/Keychains/login.keychain-db
# The app's default when HERMES_HOME is unset (a LaunchServices start never has it).
HERMES_HOME=$HOME/.hermes
LOCAL_SECRETS=hermes/hermuse-local/

# UI copy the automation reads and clicks (OCR). It MUST equal the app's
# English labels: a missing core label fails the flow, a missing secondary one
# turns that GUI proof into a manual gate.
UI_CONNECT_TITLE='Connect to a Hermes'
UI_LOCAL_CHOICE='Install Hermes on this computer'
UI_KEYSTORE_ERROR='Secure storage unavailable'
UI_RETRY_STAGE='Retry this stage'
UI_ENABLE_PLUGIN='Enable the Hermuse plugin'
UI_INSTALL_PLUGIN='Install the plugin'
UI_BACK_TO_CHAT='Back to chat'
UI_CONNECTIONS='Connections'
UI_SEARCH_CONNECTIONS='Search connections'
UI_BRIDGE_CARD='Meta (bridge)'
UI_CONNECT='Connect'
UI_CANCEL='Cancel'
UI_FEED='Feed'
UI_GOALS='Goals'
UI_DOCKER_NOTICE='Install Docker'

# --- arguments -----------------------------------------------------------------

die() {
  echo "macos.sh: $*" >&2
  exit 2
}

SCENARIO=${1:-}
[ $# -gt 0 ] && shift
DIST='' OUT='' RUN_ID='' RUNNER='' TIMEOUT_SCALE=1
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "$1 needs a value"
  case $1 in
    --dist) DIST=$2 ;;
    --out) OUT=$2 ;;
    --run-id) RUN_ID=$2 ;;
    --runner) RUNNER=$2 ;;
    --timeout-scale) TIMEOUT_SCALE=$2 ;;
    *) die "unknown argument $1" ;;
  esac
  shift 2
done
[ "$SCENARIO" = fresh ] || die "unknown scenario '$SCENARIO' (fresh)"
[ -n "$DIST" ] && [ -f "$DIST/macos/VERSION.json" ] || die "--dist must contain macos/VERSION.json"
[ -n "$OUT" ] && [ -n "$RUN_ID" ] && [ -n "$RUNNER" ] || die "--out, --run-id and --runner are required"
[[ $TIMEOUT_SCALE =~ ^[1-9][0-9]*$ ]] || die "--timeout-scale is a positive integer"
[ "$(uname -s)" = Darwin ] || die "runs on macOS"

DIST=$(cd "$DIST" && pwd)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
RES=$OUT/results
EVID=$OUT/evidence
SHOTS=$EVID/screens
STATE=$(mktemp -d "${TMPDIR:-/tmp}/hermuse-smoke.XXXXXX")
mkdir -p "$RES" "$EVID/logs" "$EVID/probe" "$SHOTS"
: >"$OUT/checks.jsonl"

VERSION_JSON=$DIST/macos/VERSION.json
APP_VERSION=$(jq -er '.app.version' "$VERSION_JSON") || die "VERSION.json lacks .app.version"
PIN_COMMIT=$(jq -er '.hermes.commit' "$VERSION_JSON") || die "VERSION.json lacks .hermes.commit"
DMG=$DIST/$(jq -er '[.artifacts[].name | select(endswith(".dmg"))][0]' "$VERSION_JSON") || die "VERSION.json lists no .dmg"
SIGNED=$(jq -r '.signing.signed // false' "$VERSION_JSON")

# macOS runs bash 3.2: no associative arrays, and an empty array must be
# expanded as ${a[@]+"${a[@]}"} under set -u.
EXPECTED=()
RECORDER_PID=''

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
T() { echo $(($1 * TIMEOUT_SCALE)); }
D() { python3 "$SMOKE_DIR/desktop/desktop.py" "$@"; }

wait_until() { # <timeout-s> <interval-s> <command...>
  local deadline=$((SECONDS + $1)) interval=$2
  shift 2
  while :; do
    "$@" && return 0
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep "$interval"
  done
}

# --- results ---------------------------------------------------------------------
expect() { # <id>
  EXPECTED+=("$1")
}

criterion() { # <id>: the acceptance criterion of the plan a result proves
  case $1 in
    c0-test-base) echo base ;;
    c*-*) echo "${1%%-*}" | tr -d c ;;
    *) echo '?' ;;
  esac
}

check() { # <id> <name> <status> <detail> [evidence-path...]
  local id=$1 name=$2 status=$3 detail=$4
  shift 4
  D result check "$OUT" "$id" "$(criterion "$id")" "$name" "$status" "$detail" "$@"
}

pass_or_fail() { # <id> <name> <ok:0|1> <detail> [evidence...]
  local id=$1 name=$2 ok=$3
  shift 3
  if [ "$ok" = 0 ]; then check "$id" "$name" pass "$@"; else check "$id" "$name" fail "$@"; fi
}

verdict() { # <id> <name> <pass-detail> <fail-detail> <command...>: pass when the command succeeds
  local id=$1 name=$2 good=$3 bad=$4
  shift 4
  if "$@"; then check "$id" "$name" pass "$good"; else check "$id" "$name" fail "$bad"; fi
}

recorder_start() { # one small JPEG every few seconds: the run as a flip-book
  mkdir -p "$EVID/frames"
  (
    while :; do
      screencapture -x -t jpg "$EVID/frames/$(date +%s).jpg" 2>/dev/null
      sleep 5
    done
  ) &
  RECORDER_PID=$!
}

recorder_stop() {
  [ -n "$RECORDER_PID" ] || return 0
  kill "$RECORDER_PID" 2>/dev/null
  wait "$RECORDER_PID" 2>/dev/null
  RECORDER_PID=''
}

finalize() {
  local rc=$?
  trap - EXIT
  recorder_stop
  app_close 120 || true
  cp "$HOME/Library/Logs/DiagnosticReports/"*"$APP_NAME"* "$EVID/logs/" 2>/dev/null
  local id
  local -a expects=()
  for id in ${EXPECTED[@]+"${EXPECTED[@]}"}; do expects+=(--expect "$id=$(criterion "$id")"); done
  D result finalize "$OUT" --runner "$RUNNER" --format dmg --scenario "$SCENARIO" --run "$RUN_ID" \
    --exit-code "$rc" ${expects[@]+"${expects[@]}"}
  rm -rf "$STATE"
  log "results written to $RES"
  exit 0
}

# --- app and GUI ------------------------------------------------------------------

sha_of() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
app_pid() { pgrep -n -f "^$APP/Contents/MacOS/" 2>/dev/null; }
app_gone() { [ -z "$(app_pid)" ]; }
shot() { D shot "$SHOTS/$(date +%H%M%S)-$1.png"; }
ui_click() { D click "$1" --shots "$SHOTS" --timeout "$2" --mode "${3:-line}" --window "$WINDOW_TITLE"; }
ui_wait() { D wait-text "$1" --shots "$SHOTS" --timeout "$2" --mode "${3:-any}"; }
backend_up() { D backend >"$EVID/probe/backend.json" 2>&1; }
rest() { D rest "$1" "$2" >"$3" 2>&1; } # <method> <path> <out-file>

# Starts the app like Finder does (LaunchServices, from an arbitrary directory)
# and waits for its window, which then fills the screen's visible frame.
app_launch() { # <label>
  local cwd
  cwd=$(mktemp -d "$STATE/cwd.XXXXXX")
  (cd "$cwd" && open "$APP") >>"$EVID/logs/open-$1.log" 2>&1 || return 1
  D window "$WINDOW_TITLE" --timeout "$(T 180)" >"$EVID/logs/window-$1.txt" 2>&1 || return 1
  D maximize "$WINDOW_TITLE" || log "the window did not take the visible frame"
  sleep 3
  log "app running: pid $(app_pid), window $(cat "$EVID/logs/window-$1.txt")"
}

# The window's close button, as a user does: the app quits with its last
# window and stops the processes it supervises.
app_close() { # [timeout-s]
  app_gone && return 0
  D close "$WINDOW_TITLE" || log "no close button found for '$WINDOW_TITLE'"
  wait_until "${1:-$(T 300)}" 2 app_gone
}

# A transient failure the app reports with its retry button (e.g. HTTP 429 of
# raw.githubusercontent.com): a user reads the error and clicks the button.
# The screen is read at most every minute, the button clicked at most every 3
# minutes; each click is kept as evidence.
RETRY_LOOKED=-1000 RETRY_CLICKED=-1000
retry_when_offered() { # <id>
  [ $((SECONDS - RETRY_LOOKED)) -ge 60 ] && [ $((SECONDS - RETRY_CLICKED)) -ge 180 ] || return 0
  RETRY_LOOKED=$SECONDS
  local png xy
  png=$(shot retry-offered) || return 0
  if D text "$png" | grep -qiwE 'cannot|failed|error|unable' && xy=$(D locate "$png" "$UI_RETRY_STAGE"); then
    # shellcheck disable=SC2086 # "x y"
    D pointer $xy
    RETRY_CLICKED=$SECONDS
    check "$1" user-retry pass "the app reported an error with '$UI_RETRY_STAGE': clicked it, as a user does" "$png"
    return 0
  fi
  rm -f "$png"
}

ready_or_retry() { # <id> <predicate...>: the predicate, else maybe the app's retry button
  local id=$1
  shift
  "$@" && return 0
  retry_when_offered "$id"
  return 1
}

# --- criterion checks ------------------------------------------------------------

c0_test_base() {
  local id=c0-test-base
  { sw_vers; uname -a; id; } >"$EVID/logs/os.txt" 2>&1
  check "$id" os pass "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)) on $(uname -m), runner $RUNNER" \
    "$EVID/logs/os.txt"
  pass_or_fail "$id" arm64 "$([ "$(uname -m)" = arm64 ] && echo 0 || echo 1)" "Apple Silicon (the only macOS target)"
  {
    python3 --version
    tesseract --version 2>&1 | head -n 1
    magick -version | head -n 1
    xcodebuild -version 2>&1 | head -n 1
    brew --version 2>&1 | head -n 1
  } >"$EVID/logs/tools.txt" 2>&1
  # What the app installs itself: none of it may pre-exist on the runner.
  local -a present=()
  local path
  for path in "$HERMES_HOME" "$HOME/.local/bin/hermes" "$APP" "$APP_SUPPORT"; do
    [ -e "$path" ] && present+=("$path")
  done
  command -v hermes >/dev/null 2>&1 && present+=("hermes on PATH: $(command -v hermes)")
  security dump-keychain "$KEYCHAIN" 2>/dev/null | grep -q "\"svce\"<blob>=\"$BUNDLE_ID\"" &&
    present+=("login keychain items of $BUNDLE_ID")
  printf '%s\n' ${present[@]+"${present[@]}"} >"$EVID/logs/prior-state.txt"
  pass_or_fail "$id" no-prior-state "${#present[@]}" \
    "no Hermes, HERMES_HOME, app, app data or app keychain item before the test${present[*]:+; found: ${present[*]}}" \
    "$EVID/logs/prior-state.txt"
  rc_fingerprint >"$EVID/logs/rc-before.txt"
  # Recorded, not required: what the hosted image adds over a new Mac. The
  # app starts from launchd and gives its processes a login shell's PATH
  # (/etc/paths, /etc/paths.d), so Homebrew and the tool cache stay out of
  # their reach; Xcode's git and clang (a new Mac installs them on request) do not.
  cp /etc/paths "$EVID/logs/etc-paths.txt" 2>/dev/null
  cat /etc/paths.d/* >>"$EVID/logs/etc-paths.txt" 2>/dev/null
  check "$id" runner-image pass \
    "hosted image extras: Xcode $(xcodebuild -version 2>/dev/null | head -n 1 | cut -d' ' -f2), Homebrew, Docker $(command -v docker >/dev/null && echo present || echo absent)" \
    "$EVID/logs/tools.txt" "$EVID/logs/etc-paths.txt"
}

c1_launch() {
  local id=c1-launch mnt=$STATE/dmg ok
  hdiutil verify "$DMG" >"$EVID/logs/hdiutil-verify.txt" 2>&1
  pass_or_fail "$id" dmg-checksum $? "hdiutil verify $(basename "$DMG")" "$EVID/logs/hdiutil-verify.txt"
  if ! hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$DMG" >"$EVID/logs/hdiutil-attach.txt" 2>&1; then
    check "$id" dmg-mount fail "hdiutil attach failed" "$EVID/logs/hdiutil-attach.txt"
    return 1
  fi
  ls -la "$mnt" >"$EVID/logs/dmg-contents.txt" 2>&1
  diskutil info "$mnt" >>"$EVID/logs/dmg-contents.txt" 2>&1
  ok=0
  [ -d "$mnt/$APP_NAME.app" ] && [ "$(readlink "$mnt/Applications")" = /Applications ] || ok=1
  grep -Eq 'Volume Name: +Hermuse Agent$' "$EVID/logs/dmg-contents.txt" || ok=1
  pass_or_fail "$id" dmg-layout "$ok" "volume 'Hermuse Agent' holds $APP_NAME.app and an Applications link" \
    "$EVID/logs/dmg-contents.txt"
  codesign --verify --deep --strict --verbose=2 "$mnt/$APP_NAME.app" >"$EVID/logs/codesign-verify.txt" 2>&1
  pass_or_fail "$id" code-signature $? "codesign --verify --deep --strict: every nested binary is sealed" \
    "$EVID/logs/codesign-verify.txt"
  codesign -dvvv "$mnt/$APP_NAME.app" >"$EVID/logs/codesign-display.txt" 2>&1
  spctl --assess --type execute -vv "$mnt/$APP_NAME.app" >"$EVID/logs/spctl.txt" 2>&1
  local accepted=$?
  if [ "$SIGNED" = true ]; then
    ok=0
    grep -q '^Authority=Developer ID Application: ' "$EVID/logs/codesign-display.txt" || ok=1
    grep -q 'flags=.*runtime' "$EVID/logs/codesign-display.txt" || ok=1
    pass_or_fail "$id" developer-id "$ok" "Developer ID signature with the hardened runtime" "$EVID/logs/codesign-display.txt"
    pass_or_fail "$id" gatekeeper "$([ "$accepted" = 0 ] && grep -q 'source=Notarized Developer ID' "$EVID/logs/spctl.txt" && echo 0 || echo 1)" \
      "Gatekeeper accepts the app: notarized Developer ID" "$EVID/logs/spctl.txt"
    { xcrun stapler validate "$DMG" && xcrun stapler validate "$mnt/$APP_NAME.app"; } >"$EVID/logs/stapler.txt" 2>&1
    pass_or_fail "$id" stapled $? "notarization tickets stapled to the dmg and the app" "$EVID/logs/stapler.txt"
  else
    check "$id" gatekeeper skipped-missing-prereq \
      "unsigned build ($(jq -r '.signing.reason // "no reason recorded"' "$VERSION_JSON")): Gatekeeper refuses it, notarization is proven on signed release builds only" \
      "$EVID/logs/spctl.txt" "$EVID/logs/codesign-display.txt"
  fi
  # Drag and drop to Applications, as the volume invites.
  ditto "$mnt/$APP_NAME.app" "$APP" >"$EVID/logs/install.log" 2>&1
  pass_or_fail "$id" installed $? "$APP_NAME.app copied from the dmg to /Applications" "$EVID/logs/install.log"
  hdiutil detach "$mnt" >>"$EVID/logs/hdiutil-attach.txt" 2>&1 || hdiutil detach -force "$mnt" >/dev/null 2>&1
  local plist=$APP/Contents/Info.plist exe icon
  plutil -convert json -o "$EVID/logs/Info.plist.json" "$plist" 2>/dev/null
  exe=$(jq -r '.CFBundleExecutable // ""' "$EVID/logs/Info.plist.json")
  icon=$(jq -r '.CFBundleIconFile // ""' "$EVID/logs/Info.plist.json")
  ok=0
  jq -e --arg id "$BUNDLE_ID" --arg version "$APP_VERSION" --arg name "$APP_NAME" '
    .CFBundleIdentifier == $id and .CFBundleShortVersionString == $version
    and ((.CFBundleDisplayName // .CFBundleName) == $name)' "$EVID/logs/Info.plist.json" >/dev/null || ok=1
  [ -f "$APP/Contents/Resources/${icon%.icns}.icns" ] || ok=1
  [ "$(lipo -archs "$APP/Contents/MacOS/$exe" 2>/dev/null)" = arm64 ] || ok=1
  pass_or_fail "$id" bundle "$ok" \
    "Info.plist: $BUNDLE_ID $APP_VERSION named '$APP_NAME', icon ${icon:-none}, arm64 executable '$exe'" \
    "$EVID/logs/Info.plist.json"
  local want got
  want=$(jq -r '.cliproxy.binary_sha256' "$VERSION_JSON")
  got=$(sha_of "$APP/Contents/MacOS/cliproxy")
  pass_or_fail "$id" bundle-integrity "$([ -n "$got" ] && [ "$got" = "$want" ] && echo 0 || echo 1)" \
    "Contents/MacOS/cliproxy matches VERSION.json (${got:-missing})"
  if ! app_launch first; then
    check "$id" window fail "no window titled '$WINDOW_TITLE' after 'open $APP'" "$(shot no-window)" \
      "$EVID/logs/open-first.log"
    return 1
  fi
  local png text
  png=$(shot welcome)
  D text "$png" >"$EVID/logs/ocr-welcome.txt" 2>&1
  text=$(D text "$png" --title-bar "$WINDOW_TITLE" 2>&1)
  printf '%s\n' "$text" >"$EVID/logs/ocr-title-bar.txt"
  pass_or_fail "$id" window-title "$(grep -qi 'hermuse agent' <<<"$text" && echo 0 || echo 1)" \
    "window '$WINDOW_TITLE' (window server) with 'Hermuse Agent' read by OCR in its title bar" "$png" \
    "$EVID/logs/ocr-title-bar.txt"
  text=$(D text "$png" --crop "$(menu_bar_crop "$png")" 2>&1)
  printf '%s\n' "$text" >"$EVID/logs/ocr-menu-bar.txt"
  pass_or_fail "$id" menu-bar-name "$(grep -qi 'hermuse agent' <<<"$text" && echo 0 || echo 1)" \
    "the menu bar names the app 'Hermuse Agent' (OCR)" "$EVID/logs/ocr-menu-bar.txt"
  ok=0
  D locate "$png" "$UI_CONNECT_TITLE" any >/dev/null || ok=1
  D locate "$png" "$UI_LOCAL_CHOICE" >/dev/null || ok=1
  pass_or_fail "$id" welcome "$ok" "Welcome screen: '$UI_CONNECT_TITLE' and '$UI_LOCAL_CHOICE' (OCR)" "$png" \
    "$EVID/logs/ocr-welcome.txt"
  pass_or_fail "$id" keystore-probe "$(grep -qi "$UI_KEYSTORE_ERROR" "$EVID/logs/ocr-welcome.txt" && echo 1 || echo 0)" \
    "the launch keychain round-trip passed: no '$UI_KEYSTORE_ERROR' screen" "$png"
  check "$id" dock-icon manual-gate "confirm the Dock shows the Hermuse icon, not the Flutter default" "$png"
}

menu_bar_crop() { # <png>: the left half of the menu bar, in screenshot pixels
  local width
  width=$(sips -g pixelWidth "$1" 2>/dev/null | awk '/pixelWidth/ { print $2 }')
  echo "$((width / 2))x$((width / 40))+0+0"
}

journal_file() { printf '%s\n' "$APP_SUPPORT/hermes-install.json"; }

rc_fingerprint() { # the user's shell startup files, which the install must not touch
  local file
  for file in .zshrc .zprofile .zshenv .bash_profile .bashrc .profile; do
    printf '%s %s\n' "$file" "$(sha_of "$HOME/$file" || true)"
  done
}

c4_hermes() {
  local id=c4-hermes png
  if ! png=$(ui_click "$UI_LOCAL_CHOICE" "$(T 60)"); then
    check "$id" local-choice fail "no '$UI_LOCAL_CHOICE' button" "$(shot local-choice-missing)"
    return 1
  fi
  check "$id" local-choice pass "clicked '$UI_LOCAL_CHOICE' (OCR + pointer event)" "$png"
  if ! wait_until "$(T 3600)" 10 ready_or_retry "$id" backend_up; then
    check "$id" backend-serve fail "no app-supervised backend answering /api/status" "$(shot install-stuck)" \
      "$EVID/probe/backend.json"
    return 1
  fi
  shot backend-up >/dev/null
  local journal ok
  journal=$(journal_file)
  cp "$journal" "$EVID/logs/journal.json" 2>/dev/null
  ok=0
  jq -e --arg home "$HERMES_HOME" --arg pin "$PIN_COMMIT" '
    .hermes_home == $home and .commit == $pin and .install_dir == ($home + "/hermes-agent")
    and .finished == true and (.completed_stages | length) > 0' "$journal" >/dev/null 2>&1 || ok=1
  pass_or_fail "$id" journal "$ok" \
    "install journal finished, pinned to $PIN_COMMIT, stages: $(jq -r '.completed_stages | join(" ")' "$journal" 2>/dev/null)" \
    "$EVID/logs/journal.json"
  local install_dir=$HERMES_HOME/hermes-agent marker
  marker=$install_dir/.hermes-bootstrap-complete
  cp "$marker" "$EVID/logs/hermes-bootstrap-complete.json" 2>/dev/null
  ok=0
  jq -e --arg pin "$PIN_COMMIT" '.schemaVersion == 1 and .pinnedCommit == $pin' "$marker" >/dev/null 2>&1 || ok=1
  [ "$(git -C "$install_dir" rev-parse HEAD 2>/dev/null)" = "$PIN_COMMIT" ] || ok=1
  pass_or_fail "$id" pinned-checkout "$ok" "checkout HEAD and bootstrap marker at $PIN_COMMIT" \
    "$EVID/logs/hermes-bootstrap-complete.json"
  # The stages run with the managed HOME the journal records
  # (<HERMES_HOME>/runtime), so the launcher and Node shims live there.
  local runtime launcher version=$EVID/logs/hermes-version.txt
  runtime=$(jq -r '.runtime_home // empty' "$journal" 2>/dev/null)
  launcher=${runtime:+$runtime/.local/bin/hermes}
  if [ -n "$launcher" ] && [ -x "$launcher" ]; then
    env -i HOME="$HOME" PATH="$runtime/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$launcher" --version >"$version" 2>&1
    pass_or_fail "$id" launcher-version "$(grep -q '0\.21\.' "$version" && echo 0 || echo 1)" \
      "managed launcher $launcher answers $(head -n 1 "$version")" "$version"
  else
    check "$id" launcher-version fail "no managed launcher under the journal's runtime_home (${runtime:-unset})"
  fi
  local leak
  local -a leaked=()
  for leak in hermes node npm uv; do
    [ -e "$HOME/.local/bin/$leak" ] && leaked+=("$leak")
  done
  rc_fingerprint >"$EVID/logs/rc-after.txt"
  ok=0
  [ ${#leaked[@]} -eq 0 ] || ok=1
  cmp -s "$EVID/logs/rc-before.txt" "$EVID/logs/rc-after.txt" || ok=1
  pass_or_fail "$id" real-home-untouched "$ok" \
    "no shim in ~/.local/bin${leaked[*]:+ (found ${leaked[*]})}, the shell startup files unchanged" \
    "$EVID/logs/rc-before.txt" "$EVID/logs/rc-after.txt"
  ok=0
  jq -e --arg home "$HOME" '.backend.home == $home and .backend.hermes_desktop == "1"
    and ((.backend.hermes_home // "") == "" or .backend.hermes_home == ($home + "/.hermes"))
    and (.api_status.version | tostring | test("^0\\.21\\."))' "$EVID/probe/backend.json" >/dev/null || ok=1
  pass_or_fail "$id" backend-serve "$ok" \
    "supervised 'hermes serve' answers /api/status on loopback with the real HOME ($(jq -r '.api_status.version' "$EVID/probe/backend.json"))" \
    "$EVID/probe/backend.json"
}

c3_keyring() {
  local id=c3-keyring value service=hermuse-smoke-$RUN_ID log=$EVID/logs/secret-roundtrip.log
  value=hermuse-smoke-$RUN_ID-$RANDOM$RANDOM
  {
    security add-generic-password -s "$service" -a fixture -w "$value" "$KEYCHAIN" &&
      [ "$(security find-generic-password -s "$service" -a fixture -w "$KEYCHAIN")" = "$value" ] &&
      security delete-generic-password -s "$service" -a fixture "$KEYCHAIN" &&
      ! security find-generic-password -s "$service" -a fixture "$KEYCHAIN"
  } >"$log" 2>&1
  pass_or_fail "$id" fixture-secret-roundtrip $? "store, find, delete of a fixture secret in the login keychain" "$log"
  # The app's items, by attributes only (reading their data would ask the
  # user: they belong to the app).
  security dump-keychain "$KEYCHAIN" 2>/dev/null | awk -v svc="\"svce\"<blob>=\"$BUNDLE_ID\"" '
    /^keychain: / { if (hit) print acct; hit = 0; acct = "" }
    index($0, svc) { hit = 1 }
    /"acct"<blob>=/ { acct = $0; sub(/.*"acct"<blob>=/, "", acct) }
    END { if (hit) print acct }' >"$EVID/logs/keychain-app-items.txt"
  pass_or_fail "$id" app-secrets-in-keychain "$(grep -q "\"$LOCAL_SECRETS" "$EVID/logs/keychain-app-items.txt" && echo 0 || echo 1)" \
    "the local instance's secrets are login keychain items of $BUNDLE_ID: $(tr '\n' ' ' <"$EVID/logs/keychain-app-items.txt")" \
    "$EVID/logs/keychain-app-items.txt"
  local -a paths=("$APP_SUPPORT")
  local dir
  for dir in "$HOME/Library/Preferences" "$HOME/Library/Caches/$BUNDLE_ID" "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
    "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"; do
    [ -e "$dir" ] && paths+=("$dir")
  done
  D plaintext "${paths[@]}" --name "$LOCAL_SECRETS" >"$EVID/probe/plaintext.json" 2>&1
  pass_or_fail "$id" no-plaintext $? \
    "neither the backend's session token nor the app's secret names in the app's files (Application Support, Preferences, caches)" \
    "$EVID/probe/plaintext.json"
}

cron_ids() { jq -r '.body.jobs[] | select(.registered) | .job_id' "$1" 2>/dev/null | sort; }

plugin_ready() {
  [ -f "$HERMES_HOME/plugins/hermuse/plugin.yaml" ] && rest GET /api/plugins/hermuse/feed "$EVID/probe/feed.json"
}

c5_plugin() {
  local id=c5-plugin ok png
  ui_click "$UI_BACK_TO_CHAT" 10 >/dev/null || true
  # The plugin gate sits on every product route: Feed, second in the rail.
  if ! D rail 2 "$WINDOW_TITLE" >"$EVID/logs/rail.json" 2>&1 || ! png=$(ui_wait "$UI_ENABLE_PLUGIN" "$(T 60)"); then
    check "$id" plugin-gate fail "Feed does not show '$UI_ENABLE_PLUGIN'" "$(shot plugin-gate-missing)" "$EVID/logs/rail.json"
    return 1
  fi
  check "$id" plugin-gate pass "Feed shows '$UI_ENABLE_PLUGIN' for the local instance" "$png"
  if ! png=$(ui_click "$UI_INSTALL_PLUGIN" "$(T 30)"); then
    check "$id" plugin-install fail "no '$UI_INSTALL_PLUGIN' button" "$(shot install-plugin-missing)"
    return 1
  fi
  if ! wait_until "$(T 900)" 5 plugin_ready; then
    check "$id" plugin-install fail "the plugin never served /api/plugins/hermuse/feed" "$(shot plugin-stuck)" \
      "$EVID/probe/feed.json"
    return 1
  fi
  check "$id" plugin-install pass "clicked '$UI_INSTALL_PLUGIN': the restarted backend serves the plugin" "$png"
  local assets=$APP/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/hermes-plugin/hermuse
  diff -r -x __pycache__ "$assets" "$HERMES_HOME/plugins/hermuse" >"$EVID/logs/plugin-diff.txt" 2>&1
  pass_or_fail "$id" plugin-copied $? "HERMES_HOME/plugins/hermuse equals the plugin assets of the app bundle" \
    "$EVID/logs/plugin-diff.txt"
  pass_or_fail "$id" feed-endpoint 0 "GET /api/plugins/hermuse/feed on the supervised backend" "$EVID/probe/feed.json"
  rest GET /api/plugins/hermuse/goals "$EVID/probe/goals.json"
  pass_or_fail "$id" goals-endpoint $? "GET /api/plugins/hermuse/goals" "$EVID/probe/goals.json"
  local count jobs=$HERMES_HOME/cron/jobs.json ran
  wait_until "$(T 120)" 5 sh -c "python3 '$SMOKE_DIR/desktop/desktop.py' rest GET /api/plugins/hermuse/cron >'$EVID/probe/cron-1.json' 2>&1 &&
    jq -e '[.body.jobs[] | select(.registered and .enabled)] | length == 4' '$EVID/probe/cron-1.json' >/dev/null"
  count=$(jq '[.body.jobs[] | select(.registered and .enabled)] | length' "$EVID/probe/cron-1.json" 2>/dev/null || echo 0)
  pass_or_fail "$id" jobs-registered "$([ "$count" = 4 ] && echo 0 || echo 1)" \
    "$count/4 Hermuse jobs registered and enabled" "$EVID/probe/cron-1.json"
  ran=$(cron_ids "$EVID/probe/cron-1.json" | while read -r job; do
    jq -r --arg j "$job" '.jobs[] | select(.id == $j and .last_run_at != null) | .id' "$jobs" 2>/dev/null
  done)
  cp "$jobs" "$EVID/logs/cron-jobs.json" 2>/dev/null
  pass_or_fail "$id" jobs-not-run "$([ -z "$ran" ] && echo 0 || echo 1)" \
    "registered jobs have no run recorded (registration is not execution)" "$EVID/logs/cron-jobs.json"
  # Idempotent enablement: a restart runs the setup again, never duplicates.
  local total_before
  total_before=$(jq '.jobs | length' "$jobs" 2>/dev/null || echo 0)
  app_close
  if app_launch plugin-restart && wait_until "$(T 600)" 5 backend_up; then
    rest GET /api/plugins/hermuse/cron "$EVID/probe/cron-2.json"
    ok=0
    [ "$(cron_ids "$EVID/probe/cron-1.json")" = "$(cron_ids "$EVID/probe/cron-2.json")" ] || ok=1
    [ "$(jq '.jobs | length' "$jobs" 2>/dev/null || echo 0)" = "$total_before" ] || ok=1
    pass_or_fail "$id" enable-idempotent "$ok" "same 4 job ids and no new job after a restart" "$EVID/probe/cron-2.json"
  else
    check "$id" enable-idempotent fail "no backend after a restart" "$(shot restart-no-backend)"
  fi
  local feed goals
  ui_click "$UI_BACK_TO_CHAT" 20 >/dev/null || true
  D rail 2 "$WINDOW_TITLE" >/dev/null 2>&1 && feed=$(ui_wait "$UI_FEED" 30)
  D rail 4 "$WINDOW_TITLE" >/dev/null 2>&1 && goals=$(ui_wait "$UI_GOALS" 30)
  check "$id" feed-goals-ui manual-gate \
    "confirm Feed and Goals load, and the 4 registered jobs are not shown as executed" \
    "${feed:-$(shot feed-missing)}" "${goals:-$(shot goals-missing)}"
}

# Connections > the bridge card > its Connect button. The provider list is
# long: its search field brings the card up. A click opens the row, whose body
# holds the filled Connect button (the row's own "Connect" is a label that
# folds the row again).
ui_bridge_connect() {
  ui_click "$UI_BACK_TO_CHAT" 10 >/dev/null || true
  ui_click "$UI_CONNECTIONS" 5 >/dev/null ||
    { D rail last "$WINDOW_TITLE" >/dev/null 2>&1 && ui_click "$UI_CONNECTIONS" 60 >/dev/null; } || return 1
  D scroll up 60 "$WINDOW_TITLE"
  sleep 1
  ui_click "$UI_SEARCH_CONNECTIONS" 30 any >/dev/null || return 1
  D type "$UI_BRIDGE_CARD"
  sleep 2
  ui_click "$UI_BRIDGE_CARD" 30 any >/dev/null && ui_click "$UI_CONNECT" 30 filled >/dev/null
}

c6_bridge() {
  local id=c6-bridge config=$HERMES_HOME/cliproxy/config.yaml
  if ! ui_bridge_connect; then
    check "$id" sidecar manual-gate \
      "Connections > search '$UI_BRIDGE_CARD' > '$UI_CONNECT' not reachable by OCR: start a bridge by hand" \
      "$(shot bridge-ui-missing)"
    return 0
  fi
  if wait_until "$(T 120)" 3 test -s "$config" &&
    wait_until "$(T 120)" 3 sh -c "python3 '$SMOKE_DIR/desktop/desktop.py' cliproxy --config '$config' \
      --expect-exe '$APP/Contents/MacOS/cliproxy' >'$EVID/probe/cliproxy.json' 2>&1"; then
    check "$id" sidecar pass \
      "CLIProxy started from $APP/Contents/MacOS/cliproxy; management API: 401 without key, 200 with it" \
      "$EVID/probe/cliproxy.json" "$(shot bridge-login)"
  else
    check "$id" sidecar fail "the bridge did not start from the bundle slot" "$EVID/probe/cliproxy.json" "$(shot bridge)"
  fi
  ui_click "$UI_CANCEL" 30 >/dev/null || true
  # The login is only started: no subscription credential may exist.
  local auth_dir
  auth_dir=$(sed -n 's/^auth-dir: *"\(.*\)"$/\1/p' "$config" 2>/dev/null)
  find "${auth_dir:-/nonexistent}" -type f >"$EVID/logs/cliproxy-auth-files.txt" 2>/dev/null
  pass_or_fail "$id" no-subscription-credential "$([ -s "$EVID/logs/cliproxy-auth-files.txt" ] && echo 1 || echo 0)" \
    "no subscription credential stored in ${auth_dir:-the bridge auth dir} (login started, never completed)" \
    "$EVID/logs/cliproxy-auth-files.txt"
}

c7_computer() {
  local id=c7-computer png
  rest GET /api/plugins/hermuse/computer/status "$EVID/probe/computer-status.json"
  pass_or_fail "$id" docker-missing-reported \
    "$(jq -e '.body.state == "docker_missing"' "$EVID/probe/computer-status.json" >/dev/null 2>&1 && echo 0 || echo 1)" \
    "no Docker on the runner: the plugin reports '$(jq -r '.body.state // "?"' "$EVID/probe/computer-status.json")'" \
    "$EVID/probe/computer-status.json"
  ui_click "$UI_BACK_TO_CHAT" 10 >/dev/null || true
  D rail 2 "$WINDOW_TITLE" >/dev/null 2>&1
  png=$(ui_wait "$UI_DOCKER_NOTICE" 30) || png=$(shot docker-notice-missing)
  check "$id" computer manual-gate \
    "the hosted macOS arm64 runner has no nested virtualization, so no Docker: confirm the Docker notice here, then attest the agent's computer (image pull, doctor, frames, take control) on a real Mac" \
    "$png" "$EVID/probe/computer-status.json"
}

scenario_fresh() {
  local id
  for id in c0-test-base c1-launch c3-keyring c4-hermes c5-plugin c6-bridge c7-computer; do expect "$id"; done
  c0_test_base
  recorder_start
  c1_launch || return 1
  c4_hermes || return 1
  c3_keyring
  c5_plugin || return 1
  c6_bridge
  c7_computer
}

main() {
  trap finalize EXIT
  trap 'exit 143' TERM INT HUP
  log "scenario $SCENARIO (dmg) on $RUNNER, run $RUN_ID, $(basename "$DMG")"
  scenario_fresh
}

main
