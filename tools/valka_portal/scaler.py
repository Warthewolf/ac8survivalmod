"""scaler.py <out folder> : VALKA's portal's scaler (the user, 2026-11-22: "the portal opening and closing is so laggy
its not smooth at all"). Survival's Lua runs 4 times a second (sv_main.lua's loop: one tick of 250 ms, a faster or a
second loop crashed UE4SS's Lua), so a piece scaled by it grows in steps. The engine plays an animation every frame:
each portal piece hangs on its own scaler (Scripts/sv_anomalies.lua portalMesh) and grows, holds and shrinks with its
one bone, B. Writes SK_SV_PortalScaler.gltf / .bin: bones Root and B, one triangle 1 mm across skinned to B (never
seen), and three animations of B's scale, each 1 s long, LINEAR keys every 1/60 s:
  A_SV_PortalGrow    0.001 -> 1, out fast and settling (1 - (1 - t)^3, the opening's curve)
  A_SV_PortalHold    1
  A_SV_PortalShrink  1 -> 0.001, falling in faster and faster (1 - t^2, the closing's)
Lua plays one at the rate 1 / its window's length (a piece's open / close window, shares of open_s / close_s).
Plain Python (no numpy, no Blender)."""
import json
import os
import struct
import sys

OUT = sys.argv[1]
NAME = 'SK_SV_PortalScaler'
FPS, MINS = 60, 0.001
CURVES = [('A_SV_PortalGrow', lambda t: MINS + (1 - MINS) * (1 - (1 - t) ** 3)),
          ('A_SV_PortalHold', lambda t: 1.0),
          ('A_SV_PortalShrink', lambda t: MINS + (1 - MINS) * (1 - t * t))]


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
        anims.append({'name': aname, 'samplers': [{'input': tin, 'output': o, 'interpolation': 'LINEAR'}],
                      'channels': [{'sampler': 0, 'target': {'node': 1, 'path': 'scale'}}]})
    g = {
        'asset': {'version': '2.0', 'generator': 'tools/valka_portal/scaler.py'},
        'scene': 0, 'scenes': [{'nodes': [0, 2]}],
        'nodes': [{'name': 'Root', 'children': [1]}, {'name': 'B'}, {'name': NAME, 'mesh': 0, 'skin': 0}],
        'skins': [{'joints': [0, 1], 'skeleton': 0, 'inverseBindMatrices': ibm}],
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
