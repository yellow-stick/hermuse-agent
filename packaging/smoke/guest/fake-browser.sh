#!/bin/sh
# Default web browser of the smoke tester (x-scheme-handler/http[s]). Records
# the URL the app asked to open and the environment it was launched with, so
# the scenario can prove the host browser gets the host environment (no
# AppImage runtime or bundled GTK variables). Never contacts the URL.
out=/run/hermuse-smoke/out/browser
mkdir -p "$out"
record="$out/$(date +%s%N).env"
{
  printf 'url=%s\n' "${1:-}"
  env | sort
} >"$record.tmp"
mv "$record.tmp" "$record"
