"""Feed images: share-image discovery, guarded fetching, storage beside the post."""

from __future__ import annotations

import http.server
import socket
import threading

import pytest

import feed_images
import store

PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 32
JPEG = b"\xff\xd8\xff\xe0" + b"\0" * 32


def test_sniff_accepts_raster_images_only():
    assert feed_images.sniff_image(PNG) == ".png"
    assert feed_images.sniff_image(JPEG) == ".jpg"
    assert feed_images.sniff_image(b"GIF89a....") == ".gif"
    assert feed_images.sniff_image(b"RIFF\0\0\0\0WEBPVP8 ") == ".webp"
    assert feed_images.sniff_image(b"<svg xmlns='http://www.w3.org/2000/svg'/>") is None
    assert feed_images.sniff_image(b"<html>") is None


def test_share_image_prefers_og_and_resolves_relative_urls():
    html = """<html><head>
      <link rel="image_src" href="/link.png">
      <meta name="twitter:image" content="https://cdn.example/tw.jpg">
      <meta property="og:image" content="/img/og.jpg">
    </head><body></body></html>"""
    assert feed_images.share_image_url(html, "https://news.example/a/b") == "https://news.example/img/og.jpg"
    assert feed_images.share_image_url(
        '<meta name="twitter:image" content="tw.png">', "https://x.example/p/") == "https://x.example/p/tw.png"
    assert feed_images.share_image_url('<link rel="image_src" href="s.png">', "https://x.example/") == (
        "https://x.example/s.png")
    assert feed_images.share_image_url('<meta property="og:image" content="javascript:alert(1)">',
                                       "https://x.example/") is None
    assert feed_images.share_image_url("<p>no image</p>", "https://x.example/") is None


class FakeWeb:
    """``fetch`` stand-in: canned ``url -> (content_type, body)``, records calls."""

    def __init__(self, pages):
        self.pages = pages
        self.calls = []

    def __call__(self, url, *, accept, limit, deadline):
        self.calls.append(url)
        if url not in self.pages:
            raise feed_images.FetchRefused("HTTP 404")
        content_type, body = self.pages[url]
        return url, content_type, body


def test_named_image_wins_then_first_source_share_image():
    web = FakeWeb({
        "https://img.example/named.jpg": ("image/jpeg", JPEG),
        "https://news.example/a": ("text/html; charset=utf-8", b'<meta property="og:image" content="/og.png">'),
        "https://news.example/og.png": ("image/png", PNG),
    })
    assert feed_images.find_post_image("https://img.example/named.jpg", ["https://news.example/a"], get=web) == (
        JPEG, ".jpg")
    assert feed_images.find_post_image(None, ["https://news.example/a"], get=web) == (PNG, ".png")
    # A dead named image falls back to the source's.
    assert feed_images.find_post_image("https://img.example/gone.jpg", ["https://news.example/a"], get=web) == (
        PNG, ".png")


def test_no_image_cases_never_raise():
    web = FakeWeb({
        "https://a.example/": ("text/html", b"<p>nothing</p>"),
        "https://b.example/": ("application/pdf", b"%PDF"),
        "https://c.example/": ("text/html", b'<meta property="og:image" content="https://c.example/i.svg">'),
        "https://c.example/i.svg": ("image/svg+xml", b"<svg/>"),
        "https://d.example/": ("text/html", b'<meta property="og:image" content="https://d.example/i.png">'),
    })
    for source in ("https://a.example/", "https://b.example/", "https://c.example/", "https://d.example/",
                   "https://unknown.example/"):
        assert feed_images.find_post_image(None, [source], get=web) is None
    assert feed_images.find_post_image(None, [], get=web) is None


def test_only_the_first_two_sources_are_tried():
    web = FakeWeb({"https://third.example/": ("text/html", b'<meta property="og:image" content="x.png">')})
    assert feed_images.find_post_image(
        None, ["https://one.example/", "https://two.example/", "https://third.example/"], get=web) is None
    assert web.calls == ["https://one.example/", "https://two.example/"]


@pytest.mark.parametrize("address", ["127.0.0.1", "10.0.0.5", "192.168.1.2", "169.254.169.254", "::1", "fd00::1",
                                     "100.64.0.1", "0.0.0.0", "224.0.0.1"])
def test_non_public_addresses_are_refused(address):
    with pytest.raises(feed_images.FetchRefused):
        feed_images.public_address(address, 443)


def test_mixed_public_and_private_records_are_refused(monkeypatch):
    def records(host, port, *args, **kwargs):
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.215.14", port)),
                (socket.AF_INET, socket.SOCK_STREAM, 6, "", ("127.0.0.1", port))]

    monkeypatch.setattr(socket, "getaddrinfo", records)
    with pytest.raises(feed_images.FetchRefused):
        feed_images.public_address("rebind.example", 443)


def test_fetch_refuses_other_schemes():
    for url in ("file:///etc/passwd", "ftp://x.example/a", "gopher://x", "http:///nohost"):
        with pytest.raises(feed_images.FetchRefused):
            feed_images.fetch(url, accept="*/*", limit=10, deadline=float("inf"))


@pytest.fixture()
def local_site(monkeypatch):
    """A real HTTP server reachable as http://site.test:<port>/ (only that name
    is let through the public-address check; everything else stays guarded)."""
    routes: dict[str, tuple[int, dict, bytes]] = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            status, headers, body = routes.get(self.path, (404, {}, b""))
            self.send_response(status)
            for key, value in headers.items():
                self.send_header(key, value)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    real = feed_images.public_address
    monkeypatch.setattr(feed_images, "public_address",
                        lambda host, port: "127.0.0.1" if host == "site.test" else real(host, port))
    yield f"http://site.test:{server.server_address[1]}", routes
    server.shutdown()
    server.server_close()


def test_real_fetch_finds_the_share_image(local_site):
    base, routes = local_site
    routes["/article"] = (200, {"Content-Type": "text/html; charset=utf-8"},
                          b'<html><head><meta property="og:image" content="/cover.png"></head></html>')
    routes["/old"] = (301, {"Location": "/article"}, b"")
    routes["/cover.png"] = (200, {"Content-Type": "image/png"}, PNG)
    assert feed_images.find_post_image(None, [f"{base}/old"]) == (PNG, ".png")


def test_real_fetch_refuses_redirects_to_private_addresses_and_oversize_bodies(local_site):
    base, routes = local_site
    routes["/meta"] = (302, {"Location": "http://169.254.169.254/latest/meta-data"}, b"")
    routes["/huge.png"] = (200, {"Content-Type": "image/png"}, PNG + b"\0" * feed_images.MAX_IMAGE_BYTES)
    with pytest.raises(feed_images.FetchRefused):
        feed_images.fetch(f"{base}/meta", accept="*/*", limit=1000, deadline=float("inf"))
    with pytest.raises(feed_images.FetchRefused):
        feed_images.fetch(f"{base}/huge.png", accept="*/*", limit=feed_images.MAX_IMAGE_BYTES,
                          deadline=float("inf"))
    assert feed_images.find_post_image(f"{base}/huge.png", [f"{base}/meta"]) is None


def test_stored_image_is_served_by_the_plugin_and_deleted_with_the_post(hermuse_root):
    record = store.post_feed(hermuse_root, title="Rain", body="b", why="w", image=(PNG, ".png"),
                             image_url="https://ignored.example/x.png")
    assert record["image_url"] == f"/api/plugins/hermuse/feed/{record['id']}/image"
    path, mime = store.feed_image(hermuse_root, record["id"])
    assert path.read_bytes() == PNG and mime == "image/png"
    assert "images/" in (hermuse_root / "feed" / record["file"]).read_text()
    assert store.get_feed_post(hermuse_root, record["id"])["image_url"] == record["image_url"]
    assert store.delete_feed_post(hermuse_root, record["id"])
    assert not path.exists()
    with pytest.raises(ValueError):
        store.post_feed(hermuse_root, title="t", body="b", image=(b"<svg/>", ".svg"))
    plain = store.post_feed(hermuse_root, title="t", body="b")
    assert plain["image_url"] is None and store.feed_image(hermuse_root, plain["id"]) is None
