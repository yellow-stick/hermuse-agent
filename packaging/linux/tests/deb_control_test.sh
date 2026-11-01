#!/bin/sh
# The .deb control template: package fields the app relies on at run time.
set -u
here=$(cd "$(dirname "$0")" && pwd)
control=$here/../deb/control.in
failures=0

expect_line() {
  if grep -qx "$1" "$control"; then
    echo "ok   $2"
  else
    echo "FAIL $2: no line '$1' in deb/control.in"
    failures=$((failures + 1))
  fi
}

expect_line 'Depends: @DEPENDS@' 'Depends filled from the computed list'
# Without a color emoji font, Flutter draws emoji in chat and Feed as boxes.
expect_line 'Recommends: fonts-noto-color-emoji' 'emoji font recommended'

[ "$failures" -eq 0 ]
