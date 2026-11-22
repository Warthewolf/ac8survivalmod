"""make_portal.py : VALKA's portal, a black hole's event horizon (docs/re/VALKA.md section 8), modelled in Blender 3.3 as
3D meshes, each exported as a glTF, in one of several designs.

  blender -b -P tools/valka_portal/make_portal.py -- <out folder> [design]

The user, 2026-11-22: "Can you make custom 3D assets for this in Blender and Unreal Engine Editor please", "I want the
portal to look like an event horizon from a black hole" (Interstellar's Gargantua and the like), "Needs to be a 3D model,
not a png floating in the air", "rebuild the Event Horizon Model so that its more detailed and is animated to show it
moving", "I want a higher detailed model, more looking like this" (a picture: a huge black shadow ringed by a crisp thin
photon ring; the disk's lensed image a broad, glowing arch over the top, white-hot at the shadow and fading to orange,
broadest on the approaching (left) side; the disk a wide bright band across the lower part of the shadow, swirling out
into darker spiral arms and sparks), "Does it have to have the lines styling on the disc? Can't you give me several
different designs that look closer to what I'm after?". The designs:
  lines    the disk and the arch as streaks in rings (v3, 0.74.211's preview)
  soft     no lines, no hard edges: many faint layers, each a little further out, wavier and warmer: a gradient
  detailed the most detailed (the user: "as detailed as you can make it"): ~3,500 wisps shaped by noise (pinched,
           wobbling, spiralling in, tapering to points) in eight bands white-hot to dark red with hot knots and dark
           lanes, the disk flaring thicker outwards; the arch made from the disk's own far side bent over the
           shadow (and a thin second image under it), swept out into the disk at both sides, hotter on the
           approaching side; noisy infall streams, sparks, and soft haze layers for a see-through glow
  smooth   no lines: the arch and the disk as continuous see-through layers, white-hot inside to orange and red outside
  glow     soft volumes: the disk as flattened rings and the arch as tubes in AC8's fresnel glow (bright where you see them
           edge-on), a thin bright core under them
  silk     hundreds of fine, faint strands, no gaps, thickest near the shadow: a smooth glow from afar, fibres close up
  hybrid   smooth's layers under a few of silk's strands, the spiral arms and sparks
Every piece is real geometry made here from numbers (no source art, no texture: AC8's own materials colour each piece in
game, hard rule 58), in units of the shadow's diameter (1.0), its symmetry axis +Z. In game (sv_anomalies_valka.lua) the
shadow, the photon ring and the arch pieces (`faces`) face you, the disk pieces lie tipped towards you, each turning at
its own speed (`spin`), and the whole hole keeps facing you. Each design's <out>/<design>/manifest.json lists its pieces
with the material each takes in game (`ring`: MI_TrainingRing, `glow`: MI_TrainingRingGlow, `shadow`: the flat black),
its colour, opacity and spin (tools/valka_portal/preview.py draws it from there). UVs: U along the orbit, V across.
Prints `portal: <name> <verts> verts <tris> tris` for each and `portal: done` at the end (tools/valka_portal/build.sh).
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy

ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
ROOT = ARGS[0] if ARGS else os.path.join(os.getcwd(), 'build', 'valka_portal', 'src')
DESIGN = ARGS[1] if len(ARGS) > 1 else 'detailed'
OUT = os.path.join(ROOT, DESIGN)
os.makedirs(OUT, exist_ok=True)
random.seed(20261122)
TAU = 2 * math.pi
R0 = 0.5                                           # the shadow's radius
MANIFEST = []


def finish(name, bm, kind, rgb, opacity=1.0, faces=False, spin=0.0, smooth=True, **extra):
    """bm -> an object `name`, one material slot, triangulated, exported as <OUT>/<name>.glb; its manifest entry"""
    bmesh.ops.triangulate(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(bpy.data.materials.new('M_' + name))
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    path = os.path.join(OUT, name + '.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_materials='PLACEHOLDER', export_texcoords=True, export_normals=True)
    print(f'portal: {name} {len(me.vertices)} verts {len(me.polygons)} tris -> {path}')
    MANIFEST.append(dict(name=name, kind=kind, rgb=list(rgb), opacity=opacity, faces=faces, spin=spin,
                         tris=len(me.polygons), **extra))
    bpy.data.objects.remove(ob)


# ---- shapes ----
def strip(bm, uv, a0, a1, rin, rout, z, segs, u_rep=4.0):
    """a sheet in the XY plane from angle a0 to a1 between radius rin(a) and rout(a), at height z(a); both faces drawn
    (AC8's materials draw one side). U along the angle (u_rep a turn), V across."""
    n = max(2, int(segs * abs(a1 - a0) / TAU) + 1)
    rows = []
    for s in range(n + 1):
        a = a0 + (a1 - a0) * s / n
        ri, ro = rin(a), max(rin(a) + 1e-4, rout(a))
        ca, sa, zz = math.cos(a), math.sin(a), z(a)
        rows.append((bm.verts.new((ri * ca, ri * sa, zz)), bm.verts.new((ro * ca, ro * sa, zz)), a / TAU * u_rep))
    for s in range(n):
        (p0, p1, u0), (q0, q1, u1) = rows[s], rows[s + 1]
        f = bm.faces.new((p0, p1, q1, q0))
        for loop, t in zip(f.loops, ((u0, 0), (u0, 1), (u1, 1), (u1, 0))):
            loop[uv].uv = t
        g = bm.faces.new(tuple(bm.verts.new(v.co) for v in (q0, q1, p1, p0)))
        for loop, t in zip(g.loops, ((u1, 0), (u1, 1), (u0, 1), (u0, 0))):
            loop[uv].uv = t


def broken(a0, a1, piece_deg, gap_p, gap_deg):
    """[a0, a1] cut into pieces about piece_deg long, a gap of up to gap_deg after each with chance gap_p"""
    out, a = [], a0
    while a < a1 - 1e-3:
        b = min(a1, a + math.radians(random.uniform(piece_deg * 0.5, piece_deg * 1.5)))
        out.append((a, b))
        a = b
        if random.random() < gap_p:
            a += math.radians(random.uniform(gap_deg * 0.2, gap_deg))
    return out


def torus(bm, uv, R, a_r, a_z, segs, rings, a0=0.0, a1=TAU, tube=None):
    """a torus of radius R round +Z, its tube a_r across (in the plane) by a_z (up), an ellipse; from angle a0 to a1
    (a part: open ends); tube(a) -> a scale of the tube at angle a (the arch's tubes: thickest over the top)"""
    full = abs(a1 - a0 - TAU) < 1e-6
    n = segs if full else segs + 1
    grid = []
    for j in range(n):
        a = a0 + (a1 - a0) * j / segs
        k = tube(a) if tube else 1.0
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for i in range(rings):
            b = TAU * i / rings
            rr = R + a_r * k * math.cos(b)
            ring.append(bm.verts.new((rr * ca, rr * sa, a_z * k * math.sin(b))))
        grid.append(ring)
    for j in range(segs):
        j2 = (j + 1) % n if full else j + 1
        for i in range(rings):
            i2 = (i + 1) % rings
            f = bm.faces.new((grid[j][i], grid[j2][i], grid[j2][i2], grid[j][i2]))
            for loop, t in zip(f.loops, ((j / segs, i / rings), ((j + 1) / segs, i / rings),
                                         ((j + 1) / segs, (i + 1) / rings), (j / segs, (i + 1) / rings))):
                loop[uv].uv = t


def arch_width(a, top):
    """the arch's breadth at angle a (0 +X, 90 the top): broad over the top, broadest towards -X's side (the approaching
    side), running further down that side into the disk, gone underneath"""
    s = math.sin(a)
    low = -0.34 if math.cos(a) < 0 else -0.12
    if s < low:
        return 0.0
    base = max(0.0, (s - low) / (1 - low)) ** 0.7
    return top * base * (1.0 + 0.45 * math.cos(a - math.radians(125)))


ARCH_A0, ARCH_A1 = -math.radians(8), math.pi + math.radians(21)


def crescent(bm, uv, r_in, top, segs=480, feather=0.0):
    """the arch as one continuous sheet from r_in out to r_in + arch_width(a, top); `feather`: its outer edge wavy"""
    strip(bm, uv, ARCH_A0, ARCH_A1, lambda a: r_in,
          lambda a: r_in + arch_width(a, top) * (1 - feather * (0.5 + 0.5 * math.sin(a * 23 + 1.3) * math.sin(a * 7))),
          lambda a: 0.0, segs)


def annulus(bm, uv, r_in, r_out, z=0.0, segs=360, rout=None):
    strip(bm, uv, 0.0, TAU, lambda a: r_in, rout or (lambda a: r_out), lambda a: z, segs, u_rep=4.0 * r_in)


def strands(bm, uv, count, r_from, r_to, bias, w_rng, len_deg, z_amp, arc=None, rfun=None):
    """`count` fine strands between r_from and r_to (bias > 1: more near r_from), each w_rng wide, len_deg long, a
    little up or down; arc: (a0, a1) to keep them in (the arch); rfun(a, f): their radius at angle a (f: how far out)"""
    for _ in range(count):
        f = random.random() ** bias
        r = r_from + (r_to - r_from) * f
        w = random.uniform(*w_rng) * (0.6 + 0.8 * f)
        z0 = random.uniform(-z_amp, z_amp) * r
        if arc:
            a = random.uniform(arc[0], arc[1] - 0.3)
            b = min(arc[1], a + math.radians(random.uniform(*len_deg)))
        else:
            a = random.uniform(0, TAU)
            b = a + math.radians(random.uniform(*len_deg))
        if rfun:
            strip(bm, uv, a, b, lambda x, f=f: rfun(x, f), lambda x, f=f, w=w: rfun(x, f) + w, lambda x, z0=z0: z0, 360)
        else:
            strip(bm, uv, a, b, lambda x, r=r: r, lambda x, r=r, w=w: r + w, lambda x, z0=z0: z0, 360, u_rep=4.0 * r)


def new():
    bm = bmesh.new()
    return bm, bm.loops.layers.uv.verify()


# ---- the pieces every design has ----
def shadow():
    bm, uv = new()
    bmesh.ops.create_uvsphere(bm, u_segments=128, v_segments=64, radius=R0)
    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (0.5 + math.atan2(co.y, co.x) / TAU, 0.5 + co.z)
    finish('SM_SV_BHShadow', bm, 'shadow', (0, 0, 0), faces=True)


def photon_ring():
    bm, uv = new()
    for R, tube in ((0.506, 0.0055), (0.523, 0.0025), (0.538, 0.0016)):
        torus(bm, uv, R, tube, tube, 288, 8)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    finish('SM_SV_BHPhotonRing', bm, 'ring', (1.0, 0.96, 0.9), faces=True, pulse=[0.2, 3.1])


def halo_lower():
    bm, uv = new()
    strip(bm, uv, math.pi + 0.3, TAU - 0.3, lambda a: R0 + 0.012,
          lambda a: R0 + 0.012 + 0.012 * (0.3 + 0.7 * abs(math.sin(a))), lambda a: 0.0, 360)
    finish('SM_SV_BHHaloLower', bm, 'ring', (1.0, 0.62, 0.3), opacity=0.5, faces=True)


def swirl(opacity=0.4):
    """spiral arms out at the disk's edge: from r 2.9-3.5 winding in to 1.2-1.6, each broad and broken"""
    bm, uv = new()
    arms = 9
    for k in range(arms):
        a0 = TAU * k / arms + random.uniform(-0.25, 0.25)
        turns = random.uniform(0.35, 0.6)
        r_out, r_in = random.uniform(2.9, 3.5), random.uniform(1.2, 1.6)
        w0 = random.uniform(0.03, 0.07)
        zs = random.uniform(-0.01, 0.01)
        for p, q in broken(0.0, TAU, 70, 0.35, 25):
            t0, t1 = p / TAU, q / TAU
            n = max(2, int(120 * (t1 - t0)))
            prev = None
            for s in range(n + 1):
                t = t0 + (t1 - t0) * s / n
                r = r_out * (r_in / r_out) ** t             # (a log spiral, inwards)
                w = w0 * (0.4 + 0.6 * math.sin(math.pi * t)) * (r / r_out) ** 0.3
                a = a0 + TAU * turns * t
                ca, sa = math.cos(a), math.sin(a)
                pts = (bm.verts.new(((r - w / 2) * ca, (r - w / 2) * sa, zs * r)),
                       bm.verts.new(((r + w / 2) * ca, (r + w / 2) * sa, zs * r)))
                if prev:
                    f = bm.faces.new((prev[0], prev[1], pts[1], pts[0]))
                    g = bm.faces.new(tuple(bm.verts.new(v.co) for v in (pts[0], pts[1], prev[1], prev[0])))
                    for face in (f, g):
                        for loop, tt in zip(face.loops, ((t, 0), (t, 1), (t, 1), (t, 0))):
                            loop[uv].uv = tt
                prev = pts
    finish('SM_SV_BHSwirl', bm, 'ring', (0.9, 0.42, 0.12), opacity=opacity, spin=0.3)


def sparks():
    bm, uv = new()
    for _ in range(300):
        r = 0.55 + 3.0 * random.random() ** 1.8
        a = random.uniform(0, TAU)
        c = (r * math.cos(a), r * math.sin(a), random.uniform(-0.02, 0.02) * r)
        sz = random.uniform(0.0015, 0.004) * (1 + 0.3 * r)
        t = (-math.sin(a), math.cos(a))
        L = sz * random.uniform(1.5, 4.0)
        pts = [(c[0] + t[0] * L, c[1] + t[1] * L, c[2]), (c[0] - t[0] * L, c[1] - t[1] * L, c[2]),
               (c[0] + math.cos(a) * sz, c[1] + math.sin(a) * sz, c[2]), (c[0] - math.cos(a) * sz, c[1] - math.sin(a) * sz, c[2]),
               (c[0], c[1], c[2] + sz), (c[0], c[1], c[2] - sz)]
        vs = [bm.verts.new(p) for p in pts]
        for e in ((0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)):
            f = bm.faces.new([vs[i] for i in e])
            for loop, tt in zip(f.loops, ((0, 0), (1, 0), (0.5, 1))):
                loop[uv].uv = tt
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    finish('SM_SV_BHSparks', bm, 'ring', (1.0, 0.92, 0.75), opacity=0.9, spin=0.5, smooth=False)


def infall(opacity=0.7):
    """six filaments spiralling in from the disk's inner edge (r 0.78) to the shadow, a turn and a half each"""
    bm, uv = new()
    span = 1.5 * TAU
    for k in range(6):
        a0 = TAU * k / 6 + random.uniform(-0.2, 0.2)
        strip(bm, uv, a0, a0 + span, lambda a, a0=a0: R0 + 0.28 * (1 - (a - a0) / span) ** 1.3,
              lambda a, a0=a0: R0 + 0.28 * (1 - (a - a0) / span) ** 1.3 + 0.002 + 0.01 * (1 - (a - a0) / span),
              lambda a: 0.0, 200)
    finish('SM_SV_BHInfall', bm, 'ring', (1.0, 0.85, 0.6), opacity=opacity, spin=1.6)


# ---- the disk's and the arch's layers, white-hot inside to red outside ----
SMOOTH_DISK = [(0.55, 0.95, (1.0, 0.95, 0.86), 0.85, 1.0),     # (r from, r to, colour, opacity, spin)
               (0.55, 1.45, (1.0, 0.8, 0.5), 0.5, 0.66),
               (0.58, 2.05, (1.0, 0.58, 0.22), 0.32, 0.44),
               (0.65, 2.75, (0.85, 0.36, 0.1), 0.2, 0.28),
               (0.8, 3.6, (0.5, 0.16, 0.05), 0.12, 0.18)]
SMOOTH_ARCH = [(0.075, (1.0, 0.96, 0.88), 0.95), (0.14, (1.0, 0.8, 0.5), 0.6), (0.22, (1.0, 0.58, 0.22), 0.4),
               (0.32, (0.8, 0.3, 0.08), 0.25)]                    # (breadth over the top, colour, opacity)


def smooth_arch(feather):
    for k, (top, rgb, op) in enumerate(SMOOTH_ARCH):
        bm, uv = new()
        crescent(bm, uv, R0 + 0.004, top, feather=feather * k / 3)
        finish(f'SM_SV_BHArch{k + 1}', bm, 'ring', rgb, opacity=op, faces=True, pulse=[0.12, 1.3 + 0.4 * k])


def smooth_disk(opacity_x=1.0):
    """five continuous layers (each one's outer edge a little wavy, so they don't read as hard rings), and the
    approaching side's brighter half"""
    for k, (ra, rb, rgb, op, spin) in enumerate(SMOOTH_DISK):
        bm, uv = new()
        waves, ph = random.randint(5, 9), random.uniform(0, TAU)
        annulus(bm, uv, ra, rb, segs=480, rout=lambda a, rb=rb, w=waves, ph=ph: rb * (1 + 0.035 * math.sin(w * a + ph)))
        finish(f'SM_SV_BHDisk{k + 1}', bm, 'ring', rgb, opacity=op * opacity_x, spin=spin)
    bm, uv = new()                                   # (the approaching side: -X's half, thinning off its middle)
    strip(bm, uv, math.pi / 2, 3 * math.pi / 2, lambda a: 0.55, lambda a: 0.55 + 0.9 * abs(math.cos(a)) ** 0.8,
          lambda a: 0.0, 360)
    finish('SM_SV_BHDiskBright', bm, 'ring', (1.0, 0.96, 0.9), opacity=0.45 * opacity_x)


# ---- the designs ----
def d_smooth():
    shadow(); photon_ring(); halo_lower()
    smooth_arch(0.0)
    smooth_disk()
    infall(0.5)


def d_glow():
    shadow(); photon_ring(); halo_lower()
    bm, uv = new()                                   # (a thin bright core under the glow)
    crescent(bm, uv, R0 + 0.004, 0.06)
    finish('SM_SV_BHArch1', bm, 'ring', (1.0, 0.95, 0.85), opacity=0.9, faces=True, pulse=[0.12, 1.3])
    for k, (top, rgb) in enumerate(((0.16, (1.0, 0.75, 0.4)), (0.3, (1.0, 0.5, 0.15)))):
        bm, uv = new()
        torus(bm, uv, R0 + top / 2, top / 2, top / 2 * 0.25, 240, 16, ARCH_A0, ARCH_A1,
              tube=lambda a, top=top: max(0.05, arch_width(a, top) / top))
        finish(f'SM_SV_BHArch{k + 2}', bm, 'glow', rgb, opacity=0.6, faces=True, pulse=[0.1, 1.1 + 0.5 * k])
    bm, uv = new()
    annulus(bm, uv, 0.55, 1.0, segs=480)
    finish('SM_SV_BHDisk1', bm, 'ring', (1.0, 0.92, 0.8), opacity=0.7, spin=1.0)
    for k, (R, ar, az, rgb, spin) in enumerate(((0.9, 0.35, 0.03, (1.0, 0.8, 0.5), 0.7),
                                                (1.45, 0.55, 0.05, (1.0, 0.58, 0.22), 0.4),
                                                (2.3, 0.8, 0.08, (0.9, 0.38, 0.1), 0.22),
                                                (3.0, 0.7, 0.1, (0.55, 0.18, 0.05), 0.14))):
        bm, uv = new()
        torus(bm, uv, R, ar, az, 320, 24)
        finish(f'SM_SV_BHDisk{k + 2}', bm, 'glow', rgb, opacity=0.5, spin=spin)
    infall(0.5)


def d_silk():
    shadow(); photon_ring(); halo_lower()
    for k, (rf, rt, n, rgb, op) in enumerate(((0.0, 0.35, 160, (1.0, 0.96, 0.88), 0.55),
                                              (0.2, 0.7, 160, (1.0, 0.75, 0.4), 0.4),
                                              (0.5, 1.0, 120, (0.95, 0.48, 0.15), 0.3))):
        bm, uv = new()
        strands(bm, uv, n, 0.0, 1.0, 1.0, (0.0015, 0.005), (60, 190), 0.0, arc=(ARCH_A0, ARCH_A1),
                rfun=lambda a, f, rf=rf, rt=rt: R0 + 0.004 + arch_width(a, 0.3) * (rf + (rt - rf) * f))
        finish(f'SM_SV_BHArch{k + 1}', bm, 'ring', rgb, opacity=op, faces=True)
    for k, (rf, rt, n, rgb, op, spin) in enumerate(((0.55, 1.1, 260, (1.0, 0.94, 0.82), 0.5, 1.0),
                                                    (0.7, 1.9, 300, (1.0, 0.72, 0.36), 0.38, 0.55),
                                                    (1.0, 3.6, 320, (0.85, 0.36, 0.1), 0.28, 0.25))):
        bm, uv = new()
        strands(bm, uv, n, rf, rt, 1.4, (0.003, 0.012), (40, 320), 0.008)
        finish(f'SM_SV_BHDisk{k + 1}', bm, 'ring', rgb, opacity=op, spin=spin)
    swirl(opacity=0.3)
    infall(0.5)


def d_hybrid():
    shadow(); photon_ring(); halo_lower()
    smooth_arch(0.25)
    bm, uv = new()                                   # (fine bright strands over the arch)
    strands(bm, uv, 90, 0.0, 0.9, 1.3, (0.0012, 0.0035), (60, 190), 0.0, arc=(ARCH_A0, ARCH_A1),
            rfun=lambda a, f: R0 + 0.006 + arch_width(a, 0.3) * f)
    finish('SM_SV_BHArchFine', bm, 'ring', (1.0, 0.97, 0.92), opacity=0.5, faces=True)
    smooth_disk(0.85)
    for k, (rf, rt, n, rgb, op, spin) in enumerate(((0.55, 1.3, 120, (1.0, 0.95, 0.85), 0.35, 1.0),
                                                    (0.9, 3.3, 160, (1.0, 0.6, 0.25), 0.25, 0.4))):
        bm, uv = new()
        strands(bm, uv, n, rf, rt, 1.3, (0.002, 0.008), (30, 200), 0.006)
        finish(f'SM_SV_BHStrands{k + 1}', bm, 'ring', rgb, opacity=op, spin=spin)
    swirl(opacity=0.32)
    sparks()
    infall(0.5)


def lerp(c0, c1, x):
    return tuple(a + (b - a) * x for a, b in zip(c0, c1))


def ramp(x):
    """the colour x of the way out: white-hot, gold, orange, deep red"""
    stops = [(0.0, (1.0, 0.97, 0.92)), (0.25, (1.0, 0.82, 0.52)), (0.5, (1.0, 0.58, 0.22)), (0.75, (0.85, 0.34, 0.09)),
             (1.0, (0.45, 0.12, 0.05))]
    for (x0, c0), (x1, c1) in zip(stops, stops[1:]):
        if x <= x1:
            return lerp(c0, c1, (x - x0) / (x1 - x0))
    return stops[-1][1]


def d_soft():
    """no lines, no hard edges: many faint layers, each reaching a little further out with a wavy edge and a warmer
    colour; where they overlap (near the shadow) white-hot, further out only the outer few (dim red). Each disk layer
    turns at its own speed (the inner ones faster), so its waves swirl"""
    shadow(); photon_ring(); halo_lower()
    n = 12
    for k in range(n):
        x = k / (n - 1)
        top = 0.025 + 0.31 * x ** 1.2
        bm, uv = new()
        w1, w2, p1, p2 = random.randint(9, 17), random.randint(23, 37), random.uniform(0, TAU), random.uniform(0, TAU)
        strip(bm, uv, ARCH_A0, ARCH_A1, lambda a: R0 + 0.004,
              lambda a, top=top, w1=w1, w2=w2, p1=p1, p2=p2: R0 + 0.004 + arch_width(a, top) *
              (1 + 0.025 * math.sin(w1 * a + p1) + 0.012 * math.sin(w2 * a + p2)), lambda a: 0.0, 600)
        finish(f'SM_SV_BHArch{k + 1}', bm, 'ring', ramp(x * 0.85), opacity=0.26 - 0.1 * x, faces=True,
               pulse=[0.08, 0.9 + 0.13 * k])
    n = 14
    for k in range(n):
        x = k / (n - 1)
        r_out = 0.72 + 2.9 * x ** 1.35
        bm, uv = new()
        w1, w2, p1, p2 = random.randint(4, 8), random.randint(11, 19), random.uniform(0, TAU), random.uniform(0, TAU)
        annulus(bm, uv, 0.55 + 0.1 * x, r_out, z=random.uniform(-0.004, 0.004) * r_out, segs=600,
                rout=lambda a, r=r_out, w1=w1, w2=w2, p1=p1, p2=p2: r * (1 + 0.06 * math.sin(w1 * a + p1) + 0.03 * math.sin(w2 * a + p2)))
        finish(f'SM_SV_BHDisk{k + 1}', bm, 'ring', ramp(x), opacity=0.2 - 0.135 * x, spin=round(1.0 / (1 + 2.2 * x), 3))
    bm, uv = new()                                   # (the approaching side: -X's half, brighter)
    strip(bm, uv, math.pi / 2, 3 * math.pi / 2, lambda a: 0.55, lambda a: 0.55 + 0.9 * abs(math.cos(a)) ** 0.8,
          lambda a: 0.0, 360)
    finish('SM_SV_BHDiskBright', bm, 'ring', (1.0, 0.96, 0.9), opacity=0.25)
    swirl(opacity=0.16)
    sparks()
    infall(0.35)


# ---- the detailed design (the user, 2026-11-22: "Remodel the 3D Event Horizon Black Hole, I want it as detailed as you
# can make it"): thousands of wisps shaped by noise, the arch made from the disk's own far side bent over the shadow ----
from mathutils import Vector, noise as mnoise


def fbm(x, y, octaves=3):
    """smooth noise, about -1..1, `octaves` layers of finer detail"""
    v, amp, f, tot = 0.0, 1.0, 1.0, 0.0
    for _ in range(octaves):
        v += amp * mnoise.noise(Vector((x * f, y * f, 0.37 * f + 1.7)))
        tot += amp
        amp *= 0.5
        f *= 2.03
    return v / tot


def spindle(t, k=0.7):
    """a wisp's breadth along it: nothing at its ends, full in its middle"""
    return max(0.0, math.sin(math.pi * t)) ** k


def wisp(bm, uv, a0, a1, r_fn, w_fn, z_fn, seg_deg):
    """a ribbon from angle a0 to a1: its middle at radius r_fn(a, t), w_fn(a, t) across, at height z_fn(a, t) (t 0..1
    along it); both faces drawn (AC8's materials draw one side). U along it, V across."""
    n = max(3, int(abs(a1 - a0) / math.radians(seg_deg)) + 1)
    prev = None
    for s in range(n + 1):
        t = s / n
        a = a0 + (a1 - a0) * t
        r, w, z = r_fn(a, t), max(1e-5, w_fn(a, t)), z_fn(a, t)
        ca, sa = math.cos(a), math.sin(a)
        cur = (bm.verts.new(((r - w / 2) * ca, (r - w / 2) * sa, z)), bm.verts.new(((r + w / 2) * ca, (r + w / 2) * sa, z)), t)
        if prev:
            (pi, po, pt), (ci, co, ct) = prev, cur
            f = bm.faces.new((pi, po, co, ci))
            for loop, q in zip(f.loops, ((pt, 0), (pt, 1), (ct, 1), (ct, 0))):
                loop[uv].uv = q
            g = bm.faces.new(tuple(bm.verts.new(v.co) for v in (ci, co, po, pi)))
            for loop, q in zip(g.loops, ((ct, 0), (ct, 1), (pt, 1), (pt, 0))):
                loop[uv].uv = q
        prev = cur


def seg_for(r):
    """degrees a segment: about 0.04 units of arc, 0.8 to 2.5 degrees"""
    return max(1.0, min(3.0, math.degrees(0.055 / max(0.1, r))))


# the disk's eight bands, white-hot inside to dark red outside: (r from, r to, wisps, colour, its hot knots' colour)
DISK_BANDS = [(0.55, 0.68, 170, (1.0, 0.98, 0.94), (1.0, 1.0, 1.0)),
              (0.66, 0.85, 190, (1.0, 0.92, 0.78), (1.0, 0.98, 0.94)),
              (0.82, 1.08, 210, (1.0, 0.82, 0.56), (1.0, 0.94, 0.8)),
              (1.04, 1.38, 210, (1.0, 0.68, 0.34), (1.0, 0.86, 0.6)),
              (1.33, 1.78, 160, (1.0, 0.52, 0.18), (1.0, 0.74, 0.42)),
              (1.72, 2.32, 115, (0.8, 0.32, 0.09), (1.0, 0.56, 0.22)),
              (2.25, 3.0, 85, (0.55, 0.18, 0.07), (0.9, 0.4, 0.13)),
              (2.9, 3.8, 60, (0.32, 0.09, 0.07), (0.7, 0.26, 0.09))]
R_IN, R_OUT = 0.55, 3.8
LANES = [(0.93, 0.03), (1.2, 0.025), (1.47, 0.05), (2.05, 0.08), (2.7, 0.1)]   # (radius, half-width): the disk's darker lanes


def lane_density(r):
    d = 1.0
    for c, hw in LANES:
        d *= 1.0 - 0.75 * math.exp(-((r - c) / hw) ** 2)
    return d


def disk_band(k, spec):
    r_lo, r_hi, count, rgb, hot = spec
    bm, uv = new()
    bk, uvk = new()
    for _ in range(count):
        for _try in range(20):
            r0 = random.uniform(r_lo, r_hi)
            if random.random() < lane_density(r0):
                break
        f = (r0 - R_IN) / (R_OUT - R_IN)
        seed = random.uniform(0, 500)
        a0 = random.uniform(0, TAU)
        L = math.radians(random.uniform(35, 230) * (1.25 - 0.55 * f))
        w0 = random.uniform(0.0026, 0.0095) * (0.7 + 0.6 * f)
        arm = f > 0.4 and random.random() < 0.28              # (a spiral arm's wisp: winding in faster)
        drift = random.uniform(0.004, 0.016) * (4.0 if arm else 1.0)
        h = 0.002 + 0.009 * r0                                # (the disk flares: thicker further out)
        zc = random.gauss(0, 0.4) * h
        wob = 0.006 + 0.018 * f

        def r_fn(a, t, r0=r0, seed=seed, wob=wob, drift=drift, a0=a0):
            return r0 * (1 + wob * fbm(a * 2.3 + seed, seed * 0.13)) * (1 - drift * (a - a0))

        def w_fn(a, t, w0=w0, seed=seed):
            return w0 * spindle(t) * (0.35 + 0.65 * min(1.0, max(0.0, 0.55 + 0.9 * fbm(a * 7.0 + seed, 2.0))))

        def z_fn(a, t, zc=zc, h=h, seed=seed):
            return zc + 0.5 * h * fbm(a * 1.6 + seed, 5.0)
        wisp(bm, uv, a0, a0 + L, r_fn, w_fn, z_fn, seg_for(r0))
        if random.random() < 0.13:                            # (a hot knot along it: short, broader, brighter)
            tk = random.uniform(0.2, 0.8)
            ak = a0 + L * tk
            Lk = math.radians(random.uniform(4, 13))
            wisp(bk, uvk, ak - Lk / 2, ak + Lk / 2, lambda a, t, rf=r_fn, ak=ak: rf(a, tk),
                 lambda a, t, w0=w0: 1.8 * w0 * spindle(t, 0.5), lambda a, t, zf=z_fn: zf(a, tk) + 0.0005, seg_for(r0))
    mid = (r_lo + r_hi) / 2
    spin = round((mid / 0.615) ** -1.5, 3)                    # (an orbit's speed: the inner ones much faster)
    finish(f'SM_SV_BHDisk{k + 1}', bm, 'ring', rgb, opacity=round(0.9 - 0.06 * k, 2), spin=spin, band=k)
    finish(f'SM_SV_BHKnots{k + 1}', bk, 'ring', hot, opacity=1.0, spin=spin, band=k)


ARCH_RGB = [(1.0, 1.0, 0.97), (1.0, 0.93, 0.8), (1.0, 0.82, 0.56), (1.0, 0.66, 0.3), (0.95, 0.48, 0.16), (0.72, 0.3, 0.1)]


def arch_b(a, f, seed, low=False):
    """the apparent radius, at angle a round the shadow, of the far-side disk's ring at f of the way out, bent over the
    top (low: under the bottom, the second image), and swept out to the disk's own radius at the horizon on both sides"""
    r = R_IN + (R_OUT - R_IN) * f
    if low:
        L, s, pw = 0.07 * f ** 0.8, -math.sin(a), 7
        lean = 1.0
    else:
        L, s, pw = 0.36 * f ** 0.8, math.sin(a), 4
        lean = 1 + 0.32 * math.cos(a - math.radians(125))     # (broadest off the top, on the approaching (-X) side)
    base = R0 + 0.005 + L * lean * (1 + 0.06 * fbm(a * 5 + seed, 7.7))
    limb = min(1.0, max(0.0, 1 - max(0.0, s)) ** pw)
    return base + max(0.0, r - base) * limb, limb


def arch(low=False):
    """the disk's far side as you'd see it bent round the shadow: wisps over the top (and a thin second image under the
    bottom: low), each from its own ring of the disk, so the arch reads as the disk's continuation; hotter on the
    approaching (-X) side; six pieces, white-hot near the shadow to dark orange out at its edge"""
    pieces = [new() for _ in ARCH_RGB]
    count = 120 if low else 1100
    for _ in range(count):
        f = random.random() ** 1.5
        seed = random.uniform(0, 500)
        if low:
            th0 = math.radians(random.uniform(177, 330))
            th1 = min(math.radians(363), th0 + math.radians(random.uniform(40, 160)))
        else:
            th0 = math.radians(random.uniform(-1, 150))
            th1 = min(math.radians(181), th0 + math.radians(random.uniform(40, 170)))
        mid = (th0 + th1) / 2
        dop = 0 if low else (1 if math.cos(mid) < -0.2 else (-1 if math.cos(mid) > 0.45 else 0))
        cls = max(0, min(len(ARCH_RGB) - 1, int(f * len(ARCH_RGB)) - dop + (1 if low else 0)))
        w0 = random.uniform(0.0014, 0.0048) * (1 + 1.6 * f) * (0.5 if low else 1.0)

        def r_fn(a, t, f=f, seed=seed, low=low):
            return arch_b(a, f, seed, low)[0]

        def w_fn(a, t, f=f, w0=w0, seed=seed, low=low):
            limb = arch_b(a, f, seed, low)[1]
            return w0 * spindle(t, 0.5) * (1 + 1.2 * limb) * (0.45 + 0.55 * min(1.0, max(0.0, 0.6 + 0.8 * fbm(a * 9 + seed, 4.4))))
        bm, uv = pieces[cls]
        wisp(bm, uv, th0, th1, r_fn, w_fn, lambda a, t: 0.0, 1.6)
    tag = 'Low' if low else ''
    for k, ((bm, uv), rgb) in enumerate(zip(pieces, ARCH_RGB)):
        if len(bm.faces):
            finish(f'SM_SV_BHArch{tag}{k + 1}', bm, 'ring', rgb if not low else lerp(rgb, (0.5, 0.2, 0.08), 0.35),
                   opacity=round((0.32 if low else 0.92) - (0.03 if low else 0.07) * k, 2), faces=True, pulse=[0.06 if low else 0.1, 0.8 + 0.3 * k])
        else:
            bm.free()


def haze():
    """soft glow under the wisps (for a see-through material): the disk in 4 wavy layers, the arch in 3"""
    for k in range(2):
        x = k
        r_out = 1.0 + 1.0 * x
        bm, uv = new()
        w1, p1 = random.randint(5, 9), random.uniform(0, TAU)
        annulus(bm, uv, R_IN, r_out, segs=480, rout=lambda a, r=r_out, w1=w1, p1=p1: r * (1 + 0.05 * math.sin(w1 * a + p1)))
        finish(f'SM_SV_BHDiskHaze{k + 1}', bm, 'haze', ramp(0.3 * x), opacity=round(0.1 - 0.04 * x, 3), spin=round(1.0 / (1 + 1.5 * x), 3))
    for k in range(2):
        x = k
        bm, uv = new()
        strip(bm, uv, -math.radians(2), math.pi + math.radians(2), lambda a: R0 + 0.004,
              lambda a, x=x: arch_b(a, 0.15 + 0.85 * x, 3.3)[0] if arch_b(a, 0.15 + 0.85 * x, 3.3)[1] < 0.6 else R0 + 0.01,
              lambda a: 0.0, 480)
        finish(f'SM_SV_BHArchHaze{k + 1}', bm, 'haze', ramp(x * 0.5), opacity=round(0.16 - 0.07 * x, 3), faces=True)


def infall_detailed():
    """ten noisy streams spiralling in from the disk's inner edge to the shadow"""
    bm, uv = new()
    for k in range(10):
        a0 = TAU * k / 10 + random.uniform(-0.3, 0.3)
        span = random.uniform(1.0, 2.0) * TAU
        r_start = random.uniform(0.62, 0.8)
        seed = random.uniform(0, 500)
        w0 = random.uniform(0.004, 0.01)
        wisp(bm, uv, a0, a0 + span, lambda a, t, a0=a0, span=span, rs=r_start: R0 + 0.003 + (rs - R0) * (1 - t) ** 1.4,
             lambda a, t, w0=w0, seed=seed: w0 * (1 - t) ** 0.8 * spindle(min(1.0, t * 3), 0.6) *
             (0.5 + 0.5 * min(1.0, max(0.0, 0.6 + fbm(a * 8 + seed, 1.1)))),
             lambda a, t: 0.0, 2.0)
    finish('SM_SV_BHInfall', bm, 'ring', (1.0, 0.86, 0.62), opacity=0.8, spin=1.6)


def sparks_detailed():
    """bright specks: on the disk (most near its inner edge; they turn with it) and over the arch's broad side"""
    for name, count, faces in (('SM_SV_BHSparks', 520, False), ('SM_SV_BHSparksArch', 170, True)):
        bm, uv = new()
        for _ in range(count):
            if faces:                                          # (round the arch's base on the approaching side mostly)
                a = math.radians(random.gauss(150, 35))
                r = arch_b(a, random.random() ** 0.7, 1.0)[0] + random.uniform(-0.01, 0.05)
                c = (r * math.cos(a), r * math.sin(a), 0.0)
            else:
                r = R_IN + (R_OUT - R_IN) * random.random() ** 2.0
                a = random.uniform(0, TAU)
                c = (r * math.cos(a), r * math.sin(a), random.gauss(0, 0.006) * r)
            sz = random.uniform(0.0012, 0.0035) * (1 + 0.25 * r)
            t = (-math.sin(a), math.cos(a))
            L = sz * random.uniform(2.0, 5.0)
            pts = [(c[0] + t[0] * L, c[1] + t[1] * L, c[2]), (c[0] - t[0] * L, c[1] - t[1] * L, c[2]),
                   (c[0] + math.cos(a) * sz, c[1] + math.sin(a) * sz, c[2]), (c[0] - math.cos(a) * sz, c[1] - math.sin(a) * sz, c[2]),
                   (c[0], c[1], c[2] + sz), (c[0], c[1], c[2] - sz)]
            vs = [bm.verts.new(q) for q in pts]
            for e in ((0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)):
                fc = bm.faces.new([vs[i] for i in e])
                for loop, tt in zip(fc.loops, ((0, 0), (1, 0), (0.5, 1))):
                    loop[uv].uv = tt
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        finish(name, bm, 'ring', (1.0, 0.9, 0.7) if faces else (1.0, 0.94, 0.8), faces=faces, spin=0.0 if faces else 0.5,
               smooth=False)


def d_detailed():
    shadow()
    photon_ring()
    arch()
    arch(low=True)
    for k, spec in enumerate(DISK_BANDS):
        disk_band(k, spec)
    haze()
    infall_detailed()
    sparks_detailed()


def d_lines():
    """v3 (0.74.211's preview): the arch and the disk as streaks in rings"""
    shadow(); photon_ring(); halo_lower()
    for k, (top, rgb, op) in enumerate(SMOOTH_ARCH[:3]):
        bm, uv = new()
        bands = 22 + 4 * k
        for j in range(bands):
            s0, s1 = j / bands, (j + 0.8) / bands
            for p, q in broken(ARCH_A0, ARCH_A1, 140, 0.15, 6):
                strip(bm, uv, p, q, lambda a, s0=s0, top=top: R0 + 0.004 + arch_width(a, top) * s0,
                      lambda a, s1=s1, top=top: R0 + 0.004 + arch_width(a, top) * s1, lambda a: 0.0, 480)
        finish(f'SM_SV_BHArch{k + 1}', bm, 'ring', rgb, opacity=op, faces=True)
    for k, (ra, rb, rgb, op, spin) in enumerate(SMOOTH_DISK):
        bm, uv = new()
        bands = 30
        for j in range(bands):
            r1 = ra + (rb - ra) * j / bands
            r2 = ra + (rb - ra) * (j + 0.8) / bands
            st = random.uniform(0, TAU)
            for p, q in broken(st, st + TAU, 90, 0.3, 10):
                strip(bm, uv, p, q, lambda a, r1=r1: r1, lambda a, r2=r2: r2, lambda a: 0.0, 360)
        finish(f'SM_SV_BHDisk{k + 1}', bm, 'ring', rgb, opacity=op, spin=spin)
    swirl(); sparks(); infall()


bpy.ops.wm.read_factory_settings(use_empty=True)
{'detailed': d_detailed, 'soft': d_soft, 'smooth': d_smooth, 'glow': d_glow, 'silk': d_silk, 'hybrid': d_hybrid,
 'lines': d_lines}[DESIGN]()
with open(os.path.join(OUT, 'manifest.json'), 'w', encoding='utf-8') as fh:
    json.dump({'design': DESIGN, 'pieces': MANIFEST}, fh, indent=1)
print(f'portal: done ({DESIGN}: ' + ', '.join(p['name'] for p in MANIFEST) + f'; {sum(p["tris"] for p in MANIFEST)} tris)')
