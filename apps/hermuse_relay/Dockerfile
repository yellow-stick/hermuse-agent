# Hermuse web app + relay: ghcr.io/yellow-stick/hermuse-web:<plugin version>,
# published by .github/workflows/web-image.yml and run by the desktop app's SSH
# installer (`web` step) behind Caddy.
#
# Only COPYs prebuilt artifacts (no RUN), so the multi-arch build needs no
# emulation. Build context:
#   web/           `jaspr build` output of apps/hermuse_web
#   relay-amd64/   `dart build cli` bundle (bin/server, lib/libsqlite3.so), x64
#   relay-arm64/   same, arm64
FROM debian:bookworm-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251

ARG TARGETARCH

COPY relay-${TARGETARCH}/ /opt/hermuse-relay/
COPY web/ /opt/hermuse-relay/web/

# The relay reaches Hermes dashboards over HTTPS; the slim base has no CA
# bundle, so take Debian's from distroless (a COPY, not an apt RUN).
COPY --from=gcr.io/distroless/static-debian12@sha256:d75cdd72874d4790092fcb1b058493ecf6bb5bf2b2b897045b00ff01d91843f2 \
    /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

ENV HERMUSE_RELAY_STATIC_DIR=/opt/hermuse-relay/web \
    HERMUSE_RELAY_DB=/tmp/hermuse_relay.db \
    HERMUSE_RELAY_PORT=8787

EXPOSE 8787
USER 65532:65532
ENTRYPOINT ["/opt/hermuse-relay/bin/server"]
