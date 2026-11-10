"""straighten.py : Blender 3.3, the Leviathan design lined up with its own centreline (the user, 2026-11-10: "I want the
model straightened why the hell would you not line it up correctly").

  blender -b art/tanicorn/design/<file>.blend -P tools/tanicorn/straighten.py -- [save]

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
  - the pods' fairings (CUT_ALC_SPONSON_*) take the hull's move at their roots (the open edges lying on the hull's
    skin), fading out over 14 m, so each root stays in the hull's side as it was cut and the pods stay where they are.
  - where that cut had gone through the hull's side (the starboard bow, where the askew hull came inside the bay's
    box), the cut edge goes with the skin like the rest of the side and the hole it left is closed (mend_breach).
Animation is untouched (only rotations are keyed, and a turn about z before them only changes the z angle, which is
keyed on the mounts themselves as an absolute heading). Without `save` it only reports. model_tanacorn.py calls
straighten() on what it loads too, so a design file that has not been through this still gives a straight model.
"""
import bpy, sys, math, random
from mathutils import Vector, Matrix
from mathutils.kdtree import KDTree

IOWA = ("LEV_T16", "LEV_IOWA_T5", "LEV_IOWA_CIWS", "LEV_G16", "LEV_IOWA_G5", "LEV_IOWA_CG")
BAY, FAIRING = "CUT_ALC_SECTION", "CUT_ALC_SPONSON"   # the Alicorn's parts cut to fit the hull
BAY_Z = 8.0                                      # the deck round the bay is above this (the hull's sides are not held)
BAY_SIDE, BAY_AFT, BAY_FWD = 2.0, 0.6, 2.0       # how far from the bay's outline the deck is back with the hull, m
BAY_WIDE = 8.0                                   # (to the side: as far as the deck's width allows, up to this)
ROOT, FAIR_FADE = 0.9, 14.0                      # a fairing's root: open edges this near the hull's skin; its fade, m


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
    out = {"turn_deg": round(math.degrees(turn), 3), "shift_m": round(shift, 3)}
    if (abs(math.degrees(turn)) < 0.02 and abs(shift) < 0.02) or not apply:
        return out
    H = Matrix.Rotation(-turn, 4, "Z") @ Matrix.Translation((0.0, -shift, 0.0))
    done = set()
    # the pods' fairings first (their roots are found on the hull as it lies now)
    hull0, inv0 = hulls[0], hulls[0].matrix_world.inverted()
    for f in [o for o in objs if o.type == "MESH" and o.name.startswith(FAIRING)]:
        if f.data.name in done:
            continue
        done.add(f.data.name)
        W, me = f.matrix_world, f.data
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
        Wi, most = W.inverted(), 0.0
        for v in me.vertices:
            p = W @ v.co
            t = min(kd.find(p)[2] / FAIR_FADE, 1.0)
            w = 1.0 - t * t * (3.0 - 2.0 * t)
            if w > 0.0:
                q = p.lerp(H @ p, w)
                most = max(most, (q - p).length)
                v.co = Wi @ q
        me.update()
        log("straighten: %s: %d root vertices go with the hull's side (at most %.2f m), fading out over %.0f m"
            % (f.name, len(roots), most, FAIR_FADE))
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
            log("straighten: %s: %d deck vertices round the bay stay with it (%s); %d faces turned over (%d passes)"
                % (hull.name, held, "x %.1f..%.1f, y %.2f..%.2f" % rect if rect else "no bay here", flipped, turn_no + 1))
            assert flipped == 0, "the deck folded over round the bay"
            if rect:
                mend_breach(hull, rect, deck, log)
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
    again = symmetry([hulls[0].matrix_world @ v.co for v in hulls[0].data.vertices], span=math.radians(0.3), shift_span=0.3)
    log("straighten: the hull turned %.3f deg and shifted %+.3f m; %d Iowa mounts moved with it and turned back %.2f deg "
        "about their own middles (the Iowa's own turn, from %d clean meshes); the hull is now %.3f deg askew, %+.3f m off"
        % (-math.degrees(turn), -shift, moved, math.degrees(iowa), len(clean), math.degrees(again[0]), again[1]))
    out["mounts_turn_deg"] = round(math.degrees(iowa), 3)
    return out


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    straighten([c for c in bpy.data.collections
                if c.name != "SRC" and any(o.name.startswith("LEV_HULL") for o in c.objects)])
    if "save" in argv:
        bpy.ops.wm.save_mainfile(compress=False)
        print("straighten: saved", bpy.data.filepath)
