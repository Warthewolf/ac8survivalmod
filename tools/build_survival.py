"""build_survival.py : generate Survival Mode's zen packages into mod/Content (run by tools/build_all.sh).

Every package is a stock game file with Survival's changes (Survival Mode uses nothing from another mod):
  - PL_SurvivalMode            <- PL_Mission022 (Map17 / Comona sublevels), Mission 4's sky (LIT_NEW)
  - MC_SurvivalMode            <- MC_Mission022
  - WD_SurvivalMode_global     <- WD_Mission022_global: no unit spawns at start but the airfield's targets, pool and bomber
                                  flights sized and given Survival's behaviour rows, the shuttle and the airport's AA guns /
                                  SAM sites in units of their own (split_units), Survival's NPC table
  - WD_SurvivalMode_phase01/02 <- WD_Mission022_phase01/02 (one player start each)
  - EP_SurvivalMode_global     <- EP_Mission022_global with only Survival's records (tools/survival_events.py)
  - EP_SurvivalMode_phase01/02 <- the phase EPs with every record removed
  - EF_SurvivalMode_global     <- EF_Mission022_global holding Survival's int flags (survival_events.INT_FLAGS)
  - DT_SV_MissionRows / DT_SV_MenuRows / DT_SV_ShopRows / DT_SV_NpcRows <- one-table copies of stock rows, added to the
                                  game's tables at run time by Scripts/main.lua; DT_SV_NpcMission <- DT_NPC_Mission022
  - /Game/LuaSource/SurvivalMode/AI/*  <- Survival's behaviour scripts (Scripts/ai)
Stock packages are pulled with tools/get_stock.sh into build/stock first.
"""
import copy, math, os, sys, struct, zlib
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, 'scripts'))
from zenpkg import ZenPkg, export_hash
import uprop, eprec
sys.path.insert(0, os.path.join(HERE, "checks"))
import survival_events, ep_dump

STOCK = os.path.join(ROOT, 'build', 'stock')
OUT = os.path.join(ROOT, 'mod', 'Content')

MOD = '/Game/Mods/SurvivalMode'
PL = MOD + '/Maps/PL_SurvivalMode'
MI = MOD + '/Mission/'
M22 = '/Game/Maps/Ingame/Mission022/'

# Player start: 6 km out on the approach to Comona Airport's runway, 1500 m up, flying at the airport.
# Runway centre and heading from Mission 22's VolumeBox_LandingArea0: (1609574, -435747, 0), yaw -23.
RUNWAY = (1609574.0, -435747.0); RUNWAY_YAW = -23.0
START_BACK_CM, START_ALT_CM = 600000.0, 150000.0
_yaw = math.radians(RUNWAY_YAW)
START = (RUNWAY[0] - START_BACK_CM * math.cos(_yaw), RUNWAY[1] - START_BACK_CM * math.sin(_yaw), START_ALT_CM)
START_ROT = (0.0, RUNWAY_YAW, 0.0)   # pitch, yaw, roll

# Mission 4's sky: its lighting sublevel (sky light, sun, height fog, post process and the LiveCloudlyActor cloud
# layer) plus the world-settings values PL_Mission004 uses with it. Mission 4 leaves CloudDensityScale at its default
# and sets CloudDensityScaleBySound. (Until 2026-10-22: Mission 16's Map14 sky, clock 08:00, CloudDensityScale 0.9.)
LIT_OLD = '/Game/Maps/MapCommon/Map17/Mission022/Mission022_Common_Lit_Cloudly01'
LIT_NEW = '/Game/Maps/MapCommon/Map05/Mission004/Mission004_Common_Lit_Cloudly01'
CLOCK = (10, 10)
CLOUD_DENSITY_BY_SOUND = struct.unpack('<f', b'\x8b\x6c\xa7\x3f')[0]   # PL_Mission004's value, bit for bit (1.308)
MISSION_TIME_LIMIT = 3600.0   # seconds; Mission 22 uses 900


def stock(path):
    p = os.path.join(STOCK, path[len('/Game/'):])
    for ext in ('.umap', '.uasset'):
        if os.path.exists(p + ext): return p + ext
    raise SystemExit(f'missing stock package {path}; run tools/get_stock.sh first')


def save(z, path, ext='.uasset'):
    p = os.path.join(OUT, path[len('/Game/'):]) + ext
    os.makedirs(os.path.dirname(p), exist_ok=True)
    data = z.write(); open(p, 'wb').write(data)
    ZenPkg(data=data)   # must parse back
    print(f'{path}  {len(data)} bytes')


def rename_package(z, old_path, new_path):
    """Package path + its top-level object (export 'name' == short name) + that export's public hash."""
    old_short, new_short = old_path.rsplit('/', 1)[1], new_path.rsplit('/', 1)[1]
    i = z.export_index(old_short)
    z.rename(old_path, new_path); z.rename(old_short, new_short)
    z.set_export_public_hash(i, new_short)


def retarget_import(z, old_pkg, new_pkg):
    """Point an imported package (and its top-level object's hash) at our renamed copy."""
    old_short, new_short = old_pkg.rsplit('/', 1)[1], new_pkg.rsplit('/', 1)[1]
    hs = z.imported_hash_index(old_pkg)
    assert len(hs) == 1, (old_pkg, hs)
    assert z.imp_hashes[hs[0]] == export_hash(old_short), old_pkg
    z.imp_hashes[hs[0]] = export_hash(new_short)
    z.set_imported_package(old_pkg, new_pkg)


def package_hash(path):
    return zlib.crc32(path.lower().encode()) & 0xffffffff


# ---------------------------------------------------------------- props helpers
def props_of(z, i, sname):
    """Export payload = 4-byte prefix (zero so far) + unversioned properties + rest. Returns (props, rest)."""
    p = bytes(z.payloads[i])
    assert p[:4] == b'\0\0\0\0', p[:4]
    v, o = uprop.read_struct(uprop.Ctx(p, z.names), 4, sname)
    assert write_props(z, v) == p[:o], f'{sname}: properties do not round-trip'
    return v, p[o:]


def write_props(z, v):
    """Prefix + properties (pair with the rest returned by props_of)."""
    return b'\0\0\0\0' + uprop.write_struct(uprop.W(z.names), v)


def set_prop(props, idx, name, value):
    """props: list of (idx, name, zero, value) sorted by idx; replace or insert."""
    props[:] = [p for p in props if p[0] != idx] + [(idx, name, False, value)]
    props.sort(key=lambda p: p[0])


def drop_prop(props, idx):
    props[:] = [p for p in props if p[0] != idx]


# ---------------------------------------------------------------- packages
def build_pl():
    z = ZenPkg(stock(M22 + 'PL_Mission022'))
    rename_package(z, M22 + 'PL_Mission022', PL)
    # Lighting: Mission 4's sky/cloud level instead of Mission 22's.
    z.rename(LIT_OLD, LIT_NEW); z.rename(LIT_OLD.rsplit('/', 1)[1], LIT_NEW.rsplit('/', 1)[1])
    # Mission files
    for n in ('MC_Mission022', 'WD_Mission022_global', 'WD_Mission022_phase01', 'WD_Mission022_phase02',
              'EP_Mission022_global', 'EP_Mission022_phase01', 'EP_Mission022_phase02'):
        retarget_import(z, M22 + n, MI + n.replace('Mission022', 'SurvivalMode'))
    retarget_import(z, RADIO_STOCK, RADIO)                 # Survival's copy of Mission 22's radio lines (build_radio)
    # World settings: Mission 4's clock and cloud values; drop Mission 22's shuttle-launch cloud light.
    i = z.export_index('ChronicleWorldSettings')
    v, rest = props_of(z, i, 'LiveWorldSettings')
    props = v[2]
    sc = uprop.U.schema('LiveWorldSettings')
    idx = {nm: k for k, (nm, t) in sc.items()}
    set_prop(props, idx['ClockHour'], 'ClockHour', ('raw', 'Int', struct.pack('<i', CLOCK[0])))
    set_prop(props, idx['ClockMin'], 'ClockMin', ('raw', 'Int', struct.pack('<i', CLOCK[1])))
    drop_prop(props, idx['CloudDensityScale'])
    set_prop(props, idx['CloudDensityScaleBySound'], 'CloudDensityScaleBySound',
             ('raw', 'Float', struct.pack('<f', CLOUD_DENSITY_BY_SOUND)))
    drop_prop(props, idx['CloudLightSettings'])
    z.payloads[i] = bytearray(write_props(z, v) + rest)
    chk, _ = props_of(z, i, 'LiveWorldSettings'); assert chk == v
    save(z, PL, '.umap')


def build_mc():
    z = ZenPkg(stock(M22 + 'MC_Mission022'))
    rename_package(z, M22 + 'MC_Mission022', MI + 'MC_SurvivalMode')
    v, rest = props_of(z, 0, 'LiveCampaignMissionConfig')
    set_prop(v[2], 7, 'MissionLimitTime', ('raw', 'Float', struct.pack('<f', MISSION_TIME_LIMIT)))
    z.payloads[0] = bytearray(write_props(z, v) + rest)
    save(z, MI + 'MC_SurvivalMode')


def build_wd_phase(n):
    old, new = M22 + f'WD_Mission022_phase0{n}', MI + f'WD_SurvivalMode_phase0{n}'
    z = ZenPkg(stock(old))
    rename_package(z, old, new)   # also renames the WorldDataName value (same FName)
    v, rest = props_of(z, 0, 'LiveWorldData')
    starts = [p for p in v[2] if p[1] == 'PlayerStartDescList'][0][3][1]
    assert len(starts) == 1
    ps = starts[0][2]
    for k, (pi, pn, zero, val) in enumerate(ps):
        if pn == 'SpawnPoint': ps[k] = (pi, pn, False, ('native', 'Vector', struct.pack('<3d', *START)))
        if pn == 'Rotation': ps[k] = (pi, pn, False, ('native', 'Rotator', struct.pack('<3d', *START_ROT)))
    z.payloads[0] = bytearray(write_props(z, v) + rest)
    save(z, new)


FORMATION_CM = 30000.0     # 300 m: pairs side by side, each pair this far behind the one ahead


def unit_point(u):
    sp = [p for p in u[2] if p[1] == 'SpawnPoint']
    return struct.unpack('<3d', sp[0][3][2]) if sp and sp[0][3] else (0.0, 0.0, 0.0)


def set_flight_size(objs, size, unit, point, used_ids, top_number):
    """Cut or grow a flight's AI object list to `size` (copies of the lead / wingman pair with new UniqueIDs and the next
    free number of their name: Mission 22 numbers one name across several flights, so top_number is world-wide), and
    lay it out: lead on the unit point, wingman beside it, each further pair FORMATION_CM back."""
    del objs[size:]
    while len(objs) < size:
        k = len(objs)
        ob = copy.deepcopy(objs[k % 2])
        name = [q for q in ob[2] if q[1] == 'Name'][0][3]
        top_number[name[1]] += 1
        top = top_number[name[1]] - 1
        h = zlib.crc32(f'AC8SurvivalMode:{unit}:{k}'.encode())
        while struct.pack('<I', h) in used_ids: h = (h + 1) & 0xffffffff
        used_ids.add(struct.pack('<I', h))
        ob[2][:] = [(q[0], q[1], False, ('name', name[1], top + 1)) if q[1] == 'Name' else
                    (q[0], q[1], False, ('raw', 'UInt32', struct.pack('<I', h))) if q[1] == 'UniqueID' else q for q in ob[2]]
        objs.append(ob)
    for k, ob in enumerate(objs):
        at = (point[0] - FORMATION_CM * (k // 2), point[1] + (FORMATION_CM if k % 2 else 0.0), point[2])
        assert any(q[1] == 'SpawnPoint' for q in ob[2]), unit
        ob[2][:] = [(q[0], q[1], False, ('native', 'Vector', struct.pack('<3d', *at))) if q[1] == 'SpawnPoint' else q
                    for q in ob[2]]


def move_object(units, used_ids, z, src_unit, obj, new_unit, npc_row=None):
    """Moves AI object `obj` (a name, or a list of names) out of world-data unit `src_unit` into a new unit `new_unit`:
    a copy of the source's desc (same faction, point, area and tags) with a new UniqueID, holding only those objects
    (optionally on NPC row `npc_row`). SV_Spawn(new_unit) without a position then puts them where the stock mission
    placed them. No ground object of Mission 22's leads its unit (bGroupLead 0), so such a unit needs no leader."""
    dn = lambda n: n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}'
    unit_name = lambda u: [p for p in u[2] if p[1] == 'Name'][0][3][1]
    src = [u for u in units if unit_name(u) == src_unit][0]
    assert new_unit not in {unit_name(u) for u in units} and not new_unit[-1].isdigit(), new_unit   # hard rule 17
    objs = [p for p in src[2] if p[1] == 'AIObjectDescList'][0][3][1]
    wanted = [obj] if isinstance(obj, str) else list(obj)
    moved = []
    for name in wanted:
        hit = [ob for ob in objs if dn([q for q in ob[2] if q[1] == 'Name'][0][3]) == name]
        assert len(hit) == 1, name
        objs.remove(hit[0])
        moved.append(hit[0])
    new = copy.deepcopy(src)
    if npc_row:
        for ob in moved:
            assert any(q[1] == 'MissionNpcID' for q in ob[2]), obj
            ob[2][:] = [(q[0], q[1], False, ('name', npc_row, 0)) if q[1] == 'MissionNpcID' else q for q in ob[2]]
        z.nb.add(npc_row)
    z.nb.add(new_unit)
    ids = used_ids | {q[3][2] for u in units for q in u[2] if q[1] == 'UniqueID' and q[3]}
    h = zlib.crc32(b'AC8SurvivalMode:' + new_unit.encode())
    while struct.pack('<I', h) in ids: h = (h + 1) & 0xffffffff
    assert any(q[1] == 'UniqueID' for q in new[2]), 'unit desc without UniqueID'
    new[2][:] = [(q[0], q[1], False, ('name', new_unit, 0)) if q[1] == 'Name' else
                 (q[0], q[1], False, ('raw', q[3][1], struct.pack('<I', h))) if q[1] == 'UniqueID' else q for q in new[2]]
    [p for p in new[2] if p[1] == 'AIObjectDescList'][0][3][1][:] = moved
    units.append(new)
    return len(objs)


def new_unique_id(used_ids, seed):
    h = zlib.crc32(seed.encode())
    while struct.pack('<I', h) in used_ids: h = (h + 1) & 0xffffffff
    used_ids.add(struct.pack('<I', h))
    return struct.pack('<I', h)


def path_start(v, path):
    """The world position (cm) of AI path `path`'s first point."""
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    for el in paths:
        f = {p[1]: p[3] for p in el[2]}
        if f['Name'][1:3] == (path, 0):
            pos = {p[1]: p[3] for p in f['BeginPointDesc'][2]}['Pos']
            return struct.unpack('<3d', pos[2])
    raise LookupError(path)


def set_unit_point(u, point):
    """Unit desc `u` and its AI objects (and so their turrets) at `point` (cm)."""
    vec = ('native', 'Vector', struct.pack('<3d', *point))
    u[2][:] = [(q[0], q[1], False, vec) if q[1] == 'SpawnPoint' else q for q in u[2]]
    for ob in [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1]:
        ob[2][:] = [(q[0], q[1], False, vec) if q[1] == 'SpawnPoint' else q for q in ob[2]]


def clear_flags(u, flags):
    """Every AI object of unit desc `u` with these bool properties written as an explicit false."""
    for ob in [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1]:
        ob[2][:] = [(q[0], q[1], True, None) if q[1] in flags else q for q in ob[2]]


def retag_turrets(children, owner, rows, used_ids, z):
    """A copied ship's turret descs (ChildAIObjectDescs / GrandChildrens): named after their new owner as Mission 22
    names them (<owner>_<component>), new UniqueIDs, and Survival's mission rows (`rows`: stock row -> Survival's)."""
    for ch in children:
        d = {p[1]: p for p in ch[2]}
        data = d['Data'][3][2]
        comp = [q for q in data if q[1] == 'ComponentFieldName'][0][3][1]
        stock_row = [q for q in data if q[1] == 'MissionNpcID'][0][3][1]
        assert stock_row in rows, (owner, stock_row)
        data[:] = [(q[0], q[1], False, ('name', rows[stock_row], 0)) if q[1] == 'MissionNpcID' else q for q in data]
        name = f'{owner}_{comp}'
        assert not name.rpartition('_')[2].isdigit(), name                  # no _<digits> tail: hard rule 17
        uid = new_unique_id(used_ids, 'AC8SurvivalMode:' + name)
        ch[2][:] = [(q[0], q[1], False, ('name', name, 0)) if q[1] == 'Name' else
                    (q[0], q[1], False, ('raw', 'UInt32', uid)) if q[1] == 'UniqueID' else q for q in ch[2]]
        for n in (name, rows[stock_row]): z.nb.add(n)
        grand = d.get('GrandChildrens')
        if grand and grand[3]: retag_turrets(grand[3][1], name, rows, used_ids, z)


def ally_units(units, used_ids, z, top_number, v):
    """The STORE's allies (survival_events.ALLY_*): MOONCHILD's two-ships, parked where Mission 22 parks its scramble
    jets, and the ships, each at the start of its lane. Both may be targeted and killed (Mission 22's jets are
    invincible and its allied ships attack-target exceptions)."""
    unit_by = lambda n: [u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == n][0]
    r_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'RadiusInMeter'][0]
    for unit in survival_events.ALLY_AIR_UNITS:
        names = copy_unit(units, used_ids, z, survival_events.ALLY_AIR_SOURCE, unit, 2, top_number,
                          'SV_Obj_' + unit[len('SV_Unit_'):], survival_events.ALLY_AIR_ROW)
        survival_events.ALLY_AIR_OBJS[unit] = names
        u = unit_by(unit)
        clear_flags(u, ('bIsInvincible',))
        u[2][:] = sorted([p for p in u[2] if p[1] != 'RadiusInMeter'] + [(r_idx, 'RadiusInMeter', False,
                         ('raw', 'Float', struct.pack('<f', survival_events.AREA_RADIUS_M)))], key=lambda p: p[0])
    hulls = {key: (src, hull) for key, src, hull, _ in survival_events.ALLY_SHIPS}
    for key, n, unit, obj, lane in survival_events.ally_ships():
        src, hull = hulls[key]
        rows = {t: survival_events.ally_turret_rows(t)[0] for t in survival_events.ALLY_TURRETS[key]}
        names = copy_unit(units, used_ids, z, src, unit, 1, top_number, obj, survival_events.ally_ship_rows(key)[0])
        assert names == [obj], names
        u = unit_by(unit)
        clear_flags(u, ('bIsAttackTargetsException',))
        ob = [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
        retag_turrets([p for p in ob[2] if p[1] == 'ChildAIObjectDescs'][0][3][1], obj, rows, used_ids, z)
        x, y, _ = path_start(v, lane)
        set_unit_point(u, (x, y, 300.0))
        area = {'RadiusInMeter': survival_events.ALLY_SHIP_AREA_M, 'MinAltitudeInMeter': survival_events.ALLY_SHIP_ALT_M[0],
                'MaxAltitudeInMeter': survival_events.ALLY_SHIP_ALT_M[1]}
        sc = uprop.U.schema('LiveUnitDesc')
        aidx = {n: k for k, (n, t) in sc.items() if n in area}
        assert len(aidx) == 3, aidx
        u[2][:] = sorted([p for p in u[2] if p[1] not in area] + [(aidx[n], n, False, ('raw', 'Float', struct.pack('<f', val)))
                         for n, val in area.items()], key=lambda p: p[0])
    print(f'  allies: {len(survival_events.ALLY_AIR_UNITS)} MOONCHILD flights {survival_events.ALLY_AIR_OBJS}, '
          f'{len(survival_events.ally_ships())} ships')


M13 = '/Game/Maps/Ingame/Mission013/'


def stock_wd(path):
    """A stock world data's LiveWorldData properties (for descs copied from another mission)."""
    zs = ZenPkg(stock(path))
    i = zs.export_index(path.rsplit('/', 1)[1])
    v, _ = props_of(zs, i, 'LiveWorldData')
    return v


def desc_named(v, lst, name):
    for el in [p for p in v[2] if p[1] == lst][0][3][1]:
        if [p for p in el[2] if p[1] == 'Name'][0][3][1:3] == survival_events.fname(name)[1:]:   # ('Boss_0' = ('Boss', 1))
            return el
    raise LookupError((lst, name))


def vec(x, y, zz, kind='Vector'):
    return ('native', kind, struct.pack('<3d', x, y, zz))


def port_unit(units, used_ids, z, src, new_unit, obj_name, npc_row, points, yaw, top_number, tgt=False):
    """A new unit `new_unit` from another mission's unit desc `src`: its first len(points) AI objects at `points`
    (cm), facing `yaw`, named obj_name (numbered _0, _1 ... when more than one) on NPC row `npc_row`; no tags (they're
    the other mission's), our world data's name, new UniqueIDs; tgt: a target box and a TGT mark on each (user,
    2026-10-23: "assault ships and troops did not come with target boxes"). Returns the objects' names as event args
    write them."""
    new = copy.deepcopy(src)
    assert new_unit not in {[p for p in u[2] if p[1] == 'Name'][0][3][1] for u in units}, new_unit
    assert not new_unit[-1].isdigit() and not obj_name[-1].isdigit() and obj_name not in top_number, obj_name
    wd = ('name', 'WD_SurvivalMode_global', 0)
    objs = [p for p in new[2] if p[1] == 'AIObjectDescList'][0][3][1]
    while len(objs) < len(points): objs.append(copy.deepcopy(objs[-1]))   # more than the source has: copies of its last
    del objs[len(points):]
    names = []
    for k, (ob, pt) in enumerate(zip(objs, points)):
        num = 0 if len(points) == 1 else k + 1
        uid = new_unique_id(used_ids, f'AC8SurvivalMode:{new_unit}:{k}')
        repl = {'Name': ('name', obj_name, num), 'MissionNpcID': ('name', npc_row, 0), 'UniqueID': ('raw', 'UInt32', uid),
                'SpawnPoint': vec(*pt), 'Rotation': vec(0.0, yaw, 0.0, 'Rotator'), 'WorldDataName': wd,
                'Tags': ('arr', [])}
        assert all(any(q[1] == n for q in ob[2]) for n in ('Name', 'MissionNpcID', 'UniqueID', 'SpawnPoint')), new_unit
        ob[2][:] = [(q[0], q[1], False, repl[q[1]]) if q[1] in repl and q[3] is not None else q for q in ob[2]]
        if tgt:                    # the HUD's target box and the red TGT mark (ELiveTargetMarkType 1), as a mission target
            sc = uprop.U.schema('LiveAIObjectDesc')
            ix = {n: k for k, (n, t) in sc.items() if n in ('TargetMarkType', 'bShowHUDBox')}
            ob[2][:] = sorted([q for q in ob[2] if q[1] not in ix] + [
                (ix['TargetMarkType'], 'TargetMarkType', False, ('enum', 'ELiveTargetMarkType', ('raw', 'Byte', b'\x01'))),
                (ix['bShowHUDBox'], 'bShowHUDBox', False, ('raw', 'Bool', b'\x01'))], key=lambda q: q[0])
        names.append(obj_name if num == 0 else f'{obj_name}_{num - 1}')
    top_number[obj_name] = len(points)
    uid = new_unique_id(used_ids, f'AC8SurvivalMode:{new_unit}')
    cx, cy = sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)
    repl = {'Name': ('name', new_unit, 0), 'UniqueID': ('raw', 'UInt32', uid), 'SpawnPoint': vec(cx, cy, 0.0),
            'Rotation': vec(0.0, yaw, 0.0, 'Rotator'), 'WorldDataName': wd, 'Tags': ('arr', [])}
    new[2][:] = [(q[0], q[1], False, repl[q[1]]) if q[1] in repl and q[3] is not None else q for q in new[2]]
    # never at the level's start (the source may say so: Mission 16's Ladons and EB_002's Alicorn did, and build_wd_global's
    # switch-off has run by now; code review of 2026-10-23): an explicit zero, as Mission 22's reinforcements carry it
    sp_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'bIsSpawnFromStart'][0]
    new[2][:] = sorted([q for q in new[2] if q[1] != 'bIsSpawnFromStart'] + [(sp_idx, 'bIsSpawnFromStart', True, None)],
                       key=lambda q: q[0])
    assert npc_row in NPC_ROWS, npc_row
    for n in names_in(new) + [new_unit, obj_name, npc_row, 'WD_SurvivalMode_global']: z.nb.add(n)
    units.append(new)
    return names


def make_path(z, used_ids, template, name, pts, smooth=False, before=None, after=None):
    """An AI path desc `name` through `pts` (cm), shaped like `template` (Mission 13's LCAC path: begin point, points
    with tangents, ControlType 1). Default: short level tangents (at most 1.2 km), up straight up, no pitch: fine for
    craft and vehicles. smooth=True (aircraft: the Ladons): Mission 16's Ladon path's shape, each tangent along the
    line through its neighbours (3D) and as long as its shorter leg, so the spline turns in wide curves; up banked into
    the turn (up to 50 degrees, with the turn's angle) and the rotation's pitch the climb. `before` / `after`: the
    points just outside `pts` (a circuit's other end, the next path's second point), so the tangent runs on smoothly."""
    import math
    new = copy.deepcopy(template)
    f = {p[1]: p for p in new[2]}
    begin = f['BeginPointDesc'][3]
    point_t = f['PathPointDescList'][3][1][0]

    def unit(v):
        n = math.sqrt(sum(c * c for c in v)) or 1.0
        return [c / n for c in v]

    def shape(k, pos):
        prv = pts[k - 1] if k > 0 else (before or pos)
        nxt = pts[k + 1] if k + 1 < len(pts) else (after or pos)
        if not smooth:
            dx, dy = (nxt[0] - prv[0]), (nxt[1] - prv[1])
            seg = math.hypot(dx, dy) or 1.0
            tan = (dx / seg * min(seg, 120000.0), dy / seg * min(seg, 120000.0), 0.0)
            return tan, (0.0, 0.0, 1.0), (0.0, math.degrees(math.atan2(dy, dx)), 0.0)
        legs = [math.dist(a, b) for a, b in ((prv, pos), (pos, nxt)) if math.dist(a, b) > 1.0]
        d = unit([nxt[i] - prv[i] for i in range(3)])
        tan = tuple(c * min(legs or [1.0]) for c in d)
        din = unit([pos[0] - prv[0], pos[1] - prv[1], 0.0]) if math.dist(prv, pos) > 1.0 else None
        dout = unit([nxt[0] - pos[0], nxt[1] - pos[1], 0.0]) if math.dist(pos, nxt) > 1.0 else None
        up = (0.0, 0.0, 1.0)
        if din and dout:
            turn = math.acos(max(-1.0, min(1.0, din[0] * dout[0] + din[1] * dout[1])))
            inside = unit([dout[0] - din[0], dout[1] - din[1], 0.0])
            bank = min(math.radians(50.0), turn * 0.6)
            if turn > 0.02:
                up = (inside[0] * math.sin(bank), inside[1] * math.sin(bank), math.cos(bank))
        pitch = math.degrees(math.atan2(d[2], math.hypot(d[0], d[1])))
        return tan, up, (pitch, math.degrees(math.atan2(d[1], d[0])), 0.0)

    def point(el, k, pos, pname):
        tan, up, rot = shape(k, pos)
        repl = {'Pos': vec(*pos), 'tan': vec(*tan), 'Up': vec(*up), 'PathPointRotation': vec(*rot, 'Rotator'),
                'UniqueID': ('raw', 'UInt32', new_unique_id(used_ids, f'AC8SurvivalMode:{name}:{k}')), 'Name': pname}
        el = copy.deepcopy(el)
        el[2][:] = [(q[0], q[1], False, repl[q[1]]) if q[1] in repl and q[3] is not None else q for q in el[2]]
        return el
    els, b = [], None
    for k, pos in enumerate(pts):
        if k == 0:
            b = point(begin, k, pos, ('name', 'DefaultPathPoint', 0))
        else:
            els.append(point(point_t, k, pos, ('name', name, k)))
    # no tube data: a template's (Mission 16's Ladon path) names a tube object in its own package, an export index past
    # ours ("Bad export index 74/19": the game's loader stopped at the hangar, 2026-10-23)
    tube = ('struct', 'LiveAIPathTubeData', [(0, 'TubeData', False, ('arr', [])), (1, 'MoveData', False, ('arr', []))])
    # and so no tube control (ControlType 2): a tube path without its tube "finishes" at once, every frame (the Ladons'
    # PathFinish fired ~30 times a second and restarted their circuit: no route, a bombing run a second, 2026-10-23)
    ctl = ('enum', 'ELiveAIPathControlType', ('raw', 'Byte', b'\x01'))
    repl = {'BeginPointDesc': b, 'PathPointDescList': ('arr', els), 'PathTubeData': tube,
            'UniqueID': ('raw', 'UInt32', new_unique_id(used_ids, f'AC8SurvivalMode:{name}')),
            'Name': ('name', name, 0), 'WorldDataName': ('name', 'WD_SurvivalMode_global', 0)}
    ct = [q for q in new[2] if q[1] == 'ControlType']
    if ct and ct[0][3] is not None and ct[0][3][2][2] == b'\x02': repl['ControlType'] = ctl
    new[2][:] = [(q[0], q[1], False, repl[q[1]]) if q[1] in repl else q for q in new[2]]
    for n in names_in(new) + [name, 'DefaultPathPoint']: z.nb.add(n)
    return new


M16 = '/Game/Maps/Ingame/Mission016/'


def import_from(z, zs, ref):
    """Our import index for another package's import `ref` (('obj', -n) in `zs`): the same imported package and public
    export hash, added to `z`'s import map (and its imported packages) when it isn't there yet. Hard rule 7: pack.py
    puts the package into the container header from this list."""
    assert ref[0] == 'obj' and ref[1] < 0, ref
    x = zs.imports[-ref[1] - 1]
    assert x >> 62 == 2, hex(x)                               # a package import
    pkg = zs.imp_pkgs[(x >> 32) & 0x3fffffff]
    h = zs.imp_hashes[x & 0xffffffff]
    if pkg not in z.imp_pkgs:
        z.ipn.add(pkg)
        z.imp_pkg_nums.append(0)
    k = z.imp_pkgs.index(pkg)
    if h not in z.imp_hashes:
        z.imp_hashes.append(h)
    new = (2 << 62) | (k << 32) | z.imp_hashes.index(h)
    if new not in z.imports:
        z.imports.append(new)
    return ('obj', -(z.imports.index(new) + 1))


def retag_parts(children, owner, used_ids, z, zs):
    """A ported aircraft's parts (ChildAIObjectDescs / GrandChildrens): named after their new owner (<owner>_<component>,
    keeping the component's FName number), new UniqueIDs, our world data's name, and their classes imported from the
    source package `zs`. Their mission rows stay the source mission's (NPC_IMPORT brings them)."""
    n = 0
    for ch in children:
        d = {p[1]: p for p in ch[2]}
        data = d['Data'][3][2]
        comp = [q for q in data if q[1] == 'ComponentFieldName'][0][3]
        data[:] = [(q[0], q[1], False, import_from(z, zs, q[3])) if q[1] == 'Class' and q[3] is not None else q for q in data]
        name = (f'{owner}_{comp[1]}', comp[2])
        assert not name[0].rpartition('_')[2].isdigit(), name                 # hard rule 17
        uid = new_unique_id(used_ids, f'AC8SurvivalMode:{name[0]}:{name[1]}')
        ch[2][:] = [(q[0], q[1], False, ('name',) + name) if q[1] == 'Name' else
                    (q[0], q[1], False, ('raw', 'UInt32', uid)) if q[1] == 'UniqueID' else
                    (q[0], q[1], False, ('name', 'WD_SurvivalMode_global', 0)) if q[1] == 'WorldDataName' and q[3] is not None else q
                    for q in ch[2]]
        for nm in names_in(ch): z.nb.add(nm)
        n += 1
        grand = d.get('GrandChildrens')       # (after the whole name: EB_002's WP_L #2..#7 each hold a ram / aagun / ciws)
        sub = f'{owner}_{comp[1]}' + (f'_{comp[2] - 1}' if comp[2] else '')
        if grand and grand[3]: n += retag_parts(grand[3][1], sub, used_ids, z, zs)
    return n


def zone_area(u):
    """Unit desc `u`'s area over the whole combat zone (as the pool's: a 6-10 km area keeps an AI from what's outside)."""
    r_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'RadiusInMeter'][0]
    u[2][:] = sorted([p for p in u[2] if p[1] != 'RadiusInMeter'] + [(r_idx, 'RadiusInMeter', False,
                     ('raw', 'Float', struct.pack('<f', survival_events.AREA_RADIUS_M)))], key=lambda p: p[0])


def ladon_units(units, used_ids, z, top_number, v):
    """The Ladons (survival_events.LADON*): Mission 16's Ladon desc with its parts, once per Ladon, at the start of
    its route, on its own mission row; its route and its circuit round the airfield."""
    m16z = ZenPkg(stock(M16 + 'WD_Mission016_global'))
    i = m16z.export_index('WD_Mission016_global')
    m16, _ = props_of(m16z, i, 'LiveWorldData')
    src = desc_named(m16, 'UnitDescList', survival_events.LADON_SOURCE_UNIT)
    src_path = desc_named(m16, 'AIPathDescList', survival_events.LADON_SOURCE_PATH)
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    import math
    pz = ZenPkg(stock(survival_events.LADON_PULSE_WD))       # the pulse cannon pod's class (survival_events.LADON_PULSE_*)
    pw, _ = props_of(pz, pz.export_index(survival_events.LADON_PULSE_WD.rsplit('/', 1)[1]), 'LiveWorldData')
    pref = None
    for pu in [q for q in pw[2] if q[1] == 'UnitDescList'][0][3][1]:
        for pob in [q for q in pu[2] if q[1] == 'AIObjectDescList'][0][3][1]:
            pk = [q for q in pob[2] if q[1] == 'ChildAIObjectDescs']
            for ch in (pk[0][3][1] if pk and pk[0][3] else []):
                data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
                if [q for q in data if q[1] == 'ComponentFieldName'][0][3][1] == survival_events.LADON_PULSE_PART:
                    pref = [q for q in data if q[1] == 'Class'][0][3]
    assert pref and pref[0] == 'obj' and pref[1] < 0, pref
    for L in survival_events.ladons():
        (x0, y0, z0), (x1, y1, _) = L['route'][0], L['route'][1]
        yaw = math.degrees(math.atan2(y1 - y0, x1 - x0))
        names = port_unit(units, used_ids, z, src, L['unit'], L['obj'], L['row'], [L['route'][0]], yaw, top_number)
        assert names == [L['obj']], names
        u = [u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == L['unit']][0]
        ob = [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
        kids = [p for p in ob[2] if p[1] == 'ChildAIObjectDescs'][0][3][1]
        parts = retag_parts(kids, L['obj'], used_ids, z, m16z)
        pulse = 0                                          # the CIWS slots: the Arsenal Bird's pulse cannon pods
        for ch in kids:
            data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
            comp = [q for q in data if q[1] == 'ComponentFieldName'][0][3][1]
            if comp in survival_events.LADON_CIWS:
                data[:] = [(q[0], q[1], False, import_from(z, pz, pref)) if q[1] == 'Class' and q[3] is not None else q for q in data]
                pulse += 1
        assert pulse == len(survival_events.LADON_CIWS), pulse
        # its area over the whole job (survival_events.LADON_AREA), not 40 km round the far-west spawn
        (ax, ay), radius = survival_events.LADON_AREA
        r_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'RadiusInMeter'][0]
        u[2][:] = sorted([q for q in u[2] if q[1] != 'RadiusInMeter'] + [(r_idx, 'RadiusInMeter', False,
                         ('raw', 'Float', struct.pack('<f', radius)))], key=lambda q: q[0])
        u[2][:] = [(q[0], q[1], False, vec(ax * 100000.0, ay * 100000.0, 0.0)) if q[1] == 'SpawnPoint' else q for q in u[2]]
        far = max(math.dist((ax * 100000.0, ay * 100000.0), pt[:2]) for pt in L['route'] + L['circuit']) / 100.0
        assert far < radius * 0.9, (L['unit'], far, radius)
        # smooth: wide banked turns (players saw sharp flat turns with 1.2 km tangents, 2026-10-23); the route runs on
        # into the circuit, and the circuit (it ends over the airfield and starts just past it) into itself
        loop = L['circuit']
        paths.append(make_path(z, used_ids, src_path, L['path'], L['route'], smooth=True, after=loop[0]))
        paths.append(make_path(z, used_ids, src_path, L['loop'], loop, smooth=True, before=loop[-1], after=loop[0]))
        print(f'  ladon: {L["unit"]} ({L["row"]}), {parts} parts, route {len(L["route"])} points + circuit')


EB002 = '/Game/OnlineMode/Maps/EmergencyCall/EB_002/'


def alcn_units(units, used_ids, z, top_number, v):
    """The Alicorn (survival_events.ALCN_*): EB_002's Boss_0 at the start of its lane, without the pools it launches,
    its parts' classes imported (import_from); its ways out and back."""
    import math
    ebz = ZenPkg(stock(EB002 + 'WD_EB_002'))
    i = ebz.export_index('WD_EB_002')
    eb, _ = props_of(ebz, i, 'LiveWorldData')
    src = copy.deepcopy(desc_named(eb, 'UnitDescList', survival_events.ALCN_SOURCE_UNIT))
    ob = [p for p in src[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
    kids = [p for p in ob[2] if p[1] == 'ChildAIObjectDescs'][0][3][1]
    def comp(ch):
        data = [p for p in ch[2] if p[1] == 'Data'][0][3][2]
        return [q for q in data if q[1] == 'ComponentFieldName'][0][3][1]
    dropped = [comp(ch) for ch in kids if comp(ch) in survival_events.ALCN_DROP]
    kids[:] = [ch for ch in kids if comp(ch) not in survival_events.ALCN_DROP]
    paths_def = survival_events.alcn_paths()
    (x0, y0, z0), (x1, y1, _) = paths_def[0][1][0], paths_def[0][1][1]
    names = port_unit(units, used_ids, z, src, survival_events.ALCN_UNIT, survival_events.ALCN_OBJ,
                      survival_events.ALCN_ROW, [(x0, y0, z0)], math.degrees(math.atan2(y1 - y0, x1 - x0)), top_number)
    assert names == [survival_events.ALCN_OBJ], names
    u = [u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == survival_events.ALCN_UNIT][0]
    ob = [p for p in u[2] if p[1] == 'AIObjectDescList'][0][3][1][0]
    parts = retag_parts([p for p in ob[2] if p[1] == 'ChildAIObjectDescs'][0][3][1], survival_events.ALCN_OBJ, used_ids, z, ebz)
    zone_area(u)
    src_path = desc_named(eb, 'AIPathDescList', survival_events.ALCN_SOURCE_PATH)
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    for name, pts in paths_def:
        paths.append(make_path(z, used_ids, src_path, name, pts))
    print(f'  alicorn: {survival_events.ALCN_UNIT}, {parts} parts ({len(dropped)} pools left out: {", ".join(dropped)})')


# The Alicorn's rows, all Online Mode's (tools/re/ALICORN.md 3, 5): copies of the rows it needs, into Survival tables
# that Scripts/main.lua adds to the campaign tables at the main menu (CFG.specials.alicorn.tables).
ON_NPC = '/Game/OnlineMode/DataTables/AI/NPC/'
ALCN_TABLES = [   # (Online table, row struct, Survival's copy, the campaign table main.lua adds the rows to)
    (ON_NPC + 'DT_NPC_ON', 'LiveNpcDataTable', 'DT_SV_AlcnNpc', '/Game/Datatables/AI/NPC/DT_NPC'),
    (ON_NPC + 'DT_NPC_Model_ON', 'LiveModelDataTable', 'DT_SV_AlcnModel', '/Game/Datatables/AI/NPC/Model/DT_NPC_Model'),
    (ON_NPC + 'DT_NPC_WeaponDurability_ON', 'LiveWeaponDurabilityDataTable', 'DT_SV_AlcnWpDur',
     '/Game/Datatables/AI/NPC/WeaponDurability/DT_NPC_WeaponDurability'),
    (ON_NPC + 'DT_NPC_ExplosionDurability_ON', 'LiveExplosionDurabilityDataTable', 'DT_SV_AlcnExDur',
     '/Game/Datatables/AI/NPC/ExplosionDurability/DT_NPC_ExplosionDurability'),
]


def build_alicorn_rows():
    """DT_SV_Alcn*: the Alicorn's NPC rows (alcn_01 with its pools left out of its children, and every kept part's,
    down the tree), their model rows and the durability rows they name."""
    def load(path, st):
        z = ZenPkg(stock(path))
        dt, o = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, st)
        assert o == len(z.payloads[0]), path
        return z, dt
    def key(k): return k[0] if k[1] == 0 else f'{k[0]}_{k[1] - 1}'
    def field(row, n):
        q = [q for q in row[2] if q[1] == n]
        return q[0][3] if q else None
    def nm(v): return None if v is None else (v[1] if v[2] == 0 else f'{v[1]}_{v[2] - 1}')
    zn, dn = load(ALCN_TABLES[0][0], ALCN_TABLES[0][1])
    npc = {key(k): (k, row) for k, row in dn['rows']}
    # (and the Arsenal Bird's pulse cannon pod, on the Ladons' CIWS slots: survival_events.LADON_PULSE_NPC)
    want, seen, refs = [survival_events.ALCN_ROW, survival_events.LADON_PULSE_NPC], [], {'ModelId': set(), 'WeaponDurabilityId': set(), 'ExplosionDurabilityId': set()}
    while want:
        r = want.pop(0)
        if r in seen or r in ('None', ''): continue
        seen.append(r)
        row = npc[r][1]
        kids, comps = field(row, 'ChildNPCId'), field(row, 'ChildNPCComponentNames')
        if r == survival_events.ALCN_ROW:        # its pools out
            keep = [i for i, c in enumerate(comps[1]) if nm(c) not in survival_events.ALCN_DROP]
            row[2][:] = [(q[0], q[1], q[2], ('arr', [q[3][1][i] for i in keep])) if q[1] in ('ChildNPCId', 'ChildNPCComponentNames')
                         else q for q in row[2]]
            kids = field(row, 'ChildNPCId')
        for k in (kids[1] if kids else []): want.append(nm(k))
        for f in refs:
            v = field(row, f)
            if v is not None and nm(v) not in ('None', ''): refs[f].add(nm(v))
    keepsets = {0: set(seen), 1: refs['ModelId'], 2: refs['WeaponDurabilityId'], 3: refs['ExplosionDurabilityId']}
    for i, (src, st, out, _) in enumerate(ALCN_TABLES):
        z, dt = (zn, dn) if i == 0 else load(src, st)
        rename_package(z, src, DATA + out)
        rows = [(k, row) for k, row in dt['rows'] if key(k) in keepsets[i]]
        assert {key(k) for k, _ in rows} == keepsets[i], (out, keepsets[i] - {key(k) for k, _ in rows})
        for k, row in rows:
            for n in names_in(row) + [k[0]]: z.nb.add(n)
        dt['rows'] = rows
        z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
        chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, st)
        assert chk['rows'] == dt['rows']
        save(z, DATA + out)
        print(f'  {out}: {len(rows)} rows')


def lcac_units(units, used_ids, z, top_number, v):
    """The amphibious assault (survival_events.LCAC_*): per lane a unit of four landing craft (LCAC_CRAFT) at its start, each
    craft's path in and back out, and per craft a troop unit (one BTR-90) on the beach where it lands."""
    m13 = stock_wd(M13 + 'WD_Mission013_global')
    src_craft = desc_named(m13, 'UnitDescList', survival_events.LCAC_SOURCE_UNIT)
    src_troop = desc_named(m13, 'UnitDescList', survival_events.LCAC_TROOP_SOURCE)
    src_path = desc_named(m13, 'AIPathDescList', survival_events.LCAC_SOURCE_PATH)
    src_drive = desc_named(m13, 'AIPathDescList', survival_events.LCAC_TROOP_SOURCE_PATH)
    paths = [p for p in v[2] if p[1] == 'AIPathDescList'][0][3][1]
    craft = survival_events.lcac_craft()
    for lane in survival_events.lcac_lane_names():
        cs = [c for c in craft if c['lane'] == lane]
        names = port_unit(units, used_ids, z, src_craft, cs[0]['unit'], cs[0]['obj_base'], survival_events.LCAC_ROW,
                          [c['start'] for c in cs], cs[0]['yaw'], top_number, tgt=True)
        assert names == [c['obj'] for c in cs], names
    for c in craft:
        (sx, sy, sz), (bx, by, bz) = c['start'], c['beach']
        at = lambda t, zz: (sx + (bx - sx) * t, sy + (by - sy) * t, zz)
        shore = 1.0 - min(0.08, 60000.0 / c['length'])           # the last point at sea, up to 600 m off the beach
        inbound = [at(0.0, 0.0), at(0.35, sz), at(0.7, sz), at(shore, sz), at(1.0, bz)]
        back = [at(1.0, bz), at(shore, sz), at(0.6, sz), at(0.2, sz), at(-0.3, sz)]   # out past the start
        paths.append(make_path(z, used_ids, src_path, c['path'], inbound))
        paths.append(make_path(z, used_ids, src_path, c['back'], back))
        (gx, gy, gz) = c['runway']                                  # the troops' drive: beach to their runway spot
        gnd = survival_events.LCAC_GROUND_Z
        drive = [(bx, by, bz)] + [(bx + (gx - bx) * t, by + (gy - by) * t, gnd) for t in (0.15, 0.4, 0.65, 0.9)] + [(gx, gy, gz)]
        paths.append(make_path(z, used_ids, src_drive, c['drive'], drive))
        port_unit(units, used_ids, z, src_troop, c['troops'], c['troop_obj'], survival_events.LCAC_TROOP_ROW,
                  [c['beach']], c['yaw'], top_number, tgt=True)
    print(f'  amphibious assault: {len(survival_events.LCAC_LANES)} lanes of {len(survival_events.LCAC_CRAFT)} landing craft, {len(craft) * 3} paths, '
          f'{len(craft)} troop units')


def copy_unit(units, used_ids, z, src_unit, new_unit, size, top_number, obj_name, npc_row):
    """A new unit `new_unit`: a copy of `src_unit`'s desc (faction, point, area, tags) holding its first `size` AI
    objects, named obj_name (numbered _0, _1, ... when more than one) with new UniqueIDs, on NPC row `npc_row` (their
    airframe and, built at level load, their behaviour: hard rule 20). Returns the objects' names as event args write them."""
    unit_name = lambda u: [p for p in u[2] if p[1] == 'Name'][0][3][1]
    src = [u for u in units if unit_name(u) == src_unit][0]
    assert new_unit not in {unit_name(u) for u in units} and not new_unit[-1].isdigit(), new_unit   # hard rule 17
    new = copy.deepcopy(src)
    objs = [p for p in new[2] if p[1] == 'AIObjectDescList'][0][3][1]
    assert len(objs) >= size, (src_unit, len(objs), size)
    del objs[size:]
    assert obj_name not in top_number and not obj_name[-1].isdigit(), obj_name
    names = []
    for k, ob in enumerate(objs):
        num = 0 if size == 1 else k + 1                       # FName number: 0 = no suffix, n = "_<n-1>"
        h = zlib.crc32(f'AC8SurvivalMode:{new_unit}:{k}'.encode())
        while struct.pack('<I', h) in used_ids: h = (h + 1) & 0xffffffff
        used_ids.add(struct.pack('<I', h))
        assert any(q[1] == 'MissionNpcID' for q in ob[2]), new_unit
        ob[2][:] = [(q[0], q[1], False, ('name', obj_name, num)) if q[1] == 'Name' else
                    (q[0], q[1], False, ('name', npc_row, 0)) if q[1] == 'MissionNpcID' else
                    (q[0], q[1], False, ('raw', 'UInt32', struct.pack('<I', h))) if q[1] == 'UniqueID' else q for q in ob[2]]
        names.append(obj_name if num == 0 else f'{obj_name}_{num - 1}')
    top_number[obj_name] = len(objs)
    assert npc_row in NPC_ROWS, npc_row
    for n in (new_unit, obj_name, npc_row): z.nb.add(n)
    ids = used_ids | {q[3][2] for u in units for q in u[2] if q[1] == 'UniqueID' and q[3]}
    h = zlib.crc32(b'AC8SurvivalMode:' + new_unit.encode())
    while struct.pack('<I', h) in ids: h = (h + 1) & 0xffffffff
    new[2][:] = [(q[0], q[1], False, ('name', new_unit, 0)) if q[1] == 'Name' else
                 (q[0], q[1], False, ('raw', q[3][1], struct.pack('<I', h))) if q[1] == 'UniqueID' else q for q in new[2]]
    units.append(new)
    return names


def split_units(units, used_ids, z, top_number):
    """Comona Defense (survival_events.SHUTTLE_*): the shuttle gets a unit of its own, spawned every special, and the
    pad's invincible dummies one of theirs (PAD_DUMMY_UNIT, spawned once a run: a unit with anything alive can't be
    spawned again), so Mission 22's pad unit keeps only what can be destroyed (AA guns, SAMs, tower: removed after
    each special). Airfield defences (survival_events.DEFENCES): each of Mission 22's airport AA guns and SAM sites
    becomes a one-object unit the shop can build."""
    move_object(units, used_ids, z, survival_events.PAD_UNIT, survival_events.SHUTTLE, survival_events.SHUTTLE_UNIT,
                survival_events.SHUTTLE_NPC_ROW)
    # Mission 22's shuttle is an attack-target exception (bIsAttackTargetsException): no AI ever aims at it (its
    # "attacks" are scripted near misses), so Survival's strike flights circled it without a shot (test of 2026-10-23:
    # 0 hits in 150 s, 1.4-3.3 km out). Survival's copy can be attacked.
    clear_flags([u for u in units if [p for p in u[2] if p[1] == 'Name'][0][3][1] == survival_events.SHUTTLE_UNIT][0],
                ('bIsAttackTargetsException',))
    left = move_object(units, used_ids, z, survival_events.PAD_UNIT, survival_events.PAD_DUMMIES, survival_events.PAD_DUMMY_UNIT)
    print(f'  shuttle: {survival_events.SHUTTLE} in {survival_events.SHUTTLE_UNIT} (NPC row {survival_events.SHUTTLE_NPC_ROW}), '
          f'{len(survival_events.PAD_DUMMIES)} dummies in {survival_events.PAD_DUMMY_UNIT}; {survival_events.PAD_UNIT} keeps {left} objects')
    for new_unit, obj, mrow in survival_events.DEFENCES:
        move_object(units, used_ids, z, survival_events.DEFENCE_SOURCE, obj, new_unit, survival_events.DEFENCE_ROWS[mrow][0])
    print(f'  airfield defences: {len(survival_events.DEFENCES)} units from {survival_events.DEFENCE_SOURCE}')
    # The Anomaly (survival_events.ANOMALY_*): MINDRIPPER alone, and its guards
    # (user, 2026-10-22: "make mindripper an F-4": its NPC row is the F-4E one in the world data too, not only at spawn)
    (lead, _, _), (wing, _, _) = ace_rows('anomaly', 'f04e')
    ace = copy_unit(units, used_ids, z, survival_events.ANOMALY_SOURCE, survival_events.ANOMALY_UNIT, 1, top_number,
                    'SV_Obj_Mindripper', lead + '_sv')
    guards = copy_unit(units, used_ids, z, survival_events.ANOMALY_SOURCE, survival_events.ANOMALY_GUARD_UNIT,
                       survival_events.ANOMALY_GUARDS, top_number, 'SV_Obj_AnomalyGuard', wing + '_sv')
    survival_events.ANOMALY_OBJ = ace[0]
    print(f'  anomaly: {ace[0]} in {survival_events.ANOMALY_UNIT}, guards {guards} in {survival_events.ANOMALY_GUARD_UNIT}')


def build_wd_global():
    """Mission 22's global world data (its units, AI paths, marks, volumes and the combat zone the minimap frames
    itself on - test 6), with no unit spawning at mission start: Survival's events spawn every unit they use."""
    old, new = M22 + 'WD_Mission022_global', MI + 'WD_SurvivalMode_global'
    z = ZenPkg(stock(old))
    rename_package(z, old, new)               # also renames every WorldDataName value (same FName)
    i = z.export_index(new.rsplit('/', 1)[1])
    v, rest = props_of(z, i, 'LiveWorldData')
    units = [p for p in v[2] if p[1] == 'UnitDescList'][0][3][1]
    # An absent property means the class default, and bIsSpawnFromStart defaults to true (test M2-1: removing it
    # spawned all 71 units, 135 aircraft). Mission 22's own reinforcements carry it as an explicit zero: do the same.
    idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'bIsSpawnFromStart'][0]
    sp_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'SpawnPoint'][0]
    r_idx = [k for k, (n, t) in uprop.U.schema('LiveUnitDesc').items() if n == 'RadiusInMeter'][0]
    POOL_UNITS = set(survival_events.POOL)
    turned_off = 0
    behaviours, sized = {}, {}
    used_ids = {q[3][2] for u in units for p in u[2] if p[1] == 'AIObjectDescList' and p[3]
                for ob in p[3][1] for q in ob[2] if q[1] == 'UniqueID' and q[3]}
    top_number = {}                            # AI object name -> highest number used anywhere in the world data
    for u in units:
        for p in u[2]:
            if p[1] == 'AIObjectDescList' and p[3]:
                for ob in p[3][1]:
                    for q in ob[2]:
                        if q[1] == 'Name' and q[3]: top_number[q[3][1]] = max(top_number.get(q[3][1], 0), q[3][2])
    for u in units:
        name = [p for p in u[2] if p[1] == 'Name'][0][3][1]
        keep = name in survival_events.KEEP_AT_START
        point = survival_events.KEEP_AT_START.get(name)
        cur = [p for p in u[2] if p[1] == 'bIsSpawnFromStart']
        if not keep and not (cur and cur[0][2]): turned_off += 1
        on = (idx, 'bIsSpawnFromStart', False, ('raw', 'Bool', b'\x01')) if keep else (idx, 'bIsSpawnFromStart', True, None)
        rest_props = [p for p in u[2] if p[1] != 'bIsSpawnFromStart' and not (point and p[1] == 'SpawnPoint')]
        if point:
            # the unit's SpawnPoint alone left the anchor at the map origin (probe test 7): its AI object has a
            # SpawnPoint of its own, which is where it actually stands, so both get the point
            rest_props.append((sp_idx, 'SpawnPoint', False, ('native', 'Vector', struct.pack('<3d', *point))))
            for k, p in enumerate(rest_props):
                if p[1] == 'AIObjectDescList':
                    for obj in p[3][1]:
                        obj[2][:] = [(q[0], q[1], False, ('native', 'Vector', struct.pack('<3d', *point)))
                                     if q[1] == 'SpawnPoint' else q for q in obj[2]]
        radius = (survival_events.AREA_RADIUS_M if name in POOL_UNITS else       # the pool: an area over the whole zone
                  survival_events.HEAVY_AREA_RADIUS_M if name in survival_events.HEAVY_BOMBERS else None)
        if radius:
            rest_props = [p for p in rest_props if p[1] != 'RadiusInMeter'] + [
                (r_idx, 'RadiusInMeter', False, ('raw', 'Float', struct.pack('<f', radius)))]
        row = survival_events.behaviour_row(name)       # the flight's behaviour (survival_events: built at level load)
        if row:
            assert row in NPC_ROWS, (name, row)
            z.nb.add(row)
            for p in rest_props:
                if p[1] == 'AIObjectDescList':
                    for obj in p[3][1]:
                        assert any(q[1] == 'MissionNpcID' for q in obj[2]), name
                        obj[2][:] = [(q[0], q[1], False, ('name', row, 0)) if q[1] == 'MissionNpcID' else q for q in obj[2]]
            behaviours[row] = behaviours.get(row, 0) + 1
        size = survival_events.flight_size(name)
        if size:                               # Survival's flights: 2, 4 or 6 aircraft in a standard formation
            for p in rest_props:
                if p[1] == 'AIObjectDescList':
                    objs = p[3][1]
                    assert any(q[1] == 'bGroupLead' and q[3] == ('raw', 'Bool', b'\x01') for q in objs[0][2]), name
                    set_flight_size(objs, size, name, unit_point(u), used_ids, top_number)
                    sized[size] = sized.get(size, 0) + 1
        u[2][:] = sorted(rest_props + [on], key=lambda p: p[0])
    split_units(units, used_ids, z, top_number)
    ally_units(units, used_ids, z, top_number, v)
    lcac_units(units, used_ids, z, top_number, v)
    ladon_units(units, used_ids, z, top_number, v)
    alcn_units(units, used_ids, z, top_number, v)
    names = {[p for p in u[2] if p[1] == 'Name'][0][3][1] for u in units}
    assert set(survival_events.KEEP_AT_START) <= names, set(survival_events.KEEP_AT_START) - names
    assert set(survival_events.BOMBERS) <= names, set(survival_events.BOMBERS) - names
    assert any(p[1] == 'CombatZoneDescList' for p in v[2])
    # every object reference in the world data inside this package (an export index from another mission's desc crashes
    # the game's loader when the level loads: "Bad export index")
    def refs(x, out):
        if isinstance(x, tuple):
            if x and x[0] == 'obj' and isinstance(x[1], int) and x[1] > len(z.exports): out.append(x)
            for y in x: refs(y, out)
        elif isinstance(x, list):
            for y in x: refs(y, out)
        return out
    bad = refs(v, [])
    assert not bad, f'object references past the {len(z.exports)} exports: {bad[:5]}'
    z.payloads[i] = bytearray(write_props(z, v) + rest)
    chk, _ = props_of(z, i, 'LiveWorldData'); assert chk == v
    print(f'  {len(units)} units, spawn-at-start turned off on {turned_off}; behaviour rows (flights): {behaviours}; '
          f'flight sizes: {sized}')
    retarget_import(z, NPC_TABLE_STOCK, NPC_TABLE)        # Survival's own NPC mission table (build_npc_table)
    save(z, new)


def build_ef():
    """Mission 22's event flag asset with every flag removed, then Survival's int flags (value 0) added."""
    old = M22 + 'EF_Mission022_global'
    z = ZenPkg(stock(old))
    rename_package(z, old, MI + 'EF_SurvivalMode_global')
    v, rest = props_of(z, 0, 'LiveEventFlagAsset')
    def clear(s):
        for k, (pi, pn, zero, val) in enumerate(s[2]):
            if val and val[0] == 'map': s[2][k] = (pi, pn, False, ('map', 0, []))
            elif val and val[0] == 'struct': clear(val)
    clear(v)
    fd = [p for p in v[2] if p[1] == 'FlagData'][0][3]
    ints = [p for p in fd[2] if p[1] == 'IntegerFiled'][0][3]
    for name in survival_events.INT_FLAGS:
        # The event records name flags by string, which the game turns into an FName that splits a numeric tail
        # ("SV_Up_19" -> SV_Up, number 20). Keys must be stored the same way or the flag never matches: test of
        # 2026-10-21 05:07, flights 10-24 were never flagged up, so they were never chased.
        key = survival_events.fname(name)
        z.nb.add(key[1])
        ints[2].append((key, ('struct', 'LiveEventFlagType_Integer', [(0, 'Value', True, None)])))
    z.payloads[0] = bytearray(write_props(z, v) + rest)
    chk, _ = props_of(z, 0, 'LiveEventFlagAsset'); assert chk == v
    save(z, MI + 'EF_SurvivalMode_global')


def empty_ep(z, new_path):
    """Keep the EP's properties (world data, flag asset, package hash), remove every trigger and exec."""
    p = bytes(z.payloads[0])
    v, rest = props_of(z, 0, 'LiveEventPackage')
    props = v[2]
    for k, (pi, pn, zero, val) in enumerate(props):
        if pn == 'PackageHash': props[k] = (pi, pn, False, ('raw', 'Int', struct.pack('<I', package_hash(new_path))))
    head = write_props(z, v)
    # after the properties: u32 (always 0 so far), u32 trigger count, triggers, u32 exec count, execs
    assert rest[:4] == b'\0\0\0\0', rest[:4]
    z.payloads[0] = bytearray(head + b'\0\0\0\0' + struct.pack('<II', 0, 0))


def build_ep(part, ef=False):
    """Mission 22's event package for `part` (global / phase01 / phase02) with every trigger and exec removed;
    the global one then gets Survival's event graph (tools/survival_events.py)."""
    old, new = M22 + 'EP_Mission022_' + part, MI + 'EP_SurvivalMode_' + part
    z = ZenPkg(stock(old))
    rename_package(z, old, new)
    retarget_import(z, M22 + 'WD_Mission022_' + part, MI + 'WD_SurvivalMode_' + part)
    if ef:
        retarget_import(z, M22 + 'EF_Mission022_global', MI + 'EF_SurvivalMode_global')
    empty_ep(z, new)
    if part == 'global':
        g = survival_events.build_events(stock(old))
        # exec classes Mission 22's package doesn't import (Graph.foreign_template): the same imports, in the same order
        assert len(z.imports) + len(g.added_imports) == len(g.z.imports), (len(z.imports), len(g.added_imports))
        z.imports += g.added_imports
        head = bytes(z.payloads[0])[:-12]         # empty_ep left: properties + u32 0 + u32 0 + u32 0
        z.payloads[0] = bytearray(survival_events.write_records(g, z, head))
        _, _, _, T, E, offs = ep_dump.load_bytes(z)
        assert len(T) == len(g.trig) and len(E) == len(g.ex) and offs[3] == offs[4], (len(T), len(E), offs)
        declared = {survival_events.fname(n) for n in survival_events.INT_FLAGS}   # build_ef's keys
        assert {survival_events.fname(n) for n in g.flags} <= declared, g.flags - set(survival_events.INT_FLAGS)
        print(f'  events: {len(T)} triggers, {len(E)} execs')
    save(z, new)


# ---------------------------------------------------------------- menu + mission rows
# Survival's rows live in tables of its own. The Lua runtime copies them into the game's DT_LiveMissionTable and
# DT_LiveMenuMainTopCommands at run time (AddRow), so no stock or other-mod table is overridden.
DATA = MOD + '/Data/'
MISSION_ID = 9101          # must match SURVIVAL_MISSION_ID in runtime/survival_rt.c
LEVEL_ID = 70              # ELiveLevelID Test02: no stock row uses it
MENU_ARGS = 'SurvivalMode' # must match SURVIVAL_ARGS in runtime/survival_rt.c
import dtx


def build_rows_table(stock_path, new_path, row_struct, src_row, new_row, edit):
    """Copy a stock DataTable package, keep one row (renamed new_row) and let edit() change its properties."""
    z = ZenPkg(stock(stock_path))
    rename_package(z, stock_path, new_path)
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, row_struct)
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    row = rows[(src_row, 0)]
    edit(row[2])
    for n in names_in(row) + [new_row]:
        z.nb.add(n)
    dt['rows'] = [((new_row, 0), row)]
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, row_struct)
    assert chk['rows'] == dt['rows']
    save(z, new_path)


# Radio (tools/re/MUSIC_RADIO_CAMERA.md C): the level's radio table (ChronicleWorldSettings.RadioSettings, a hard
# import) is Survival's copy of Mission 22's, with only these changes (the voices are in the global AKB_Voice bank, the
# speakers in the global DT_SpeakerTable):
RADIO_STOCK = '/Game/Datatables/Radio/DT_Rdo_ST_ms022'
RADIO = DATA + 'DT_SV_Radio'
# MOONCHILD's takeoff (01_Wave1_Ally_Take_Off): Mission 25 part 2's Savian mercenary leader, "Our economy relies on mercs
# like us." (v2501_0054), in place of "This is Singleton Flight. Providing support." (user, 2026-10-23)
RADIO_REPLACE = {('01_Wave1_Ally_Take_Off', 'v2216_0007'): ('v2501_0054', 'ms25_Savia_Mercenary_Leader')}
# The shuttle round keeps Nagase's lines and drops the Professor's (Baxter) and Tasha's (user, 2026-10-23); groups left
# empty aren't played (survival_events.SHUTTLE_RADIO)
RADIO_DROP_SPEAKERS = ('LIVE_Baxter', 'LIVE_Tasha')
RADIO_DROP_IN = ('01_Countdown_intermission_1st', '01_Countdown_mainEngine', '01_All_Wave_Hit_Shuttle_First')
# and MOONCHILD's takeoff is the mercenary's line alone (user, 2026-10-23): Singleton's "We're joining the fight in
# aircraft we took back from Sotoa." and Tasha's "Okay!" go
RADIO_DROP_LINES = {('01_Wave1_Ally_Take_Off', 'v2216_0002'), ('01_Wave1_Ally_Take_Off', 'v0003_1682')}
# Speakers aren't the level's to change: the game reads them from the game instance's own DT_SpeakerTable (a copy for
# the level, 2026-10-23, changed nothing), so Scripts/main.lua switches the Savian mercenary leader to ally colours at
# run time (CFG.allies.ally_speakers).


def build_radio():
    z = ZenPkg(stock(RADIO_STOCK))
    rename_package(z, RADIO_STOCK, RADIO)
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveRadioTable')
    assert o == len(p), (o, len(p))
    def field(row, n): return [q for q in row[2] if q[1] == n][0][3]
    def full(v): return v[1] if v[0] != 'name' or v[2] == 0 else f'{v[1]}_{v[2] - 1}'   # 'v0003_1682' is ('v0003', 1683)
    def setf(row, n, v): row[2][:] = [(q[0], q[1], q[2], v) if q[1] == n else q for q in row[2]]
    keep, done, dropped = [], set(), 0
    for k, row in dt['rows']:
        group, text, speaker = full(field(row, 'RadioGroupID')), full(field(row, 'TextID')), field(row, 'SpeakerID')[1]
        if (group in RADIO_DROP_IN and speaker in RADIO_DROP_SPEAKERS) or (group, text) in RADIO_DROP_LINES:
            dropped += 1
            continue
        new = RADIO_REPLACE.get((group, text))
        if new:
            setf(row, 'TextID', survival_events.fname(new[0]))
            setf(row, 'SpeakerID', ('str', new[1]))
            z.nb.add(new[0]); z.nb.add(new[1])
            done.add((group, text))
        keep.append((k, row))
    assert done == set(RADIO_REPLACE), done
    assert dropped == 7, dropped        # Baxter x3 + Tasha x1 in the countdown, Baxter on the first hit, 2 at takeoff
    dt['rows'] = keep
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveRadioTable')
    assert chk['rows'] == dt['rows']
    save(z, RADIO)
    print(f'  radio: {len(keep)} rows ({dropped} dropped, {len(done)} replaced)')


# The airfield shop (Milestone 4): rows for the landing menu (the in-game hangar's command list, after its Yes / No).
# Scripts/main.lua adds them to the game's table at run time while Survival's level is loaded and removes them after;
# their texts (SV_Shop_*) are set by Lua through the native text hook (SV_SetText), and picking one is caught by the
# native landing-menu hook (StringArgs SV_Buy_<item>), so the stock page never sees them.
SHOP_TABLE_STOCK = '/Game/Datatables/UI/Menu/IngameMenu/IngameHangar/DT_LiveMenuIngameHangarCommands'
SHOP_TABLE = DATA + 'DT_SV_ShopRows'
SHOP_ITEMS = ['Missiles', 'Special', 'Flares', 'Airfield']          # Scripts/main.lua CFG.shop.items, same names
# The STORE (user, 2026-10-23: "a special tab in there for the store items"; tools/re/AIRFIELD_SHOP_UI.md): the landing
# menu's page list is the in-game menu table, and a landing row whose StringArgs is a number opens that menu. Survival
# adds pages of its own (DT_SV_MenuClassRows -> DT_IngameMenuSettingData at the main menu: indexes 20, 21, 22),
# copies of the landing page (WBP_SV_Store*, with their own settings asset and command table), and one landing row,
# STORE ("20"). Lua checks the game's menu list for them; without them it falls back to the 4 SHOP_ITEMS rows.
# A page lists 6 rows at most, so the pages link in a ring (SUPPLIES > AIRFIELD > DOCKS > SUPPLIES; user, 2026-10-23:
# "add a Docks Page too"), each with TAKE OFF.
STORE_PAGES = [  # (menu id, page, title key, rows: item name or (row name, title key, StringArgs))
    ('SV_Store', 'Store', 'SV_Store_Title',
     ['Missiles', 'Special', 'Flares', 'RepairAircraft', ('SVStoreToAirfield', 'SV_Store_ToAirfield', '21'), 'takeoff']),
    ('SV_StoreAirfield', 'StoreAirfield', 'SV_Store_TitleAirfield',
     ['RepairAirfield', 'AAGun', 'SAM', 'Moonchild', ('SVStoreToDocks', 'SV_Store_ToDocks', '22'), 'takeoff']),
    ('SV_StoreDocks', 'StoreDocks', 'SV_Store_TitleDocks',
     ['ShipAegis', ('SVStoreToSupplies', 'SV_Store_ToSupplies', '20'), 'takeoff']),
]
STORE_ROW = ('SVShopStore', 'SV_Shop_Store', '20')      # the landing page's row that opens the first page
LANDING_PAGE = '/Game/Blueprints/UI/Menu/Ingame/IngameHangar/WBP_Menu_IngameHangar_Confirmation_000'
LANDING_SETTINGS = '/Game/Datatables/UI/Menu/IngameMenu/IngameHangar/DA_LiveMenuIngameHangarSettings'
MENU_TABLE = '/Game/Datatables/UI/Menu/IngameMenu/DT_IngameMenuSettingData'
UI = MOD + '/UI/'


def command_rows(z, dt, items, extra=()):
    """LiveMenuCommandsDataTable rows: an item name -> SV_Buy_<item> with SV_Shop_<item> texts; 'takeoff' -> the stock
    take-off row; (row name, title key, StringArgs) -> a page-change row. All copies of the stock take-off row."""
    yes = dict(dt['rows'])[('1', 0)]
    assert dict((q[1], q[3]) for q in yes[2])['StringArgs'] == s('-1')    # the take-off row
    rows = []
    for item in list(items) + list(extra):
        row = copy.deepcopy(yes)
        if item == 'takeoff':
            name = 'SVTakeOff'
        elif isinstance(item, tuple):
            name, key, args = item
            setv(row[2], 'TitleTextID', s(key))
            setv(row[2], 'HelpTextID', s(key + '_Help'))
            setv(row[2], 'StringArgs', s(args))
        else:
            name = 'SVShop' + item
            setv(row[2], 'TitleTextID', s('SV_Shop_' + item))
            setv(row[2], 'HelpTextID', s('SV_Shop_' + item + '_Help'))
            setv(row[2], 'StringArgs', s('SV_Buy_' + item))
        z.nb.add(name)
        rows.append(((name, 0), row))
    return rows


def commands_table(new_path, items, extra=()):
    z = ZenPkg(stock(SHOP_TABLE_STOCK))
    rename_package(z, SHOP_TABLE_STOCK, new_path)
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveMenuCommandsDataTable')
    assert o == len(p), (o, len(p))
    dt['rows'] = command_rows(z, dt, items, extra)
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveMenuCommandsDataTable')
    assert chk['rows'] == dt['rows']
    save(z, new_path)


def build_shop_rows():
    # the landing page's rows: the fallback items and STORE (Lua adds one or the other)
    commands_table(SHOP_TABLE, SHOP_ITEMS, [STORE_ROW])
    menu_rows = []
    for menu_id, page, title, items in STORE_PAGES:
        table, settings, widget = DATA + 'DT_SV_' + page + 'Commands', UI + 'DA_SV_' + page + 'Settings', UI + 'WBP_SV_' + page
        commands_table(table, [i for i in items if not isinstance(i, tuple) and i != 'takeoff'],
                       [i for i in items if isinstance(i, tuple)] + ['takeoff'])
        # its settings asset: the landing page's, pointing at its own command table
        z = ZenPkg(stock(LANDING_SETTINGS))
        rename_package(z, LANDING_SETTINGS, settings)
        old_t = SHOP_TABLE_STOCK
        z.rename(old_t, table); z.rename(old_t.rsplit('/', 1)[1], table.rsplit('/', 1)[1])
        assert table in z.names and old_t not in z.names
        save(z, settings)
        # the page: the landing page's widget blueprint under Survival's path (its objects keep their names: a zen
        # package's export hashes are package-relative), its settings import retargeted, its title key renamed
        z = ZenPkg(stock(LANDING_PAGE))
        z.rename(LANDING_PAGE, widget)
        retarget_import(z, LANDING_SETTINGS, settings)
        z.rename('CampaignReturnTitle_Name_Resupply', title)
        assert widget in z.names and LANDING_PAGE not in z.names
        save(z, widget)
        menu_rows.append((menu_id, widget))
    # the menu-class rows: in-game menus Survival's landing rows open by number
    z = ZenPkg(stock(MENU_TABLE))
    rename_package(z, MENU_TABLE, DATA + 'DT_SV_MenuClassRows')
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveMenuClassTable')
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    hangar = [r for k, r in dt['rows'] if dict((q[1], q[3]) for q in r[2])['MenuID'] == ('name', 'IngameHagarMenu', 0)][0]
    out = []
    cls = LANDING_PAGE.rsplit('/', 1)[1] + '_C'
    mc = {n: k for k, (n, t) in uprop.U.schema('LiveMenuClassTable').items()}      # (setv knows other schemas)
    for menu_id, widget in menu_rows:
        row = copy.deepcopy(hangar)
        set_prop(row[2], mc['MenuID'], 'MenuID', ('name', menu_id, 0))
        ref = dict((q[1], q[3]) for q in row[2])['MenuWidgetReference']
        assert ref[0] == 'soft' and ref[1][1] == LANDING_PAGE and ref[2][1] == cls, ref
        set_prop(row[2], mc['MenuWidgetReference'], 'MenuWidgetReference', ('soft', ('name', widget, 0), ('name', cls, 0), ref[3]))
        name = menu_id.replace('_', '')
        for n in (menu_id, widget, name): z.nb.add(n)
        out.append(((name, 0), row))
    dt['rows'] = out
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveMenuClassTable')
    assert chk['rows'] == dt['rows']
    save(z, DATA + 'DT_SV_MenuClassRows')


def names_in(v):
    """Every FName string a property value uses."""
    out = []
    if isinstance(v, tuple):
        if v and v[0] == 'name': out.append(v[1])
        for x in v: out += names_in(x)
    elif isinstance(v, list):
        for x in v: out += names_in(x)
    return out


def setv(props, name, value):
    """Set (or add) a property of a row by name."""
    sc = uprop.U.schema('LiveLevelTable') if any(p[1] == 'MissionID' for p in props) else uprop.U.schema('LiveMenuCommandsDataTable')
    idx = [i for i, (n, t) in sc.items() if n == name][0]
    set_prop(props, idx, name, value)


def s(text): return ('str', text)


HANGAR_LEVEL_ID = 0x0F    # must match HANGAR_MENU_ID in runtime/survival_rt.c: the hangar the runtime travels to


def check_hangar(props):
    """The hangar level the runtime travels to is 10 + TravelHangarMap; the row's hangar lighting and sublevels belong
    to that hangar. If they don't match, the hangar loads without light (test 5)."""
    th = [p for p in props if p[1] == 'TravelHangarMap'][0][3][2][2][0]
    subs = [p for p in props if p[1] == 'HangarSubLevelList'][0][3][1]
    assert 10 + th == HANGAR_LEVEL_ID, f'row travels to hangar level {10 + th}, runtime to {HANGAR_LEVEL_ID}'
    want = f'/Game/Maps/Hangar/Hangar{HANGAR_LEVEL_ID - 11:03d}/'
    assert all(sl[1][1].startswith(want) for sl in subs), [sl[1][1] for sl in subs]


def edit_mission_row(props):
    check_hangar(props)
    setv(props, 'MissionID', ('raw', 'Int', struct.pack('<i', MISSION_ID)))
    setv(props, 'LevelId', ('enum', 'ELiveLevelID', ('raw', 'UInt32', struct.pack('<I', LEVEL_ID))))
    setv(props, 'LevelStringID', s('Survival Mode'))
    drop_prop(props, [p for p in props if p[1] == 'ActivityID'][0][0])          # no platform activity
    setv(props, 'MapReference', ('soft', ('name', PL, 0), ('name', PL.rsplit('/', 1)[1], 0), ''))
    setv(props, 'StartupSortNumber', ('raw', 'Int', struct.pack('<i', 91)))
    for k, v in (('MissionNameID', 'SV_Mission_Name'), ('MissionSubtitleTextID', 'SV_Mission_Subtitle'),
                 ('MissionNumberTextID', 'SV_Mission_Number'), ('MissionNumberOnlyTextID', 'SV_Mission_Number'),
                 ('MapNameID', 'SV_Mission_Location'), ('MissionClearConditionID', 'SV_Mission_Objective'),
                 ('MissionOperationTextID', 'SV_Mission_Name'), ('MissionObjectiveTextID', 'SV_Mission_Briefing')):
        setv(props, k, s(v))
    setv(props, 'MissionClearConditionIDs', ('arr', [s('SV_Mission_Objective'), s('SV_Mission_Objective')]))
    setv(props, 'CheckpointTextIndices', ('arr', []))                         # Mission 22's checkpoints
    # No wingmen in the hangar (Survival flies none). Mission 22's row offers Tasha and Coster with the save's plane and
    # skin; on a friend's save that skin list was empty and the hangar's "Wingman1 Info" panel crashed reading it
    # (minidump of 2026-10-22: 0x1479a4153, a null read of entry n-1). WingmanType None x3, as Mission 015's row.
    for k in ('HangarSelectWingman1st', 'HangarSelectWingman2nd', 'HangarSelectWingman3rd'):
        st = [p for p in props if p[1] == k][0][3]
        st[2][:] = [(q[0], q[1], True, None) if q[1] == 'WingmanType' else q for q in st[2]]


def edit_menu_row(props):
    setv(props, 'CommandID', ('name', 'Main_Top_SurvivalMode', 0))
    setv(props, 'TitleTextID', s('SV_Menu_Title'))
    setv(props, 'HelpTextID', s('SV_Menu_Help'))
    setv(props, 'MenuID', s('CampaignFreeMissionDifficulty'))   # the game's own free-mission difficulty page
    setv(props, 'StringArgs', s(MENU_ARGS))
    for k in ('ParentNewFlagTrigger', 'RefFeature'):
        hit = [p for p in props if p[1] == k]
        if hit: drop_prop(props, hit[0][0])


def edit_shuttle_npc(props):
    """The shuttle's DT_NPC row (Mission 22's OP0057_sstb_01) under Survival's name key: the text hook shows
    main.lua CFG.specials.shuttle.name for it (user, 2026-10-22: "EMBDIR Shuttle - CORRIS", not Spruce Goose)."""
    assert dict((p[1], p[3]) for p in props)['GameObjectDisplayName02'] == s('ContainerAircraft_Name_SpruceGoose')
    idx = [p[0] for p in props if p[1] == 'GameObjectDisplayName02'][0]
    set_prop(props, idx, 'GameObjectDisplayName02', s('SV_Shuttle_Name'))


# Named aces and squadrons of skill tiers 6-10 (main.lua CFG.aces; user, 2026-10-22: "build it with this line up, but
# custom names"). For each tier and airframe key: a lead row (a flight's first aircraft: the ace, under its own name) and
# a wing row (the rest: the squadron's name), DT_NPC copies of the stock rows below (their skins come along) with
# Survival's text key as callsign (GameObjectDisplayName02, as the shuttle's): main.lua sets the texts from CFG.aces
# through the text hook, so players rename them in survival.ini. Keep in step with main.lua ACE_ROSTER.
ACES = [  # (tier, key, lead DT_NPC row, wing DT_NPC row)
    ('mercenary', 'f15c',    'OP1004_f15c_Shark_01',   'OP1004_f15c_Shark_02'),
    ('mercenary', 'su35',    'OP1028_su35_Ventus_01',  'OP1028_su35_Ventus_02'),
    ('mercenary', 'typhoon', 'OP1011_typn_01',         'OP1011_typn_01'),
    ('legend',    'su47',    'OP1026_su47_01',         'OP1026_su47_01'),
    ('legend',    'rafale',  'OP1014_rflm_Savia_01',   'OP1014_rflm_Savia_01'),
    ('demon',     'f22a',    'OP1005_f22a_01',         'OP1005_f22a_01'),
    ('demon',     'su57',    'OP1021_su57_02',         'OP1021_su57_02'),
    ('phantom',   'su57',    'OP1021_su57_Shadow_24',  'OP1021_su57_Shadow_25'),
    ('phantom',   'typhoon', 'OP1011_typn_Shadow_33',  'OP1011_typn_Shadow_32'),
    ('phantom',   'su47',    'OP1026_su47_Shadow_144', 'OP1026_su47_Shadow_145'),
    ('reaper',    'su57',    'OP1021_su57_Named',      'OP1021_su57_Shadow_26'),
    ('reaper',    'f22a',    'OP1005_f22a_Named',      'OP1005_f22a_Shadow_99'),
    ('reaper',    'typhoon', 'OP1011_typn_Named',      'OP1011_typn_Shadow_37'),
    ('reaper',    'rafale',  'OP1014_rflm_Named',      'OP1011_typn_Shadow_39'),
    ('reaper',    'adfx02',  'OP1021_su57_Named',      'OP1021_su57_Named'),        # model: ACE_MODELS
    # the Anomaly's MINDRIPPER (lead) and its guards (wing): main.lua CFG.specials.anomaly names them
    ('anomaly',   'f04e',    'OP1003_f04e_Named',      'OP1003_f04e_Named'),
]
# Airframes only Online Mode has (user, 2026-10-22: "ADFX-02 appears in the Online Mode"): their model rows are in
# DT_NPC_Model_ON, not the campaign's DT_NPC_Model, so DT_SV_ModelRows carries copies (GameObjectId 1 like every
# campaign model, Survival's text key for the aircraft name) that main.lua adds to DT_NPC_Model at the main menu, and
# the ace rows above (copies of a campaign row, for its fire-control and weapon ids) are given that model, no skin.
# Their blueprints (/Game/OnlineMode/Blueprint/AI/Actors/Plane/...) derive from the campaign's BP_AIPlane_Pawn.
# (tier, key) -> (DT_SV_ModelRows row, DT_NPC_Model_ON row, text key). Keep in step with main.lua ACE.models.
ACE_MODELS = {
    ('reaper', 'adfx02'): ('SV_Model_adfx', 'OP1038_adfx02_L001', 'SV_Ac_adfx'),
}
MODEL_ON = '/Game/OnlineMode/DataTables/AI/NPC/DT_NPC_Model_ON'


def ace_rows(tier, key):
    """(lead, wing), each (DT_SV_NpcMission row, DT_NPC row, text key); no numeric tails (hard rule 17)."""
    b = f'{tier}_{key}'
    return ((f'sv_ace_{b}_l', f'SV_Ace_{b}_L', f'SV_Ace_{b}'), (f'sv_ace_{b}_w', f'SV_Ace_{b}_W', f'SV_Sqn_{tier}'))


def build_npc_rows():
    """DT_SV_NpcRows: the shuttle's row and the aces' rows, which main.lua adds to DT_NPC at the main menu (before the
    level loads: the spawner reads them then)."""
    path = '/Game/Datatables/AI/NPC/DT_NPC'
    z = ZenPkg(stock(path))
    rename_package(z, path, DATA + 'DT_SV_NpcRows')
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveNpcDataTable')
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    name_idx = [k for k, (n, t) in uprop.U.schema('LiveNpcDataTable').items() if n == 'GameObjectDisplayName02'][0]
    shuttle = copy.deepcopy(rows[('OP0057_sstb_01', 0)])
    edit_shuttle_npc(shuttle[2])
    out = [((survival_events.SHUTTLE_NPC, 0), shuttle)]
    schema = uprop.U.schema('LiveNpcDataTable')
    model_idx = [k for k, (n, t) in schema.items() if n == 'ModelId'][0]
    skin_idx = [k for k, (n, t) in schema.items() if n == 'AirframeSkinId'][0]
    for tier, key, lead, wing in ACES:
        for src, (_, npc, text) in zip((lead, wing), ace_rows(tier, key)):
            f = survival_events.fname(src)
            row = copy.deepcopy(rows[(f[1], f[2])])
            set_prop(row[2], name_idx, 'GameObjectDisplayName02', s(text))
            if (tier, key) in ACE_MODELS:
                set_prop(row[2], model_idx, 'ModelId', ('name', ACE_MODELS[(tier, key)][0], 0))
                drop_prop(row[2], skin_idx)                               # the model's own look
            out.append(((npc, 0), row))
    # the STORE's allies (survival_events.ALLY_*): MOONCHILD (an F-22 under its squadron's name key), each ship's hull
    # (under its name key) and turrets (as they are: main.lua gives every one of them fire control of its own)
    m22 = mission_npc_ids()
    allies = [(survival_events.ALLY_AIR_SOURCE_NPC, survival_events.ALLY_AIR_NPC, survival_events.ALLY_AIR_NAME_KEY)]
    allies += [(m22[src], npc, None) for src, (_, npc) in survival_events.DEFENCE_ROWS.items()]   # the airfield's defences
    for key, _, hull, _ in survival_events.ALLY_SHIPS:
        _, npc, text = survival_events.ally_ship_rows(key)
        allies.append((m22[hull], npc, text))
        allies += [(m22[t], survival_events.ally_turret_rows(t)[1], None) for t in survival_events.ALLY_TURRETS[key]]
    for src, npc, text in allies:
        f = survival_events.fname(src)
        row = copy.deepcopy(rows[(f[1], f[2])])
        if text: set_prop(row[2], name_idx, 'GameObjectDisplayName02', s(text))
        out.append(((npc, 0), row))
    # the Ladons (survival_events.LADON*): the stock Ladon under each one's name key (main.lua: name, health, speed)
    for L in survival_events.ladons():
        row = copy.deepcopy(rows[(survival_events.LADON_NPC_SOURCE, 0)])
        set_prop(row[2], name_idx, 'GameObjectDisplayName02', s(L['name_key']))
        comps = [q for q in row[2] if q[1] == 'ChildNPCComponentNames'][0][3][1]   # its CIWS: the pulse cannon pods
        pulse = survival_events.fname(survival_events.LADON_PULSE_NPC)
        row[2][:] = [(q[0], q[1], q[2], ('arr', [pulse if (c[1] in survival_events.LADON_CIWS and c[2] == 0) else k
                                                  for c, k in zip(comps, q[3][1])])) if q[1] == 'ChildNPCId' else q for q in row[2]]
        assert sum(1 for k in [q for q in row[2] if q[1] == 'ChildNPCId'][0][3][1] if k == pulse) == len(survival_events.LADON_CIWS)
        out.append(((L['npc'], 0), row))
    for k, row in out:
        for n in names_in(row) + [k[0]]: z.nb.add(n)
    dt['rows'] = out
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveNpcDataTable')
    assert chk['rows'] == dt['rows']
    print(f'  DT_SV_NpcRows: {len(out)} rows ({len(ACES)} aces and their wings, {len(allies)} allies)')
    save(z, DATA + 'DT_SV_NpcRows')


def mission_npc_ids():
    """Mission 22's NPC mission rows -> the DT_NPC row each names (NpcId), as plain strings."""
    z = ZenPkg(stock(NPC_TABLE_STOCK))
    dt, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveNpcMissionDataTable')
    plain = lambda n, k: n if k == 0 else f'{n}_{k - 1}'
    return {plain(*k): plain(*dict((q[1], q[3]) for q in r[2])['NpcId'][1:3]) for k, r in dt['rows']}


def build_model_rows():
    """DT_SV_ModelRows: ACE_MODELS' copies of Online Mode model rows, for main.lua to add to DT_NPC_Model."""
    z = ZenPkg(stock(MODEL_ON))
    rename_package(z, MODEL_ON, DATA + 'DT_SV_ModelRows')
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveModelDataTable')
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    schema = uprop.U.schema('LiveModelDataTable')
    idx = {n: k for k, (n, t) in schema.items()}
    out = []
    for new, src, text in ACE_MODELS.values():
        f = survival_events.fname(src)
        row = copy.deepcopy(rows[(f[1], f[2])])
        set_prop(row[2], idx['GameObjectDisplayName01'], 'GameObjectDisplayName01', s(text))
        set_prop(row[2], idx['GameObjectId'], 'GameObjectId', ('raw', 'Int', struct.pack('<i', 1)))
        out.append(((new, 0), row))
    for k, row in out:
        for n in names_in(row) + [k[0]]: z.nb.add(n)
    dt['rows'] = out
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveModelDataTable')
    assert chk['rows'] == dt['rows']
    print(f'  DT_SV_ModelRows: {len(out)} rows')
    save(z, DATA + 'DT_SV_ModelRows')


def build_rows():
    build_rows_table('/Game/Datatables/Information/DT_LiveMissionTable', DATA + 'DT_SV_MissionRows',
                     'LiveLevelTable', 'Mission022', 'SurvivalMode', edit_mission_row)
    build_npc_rows()
    build_model_rows()
    build_rows_table('/Game/Datatables/UI/Menu/MainMenu/Top/DT_LiveMenuMainTopCommands', DATA + 'DT_SV_MenuRows',
                     'LiveMenuCommandsDataTable', 'Campaign', 'SurvivalMode', edit_menu_row)


# ---------------------------------------------------------------- NPC mission table
# The spawner caches the aircraft of every row of the world data's NPC table once, when the level starts, and a
# spawn only looks there (tools/re/EVENTS_AIRCRAFT.md): a row added at run time never spawns. So Survival's world
# data points at its own copy of Mission 22's table, with Survival's rows added here. A row's NpcId (a DT_NPC row)
# may be one that main.lua adds to DT_NPC at run time, as long as that happens before the level loads.
NPC_TABLE_STOCK = '/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission022'
NPC_TABLE = MOD + '/Data/DT_SV_NpcMission'
NPC_ROWS = set()           # its row names, filled by build_npc_table
# Rows copied whole from other missions' NPC tables (names and values only, no object references): the heavy bombers
# of Mission 4 (Milestone 3). Their blueprints are loaded by the spawner from the NpcId's DT_NPC row.
NPC_IMPORT = [('/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission004', ['t160_common', 'tu95_common']),
              # the amphibious assault's landing craft and troops (survival_events.LCAC_*), Mission 13's
              ('/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission013', ['lcac_common', 'btr9_common']),
              # the Ladons' own rows (survival_events.LADON*: LADON_SOURCE_ROW's copies; its parts name no mission row:
              # they come with its DT_NPC row's ChildNPCId)
              ('/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission016', []),
              # the Alicorn's own mission row (its parts name none): Online Mode's EB_002
              ('/Game/OnlineMode/DataTables/AI/NPC/Mission/DT_NPC_Mission_EB_002_ON', ['alcn_01'])]
LADON_TABLE_NOTE = 'DT_NPC_Mission016'
NPC_EXTRA = [   # (new row, copy of Mission 22's row, NpcId)  - names without a numeric tail (hard rule 17)
    ('sv_probe_pkg', 'm29a_common', 'SV_m29a_ProbePkg'),   # behaviour probe (main.lua): packaged script
    ('sv_probe_rt',  'm29a_common', 'SV_m29a_ProbeRt'),    # behaviour probe: run-time LuaScript
    (survival_events.SHUTTLE_NPC_ROW, 'sstb_common', survival_events.SHUTTLE_NPC),   # Comona Defense's shuttle (its name)
]
# Enemy search (main.lua CFG.search): for each of these rows a copy <row>_sv whose NpcId is <its NpcId>_SV, the DT_NPC
# copy main.lua adds at run time with Survival's 25 km AI module. Keep in step with main.lua CFG.aircraft.
SEARCH_AIRCRAFT = ['f16c_common', 'f18e_common', 'f15e_common', 'f14d_common', 'm21b_common',
                   'm29a_common', 'su47_common', 'su33_common', 'su34_common']
# Pool aircraft Mission 22's table hasn't got: (new mission row, Mission 22 row it's shaped like, DT_NPC row). The Su-47
# (user, 2026-10-23: "add SU-47's in instead of the MiG-31's"): the campaign's plain enemy Su-47.
POOL_EXTRA = [('su47_common', 'su33_common', 'OP1026_su47_01')]
# Difficulty spikes (main.lua CFG.spikes; user, 2026-10-22: "every 7 rounds ... a difficulty spike across the board"):
# each level after the first gets its own rows, <row>_sv<letter> -> <NpcId>_SV<LETTER>, whose DT_NPC copies main.lua
# gives that level's fire control. Letters, not digits: hard rule 17. Keep in step with main.lua SPIKE_SUFFIX.
SPIKE_SUFFIXES = ['b', 'c', 'd']


def build_npc_table():
    z = ZenPkg(stock(NPC_TABLE_STOCK))
    rename_package(z, NPC_TABLE_STOCK, NPC_TABLE)
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveNpcMissionDataTable')
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    npc_idx = [k for k, (n, t) in uprop.U.schema('LiveNpcMissionDataTable').items() if n == 'NpcId'][0]
    extra = list(NPC_EXTRA)
    for new_row, src, npc in POOL_EXTRA:
        assert (new_row, 0) not in rows, new_row
        row = copy.deepcopy(rows[(src, 0)])
        nid = survival_events.fname(npc)                                    # (its numeric tail: hard rule 17)
        set_prop(row[2], npc_idx, 'NpcId', nid)
        for n in (new_row, nid[1]): z.nb.add(n)
        rows[(new_row, 0)] = row
        dt['rows'].append(((new_row, 0), row))
    for src in SEARCH_AIRCRAFT:
        npc = [p for p in rows[(src, 0)][2] if p[0] == npc_idx][0][3]          # ('name', base, number)
        base = npc[1] if npc[2] == 0 else f'{npc[1]}_{npc[2] - 1}'
        extra.append((src + '_sv', src, base + '_SV'))
        for suf in SPIKE_SUFFIXES:
            extra.append((src + '_sv' + suf, src, base + '_SV' + suf.upper()))
    # the aces (ACES): <row> -> its DT_SV_NpcRows row, and like the search aircraft <row>_sv[b|c|d] -> <that>_SV[B|C|D]
    for tier, key, _, _ in ACES:
        for row, npc, _ in ace_rows(tier, key):
            extra.append((row, 'f16c_common', npc))
            for suf in [''] + SPIKE_SUFFIXES:
                extra.append((row + '_sv' + suf, 'f16c_common', npc + '_SV' + suf.upper()))
    # the STORE's allies (survival_events.ALLY_*): MOONCHILD on Mission 22's allied F/A-18 row, each ship's hull and
    # turrets on copies of Mission 22's rows, all pointing at DT_SV_NpcRows copies (their names, their fire control)
    extra.append((survival_events.ALLY_AIR_ROW, 'f18e_common', survival_events.ALLY_AIR_NPC))
    for src, (row, npc) in survival_events.DEFENCE_ROWS.items():           # the airfield's AA guns and SAM sites
        extra.append((row, src, npc))
    for key, _, hull, _ in survival_events.ALLY_SHIPS:
        row, npc, _ = survival_events.ally_ship_rows(key)
        extra.append((row, hull, npc))
        for t in survival_events.ALLY_TURRETS[key]:
            extra.append(survival_events.ally_turret_rows(t)[:1] + (t,) + survival_events.ally_turret_rows(t)[1:])
    for new_row, src, npc in extra:
        assert not any(c.isdigit() for c in new_row[-1:] + npc[-1:]), new_row
        row = copy.deepcopy(rows[(src, 0)])
        set_prop(row[2], npc_idx, 'NpcId', ('name', npc, 0))
        for n in (new_row, npc): z.nb.add(n)
        dt['rows'].append(((new_row, 0), row))
    for table, wanted in NPC_IMPORT:
        zs = ZenPkg(stock(table))
        ds, os_ = dtx.parse(uprop.Ctx(bytes(zs.payloads[0]), zs.names), 0, 'LiveNpcMissionDataTable')
        assert os_ == len(zs.payloads[0])
        srows = dict(ds['rows'])
        if table.endswith('DT_NPC_Mission016'):          # the Ladons' own rows: Mission 16's, on Survival's NPC rows
            for L in survival_events.ladons():
                row = copy.deepcopy(srows[(survival_events.LADON_SOURCE_ROW, 0)])
                set_prop(row[2], npc_idx, 'NpcId', ('name', L['npc'], 0))
                for n in names_in(row) + [L['row'], L['npc']]: z.nb.add(n)
                dt['rows'].append(((L['row'], 0), row))
                extra.append((L['row'], LADON_TABLE_NOTE, L['npc']))
        for r in wanted:
            assert (r, 0) not in rows, r
            row = copy.deepcopy(srows[(r, 0)])
            assert not any(p[3] and p[3][0] == 'obj' for p in row[2]), r              # names and values only
            for n in names_in(row) + [r]: z.nb.add(n)
            dt['rows'].append(((r, 0), row))
            extra.append((r, table.rsplit('/', 1)[1], None))
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveNpcMissionDataTable')
    assert chk['rows'] == dt['rows']
    NPC_ROWS.update(k[0] for k, _ in dt['rows'])          # build_wd_global checks the flights' behaviour rows
    print(f'  {len(dt["rows"])} rows ({len(extra)} Survival rows)')
    save(z, NPC_TABLE)


# ---------------------------------------------------------------- AI behaviour scripts
# Survival's own enemy behaviour trees (LuaScript assets: Code / ImportPath / LuaInitializePath, see
# tools/re/AI_BEHAVIOURS.md). Source in mod/UE4SS/AC8SurvivalMode/Scripts/ai/<name>.lua (the Lua runtime reads the
# same file); the package is a copy of a stock LA_ script package with our source and our own module name.
AI_SRC = os.path.join(ROOT, 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'ai')
LUA_TEMPLATE = '/Game/LuaSource/Chronicle/AI/LA_PursueTarget_0011'
LUA_SCRIPTS = ['LA_SV_ProbePursue', 'LA_SV_MoveAway', 'LA_SV_TailChase', 'LA_SV_ProvokeNear', 'LA_SV_Escape']


# The game's Lua require() (AceCombat8.exe 0x144eb8c00) loads module "A.B.C" with StaticLoadObject from
# /Game/LuaSource/A/B/C and runs that LuaScript's Code, so a behaviour script must live at the path its
# LuaInitializePath names: /Game/LuaSource/SurvivalMode/AI/<name> (a folder only Survival uses). Test 17: at
# /Game/Mods/SurvivalMode/AI it was never found and the probe MiGs flew stock.
LUA_DIR = '/Game/LuaSource/SurvivalMode/AI/'


def build_lua_scripts():
    for name in LUA_SCRIPTS:
        code = open(os.path.join(AI_SRC, name + '.lua'), encoding='utf-8').read().replace('\r\n', '\n').replace('\n', '\r\n')
        new_path = LUA_DIR + name
        z = ZenPkg(stock(LUA_TEMPLATE))
        rename_package(z, LUA_TEMPLATE, new_path)
        props, rest = props_of(z, 0, 'LuaScript')
        vals = props[2]                                          # LuaScript: 0 Code, 1 ImportPath, 2 LuaInitializePath
        set_prop(vals, 0, 'Code', s(code))
        set_prop(vals, 1, 'ImportPath', s('../../AssetWork/LuaSource/SurvivalMode/AI/' + name + '.lua'))
        set_prop(vals, 2, 'LuaInitializePath', s('SurvivalMode.AI.' + name))
        z.payloads[0] = bytearray(write_props(z, props) + rest)
        chk, _ = props_of(z, 0, 'LuaScript')
        assert dict((p[1], p[3]) for p in chk[2])['LuaInitializePath'] == s('SurvivalMode.AI.' + name)
        save(z, new_path)


if __name__ == '__main__':
    build_radio()
    build_alicorn_rows()
    build_lua_scripts()
    build_npc_table()
    build_shop_rows()
    build_rows()
    build_pl()
    build_mc()
    build_wd_global(); build_wd_phase(1); build_wd_phase(2)
    build_ef()
    build_ep('global', ef=True)
    build_ep('phase01')
    build_ep('phase02')
    print('player start', tuple(round(x) for x in START), 'yaw', RUNWAY_YAW)
