"""breach_tanacorn.py : Blender 3.3, THE TANACORN surfacing bow-first in a running swell and then fighting, on film (the
user, 2026-11-10: "Make another surfacing animation but refine the water particles so they actually look great,
include sea swell and move the camera so it's firstly viewing the bow of the ship rising up out of the water from the
front. When it first comes out of the water it doesn't have to be a massive water explosion either. Then do a pass
over the ship with its railguns and other guns firing including the laser turrets. Have the clip last for 20 seconds").

  blender -b <model dir>/Tanacorn_model.blend -P tools/tanicorn/breach_tanacorn.py -- <film dir>

Run on the file model_tanacorn.py saves. 20 s at 24 fps:
  0 - 2.2 s   a running swell; the sea humps up over her bow
  2.2 - 6.2   her bow breaks the surface and comes up 35 deg nose-up until it stands 120 m over the sea (the rise the
              user chose for the first surfacing shot), the camera low on the water dead ahead of her; she comes out
              smoothly, not with a burst: the sea pours off her bow and flanks in streams, a ring of white water and
              thin mist where she pierces the surface, foam spreading
  6.2 - 9.6   she comes down gently and levels, the rest of her surfacing; white water along her sides
  8.6 - 11.4  the camera climbs off her bow and swings out to port as she deploys (railgun hatches and lifts, the bow's
              railcannon raised, turrets trained out to starboard)
  11.4 - 20   the camera passes aft along her port side 60 m up, looking across her deck to starboard, where the
              threats are: the railcannon fires, the 16-inch rail turrets fire salvos (blue-white flashes, rail shells
              streaking to the horizon), the starboard 5-inch twins fire flak at aircraft, the laser turrets burn down
              incoming sea-skimming missiles, the CIWS hose tracers at the ones that get closer, the sub-railguns fire,
              and the aft deck VLS launches four missiles
The sea is Blender's ocean simulation (a Phillips-spectrum swell with whitecap foam) on a grid dense round her and
stretched to the horizon; the water's colour, crests, foam (whitecaps, her waterline, where she broke through) are in
its material. Spray is particle systems drawn as small drops with motion blur (so they streak), and soft mist puffs.
Cycles on the CPU: TANA_BREACH_RES (1280x720), TANA_BREACH_SAMPLES (16), TANA_BREACH_STEP (1), TANA_BREACH_FRAMES
(a comma list: test stills), TANA_BREACH_PARTICLES (1.0: a share of the particle counts), TANA_BREACH_FX (1: 0 leaves
the weapons out), TANA_BREACH_SPRAY (1). Writes <film dir>/tanacorn_breach.mp4 (ffmpeg).
"""
import bpy, bmesh, sys, os, math, shutil, subprocess, random
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("build/tanicorn/film")
os.makedirs(OUT, exist_ok=True)
ENV = os.environ.get
RES = [int(v) for v in ENV("TANA_BREACH_RES", "1280x720").split("x")]
SAMPLES = int(ENV("TANA_BREACH_SAMPLES", "16"))
STEP = int(ENV("TANA_BREACH_STEP", "1"))
ONLY = [int(v) for v in ENV("TANA_BREACH_FRAMES", "").split(",") if v]
SCALE = float(ENV("TANA_BREACH_PARTICLES", "1.0"))
FX = ENV("TANA_BREACH_FX", "1") != "0"
SPRAY = ENV("TANA_BREACH_SPRAY", "1") != "0"
random.seed(11)

FPS, DUR = 24, 20.0
N = int(FPS * DUR)


def F(t):                                                     # the frame at t seconds
    return 1.0 + t * FPS


def fi(t):
    return int(round(F(t)))


def clamp(v, a=0.0, b=1.0):
    return max(a, min(b, v))


def ease(s):
    s = clamp(s)
    return s * s * (3.0 - 2.0 * s)


def ease5(s):
    s = clamp(s)
    return s * s * s * (s * (6.0 * s - 15.0) + 10.0)


# ---------------------------------------------------------------------------------------------------- the ship
T_UP0, T_UP1, T_DOWN = 0.8, 6.2, 9.6
PITCH = math.radians(35.0)
BOW, TOP = 325.0, 120.0
D0 = -(BOW + 25.0)                                            # her middle along her axis from the surface, at the start
D1 = TOP / math.sin(PITCH) - BOW                              # ... and at the top of the rise (-116 m)
BREACH = Vector((-D1, 0.0, 0.0))                              # where her axis stands in the sea (she ends at the origin)
AXIS = Vector((math.cos(PITCH), 0.0, math.sin(PITCH)))


def rise(s):
    return D0 + (D1 - D0) * ease5(s)


T_BREAK = T_UP0 + (T_UP1 - T_UP0) * next(k / 400.0 for k in range(401) if rise(k / 400.0) >= -BOW)   # her stem breaks out

sc = bpy.context.scene
sc.render.fps = FPS
sc.frame_start, sc.frame_end = 1, N
sc.frame_set(1)
D = bpy.data.objects
SHIP = D["LEV_ship"]

# the design's deploy sequence (30 fps keys): every channel's stowed (frame 1) and deployed (frame 200) values, then all
# its keys off: the shot keys its own
DESIGN = {}
for o in [SHIP] + list(SHIP.children_recursive):
    ad = o.animation_data
    if ad and ad.action:
        DESIGN[o.name] = {(fc.data_path, fc.array_index): (fc.evaluate(1.0), fc.evaluate(200.0)) for fc in ad.action.fcurves}
for o in [SHIP] + list(SHIP.children_recursive):
    if o.animation_data:
        o.animation_data_clear()
for o in D:
    if o.name.endswith("_proto") or o.name == "SEA":
        o.hide_render = True


def pose(t):
    """her middle and nose-up angle at t"""
    if t <= T_UP1:
        return BREACH + AXIS * rise((t - T_UP0) / (T_UP1 - T_UP0)), PITCH
    if t <= T_DOWN:                                           # she comes down gently about where she stands in the sea
        th = PITCH * (1.0 - ease((t - T_UP1) / (T_DOWN - T_UP1)))
        return BREACH + Vector((math.cos(th), 0.0, math.sin(th))) * D1, th
    u = t - T_DOWN                                            # a small heave as she settles, then the swell's slow roll
    k = math.exp(-0.8 * u)
    z = -1.4 * k * math.sin(1.7 * u) + (1.0 - k) * 0.3 * math.sin(0.8 * u)
    th = -math.radians(0.6) * k * math.sin(1.5 * u) + (1.0 - k) * math.radians(0.1) * math.sin(0.6 * u)
    return Vector((0.0, 0.0, z)), th


def keyall(o, path, frames):
    for f in frames:
        o.keyframe_insert(path, frame=f)


def linear(o):
    ad = o.animation_data
    if ad and ad.action:
        for fc in ad.action.fcurves:
            for k in fc.keyframe_points:
                k.interpolation = "LINEAR"


# ---------------------------------------------------------------------------------------------------- materials
def mat(name, build):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    build(nt, nt.nodes.new("ShaderNodeOutputMaterial"))
    return m


def N_(nt, kind, **inputs):
    n = nt.nodes.new(kind)
    for k, v in inputs.items():
        if k.startswith("_"):
            setattr(n, k[1:], v)
        else:
            n.inputs[k].default_value = v
    return n


def L_(nt, a, b):
    nt.links.new(a, b)


def math_(nt, op, a=None, b=None, clamp_=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation, n.use_clamp = op, clamp_
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            L_(nt, v, n.inputs[i])
    return n.outputs[0]


def soft(nt, power):
    """1 where a surface faces the camera, falling to 0 at its rim (a puff or a glow, not a ball)"""
    lw = N_(nt, "ShaderNodeLayerWeight", Blend=0.5)
    return math_(nt, "POWER", math_(nt, "SUBTRACT", 1.0, lw.outputs["Facing"]), power)


def glow_mat(name, strength, power=1.2):
    """emission in the object's colour (its keyed colour is its brightness: black is off), soft at the rim"""
    def build(nt, out):
        oi = nt.nodes.new("ShaderNodeObjectInfo")
        em = N_(nt, "ShaderNodeEmission", Strength=strength)
        L_(nt, oi.outputs["Color"], em.inputs["Color"])
        bw = nt.nodes.new("ShaderNodeRGBToBW")
        L_(nt, oi.outputs["Color"], bw.inputs[0])
        tr, mix = nt.nodes.new("ShaderNodeBsdfTransparent"), nt.nodes.new("ShaderNodeMixShader")
        L_(nt, math_(nt, "MULTIPLY", soft(nt, power), math_(nt, "MULTIPLY", bw.outputs[0], 8.0, True)), mix.inputs[0])
        L_(nt, tr.outputs[0], mix.inputs[1])
        L_(nt, em.outputs[0], mix.inputs[2])
        L_(nt, mix.outputs[0], out.inputs["Surface"])
    return mat(name, build)


def puff_mat(name, color, alpha, glow=0.0, power=1.6):
    """a soft puff (smoke, mist): its keyed colour's red is its opacity"""
    def build(nt, out):
        oi = nt.nodes.new("ShaderNodeObjectInfo")
        sep = nt.nodes.new("ShaderNodeSeparateRGB")
        L_(nt, oi.outputs["Color"], sep.inputs[0])
        df = N_(nt, "ShaderNodeBsdfDiffuse", Color=(*color, 1))
        tl = N_(nt, "ShaderNodeBsdfTranslucent", Color=(*color, 1))
        a = N_(nt, "ShaderNodeMixShader", Fac=0.45)
        L_(nt, df.outputs[0], a.inputs[1])
        L_(nt, tl.outputs[0], a.inputs[2])
        top = a.outputs[0]
        if glow:
            em, add = N_(nt, "ShaderNodeEmission", Color=(1.0, 0.85, 0.7, 1), Strength=glow), nt.nodes.new("ShaderNodeAddShader")
            L_(nt, a.outputs[0], add.inputs[0])
            L_(nt, em.outputs[0], add.inputs[1])
            top = add.outputs[0]
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nz = N_(nt, "ShaderNodeTexNoise", _noise_dimensions="4D", Scale=1.6, Detail=6.0, Roughness=0.6)
        L_(nt, tc.outputs["Object"], nz.inputs["Vector"])
        L_(nt, math_(nt, "MULTIPLY", oi.outputs["Random"], 40.0), nz.inputs["W"])
        torn = N_(nt, "ShaderNodeMapRange", **{"From Min": 0.42, "From Max": 0.72})
        L_(nt, nz.outputs["Fac"], torn.inputs["Value"])
        tr, mix = nt.nodes.new("ShaderNodeBsdfTransparent"), nt.nodes.new("ShaderNodeMixShader")
        L_(nt, math_(nt, "MULTIPLY", math_(nt, "MULTIPLY", math_(nt, "MULTIPLY", soft(nt, power), torn.outputs[0]),
                                            sep.outputs["R"]), alpha), mix.inputs[0])
        L_(nt, tr.outputs[0], mix.inputs[1])
        L_(nt, top, mix.inputs[2])
        L_(nt, mix.outputs[0], out.inputs["Surface"])
    return mat(name, build)


def drop_mat(name):
    """a spray drop: white water, a little glossy, lit by the sun (small and motion-blurred, so it streaks)"""
    def build(nt, out):
        p = N_(nt, "ShaderNodeBsdfPrincipled", **{"Base Color": (0.9, 0.93, 0.95, 1), "Roughness": 0.2,
                                                  "Specular": 0.7, "Emission": (1.0, 0.95, 0.88, 1),
                                                  "Emission Strength": 0.08})
        tr, mix = nt.nodes.new("ShaderNodeBsdfTransparent"), nt.nodes.new("ShaderNodeMixShader")
        L_(nt, math_(nt, "MULTIPLY", soft(nt, 0.8), 0.9), mix.inputs[0])
        L_(nt, tr.outputs[0], mix.inputs[1])
        L_(nt, p.outputs[0], mix.inputs[2])
        L_(nt, mix.outputs[0], out.inputs["Surface"])
    return mat(name, build)


FXC = bpy.data.collections.new("BREACH")
sc.collection.children.link(FXC)
MESHES = {}


def shape(kind):
    if kind in MESHES:
        return MESHES[kind]
    me = bpy.data.meshes.new("BREACH_" + kind)
    bm = bmesh.new()
    if kind.startswith("ico"):
        bmesh.ops.create_icosphere(bm, subdivisions=int(kind[3:]), radius=1.0)
    elif kind == "strand":                                    # a drop drawn out upright: 0.34 wide, 2.4 tall
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
        bmesh.ops.scale(bm, vec=(0.34, 0.34, 2.4), verts=bm.verts)
    elif kind == "cyl":                                       # unit length along +Z from 0 to 1, radius 1
        bmesh.ops.create_cone(bm, cap_ends=False, segments=10, radius1=1.0, radius2=1.0, depth=1.0)
        bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, 0.5))
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    MESHES[kind] = me
    return me


def slot_obj(o, m):
    if not o.data.materials:
        o.data.materials.append(None)
    o.material_slots[0].link = "OBJECT"
    o.material_slots[0].material = m


M_DROP = drop_mat("BREACH_drop")
M_MIST = puff_mat("BREACH_mist", (0.93, 0.95, 0.97), 0.18, glow=0.0, power=2.4)
M_HAZE = puff_mat("BREACH_haze", (0.93, 0.95, 0.97), 0.12, power=2.4)


def pattern(name, kind, m, col=(1, 1, 1, 1)):
    o = bpy.data.objects.new(name, shape(kind))
    FXC.objects.link(o)
    slot_obj(o, m)
    o.location, o.color = (0, 0, -900.0), col
    return o


DROP = pattern("BREACH_drop_p", "strand", M_DROP)
MIST = pattern("BREACH_mist_p", "ico2", M_MIST)
HAZE = pattern("BREACH_haze_p", "ico2", M_HAZE)

# ---------------------------------------------------------------------------------------------------- her pose, keyed
SHIP.rotation_mode = "XYZ"
for f in range(1, N + 1):
    loc, th = pose((f - 1) / FPS)
    SHIP.location = loc
    SHIP.rotation_euler = (0.0, -th, 0.0)
    SHIP.keyframe_insert("location", frame=f)
    SHIP.keyframe_insert("rotation_euler", frame=f)


def at_rest():
    """her settled pose (the origin, level) while the mounts are measured"""
    SHIP.animation_data.action, keep = None, SHIP.animation_data.action
    SHIP.location, SHIP.rotation_euler = (0, 0, 0), (0, 0, 0)
    bpy.context.view_layer.update()
    return keep


# ---------------------------------------------------------------------------------------------------- the camera
T_SWING0, T_SWING1 = 8.6, 11.4
PASS_X0, PASS_V = 330.0, 64.0


def cam_x(t):
    return PASS_X0 - PASS_V * max(0.0, t - T_SWING1)


def shot(t):
    """the camera: where it is, what it looks at, its lens"""
    bob = Vector((0.0, 0.0, 0.9 * math.sin(2 * math.pi * t / 5.3) + 0.3 * math.sin(2 * math.pi * t / 2.1)))
    e = ease((t - T_BREAK + 0.6) / (T_UP1 - T_BREAK + 0.4))   # (it tilts up after her bow)
    p0 = Vector((BREACH.x + 345.0 + 22.0 * ease(t / T_SWING0), 20.0, 9.0)) + bob
    l0 = Vector((BREACH.x + 70.0 + 10.0 * e, 0.0, 10.0 + 58.0 * e))
    if t < T_UP1:
        return p0, l0, 22.0
    d = ease((t - T_UP1) / (T_DOWN - T_UP1))                  # (and down again after it, to her forebody)
    l1 = l0.lerp(Vector((250.0, 0.0, 14.0)), d)
    if t < T_SWING0:
        return p0, l1, 22.0
    s = ease((t - T_SWING0) / (T_SWING1 - T_SWING0))
    pp = Vector((cam_x(t), 96.0, 62.0))
    lp = Vector((cam_x(t) - 95.0, -62.0, 11.0))
    mid = Vector((440.0, 80.0, 42.0))                         # (a curve: out to port and up, clear of her bow)
    p = (p0 * (1 - s) + mid * s) * (1 - s) + (mid * (1 - s) + pp * s) * s
    return p, l1.lerp(lp, s), 22.0 + 2.0 * s


cam = bpy.data.objects.new("CAM_breach", bpy.data.cameras.new("CAM_breach"))
FXC.objects.link(cam)
cam.data.clip_start, cam.data.clip_end = 0.5, 40000.0
sc.camera = cam
for f in range(1, N + 1):
    loc, look, lens = shot((f - 1) / FPS)
    cam.location = loc
    cam.rotation_euler = (look - loc).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    cam.keyframe_insert("location", frame=f)
    cam.keyframe_insert("rotation_euler", frame=f)
    cam.data.keyframe_insert("lens", frame=f)

# ---------------------------------------------------------------------------------------------------- the weapons
LIGHTS = []


def light(name, color, size=4.0):
    l = bpy.data.objects.new(name, bpy.data.lights.new(name, "POINT"))
    l.data.color, l.data.shadow_soft_size, l.data.energy = color, size, 0.0
    FXC.objects.link(l)
    LIGHTS.append(l)
    return l


def world_verts(o):
    me = o.data
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    M = np.array(o.matrix_world)
    return co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]


def find_muzzles(guns, pivot, n_max=3):
    """a gun's barrels: its long axis (pointing away from the mount's pivot) and the mouths along it"""
    P = np.concatenate([world_verts(g) for g in guns])
    c = P.mean(0)
    _, _, vt = np.linalg.svd(P - c, full_matrices=False)
    a = vt[0]
    pr = (P - c) @ a
    piv = np.array(pivot)
    hd = lambda q: math.hypot(q[0] - piv[0], q[1] - piv[1])
    if hd(P[pr < pr.min() + 0.5].mean(0)) > hd(P[pr > pr.max() - 0.5].mean(0)):
        a, pr = -a, -pr
    front = P[pr > pr.max() - 0.7]
    side = np.cross(a, [0.0, 0.0, 1.0])
    side = side / (np.linalg.norm(side) or 1.0)
    s = front @ side
    o = np.argsort(s)
    s, front = s[o], front[o]
    gaps = np.diff(s)
    wide = max(0.45, 0.3 * float(gaps.max())) if len(gaps) else 0.45
    cuts = [0] + [i + 1 for i, g in enumerate(gaps) if g > wide] + [len(s)]
    tips = []
    for x, y in zip(cuts, cuts[1:]):
        q = front[x:y]
        tips.append(q.mean(0) + a * ((q @ a).max() - (q @ a).mean() + 0.3))
    if len(tips) > n_max:                                     # (a rim's gaps: one mouth, its middle)
        tips = [sum(tips) / len(tips)]
    return Vector(a), [Vector(t) for t in tips]


class Mount:
    def __init__(self, name, yaw, pitch, guns, n_max=3, socket=None):
        self.name = name
        self.yaw, self.pitch = D[yaw], D[pitch]
        g = [D[x] for x in guns]
        piv = self.yaw.matrix_world.translation
        if socket:
            s = D[socket].matrix_world.translation
            self.f, tips = (s - self.pitch.matrix_world.translation).normalized(), [s.copy()]
        else:
            self.f, tips = find_muzzles(g, piv, n_max)
        self.P = self.pitch.matrix_world.translation.copy()
        self.y0, self.p0 = self.yaw.rotation_euler[2], self.pitch.rotation_euler[1]
        self.side = -1 if piv.y < -2.0 else (1 if piv.y > 2.0 else 0)
        self.tips = []
        for k, t in enumerate(tips):                          # an empty at each mouth, riding with the guns, +Z out
            e = bpy.data.objects.new("BREACH_mz_%s_%d" % (name, k), None)
            FXC.objects.link(e)
            e.parent = g[0] if not socket else self.pitch
            e.matrix_parent_inverse = e.parent.matrix_world.inverted()
            e.matrix_world = Matrix.Translation(t) @ self.f.to_track_quat("Z", "X").to_matrix().to_4x4()
            self.tips.append(e)
        # which way a pitch turn lifts the guns
        bpy.context.view_layer.update()
        e0 = self.f_now().z
        self.pitch.rotation_euler[1] = self.p0 - 0.1
        bpy.context.view_layer.update()
        self.sgn = -1.0 if self.f_now().z > e0 else 1.0
        self.pitch.rotation_euler[1] = self.p0
        bpy.context.view_layer.update()
        self.keys = [(0.0, self.y0, self.p0)]

    def f_now(self):
        return self.tips[0].matrix_world.to_3x3() @ Vector((0, 0, 1))

    def solve(self, T):
        d = Vector(T) - self.P
        h0, h1 = math.atan2(self.f.y, self.f.x), math.atan2(d.y, d.x)
        dh = (h1 - h0 + math.pi) % (2 * math.pi) - math.pi
        e0 = math.asin(clamp(self.f.z, -1, 1))
        e1 = clamp(math.atan2(d.z, math.hypot(d.x, d.y)), math.radians(-4.0), math.radians(65.0))
        return self.y0 + dh, self.p0 + self.sgn * (e1 - e0)

    def aim(self, t, T, slew=1.0):
        y, p = self.solve(T)
        ty, py = self.keys[-1][1], self.keys[-1][2]
        self.keys.append((max(t - slew, self.keys[-1][0] + 0.05), ty, py))
        self.keys.append((t, y, p))

    def commit(self):
        for t, y, p in self.keys:
            self.yaw.rotation_euler[2], self.pitch.rotation_euler[1] = y, p
            self.yaw.keyframe_insert("rotation_euler", index=2, frame=F(t))
            self.pitch.keyframe_insert("rotation_euler", index=1, frame=F(t))
        self.yaw.rotation_euler[2], self.pitch.rotation_euler[1] = self.keys[0][1], self.keys[0][2]


def deploy(name, t0, t1):
    """a part of her deploy sequence, from stowed at t0 to the design's deployed pose at t1"""
    o = D[name]
    for (path, idx), (a, b) in DESIGN.get(name, {}).items():
        for t, v in ((t0, a), (t1, b)):
            getattr(o, path)[idx] = v
            o.keyframe_insert(path, index=idx, frame=F(t))
        getattr(o, path)[idx] = a


T_DEP0, T_DEP1 = 8.8, 11.0
M_FLASH = glow_mat("BREACH_flash", 9.0, power=0.9)
M_BEAM = glow_mat("BREACH_beam", 30.0, power=0.7)
M_SHELL = glow_mat("BREACH_shell", 40.0, power=0.5)
M_SMOKE = puff_mat("BREACH_smoke", (0.5, 0.5, 0.51), 0.7, power=1.6)
M_DARK = puff_mat("BREACH_flak", (0.07, 0.07, 0.075), 0.9, power=1.3)
M_WHITE = puff_mat("BREACH_white", (0.88, 0.88, 0.88), 0.55, power=1.7)
M_TRAIL = puff_mat("BREACH_trail", (0.85, 0.86, 0.88), 0.16, power=1.8)
BODY = mat("BREACH_body", lambda nt, out: L_(nt, N_(nt, "ShaderNodeBsdfPrincipled", **{"Base Color": (0.3, 0.31, 0.32, 1),
                                                                                       "Roughness": 0.5}).outputs[0],
                                               out.inputs["Surface"]))
TRAIL = pattern("BREACH_trail_p", "ico2", M_TRAIL)
BLUE, ORANGE, RED, GOLD = (0.55, 0.8, 1.0), (1.0, 0.62, 0.25), (1.0, 0.22, 0.12), (1.0, 0.8, 0.45)


def pulse(o, frames_vals, path="color"):
    """key an object's colour (its brightness) or scale over (frame, value) pairs"""
    for f, v in frames_vals:
        if path == "color":
            o.color = (*v, 1.0) if len(v) == 3 else v
        else:
            o.scale = v
        o.keyframe_insert(path, frame=f)


def blink(o, t, col, rise=1, hold=1, fall=4):
    f = F(t)
    pulse(o, [(f - rise, (0, 0, 0)), (f, col), (f + hold, col), (f + hold + fall, (0, 0, 0))])


def flash_at(tip, t, size, col, length=2.4):
    o = bpy.data.objects.new("BREACH_flash_%s_%d" % (tip.name[10:], fi(t)), shape("ico2"))
    FXC.objects.link(o)
    slot_obj(o, M_FLASH)
    o.parent = tip
    o.location = (0, 0, size * length * 0.5)
    o.scale = (size, size, size * length)
    o.color = (0, 0, 0, 1)
    f = F(t)
    pulse(o, [(f - 1, (0, 0, 0)), (f, col), (f + 1, tuple(c * 0.5 for c in col)), (f + 3, (0, 0, 0))])
    pulse(o, [(f, (size, size, size * length)), (f + 3, (size * 1.5, size * 1.5, size * length * 1.3))], "scale")
    return o


def puff(name, m, loc, t, r0, r1, life, drift=(0, 0, 0), alpha=1.0, grow=0.35):
    o = bpy.data.objects.new(name, shape("ico2"))
    FXC.objects.link(o)
    slot_obj(o, m)
    f, f1 = F(t), F(t + life)
    o.location = loc
    o.keyframe_insert("location", frame=f)
    o.location = Vector(loc) + Vector(drift)
    o.keyframe_insert("location", frame=f1)
    for ff, s in ((f - 1, 0.0), (f, r0), (F(t + life * grow), r1 * 0.8), (f1, r1)):
        o.scale = (s, s, s * 0.8)
        o.keyframe_insert("scale", frame=ff)
    for ff, a in ((f - 1, 0.0), (f, alpha), (F(t + life * 0.4), alpha * 0.6), (f1, 0.0)):
        o.color = (a, a, a, 1)
        o.keyframe_insert("color", frame=ff)
    o.location = (0, 0, -900)
    return o


def beam(name, p0, p1, t_on, t_off, col, radius, fade=0.25):
    """a straight glowing line from p0 to p1, on from t_on, fading out after t_off"""
    o = bpy.data.objects.new(name, shape("cyl"))
    FXC.objects.link(o)
    slot_obj(o, M_BEAM)
    d = Vector(p1) - Vector(p0)
    o.matrix_world = Matrix.Translation(p0) @ d.to_track_quat("Z", "X").to_matrix().to_4x4() @ \
        Matrix.Diagonal((radius, radius, d.length, 1.0))
    o.color = (0, 0, 0, 1)
    pulse(o, [(F(t_on) - 1, (0, 0, 0)), (F(t_on), col), (F(t_off), tuple(c * 0.8 for c in col)), (F(t_off + fade), (0, 0, 0))])
    return o


def tracking_beam(name, src, target_at, t0, t1, col, radius):
    """a beam keyed frame by frame from a muzzle to a moving point (a laser holding on its missile)"""
    o = bpy.data.objects.new(name, shape("cyl"))
    FXC.objects.link(o)
    slot_obj(o, M_BEAM)
    o.rotation_mode = "QUATERNION"
    for f in range(fi(t0) - 1, fi(t1) + 2):
        sc.frame_set(f)
        p0 = src.matrix_world.translation.copy()
        d = target_at((f - 1) / FPS) - p0
        o.location = p0
        o.rotation_quaternion = d.to_track_quat("Z", "X")
        o.scale = (radius, radius, d.length)
        for path in ("location", "rotation_quaternion", "scale"):
            o.keyframe_insert(path, frame=f)
    on = (*col,)
    pulse(o, [(F(t0) - 1, (0, 0, 0)), (F(t0), on), (F(t0) + 2, tuple(c * 0.55 for c in on)), (F(t0) + 3, on),
              (F(t1), on), (F(t1) + 2, (0, 0, 0))])
    return o


def projectile(name, p0, d, t0, speed, life, col, r):
    o = bpy.data.objects.new(name, shape("ico1"))
    FXC.objects.link(o)
    slot_obj(o, M_SHELL)
    o.color = (*col, 1)
    o.location = p0
    o.keyframe_insert("location", frame=F(t0))
    o.location = Vector(p0) + Vector(d).normalized() * speed * life
    o.keyframe_insert("location", frame=F(t0 + life))
    for f, s in ((F(t0) - 0.1, 0.0), (F(t0), r), (F(t0 + life), r), (F(t0 + life) + 0.1, 0.0)):
        o.scale = (s, s, s)
        o.keyframe_insert("scale", frame=f)
    linear(o)
    return o


def burst(name, at, t, size=14.0, col=ORANGE, dark=True):
    o = bpy.data.objects.new(name, shape("ico2"))
    FXC.objects.link(o)
    slot_obj(o, M_FLASH)
    o.location = at
    o.color = (0, 0, 0, 1)
    f = F(t)
    pulse(o, [(f - 1, (0, 0, 0)), (f, col), (f + 2, tuple(c * 0.6 for c in col)), (f + 6, (0, 0, 0))])
    pulse(o, [(f, (size * 0.5,) * 3), (f + 6, (size * 1.4,) * 3)], "scale")
    if dark:
        puff(name + "_smoke", M_DARK, at, t + 0.05, size * 0.5, size * 1.6, 3.5, drift=(0, 0, 6.0), alpha=0.9)


def tips_at(m, t):
    sc.frame_set(fi(t))
    return [(e.matrix_world.translation.copy(), (e.matrix_world.to_3x3() @ Vector((0, 0, 1))).normalized()) for e in m.tips]


TRAILS = []                                                   # (missile, from, to, puffs a second, size, life)
if FX:
    keep = at_rest()
    T16 = [Mount("T16_%s" % s, "LEV_T16_%s.001" % s, "LEV_G16_%s_trunnion" % s, ["LEV_G16_%s.001" % s], 3) for s in ("FWD", "AFT")]
    T5 = [Mount("T5_%d" % k, "LEV_IOWA_T5_%d.001" % k, "LEV_IOWA_G5_%d_trunnion" % k, ["LEV_IOWA_G5_%d.001" % k], 2) for k in range(1, 7)]
    CIWS = [Mount("CIWS_%d" % k, "LEV_IOWA_CIWS_%d.001" % k, "LEV_IOWA_CG_%d_trunnion" % k, ["LEV_IOWA_CG_%d.001" % k], 1) for k in range(1, 5)]
    LASER = {s: Mount("LASER_%s" % s, "TANA_LASER_%s_house" % s, "TANA_LASER_%s_gun" % s, ["TANA_LASER_%s_gun" % s], 1,
                      socket="TANA_LASER_%s_SOC_Gun_01" % s) for s in ("FWD_L", "FWD_R", "AFT_L", "AFT_R")}
    RG = {s: Mount("RG_%s" % s, "railgun_%s_yaw" % s, "railgun_%s_pitch" % s, ["EMLS_rails.00%d" % (1 if s == "L" else 2)], 1)
          for s in ("L", "R")}
    RC_TIP = find_muzzles([D["RC_barrel_n.001"], D["RC_barrel_p.001"]], D["railcannon_pitch"].matrix_world.translation, 1)
    rc = bpy.data.objects.new("BREACH_mz_RC", None)
    FXC.objects.link(rc)
    rc.parent = D["railcannon_pitch"]
    rc.matrix_parent_inverse = rc.parent.matrix_world.inverted()
    rc.matrix_world = Matrix.Translation(RC_TIP[1][0]) @ RC_TIP[0].to_track_quat("Z", "X").to_matrix().to_4x4()
    print("breach: mounts measured: 16-inch %s, 5-inch %s, CIWS %s, lasers %s, railguns %s mouths"
          % ([len(m.tips) for m in T16], [len(m.tips) for m in T5], [len(m.tips) for m in CIWS],
             [len(m.tips) for m in LASER.values()], [len(m.tips) for m in RG.values()]))
    SHIP.animation_data.action = keep

    # deploy: the sub-railguns' hatches open and the guns lift, the bow railcannon rises and parts its rails
    for n in ("hatch_L_door_n", "hatch_L_door_p", "hatch_R_door_n", "hatch_R_door_p"):
        deploy(n, T_DEP0, T_DEP0 + 0.9)
    for n in ("railgun_L_lift", "railgun_R_lift"):
        deploy(n, T_DEP0 + 0.6, T_DEP0 + 1.6)
    deploy("railcannon_pitch", T_DEP0, T_DEP1 - 0.4)
    for n in ("railcannon_barrel_n", "railcannon_barrel_p"):
        deploy(n, T_DEP1 - 0.9, T_DEP1)

    # the threats, all to starboard: rail-shell targets on the horizon, aircraft for the flak, sea-skimmers for the lasers
    def far(x, y=-11000.0, z=260.0):
        return Vector((x, y, z))

    SALVOS = [(T16[0], 12.9, far(7000.0, -9000.0)), (T16[0], 14.7, far(5500.0, -10000.0)),
              (T16[1], 16.4, far(-8000.0, -8500.0)), (T16[1], 18.4, far(-9500.0, -7500.0, 320.0))]
    # missiles: (killed at, kill point, by)
    MISSILES = [(12.45, Vector((1100.0, -1500.0, 45.0)), "FWD_R"), (13.0, Vector((1900.0, -300.0, 55.0)), "FWD_L"),
                (13.6, Vector((300.0, -2000.0, 35.0)), "FWD_R"), (14.35, Vector((-150.0, -1750.0, 40.0)), "CIWS_1"),
                (15.1, Vector((-350.0, -2100.0, 50.0)), "FWD_R"), (15.95, Vector((-700.0, -1900.0, 30.0)), "AFT_R"),
                (16.6, Vector((-900.0, -1300.0, 28.0)), "CIWS_3"), (17.3, Vector((-1100.0, -2200.0, 60.0)), "AFT_R"),
                (18.2, Vector((-1450.0, -1700.0, 40.0)), "AFT_R"), (18.75, Vector((-1250.0, -900.0, 26.0)), "CIWS_3"),
                (19.35, Vector((-1700.0, -2300.0, 55.0)), "AFT_R")]
    FLAK = []
    for m, times in ((T5[0], (13.2, 13.9, 14.6, 15.3, 16.0)), (T5[2], (13.5, 14.2, 14.9, 15.6, 16.3, 17.0)),
                     (T5[4], (15.0, 15.7, 16.4, 17.1, 17.8, 18.5, 19.2))):
        for k, t in enumerate(times):
            cx = cam_x(t) - 650.0
            FLAK.append((m, t, Vector((cx + random.uniform(-500, 300), random.uniform(-4200, -3000), random.uniform(260, 520))), k))

    # the turrets: trained out as she deploys, then onto each target in turn
    for m in T16:
        m.aim(T_DEP1, far(7000.0, -9000.0) if m is T16[0] else far(-8000.0, -8500.0), slew=T_DEP1 - T_DEP0)
    for m, t, T in SALVOS:
        m.aim(t - 0.25, T, slew=0.9)
    first = {}
    for m, t, T, k in FLAK:
        first.setdefault(m.name, (m, t, T))
    for m in T5:                                              # the port 5-inch train out to port, guarding
        if m.side > 0:
            m.aim(T_DEP1, Vector((m.P.x + 800.0, 4000.0, 400.0)), slew=T_DEP1 - T_DEP0)
    for m, t, T in first.values():
        m.aim(T_DEP1, T, slew=T_DEP1 - T_DEP0)
    for m, t, T, k in FLAK:
        if (m.name, t) != (first[m.name][0].name, first[m.name][1]):
            m.aim(t - 0.12, T, slew=0.5)

    def mpos(K, tk, back):
        """an incoming missile's place at t: on a straight line in at 520 m/s to its kill point"""
        return lambda t: K + back * 520.0 * (tk - t)

    for m in list(LASER.values()) + CIWS + list(RG.values()):
        m.aim(T_DEP1, Vector((m.P.x - 300.0, -3000.0 if m.side <= 0 else 3000.0, 150.0)), slew=T_DEP1 - T_DEP0)
    kills = []
    for k, (tk, K, by) in enumerate(MISSILES):
        back = Vector((K.x * 0.15, K.y, 0.0)).normalized() + Vector((0.0, 0.0, 0.02))
        back.normalize()
        where = mpos(K, tk, back)
        m = LASER.get(by) or next(c for c in CIWS if c.name == by)
        dur = 0.32 if by in LASER else 1.0
        m.aim(tk - dur - 0.05, where(tk - dur), slew=0.45)
        m.aim(tk, where(tk), slew=dur)
        kills.append((k, tk, K, back, where, m, dur))
    RG_SHOTS = [(RG["R"], 17.2, far(-2000.0, z=1400.0)), (RG["L"], 18.0, Vector((2600.0, -6000.0, 1600.0)))]
    for m, t, T in RG_SHOTS:
        m.aim(t - 0.2, T, slew=1.2)
    for m in T16 + T5 + CIWS + list(LASER.values()) + list(RG.values()):
        m.keys.sort(key=lambda k: k[0])
        m.commit()

    # firing, now that every mount is keyed
    for m, t, T in SALVOS:                                    # the 16-inch rail turrets: blue-white, the shells streak
        lt = light("BREACH_light_" + m.name + "_%d" % fi(t), (0.7, 0.85, 1.0), 6.0)
        tips = tips_at(m, t)
        lt.location = sum((p for p, d in tips), Vector()) / len(tips)
        for f, e in ((F(t) - 1, 0.0), (F(t), 2.5e6), (F(t) + 2, 0.8e6), (F(t) + 6, 0.0)):
            lt.data.energy = e
            lt.data.keyframe_insert("energy", frame=f)
        for k, (p, d) in enumerate(tips):
            tt = t + 0.04 * k
            flash_at(m.tips[k], tt, 2.0, (0.45, 0.65, 1.0), length=2.6)
            projectile("BREACH_rail_%s_%d_%d" % (m.name, fi(t), k), p, d, tt, 2600.0, 2.6, (0.6, 0.8, 1.0), 0.55)
            beam("BREACH_railtrail_%s_%d_%d" % (m.name, fi(t), k), p + d * 6.0, p + d * 4200.0, tt, tt + 0.1,
                 (0.18, 0.3, 0.55), 0.22, fade=0.7)
            puff("BREACH_gas_%s_%d_%d" % (m.name, fi(t), k), M_SMOKE, p + d * 10.0, tt, 3.0, 15.0, 3.2,
                 drift=d * 26.0 + Vector((0, 0, 8.0)), alpha=0.75)
    for m, t, T, k in FLAK:                                   # the 5-inch: orange flashes, tracers, bursts round the aircraft
        p, d = tips_at(m, t)[k % len(m.tips)]
        flash_at(m.tips[k % len(m.tips)], t, 1.4, ORANGE, length=2.2)
        puff("BREACH_g5_%s_%d" % (m.name, fi(t)), M_SMOKE, p + d * 4.0, t, 1.5, 7.0, 1.8, drift=d * 9.0 + Vector((0, 0, 3.0)),
             alpha=0.55)
        dist = (T - p).length
        projectile("BREACH_s5_%s_%d" % (m.name, fi(t)), p, (T - p), t, 1600.0, dist / 1600.0, GOLD, 0.45)
        burst("BREACH_flak_%s_%d" % (m.name, fi(t)), T, t + dist / 1600.0, size=16.0, col=GOLD)
    for k, tk, K, back, where, m, dur in kills:               # the missiles, and what kills them
        o = bpy.data.objects.new("BREACH_missile_%d" % k, shape("cyl"))
        FXC.objects.link(o)
        slot_obj(o, BODY)
        t0 = tk - 4.0
        o.matrix_world = Matrix.Translation(where(t0)) @ (-back).to_track_quat("Z", "X").to_matrix().to_4x4() @ \
            Matrix.Diagonal((0.4, 0.4, 5.0, 1.0))
        o.keyframe_insert("location", frame=F(t0))
        o.location = where(tk)
        o.keyframe_insert("location", frame=F(tk))
        linear(o)
        for f, s in ((F(tk), 1.0), (F(tk) + 0.1, 0.0)):
            o.scale = (0.4 * s, 0.4 * s, 5.0 * s)
            o.keyframe_insert("scale", frame=f)
        o.scale = (0.4, 0.4, 5.0)
        g = bpy.data.objects.new("BREACH_exhaust_%d" % k, shape("ico1"))
        FXC.objects.link(g)
        slot_obj(g, M_FLASH)
        g.parent = o
        g.location, g.scale = (0, 0, -0.1), (3.0, 3.0, 0.3)
        g.color = (1.0, 0.75, 0.45, 1)
        TRAILS.append((o, t0, tk, 260, 2.4, 2.6))
        for f, s in ((F(t0) - 0.1, 0.0), (F(t0), 1.0)):     # (not there before it comes in)
            o.scale = (0.4 * s, 0.4 * s, 5.0 * s)
            o.keyframe_insert("scale", frame=f)
        o.scale = (0.4, 0.4, 5.0)
        if m.name.startswith("LASER"):
            tracking_beam("BREACH_laser_%d" % k, m.tips[0], where, tk - dur, tk, (1.0, 0.3, 0.2), 0.18)
            tracking_beam("BREACH_laserglow_%d" % k, m.tips[0], where, tk - dur, tk, (0.22, 0.035, 0.02), 0.8)
            g2 = flash_at(m.tips[0], tk - dur, 0.7, RED, length=1.0)
            blink(g2, tk - dur / 2, RED, hold=int(dur * FPS), fall=3)
        else:                                                 # the CIWS: a stream of tracers onto it
            for j in range(int(dur * 20)):
                tt = tk - dur + j / 20.0
                p, d = tips_at(m, tt)[0]
                aimp = where(tt + 0.5) + Vector((random.uniform(-12, 12), random.uniform(-12, 12), random.uniform(-6, 6)))
                dd = aimp - p
                projectile("BREACH_ciws_%d_%d" % (k, j), p, dd, tt, 1100.0, dd.length / 1100.0, GOLD, 0.25)
                if j % 2 == 0:
                    flash_at(m.tips[0], tt, 0.7, ORANGE, length=1.6)
        burst("BREACH_kill_%d" % k, where(tk), tk, size=18.0, col=ORANGE)
    # the bow railcannon: the biggest flash of the shot, a bolt along her axis, a ring blown across the sea
    T_RC = 11.9
    sc.frame_set(fi(T_RC))
    p, d = rc.matrix_world.translation.copy(), (rc.matrix_world.to_3x3() @ Vector((0, 0, 1))).normalized()
    flash_at(rc, T_RC, 4.0, (0.45, 0.7, 1.0), length=2.6)
    lt = light("BREACH_light_RC", (0.6, 0.85, 1.0), 10.0)
    lt.location = p
    for f, e in ((F(T_RC) - 1, 0.0), (F(T_RC), 5.0e6), (F(T_RC) + 3, 1.5e6), (F(T_RC) + 9, 0.0)):
        lt.data.energy = e
        lt.data.keyframe_insert("energy", frame=f)
    projectile("BREACH_rcbolt", p, d, T_RC, 3500.0, 2.5, (0.6, 0.85, 1.0), 1.3)
    beam("BREACH_rctrail", p + d * 4.0, p + d * 6000.0, T_RC, T_RC + 0.15, (0.25, 0.42, 0.75), 0.5, fade=1.2)
    puff("BREACH_rcgas", M_WHITE, p + d * 20.0, T_RC, 6.0, 30.0, 3.0, drift=d * 60.0 + Vector((0, 0, 12.0)), alpha=0.6)
    ring = bpy.data.objects.new("BREACH_rcring", shape("ico2"))
    FXC.objects.link(ring)
    slot_obj(ring, M_HAZE)
    ring.location = (p.x + 60.0, 0.0, 0.5)
    for f, s, a in ((F(T_RC) - 1, 0.0, 0.0), (F(T_RC), 20.0, 1.0), (F(T_RC + 1.4), 220.0, 0.7), (F(T_RC + 3.0), 320.0, 0.0)):
        ring.scale = (s, s * 0.8, 2.5)
        ring.color = (a, a, a, 1)
        ring.keyframe_insert("scale", frame=f)
        ring.keyframe_insert("color", frame=f)
    # the sub-railguns
    for m, t, T in RG_SHOTS:
        p, d = tips_at(m, t)[0]
        flash_at(m.tips[0], t, 1.6, (0.45, 0.65, 1.0), length=2.4)
        lt = light("BREACH_light_" + m.name, (0.7, 0.85, 1.0), 4.0)
        lt.location = p
        for f, e in ((F(t) - 1, 0.0), (F(t), 1.2e6), (F(t) + 5, 0.0)):
            lt.data.energy = e
            lt.data.keyframe_insert("energy", frame=f)
        projectile("BREACH_rgbolt_" + m.name, p, d, t, 3000.0, 2.5, (0.6, 0.8, 1.0), 0.5)
        beam("BREACH_rgtrail_" + m.name, p + d * 4.0, p + d * 4500.0, t, t + 0.1, (0.18, 0.3, 0.55), 0.2, fade=0.8)
    # the aft deck VLS: four missiles up and away to starboard
    for k in range(4):
        blk = "TANA_VLSD_1"
        h = D["%s_Hatch_%02d" % (blk, k + 1)]
        deploy(h.name, 16.9 + 0.15 * k, 17.3 + 0.15 * k)
        t0 = 17.6 + 0.3 * k
        sc.frame_set(fi(t0))
        c = D["%s_SOC_Vls_%02d" % (blk, k + 1)].matrix_world.translation.copy()
        goal = Vector((c.x - 2500.0 - 400.0 * k, -5200.0, 420.0))
        o = bpy.data.objects.new("BREACH_vls_%d" % k, shape("cyl"))
        FXC.objects.link(o)
        slot_obj(o, BODY)
        o.rotation_mode = "QUATERNION"
        last = None
        for f in range(fi(t0), N + 2):
            u = (f - F(t0)) / FPS
            s = clamp(u / 3.2)                                # up out of the cell, then over onto its bearing
            b = (1 - s) ** 2 * c + 2 * (1 - s) * s * (c + Vector((0, 0, 260.0))) + s * s * goal
            b = b if u < 3.2 else goal + (goal - (c + Vector((0, 0, 260.0)))).normalized() * 900.0 * (u - 3.2)
            w = b
            if last is not None and (w - last).length > 1e-3:
                o.rotation_quaternion = (w - last).to_track_quat("Z", "X")
            else:
                o.rotation_quaternion = Vector((0, 0, 1)).to_track_quat("Z", "X")
            o.location, o.scale = w, (0.5, 0.5, 6.0)
            o.keyframe_insert("location", frame=f)
            o.keyframe_insert("rotation_quaternion", frame=f)
            last = w
        for f, s in ((F(t0) - 0.1, 0.0), (F(t0), 1.0)):
            o.scale = (0.5 * s, 0.5 * s, 6.0 * s)
            o.keyframe_insert("scale", frame=f)
        g = bpy.data.objects.new("BREACH_vlsfire_%d" % k, shape("ico1"))
        FXC.objects.link(g)
        slot_obj(g, M_FLASH)
        g.parent = o
        g.location, g.scale, g.color = (0, 0, -0.15), (3.5, 3.5, 0.5), (1.0, 0.8, 0.5, 1)
        TRAILS.append((o, t0, DUR, 420, 2.8, 3.0))
        puff("BREACH_vlsblast_%d" % k, M_WHITE, c + Vector((0, 0, 4.0)), t0, 2.5, 13.0, 2.8, drift=(0, 0, 9.0), alpha=0.6)
        burst("BREACH_vlsflash_%d" % k, c + Vector((0, 0, 3.0)), t0, size=4.0, col=(0.9, 0.6, 0.3), dark=False)
    for o in FXC.objects:
        if o.name.startswith(("BREACH_flash", "BREACH_kill", "BREACH_flak", "BREACH_laser")):
            for fc in (o.animation_data.action.fcurves if o.animation_data and o.animation_data.action else []):
                if fc.data_path == "color":
                    for kp in fc.keyframe_points:
                        kp.interpolation = "LINEAR"

# ---------------------------------------------------------------------------------------------------- the sea
WATER_STEP = float(ENV("TANA_BREACH_WATER_STEP", "3.0"))
WC_MIN = float(ENV("TANA_BREACH_WHITECAPS", "0.78"))           # (the simulation's foam over this is a whitecap)


def axis_lines(lo, hi, step, far):
    xs = list(np.arange(lo, hi + 1e-6, step))
    p, d = hi, step
    while p < far:
        d *= 1.2
        p += d
        xs.append(p)
    p, d, low = lo, step, []
    while p > -far:
        d *= 1.2
        p -= d
        low.append(p)
    return np.array(sorted(low) + xs)


def grid(name, xs, ys):
    nx, ny = len(xs), len(ys)
    X, Y = np.meshgrid(xs, ys, indexing="ij")
    co = np.stack([X.ravel(), Y.ravel(), np.zeros(X.size)], 1)
    i = np.arange(nx - 1)[:, None] * ny + np.arange(ny - 1)[None, :]
    quads = np.stack([i, i + ny, i + ny + 1, i + 1], -1).reshape(-1, 4)
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(co))
    me.vertices.foreach_set("co", co.astype(np.float32).ravel())
    me.loops.add(quads.size)
    me.loops.foreach_set("vertex_index", quads.astype(np.int32).ravel())
    me.polygons.add(len(quads))
    me.polygons.foreach_set("loop_start", (np.arange(len(quads)) * 4).astype(np.int32))
    me.polygons.foreach_set("loop_total", np.full(len(quads), 4, np.int32))
    me.polygons.foreach_set("use_smooth", np.ones(len(quads), bool))
    me.update(calc_edges=True)
    me.validate()
    return me


xs = axis_lines(-650.0, 950.0, WATER_STEP, 22000.0)
ys = axis_lines(-850.0, 420.0, WATER_STEP, 22000.0)
SEA = bpy.data.objects.new("BREACH_sea", grid("BREACH_sea", xs, ys))
FXC.objects.link(SEA)
SEA.cycles.use_motion_blur = False                            # (the sea's own motion is slow: no blur, a lot less memory)
oc = SEA.modifiers.new("swell", "OCEAN")
oc.geometry_mode = "DISPLACE"
oc.spectrum = "PHILLIPS"
oc.resolution = int(ENV("TANA_BREACH_OCEAN_RES", "24"))
oc.viewport_resolution = 8
oc.spatial_size = 360
oc.wave_scale = float(ENV("TANA_BREACH_WAVES", "5.0"))      # (about +-3.7 m: measured)
oc.wave_scale_min = 2.0 * WATER_STEP                          # (no waves shorter than the grid can carry: no aliasing)
oc.wind_velocity = 17.0
oc.wave_alignment = 0.55
oc.wave_direction = math.radians(115.0)                       # the swell runs in from her starboard bow
oc.choppiness = 1.15
oc.damping = 0.5
oc.depth = 300.0
oc.random_seed = 7
oc.use_normals = False
oc.use_foam = True
oc.foam_layer_name = "foam"
oc.foam_coverage = 0.2
oc.time = 0.0
oc.keyframe_insert("time", frame=1)
oc.time = DUR
oc.keyframe_insert("time", frame=N + 1)
for fc in SEA.animation_data.action.fcurves:
    for k in fc.keyframe_points:
        k.interpolation = "LINEAR"

# the sea humping up over her bow before it breaks out
hump = bpy.data.objects.new("BREACH_hump", None)
FXC.objects.link(hump)
hump.location = BREACH + Vector((35.0, 0.0, 0.0))
hump.scale = (75.0, 48.0, 1.0)
tex = bpy.data.textures.new("BREACH_hump", "BLEND")
tex.progression = "QUADRATIC_SPHERE"
dm = SEA.modifiers.new("hump", "DISPLACE")
dm.texture, dm.texture_coords, dm.texture_coords_object = tex, "OBJECT", hump
dm.direction, dm.mid_level = "Z", 0.0
for t, v in ((0.0, 0.0), (T_BREAK - 1.6, 0.6), (T_BREAK - 0.1, 5.0), (T_BREAK + 0.7, 2.0), (T_BREAK + 1.8, 0.0)):
    dm.strength = v
    dm.keyframe_insert("strength", frame=F(t))


def hull_mask(size=(1536, 512), x0=-384.0, x1=384.0, y0=-128.0, y1=128.0, blur=(7.0, 2.5)):
    """her waterline, settled, as an image lying on the sea: where her hull and pods cross z = 0, blurred out to the
    white water along her sides"""
    W, H = size
    img = np.zeros((H, W), np.float32)
    for o in [o for o in SHIP.children_recursive if o.type == "MESH" and not o.hide_render]:
        me = o.data
        me.calc_loop_triangles()
        if not len(me.loop_triangles):
            continue
        co = np.empty(len(me.vertices) * 3, np.float32)
        me.vertices.foreach_get("co", co)
        M = np.array(o.matrix_world)
        P = co.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
        t = np.empty(len(me.loop_triangles) * 3, np.int32)
        me.loop_triangles.foreach_get("vertices", t)
        T = P[t.reshape(-1, 3)]
        z = T[:, :, 2]
        cross = (z.min(1) < 0.0) & (z.max(1) > 0.0)
        for tri in T[cross]:
            pts = []
            for a, b in ((0, 1), (1, 2), (2, 0)):
                za, zb = tri[a, 2], tri[b, 2]
                if (za < 0) != (zb < 0):
                    pts.append(tri[a] + (tri[b] - tri[a]) * (za / (za - zb)))
            if len(pts) == 2:
                n = max(2, int(np.linalg.norm(pts[1] - pts[0]) / 0.3))
                for s in np.linspace(0, 1, n):
                    q = pts[0] + (pts[1] - pts[0]) * s
                    u, v = int((q[0] - x0) / (x1 - x0) * W), int((q[1] - y0) / (y1 - y0) * H)
                    if 0 <= u < W and 0 <= v < H:
                        img[v, u] = 1.0
    px = (x1 - x0) / W
    for r_m, w in ((blur[0], 0.75), (blur[1], 1.0)):
        r = max(1, int(r_m / px))
        a = img.copy()
        for _ in range(3):                                    # three box blurs: near enough a Gaussian
            k = np.ones(2 * r + 1, np.float32) / (2 * r + 1)
            a = np.apply_along_axis(lambda m: np.convolve(m, k, "same"), 1, a)
            a = np.apply_along_axis(lambda m: np.convolve(m, k, "same"), 0, a)
        img = np.maximum(img, a / max(a.max(), 1e-6) * w)
    im = bpy.data.images.new("BREACH_hullmask", W, H, alpha=False, float_buffer=True)
    rgba = np.ones((H, W, 4), np.float32)
    rgba[:, :, 0] = rgba[:, :, 1] = rgba[:, :, 2] = img
    im.pixels.foreach_set(rgba.ravel())
    im.pack()
    im.colorspace_settings.name = "Non-Color"
    return im, (x0, x1, y0, y1)


keep = at_rest()
HULLMASK, HM_BOX = hull_mask()
SHIP.animation_data.action = keep
breach_spot = bpy.data.objects.new("BREACH_foamspot", None)
FXC.objects.link(breach_spot)
breach_spot.location = BREACH + Vector((25.0, 0.0, 0.0))
for t, sx, sy in ((0.0, 30.0, 18.0), (T_BREAK, 30.0, 18.0), (T_UP1, 85.0, 42.0), (T_DOWN, 140.0, 66.0), (DUR, 190.0, 90.0)):
    breach_spot.scale = (sx, sy, 1.0)
    breach_spot.keyframe_insert("scale", frame=F(t))


def sea_mat():
    def build(nt, out):
        tc = nt.nodes.new("ShaderNodeTexCoord")
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sxyz = nt.nodes.new("ShaderNodeSeparateXYZ")
        L_(nt, geo.outputs["Position"], sxyz.inputs[0])
        # crests catch a little green light; troughs deep blue
        crest = N_(nt, "ShaderNodeMapRange", **{"From Min": -1.2, "From Max": 2.4})
        L_(nt, sxyz.outputs["Z"], crest.inputs["Value"])
        col = N_(nt, "ShaderNodeMixRGB", Color1=(0.004, 0.018, 0.03, 1), Color2=(0.02, 0.085, 0.085, 1))
        L_(nt, math_(nt, "MULTIPLY", crest.outputs[0], 0.7), col.inputs["Fac"])
        # foam: whitecaps (the simulation's own), her waterline (once she is down), where she broke out
        fa = N_(nt, "ShaderNodeAttribute", _attribute_name="foam")
        wc = N_(nt, "ShaderNodeMapRange", **{"From Min": WC_MIN, "From Max": 1.0})
        L_(nt, fa.outputs["Fac"], wc.inputs["Value"])
        mp = N_(nt, "ShaderNodeMapping")
        x0, x1, y0, y1 = HM_BOX
        mp.inputs["Scale"].default_value = (1.0 / (x1 - x0), 1.0 / (y1 - y0), 1.0)
        mp.inputs["Location"].default_value = (-x0 / (x1 - x0), -y0 / (y1 - y0), 0.0)
        L_(nt, tc.outputs["Object"], mp.inputs["Vector"])
        hm = N_(nt, "ShaderNodeTexImage", _image=HULLMASK, _extension="CLIP")
        L_(nt, mp.outputs[0], hm.inputs["Vector"])
        hfade = N_(nt, "ShaderNodeValue", _name="hull_fade")
        hfade.outputs[0].default_value = 0.0
        tb = N_(nt, "ShaderNodeTexCoord", _object=breach_spot)
        gr = N_(nt, "ShaderNodeTexGradient", _gradient_type="QUADRATIC_SPHERE")
        L_(nt, tb.outputs["Object"], gr.inputs["Vector"])
        bfade = N_(nt, "ShaderNodeValue", _name="breach_fade")
        bfade.outputs[0].default_value = 0.0
        amount = math_(nt, "ADD", math_(nt, "MULTIPLY", wc.outputs[0], 0.45),
                       math_(nt, "ADD", math_(nt, "MULTIPLY", hm.outputs["Color"], hfade.outputs[0]),
                             math_(nt, "MULTIPLY", math_(nt, "POWER", gr.outputs["Fac"], 0.6), bfade.outputs[0])))
        # lace: foam is streaks and holes, not paint
        st = N_(nt, "ShaderNodeMapping")                          # (drawn out along the swell's run)
        st.inputs["Rotation"].default_value = (0.0, 0.0, math.radians(115.0))
        st.inputs["Scale"].default_value = (1.0, 3.0, 1.0)
        L_(nt, tc.outputs["Object"], st.inputs["Vector"])
        mg = N_(nt, "ShaderNodeTexMusgrave", _musgrave_type="RIDGED_MULTIFRACTAL", Scale=0.07, Detail=7.0,
                Dimension=0.55, Lacunarity=2.3, Offset=1.0, Gain=2.2)
        L_(nt, st.outputs[0], mg.inputs["Vector"])
        nz = N_(nt, "ShaderNodeTexNoise", Scale=0.05, Detail=6.0, Roughness=0.6)
        L_(nt, st.outputs[0], nz.inputs["Vector"])
        lace = N_(nt, "ShaderNodeMapRange", **{"From Min": 0.35, "From Max": 1.6})
        L_(nt, math_(nt, "MULTIPLY", mg.outputs["Fac"], math_(nt, "ADD", nz.outputs["Fac"], 0.5)), lace.inputs["Value"])
        foam = math_(nt, "MULTIPLY", math_(nt, "SUBTRACT", math_(nt, "MULTIPLY", amount, lace.outputs[0]), 0.1), 2.4, True)
        white = N_(nt, "ShaderNodeMixRGB")
        L_(nt, foam, white.inputs["Fac"])
        L_(nt, col.outputs[0], white.inputs["Color1"])
        white.inputs["Color2"].default_value = (0.78, 0.82, 0.84, 1)
        rough = N_(nt, "ShaderNodeMapRange", **{"To Min": 0.07, "To Max": 0.65})
        L_(nt, foam, rough.inputs["Value"])
        # small ripples over the swell
        rip = N_(nt, "ShaderNodeTexNoise", Scale=0.42, Detail=4.0, Roughness=0.55)
        L_(nt, tc.outputs["Object"], rip.inputs["Vector"])
        cat = N_(nt, "ShaderNodeTexNoise", Scale=2.2, Detail=2.0, Roughness=0.5)     # (cat's-paws: the wind on it)
        L_(nt, tc.outputs["Object"], cat.inputs["Vector"])
        bump = N_(nt, "ShaderNodeBump", Strength=0.5, Distance=0.2)
        L_(nt, math_(nt, "ADD", rip.outputs["Fac"], math_(nt, "MULTIPLY", cat.outputs["Fac"], 0.35)), bump.inputs["Height"])
        p = N_(nt, "ShaderNodeBsdfPrincipled", Specular=0.5, IOR=1.33)
        L_(nt, white.outputs[0], p.inputs["Base Color"])
        L_(nt, rough.outputs[0], p.inputs["Roughness"])
        L_(nt, bump.outputs[0], p.inputs["Normal"])
        L_(nt, p.outputs[0], out.inputs["Surface"])
    return mat("BREACH_sea", build)


SEA.data.materials.append(sea_mat())
SEA_NT = SEA.data.materials[0].node_tree
for name, keys in (("breach_fade", ((0.0, 0.0), (T_BREAK - 0.5, 0.0), (T_BREAK + 0.6, 1.0), (T_DOWN, 0.85), (DUR, 0.55))),
                   ("hull_fade", ((0.0, 0.0), (T_DOWN - 2.0, 0.0), (T_DOWN + 0.6, 1.0), (DUR, 0.7)))):
    v = SEA_NT.nodes[name].outputs[0]
    for t, a in keys:
        v.default_value = a
        v.keyframe_insert("default_value", frame=F(t))

# ---------------------------------------------------------------------------------------------------- the water she sheds
EMITTERS = []


def emitter_band(name, outline, inward=4.0, up=3.0):
    """a strip of faces along a closed outline on the sea, its normals up and outward"""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    c = sum((Vector(p) for p in outline), Vector()) / len(outline)
    lo = [bm.verts.new(p) for p in outline]
    hi = [bm.verts.new(Vector(p) + (c - Vector(p)).normalized() * inward + Vector((0, 0, up))) for p in outline]
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    for f in bm.faces:
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    FXC.objects.link(o)
    o.show_instancer_for_render = False
    EMITTERS.append(o)
    return o


def spray(obj, name, t0, t1, count, speed, rand, life, size, inst, drag=0.04, follow=0.0, srand=0.7, grav=1.0, sub=0):
    ps = obj.modifiers.new(name, "PARTICLE_SYSTEM").particle_system
    s = ps.settings
    s.name = name
    s.count = max(10, int(count * SCALE))
    s.frame_start, s.frame_end = F(t0), F(t1)
    s.lifetime, s.lifetime_random = life * FPS, 0.35
    s.emit_from, s.distribution, s.use_emit_random = "FACE", "RAND", True
    s.physics_type = "NEWTON"
    s.normal_factor, s.factor_random = speed, speed * rand
    s.object_factor = follow
    s.drag_factor, s.mass = drag, 1.0
    s.effector_weights.gravity = grav
    s.render_type, s.instance_object = "OBJECT", inst
    s.particle_size, s.size_random = size, srand
    s.use_rotations = False
    s.subframes = sub
    ps.point_cache.frame_start, ps.point_cache.frame_end = 1, N
    return ps


def shed_emitter():
    """her forebody's flanks and stem above her waterline (settled), and the deck edges: where the sea pours off her
    as she comes up (a copy of those faces, riding with her)"""
    keep = at_rest()
    hull = D["LEV_HULL.001"]
    me = hull.data
    W = hull.matrix_world
    N3 = W.to_3x3().inverted().transposed()
    bm = bmesh.new()
    verts = {}
    for p in me.polygons:
        c = W @ p.center
        n = (N3 @ p.normal).normalized()
        if c.x > 95.0 and c.z > 1.0 and abs(n.z) < 0.55 and p.area > 0.05:
            vs = []
            for i in p.vertices:
                if i not in verts:
                    verts[i] = bm.verts.new(W @ me.vertices[i].co + n * 0.4)
                vs.append(verts[i])
            try:
                bm.faces.new(vs)
            except ValueError:
                pass
    e = bpy.data.meshes.new("BREACH_shed")
    bm.to_mesh(e)
    bm.free()
    o = bpy.data.objects.new("BREACH_shed", e)
    FXC.objects.link(o)
    o.parent = SHIP
    o.matrix_parent_inverse = Matrix.Identity(4)
    o.show_instancer_for_render = False
    SHIP.animation_data.action = keep
    EMITTERS.append(o)
    return o


if SPRAY:
    # where she pierces the sea: a ring of white water, not a burst (speeds of 5-14 m/s: it rises a few to 15 m)
    ring = [(BREACH.x + 28.0 + 44.0 * math.cos(a), 21.0 * math.sin(a), 0.4) for a in (2 * math.pi * k / 40 for k in range(40))]
    E_RING = emitter_band("BREACH_ring", ring)
    spray(E_RING, "ring_drops", T_BREAK - 0.15, T_UP1 + 0.8, 80000, 6.5, 0.8, 2.6, 0.22, DROP, drag=0.05)
    spray(E_RING, "ring_lift", T_BREAK - 0.1, T_BREAK + 1.2, 26000, 12.0, 0.5, 3.0, 0.24, DROP, drag=0.04)
    spray(E_RING, "ring_mist", T_BREAK, T_UP1 + 1.5, 110, 2.5, 0.6, 5.0, 9.0, MIST, drag=0.12, grav=0.0)
    spray(E_RING, "ring_haze", T_BREAK + 0.3, T_DOWN, 30, 1.5, 0.5, 7.0, 24.0, HAZE, drag=0.2, grav=0.0)
    # the sea pouring off her bow and flanks as they come up (it leaves with a little of her speed and falls)
    E_SHED = shed_emitter()
    spray(E_SHED, "shed_streams", T_BREAK - 0.2, T_UP1 - 1.6, 330000, 1.2, 0.8, 4.8, 0.22, DROP, drag=0.0, follow=0.3,
          sub=2)

    def footprint(x0, x1, n, half_bow=30.0):
        side = []
        for k in range(n):
            x = x1 - (x1 - x0) * k / (n - 1)
            half = 8.0 + half_bow * min(1.0, (330.0 - x) / 150.0) if x > -20.0 else 78.0 - 30.0 * max(0.0, (-250.0 - x) / 80.0)
            side.append((x, half, 0.4))
        return side + [(x, -y, z) for x, y, z in reversed(side)]

    # she comes down and levels: white water thrown off her sides along her length, no great wall
    E_DOWN = emitter_band("BREACH_down", footprint(-300.0, 320.0, 40), inward=5.0, up=2.0)
    spray(E_DOWN, "down_drops", T_DOWN - 1.6, T_DOWN + 0.9, 200000, 8.0, 0.6, 2.8, 0.22, DROP, drag=0.05)
    spray(E_DOWN, "down_haze", T_DOWN - 1.0, T_DOWN + 2.5, 120, 1.5, 0.5, 6.0, 26.0, HAZE, drag=0.2, grav=0.0)

for o, t0, t1, rate, size, life in TRAILS:                    # the missiles' smoke trails: puffs left along their way
    ps = o.modifiers.new("trail", "PARTICLE_SYSTEM").particle_system
    s = ps.settings
    s.count, s.frame_start, s.frame_end = int(rate * (t1 - t0) * SCALE) + 10, F(t0), F(t1)
    s.lifetime, s.lifetime_random = life * FPS, 0.3
    s.emit_from, s.physics_type, s.normal_factor, s.object_factor = "VERT", "NEWTON", 0.0, 0.0
    s.effector_weights.gravity, s.drag_factor = 0.0, 0.0
    s.render_type, s.instance_object, s.particle_size, s.size_random = "OBJECT", TRAIL, size, 0.5
    s.use_rotations = False
    s.subframes = 10                                          # (emitted along each frame's stretch, not all at its end)
    ps.point_cache.frame_start, ps.point_cache.frame_end = 1, N

# ---------------------------------------------------------------------------------------------------- light
SKY = next((n for n in sc.world.node_tree.nodes if n.bl_idname == "ShaderNodeTexSky"), None)
if SKY:                                                       # a low evening sun off her port bow: behind the camera's
    SKY.sun_elevation = math.radians(float(ENV("TANA_BREACH_SUN", "9.0")))   # shoulder in both halves of the shot
    SKY.sun_rotation = math.atan2(0.62, 0.78)
    SKY.air_density, SKY.dust_density, SKY.ozone_density, SKY.sun_intensity = 1.0, float(ENV("TANA_BREACH_DUST", "0.8")), 2.0, 1.0
for n in sc.world.node_tree.nodes:
    if n.bl_idname == "ShaderNodeBackground":
        n.inputs["Strength"].default_value = float(ENV("TANA_BREACH_SKY", "0.22"))
sc.view_settings.view_transform = "Filmic"
sc.view_settings.look = "Medium High Contrast"
sc.view_settings.exposure = float(ENV("TANA_BREACH_EXPOSURE", "0.3"))

# ---------------------------------------------------------------------------------------------------- bake and render
sc.frame_set(1)
with bpy.context.temp_override(scene=sc, view_layer=sc.view_layers[0]):
    bpy.ops.ptcache.bake_all(bake=True)
n_ps = sum(len(o.particle_systems) for o in sc.objects if o.type == "MESH")
print("breach: %d frames at %d fps; her stem breaks out at %.2f s; %d particle systems baked; %d effect objects, %d lights"
      % (N, FPS, T_BREAK, n_ps, len(FXC.objects), len(LIGHTS)))
# the effects light nothing by themselves (the flash lights do that) and cast no shadows: Cycles would otherwise sample
# every glowing face as a lamp (600,000 drops among them) and trace shadows through every puff
for m in bpy.data.materials:
    if m.name.startswith("BREACH_"):
        m.cycles.sample_as_light = False
for o in FXC.objects:
    if o.type == "MESH" and o.name != "BREACH_sea":
        o.visible_shadow = False
        o.visible_diffuse = False
        o.visible_transmission = False
if ENV("TANA_BREACH_DUMP"):
    sc.frame_set(int(ENV("TANA_BREACH_DUMP")))
    for o in sc.objects:
        if o.type == "MESH" and not o.hide_render and min(o.matrix_world.to_scale()) > 1e-4 and o.name.startswith("BREACH_") \
                and o.name not in ("BREACH_sea",) and o.matrix_world.translation.z > -100:
            print("dump: %-34s at %s scale %.2f colour %s" % (o.name, tuple(round(c) for c in o.matrix_world.translation),
                                                              max(o.matrix_world.to_scale()), tuple(round(c, 2) for c in o.color)))
    sys.exit(0)
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
sc.cycles.denoiser = "OPENIMAGEDENOISE"
sc.cycles.transparent_max_bounces = 16
sc.cycles.max_bounces = 4
sc.cycles.diffuse_bounces, sc.cycles.glossy_bounces, sc.cycles.transmission_bounces = 2, 2, 2
sc.cycles.volume_bounces = 0
sc.cycles.caustics_reflective = sc.cycles.caustics_refractive = False
sc.render.use_motion_blur = True
sc.render.motion_blur_shutter = float(ENV("TANA_BREACH_SHUTTER", "0.3"))
sc.render.use_persistent_data = True
sc.render.resolution_x, sc.render.resolution_y = RES
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = "PNG"
sc.view_layers[0].material_override = None
d = os.path.join(OUT, "frames_breach")
RESUME = ENV("TANA_BREACH_RESUME", "0") == "1"                 # (keep the frames already rendered: a stopped run goes on)
if not ONLY and not RESUME:
    shutil.rmtree(d, ignore_errors=True)
os.makedirs(d, exist_ok=True)
frames = ONLY or list(range(1, N + 1, STEP))
for k, f in enumerate(frames):
    sc.render.filepath = os.path.join(d, ("still_%04d.png" % f) if ONLY else ("%04d.png" % k))
    if RESUME and os.path.exists(sc.render.filepath):
        continue
    sc.frame_set(f)
    bpy.ops.render.render(write_still=True)
    print("breach: frame %d (%.2f s)" % (f, (f - 1) / FPS), flush=True)
if not ONLY:
    clip = os.path.join(OUT, "tanacorn_breach.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(max(1, FPS // STEP)), "-i",
                    os.path.join(d, "%04d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "17", clip], check=True)
    print("breach: ->", clip)
