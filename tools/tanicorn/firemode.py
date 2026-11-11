"""firemode.py : Blender 3.3, the 16-inch triples' FIRE MODE, FIRST DRAFT (2026-11-11; the user asked for a higher-quality rebuild of
the mount and barrels themselves: this pass only cuts the Iowa's low-poly turret apart and adds boxes, and is not wired
into model_tanacorn.py) (the user, 2026-11-11: "Here's some ideas for the tanacorns
triple guns, we make them look normal, until they transform into fire mode"; their reference stills: a battleship's
turret whose armour opens off its sides, whose barrels split lengthwise into rails with a glow between them, and that
fires with green lightning and rings round the muzzles). The design here is the agent's own on those ideas.

Imported by model_tanacorn.py (after the hull sockets, before the save) and run on both turrets, LEV_T16_FWD / _AFT.
STOWED each is the Iowa turret exactly as it was (the user: "look normal"), but for a few dim teal running lights on
its face. FIRE MODE:
  armour   the house's forward side walls (each a loose plate in the Iowa's mesh, with the vent box on it) swing out
           ARMOR_SWING about their aft edge and slide ARMOR_SLIDE outward on two struts:
           TANA_T16_<tag>_Armor_L / _R, parented to the house, origin its joint (the aft edge's middle)
  banks    behind each plate a capacitor bank fills the opening (dark ribs over a lit teal face): TANA_T16_<tag>_bank,
           part of the house, hidden while the plates are shut
  barrels  each barrel forward of its breech rings (the Iowa models every barrel as two mirrored halves) splits along
           its vertical centre plane: TANA_T16_<tag>_Barrel_<n>_L / _R (n 1 port .. 3 starboard, L port), parented to
           the trunnion, slide BARREL_SLIDE apart and toe out BARREL_TOE, so the gap opens from ~0.8 m at the breech to
           ~1.9 m at the muzzle; each half is closed on its split face by a dark plate
  rails    in each half a rail bar, its inner face lit, slides RAIL_OUT forward out of the muzzle:
           TANA_T16_<tag>_Rail_<n>_L / _R, parented to its half. Stowed it is all inside the closed barrel
  lights   TANA_T16_<tag>_lights, part of the house: running lights on the face, dim stowed, bright in fire mode
The transform takes DEPLOY_S (2.5 s): the lights 0-25 %, armour 0-45 %, barrels 30-70 %, rails 60-100 %, the rails'
glow 70-100 % (STAGES); the stow is the same backwards. pose(t) poses it (t 0 stowed .. 1 fire mode); key() keys it
into the model's timeline (KEYS). The game plays it as two AnimSequences on their own skeletal meshes riding the
turret's bones (export_tanacorn.py: T16_ARMOR on turret_yaw, T16_GUNS on turret_pitch; docs/re/TANICORN.md 7).
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix

DEPLOY_S = 2.5
FPS = 30
ARMOR_SLIDE, ARMOR_SWING = 2.2, math.radians(18.0)
BARREL_SLIDE, BARREL_TOE = 0.40, math.radians(1.6)
RAIL_OUT = 6.0
STAGES = {"slit": (0.0, 0.25), "armor": (0.0, 0.45), "barrel": (0.30, 0.70), "rail": (0.60, 1.0), "glow": (0.70, 1.0)}
KEYS = ((110, 185), (226, 301))     # the model's 1-360 timeline (30 fps): deploy as the guns finish lifting, stow as
                                    # they come down (the design's keys: train 34-104, lift 94-129, lower 225-255)
SPLIT_X = 5.70                      # the barrels split forward of this, m ahead of the trunnion (the breech rings end
                                    # 5.73 m ahead of it; the middle segment starts there)
TURRETS = ("FWD", "AFT")


def smooth(t, a, b):
    f = min(1.0, max(0.0, (t - a) / (b - a)))
    return f * f * (3.0 - 2.0 * f)


def stage(t, key):
    return smooth(t, *STAGES[key])


# ---------------------------------------------------------------------------------------------------- materials
def _mat(name, rgb, metal, rough, emit, strength):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    b.inputs["Emission"].default_value = (*emit, 1.0)
    b.inputs["Emission Strength"].default_value = strength
    m["tana_base"] = list(rgb)
    m["tana_glow"] = True
    return m


GLOW = {   # name: (base colour, emission colour, strength stowed, strength in fire mode)
    "TANA_fm_bank": ((0.02, 0.30, 0.26), (0.05, 0.90, 0.72), 0.0, 5.0),
    "TANA_fm_rail": ((0.06, 0.42, 0.30), (0.20, 1.00, 0.42), 0.0, 5.0),
    "TANA_fm_slit": ((0.05, 0.42, 0.38), (0.10, 0.95, 0.85), 1.5, 9.0),
}


def materials():
    out = {k: _mat(k, v[0], 0.2, 0.3, v[1], v[2]) for k, v in GLOW.items()}
    out["dark"] = bpy.data.materials.get("TANA_dark") or _mat("TANA_dark", (0.026, 0.027, 0.029), 0.5, 0.48, (0, 0, 0), 0)
    out["paint"] = bpy.data.materials.get("TANA_paint") or _mat("TANA_paint", (0.085, 0.088, 0.092), 0.65, 0.34, (0, 0, 0), 0)
    return out


def glow(t):
    """the glow materials' emission strength at t (the lights, the banks as their armour opens, the rails)"""
    for name, (_, _, lo, hi) in GLOW.items():
        k = stage(t, {"TANA_fm_slit": "slit", "TANA_fm_bank": "armor", "TANA_fm_rail": "glow"}[name])
        bpy.data.materials[name].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = lo + (hi - lo) * k


# ---------------------------------------------------------------------------------------------------- mesh helpers
def islands(bm):
    bm.faces.ensure_lookup_table()
    seen, out = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        todo, comp = [f], []
        seen.add(f.index)
        while todo:
            a = todo.pop()
            comp.append(a)
            for v in a.verts:
                for b in v.link_faces:
                    if b.index not in seen:
                        seen.add(b.index)
                        todo.append(b)
        out.append(comp)
    return out


def bounds(points):
    return (Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points))),
            Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points))))


def take(src, faces, name, to_piece, coll):
    """a new object of `src`'s faces (indices), its vertices through to_piece (src local -> the piece's frame)"""
    me = src.data.copy()
    me.name = name
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    keep = set(faces)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.transform(bm, matrix=to_piece, verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def drop(src, faces):
    bm = bmesh.new()
    bm.from_mesh(src.data)
    bm.faces.ensure_lookup_table()
    gone = set(faces)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index in gone], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(src.data)
    bm.free()


def slot(ob, m):
    for i, s in enumerate(ob.material_slots):
        if s.material == m:
            return i
    ob.data.materials.append(m)
    return len(ob.data.materials) - 1


def add_box(bm, centre, axes, half, mi, mats_by_side=None):
    """a box: centre, three unit axes, half sizes; mats_by_side {(axis index, sign): material index} for some faces"""
    vs = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                vs.append(bm.verts.new(centre + axes[0] * half[0] * sx + axes[1] * half[1] * sy + axes[2] * half[2] * sz))
    idx = lambda sx, sy, sz: vs[(sx > 0) * 4 + (sy > 0) * 2 + (sz > 0)]
    quads = {(0, -1): [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)],
             (0, 1): [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)],
             (1, -1): [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)],
             (1, 1): [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)],
             (2, -1): [(-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)],
             (2, 1): [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]}
    for key, q in quads.items():
        f = bm.faces.new([idx(*c) for c in q])
        f.material_index = (mats_by_side or {}).get(key, mi)
    return vs


def finish_mesh(bm, ob):
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def box_uv(ob, size=2.0):
    """a simple box map for the new solids (their materials are flat colours; the export wants a map)"""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for p in me.polygons:
        n = p.normal
        a = max(range(3), key=lambda i: abs(n[i]))
        u, v = [(1, 2), (0, 2), (0, 1)][a]
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = (co[u] / size % 1.0, co[v] / size % 1.0)


def hull2d(pts):
    pts = sorted(set((round(p[0], 4), round(p[1], 4)) for p in pts))
    if len(pts) < 3:
        return pts
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def span_at(poly, u):
    """a convex polygon's v range on the line u"""
    vs = []
    for (u0, v0), (u1, v1) in zip(poly, poly[1:] + poly[:1]):
        if (u0 - u) * (u1 - u) <= 0 and u0 != u1:
            vs.append(v0 + (v1 - v0) * (u - u0) / (u1 - u0))
    return (min(vs), max(vs)) if vs else None


# ---------------------------------------------------------------------------------------------------- one turret
class Turret:
    """one 16-inch turret's fire-mode pieces: pose(t) moves them"""

    def __init__(self, tag, coll, log):
        self.tag = tag
        self.house = bpy.data.objects["LEV_T16_%s.001" % tag]
        self.trun = bpy.data.objects["LEV_G16_%s_trunnion" % tag]
        self.gun = bpy.data.objects["LEV_G16_%s.001" % tag]
        yaw = round(self.trun.rotation_euler.z / (math.pi / 2)) * (math.pi / 2)
        self.R = Matrix.Rotation(yaw, 4, "Z")              # the house's local frame -> the turret's (+x its guns' way)
        self.coll, self.log = coll, log
        self.armor, self.barrels, self.rails = {}, {}, {}
        self.rest = {}
        self.split_gun()
        self.split_house()

    # ---------------------------------------------------------------- the barrels
    def split_gun(self):
        G = self.gun
        bm = bmesh.new()
        bm.from_mesh(G.data)
        isl = islands(bm)
        moving = [c for c in isl if min(v.co.x for f in c for v in f.verts) >= SPLIT_X]
        tops = {}
        for c in moving:
            lo, hi = bounds([v.co for f in c for v in f.verts])
            tops.setdefault(round(lo.y, 3), []).append(("lo", lo, hi))
            tops.setdefault(round(hi.y, 3), []).append(("hi", lo, hi))
        centres = sorted((y for y, ends in tops.items() if {"lo", "hi"} <= {e[0] for e in ends}), reverse=True)
        assert len(centres) == 3, "%s: barrel centre planes %s (want 3)" % (self.tag, centres)
        allv = [v.co for c in moving for f in c for v in f.verts]
        lo, hi = bounds(allv)
        zc = (lo.z + hi.z) / 2.0
        muzzle = hi.x
        # the muzzle caps (and anything else across a centre plane) cut on it
        for c in moving:
            vs = [v.co for f in c for v in f.verts]
            l, h = bounds(vs)
            for yc in centres:
                if l.y < yc - 0.01 and h.y > yc + 0.01:
                    geom = list({e for f in c for e in f.edges}) + list({v for f in c for v in f.verts}) + list(c)
                    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=(0, yc, 0), plane_no=(0, 1, 0))
        bm.faces.ensure_lookup_table()
        bm.to_mesh(G.data)
        isl = islands(bm)
        move_faces = {f.index for c in isl if min(v.co.x for f in c for v in f.verts) >= SPLIT_X for f in c}
        groups = {}
        for i in move_faces:
            f = bm.faces[i]
            cc = f.calc_center_median()
            n = min(range(3), key=lambda k: abs(cc.y - centres[k]))
            s = "L" if cc.y > centres[n] else "R"
            groups.setdefault((n + 1, s), []).append(i)
        split_lo = min(v.co.x for i in move_faces for v in bm.faces[i].verts)
        bm.free()
        mats = materials()
        for (n, s), faces in sorted(groups.items()):
            yc = centres[n - 1]
            sg = 1.0 if s == "L" else -1.0
            J = Vector((split_lo, yc, zc))
            name = "TANA_T16_%s_Barrel_%d_%s" % (self.tag, n, s)
            ob = take(G, faces, name, Matrix.Translation(-J), self.coll)
            ob.parent = self.trun
            ob.matrix_parent_inverse = Matrix()
            ob.matrix_basis = G.matrix_basis @ Matrix.Translation(J)
            self.close_half(ob, sg, muzzle - split_lo, mats)
            self.barrels[(n, s)] = ob
            self.rest[ob.name] = ob.matrix_basis.copy()
            # the rail bar: from 0.8 m forward of the split to just inside the muzzle, its inner face lit
            r = bpy.data.objects.new("TANA_T16_%s_Rail_%d_%s" % (self.tag, n, s), bpy.data.meshes.new("TANA_T16_rail"))
            self.coll.objects.link(r)
            x0, x1 = 0.8, muzzle - split_lo - 0.2
            r.data.materials.append(mats["dark"])
            r.data.materials.append(mats["TANA_fm_rail"])
            rb = bmesh.new()
            add_box(rb, Vector(((x1 - x0) / 2.0, 0, 0)), (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))),
                    ((x1 - x0) / 2.0, 0.095, 0.33), 0, {(1, -1 if sg > 0 else 1): 1, (0, 1): 1})
            finish_mesh(rb, r)
            box_uv(r)
            r.parent = ob
            r.matrix_parent_inverse = Matrix()
            r.matrix_basis = Matrix.Translation((x0, sg * 0.13, 0.0))
            self.rails[(n, s)] = r
            self.rest[r.name] = r.matrix_basis.copy()
        drop(G, move_faces)
        self.cap_stays(centres, zc, split_lo, mats)
        self.muzzles = [Vector((muzzle, yc, zc)) for yc in centres]       # gun local (the trunnion's frame)
        self.split_at = split_lo
        self.log("firemode: %s barrels split at %.2f m ahead of the trunnion, centres y %s, axis z %.2f, muzzle %.2f m; "
                 "%d halves, %d faces" % (self.tag, split_lo, [round(c, 2) for c in centres], zc, muzzle, len(groups),
                                           len(move_faces)))

    def cap_stays(self, centres, zc, x, mats):
        """the breech rings' open fronts closed (the barrels' halves used to cover them)"""
        G = self.gun
        r = {}
        for v in G.data.vertices:
            if abs(v.co.x - x) < 0.02:
                k = min(range(3), key=lambda i: abs(v.co.y - centres[i]))
                r[k] = max(r.get(k, 0.0), math.hypot(v.co.y - centres[k], v.co.z - zc))
        bm = bmesh.new()
        bm.from_mesh(G.data)
        mi = slot(G, mats["dark"])
        for k, yc in enumerate(centres):
            ring = [bm.verts.new((x - 0.01, yc + r.get(k, 0.9) * 0.98 * math.cos(a), zc + r.get(k, 0.9) * 0.98 * math.sin(a)))
                    for a in [2 * math.pi * i / 16 for i in range(16)]]
            f = bm.faces.new(ring)
            f.material_index = mi
            f.normal_update()
            if f.normal.x < 0:
                f.normal_flip()
        bm.to_mesh(G.data)
        bm.free()
        G.data.update()

    def close_half(self, ob, sg, length, mats):
        """the half's open split face shut with a dark plate just inside it, following the half's own profile"""
        me = ob.data
        prof = {}
        for v in me.vertices:
            if abs(v.co.y) < 2e-3:
                k = round(v.co.x, 3)
                prof[k] = min(prof.get(k, 9.0), abs(v.co.z))
        xs = sorted(prof)
        assert len(xs) >= 2, "%s: no split face found" % ob.name
        bm = bmesh.new()
        bm.from_mesh(me)
        mi = slot(ob, mats["dark"])
        y = sg * 0.012
        prev = None
        for x in xs:
            r = prof[x] * 0.97
            top, bot = bm.verts.new((x, y, r)), bm.verts.new((x, y, -r))
            if prev:
                f = bm.faces.new([prev[1], bot, top, prev[0]] if sg > 0 else [prev[0], top, bot, prev[1]])
                f.material_index = mi
            prev = (top, bot)
        bm.to_mesh(me)
        bm.free()
        me.update()

    # ---------------------------------------------------------------- the house
    def split_house(self):
        H, R = self.house, self.R
        Ri = R.inverted()
        bm = bmesh.new()
        bm.from_mesh(H.data)
        mats = materials()
        isl = islands(bm)
        sides = {"L": [], "R": []}
        face = None
        for c in isl:
            lo, hi = bounds([Ri @ v.co for f in c for v in f.verts])
            if lo.x >= 3.6 and hi.x <= 14.6 and hi.z <= 6.7:
                if lo.y > 8.8:
                    sides["L"] += [f.index for f in c]
                elif hi.y < -8.8:
                    sides["R"] += [f.index for f in c]
                elif lo.x > 10.0 and hi.y - lo.y > 15.0 and len(c) > 8 and face is None:
                    face = c                                        # the sloped face the guns come through
        assert sides["L"] and sides["R"], "%s: side plates not found" % self.tag
        # the face's plane (turret frame), for the running lights
        fn = sum(((Ri.to_3x3() @ f.normal) * f.calc_area() for f in face), Vector()).normalized()
        fp = sum((Ri @ f.calc_center_median() for f in face), Vector()) / len(face)
        info = {}
        for s, faces in sides.items():
            sg = 1.0 if s == "L" else -1.0
            pts = [Ri @ v.co for i in faces for v in bm.faces[i].verts]
            lo, hi = bounds(pts)
            n = sum(((Ri.to_3x3() @ bm.faces[i].normal) * bm.faces[i].calc_area() for i in faces
                     if sg * (Ri.to_3x3() @ bm.faces[i].normal).y > 0.3), Vector()).normalized()
            aft = [p for p in pts if p.x < lo.x + 0.05]
            J = Vector((lo.x, sum(p.y for p in aft) / len(aft), sum(p.z for p in aft) / len(aft)))
            info[s] = (faces, pts, n, J)
        bm.free()
        for s, (faces, pts, n, J) in info.items():
            sg = 1.0 if s == "L" else -1.0
            name = "TANA_T16_%s_Armor_%s" % (self.tag, s)
            B = R @ Matrix.Translation(J)
            ob = take(H, faces, name, B.inverted(), self.coll)
            ob.parent = H
            ob.matrix_parent_inverse = Matrix()
            ob.matrix_basis = B
            self.back_skin(ob, mats)
            self.add_struts(ob, [p - J for p in pts], n, mats)
            self.armor[s] = (ob, Vector((n.x, n.y, 0.0)).normalized(), sg)
            ob["fm_slide_dir"] = list(self.armor[s][1])
            self.rest[ob.name] = B.copy()
        drop(H, [i for faces, _, _, _ in info.values() for i in faces])
        self.make_bank(info, mats)
        self.make_lights(fp, fn, info, mats)
        self.log("firemode: %s armour plates %d + %d faces, joints %s; face normal %s" % (
            self.tag, len(info["L"][0]), len(info["R"][0]),
            [tuple(round(c, 2) for c in info[s][3]) for s in "LR"], tuple(round(c, 2) for c in fn)))

    def back_skin(self, ob, mats):
        """the plate's inside: its faces again, flipped, 4 cm in (the Iowa's walls are one-sided: open, the game would
        show the bank through the plate's back)"""
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        mi = slot(ob, mats["dark"])
        bm.normal_update()
        for f in list(bm.faces):
            vs = [bm.verts.new(v.co - f.normal * 0.04) for v in reversed(f.verts)]
            g = bm.faces.new(vs)
            g.material_index = mi
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()

    def plane_axes(self, n):
        u = Vector((0, 0, 1)).cross(n).normalized()            # along the plate, level
        if u.x < 0:
            u = -u
        v = n.cross(u).normalized()                            # up the plate
        if v.z < 0:
            v = -v
        return u, v

    def add_struts(self, ob, pts, n, mats):
        """two struts on the plate's inside, back into the bank: they span the gap when it slides out"""
        c = sum(pts, Vector()) / len(pts)
        u, v = self.plane_axes(n)
        lo_u, hi_u = min((p - c).dot(u) for p in pts), max((p - c).dot(u) for p in pts)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        mi = slot(ob, mats["paint"])
        for k in (0.3, 0.62):
            pu = lo_u + (hi_u - lo_u) * k
            # long enough to stay in the bank at full travel: the slide, the swing at that distance from the hinge
            # (the origin), the bank's 0.42 m and a margin; shut, the rest of it is inside the house
            ln = ARMOR_SLIDE + (pu + c.dot(u)) * math.sin(ARMOR_SWING) + 0.42 + 0.6
            at = c + u * pu - v * 0.4 - n * (ln / 2.0 + 0.05)
            add_box(bm, at, (u, v, n), (0.2, 0.2, ln / 2.0), mi)
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()

    def make_bank(self, info, mats):
        """a capacitor bank behind each plate (in the house): its outer face lit teal under dark vertical ribs"""
        ob = bpy.data.objects.new("TANA_T16_%s_bank" % self.tag, bpy.data.meshes.new("TANA_T16_%s_bank" % self.tag))
        self.coll.objects.link(ob)
        ob.parent = self.house
        ob.matrix_parent_inverse = Matrix()
        ob.matrix_basis = self.R.copy()
        for k in ("dark", "TANA_fm_bank"):
            ob.data.materials.append(mats[k])
        bm = bmesh.new()
        for s, (faces, pts, n, J) in info.items():
            c = sum(pts, Vector()) / len(pts)
            u, v = self.plane_axes(n)
            poly = hull2d([((p - c).dot(u), (p - c).dot(v)) for p in pts])
            cu = sum(p[0] for p in poly) / len(poly)
            cv = sum(p[1] for p in poly) / len(poly)
            poly = [(cu + (a - cu) * 0.99, cv + (b - cv) * 0.99) for a, b in poly]
            # a jamb from just inside the plate (so nothing of the house's inside shows round it) down to the lit face
            # 0.42 m in; every face turned to be seen from the opening (the game draws one side)
            mid = c + u * cu + v * cv
            rim = [bm.verts.new(c + u * a + v * b - n * 0.05) for a, b in poly]
            outer = [bm.verts.new(c + u * a + v * b - n * 0.42) for a, b in poly]
            k0 = len(poly)
            for k in range(k0):
                f = bm.faces.new([rim[k], rim[(k + 1) % k0], outer[(k + 1) % k0], outer[k]])
                f.normal_update()
                if f.normal.dot(mid - n * 0.2 - f.calc_center_median()) < 0:
                    f.normal_flip()
            fo = bm.faces.new(outer)
            fo.material_index = 1
            fo.normal_update()
            if fo.normal.dot(n) < 0:
                fo.normal_flip()
            umin, umax = min(p[0] for p in poly), max(p[0] for p in poly)
            k = umin + 0.55
            while k < umax - 0.4:
                sp = span_at(poly, k)
                if sp and sp[1] - sp[0] > 0.8:
                    mid = c + u * k + v * ((sp[0] + sp[1]) / 2.0) - n * (0.42 - 0.13)
                    add_box(bm, mid, (u, v, n), (0.07, (sp[1] - sp[0]) / 2.0 - 0.18, 0.13), 0)
                k += 1.05
        bm.to_mesh(ob.data)
        bm.free()
        box_uv(ob)

    def make_lights(self, fp, fn, info, mats):
        """running lights: a slit under the face between the guns and outboard of them, and one on each plate"""
        ob = bpy.data.objects.new("TANA_T16_%s_lights" % self.tag, bpy.data.meshes.new("TANA_T16_%s_lights" % self.tag))
        self.coll.objects.link(ob)
        ob.parent = self.house
        ob.matrix_parent_inverse = Matrix()
        ob.matrix_basis = self.R.copy()
        ob.data.materials.append(materials()["TANA_fm_slit"])
        bm = bmesh.new()
        up = fn.cross(Vector((0, 1, 0))).normalized()
        if up.z < 0:
            up = -up
        # on the face: its plane through fp; z 2.3 m over the house's floor, between and outboard of the guns
        for y in (-8.0, -2.95, 2.95, 8.0):
            p = Vector((0.0, y, 2.3))
            p.x = fp.x - ((p.y - fp.y) * fn.y + (p.z - fp.z) * fn.z) / fn.x
            add_box(bm, p + fn * 0.03, (Vector((0, 1, 0)), up, fn), (0.55, 0.11, 0.03), 0)
        bm.to_mesh(ob.data)
        bm.free()
        box_uv(ob)
        # one on each plate (moves with it)
        for s, (faces, pts, n, J) in info.items():
            plate = bpy.data.objects["TANA_T16_%s_Armor_%s" % (self.tag, s)]
            mi = slot(plate, mats["TANA_fm_slit"])
            c = sum(pts, Vector()) / len(pts) - J
            u, v = self.plane_axes(n)
            pb = bmesh.new()
            pb.from_mesh(plate.data)
            add_box(pb, c + u * 1.2 + v * 1.3 + n * 0.03, (u, v, n), (0.6, 0.1, 0.03), mi)
            pb.to_mesh(plate.data)
            pb.free()

    # ---------------------------------------------------------------- the pose
    def pose(self, t):
        a, b, r = stage(t, "armor"), stage(t, "barrel"), stage(t, "rail")
        for s, (ob, nh, sg) in self.armor.items():
            ob.matrix_basis = self.rest[ob.name] @ Matrix.Translation(nh * ARMOR_SLIDE * a) @ \
                Matrix.Rotation(sg * ARMOR_SWING * a, 4, "Z")
        for (n, s), ob in self.barrels.items():
            sg = 1.0 if s == "L" else -1.0
            ob.matrix_basis = self.rest[ob.name] @ Matrix.Translation((0, sg * BARREL_SLIDE * b, 0)) @ \
                Matrix.Rotation(sg * BARREL_TOE * b, 4, "Z")
        for (n, s), ob in self.rails.items():
            ob.matrix_basis = self.rest[ob.name] @ Matrix.Translation((RAIL_OUT * r, 0, 0))

    def pieces(self):
        return [o for o, _, _ in self.armor.values()] + list(self.barrels.values()) + list(self.rails.values())


TURRET = {}


def attach(log=print):
    """the registry again from a saved model (its pieces' rest = their pose at frame 1, before KEYS' deploy)"""
    bpy.context.scene.frame_set(1)
    for tag in TURRETS:
        T = Turret.__new__(Turret)
        T.tag, T.log = tag, log
        T.house = bpy.data.objects["LEV_T16_%s.001" % tag]
        T.trun = bpy.data.objects["LEV_G16_%s_trunnion" % tag]
        T.gun = bpy.data.objects["LEV_G16_%s.001" % tag]
        T.armor = {s: (bpy.data.objects["TANA_T16_%s_Armor_%s" % (tag, s)],
                       Vector(bpy.data.objects["TANA_T16_%s_Armor_%s" % (tag, s)]["fm_slide_dir"]), 1.0 if s == "L" else -1.0)
                   for s in "LR"}
        T.barrels = {(n, s): bpy.data.objects["TANA_T16_%s_Barrel_%d_%s" % (tag, n, s)] for n in (1, 2, 3) for s in "LR"}
        T.rails = {(n, s): bpy.data.objects["TANA_T16_%s_Rail_%d_%s" % (tag, n, s)] for n in (1, 2, 3) for s in "LR"}
        T.rest = {o.name: o.matrix_basis.copy() for o in T.pieces()}
        TURRET[tag] = T
    return TURRET


def build(coll, log=print):
    """both turrets' fire-mode pieces (into `coll`); the house and gun meshes lose what moves"""
    for tag in TURRETS:
        TURRET[tag] = Turret(tag, coll, log)
    pose(0.0)
    return TURRET


def pose(t):
    for T in TURRET.values():
        T.pose(t)
    glow(t)


def key(log=print):
    """the transform keyed into the model's timeline: deploy at KEYS[0], stow at KEYS[1] (every second frame, linear)"""
    sc = bpy.context.scene
    n = 0
    for (f0, f1), up in zip(KEYS, (True, False)):
        for f in range(f0, f1 + 1, 2):
            t = (f - f0) / float(f1 - f0)
            pose(t if up else 1.0 - t)
            for T in TURRET.values():
                for ob in T.pieces():
                    ob.keyframe_insert("location", frame=f)
                    ob.keyframe_insert("rotation_euler", frame=f)
            for name in GLOW:
                b = bpy.data.materials[name].node_tree.nodes["Principled BSDF"]
                b.inputs["Emission Strength"].keyframe_insert("default_value", frame=f)
            n += 1
    for T in TURRET.values():
        for ob in T.pieces():
            for fc in ob.animation_data.action.fcurves:
                for k in fc.keyframe_points:
                    k.interpolation = "LINEAR"
    for name in GLOW:
        for fc in bpy.data.materials[name].node_tree.animation_data.action.fcurves:
            for k in fc.keyframe_points:
                k.interpolation = "LINEAR"
    sc.frame_set(1)
    log("firemode: keyed %d poses: deploy %d-%d, stow %d-%d (%.1f s each at %d fps)" % (
        n, KEYS[0][0], KEYS[0][1], KEYS[1][0], KEYS[1][1], (KEYS[0][1] - KEYS[0][0]) / FPS, FPS))
