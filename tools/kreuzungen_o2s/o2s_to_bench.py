"""Convert osm2streets GeoJSON output into the junction-bench schema (tools/kreuzungen.py).
See README.md. usage: python3 o2s_to_bench.py <raw-dir> <mode std|dual> <fixtures-json> <our-export-dir> <out-dir>"""
import json, math, sys
from pathlib import Path

import shapely as _sh
from shapely.geometry import Polygon as _P

raw, mode, spec_p, ours, out = sys.argv[1:6]
R = 6378137.0
DRIVE = {"Driving", "Bus", "Biking", "Parking", "Shoulder", "SharedLeftTurn", "Buffer"}
SIDEWALK = {"Sidewalk", "SharedUse"}
MARKS = {"center line", "lane separator", "vehicle stop line", "lane arrow", "buffer edge", "parking hatching"}
spec = json.load(open(spec_p))
Path(out).mkdir(parents=True, exist_ok=True)


def proj(lat0, lon0):
    c = math.cos(math.radians(lat0))
    return lambda lon, lat: (R * math.radians(lon - lon0) * c, -R * math.radians(lat - lat0))


def rings(geom, f):
    if geom["type"] == "Polygon":
        polys = [geom["coordinates"]]
    elif geom["type"] == "MultiPolygon":
        polys = geom["coordinates"]
    else:
        return []
    res = []
    for poly in polys:
        flat = []
        for lon, lat in poly[0]:
            x, z = f(lon, lat)
            flat += [round(x, 3), round(z, 3)]
        res.append(flat)
    return res


def poly_len(flat):
    pts = [(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)]
    per = sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
    area = 0.5 * abs(sum(pts[i][0] * pts[i + 1][1] - pts[i + 1][0] * pts[i][1] for i in range(len(pts) - 1)))
    h = per / 2.0
    disc = max(0.0, h * h - 4 * area)
    return (h + math.sqrt(disc)) / 2.0


for fx in spec["kreuzungen"]:
    fid = fx["id"]
    f = proj(fx["lat"], fx["lon"])
    plain = json.load(open(f"{raw}/{fid}.{mode}.plain.geojson"))
    lanes = json.load(open(f"{raw}/{fid}.{mode}.lanes.geojson"))
    marks = json.load(open(f"{raw}/{fid}.{mode}.markings.geojson"))
    imarks = json.load(open(f"{raw}/{fid}.{mode}.imarkings.geojson"))
    asphalt, sidewalk, mark = [], [], []
    # only roads that carry motor traffic; separate cycleways/footways are paths in the game
    drive_roads = {str(ft["properties"].get("road")) for ft in lanes["features"]
                   if ft["properties"].get("type") in ("Driving", "Bus")}
    for ft in lanes["features"]:
        p = ft["properties"]
        t = p.get("type")
        if str(p.get("road")) not in drive_roads:
            continue
        if t in DRIVE:
            asphalt += rings(ft["geometry"], f)
        elif t in SIDEWALK:
            sidewalk += rings(ft["geometry"], f)
    for ft in imarks["features"]:
        if ft["properties"].get("type") == "sidewalk corner":
            sidewalk += rings(ft["geometry"], f)
    _asp = _sh.union_all([_P([(r[i], r[i + 1]) for i in range(0, len(r), 2)]).buffer(0) for r in asphalt if len(r) >= 6])
    for ft in marks["features"]:
        if ft["properties"].get("type") in MARKS:
            for r in rings(ft["geometry"], f):
                if len(r) >= 6 and _asp.contains(_P([(r[i], r[i + 1]) for i in range(0, len(r), 2)]).buffer(0).centroid):
                    mark.append(r)
    roads = {}
    ideg = {}
    for ft in plain["features"]:
        p = ft["properties"]
        if p["type"] == "road" and str(p["id"]) in drive_roads:
            rg = rings(ft["geometry"], f)
            roads[str(p["id"])] = (rg[0] if rg else [], p)
            for k in ("src_i", "dst_i"):
                ideg[str(p[k])] = ideg.get(str(p[k]), 0) + 1
    nodes = []
    # osm2streets intersection polygons include the sidewalk corners; the game would cut them out
    _sw = _sh.union_all([_P([(r[i], r[i + 1]) for i in range(0, len(r), 2)]).buffer(0) for r in sidewalk if len(r) >= 6])
    itris = []
    for ft in plain["features"]:
        p = ft["properties"]
        if p["type"] != "intersection":
            continue
        rg = rings(ft["geometry"], f)
        deg = ideg.get(str(p["id"]), 0)
        if deg == 0 or not rg:
            continue
        g = _P([(rg[0][i], rg[0][i + 1]) for i in range(0, len(rg[0]), 2)]).buffer(0).difference(_sw)
        for t in getattr(_sh.constrained_delaunay_triangles(g), "geoms", []):
            c = list(t.exterior.coords)[:3]
            itris += [c[0][0], c[0][1], c[1][0], c[1][1], c[2][0], c[2][1]]
        xs, zs = rg[0][0::2], rg[0][1::2]
        nodes.append({"pos": [sum(xs) / len(xs), sum(zs) / len(zs)], "deg": deg, "ctrl": p.get("control", "")})
    edges = [{"len": poly_len(flat), "pts": flat} for flat, p in roads.values() if flat]
    ours_d = json.load(open(f"{ours}/{fid}.json"))
    res = {"id": fid, "name": fx["name"], "radius_m": fx.get("radius_m", 150), "drive_paths": False,
           "polys": {"asphalt": asphalt, "sidewalk": sidewalk, "mark": mark},
           "layers": {"asphalt": itris}, "nodes": nodes, "edges": edges,
           "lanes": [], "connectors": [], "osm_roads": ours_d.get("osm_roads", [])}
    json.dump(res, open(f"{out}/{fid}.json", "w"))
    print(fid, len(asphalt), len(sidewalk), len(mark), len(nodes))
