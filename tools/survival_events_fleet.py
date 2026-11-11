"""survival_events_fleet.py : THE INVINCIBLE FLEET's fleet (round 30, WP7 of docs/design/INVINCIBLE_FLEET.md; its research and
build notes: docs/design/INVINCIBLE_FLEET_WP7.md): its ships, their names, the formation, the course lanes and build_fleet.

IF_* (the ships: IF_SHIPS, IF_KINDS; their rows: IF_TURRETS and the named rows of if_fleet(); the course: if_course,
the lanes: if_fleet's lane points) and build_fleet (each ship's orders and its lane as it appears, RE_SV_IFGo<Key> for
Lua, RE_SV_IFFleetRemove). The units and rows are tools/build_survival_fleet.py's. Nothing spawns at the level's start:
Scripts/sv_fleet.lua (test only: Ctrl+N) spawns every ship. Round 30 is the user's dev install only (INVINCIBLE_FLEET.md
WP12): the Lua that spawns the fleet is TEST ONLY; these units and rows are in every build (as the Tanicorn's test units),
spawned by nothing outside a test build.

A part of tools/survival_events.py (its docstring has the layout): every name survival_events defines is here through the
import below, and survival_events imports this part back whole, so each name here is survival_events.<name> too
(build_survival.py and tools/checks read them so). Import survival_events, not this file.
"""
from survival_events import *  # noqa: F401,F403 (survival_events' names; it imports this part at its end)


# ---------------------------------------------------------------- the ships (INVINCIBLE_FLEET.md 2, WP7; the user, 2026-11-10)
# Every ship a one-ship unit of its own (the Spaceport's way: Faction 2, no tags, a TGT mark and a box, Normal as it
# appears and every part its own Normal / PlayerFirst order 2.5 s on: a hull's order never reaches its turrets), new units
# even where the Spaceport has the class (its units stay as they are). A named ship's box reads its name: the box's first
# line is its MODEL row's GameObjectDisplayName01 (HISTORY 0.74.11, the ZFA-44's), so each named ship has a model row of its
# own (SV_Model_Fleet_<Key>: its class's stock model row, only that name changed to IF_NAME_KEY + Key, whose text Lua
# sets) and a DT_NPC row naming it (SV_IF_<Key>: its class's hull row, its ChildNPCId on the fleet's turret rows), on a
# mission row of its own (sv_if_<key>). Unnamed ships (the pickets) keep their class's rows and name (the Spaceport's).
IF_NAME_KEY = 'SV_FleetName_'                    # + Key: the text key of a ship's name (Scripts/sv_fleet.lua SV_SetText)
IF_CLASS_KEY = 'SV_FleetClass_'                  # + its class (Ford, Aegis, Krov ...): the box's second line (its hull row's 02)
IF_MODEL = 'SV_Model_Fleet_'                     # + Key: its model row (DT_SV_ModelRows)
IF_NPC = 'SV_IF_'                                # + Key: its hull's DT_NPC row (DT_SV_NpcRows)
IF_ROW = 'sv_if_'                                # + key (lower case): its mission row (DT_SV_NpcMission)
IF_UNIT, IF_OBJ, IF_PATH = 'SV_Unit_IF', 'SV_Obj_IF', 'SV_Path_IF'   # + Key
# The ship classes. src: where its desc comes from: ('m16', unit) Mission 16's world data (the Ford: Mission 16's allied
# Grindylow, as the Spaceport's), ('wd', unit, object) Survival's own world data (Mission 22's: its allied Aegis
# AC_Unit_01_Ship1, its enemy fleet EA_Unit_01_Ship0..3, docs/re/SPECIAL_ROUNDS.md 3), ('tr6', unit) Training006's missile
# boat. hull: its stock DT_NPC row (the named copies' source), model: its stock model row, shape: the Mission 22 mission
# row its own is shaped as, z: its source's height (cm), parts: its parts as event args name them (after the ship's
# object name), pay (later, WP10).
IF_KINDS = {
    'ford':  dict(src=('m16', 'A_Unit_01_Ship0'), hull='VE004_grfd_01', model='VE004_grfd', shape='aegs_common', z=50.0,
                  parts=SP_FORD_PARTS, label='carrier'),
    'aegis': dict(src=('wd', SP_AEGIS_SOURCE, 'AC_Obj_01_Ship1_aegs_0'), hull='VE002_aegs_01', model='VE002_aegs',
                  shape='aegs_common', z=300.0, parts=SP_AEGIS_PARTS, label='Aegis'),
    'krov':  dict(src=('wd', 'EA_Unit_01_Ship3', 'EA_Obj_01_Ship3_krov_0'), hull='VE005_krov_MS22', model='VE005_krov',
                  shape='krov_common', z=300.0, parts=['Gun', 'Gun_Artillery', 'Sam', 'Vls'], label='Kirov battlecruiser'),
    'gors':  dict(src=('wd', 'EA_Unit_01_Ship2', 'EA_Obj_01_Ship2_gors_0'), hull='VE001_gors_MS22', model='VE001_gors',
                  shape='gors_common', z=300.0, parts=['Vls', 'Art', 'PalmaCiws', 'PalmaGun'], label='Gorshkov frigate'),
    'udal':  dict(src=('wd', 'EA_Unit_01_Ship0', 'EA_Obj_01_Ship0_udal_0'), hull='VE007_udal_MS22', model='VE007_udal',
                  shape='udal_common', z=300.0, parts=['Gun', 'Art'], label='Udaloy destroyer'),
    'grig':  dict(src=('wd', 'EA_Unit_01_Ship0', 'EA_Obj_01_Ship0_grig_0'), hull='VE015_grig_MS22', model='VE015_grig',
                  shape='grig_common', z=300.0, parts=['Art', 'GunL', 'GunR'], label='Grigorovich frigate'),
    'boat':  dict(src=('tr6', SP_BOAT_SOURCE[1]), hull=None, model=None, shape=None, z=0.0, parts=SP_BOAT_PARTS,
                  label='missile boat'),
}
# Mission 22's ships' parts by their component (the world data's ComponentFieldName), renamed by place (their names end in
# digits, _01 / _02: hard rule 17), and the GrandChildrens' (the Kirov's gun mount's Artillery) after their parent's
IF_M22_PLACES = {'BP_VE007_udal_ak130_01': 'Gun', 'BP_VE007_udal_ak130_02': 'Art',
                 'BP_VE015_grig_a190': 'Art', 'BP_VE015_grig_ak630_01': 'GunL', 'BP_VE015_grig_ak630_02': 'GunR',
                 'BP_VE001_gors_3r14': 'Vls', 'BP_VE001_gors_a192': 'Art', 'BP_VE001_gors_palma_01': 'PalmaCiws',
                 'BP_VE001_gors_palma_02': 'PalmaGun',
                 'BP_VE005_krov_ak130': 'Gun', 'Artillery': 'Artillery', 'BP_VE005_krov_kashtan': 'Sam', 'BP_VE005_krov_s300fm': 'Vls'}
# Their turrets on Survival's own rows (as the Spaceport's SP_TURRETS): (the part's Mission 22 mission row, Survival's
# mission row, Survival's DT_NPC row, the stock DT_NPC row it copies). Scripts/sv_fleet.lua adds the DT_NPC rows at the main
# menu and puts each on the Spaceport fleet's fire control (<FCS>_SVA_Fleet, sv_allies.lua) where that clone exists.
# (The Aegis's and the Ford's parts fly the Spaceport's own turret rows, SP_TURRETS: already on that fire control.)
IF_TURRETS = [
    ('udal_ak130', 'sv_iff_udalgun', 'SV_IFF_UdalGun', 'VE007_udal_ak130_aagun_MS22'),
    ('udal_ak130_artillery', 'sv_iff_udalart', 'SV_IFF_UdalArt', 'VE007_udal_ak130_artillery_MS22'),
    ('grig_a190', 'sv_iff_grigart', 'SV_IFF_GrigArt', 'VE015_grig_a190_MS22'),
    ('grig_ak630_L', 'sv_iff_griggunl', 'SV_IFF_GrigGunL', 'VE015_grig_ak630_L_MS22'),
    ('grig_ak630_R', 'sv_iff_griggunr', 'SV_IFF_GrigGunR', 'VE015_grig_ak630_R_MS22'),
    ('gors_3r14', 'sv_iff_gorsvls', 'SV_IFF_GorsVls', 'VE001_gors_3r14_MS22'),
    ('gors_a192', 'sv_iff_gorsart', 'SV_IFF_GorsArt', 'VE001_gors_a192_MS22'),
    ('gors_plama_ciws', 'sv_iff_gorspalmaciws', 'SV_IFF_GorsPalmaCiws', 'VE001_gors_palma_ciws_MS22'),
    ('gors_plama_aagun', 'sv_iff_gorspalmagun', 'SV_IFF_GorsPalmaGun', 'VE001_gors_palma_aagun_MS22'),
    ('krov_ak130', 'sv_iff_krovgun', 'SV_IFF_KrovGun', 'VE005_krov_ak130_aagun_MS22'),
    ('krov_ak130_artillery', 'sv_iff_krovart', 'SV_IFF_KrovArt', 'VE005_krov_ak130_artillery_MS22'),
    ('krov_kashtan', 'sv_iff_krovsam', 'SV_IFF_KrovSam', 'VE005_krov_kashtan_MS22'),
    ('krov_s300fm', 'sv_iff_krovvls', 'SV_IFF_KrovVls', 'VE005_krov_s300fm_MS22'),
]
IF_TURRET_SHAPE = SP_TURRET_SHAPE                # (their mission rows shaped as the Spaceport's turrets')
# The fleet (the user, 2026-11-10: "rings round GEOFON"; AC04's names, each once): (name on its box ('' for an unnamed ship),
# Key (its units' and rows' names), class, fwd_m, right_m: its spot in GEOFON's frame as the fleet sails in, metres ahead of
# GEOFON and to its starboard). RAVEN beside GEOFON (~600 m off its beam: the capture's source sails with it, WP14), the four
# Aegis an inner ring (1.5 km, on the diagonals), the cruisers and destroyers an outer ring (3.5 km, every 360/7 deg from
# dead ahead, clockwise), the missile boats IF_PICKET_KM ahead as pickets. Scripts/sv_fleet.lua CFG.specials.fleet.ships
# has the same table (the build checks it).
IF_INNER_KM, IF_OUTER_KM = 1.5, 3.5
IF_PICKET_KM, IF_PICKET_SIDE_KM = 5.0, 1.0


def _ring(r_km, deg):
    import math
    a = math.radians(deg)
    return round(r_km * 1000.0 * math.cos(a)), round(r_km * 1000.0 * math.sin(a))


IF_SHIPS = ([('GEOFON', 'Geofon', 'ford', 0, 0), ('RAVEN', 'Raven', 'aegis', 0, 600)]
            + [(n, n.title(), 'aegis') + _ring(IF_INNER_KM, d) for n, d in
               (('CONDOR', 45), ('FINCH', 135), ('SPARROW', 225), ('MAGPIE', 315))]
            + [(n, n.title(), k) + _ring(IF_OUTER_KM, 360.0 / 7 * i) for i, (n, k) in enumerate(
                (('BELUGA', 'krov'), ('KOLGA', 'udal'), ('HERNE', 'grig'), ('TAISCH', 'grig'), ('THIASSI', 'grig'),
                 ('LAZULI', 'grig'), ('FENRIS', 'gors')))]
            + [('', 'PicketA', 'boat', round(IF_PICKET_KM * 1000), round(IF_PICKET_SIDE_KM * 1000)),
               ('', 'PicketB', 'boat', round(IF_PICKET_KM * 1000), -round(IF_PICKET_SIDE_KM * 1000))])

# ---------------------------------------------------------------- the course (INVINCIBLE_FLEET.md WP7 "Course")
# North = -Y, east = +X (docs/re/COMONA_MAP.md 1). GEOFON comes in from IF_START_KM north-west of the runway's centre and
# sails south-east (UE yaw IF_YAW, heading 135) straight at the airfield, turns onto its station (crossing its gun line,
# IF_SHELL_KM out, as it turns) and laps it: a racetrack across the line of approach, its far leg on the gun line and its
# near leg IF_HOLD_KM out (never nearer: WP13 shells from there), turns of IF_TURN_KM, legs of IF_LEG_KM, IF_LAPS laps, all
# in the one path started as it appears (hard rule 54; the station's laps in the same path, as the Ladons' circuit). Every
# ship's lane is GEOFON's course moved by the ship's spot (its offset turned by IF_YAW, then the same for the whole course:
# a translation), so every lane is the same shape and length and, sailed at one speed (IF_SPEED), the formation holds
# exactly, on the turns too: it keeps its compass orientation (the pickets lead the way in, and trail on the station's
# back leg). Its first point a little ahead of where the ship spawns (IF_LEAD_M behind it along the course: hard rule 2),
# ControlType 1 (hard rule 35), points every IF_STEP_KM on the straights and IF_ARC_DEG on the turns, smooth tangents and
# the ship kept level (build_survival_fleet.fleet_path). At 45 km/h: the gun line ~15 minutes in, a lap ~38 minutes.
IF_RUNWAY = (1610476.0, -436143.0)               # the runway's centre (COMONA_MAP.md 1)
IF_YAW = 45.0                                    # the course in (UE yaw: south-east)
IF_START_KM, IF_SHELL_KM, IF_HOLD_KM = 30.0, 20.0, 16.0
IF_TURN_KM, IF_LEG_KM, IF_LAPS = 2.0, 8.0, 2
IF_STEP_KM, IF_ARC_DEG = 2.0, 20.0
IF_SPEED = '45.0'                                # km/h, every ship (the path record's speed)
IF_LEAD_M = 500.0
IF_AREA_M, IF_ALT_M = SP_SHIP_AREA_M, SP_SHIP_ALT_M   # each unit's area (45 km: the whole course and the airfield)
IF_COAST_KM = 3.0                                # no lane point nearer a land tile (COMONA_MAP.md 3's 22 tiles)
IF_LAND_TILES = ['B14', 'B15', 'B16', 'C12', 'C13', 'C14', 'C15', 'D05', 'D06', 'D10', 'D11', 'D12', 'D13',
                 'E05', 'E06', 'E07', 'E08', 'E09', 'E11', 'F04', 'F05', 'F06']
IF_TILE_CM = 443370.0


def if_frame():
    """(forward, starboard) unit vectors of the course in."""
    import math
    a = math.radians(IF_YAW)
    return (math.cos(a), math.sin(a)), (-math.sin(a), math.cos(a))


def if_course():
    """GEOFON's course (x, y) cm: the run in from IF_START_KM, the turn onto the station's far leg, IF_LAPS laps."""
    import math
    (ux, uy), (rx, ry) = if_frame()
    R, step, arc = IF_TURN_KM * 1e5, IF_STEP_KM * 1e5, math.radians(IF_ARC_DEG)
    x, y = IF_RUNWAY[0] - ux * IF_START_KM * 1e5, IF_RUNWAY[1] - uy * IF_START_KM * 1e5
    h = math.radians(IF_YAW)
    pts = [(x, y)]

    def straight(d):
        nonlocal x, y
        n = max(1, math.ceil(d / step - 1e-9))
        for k in range(1, n + 1):
            pts.append((x + math.cos(h) * d * k / n, y + math.sin(h) * d * k / n))
        x, y = pts[-1]

    def turn(deg, right):
        nonlocal x, y, h
        s = 1.0 if right else -1.0                      # (UE: +yaw turns to starboard)
        cx, cy = x + math.cos(h + s * math.pi / 2) * R, y + math.sin(h + s * math.pi / 2) * R
        a0 = math.atan2(y - cy, x - cx)
        tot = math.radians(deg)
        n = max(1, math.ceil(tot / arc - 1e-9))
        for k in range(1, n + 1):
            a = a0 + s * tot * k / n
            pts.append((cx + math.cos(a) * R, cy + math.sin(a) * R))
        x, y = pts[-1]
        h += s * tot
    far = IF_HOLD_KM + 2 * IF_TURN_KM                   # (the far leg's distance out: the gun line)
    assert abs(far - IF_SHELL_KM) < 1e-6, 'the station\'s far leg is the gun line'
    straight((IF_START_KM - far - IF_TURN_KM) * 1e5)    # in, to a turn's radius short of the far leg
    turn(90.0, True)                                    # onto the far leg (heading south-west)
    straight((IF_LEG_KM / 2 - IF_TURN_KM) * 1e5)        # to its end
    for _ in range(IF_LAPS):
        turn(180.0, False); straight(IF_LEG_KM * 1e5)   # to the near leg (IF_HOLD_KM out), along it
        turn(180.0, False); straight(IF_LEG_KM * 1e5)   # back to the far leg, along it
    return pts


def if_land_km(x, y):
    """The distance (km) from (x, y) cm to the nearest of COMONA_MAP.md 3's land tiles (a tile's whole square)."""
    import math
    best = 1e9
    for t in IF_LAND_TILES:
        row, col = ord(t[0]) - 65, int(t[1:])
        x0, y0 = (col - 9) * IF_TILE_CM, (row - 4) * IF_TILE_CM
        dx = max(x0 - x, 0.0, x - (x0 + IF_TILE_CM))
        dy = max(y0 - y, 0.0, y - (y0 + IF_TILE_CM))
        best = min(best, math.hypot(dx, dy) / 1e5)
    return best


def if_fleet():
    """Every ship of the fleet, GEOFON first: dict(name, key, kind, unit, obj, path, point (its spawn, cm), yaw, lane
    [(x, y, z) cm], off (world dx, dy cm), fwd_m, right_m, row / npc / model / name_key (None for an unnamed ship), parts (as
    event args name them), up (its appearance event), go (Lua's remote event))."""
    if getattr(if_fleet, 'done', None): return if_fleet.done
    (ux, uy), (rx, ry) = if_frame()
    course = if_course()
    out = []
    for name, key, kind, fwd, right in IF_SHIPS:
        K = IF_KINDS[kind]
        assert key.isalpha() and key[0].isupper(), key          # (no digit: hard rule 17)
        ox, oy = (ux * fwd + rx * right) * 100.0, (uy * fwd + ry * right) * 100.0
        lane = [(x + ox, y + oy, K['z']) for x, y in course]
        sx, sy = lane[0][0] - ux * IF_LEAD_M * 100.0, lane[0][1] - uy * IF_LEAD_M * 100.0
        named = bool(name)
        s = dict(name=name, key=key, kind=kind, unit=IF_UNIT + key, obj=IF_OBJ + key, path=IF_PATH + key,
                 point=(sx, sy, K['z']), yaw=IF_YAW, lane=lane, off=(ox, oy), fwd_m=fwd, right_m=right,
                 row=(IF_ROW + key.lower()) if named else None, npc=(IF_NPC + key) if named else None,
                 model=(IF_MODEL + key) if named else None, name_key=(IF_NAME_KEY + key) if named else None,
                 up=f'SV_IFUp{key}', go=f'RE_SV_IFGo{key}')
        s['parts'] = [f"{s['obj']}_{p}" for p in K['parts']]
        out.append(s)
    assert out[0]['key'] == 'Geofon' and len({s['key'] for s in out}) == len(out)
    for s in out:                                               # the coast (WP7: "never nearer the coast")
        near = min(if_land_km(x, y) for x, y, _ in [s['point']] + s['lane'])
        assert near >= IF_COAST_KM, (s['key'], f'{near:.2f} km from a land tile')
    if_fleet.done = out
    return out


def if_lua_ships():
    """Scripts/sv_fleet.lua's CFG.specials.fleet.ships as (name, key, kind, fwd_m, right_m), read from its text."""
    import re
    lua = runtime_lua()
    m = re.search(r'\n    ships = \{(.*?)\n    \},', lua, re.S)
    assert m, 'Scripts/sv_fleet.lua: no CFG.specials.fleet.ships'
    return [(a, b, c, int(d), int(e)) for a, b, c, d, e in re.findall(
        r'\{ name = "(\w*)", key = "(\w+)", kind = "(\w+)", fwd_m = (-?\d+), right_m = (-?\d+)', m.group(1))]


def build_fleet(g, flag, stock_ep):
    """THE INVINCIBLE FLEET's records (IF_*), each ship's as it appears (SV_IFUp<Key>) and again on Lua's RE_SV_IFGo<Key>
    (Scripts/sv_fleet.lua fires it for a ship it doesn't see under way, as THE FESTIVAL's RE_SV_FestUp_<g>): the unit and the
    ship on its lane at IF_SPEED (the STORE's ships' path records, as the Spaceport's boat patrols: 1 s on), Mission 22's
    Normal ship order on the unit (2 s) and every part its own Normal / PlayerFirst order (Mission 16's Ladon CIWS order,
    2.5 s). RE_SV_IFFleetRemove: every ship's unit despawned (Mission 22's)."""
    import re
    lua = runtime_lua()
    assert '"RE_SV_IFGo" ..' in lua, 'Scripts/sv_fleet.lua never fires RE_SV_IFGo<Key>'
    fleet = if_fleet()
    want = [(s['name'], s['key'], s['kind'], s['fwd_m'], s['right_m']) for s in fleet]
    assert if_lua_ships() == want, ('Scripts/sv_fleet.lua CFG.specials.fleet.ships differs from IF_SHIPS', if_lua_ships(), want)
    m = re.search(r'turret_rows = \{([^}]*)\}', lua)            # (the rows it adds at the main menu, the names it gives)
    assert m and re.findall(r'"(\w+)"', m.group(1)) == [npc for _, _, npc, _ in IF_TURRETS], 'sv_fleet.lua turret_rows: not IF_TURRETS'
    for k in (IF_NAME_KEY, IF_CLASS_KEY, IF_MODEL, IF_NPC, IF_UNIT):
        assert f'"{k}" ..' in lua, f'Scripts/sv_fleet.lua names no {k}<Key>'
    m = re.search(r'course_yaw = (-?[\d.]+), runway_cm = \{ (-?\d+), (-?\d+) \}', lua)
    assert m and (float(m.group(1)), float(m.group(2)), float(m.group(3))) == (IF_YAW,) + IF_RUNWAY, 'sv_fleet.lua course_yaw / runway_cm'
    t_seng = g.exec_template('LiveAIEngagementOrder', 'UnitDamage_Enemy_Ship_Last1', lambda a, e: a[0].startswith('AC_Obj_01_Ship1'))
    m16 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission016', 'EP_Mission016_global.uasset')
    t_part = g.foreign_template(m16, 'LiveAIEngagementOrder', 'Default_RemoteEvent_20',
                                lambda a, e: a[0] == 'B_Obj_01_Air0_Ladon0_LCIWS')
    t_spath = g.exec_template('LiveAIPathExecution', 'RE_Wave01_Start', lambda a, e: a[0] == 'AC_Obj_01_Ship1_aegs_0')
    t_upath = g.exec_template('LiveAIPathExecution', 'RE_Wave01_Start', lambda a, e: a[1] == 'AC_Unit_01_Ship1')
    t_remove = g.exec_template('LiveDestroyUnitExecution', 'Debug_Destroy_Shuttle')
    assert arg_values(t_seng)[3] == 'Normal' and arg_values(t_part)[3] == 'Normal' and arg_values(t_part)[6] == 'PlayerFirst'
    assert arg_values(t_spath)[1] == 'NoneSelect' and arg_values(t_upath)[0] == 'NoneSelect', (arg_values(t_spath), arg_values(t_upath))
    float(arg_values(t_spath)[4]); float(arg_values(t_upath)[4])          # (arg 4: the speed, km/h)
    parts = 0
    for s in fleet:
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', s['up'], arg_changes={0: s['unit']})
        g.trigger('RE_SpawnEnemy_kokatu_1st', s['go'])                    # (a remote-event trigger)
        for ev in (s['up'], s['go']):
            g.execute(t_spath, ev, {0: s['obj'], 2: s['path'], 4: IF_SPEED}, delay=1.0)
            g.execute(t_upath, ev, {1: s['unit'], 2: s['path'], 4: IF_SPEED}, delay=1.0)
            g.execute(t_seng, ev, {0: 'NoneSelect', 1: s['unit']}, delay=2.0)
            for p in s['parts']:
                g.execute(t_part, ev, {0: p}, delay=2.5)
                parts += 1
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_IFFleetRemove')
    for s in fleet:
        g.execute(t_remove, 'RE_SV_IFFleetRemove', {0: 'NoneSelect', 1: s['unit'], 2: 'NoneSelect'})
    print(f'  invincible fleet: {len(fleet)} ships (SV_IFUp<Key> / RE_SV_IFGo<Key>: each on its lane at {IF_SPEED} km/h, '
          f'Normal; {parts // 2} parts ordered Normal / PlayerFirst), RE_SV_IFFleetRemove')
