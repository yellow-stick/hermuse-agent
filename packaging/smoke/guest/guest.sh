#!/usr/bin/env bash
# Host side of the release smoke: pinned cloud image -> ephemeral QEMU guest on a
# fresh qcow2 overlay -> root SSH with per-run keys -> destroyed after the run.
# CI runners only (the plan forbids a VM lab on a workstation): locally, run
# `up --dry-run`, which renders the seed and prints the QEMU command without
# booting anything.
#
#   guest.sh fetch <guest> <cache-dir>                     download + verify the pinned image
#   guest.sh up <guest> <cache-dir> <run-dir> [--dry-run]  seed, overlay, boot, wait for cloud-init
#   guest.sh ssh <run-dir> [command...]                    root command in the guest
#   guest.sh push <run-dir> <local-path> <guest-dir>       copy into the guest (scp -r)
#   guest.sh pull <run-dir> <guest-path> <local-dir>       copy out of the guest (scp -r)
#   guest.sh exec <run-dir> <timeout-s> <command...>       run as a transient root unit that
#                                                          survives SSH drops; streams its journal,
#                                                          returns its exit status (124 = timeout)
#   guest.sh down <run-dir>                                stop QEMU (the overlay dies with the run dir)
#
# <guest> is a key of tool/release/guest-images.lock.json `.guests`.
# Resources: HERMUSE_GUEST_CPUS / HERMUSE_GUEST_MEMORY_MB / HERMUSE_GUEST_DISK
# override the defaults (all host CPUs, host RAM - 3 GiB clamped to 4-10 GiB, 48G).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../../.." && pwd)
lock=${HERMUSE_GUEST_LOCK:-$repo/tool/release/guest-images.lock.json}

die() {
  echo "guest.sh: $*" >&2
  exit 1
}

need() {
  local tool
  for tool; do
    command -v "$tool" >/dev/null 2>&1 || die "missing host tool: $tool"
  done
}

lock_field() { # <guest> <field>
  jq -er --arg g "$1" --arg f "$2" '.guests[$g][$f]' "$lock" ||
    die "no .guests[\"$1\"].$2 in $lock"
}

sha256_ok() { # <file> <sha256>
  [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$2" ]
}

cmd_fetch() {
  [ $# -eq 2 ] || die "usage: fetch <guest> <cache-dir>"
  need curl jq sha256sum
  local guest=$1 cache=$2 url sha image
  url=$(lock_field "$guest" url)
  sha=$(lock_field "$guest" sha256)
  mkdir -p "$cache"
  image="$cache/$guest.qcow2"
  if [ -f "$image" ] && sha256_ok "$image" "$sha"; then
    echo "guest.sh: $guest image verified ($sha)"
    return
  fi
  rm -f "$image" "$image.part"
  curl -fL --proto '=https' --tlsv1.2 --retry 5 --retry-delay 10 -o "$image.part" "$url"
  if ! sha256_ok "$image.part" "$sha"; then
    rm -f "$image.part"
    die "$url does not match the pinned sha256 $sha"
  fi
  mv "$image.part" "$image"
  echo "guest.sh: $guest image downloaded and verified ($sha)"
}

# --- run-dir state --------------------------------------------------------

port_of() { cat "$1/ssh-port"; }

ssh_opts() { # <run-dir>
  printf '%s\n' -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
    -o "UserKnownHostsFile=$1/known_hosts" -o LogLevel=ERROR -o ConnectTimeout=10 \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=8 -i "$1/harness_key"
}

guest_ssh() { # <run-dir> <command...>
  local run=$1
  shift
  local -a opts
  mapfile -t opts < <(ssh_opts "$run")
  ssh "${opts[@]}" -p "$(port_of "$run")" root@127.0.0.1 "$@"
}

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

render_user_data() { # <template> <run-dir> <tester-password-hash>
  local template=$1 run=$2 hash=$3
  awk -v host="hermuse-smoke" \
    -v host_pub="$(cut -d' ' -f1,2 "$run/host_key.pub")" \
    -v harness_pub="$(cut -d' ' -f1,2 "$run/harness_key.pub")" \
    -v hash="$hash" -v keyfile="$run/host_key" '
    /@HOST_KEY_PRIVATE@/ {
      indent = $0
      sub(/@HOST_KEY_PRIVATE@.*/, "", indent)
      while ((getline line < keyfile) > 0) print indent line
      close(keyfile)
      next
    }
    {
      gsub(/@HOSTNAME@/, host)
      gsub(/@HOST_KEY_PUBLIC@/, host_pub)
      gsub(/@HARNESS_PUBKEY@/, harness_pub)
      # The hash contains "$" and "/": index-based replacement, no regex.
      i = index($0, "@TESTER_PASSWORD_HASH@")
      if (i > 0) $0 = substr($0, 1, i - 1) "\"" hash "\"" substr($0, i + length("@TESTER_PASSWORD_HASH@"))
      print
    }' "$template"
}

cmd_up() {
  [ $# -ge 3 ] || die "usage: up <guest> <cache-dir> <run-dir> [--dry-run]"
  local guest=$1 cache=$2 run=$3 dry=${4:-}
  [ -z "$dry" ] || [ "$dry" = --dry-run ] || die "unknown option $dry"
  need jq ssh-keygen openssl genisoimage qemu-img python3 awk
  [ -n "$dry" ] || need qemu-system-x86_64 ssh
  local base="$cache/$guest.qcow2" sha
  sha=$(lock_field "$guest" sha256)
  if [ -f "$base" ]; then
    sha256_ok "$base" "$sha" || die "$base does not match the pinned sha256 (run fetch)"
  elif [ -z "$dry" ]; then
    die "$base missing (run: guest.sh fetch $guest $cache)"
  fi
  [ ! -e "$run" ] || [ -z "$(ls -A "$run")" ] || die "$run is not empty: one fresh run dir per guest"
  mkdir -p "$run"
  chmod 700 "$run"
  echo "$guest" >"$run/guest"

  ssh-keygen -q -t ed25519 -N '' -C hermuse-smoke-harness -f "$run/harness_key"
  ssh-keygen -q -t ed25519 -N '' -C hermuse-smoke-guest-host -f "$run/host_key"
  # Synthetic secrets of this run only: the tester login/polkit password and
  # the password the harness gives the new keyring when gnome-keyring asks.
  (umask 077 && od -An -N18 -tx1 /dev/urandom | tr -d ' \n' >"$run/tester-password")
  (umask 077 && od -An -N18 -tx1 /dev/urandom | tr -d ' \n' >"$run/keyring-password")
  local hash
  hash=$(openssl passwd -6 -stdin <"$run/tester-password")
  (umask 077 && render_user_data "$here/user-data.yaml.in" "$run" "$hash" >"$run/user-data")
  grep -q '@[A-Z_]*@' "$run/user-data" && die "unrendered placeholder in user-data"
  printf 'instance-id: hermuse-smoke-%s-%s\nlocal-hostname: hermuse-smoke\n' \
    "$guest" "$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')" >"$run/meta-data"
  genisoimage -quiet -output "$run/seed.iso" -volid cidata -joliet -rock \
    "$run/user-data" "$run/meta-data"

  local port cpus mem disk accel cpu_model
  port=$(free_port)
  echo "$port" >"$run/ssh-port"
  printf '[127.0.0.1]:%s %s\n' "$port" "$(cut -d' ' -f1,2 "$run/host_key.pub")" >"$run/known_hosts"
  cpus=${HERMUSE_GUEST_CPUS:-$(nproc)}
  mem=${HERMUSE_GUEST_MEMORY_MB:-$(awk '/^MemTotal:/ { m = int($2 / 1024) - 3072; if (m > 10240) m = 10240; if (m < 4096) m = 4096; print m }' /proc/meminfo)}
  disk=${HERMUSE_GUEST_DISK:-48G}
  if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    accel=kvm
    cpu_model=host
  else
    accel=tcg,thread=multi
    cpu_model=max
  fi
  echo "${accel%%,*}" >"$run/accel"

  local -a qemu=(
    qemu-system-x86_64 -name "hermuse-smoke-$guest" -machine q35 -accel "$accel"
    -cpu "$cpu_model" -smp "$cpus" -m "$mem"
    -drive "file=$run/overlay.qcow2,if=virtio,format=qcow2,cache=unsafe,discard=unmap"
    -drive "file=$run/seed.iso,media=cdrom,readonly=on"
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$port-:22" -device "virtio-net-pci,netdev=net0"
    -device virtio-rng-pci -vga std -display none
    -serial "file:$run/console.log" -pidfile "$run/qemu.pid" -daemonize
  )
  printf '%q ' "${qemu[@]}" >"$run/qemu-command"
  echo >>"$run/qemu-command"

  if [ -n "$dry" ]; then
    if [ -f "$base" ]; then
      qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath "$base")" "$run/overlay.qcow2" "$disk"
    fi
    echo "guest.sh: dry run for $guest (accel ${accel%%,*}, $cpus CPUs, $mem MiB, disk $disk)"
    echo "guest.sh: seed $run/seed.iso, ssh port $port"
    cat "$run/qemu-command"
    return
  fi

  qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath "$base")" "$run/overlay.qcow2" "$disk"
  "${qemu[@]}"
  echo "guest.sh: $guest booting (accel ${accel%%,*}, $cpus CPUs, $mem MiB)"

  local deadline=$((SECONDS + ${HERMUSE_GUEST_BOOT_TIMEOUT:-1800}))
  until guest_ssh "$run" true 2>/dev/null; do
    [ "$SECONDS" -lt "$deadline" ] || {
      tail -n 50 "$run/console.log" >&2 || true
      die "no SSH from $guest"
    }
    kill -0 "$(cat "$run/qemu.pid")" 2>/dev/null || die "QEMU exited during boot"
    sleep 10
  done
  # Exit 2 is "done with recoverable errors" (e.g. deprecation warnings);
  # linux.sh verifies the test base itself before any scenario.
  local rc=0
  guest_ssh "$run" 'cloud-init status --wait --long' || rc=$?
  case $rc in
    0 | 2) ;;
    *) die "cloud-init failed in $guest (exit $rc)" ;;
  esac
  echo "guest.sh: $guest ready on port $port"
}

cmd_ssh() {
  [ $# -ge 1 ] || die "usage: ssh <run-dir> [command...]"
  guest_ssh "$@"
}

cmd_push() {
  [ $# -eq 3 ] || die "usage: push <run-dir> <local-path> <guest-dir>"
  local run=$1
  local -a opts
  mapfile -t opts < <(ssh_opts "$run")
  guest_ssh "$run" "mkdir -p '$3'"
  scp -q -r "${opts[@]}" -P "$(port_of "$run")" "$2" "root@127.0.0.1:$3/"
}

cmd_pull() {
  [ $# -eq 3 ] || die "usage: pull <run-dir> <guest-path> <local-dir>"
  local run=$1
  local -a opts
  mapfile -t opts < <(ssh_opts "$run")
  mkdir -p "$3"
  scp -q -r "${opts[@]}" -P "$(port_of "$run")" "root@127.0.0.1:$2" "$3/"
}

cmd_exec() {
  [ $# -ge 3 ] || die "usage: exec <run-dir> <timeout-s> <command...>"
  local run=$1 timeout=$2
  shift 2
  local unit
  unit="hermuse-smoke-$(date +%s)"
  local quoted
  quoted=$(printf '%q ' "$@")
  guest_ssh "$run" "systemd-run --quiet --unit=$unit --remain-after-exit --setenv=LANG=C.UTF-8 -- $quoted"
  local deadline=$((SECONDS + timeout)) state=""
  while :; do
    guest_ssh "$run" "journalctl -u $unit -o cat --no-pager --cursor-file=/run/$unit.cursor" || true
    state=$(guest_ssh "$run" "systemctl show -p ActiveState --value $unit" || echo unknown)
    case $state in
      active | activating | reloading | deactivating) ;;
      *) break ;;
    esac
    # Remain-after-exit keeps a finished success unit "active (exited)".
    if [ "$(guest_ssh "$run" "systemctl show -p SubState --value $unit" || true)" = exited ]; then
      break
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      guest_ssh "$run" "systemctl kill $unit" || true
      echo "guest.sh: $* timed out after ${timeout}s" >&2
      return 124
    fi
    sleep 15
  done
  guest_ssh "$run" "journalctl -u $unit -o cat --no-pager --cursor-file=/run/$unit.cursor" || true
  local status
  status=$(guest_ssh "$run" "systemctl show -p ExecMainStatus --value $unit")
  return "${status:-1}"
}

cmd_down() {
  [ $# -eq 1 ] || die "usage: down <run-dir>"
  local run=$1 pid
  [ -f "$run/qemu.pid" ] || return 0
  pid=$(cat "$run/qemu.pid")
  if kill -0 "$pid" 2>/dev/null; then
    guest_ssh "$run" 'systemctl poweroff' 2>/dev/null || true
    for _ in $(seq 1 30); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 2
    done
    kill "$pid" 2>/dev/null || true
  fi
  rm -f "$run/overlay.qcow2"
  echo "guest.sh: guest stopped, overlay removed"
}

main() {
  [ $# -ge 1 ] || die "usage: guest.sh fetch|up|ssh|push|pull|exec|down ..."
  local command=$1
  shift
  case $command in
    fetch) cmd_fetch "$@" ;;
    up) cmd_up "$@" ;;
    ssh) cmd_ssh "$@" ;;
    push) cmd_push "$@" ;;
    pull) cmd_pull "$@" ;;
    exec) cmd_exec "$@" ;;
    down) cmd_down "$@" ;;
    *) die "unknown command $command" ;;
  esac
}

main "$@"
