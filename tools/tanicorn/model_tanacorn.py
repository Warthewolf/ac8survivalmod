"""model_tanacorn.py : Blender 3.3, THE TANACORN's model from the Leviathan design (docs/design/INVINCIBLE_FLEET.md WP0).

  blender -b art/tanicorn/design/Leviathan_animated.blend -P tools/tanicorn/model_tanacorn.py -- <out dir> [render]

The design (Sea Power's Iowa fused with AC8's Alicorn: the user's dev install only, never shipped) is the ship as it is;
this script adds what the settled armament needs that neither source ship has, and the hull's mount sockets:
  - 4 laser interceptor turrets at the design's LEV_LASER_* corners: TANA_LASER_<pos>_house (turret_yaw) and
    TANA_LASER_<pos>_gun (turret_pitch, its origin the pitch pivot), the beam's socket SOC_Gun_01 at the lens;
  - 8 deck VLS blocks on the aft deck behind turret C (TANA_VLSD_1..8): 8 cell wells under 8 hinged hatches each
    (TANA_VLSD_<n>_Hatch_01..08, each object's origin its hinge), sockets SOC_Vls_01..08 straight up;
  - 8 side VLS blocks on the bow's flanks, 4 a side (TANA_VLSS_L1..4 / R1..4), set flush in the hull's skin, following
    its flare and sheer: 8 wells under 8 hatches hinged at their top edge, swinging up and out; sockets SOC_Vls_01..08
    along each cell's launch line (out of the hull's side, 35 deg above level);
  - SOCKET_Mount_* empties on the hull for every part, in tanacorn_hull_sockets.json (UE frame: cm, x fwd, y right,
    z up; yaw / pitch degrees, a socket's +X its forward), with each VLS block's hatches (hinge, axis, open angle).
Every new part type is built once (a prototype mesh shared by all its copies) as ONE closed solid: its pieces united by
Blender's exact boolean, cell wells cut, bevelled (2 segments, normals hardened), merged, normals outward, unwrapped
(smart UV, no overlaps) and checked (non-manifold / open edges, faces through each other, degenerate faces, UVs out of
0..1: tanacorn_model_check.json). Its texture is baked once (textures/T_TANA_<part>_D.png: the paint, a light grime
noise and its own ambient occlusion; ordinary PNGs, hard rule 44).
Writes <out>/Tanacorn_model.blend (the design file is never changed) and, with `render`, <out>/renders/*.png (Cycles
on the CPU; TANA_SAMPLES, TANA_SHOTS).
"""
import bpy, bmesh, sys, os, json, math
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("build/tanicorn/model")
RENDER = "render" in argv[1:]
TEX = os.path.join(OUT, "textures")
os.makedirs(TEX, exist_ok=True)

SHIP = bpy.data.objects["LEV_ship"]
HULL = bpy.data.objects["LEV_HULL.001"]
COLL = bpy.data.collections["5 LEVIATHAN animated"]


def collection(name, parent):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in [x.name for x in parent.children]:
        parent.children.link(c)
    return c


ADD = collection("TANACORN additions", COLL)
SOCK = collection("TANACORN sockets", COLL)
WORK = collection("TANACORN prototypes", bpy.context.scene.collection)   # each part type once, away from the ship
DG = bpy.context.evaluated_depsgraph_get()
SHIP_MESHES = [o for o in COLL.all_objects if o.type == "MESH"]
CHECK = {}


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
    m["tana_base"] = list(rgb)
    return m


M_PAINT = mat("TANA_paint", (0.085, 0.088, 0.092), 0.65, 0.34)          # the design's Alicorn grey upper works
M_DARK = mat("TANA_dark", (0.026, 0.027, 0.029), 0.5, 0.48)              # cell wells, the emitter's rings
M_TEAL = mat("TANA_teal", (0.02, 0.35, 0.32), 0.2, 0.25, (0.05, 0.85, 0.75), 6.0)   # the railcannon bay's teal, lit
M_TEAL["tana_glow"] = True


# ---------------------------------------------------------------------------------------------------- clean solids
class Part:
    """primitives (each with a material) united into one closed solid; cutters carved out of it"""
    def __init__(self):
        self.bm, self.cut, self.mats = bmesh.new(), bmesh.new(), []

    def _slot(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _put(self, bm, verts, m):
        i = self._slot(m)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = i

    def box(self, size, at, m=M_PAINT, rot=Matrix(), cut=False):
        bm = self.cut if cut else self.bm
        r = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(at) @ rot.to_4x4() @ Matrix.Diagonal((*size, 1)))
        self._put(bm, r["verts"], m)

    def cyl(self, r1, r2, depth, at, axis="Z", m=M_PAINT, seg=24):
        R = {"Z": Matrix(), "X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Y": Matrix.Rotation(math.pi / 2, 4, "X")}[axis]
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=depth,
                                  matrix=Matrix.Translation(at) @ R)
        self._put(self.bm, r["verts"], m)

    def solid(self, name, bevel=0.03, simplify=True):
        me = bpy.data.meshes.new(name + "_raw")
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        tmp = bpy.data.objects.new(name + "_tmp", me)
        WORK.objects.link(tmp)
        dummy = bpy.data.objects.new(name + "_none", bpy.data.meshes.new(name + "_none"))
        WORK.objects.link(dummy)
        u = tmp.modifiers.new("union", "BOOLEAN")
        u.operation, u.solver, u.use_self, u.object = "UNION", "EXACT", True, dummy
        cutter = None
        if self.cut.verts:                                           # the cell wells, cut with the union
            cme = bpy.data.meshes.new(name + "_cut")
            self.cut.to_mesh(cme)
            for m in self.mats:
                cme.materials.append(m)
            cutter = bpy.data.objects.new(name + "_cutter", cme)
            WORK.objects.link(cutter)
            d = tmp.modifiers.new("cells", "BOOLEAN")
            d.operation, d.solver, d.object = "DIFFERENCE", "EXACT", cutter
            if hasattr(d, "material_mode"):
                d.material_mode = "TRANSFER"                       # the wells' walls take the cutter's dark
        out = applied(tmp, name + "_solid")                          # 1. united and cut
        tmp.modifiers.clear()
        for o in (dummy, cutter):
            if o:
                bpy.data.objects.remove(o)
        tmp.data = out
        bpy.data.meshes.remove(me)
        bm = bmesh.new()                                             # 2. welded, straight edges and flat faces made
        bm.from_mesh(out)                                            #    simple (no stray vertices for the bevel to trip on)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
        if simplify:
            bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.5), use_dissolve_boundaries=False, verts=bm.verts,
                                     edges=bm.edges, delimit={"MATERIAL"})
        bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=0.0005)
        bmesh.ops.connect_verts_concave(bm, faces=bm.faces)          # no concave faces (no face wrapping round a well)
        bmesh.ops.connect_verts_nonplanar(bm, angle_limit=math.radians(1.0), faces=bm.faces)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bw = bm.edges.layers.bevel_weight.verify()                   # only outside edges are rounded: inside corners
        for e in bm.edges:                                           # stay crisp (bevels there collide in tight spots)
            e[bw] = 1.0 if (e.is_manifold and e.is_convex and e.calc_face_angle(0.0) > math.radians(30)) else 0.0
        bm.to_mesh(out)
        bm.free()
        if bevel:                                                    # 3. bevelled, and nothing touches it after
            out.use_auto_smooth, out.auto_smooth_angle = True, math.radians(30)
            b = tmp.modifiers.new("bevel", "BEVEL")
            b.width, b.segments, b.limit_method = bevel, 2, "WEIGHT"
            b.use_clamp_overlap = True
            nxt = applied(tmp, name + "_bevel")
            tmp.modifiers.clear()
            tmp.data = nxt
            bpy.data.meshes.remove(out)
            out = nxt
            bm = bmesh.new()                                         # 4. the bevel's corner faces split convex
            bm.from_mesh(out)
            bmesh.ops.connect_verts_concave(bm, faces=bm.faces)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(out)
            bm.free()
        self.cut.free()
        out.name = name
        out.use_auto_smooth, out.auto_smooth_angle = True, math.radians(30)
        unwrap(tmp)
        check(out)
        tmp.name = name + "_proto"
        return out, tmp


def tidy(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()


def applied(obj, name):
    dg = bpy.context.evaluated_depsgraph_get()
    m = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    m.name = name
    return m


def select_only(obj):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)


def unwrap(obj):
    select_only(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.012, area_weight=0.0, correct_aspect=True,
                             scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def check(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    tree = BVHTree.FromBMesh(bm)
    inter = 0
    for a, c in tree.overlap(tree):
        if a < c and not ({v.index for v in bm.faces[a].verts} & {v.index for v in bm.faces[c].verts}):
            inter += 1
    uv = bm.loops.layers.uv.active
    uv_out = sum(1 for f in bm.faces for lp in f.loops if not (-1e-4 <= lp[uv].uv.x <= 1.0001 and -1e-4 <= lp[uv].uv.y <= 1.0001)) if uv else -1
    tris = sum(len(f.verts) - 2 for f in bm.faces)

    def concave(f):
        if len(f.verts) < 4:
            return False
        vs = [v.co for v in f.verts]
        n = f.normal
        return any((vs[i] - vs[i - 1]).cross(vs[(i + 1) % len(vs)] - vs[i]).dot(n) < -1e-9 for i in range(len(vs)))
    r = {"verts": len(bm.verts), "tris": tris,
         "non_manifold_edges": sum(1 for e in bm.edges if not e.is_manifold),
         "open_edges": sum(1 for e in bm.edges if e.is_boundary),
         "faces_through_each_other": inter,
         "degenerate_faces": sum(1 for f in bm.faces if f.calc_area() < 1e-7),
         "loose_verts": sum(1 for v in bm.verts if not v.link_faces),
         "concave_faces": sum(1 for f in bm.faces if concave(f)),
         "largest_face_verts": max(len(f.verts) for f in bm.faces),
         "uv_loops_outside_0_1": uv_out,
         "closed_solid": all(e.is_manifold for e in bm.edges)}
    bm.free()
    r["clean"] = (r["non_manifold_edges"] == 0 and r["open_edges"] == 0 and r["faces_through_each_other"] == 0
                  and r["degenerate_faces"] == 0 and r["loose_verts"] == 0 and r["uv_loops_outside_0_1"] == 0
                  and r["concave_faces"] == 0)
    CHECK[me.name] = r
    print("model: check %-22s %s" % (me.name, r))


# ---------------------------------------------------------------------------------------------------- textures
def bake_mat(src, img):
    m = bpy.data.materials.new(src.name + "_bake")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    base = src.get("tana_base", (0.085, 0.088, 0.092))
    if src.get("tana_glow"):
        em.inputs["Color"].default_value = (*base, 1.0)
    else:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value, noise.inputs["Detail"].default_value = 0.6, 6.0
        nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
        grime = nt.nodes.new("ShaderNodeMapRange")                 # +-6 % of the paint, never blotchy
        grime.inputs["From Min"].default_value, grime.inputs["From Max"].default_value = 0.3, 0.7
        grime.inputs["To Min"].default_value, grime.inputs["To Max"].default_value = 0.94, 1.06
        nt.links.new(noise.outputs["Fac"], grime.inputs["Value"])
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.only_local, ao.samples = True, 16
        ao.inputs["Distance"].default_value = 1.2
        shade = nt.nodes.new("ShaderNodeMapRange")                  # crevices to 55 %, open faces 100 %
        shade.inputs["To Min"].default_value, shade.inputs["To Max"].default_value = 0.55, 1.0
        nt.links.new(ao.outputs["AO"], shade.inputs["Value"])
        k = nt.nodes.new("ShaderNodeMath")
        k.operation = "MULTIPLY"
        nt.links.new(grime.outputs["Result"], k.inputs[0])
        nt.links.new(shade.outputs["Result"], k.inputs[1])
        col = nt.nodes.new("ShaderNodeMixRGB")
        col.blend_type, col.inputs["Fac"].default_value = "MULTIPLY", 1.0
        col.inputs["Color1"].default_value = (*base, 1.0)
        nt.links.new(k.outputs["Value"], col.inputs["Color2"])
        nt.links.new(col.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.select = True
    nt.nodes.active = tex
    return m


def final_mat(src, img, part):
    name = "TANA_%s_%s" % (part, src.name.replace("TANA_", ""))
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    sb = src.node_tree.nodes.get("Principled BSDF")
    for k in ("Metallic", "Roughness", "Emission", "Emission Strength"):
        b.inputs[k].default_value = sb.inputs[k].default_value
    t = nt.nodes.get("tana_tex") or nt.nodes.new("ShaderNodeTexImage")
    t.name, t.image = "tana_tex", img
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    return m


def bake(me, proto, part, size):
    img = bpy.data.images.new("T_TANA_%s_D" % part, size, size, alpha=False)
    srcs = [m or M_PAINT for m in me.materials]               # (a slot the boolean left empty: the paint)
    me.materials.clear()
    for s in srcs:
        me.materials.append(bake_mat(s, img))
    select_only(proto)
    sc = bpy.context.scene
    sc.render.engine, sc.cycles.device, sc.cycles.samples = "CYCLES", "CPU", 16
    bpy.ops.object.bake(type="EMIT", margin=8, use_clear=True)
    img.filepath_raw = os.path.join(TEX, "T_TANA_%s_D.png" % part)
    img.file_format = "PNG"
    img.save()
    finals = [final_mat(s, img, part) for s in srcs]
    for m in list(me.materials):
        bpy.data.materials.remove(m)
    me.materials.clear()
    for m in finals:
        me.materials.append(m)
    px = img.pixels[:]
    lum = [0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2] for i in range(0, len(px), 4 * 97)]
    CHECK.setdefault(me.name, {})["texture"] = {"file": os.path.basename(img.filepath_raw), "size": size,
                                               "luma_min": round(min(lum), 3), "luma_max": round(max(lum), 3)}
    print("model: baked %s (%d px), luma %.3f..%.3f" % (img.name, size, min(lum), max(lum)))


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
def laser_house():
    p = Part()
    p.cyl(2.7, 2.7, 0.9, Vector((0, 0, 0.45)), m=M_DARK)                           # the turret ring
    p.cyl(2.35, 2.35, 2.2, Vector((0, 0, 1.99)), seg=8)                            # the armoured housing
    p.cyl(2.35, 1.55, 0.8, Vector((0, 0, 3.49)), seg=8)                            # its chamfered roof
    p.box((0.9, 0.9, 0.55), Vector((-1.0, 0, 4.12)))                               # the tracker on the roof
    p.cyl(0.42, 0.42, 0.16, Vector((-1.0, 0.0, 4.46)), m=M_TEAL, seg=16)           # its sensor glass
    for s in (1, -1):                                                              # the cheeks the emitter rides in
        p.box((1.9, 0.38, 1.9), Vector((1.0, 1.32 * s, 3.05)))
    return p.solid("TANA_LASER_house")


LASER_PIVOT = Vector((1.0, 0, 3.05))
LASER_TIP = 4.85


def laser_gun():
    p = Part()                                                                     # along +X from the pitch pivot
    p.cyl(0.62, 0.62, 1.3, Vector((0.1, 0, 0)), axis="X", m=M_DARK, seg=16)        # the trunnion block
    p.cyl(0.52, 0.42, 4.2, Vector((2.4, 0, 0)), axis="X", seg=16)                  # the barrel
    for k in (1.6, 2.4, 3.2):                                                      # cooling rings
        p.cyl(0.62, 0.62, 0.16, Vector((k, 0, 0)), axis="X", m=M_DARK, seg=16)
    p.cyl(0.72, 0.72, 0.45, Vector((4.55, 0, 0)), axis="X", seg=16)                # the muzzle collar
    p.cyl(0.42, 0.42, 0.08, Vector((4.81, 0, 0)), axis="X", m=M_TEAL, seg=16)      # the lens
    return p.solid("TANA_LASER_gun", bevel=0.02)


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
    grid_body(p, sorted(xs), sorted(ys), kind, VLSD_TOP, 0.0)
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
VLSS_FACE = 0.06


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
    h = cast((x, y, 300.0), (0, 0, -1))
    return h[1].z if h else None


made = {"laser": [], "vlsd": [], "vlss": []}
hatches = {}
for tag, heading in (("FWD_L", 0.0), ("FWD_R", 0.0), ("AFT_L", math.pi), ("AFT_R", math.pi)):
    at = bpy.data.objects["LEV_LASER_%s" % tag].matrix_world.translation.copy()
    M = Matrix.Translation(at) @ Matrix.Rotation(heading, 4, "Z")
    house = copy_of("LASER_house", "TANA_LASER_%s_house" % tag, M, SHIP)
    gun = copy_of("LASER_gun", "TANA_LASER_%s_gun" % tag, M @ Matrix.Translation(LASER_PIVOT), house)
    empty("TANA_LASER_%s_SOC_Gun_01" % tag, M @ Matrix.Translation(LASER_PIVOT + Vector((LASER_TIP, 0, 0))), gun, 0.8, coll=ADD)
    made["laser"].append((house, gun))

n = 0
for x in (-210.0, -228.0, -246.0, -264.0):                    # behind turret C's barrels' sweep (to x -194)
    for y in (16.0, -16.0):
        n += 1
        M = Matrix.Translation((x, y, deck_z(x, y)))
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

LAUNCH_LOCAL = None
for side, s in (("L", 1), ("R", -1)):
    for i, x in enumerate((150.0, 172.0, 194.0, 216.0)):
        w = cast((x, 80.0 * s, 5.0), (0, -s, 0))[1]
        edge = deck_z(x, w.y - 1.2 * s)                            # the deck's edge here: the blocks follow the sheer
        hit = cast((x, 80.0 * s, edge - 4.6), (0, -s, 0))
        nrm = hit[2]                                               # flush with the skin, flare and all
        fwd = Vector((0, 0, 1)).cross(nrm).normalized()
        if fwd.x < 0:
            fwd = -fwd
        xa = fwd if s > 0 else -fwd                                # starboard: the same block turned 180 deg (+X aft)
        ya = nrm
        za = xa.cross(ya).normalized()
        xa = ya.cross(za).normalized()
        M = Matrix.Translation(hit[1]) @ Matrix((xa, ya, za)).transposed().to_4x4()
        body = copy_of("VLSS_body", "TANA_VLSS_%s%d" % (side, i + 1), M, SHIP)
        level_out = Vector((nrm.x, nrm.y, 0)).normalized()
        launch = (level_out * math.cos(SIDE_UP) + Vector((0, 0, 1)) * math.sin(SIDE_UP)).normalized()
        hs = []
        for k, (cx, cz) in enumerate(VLSS_CELLS, 1):
            hinge = Matrix.Translation((cx, VLSS_FACE + 0.01, cz + 0.98))
            h = copy_of("VLSS_hatch", "TANA_VLSS_%s%d_Hatch_%02d" % (side, i + 1, k), M @ hinge, body)
            hs.append((h, hinge))
            at = (M @ Vector((cx, VLSS_FACE - 0.2, cz)))
            empty("TANA_VLSS_%s%d_SOC_Vls_%02d" % (side, i + 1, k), frame(launch, Vector((0, 0, 1)), at), body, 0.6, coll=ADD)
        hatches[body.name] = ("vlss", hs)
        made["vlss"].append(body)


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
    hp = house.matrix_world.translation
    gv = [guns.matrix_world @ v.co for v in guns.data.vertices]
    c = sum(gv, Vector()) / len(gv)
    return math.atan2(c.y - hp.y, c.x - hp.x)


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
        {"hinge_cm": ue_cm(hinge.translation), "axis": axis, "open_deg": deg, "open_s": 0.5} for _, hinge in hs]})
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
    json.dump(CHECK, f, indent=1)
print("model: %d hull sockets; parts %s" % (len(sockets), parts))
print("model: every part clean: %s" % all(r.get("clean") for r in CHECK.values()))
for o in [h for h, _ in made["laser"]] + made["vlsd"] + made["vlss"]:
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


if RENDER:
    sc = bpy.context.scene
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
    ]
    only = os.environ.get("TANA_SHOTS")
    os.makedirs(os.path.join(OUT, "renders"), exist_ok=True)
    for tag, cam, opened in shots:
        if only and tag not in only.split(","):
            continue
        open_hatches(list(hatches), 0.0)
        open_hatches(opened, 1.0)
        sc.view_layers[0].material_override = wire_mat() if tag.endswith("_wire") else None
        sc.camera = cam
        sc.render.filepath = os.path.join(OUT, "renders", "tanacorn_%s.png" % tag)
        bpy.ops.render.render(write_still=True)
        print("model: rendered", sc.render.filepath)
    sc.view_layers[0].material_override = None
    open_hatches(list(hatches), 0.0)
