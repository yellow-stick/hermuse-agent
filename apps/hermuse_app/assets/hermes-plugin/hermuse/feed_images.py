"""Feed post images: the share image (``og:image``) of the post's source page,
or the image the agent named, copied next to the post.

Stdlib only, shared by the agent tool and the dashboard routes. The URLs come
from the model, so every fetch is guarded: http(s) only, every hop (redirects
included) must resolve to public addresses only and is connected to the
address that was checked (no second DNS lookup), a time budget, size caps and
image bytes recognised by their signature (no SVG). Any failure means "no
image", never an error for the post.
"""

from __future__ import annotations

import http.client
import ipaddress
import logging
import socket
import ssl
import time
import urllib.parse
from html.parser import HTMLParser
from typing import Callable, Optional

log = logging.getLogger(__name__)

TIMEOUT_S = 5.0
BUDGET_S = 10.0
MAX_REDIRECTS = 3
MAX_PAGE_BYTES = 512 * 1024
MAX_IMAGE_BYTES = 2 * 1024 * 1024
MAX_SOURCES = 2
USER_AGENT = "Mozilla/5.0 (compatible; HermuseFeed/1.0; link preview)"

# Share image tags, most specific first.
_META_KEYS = ("og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src")


class FetchRefused(Exception):
    """A URL, address or response this module will not use."""


def sniff_image(data: bytes) -> Optional[str]:
    """File extension for JPEG, PNG, GIF or WebP bytes; None otherwise."""
    if data.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return ".gif"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return ".webp"
    return None


def public_address(host: str, port: int) -> str:
    """The address to connect to for *host*; refuses unless every resolved
    address is public (a mix could be swapped between lookups)."""
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except OSError as exc:
        raise FetchRefused(f"cannot resolve {host}") from exc
    addresses = []
    for info in infos:
        address = ipaddress.ip_address(info[4][0].split("%", 1)[0])
        if not address.is_global or address.is_multicast:
            raise FetchRefused(f"{host} resolves to a non-public address")
        addresses.append(str(address))
    if not addresses:
        raise FetchRefused(f"cannot resolve {host}")
    return addresses[0]


def _connection(scheme: str, host: str, port: int, deadline: float) -> http.client.HTTPConnection:
    remaining = max(0.5, min(TIMEOUT_S, deadline - time.monotonic()))
    address = public_address(host, port)
    sock = socket.create_connection((address, port), timeout=remaining)
    if scheme == "https":
        try:
            sock = ssl.create_default_context().wrap_socket(sock, server_hostname=host)
        except (OSError, ssl.SSLError):
            sock.close()
            raise
        conn: http.client.HTTPConnection = http.client.HTTPSConnection(host, port, timeout=remaining)
    else:
        conn = http.client.HTTPConnection(host, port, timeout=remaining)
    conn.sock = sock  # connected to the checked address; Host/SNI stay the name
    return conn


def fetch(url: str, *, accept: str, limit: int, deadline: float) -> tuple[str, str, bytes]:
    """GET *url* following up to MAX_REDIRECTS guarded hops.

    Returns ``(final_url, content_type, body)``; raises FetchRefused or
    OSError. A body over *limit* bytes is refused, not truncated."""
    for _ in range(MAX_REDIRECTS + 1):
        if time.monotonic() > deadline:
            raise FetchRefused("time budget spent")
        parts = urllib.parse.urlsplit(url)
        if parts.scheme not in ("http", "https") or not parts.hostname:
            raise FetchRefused(f"not an http(s) URL: {url[:80]}")
        port = parts.port or (443 if parts.scheme == "https" else 80)
        conn = _connection(parts.scheme, parts.hostname, port, deadline)
        try:
            path = urllib.parse.urlunsplit(("", "", parts.path or "/", parts.query, ""))
            conn.request("GET", path, headers={
                "User-Agent": USER_AGENT, "Accept": accept, "Accept-Encoding": "identity"})
            response = conn.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader("Location")
                if not location:
                    raise FetchRefused("redirect without Location")
                url = urllib.parse.urljoin(url, location)
                continue
            if response.status != 200:
                raise FetchRefused(f"HTTP {response.status}")
            body = response.read(limit + 1)
            if len(body) > limit:
                raise FetchRefused("response too large")
            return url, (response.getheader("Content-Type") or "").lower(), body
        finally:
            conn.close()
    raise FetchRefused("too many redirects")


class _ShareImageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.found: dict[str, str] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, Optional[str]]]) -> None:
        values = {k.lower(): (v or "").strip() for k, v in attrs}
        if tag == "meta":
            key = (values.get("property") or values.get("name") or "").lower()
            if key in _META_KEYS and values.get("content"):
                self.found.setdefault(key, values["content"])
        elif tag == "link" and "image_src" in values.get("rel", "").lower().split() and values.get("href"):
            self.found.setdefault("image_src", values["href"])


def share_image_url(html: str, page_url: str) -> Optional[str]:
    """Absolute URL of the page's share image, or None."""
    parser = _ShareImageParser()
    try:
        parser.feed(html)
        parser.close()
    except Exception:  # noqa: BLE001 — malformed markup just has no image
        pass
    for key in (*_META_KEYS, "image_src"):
        if value := parser.found.get(key):
            absolute = urllib.parse.urljoin(page_url, value)
            if urllib.parse.urlsplit(absolute).scheme in ("http", "https"):
                return absolute
    return None


def _charset(content_type: str) -> str:
    for part in content_type.split(";")[1:]:
        name, _, value = part.strip().partition("=")
        if name.lower() == "charset" and value:
            return value.strip("\"'")
    return "utf-8"


Fetcher = Callable[..., tuple[str, str, bytes]]


def _download_image(url: str, deadline: float, get: Fetcher) -> Optional[tuple[bytes, str]]:
    _, _, data = get(url, accept="image/avif,image/webp,image/png,image/jpeg,image/gif;q=0.9",
                     limit=MAX_IMAGE_BYTES, deadline=deadline)
    ext = sniff_image(data)
    return (data, ext) if ext else None


def find_post_image(
    image_url: Optional[str],
    sources: list[str],
    *,
    get: Optional[Fetcher] = None,
) -> Optional[tuple[bytes, str]]:
    """``(bytes, ".jpg"|".png"|".gif"|".webp")`` for a post, or None.

    The image the agent named wins; else the share image of the first
    MAX_SOURCES source pages, in order. Never raises."""
    get = get or fetch
    deadline = time.monotonic() + BUDGET_S
    if image_url:
        try:
            if found := _download_image(image_url, deadline, get):
                return found
        except (FetchRefused, OSError, http.client.HTTPException, ValueError) as exc:
            log.debug("hermuse feed: image %s unusable: %s", image_url[:120], exc)
    for source in sources[:MAX_SOURCES]:
        try:
            final_url, content_type, body = get(
                source, accept="text/html,application/xhtml+xml", limit=MAX_PAGE_BYTES, deadline=deadline)
            if "html" not in content_type:
                continue
            target = share_image_url(body.decode(_charset(content_type), errors="replace"), final_url)
            if target and (found := _download_image(target, deadline, get)):
                return found
        except (FetchRefused, OSError, http.client.HTTPException, ValueError, LookupError) as exc:
            log.debug("hermuse feed: no image from %s: %s", source[:120], exc)
    return None
