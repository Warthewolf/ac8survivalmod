"""styles_firemode.py : Blender 3.3, one of firemode.py's eight turret styles built and rendered for the user's choice.

  blender -b <model without the mount> -P tools/tanicorn/styles_firemode.py -- <out dir> <style 1-8> [stowed]

The model without the mount: model_tanacorn.py with TANA_FM_STYLE=0 (the design's Iowa mount; the style is built here,
untextured: firemode.BAKE off). At night, as the user's reference stills are (the sun 4 deg under the horizon, a cold
moon lamp, the glow doing the rest). Turret B (LEV_T16_FWD), three views each like one of the stills:
  style<N>_1_overhead  from above and behind the turret, its guns lifted 12 deg, transformed and charging
  style<N>_2_firing    low ahead of it, its guns lifted 30 deg, firing: the cores white-gold, green lightning from the
                       cores to the open pieces and between them, green rings round the muzzles
  style<N>_3_side      its port side close up, transformed (the armour off its bays)
  style<N>_4_front     from ahead, above and to port, transformed: the opened guns and the face
  stowed               (with `stowed`) the turret shut, before it transforms (the same for every style)
The lightning, rings and flash are the preview's own (PREVIEW_*); in the game they are AC8's own effects (hard rule 58).
TANA_FM_SAMPLES (12), TANA_FM_RES (1280x720).
"""
import bpy, sys, os, math, random
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, STYLE = os.path.abspath(argv[0]), int(argv[1])
STOWED = "stowed" in argv[2:]
os.makedirs(OUT, exist_ok=True)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tanakit
sc = bpy.context.scene
tanakit.WORK = bpy.data.collections.get("TANACORN prototypes") or bpy.data.collections.new("TANACORN prototypes")
if tanakit.WORK.name not in sc.collection.children:
    sc.collection.children.link(tanakit.WORK)
tanakit.TEX = os.path.join(OUT, "textures")
import firemode
firemode.BAKE = False
coll = bpy.data.collections.new("TANACORN fire mode")
sc.collection.children.link(coll)
firemode.build(coll, style=STYLE)
T = firemode.TURRET["FWD"]
for o in [T.house, T.trun]:
    o.animation_data_clear()
for o in bpy.data.objects:
    if o.name.endswith("_proto"):
        o.hide_render = True

# ---------------------------------------------------------------------------------------------------- night
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = int(os.environ.get("TANA_FM_SAMPLES", "12"))
sc.cycles.use_denoising = True
sc.render.resolution_x, sc.render.resolution_y = [int(v) for v in os.environ.get("TANA_FM_RES", "1280x720").split("x")]
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = "PNG"
SKY = next((n for n in sc.world.node_tree.nodes if n.bl_idname == "ShaderNodeTexSky"), None)
BG = next((n for n in sc.world.node_tree.nodes if n.bl_idname == "ShaderNodeBackground"), None)
if SKY:
    SKY.sun_elevation = math.radians(-4.0)
if BG:
    BG.inputs["Strength"].default_value = 1.0
moon = bpy.data.objects.new("PREVIEW_moon", bpy.data.lights.new("PREVIEW_moon", "SUN"))
sc.collection.objects.link(moon)
moon.data.energy, moon.data.color, moon.data.angle = 1.1, (0.55, 0.68, 1.0), math.radians(1.0)
sc.view_settings.exposure = 1.2
cam = bpy.data.objects.new("CAM_styles", bpy.data.cameras.new("CAM_styles"))
sc.collection.objects.link(cam)
cam.data.clip_end = 20000.0
sc.camera = cam
C = T.house.matrix_world.translation.copy()


def aim(loc, look, lens):
    loc, look = Vector(loc), Vector(look)
    cam.location = loc
    cam.rotation_euler = (look - loc).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    d = (loc - look).normalized()                              # the moon over the camera's shoulder, high
    moon.rotation_euler = (-d + Vector((0.4, -0.3, -1.2))).normalized().to_track_quat("-Z", "Y").to_euler()


# ---------------------------------------------------------------------------------------------------- effects
def emit_mat(name, rgb):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out, em = nt.nodes.new("ShaderNodeOutputMaterial"), nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1.0)
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m, em


ARC, ARC_EM = emit_mat("PREVIEW_arc", (0.25, 1.0, 0.18))
RING, RING_EM = emit_mat("PREVIEW_ring", (0.2, 0.85, 0.3))
FX = bpy.data.collections.new("PREVIEW_fx")
sc.collection.children.link(FX)
BS = firemode.STYLES[STYLE]["barrel"]
EXT = BS.get("extend", 0.0)


def clear_fx():
    for o in list(FX.objects):
        d = o.data
        bpy.data.objects.remove(o)
        if d and d.users == 0:
            (bpy.data.curves if isinstance(d, bpy.types.Curve) else bpy.data.meshes).remove(d)


def poly(points, width, mat):
    cu = bpy.data.curves.new("PREVIEW_arc", "CURVE")
    cu.dimensions, cu.bevel_depth, cu.bevel_resolution = "3D", width, 1
    sp = cu.splines.new("POLY")
    sp.points.add(len(points) - 1)
    for p, q in zip(sp.points, points):
        p.co = (*q, 1.0)
    ob = bpy.data.objects.new("PREVIEW_arc", cu)
    ob.data.materials.append(mat)
    FX.objects.link(ob)


def jag(a, b, amp, steps, rnd):
    d = b - a
    p1 = d.orthogonal().normalized()
    p2 = d.cross(p1).normalized()
    return [a + d * (i / steps) + ((p1 * rnd.uniform(-amp, amp) + p2 * rnd.uniform(-amp, amp)) if 0 < i < steps else Vector())
            for i in range(steps + 1)]


def ring(c, axis, radius, width):
    pts = []
    a = axis.normalized()
    u = a.orthogonal().normalized()
    v = a.cross(u)
    for i in range(49):
        t = 2 * math.pi * i / 48
        pts.append(c + (u * math.cos(t) + v * math.sin(t)) * radius)
    poly(pts, width, RING)


def barrel_frame(b):
    yc = firemode.GUN_Y[b - 1]
    M = T.trun.matrix_world
    return M, yc, (M.to_3x3() @ Vector((1, 0, 0))).normalized()


def core_point(b, x):
    M, yc, _ = barrel_frame(b)
    return M @ Vector((x, yc, 0.0))


def piece_point(ob, x, r):
    a = math.radians(ob["fm_dir"])
    return ob.matrix_world @ Vector((x, r * math.cos(a), r * math.sin(a)))


def effects(level, firing, seed):
    """level 0..1 the charge (arcs, core glow), firing: the shot's rings and flash"""
    clear_fx()
    if level <= 0:
        return
    rnd = random.Random(seed)
    ARC_EM.inputs["Strength"].default_value = 2.5 + 2.0 * firing      # (green stays green: brighter goes white)
    RING_EM.inputs["Strength"].default_value = 1.6
    pieces = [o for o in T.pieces() if "fm_barrel" in o]
    L = firemode.MUZZLE - firemode.SPLIT
    for b in (1, 2, 3):
        mine = [o for o in pieces if o["fm_barrel"] == b]
        for _ in range(int(2 + 4 * level)):                 # from the core to the open pieces, inside the gun
            x = rnd.uniform(0.35, 0.97) * L
            o = rnd.choice(mine)
            poly(jag(core_point(b, firemode.SPLIT + x + EXT), piece_point(o, x, firemode.BORE - 0.05), 0.08, 5, rnd), 0.02, ARC)
        M, yc, fwd = barrel_frame(b)
        tip = core_point(b, firemode.MUZZLE + EXT)
        if firing:                                          # two rings ahead of the muzzle, a few sparks off it
            for k in range(2):
                ring(tip + fwd * (1.5 + 3.0 * k), fwd, 1.3 + 0.9 * k, 0.035)
            for _ in range(3):
                a = tip + fwd * rnd.uniform(0.3, 2.5)
                poly(jag(a, a + fwd.orthogonal().normalized() * rnd.uniform(1.0, 2.2) + fwd * rnd.uniform(0, 2), 0.3, 5, rnd),
                     0.02, ARC)


def render(name):
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("styles: rendered", name)


# ---------------------------------------------------------------------------------------------------- the views
if STOWED:
    T.trun.rotation_euler.y = -math.radians(12.0)
    firemode.pose(0.0)
    effects(0, 0, 0)
    aim(C + Vector((46, 30, 12)), C + Vector((10, 2, 4)), 30)
    render("stowed")
T.trun.rotation_euler.y = -math.radians(12.0)
firemode.pose(1.0, {"fm_core": 0.6})
effects(0.4, 0, 3)
aim(C + Vector((-20, -34, 42)), C + Vector((11, 0, 2)), 26)
render("style%d_1_overhead" % STYLE)
firemode.pose(1.0, {"fm_core": 0.6})
effects(0.4, 0, 5)
aim(C + Vector((62, 30, 26)), C + Vector((17, 0, 6)), 30)
render("style%d_4_front" % STYLE)
T.trun.rotation_euler.y = -math.radians(30.0)
firemode.pose(1.0, {"fm_core": 1.6, "fm_rail": 1.2})
effects(1.0, 1, 7)
aim(C + Vector((58, 7, 5)), C + Vector((14, 1, 13)), 30)
render("style%d_2_firing" % STYLE)
T.trun.rotation_euler.y = -math.radians(10.0)
firemode.pose(1.0)
effects(0.3, 0, 11)
aim(C + Vector((5, 36, 6)), C + Vector((1, 0, 3.6)), 28)
render("style%d_3_side" % STYLE)
