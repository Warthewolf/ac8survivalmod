"""model_tanacorn.py : Blender 3.3, THE TANACORN's model from the Leviathan design (docs/design/INVINCIBLE_FLEET.md WP0).

  blender -b art/tanicorn/design/Leviathan_animated.blend -P tools/tanicorn/model_tanacorn.py -- <out dir> [render]

The design (Sea Power's Iowa fused with AC8's Alicorn: the user's dev install only, never shipped) is the ship as it is;
this script adds what the settled armament needs that neither source ship has, and the hull's mount sockets:
  - 4 laser interceptor turrets at the design's LEV_LASER_* corners: TANA_LASER_<pos>_house (turret_yaw) and
    TANA_LASER_<pos>_gun (turret_pitch, its origin the pitch pivot), the beam's socket SOC_Gun_01 at the lens;
  - 8 deck VLS blocks on the aft deck behind turret C (TANA_VLSD_1..8): 8 cell wells under 8 hinged hatches each
    (TANA_VLSD_<n>_Hatch_01..08, each object's origin its hinge), sockets SOC_Vls_01..08 straight up;
  - 8 side VLS blocks on the bow's flanks, 4 a side (TANA_VLSS_L1..4 / R1..4), each bent onto the hull's skin (its
    flare; wrap_map) and following its sheer: 8 wells under 8 hatches hinged at their top edge, swinging up and out; sockets SOC_Vls_01..08
    along each cell's launch line (out of the hull's side, 35 deg above level);
  - SOCKET_Mount_* empties on the hull for every part, in tanacorn_hull_sockets.json (UE frame: cm, x fwd, y right,
    z up; yaw / pitch degrees, a socket's +X its forward), with each VLS block's hatches (hinge, axis, open angle).
Every new part type is built once (a prototype mesh shared by all its copies) as ONE closed solid: its pieces united by
Blender's exact boolean, cell wells cut, bevelled (2 segments, normals hardened), merged, normals outward, unwrapped
(smart UV, no overlaps) and checked (non-manifold / open edges, faces through each other, degenerate faces, UVs out of
0..1: tanacorn_model_check.json). Its texture is baked once (textures/T_TANA_<part>_D.png: the paint, a light grime
noise and its own ambient occlusion; ordinary PNGs, hard rule 44).
Writes <out>/Tanacorn_model.blend (the design file is never changed; every hatch keyed open and shut in its 1-360
sequence, HATCH_KEYS), with `render` <out>/renders/*.png (Cycles on the CPU; TANA_SAMPLES, TANA_SHOTS), and with `anim`
<out>/renders/anim/tanacorn_hatches_<view>.mp4 and tanacorn_hatches.mp4: every block's hatches opening in 0.5 s, held,
then shutting, from 5 views (ffmpeg; TANA_ANIM_SAMPLES, TANA_ANIM_VIEWS).
"""
import bpy, bmesh, sys, os, json, math
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("build/tanicorn/model")
RENDER = "render" in argv[1:]
ANIM = "anim" in argv[1:]
TEX = os.path.join(OUT, "textures")
os.makedirs(TEX, exist_ok=True)

SHIP = bpy.data.objects["LEV_ship"]
HULL = bpy.data.objects["LEV_HULL.001"]
COLL = bpy.data.collections["5 LEVIATHAN animated"]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import straighten                                    # (the design files were straightened with it, 2026-11-10; a file
STRAIGHT = straighten.straighten(COLL, lambda t: print("model: " + t))   # that was not is straightened here, in memory)


def collection(name, parent):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in [x.name for x in parent.children]:
        parent.children.link(c)
    return c


ADD = collection("TANACORN additions", COLL)
SOCK = collection("TANACORN sockets", COLL)
WORK = collection("TANACORN prototypes", bpy.context.scene.collection)   # each part type once, away from the ship


def remove_crew():
    """the Iowa's crew figures (the user, 2026-11-10: "remove the people models from the ship"): every face on a material
    whose texture is the Iowa's crew sheet, and the vertices that leaves loose, from every mesh of the ship"""
    n = 0
    for o in COLL.all_objects:
        if o.type != "MESH":
            continue
        slots = {i for i, sl in enumerate(o.material_slots) if sl.material and sl.material.use_nodes and any(
            nd.type == "TEX_IMAGE" and nd.image and "crew" in nd.image.name.lower() for nd in sl.material.node_tree.nodes)}
        if not slots:
            continue
        if o.data.users > 1:
            o.data = o.data.copy()
        bm = bmesh.new()
        bm.from_mesh(o.data)
        faces = [f for f in bm.faces if f.material_index in slots]
        n += len(faces)
        bmesh.ops.delete(bm, geom=faces, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
        print("model: crew removed from %s: %d faces" % (o.name, len(faces)))
    return n


CREW_FACES = remove_crew()


def remove_deck_crew():
    """the Alicorn's own deck crew left on the aft deck (the user's marked render, 2026-11-10: legs and torsos at real
    size, on the Alicorn's deck material, so the crew-texture pass missed them): every separate piece (the hull's
    fragments joined where they share a vertex position) under 1.3 m across, 0.5-1.6 m tall, standing at the aft deck's
    height on the Alicorn's deck; vents, bollards and fittings are larger or elsewhere (checked by eye)"""
    me = HULL.data
    M = HULL.matrix_world
    co = [M @ v.co for v in me.vertices]
    par = list(range(len(co)))

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a
    seen = {}
    for i, p in enumerate(co):
        k = (round(p.x, 3), round(p.y, 3), round(p.z, 3))
        if k in seen:
            par[find(i)] = find(seen[k])
        else:
            seen[k] = i
    for e in me.edges:
        par[find(e.vertices[0])] = find(e.vertices[1])
    groups = {}
    for i in range(len(co)):
        groups.setdefault(find(i), []).append(i)
    doomed = set()
    for vs in groups.values():
        ps = [co[i] for i in vs]
        lo = Vector((min(p.x for p in ps), min(p.y for p in ps), min(p.z for p in ps)))
        hi = Vector((max(p.x for p in ps), max(p.y for p in ps), max(p.z for p in ps)))
        d = hi - lo
        if max(d.x, d.y) < 1.3 and 0.5 < d.z < 1.6 and 9.9 < lo.z < 11.3 and hi.x < -140:
            doomed.update(vs)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    faces = {f for i in doomed for f in bm.verts[i].link_faces}
    bmesh.ops.delete(bm, geom=list(faces), context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    print("model: deck crew removed from %s: %d faces" % (HULL.name, len(faces)))
    return len(faces)


DECK_CREW_FACES = remove_deck_crew()
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hull_uv                                                       # (the hull's ALC faces mapped again from scratch:
HULL_UV = hull_uv.fix(HULL, lambda t: print("model: " + t))          # hull_uv.py; the copied map had the dark deck patches)
DG = bpy.context.evaluated_depsgraph_get()
SHIP_MESHES = [o for o in COLL.all_objects if o.type == "MESH"]
CHECK = {}


# ---------------------------------------------------------------------------------------------------- the kit
import tanakit                                       # (tanakit.py: materials, Part, unwrap, check, bake)
tanakit.WORK, tanakit.TEX, tanakit.CHECK = WORK, TEX, CHECK
from tanakit import *


def grid_body(part, xs, ys, kind, top, base, R=Matrix()):
    """an all-quad block: its top a grid on xs x ys (every well, mount and uptake edge a grid line), the sides and
    bottom closed; kind(cx, cy) -> None, ("well", depth) or ("raise", height, material) for each grid cell; R turns the
    block from its own frame (top +Z) into the part's"""
    bm = part.bm
    nx, ny = len(xs), len(ys)
    T = {(i, j): bm.verts.new((xs[i], ys[j], top)) for i in range(nx) for j in range(ny)}
    B = {(i, j): bm.verts.new((xs[i], ys[j], base)) for i in range(nx) for j in range(ny)}
    paint, dark = part._slot(M_PAINT), part._slot(M_DARK)
    cells = {}
    for i in range(nx - 1):
        for j in range(ny - 1):
            f = bm.faces.new((T[i, j], T[i + 1, j], T[i + 1, j + 1], T[i, j + 1]))
            f.material_index = paint
            cells[i, j] = f
            g = bm.faces.new((B[i, j + 1], B[i + 1, j + 1], B[i + 1, j], B[i, j]))
            g.material_index = paint
    for i in range(nx - 1):                                              # the four sides
        for a, b in (((i, 0), (i + 1, 0)), ((i + 1, ny - 1), (i, ny - 1))):
            bm.faces.new((T[a], B[a], B[b], T[b])).material_index = paint
    for j in range(ny - 1):
        for a, b in (((nx - 1, j), (nx - 1, j + 1)), ((0, j + 1), (0, j))):
            bm.faces.new((T[a], B[a], B[b], T[b])).material_index = paint
    groups = {}
    for (i, j), f in cells.items():
        k = kind((xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2)
        if k:
            groups.setdefault(k, []).append(f)
    for k, faces in groups.items():                                      # wells pushed down, mounts pulled up
        ret = bmesh.ops.extrude_face_region(bm, geom=faces)
        moved = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
        dz = -k[1] if k[0] == "well" else k[1]
        bmesh.ops.translate(bm, vec=Vector((0, 0, dz)), verts=moved)
        new_faces = {f for v in moved for f in v.link_faces}
        for f in new_faces:
            f.material_index = dark if k[0] == "well" else part._slot(k[2])
        bmesh.ops.delete(bm, geom=faces, context="FACES_ONLY")          # (the region's old faces, now inside)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=R.to_4x4(), verts=bm.verts)


# ---------------------------------------------------------------------------------------------------- the part types
# The laser director (the user's reference photos, 2026-11-10: a beam director on a turret ring): a squat ring, a
# U-shaped yoke whose arms are rounded on top with rows of vent holes down their outer faces (the house, turning about
# Z), and between the arms a head (the gun, tilting about the arms' axis) with a big octagonal window off to one side,
# two round sensor lenses beside it, a small camera above, and a sloped chin under the window. Matte black, dark glass.
# About 5.5 m tall on the 650 m ship.
ARM_Y, ARM_T, ARM_W, ARM_R = 1.85, 0.8, 2.8, 1.4        # the arms' centre, thickness, width (x) and top radius
LASER_PIVOT = Vector((0.0, 0, 3.4))                     # the head's tilt axis, through the arms' rounded tops


def octagon(cu, cv, w, h, c):
    """an octagon centred (cu, cv), w x h, its corners cut by c (counter-clockwise)"""
    u0, u1, v0, v1 = cu - w / 2, cu + w / 2, cv - h / 2, cv + h / 2
    return [(u0 + c, v0), (u1 - c, v0), (u1, v0 + c), (u1, v1 - c), (u1 - c, v1), (u0 + c, v1), (u0, v1 - c), (u0, v0 + c)]


def laser_house():
    p = Part()
    p.cyl(2.2, 2.2, 1.3, Vector((0, 0, 0.25)), m=M_DARK, seg=32)                   # the ring (0.4 m into the deck)
    p.cyl(2.45, 2.45, 0.22, Vector((0, 0, 0.98)), m=M_BLACK, seg=32)               # the ring's flange
    p.prism(octagon(0, 0, 3.2, 4.6, 0.45), "Z", 1.05, 1.75, m=M_BLACK)            # the yoke's base
    for s_ in (1, -1):
        y = ARM_Y * s_
        p.box((ARM_W, ARM_T, LASER_PIVOT.z - 1.6), Vector((0, y, (1.6 + LASER_PIVOT.z) / 2)), m=M_BLACK)   # the arm
        p.cyl(ARM_R, ARM_R, ARM_T, Vector((0, y, LASER_PIVOT.z)), axis="Y", m=M_BLACK, seg=32)          # its round top
        face = y + s_ * ARM_T / 2
        for k in range(6):                                                          # vent holes down the outer face
            p.cyl(0.075, 0.075, 0.3, Vector((-0.95, face, 1.95 + k * 0.42)), axis="Y", m=M_DARK, seg=12, cut=True)
        for k in range(5):                                                          # and round the top
            a_ = math.radians(110 - k * 22)
            p.cyl(0.075, 0.075, 0.3, Vector((math.cos(a_) * 1.05, face, LASER_PIVOT.z + math.sin(a_) * 1.05)),
                  axis="Y", m=M_DARK, seg=12, cut=True)
    return p.solid("TANA_LASER_house", bevel=0.04)


HEAD_X0, HEAD_X1 = -1.25, 1.15                         # the head's back and front (from the tilt axis)
WIN = (-0.3, 0.35, 1.75, 1.45, 0.32)                    # the window: centre (y, z), width, height, corner cut
LASER_TIP = HEAD_X1 + 0.05                              # the beam leaves the window's middle


def laser_gun():
    p = Part()                                                                     # x forward from the tilt axis
    head = [(-1.38, -1.45), (1.38, -1.45), (1.38, 0.95), (0.95, 1.38), (-0.95, 1.38), (-1.38, 0.95)]   # (y, z)
    p.prism(head, "X", HEAD_X0, HEAD_X1, m=M_BLACK)                                # the head, its top corners cut
    p.prism([(HEAD_X1 - 0.05, -0.62), (HEAD_X1 + 0.42, -0.62), (HEAD_X1 + 0.12, -0.18), (HEAD_X1 - 0.05, -0.18)],
            "Y", -1.3, 1.3, m=M_BLACK)                                             # the chin under the window
    for s_ in (1, -1):
        p.cyl(0.55, 0.55, 0.2, Vector((0, 1.38 * s_ + 0.08 * s_, 0)), axis="Y", m=M_DARK, seg=24)   # the trunnions
    wy, wz, ww, wh, wc = WIN
    p.prism(octagon(wy, wz, ww, wh, wc), "X", HEAD_X1 - 0.16, HEAD_X1 + 0.1, m=M_DARK, cut=True)   # the window's recess
    p.prism(octagon(wy, wz, ww - 0.1, wh - 0.1, wc - 0.03), "X", HEAD_X1 - 0.13, HEAD_X1 - 0.07, m=M_GLASS, post=True)   # glass
    for (ly, lz, lr) in ((0.95, 0.78, 0.2), (0.95, 0.12, 0.27)):                   # the two lenses beside it
        p.cyl(lr + 0.05, lr + 0.05, 0.26, Vector((HEAD_X1, ly, lz)), axis="X", m=M_DARK, seg=24, cut=True)
        p.cyl(lr, lr, 0.06, Vector((HEAD_X1 - 0.08, ly, lz)), axis="X", m=M_GLASS, seg=24, post=True)
    p.cyl(0.07, 0.07, 0.2, Vector((HEAD_X1, 0.1, 1.2)), axis="X", m=M_DARK, seg=12, cut=True)   # the camera
    return p.solid("TANA_LASER_gun", bevel=0.035)


VLSD_CELLS = [(x, y) for y in (1.45, -1.45) for x in (3.9, 1.3, -1.3, -3.9)]     # SOC_Vls_01..08: port row fwd -> aft
VLSD_TOP = 0.70


def vlsd_body():
    p = Part()
    WX, WY, MX = 1.075, 1.175, (1.4, 1.2)                                  # a well's half sizes; the hinge mount's x
    xs, ys = {-5.6, 5.6}, {-3.2, 3.2, -0.18, 0.18}
    for x, y in VLSD_CELLS:
        xs |= {x - WX, x + WX, x - MX[0], x - MX[1]}
        ys |= {y - WY, y + WY, y - 1.05, y + 1.05}

    def kind(cx, cy):
        for x, y in VLSD_CELLS:
            if abs(cx - x) < WX and abs(cy - y) < WY:
                return ("well", 0.6)
            if x - MX[0] < cx < x - MX[1] and abs(cy - y) < 1.05:
                return ("raise", 0.16, M_PAINT)                          # the hinge's mount
        if abs(cy) < 0.18 and abs(cx) < 5.3:
            return ("raise", 0.22, M_PAINT)                              # the uptake between the rows
        return None
    xs.add(-5.3); xs.add(5.3)
    grid_body(p, sorted(xs), sorted(ys), kind, VLSD_TOP, -0.4)           # (its base 0.4 m into the deck: the aft deck's
                                                                          # camber leaves no gap under an edge)
    return p.solid("TANA_VLSD_body", simplify=False)


def vlsd_hatch():
    """origin on the hinge (the lid's aft edge), lid along +X; opens about Y"""
    p = Part()
    p.box((2.3, 2.5, 0.12), Vector((1.15, 0, 0)))
    p.box((1.6, 0.18, 0.05), Vector((1.2, 0.7, 0.085)))                            # stiffeners
    p.box((1.6, 0.18, 0.05), Vector((1.2, -0.7, 0.085)))
    for y in (0.85, -0.85):
        p.cyl(0.11, 0.11, 0.5, Vector((0, y, 0)), axis="Y", seg=12)                # hinge knuckles
    return p.solid("TANA_VLSD_hatch", bevel=0.015)


SIDE_UP = math.radians(35.0)                     # the side cells' launch line: out of the hull, 35 deg above level
VLSS_CELLS = [(x, z) for z in (1.3, -1.3) for x in (3.9, 1.3, -1.3, -3.9)]
VLSS_FACE = 0.02                                 # the face stands this far off the hull's skin (z-fight clear)
VLSS_US, VLSS_WS = [], []                        # the body's grid lines along and up the side (the wrap bends on them)


def vlss_body():
    """+Y out of the hull's skin (the block's face at y = VLSS_FACE), +Z up the side. Built in its own frame (face +Z,
    its y = the side's -z) and turned: R_x(-90 deg) takes +Z to +Y and +Y to -Z"""
    p = Part()
    WX, WZ = 1.0, 0.9
    xs, ys = {-5.5, 5.5, -5.3, 5.3}, {-2.9, 2.9, -2.7, 2.7}
    for x, z in VLSS_CELLS:
        xs |= {x - WX, x + WX, x - 1.075, x + 1.075}
        ys |= {-(z + WZ), -(z - WZ), -(z + 1.22), -(z + 1.02)}

    def kind(cx, cy):
        cz = -cy
        if abs(cx) > 5.3 or abs(cy) > 2.7:
            return ("raise", 0.12, M_PAINT)                              # the frame round the face
        for x, z in VLSS_CELLS:
            if abs(cx - x) < WX and abs(cz - z) < WZ:
                return ("well", 0.7)
            if abs(cx - x) < 1.075 and z + 1.02 < cz < z + 1.22:
                return ("raise", 0.12, M_PAINT)                          # the hinge's mount above the cell
        return None
    ys = sorted(ys)
    for a, b in zip(list(ys), list(ys)[1:]):                             # a line every 0.5 m at most up the side: the
        n = int(math.ceil((b - a) / 0.5 - 1e-6))                         # block is bent onto the hull's flare on them
        ys += [a + (b - a) * k / n for k in range(1, n)]
    VLSS_US[:], VLSS_WS[:] = sorted(xs), sorted(-y for y in ys)
    grid_body(p, sorted(xs), sorted(ys), kind, 0.0, -1.6,
              Matrix.Translation((0, VLSS_FACE, 0)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    return p.solid("TANA_VLSS_body", simplify=False)


def vlss_hatch():
    """origin on the hinge (the lid's top edge), lid hanging down (-Z); opens about X, swinging out (+Y) and up"""
    p = Part()
    p.box((2.1, 0.08, 1.95), Vector((0, 0.04, -0.975)))
    p.box((1.6, 0.05, 0.16), Vector((0, 0.1, -0.6)))                               # stiffeners
    p.box((1.6, 0.05, 0.16), Vector((0, 0.1, -1.35)))
    for x in (0.7, -0.7):                                                          # hinge knuckles on their leaves, clear of
        p.cyl(0.09, 0.09, 0.45, Vector((x, 0.04, 0.13)), axis="X", seg=12)         # the lid's faces
        p.box((0.4, 0.08, 0.16), Vector((x, 0.04, 0.04)))
    return p.solid("TANA_VLSS_hatch", bevel=0.012)


HATCH_OPEN = {"vlsd": ("Y", -100.0), "vlss": ("X", 115.0)}   # degrees about the hinge's own axis, 0.5 s (the Alicorn's)

TYPES = {}
for key, fn, size in (("LASER_house", laser_house, 1024), ("LASER_gun", laser_gun, 512), ("VLSD_body", vlsd_body, 1024),
                      ("VLSD_hatch", vlsd_hatch, 256), ("VLSS_body", vlss_body, 1024), ("VLSS_hatch", vlss_hatch, 256)):
    me, proto = fn()
    bake(me, proto, key, size)
    TYPES[key] = (me, proto)

for i, (me, proto) in enumerate(TYPES.values()):                    # the prototypes in a line on the sea, for the review
    proto.location = (-60.0 + i * 24.0, 420.0, 8.0)
    proto.matrix_world = Matrix.Translation(proto.location)


# ---------------------------------------------------------------------------------------------------- the ship's copies
def empty(name, M, parent=None, size=1.0, kind="ARROWS", coll=SOCK):
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    e = bpy.data.objects.new(name, None)
    e.empty_display_type, e.empty_display_size = kind, size
    coll.objects.link(e)
    if parent:
        e.parent = parent
    e.matrix_world = M
    return e


def copy_of(key, name, M, parent):
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    o = bpy.data.objects.new(name, TYPES[key][0])
    ADD.objects.link(o)
    o.parent = parent
    o.matrix_world = M
    return o


def frame(fwd, up=Vector((0, 0, 1)), at=Vector()):
    """a matrix whose +X is fwd and +Z is as near up as it can be"""
    x = fwd.normalized()
    y = up.cross(x).normalized()
    z = x.cross(y)
    return Matrix.Translation(at) @ Matrix((x, y, z)).transposed().to_4x4()


def cast(origin, d):
    best = None
    for o in SHIP_MESHES:
        inv = o.matrix_world.inverted()
        ok, loc, nor, _ = o.ray_cast(inv @ Vector(origin), (inv.to_3x3() @ Vector(d)).normalized(), depsgraph=DG)
        if ok:
            w = o.matrix_world @ loc
            dist = (w - Vector(origin)).length
            if best is None or dist < best[0]:
                best = (dist, w, (o.matrix_world.to_3x3().inverted().transposed() @ nor).normalized())
    return best


def deck_z(x, y):
    """the deck's height here: the middle one of five rays a hand apart. One ray alone, when it runs exactly down an
    edge between two deck faces, can slip between them and land on the hull's bottom from inside: at x = 194 to
    starboard that put the side block TANA_VLSS_R3 15 m too low, under the water (found 2026-11-10 in the export's
    check; her port twin stood right)."""
    zs = sorted(h[1].z for h in (cast((x + dx, y + dy, 300.0), (0, 0, -1))
                                 for dx, dy in ((0, 0), (0.07, 0.05), (-0.07, 0.05), (0.07, -0.05), (-0.07, -0.05))) if h)
    return zs[len(zs) // 2] if zs else None


# the hull lies 0.4 deg askew to the world's x axis in the design file (hull_uv.py found its centreline): the mounts on
# the deck are placed either side of the hull's own centreline and turned with it, not the world's
SKEW = math.atan(HULL_UV["centreline"]["skew"])


def centre_y(x):
    return HULL_UV["centreline"]["skew"] * x + HULL_UV["centreline"]["shift_m"]


made = {"laser": [], "vlsd": [], "vlss": []}
hatches = {}
for tag, heading in (("FWD_L", 0.0), ("FWD_R", 0.0), ("AFT_L", math.pi), ("AFT_R", math.pi)):
    at = bpy.data.objects["LEV_LASER_%s" % tag].matrix_world.translation.copy()
    at.y += centre_y(at.x)                                                         # (square to the hull's own centreline)
    at.z = deck_z(at.x, at.y) if abs(deck_z(at.x, at.y) - at.z) < 1.0 else at.z
    M = Matrix.Translation(at) @ Matrix.Rotation(heading + SKEW, 4, "Z")
    house = copy_of("LASER_house", "TANA_LASER_%s_house" % tag, M, SHIP)
    gun = copy_of("LASER_gun", "TANA_LASER_%s_gun" % tag, M @ Matrix.Translation(LASER_PIVOT), house)
    empty("TANA_LASER_%s_SOC_Gun_01" % tag, M @ Matrix.Translation(LASER_PIVOT + Vector((LASER_TIP, WIN[0], WIN[1]))), gun,
          0.8, coll=ADD)                                                           # (the beam from the window's middle)
    made["laser"].append((house, gun))

n = 0
for x in (-210.0, -228.0, -246.0, -264.0):                    # behind turret C's barrels' sweep (to x -194)
    for y in (16.0, -16.0):
        n += 1
        y += centre_y(x)
        M = Matrix.Translation((x, y, deck_z(x, y))) @ Matrix.Rotation(SKEW, 4, "Z")
        body = copy_of("VLSD_body", "TANA_VLSD_%d" % n, M, SHIP)
        hs = []
        for k, (cx, cy) in enumerate(VLSD_CELLS, 1):
            hinge = Matrix.Translation((cx - 1.2, cy, VLSD_TOP + 0.075))
            h = copy_of("VLSD_hatch", "TANA_VLSD_%d_Hatch_%02d" % (n, k), M @ hinge, body)
            hs.append((h, hinge))
            empty("TANA_VLSD_%d_SOC_Vls_%02d" % (n, k), M @ frame(Vector((0, 0, 1)), Vector((1, 0, 0)), Vector((cx, cy, 0.2))),
                  body, 0.6, coll=ADD)
        hatches[body.name] = ("vlsd", hs)
        made["vlsd"].append(body)

def cast_hull(origin, d):
    inv = HULL.matrix_world.inverted()
    ok, loc, _, _ = HULL.ray_cast(inv @ Vector(origin), (inv.to_3x3() @ Vector(d)).normalized(), depsgraph=DG)
    return HULL.matrix_world @ loc if ok else None


def skin(M, us, ws):
    """the hull's skin over a side block's own plane: its height y at each (us[i], ws[j]) of the frame M"""
    R, Mi = M.to_3x3(), M.inverted()
    d = R @ Vector((0, -1, 0))
    Y = np.full((len(us), len(ws)), np.nan)
    for i, u in enumerate(us):
        for j, w in enumerate(ws):
            h = cast_hull(M @ Vector((u, 30.0, w)), d)
            if h is not None:
                Y[i, j] = (Mi @ h).y
        ok = ~np.isnan(Y[i])
        Y[i] = np.interp(ws, np.asarray(ws)[ok], Y[i][ok]) if ok.any() else 0.0
    return Y


def bilin(xs, ys, Z, x, y):
    i = min(max(int(np.searchsorted(xs, x)) - 1, 0), len(xs) - 2)
    j = min(max(int(np.searchsorted(ys, y)) - 1, 0), len(ys) - 2)
    tx = min(max((x - xs[i]) / (xs[i + 1] - xs[i]), 0.0), 1.0)
    ty = min(max((y - ys[j]) / (ys[j + 1] - ys[j]), 0.0), 1.0)
    return float((Z[i, j] * (1 - tx) + Z[i + 1, j] * tx) * (1 - ty) + (Z[i, j + 1] * (1 - tx) + Z[i + 1, j + 1] * tx) * ty)


def fit_frame(M):
    """the block's frame turned onto the skin's best plane over its whole footprint (one ray's normal is one facet's:
    on the bow's flare that buried the block's top 0.7 m and stood its foot proud, the user's close-ups of 2026-11-10)"""
    us, ws = np.linspace(-5.5, 5.5, 12), np.linspace(-2.9, 2.9, 13)
    U, W = np.meshgrid(us, ws, indexing="ij")
    A = np.c_[U.ravel(), W.ravel(), np.ones(U.size)]
    for _ in range(2):
        (a, b, c), *_ = np.linalg.lstsq(A, skin(M, us, ws).ravel(), rcond=None)
        R = M.to_3x3()
        ya = (R @ Vector((-a, 1.0, -b))).normalized()
        za = (R @ Vector((1, 0, 0))).cross(ya).normalized()
        xa = ya.cross(za).normalized()
        M = Matrix.Translation(M @ Vector((0, c, 0))) @ Matrix((xa, ya, za)).transposed().to_4x4()
    return M


def wrap_map(M):
    """a side block bent onto the hull's skin (the flare curves up to 0.8 m over a block's height; it is straight along
    it): each of the body's grid lines up the side (VLSS_WS, as arc length from the block's middle) gets its place on
    the skin's profile (wmap), and each grid point the skin's height there (G), so the face keeps its true lengths (the
    lids still fit their cells) and lies on the skin. A knuckle of the skin between two lines lifts the whole block by
    what it would bury (`lift`); `gap` is the most the face then stands off the skin."""
    du, dw = np.linspace(-6.0, 6.0, 25), np.linspace(-3.6, 3.6, 145)
    Y = skin(M, du, dw)
    prof = np.median(Y, axis=0)
    arc = np.concatenate(([0.0], np.cumsum(np.hypot(np.diff(dw), np.diff(prof)))))
    arc -= np.interp(0.0, dw, arc)
    us, ws = np.array(VLSS_US), np.array(VLSS_WS)
    wmap = np.interp(ws, arc, dw)
    G = np.array([[bilin(du, dw, Y, u, w) for w in wmap] for u in us])
    off = [(Y[a, k] - bilin(us, ws, G, u, float(np.interp(w, wmap, ws))))
           for a, u in enumerate(du) if abs(u) <= 5.5 for k, w in enumerate(dw) if wmap[0] <= w <= wmap[-1]]
    lift = max(max(off), 0.0)
    return us, ws, G + lift, wmap, {"bend_m": round(float(prof.max() - prof.min()), 3), "lift_m": round(lift, 3),
                                    "gap_m": round(lift - min(off), 3)}


for side, s in (("L", 1), ("R", -1)):
    for i, x in enumerate((150.0, 172.0, 194.0, 216.0)):
        w = cast((x, 80.0 * s, 5.0), (0, -s, 0))[1]
        edge = deck_z(x, w.y - 1.2 * s)                            # the deck's edge here: the blocks follow the sheer
        hit = cast((x, 80.0 * s, edge - 4.6), (0, -s, 0))
        nrm = hit[2]
        fwd = Vector((0, 0, 1)).cross(nrm).normalized()
        if fwd.x < 0:
            fwd = -fwd
        xa = fwd if s > 0 else -fwd                                # starboard: the same block turned 180 deg (+X aft)
        ya = nrm
        za = xa.cross(ya).normalized()
        xa = ya.cross(za).normalized()
        M = fit_frame(Matrix.Translation(hit[1]) @ Matrix((xa, ya, za)).transposed().to_4x4())
        us, ws, G, wmap, fit = wrap_map(M)
        name = "TANA_VLSS_%s%d" % (side, i + 1)
        body = copy_of("VLSS_body", name, M, SHIP)
        me = TYPES["VLSS_body"][0].copy()                          # this block's own body: the type's, bent onto the skin
        me.name = name                                             # here (same faces, UVs and texture)
        for v in me.vertices:
            v.co = (v.co.x, v.co.y + bilin(us, ws, G, v.co.x, v.co.z), float(np.interp(v.co.z, ws, wmap)))
        me.update()
        body.data = me
        check(me)
        CHECK[name]["on_the_hull"] = fit
        print("model: %s on the hull's skin: bent %.2f m over its height, lifted %.3f m, its face at most %.3f m off it"
              % (name, fit["bend_m"], fit["lift_m"], VLSS_FACE + fit["gap_m"]))
        ya = M.to_3x3() @ Vector((0, 1, 0))
        level_out = Vector((ya.x, ya.y, 0)).normalized()
        launch = (level_out * math.cos(SIDE_UP) + Vector((0, 0, 1)) * math.sin(SIDE_UP)).normalized()
        hs = []
        for k, (cx, cz) in enumerate(VLSS_CELLS, 1):
            sh = cz + 0.98                                         # the hinge line; the lid hangs 1.95 m down the face
            ss = np.linspace(sh - 1.95, sh, 14)
            pw = np.interp(ss, ws, wmap)
            py = np.array([max(bilin(us, ws, G, cx + d, t) for d in (-1.05, 0.0, 1.05)) for t in ss]) + VLSS_FACE
            slope = float(np.polyfit(pw, py, 1)[0])                # the lid lies along its own cell's stretch of the skin,
            wh = float(np.interp(sh, ws, wmap))                    # 1 cm clear of the face's highest point under it
            yh = float(np.max(py - slope * (pw - wh))) + 0.01
            hinge = Matrix.Translation((cx, yh, wh)) @ Matrix.Rotation(-math.atan(slope), 4, "X")
            h = copy_of("VLSS_hatch", "TANA_VLSS_%s%d_Hatch_%02d" % (side, i + 1, k), M @ hinge, body)
            hs.append((h, hinge))
            at = M @ Vector((cx, bilin(us, ws, G, cx, cz) + VLSS_FACE - 0.2, float(np.interp(cz, ws, wmap))))
            empty("TANA_VLSS_%s%d_SOC_Vls_%02d" % (side, i + 1, k), frame(launch, Vector((0, 0, 1)), at), body, 0.6, coll=ADD)
        hatches[body.name] = ("vlss", hs)
        made["vlss"].append(body)
for a, b in zip(made["vlss"][:4], made["vlss"][4:]):               # port and starboard stand as a mirrored pair
    ta, tb = a.matrix_world.translation, b.matrix_world.translation
    assert abs(ta.x - tb.x) < 0.05 and abs(ta.y + tb.y) < 0.3 and abs(ta.z - tb.z) < 0.3, \
        "%s at %s and %s at %s are not a mirrored pair" % (a.name, tuple(ta), b.name, tuple(tb))


def open_hatches(names, frac):
    """frac 0 closed .. 1 open (HATCH_OPEN's angle) for the blocks named"""
    for b in names:
        kind, hs = hatches[b]
        axis, deg = HATCH_OPEN[kind]
        body = bpy.data.objects[b]
        for h, hinge in hs:
            h.matrix_world = body.matrix_world @ hinge @ Matrix.Rotation(math.radians(deg) * frac, 4, axis)


# ---------------------------------------------------------------------------------------------------- hull sockets
def heading_of(house, guns):
    """where a mount's guns point at rest. On the straightened ship (straighten.py) every Iowa mount rests dead ahead,
    astern or abeam, so a heading within 2 deg of a quarter turn IS that quarter turn: measured from the guns'
    vertices alone it came out 0.2-0.3 deg off (a vertex centroid isn't the mount's middle), and every part exported
    in its socket's frame (export_tanacorn.py) had its guns that far off its own forward axis."""
    hp = house.matrix_world.translation
    gv = [guns.matrix_world @ v.co for v in guns.data.vertices]
    c = sum(gv, Vector()) / len(gv)
    a = math.atan2(c.y - hp.y, c.x - hp.x)
    q = round(a / (math.pi / 2)) * (math.pi / 2)
    return q if abs(a - q) < math.radians(2.0) else a


def ue_cm(v):
    return [round(v.x * 100, 1), round(-v.y * 100, 1), round(v.z * 100, 1)]


sockets = []


def mount(name, M, note="", extra=None):
    empty("SOCKET_Mount_%s" % name, M, HULL, 3.0)
    fwd = M.to_3x3() @ Vector((1, 0, 0))
    sockets.append({"name": "Mount_%s" % name, "loc_cm": ue_cm(M.translation),
                    "yaw": round(-math.degrees(math.atan2(fwd.y, fwd.x)), 2),
                    "pitch": round(math.degrees(math.asin(max(-1.0, min(1.0, fwd.z)))), 2),
                    **({"note": note} if note else {}), **(extra or {})})


def yaw_at(at, yaw):
    return Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, "Z")


for tag in ("FWD", "AFT"):
    t, g = bpy.data.objects["LEV_T16_%s.001" % tag], bpy.data.objects["LEV_G16_%s.001" % tag]
    mount("T16_" + tag, yaw_at(t.matrix_world.translation, heading_of(t, g)))
for i in range(1, 7):
    t, g = bpy.data.objects["LEV_IOWA_T5_%d.001" % i], bpy.data.objects["LEV_IOWA_G5_%d.001" % i]
    mount("T5_%d" % i, yaw_at(t.matrix_world.translation, heading_of(t, g)))
for i in range(1, 5):
    t, g = bpy.data.objects["LEV_IOWA_CIWS_%d.001" % i], bpy.data.objects["LEV_IOWA_CG_%d.001" % i]
    mount("CIWS_%d" % i, yaw_at(t.matrix_world.translation, heading_of(t, g)))
for house, gun in made["laser"]:
    mount("LASER_" + house.name[len("TANA_LASER_"):-len("_house")], house.matrix_world.copy())
for o in made["vlsd"] + made["vlss"]:
    kind, hs = hatches[o.name]
    axis, deg = HATCH_OPEN[kind]
    mount(o.name.replace("TANA_", ""), o.matrix_world.copy(), extra={"hatches": [
        {"hinge_cm": ue_cm(hinge.translation), "axis": axis, "open_deg": deg, "open_s": 0.5,
         "rest_deg": round(math.degrees(hinge.to_euler("XYZ")["XYZ".index(axis)]), 2)} for _, hinge in hs]})
for side in ("L", "R"):
    mount("RAILGUN_" + side, yaw_at(bpy.data.objects["railgun_%s" % side].matrix_world.translation, 0.0))
mount("RAILCANNON", yaw_at(bpy.data.objects["railcannon_bay"].matrix_world.translation, 0.0))
mount("CORE", yaw_at(Vector((0.0, 0.0, 20.0)), 0.0),
      note="provisional: inside the superstructure amidships; the phase-3 core's look and place are WP11's")

parts = {"16-inch triple": 2, "5-inch twin": 6, "CIWS": 4, "laser": len(made["laser"]), "deck VLS": len(made["vlsd"]),
         "side VLS": len(made["vlss"]), "sub-railgun": 2, "railcannon": 1, "core": 1}
with open(os.path.join(OUT, "tanacorn_hull_sockets.json"), "w") as f:
    json.dump({"ship": "TANACORN (the Leviathan design + model_tanacorn.py)", "units": "UE cm, yaw / pitch degrees",
               "parts": parts, "sockets": sockets}, f, indent=1)
with open(os.path.join(OUT, "tanacorn_model_check.json"), "w") as f:
    json.dump({**CHECK, "LEV_HULL uv map": HULL_UV}, f, indent=1)
print("model: %d hull sockets; parts %s" % (len(sockets), parts))
print("model: every part clean: %s" % all(r.get("clean") for r in CHECK.values()))
for o in [h for h, _ in made["laser"]] + made["vlsd"] + made["vlss"]:
    t = o.matrix_world.translation
    print("model: %-18s at (%.1f, %.1f, %.1f) m" % (o.name, t.x, t.y, t.z))

# every VLS hatch keyed into the design's deploy sequence (30 fps, frames 1-360: the doors and turrets open by ~150): all
# 128 open together at HATCH_KEYS' first pair (0.5 s, the game's open_s), hold, and shut at the second; Bezier keys, so
# each swing eases in and out. Each hatch's basis is its hinge (a translation) times one rotation about HATCH_OPEN's axis.
HATCH_KEYS = ((150, 165), (290, 305))
for b, (kind, hs) in hatches.items():
    axis, deg = HATCH_OPEN[kind]
    i = "XYZ".index(axis)
    for h, hinge in hs:
        h.matrix_basis = hinge.copy()
        h.rotation_mode = "XYZ"
        rest = h.rotation_euler[i]                 # (a side lid's rest: tilted to its cell's stretch of the hull)
        for f, a in ((HATCH_KEYS[0][0], 0.0), (HATCH_KEYS[0][1], deg), (HATCH_KEYS[1][0], deg), (HATCH_KEYS[1][1], 0.0)):
            h.rotation_euler[i] = rest + math.radians(a)
            h.keyframe_insert("rotation_euler", index=i, frame=f)
        h.animation_data.action.name = h.name + "_open"
print("model: %d hatches keyed: open %d-%d, shut %d-%d (30 fps)" % (sum(len(hs) for _, hs in hatches.values()),
      HATCH_KEYS[0][0], HATCH_KEYS[0][1], HATCH_KEYS[1][0], HATCH_KEYS[1][1]))

# the laser turrets slew in the same sequence, so the file shows every moving part working (the user, 2026-11-10: "a shot
# of all animations working"): each house trains 70 deg outboard and its director lifts 35 deg (LASER_KEYS' first
# pair), holds, and comes back (the second)
LASER_KEYS = ((60, 100), (200, 240))
for house, gun in made["laser"]:
    t = house.matrix_world.translation
    port = 1.0 if t.y > centre_y(t.x) else -1.0
    ahead = 1.0 if (house.matrix_world.to_3x3() @ Vector((1, 0, 0))).x > 0 else -1.0
    for o, i, swing in ((house, 2, math.radians(70.0) * port * ahead), (gun, 1, -math.radians(35.0))):
        o.rotation_mode = "XYZ"
        rest = o.rotation_euler[i]
        for f, a in ((LASER_KEYS[0][0], 0.0), (LASER_KEYS[0][1], swing), (LASER_KEYS[1][0], swing), (LASER_KEYS[1][1], 0.0)):
            o.rotation_euler[i] = rest + a
            o.keyframe_insert("rotation_euler", index=i, frame=f)
        o.animation_data.action.name = o.name + "_slew"
print("model: %d laser turrets keyed: out %d-%d, back %d-%d" % (len(made["laser"]), LASER_KEYS[0][0], LASER_KEYS[0][1],
                                                               LASER_KEYS[1][0], LASER_KEYS[1][1]))

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Tanacorn_model.blend"), compress=False, copy=True)
for _, hs in hatches.values():                     # the renders below pose the hatches themselves (open_hatches)
    for h, hinge in hs:
        h.animation_data_clear()
for house, gun in made["laser"]:                   # (and show the lasers at rest)
    house.animation_data_clear()
    gun.animation_data_clear()
print("model: saved", os.path.join(OUT, "Tanacorn_model.blend"))


# ---------------------------------------------------------------------------------------------------- renders
def camera(name, loc, look, lens=50.0):
    cam = bpy.data.objects.get(name)
    if not cam:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        bpy.context.scene.collection.objects.link(cam)
    cam.location = loc
    d = Vector(look) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    cam.data.clip_end = 20000.0
    return cam


def wire_mat():
    m = bpy.data.materials.get("TANA_wire_review") or bpy.data.materials.new("TANA_wire_review")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bs.inputs["Base Color"].default_value = (0.35, 0.37, 0.4, 1)
    wf = nt.nodes.new("ShaderNodeWireframe")
    wf.use_pixel_size, wf.inputs["Size"].default_value = True, 1.0
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.inputs["Color1"].default_value = (0.35, 0.37, 0.4, 1)
    mix.inputs["Color2"].default_value = (0.02, 0.02, 0.02, 1)
    nt.links.new(wf.outputs["Fac"], mix.inputs["Fac"])
    nt.links.new(mix.outputs["Color"], bs.inputs["Base Color"])
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    return m


PART_NAMES = {"LASER_house": "laser turret: house (yaw)", "LASER_gun": "laser turret: beam director (pitch)",
              "VLSD_body": "deck VLS block", "VLSD_hatch": "deck VLS hatch", "VLSS_body": "side VLS block",
              "VLSS_hatch": "side VLS hatch"}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def part_sheet(path, wire):
    """every part type in its own close-up, in one 3 x 2 sheet (the six on one line were specks in one frame)"""
    import subprocess
    sc = bpy.context.scene
    res = (sc.render.resolution_x, sc.render.resolution_y)
    sc.render.resolution_x, sc.render.resolution_y = 800, 600
    tiles = []
    for i, (key, (me, proto)) in enumerate(TYPES.items()):
        bb = [proto.matrix_world @ Vector(c) for c in proto.bound_box]
        c = sum(bb, Vector()) / 8.0
        r = max((q - c).length for q in bb)
        d = Vector((0.8, 1.0, 0.55)) if key.startswith("VLSS") else Vector((0.9, 1.0, 0.75))   # the sun's side (+Y)
        sc.camera = camera("CAM_T_part", c + d.normalized() * r * 3.6, c, 50)
        sc.render.filepath = path[:-4] + "_%d.png" % i
        bpy.ops.render.render(write_still=True)
        tiles.append(sc.render.filepath)
    sc.render.resolution_x, sc.render.resolution_y = res
    ins, flt = [], []
    for i, (t, key) in enumerate(zip(tiles, TYPES)):
        ins += ["-i", t]
        text = "drawtext=fontfile=%s:text='%s':x=24:y=24:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=8" \
               % (FONT, PART_NAMES[key].replace(":", "\\:"))
        flt.append("[%d:v]%s[t%d]" % (i, text if os.path.exists(FONT) else "null", i))
    flt.append("".join("[t%d]" % i for i in range(len(tiles))) + "xstack=inputs=6:layout=0_0|800_0|1600_0|0_600|800_600|1600_600")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error"] + ins + ["-filter_complex", ";".join(flt), "-frames:v", "1", path],
                   check=True)
    for t in tiles:
        os.remove(t)


SKY = next((n for n in bpy.context.scene.world.node_tree.nodes if n.bl_idname == "ShaderNodeTexSky"), None)
SUN_ROT = SKY.sun_rotation if SKY else 0.0


def fill_light(on):
    """the starboard views: the design's sun (its sky's, to port) mirrored to starboard, or that side renders near black
    (a second sun lamp only made hot glints on the hull's gloss)"""
    if SKY:
        SKY.sun_rotation = math.pi - SUN_ROT if on else SUN_ROT


def close_cam(name, body, out, up, along=0.0, lens=40):
    """a close-up of one side block: `out` m off its face, `up` m above its middle, `along` m along the hull"""
    M = body.matrix_world
    return camera(name, M @ Vector((along, out, 0)) + Vector((0, 0, up)), M.translation, lens)


sc = bpy.context.scene
if RENDER or ANIM:
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = int(os.environ.get("TANA_SAMPLES", "48"))
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    aft_open = ["TANA_VLSD_%d" % k for k in (1, 2, 3, 4)]
    side_open = ["TANA_VLSS_L1", "TANA_VLSS_L2", "TANA_VLSS_R1", "TANA_VLSS_R2"]
    shots = [
        ("01_full", camera("CAM_T_full", (420, 620, 300), (-20, 0, 10), 45), []),
        ("02_aft_vls", camera("CAM_T_aft", (-330, 95, 75), (-236, 0, 8), 55), aft_open),
        ("03_bow_side_vls_L", camera("CAM_T_bow_side", (265, 95, 22), (183, 18, 5), 50), side_open),
        ("04_bow_side_vls_R", camera("CAM_T_bow_side_R", (265, -95, 22), (183, -16, 5), 50), side_open),
        ("05_laser_fwd", camera("CAM_T_laser_fwd", (82, 46, 30), (50, 0, 15), 50), []),
        ("06_laser_aft", camera("CAM_T_laser_aft", (-140, 52, 46), (-100, 0, 24), 50), []),
        ("07_parts", camera("CAM_T_parts", (0, 330, 40), (0, 420, 8), 50), []),
        ("08_parts_wire", camera("CAM_T_parts", (0, 330, 40), (0, 420, 8), 50), []),
        ("09_top", camera("CAM_T_top", (0, 0, 1300), (0, 0, 0), 30), []),
        ("10_side_vls_flush_L", close_cam("CAM_T_flush_L", bpy.data.objects["TANA_VLSS_L4"], 9, 1.5, 17, 35), ["TANA_VLSS_L3"]),
        ("11_side_vls_flush_L1", close_cam("CAM_T_flush_L1", bpy.data.objects["TANA_VLSS_L1"], 16, 3, -9, 40), []),
        ("12_side_vls_flush_R", close_cam("CAM_T_flush_R", bpy.data.objects["TANA_VLSS_R4"], 9, 1.5, -17, 35), ["TANA_VLSS_R3"]),
    ]
    only = os.environ.get("TANA_SHOTS") or ("" if RENDER else "none")
    os.makedirs(os.path.join(OUT, "renders"), exist_ok=True)
    for tag, cam, opened in shots:
        if only and tag not in only.split(","):
            continue
        open_hatches(list(hatches), 0.0)
        open_hatches(opened, 1.0)
        sc.view_layers[0].material_override = wire_mat() if tag.endswith("_wire") else None
        sc.camera = cam
        sc.render.filepath = os.path.join(OUT, "renders", "tanacorn_%s.png" % tag)
        fill_light(tag.endswith("_R"))
        if "_parts" in tag:
            part_sheet(sc.render.filepath, tag.endswith("_wire"))
        else:
            bpy.ops.render.render(write_still=True)
        print("model: rendered tanacorn_%s.png" % tag)
    sc.view_layers[0].material_override = None
    fill_light(False)
    open_hatches(list(hatches), 0.0)


if ANIM:
    import shutil, subprocess
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.cycles.samples = int(os.environ.get("TANA_ANIM_SAMPLES", "24"))
    sc.view_layers[0].material_override = None
    d1, l1 = bpy.data.objects["TANA_VLSD_1"], bpy.data.objects["TANA_VLSS_L1"]
    views = [
        ("aft_deck", camera("CAM_T_aft", (-330, 95, 75), (-236, 0, 8), 55)),
        ("aft_deck_close", camera("CAM_A_deck_close", d1.matrix_world.translation + Vector((14, 16, 9)),
                                  d1.matrix_world.translation, 40)),
        ("bow_L", camera("CAM_T_bow_side", (265, 95, 22), (183, 18, 5), 50)),
        ("bow_L_close", close_cam("CAM_A_bow_L_close", l1, 22, 5, 6)),
        ("bow_R", camera("CAM_T_bow_side_R", (265, -95, 22), (183, -16, 5), 50)),
    ]
    want = os.environ.get("TANA_ANIM_VIEWS")
    FR, STEPS = 30, 15                                     # 0.5 s open = 15 frames at 30 fps
    adir = os.path.join(OUT, "renders", "anim")
    os.makedirs(adir, exist_ok=True)
    clips = []
    for tag, cam in views:
        if want and tag not in want.split(","):
            continue
        sc.camera = cam
        fill_light(tag.endswith("_R"))
        poses = []
        for k in range(STEPS + 1):                         # the open swing's frames; the shut is the same, reversed
            f = k / STEPS
            open_hatches(list(hatches), f * f * (3 - 2 * f))
            sc.render.filepath = os.path.join(adir, "%s_%02d.png" % (tag, k))
            bpy.ops.render.render(write_still=True)
            poses.append(sc.render.filepath)
        print("model: animated", tag)
        seq = [poses[0]] * 15 + poses + [poses[-1]] * 30 + poses[::-1] + [poses[0]] * 15
        sdir = os.path.join(adir, "seq_" + tag)
        shutil.rmtree(sdir, ignore_errors=True)
        os.makedirs(sdir)
        for i, src in enumerate(seq):
            shutil.copyfile(src, os.path.join(sdir, "%04d.png" % i))
        clip = os.path.join(adir, "tanacorn_hatches_%s.mp4" % tag)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FR), "-i", os.path.join(sdir, "%04d.png"),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", clip], check=True)
        shutil.rmtree(sdir)
        clips.append(clip)
        print("model: clip", clip)
    if len(clips) > 1:
        lst = os.path.join(adir, "clips.txt")
        with open(lst, "w") as f:
            f.write("".join("file '%s'\n" % c for c in clips))
        allc = os.path.join(adir, "tanacorn_hatches.mp4")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", allc],
                       check=True)
        print("model: clip", allc)
    open_hatches(list(hatches), 0.0)
