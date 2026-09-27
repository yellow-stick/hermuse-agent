#!/usr/bin/env bash
# Hermuse computer entrypoint: X display, XFCE session, CDP proxy, screend and
# a Chromium restart loop. Runs as user `hermuse`; /home/hermuse is the
# persistent volume (Chromium profile, XFCE settings).
set -euo pipefail

export HOME=/home/hermuse

# `docker stop` signals PID 1 only: stop the children (Chromium flushes its
# profile on SIGTERM) and wait for them instead of being SIGKILLed after 10 s.
shutdown() {
  trap - TERM INT
  kill -TERM $(jobs -p) 2>/dev/null || true
  wait || true
  exit 0
}
trap shutdown TERM INT

# A container restart keeps /tmp: drop the previous run's X lock and socket.
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

Xvfb :1 -screen 0 1920x1080x24 -nolisten tcp &
for _ in $(seq 20); do
  xdpyinfo -display :1 >/dev/null 2>&1 && break
  sleep 0.25
done
if ! xdpyinfo -display :1 >/dev/null 2>&1; then
  echo "hermuse computer: Xvfb did not start on :1" >&2
  exit 1
fi
export DISPLAY=:1

# Seed the default panel layout so xfce4-panel's first-start dialog never
# covers the screen, with the bottom dock (panel-2, the only panel with an
# autohide setting) always hidden so it never covers Chromium's window.
panel_xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
if [ ! -f "$panel_xml" ] && [ -f /etc/xdg/xfce4/panel/default.xml ]; then
  mkdir -p "$(dirname "$panel_xml")"
  sed 's/name="autohide-behavior" type="uint" value="1"/name="autohide-behavior" type="uint" value="2"/' \
    /etc/xdg/xfce4/panel/default.xml > "$panel_xml"
fi

dbus-launch --exit-with-session xfce4-session &

# Chromium ignores --remote-debugging-address: relay its loopback CDP port
# (9222) to 9223 on all container interfaces so Docker can publish it.
python3 /opt/hermuse/cdp_relay.py &

python3 /opt/hermuse/screend.py &

# Restart loop: Hermes' idle janitor may close the browser over CDP.
# --no-sandbox is intentional: the container is the isolation boundary.
profile=/home/hermuse/chrome
while true; do
  # A lock left by a killed Chromium (or by a previous container with another
  # hostname) would make Chromium refuse the profile.
  rm -f "$profile/SingletonLock" "$profile/SingletonSocket" "$profile/SingletonCookie"
  chromium --no-sandbox --disable-dev-shm-usage --disable-gpu --no-first-run \
    --no-default-browser-check --password-store=basic \
    --remote-debugging-port=9222 '--remote-allow-origins=*' \
    --user-data-dir="$profile" --start-maximized --window-size=1920,1080 \
    about:blank &
  wait $! || true
  sleep 1
done
