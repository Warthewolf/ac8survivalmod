"""scan_spaceport_buildings.py : building footprints round the Comona spaceport, read from the stock level packages
(build-time data for the Spaceport Retake's island enemies: tools/spaceport_spots.py; user, 2026-10-31: "do a building
check so that no enemies spawn in buildings").

    python -X utf8 -I tools/scan_spaceport_buildings.py [--radius-km 5] [--no-pull]

Reads every streamed sublevel PL_Mission022 names (Survival's PL_SurvivalMode is a copy of it) plus Mission022_MiniGame,
takes every StaticMeshComponent (a StaticMeshActor's root) and every instance of every InstancedStaticMeshComponent
(component transform from its attach chain, instance FMatrix from PerInstanceSMData), looks up each mesh's
ExtendedBounds in its own package (pulled into build/stock with tools/get_stock.sh when missing) and writes one oriented
box per building-like placement within the radius of the shuttle pad: tools/data/spaceport_buildings.json.
Entries: name, actor, mesh, kind, x/y/z (world centre of the box, cm), yaw (deg), hx/hy/hz (half extents in the box's
own axes, world-scaled cm), zmin/zmax. Read only on the game data; writes tools/data/spaceport_buildings.json, its mesh
bounds cache in build/research/buildings (and build/stock through get_stock.sh).
"""
import json, math, os, pickle, re, struct, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools')); sys.path.insert(0, os.path.join(ROOT, 'tools', 'scripts'))
from zenpkg import ZenPkg, export_hash
import uprop

STOCK = os.path.join(ROOT, 'build', 'stock')
SO = pickle.load(open(os.path.join(ROOT, 'tools', 'scriptobjs.pkl'), 'rb'))
PL = '/Game/Maps/Ingame/Mission022/PL_Mission022'
EXTRA_LEVELS = ['/Game/Maps/Ingame/Mission022/Mission022_MiniGame']
PAD = (-1325196.0, 59778.0)           # the shuttle pad (Mission 22's world data)
OUT = os.path.join(HERE, 'data', 'spaceport_buildings.json')
CACHE = os.path.join(ROOT, 'build', 'research', 'buildings', 'mesh_bounds.json')

# Known clear ground spots (Mission 22's world data) to test the method against.
KNOWN = {
    'AA gun 1': (-1444081, 147755), 'AA gun 2': (-1338363, 131024), 'AA gun 3': (-1384957, 168478),
    'AA gun 4': (-1404999, 94504), 'AA gun 5': (-1357884, -40453), 'AA gun 6': (-1285470, -19260),
    'SAM 1': (-1293594, -27620), 'SAM 2': (-1458318, 151017), 'SAM 3': (-1386263, 159584), 'SAM 4': (-1357373, -25741),
    'control centre': (-1497330, 150122),
    'troops 1': (-1490317, 157461), 'troops 2': (-1484219, 75102), 'troops 3': (-1419829, -21557),
}

# What isn't a building: by mesh name / path.
SKIP = [
    (re.compile(r'/Terrain/|^SM_TER_|_Sea_|Sea\d*$', re.I), 'terrain'),
    (re.compile(r'StreetLight|TrafficLight|LightsEmissive|AirportLights|Billboard|/Light/|Lamp', re.I), 'light'),
    (re.compile(r'/Plant/|/Foliage/|_Tree|Bush|Grass|Leaf', re.I), 'foliage'),
    (re.compile(r'/Traffic/MapRoad/|^SM_ROD_|Road|Spline', re.I), 'road'),
    (re.compile(r'Decal', re.I), 'decal'),
    (re.compile(r'Sky|Cloud', re.I), 'sky'),
]
PROP = re.compile(r'Trashbag|WoodBox|Scrap|Propset|Concrete|Pipe0|Tube|DumpsSter|Wood0|Contena|MaterialsDepot|Tent|'
                  r'Light0|BasePipeStep', re.I)
FLAT_CM = 60.0      # a box thinner than this (full height) is a ground plate, not a building
GROUND_CM = 500.0   # the island's ground (z 5 m)
ELEVATED_CM = 1500.0  # a box whose bottom is this far above the ground doesn't block ground units (bridge signs)
COMPOUND_CM = 20000.0  # a box over 200 m on a side is a compound mesh (a whole complex): flagged, its box is coarse


# ------------------------------------------------------------------ package helpers
def pkg_file(path):
    p = os.path.join(STOCK, path[len('/Game/'):])
    for ext in ('.umap', '.uasset'):
        if os.path.exists(p + ext): return p + ext
    return None


def pull(paths, no_pull):
    """get_stock.sh for packages not in build/stock yet (it greps build/scan/all_chunks.txt for each)."""
    if no_pull: return
    chunks = open(os.path.join(ROOT, 'build', 'scan', 'all_chunks.txt'), encoding='utf-8', errors='replace').read()
    want = []
    for p in paths:
        if pkg_file(p): continue
        rel = p[len('/Game/'):]
        for ext in ('.uasset', '.umap'):
            if f'Live/Content/{rel}{ext}' in chunks: want.append(rel + ext); break
    for k in range(0, len(want), 40):
        subprocess.run(['sh', 'tools/get_stock.sh'] + want[k:k + 40], cwd=ROOT, check=False,
                       env=dict(os.environ, MSYS_NO_PATHCONV='1'), stdout=subprocess.DEVNULL)


class Pkg:
    def __init__(self, path):
        self.z = ZenPkg(path)
        # imported package names are FNames: a numeric tail is stored split (hard rule 17)
        self.pkgs = [n + (f'_{k - 1}' if k else '') for n, k in zip(self.z.imp_pkgs, self.z.imp_pkg_nums)]
        self._short = {}
        for p in self.pkgs:
            s = p.rsplit('/', 1)[1]
            for c in (s, s + '_C'):
                self._short[export_hash(c)] = c

    def cls(self, i):
        return self.ref(struct.unpack_from('<Q', self.z.exports[i], 32)[0])

    def outer(self, i):
        x = struct.unpack_from('<Q', self.z.exports[i], 24)[0]
        return None if x >> 62 == 3 else x & ((1 << 62) - 1)

    def ref(self, x):
        """FPackageObjectIndex -> script class name, '/Game/pkg.Object' for a package import, or ('exp', i)."""
        t = x >> 62
        if t == 3: return None
        if t == 0: return ('exp', x & ((1 << 62) - 1))
        if t == 1: return SO.get(x, hex(x))
        k, hi = (x >> 32) & 0x3fffffff, x & 0xffffffff
        pkg = self.pkgs[k]
        return pkg + '.' + self._short.get(self.z.imp_hashes[hi], '?')

    def obj(self, v):
        """An ('obj', FPackageIndex) property value -> ref() of it."""
        n = v[1]
        if n < 0: return self.ref(self.z.imports[-n - 1])
        if n > 0: return ('exp', n - 1)
        return None

    def props(self, i, cls):
        p = bytes(self.z.payloads[i])
        v, o = uprop.read_struct(uprop.Ctx(p, self.z.names), 4, cls)
        return {q[1]: q[3] for q in v[2]}, p, o


# ------------------------------------------------------------------ maths (UE row-vector matrices: p' = p * M)
def rot_matrix(pitch, yaw, roll):
    p, y, r = (math.radians(a) for a in (pitch, yaw, roll))
    sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    return [[cp * cy, cp * sy, sp],
            [sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp],
            [-(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp]]


def trs(loc, rot, scale):
    R = rot_matrix(*rot)
    M = [[R[i][j] * scale[i] for j in range(3)] + [0.0] for i in range(3)]
    return M + [list(loc) + [1.0]]


def mul(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


IDENT = trs((0, 0, 0), (0, 0, 0), (1, 1, 1))


def vec(v, default):
    return struct.unpack('<3d', v[2]) if v else default


# ------------------------------------------------------------------ level reading
COMP_SCHEMA = {'StaticMeshComponent', 'InstancedStaticMeshComponent', 'HierarchicalInstancedStaticMeshComponent',
               'FoliageInstancedStaticMeshComponent', 'SceneComponent', 'BoxComponent', 'ChildActorComponent'}


def level_placements(path):
    """-> list of (name, actor, mesh path, world 4x4) for every static mesh placement in the level."""
    P = Pkg(pkg_file(path))
    z = P.z
    cache = {}

    def comp(i):
        if i in cache: return cache[i]
        cache[i] = None
        cls = P.cls(i)
        if not isinstance(cls, str) or cls not in COMP_SCHEMA: return None
        try:
            f, p, o = P.props(i, cls)
        except Exception:
            return None
        loc = vec(f.get('RelativeLocation'), (0.0, 0.0, 0.0))
        rot = vec(f.get('RelativeRotation'), (0.0, 0.0, 0.0))
        scl = vec(f.get('RelativeScale3D'), (1.0, 1.0, 1.0))
        M = trs(loc, rot, scl)
        par = P.obj(f['AttachParent']) if f.get('AttachParent') else None
        if isinstance(par, tuple):
            pm = comp(par[1])
            if pm: M = mul(M, pm[0])
        cache[i] = (M, f, p, o, cls)
        return cache[i]

    out = []
    for i in range(len(z.exports)):
        cls = P.cls(i)
        if not isinstance(cls, str) or 'StaticMeshComponent' not in cls: continue
        c = comp(i)
        if not c or not c[1].get('StaticMesh'): continue
        M, f, p, o, cls = c
        mesh = P.obj(f['StaticMesh'])
        if not isinstance(mesh, str): continue
        oi = P.outer(i)
        actor = z.export_name(oi) if oi is not None else '?'
        name = z.export_name(i)
        if 'Instanced' not in cls:
            out.append((name, actor, mesh, M)); continue
        # PerInstanceSMData: bulk array of FInstancedStaticMeshInstanceData (FMatrix44d, 128 bytes), 12 bytes after it.
        hit = None
        for off in range(o, min(len(p) - 8, o + 512), 4):
            es, n = struct.unpack_from('<II', p, off)
            if es == 128 and len(p) - (off + 8 + 128 * n) == 12:
                hit = (off + 8, n); break
        if hit is None:
            print(f'  {os.path.basename(path)}: {name}: instance data not found', file=sys.stderr); continue
        for k in range(hit[1]):
            m = struct.unpack_from('<16d', p, hit[0] + 128 * k)
            IM = [list(m[0:4]), list(m[4:8]), list(m[8:12]), list(m[12:16])]
            out.append((f'{name}#{k}', actor, mesh, mul(IM, M)))
    return out


def sublevels():
    z = ZenPkg(pkg_file(PL))
    lv = [n for n in z.names if n.startswith('/Game/Maps/') and n != PL]
    return lv + [n for n in EXTRA_LEVELS if n not in lv]


# ------------------------------------------------------------------ mesh bounds
def mesh_bounds(mesh_paths, no_pull):
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    todo = sorted({m.split('.')[0] for m in mesh_paths} - set(cache))
    pull(todo, no_pull)
    for pkg in todo:
        f = pkg_file(pkg)
        if not f: cache[pkg] = None; continue
        P = Pkg(f)
        got = None
        for i in range(len(P.z.exports)):
            if P.cls(i) != 'StaticMesh': continue
            try:
                props, _, _ = P.props(i, 'StaticMesh')
            except Exception as ex:
                got = {'err': str(ex)}; break
            eb = props.get('ExtendedBounds')
            if eb:
                b = {q[1]: q[3] for q in eb[2]}
                got = {'origin': vec(b.get('Origin'), (0, 0, 0)), 'extent': vec(b.get('BoxExtent'), (0, 0, 0))}
            else:
                got = {'err': 'no ExtendedBounds'}
            break
        cache[pkg] = got
    json.dump(cache, open(CACHE, 'w'), indent=0)
    return cache


def kind_of(mesh):
    short = mesh.split('.')[0].rsplit('/', 1)[1]
    for rx, k in SKIP:
        if rx.search(mesh.split('.')[0]) or rx.search(short): return k
    if PROP.search(short): return 'prop'
    return 'building'


def obb(M, b):
    """World oriented box of local box b under M: centre, yaw, half extents in its own (scaled) axes, z range."""
    o, e = b['origin'], b['extent']
    c = [sum(o[k] * M[k][j] for k in range(3)) + M[3][j] for j in range(3)]
    ax = [math.sqrt(sum(M[k][j] ** 2 for j in range(3))) for k in range(3)]
    h = [e[k] * ax[k] for k in range(3)]
    yaw = math.degrees(math.atan2(M[0][1], M[0][0]))
    corners = [[c[j] + sum(s[k] * e[k] * M[k][j] for k in range(3)) for j in range(3)]
               for s in [(a, b2, d) for a in (-1, 1) for b2 in (-1, 1) for d in (-1, 1)]]
    zs = [q[2] for q in corners]
    return c, yaw, h, min(zs), max(zs)


def dist_to_box(pt, e):
    """2D distance (cm) from pt to entry e's footprint (0 inside)."""
    a = math.radians(e['yaw']); dx, dy = pt[0] - e['x'], pt[1] - e['y']
    lx, ly = dx * math.cos(a) + dy * math.sin(a), -dx * math.sin(a) + dy * math.cos(a)
    ox, oy = max(abs(lx) - e['hx'], 0.0), max(abs(ly) - e['hy'], 0.0)
    return math.hypot(ox, oy)


def main():
    radius = 5.0; no_pull = '--no-pull' in sys.argv
    if '--radius-km' in sys.argv: radius = float(sys.argv[sys.argv.index('--radius-km') + 1])
    R = radius * 100000.0
    levels = sublevels()
    pull(levels, no_pull)
    placed = []
    for lv in levels:
        if not pkg_file(lv): print('missing level', lv, file=sys.stderr); continue
        got = level_placements(lv)
        near = [g for g in got if math.hypot(g[3][3][0] - PAD[0], g[3][3][1] - PAD[1]) < R + 50000]
        print(f'{lv}: {len(got)} placements, {len(near)} near the pad', file=sys.stderr)
        placed += [(lv,) + g for g in near]
    bounds = mesh_bounds([g[3] for g in placed], no_pull)
    entries, skipped, nob = [], {}, set()
    for lv, name, actor, mesh, M in placed:
        k = kind_of(mesh)
        if k not in ('building', 'prop'): skipped[k] = skipped.get(k, 0) + 1; continue
        b = bounds.get(mesh.split('.')[0])
        if not b or 'err' in b: nob.add(mesh); continue
        c, yaw, h, z0, z1 = obb(M, b)
        if math.hypot(c[0] - PAD[0], c[1] - PAD[1]) - math.hypot(h[0], h[1]) > R: continue
        if z1 - z0 < FLAT_CM: skipped['flat'] = skipped.get('flat', 0) + 1; continue
        if z0 > GROUND_CM + ELEVATED_CM: skipped['elevated'] = skipped.get('elevated', 0) + 1; continue
        entries.append(dict(mesh=mesh.split('.')[0].rsplit('/', 1)[1], kind=k,
                            compound=max(h[0], h[1]) * 2 > COMPOUND_CM,
                            x=round(c[0], 1), y=round(c[1], 1), z=round(c[2], 1), yaw=round(yaw, 2),
                            hx=round(h[0], 1), hy=round(h[1], 1), hz=round(h[2], 1),
                            zmin=round(z0, 1), zmax=round(z1, 1)))
    entries.sort(key=lambda e: math.hypot(e['x'] - PAD[0], e['y'] - PAD[1]))
    json.dump({'pad': PAD, 'radius_cm': R, 'count': len(entries), 'skipped': skipped,
               'no_bounds': sorted(nob), 'buildings': entries}, open(OUT, 'w'), separators=(',', ':'))
    print(f'{len(entries)} entries ({sum(e["kind"] == "building" for e in entries)} buildings) -> {OUT}')
    print('skipped:', skipped, ' meshes without bounds:', len(nob))
    big = sorted(entries, key=lambda e: -4 * e['hx'] * e['hy'])[:8]
    for e in big:
        print(f'  biggest: {e["mesh"]} {2 * e["hx"] / 100:.0f} x {2 * e["hy"] / 100:.0f} m, {e["zmax"] / 100:.0f} m top,'
              f' at ({e["x"]:.0f}, {e["y"]:.0f}), {math.hypot(e["x"] - PAD[0], e["y"] - PAD[1]) / 100:.0f} m from the pad')
    for nm, pt in KNOWN.items():
        d = sorted((dist_to_box(pt, e), e['mesh'], e['kind'], e['compound']) for e in entries)
        nc = [x for x in d if not x[3]][:1]
        print(f'  {nm:15s} nearest footprint {d[0][0] / 100:6.1f} m ({d[0][1]}, {d[0][2]})'
              + (f'; without compound meshes {nc[0][0] / 100:6.1f} m ({nc[0][1]})' if nc and nc[0] != d[0] else ''))


if __name__ == '__main__':
    main()
