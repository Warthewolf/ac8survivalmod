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
  T_X02S_Valka_LM.tga     AC8's "Livemap" (its _MRX: three paint-region masks): 4x4 black, no regions
python -I tools/x02s/prepare.py   (needs the .psa: tools/x02s/build.sh exports it with UModel first)
"""
import json, os, shutil, struct

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
    g['buffers'][0]['uri'] = 'x02s_skel.bin'
    g['nodes'][0]['name'] = 'SK_X02S_Valka'
    json.dump(g, open(os.path.join(OUT, 'x02s_skel.gltf'), 'w', encoding='utf-8'), indent=1)
    open(os.path.join(OUT, 'x02s_skel.bin'), 'wb').write(buf)
    return s, hi - lo


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
    black_tga(os.path.join(OUT, 'T_X02S_Valka_LM.tga'))
    print(f'x02s: skinned mesh x{s:.3f} ({length:.3f} -> {LENGTH_M} m), sweep of {nb} wing bones (frames '
          f'{SWEEP_FRAMES[0]}-{SWEEP_FRAMES[1]} of {nf}), the stock Osean skin ({SKIN}), normal map (00), blank Livemap -> '
          f'{os.path.normpath(OUT)}')


if __name__ == '__main__':
    main()
