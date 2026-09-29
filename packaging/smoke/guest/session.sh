#!/bin/sh
# Desktop session of the smoke guest. linux.sh (root) makes getty autologin the
# synthetic `tester` on tty1 and execs this from ~/.bash_profile, so it runs in
# a local, active logind session on seat0 with the systemd user bus, like a
# real desktop login. It brings up an X11 display (Xvfb) with a window manager
# and the polkit authentication agent of that session, then runs the command
# files root drops into the spool: everything the app spawns (including its
# pkexec) belongs to this session, and the real polkit dialog appears on :99.
set -u

state=/run/hermuse-smoke
spool=$state/spool
out=$state/out
display=:99

export DISPLAY=$display XAUTHORITY="$HOME/.Xauthority"
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi

(umask 077 && : >"$XAUTHORITY")
xauth -q -f "$XAUTHORITY" add "$display" . "$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
Xvfb "$display" -screen 0 1920x1080x24 -dpi 96 -auth "$XAUTHORITY" -nolisten tcp >"$out/xvfb.log" 2>&1 &
tries=0
until xdpyinfo >/dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -gt 150 ]; then
    echo "Xvfb did not start" >"$out/session-failed"
    exit 1
  fi
  sleep 0.2
done

# D-Bus/systemd activated services (gnome-keyring prompts) must reach this
# display.
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY >"$out/activation-env.log" 2>&1
openbox --sm-disable >"$out/openbox.log" 2>&1 &
/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 >"$out/polkit-agent.log" 2>&1 &

{
  echo "session=${XDG_SESSION_ID:-}"
  loginctl show-session "${XDG_SESSION_ID:-}" -p Type -p Class -p Seat -p TTY -p Active -p Remote -p State
  glxinfo -B 2>&1
} >"$out/session-info.txt" 2>&1
env | sort >"$out/session.env"
: >"$out/ready"

# Jobs run one at a time, each in its own session without a controlling
# terminal and with stdin from /dev/null: a prompt (sudo, git credentials,
# a y/N question on /dev/tty) fails instead of blocking the session. Its pid
# is the process group root kills when the job times out. A job started by a
# previous instance of this session (restarted while the job ran) is never
# run twice: it is reported as interrupted (rc 129).
while :; do
  for job in "$spool"/*.sh; do
    [ -e "$job" ] || continue
    name=$(basename "$job" .sh)
    [ -e "$out/$name.rc" ] && continue
    if [ -e "$out/$name.started" ]; then
      echo 129 >"$out/$name.rc"
      continue
    fi
    : >"$out/$name.started"
    setsid sh "$job" </dev/null >"$out/$name.log" 2>&1 &
    echo "$!" >"$out/$name.pid"
    wait "$!"
    echo "$?" >"$out/$name.rc.tmp"
    mv "$out/$name.rc.tmp" "$out/$name.rc"
  done
  sleep 0.3
done
