"""scaler.py <out folder> : VALKA's portal's scaler (the user, 2026-11-22: "the portal opening and closing is so laggy
its not smooth at all"). Survival's Lua runs 4 times a second (sv_main.lua's loop: one tick of 250 ms, a faster or a
second loop crashed UE4SS's Lua), so a piece scaled by it grows in steps. The engine plays an animation every frame:
each portal piece hangs on its own scaler (Scripts/sv_anomalies.lua portalMesh) and grows, holds and shrinks with its
one bone, B. Writes SK_SV_PortalScaler.gltf / .bin: bones Root and B, one triangle 1 mm across skinned to B (never
seen), and one animation of B's scale, 1 s long, LINEAR keys every 1/60 s (the closing plays it backwards):
  A_SV_PortalGrow    0.001 -> 1, out fast and settling (1 - (1 - t)^3, the opening's curve)
Lua plays one at the rate 1 / its window's length (a piece's open / close window, shares of open_s / close_s).
Plain Python (no numpy, no Blender)."""
import json
import os
import struct
import sys

OUT = sys.argv[1]
NAME = 'SK_SV_PortalScaler'
FPS, MINS = 60, 0.001
# (one animation: UE's glTF import gave only a file's first animation its skeleton; the closing plays it backwards)
CURVES = [('A_SV_PortalGrow', lambda t: MINS + (1 - MINS) * (1 - (1 - t) ** 3))]


def main():
    os.makedirs(OUT, exist_ok=True)
    blob = bytearray()
    views, accessors = [], []

    def add(fmt, values, kind, ctype, count, minmax=None, target=None):
        while len(blob) % 4:
            blob.append(0)
        data = struct.pack('<' + fmt * (len(values) // len(fmt)), *values)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data), **({'target': target} if target else {})})
        blob.extend(data)
        acc = {'bufferView': len(views) - 1, 'componentType': ctype, 'count': count, 'type': kind}
        if minmax:
            acc['min'], acc['max'] = minmax
        accessors.append(acc)
        return len(accessors) - 1

    h = 0.05                                             # (cm: a triangle 1 mm across at the bone)
    pos = add('fff', [0, 0, 0, h, 0, 0, 0, h, 0], 'VEC3', 5126, 3, ([0, 0, 0], [h, h, 0]), 34962)
    nrm = add('fff', [0, 0, 1] * 3, 'VEC3', 5126, 3, None, 34962)
    uv = add('ff', [0, 0, 1, 0, 0, 1], 'VEC2', 5126, 3, None, 34962)
    joints = add('HHHH', [1, 0, 0, 0] * 3, 'VEC4', 5123, 3, None, 34962)   # (skin joint 1: B)
    # ((2026-11-22) laid out as tools/solg/prepare.py's SK_SV_SOLG, whose animation imports and plays: the mesh node first,
    # the bones' root next; each animation B's rotation and place too (constant): the first scaler's animations came in
    # with no skeleton (scale tracks alone, the mesh node last))
    weights = add('ffff', [1, 0, 0, 0] * 3, 'VEC4', 5126, 3, None, 34962)
    idx = add('HHH', [0, 1, 2], 'SCALAR', 5123, 3, None, 34963)
    ibm = add('f' * 16, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] * 2, 'MAT4', 5126, 2)
    n = FPS + 1
    times = [k / FPS for k in range(n)]
    tin = add('f', times, 'SCALAR', 5126, n, ([0.0], [1.0]))
    anims = []
    for aname, f in CURVES:
        vals = []
        for t in times:
            s = f(t)
            vals += [s, s, s]
        o = add('fff', vals, 'VEC3', 5126, n)
        rot = add('ffff', [0, 0, 0, 1] * n, 'VEC4', 5126, n)
        loc = add('fff', [0, 0, 0] * n, 'VEC3', 5126, n)
        anims.append({'name': aname, 'samplers': [{'input': tin, 'output': o, 'interpolation': 'LINEAR'},
                                                  {'input': tin, 'output': rot, 'interpolation': 'LINEAR'},
                                                  {'input': tin, 'output': loc, 'interpolation': 'LINEAR'}],
                      'channels': [{'sampler': 0, 'target': {'node': 2, 'path': 'scale'}},
                                   {'sampler': 1, 'target': {'node': 2, 'path': 'rotation'}},
                                   {'sampler': 2, 'target': {'node': 2, 'path': 'translation'}}]})
    g = {
        'asset': {'version': '2.0', 'generator': 'tools/valka_portal/scaler.py'},
        'scene': 0, 'scenes': [{'nodes': [0, 1]}],
        'nodes': [{'name': NAME, 'mesh': 0, 'skin': 0}, {'name': 'Root', 'children': [2]}, {'name': 'B'}],
        'skins': [{'name': NAME + '_Skin', 'joints': [1, 2], 'skeleton': 1, 'inverseBindMatrices': ibm}],
        'materials': [{'name': 'scaler', 'pbrMetallicRoughness': {'baseColorFactor': [0, 0, 0, 1]}}],
        'meshes': [{'name': NAME, 'primitives': [{'attributes': {'POSITION': pos, 'NORMAL': nrm, 'TEXCOORD_0': uv,
                                                                 'JOINTS_0': joints, 'WEIGHTS_0': weights},
                                                  'indices': idx, 'material': 0}]}],
        'animations': anims,
        'buffers': [{'uri': NAME + '.bin', 'byteLength': len(blob)}],
        'bufferViews': views, 'accessors': accessors,
    }
    open(os.path.join(OUT, NAME + '.bin'), 'wb').write(bytes(blob))
    json.dump(g, open(os.path.join(OUT, NAME + '.gltf'), 'w'), indent=1)
    print('scaler: %s with %s (%d keys each, 1 s)' % (NAME, ', '.join(a for a, _ in CURVES), n))


if __name__ == '__main__':
    main()
