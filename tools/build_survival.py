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
import os, sys, struct, zlib, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, 'scripts'))
from zenpkg import ZenPkg, export_hash
import uprop, eprec

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

# Mission 16's sky: its lighting sublevel plus the world-settings values PL_Mission016 uses with it.
LIT_OLD = '/Game/Maps/MapCommon/Map17/Mission022/Mission022_Common_Lit_Cloudly01'
LIT_NEW = '/Game/Maps/MapCommon/Map14/Mission016/Mission016_Common_Lit_Cloudly01'
CLOCK = (8, 0)
CLOUD_DENSITY = 0.9
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
    # Lighting: Mission 16's sky/cloud level instead of Mission 22's.
    z.rename(LIT_OLD, LIT_NEW); z.rename(LIT_OLD.rsplit('/', 1)[1], LIT_NEW.rsplit('/', 1)[1])
    # Mission files
    for n in ('MC_Mission022', 'WD_Mission022_global', 'WD_Mission022_phase01', 'WD_Mission022_phase02',
              'EP_Mission022_global', 'EP_Mission022_phase01', 'EP_Mission022_phase02'):
        retarget_import(z, M22 + n, MI + n.replace('Mission022', 'SurvivalMode'))
    # World settings: Mission 16's clock and cloud density; drop Mission 22's shuttle-launch cloud light.
    i = z.export_index('ChronicleWorldSettings')
    v, rest = props_of(z, i, 'LiveWorldSettings')
    props = v[2]
    sc = uprop.U.schema('LiveWorldSettings')
    idx = {nm: k for k, (nm, t) in sc.items()}
    set_prop(props, idx['ClockHour'], 'ClockHour', ('raw', 'Int', struct.pack('<i', CLOCK[0])))
    set_prop(props, idx['ClockMin'], 'ClockMin', ('raw', 'Int', struct.pack('<i', CLOCK[1])))
    set_prop(props, idx['CloudDensityScale'], 'CloudDensityScale', ('raw', 'Float', struct.pack('<f', CLOUD_DENSITY)))
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
    """An empty world data: Mission 22's phase-2 world data without its player start."""
    old = M22 + 'WD_Mission022_phase02'
    z = ZenPkg(stock(old))
    rename_package(z, old, MI + 'WD_SurvivalMode_global')
    v, rest = props_of(z, 0, 'LiveWorldData')
    v[2][:] = [p for p in v[2] if p[1] != 'PlayerStartDescList']
    assert not v[2], v[2]
    z.payloads[0] = bytearray(write_props(z, v) + rest)
    save(z, MI + 'WD_SurvivalMode_global')


def build_ef():
    """Mission 22's event flag asset with every integer, bool and timer flag removed."""
    old = M22 + 'EF_Mission022_global'
    z = ZenPkg(stock(old))
    rename_package(z, old, MI + 'EF_SurvivalMode_global')
    v, rest = props_of(z, 0, 'LiveEventFlagAsset')
    def clear(s):
        for k, (pi, pn, zero, val) in enumerate(s[2]):
            if val and val[0] == 'map': s[2][k] = (pi, pn, False, ('map', 0, []))
            elif val and val[0] == 'struct': clear(val)
    clear(v)
    z.payloads[0] = bytearray(write_props(z, v) + rest)
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
    """Mission 22's event package for `part` (global / phase01 / phase02) with every trigger and exec removed."""
    old, new = M22 + 'EP_Mission022_' + part, MI + 'EP_SurvivalMode_' + part
    z = ZenPkg(stock(old))
    rename_package(z, old, new)
    retarget_import(z, M22 + 'WD_Mission022_' + part, MI + 'WD_SurvivalMode_' + part)
    if ef:
        retarget_import(z, M22 + 'EF_Mission022_global', MI + 'EF_SurvivalMode_global')
    empty_ep(z, new)
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


if __name__ == '__main__':
    build_rows()
    build_pl()
    build_mc()
    build_wd_global(); build_wd_phase(1); build_wd_phase(2)
    build_ef()
    build_ep('global', ef=True)
    build_ep('phase01')
    build_ep('phase02')
    print('player start', tuple(round(x) for x in START), 'yaw', RUNWAY_YAW)
