# Hermuse computer: Chromium (CDP relayed to 9223 by cdp_relay) on an XFCE
# desktop, streamed as JPEG frames over WebSocket by screend (8765; X grab +
# Pillow JPEG, no ffmpeg). Published multi-arch as
# ghcr.io/yellow-stick/hermuse-computer:<plugin version> by
# .github/workflows/computer-image.yml; the Hermuse plugin pulls it, or builds
# this directory locally when the pull fails.
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        chromium xvfb x11-utils xfce4 xfce4-terminal dbus-x11 xdotool \
        python3 python3-aiohttp python3-xlib python3-pil \
        fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*

# --no-sandbox is intentional (the container is the isolation boundary): hide
# Chromium's warning bar about it, which would sit on every frame.
RUN useradd -m -u 1000 hermuse \
    && mkdir -p /etc/chromium/policies/managed \
    && printf '{"CommandLineFlagSecurityWarningsEnabled": false}\n' \
        > /etc/chromium/policies/managed/hermuse.json

COPY entrypoint.sh cdp_relay.py screend.py /opt/hermuse/
# The build context may come from a copy that dropped the exec bit (the
# desktop installer writes plugin files as plain bytes).
RUN chmod 0755 /opt/hermuse/entrypoint.sh \
    && chmod 0644 /opt/hermuse/cdp_relay.py /opt/hermuse/screend.py

USER hermuse
WORKDIR /home/hermuse
EXPOSE 9223 8765
ENTRYPOINT ["/opt/hermuse/entrypoint.sh"]
