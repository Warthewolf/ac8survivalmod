"""survival_events_specials.py : the special rounds of the event graph, their names and their builders.

The Amphibious Assault (LCAC_*, build_amphib), the Ladons (LADON*, build_ladon), the Alicorn (ALCN_*,
build_alicorn), the Anomaly (ANOMALY_*, build_anomaly), AB.L..IN (GLITCH_*, build_glitch), VALKA (VALKA_*,
build_valka) and Comona Defense's shuttle (build_shuttle; its names are survival_events.SHUTTLE_* / PAD_*).

A part of tools/survival_events.py (its docstring has the layout): every name survival_events defines is
here through the import below, and survival_events imports this part back whole, so each name here is
survival_events.<name> too (build_survival.py and tools/checks read them so). Import survival_events, not this file.
"""
from survival_events import *  # noqa: F401,F403 (survival_events' names; it imports this part at its end)
import survival_events as _se   # build_survival.py sets ANOMALY_OBJ / GLITCH_OBJ / VALKA_OBJ there: read them there


# Special round "Amphibious Assault" (docs/design/SURVIVAL_SPEC.md 7; docs/re/SPECIAL_ROUNDS.md 12b): Mission 13's enemy LCAC
# pattern on Comona. Each lane: a unit of four landing craft (LCAC_CRAFT; a copy of Mission 13's E_Unit02_02_Ship0, NPC row
# lcac_common) that Scripts/main.lua spawns at the lane's start point at sea; its appearance sends each craft along
# its own path (side by side, LCAC_GAP_CM apart) onto the beach; at the end of it the craft leaves its path, the
# event package sets SV_LcacLand<lane><craft> and main.lua spawns that craft's troops (a copy of Mission 13's
# E_Unit02_02_Ground0, one BTR-90, btr9_common) on the beach; LCAC_RETURN_S later the craft heads back out along the
# lane, and main.lua takes the lane's craft off (RE_SV_LcacRemove<lane>) once they're well away, so the lane can come
# again. Lanes from the user's Ctrl+F10 marks (config/coast_marks.txt, 2026-10-23): the first five are beaches, the
# four after them start points at sea; each start goes to the beach it faces (the fifth beach mark, at sea level,
# 350, isn't used).
LCAC_SOURCE_UNIT = 'E_Unit02_02_Ship0'
LCAC_SOURCE_PATH = '02_ship0_lcac_0_Path0'
LCAC_TROOP_SOURCE = 'E_Unit02_02_Ground0'
LCAC_ROW, LCAC_TROOP_ROW = 'lcac_common', 'btr9_common'
LCAC_LANES = [   # (lane, start at sea (x, y) cm, beach (x, y, ground z) cm) - main.lua CFG.specials.amphibious.lanes
    ('A', (1124592, 601882), (1125609, -41221, 500)),
    ('B', (1181763, -939973), (1451014, -405292, 393)),
    ('C', (1202428, -1235402), (1600055, -489665, 500)),
    ('D', (1472712, -1417822), (1781906, -515173, 496)),
]
LCAC_CRAFT = 'WXYZ'            # the craft of a lane, side by side across its line (user, 2026-10-23: "spawn more
                               # LCAC's": four a lane, was two; Mission 13's unit has two, the others are copies)
LCAC_GAP_CM = 18000.0          # between two neighbours
LCAC_SEA_Z = -20.0             # Mission 13's craft and path points at sea
LCAC_SPEED = '180.0'           # Mission 13's (02_ReinforcementAppearance)
LCAC_RETURN_S = 20.0           # Mission 13's: landing to heading back out
# The troops drive from where their craft landed to the runway (user, 2026-10-23: "draw a path for the Troops to Drive
# on so that they reach the airfield"), each to its own spot along it (Mission 22's runway: centre, heading), on
# Mission 13's order (EvadeOnly: they keep driving) at LCAC_TROOP_SPEED; reaching the end of the path sets
# SV_LcacRunway<lane><craft> and Scripts/main.lua adds to the airfield's capture.
LCAC_RUNWAY = ((1609574.0, -435747.0), -23.0)
LCAC_RUNWAY_SPREAD_CM = 90000.0   # the spots, from one end of this stretch along the runway to the other
LCAC_GROUND_Z = 300.0             # path points over land (Mission 13's drive path: 48-200; the airport is near sea level)
LCAC_TROOP_SPEED = '60.0'         # km/h (Mission 13's 25.0)
LCAC_TROOP_SOURCE_PATH = '02_Ground0_Tank_0_Path0'


def lcac_craft():
    """One dict per landing craft: its lane's unit and object, its paths, its troops and its landing flag."""
    import math
    out = []
    (rx, ry), ryaw = LCAC_RUNWAY
    rux, ruy = math.cos(math.radians(ryaw)), math.sin(math.radians(ryaw))
    total = len(LCAC_LANES) * len(LCAC_CRAFT)
    for lane, start, beach in LCAC_LANES:
        dx, dy = beach[0] - start[0], beach[1] - start[1]
        length = math.hypot(dx, dy)
        ux, uy = dx / length, dy / length
        for k, c in enumerate(LCAC_CRAFT):
            side = (k - (len(LCAC_CRAFT) - 1) / 2.0) * LCAC_GAP_CM   # across the line, in order
            ox, oy = -uy * side, ux * side
            i = len(out)                                          # its spot on the runway
            along = (i / max(1, total - 1) - 0.5) * LCAC_RUNWAY_SPREAD_CM
            out.append(dict(
                lane=lane, craft=c, k=k, unit=f'SV_Unit_Lcac{lane}', obj_base=f'SV_Obj_Lcac{lane}',
                obj=f'SV_Obj_Lcac{lane}_{k}',                              # as event args write the 2-craft unit's objects
                path=f'SV_Path_Lcac{lane}{c}', back=f'SV_Path_Lcac{lane}{c}Back',
                troops=f'SV_Unit_LcacTroops{lane}{c}', troop_obj=f'SV_Obj_LcacTroops{lane}{c}',
                flag=f'SV_LcacLand{lane}{c}', land=f'SV_LcacLanded{lane}{c}', up=f'SV_LcacUp{lane}',
                drive=f'SV_Path_LcacDrive{lane}{c}', troops_up=f'SV_LcacTroopsUp{lane}{c}',
                rflag=f'SV_LcacRunway{lane}{c}', at_runway=f'SV_LcacAtRunway{lane}{c}',
                runway=(rx + rux * along, ry + ruy * along, LCAC_GROUND_Z),
                start=(start[0] + ox, start[1] + oy, LCAC_SEA_Z), beach=(beach[0] + ox, beach[1] + oy, float(beach[2])),
                yaw=math.degrees(math.atan2(dy, dx)), length=length))
    return out


# Special round "Ladon" (user, 2026-10-23: "adding the LADON special round, the HP needs to be nerfed a bit and their
# speed needs a nerf slightly, have them spawn on the far western side of the map and create a path that takes the
# players on a bit of a ride back to the airfield, have no other aircraft spawn"; "KOT and MISHKA are the two LADON
# names"). Two Ladons, each a copy of Mission 16's B_Unit_01_Air0 (its 18 parts: ChildAIObjectDescs with the parts'
# blueprint classes as imports, hard rule 7), each on a mission row of its own (sv_ladon_<key> -> SV_Ladon_<Key> in
# DT_SV_NpcRows, which Scripts/main.lua gives its name, health and speed). From the far west they fly LADON_ROUTE, a
# long way round, and over the airfield (its end: SV_LadonRun<Key> goes up by one, its first bombing run), then round
# and round the circuit (LADON_CIRCUIT_*), over the airfield once a lap; Scripts/sv_ladon.lua counts those passes by
# distance and drops its bombs on the airfield.
LADON_SOURCE_UNIT = 'B_Unit_01_Air0'
LADON_SOURCE_PATH = '01_Air0_Ladon_Path1'
LADON_SOURCE_ROW = 'OP0045_radn_01'          # Mission 16's mission row (NpcId OP0045_ladn_01)
LADON_NPC_SOURCE = 'OP0045_ladn_01'          # DT_NPC (1200 HP, LuaSet 0031_CP)
LADONS = [('Kot', 0.0, 0.0), ('Mishka', 2200.0, 300.0)]   # (key, offset north m, height offset m) - main.lua CFG.specials.ladon
# (x km, y km, altitude km): from the far west (Mission 22's combat zone runs to x -44 km), north, back south across
# the island's west, east along the south and in over the airfield (16.1, -4.4), where the route ends.
LADON_AIRFIELD = (16.1, -4.4, 1.2)
LADON_ROUTE = [(-42, 4, 3.0), (-34, 17, 3.2), (-20, 24, 2.8), (-6, 16, 2.2), (-11, 2, 1.8), (-3, -13, 2.4),
               (7, -19, 2.0), (12, -11, 1.6), LADON_AIRFIELD]
# (0.73.73) The circuit: a circle through the airfield, met along the route's way in (its tangent there is the route's
# last leg), the Ladon going round it for good (ladon_circuit). Why: an AI plane handed a new path at its last one's
# PathFinish flies it only when the new path's start lies a little ahead of it, along its way (hard rule 2): the route
# ran into the old circuit's first point, 6 deg off its way, and it was flown; that circuit ended over the airfield
# heading (0.99, -0.15) with its own start 1.5 km off to the side (74-88 deg), so every circuit after it (the same path
# again, 0.73.61; a copy, 0.73.62; the copy with the unit area moved, 0.73.69) was never flown: the Ladons held that
# path's end tangent exactly, heading and descent (A19, 12:02:13-12:03:24: (0.989, -0.148), -1.3 deg, from 1.1 km to
# 0.1 km and 50 km east; the tangent (0.988, -0.151), -1.26 deg), and no PathFinish came again (their pass flag stayed
# 2). The rage circuit (HOTFIX_NOTES open problem 2: "87 km east and below sea level") started at the same point.
# So the circle is two arcs, A (from LADON_ARC_STEP_DEG past the airfield to the far side) and B (from a step past A's
# end back to over the airfield), each one's end starting the other: every new path starts one step (2.5 km) ahead of
# the plane along the circle, and its own end is half a circle away (Mission 16's own chain is built so: Path0 to
# Path6, each next path 1-4 km ahead within 10 deg). Heights from LADON_CIRCUIT_ALT_KM[0] over the airfield to [1] on
# the far side.
LADON_CIRCUIT_KM = 8.0                       # its radius: the old circuit's tightest turns (~8 km) were flown at 2500
LADON_ARC_STEP_DEG = 18.0                    # its points (and each arc's start past the other's end) every N deg
LADON_CIRCUIT_ALT_KM = (1.25, 2.0)           # over the airfield, on the far side (the old circuit's)
# (0.73.74) The circuit's laps are part of the route's own path, LADON_LAPS of them after the route (each lap arc A then
# arc B, ending over the airfield where the next begins): the test of 2026-11-02 23:16 (0.73.73) showed arc A handed
# over at the route's PathFinish was never flown at LADON_SPEED (2500 km/h: its start 2.5 km ahead is 3.6 s away; the
# Ladons held the route's end tangent, descending to 0.2 km 29 km out, legs 0), while VOID WATCHER took the same kind of
# handover at 450-550 km/h. The one path an AI plane has always flown is the first one, started at its appearance; so no
# handover at all until the laps run out (~72 s a lap at 2500: 15 laps ~18 minutes); then arc A / B as before.
LADON_LAPS = 15
# The enraged Ladon (behaviour roadmap P7: "after one Ladon dies the other changes route and volleys faster";
# Scripts/sv_ladon.lua SPC.ladonRage, CFG.specials.ladon.rage; docs/re/BEHAVIOUR_DIRECTOR.md unit 9): Lua fires
# RE_SV_LadonRage<Key>, which sets SV_LadonRage<Key>, and each arc's end starts the next at LADON_RAGE_SPEED (flag-gated
# records, no delay: hard rule 26). (0.73.73) The same circle, faster: a tighter circuit of its own would need a new
# path started off the circle, which is what was never flown.
LADON_RAGE_SPEED = '3000.0'                  # km/h (Mission 16's Ladon: 1200-3200)
# (0.73.73) Lua's backstop (Scripts/sv_ladon.lua, CFG.specials.ladon.leash_*): a Ladon leash_km from the airfield
# after its first pass is off its circuit; RE_SV_LadonLeash<Key> takes it off its path (Mission 22's
# LiveAIPathExitExecution, as its airport strike leaves its path) and moves its unit area onto the airport at
# LADON_LEASH_AREA_M, where an AI plane with no path circles (VOID WATCHER's, 0.73.62). (0.73.69 moved the area onto
# the airport at every lap but never took the Ladon off its path: it flew on 50 km east all the same.)
LADON_LEASH_AREA_M = 6000.0
# the Ladons' unit area (a unit only fights inside it; build_survival.ladon_units): centred on the whole job, not the
# spawn, big enough for all of it (code review of 2026-10-23: 40 km round the spawn left the airfield 59 km out, so the
# AI kept turning them back west)
LADON_AREA = ((-9.0, 2.0), 80000.0)          # (centre x, y km), radius m
# the parts that fire. The CIWS turrets: Mission 16's Normal engagement order on each (its Default_RemoteEvent_20
# record). The missiles never fire on an order alone (test of 2026-10-23: none at all): Mission 16 opens the missile
# hatch and fires each VLS at its target with LiveFireOneShotWeapon, so RE_SV_LadonVolley<Key> does that at the
# player, and Scripts/main.lua fires it while the player is in range (CFG.specials.ladon.volley_*).
LADON_CIWS = ['LCIWS', 'LCIWS1', 'LCIWS2', 'LCIWS3']
# ... which carry the Arsenal Bird's pulse cannons (user, 2026-10-23: "put the Pulse Lasers that the Arsenal Bird uses
# online, and Replace the Ladon's CIWS with them"): Online Mode boss BA001 (aias) fires them from its PC_L / PC_R pods,
# AITurret pawns whose blueprint carries the weapon (AIAS_CannonPod -> BP_wp_pulse_cannon_aias). Each CIWS slot gets
# that pod's class (from EB_001's world data) and NPC row (Online Mode's aias_CannonPod_01, which Scripts/main.lua adds
# to the campaign's DT_NPC at the main menu with the Alicorn's rows: build_survival.build_alicorn_rows).
LADON_PULSE_WD = '/Game/OnlineMode/Maps/EmergencyCall/EB_001/WD_EB_001'
LADON_PULSE_PART = 'PC_L'
LADON_PULSE_NPC = 'aias_CannonPod_01'
LADON_VLS = ['VLS0', 'VLS1']
LADON_SPEED = '2500.0'                       # km/h (user, 2026-10-23: "make the Ladon Speed 2500"; was 1500. Mission 16: 1200-3200)


def circle_point(c, r, a0, sense, psi_deg, alt_km):
    """(x, y, alt) km on the circle round c (km) of radius r, psi_deg round from angle a0 (rad) in `sense` (+1 / -1)."""
    import math
    a = a0 + sense * math.radians(psi_deg)
    return (c[0] + r * math.cos(a), c[1] + r * math.sin(a), alt_km)


def ladon_circuit():
    """KOT's circuit (LADON_CIRCUIT_*, km): the circle through LADON_AIRFIELD along the route's last leg, its centre on
    that leg's left. {'centre', 'arc_a', 'arc_b' (points), 'a_before', 'a_after', 'b_before', 'b_after' (the points just
    outside each arc, for its tangents), 'pt' (psi deg round from the airfield -> point)}."""
    import math
    (ax, ay, _), (px, py, _) = LADON_AIRFIELD, LADON_ROUTE[-2]
    n = math.hypot(ax - px, ay - py)
    ux, uy = (ax - px) / n, (ay - py) / n                  # the way in over the airfield
    r = LADON_CIRCUIT_KM
    c = (ax - r * uy, ay + r * ux)                         # (left of it: the circle runs on along u, counter-clockwise)
    a0 = math.atan2(ay - c[1], ax - c[0])
    lo, hi = LADON_CIRCUIT_ALT_KM
    pt = lambda psi: circle_point(c, r, a0, 1, psi, lo + (hi - lo) * (1.0 - math.cos(math.radians(psi))) / 2.0)
    step = LADON_ARC_STEP_DEG
    assert abs(180.0 / step - round(180.0 / step)) < 1e-9, 'LADON_ARC_STEP_DEG must divide 180'
    k = int(round(180.0 / step))
    arc_a = [pt(step * i) for i in range(1, k + 1)]                    # one step past the airfield .. the far side
    arc_b = [pt(180.0 + step * i) for i in range(1, k + 1)]            # one step past that .. over the airfield
    return dict(centre=c, pt=pt, arc_a=arc_a, arc_b=arc_b, a_before=pt(0.0), a_after=pt(180.0 + step),
                b_before=pt(180.0), b_after=pt(360.0 + step))


def ladons():
    """One dict per Ladon: unit, object, mission / NPC rows, paths, flags, events, its route and circuit's arcs (cm)."""
    out = []
    cc = ladon_circuit()
    for key, side_m, up_m in LADONS:
        def place(pts):
            """pts shifted side_m north (+y) and up_m up: one fixed shift for the whole track, so its shape, its
            joins and its turns are KOT's (a shift to the side of the way on flipped across the turn over the airfield:
            MISHKA's next circuit began 1.7 km behind it)"""
            return [(x * 100000.0, (y + side_m / 1000.0) * 100000.0, (a * 1000.0 + up_m) * 100.0) for x, y, a in pts]
        out.append(dict(key=key, unit=f'SV_Unit_Ladon{key}', obj=f'SV_Obj_Ladon{key}', row=f'sv_ladon_{key.lower()}',
                        npc=f'SV_Ladon_{key}', name_key=f'SV_Ladon_{key}', path=f'SV_Path_Ladon{key}',
                        flag=f'SV_LadonRun{key}', up=f'SV_LadonUp{key}', over=f'SV_LadonOver{key}',
                        route=place(LADON_ROUTE),
                        # (0.73.73) its circuit's two arcs (ladon_circuit), their PathFinish triggers and the points just
                        # outside each (its tangents); SV_LadonLeg<Key> + 1 at each arc's end (the log's "legs": the
                        # circuit being flown)
                        arc_a=f'SV_Path_Ladon{key}ArcA', arc_b=f'SV_Path_Ladon{key}ArcB',
                        leg_a=f'SV_LadonLegA{key}', leg_b=f'SV_LadonLegB{key}', leg=f'SV_LadonLeg{key}',
                        arc_a_pts=place(cc['arc_a']), arc_b_pts=place(cc['arc_b']),
                        a_before=place([cc['a_before']])[0], a_after=place([cc['a_after']])[0],
                        b_before=place([cc['b_before']])[0], b_after=place([cc['b_after']])[0],
                        # (0.73.73) its appearance runs once a spawn (HOTFIX_NOTES open problem 3): SV_LadonDone<Key> set
                        # by it, cleared by Lua's RE_SV_LadonRearm<Key> once it's gone; SV_LadonSeen<Key> counts its
                        # appearance's fires (Lua logs a fire again); Lua's backstop RE_SV_LadonLeash<Key>
                        done=f'SV_LadonDone{key}', seen=f'SV_LadonSeen{key}', rearm=f'RE_SV_LadonRearm{key}',
                        leash=f'RE_SV_LadonLeash{key}',
                        # its rage (P7): the flag and Lua's remote event (the same circuit, LADON_RAGE_SPEED)
                        rage_flag=f'SV_LadonRage{key}', rage_ev=f'RE_SV_LadonRage{key}'))
    return out


# Special round "Alicorn" (user, 2026-10-23: "start working on the ALICORN special round ... spawn none of the normal
# aircraft"; docs/re/ALICORN.md): the submarine carrier exists only in Online Mode, as Emergency Call EB_002's boss
# (unit Boss_0: one AI object with 30 parts, their blueprints Online Mode's). Survival's copy keeps the hull, core,
# ballast tanks, railguns, rail cannon, ECM, VLS and the 12 weapon hatches, and leaves out the pools of fighters and
# drones it launches (ALCN_DROP). It sails Mission 22's allied fleet lane in the west sea and back (EB_002's speed,
# 120); Scripts/main.lua fires its actions as remote events: dive / surface, railgun, the VLS volley at the player,
# and once its four ballast tanks are gone the core's opening (ALCN_OpenCore). Destroying the core sinks it.
ALCN_SOURCE_UNIT = 'Boss_0'
ALCN_SOURCE_PATH = 'Path_Boss0_ALCN_0_0'
ALCN_ROW = 'alcn_01'                          # mission row = NpcId (DT_NPC_Mission_EB_002_ON / DT_NPC_ON)
ALCN_UNIT, ALCN_OBJ = 'SV_Unit_Alicorn', 'SV_Obj_Alicorn'
ALCN_DROP = {'airs0', 'airs1', 'airs2', 'Airs0', 'Airs1', 'Airs2', 'BarrierDrones', 'SLUAVs'}
# (x km, y km): Mission 22's allied fleet lane (01_Ship0_freeAlly_0_Path0: -27.7,-4.4 -> -15.3,-6.3), on east a little
ALCN_ROUTE = [(-27.7, -4.4), (-23.0, -5.1), (-19.0, -5.8), (-15.3, -6.3), (-11.5, -6.4)]
ALCN_SPEED = '120.0'
ALCN_VLS = ['vls_L_1', 'vls_L_2', 'vls_R_1', 'vls_R_2']
# The parts' damage table (user, 2026-10-23: "how tough are those ballast tanks"; 14 missiles and specials took none
# down; then "lower the health down on the alicorns weaponry"): Online Mode's NWDID_SubMarine* tables take 10-62.5 %
# from most weapon categories. Every part row naming one (the ballast tanks, the core, the railguns, VLS, hatches and
# their guns, the ECM; not the hull ALCN_ROW) names Survival's copy ALCN_PART_DURABILITY instead: 100 % from every
# category. Their health is main.lua's (CFG.specials.alicorn tank_missiles / weapon_missiles / railgun_missiles).
ALCN_DURABLE_FROM = 'NWDID_SubMarine'          # (a prefix: NWDID_SubMarine, ..MainArm, ..Ciws, ..ECM)
ALCN_DURABLE_MIN = 5                           # at least the 4 tanks and the core
ALCN_PART_DURABILITY = 'NWDID_SV_AlcnParts'
ALCN_PART_DURABILITY_SOURCE = 'NWDID_SubMarine'
# the railguns: _Distributed, as EB_002 fires them (TargetMode 1: at the players); _Focus (TargetMode 0) didn't aim at
# the player (user, 2026-10-23: "the alicorns railguns ... don't seem to target the player")
ALCN_ACTIONS = {'RE_SV_AlcnRailgun': 'ALCN_ShotRailgun_Distributed', 'RE_SV_AlcnOpenCore': 'ALCN_OpenCore',
                'RE_SV_AlcnAdvance': 'ALCN_AdvancePhase'}


def alcn_paths():
    """The Alicorn's way out and back (cm, on the surface)."""
    out = [(x * 100000.0, y * 100000.0, 0.0) for x, y in ALCN_ROUTE]
    return [('SV_Path_AlicornOut', out), ('SV_Path_AlicornBack', list(reversed(out)))]


def lcac_lane_names():
    return [lane for lane, _, _ in LCAC_LANES]


# Special round "The Anomaly" (docs/re/SPECIAL_ROUNDS.md 13; user, 2026-10-22: the ace flies an F-4 and is named
# MINDRIPPER; its own HUD warning; the mission-update beep when its round starts; the shuttle's zoom-in camera on it).
# build_survival.py copies pool flight ANOMALY_SOURCE (Survival's fighter behaviour, 40 km area) into MINDRIPPER's own
# one-aircraft unit and a guard unit; Scripts/main.lua spawns both, gives MINDRIPPER its NPC row and flies the field
# (inside 3 km the player's pitch and roll invert: dlls/main.dll SV_Invert). The records here are the stock
# presentation: Mission 22's MISSION UPDATE message (its beep) and focus camera, and Mission 15's forced WARNING
# message, radar noise and glasses effect (Graph.foreign_template: classes Mission 22's package doesn't import).
ANOMALY_SOURCE = 'ERA_Unit_01_Dep_Air1'     # a 4-ship of the pool
ANOMALY_UNIT = 'SV_Unit_Anomaly'
ANOMALY_GUARD_UNIT = 'SV_Unit_AnomalyGuards'
ANOMALY_GUARDS = 4
ANOMALY_GUARD_RADIUS_M = 2000.0             # its guards' unit area, on it: they circle inside it
# The game's throttle on how hard enemies may press the player (Mission 22 sets it per wave): how many missiles may be
# aimed at the player at once, how many enemies may attack at once, and its attack cooldowns. Survival never set it, so
# it ran on the game's defaults; ATTACK_BASE (Mission 22's wave 3) from the mission start and after the Anomaly, and
# while MINDRIPPER is up ANOMALY_ATTACK (user, 2026-10-22: "mindripper still wasn't aggressive enough").
ATTACK_BASE = {'missiles': 4, 'attackers': 6, 'cooldown': (4.0, 8.0, 15.0, 20.0)}
ANOMALY_ATTACK = {'missiles': 8, 'attackers': 10, 'cooldown': (0.5, 1.0, 3.0, 5.0)}
# The throttle's presets Lua picks (behaviour roadmap P8 x P4, docs/re/BEHAVIOUR_DIRECTOR.md unit 3): remote events
# RE_SV_Pressure<letter> (letters: hard rule 17), built in build_anomaly with its attack(). Scripts/sv_rounds.lua fires
# one by round band (CFG.late.pressure: C from round 26, D from 31, so the attackers at once stay about a third of the
# most up), never in an Anomaly or VALKA round (their records below set ANOMALY_ATTACK and put ATTACK_BASE back), and
# again the round after them. A: a lull (for the intensity director, P4); B: ATTACK_BASE. Keep the letters in step
# with Scripts/sv_config.lua TIER.PRESSURE_PRESETS (build_anomaly checks it). Their effect was never measured.
PRESSURE = {'A': {'missiles': 2, 'attackers': 3, 'cooldown': (8.0, 12.0, 20.0, 25.0)},
            'B': ATTACK_BASE,
            'C': {'missiles': 6, 'attackers': 8, 'cooldown': (2.0, 4.0, 8.0, 12.0)},
            'D': {'missiles': 8, 'attackers': 10, 'cooldown': (1.0, 2.0, 5.0, 8.0)}}
ANOMALY_OBJ = None                          # MINDRIPPER's AI object name, set by build_survival.py copy_unit
# The arrival (user, 2026-10-22: "the zoom in camera appears, then the portal, then MINDRIPPER"): it spawns hidden
# (Scripts/main.lua CFG.specials.anomaly.portal) and the focus camera swings onto it at once; Lua opens the portal on it
# and shows it ~3 s in, so the camera holds on through the burst.
ANOMALY_CAMERA_S = 9.0                      # (Mission 22's shuttle camera: 9 s)
# Its camera settings (BP_InGameCameraParameter names): RE_SV_AnomalyCam_<n> focuses on it with the nth, then lets go;
# Scripts/main.lua fires the one CFG.specials.anomaly.camera names (user, 2026-10-22: ms22-01, the shuttle's, was
# "far too zoomed in"; the game zooms harder the farther the target is). Keep in step with main.lua ANOMALY_CAMERAS.
ANOMALY_CAMERAS = ['LookAt_Event_Camera', 'LookAt_Event_Camera_ms08-01', 'LookAt_Event_Camera_ms04-01',
                   'LookAt_Event_Camera_ms23-01', 'LookAt_Event_Camera_ms22-01']
ANOMALY_HUM = 'AKE_Ms23_ARMS_SKY_OP0049_cleo_ControlUnit_Electricity_'   # + Play / Stop: the Celaeno core's crackle
# its death plays the Celaeno's (Mission 23; user, 2026-10-22: "the celaeno has this special sound when its destroyed,
# add that when MINDRIPPER is destroyed"): the airship's three-part body explosion, on its wreck, seconds after the
# kill. Mission 23's sound events: Scripts/main.lua loads their assets when the level starts (CFG.specials.anomaly).
ANOMALY_DOWN_SOUNDS = [(0.0, 'AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq01_Play'),
                       (1.5, 'AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq02_Play'),
                       (3.0, 'AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq03_Play'),
                       (0.5, 'AKE_Ms23_ARMS_SKY_OP0049_cleo_ControlUnit_Collapse_Play')]
# Special round "AB.L..IN" (user, 2026-10-23: "One Last Anomaly. an EA-18G Growler ... its Squadron Tag is IFF: FATAL
# ERROR, it's name is AB.L..IN"): one EA-18G (the campaign named-ace row, its ECM pod held up by main.lua) in its own
# one-aircraft unit, a copy of pool flight ANOMALY_SOURCE like MINDRIPPER's; Scripts/main.lua spawns it hidden, shows
# it in a puff of smoke and, each time it's hit, blinks it around the player for a few seconds, aimed at them, gun
# firing (CFG.specials.glitch). The records here: the pool's orders and the MISSION UPDATE banner when it appears.
GLITCH_UNIT = 'SV_Unit_Glitch'
GLITCH_OBJ = None                           # its AI object name, set by build_survival.py build_wd_global
# Its blinks (user, 2026-10-23: "the teleport did not work": Lua's K2_SetActorLocationAndRotation read back right but
# the flight model put the plane back): Mission 22's LiveActorTeleportExecution, which moved its dummies onto the player
# (target Player, world offsets, Absolute), one remote event per spot: RE_SV_GlitchBlink_<tag> puts AB.L..IN `m` metres
# from the player at bearing `deg` (world: 0 = +X, 90 = +Y), at their height, its nose (yaw) on them. Scripts/main.lua
# picks the spot (CFG.specials.glitch.blinks: keep in step).
# Its gun and ECM pod on command (user, 2026-10-23: "no crazy guns either"; "ECM didn't turn on"): Mission 19's
# LiveFireOneShotWeapon, which has a Rafale fire WN_WEAPON_3 at the player. WN_WEAPON_<n> is fire-control slot n - 1
# (that Rafale's row: flares, gun, missiles; the Ladon VLS's WN_WEAPON_1 / _2 are its two missiles), so on the EA-18G's
# row (flares, gun, missiles, ECM) the gun is WN_WEAPON_2 and the ECM pod WN_WEAPON_4. Scripts/main.lua fires
# RE_SV_GlitchGun through each frenzy and RE_SV_GlitchEcm every ecm_every_s.
GLITCH_GUN_SLOT = 'WN_WEAPON_2'
GLITCH_ECM_SLOT = 'WN_WEAPON_4'
# each RE_SV_GlitchGun fires the gun GLITCH_GUN_SHOTS times GLITCH_GUN_EVERY_S apart (user, 2026-10-23: "make it fire at
# 0.1"; Lua's tick is 250 ms, so the repeat is the record's: delay + loop, as the bombers' runs); main.lua fires the
# event every GLITCH_GUN_SHOTS x GLITCH_GUN_EVERY_S (CFG.specials.glitch.gun_every_s: keep in step)
# its post-stalls, RE_SV_Glitch<name> -> the stock unique action (Mission 28's Shadows', Mission 19's Toprak's kulbit,
# Mission 2's Tasha's cobra); main.lua CFG.specials.glitch.post_stall_moves names the same <name>s. 'Turn' (the campaign
# aces' LastTGT, RE_SV_GlitchTurn) is its phase 3's (behaviour roadmap P7, CFG.specials.glitch.phases: onto you every
# allout_turn_s and when you're behind it), never one of post_stall_moves, which are picked at random
GLITCH_POST_STALL = (('Kulbit', 'Shadow_Kulbit'), ('KulbitB', 'Toprak_Kulbit'), ('Cobra', 'Tasha_Cobra'), ('Turn', 'LastTGT'))
GLITCH_GUN_EVERY_S = 0.1
GLITCH_GUN_SHOTS = 5
GLITCH_BLINK_STEP_DEG = 30
GLITCH_BLINK_RINGS_M = (500, 800)


def glitch_blinks():
    """[(event, bearing deg, metres)]; tags are letters (hard rule 17)."""
    out = []
    for ring, m in enumerate(GLITCH_BLINK_RINGS_M):
        for k, deg in enumerate(range(0, 360, GLITCH_BLINK_STEP_DEG)):
            out.append((f'RE_SV_GlitchBlink_{chr(65 + ring)}{chr(65 + k)}', deg, m))
    return out


# Special round "VALKA" (user, 2026-10-24: "port the Mihaly fight from ACE7 into ACE8 Survival Mode as an Anomaly Boss
# ... VALKA, who uses an EML"): AC7 Mission 18's opener, then a Super AI with AB.L..IN's blinks and a chance of
# MINDRIPPER's inverted controls. AC7's opener (ms18_Phase_01, docs/re/VALKA.md): a hidden dummy railgun of its own
# (ms18_dummy_eml_p1, not Mihaly), placed once ahead of the player along where they're aiming, facing them, charges
# 6 s (HUD warning, a flash of light at it), then fires at them; Mihaly shows after. Ours: the dummy is the X-40A's
# RailGun part alone (VALKA_EML_*: DT_NPC OP1016_x40a_RG on its own unit), spawned once by main.lua 9 km along your aim
# (user, 2026-10-24: "9km from me in a fixed position in the sky that the player was currently aiming at, she can't
# be attached to the aircraft at all"; AC7's 70000 is not 700 m), held (EvadeOnly) and fired once (RE_SV_ValkaEmlShot:
# Mission 26's LiveFireOneShotWeapon on its x40a's railgun), then removed; VALKA spawns at its spot after the shot and
# the focus camera swings onto her. AC8 has no X-02S: she flies Mission 26's X-40A (EI_Unit_01_Air0 with its four
# parts, ported as the Ladon is) until the X-02S model is built.
# Scripts/main.lua CFG.specials.valka drives it (SPC.V.*); keep VALKA_SPOTS in step with its `spots`.
VALKA_SOURCE_UNIT = 'EI_Unit_01_Air0'          # Mission 26's x40a ("Nightmare") and its parts
VALKA_UNIT = 'SV_Unit_Valka'
VALKA_OBJ = None                               # her AI object name, set by build_survival.py valka_unit
VALKA_PARTS = {}                               # component -> its object name (RailGun, RailGunCK, RailGunPF, LaserPod)
VALKA_RAILGUN = 'RailGun'                      # the part she fires (the CK one is Mission 26's scripted sure kill)
VALKA_IDLE_PARTS = ('RailGunCK', 'RailGunPF', 'LaserPod')   # held back (EvadeOnly), as Mission 26 holds its CK railgun
VALKA_EML_UNIT = 'SV_Unit_ValkaEml'            # the opener's dummy railgun (build_survival.py valka_eml_unit)
VALKA_EML_OBJ = 'SV_Obj_ValkaEml'
VALKA_EML_ROW = 'sv_valka_eml'                 # mission row -> DT_NPC OP1016_x40a_RG (the x40a's RailGun part)
VALKA_EML_NPC = 'OP1016_x40a_RG'
VALKA_MISS_UP_M = 250                           # the opener's aim: a dummy this high above the player (it has to miss)
VALKA_DUMMY = 'A_Obj_01_dummyN0'                # Mission 22's dummy (Unit_dummyN0, in Survival's world data, unused)
# teleport rings for her blinks: (ring letter, metres, step deg)
VALKA_SPOTS = (('B', 500, 30), ('C', 800, 30))
VALKA_CHARGE_SOUND = 'AKE_Ms29_ARMS_SKY_OP1016_x40a_Railgun_Charge_'      # + Play / Stop: the x40a railgun's charge
VALKA_POST_STALL = (('Turn', 'LastTGT'), ('Kulbit', 'Shadow_Kulbit'), ('KulbitB', 'Toprak_Kulbit'), ('Cobra', 'Tasha_Cobra'))


def valka_spots():
    """[(event, bearing deg, metres)]: two bearing letters (36 steps), no digits (hard rule 17)."""
    out = []
    for ring, m, step in VALKA_SPOTS:
        for k, deg in enumerate(range(0, 360, step)):
            out.append((f'RE_SV_ValkaTp_{ring}{chr(65 + k // 26)}{chr(65 + k % 26)}', deg, m))
    return out


def build_amphib(g, flag, stock_ep):
    """The amphibious assault (LCAC_*), in Mission 13's order (hard rule 5): the lane's craft appear -> each craft and
    the unit get their path -> PathFinish (hard rule 1) -> the craft leaves its path, SV_LcacLand<lane><craft> = 1
    (Scripts/main.lua spawns its troops) -> LCAC_RETURN_S later back out along the lane. RE_SV_LcacRemove<lane> and
    RE_SV_LcacTroopsRemove<lane><craft> (main.lua) take a lane's craft / a craft's troops off, so they can come again."""
    m13 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission013', 'EP_Mission013_global.uasset')
    t_cpath = g.foreign_template(m13, 'LiveAIPathExecution', '02_ReinforcementAppearance',
                                 lambda a, e: a[0] == 'E_Obj02_02_Ship0_lcac_0')
    t_upath = g.foreign_template(m13, 'LiveAIPathExecution', '02_ReinforcementAppearance',
                                 lambda a, e: a[1] == 'E_Unit02_02_Ship0')
    t_exit = g.foreign_template(m13, 'LiveAIPathExitExecution', '02_LCAC_PathFinish_0')
    t_remove = g.exec_template('LiveDestroyUnitExecution', 'Debug_Destroy_Shuttle')
    t_tpath = g.foreign_template(m13, 'LiveAIPathExecution', '02_Reinforce_tank_0',
                                 lambda a, e: a[0] == 'E_Obj02_02_Ground0_tank_0')
    t_tengage = g.foreign_template(m13, 'LiveAIEngagementOrder', '02_Reinforce_tank_0',
                                   lambda a, e: a[1] == 'E_Unit02_02_Ground0')
    assert arg_values(t_tpath)[2] == LCAC_TROOP_SOURCE_PATH and arg_values(t_tengage)[3] == 'EvadeOnly'
    assert arg_values(t_cpath)[2] == LCAC_SOURCE_PATH and arg_values(t_cpath)[4] == LCAC_SPEED, arg_values(t_cpath)
    assert arg_values(t_upath)[2] == LCAC_SOURCE_PATH, arg_values(t_upath)
    finish = '01_A_Air1_f18e_PathFinish'                   # PathFinish trigger template: {0 object, 2 path}
    craft = lcac_craft()
    for lane in lcac_lane_names():
        cs = [c for c in craft if c['lane'] == lane]
        up = cs[0]['up']
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: cs[0]['unit']})
        for c in cs:
            flag(up, c['flag'], 'Set', 0)
            g.execute(t_cpath, up, {0: c['obj'], 2: c['path']}, delay=0.5 + c['k'] * 1.5)
        g.execute(t_upath, up, {1: cs[0]['unit'], 2: cs[0]['path']}, delay=0.5)
        rm = f'RE_SV_LcacRemove{lane}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', rm)                  # a remote-event trigger
        g.execute(t_remove, rm, {0: 'NoneSelect', 1: cs[0]['unit'], 2: 'NoneSelect'})
        for c in cs:
            g.trigger(finish, c['land'], arg_changes={0: c['obj'], 2: c['path']})
            g.execute(t_exit, c['land'], {0: c['obj']})
            flag(c['land'], c['flag'], 'Set', 1)
            g.execute(t_cpath, c['land'], {0: c['obj'], 2: c['back']}, delay=LCAC_RETURN_S)
            # its troops: off the beach along their path to the runway, driving on whatever shoots at them
            g.trigger('01_E_AreaA_ReinforcementAppearance_0', c['troops_up'], arg_changes={0: c['troops']})
            flag(c['troops_up'], c['rflag'], 'Set', 0)
            g.execute(t_tengage, c['troops_up'], {1: c['troops']})
            g.execute(t_tpath, c['troops_up'], {0: c['troop_obj'], 2: c['drive'], 4: LCAC_TROOP_SPEED}, delay=0.5)
            g.trigger(finish, c['at_runway'], arg_changes={0: c['troop_obj'], 2: c['drive']})
            flag(c['at_runway'], c['rflag'], 'Set', 1)
            trm = f'RE_SV_LcacTroopsRemove{lane}{c["craft"]}'
            g.trigger('RE_SpawnEnemy_kokatu_1st', trm)
            g.execute(t_remove, trm, {0: 'NoneSelect', 1: c['troops'], 2: 'NoneSelect'})


def build_ladon(g, flag, stock_ep):
    """The Ladons (LADON*), on Mission 16's records: appearance -> its route (PathFinish triggers: hard rule 1) and
    Mission 16's Normal engagement order; the end of the route -> SV_LadonRun<Key> + 1 and its circuit's arc A; each
    arc's end -> SV_LadonLeg<Key> + 1 and the other arc (ladon_circuit). RE_SV_LadonLeash<Key> (Lua's backstop): off its
    path, its area onto the airport. RE_SV_LadonRearm<Key>: its appearance may run again (the next spawn)."""
    m16 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission016', 'EP_Mission016_global.uasset')
    t_path = g.foreign_template(m16, 'LiveAIPathExecution', 'PathFinish_Ladon0_0', lambda a, e: a[0] == 'B_Obj_01_Air0_Ladon0')
    t_eng = g.foreign_template(m16, 'LiveAIEngagementOrder', 'Default_CompositeEvent_83',
                               lambda a, e: a[0] == 'B_Obj_01_Air0_Ladon0')
    assert arg_values(t_eng)[3] == 'Normal', arg_values(t_eng)
    # its guns' own orders (code review of 2026-10-23: only the body had one) and its missile volleys (LADON_VLS)
    t_ciws = g.foreign_template(m16, 'LiveAIEngagementOrder', 'Default_RemoteEvent_20',
                                lambda a, e: a[0] == 'B_Obj_01_Air0_Ladon0_LCIWS')
    assert arg_values(t_ciws)[3] == 'Normal' and arg_values(t_ciws)[6] == 'PlayerFirst', arg_values(t_ciws)
    t_hatch = g.foreign_template(m16, 'LiveFireOneShotWeapon', 'Default_VolumeEvent_51',
                                 lambda a, e: a[1] == 'B_Obj_01_Air0_Ladon0_MissileHatch')
    t_vls = g.foreign_template(m16, 'LiveFireOneShotWeapon', 'Default_CompositeEvent_44',
                               lambda a, e: a[1] == 'B_Obj_01_Air0_Ladon0_VLS0' and a[2] == 'A_Obj_01_Air0_f18c_0')
    assert arg_values(t_hatch)[0] == 'WN_WEAPON_1' and arg_values(t_vls)[0] == 'WN_WEAPON_2', (arg_values(t_hatch), arg_values(t_vls))
    finish = '01_A_Air1_f18e_PathFinish'                   # PathFinish trigger template: {0 object, 2 path}
    m06 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'MIssion006', 'EP_Mission006_global.uasset')
    t_radius = g.foreign_template(m06, 'LiveChangeUnitRadius', 'PhaseStart_Phase02_2')
    t_bmove = g.exec_template('LiveUnitMoveActor', 'Default_CompositeEvent_19')       # unit area onto AreaB_MarkActor0
    assert arg_values(t_bmove)[3] == AIRFIELD_MARK, arg_values(t_bmove)
    # (0.73.73) Mission 22's airport strike leaves its path so (Default_CompositeEvent_19: LiveAIPathExitExecution on
    # each aircraft, then its area onto the airport)
    t_exit = g.exec_template('LiveAIPathExitExecution', 'Default_CompositeEvent_19', lambda a, e: a[0] != 'NoneSelect')
    assert arg_values(t_exit)[1] == 'NoneSelect', arg_values(t_exit)
    for L in ladons():
        up = L['up']
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: L['unit']})
        # (0.73.73) once a spawn (HOTFIX_NOTES open problem 3: a volley after its first pass fired its appearance again,
        # which set its pass count to 0 and sent it back onto its route from the far west, "the Ladon left the map"):
        # what restarts it is gated on SV_LadonDone<Key> 0 (conditions are read as the appearance fires: hard rule 26),
        # which its last record sets 1 half a second on; Lua's RE_SV_LadonRearm<Key> clears it once that Ladon is gone.
        # Its orders, harmless again, stay ungated (a co-op joiner's copies, spawned again, need them). Each fire
        # counted.
        once = lambda: [g.cond(L['done'], 'Leq', 0)]
        flag(up, L['seen'], 'Add', 1)
        flag(up, L['flag'], 'Set', 0, conds=once())
        flag(up, L['leg'], 'Set', 0, conds=once())
        g.execute(t_path, up, {0: L['obj'], 2: L['path'], 4: LADON_SPEED}, delay=1.0, conds=once())
        g.execute(t_eng, up, {0: L['obj']}, delay=2.0)
        for part in LADON_CIWS:
            g.execute(t_ciws, up, {0: f"{L['obj']}_{part}"}, delay=2.5)
        # one launcher a volley (user, 2026-10-23: "nerf the enemy LADONs VLS, way too insane": both at once shot the
        # player down within 9 s of the first volley): RE_SV_LadonVolley<Key>L / R, main.lua alternates them
        for side, part in zip('LR', LADON_VLS):
            volley = f"RE_SV_LadonVolley{L['key']}{side}"
            g.trigger('RE_SpawnEnemy_kokatu_1st', volley)
            g.execute(t_hatch, volley, {1: f"{L['obj']}_MissileHatch"})
            # WN_WEAPON_1: the launcher's ordinary missile (BP_wp_vls_ladon). WN_WEAPON_2, Mission 16's record, is
            # BP_wp_vls_certain_ladon, the scripted sure kill it fires at the allied F/A-18s: flares did nothing
            # against it (user, 2026-10-23: "the VLS guidance needs to be nerfed ... Flares don't even work")
            g.execute(t_vls, volley, {0: 'WN_WEAPON_1', 1: f"{L['obj']}_{part}", 2: 'Player'}, delay=1.5)
        # its rage (P7): Lua's RE_SV_LadonRage<Key> sets the flag (its appearance clears it), and each arc's end starts
        # the next at LADON_RAGE_SPEED (conditions checked as the PathFinish fires, after Lua set the flag: hard rule 26)
        flag(up, L['rage_flag'], 'Set', 0, conds=once())
        g.trigger('RE_SpawnEnemy_kokatu_1st', L['rage_ev'])
        flag(L['rage_ev'], L['rage_flag'], 'Set', 1)
        # (0.73.73) the route's end over the airfield (its first pass: SV_LadonRun<Key>) -> arc A; each arc's end -> the
        # other arc (ladon_circuit: every new path one step ahead of it, its own end half a circle away), as Mission 16
        # chains its Ladon's paths (PathFinish -> the next path, no delay). Its later passes Lua counts by distance.
        for ev, path, nxt in ((L['over'], L['path'], L['arc_a']), (L['leg_a'], L['arc_a'], L['arc_b']),
                              (L['leg_b'], L['arc_b'], L['arc_a'])):
            g.trigger(finish, ev, arg_changes={0: L['obj'], 2: path})
            flag(ev, L['flag'] if ev == L['over'] else L['leg'], 'Add', 1)
            g.execute(t_path, ev, {0: L['obj'], 2: nxt, 4: LADON_SPEED}, conds=[g.cond(L['rage_flag'], 'Leq', 0)])
            g.execute(t_path, ev, {0: L['obj'], 2: nxt, 4: LADON_RAGE_SPEED}, conds=[g.cond(L['rage_flag'], 'Geq', 1)])
        # (0.73.73) Lua's backstop, a Ladon off its circuit: off its path, its area onto the airport (LADON_LEASH_AREA_M)
        g.trigger('RE_SpawnEnemy_kokatu_1st', L['leash'])
        g.execute(t_exit, L['leash'], {0: L['obj']})
        g.execute(t_bmove, L['leash'], {0: L['unit']}, delay=0.5)
        g.execute(t_radius, L['leash'], {0: L['unit'], 1: 'NoneSelect', 2: f'{LADON_LEASH_AREA_M:.1f}'}, delay=1.0)
        # (0.73.73) its appearance may run again (Lua, once this Ladon is gone; it's set half a second after a fire)
        g.trigger('RE_SpawnEnemy_kokatu_1st', L['rearm'])
        flag(L['rearm'], L['done'], 'Set', 0)
        flag(up, L['done'], 'Set', 1, delay=0.5)           # (its appearance's last record: after every check above)
    import re
    lua = runtime_lua()
    for name in ('"RE_SV_LadonRage"', '"RE_SV_LadonLeash"', '"RE_SV_LadonRearm"', '"SV_LadonLeg"', '"SV_LadonSeen"',
                 '"SV_LadonDone"'):
        assert name in lua, f'Scripts/sv_ladon.lua never names {name}'
    m = re.search(r'names = \{ Kot = "\w+", Mishka = "\w+" \}', lua)
    assert m and all(f'{k} = ' in m.group(0) for k, _, _ in LADONS), 'Scripts/sv_config.lua CFG.specials.ladon.names != LADONS'
    cc = ladon_circuit()
    print(f'  ladons: circuit {LADON_CIRCUIT_KM:.1f} km round ({cc["centre"][0]:.2f}, {cc["centre"][1]:.2f}), arcs of '
          f'{len(cc["arc_a"])} points every {LADON_ARC_STEP_DEG:.0f} deg, each started a step ahead of the other\'s end')


def build_alicorn(g, flag, stock_ep):
    """The Alicorn (ALCN_*), on EB_002's records: appearance -> out along its lane, and back at each end (PathFinish);
    remote events for Lua: RE_SV_AlcnDive / Surface (LiveSubmarineOperation), the ALCN_ACTIONS (LiveAIActionEvent-
    Execution), RE_SV_AlcnVolley (each VLS fires at the player, LiveFireOneShotWeapon), RE_SV_AlcnRemove."""
    eb = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(stock_ep)))), 'OnlineMode', 'Maps', 'EmergencyCall',
                      'EB_002', 'EP_EB_002.uasset')
    t_path = g.foreign_template(eb, 'LiveAIPathExecution', 'MissionStart', lambda a, e: a[0] == 'Boss_0_ALCN_0')
    t_dive = g.foreign_template(eb, 'LiveSubmarineOperation', 'Debug_Dive')
    t_surface = g.foreign_template(eb, 'LiveSubmarineOperation', 'Debug_Surface')
    t_action = g.foreign_template(eb, 'LiveAIActionEventExecution', 'Debug_OpenCore')
    t_vls = g.foreign_template(eb, 'LiveFireOneShotWeapon', 'ElapsedTime_5s', lambda a, e: a[1] == 'Boss_0_ALCN_0_vls_L_1')
    t_eng = g.exec_template('LiveAIEngagementOrder', 'UnitDamage_Enemy_Ship_Last1', lambda a, e: a[0].startswith('AC_Obj_01_Ship1'))
    t_remove = g.exec_template('LiveDestroyUnitExecution', 'Debug_Destroy_Shuttle')
    assert arg_values(t_path)[4] == ALCN_SPEED and arg_values(t_dive)[1] == 'Diving' and arg_values(t_surface)[1] == 'Surface'
    finish = '01_A_Air1_f18e_PathFinish'
    (out, _), (back, _) = alcn_paths()
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', 'SV_AlcnUp', arg_changes={0: ALCN_UNIT})
    g.execute(t_path, 'SV_AlcnUp', {0: ALCN_OBJ, 2: out}, delay=1.0)
    g.execute(t_eng, 'SV_AlcnUp', {0: 'NoneSelect', 1: ALCN_UNIT}, delay=2.0)
    for ev, a, b in (('SV_AlcnOut', out, back), ('SV_AlcnBack', back, out)):
        g.trigger(finish, ev, arg_changes={0: ALCN_OBJ, 2: a})
        g.execute(t_path, ev, {0: ALCN_OBJ, 2: b})
    for ev, t in (('RE_SV_AlcnDive', t_dive), ('RE_SV_AlcnSurface', t_surface)):
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t, ev, {0: ALCN_OBJ})
    for ev, row in ALCN_ACTIONS.items():
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_action, ev, {0: ALCN_OBJ, 1: row})
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_AlcnVolley')
    for k, v in enumerate(ALCN_VLS):
        g.execute(t_vls, 'RE_SV_AlcnVolley', {1: f'{ALCN_OBJ}_{v}', 2: 'Player'}, delay=0.2 + 0.3 * k)
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_AlcnRemove')
    g.execute(t_remove, 'RE_SV_AlcnRemove', {0: 'NoneSelect', 1: ALCN_UNIT, 2: 'NoneSelect'})
    # its railgun's RAILGUN WARNING (behaviour roadmap P3/P7; Scripts/sv_alicorn.lua railAlert, with the railgun's tell):
    # Mission 18's LiveSetRailgunAlertEnable, as VALKA's (hard rule 45), under the Alicorn's own names so it doesn't
    # depend on hers (foreign_template imports the class once)
    m18 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission018', 'EP_Mission018_global.uasset')
    t_alert = g.foreign_template(m18, 'LiveSetRailgunAlertEnable', 'RemoteEvent_OverAltitude')     # {0 bool}
    assert arg_values(t_alert) == ['true'], arg_values(t_alert)
    for ev, on in (('RE_SV_AlcnAlertOn', 'true'), ('RE_SV_AlcnAlertOff', 'false')):
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_alert, ev, {0: on})


def build_anomaly(g, flag, stock_ep, t_search, t_engage, t_move):
    """The Anomaly (see ANOMALY_*): MINDRIPPER's appearance, its guards' orders, its death, and the field's effects
    Scripts/main.lua switches with RE_SV_AnomalyFieldOn / RE_SV_AnomalyFieldOff (RE_SV_AnomalyEnd: everything off)."""
    ANOMALY_OBJ = _se.ANOMALY_OBJ                # (build_survival.py sets it on survival_events, not on this part)
    assert ANOMALY_OBJ, 'build_survival.py build_wd_global sets ANOMALY_OBJ first'
    m15 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission015', 'EP_Mission015_global.uasset')
    t_msg = g.exec_template('LiveMessageExecution', 'RE_FinishMessage')                  # {0e MISSION_ACCOMPLISHED}
    t_cam_on = g.exec_template('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == SHUTTLE)
    t_cam_off = g.exec_template('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == 'NoneSelect')
    t_warn_on = g.foreign_template(m15, 'LiveSetForceWarinigMessageExecution', '01_Start_Enemy_Attack')
    t_warn_off = g.foreign_template(m15, 'LiveSetForceWarinigMessageExecution', 'Green_SpeedUp_0')
    t_noise = g.foreign_template(m15, 'LiveStartHUDRaderMapNoiseExecution', 'RadarNoise_01')       # 4 / 3 / 6
    t_noise_hard = g.foreign_template(m15, 'LiveStartHUDRaderMapNoiseExecution', 'RadarNoise_02')  # 5 / 5 / 8
    t_noise_off = g.foreign_template(m15, 'LiveStopHUDRaderMapNoiseExecution', 'NoiseCancel03')
    t_glass_on = g.foreign_template(m15, 'LiveActivateGlassesEffectExecution')
    t_glass_off = g.foreign_template(m15, 'LiveDeactivateGlassesEffectExecution')
    # no health bar (user, 2026-10-23: "don't have a healthbar, our original version didn't have one either"; Mission
    # 6's LiveUnitHealthDisplaySwitch drew a "None" list entry and a gauge in the sea at the unit's spawn point)
    t_sound = g.exec_template('LiveSoundGeneralPostEventExecution', 'RE_Shuttle_Launch', lambda a, e: a[0].endswith('LiftOff_Play'))
    t_mm = g.exec_template('LiveSetPlayerMaxAttackerMissiles', '01_Wave03_RemainingTime_0')     # [BOTH_MISSILE, n, false]
    t_cd = g.exec_template('LivePlayerAttackCooldownOverrideExecution', '01_Wave03_RemainingTime_0')   # 4 floats
    t_ma = g.exec_template('LiveChangePlayerMaxAttackersNumExecution', '01_Wave03_RemainingTime_0')    # [n]
    assert arg_values(t_mm)[0] == 'BOTH_MISSILE' and len(arg_values(t_cd)) == 4 and len(arg_values(t_ma)) == 1
    def attack(ev, a, delay=None):
        g.execute(t_mm, ev, {1: a['missiles']}, delay=delay)
        g.execute(t_ma, ev, {0: a['attackers']}, delay=delay)
        g.execute(t_cd, ev, {i: f'{v}' for i, v in enumerate(a['cooldown'])}, delay=delay)
    attack('MissionStart', ATTACK_BASE)
    # the presets Lua picks (PRESSURE): a remote event each, the same three records as above. The letters and Lua's
    # TIER.PRESSURE_PRESETS / CFG.late.pressure checked here so the two can't drift
    import re
    lua = runtime_lua()
    m_pp = re.search(r'TIER\.PRESSURE_PRESETS = "([A-Z]+)"', lua)
    assert m_pp and m_pp.group(1) == ''.join(sorted(PRESSURE)), 'sv_config.lua TIER.PRESSURE_PRESETS != PRESSURE'
    m_pr = re.search(r'pressure = \{ enabled = \w+, from_round = \{ [\d, ]+ \}, preset = \{ ([^}]*) \} \}', lua)
    assert m_pr and all(x.strip().strip('"') in PRESSURE for x in m_pr.group(1).split(',')), 'CFG.late.pressure presets not in PRESSURE'
    for letter, a in sorted(PRESSURE.items()):
        ev = f'RE_SV_Pressure{letter}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)                             # a remote event Lua fires (SV_Event)
        attack(ev, a)
    assert arg_values(t_warn_on) == ['true'] and arg_values(t_warn_off) == ['false'], (arg_values(t_warn_on), arg_values(t_warn_off))
    up, guards, down = 'SV_AnomalyUp', 'SV_AnomalyGuardsUp', 'SV_AnomalyDown'
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: ANOMALY_UNIT})
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', guards, arg_changes={0: ANOMALY_GUARD_UNIT})
    g.execute(t_search, up, {1: ANOMALY_UNIT}, delay=2.0)                    # MINDRIPPER: the pool's orders
    g.execute(t_engage, up, {1: ANOMALY_UNIT, 6: 'PlayerOnlyNoLimit'}, delay=2.0)
    # Its guards circle it (user, 2026-10-22: "they need to circle MINDRIPPER, currently they leave mindripper alone
    # after they sight the player"): Mission 26's escort pattern, their unit area on it (ANOMALY_GUARD_RADIUS_M,
    # following it: arg 10 true, as Start_WaveI_UAV_Setting keeps the UAVs on the x40a), and PlayerOnly instead of the
    # pool's PlayerOnlyNoLimit, so they attack the player near it and go back to it. Once it's down they hunt the player.
    assert arg_values(t_move)[1] == 'NoneSelect' and arg_values(t_move)[10] == 'false', arg_values(t_move)
    g.execute(t_search, guards, {1: ANOMALY_GUARD_UNIT}, delay=2.0)
    g.execute(t_engage, guards, {1: ANOMALY_GUARD_UNIT, 6: 'PlayerOnly'}, delay=2.0)
    g.execute(t_move, guards, {0: ANOMALY_GUARD_UNIT, 1: ANOMALY_OBJ, 3: 'NoneSelect', 5: f'{ANOMALY_GUARD_RADIUS_M}',
                               10: 'true'}, delay=2.5)
    # PHANTASM's pack (behaviour roadmap P7: "guards fly as a Wolf pack that springs while your controls are scrambled";
    # Scripts/sv_anomalies.lua ANOM.packTick, CFG.specials.anomaly.pack; docs/re/BEHAVIOUR_DIRECTOR.md unit 9), remote
    # events Lua fires, no conditions or flags (hard rule 26):
    #   RE_SV_AnomalyPackSpring  the guards loose (the down records' PlayerOnlyNoLimit and the area over the whole zone)
    #                            and every one of them the campaign aces' LastTGT onto the player (Mission 6's
    #                            EnemyBehind_LastTGT by unit, OneShot, Below_Return: hard rule 37)
    #   RE_SV_AnomalyPackHold    back round MINDRIPPER: their appearance's PlayerOnly and following area
    # Both kept on the co-op host (Scripts/sv_coop.lua KEEP_EVENTS ^RE_SV_AnomalyPack): sprung on the host's field, the
    # LastTGT steers to LocalPlayer
    assert '"^RE_SV_AnomalyPack"' in lua, 'Scripts/sv_coop.lua KEEP_EVENTS has no ^RE_SV_AnomalyPack'
    for ev in ('RE_SV_AnomalyPackSpring', 'RE_SV_AnomalyPackHold'):
        assert f'"{ev}"' in lua, f'Scripts/sv_anomalies.lua never fires {ev}'
    m06 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'MIssion006', 'EP_Mission006_global.uasset')
    t_req = g.foreign_template(m06, 'LiveAIRequestUniqueAction', 'EnemyBehind_LastTGT')
    assert arg_values(t_req)[3] == 'LastTGT', arg_values(t_req)
    spring, hold = 'RE_SV_AnomalyPackSpring', 'RE_SV_AnomalyPackHold'
    g.trigger('RE_SpawnEnemy_kokatu_1st', spring)
    g.execute(t_engage, spring, {1: ANOMALY_GUARD_UNIT, 6: 'PlayerOnlyNoLimit'})
    g.execute(t_move, spring, {0: ANOMALY_GUARD_UNIT, 5: f'{AREA_RADIUS_M}'})
    g.execute(t_req, spring, {0: 'NoneSelect', 1: ANOMALY_GUARD_UNIT, 2: '', 3: 'LastTGT', 4: 'OneShot', 5: 'Below_Return',
                              6: 'NoneSelect', 7: 'false'})
    g.trigger('RE_SpawnEnemy_kokatu_1st', hold)
    g.execute(t_engage, hold, {1: ANOMALY_GUARD_UNIT, 6: 'PlayerOnly'})
    g.execute(t_move, hold, {0: ANOMALY_GUARD_UNIT, 1: ANOMALY_OBJ, 3: 'NoneSelect', 5: f'{ANOMALY_GUARD_RADIUS_M}', 10: 'true'})
    flag(up, 'SV_AnomalyUp', 'Set', 1)
    attack(up, ANOMALY_ATTACK)
    g.execute(t_msg, up, {0: 'MISSION_UPDATE'})                               # the stock banner and its beep
    g.execute(t_warn_on, up, delay=1.0)                                       # WARNING until it's down
    g.execute(t_noise, up, delay=1.0)
    assert arg_values(t_cam_on)[4] == 'LookAt_Event_Camera_ms22-01', arg_values(t_cam_on)
    for k, cam in enumerate(ANOMALY_CAMERAS):
        ev = f'RE_SV_AnomalyCam_{chr(65 + k)}'                                  # letters: hard rule 17
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_cam_on, ev, {0: ANOMALY_OBJ, 4: cam})
        g.execute(t_cam_off, ev, delay=ANOMALY_CAMERA_S)
    g.execute(t_sound, up, {0: ANOMALY_HUM + 'Play', 1: ANOMALY_OBJ}, delay=1.0)   # crackles from the portal on
    for name in ('RE_SV_AnomalyFieldOn', 'RE_SV_AnomalyFieldOff', 'RE_SV_AnomalyEnd'):
        g.trigger('RE_SpawnEnemy_kokatu_1st', name)                           # remote events Lua fires (SV_Event)
    g.execute(t_glass_on, 'RE_SV_AnomalyFieldOn')
    g.execute(t_noise_hard, 'RE_SV_AnomalyFieldOn')
    g.execute(t_glass_off, 'RE_SV_AnomalyFieldOff')
    g.execute(t_noise, 'RE_SV_AnomalyFieldOff')
    g.trigger('UnitDamage_Ship_Destroy_0', down, arg_changes={0: ANOMALY_UNIT})
    g.execute(t_sound, down, {0: ANOMALY_HUM + 'Stop', 1: ANOMALY_OBJ})
    for delay, key in ANOMALY_DOWN_SOUNDS:
        g.execute(t_sound, down, {0: key, 1: ANOMALY_OBJ}, delay=delay)
    for ev in (down, 'RE_SV_AnomalyEnd'):
        attack(ev, ATTACK_BASE)
        g.execute(t_engage, ev, {1: ANOMALY_GUARD_UNIT, 6: 'PlayerOnlyNoLimit'})     # the guards, loose
        g.execute(t_move, ev, {0: ANOMALY_GUARD_UNIT, 5: f'{AREA_RADIUS_M}'})        # (Mission 22's mark, the whole zone)
        flag(ev, 'SV_AnomalyUp', 'Set', 0)
        g.execute(t_warn_off, ev)
        g.execute(t_noise_off, ev)
        g.execute(t_glass_off, ev)


def build_glitch(g, t_search, t_engage, stock_ep):
    """AB.L..IN (see GLITCH_*): the pool's orders when it appears (search, then engage the player anywhere), the
    stock MISSION UPDATE banner and beep, and its blinks (GLITCH_BLINK_*). Everything else is Scripts/main.lua's
    (ANOM.glitchTick)."""
    import math
    GLITCH_OBJ = _se.GLITCH_OBJ                  # (build_survival.py sets it on survival_events, not on this part)
    assert GLITCH_OBJ, 'build_survival.py build_wd_global sets GLITCH_OBJ first'
    t_msg = g.exec_template('LiveMessageExecution', 'RE_FinishMessage')                  # {0e MISSION_ACCOMPLISHED}
    # Mission 22's: A_Obj_01_dummyN0 onto the player, 6.5 km north ({1: obj, 2: Player, 4-6: offset cm, 9-11: rotation
    # (roll, pitch, yaw), 13: Absolute})
    t_tp = g.exec_template('LiveActorTeleportExecution', '01_Wave05_YesEvent02', lambda a, e: a[1] == 'A_Obj_01_dummyN0')
    v = arg_values(t_tp)
    assert v[2] == 'Player' and v[13] == 'Absolute' and v[8] == 'NoneSelect', v
    # main.lua builds the same names from CFG.specials.glitch (blinks, gun_every_s): checked here so the two can't drift
    # (code review of 2026-10-23)
    import re
    lua = runtime_lua()
    m_bl = re.search(r'blinks = \{ step_deg = (\d+), rings_m = \{ ([\d, ]+) \} \}', lua)
    m_gun = re.search(r'[^a-z_]gun_every_s = ([\d.]+)', lua)          # (not railgun_every_s)
    assert m_bl and int(m_bl.group(1)) == GLITCH_BLINK_STEP_DEG and         tuple(int(x) for x in m_bl.group(2).split(',')) == GLITCH_BLINK_RINGS_M, 'main.lua CFG.specials.glitch.blinks != GLITCH_BLINK_*'
    assert m_gun and abs(float(m_gun.group(1)) - GLITCH_GUN_SHOTS * GLITCH_GUN_EVERY_S) < 1e-6, 'main.lua gun_every_s != GLITCH_GUN_*'
    for ev, deg, m in glitch_blinks():
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)                                  # a remote event Lua fires
        dx, dy = m * 100 * math.cos(math.radians(deg)), m * 100 * math.sin(math.radians(deg))
        yaw = (deg + 180 + 180) % 360 - 180                                     # facing back at the player
        g.execute(t_tp, ev, {1: GLITCH_OBJ, 4: f'{dx:.1f}', 5: f'{dy:.1f}', 6: '0.0', 9: '0.0', 10: '0.0', 11: f'{yaw:.1f}'})
    m19 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission019', 'EP_Mission019_global.uasset')
    t_fire = g.foreign_template(m19, 'LiveFireOneShotWeapon', '05_PhaseStart_4', lambda a, e: a[1] == 'E_Obj_00_Air0_rflm_0')
    assert arg_values(t_fire)[0] == 'WN_WEAPON_3' and arg_values(t_fire)[2] == 'Player', arg_values(t_fire)
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_GlitchGun')
    g.execute(t_fire, 'RE_SV_GlitchGun', {0: GLITCH_GUN_SLOT, 1: GLITCH_OBJ}, delay=GLITCH_GUN_EVERY_S, loop=GLITCH_GUN_SHOTS)
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_GlitchEcm')
    g.execute(t_fire, 'RE_SV_GlitchEcm', {0: GLITCH_ECM_SLOT, 1: GLITCH_OBJ})
    # its post-stalls on command (user, 2026-10-24: "make the EA-18G do post stalls even more"): the campaign's own
    # unique actions (docs/re/UNIQUE_ACTIONS.md 9), OneShot (they end by themselves), Below_Return (above evading and
    # pursuit), as build_ace_moves; Scripts/main.lua ANOM.glitchTick picks one (CFG.specials.glitch.post_stall_*)
    m06 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'MIssion006', 'EP_Mission006_global.uasset')
    t_req = g.foreign_template(m06, 'LiveAIRequestUniqueAction', 'EnemyBehind_LastTGT')
    assert arg_values(t_req)[3] == 'LastTGT', arg_values(t_req)
    assert '"RE_SV_GlitchTurn"' in lua, 'Scripts/sv_anomalies.lua never fires RE_SV_GlitchTurn (its phase 3)'
    m_ps = re.search(r'post_stall_moves = \{ ([^}]*) \},', lua)
    assert m_ps and 'Turn' not in re.findall(r'"(\w+)"', m_ps.group(1)), 'CFG.specials.glitch.post_stall_moves: never "Turn"'
    for name, action in GLITCH_POST_STALL:
        ev = f'RE_SV_Glitch{name}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_req, ev, {0: 'NoneSelect', 1: GLITCH_UNIT, 2: '', 3: action, 4: 'OneShot', 5: 'Below_Return',
                              6: 'NoneSelect', 7: 'false'})
    # its death: MINDRIPPER's (user, 2026-10-23: "add the same death scream MINDRIPPER has on its kill"), the Celaeno's
    # body explosion and core collapse (ANOMALY_DOWN_SOUNDS) on its wreck
    t_sound = g.exec_template('LiveSoundGeneralPostEventExecution', 'RE_Shuttle_Launch', lambda a, e: a[0].endswith('LiftOff_Play'))
    down = 'SV_GlitchDown'
    g.trigger('UnitDamage_Ship_Destroy_0', down, arg_changes={0: GLITCH_UNIT})
    for delay, key in ANOMALY_DOWN_SOUNDS:
        g.execute(t_sound, down, {0: key, 1: GLITCH_OBJ}, delay=delay)
    up = 'SV_GlitchUp'
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: GLITCH_UNIT})
    g.execute(t_search, up, {1: GLITCH_UNIT}, delay=2.0)
    g.execute(t_engage, up, {1: GLITCH_UNIT, 6: 'PlayerOnlyNoLimit'}, delay=2.0)
    g.execute(t_msg, up, {0: 'MISSION_UPDATE'})


def build_valka(g, flag, t_search, t_engage, stock_ep):
    """VALKA (see VALKA_*): the orders when she spawns (the player only, anywhere; her spare railguns and laser pod
    held back), her teleport spots, the railgun shot, the opener's warning / charge, her reveal (MISSION UPDATE, the
    focus camera, the Anomaly's attack pressure), LastTGT and the post-stalls. The rest is Scripts/main.lua's (VALK.*)."""
    import math, re
    VALKA_OBJ = _se.VALKA_OBJ                    # (build_survival.py sets it on survival_events, not on this part)
    assert VALKA_OBJ and VALKA_RAILGUN in VALKA_PARTS, 'build_survival.py valka_unit sets VALKA_OBJ / VALKA_PARTS first'
    lua = runtime_lua()
    m = re.search(r'spots = \{ ((?:\{ [^}]* \},? )+)\}', lua)
    lua_spots = re.findall(r'\{ "(\w)", (\d+), (\d+) \}', m.group(1)) if m else []
    assert [(r, int(a), int(b)) for r, a, b in lua_spots] == list(VALKA_SPOTS), 'main.lua CFG.specials.valka.spots != VALKA_SPOTS'
    dirn = os.path.dirname(os.path.dirname(stock_ep))
    m15 = os.path.join(dirn, 'Mission015', 'EP_Mission015_global.uasset')
    m19 = os.path.join(dirn, 'Mission019', 'EP_Mission019_global.uasset')
    m26 = os.path.join(dirn, 'Mission026', 'EP_Mission026_global.uasset')
    m06 = os.path.join(dirn, 'MIssion006', 'EP_Mission006_global.uasset')
    m18 = os.path.join(dirn, 'Mission018', 'EP_Mission018_global.uasset')
    t_msg = g.exec_template('LiveMessageExecution', 'RE_FinishMessage')
    t_tp = g.exec_template('LiveActorTeleportExecution', '01_Wave05_YesEvent02', lambda a, e: a[1] == 'A_Obj_01_dummyN0')
    t_fire = g.foreign_template(m19, 'LiveFireOneShotWeapon', '05_PhaseStart_4', lambda a, e: a[1] == 'E_Obj_00_Air0_rflm_0')
    t_hold = g.foreign_template(m26, 'LiveAIEngagementOrder', 'x40a_fire_AB_Ship0_3')        # {0 part, 3 EvadeOnly}
    t_alert = g.foreign_template(m18, 'LiveSetRailgunAlertEnable', 'RemoteEvent_OverAltitude')     # {0 bool}
    assert arg_values(t_alert) == ['true'], arg_values(t_alert)
    m_miss = re.search(r'opener_miss_up_m = (\d+)', lua)
    assert m_miss and int(m_miss.group(1)) == VALKA_MISS_UP_M, "main.lua opener_miss_up_m != VALKA_MISS_UP_M"
    t_req = g.foreign_template(m06, 'LiveAIRequestUniqueAction', 'EnemyBehind_LastTGT')
    t_warn_on = g.foreign_template(m15, 'LiveSetForceWarinigMessageExecution', '01_Start_Enemy_Attack')
    t_warn_off = g.foreign_template(m15, 'LiveSetForceWarinigMessageExecution', 'Green_SpeedUp_0')
    t_noise = g.foreign_template(m15, 'LiveStartHUDRaderMapNoiseExecution', 'RadarNoise_02')
    t_noise_off = g.foreign_template(m15, 'LiveStopHUDRaderMapNoiseExecution', 'NoiseCancel03')
    t_sound = g.exec_template('LiveSoundGeneralPostEventExecution', 'RE_Shuttle_Launch', lambda a, e: a[0].endswith('LiftOff_Play'))
    t_cam_on = g.exec_template('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == SHUTTLE)
    t_cam_off = g.exec_template('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == 'NoneSelect')
    t_remove = g.exec_template('LiveDestroyUnitExecution', 'Debug_Destroy_Shuttle')
    t_mm = g.exec_template('LiveSetPlayerMaxAttackerMissiles', '01_Wave03_RemainingTime_0')
    t_cd = g.exec_template('LivePlayerAttackCooldownOverrideExecution', '01_Wave03_RemainingTime_0')
    t_ma = g.exec_template('LiveChangePlayerMaxAttackersNumExecution', '01_Wave03_RemainingTime_0')
    v = arg_values(t_tp)
    assert v[2] == 'Player' and v[13] == 'Absolute', v
    assert arg_values(t_fire)[0] == 'WN_WEAPON_3' and arg_values(t_fire)[2] == 'Player', arg_values(t_fire)
    assert arg_values(t_hold)[3] == 'EvadeOnly' and arg_values(t_hold)[0].endswith('_RailGunCK'), arg_values(t_hold)
    assert arg_values(t_req)[3] == 'LastTGT', arg_values(t_req)
    assert arg_values(t_warn_on) == ['true'] and arg_values(t_warn_off) == ['false']
    def attack(ev, a):
        g.execute(t_mm, ev, {1: a['missiles']})
        g.execute(t_ma, ev, {0: a['attackers']})
        g.execute(t_cd, ev, {i: f'{x}' for i, x in enumerate(a['cooldown'])})
    remote = lambda ev: g.trigger('RE_SpawnEnemy_kokatu_1st', ev)          # remote events Lua fires (SV_Event)
    up = 'SV_ValkaUp'
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: VALKA_UNIT})
    g.execute(t_search, up, {1: VALKA_UNIT}, delay=2.0)
    g.execute(t_engage, up, {1: VALKA_UNIT, 6: 'PlayerOnlyNoLimit'}, delay=2.0)
    for comp in VALKA_IDLE_PARTS:
        g.execute(t_hold, up, {0: VALKA_PARTS[comp]}, delay=3.0)
    # all four parts, her own RailGun too, held again whenever main.lua asks (every hold_s while she hunts): held parts
    # still fire on command (the opener's held dummy did); test of 2026-10-24: the unheld RailGun (or a hold that
    # lapsed) hit the airfield 38 times in 13 s
    remote('RE_SV_ValkaHold')
    for comp in (VALKA_RAILGUN,) + VALKA_IDLE_PARTS:
        g.execute(t_hold, 'RE_SV_ValkaHold', {0: VALKA_PARTS[comp]})
    # her search and attack orders (the player only, anywhere) again whenever main.lua asks (every engage_every_s while
    # she hunts; user, 2026-10-24: "adjust her behaviours so that she tries to follow you more often")
    remote('RE_SV_ValkaEngage')
    g.execute(t_search, 'RE_SV_ValkaEngage', {1: VALKA_UNIT})
    g.execute(t_engage, 'RE_SV_ValkaEngage', {1: VALKA_UNIT, 6: 'PlayerOnlyNoLimit'})
    flag(up, 'SV_ValkaUp', 'Set', 1)
    # the opener's dummy railgun: held (EvadeOnly: it never attacks by itself; twice, in case the first is early),
    # one shot at the player on command (as Mission 26 fires its held CK railgun), its charge heard at the player (it's
    # 9 km out), removed by main.lua after the shot
    eml_up = 'SV_ValkaEmlUp'
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', eml_up, arg_changes={0: VALKA_EML_UNIT})
    for d in (0.5, 2.0):
        g.execute(t_hold, eml_up, {0: VALKA_EML_OBJ}, delay=d)
    # the opener's shot misses (user, 2026-10-24: "that first shot HAS to miss me"): aimed at Mission 22's dummy, put
    # VALKA_MISS_UP_M straight above the player first (a world offset: whichever way you fly); main.lua also makes its
    # rounds harmless
    remote('RE_SV_ValkaEmlShot')
    g.execute(t_tp, 'RE_SV_ValkaEmlShot', {1: VALKA_DUMMY, 4: '0.0', 5: '0.0', 6: f'{VALKA_MISS_UP_M * 100:.1f}',
                                           9: '0.0', 10: '0.0', 11: '0.0'})
    g.execute(t_fire, 'RE_SV_ValkaEmlShot', {0: 'WN_WEAPON_1', 1: VALKA_EML_OBJ, 2: VALKA_DUMMY}, delay=0.1)
    # the railgun alert (Mission 18's) while she's up: on with the opener's charge and every charge of hers
    remote('RE_SV_ValkaAlertOn')
    g.execute(t_alert, 'RE_SV_ValkaAlertOn', {0: 'true'})
    remote('RE_SV_ValkaAlertOff')                          # (main.lua: a few s after each shot, and when she's down)
    g.execute(t_alert, 'RE_SV_ValkaAlertOff', {0: 'false'})
    remote('RE_SV_ValkaEmlChargeOn')
    g.execute(t_noise, 'RE_SV_ValkaEmlChargeOn')
    g.execute(t_sound, 'RE_SV_ValkaEmlChargeOn', {0: VALKA_CHARGE_SOUND + 'Play', 1: 'Player'})
    remote('RE_SV_ValkaEmlChargeOff')
    g.execute(t_noise_off, 'RE_SV_ValkaEmlChargeOff')
    g.execute(t_sound, 'RE_SV_ValkaEmlChargeOff', {0: VALKA_CHARGE_SOUND + 'Stop', 1: 'Player'})
    remote('RE_SV_ValkaEmlRemove')
    g.execute(t_remove, 'RE_SV_ValkaEmlRemove', {0: 'NoneSelect', 1: VALKA_EML_UNIT, 2: 'NoneSelect'})
    for ev, deg, metres in valka_spots():                  # her spots round the player, at their height, nose on them
        remote(ev)
        dx, dy = metres * 100 * math.cos(math.radians(deg)), metres * 100 * math.sin(math.radians(deg))
        yaw = (deg + 180 + 180) % 360 - 180
        g.execute(t_tp, ev, {1: VALKA_OBJ, 4: f'{dx:.1f}', 5: f'{dy:.1f}', 6: '0.0', 9: '0.0', 10: '0.0', 11: f'{yaw:.1f}'})
    remote('RE_SV_ValkaRailgun')                           # one shot (main.lua makes the part a single-shot one)
    g.execute(t_fire, 'RE_SV_ValkaRailgun', {0: 'WN_WEAPON_1', 1: VALKA_PARTS[VALKA_RAILGUN]})
    # her attack (user, 2026-10-24: she hides in a normal round and attacks once its fighters are down; "have the WARNING
    # play for the round just like we do for the other two anomaly rounds"): the forced WARNING from her attack until
    # she's down (SV_ValkaDown / RE_SV_ValkaEnd)
    remote('RE_SV_ValkaWarnOn')
    g.execute(t_warn_on, 'RE_SV_ValkaWarnOn')
    remote('RE_SV_ValkaChargeOn')                          # a railgun charging at you: radar noise, the hum
    g.execute(t_noise, 'RE_SV_ValkaChargeOn')
    g.execute(t_sound, 'RE_SV_ValkaChargeOn', {0: VALKA_CHARGE_SOUND + 'Play', 1: VALKA_OBJ})
    remote('RE_SV_ValkaChargeOff')
    g.execute(t_noise_off, 'RE_SV_ValkaChargeOff')
    g.execute(t_sound, 'RE_SV_ValkaChargeOff', {0: VALKA_CHARGE_SOUND + 'Stop', 1: VALKA_OBJ})
    remote('RE_SV_ValkaReveal')                            # after the first shot: the banner, the pressure
    g.execute(t_msg, 'RE_SV_ValkaReveal', {0: 'MISSION_UPDATE'})
    attack('RE_SV_ValkaReveal', ANOMALY_ATTACK)
    for k, cam in enumerate(ANOMALY_CAMERAS):              # the focus camera on her (main.lua picks one: `camera`)
        ev = f'RE_SV_ValkaCam_{chr(65 + k)}'
        remote(ev)
        g.execute(t_cam_on, ev, {0: VALKA_OBJ, 4: cam})
        g.execute(t_cam_off, ev, delay=ANOMALY_CAMERA_S)
    for name, action in VALKA_POST_STALL:                  # LastTGT and the post-stalls, as build_glitch's
        ev = f'RE_SV_Valka{name}'
        remote(ev)
        g.execute(t_req, ev, {0: 'NoneSelect', 1: VALKA_UNIT, 2: '', 3: action, 4: 'OneShot', 5: 'Below_Return',
                              6: 'NoneSelect', 7: 'false'})
    down = 'SV_ValkaDown'
    g.trigger('UnitDamage_Ship_Destroy_0', down, arg_changes={0: VALKA_UNIT})
    for ev in (down, 'RE_SV_ValkaEnd'):
        if ev != down: remote(ev)
        attack(ev, ATTACK_BASE)
        flag(ev, 'SV_ValkaUp', 'Set', 0)
        g.execute(t_warn_off, ev)
        g.execute(t_noise_off, ev)
        g.execute(t_sound, ev, {0: VALKA_CHARGE_SOUND + 'Stop', 1: VALKA_OBJ})


def build_shuttle(g, flag):
    """Comona Defense (see SHUTTLE_*): Mission 22's shuttle records, copied with their exact arguments, on main.lua's
    countdown events (RE_SV_ShuttleT_<second>) instead of Mission 22's mission timer."""
    T = SHUTTLE_COUNTDOWN_S
    made = set()

    def at(sec):
        """The event for second `sec` of the countdown (main.lua fires RE_SV_ShuttleT_1, _2, ... as its clock runs)."""
        assert float(sec).is_integer() and 1 <= sec <= T + 30, sec
        name = f'RE_SV_ShuttleT_{int(sec)}'
        if name not in made:
            made.add(name)
            g.trigger('RE_SpawnEnemy_kokatu_1st', name)
        return name
    tpl = lambda cls, ev, pred=None: g.exec_template(cls, ev, pred)
    t_maxhp = tpl('LiveSetMaxHealthExecution', 'MissionStart')
    t_minhp = tpl('LiveSetMinHealthExecution', 'RE_SetGroundObjMinHP1')
    t_sound = tpl('LiveSoundGeneralPostEventExecution', 'RE_Shuttle_Launch', lambda a, e: a[0].endswith('LiftOff_Play'))
    t_sflag = tpl('LiveSoundGeneralPostEventExecution', 'CompositeEvent_CountDown_1')
    t_radio = tpl('LiveRadioPlayExecution', 'CompositeEvent_CountDown_1')
    t_vfx_on = tpl('LiveSetActiveVFXExecution', 'RE_Shuttle_Boost_On')
    t_vfx_off = tpl('LiveSetActiveVFXExecution', 'RE_Shuttle_Boost_Off')
    t_fire = tpl('LiveAIPathExecution', 'RE_Shuttle_Fire_On')
    t_climb = tpl('LiveAIPathExecution', 'RE_Shuttle_Launch', lambda a, e: a[4] == '4000.0')
    t_climb2 = tpl('LiveAIPathExecution', 'RE_Shuttle_Launch', lambda a, e: a[4] == '5000.0')
    t_cam_on = tpl('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == SHUTTLE)
    t_cam_off = tpl('LiveEventFocusCameraExecution', 'RE_ShuttleFocusCamera', lambda a, e: a[0] == 'NoneSelect')
    t_remove = tpl('LiveDestroyUnitExecution', 'Debug_Destroy_Shuttle')
    for t in (t_fire, t_climb, t_climb2):
        assert arg_values(t)[0] == SHUTTLE and arg_values(t)[2] == SHUTTLE_PATH
    assert arg_values(t_remove)[2] == SHUTTLE and arg_values(t_maxhp)[0] == SHUTTLE
    standing = lambda: [g.cond('SV_ShuttleLost', 'Leq', 0)]          # nothing more once it's been shot down
    up = 'SV_ShuttleUp'
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: SHUTTLE_UNIT})
    resets = ['SV_ShuttleLost', 'SV_ShuttleLaunched', 'SV_ShuttleHits', 'SV_ShuttleNearSaid'] + [f'SV_ShuttleDmg{c}' for c in 'ABC']
    for name in resets:
        flag(up, name, 'Set', 0)
    flag(up, 'SV_ShuttleRound', 'Set', 1)
    g.execute(t_maxhp, up, {3: f'{SHUTTLE_HP}'})
    g.execute(t_sound, up, {0: SHUTTLE_SOUND + 'Ignition_Stop', 1: SHUTTLE})
    for before, key in SHUTTLE_RADIO:
        g.execute(t_radio, at(T - before), {0: key}, conds=standing())
    for before, key in SHUTTLE_SOUND_FLAGS:
        g.execute(t_sflag, at(T - before), {0: key}, conds=standing())
    g.execute(t_minhp, at(T - 20), {0: SHUTTLE, 3: '1.0'}, conds=standing())   # the last 20 s it can't die
    g.execute(t_vfx_on, at(T - 14), conds=standing())                         # ignition (RE_Shuttle_Boost_On)
    g.execute(t_sound, at(T - 14), {0: SHUTTLE_SOUND + 'Ignition_Play', 1: SHUTTLE}, conds=standing())
    g.execute(t_fire, at(T - 4), conds=standing())                            # on its path, engines lit
    g.execute(t_cam_on, at(T - 2), conds=standing())
    # liftoff (RE_Shuttle_Launch, without Mission 22's wave cleanup)
    g.execute(t_climb, at(T), conds=standing())
    g.execute(t_sound, at(T), {0: SHUTTLE_SOUND + 'Ignition_Stop', 1: SHUTTLE}, conds=standing())
    g.execute(t_sound, at(T), {0: SHUTTLE_SOUND + 'LiftOff_Play', 1: SHUTTLE}, conds=standing())
    flag(at(T), 'SV_ShuttleLaunched', 'Set', 1, conds=standing())
    flag(at(T), 'SV_ShuttleRound', 'Set', 0, conds=standing())
    g.execute(t_climb2, at(T + 13), conds=standing())
    g.execute(t_cam_off, at(T + 7))
    g.execute(t_vfx_off, at(T + 30))
    # Taking it and the pad's allies off after liftoff: Scripts/main.lua fires RE_SV_ShuttleRemove SHUTTLE_REMOVE_S after
    # it (test of 2026-10-22: records here on a delay gated on SV_ShuttleLaunched never ran, both units stayed up to
    # round 9: a delayed record's conditions are checked when its event fires, at the shuttle's appearance).
    # LiveDestroyUnitExecution kills through TakeDamage(FLT_MAX), which is clamped at the object's MinHealth: the 1.0
    # set before liftoff has to go back to 0 first (as M019/M021/M026 do), or the shuttle stays up with 1 HP.
    # (user, 2026-10-23: "the space shuttle and centre hasnt despawned", RE_SV_ShuttleRemove fired: destroying them
    # through damage never took them off) Both units are switched off with Mission 22's own despawn,
    # LiveSetActiveGameObjectExecution ({0 object, 1 unit, 2 tag, 3 active}: false), as it does its stray dummies; the
    # next shuttle round spawns them fresh. The pad's allies (guns, SAMs, tower) go with it: the whole unit.
    t_off = g.exec_template('LiveSetActiveGameObjectExecution', None, lambda a, e: a[0] != 'NoneSelect' and a[3] == 'false')
    assert arg_values(t_off)[1] == 'NoneSelect' and arg_values(t_off)[2] == 'NoneSelect', arg_values(t_off)
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_ShuttleRemove')
    for unit in (SHUTTLE_UNIT, PAD_UNIT):
        g.execute(t_off, 'RE_SV_ShuttleRemove', {0: 'NoneSelect', 1: unit, 2: 'NoneSelect', 3: 'false'})
    # the flags back to 0 once it's taken off (they're set to 0 at its next appearance too). ((2026-11-11) SV_ShuttleRound
    # too, kept out of `resets`, which SV_ShuttleUp sets to 0 before its own Set 1: until then only the liftoff at T or a
    # kill on the pad set it back, and Saint Alessia's co-op host, whose liftoff her STORE ate, sent every raid after it
    # at the shuttle, SV_BomberUp_NN's shuttle branch. Scripts/sv_rounds.lua SPC.shuttleRemoveCheck reads SV_ShuttleRound
    # and SV_ShuttleLaunched still up after this event as its being lost, and fires it again)
    cleared = resets + ['SV_ShuttleRound']
    assert {'SV_ShuttleRound', 'SV_ShuttleLaunched'} <= set(cleared), cleared
    for name in cleared:
        flag('RE_SV_ShuttleRemove', name, 'Set', 0)
    # hits: Mission 22's ObjectDamage_Shuttle; its low-health radio (61 / 31 / 16 %) keeps the stock health conditions.
    # Mission 22 also gates each stage on a bool flag of its own (Bool_Shuttle_Damage_Phase0N), which Survival's flag
    # asset doesn't have: that check is replaced by an int flag of Survival's, set when the line plays and reset when the
    # shuttle appears, so the callouts come again every special (a life-1 trigger would fire once a level).
    hit = 'SV_ShuttleHit'
    g.trigger('ObjectDamage_Shuttle', hit)
    g.execute(t_radio, hit, {0: '01_All_Wave_Hit_Shuttle_First'}, conds=[g.cond('SV_ShuttleHits', 'Leq', 0)])
    flag(hit, 'SV_ShuttleHits', 'Add', 1)
    for c, stage, line in (('A', 1, 'Durability50'), ('B', 2, 'Durability30'), ('C', 3, 'Durability_Limit')):
        t = tpl('LiveCallRemoteEventExecution', 'ObjectDamage_Shuttle', lambda a, e, n=stage: a[0] == f'RE_Shuttle_Damage_Phase{n}')
        stock = fields(t)['ConditionalStatementTables'][3][1]
        cls = [ep_dump.show(fields(x)['StatementClass'][3], g.z) for x in stock]
        health = [x for x, c in zip(stock, cls) if c == 'LiveIsLowHealthStatement']     # its band, e.g. < 61 and >= 31 %
        assert health and set(cls) == {'LiveIsLowHealthStatement', 'LiveCheck_FlagBoolStatement'}, (stage, cls)
        said = f'SV_ShuttleDmg{c}'
        ev = f'RE_SV_ShuttleDamage{c}'                               # no numeric tail (hard rule 17)
        g.execute(t, hit, {0: ev}, conds=health + [g.cond(said, 'Leq', 0)])
        g.trigger('RE_Shuttle_Damage_Phase1', ev)
        g.execute(t_radio, ev, {0: f'01_All_Wave_{line}_Shuttle'})
        flag(ev, said, 'Set', 1)
    near = 'SV_ShuttleNear'
    g.trigger('VolumeEvent_Shuttle_Near_1st', near)
    g.execute(t_radio, near, {0: '01_All_Wave_Close_Shuttle_First'},
              conds=standing() + [g.cond('SV_ShuttleNearSaid', 'Leq', 0), g.cond('SV_ShuttleRound', 'Geq', 1)])
    flag(near, 'SV_ShuttleNearSaid', 'Set', 1, conds=[g.cond('SV_ShuttleRound', 'Geq', 1)])
    # shot down on the pad (Mission 22's ObjectDestroy / ObjectDestroy_1, any attacker or a system kill)
    on_pad = lambda: [g.cond('SV_ShuttleLaunched', 'Leq', 0)]
    for src, ev in (('ObjectDestroy', 'SV_ShuttleDown'), ('ObjectDestroy_1', 'SV_ShuttleDownSys')):
        assert arg_values(g.trig_template(src))[16] == SHUTTLE
        g.trigger(src, ev)
        flag(ev, 'SV_ShuttleLost', 'Set', 1, conds=on_pad())
        flag(ev, 'SV_ShuttleRound', 'Set', 0, conds=on_pad())
    g.execute(t_radio, 'SV_ShuttleDown', {0: '01_Mission_Failure_Destroy_Shuttle'},
              conds=[g.cond('SV_ShuttleLaunched', 'Leq', 0)])
    g.execute(t_sflag, 'SV_ShuttleDown', {0: 'AKE_FLAG_Ms22_ARMS_SKY_OP0057_sstb_Countdown_Interrupted_Set'},
              conds=[g.cond('SV_ShuttleLaunched', 'Leq', 0)])
    for k in range(3):
        g.execute(t_vfx_on, 'SV_ShuttleDown', {0: f'VFX_ShuttleDummy{k}'}, conds=[g.cond('SV_ShuttleLaunched', 'Leq', 0)])
    g.execute(t_remove, 'SV_ShuttleDown', {0: 'NoneSelect', 1: PAD_UNIT, 2: 'NoneSelect'}, delay=PAD_REMOVE_LOST_S,
              conds=[g.cond('SV_ShuttleLaunched', 'Leq', 0)])
