#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
#
# In-guest scenario runner of the Hermuse Agent Linux release smoke.
#
# Runs as root inside an ephemeral QEMU guest booted by guest/guest.sh (or,
# for `compat`, inside a throwaway distro container) and exercises the
# INSTALLED artifact (.deb through APT, AppImage run directly) the way a user
# does: real window, real buttons (OCR + pointer events), the real polkit
# dialog answered with the synthetic tester password, real Secret Service,
# real Hermes install at the pin, real Docker pull of the computer image.
# Every acceptance criterion of the plan gets results/<id>.json:
#
#   {schema, id, criterion, guest, format, scenario, run, status, checks[],
#    gui_proof[]}      status: pass | fail | manual-gate | skipped-missing-prereq
#
#   pass                   every check was observed automatically
#   fail                   a check failed, or the scenario stopped before it
#   manual-gate            automatic checks passed but a GUI proof (listed in
#                          gui_proof) needs a human reviewer; never a pass
#   skipped-missing-prereq a prerequisite is absent (model test account on
#                          PR/fork runs) and the proof is recorded as missing
#
# Scenarios: fresh (criteria 1-8), adopt-compatible / adopt-foreign
# (criterion 4), docker-ce / docker-stopped / docker-rootless /
# docker-remote-context (criterion 9), lifecycle (criterion 10), compat
# (container: APT resolution, ELF resolution, window).
#
# usage: linux.sh <scenario> --format deb|appimage --dist DIR --out DIR
#          --run-id ID --guest NAME [--secrets DIR] [--fixture-deb FILE]
#          [--model-env FILE] [--timeout-scale N]
#
# --dist holds the release files and VERSION.json; --secrets the per-run
# tester-password / keyring-password files (root-only); --model-env the
# optional HERMUSE_TEST_MODEL_* file (release environment only).

set -uo pipefail
umask 022
export LC_ALL=C.UTF-8 LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SMOKE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=guest/gui.sh
. "$SMOKE_DIR/guest/gui.sh"

# --- configuration ------------------------------------------------------------

TESTER=tester
TESTER_HOME=/home/$TESTER
STATE=/run/hermuse-smoke
APP_ID=com.yellowstick.hermuse_app
WINDOW_TITLE='Hermuse Agent'
DEB_PACKAGE=hermuse-agent
DEB_ROOT=/opt/hermuse-agent
DESKTOP_FILE=/usr/share/applications/$APP_ID.desktop
APP_SUPPORT=$TESTER_HOME/.local/share/$APP_ID
DOCKER_CE_KEY_FPR=9DC858229FC7DD38854AE2D88D81803C0EBFCD88
INSTALL_STAGES='prerequisites repository venv python-deps node-deps path config complete'

# UI copy the automation clicks (OCR, whole-line match). It MUST equal the
# app's English labels: a missing core label fails the flow, a missing
# secondary one turns that GUI proof into a manual gate.
UI_LOCAL_CHOICE='Install Hermes on this computer'
UI_PREPARE='Prepare'
UI_CHECK_AGAIN='Check again'
UI_CONNECTIONS='Connections'
UI_SEARCH_CONNECTIONS='Search connections'
UI_BRIDGE_CARD='Meta (bridge)'
UI_CONNECT='Connect'
UI_OPEN_LINK='Open link'
UI_CANCEL='Cancel'
UI_RETRY_STAGE='Retry this stage'
UI_FEED='Feed'
UI_GOALS='Goals'
UI_BACK_TO_CHAT='Back to chat'
UI_USE_LOCAL_DOCKER="Use this computer's Docker"

# --- arguments -----------------------------------------------------------------

die() {
  echo "linux.sh: $*" >&2
  exit 2
}

SCENARIO=${1:-}
[ $# -gt 0 ] && shift
FORMAT='' DIST='' OUT='' RUN_ID='' GUEST='' SECRETS='' FIXTURE_DEB='' MODEL_ENV='' TIMEOUT_SCALE=1
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "$1 needs a value"
  case $1 in
    --format) FORMAT=$2 ;;
    --dist) DIST=$2 ;;
    --out) OUT=$2 ;;
    --run-id) RUN_ID=$2 ;;
    --guest) GUEST=$2 ;;
    --secrets) SECRETS=$2 ;;
    --fixture-deb) FIXTURE_DEB=$2 ;;
    --model-env) MODEL_ENV=$2 ;;
    --timeout-scale) TIMEOUT_SCALE=$2 ;;
    *) die "unknown argument $1" ;;
  esac
  shift 2
done
case $SCENARIO in
  fresh | adopt-compatible | adopt-foreign | docker-ce | docker-stopped | docker-rootless | \
    docker-remote-context | lifecycle | compat) ;;
  *) die "unknown scenario '$SCENARIO'" ;;
esac
case $FORMAT in deb | appimage) ;; *) die "--format deb|appimage" ;; esac
[ -n "$DIST" ] && [ -f "$DIST/VERSION.json" ] || die "--dist must contain VERSION.json"
[ -n "$OUT" ] && [ -n "$RUN_ID" ] && [ -n "$GUEST" ] || die "--out, --run-id and --guest are required"
[ "$(id -u)" = 0 ] || die "runs as root"
[[ $TIMEOUT_SCALE =~ ^[1-9][0-9]*$ ]] || die "--timeout-scale is a positive integer"
if [ "$SCENARIO" != compat ]; then
  [ -s "$SECRETS/tester-password" ] && [ -s "$SECRETS/keyring-password" ] ||
    die "--secrets must hold tester-password and keyring-password"
fi
if [ "$SCENARIO" = lifecycle ] && [ "$FORMAT" = deb ]; then
  [ -f "$FIXTURE_DEB" ] || die "lifecycle/deb needs --fixture-deb"
fi

# The unique basename the plugin derives container/volume names from.
HERMES_HOME=$TESTER_HOME/hermuse-release-$RUN_ID-$FORMAT
RES=$OUT/results
EVID=$OUT/evidence
CHECKS=$OUT/checks.jsonl
mkdir -p "$RES" "$EVID/logs" "$EVID/session" "$EVID/probe"
: >"$CHECKS"

VERSION_JSON=$DIST/VERSION.json
PIN_COMMIT=$(jq -er '.hermes.commit' "$VERSION_JSON") || die "VERSION.json lacks .hermes.commit"
PLUGIN_VERSION=$(jq -er '.plugin.version' "$VERSION_JSON") || die "VERSION.json lacks .plugin.version"
COMPUTER_IMAGE=ghcr.io/yellow-stick/hermuse-computer:$PLUGIN_VERSION
DEB_FILE=$DIST/$(jq -er '[.artifacts[].name | select(endswith(".deb"))][0]' "$VERSION_JSON")
APPIMAGE_FILE=$DIST/$(jq -er '[.artifacts[].name | select(endswith(".AppImage"))][0]' "$VERSION_JSON")

APP_DIR=''
APP_PID=''
APPIMAGE_PATH=''
DEB_EXEC=''
TESTER_UID=''
KEYRING_WATCHER_PID=''
C4_INTERRUPTED=''
SPOOL_SEQ=0
declare -A CRITERION=()
EXPECTED=()

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
T() { echo $(($1 * TIMEOUT_SCALE)); }
rel() { realpath -m --relative-to="$OUT" "$1"; }

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

expect() { # <id> <criterion>
  CRITERION[$1]=$2
  EXPECTED+=("$1")
}

check() { # <id> <name> <status> <detail> [evidence-path...]
  local id=$1 name=$2 status=$3 detail=$4
  shift 4
  local -a evidence=()
  local path
  for path; do
    [ -n "$path" ] && [ -e "$path" ] && evidence+=("$(rel "$path")")
  done
  jq -cn --arg id "$id" --arg criterion "${CRITERION[$id]:-?}" --arg name "$name" \
    --arg status "$status" --arg detail "$detail" \
    '{id: $id, criterion: $criterion, name: $name, status: $status, detail: $detail,
      evidence: $ARGS.positional}' --args "${evidence[@]}" >>"$CHECKS"
  log "[$status] $id/$name: $detail"
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

not() { ! "$@"; }

newest() { # <dir> <glob>: most recent matching file
  find "$1" -maxdepth 1 -name "$2" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-
}

redact() {
  local file
  for file in "$SECRETS/tester-password" "$SECRETS/keyring-password" "${MODEL_KEY_FILE:-}"; do
    [ -n "$file" ] && [ -s "$file" ] || continue
    # shellcheck disable=SC2016 # perl reads the secret from its environment
    grep -rlF --null -f "$file" "$OUT" 2>/dev/null |
      S=$(cat "$file") xargs -0 -r perl -pi -e 's/\Q$ENV{S}\E/[REDACTED]/g'
  done
}

finalize() {
  local rc=$?
  trap - EXIT
  gui_recorder_stop
  keyring_watcher_stop
  local id
  for id in "${EXPECTED[@]}"; do
    # Slurped: jq 1.6 (Ubuntu 22.04) takes the -e status from the last input only.
    jq -se --arg id "$id" 'any(.[]; .id == $id)' "$CHECKS" >/dev/null 2>&1 ||
      check "$id" reached fail "the scenario stopped before this criterion (runner exit $rc)"
  done
  cp -a "$STATE/out/." "$EVID/session/" 2>/dev/null
  rm -f "$EVID/session/ready"
  local line
  while IFS= read -r line; do
    id=$(jq -r .id <<<"$line")
    jq . <<<"$line" >"$RES/$id.json"
  done < <(jq -cs --arg guest "$GUEST" --arg format "$FORMAT" --arg scenario "$SCENARIO" \
    --arg run "$RUN_ID" '
    group_by(.id)[] | . as $c | {
      schema: 1, id: $c[0].id, criterion: $c[0].criterion, guest: $guest, format: $format,
      scenario: $scenario, run: $run,
      status: (if any($c[]; .status == "fail") then "fail"
               elif any($c[]; .status == "manual-gate") then "manual-gate"
               elif any($c[]; .status == "skipped-missing-prereq") then "skipped-missing-prereq"
               else "pass" end),
      checks: [$c[] | del(.id, .criterion)],
      gui_proof: ([$c[] | select(.status == "manual-gate") | .evidence[]] | unique)
    }' "$CHECKS")
  redact
  echo "$rc" >"$OUT/runner-exit-code"
  log "results written to $RES"
  exit 0
}

# --- tester, session and app ----------------------------------------------------

tester_env() { # env(1) arguments of the tester's non-graphical login environment
  printf '%s\n' "HOME=$TESTER_HOME" "USER=$TESTER" "LOGNAME=$TESTER" "LANG=C.UTF-8" \
    "PATH=/usr/local/bin:/usr/bin:/bin" "XDG_RUNTIME_DIR=/run/user/$TESTER_UID" \
    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$TESTER_UID/bus"
}

# Directories in the tester's home are created by the tester: `install -d -o`
# would leave the parents it creates (~/.local, ~/.local/share) owned by root.
tester_mkdir() { runuser -u "$TESTER" -- mkdir -p "$@"; }

tester_run() { # <command...> as the tester, user bus, outside the graphical session
  local -a env_args
  mapfile -t env_args < <(tester_env)
  runuser -u "$TESTER" -- env -i "${env_args[@]}" "$@"
}

hermes_cli() { # <args...> the managed launcher, as the supervisor runs it
  local launcher=$HERMES_HOME/runtime/.local/bin/hermes
  [ -x "$launcher" ] || return 127
  local -a env_args
  mapfile -t env_args < <(tester_env)
  runuser -u "$TESTER" -- env -i "${env_args[@]}" HERMES_HOME="$HERMES_HOME" \
    PATH="$HERMES_HOME/runtime/.local/bin:$HERMES_HOME/node/bin:$HERMES_HOME/bin:/usr/local/bin:/usr/bin:/bin" \
    "$launcher" "$@"
}

# Runs <script> inside the tty1 graphical session (see guest/session.sh). A
# job that times out is killed (its process group) after its process tree is
# kept as evidence, so the session goes on with the next job.
in_session() { # <name> <timeout-s> <script>
  SPOOL_SEQ=$((SPOOL_SEQ + 1))
  local job pid
  job=$(printf '%04d-%s' "$SPOOL_SEQ" "$(gui_slug "$1")")
  # shellcheck disable=SC2016 # expanded by the session shell
  printf 'set -u\ncd "$HOME" || exit 1\n%s\n' "$3" >"$STATE/spool/.$job"
  chmod 0644 "$STATE/spool/.$job"
  mv "$STATE/spool/.$job" "$STATE/spool/$job.sh"
  if ! wait_until "$2" 1 test -e "$STATE/out/$job.rc"; then
    log "session job $job timed out"
    ps -eo pid,ppid,pgid,etime,stat,args --forest >"$EVID/logs/timeout-$job-ps.txt" 2>&1
    pid=$(cat "$STATE/out/$job.pid" 2>/dev/null)
    [ -n "$pid" ] && kill -TERM -- "-$pid" 2>/dev/null
    return 124
  fi
  return "$(cat "$STATE/out/$job.rc")"
}

session_start() {
  TESTER_UID=$(id -u "$TESTER")
  install -d -m 0755 "$STATE" "$STATE/spool"
  install -d -m 0755 -o "$TESTER" -g "$TESTER" "$STATE/out"
  install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
  cat >/etc/systemd/system/getty@tty1.service.d/hermuse-smoke-autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin $TESTER %I \$TERM
EOF
  cat >"$TESTER_HOME/.bash_profile" <<'EOF'
# hermuse smoke: the tty1 autologin is the test desktop session. Like a
# display manager, source ~/.profile first (it adds ~/.local/bin to PATH).
[ -f "$HOME/.profile" ] && . "$HOME/.profile"
if [ "$(tty)" = /dev/tty1 ]; then exec /bin/sh /opt/hermuse-smoke/guest/session.sh; fi
EOF
  chown "$TESTER:$TESTER" "$TESTER_HOME/.bash_profile"
  # Default browser of the tester: a recorder (guest/fake-browser.sh).
  tester_mkdir "$TESTER_HOME/.local/share/applications"
  cat >"$TESTER_HOME/.local/share/applications/hermuse-smoke-browser.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Smoke browser
Exec=/opt/hermuse-smoke/guest/fake-browser.sh %u
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
NoDisplay=true
EOF
  chown "$TESTER:$TESTER" "$TESTER_HOME/.local/share/applications/hermuse-smoke-browser.desktop"
  tester_run xdg-mime default hermuse-smoke-browser.desktop x-scheme-handler/http \
    x-scheme-handler/https text/html >/dev/null 2>&1
  systemctl daemon-reload
  systemctl restart getty@tty1.service
  if ! wait_until "$(T 180)" 2 test -e "$STATE/out/ready"; then
    log "the tty1 test session did not start"
    return 1
  fi
  gui_init "$EVID"
  cp "$STATE/out/session-info.txt" "$EVID/session/" 2>/dev/null
  return 0
}

# A fresh login of the tester (e.g. after a user-side install): the tty1
# session ends, getty logs the tester in again, session.sh comes back up.
# getty stays stopped until the old session is gone: it would otherwise log
# the tester in again at once, next to the old session and its X server.
session_restart() {
  local session
  systemctl stop getty@tty1.service
  rm -f "$STATE/out/ready"
  for session in $(loginctl show-user "$TESTER" -p Sessions --value 2>/dev/null); do
    loginctl terminate-session "$session"
  done
  if ! wait_until 60 1 not pgrep -u "$TESTER" -x Xvfb; then
    log "the previous session's Xvfb outlived the session: killing it"
    pkill -KILL -u "$TESTER" -x Xvfb
    wait_until 10 1 not pgrep -u "$TESTER" -x Xvfb
  fi
  systemctl start getty@tty1.service
  wait_until "$(T 180)" 2 test -e "$STATE/out/ready"
}

keyring_watcher_start() { # answers gnome-keyring prompts per $STATE/keyring-policy
  echo accept >"$STATE/keyring-policy"
  (
    while :; do
      if [ -n "$(xdotool search --onlyvisible --class gcr-prompter 2>/dev/null | head -n 1)" ]; then
        kind=$(gui_keyring_prompt "$(cat "$STATE/keyring-policy")" "$SECRETS/keyring-password" 1)
        echo "$(date -u +%FT%TZ) $kind" >>"$EVID/logs/keyring-prompts.log"
      fi
      sleep 2
    done
  ) &
  KEYRING_WATCHER_PID=$!
}

keyring_watcher_stop() {
  [ -n "$KEYRING_WATCHER_PID" ] || return 0
  kill "$KEYRING_WATCHER_PID" 2>/dev/null
  KEYRING_WATCHER_PID=''
  return 0
}

app_pid() { pgrep -n -u "$TESTER" -x hermuse_app; }
app_gone() { ! pgrep -u "$TESTER" -x hermuse_app >/dev/null; }

app_command() { # [extra args...] -> shell words
  local arg
  case $FORMAT in
    deb) printf '%s' "$DEB_EXEC" ;;
    appimage) printf "'%s'" "$APPIMAGE_PATH" ;;
  esac
  for arg; do printf " '%s'" "$arg"; done
}

window_maximized() {
  # shellcheck disable=SC2034 # WINDOW X Y SCREEN are set by the eval
  local wid WINDOW X Y WIDTH HEIGHT SCREEN
  wid=$(gui_window "^${WINDOW_TITLE}\$" 0) || return 1
  eval "$(xdotool getwindowgeometry --shell "$wid" 2>/dev/null)" || return 1
  # shellcheck disable=SC2153 # set by the eval
  [ "${WIDTH:-0}" -ge 1800 ] && [ "${HEIGHT:-0}" -ge 950 ]
}

# Starts the app inside the session from a fresh arbitrary directory and waits
# for its window. The app gets only HERMES_HOME on top of the session env.
app_launch() { # <label> [raw shell command]
  local label=$1 command=${2:-} cwd
  cwd=$(mktemp -d /tmp/hermuse-cwd.XXXXXX)
  chown "$TESTER:$TESTER" "$cwd"
  [ -n "$command" ] || command=$(app_command)
  in_session "launch-$label" 60 \
    "cd '$cwd' && HERMES_HOME='$HERMES_HOME' setsid -f $command >>'$STATE/out/app-$label.log' 2>&1 </dev/null" ||
    return 1
  gui_window "^${WINDOW_TITLE}\$" "$(T 180)" >/dev/null || return 1
  # Maximized, as a user does with a long setup page (still scrollable). The
  # next screenshot must see the final layout: a click computed on the small
  # window would land beside the button once the window grows.
  wmctrl -r "$WINDOW_TITLE" -b add,maximized_vert,maximized_horz 2>/dev/null
  wait_until 20 1 window_maximized || log "the window did not maximize"
  sleep 3
  APP_PID=$(app_pid)
  [ -n "$APP_PID" ] || return 1
  APP_DIR=$(dirname "$(readlink -f "/proc/$APP_PID/exe")")
  log "app running: pid $APP_PID from $APP_DIR (cwd $cwd)"
  return 0
}

app_close() { # [timeout-s]: a running install stage or APT transaction finishes first
  app_gone && return 0
  gui_close "$WINDOW_TITLE"
  wait_until "${1:-$(T 300)}" 2 app_gone
}

ui_click() { # <label> <timeout-s> [line|any|filled]: 0 clicked, 1 not found
  gui_click "$@" >/dev/null
}

# The pointer to the middle of the window: a hovered rail item shows its
# tooltip, which covers the top of the rail and of the page.
ui_pointer_away() { # <window-id>
  # shellcheck disable=SC2034 # WINDOW and SCREEN are set by the eval
  local WINDOW X Y WIDTH HEIGHT SCREEN
  eval "$(xdotool getwindowgeometry --shell "$1" 2>/dev/null)" || return 0
  [ -n "${WIDTH:-}" ] && xdotool mousemove --sync $((X + WIDTH / 2)) $((Y + HEIGHT / 2))
  sleep 1
}

# Clicks an item of the icon rail: 1-based from the top (Chat, Feed, Ideas,
# Goals, Library) or `last` (Settings, at the bottom).
ui_rail() { # <n|last>
  local wid xy
  local -a items
  wid=$(gui_window "^${WINDOW_TITLE}\$" 5) || return 1
  ui_pointer_away "$wid"
  mapfile -t items < <(gui_rail_items "$wid")
  [ "${#items[@]}" -ge 6 ] || return 1
  if [ "$1" = last ]; then xy=${items[-1]}; else xy=${items[$(($1 - 1))]}; fi
  # shellcheck disable=SC2086 # "x y"
  xdotool mousemove --sync $xy click 1
  sleep 1
  ui_pointer_away "$wid"
}

# Settings (bottom of the rail) lists the instances, each with its Connections.
ui_connections() {
  ui_click "$UI_BACK_TO_CHAT" 10 || true
  ui_click "$UI_CONNECTIONS" 5 || { ui_rail last && ui_click "$UI_CONNECTIONS" 60; }
}

# Connections > the bridge card > its Connect button. The provider list is
# long: its search field brings the card up. A click opens the row, whose
# body holds the filled Connect button (the row's own "Connect" is a label
# that folds the row again).
ui_bridge_connect() {
  ui_connections || return 1
  # The page keeps its scroll offset: the search field is at its very top.
  gui_scroll up 60
  sleep 1
  ui_click "$UI_SEARCH_CONNECTIONS" 30 any || return 1
  xdotool type --delay 40 "$UI_BRIDGE_CARD"
  sleep 2
  ui_click "$UI_BRIDGE_CARD" 30 any && ui_click "$UI_CONNECT" 30 filled
}

# Waits for the gate and clicks through it; polkit dialogs are handled by the
# caller. Returns 1 when neither gate button shows up.
ui_prepare() {
  ui_click "$UI_LOCAL_CHOICE" "$(T 30)" || true
  ui_click "$UI_PREPARE" "$(T 90)" || ui_click "$UI_CHECK_AGAIN" 10
}

# A transient failure the app reports with its retry button, e.g. HTTP 429
# from raw.githubusercontent.com while many legs fetch at once: a user reads
# the error and clicks the button. The screen is read at most every minute,
# the button clicked at most every 3 minutes; each click is kept as evidence.
RETRY_LOOKED=-1000 RETRY_CLICKED=-1000
retry_when_offered() { # <id>
  [ $((SECONDS - RETRY_LOOKED)) -ge 60 ] && [ $((SECONDS - RETRY_CLICKED)) -ge 180 ] || return 0
  RETRY_LOOKED=$SECONDS
  local shot xy label words
  shot=$(gui_shot retry-offered) || return 0
  words=$(gui_ocr "$shot" | awk -F'\t' 'NR > 1 && $12 != "" { w = tolower($12); gsub(/[^a-z]/, "", w); print w }')
  if grep -qxE 'cannot|failed|error|unable' <<<"$words"; then
    for label in "$UI_RETRY_STAGE" "$UI_CHECK_AGAIN"; do
      xy=$(gui_locate "$shot" "$label" line) || continue
      # shellcheck disable=SC2086 # "x y"
      xdotool mousemove --sync $xy click 1
      RETRY_CLICKED=$SECONDS
      check "$1" user-retry pass "the app reported an error with '$label': clicked it, as a user does" "$shot"
      return 0
    done
  fi
  rm -f "$shot"
}

ready_or_retry() { # <id> <predicate...>: the predicate, else maybe the app's retry button
  local id=$1
  shift
  "$@" && return 0
  retry_when_offered "$id"
  return 1
}

backend_up() { python3 "$SMOKE_DIR/guest/probe.py" backend >"$EVID/probe/backend.json" 2>&1; }
# The app holds a connection to its supervised backend (not merely spawned it).
app_connected() {
  local pid
  pid=$(app_pid)
  [ -n "$pid" ] && python3 "$SMOKE_DIR/guest/probe.py" connection --app-pid "$pid" >"$EVID/probe/connection.json" 2>&1
}

helper_plan() { # <out-file>: read-only plan of the bundled helper, as the tester
  tester_run sh "$APP_DIR/libexec/hermuse-linux-setup" plan >"$1" 2>"$1.stderr"
}

dpkg_snapshot() { # <file>
  dpkg-query -W -f '${Package} ${Version} ${Status}\n' | sort >"$1"
}

apt_busy() { pgrep -x apt-get >/dev/null || pgrep -x dpkg >/dev/null; }
apt_idle() { ! apt_busy; }
dpkg_running() { pgrep -x dpkg >/dev/null; }
installed_names() { grep ' install ok installed$' "$1" | cut -d' ' -f1 | sort -u; }

sha_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# --- criterion checks ------------------------------------------------------------

c0_test_base() {
  local id=c0-test-base
  # shellcheck disable=SC1091
  . /etc/os-release
  cp /etc/os-release "$EVID/logs/os-release"
  check "$id" os pass "$PRETTY_NAME ($VERSION_CODENAME), $(uname -r)" "$EVID/logs/os-release"
  dpkg_snapshot "$EVID/logs/dpkg-initial.txt"
  local -a missing=() present=()
  local pkg
  for pkg in xvfb openbox xdotool wmctrl imagemagick tesseract-ocr pkexec policykit-1-gnome \
    dbus-user-session libgtk-3-bin libsecret-tools xdg-utils jq; do
    grep -q "^$pkg .* install ok installed$" "$EVID/logs/dpkg-initial.txt" || missing+=("$pkg")
  done
  pass_or_fail "$id" desktop-test-base "${#missing[@]}" \
    "test desktop base installed${missing[*]:+; missing: ${missing[*]}}" "$EVID/logs/dpkg-initial.txt"
  # What the app must provide itself: none of it may pre-exist.
  for pkg in docker.io docker-ce moby-engine podman-docker gnome-keyring kwalletmanager kwalletd5 kwalletd6 \
    keepassxc nodejs; do
    grep -q "^$pkg .* install ok installed$" "$EVID/logs/dpkg-initial.txt" && present+=("package:$pkg")
  done
  local tool
  for tool in docker dockerd node npm uv uvx hermes flutter dart gnome-keyring-daemon; do
    command -v "$tool" >/dev/null 2>&1 && present+=("command:$tool")
    [ -e "$TESTER_HOME/.local/bin/$tool" ] && present+=("$TESTER_HOME/.local/bin/$tool")
  done
  [ -e "$TESTER_HOME/.hermes" ] && present+=("$TESTER_HOME/.hermes")
  grep -lsx 'Name=org.freedesktop.secrets' /usr/share/dbus-1/services/*.service >/dev/null &&
    present+=("activatable org.freedesktop.secrets")
  pass_or_fail "$id" nothing-preinstalled "${#present[@]}" \
    "no Hermes, uv, Node, Docker, Flutter/Dart or Secret Service provider${present[*]:+; found: ${present[*]}}"
  local artifact name sha ok=0
  for artifact in "$DEB_FILE" "$APPIMAGE_FILE"; do
    [ -f "$artifact" ] || continue
    name=$(basename "$artifact")
    sha=$(jq -r --arg n "$name" '.artifacts[] | select(.name == $n) | .sha256' "$VERSION_JSON")
    [ "$(sha_of "$artifact")" = "$sha" ] || ok=1
  done
  pass_or_fail "$id" artifact-digest "$ok" "tested files match VERSION.json .artifacts[].sha256"
}

bundle_integrity() { # <id> <bundle-dir>: embedded bridge + helper against VERSION.json
  local id=$1 dir=$2 cliproxy helper ok=0 detail
  cliproxy=$(jq -r '.cliproxy.binary_sha256' "$VERSION_JSON")
  helper=$(jq -r '.linux_helper.sha256' "$VERSION_JSON")
  [ "$(sha_of "$dir/lib/cliproxy")" = "$cliproxy" ] || ok=1
  [ "$(sha_of "$dir/libexec/hermuse-linux-setup")" = "$helper" ] || ok=1
  [ -x "$dir/lib/cliproxy" ] && [ -x "$dir/libexec/hermuse-linux-setup" ] || ok=1
  detail="lib/cliproxy $(sha_of "$dir/lib/cliproxy"), libexec/hermuse-linux-setup $(sha_of "$dir/libexec/hermuse-linux-setup")"
  pass_or_fail "$id" bundle-integrity "$ok" "$detail (expected $cliproxy / $helper, both executable)"
}

install_deb() { # <id> <deb-file> <expected-version>
  local id=$1 deb=$2 version=$3 log ok=0
  log=$EVID/logs/apt-install-$(basename "$2" .deb).log
  { apt-get update && apt-get install -y "$deb"; } >"$log" 2>&1 || ok=1
  pass_or_fail "$id" apt-install "$ok" "apt-get install $(basename "$deb") resolved and installed" "$log"
  [ "$ok" = 0 ] || return 1
  local installed
  installed=$(dpkg-query -W -f '${Version}' "$DEB_PACKAGE" 2>/dev/null)
  pass_or_fail "$id" deb-version "$([ "$installed" = "$version" ] && echo 0 || echo 1)" \
    "installed $DEB_PACKAGE $installed (expected $version)"
}

install_artifact() { # <id>
  local id=$1
  if [ "$FORMAT" = deb ]; then
    install_deb "$id" "$DEB_FILE" "$(jq -r '.app.debian_version' "$VERSION_JSON")" || return 1
    APP_DIR=$DEB_ROOT
    local ok=0 icon
    [ "$(readlink -f /usr/bin/hermuse-agent)" = "$DEB_ROOT/hermuse_app" ] || ok=1
    desktop-file-validate "$DESKTOP_FILE" >"$EVID/logs/desktop-file-validate.log" 2>&1 || ok=1
    for icon in 48x48 128x128 256x256 512x512; do
      [ -s "/usr/share/icons/hicolor/$icon/apps/$APP_ID.png" ] || ok=1
    done
    [ -s "/usr/share/icons/hicolor/scalable/apps/$APP_ID.svg" ] || ok=1
    cp "$DESKTOP_FILE" "$EVID/logs/" 2>/dev/null
    pass_or_fail "$id" desktop-integration "$ok" \
      "/usr/bin/hermuse-agent link, valid $APP_ID.desktop, hicolor 48/128/256/512 + scalable icons" \
      "$EVID/logs/desktop-file-validate.log" "$EVID/logs/$APP_ID.desktop"
    DEB_EXEC=$(sed -n 's/^Exec=//p' "$DESKTOP_FILE" | head -n 1 | sed -E 's/ %[fFuUdDnNickvm]//g')
    bundle_integrity "$id" "$DEB_ROOT"
    return 0
  fi
  # AppImage: a machine where FUSE cannot be used, then the file placed and
  # marked executable the way a file manager does it; nothing else is
  # prepared. The mount helpers and libfuse2 are purged; a FUSE library the
  # boot chain depends on (grub-common needs libfuse3) stays installed but is
  # unusable: the device node is removed and the module may not load.
  local fuse=() pkg
  for pkg in fuse fuse3 libfuse2 libfuse2t64; do
    dpkg-query -W -f '${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' && fuse+=("$pkg")
  done
  if [ ${#fuse[@]} -gt 0 ]; then
    apt-get purge -y "${fuse[@]}" >"$EVID/logs/apt-purge-fuse.log" 2>&1
  fi
  local helper path diverted=()
  for helper in fusermount fusermount3; do
    # Only when a purge could not remove it (a dependency of the base system).
    path=$(command -v "$helper") || continue
    dpkg-divert --local --rename --divert "$path.hermuse-smoke-disabled" --add "$path" \
      >>"$EVID/logs/apt-purge-fuse.log" 2>&1 && diverted+=("$path")
  done
  printf 'install fuse /bin/false\n' >/etc/modprobe.d/hermuse-smoke-no-fuse.conf
  modprobe -r fuse 2>/dev/null
  rm -f /dev/fuse
  local ok=0 found=() kept=''
  command -v fusermount >/dev/null && found+=(fusermount)
  command -v fusermount3 >/dev/null && found+=(fusermount3)
  [ -e /dev/fuse ] && found+=(/dev/fuse)
  # A library the boot chain keeps (grub-common depends on libfuse2 on
  # Debian 12) cannot mount anything without the helpers and the device.
  ldconfig -p | grep -q 'libfuse\.so\.2' && kept='; libfuse.so.2 kept for the boot chain, unusable'
  [ ${#found[@]} -eq 0 ] || ok=1
  pass_or_fail "$id" no-fuse "$ok" \
    "FUSE unusable: no fusermount/fusermount3, no /dev/fuse (purged: ${fuse[*]:-none}${diverted[*]:+; diverted: ${diverted[*]}})$kept${found[*]:+; still present: ${found[*]}}" \
    "$EVID/logs/apt-purge-fuse.log"
  tester_mkdir "$TESTER_HOME/Applications"
  APPIMAGE_PATH=$TESTER_HOME/Applications/$(basename "$APPIMAGE_FILE")
  install -o "$TESTER" -g "$TESTER" -m 0644 "$APPIMAGE_FILE" "$APPIMAGE_PATH"
  tester_run chmod u+x "$APPIMAGE_PATH"
  # Static checks on a root-side extraction (never the copy the tester runs).
  appimage_extract_root /root/appimage-inspect
  local root=/root/appimage-inspect/squashfs-root
  ok=0
  desktop-file-validate "$root/$APP_ID.desktop" >"$EVID/logs/desktop-file-validate.log" 2>&1 || ok=1
  grep -qx 'Exec=hermuse_app' "$root/$APP_ID.desktop" || ok=1
  pass_or_fail "$id" appimage-desktop-entry "$ok" "root $APP_ID.desktop valid, Exec=hermuse_app" \
    "$EVID/logs/desktop-file-validate.log"
  bundle_integrity "$id" "$root/usr/bin"
}

appimage_extract_root() { # <dir>: root-side --appimage-extract of the tested AppImage
  rm -rf "$1" && mkdir -p "$1" && install -m 0755 "$APPIMAGE_FILE" "$1/tested.AppImage" &&
    (cd "$1" && ./tested.AppImage --appimage-extract >/dev/null 2>&1)
  local rc=$?
  rm -f "$1/tested.AppImage"
  return "$rc"
}

window_checks() { # <id> <label>
  local id=$1 label=$2 wid shot props ok=0
  wid=$(gui_window "^${WINDOW_TITLE}\$" 5) || {
    check "$id" "window-$label" fail "no window titled '$WINDOW_TITLE'"
    return 1
  }
  props=$EVID/logs/window-$label.txt
  gui_window_props "$wid" >"$props"
  grep -q "\"$APP_ID\"" "$props" || ok=1
  pass_or_fail "$id" "window-$label" "$ok" "'$WINDOW_TITLE' mapped, WM_CLASS carries $APP_ID" "$props"
  sleep 5
  shot=$(gui_shot "window-$label")
  # The first-run screens name Hermuse; the shell of a prepared instance
  # shows the local instance card instead.
  local phrase read_back=''
  for phrase in Hermuse 'This computer' 'Open computer'; do
    gui_locate "$shot" "$phrase" any >/dev/null && read_back=$phrase && break
  done
  if [ -n "$read_back" ]; then
    check "$id" "window-content-$label" pass "rendered UI text '$read_back' read back by OCR" "$shot"
  else
    check "$id" "window-content-$label" manual-gate "window content not recognised by OCR: review the screenshot" "$shot"
  fi
}

c1_launch() {
  local id=c1-launch
  if [ "$FORMAT" = deb ]; then
    # Menu path: the desktop entry through GIO, from an arbitrary directory.
    local cwd
    cwd=$(mktemp -d /tmp/hermuse-cwd.XXXXXX)
    chown "$TESTER:$TESTER" "$cwd"
    if in_session launch-menu 60 "cd '$cwd' && HERMES_HOME='$HERMES_HOME' gtk-launch $APP_ID" &&
      gui_window "^${WINDOW_TITLE}\$" "$(T 180)" >/dev/null; then
      APP_PID=$(app_pid)
      window_checks "$id" menu
      app_close
    else
      check "$id" window-menu fail "gtk-launch $APP_ID opened no window"
    fi
  fi
  if app_launch first; then
    check "$id" launch pass "started ($FORMAT) from an arbitrary cwd without flags; bundle $APP_DIR"
    window_checks "$id" first
    if [ "$FORMAT" = appimage ]; then
      case $APP_DIR in
        /tmp/appimage_extracted_*) check "$id" appimage-extract-policy pass "runtime extracted to $APP_DIR (no FUSE mount)" ;;
        *) check "$id" appimage-extract-policy fail "unexpected bundle location $APP_DIR" ;;
      esac
    fi
  else
    check "$id" launch fail "no '$WINDOW_TITLE' window after launch" "$(gui_shot launch-failed)"
    return 1
  fi
}

c2_prepare() {
  local id=c2-prepare
  # The real shell files, before anything is installed (see c4).
  sha_of "$TESTER_HOME/.bashrc" >"$EVID/logs/rc-before.txt"
  sha_of "$TESTER_HOME/.profile" >>"$EVID/logs/rc-before.txt"
  helper_plan "$EVID/logs/helper-plan-before.jsonl"
  check "$id" helper-plan-before pass "missing: $(jq -r 'select(.event == "missing") | .package' \
    "$EVID/logs/helper-plan-before.jsonl" 2>/dev/null | tr '\n' ' ')" "$EVID/logs/helper-plan-before.jsonl"
  dpkg_snapshot "$EVID/logs/dpkg-before-prepare.txt"
  local shot
  ui_click "$UI_LOCAL_CHOICE" "$(T 60)" || true
  if ! shot=$(gui_click "$UI_PREPARE" "$(T 120)"); then
    check "$id" gate fail "no '$UI_PREPARE' button on the preparation gate" "$(gui_shot gate-missing)"
    return 1
  fi
  if gui_locate "$shot" docker any >/dev/null && gui_locate "$shot" root any >/dev/null; then
    check "$id" docker-group-warning pass "the gate names the docker group and root before consent" "$shot"
  else
    check "$id" docker-group-warning manual-gate "confirm the gate warns that the docker group is root-equivalent" "$shot"
  fi
  # 1. Refused elevation leaves everything incomplete.
  if gui_polkit cancel "$SECRETS/tester-password" "$(T 90)"; then
    check "$id" polkit-dialog pass "real polkit dialog shown for the listed operations, then cancelled" \
      "$(newest "$EVID/screens" '*polkit-dialog-cancel*')"
  else
    check "$id" polkit-dialog fail "no polkit authentication dialog after '$UI_PREPARE'" "$(gui_shot no-polkit)"
    return 1
  fi
  sleep 15
  dpkg_snapshot "$EVID/logs/dpkg-after-cancel.txt"
  local ok=0
  cmp -s "$EVID/logs/dpkg-before-prepare.txt" "$EVID/logs/dpkg-after-cancel.txt" || ok=1
  [ -e "$HERMES_HOME/hermes-agent" ] && ok=1
  pass_or_fail "$id" cancel-changes-nothing "$ok" \
    "after the cancelled dialog: no package change, no Hermes install started" "$EVID/logs/dpkg-after-cancel.txt"
  shot=$(gui_shot after-cancel)
  if gui_locate "$shot" "$UI_PREPARE" line >/dev/null || gui_locate "$shot" "$UI_CHECK_AGAIN" line >/dev/null; then
    check "$id" cancel-shown-incomplete pass "the gate is still offered after the refusal" "$shot"
  else
    check "$id" cancel-shown-incomplete manual-gate "confirm the refusal is shown as incomplete" "$shot"
  fi
  # 2. Consent once for everything listed.
  if ! { ui_click "$UI_PREPARE" "$(T 60)" || ui_click "$UI_CHECK_AGAIN" 10; }; then
    check "$id" retry fail "no '$UI_PREPARE'/'$UI_CHECK_AGAIN' after the refusal" "$(gui_shot retry-missing)"
    return 1
  fi
  if ! gui_polkit accept "$SECRETS/tester-password" "$(T 90)"; then
    check "$id" consent fail "no polkit dialog on retry" "$(gui_shot no-polkit-retry)"
    return 1
  fi
  check "$id" consent pass "authenticated once in the real polkit dialog"
  # 3. Closing the app while dpkg runs must not interrupt the transaction.
  if wait_until "$(T 600)" 1 dpkg_running; then
    sleep 5
    local closed_at=$SECONDS
    gui_close "$WINDOW_TITLE"
    log "closed the window while APT was running"
    wait_until "$(T 3600)" 5 apt_idle
    local audit=$EVID/logs/dpkg-audit.txt
    dpkg --audit >"$audit" 2>&1
    ok=0
    [ -s "$audit" ] && ok=1
    grep -c '^Start-Date' /var/log/apt/history.log >"$EVID/logs/apt-history-count.txt"
    [ "$(grep -c '^Start-Date' /var/log/apt/history.log)" = "$(grep -c '^End-Date' /var/log/apt/history.log)" ] || ok=1
    cp /var/log/apt/history.log "$EVID/logs/apt-history.log" 2>/dev/null
    pass_or_fail "$id" close-during-apt "$ok" \
      "window closed $((SECONDS - closed_at))s before APT ended: dpkg --audit clean, every APT run has an End-Date" \
      "$audit" "$EVID/logs/apt-history.log"
    if wait_until "$(T 600)" 5 app_gone; then
      check "$id" close-waits-then-exits pass "the app exited after the privileged transaction"
    else
      check "$id" close-waits-then-exits fail "the app kept running after its close was requested"
    fi
  else
    check "$id" close-during-apt fail "APT never ran after consent" "$(gui_shot no-apt)"
    return 1
  fi
  # 4. Relaunch: the local choice again, then the gate for what is left or,
  # with nothing left, the Hermes install at once (its journal appears). c4
  # interrupts that install: nothing else may run in between.
  if ! app_launch after-apt; then
    check "$id" relaunch fail "no window on relaunch"
    return 1
  fi
  ui_click "$UI_LOCAL_CHOICE" 20 || true
  # The gate buttons also retry a failure the app reports (a transient HTTP
  # 429 while fetching the installer): minutes may pass before the install.
  local deadline=$((SECONDS + $(T 900))) xy
  while ! find_journal >/dev/null; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      check "$id" resume fail "neither the gate nor the Hermes install after the relaunch" "$(gui_shot resume-missing)"
      return 1
    fi
    shot=$(gui_shot resume) || return 1
    if xy=$(gui_locate "$shot" "$UI_PREPARE" line) || xy=$(gui_locate_filled "$shot" "$UI_PREPARE") ||
      xy=$(gui_locate "$shot" "$UI_CHECK_AGAIN" line); then
      # shellcheck disable=SC2086 # "x y"
      xdotool mousemove --sync $xy click 1
      if gui_polkit accept "$SECRETS/tester-password" "$(T 45)"; then
        check "$id" second-consent pass "remaining privileged operations authorised on resume" "$shot"
      fi
    else
      rm -f "$shot"
    fi
    sleep 2
  done
}

# After c4 interrupted the install: the preparation left nothing missing and
# removed nothing.
c2_dependencies() {
  local id=c2-prepare ok=0
  wait_until "$(T 900)" 10 deps_ready
  helper_plan "$EVID/logs/helper-plan-after.jsonl"
  jq -se 'any(.[]; .event == "missing")' "$EVID/logs/helper-plan-after.jsonl" >/dev/null 2>&1 && ok=1
  pass_or_fail "$id" dependencies-satisfied "$ok" "bundled helper plan reports nothing missing" \
    "$EVID/logs/helper-plan-after.jsonl"
  dpkg_snapshot "$EVID/logs/dpkg-after-prepare.txt"
  diff "$EVID/logs/dpkg-before-prepare.txt" "$EVID/logs/dpkg-after-prepare.txt" >"$EVID/logs/dpkg-prepare.diff"
  local removed
  removed=$(comm -23 <(installed_names "$EVID/logs/dpkg-before-prepare.txt") \
    <(installed_names "$EVID/logs/dpkg-after-prepare.txt") | tr '\n' ' ')
  pass_or_fail "$id" nothing-removed "$([ -z "$removed" ] && echo 0 || echo 1)" \
    "APT removed nothing${removed:+; removed: $removed}" "$EVID/logs/dpkg-prepare.diff"
}

deps_ready() {
  helper_plan "$STATE/plan-poll.jsonl" &&
    jq -se 'any(.[]; .result.ok == true) and all(.[]; .event != "missing")' "$STATE/plan-poll.jsonl" >/dev/null 2>&1
}

secret_roundtrip() { # <id>: fixture secret through the real Secret Service
  local id=$1 value ok=0 log=$EVID/logs/secret-roundtrip.log
  value=hermuse-smoke-$RUN_ID-$RANDOM
  {
    printf '%s' "$value" | tester_run secret-tool store --label='Hermuse smoke fixture' hermuse-smoke fixture &&
      [ "$(tester_run secret-tool lookup hermuse-smoke fixture)" = "$value" ] &&
      tester_run secret-tool clear hermuse-smoke fixture &&
      ! tester_run secret-tool lookup hermuse-smoke fixture
  } >"$log" 2>&1 || ok=1
  pass_or_fail "$id" fixture-secret-roundtrip "$ok" "store, lookup, clear of a fixture secret via secret-tool" "$log"
}

secrets_owner() {
  tester_run busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus \
    NameHasOwner s org.freedesktop.secrets 2>/dev/null | grep -q 'b true'
}

no_plaintext_secrets() { # <id> <name>
  local hits=$EVID/logs/plaintext-scan-$2.txt
  grep -rlF 'hermes/hermuse-local/' "$TESTER_HOME" --exclude-dir=keyrings --exclude-dir=.cache \
    --exclude-dir="$(basename "$HERMES_HOME")" >"$hits" 2>/dev/null
  pass_or_fail "$1" "$2" "$([ -s "$hits" ] && echo 1 || echo 0)" \
    "no file outside the keyring holds the app's secret keys (hermes/hermuse-local/...)" "$hits"
}

c3_keyring() {
  local id=c3-keyring
  local ok=0
  grep -q '^gnome-keyring .* install ok installed$' "$EVID/logs/dpkg-after-prepare.txt" 2>/dev/null || ok=1
  pass_or_fail "$id" provider-installed "$ok" "gnome-keyring installed by the preparation (none before)"
  secret_roundtrip "$id"
  if wait_until "$(T 120)" 3 secrets_owner; then
    check "$id" provider-on-user-bus pass "org.freedesktop.secrets owned on the user bus"
  else
    check "$id" provider-on-user-bus fail "org.freedesktop.secrets has no owner on the user bus"
  fi
  no_plaintext_secrets "$id" no-plaintext
}

c3_keyring_locked() {
  local id=c3-keyring
  app_close
  local locked=$EVID/logs/keyring-lock.txt
  tester_run gdbus call --session --dest org.freedesktop.secrets --object-path /org/freedesktop/secrets \
    --method org.freedesktop.Secret.Service.Lock "['/org/freedesktop/secrets/aliases/default']" >"$locked" 2>&1
  tester_run busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/aliases/default \
    org.freedesktop.Secret.Collection Locked >>"$locked" 2>&1
  if ! grep -q 'b true' "$locked"; then
    check "$id" lock-keyring fail "could not lock the default collection" "$locked"
    return 1
  fi
  echo cancel >"$STATE/keyring-policy"
  local prompts_before
  prompts_before=$(wc -l <"$EVID/logs/keyring-prompts.log" 2>/dev/null || echo 0)
  app_launch locked-keyring || return 1
  if wait_until "$(T 120)" 3 sh -c "[ \$(wc -l <'$EVID/logs/keyring-prompts.log' 2>/dev/null || echo 0) -gt $prompts_before ]"; then
    check "$id" unlock-prompt-refused pass "the locked keyring raised the system unlock prompt; it was refused" \
      "$(newest "$EVID/screens" '*keyring-prompt-cancel*')"
  else
    check "$id" unlock-prompt-refused manual-gate "no unlock prompt observed: review how the locked keyring is reported" \
      "$(gui_shot locked-no-prompt)"
  fi
  sleep 20
  if app_connected; then
    check "$id" locked-no-connection fail "the app connected an instance with a locked keyring" "$EVID/probe/connection.json"
  else
    check "$id" locked-no-connection pass "no connected instance while the keyring stays locked" "$EVID/probe/connection.json"
  fi
  no_plaintext_secrets "$id" no-plaintext-when-locked
  local shot
  shot=$(gui_shot locked-state)
  if gui_locate "$shot" locked any >/dev/null || gui_locate "$shot" unlock any >/dev/null; then
    check "$id" locked-state-shown pass "the UI reports the locked keyring" "$shot"
  else
    check "$id" locked-state-shown manual-gate "confirm the UI reports the locked keyring" "$shot"
  fi
  echo accept >"$STATE/keyring-policy"
  ui_click "$UI_CHECK_AGAIN" "$(T 60)" || ui_click "$UI_RETRY_STAGE" 10 || true
  if wait_until "$(T 600)" 5 app_connected; then
    check "$id" unlock-retry pass "after unlocking, the retry reconnects the local instance" "$EVID/probe/connection.json"
  else
    check "$id" unlock-retry fail "no connection after unlocking and retrying" "$(gui_shot unlock-retry-failed)"
  fi
}

# The integrator writes the InstallJournal at <app support dir>/hermes-install.json.
find_journal() {
  local file=$APP_SUPPORT/hermes-install.json
  [ -f "$file" ] && jq -e 'has("completed_stages") and has("finished")' "$file" >/dev/null 2>&1 || return 1
  printf '%s\n' "$file"
}

journal_in_stage() { # a stage runs after at least one completed one
  local journal
  journal=$(find_journal) || return 1
  jq -e '(.completed_stages | length) >= 2 and .current_stage != null and .finished == false' "$journal" >/dev/null
}

journal_finished() {
  local journal
  journal=$(find_journal) || return 1
  jq -e '.finished == true' "$journal" >/dev/null
}

# The install c2's relaunch started is closed mid-stage as soon as a stage
# runs after two completed ones (the whole install can take 2-3 minutes).
c4_hermes_interrupt() {
  local id=c4-hermes journal ok
  if ! wait_until "$(T 1800)" 1 ready_or_retry "$id" journal_in_stage; then
    check "$id" journal fail "no install journal with a running stage under $APP_SUPPORT" "$(gui_shot no-journal)"
    return 1
  fi
  journal=$(find_journal)
  cp "$journal" "$EVID/logs/journal-at-close.json"
  ok=0
  jq -e --arg home "$HERMES_HOME" --arg pin "$PIN_COMMIT" \
    '.hermes_home == $home and .commit == $pin and .install_dir == ($home + "/hermes-agent")' \
    "$journal" >/dev/null || ok=1
  pass_or_fail "$id" journal "$ok" "journal written before the stages, pinned to $PIN_COMMIT" "$EVID/logs/journal-at-close.json"
  C4_INTERRUPTED=$(jq -r '.current_stage' "$journal")
  # The running stage (python-deps or node-deps can take minutes) completes first.
  if app_close "$(T 1800)"; then
    check "$id" close-mid-stage pass "closing during '$C4_INTERRUPTED' let the stage finish, then the app exited"
  else
    check "$id" close-mid-stage fail "the app did not exit after closing during '$C4_INTERRUPTED'"
  fi
  jq . "$journal" >"$EVID/logs/journal-after-close.json" 2>/dev/null
}

c4_hermes_resume() {
  local id=c4-hermes journal ok interrupted=$C4_INTERRUPTED
  if ! app_launch resume; then
    check "$id" resume fail "no window on relaunch after closing during stage $interrupted"
    return 1
  fi
  ui_click "$UI_CHECK_AGAIN" "$(T 60)" || ui_click "$UI_RETRY_STAGE" 10 || true
  if ! wait_until "$(T 3600)" 10 ready_or_retry "$id" journal_finished; then
    check "$id" resume fail "the journal never finished after closing during '$interrupted'" "$(gui_shot resume-stuck)"
    return 1
  fi
  journal=$(find_journal)
  cp "$journal" "$EVID/logs/journal-final.json"
  ok=0
  [ "$(jq -r '.completed_stages | join(" ")' "$journal")" = "$INSTALL_STAGES" ] || ok=1
  pass_or_fail "$id" resume "$ok" \
    "closed during '$interrupted', resumed on relaunch: completed stages '$(jq -r '.completed_stages | join(" ")' "$journal")'" \
    "$EVID/logs/journal-final.json"
  local install_dir=$HERMES_HOME/hermes-agent marker
  marker=$install_dir/.hermes-bootstrap-complete
  ok=0
  jq -e --arg pin "$PIN_COMMIT" '.schemaVersion == 1 and .pinnedCommit == $pin' "$marker" >/dev/null 2>&1 || ok=1
  [ "$(cat "$install_dir/.git/HEAD" 2>/dev/null)" = "$PIN_COMMIT" ] || ok=1
  cp "$marker" "$EVID/logs/hermes-bootstrap-complete.json" 2>/dev/null
  pass_or_fail "$id" pinned-checkout "$ok" "checkout HEAD and bootstrap marker at $PIN_COMMIT" \
    "$EVID/logs/hermes-bootstrap-complete.json"
  local version=$EVID/logs/hermes-version.txt
  hermes_cli --version >"$version" 2>&1
  pass_or_fail "$id" launcher-version "$(grep -q '0\.21\.[5-9]' "$version" && echo 0 || echo 1)" \
    "managed launcher $HERMES_HOME/runtime/.local/bin/hermes answers $(head -n 1 "$version")" "$version"
  ok=0
  local leaked=()
  for leak in hermes node npm uv; do
    [ -e "$TESTER_HOME/.local/bin/$leak" ] && leaked+=("$leak")
  done
  [ ${#leaked[@]} -eq 0 ] || ok=1
  sha_of "$TESTER_HOME/.bashrc" >"$EVID/logs/rc-after.txt"
  sha_of "$TESTER_HOME/.profile" >>"$EVID/logs/rc-after.txt"
  cmp -s "$EVID/logs/rc-before.txt" "$EVID/logs/rc-after.txt" || ok=1
  pass_or_fail "$id" real-home-untouched "$ok" \
    "no shim in ~/.local/bin${leaked[*]:+ (found ${leaked[*]})}, ~/.bashrc and ~/.profile unchanged"
  if wait_until "$(T 600)" 5 backend_up; then
    ok=0
    jq -e --arg home "$TESTER_HOME" --arg runtime "$HERMES_HOME/runtime/.local/bin" '
      .backend.home == $home and (.backend.path | startswith($runtime))
      and .backend.ld_library_path == null and (.backend.appimage_vars | length) == 0
      and (.api_status.version | tostring | test("^0\\.21\\."))' "$EVID/probe/backend.json" >/dev/null || ok=1
    pass_or_fail "$id" backend-serve "$ok" \
      "supervised 'hermes serve' answers /api/status on loopback with the real HOME and host env" \
      "$EVID/probe/backend.json"
  else
    check "$id" backend-serve fail "no app-supervised backend answering /api/status" "$EVID/probe/backend.json"
  fi
}

rest() { # <method> <path> <out-file>
  python3 "$SMOKE_DIR/guest/probe.py" rest "$1" "$2" >"$3" 2>&1
}

cron_ids() { jq -r '.body.jobs[] | select(.registered) | .job_id' "$1" 2>/dev/null | sort; }

c5_plugin() {
  local id=c5-plugin ok=0
  local assets=$APP_DIR/data/flutter_assets/assets/hermes-plugin/hermuse
  diff -r -x __pycache__ "$assets" "$HERMES_HOME/plugins/hermuse" >"$EVID/logs/plugin-diff.txt" 2>&1 || ok=1
  pass_or_fail "$id" plugin-copied "$ok" "HERMES_HOME/plugins/hermuse equals the bundled plugin assets" \
    "$EVID/logs/plugin-diff.txt"
  rest GET /api/plugins/hermuse/feed "$EVID/probe/feed.json"
  pass_or_fail "$id" feed-endpoint $? "GET /api/plugins/hermuse/feed on the supervised backend" "$EVID/probe/feed.json"
  rest GET /api/plugins/hermuse/goals "$EVID/probe/goals.json"
  pass_or_fail "$id" goals-endpoint $? "GET /api/plugins/hermuse/goals" "$EVID/probe/goals.json"
  rest GET /api/plugins/hermuse/cron "$EVID/probe/cron-1.json"
  local count
  count=$(jq '[.body.jobs[] | select(.registered and .enabled)] | length' "$EVID/probe/cron-1.json" 2>/dev/null || echo 0)
  pass_or_fail "$id" jobs-registered "$([ "$count" = 4 ] && echo 0 || echo 1)" \
    "$count/4 Hermuse jobs registered and enabled" "$EVID/probe/cron-1.json"
  local jobs=$HERMES_HOME/cron/jobs.json ran
  ran=$(cron_ids "$EVID/probe/cron-1.json" | while read -r job; do
    jq -r --arg j "$job" '.jobs[] | select(.id == $j and .last_run_at != null) | .id' "$jobs" 2>/dev/null
  done)
  cp "$jobs" "$EVID/logs/cron-jobs.json" 2>/dev/null
  pass_or_fail "$id" jobs-not-run "$([ -z "$ran" ] && echo 0 || echo 1)" \
    "registered jobs have no run recorded (registration is not execution)" "$EVID/logs/cron-jobs.json"
  # Idempotent enablement: a restart re-runs the setup, never duplicates.
  app_close
  local total_before
  total_before=$(jq '.jobs | length' "$jobs" 2>/dev/null || echo 0)
  if app_launch plugin-restart && wait_until "$(T 600)" 5 backend_up; then
    rest GET /api/plugins/hermuse/cron "$EVID/probe/cron-2.json"
    ok=0
    [ "$(cron_ids "$EVID/probe/cron-1.json")" = "$(cron_ids "$EVID/probe/cron-2.json")" ] || ok=1
    [ "$(jq '.jobs | length' "$jobs" 2>/dev/null || echo 0)" = "$total_before" ] || ok=1
    pass_or_fail "$id" enable-idempotent "$ok" "same 4 job ids and no new job after a restart" "$EVID/probe/cron-2.json"
  else
    check "$id" enable-idempotent fail "no backend after restart"
  fi
  local feed goals
  # After the preparation the app opens the local instance's onboarding.
  ui_click "$UI_BACK_TO_CHAT" 30 || true
  ui_rail 2 && feed=$(gui_wait_text "$UI_FEED" 30)
  ui_rail 4 && goals=$(gui_wait_text "$UI_GOALS" 30)
  check "$id" feed-goals-ui manual-gate \
    "confirm Feed and Goals load, and the 4 registered jobs are not shown as executed" \
    "${feed:-$(gui_shot feed-missing)}" "${goals:-$(gui_shot goals-missing)}"
}

computer_ready() {
  rest GET /api/plugins/hermuse/computer/status "$EVID/probe/computer-status.json" &&
    jq -e '.body.state == "running" or .body.state == "stopped"' "$EVID/probe/computer-status.json" >/dev/null
}

# The local setup ran to its end: plugin installed and scheduled, and the
# computer running (the app checks the bridge before the computer).
setup_done() {
  [ -f "$HERMES_HOME/plugins/hermuse/plugin.yaml" ] &&
    rest GET /api/plugins/hermuse/cron "$EVID/probe/cron-setup.json" &&
    jq -e '[.body.jobs[] | select(.registered)] | length == 4' "$EVID/probe/cron-setup.json" >/dev/null &&
    rest GET /api/plugins/hermuse/computer/status "$EVID/probe/computer-status.json" &&
    jq -e '.body.state == "running"' "$EVID/probe/computer-status.json" >/dev/null
}

in_docker_group() { id -nG "$TESTER" | grep -qw docker; }

docker_as() { # <root|tester> <docker args...>
  local who=$1
  shift
  if [ "$who" = root ]; then docker "$@"; else tester_run docker "$@"; fi
}

# The computer as seen from inside its container (evidence only): its log
# (screend reports input errors there), which X window has the keyboard
# focus, the window list, the X extensions and the whole desktop, not only
# the Chromium crop the viewer streams.
computer_diagnostics() { # <root|tester> <container> <label>
  local owner=$1 name=$2 label=$3
  mkdir -p "$EVID/probe/computer"
  docker_as "$owner" logs --tail 300 "$name" >"$EVID/logs/computer-log-$label.txt" 2>&1
  # shellcheck disable=SC2016 # expanded in the container
  docker_as "$owner" exec -e DISPLAY=:1 "$name" sh -c '
    echo "## focus"; focus=$(xdotool getwindowfocus 2>&1); echo "$focus"; xprop -id "$focus" WM_CLASS WM_NAME 2>&1
    echo "## chromium windows"; xdotool search --onlyvisible --class chromium 2>&1
    echo "## windows"; xwininfo -root -children 2>&1 | head -n 60
    echo "## extensions"; xdpyinfo 2>&1 | sed -n "/number of extensions/,/default screen number/p"' \
    >"$EVID/logs/computer-x11-$label.txt" 2>&1
  docker_as "$owner" exec "$name" python3 -c \
    'import sys; from PIL import ImageGrab; ImageGrab.grab(xdisplay=":1").save(sys.stdout.buffer, "PNG")' \
    >"$EVID/probe/computer/desktop-$label.png" 2>/dev/null || rm -f "$EVID/probe/computer/desktop-$label.png"
}

# The plugin names the container after the HERMES_HOME basename.
computer_container() {
  printf 'hermuse-computer-%s\n' "$(basename "$HERMES_HOME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
}

computer_on_engine() { # <root|tester>: running, and its container runs on that engine
  local name listed
  name=$(computer_container)
  rest GET /api/plugins/hermuse/computer/status "$EVID/probe/computer-status.json" &&
    jq -e '.body.state == "running"' "$EVID/probe/computer-status.json" >/dev/null &&
    listed=$(docker_as "$1" ps --filter "name=^$name\$" --format '{{.Names}}' 2>/dev/null) &&
    [ "$listed" = "$name" ]
}

c7_computer() { # [engine-owner root|tester]
  local id=c7-computer owner=${1:-root} ok
  if ! wait_until "$(T 3600)" 15 ready_or_retry "$id" computer_ready; then
    check "$id" computer-prepared fail "computer never became startable" "$EVID/probe/computer-status.json"
    return 1
  fi
  check "$id" computer-prepared pass "computer status $(jq -r .body.state "$EVID/probe/computer-status.json")" \
    "$EVID/probe/computer-status.json"
  local inspect=$EVID/logs/computer-image.json
  docker_as "$owner" image inspect "$COMPUTER_IMAGE" "hermuse-computer:$PLUGIN_VERSION" >"$inspect" 2>&1
  ok=0
  jq -e --arg repo "${COMPUTER_IMAGE%%:*}@sha256:" \
    'length == 2 and ([.[0].RepoDigests[] | startswith($repo)] | any) and .[0].Id == .[1].Id' "$inspect" >/dev/null || ok=1
  pass_or_fail "$id" image-pulled "$ok" \
    "$COMPUTER_IMAGE pulled anonymously from GHCR (registry digest), tagged locally; no local build" "$inspect"
  # The plugin reports where the image came from; a local build is never a pull.
  ok=0
  jq -e '.body.image_source == "registry" and ((.body.image_digest // "") | length) > 0' \
    "$EVID/probe/computer-status.json" >/dev/null || ok=1
  pass_or_fail "$id" image-source "$ok" \
    "computer status reports image_source=registry, digest $(jq -r '.body.image_digest // "none"' "$EVID/probe/computer-status.json")" \
    "$EVID/probe/computer-status.json"
  local doctor=$EVID/logs/hermuse-doctor.txt
  hermes_cli hermuse doctor >"$doctor" 2>&1
  pass_or_fail "$id" doctor $? "hermes hermuse doctor" "$doctor"
  local name probe=$EVID/probe/computer.json rc
  name=$(computer_container)
  computer_diagnostics "$owner" "$name" before
  python3 "$SMOKE_DIR/guest/probe.py" computer --out "$EVID/probe/computer" --timeout "$(T 180)" >"$probe" 2>&1
  rc=$?
  [ "$rc" = 0 ] || computer_diagnostics "$owner" "$name" after
  pass_or_fail "$id" viewer-protocol "$rc" \
    "real frames, take control, type/click/scroll on a fixture page, hand back (input ignored after release)" \
    "$probe" "$EVID/probe/computer/frame-first.jpg" "$EVID/probe/computer/frame-after-input.jpg"
  docker_as "$owner" ps --filter "name=^$name\$" --format '{{.Names}} {{.Image}} {{.Status}}' >"$EVID/logs/computer-container.txt" 2>&1
  pass_or_fail "$id" container "$(grep -q "^$name " "$EVID/logs/computer-container.txt" && echo 0 || echo 1)" \
    "container $name running on the $owner engine" "$EVID/logs/computer-container.txt"
  check "$id" viewer-ui manual-gate "confirm the app's computer viewer shows live frames and Take control / hand back" \
    "$(gui_shot computer-viewer)" "$EVID/frames"
}

c6_bridge() {
  local id=c6-bridge
  local config=$HERMES_HOME/cliproxy/config.yaml
  if ui_bridge_connect; then
    if wait_until "$(T 120)" 3 test -s "$config" &&
      wait_until "$(T 120)" 3 python3 "$SMOKE_DIR/guest/probe.py" cliproxy --config "$config" \
        --expect-exe "$APP_DIR/lib/cliproxy" >"$EVID/probe/cliproxy.json" 2>&1; then
      check "$id" sidecar pass "CLIProxy started from $APP_DIR/lib/cliproxy; management API: 401 without key, 200 with it" \
        "$EVID/probe/cliproxy.json"
    else
      check "$id" sidecar fail "the bridge did not start from the bundle slot" "$EVID/probe/cliproxy.json" "$(gui_shot bridge)"
    fi
    if ui_click "$UI_OPEN_LINK" "$(T 120)"; then
      sleep 5
    fi
    ui_click "$UI_CANCEL" 30 || true
    # The login is only started: no subscription credential may exist.
    local auth_dir
    auth_dir=$(sed -n 's/^auth-dir: *"\(.*\)"$/\1/p' "$config")
    find "$auth_dir" -type f >"$EVID/logs/cliproxy-auth-files.txt" 2>/dev/null
    pass_or_fail "$id" no-subscription-credential "$([ -s "$EVID/logs/cliproxy-auth-files.txt" ] && echo 1 || echo 0)" \
      "no subscription credential stored in ${auth_dir:-the bridge auth dir} (login started, never completed)" \
      "$EVID/logs/cliproxy-auth-files.txt"
  else
    check "$id" sidecar manual-gate "Connections > search '$UI_BRIDGE_CARD' > '$UI_CONNECT' not reachable by OCR: start a bridge by hand" \
      "$(gui_shot bridge-ui-missing)"
  fi
}

c6_bad_hash() {
  local id=c6-bridge target restore dir
  app_close
  if [ "$FORMAT" = deb ]; then
    dir=$DEB_ROOT
    target=$dir/lib/cliproxy
    restore=/root/cliproxy.orig
    cp -p "$target" "$restore"
    printf 'tampered' >>"$target"
    app_launch bad-hash || return 1
  else
    # A writable extraction: the tampered binary sits in the tester's copy.
    dir=$TESTER_HOME/bad-hash/squashfs-root/usr/bin
    in_session extract-bad-hash 600 "rm -rf ~/bad-hash && mkdir ~/bad-hash && cd ~/bad-hash && '$APPIMAGE_PATH' --appimage-extract >/dev/null" ||
      return 1
    target=$dir/lib/cliproxy
    printf 'tampered' >>"$target"
    app_launch bad-hash "'$TESTER_HOME/bad-hash/squashfs-root/AppRun'" || return 1
  fi
  local shot=''
  if ui_bridge_connect; then
    sleep 20
    shot=$(gui_shot bad-hash-refused)
  fi
  local running=0 pid
  for pid in $(pgrep -u "$TESTER" -f cliproxy); do
    [ "$(readlink -f "/proc/$pid/exe")" = "$(readlink -f "$target")" ] && running=1
  done
  pass_or_fail "$id" tampered-binary-not-run "$running" "no process runs the tampered $target"
  if [ -n "$shot" ] && gui_locate "$shot" "hash mismatch" any >/dev/null; then
    check "$id" tampered-binary-refused pass "the UI reports 'bundled CLIProxyAPI hash mismatch'" "$shot"
  else
    check "$id" tampered-binary-refused manual-gate "confirm the bridge refuses the tampered binary with an explicit error" \
      "${shot:-$(gui_shot bad-hash-ui)}"
  fi
  app_close
  if [ "$FORMAT" = deb ]; then
    cp -p "$restore" "$target"
  fi
}

browser_env_clean() { # <record> <session-env>: the host browser got the host environment
  local record=$1 session=$2 var ok=0
  for var in APPDIR APPIMAGE APPOFFSET ARGV0 OWD URUNTIME URUNTIME_DIR HERMUSE_APPIMAGE_ENV_SAVED; do
    grep -q "^$var=" "$record" && ok=1
  done
  grep -q '^HERMUSE_ORIG_' "$record" && ok=1
  for var in LD_LIBRARY_PATH PATH XDG_DATA_DIRS GTK_PATH GTK_THEME GDK_BACKEND GIO_MODULE_DIR \
    GSETTINGS_SCHEMA_DIR GI_TYPELIB_PATH GDK_PIXBUF_MODULE_FILE GTK_IM_MODULE_FILE; do
    [ "$(grep "^$var=" "$record")" = "$(grep "^$var=" "$session")" ] || ok=1
  done
  return "$ok"
}

c8_extras() {
  local id=c8-scheduling-conversation
  # One-shot no-agent job run by the ticker of the app-supervised backend
  # (never `cron run`/`tick` from here): heartbeat, final state, output.
  local nonce=hermuse-cron-$RUN_ID-$RANDOM out=$EVID/logs/cron-oneshot.txt
  tester_mkdir "$HERMES_HOME/scripts"
  printf '#!/bin/sh\necho %s\n' "$nonce" >"$HERMES_HOME/scripts/hermuse-smoke-cron.sh"
  chown "$TESTER:$TESTER" "$HERMES_HOME/scripts/hermuse-smoke-cron.sh"
  hermes_cli cron create 'in 1m' --name hermuse-smoke-oneshot --script hermuse-smoke-cron.sh \
    --no-agent --deliver local >"$out" 2>&1
  local job
  job=$(sed -e 's/\x1b\[[0-9;]*m//g' -n -e 's/.*Created job: *\([^ ]*\).*/\1/p' "$out" | head -n 1)
  if [ -n "$job" ] && wait_until "$(T 420)" 10 grep -rqs "$nonce" "$HERMES_HOME/cron/output/$job"; then
    local heartbeat age
    heartbeat=$(cat "$HERMES_HOME/cron/ticker_heartbeat" 2>/dev/null || echo 0)
    age=$(($(date +%s) - ${heartbeat%.*}))
    jq --arg j "$job" '.jobs[] | select(.id == $j)' "$HERMES_HOME/cron/jobs.json" >"$EVID/logs/cron-oneshot-job.json" 2>/dev/null
    cp -r "$HERMES_HOME/cron/output/$job" "$EVID/logs/cron-oneshot-output" 2>/dev/null
    local ok=0
    [ "$age" -lt 180 ] || ok=1
    jq -e '.last_status == "ok" and .last_run_at != null' "$EVID/logs/cron-oneshot-job.json" >/dev/null || ok=1
    pass_or_fail "$id" cron-oneshot-ticker "$ok" \
      "job $job fired by the backend ticker (heartbeat ${age}s old), state $(jq -r '.state // "?"' "$EVID/logs/cron-oneshot-job.json"), output carries the nonce" \
      "$out" "$EVID/logs/cron-oneshot-job.json" "$EVID/logs/cron-oneshot-output"
  else
    check "$id" cron-oneshot-ticker fail "the one-shot job produced no output (job '${job:-none}')" "$out"
  fi
  # Host browser: records left by guest/fake-browser.sh during the bridge login.
  local record
  record=$(newest "$STATE/out/browser" '*.env')
  if [ -n "$record" ]; then
    cp "$record" "$EVID/logs/browser-launch.env"
    if browser_env_clean "$record" "$STATE/out/session.env"; then
      check "$id" host-browser pass "the login URL opened in the host default browser with the host environment" \
        "$EVID/logs/browser-launch.env"
    else
      check "$id" host-browser fail "the browser inherited bundle/AppImage environment" "$EVID/logs/browser-launch.env"
    fi
  else
    check "$id" host-browser manual-gate "no browser launch recorded: open a connection login link by hand" \
      "$(gui_shot no-browser-launch)"
  fi
  # Real conversation: only with the capped test account of the release
  # environment.
  if [ -z "$MODEL_ENV" ] || [ ! -s "$MODEL_ENV" ]; then
    check "$id" conversation skipped-missing-prereq "no HERMUSE_TEST_MODEL_* test account on this run"
    check "$id" cron-oneshot-agent skipped-missing-prereq "needs the model test account"
    return 0
  fi
  model_conversation "$id"
}

model_conversation() { # <id>
  local id=$1 body=$STATE/model-set.json
  # shellcheck disable=SC1090
  . "$MODEL_ENV"
  MODEL_KEY_FILE=$STATE/model-key
  (umask 077 && printf '%s' "${HERMUSE_TEST_MODEL_API_KEY:-}" >"$MODEL_KEY_FILE")
  (umask 077 && jq -n --arg provider "${HERMUSE_TEST_MODEL_PROVIDER:-}" --arg model "${HERMUSE_TEST_MODEL_NAME:-}" \
    --arg base "${HERMUSE_TEST_MODEL_BASE_URL:-}" --rawfile key "$MODEL_KEY_FILE" \
    '{scope: "main", provider: $provider, model: $model, confirm_expensive_model: true}
     + (if $base == "" then {} else {base_url: $base} end) + (if $key == "" then {} else {api_key: $key} end)' >"$body")
  python3 "$SMOKE_DIR/guest/probe.py" rest POST /api/model/set --body-file "$body" >"$EVID/probe/model-set.json" 2>&1
  local set_ok=$?
  rm -f "$body"
  if [ "$set_ok" != 0 ]; then
    check "$id" conversation fail "POST /api/model/set refused the test account" "$EVID/probe/model-set.json"
    return 1
  fi
  local nonce=HERMUSE-$RUN_ID-$RANDOM
  python3 "$SMOKE_DIR/guest/probe.py" converse --nonce "$nonce" --timeout "$(T 300)" >"$EVID/probe/conversation.json" 2>&1
  pass_or_fail "$id" conversation $? "real turn over /api/ws answered with the expected token" "$EVID/probe/conversation.json"
  local out=$EVID/logs/cron-agent.txt job
  hermes_cli cron create 'in 1m' "Reply with exactly: CRON-$nonce" --name hermuse-smoke-agent --deliver local >"$out" 2>&1
  job=$(sed -e 's/\x1b\[[0-9;]*m//g' -n -e 's/.*Created job: *\([^ ]*\).*/\1/p' "$out" | head -n 1)
  if [ -n "$job" ] && wait_until "$(T 600)" 10 grep -rqs "CRON-$nonce" "$HERMES_HOME/cron/output/$job"; then
    cp -r "$HERMES_HOME/cron/output/$job" "$EVID/logs/cron-agent-output" 2>/dev/null
    check "$id" cron-oneshot-agent pass "agent one-shot job $job answered through the ticker" "$EVID/logs/cron-agent-output"
  else
    check "$id" cron-oneshot-agent fail "the agent one-shot job produced no expected output" "$out"
  fi
  local shot
  shot=$(gui_shot conversation)
  check "$id" conversation-ui manual-gate "optional: the conversation as the app shows it" "$shot"
}

no_extraction_dirs() { [ -z "$(find /tmp -maxdepth 1 -type d -name 'appimage_extracted_*' 2>/dev/null)" ]; }

appimage_modes() {
  local id=c1-launch
  app_close
  local left=''
  wait_until 30 2 no_extraction_dirs || left=$(find /tmp -maxdepth 1 -type d -name 'appimage_extracted_*')
  pass_or_fail "$id" appimage-cleanup "$([ -z "$left" ] && echo 0 || echo 1)" \
    "no extraction directory left after exit${left:+: $left}"
  if app_launch extract-and-run "$(app_command --appimage-extract-and-run)"; then
    window_checks "$id" extract-and-run
    app_close
  else
    check "$id" window-extract-and-run fail "--appimage-extract-and-run opened no window"
  fi
  if in_session manual-extract 900 "rm -rf ~/manual-extract && mkdir ~/manual-extract && cd ~/manual-extract && '$APPIMAGE_PATH' --appimage-extract >/dev/null" &&
    app_launch manual-extract "'$TESTER_HOME/manual-extract/squashfs-root/AppRun'"; then
    window_checks "$id" manual-extract
    app_close
  else
    check "$id" window-manual-extract fail "squashfs-root/AppRun opened no window"
  fi
}

# --- Docker fixtures (criterion 9) ------------------------------------------------

docker_repo() {
  # shellcheck disable=SC1091
  . /etc/os-release
  apt-get install -y ca-certificates curl gnupg >>"$EVID/logs/fixture.log" 2>&1
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /root/docker.asc || return 1
  local fpr
  fpr=$(gpg --show-keys --with-colons /root/docker.asc 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')
  [ "$fpr" = "$DOCKER_CE_KEY_FPR" ] || {
    log "unexpected Docker CE key $fpr"
    return 1
  }
  install -d -m 0755 /etc/apt/keyrings
  gpg --dearmor </root/docker.asc >/etc/apt/keyrings/docker.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update >>"$EVID/logs/fixture.log" 2>&1
}

docker_resources() { # <root|tester>: foreign resources the app must never touch
  local who=$1
  docker_as "$who" volume create --label hermuse.smoke.fixture=1 hermuse-smoke-fixture-vol >/dev/null &&
    docker_as "$who" network create --label hermuse.smoke.fixture=1 hermuse-smoke-fixture-net >/dev/null &&
    tar -cf /tmp/empty.tar --files-from /dev/null &&
    chmod 0644 /tmp/empty.tar &&
    if [ "$who" = root ]; then docker import /tmp/empty.tar hermuse-smoke-fixture:1 >/dev/null; else
      tester_run sh -c 'docker import /tmp/empty.tar hermuse-smoke-fixture:1' >/dev/null
    fi &&
    docker_as "$who" create --label hermuse.smoke.fixture=1 --name hermuse-smoke-fixture-ctr \
      hermuse-smoke-fixture:1 /nonexistent >/dev/null
}

section() { # <fingerprint-file> <name>: the lines under "## <name>"
  awk -v want="## $2" '$0 == want { on = 1; next } /^## / { on = 0 } on' "$1"
}

docker_fingerprint() { # <file> <root|tester>
  local who=$2
  {
    echo "## packages"
    dpkg-query -W -f '${Package} ${Version} ${Status}\n' 2>/dev/null |
      grep -E '^(docker|containerd|moby|podman|runc)' | grep 'install ok installed'
    echo "## daemon.json"
    sha_of /etc/docker/daemon.json || true
    echo "## tester docker context"
    tester_run docker context show 2>&1
    tester_run docker context ls --format '{{.Name}} {{.DockerEndpoint}}' 2>&1
    echo "## fixture resources"
    docker_as "$who" volume ls -q --filter label=hermuse.smoke.fixture=1 2>&1
    docker_as "$who" network ls -q --filter label=hermuse.smoke.fixture=1 2>&1
    docker_as "$who" image ls -q hermuse-smoke-fixture 2>&1
    docker_as "$who" ps -aq --filter label=hermuse.smoke.fixture=1 2>&1
  } >"$1"
}

# The user's own rootless engine, set up the documented way inside the
# session. The user journal of a failed start is kept as evidence.
fixture_rootless() {
  if ! grep -q "^$TESTER:" /etc/subuid || ! grep -q "^$TESTER:" /etc/subgid; then
    usermod --add-subuids 231072-296607 --add-subgids 231072-296607 "$TESTER" >>"$EVID/logs/fixture.log" 2>&1
  fi
  if in_session rootless-setup 900 'dockerd-rootless-setuptool.sh install && docker context use rootless'; then
    return 0
  fi
  in_session rootless-journal 60 'journalctl --user -u docker.service -n 80 --no-pager; systemctl --user status docker.service --no-pager'
  return 1
}

fixture_docker() { # <variant> -> engine owner on stdout
  local variant=$1
  case $variant in
    docker-ce)
      docker_repo &&
        apt-get install -y docker-ce docker-ce-cli containerd.io >>"$EVID/logs/fixture.log" 2>&1 &&
        mkdir -p /etc/docker && printf '{\n  "log-level": "warn"\n}\n' >/etc/docker/daemon.json &&
        systemctl restart docker && docker_resources root && echo root
      ;;
    docker-stopped)
      # The resources are listed while the daemon still runs: the "before"
      # state of the stopped engine.
      apt-get install -y docker.io >>"$EVID/logs/fixture.log" 2>&1 &&
        mkdir -p /etc/docker && printf '{\n  "log-level": "warn"\n}\n' >/etc/docker/daemon.json &&
        systemctl restart docker && docker_resources root &&
        docker_fingerprint "$EVID/logs/docker-before.txt" root &&
        systemctl disable --now docker.service docker.socket >>"$EVID/logs/fixture.log" 2>&1 && echo root
      ;;
    docker-rootless)
      docker_repo &&
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras uidmap \
          slirp4netns >>"$EVID/logs/fixture.log" 2>&1 &&
        systemctl disable --now docker.service docker.socket >>"$EVID/logs/fixture.log" 2>&1 &&
        fixture_rootless && docker_resources tester && echo tester
      ;;
    docker-remote-context)
      docker_repo &&
        apt-get install -y docker-ce-cli >>"$EVID/logs/fixture.log" 2>&1 &&
        tester_run docker context create hermuse-smoke-remote --docker host=tcp://192.0.2.10:2376 >/dev/null &&
        tester_run docker context use hermuse-smoke-remote >/dev/null && echo none
      ;;
  esac
}

# --- scenarios -------------------------------------------------------------------

start_desktop() {
  session_start || {
    check c0-test-base session fail "the tty1 test desktop session did not come up"
    return 1
  }
  check c0-test-base session pass "tty1 logind session, Xvfb :99, openbox, polkit-gnome agent, user bus" \
    "$EVID/session/session-info.txt"
  keyring_watcher_start
  gui_recorder_start 4
}

prepare_and_accept() { # generic consent path of the non-fresh scenarios
  ui_prepare || return 1
  gui_polkit accept "$SECRETS/tester-password" "$(T 90)" || true
  return 0
}

scenario_fresh() {
  expect c0-test-base base
  expect c1-launch 1
  expect c2-prepare 2
  expect c3-keyring 3
  expect c4-hermes 4
  expect c5-plugin 5
  expect c6-bridge 6
  expect c7-computer 7
  expect c8-scheduling-conversation 8
  c0_test_base
  install_artifact c1-launch || return 1
  start_desktop || return 1
  c1_launch || return 1
  c2_prepare || return 1
  c4_hermes_interrupt || return 1
  c2_dependencies
  c3_keyring
  c4_hermes_resume || return 1
  # The app goes on by itself: plugin, bridge check, computer, then onboarding.
  if wait_until "$(T 5400)" 15 ready_or_retry c5-plugin setup_done; then
    check c5-plugin setup-completed pass "the local setup went through plugin, bridge check and computer by itself"
  else
    check c5-plugin setup-completed fail "the local setup did not complete" "$(gui_shot setup-not-done)"
  fi
  c5_plugin
  c7_computer root
  c6_bridge
  c8_extras
  c3_keyring_locked
  c6_bad_hash
  if [ "$FORMAT" = appimage ]; then
    app_launch final && appimage_modes
  fi
  app_close
}

scenario_adopt() { # <compatible|foreign>
  local kind=$1 id=c4-hermes-adopt-$1
  expect c0-test-base base
  expect "$id" 4
  c0_test_base
  install_artifact "$id" || return 1
  # Fixture: the Hermes system tools a user who installed Hermes has.
  apt-get install -y git curl tar ca-certificates build-essential python3-dev libffi-dev libatomic1 \
    ripgrep ffmpeg >"$EVID/logs/fixture.log" 2>&1
  start_desktop || return 1
  local install_dir=$HERMES_HOME/hermes-agent fingerprint_before=$EVID/logs/foreign-before.txt
  if [ "$kind" = compatible ]; then
    # A user-run upstream install at the pin, outside the app. Git never
    # prompts and gives up on a stalled transfer (the script retries clones).
    local script=/tmp/hermes-install.sh fixture_rc=1
    # raw.githubusercontent.com answers HTTP 429 while many legs fetch at once.
    if curl -fsSL --retry 10 --retry-max-time 900 --retry-all-errors \
      "https://raw.githubusercontent.com/NousResearch/hermes-agent/$PIN_COMMIT/scripts/install.sh" -o "$script" \
      2>"$EVID/logs/upstream-script-download.log" &&
      chmod 0755 "$script"; then
      in_session upstream-install "$(T 3600)" \
        "HERMES_HOME='$HERMES_HOME' GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=120 '$script' --commit '$PIN_COMMIT' --dir '$install_dir' --hermes-home '$HERMES_HOME' --skip-setup --skip-browser --skip-computer-use --non-interactive >'$STATE/out/upstream-install.log' 2>&1"
      fixture_rc=$?
    fi
    cp "$STATE/out/upstream-install.log" "$EVID/logs/" 2>/dev/null
    if [ "$fixture_rc" != 0 ] || [ ! -x "$TESTER_HOME/.local/bin/hermes" ]; then
      check "$id" fixture-install fail "the upstream install script at the pin failed (exit $fixture_rc, 124 = timed out)" \
        "$EVID/logs/upstream-install.log" "$(newest "$EVID/logs" 'timeout-*-upstream-install-ps.txt')"
      return 1
    fi
    check "$id" fixture-install pass "compatible Hermes installed by the upstream script at the pin (fixture, not the app)" \
      "$EVID/logs/upstream-install.log"
    # The user logs in again after installing, as they would on a desktop.
    session_restart || check "$id" relogin fail "the tester session did not come back"
  else
    # An incompatible foreign install: version 0.20.0, arbitrary content.
    tester_mkdir "$install_dir" "$TESTER_HOME/.local/bin"
    printf '#!/bin/sh\necho "Hermes Agent v0.20.0"\n' >"$TESTER_HOME/.local/bin/hermes"
    printf 'foreign install, keep me\n' >"$install_dir/README.foreign"
    chmod 0755 "$TESTER_HOME/.local/bin/hermes"
    chown -R "$TESTER:$TESTER" "$TESTER_HOME/.local/bin" "$install_dir"
    check "$id" fixture-install pass "incompatible foreign install (0.20.0) placed in $install_dir and ~/.local/bin"
    session_restart || check "$id" relogin fail "the tester session did not come back"
  fi
  (cd "$HERMES_HOME" && find . -path ./runtime -prune -o -name __pycache__ -prune -o -type f -print0 |
    sort -z | xargs -0 sha256sum) >"$fingerprint_before" 2>/dev/null
  cat "$install_dir/.git/HEAD" >>"$fingerprint_before" 2>/dev/null
  app_launch first || return 1
  prepare_and_accept || check "$id" gate fail "no preparation gate" "$(gui_shot gate-missing)"
  if [ "$kind" = compatible ]; then
    if wait_until "$(T 1800)" 10 ready_or_retry "$id" backend_up; then
      local ok=0
      jq -e --arg dir "$install_dir" '.backend.cmdline | join(" ") | contains($dir)' "$EVID/probe/backend.json" >/dev/null ||
        ok=1
      pass_or_fail "$id" adopted "$ok" "the backend runs from the existing checkout" "$EVID/probe/backend.json"
    else
      check "$id" adopted fail "the compatible install was not adopted (no backend)" "$(gui_shot not-adopted)"
    fi
    if find_journal >/dev/null; then
      check "$id" no-reinstall fail "the installer ran on an adopted checkout" "$(find_journal)"
    else
      check "$id" no-reinstall pass "no install journal: the installer never ran"
    fi
  else
    sleep "$(T 300)"
    if [ -e "$HERMES_HOME/runtime" ] || find_journal >/dev/null; then
      check "$id" not-replaced fail "the app started its own install into the foreign HERMES_HOME"
    else
      check "$id" not-replaced pass "no reinstall/downgrade/replacement of the foreign install"
    fi
    check "$id" foreign-reported manual-gate "confirm the incompatible version is reported (kept, not repaired)" \
      "$(gui_shot foreign-reported)"
  fi
  app_close
  local fingerprint_after=$EVID/logs/foreign-after.txt
  (cd "$HERMES_HOME" && find . -path ./runtime -prune -o -name __pycache__ -prune -o -path ./logs -prune -o \
    -path ./sessions -prune -o -path ./plugins -prune -o -path ./computer -prune -o -path ./cron -prune -o \
    -path ./hermuse -prune -o -path ./cliproxy -prune -o -type f -print0 | sort -z | xargs -0 sha256sum) \
    >"$fingerprint_after" 2>/dev/null
  cat "$install_dir/.git/HEAD" >>"$fingerprint_after" 2>/dev/null
  # Only files of the checkout itself are compared: the app legitimately adds
  # its plugin, cron and computer state next to it.
  local changed
  changed=$(diff <(grep ' ./hermes-agent/' "$fingerprint_before") <(grep ' ./hermes-agent/' "$fingerprint_after") | head -n 20)
  pass_or_fail "$id" checkout-unchanged "$([ -z "$changed" ] && echo 0 || echo 1)" \
    "the existing checkout is byte-identical after the app ran${changed:+: $changed}" "$fingerprint_before" "$fingerprint_after"
}

scenario_docker() { # <variant>
  local variant=$1 id=c9-$1 owner
  expect c0-test-base base
  expect "$id" 9
  c0_test_base
  install_artifact "$id" || return 1
  start_desktop || return 1
  owner=$(fixture_docker "$variant")
  if [ -z "$owner" ]; then
    check "$id" fixture fail "could not set up the $variant fixture" "$EVID/logs/fixture.log"
    return 1
  fi
  check "$id" fixture pass "$variant fixture ready (engine owner: $owner)" "$EVID/logs/fixture.log"
  local before=$EVID/logs/docker-before.txt after=$EVID/logs/docker-after.txt
  [ -s "$before" ] || docker_fingerprint "$before" "${owner/none/root}"
  local groups_before
  groups_before=$(id -nG "$TESTER")
  app_launch first || return 1
  local shot=''
  if ui_prepare; then
    shot=$(gui_shot docker-plan)
    gui_polkit accept "$SECRETS/tester-password" "$(T 90)" || true
  fi
  if [ "$variant" = docker-remote-context ]; then
    sleep "$(T 600)"
  else
    wait_until "$(T 5400)" 15 ready_or_retry "$id" computer_on_engine "$owner"
  fi
  docker_fingerprint "$after" "${owner/none/root}"
  pass_or_fail "$id" engine-not-replaced \
    "$([ "$(section "$before" packages)" = "$(section "$after" packages)" ] && echo 0 || echo 1)" \
    "Docker packages identical (no docker.io over an existing engine, no reinstall)" "$before" "$after"
  pass_or_fail "$id" daemon-config-unchanged \
    "$([ "$(section "$before" daemon.json)" = "$(section "$after" daemon.json)" ] && echo 0 || echo 1)" \
    "/etc/docker/daemon.json identical"
  pass_or_fail "$id" context-unchanged \
    "$([ "$(section "$before" 'tester docker context')" = "$(section "$after" 'tester docker context')" ] && echo 0 || echo 1)" \
    "the user's current docker context and context list are unchanged"
  pass_or_fail "$id" foreign-resources-intact \
    "$([ "$(section "$before" 'fixture resources')" = "$(section "$after" 'fixture resources')" ] && echo 0 || echo 1)" \
    "fixture volume, network, image and container untouched"
  case $variant in
    docker-ce)
      verdict "$id" computer-on-engine "the computer container runs on the existing Docker CE" \
        "no running computer container on the existing Docker CE" computer_on_engine root
      verdict "$id" docker-group "docker group added after the root-equivalence consent" \
        "the tester cannot reach the rootful engine" in_docker_group
      ;;
    docker-stopped)
      verdict "$id" started "the stopped engine was started (the consented action only)" \
        "the stopped engine is still down" systemctl is-active --quiet docker
      verdict "$id" computer-on-engine "the computer container runs on the started docker.io" \
        "no running computer container on the started engine" computer_on_engine root
      ;;
    docker-rootless)
      verdict "$id" computer-on-engine "the computer container runs on the rootless engine" \
        "no running computer container on the rootless engine" computer_on_engine tester
      verdict "$id" no-docker-group "no docker group added for a usable rootless engine" \
        "group membership changed: $(id -nG "$TESTER")" test "$groups_before" = "$(id -nG "$TESTER")"
      verdict "$id" rootful-untouched "the rootful daemon stayed stopped" \
        "the rootful daemon was started" not systemctl is-active --quiet docker.service
      ;;
    docker-remote-context)
      verdict "$id" no-silent-local-engine "no local engine installed or started silently" \
        "a local daemon was started without an explicit choice" not pgrep -x dockerd
      # The explicit choice must be offered; the smoke never makes it.
      local choice
      if choice=$(gui_wait_text "$UI_USE_LOCAL_DOCKER" 60 line); then
        check "$id" explicit-choice pass "the app offers '$UI_USE_LOCAL_DOCKER' instead of switching engines" "$choice"
      else
        check "$id" explicit-choice manual-gate "confirm the app asks for an explicit local engine for Hermuse" \
          "${shot:-$(gui_shot remote-context)}"
      fi
      ;;
  esac
  app_close
}

lifecycle_fixtures() { # <file>: data the package lifecycle must preserve
  tester_mkdir "$HERMES_HOME/hermuse/feed"
  printf '# fixture\nhermuse smoke %s\n' "$RUN_ID" >"$HERMES_HOME/hermuse/feed/fixture.md"
  chown -R "$TESTER:$TESTER" "$HERMES_HOME"
  printf '%s' "fixture-$RUN_ID" | tester_run secret-tool store --label='Hermuse smoke fixture' hermuse-smoke lifecycle
  lifecycle_state "$1"
}

lifecycle_state() { # <file>
  {
    echo "## HERMES_HOME"
    (cd "$HERMES_HOME" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
    echo "## secret"
    tester_run secret-tool lookup hermuse-smoke lifecycle
    echo
    echo "## app databases"
    local db
    for db in $(find "$APP_SUPPORT" -type f \( -name '*.sqlite' -o -name '*.db' -o -name '*.sqlite3' \) 2>/dev/null | sort); do
      echo "$db $(sqlite3 "$db" 'PRAGMA integrity_check;') $(sqlite3 "$db" "select group_concat(name, ',') from (select name from sqlite_master where type = 'table' order by name);")"
    done
    echo "## docker"
    docker volume ls -q --filter label=hermuse.smoke.fixture=1 2>/dev/null
    docker image ls -q hermuse-smoke-fixture 2>/dev/null
  } >"$1" 2>&1
}

system_files() { # <file>: owned-file removal check
  find / -xdev \( -path /proc -o -path /sys -o -path /run -o -path /tmp -o -path /var/tmp -o -path /var/log \
    -o -path /var/cache -o -path /var/lib/apt -o -path /var/lib/dpkg -o -path /home -o -path /root \
    -o -path /var/lib/docker -o -path /var/lib/containerd \) -prune -o -print 2>/dev/null | sort >"$1"
}

scenario_lifecycle() {
  local id=c10-lifecycle
  expect c0-test-base base
  expect "$id" 10
  c0_test_base
  # Fixture only: a keyring provider and a Docker engine holding user data.
  apt-get install -y gnome-keyring docker.io >"$EVID/logs/fixture.log" 2>&1
  tar -cf /tmp/empty.tar --files-from /dev/null
  docker volume create --label hermuse.smoke.fixture=1 hermuse-smoke-fixture-vol >/dev/null
  docker import /tmp/empty.tar hermuse-smoke-fixture:1 >/dev/null
  if [ "$FORMAT" = deb ]; then
    local fixture_version
    fixture_version=$(dpkg-deb -f "$FIXTURE_DEB" Version)
    install_deb "$id" "$FIXTURE_DEB" "$fixture_version" || return 1
    check "$id" fixture-label pass "installed the packaging fixture $fixture_version (never published)"
    APP_DIR=$DEB_ROOT
    DEB_EXEC=$(sed -n 's/^Exec=//p' "$DESKTOP_FILE" | head -n 1 | sed -E 's/ %[fFuUdDnNickvm]//g')
  else
    install_artifact "$id" || return 1
  fi
  start_desktop || return 1
  app_launch data || return 1
  sleep 20
  app_close
  local before=$EVID/logs/lifecycle-before.txt
  lifecycle_fixtures "$before"
  if [ "$FORMAT" = deb ]; then
    install_deb "$id" "$DEB_FILE" "$(jq -r '.app.debian_version' "$VERSION_JSON")" || return 1
    lifecycle_state "$EVID/logs/lifecycle-after-upgrade.txt"
    pass_or_fail "$id" upgrade-preserves "$(cmp -s "$before" "$EVID/logs/lifecycle-after-upgrade.txt" && echo 0 || echo 1)" \
      "upgrade $(dpkg-deb -f "$FIXTURE_DEB" Version) -> $(jq -r '.app.debian_version' "$VERSION_JSON"): SQLite, HERMES_HOME, secret, Docker fixtures intact" \
      "$before" "$EVID/logs/lifecycle-after-upgrade.txt"
    if app_launch upgraded; then
      check "$id" upgraded-launch pass "the upgraded app opens"
      app_close
    else
      check "$id" upgraded-launch fail "the upgraded app does not open"
    fi
    lifecycle_state "$before"
    dpkg -L "$DEB_PACKAGE" | sort >"$EVID/logs/deb-owned-files.txt"
    system_files "$EVID/logs/fs-before-remove.txt"
    apt-get remove -y "$DEB_PACKAGE" >"$EVID/logs/apt-remove.log" 2>&1
    lifecycle_state "$EVID/logs/lifecycle-after-remove.txt"
    local ok=0
    cmp -s "$before" "$EVID/logs/lifecycle-after-remove.txt" || ok=1
    [ -e "$DEB_ROOT" ] || [ -e /usr/bin/hermuse-agent ] || [ -e "$DESKTOP_FILE" ] && ok=1
    pass_or_fail "$id" remove "$ok" "remove: app files gone, user data intact" "$EVID/logs/apt-remove.log" \
      "$EVID/logs/lifecycle-after-remove.txt"
    apt-get purge -y "$DEB_PACKAGE" >"$EVID/logs/apt-purge.log" 2>&1
    lifecycle_state "$EVID/logs/lifecycle-after-purge.txt"
    ok=0
    cmp -s "$before" "$EVID/logs/lifecycle-after-purge.txt" || ok=1
    dpkg-query -W -f '${Status}' "$DEB_PACKAGE" 2>/dev/null | grep -q 'installed' && ok=1
    pass_or_fail "$id" purge "$ok" "purge: package gone, SQLite/HERMES_HOME/secret/Docker fixtures intact" \
      "$EVID/logs/apt-purge.log" "$EVID/logs/lifecycle-after-purge.txt"
    system_files "$EVID/logs/fs-after-purge.txt"
    comm -23 "$EVID/logs/fs-before-remove.txt" "$EVID/logs/fs-after-purge.txt" >"$EVID/logs/fs-removed.txt"
    local foreign
    foreign=$(comm -23 "$EVID/logs/fs-removed.txt" "$EVID/logs/deb-owned-files.txt" | head -n 20)
    pass_or_fail "$id" only-owned-files-removed "$([ -z "$foreign" ] && echo 0 || echo 1)" \
      "every removed path belongs to the package${foreign:+; also removed: $foreign}" "$EVID/logs/fs-removed.txt"
  else
    # Replacing the AppImage: delete the file, download it again elsewhere.
    # The first release has a single AppImage, so the replacement is the same
    # bytes under a new path; data lives outside the file and the extraction.
    rm -f "$APPIMAGE_PATH"
    tester_mkdir "$TESTER_HOME/Downloads"
    APPIMAGE_PATH=$TESTER_HOME/Downloads/$(basename "$APPIMAGE_FILE")
    install -o "$TESTER" -g "$TESTER" -m 0644 "$APPIMAGE_FILE" "$APPIMAGE_PATH"
    tester_run chmod u+x "$APPIMAGE_PATH"
    if app_launch replaced; then
      sleep 20
      app_close
      lifecycle_state "$EVID/logs/lifecycle-after-replace.txt"
      pass_or_fail "$id" appimage-replacement "$(cmp -s "$before" "$EVID/logs/lifecycle-after-replace.txt" && echo 0 || echo 1)" \
        "AppImage replaced (same bytes, new path): SQLite, HERMES_HOME, secret, Docker fixtures intact" \
        "$before" "$EVID/logs/lifecycle-after-replace.txt"
    else
      check "$id" appimage-replacement fail "the replaced AppImage does not open"
    fi
  fi
}

scenario_compat() {
  local id=compat
  expect "$id" compat
  # shellcheck disable=SC1091
  . /etc/os-release
  check "$id" os pass "$PRETTY_NAME (container $GUEST)"
  apt-get update >"$EVID/logs/apt-update.log" 2>&1
  apt-get install -y --no-install-recommends xvfb xauth x11-utils xdotool imagemagick tesseract-ocr \
    tesseract-ocr-eng dbus dbus-user-session libgl1-mesa-dri libglx-mesa0 libegl-mesa0 jq procps binutils file \
    desktop-file-utils >"$EVID/logs/apt-tools.log" 2>&1
  if [ "$FORMAT" = appimage ]; then
    # What every desktop provides and the AppImage deliberately takes from the
    # host: the GL stack and the linuxdeploy excludelist libraries.
    apt-get install -y --no-install-recommends libgl1 libegl1 libgles2 libx11-6 libxcb1 libfontconfig1 \
      libfreetype6 libharfbuzz0b libfribidi0 libexpat1 zlib1g libbz2-1.0 libgmp10 libgpg-error0 libcom-err2 \
      libwayland-client0 >>"$EVID/logs/apt-tools.log" 2>&1
  fi
  local root elf unresolved=$EVID/logs/ldd-missing.txt
  : >"$unresolved"
  if [ "$FORMAT" = deb ]; then
    apt-get install -y "$DEB_FILE" >"$EVID/logs/apt-install.log" 2>&1
    pass_or_fail "$id" apt-resolution $? "APT resolved and installed $(basename "$DEB_FILE") on a bare $GUEST" \
      "$EVID/logs/apt-install.log"
    root=$DEB_ROOT
    # hermuse_app loads every bundled library through its RUNPATH $ORIGIN/lib;
    # the plugin libraries find libflutter_linux_gtk.so the same way at run
    # time (already loaded by the executable), so ldd gets that directory.
    # shellcheck disable=SC2016 # a literal $ORIGIN
    readelf -d "$root/hermuse_app" 2>/dev/null | grep -E '(RUNPATH|RPATH).*\$ORIGIN/lib' \
      >"$EVID/logs/hermuse_app-runpath.txt" || echo "$root/hermuse_app: no \$ORIGIN/lib RUNPATH" >>"$unresolved"
    ldd "$root/hermuse_app" 2>&1 | grep 'not found' | sed "s|^|$root/hermuse_app: |" >>"$unresolved"
    for elf in "$root"/lib/*.so*; do
      LD_LIBRARY_PATH=$root/lib ldd "$elf" 2>&1 | grep 'not found' | sed "s|^|$elf: |" >>"$unresolved"
    done
  else
    appimage_extract_root /root/compat
    root=/root/compat/squashfs-root
    for elf in "$root/usr/bin/hermuse_app" "$root"/usr/bin/lib/*.so* "$root"/usr/lib/*.so*; do
      [ -f "$elf" ] || continue
      LD_LIBRARY_PATH=$root/usr/lib:$root/usr/bin/lib ldd "$elf" 2>&1 | grep 'not found' | sed "s|^|$elf: |" >>"$unresolved"
    done
  fi
  pass_or_fail "$id" elf-resolution "$([ -s "$unresolved" ] && echo 1 || echo 0)" \
    "every bundled ELF resolves its libraries" "$unresolved"
  id -u "$TESTER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$TESTER"
  TESTER_UID=$(id -u "$TESTER")
  install -d -m 0755 "$STATE"
  install -d -m 0700 -o "$TESTER" -g "$TESTER" "/run/user/$TESTER_UID"
  local runner=/tmp/compat-session.sh app
  if [ "$FORMAT" = deb ]; then app="$DEB_ROOT/hermuse_app"; else
    install -o "$TESTER" -g "$TESTER" -m 0755 "$APPIMAGE_FILE" "/home/$TESTER/$(basename "$APPIMAGE_FILE")"
    app="/home/$TESTER/$(basename "$APPIMAGE_FILE")"
  fi
  cat >"$runner" <<EOF
export DISPLAY=:99 XAUTHORITY=\$HOME/.Xauthority XDG_RUNTIME_DIR=/run/user/$TESTER_UID
: >"\$XAUTHORITY"
xauth -q add :99 . \$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
Xvfb :99 -screen 0 1600x1000x24 -auth "\$XAUTHORITY" -nolisten tcp >/tmp/compat-xvfb.log 2>&1 &
sleep 3
cd "\$(mktemp -d)" && exec dbus-run-session -- '$app' >/tmp/compat-app.log 2>&1
EOF
  chmod 0755 "$runner"
  runuser -u "$TESTER" -- env -i HOME="/home/$TESTER" PATH=/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 \
    sh "$runner" &
  sleep 5
  gui_init "$EVID"
  if gui_window "^${WINDOW_TITLE}\$" "$(T 240)" >/dev/null; then
    window_checks "$id" compat
  else
    check "$id" window-compat fail "no window under Xvfb" "$(gui_shot compat-no-window)"
  fi
  cp /tmp/compat-app.log "$EVID/logs/" 2>/dev/null
  pkill -u "$TESTER" -x hermuse_app
  return 0
}

main() {
  trap finalize EXIT
  trap 'exit 143' TERM INT HUP
  log "scenario $SCENARIO ($FORMAT) on $GUEST, run $RUN_ID, HERMES_HOME $HERMES_HOME"
  case $SCENARIO in
    fresh) scenario_fresh ;;
    adopt-compatible) scenario_adopt compatible ;;
    adopt-foreign) scenario_adopt foreign ;;
    docker-*) scenario_docker "$SCENARIO" ;;
    lifecycle) scenario_lifecycle ;;
    compat) scenario_compat ;;
  esac
}

main
