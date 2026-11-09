# Blender 3.3: import the AC8 Alicorn (GLBs from ACE8 Aircraft Builder's dev mesh) and Sea Power's Iowa (OBJ),
# give them their textures, group them into reusable source objects, save a source .blend.
# blender -b -P bl_import.py -- <alcn dir> <iowa dir> <out.blend>
import bpy, bmesh, sys, os, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
ALC, IOWA, OUT = argv[0], argv[1], argv[2]
IOWA_SCALE = 270.4 / 3.9265  # Sea Power's model is 3.9265 units bow to stern; the real ship is 270.4 m

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
src = bpy.data.collections.new("SRC")
scene.collection.children.link(src)


def only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def bake_skins(objs):
    """Keep skinned meshes in their bind pose as plain meshes; drop the armatures."""
    out = []
    for o in objs:
        if o.type == "MESH":
            for m in list(o.modifiers):
                o.modifiers.remove(m)
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
            out.append(o)
    for o in objs:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    return out


def import_glb(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ALC, name + ".glb"))
    return bake_skins([o for o in bpy.data.objects if o not in before])


def ue(x, y, z):  # Unreal cm (left-handed) -> Blender m, matching the GLB import
    return Vector((x * 0.01, -y * 0.01, z * 0.01))


def img(path, noncolor=False):
    i = bpy.data.images.load(path, check_existing=True)
    if noncolor:
        i.colorspace_settings.name = "Non-Color"
    return i


def alc_material(tag):
    m = bpy.data.materials.new("ALC_" + tag)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    d = nt.nodes.new("ShaderNodeTexImage"); d.image = img(os.path.join(ALC, "tex", "T_BA002_alcn_%s_D.png" % tag))
    nt.links.new(d.outputs["Color"], p.inputs["Base Color"])
    n = nt.nodes.new("ShaderNodeTexImage"); n.image = img(os.path.join(ALC, "tex", "T_BA002_alcn_%s_N.png" % tag), True)
    sep = nt.nodes.new("ShaderNodeSeparateRGB"); nt.links.new(n.outputs["Color"], sep.inputs[0])
    inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
    nt.links.new(sep.outputs["G"], inv.inputs[1])  # UE normal maps are DirectX (green down)
    comb = nt.nodes.new("ShaderNodeCombineRGB"); comb.inputs["B"].default_value = 1.0
    nt.links.new(sep.outputs["R"], comb.inputs["R"]); nt.links.new(inv.outputs[0], comb.inputs["G"])
    nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(comb.outputs[0], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    mr = nt.nodes.new("ShaderNodeTexImage"); mr.image = img(os.path.join(ALC, "tex", "T_BA002_alcn_%s_MREC.png" % tag), True)
    sep2 = nt.nodes.new("ShaderNodeSeparateRGB"); nt.links.new(mr.outputs["Color"], sep2.inputs[0])
    nt.links.new(sep2.outputs["R"], p.inputs["Metallic"]); nt.links.new(sep2.outputs["G"], p.inputs["Roughness"])
    return m


MAT = {"a": alc_material("a"), "b": alc_material("b")}


def set_alc_mats(o):
    for s in o.material_slots:
        s.material = MAT["a"] if (s.material and "alcn_a" in s.material.name) else MAT["b"]


# ---------- Alicorn ----------
# the game builds the Alicorn from the body (open railcannon slot and bay) and the bridge; SM_BA002_alcn is a
# closed whole-ship mesh with the deck over the cannon
hull = import_glb("SM_BA002_alcn_body") + import_glb("SM_BA002_alcn_bridge")
alc_parts = list(hull)
sock = {
    "aagun": [(23806.2, -1330), (23806.2, 1330), (14056.2, -1330), (14056.2, 1330), (4306.2, -1330), (4306.2, 1330),
              (-24456.2, -1330), (-24456.2, 1330)],
    "ram": [(27056.2, -1330), (27056.2, 1330), (-27706.2, -1330), (-27706.2, 1330)],
    "emls": [(-11460.0, -5655), (-11460.0, 5655)],
}
for kind, files in (("aagun", ["SK_BA002_alcn_aagun"]), ("ram", ["SK_BA002_alcn_ram"])):
    base = import_glb(files[0])[0]
    for i, (x, y) in enumerate(sock[kind]):
        o = base if i == 0 else base.copy()
        if i:
            src.objects.link(o)
        o.location = ue(x, y, 1820)
        alc_parts.append(o)
for f in ["SM_BA002_alcn_ecm", "SM_BA002_alcn_tank_L_01", "SM_BA002_alcn_tank_L_02", "SM_BA002_alcn_tank_R_01",
          "SM_BA002_alcn_tank_R_02", "SM_BA002_alcn_vls_L_01", "SM_BA002_alcn_vls_L_02", "SM_BA002_alcn_vls_R_01",
          "SM_BA002_alcn_vls_R_02"] + ["SK_BA002_alcn_hatch_%s_%02d" % (s, n) for s in "LR" for n in range(1, 7)]:
    alc_parts += import_glb(f)
emlm = import_glb("SK_BA002_alcn_emlm")
for o in bpy.data.objects:
    if o.type == "MESH":
        for c in list(o.users_collection):
            c.objects.unlink(o)
        src.objects.link(o)
        set_alc_mats(o)
for o in alc_parts:  # make copies single-user before joining
    if o.data.users > 1:
        o.data = o.data.copy()
only(alc_parts); bpy.ops.object.join(); A = bpy.context.view_layer.objects.active; A.name = "ALC_HULL"
only(emlm); bpy.ops.object.join(); E = bpy.context.view_layer.objects.active; E.name = "ALC_RAILCANNON"
for o in (A, E):
    only([o]); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# ---------- Iowa ----------
before = set(bpy.data.objects)
bpy.ops.import_scene.obj(filepath=os.path.join(IOWA, "Iowa.obj"), use_split_objects=True, use_split_groups=False,
                         axis_forward="-Z", axis_up="Y")
iowa = [o for o in bpy.data.objects if o not in before]
for o in iowa:
    for c in list(o.users_collection):
        c.objects.unlink(o)
    src.objects.link(o)
only(iowa)
bpy.ops.transform.resize(value=(IOWA_SCALE,) * 3, center_override=(0, 0, 0))
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def centre(o):
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    lo = Vector([min(v[i] for v in vs) for i in range(3)]); hi = Vector([max(v[i] for v in vs) for i in range(3)])
    return (lo + hi) / 2, lo, hi


def base_name(o):
    n = o.name.split("#", 1)[-1].split(".")[0]
    return n


t1 = [o for o in iowa if base_name(o).startswith("usn_bb_iowa_406mm_turret_1")][0]
c1 = centre(t1)[0]
# turn the ship so its bow (turret 1 end) points along +X
ang = -math.atan2(c1.y, c1.x) + math.pi  # Sea Power's "turret_1" is the aft one (checked on the top view)
only(iowa)
bpy.ops.transform.rotate(value=ang, orient_axis="Z", center_override=(0, 0, 0))
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in iowa:
    o.data.materials and None


def group(prefix_anchor, members):
    """members: objects joined to the nearest anchor (anchors are the objects whose name starts with prefix_anchor)."""
    anchors = [o for o in members if base_name(o).startswith(prefix_anchor)
               and not base_name(o).endswith(("_top", "_trans")) and "_top_" not in base_name(o) and "_trans_" not in base_name(o)]
    out = {a: [a] for a in anchors}
    ac = {a: centre(a)[0] for a in anchors}
    def num(o):  # Sea Power lists a turret's parts right after it: name_<running number>
        t = base_name(o).rsplit("_", 1)[-1]
        return int(t) if t.isdigit() else None
    for o in members:
        if o in anchors:
            continue
        n = num(o)
        before = [a for a in anchors if num(a) is not None and n is not None and num(a) < n]
        if before:
            a = max(before, key=num)
        else:
            c = centre(o)[0]
            a = min(anchors, key=lambda a: (Vector((c.x, c.y)) - Vector((ac[a].x, ac[a].y))).length)
        out[a].append(o)
    return out


heavy = [o for o in iowa if "406mm" in base_name(o)]
five = [o for o in iowa if "127mm" in base_name(o)]
ciws = [o for o in iowa if "ciws" in base_name(o)]
rest = [o for o in iowa if o not in heavy + five + ciws]
made = []
for label, prefix, members in (("IOWA_T16_", "usn_bb_iowa_406mm_turret_", heavy), ("IOWA_T5_", "usn_bb_iowa_127mm_turret", five),
                               ("IOWA_CIWS_", "usn_bb_iowa_ciws_mount", ciws)):
    gs = group(prefix, members)
    for i, (a, objs) in enumerate(sorted(gs.items(), key=lambda kv: -centre(kv[0])[0].x)):
        c, lo, hi = centre(a)
        guns = [o for o in objs if any(k in base_name(o) for k in ("_guns", "barrel", "ciws_gun"))]
        house = [o for o in objs if o not in guns]
        gp = None
        if guns:
            core = [o for o in guns if "_guns" in base_name(o) or "ciws_gun" in base_name(o)] or guns
            gc, glo, ghi = centre(core[0])
            gp = gc if "ciws" not in label else Vector((gc.x, gc.y, glo.z))
        only(house); bpy.ops.object.join(); j = bpy.context.view_layer.objects.active
        j.name = "%s%d" % (label, i + 1)
        piv = Vector((c.x, c.y, lo.z))
        j.data.transform(Matrix.Translation(-piv)); j.location = piv
        made.append(j)
        if guns:
            only(guns); bpy.ops.object.join(); g = bpy.context.view_layer.objects.active
            g.name = "%s%d" % (label.replace("_T", "_G").replace("_CIWS_", "_CG_"), i + 1)
            g.data.transform(Matrix.Translation(-gp)); g.location = gp
            made.append(g)
only(rest); bpy.ops.object.join(); H = bpy.context.view_layer.objects.active; H.name = "IOWA_HULL"
for o in made:
    print("group", o.name, tuple(round(v, 1) for v in o.location), len(o.data.polygons))
for o in (A, E, H):
    c, lo, hi = centre(o)
    print("bounds", o.name, tuple(round(v, 1) for v in lo), tuple(round(v, 1) for v in hi), len(o.data.polygons))
bpy.ops.wm.save_as_mainfile(filepath=OUT)
