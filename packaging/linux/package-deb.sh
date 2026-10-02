#!/usr/bin/env bash
# Builds hermuse-agent_<version>-<build>_amd64.deb (Debian version <debver>,
# see hermuse_load_versions) from a complete release bundle
# (hermuse_app, data/, lib/ with lib/cliproxy, libexec/hermuse-linux-setup).
#
#   packaging/linux/package-deb.sh <bundle-dir> <out-dir>
#
# The bundle lands unchanged under /opt/hermuse-agent. Depends = the base list
# below merged with dpkg-shlibdeps over every ELF file of the bundle (private
# libraries resolved from the bundle's lib/). Run it in the builder image
# (Ubuntu 22.04) so the computed minimum versions match the glibc 2.35 floor.
#
# HERMUSE_DEB_VERSION_OVERRIDE=<debian version> is for packaging fixtures only
# (e.g. the 0.1.0~rc.1-1 upgrade fixture, in hermuse-agent_<debver>_amd64.deb);
# release builds refuse it.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"
# stdout carries only the path of the built package; tool output goes to stderr.
exec 3>&1 1>&2

[ "$#" -eq 2 ] || hermuse_die "usage: $0 <bundle-dir> <out-dir>"
[ -d "$1" ] || hermuse_die "no bundle directory $1"
bundle="$(cd "$1" && pwd)"
mkdir -p "$2"
out="$(cd "$2" && pwd)"

hermuse_require dpkg-deb dpkg-shlibdeps dpkg-query readelf ldd perl jq gzip \
  rsvg-convert desktop-file-validate appstreamcli
hermuse_load_versions
hermuse_source_date_epoch

# Base dependencies; dpkg-shlibdeps adds the exact library minimums. The
# Flutter engine loads EGL/GLES through libepoxy at run time (dlopen, invisible
# to dpkg-shlibdeps) and aborts without libGLESv2.so.2.
base_depends='libc6 (>= 2.35), libstdc++6, libgcc-s1, libgtk-3-0t64 | libgtk-3-0, libsecret-1-0, libegl1, libgl1, libgles2, ca-certificates, pkexec, dbus-user-session'
# Direct dependencies renamed by the 64-bit time_t transition (Ubuntu 24.04+,
# Debian 13): depend on either name with the same minimum version. The t64
# packages also Provide the old name, so both forms resolve on every target.
t64_renamed='libglib2.0-0 libgtk-3-0 libatk1.0-0'

deb_version="$HERMUSE_DEB_VERSION"
deb_file="$out/$HERMUSE_DEB_FILE"
if [ -n "${HERMUSE_DEB_VERSION_OVERRIDE:-}" ]; then
  [[ "$HERMUSE_DEB_VERSION_OVERRIDE" =~ ^[0-9][0-9A-Za-z.+~]*-[0-9A-Za-z.+~]+$ ]] ||
    hermuse_die "HERMUSE_DEB_VERSION_OVERRIDE '$HERMUSE_DEB_VERSION_OVERRIDE' is not a Debian version"
  deb_version="$HERMUSE_DEB_VERSION_OVERRIDE"
  deb_file="$out/${HERMUSE_DEB_PACKAGE}_${deb_version}_amd64.deb"
  hermuse_warn "PACKAGING FIXTURE: building $HERMUSE_DEB_PACKAGE $deb_version from the $HERMUSE_PUBSPEC_VERSION bundle; never publish it"
fi

check_bundle "$bundle"
check_elf_tree "$bundle" "$bundle/lib"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
root="$stage/debian/$HERMUSE_DEB_PACKAGE"
opt="$root/opt/$HERMUSE_DEB_PACKAGE"
doc="$root/usr/share/doc/$HERMUSE_DEB_PACKAGE"

hermuse_log "staging $HERMUSE_DEB_PACKAGE $deb_version"
install -d -m 0755 "$opt" "$root/usr/bin" "$root/usr/share/applications" \
  "$root/usr/share/metainfo" "$doc" "$root/DEBIAN"
cp -a "$bundle/." "$opt/"
# Content stays byte-identical; only modes are normalised for dpkg/lintian.
find "$opt" -type d -exec chmod 0755 {} +
find "$opt" -type f -exec chmod 0644 {} +
chmod 0755 "$opt/$HERMUSE_BINARY" "$opt/$HERMUSE_BUNDLE_CLIPROXY" "$opt/$HERMUSE_BUNDLE_HELPER"
ln -s "/opt/$HERMUSE_DEB_PACKAGE/$HERMUSE_BINARY" "$root/usr/bin/$HERMUSE_DEB_PACKAGE"

render_template "$HERMUSE_LINUX_DIR/hermuse-agent.desktop.in" \
  "$root/usr/share/applications/$HERMUSE_APP_ID.desktop" \
  "EXEC=/opt/$HERMUSE_DEB_PACKAGE/$HERMUSE_BINARY"
desktop-file-validate "$root/usr/share/applications/$HERMUSE_APP_ID.desktop"
render_icons "$root/usr/share/icons/hicolor"
render_template "$HERMUSE_LINUX_DIR/com.yellowstick.hermuse_app.metainfo.xml.in" \
  "$root/usr/share/metainfo/$HERMUSE_APP_ID.metainfo.xml" \
  "VERSION=$HERMUSE_APP_VERSION" "DATE=$(hermuse_release_date)"
appstreamcli validate --no-net "$root/usr/share/metainfo/$HERMUSE_APP_ID.metainfo.xml"

install -m 0644 "$HERMUSE_LINUX_DIR/deb/copyright" "$doc/copyright"
write_app_notices "$doc/notices" "$bundle"
{
  printf '%s (%s) stable; urgency=medium\n\n' "$HERMUSE_DEB_PACKAGE" "$deb_version"
  printf '  * Hermuse Agent %s for Linux.\n\n' "$HERMUSE_APP_VERSION"
  printf ' -- %s  %s\n' "$HERMUSE_MAINTAINER" "$(date -u -R -d "@$SOURCE_DATE_EPOCH")"
} | gzip -9n >"$doc/changelog.Debian.gz"
chmod 0644 "$doc/changelog.Debian.gz"

# --- Depends -----------------------------------------------------------------
hermuse_log "computing Depends with dpkg-shlibdeps"
cat >"$stage/debian/control" <<EOF
Source: $HERMUSE_DEB_PACKAGE
Maintainer: $HERMUSE_MAINTAINER

Package: $HERMUSE_DEB_PACKAGE
Architecture: amd64
Description: Hermuse Agent
EOF
mapfile -t elf_files < <(list_elf_files "$opt")
[ "${#elf_files[@]}" -gt 0 ] || hermuse_die "no ELF files in $opt"
shlibs="$(cd "$stage" && dpkg-shlibdeps -O -x"$HERMUSE_DEB_PACKAGE" -l"$opt/lib" "${elf_files[@]}")" ||
  hermuse_die "dpkg-shlibdeps failed"
shlibs="$(printf '%s\n' "$shlibs" | sed -n 's/^shlibs:Depends=//p')"
[ -n "$shlibs" ] || hermuse_die "dpkg-shlibdeps produced no dependencies"
hermuse_log "dpkg-shlibdeps: $shlibs"

depends="$(T64_RENAMED="$t64_renamed" perl -MDpkg::Deps -e '
  use strict; use warnings;
  my %t64 = map { $_ => 1 } split(" ", $ENV{T64_RENAMED});
  my $deps = deps_parse(join(", ", @ARGV)) or die "cannot parse dependencies\n";
  $deps->simplify_deps(Dpkg::Deps::KnownFacts->new());
  my @out;
  foreach my $dep ($deps->get_deps()) {
    if ($dep->isa("Dpkg::Deps::Simple") and $t64{$dep->{package}}) {
      my $rel = defined $dep->{relation} ? " ($dep->{relation} $dep->{version})" : "";
      push @out, "$dep->{package}t64$rel | $dep->{package}$rel";
    } else {
      push @out, $dep->output();
    }
  }
  my $merged = deps_parse(join(", ", @out)) or die "cannot parse merged dependencies\n";
  $merged->simplify_deps(Dpkg::Deps::KnownFacts->new());
  $merged->sort();
  print $merged->output(), "\n";
' "$shlibs" "$base_depends")" || hermuse_die "cannot merge dependencies"
hermuse_log "Depends: $depends"

installed_size="$(du -sk --apparent-size --exclude=DEBIAN "$root" | cut -f1)"
render_template "$HERMUSE_LINUX_DIR/deb/control.in" "$root/DEBIAN/control" \
  "VERSION=$deb_version" "INSTALLED_SIZE=$installed_size" "DEPENDS=$depends"
install -m 0755 "$HERMUSE_LINUX_DIR/deb/postinst" "$root/DEBIAN/postinst"
install -m 0755 "$HERMUSE_LINUX_DIR/deb/postrm" "$root/DEBIAN/postrm"
(cd "$root" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' | LC_ALL=C sort -z |
  xargs -0 md5sum) >"$root/DEBIAN/md5sums"
chmod 0644 "$root/DEBIAN/control" "$root/DEBIAN/md5sums"
find "$root" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

hermuse_log "building $(basename "$deb_file")"
rm -f "$deb_file"
dpkg-deb --root-owner-group -Zxz --build "$root" "$deb_file"

# The embedded bridge and helper must come out exactly as they went in.
check="$stage/check"
mkdir -p "$check"
dpkg-deb -x "$deb_file" "$check"
[ "$(dpkg-deb -f "$deb_file" Version)" = "$deb_version" ] || hermuse_die "wrong Version in $deb_file"
check_bundle "$check/opt/$HERMUSE_DEB_PACKAGE"
diff -r "$bundle" "$check/opt/$HERMUSE_DEB_PACKAGE" >/dev/null ||
  hermuse_die "/opt/$HERMUSE_DEB_PACKAGE differs from the bundle"
[ "$(readlink "$check/usr/bin/$HERMUSE_DEB_PACKAGE")" = "/opt/$HERMUSE_DEB_PACKAGE/$HERMUSE_BINARY" ] ||
  hermuse_die "/usr/bin/$HERMUSE_DEB_PACKAGE does not point at the app"
hermuse_log "wrote $deb_file"
printf '%s\n' "$deb_file" >&3