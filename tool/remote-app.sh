#!/usr/bin/env bash
# `flutter run -d linux` on a headless KasmVNC display, to work on the desktop
# app from a machine without a screen (VPS). Every worktree gets its own
# display, served at http://<worktree>.localhost:6901 by a local proxy shared
# by all worktrees; http://localhost:6901 lists the running ones. The script
# prints the URL and the SSH tunnel that serves it at the same address on
# another computer. The main checkout is `main`, a linked worktree is named
# after its directory. Displays and proxy listen on loopback without login,
# outlive `flutter run` and are reused by the next run; the Orca archive hook
# stops a worktree's display with the worktree. Needs kasmvncserver
# (https://github.com/kasmtech/KasmVNC/releases), openbox, caddy, dbus and
# gnome-keyring. Extra arguments go to `flutter run`.
set -euo pipefail

proxy_port=6901

root="$(git rev-parse --show-toplevel)"
git_dir="$(git -C "$root" rev-parse --path-format=absolute --git-dir)"
common_dir="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)"
if [ "$git_dir" = "$common_dir" ]; then
  name=main
else
  name="$(basename "$root" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n-' '-')"
fi

for bin in Xkasmvnc openbox caddy flock dbus-run-session gnome-keyring-daemon xdpyinfo flutter; do
  if ! command -v "$bin" >/dev/null; then
    echo "remote-app: $bin is not on PATH" >&2
    exit 1
  fi
done

state="${XDG_CACHE_HOME:-$HOME/.cache}/hermuse-remote"
mkdir -p "$state/routes"
# Serializes display allocation and proxy reloads across worktrees. Every
# background child closes fd 9, or it would hold the lock for its lifetime.
exec 9>"$state/lock"
flock 9

alive() { xdpyinfo -display ":$1" >/dev/null 2>&1; }
listening() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# Display :N serves websockets on port 6850 + N, behind the proxy.
display=
if [ -f "$state/routes/$name" ]; then
  read -r d owner <"$state/routes/$name"
  if alive "$d"; then
    if [ "$owner" != "$root" ]; then
      echo "remote-app: $name.localhost already serves $owner" >&2
      exit 1
    fi
    display=$d
  fi
fi

if [ -z "$display" ]; then
  for d in $(seq 52 148); do
    if alive "$d" || [ -e "/tmp/.X$d-lock" ] || listening $((6850 + d)); then
      continue
    fi
    display=$d
    break
  done
  if [ -z "$display" ]; then
    echo "remote-app: no free display between :52 and :148" >&2
    exit 1
  fi
  mkdir -p "$state/$display"
  # Every window fills the screen, which follows the browser size on connect.
  cat >"$state/$display/openbox-rc.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <applications>
    <application class="*">
      <decor>no</decor>
      <maximized>yes</maximized>
    </application>
  </applications>
</openbox_config>
XML
  # Started from the worktree so the archive hook finds and stops the display;
  # openbox moves to $HOME but exits with it.
  (cd "$root" && exec setsid Xkasmvnc ":$display" -geometry 1440x900 -depth 24 \
    -interface 127.0.0.1 -websocketPort $((6850 + display)) \
    -httpd /usr/share/kasmvnc/www -DisableBasicAuth -SecurityTypes None \
    -rfbport 0 -sslOnly 0 -FrameRate 60 -AlwaysShared -nolisten tcp \
    >"$state/$display/kasmvnc.log" 2>&1 </dev/null) 9>&- &
  for _ in $(seq 50); do
    alive "$display" && break
    sleep 0.2
  done
  if ! alive "$display"; then
    echo "remote-app: display :$display did not start, see $state/$display/kasmvnc.log" >&2
    exit 1
  fi
  (cd "$root" && exec env DISPLAY=":$display" setsid openbox \
    --config-file "$state/$display/openbox-rc.xml" \
    >"$state/$display/openbox.log" 2>&1 </dev/null) 9>&- &
  printf '%s %s\n' "$display" "$root" >"$state/routes/$name"
fi

# Proxy config from the live displays; routes of stopped ones are dropped.
routes=""
links=""
for f in "$state"/routes/*; do
  [ -e "$f" ] || continue
  read -r d _ <"$f"
  if ! alive "$d"; then
    rm -f "$f"
    continue
  fi
  n="$(basename "$f")"
  routes+="	@$n host $n.localhost
	handle @$n {
		reverse_proxy 127.0.0.1:$((6850 + d))
	}
"
  links+="<li><a href='http://$n.localhost:$proxy_port/'>$n</a></li>"
done
admin="unix/$state/caddy-admin.sock"
cat >"$state/Caddyfile" <<EOF
{
	admin $admin
	auto_https off
	persist_config off
}

http://localhost:$proxy_port, http://*.localhost:$proxy_port {
	bind 127.0.0.1 [::1]
$routes
	handle {
		header Content-Type "text/html; charset=utf-8"
		respond "<!doctype html><title>Hermuse remote app</title><ul>$links</ul>"
	}
}
EOF
if ! caddy reload --config "$state/Caddyfile" --adapter caddyfile --address "$admin" \
  >>"$state/caddy.log" 2>&1; then
  if listening "$proxy_port"; then
    echo "remote-app: port $proxy_port is taken by another program" >&2
    exit 1
  fi
  rm -f "$state/caddy-admin.sock"
  (cd "$state" && exec setsid caddy run --config "$state/Caddyfile" --adapter caddyfile \
    >>"$state/caddy.log" 2>&1 </dev/null) 9>&- &
  for _ in $(seq 50); do
    listening "$proxy_port" && break
    sleep 0.2
  done
  if ! listening "$proxy_port"; then
    echo "remote-app: proxy did not start, see $state/caddy.log" >&2
    exit 1
  fi
fi
exec 9>&-

# The address this SSH session came in on, else the one of the default route.
if [ -n "${SSH_CONNECTION:-}" ]; then
  host="${SSH_CONNECTION#* * }"
  host="${host%% *}"
else
  host="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')"
fi
echo "remote-app: http://$name.localhost:$proxy_port (display :$display; all: http://localhost:$proxy_port)"
echo "remote-app: from another computer: ssh -N -L $proxy_port:127.0.0.1:$proxy_port $USER@${host:-<this-host>}"
cd "$root/apps/hermuse_app"
# A private session bus with an unlocked keyring: the app keeps credentials
# only in the system keyring, which a headless session lacks.
exec env -u DBUS_SESSION_BUS_ADDRESS DISPLAY=":$display" dbus-run-session -- bash -c \
  'printf "" | gnome-keyring-daemon --unlock --components=secrets >/dev/null && exec flutter run -d linux "$@"' \
  remote-app "$@"
