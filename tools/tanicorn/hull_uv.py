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
  the shell (sides, and everything under the water): one continuous strip of the aft sheet's plain plating a side,
      along the hull's outline (its arc length in plan, round the stern to the centreline) and up it; the hull is
      longer than any clean stretch of plating, so the strip runs to and fro over one stretch (mirrored at each turn,
      which joins without a seam), the hull cut at the turns; above the water the strip goes up by height, under it
      by girth (down the side and in under the bottom to the keel), squeezed there;
  the rest (steps, coamings, fittings' sides): each flat-ish group laid square on plain plating (a box mapping).
The Alicorn's rail, slots and draft marks are not on the sides any more: they belong to its own outline, which this
hull does not have. model_tanacorn.py calls fix(HULL).
"""
import bpy, bmesh, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

DENS = 400.0          # m per UV unit: the sheets' own density
DECK = {"ALC_a": (0.86617, 0.84480), "ALC_b": (-0.12728, 0.81111)}   # the Alicorn's deck layout: (cu, cv) a sheet
X_SPLIT = -52.0       # sheet a's deck forward of here, sheet b's aft (the Alicorn's own split)
X_STERN = -288.0      # aft of here the shell is followed round the transom
WATER = -2.0          # the shell's strip splits here: by height above, by girth under
FOLD = 0.62           # the stretch of plating the strip runs to and fro over, in UV units (248 m)
DECK_FOLD = 0.05      # the outer deck's plating runs to and fro across the ship too, over this much (20 m)
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


def fix(HULL, log=print):
    me, M = HULL.data, HULL.matrix_world
    R3, Mi = M.to_3x3(), M.inverted()
    slots = [s.material.name if s.material else "" for s in HULL.material_slots]
    ia, ib = slots.index("ALC_a"), slots.index("ALC_b")
    plate = Sheet(HULL.material_slots[ib].material)
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
        rb.free()
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

    # ---------------------------------------------------------------- 2. the decks: the Alicorn's own top-down layout
    decks = [f for f in F if f not in shell and nor[f].z > 0.75]
    out, off, outer = 0, set(), []
    du0, dv0, dodd = plate.window(FOLD, DECK_FOLD)

    def dfold(t):
        m = t % (2 * DECK_FOLD)
        return m if m <= DECK_FOLD else 2 * DECK_FOLD - m
    for f in decks:
        if not on_alicorn_deck(cen[f]):                                  # (a cell's middle decides for the cell: past
            outer.append(f)                                              # the flat deck's edge the sheet is plating
                                                                         # for 9 m more, then the rail)
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
    return {"shell_faces": len(shell), "deck_faces_on_the_layout": len(decks) - out - len(outer),
            "deck_faces_on_plating": len(outer), "rest_faces": len(rest),
            "strip_turns_x_m": [round(x, 1) for x in turns],
            "smooth_edges_joining_two_mappings_pct": round(100.0 * broken / max(total, 1), 2)}
