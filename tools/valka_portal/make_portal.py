"""make_portal.py : VALKA's portal, a black hole's event horizon (docs/re/VALKA.md section 8), modelled in Blender 3.3 as
3D meshes, each exported as a glTF.

  blender -b -P tools/valka_portal/make_portal.py -- <out folder>

The user, 2026-11-22: "Can you make custom 3D assets for this in Blender and Unreal Engine Editor please", "I want the
portal to look like an event horizon from a black hole" (Interstellar's Gargantua and the like: a black shadow, a thin
photon ring, a streaked accretion disk seen nearly edge-on across it, the disk's lensed image arching over the top and
under the bottom, one side brighter), "Needs to be a 3D model, not a png floating in the air". Every piece is real
geometry made here from numbers (no source art, no texture: AC8's own glow materials colour each piece in game, hard
rule 58), in units of the shadow's diameter (1.0), its symmetry axis +Z. In game (sv_anomalies_valka.lua) the disk
pieces lie tilted a few degrees towards you and turn on their axis (inner faster), the shadow, the photon ring and the
lensed arcs face you, and the whole hole turns to keep facing you.
  SM_SV_BHShadow       the event horizon's shadow: a sphere, 1.0 across
  SM_SV_BHPhotonRing   the photon ring: a thin torus just outside it
  SM_SV_BHHaloInner    the lensed disk's image round it: streaked arcs, broad over the top, thin underneath
  SM_SV_BHHaloOuter    fainter, broken arcs further out over the top
  SM_SV_BHDiskHot      the disk's hot inner bands (streaks with a little thickness, both faces drawn)
  SM_SV_BHDiskWarm     its warm middle bands, broken more often
  SM_SV_BHDiskCool     its cool outer bands and clumps, sparse
  SM_SV_BHDiskBright   the approaching side's brighter streaks (one half of the inner disk; it never turns)
Prints `portal: <name> <verts> verts <tris> tris` for each and `portal: done` at the end (tools/valka_portal/build.sh).
"""
import math
import os
import random
import sys

import bmesh
import bpy

OUT = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else os.path.join(os.getcwd(), 'build', 'valka_portal', 'src')
os.makedirs(OUT, exist_ok=True)
random.seed(20261122)
TAU = 2 * math.pi
NAMES = []


def finish(name, bm, smooth=True):
    """bm -> an object `name`, one material slot, triangulated, exported as <OUT>/<name>.glb (its faces as built)"""
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
    NAMES.append(name)
    bpy.data.objects.remove(ob)


def quad(bm, uv, a, b, c, d, uvs=((0, 0), (1, 0), (1, 1), (0, 1)), both=True):
    """a quad, and its back face too (AC8's materials draw one side)"""
    f = bm.faces.new((a, b, c, d))
    for loop, t in zip(f.loops, uvs):
        loop[uv].uv = t
    if both:
        g = bm.faces.new((bm.verts.new(d.co), bm.verts.new(c.co), bm.verts.new(b.co), bm.verts.new(a.co)))
        for loop, t in zip(g.loops, reversed(uvs)):
            loop[uv].uv = t


def band(bm, uv, r_in, width_fn, a0, a1, z_fn, segs, thick=0.0):
    """a flat streak: an arc band from angle a0 to a1, from r_in out by width_fn(angle), at height z_fn(angle, r),
    in the XY plane; `thick`: a slab (top, bottom and the two long edges) instead of a sheet"""
    n = max(2, int(segs * (a1 - a0) / TAU) + 1)
    rows = []
    for s in range(n + 1):
        a = a0 + (a1 - a0) * s / n
        w = width_fn(a)
        ca, sa = math.cos(a), math.sin(a)
        z = z_fn(a, r_in)
        pts = [(r_in * ca, r_in * sa, z), ((r_in + w) * ca, (r_in + w) * sa, z)]
        if thick:
            rows.append([bm.verts.new((x, y, zz + dz)) for dz in (thick, -thick) for x, y, zz in pts])
        else:
            rows.append([bm.verts.new(p) for p in pts])
    for s in range(n):
        p, q = rows[s], rows[s + 1]
        u0, u1 = s / n, (s + 1) / n
        if thick:                                     # 0 top in, 1 top out, 2 bottom in, 3 bottom out
            for i, j in ((0, 1), (3, 2), (2, 0), (1, 3)):
                quad(bm, uv, p[i], p[j], q[j], q[i], ((u0, 0), (u0, 1), (u1, 1), (u1, 0)), both=False)
        else:
            quad(bm, uv, p[0], p[1], q[1], q[0], ((u0, 0), (u0, 1), (u1, 1), (u1, 0)))


def arcs(bm, uv, r_from, r_to, count, gap_p, gap_deg, seg_deg, width, z_amp, segs, thick):
    """`count` streak rings between r_from and r_to, each broken into arcs (a gap of gap_deg with chance gap_p after
    each piece of seg_deg), each a little higher or lower (z_amp x r), `width` wide (jittered)"""
    for k in range(count):
        r = r_from + (r_to - r_from) * (k + random.random() * 0.8) / count
        w = width * random.uniform(0.4, 1.3)
        z0 = random.uniform(-z_amp, z_amp) * r
        a = random.uniform(0, TAU)
        end = a + TAU
        while a < end - 0.01:
            piece = math.radians(random.uniform(seg_deg * 0.4, seg_deg * 1.6))
            b = min(end, a + piece)
            band(bm, uv, r, lambda _a, w=w: w, a, b, lambda _a, _r, z0=z0: z0, segs, thick)
            a = b
            if random.random() < gap_p:
                a += math.radians(random.uniform(gap_deg * 0.3, gap_deg))


def shadow():
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=32, radius=0.5)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (0.5 + math.atan2(co.y, co.x) / TAU, 0.5 + co.z)
    finish('SM_SV_BHShadow', bm)


def photon_ring():
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    R, tube, segs, rings = 0.515, 0.0055, 192, 10
    grid = [[bm.verts.new(((R + tube * math.cos(TAU * i / rings)) * math.cos(TAU * j / segs),
                           (R + tube * math.cos(TAU * i / rings)) * math.sin(TAU * j / segs),
                           tube * math.sin(TAU * i / rings))) for j in range(segs)] for i in range(rings)]
    for i in range(rings):
        for j in range(segs):
            i2, j2 = (i + 1) % rings, (j + 1) % segs
            f = bm.faces.new((grid[i][j], grid[i][j2], grid[i2][j2], grid[i2][j]))
            for loop, t in zip(f.loops, ((j / segs, i / rings), ((j + 1) / segs, i / rings),
                                         ((j + 1) / segs, (i + 1) / rings), (j / segs, (i + 1) / rings))):
                loop[uv].uv = t
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    finish('SM_SV_BHPhotonRing', bm)


def halo_inner():
    """the lensed image: 7 streaks from r 0.53, broad over the top (+Y, which faces up in game), thin underneath"""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    for k in range(9):                                # (the preview of 14:05: too thin: 9 streaks, ~0.3 broad on top)
        r0 = 0.525 + 0.03 * k + random.uniform(0, 0.008)
        top = random.uniform(0.022, 0.036) * (1.2 - 0.07 * k)
        bottom = top * random.uniform(0.12, 0.25) * (1.0 if k < 4 else 0.0) + 0.0015

        def width(a, top=top, bottom=bottom):
            s = (1 + math.sin(a)) / 2
            return bottom + (top - bottom) * s ** 1.8
        # (broken only near the bottom, where the lensed image is thin and frays)
        a = -math.pi / 2 + random.uniform(0.2, 0.6)
        end = a + TAU - random.uniform(0.25, 0.7)
        band(bm, uv, r0, width, a, end, lambda _a, _r: 0.0, 256)
    finish('SM_SV_BHHaloInner', bm)


def halo_outer():
    """fainter streaks further out, mostly over the top, broken"""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    for k in range(9):
        r0 = 0.66 + 0.022 * k + random.uniform(0, 0.012)
        top = random.uniform(0.008, 0.02)
        a = math.radians(random.uniform(10, 60))
        while a < math.radians(random.uniform(120, 175)):
            b = a + math.radians(random.uniform(15, 55))

            def width(x, top=top):
                return top * max(0.15, math.sin(x)) ** 1.5
            band(bm, uv, r0, width, a, b, lambda _a, _r: 0.0, 160)
            a = b + math.radians(random.uniform(3, 14))
    finish('SM_SV_BHHaloOuter', bm)


def disk_hot():
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    arcs(bm, uv, 0.62, 1.25, 34, 0.25, 10, 70, 0.016, 0.004, 192, 0.002)
    finish('SM_SV_BHDiskHot', bm)


def disk_warm():
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    arcs(bm, uv, 1.15, 2.1, 40, 0.5, 18, 45, 0.02, 0.007, 192, 0.003)
    finish('SM_SV_BHDiskWarm', bm)


def disk_cool():
    """sparse outer bands and clumps (tangential blobs) out to r 3.2"""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    arcs(bm, uv, 1.9, 3.2, 30, 0.7, 30, 25, 0.026, 0.012, 160, 0.004)
    for _ in range(140):                              # clumps: stretched along the orbit
        a = random.uniform(0, TAU)
        r = random.uniform(1.6, 3.3)
        c = (r * math.cos(a), r * math.sin(a), random.uniform(-0.012, 0.012) * r)
        t = (-math.sin(a), math.cos(a), 0.0)
        n = (math.cos(a), math.sin(a), 0.0)
        L, W, H = random.uniform(0.05, 0.16), random.uniform(0.008, 0.02), random.uniform(0.004, 0.01)
        pts = [(c[0] + t[0] * L * sx + n[0] * W * sy, c[1] + t[1] * L * sx + n[1] * W * sy, c[2] + H * sz)
               for sx, sy, sz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]
        vs = [bm.verts.new(p) for p in pts]
        for e in ((0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)):
            f = bm.faces.new([vs[i] for i in e])
            for loop, tt in zip(f.loops, ((0, 0), (1, 0), (0.5, 1))):
                loop[uv].uv = tt
    finish('SM_SV_BHDiskCool', bm, smooth=False)


def disk_bright():
    """the approaching side (-X): bright streaks over half the inner disk, thinning away from its middle"""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    for k in range(22):
        r = 0.64 + 0.9 * (k + random.random()) / 22
        w = random.uniform(0.006, 0.016)
        z0 = random.uniform(-0.003, 0.003) * r
        a = math.pi / 2 + math.radians(random.uniform(5, 30))
        end = 3 * math.pi / 2 - math.radians(random.uniform(5, 30))
        while a < end:
            b = min(end, a + math.radians(random.uniform(20, 70)))

            def width(x, w=w):
                return w * (0.3 + 0.7 * abs(math.cos(x)))
            band(bm, uv, r, width, a, b, lambda _a, _r, z0=z0: z0, 192, 0.0018)
            a = b + math.radians(random.uniform(1, 8))
    finish('SM_SV_BHDiskBright', bm)


bpy.ops.wm.read_factory_settings(use_empty=True)
for fn in (shadow, photon_ring, halo_inner, halo_outer, disk_hot, disk_warm, disk_cool, disk_bright):
    fn()
print('portal: done (' + ', '.join(NAMES) + ')')
