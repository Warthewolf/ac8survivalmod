"""tanakit.py : Blender 3.3, the kit THE TANACORN's own parts are modelled with (split out of model_tanacorn.py on
2026-11-11 so firemode.py's turret uses the same, unchanged): its flat materials (mat, M_PAINT ...), Part (primitives
united into one closed solid by Blender's exact boolean, cutters carved out, what goes in after the cut, convex edges
bevelled), unwrap, check (tanacorn_model_check.json's rows) and bake (paint, a light grime noise and the part's own
ambient occlusion into an ordinary PNG, hard rule 44). The caller sets WORK (the prototypes' collection), TEX (the
textures' folder) and shares CHECK.
"""
import bpy, bmesh, os, math
from mathutils import Matrix
from mathutils.bvhtree import BVHTree

WORK = None                                          # set by the caller: where prototypes and boolean scratch go
TEX = None                                           # set by the caller: the baked textures' folder
CHECK = {}                                           # every part's check (the caller writes it out)

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
M_BLACK = mat("TANA_black", (0.018, 0.019, 0.021), 0.25, 0.55)           # the laser director's matte black (the user's photos)
M_GLASS = mat("TANA_glass", (0.010, 0.030, 0.034), 0.9, 0.06)            # its window and lenses: dark, glossy, a little teal


# ---------------------------------------------------------------------------------------------------- clean solids
class Part:
    """primitives (each with a material) united into one closed solid; cutters carved out of it"""
    def __init__(self):
        self.bm, self.cut, self.post, self.mats = bmesh.new(), bmesh.new(), bmesh.new(), []

    def _slot(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _put(self, bm, verts, m):
        i = self._slot(m)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = i

    def _bm(self, cut, post):
        return self.cut if cut else (self.post if post else self.bm)

    def box(self, size, at, m=M_PAINT, rot=Matrix(), cut=False, post=False):
        bm = self._bm(cut, post)
        r = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(at) @ rot.to_4x4() @ Matrix.Diagonal((*size, 1)))
        self._put(bm, r["verts"], m)

    def cyl(self, r1, r2, depth, at, axis="Z", m=M_PAINT, seg=24, cut=False, post=False):
        bm = self._bm(cut, post)
        R = {"Z": Matrix(), "X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Y": Matrix.Rotation(math.pi / 2, 4, "X")}[axis]
        r = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=depth,
                                  matrix=Matrix.Translation(at) @ R)
        self._put(bm, r["verts"], m)

    def prism(self, poly, axis, a0, a1, m=M_PAINT, cut=False, post=False):
        """a convex polygon (in the plane across `axis`: X -> (y, z), Y -> (x, z), Z -> (x, y)) extruded from a0 to a1;
        post: added after the cut (glass inside a recess)"""
        bm = self._bm(cut, post)

        def P(u, v, a):
            return {"X": (a, u, v), "Y": (u, a, v), "Z": (u, v, a)}[axis]
        lo = [bm.verts.new(P(u, v, a0)) for u, v in poly]
        hi = [bm.verts.new(P(u, v, a1)) for u, v in poly]
        bm.faces.new(lo[::-1])
        bm.faces.new(hi)
        n = len(poly)
        for i in range(n):
            bm.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
        bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if any(v in lo or v in hi for v in f.verts)])
        self._put(bm, lo + hi, m)

    def solid(self, name, bevel=0.03, simplify=True):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)      # every shell outward (the boolean needs it)
        bmesh.ops.recalc_face_normals(self.cut, faces=self.cut.faces)
        bmesh.ops.recalc_face_normals(self.post, faces=self.post.faces)
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
        poster = None
        if self.post.verts:                                          # what goes in after the cut (its own shells)
            pme = bpy.data.meshes.new(name + "_post")
            self.post.to_mesh(pme)
            for m in self.mats:
                pme.materials.append(m)
            poster = bpy.data.objects.new(name + "_poster", pme)
            WORK.objects.link(poster)
            q = tmp.modifiers.new("post", "BOOLEAN")
            q.operation, q.solver, q.object = "UNION", "EXACT", poster
            if hasattr(q, "material_mode"):
                q.material_mode = "TRANSFER"
        self.post.free()
        out = applied(tmp, name + "_solid")                          # 1. united and cut
        tmp.modifiers.clear()
        for o in (dummy, cutter, poster):
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
            e[bw] = 1.0 if (e.is_manifold and e.is_convex and e.calc_face_angle(0.0) > math.radians(30)
                            and e.calc_length() > 3 * (bevel or 0.03)) else 0.0   # (small holes' rims stay crisp)
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
            bm = bmesh.new()                                         # 4. the bevel's corner faces split convex,
            bm.from_mesh(out)                                        #    and no sliver left
            bmesh.ops.connect_verts_concave(bm, faces=bm.faces)
            fix_slivers(bm)
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


def fix_slivers(bm):
    """zero-length edges welded (only their own ends) and zero-area faces gone: each one's straight-through vertex
    dissolved, what that leaves concave split again; never a merge pass over the whole mesh (it ate the bevels)"""
    for _ in range(6):
        short = {v for e in bm.edges if e.calc_length() < 1e-5 for v in e.verts}
        if short:
            bmesh.ops.remove_doubles(bm, verts=list(short), dist=1e-5)
        bad = [f for f in bm.faces if f.calc_area() < 1e-7]
        if not bad:
            return
        flat = {max(f.loops, key=lambda lp: lp.calc_angle()).vert for f in bad}
        bmesh.ops.dissolve_verts(bm, verts=list(flat))
        bmesh.ops.connect_verts_concave(bm, faces=bm.faces)


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
