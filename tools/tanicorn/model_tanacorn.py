"""model_tanacorn.py : Blender 3.3, THE TANACORN's model from the Leviathan design (docs/design/INVINCIBLE_FLEET.md WP0).

  blender -b art/tanicorn/design/Leviathan_animated.blend -P tools/tanicorn/model_tanacorn.py -- <out dir> [render]

The design (Sea Power's Iowa fused with AC8's Alicorn: the user's dev install only, never shipped) is the ship as it is;
this script adds what the settled armament needs that neither source ship has, and the hull's mount sockets:
  - 4 laser interceptor turrets at the design's LEV_LASER_* corners (our own: a turret ring and housing that train, an
    emitter that elevates; teal lens), split as tools/tanicorn's mounts are: TANA_LASER_<pos>_house (turret_yaw) and
    TANA_LASER_<pos>_gun (turret_pitch, its origin the pitch pivot), the beam's socket SOC_Gun_01 at the emitter's tip;
  - 8 deck VLS blocks on the aft deck behind turret C (TANA_VLSD_1..8: 8 hatches each, sockets SOC_Vls_01..08 up);
  - 8 side VLS blocks on the bow's flanks, 4 a side (TANA_VLSS_L1..4 / R1..4: 8 cells each, lids canted outward,
    sockets SOC_Vls_01..08 along each cell's launch line: out of the hull's side and up);
  - SOCKET_Mount_* empties on the hull for every part (2 x 16-inch, 6 x 5-inch, 4 CIWS, 4 lasers, 16 VLS, 2
    sub-railguns, the railcannon, the core), written to <out>/tanacorn_hull_sockets.json in UE's frame (cm; x fwd, y
    right, z up; yaw / pitch in degrees, a socket's +X its forward).
Writes <out>/Tanacorn_model.blend and, with `render`, <out>/renders/*.png (Cycles on the CPU).
"""
import bpy, bmesh, sys, os, json, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("build/tanicorn/model")
RENDER = "render" in argv[1:]
os.makedirs(OUT, exist_ok=True)

SHIP = bpy.data.objects["LEV_ship"]
HULL = bpy.data.objects["LEV_HULL.001"]
COLL = bpy.data.collections["5 LEVIATHAN animated"]
ADD = bpy.data.collections.get("TANACORN additions") or bpy.data.collections.new("TANACORN additions")
if ADD.name not in [c.name for c in COLL.children]:
    COLL.children.link(ADD)
SOCK = bpy.data.collections.get("TANACORN sockets") or bpy.data.collections.new("TANACORN sockets")
if SOCK.name not in [c.name for c in COLL.children]:
    COLL.children.link(SOCK)
DG = bpy.context.evaluated_depsgraph_get()
SHIP_MESHES = [o for o in COLL.all_objects if o.type == "MESH"]


# ---------------------------------------------------------------------------------------------------- materials
def mat(name, rgb, metal, rough, emit=None, strength=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = strength
    return m


M_PAINT = mat("TANA_paint", (0.085, 0.088, 0.092), 0.65, 0.32)          # the design's Alicorn grey upper works
M_DARK = mat("TANA_dark", (0.030, 0.031, 0.033), 0.5, 0.45)              # hatches, recesses, the emitter's barrel
M_TEAL = mat("TANA_teal", (0.02, 0.35, 0.32), 0.2, 0.25, (0.05, 0.85, 0.75), 6.0)   # the railcannon bay's teal, lit


# ---------------------------------------------------------------------------------------------------- mesh helpers
class Part:
    """bmesh pieces with a material each, made into one object"""
    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def _slot(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _tag(self, geom, m):
        i = self._slot(m)
        for f in [g for g in geom if isinstance(g, bmesh.types.BMFace)]:
            f.material_index = i

    def box(self, size, at, m=M_PAINT, rot=Matrix()):
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=Matrix.Translation(at) @ rot.to_4x4() @ Matrix.Diagonal((*size, 1)))
        self._tag(list({f for v in r["verts"] for f in v.link_faces}), m)

    def cyl(self, r1, r2, depth, at, axis="Z", m=M_PAINT, seg=24, rot=None):
        R = rot.to_4x4() if rot is not None else {"Z": Matrix(), "X": Matrix.Rotation(math.pi / 2, 4, "Y"),
                                                 "Y": Matrix.Rotation(math.pi / 2, 4, "X")}[axis]
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=depth,
                                  matrix=Matrix.Translation(at) @ R)
        self._tag(list({f for v in r["verts"] for f in v.link_faces}), m)

    def make(self, name, collection=ADD, uv_m=4.0):
        me = bpy.data.meshes.new(name)
        uv = self.bm.loops.layers.uv.new("UVMap")
        for f in self.bm.faces:                                   # box mapping, uv_m metres a tile (for texturing later)
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            u, v = [(1, 2), (0, 2), (0, 1)][ax]
            for lp in f.loops:
                lp[uv].uv = (lp.vert.co[u] / uv_m, lp.vert.co[v] / uv_m)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        for p in me.polygons:
            p.use_smooth = False
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
        o = bpy.data.objects.new(name, me)
        collection.objects.link(o)
        return o


def empty(name, M, parent=None, size=1.0, kind="ARROWS", collection=SOCK):
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    e = bpy.data.objects.new(name, None)
    e.empty_display_type, e.empty_display_size = kind, size
    collection.objects.link(e)
    if parent:
        e.parent = parent
    e.matrix_world = M
    return e


def frame(fwd, up=Vector((0, 0, 1)), at=Vector()):
    """a matrix whose +X is fwd and +Z is as near up as it can be"""
    x = fwd.normalized()
    y = up.cross(x).normalized()
    z = x.cross(y)
    R = Matrix((x, y, z)).transposed()
    return Matrix.Translation(at) @ R.to_4x4()


def cast(origin, d):
    best = None
    for o in SHIP_MESHES:
        if o.name.startswith("TANA_"):
            continue
        inv = o.matrix_world.inverted()
        ok, loc, nor, _ = o.ray_cast(inv @ Vector(origin), (inv.to_3x3() @ Vector(d)).normalized(), depsgraph=DG)
        if ok:
            w = o.matrix_world @ loc
            dist = (w - Vector(origin)).length
            if best is None or dist < best[0]:
                best = (dist, w, (o.matrix_world.to_3x3().inverted().transposed() @ nor).normalized())
    return best


def deck_z(x, y):
    h = cast((x, y, 300.0), (0, 0, -1))
    return h[1].z if h else None


# ---------------------------------------------------------------------------------------------------- the parts
def laser_turret(tag, M):
    """M: the mount's base on the deck (+X its rest heading). Returns (house, gun, muzzle socket)."""
    h = Part()
    h.cyl(2.7, 2.7, 0.9, Vector((0, 0, 0.45)), m=M_DARK)                           # the turret ring
    h.cyl(2.35, 2.35, 2.2, Vector((0, 0, 2.0)), seg=8)                             # the armoured housing
    h.cyl(2.35, 1.55, 0.8, Vector((0, 0, 3.5)), seg=8)                             # its chamfered roof
    h.box((0.9, 0.9, 0.55), Vector((-1.0, 0, 4.15)), m=M_DARK)                     # the tracker on the roof
    h.cyl(0.5, 0.5, 0.18, Vector((-1.0, 0, 4.5)), m=M_TEAL, seg=16)                # its sensor glass
    for s in (1, -1):                                                              # the cheeks the emitter rides in
        h.box((1.9, 0.38, 1.9), Vector((1.0, 1.32 * s, 3.05)))
    house = h.make("TANA_LASER_%s_house" % tag)
    house.matrix_world = M
    house.parent = SHIP
    house.matrix_parent_inverse = SHIP.matrix_world.inverted()
    pivot = Vector((1.0, 0, 3.05))
    g = Part()                                                                     # the emitter, along +X from its pivot
    g.cyl(0.62, 0.62, 1.3, Vector((0.1, 0, 0)), axis="X", m=M_DARK, seg=16)        # the trunnion block
    g.cyl(0.52, 0.42, 4.2, Vector((2.4, 0, 0)), axis="X", seg=16)                  # the barrel
    for k in (1.6, 2.4, 3.2):                                                      # cooling rings
        g.cyl(0.62, 0.62, 0.16, Vector((k, 0, 0)), axis="X", m=M_DARK, seg=16)
    g.cyl(0.72, 0.72, 0.45, Vector((4.55, 0, 0)), axis="X", seg=16)                # the muzzle collar
    g.cyl(0.42, 0.42, 0.08, Vector((4.8, 0, 0)), axis="X", m=M_TEAL, seg=16)       # the lens
    gun = g.make("TANA_LASER_%s_gun" % tag)
    gun.parent = house
    gun.matrix_world = M @ Matrix.Translation(pivot)
    sock = empty("TANA_LASER_%s_SOC_Gun_01" % tag, M @ Matrix.Translation(pivot + Vector((4.85, 0, 0))), gun, 0.8, collection=ADD)
    return house, gun, sock


def deck_vls(tag, M):
    """8 cells, 2 x 4, along +X; M: the block's centre on the deck"""
    p = Part()
    p.box((11.2, 6.4, 0.7), Vector((0, 0, 0.35)))                                  # the armoured box
    p.box((11.6, 6.8, 0.18), Vector((0, 0, 0.09)), m=M_DARK)                       # its foot
    socks = []
    n = 0
    for iy, y in enumerate((1.45, -1.45)):
        for ix, x in enumerate((3.9, 1.3, -1.3, -3.9)):
            n += 1
            p.box((2.3, 2.55, 0.14), Vector((x, y, 0.77)), m=M_DARK)               # the hatch lid
            p.box((0.22, 2.55, 0.2), Vector((x - 1.28, y, 0.8)))                   # its hinge
            socks.append((n, Vector((x, y, 0.85))))
    p.box((10.6, 0.35, 0.25), Vector((0, 0, 0.82)))                                # the uptake between the rows
    o = p.make("TANA_VLSD_%s" % tag)
    o.parent = SHIP
    o.matrix_world = M
    for n, at in socks:                                                            # each cell fires straight up
        empty("TANA_VLSD_%s_SOC_Vls_%02d" % (tag, n), M @ frame(Vector((0, 0, 1)), Vector((1, 0, 0)), at), o, 0.6, collection=ADD)
    return o


SIDE_UP = math.radians(35.0)                     # the side cells' launch line: out of the hull, 35 deg above level


def side_vls(tag, M):
    """8 cells, 2 rows x 4, set in the hull's side; M's +Y is outward, +Z up, the block's centre on the hull's skin"""
    p = Part()
    p.box((10.6, 1.4, 5.4), Vector((0, -0.35, 0)))                                 # the casing, sunk into the hull
    p.box((11.0, 0.25, 5.8), Vector((0, 0.3, 0)), m=M_DARK)                        # its frame on the skin
    launch = Vector((0, math.cos(SIDE_UP), math.sin(SIDE_UP)))
    lid_rot = Matrix.Rotation(SIDE_UP, 3, "X")                                     # a lid faces along its launch line
    socks = []
    n = 0
    for z in (1.3, -1.3):
        for x in (-3.9, -1.3, 1.3, 3.9):
            n += 1
            c = Vector((x, 0.55, z))
            p.box((2.2, 0.12, 2.0), c, m=M_DARK, rot=lid_rot)
            socks.append((n, c + launch * 0.2))
    o = p.make("TANA_VLSS_%s" % tag)
    o.parent = SHIP
    o.matrix_world = M
    for n, at in socks:
        empty("TANA_VLSS_%s_SOC_Vls_%02d" % (tag, n), M @ frame(launch, Vector((0, 0, 1)), at), o, 0.6, collection=ADD)
    return o


# ---------------------------------------------------------------------------------------------------- placing them
made = {"laser": [], "vlsd": [], "vlss": []}
for tag, heading in (("FWD_L", 0.0), ("FWD_R", 0.0), ("AFT_L", math.pi), ("AFT_R", math.pi)):
    mk = bpy.data.objects["LEV_LASER_%s" % tag]
    at = mk.matrix_world.translation.copy()
    made["laser"].append(laser_turret(tag, Matrix.Translation(at) @ Matrix.Rotation(heading, 4, "Z")))

n = 0
for x in (-210.0, -228.0, -246.0, -264.0):                    # behind turret C's barrels' sweep (to x -194)
    for y in (16.0, -16.0):
        n += 1
        z = deck_z(x, y)
        made["vlsd"].append(deck_vls(str(n), Matrix.Translation((x, y, z))))

for side, s in (("L", 1), ("R", -1)):
    for i, x in enumerate((150.0, 172.0, 194.0, 216.0)):
        hit = cast((x, 80.0 * s, 5.0), (0, -s, 0))
        n_h = Vector((hit[2].x, hit[2].y, 0)).normalized()      # outward, level (the hull flares: the block stays upright)
        fwd = Vector((0, 0, 1)).cross(n_h).normalized()         # along the hull's side, pointing forward
        if fwd.x < 0:
            fwd = -fwd
        x_axis = fwd if s > 0 else -fwd                         # starboard: the same block turned 180 deg (+X aft)
        y_axis = n_h
        z_axis = x_axis.cross(y_axis)                           # (up on both sides)
        M = Matrix.Translation(hit[1] + n_h * 0.05) @ Matrix((x_axis, y_axis, z_axis)).transposed().to_4x4()
        made["vlss"].append(side_vls("%s%d" % (side, i + 1), M))


# ---------------------------------------------------------------------------------------------------- hull sockets
def heading_of(house, guns):
    hp = house.matrix_world.translation
    gv = [guns.matrix_world @ v.co for v in guns.data.vertices]
    c = sum(gv, Vector()) / len(gv)
    return math.atan2(c.y - hp.y, c.x - hp.x)


sockets = []


def mount(name, at, yaw=0.0, pitch=0.0, note=""):
    M = Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(-pitch, 4, "Y")
    empty("SOCKET_Mount_%s" % name, M, HULL, 3.0)
    sockets.append({"name": "Mount_%s" % name, "loc_cm": [round(at.x * 100, 1), round(-at.y * 100, 1), round(at.z * 100, 1)],
                    "yaw": round(-math.degrees(yaw), 2), "pitch": round(math.degrees(pitch), 2), **({"note": note} if note else {})})


for tag in ("FWD", "AFT"):
    t, g = bpy.data.objects["LEV_T16_%s.001" % tag], bpy.data.objects["LEV_G16_%s.001" % tag]
    mount("T16_" + tag, t.matrix_world.translation, heading_of(t, g))
for i in range(1, 7):
    t, g = bpy.data.objects["LEV_IOWA_T5_%d.001" % i], bpy.data.objects["LEV_IOWA_G5_%d.001" % i]
    mount("T5_%d" % i, t.matrix_world.translation, heading_of(t, g))
for i in range(1, 5):
    t, g = bpy.data.objects["LEV_IOWA_CIWS_%d.001" % i], bpy.data.objects["LEV_IOWA_CG_%d.001" % i]
    mount("CIWS_%d" % i, t.matrix_world.translation, heading_of(t, g))
for house, gun, _ in made["laser"]:
    tag = house.name.split("TANA_LASER_")[1].rsplit("_house", 1)[0]
    mount("LASER_" + tag, house.matrix_world.translation, house.matrix_world.to_euler().z)
for o in made["vlsd"] + made["vlss"]:
    e = o.matrix_world.to_euler()
    mount(o.name.replace("TANA_", ""), o.matrix_world.translation, e.z)
for side in ("L", "R"):
    rg = bpy.data.objects["railgun_%s" % side]
    mount("RAILGUN_" + side, rg.matrix_world.translation, 0.0)
mount("RAILCANNON", bpy.data.objects["railcannon_bay"].matrix_world.translation, 0.0)
mount("CORE", Vector((0.0, 0.0, 20.0)), 0.0, note="provisional: inside the superstructure amidships; the phase-3 core's "
      "look and place are WP11's")

parts = {"16-inch triple": 2, "5-inch twin": 6, "CIWS": 4, "laser": len(made["laser"]), "deck VLS": len(made["vlsd"]),
         "side VLS": len(made["vlss"]), "sub-railgun": 2, "railcannon": 1, "core": 1}
with open(os.path.join(OUT, "tanacorn_hull_sockets.json"), "w") as f:
    json.dump({"ship": "TANACORN (the Leviathan design + model_tanacorn.py)", "units": "UE cm, yaw / pitch degrees",
               "parts": parts, "sockets": sockets}, f, indent=1)
print("model: %d hull sockets; parts %s" % (len(sockets), parts))
for o in [h for h, _, _ in made["laser"]] + made["vlsd"] + made["vlss"]:
    t = o.matrix_world.translation
    print("model: %-18s at (%.1f, %.1f, %.1f) m" % (o.name, t.x, t.y, t.z))

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Tanacorn_model.blend"), compress=False, copy=True)
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


if RENDER:
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = int(os.environ.get("TANA_SAMPLES", "48"))
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.render.resolution_percentage = 100
    sc.render.use_stamp_filename = False
    sc.render.image_settings.file_format = "PNG"
    shots = [
        ("01_full", camera("CAM_T_full", (330, 470, 230), (-10, 0, 10), 50)),
        ("02_aft_vls", camera("CAM_T_aft", (-330, 95, 75), (-236, 0, 8), 55)),
        ("03_bow_side_vls", camera("CAM_T_bow_side", (265, 95, 22), (183, 18, 5), 50)),
        ("04_bow_side_vls_R", camera("CAM_T_bow_side_R", (265, -95, 22), (183, -16, 5), 50)),
        ("05_laser_fwd", camera("CAM_T_laser_fwd", (82, 46, 30), (50, 0, 15), 50)),
        ("06_laser_aft", camera("CAM_T_laser_aft", (-140, 52, 46), (-100, 0, 24), 50)),
        ("07_top", camera("CAM_T_top", (0, 0, 1200), (0, 0, 0), 30)),
    ]
    only = os.environ.get("TANA_SHOTS")
    os.makedirs(os.path.join(OUT, "renders"), exist_ok=True)
    for tag, cam in shots:
        if only and tag not in only.split(","):
            continue
        sc.camera = cam
        sc.render.filepath = os.path.join(OUT, "renders", "tanacorn_%s.png" % tag)
        bpy.ops.render.render(write_still=True)
        print("model: rendered", sc.render.filepath)
