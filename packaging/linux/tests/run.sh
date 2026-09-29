#!/bin/sh
# Runs every packaging/linux/tests/*_test.sh; exit 0 only when all pass.
# Needs POSIX sh, coreutils and python3. Never run as root: these tests must
# not be able to change the machine they run on.
set -u
here=$(cd "$(dirname "$0")" && pwd)
if [ "$(id -u)" = 0 ]; then
  echo "packaging tests refuse to run as root" >&2
  exit 1
fi
status=0
for suite in "$here"/*_test.sh; do
  [ -f "$suite" ] || continue
  echo "== ${suite##*/}"
  sh "$suite" || status=1
done
exit "$status"
