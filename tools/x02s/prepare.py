"""prepare.py : VALKA's X-02S (AC7's, tools/re/VALKA.md, tools/x02s/README.md) made ready for UE 5.4's glTF import.

AC7's UModel export (E:/Ace Combat 7 Exports/Game/Vehicles/Aircraft/x02s) is a skinned mesh (58 bones: swing wings,
canards, flaps, nozzles, bay doors) at AC7's model scale (2.19 m long; AC8's aircraft are life-size: its F/A-18E is
18.28 m). Written to build/x02s/:
  x02s_skel.gltf / .bin   the skinned mesh at LENGTH_M: positions, bind matrices and bone positions scaled
  scale.json              the scale (AC7 units -> life-size), for the sockets
  sweep.json              the swing wings' sweep for the UE script: AC7's x02s_Anim (UModel .psa, build/x02s/umodel)
                          moves every part from 0 to 100 % across its 101 frames; the wings (VariableWing_*) sweep in
                          frames SWEEP_FRAMES, so their rotations there, as the .psa holds them (x, y, z, w)
  T_X02S_Valka_C.tga      the stock Osean skin (00: the base texture 03-07 share too, no emblem decals, so not
                          Trigger's; user, 2026-10-24), its colour map as it is
  T_X02S_Valka_NO.tga     the normal map (00, shared by every skin), as it is (blue and the alpha the importer adds are near
                          1, so AC8's _NO occlusion, wherever it sits, reads as none)
  T_X02S_Valka_LM.tga     AC8's "Livemap" (its _MRX: the R / G / B paint layers' masks), 256x256 black: no layers
                          (all zero is AC8's own neutral one, T_Livemap_Flat), big enough to be a virtual texture
python -I tools/x02s/prepare.py   (needs the .psa: tools/x02s/build.sh exports it with UModel first)
"""
import json, math, os, shutil, struct

SRC = r'E:/Ace Combat 7 Exports/Game/Vehicles/Aircraft/x02s'
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'build', 'x02s')
PSA = os.path.join(OUT, 'umodel', 'Game', 'Vehicles', 'Aircraft', 'x02s', 'x02s_Anim.psa')
LENGTH_M = 19.6            # the X-02S's length (main.lua CFG.specials.valka.model_length_m scales it at run time)
SKIN = '00'                # stock Osean (user: "not in mihalys colours and just the stock empty osean one, not triggers")
SWEEP_FRAMES = (50, 100)   # the wings' window in x02s_Anim (frames 51-100 move them; 50 is the last unswept)


def skinned_gltf():
    g = json.load(open(os.path.join(SRC, 'x02s.gltf'), encoding='utf-8'))
    buf = bytearray(open(os.path.join(SRC, 'x02s.bin'), 'rb').read())
    pos = {p['attributes']['POSITION'] for m in g['meshes'] for p in m['primitives']}
    lo, hi = min(g['accessors'][a]['min'][0] for a in pos), max(g['accessors'][a]['max'][0] for a in pos)
    s = LENGTH_M / (hi - lo)

    def view_floats(acc, per):
        a = g['accessors'][acc]
        v = g['bufferViews'][a['bufferView']]
        base = v.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = v.get('byteStride') or 4 * per
        return [base + k * stride for k in range(a['count'])]

    for acc in pos:                                   # vertex positions
        for o in view_floats(acc, 3):
            struct.pack_into('<3f', buf, o, *(c * s for c in struct.unpack_from('<3f', buf, o)))
        a = g['accessors'][acc]
        a['min'] = [c * s for c in a['min']]
        a['max'] = [c * s for c in a['max']]
    for sk in g['skins']:                             # inverse bind matrices (column-major: translation at 12-14)
        for o in view_floats(sk['inverseBindMatrices'], 16):
            m = list(struct.unpack_from('<16f', buf, o))
            m[12], m[13], m[14] = m[12] * s, m[13] * s, m[14] * s
            struct.pack_into('<16f', buf, o, *m)
    for n in g['nodes']:                              # bone positions
        if 'translation' in n:
            n['translation'] = [c * s for c in n['translation']]
    for part in PARTS:                                # AC7's other X-02S meshes, on her Body bone
        merge_part(g, buf, part, s)
    g['buffers'][0]['byteLength'] = len(buf)
    g['buffers'][0]['uri'] = 'x02s_skel.bin'
    g['nodes'][0]['name'] = 'SK_X02S_Valka'
    json.dump(g, open(os.path.join(OUT, 'x02s_skel.gltf'), 'w', encoding='utf-8'), indent=1)
    open(os.path.join(OUT, 'x02s_skel.bin'), 'wb').write(buf)
    return s, hi - lo


# AC7 builds the X-02S from more than x02s.gltf: the closed gear doors and refuel panel are their own static meshes, and
# the belly between the engines is a special weapon's skinned mesh (SWP1-3; SWP3 the long centre piece). Without them
# she had holes (test of 2026-10-24, 0.67.x: "her refuel off mesh isn't visible", the slot between her engines).
# Each goes into her skinned mesh as more triangles on her Body bone, in its rest pose, on her paint (material 0).
PARTS = ('x02s_GearOff_SM', 'x02s_RefuelOff_SM', 'x02s_SWP3')
# AC7 Mission 18's lens flash before Mihaly's first shot (ms18_LensEffect1: a screen-space billboard, M_LensBokeh1,
# and planes with M_LensFlare1 / M_LensFlare2 / M_LensRing1): its textures, for VALKA's opener light
AC7_ROOT = 'E:/Ace Combat 7 Exports'
FLARE_TEX = (('Game/VFX/Common/Textures/Misc/Ace_SunGlareVR.tga', 'T_SV_ValkaFlare_Glare'),
             ('Game/VFX/Environment/ms18LensEffect/T_EML_shine01.tga', 'T_SV_ValkaFlare_Shine'),
             ('Game/VFX/Environment/ms18LensEffect/T_EML_LensFlare01.tga', 'T_SV_ValkaFlare_Ring'),
             ('Engine/EngineMaterials/DefaultBokeh.tga', 'T_SV_ValkaFlare_Bokeh'))


def _m4(a, b):                                        # column-major 4x4 product (glTF)
    return [sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4)) for c in range(4) for r in range(4)]


def _trs(n):
    if 'matrix' in n:
        return list(n['matrix'])
    t, (x, y, z, w), sc = n.get('translation', [0, 0, 0]), n.get('rotation', [0, 0, 0, 1]), n.get('scale', [1, 1, 1])
    m = [1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
         2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
         2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0, t[0], t[1], t[2], 1]
    for c in range(3):
        for r in range(3):
            m[c * 4 + r] *= sc[c]
    return m


def merge_part(g, buf, name, s):
    """name.gltf (AC7's export next to x02s.gltf): its triangles posed (a skinned part through its own bones, a static
    one through its node), scaled by s, appended to g's first mesh as one primitive weighted 100 % to the Body joint."""
    pg = json.load(open(os.path.join(SRC, name + '.gltf'), encoding='utf-8'))
    pb = open(os.path.join(SRC, pg['buffers'][0]['uri']), 'rb').read()

    def read(i):
        a = pg['accessors'][i]
        v = pg['bufferViews'][a['bufferView']]
        n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
        fmt = {5126: 'f', 5125: 'I', 5123: 'H', 5121: 'B'}[a['componentType']]
        st = v.get('byteStride') or n * struct.calcsize(fmt)
        base = v.get('byteOffset', 0) + a.get('byteOffset', 0)
        return [struct.unpack_from('<' + fmt * n, pb, base + k * st) for k in range(a['count'])]

    parent = {c: i for i, n in enumerate(pg['nodes']) for c in n.get('children', [])}
    glob = {}

    def G(i):
        if i not in glob:
            glob[i] = _trs(pg['nodes'][i]) if i not in parent else _m4(G(parent[i]), _trs(pg['nodes'][i]))
        return glob[i]

    mesh_node = next(i for i, n in enumerate(pg['nodes']) if 'mesh' in n)
    skin = pg['skins'][0] if pg.get('skins') else None
    jm = [_m4(G(j), list(m)) for j, m in zip(skin['joints'], read(skin['inverseBindMatrices']))] if skin else None
    P, N, T, UV, IDX = [], [], [], [], []
    for prim in pg['meshes'][pg['nodes'][mesh_node]['mesh']]['primitives']:
        at = prim['attributes']
        pos, nrm, uv = read(at['POSITION']), read(at['NORMAL']), read(at['TEXCOORD_0'])
        tan = read(at['TANGENT']) if 'TANGENT' in at else [(1, 0, 0, 1)] * len(pos)
        J = read(at['JOINTS_0']) if skin and 'JOINTS_0' in at else None
        W = read(at['WEIGHTS_0']) if J else None
        base = len(P)
        for k, p in enumerate(pos):
            if J:                                     # the bones' rest pose, weighted
                m = [0.0] * 16
                for j, w in zip(J[k], W[k]):
                    if w:
                        for e in range(16):
                            m[e] += jm[j][e] * w / 255.0
            else:
                m = G(mesh_node)
            def lin(v, wgt):
                return [m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12] * wgt,
                        m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13] * wgt,
                        m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14] * wgt]
            def unit(v):
                ln = math.sqrt(sum(c * c for c in v)) or 1.0
                return [c / ln for c in v]
            P.append([c * s for c in lin(p, 1)])
            N.append(unit(lin(nrm[k], 0)))
            T.append(unit(lin(tan[k][:3], 0)) + [tan[k][3]])
            UV.append(uv[k])
        IDX += [base + i[0] for i in read(prim['indices'])]
    body = next(k for k, j in enumerate(g['skins'][0]['joints']) if g['nodes'][j].get('name') == 'Body')

    def add(data, ctype, typ, count, target, mn=None, mx=None, normalized=False):
        while len(buf) % 4:
            buf.append(0)
        g['bufferViews'].append({'buffer': 0, 'byteOffset': len(buf), 'byteLength': len(data), 'target': target})
        buf.extend(data)
        a = {'bufferView': len(g['bufferViews']) - 1, 'componentType': ctype, 'count': count, 'type': typ}
        if mn is not None:
            a['min'], a['max'] = mn, mx
        if normalized:
            a['normalized'] = True
        g['accessors'].append(a)
        return len(g['accessors']) - 1

    n = len(P)
    flat = lambda rows, f: b''.join(struct.pack('<' + f * len(r), *r) for r in rows)
    attrs = {
        'POSITION': add(flat(P, 'f'), 5126, 'VEC3', n, 34962, [min(p[d] for p in P) for d in range(3)], [max(p[d] for p in P) for d in range(3)]),
        'NORMAL': add(flat(N, 'f'), 5126, 'VEC3', n, 34962),
        'TANGENT': add(flat(T, 'f'), 5126, 'VEC4', n, 34962),
        'COLOR_0': add(bytes([255, 255, 255, 255]) * n, 5121, 'VEC4', n, 34962, normalized=True),
        'JOINTS_0': add(struct.pack('<4H', body, 0, 0, 0) * n, 5123, 'VEC4', n, 34962),
        'WEIGHTS_0': add(bytes([255, 0, 0, 0]) * n, 5121, 'VEC4', n, 34962, normalized=True),
        'TEXCOORD_0': add(flat(UV, 'f'), 5126, 'VEC2', n, 34962),
        'TEXCOORD_1': add(flat(UV, 'f'), 5126, 'VEC2', n, 34962),
    }
    idx = add(struct.pack(f'<{len(IDX)}I', *IDX), 5125, 'SCALAR', len(IDX), 34963)
    g['meshes'][0]['primitives'].append({'attributes': attrs, 'indices': idx, 'material': 0})
    print(f'x02s: {name} merged: {len(IDX) // 3} triangles on Body (joint {body}), '
          f'x {min(p[0] for p in P):.2f}..{max(p[0] for p in P):.2f} m')


# VALKA's portal (user, 2026-10-24: "an event horizon black hole that Valka will spawn out of"): textures made here for
# AC8's own effect materials (Lua makes their dynamic instances at run time, no shader of ours):
#   T_SV_Portal_Disc   the event horizon for M_Smoke01 (black, its alpha a soft-edged disc, in all 8 x 8 cells of the
#                      flipbook atlas that material samples)
#   T_SV_Portal_Ring   the photon ring for the additive flare (a thin hot ring, brighter on one side: Doppler beaming)
#   T_SV_Portal_Glow   the accretion glow for the additive flare (a wide ring of spiral streaks)
def tga32(path, w, h, px):
    """px(x, y) -> (r, g, b, a) bytes 0-255; an uncompressed 32-bit TGA, top-left origin."""
    head = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8 | 0x20)
    rows = bytearray()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px(x, y)
            rows += bytes((b, g, r, a))
    open(path, 'wb').write(head + bytes(rows))


def portal_textures():
    def smooth(e0, e1, v):
        t = max(0.0, min(1.0, (v - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    cell = 128                                         # disc: 8 x 8 cells of 128 px
    def disc(x, y):
        cx, cy = (x % cell) - cell / 2 + 0.5, (y % cell) - cell / 2 + 0.5
        r = math.hypot(cx, cy) / (cell / 2)
        return 0, 0, 0, int(255 * (1 - smooth(0.80, 0.92, r)))
    tga32(os.path.join(OUT, 'T_SV_Portal_Disc.tga'), cell * 8, cell * 8, disc)
    n = 512
    def ring(x, y):
        cx, cy = (x - n / 2 + 0.5) / (n / 2), (y - n / 2 + 0.5) / (n / 2)
        r, ang = math.hypot(cx, cy), math.atan2(cy, cx)
        band = math.exp(-((r - 0.62) / 0.025) ** 2) + 0.35 * math.exp(-((r - 0.62) / 0.08) ** 2)
        beam = 0.55 + 0.45 * math.cos(ang - 0.6)       # one side brighter
        v = min(1.0, band * beam)
        return int(255 * v), int(235 * v ** 1.2), int(200 * v ** 1.6), 255
    tga32(os.path.join(OUT, 'T_SV_Portal_Ring.tga'), n, n, ring)
    def glow(x, y):
        cx, cy = (x - n / 2 + 0.5) / (n / 2), (y - n / 2 + 0.5) / (n / 2)
        r, ang = math.hypot(cx, cy), math.atan2(cy, cx)
        body = smooth(0.30, 0.42, r) * (1 - smooth(0.62, 0.98, r))
        streak = 0.55 + 0.45 * math.sin(7 * ang + 9.0 * math.log(max(r, 0.05)))      # log-spiral arms
        v = max(0.0, min(1.0, body * streak * (0.8 + 0.2 * math.cos(ang - 0.6))))
        return int(255 * v), int(120 * v ** 1.3), int(60 * v ** 1.8), 255             # hot orange
    tga32(os.path.join(OUT, 'T_SV_Portal_Glow.tga'), n, n, glow)


def sweep():
    b = open(PSA, 'rb').read()
    o, ch = 0, {}
    while o < len(b):
        cid, _, size, cnt = struct.unpack_from('<20sIII', b, o)
        o += 32
        ch[cid.split(b'\0')[0].decode()] = (o, size, cnt)
        o += size * cnt
    oo, sz, n = ch['BONENAMES']
    bones = [struct.unpack_from('<64s', b, oo + i * sz)[0].split(b'\0')[0].decode() for i in range(n)]
    oo, sz, nk = ch['ANIMKEYS']
    nf = nk // len(bones)
    a, z = SWEEP_FRAMES
    rot = {}
    for i, bn in enumerate(bones):
        if bn.startswith('VariableWing_'):
            rot[bn] = [list(struct.unpack_from('<4f', b, oo + (f * len(bones) + i) * sz + 12)) for f in range(a, z + 1)]
    rest = {bn: list(struct.unpack_from('<4f', b, oo + i * sz + 12)) for i, bn in enumerate(bones)}   # frame 0
    json.dump({'frames': SWEEP_FRAMES, 'source_frames': nf, 'bones': rot, 'frame0': rest},
              open(os.path.join(OUT, 'sweep.json'), 'w'), indent=0)
    return len(rot), nf


def black_tga(path, n=4):
    head = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, n, n, 32, 8)
    open(path, 'wb').write(head + bytes(4 * n * n))


def main():
    os.makedirs(OUT, exist_ok=True)
    s, length = skinned_gltf()
    json.dump({'scale': s, 'length_m': LENGTH_M}, open(os.path.join(OUT, 'scale.json'), 'w'))
    nb, nf = sweep()
    shutil.copyfile(os.path.join(SRC, SKIN, f'x02s_{SKIN}_D.tga'), os.path.join(OUT, 'T_X02S_Valka_C.tga'))
    shutil.copyfile(os.path.join(SRC, '00', 'x02s_00_N.tga'), os.path.join(OUT, 'T_X02S_Valka_NO.tga'))
    black_tga(os.path.join(OUT, 'T_X02S_Valka_LM.tga'), 256)
    for src, dst in FLARE_TEX:                        # AC7 Mission 18's lens flash (ms18_LensEffect1)
        shutil.copyfile(os.path.join(AC7_ROOT, src), os.path.join(OUT, dst + '.tga'))
    portal_textures()   # (all zero is AC8's neutral Livemap: T_Livemap_Flat)
    print(f'x02s: skinned mesh x{s:.3f} ({length:.3f} -> {LENGTH_M} m), sweep of {nb} wing bones (frames '
          f'{SWEEP_FRAMES[0]}-{SWEEP_FRAMES[1]} of {nf}), the stock Osean skin ({SKIN}), normal map (00), blank Livemap -> '
          f'{os.path.normpath(OUT)}')


if __name__ == '__main__':
    main()
