#!/usr/bin/env python3
"""Turns the Sketchfab model "Mercedes CITARO II RATP" (moussasy.sy715, CC BY 4.0, downloaded by
Jonathan into Tiefbau Tycoon/private/mercedescitaroiiratp.zip) into the traffic bus of the game:
game/assets/consim/bus_citaro/bus_citaro.glb + .json (private asset folder, never in git).

What it does (issue #2):
- conventions of the extracted traffic models (docs/consim_assets.md): metres, Y up, front -Z,
  +X = vehicle right, ground y = 0, X centred, Z = midpoint between the axles;
- drops the SketchUp edge lines (line primitives) and flattens the scene into one mesh;
- lamp glass gets the game's naming <material>__light_head / __light_tail / __light_brake /
  __indicator_l / __indicator_r, so TrafficModels lights the bus's own glass;
- HVV livery: the RATP jade/white body becomes Hochbahn red, RATP logos are painted over;
- PBR fix: SketchUp exports leave metallicFactor at the glTF default 1.0 (everything chrome).

usage: python3 tools/models/citaro_import.py <source .glb or .zip> [out dir]
"""
import io, json, struct, sys, zipfile
from pathlib import Path
import numpy as np
from pygltflib import GLTF2

SRC_FRONT_X = 0.0                  # source: length along +X, front at x ~ 0
AXLES_X = (2.93, 8.94)             # source x of the front / rear axle (wheel centres)
CENTRE_Z = 12.53                   # source z of the vehicle centre line (body z 11.25 .. 13.80)
WHEEL_R = 0.44
HVV_RED = [0.40, 0.012, 0.016, 1.0]  # linear; Hochbahn red (deep, the sun brightens it)
ROOF_WHITE = [0.86, 0.86, 0.86, 1.0]

# lamp glass: (material name, test(x, y, z) in source coordinates, function or "ind" = by side)
LAMPS = [
    ("Color_002", lambda x, y, z: x < 0.6 and abs(z - CENTRE_Z) > 0.6, "head"),       # headlight lenses
    ("Color_F19", lambda x, y, z: x < 0.6, "head"),                                    # headlight reflectors
    ("Color_B09", lambda x, y, z: x < 0.6, "ind"),                                     # front indicators
    ("Color_A06", lambda x, y, z: x > 11.9, "tail"),                                   # rear lamps + top markers
    ("Color_A05", lambda x, y, z: x > 11.9, "brake"),                                  # brake lenses
    ("Color_B01", lambda x, y, z: x > 11.9 and y < 1.0, "ind"),                        # rear corner indicators
]
SUFFIX = {"head": "__light_head", "tail": "__light_tail", "brake": "__light_brake",
          "ind_l": "__indicator_l", "ind_r": "__indicator_r"}
# livery: material name -> new base colour (None = keep)
LIVERY = {"<LightSeaGreen>1": HVV_RED, "Color_D01": HVV_RED}
LIVERY_BODY = "Color_C01"            # white body panels: red below 2.75 m, white roof above
SKIP_MATERIALS = {"logo%20RATP", "ratp-logo"}      # RATP stickers: dropped, the body is underneath
WINDOW_GLASS = {"[Translucent_Glass_Gray]1": ([0.035, 0.04, 0.045, 0.82], 0.05)}   # dark tinted windows
PLATE_IMAGE, DISPLAY_IMAGE = 1, 2      # source image index of the licence plate / destination display
PLATE_TEXT = "HH-HB 389"
DISPLAY_ROUTE, DISPLAY_TEXT = "6", "U Hauptbahnhof"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"


def plate_png(w, h):
    """German EU plate: blue band with D, black text on white."""
    from PIL import Image, ImageDraw, ImageFont
    im = Image.new("RGB", (w, h), (245, 245, 240))
    d = ImageDraw.Draw(im)
    band = int(w * 0.09)
    d.rectangle([0, 0, band, h], fill=(20, 60, 160))
    f_small = ImageFont.truetype(FONT, int(h * 0.32))
    d.text((band / 2, h * 0.78), "D", font=f_small, fill=(255, 255, 255), anchor="mm")
    for k in range(12):   # EU stars
        import math
        a = k / 12 * 2 * math.pi
        cx, cy = band / 2 + math.cos(a) * band * 0.28, h * 0.32 + math.sin(a) * band * 0.28
        d.ellipse([cx - 1.5, cy - 1.5, cx + 1.5, cy + 1.5], fill=(250, 210, 0))
    size = int(h * 0.82)
    f = ImageFont.truetype(FONT, size)
    while d.textlength(PLATE_TEXT, font=f) > (w - band) * 0.92 and size > 10:
        size -= 1
        f = ImageFont.truetype(FONT, size)
    d.text((band + (w - band) / 2, h / 2), PLATE_TEXT, font=f, fill=(15, 15, 15), anchor="mm")
    d.rectangle([0, 0, w - 1, h - 1], outline=(20, 20, 20), width=2)
    return im


def display_png(w, h):
    """Amber LED destination display: route box + destination, dot matrix."""
    from PIL import Image, ImageDraw, ImageFont
    big = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(big)
    f = ImageFont.truetype(FONT, int(h * 0.86))
    route_w = int(w * 0.16)
    d.text((route_w / 2, h / 2), DISPLAY_ROUTE, font=f, fill=255, anchor="mm")
    size = int(h * 0.7)
    f2 = ImageFont.truetype(FONT, size)
    while d.textlength(DISPLAY_TEXT, font=f2) > (w - route_w) * 0.95 and size > 8:
        size -= 1
        f2 = ImageFont.truetype(FONT, size)
    d.text((route_w + (w - route_w) / 2, h / 2), DISPLAY_TEXT, font=f2, fill=255, anchor="mm")
    im = Image.new("RGB", (w, h), (8, 6, 4))
    px, src = im.load(), big.load()
    pitch = 3
    for y in range(1, h - 1, pitch):
        for x in range(1, w - 1, pitch):
            on = src[x, y] > 110
            c = (255, 150, 10) if on else (28, 18, 6)
            px[x, y] = c
            px[x + 1, y] = c
            px[x, y + 1] = c
            px[x + 1, y + 1] = c
    return im


def png_bytes(im):
    b = io.BytesIO()
    im.save(b, format="PNG")
    return b.getvalue()


def load(path):
    p = Path(path)
    if p.suffix.lower() == ".zip":
        with zipfile.ZipFile(p) as z:
            name = [n for n in z.namelist() if n.lower().endswith(".glb")][0]
            data = z.read(name)
        return GLTF2.load_from_bytes(data)
    return GLTF2().load(str(p))


def accessor(g, blob, i):
    a = g.accessors[i]
    bv = g.bufferViews[a.bufferView]
    dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a.componentType]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a.type]
    off = (bv.byteOffset or 0) + (a.byteOffset or 0)
    isz = np.dtype(dt).itemsize
    stride = bv.byteStride or n * isz
    if stride == n * isz:
        return np.frombuffer(blob, dtype=dt, count=n * a.count, offset=off).reshape(a.count, n).astype(np.float64 if dt == np.float32 else np.int64)
    return np.array([np.frombuffer(blob, dtype=dt, count=n, offset=off + k * stride) for k in range(a.count)])


def node_matrix(nd):
    if nd.matrix:
        return np.array(nd.matrix, dtype=np.float64).reshape(4, 4).T
    T = np.eye(4); R = np.eye(4); S = np.eye(4)
    if nd.translation:
        T[:3, 3] = nd.translation
    if nd.rotation:
        x, y, z, w = nd.rotation
        R[:3, :3] = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    if nd.scale:
        S[0, 0], S[1, 1], S[2, 2] = nd.scale
    return T @ R @ S


def main():
    src = sys.argv[1]
    out_dir = Path(sys.argv[2] if len(sys.argv) > 2 else Path(__file__).resolve().parents[2] / "game/assets/consim/bus_citaro")
    g = load(src)
    blob = g.binary_blob()
    # source -> game: x_g = CENTRE_Z - z, y_g = y, z_g = x - axle midpoint (a rotation, det +1)
    mid = (AXLES_X[0] + AXLES_X[1]) * 0.5
    G = np.array([[0, 0, -1, CENTRE_Z], [0, 1, 0, 0], [1, 0, 0, -mid], [0, 0, 0, 1]], dtype=np.float64)

    groups = {}   # (material index, function) -> lists
    def add(mat, fn, P, N, UV):
        k = (mat, fn)
        gr = groups.setdefault(k, {"P": [], "N": [], "UV": [], "uv": UV is not None})
        gr["P"].append(P); gr["N"].append(N)
        gr["UV"].append(UV if UV is not None else np.zeros((len(P), 2)))

    def walk(n, M):
        W = M @ node_matrix(g.nodes[n])
        nd = g.nodes[n]
        if nd.mesh is not None:
            for p in g.meshes[nd.mesh].primitives:
                if p.mode not in (None, 4) or p.material is None:
                    continue   # SketchUp edge lines / unassigned
                if (g.materials[p.material].name or "") in SKIP_MATERIALS:
                    continue
                v = accessor(g, blob, p.attributes.POSITION)
                idx = accessor(g, blob, p.indices).ravel() if p.indices is not None else np.arange(len(v))
                vs = (W @ np.c_[v, np.ones(len(v))].T).T[:, :3]
                if p.attributes.NORMAL is not None:
                    nrm = accessor(g, blob, p.attributes.NORMAL)
                    nrm = (np.linalg.inv(W[:3, :3]).T @ nrm.T).T
                else:
                    nrm = None
                uv = accessor(g, blob, p.attributes.TEXCOORD_0) if p.attributes.TEXCOORD_0 is not None else None
                tri = idx.reshape(-1, 3)
                if np.linalg.det(W[:3, :3]) < 0:
                    tri = tri[:, [0, 2, 1]]
                mname = g.materials[p.material].name or ""
                for t in tri:
                    P = vs[t]
                    if nrm is not None:
                        N = nrm[t]
                    else:
                        fn_ = np.cross(P[1] - P[0], P[2] - P[0]); N = np.tile(fn_ / (np.linalg.norm(fn_) + 1e-12), (3, 1))
                    c = P.mean(0)
                    fn = ""
                    for lm, test, f in LAMPS:
                        if mname == lm and test(*c):
                            fn = f
                            if f == "ind":
                                fn = "ind_l" if c[2] > CENTRE_Z else "ind_r"   # source +z = vehicle left
                            break
                    add(p.material, fn, P, N, uv[t] if uv is not None else None)
        for ch in nd.children or []:
            walk(ch, W)

    for r in g.scenes[g.scene or 0].nodes:
        walk(r, np.eye(4))

    # ---- write the new glTF ------------------------------------------------------------------
    out = {"asset": {"version": "2.0", "generator": "tiefbau-tycoon citaro_import.py"},
           "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "bus_citaro", "children": [1]}, {"name": "body", "mesh": 0}],
           "meshes": [{"name": "body", "primitives": []}], "materials": [], "accessors": [], "bufferViews": [],
           "buffers": [], "images": [], "textures": [], "samplers": [{"magFilter": 9729, "minFilter": 9987}]}
    buf = bytearray()

    def view(data, target=None):
        while len(buf) % 4:
            buf.append(0)
        off = len(buf); buf.extend(data)
        bv = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            bv["target"] = target
        out["bufferViews"].append(bv)
        return len(out["bufferViews"]) - 1

    def acc(arr, typ, comp, target, minmax=False):
        a = {"bufferView": view(arr.tobytes(), target), "componentType": comp, "count": len(arr), "type": typ}
        if minmax:
            a["min"] = arr.min(0).tolist(); a["max"] = arr.max(0).tolist()
        out["accessors"].append(a)
        return len(out["accessors"]) - 1

    img_map = {}
    for i, im in enumerate(g.images):
        bv = g.bufferViews[im.bufferView]
        data = blob[(bv.byteOffset or 0):(bv.byteOffset or 0) + bv.byteLength]
        mime = im.mimeType
        if i in (PLATE_IMAGE, DISPLAY_IMAGE):
            from PIL import Image
            w, h = Image.open(io.BytesIO(data)).size
            data = png_bytes(plate_png(w, h) if i == PLATE_IMAGE else display_png(w, h))
            mime = "image/png"
        out["images"].append({"bufferView": view(data), "mimeType": mime})
        img_map[i] = len(out["images"]) - 1
    for t in g.textures:
        out["textures"].append({"source": img_map[t.source], "sampler": 0})

    mat_index = {}
    def material(mi, fn, roof):
        key = (mi, fn, roof)
        if key in mat_index:
            return mat_index[key]
        m = g.materials[mi]
        name = m.name or "mat%d" % mi
        pbr = m.pbrMetallicRoughness
        col = list(pbr.baseColorFactor) if pbr and pbr.baseColorFactor else [1, 1, 1, 1]
        tex = pbr.baseColorTexture.index if pbr and pbr.baseColorTexture else None
        if name in LIVERY:
            col = LIVERY[name]
        if name == LIVERY_BODY:
            col = ROOF_WHITE if roof else HVV_RED
        low = name.lower()
        metal, rough = 0.0, 0.55
        if "metal" in low or "alumin" in low:
            metal, rough = 0.8, 0.35
        elif name in WINDOW_GLASS:
            col, rough = WINDOW_GLASS[name]
        elif "glass" in low or fn:
            rough = 0.15
        elif "charcoal" in low or "black" in low:
            rough = 0.85
        elif col == HVV_RED or name == LIVERY_BODY:
            rough = 0.35
        md = {"name": name + (SUFFIX[fn] if fn else "") + ("_roof" if roof else ""),
              "pbrMetallicRoughness": {"baseColorFactor": col, "metallicFactor": metal, "roughnessFactor": rough},
              "doubleSided": bool(m.doubleSided)}
        if tex is not None:
            md["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex}
        if m.alphaMode and m.alphaMode != "OPAQUE" and not fn:
            md["alphaMode"] = m.alphaMode
        if fn:
            md["extras"] = {"light_function": fn}
        out["materials"].append(md)
        mat_index[key] = len(out["materials"]) - 1
        return mat_index[key]

    # roof split for the white body material happens per triangle
    tri_total = 0
    final = {}
    for (mi, fn), gr in groups.items():
        P = np.concatenate([np.asarray(x) for x in gr["P"]]).reshape(-1, 3, 3)
        N = np.concatenate([np.asarray(x) for x in gr["N"]]).reshape(-1, 3, 3)
        UV = np.concatenate([np.asarray(x) for x in gr["UV"]]).reshape(-1, 3, 2)
        roof = np.zeros(len(P), bool)
        if g.materials[mi].name == LIVERY_BODY:
            roof = P[:, :, 1].mean(1) > 2.75
        for r in (False, True):
            sel = roof == r
            if not sel.any():
                continue
            final[(mi, fn, r)] = (P[sel], N[sel], UV[sel], gr["uv"])
    for (mi, fn, r), (P, N, UV, has_uv) in final.items():
        n = len(P) * 3
        pg = (G @ np.c_[P.reshape(-1, 3), np.ones(n)].T).T[:, :3].astype(np.float32)
        ng = (G[:3, :3] @ N.reshape(-1, 3).T).T
        ng = (ng / (np.linalg.norm(ng, axis=1, keepdims=True) + 1e-12)).astype(np.float32)
        prim = {"attributes": {"POSITION": acc(pg, "VEC3", 5126, 34962, True), "NORMAL": acc(ng, "VEC3", 5126, 34962)},
                "indices": acc(np.arange(n, dtype=np.uint32), "SCALAR", 5125, 34963), "material": material(mi, fn, r)}
        if has_uv:
            prim["attributes"]["TEXCOORD_0"] = acc(UV.reshape(-1, 2).astype(np.float32), "VEC2", 5126, 34962)
        out["meshes"][0]["primitives"].append(prim)
        tri_total += len(P)
    out["buffers"].append({"byteLength": len(buf)})
    js = json.dumps(out, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    while len(buf) % 4:
        buf.append(0)
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(buf))
    glb += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(buf), 0x004E4942) + bytes(buf)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "bus_citaro.glb").write_bytes(glb)

    allp = np.concatenate([(G @ np.c_[v[0].reshape(-1, 3), np.ones(v[0].size // 3)].T).T[:, :3] for v in final.values()])
    lo, hi = allp.min(0), allp.max(0)
    fns = sorted({fn for (_, fn, _) in final if fn})
    meta = {
        "id": "bus_citaro",
        "source": "Sketchfab \"Mercedes+CITARO+II+RATP\" by moussasy.sy715, CC BY 4.0 "
                  "(https://sketchfab.com/3d-models/mercedescitaroiiratp-93010eea7663482e8f1ca17168af6d8a); "
                  "converted by tools/models/citaro_import.py, HVV livery",
        "category": "bus",
        "dimensions_m": {"length": round(hi[2] - lo[2], 3), "width": round(hi[0] - lo[0], 3), "height": round(hi[1] - lo[1], 3)},
        "triangles": int(tri_total),
        "wheels": [{"axle_z": round(z - mid, 3), "radius": WHEEL_R} for z in AXLES_X],
        "lamp_functions": fns,
        "notes": "Traffic bus, front faces -Z, origin between the axles, ground y=0. One flattened mesh "
                 "(no wheel nodes). Lamp glass split into <mat>__light_head/__light_tail/__light_brake/"
                 "__indicator_l/__indicator_r. Private use only (lives in the private asset folder).",
        "bbox_min": [round(float(x), 3) for x in lo], "bbox_max": [round(float(x), 3) for x in hi],
    }
    (out_dir / "bus_citaro.json").write_text(json.dumps(meta, indent=1))
    print("bus_citaro: %d triangles, %d primitives, %.2f MB, size %s, lamps %s" % (
        tri_total, len(out["meshes"][0]["primitives"]), len(glb) / 1e6, (hi - lo).round(2), fns))


if __name__ == "__main__":
    main()
