"""survival_events_festival.py : GONE FISHIN' and THE FESTIVAL (2026-11-06): their names, shapes and events.

FISH_* / SAL_BOAT_* (the shoals and SAL's boat: no events), FEST_* (the Tu-160 formations, their cruise
missiles and the searchlights) and build_festival.

A part of tools/survival_events.py (its docstring has the layout): every name survival_events defines is
here through the import below, and survival_events imports this part back whole, so each name here is
survival_events.<name> too (build_survival.py and tools/checks read them so). Import survival_events, not this file.
"""
from survival_events import *  # noqa: F401,F403 (survival_events' names; it imports this part at its end)


# ---------------------------------------------------------------- GONE FISHIN' and THE FESTIVAL (2026-11-06)
# The build data of the build contract of 2026-11-06 (FISHING_ROUND_PLAN.md section 0; the research: docs/re/FISHING.md,
# whose "Build names" section lists everything below). Coordinates UE cm, north = -Y, east = +X. The Lua (rounds, catches,
# the festival's sequence) spawns and fires all of it; nothing here spawns at the level's start.
FISH_RWY = (1610476.0, -436142.0)              # the contract's runway centre (docs/re/COMONA_MAP.md, runway.json)
# GONE FISHIN': FISH_PER_GROUND shoals a unit, every unit round SAL's boat (user, 2026-11-07, after Alyssa's test: "the
# shoals need to be more numerous and spread around the boat"; were three grounds of 8 far apart, the boat at one):
# unit A on the boat itself, its shoals FISH_INNER_MIN_M .. FISH_SPREAD_M out (clear of the boat whatever the yaw), the
# others on a ring of FISH_RING_M round it, so the shoals lie about 0.3-2.7 km from the boat, open sea all round (5.7 km
# to land: FISHING.md 4). Lua spawns each at its pose (Scripts/sv_fishing.lua FISH.grounds: the ring turned at random
# each round); these are only the world data's spots
FISH_KEYS = 'ABCDEF'
FISH_PER_GROUND = 8
FISH_SPREAD_M, FISH_GAP_M = 800.0, 150.0       # each shoal within FISH_SPREAD_M of its unit's origin, none closer than GAP
FISH_INNER_MIN_M = 300.0                       # unit A's (on the boat) shoals this far from it at least
FISH_RING_M = 1900.0                           # the other units' origins this far from the boat, evenly round it
FISH_Z_CM = 700.0                              # 7 m up: the sea's collision plane is at 3.5 m (Lua spawns them at z 700)
# a shoal: Mission 13's scored dummy unit (E_Obj02_02_Score0: the stock invisible turret pawn GR000_dummy, faction 2),
# ported with a box and the TGT mark (hard rules 31, 32); its own DT_NPC row on its own model row (MaxHealth FISH_HEALTH:
# above co-op's 1 HP copy floor, one missile or bomb), both added to the campaign tables at the main menu by Lua.
# bIsLanding cleared (Mission 17's sky dummy has none and holds 12 km up; Mission 22's sea dummies carry it, at z 3.5 m)
FISH_SOURCE = ('/Game/Maps/Ingame/Mission013/WD_Mission013_global', 'E_Unit02_02_Score0')
FISH_ROW = 'sv_shoal'                          # DT_SV_NpcMission row (Mission 22's dummy_common) -> NpcId FISH_NPC
FISH_ROW_TEMPLATE = 'dummy_common'
FISH_NPC = 'SV_Shoal'                          # DT_SV_NpcRows: GR000_dummy with durability rows, name key, no score
FISH_NPC_SOURCE = 'GR000_dummy'
FISH_DURABILITY = ('NPC_WPDur_000', 'test_NPC_ExpDur_000')    # (WeaponDurabilityId, ExplosionDurabilityId: the boats')
FISH_MODEL = 'SV_Model_Shoal'                  # DT_SV_ModelRows: the campaign's GR000_dummy model row, MaxHealth FISH_HEALTH
FISH_MODEL_SOURCE = 'GR000_dummy'
FISH_HEALTH = 10.0
FISH_NAME_KEY = 'SV_Shoal_Name'                # its text (SHOAL) set by Lua (SV_SetText): the box's name
FISH_SUB_KEY = 'SV_Shoal_Sub'                  # the box's second line (the NPC row's name 02; 2026-11-07: it was the name
                                               # key too, SHOAL twice), its text set empty by Lua

# THE TANICORN's milestone 0 (docs/re/TANICORN.md, test builds only: Scripts/sv_tanicorn.lua Ctrl+T): one gun mount of
# Survival's own (BP_SV_Tani_T5, built by tools/tanicorn, its container staged with TANI=1 only) spawned as the shoal is:
# Mission 13's scored dummy unit ported (faction 2, box and TGT mark), its own mission row, DT_NPC row and model row, the
# model row's blueprint ours. Names with no numeric tail (hard rule 17). Nothing names the Tanicorn's blueprint but the
# model row (a soft path): without its container the row names a class the game hasn't and the unit doesn't spawn.
TANI_UNIT = 'SV_Unit_TaniTest'
TANI_OBJ = 'SV_Obj_TaniTest'
TANI_ROW = 'sv_tani_mount'                     # DT_SV_NpcMission (Mission 22's dummy_common) -> NpcId TANI_NPC
TANI_NPC = 'SV_Npc_TaniMount'                  # DT_SV_NpcRows: GR000_dummy's row on TANI_MODEL, the boats' durability rows
TANI_MODEL = 'SV_Model_TaniMount'              # DT_SV_ModelRows: GR000_dummy's model row, our blueprint, TANI_HEALTH
TANI_BP = '/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_T5'
TANI_BP_CLASS = 'BP_SV_Tani_T5_C'
TANI_HEALTH = 40.0
# (0.74.58) TANI_NPC's NpcFCSId0: the stock ground flak gun's fire control row; (0.74.59) its copy with the twin mount's two
# muzzles (SlotNum 2), made at the main menu by Scripts/sv_tanicorn.lua (TANI.fcs; the stock row's SlotNum fires one barrel)
TANI_FCS = 'SV_FCS_TaniT5'
# (0.74.60) THE TANACORN's hull with every part drawn on its socket (docs/design/INVINCIBLE_FLEET.md WP2, its first step:
# the whole ship on the sea), spawned as the test mount is (the same scored dummy unit, our model row's blueprint
# BP_SV_Tani_HULL); Scripts/sv_tanicorn.lua's Ctrl+Y. Its parts become live AI parts in WP2's next step.
TANI_HULL_UNIT = 'SV_Unit_TaniHull'
TANI_HULL_OBJ = 'SV_Obj_TaniHull'
TANI_HULL_ROW = 'sv_tani_hull'
TANI_HULL_NPC = 'SV_Npc_TaniHull'
TANI_HULL_MODEL = 'SV_Model_TaniHull'
TANI_HULL_BP = '/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_HULL'
TANI_HULL_BP_CLASS = 'BP_SV_Tani_HULL_C'
TANI_HULL_HEALTH = 5000.0
TANI_HULL_NAME_KEY = 'SV_TaniHull_Name'
TANI_NAME_KEY = 'SV_TaniMount_Name'
# (0.74.61) the Tanicorn's other gun mounts, each testable as the T5 is (Scripts/sv_tanicorn.lua Ctrl+U spawns the three in a
# row): one unit each (the scored dummy unit again), its own mission row, DT_NPC row and model row (its blueprint
# BP_SV_Tani_<part>, its health, its name key), the DT_NPC row's NpcFCSId0 its own fire control row SV_FCS_Tani<part>, which
# sv_tanicorn.lua (TANI.mounts) clones at the main menu from a stock row whose arms blueprint drives BN_turret_yaw /
# BN_turret_pitch on TurretPoseableMesh with the GUN prefix (0.74.59: the row's arm replaces the blueprint's and gives it its
# muzzles; 0.74.58: without a row the weapon hung at socket None):
#   T16    NPC_FCS_VesselArtillery000 (BP_FCS_Vessel_Artillery_00, the ships' main gun, BP_wp_artillery_vesselgun); the land
#          battleships' railgun arms (BP_FCS_StrafingRailgun_00, the GR036 main cannon) drive PM_Cannon's BN_turret_pitch_01
#          / _02, bones and a mesh our triple hasn't
#   CIWS   NPC_FCS_VesselCIWS000 (BP_FCS_Vessel_CIWS_00, the Aegis's Mk15, BP_wp_ciws_vessel)
#   LASER  NPC_FCS_VesselCIWS000 too, for now: no stock arms blueprint fires a laser (docs/re/TANICORN.md 3)
# part: (the tag its names carry, its health). The tag never ends in a digit (build_survival.py's extra rows assert it;
# hard rule 17), so the 16-inch's is T16Gun.
TANI_MOUNT_PARTS = {'T16': ('T16Gun', 80.0), 'CIWS': ('CIWS', 30.0), 'LASER': ('LASER', 30.0)}


def tani_mount(part):
    """The names of THE TANICORN's test mount `part` (TANI_MOUNT_PARTS), as the T5's TANI_* are."""
    tag, health = TANI_MOUNT_PARTS[part]
    return {'part': part, 'unit': f'SV_Unit_Tani{tag}', 'obj': f'SV_Obj_Tani{tag}', 'row': f'sv_tani_{tag.lower()}',
            'npc': f'SV_Npc_Tani{tag}', 'model': f'SV_Model_Tani{tag}',
            'bp': f'/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_{part}', 'bp_class': f'BP_SV_Tani_{part}_C',
            'fcs': f'SV_FCS_Tani{part}', 'name_key': f'SV_Tani{tag}_Name', 'health': health, 'up': f'SV_TaniUp{tag}'}


TANI_MOUNTS = [tani_mount(p) for p in TANI_MOUNT_PARTS]
# (2026-11-11, WP2 step 2, route (a): docs/design/INVINCIBLE_FLEET.md "WP2 step 2") THE TANACORN with her gun mounts LIVE,
# a second hull beside the drawn one (TANI_HULL_*: Ctrl+Y / Ctrl+R, unchanged): BP_SV_Tani_HULLLIVE (tools/tanicorn/spec.py
# hull_bp, LIVE: the same rise rig and hull mesh) whose 16 gun-mount sockets carry LiveChildActorComponents, Part_<socket>,
# the mount's own blueprint. In the world data each is a child desc of the hull's object (Mission 22's Aegis mk15 child as
# the template: tools/build_survival_world.py tanicorn_units) naming its class, a HARD import of the Tanicorn container's
# blueprint (hard rule 7), so ONLY in TANI=1 builds (TANI_WD: the switch the user sets for build_all.sh and package_dev.sh;
# the packagers refuse a build whose world data has it: build/install/tani_wd.txt). Each part on the mount's own rows (the
# test mounts': its mission row in the desc, its DT_NPC row in the hull's ChildNPCId / ChildNPCComponentNames too, so it
# doesn't matter which the game takes), its own TGT mark, ordered by name TANI_LIVE_ORDER_S after the hull appears (a hull's
# order never reaches its turrets: the Spaceport's 0.73.40). The orders and the rows are names only: in every build.
# Scripts/sv_tanicorn.lua's Ctrl+L.
TANI_WD = os.environ.get('TANI') == '1'
TANI_HULL_LIVE_UNIT = 'SV_Unit_TaniHullLive'
TANI_HULL_LIVE_OBJ = 'SV_Obj_TaniHullLive'
TANI_HULL_LIVE_ROW = 'sv_tani_hull_live'
TANI_HULL_LIVE_NPC = 'SV_Npc_TaniHullLive'
TANI_HULL_LIVE_MODEL = 'SV_Model_TaniHullLive'
TANI_HULL_LIVE_BP = '/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_HULLLIVE'
TANI_HULL_LIVE_BP_CLASS = 'BP_SV_Tani_HULLLIVE_C'
TANI_HULL_LIVE_NAME_KEY = 'SV_TaniHullLive_Name'   # (its box: TANACORN, Lua's text)
TANI_HULL_LIVE_UP = 'SV_TaniUpHullLive'            # (the hull's appearance: each part's order)
TANI_LIVE_ORDER_S = 2.5
TANI_PKG = '/Game/Mods/SurvivalMode/Tanicorn'      # (the container's folder: no import under it without TANI_WD)
# each mount type's sockets on the hull (tools/tanicorn's export: the hull's Mount_<socket>), in its parts.json order
TANI_LIVE_SOCKETS = {'T16': ['T16_FWD', 'T16_AFT'], 'T5': [f'T5_{k}' for k in range(1, 7)],
                     'CIWS': [f'CIWS_{k}' for k in range(1, 5)],
                     'LASER': ['LASER_FWD_L', 'LASER_FWD_R', 'LASER_AFT_L', 'LASER_AFT_R']}


def tani_live():
    """THE TANACORN's live parts, one a socket: its component (Part_<socket>), its object as event args write it
    (SV_Obj_TaniHullLive_Part_<socket>; the world data stores both through fname: 'Part_T5_1' = ('Part_T5', 2), hard rule
    17), its mount type's mission row, DT_NPC row and blueprint (the T5's TANI_*, the others' TANI_MOUNTS)."""
    out = []
    for part, sockets in TANI_LIVE_SOCKETS.items():
        m = {'row': TANI_ROW, 'npc': TANI_NPC, 'bp': TANI_BP, 'bp_class': TANI_BP_CLASS} if part == 'T5' else tani_mount(part)
        for s in sockets:
            comp, obj = f'Part_{s}', f'{TANI_HULL_LIVE_OBJ}_Part_{s}'
            assert fname(comp)[2] == fname(obj)[2], (comp, obj)          # (the same split tail: hard rule 17)
            assert m['bp'].startswith(TANI_PKG + '/') and m['bp_class'] == m['bp'].rsplit('/', 1)[1] + '_C', m
            out.append({'socket': s, 'part': part, 'comp': comp, 'obj': obj, 'row': m['row'], 'npc': m['npc'],
                        'bp': m['bp'], 'bp_class': m['bp_class']})
    return out


TANI_LIVE = tani_live()
# SAL's boat (FISHING.md 3; user: "SAL boat can just be an ally, dont worry about it too much"): Mission 28's allied Wasp
# desc (faction 1, box, callsign, attack-target exception) on the stock fishing boat VE027_boat2_01, not invincible but
# from AI and wingmen, MinHealth 1 on its mission row (as the stock allied ships'), its callsign as VOID WATCHER's
SAL_BOAT_UNIT = 'SV_Unit_SalBoat'
SAL_BOAT_OBJ = 'SV_Obj_SalBoat'
SAL_BOAT_ROW = 'sv_fish_boat'                  # DT_SV_NpcMission row (shaped as Mission 22's aegs_common) -> NpcId SAL_BOAT_NPC
SAL_BOAT_ROW_TEMPLATE = 'aegs_common'
SAL_BOAT_NPC = 'VE027_boat2_01'                # the stock DT_NPC row (13.6 m fishing boat, MaxHealth 20)
SAL_BOAT_MIN_HEALTH = 1.0
SAL_BOAT_NAME_KEY = 'SV_SalBoat'               # its callsign's text (SAL) set by Lua (SV_SetText)
SAL_BOAT_SPOT = (1687842.0, -1191916.0, 300.0)
SAL_BOAT_YAW = 157.0                           # (any: it doesn't move)


def _fish_grounds():
    import math
    bx, by = SAL_BOAT_SPOT[0], SAL_BOAT_SPOT[1]
    out = [(FISH_KEYS[0], (bx, by))]
    ring = FISH_KEYS[1:]
    for i, k in enumerate(ring):
        a = 2 * math.pi * i / len(ring)
        out.append((k, (round(bx + FISH_RING_M * 100.0 * math.cos(a)), round(by + FISH_RING_M * 100.0 * math.sin(a)))))
    return [(k, (float(x), float(y))) for k, (x, y) in out]


FISH_GROUNDS = _fish_grounds()                 # [(key, (x, y) cm)]: A on SAL's boat, B-F on the ring
FISH_NPC_ROWS = [(SAL_BOAT_ROW, SAL_BOAT_ROW_TEMPLATE, SAL_BOAT_NPC)]   # build_survival.py build_npc_table (as SP_NPC_ROWS)


def fish_offsets(key):
    """Ground `key`'s FISH_PER_GROUND shoal offsets (dx, dy) cm from its unit's origin: within FISH_SPREAD_M (unit A's,
    on SAL's boat, FISH_INNER_MIN_M out at least), no two closer than FISH_GAP_M (spread wider where they fit), the same
    every build (a fixed seed per ground)."""
    import math, random
    rnd = random.Random('AC8SurvivalMode:fish:' + key)
    lo = (FISH_INNER_MIN_M / (FISH_SPREAD_M * 0.97)) ** 2 if key == FISH_KEYS[0] else 0.0
    for gap in (350.0, 300.0, 250.0, 200.0, FISH_GAP_M):
        for _ in range(400):
            pts = []
            for _ in range(5000):
                if len(pts) == FISH_PER_GROUND: break
                r = FISH_SPREAD_M * 0.97 * math.sqrt(lo + (1.0 - lo) * rnd.random())
                a = rnd.random() * 2 * math.pi
                p = (round(r * math.cos(a) * 100.0), round(r * math.sin(a) * 100.0))
                if all(math.dist(p, q) >= gap * 100.0 for q in pts): pts.append(p)
            if len(pts) == FISH_PER_GROUND: return [(float(x), float(y)) for x, y in pts]
    raise ValueError(key)


def fish_units():
    """[(ground key, unit, object base, (x, y) ground cm, [object points (x, y, z) cm])]: the shoals' units."""
    out = []
    for key, (gx, gy) in FISH_GROUNDS:
        pts = [(gx + dx, gy + dy, FISH_Z_CM) for dx, dy in fish_offsets(key)]
        out.append((key, f'SV_Unit_Fish{key}', f'SV_Obj_Fish{key}', (gx, gy), pts))
    return out


# THE FESTIVAL (round F+6, at sunset): three Tu-160 formations from the NORTH, WEST and SOUTH standing off 25 km out,
# each launching Mission 30's path-flown cruise missiles at the runway as it passes its launch point (Lua spawns them)
FEST_GROUPS = 'NWS'
FEST_BEARING = {'N': (0.0, -1.0), 'W': (-1.0, 0.0), 'S': (0.0, 1.0)}   # unit vector from the runway out to the group
FEST_ASIDE = {'N': (-1.0, 0.0), 'W': (0.0, 1.0), 'S': (-1.0, 0.0)}     # the racetrack's side (its outbound leg's offset)
FEST_LAUNCH_KM = 25.0                         # the launch points (the contract's): N (1610476, -2936142) W (-889524, -436142)
FEST_LAUNCH_Z_CM = 200000.0                   # S (1610476, 2063858), z 2 km: where Lua spawns each salvo
FEST_ZONE = ((-707336.0, -261895.0), 4000000.0)   # Survival's combat zone (Mission 22's): centre, half side cm
FEST_ENTRY_INSIDE_KM = 5.0                    # each formation enters this far inside the zone's edge on its bearing
FEST_ZONE_MARGIN_KM = 3.0                     # its path keeps inside Scripts/sv_ai.lua ZONE (the zone less 3 km: ZONE_KM)
FEST_TRACK_KM = (22.0, 29.0, 4.5)             # the racetrack: inner end, outer end (km from the runway), its turns' radius
FEST_INBOUND_KM = (29.0, 27.0, 25.0, 23.5, 22.0)   # its inbound leg's points: through the launch point (25 km) each lap
FEST_TURN_STEP_DEG = 22.5
FEST_RUNIN_STEP_KM = 3.0
FEST_LAPS = 15                                # every lap in the one path from its appearance (hard rule 54, LADON_LAPS)
FEST_NEAR_KM = 15.0                           # never nearer the runway than this
FEST_BOMBER_ALT_CM = 230000.0                 # 2.3 km: 300 m above the launch point (the salvo appears under them)
FEST_BOMBER_SPEED = '700.0'                   # km/h: ~40 deg of bank round a 4.5 km turn
FEST_SOURCE_UNIT = 'EA_Unit_01_Air2'          # Survival's 4-ship Tu-160 heavy flight (HEAVY_BOMBERS: copy_unit)
FEST_BOMBER_ROW = 't160_common'               # Mission 4's Tu-160 (NLID_1000: large aircraft); not in BOMBERS
FEST_BOMBERS_N = 4
FEST_FORMATION_CM = 30000.0                   # 300 m: lead, one beside it (outside the turns), a pair 300 m behind
FEST_AREA_M, FEST_ALT_M = 80000.0, (500.0, 6000.0)   # their unit areas over the whole zone (as the Ladons')
# the cruise missiles: Mission 30's path-flown SLCM (slcmp_ms30 -> OP0039_slcmp_01: an ordinary AI plane, 25 HP, boxed),
# its row imported as FEST_CM_ROW (no digit tail: hard rule 17), its unit (B_Unit_00_MainMissile_PathMove0_0: one
# object, no children) ported with FEST_CM_PER objects side by side, a box and the TGT mark; three salvo units a group
FEST_CM_SOURCE = ('/Game/Maps/Ingame/Mission030/WD_Mission030_global', 'B_Unit_00_MainMissile_PathMove0_0')
FEST_CM_ROW = 'sv_fest_cm'
FEST_CM_SOURCE_ROW = 'slcmp_ms30'
FEST_CM_SALVOS = 3
FEST_CM_PER = 4
FEST_CM_GAP_CM = 6000.0                       # 60 m apart, side by side across their way
FEST_CM_LANES = 'ABCD'                        # each missile's own path (lane), parallel: they don't fold onto one line
FEST_CM_SPEED = '600.0'                       # km/h (Mission 30's record)
FEST_CM_PROFILE = [(0.0, 2000.0), (1.5, 1850.0), (3.5, 1400.0), (5.5, 800.0), (7.5, 300.0), (9.5, 120.0),
                   (12.0, 100.0), (15.0, 100.0), (18.0, 100.0), (21.0, 100.0), (23.5, 100.0), (25.0, 100.0),
                   (26.5, 100.0)]             # (km along from the launch point to the runway and 1.5 km past, m up)
FEST_GROUND_CM = 500.0                        # (Comona is flat: sea 3.5 m, land 5 m; tallest on their way ~40 m trees)
# the searchlights: Online Mode's (C_011's GR053_seli_01 vehicle with its SystemObject_SearchLight child), allied, at four
# spots round the runway clear of buildings and trees (tools/checks/festival_lights_check.py); their Online Mode rows ride
# in the Alicorn's tables (build_survival.py ALCN_TABLES), which Lua adds to the campaign tables at the main menu
FEST_LIGHT_SOURCE = ('/Game/OnlineMode/Maps/CompetitiveCoop/C_011/WD_C_011_03', 'B_Ground_0', 'GR053_seli_01')
FEST_LIGHT_NPC = 'GR053_seli_01'              # its DT_NPC_ON row (ChildNPCId GR053_seli_light_01: the light itself)
FEST_LIGHT_ROW = 'sv_fest_light'              # DT_SV_NpcMission: C_011's GR053_seli_01 / GR053_seli_light_01 rows
FEST_BEAM_ROW = 'sv_fest_beam'
FEST_LIGHT_ROWS = [(FEST_LIGHT_ROW, 'GR053_seli_01'), (FEST_BEAM_ROW, 'GR053_seli_light_01')]
FEST_LIGHT_PART = 'SearchLight'               # the child's component
FEST_LIGHT_Z_CM = 500.0
FEST_LIGHTS = [  # (unit, object, km along the runway from its centre (+ ENE), km across it (+ SSE)): LCAC_RUNWAY's frame
    ('SV_Unit_FestLight_1', 'SV_Obj_FestLightA', -0.14, -0.38),     # north side, by the middle
    ('SV_Unit_FestLight_2', 'SV_Obj_FestLightB', -1.06, +0.53),     # past the WSW end, south side
    ('SV_Unit_FestLight_3', 'SV_Obj_FestLightC', +1.08, -0.50),     # past the ENE end, north side
    ('SV_Unit_FestLight_4', 'SV_Obj_FestLightD', +0.58, +0.38),     # the ENE half, south side
]


# (2026-11-07, the user: "Add some Allied Target Boxes in the town next to the airfield. "Valka" "Audrey" (these two allies
# should be next to each other as they are Girlfriends). Add other allied target box's like "Concert" "Market Stall"
# "Food Truck" and other things a Festival Might have"; "The units that the festival spawn can just be invincible dummies
# again") the festival in the town: one unit of Mission 22's invisible dummy (Unit_dummyN0 on dummy_common, as THE
# DECOY's marks) made allied, invincible and out of every attack, an object per box, each with its own callsign key
# (GameObjectDisplayNameID02, shown for an ally with bShowCallSignForAlly; the text set by Lua with SV_SetText:
# CFG.specials.festival.town), round FEST_TOWN_CENTRE, the town's densest houses just past the runway's WSW end
# (build/research's airport buildings, 2.2 km along it and 0.3 km south of its centre line on LCAC_RUNWAY's frame)
FEST_TOWN_UNIT, FEST_TOWN_OBJ = 'SV_Unit_FestTown', 'SV_Obj_FestTown'
FEST_TOWN_CENTRE = (-2.15, +0.30)             # km along / across the runway from its centre (LCAC_RUNWAY's frame)
FEST_TOWN_Z_CM = 800.0                         # 8 m up (the town's ground 3-5 m: its houses' footings), bIsLanding cleared
FEST_TOWN_BOXES = [  # (callsign key, metres along / across the runway from FEST_TOWN_CENTRE): the texts are Lua's
    ('SV_FestBox_Concert', 0.0, 0.0),
    ('SV_FestBox_Valka', -6.0, 45.0),          # VALKA and AUDREY side by side, 12 m apart, in front of the stage
    ('SV_FestBox_Audrey', 6.0, 45.0),
    ('SV_FestBox_Dance', 0.0, 95.0),
    ('SV_FestBox_Market', 70.0, -30.0),
    ('SV_FestBox_Market', 92.0, -30.0),
    ('SV_FestBox_Market', 114.0, -30.0),
    ('SV_FestBox_FoodTruck', -80.0, -40.0),
    ('SV_FestBox_FoodTruck', -105.0, -40.0),
    ('SV_FestBox_FishGrill', 60.0, 75.0),
    ('SV_FestBox_Dessert', -70.0, 65.0),
    ('SV_FestBox_Lanterns', 145.0, 20.0),
    ('SV_FestBox_RingToss', 40.0, -105.0),
    ('SV_FestBox_Soup', -145.0, 10.0),
    ('SV_FestBox_Fireworks', -40.0, -155.0),
]
FEST_TOWN_KEYS = sorted({k for k, _, _ in FEST_TOWN_BOXES})


def fest_town():
    """[(callsign key, (x, y, z) cm)]: FEST_TOWN_BOXES on the runway frame round FEST_TOWN_CENTRE, in order (the unit's
    objects SV_Obj_FestTown_0 ..)."""
    import math
    (rx, ry), ryaw = LCAC_RUNWAY
    ux, uy = math.cos(math.radians(ryaw)), math.sin(math.radians(ryaw))
    out = []
    for key, al_m, ac_m in FEST_TOWN_BOXES:
        al, ac = FEST_TOWN_CENTRE[0] + al_m / 1000.0, FEST_TOWN_CENTRE[1] + ac_m / 1000.0
        out.append((key, (round(rx + (al * ux - ac * uy) * 1e5, 1), round(ry + (al * uy + ac * ux) * 1e5, 1), FEST_TOWN_Z_CM)))
    return out


def fest_lights():
    """[(unit, object, (x, y, z) cm, yaw deg)]: FEST_LIGHTS on Mission 22's runway frame (as defence_ciws), along it."""
    import math
    (rx, ry), ryaw = LCAC_RUNWAY
    ux, uy = math.cos(math.radians(ryaw)), math.sin(math.radians(ryaw))
    return [(unit, obj, (rx + (al * ux - ac * uy) * 1e5, ry + (al * uy + ac * ux) * 1e5, FEST_LIGHT_Z_CM), ryaw)
            for unit, obj, al, ac in FEST_LIGHTS]


def _fest_frame(g):
    """(at(r_km, a_km, z) -> (x, y, z) cm, u, p): group g's frame, r km out from the runway on its bearing, a km aside."""
    (ux, uy), (px, py) = FEST_BEARING[g], FEST_ASIDE[g]
    return ((lambda r, a, zz: (FISH_RWY[0] + (r * ux + a * px) * 1e5, FISH_RWY[1] + (r * uy + a * py) * 1e5, zz)),
            (ux, uy), (px, py))


def fest_launch(g):
    """Group g's launch point (x, y, z) cm."""
    at, _, _ = _fest_frame(g)
    return at(FEST_LAUNCH_KM, 0.0, FEST_LAUNCH_Z_CM)


def fest_yaw(g):
    """The heading (UE yaw, deg) from group g's launch point to the runway: its salvos' yaw (and its run in's)."""
    import math
    ux, uy = FEST_BEARING[g]
    return math.degrees(math.atan2(-uy, -ux)) + 0.0          # (+ 0.0: W's -0.0 a plain 0)


def fest_entry_km(g):
    """Km out from the runway where group g enters: FEST_ENTRY_INSIDE_KM inside the zone's edge on its bearing."""
    (cx, cy), half = FEST_ZONE
    ux, uy = FEST_BEARING[g]
    edge = (cx + half * ux - FISH_RWY[0]) * ux if ux else (cy + half * uy - FISH_RWY[1]) * uy
    return edge / 1e5 - FEST_ENTRY_INSIDE_KM


def fest_track(g, side_km=0.0):
    """Group g's path: the run in from its entry along its bearing, then FEST_LAPS laps of its racetrack, each lap's
    inbound leg through the launch point; side_km: a lane that far outside the track (the formation's outer aircraft).
    -> (points (x, y, z) cm, the next lap's first point: the path's `after`)."""
    import math
    at, _, _ = _fest_frame(g)
    r_in, r_out, rad = FEST_TRACK_KM
    entry = fest_entry_km(g)
    runin = [entry]
    while runin[-1] - FEST_RUNIN_STEP_KM > FEST_INBOUND_KM[0] + 1.0: runin.append(runin[-1] - FEST_RUNIN_STEP_KM)
    n = int(round(180.0 / FEST_TURN_STEP_DEG))
    step = [math.radians(k * FEST_TURN_STEP_DEG) for k in range(1, n)]
    inner = [(r_in - rad * math.sin(t), rad - rad * math.cos(t)) for t in step]
    outbound = [(r, 2 * rad) for r in reversed(FEST_INBOUND_KM)]
    outer = [(r_out + rad * math.sin(t), rad + rad * math.cos(t)) for t in step]
    inbound = [(r, 0.0) for r in FEST_INBOUND_KM]
    lap = inner + outbound + outer + inbound
    ra = [(r, 0.0) for r in runin] + inbound + lap * FEST_LAPS + inner[:1]
    if side_km:                     # the lane outside the track: each point side_km off along the way's outward normal
        moved = []
        for k, (r, a) in enumerate(ra):
            (r0, a0), (r1, a1) = ra[max(k - 1, 0)], ra[min(k + 1, len(ra) - 1)]
            dr, da = r1 - r0, a1 - a0
            n_ = math.hypot(dr, da) or 1.0
            moved.append((r + side_km * (-da / n_), a + side_km * (dr / n_)))
        ra = moved
    pts = [at(r, a, FEST_BOMBER_ALT_CM) for r, a in ra]
    return pts[:-1], pts[-1]


def fest_bombers():
    """[{g, unit, obj, objs, path, side_path, ev, up, run, entry, yaw, points (each aircraft's spawn), lanes}]."""
    out = []
    for g in FEST_GROUPS:
        at, _, _ = _fest_frame(g)
        e, d = fest_entry_km(g), FEST_FORMATION_CM / 1e5
        z = FEST_BOMBER_ALT_CM
        pts = [at(e, 0.0, z), at(e, -d, z),            # the lead, and beside it outside the track (its side lane)
               at(e + d, 0.0, z), at(e + d, -d, z)]    # a pair 300 m behind them
        obj = f'SV_Obj_Fest{g}'
        out.append({'g': g, 'unit': f'SV_Unit_Fest{g}', 'obj': obj, 'objs': [f'{obj}_{k}' for k in range(FEST_BOMBERS_N)],
                    'path': f'SV_Path_Fest_{g}', 'side_path': f'SV_Path_Fest_{g}R', 'ev': f'RE_SV_FestUp_{g}',
                    'up': f'SV_FestUp{g}', 'run': f'SV_FestRun{g}', 'entry': pts[0], 'yaw': fest_yaw(g), 'points': pts,
                    'lanes': ['path', 'side_path', 'path', 'side_path']})
    return out


def fest_missiles():
    """[{g, k, unit, obj, objs, ev, hits, lanes: [(path, [points])] one per missile, points (each one's spawn), launch,
    yaw}]: the salvo units, three a group on the same four lanes."""
    out = []
    for g in FEST_GROUPS:
        at, _, _ = _fest_frame(g)
        offs = [(i - (FEST_CM_PER - 1) / 2.0) * FEST_CM_GAP_CM / 1e5 for i in range(FEST_CM_PER)]   # km aside
        lanes = []
        for L, a in zip(FEST_CM_LANES, offs):
            pts = [at(FEST_LAUNCH_KM - km, a, FEST_LAUNCH_Z_CM if km == 0.0 else FEST_GROUND_CM + m * 100.0)
                   for km, m in FEST_CM_PROFILE]
            lanes.append((f'SV_Path_FestCM_{g}{L}', pts))
        spawn = [lane[1][0] for lane in lanes]
        for k in range(1, FEST_CM_SALVOS + 1):
            obj = f'SV_Obj_FestCM_{g}{k}'
            out.append({'g': g, 'k': k, 'unit': f'SV_Unit_FestCM_{g}{k}', 'obj': obj,
                        'objs': [f'{obj}_{i}' for i in range(FEST_CM_PER)], 'ev': f'RE_SV_FestCM_{g}{k}',
                        'hits': [f'RE_SV_FestCMHit_{g}{k}_{i}' for i in range(FEST_CM_PER)],
                        'lanes': lanes, 'points': spawn, 'launch': fest_launch(g), 'yaw': fest_yaw(g)})
    return out


INT_FLAGS += [f'SV_FestRun{g}' for g in FEST_GROUPS]   # a formation's path started (build_festival: once a spawn)


def build_festival(g, flag, stock_ep):
    """THE FESTIVAL's records (FEST_*). Each formation: its appearance (SV_FestUp<g>) and Lua's RE_SV_FestUp_<g> (the same:
    a unit that appears while the player is in the landing menu gets no appearance trigger) -> gear up, engagement None
    (Mission 22's finale flight's order on its unit) and, once a spawn (SV_FestRun<g>: 1 from 1.5 s to 10 s after the
    first), its path from its entry: the unit and each aircraft on its lane, as Mission 22's RE_Wave2_AreaB_PathSet sends a
    strike flight (the unit and its lead one path, the others theirs). Each salvo RE_SV_FestCM_<g><k> (Lua, right after it
    spawns the salvo's unit at the launch point): Mission 30's path-flown missile records on each missile (its own lane
    from the launch point to the runway, engagement None, look-ahead 0; Mission 30's LiveReinforcementExecution is Lua's
    SV_Spawn, its counters left out). RE_SV_FestCMHit_<g><k>_<i> (Lua, on the host, as missile i nears the runway):
    Mission 22's LiveDestroyUnitExecution on that missile."""
    m16 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission016', 'EP_Mission016_global.uasset')
    m30 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission030', 'EP_Mission030_global.uasset')
    t_path = g.foreign_template(m16, 'LiveAIPathExecution', 'PathFinish_Ladon0_0', lambda a, e: a[0] == 'B_Obj_01_Air0_Ladon0')
    t_upath = g.exec_template('LiveAIPathExecution', 'RE_Wave2_AreaB_PathSet', lambda a, e: a[1] == 'ERB_Unit_01_Air2')
    t_gear_up = g.exec_template('LiveEnableLandingGear', '01_A_Air1_f18e_PathFinish_3')
    t_eng = g.exec_template('LiveAIEngagementOrder', 'RE_Wave6_AllyFly', lambda a, e: a[1] == 'AA_Unit_01_Air0')
    assert arg_values(t_path)[1] == 'NoneSelect' and arg_values(t_path)[9] == 'false', arg_values(t_path)
    assert arg_values(t_upath)[0] == 'NoneSelect' and arg_values(t_upath)[9] == 'false', arg_values(t_upath)
    assert arg_values(t_gear_up)[3] == 'false', arg_values(t_gear_up)
    assert arg_values(t_eng)[:4] == ['NoneSelect', 'AA_Unit_01_Air0', 'NoneSelect', 'None'], arg_values(t_eng)
    m30ev, obj30 = 'RemoteEvent_Spawn_MainMissile_PathMove0_0', 'B_Obj_00_MainMissile_PathMove0_slcmp_0'
    t_cpath = g.foreign_template(m30, 'LiveAIPathExecution', m30ev, lambda a, e: a[0] == obj30)
    t_ceng = g.foreign_template(m30, 'LiveAIEngagementOrder', m30ev, lambda a, e: a[0] == obj30)
    t_clook = g.foreign_template(m30, 'LiveSetLookAheadTimeSec', m30ev, lambda a, e: a[0] == obj30)
    assert arg_values(t_cpath)[2] == '01_Slcmp_Path0' and float(arg_values(t_cpath)[4]) == float(FEST_CM_SPEED), arg_values(t_cpath)
    assert arg_values(t_ceng)[3] == 'None' and arg_values(t_clook)[3] == '0', (arg_values(t_ceng), arg_values(t_clook))
    t_remove = g.exec_template('LiveDestroyUnitExecution', 'Debug_Destroy_Shuttle')
    assert arg_values(t_remove)[:3] == ['NoneSelect', 'NoneSelect', 'AA_Obj_01_Ground0_Shuttle_0'], arg_values(t_remove)
    n_trig, n_ex = len(g.trig), len(g.ex)
    for F in fest_bombers():
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', F['up'], arg_changes={0: F['unit']})
        g.trigger('RE_SpawnEnemy_kokatu_1st', F['ev'])                       # (a remote event Lua fires)
        for ev in (F['up'], F['ev']):
            once = lambda: [g.cond(F['run'], 'Leq', 0)]
            for o in F['objs']:
                g.execute(t_gear_up, ev, {0: o}, delay=0.5)
            g.execute(t_eng, ev, {1: F['unit']}, delay=0.5)
            g.execute(t_upath, ev, {1: F['unit'], 2: F['path'], 4: FEST_BOMBER_SPEED}, delay=1.0, conds=once())
            for o, lane in zip(F['objs'], F['lanes']):
                g.execute(t_path, ev, {0: o, 2: F[lane], 4: FEST_BOMBER_SPEED}, delay=1.0, conds=once())
            flag(ev, F['run'], 'Set', 1, delay=1.5)
            flag(ev, F['run'], 'Set', 0, delay=10.0)
    for M in fest_missiles():
        g.trigger('RE_SpawnEnemy_kokatu_1st', M['ev'])
        for o, (lane, _) in zip(M['objs'], M['lanes']):
            g.execute(t_cpath, M['ev'], {0: o, 2: lane}, delay=0.3)
            g.execute(t_ceng, M['ev'], {0: o}, delay=0.3)
            g.execute(t_clook, M['ev'], {0: o}, delay=0.3)
        for o, hit in zip(M['objs'], M['hits']):
            g.trigger('RE_SpawnEnemy_kokatu_1st', hit)
            g.execute(t_remove, hit, {2: o})
    print(f'  festival: {len(FEST_GROUPS)} Tu-160 formations (RE_SV_FestUp_<g> / SV_FestUp<g>, {FEST_BOMBER_SPEED} km/h, '
          f'{FEST_LAPS} laps a path), {len(fest_missiles())} cruise missile salvos of {FEST_CM_PER} (RE_SV_FestCM_<g><k>, '
          f'RE_SV_FestCMHit_<g><k>_<i>, {FEST_CM_SPEED} km/h): {len(g.trig) - n_trig} triggers, {len(g.ex) - n_ex} execs')


def build_tanicorn(g, stock_ep):
    """THE TANICORN's test mount (TANI_*; docs/re/TANICORN.md): as it appears, Mission 16's Normal / PlayerFirst
    engagement order on its object (the Ladon's CIWS order, the Spaceport turrets' (build_spaceport): a turret engages only
    when ordered: the user's run of 0.74.46 had it up, hit and killed, never firing)."""
    m16 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission016', 'EP_Mission016_global.uasset')
    t_part = g.foreign_template(m16, 'LiveAIEngagementOrder', 'Default_RemoteEvent_20',
                                lambda a, e: a[0] == 'B_Obj_01_Air0_Ladon0_LCIWS')
    assert arg_values(t_part)[3] == 'Normal' and arg_values(t_part)[6] == 'PlayerFirst', arg_values(t_part)
    up = 'SV_TaniUp'
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: TANI_UNIT})
    g.execute(t_part, up, {0: TANI_OBJ}, delay=1.0)
    print(f'  tanicorn: {TANI_OBJ} ordered as it appears ({up}: Normal, PlayerFirst)')
    for m in TANI_MOUNTS:                    # (0.74.61) the other gun mounts, the same way (TANI_MOUNTS)
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', m['up'], arg_changes={0: m['unit']})
        g.execute(t_part, m['up'], {0: m['obj']}, delay=1.0)
        print(f'  tanicorn: {m["obj"]} ({m["part"]}) ordered as it appears ({m["up"]}: Normal, PlayerFirst)')
    # (2026-11-11, WP2 step 2) the live hull's parts (TANI_LIVE): each its own order by name TANI_LIVE_ORDER_S after the hull
    # appears, as the Spaceport's turrets get theirs (build_spaceport); names only, so in every build
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', TANI_HULL_LIVE_UP, arg_changes={0: TANI_HULL_LIVE_UNIT})
    for p in TANI_LIVE:
        g.execute(t_part, TANI_HULL_LIVE_UP, {0: p['obj']}, delay=TANI_LIVE_ORDER_S)
    print(f'  tanicorn: {TANI_HULL_LIVE_UNIT}\'s {len(TANI_LIVE)} live parts ordered by name {TANI_LIVE_ORDER_S} s after it '
          f'appears ({TANI_HULL_LIVE_UP}: Normal, PlayerFirst)'
          + ('' if TANI_WD else '; names only: this build has no live parts (TANI unset)'))

