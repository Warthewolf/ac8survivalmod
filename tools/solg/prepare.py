"""prepare.py : AC:I's SOLG (Special Raid "Satellite Interception") -> build/solg, for tools/solg/ue_import.py.

  py -3.12 -I tools/solg/prepare.py            (needs numpy + Pillow, Inveigh's AC:I kit and an AC:I install:
                                                .env's ACI: the AC:I folder; ACI_KIT = the kit's tools folder,
                                                default $ACI/aci_kit/tools; ACI_USRDIR = the install's USRDIR,
                                                default $ACI/NPUB31347/USRDIR)

AC:I assets are allowed for the SOLG round only (the user, 2026-11-03; tools/re/SOLG.md). Nothing here is committed:
the outputs go to build/solg.

Reads DATA01 entry 213 (SOLG -Schroeter-'s models: every SOLG texture is in it) and writes:
  <mesh>.gltf / .bin   one static mesh each: the body (s_solg) and its nine part models (s_sg01 .. s_sg09), live (the
                       `_l1` mesh) and destroyed (`_d1`, "<mesh>_Wreck"). glTF is right-handed, +Y up, +Z forward, +X
                       left, metres: AC:I's own model space, so the vertices go in as they are.
  T_SV_SOLG_<id>.png   every texture they use, named by AC:I texture id (as Stonehenge Returns' T_SH_tex<id>)
  layout.json          the meshes (vertex / triangle counts, AC:I bounds, texture per glTF material) and the body's
                       part mount points (its 68-node tree's plan_node_<model>_<nn>: AC:I position and rotation)
"""
import json, math, os, re, struct, sys
import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import env                                   # noqa: E402  (.env: ACI, the user's AC:I folder; no machine path here)
ACI = env.need('ACI', "the user's Ace Combat Infinity folder (its aci_kit and NPUB31347\\USRDIR; tools/solg)")
KIT = os.environ.get('ACI_KIT', os.path.join(ACI, 'aci_kit', 'tools'))
os.environ.setdefault('ACI_USRDIR', os.path.join(ACI, 'NPUB31347', 'USRDIR'))
sys.path.insert(0, KIT)
from fhm import DPL, fhm_tree, flat          # noqa: E402  (the kit)
import ndp3, ntp3, skel                      # noqa: E402

OUT = os.path.join(ROOT, 'build', 'solg')
PAC, ENTRY = 'DATA01', 213
MODELS = ['s_solg'] + ['s_sg%02d' % i for i in range(1, 10)]
NAME = {'s_solg': 'SM_SV_SOLG_Body', **{'s_sg%02d' % i: 'SM_SV_SOLG_SG%02d' % i for i in range(1, 10)}}


# AC:I -> glTF: a quarter turn about up (a proper rotation, no mirror), so the SOLG's long axis (AC:I +Z, the core /
# nose end) becomes glTF +X: UE 5.4's glTF importer maps glTF (x, y, z) to UE (x, z, y) (measured by ue_import.py's
# probe, 2026-11-03), so the nose points along UE +X, an AI plane's forward, and AC:I +X (left) lands on UE -Y (left).
TURN = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], np.float64)


def turned(v):
    return np.asarray(v, np.float64) @ TURN.T


def meshes_of(d, ch, model, state):
    """The NDP3 whose first group is <model>_<state>_O... -> [(P, N, UV, T, texture id)] (the kit's ndp3 reader)."""
    for c in ch:
        if c[1] != b'NDP3':
            continue
        b = d[c[2]:c[2] + c[3]]
        gs = ndp3.parse(b)
        if gs and gs[0]['name'].startswith('%s_%s_O' % (model, state)):
            out = []
            for g in gs:
                for r in g['rgs']:
                    x = ndp3.read_rg(b, r)
                    if x is None:
                        raise SystemExit('%s %s: render group %s not readable (vertex format %#x)' % (model, state, g['name'], r['vfmt']))
                    out.append((turned(x[0]), turned(x[1]), x[2], x[3], r['tex'][0] if r['tex'] else 0))
            return out
    raise SystemExit('%s: no %s mesh in %s:%d' % (model, state, PAC, ENTRY))


def export_textures(d, ch, outdir):
    """Every texture of the package's first NTP3 block -> <outdir>/<id>.png: {id: (path, w, h, fmt)}. As the kit's
    ntp3.export, but the id is read after the header's GIDX tag: headers are 128 or 112 bytes (the s_sg08 texture,
    0x20004c3e, has a 112-byte one), so the kit's fixed +0x78 misreads some."""
    os.makedirs(outdir, exist_ok=True)
    i = [k for k, c in enumerate(ch) if c[1] == b'NTP3'][0]
    n = struct.unpack_from('>H', d, ch[i][2] + 6)[0]
    heads, datas = ch[i + 1:i + 1 + n], ch[i + 1 + n:i + 1 + 2 * n]
    out = {}
    for h, c in zip(heads, datas):
        hb = d[h[2]:h[2] + h[3]]
        g = hb.find(b'GIDX')
        if g < 0:
            continue
        tid = struct.unpack_from('>I', hb, g + 8)[0]
        mips, fmt, w, hh = struct.unpack_from('>HHHH', hb, 0x10)
        if fmt not in ntp3.FOURCC:
            out[tid] = None; continue
        im = ntp3.dds(w, hh, fmt, d[c[2]:c[2] + c[3]]).convert('RGBA')
        p = os.path.join(outdir, '%08x.png' % tid)
        im.save(p)
        out[tid] = (p, w, hh, fmt)
    return out


def qmat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def front_facing(P, N, T):
    """+1 when the triangles wind counter-clockwise round their vertex normals (glTF's front face), -1 when clockwise."""
    a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    fn = np.cross(b - a, c - a)
    vn = N[T[:, 0]] + N[T[:, 1]] + N[T[:, 2]]
    s = float(np.sum(np.einsum('ij,ij->i', fn, vn)))
    return 1 if s >= 0 else -1


def write_gltf(name, parts):
    """parts: [(P, N, UV, T, tex)] -> <name>.gltf + .bin, one primitive (and material) per render group."""
    blob = bytearray()
    views, accessors, prims, mats, matidx = [], [], [], [], {}

    def add(arr, target, kind, minmax=False):
        a = np.ascontiguousarray(arr)
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': a.nbytes, **({'target': target} if target else {})})
        blob.extend(a.tobytes())
        acc = {'bufferView': len(views) - 1, 'componentType': 5126 if a.dtype == np.float32 else 5125,
               'count': int(a.shape[0]) if kind != 'SCALAR' else int(a.size), 'type': kind}
        if minmax:
            acc['min'] = a.min(0).tolist(); acc['max'] = a.max(0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    flipped = 0
    for P, N, UV, T, tex in parts:
        P = P.astype(np.float32); N = N.astype(np.float32); UV = UV.astype(np.float32)
        ln = np.linalg.norm(N, axis=1, keepdims=True); ln[ln == 0] = 1; N = N / ln
        T = T.astype(np.uint32)
        if front_facing(P, N, T) < 0:
            T = T[:, [0, 2, 1]]; flipped += 1
        m = 't%08x' % tex
        if m not in matidx:
            matidx[m] = len(mats)
            mats.append({'name': m, 'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0, 'roughnessFactor': 1}})
        prims.append({'attributes': {'POSITION': add(P, 34962, 'VEC3', True), 'NORMAL': add(N, 34962, 'VEC3'),
                                     'TEXCOORD_0': add(UV, 34962, 'VEC2')},
                      'indices': add(T.reshape(-1), 34963, 'SCALAR'), 'material': matidx[m], 'mode': 4})
    g = {'asset': {'version': '2.0', 'generator': 'AC8 Survival Mode tools/solg/prepare.py'},
         'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'name': name, 'mesh': 0}],
         'meshes': [{'name': name, 'primitives': prims}], 'materials': mats,
         'buffers': [{'uri': name + '.bin', 'byteLength': len(blob)}], 'bufferViews': views, 'accessors': accessors}
    open(os.path.join(OUT, name + '.bin'), 'wb').write(bytes(blob))
    json.dump(g, open(os.path.join(OUT, name + '.gltf'), 'w'), indent=1)
    return flipped


def mat4(R, p):
    """4x4 (row-major numpy) of rotation R and translation p."""
    M = np.eye(4); M[:3, :3] = R; M[:3, 3] = p
    return M


def rquat(R):
    """Rotation matrix -> quaternion (x, y, z, w)."""
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


def write_skinned(name, pieces, bones):
    """The whole SOLG as one skinned glTF (the cooked static meshes crashed AC8's renderer in test T0, 2026-11-03; a
    skeletal mesh added at run time is proven: VALKA, hard rule 46). bones: [(name, R, p)] in the turned frame, the
    first the root (identity); pieces: [(bone index, [(P, N, UV, T, tex)] in that bone's frame)]. Each vertex is put
    in the bind pose (R . v + p) and skinned 100 % to its bone; one primitive per (piece, render group)."""
    blob = bytearray()
    views, accessors = [], []

    def add(arr, target, kind, ctype, minmax=False):
        a = np.ascontiguousarray(arr)
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': a.nbytes, **({'target': target} if target else {})})
        blob.extend(a.tobytes())
        cnt = int(a.shape[0]) if kind not in ('SCALAR',) else int(a.size)
        acc = {'bufferView': len(views) - 1, 'componentType': ctype, 'count': cnt, 'type': kind}
        if minmax:
            acc['min'] = a.min(0).tolist(); acc['max'] = a.max(0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    mats, matidx, prims = [], {}, []
    for bi, parts in pieces:
        _, R, p = bones[bi]
        for P, N, UV, T, tex in parts:
            Pw = (np.asarray(P, np.float64) @ R.T + p).astype(np.float32)
            Nw = (np.asarray(N, np.float64) @ R.T).astype(np.float32)
            ln = np.linalg.norm(Nw, axis=1, keepdims=True); ln[ln == 0] = 1; Nw = Nw / ln
            T = T.astype(np.uint32)
            if front_facing(Pw, Nw, T) < 0:
                T = T[:, [0, 2, 1]]
            m = 't%08x' % tex
            if m not in matidx:
                matidx[m] = len(mats)
                mats.append({'name': m, 'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0, 'roughnessFactor': 1}})
            J = np.zeros((len(Pw), 4), np.uint16); J[:, 0] = bi
            Wt = np.zeros((len(Pw), 4), np.float32); Wt[:, 0] = 1.0
            prims.append({'attributes': {'POSITION': add(Pw, 34962, 'VEC3', 5126, True), 'NORMAL': add(Nw, 34962, 'VEC3', 5126),
                                         'TEXCOORD_0': add(UV.astype(np.float32), 34962, 'VEC2', 5126),
                                         'JOINTS_0': add(J, 34962, 'VEC4', 5123), 'WEIGHTS_0': add(Wt, 34962, 'VEC4', 5126)},
                          'indices': add(T.reshape(-1), 34963, 'SCALAR', 5125), 'material': matidx[m], 'mode': 4})
    # joints: node 1 the root, every other a child of it (its transform = its bind pose: the root is identity)
    nodes = [{'name': name, 'mesh': 0, 'skin': 0}]
    for k, (bn, R, p) in enumerate(bones):
        nd = {'name': bn}
        if k > 0:
            nd['translation'] = [float(v) for v in p]
            nd['rotation'] = [float(v) for v in rquat(R)]
        nodes.append(nd)
    nodes[1]['children'] = list(range(2, len(bones) + 1))
    ibm = np.stack([np.linalg.inv(mat4(R, p)).T.reshape(-1) for _, R, p in bones]).astype(np.float32)   # column-major
    g = {'asset': {'version': '2.0', 'generator': 'AC8 Survival Mode tools/solg/prepare.py'},
         'scene': 0, 'scenes': [{'nodes': [0, 1]}], 'nodes': nodes,
         'skins': [{'name': name + '_Skin', 'joints': list(range(1, len(bones) + 1)), 'skeleton': 1,
                    'inverseBindMatrices': add(ibm, None, 'MAT4', 5126)}],
         'meshes': [{'name': name, 'primitives': prims}], 'materials': mats,
         'buffers': [{'uri': name + '.bin', 'byteLength': len(blob)}], 'bufferViews': views, 'accessors': accessors}
    open(os.path.join(OUT, name + '.bin'), 'wb').write(bytes(blob))
    json.dump(g, open(os.path.join(OUT, name + '.gltf'), 'w'))
    return len(prims), sum(a['count'] for a in accessors if a['type'] == 'VEC3' and 'min' in a)


def main():
    os.makedirs(OUT, exist_ok=True)
    d = DPL(os.path.join(os.environ['ACI_USRDIR'], PAC + '.PAC')).read(ENTRY)
    ch = list(flat(fhm_tree(d)))
    layout = {'source': '%s:%d' % (PAC, ENTRY), 'meshes': {}, 'mounts': []}
    texids, cache = set(), {}
    for model in MODELS:
        for state, suffix in (('l1', ''), ('d1', '_Wreck')):
            parts = meshes_of(d, ch, model, state)
            cache[(model, state)] = parts
            name = NAME[model] + suffix
            flipped = write_gltf(name, parts)
            P = np.concatenate([p[0] for p in parts])
            texids.update(p[4] for p in parts)
            layout['meshes'][name] = {
                'model': model, 'state': state, 'vertices': int(len(P)), 'triangles': int(sum(len(p[3]) for p in parts)),
                'min_m': P.min(0).round(3).tolist(), 'max_m': P.max(0).round(3).tolist(),
                'materials': ['t%08x' % p[4] for p in parts], 'winding_flipped': flipped}
            print('%-24s %6d vertices %6d triangles  bounds %s .. %s  (%d groups flipped)' % (
                name, len(P), layout['meshes'][name]['triangles'], layout['meshes'][name]['min_m'],
                layout['meshes'][name]['max_m'], flipped))
    # the body's 68-node tree: the plan nodes are where the parts are mounted
    k = next(k for k, c in enumerate(ch) if c[1] == b'MNT\x00' and b'plan_node_f_sgc1' in d[c[2]:c[2] + c[3]])
    mn, mo = ch[k], next(c for c in ch[k + 1:] if c[1] == b'MOP2')
    names, par = skel.parse_mnt(d[mn[2]:mn[2] + mn[3]])
    cl = skel.clips(d[mo[2]:mo[2] + mo[3]])
    pos, rot = skel.basepose(cl['basepose'], len(names))
    W = skel.world(par, pos, rot)
    for i, n in enumerate(names):
        m = re.fullmatch(r'plan_node_([sf]_sg[c0-9]\d)_?(\d\d)?', n)
        if not m:
            continue
        R = TURN @ qmat(W[i][1]) @ TURN.T            # the mount's rotation in the turned frame
        layout['mounts'].append({'node': n, 'model': m.group(1), 'index': int(m.group(2) or 1),
                                 'parent': names[par[i]] if par[i] >= 0 else None,
                                 'pos_m': np.round(turned(W[i][0]), 4).tolist(), 'rot_m': np.round(R, 6).tolist(),
                                 'aci_pos_m': np.round(W[i][0], 4).tolist()})
    layout['rings'] = {n: np.round(turned(W[i][0]), 4).tolist() for i, n in enumerate(names) if n.startswith('auta')}
    layout['frame'] = 'glTF = AC:I turned: (AC.z, AC.y, -AC.x); UE = (AC.z, -AC.x, AC.y) x 100 (nose along UE +X)'
    counts = {}
    for mt in layout['mounts']:
        counts[mt['model']] = counts.get(mt['model'], 0) + 1
    print('mounts:', ', '.join('%s x%d' % kv for kv in sorted(counts.items())))
    # the skeletal SOLG: root SOLG (the body; SOLG_W its wreck), a bone per mount (<KEY>_<nn>: the piece) and one beside
    # it (<KEY>_<nn>_W: its destroyed mesh, hidden at the start by Scripts/sv_solg.lua), CORE_01 (f_sgc1: the SP
    # shell's place, no mesh of its own) and RING_1 / RING_2 (no mesh)
    I3 = np.eye(3)
    bones = [('SOLG', I3, np.zeros(3)), ('SOLG_W', I3, np.zeros(3))]
    pieces = [(0, cache[('s_solg', 'l1')]), (1, cache[('s_solg', 'd1')])]
    for mt in layout['mounts']:
        R, p = np.array(mt['rot_m']), np.array(mt['pos_m'])
        if mt['model'] == 'f_sgc1':
            bones.append(('CORE_%02d' % mt['index'], R, p))
            continue
        key = '%s_%02d' % (mt['model'][2:].upper(), mt['index'])
        bones.append((key, R, p)); pieces.append((len(bones) - 1, cache[(mt['model'], 'l1')]))
        bones.append((key + '_W', R, p)); pieces.append((len(bones) - 1, cache[(mt['model'], 'd1')]))
    for n, pos in sorted(layout['rings'].items()):
        bones.append(('RING_' + n[-1], I3, np.array(pos)))
    nprim, nvert = write_skinned('SK_SV_SOLG', pieces, bones)
    layout['skeletal'] = {'mesh': 'SK_SV_SOLG', 'bones': [b[0] for b in bones], 'primitives': nprim, 'vertices': nvert}
    print('SK_SV_SOLG: %d bones, %d primitives, %d vertices' % (len(bones), nprim, nvert))
    # textures: every texture in the package as <id>.png, then the ones the meshes use renamed
    tmp = os.path.join(OUT, 'tex_all')
    got = export_textures(d, ch, tmp)
    layout['textures'] = {}
    for t in sorted(texids):
        if not got.get(t):
            raise SystemExit('texture %08x missing from %s:%d' % (t, PAC, ENTRY))
        src, w, h, fmt = got[t]
        dst = os.path.join(OUT, 'T_SV_SOLG_%08x.png' % t)
        os.replace(src, dst)
        layout['textures']['t%08x' % t] = {'file': os.path.basename(dst), 'size': [w, h], 'dxt': fmt}
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)
    # flat maps for AC8's M_Live_Base (tools/solg/ue_import.py): a neutral normal and a neutral Livemap
    from PIL import Image
    Image.new('RGBA', (4, 4), (128, 128, 255, 255)).save(os.path.join(OUT, 'T_SV_SOLG_FlatN.png'))
    Image.new('RGBA', (4, 4), (0, 191, 255, 255)).save(os.path.join(OUT, 'T_SV_SOLG_FlatL.png'))
    json.dump(layout, open(os.path.join(OUT, 'layout.json'), 'w'), indent=1)
    print('textures:', ', '.join(sorted(layout['textures'])))
    print('wrote', OUT)


if __name__ == '__main__':
    main()
