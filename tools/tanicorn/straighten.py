"""straighten.py : Blender 3.3, the Leviathan design lined up with its own centreline (the user, 2026-11-10: "I want the
model straightened why the hell would you not line it up correctly").

  blender -b art/tanicorn/design/<file>.blend -P tools/tanicorn/straighten.py -- [save]

(And sheared: the Iowa was turned and THEN scaled more along than across, so its frames were not square to its keel:
shear_of, taken out with the turn.)
In the design files everything that came from the Iowa (the fused hull LEV_HULL*, the 16-inch and 5-inch turrets with
their guns, the CIWS) lay about 0.4 deg askew to the world's x axis, its middle 2.3 m to starboard at the stern and as
far to port at the bow, while everything from the Alicorn (the pods, the railcannon, the sub-railguns) was square to
it. The deck texture laid by the world's axes sat off centre under the turrets, and a ship 0.4 deg off her own pods is
simply wrong. This finds the hull's plane of mirror symmetry (the turn and the shift about which its vertices best
match their own mirror image) and puts it on y = 0:
  - the hull's mesh is turned and shifted (its object stays at the origin, unturned);
  - every Iowa mount standing on it (LEV_T16*, LEV_IOWA_T5*, LEV_IOWA_CIWS*: the ones not parented to another of
    them) is moved with it, and, when its own mesh is askew about its own origin (0.55 deg, the Iowa's own turn; the
    hull's is 0.44 because it was scaled more along than across), its mesh and its children (the guns' trunnions)
    are turned back by that, so a turret at rest points dead ahead or dead astern.
The Alicorn's parts were cut to fit the hull while it lay askew, so a hull turned as one rigid piece no longer fits
them (the first straightening, 2026-11-10: the bay's opening in the deck came out up to 1.4 m to starboard of its
doors, a black slot along them, and the starboard pod's fairing stood up to 1.1 m off the hull's side). So:
  - the deck round the bow's railcannon bay (CUT_ALC_SECTION) stays with the bay: the hull's vertices at deck height
    take none of the hull's move on the bay's outline and all of it at the deck's edge (8 m out at most; 0.6 m aft,
    where the forward turret's barbette begins; the gunwale and the hull's sides go whole), so the opening is square to the ship and centred on its doors;
  - the pods' fairings (CUT_ALC_SPONSON_*_FAIR) are made again for the straight hull from the un-faired pods kept in
    the file (refair: each vertex drawn in to the hull by the mean of what it and its mirror twin were for the askew
    one), so both come out mirror images with their roots in the hull's sides as they were cut.
  - where that cut had gone through the hull's side (the starboard bow, where the askew hull came inside the bay's
    box), the cut edge goes with the skin like the rest of the side and the hole it left is closed (mend_breach).
  - the forward turret's barbette, whose front the bay's after end sliced off and left open (the inside of the
    hull on show under the forward guns, in the design from the start), gets a flat front (cap_cut).
Animation is untouched (only rotations are keyed, and a turn about z before them only changes the z angle, which is
keyed on the mounts themselves as an absolute heading). Without `save` it only reports. model_tanacorn.py calls
straighten() on what it loads too, so a design file that has not been through this still gives a straight model.
"""
import bpy, sys, os, math, random
import numpy as np
from mathutils import Vector, Matrix
from mathutils.kdtree import KDTree
from mathutils.bvhtree import BVHTree

IOWA = ("LEV_T16", "LEV_IOWA_T5", "LEV_IOWA_CIWS", "LEV_G16", "LEV_IOWA_G5", "LEV_IOWA_CG")
BAY, FAIRING = "CUT_ALC_SECTION", "CUT_ALC_SPONSON"   # the Alicorn's parts cut to fit the hull
BAY_Z = 8.0                                      # the deck round the bay is above this (the hull's sides are not held)
BAY_SIDE, BAY_AFT, BAY_FWD = 2.0, 0.6, 2.0       # how far from the bay's outline the deck is back with the hull, m
PIECE = 40.0                                     # a connected piece smaller than this in plan is a fitting: it moves whole
BAY_WIDE = 8.0                                   # (to the side: as far as the deck's width allows, up to this)
ROOT, FAIR_FADE = 0.9, 6.0                       # a fairing's root: open edges this near the hull's skin; its fade, m


def symmetry(points, turn0=0.0, span=math.radians(1.2), shift_span=1.5):
    """the vertical plane of mirror symmetry of a cloud of points lying along x: (turn about z, shift in y), found by
    matching the points with their own mirror image"""
    random.seed(7)
    pts = points if len(points) <= 6000 else random.sample(points, 6000)
    kd = KDTree(len(points) if len(points) <= 60000 else 60000)
    for i, p in enumerate(points if len(points) <= 60000 else random.sample(points, 60000)):
        kd.insert(p, i)
    kd.balance()

    def miss(th, b):
        c, s = math.cos(th), math.sin(th)
        t = 0.0
        for p in pts:
            x, y = p.x, p.y - b                                     # into the candidate frame
            xr, yr = c * x + s * y, -s * x + c * y
            yr = -yr                                                # mirrored
            q = Vector((c * xr - s * yr, s * xr + c * yr + b, p.z))  # and back
            t += min(kd.find(q)[2], 2.0)
        return t / len(pts)
    best = (1e9, turn0, 0.0)
    step_t, step_b = span / 8, shift_span / 6
    for _ in range(4):                                              # coarse to fine
        th0, b0 = best[1], best[2]
        for i in range(-8, 9):
            for j in range(-6, 7):
                th, b = th0 + i * step_t, b0 + j * step_b
                e = miss(th, b)
                if e < best[0]:
                    best = (e, th, b)
        step_t, step_b = step_t / 5, step_b / 5
    return best[1], best[2], best[0]


def shear_of(points, span=0.012):
    """The shear left in a hull already lying along x: k, with x + k y the true place. The Iowa's hull was turned
    0.55 deg and THEN scaled more along than across (2.40 against 1.90), which leaves it not only askew (0.437 deg)
    but sheared: its frames no longer square to its keel, every port fitting 2 k |y| ahead of or astern of its
    starboard twin (0.22 m between the beam 5-inch mounts; the mounts' sockets showed it, 2026-11-10). Found as the
    turn is: the k at which the points best match their own mirror image."""
    random.seed(7)
    pts = points if len(points) <= 6000 else random.sample(points, 6000)
    full = points if len(points) <= 60000 else random.sample(points, 60000)
    kd = KDTree(len(full))
    for i, p in enumerate(full):
        kd.insert(p, i)
    kd.balance()

    def miss(k):                                                    # (a point's mirror twin, in the sheared frame)
        return sum(min(kd.find(Vector((p.x + 2.0 * k * p.y, -p.y, p.z)))[2], 0.5) for p in pts) / len(pts)
    best, step = (miss(0.0), 0.0), span / 8
    for _ in range(4):
        k0 = best[1]
        for i in range(-8, 9):
            e = miss(k0 + i * step)
            if e < best[0]:
                best = (e, k0 + i * step)
        step /= 5
    return best[1], best[0]


def bumpy(pts):
    """how far a ring of points is from flat: the most any lies off the plane through their middle (by Newell's normal)"""
    c = sum(pts, Vector()) / len(pts)
    n = Vector()
    for a, b in zip(pts, pts[1:] + pts[:1]):
        n += (a - c).cross(b - c)
    if n.length < 1e-12:
        return 0.0
    n.normalize()
    return max(abs((p - c).dot(n)) for p in pts)


def mend_breach(hull, rect, deck, log=print):
    """Where the hull's side came inside the bay's box when the bay was cut out of the askew hull (the starboard bow:
    the hull lay 1.6 m to port there), the cut took a wedge out of the skin: a hole under the rail between the last
    two side VLS blocks (the user's marked render, 2026-11-10: "What the hell is this hole"). On the straightened
    hull the skin stands clear of the bay, so the hole is simply closed: every closed ring of open edges in the
    hull's side beside the bay (under the deck, above BAY_Z - 2) gets a face, with its neighbour's material."""
    import bmesh
    W, me = hull.matrix_world, hull.data
    bm = bmesh.new()
    bm.from_mesh(me)

    def beside(v):
        p = W @ v.co
        d = deck(p.x)
        return (rect[0] - 5.0 < p.x < rect[1] + 8.0 and rect[3] - 1.5 < abs(p.y) < rect[3] + 6.0
                and d is not None and BAY_Z - 2.0 < p.z < d - 0.3)
    edges = [e for e in bm.edges if len(e.link_faces) == 1 and beside(e.verts[0]) and beside(e.verts[1])]
    link = {}
    for e in edges:
        for v in e.verts:
            link.setdefault(v, []).append(e)
    seen, made = set(), 0
    for e0 in edges:
        if e0 in seen:
            continue
        ring, todo = [], [e0]
        while todo:
            e = todo.pop()
            if e in seen:
                continue
            seen.add(e)
            ring.append(e)
            for v in e.verts:
                todo += link[v]
        verts = {v for e in ring for v in e.verts}
        if not (3 <= len(ring) <= 16 and len(verts) == len(ring) and all(len(link[v]) == 2 for v in verts)):
            continue                                                # (an open chain, or not one ring)
        near = ring[0].link_faces[0]
        new = bmesh.ops.holes_fill(bm, edges=ring, sides=0)["faces"]
        c = sum((W @ v.co for v in verts), Vector()) / len(verts)
        # the side is flat strakes meeting at knuckles: a face over a knuckle is cut along it (the cut that leaves the
        # two flattest pieces), until every piece is flat to a centimetre, so each lies in its own strake's plane
        todo, new = list(new), []
        while todo:
            f = todo.pop()
            vs = list(f.verts)
            if len(vs) == 3 or bumpy([v.co for v in vs]) < 0.01:
                new.append(f)
                continue
            best = None
            for i in range(len(vs)):
                for j in range(i + 2, len(vs)):
                    if i == 0 and j == len(vs) - 1:
                        continue
                    a, b = vs[i:j + 1], vs[j:] + vs[:i + 1]
                    worst = max(bumpy([v.co for v in a]), bumpy([v.co for v in b]))
                    if best is None or worst < best[0]:
                        best = (worst, vs[i], vs[j])
            g = bmesh.utils.face_split(f, best[1], best[2])[0]
            todo += [f, g]
        for f in new:
            f.material_index, f.smooth = near.material_index, near.smooth
            f.normal_update()
            out = W.to_3x3() @ f.normal
            if out.y * c.y < 0.0:                                   # (facing outboard, as the skin round it)
                f.normal_flip()
        made += len(new)
        log("straighten: %s: a hole in the side beside the bay closed (%d edges round (%.1f, %.1f, %.1f) m) with %d flat "
            "faces: %s" % (hull.name, len(ring), c.x, c.y, c.z, len(new), ", ".join(
                "%d corners, facing (%.2f, %.2f, %.2f)" % (len(f.verts), *(W.to_3x3() @ f.normal)) for f in new)))
    if made:
        bm.to_mesh(me)
        me.update()
    bm.free()
    return made


def refair(fairs, log=print):
    """The pods' fairings made again for the straight hull, from how the design made them. Each fairing is the
    Alicorn's pod cut off at |y| = 34 (CUT_ALC_SPONSON_L / _R, kept in the file: exact mirror images) with its inner
    16 m drawn in sideways to the hull, the cut edge all the way and the rest by a falling share. The hull lay askew,
    so the port pod was drawn in up to 1.8 m further than it would have been and the starboard one as much less: the
    two fairings differed port to starboard over ~1,200 m2 of their upper faces, by more than a metre in places
    (audit_tanacorn.py, 2026-11-10; moving their roots with the hull, the first two tries, bent the same wrong shapes
    further). For a straight hull each vertex is drawn in by the MEAN of what it and its mirror twin were: the hull's
    side midway between where the askew one stood to port and to starboard, by the design's own shares. Both
    fairings come out mirror images, their roots as deep in the hull's sides as they were cut. Returns the meshes
    done, or None when the un-faired pods are not in the file."""
    by = {}
    for f in fairs:
        base = f.name.split("_FAIR")[0]                            # CUT_ALC_SPONSON_L
        if base[-2:] not in ("_L", "_R") or base not in bpy.data.objects:
            return None
        by.setdefault(base[-1], (f, bpy.data.objects[base]))
    if set(by) != {"L", "R"}:
        return None

    def coords(me):
        a = np.empty(len(me.vertices) * 3, np.float64)
        me.vertices.foreach_get("co", a)
        return a.reshape(-1, 3)
    (fl, sl), (fr, sr) = by["L"], by["R"]
    aL, bL, aR, bR = coords(sl.data), coords(fl.data), coords(sr.data), coords(fr.data)
    if len(aL) != len(bL) or len(aR) != len(bR):
        return None
    m = np.array([1.0, -1.0, 1.0])

    def twins(a, b):                                               # each vertex of a: its mirror twin in b
        kd = KDTree(len(b))
        for i, q in enumerate(b):
            kd.insert(q * m, i)
        kd.balance()
        out = np.empty(len(a), np.int64)
        for i, q in enumerate(a):
            _, j, dist = kd.find(q)
            assert dist < 0.05, "the un-faired pods are not mirror images (%.3f m at %s)" % (dist, tuple(q))
            out[i] = j
        return out
    tL, tR = twins(aL, aR), twins(aR, aL)
    newL = aL + 0.5 * ((bL - aL) + (bR - aR)[tL] * m)
    newR = newL[tR] * m
    for f, new, old in ((fl, newL, bL), (fr, newR, bR)):
        f.data.vertices.foreach_set("co", new.ravel())
        f.data.update()
        d = np.abs(new - old)[:, 1]
        log("straighten: %s: made again from the un-faired pod for a straight hull: %d vertices drawn in differently, "
            "by up to %.2f m" % (f.name, int((d > 1e-3).sum()), d.max()))
    return {fl.data.name, fr.data.name}


def cap_cut(hull, cut, log=print):
    """One flat face over the opening a plane cut left in a standing piece: `cut` are the piece's vertices on the cut
    (the forward barbette's two walls and its roof where the bay's after end sliced it: a 23 x 5 m hole under the
    forward guns, in the design from the start, seen in the survey's photos 2026-11-10). The face takes the cut
    vertices that lie on the outline of them all (their convex hull in the cut's plane), faces away from the piece,
    and has the piece's material."""
    import bmesh
    if len(cut) < 3:
        return 0
    W, me = hull.matrix_world, hull.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    P = {i: W @ bm.verts[i].co for i in cut}
    c = sum(P.values(), Vector()) / len(P)
    pts = sorted(P, key=lambda i: (round(P[i].y, 3), round(P[i].z, 3)))

    def turn(o, a, b):
        return (P[a].y - P[o].y) * (P[b].z - P[o].z) - (P[a].z - P[o].z) * (P[b].y - P[o].y)
    lower, upper = [], []                                          # the corners only (strictly convex)...
    for i in pts:
        while len(lower) >= 2 and turn(lower[-2], lower[-1], i) <= 1e-6:
            lower.pop()
        lower.append(i)
    for i in reversed(pts):
        while len(upper) >= 2 and turn(upper[-2], upper[-1], i) <= 1e-6:
            upper.pop()
        upper.append(i)
    corners = lower[:-1] + upper[:-1]
    ring, seen = [], set()
    for a, b in zip(corners, corners[1:] + corners[:1]):           # ...then every cut vertex along each side, in order
        ab = Vector((P[b].y - P[a].y, P[b].z - P[a].z))
        on = []
        for i in pts:
            ai = Vector((P[i].y - P[a].y, P[i].z - P[a].z))
            t = ai.dot(ab) / ab.length_squared
            if -1e-6 <= t < 1.0 - 1e-6 and (ai - ab * t).length < 0.02:
                on.append((t, i))
        for _, i in sorted(on):
            k = (round(P[i].y, 2), round(P[i].z, 2))               # (vertices at one place: the first of them)
            if k not in seen:
                seen.add(k)
                ring.append(i)
    if len(ring) < 3:
        bm.free()
        return 0
    inner = sum((W @ v.co for v in bm.verts[ring[0]].link_faces[0].verts), Vector()) / len(bm.verts[ring[0]].link_faces[0].verts)
    near = bm.verts[ring[0]].link_faces[0]
    f = bm.faces.new([bm.verts[i] for i in ring])
    f.material_index, f.smooth = near.material_index, False
    f.normal_update()
    if (W.to_3x3() @ f.normal).dot(c - inner) < 0.0:                # (facing away from the piece it closes)
        f.normal_flip()
    uv = bm.loops.layers.uv.active
    if uv:
        for l in f.loops:
            other = next((o for o in l.vert.link_loops if o.face is not f), None)
            if other:
                l[uv].uv = other[uv].uv
    ys, zs = [P[i].y for i in ring], [P[i].z for i in ring]
    if os.environ.get("TANA_STRAIGHTEN_DEBUG"):
        log("straighten:   cut vertices %d; ring %s" % (len(cut), [tuple(round(c, 2) for c in P[i]) for i in ring]))
        log("straighten:   all cut: %s" % sorted({tuple(round(c, 1) for c in P[i]) for i in cut}))
    n = W.to_3x3() @ f.normal
    log("straighten: %s: the opening a cut left in a standing piece closed: one face of %d corners, y %.1f..%.1f, "
        "z %.1f..%.1f at x %.1f, facing (%.2f, %.2f, %.2f)" % (hull.name, len(ring), min(ys), max(ys), min(zs), max(zs), c.x, *n))
    bm.to_mesh(me)
    me.update()
    bm.free()
    return 1


def straighten(colls, log=print, apply=True):
    """every LEV_HULL* in these collections and the Iowa mounts standing on them; returns what it found"""
    if not isinstance(colls, (list, tuple)):
        colls = [colls]
    objs = [o for c in colls for o in c.all_objects]
    hulls = [o for o in objs if o.type == "MESH" and o.name.startswith("LEV_HULL")]
    if not hulls:
        log("straighten: no LEV_HULL here")
        return None
    W = hulls[0].matrix_world
    turn, shift, miss = symmetry([W @ v.co for v in hulls[0].data.vertices])
    log("straighten: %s lies %.3f deg askew, its middle y = %.4f x %+.3f m (mirror miss %.3f m)"
        % (hulls[0].name, math.degrees(turn), math.tan(turn), shift, miss))
    H = Matrix.Rotation(-turn, 4, "Z") @ Matrix.Translation((0.0, -shift, 0.0))
    shear, smiss = shear_of([H @ (W @ v.co) for v in hulls[0].data.vertices])
    log("straighten: %s is sheared by %.5f (%.3f deg: a fitting 25 m off the middle stands %.2f m from square to its "
        "twin; mirror miss %.3f m)" % (hulls[0].name, shear, math.degrees(math.atan(shear)), abs(shear) * 50.0, smiss))
    out = {"turn_deg": round(math.degrees(turn), 3), "shift_m": round(shift, 3), "shear": round(shear, 5)}
    if (abs(math.degrees(turn)) < 0.02 and abs(shift) < 0.02 and abs(shear) < 0.0004) or not apply:
        return out
    S = Matrix.Identity(4)
    S[0][1] = shear                                                 # x + k y
    H = S @ H
    done = set()
    # The pods' fairings first: made again from the un-faired pods kept in the file (refair). Only if those are not
    # there: the two fairings are one shape mirrored, each cut off where it met the askew hull, so the roots
    # go with the hull's side (fading out over FAIR_FADE) and every vertex moved is then put back ON the fairing's own
    # surface: the two fairings' surfaces laid over each other (the other one mirrored), so the starboard root finds
    # under it the stretch of surface only the port fairing kept. Vertices slide along the surface; the surface stays.
    # (The first version moved the vertices and left them: the surfaces themselves were shifted, up to 5.6 m apart in
    # height port against starboard near the roots: audit_tanacorn.py, 2026-11-10.)
    hull0, inv0 = hulls[0], hulls[0].matrix_world.inverted()
    fairs = [o for o in objs if o.type == "MESH" and o.name.startswith(FAIRING)]
    flip = Matrix.Scale(-1.0, 4, Vector((0, 1, 0)))

    def surface(port):
        """both fairings' faces as one tree on that side (the other side's mirrored)"""
        vs, ps, seen_me = [], [], set()
        for f in fairs:
            if f.data.name in seen_me:
                continue
            seen_me.add(f.data.name)
            W = f.matrix_world
            c = sum((W @ v.co for v in f.data.vertices), Vector()) / len(f.data.vertices)
            same = (c.y > 0.0) == port
            base = len(vs)
            vs += [(W @ v.co) if same else flip @ (W @ v.co) for v in f.data.vertices]
            ps += [[base + i for i in (poly.vertices if same else reversed(poly.vertices))] for poly in f.data.polygons]
        return BVHTree.FromPolygons(vs, ps, all_triangles=False, epsilon=0.0)
    remade = refair(fairs, log) if fairs else None
    if remade:
        done |= remade
    trees = {True: surface(True), False: surface(False)} if fairs and not remade else {}
    for f in fairs:
        if f.data.name in done:
            continue
        done.add(f.data.name)
        W, me = f.matrix_world, f.data
        N = W.to_3x3().inverted().transposed()
        count = {}
        for poly in me.polygons:
            for k in poly.edge_keys:
                count[k] = count.get(k, 0) + 1
        open_v = {i for k, n in count.items() if n == 1 for i in k}
        roots = []
        for i in open_v:
            p = W @ me.vertices[i].co
            ok, loc, _, _ = hull0.closest_point_on_mesh(inv0 @ p)
            if ok and ((hull0.matrix_world @ loc) - p).length < ROOT:
                roots.append(p)
        if not roots:
            log("straighten: %s has no root on the hull; left as it is" % f.name)
            continue
        kd = KDTree(len(roots))
        for i, p in enumerate(roots):
            kd.insert(p, i)
        kd.balance()
        port = sum((p.y for p in roots)) > 0.0
        tree = trees[port]
        Wi, most, off, slid = W.inverted(), 0.0, 0.0, 0
        for v in me.vertices:
            p = W @ v.co
            t = min(kd.find(p)[2] / FAIR_FADE, 1.0)
            w = 1.0 - t * t * (3.0 - 2.0 * t)
            if w <= 0.0:
                continue
            q = p.lerp(H @ p, w)
            n = (N @ v.normal).normalized()
            best = None                                             # the nearest point of the surface that faces as
            for loc, nor, _, dist in tree.find_nearest_range(q, 4.0):   # the vertex does (not the skin's other side)
                if nor.dot(n) > 0.3 and (best is None or dist < best[1]):
                    best = (loc, dist)
            if best is None:
                loc, _, _, dist = tree.find_nearest(q)
                best = (loc, dist)
            off = max(off, best[1])
            most = max(most, (best[0] - p).length)
            v.co = Wi @ best[0]
            slid += 1
        me.update()
        log("straighten: %s: its %d root vertices go with the hull's side (%d vertices slid along the fairing's own "
            "surface, at most %.2f m, fading out over %.0f m; the farthest any was put back onto it: %.2f m)"
            % (f.name, len(roots), slid, most, FAIR_FADE, off))
    # the hull: turned and shifted, but for the deck round the bay, which stays on the bay's outline
    bay = next((o for o in objs if o.type == "MESH" and o.name.startswith(BAY)), None)
    rect = None
    if bay:
        bx = [bay.matrix_world @ v.co for v in bay.data.vertices]
        rect = (min(p.x for p in bx), max(p.x for p in bx), min(p.y for p in bx), max(p.y for p in bx))

        # the deck's edge either side of the bay (the gunwale: the widest the hull is at deck height, in 1 m bins),
        # each as (y, z)
        edge = {}
        for v in hulls[0].data.vertices:
            p = hulls[0].matrix_world @ v.co
            if p.z > BAY_Z and rect[0] - 4.0 < p.x < rect[1] + 4.0:
                k = int(math.floor(p.x))
                lo, hi = edge.get(k, ((0.0, 0.0), (0.0, 0.0)))
                edge[k] = ((p.y, p.z) if p.y < lo[0] else lo, (p.y, p.z) if p.y > hi[0] else hi)

        # the deck's height along the bay (it rises to the bow): the height of the flat deck's vertices (every face at
        # them facing up) within 8 m of the bay's sides, in 5 m bins
        me0, W0 = hulls[0].data, hulls[0].matrix_world
        flat = [True] * len(me0.vertices)
        for poly in me0.polygons:
            if abs((W0.to_3x3() @ poly.normal).normalized().z) < 0.9:
                for i in poly.vertices:
                    flat[i] = False
        zs = {}
        for v in me0.vertices:
            p = W0 @ v.co
            if flat[v.index] and p.z > BAY_Z and rect[0] - 6.0 < p.x < rect[1] + 6.0 and rect[2] - 8.0 < p.y < rect[3] + 8.0:
                zs.setdefault(int(math.floor(p.x / 5.0)), []).append(p.z)
        deck_bins = {k: sorted(v)[len(v) // 10] for k, v in zs.items()}    # (the low tenth: the deck itself, not the
                                                                             # barbette's or a fitting's flat top)

    def deck(x):
        a = x / 5.0 - 0.5
        k, f = int(math.floor(a)), a - math.floor(a)
        z = [deck_bins.get(j, deck_bins.get(j - 1, deck_bins.get(j + 1))) for j in (k, k + 1)]
        if z[0] is None or z[1] is None:
            return None
        return z[0] * (1 - f) + z[1] * f

    def gunwale(x, port):
        """the deck's edge at x on that side (the widest of this metre and its neighbours)"""
        k = int(math.floor(x))
        g = [edge[j] for j in (k - 1, k, k + 1) if j in edge]
        if not g:
            return None
        return max(e[1][0] for e in g) if port else min(e[0][0] for e in g)

    def with_hull(p):
        """how much of the hull's move a hull vertex takes: all of it, but for the deck round the bay: none on the
        bay's outline, rising to all at the deck's edge (0.3 m short of it, BAY_WIDE from the outline at most), so
        the gunwale and the hull's side under it go wholly with the hull"""
        if rect is None or p.z < BAY_Z:
            return 1.0
        dx = rect[0] - p.x if p.x < rect[0] else p.x - rect[1] if p.x > rect[1] else 0.0
        dy = max(p.y - rect[3], rect[2] - p.y, 0.0)
        d = deck(p.x)
        if d is not None and p.z < d - 0.4:                         # under the deck: the hull's side (where the bay's
            return 1.0                                              # cut reached it too, its cut edge is the skin's)
        g = gunwale(p.x, p.y > 0.0)
        side = min(max(abs(g) - rect[3] - 0.3, 0.5), BAY_WIDE) if g is not None else BAY_SIDE
        t = min(1.0, math.hypot(dx / (BAY_AFT if p.x < rect[0] else BAY_FWD), dy / side))
        return t * t * (3.0 - 2.0 * t) if side > 3.5 else t         # (eased where there is room for it)
    for hull in hulls:
        if hull.data.name not in done:
            W, Wi, me = hull.matrix_world, hull.matrix_world.inverted(), hull.data
            up = [poly.normal.z for poly in me.polygons]
            at = [W @ v.co for v in me.vertices]
            wt = [with_hull(p) for p in at]
            # Only the deck's own sheet bends. Every other connected piece that reaches the bay's zone (a fitting
            # standing on the deck, the forward turret's barbette, whose front the bay's cut trimmed) goes as ONE
            # piece, by the share at its middle: sheared, a barbette's front edge stood 0.8 m off its own ring
            # (found by comparing every vertex with the original design, 2026-11-10)
            root = list(range(len(at)))

            def find(i):
                while root[i] != i:
                    root[i] = root[root[i]]
                    i = root[i]
                return i
            for e in me.edges:
                a, b = find(e.vertices[0]), find(e.vertices[1])
                if a != b:
                    root[a] = b
            pieces = {}
            for i in range(len(at)):
                pieces.setdefault(find(i), []).append(i)
            # (pieces that touch are one fitting: a bollard's posts and its base plate go by one share)
            small = []
            for idx in pieces.values():
                lo = Vector((min(at[i].x for i in idx), min(at[i].y for i in idx), min(at[i].z for i in idx)))
                hi = Vector((max(at[i].x for i in idx), max(at[i].y for i in idx), max(at[i].z for i in idx)))
                if math.hypot(hi.x - lo.x, hi.y - lo.y) > PIECE or hi.z < BAY_Z or rect is None:
                    continue                                        # (the deck's sheet; or nothing near the bay)
                if hi.x < rect[0] - 5.0 or lo.x > rect[1] + 5.0 or lo.y > rect[3] + BAY_WIDE + 3.0 or hi.y < rect[2] - BAY_WIDE - 3.0:
                    continue
                small.append((idx, lo, hi))
            group = list(range(len(small)))

            def gfind(i):
                while group[i] != i:
                    group[i] = group[group[i]]
                    i = group[i]
                return i
            for i in range(len(small)):
                for j in range(i + 1, len(small)):
                    (_, alo, ahi), (_, blo, bhi) = small[i], small[j]
                    if all(alo[k] <= bhi[k] + 0.15 and blo[k] <= ahi[k] + 0.15 for k in range(3)):
                        gi, gj = gfind(i), gfind(j)
                        if gi != gj:
                            group[gi] = gj
            fittings = {}
            for i, (idx, _, _) in enumerate(small):
                fittings.setdefault(gfind(i), []).extend(idx)
            whole = 0
            for idx in fittings.values():
                if all(wt[i] >= 1.0 for i in idx):
                    continue
                c = sum((at[i] for i in idx), Vector()) / len(idx)
                m = with_hull(c)
                for i in idx:
                    wt[i] = m
                whole += 1
            for turn_no in range(8):
                for v, p, w in zip(me.vertices, at, wt):
                    v.co = Wi @ p.lerp(H @ p, w)
                me.update()
                over = [poly for poly, z in zip(me.polygons, up) if abs(z) > 0.5 and poly.normal.z * z < 0.0]
                if not over:
                    break
                # a small piece standing on the deck (a fitting's slivers) folds when its corners take different
                # shares of the move: each such face's corners take one share, the mean of theirs, and it goes whole
                for poly in over:
                    m = sum(wt[i] for i in poly.vertices) / len(poly.vertices)
                    for i in poly.vertices:
                        wt[i] = m
            held = sum(1 for w in wt if w < 1.0)
            for poly in over:
                log("straighten:   turned over: a face of %.4f m2 at %s" % (poly.area, tuple(round(c, 2) for c in W @ poly.center)))
            flipped = len(over)
            log("straighten: %s: %d deck vertices round the bay stay with it (%s), %d standing pieces there moved whole; "
                "%d faces turned over (%d passes)" % (hull.name, held, "x %.1f..%.1f, y %.2f..%.2f" % rect if rect
                                                      else "no bay here", whole, flipped, turn_no + 1))
            assert flipped == 0, "the deck folded over round the bay"
            if rect:
                mend_breach(hull, rect, deck, log)
                # a standing piece the bay's after end cut through (the forward turret's barbette: its front sliced
                # off flat at the bay's end and left open, the inside of the hull on show under the guns)
                cut = [i for idx, _, _ in small for i in idx
                       if wt[i] >= 1.0 and abs(at[i].x - rect[0]) < 0.02 and at[i].z > BAY_Z - 0.5
                       and rect[2] - 0.5 < at[i].y < rect[3] + 0.5]
                cap_cut(hull, cut, log)
            done.add(hull.data.name)
    mounts = [o for o in objs if o.name.startswith(IOWA) and not (o.parent and o.parent.name.startswith(IOWA))]

    def middle(o):                                                  # a mount's middle in plan, in its mesh's own frame
        xs, ys = [v.co.x for v in o.data.vertices], [v.co.y for v in o.data.vertices]
        return Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, 0.0))
    # the mounts' own turn: each mesh's own mirror plane about its middle; the clean ones (the 5-inch houses, the
    # CIWS: a mirror miss of millimetres) all give the Iowa's 0.55 deg, and that is used for every mount (a 16-inch
    # house with its guns on it, or trained off the beam, has no clean mirror plane of its own)
    own = []
    for o in mounts:
        if o.type == "MESH" and o.data.name not in {n for n, _ in own}:
            c = middle(o)
            t, _, m = symmetry([v.co - c for v in o.data.vertices], span=math.radians(1.2), shift_span=0.3)
            own.append((o.data.name, (t, m)))
    clean = sorted(t for _, (t, m) in own if m < 0.05 and math.radians(0.1) < abs(t) < math.radians(1.0))
    iowa = clean[len(clean) // 2] if clean else turn
    back = Matrix.Rotation(-iowa, 4, "Z")
    moved = 0
    for o in mounts:
        if o.type == "MESH" and o.matrix_world.translation.length < 0.01:
            if o.data.name not in done:                             # its mesh is in the world's frame: moved with the
                c = o.matrix_world @ middle(o)                      # hull and turned back about its own middle
                o.data.transform(o.matrix_world.inverted() @ Matrix.Translation(H @ c) @ back @ Matrix.Translation(-c)
                                 @ o.matrix_world)
                o.data.update()
                done.add(o.data.name)
        else:                                                       # it stands at its own origin: the origin moves,
            Mw = o.matrix_world.copy()                              # the mesh and the children (the guns' trunnions)
            Mw.translation = H @ Mw.translation                     # turn back about it
            o.matrix_world = Mw
            if o.type == "MESH" and o.data.name not in done:
                o.data.transform(back)
                o.data.update()
                done.add(o.data.name)
            for ch in o.children:                                   # (from its own basis: its world matrix is stale
                local = ch.matrix_parent_inverse @ ch.matrix_basis  # once the parent has been moved)
                ch.matrix_basis = ch.matrix_parent_inverse.inverted() @ back @ local
        moved += 1
    bpy.context.view_layer.update()
    now = [hulls[0].matrix_world @ v.co for v in hulls[0].data.vertices]
    again = symmetry(now, span=math.radians(0.3), shift_span=0.3)
    log("straighten: the hull turned %.3f deg, shifted %+.3f m and unsheared %.5f; %d Iowa mounts moved with it and turned "
        "back %.2f deg about their own middles (the Iowa's own turn, from %d clean meshes); the hull is now %.3f deg "
        "askew, %+.3f m off, sheared %.5f"
        % (-math.degrees(turn), -shift, shear, moved, math.degrees(iowa), len(clean), math.degrees(again[0]), again[1],
           shear_of(now, span=0.003)[0]))
    out["mounts_turn_deg"] = round(math.degrees(iowa), 3)
    return out


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    straighten([c for c in bpy.data.collections
                if c.name != "SRC" and any(o.name.startswith("LEV_HULL") for o in c.objects)])
    if "save" in argv:
        bpy.ops.wm.save_mainfile(compress=False)
        print("straighten: saved", bpy.data.filepath)
