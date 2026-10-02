#!/usr/bin/env bash
# Orca archive hook: stop processes rooted in a worktree before Orca removes its
# files — `jaspr serve` (build_runner, webdev, proxy), `flutter run` apps built
# under build/, test runners, language servers started inside the tree.
set -uo pipefail

ROOT="${ORCA_WORKTREE_PATH:-$PWD}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd -P)" || ROOT=""
case "$ROOT" in
  "" | "/" | "${HOME:-/nonexistent}")
    echo "archive: refusing unsafe worktree path '${ORCA_WORKTREE_PATH:-$PWD}'" >&2
    exit 1
    ;;
esac
if [ ! -d /proc ]; then
  echo "archive: /proc unavailable; skipping process sweep of $ROOT" >&2
  exit 0
fi

# Keep the sweep's own subshells, find, sed and sort outside the worktree.
# Otherwise each scan discovers fresh helpers and reports them as survivors.
cd / || exit 1

# Never kill this script or the Orca shell that runs it.
self_chain=" "
pid=$$
while [ "${pid:-0}" -gt 1 ]; do
  self_chain="$self_chain$pid "
  pid="$(sed -n 's/^PPid:[[:space:]]*//p' "/proc/$pid/status" 2>/dev/null)"
done

# Live pids whose cwd or executable sits inside the worktree.
rooted_pids() {
  find /proc -mindepth 2 -maxdepth 2 \( -name cwd -o -name exe \) -printf '%h\t%l\n' 2>/dev/null |
    while IFS=$'\t' read -r dir target; do
      pid="${dir#/proc/}"
      case "$pid" in "" | *[!0-9]*) continue ;; esac
      case "$self_chain" in *" $pid "*) continue ;; esac
      case "$target" in
        "$ROOT" | "$ROOT"/* | "$ROOT (deleted)" | "$ROOT"/*" (deleted)") ;;
        *) continue ;;
      esac
      state="$(sed -n 's/^.*) \([A-Za-z]\).*/\1/p' "/proc/$pid/stat" 2>/dev/null)"
      case "$state" in Z* | X* | x*) continue ;; esac
      echo "$pid"
    done | sort -un
}

mapfile -t victims < <(rooted_pids)
if [ "${#victims[@]}" -eq 0 ]; then
  echo "archive: no process rooted in $ROOT"
  exit 0
fi

echo "archive: stopping ${#victims[@]} process(es) rooted in $ROOT"
kill -TERM "${victims[@]}" 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.5
  mapfile -t victims < <(rooted_pids)
  [ "${#victims[@]}" -eq 0 ] && exit 0
done

kill -KILL "${victims[@]}" 2>/dev/null
sleep 0.5
mapfile -t victims < <(rooted_pids)
if [ "${#victims[@]}" -gt 0 ]; then
  echo "archive: ${#victims[@]} process(es) survived SIGKILL:" >&2
  printf '  pid %s\n' "${victims[@]}" >&2
  exit 1
fi
