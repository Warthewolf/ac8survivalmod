"""build_survival.py : generate Survival Mode's zen packages into mod/Content.

Milestone 1 (fly at Comona): PL_SurvivalMode + a minimal mission (player start over Comona Airport, no events).
Templates:
  - PL_SurvivalMode            <- stock PL_Mission022 (Map17/Comona sublevels), lighting swapped to Mission 16's
  - MC_SurvivalMode            <- stock MC_Mission022
  - WD_SurvivalMode_phase01/02 <- stock WD_Mission022_phase01/02 (one player start each)
  - WD_SurvivalMode_global     <- stock WD_Mission022_phase02 without its player start (an empty world data)
  - EP_SurvivalMode_*          <- stock EP_Mission022_* with every trigger/exec removed
  - EF_SurvivalMode_global     <- stock EF_Mission022_global with no flags (flags come in Milestone 2)
  - DT_SV_MissionRows / DT_SV_MenuRows <- one row each from the stock mission and main-menu tables
Every template is a stock game file: Survival Mode uses nothing from another mod.
Stock packages are pulled with tools/get_stock.sh into build/stock first.
"""
import copy, os, sys, struct, zlib, subprocess
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
import math
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
        if name in POOL_UNITS and survival_events.AREA_RADIUS_M:   # the spawner's pool, without chase: an area over the whole zone
            rest_props = [p for p in rest_props if p[1] != 'RadiusInMeter'] + [
                (r_idx, 'RadiusInMeter', False, ('raw', 'Float', struct.pack('<f', survival_events.AREA_RADIUS_M)))]
        u[2][:] = sorted(rest_props + [on], key=lambda p: p[0])
    names = {[p for p in u[2] if p[1] == 'Name'][0][3][1] for u in units}
    assert set(survival_events.KEEP_AT_START) <= names, set(survival_events.KEEP_AT_START) - names
    assert any(p[1] == 'CombatZoneDescList' for p in v[2])
    z.payloads[i] = bytearray(write_props(z, v) + rest)
    chk, _ = props_of(z, i, 'LiveWorldData'); assert chk == v
    print(f'  {len(units)} units, spawn-at-start turned off on {turned_off}')
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


def edit_menu_row(props):
    setv(props, 'CommandID', ('name', 'Main_Top_SurvivalMode', 0))
    setv(props, 'TitleTextID', s('SV_Menu_Title'))
    setv(props, 'HelpTextID', s('SV_Menu_Help'))
    setv(props, 'MenuID', s('CampaignFreeMissionDifficulty'))   # the game's own free-mission difficulty page
    setv(props, 'StringArgs', s(MENU_ARGS))
    for k in ('ParentNewFlagTrigger', 'RefFeature'):
        hit = [p for p in props if p[1] == k]
        if hit: drop_prop(props, hit[0][0])


def build_rows():
    build_rows_table('/Game/Datatables/Information/DT_LiveMissionTable', DATA + 'DT_SV_MissionRows',
                     'LiveLevelTable', 'Mission022', 'SurvivalMode', edit_mission_row)
    build_rows_table('/Game/Datatables/UI/Menu/MainMenu/Top/DT_LiveMenuMainTopCommands', DATA + 'DT_SV_MenuRows',
                     'LiveMenuCommandsDataTable', 'Campaign', 'SurvivalMode', edit_menu_row)


# ---------------------------------------------------------------- NPC mission table
# The spawner caches the aircraft of every row of the world data's NPC table once, when the level starts, and a
# spawn only looks there (tools/re/EVENTS_AIRCRAFT.md): a row added at run time never spawns. So Survival's world
# data points at its own copy of Mission 22's table, with Survival's rows added here. A row's NpcId (a DT_NPC row)
# may be one that main.lua adds to DT_NPC at run time, as long as that happens before the level loads.
NPC_TABLE_STOCK = '/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission022'
NPC_TABLE = MOD + '/Data/DT_SV_NpcMission'
NPC_EXTRA = [   # (new row, copy of Mission 22's row, NpcId)  - names without a numeric tail (hard rule 17)
    ('sv_probe_pkg', 'm29a_common', 'SV_m29a_ProbePkg'),   # behaviour probe (main.lua): packaged script
    ('sv_probe_rt',  'm29a_common', 'SV_m29a_ProbeRt'),    # behaviour probe: run-time LuaScript
]


def build_npc_table():
    z = ZenPkg(stock(NPC_TABLE_STOCK))
    rename_package(z, NPC_TABLE_STOCK, NPC_TABLE)
    p = bytes(z.payloads[0])
    dt, o = dtx.parse(uprop.Ctx(p, z.names), 0, 'LiveNpcMissionDataTable')
    assert o == len(p), (o, len(p))
    rows = dict(dt['rows'])
    npc_idx = [k for k, (n, t) in uprop.U.schema('LiveNpcMissionDataTable').items() if n == 'NpcId'][0]
    for new_row, src, npc in NPC_EXTRA:
        assert not any(c.isdigit() for c in new_row[-1:] + npc[-1:]), new_row
        row = copy.deepcopy(rows[(src, 0)])
        set_prop(row[2], npc_idx, 'NpcId', ('name', npc, 0))
        for n in (new_row, npc): z.nb.add(n)
        dt['rows'].append(((new_row, 0), row))
    z.payloads[0] = bytearray(dtx.write(uprop.W(z.names), dt))
    chk, _ = dtx.parse(uprop.Ctx(bytes(z.payloads[0]), z.names), 0, 'LiveNpcMissionDataTable')
    assert chk['rows'] == dt['rows']
    print(f'  {len(dt["rows"])} rows ({len(NPC_EXTRA)} Survival rows)')
    save(z, NPC_TABLE)


# ---------------------------------------------------------------- AI behaviour scripts
# Survival's own enemy behaviour trees (LuaScript assets: Code / ImportPath / LuaInitializePath, see
# tools/re/AI_BEHAVIOURS.md). Source in mod/UE4SS/AC8SurvivalMode/Scripts/ai/<name>.lua (the Lua runtime reads the
# same file); the package is a copy of a stock LA_ script package with our source and our own module name.
AI_SRC = os.path.join(ROOT, 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'ai')
LUA_TEMPLATE = '/Game/LuaSource/Chronicle/AI/LA_PursueTarget_0011'
LUA_SCRIPTS = ['LA_SV_ProbePursue']


def build_lua_scripts():
    for name in LUA_SCRIPTS:
        code = open(os.path.join(AI_SRC, name + '.lua'), encoding='utf-8').read().replace('\r\n', '\n').replace('\n', '\r\n')
        new_path = MOD + '/AI/' + name
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
    build_lua_scripts()
    build_npc_table()
    build_rows()
    build_pl()
    build_mc()
    build_wd_global(); build_wd_phase(1); build_wd_phase(2)
    build_ef()
    build_ep('global', ef=True)
    build_ep('phase01')
    build_ep('phase02')
    print('player start', tuple(round(x) for x in START), 'yaw', RUNWAY_YAW)
