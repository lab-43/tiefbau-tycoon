"""Create an offline map fixture in exactly the format the game downloads from Overpass.

The game requests, for a square map of size S around (lat0, lon0):
  * one "ways+nodes" query per 2x2 km tile  -> osm/tile_<i>_<j>.json   (out body geom)
  * one multipolygon relation query          -> osm/relations.json     (out body geom)
  * one bus route relation query             -> osm/bus.json           (out body)
This script reproduces those responses from a local .osm.pbf so the game can be
tested without network access.

usage: python3 pbf_to_overpass.py <file.osm.pbf> <out_dir> <lat0> <lon0> <size_m> [name]
"""
import sys, os, json, math
import osmium

R = 6378137.0
TILE = 2000.0

WAY_KEYS = {
    "highway": None, "building": None, "landuse": None,
    "leisure": {"park", "garden", "playground", "pitch", "sports_centre", "golf_course"},
    "natural": {"water", "wood", "scrub", "grassland", "heath", "sand", "beach", "wetland"},
    "waterway": {"riverbank", "dock", "canal", "river"},
    "water": None, "railway": {"rail", "light_rail", "subway", "tram"},
    "man_made": {"bridge", "pier"}, "area:highway": None,
}
NODE_KEYS = {"highway": {"traffic_signals", "stop", "give_way", "crossing", "bus_stop", "street_lamp"},
             "natural": {"tree"}}
REL_KEYS = {"building": None, "landuse": None, "leisure": {"park", "garden"},
            "natural": {"water", "wood", "scrub", "grassland", "wetland"},
            "waterway": {"riverbank"}, "water": None}


def match(tags, spec):
    for k, allowed in spec.items():
        v = tags.get(k)
        if v is not None and (allowed is None or v in allowed):
            return True
    return False


def to_local(lat, lon, lat0, lon0):
    x = R * math.radians(lon - lon0) * math.cos(math.radians(lat0))
    z = -R * math.radians(lat - lat0)
    return x, z


def to_latlon(x, z, lat0, lon0):
    lon = lon0 + math.degrees(x / (R * math.cos(math.radians(lat0))))
    lat = lat0 - math.degrees(z / R)
    return lat, lon


class Collector(osmium.SimpleHandler):
    def __init__(self, bbox, need_ways=None):
        super().__init__()
        self.s, self.w, self.n, self.e = bbox
        self.need_ways = need_ways
        self.nodes, self.ways, self.rels, self.bus = [], {}, [], []

    def inside(self, lat, lon):
        return self.s <= lat <= self.n and self.w <= lon <= self.e

    def node(self, n):
        if not n.location.valid() or not self.inside(n.location.lat, n.location.lon):
            return
        tags = {t.k: t.v for t in n.tags}
        if match(tags, NODE_KEYS):
            self.nodes.append({"type": "node", "id": n.id, "lat": round(n.location.lat, 7),
                               "lon": round(n.location.lon, 7), "tags": tags})

    def way(self, w):
        tags = {t.k: t.v for t in w.tags}
        wanted = match(tags, WAY_KEYS)
        needed = self.need_ways is not None and w.id in self.need_ways
        if not (wanted or needed):
            return
        geom, ids, any_in = [], [], False
        for nd in w.nodes:
            if not nd.location.valid():
                return
            geom.append({"lat": round(nd.location.lat, 7), "lon": round(nd.location.lon, 7)})
            ids.append(nd.ref)
            any_in = any_in or self.inside(nd.location.lat, nd.location.lon)
        self.ways[w.id] = {"type": "way", "id": w.id, "nodes": ids, "geometry": geom, "tags": tags,
                           "_wanted": wanted, "_in": any_in}

    def relation(self, r):
        tags = {t.k: t.v for t in r.tags}
        members = [{"type": {"n": "node", "w": "way", "r": "relation"}[m.type], "ref": m.ref, "role": m.role} for m in r.members]
        if tags.get("type") == "multipolygon" and match(tags, REL_KEYS):
            self.rels.append({"type": "relation", "id": r.id, "members": members, "tags": tags})
        elif tags.get("type") == "route" and tags.get("route") == "bus":
            self.bus.append({"type": "relation", "id": r.id, "members": members, "tags": tags})


def overpass_doc(elements):
    return {"version": 0.6, "generator": "Overpass API (fixture from pbf)", "osm3s": {"copyright": "OpenStreetMap contributors, ODbL"},
            "elements": elements}


def main():
    pbf, out, lat0, lon0, size = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
    name = sys.argv[6] if len(sys.argv) > 6 else "Fixture"
    half = size / 2
    s, w = to_latlon(-half, half, lat0, lon0)
    n, e = to_latlon(half, -half, lat0, lon0)
    bbox = (s, w, n, e)
    # pass 1: relations (to know which member ways we need)
    c1 = Collector(bbox)
    c1.apply_file(pbf, locations=False)
    # keep relations with at least one member way that we will see inside bbox -> resolved in pass 2
    need = set()
    for r in c1.rels:
        for m in r["members"]:
            if m["type"] == "way":
                need.add(m["ref"])
    c2 = Collector(bbox, need_ways=need)
    c2.apply_file(pbf, locations=True)
    os.makedirs(os.path.join(out, "osm"), exist_ok=True)
    tiles = int(math.ceil(size / TILE))
    total = 0
    for i in range(tiles):
        for j in range(tiles):
            x0, z0 = -half + i * TILE, -half + j * TILE
            ts, tw = to_latlon(x0, z0 + TILE, lat0, lon0)
            tn, te = to_latlon(x0 + TILE, z0, lat0, lon0)
            els = []
            for nd in c2.nodes:
                if ts <= nd["lat"] <= tn and tw <= nd["lon"] <= te:
                    els.append(nd)
            for wid, wy in c2.ways.items():
                if not wy["_wanted"]:
                    continue
                if any(ts <= g["lat"] <= tn and tw <= g["lon"] <= te for g in wy["geometry"]):
                    els.append({k: v for k, v in wy.items() if not k.startswith("_")})
            total += len(els)
            with open(os.path.join(out, "osm", f"tile_{i}_{j}.json"), "w") as f:
                json.dump(overpass_doc(els), f, separators=(",", ":"))
    rels = []
    for r in c1.rels:
        mem, any_in = [], False
        for m in r["members"]:
            if m["type"] != "way":
                continue
            wy = c2.ways.get(m["ref"])
            if not wy:
                continue
            any_in = any_in or wy["_in"]
            mem.append({"type": "way", "ref": m["ref"], "role": m["role"], "geometry": wy["geometry"]})
        if any_in and mem:
            rels.append({"type": "relation", "id": r["id"], "members": mem, "tags": r["tags"]})
    with open(os.path.join(out, "osm", "relations.json"), "w") as f:
        json.dump(overpass_doc(rels), f, separators=(",", ":"))
    bus_in = []
    inside_way_ids = {wid for wid, wy in c2.ways.items() if wy["_in"]}
    for r in c1.bus:
        if any(m["type"] == "way" and m["ref"] in inside_way_ids for m in r["members"]):
            bus_in.append(r)
    with open(os.path.join(out, "osm", "bus.json"), "w") as f:
        json.dump(overpass_doc(bus_in), f, separators=(",", ":"))
    meta = {"name": name, "center_lat": lat0, "center_lon": lon0, "size_m": size, "tile_m": TILE, "tiles": tiles,
            "source": "fixture:" + os.path.basename(pbf)}
    with open(os.path.join(out, "fixture.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print("tiles", tiles, "elements", total, "relations", len(rels), "bus", len(bus_in))


if __name__ == "__main__":
    main()
