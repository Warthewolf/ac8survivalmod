"""film_firemode.py : Blender 3.3, the 16-inch triples' FIRE MODE on film, for the user's approval (firemode.py).

  blender -b build/tanicorn/model/Tanacorn_model.blend -P tools/tanicorn/film_firemode.py -- <out dir> [stills] [clip]

Run on the saved model (model_tanacorn.py builds the fire mode into it; on a model made before it, this builds it in
memory). Turret B (LEV_T16_FWD) trained 17 deg to port, its guns lifted 13 deg, at dusk (TANA_FM_SUN: the sun 1.5 deg up,
over the camera's shoulder; dusk, 1.5 deg), so the glow reads as it does in the user's reference stills:
  stills   firemode_1_stowed and _2_fire_mode (the same view), _3_side, _4_muzzles (low, under the forks), _5_firing
  clip     firemode.mp4 (24 fps): stowed 1 s, the transform 2.5 s, the charge 2 s (arcs between the rails, rings round
           the forks), the shot, the glow dying away, the stow 2.5 s; the camera dollies slowly round the turret
The lightning, the rings and the shot's bolt are the preview's own (objects PREVIEW_*, never exported): in the game
they are AC8's own effects at the guns' SOC_Charge_NN sockets (docs/re/TANICORN.md 7; hard rule 58).
TANA_FM_SAMPLES (16 for stills, 10 for the clip), TANA_FM_RES (stills 1600x900, clip 1280x720), TANA_FM_FRAMES=a,b
(the clip's frames a..b only, for tests).
"""
import bpy, sys, os, math, random, subprocess
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("build/tanicorn/film")
WANT = argv[1:] or ["stills", "clip"]
os.makedirs(OUT, exist_ok=True)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import firemode

sc = bpy.context.scene
sc.frame_set(1)
if "TANA_T16_FWD_Armor_L" in bpy.data.objects:
    firemode.attach()
else:
    import tanakit                                       # (a model made before the new mount: built here, in memory)
    tanakit.WORK = bpy.data.collections.get("TANACORN prototypes") or bpy.data.collections.new("TANACORN prototypes")
    if tanakit.WORK.name not in sc.collection.children:
        sc.collection.children.link(tanakit.WORK)
    tanakit.TEX = os.path.join(OUT, "textures")
    os.makedirs(tanakit.TEX, exist_ok=True)
    coll = bpy.data.collections.new("TANACORN fire mode")
    sc.collection.children.link(coll)
    firemode.build(coll)
for T in firemode.TURRET.values():                       # this script poses everything itself
    for o in T.pieces() + [T.house, T.trun]:
        o.animation_data_clear()
for m in bpy.data.materials:
    if any(m.name.endswith(k) for k in firemode.GLOW) and m.use_nodes:
        m.node_tree.animation_data_clear()
for o in bpy.data.objects:
    if o.name.endswith("_proto"):
        o.hide_render = True

T = firemode.TURRET["FWD"]
T.house.rotation_euler.z = math.radians(17.0)
T.trun.rotation_euler.y = -math.radians(13.0)

sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.use_denoising = True
sc.render.use_persistent_data = True
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = "PNG"
sc.view_layers[0].material_override = None
SKY = next((n for n in sc.world.node_tree.nodes if n.bl_idname == "ShaderNodeTexSky"), None)
BG = next((n for n in sc.world.node_tree.nodes if n.bl_idname == "ShaderNodeBackground"), None)
if SKY:
    SKY.sun_elevation = math.radians(float(os.environ.get("TANA_FM_SUN", "1.5")))
if BG:
    BG.inputs["Strength"].default_value = 0.10
sc.view_settings.exposure = 0.3

cam = bpy.data.objects.new("CAM_firemode", bpy.data.cameras.new("CAM_firemode"))
sc.collection.objects.link(cam)
cam.data.clip_end = 20000.0
sc.camera = cam
C = T.house.matrix_world.translation.copy()


def aim(loc, look, lens):
    loc, look = Vector(loc), Vector(look)
    cam.location = loc
    cam.rotation_euler = (look - loc).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    if SKY:                                              # the low sun over the camera's shoulder
        d = loc - look
        SKY.sun_rotation = math.pi / 2 - (math.atan2(d.y, d.x) + math.radians(40.0))


# ---------------------------------------------------------------------------------------------------- the effects
def emit_mat(name, rgb, strength):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1.0)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m, em


ARC_MAT, ARC_EM = emit_mat("PREVIEW_arc", (0.3, 1.0, 0.3), 12.0)
RING_MAT, RING_EM = emit_mat("PREVIEW_ring", (0.3, 1.0, 0.4), 6.0)
BOLT_MAT, BOLT_EM = emit_mat("PREVIEW_bolt", (1.0, 0.95, 0.55), 25.0)
FX = bpy.data.collections.new("PREVIEW_fx")
sc.collection.children.link(FX)
FLASH = bpy.data.objects.new("PREVIEW_flash", bpy.data.lights.new("PREVIEW_flash", "POINT"))
FX.objects.link(FLASH)
FLASH.data.color = (0.6, 1.0, 0.6)
FLASH.data.shadow_soft_size = 3.0
RAIL_BSDFS = [m.node_tree.nodes["Principled BSDF"] for m in bpy.data.materials
              if m.name.endswith("fm_rail") and m.use_nodes and m.node_tree.nodes.get("Principled BSDF")]


def clear_fx():
    for o in list(FX.objects):
        if o is not FLASH:
            d = o.data
            bpy.data.objects.remove(o)
            if d and d.users == 0:
                (bpy.data.curves if isinstance(d, bpy.types.Curve) else bpy.data.meshes).remove(d)
    FLASH.data.energy = 0.0


CHASE_LEN = firemode.MUZZLE - firemode.CHASE


def rail_point(n, s, k, inward=0.0, z=None):
    """a point on the split face of barrel n's chase half s (its rail channels at z +-0.58), k 0 (its back) .. 1 (the
    muzzle), world; inward: off the face into the gap"""
    r = T.chases[(n, s)]
    sg = 1.0 if s == "L" else -1.0
    zz = random.choice((0.58, -0.58, 0.0)) if z is None else z
    return r.matrix_world @ Vector((CHASE_LEN * k, -sg * inward, zz))


def axis_frame(n):
    """barrel n's fork: the point midway between its halves' muzzles, its forward and two cross axes"""
    a, b = rail_point(n, "L", 1.0, z=0.0), rail_point(n, "R", 1.0, z=0.0)
    fwd = (T.chases[(n, "L")].matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized()
    side = (a - b).normalized()
    up = fwd.cross(side).normalized()
    return (a + b) / 2.0, fwd, side, up


def arc(points, width):
    cu = bpy.data.curves.new("PREVIEW_arc", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = width
    cu.bevel_resolution = 1
    sp = cu.splines.new("POLY")
    sp.points.add(len(points) - 1)
    for p, q in zip(sp.points, points):
        p.co = (*q, 1.0)
    ob = bpy.data.objects.new("PREVIEW_arc", cu)
    ob.data.materials.append(ARC_MAT)
    FX.objects.link(ob)


def jag(a, b, amp, steps, rnd, bulge=0.0, bulge_dir=None):
    d = b - a
    perp1 = d.orthogonal().normalized()
    perp2 = d.cross(perp1).normalized()
    pts = []
    for i in range(steps + 1):
        f = i / steps
        p = a + d * f
        if 0 < i < steps:
            p += perp1 * rnd.uniform(-amp, amp) + perp2 * rnd.uniform(-amp, amp)
        if bulge and bulge_dir is not None:
            p += bulge_dir * bulge * math.sin(math.pi * f)
        pts.append(p)
    return pts


def ring(centre, fwd, radius, thick):
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=thick, major_segments=40, minor_segments=6,
                                     location=centre)
    ob = bpy.context.active_object
    ob.name = "PREVIEW_ring"
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = fwd.to_track_quat("Z", "Y")
    ob.data.materials.append(RING_MAT)
    for c in ob.users_collection:
        c.objects.unlink(ob)
    FX.objects.link(ob)


def effects(charge, shot, after, seed, t=1.0):
    """charge 0..1 (arcs and rings building), shot 0..1 (the bolt and the flash), after 0..1 (fading); t the pose"""
    clear_fx()
    rnd = random.Random(seed)
    live = max(charge, 0.0) * (1.0 - after)
    _, _, lo, hi, st = firemode.GLOW["fm_rail"]
    base = lo + (hi - lo) * firemode.stage(t, st)
    for b in RAIL_BSDFS:
        b.inputs["Emission Strength"].default_value = base * (1.0 + 1.5 * live + 3.0 * shot)
        b.inputs["Emission"].default_value = (0.25 + 0.75 * shot, 1.0, 0.45 + 0.4 * shot, 1.0)
    ARC_EM.inputs["Strength"].default_value = 10.0 + 20.0 * shot
    if live <= 0.0 and shot <= 0.0:
        return
    for n in (1, 2, 3):
        c, fwd, side, up = axis_frame(n)
        # arcs leaping the gap between the rails, more as the charge builds, some looping out over the fork
        for i in range(int(2 + 7 * live + 4 * shot)):
            k = rnd.uniform(0.1, 1.0)
            z = rnd.choice((0.58, -0.58, 0.0))
            a, b = rail_point(n, "L", k, 0.01, z), rail_point(n, "R", min(1.0, k + rnd.uniform(-0.05, 0.05)), 0.01, z)
            loop = rnd.random() < 0.3
            arc(jag(a, b, 0.22, 7, rnd, rnd.uniform(0.6, 1.6) if loop else 0.0, up * rnd.choice((-1, 1))), 0.03)
        for i in range(int(3 * live)):                           # a few crawling forward off the prongs' tips
            a = rail_point(n, rnd.choice("LR"), 1.0, 0.01)
            b = c + fwd * rnd.uniform(1.5, 4.0) + side * rnd.uniform(-1.2, 1.2) + up * rnd.uniform(-1.2, 1.2)
            arc(jag(a, b, 0.35, 6, rnd), 0.025)
        # rings round the fork, ahead of the muzzle: tight while charging, thrown out and wide when it fires
        grow = live + after * 2.5
        for j in range(3):
            if live > 0.15 * j or after > 0:
                ring(c + fwd * (1.0 + 2.2 * j + 6.0 * after), fwd, 1.2 + 0.5 * j + grow * 0.8, 0.05 + 0.03 * (1.0 - after))
        if shot > 0:
            mid = c + fwd * 160.0
            bpy.ops.mesh.primitive_cylinder_add(radius=0.3 * shot, depth=320.0, vertices=16, location=mid)
            bolt = bpy.context.active_object
            bolt.name = "PREVIEW_bolt"
            bolt.rotation_mode = "QUATERNION"
            bolt.rotation_quaternion = fwd.to_track_quat("Z", "Y")
            bolt.data.materials.append(BOLT_MAT)
            for cc in bolt.users_collection:
                cc.objects.unlink(bolt)
            FX.objects.link(bolt)
    RING_EM.inputs["Strength"].default_value = 6.0 * (1.0 - after) + 10.0 * shot
    c, fwd, _, _ = axis_frame(2)
    FLASH.location = c + fwd * 3.0
    FLASH.data.energy = 6.0e5 * shot + 6.0e4 * live


def render(path, samples, res):
    sc.cycles.samples = samples
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ---------------------------------------------------------------------------------------------------- stills
VIEW = (C + Vector((60, 44, 16)), C + Vector((14, 4, 5)), 30)
if "stills" in WANT:
    res = [int(v) for v in os.environ.get("TANA_FM_RES", "1600x900").split("x")]
    smp = int(os.environ.get("TANA_FM_SAMPLES", "16"))
    shots = [("1_stowed", VIEW, 0.0, (0, 0, 0)), ("2_fire_mode", VIEW, 1.0, (0, 0, 0)),
             ("3_side", (C + Vector((6, 58, 9)), C + Vector((9, 0, 4)), 30), 1.0, (0, 0, 0)),
             ("4_muzzles", (C + Vector((50, 14, 3)), C + Vector((18, 4, 7)), 26), 1.0, (0.7, 0, 0)),
             ("5_firing", (C + Vector((70, 38, 10)), C + Vector((26, 8, 9)), 28), 1.0, (1.0, 1.0, 0.0))]
    for tag, (loc, look, lens), t, fx in shots:
        firemode.pose(t)
        aim(loc, look, lens)
        effects(*fx, seed=7, t=t)
        render(os.path.join(OUT, "firemode_%s.png" % tag), smp, res)
        print("firemode film: still", tag)
    effects(0, 0, 0, 0)

# ---------------------------------------------------------------------------------------------------- clip
if "clip" in WANT:
    FPS = 24
    D = int(firemode.DEPLOY_S * FPS)                      # 60 frames: the transform at the game's speed
    P = {"deploy": 24, "charge": 24 + D, "fire": 24 + D + 48, "fade": 24 + D + 52, "stow": 24 + D + 96}
    END = P["stow"] + D + 12
    res = [int(v) for v in os.environ.get("TANA_FM_RES", "1280x720").split("x")]
    smp = int(os.environ.get("TANA_FM_SAMPLES", "10"))
    a, b = [int(v) for v in os.environ.get("TANA_FM_FRAMES", "0,%d" % END).split(",")]
    seq = os.path.join(OUT, "firemode_seq")
    os.makedirs(seq, exist_ok=True)
    start = (C + Vector((64, 50, 18)), C + Vector((14, 4, 5)))     # the turret three-quarters from ahead, round to
    stop = (C + Vector((52, 15, 4)), C + Vector((18, 4, 7)))        # low ahead of it, under the opening forks
    for f in range(a, min(b, END) + 1):
        u = f / END
        u = u * u * (3 - 2 * u)
        aim(start[0].lerp(stop[0], u), start[1].lerp(stop[1], u), 30)
        if f < P["stow"]:
            t = firemode.smooth(f, P["deploy"], P["charge"]) if f < P["charge"] else 1.0
        else:
            t = 1.0 - min(1.0, (f - P["stow"]) / float(D))
        firemode.pose(t)
        charge = firemode.smooth(f, P["charge"], P["fire"]) if P["charge"] <= f < P["fire"] + 4 else 0.0
        shot = max(0.0, 1.0 - abs(f - P["fire"]) / 3.0) if abs(f - P["fire"]) < 3 else 0.0
        after = min(1.0, (f - P["fire"]) / 30.0) if f > P["fire"] else 0.0
        if f >= P["fire"] + 30:
            charge = after = 0.0
        effects(charge, shot, after, seed=f, t=t)
        render(os.path.join(seq, "%04d.png" % f), smp, res)
        print("firemode film: frame %d / %d" % (f, END))
    if a == 0 and b >= END:
        clip = os.path.join(OUT, "firemode.mp4")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(seq, "%04d.png"),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", clip], check=True)
        print("firemode film: clip", clip)
