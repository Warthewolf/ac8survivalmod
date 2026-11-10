"""hull_uv.py : the Leviathan hull's UV map put right (the user, 2026-11-10: "Fix the UV Map on the hull too").

The fused hull (LEV_HULL.001) wears the Alicorn's two sheets (ALC_a forward, ALC_b aft), but its faces took their UVs
piecemeal: 4,245 UV islands, a third of the area in islands under 100 m2, a quarter of the smooth edges broken. On the
bow's sides the Alicorn's deck-edge rail and slots run across the plating in offset pieces and the teal strips are cut;
the decks have saw-tooth triangles where neighbours use different parts of a sheet. Three passes, each only ever
writing plating or the deck's own layout:

  1. the bow's shell sides (forward of X_BOW): one continuous strip a side, along the hull (plan arc length -> u) and
     up it (z -> v), on one clean stretch of plain plating of the aft sheet (the same plating; the forward sheet has
     no clean stretch that long), so those faces become ALC_b; and the stern's shell aft of X_STERN the same way,
     round the transom from beam to beam;
  2. deck fragments: every sheet's deck is a top-down projection, so the biggest groups of deck faces sharing one
     mapping are the deck's layout; an uncoloured deck face outside them takes the layout of the group it touches
     (rejected where that would land on a coloured marking);
  3. stretched faces (a texel smeared over 4 times longer one way than the other, or no UV area at all) that show
     plain plating anyway: each patch of them laid flat at the sheets' own density on clean plain plating of the aft
     sheet. (Small islands that already show plating evenly are left: laying them again only changed their tone.)
Faces that show a coloured or bright detail are never touched. model_tanacorn.py calls fix(HULL).
"""
import bmesh, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

DENS = 400.0          # m per UV unit: the sheets' own density on the hull (measured: 390-460)
X_BOW = 60.0          # the bow's shell forward of here is mapped again as one strip
X_STERN = -288.0      # and the stern's shell aft of here (behind the pods), round the transom
WATER = -2.0          # the strip's split: above the water, and the underwater sides (seen when the bow rears up)
SMALL = 150.0         # m2: a UV island under this is a fragment
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

    def look(self, u, v):
        x, y = int(u % 1 * self.W) % self.W, int(v % 1 * self.H) % self.H
        return float(self.luma[y, x]), float(self.sat[y, x]), bool(self.odd[y, x])


def fix(HULL, log=print):
    me, M = HULL.data, HULL.matrix_world
    R3 = M.to_3x3()
    slots = [s.material.name if s.material else "" for s in HULL.material_slots]
    ia, ib = slots.index("ALC_a"), slots.index("ALC_b")
    sheet = {ia: Sheet(HULL.material_slots[ia].material), ib: Sheet(HULL.material_slots[ib].material)}
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()
    uv = bm.loops.layers.uv.active
    P = [M @ v.co for v in bm.verts]
    K = [(round(p.x, 3), round(p.y, 3), round(p.z, 3)) for p in P]
    F = [f for f in bm.faces if f.material_index in (ia, ib)]
    cen = {f: sum((P[v.index] for v in f.verts), Vector()) / len(f.verts) for f in F}
    nor = {f: (R3 @ f.normal).normalized() for f in F}
    area = {f: f.calc_area() for f in F}                              # (the hull's own scale is 1)

    def edges_of(f):
        ls = f.loops
        for i in range(len(ls)):
            a, b = ls[i], ls[(i + 1) % len(ls)]
            ka, kb = K[a.vert.index], K[b.vert.index]
            yield ((ka, kb), a, b) if ka < kb else ((kb, ka), b, a)
    E = {}
    for f in F:
        for k, a, b in edges_of(f):
            E.setdefault(k, []).append((f, a, b))
    at = {}
    for f in F:
        for v in f.verts:
            at.setdefault(K[v.index], []).append(f)

    def stretched(f):
        ls = f.loops
        for k in range(len(ls) - 2):
            p0, e1, e2 = P[ls[0].vert.index], P[ls[k + 1].vert.index], P[ls[k + 2].vert.index]
            e1, e2 = e1 - p0, e2 - p0
            n = e1.cross(e2)
            if n.length < 1e-9:
                continue
            ax = e1.normalized()
            ay = n.normalized().cross(ax)
            A = np.array([[e1.dot(ax), e1.dot(ay)], [e2.dot(ax), e2.dot(ay)]])
            u0 = ls[0][uv].uv
            U = np.array([[ls[k + 1][uv].uv.x - u0.x, ls[k + 1][uv].uv.y - u0.y],
                          [ls[k + 2][uv].uv.x - u0.x, ls[k + 2][uv].uv.y - u0.y]])
            if abs(np.linalg.det(U)) < 1e-14:
                return True
            s = np.linalg.svd(np.linalg.solve(U, A), compute_uv=False)
            if s[0] / max(s[1], 1e-9) > 4.0:
                return True
        return False

    def looks(f):
        """the face as it shows now: (lowest luma, highest luma, highest saturation, all plain plating)"""
        sh = sheet[f.material_index]
        pts = [lp[uv].uv for lp in f.loops]
        c = sum(pts, Vector((0, 0))) / len(pts)
        pts = [c] + [c + (p - c) * 0.6 for p in pts]
        got = [sh.look(p.x, p.y) for p in pts]
        return min(g[0] for g in got), max(g[0] for g in got), max(g[1] for g in got), not any(g[2] for g in got)

    def lands_ok(sh, new, bright):
        """a deck face's new place on the sheet: not on a coloured marking, nor on a bright one (a roundel cut off by
        the face's edge) unless the layout's faces touching it are bright too (a white line running on across it)"""
        c = sum(new) / len(new)
        got = [sh.look(*q) for q in [c] + [c + (q - c) * t for q in new for t in (0.35, 0.7, 0.95)]]
        return max(g[1] for g in got) <= 0.12 and (max(g[0] for g in got) <= 0.45 or bright)

    def bright_round(f, member, i):
        return any(looks(g)[1] > 0.45 for v in f.verts for g in at[K[v.index]] if member.get(g) == i)

    # ------------------------------------------------------------------ 1. the bow's shell sides: one strip a side
    tree = BVHTree.FromPolygons(P, [[v.index for v in f.verts] for f in bm.faces])
    inF = set(F)
    seeds, half = [], []
    for x in np.arange(X_BOW + 2.0, 345.0, 1.0):
        for side in (1.0, -1.0):
            for z in (2.0, 4.0, 7.0):
                hit = tree.ray_cast(Vector((x, 200.0 * side, z)), Vector((0, -side, 0)))
                if hit[2] is not None and bm.faces[hit[2]] in inF:
                    seeds.append(bm.faces[hit[2]])
                    if side > 0 and z == 4.0:
                        half.append((x, hit[0].y))
    shell, stack = set(seeds), list(seeds)
    while stack:
        f = stack.pop()
        for k, _, _ in edges_of(f):
            for g, _, _ in E[k]:
                if (g not in shell and cen[g].x > X_BOW and abs(nor[g].z) < 0.8 and nor[g].dot(nor[f]) > 0.77
                        and nor[g].y * nor[f].y > -0.2):
                    shell.add(g)
                    stack.append(g)
    hx = np.array([h[0] for h in half])
    hy = np.array([h[1] for h in half])
    arc = np.concatenate(([0.0], np.cumsum(np.hypot(np.diff(hx), np.diff(hy)))))
    xs_ = [P[v.index].x for f in shell for v in f.verts]
    tip = (max(xs_) - hx[-1]) if max(xs_) > hx[-1] else 0.0             # (the stem, past the last side hit)

    def strips(faces, s_of, length, what):
        for name, band in (("above the water", [f for f in faces if cen[f].z >= WATER]),
                           ("under it", [f for f in faces if cen[f].z < WATER])):
            if not band:
                continue
            zs = [P[v.index].z for f in band for v in f.verts]          # (two strips: no clean stretch of plating
            z0, z1 = min(zs), max(zs)                                   # is tall enough for the side keel to deck)
            got = None
            for kv in (1.0, 1.15, 1.3):                                 # (a little squeezed up the side if it must be)
                w = sheet[ib].window(length / DENS, (z1 - z0) / DENS / kv)
                if got is None or w[2] < got[1][2] - 1e-6:
                    got = (kv, w)
                if w[2] < 0.002:
                    break
            kv, (u0, v0, odd) = got
            for f in band:
                f.material_index = ib
                for lp in f.loops:
                    p = P[lp.vert.index]
                    lp[uv].uv = (u0 + s_of(p) / DENS, v0 + (p.z - z0) / DENS / kv)
            log("hull UVs: 1. %s %s: %d faces, %.0f m2, %.0f m along, z %.1f..%.1f m, one strip on plain plating at "
                "uv (%.3f, %.3f), %.2f %% of it not plain%s"
                % (what, name, len(band), sum(area[f] for f in band), length, z0, z1, u0, v0, 100 * odd,
                   "" if kv == 1.0 else ", squeezed %.2f up the side" % kv))
    strips(shell, lambda p: float(np.interp(p.x, hx, arc)) + max(0.0, p.x - hx[-1]), arc[-1] + tip,
           "the bow's shell sides (each side)")
    # the stern's shell, round the transom from beam to beam: its place along the strip is the arc length of the
    # stern's outline at the angle it is seen at from a point on the centreline
    ang = lambda p: math.atan2(p.y, p.x - X_STERN) % (2 * math.pi)
    seeds, ring = [], []
    for th in np.radians(np.arange(95.0, 265.1, 1.0)):
        d = Vector((math.cos(th), math.sin(th), 0.0))
        for z in (5.0, 6.0, 8.0):
            hit = tree.ray_cast(Vector((X_STERN, 0.0, z)) + d * 150.0, -d)
            if hit[2] is not None and bm.faces[hit[2]] in inF and cen[bm.faces[hit[2]]].x < X_STERN:
                seeds.append(bm.faces[hit[2]])
                if z == 6.0:
                    ring.append((float(th), hit[0].x, hit[0].y))
    stern, stack = set(seeds), list(seeds)
    while stack:
        f = stack.pop()
        for k, _, _ in edges_of(f):
            for g, _, _ in E[k]:
                if g not in stern and cen[g].x < X_STERN and abs(nor[g].z) < 0.8 and nor[g].dot(nor[f]) > 0.77:
                    stern.add(g)
                    stack.append(g)
    if stern and len(ring) > 8:
        rt = np.array([r[0] for r in ring])
        ra = np.concatenate(([0.0], np.cumsum(np.hypot(np.diff([r[1] for r in ring]), np.diff([r[2] for r in ring])))))
        strips(stern, lambda p: float(np.interp(ang(p), rt, ra)), float(ra[-1]), "the stern's shell (beam to beam)")
    shell |= stern

    # ------------------------------------------------------------------ 2. deck fragments onto the deck's own layout
    rest = [f for f in F if f not in shell]
    bad = {f for f in rest if stretched(f)}

    def top_affine(fs):
        A = [(P[lp.vert.index].x, P[lp.vert.index].y, 1.0) for f in fs for lp in f.loops]
        U = [tuple(lp[uv].uv) for f in fs for lp in f.loops]
        return np.linalg.lstsq(np.array(A), np.array(U), rcond=None)[0]
    laid = adopted = teeth = 0
    for mi in (ia, ib):
        tops = sorted((f for f in rest if f.material_index == mi and nor[f].z > 0.9 and f not in bad),
                      key=lambda f: -area[f])
        refs, member = [], {}                                            # groups of deck faces sharing one mapping
        RX = np.zeros((len(tops), 3, 2))
        for f in tops:
            X = top_affine([f])
            d = np.abs(RX[:len(refs)] - X)
            hit = np.nonzero((d[:, :2].max(axis=(1, 2)) < 2e-4) & (d[:, 2].max(axis=1) < 0.02))[0] if refs else []
            if len(hit):
                refs[hit[0]][1].append(f)
                member[f] = int(hit[0])
            else:
                member[f] = len(refs)
                RX[len(refs)] = X
                refs.append((X, [f]))
        big = {i for i, (_, fs) in enumerate(refs) if sum(area[f] for f in fs) > 600.0}
        layout = {i: top_affine(refs[i][1][:400]) for i in big}
        laid += len(big)
        sh = sheet[mi]
        for f in [f for f in rest if f.material_index == mi and nor[f].z > 0.9 and member.get(f) not in big]:
            if looks(f)[2] > 0.12:                                       # a coloured detail of its own: left alone
                continue
            near = {}
            for v in f.verts:
                for g in at[K[v.index]]:
                    if member.get(g) in big and abs(cen[g].z - cen[f].z) < 1.0:
                        near[member[g]] = near.get(member[g], 0.0) + area[g]
            if not near:
                continue
            to = max(near, key=near.get)
            X = layout[to]
            new = [np.array((P[lp.vert.index].x, P[lp.vert.index].y, 1.0)) @ X for lp in f.loops]
            if not all(0.0 <= q[0] <= 1.0 and 0.0 <= q[1] <= 1.0 for q in new):
                continue
            if not lands_ok(sh, new, bright_round(f, member, to)):
                continue                                                 # (it would land on a marking)
            for lp, q in zip(f.loops, new):
                lp[uv].uv = (float(q[0]), float(q[1]))
            bad.discard(f)
            member[f] = to
            adopted += 1
        # saw teeth: where two layouts meet along a row of triangles the faces alternate between them. A face with
        # more of its edges on a bigger layout than on its own goes over to it (never back), so the join runs straight
        size = {i: sum(area[f] for f in refs[i][1]) for i in big}
        mine = [f for f in rest if f.material_index == mi and nor[f].z > 0.9 and member.get(f) in big]
        for _ in range(6):
            moved = 0
            for f in mine:
                own, cnt = member[f], {}
                for k, _, _ in edges_of(f):
                    for g, _, _ in E[k]:
                        if g is not f and member.get(g) in big and nor[g].z > 0.9 and abs(cen[g].z - cen[f].z) < 1.0:
                            cnt[member[g]] = cnt.get(member[g], 0) + 1
                to = max((i for i in cnt if i != own and size[i] > size[own]), key=lambda i: cnt[i], default=None)
                if to is None or cnt[to] < 2 or cnt[to] <= cnt.get(own, 0) or looks(f)[2] > 0.12:
                    continue
                new = [np.array((P[lp.vert.index].x, P[lp.vert.index].y, 1.0)) @ layout[to] for lp in f.loops]
                if not all(0.0 <= q[0] <= 1.0 and 0.0 <= q[1] <= 1.0 for q in new):
                    continue
                if not lands_ok(sh, new, bright_round(f, member, to)):
                    continue
                for lp, q in zip(f.loops, new):
                    lp[uv].uv = (float(q[0]), float(q[1]))
                member[f] = to
                moved += 1
            teeth += moved
            if not moved:
                break
    log("hull UVs: 2. the decks: %d layouts found; %d deck faces outside them laid on the layout they touch, %d saw "
        "teeth between two layouts straightened" % (laid, adopted, teeth))

    # ------------------------------------------------------------------ 3. plating fragments laid flat on plain plating
    par = {f: f for f in rest}

    def find(f):
        while par[f] is not f:
            par[f] = par[par[f]]
            f = par[f]
        return f
    for k, lst in E.items():
        lst = [e for e in lst if e[0] in par]
        for i in range(len(lst)):
            for j in range(i + 1, len(lst)):
                (f, a1, b1), (g, a2, b2) = lst[i], lst[j]
                if (f.material_index == g.material_index and (a1[uv].uv - a2[uv].uv).length < 0.002
                        and (b1[uv].uv - b2[uv].uv).length < 0.002):
                    par[find(f)] = find(g)
    isl = {}
    for f in rest:
        isl.setdefault(find(f), []).append(f)
    patches = []
    for fs in isl.values():
        if sum(area[f] for f in fs) < SMALL and sum(area[f] for f in fs if f in bad) > 0.3 * sum(area[f] for f in fs):
            patches.append(fs)                                           # a fragment that is mostly smeared: all of it
        else:                                                            # else only the stretched faces, by themselves
            seen = set()
            for f in fs:
                if f in bad and f not in seen:
                    grp, st = [], [f]
                    seen.add(f)
                    while st:
                        g = st.pop()
                        grp.append(g)
                        for k, _, _ in edges_of(g):
                            for h, _, _ in E[k]:
                                if h in bad and h not in seen and find(h) is find(f):
                                    seen.add(h)
                                    st.append(h)
                    patches.append(grp)
    done = faces = 0
    shb = sheet[ib]
    for fs in patches:
        fs = [f for f in fs if area[f] > 1e-6]
        if not fs:
            continue
        see = [looks(f) for f in fs]
        if not all(s[3] or (f in bad and s[2] < 0.08 and 0.13 < s[0] and s[1] < 0.29) for f, s in zip(fs, see)):
            continue                                                     # (it shows something other than plating)
        n = sum((nor[f] * area[f] for f in fs), Vector())
        if n.length < 1e-9:
            continue
        n.normalize()
        if abs(n.z) > 0.7:
            a = (Vector((1, 0, 0)) - n * n.x).normalized()
            b = n.cross(a)
        else:
            b = (Vector((0, 0, 1)) - n * n.z).normalized()
            a = b.cross(n)
        pts = [(P[lp.vert.index].dot(a), P[lp.vert.index].dot(b)) for f in fs for lp in f.loops]
        a0, b0 = min(p[0] for p in pts), min(p[1] for p in pts)
        wu, hv = (max(p[0] for p in pts) - a0) / DENS, (max(p[1] for p in pts) - b0) / DENS
        u0, v0, odd = shb.window(wu, hv)
        if odd > 0.002 or wu > 0.9 or hv > 0.9:
            continue
        for f in fs:
            f.material_index = ib
            for lp in f.loops:
                p = P[lp.vert.index]
                lp[uv].uv = (u0 + (p.dot(a) - a0) / DENS, v0 + (p.dot(b) - b0) / DENS)
        done += 1
        faces += len(fs)
    log("hull UVs: 3. %d patches of smeared plating (%d faces) laid flat on plain plating" % (done, faces))
    left = sum(1 for f in rest if stretched(f))
    bm.to_mesh(me)
    bm.free()
    me.update()
    return {"bow_and_stern_shell_faces": len(shell), "deck_faces_laid": adopted, "deck_saw_teeth": teeth, "smeared_patches": done,
            "smeared_faces_laid": faces, "stretched_faces_left": left}
