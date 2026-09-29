#!/bin/sh
# Behaviour of packaging/linux/hermuse-linux-setup without root and without
# touching the system: `plan` only reads (fixture roots through
# HERMUSE_SETUP_ROOT), and every `apply` below is refused before it acts.
set -u
here=$(cd "$(dirname "$0")" && pwd)
helper=$here/../hermuse-linux-setup
if [ "$(id -u)" = 0 ]; then
  echo "helper tests refuse to run as root" >&2
  exit 1
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
count=0
current=''

# Validates the helper's stdout against the protocol and prints one summary
# line per JSON line: `<event> key=value...` or
# `result code=<c> ok=<bool> exit=<n> applied=<a,b>`.
cat > "$tmp/check.py" << 'EOF'
import json
import sys

CATEGORIES = ["hermes-tools", "secret-service", "docker-install", "docker-start", "docker-group"]
PACKAGES = {"git", "curl", "tar", "ca-certificates", "build-essential", "python3-dev",
            "libffi-dev", "libatomic1", "ripgrep", "ffmpeg", "gnome-keyring",
            "libsecret-1-0", "docker.io"}
EXIT = {"ok": 0, "usage": 2, "caller-invalid": 3, "not-root": 3, "unsupported-os": 4,
        "apt-failed": 5, "docker-start-failed": 5, "usermod-failed": 5, "docker-present": 6,
        "docker-unit-missing": 6, "docker-group-missing": 6, "internal": 70}
CODES = {
    "os": {"supported", "unsupported-distribution", "unsupported-release",
           "unsupported-architecture", "os-release-unreadable"},
    "docker-footprint": {"package", "binary", "socket", "unit", "data", "config", "snap",
                         "rootless"},
    "secret-provider": {"present", "absent"},
    "apt-update": {"ok", "failed"},
    "note": {"provider-present"},
    "skip": {"satisfied", "already-active", "already-member"},
    "fail": set(EXIT) - {"ok"},
}
KEYS = {
    "os": {"code", "base"}, "missing": {"category", "package"}, "docker-footprint": {"code"},
    "secret-provider": {"code"}, "begin": {"category"}, "install": {"category", "package"},
    "apt-update": {"code"}, "note": {"category", "code"}, "skip": {"category", "code"},
    "done": {"category"}, "fail": {"category", "code"},
}


def check(path, status):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    if lines[-1] != "":
        raise ValueError("stdout does not end with a newline")
    lines.pop()
    if not lines:
        raise ValueError("no stdout")
    summary = []
    for line in lines[:-1]:
        obj = json.loads(line)
        event = obj.get("event")
        if event not in KEYS or not set(obj) - {"event"} <= KEYS[event]:
            raise ValueError(f"unknown event shape: {line}")
        for key, value in obj.items():
            if not isinstance(value, str):
                raise ValueError(f"non-string value: {line}")
        if "category" in obj and obj["category"] not in CATEGORIES:
            raise ValueError(f"unknown category: {line}")
        if "package" in obj and obj["package"] not in PACKAGES:
            raise ValueError(f"unknown package: {line}")
        if event in CODES and obj.get("code") not in CODES[event]:
            raise ValueError(f"unknown code: {line}")
        if event == "os" and ("base" in obj) != (obj["code"] == "supported"):
            raise ValueError(f"os base mismatch: {line}")
        summary.append(" ".join([event] + [f"{k}={v}" for k, v in obj.items() if k != "event"]))
    last = json.loads(lines[-1])
    result = last.get("result") if set(last) == {"result"} else None
    if not isinstance(result, dict) or set(result) != {"ok", "code", "applied", "exit"}:
        raise ValueError(f"last line is not a result: {lines[-1]}")
    code, applied = result["code"], result["applied"]
    if code not in EXIT or result["exit"] != EXIT[code] or result["exit"] != status:
        raise ValueError(f"exit status {status} does not match {lines[-1]}")
    if result["ok"] is not (status == 0):
        raise ValueError(f"ok does not match the exit status: {lines[-1]}")
    if [c for c in CATEGORIES if c in applied] != applied:
        raise ValueError(f"applied is not in the fixed order: {lines[-1]}")
    summary.append(f"result code={code} ok={str(result['ok']).lower()} exit={status} "
                   f"applied={','.join(applied)}")
    print("\n".join(summary))


try:
    check(sys.argv[1], int(sys.argv[2]))
except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
    print(f"protocol violation: {exc}", file=sys.stderr)
    sys.exit(1)
EOF

begin() {
  current=$1
  count=$((count + 1))
}

fail() {
  printf 'FAIL %s: %s\n' "$current" "$1"
  if [ -s "$tmp/summary" ]; then sed 's/^/    /' "$tmp/summary"; fi
  failures=$((failures + 1))
}

# helper [VAR=value...] ARGS... — runs the helper through `env`, validates
# its stdout and leaves status + $tmp/summary.
helper() {
  env "$@" < /dev/null > "$tmp/out" 2> "$tmp/err"
  status=$?
  if ! python3 "$tmp/check.py" "$tmp/out" "$status" > "$tmp/summary" 2> "$tmp/violation"; then
    : > "$tmp/summary"
    fail "$(cat "$tmp/violation")"
    return 1
  fi
}

has() {
  grep -qxF -- "$1" "$tmp/summary"
}

expect() {
  has "$1" || fail "expected line: $1"
}

expect_not() {
  if has "$1"; then fail "unexpected line: $1"; fi
}

lines() {
  wc -l < "$tmp/summary" | tr -d ' '
}

# fixture NAME OS_RELEASE — a fake root with an empty dpkg database.
fixture() {
  root=$tmp/$1
  mkdir -p "$root/etc" "$root/var/lib/dpkg"
  printf '%s\n' "$2" > "$root/etc/os-release"
  : > "$root/var/lib/dpkg/status"
}

# package ROOT NAME ARCH [STATUS]
package() {
  printf 'Package: %s\nStatus: %s\nMaintainer: Fixture <fixture@example.invalid>\nArchitecture: %s\nVersion: 1\nDescription: fixture\n\n' \
    "$2" "${4:-install ok installed}" "$3" >> "$1/var/lib/dpkg/status"
}

all_tools() {
  for name in git curl tar build-essential python3-dev libffi-dev libatomic1 ripgrep ffmpeg \
    gnome-keyring libsecret-1-0; do
    package "$1" "$name" amd64
  done
  package "$1" ca-certificates all
}

UBUNTU_NOBLE='NAME="Ubuntu"
VERSION_ID="24.04"
ID=ubuntu
ID_LIKE=debian
VERSION_CODENAME=noble
UBUNTU_CODENAME=noble'

plan() {
  helper HERMUSE_SETUP_ROOT="$1" sh "$helper" plan
}

native_arch=$(dpkg --print-architecture 2> /dev/null || true)

# --- usage ---------------------------------------------------------------

begin 'the helper parses'
sh -n "$helper" || fail 'sh -n failed'

begin 'anything but plan or fixed categories is refused'
for args in '' 'install' 'plan extra' 'apply' 'apply docker.io' 'apply gnome-keyring' \
  'apply hermes-tools hermes-tools' 'apply hermes-tools --yes' 'apply hermes-tools;id' \
  'apply HERMES-TOOLS' 'apply docker-install /usr/bin/docker'; do
  # shellcheck disable=SC2086 # the argument sets are split on purpose
  helper PKEXEC_UID="$(id -u)" sh "$helper" $args || continue
  [ "$status" = 2 ] || fail "'$args' exited $status"
  expect 'result code=usage ok=false exit=2 applied='
  [ "$(lines)" = 1 ] || fail "'$args' printed events before refusing"
done

begin 'an empty category is refused'
helper PKEXEC_UID="$(id -u)" sh "$helper" apply '' && expect 'result code=usage ok=false exit=2 applied='

# --- callers -------------------------------------------------------------

unknown_uid=4242420
while getent passwd "$unknown_uid" > /dev/null; do unknown_uid=$((unknown_uid + 1)); done

begin 'apply refuses a missing, root or malformed PKEXEC_UID'
helper -u PKEXEC_UID sh "$helper" apply hermes-tools &&
  expect 'result code=caller-invalid ok=false exit=3 applied='
for uid in '' 0 00 "0$(id -u)" -1 abc "$(id -u) " "$unknown_uid"; do
  helper PKEXEC_UID="$uid" sh "$helper" apply hermes-tools docker-group || continue
  expect 'result code=caller-invalid ok=false exit=3 applied='
  [ "$(lines)" = 1 ] || fail "PKEXEC_UID='$uid' printed events before refusing"
done

begin 'apply without root stops before any change'
helper PKEXEC_UID="$(id -u)" sh "$helper" apply hermes-tools secret-service docker-install \
  docker-start docker-group
expect_not 'begin category=hermes-tools'
if has 'result code=unsupported-os ok=false exit=4 applied='; then
  : # this machine is outside the supported set; refused even earlier
else
  expect 'result code=not-root ok=false exit=3 applied='
fi
[ "$(lines)" = 2 ] || fail 'expected only the os event and the result'

begin 'apply never reads HERMUSE_SETUP_ROOT'
helper sh "$helper" plan
real_os=$(grep '^os ' "$tmp/summary")
fixture fedora 'ID=fedora
VERSION_ID=42'
helper HERMUSE_SETUP_ROOT="$tmp/fedora" PKEXEC_UID="$(id -u)" sh "$helper" apply hermes-tools
expect "$real_os"

# --- plan on this machine ------------------------------------------------

begin 'plan on this machine is read-only protocol output'
helper sh "$helper" plan
case $status in
  0) expect 'result code=ok ok=true exit=0 applied=' ;;
  4) expect 'result code=unsupported-os ok=false exit=4 applied=' ;;
  *) fail "plan exited $status" ;;
esac
cp "$tmp/out" "$tmp/first"
helper sh "$helper" plan
cmp -s "$tmp/first" "$tmp/out" || fail 'two plans of the same machine differ'

# --- operating system ----------------------------------------------------

begin 'supported Debian and Ubuntu families resolve to their base release'
if [ "$native_arch" != amd64 ]; then
  echo "SKIP $current: dpkg architecture is '$native_arch'"
else
  while IFS='|' read -r name base release; do
    fixture "$name" "$(printf '%b' "$release")"
    plan "$root" || continue
    [ "$status" = 0 ] || fail "$name exited $status"
    expect "os code=supported base=$base"
  done << 'EOF'
ubuntu-22.04|jammy|NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\nVERSION_ID="22.04"\nVERSION_CODENAME=jammy\nUBUNTU_CODENAME=jammy
ubuntu-24.04|noble|NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\nVERSION_ID="24.04"\nVERSION_CODENAME=noble\nUBUNTU_CODENAME=noble
ubuntu-26.04|resolute|NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\nVERSION_ID="26.04"\nVERSION_CODENAME=resolute\nUBUNTU_CODENAME=resolute
debian-12|bookworm|PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"\nID=debian\nVERSION_ID="12"\nVERSION_CODENAME=bookworm
debian-13|trixie|PRETTY_NAME="Debian GNU/Linux 13 (trixie)"\nID=debian\nVERSION_ID="13"\nVERSION_CODENAME=trixie
pop-24.04|noble|NAME="Pop!_OS"\nID=pop\nID_LIKE="ubuntu debian"\nVERSION_ID="24.04"\nVERSION_CODENAME=noble\nUBUNTU_CODENAME=noble
mint-22|noble|NAME="Linux Mint"\nID=linuxmint\nID_LIKE="ubuntu debian"\nVERSION_ID="22.1"\nVERSION_CODENAME=xia\nUBUNTU_CODENAME=noble
lmde-6|bookworm|NAME="LMDE"\nID=linuxmint\nID_LIKE=debian\nVERSION_ID="6"\nVERSION_CODENAME=faye\nDEBIAN_CODENAME=bookworm
EOF
fi

begin 'other systems are reported unsupported before anything else'
while IFS='|' read -r name code release; do
  fixture "$name" "$(printf '%b' "$release")"
  plan "$root" || continue
  [ "$status" = 4 ] || fail "$name exited $status"
  expect "os code=$code"
  expect 'result code=unsupported-os ok=false exit=4 applied='
  [ "$(lines)" = 2 ] || fail "$name reported more than the os verdict"
done << 'EOF'
fedora|unsupported-distribution|NAME="Fedora Linux"\nID=fedora\nVERSION_ID=42
arch|unsupported-distribution|NAME="Arch Linux"\nID=arch
ubuntu-20.04|unsupported-release|ID=ubuntu\nID_LIKE=debian\nVERSION_CODENAME=focal\nUBUNTU_CODENAME=focal
debian-sid|unsupported-release|PRETTY_NAME="Debian GNU/Linux trixie/sid"\nID=debian
derivative-without-base|unsupported-release|ID=someos\nID_LIKE=ubuntu\nVERSION_CODENAME=noble
EOF

begin 'a missing os-release is reported'
root=$tmp/empty-root
mkdir -p "$root/var/lib/dpkg"
plan "$root" && expect 'os code=os-release-unreadable'

begin 'hostile os-release values never reach the JSON'
fixture hostile 'ID="ubuntu\",\"x\":\"y"
UBUNTU_CODENAME="noble\"}"
VERSION_CODENAME=noble'
plan "$root" && expect 'result code=unsupported-os ok=false exit=4 applied='

# --- packages ------------------------------------------------------------

if [ "$native_arch" = amd64 ]; then
  begin 'plan lists exactly the packages apply would install'
  fixture noble-partial "$UBUNTU_NOBLE"
  package "$root" git amd64
  package "$root" ca-certificates all
  package "$root" ripgrep amd64 'deinstall ok config-files'
  package "$root" libatomic1 i386
  plan "$root"
  for name in curl tar build-essential python3-dev libffi-dev ripgrep ffmpeg libatomic1; do
    expect "missing category=hermes-tools package=$name"
  done
  expect_not 'missing category=hermes-tools package=git'
  expect_not 'missing category=hermes-tools package=ca-certificates'
  expect 'missing category=secret-service package=gnome-keyring'
  expect 'missing category=secret-service package=libsecret-1-0'
  expect 'secret-provider code=absent'

  begin 'nothing is missing on a prepared system'
  fixture noble-ready "$UBUNTU_NOBLE"
  all_tools "$root"
  plan "$root"
  if grep -Eq '^missing category=(hermes-tools|secret-service) ' "$tmp/summary"; then
    fail 'reported missing packages on a prepared system'
  fi

  begin 'another Secret Service provider is kept'
  fixture kwallet "$UBUNTU_NOBLE"
  mkdir -p "$root/usr/share/dbus-1/services"
  printf '[D-BUS Service]\nName = org.freedesktop.secrets\nExec=/usr/bin/ksecretd\n' \
    > "$root/usr/share/dbus-1/services/org.kde.secretservicecompat.service"
  plan "$root"
  expect 'secret-provider code=present'
  expect 'missing category=secret-service package=libsecret-1-0'
  expect_not 'missing category=secret-service package=gnome-keyring'

  # --- docker ------------------------------------------------------------

  begin 'docker.io is only offered when no Docker exists'
  fixture no-docker "$UBUNTU_NOBLE"
  all_tools "$root"
  plan "$root"
  expect 'missing category=docker-install package=docker.io'
  if grep -q '^docker-footprint' "$tmp/summary"; then fail 'footprint on an empty root'; fi

  account_home=$(getent passwd "$(id -u)" | cut -d: -f6)
  while IFS='|' read -r code trace; do
    begin "an existing Docker ($code: $trace) blocks docker.io"
    fixture "docker-$code-$(printf '%s' "$trace" | tr -c 'a-z0-9' '-')" "$UBUNTU_NOBLE"
    all_tools "$root"
    case $trace in
      pkg:*)
        name=${trace#pkg:}
        state=${name#*=}
        name=${name%%=*}
        package "$root" "$name" amd64 "$state"
        ;;
      dir:*) mkdir -p "$root${trace#dir:}" ;;
      home:*)
        mkdir -p "$(dirname "$root$account_home${trace#home:}")"
        : > "$root$account_home${trace#home:}"
        ;;
      *)
        mkdir -p "$(dirname "$root$trace")"
        : > "$root$trace"
        ;;
    esac
    plan "$root" || continue
    expect "docker-footprint code=$code"
    expect_not 'missing category=docker-install package=docker.io'
  done << 'EOF'
package|pkg:docker-ce=install ok installed
package|pkg:docker.io=deinstall ok config-files
package|pkg:podman-docker=install ok installed
binary|/usr/local/bin/docker
binary|/usr/bin/dockerd
socket|/run/docker.sock
socket|/var/run/docker.sock
unit|/etc/systemd/system/docker.service
unit|/lib/systemd/system/docker.socket
data|dir:/var/lib/docker
config|dir:/etc/docker
snap|/snap/bin/docker
rootless|home:/.config/systemd/user/docker.service
rootless|home:/bin/dockerd
EOF
else
  echo "SKIP package and Docker fixtures: dpkg architecture is '$native_arch'"
fi

if [ "$failures" -gt 0 ]; then
  echo "helper: $failures failure(s) in $count test(s)"
  exit 1
fi
echo "helper: $count test(s) passed"
