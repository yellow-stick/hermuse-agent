#!/usr/bin/env bash
# Orca setup hook: make a fresh worktree ready for Flutter, Jaspr and plugin work.
#
# Nothing is shared with the main checkout: .dart_tool/package_config.json holds
# absolute paths into its own checkout and build_runner caches are per tree, so
# each worktree resolves on its own. The global pub cache keeps that fast.
# Generated sources (contract, drift, riverpod, Jaspr options) are committed, so
# no build_runner pass is needed here.
set -euo pipefail

ROOT="${ORCA_WORKTREE_PATH:-$PWD}"
cd "$ROOT"

for tool in flutter dart; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "setup: $tool is not on PATH" >&2
    exit 1
  fi
done

# One resolution covers every app and package of the pub workspace; the
# committed lockfile is the contract, so a drifted resolution fails setup.
flutter pub get --enforce-lockfile

missing=()
command -v melos >/dev/null 2>&1 || missing+=("melos (dart pub global activate melos)")
command -v jaspr >/dev/null 2>&1 || missing+=("jaspr (dart pub global activate jaspr_cli)")
hermes_python="${HERMES_HOME:-$HOME/.hermes}/hermes-agent/venv/bin/python"
[ -x "$hermes_python" ] || missing+=("Hermes venv for plugin tests ($hermes_python)")
for item in "${missing[@]}"; do
  echo "setup: missing $item" >&2
done

echo "setup: worktree ready at $ROOT"
echo "setup: web dev server: tool/serve-web.sh (ports unique to this worktree)"
