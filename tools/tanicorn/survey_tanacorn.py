"""survey_tanacorn.py : Blender 3.3, THE TANACORN photographed area by area (the user, 2026-11-10: "go over the entire
model ... I want to see photos of each area"). Run on the file model_tanacorn.py saves:

  blender -b <model dir>/Tanacorn_model.blend -P tools/tanicorn/survey_tanacorn.py -- <out dir> [shot ...]

Square-on views with no perspective, so nothing hides behind anything: five stretches of her from above (stern to
bow), the same five from each side, from ahead and from astern; then the joints close up from both sides (the bow's
bay and its doors, the forward barbette at the bay's end, the bow where the starboard side was mended, each pod's
root from above, from astern and along the deck's edge); then her underside with the sea taken away (stern, middle,
bow). Port and starboard are always shot as a pair from mirrored places, so the two pictures can be laid side by
side. Every picture gets its name and what it shows written along its foot (PIL, when it is there).
TANA_SURVEY_SAMPLES (24), TANA_SURVEY_WIDTH (1600). audit_tanacorn.py is the measured half of the same check.
"""
import bpy, sys, os, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("build/tanicorn/survey")
WANT = argv[1:]
WIDTH = int(os.environ.get("TANA_SURVEY_WIDTH", "1600"))
os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
sc.frame_set(1)
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = int(os.environ.get("TANA_SURVEY_SAMPLES", "24"))
sc.cycles.use_denoising = True
sc.render.use_persistent_data = True
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = "PNG"
sc.view_settings.view_transform = "Standard"                  # (plain: what is dark is dark geometry, not the look)
sc.view_settings.exposure = float(os.environ.get("TANA_SURVEY_EXPOSURE", "1.2"))
for o in bpy.data.objects:
    if o.name.endswith("_proto"):
        o.hide_render = True
SEA = bpy.data.objects.get("SEA")
# even light: a plain bright sky all round (so the undersides and the shaded side are lit too) and one sun over the
# camera's shoulder for shape
world = bpy.data.worlds.new("survey")
world.use_nodes = True
nt = world.node_tree
bg = nt.nodes["Background"]
bg.inputs[0].default_value, bg.inputs[1].default_value = (0.72, 0.78, 0.85, 1.0), 0.55
# what the camera itself sees of the sky is a plain light blue: anywhere the ship can be seen THROUGH shows as that
# blue, and is not to be mistaken for a white glint off the plating
seen = nt.nodes.new("ShaderNodeBackground")
seen.inputs[0].default_value, seen.inputs[1].default_value = (0.35, 0.62, 0.95, 1.0), 0.75
path, mix = nt.nodes.new("ShaderNodeLightPath"), nt.nodes.new("ShaderNodeMixShader")
nt.links.new(path.outputs["Is Camera Ray"], mix.inputs[0])
nt.links.new(bg.outputs[0], mix.inputs[1])
nt.links.new(seen.outputs[0], mix.inputs[2])
nt.links.new(mix.outputs[0], nt.nodes["World Output"].inputs["Surface"])
sc.world = world
for o in [o for o in bpy.data.objects if o.type == "LIGHT"]:
    o.hide_render = True
sun = bpy.data.objects.new("survey_sun", bpy.data.lights.new("survey_sun", "SUN"))
sun.data.energy, sun.data.angle = 2.6, math.radians(4.0)
sc.collection.objects.link(sun)
cam = bpy.data.objects.new("survey_cam", bpy.data.cameras.new("survey_cam"))
cam.data.clip_start, cam.data.clip_end = 1.0, 5000.0
sc.collection.objects.link(cam)
sc.camera = cam


def look(loc, at, up="Y"):
    loc, at = Vector(loc), Vector(at)
    cam.location = loc
    cam.rotation_euler = (at - loc).to_track_quat("-Z", up).to_euler()
    d = (loc - at).normalized()                                # the sun from over the camera's shoulder
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 0.1:
        side = Vector((1, 0, 0))
    s = (d + 0.9 * side.normalized() + (0.8 if abs(d.z) < 0.9 else 0.0) * Vector((0, 0, 1))).normalized()   # (well off the
                                                               # camera's line: no mirror glints straight back off the plating)
    sun.rotation_euler = (-s).to_track_quat("-Z", "Y").to_euler()


def ortho(name, note, loc, at, wide, high, up="Y", sea=True):
    cam.data.type = "ORTHO"
    sc.render.resolution_x, sc.render.resolution_y = WIDTH, int(round(WIDTH * high / wide))
    cam.data.ortho_scale = max(wide, high)
    look(loc, at, up)
    shoot(name, note, sea)


def persp(name, note, loc, at, lens=50.0, sea=True):
    cam.data.type = "PERSP"
    cam.data.lens = lens
    sc.render.resolution_x, sc.render.resolution_y = WIDTH, int(WIDTH * 9 / 16)
    look(loc, at, "Y")
    shoot(name, note, sea)


DONE = []


def shoot(name, note, sea):
    if WANT and not any(name.startswith(w) or w in name for w in WANT):
        return
    if SEA:
        SEA.hide_render = not sea
    path = os.path.join(OUT, "survey_%s.png" % name)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    DONE.append((name, note, path))
    print("survey: %s (%s)" % (name, note))


# ---- from above: stern to bow, port at the top, the bow to the right
STRETCH = (("1_stern", -330, -190, 80), ("2_aft", -200, -60, 80), ("3_middle", -70, 70, 42), ("4_fore", 60, 200, 42),
           ("5_bow", 190, 330, 42))
for tag, x0, x1, half in STRETCH:
    ortho("top_%s" % tag, "from above, x %d..%d m (port at the top, bow to the right)" % (x0, x1),
          ((x0 + x1) / 2, 0, 400), ((x0 + x1) / 2, 0, 0), x1 - x0, 2 * half)
# ---- from each side, the same stretches
for tag, x0, x1, _ in STRETCH:
    top = 88 if tag == "3_middle" else 62
    for side, s in (("port", 1), ("starboard", -1)):
        ortho("side_%s_%s" % (tag, side), "from %s, x %d..%d m" % (side, x0, x1),
              ((x0 + x1) / 2, 500 * s, (top - 8) / 2), ((x0 + x1) / 2, 0, (top - 8) / 2), x1 - x0, top + 8, up="Y")
# ---- end on
ortho("end_ahead", "from dead ahead", (900, 0, 38), (0, 0, 38), 164, 96, up="Y")
ortho("end_astern", "from dead astern", (-900, 0, 38), (0, 0, 38), 164, 96, up="Y")
# ---- the joints, each from port and from starboard (mirrored places)
for side, s in (("port", 1), ("starboard", -1)):
    persp("joint_bay_%s" % side, "the bow's bay and its doors in the deck, from off the %s bow" % side,
          (262, 48 * s, 55), (158, 0, 9), 45)
    persp("joint_barbette_%s" % side, "the forward turret's barbette at the bay's after end, from %s" % side,
          (128, 34 * s, 24), (99, 2 * s, 12), 50)
    persp("joint_bow_side_%s" % side, "the bow's %s side under the rail, between the last two side VLS blocks "
          "(where the starboard side was mended)" % side, (236, 60 * s, 13), (206, 12.5 * s, 8.5), 60)
    persp("joint_midships_%s" % side, "the superstructure abaft the forward funnel, %s side (the Iowa's own openings "
          "there)" % side, (-62, 58 * s, 58), (-17, 5 * s, 22), 70)
    persp("joint_pod_above_%s" % side, "the %s pod's root on the hull, from above" % side,
          (-70, 105 * s, 85), (-150, 30 * s, 6), 50)
    persp("joint_pod_astern_%s" % side, "the %s pod's root from off the stern" % side,
          (-345, 70 * s, 34), (-225, 24 * s, 3), 50)
    persp("joint_pod_fore_%s" % side, "the %s pod's forward end where it meets the hull's side" % side,
          (60, 75 * s, 22), (-20, 31 * s, 5), 50)
    persp("joint_pod_edge_%s" % side, "along the %s pod's root at the deck's edge, looking aft" % side,
          (-55, 38 * s, 16), (-150, 31 * s, 9), 40)
# ---- her underside, the sea taken away: looking straight up, port at the top, bow to the right
for tag, x0, x1, half in (("1_stern", -330, -190, 80), ("2_aft", -200, -60, 80), ("3_fore", -70, 130, 80), ("4_bow", 120, 330, 60)):
    ortho("under_%s" % tag, "from below (the sea taken away), x %d..%d m" % (x0, x1),
          ((x0 + x1) / 2, 0, -400), ((x0 + x1) / 2, 0, 0), x1 - x0, 2 * half, up="Y", sea=False)

import json
with open(os.path.join(OUT, "survey.json"), "w") as f:         # (label_survey.py writes each picture's name along its foot)
    json.dump([{"name": n, "note": t, "file": os.path.basename(p)} for n, t, p in DONE], f, indent=1)
print("survey: %d pictures in %s" % (len(DONE), OUT))
