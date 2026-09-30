#!/bin/sh
# Release metadata of the checked-out tree as key=value lines (for $GITHUB_OUTPUT).
#
# The only version source is the app pubspec: X.Y.Z+B or X.Y.Z-rc.N+B.
#   Debian     X.Y.Z-B                    X.Y.Z~rc.N-B
#   AppImage   Hermuse-Agent-X.Y.Z-linux-x86_64.AppImage (X.Y.Z-rc.N for an rc)
#   macOS      Hermuse-Agent-X.Y.Z-macos-arm64.dmg
#   Windows    Hermuse-Agent-X.Y.Z-windows-x64-Setup.exe
#   Tag        hermuse/vX.Y.Z             hermuse/vX.Y.Z-rc.N
# The upgrade fixture of the lifecycle smoke is a packaging fixture, never a
# release: X.Y.Z~rc.1-B for a final version, X.Y.Z~rc.N~fixture-B for an rc,
# both sorting below the release Debian version.
#
# usage: tool/release/release-metadata.sh [--tag <tag>] [--pubspec <path>]
# With --tag, exits 1 unless the tag names exactly the pubspec version.
set -eu

pubspec=apps/hermuse_app/pubspec.yaml
tag=
while [ $# -gt 0 ]; do
  case $1 in
    --tag | --pubspec)
      [ $# -ge 2 ] || { echo "release-metadata: $1 needs a value" >&2; exit 2; }
      if [ "$1" = --tag ]; then tag=$2; else pubspec=$2; fi
      shift 2
      ;;
    *) echo "release-metadata: unknown argument $1" >&2; exit 2 ;;
  esac
done

[ -f "$pubspec" ] || { echo "release-metadata: $pubspec not found" >&2; exit 1; }
raw=$(sed -n 's/^version:[[:space:]]*//p' "$pubspec" | tr -d "\"' \r")
if [ "$(printf '%s\n' "$raw" | grep -c .)" -ne 1 ] ||
  ! printf '%s\n' "$raw" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?\+[0-9]+$'; then
  echo "release-metadata: $pubspec version '$raw' is not X.Y.Z+B or X.Y.Z-rc.N+B" >&2
  exit 1
fi

app_version=${raw%%+*}
build=${raw#*+}
case $app_version in
  *-rc.*)
    base=${app_version%%-rc.*}
    rc=${app_version#*-rc.}
    deb_upstream="$base~rc.$rc"
    fixture_upstream="$base~rc.$rc~fixture"
    prerelease=true
    ;;
  *)
    deb_upstream=$app_version
    fixture_upstream="$app_version~rc.1"
    prerelease=false
    ;;
esac
expected_tag="hermuse/v$app_version"

if [ -n "$tag" ] && [ "$tag" != "$expected_tag" ]; then
  echo "release-metadata: tag '$tag' does not match the app version $raw (expected $expected_tag)" >&2
  exit 1
fi

cat <<EOF
pubspec_version=$raw
app_version=$app_version
build_number=$build
prerelease=$prerelease
tag=$expected_tag
deb_version=$deb_upstream-$build
deb_file=hermuse-agent_$deb_upstream-${build}_amd64.deb
appimage_file=Hermuse-Agent-$app_version-linux-x86_64.AppImage
sources_file=hermuse-agent-$app_version-corresponding-sources.tar.gz
fixture_deb_version=$fixture_upstream-$build
fixture_deb_file=hermuse-agent_$fixture_upstream-${build}_amd64.deb
dmg_file=Hermuse-Agent-$app_version-macos-arm64.dmg
windows_setup_file=Hermuse-Agent-$app_version-windows-x64-Setup.exe
EOF
