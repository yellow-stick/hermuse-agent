// Shell recipes are kept separate from transport and orchestration. Every
// interpolation is either shell-quoted or an installer-generated identifier.
import 'dart:convert';

import 'installer.dart';

String shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

/// Fails for any existing path, including a symlink planted by another user.
String createPluginStagingScript(String path) =>
    'umask 077\nmkdir -- ${shellQuote(path)}';

const remoteHome = '/home/hermes';
const remoteHermesHome = '$remoteHome/.hermes';
const remoteCheckout = '$remoteHermesHome/hermes-agent';
const remoteHermes = '$remoteHome/.local/bin/hermes';
const remotePython = '$remoteCheckout/venv/bin/python';
const provisionRoot = '/var/lib/hermuse-provision';

const prerequisitePackages = [
  'ca-certificates',
  'curl',
  'git',
  'tar',
  'unzip',
  'build-essential',
  'python3',
  'python3-dev',
  'python3-venv',
  'libffi-dev',
  'libatomic1',
  'ripgrep',
  'ffmpeg',
  'dbus-user-session',
];

String _health(String predicate) =>
    '''
if ( $predicate ); then
  printf 'HERMUSE_HEALTH_V1:ready\\n'
else
  printf 'HERMUSE_HEALTH_V1:repair\\n'
fi
''';

/// These probes never invoke installers, config loaders or plugin CLI startup.
/// In particular, Hermes config/job loaders may migrate files while reading.
String get prerequisitesHealthScript => _health('''
${prerequisitePackages.map((package) => '''
[ "\$(dpkg-query -W -f='\${db:Status-Status}' $package 2>/dev/null)" = installed ] || exit 1
''').join()}
for tool in curl git python3 sha256sum; do command -v "\$tool" >/dev/null || exit 1; done
''');

final hermesUserHealthScript = _health(r'''
id hermes >/dev/null 2>&1 &&
[ -f /var/lib/hermuse-provision/owns-hermes ] &&
[ "$(getent passwd hermes | cut -d: -f6)" = /home/hermes ] &&
[ "$(id -u hermes)" -ne 0 ] &&
[ -d /home/hermes/.hermes ] &&
[ "$(stat -c %U /home/hermes)" = hermes ] &&
[ "$(stat -c %U /home/hermes/.hermes)" = hermes ] &&
[ "$(stat -c %a /home/hermes/.hermes)" = 700 ]
''');

const publicAddressScript = r'''
if command -v curl >/dev/null; then
  curl -4 --fail --silent --show-error --proto '=https' --max-time 15 https://api.ipify.org
elif command -v python3 >/dev/null; then
  python3 -B -c 'import urllib.request; print(urllib.request.urlopen("https://api.ipify.org", timeout=15).read().decode())'
fi
''';

final hermesHealthScript =
    '''
if [ ! -x $remotePython ]; then
  printf 'HERMUSE_HEALTH_V1:repair\\n'
else
  ${_health(asHermes('''
[ "\$(git -C $remoteCheckout rev-parse HEAD 2>/dev/null)" = $hermesReleaseCommit ] &&
PYTHONDONTWRITEBYTECODE=1 $remotePython -I -S -B -c ${shellQuote('''
import json, os, subprocess, sys
from pathlib import Path
try:
    checkout = Path("$remoteCheckout")
    marker = json.loads((checkout / ".hermes-bootstrap-complete").read_text())
    assert marker.get("schemaVersion") == 1 and marker.get("pinnedCommit") == "$hermesReleaseCommit"
    assert (3, 11) <= sys.version_info[:2] < (3, 14)
    launcher = Path("$remoteHermes")
    expected = "\\n".join((
        "#!/usr/bin/env bash", "unset PYTHONPATH", "unset PYTHONHOME",
        'exec "$remotePython" "$remoteCheckout/hermes" "\$@"', "",
    ))
    assert launcher.is_file() and not launcher.is_symlink() and os.access(launcher, os.X_OK)
    assert launcher.read_text() == expected
    # Only the pinned, reviewed lightweight initializer is imported. Full CLI
    # startup/--version can self-heal and write update/config caches.
    for name in ("hermes", "hermes_cli/__init__.py"):
        target = checkout / name
        assert target.is_file() and not target.is_symlink()
        pinned = subprocess.check_output(
            ["git", "-C", str(checkout), "show", "$hermesReleaseCommit:" + name],
            stderr=subprocess.DEVNULL,
        )
        assert target.read_bytes() == pinned
    sys.path.insert(0, str(checkout))
    import hermes_cli
    assert Path(hermes_cli.__file__).resolve() == (checkout / "hermes_cli/__init__.py").resolve()
    assert isinstance(hermes_cli.__version__, str) and hermes_cli.__version__.strip()
except (OSError, ValueError, AttributeError, AssertionError, ImportError, subprocess.SubprocessError):
    raise SystemExit(1)
''')}
'''))}
fi
''';

/// Refuses foreign paths before any package/user/plugin/configuration mutation.
const managedPathsPreflightScript = r'''
for path in /var/lib/hermuse-provision /var/lib/hermuse-provision/owns-hermes; do
  [ ! -L "$path" ] || { echo 'Installer ownership paths must not be symlinks.' >&2; exit 1; }
  if [ -e "$path" ]; then
    [ "$(stat -c %u "$path")" = 0 ] &&
    [ $((8#$(stat -c %a "$path") & 0022)) = 0 ] || {
      echo 'Installer ownership paths must be root-owned and not writable by other users.' >&2; exit 1;
    }
  fi
done
for path in /home/hermes /home/hermes/.hermes /home/hermes/.hermes/hermes-agent \
  /home/hermes/.hermes/plugins /home/hermes/.hermes/plugins/hermuse \
  /etc/systemd/system/hermuse-dashboard.service /etc/caddy/Caddyfile \
  /etc/caddy/hermuse-remote.caddy; do
  [ ! -L "$path" ] || { echo "Refusing a symlink at managed path: $path" >&2; exit 1; }
done
plugin=/home/hermes/.hermes/plugins/hermuse
if [ -e "$plugin" ] && [ ! -f "$plugin/.hermuse-remote-managed" ]; then
  echo 'An unrelated plugin occupies the Hermuse plugin directory.' >&2; exit 1
fi
if [ -e /etc/caddy/hermuse-remote.caddy ] &&
   ! grep -q '^# Managed by Hermuse remote installer$' /etc/caddy/hermuse-remote.caddy; then
  echo 'The Hermuse Caddy site path holds unrelated configuration.' >&2; exit 1
fi
''';

String pluginHealthScript(Map<String, String> hashes) =>
    '''
if [ ! -x $remotePython ]; then
  printf 'HERMUSE_HEALTH_V1:deferred\\n'
else
  ${_health(asHermes('$remotePython -B -c ${shellQuote('''
import hashlib, importlib.util, json, sys
from pathlib import Path
import yaml
root = Path("$remoteHermesHome/plugins/hermuse")
expected = json.loads(${jsonString(hashes)})
try:
    files_ok = (root / ".hermuse-remote-managed").is_file() and all(
        not (root / name).is_symlink() and
        hashlib.sha256((root / name).read_bytes()).hexdigest() == digest
        for name, digest in expected.items())
    if not files_ok:
        raise SystemExit(1)
    cfg = yaml.safe_load(Path("$remoteHermesHome/config.yaml").read_text()) or {}
    plugins = cfg.get("plugins", {})
    if "hermuse" not in plugins.get("enabled", []) or "hermuse" in plugins.get("disabled", []):
        raise SystemExit(1)
    spec = importlib.util.spec_from_file_location("hermuse_inventory_specs", root / "cron_specs.py")
    specs = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = specs
    spec.loader.exec_module(specs)
    data = json.loads(Path("$remoteHermesHome/cron/jobs.json").read_text())
    records = data["jobs"]
    if not isinstance(records, list):
        raise SystemExit(1)
    for desired in specs.SPECS:
        matches = [job for job in records if isinstance(job, dict)
                   and job.get("origin") == {"source": "hermuse", "key": desired.key}]
        if len(matches) != 1:
            raise SystemExit(1)
        job = matches[0]
        schedule = job.get("schedule")
        schedule_ok = (schedule == desired.schedule or isinstance(schedule, dict)
                       and schedule.get("kind") == "cron" and schedule.get("expr") == desired.schedule)
        if not (job.get("name") == desired.name and job.get("prompt") == desired.prompt
                and job.get("skills") == [desired.skill_ref]
                and job.get("deliver") == "local" and schedule_ok):
            raise SystemExit(1)
except (OSError, ValueError, TypeError, AttributeError, KeyError, ImportError):
    raise SystemExit(1)
''')}'))}
fi
''';

// JSON inside a Python string literal, not shell or executable Python input.
String jsonString(Object value) => jsonEncode(jsonEncode(value));

const computerOwnershipScript = r'''
if command -v docker >/dev/null && command -v python3 >/dev/null &&
   systemctl is-active --quiet docker; then
  python3 -B -c '
import json, subprocess
result = subprocess.run(["docker", "inspect", "--type", "container", "hermuse-computer-hermes"],
                        capture_output=True, text=True, timeout=10)
if result.returncode:
    if "No such" not in result.stderr:
        raise SystemExit("Could not inspect the existing computer container safely.")
else:
    for container in json.loads(result.stdout):
        if not container.get("Config", {}).get("Image", "").startswith("hermuse-computer:"):
            raise SystemExit("An unrelated container occupies the Hermuse computer name; it was not changed.")
'
fi
''';

final computerHealthScript = _health('''
systemctl is-active --quiet docker &&
systemctl is-enabled --quiet docker &&
id -nG hermes | tr ' ' '\\n' | grep -qx docker &&
${asHermes('$remotePython -B -c ${shellQuote(r'''
import json, subprocess, sys
from pathlib import Path
sys.path.insert(0, "/home/hermes/.hermes/plugins")
try:
    from hermuse.computer import runtime, state
    home = Path("/home/hermes/.hermes")
    name = runtime.container_name(home)
    def docker(*args):
        return subprocess.check_output(["docker", *args], timeout=10, text=True)
    container = json.loads(docker("inspect", "--type", "container", name))[0]
    image = json.loads(docker("image", "inspect", runtime.IMAGE))[0]
    ports = container["NetworkSettings"]["Ports"]
    def port(number):
        bindings = ports[str(number) + "/tcp"]
        if len(bindings) != 1 or bindings[0]["HostIp"] != "127.0.0.1":
            raise ValueError("Non-loopback computer port")
        return int(bindings[0]["HostPort"])
    cdp = port(runtime.CDP_PORT)
    screen = port(runtime.SCREEN_PORT)
    token = next(value.split("=", 1)[1] for value in container["Config"]["Env"]
                 if value.startswith("SCREEND_TOKEN="))
    rt = state.read_runtime(home) or {}
    ok = (container["State"]["Running"] is True
          and container["Config"]["Image"] == runtime.IMAGE and container["Image"] == image["Id"]
          and token and rt.get("backend") == "docker" and rt.get("container") == name
          and rt.get("image") == runtime.IMAGE and rt.get("cdp_port") == cdp
          and rt.get("screen_port") == screen and rt.get("token") == token
          and any(mount.get("Name") == runtime.volume_name(home)
                  and mount.get("Destination") == "/home/hermuse"
                  for mount in container.get("Mounts", [])))
    if ok:
        version = json.loads(runtime.loopback_request(f"http://127.0.0.1:{cdp}/json/version", 3))
        ok = isinstance(version.get("webSocketDebuggerUrl"), str) and bool(version["webSocketDebuggerUrl"])
except (OSError, ValueError, TypeError, KeyError, AttributeError, ImportError,
        StopIteration, subprocess.SubprocessError):
    ok = False
raise SystemExit(0 if ok else 1)
''')}')}
''');

String dashboardHealthScript(String domain, {bool authenticate = true}) =>
    _health('''
cmp -s /etc/systemd/system/hermuse-dashboard.service <(printf '%s' ${shellQuote('$dashboardService\n')}) &&
systemctl is-active --quiet hermuse-dashboard.service &&
systemctl is-enabled --quiet hermuse-dashboard.service &&
${asHermes('$remotePython -B -c ${shellQuote('''
import json, sys, urllib.error, urllib.request
from pathlib import Path
import yaml
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None
try:
    cfg = yaml.safe_load(Path("$remoteHermesHome/config.yaml").read_text()) or {}
    dashboard = cfg.get("dashboard", {})
    auth = dashboard.get("basic_auth", {})
    plugins = cfg.get("plugins", {})
    if (dashboard.get("public_url") != "https://$domain" or auth.get("username") != "admin"
            or not auth.get("password_hash") or not auth.get("secret")
            or {"basic", "dashboard_auth/basic"} & set(plugins.get("disabled", []))):
        raise SystemExit(1)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    base = "http://127.0.0.1:9119"
    status = json.loads(opener.open(base + "/api/status", timeout=3).read())
    if not status.get("auth_required") or "basic" not in status.get("auth_providers", []):
        raise SystemExit(1)
    try:
        opener.open(base + "/api/plugins/hermuse/files", timeout=3)
        raise SystemExit(1)
    except urllib.error.HTTPError as exc:
        if exc.code not in (401, 403):
            raise SystemExit(1)
    if ${authenticate ? 'False' : 'True'}:
        raise SystemExit(0)
    request = urllib.request.Request(base + "/auth/password-login",
        data=json.dumps({"provider": "basic", "username": "admin", "password": sys.stdin.read()}).encode(),
        headers={"Content-Type": "application/json"})
    response = opener.open(request, timeout=5)
    # Cookies are Secure on this loopback HTTP hop; explicitly reuse only here.
    cookies = response.headers.get_all("Set-Cookie") or []
    cookie = "; ".join(value.split(";", 1)[0] for value in cookies)
    if not cookie:
        raise SystemExit(1)
    opener.open(urllib.request.Request(base + "/api/plugins/hermuse/files",
                                     headers={"Cookie": cookie}), timeout=3).read()
except (OSError, ValueError, TypeError, KeyError, AttributeError):
    raise SystemExit(1)
''')}')}
''');

final preflightScript =
    r'''
[ "$(uname -s)" = Linux ] || { echo 'A Linux server is required.' >&2; exit 1; }
. /etc/os-release
case "$ID:$VERSION_ID" in
  ubuntu:24.04|ubuntu:26.04|debian:12|debian:13) ;;
  *) echo 'Supported servers: Ubuntu 24.04/26.04 or Debian 12/13.' >&2; exit 1 ;;
esac
case "$(uname -m)" in x86_64|aarch64) ;; *) echo 'x86-64 or ARM64 is required.' >&2; exit 1 ;; esac
[ -d /run/systemd/system ] || { echo 'A running systemd is required.' >&2; exit 1; }
for tool in apt-get bash timeout setsid flock tar runuser ps; do
  command -v "$tool" >/dev/null || { echo "Missing required system tool: $tool" >&2; exit 1; }
done
# MemTotal is slightly smaller than the advertised RAM because of reservations.
mem=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
[ "$mem" -ge 3700000 ] || { echo 'At least 4 GB RAM is required.' >&2; exit 1; }
free=$(df -Pk /home | awk 'END {print $4}')
[ "$free" -ge 10485760 ] || { echo 'At least 10 GiB free disk under /home is required.' >&2; exit 1; }
if systemctl is-active --quiet firewalld || systemctl is-active --quiet nftables; then
  echo 'An existing firewalld/nftables service is active. Configure SSH/80/443 manually instead of replacing it.' >&2
  exit 1
fi
if ! command -v ufw >/dev/null &&
   { [ -e /etc/ufw ] || [ -e /etc/default/ufw ]; }; then
  echo 'A removed UFW package left existing configuration. Restore that firewall manually before provisioning.' >&2; exit 1
fi
if id hermes >/dev/null 2>&1; then
  [ -f /var/lib/hermuse-provision/owns-hermes ] || {
    echo 'The hermes user already exists and is not owned by this installer. Existing accounts are never overwritten.' >&2; exit 1;
  }
  [ "$(getent passwd hermes | cut -d: -f6)" = /home/hermes ] || exit 1
  [ "$(id -u hermes)" -ne 0 ] || exit 1
elif [ -e /home/hermes ]; then
  echo '/home/hermes already exists; it will not be overwritten.' >&2; exit 1
fi
for unit in hermuse-firewall-rollback hermuse-caddy-rollback; do
  if systemctl is-active --quiet "$unit.timer" || systemctl is-active --quiet "$unit.service"; then
    echo "A previous $unit is still pending. Wait for its restoration before retrying." >&2; exit 1
  fi
done
if [ -e /etc/systemd/system/hermuse-dashboard.service ] &&
   ! grep -q '^# Managed by Hermuse remote installer$' /etc/systemd/system/hermuse-dashboard.service; then
  echo 'An unrelated hermuse-dashboard.service exists; it will not be overwritten.' >&2; exit 1
fi
''' +
    managedPathsPreflightScript +
    r'''
printf 'HERMUSE_PREFLIGHT_OK\n'
''';

String get installPrerequisitesScript =>
    '''
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l
missing=()
for package in ${prerequisitePackages.join(' ')}; do
  if [ "\$(dpkg-query -W -f='\${db:Status-Status}' "\$package" 2>/dev/null)" != installed ]; then
    missing+=("\$package")
  fi
done
if [ "\${#missing[@]}" -gt 0 ]; then
  apt-get -o DPkg::Lock::Timeout=120 update
  apt-get -o DPkg::Lock::Timeout=120 install --no-upgrade -y "\${missing[@]}"
fi
''';

const createHermesUserScript = r'''
install -d -m 0700 /var/lib/hermuse-provision
if ! id hermes >/dev/null 2>&1; then
  useradd --create-home --home-dir /home/hermes --shell /bin/bash hermes
  touch /var/lib/hermuse-provision/owns-hermes
fi
[ -f /var/lib/hermuse-provision/owns-hermes ] || exit 1
[ "$(id -u hermes)" -ne 0 ] || exit 1
[ ! -L /home/hermes ] && [ ! -L /home/hermes/.hermes ] || exit 1
[ "$(getent passwd hermes | cut -d: -f6)" = /home/hermes ] || exit 1
chown hermes:hermes /home/hermes
install -d -o hermes -g hermes -m 0700 /home/hermes/.hermes
# No sudoers entry: privileged packages are installed by the SSH administrator.
''';

/// Runs Hermes with only its own HOME, PATH and data directory.
String asHermes(String command) =>
    'runuser -u hermes -- env -i HOME=$remoteHome USER=hermes LOGNAME=hermes '
    'PATH=$remoteHome/.local/bin:$remoteHermesHome/node/bin:/usr/local/bin:/usr/bin:/bin '
    'HERMES_HOME=$remoteHermesHome LANG=C.UTF-8 '
    'bash -euo pipefail -c ${shellQuote('cd $remoteHome\n$command')}';

String downloadInstallerScript(String directory, InstallerSource source) {
  final script = '$directory/install.sh';
  return '''
install -d -m 0755 ${shellQuote(directory)}
${source.downloadUris.map((uri) => '''
if curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \\
    --connect-timeout 15 --max-time 120 \\
    -H 'Accept: application/vnd.github.raw' ${shellQuote('$uri')} -o ${shellQuote('$script.partial')}; then
  if printf '%s  %s\\n' ${shellQuote(source.sha256!)} ${shellQuote('$script.partial')} | sha256sum --check --status; then
    chmod 0644 ${shellQuote('$script.partial')}
    mv ${shellQuote('$script.partial')} ${shellQuote(script)}
    exit 0
  fi
  echo 'Installer SHA-256 verification failed.' >&2
fi
''').join()}
rm -f ${shellQuote('$script.partial')}
echo 'Could not obtain the pinned, SHA-256 verified Hermes installer.' >&2
exit 1
''';
}

/// A server-side watchdog bounds work after an abruptly lost SSH connection.
/// It retains inherited operation locks until the whole process group is gone.
String supervisedCommand(String command, int seconds) =>
    '''
for tool in setsid timeout ps; do
  command -v "\$tool" >/dev/null || { echo "Missing required supervision tool: \$tool" >&2; exit 1; }
done
parent=\$PPID
child=
watcher=
stopping=0
request_stop() {
  stopping=1
  if [ -n "\$child" ]; then
    kill -TERM -- -"\$child" 2>/dev/null || true
    kill -TERM "\$child" 2>/dev/null || true
  fi
  [ -z "\$watcher" ] || kill -TERM "\$watcher" 2>/dev/null || true
}
trap request_stop HUP INT TERM
group_busy() {
  local processes pid pgid state
  # Failure to observe shutdown is not proof of shutdown: retain the lock.
  processes=\$(ps -e -o pid= -o pgid= -o stat= 7>&-) || return 0
  while read -r pid pgid state; do
    if { [ "\$pid" = "\$child" ] || [ "\$pgid" = "\$child" ]; } &&
       [[ "\$state" != Z* ]]; then
      return 0
    fi
  done <<< "\$processes"
  return 1
}
[ "\$stopping" = 0 ] || exit 143
setsid timeout --signal=TERM --kill-after=10s ${seconds}s bash -euo pipefail -c ${shellQuote(command)} <&0 &
child=\$!
(
  trap 'stopping=1' HUP INT TERM
  deadline=\$((SECONDS + $seconds))
  while group_busy; do
    if [ "\$stopping" != 0 ] || ! kill -0 "\$parent" 2>/dev/null ||
       [ "\$SECONDS" -ge "\$deadline" ]; then
      kill -TERM -- -"\$child" 2>/dev/null || true
      kill -TERM "\$child" 2>/dev/null || true
      grace=\$((SECONDS + 10))
      while [ "\$SECONDS" -lt "\$grace" ]; do sleep 1 7>&- || true; done
      kill -KILL -- -"\$child" 2>/dev/null || true
      kill -KILL "\$child" 2>/dev/null || true
      while group_busy; do sleep 1 7>&- || true; done
      break
    fi
    sleep 1 7>&- || true
  done
) </dev/null >/dev/null 2>&1 &
watcher=\$!
code=0
wait "\$child" || code=\$?
if ! group_busy; then
  # The parent holds the inherited lock during this positive shutdown proof.
  kill -KILL "\$watcher" 2>/dev/null || true
elif [ "\$stopping" != 0 ]; then
  kill -TERM "\$watcher" 2>/dev/null || true
fi
while kill -0 "\$watcher" 2>/dev/null; do wait "\$watcher" || true; done
exit "\$code"
''';

String _transactionLock(String unit) =>
    '''
install -d -m 0711 $provisionRoot
exec 8>$provisionRoot/$unit.lock
flock 8
''';

String _beginTransaction(String directory, String unit) =>
    '''
${_transactionLock(unit)}
if systemctl is-active --quiet $unit.timer || systemctl is-active --quiet $unit.service; then
  echo 'Another $unit transaction is still pending. Wait for it to complete.' >&2
  exit 1
fi
printf '%s' ${shellQuote(directory)} > $provisionRoot/$unit.owner
''';

String _ownedTransaction(String directory, String unit) =>
    '''
${_transactionLock(unit)}
[ "\$(cat $provisionRoot/$unit.owner 2>/dev/null || true)" = ${shellQuote(directory)} ] || exit 0
''';

String _finishTransaction(String unit) =>
    '''
systemctl stop $unit.timer
rm -f $provisionRoot/$unit.owner
''';

String firewallConfigureScript(String directory, Set<int> ports) =>
    '''
${_beginTransaction(directory, 'hermuse-firewall-rollback')}
install -d -m 0700 ${shellQuote(directory)}
exec 9>${shellQuote('$directory/lock')}
flock 9
if command -v ufw >/dev/null; then
  ufw status | grep -q '^Status: active' && echo active > ${shellQuote('$directory/previous')} || echo inactive > ${shellQuote('$directory/previous')}
  tar -C / -cpf ${shellQuote('$directory/ufw.tar')} etc/ufw etc/default/ufw
else
  echo inactive > ${shellQuote('$directory/previous')}
fi
cat > ${shellQuote('$directory/rollback.sh')} <<'HERMUSE_ROLLBACK'
#!/bin/bash
set -euo pipefail
${_ownedTransaction(directory, 'hermuse-firewall-rollback')}
exec 9>${shellQuote('$directory/lock')}
flock 9
if [ -f ${shellQuote('$directory/committed')} ] || [ -f ${shellQuote('$directory/restored')} ]; then
  ${_finishTransaction('hermuse-firewall-rollback')}
  exit 0
fi
if command -v ufw >/dev/null; then ufw --force disable; fi
if [ -f ${shellQuote('$directory/ufw.tar')} ]; then
  tar -C / -xpf ${shellQuote('$directory/ufw.tar')}
fi
if [ "\$(cat ${shellQuote('$directory/previous')})" = active ]; then ufw --force enable; fi
touch ${shellQuote('$directory/restored')}
${_finishTransaction('hermuse-firewall-rollback')}
HERMUSE_ROLLBACK
chmod 0700 ${shellQuote('$directory/rollback.sh')}
systemctl reset-failed hermuse-firewall-rollback.timer hermuse-firewall-rollback.service 2>/dev/null || true
# Arm restoration BEFORE package installation, the first rule or activation.
systemd-run --quiet --unit=hermuse-firewall-rollback --on-active=180s /bin/bash ${shellQuote('$directory/rollback.sh')}
touch ${shellQuote('$directory/armed')}
if ! command -v ufw >/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 install --no-upgrade -y ufw
fi
${ports.map((port) => 'ufw insert 1 allow $port/tcp comment "Hermuse remote setup"').join('\n')}
ufw --force enable
''';

String commitRollbackScript(String directory, String unit) =>
    '''
${_transactionLock(unit)}
[ "\$(cat $provisionRoot/$unit.owner 2>/dev/null || true)" = ${shellQuote(directory)} ] || { echo 'The configuration transaction no longer belongs to this attempt.' >&2; exit 1; }
exec 9>${shellQuote('$directory/lock')}
flock 9
[ ! -f ${shellQuote('$directory/restored')} ] || { echo 'The safety timer already restored the previous configuration. Retry installation.' >&2; exit 1; }
touch ${shellQuote('$directory/committed')}
${_finishTransaction(unit)}
''';

String restoreRollbackScript(String directory, String unit) =>
    '''
if [ -f ${shellQuote('$directory/armed')} ] &&
   [ "\$(cat $provisionRoot/$unit.owner 2>/dev/null || true)" = ${shellQuote(directory)} ]; then
  /bin/bash ${shellQuote('$directory/rollback.sh')}
fi
''';

const installDockerScript = r'''
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l
if ! command -v docker >/dev/null; then
  apt-get -o DPkg::Lock::Timeout=120 install -y docker.io
fi
systemctl enable --now docker
getent group docker >/dev/null || { echo 'Docker did not create its access group.' >&2; exit 1; }
usermod -a -G docker hermes
docker version --format '{{.Server.Version}}'
''';

// Pull/build synchronously in the cancellable SSH process group. The plugin's
// setup can then configure Hermes without leaving a detached bootstrap behind.
const prepareComputerImageScript = r'''
import subprocess, sys
sys.path.insert(0, "/home/hermes/.hermes/plugins")
from hermuse.computer.runtime import IMAGE, REGISTRY_IMAGE, IMAGE_DIR
if subprocess.run(["docker", "image", "inspect", IMAGE],
                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
    if subprocess.run(["docker", "pull", REGISTRY_IMAGE]).returncode == 0:
        subprocess.run(["docker", "tag", REGISTRY_IMAGE, IMAGE], check=True)
    else:
        subprocess.run(["docker", "build", "-t", IMAGE, str(IMAGE_DIR)], check=True)
''';

/// Recreates a stale managed container without touching its named home volume.
const repairComputerContainerScript = r'''
import json, subprocess, sys
from pathlib import Path
sys.path.insert(0, "/home/hermes/.hermes/plugins")
from hermuse.computer.runtime import IMAGE, container_name, volume_name
home = Path("/home/hermes/.hermes")
name = container_name(home)
existing = subprocess.run(["docker", "inspect", "--type", "container", name],
                          capture_output=True, text=True, timeout=10)
if existing.returncode == 0:
    container = json.loads(existing.stdout)[0]
    if not container["Config"]["Image"].startswith("hermuse-computer:"):
        raise SystemExit("An unrelated container occupies the Hermuse computer name.")
    image = json.loads(subprocess.check_output(
        ["docker", "image", "inspect", IMAGE], text=True, timeout=10))[0]
    ports = container.get("HostConfig", {}).get("PortBindings", {})
    loopback = all(bindings and all(binding.get("HostIp") == "127.0.0.1" for binding in bindings)
                   for bindings in (ports.get("9223/tcp"), ports.get("8765/tcp")))
    token = any(value.startswith("SCREEND_TOKEN=") and value.split("=", 1)[1]
                for value in container["Config"].get("Env", []))
    home_mounted = any(mount.get("Name") == volume_name(home) and mount.get("Destination") == "/home/hermuse"
                       for mount in container.get("Mounts", []))
    if (container["Config"]["Image"] != IMAGE or container["Image"] != image["Id"]
            or not loopback or not token or not home_mounted):
        subprocess.run(["docker", "rm", "-f", name], check=True, timeout=30)
elif "No such" not in existing.stderr:
    raise SystemExit("Could not inspect the existing computer container safely.")
''';

const dashboardPasswordScript = r'''
import secrets, sys
sys.path.insert(0, sys.prefix + "/..")
from plugins.dashboard_auth.basic import hash_password
from hermes_cli.config import load_config, save_config
from hermes_cli.plugins_cmd import ensure_basic_auth_plugin_enabled_in_config
pw = sys.stdin.read()
if len(pw) < 24:
    raise SystemExit("Refusing an empty or short dashboard password")
cfg = load_config()
auth = cfg.setdefault("dashboard", {}).setdefault("basic_auth", {})
auth.update(username="admin", password_hash=hash_password(pw), password="",
            secret=secrets.token_urlsafe(32))
ensure_basic_auth_plugin_enabled_in_config(cfg)
save_config(cfg)
''';

const dashboardService = '''# Managed by Hermuse remote installer
[Unit]
Description=Hermuse Hermes dashboard
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=hermes
Group=hermes
SupplementaryGroups=docker
WorkingDirectory=/home/hermes/.hermes
Environment=HOME=/home/hermes
Environment=HERMES_HOME=/home/hermes/.hermes
Environment=PATH=/home/hermes/.local/bin:/home/hermes/.hermes/node/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/hermes/.local/bin/hermes dashboard --port 9119 --host 127.0.0.1 --no-open
Restart=on-failure
RestartSec=5
UMask=0077

[Install]
WantedBy=multi-user.target
''';

String configureDashboardScript() =>
    '''
[ ! -L /etc/systemd/system/hermuse-dashboard.service ] || exit 1
if [ -e /etc/systemd/system/hermuse-dashboard.service ] &&
   ! grep -q '^# Managed by Hermuse remote installer\$' /etc/systemd/system/hermuse-dashboard.service; then
  echo 'An unrelated dashboard service was not overwritten.' >&2; exit 1
fi
if ! cmp -s /etc/systemd/system/hermuse-dashboard.service <(printf '%s' ${shellQuote('$dashboardService\n')}); then
  printf '%s' ${shellQuote('$dashboardService\n')} > /etc/systemd/system/hermuse-dashboard.service
  chmod 0644 /etc/systemd/system/hermuse-dashboard.service
  systemctl daemon-reload
fi
if ! systemctl is-enabled --quiet hermuse-dashboard.service; then systemctl enable hermuse-dashboard.service; fi
systemctl restart hermuse-dashboard.service
for attempt in \$(seq 1 60); do
  if curl --fail --silent --max-time 3 http://127.0.0.1:9119/api/status >/dev/null; then exit 0; fi
  sleep 1
done
echo 'The loopback dashboard did not become ready.' >&2
exit 1
''';

const installCaddyScript = r'''
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l
if ! command -v caddy >/dev/null; then
  apt-get -o DPkg::Lock::Timeout=120 install -y caddy
fi
# Custom service command lines must not be silently switched to another config.
exec_start=$(systemctl show caddy --property=ExecStart --value)
case "$exec_start" in *'/etc/caddy/Caddyfile'*) ;; *) echo 'Caddy uses a custom configuration path; it was not changed.' >&2; exit 1 ;; esac
''';

// Caddy itself resolves every import/glob. The classifier inspects its JSON,
// including wrong upstreams and wildcard routes, rather than parsing Caddyfiles.
// Arguments: <host> <expected upstream dial> [dedicated <allowed host>...]. The
// dedicated form additionally requires a configuration made only of exact
// single-host sites for the allowed hosts, each at most once.
const _caddyRouteStatus = r'''
import fnmatch, json, sys
domain, dial = sys.argv[1], sys.argv[2]
def routes(node):
    if isinstance(node, list):
        return [route for child in node for route in routes(child)]
    if not isinstance(node, dict):
        return []
    hosts = [host for matcher in node.get("match", []) for host in matcher.get("host", [])]
    if any(fnmatch.fnmatchcase(domain, host) for host in hosts):
        return [node]
    return [route for child in node.values() for route in routes(child)]
def handlers(node):
    if isinstance(node, list):
        return [handler for child in node for handler in handlers(child)]
    if not isinstance(node, dict):
        return []
    return ([node] if node.get("handler") else []) + [
        handler for child in node.values() for handler in handlers(child)]
data = json.load(sys.stdin)
if sys.argv[3:4] == ["dedicated"]:
    allowed = set(sys.argv[4:])
    apps = data.get("apps", {})
    servers = apps.get("http", {}).get("servers", {})
    top = [route for server in servers.values() for route in server.get("routes", [])]
    names = []
    for route in top:
        sites = {tuple(matcher.get("host") or ()) for matcher in route.get("match") or [{}]}
        site = sites.pop() if len(sites) == 1 else ()
        if len(site) != 1 or site[0] not in allowed or site[0] in names:
            names = None
            break
        names.append(site[0])
    if set(apps) != {"http"} or len(servers) != 1 or not top or names is None:
        print("foreign")
        raise SystemExit(0)
matches = routes(data)
if not matches:
    print("missing")
elif len(matches) != 1:
    print("ambiguous")
else:
    chain = handlers(matches[0].get("handle", []))
    proxies = [handler for handler in chain if handler.get("handler") == "reverse_proxy"]
    exact = any(matcher.get("host") == [domain] for matcher in matches[0].get("match", []))
    owned = exact and any(handler.get("handler") == "vars"
                          and handler.get("hermuse_remote_installer") == "v1" for handler in chain)
    safe = (owned and len(proxies) == 1
            and proxies[0].get("upstreams") == [{"dial": dial}]
            and all(handler["handler"] in ("subroute", "vars", "reverse_proxy") for handler in chain))
    print("ready" if safe else "owned" if owned else "foreign")
''';

/// The web app owns its own origin root (manifest, service worker, relay
/// detection), so it is published on a dedicated sslip.io host.
String webAppDomain(String dashboardDomain) => 'app.$dashboardDomain';

const dashboardLoopbackPort = 9119;
const webLoopbackPort = 9120;
const webContainerName = 'hermuse-web';
const webContainerLabel = 'org.hermuse.remote-installer=web-v1';
const webImageRepository = 'ghcr.io/yellow-stick/hermuse-web';

String _caddyRoute(
  String config,
  String host,
  int port, {
  List<String>? dedicated,
}) =>
    'caddy adapt --config $config --adapter caddyfile |\n'
    '  python3 -B -c ${shellQuote(_caddyRouteStatus)} ${shellQuote(host)} '
    '127.0.0.1:$port'
    '${dedicated == null ? '' : ' dedicated ${dedicated.map(shellQuote).join(' ')}'}';

String caddySite(String domain, {String? webDomain}) =>
    '''# Managed by Hermuse remote installer
$domain {
  vars hermuse_remote_installer v1
  reverse_proxy 127.0.0.1:$dashboardLoopbackPort
}
${webDomain == null ? '' : '''$webDomain {
  vars hermuse_remote_installer v1
  reverse_proxy 127.0.0.1:$webLoopbackPort
}
'''}''';

/// [webDomain] is the web host the fragment must publish, if any. A managed
/// fragment may always carry an owned block for the derived web host, so a
/// previously published web app is recognized rather than called foreign.
String caddyOwnershipScript(String domain, {String? webDomain}) {
  final fragmentHosts = [domain, webAppDomain(domain)];
  return '''
[ ! -L /etc/caddy/Caddyfile ] || { echo 'Caddyfile is a symlink; refusing to replace it.' >&2; exit 1; }
site=/etc/caddy/hermuse-remote.caddy
[ ! -L "\$site" ] || { echo 'The Hermuse Caddy site is a symlink.' >&2; exit 1; }
if [ -e "\$site" ] && ! grep -q '^# Managed by Hermuse remote installer\$' "\$site"; then
  echo 'The Hermuse Caddy site path holds unrelated configuration.' >&2; exit 1
fi
for path in /etc/caddy/Caddyfile "\$site"; do
  if [ -e "\$path" ]; then
    [ -f "\$path" ] && [ "\$(stat -c %u "\$path")" = 0 ] &&
    [ \$((8#\$(stat -c %a "\$path") & 0022)) = 0 ] || {
      echo 'Caddy configuration must be regular, root-owned and not writable by other users.' >&2; exit 1;
    }
  fi
done
if command -v caddy >/dev/null; then
  exec_start=\$(systemctl show caddy --property=ExecStart --value)
  case "\$exec_start" in *'/etc/caddy/Caddyfile'*) ;; *) echo 'Caddy uses a custom configuration path; it was not changed.' >&2; exit 1 ;; esac
  command -v python3 >/dev/null || { echo 'Python is required to inspect existing Caddy routes safely.' >&2; exit 1; }
  owned=missing
  owned_web=missing
  if [ -f "\$site" ]; then
    owned=\$(${_caddyRoute('"\$site"', domain, dashboardLoopbackPort, dedicated: fragmentHosts)})
    owned_web=\$(${_caddyRoute('"\$site"', fragmentHosts[1], webLoopbackPort, dedicated: fragmentHosts)})
    if { [ "\$owned" != ready ] && [ "\$owned" != owned ]; } ||
       { [ "\$owned_web" != ready ] && [ "\$owned_web" != owned ] && [ "\$owned_web" != missing ]; }; then
      echo 'The Hermuse Caddy fragment contains unrelated configuration; it was not changed.' >&2; exit 1
    fi
  fi
  route=\$(${_caddyRoute('/etc/caddy/Caddyfile', domain, dashboardLoopbackPort)})
  if [ "\$route" != missing ]; then
    # Even an identical dashboard upstream is unrelated without an owned site.
    if { [ "\$route" != ready ] && [ "\$route" != owned ]; } ||
       { [ "\$owned" != ready ] && [ "\$owned" != owned ]; }; then
      echo 'An unrelated Caddy route already owns $domain; it was not changed.' >&2; exit 1
    fi
  fi
${webDomain == null ? '' : '''
  route=\$(${_caddyRoute('/etc/caddy/Caddyfile', webDomain, webLoopbackPort)})
  if [ "\$route" != missing ]; then
    if { [ "\$route" != ready ] && [ "\$route" != owned ]; } ||
       { [ "\$owned_web" != ready ] && [ "\$owned_web" != owned ]; }; then
      echo 'An unrelated Caddy route already owns $webDomain, the web app address; it was not changed.' >&2; exit 1
    fi
  fi
'''}elif [ -e /etc/caddy/Caddyfile ] || [ -e "\$site" ]; then
  echo 'Existing Caddy configuration cannot be inspected without Caddy. Restore its package before setup.' >&2; exit 1
fi
''';
}

String caddyHealthScript(String domain, {String? webDomain}) =>
    '''
${caddyOwnershipScript(domain, webDomain: webDomain)}
${_health('''
command -v caddy >/dev/null &&
cmp -s /etc/caddy/hermuse-remote.caddy <(printf '%s' ${shellQuote(caddySite(domain, webDomain: webDomain))}) &&
systemctl is-active --quiet caddy &&
systemctl is-enabled --quiet caddy &&
route=\$(${_caddyRoute('/etc/caddy/Caddyfile', domain, dashboardLoopbackPort)}) &&
[ "\$route" = ready ] &&
${webDomain == null ? '' : '''web_route=\$(${_caddyRoute('/etc/caddy/Caddyfile', webDomain, webLoopbackPort)}) &&
[ "\$web_route" = ready ] &&
'''}caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
''')}
''';

String caddyConfigureScript(
  String directory,
  String domain, {
  String? webDomain,
}) =>
    '''
${caddyOwnershipScript(domain, webDomain: webDomain)}
${_beginTransaction(directory, 'hermuse-caddy-rollback')}
install -d -m 0700 ${shellQuote(directory)}
exec 9>${shellQuote('$directory/lock')}
flock 9
[ ! -L /etc/caddy/Caddyfile ] || { echo 'Caddyfile is a symlink; refusing to replace it.' >&2; exit 1; }
site=/etc/caddy/hermuse-remote.caddy
[ ! -L "\$site" ] || exit 1
if [ -e "\$site" ] && ! grep -q '^# Managed by Hermuse remote installer\$' "\$site"; then
  echo 'The Hermuse Caddy site path holds unrelated configuration.' >&2; exit 1
fi
cp -a /etc/caddy/Caddyfile ${shellQuote('$directory/Caddyfile')}
if [ -e "\$site" ]; then cp -a "\$site" ${shellQuote('$directory/site')}; fi
systemctl is-active --quiet caddy && touch ${shellQuote('$directory/was-active')} || true
systemctl is-enabled --quiet caddy && touch ${shellQuote('$directory/was-enabled')} || true
cat > ${shellQuote('$directory/rollback.sh')} <<'HERMUSE_ROLLBACK'
#!/bin/bash
set -euo pipefail
${_ownedTransaction(directory, 'hermuse-caddy-rollback')}
exec 9>${shellQuote('$directory/lock')}
flock 9
if [ -f ${shellQuote('$directory/committed')} ] || [ -f ${shellQuote('$directory/restored')} ]; then
  ${_finishTransaction('hermuse-caddy-rollback')}
  exit 0
fi
cp -a ${shellQuote('$directory/Caddyfile')} /etc/caddy/Caddyfile
if [ -e ${shellQuote('$directory/site')} ]; then
  cp -a ${shellQuote('$directory/site')} /etc/caddy/hermuse-remote.caddy
else
  rm -f /etc/caddy/hermuse-remote.caddy
fi
if [ -e ${shellQuote('$directory/was-active')} ]; then
  systemctl reload-or-restart caddy
else
  systemctl stop caddy
fi
if [ ! -e ${shellQuote('$directory/was-enabled')} ]; then systemctl disable caddy; fi
touch ${shellQuote('$directory/restored')}
${_finishTransaction('hermuse-caddy-rollback')}
HERMUSE_ROLLBACK
chmod 0700 ${shellQuote('$directory/rollback.sh')}
systemctl reset-failed hermuse-caddy-rollback.timer hermuse-caddy-rollback.service 2>/dev/null || true
systemd-run --quiet --unit=hermuse-caddy-rollback --on-active=600s /bin/bash ${shellQuote('$directory/rollback.sh')}
touch ${shellQuote('$directory/armed')}
printf '%s' ${shellQuote(caddySite(domain, webDomain: webDomain))} > "\$site"
chmod 0644 "\$site"
route=\$(${_caddyRoute('/etc/caddy/Caddyfile', domain, dashboardLoopbackPort)})
if [ "\$route" = missing ]; then
  printf '\\nimport /etc/caddy/hermuse-remote.caddy\\n' >> /etc/caddy/Caddyfile
elif [ "\$route" != ready ]; then
  echo 'The desired Hermuse Caddy route collides with existing configuration.' >&2; exit 1
fi
${webDomain == null ? '' : '''route=\$(${_caddyRoute('/etc/caddy/Caddyfile', webDomain, webLoopbackPort)})
if [ "\$route" != ready ]; then
  echo 'The desired Hermuse web app route collides with existing configuration.' >&2; exit 1
fi
'''}caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl enable caddy
systemctl reload-or-restart caddy
''';

String webImageReference(String version) => '$webImageRepository:$version';

// Shared by inventory and deployment. A label proves the installer created the
// container; a matching name alone is foreign and is never changed.
const _webInspection = r'''
import json, os, shutil, socket, subprocess, sys, tempfile, time, urllib.request
web, dashboard, image = sys.argv[1:4]
NAME = "hermuse-web"
LABEL = "org.hermuse.remote-installer"
PORT = 9120
BINDING = {"8787/tcp": [{"HostIp": "127.0.0.1", "HostPort": str(PORT)}]}
FOREIGN = ("A Docker container named hermuse-web that this installer did not create exists; "
           "it was not changed. Rename or remove it, or choose not to publish the web app.")
BUSY = ("Port 127.0.0.1:9120, needed by the web app, is used by another service; nothing was "
        "changed. Free the port or choose not to publish the web app.")
def docker(*args, timeout=30):
    return subprocess.run(["docker", *args], stdin=subprocess.DEVNULL, capture_output=True,
                          text=True, timeout=timeout)
DOCKER = bool(shutil.which("docker")) and subprocess.run(
    ["systemctl", "is-active", "--quiet", "docker"], stdin=subprocess.DEVNULL).returncode == 0
def container():
    if not DOCKER:
        return None
    result = docker("inspect", "--type", "container", NAME)
    if result.returncode:
        if "No such" in result.stderr or "not found" in result.stderr:
            return None
        raise SystemExit("Could not inspect the existing web app container safely.")
    items = json.loads(result.stdout)
    if not isinstance(items, list) or len(items) != 1:
        raise SystemExit("Docker returned an ambiguous web app container identity.")
    return items[0]
def owned(item):
    return ((item.get("Config") or {}).get("Labels") or {}).get(LABEL) == "web-v1"
def running(item):
    return (item.get("State") or {}).get("Running") is True
def bound(item):
    return (item.get("HostConfig") or {}).get("PortBindings") == BINDING
def answering():
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        body = json.loads(opener.open("http://127.0.0.1:%d/relay/health" % PORT, timeout=3).read())
        return isinstance(body, dict) and body.get("ok") is True
    except (OSError, ValueError):
        return False
def current(item):
    if not image or not DOCKER:
        return False
    local = docker("image", "inspect", "--format", "{{.Id}}", image)
    config = item.get("Config") or {}
    host = item.get("HostConfig") or {}
    env = config.get("Env") or []
    secret = "HERMUSE_RELAY_ADMIN_TOKEN="
    return (local.returncode == 0 and running(item) and bound(item)
            and config.get("Image") == image and item.get("Image") == local.stdout.strip()
            and (host.get("RestartPolicy") or {}).get("Name") == "unless-stopped"
            and host.get("ReadonlyRootfs") is True
            and "HERMUSE_RELAY_ORIGIN=https://" + web in env
            and "HERMUSE_RELAY_UPSTREAMS=https://" + dashboard in env
            and any(value.startswith(secret) and len(value) >= len(secret) + 24 for value in env))
def port_taken():
    if DOCKER:
        published = docker("ps", "--filter", "publish=%d" % PORT, "--format", "{{.Names}}")
        if published.returncode:
            raise SystemExit("Could not inspect Docker port bindings safely.")
        if any(name != NAME for name in published.stdout.split()):
            return True
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(("127.0.0.1", PORT))
        return False
    except OSError:
        return True
    finally:
        probe.close()
''';

const _webInventory = r'''
publish = sys.argv[4] == "publish"
item = container()
if item is not None and not owned(item):
    if publish:
        raise SystemExit(FOREIGN)
    item = None
if publish and not (item is not None and running(item) and bound(item)) and port_taken():
    raise SystemExit(BUSY)
if item is None:
    print("HERMUSE_HEALTH_V1:absent")
else:
    print("HERMUSE_HEALTH_V1:" + ("ready" if current(item) and answering() else "repair"))
''';

const _webDeploy = r'''
token = sys.stdin.read().strip()
if len(token) < 24:
    raise SystemExit("Refusing an empty or short relay admin token.")
if not DOCKER:
    raise SystemExit("Docker is not running; the web app cannot be started.")
item = container()
if item is not None:
    if not owned(item):
        raise SystemExit(FOREIGN)
    if current(item) and answering():
        raise SystemExit(0)
    if docker("rm", "-f", item["Id"], timeout=60).returncode:
        raise SystemExit("The previous web app container could not be replaced.")
if port_taken():
    raise SystemExit(BUSY)
os.makedirs(sys.argv[4], 0o700, exist_ok=True)
handle, path = tempfile.mkstemp(prefix=".hermuse-web-env-", dir=sys.argv[4])
try:
    with os.fdopen(handle, "w") as stream:
        stream.write("HERMUSE_RELAY_ADMIN_TOKEN=" + token + "\n"
                     "HERMUSE_RELAY_ORIGIN=https://" + web + "\n"
                     "HERMUSE_RELAY_UPSTREAMS=https://" + dashboard + "\n")
    started = docker("run", "-d", "--name", NAME, "--label", LABEL + "=web-v1",
                     "--restart", "unless-stopped", "-p", "127.0.0.1:%d:8787" % PORT,
                     "--read-only", "--tmpfs", "/tmp:rw,size=16m", "--cap-drop", "ALL",
                     "--security-opt", "no-new-privileges", "--env-file", path, image, timeout=180)
finally:
    os.unlink(path)
if started.returncode:
    raise SystemExit("The web app container could not be started: " + started.stderr.strip()[:1000])
for attempt in range(60):
    if answering():
        raise SystemExit(0)
    time.sleep(1)
raise SystemExit("The web app did not answer on 127.0.0.1:9120 within 60 seconds.")
''';

/// Read-only. Prints `ready` for an owned, current, answering deployment,
/// `repair` for an owned one that is not, and `absent` otherwise. With
/// [publish], a foreign `hermuse-web` container or another listener on the
/// loopback port fails before any mutation.
String webInventoryScript(
  String webDomain,
  String dashboardDomain,
  String? image, {
  required bool publish,
}) =>
    '''
if command -v python3 >/dev/null; then
  python3 -B -c ${shellQuote(_webInspection + _webInventory)} ${shellQuote(webDomain)} ${shellQuote(dashboardDomain)} ${shellQuote(image ?? '')} ${publish ? 'publish' : 'keep'}
else
  printf 'HERMUSE_HEALTH_V1:absent\\n'
fi
''';

/// Replaces an owned stale container and starts the current one. The relay
/// admin token arrives on stdin and only touches a root-only temporary env
/// file that is removed after `docker run`.
String webDeployScript(
  String webDomain,
  String dashboardDomain,
  String image,
) =>
    'python3 -B -c ${shellQuote(_webInspection + _webDeploy)} '
    '${shellQuote(webDomain)} ${shellQuote(dashboardDomain)} '
    '${shellQuote(image)} $provisionRoot';
