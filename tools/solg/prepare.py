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
CUT = 429                                    # (DATA01: the SOLG's arrival cutscene: where its KEW shells sit)
# the versions' skins (main(): SOLG_SKIN): package, entry, {the first set's texture id: the skin's}
SKINS = {'gould': ('DATA92', 528, {0x20004c40: 0x200055ff, 0x20004c3d: 0x20005600, 0x200051da: 0x20005601,
                                   0x20004c3f: 0x20005603, 0x20004c43: 0x20005605, 0x20004e4d: 0x20005606,
                                   0x20004c3e: 0x20005607, 0x20004fa9: 0x20005608, 0x20004dae: 0x20005609,
                                   0x2000520c: 0x2000560a, 0x20004c42: 0x2000560b,
                                   0x20004fa4: 0x20005604, 0x200051db: 0x20005602})}   # (the panels' second textures)
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


def anim_gltf(a, bones, parents, W, add):
    """a = {'name', 'length_s', 'keys', 'bones': {bone name: (axis (3,), turns over length_s)}}: each listed bone turned
    about its own axis (in its own frame) from its rest; LINEAR quaternion keys"""
    names = [b[0] for b in bones]
    t = np.linspace(0.0, a['length_s'], a['keys'] + 1).astype(np.float32)
    samplers, channels = [], []
    tin = add(t, None, 'SCALAR', 5126, False)
    accessors_minmax = (float(t.min()), float(t.max()))
    for bn, (axis, turns) in a['bones'].items():
        k = names.index(bn)
        L = np.linalg.inv(W[parents[k]]) @ W[k]
        rest = rquat(L[:3, :3])
        ax = np.asarray(axis, np.float64) / np.linalg.norm(axis)
        out = []
        for ti in t:
            ang = 2 * math.pi * turns * ti / a['length_s']
            q = np.array([*(ax * math.sin(ang / 2)), math.cos(ang / 2)])
            x1, y1, z1, w1 = rest
            x2, y2, z2, w2 = q                       # rest . spin (the spin in the bone's own frame)
            out.append([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                        w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2])
        o = add(np.asarray(out, np.float32), None, 'VEC4', 5126, False)
        samplers.append({'input': tin, 'output': o, 'interpolation': 'LINEAR'})
        channels.append({'sampler': len(samplers) - 1, 'target': {'node': k + 1, 'path': 'rotation'}})
    return {'name': a['name'], 'samplers': samplers, 'channels': channels, '_minmax': accessors_minmax}


def write_skinned(name, pieces, bones, parents=None, anims=None):
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
            # ((2026-11-22) the user: "the internal hallway of the SOLG isn't visible and neither is the rear hatch": AC:I
            # draws the SOLG from both sides; AC8 culls back faces, so its inner shaft's walls (facing out) and the flat
            # hatch (s_sg08) showed from one side only. Every face doubled, the copy turned round with its normals:
            # a two-sided material can't be had, ours being a stand-in for AC8's M_Live_Base (its shaders would ship))
            nv = len(Pw)
            Pw, Nw, UV = np.concatenate([Pw, Pw]), np.concatenate([Nw, -Nw]), np.concatenate([np.asarray(UV), np.asarray(UV)])
            T = np.concatenate([T, T[:, [0, 2, 1]] + nv]).astype(np.uint32)
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
    # joints: node 1 the root; parents[k] = bone k's parent (default the root); a joint's transform = its bind pose
    # in its parent's frame ((2026-11-22) the rings' pieces are their ring's children, so they turn with it)
    parents = parents or [-1] + [0] * (len(bones) - 1)
    nodes = [{'name': name, 'mesh': 0, 'skin': 0}]
    W = [mat4(R, p) for _, R, p in bones]
    for k, (bn, R, p) in enumerate(bones):
        nd = {'name': bn}
        if k > 0:
            L = np.linalg.inv(W[parents[k]]) @ W[k]
            nd['translation'] = [float(v) for v in L[:3, 3]]
            nd['rotation'] = [float(v) for v in rquat(L[:3, :3])]
        nodes.append(nd)
    for k in range(1, len(bones)):
        nodes[parents[k] + 1].setdefault('children', []).append(k + 1)
    ibm = np.stack([np.linalg.inv(mat4(R, p)).T.reshape(-1) for _, R, p in bones]).astype(np.float32)   # column-major
    g = {'asset': {'version': '2.0', 'generator': 'AC8 Survival Mode tools/solg/prepare.py'},
         'scene': 0, 'scenes': [{'nodes': [0, 1]}], 'nodes': nodes,
         'skins': [{'name': name + '_Skin', 'joints': list(range(1, len(bones) + 1)), 'skeleton': 1,
                    'inverseBindMatrices': add(ibm, None, 'MAT4', 5126)}],
         'meshes': [{'name': name, 'primitives': prims}], 'materials': mats,
         **({'animations': [anim_gltf(a, bones, parents, W, add) for a in anims]} if anims else {}),
         'buffers': [{'uri': name + '.bin', 'byteLength': len(blob)}], 'bufferViews': views, 'accessors': accessors}
    for an in g.get('animations', []):
        lo, hi = an.pop('_minmax')
        for sm in an['samplers']:
            accessors[sm['input']]['min'] = [lo]
            accessors[sm['input']]['max'] = [hi]
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
    # ((2026-11-22) its KEW shells (s_sg06, AC:I's KEW SHELL targets): on no plan node of the body; where they sit comes
    # from the arrival cutscene (DATA01 429, cut 0, frame 0: Tdemo__s_sg06_t1__NN, tools/solg/kfm1.py), each shell's
    # place and turn relative to the body's (Tdemo__s_solg_t1__01), in the body's own frame; on the nearer ring)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # (-I: the script's folder isn't on the path)
    import kfm1
    dc = DPL(os.path.join(os.environ['ACI_USRDIR'], PAC + '.PAC')).read(CUT)
    cch = list(flat(fhm_tree(dc)))
    first = {}
    for c in cch:
        if c[1] != b'MOP2' or c[3] < 32:
            continue
        for nm_, kb in skel.clips(dc[c[2]:c[2] + c[3]]).items():
            if nm_.startswith('Tdemo__s_') and nm_ not in first:
                first[nm_] = kfm1.decode(kb)[1]
    def pose(tr):
        pp = next(t for t in tr if t['type'] == 0x0503)['vals'][0]
        qq = next(t for t in tr if t['type'] == 0x0704)['vals'][0]
        return np.array(pp, np.float64), qmat(qq)
    bp, bR = pose(first['Tdemo__s_solg_t1__01'])
    # ((2026-11-22) ring 1 has turned in that frame (its arms 11.4 degrees on from the plan nodes'): turned back, so each
    # shell lies along its arm as in AC:I (a check against the cutscene: on the arm's line, 160-480 m out, 4 x 9))
    cut_arms = sorted(math.degrees(math.atan2(*(bR.T @ (pose(first[k])[0] - bp))[1::-1]))
                      for k in first if k.startswith('Tdemo__s_sg01_t1__'))
    plan_arms = sorted(math.degrees(math.atan2(m['aci_pos_m'][1], m['aci_pos_m'][0])) for m in layout['mounts'] if m['model'] == 's_sg01')
    d_ring = np.mean([((c_ - p_ + 180) % 360) - 180 for c_, p_ in zip(cut_arms, plan_arms)]) if len(cut_arms) == 4 else 0.0
    cz, sz = math.cos(math.radians(-d_ring)), math.sin(math.radians(-d_ring))
    unring = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]], np.float64)
    print('KEW shells: ring 1 turned %.1f deg in the cutscene frame: turned back' % d_ring)
    kew = sorted(k for k in first if k.startswith('Tdemo__s_sg06_t1__'))
    layout['kew'] = []
    for i, k in enumerate(kew):
        pp, R = pose(first[k])
        rel = unring @ (bR.T @ (pp - bp))        # in the body's AC:I frame, ring 1 at its plan pose
        Rrel = unring @ bR.T @ R
        key = 'KEW_%02d' % (i + 1)
        ring = 'RING_1' if abs(rel[2] - 714.3) <= abs(rel[2] - 791.5) else 'RING_2'
        Rt, pt = TURN @ Rrel @ TURN.T, turned(rel)
        bones.append((key, Rt, pt)); pieces.append((len(bones) - 1, cache[('s_sg06', 'l1')]))
        bones.append((key + '_W', Rt, pt)); pieces.append((len(bones) - 1, cache[('s_sg06', 'd1')]))
        layout['kew'].append({'bone': key, 'cut_clip': k, 'aci_pos_m': np.round(rel, 2).tolist(), 'ring': ring})
    print('KEW shells: %d from %s (radius %.0f-%.0f m from the barrel, AC:I z %.0f-%.0f)' % (
        len(kew), 'DATA01 %d' % CUT, min(np.hypot(e['aci_pos_m'][0], e['aci_pos_m'][1]) for e in layout['kew']),
        max(np.hypot(e['aci_pos_m'][0], e['aci_pos_m'][1]) for e in layout['kew']),
        min(e['aci_pos_m'][2] for e in layout['kew']), max(e['aci_pos_m'][2] for e in layout['kew'])))
    # ((2026-11-22) its laser turrets, AC:I's (tools/solg/lasers.py, docs/re/SOLG.md section 11): f_111t x28, 16 on the
    # arms (4 each, on ring 1) and 12 round the barrel (the body); LSR_01..28, no wreck mesh in AC:I (a broken one hidden)
    import lasers
    lparts = meshes_of(d, ch, 'f_111t', 'l1')
    cache[('f_111t', 'l1')] = lparts
    texids.update(p_[4] for p_ in lparts)
    tl = lasers.turrets(layout, lasers.graph(DPL, fhm_tree, flat))
    tl.sort(key=lambda t: (t['set'], t['arm'] or 0, -t['pos'][2]))
    layout['lasers'] = []
    for i, t in enumerate(tl):
        key = 'LSR_%02d' % (i + 1)
        bones.append((key, TURN @ t['R'] @ TURN.T, turned(t['pos']))); pieces.append((len(bones) - 1, lparts))
        layout['lasers'].append({'bone': key, 'set': t['set'], 'arm': 'SG01_%02d' % t['arm'] if t['arm'] else None,
                                 'aci_pos_m': np.round(t['pos'], 2).tolist()})
    print('lasers: %d f_111t turrets (%d on the arms, %d on the barrel)' % (len(tl), sum(1 for t in tl if t['set'] == 'A'),
          sum(1 for t in tl if t['set'] == 'B')))
    # ((2026-11-22) its animation, AC:I's own (tools/solg/kfm1.py, docs/re/SOLG.md section 10): the body's `auta`
    # turns ring auta1 (RING_1) and auta2 (RING_2) the opposite ways about the barrel (AC:I z = glTF x), 0.3 degrees a
    # frame each (one turn in 1,200 frames, 40 s at 30 fps). The pieces on a ring are that ring's bone's children; the
    # arms (the autoloaders, s_sg01) only ride ring 1: the small `auta` clips in the package are o_de01..05's, not the
    # SOLG's (the user, 2026-11-22: "The autoloaders are tumbling", when they had been given that spin))
    ringof = {'auta1': 'RING_1', 'auta2': 'RING_2'}
    owner = {}
    for mt in layout['mounts']:
        key = 'CORE_%02d' % mt['index'] if mt['model'] == 'f_sgc1' else '%s_%02d' % (mt['model'][2:].upper(), mt['index'])
        owner[key] = owner[key + '_W'] = ringof.get(mt['parent'])
    for e in layout['kew']:
        owner[e['bone']] = owner[e['bone'] + '_W'] = e['ring']
    for e in layout['lasers']:
        owner[e['bone']] = 'RING_1' if e['set'] == 'A' else None
    bn = [b[0] for b in bones]
    parents = [-1] + [bn.index(owner[b]) if owner.get(b) else 0 for b in bn[1:]]
    spin = {'name': 'A_SV_SOLG_Spin', 'length_s': 40.0, 'keys': 160,
            'bones': {'RING_1': ((1, 0, 0), -1), 'RING_2': ((1, 0, 0), 1)}}
    nprim, nvert = write_skinned('SK_SV_SOLG', pieces, bones, parents, [spin])
    # the solar array wings on their own (each its live and its wreck bone at its origin): when one's shot off, it's
    # hidden on the body and one of these falls (Scripts/sv_solg.lua)
    for mdl, nm in (('s_sg04', 'SK_SV_SOLG_SAW4'), ('s_sg05', 'SK_SV_SOLG_SAW5')):
        write_skinned(nm, [(0, cache[(mdl, 'l1')]), (1, cache[(mdl, 'd1')])], [('PANEL', I3, np.zeros(3)), ('PANEL_W', I3, np.zeros(3))])
    layout['panels'] = ['SK_SV_SOLG_SAW4', 'SK_SV_SOLG_SAW5']
    # ((2026-11-22) the user: "Each of its autoloaders falls off after each has had all of its targets destroyed") an arm
    # on its own: arm 4 (SG01_04, at 0 degrees) with the wrecks of the 8 MAG panels and 9 KEW shells along it (each
    # within 15 degrees of it about the barrel), in the arm's own frame. The four arms are alike, 90 degrees apart: the
    # same mesh falls from whichever arm breaks (Scripts/sv_solg.lua SOLG.breakArm); ARM_W its wreck (hidden at first)
    bi = {b_[0]: k for k, b_ in enumerate(bones)}
    Ra, pa = bones[bi['SG01_04']][1], bones[bi['SG01_04']][2]
    def on_arm4(v):
        return math.hypot(v[0], v[1]) > 50 and abs(math.degrees(math.atan2(v[1], v[0]))) < 15
    mine = ['SG07_%02d' % m['index'] for m in layout['mounts'] if m['model'] == 's_sg07' and on_arm4(m['aci_pos_m'])]
    mine += [e['bone'] for e in layout['kew'] if on_arm4(e['aci_pos_m'])]
    assert len(mine) == 17, ('arm 4 carries', mine)
    guns = [e['bone'] for e in layout['lasers'] if e['arm'] == 'SG01_04']
    assert len(guns) == 4, ('arm 4 lasers', guns)
    abones = [('ARM', I3, np.zeros(3)), ('ARM_W', I3, np.zeros(3))]
    apieces = [(0, cache[('s_sg01', 'l1')]), (1, cache[('s_sg01', 'd1')])]
    for nm_ in mine:
        R_, p_ = bones[bi[nm_]][1], bones[bi[nm_]][2]
        model_ = 's_sg06' if nm_.startswith('KEW') else 's_sg07'
        abones.append(('P_' + nm_, Ra.T @ R_, Ra.T @ (p_ - pa)))
        apieces.append((len(abones) - 1, cache[(model_, 'd1')]))
    for nm_ in guns:                                       # (its lasers: as they are, hidden on the falling arm if broken)
        R_, p_ = bones[bi[nm_]][1], bones[bi[nm_]][2]
        abones.append(('P_' + nm_, Ra.T @ R_, Ra.T @ (p_ - pa)))
        apieces.append((len(abones) - 1, cache[('f_111t', 'l1')]))
    write_skinned('SK_SV_SOLG_ARM', apieces, abones)
    layout['panels'].append('SK_SV_SOLG_ARM')
    layout['arm'] = {'from': 'SG01_04', 'pieces': mine, 'lasers': guns}
    print('SK_SV_SOLG_ARM: the arm and the wrecks of its %d pieces (%s)' % (len(mine), ', '.join(mine)))
    layout['parents'] = {b: (bn[parents[k]] if parents[k] >= 0 else None) for k, b in enumerate(bn)}
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
    # ((2026-11-22) the user: "SOLG -Gould- is the one we want, the black texture too") its skin: each SOLG version's
    # package carries a re-skin of the same meshes (its own texture ids, the meshes naming the first set's); Gould's,
    # DATA92 528, is near black with red lights. SKINS: which of its textures takes each texture's place (matched by
    # size and shape, docs/re/SOLG.md section 12). SOLG_SKIN (env): gould (default) or base (the first set's grey)
    skin = os.environ.get('SOLG_SKIN', 'gould')
    if skin in SKINS:
        spac, sentry, swap = SKINS[skin]
        ds = DPL(os.path.join(os.environ['ACI_USRDIR'], spac + '.PAC')).read(sentry)
        sg = export_textures(ds, list(flat(fhm_tree(ds))), tmp)
        done = []
        for t, r in sorted(swap.items()):
            if ('t%08x' % t) in layout['textures'] and sg.get(r):
                os.replace(sg[r][0], os.path.join(OUT, 'T_SV_SOLG_%08x.png' % t))
                done.append('%08x<-%08x' % (t, r))
        for f in os.listdir(tmp):
            os.remove(os.path.join(tmp, f))
        os.rmdir(tmp)
        layout['skin'] = {'name': skin, 'source': '%s:%d' % (spac, sentry), 'swapped': done}
        print('skin %s (%s:%d): %d textures swapped (%s)' % (skin, spac, sentry, len(done), ', '.join(done)))
    # flat maps for AC8's M_Live_Base (tools/solg/ue_import.py): a neutral normal and a neutral Livemap
    from PIL import Image
    Image.new('RGBA', (4, 4), (128, 128, 255, 255)).save(os.path.join(OUT, 'T_SV_SOLG_FlatN.png'))
    Image.new('RGBA', (4, 4), (0, 191, 255, 255)).save(os.path.join(OUT, 'T_SV_SOLG_FlatL.png'))
    json.dump(layout, open(os.path.join(OUT, 'layout.json'), 'w'), indent=1)
    print('textures:', ', '.join(sorted(layout['textures'])))
    print('wrote', OUT)


if __name__ == '__main__':
    main()
