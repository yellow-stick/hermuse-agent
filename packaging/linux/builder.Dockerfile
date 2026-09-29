# Hermuse Agent Linux release builder: Ubuntu 22.04 amd64 (glibc 2.35 floor),
# Flutter SDK and Melos from tool/release/toolchain.lock.json, no JDK.
#
#   docker build -f packaging/linux/builder.Dockerfile -t hermuse-linux-builder:<tag> tool/release
#   docker run --rm -v "$PWD:/src" -w /src hermuse-linux-builder:<tag> packaging/linux/build-release.sh
#
# The build context is tool/release: only toolchain.lock.json is read. Keep the
# FROM digest equal to .builder.digest in that lock (build-release.sh checks).
FROM docker.io/library/ubuntu:22.04@sha256:b8b6ee6aa931ecd9d0d952abc34dc0e5f7c6a30c6bb71b079fe399fde0329c02

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

COPY toolchain.lock.json /opt/hermuse-builder/toolchain.lock.json

# TLS trust comes from the image's own archive; every other package, binary or
# source, comes from the Ubuntu snapshot pinned in the lock. The package lists
# stay in the image so build-release.sh can `apt-get source` exactly the
# library versions bundled into the AppImage.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && lock=/opt/hermuse-builder/toolchain.lock.json \
 && snapshot="$(sed -n 's/.*"apt_snapshot": *"\([0-9TZ]*\)".*/\1/p' "$lock")" \
 && base="$(sed -n 's/.*"apt_snapshot_url": *"\(https:[^"]*\)".*/\1/p' "$lock")/$snapshot" \
 && test -n "$snapshot" \
 && rm -f /etc/apt/sources.list.d/* \
 && for kind in deb deb-src; do \
      for suite in jammy jammy-updates jammy-security; do \
        echo "$kind [check-valid-until=no] $base $suite main restricted universe multiverse"; \
      done; \
    done >/etc/apt/sources.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      appstream \
      binutils \
      clang \
      cmake \
      curl \
      desktop-file-utils \
      dpkg-dev \
      file \
      git \
      jq \
      libgirepository1.0-dev \
      libgtk-3-dev \
      liblzma-dev \
      librsvg2-bin \
      librsvg2-dev \
      libsecret-1-dev \
      libstdc++-12-dev \
      lintian \
      ninja-build \
      pkg-config \
      unzip \
      xz-utils \
      zip \
 && if dpkg-query -W -f '${Package}\n' | grep -Eq '(jdk|jre)'; then \
      echo 'a JDK/JRE was pulled into the builder' >&2; exit 1; \
    fi \
 && ! command -v java \
 && ! command -v javac \
 && apt-get clean

# Flutter SDK from the pinned release tarball, verified before extraction.
RUN lock=/opt/hermuse-builder/toolchain.lock.json \
 && url="$(jq -er .flutter.url "$lock")" \
 && sha="$(jq -er .flutter.sha256 "$lock")" \
 && curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o /tmp/flutter.tar.xz "$url" \
 && echo "$sha  /tmp/flutter.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz \
 && git config --system --add safe.directory '*' \
 && test "$(git -C /opt/flutter rev-parse HEAD)" = "$(jq -er .flutter.commit "$lock")"

ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/root/.pub-cache/bin:$PATH

RUN lock=/opt/hermuse-builder/toolchain.lock.json \
 && flutter config --no-analytics --no-cli-animations --enable-linux-desktop \
 && dart --disable-analytics \
 && flutter precache --linux \
 && test "$(flutter --version --machine | jq -r .frameworkVersion)" = "$(jq -er .flutter.version "$lock")" \
 && dart pub global activate melos "$(jq -er .melos.version "$lock")" \
 && test "$(melos --version)" = "$(jq -er .melos.version "$lock")"