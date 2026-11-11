"""firemode.py : Blender 3.3, THE TANACORN's 16-inch triple turret, modelled again from scratch, and its FIRE MODE.

The user (2026-11-11): "Here's some ideas for the tanacorns triple guns, we make them look normal, until they transform
into fire mode", with stills of a battleship turret whose side armour opens, whose barrels split lengthwise into rails
with a glow between, and that fires with green lightning and rings; then, on a first pass that only cut the Iowa's
low-poly turret apart: "Edit the barrels and gun mount itself. Surely you can do a higher quality job than this". The
design here is the agent's own on those ideas (no other work's model or drawing is used).

Imported by model_tanacorn.py (tanakit.py's Part: every piece one closed, bevelled solid, unwrapped and baked like the
ship's other new parts), and run on both turrets, LEV_T16_FWD (B) and LEV_T16_AFT (C). It REPLACES the Iowa's mount: the
house object (LEV_T16_<tag>.001) gets the new house, the gun object (LEV_G16_<tag>.001) the guns' fixed parts, and the
trunnion (LEV_G16_<tag>_trunnion) moves back to 1.2 m behind the face, as on a real turret (the muzzles stay where the
design had them). Same outline, size and pivots as the design's turret, so the ship, its sockets and the deploy
sequence are unchanged.

STOWED it is a battleship turret (the user: "look normal"): an armoured house with a skirt, a raised roof plate, sighting
hoods, hatches, vents and rangefinder ears, three guns in drum mantlets set in wells in the sloped face, long tapered
barrels with bands and a muzzle swell; a few dim teal running lights.
FIRE MODE (DEPLOY_S, 2.5 s; STAGES):
  armour   TANA_T16_<tag>_Armor_L / _R: the forward side walls are armour slabs hinged along their top edge that swing
           PLATE_OPEN up and out (gull wings), uncovering a bay of glowing coil stacks in the house
  roof     TANA_T16_<tag>_Vent_L / _R: the roof's rear splits down the middle, each half hinged at its outer edge and
           lifting VENT_OPEN, over glowing heat-sink fins
  barrels  TANA_T16_<tag>_Barrel_<n>_L / _R (n 1 port .. 3 starboard; L port): each barrel forward of its root is two
           half solids, their split faces carrying a glowing bore and two glowing rail channels; they slide apart and
           toe out (BARREL_SLIDE, BARREL_TOE)
  chases   TANA_T16_<tag>_Chase_<n>_L / _R, on their halves: the barrel's chase telescopes CHASE_OUT forward off a
           glowing coil sleeve, so the open fork is longer than the gun was
  glow     the bays, fins and coils (TANA_*fm_bank), the bores and rails (fm_rail), the running lights (fm_slit)
pose(t) poses it (t 0 stowed .. 1 fire mode), key() keys it into the model's timeline (KEYS), attach() finds it again
in a saved model. The game plays the transform as two AnimSequences on skeletal meshes riding the turret's bones
(export_tanacorn.py: T16_ARMOR on turret_yaw, T16_GUNS on turret_pitch; docs/re/TANICORN.md 7).
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix
import tanakit
from tanakit import Part, M_PAINT, M_DARK, M_GLASS

DEPLOY_S, FPS = 2.5, 30
PLATE_OPEN = math.radians(50.0)          # the side armour's swing up and out about its top edge
VENT_OPEN = math.radians(58.0)
BARREL_SLIDE, BARREL_TOE = 0.42, math.radians(1.5)
CHASE_OUT = 3.6
STAGES = {"slit": (0.0, 0.2), "plate": (0.0, 0.4), "vent": (0.1, 0.45), "barrel": (0.3, 0.65), "chase": (0.55, 0.9),
          "glow": (0.65, 1.0)}
KEYS = ((110, 185), (226, 301))           # the model's 1-360 timeline (30 fps): deploy as the guns finish lifting
                                          # (the design: train 34-104, lift 94-129), stow as they come down (225-255)
TURRETS = ("FWD", "AFT")

# ---------------------------------------------------------------------------------------------------- measures
# The turret's frame: x its guns' way, z up, the origin the house object's (the yaw pivot); the guns' frame: the
# trunnion's. Lengths in m. The outline is the design's (the Iowa's at the Leviathan's scale): port halves from the
# rear's middle round to the face's middle, v off the turret's centre line.
Z0, Z1 = 0.61, 6.52                       # the house's floor and roof
HALF_B = [(-15.05, 0.0), (-14.8, 3.1), (-14.3, 6.6), (-13.75, 9.3), (3.3, 11.75), (12.9, 9.55), (14.4, 8.3), (14.4, 0.0)]
HALF_T = [(-14.95, 0.0), (-14.7, 2.9), (-14.2, 6.2), (-13.65, 8.75), (3.6, 10.75), (9.55, None), (10.3, None), (10.3, 0.0)]
FACE_X0, FACE_K = 14.4, 4.1 / 5.91        # the face: x = FACE_X0 - (z - Z0) * FACE_K (35 deg back)
GUN_Y = (5.89, 0.0, -5.89)                # each gun's axis off the trunnion's (port first: SOC_Gun_01..03)
BEHIND_FACE = 1.2                         # the trunnion this far behind the face
DRUM_R, DRUM_W = 1.75, 2.9
SPLIT, CHASE, MUZZLE = 6.6, 16.1, 26.9    # where the halves start, the chase starts, the muzzle (from the trunnion)
BORE = 0.37
SEG = 40                                  # a barrel's sides round
# the barrel's outside: (x0, x1, r0, r1) cones, from the trunnion
ROOT = [(1.45, 2.67, 1.24, 1.17), (2.65, 6.6, 1.10, 1.04), (5.0, 5.3, 1.15, 1.15)]
MID = [(6.6, 6.92, 1.04, 1.04), (6.9, 15.82, 0.97, 0.87), (11.2, 11.45, 0.93, 0.93), (15.8, 16.1, 0.91, 0.91)]
SLEEVE = (15.5, 20.9, 0.77)
CHASE_P = [(16.1, 16.37, 0.89, 0.89), (16.35, 25.62, 0.83, 0.74), (25.6, 26.52, 0.74, 0.82), (26.5, 26.9, 0.82, 0.79)]


def smooth(t, a, b):
    f = min(1.0, max(0.0, (t - a) / (b - a)))
    return f * f * (3.0 - 2.0 * f)


def stage(t, key):
    return smooth(t, *STAGES[key])


# ---------------------------------------------------------------------------------------------------- materials
GLOW = {   # key: (base colour, emission colour, strength stowed, strength in fire mode, the stage that drives it)
    "fm_bank": ((0.015, 0.11, 0.10), (0.05, 0.90, 0.72), 0.0, 5.0, "plate"),
    "fm_rail": ((0.015, 0.07, 0.05), (0.25, 1.00, 0.45), 0.0, 3.5, "glow"),
    "fm_slit": ((0.06, 0.40, 0.36), (0.20, 0.95, 0.88), 1.2, 8.0, "slit"),
}
MAT = {}
for _k, (_base, _emit, _lo, _hi, _st) in GLOW.items():
    MAT[_k] = tanakit.mat("TANA_" + _k, _base, 0.2, 0.3, _emit, _lo)
    MAT[_k]["tana_glow"] = True


def glow(t):
    """every glow material's strength at t (the baked parts' copies too: TANA_<part>_fm_*)"""
    for m in bpy.data.materials:
        for k, (_, _, lo, hi, st) in GLOW.items():
            if m.name.endswith(k) and m.use_nodes and m.node_tree.nodes.get("Principled BSDF"):
                m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = lo + (hi - lo) * stage(t, st)


# ---------------------------------------------------------------------------------------------------- primitives
def cyl(part, r1, r2, depth, centre, axis, m, seg=48, cut=False, post=False):
    """a cone along `axis` (r1 at its back end), centred"""
    bm = part._bm(cut, post)
    q = Vector((0, 0, 1)).rotation_difference(Vector(axis).normalized())
    r = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=depth,
                              matrix=Matrix.Translation(centre) @ q.to_matrix().to_4x4())
    part._put(bm, r["verts"], m)


def cone_x(part, x0, x1, r0, r1, y, z, m, seg=48, cut=False, post=False):
    cyl(part, r0, r1, x1 - x0, Vector(((x0 + x1) / 2.0, y, z)), (1, 0, 0), m, seg, cut, post)


def box(part, centre, axes, size, m, cut=False, post=False):
    """a box: centre, three unit axes (a right-handed frame), full sizes along them"""
    bm = part._bm(cut, post)
    R = Matrix((axes[0], axes[1], axes[2])).transposed().to_4x4()
    r = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(centre) @ R @ Matrix.Diagonal((*size, 1.0)))
    part._put(bm, r["verts"], m)


XYZ = (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))


def abox(part, lo, hi, m, cut=False, post=False):
    lo, hi = Vector(lo), Vector(hi)
    box(part, (lo + hi) / 2.0, XYZ, hi - lo, m, cut, post)


def poly_prism(part, outline, n, a0, a1, m, cut=False, post=False):
    """a flat convex outline (3D points) swept along n from a0 to a1"""
    bm = part._bm(cut, post)
    lo = [bm.verts.new(p + n * a0) for p in outline]
    hi = [bm.verts.new(p + n * a1) for p in outline]
    fs = [bm.faces.new(lo[::-1]), bm.faces.new(hi)]
    k = len(outline)
    for i in range(k):
        fs.append(bm.faces.new((lo[i], lo[(i + 1) % k], hi[(i + 1) % k], hi[i])))
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    part._put(bm, lo + hi, m)


def loft(part, polyB, zB, polyT, zT, m):
    """a solid between two convex polygons with as many corners (x, y), at zB and zT"""
    bm = part.bm
    lo = [bm.verts.new((x, y, zB)) for x, y in polyB]
    hi = [bm.verts.new((x, y, zT)) for x, y in polyT]
    fs = [bm.faces.new(lo[::-1]), bm.faces.new(hi)]
    k = len(polyB)
    for i in range(k):
        fs.append(bm.faces.new((lo[i], lo[(i + 1) % k], hi[(i + 1) % k], hi[i])))
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    part._put(bm, lo + hi, m)


def offset2d(poly, d):
    """a convex polygon's edges moved d outward (negative: in), corners where they meet again (straight-through
    corners dropped first: two parallel edges never meet)"""
    keep = []
    for i in range(len(poly)):
        (ax, ay), (bx, by), (cx, cy) = poly[i - 1], poly[i], poly[(i + 1) % len(poly)]
        if abs((bx - ax) * (cy - by) - (by - ay) * (cx - bx)) > 1e-9:
            keep.append(poly[i])
    poly = keep
    k = len(poly)
    area = sum(poly[i][0] * poly[(i + 1) % k][1] - poly[(i + 1) % k][0] * poly[i][1] for i in range(k))
    s = 1.0 if area > 0 else -1.0                  # counter-clockwise: the outward normal of a->b is (dy, -dx)
    lines = []
    for i in range(k):
        (ax, ay), (bx, by) = poly[i], poly[(i + 1) % k]
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy)
        nx, ny = s * dy / L, -s * dx / L
        lines.append(((ax + nx * d, ay + ny * d), (dx, dy)))
    out = []
    for i in range(k):
        (p, u), (q, w) = lines[i - 1], lines[i]
        den = u[0] * w[1] - u[1] * w[0]
        t = ((q[0] - p[0]) * w[1] - (q[1] - p[1]) * w[0]) / den
        out.append((p[0] + u[0] * t, p[1] + u[1] * t))
    return out


def full(half, y0):
    """a port half outline (rear middle .. face middle) mirrored about the centre line y0"""
    return [(x, y0 + v) for x, v in half] + [(x, y0 - v) for x, v in reversed(half[1:-1])]


# ---------------------------------------------------------------------------------------------------- the house
class Measures:
    """the outline completed (the walls flat), the face's frame, the guns' places, each side wall's armour"""

    def __init__(self, y0, zt):
        self.y0, self.zt = y0, zt
        B, T = [list(p) for p in HALF_B], [list(p) for p in HALF_T]
        P = lambda q, z: Vector((q[0], q[1], z))
        # the forward side wall flat: T[5] on the plane of B[4], B[5], T[4]; the front chamfer flat: T[6] on B[5], B[6], T[5]
        for i, (a, b, c) in ((5, (4, 5, 4)), (6, (5, 6, 5))):
            pa, pb, pc = P(B[a], Z0), P(B[b], Z0), P(T[c], Z1)
            n = (pb - pa).cross(pc - pa)
            T[i][1] = pa.y - (n.x * (T[i][0] - pa.x) + n.z * (Z1 - Z0)) / n.y
        self.B, self.T = [tuple(p) for p in B], [tuple(p) for p in T]
        self.fn = Vector((5.91, 0.0, 4.1)).normalized()             # the face's outward normal
        self.fup = Vector((-4.1, 0.0, 5.91)).normalized()           # up the face
        self.f0 = Vector((FACE_X0, y0, Z0))
        xt = FACE_X0 - (zt - Z0) * FACE_K - BEHIND_FACE
        self.trun = Vector((xt, y0, zt))                            # the trunnion, turret frame
        self.walls = {s: self.wall(s) for s in "LR"}

    def on_face(self, v, h):
        return self.f0 + Vector((0, v, 0)) + self.fup * h

    def wall(self, s):
        """a side wall's armour slab: its outline (4 points on the wall), outward normal, along / up axes"""
        sg = 1.0 if s == "L" else -1.0
        P = lambda q, z: Vector((q[0], self.y0 + sg * q[1], z))
        b4, b5, t4, t5 = P(self.B[4], Z0), P(self.B[5], Z0), P(self.T[4], Z1), P(self.T[5], Z1)
        n = (b5 - b4).cross(t4 - b4).normalized()
        if n.y * sg < 0:
            n = -n

        def at(z, back, front):
            k = (z - Z0) / (Z1 - Z0)
            a, f = b4.lerp(t4, k), b5.lerp(t5, k)
            d = (f - a).normalized()
            return a + d * back, f - d * front
        za, zb = Z0 + 0.5, Z1 - 0.45
        a0, f0 = at(za, 0.55, 0.6)
        a1, f1 = at(zb, 0.55, 0.6)
        outline = [a0, f0, f1, a1]
        along = (f0 - a0).normalized()
        up = n.cross(along).normalized() if sg > 0 else along.cross(n).normalized()
        if up.z < 0:
            up = -up
        return {"outline": outline, "n": n, "along": along, "up": up, "sg": sg,
                "centre": sum(outline, Vector()) / 4.0}


def inset_outline(w, d):
    """a wall outline moved d in along its own plane (the slab's gap round it)"""
    c = w["centre"]
    u, v = w["along"], w["up"]
    flat = [((p - c).dot(u), (p - c).dot(v)) for p in w["outline"]]
    return [c + u * a + v * b for a, b in offset2d(flat, -d)]


def house_part(M):
    p = Part(overlap=True)
    y0 = M.y0
    loft(p, full(M.B, y0), Z0, full(M.T, y0), Z1, M_PAINT)                         # the house
    p.prism(offset2d(full(M.B, y0), 0.22), "Z", 0.0, Z0 + 0.28)                     # its skirt on the barbette
    p.prism(offset2d(full(M.T, y0), -0.55), "Z", Z1 - 0.1, Z1 + 0.13)             # the raised roof plate
    # the face: a well round each gun's drum, a seam across it above the guns, a running light under each well
    for v in GUN_Y:
        c = Vector((M.trun.x, y0 + v, M.trun.z))
        h = (c - M.f0).dot(M.fup)
        box(p, M.on_face(v, h) - M.fn * 0.25, (M.fn, XYZ[1], M.fup), (1.1, DRUM_W + 0.5, 2 * DRUM_R + 0.55), M_DARK, cut=True)
        box(p, M.on_face(v, h - DRUM_R - 0.62) + M.fn * 0.015, (M.fn, XYZ[1], M.fup), (0.06, 1.25, 0.17), MAT["fm_slit"],
            post=True)
    box(p, M.on_face(0.0, (5.55 - Z0) / M.fup.z), (M.fn, XYZ[1], M.fup), (0.09, 2 * 8.2, 0.07), M_DARK, cut=True)
    for v in (-8.0, 8.0):
        box(p, M.on_face(v, 1.0) + M.fn * 0.015, (M.fn, XYZ[1], M.fup), (0.06, 0.7, 0.14), MAT["fm_slit"], post=True)
    # the roof: sighting hoods at the front corners, two crew hatches, mushroom vents at the back
    for sg in (1.0, -1.0):
        hood = [(5.0, Z1 + 0.05), (8.4, Z1 + 0.05), (7.7, Z1 + 1.0), (5.4, Z1 + 1.0)]
        a, b = sorted((y0 + sg * 5.9, y0 + sg * 7.5))
        p.prism(hood, "Y", a, b)
        box(p, Vector((8.05 + 0.02, (a + b) / 2.0, Z1 + 0.55)), (Vector((0.805, 0, 0.593)), XYZ[1], Vector((-0.593, 0, 0.805))),
            (0.06, 1.1, 0.22), M_GLASS, post=True)
        cyl(p, 0.78, 0.74, 0.22, Vector((-3.0, y0 + sg * 3.4, Z1 + 0.2)), (0, 0, 1), M_PAINT, 32)
        cyl(p, 0.42, 0.42, 0.16, Vector((-3.0, y0 + sg * 3.4, Z1 + 0.36)), (0, 0, 1), M_PAINT, 24)
        abox(p, (-3.95, y0 + sg * 3.4 - 0.25, Z1 + 0.1), (-3.65, y0 + sg * 3.4 + 0.25, Z1 + 0.38), M_PAINT)
        cyl(p, 0.3, 0.3, 0.7, Vector((-12.6, y0 + sg * 5.2, Z1 + 0.4)), (0, 0, 1), M_PAINT, 24)
        cyl(p, 0.58, 0.5, 0.2, Vector((-12.6, y0 + sg * 5.2, Z1 + 0.82)), (0, 0, 1), M_PAINT, 24)
        # the rangefinder ears at the back's sides, a lens in each end
        oc = [(-12.9, 4.25), (-12.3, 3.55), (-8.9, 3.55), (-8.3, 4.25), (-8.3, 5.25), (-8.9, 5.95), (-12.3, 5.95), (-12.9, 5.25)]
        a, b = sorted((y0 + sg * 8.4, y0 + sg * 14.25))
        p.prism(oc, "Y", a, b)
        cyl(p, 0.62, 0.62, 0.3, Vector((-10.6, y0 + sg * 14.25, 4.75)), (0, 1, 0), M_DARK, 32, cut=True)
        cyl(p, 0.56, 0.56, 0.08, Vector((-10.6, y0 + sg * 14.12, 4.75)), (0, 1, 0), M_GLASS, 32, post=True)
    # FIRE MODE's bays: the roof's rear opens over heat-sink fins on a glowing floor
    rx0, rx1, rv = -11.2, -3.6, 6.65
    abox(p, (rx0, y0 - rv, Z1 - 0.95), (rx1, y0 + rv, Z1 + 0.6), M_DARK, cut=True)
    abox(p, (rx0 + 0.02, y0 - rv + 0.02, Z1 - 0.95), (rx1 - 0.02, y0 + rv - 0.02, Z1 - 0.88), MAT["fm_bank"], post=True)
    x = rx0 + 0.45
    while x < rx1 - 0.3:
        abox(p, (x - 0.07, y0 - rv + 0.05, Z1 - 0.9), (x + 0.07, y0 + rv - 0.05, Z1 - 0.32), M_DARK, post=True)
        x += 0.55
    # ... and each side wall's armour comes off a bay of coil stacks (the slab itself is its own part)
    for s, w in M.walls.items():
        n, u, v = w["n"], w["along"], w["up"]
        poly_prism(p, w["outline"], n, -1.15, 0.6, M_DARK, cut=True)
        poly_prism(p, inset_outline(w, 0.08), n, -1.15, -1.09, MAT["fm_bank"], post=True)
        pts = flat(w)
        k = min(q[0] for q in pts) + 0.6
        while k <= max(q[0] for q in pts) - 0.4:
            hr = h_range(w, k - 0.3), h_range(w, k + 0.3)
            if None in hr:
                k += 0.95
                continue
            h0, h1 = max(hr[0][0], hr[1][0]) + 0.3, min(hr[0][1], hr[1][1]) - 0.3
            if h1 - h0 > 1.0:
                c = w["centre"] + u * k + v * ((h0 + h1) / 2.0) - n * 0.78
                cyl(p, 0.2, 0.2, h1 - h0, c, v, MAT["fm_bank"], 12, post=True)
                hh = h0 + 0.1
                while hh <= h1 - 0.05:
                    cyl(p, 0.28, 0.28, 0.1, w["centre"] + u * k + v * hh - n * 0.78, v, M_DARK, 12, post=True)
                    hh += 0.5
            k += 0.95
    return p


def flat(w):
    c, u, v = w["centre"], w["along"], w["up"]
    return [((q - c).dot(u), (q - c).dot(v)) for q in w["outline"]]


def h_range(w, k):
    """the wall outline's extent up the wall at k along it"""
    pts = flat(w)
    hs = []
    for (u0, v0), (u1, v1) in zip(pts, pts[1:] + pts[:1]):
        if (u0 - k) * (u1 - k) <= 0 and u0 != u1:
            hs.append(v0 + (v1 - v0) * (k - u0) / (u1 - u0))
    return (min(hs), max(hs)) if hs else None


def u_range(w, h):
    """... and along it at h up it"""
    pts = flat(w)
    us = []
    for (u0, v0), (u1, v1) in zip(pts, pts[1:] + pts[:1]):
        if (v0 - h) * (v1 - h) <= 0 and v0 != v1:
            us.append(u0 + (u1 - u0) * (h - v0) / (v1 - v0))
    return (min(us), max(us)) if us else None


def hinge_of(w):
    """the slab's hinge: the middle of its outline's top edge, on the wall"""
    return (w["outline"][2] + w["outline"][3]) / 2.0


def plate_part(M, s):
    """a side wall's armour slab, flush with the wall, hinged along its top edge (in the turret's frame)"""
    w = M.walls[s]
    p = Part(overlap=True)
    n, u, v = w["n"], w["along"], w["up"]
    poly_prism(p, inset_outline(w, 0.05), n, -0.42, 0.0, M_PAINT)
    # a raised rib along its upper third, a running light at the rib's front end
    pts = flat(w)
    hb = min(q[1] for q in pts) + (max(q[1] for q in pts) - min(q[1] for q in pts)) * 0.68
    lo, hi = u_range(w, hb + 0.3)
    lo, hi = lo + 0.45, hi - 0.45
    poly_prism(p, [w["centre"] + u * a + v * b for a, b in ((lo, hb), (hi - 1.3, hb), (hi - 1.3, hb + 0.25), (lo, hb + 0.25))],
               n, -0.05, 0.07, M_PAINT)
    box(p, w["centre"] + u * (hi - 0.6) + v * (hb + 0.125) + n * 0.02, (u, v, n), (0.9, 0.14, 0.06), MAT["fm_slit"], post=True)
    # its hinge knuckles on the top edge, and stiffeners on its inside (seen once it's up)
    hj = hinge_of(w)
    top = u_range(w, max(q[1] for q in pts) - 0.05)
    for f in (0.15, 0.5, 0.85):
        cyl(p, 0.17, 0.17, 0.7, hj + u * ((top[0] + top[1]) / 2.0 - (hj - w["centre"]).dot(u) + (top[1] - top[0]) * (f - 0.5) * 0.9),
            u, M_PAINT, 16)
    h0, h1 = min(q[1] for q in pts) + 0.35, max(q[1] for q in pts) - 0.35
    for f in (0.3, 0.68):
        lo, hi = u_range(w, (h0 + h1) / 2.0)
        k = lo + (hi - lo) * f
        hr = h_range(w, k)
        box(p, w["centre"] + u * k + v * ((hr[0] + hr[1]) / 2.0) - n * 0.44, (u, v, n), (0.26, hr[1] - hr[0] - 0.7, 0.16), M_PAINT)
    # (the stiffeners sunk well into the slab: a hair's overlap left an edge four faces shared; a rib across them made
    # the bevel run into itself)
    return p


def vent_part(M, sg):
    """one half of the roof's rear (port sg 1): a slab hinged at its outer edge"""
    p = Part(overlap=True)
    y0 = M.y0
    rx0, rx1, rv = -11.2, -3.6, 6.65
    a, b = sorted((y0 + sg * 0.03, y0 + sg * (rv - 0.04)))
    abox(p, (rx0 + 0.04, a, Z1 + 0.13 - 0.26), (rx1 - 0.04, b, Z1 + 0.13), M_PAINT)
    for x in (rx0 + 1.3, (rx0 + rx1) / 2.0, rx1 - 1.3):                         # its hinge knuckles
        cyl(p, 0.19, 0.19, 0.9, Vector((x, y0 + sg * (rv - 0.12), Z1 + 0.06)), (1, 0, 0), M_PAINT, 20)
    abox(p, (rx0 + 0.6, min(y0 + sg * 1.2, y0 + sg * 5.4), Z1 + 0.1), (rx1 - 0.6, max(y0 + sg * 1.2, y0 + sg * 5.4), Z1 + 0.2),
         M_PAINT)
    for x in (rx0 + 1.6, (rx0 + rx1) / 2.0, rx1 - 1.6):                       # stiffeners underneath (over the fins)
        a, b = sorted((y0 + sg * 0.4, y0 + sg * (rv - 0.4)))
        abox(p, (x - 0.12, a, Z1 - 0.2), (x + 0.12, b, Z1 - 0.1), M_PAINT)
    return p


# ---------------------------------------------------------------------------------------------------- the guns
def stays_part():
    """what doesn't split: each gun's drum mantlet and its barrel's root (the guns' frame)"""
    p = Part(overlap=True)
    for yc in GUN_Y:
        cyl(p, DRUM_R, DRUM_R, DRUM_W, Vector((0, yc, 0)), (0, 1, 0), M_PAINT, SEG)
        for e in (-1.0, 1.0):
            cyl(p, DRUM_R + 0.06, DRUM_R + 0.06, 0.22, Vector((0, yc + e * (DRUM_W / 2 - 0.25), 0)), (0, 1, 0), M_PAINT, SEG)
        for x0, x1, r0, r1 in ROOT:
            cone_x(p, x0, x1, r0, r1, yc, 0.0, M_PAINT, SEG)
        cone_x(p, SPLIT - 0.25, SPLIT + 0.05, BORE + 0.02, BORE + 0.02, yc, 0.0, MAT["fm_rail"], 32, cut=True)
    return p


def half_part(kind, sg):
    """one half (port sg 1) of a barrel's middle (with its coil sleeve) or its chase, in its own frame: x from the
    half's back on the barrel's axis, the split face y = 0"""
    p = Part(overlap=True)
    x0 = SPLIT if kind == "mid" else CHASE
    cones = MID if kind == "mid" else CHASE_P
    for a, b, r0, r1 in cones:
        cone_x(p, a - x0, b - x0, r0, r1, 0.0, 0.0, M_PAINT, SEG)
    end = (cones[-1][1] if kind == "chase" else SLEEVE[1]) - x0
    if kind == "mid":
        cone_x(p, SLEEVE[0] - x0, SLEEVE[1] - x0, SLEEVE[2], SLEEVE[2], 0.0, 0.0, M_DARK, SEG)
        x = 16.5
        while x < 20.5:                                                # the sleeve's coils, glowing
            cone_x(p, x - x0, x + 0.2 - x0, SLEEVE[2] + 0.006, SLEEVE[2] + 0.006, 0.0, 0.0, MAT["fm_rail"], SEG, post=True)
            x += 0.62
    # the other half cut away (its face dark steel), the bore (lit) through, two rail channels and the coil grooves
    if sg > 0:
        abox(p, (-1.3, -4.5, -2.0), (end + 1.3, 0.0, 2.0), M_DARK, cut=True)
    else:
        abox(p, (-1.3, 0.0, -2.0), (end + 1.3, 4.5, 2.0), M_DARK, cut=True)
    cone_x(p, -0.9, end + 0.9, BORE, BORE, 0.0, 0.0, MAT["fm_rail"], SEG, cut=True)
    c0, c1 = 0.35, (cones[-1][1] - x0) - 0.45 if kind == "chase" else end - 0.3
    for z in (0.58, -0.58):
        a, b = sorted((-sg * 0.05, sg * 0.1))
        abox(p, (c0, a, z - 0.085), (c1, b, z + 0.085), M_DARK, cut=True)
        a, b = sorted((sg * 0.06, sg * 0.1))
        abox(p, (c0 + 0.02, a, z - 0.06), (c1 - 0.02, b, z + 0.06), MAT["fm_rail"], post=True)
    x = 1.0
    while x < c1 - 0.3:
        r = radius_at(kind, x + x0) - 0.1
        a, b = sorted((sg * 0.05, -sg * 0.05))
        abox(p, (x - 0.05, a, -r), (x + 0.05, b, r), M_DARK, cut=True)
        x += 1.55
    return p


def radius_at(kind, x):
    rr = []
    for a, b, r0, r1 in (MID + [(SLEEVE[0], SLEEVE[1], SLEEVE[2], SLEEVE[2])] if kind == "mid" else CHASE_P):
        if a <= x <= b:
            rr.append(r0 + (r1 - r0) * (x - a) / (b - a))
    return min(rr) if rr else 0.7


# ---------------------------------------------------------------------------------------------------- building
PROTO = {}


def solid(name, part, size, J=None, bevel=0.06):
    """the part made a clean solid and baked (tanakit), moved so J is its origin; its prototype hidden. The barrels'
    halves aren't bevelled (round, smooth-shaded; a bevel there doubled their triangles)"""
    me, proto = part.solid("TANA_T16_" + name, bevel=bevel)
    tanakit.bake(me, proto, "T16_" + name, size)
    if J is not None:
        me.transform(Matrix.Translation(-J))
    proto.hide_render = proto.hide_viewport = True
    PROTO[name] = me
    return me


def mirrored(me, name):
    """a port piece mirrored to starboard in its own frame (y -> -y; every starboard piece's frame is its port twin's
    mirrored about the turret's centre line), sharing its port twin's baked texture"""
    m = me.copy()
    m.name = "TANA_T16_" + name
    m.transform(Matrix.Diagonal((1.0, -1.0, 1.0, 1.0)))
    bm = bmesh.new()
    bm.from_mesh(m)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(m)
    bm.free()
    m.update()
    PROTO[name] = m
    return m


class Turret:
    """one 16-inch turret's objects and its fire-mode pieces: pose(t) moves them"""

    def __init__(self, tag):
        self.tag = tag
        self.house = bpy.data.objects["LEV_T16_%s.001" % tag]
        self.trun = bpy.data.objects["LEV_G16_%s_trunnion" % tag]
        self.gun = bpy.data.objects["LEV_G16_%s.001" % tag]
        yaw = round(self.trun.rotation_euler.z / (math.pi / 2)) * (math.pi / 2)
        self.R = Matrix.Rotation(yaw, 4, "Z")                # the house's local frame -> the turret's
        self.armor, self.vents, self.barrels, self.chases, self.rest = {}, {}, {}, {}, {}

    def pieces(self):
        return (list(self.armor.values()) + list(self.vents.values()) + list(self.barrels.values())
                + list(self.chases.values()))

    def pose(self, t):
        a, v, b, c = stage(t, "plate"), stage(t, "vent"), stage(t, "barrel"), stage(t, "chase")
        for s, ob in self.armor.items():
            sg = 1.0 if s == "L" else -1.0
            ob.matrix_basis = self.rest[ob.name] @ Matrix.Rotation(sg * PLATE_OPEN * a, 4, Vector(ob["fm_hinge_axis"]))
        for s, ob in self.vents.items():
            sg = 1.0 if s == "L" else -1.0
            ob.matrix_basis = self.rest[ob.name] @ Matrix.Rotation(-sg * VENT_OPEN * v, 4, "X")
        for (n, s), ob in self.barrels.items():
            sg = 1.0 if s == "L" else -1.0
            ob.matrix_basis = self.rest[ob.name] @ Matrix.Translation((0, sg * BARREL_SLIDE * b, 0)) @ \
                Matrix.Rotation(sg * BARREL_TOE * b, 4, "Z")
        for (n, s), ob in self.chases.items():
            ob.matrix_basis = self.rest[ob.name] @ Matrix.Translation((CHASE_OUT * c, 0, 0))


TURRET = {}
INFO = {}


def build(coll, log=print):
    """the new mount on both turrets (their house, gun and trunnion objects changed in place), the fire-mode pieces
    made into `coll`; tanakit.WORK and tanakit.TEX set by the caller"""
    bpy.context.scene.frame_set(1)
    first = Turret("FWD")
    tl = first.R.inverted() @ first.trun.matrix_basis.translation        # the design's trunnion, turret frame
    M = Measures(tl.y, tl.z)
    log("firemode: the design's trunnion %s m, the new one %s m (turret frame)" % (
        tuple(round(c, 2) for c in tl), tuple(round(c, 2) for c in M.trun)))
    house = solid("house", house_part(M), 2048, bevel=0.05)
    stays = solid("stays", stays_part(), 1024, bevel=0)
    hinge = {s: Vector((-7.4, M.y0 + sg * (6.65 - 0.12), Z1 + 0.06)) for s, sg in (("L", 1.0), ("R", -1.0))}
    plates = {"L": solid("plate_L", plate_part(M, "L"), 512, hinge_of(M.walls["L"]), bevel=0.03)}
    vents = {"L": solid("vent_L", vent_part(M, 1.0), 512, hinge["L"])}
    mids = {"L": solid("mid_L", half_part("mid", 1.0), 512, bevel=0)}
    chases = {"L": solid("chase_L", half_part("chase", 1.0), 512, bevel=0)}
    for d, key in ((plates, "plate"), (vents, "vent"), (mids, "mid"), (chases, "chase")):
        d["R"] = mirrored(d["L"], key + "_R")
    INFO.update({"trunnion_m": list(M.trun), "muzzles_m": [[MUZZLE, v, 0.0] for v in GUN_Y],
                 "fire_muzzles_m": [[MUZZLE + CHASE_OUT, v, 0.0] for v in GUN_Y]})
    for tag in TURRETS:
        T = Turret(tag)
        TURRET[tag] = T
        old_house, old_gun = T.house.data, T.gun.data
        hm = house.copy() if tag != "FWD" else house
        if tag != "FWD":
            hm.transform(T.R)
        hm.name = "TANA_T16_house_%s" % tag
        T.house.data = hm
        T.gun.data = stays
        for me in (old_house, old_gun):
            if me.users == 0:
                bpy.data.meshes.remove(me)
        T.trun.location = T.R @ M.trun                                 # the pivot back behind the face
        T.gun.matrix_basis = Matrix()

        def add(name, me, parent, basis):
            ob = bpy.data.objects.new("TANA_T16_%s_%s" % (tag, name), me)
            coll.objects.link(ob)
            ob.parent = parent
            ob.matrix_parent_inverse = Matrix()
            ob.matrix_basis = basis
            T.rest[ob.name] = basis.copy()
            return ob
        for s in "LR":
            T.armor[s] = add("Armor_" + s, plates[s], T.house, T.R @ Matrix.Translation(hinge_of(M.walls[s])))
            T.armor[s]["fm_hinge_axis"] = list(M.walls[s]["along"])
            T.vents[s] = add("Vent_" + s, vents[s], T.house, T.R @ Matrix.Translation(hinge[s]))
        for n, yc in enumerate(GUN_Y, 1):
            for s in "LR":
                T.barrels[(n, s)] = add("Barrel_%d_%s" % (n, s), mids[s], T.trun, Matrix.Translation((SPLIT, yc, 0.0)))
                T.chases[(n, s)] = add("Chase_%d_%s" % (n, s), chases[s], T.barrels[(n, s)],
                                       Matrix.Translation((CHASE - SPLIT, 0.0, 0.0)))
    tris = {k: sum(len(f.vertices) - 2 for f in me.polygons) for k, me in PROTO.items()}
    log("firemode: the mount built: %s triangles (a turret: %d)" % (tris, tris["house"] + tris["stays"] + sum(
        tris[k] for k in ("plate_L", "plate_R", "vent_L", "vent_R")) + 3 * sum(tris[k] for k in ("mid_L", "mid_R", "chase_L", "chase_R"))))
    pose(0.0)
    return TURRET


def attach(log=print):
    """the registry again from a saved model (the pieces' rest = their pose at frame 1, before KEYS' deploy)"""
    bpy.context.scene.frame_set(1)
    O = bpy.data.objects
    for tag in TURRETS:
        T = Turret(tag)
        T.armor = {s: O["TANA_T16_%s_Armor_%s" % (tag, s)] for s in "LR"}
        T.vents = {s: O["TANA_T16_%s_Vent_%s" % (tag, s)] for s in "LR"}
        T.barrels = {(n, s): O["TANA_T16_%s_Barrel_%d_%s" % (tag, n, s)] for n in (1, 2, 3) for s in "LR"}
        T.chases = {(n, s): O["TANA_T16_%s_Chase_%d_%s" % (tag, n, s)] for n in (1, 2, 3) for s in "LR"}
        T.rest = {o.name: o.matrix_basis.copy() for o in T.pieces()}
        TURRET[tag] = T
    return TURRET


def pose(t):
    for T in TURRET.values():
        T.pose(t)
    glow(t)


def key(log=print):
    """the transform keyed into the model's timeline: deploy at KEYS[0], stow at KEYS[1] (every second frame, linear)"""
    n = 0
    mats = [m for m in bpy.data.materials if any(m.name.endswith(k) for k in GLOW) and m.use_nodes
            and m.node_tree.nodes.get("Principled BSDF")]
    for (f0, f1), up in zip(KEYS, (True, False)):
        for f in range(f0, f1 + 1, 2):
            t = (f - f0) / float(f1 - f0)
            pose(t if up else 1.0 - t)
            for T in TURRET.values():
                for ob in T.pieces():
                    ob.keyframe_insert("location", frame=f)
                    ob.keyframe_insert("rotation_euler", frame=f)
            for m in mats:
                m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].keyframe_insert("default_value", frame=f)
            n += 1
    for ob in [o for T in TURRET.values() for o in T.pieces()]:
        for fc in ob.animation_data.action.fcurves:
            for k in fc.keyframe_points:
                k.interpolation = "LINEAR"
    for m in mats:
        for fc in m.node_tree.animation_data.action.fcurves:
            for k in fc.keyframe_points:
                k.interpolation = "LINEAR"
    bpy.context.scene.frame_set(1)
    log("firemode: keyed %d poses: deploy %d-%d, stow %d-%d (%.1f s each at %d fps)" % (
        n, KEYS[0][0], KEYS[0][1], KEYS[1][0], KEYS[1][1], (KEYS[0][1] - KEYS[0][0]) / FPS, FPS))
