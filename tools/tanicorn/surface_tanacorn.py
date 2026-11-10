"""surface_tanacorn.py : Blender 3.3, THE TANACORN breaking the surface, on film (the user, 2026-11-10, with a reference
clip of a submarine breaching against a sunset: "render a shot of it surfacing out of water like this video. Add VFX
to it").

  blender -b <out>/Tanacorn_model.blend -P tools/tanicorn/surface_tanacorn.py -- <film dir>

Run on the file model_tanacorn.py saves. The shot, at 24 fps (13.5 s):
  0.5 - 5 s     her bow comes up out of the sea along her own axis, 35 deg nose-up, fast and slowing, until it stands
                120 m over the water with about a third of her out (the user's choice after a first test at 60 deg
                and 480 m: "THATS WAAAY TOO HIGH");
  5 - 9 s       she hangs, then her bow comes down about the point where her hull stands in the water, faster and
                faster, while the rest of her comes up through the surface;
  9 s           her bow slams flat; a few seconds of pitching and heaving as she settles.
Her mounts stay stowed (the deploy sequence's keys are taken off for the shot). The effects are Blender's own, no
simulation of the sea itself:
  - spray: particle systems (Newtonian, the scene's gravity, a little drag; baked before rendering) drawn as soft
    translucent blobs and bright drops: a burst and then a steady curtain from a ring where the hull stands in the
    water, water shed off the whole hull as it comes up (it leaves with the hull's own speed), a wall thrown up
    round her forebody when her bow slams, and the sea boiling along the rest of her as her decks come through it;
  - foam: two patches lying on the sea, a disc spreading from where she breaks the surface and a long one where she
    falls, their edges and holes from a noise texture;
  - light: the design's sky turned to a low sun behind her, so the spray is lit from behind as in the reference.
Two cameras, both low on the water off her port bow, the sun and the spray behind her: close as her stem comes up (it
tilts up after her bow), then further off and wider as her bow comes down and she levels. Cycles on the CPU; TANA_SURF_RES (1280x720), TANA_SURF_SAMPLES (12),
TANA_SURF_STEP (1: every frame), TANA_SURF_FRAMES (a comma list, for test stills). Writes <film dir>/
tanacorn_surfacing.mp4 (ffmpeg).
"""
import bpy, bmesh, sys, os, math, shutil, subprocess
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("build/tanicorn/film")
os.makedirs(OUT, exist_ok=True)
RES = [int(v) for v in os.environ.get("TANA_SURF_RES", "1280x720").split("x")]
STEP = int(os.environ.get("TANA_SURF_STEP", "1"))
ONLY = [int(v) for v in os.environ.get("TANA_SURF_FRAMES", "").split(",") if v]
SCALE = float(os.environ.get("TANA_SURF_PARTICLES", "1.0"))        # (fewer particles for a quick test)

FPS, DUR = 24, 13.5
N = int(FPS * DUR)
T_UP0, T_UP1, T_SLAM = 0.5, 5.0, 9.0
PITCH = math.radians(35.0)                                 # (the user, on a first test at 60 deg with the bow 480 m up:
BOW, STERN = 325.0, -325.0                                 # "THATS WAAAY TOO HIGH"; a third of her out, they chose)
TOP = 120.0                                                # the bow's height at the top of the rise
D0 = -(BOW + 25.0)                                         # the ship's middle along her axis from the surface: start
D1 = TOP / math.sin(PITCH) - BOW                           # ... and at the top (-116 m: 209 m of her 650 out)
BREACH = Vector((-D1, 0.0, 0.0))                           # where her axis stands in the sea (she ends at the origin)

sc = bpy.context.scene
sc.render.fps = FPS
sc.frame_start, sc.frame_end = 1, N
sc.frame_set(1)
SHIP = bpy.data.objects["LEV_ship"]
HULL = bpy.data.objects["LEV_HULL.001"]
for o in [SHIP] + list(SHIP.children_recursive):           # the mounts stay stowed: the deploy sequence's keys off
    if o.animation_data:
        o.animation_data_clear()
for o in bpy.data.objects:
    if o.name.endswith("_proto"):
        o.hide_render = True


def pose(t):
    """the ship's middle and her nose-up angle at t seconds"""
    if t <= T_UP1:
        s = min(1.0, max(0.0, (t - T_UP0) / (T_UP1 - T_UP0)))
        d = D0 + (D1 - D0) * (1.0 - (1.0 - s) ** 1.8)      # fast out of the water, slowing to a stop at the top
        th = PITCH
        return BREACH + Vector((math.cos(th), 0.0, math.sin(th))) * d, th
    if t <= T_SLAM:
        s = (t - T_UP1) / (T_SLAM - T_UP1)
        th = PITCH * math.cos(math.pi / 2 * s ** 1.7)      # she hangs, then her bow comes down faster and faster
                                                           # while the rest of her comes up through the surface
        return BREACH + Vector((math.cos(th), 0.0, math.sin(th))) * D1, th
    u = t - T_SLAM                                         # the slam's bounce: the bow digs in, she heaves and settles
    k = math.exp(-0.9 * u)
    return Vector((0.0, 0.0, -3.0 * k * math.cos(2.2 * u))), -math.radians(2.2) * k * math.sin(2.6 * u)


SHIP.rotation_mode = "XYZ"
for f in range(1, N + 1):
    loc, th = pose((f - 1) / FPS)
    SHIP.location = loc
    SHIP.rotation_euler = (0.0, -th, 0.0)
    SHIP.keyframe_insert("location", frame=f)
    SHIP.keyframe_insert("rotation_euler", frame=f)

# ---------------------------------------------------------------------------------------------------- the spray
coll = bpy.data.collections.new("SURFACING")
sc.collection.children.link(coll)


def mat(name, build):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    build(nt, nt.nodes.new("ShaderNodeOutputMaterial"))
    return m


def mist(nt, out, alpha=None):                             # a soft blob: mostly see-through, lit through from behind
    tr, tl, df = (nt.nodes.new(k) for k in ("ShaderNodeBsdfTransparent", "ShaderNodeBsdfTranslucent", "ShaderNodeBsdfDiffuse"))
    tl.inputs["Color"].default_value = (1.0, 0.97, 0.94, 1)
    df.inputs["Color"].default_value = (0.95, 0.95, 0.95, 1)
    a, b = nt.nodes.new("ShaderNodeMixShader"), nt.nodes.new("ShaderNodeMixShader")
    a.inputs[0].default_value, b.inputs[0].default_value = 0.6, alpha or MIST_ALPHA
    em, add = nt.nodes.new("ShaderNodeEmission"), nt.nodes.new("ShaderNodeAddShader")
    em.inputs["Color"].default_value, em.inputs["Strength"].default_value = (1.0, 0.8, 0.6, 1), GLOW
    nt.links.new(df.outputs[0], a.inputs[1])
    nt.links.new(tl.outputs[0], a.inputs[2])
    nt.links.new(a.outputs[0], add.inputs[0])
    nt.links.new(em.outputs[0], add.inputs[1])
    lw, inv, pw, mu = (nt.nodes.new(k) for k in ("ShaderNodeLayerWeight", "ShaderNodeMath", "ShaderNodeMath", "ShaderNodeMath"))
    lw.inputs["Blend"].default_value = 0.5                 # (a puff, not a ball: it thins out to nothing at its rim)
    inv.operation, pw.operation, mu.operation = "SUBTRACT", "POWER", "MULTIPLY"
    inv.inputs[0].default_value, pw.inputs[1].default_value, mu.inputs[1].default_value = 1.0, 1.6, alpha or MIST_ALPHA
    nt.links.new(lw.outputs["Facing"], inv.inputs[1])
    nt.links.new(inv.outputs[0], pw.inputs[0])
    nt.links.new(pw.outputs[0], mu.inputs[0])
    nt.links.new(mu.outputs[0], b.inputs[0])
    nt.links.new(tr.outputs[0], b.inputs[1])
    nt.links.new(add.outputs[0], b.inputs[2])
    nt.links.new(b.outputs[0], out.inputs["Surface"])


def drop(nt, out):                                         # a bright drop
    tl, df, a = nt.nodes.new("ShaderNodeBsdfTranslucent"), nt.nodes.new("ShaderNodeBsdfDiffuse"), nt.nodes.new("ShaderNodeMixShader")
    a.inputs[0].default_value = 0.6
    em, add = nt.nodes.new("ShaderNodeEmission"), nt.nodes.new("ShaderNodeAddShader")
    em.inputs["Color"].default_value, em.inputs["Strength"].default_value = (1.0, 0.85, 0.7, 1), GLOW * 1.5
    nt.links.new(df.outputs[0], a.inputs[1])
    nt.links.new(tl.outputs[0], a.inputs[2])
    nt.links.new(a.outputs[0], add.inputs[0])
    nt.links.new(em.outputs[0], add.inputs[1])
    nt.links.new(add.outputs[0], out.inputs["Surface"])


GLOW = float(os.environ.get("TANA_SURF_GLOW", "0.12"))        # the spray's own warm light (it is lit from behind)
MIST_ALPHA = float(os.environ.get("TANA_SURF_ALPHA", "0.85"))
M_MIST, M_DROP = mat("SURF_mist", mist), mat("SURF_drop", drop)
M_HAZE = mat("SURF_haze", lambda nt, out: mist(nt, out, 0.12))   # the big faint puffs that hang over the foot of it


def blob(name, m, sub):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    o.location = (0, 0, -500.0)                            # (the pattern itself: under the sea, out of sight)
    return o


BLOB, DROP, HAZE = blob("SURF_blob", M_DROP, 1), blob("SURF_drop", M_DROP, 1), blob("SURF_haze", M_HAZE, 2)   # (drops are
# solid: at a pixel or two across, see-through ones only cost time)


def band(name, outline, lift=1.0, out=0.45):
    """an emitter: a strip of faces along a closed outline at the sea's level, lying back so that its normals point
    up and a little outward (a first try stood them nearly upright: the spray went out flat over the sea)"""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    c = sum((Vector(p) for p in outline), Vector()) / len(outline)
    lo = [bm.verts.new(p) for p in outline]
    hi = [bm.verts.new(Vector(p) + (c - Vector(p)).normalized() * 6.0 * lift + Vector((0, 0, 6.0 * out))) for p in outline]
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:                                     # normals up and outward
        if f.normal.z < 0:
            f.normal_flip()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    o.show_instancer_for_render = False
    return o


def spray(obj, name, t0, t1, count, speed, rand, life, size, inst, drag=0.035, follow=0.0, srand=0.75):
    ps = obj.modifiers.new(name, "PARTICLE_SYSTEM").particle_system
    s = ps.settings
    s.name = name
    s.count = max(10, int(count * SCALE))
    s.frame_start, s.frame_end = 1 + t0 * FPS, 1 + t1 * FPS
    s.lifetime, s.lifetime_random = life * FPS, 0.4
    s.emit_from, s.distribution, s.use_emit_random = "FACE", "RAND", True
    s.physics_type = "NEWTON"
    s.normal_factor, s.factor_random = speed, speed * rand      # (factor_random is in m/s, not a share: without
                                                           # it every drop leaves at one speed and the spray is a flat sheet)
    s.object_factor = follow                               # (water shed off the hull leaves with the hull's speed)
    s.drag_factor, s.mass = drag, 1.0
    s.render_type, s.instance_object = "OBJECT", inst
    s.particle_size, s.size_random = size, srand
    s.use_rotations = False
    ps.point_cache.frame_start, ps.point_cache.frame_end = 1, N
    return ps


# spray is a great many small drops, not big balls (a first try with 4-17 m blobs looked like popcorn and hid her):
# drops of 0.3-1.5 m, under a pixel or two from the cameras, so the frame's sampling turns them into mist; thrown at
# 15-50 m/s with half as much again either way at random, so the spray is ragged, 20-150 m high, and takes seconds to
# rise and fall (the slowness is what makes her look as big as she is); a few big faint puffs of haze over its foot
ring = [(BREACH.x + 70.0 * math.cos(a), 40.0 * math.sin(a), 0.5) for a in (2 * math.pi * k / 48 for k in range(48))]
E_RING = band("SURF_ring", ring)
spray(E_RING, "breach_burst", T_UP0, T_UP0 + 1.3, 70000, 34.0, 0.4, 6.5, 1.3, BLOB)
spray(E_RING, "breach_drops", T_UP0, T_UP0 + 1.8, 30000, 46.0, 0.5, 6.5, 0.9, DROP, drag=0.02)
spray(E_RING, "curtain", T_UP0 + 1.0, T_SLAM, 80000, 19.0, 0.45, 4.5, 1.2, BLOB, drag=0.05)
spray(E_RING, "foot_haze", T_UP0 + 0.3, T_SLAM + 1.5, 1600, 7.0, 0.6, 6.0, 18.0, HAZE, drag=0.1)


def footprint(x0, x1, n):                                  # her outline at the waterline between two stations
    side = []
    for k in range(n):
        x = x1 - (x1 - x0) * k / (n - 1)
        half = 8.0 + 26.0 * min(1.0, (330.0 - x) / 150.0) if x > -20.0 else 78.0 - 30.0 * max(0.0, (-250.0 - x) / 80.0)
        side.append((x, half, 0.5))
    return side + [(x, -y, z) for x, y, z in reversed(side)]


E_SLAM = band("SURF_slam", footprint(BREACH.x - 10.0, 330.0, 16))   # the bow coming down
spray(E_SLAM, "slam_wall", T_SLAM - 0.35, T_SLAM + 0.7, 95000, 36.0, 0.6, 7.5, 1.3, BLOB, drag=0.03)
spray(E_SLAM, "slam_drops", T_SLAM - 0.3, T_SLAM + 0.9, 40000, 48.0, 0.5, 7.5, 0.9, DROP, drag=0.015)
spray(E_SLAM, "slam_haze", T_SLAM - 0.1, T_SLAM + 2.5, 1800, 10.0, 0.6, 6.0, 22.0, HAZE, drag=0.08)
E_BOIL = band("SURF_boil", footprint(-330.0, BREACH.x - 10.0, 28))   # the rest of her coming up
spray(E_BOIL, "boil", T_UP1 + 1.6, T_SLAM + 1.0, 60000, 15.0, 0.7, 3.4, 1.0, BLOB, drag=0.06)
spray(E_BOIL, "boil_drops", T_UP1 + 1.8, T_SLAM + 0.8, 20000, 20.0, 0.6, 3.6, 0.8, DROP, drag=0.03)
spray(HULL, "shed", T_UP0 + 0.4, T_SLAM + 1.5, 30000, 3.0, 0.6, 2.6, 0.6, DROP, drag=0.01, follow=1.0)
spray(HULL, "shed_mist", T_UP0 + 0.4, T_SLAM + 1.0, 50000, 4.0, 0.6, 2.8, 0.9, BLOB, drag=0.06, follow=0.85)

# ---------------------------------------------------------------------------------------------------- the foam


def foam(name, key_scale, key_fade):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, cap_tris=True, segments=64, radius=1.0)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)

    def build(nt, out):
        tc, noise, ramp = nt.nodes.new("ShaderNodeTexCoord"), nt.nodes.new("ShaderNodeTexNoise"), nt.nodes.new("ShaderNodeValToRGB")
        noise.inputs["Scale"].default_value, noise.inputs["Detail"].default_value = 9.0, 8.0
        grad, mul, fade = nt.nodes.new("ShaderNodeTexGradient"), nt.nodes.new("ShaderNodeMath"), nt.nodes.new("ShaderNodeMath")
        grad.gradient_type = "SPHERICAL"                   # thick in the middle, torn at the edge
        ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[1].position = 0.5, 0.72
        mul.operation = fade.operation = "MULTIPLY"
        val = nt.nodes.new("ShaderNodeValue")
        val.name = "fade"
        df, tr, mix = nt.nodes.new("ShaderNodeBsdfDiffuse"), nt.nodes.new("ShaderNodeBsdfTransparent"), nt.nodes.new("ShaderNodeMixShader")
        df.inputs["Color"].default_value = (0.92, 0.93, 0.94, 1)
        nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
        nt.links.new(tc.outputs["Object"], grad.inputs["Vector"])
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], mul.inputs[0])
        nt.links.new(grad.outputs["Fac"], mul.inputs[1])
        nt.links.new(mul.outputs[0], fade.inputs[0])
        nt.links.new(val.outputs[0], fade.inputs[1])
        nt.links.new(fade.outputs[0], mix.inputs[0])
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(df.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
    m = mat(name, build)
    me.materials.append(m)
    val = m.node_tree.nodes["fade"].outputs[0]
    for t, sxy in key_scale:
        o.scale = (sxy[0], sxy[1], 1.0)
        o.keyframe_insert("scale", frame=1 + t * FPS)
    for t, v in key_fade:
        val.default_value = v
        val.keyframe_insert("default_value", frame=1 + t * FPS)
    return o


F1 = foam("SURF_foam_breach", [(T_UP0, (40, 30)), (T_UP0 + 2.0, (130, 95)), (T_SLAM, (240, 150)), (DUR, (270, 170))],
          [(0.0, 0.0), (T_UP0, 0.0), (T_UP0 + 0.7, 2.6), (T_SLAM, 2.2), (DUR, 1.3)])
F1.location = (BREACH.x + 40.0, 0.0, 0.35)
F2 = foam("SURF_foam_hull", [(T_UP1 + 1.0, (330, 60)), (T_SLAM, (400, 130)), (DUR, (450, 190))],
          [(0.0, 0.0), (T_UP1 + 1.0, 0.0), (T_SLAM - 0.5, 1.6), (DUR, 1.4)])
F2.location = (-20.0, 0.0, 0.45)

# ---------------------------------------------------------------------------------------------------- light and cameras
SKY = next((n for n in sc.world.node_tree.nodes if n.bl_idname == "ShaderNodeTexSky"), None)
if SKY:                                                     # a low sun astern of her and to starboard: behind her and
    SKY.sun_elevation = math.radians(float(os.environ.get("TANA_SURF_SUN", "4.0")))   # her spray from both cameras
    SKY.sun_rotation = math.atan2(-0.80, -0.60)             # (the sun's bearing: x -0.80 astern, y -0.60 to starboard)
    SKY.air_density, SKY.dust_density, SKY.ozone_density, SKY.sun_intensity = 2.0, 7.0, 3.0, 1.0
for n in sc.world.node_tree.nodes:
    if n.bl_idname == "ShaderNodeBackground":
        n.inputs["Strength"].default_value = float(os.environ.get("TANA_SURF_SKY", "0.16"))
sc.view_settings.exposure = float(os.environ.get("TANA_SURF_EXPOSURE", "0.0"))
fill = bpy.data.objects.new("SURF_fill", bpy.data.lights.new("SURF_fill", "SUN"))   # a soft light from the cameras' side,
fill.data.energy, fill.data.angle = float(os.environ.get("TANA_SURF_FILL", "7.0")), math.radians(25.0)   # so she is not
fill.data.color = (1.0, 0.86, 0.72)                         # only a black shape against the sun
fill.rotation_euler = Vector((-0.62, -0.68, -0.4)).to_track_quat("-Z", "Y").to_euler()
coll.objects.link(fill)
sea = bpy.data.objects.get("SEA")
if sea:                                                     # a longer swell for the low light to catch
    for n in sea.data.materials[0].node_tree.nodes:
        if n.bl_idname == "ShaderNodeBump":
            n.inputs["Strength"].default_value = 0.5

cam = bpy.data.objects.new("CAM_surfacing", bpy.data.cameras.new("CAM_surfacing"))
sc.collection.objects.link(cam)
cam.data.clip_end = 30000.0
sc.camera = cam
T_CUT = 5.7


def shot(t):
    if t < T_CUT:                                          # low on the water off her port bow, ahead of where she
        s = min(1.0, max(0.0, (t - T_UP0) / (T_UP1 - T_UP0)))   # breaks the surface: her stem comes up out of the sea
        e = s * s * (3 - 2 * s)                            # towards the camera and over it, the spray behind her; it
        look = Vector((BREACH.x + 70.0 + 60.0 * e, 0.0, 16.0 + 50.0 * e))   # tilts up after her bow
        return Vector((BREACH.x + 400.0 - 30.0 * e, 250.0, 5.0)), look, 32.0
    s = (t - T_CUT) / (DUR - T_CUT)                        # further off and higher on the same bow: her bow comes down,
    return Vector((520.0 - 40.0 * s, 380.0, 34.0)), Vector((40.0, 0.0, 38.0 - 22.0 * min(1.0, s * 2.0))), 27.0   # she levels


for f in range(1, N + 1):
    loc, look, lens = shot((f - 1) / FPS)
    cam.location = loc
    cam.rotation_euler = (look - loc).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    cam.keyframe_insert("location", frame=f)
    cam.keyframe_insert("rotation_euler", frame=f)
    cam.data.keyframe_insert("lens", frame=f)

# ---------------------------------------------------------------------------------------------------- bake and render
with bpy.context.temp_override(scene=sc, view_layer=sc.view_layers[0]):
    bpy.ops.ptcache.bake_all(bake=True)
print("surfacing: %d frames at %d fps; spray baked: %d particles in %d systems"
      % (N, FPS, sum(ps.settings.count for o in (E_RING, E_SLAM, E_BOIL, HULL) for ps in o.particle_systems),
         sum(len(o.particle_systems) for o in (E_RING, E_SLAM, E_BOIL, HULL))))
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = int(os.environ.get("TANA_SURF_SAMPLES", "12"))
sc.cycles.use_denoising = True
sc.cycles.transparent_max_bounces = 16
sc.cycles.max_bounces = 6
sc.render.resolution_x, sc.render.resolution_y = RES
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = "PNG"
sc.view_layers[0].material_override = None
d = os.path.join(OUT, "frames_surfacing")
if not ONLY:
    shutil.rmtree(d, ignore_errors=True)
os.makedirs(d, exist_ok=True)
frames = ONLY or list(range(1, N + 1, STEP))
for k, f in enumerate(frames):
    sc.frame_set(f)
    sc.render.filepath = os.path.join(d, ("still_%04d.png" % f) if ONLY else ("%04d.png" % k))
    bpy.ops.render.render(write_still=True)
    print("surfacing: frame %d (%.2f s)" % (f, (f - 1) / FPS))
if not ONLY:
    clip = os.path.join(OUT, "tanacorn_surfacing.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(max(1, FPS // STEP)), "-i",
                    os.path.join(d, "%04d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "17", clip], check=True)
    print("surfacing: ->", clip)
