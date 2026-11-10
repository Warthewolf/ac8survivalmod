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
Animation is untouched (only rotations are keyed, and a turn about z before them only changes the z angle, which is
keyed on the mounts themselves as an absolute heading). Without `save` it only reports. model_tanacorn.py calls
straighten() on what it loads too, so a design file that has not been through this still gives a straight model.
"""
import bpy, sys, math, random
from mathutils import Vector, Matrix
from mathutils.kdtree import KDTree

IOWA = ("LEV_T16", "LEV_IOWA_T5", "LEV_IOWA_CIWS", "LEV_G16", "LEV_IOWA_G5", "LEV_IOWA_CG")


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
    for hull in hulls:
        if hull.data.name not in done:
            hull.data.transform(hull.matrix_world.inverted() @ H @ hull.matrix_world)
            hull.data.update()
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
