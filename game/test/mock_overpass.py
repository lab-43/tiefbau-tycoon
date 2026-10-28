#!/usr/bin/env python3
"""Local stand-in for Overpass servers, serving the Utrecht fixture by bounding box.

Each URL path prefix picks a behaviour, so one process can play several servers:
  /ok/api/interpreter      answers normally
  /slow/api/interpreter    answers after a delay
  /rate/api/interpreter    always HTTP 429
  /flaky/api/interpreter   every second request HTTP 504 (HTML error page)
  /big/api/interpreter     tiles wider than 600 m end with a runtime error (timeout remark)
  /dead/...                is not served at all (use a closed port for that)
Usage: mock_overpass.py <fixture osm dir> <port>
"""
import json, math, os, re, sys, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FIX = sys.argv[1]
PORT = int(sys.argv[2])

ways, nodes, rels, bus = {}, {}, {}, {}
for f in sorted(os.listdir(FIX)):
    if not f.endswith(".json"):
        continue
    d = json.load(open(os.path.join(FIX, f)))
    for e in d["elements"]:
        if f.startswith("bus"):
            bus[e["id"]] = e
        elif e["type"] == "relation":
            rels[e["id"]] = e
        elif e["type"] == "way":
            ways[e["id"]] = e
        elif e["type"] == "node":
            nodes[e["id"]] = e


def bounds_of(pts):
    lats = [p["lat"] for p in pts]
    lons = [p["lon"] for p in pts]
    return (min(lats), min(lons), max(lats), max(lons))


wb = {i: bounds_of(w["geometry"]) for i, w in ways.items() if w.get("geometry")}
rb = {}
for i, r in rels.items():
    pts = [p for m in r.get("members", []) for p in m.get("geometry", [])]
    if pts:
        rb[i] = bounds_of(pts)

counter = {"n": 0}
lock = threading.Lock()


def hit(b, q):
    return not (b[2] < q[0] or b[0] > q[2] or b[3] < q[1] or b[1] > q[3])


def answer(elements, remark=None):
    body = '{\n  "version": 0.6,\n  "generator": "mock",\n  "elements": [\n'
    body += ",\n".join(json.dumps(e) for e in elements)
    body += "\n  ]"
    if remark:
        body += ',\n  "remark": "%s"' % remark
    body += "\n}\n"
    return body.encode()


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.endswith("/api/status"):
            self._send(200, b"Connected as: 1\nRate limit: 2\n2 slots available now.\n", "text/plain")
        else:
            self._send(404, b"nope", "text/plain")

    def do_POST(self):
        mode = self.path.strip("/").split("/")[0]
        n = int(self.headers.get("Content-Length", 0))
        q = urllib.parse.unquote_plus(self.rfile.read(n).decode())[5:]
        with lock:
            counter["n"] += 1
            k = counter["n"]
        if mode == "rate":
            return self._send(429, b"<html><body><p>Rate limit exceeded</p></body></html>", "text/html")
        if mode == "flaky" and k % 2 == 0:
            return self._send(504, b"<html><body><p><strong>Error</strong>: runtime error: open64: 0 Success /osm3s_osm_base Dispatcher_Client::request_read_and_idx::timeout. The server is probably too busy to handle your request.</p></body></html>", "text/html")
        if mode == "slow":
            time.sleep(2.5)
        m = re.search(r"\[bbox:([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\]", q)
        bb = tuple(float(x) for x in m.groups()) if m else None
        if "relation(id:" in q:
            ids = [int(x) for x in re.search(r"id:([\d,]+)", q).group(1).split(",")]
            return self._send(200, answer([rels[i] for i in ids if i in rels]))
        if "out ids" in q:
            return self._send(200, answer([{"type": "relation", "id": i} for i, b in rb.items() if hit(b, bb)]))
        if '"route"="bus"' in q:
            return self._send(200, answer(list(bus.values())))
        # tile
        width_m = (bb[3] - bb[1]) * 111320 * math.cos(math.radians(bb[0]))
        if mode == "big" and width_m > 600:
            return self._send(200, answer([], 'runtime error: Query timed out in \\"query\\" at line 1 after 91 seconds.'))
        els = [nodes[i] for i in nodes if bb[0] <= nodes[i]["lat"] <= bb[2] and bb[1] <= nodes[i]["lon"] <= bb[3]]
        els += [ways[i] for i, b in wb.items() if hit(b, bb)]
        self._send(200, answer(els))


print("mock overpass on", PORT, "ways", len(ways), "rels", len(rels), "bus", len(bus), flush=True)
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
