#!/usr/bin/env python3
"""Junction bench ("Kreuzungs-Prüfstand"): measures and draws the road geometry that
game/test/junction_bench.gd exported for the fixed junctions in testdata/kreuzungen.

    tools/kreuzungen.sh                          # bake + measure + pictures (current code)
    python3 tools/kreuzungen.py IN [IN2 ...] --out DIR [--labels heute,neu]

Pictures: <fixture>.png (whole circle), <fixture>_nah.png (centre), <fixture>_fehler.png (worst spots of
the first IN). Each IN is a directory with one <fixture>.json per junction (same schema as junction_bench.gd writes;
other generators such as an osm2streets converter write the same schema). With several INs the
pictures show the variants side by side and the table compares them.

Measured inside the circle of radius_m around the junction centre:
  knoten        graph nodes with >= 3 roads (one real junction should be one node)
  kurz          road pieces shorter than 10 m between two nodes (stubs between mini junctions)
  luecke_m      metres of lane/turn path centre line that are not on asphalt (visible gaps; U-turns excluded)
  ueber_gehweg_m metres of lane/connector centre line over a raised sidewalk (cars drive through the curb)
  gehweg_auf_fahrbahn_m2  sidewalk area lying on top of asphalt. Asphalt hidden under a sidewalk is
                not visible, so this overstates; what you see is ueber_gehweg_m and the pictures
  splitter      tiny holes (0.02 – 4 m²) inside the asphalt surface (ground showing through)
  stufen        steps and spikes in the asphalt outline: two sharp turns (> 45°) in opposite directions
                0.3–3 m apart (a width jump), or one turn sharper than 120° (a spike)
  knicke        places where a lane or turn path changes heading by more than 15° within 1 m
  versatz       straight-through connectors whose lanes are offset sideways by more than 0.5 m (S-wobble)
  markierung_m  approximate length of road markings (area / 0.12 m)
Needs shapely and matplotlib (pip install --break-system-packages shapely matplotlib).
"""
import argparse, json, math, sys
from pathlib import Path

try:
    import numpy as np
    import shapely
    from shapely.geometry import LineString, Point, Polygon
    from shapely.ops import unary_union
except ImportError:
    sys.exit("shapely fehlt: pip install --break-system-packages shapely matplotlib")

MARK_W = 0.12
KINK_DEG = 15.0
KINK_SPAN = 1.0
OFFSET_TOL = 0.5
METRICS = ["knoten", "kurz", "luecke_m", "ueber_gehweg_m", "gehweg_auf_fahrbahn_m2", "splitter", "stufen", "knicke", "versatz", "markierung_m"]
LOWER_IS_BETTER = {"knoten", "kurz", "luecke_m", "ueber_gehweg_m", "gehweg_auf_fahrbahn_m2", "splitter", "stufen", "knicke", "versatz"}


def pts_of(flat):
    return [(flat[i], flat[i + 1]) for i in range(0, len(flat) - 1, 2)]


def layer_geom(d, name):
    """Union of a layer: either flat triangles (layers) or polygon rings (polys)."""
    geoms = []
    tris = d.get("layers", {}).get(name)
    if tris:
        arr = np.asarray(tris, dtype=float).reshape(-1, 3, 2)
        geoms.extend(shapely.polygons(arr))
    for ring in d.get("polys", {}).get(name, []):
        p = pts_of(ring)
        if len(p) >= 3:
            g = Polygon(p)
            geoms.append(g if g.is_valid else g.buffer(0))
    if not geoms:
        return Polygon()
    return shapely.union_all(shapely.make_valid(np.asarray(geoms, dtype=object)), grid_size=0.001)


def layer_parts(d, name):
    """Individual pieces of a layer for drawing."""
    out = []
    tris = d.get("layers", {}).get(name)
    if tris:
        arr = np.asarray(tris, dtype=float).reshape(-1, 3, 2)
        out.extend(arr)
    for ring in d.get("polys", {}).get(name, []):
        p = pts_of(ring)
        if len(p) >= 3:
            out.append(np.asarray(p))
    return out


def resample(pts, step=0.5):
    ls = LineString(pts)
    n = max(2, int(ls.length / step) + 1)
    return [ls.interpolate(i * ls.length / (n - 1)).coords[0] for i in range(n)]


def heading(a, b):
    return math.atan2(b[1] - a[1], b[0] - a[0])


def kinks(pts, step=0.5):
    """Positions where the heading changes by more than KINK_DEG within KINK_SPAN metres."""
    if len(pts) < 2 or LineString(pts).length < 2.0:
        return []
    r = resample(pts, step)
    k = max(1, int(KINK_SPAN / step))
    hs = [heading(r[i], r[i + 1]) for i in range(len(r) - 1)]
    out = []
    for i in range(len(hs) - k):
        dh = abs((hs[i + k] - hs[i] + math.pi) % (2 * math.pi) - math.pi)
        if math.degrees(dh) > KINK_DEG:
            out.append(r[i + 1])
    return out


def tail(pts, length):
    ls = LineString(pts)
    if ls.length <= length:
        return list(ls.coords)
    return list(shapely.ops.substring(ls, ls.length - length, ls.length).coords)


def head(pts, length):
    ls = LineString(pts)
    if ls.length <= length:
        return list(ls.coords)
    return list(shapely.ops.substring(ls, 0, length).coords)


def outline_steps(geom):
    """Points where the outline of the asphalt makes a step (two sharp opposite turns within 3 m)
    or a spike (one turn sharper than 120°)."""
    out = []
    for poly in getattr(geom, "geoms", [geom]):
        if not isinstance(poly, Polygon) or poly.is_empty:
            continue
        for ring in [poly.exterior] + list(poly.interiors):
            c = list(ring.simplify(0.1).coords)[:-1]
            n = len(c)
            if n < 4:
                continue
            turns = []
            for i in range(n):
                a, b, e = c[i - 1], c[i], c[(i + 1) % n]
                t = math.atan2(e[1] - b[1], e[0] - b[0]) - math.atan2(b[1] - a[1], b[0] - a[0])
                turns.append((t + math.pi) % (2 * math.pi) - math.pi)
            for i in range(n):
                j = (i + 1) % n
                if abs(turns[i]) > math.radians(120) and min(math.dist(c[i], c[i - 1]), math.dist(c[i], c[j])) > 0.3:
                    out.append(c[i])
                elif (0.3 < math.dist(c[i], c[j]) < 3.0 and abs(turns[i]) > math.radians(45) and abs(turns[j]) > math.radians(45)
                      and turns[i] * turns[j] < 0):
                    out.append(((c[i][0] + c[j][0]) / 2, (c[i][1] + c[j][1]) / 2))
    return out


def measure(d):
    R = float(d.get("radius_m", 150.0))
    win = Point(0, 0).buffer(R, 64)
    asphalt = layer_geom(d, "asphalt")
    sidewalk = layer_geom(d, "sidewalk")
    mark = layer_geom(d, "mark")
    m = {}
    nodes = [n for n in d.get("nodes", []) if math.hypot(*n["pos"]) <= R]
    m["knoten"] = sum(1 for n in nodes if n.get("deg", 0) >= 3)
    m["kurz"] = sum(1 for e in d.get("edges", []) if e.get("len", 99) < 10.0
                    and LineString(pts_of(e["pts"])).intersects(win))
    lanes = {l["key"]: pts_of(l["pts"]) for l in d.get("lanes", []) if len(l["pts"]) >= 4}
    drive = []
    for p in lanes.values():
        drive.append(LineString(p))
    conns = [c for c in d.get("connectors", []) if len(c["pts"]) >= 4]
    for c in conns:
        if c.get("turn") != "U":   # turning at dead ends is not a junction matter
            drive.append(LineString(pts_of(c["pts"])))
    dr = shapely.union_all(drive).intersection(win) if drive else LineString()
    gap = dr.difference(asphalt.buffer(0.05)) if not asphalt.is_empty else dr
    m["luecke_m"] = round(gap.length, 1)
    over_sw = dr.intersection(sidewalk.buffer(-0.05)) if not sidewalk.is_empty else LineString()
    m["ueber_gehweg_m"] = round(over_sw.length, 1)
    sw_on = sidewalk.intersection(asphalt).intersection(win) if not (sidewalk.is_empty or asphalt.is_empty) else Polygon()
    m["gehweg_auf_fahrbahn_m2"] = round(sw_on.area, 1)
    holes = []
    for poly in getattr(asphalt.intersection(win), "geoms", [asphalt.intersection(win)]):
        if isinstance(poly, Polygon):
            for ring in poly.interiors:
                h = Polygon(ring)
                if 0.02 <= h.area < 4.0:   # smaller ones are numeric seams, not visible
                    holes.append(h)
    m["splitter"] = len(holes)
    steps = [q for q in outline_steps(asphalt) if math.hypot(*q) <= R - 2.0]
    step_cells = {}
    for q in steps:
        step_cells.setdefault((round(q[0] / 3.0), round(q[1] / 3.0)), q)
    steps = list(step_cells.values())
    m["stufen"] = len(steps)
    # kinks along lanes and along turn paths (lane tail + connector + lane head)
    kp = []
    for p in lanes.values():
        kp.extend(kinks(p))
    offsets = []
    for c in conns:
        if c.get("turn") == "U":
            continue
        cp = pts_of(c["pts"])
        chain = list(cp)
        if c.get("from") in lanes:
            chain = tail(lanes[c["from"]], 10.0)[:-1] + chain
        if c.get("to") in lanes:
            chain = chain + head(lanes[c["to"]], 10.0)[1:]
        kp.extend(kinks(chain))
        if c.get("turn") == "S" and c.get("from") in lanes and c.get("to") in lanes:
            a = lanes[c["from"]]
            p0, p1 = a[-2], a[-1]
            t = (p1[0] - p0[0], p1[1] - p0[1])
            tl = math.hypot(*t) or 1.0
            b = lanes[c["to"]]
            q, q1 = b[0], b[1]
            u = (q1[0] - q[0], q1[1] - q[1])
            ul = math.hypot(*u) or 1.0
            # only real straight-through movements (at a T the "closest to straight" move is a turn)
            if (t[0] * u[0] + t[1] * u[1]) / (tl * ul) < math.cos(math.radians(20.0)):
                continue
            lat = abs((q[0] - p1[0]) * (-t[1] / tl) + (q[1] - p1[1]) * (t[0] / tl))
            if lat > OFFSET_TOL and math.hypot(q[0] - p1[0], q[1] - p1[1]) < 60:
                offsets.append((p1, q))
    kp = [p for p in kp if math.hypot(*p) <= R]
    cells = {(round(p[0] / 2.0), round(p[1] / 2.0)) for p in kp}
    m["knicke"] = len(cells)
    m["versatz"] = sum(1 for p, q in offsets if math.hypot(*p) <= R)
    m["markierung_m"] = round(mark.intersection(win).area / MARK_W, 0) if not mark.is_empty else 0
    if d.get("drive_paths", True) is False:
        # generator without lanes/turn paths (e.g. osm2streets): these measures do not apply
        for k in ("luecke_m", "ueber_gehweg_m", "knicke", "versatz"):
            m[k] = None
    extra = {"gap": gap, "sw_on": sw_on, "kinks": kp, "holes": holes, "offsets": offsets, "steps": steps}
    return m, extra


def draw(fixture, variants, labels, out_png, radius=None):
    """One row per variant: left the surface as in the game, right the drive paths and the errors."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.collections import PolyCollection, LineCollection
    n = len(variants)
    fig, axes = plt.subplots(n, 2, figsize=(18, 9.2 * n), dpi=90, squeeze=False)
    for row, ((d, m, ex), lab) in enumerate(zip(variants, labels)):
        R = radius or float(d.get("radius_m", 150.0)) + 10
        lw_scale = 150.0 / R
        for col in range(2):
            ax = axes[row][col]
            ax.set_facecolor("#d8d8d4")
            ax.set_xlim(-R, R)
            ax.set_ylim(R, -R)  # z points south: north up
            ax.set_aspect("equal")
            ax.set_xticks([])
            ax.set_yticks([])
        ax = axes[row][0]
        for name, color in (("asphalt", "#3b3e44"), ("sidewalk", "#b9b9b4"), ("mark", "#ffffff")):
            parts = layer_parts(d, name)
            if parts:
                ax.add_collection(PolyCollection(parts, facecolors=color, edgecolors=color, linewidths=0.15))
        ax.set_title(f"{lab}: Oberfläche wie im Spiel (von oben)", fontsize=13)
        ax = axes[row][1]
        parts = layer_parts(d, "asphalt")
        if parts:
            ax.add_collection(PolyCollection(parts, facecolors="#9a9ca0", edgecolors="#9a9ca0", linewidths=0.1))
        parts = layer_parts(d, "sidewalk")
        if parts:
            ax.add_collection(PolyCollection(parts, facecolors="#cfcfca", edgecolors="#cfcfca", linewidths=0.1))
        for r_ in d.get("osm_roads", []):
            p = pts_of(r_["pts"])
            ax.plot([q[0] for q in p], [q[1] for q in p], color="black", lw=0.5, ls=(0, (2, 2)), alpha=0.6)
        lanes = [pts_of(l["pts"]) for l in d.get("lanes", [])]
        ax.add_collection(LineCollection(lanes, colors="#1f5fbf", linewidths=0.9 * lw_scale ** 0.5))
        cs = [pts_of(c["pts"]) for c in d.get("connectors", [])]
        ax.add_collection(LineCollection(cs, colors="#e07b00", linewidths=0.7 * lw_scale ** 0.5))
        for part in getattr(ex["gap"], "geoms", [ex["gap"]]):
            if isinstance(part, LineString) and not part.is_empty:
                x, y = part.xy
                ax.plot(x, y, color="#e00000", lw=2.5)
        for part in getattr(ex["sw_on"], "geoms", [ex["sw_on"]]):
            if isinstance(part, Polygon) and not part.is_empty:
                x, y = part.exterior.xy
                ax.fill(x, y, color="#d000d0", alpha=0.8)
        for h in ex["holes"]:
            x, y = h.exterior.xy
            ax.fill(x, y, color="#e00000", alpha=0.9)
            ax.plot([h.centroid.x], [h.centroid.y], "s", mfc="none", mec="#e00000", ms=9, mew=1.5)
        if ex["kinks"]:
            ax.plot([p[0] for p in ex["kinks"]], [p[1] for p in ex["kinks"]], "o", mfc="none", mec="#e00000", ms=7, mew=1.2)
        if ex["steps"]:
            ax.plot([p[0] for p in ex["steps"]], [p[1] for p in ex["steps"]], "^", mfc="none", mec="#7a00c0", ms=9, mew=1.5)
        for p, q in ex["offsets"]:
            ax.plot([p[0], q[0]], [p[1], q[1]], color="#00a000", lw=2)
        for n_ in d.get("nodes", []):
            if n_.get("deg", 0) >= 3:
                ax.plot(n_["pos"][0], n_["pos"][1], "o", color="black", ms=4)
        txt = "  ".join(f"{k}={'–' if m[k] is None else m[k]}" for k in METRICS)
        ax.set_title(f"{lab}: Fahrwege (blau Spur, orange Abbiegen, schwarz gestrichelt OSM)\n"
                     "rot = Lücke/Knick/Splitter (Quadrat), violettes Dreieck = Stufe/Zacke, lila Fläche = Gehweg auf Fahrbahn, grün = Versatz, Punkt = Kreuzungsknoten", fontsize=10)
        ax.text(0.01, 0.01, txt, transform=ax.transAxes, fontsize=8.5, color="black",
                bbox=dict(facecolor="white", alpha=0.85, edgecolor="none"))
    d0 = variants[0][0]
    R0 = radius or int(d0.get("radius_m", 150))
    fig.suptitle(f"{d0.get('name', fixture)} ({fixture}) – Ausschnitt ±{int(R0)} m", fontsize=16)
    fig.tight_layout(rect=(0, 0, 1, 0.97))
    fig.savefig(out_png)
    plt.close(fig)


def problem_spots(ex, R, limit):
    """The worst places of one variant: [(x, z, what, size)], at most one per 15 m."""
    spots = []
    for part in getattr(ex["sw_on"], "geoms", [ex["sw_on"]]):
        if isinstance(part, Polygon) and part.area > 0.5:
            spots.append((part.centroid.x, part.centroid.y, "Gehweg auf Fahrbahn %.1f m²" % part.area, part.area * 2))
    for h in ex["holes"]:
        spots.append((h.centroid.x, h.centroid.y, "Splitter %.1f m²" % h.area, 3.0 + h.area))
    for part in getattr(ex["gap"], "geoms", [ex["gap"]]):
        if isinstance(part, LineString) and part.length > 1.0:
            q = part.interpolate(0.5, normalized=True)
            spots.append((q.x, q.y, "Lücke %.1f m" % part.length, part.length))
    for q in ex.get("steps", []):
        spots.append((q[0], q[1], "Stufe/Zacke im Rand", 2.5))
    spots = [s_ for s_ in spots if math.hypot(s_[0], s_[1]) <= R]
    spots.sort(key=lambda s_: -s_[3])
    keep = []
    for s_ in spots:
        if all(math.hypot(s_[0] - k[0], s_[1] - k[1]) > 15.0 for k in keep):
            keep.append(s_)
        if len(keep) >= limit:
            break
    return keep


def draw_spots(fixture, d, ex, spots, out_png, half=18.0):
    """Close-ups (±half m) of problem spots: surface, lanes and turn paths in one picture each."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.collections import PolyCollection, LineCollection
    cols = 3
    rows = (len(spots) + cols - 1) // cols
    fig, axes = plt.subplots(rows, cols, figsize=(6 * cols, 6 * rows), dpi=80, squeeze=False)
    layers = {name: layer_parts(d, name) for name in ("asphalt", "sidewalk", "mark")}
    lanes = [pts_of(l["pts"]) for l in d.get("lanes", [])]
    cs = [pts_of(c["pts"]) for c in d.get("connectors", []) if c.get("turn") != "U"]
    for i in range(rows * cols):
        ax = axes[i // cols][i % cols]
        ax.set_xticks([])
        ax.set_yticks([])
        if i >= len(spots):
            ax.axis("off")
            continue
        x, z, what, _ = spots[i]
        ax.set_facecolor("#d8d8d4")
        ax.set_xlim(x - half, x + half)
        ax.set_ylim(z + half, z - half)
        ax.set_aspect("equal")
        for name, color in (("asphalt", "#3b3e44"), ("sidewalk", "#b9b9b4"), ("mark", "#ffffff")):
            if layers[name]:
                ax.add_collection(PolyCollection(layers[name], facecolors=color, edgecolors=color, linewidths=0.15))
        ax.add_collection(LineCollection(lanes, colors="#4f8fff", linewidths=1.0))
        ax.add_collection(LineCollection(cs, colors="#ff9a20", linewidths=0.8))
        ax.plot([x], [z], "o", mfc="none", mec="#ff2020", ms=26, mew=2)
        ax.set_title(f"{what} bei ({x:.0f}, {z:.0f})", fontsize=11)
    fig.suptitle(f"{d.get('name', fixture)} – Fehlerstellen ({fixture})", fontsize=14)
    fig.tight_layout(rect=(0, 0, 1, 0.97))
    fig.savefig(out_png)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--labels", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--no-pictures", action="store_true")
    ap.add_argument("--zoom", type=float, default=55.0, help="half edge of the close-up picture (m)")
    ap.add_argument("--spots", type=int, default=6, help="close-ups of the worst problem spots of the first input")
    a = ap.parse_args()
    labels = a.labels.split(",") if a.labels else [Path(p).name for p in a.inputs]
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    fixtures = sorted(p.stem for p in Path(a.inputs[0]).glob("*.json") if p.stem != "metrics")
    if a.only:
        fixtures = [f for f in fixtures if f in a.only.split(",")]
    table = {}
    for fx in fixtures:
        variants = []
        for inp in a.inputs:
            p = Path(inp) / f"{fx}.json"
            if not p.exists():
                continue
            d = json.loads(p.read_text())
            m, ex = measure(d)
            variants.append((d, m, ex))
            table.setdefault(fx, {})[labels[a.inputs.index(inp)]] = m
        if variants and not a.no_pictures:
            labs = [labels[a.inputs.index(i)] for i in a.inputs if (Path(i) / f"{fx}.json").exists()]
            draw(fx, variants, labs, out / f"{fx}.png")
            draw(fx, variants, labs, out / f"{fx}_nah.png", radius=a.zoom)
            if a.spots > 0:
                d0, m0, ex0 = variants[0]
                sp = problem_spots(ex0, float(d0.get("radius_m", 150.0)), a.spots)
                if sp:
                    draw_spots(fx, d0, ex0, sp, out / f"{fx}_fehler.png")
    (out / "metrics.json").write_text(json.dumps(table, indent=1, ensure_ascii=False))
    w = max(len(f) for f in fixtures) if fixtures else 10
    print(f"{'Kreuzung':<{w}}  {'Variante':<12} " + " ".join(f"{k[:10]:>10}" for k in METRICS))
    totals = {}
    for fx in fixtures:
        for lab, m in table.get(fx, {}).items():
            print(f"{fx:<{w}}  {lab:<12} " + " ".join(f"{'–' if m[k] is None else m[k]:>10}" for k in METRICS))
            t = totals.setdefault(lab, {k: 0 for k in METRICS})
            for k in METRICS:
                t[k] = None if (m[k] is None or t[k] is None) else t[k] + m[k]
    for lab, t in totals.items():
        print(f"{'SUMME':<{w}}  {lab:<12} " + " ".join(f"{'–' if t[k] is None else round(t[k], 1):>10}" for k in METRICS))
    print(f"Bilder und metrics.json in {out}")


if __name__ == "__main__":
    main()
