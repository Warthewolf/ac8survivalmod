"""styles_firemode.py : Blender 3.3, one of firemode.py's eight turret styles built and rendered for the user's choice.

  blender -b <model without the mount> -P tools/tanicorn/styles_firemode.py -- <out dir> <style 1-8> [stowed]

The model without the mount: model_tanacorn.py with TANA_FM_STYLE=0 (the design's Iowa mount; the style is built here,
untextured: firemode.BAKE off). At night, as the user's reference stills are (the sun 4 deg under the horizon, a cold
moon lamp, the glow doing the rest). Turret B (LEV_T16_FWD), three views each like one of the stills:
  style<N>_1_overhead  from above and behind the turret, its guns lifted 12 deg, transformed
  style<N>_2_firing    low ahead of it, its guns lifted 30 deg, firing: the cores lit gold (only now: nothing inside
                       glows otherwise), green lightning from the cores to the open pieces, green rings at the muzzles
  style<N>_3_side      its port side close up, transformed (the armour off its bays)
  style<N>_4_front     from ahead, above and to port, transformed: the opened guns and the face
  style<N>_5_inside, _6_inside_front   (a style with the gun house's interior) into it past the blown-out quarters
  style<N>_seq_1..5    (with `sequence`) the transform at t 0, 0.3, 0.55, 0.75, 1
  style<N>_clip_front_1..8, _clip_side_1..6   (with `clip`; `only=clip` renders nothing else) the user's clip's two shots (CLIP_*), step by step:
                       style_sheet.py lays them beside the clip's frames when given their folder
  stowed               (with `stowed`) the turret shut, before it transforms (the same for every style)
The lightning, rings and flash are the preview's own (PREVIEW_*); in the game they are AC8's own effects (hard rule 58).
TANA_FM_SAMPLES (12), TANA_FM_RES (1280x720).
"""
import bpy, sys, os, math, random
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, STYLE = os.path.abspath(argv[0]), int(argv[1])
STOWED = "stowed" in argv[2:]
ONLY = next((a[5:] for a in argv[2:] if a.startswith("only=")), None)
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
moon.data.energy, moon.data.color, moon.data.angle = 2.0, (0.6, 0.72, 1.0), math.radians(1.0)
sc.view_settings.exposure = 1.4
cam = bpy.data.objects.new("CAM_styles", bpy.data.cameras.new("CAM_styles"))
sc.collection.objects.link(cam)
cam.data.clip_end = 20000.0
sc.camera = cam
C = T.house.matrix_world.translation.copy()


def cel_glow():
    """the cores and their rings glow to the camera but light nothing round them, as in the user's clip (an anime's cel
    look): lit by them, the staves' insides read gold"""
    for key in ("fm_core", "fm_ring", "fm_edge"):
        nt = firemode.MAT[key].node_tree
        out = next(n for n in nt.nodes if n.bl_idname == "ShaderNodeOutputMaterial")
        lp, mix, dk = (nt.nodes.new(k) for k in ("ShaderNodeLightPath", "ShaderNodeMixShader", "ShaderNodeBsdfDiffuse"))
        dk.inputs["Color"].default_value = (0.03, 0.03, 0.03, 1.0)
        nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
        nt.links.new(dk.outputs[0], mix.inputs[1])
        nt.links.new(nt.nodes["Principled BSDF"].outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])


def night_world():
    """the clip's sky: deep blue, lighter at the horizon (the views until then keep the design's dusk)"""
    w = bpy.data.worlds.new("PREVIEW_night")
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    tc, sep, ramp = (nt.nodes.new(k) for k in ("ShaderNodeTexCoord", "ShaderNodeSeparateXYZ", "ShaderNodeValToRGB"))
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    ramp.color_ramp.elements[0].color = (0.035, 0.06, 0.24, 1.0)
    ramp.color_ramp.elements[1].position = 0.6
    ramp.color_ramp.elements[1].color = (0.008, 0.014, 0.07, 1.0)
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    sc.world = w
    moon.data.energy = 3.5
    sc.view_settings.view_transform, sc.view_settings.exposure = "Standard", 0.6   # (the cel look keeps its yellows)
    global CLIP_LIGHT
    CLIP_LIGHT = True


cel_glow()


CLIP_LIGHT = False


def aim(loc, look, lens):
    loc, look = Vector(loc), Vector(look)
    cam.location = loc
    cam.rotation_euler = (look - loc).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    d = (loc - look).normalized()                              # the moon over the camera's shoulder, high
    tilt = Vector((0.15, -0.1, -0.45)) if CLIP_LIGHT else Vector((0.4, -0.3, -1.2))   # (the clip: lower, from behind
    moon.rotation_euler = (-d + tilt).normalized().to_track_quat("-Z", "Y").to_euler()  # the camera, the sides lit)


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
CORE = firemode.STYLES[STYLE].get("core")                  # (style 10's rod: radius, its tip's x)
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
    """a point on a barrel piece's inside, x along the barrel from SPLIT (its own frame starts at fm_x0)"""
    a = math.radians(ob["fm_dir"])
    x = x + firemode.SPLIT - ob.get("fm_x0", firemode.SPLIT)
    return ob.matrix_world @ Vector((x, r * math.cos(a), r * math.sin(a)))


def covers(ob, x):
    """does this piece run over x (from SPLIT)? (style 9's halves each cover half the barrel)"""
    x0 = ob.get("fm_x0", firemode.SPLIT) - firemode.SPLIT
    return x0 - 0.1 <= x <= x0 + ob.get("fm_len", firemode.X_MID - firemode.SPLIT) + 0.1 if "fm_x0" in ob else True


def effects(level, firing, seed):
    """level 0..1 the charge (arcs, core glow), firing: the shot's rings and flash"""
    clear_fx()
    if level <= 0:
        return
    bpy.context.view_layer.update()                         # (the pieces' and guns' world matrices: as just posed)
    rnd = random.Random(seed)
    ARC_EM.inputs["Strength"].default_value = 2.5 + 2.0 * firing      # (green stays green: brighter goes white)
    RING_EM.inputs["Strength"].default_value = 1.6
    pieces = [o for o in T.pieces() if "fm_barrel" in o and "fm_rod" not in o and "fm_petal" not in o]
    L = (CORE[1] if CORE else firemode.MUZZLE) - firemode.SPLIT          # (the arcs stop at the rod's tip)
    RL = (firemode.STYLES[STYLE].get("rings_to") or firemode.MUZZLE) - firemode.SPLIT   # (and its rings')
    for b in (1, 2, 3):
        mine = [o for o in pieces if o["fm_barrel"] == b]
        shell = any("fm_x0" in o for o in mine)
        for _ in range(int(2 + 4 * level)):                 # from the core to the open pieces, inside the gun
            x = rnd.uniform(0.35, 0.97) * L
            o = rnd.choice([q for q in mine if covers(q, x)] or mine)
            poly(jag(core_point(b, firemode.SPLIT + x + EXT), piece_point(o, x, 0.8 if shell else firemode.BORE - 0.05), 0.08, 5, rnd),
                 0.02, ARC)
        if shell:                                           # and along the core's coil rings
            for _ in range(int(3 + 4 * level)):
                k = rnd.randrange(max(1, int((min(L, RL) - 2.1) / firemode.RING_STEP)))
                x = firemode.SPLIT + 0.9 + firemode.RING_STEP * k
                a = rnd.uniform(0, 2 * math.pi)
                M, yc, fwd = barrel_frame(b)
                q = M @ Vector((x + firemode.RING_STEP, yc + firemode.RING_R * math.cos(a), firemode.RING_R * math.sin(a)))
                poly(jag(core_point(b, x), q, 0.07, 4, rnd), 0.018, ARC)
        M, yc, fwd = barrel_frame(b)
        tip = core_point(b, firemode.MUZZLE + EXT)
        if firing and CORE:                                 # the clip (frames 66-70): wide thin rings round the
            for k in range(3):                              # rod's front half, sparks off its tip
                ring(core_point(b, CORE[1] - 7.0 + 3.0 * k), fwd, 2.6 + 1.7 * k, 0.03)
            tip = core_point(b, CORE[1])
        elif firing:                                        # two rings ahead of the muzzle, a few sparks off it
            for k in range(2):
                ring(tip + fwd * (1.5 + 3.0 * k), fwd, 1.3 + 0.9 * k, 0.035)
            for _ in range(3):
                a = tip + fwd * rnd.uniform(0.3, 2.5)
                poly(jag(a, a + fwd.orthogonal().normalized() * rnd.uniform(1.0, 2.2) + fwd * rnd.uniform(0, 2), 0.3, 5, rnd),
                     0.02, ARC)


# the clip's shots (with `clip`): its frames 46-70 (the barrels opening, then the charge and the shot) and 165-198 (the
# armour opening), each step at the transform's t (fire: the charge, 1 the shot); cameras (place, look at, lens)
CLIP_ELEV = 5.0
CLIP_FRONT = ((0.0, 0.0), (0.16, 0.0), (0.26, 0.0), (0.4, 0.0), (0.6, 0.0), (1.0, 0.0), (1.0, 0.6), (1.0, 1.0))
CLIP_FRONT_CAM = ((56.0, -8.0, 1.0), (20.0, -1.0, 8.0), 26)
if os.environ.get("TANA_CLIP_CAM"):                         # (x y z, look x y z, lens: to frame a shot)
    _c = [float(v) for v in os.environ["TANA_CLIP_CAM"].split(",")]
    CLIP_FRONT_CAM = (tuple(_c[0:3]), tuple(_c[3:6]), _c[6])
CLIP_SIDE = (0.0, 0.03, 0.12, 0.2, 0.45, 1.0)
CLIP_SIDE_CAM = ((-20.0, -24.0, 3.0), (-4.0, 0.0, 4.4), 28)
if os.environ.get("TANA_CLIP_SIDE_CAM"):
    _c = [float(v) for v in os.environ["TANA_CLIP_SIDE_CAM"].split(",")]
    CLIP_SIDE_CAM = (tuple(_c[0:3]), tuple(_c[3:6]), _c[6])


def render(name):
    if ONLY and ONLY not in name:                          # (`only=clip`: just the views so named)
        return
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
firemode.pose(1.0)
effects(0, 0, 3)
aim(C + Vector((-20, -34, 42)), C + Vector((11, 0, 2)), 26)
render("style%d_1_overhead" % STYLE)
firemode.pose(1.0)
effects(0, 0, 5)
aim(C + Vector((62, 30, 26)), C + Vector((17, 0, 6)), 30)
render("style%d_4_front" % STYLE)
T.trun.rotation_euler.y = -math.radians(30.0)
firemode.pose(1.0, fire=1.0)
effects(1.0, 1, 7)
aim(C + Vector((58, 7, 5)), C + Vector((14, 1, 13)), 30)
render("style%d_2_firing" % STYLE)
T.trun.rotation_euler.y = -math.radians(10.0)
firemode.pose(1.0)
effects(0, 0, 11)
aim(C + Vector((5, 36, 6)), C + Vector((1, 0, 3.6)), 28)
render("style%d_3_side" % STYLE)
if firemode.STYLES[STYLE].get("interior"):                 # into the gun house, past the blown-out back left quarter
    aim(C + Vector((-21, 17, 3.2)), C + Vector((-9, 7.0, 2.4)), 22)
    render("style%d_5_inside" % STYLE)
    if firemode.STYLES[STYLE]["armour"] != "clip":          # and the front left (style 10's front walls stay)
        aim(C + Vector((19, 16, 3.0)), C + Vector((6.5, 6.5, 2.3)), 22)
        render("style%d_6_inside_front" % STYLE)
if "clip" in argv[2:]:                                     # the user's clip's two shots, for a side-by-side with it
    night_world()
    for k, (t, fire) in enumerate(CLIP_FRONT):             # low ahead and to starboard, the guns lifted, the sky behind
        T.trun.rotation_euler.y = -math.radians(CLIP_ELEV)
        firemode.pose(t, fire=fire)
        effects(fire, 1 if fire >= 1 else 0, 13 + k)
        aim(C + Vector(CLIP_FRONT_CAM[0]), C + Vector(CLIP_FRONT_CAM[1]), CLIP_FRONT_CAM[2])
        render("style%d_clip_front_%d" % (STYLE, k + 1))
    T.trun.rotation_euler.y = -math.radians(4.0)
    for k, t in enumerate(CLIP_SIDE):                       # the house's starboard side from the deck, its rear on the left
        firemode.pose(t)
        effects(0, 0, 0)
        aim(C + Vector(CLIP_SIDE_CAM[0]), C + Vector(CLIP_SIDE_CAM[1]), CLIP_SIDE_CAM[2])
        render("style%d_clip_side_%d" % (STYLE, k + 1))
if "sequence" in argv[2:]:                                 # the transform in five steps, from ahead and to port
    T.trun.rotation_euler.y = -math.radians(10.0)
    for k, t in enumerate((0.0, 0.3, 0.55, 0.75, 1.0)):
        firemode.pose(t)
        effects(0, 0, 0)
        aim(C + Vector((50, 28, 17)), C + Vector((15, 0, 4)), 30)
        render("style%d_seq_%d" % (STYLE, k + 1))
