"""survival_events_escort.py : THE ESCORT, the ZFA-44 cargo ships and THE DECOY (2026-11-06): names, shapes and events.

ESC_* (CHARLENE, her escorts, the runway's paths and parking; ESC_START and ESC_ESCORTS are in
survival_events.py: tools/checks/escort_test.lua reads them there), CARGO_* / ZFA_* (the cargo ships and
their ZFA-44 launches), DECOY_* (the bait, the trap UAVs, the Spear) and build_escort / build_decoy.

A part of tools/survival_events.py (its docstring has the layout): every name survival_events defines is
here through the import below, and survival_events imports this part back whole, so each name here is
survival_events.<name> too (build_survival.py and tools/checks read them so). Import survival_events, not this file.
"""
from survival_events import *  # noqa: F401,F403 (survival_events' names; it imports this part at its end)


# ---------------------------------------------------------------- THE ESCORT (CHARLENE) and THE DECOY (2026-11-06)
# The build contracts of 2026-11-06 (THE ESCORT: CHARLENE, her four escorts and the ZFA-44 cargo ships; THE DECOY: the
# Tonitrus Spear trap). Research: build/research/escort/ESCORT.md, build/research/decoy/DECOY.md. tools/re/ESCORT.md and
# tools/re/DECOY.md "Build names" list everything below. Coordinates UE cm, north = -Y, east = +X. The Lua (sv_escort.lua,
# sv_decoy.lua) spawns every unit and fires every remote event; nothing here spawns at the level's start.
#
# THE ESCORT. Runway 07/25 in tools/re/COMONA_MAP.md 6's frame: t m along it from the paved mesh's origin (+ ENE, runway
# 07's landing direction), s m across it (+ SSE, the parallel taxiway's side). Everything lands on runway 07 (heading 067).
ESC_RWY_O = (1609740.0, -435830.0)
ESC_RWY_U = (0.92050, -0.39073)
ESC_RWY_S = (0.39073, 0.92050)
ESC_GROUND_Z = 750.0                    # MOONCHILD's runway paths' height (z 7.5 m: an AI plane holds the runway on them)
ESC_THRESH_T = (-742.0, 758.0)          # the thresholds: west (1541439, -406838), east (1679514, -465447)
ESC_TOUCH_T = -442.0                    # touchdown: 300 m past the west threshold (the contract's zone: 150-600 m)
ESC_GLIDE_DEG = 3.0
ESC_FINAL_KM = (16.0, 14.0, 12.0, 10.0, 8.0, 6.0, 4.5, 3.0, 2.0, 1.2, 0.6, 0.3, 0.15, 0.0)   # km before touchdown
ESC_FLARE_M = {0.15: 11.0, 0.0: 7.5}    # the last 150 m flatter than the slope (the flare), then the runway's 7.5 m
ESC_ROLL_T = (-402.0, 638.0)            # the rollout: 40 m past touchdown to 120 m short of the east threshold
ESC_ROLL_STEP_M = 130.0
# ESC_START (the contract's start): survival_events.py (tools/checks/escort_test.lua reads it there)
ESC_ROUTE_STEP_KM = 5.0
ESC_ROUTE_SHORT_KM = 1.5                # each route ends this far short of its IAF, so the next path starts ahead (rule 2)
ESC_AREA_M, ESC_ALT_M = 80000.0, (0.0, 12000.0)   # their unit areas over the whole way (the Ladons' / festival's way)
# CHARLENE: one allied B-1B on mission row ESC_CHAR_ROW (Mission 22's e767_common shape: KeepMinHeight 0, as VOID
# WATCHER's, which taxied, rolled and took off on these runway paths) naming the stock DT_NPC row OP0008_b01b_Ally_01
# (NLID_1000 large aircraft, flares and bombs; nothing for Lua to add), her health raised by the mission row's
# MaxHealthDifference (in MaxHealth HP: the B-1's 130 + ESC_CHAR_HEALTH_ADD). Her desc is Mission 14's escorted C-130's
# (Air_Unit_c130_0: the unit an escort target, bIsEscortedUnit; the object's Attention mark, callsign shown for an ally,
# visible at any distance), its wing parts left out, her callsign SV_CharleneCall on it (2026-11-07: SV_Charlene was her
# mission row's name sv_charlene but for case, and an FName keeps its first casing: her box read "sv_charlene").
ESC_CHAR_SOURCE = ('/Game/Maps/Ingame/Mission014/WD_Mission014_global', 'Air_Unit_c130_0')
ESC_CHAR_UNIT, ESC_CHAR_OBJ = 'SV_Unit_Charlene', 'SV_Obj_Charlene'
ESC_CHAR_ROW, ESC_CHAR_ROW_TEMPLATE, ESC_CHAR_NPC = 'sv_charlene', 'e767_common', 'OP0008_b01b_Ally_01'
ESC_CHAR_NAME_KEY = 'SV_CharleneCall'
ESC_CHAR_HEALTH_ADD = 170.0             # 130 + 170 = 300 HP (Lua may set her health at spawn on top)
# ESC_ESCORTS (her four escorts): survival_events.py (tools/checks/escort_test.lua reads them there)
# Survival's allied rows: DT_SV_NpcMission row -> (DT_SV_NpcRows row, its stock DT_NPC source, the allied model). The DT_NPC
# rows are copies of the campaign's plain enemy rows on the allied model (no skin row: the model's own look), flying
# MOONCHILD's behaviour set (its row's LuaSet, NLID_0003_CP; never NLID_0400_CP: hard rule 22). Lua adds them to DT_NPC at
# the main menu (hard rule 20: before the level loads).
ESC_ROWS = {'sv_esc_su57': ('SV_Esc_Su57', 'OP1021_su57_01', 'OP1021_su57_Ally'),
            'sv_esc_su33': ('SV_Esc_Su33', 'OP1030_su33_01', 'OP1030_su33_Ally'),
            'sv_esc_su35': ('SV_Esc_Su35', 'OP1028_su35_01', 'OP1028_su35_Ally')}
ESC_ROW_TEMPLATE = 'f18e_common'        # (MOONCHILD's mission row's shape)
# speeds, km/h (ESCORT.md 1.2's table: Mission 14's landing values; the B-1's SpeedMin 300 and the Su-57's 750 are the
# models', a path's speed overrides them as MOONCHILD's 50 km/h taxi does)
# ((2026-11-08) the user: "Bump Charlene, Yorke, Rock, Danielle, Ali's landing speeds up to 600") every landing speed
# (her slowed route, the escorts' circuit, the final and its two slow-downs near the runway) at 600 km/h, the route's;
# was 450 / 450 / 320 / 280 / 260
ESC_SPEED = {'route': '600.0', 'cruise_slow': '600.0', 'circuit': '600.0', 'final': '600.0', 'final_slow': '600.0',
             'final_short': '600.0', 'roll': '50.0', 'taxi': '30.0'}
ESC_FINAL_ACCEL = '30.0'                # Mission 14's descent record (225 km/h, accel 30)
# the touchdown record's braking, m/s^2 (Mission 14's 2.7: DANIELLE's roll of 2026-11-07 lost ~10 km/h a second, 197 ->
# 50). From 600 km/h at 2.7 the roll is ~5 km and the rollout path (ESC_ROLL_T) 1,040 m: at 16 it's ~860 m, ~9.5 s
ESC_ROLL_ACCEL = '16.0'
# (2026-11-07, Alyssa's test: the escorts' wait-circle paths began 8-12 km round the circle from where they were, so
# they never took them, and flew off; CHARLENE was given a new path for her final mid-route and didn't take it either.)
# The escorts' wait: a hold over CHARLENE (their unit area onto her at ESC_HOLD_RADIUS_M, no path: the Guard record's
# way), then, one at a time once she's down, the landing circuit: one shared path from over the runway's east end north
# of it, downwind (WSW) ESC_CIRC_S m across at ESC_CIRC_Z_M, a half-circle base turn of ESC_CIRC_R_M onto the extended
# centre line ESC_CIRC_TURN_T m along it, the 3 deg final and the rollout (the path given again at each new speed after,
# Mission 14's way). Lua starts it only with its first point a little ahead of the escort (hard rule 2).
# ((2026-11-07, the user: "The Landing for Yorke, Charlene, Rock, Ali and Danielle takes WAY TOO long") the circuit cut
# from ~26 km (start 3 km past the origin 3 km north, downwind to -9 km, a 1.5 km base turn, a 9 km final) to ~14 km:
# start 1.5 km past the origin 2 km north, downwind to -5 km, a 1 km turn, a 4.6 km final; Lua's CFG.specials.escort.
# geo.circuit_start is its first point, esc_rwy(ESC_CIRC_START_T, ESC_CIRC_S, ESC_CIRC_Z_M * 100))
ESC_HOLD_RADIUS_M = 4000.0
ESC_PATH_CIRCUIT = 'SV_Path_EscCircuit'
ESC_CIRC_S, ESC_CIRC_Z_M, ESC_CIRC_R_M = -2000.0, 600.0, 1000.0
ESC_CIRC_START_T, ESC_CIRC_TURN_T, ESC_CIRC_STEP_M = 1500.0, -5000.0, 1500.0
# the shared paths (the contract's) and the parking: five slots on the parallel taxiway (s 62.5: MOONCHILD's taxi line),
# taken in landing order (SV_EscortSlots), the first lander the farthest west, so nobody taxis past a parked aircraft;
# each 36-62 m from every building or prop box (tools/checks/festival_lights_data.json)
# her route (SV_Path_CharRoute) runs on into the final and the rollout (one path); SV_Path_CharFinal is the final and the
# rollout alone, for the landing test T0 (Ctrl+F5: her spawned before the IAF)
ESC_PATH_ROUTE, ESC_PATH_FINAL = 'SV_Path_CharRoute', 'SV_Path_CharFinal'
ESC_TAXI_S = 62.5
ESC_TAXI_FIRST_T = 660.0                # the taxi's first point: 22 m past the rollout's end, then MOONCHILD's taxi backwards
ESC_TAXI_STEP_M = 80.0
ESC_SLOTS = (('A', 90.0), ('B', 170.0), ('C', 250.0), ('D', 330.0), ('E', 410.0))   # (slot, t m)
ESC_STOP_M = (3.0, 21.0)                # a stop path: from 3 m past the slot 18 m on west (Mission 26's 18 m stop path)
ESC_GUARD_RADIUS_M = 3000.0             # RE_SV_Esc<Name>Guard: the escort's area onto her (Mission 14's way, 1-3 km)


def esc_rwy(t, s=0.0, z=ESC_GROUND_Z):
    """(x, y, z) cm of the point t m along runway 07/25 from the paved mesh's origin (+ ENE) and s m across it (+ SSE)."""
    return (ESC_RWY_O[0] + 100.0 * (ESC_RWY_U[0] * t + ESC_RWY_S[0] * s),
            ESC_RWY_O[1] + 100.0 * (ESC_RWY_U[1] * t + ESC_RWY_S[1] * s), z)


def esc_glide_cm(d_km):
    """The final's height (cm) d_km before touchdown: the 3 deg slope over the runway's 7.5 m, the flare at the end."""
    import math
    if d_km in ESC_FLARE_M: return ESC_FLARE_M[d_km] * 100.0
    return 100.0 * (7.5 + 1000.0 * d_km * math.tan(math.radians(ESC_GLIDE_DEG)))


def esc_final_pts():
    """SV_Path_CharFinal: the IAF (16 km out, 846 m) down the 3 deg slope to touchdown, on the extended centre line."""
    return [esc_rwy(ESC_TOUCH_T - 1000.0 * d, 0.0, esc_glide_cm(d)) for d in ESC_FINAL_KM]


def esc_roll_pts():
    """The rollout along the centre line at the runway's height (the end of her path, T0's and the circuit's)."""
    t0, t1 = ESC_ROLL_T
    n = max(1, int(round((t1 - t0) / ESC_ROLL_STEP_M)))
    return [esc_rwy(t0 + (t1 - t0) * k / n) for k in range(n + 1)]


def esc_route_pts(right_km=0.0, up_km=0.0):
    """CHARLENE's route (the start to ESC_ROUTE_SHORT_KM short of the IAF, straight over open sea, descending from 3 km to
    the IAF's 846 m), or an escort's: the same, right_km to her right and up_km above. -> (points cm, the point after)."""
    import math
    s, e = ESC_START, esc_final_pts()[0]
    dx, dy = e[0] - s[0], e[1] - s[1]
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    rx, ry = -uy, ux                                       # (right of the way, north being -y)
    end = L - ESC_ROUTE_SHORT_KM * 1e5
    n = max(1, int(math.ceil(end / (ESC_ROUTE_STEP_KM * 1e5))))
    at = lambda d: (s[0] + ux * d + rx * right_km * 1e5, s[1] + uy * d + ry * right_km * 1e5,
                    s[2] + (e[2] - s[2]) * d / L + up_km * 1e5)
    return [at(end * k / n) for k in range(n + 1)], at(L)


def esc_char_pts():
    """SV_Path_CharRoute: her route, the final from the IAF and the rollout, one path. -> (points cm, the point after)."""
    route, _ = esc_route_pts()
    roll = esc_roll_pts()
    after = esc_rwy(ESC_ROLL_T[1] + ESC_ROLL_STEP_M)
    return route + esc_final_pts() + roll[1:], after


def esc_t0_pts():
    """SV_Path_CharFinal (the landing test T0's): the final from the IAF and the rollout. -> (points, before, after)."""
    final = esc_final_pts()
    t_iaf = ESC_TOUCH_T - 1000.0 * ESC_FINAL_KM[0]
    return final + esc_roll_pts()[1:], esc_rwy(t_iaf - 2000.0, 0.0, final[0][2]), esc_rwy(ESC_ROLL_T[1] + ESC_ROLL_STEP_M)


def esc_circuit_pts():
    """SV_Path_EscCircuit: downwind (WSW, north of the runway), the base turn, the final and the rollout.
    -> (points cm, before, after)."""
    import math
    z = ESC_CIRC_Z_M * 100.0
    pts, t = [], ESC_CIRC_START_T
    while t > ESC_CIRC_TURN_T + 1.0:
        pts.append(esc_rwy(t, ESC_CIRC_S, z))
        t -= ESC_CIRC_STEP_M
    d_end = (ESC_TOUCH_T - ESC_CIRC_TURN_T) / 1000.0           # km before touchdown where the turn ends
    z_end = esc_glide_cm(d_end)
    tc, sc, R = ESC_CIRC_TURN_T, ESC_CIRC_S + ESC_CIRC_R_M, ESC_CIRC_R_M
    for k in range(0, 7):                                       # (the half circle from the downwind onto the centre line)
        th = math.pi * k / 6.0
        pts.append(esc_rwy(tc - R * math.sin(th), sc - R * math.cos(th), z + (z_end - z) * k / 6.0))
    pts += [esc_rwy(ESC_TOUCH_T - 1000.0 * d, 0.0, esc_glide_cm(d)) for d in ESC_FINAL_KM if d < d_end - 0.5]
    pts += esc_roll_pts()[1:]
    return pts, esc_rwy(ESC_CIRC_START_T + ESC_CIRC_STEP_M, ESC_CIRC_S, z), esc_rwy(ESC_ROLL_T[1] + ESC_ROLL_STEP_M)


def esc_orbit():
    """(unused since 2026-11-07: the escorts hold over her) The old wait circle: {'touch' (cm), 'centre' (cm), 'pt' (psi deg round from the touching point, along the way
    -> cm)}. At psi 0 its way is runway 07's heading (asserted)."""
    import math
    T = esc_rwy(ESC_TOUCH_T - 1000.0 * ESC_ORBIT_T_KM, 0.0, ESC_ORBIT_ALT_KM * 1e5)
    R = ESC_ORBIT_KM * 1e5
    C = (T[0] - ESC_RWY_S[0] * R, T[1] - ESC_RWY_S[1] * R)          # (north of the centre line)
    a0 = math.atan2(T[1] - C[1], T[0] - C[0])
    pt = lambda psi: (C[0] + R * math.cos(a0 - math.radians(psi)), C[1] + R * math.sin(a0 - math.radians(psi)), T[2])
    d = (math.sin(a0), -math.cos(a0))                               # d pt / d psi at psi 0
    assert abs(d[0] - ESC_RWY_U[0]) < 1e-3 and abs(d[1] - ESC_RWY_U[1]) < 1e-3, ('the escort orbit runs the wrong way', d)
    return dict(touch=T, centre=C, pt=pt)


def esc_orbit_pts(name):
    """Escort `name`'s orbit path: ESC_ORBIT_LAPS laps from its phase, ending a step short of its start's last lap (so a
    restart at its end begins a step ahead). -> (points, before, after)."""
    o = esc_orbit()
    ph, st = ESC_ORBIT_PHASE_DEG[name], ESC_ORBIT_STEP_DEG
    n = int(round(360.0 * ESC_ORBIT_LAPS / st))
    return [o['pt'](ph + st * k) for k in range(n)], o['pt'](ph - st), o['pt'](ph + st * n)


def esc_aircraft():
    """CHARLENE and her escorts: [{key, unit, obj, row, name_key, leg (flag), slot (flag), legs {step: n}, route, orbit
    (always None since 2026-11-07: the escorts hold over her, leg 'orbit' the hold), right_km, up_km, ev (remote event
    prefix), up (appearance trigger)}]."""
    out = [dict(key='Char', unit=ESC_CHAR_UNIT, obj=ESC_CHAR_OBJ, row=ESC_CHAR_ROW, name_key=ESC_CHAR_NAME_KEY,
                leg='SV_CharLeg', slot='SV_TaxiSlotChar', legs={'route': 1, 'final': 2, 'roll': 3, 'taxi': 4, 'stop': 5},
                route=ESC_PATH_ROUTE, orbit=None, right_km=0.0, up_km=0.0, ev='RE_SV_Char', up='SV_CharUp', escort=False)]
    for name, row, right, up in ESC_ESCORTS:
        out.append(dict(key=name, unit=f'SV_Unit_Esc{name}', obj=f'SV_Obj_Esc{name}', row=row, name_key=f'SV_{name}',
                        leg=f'SV_EscLeg{name}', slot=f'SV_TaxiSlot{name}',
                        legs={'route': 1, 'orbit': 2, 'final': 3, 'roll': 4, 'taxi': 5, 'stop': 6},
                        route=f'SV_Path_EscRoute_{name}', orbit=None, right_km=right, up_km=up,
                        ev=f'RE_SV_Esc{name}', up=f'SV_EscUp{name}', escort=True))
    return out


# The ZFA-44 cargo ships (the escort's unlock; user, 2026-11-06: launched from the ships' container launchers as Mission
# 17's drones are): Mission 17's container ship (VE021_ctslf), its hull with its two container launchers and its Stinger
# mount, allied (Faction 1: the Spaceport fleet's enemy_unit the other way), its callsign SV_Cargo. Each launcher's six
# spawner arms (WN_WEAPON_1..6, its fire control's AllArms order: hard rule 40) each name a world-data unit by exact name
# (LiveFCSModule_ProjectileSpawnerFromWorldData, Mission 17's E_Unit_01_drone_<k>_<m>, not spawned at the level's start: the
# arm spawns it), so Survival's world data has units of exactly those names holding the ZFA-44 hosts. The three launcher
# variants name 18 different units, six each; a ship carries two variants (its hull's components), ship 1 01 + 02 and ship
# 2 02 + 03, and each ship fires only its own variant (ship 1 cntus_01, ship 2 cntus_03; cntus_02, on both, is never
# fired: the same arm on both ships would pull the same unit).
CARGO_SOURCE_WD = '/Game/Maps/Ingame/Mission017/WD_Mission017_global'
CARGO_SHIPS = [  # (s, unit, object, mission row, Mission 17's mission row, Mission 17's unit, spot cm, yaw, launcher fired)
    (1, 'SV_Unit_Cargo1', 'SV_Obj_Cargo1', 'sv_cargo_a', 'VE021_ctslf_01', '01_Unit_FaekShip_Spwan5',
     (1270476.0, -1096142.0, 50.0), -23.0, 'BP_VE021_ctslf_cntus_01_CP'),
    (2, 'SV_Unit_Cargo2', 'SV_Obj_Cargo2', 'sv_cargo_b', 'VE021_ctslf_03', '01_Unit_FaekShip_Spwan3',
     (2130476.0, 103858.0, 50.0), -23.0, 'BP_VE021_ctslf_cntus_03_CP'),
]
CARGO_MISSION_TABLE = '/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission017'
CARGO_NAME_KEY = 'SV_Cargo'
CARGO_LAUNCHER_DIR = '/Game/Blueprints/Vehicle/AI/Vessels/VE021_ctslf/CP/'     # + the launcher component: its class's package
CARGO_ARMS_EXPECTED = {   # (read from the stock blueprints by build_survival.py cargo_arms, checked against this)
    'BP_VE021_ctslf_cntus_01_CP': ['E_Unit_01_drone_5_0', 'E_Unit_01_drone_4_0', 'E_Unit_01_drone_0_0',
                                   'E_Unit_01_drone_1_0', 'E_Unit_01_drone_7_0', 'E_Unit_01_drone_8_0'],
    'BP_VE021_ctslf_cntus_03_CP': ['E_Unit_01_drone_3_1', 'E_Unit_01_drone_4_1', 'E_Unit_01_drone_1_1',
                                   'E_Unit_01_drone_2_1', 'E_Unit_01_drone_6_1', 'E_Unit_01_drone_7_1']}
CARGO_ARMS = {}           # s -> [(n, unit, [objects])], set by build_survival.py cargo_units before the events are built
CARGO_AREA_M, CARGO_ALT_M = ALLY_SHIP_AREA_M, ALLY_SHIP_ALT_M
# the ZFA-44 host: Survival's allied row ZFA_ROW -> ZFA_NPC, a copy of the campaign's plain Su-47 on its allied model at
# full speed (the plain row flies at x0.8): the airframe nearest the ZFA-44's size (22.6 x 15.2 m against 24.0 x 14.6 m,
# its hit spheres x1.25) and the one AC7 flew the ZFA-44EL's flight table on (the False Mihaly Su-47's boost table)
ZFA_ROW, ZFA_NPC, ZFA_NPC_SOURCE, ZFA_MODEL = 'sv_zfa_ally', 'SV_Zfa_Ally', 'OP1026_su47_01', 'OP1026_su47_Ally'
ZFA_NAME_KEY = 'SV_Zfa44'
# ((2026-11-07) the user's screenshot: the boxes read "SU-47" over "ZFA-44": "remove that and change its aircraft name to
# ZFA-44") the box's first line is the model row's name (DT_NPC_Model GameObjectDisplayName01): the host row on
# ZFA_MODEL_SV, Survival's copy of ZFA_MODEL with ZFA_NAME_KEY for it (DT_SV_ModelRows; Lua adds it to DT_NPC_Model at the
# main menu before the host row, as the shoal's); its second line the host row's GameObjectDisplayName02, ZFA_SUB_KEY
# (Lua's text: CFG.allies.carrier.zfa.sub, "VAMPIRE")
ZFA_SUB_KEY = 'SV_ZfaSub'
ZFA_MODEL_SV = 'SV_Model_Zfa'
# ((2026-11-07) the user: "why not just swap the drone model that launches originally with the ZFA-44 model", "i know for
# a fact that there was some launch smoke and VFX ... when the drones launched from the Cargo Ship", "the drones seem to
# just fly the same path together") the launched ZFA-44s fly Mission 16's allied container drone (OP0018_uavc_Ally,
# BP_OP0018_uavc_Base: the container launcher's mounted-actor interface, its own launch smoke NS_UAVLaunch001 and
# wing-opening animation), dressed as the ZFA-44 as before: DT_NPC row ZFA_DRONE_NPC (a copy of ZFA_DRONE_NPC_SOURCE,
# MOONCHILD's behaviour set) on ZFA_DRONE_MODEL_SV (its model row named "ZFA-44", ZFA_DRONE_HEALTH: the Su-47's 60, not
# the drone's 6), mission row ZFA_DRONE_ROW; its laser twin ZFA_DRONE_TLS_NPC (the gun's slot, as the Su-47's). The pose
# fallback keeps the Su-47 host (ZFA_ROW).
ZFA_DRONE_ROW, ZFA_DRONE_NPC, ZFA_DRONE_NPC_SOURCE = 'sv_zfa_drone', 'SV_Zfa_Drone', 'OP0018_uavc_Ally_01'
ZFA_DRONE_MODEL, ZFA_DRONE_MODEL_SV, ZFA_DRONE_HEALTH = 'OP0018_uavc_Ally', 'SV_Model_ZfaDrone', 60.0
ZFA_DRONE_TLS_NPC = 'SV_Zfa_DroneTLS'
# the launch in Mission 17's order (RemoteEvent_SpinUpWeapan's ToOpen, the container's fire, ToClose 2 s after it):
# RE_SV_CargoLaunch_<s>_<n> opens ship s's container, fires arm n ZFA_OPEN_S on and closes it ZFA_CLOSE_S after; the
# arm's planes wait parked until then (no orders at their appearance: ordered, they flew off their parking as one flight
# and the container had nothing left to launch). Lua sees them come out of the container and fires RE_SV_ZfaClimb_<s>_<n>:
# each object its own climb-out path SV_Path_ZfaClimb_<s>_<k> (fanned ZFA_CLIMB_FAN_DEG apart off the ship's bow,
# ZFA_CLIMB_KM out and ZFA_CLIMB_UP_M up) at Mission 17's 1200 km/h, their orders ZFA_CLIMB_ORDERS_S on
ZFA_OPEN_S, ZFA_CLOSE_S = 2.0, 3.0
# ((2026-11-07, the user's first container launch, 0.74.13: "the ZFA-44's stuck together": both leave the one container at
# once, their paths 30 deg apart were 80 m apart at their first point, and both took the unit's orders at the same
# moment) 90 deg apart (each 45 off the bow, 565 m apart 400 m out), each its own orders, ZFA_CLIMB_STAGGER_S apart
ZFA_CLIMB_KM, ZFA_CLIMB_UP_M, ZFA_CLIMB_FAN_DEG = 3.2, 800.0, 90.0
ZFA_CLIMB_ORDERS_S, ZFA_CLIMB_STAGGER_S = (8.0, 14.0), 4.0
# ((2026-11-07) the user: "need to make the Vampires Escort the Nearest Player too them") each VAMPIRES flight's cover
# record (Lua fires it for the flight whose nearest player is this game's own: sv_escort_laser.lua ZLAUNCH.coverTick):
# its area moved near that plane (Mission 6's NearPlayer move, as the STORE allies' Cover), ZFA_COVER_RADIUS_M round it
ZFA_COVER_RADIUS_M = 3000.0
ZFA_DRONE_SOURCE = 'E_Unit_01_drone_5_0'     # Mission 17's drone unit desc the launch units are copies of
ZFA_PER_ARM = 2                              # a two-ship a firing (the arm's magazine holds 5)
ZFA_PARK_Z = -24483.9                        # Mission 17's drones' height until launched (under the sea)
ZFA_AREA_M, ZFA_ALT_M = AREA_RADIUS_M, (0.0, 12000.0)
ZFA_ORDERS_S = (6.0, 10.0)                   # after a launch: the launched unit's orders (the arm's spin-up is 3.33 s)
# the pose-spawn fallback (the contract's; untested whether a fighter can leave a drone rack): one 4-ship a ship, Lua
# spawns it above its ship, MOONCHILD's lead's desc
ZFA_FALLBACK = [('A', 'SV_Unit_ZfaA', 'SV_Obj_ZfaA', 1), ('B', 'SV_Unit_ZfaB', 'SV_Obj_ZfaB', 2)]
ZFA_FALLBACK_N, ZFA_FALLBACK_UP_CM, ZFA_GAP_CM = 4, 30000.0, 6000.0
# (2026-11-07) the ZFA-44s' anti-missile laser (tools/re/LASER_INTERCEPTOR.md "Built"): AC8's own BP_SwingTLS_ForMSL (the
# Nightmare UAV's TLSforMSL arm's weapon) on a fire-control arm of Survival's, ZFA_TLS_FCS_PKG (build_survival.py
# build_zfa_laser: a copy of the ships' CIWS arm ZFA_TLS_FCS_SOURCE, its launcher a LauncherCommon at the host's gun
# socket, its AIControlCIWS missiles only), named by fire-control row ZFA_TLS_FCS_ROW (DT_SV_NpcFCS, a copy of
# NPC_FCS_VesselCIWS000) in slot ZFA_TLS_SLOT of ZFA_TLS_NPC (DT_SV_NpcRows: ZFA_NPC with that slot filled; the Su-47's
# AllArms has slots 3-5 free). Lua (Scripts/sv_escort_laser.lua) adds the FCS row to DT_NPC_FCS at the main menu and,
# with it in, ZFA_NPC's DT_NPC row from ZFA_TLS_NPC's struct. Each interception: Mission 29's WeaponIntercept_UAV_TLS
# trigger (WID_tls; any object, no tag: Mission 27's CIWS shape) adds 1 to ZFA_TLS_FLAG.
ZFA_TLS_FCS_SOURCE = '/Game/Blueprints/Weapons/BP_FCS/CP/BP_FCS_Vessel_CIWS_00'
ZFA_TLS_FCS_PKG = '/Game/Mods/SurvivalMode/Weapons/BP_FCS_SV_ZfaTLS'
ZFA_TLS_OLD_WEAPON = '/Game/Blueprints/Weapons/CIWS/Vessel/BP_wp_ciws_vessel'       # the CIWS arm's weapon
ZFA_TLS_WEAPON = '/Game/Blueprints/Weapons/Laser/Tls/UAVN/BP_SwingTLS_ForMSL'      # ours (stock, unchanged)
ZFA_TLS_LAUNCHER_SOURCE = '/Game/Blueprints/Weapons/BP_FCS/CP/BP_FCS_ECM_00'       # its LauncherCommon's class ids
ZFA_TLS_FCS_TABLE = '/Game/Mods/SurvivalMode/Data/DT_SV_NpcFCS'
ZFA_TLS_FCS_ROW, ZFA_TLS_FCS_ROW_SOURCE = 'SV_FCS_ZfaTLS', 'NPC_FCS_VesselCIWS000'
# ((0.74.12) the user: "swap the guns out for the Laser Interceptor") its slot is the gun's, NpcFCSId1 (NPC_FCS_PlaneGun000
# on the Su-47): no gun; WN_WEAPON_2 (hard rule 40). Lua fires it too (Scripts/sv_escort_laser.lua ZLAS.drive)
ZFA_TLS_NPC, ZFA_TLS_SLOT, ZFA_TLS_GUN = 'SV_Zfa_AllyTLS', 1, 'NPC_FCS_PlaneGun000'
# ((2026-11-07) the user: "I want the entire weapon from ACE7 to be ported over") AC7's LaserInterceptor (tools/laser7,
# runtime laser.c, Scripts/sv_escort_li.lua) is spawned by Lua onto each ZFA-44: its hosts fly these twins, the gun's slot
# EMPTY (no gun, and no arm of AC8's laser firing on its own beside AC7's)
ZFA_LI_NPC, ZFA_DRONE_LI_NPC = 'SV_Zfa_AllyLI', 'SV_Zfa_DroneLI'
ZFA_LI_CLASS = '/Game/Mods/SurvivalMode/Laser7/BP_SV_LaserInterceptor'
ZFA_TLS_EVENT, ZFA_TLS_FLAG = 'SV_ZfaTLSHit', 'SV_ZfaTLSHits'


def cargo_ship(s):
    return [c for c in CARGO_SHIPS if c[0] == s][0]


def cargo_launch_event(s, n):
    return f'RE_SV_CargoLaunch_{s}_{n}'


def zfa_climb_event(s, n):
    return f'RE_SV_ZfaClimb_{s}_{n}'


def zfa_climb_path(s, k):
    # ((2026-11-07, 0.74.14's launch: both drones 3 m apart for 15 s, neither on its path) a letter, never a number tail:
    # the record names the path by string, which the engine splits ("..._1_0" -> "..._1", 1: hard rule 17), and the desc's
    # name was stored whole, so the game never found it (make_path refuses a number tail now)
    return f'SV_Path_ZfaClimb{s}{chr(65 + k)}'


def zfa_cover_event(s, n=None):
    """RE_SV_ZfaCover_<s>_<n> (ship s's arm n unit) or RE_SV_ZfaCover<L> (pose flight L)."""
    return f'RE_SV_ZfaCover_{s}_{n}' if n is not None else f'RE_SV_ZfaCover{s}'


def zfa_tls_event(s, n=None):
    """(2026-11-07) The ZFA-44s' own laser fired on command (the user: "the Laser Interceptor doesn't swing or go after
    the missiles, it also isn't attached to the aircraft"): RE_SV_ZfaTLS_<s>_<n> fires the laser's slot on every object of
    ship s's arm n unit, RE_SV_ZfaTLS<L> on pose flight L's (s a letter, n None)."""
    return f'RE_SV_ZfaTLS_{s}_{n}' if n is not None else f'RE_SV_ZfaTLS{s}'


def zfa_climb_points(s, k):
    """Object k's climb-out path off ship s (cm): from 150 m off its bow, ZFA_CLIMB_FAN_DEG apart, up to ZFA_CLIMB_UP_M."""
    import math
    c = cargo_ship(s)
    x, y = c[6][0], c[6][1]
    h = math.radians(c[7] + (k - (ZFA_PER_ARM - 1) / 2.0) * ZFA_CLIMB_FAN_DEG)
    return [(x + math.cos(h) * d * 100000.0, y + math.sin(h) * d * 100000.0, up * 100.0)
            for d, up in ((0.4, 80.0), (1.2, 300.0), (2.2, 600.0), (ZFA_CLIMB_KM, ZFA_CLIMB_UP_M))]


# THE DECOY: the bait (Mission 30's Marker UAV with its laser pod, more health, far north), its laser's mark at the
# airfield, 35 trap UAVs (the same on a weaponless row) and their 35 marks (Mission 22's dummy desc, as VALKA's aim), the
# Spear's four virtual shooters (Mission 19's, player avoidance off by their blueprint), the Spear, its impact counter and
# the sure kill, five AWACS radio lines.
DECOY_UAV_SOURCE = ('/Game/Maps/Ingame/Mission030/WD_Mission030_global', 'B_Unit_00_UAVST0')
DECOY_POD = 'BP_OP0033_uavst_laser'          # the laser pod child's component (ALiveAIAirshipLaserPod)
DECOY_BAIT_UNIT, DECOY_BAIT_OBJ, DECOY_BAIT_ROW = 'SV_Unit_DecoyBait', 'SV_Obj_DecoyBait', 'sv_decoy_bait'
DECOY_BAIT_SPOT, DECOY_BAIT_YAW = (1610476.0, -3600000.0, 250000.0), 90.0   # 31.6 km due north, 2.5 km up, facing south
DECOY_BAIT_HEALTH_ADD = 114.0                # 6 + 114 = 120 HP (the mission row's MaxHealthDifference)
DECOY_BAIT_AREA_M = 4000.0
DECOY_BAIT_MARK_UNIT, DECOY_BAIT_MARK_OBJ = 'SV_Unit_DecoyBaitMark', 'SV_Obj_DecoyBaitMark'
DECOY_BAIT_MARK_SPOT = (1610476.0, -436142.0, 600.0)                       # the runway's centre, 1 m over it
DECOY_N = 35
DECOY_UAV_ROW, DECOY_UAV_NPC, DECOY_UAV_NPC_SOURCE = 'sv_decoy_uav', 'SV_DecoyUav', 'OP0033_uavst_01'
DECOY_UAV_AREA_M, DECOY_UAV_ALT_M = 2500.0, (100.0, 12000.0)                # they circle where they're spawned
DECOY_MISSION_TABLE = '/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission030'
DECOY_MISSION_SOURCE = 'uavst_ms30'
DECOY_MARK_SOURCE, DECOY_MARK_ROW = 'Unit_dummyN0', 'dummy_common'       # Mission 22's (VALKA's aim, A_Obj_01_dummyN0)
DECOY_SPEAR_SOURCE = ('/Game/Maps/Ingame/Mission019/WD_Mission019_global', 'E_Unit_01_God_0')
DECOY_SPEAR_TABLE, DECOY_SPEAR_SOURCE_ROW = '/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission019', 'aship_RoG_ms19'
DECOY_SPEAR_ROW = 'sv_decoy_spear'
DECOY_SPEARS = [(f'SV_Unit_DecoySpear_{k + 1}', f'SV_Obj_DecoySpear{c}') for k, c in enumerate('ABCD')]
DECOY_SPEAR_Z, DECOY_SPEAR_GAP_CM = 3000000.0, 100000.0                      # 30 km up over the airfield, 1 km apart
DECOY_SPEAR_TAG, DECOY_SPEAR_SLOT, DECOY_HIT_FLAG = 'SV_DecoySpear', 'WN_WEAPON_1', 'SV_DecoySpearHit'
DECOY_LASER_SEARCH_S, DECOY_LASER_HOLD_S = '1.5', '10000.0'   # LiveAirshipLaserDesignate args 6 / 7 (Mission 30's 5 / 10000)
DECOY_RADIO = [  # (suffix, TextID, options): DT_SV_Radio group SV_DecoyRadio_<suffix>, played by RE_SV_DecoyRadio_<suffix>
    ('Lock', 'v0001_1514', {'now': True}),       # "Joker Flight, laser targeting!" (ST_ms011 / ms019)
    ('Incoming', 'v0001_1507', {'now': True}),   # "Laser targeting! Tonitrus Spear incoming!" (ST_ms019)
    ('Imminent', 'v0001_1515', {'now': True}),   # "Strike imminent!" (ST_ms019)
    ('Hit', 'v0001_1513', {}),                   # "Joker 1 took a direct Spear hit!" (ST_ms019)
    ('Brief', 'v0001_1502', {}),                 # "Projectiles will hit locations marked by the laser. Keep your distance."
]
DECOY_RADIO_SPEAKER = 'LIVE_AWACS'


def decoy_uavs():
    """[(nn, unit, object, mark unit, mark object)] for the 35 trap UAVs: SV_Unit_DecoyUav_01 .. _35 (stored as the engine
    splits them: hard rule 17), their objects SV_Obj_DecoyUav01 .. (no split tail), marks SV_Unit_DecoyMark_01 .. ."""
    return [(k, f'SV_Unit_DecoyUav_{k:02d}', f'SV_Obj_DecoyUav{k:02d}', f'SV_Unit_DecoyMark_{k:02d}', f'SV_Obj_DecoyMark{k:02d}')
            for k in range(1, DECOY_N + 1)]


def decoy_radio():
    """[(group, event, TextID, speaker, options)]."""
    return [(f'SV_DecoyRadio_{suf}', f'RE_SV_DecoyRadio_{suf}', tid, DECOY_RADIO_SPEAKER, opts) for suf, tid, opts in DECOY_RADIO]


# the mission rows (DT_SV_NpcMission; build_survival.py build_npc_table): (row, stock table or None for Mission 22's, its
# source row there, its NpcId or None for the source's, MaxHealthDifference or None)
ESCORT_DECOY_MISSION_ROWS = (
    [(ESC_CHAR_ROW, None, ESC_CHAR_ROW_TEMPLATE, ESC_CHAR_NPC, ESC_CHAR_HEALTH_ADD)]
    + [(row, None, ESC_ROW_TEMPLATE, npc, None) for row, (npc, _, _) in ESC_ROWS.items()]
    + [(ZFA_ROW, None, ESC_ROW_TEMPLATE, ZFA_NPC, None), (ZFA_DRONE_ROW, None, ESC_ROW_TEMPLATE, ZFA_DRONE_NPC, None)]
    + [(c[3], CARGO_MISSION_TABLE, c[4], None, None) for c in CARGO_SHIPS]
    + [(DECOY_BAIT_ROW, DECOY_MISSION_TABLE, DECOY_MISSION_SOURCE, None, DECOY_BAIT_HEALTH_ADD),
       (DECOY_UAV_ROW, DECOY_MISSION_TABLE, DECOY_MISSION_SOURCE, DECOY_UAV_NPC, None),
       (DECOY_SPEAR_ROW, DECOY_SPEAR_TABLE, DECOY_SPEAR_SOURCE_ROW, None, None)])
ESCORT_ALLIED_ROWS = {ESC_CHAR_ROW, ZFA_ROW, ZFA_DRONE_ROW, *ESC_ROWS, *(c[3] for c in CARGO_SHIPS)}
# the DT_NPC rows (DT_SV_NpcRows; build_survival.py build_npc_rows), which Lua adds to DT_NPC at the main menu:
# (row, its stock DT_NPC source, the model or None (the source's), fly MOONCHILD's set, drop its weapons, name key, full speed)
ESCORT_DECOY_NPC_ROWS = (
    [(npc, src, model, True, False, None, False) for npc, src, model in ESC_ROWS.values()]
    + [(ZFA_NPC, ZFA_NPC_SOURCE, ZFA_MODEL, True, False, ZFA_NAME_KEY, True),
       (ZFA_DRONE_NPC, ZFA_DRONE_NPC_SOURCE, ZFA_DRONE_MODEL, True, False, ZFA_NAME_KEY, True),
       (DECOY_UAV_NPC, DECOY_UAV_NPC_SOURCE, None, False, True, None, False)])
INT_FLAGS += ([a['leg'] for a in esc_aircraft()] + [a['slot'] for a in esc_aircraft()] + ['SV_EscortSlots', DECOY_HIT_FLAG])
INT_FLAGS += [ZFA_TLS_FLAG]                    # (the ZFA-44s' laser's interceptions: build_escort)


def build_escort(g, flag, stock_ep):
    """THE ESCORT's records (ESC_*, CARGO_*, ZFA_*). For CHARLENE and each escort, one remote event a step (Lua fires them;
    ESC_SPEED's speeds): Go (gear up, her engagement None / theirs Normal, her route), CruiseSlow (the route at 450),
    Orbit (an escort's wait circle: off its path, then the circle 0.1 s on, Mission 26's switch), Final (the glide slope
    from the IAF, gear down; an escort off its path first and its engagement None), FinalSlow / FinalShort (the final again
    at 280 / 260: a path given again with a new speed goes on along it, Mission 14's way), Roll (Mission 14's touchdown
    record: 50 km/h, accel 2.7; invincible, engagement None), Taxi (the next free parking slot in landing order:
    SV_EscortSlots, each aircraft's slot in SV_TaxiSlot<who>), Stop (its slot's 18 m stop path at speed 0, Mission 26's),
    GearDown, Remove (Mission 22's despawn), an escort's Guard (off its path, Normal, its area onto CHARLENE 3 km: Mission
    14's way of keeping units on its C-130). Each step sets its aircraft's leg flag (SV_CharLeg / SV_EscLeg<Name>). Each
    path's end (PathFinish, hard rule 1) starts the next step only while its leg flag says Lua hasn't (a backstop: conditions
    are read as the PathFinish fires, hard rule 26). The cargo ships: their engagement as they appear (the hull Normal, the
    Stinger Normal / Default), RE_SV_CargoLaunch_<s>_<n> (Mission 17's LiveFireOneShotWeapon on ship s's launcher, arm n,
    then the launched two-ship's orders), RE_SV_CargoRemove_<s>; the ZFA-44 units' orders as they appear; the fallback
    4-ships' RE_SV_ZfaGo<A|B>; the ZFA-44s' laser's interceptions (ZFA_TLS_EVENT -> ZFA_TLS_FLAG + 1)."""
    d = os.path.dirname(os.path.dirname(stock_ep))
    m06 = os.path.join(d, 'MIssion006', 'EP_Mission006_global.uasset')
    m14 = os.path.join(d, 'Mission014', 'EP_Mission014_global.uasset')
    m16 = os.path.join(d, 'Mission016', 'EP_Mission016_global.uasset')
    m17 = os.path.join(d, 'Mission017', 'EP_Mission017_global.uasset')
    m26 = os.path.join(d, 'Mission026', 'EP_Mission026_global.uasset')
    m29 = os.path.join(d, 'Mission029', 'EP_Mission029_global.uasset')
    c130, lead = 'Air_obj_c130_0', 'AB_Obj_01_Air1_f18e_0'
    t_path = g.foreign_template(m16, 'LiveAIPathExecution', 'PathFinish_Ladon0_0', lambda a, e: a[0] == 'B_Obj_01_Air0_Ladon0')
    t_final = g.foreign_template(m14, 'LiveAIPathExecution', 'Default_PathPointReceive_25', lambda a, e: a[0] == c130)
    t_touch = g.foreign_template(m14, 'LiveAIPathExecution', 'Default_PathPointReceive_40', lambda a, e: a[0] == c130)
    t_safe = g.foreign_template(m14, 'LiveSetCommonAttribute', 'Debug_c130_MUTEKI')
    t_stop = g.foreign_template(m26, 'LiveAIPathExecution', 'Baxter_Stop_0')
    t_taxi = g.exec_template('LiveAIPathExecution', '01_Wave01_CheckDistanceEvent', lambda a, e: a[0] == lead)
    t_gear_dn = g.exec_template('LiveEnableLandingGear', 'RE_Wave01_Start', lambda a, e: a[0] == lead)
    t_gear_up = g.exec_template('LiveEnableLandingGear', '01_A_Air1_f18e_PathFinish_3')
    t_attr_air = g.exec_template('LiveSetCommonAttribute', '01_A_Air1_f18e_PathFinish_3')
    t_eng_none = g.exec_template('LiveAIEngagementOrder', 'RE_Wave01_Start', lambda a, e: a[0] == lead)
    t_eng_air = g.exec_template('LiveAIEngagementOrder', '01_A_Air1_f18e_PathFinish_3')
    t_search = g.exec_template('LiveAIChangeEnemySearchType', '01_E_AreaA_ReinforcementAppearance_0')
    t_exit = g.exec_template('LiveAIPathExitExecution', 'Default_CompositeEvent_19', lambda a, e: a[0] != 'NoneSelect')
    t_move = g.exec_template('LiveUnitMoveActor', '01_E_AreaA_ReinforcementAppearance_0')
    t_radius = g.foreign_template(m06, 'LiveChangeUnitRadius', 'PhaseStart_Phase02_2')
    t_near = g.foreign_template(m06, 'LiveUnitMoveActor', 'CE_ReinforceAppear_Phase01_2')
    assert arg_values(t_near)[12] == 'NearPlayer', arg_values(t_near)
    t_off = g.exec_template('LiveSetActiveGameObjectExecution', None, lambda a, e: a[0] != 'NoneSelect' and a[3] == 'false')
    t_seng = g.exec_template('LiveAIEngagementOrder', 'UnitDamage_Enemy_Ship_Last1', lambda a, e: a[0].startswith('AC_Obj_01_Ship1'))
    t_launch = g.foreign_template(m17, 'LiveFireOneShotWeapon', 'Default_PreRadioEvent_49', lambda a, e: a[1].endswith('_cntus_03_CP'))
    t_open = g.foreign_template(m17, 'LiveUniqueStateMachineTransitionEvent', 'RemoteEvent_SpinUpWeapan',
                                lambda a, e: a[0].endswith('_cntus_01_CP'))
    t_climb = g.foreign_template(m17, 'LiveAIPathExecution', 'RemoteEvent_FireWeapon_12', lambda a, e: a[4] == '1200.0')
    v = arg_values
    assert v(t_path)[9] == 'false' and v(t_final)[9] == 'false' and v(t_touch)[9] == 'false', (v(t_path), v(t_final), v(t_touch))
    assert (float(v(t_final)[4]), float(v(t_final)[5])) == (225.0, 30.0), v(t_final)
    assert (float(v(t_touch)[4]), float(v(t_touch)[5])) == (50.0, 2.7), v(t_touch)
    assert float(v(t_stop)[4]) == 0.0 and v(t_stop)[2] == 'Baxter_Path_Stop_0', v(t_stop)
    assert v(t_taxi)[2] == TAKEOFF_LEAD[0] and v(t_taxi)[4] == '50', v(t_taxi)
    assert v(t_safe)[3:6] == ['true', 'true', 'Attention'] and v(t_attr_air)[3:5] == ['true', 'false'], (v(t_safe), v(t_attr_air))
    assert v(t_eng_none)[3] == 'None' and v(t_eng_air)[3] == 'Normal' and v(t_seng)[3] == 'Normal', (v(t_eng_none), v(t_eng_air))
    assert v(t_gear_dn)[3] == 'true' and v(t_gear_up)[3] == 'false'
    assert v(t_launch)[0] == 'WN_WEAPON_1' and v(t_launch)[2:4] == ['NoneSelect', 'NoneSelect'], v(t_launch)
    assert v(t_open)[1:3] == ['ToOpen', 'false'], v(t_open)
    assert v(t_climb)[1] == 'NoneSelect' and v(t_climb)[3:8] == ['NoneSelect', '1200.0', '300.0', '90.0', 'NotSnap'], v(t_climb)
    finish = '01_A_Air1_f18e_PathFinish'                   # PathFinish trigger template: {0 object, 2 path}
    remote = lambda ev: g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
    n_trig, n_ex = len(g.trig), len(g.ex)
    no_conds = lambda: []

    def attr(ev, a, safe, delay=None, conds=no_conds):
        """visible; invincible or not; CHARLENE keeps her Attention mark (Mission 14's C-130's), an escort none"""
        mark = 'Attention' if not a['escort'] else 'None'
        g.execute(t_safe, ev, {0: 'NoneSelect', 1: a['obj'], 2: 'NoneSelect', 3: 'true', 4: 'true' if safe else 'false', 5: mark},
                  delay=delay, conds=conds())

    def step(ev, a, s, conds=no_conds):
        """step s of aircraft a on event ev; conds: a factory of the backstop's extra conditions (fresh records each)"""
        o, u, L = a['obj'], a['unit'], a['legs']
        c = conds
        before = lambda leg: (lambda: conds() + [g.cond(a['leg'], 'Leq', leg - 1)])      # (that step not begun yet)
        if s == 'go':
            g.execute(t_gear_up, ev, {0: o}, conds=c())
            if a['escort']:
                g.execute(t_eng_air, ev, {0: o}, conds=c())
                g.execute(t_search, ev, {0: o, 1: 'NoneSelect'}, conds=c())
            else:
                g.execute(t_eng_none, ev, {0: o}, conds=c())
                flag(ev, 'SV_EscortSlots', 'Set', 0, conds=c())       # (her round starts: no parking slot taken yet)
            attr(ev, a, False, conds=c)
            flag(ev, a['leg'], 'Set', L['route'], conds=c())
            g.execute(t_path, ev, {0: o, 2: a['route'], 4: ESC_SPEED['route']}, conds=c())
        elif s == 'cruise_slow':
            g.execute(t_path, ev, {0: o, 2: a['route'], 4: ESC_SPEED['cruise_slow']}, conds=c())
        elif s == 'orbit':                                 # (an escort's hold over her: off its path, its area on her)
            g.execute(t_exit, ev, {0: o}, conds=c())
            g.execute(t_eng_air, ev, {0: o}, delay=0.1, conds=c())
            g.execute(t_search, ev, {0: o, 1: 'NoneSelect'}, delay=0.1, conds=c())
            g.execute(t_move, ev, {0: u, 1: ESC_CHAR_OBJ, 3: 'NoneSelect'}, delay=0.5, conds=c())
            g.execute(t_radius, ev, {0: u, 1: 'NoneSelect', 2: f'{ESC_HOLD_RADIUS_M:.1f}'}, delay=1.0, conds=c())
            flag(ev, a['leg'], 'Set', L['orbit'], conds=c())
        elif s in ('final', 'final_slow', 'final_short', 't0_final', 't0_final_slow', 't0_final_short'):
            # her path given again at the new speed (the route runs on into the final: Mission 14's way, no new path); an
            # escort's first final starts the landing circuit (Lua: with its start a little ahead), then again at each
            # new speed; T0's her final alone (SV_Path_CharFinal, her spawned before its start)
            t0 = s.startswith('t0_')
            sp = s[3:] if t0 else s
            path = ESC_PATH_FINAL if t0 else (ESC_PATH_CIRCUIT if a['escort'] else ESC_PATH_ROUTE)
            first = sp == 'final' and (a['escort'] or t0)
            if sp == 'final':
                if a['escort']:
                    g.execute(t_exit, ev, {0: o}, conds=c())
                    g.execute(t_eng_none, ev, {0: o}, conds=c())
                    g.execute(t_radius, ev, {0: u, 1: 'NoneSelect', 2: f'{ESC_AREA_M:.1f}'}, conds=c())
                g.execute(t_gear_dn, ev, {0: o}, delay=0.5, conds=c())
                flag(ev, a['leg'], 'Set', L['final'], conds=c())
            speed = ESC_SPEED['circuit'] if (a['escort'] and sp == 'final') else ESC_SPEED[sp]
            g.execute(t_final, ev, {0: o, 2: path, 4: speed, 5: ESC_FINAL_ACCEL},
                      delay=0.1 if (first and a['escort']) else None, conds=c())
        elif s in ('roll', 't0_roll'):
            path = ESC_PATH_FINAL if s == 't0_roll' else (ESC_PATH_CIRCUIT if a['escort'] else ESC_PATH_ROUTE)
            g.execute(t_touch, ev, {0: o, 2: path, 4: ESC_SPEED['roll'], 5: ESC_ROLL_ACCEL}, conds=c())
            g.execute(t_eng_none, ev, {0: o}, conds=c())
            g.execute(t_gear_dn, ev, {0: o}, conds=c())
            attr(ev, a, True, conds=c)
            flag(ev, a['leg'], 'Set', L['roll'], conds=c())
        elif s == 'taxi':                                  # (once: only while its taxi hasn't begun)
            gate = before(L['taxi'])
            for k, (S, _) in enumerate(ESC_SLOTS):
                last = k + 1 == len(ESC_SLOTS)             # (the last slot also takes any count past it)
                slot = lambda: gate() + [g.cond('SV_EscortSlots', 'Geq', k)] + ([] if last else [g.cond('SV_EscortSlots', 'Leq', k)])
                g.execute(t_taxi, ev, {0: o, 2: f'SV_Path_TaxiSlot{S}', 4: ESC_SPEED['taxi']}, conds=slot())
                flag(ev, a['slot'], 'Set', k + 1, conds=slot())
            flag(ev, 'SV_EscortSlots', 'Add', 1, conds=gate())
            flag(ev, a['leg'], 'Set', L['taxi'], conds=gate())
        elif s == 'stop':
            for k, (S, _) in enumerate(ESC_SLOTS):
                g.execute(t_stop, ev, {0: o, 2: f'SV_Path_StopSlot{S}'},
                          conds=c() + [g.cond(a['slot'], 'Geq', k + 1), g.cond(a['slot'], 'Leq', k + 1)])
            flag(ev, a['leg'], 'Set', L['stop'], conds=c())
        elif s == 'gear_down':
            g.execute(t_gear_dn, ev, {0: o}, conds=c())
        elif s == 'guard':                                 # (an escort: off its path and onto whatever attacks her)
            g.execute(t_exit, ev, {0: o}, conds=c())
            g.execute(t_eng_air, ev, {0: o}, delay=0.1, conds=c())
            g.execute(t_search, ev, {0: o, 1: 'NoneSelect'}, delay=0.1, conds=c())
            g.execute(t_move, ev, {0: u, 1: ESC_CHAR_OBJ, 3: 'NoneSelect'}, delay=0.5, conds=c())
            g.execute(t_radius, ev, {0: u, 1: 'NoneSelect', 2: f'{ESC_GUARD_RADIUS_M:.1f}'}, delay=1.0, conds=c())
            flag(ev, a['leg'], 'Set', L['orbit'], conds=c() + [g.cond(a['leg'], 'Leq', L['orbit'])])   # (its route's end idle)
        elif s == 'remove':
            g.execute(t_off, ev, {0: 'NoneSelect', 1: u, 2: 'NoneSelect', 3: 'false'}, conds=c())
        else:
            raise KeyError(s)
    names = {'go': 'Go', 'cruise_slow': 'CruiseSlow', 'orbit': 'Orbit', 'final': 'Final', 'final_slow': 'FinalSlow',
             'final_short': 'FinalShort', 'roll': 'Roll', 'taxi': 'Taxi', 'stop': 'Stop', 'gear_down': 'GearDown',
             'guard': 'Guard', 'remove': 'Remove', 't0_final': 'T0Final', 't0_final_slow': 'T0FinalSlow',
             't0_final_short': 'T0FinalShort', 't0_roll': 'T0Roll'}
    ESC_EVENTS.clear()
    for a in esc_aircraft():
        o = a['obj']
        # its appearance: gear up, her engagement None (an escort Normal, air search), visible and not invincible
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', a['up'], arg_changes={0: a['unit']})
        g.execute(t_gear_up, a['up'], {0: o}, delay=0.5)
        if a['escort']:
            g.execute(t_eng_air, a['up'], {0: o}, delay=0.5)
            g.execute(t_search, a['up'], {0: o, 1: 'NoneSelect'}, delay=0.5)
        else:
            g.execute(t_eng_none, a['up'], {0: o}, delay=0.5)
        attr(a['up'], a, False, delay=0.5)
        for s, suffix in names.items():
            if s in ('orbit', 'guard') and not a['escort']: continue
            if s.startswith('t0_') and a['escort']: continue
            ev = a['ev'] + suffix
            remote(ev)
            step(ev, a, s)
            ESC_EVENTS.setdefault(a['key'], []).append(ev)
        # the backstops: each path's end starts the next step while the leg flag says Lua hasn't
        L = a['legs']
        # (her route ends at the rollout's end, as T0's final and the escorts' circuit do: their ends start the taxi)
        if a['escort']:
            chain = [(a['route'], 'orbit', L['route']), (ESC_PATH_CIRCUIT, 'taxi', L['roll'])]
        else:
            chain = [(ESC_PATH_ROUTE, 'taxi', L['roll']), (ESC_PATH_FINAL, 'taxi', L['roll'])]
        for path, nxt, upto in chain:
            ev = f"SV_{a['key']}End{path[len('SV_Path_'):].replace('_', '')}"
            g.trigger(finish, ev, arg_changes={0: o, 2: path})
            if upto is not None:
                gate = lambda upto=upto, a=a: [g.cond(a['leg'], 'Leq', upto)]
            else:                                          # (its orbit's end: round again while it's still waiting)
                gate = lambda a=a: [g.cond(a['leg'], 'Geq', a['legs']['orbit']), g.cond(a['leg'], 'Leq', a['legs']['orbit'])]
            step(ev, a, nxt, conds=gate)
        for k, (S, _) in enumerate(ESC_SLOTS):
            ev = f"SV_{a['key']}EndTaxi{S}"
            g.trigger(finish, ev, arg_changes={0: o, 2: f'SV_Path_TaxiSlot{S}'})
            step(ev, a, 'stop', conds=lambda a=a: [g.cond(a['leg'], 'Leq', a['legs']['taxi'])])
    # every leg and slot back to 0 (Lua, before a new escort round or the landing test without her)
    remote('RE_SV_EscortReset')
    for a in esc_aircraft():
        flag('RE_SV_EscortReset', a['leg'], 'Set', 0)
        flag('RE_SV_EscortReset', a['slot'], 'Set', 0)
    flag('RE_SV_EscortReset', 'SV_EscortSlots', 'Set', 0)
    # the cargo ships and their ZFA-44s
    assert set(CARGO_ARMS) == {c[0] for c in CARGO_SHIPS}, 'build_survival.py cargo_units sets CARGO_ARMS first'

    def zfa_orders(ev, unit, objs, delay):
        for ob in objs:
            g.execute(t_gear_up, ev, {0: ob}, delay=delay)
        g.execute(t_seng, ev, {0: 'NoneSelect', 1: unit}, delay=delay)
        g.execute(t_search, ev, {1: unit}, delay=delay)
    for s, unit, obj, *_ , launcher in CARGO_SHIPS:
        up = f'SV_CargoUp{s}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        g.execute(t_seng, up, {0: 'NoneSelect', 1: unit}, delay=2.0)
        g.execute(t_eng_air, up, {0: f'{obj}_BP_VE021_stgr_Base'}, delay=2.5)
        rm = f'RE_SV_CargoRemove_{s}'
        remote(rm)
        g.execute(t_off, rm, {0: 'NoneSelect', 1: unit, 2: 'NoneSelect', 3: 'false'})
        cont = f'{obj}_{launcher}'
        for n, zunit, zobjs in CARGO_ARMS[s]:
            # ((2026-11-07) Mission 17's launch: the container opened, arm n fired, closed again; nothing ordered at
            # the planes' appearance, so they wait parked for it; their climb-out and orders once Lua sees them out)
            ev = cargo_launch_event(s, n)
            remote(ev)
            g.execute(t_open, ev, {0: cont, 1: 'ToOpen'})
            g.execute(t_launch, ev, {0: f'WN_WEAPON_{n}', 1: cont}, delay=ZFA_OPEN_S)
            g.execute(t_open, ev, {0: cont, 1: 'ToClose'}, delay=ZFA_OPEN_S + ZFA_CLOSE_S)
            cl = zfa_climb_event(s, n)
            remote(cl)
            assert len(zobjs) == ZFA_PER_ARM, (zunit, zobjs)
            for k, ob in enumerate(zobjs):
                g.execute(t_climb, cl, {0: ob, 2: zfa_climb_path(s, k)})
                g.execute(t_gear_up, cl, {0: ob}, delay=1.0)
                for dl in ZFA_CLIMB_ORDERS_S:                 # (each its own Normal, ZFA_CLIMB_STAGGER_S apart)
                    g.execute(t_eng_air, cl, {0: ob}, delay=dl + k * ZFA_CLIMB_STAGGER_S)
            g.execute(t_search, cl, {1: zunit}, delay=ZFA_CLIMB_ORDERS_S[0])
            cov = zfa_cover_event(s, n)                       # (its escort of this game's player: Lua picks when)
            remote(cov)
            g.execute(t_near, cov, {0: zunit})
            g.execute(t_radius, cov, {0: zunit, 1: 'NoneSelect', 2: f'{ZFA_COVER_RADIUS_M:.1f}'})
            tls = zfa_tls_event(s, n)                         # (its laser on command: Lua picks the missile)
            remote(tls)
            for ob in zobjs:
                g.execute(t_launch, tls, {0: f'WN_WEAPON_{ZFA_TLS_SLOT + 1}', 1: ob})
    for L, unit, obj, s in ZFA_FALLBACK:
        objs = [f'{obj}_{k}' for k in range(ZFA_FALLBACK_N)]
        cov = zfa_cover_event(L)
        remote(cov)
        g.execute(t_near, cov, {0: unit})
        g.execute(t_radius, cov, {0: unit, 1: 'NoneSelect', 2: f'{ZFA_COVER_RADIUS_M:.1f}'})
        tls = zfa_tls_event(L)
        remote(tls)
        for ob in objs:
            g.execute(t_launch, tls, {0: f'WN_WEAPON_{ZFA_TLS_SLOT + 1}', 1: ob})
        for ev in (f'SV_ZfaUp{L}', f'RE_SV_ZfaGo{L}'):
            if ev.startswith('RE_'): remote(ev)
            else: g.trigger('01_E_AreaA_ReinforcementAppearance_0', ev, arg_changes={0: unit})
            zfa_orders(ev, unit, objs, 0.5)
    # the ZFA-44s' laser's interceptions: Mission 29's count of its Nightmare UAVs' TLS interceptions (args: the
    # intercepting weapon's ID, its object, its object's tag, the intercepted weapon's kind, a bool), its tag 'uav' let go
    # (Mission 27's CIWS count has no object and no tag): every WID_tls interception in the level (only the ZFA-44s fire
    # one in Survival) adds 1 to ZFA_TLS_FLAG
    t_tls = g.foreign_trig_template(m29, 'WeaponIntercept_UAV_TLS')
    assert v(t_tls) == ['WID_tls', 'NoneSelect', 'uav', 'NoneSelect', 'true'], v(t_tls)
    g.trigger(None, ZFA_TLS_EVENT, arg_changes={2: 'NoneSelect'}, template=t_tls)
    flag(ZFA_TLS_EVENT, ZFA_TLS_FLAG, 'Add', 1)
    print(f'  escort: CHARLENE + {len(ESC_ESCORTS)} escorts ({sum(len(x) for x in ESC_EVENTS.values())} remote events, '
          f'legs SV_CharLeg / SV_EscLeg<Name>, {len(ESC_SLOTS)} parking slots by landing order), {len(CARGO_SHIPS)} cargo ships '
          f'({sum(len(x) for x in CARGO_ARMS.values())} launches RE_SV_CargoLaunch_<s>_<n>: open, fire, close; their '
          f'climb-outs RE_SV_ZfaClimb_<s>_<n>, a path each), {len(ZFA_FALLBACK)} fallback '
          f'ZFA-44 4-ships: {len(g.trig) - n_trig} triggers, {len(g.ex) - n_ex} execs')


ESC_EVENTS = {}                                # who -> its remote events (build_escort), for the read-back


def build_decoy(g, flag, stock_ep):
    """THE DECOY's records (DECOY_*). The bait's and each trap UAV's appearance: its laser pod hidden from the HUD and
    invincible (Mission 30's RemoteEvent_Injection_uavst records), a trap UAV's engagement None (it circles, it doesn't hunt).
    RE_SV_DecoyBaitLaser (/ Off): the bait's laser on its mark at the airfield (Mission 30's UAV designate, laser only).
    RE_SV_DecoyLaserOn_<nn> / Off_<nn>: UAV nn's laser on mark nn (search DECOY_LASER_SEARCH_S, hold DECOY_LASER_HOLD_S) / off
    (Mission 19's Impact_Center stop). RE_SV_DecoyMarkOnMe_<nn>: mark nn teleported onto this game's player (Mission 22's
    teleport, VALKA's aim's; a fallback if Lua can't move the mark). RE_SV_DecoySpear_<s>: the Spear from shooter s at the
    player (Mission 6's LiveFireOneShotWeapon with an impact tag), its MeteoriteImpact trigger SV_DecoySpearImpact adding 1 to
    SV_DecoySpearHit. RE_SV_DecoyKill: Mission 26's LiveDestroyPlayerPlaneExecution. RE_SV_DecoyRadio_<X>: the radio lines."""
    d = os.path.dirname(os.path.dirname(stock_ep))
    m06 = os.path.join(d, 'MIssion006', 'EP_Mission006_global.uasset')
    m19 = os.path.join(d, 'Mission019', 'EP_Mission019_global.uasset')
    m26 = os.path.join(d, 'Mission026', 'EP_Mission026_global.uasset')
    m30 = os.path.join(d, 'Mission030', 'EP_Mission030_global.uasset')
    t_desig = g.foreign_template(m30, 'LiveAirshipLaserDesignate', 'VolumeEvent_LaserDesignate_uavst0_0')
    t_stop = g.foreign_template(m19, 'LiveAirshipStopLaserDesignate', 'Impact_Center', lambda a, e: a[0] == 'E_Obj_01_Air0_aship_0')
    t_pod = g.foreign_template(m30, 'LiveSetCommonAttribute', 'RemoteEvent_Injection_uavst_0')
    t_spear = g.foreign_template(m06, 'LiveFireOneShotWeapon', 'RE_ArtilleryHit_0', lambda a, e: a[5] == 'ArtilleryHit_LCAC0')
    t_impact = g.foreign_trig_template(m06, 'MeteoriteImpact_ArtilleryHit_LCAC1_0')
    t_kill = g.foreign_template(m26, 'LiveDestroyPlayerPlaneExecution', 'Player_Crash_Baxter')
    t_tp = g.exec_template('LiveActorTeleportExecution', '01_Wave05_YesEvent02', lambda a, e: a[1] == 'A_Obj_01_dummyN0')
    t_ueng = g.exec_template('LiveAIEngagementOrder', 'RE_Wave6_AllyFly', lambda a, e: a[1] == 'AA_Unit_01_Air0')
    t_radio = g.exec_template('LiveRadioPlayExecution', 'CompositeEvent_CountDown_1')
    v = arg_values
    assert v(t_desig) == ['B_Obj_00_UAVST0_uavst_0', 'NoneSelect', 'A_Obj_00_Ship0_edrne_0', 'NoneSelect', 'NoneSelect',
                          '5.0', '10000.0', '0', 'NoneSelect'], v(t_desig)
    assert v(t_stop) == ['E_Obj_01_Air0_aship_0', 'NoneSelect', 'false', 'true', '0.1'], v(t_stop)
    assert v(t_pod)[2:5] == ['Obj_Uavst_LaserPod', 'false', 'true'], v(t_pod)
    assert v(t_spear)[0] == 'WN_WEAPON_1' and v(t_spear)[3:] == ['NoneSelect', 'false', 'ArtilleryHit_LCAC0', 'false'], v(t_spear)
    assert v(t_impact) == ['ArtilleryHit_LCAC1'], v(t_impact)
    assert v(t_kill) == [], v(t_kill)
    assert v(t_tp)[2] == 'Player' and v(t_tp)[13] == 'Absolute', v(t_tp)
    assert v(t_ueng)[:4] == ['NoneSelect', 'AA_Unit_01_Air0', 'NoneSelect', 'None'], v(t_ueng)
    remote = lambda ev: g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
    n_trig, n_ex = len(g.trig), len(g.ex)
    pod = lambda obj: f'{obj}_{DECOY_POD}'

    def pod_safe(ev, obj, delay):
        g.execute(t_pod, ev, {0: 'NoneSelect', 1: pod(obj), 2: 'NoneSelect'}, delay=delay)
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', 'SV_DecoyBaitUp', arg_changes={0: DECOY_BAIT_UNIT})
    pod_safe('SV_DecoyBaitUp', DECOY_BAIT_OBJ, 0.5)
    remote('RE_SV_DecoyBaitLaser')
    g.execute(t_desig, 'RE_SV_DecoyBaitLaser', {0: DECOY_BAIT_OBJ, 2: DECOY_BAIT_MARK_OBJ})
    remote('RE_SV_DecoyBaitLaserOff')
    g.execute(t_stop, 'RE_SV_DecoyBaitLaserOff', {0: DECOY_BAIT_OBJ})
    # the bait's minimap ping (Lua's: as RE_SV_RaidPing_NN, Mission 22's own "look here" on its unit)
    t_nav = g.exec_template('LiveBattleNavigationExecution', 'Default_PreRadioEvent_28')
    assert arg_values(t_nav)[1:] == ['AA_Unit_01_Ground0', 'Quadruple', 'false'], arg_values(t_nav)
    remote('RE_SV_DecoyBaitPing')
    g.execute(t_nav, 'RE_SV_DecoyBaitPing', {1: DECOY_BAIT_UNIT})
    for nn, unit, obj, munit, mobj in decoy_uavs():
        up = f'SV_DecoyUavUp_{nn:02d}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        pod_safe(up, obj, 0.5)
        g.execute(t_ueng, up, {1: unit}, delay=0.5)
        on, off, me = f'RE_SV_DecoyLaserOn_{nn:02d}', f'RE_SV_DecoyLaserOff_{nn:02d}', f'RE_SV_DecoyMarkOnMe_{nn:02d}'
        remote(on)
        g.execute(t_desig, on, {0: obj, 2: mobj, 5: DECOY_LASER_SEARCH_S, 6: DECOY_LASER_HOLD_S})
        g.execute(t_ueng, on, {1: unit})
        remote(off)
        g.execute(t_stop, off, {0: obj})
        remote(me)
        g.execute(t_tp, me, {1: mobj, 4: '0.0', 5: '0.0', 6: '0.0', 9: '0.0', 10: '0.0', 11: '0.0'})
    for k, (unit, obj) in enumerate(DECOY_SPEARS):
        ev = f'RE_SV_DecoySpear_{k + 1}'
        remote(ev)
        g.execute(t_spear, ev, {0: DECOY_SPEAR_SLOT, 1: obj, 2: 'Player', 3: 'NoneSelect', 5: DECOY_SPEAR_TAG})
    g.trigger(None, 'SV_DecoySpearImpact', arg_changes={0: DECOY_SPEAR_TAG}, template=t_impact)   # (every impact)
    flag('SV_DecoySpearImpact', DECOY_HIT_FLAG, 'Add', 1)
    remote('RE_SV_DecoyKill')
    g.execute(t_kill, 'RE_SV_DecoyKill')
    for grp, ev, tid, spk, opts in decoy_radio():
        assert survival_fname_plain(grp) and survival_fname_plain(ev), grp
        remote(ev)
        g.execute(t_radio, ev, {0: grp})
    print(f'  decoy: the bait, {DECOY_N} trap UAVs (RE_SV_DecoyLaserOn_<nn> / Off_<nn> / MarkOnMe_<nn>), {len(DECOY_SPEARS)} Spear '
          f'shooters (RE_SV_DecoySpear_<s>, tag {DECOY_SPEAR_TAG} -> {DECOY_HIT_FLAG}), RE_SV_DecoyKill, {len(DECOY_RADIO)} radio '
          f'lines: {len(g.trig) - n_trig} triggers, {len(g.ex) - n_ex} execs')
