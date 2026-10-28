#!/usr/bin/env python3
"""Local stand-in for a Terrarium height tile server (#8, TerrainSource), tiles computed on the fly.

Height in metres at (lat, lon): 12 + 900 * (lon - LON0) - 700 * (lat - LAT0), a plain tilted plane, so the
test can compare Terrain.sample() with the exact value (e2e_gelaende.gd, mode "download").
Paths: /ok/{z}/{x}/{y}.png answers normally (PNG, 256 px like the AWS tiles),
       /webp/{z}/{x}/{y}.webp answers lossless WebP (512 px like Mapterhorn),
       /404/... always HTTP 404, /flaky/... every second request HTTP 503,
       /html/... HTTP 200 with an HTML page (like a proxy or captive portal).
Usage: mock_terrain.py <port>
"""
import io, math, re, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from PIL import Image

PORT = int(sys.argv[1])
LAT0, LON0 = 52.0907, 5.1214   # Utrecht fixture centre (Game.dev_fixture)
counter = {"n": 0}
lock = threading.Lock()


def height(lat, lon):
    return 12.0 + 900.0 * (lon - LON0) - 700.0 * (lat - LAT0)


def tile(z, x, y, size, fmt):
    img = Image.new("RGB", (size, size))
    px = img.load()
    n = 2 ** z
    for j in range(size):
        yy = (y + (j + 0.5) / size) / n
        lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * yy))))
        for i in range(size):
            lon = (x + (i + 0.5) / size) / n * 360.0 - 180.0
            v = height(lat, lon) + 32768.0
            r = int(v // 256)
            g = int(v) % 256
            b = int((v - math.floor(v)) * 256)
            px[i, j] = (r, g, b)
    buf = io.BytesIO()
    if fmt == "webp":
        img.save(buf, "WEBP", lossless=True)
    else:
        img.save(buf, "PNG")
    return buf.getvalue()


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        m = re.match(r"^/(\w+)/(\d+)/(\d+)/(\d+)\.(png|webp)$", self.path)
        if not m:
            self.send_error(404)
            return
        mode, z, x, y, ext = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4)), m.group(5)
        with lock:
            counter["n"] += 1
            k = counter["n"]
        if mode == "404" or (mode == "flaky" and k % 2 == 0):
            self.send_error(404 if mode == "404" else 503)
            return
        if mode == "html":
            body = b"<html><body>" + b"Bitte anmelden. " * 20 + b"</body></html>"
            ctype = "text/html"
        else:
            body = tile(z, x, y, 512 if ext == "webp" else 256, ext)
            ctype = "image/" + ext
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
