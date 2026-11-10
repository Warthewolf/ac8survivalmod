"""audit_tanacorn.py : Blender 3.3, THE TANACORN's model looked over from every side for holes and misfits (the user,
2026-11-10: "go over the entire model and make sure theres no hidden holes that got messed up when you straightened
the ship").

  blender -b <model dir>/Tanacorn_model.blend -P tools/tanicorn/audit_tanacorn.py -- <out dir>

Every mesh of the ship (not the prototypes' line-up, not the sea) goes into one tree, and parallel rays a quarter of a
metre apart are shot at it from six sides: from above, from below, from port, from starboard, from ahead, from astern.
For each ray: what it hits first, where, and whether it hits that face from behind. Then, per view:
  - MIRROR: the ship is the same either side of y = 0, so a ray and its mirror image must hit at the same depth. Where
    they differ by more than TOL the cells are grouped into patches and listed with what was hit on each side (a hole,
    a part that sits differently on one side, or a detail one side has and the other hasn't).
  - INSIDE: a ray that hits a face from behind is looking at the inside of something: through a hole, or at a sheet
    with nothing behind it. Listed by patch as well.
  - OPENINGS: the same test from 36 directions round her (the square-on views cannot see past what stands in
    front): patches of inside faces that are thick in every direction, i.e. the inside of a closed part on show.
Writes <out dir>/audit.json (every patch), audit_<view>.png (the mismatch maps: white = same, red = differs, blue =
seen from inside) and prints a summary. It judges nothing: each patch is looked at (a render, or the numbers) and put
down as a fault or as the design's own.
"""
import bpy, sys, os, json, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("build/tanicorn/audit")
os.makedirs(OUT, exist_ok=True)
STEP = float(os.environ.get("TANA_AUDIT_STEP", "0.25"))
TOL = float(os.environ.get("TANA_AUDIT_TOL", "0.30"))
MIN_CELLS = int(os.environ.get("TANA_AUDIT_MIN", "24"))     # a patch smaller than this (1.5 m2 at 0.25 m) is not listed
bpy.context.scene.frame_set(1)
dg = bpy.context.evaluated_depsgraph_get()

objs = [o for o in bpy.data.objects if o.type == "MESH" and o.users_collection and o.users_collection[0].name != "SRC"
        and not o.name.endswith("_proto") and o.name != "SEA" and not o.hide_render]
ONLY = tuple(x for x in os.environ.get("TANA_AUDIT_ONLY", "").split(",") if x)     # name prefixes: only these meshes
if ONLY:
    objs = [o for o in objs if o.name.startswith(ONLY)]
verts, polys, owner, normals = [], [], [], []
for k, o in enumerate(objs):
    me = o.evaluated_get(dg).to_mesh()
    W = o.matrix_world
    N = W.to_3x3().inverted().transposed()
    base = len(verts)
    verts += [W @ v.co for v in me.vertices]
    for p in me.polygons:
        polys.append([base + i for i in p.vertices])
        owner.append(k)
        normals.append((N @ p.normal).normalized())
    o.evaluated_get(dg).to_mesh_clear()
tree = BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)
V = np.array(verts)
lo, hi = V.min(axis=0) - 2.0, V.max(axis=0) + 2.0
print("audit: %d meshes, %d faces; the ship spans x %.1f..%.1f, y %.1f..%.1f, z %.1f..%.1f"
      % (len(objs), len(polys), lo[0] + 2, hi[0] - 2, lo[1] + 2, hi[1] - 2, lo[2] + 2, hi[2] - 2))
HALF = max(abs(lo[1]), abs(hi[1]))


def shoot(origin_of, d, na, nb):
    """a grid of rays: depth along the ray, the owner, and whether the face was hit from behind"""
    depth = np.full((na, nb), np.nan, np.float32)
    who = np.full((na, nb), -1, np.int32)
    back = np.zeros((na, nb), bool)
    dv = Vector(d)
    for a in range(na):
        for b in range(nb):
            loc, nor, idx, dist = tree.ray_cast(origin_of(a, b), dv)
            if idx is not None:
                depth[a, b], who[a, b] = dist, owner[idx]
                back[a, b] = normals[idx].dot(dv) > 0.05
    return depth, who, back


xs = np.arange(lo[0], hi[0], STEP)
ys = np.arange(STEP / 2, HALF, STEP)                        # one side; the other is its mirror
zs = np.arange(lo[2], hi[2], STEP)
VIEWS = {}
# from above / below: a = x, b = y (port +y, starboard -y)
for name, z0, d in (("top", hi[2] + 5, (0, 0, -1)), ("bottom", lo[2] - 5, (0, 0, 1))):
    P = shoot(lambda a, b: Vector((xs[a], ys[b], z0)), d, len(xs), len(ys))
    Sd = shoot(lambda a, b: Vector((xs[a], -ys[b], z0)), d, len(xs), len(ys))
    VIEWS[name] = (P, Sd, ("x", xs), ("y", ys))
# from the sides: a = x, b = z
P = shoot(lambda a, b: Vector((xs[a], HALF + 5, zs[b])), (0, -1, 0), len(xs), len(zs))
Sd = shoot(lambda a, b: Vector((xs[a], -HALF - 5, zs[b])), (0, 1, 0), len(xs), len(zs))
VIEWS["side"] = (P, Sd, ("x", xs), ("z", zs))
# from ahead / astern: a = y, b = z
for name, x0, d in (("ahead", hi[0] + 5, (-1, 0, 0)), ("astern", lo[0] - 5, (1, 0, 0))):
    P = shoot(lambda a, b: Vector((x0, ys[a], zs[b])), d, len(ys), len(zs))
    Sd = shoot(lambda a, b: Vector((x0, -ys[a], zs[b])), d, len(ys), len(zs))
    VIEWS[name] = (P, Sd, ("y", ys), ("z", zs))


def patches(mask):
    """connected patches of a mask (4-neighbours): lists of (a, b)"""
    seen = np.zeros_like(mask)
    out = []
    for a, b in zip(*np.nonzero(mask)):
        if seen[a, b]:
            continue
        todo, cells = [(a, b)], []
        seen[a, b] = True
        while todo:
            i, j = todo.pop()
            cells.append((i, j))
            for u, v in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1)):
                if 0 <= u < mask.shape[0] and 0 <= v < mask.shape[1] and mask[u, v] and not seen[u, v]:
                    seen[u, v] = True
                    todo.append((u, v))
        out.append(cells)
    return out


def names(who, cells):
    ids, n = np.unique([who[c] for c in cells], return_counts=True)
    return [("nothing" if i < 0 else objs[i].name) + " x%d" % c for i, c in sorted(zip(ids, n), key=lambda t: -t[1])][:4]


def save_map(name, diff, inside, hit):
    h, w = diff.shape[1], diff.shape[0]
    img = np.ones((h, w, 4), np.float32)
    img[:, :, :3] = np.where(hit.T[:, :, None], 0.82, 1.0)
    img[diff.T] = (0.9, 0.1, 0.1, 1.0)
    img[inside.T & ~diff.T] = (0.1, 0.3, 0.9, 1.0)
    im = bpy.data.images.new("audit_" + name, w, h)
    im.pixels.foreach_set(img.ravel())
    im.filepath_raw, im.file_format = os.path.join(OUT, "audit_%s.png" % name), "PNG"
    im.save()


REPORT = {}
for name, ((dp, wp, bp), (ds, ws, bs), (an, av), (bn, bv)) in VIEWS.items():
    one = np.isnan(dp) != np.isnan(ds)
    both = ~np.isnan(dp) & ~np.isnan(ds)
    diff = one | (both & (np.abs(np.nan_to_num(dp) - np.nan_to_num(ds)) > TOL))
    rows = []
    for cells in patches(diff):
        if len(cells) < MIN_CELLS:
            continue
        A, B = [c[0] for c in cells], [c[1] for c in cells]
        gap = [abs(float(dp[c]) - float(ds[c])) for c in cells if both[c]]
        rows.append({"kind": "mirror", "cells": len(cells), "area_m2": round(len(cells) * STEP * STEP, 1),
                     an: [round(float(av[min(A)]), 1), round(float(av[max(A)]), 1)],
                     bn: [round(float(bv[min(B)]), 1), round(float(bv[max(B)]), 1)],
                     "differs_m": round(max(gap), 2) if gap else None, "one_side_only": int(sum(one[c] for c in cells)),
                     "port": names(wp, cells), "starboard": names(ws, cells)})
    for side, back, who in (("port", bp, wp), ("starboard", bs, ws)):
        for cells in patches(back):
            if len(cells) < MIN_CELLS:
                continue
            A, B = [c[0] for c in cells], [c[1] for c in cells]
            rows.append({"kind": "inside", "side": side, "cells": len(cells), "area_m2": round(len(cells) * STEP * STEP, 1),
                         an: [round(float(av[min(A)]), 1), round(float(av[max(A)]), 1)],
                         bn: [round(float(bv[min(B)]), 1), round(float(bv[max(B)]), 1)], "what": names(who, cells)})
    rows.sort(key=lambda r: -r["cells"])
    REPORT[name] = rows
    save_map(name, diff, bp | bs, ~np.isnan(dp) | ~np.isnan(ds))
    m = [r for r in rows if r["kind"] == "mirror"]
    i = [r for r in rows if r["kind"] == "inside"]
    print("audit: %-7s %7d rays a side; %5d cells differ port/starboard in %3d patches (%.0f m2); seen from inside: %5d "
          "cells to port, %5d to starboard, %3d patches (%.0f m2)"
          % (name, dp.size, int(diff.sum()), len(m), sum(r["area_m2"] for r in m), int(bp.sum()), int(bs.sum()), len(i),
             sum(r["area_m2"] for r in i)))
# ---- looked INTO from every quarter. The six square-on views cannot see an opening that something stands in front of
# (the forward barbette's open front, under the guns and behind the bow's sheer: found only in a photo, 2026-11-10).
# So: rays from 36 directions round her (every 30 deg, 10 / 30 / 55 deg down) half a metre apart; every ray whose
# first hit is a face seen from behind, at a point shut in on all sides (walls in 13 of 14 directions round it: the
# inside of a closed part, not a railing's or a lattice's sheet seen from its back in the open air), marks the 1 m
# cell it lands in. Cells are joined into patches: each is somewhere the inside of a closed part can be seen from
# outside, an opening.
OB_STEP = float(os.environ.get("TANA_AUDIT_OBLIQUE_STEP", "0.5"))
AROUND = [Vector(v).normalized() for v in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1),
                                           (1, 1, 1), (1, 1, -1), (1, -1, 1), (1, -1, -1), (-1, 1, 1), (-1, 1, -1),
                                           (-1, -1, 1), (-1, -1, -1))]


def shut_in(p):
    """is this point inside a closed part: walls within 80 m in at least 13 of 14 directions round it"""
    return sum(1 for a in AROUND if tree.ray_cast(p, a, 80.0)[0] is not None) >= 13


cells = {}
corners = [Vector((x, y, z)) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
ndir = 0
for el in (10.0, 30.0, 55.0):
    for az in range(0, 360, 30):
        e, a = math.radians(el), math.radians(az)
        d = Vector((-math.cos(e) * math.cos(a), -math.cos(e) * math.sin(a), -math.sin(e)))     # the way the rays go
        u = Vector((-math.sin(a), math.cos(a), 0.0))
        v = d.cross(u).normalized()
        us, vs_, ds = [c.dot(u) for c in corners], [c.dot(v) for c in corners], [c.dot(d) for c in corners]
        start = min(ds) - 5.0
        ndir += 1
        for iu in range(int((max(us) - min(us)) / OB_STEP) + 1):
            pu = u * (min(us) + iu * OB_STEP)
            for iv in range(int((max(vs_) - min(vs_)) / OB_STEP) + 1):
                o = pu + v * (min(vs_) + iv * OB_STEP) + d * start
                loc, nor, idx, dist = tree.ray_cast(o, d)
                if idx is not None and normals[idx].dot(d) > 0.05 and loc.z > -1.0:      # (above the water)
                    if not shut_in(loc - d * 0.4):
                        continue                                    # (a sheet's back in the open air: a railing)
                    k = (int(math.floor(loc.x)), int(math.floor(loc.y)), int(math.floor(loc.z)))
                    c = cells.setdefault(k, [0, set(), {}])
                    c[0] += 1
                    c[1].add(ndir)
                    c[2][owner[idx]] = c[2].get(owner[idx], 0) + 1
seen3, openings = set(), []
for k0 in cells:
    if k0 in seen3:
        continue
    todo, group = [k0], []
    seen3.add(k0)
    while todo:
        k = todo.pop()
        group.append(k)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    n = (k[0] + dx, k[1] + dy, k[2] + dz)
                    if n in cells and n not in seen3:
                        seen3.add(n)
                        todo.append(n)
    G = np.array(group)
    size = G.max(axis=0) - G.min(axis=0) + 1
    who = {}
    for k in group:
        for o, n in cells[k][2].items():
            who[o] = who.get(o, 0) + n
    row = {"cells": len(group), "rays": int(sum(cells[k][0] for k in group)),
           "from_directions": len(set().union(*[cells[k][1] for k in group])),
           "x": [int(G[:, 0].min()), int(G[:, 0].max()) + 1], "y": [int(G[:, 1].min()), int(G[:, 1].max()) + 1],
           "z": [int(G[:, 2].min()), int(G[:, 2].max()) + 1], "thin_m": int(size.min()),
           "what": [objs[o].name + " x%d" % n for o, n in sorted(who.items(), key=lambda t: -t[1])][:3]}
    openings.append(row)
openings.sort(key=lambda r: -r["cells"])
deep = [r for r in openings if r["cells"] >= 12]
print("audit: looked into from %d directions: %d cells show the inside of a closed part, in %d patches; %d of 12 cells "
      "or more:" % (ndir, len(cells), len(openings), len(deep)))
for r in deep:
    print("audit:   x %s y %s z %s: %d cells, %d rays from %d directions | %s"
          % (r["x"], r["y"], r["z"], r["cells"], r["rays"], r["from_directions"], "; ".join(r["what"])))
REPORT["openings"] = deep
with open(os.path.join(OUT, "audit.json"), "w") as f:
    json.dump({"step_m": STEP, "tol_m": TOL, "meshes": len(objs), "views": REPORT}, f, indent=1)
print("audit: wrote", os.path.join(OUT, "audit.json"))
