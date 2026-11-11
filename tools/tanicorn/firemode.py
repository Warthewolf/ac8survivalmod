"""firemode.py : Blender 3.3, THE TANACORN's 16-inch triple turret, modelled from scratch, and its FIRE MODE, in eight
styles for the user to choose from (STYLES).

The user (2026-11-11): "we make them look normal, until they transform into fire mode", with stills of a battleship
turret transforming: its armour coming apart in angular blocks, side plates held out on arms, slabs staggered out in
layers; each barrel splitting lengthwise and opening like jaws round a glowing core, bracket rings along the open
halves; green lightning and rings round the muzzles as it fires. Two passes were turned down ("Surely you can do a
higher quality job", "I don't like this version either"); then: "give me 8 different versions of the Turret with
different styles, I want it as close as humanly possible to what those screenshots showed you and I'll pick". Every
style is our own geometry built here (no other work's model or drawing is used).

Imported by model_tanacorn.py (TANA_FM_STYLE: the style, DEFAULT_STYLE when unset, 0 for none: the design's Iowa
mount) and by styles_firemode.py (each style built in turn and rendered for the choice). It REPLACES the Iowa's mount
on both turrets (LEV_T16_FWD / _AFT): the house object gets the house, the gun object the guns' fixed parts (bloomer
boots, the barrels' root rings, the core rods), the trunnion moves back to 1.2 m behind the face. The house is
an armour SHELL over a dark core: thirteen wall slabs and the roof, each mitred to its neighbours with a seam between;
stowed, a battleship turret with dim running lights. In fire mode the style's slabs move off dark machinery bays and
every barrel forward of its root splits into 2-4 pieces round its core rod. Nothing inside glows (GLOW): the core rods
light only as the guns fire.

Pieces are objects TANA_T16_<tag>_<bone>, each carrying its motion (fm_ops, json: translations and turns, each over a
stretch of the 2.5 s transform), its part (fm_part ARMOR: on turret_yaw, GUNS: on turret_pitch) and bone (fm_bone).
pose(t) poses them (t 0 stowed .. 1 fire mode), key() keys the transform into the model's timeline (KEYS), attach()
finds them again in a saved model.
"""
import bpy, bmesh, math, json, os, random
from mathutils import Vector, Matrix
import tanakit
from tanakit import Part, M_PAINT, M_DARK, M_GLASS

DEPLOY_S, FPS = 2.5, 30
KEYS = ((110, 185), (226, 301))           # the model's 1-360 timeline (30 fps): deploy as the guns finish lifting
                                          # (the design: train 34-104, lift 94-129), stow as they come down (225-255)
TURRETS = ("FWD", "AFT")
BAKE = True                               # styles_firemode.py turns it off (the choice needs no textures)

# ---------------------------------------------------------------------------------------------------- the styles
# barrel: split  LR (left / right jaws), TB (top / bottom jaws), Q4 (four petals), T3 (three petals, one on top),
#                S4 (four staves on the diagonals)
#         hinge  deg each piece swings out about its root; slide m it moves straight out; extend m it slides forward
# armour: struts    the forward side walls slide out on arms
#         layers    the side walls (aft, forward, chamfer) in three slabs each, cut on a slant, staggered out
#         exploded  the roof in three blocks lifting apart, the side walls and the rear sliding out
#         clamshell the roof's halves hinged up on their outer edges, the forward side walls hinged down
# circuit: the Fog's glowing lines over the armour
STYLES = {
    1: {"name": "Jaws, armour on struts", "barrel": {"split": "LR", "hinge": 3.5}, "armour": "struts"},
    2: {"name": "Jaws, layered armour", "barrel": {"split": "LR", "hinge": 3.5}, "armour": "layers"},
    3: {"name": "Crocodile jaws, armour on struts", "barrel": {"split": "TB", "hinge": 4.5}, "armour": "struts"},
    4: {"name": "Sliding rails, exploded house", "barrel": {"split": "LR", "slide": 0.5, "extend": 3.0},
        "armour": "exploded"},
    5: {"name": "Four petals, exploded house", "barrel": {"split": "Q4", "hinge": 4.0}, "armour": "exploded"},
    6: {"name": "Splayed staves, layered armour", "barrel": {"split": "S4", "hinge": 2.0, "slide": 0.3},
        "armour": "layers"},
    7: {"name": "Three petals, clamshell roof", "barrel": {"split": "T3", "hinge": 5.0}, "armour": "clamshell"},
    8: {"name": "Fog circuits, jaws, layered armour", "barrel": {"split": "LR", "hinge": 3.5}, "armour": "layers",
        "circuit": True},
    # the user's own (2026-11-11, with two manga panels of the guns opened round coil rings): "Split the barrels into
    # four sections. Then split the barrels in the middle and have them slide back and angle themselves upwards. Keep
    # the glowing rod in the center of the barrel. Have the back left and back right of the turret explode outwards.
    # And have the front right and left sides also explode outwards. Feel free to model an interior of the gun housing."
    9: {"name": "Four sections split mid-length, sliding back, angled up; quarters exploding out; the gun house inside",
        "barrel": {"split": "Q4", "mid": True}, "armour": "quarters", "interior": True},
    # the user's clip (2026-11-11, an 8 s screen recording: "Watch this frame by frame. I want it to look exactly like
    # this"), with their correction before it: "have the front right and left sides, along with the front section of the
    # roof lift up". As its frames show it: each barrel's shell is four quarters, top, bottom, port and starboard, the
    # seams an X on the muzzle (frames 11-41); the quarters step out together, the seams flashing yellow (47-50), and,
    # cut in the middle, slide back over their rear halves in two steps, angling up (57-59), round a khaki rod that
    # then pushes out and lights (61-70). The side walls split on a stepped seam, high aft and running down forward
    # (171-176): the upper panel lifts straight up, the lower one slides forward, the rear corners fold out into ramps
    # with their upper halves standing back up, the roof over the rear rises (177-183), a big drum inside; the roof's
    # front halves rise and tip up like visors (38-44): "the front ... sides, along with the front section of the roof
    # lift up".
    10: {"name": "The clip: quarters slide back round the rod; panels lift, rear folds out, roof front tips up",
         "barrel": {"split": "Q4", "mid": True, "clip": True, "shell_t": 0.3, "bore": 0.58, "rim": True, "edges": True},
         "armour": "clip", "interior": True, "roof_static": (-8.0, 3.4), "rings_glow": True, "rings_to": 7.6,
         "core": (0.24, 23.8, 2.0), "struts": False},
}
DEFAULT_STYLE = 10
# style 10's barrel (the clip's frames 47-70, read by the analysis of 2026-11-11): the four quarters step out from the rod
# together ("part", 47), the front halves a little further (to pass over the rear ones: (offset difference) x cos 45 >
# the rear's outer radius - the front's inner), then the front halves slide back in two steps ("back", a small step at
# 57, the rest at 59) to 65 % of the barrel, while the whole staves pitch up about their roots ("pitch": the side
# quarters, the top one, the bottom one; deg nose up: "have them slide back and angle themselves upwards"); the rod
# pushes forward ("core"'s third value, 61) and lights up (64-70); a yellow flash from the seams as they open (47-49)
CLIP = {"part": 0.55, "front_out": 0.7, "back": 9.0, "back_first": 0.3, "pitch": (10.0, 5.0, 0.0),
        "stages": {"part": (0.04, 0.16), "out": (0.18, 0.28), "back1": (0.3, 0.4), "back2": (0.46, 0.62),
                   "pitch": (0.46, 0.62), "push": (0.66, 0.74)},
        "flash": (0.04, 0.2, 1.4)}
# style 9's barrel: a thin shell in four sections (port, top, starboard, bottom) round a core assembly (the glowing rod,
# coil rings on spokes, rails), each section cut at X_MID; the pieces part (MID_OUT), slide back (MID_BACK) and pitch up
# (MID_TILT deg, parallel: the top ones about their back end, the bottom ones about their front, the sides about their
# middle), the rear pieces less than the front so the front ones stack outside them
X_MID = 14.95
MID_OUT, MID_BACK, MID_TILT = {"rear": 0.75, "front": 1.45}, {"rear": 0.6, "front": 3.2}, 16.0
MID_STAGES = ((0.25, 0.5), (0.45, 0.7), (0.65, 0.9))      # part, slide back, pitch up
SHELL_T = 0.13                                            # the shell's thickness
RING_R, RING_T, RING_STEP = 0.56, 0.08, 1.7               # the coil rings: radius, tube, spacing
SPLITS = {"LR": (0, 180), "TB": (90, 270), "Q4": (0, 90, 180, 270), "T3": (90, 210, 330), "S4": (45, 135, 225, 315)}
STAGE_ARMOUR, STAGE_BARREL, STAGE_GLOW, STAGE_SLIT = (0.0, 0.45), (0.3, 0.7), (0.6, 1.0), (0.0, 0.2)

# ---------------------------------------------------------------------------------------------------- measures
# The turret's frame: x its guns' way, z up, the origin the house object's (the yaw pivot); the guns' frame: the
# trunnion's. Lengths in m. The outline is the design's (the Iowa's at the Leviathan's scale): port halves from the
# rear's middle round to the face's middle, v off the turret's centre line.
Z0, Z1 = 0.61, 6.52                       # the house's floor and roof
SHELL = 0.45                              # the armour's thickness over the core
HALF_B = [(-15.05, 0.0), (-14.8, 3.1), (-14.3, 6.6), (-13.75, 9.3), (3.3, 11.75), (12.9, 9.55), (14.4, 8.3), (14.4, 0.0)]
HALF_T = [(-14.95, 0.0), (-14.7, 2.9), (-14.2, 6.2), (-13.65, 8.75), (3.6, 10.75), (9.55, None), (10.3, None), (10.3, 0.0)]
FACE_X0, FACE_K = 14.4, 4.1 / 5.91        # the face: x = FACE_X0 - (z - Z0) * FACE_K (35 deg back)
GUN_Y = (5.89, 0.0, -5.89)                # each gun's axis off the trunnion's (port first: SOC_Gun_01..03)
BEHIND_FACE = 1.2                         # the trunnion this far behind the face
SPLIT, MUZZLE = 3.0, 26.9                 # where the barrel splits and its muzzle, from the trunnion
BORE, CORE_R = 0.45, 0.24
SEG = 40
BARREL = [(3.0, 3.32, 1.09, 1.09), (3.3, 25.92, 1.02, 0.86), (10.9, 11.15, 1.05, 1.05), (18.4, 18.62, 0.98, 0.98),
          (25.9, 26.52, 0.86, 0.94), (26.5, 26.9, 0.94, 0.91)]
# the bloomer boot round each gun's root: (x0, x1, r) rings, a fold every 0.42 m, narrowing to the barrel
BOOT = [(-0.9 + 0.42 * k, -0.9 + 0.42 * k + 0.26, 1.72 - 0.085 * k) for k in range(9)] + \
       [(-0.9 + 0.42 * k + 0.2, -0.9 + 0.42 * k + 0.46, 1.6 - 0.085 * k) for k in range(9)]
NAMES = ["rear_L1", "rear_L2", "rear_L3", "aside_L", "fside_L", "chamfer_L", "face", "chamfer_R", "fside_R", "aside_R",
         "rear_R3", "rear_R2", "rear_R1"]   # the outline's 13 walls, from the rear's middle by port round to starboard
WHOLE = ((0, 0), (1, 0), (1, 1), (0, 1))


def smooth(t, a, b):
    f = min(1.0, max(0.0, (t - a) / (b - a)))
    return f * f * (3.0 - 2.0 * f)


# ---------------------------------------------------------------------------------------------------- materials
# Nothing inside glows (the user, 2026-11-11: "Don't have the insides glow") but the core rods ("Keep the glowing rod in
# the center of the barrel"): the bays under the armour, the fins under the roof, the gun house's machinery and the
# barrels' bores are dark. The running lights outside glow dim stowed, brighter in fire mode; the cores light in fire
# mode and flare as a gun fires (FIRE: glow(t, fire)).
GLOW = {   # key: (base colour, emission colour, strength stowed, strength in fire mode, its stretch)
    "fm_core": ((0.30, 0.28, 0.16), (1.00, 0.76, 0.12), 0.0, 0.25, STAGE_GLOW),  # the clip's khaki rod, lit as it fires
    "fm_slit": ((0.06, 0.40, 0.36), (0.20, 0.95, 0.88), 1.0, 7.0, STAGE_SLIT),
}
FLASH = None                              # build() sets it from a style's barrel (style 10: CLIP["flash"])
FIRE = {"fm_core": 1.5, "fm_ring": 1.5}   # the cores' (and their rings') glow as a gun fires: yellow, not white
GLOW["fm_ring"] = ((0.07, 0.06, 0.03), (1.00, 0.80, 0.30), 0.0, 1.6, STAGE_GLOW)   # style 10's coil rings, gold
GLOW["fm_edge"] = ((0.05, 0.045, 0.03), (1.00, 0.82, 0.20), 0.0, 0.0, STAGE_GLOW)  # style 10's stave edges: lit only
FIRE["fm_edge"] = 1.6                                                               # as the rod fires (the clip, 69-70)
M_RIM = tanakit.mat("TANA_rim", (0.30, 0.31, 0.32), 0.5, 0.4)       # style 10's muzzle faces: light grey (the clip)
MAT = {}
for _k, (_base, _emit, _lo, _hi, _st) in GLOW.items():
    MAT[_k] = tanakit.mat("TANA_" + _k, _base, 0.2, 0.3, _emit, _lo)
    MAT[_k]["tana_glow"] = True


def glow(t, fire=0.0):
    """every glow material's strength at t (the baked parts' copies too: TANA_<part>_fm_*); fire 0..1: a shot"""
    for m in bpy.data.materials:
        for k, (_, _, lo, hi, st) in GLOW.items():
            if m.name.endswith(k) and m.use_nodes and m.node_tree.nodes.get("Principled BSDF"):
                v = lo + (hi - lo) * smooth(t, *st) + FIRE.get(k, 0.0) * fire
                if k == "fm_core" and FLASH:                # (style 10: the seams' flash as the quarters open)
                    a, b, peak = FLASH
                    v += peak * math.sin(math.pi * min(1.0, max(0.0, (t - a) / (b - a))))
                m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = v


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
    """a box: centre, three unit axes, full sizes along them"""
    bm = part._bm(cut, post)
    R = Matrix((axes[0], axes[1], axes[2])).transposed().to_4x4()
    r = bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(centre) @ R @ Matrix.Diagonal((*size, 1.0)))
    part._put(bm, r["verts"], m)


XYZ = (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))


def abox(part, lo, hi, m, cut=False, post=False):
    lo, hi = Vector(lo), Vector(hi)
    box(part, (lo + hi) / 2.0, XYZ, hi - lo, m, cut, post)


def hexa(part, outer, inner, m, cut=False, post=False):
    """a six-sided solid: an outer and an inner quad (corresponding corners)"""
    bm = part._bm(cut, post)
    o = [bm.verts.new(p) for p in outer]
    i = [bm.verts.new(p) for p in inner]
    fs = [bm.faces.new(o), bm.faces.new(i[::-1])]
    for k in range(4):
        fs.append(bm.faces.new((o[k], i[k], i[(k + 1) % 4], o[(k + 1) % 4])))
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    part._put(bm, o + i, m)


def loft(part, polyB, zB, polyT, zT, m, cut=False, post=False):
    """a solid between two convex polygons with as many corners (x, y), at zB and zT"""
    bm = part._bm(cut, post)
    lo = [bm.verts.new((x, y, zB)) for x, y in polyB]
    hi = [bm.verts.new((x, y, zT)) for x, y in polyT]
    fs = [bm.faces.new(lo[::-1]), bm.faces.new(hi)]
    k = len(polyB)
    for i in range(k):
        fs.append(bm.faces.new((lo[i], lo[(i + 1) % k], hi[(i + 1) % k], hi[i])))
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    part._put(bm, lo + hi, m)


def arc_tube(part, x, r_arc, a0, a1, r_tube, m, steps=10):
    """a bracket: a tube along an arc round the x axis (angles a0..a1 from +y toward +z), its ends closed (post)"""
    bm = part._bm(False, True)
    rings = []
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        rad = Vector((0, math.cos(a), math.sin(a)))
        c = Vector((x, 0, 0)) + rad * r_arc
        rings.append([bm.verts.new(c + Vector((1, 0, 0)) * r_tube * math.cos(b) + rad * r_tube * math.sin(b))
                      for b in [2 * math.pi * j / 8 for j in range(8)]])
    fs = []
    for r0, r1 in zip(rings, rings[1:]):
        for j in range(8):
            fs.append(bm.faces.new((r0[j], r0[(j + 1) % 8], r1[(j + 1) % 8], r1[j])))
    fs += [bm.faces.new(rings[0][::-1]), bm.faces.new(rings[-1])]
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    part._put(bm, [v for r in rings for v in r], m)


def torus_x(part, x, y, z, R, r, m, major=20, minor=6, post=True):
    """a ring round the x axis at (x, y, z): radius R, tube r"""
    bm = part._bm(False, post)
    rings = []
    for i in range(major):
        a = 2 * math.pi * i / major
        rad = Vector((0, math.cos(a), math.sin(a)))
        c = Vector((x, y, z)) + rad * R
        rings.append([bm.verts.new(c + Vector((1, 0, 0)) * r * math.cos(b) + rad * r * math.sin(b))
                      for b in [2 * math.pi * j / minor for j in range(minor)]])
    fs = []
    for i in range(major):
        r0, r1 = rings[i], rings[(i + 1) % major]
        for j in range(minor):
            fs.append(bm.faces.new((r0[j], r0[(j + 1) % minor], r1[(j + 1) % minor], r1[j])))
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    part._put(bm, [v for rr in rings for v in rr], m)


def offset2d(poly, d):
    """a convex polygon's edges moved d outward (negative: in), corners where they meet again"""
    k = len(poly)
    area = sum(poly[i][0] * poly[(i + 1) % k][1] - poly[(i + 1) % k][0] * poly[i][1] for i in range(k))
    s = 1.0 if area > 0 else -1.0
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


def shrink(quad, d):
    c = sum(quad, Vector()) / len(quad)
    return [c + (p - c) * max(0.0, 1.0 - d / max((p - c).length, 1e-6)) for p in quad]


# ---------------------------------------------------------------------------------------------------- the shell
class Shell:
    """the house's outline (13 flat walls and the roof), its core SHELL in, the face's frame, the trunnion"""

    def __init__(self, y0, zt):
        self.y0 = y0
        B, T = [list(p) for p in HALF_B], [list(p) for p in HALF_T]
        P = lambda q, z: Vector((q[0], q[1], z))
        for i, (a, b, c) in ((5, (4, 5, 4)), (6, (5, 6, 5))):      # the forward side wall and the chamfer flat
            pa, pb, pc = P(B[a], Z0), P(B[b], Z0), P(T[c], Z1)
            n = (pb - pa).cross(pc - pa)
            T[i][1] = pa.y - (n.x * (T[i][0] - pa.x) + n.z * (Z1 - Z0)) / n.y
        full = lambda h: [(x, y0 + v) for x, v in h[:7]] + [(x, y0 - v) for x, v in reversed(h[1:7])]
        self.B, self.T = full(B), full(T)                          # 13 corners (the face's middle left out: in line)
        self.Bc, self.Tc = offset2d(self.B, -SHELL), offset2d(self.T, -SHELL)
        self.zc = Z1 - SHELL                                       # the core's top
        self.fn = Vector((5.91, 0.0, 4.1)).normalized()           # the face's outward normal, up the face
        self.fup = Vector((-4.1, 0.0, 5.91)).normalized()
        self.f0 = Vector((FACE_X0, y0, Z0))
        self.trun = Vector((FACE_X0 - (zt - Z0) * FACE_K - BEHIND_FACE, y0, zt))

    def wall(self, name):
        """a wall's outer and inner quads (bottom a, bottom b, top b, top a), its frame (along, up, out)"""
        i = NAMES.index(name)
        j = (i + 1) % 13
        O = [Vector((*self.B[i], Z0)), Vector((*self.B[j], Z0)), Vector((*self.T[j], Z1)), Vector((*self.T[i], Z1))]
        I = [Vector((*self.Bc[i], Z0)), Vector((*self.Bc[j], Z0)), Vector((*self.Tc[j], self.zc)),
             Vector((*self.Tc[i], self.zc))]
        u = (O[1] - O[0]).normalized()
        n = (O[1] - O[0]).cross(O[3] - O[0]).normalized()
        c = sum(O, Vector()) / 4.0
        if n.dot(c - Vector((0.0, self.y0, c.z))) < 0:
            n = -n
        v = n.cross(u).normalized()
        if v.z < 0:
            v = -v
        return O, I, u, v, n

    @staticmethod
    def at(Q, s, w):
        return (Q[0].lerp(Q[1], s)).lerp(Q[3].lerp(Q[2], s), w)

    def on_face(self, v, h):
        return self.f0 + Vector((0, v, 0)) + self.fup * h


def slab(part, S, name, region=WHOLE, m=M_PAINT, seam=0.035):
    """a wall's armour (or a stretch of it: region in its (along, up) 0..1), mitred to its neighbours, a seam round it"""
    O, I, u, v, n = S.wall(name)
    inner = [p - n * 0.06 for p in shrink([S.at(I, s, w) for s, w in region], seam)]   # (sunk into the core: flush
    hexa(part, shrink([S.at(O, s, w) for s, w in region], seam), inner, m)              # faces broke the union)


def poly_slab(part, S, name, poly, m=M_PAINT, seam=0.035):
    """a wall's armour over any (simple) polygon of its (along, up) 0..1, mitred like slab(), a seam round it"""
    O, I, u, v, n = S.wall(name)
    Ls = ((O[1] - O[0]).length + (O[2] - O[3]).length) / 2.0
    Lw = ((O[3] - O[0]).length + (O[2] - O[1]).length) / 2.0
    q = [(a / Ls, b / Lw) for a, b in offset2d([(s * Ls, w * Lw) for s, w in poly], -seam)]
    bm = part._bm(False, False)
    o = [bm.verts.new(S.at(O, s, w)) for s, w in q]
    i = [bm.verts.new(S.at(I, s, w) - n * 0.06) for s, w in q]
    fs = [bm.faces.new(o), bm.faces.new(i[::-1])]
    k = len(q)
    for j in range(k):
        fs.append(bm.faces.new((o[j], i[j], i[(j + 1) % k], o[(j + 1) % k])))
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    part._put(bm, o + i, m)


def bay(part, S, name):
    """what's under a wall's armour (seen when the armour moves): dark machinery, unlit: a sunk panel, ribs across it,
    two pipes along it"""
    O, I, u, v, n = S.wall(name)
    q = shrink([S.at(I, s, w) for s, w in WHOLE], 0.25)
    hexa(part, [p + n * 0.04 for p in q], [p - n * 0.05 for p in q], M_DARK, post=True)
    L = (q[1] - q[0]).length
    k = 0.7
    while k < L - 0.4:
        f = k / L
        a, b = q[0].lerp(q[1], f), q[3].lerp(q[2], f)
        box(part, (a + b) / 2.0 + n * 0.12, (u, (b - a).normalized(), n), (0.14, (b - a).length, 0.24), M_PAINT, post=True)
        k += 0.85
    for w in (0.3, 0.68):
        a, b = q[0].lerp(q[3], w), q[1].lerp(q[2], w)
        cyl(part, 0.13, 0.13, (b - a).length - 0.3, (a + b) / 2.0 + n * 0.3, b - a, M_DARK, 12, post=True)


def roof_slab(part, S, x_lo=None, x_hi=None, side=0, gap=0.04):
    """the roof's armour (or a block of it: between x_lo and x_hi, port side 1 / starboard -1 / both 0)"""
    loft(part, offset2d(S.T, -gap), Z1, offset2d(S.Tc, -gap - 0.04), S.zc - 0.06, M_PAINT)
    W = 40.0
    if x_lo is not None:
        abox(part, (-W, -W, Z0 - 1), (x_lo + gap, W, Z1 + 2), M_DARK, cut=True)
    if x_hi is not None:
        abox(part, (x_hi - gap, -W, Z0 - 1), (W, W, Z1 + 2), M_DARK, cut=True)
    if side > 0:
        abox(part, (-W, -W, Z0 - 1), (W, S.y0 + gap, Z1 + 2), M_DARK, cut=True)
    elif side < 0:
        abox(part, (-W, S.y0 - gap, Z0 - 1), (W, W, Z1 + 2), M_DARK, cut=True)


def roof_details(part, S, x_lo=-99.0, x_hi=99.0, side=0):
    """the roof's fittings that fall on this block: sighting hoods, hatches, mushroom vents"""
    y0 = S.y0
    for sg in (1.0, -1.0):
        if side and sg != side:
            continue
        if x_lo < 6.7 < x_hi:
            a, b = sorted((y0 + sg * 5.9, y0 + sg * 7.5))
            part.prism([(5.0, Z1 - 0.05), (8.4, Z1 - 0.05), (7.7, Z1 + 0.95), (5.4, Z1 + 0.95)], "Y", a, b)
            box(part, Vector((8.07, (a + b) / 2.0, Z1 + 0.5)), (Vector((0.805, 0, 0.593)), XYZ[1], Vector((-0.593, 0, 0.805))),
                (0.06, 1.1, 0.22), M_GLASS, post=True)
        if x_lo < -3.0 < x_hi:
            cyl(part, 0.78, 0.74, 0.22, Vector((-3.0, y0 + sg * 3.4, Z1 + 0.06)), (0, 0, 1), M_PAINT, 32)
            cyl(part, 0.42, 0.42, 0.16, Vector((-3.0, y0 + sg * 3.4, Z1 + 0.22)), (0, 0, 1), M_PAINT, 24)
        if x_lo < -12.6 < x_hi:
            cyl(part, 0.3, 0.3, 0.8, Vector((-12.6, y0 + sg * 5.2, Z1 + 0.3)), (0, 0, 1), M_PAINT, 24)
            cyl(part, 0.58, 0.5, 0.2, Vector((-12.6, y0 + sg * 5.2, Z1 + 0.72)), (0, 0, 1), M_PAINT, 24)


def ears(part, S, sg):
    """a rangefinder ear on an aft side wall, a lens in its end"""
    y0 = S.y0
    oc = [(-12.9, 4.25), (-12.3, 3.55), (-8.9, 3.55), (-8.3, 4.25), (-8.3, 5.25), (-8.9, 5.95), (-12.3, 5.95), (-12.9, 5.25)]
    a, b = sorted((y0 + sg * 8.6, y0 + sg * 14.25))
    part.prism(oc, "Y", a, b)
    cyl(part, 0.62, 0.62, 0.3, Vector((-10.6, y0 + sg * 14.25, 4.75)), (0, 1, 0), M_DARK, 32, cut=True)
    cyl(part, 0.56, 0.56, 0.08, Vector((-10.6, y0 + sg * 14.12, 4.75)), (0, 1, 0), M_GLASS, 32, post=True)


def gun_wells(part, S):
    """the face's slots the guns' boots sit in (cut through the face's armour into the core)"""
    for v in GUN_Y:
        h = (Vector((S.trun.x, S.y0 + v, S.trun.z)) - S.f0).dot(S.fup)
        box(part, S.on_face(v, h + 0.6) - S.fn * 0.9, (S.fn, XYZ[1], S.fup), (2.6, 3.9, 6.2), M_DARK, cut=True)


def face_lights(part, S):
    for v in GUN_Y:
        h = (Vector((S.trun.x, S.y0 + v, S.trun.z)) - S.f0).dot(S.fup)
        box(part, S.on_face(v, h - 2.85) + S.fn * 0.015, (S.fn, XYZ[1], S.fup), (0.06, 1.3, 0.17), MAT["fm_slit"], post=True)
    for v in (-8.0, 8.0):
        box(part, S.on_face(v, 1.0) + S.fn * 0.015, (S.fn, XYZ[1], S.fup), (0.06, 0.7, 0.14), MAT["fm_slit"], post=True)


def circuit(part, S, name, region, seed):
    """the Fog's glowing lines over an armour slab: three square-cornered runs (deterministic)"""
    rnd = random.Random(seed)
    O, I, u, v, n = S.wall(name)
    (s0, w0), (s1, _), _, (_, w1) = region
    for _ in range(3):
        s, w = rnd.uniform(s0 + 0.08, s1 - 0.08), rnd.uniform(w0 + 0.12, max(w0 + 0.13, w1 - 0.12))
        horiz = rnd.random() < 0.5
        for _ in range(rnd.randint(2, 4)):
            if horiz:
                s2 = min(s1 - 0.06, max(s0 + 0.06, s + rnd.choice((-1, 1)) * rnd.uniform(0.12, 0.35)))
                a, b = Shell.at(O, s, w), Shell.at(O, s2, w)
                s = s2
            else:
                w2 = min(w1 - 0.08, max(w0 + 0.08, w + rnd.choice((-1, 1)) * rnd.uniform(0.15, 0.4)))
                a, b = Shell.at(O, s, w), Shell.at(O, s, w2)
                w = w2
            d = b - a
            if d.length > 0.2:
                ax = d.normalized()
                box(part, (a + b) / 2.0 + n * 0.012, (ax, n.cross(ax).normalized(), n), (d.length + 0.1, 0.1, 0.05),
                    MAT["fm_slit"], post=True)
            horiz = not horiz


def struts(part, S, name, region, travel, reach=1.0, height=0.5):
    """two arms on a slab's inside, along its travel (shut, they run into the core; reach m past the travel)"""
    O, I, u, v, n = S.wall(name)
    d = travel.normalized()
    L = travel.length + reach
    for s in (0.3, 0.7):
        w = region[0][1] + (region[3][1] - region[0][1]) * height
        a = Shell.at(O, region[0][0] + (region[1][0] - region[0][0]) * s, w) - n * (SHELL * 0.6)
        cyl(part, 0.17, 0.17, L, a - d * (L / 2.0), d, M_PAINT, 16)


# ---------------------------------------------------------------------------------------------------- the armour
def armour_plan(style, S):
    """the style's moving armour: [(bone, kind, wall name or roof block, region, ops)]; ops in the turret's frame"""
    kind = style["armour"]
    plan = []

    def out(name):
        n = S.wall(name)[4]
        return Vector((n.x, n.y, 0.0)).normalized()
    if kind == "struts":
        for s in "LR":
            plan.append(("Armor_fside_%s" % s, "wall", "fside_" + s, None, [("T", out("fside_" + s) * 2.4, STAGE_ARMOUR)]))
    elif kind == "layers":
        cuts = [(lambda s: 0.0), (lambda s: 0.34 + 0.12 * s), (lambda s: 0.72 - 0.12 * s), (lambda s: 1.0)]
        for s in "LR":
            for name in ("aside_" + s, "fside_" + s, "chamfer_" + s):
                for k in range(3):
                    lo, hi = cuts[k], cuts[k + 1]
                    region = ((0, lo(0)), (1, lo(1)), (1, hi(1)), (0, hi(0)))
                    d = out(name) * (0.7 + 0.75 * k) + Vector((0, 0, 0.25 * (k - 1)))
                    plan.append(("Armor_%s_%d" % (name, k + 1), "wall", name, region, [("T", d, (0.05 * k, 0.33 + 0.06 * k))]))
    elif kind == "exploded":
        for s in "LR":
            for name in ("aside_" + s, "fside_" + s):
                plan.append(("Armor_" + name, "wall", name, None, [("T", out(name) * 2.0, (0.05, 0.42))]))
            for name in ("rear_%s1" % s, "rear_%s2" % s, "rear_%s3" % s):
                plan.append(("Armor_" + name, "wall", name, None, [("T", out(name) * 1.5, (0.0, 0.38))]))
        plan.append(("Armor_roof_rear", "roof", (-99.0, -5.0, 0), None, [("T", Vector((-1.2, 0, 1.1)), (0.0, 0.4))]))
        plan.append(("Armor_roof_mid", "roof", (-5.0, 3.5, 0), None, [("T", Vector((0, 0, 1.9)), (0.05, 0.45))]))
        plan.append(("Armor_roof_front", "roof", (3.5, 99.0, 0), None, [("T", Vector((0.7, 0, 1.0)), (0.1, 0.45))]))
    elif kind == "quarters":
        # the back left and right (the aft side walls in two chunks, the rear corners) and the front left and right
        # (the forward side walls in two bands, the chamfers) blown outward on arms, each chunk turning as it goes
        def bottom(name, reg):
            O = S.wall(name)[0]
            return Shell.at(O, (reg[0][0] + reg[1][0]) / 2.0, reg[0][1])
        for s, sg in (("L", 1.0), ("R", -1.0)):
            a, f, c = "aside_" + s, "fside_" + s, "chamfer_" + s
            u = lambda nm: S.wall(nm)[2]
            back = ((0, 0), (0.5, 0), (0.5, 1), (0, 1))
            mid = ((0.5, 0), (1, 0), (1, 1), (0.5, 1))
            low = ((0, 0), (1, 0), (1, 0.5), (0, 0.5))
            high = ((0, 0.5), (1, 0.5), (1, 1), (0, 1))
            plan.append(("Armor_%s_1" % a, "wall", a, back,
                         [("T", out(a) * 3.0 + Vector((-0.9, 0, 0.5)), (0.0, 0.35)),
                          ("R", u(a), bottom(a, back), -sg * 14.0, (0.1, 0.4))]))
            plan.append(("Armor_%s_2" % a, "wall", a, mid,
                         [("T", out(a) * 2.4 + Vector((0, 0, 0.3)), (0.03, 0.36)),
                          ("R", u(a), bottom(a, mid), -sg * 9.0, (0.1, 0.4))]))
            plan.append(("Armor_rear_%s3" % s, "wall", "rear_%s3" % s, None,
                         [("T", out("rear_%s3" % s) * 2.6 + Vector((-0.8, 0, 0.3)), (0.0, 0.35)),
                          ("R", Vector((0, 0, 1)), bottom("rear_%s3" % s, WHOLE), sg * 10.0, (0.1, 0.4))]))
            plan.append(("Armor_rear_%s2" % s, "wall", "rear_%s2" % s, None,
                         [("T", out("rear_%s2" % s) * 1.8, (0.02, 0.35))]))
            plan.append(("Armor_%s_1" % f, "wall", f, low,
                         [("T", out(f) * 2.4 + Vector((0.3, 0, -0.1)), (0.05, 0.38)),
                          ("R", u(f), bottom(f, low), -sg * 6.0, (0.12, 0.42))]))
            plan.append(("Armor_%s_2" % f, "wall", f, high,
                         [("T", out(f) * 3.2 + Vector((0.2, 0, 0.7)), (0.05, 0.4)),
                          ("R", u(f), bottom(f, high), -sg * 16.0, (0.12, 0.45))]))
            plan.append(("Armor_" + c, "wall", c, None,
                         [("T", out(c) * 2.6 + Vector((1.0, 0, 0.2)), (0.05, 0.4)),
                          ("R", Vector((0, 0, 1)), bottom(c, WHOLE), -sg * 12.0, (0.12, 0.45))]))
    elif kind == "clip":
        # as the clip's side shot draws it (frames 171-183, read by the analysis): the aft side wall's seam level at
        # half height from the rear corner to 0.35 along, sloping down to 0.71, then straight down to the foot at 0.73:
        # above it an L-shaped panel (its forward tab full height) lifts straight up 0.42 H, no tilt; below it the
        # lower panel slides forward 0.42 H along the foot (once the tab is clear) and 0.1 H out
        H = Z1 - Z0
        upper = [(0, 0.51), (0.35, 0.51), (0.71, 0.39), (0.73, 0), (1, 0), (1, 1), (0, 1)]
        lower = [(0, 0), (0.73, 0), (0.71, 0.39), (0.35, 0.51), (0, 0.51)]
        for s, sg in (("L", 1.0), ("R", -1.0)):
            flip = (lambda P: P) if s == "L" else (lambda P: [(1 - a, b) for a, b in reversed(P)])   # (starboard walls
            A = "aside_" + s                                                                   # run front to back)
            O, I, u, v, n = S.wall(A)
            fwd = u if s == "L" else -u
            plan.append(("Armor_%s_up" % A, "wall", A, flip(upper), [("T", Vector((0, 0, 0.42 * H)), (0.03, 0.28))]))
            plan.append(("Armor_%s_low" % A, "wall", A, flip(lower),
                         [("T", fwd * (0.42 * H) + n * 0.6, (0.2, 0.42))]))
            # the rear corner: each of its two facets tips out on its foot (62 deg: a ramp) and folds at 0.4 of its
            # height, its upper part standing back up, leaning in toward the house (the clip's leaves, 15 / 25 deg)
            for name, lean in (("rear_%s3" % s, 15.0), ("rear_%s2" % s, 25.0)):
                Ow, Iw, uw, vw, nw = S.wall(name)
                foot, fold = (Ow[0] + Ow[1]) / 2.0, Shell.at(Ow, 0.5, 0.4)
                tip = ("R", uw, foot, 62.0, (0.04, 0.32))
                plan.append(("Armor_%s_low" % name, "wall", name, ((0, 0), (1, 0), (1, 0.4), (0, 0.4)), [tip]))
                plan.append(("Armor_%s_up" % name, "wall", name, ((0, 0.4), (1, 0.4), (1, 1), (0, 1)),
                             [tip, ("R", uw, fold, -(62.0 + lean), (0.08, 0.36))]))
        # the roof over the rear corner rises straight up 0.27 H, a canopy (frames 177-183)
        plan.append(("Armor_roof_rear", "roof", (-99.0, -8.0, 0), None, [("T", Vector((0, 0, 0.27 * H)), (0.04, 0.3))]))
        # the roof's front, over the front corners, in two halves that rise and tip up like visors on their rear
        # edges, a little out (the superfiring turret, frames 38-44): "the front right and left sides, along with
        # the front section of the roof lift up"; the front corners' walls stay (the side shot: 179-198)
        for s, sg in (("L", 1.0), ("R", -1.0)):
            plan.append(("Armor_roof_front_" + s, "roof", (3.4, 99.0, sg), None,
                         [("T", Vector((0, sg * 0.35, 1.6)), (0.06, 0.34)),
                          ("R", Vector((0, 1, 0)), Vector((3.4, S.y0 + sg * 5.0, Z1)), -18.0, (0.12, 0.42))]))
    elif kind == "clamshell":
        for s, sg in (("L", 1.0), ("R", -1.0)):
            piv = Vector((0.0, S.y0 + sg * 8.9, Z1))
            plan.append(("Armor_roof_" + s, "roof", (-99.0, 99.0, sg), None,
                         [("R", Vector((1, 0, 0)), piv, -sg * 62.0, STAGE_ARMOUR)]))
            O, I, u, v, n = S.wall("fside_" + s)
            plan.append(("Armor_fside_" + s, "wall", "fside_" + s, None,
                         [("R", u, (O[0] + O[1]) / 2.0, -sg * 38.0, (0.05, 0.45))]))
    return plan


# ---------------------------------------------------------------------------------------------------- the guns
def rod_x(part, x0, x1, r, y, z, m, seg=24, cap=6):
    """the core rod as one solid of revolution: flat at its root, its tip a hemisphere (the clip's rounded rods)"""
    bm = part._bm(False, False)
    prof = [(x0, r)] + [(x1 - r + r * math.sin(math.pi / 2 * k / cap), r * math.cos(math.pi / 2 * k / cap))
                        for k in range(cap)]
    rings = []
    for x, rr in prof:
        rings.append([bm.verts.new((x, y + rr * math.cos(2 * math.pi * j / seg), z + rr * math.sin(2 * math.pi * j / seg)))
                      for j in range(seg)])
    tip = bm.verts.new((x1, y, z))
    fs = [bm.faces.new(rings[0][::-1])]
    for a, b in zip(rings, rings[1:]):
        for j in range(seg):
            fs.append(bm.faces.new((a[j], a[(j + 1) % seg], b[(j + 1) % seg], b[j])))
    for j in range(seg):
        fs.append(bm.faces.new((rings[-1][j], rings[-1][(j + 1) % seg], tip)))
    bmesh.ops.recalc_face_normals(bm, faces=fs)
    part._put(bm, [v for q in rings for v in q] + [tip], m)


def stays_part(rings=False, breech=False, ring_mat=None, rings_to=None, rails=True, core=None):
    """what doesn't split: each gun's bloomer boot, its barrel's root ring and its core rod (the guns' frame); rings:
    the core assembly round the rod (coil rings on spokes and hubs, four rails through them: style 9, after the user's
    manga panels); breech: the breech, its block and recoil cylinders and the cradle inside the house"""
    p = Part(overlap=True)
    for yc in GUN_Y:
        for x0, x1, r in BOOT:
            cone_x(p, x0, x1, r, r - 0.03, yc, 0.0, M_PAINT, SEG)
        cone_x(p, 2.7, SPLIT + 0.02, 1.12, 1.1, yc, 0.0, M_PAINT, SEG)
        if core:                                            # (r, its tip's x when out, its push): style 10's
            if not core[2]:                                 # rod, a piece of its own when it moves (build)
                rod_x(p, SPLIT - 0.4, core[1], core[0], yc, 0.0, MAT["fm_core"])
        else:
            cone_x(p, SPLIT - 0.4, MUZZLE - 0.7, CORE_R, CORE_R, yc, 0.0, MAT["fm_core"], 24)
        if not rings:
            cone_x(p, SPLIT - 0.05, SPLIT + 0.08, BORE + 0.03, BORE + 0.03, yc, 0.0, M_DARK, 32, cut=True)
        else:
            x = SPLIT + 0.9
            while x < (rings_to or MUZZLE - 1.2):
                torus_x(p, x, yc, 0.0, RING_R, RING_T, ring_mat or M_PAINT, major=16)
                cone_x(p, x - 0.16, x + 0.16, 0.33, 0.33, yc, 0.0, M_DARK, 12, post=True)
                for k in range(4):
                    a = math.radians(45 + 90 * k)
                    d = Vector((0, math.cos(a), math.sin(a)))
                    box(p, Vector((x, yc, 0.0)) + d * ((RING_R + 0.3) / 2.0), (XYZ[0], d, XYZ[0].cross(d)),
                        (0.07, RING_R - 0.28, 0.07), M_PAINT, post=True)
                x += RING_STEP
            for k in range(4 if rails else 0):
                a = math.radians(90 * k)
                cone_x(p, SPLIT + 0.8, x - RING_STEP + 0.1, 0.05, 0.05, yc + RING_R * math.cos(a), RING_R * math.sin(a),
                       M_DARK, 8, post=True)
        if breech:
            cone_x(p, -6.4, -0.3, 1.2, 1.15, yc, 0.0, M_PAINT, 32)
            cone_x(p, -6.9, -6.3, 1.38, 1.38, yc, 0.0, M_DARK, 32)
            abox(p, (-7.4, yc - 0.7, -0.8), (-6.8, yc + 0.7, 0.8), M_PAINT)
            for e in (-1.0, 1.0):
                cone_x(p, -4.2, 0.4, 0.28, 0.28, yc + e * 0.9, 1.0, M_DARK, 16)
            abox(p, (-5.2, yc - 1.0, -1.55), (0.6, yc + 1.0, -1.1), M_PAINT)
    return p


def shell_piece_part(seg, cut=X_MID, shell_t=SHELL_T, bore=0.42, rim=False, edges=False):
    """styles 9 and 10: one section of the barrel's thin shell (a quarter round +y), its rear or its front part (cut
    across at `cut`); its own frame: x from the part's back end, on the barrel's axis. The front part's muzzle closed
    down to a gun's bore. rim: its muzzle face light grey; edges: strips inside along its two cut edges that light as
    the gun fires (style 10, the clip)"""
    p = Part(overlap=True)
    x0, x1 = (SPLIT, cut - 0.02) if seg == "rear" else (cut + 0.02, MUZZLE)
    xr = MUZZLE - 0.05 if rim else MUZZLE + 1.0
    for a, b, r0, r1 in BARREL:
        for lo, hi, m in ((max(a, x0), min(b, x1, xr), M_PAINT), (max(a, x0, xr), min(b, x1), M_RIM)):
            if hi - lo > 1e-3:
                ra = r0 + (r1 - r0) * (lo - a) / (b - a)
                rb = r0 + (r1 - r0) * (hi - a) / (b - a)
                cone_x(p, lo - x0, hi - x0, ra, rb, 0.0, 0.0, m, SEG)
    rin = lambda x: (1.02 - shell_t) + ((0.86 - shell_t) - (1.02 - shell_t)) * (x - SPLIT) / (MUZZLE - SPLIT)
    if edges:                                             # (clear of the inner wall: each length at its narrow end's
        xe = MUZZLE - 0.7 if seg == "front" else x1       # radius, a little in)
        xa = x0 + 0.3
        while xa < xe - 0.3:
            xb = min(xa + 2.0, xe)
            rr = rin(xb) - 0.03
            for th in (math.radians(41.0), -math.radians(41.0)):
                r = Vector((0, math.cos(th), math.sin(th)))
                box(p, Vector(((xa + xb) / 2.0 - x0, 0, 0)) + r * rr, (XYZ[0], r, XYZ[0].cross(r)),
                    (xb - xa - 0.04, 0.03, 0.08), MAT["fm_edge"], post=True)
            xa = xb
    end = x1 + 1.0 if seg == "rear" else MUZZLE - 0.45
    cone_x(p, -1.0, end - x0, rin(x0 - 1.0), rin(end), 0.0, 0.0, M_DARK, SEG, cut=True)
    if seg == "front":
        cone_x(p, MUZZLE - 0.6 - x0, MUZZLE + 1.0 - x0, bore, bore, 0.0, 0.0, M_DARK, SEG, cut=True)
    L = x1 - x0
    half = math.radians(45.0)
    W = 6.0
    for th, sgn in ((-half, -1.0), (half, 1.0)):
        r = Vector((0, math.cos(th), math.sin(th)))
        nrm = Vector((0, -math.sin(th), math.cos(th)))
        box(p, Vector((L / 2.0, 0, 0)) + nrm * (sgn * W / 2.0), (XYZ[0], r, nrm), (L + 4.0, 2 * W, W), M_DARK, cut=True)
    return p


def interior(h, S, moves=None):
    """styles 9, 10: the gun house's inside, seen where its armour opens: a hollow cut into the core behind each aft
    side wall (and forward one) that moves, a doorway into it through a rear corner that opens; a grated floor, frames
    and pipes along its inner wall, a shell hoist, racks of shells, the training gear's big wheel (the clip's drum) aft,
    cabinets forward; the outer guns' breeches (on the guns) show in it. Nothing in it meets another face flat on (the
    union breaks on coplanar contact): what stands on something sinks a little into it; nothing pokes past the core"""
    moves = set(NAMES) if moves is None else moves
    y0 = S.y0
    zf, zt = Z0 + 0.3, Z1 - 0.75                              # (the floor clear of the skirt's top, Z0 + 0.28)
    for sg, s in ((1.0, "L"), (-1.0, "R")):
        Y = lambda v: y0 + sg * v
        lo_hi = lambda a, b: (min(Y(a), Y(b)), max(Y(a), Y(b)))
        Ia, If = S.wall("aside_" + s)[1], S.wall("fside_" + s)[1]

        def core(x):                                          # |y| of the side walls' core at x, from y0
            I = Ia if x < min(If[0].x, If[1].x) else If          # (the aft wall, or the forward one past their corner)
            t = (x - I[0].x) / (I[1].x - I[0].x)
            return abs(I[0].lerp(I[1], t).y - y0)
        bays = ([(-13.6, 2.9)] if "aside_" + s in moves else []) + ([(3.7, 9.6)] if "fside_" + s in moves else [])
        if "rear_%s2" % s in moves:                           # the doorway through the rear corner
            a, b = lo_hi(3.6, 9.0)
            abox(h, (-15.6, a, zf), (-13.4, b, zt), M_DARK, cut=True)
        for x0, x1 in bays:
            a, b = lo_hi(3.6, 15.0)
            abox(h, (x0, a, zf), (x1, b, zt), M_DARK, cut=True)
            reach = lambda x: core(x) - 0.1
            h.prism([(x0 - 0.05, Y(3.55)), (x1 + 0.05, Y(3.55)), (x1 + 0.05, Y(reach(x1))), (x0 - 0.05, Y(reach(x0)))][::int(sg)],
                    "Z", zf - 0.05, zf + 0.1, M_DARK, post=True)                                   # the floor
            x = x0 + 0.4
            while x < x1 - 0.3:                                                                   # its grating
                a, b = lo_hi(3.7, reach(x) - 0.15)
                abox(h, (x - 0.05, a, zf + 0.08), (x + 0.05, b, zf + 0.18), M_PAINT, post=True)
                x += 0.6
            x = x0 + 0.6
            while x < x1 - 0.3:                                                                   # frames
                a, b = lo_hi(3.5, 3.9)
                abox(h, (x - 0.14, a, zf - 0.05), (x + 0.14, b, zt + 0.05), M_PAINT, post=True)
                x += 2.4
            for k, (v, z, r) in enumerate(((4.1, 1.75, 0.14), (4.2, 2.45, 0.1), (4.15, 4.5, 0.16), (4.3, 5.1, 0.1))):
                cyl(h, r, r, x1 - x0 + 0.1, Vector(((x0 + x1) / 2.0, Y(v), z)), (1, 0, 0), M_DARK, 12, post=True)
            if x0 > 0:                                        # forward: cabinets along the inner wall, past the pipes
                for x in (4.6, 6.0, 7.4, 8.8):
                    a, b = lo_hi(4.5, 5.25)
                    abox(h, (x - 0.55, a, zf + 0.05), (x + 0.55, b, zf + 2.3), M_PAINT, post=True)
                    a, b = lo_hi(5.24, 5.3)
                    abox(h, (x - 0.45, a, zf + 0.3), (x + 0.45, b, zf + 2.1), M_DARK, post=True)
                continue
            # aft: the shell hoist, two racks of shells (inside the core's line), the rammer's rail
            cyl(h, 0.95, 0.95, zt - zf + 0.1, Vector((-9.6, Y(6.6), (zf + zt) / 2.0)), (0, 0, 1), M_PAINT, 24, post=True)
            for z in (zf + 0.9, zt - 1.0):
                cyl(h, 1.05, 1.05, 0.18, Vector((-9.6, Y(6.6), z)), (0, 0, 1), M_DARK, 24, post=True)
            for row, z in enumerate((1.4, 2.0)):
                for k in range(4):
                    c = Vector((-13.4 + 0.6 * k, Y(7.6), z))
                    cyl(h, 0.26, 0.26, 1.2, c, (0, sg, 0), M_PAINT, 12, post=True)
                    cyl(h, 0.26, 0.02, 0.45, c + Vector((0, sg * 0.8, 0)), (0, sg, 0), M_DARK, 12, post=True)
            a, b = lo_hi(8.3, 8.5)
            abox(h, (-13.55, a, zf + 0.05), (-11.0, b, 2.4), M_DARK, post=True)
            a, b = lo_hi(5.2, 5.6)
            abox(h, (-10.2, a, 2.4), (-6.6, b, 2.7), M_PAINT, post=True)
            # the training gear's big wheel by the outer gun (the clip's round drum), its teeth, its hub
            gc = Vector((-2.6, Y(8.0), 2.95))
            cyl(h, 1.65, 1.65, 0.45, gc, (0, 1, 0), M_PAINT, 40, post=True)
            cyl(h, 0.55, 0.55, 0.8, gc, (0, 1, 0), M_DARK, 20, post=True)
            for k in range(30):
                a = 2 * math.pi * k / 30
                r = Vector((math.cos(a), 0, math.sin(a)))
                box(h, gc + r * 1.72, (r, XYZ[1], XYZ[1].cross(r)), (0.18, 0.4, 0.16), M_DARK, post=True)


def piece_part(n_split):
    """one barrel piece: the barrel forward of SPLIT inside the sector of 360/n deg round +y (its own frame: x along
    the barrel from the split, on its axis), the bore through it lit, bracket rings along the bore"""
    p = Part(overlap=True)
    for x0, x1, r0, r1 in BARREL:
        cone_x(p, x0 - SPLIT, x1 - SPLIT, r0, r1, 0.0, 0.0, M_PAINT, SEG)
    L = MUZZLE - SPLIT
    half = math.radians(180.0 / n_split)
    W = 6.0
    for th, sgn in ((-half, -1.0), (half, 1.0)):
        r = Vector((0, math.cos(th), math.sin(th)))
        nrm = Vector((0, -math.sin(th), math.cos(th)))
        box(p, Vector((L / 2.0, 0, 0)) + nrm * (sgn * W / 2.0), (XYZ[0], r, nrm), (L + 4.0, 2 * W, W), M_DARK, cut=True)
        if n_split == 2:
            break
    cone_x(p, -1.0, L + 1.0, BORE, BORE, 0.0, 0.0, M_DARK, SEG, cut=True)
    x = 1.2
    while x < L - 1.0:
        arc_tube(p, x, BORE - 0.01, -half + math.radians(9), half - math.radians(9), 0.075, M_PAINT)
        x += 2.1
    return p


# ---------------------------------------------------------------------------------------------------- building
PROTO = {}


def solid(name, part, size, J=None, bevel=0.05):
    me, proto = part.solid("TANA_T16_" + name, bevel=bevel)
    if BAKE:
        tanakit.bake(me, proto, "T16_" + name, size)
    if J is not None:
        me.transform(Matrix.Translation(-J))
    proto.hide_render = proto.hide_viewport = True
    PROTO[name] = me
    return me


def turned(me, deg, name):
    """a barrel piece's mesh turned round its axis to its sector (sharing one texture)"""
    m = me.copy()
    m.name = "TANA_T16_" + name
    m.transform(Matrix.Rotation(math.radians(deg), 4, "X"))
    PROTO[name] = m
    return m


def ops_matrix(ops, t):
    M = Matrix()
    for op in ops:
        f = smooth(t, *op[-1])
        if op[0] == "T":
            M = M @ Matrix.Translation(Vector(op[1]) * f)
        else:
            p = Vector(op[2])
            M = M @ Matrix.Translation(p) @ Matrix.Rotation(math.radians(op[3]) * f, 4, Vector(op[1])) @ \
                Matrix.Translation(-p)
    return M


def to_json(ops):
    return json.dumps([[o[0]] + [list(x) if isinstance(x, Vector) else x for x in o[1:]] for o in ops])


class Turret:
    def __init__(self, tag):
        self.tag = tag
        self.house = bpy.data.objects["LEV_T16_%s.001" % tag]
        self.trun = bpy.data.objects["LEV_G16_%s_trunnion" % tag]
        self.gun = bpy.data.objects["LEV_G16_%s.001" % tag]
        yaw = round(self.trun.rotation_euler.z / (math.pi / 2)) * (math.pi / 2)
        self.R = Matrix.Rotation(yaw, 4, "Z")
        self.pieces_, self.rest = [], {}

    def pieces(self):
        return list(self.pieces_)

    def pose(self, t):
        for ob in self.pieces_:
            ob.matrix_basis = self.rest[ob.name] @ ops_matrix(json.loads(ob["fm_ops"]), t)


TURRET = {}
INFO = {}


def style_of(n=None):
    if n is None:
        n = int(os.environ.get("TANA_FM_STYLE", str(DEFAULT_STYLE)))
    return n, (STYLES.get(n) if n else None)


def armour_piece(S, st, bone, k, nm, region, ops):
    """one moving armour piece's Part (the turret's frame) and its origin"""
    p = Part(overlap=True)
    tr = sum((Vector(o[1]) for o in ops if o[0] == "T"), Vector())
    if k == "wall":
        reg = region or WHOLE
        if len(reg) == 4:
            slab(p, S, nm, reg)
        else:                                     # a stepped shape: its (along, up) bounds stand for it below
            poly_slab(p, S, nm, reg)
            ss, ws = [a for a, _ in reg], [b for _, b in reg]
            reg = ((min(ss), min(ws)), (max(ss), min(ws)), (max(ss), max(ws)), (min(ss), max(ws)))
        if st.get("circuit"):
            circuit(p, S, nm, reg, sum(map(ord, bone)))
        if nm.startswith("aside") and reg[3][1] > 0.9 and reg[0][0] < 0.19 < reg[1][0]:      # (the ear is 0.19 along)
            ears(p, S, 1.0 if nm.endswith("L") else -1.0)
        O, I, u, v, n = S.wall(nm)
        if nm.startswith("fside") and reg[3][1] > 0.9:
            c = Shell.at(O, 0.75, (reg[0][1] + reg[3][1]) / 2.0 if region else 0.62)
            box(p, c + n * 0.02, (u, n.cross(u).normalized(), n), (0.9, 0.13, 0.06), MAT["fm_slit"], post=True)
        if tr.length > 0.3 and st.get("struts", True):     # (into the house's hollow: arms long enough to reach it)
            struts(p, S, nm, reg, tr, *((6.0, 0.85) if st.get("interior") else ()))
        J = sum([Shell.at(O, s, w) for s, w in (region or WHOLE)], Vector()) / len(region or WHOLE)
    else:
        x_lo, x_hi, side = nm
        roof_slab(p, S, x_lo=None if x_lo < -90 else x_lo, x_hi=None if x_hi > 90 else x_hi, side=side)
        roof_details(p, S, x_lo, x_hi, side)
        cx = (max(x_lo, -14.0) + min(x_hi, 10.0)) / 2.0
        J = Vector((cx, S.y0 + side * 4.5, Z1))
        if tr.length > 0.3:
            L = tr.length + 1.2
            for dy in ((-3.5, 3.5) if not side else (side * 2.5, side * 6.5)):
                cyl(p, 0.22, 0.22, L, Vector((cx, S.y0 + dy, S.zc + 0.1)) - tr.normalized() * (L / 2.0), tr, M_PAINT, 16)
    return p, J


def build(coll, log=print, style=None):
    """the style's mount on both turrets (their house, gun and trunnion objects changed in place), its moving pieces
    into `coll`; tanakit.WORK and tanakit.TEX set by the caller. Style 0: nothing (the design's Iowa mount stays)"""
    global FLASH
    n, st = style_of(style)
    if not st:
        log("firemode: style 0, the design's mount kept")
        return TURRET
    FLASH = CLIP["flash"] if st["barrel"].get("clip") else None
    bpy.context.scene.frame_set(1)
    first = Turret("FWD")
    tl = first.R.inverted() @ first.trun.matrix_basis.translation
    S = Shell(tl.y, tl.z)
    plan = armour_plan(st, S)
    moves = {nm for _, k, nm, _, _ in plan if k == "wall"}
    roof_moves = any(k == "roof" for _, k, _, _, _ in plan)
    # the house: the core, its skirt, every armour slab that stays, the roof if it stays, the bays under what moves
    h = Part(overlap=True)
    loft(h, S.Bc, Z0 - 0.3, S.Tc, S.zc, M_DARK)
    h.prism(offset2d(S.B, 0.22), "Z", 0.0, Z0 + 0.28)
    for name in NAMES:
        if name in moves:
            if not st.get("interior"):
                bay(h, S, name)
        else:
            slab(h, S, name)
            if st.get("circuit"):
                circuit(h, S, name, WHOLE, sum(map(ord, name)))
    if st.get("roof_static"):                                # part of the roof stays; under the rest, fins
        lo, hi = st["roof_static"]
        roof_slab(h, S, x_lo=None if lo < -90 else lo, x_hi=None if hi > 90 else hi)
        roof_details(h, S, lo, hi)
        x = hi + 0.5
        while x < 9.6:
            abox(h, (x - 0.08, S.y0 - 6.0, S.zc - 0.02), (x + 0.08, S.y0 + 6.0, S.zc + 0.3), M_PAINT, post=True)
            x += 0.6
        x = lo - 0.5
        while x > -13.8:                                      # (and aft, under a rear block that rises)
            abox(h, (x - 0.08, S.y0 - 5.0, S.zc - 0.02), (x + 0.08, S.y0 + 5.0, S.zc + 0.3), M_PAINT, post=True)
            x -= 0.6
    elif not roof_moves:
        roof_slab(h, S)
        roof_details(h, S)
    else:                                                   # under the roof: a dark floor and heat-sink fins
        q = offset2d(S.Tc, -0.3)
        loft(h, q, S.zc - 0.05, q, S.zc + 0.04, M_DARK, post=True)
        x = min(p[0] for p in q) + 0.6
        while x < max(p[0] for p in q) - 0.6:
            abox(h, (x - 0.08, S.y0 - 6.0, S.zc), (x + 0.08, S.y0 + 6.0, S.zc + 0.32), M_PAINT, post=True)
            x += 0.6
    for s, sg in (("L", 1.0), ("R", -1.0)):
        if "aside_" + s not in moves:
            ears(h, S, sg)
    gun_wells(h, S)
    face_lights(h, S)
    if st.get("interior"):
        interior(h, S, moves)
    house = solid("house", h, 2048)
    armour = []
    for bone, k, nm, region, ops in plan:
        p, J = armour_piece(S, st, bone, k, nm, region, ops)
        armour.append((bone, solid(bone, p, 1024, J), J, ops))
    # the guns: the fixed parts, and one barrel piece turned round to each sector
    bs = st["barrel"]
    stays = solid("stays", stays_part(rings=bs.get("mid", False), breech=st.get("interior", False),
                                      ring_mat=MAT["fm_ring"] if st.get("rings_glow") else None,
                                      rings_to=st.get("rings_to"), rails=not st.get("rings_to"),
                                      core=st.get("core")), 1024, bevel=0)
    angles = SPLITS[bs["split"]]
    cut = bs.get("cut", X_MID)
    core, rod_me = st.get("core"), None
    if core and core[2]:                                  # style 10: the rod moves (its tip at core[1] once out)
        rp = Part()
        rod_x(rp, SPLIT - 0.4, core[1] - core[2], core[0], 0.0, 0.0, MAT["fm_core"])
        rod_me = solid("core", rp, 256, bevel=0)
    if bs.get("mid"):                                     # styles 9, 10: eight shell pieces a gun, rear and front parts
        segs = {}
        for seg in ("rear", "front"):
            base = solid("piece_" + seg, shell_piece_part(seg, cut, bs.get("shell_t", SHELL_T), bs.get("bore", 0.42),
                                                          bs.get("rim", False), bs.get("edges", False)), 512, bevel=0)
            segs[seg] = [turned(base, a, "piece_%s_%d" % (seg, k + 1)) for k, a in enumerate(angles)]
            del PROTO["piece_" + seg]
        pieces = None
    else:
        base = solid("piece", piece_part(len(angles)), 512, bevel=0)
        pieces = [turned(base, a, "piece_%d" % (k + 1)) for k, a in enumerate(angles)]
        del PROTO["piece"]
    INFO.update({"style": n, "name": st["name"], "trunnion_m": list(S.trun), "muzzle_m": MUZZLE,
                 "extend_m": bs.get("extend", 0.0), "split": bs["split"]})
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
        T.trun.location = T.R @ S.trun
        T.gun.matrix_basis = Matrix()

        def add(bone, me, parent, basis, part, ops, extra=None):
            ob = bpy.data.objects.new("TANA_T16_%s_%s" % (tag, bone), me)
            coll.objects.link(ob)
            ob.parent = parent
            ob.matrix_parent_inverse = Matrix()
            ob.matrix_basis = basis
            ob["fm_part"], ob["fm_bone"], ob["fm_ops"] = part, bone, to_json(ops)
            for k2, v2 in (extra or {}).items():
                ob[k2] = v2
            T.rest[ob.name] = basis.copy()
            T.pieces_.append(ob)
            return ob
        for bone, me, J, ops in armour:
            # the ops about the piece's origin J (its axes the turret's)
            local = [o if o[0] == "T" else (o[0], o[1], Vector(o[2]) - J, o[3], o[4]) for o in ops]
            add(bone, me, T.house, T.R @ Matrix.Translation(J), "ARMOR", local)
        for b, yc in enumerate(GUN_Y, 1):
            if pieces is None:
                for j, seg in enumerate(("rear", "front")):
                    x0 = SPLIT if seg == "rear" else cut + 0.02
                    L = (cut - 0.02 - SPLIT) if seg == "rear" else (MUZZLE - x0)
                    for k, a in enumerate(angles):
                        d = Vector((0, math.cos(math.radians(a)), math.sin(math.radians(a))))
                        if bs.get("clip"):              # the clip: quarters out, fronts back, staves pitched up
                            st_ = CLIP["stages"]
                            up = CLIP["pitch"][0 if abs(d.y) > 0.5 else (1 if d.z > 0 else 2)]
                            ops = [("T", d * CLIP["part"], st_["part"])]
                            if seg == "front":          # (its turn about the stave's root: the rear half's back end)
                                ops += [("T", d * CLIP["front_out"], st_["out"]),
                                        ("R", Vector((0, 1, 0)), Vector((SPLIT - x0, 0, 0)) - d * CLIP["front_out"],
                                         -up, st_["pitch"]),
                                        ("T", Vector((-CLIP["back"] * CLIP["back_first"], 0, 0)), st_["back1"]),
                                        ("T", Vector((-CLIP["back"] * (1 - CLIP["back_first"]), 0, 0)), st_["back2"])]
                            else:
                                ops.append(("R", Vector((0, 1, 0)), Vector((0, 0, 0)), -up, st_["pitch"]))
                        else:
                            xp = 0.0 if a == 90 else (L if a == 270 else L / 2.0)   # top: its back, bottom: its front
                            ops = [("T", d * MID_OUT[seg], MID_STAGES[0]),
                                   ("T", Vector((-MID_BACK[seg], 0, 0)), MID_STAGES[1]),
                                   ("R", Vector((0, 1, 0)), Vector((xp, 0, 0)) + d * 1.0, -MID_TILT, MID_STAGES[2])]
                        add("Barrel_%d_%d" % (b, j * 4 + k + 1), segs[seg][k], T.trun, Matrix.Translation((x0, yc, 0.0)),
                            "GUNS", ops, {"fm_dir": a, "fm_barrel": b, "fm_x0": x0, "fm_len": L})
                if rod_me is not None:                  # the rod, pushed forward once the staves are back
                    add("Barrel_%d_9" % b, rod_me, T.trun, Matrix.Translation((0.0, yc, 0.0)), "GUNS",
                        [("T", Vector((core[2], 0, 0)), CLIP["stages"]["push"])],
                        {"fm_barrel": b, "fm_rod": True, "fm_tip": core[1]})
                continue
            for k, a in enumerate(angles):
                d = Vector((0, math.cos(math.radians(a)), math.sin(math.radians(a))))
                ops = []
                if bs.get("slide") or bs.get("extend"):
                    ops.append(("T", d * bs.get("slide", 0.0) + Vector((bs.get("extend", 0.0), 0, 0)), STAGE_BARREL))
                if bs.get("hinge"):
                    ops.append(("R", Vector((1, 0, 0)).cross(d), d * 1.06, bs["hinge"], STAGE_BARREL))
                add("Barrel_%d_%d" % (b, k + 1), pieces[k], T.trun, Matrix.Translation((SPLIT, yc, 0.0)), "GUNS", ops,
                    {"fm_dir": a, "fm_barrel": b})
    tris = {k: sum(len(f.vertices) - 2 for f in me.polygons) for k, me in PROTO.items()}
    per = tris["house"] + tris["stays"] + sum(v for k, v in tris.items() if k.startswith("Armor")) + \
        3 * sum(v for k, v in tris.items() if k.startswith("piece"))
    log("firemode: style %d (%s): %d moving armour pieces, %d barrel pieces a gun; %d triangles a turret" % (
        n, st["name"], len(armour), len(angles) * (2 if pieces is None else 1), per))
    pose(0.0)
    return TURRET


def attach(log=print):
    """the registry again from a saved model (the pieces' rest = their pose at frame 1, before KEYS' deploy)"""
    bpy.context.scene.frame_set(1)
    for tag in TURRETS:
        T = Turret(tag)
        T.pieces_ = sorted((o for o in bpy.data.objects if o.name.startswith("TANA_T16_%s_" % tag) and "fm_ops" in o),
                           key=lambda o: o.name)
        T.rest = {o.name: o.matrix_basis.copy() for o in T.pieces_}
        TURRET[tag] = T
    return TURRET


def pose(t, fire=0.0):
    for T in TURRET.values():
        T.pose(t)
    glow(t, fire)


def key(log=print):
    """the transform keyed into the model's timeline: deploy at KEYS[0], stow at KEYS[1] (every second frame, linear)"""
    if not TURRET:
        return
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
