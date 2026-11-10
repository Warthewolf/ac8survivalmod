"""film_tanacorn.py : Blender 3.3, THE TANACORN's moving parts on film (the user, 2026-11-10: "render a shot of all
animations working as the camera tracks around, get some close up shots too").

  blender -b <out>/Tanacorn_model.blend -P tools/tanicorn/film_tanacorn.py -- <film dir> [shot ...]

Run on the file model_tanacorn.py saves: it holds the design's own deploy sequence (30 fps, frames 1-360: the bow's
hatch doors, the railcannon, the 16-inch and 5-inch turrets training and their guns lifting, the CIWS) and what the
model adds to it (all 128 VLS hatches opening at 150-165 and shutting at 290-305, the four laser turrets slewing out at
60-100 and back at 200-240). Shots, each rendered every STEP-th frame of the sequence and played at 30 / STEP fps, so
the parts move at their real speed:
  orbit        the camera tracks right round the ship over the whole sequence
  aft_vls      close: the aft deck's VLS blocks, their hatches opening and shutting
  side_vls     close: the bow's side VLS blocks, along the port flank
  bow          close: the forward turret and the bow as the sequence deploys them
  laser        close: a laser turret slewing
  aft_turret   close: turret C and the superstructure's aft end
The sun goes round with the camera (always over its shoulder), so no shot looks at a side in shade. Cycles on the CPU;
TANA_FILM_SAMPLES (10), TANA_FILM_RES (960x540), TANA_FILM_STEP (2). Writes <film dir>/tanacorn_<shot>.mp4 and all of
them end to end as tanacorn_film.mp4 (ffmpeg).
"""
import bpy, sys, os, math, shutil, subprocess
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("build/tanicorn/film")
WANT = argv[1:]
STEP = int(os.environ.get("TANA_FILM_STEP", "2"))
RES = [int(v) for v in os.environ.get("TANA_FILM_RES", "960x540").split("x")]
os.makedirs(OUT, exist_ok=True)

sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = int(os.environ.get("TANA_FILM_SAMPLES", "10"))
sc.cycles.use_denoising = True
sc.render.use_persistent_data = True
sc.render.resolution_x, sc.render.resolution_y = RES
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = "PNG"
sc.view_layers[0].material_override = None
SKY = next((n for n in sc.world.node_tree.nodes if n.bl_idname == "ShaderNodeTexSky"), None)

for o in bpy.data.objects:                                     # the part types' line-up on the sea beside her (the
    if o.name.endswith("_proto"):                              # stills' sheet) is not part of the ship
        o.hide_render = True
cam = bpy.data.objects.new("CAM_film", bpy.data.cameras.new("CAM_film"))
sc.collection.objects.link(cam)
cam.data.clip_end = 20000.0
sc.camera = cam


def aim(loc, look, lens):
    loc, look = Vector(loc), Vector(look)
    cam.location = loc
    cam.rotation_euler = (look - loc).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    if SKY:                                                    # the sun over the camera's shoulder (35 deg round)
        d = loc - look
        SKY.sun_rotation = math.pi / 2 - (math.atan2(d.y, d.x) + math.radians(35.0))


def lerp(a, b, t):
    return Vector(a) * (1 - t) + Vector(b) * t


def ease(t):
    return t * t * (3 - 2 * t)


def at(name):
    return bpy.data.objects[name].matrix_world.translation.copy()


def orbit(t):
    a = math.radians(55.0 + 330.0 * t)                         # from off the port bow, round the stern, back to the bow
    h = 150.0 - 60.0 * math.sin(math.pi * t)                   # (broadside the whole 650 m just fills the frame)
    return (560.0 * math.cos(a), 640.0 * math.sin(a), h), (0, 0, 14), 28      # (the whole 650 m in frame all the way)


def aft_vls(t):
    return lerp((-345, 80, 62), (-318, 30, 44), ease(t)), (-240, 0, 9), 45


def side_vls(t):
    return lerp((262, 80, 16), (150, 62, 24), ease(t)), lerp((205, 12, 6), (165, 18, 6), ease(t)), 42


def bow(t):
    return lerp((255, 120, 70), (215, 85, 40), ease(t)), lerp((120, 0, 14), (140, 0, 12), ease(t)), 40


def laser(t):
    c = at("TANA_LASER_FWD_L_house") + Vector((0, 0, 3.4))
    a = math.radians(20.0 + 110.0 * ease(t))
    return c + Vector((17 * math.cos(a), 17 * math.sin(a), 5.0)), c, 50


def aft_turret(t):
    return lerp((-250, 110, 70), (-215, 75, 48), ease(t)), (-150, 0, 16), 40


SHOTS = [("orbit", orbit, 1, 360), ("aft_vls", aft_vls, 130, 315), ("side_vls", side_vls, 130, 315),
         ("bow", bow, 10, 270), ("laser", laser, 45, 250), ("aft_turret", aft_turret, 20, 260)]
clips = []
for name, fn, f0, f1 in SHOTS:
    if WANT and name not in WANT:
        continue
    d = os.path.join(OUT, "frames_" + name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    frames = list(range(f0, f1 + 1, STEP))
    for k, f in enumerate(frames):
        sc.frame_set(f)
        aim(*fn(k / max(1, len(frames) - 1)))
        sc.render.filepath = os.path.join(d, "%04d.png" % k)
        bpy.ops.render.render(write_still=True)
    clip = os.path.join(OUT, "tanacorn_%s.mp4" % name)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(max(1, 30 // STEP)), "-i", os.path.join(d, "%04d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", clip], check=True)
    if not os.environ.get("TANA_FILM_KEEP"):
        shutil.rmtree(d)
    clips.append(clip)
    print("film: %s: frames %d-%d, %d rendered -> %s" % (name, f0, f1, len(frames), clip))
if len(clips) > 1:
    lst = os.path.join(OUT, "clips.txt")
    with open(lst, "w") as fh:
        fh.write("".join("file '%s'\n" % c for c in clips))
    whole = os.path.join(OUT, "tanacorn_film.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", whole],
                   check=True)
    print("film: all of them -> %s" % whole)
