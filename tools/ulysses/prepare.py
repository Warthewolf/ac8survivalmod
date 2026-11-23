"""prepare.py : AC:I's meteors ("Stardust", the ULYSSES special) -> build/ulysses, for tools/ulysses/ue_import.py.

  py -3.12 -I tools/ulysses/prepare.py         (needs numpy + Pillow, the AC:I kit and an AC:I install: .env's ACI, as
                                                tools/solg/prepare.py, whose readers this reuses)

AC:I's meteor models, their textures and the Stardust sounds are allowed for the ULYSSES special (the user, 2026-11-23;
docs/rules/sources_and_toolchain.md). Nothing here is committed: the outputs go to build/ulysses.

The meteors in AC:I (read 2026-11-23):
  o_meta   DATA00 2099 (with o_metb's cutscene clips): the big one, ~68 x 54 x 97 m, 644 triangles
  o_metc   DATA01 24 (the meteor mission's package; also DATA01 81): ~6.5 x 6.3 x 5.8 m, 644 triangles
  o_metd   DATA01 24: ~3.2 m, 644 triangles
  o_metb   NO mesh in any DATA*.PAC: only a node tree (o_metb_l1 / _d1) and cutscene clips (Tdemo__o_metb_t1__NN)
  o_metx   a one-triangle placeholder of zero size (an effect anchor): nothing to draw
  o_metc_d1..d4 are the whole rock again (o_metc's destroyed-state LODs, the same 644 triangles), and the _shl / _shd
  meshes are its shadow models (texture 20000011): no break-up pieces exist in AC:I's data.
All three share one rock skin: 2000457c (colour, 256 x 256) and 2000460f (a grey relief map, 256 x 256).

Writes, each mesh centred on its bounds' centre (its pivot), AC:I metres (glTF metres: UE's importer makes them cm):
  SM_SV_Ulysses_<K>.gltf / .bin   static mesh (one primitive, material t2000457c)
  SK_SV_Ulysses_<K>.gltf / .bin   the same rock as a one-bone skeletal mesh (bone ROCK): the route AC8 is proven to draw
                                  for meshes of ours (SOLG T0: a static mesh of ours crashed AC8; docs/re/SOLG.md 8)
  T_SV_Ulysses_Rock_D.png         the colour (2000457c)
  T_SV_Ulysses_Rock_N.png         a normal map derived from the relief map (2000460f, read as height)
  T_SV_Ulysses_Rock_L.png         a flat Livemap (metallic 0, roughness 0.92, occlusion 1: a rough rock)
  SM_ / SK_SV_Ulysses_Tail        the streak, ours (tail_mesh: no outside asset), UV1 = UV0
  T_SV_Ulysses_Tail_D.png         its colour along U (tail_texture), T_SV_Ulysses_FlatN.png a flat normal
  layout.json                     the meshes (vertices, triangles, bounds in metres)
"""
import json, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'solg'))
import prepare as solg                       # noqa: E402  (tools/solg/prepare.py: .env's ACI, the kit, its readers)
from fhm import DPL, fhm_tree, flat          # noqa: E402  (the kit, put on the path by tools/solg/prepare.py)

ROOT = solg.ROOT
OUT = os.path.join(ROOT, 'build', 'ulysses')
solg.OUT = OUT                               # (its write_gltf / write_skinned write to its OUT)
# key: (AC:I model, package, entry)
METEORS = {'A': ('o_meta', 'DATA00', 2099), 'C': ('o_metc', 'DATA01', 24), 'D': ('o_metd', 'DATA01', 24)}
SKIPPED = {'B': 'o_metb has no mesh in any DATA*.PAC (a node tree and cutscene clips only)',
           'X': 'o_metx is a one-triangle placeholder of zero size (an effect anchor)',
           'C_Debris': "o_metc_d1..d4 are the whole rock again (destroyed-state LODs), _shl / _shd its shadow meshes"}
COLOUR, RELIEF = 0x2000457c, 0x2000460f
# ((2026-11-23) the user rejected AC8's Tonitrus rod trail for the fragments: "come up with your own") the streak, ours,
# made here (no outside asset): a teardrop along -X, its head (radius HEAD_R, a round cap ahead of it) at the origin,
# where the rock's centre sits; it tapers to a point TAIL_M behind. U runs along it (0 head, 1 tail), V round it.
TAIL_M, HEAD_R, SIDES, RINGS, CAP = 24.0, 1.0, 16, 12, 3
# its colour along U (sRGB values; alpha 1 at the head to 0 at the tail, for a translucent parent)
TAIL_KEYS = [(0.0, (1.0, 0.97, 0.9)), (0.25, (1.0, 0.6, 0.15)), (0.6, (0.6, 0.08, 0.02)), (1.0, (0.02, 0.005, 0.0))]


def tail_mesh():
    """The streak -> [(P, N, UV, T, tex)] in glTF's frame, metres: its body along glTF -X, which UE's importer keeps as
    UE -X (SOLG's axis probe: glTF (x, y, z) -> UE (x, z, y)), so +X faces along the fall."""
    rings = []                                     # (x, r, u)
    for k in range(CAP):                           # the head's round cap, from the nose (x = HEAD_R) back to x = 0
        a = (k / CAP) * (np.pi / 2)
        rings.append((HEAD_R * np.cos(a), HEAD_R * np.sin(a), 0.0))
    for k in range(RINGS + 1):                     # the body: radius (1 - t)^1.4, t 0 .. 1 over TAIL_M
        t = k / RINGS
        rings.append((-TAIL_M * t, max(HEAD_R * (1 - t) ** 1.4, 0.0), t))
    P, UV = [], []
    for x, r, u in rings:
        for s in range(SIDES + 1):                 # (a seam column: V 0 and 1 apart)
            a = 2 * np.pi * s / SIDES
            P.append((x, r * np.cos(a), r * np.sin(a)))
            UV.append((u, s / SIDES))
    P, UV = np.array(P, np.float64), np.array(UV, np.float64)
    T, W = [], SIDES + 1
    for i in range(len(rings) - 1):
        for s in range(SIDES):
            a, b, c, d = i * W + s, i * W + s + 1, (i + 1) * W + s, (i + 1) * W + s + 1
            T += [(a, c, b), (b, c, d)]
    T = np.array(T, np.uint32)
    area = np.linalg.norm(np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]]), axis=1)
    T = T[area > 1e-9]                             # (the tip's and the nose's zero-area triangles)
    # smooth normals: the faces' (outward: away from the axis) summed at each vertex, the seam's two columns joined
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    cen = P[T].mean(1)
    out = cen.copy(); out[:, 0] = 0                # (away from the axis)
    if np.sum(np.einsum('ij,ij->i', fn, out)) < 0:
        T = T[:, [0, 2, 1]]; fn = -fn
    N = np.zeros_like(P)
    for j in range(3):
        np.add.at(N, T[:, j], fn)
    for i in range(len(rings)):
        a, b = i * W, i * W + SIDES
        N[a] = N[b] = N[a] + N[b]
    N[0:W] = (1, 0, 0)                             # (the nose point)
    ln = np.linalg.norm(N, axis=1, keepdims=True); ln[ln == 0] = 1
    return [(P, N / ln, UV, T, 0)]


def tail_texture(path, w=256, h=16):
    from PIL import Image
    us = np.linspace(0, 1, w)
    keys = np.array([k for k, _ in TAIL_KEYS]); cols = np.array([c for _, c in TAIL_KEYS])
    rgb = np.stack([np.interp(us, keys, cols[:, j]) for j in range(3)], 1)
    alpha = np.clip(1 - us, 0, 1) ** 1.5
    row = np.concatenate([rgb, alpha[:, None]], 1)
    img = np.repeat(row[None], h, 0)
    Image.fromarray(np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8), 'RGBA').save(path)


def add_uv1(name):
    """TEXCOORD_1 = TEXCOORD_0 on every primitive of <name>.gltf: AC8's gear master samples its EmissiveLightMap on UV
    channel 1 (docs/re/FALKEN_MATERIALS.md 2.4)."""
    p = os.path.join(OUT, name + '.gltf')
    g = json.load(open(p))
    for m in g['meshes']:
        for pr in m['primitives']:
            pr['attributes']['TEXCOORD_1'] = pr['attributes']['TEXCOORD_0']
    json.dump(g, open(p, 'w'))


def normal_from_height(h, strength=6.0):
    """A tiling normal map (UE's +Y-down green, DirectX style) from a height map in 0..1."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    n = np.dstack([-dx * strength, dy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return np.clip((n * 0.5 + 0.5) * 255 + 0.5, 0, 255).astype(np.uint8)


def main():
    from PIL import Image
    os.makedirs(OUT, exist_ok=True)
    layout = {'meshes': {}, 'skipped': SKIPPED}
    cache = {}
    texs = None
    for key, (model, pac, entry) in sorted(METEORS.items()):
        if (pac, entry) not in cache:
            d = DPL(os.path.join(os.environ['ACI_USRDIR'], pac + '.PAC')).read(entry)
            cache[(pac, entry)] = (d, list(flat(fhm_tree(d))))
        d, ch = cache[(pac, entry)]
        solg.PAC, solg.ENTRY = pac, entry    # (its error messages)
        parts = solg.meshes_of(d, ch, model, 'l1')
        P = np.concatenate([p[0] for p in parts])
        c = (P.min(0) + P.max(0)) / 2        # pivot: the bounds' centre
        parts = [(p[0] - c, p[1], p[2], p[3], p[4]) for p in parts]
        bad = {p[4] for p in parts} - {COLOUR}
        if bad:
            raise SystemExit('%s: a texture other than the rock skin: %s' % (model, sorted('%08x' % t for t in bad)))
        sm, sk = 'SM_SV_Ulysses_' + key, 'SK_SV_Ulysses_' + key
        solg.write_gltf(sm, parts)
        solg.write_skinned(sk, [(0, parts)], [('ROCK', np.eye(3), np.zeros(3))])
        P = np.concatenate([p[0] for p in parts])
        tris = int(sum(len(np.asarray(p[3]).reshape(-1, 3)) for p in parts))
        layout['meshes'][sm] = {'model': model, 'source': '%s:%d' % (pac, entry), 'skeletal': sk, 'mi': 'Rock',
                                'vertices': int(len(P)), 'triangles': tris,
                                'min_m': P.min(0).round(2).tolist(), 'max_m': P.max(0).round(2).tolist(),
                                'size_m': (P.max(0) - P.min(0)).round(2).tolist(), 'aci_centre_m': c.round(3).tolist()}
        print('%-18s %-7s %s:%-5d %5d vertices %5d triangles  size %s m' % (
            sm, model, pac, entry, len(P), tris, layout['meshes'][sm]['size_m']))
        if texs is None:
            texs = solg.export_textures(d, ch, os.path.join(OUT, 'tex_all'))
    tmp = os.path.join(OUT, 'tex_all')
    if not (texs.get(COLOUR) and texs.get(RELIEF)):
        raise SystemExit('the rock textures (%08x, %08x) are missing' % (COLOUR, RELIEF))
    Image.open(texs[COLOUR][0]).convert('RGBA').save(os.path.join(OUT, 'T_SV_Ulysses_Rock_D.png'))
    h = np.asarray(Image.open(texs[RELIEF][0]).convert('L'), np.float64) / 255.0
    Image.fromarray(normal_from_height(h)).save(os.path.join(OUT, 'T_SV_Ulysses_Rock_N.png'))
    Image.new('RGBA', (4, 4), (0, 235, 255, 255)).save(os.path.join(OUT, 'T_SV_Ulysses_Rock_L.png'))
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)
    layout['textures'] = {'T_SV_Ulysses_Rock_D': '%08x' % COLOUR, 'T_SV_Ulysses_Rock_N': 'from %08x' % RELIEF,
                          'T_SV_Ulysses_Rock_L': 'flat (0, 235, 255)'}
    json.dump(layout, open(os.path.join(OUT, 'layout.json'), 'w'), indent=1)
    # the streak (ours): SM_ and SK_ (one bone ROCK), UV1 = UV0 for the gear master's emissive map; its texture
    parts = tail_mesh()
    solg.write_gltf('SM_SV_Ulysses_Tail', parts)
    solg.write_skinned('SK_SV_Ulysses_Tail', [(0, parts)], [('ROCK', np.eye(3), np.zeros(3))])
    for nm in ('SM_SV_Ulysses_Tail', 'SK_SV_Ulysses_Tail'):
        add_uv1(nm)
    tail_texture(os.path.join(OUT, 'T_SV_Ulysses_Tail_D.png'))
    Image.new('RGBA', (4, 4), (128, 128, 255, 255)).save(os.path.join(OUT, 'T_SV_Ulysses_FlatN.png'))
    P = parts[0][0]
    layout['meshes']['SM_SV_Ulysses_Tail'] = {'model': 'ours (tools/ulysses/prepare.py tail_mesh)', 'skeletal': 'SK_SV_Ulysses_Tail',
                                              'mi': 'Tail', 'vertices': int(len(P)), 'triangles': int(len(parts[0][3])),
                                              'min_m': P.min(0).round(2).tolist(), 'max_m': P.max(0).round(2).tolist(),
                                              'size_m': (P.max(0) - P.min(0)).round(2).tolist()}
    layout['textures']['T_SV_Ulysses_Tail_D'] = 'ours: white-hot -> orange -> red -> black along U, alpha 1 -> 0'
    json.dump(layout, open(os.path.join(OUT, 'layout.json'), 'w'), indent=1)
    print('%-18s %-7s %5d vertices %5d triangles  bounds %s .. %s m' % ('SM_SV_Ulysses_Tail', 'ours', len(P), len(parts[0][3]),
          layout['meshes']['SM_SV_Ulysses_Tail']['min_m'], layout['meshes']['SM_SV_Ulysses_Tail']['max_m']))
    for k, why in SKIPPED.items():
        print('skipped %s: %s' % (k, why))
    print('wrote', OUT)


if __name__ == '__main__':
    main()
