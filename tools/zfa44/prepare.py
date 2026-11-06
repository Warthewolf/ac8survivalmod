"""prepare.py : the ZFA-44EL (the user's edited CFA-44 from their AC7 mod Alicorn Special Raid IV; tools/re/ZFA44.md)
made ready for UE 5.4's glTF import, as tools/x02s/prepare.py did VALKA's X-02S.

AGENTS.md (Toolchain) records the user's exception (2026-11-06): their ZFA-44's model and paint and the AC7 stock
assets they use, for a Survival special. Nothing read or written here is ever committed: the inputs are the extraction
in build/zfa44 (tools/re/ZFA44.md: UModel's glTF of the mod's uavs_SM, its sockets, the textures as PNG), the outputs
go to build/zfa44/prep.

The mesh (uavs_SM: a UE 4.18 STATIC mesh, 10 sections) becomes ONE SKELETAL mesh (a static mesh of ours added at run
time crashed AC8's renderer, SOLG test T0; the skeletal one drew, T0b; hard rule 46):
  SK_ZFA44.gltf / .bin    every vertex on bone Body (Root -> Body), life size: AC7's world is about 1/10 scale (1 unit =
                          10 cm, ZFA44.md 0), so 240.4 units = 24.0 m; UModel's glTF is in metres = units / 100, so x10.
                          The sockets as leaf bones of Body: the edited mesh's own (gun, ws1-3, vapor01 / 02), the
                          stock CFA-44's body sockets (burner_03 / 04, cam_*, pitchup_*, VFX_Dmg_*, GUNHIT01-20),
                          burner_01 / _02 at the nozzles (derived in ZFA44.md 2), the TLS pod's lens (laser), and the
                          x40a's effect socket names at the same kind of spot (as VALKA's skeleton carries them).
                          Four material slots: Body (sections 0, 2, 3, 7, 8, 9), Canopy (1 canopy, 5 the pod's lens),
                          Pod (4, the Morgan's TLS pod), Fairing (6, its fairing).
                          Sections 0 and 7 sample the body paint at negative U (AC7's MirrorSettings): folded (|u|), their
                          tangents turned with it. The fairing's UVs (u 0.254-0.371, v 0.877-0.997 of mrgn_00_D) remapped
                          onto a 512 px crop of that box.
  textures (PNG, ordinary: hard rule 44)
    T_ZFA44_C          the user's fa44_00_D, RGB (its alpha, 254-255, dropped: no DXT5)
    T_ZFA44_N          AC7's fa44_00_N (UE imports it as BC5; ue_import.py caps it at 2048)
    T_ZFA44_LM         AC8's Livemap as a constant 4 x 4 (R 0, G 191, B 255: the Falken add-on's; FALKEN_MATERIALS.md)
    T_ZFA44_LM_MREC    a Livemap from the user's fa44_00xMREC: R metallic, G roughness, B 255 (ZFA44.md 4.3; [I])
    T_ZFA44_Pod_C / _N        AC7's w_tls_x1_D / _N (2048)
    T_ZFA44_Fair_C / _N       AC7's mrgn_00_D / _N cropped to the fairing's box (512)
  layout.json             scale, slots, bones (UE cm, for ue_import.py's check and the Lua's notes)

Axes: UModel's glTF holds UE's (X, Y, Z) as (X, Z, Y) (the stock fa44's L_Nozzle_01 at glTF z -0.123: UE Y -12.3), and
UE 5.4's glTF import maps glTF (x, y, z) to UE (x, z, y) x 100 (tools/solg's axis probe), so positions round-trip;
bone rotations are written as S R S (S swaps y and z).
    py -3.12 -I tools/zfa44/prepare.py        (numpy and Pillow; tools/zfa44/build.sh runs it)
"""
import json, math, os, shutil

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
SRC = os.path.join(ROOT, 'build', 'zfa44')
MESH = os.path.join(SRC, 'mesh', 'uavs_SM.gltf')
OUT = os.path.join(SRC, 'prep')
NAME = 'SK_ZFA44'
UNIT_M = 0.1                       # one AC7 unit in metres (ZFA44.md 0); UModel's glTF holds units / 100
SCALE = UNIT_M * 100.0             # glTF value -> glTF metres at life size

# section -> slot (sections.json; ZFA44.md 2)
SLOTS = ('Body', 'Canopy', 'Pod', 'Fairing')
SECTION_SLOT = {0: 'Body', 1: 'Canopy', 2: 'Body', 3: 'Body', 4: 'Pod', 5: 'Canopy', 6: 'Fairing', 7: 'Body',
                8: 'Body', 9: 'Body'}
FOLD_U = (0, 7)                    # body-paint pieces sampled at negative U (AC7's MirrorSettings)
FAIRING_BOX = (0.25, 0.875, 0.375, 1.0)    # u0, v0, u1, v1 of mrgn_00_D: 512 x 512 px at 4096 (section 6 uses 0.254-0.371,
                                           # 0.877-0.997)

# Leaf bones of Body: name -> (location in AC7 units, mesh space, UE axes; rotation (pitch, yaw, roll) degrees).
# From build/zfa44/mesh/sockets.json: the edited mesh's sockets, the derived burners and laser, the stock CFA-44's body
# sockets (its body section is the stock body at rest, identical positions: ZFA44.md 2). Burners point aft (yaw 180), as
# the stock burner_03 / _04 do.
AFT = (0.0, 180.0, 0.0)
SOCKETS = {
    'gun': ((100.783, 8.22, 4.076), None), 'TEMP_muzzleFlash': ((100.783, 8.22, 4.076), None),
    'ws1': ((32.769, -0.095, 17.255), None), 'ws2': ((-10.393, 46.374, -4.714), None),
    'ws3': ((-10.393, -46.084, -4.714), None),
    'vapor01': ((-26.391, -72.448, -2.883), None), 'vapor02': ((-26.391, 71.603, -2.883), None),
    'burner_01': ((-51.0, -12.35, -2.7), AFT), 'burner_02': ((-51.0, 12.35, -2.7), AFT),
    'burner_03': ((-29.0, -12.35, -2.7), AFT), 'burner_04': ((-29.0, 12.35, -2.7), AFT),
    'laser': ((30.916, 0.0, 16.856), None),
    'cam_nose': ((165.251, 0.0, -2.165), None), 'cam_pilot': ((110.5, 0.0, 13.0), None),
    'cam_tailL': ((-31.0, -28.0, 11.0), None), 'cam_tailR': ((-31.0, 28.0, 11.0), None),
    'cam_thrusters': ((-50.941, 0.0, -2.7), None),
    'pitchup_body_01': ((107.437, -8.984, 0.056), None), 'pitchup_body_02': ((107.437, 8.984, 0.056), None),
    'pitchup_frtFlap_01': ((70.874, -14.122, 0.034), None), 'pitchup_frtFlap_02': ((70.874, 14.122, 0.034), None),
    'VFX_Dmg_Body': ((8.534, 5.144, 5.192), None), 'VFX_Dmg_WingL': ((-2.716, -48.009, 0.841), None),
    'VFX_Dmg_WingR': ((9.021, 37.489, 1.441), None), 'VFX_Dmg_Engine': ((-46.775, 12.35, -2.7), None),
}
GUNHITS = [(20.129, 27.249, -3.087), (-40.376, -17.566, -8.643), (115.354, 3.567, -3.944), (48.922, 12.177, -12.042),
           (72.199, -1.442, -7.504), (34.121, -23.31, -10.267), (-23.79, -1.637, -9.332), (-8.076, 13.515, -12.644),
           (-10.841, 37.95, -2.581), (4.635, -35.385, -2.136), (10.024, 6.776, 5.377), (-31.969, 12.099, 5.339),
           (92.47, -5.991, 9.738), (67.241, 8.83, 9.38), (-6.689, 46.212, 1.461), (-49.283, -0.679, 4.017),
           (19.826, 32.552, 2.713), (1.621, -39.119, 1.154), (36.242, -7.835, 5.944), (-8.657, -12.451, 5.194)]
for i, p in enumerate(GUNHITS):                       # (sockets.json lists GUNHIT20 first, GUNHIT01 last)
    SOCKETS['GUNHIT%02d' % (20 - i)] = (p, None)
# the x40a's effect socket names (AC8 DT_OP0016_x40a_FX_MapTable; tools/x02s/ue_import.py X40A_ALIASES) at the ZFA-44's
# own spot of that kind, so an effect asked for by one of them finds a bone here
ALIASES = {
    'core01': 'burner_01', 'cone01': 'burner_01', 'fakeLight01': 'burner_01', 'SOC_EF_Burner_01': 'burner_01',
    'core02': 'burner_02', 'cone02': 'burner_02', 'fakeLight02': 'burner_02', 'SOC_EF_Burner_02': 'burner_02',
    'SOC_R_EF_Burner': 'burner_02', 'ShoulderVaporL': 'pitchup_body_01', 'ShoulderVaporR': 'pitchup_body_02',
    'WingOverVaporL': 'vapor01', 'WingOverVaporR': 'vapor02',
}

S = np.array([[1, 0, 0], [0, 0, 1], [0, 1, 0]], np.float64)   # UE <-> glTF (a swap of y and z: its own inverse)


def ue_rot(rot):
    """UE's FRotationMatrix(pitch, yaw, roll) as a column-vector rotation (columns = the X, Y, Z axes)."""
    p, y, r = (math.radians(v) for v in rot)
    sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    x = [cp * cy, cp * sy, sp]
    yv = [sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp]
    z = [-(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp]
    return np.array([x, yv, z], np.float64).T


def rquat(R):
    """Rotation matrix -> quaternion (x, y, z, w) (tools/solg/prepare.py)."""
    t = np.trace(R)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2; w = 0.25 * s
        x = (R[2, 1] - R[1, 2]) / s; y = (R[0, 2] - R[2, 0]) / s; z = (R[1, 0] - R[0, 1]) / s
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        s = math.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2]) * 2; w = (R[2, 1] - R[1, 2]) / s
        x = 0.25 * s; y = (R[0, 1] + R[1, 0]) / s; z = (R[0, 2] + R[2, 0]) / s
    elif R[1, 1] > R[2, 2]:
        s = math.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2]) * 2; w = (R[0, 2] - R[2, 0]) / s
        x = (R[0, 1] + R[1, 0]) / s; y = 0.25 * s; z = (R[1, 2] + R[2, 1]) / s
    else:
        s = math.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1]) * 2; w = (R[1, 0] - R[0, 1]) / s
        x = (R[0, 2] + R[2, 0]) / s; y = (R[1, 2] + R[2, 1]) / s; z = 0.25 * s
    q = np.array([x, y, z, w]); return q / np.linalg.norm(q)


def read_gltf():
    g = json.load(open(MESH, encoding='utf-8'))
    blob = open(os.path.join(os.path.dirname(MESH), g['buffers'][0]['uri']), 'rb').read()

    def acc(i):
        a = g['accessors'][i]
        v = g['bufferViews'][a['bufferView']]
        n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[a['componentType']]
        assert not v.get('byteStride'), 'interleaved buffers not handled'
        arr = np.frombuffer(blob, dt, count=a['count'] * n, offset=v.get('byteOffset', 0) + a.get('byteOffset', 0))
        return arr.reshape(a['count'], n).astype(np.float64 if dt == np.float32 else np.int64) if n > 1 else arr.astype(np.int64)

    out = []
    for i, p in enumerate(g['meshes'][0]['primitives']):
        at = p['attributes']
        out.append({'section': i, 'P': acc(at['POSITION']), 'N': acc(at['NORMAL']), 'T': acc(at['TANGENT']),
                    'UV': acc(at['TEXCOORD_0']), 'I': acc(p['indices'])})
    assert len(out) == 10, f'{len(out)} sections (ZFA44.md: 10)'
    return out


def build_mesh(sections):
    """The skinned glTF (tools/solg/prepare.py write_skinned's layout: node 0 the mesh, node 1 the root joint)."""
    blob = bytearray()
    views, accessors = [], []

    def add(arr, target, kind, ctype, minmax=False, normalized=False):
        a = np.ascontiguousarray(arr)
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': a.nbytes, **({'target': target} if target else {})})
        blob.extend(a.tobytes())
        cnt = int(a.shape[0]) if kind != 'SCALAR' else int(a.size)
        acc = {'bufferView': len(views) - 1, 'componentType': ctype, 'count': cnt, 'type': kind}
        if minmax:
            acc['min'] = a.min(0).tolist(); acc['max'] = a.max(0).tolist()
        if normalized:
            acc['normalized'] = True
        accessors.append(acc)
        return len(accessors) - 1

    body_joint = 1                                    # joints: 0 Root, 1 Body, 2.. the leaves
    prims, stats = [], []
    lo, hi = np.full(3, 1e9), np.full(3, -1e9)
    for s in sections:
        k = s['section']
        P = s['P'] * SCALE
        N, T, UV = s['N'].copy(), s['T'].copy(), s['UV'].copy()
        how = ''
        if k in FOLD_U:
            neg = UV[:, 0] < 0
            UV[neg, 0] = -UV[neg, 0]
            T[neg, :3] = -T[neg, :3]                  # (u mirrored: dP/du and the bitangent's sign turn with it)
            T[neg, 3] = -T[neg, 3]
            how = f', {int(neg.sum())} UVs folded'
        if SECTION_SLOT[k] == 'Fairing':
            u0, v0, u1, v1 = FAIRING_BOX
            assert UV[:, 0].min() >= u0 and UV[:, 0].max() <= u1 and UV[:, 1].min() >= v0 and UV[:, 1].max() <= v1, \
                'the fairing samples outside its crop box'
            UV[:, 0] = (UV[:, 0] - u0) / (u1 - u0)
            UV[:, 1] = (UV[:, 1] - v0) / (v1 - v0)
            how = ', UVs onto the fairing crop'
        n = len(P)
        lo, hi = np.minimum(lo, P.min(0)), np.maximum(hi, P.max(0))
        J = np.zeros((n, 4), np.uint16); J[:, 0] = body_joint
        W = np.zeros((n, 4), np.float32); W[:, 0] = 1.0
        C = np.full((n, 4), 255, np.uint8)
        uv32 = UV.astype(np.float32)
        prims.append({'attributes': {'POSITION': add(P.astype(np.float32), 34962, 'VEC3', 5126, True),
                                     'NORMAL': add(N.astype(np.float32), 34962, 'VEC3', 5126),
                                     'TANGENT': add(T.astype(np.float32), 34962, 'VEC4', 5126),
                                     'TEXCOORD_0': add(uv32, 34962, 'VEC2', 5126),
                                     'TEXCOORD_1': add(uv32, 34962, 'VEC2', 5126),
                                     'COLOR_0': add(C, 34962, 'VEC4', 5121, normalized=True),
                                     'JOINTS_0': add(J, 34962, 'VEC4', 5123),
                                     'WEIGHTS_0': add(W, 34962, 'VEC4', 5126)},
                      'indices': add(s['I'].astype(np.uint32), 34963, 'SCALAR', 5125),
                      'material': SLOTS.index(SECTION_SLOT[k]), 'mode': 4})
        stats.append(f'section {k} -> {SECTION_SLOT[k]}: {n} vertices, {len(s["I"]) // 3} triangles{how}')

    # bones (UE cm for the layout; glTF metres in the file)
    bones = [('Root', None, None), ('Body', None, None)]
    for name, (loc, rot) in SOCKETS.items():
        bones.append((name, loc, rot))
    for name, src in ALIASES.items():
        loc, rot = SOCKETS[src]
        bones.append((name, loc, rot))
    nodes = [{'name': NAME, 'mesh': 0, 'skin': 0}, {'name': 'Root', 'children': [2]},
             {'name': 'Body', 'children': list(range(3, len(bones) + 1))}]
    ibm, layout_bones = [], {}
    for k, (name, loc, rot) in enumerate(bones):
        M = np.eye(4)
        if loc is not None:
            ue = np.array(loc, np.float64) * UNIT_M              # metres, UE axes
            g = S @ ue                                          # glTF axes
            R = S @ ue_rot(rot) @ S if rot else np.eye(3)
            nd = {'name': name, 'translation': [float(v) for v in g]}
            if rot:
                nd['rotation'] = [float(v) for v in rquat(R)]
            nodes.append(nd)
            M[:3, :3] = R; M[:3, 3] = g                         # (its parent Body is identity at the origin)
            layout_bones[name] = {'ue_cm': [round(float(v) * 100, 2) for v in ue], 'rot': list(rot) if rot else None}
        ibm.append(np.linalg.inv(M).T.reshape(-1))              # column-major
    ibm = np.stack(ibm).astype(np.float32)
    mats = [{'name': m, 'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0, 'roughnessFactor': 1}}
            for m in SLOTS]
    g = {'asset': {'version': '2.0', 'generator': 'AC8 Survival Mode tools/zfa44/prepare.py'},
         'scene': 0, 'scenes': [{'nodes': [0, 1]}], 'nodes': nodes,
         'skins': [{'name': NAME + '_Skin', 'joints': list(range(1, len(bones) + 1)), 'skeleton': 1,
                    'inverseBindMatrices': add(ibm, None, 'MAT4', 5126)}],
         'meshes': [{'name': NAME, 'primitives': prims}], 'materials': mats,
         'buffers': [{'uri': NAME + '.bin', 'byteLength': len(blob)}], 'bufferViews': views, 'accessors': accessors}
    open(os.path.join(OUT, NAME + '.bin'), 'wb').write(bytes(blob))
    json.dump(g, open(os.path.join(OUT, NAME + '.gltf'), 'w'), indent=1)
    ue_lo, ue_hi = S @ lo * 100, S @ hi * 100                    # (S on a box: the y / z bounds swap)
    size_m = (hi - lo)                                         # glTF axes: x length, y height, z span
    return {'stats': stats, 'bones': layout_bones, 'bounds_cm': {'min': [round(float(v), 1) for v in ue_lo],
                                                                  'max': [round(float(v), 1) for v in ue_hi]},
            'size_m': {'length': round(float(size_m[0]), 2), 'span': round(float(size_m[2]), 2),
                       'height': round(float(size_m[1]), 2)}}


def png(img, name):
    path = os.path.join(OUT, name + '.png')
    img.save(path, optimize=False)
    return f'{name} {img.size[0]}x{img.size[1]} {img.mode}'


def textures():
    tex = os.path.join(SRC, 'tex')
    made = []
    made.append(png(Image.open(os.path.join(tex, 'mod', 'fa44_00_D.png')).convert('RGB'), 'T_ZFA44_C'))
    made.append(png(Image.open(os.path.join(tex, 'stock', 'fa44_00_N.png')).convert('RGB'), 'T_ZFA44_N'))
    made.append(png(Image.new('RGB', (4, 4), (0, 191, 255)), 'T_ZFA44_LM'))
    m = np.asarray(Image.open(os.path.join(tex, 'mod', 'fa44_00xMREC.png')))   # (RGBA: read raw, never resized with alpha)
    lm = np.empty(m.shape[:2] + (3,), np.uint8)
    lm[..., 0], lm[..., 1], lm[..., 2] = m[..., 0], m[..., 1], 255
    made.append(png(Image.fromarray(lm, 'RGB'), 'T_ZFA44_LM_MREC'))
    made.append(png(Image.open(os.path.join(tex, 'stock', 'w_tls_x1_D.png')).convert('RGB'), 'T_ZFA44_Pod_C'))
    made.append(png(Image.open(os.path.join(tex, 'stock', 'w_tls_x1_N.png')).convert('RGB'), 'T_ZFA44_Pod_N'))
    for src, dst in (('mrgn_00_D.png', 'T_ZFA44_Fair_C'), ('mrgn_00_N.png', 'T_ZFA44_Fair_N')):
        im = Image.open(os.path.join(tex, 'stock', src)).convert('RGB')
        w, h = im.size
        u0, v0, u1, v1 = FAIRING_BOX
        made.append(png(im.crop((round(u0 * w), round(v0 * h), round(u1 * w), round(v1 * h))), dst))
    return made


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    sections = read_gltf()
    info = build_mesh(sections)
    made = textures()
    layout = {'mesh': NAME, 'slots': list(SLOTS), 'unit_m': UNIT_M, 'section_slot': SECTION_SLOT, **info,
              'textures': made}
    json.dump(layout, open(os.path.join(OUT, 'layout.json'), 'w'), indent=1)
    for line in info['stats']:
        print('zfa44: ' + line)
    print(f"zfa44: {NAME}: {len(info['bones'])} socket bones on Body, {info['size_m']['length']} m long, "
          f"{info['size_m']['span']} m span, {info['size_m']['height']} m tall; bounds {info['bounds_cm']} cm")
    for t in made:
        print('zfa44: texture ' + t)
    b = info['bones']
    print(f"zfa44: burner_01 {b['burner_01']['ue_cm']} cm, burner_02 {b['burner_02']['ue_cm']} cm, "
          f"vapor01 {b['vapor01']['ue_cm']}, cam_nose {b['cam_nose']['ue_cm']} -> {os.path.normpath(OUT)}")


if __name__ == '__main__':
    main()
