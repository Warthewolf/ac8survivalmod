"""hull_uv.py : the Leviathan hull's UV map made again from scratch (the user, 2026-11-10: "get rid of the saw teeth
and sort out the rest of the uv so the texture looks correct").

The fused hull (LEV_HULL.001) is the Iowa's hull at the Alicorn's length wearing the Alicorn's two sheets (ALC_a
forward, ALC_b aft). Its shape is nowhere the Alicorn's (under 1 % of its area lies on any Alicorn source mesh), and
its UVs were copied over face by face from whatever Alicorn surface lay nearest: 4,245 UV islands, a third of the
area in islands under 100 m2, saw-tooth triangles wherever two neighbours took different pieces, the deck-edge rail
and slots running across the sides in offset bits. Patching fragments (the first hull_uv.py) left the saw teeth
where two big pieces met and changed the tone of what it touched. So nothing of the copied map is kept: every ALC
face is mapped by where it is and which way it faces, one rule per kind of surface, so neighbours always agree:

  decks (faces looking up): the Alicorn's own deck layout, which is a plain top-down projection (fitted from the
      source mesh ALC_HULL in the design file's SRC collection: u = cu - x / 400, v = cv - y / 400, sheet a forward
      of x = -52 m, sheet b aft of it); the hull is cut along that line so the join is straight. Only where the
      Alicorn has flat deck under the spot (its flight deck, 13 m either side of the middle): outside that its sheets
      hold its rounded shoulders and side skin folded out (the rail, the slots, draft marks), which this wider deck
      used to wear; there the deck is plain plating, laid top-down to and fro like the shell's strip. The decks are
      cut into 5 m cells first, so each cell is wholly one or the other;
  the sides above the water: the Alicorn's own side skin, as the user asked ("the hull sides must remain as the
      alicorns"): each face takes what the source mesh ALC_HULL shows on its plain hull side (the stretch between its
      pods' roots and its nose, worn to and fro along this longer hull, mirrored at each turn) as far up its skin
      from the waterline, so the rail line, the rows of slots and the draft marks run straight along this hull;
  the shell under them (the sides' foot, everything under the water, and where the Alicorn has no side to give: the
      transom, past its bow): one continuous strip of the aft sheet's plain plating a side,
      along the hull's outline (its arc length in plan, round the stern to the centreline) and up it; the hull is
      longer than any clean stretch of plating, so the strip runs to and fro over one stretch (mirrored at each turn,
      which joins without a seam), the hull cut at the turns; above the water the strip goes up by height, under it
      by girth (down the side and in under the bottom to the keel), squeezed there;
  the rest (steps, coamings, fittings' sides): each flat-ish group laid square on plain plating (a box mapping).
model_tanacorn.py calls fix(HULL).
"""
import bpy, bmesh, math
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

DENS = 400.0          # m per UV unit: the sheets' own density
DECK = {"ALC_a": (0.86617, 0.84480), "ALC_b": (-0.12728, 0.81111)}   # the Alicorn's deck layout: (cu, cv) a sheet
X_SPLIT = -52.0       # sheet a's deck forward of here, sheet b's aft (the Alicorn's own split)
X_STERN = -288.0      # aft of here the shell is followed round the transom
WATER = -2.0          # the shell's strip splits here: by height above, by girth under
FOLD = 0.62           # the stretch of plating the strip runs to and fro over, in UV units (248 m)
DECK_FOLD = 0.05      # the outer deck's plating runs to and fro across the ship too, over this much (20 m)
UNDER = 0.2           # a coloured deck marking with this share of it under the ship's own upper works is taken off
CELL = 5.0            # m: the decks are cut into cells this big at most
SQUEEZE = 2.5         # the under-water strip's squeeze down the girth (plain plating, seldom seen)
PLATE = (0.21, 0.63)  # the plating's luma and metal on both sheets (measured from the files), rough 0.05-0.16


class Sheet:
    def __init__(self, mat):
        imgs = {n.image.name[-8:-4].split("_")[-1]: n.image for n in mat.node_tree.nodes
                if n.type == "TEX_IMAGE" and n.image}
        d, m = imgs["D"], imgs["MREC"]
        self.W, self.H = d.size

        def px(img):
            a = np.empty(self.W * self.H * 4, dtype=np.float32)
            img.pixels.foreach_get(a)
            return a.reshape(self.H, self.W, 4)[:, :, :3]
        D, R = px(d), px(m)                                         # (a byte image's pixels: the file's own values)
        self.luma = D @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
        self.sat = D.max(axis=2) - D.min(axis=2)
        self.odd = ((np.abs(self.luma - PLATE[0]) > 0.05) | (self.sat > 0.08) | (R[:, :, 1] > 0.3)
                    | (np.abs(R[:, :, 0] - PLATE[1]) > 0.2))
        self.I, self.L1, self.L2 = (np.zeros((self.H + 1, self.W + 1)) for _ in range(3))
        self.I[1:, 1:] = self.odd.cumsum(0).cumsum(1)
        self.L1[1:, 1:] = self.luma.astype(np.float64).cumsum(0).cumsum(1)
        self.L2[1:, 1:] = (self.luma.astype(np.float64) ** 2).cumsum(0).cumsum(1)
        self.cache = {}

    def window(self, w_uv, h_uv):
        """the cleanest stretch of plain plating of this size: (u0, v0, share of odd pixels); among clean ones, the one
        with the most of the plating's own panel lines in it (the liveliest), not a blank patch of grime"""
        w = min(self.W - 8, int(math.ceil(w_uv * self.W / 16.0)) * 16 + 16)
        h = min(self.H - 8, int(math.ceil(h_uv * self.H / 16.0)) * 16 + 16)
        if (w, h) not in self.cache:
            best, live = None, None
            xs = np.arange(0, self.W - w, 4)
            box = lambda T, y: T[y + h, xs + w] - T[y, xs + w] - T[y + h, xs] + T[y, xs]
            for y in range(0, self.H - h, 4):
                c = box(self.I, y)
                k = int(c.argmin())
                if best is None or c[k] < best[0]:
                    best = (float(c[k]), int(xs[k]), y)
                var = box(self.L2, y) / (w * h) - (box(self.L1, y) / (w * h)) ** 2
                var[c > 0.002 * w * h] = -1.0
                k = int(var.argmax())
                if var[k] >= 0 and (live is None or var[k] > live[0]):
                    live = (float(var[k]), int(xs[k]), y, float(c[k]))
            if live:
                best = (live[3], live[1], live[2])
            self.cache[w, h] = ((best[1] + 8) / self.W, (best[2] + 8) / self.H, best[0] / (w * h))
        return self.cache[w, h]

    def colour(self, u, v):
        return float(self.sat[int(v % 1 * self.H) % self.H, int(u % 1 * self.W) % self.W])


def fix(HULL, log=print):
    me = HULL.data
    # the hull's own centreline: in the design file the Iowa's hull (with its turrets and upper works) lies 0.4 deg
    # askew to the world's x axis, its middle 2.3 m to starboard at the stern and as far to port at the bow, while the
    # Alicorn's source mesh is square to it. Everything here is laid along the hull's own centreline: by the world's
    # axes the deck's runway sat off centre under the turrets (the user's marked render, 2026-11-10: "Why is the deck
    # off centre"). M takes the mesh into the hull's frame: x along its centreline, y from it.
    W0 = HULL.matrix_world
    pts = np.array([W0 @ v.co for v in me.vertices])
    sx, sm = [], []
    for x0 in np.arange(-300.0, 300.1, 10.0):
        k = (np.abs(pts[:, 0] - x0) < 3.0) & (pts[:, 2] > 5.0) & (pts[:, 2] < 12.0)
        if k.sum() > 20:
            sx.append(x0)
            sm.append((pts[k, 1].min() + pts[k, 1].max()) / 2.0)
    skew, shift = (float(c) for c in np.polyfit(sx, sm, 1))
    M = Matrix.Rotation(-math.atan(skew), 4, "Z") @ Matrix.Translation((0.0, -shift, 0.0)) @ W0
    R3, Mi = M.to_3x3(), M.inverted()
    log("hull UVs: the hull's centreline is y = %.4f x %+.2f m in the design file (%.2f deg askew): everything is laid "
        "along it" % (skew, shift, math.degrees(math.atan(skew))))
    slots = [s.material.name if s.material else "" for s in HULL.material_slots]
    ia, ib = slots.index("ALC_a"), slots.index("ALC_b")
    plate = Sheet(HULL.material_slots[ib].material)
    sheets = {ia: Sheet(HULL.material_slots[ia].material), ib: plate}
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active

    def cut(co, no, decks=False):
        """the ALC faces (or only those looking up) cut along a plane (world), so a join that must be straight is"""
        fs = [f for f in bm.faces if f.material_index in (ia, ib) and (not decks or (R3 @ f.normal).z > 0.75)]
        geom = fs + list({e for f in fs for e in f.edges}) + list({v for f in fs for v in f.verts})
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-4, plane_co=Mi @ Vector(co),
                               plane_no=(R3.transposed() @ Vector(no)).normalized(), clear_inner=False,
                               clear_outer=False)

    def tree_of():
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        bm.verts.index_update()
        bm.faces.index_update()
        return BVHTree.FromPolygons([M @ v.co for v in bm.verts], [[v.index for v in f.verts] for f in bm.faces])

    n0 = len(bm.faces)
    cut((X_SPLIT, 0, 0), (1, 0, 0))
    cut((0, 0, WATER), (0, 0, 1))
    # ---------------------------------------------------------------- the hull's outline in plan (port; it is symmetric)
    tree = tree_of()

    def side_hit(x, z):
        hit = tree.ray_cast(Vector((x, 200.0, z)), Vector((0, -1, 0)))
        return hit[0].y if hit[0] is not None else None

    def ring_hit(th, z):
        d = Vector((math.cos(th), math.sin(th), 0.0))
        hit = tree.ray_cast(Vector((X_STERN, 0.0, z)) + d * 150.0, -d)
        return hit[0] if hit[0] is not None else None
    hx, hy, wy = [], [], []
    for x in np.arange(X_STERN, 345.0, 1.0):
        y = side_hit(x, 4.0)
        if y is not None:
            hx.append(x)
            hy.append(y)
            wy.append(side_hit(x, WATER - 0.05) or 0.0)                   # (the half breadth just under the water)
    hx, hy, wy = np.array(hx), np.array(hy), np.array(wy)
    arc = np.concatenate(([0.0], np.cumsum(np.hypot(np.diff(hx), np.diff(hy)))))
    rt, rxy, rw = [], [], []
    for deg in np.arange(90.0, 180.01, 1.0):
        p = ring_hit(math.radians(deg), 6.0)
        if p is not None:
            rt.append(math.radians(deg))
            rxy.append((p.x, p.y))
            q = ring_hit(math.radians(deg), WATER - 0.05)
            rw.append(math.hypot(q.x - X_STERN, q.y) if q is not None else 0.0)
    rt, rxy, rw = np.array(rt), np.array(rxy), np.array(rw)
    ra = np.concatenate(([0.0], np.cumsum(np.hypot(np.diff(rxy[:, 0]), np.diff(rxy[:, 1])))))
    s_stern = float(ra[-1])
    turns = []                                                            # the strip's turns: stations along the hull
    k = 1
    while k * FOLD * DENS - s_stern < arc[-1] - 1.0:
        s = k * FOLD * DENS - s_stern
        assert s > 1.0, "a turn of the strip falls on the stern: change FOLD"
        turns.append(float(np.interp(s, arc, hx)))
        k += 1
    for x in turns:
        cut((x, 0, 0), (1, 0, 0))
    x_aft = min((M @ v.co).x for v in bm.verts)
    deck_turns = [x_aft + k * FOLD * DENS for k in (1, 2, 3) if x_aft + k * FOLD * DENS < hx[-1]]
    for x in deck_turns:                                                  # the outer deck's plating: its turns
        cut((x, 0, 0), (1, 0, 0), decks=True)
    for y in (0.0, DECK_FOLD * DENS, -DECK_FOLD * DENS, 2 * DECK_FOLD * DENS, -2 * DECK_FOLD * DENS):
        cut((0, y, 0), (0, 1, 0), decks=True)
    # the decks cut into cells of CELL m at most: a deck face is the layout's or plating's whole, and some were 20 m
    # across (the yellow bar at the runway's end lost a corner to one)
    for x in np.arange(math.ceil(x_aft / CELL) * CELL, hx[-1] + CELL, CELL):
        cut((float(x), 0, 0), (1, 0, 0), decks=True)
    for y in np.arange(-40.0, 40.01, CELL):
        if abs(y) > 0.01:
            cut((0, float(y), 0), (0, 1, 0), decks=True)
    ref = bpy.data.objects.get("ALC_HULL")                                # the Alicorn's own decks, in plan
    plan = None
    if ref:
        rb = bmesh.new()
        rb.from_mesh(ref.data)
        rb.verts.ensure_lookup_table()
        rn = ref.matrix_world.to_3x3()
        plan = BVHTree.FromPolygons([ref.matrix_world @ v.co for v in rb.verts],
                                    [[v.index for v in f.verts] for f in rb.faces if (rn @ f.normal).z > 0.9])
        # ... and its side skin: the source triangulated, its UV islands, and the height up its side by arc length
        bmesh.ops.triangulate(rb, faces=rb.faces)
        rb.verts.ensure_lookup_table()
        rb.faces.ensure_lookup_table()
        ruv = rb.loops.layers.uv["UVMap"] if "UVMap" in rb.loops.layers.uv else rb.loops.layers.uv.active
        RW = [ref.matrix_world @ v.co for v in rb.verts]
        rtree = BVHTree.FromPolygons(RW, [[v.index for v in f.verts] for f in rb.faces])
        rslot = [ia if (sl.material and sl.material.name == "ALC_a") else ib for sl in ref.material_slots]
        rpar = list(range(len(rb.faces)))

        def rfind(i):
            while rpar[i] != i:
                rpar[i] = rpar[rpar[i]]
                i = rpar[i]
            return i
        redge = {}
        for f in rb.faces:
            ls = f.loops
            for i in range(3):
                a, b = ls[i], ls[(i + 1) % 3]
                ka = tuple(round(c, 3) for c in RW[a.vert.index])
                kb = tuple(round(c, 3) for c in RW[b.vert.index])
                key, ua, ub = ((ka, kb), a[ruv].uv, b[ruv].uv) if ka < kb else ((kb, ka), b[ruv].uv, a[ruv].uv)
                for g, va, vb in redge.setdefault(key, []):
                    if rb.faces[g].material_index == f.material_index and (va - ua).length < 0.002 \
                            and (vb - ub).length < 0.002:
                        rpar[rfind(f.index)] = rfind(g)
                redge[key].append((f.index, ua.copy(), ub.copy()))
        GX, GZ = np.arange(-332.0, 322.01, 2.0), np.arange(0.0, 19.01, 0.25)
        # the stretch of the Alicorn's side that is plain hull side: forward of where its pods' roots swell out of it
        # (a second rail starts there) and aft of its rounded nose (the rail hooks round it). This hull's sides wear
        # that stretch to and fro along their whole length (mirrored at each turn: the rail runs on unbroken)
        wide = []
        for x in np.arange(0.0, 316.0, 1.0):
            h = rtree.ray_cast(Vector((x, 200.0, 4.0)), Vector((0, -1, 0)))
            wide.append((x, h[0].y if h[0] is not None else 0.0))
        wide = np.array(wide)
        mid = float(np.median(wide[(wide[:, 0] > 100) & (wide[:, 0] < 250), 1]))
        plain = wide[np.abs(wide[:, 1] - mid) < 3.0, 0]
        run, best = [plain[0]], []
        for x in plain[1:]:                                              # the longest unbroken run of such stations
            if x - run[-1] > 1.5:
                best, run = max(best, run, key=len), []
            run.append(x)
        best = max(best, run, key=len)
        SRC0, SRC1 = float(best[0]) + 4.0, float(best[-1]) - 4.0

        def station(x):
            m = (x - SRC0) % (2 * (SRC1 - SRC0))
            return SRC0 + (m if m <= SRC1 - SRC0 else 2 * (SRC1 - SRC0) - m)

        def heights(sgn):
            """T[i][j]: the height on the Alicorn's side at station GX[i] that lies GZ[j] m up its skin from the
            waterline (its shoulder rolls inboard above the rail: by height alone the skin would be squeezed there)"""
            T = np.full((len(GX), len(GZ)), np.nan)
            for i, x in enumerate(GX):
                ys = []
                for z in GZ:
                    h = rtree.ray_cast(Vector((x, 200.0 * sgn, z)), Vector((0, -sgn, 0)))
                    if h[0] is None:
                        break
                    ys.append(h[0].y)
                if len(ys) >= 4:
                    up = np.concatenate(([0.0], np.cumsum(np.hypot(np.diff(GZ[:len(ys)]), np.diff(ys)))))
                    T[i] = np.interp(GZ, up, GZ[:len(ys)], right=np.nan)
            return T
        ZT = {1.0: heights(1.0), -1.0: heights(-1.0)}

        def zeff(x, z, sgn):
            if z <= 0.0:
                return z
            T = ZT[sgn]
            fi, fj = (x - GX[0]) / 2.0, z / 0.25
            i, j = int(math.floor(fi)), int(math.floor(fj))
            if i < 0 or j < 0 or i >= len(GX) - 1 or j >= len(GZ) - 1:
                return None
            tx, tz = fi - i, fj - j
            q = (T[i, j] * (1 - tx) + T[i + 1, j] * tx) * (1 - tz) + (T[i, j + 1] * (1 - tx) + T[i + 1, j + 1] * tx) * tz
            return None if np.isnan(q) else float(q)

        def skin(p, sgn):
            """the Alicorn's side skin at a point's station and height: (uv, its island, its sheet) or None"""
            x = station(p.x)
            ze = zeff(x, p.z, sgn)
            if ze is None:
                return None
            loc, n, idx, _ = rtree.ray_cast(Vector((x, 200.0 * sgn, ze)), Vector((0, -sgn, 0)))
            if idx is None or abs(n.y) < 0.2:
                return None
            ls = rb.faces[idx].loops
            w = poly_3d_calc([RW[lp.vert.index] for lp in ls], loc)
            return (sum((lp[ruv].uv * wi for lp, wi in zip(ls, w)), Vector((0.0, 0.0))), rfind(idx),
                    rslot[rb.faces[idx].material_index])
    memo = {}

    def on_alicorn_deck(p):
        k = (round(p.x, 1), round(p.y, 1))
        if k not in memo:
            memo[k] = plan is None or plan.ray_cast(Vector((p.x, p.y, 500.0)), Vector((0, 0, -1)))[0] is not None
        return memo[k]

    # ---------------------------------------------------------------- the faces as they are now
    tree = tree_of()
    P = [M @ v.co for v in bm.verts]
    K = [(round(p.x, 3), round(p.y, 3), round(p.z, 3)) for p in P]
    F = [f for f in bm.faces if f.material_index in (ia, ib)]
    inF = set(F)
    cen = {f: sum((P[v.index] for v in f.verts), Vector()) / len(f.verts) for f in F}
    nor = {f: (R3 @ f.normal).normalized() for f in F}
    area = {f: f.calc_area() for f in F}

    def edges_of(f):
        ls = f.loops
        for i in range(len(ls)):
            a, b = K[ls[i].vert.index], K[ls[(i + 1) % len(ls)].vert.index]
            yield (a, b) if a < b else (b, a)
    E = {}
    for f in F:
        for k in edges_of(f):
            E.setdefault(k, []).append(f)

    # ---------------------------------------------------------------- 1. the shell: sides, and all under the water
    seeds = []
    for x in np.arange(X_STERN, 345.0, 1.0):
        for side in (1.0, -1.0):
            for z in (-6.0, 2.0, 4.0, 7.0):
                hit = tree.ray_cast(Vector((x, 200.0 * side, z)), Vector((0, -side, 0)))
                if hit[2] is not None and bm.faces[hit[2]] in inF:
                    seeds.append(bm.faces[hit[2]])
    for deg in np.arange(90.0, 270.01, 1.0):
        d = Vector((math.cos(math.radians(deg)), math.sin(math.radians(deg)), 0.0))
        for z in (5.0, 6.0, 8.0):
            hit = tree.ray_cast(Vector((X_STERN, 0.0, z)) + d * 150.0, -d)
            if hit[2] is not None and bm.faces[hit[2]] in inF and cen[bm.faces[hit[2]]].x < X_STERN:
                seeds.append(bm.faces[hit[2]])
    shell, stack = set(seeds), list(seeds)
    while stack:
        f = stack.pop()
        for k in edges_of(f):
            for g in E[k]:
                if g not in shell and nor[g].dot(nor[f]) > 0.77 and (abs(nor[g].z) < 0.8 or cen[g].z < WATER):
                    shell.add(g)
                    stack.append(g)

    def along(p):
        """a point's place along the strip: the arc length of the hull's outline from the stern's centreline"""
        if p.x >= X_STERN:
            return s_stern + float(np.interp(p.x, hx, arc)) + max(0.0, p.x - hx[-1])
        th = math.atan2(abs(p.y), p.x - X_STERN)
        return s_stern - float(np.interp(th, rt, ra))

    def girth(p):
        """under the water: down the side from the waterline and in under the bottom to the keel"""
        if p.x >= X_STERN:
            return (WATER - p.z) + max(0.0, float(np.interp(p.x, hx, wy)) - abs(p.y))
        th = math.atan2(abs(p.y), p.x - X_STERN)
        return (WATER - p.z) + max(0.0, float(np.interp(th, rt, rw)) - math.hypot(p.x - X_STERN, p.y))

    def fold(t):
        m = t % (2 * FOLD)
        return m if m <= FOLD else 2 * FOLD - m
    hi = [f for f in shell if cen[f].z >= WATER]
    lo = [f for f in shell if cen[f].z < WATER]
    top_z = max(P[v.index].z for f in hi for v in f.verts)
    deep = max(girth(P[v.index]) for f in lo for v in f.verts)
    for band, name, up, height in ((hi, "above the water", lambda p: (p.z - WATER) / DENS, (top_z - WATER) / DENS),
                                   (lo, "under it", lambda p: girth(p) / DENS / SQUEEZE, deep / DENS / SQUEEZE)):
        u0, v0, odd = plate.window(FOLD, height)
        for f in band:
            f.material_index = ib
            for lp in f.loops:
                p = P[lp.vert.index]
                lp[uv].uv = (u0 + fold(along(p) / DENS), v0 + max(0.0, up(p)))
        log("hull UVs: the shell %s: %d faces, %.0f m2, one strip a side %.0f m long (%.0f m of it round the stern) and "
            "%.1f m %s, to and fro over %.0f m of plain plating at uv (%.3f, %.3f), %.2f %% of it not plain"
            % (name, len(band), sum(area[f] for f in band), s_stern + arc[-1], s_stern,
               height * DENS * (1.0 if band is hi else SQUEEZE), "up" if band is hi else "of girth", FOLD * DENS, u0, v0,
               100 * odd))
    log("hull UVs: the strip turns at x = %s m (the hull is cut there, and at the deck sheets' join x = %.0f m and the "
        "waterline strip's foot z = %.0f m: %d faces more)" % (", ".join("%.1f" % x for x in turns), X_SPLIT, WATER,
                                                               len(bm.faces) - n0))

    # the sides above the water: the Alicorn's own side skin (the user, 2026-11-10: "the hull sides must remain as the
    # alicorns"): each face takes what the Alicorn's side shows at its station and as far up from the waterline (the
    # rail line, the rows of slots, the draft marks, straight along this hull as along the Alicorn's). A face whose
    # corners fall in two of the Alicorn's UV islands takes the island of its middle. Where the Alicorn has no side to
    # give (past its bow, the transom, a face looking fore or aft) the plating strip stays.
    worn = 0
    if ref:
        for f in hi:
            if abs(nor[f].y) < 0.5:
                continue
            sgn = 1.0 if nor[f].y > 0 else -1.0
            c = skin(cen[f], sgn)
            if c is None:
                continue
            new = []
            for lp in f.loops:
                p = P[lp.vert.index]
                h = skin(p, sgn)
                if h is None or h[1] != c[1] or h[2] != c[2]:
                    h = skin(cen[f] + (p - cen[f]) * 0.9, sgn)
                    if h is None or h[1] != c[1] or h[2] != c[2]:
                        new = None
                        break
                    new.append(c[0] + (h[0] - c[0]) / 0.9)
                else:
                    new.append(h[0])
            if new is None:
                continue
            f.material_index = c[2]
            for lp, q in zip(f.loops, new):
                lp[uv].uv = q
            worn += 1
        log("hull UVs: the sides above the water: %d of %d shell faces there wear the Alicorn's own side skin (the rail, "
            "the slots, the draft marks), taken from ALC_HULL's plain hull side (its x %.0f..%.0f m, to and fro along "
            "this hull) at each face's height up the skin; the rest (the transom, faces looking fore or aft) stay on the "
            "plating strip" % (worn, len(hi), SRC0, SRC1))

    # ---------------------------------------------------------------- 2. the decks: the Alicorn's own top-down layout
    decks = [f for f in F if f not in shell and nor[f].z > 0.75]
    out, off, outer = 0, set(), []
    du0, dv0, dodd = plate.window(FOLD, DECK_FOLD)

    def dfold(t):
        m = t % (2 * DECK_FOLD)
        return m if m <= DECK_FOLD else 2 * DECK_FOLD - m
    for f in decks:
        mid = Vector(((math.floor(cen[f].x / CELL) + 0.5) * CELL, (math.floor(cen[f].y / CELL) + 0.5) * CELL, 0.0))
        if not on_alicorn_deck(mid):                                     # (the cell's middle decides for every face in
            outer.append(f)                                              # the cell, so the two meet along the cuts;
                                                                         # past the flat deck's edge the sheet is
                                                                         # plating for 9 m more, then the rail)
            f.material_index = ib
            for lp in f.loops:
                p = P[lp.vert.index]
                lp[uv].uv = (du0 + fold((p.x - x_aft) / DENS), dv0 + dfold(abs(p.y) / DENS))
            continue
        mi = ia if cen[f].x >= X_SPLIT else ib
        cu, cv = DECK[slots[mi]]
        new = [(cu - P[lp.vert.index].x / DENS, cv - P[lp.vert.index].y / DENS) for lp in f.loops]
        if not all(-1e-4 <= q[0] <= 1.0001 and -1e-4 <= q[1] <= 1.0001 for q in new):
            out += 1
            off.add(f)
            continue
        f.material_index = mi
        for lp, q in zip(f.loops, new):
            lp[uv].uv = q
    log("hull UVs: the decks: %d faces, %.0f m2, on the Alicorn's top-down deck layout (sheet a forward of x = %.0f m, "
        "sheet b aft)%s; %d faces, %.0f m2, with no Alicorn deck under them on plain plating (top-down, to and fro, at "
        "uv (%.3f, %.3f), %.2f %% of it not plain)"
        % (len(decks) - out - len(outer), sum(area[f] for f in decks) - sum(area[f] for f in outer), X_SPLIT,
           "; %d off the sheet, laid with the rest" % out if out else "", len(outer), sum(area[f] for f in outer),
           du0, dv0, 100 * dodd))

    # a coloured deck marking that lies partly under the ship's own upper works (the Alicorn's hazard-striped lift
    # outline, half under turret C's barbette and the superstructure) is taken off: its cells take the deck as it is
    # some cells further along (the runway's lines run fore and aft, so they carry straight on)
    moved = 0
    outside = set(outer)
    on_layout = [f for f in decks if f not in off and f not in outside]

    def colour_of(f, du=0.0):
        sh = sheets[f.material_index]
        pts = [lp[uv].uv for lp in f.loops]
        c = sum(pts, Vector((0.0, 0.0))) / len(pts)
        mids = [(pts[i] + pts[(i + 1) % len(pts)]) / 2 for i in range(len(pts))]
        return max(sh.colour(q.x + du, q.y) for q in [c] + [c + (q - c) * t for q in pts + mids for t in (0.5, 0.97)])
    marked = [f for f in on_layout if colour_of(f) > 0.15]
    grid = {}
    for f in marked:
        grid.setdefault((int(cen[f].x // 12), int(cen[f].y // 12)), []).append(f)
    seen = set()
    for f in marked:
        if f in seen:
            continue
        grp, st = [], [f]
        seen.add(f)
        while st:
            g = st.pop()
            grp.append(g)
            gx, gy = int(cen[g].x // 12), int(cen[g].y // 12)
            for h in (h for i in (-1, 0, 1) for j in (-1, 0, 1) for h in grid.get((gx + i, gy + j), [])):
                if h not in seen and (cen[h] - cen[g]).length < 12.0 and abs(cen[h].z - cen[g].z) < 1.5:
                    seen.add(h)
                    st.append(h)
        under = sum(area[g] for g in grp
                    if tree.ray_cast(cen[g] + Vector((0, 0, 0.3)), Vector((0, 0, 1)), 80.0)[0] is not None)
        share = under / sum(area[g] for g in grp)
        log("hull UVs: a coloured deck marking at x %.0f..%.0f m, y %.0f..%.0f m: %.0f %% of it under the upper works: %s"
            % (min(cen[g].x for g in grp), max(cen[g].x for g in grp), min(cen[g].y for g in grp),
               max(cen[g].y for g in grp), 100 * share, "taken off" if share >= UNDER else "kept"))
        if share < UNDER:
            continue                                                     # (open to the sky: a marking to keep)
        # every cell of the deck in the marking's box goes with it, so no corner of it is left behind
        x0 = math.floor(min(cen[g].x for g in grp) / CELL) * CELL
        x1 = (math.floor(max(cen[g].x for g in grp) / CELL) + 1) * CELL
        y0 = math.floor(min(cen[g].y for g in grp) / CELL) * CELL
        y1 = (math.floor(max(cen[g].y for g in grp) / CELL) + 1) * CELL
        zm = float(np.median([cen[g].z for g in grp]))                   # (its own deck level only: there are decks
        box = [g for g in on_layout if x0 <= cen[g].x <= x1 and y0 <= cen[g].y <= y1     # under decks)
               and abs(cen[g].z - zm) < 1.5 and g.material_index == grp[0].material_index]
        for k in (k for n in range(1, 61) for k in (n, -n)):
            du = k * CELL / DENS
            if all(colour_of(g, du) < 0.1 and all(0.0 <= lp[uv].uv.x + du <= 1.0 for lp in g.loops) for g in box):
                for g in box:
                    for lp in g.loops:
                        lp[uv].uv.x += du
                moved += len(box)
                break
    if moved:
        log("hull UVs: %d deck cells round a coloured marking half under the upper works moved along the deck" % moved)

    # ---------------------------------------------------------------- 3. the rest: box-mapped onto plain plating
    rest = [f for f in F if f not in shell and (nor[f].z <= 0.75 or f in off)]

    def axis(f):
        n = nor[f]
        i = max(range(3), key=lambda k: abs(n[k]))
        return i, n[i] > 0
    cls = {f: axis(f) for f in rest}
    seen, groups = set(), []
    for f in rest:
        if f in seen:
            continue
        grp, st = [], [f]
        seen.add(f)
        while st:
            g = st.pop()
            grp.append(g)
            for k in edges_of(g):
                for h in E[k]:
                    if h in cls and h not in seen and cls[h] == cls[f]:
                        seen.add(h)
                        st.append(h)
        groups.append(grp)
    AX = ((1, 2), (0, 2), (0, 1))                                        # the two world axes a group is laid along
    laid = split = 0

    def lay(fs, i):
        a, b = AX[i]
        pts = [(P[lp.vert.index][a], P[lp.vert.index][b]) for f in fs for lp in f.loops]
        a0, b0 = min(p[0] for p in pts), min(p[1] for p in pts)
        wu, hv = (max(p[0] for p in pts) - a0) / DENS, (max(p[1] for p in pts) - b0) / DENS
        if wu > 0.9 or hv > 0.9:
            return False
        u0, v0, odd = plate.window(wu, hv)
        if odd > 0.002:
            return False
        for f in fs:
            f.material_index = ib
            for lp in f.loops:
                p = P[lp.vert.index]
                lp[uv].uv = (u0 + (p[a] - a0) / DENS, v0 + (p[b] - b0) / DENS)
        return True
    for grp in groups:
        i = cls[grp[0]][0]
        if lay(grp, i):
            laid += 1
        else:                                                            # too big for any clean stretch: face by face
            split += 1
            for f in grp:
                lay([f], i)
    log("hull UVs: the rest: %d faces, %.0f m2, in %d flat-ish groups laid square on plain plating%s"
        % (len(rest), sum(area[f] for f in rest), laid + split,
           " (%d of them too big for one stretch: laid face by face)" % split if split else ""))

    # ---------------------------------------------------------------- what is left: joins between neighbours that differ
    def uv_at(f):
        return {K[lp.vert.index]: lp[uv].uv.copy() for lp in f.loops}
    broken = total = 0.0
    for k, fs in E.items():
        if len(fs) != 2 or nor[fs[0]].dot(nor[fs[1]]) < 0.94:
            continue
        ln = (Vector(k[0]) - Vector(k[1])).length
        total += ln
        a, b = uv_at(fs[0]), uv_at(fs[1])
        if fs[0].material_index != fs[1].material_index or (a[k[0]] - b[k[0]]).length > 0.002 \
                or (a[k[1]] - b[k[1]]).length > 0.002:
            broken += ln
    log("hull UVs: of %.0f km of smooth edges on the ALC faces, %.1f %% still join two different mappings (the deck "
        "sheets' join, the strips' feet, plating laid against plating)" % (total / 1000.0, 100.0 * broken / max(total, 1)))
    bm.to_mesh(me)
    bm.free()
    me.update()
    return {"centreline": {"skew": round(skew, 5), "shift_m": round(shift, 3)}, "shell_faces": len(shell), "side_faces_in_the_alicorns_skin": worn, "deck_marking_cells_moved": moved, "deck_faces_on_the_layout": len(decks) - out - len(outer),
            "deck_faces_on_plating": len(outer), "rest_faces": len(rest),
            "strip_turns_x_m": [round(x, 1) for x in turns],
            "smooth_edges_joining_two_mappings_pct": round(100.0 * broken / max(total, 1), 2)}
