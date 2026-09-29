#!/usr/bin/env bash
# Assembles the release files of every platform into one directory: the
# packaged bytes of each OS job, one merged VERSION.json and one
# SHA256SUMS.txt over all of them. Nothing is rebuilt or re-signed.
#
# usage: tool/release/assemble-release.sh --commit SHA --linux DIR --macos DIR --windows DIR --out DIR
#
#   --linux    linux-dist + linux-sources: .deb, AppImage, sources tarball,
#              SHA256SUMS.txt, VERSION.json (packaging/linux/build-release.sh)
#   --macos    macos-dist: the .dmg, macos/SHA256SUMS.txt, macos/VERSION.json
#   --windows  windows-dist: the Setup.exe, windows/SHA256SUMS.txt, windows/VERSION.json
#
# Each directory must hold exactly the files named by release-metadata.sh for
# the checked-out pubspec, match its own SHA256SUMS.txt and name the same
# source commit (--commit, clean tree), app version, plugin and Hermes pin.
# Exits 1 on any mismatch.
set -euo pipefail

die() {
  echo "assemble-release: $*" >&2
  exit 1
}

commit='' linux='' macos='' windows='' out=''
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "$1 needs a value"
  case $1 in
    --commit) commit=$2 ;;
    --linux) linux=$2 ;;
    --macos) macos=$2 ;;
    --windows) windows=$2 ;;
    --out) out=$2 ;;
    *) die "unknown argument $1" ;;
  esac
  shift 2
done
[ -n "$commit" ] && [ -n "$linux" ] && [ -n "$macos" ] && [ -n "$windows" ] && [ -n "$out" ] ||
  die "--commit, --linux, --macos, --windows and --out are required"

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
meta=$("$here/release-metadata.sh")
field() { sed -n "s/^$1=//p" <<<"$meta"; }
app_version=$(field app_version)
deb=$(field deb_file)
appimage=$(field appimage_file)
sources=$(field sources_file)
dmg=$(field dmg_file)
setup=$(field windows_setup_file)

# Exactly the expected files, each matching the platform's own checksums.
files_are() { # <dir> <expected relative paths...>
  local dir=$1 expected actual
  shift
  expected=$(printf '%s\n' "$@" | LC_ALL=C sort)
  actual=$(cd "$dir" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
  [ "$actual" = "$expected" ] || die "$dir holds:
$actual
expected:
$expected"
}
files_are "$linux" "$deb" "$appimage" "$sources" SHA256SUMS.txt VERSION.json
files_are "$macos" "$dmg" macos/SHA256SUMS.txt macos/VERSION.json
files_are "$windows" "$setup" windows/SHA256SUMS.txt windows/VERSION.json
(cd "$linux" && sha256sum --quiet --strict -c SHA256SUMS.txt) || die "linux files do not match their SHA256SUMS.txt"
(cd "$macos" && sha256sum --quiet --strict -c macos/SHA256SUMS.txt) || die "macOS files do not match macos/SHA256SUMS.txt"
(cd "$windows" && sha256sum --quiet --strict -c windows/SHA256SUMS.txt) || die "Windows files do not match windows/SHA256SUMS.txt"
grep -q "  $dmg\$" "$macos/macos/SHA256SUMS.txt" || die "macos/SHA256SUMS.txt does not cover $dmg"
grep -q "  $setup\$" "$windows/windows/SHA256SUMS.txt" || die "windows/SHA256SUMS.txt does not cover $setup"

linux_json=$linux/VERSION.json
macos_json=$macos/macos/VERSION.json
windows_json=$windows/windows/VERSION.json

# One source, one version, one plugin, one Hermes pin for every platform; each
# fragment lists the artifact it ships with the bytes found here.
for json in "$linux_json" "$macos_json" "$windows_json"; do
  jq -e --arg commit "$commit" --arg version "$app_version" '
    .source.commit == $commit and .source.dirty == false and .app.version == $version' "$json" >/dev/null ||
    die "$json: not the clean commit $commit at version $app_version"
done
jq -e -n --slurpfile l "$linux_json" --slurpfile m "$macos_json" --slurpfile w "$windows_json" '
  [$l[0], $m[0], $w[0]] | (map(.plugin.version) | unique | length) == 1
    and (map(.hermes.commit) | unique | length) == 1
    and (map(.app.pubspec_version) | unique | length) == 1' >/dev/null ||
  die "the platforms disagree on the plugin version, the Hermes pin or the pubspec version"
jq -e '.os == "macos" and .arch == "arm64"' "$macos_json" >/dev/null || die "$macos_json is not the macOS arm64 fragment"
jq -e '.os == "windows" and .arch == "x64"' "$windows_json" >/dev/null || die "$windows_json is not the Windows x64 fragment"
check_artifacts() { # <json> <dir> <file...>: the fragment lists exactly these files with their bytes
  local json=$1 dir=$2 file listed
  shift 2
  listed=$(jq -r '.artifacts[].name' "$json" | LC_ALL=C sort)
  [ "$listed" = "$(printf '%s\n' "$@" | LC_ALL=C sort)" ] || die "$json lists artifacts: $listed"
  for file; do
    jq -e --arg n "$file" --arg sha "$(sha256sum "$dir/$file" | cut -d' ' -f1)" \
      --argjson size "$(stat -c %s "$dir/$file")" \
      '[.artifacts[] | select(.name == $n and .sha256 == $sha and .size == $size)] | length == 1' "$json" >/dev/null ||
      die "$json: $file has other bytes"
  done
}
check_artifacts "$linux_json" "$linux" "$deb" "$appimage" "$sources"
check_artifacts "$macos_json" "$macos" "$dmg"
check_artifacts "$windows_json" "$windows" "$setup"

mkdir -p "$out"
[ -z "$(ls -A "$out")" ] || die "$out is not empty"
cp -p "$linux/$deb" "$linux/$appimage" "$linux/$sources" "$macos/$dmg" "$windows/$setup" "$out/"
jq -n --slurpfile l "$linux_json" --slurpfile m "$macos_json" --slurpfile w "$windows_json" '
  $l[0] as $linux | {
    schema: 2,
    app: {name: $linux.app.name, version: $linux.app.version, build: $linux.app.build,
          pubspec_version: $linux.app.pubspec_version},
    source: {commit: $linux.source.commit, dirty: false},
    plugin: $linux.plugin,
    hermes: $linux.hermes,
    platforms: {linux: $linux, macos: $m[0], windows: $w[0]},
    artifacts: ($linux.artifacts + $m[0].artifacts + $w[0].artifacts)
  }' >"$out/VERSION.json"
(cd "$out" && sha256sum -- "$deb" "$appimage" "$sources" "$dmg" "$setup" VERSION.json >SHA256SUMS.txt)
echo "release files in $out:" >&2
(cd "$out" && ls -l && cat SHA256SUMS.txt) >&2
