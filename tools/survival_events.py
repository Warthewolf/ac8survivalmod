"""survival_events.py : Survival Mode's event graph (EP_SurvivalMode_global), built from Mission 22's own records.

Every trigger / exec here is a deep copy of a stock Mission 22 record of the same node class, with only its names,
unit/flag arguments, delays and conditions changed, so the node classes, argument layouts and TipsHashes are the
game's own. EP_SurvivalMode_global is a copy of EP_Mission022_global, so its import and name tables already hold every
node class and most names these records use. Record format: tools/re/EVENT_NOTES.md.

Rounds are run by Survival's own spawner (Scripts/main.lua + the native runtime, tools/re/SPAWN_SYSTEM.md), not
by events: the game never spawns a desc again while its shot-down flight is still on the phase's unit list. The events:
  MissionStart        the mission clock paused and hidden (Mission 22's own pair): Survival is endless (no music: the
                      pause menu's Music Player is the only music)
  SV_FlightUp_NN      (one per pool flight, "reinforcement appeared", fires for any spawn of it) SV_Alive += 1,
                      SV_Up_NN = 1; 2 s later: air-only enemy search + engage the player only (PlayerOnlyNoLimit)
  RE_SV_FlightOrders_NN  the same, fired by Scripts/main.lua for a flight whose appearance didn't fire (landing menu)
  SV_FlightDown_NN    (one per pool flight, destroyed) SV_Alive -= 1, SV_Kills += 1 (for the Lua log), SV_Up_NN = 0
  SV_BomberUp_NN      (one per bomber flight, BOMBERS) Mission 22's Comona Airport strike: unit area onto the airport,
                      ground-only search, engagement order on the airfield unit (AIRFIELD_UNIT); on the shuttle while
                      SV_ShuttleRound is 1
  SV_AirfieldHit_N    (one per airfield dummy) a weapon an enemy fired at it ended there: SV_AirHits += 1 and
                      Mission 22's explosion VFX on that dummy; Scripts/main.lua turns SV_AirHits into airfield health
  RE_SV_AirfieldClose / RE_SV_AirfieldOpen   landing off / on (fired by Scripts/main.lua with SV_Event)
  RE_SV_BombRun_NN    (one per bomber flight) both aircraft drop BOMB_COUNT bombs (weapon slot 4); Scripts/main.lua
                      fires it when a Tu-95 / Tu-160 of that flight is over the airfield
  SV_Shuttle*         Comona Defense (build_shuttle, SHUTTLE_*): countdown, liftoff, hits, loss
"""
import copy, os, struct, sys, zlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'checks'))
import ep_dump

# The flights Survival's spawner draws from: Mission 22's 24 "kokatu" reinforcement flights, 2 aircraft each.
# Scripts/main.lua has the same list (CFG.pool); a flight outside it would spawn without its orders.
POOL = [f'ERA_Unit_{n:02d}_Dep_Air{k}' for n in range(1, 9) for k in range(3)]
# A flight only works inside its unit area (Mission 22's: 6000 m, 0.5 patrol ratio): it loitered near its spawn until
# the player came within ~3 km. Every pool flight gets a 40 km area and (Scripts/main.lua CFG.search) a 40 km AI search
# radius that doesn't lose the player in cloud, so it comes for the player from anywhere in the zone. (The 2026-10-21
# chase, which moved each flight's area onto the player every 6 s, was turned off on 2026-10-22: flights broke off
# fights to fly to the moved area; it is in git history.)
AREA_RADIUS_M = 40000.0                      # pool flights' RadiusInMeter (None: Mission 22's own 6000)
# Milestone 3 (user, 2026-10-22: bombers that only attack the airfield). Mission 22's own Comona Airport strike
# (tools/re/AIRFIELD_SUPPLY.md 2b): its Su-34s get the airport unit as their engagement target with a ground-only search
# and fire at its invincible dummies; a MissedWeapon trigger on each dummy counts what reaches it. The target is
# AB_Unit_01_Ground2 (the 4 dummies alone, Mission 22's landing-time target), spawned at mission start. The bomber
# flights are Mission 22's strike desc and its four idle enemy fighter descs, sized by BOMBER_SIZES in
# build_survival.py; Scripts/main.lua (CFG.airfield) picks their aircraft: Su-34, F-15E, Tu-95, Tu-160.
AIRFIELD_UNIT = 'AB_Unit_01_Ground2'
AIRFIELD_DUMMIES = [f'AB_Obj_01_Dummy{k}' for k in range(4, 8)]      # Mission 22's MissedWeapon_AreaB_0..3 dummies' twins
AIRFIELD_MARK = 'AreaB_MarkActor0'
# Bomber flights and their sizes (user, 2026-10-22: squadrons of 2, 4 and 6). The order is RE_SV_BombRun_NN's and
# Scripts/main.lua CFG.airfield.bombers.pool's.
BOMBER_SIZES = {'ERB_Unit_01_Air2': 4, 'EA_Unit_01_Air0': 2, 'EA_Unit_01_Air1': 2, 'EA_Unit_01_Air2': 4,
                'EB_Unit_01_Air0': 6}
BOMBERS = list(BOMBER_SIZES)
# Heavy bombers never bomb on their own: in every stock mission (M003/004/009/013/028) a Tu-95 / Tu-160 drop is a
# scripted LiveFireOneShotWeapon on weapon slot 4 (WN_WEAPON_4: PlaneBomb002, unguided, no AI capture distance), and
# the damage is counted by script too (build/research/bombers, 2026-10-22). Survival does the same: Lua watches the
# heavies and fires the flight's bomb run over the airfield, then applies the damage itself.
BOMB_COUNT = 6
BOMB_GAP_S = 0.4
# Special round "Comona Defense" (Milestone 6, tools/re/SPECIAL_ROUNDS.md 12a): Mission 22's shuttle on its pad, a
# countdown, liftoff. Mission 22's pad stays as it is (PAD_UNIT: near-miss dummies, 6 AA guns, 4 SAMs, the control
# tower; user, 2026-10-22: "you can leave the AA guns in", "SAMs too and tower"), spawned at the first special and kept;
# build_survival.py moves the shuttle into a unit of its own (SHUTTLE_UNIT, spawned every special: a unit with
# anything still alive can't be spawned again) and gives it Survival's NPC row, for its name SV_Shuttle_Name.
# Scripts/main.lua spawns both in place (SV_Spawn without a position) and runs the countdown on a clock of its own
# that stops while the player is down at the airfield (user, 2026-10-23: "Shuttle timer continues to countdown while in
# the airfield landing store"; exec delays from the shuttle's appearance couldn't stop): at each whole second s of it,
# main.lua fires RE_SV_ShuttleT_<s>, which carries that second's records (radio, ignition, liftoff at
# SHUTTLE_COUNTDOWN_S = main.lua CFG.specials.shuttle.countdown_s, the climb after it). SHUTTLE_REMOVE_S after liftoff
# it is taken off (LiveDestroyUnitExecution) so the next special can spawn it again. Flags for Lua: SV_ShuttleRound 1 while it's on the pad (strike flights go for it instead of the
# airfield), SV_ShuttleLaunched / SV_ShuttleLost, SV_ShuttleHits.
PAD_UNIT = 'AA_Unit_01_Ground0'
SHUTTLE_UNIT = 'SV_Unit_Shuttle'
# the pad's invincible near-miss / tower dummies: a unit of their own, spawned once a run and kept, so the pad's guns,
# SAMs and tower can be removed after each special (user, 2026-10-22: "we have to despawn the allies that spawned with
# the shuttle") and spawned again for the next (a unit with anything still alive can't be)
PAD_DUMMY_UNIT = 'SV_Unit_PadDummies'
PAD_DUMMIES = (['AA_Obj_01_Ground0_Shuttle_Dummy_Point0'] + [f'AA_Obj_01_Ground0_Shuttle_Dummy_{k}' for k in range(5)]
               + [f'AA_Obj_01_Ground0_Tower_Dummy{k}' for k in range(3)])
PAD_REMOVE_LOST_S = 30.0                    # the pad's allies go this long after the shuttle is lost (after liftoff:
                                            # SHUTTLE_REMOVE_S, with the shuttle)
SHUTTLE = 'AA_Obj_01_Ground0_Shuttle_0'
SHUTTLE_NPC_ROW = 'sstb_common_sv'          # DT_SV_NpcMission row (NpcId SHUTTLE_NPC)
SHUTTLE_NPC = 'OP0057_sstb_01_SV'           # DT_SV_NpcRows row, added to DT_NPC by main.lua
SHUTTLE_PATH = '01_Ground0_shuttle_0_Path0'
SHUTTLE_HP = 175.0                          # Mission 22's
SHUTTLE_COUNTDOWN_S = 150.0
SHUTTLE_REMOVE_S = 180.0                    # = Scripts/main.lua CFG.specials.shuttle.remove_s
# Mission 22's countdown radio, as seconds before liftoff (its lines count down in seconds), and its countdown sound
# flags; Mission 22 drives them off its mission timer, Survival off delays from the shuttle's appearance. Nagase's lines
# only (user, 2026-10-23): the Professor's and Tasha's groups (28 s intermission, 10 s main engine) are left out, and
# build_survival.py RADIO_DROP_* takes their rows out of Survival's radio table.
SHUTTLE_RADIO = [(SHUTTLE_COUNTDOWN_S - 3, '01_Wave5_Countdown_Start'), (33, '01_Countdown_Shuttle33'),
                 (32, '01_Countdown_Shuttle32'), (31, '01_Countdown_Shuttle31'),
                 (23, '01_Countdown_Shuttle23'), (22, '01_Countdown_Shuttle22'), (21, '01_Countdown_Shuttle21'),
                 (20, '01_Countdown_Shuttle20'), (19, '01_Countdown_Shuttle19'), (15, '01_Countdown_intermission_2nd'),
                 (11, '01_Countdown_Ignistion'), (8, '01_Countdown_Shuttle8'),
                 (7, '01_Countdown_Shuttle7'), (2, '01_Countdown_Shuttle2and1')]
SHUTTLE_SOUND_FLAGS = [(33, 'AKE_FLAG_Ms22_ARMS_SKY_OP0057_sstb_Countdown_33sec_Set'),
                       (23, 'AKE_FLAG_Ms22_ARMS_SKY_OP0057_sstb_Countdown_23sec_Set'),
                       (8, 'AKE_FLAG_Ms22_ARMS_SKY_OP0057_sstb_Countdown_08sec_Set'),
                       (2, 'AKE_FLAG_Ms22_ARMS_SKY_OP0057_sstb_Countdown_02sec_Set')]
SHUTTLE_SOUND = 'AKE_Ms22_ARMS_SKY_OP0057_sstb_Body_'
# Special round "Amphibious Assault" (SURVIVAL_SPEC.md 7; tools/re/SPECIAL_ROUNDS.md 12b): Mission 13's enemy LCAC
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
# long way round, and over the airfield; each time a Ladon ends a pass over it (the end of the route, then of each
# LADON_LOOP circuit round the airfield) SV_LadonRun<Key> goes up by one and main.lua drops its bombs on the airfield.
LADON_SOURCE_UNIT = 'B_Unit_01_Air0'
LADON_SOURCE_PATH = '01_Air0_Ladon_Path1'
LADON_SOURCE_ROW = 'OP0045_radn_01'          # Mission 16's mission row (NpcId OP0045_ladn_01)
LADON_NPC_SOURCE = 'OP0045_ladn_01'          # DT_NPC (1200 HP, LuaSet 0031_CP)
LADONS = [('Kot', 0.0, 0.0), ('Mishka', 2200.0, 300.0)]   # (key, offset north m, height offset m) - main.lua CFG.specials.ladon
# (x km, y km, altitude km): from the far west (Mission 22's combat zone runs to x -44 km), north, back south across
# the island's west, east along the south and in over the airfield (16.1, -4.4), where the route ends. The circuit
# starts a little past the airfield (LADON_LOOP[0]: a new path begins ahead of the aircraft, hard rule 2; its start
# isn't its end, so it can't "finish" as it begins) and ends over it, so every PathFinish, the bombing run, is over the
# airfield (code review of 2026-10-23: they ended 6.6 km NE of it).
LADON_AIRFIELD = (16.1, -4.4, 1.2)
LADON_ROUTE = [(-42, 4, 3.0), (-34, 17, 3.2), (-20, 24, 2.8), (-6, 16, 2.2), (-11, 2, 1.8), (-3, -13, 2.4),
               (7, -19, 2.0), (12, -11, 1.6), LADON_AIRFIELD]
LADON_LOOP = [(16.72, -3.03, 1.25), (19, 2, 1.5), (24, -6, 1.8), (17, -14, 2.0), (8, -10, 1.8), (10, -2, 1.4), LADON_AIRFIELD]
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


def ladons():
    """One dict per Ladon: unit, object, mission / NPC rows, paths, flag, events, its route (cm)."""
    import math
    out = []
    for key, side_m, up_m in LADONS:
        def place(pts):
            """pts shifted side_m north (+y) and up_m up: one fixed shift for the whole track, so its shape, its
            joins and its turns are KOT's (a shift to the side of the way on flipped across the turn over the airfield:
            MISHKA's next circuit began 1.7 km behind it)"""
            return [(x * 100000.0, (y + side_m / 1000.0) * 100000.0, (a * 1000.0 + up_m) * 100.0) for x, y, a in pts]
        out.append(dict(key=key, unit=f'SV_Unit_Ladon{key}', obj=f'SV_Obj_Ladon{key}', row=f'sv_ladon_{key.lower()}',
                        npc=f'SV_Ladon_{key}', name_key=f'SV_Ladon_{key}', path=f'SV_Path_Ladon{key}',
                        loop=f'SV_Path_Ladon{key}Loop', flag=f'SV_LadonRun{key}', up=f'SV_LadonUp{key}',
                        over=f'SV_LadonOver{key}', lap=f'SV_LadonLap{key}',
                        route=place(LADON_ROUTE), circuit=place(LADON_LOOP)))
    return out


# Special round "Alicorn" (user, 2026-10-23: "start working on the ALICORN special round ... spawn none of the normal
# aircraft"; tools/re/ALICORN.md): the submarine carrier exists only in Online Mode, as Emergency Call EB_002's boss
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


# Special round "The Anomaly" (tools/re/SPECIAL_ROUNDS.md 13; user, 2026-10-22: the ace flies an F-4 and is named
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
# Mission 2's Tasha's cobra); main.lua CFG.specials.glitch.post_stall_moves names the same <name>s
GLITCH_POST_STALL = (('Kulbit', 'Shadow_Kulbit'), ('KulbitB', 'Toprak_Kulbit'), ('Cobra', 'Tasha_Cobra'))
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
# MINDRIPPER's inverted controls. AC7's opener (ms18_Phase_01, tools/re/VALKA.md): a hidden dummy railgun of its own
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
# Airfield defences the shop builds (user, 2026-10-22: "purchase AA guns that sit around the airfield or SAM sites, make
# them expensive"): Mission 22's own airport AA guns and SAM sites (AB_Unit_01_Ground0, never spawned by Survival), each
# moved into a unit of its own by build_survival.py, so Scripts/main.lua (CFG.shop.items.Airfield.defences) spawns them
# one at a time where Mission 22 placed them. Allied, so they fire at enemies by themselves; no event records.
DEFENCE_SOURCE = 'AB_Unit_01_Ground0'
DEFENCES = ([(f'SV_Unit_AAGun_{c}', f'AB_Obj_01_Ground0_AAGUN_{k}', 'gepa_common') for k, c in enumerate('ABCDE')] +
            [(f'SV_Unit_SAM_{c}', f'AB_Obj_01_Ground0_SAM{k}', 'avng_common') for k, c in enumerate('AB')])
# their rows of their own (user, 2026-10-23: "increase the fire rate of the Airfield"): Mission 22's mission row ->
# (Survival's mission row, its DT_SV_NpcRows copy of the DT_NPC row), so Scripts/main.lua can give their weapons fire
# control of their own (CFG.shop.items.Airfield.defences.fcs) without touching the stock rows
DEFENCE_ROWS = {'gepa_common': ('sv_def_gepa', 'SV_Def_Gepa'), 'avng_common': ('sv_def_avng', 'SV_Def_Avng')}
# Allies the STORE sells (user, 2026-10-23: "buy Allied Aircraft from the Store from the Airfield Page ... a Docks Page
# ... Different Allied Ships that will cruise around on the water ... expensive ... boost their FCS ... enemies can
# target these ... Allied Aircraft are F-22's and they spawn in at the Airfield, Take Off from the airfield and their
# Squadron ID is MOONCHILD"). build_survival.py copies the units (enemies may target and kill them: Mission 22's
# scramble jets are invincible and its allied ships attack-target exceptions, both cleared); Scripts/main.lua
# (CFG.allies) sells and spawns them, adds their DT_NPC rows and gives them fire control of their own (<FCS>_SVA).
# MOONCHILD: Mission 22's two F/A-18Es parked at Comona Airport (AB_Unit_01_Air1), as F-22 two-ships. Their appearance
# runs Mission 22's own scramble: hold (gear down, invincible), taxi (the wing 5 s behind, onto the lead's start),
# takeoff roll, climb out; airborne (end of the climb path): gear up, no longer invincible, normal combat orders, an
# air-only search. SV_AllyAir<X> counts the flight's aircraft airborne (main.lua sends enemies after them then).
ALLY_AIR_SOURCE = 'AB_Unit_01_Air1'
ALLY_AIR_UNITS = ['SV_Unit_MoonchildA', 'SV_Unit_MoonchildB']   # main.lua CFG.allies.aircraft.units
ALLY_AIR_ROW = 'sv_ally_moonchild'          # DT_SV_NpcMission row -> NpcId ALLY_AIR_NPC
ALLY_AIR_NPC = 'SV_Ally_Moonchild'          # DT_SV_NpcRows: ALLY_AIR_SOURCE_NPC under name key ALLY_AIR_NAME_KEY
ALLY_AIR_SOURCE_NPC = 'OP1005_f22a_01'
ALLY_AIR_NAME_KEY = 'SV_Moonchild'
ALLY_AIR_OBJS = {}                          # unit -> [lead, wing] object names, set by build_survival.py
TAKEOFF_LEAD = ['01_Air0_f18e_0_Path0', '01_Air0_f18e_0_Path1', '01_Air0_f18e_0_Path2']   # taxi, roll, climb
TAKEOFF_WING_FIRST = '01_Air0_f18e_0_Path0_Sub0'     # the wing's taxi onto the lead's start; then the lead's three
# Ships: Mission 22's own allied hulls, the only ones its world data describes turret by turret (ChildAIObjectDescs:
# mission row, hull component and turret blueprint class each; other hulls would need their turret blueprints
# imported, hard rule 7). One ship per lane, each sailing one of Mission 22's enemy-fleet lanes (Survival has no fleet)
# south and north of the airfield, back and forth: the end of its lane starts the lane again (a PathFinish trigger:
# hard rule 1). Its turrets fly Survival's copies of their mission rows (sv_<row>_ally -> SV_Turret_<row>_Ally).
# Aegis destroyers only (user, 2026-10-23: "remove the LCS Freedom and make it another Aegis"): four, one per lane.
ALLY_SHIPS = [  # (key, Mission 22 source unit, its hull's mission row, lanes) - main.lua CFG.allies.ships, same keys
    ('Aegis', 'AC_Unit_01_Ship1', 'aegs_common', ['01_Ship1_grig_0_Path0', '01_Ship2_gors_0_Path0',
                                                  '01_Ship1_udal_0_Path0', '01_Ship0_udal_0_Path0']),
]
ALLY_TURRETS = {   # each hull's turret mission rows in Mission 22's world data (build_survival.py checks them)
    'Aegis': ['aegs_mk15', 'aegs_mk41', 'aegs_mk45', 'aegs_artillery'],
}
ALLY_SHIP_SPEED = '80'                      # Mission 22's allied ships'
# A ship's unit area: Mission 22's allied hulls have 10 km and 200-6000 m, and its turrets engage only inside it (as
# the fighters' 6 km area kept them from the player): the Aegis's 25 km search and 20 km missiles stopped at 10 km
# (user, 2026-10-23: "aegis's didn't seem to fire all that much better"). Survival's ships get this much.
ALLY_SHIP_AREA_M, ALLY_SHIP_ALT_M = 25000.0, (0.0, 15000.0)


def ally_ships():
    """(key, n, unit, object, lane) for every ship the STORE sells: SV_Unit_Ship<key><A|B|C|D>."""
    return [(key, n, f'SV_Unit_Ship{key}{c}', f'SV_Obj_Ship{key}{c}', lane)
            for key, _, _, lanes in ALLY_SHIPS for n, (c, lane) in enumerate(zip('ABCD', lanes))]


def ally_ship_rows(key):
    """(DT_SV_NpcMission hull row, DT_SV_NpcRows hull row, text key) of ship type `key`."""
    return f'sv_ally_{key.lower()}', f'SV_Ally_{key}', f'SV_Ship_{key}'


def ally_turret_rows(mission_row):
    """(DT_SV_NpcMission row, DT_SV_NpcRows row) of a turret: copies of Mission 22's, no numeric tail (hard rule 17)."""
    return f'sv_{mission_row}_ally', f'SV_Turret_{mission_row}_Ally'
# Behaviour rows (test of 2026-10-22): the game builds every AI aircraft's behaviour trees when the level loads, one
# set per world-data AI object desc, from the NPC row the desc names at that moment (127 aircraft x 15 slots = the
# 1915 behaviours the census counted before anything spawned; each stock script was built once, ours never).
# SV_SetAircraft at spawn changes the airframe and the AI module (search radius), not the behaviour, so every flight
# Survival flies gets its behaviour row here, in the world data (tools/build_survival.py):
POOL_BEHAVIOUR_ROW = 'f16c_common_sv'      # its DT_NPC row is made by Scripts/main.lua at the main menu, with the
                                           # behaviour set CFG.search.luaset (NLID_SV_Fighter; hard rule 22)
PROBE_UNITS = {'Pkg': 'ERA_Unit_08_Dep_Air2', 'Rt': 'ERA_Unit_08_Dep_Air1'}   # main.lua CFG.probe.units
PROBE_ROWS = {'Pkg': 'sv_probe_pkg', 'Rt': 'sv_probe_rt'}                     # build_survival.py NPC_EXTRA
HEAVY_BOMBERS = ['EA_Unit_01_Air1', 'EA_Unit_01_Air2']   # main.lua CFG.airfield.bombers.heavy_units
# Their unit area (RadiusInMeter, moved onto the airfield by SV_BomberUp_NN): Tu-95s / Tu-160s circle inside it, and
# with Mission 22's 6 km they circled 8-12 km out and never crossed the runway, so the scripted bomb run never fired
# (test of 2026-10-22: "TU160's didn't do anything when reaching the airfield"). 1.5 km keeps their orbit over it.
HEAVY_AREA_RADIUS_M = 1500.0
STRIKE_BEHAVIOUR_ROW = 'su34_common'       # Mission 22's strike Su-34s (0021_CP)
HEAVY_BEHAVIOUR_ROW = 't160_common'        # Mission 4's Tu-160 (NLID_1000: large aircraft, no dogfighting)


def flight_size(unit):
    """Aircraft in a flight Survival flies (build_survival.py adds or removes AI objects), or None to leave it.
    Fighter pool: ERA_Unit_NN_Dep_Air0 2, _Air1 4, _Air2 6 (Scripts/main.lua flightSize, same rule)."""
    if unit in BOMBER_SIZES: return BOMBER_SIZES[unit]
    if unit in POOL: return {'0': 2, '1': 4, '2': 6}[unit[-1]]
    return None


def behaviour_row(unit):
    """The NPC row a flight's AI objects name in the world data (its behaviour), or None to leave Mission 22's."""
    for v, u in PROBE_UNITS.items():
        if u == unit: return PROBE_ROWS[v]
    if unit in BOMBERS: return HEAVY_BEHAVIOUR_ROW if unit in HEAVY_BOMBERS else STRIKE_BEHAVIOUR_ROW
    if unit in POOL: return POOL_BEHAVIOUR_ROW
    return None
KEEP_AT_START = {AIRFIELD_UNIT: None}                 # units spawned at mission start (name -> spawn point or None)
# SV_Alive / SV_Kills: diagnostics, logged by Scripts/main.lua. SV_Up_NN: 1 while pool flight NN is up (its orders
# came; main.lua's ordersTick checks it). SV_Shuttle*: Comona Defense (build_shuttle).
INT_FLAGS = (['SV_Alive', 'SV_Kills', 'SV_AirHits'] + [f'SV_Up_{k + 1:02d}' for k in range(len(POOL))]
             + ['SV_ShuttleRound', 'SV_ShuttleLaunched', 'SV_ShuttleLost', 'SV_ShuttleHits', 'SV_ShuttleNearSaid']
             + [f'SV_ShuttleDmg{c}' for c in 'ABC'] + ['SV_AnomalyUp']
             + ['SV_AllyAir' + u[-1] for u in ALLY_AIR_UNITS]
             + [f'SV_LcacLand{lane}{c}' for lane, _, _ in LCAC_LANES for c in LCAC_CRAFT]
             + [f'SV_LcacRunway{lane}{c}' for lane, _, _ in LCAC_LANES for c in LCAC_CRAFT]
             + [f'SV_LadonRun{key}' for key, _, _ in LADONS] + ['SV_Beat', 'SV_ValkaUp'])


# ---------------------------------------------------------------- record helpers (uprop struct tuples)
def fields(rec):
    return {p[1]: p for p in rec[2]}


def setf(rec, name, value):
    """Set field `name` (must exist in the record) to a non-default value."""
    for k, p in enumerate(rec[2]):
        if p[1] == name:
            rec[2][k] = (p[0], name, False, value)
            return
    raise KeyError(name)


def clearf(rec, name):
    for k, p in enumerate(rec[2]):
        if p[1] == name:
            rec[2][k] = (p[0], name, True, None)
            return
    raise KeyError(name)


def args(rec):
    return fields(rec)['ArgsInfo'][3][1]


def set_arg(rec, i, value):
    a = args(rec)[i]
    a[2][:] = [(q[0], q[1], q[2], ('str', str(value)) if q[1] == 'Value' else q[3]) for q in a[2]]


def arg_values(rec):
    return [fields(a)['Value'][3][1] for a in args(rec)]


def fname(s):
    """FName value: 'Name_3' is stored as ('Name', 4) like the engine does; plain names as number 0."""
    base, _, tail = s.rpartition('_')
    if base and tail.isdigit() and not (len(tail) > 1 and tail[0] == '0'):
        return ('name', base, int(tail) + 1)
    return ('name', s, 0)


class Graph:
    def __init__(self, stock_ep):
        self.z, self.i, self.props, self.T, self.E, self.offs = ep_dump.load(stock_ep)
        self.trig, self.ex = [], []
        self.names = set()
        self.used_hashes = {struct.unpack('<i', fields(t)['EventHash'][3][2])[0] for t in self.T}
        self.next_shared = 900000
        self.next_exec = 1
        self.flags = set()      # int flags the records read or write (must all be in INT_FLAGS)
        self.foreign = {}       # other stock EPs read for templates
        self.added_imports = [] # script imports (exec classes) appended to the EP's import map, in order

    # templates --------------------------------------------------------
    def exec_template(self, cls, event=None, pred=None):
        for e in self.E:
            f = fields(e)
            if ep_dump.show(f['ExecutionClass'][3], self.z) != cls: continue
            if event and ep_dump.show(f['ConnectionEventName'][3], self.z) != event: continue
            if pred and not pred(arg_values(e), e): continue
            return copy.deepcopy(e)
        raise LookupError((cls, event))

    def foreign_template(self, stock_ep, cls, event=None, pred=None):
        """An exec record of another stock EP, for a class Mission 22's package doesn't import (Mission 15's HUD
        warning, radar noise, glasses). Its class is a script import: it's appended to this EP's import map (build_ep
        appends the same to the package it writes) and the record points at it."""
        if stock_ep not in self.foreign: self.foreign[stock_ep] = ep_dump.load(stock_ep)
        fz, _, _, _, fE, _ = self.foreign[stock_ep]
        for e in fE:
            f = fields(e)
            if ep_dump.show(f['ExecutionClass'][3], fz) != cls: continue
            if event and ep_dump.show(f['ConnectionEventName'][3], fz) != event: continue
            if pred and not pred(arg_values(e), e): continue
            e = copy.deepcopy(e)
            ref = f['ExecutionClass'][3]
            assert ref[0] == 'obj' and ref[1] < 0, ref
            x = fz.imports[-ref[1] - 1]
            assert x >> 62 == 1, (cls, hex(x))                       # a script import: no package to add
            if x not in self.z.imports:
                self.z.imports.append(x)
                self.added_imports.append(x)
            setf(e, 'ExecutionClass', ('obj', -(self.z.imports.index(x) + 1)))
            setf(e, 'ConditionalStatementTables', ('arr', []))
            return e
        raise LookupError((stock_ep, cls, event))

    def trig_template(self, event):
        for t in self.T:
            if ep_dump.show(fields(t)['EventName'][3], self.z) == event:
                return copy.deepcopy(t)
        raise LookupError(event)

    def cond_template(self):
        for e in self.E:
            for c in fields(e)['ConditionalStatementTables'][3][1]:
                if ep_dump.show(fields(c)['StatementClass'][3], self.z) == 'LiveInequality_FlagIntStatement':
                    return copy.deepcopy(c)
        raise LookupError('LiveInequality_FlagIntStatement')

    # builders ---------------------------------------------------------
    def _hash(self, name):
        h = zlib.crc32(b'AC8SurvivalMode:' + name.encode())
        h = h - (1 << 32) if h >= 1 << 31 else h
        while h in self.used_hashes: h += 1
        self.used_hashes.add(h)
        return h

    def foreign_trig_template(self, stock_ep, event):
        """A trigger record of another stock EP (its type is a byte, EventType: nothing to import)."""
        if stock_ep not in self.foreign: self.foreign[stock_ep] = ep_dump.load(stock_ep)
        fz, _, _, fT, _, _ = self.foreign[stock_ep]
        for t in fT:
            if ep_dump.show(fields(t)['EventName'][3], fz) == event:
                return copy.deepcopy(t)
        raise LookupError((stock_ep, event))

    def trigger(self, template_event, name, life=None, arg_changes=None, template=None):
        t = copy.deepcopy(template) if template is not None else self.trig_template(template_event)
        setf(t, 'EventName', fname(name)); self.names.add(fname(name)[1])
        setf(t, 'EventHash', ('raw', 'Int', struct.pack('<i', self._hash(name))))
        if life: setf(t, 'LifeCount', ('raw', 'Int', struct.pack('<i', life)))
        else: clearf(t, 'LifeCount')
        for i, v in (arg_changes or {}).items(): set_arg(t, i, v)
        self.trig.append(t)
        return t

    def cond(self, flag, op, value):
        c = self.cond_template()
        setf(c, 'SharedID', ('raw', 'Int', struct.pack('<i', self.next_shared))); self.next_shared += 1
        for i, v in enumerate((flag, op, value)): set_arg(c, i, v)
        self.flags.add(flag)
        return c

    def execute(self, template, event, arg_changes=None, delay=None, conds=(), loop=None):
        e = copy.deepcopy(template)
        setf(e, 'ConnectionEventName', fname(event)); self.names.add(fname(event)[1])
        for i, v in (arg_changes or {}).items(): set_arg(e, i, v)
        if delay: setf(e, 'Delay', ('raw', 'Float', struct.pack('<f', delay)))
        else: clearf(e, 'Delay')
        if loop: setf(e, 'LoopCount', ('raw', 'Int', struct.pack('<i', loop)))
        setf(e, 'ConditionalStatementTables', ('arr', list(conds)))
        eid = f'SV_Exec_{self.next_exec}'
        setf(e, 'ExecutionID', fname(eid)); self.names.add(fname(eid)[1])
        setf(e, 'ExecutionNumber', ('raw', 'Int', struct.pack('<i', self.next_exec))); self.next_exec += 1
        self.ex.append(e)
        return e


def unit_objects(stock_ep, units):
    """{unit: [AI object names]} from the stock world data next to the EP (as event args write them: 'X_0')."""
    import uprop
    from zenpkg import ZenPkg
    wd = os.path.join(os.path.dirname(stock_ep), os.path.basename(stock_ep).replace('EP_', 'WD_'))
    z = ZenPkg(wd)
    i = max(range(len(z.payloads)), key=lambda k: len(z.payloads[k]))
    v, _ = uprop.read_struct(uprop.Ctx(bytes(z.payloads[i]), z.names), 4, 'LiveWorldData')
    out = {}
    for u in [p for p in v[2] if p[1] == 'UnitDescList'][0][3][1]:
        f = {p[1]: p[3] for p in u[2]}
        if f['Name'][1] not in units: continue
        names = []
        for ob in f['AIObjectDescList'][1]:
            n = {p[1]: p[3] for p in ob[2]}['Name']
            names.append(n[1] if n[2] == 0 else f'{n[1]}_{n[2] - 1}')
        out[f['Name'][1]] = names
    return out


def build_events(stock_ep):
    g = Graph(stock_ep)
    # templates, all from Mission 22
    t_flag = g.exec_template('LiveFlagOperation_IntExecution', pred=lambda a, e: a[1] == 'Set')
    t_search = g.exec_template('LiveAIChangeEnemySearchType', '01_E_AreaA_ReinforcementAppearance_0')
    t_engage = g.exec_template('LiveAIEngagementOrder', '01_E_Wave03_ReinforcementAppearance_0')
    # Mission 22's order says PlayerFirst, which let fighters pick the airfield's target points once those existed (AI
    # watch, 2026-10-22: an F-15E pursued BP_GR000_dummy at the runway). PlayerOnlyNoLimit, as Mission 24 orders its
    # pursuers (RE_SilverProtect602_0): the player only, at any range.
    assert arg_values(t_engage)[4] == 'Player' and arg_values(t_engage)[6] == 'PlayerFirst'
    t_move = g.exec_template('LiveUnitMoveActor', '01_E_AreaA_ReinforcementAppearance_0')
    # Mission 22's airport strike (records 1686, 1694, 2037) and its landing switch (2099)
    t_bmove = g.exec_template('LiveUnitMoveActor', 'Default_CompositeEvent_19')       # unit area onto AreaB_MarkActor0
    t_bsearch = g.exec_template('LiveAIChangeEnemySearchType', 'Default_CompositeEvent_98')   # GROUND_ONLY
    t_bengage = g.exec_template('LiveAIEngagementOrder', 'Default_CompositeEvent_98')         # Normal, target unit, AIOnly
    # Mission 22's order on its shuttle attackers (RE_Wave02_TargetUpdate): AttackOnly on the pad unit, AIOnly
    t_sengage = g.exec_template('LiveAIEngagementOrder', 'RE_Wave02_TargetUpdate')
    t_landing = g.exec_template('LiveSetTakeoffAndLandingEventExecution', 'Default_Campaign_ExterminationBattleSuccess')
    t_fire = g.exec_template('LiveFireOneShotWeapon', '01_A_Wave03_ReinforcementAppearance_0')   # WN_WEAPON_4, no target
    t_pause = g.exec_template('LiveSetPauseTimerExecution', 'Default_CompositeEvent_106')   # pause: true
    t_hide = g.exec_template('LiveHideRemainingTimerExecution', 'Default_CompositeEvent_106')

    def flag(event, name, op, value, **kw):
        g.flags.add(name)
        return g.execute(t_flag, event, {0: name, 1: op, 2: value}, **kw)

    g.trigger('MissionStart', 'MissionStart')
    g.execute(t_pause, 'MissionStart')
    g.execute(t_hide, 'MissionStart')
    g.execute(t_hide, 'MissionStart', delay=3.0)   # again once the HUD is up (Mission 8 hides 3 s late)
    # RE_SV_FlightOrders_NN gives a flight the same orders as its appearance: a flight that appears while the player
    # is in the landing menu never gets its appearance trigger (test of 2026-10-22: two F-16 flights spawned during a
    # rearm kept Mission 22's PlayerFirst and attacked the airfield), so Scripts/main.lua fires it for an unflagged flight.
    for k, unit in enumerate(POOL):
        up, down = f'SV_FlightUp_{k + 1:02d}', f'SV_FlightDown_{k + 1:02d}'
        orders = f'RE_SV_FlightOrders_{k + 1:02d}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        g.trigger('RE_SpawnEnemy_kokatu_1st', orders)                  # a remote-event trigger (the 2026-10-21 chase's)
        for ev in (up, orders):
            flag(ev, 'SV_Alive', 'Add', 1)
            flag(ev, f'SV_Up_{k + 1:02d}', 'Set', 1)
            g.execute(t_search, ev, {1: unit}, delay=2.0)
            g.execute(t_engage, ev, {1: unit, 6: 'PlayerOnlyNoLimit'}, delay=2.0)
        g.trigger('UnitDamage_Ship_Destroy_0', down, arg_changes={0: unit})
        flag(down, 'SV_Alive', 'Sub', 1)
        flag(down, 'SV_Kills', 'Add', 1)
        flag(down, f'SV_Up_{k + 1:02d}', 'Set', 0)
    assert arg_values(t_bmove)[3] == AIRFIELD_MARK and arg_values(t_bsearch)[3] == 'GROUND_ONLY'
    assert arg_values(t_bengage)[3] == 'Normal' and arg_values(t_bengage)[5] == 'AB_Unit_01_Ground0'
    assert arg_values(t_sengage)[3] == 'AttackOnly' and arg_values(t_sengage)[5] == PAD_UNIT and arg_values(t_sengage)[6] == 'AIOnly'
    on_airfield = lambda: [g.cond('SV_ShuttleRound', 'Leq', 0)]
    on_shuttle = lambda: [g.cond('SV_ShuttleRound', 'Geq', 1)]
    for k, unit in enumerate(BOMBERS):
        up = f'SV_BomberUp_{k + 1:02d}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        g.execute(t_bmove, up, {0: unit}, delay=1.0, conds=on_airfield())
        g.execute(t_bsearch, up, {1: unit}, delay=2.0, conds=on_airfield())
        g.execute(t_bengage, up, {1: unit, 5: AIRFIELD_UNIT}, delay=2.0, conds=on_airfield())
        # Comona Defense: while the shuttle is on its pad the strike flights go for it (Mission 22's waves' order)
        g.execute(t_move, up, {0: unit, 1: SHUTTLE, 3: 'NoneSelect'}, delay=1.0, conds=on_shuttle())
        # The shuttle is an AI plane (Blueprints/Vehicle/AI/Plane/OP0057_sstb): GROUND_ONLY, the airport strike's search,
        # let the strike flights fly past it (report of 2026-10-23: never damaged). Air and ground, and Mission 22's
        # AttackOnly order on it, so they go for nothing else.
        g.execute(t_bsearch, up, {1: unit, 3: 'AIR_AND_GROUND'}, delay=2.0, conds=on_shuttle())
        g.execute(t_sengage, up, {0: 'NoneSelect', 1: unit, 5: SHUTTLE_UNIT}, delay=2.0, conds=on_shuttle())
        # ... and once the shuttle's taken off, back to the airfield (main.lua fires it for each strike flight still up;
        # a friend's log of 2026-10-24: with only the AttackOnly order on the gone shuttle, three bombers wandered
        # 35 km out for 4 minutes and the round couldn't end)
        retask = f'RE_SV_BomberRetask_{k + 1:02d}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', retask)
        g.execute(t_bmove, retask, {0: unit}, delay=1.0)
        g.execute(t_bsearch, retask, {1: unit}, delay=2.0)
        g.execute(t_bengage, retask, {1: unit, 5: AIRFIELD_UNIT}, delay=2.0)
    for k, dummy in enumerate(AIRFIELD_DUMMIES):
        hit = f'SV_AirfieldHit_{k + 1}'
        t = g.trigger(f'MissedWeapon_AreaB_{k}', hit, arg_changes={4: dummy})      # LifeCount cleared: every hit
        assert arg_values(t)[0] == 'EnemyNPC'
        flag(hit, 'SV_AirHits', 'Add', 1)
        g.execute(g.exec_template('LiveSetActiveVFXExecution', f'MissedWeapon_AreaB_{k}'), hit)
    assert arg_values(t_fire)[0] == 'WN_WEAPON_4' and arg_values(t_fire)[2] == arg_values(t_fire)[3] == 'NoneSelect'
    objs = unit_objects(stock_ep, BOMBERS)
    for k, unit in enumerate(BOMBERS):
        run = f'RE_SV_BombRun_{k + 1:02d}'
        g.trigger('RE_Wave2_AreaB_PathSet', run)
        for obj in objs[unit][:BOMBER_SIZES[unit]]:   # build_survival.py keeps these first aircraft
            g.execute(t_fire, run, {1: obj}, delay=BOMB_GAP_S, loop=BOMB_COUNT)
    assert arg_values(t_landing)[0] == 'false'
    # the run's heartbeat (Scripts/main.lua fires it every 10 s): a mission restart sets every flag back to 0, so a drop
    # in SV_Beat is a restart even in a round without a kill or an airfield hit (test of 2026-10-23: a retry after the
    # Ladons shot the player down went unseen and the run went on to round 2)
    g.trigger('RE_Wave2_AreaB_PathSet', 'RE_SV_Beat')
    flag('RE_SV_Beat', 'SV_Beat', 'Add', 1)
    for ev, on in (('RE_SV_AirfieldClose', 'false'), ('RE_SV_AirfieldOpen', 'true')):
        g.trigger('RE_Wave2_AreaB_PathSet', ev)                                    # a remote-event trigger
        g.execute(t_landing, ev, {0: on})
    build_shuttle(g, flag)
    build_anomaly(g, flag, stock_ep, t_search, t_engage, t_move)
    build_glitch(g, t_search, t_engage, stock_ep)
    build_valka(g, flag, t_search, t_engage, stock_ep)
    build_repair(g, stock_ep)
    build_allies(g, flag, t_search, t_move, t_bsearch)
    build_amphib(g, flag, stock_ep)
    build_ladon(g, flag, stock_ep)
    build_alicorn(g, flag, stock_ep)
    build_ace_moves(g, flag, stock_ep)
    return g


def build_ace_moves(g, flag, stock_ep):
    """Ace moves (2026-10-23, "a proper fix for the cannon fodder"; tools/re/UNIQUE_ACTIONS.md): remote events that
    Scripts/main.lua fires on a pool flight flying a top tier (CFG.aces.flight <tier>.moves) when the player gets
    behind one of its aircraft: RE_SV_AceTurn_NN = the campaign aces' LastTGT (a hard 600 km/h turn onto the player,
    then 10 s 200 m behind it, twice), RE_SV_AceKulbit_NN = the Shadow squadron's kulbit (0.5 s straight, a kulbit firing
    its special weapon). Both OneShot (they end by themselves), by unit (every plane of the flight), Below_Return
    (they outrank evading, provoke and pursuit). The stock EnemyBehind trigger isn't used: it only fires for the
    player's selected target, matches a callsign, and re-fires every frame (restarting the move)."""
    m06 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'MIssion006', 'EP_Mission006_global.uasset')
    t_req = g.foreign_template(m06, 'LiveAIRequestUniqueAction', 'EnemyBehind_LastTGT')
    assert arg_values(t_req)[3] == 'LastTGT', arg_values(t_req)
    for k, unit in enumerate(POOL):
        for name, action in (('AceTurn', 'LastTGT'), ('AceKulbit', 'Shadow_Kulbit')):
            ev = f'RE_SV_{name}_{k + 1:02d}'
            g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
            g.execute(t_req, ev, {0: 'NoneSelect', 1: unit, 2: '', 3: action, 4: 'OneShot', 5: 'Below_Return', 6: 'NoneSelect', 7: 'false'})


def build_allies(g, flag, t_search, t_move, t_bsearch):
    """The STORE's allies (ALLY_*): MOONCHILD's scramble, the ships' lanes, and the enemy orders Scripts/main.lua fires
    at them: RE_SV_Hunt_NN (pool flight NN prefers AI targets: allied aircraft over the player) and
    RE_SV_Strike<ship unit>_NN (bomber flight NN attacks that ship only)."""
    tpl = lambda cls, ev, pred=None: g.exec_template(cls, ev, pred)
    lead = lambda i: (lambda a, e: a[i] == 'AB_Obj_01_Air1_f18e_0')
    t_hold = tpl('LiveAIPathExecution', 'RE_Wave01_Start', lead(0))                   # Path0 at speed 0
    t_taxi = tpl('LiveAIPathExecution', '01_Wave01_CheckDistanceEvent', lead(0))      # Path0 at 50
    t_roll = tpl('LiveAIPathExecution', '01_A_Air1_f18e_PathFinish')                  # Path1 at 600
    t_climb = tpl('LiveAIPathExecution', '01_A_Air1_f18e_PathFinish_1')               # Path2 at 800
    t_gear_dn = tpl('LiveEnableLandingGear', 'RE_Wave01_Start', lead(0))
    t_gear_up = tpl('LiveEnableLandingGear', '01_A_Air1_f18e_PathFinish_3')
    t_attr_hold = tpl('LiveSetCommonAttribute', 'RE_Wave01_Start', lead(1))
    t_attr_taxi = tpl('LiveSetCommonAttribute', '01_Wave01_CheckDistanceEvent', lead(1))
    t_attr_air = tpl('LiveSetCommonAttribute', '01_A_Air1_f18e_PathFinish_3')
    t_eng_hold = tpl('LiveAIEngagementOrder', 'RE_Wave01_Start', lead(0))             # None: no fighting on the ground
    t_eng_air = tpl('LiveAIEngagementOrder', '01_A_Air1_f18e_PathFinish_3')           # Normal, Default
    t_radio = tpl('LiveRadioPlayExecution', '01_Wave01_CheckDistanceEvent')           # allies taking off
    assert [arg_values(t)[2] for t in (t_hold, t_taxi, t_roll, t_climb)] == TAKEOFF_LEAD[:1] * 2 + TAKEOFF_LEAD[1:]
    assert arg_values(t_hold)[4] in ('0', '0.0') and arg_values(t_taxi)[4] == '50'
    assert arg_values(t_gear_dn)[3] == 'true' and arg_values(t_gear_up)[3] == 'false'
    assert arg_values(t_attr_hold)[3:5] == ['false', 'true'] and arg_values(t_attr_air)[3:5] == ['true', 'false']
    assert arg_values(t_eng_air)[3] == 'Normal' and arg_values(t_eng_air)[6] == 'Default'
    assert arg_values(t_radio)[0] == '01_Wave1_Ally_Take_Off'
    finish = '01_A_Air1_f18e_PathFinish'                   # PathFinish trigger template: {0 object, 2 path}
    assert arg_values(g.trig_template(finish))[2] == TAKEOFF_LEAD[0]
    for unit in ALLY_AIR_UNITS:
        x = unit[-1]
        o_lead, o_wing = ALLY_AIR_OBJS[unit]
        up, air = f'SV_AllyUp{x}', f'SV_AllyAir{x}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        flag(up, air, 'Set', 0)
        for o, path in ((o_lead, TAKEOFF_LEAD[0]), (o_wing, TAKEOFF_WING_FIRST)):
            g.execute(t_hold, up, {0: o, 2: path})
            g.execute(t_gear_dn, up, {0: o})
            g.execute(t_attr_hold, up, {1: o})
            g.execute(t_eng_hold, up, {0: o})
        g.execute(t_taxi, up, {0: o_lead}, delay=3.0)
        g.execute(t_taxi, up, {0: o_wing, 2: TAKEOFF_WING_FIRST}, delay=8.0)
        for o in (o_lead, o_wing):
            g.execute(t_attr_taxi, up, {1: o}, delay=3.0)
        g.execute(t_radio, up, delay=3.0)
        # the chain, one PathFinish trigger per aircraft and path: wing onto the lead's start first
        chain = [(o_lead, TAKEOFF_LEAD[0], t_roll, 'L1'), (o_wing, TAKEOFF_WING_FIRST, t_taxi, 'W0'),
                 (o_wing, TAKEOFF_LEAD[0], t_roll, 'W1'), (o_lead, TAKEOFF_LEAD[1], t_climb, 'L2'),
                 (o_wing, TAKEOFF_LEAD[1], t_climb, 'W2')]
        for o, path, nxt, tag in chain:
            ev = f'SV_AllyTakeoff{x}{tag}'
            g.trigger(finish, ev, arg_changes={0: o, 2: path})
            g.execute(nxt, ev, {0: o})
        for o, tag in ((o_lead, 'L'), (o_wing, 'W')):
            ev = f'SV_AllyAirborne{x}{tag}'                  # the end of the climb out: a fighter now
            g.trigger(finish, ev, arg_changes={0: o, 2: TAKEOFF_LEAD[2]})
            g.execute(t_gear_up, ev, {0: o})
            g.execute(t_attr_air, ev, {1: o})
            g.execute(t_eng_air, ev, {0: o})
            g.execute(t_search, ev, {0: o, 1: 'NoneSelect'})
            flag(ev, air, 'Add', 1)
    # ships: on their lane at once, and again from its start whenever they reach its end; turrets fire at will
    t_spath = tpl('LiveAIPathExecution', 'RE_Wave01_Start', lambda a, e: a[0] == 'AC_Obj_01_Ship1_aegs_0')
    t_upath = tpl('LiveAIPathExecution', 'RE_Wave01_Start', lambda a, e: a[1] == 'AC_Unit_01_Ship1')
    t_seng = tpl('LiveAIEngagementOrder', 'UnitDamage_Enemy_Ship_Last1', lambda a, e: a[0].startswith('AC_Obj_01_Ship1'))
    assert arg_values(t_spath)[4] == ALLY_SHIP_SPEED and arg_values(t_seng)[3] == 'Normal'
    for key, n, unit, obj, lane in ally_ships():
        up, lap = f'SV_ShipUp{key}{unit[-1]}', f'SV_ShipLap{key}{unit[-1]}'
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: unit})
        g.trigger(finish, lap, arg_changes={0: obj, 2: lane})
        for ev, delay in ((up, 1.0), (lap, 2.0)):
            g.execute(t_spath, ev, {0: obj, 2: lane}, delay=delay)
            g.execute(t_upath, ev, {1: unit, 2: lane}, delay=delay)
        g.execute(t_seng, up, {0: 'NoneSelect', 1: unit}, delay=2.0)
    # enemy orders on them: a fighter flight that prefers AI targets (Mission 22's AIFirst order, no target: the allied
    # aircraft first, else the player; still air-only), and a strike flight on one ship (as on the shuttle)
    t_hunt = g.exec_template('LiveAIEngagementOrder', pred=lambda a, e: a[3] == 'Normal' and a[6] == 'AIFirst')
    t_strike = tpl('LiveAIEngagementOrder', 'RE_Wave02_TargetUpdate')
    assert arg_values(t_strike)[3] == 'AttackOnly' and arg_values(t_strike)[6] == 'AIOnly'
    for k, unit in enumerate(POOL):
        ev = f'RE_SV_Hunt_{k + 1:02d}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_hunt, ev, {0: 'NoneSelect', 1: unit, 2: 'NoneSelect', 4: 'NoneSelect', 5: 'NoneSelect'})
    for key, n, ship, obj, lane in ally_ships():
        for k, unit in enumerate(BOMBERS):
            ev = f'RE_SV_Strike{key}{ship[-1]}_{k + 1:02d}'
            g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
            g.execute(t_move, ev, {0: unit, 1: obj, 3: 'NoneSelect'})
            g.execute(t_bsearch, ev, {1: unit, 3: 'AIR_AND_GROUND'})
            g.execute(t_strike, ev, {0: 'NoneSelect', 1: unit, 5: ship})


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
    Mission 16's Normal engagement order; the end of the route or of a circuit -> SV_LadonRun<Key> + 1 and the next
    circuit."""
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
    for L in ladons():
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', L['up'], arg_changes={0: L['unit']})
        flag(L['up'], L['flag'], 'Set', 0)
        g.execute(t_path, L['up'], {0: L['obj'], 2: L['path'], 4: LADON_SPEED}, delay=1.0)
        g.execute(t_eng, L['up'], {0: L['obj']}, delay=2.0)
        for part in LADON_CIWS:
            g.execute(t_ciws, L['up'], {0: f"{L['obj']}_{part}"}, delay=2.5)
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
        for ev, path in ((L['over'], L['path']), (L['lap'], L['loop'])):
            g.trigger(finish, ev, arg_changes={0: L['obj'], 2: path})
            flag(ev, L['flag'], 'Add', 1)
            g.execute(t_path, ev, {0: L['obj'], 2: L['loop'], 4: LADON_SPEED})


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


def build_repair(g, stock_ep):
    """RE_SV_RepairAircraft: the player's aircraft back to full health (LiveRestorePlayerPlaneExecution, Training001's
    node: SetHealth(Max) and the armour pool refilled; tools/re/KILLS_HEALTH_DEATH.md). The airfield shop fires it."""
    tr = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Training001', 'EP_Training001_global.uasset')
    t_restore = g.foreign_template(tr, 'LiveRestorePlayerPlaneExecution')
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_RepairAircraft')
    g.execute(t_restore, 'RE_SV_RepairAircraft')


def build_anomaly(g, flag, stock_ep, t_search, t_engage, t_move):
    """The Anomaly (see ANOMALY_*): MINDRIPPER's appearance, its guards' orders, its death, and the field's effects
    Scripts/main.lua switches with RE_SV_AnomalyFieldOn / RE_SV_AnomalyFieldOff (RE_SV_AnomalyEnd: everything off)."""
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
    lua = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts',
                            'main.lua'), encoding='utf-8').read()
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
    # unique actions (tools/re/UNIQUE_ACTIONS.md 9), OneShot (they end by themselves), Below_Return (above evading and
    # pursuit), as build_ace_moves; Scripts/main.lua ANOM.glitchTick picks one (CFG.specials.glitch.post_stall_*)
    m06 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'MIssion006', 'EP_Mission006_global.uasset')
    t_req = g.foreign_template(m06, 'LiveAIRequestUniqueAction', 'EnemyBehind_LastTGT')
    assert arg_values(t_req)[3] == 'LastTGT', arg_values(t_req)
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
    assert VALKA_OBJ and VALKA_RAILGUN in VALKA_PARTS, 'build_survival.py valka_unit sets VALKA_OBJ / VALKA_PARTS first'
    lua = open(os.path.join(HERE, '..', 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'main.lua'), encoding='utf-8').read()
    m = re.search(r'spots = \{ ((?:\{ [^}]* \},? )+)\}', lua)
    lua_spots = re.findall(r'\{ "(\w)", (\d+), (\d+) \}', m.group(1)) if m else []
    assert [(r, int(a), int(b)) for r, a, b in lua_spots] == list(VALKA_SPOTS), 'main.lua CFG.specials.valka.spots != VALKA_SPOTS'
    dirn = os.path.dirname(os.path.dirname(stock_ep))
    m15 = os.path.join(dirn, 'Mission015', 'EP_Mission015_global.uasset')
    m19 = os.path.join(dirn, 'Mission019', 'EP_Mission019_global.uasset')
    m26 = os.path.join(dirn, 'Mission026', 'EP_Mission026_global.uasset')
    m06 = os.path.join(dirn, 'MIssion006', 'EP_Mission006_global.uasset')
    t_msg = g.exec_template('LiveMessageExecution', 'RE_FinishMessage')
    t_tp = g.exec_template('LiveActorTeleportExecution', '01_Wave05_YesEvent02', lambda a, e: a[1] == 'A_Obj_01_dummyN0')
    t_fire = g.foreign_template(m19, 'LiveFireOneShotWeapon', '05_PhaseStart_4', lambda a, e: a[1] == 'E_Obj_00_Air0_rflm_0')
    t_hold = g.foreign_template(m26, 'LiveAIEngagementOrder', 'x40a_fire_AB_Ship0_3')        # {0 part, 3 EvadeOnly}
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
    flag(up, 'SV_ValkaUp', 'Set', 1)
    # the opener's dummy railgun: held (EvadeOnly: it never attacks by itself; twice, in case the first is early),
    # one shot at the player on command (as Mission 26 fires its held CK railgun), its charge heard at the player (it's
    # 9 km out), removed by main.lua after the shot
    eml_up = 'SV_ValkaEmlUp'
    g.trigger('01_E_AreaA_ReinforcementAppearance_0', eml_up, arg_changes={0: VALKA_EML_UNIT})
    for d in (0.5, 2.0):
        g.execute(t_hold, eml_up, {0: VALKA_EML_OBJ}, delay=d)
    remote('RE_SV_ValkaEmlShot')
    g.execute(t_fire, 'RE_SV_ValkaEmlShot', {0: 'WN_WEAPON_1', 1: VALKA_EML_OBJ})
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
    # the flags back to 0 once it's taken off (they're set to 0 at its next appearance too)
    for name in resets:
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


def write_records(g, z, prefix_props_bytes):
    """Payload for z (the renamed EP copy): properties + u32 0 + triggers + execs."""
    import uprop
    for n in sorted(g.names): z.nb.add(n)       # sorted: the same build twice gives the same bytes
    w = uprop.W(z.names)
    out = bytearray(prefix_props_bytes) + b'\0\0\0\0' + struct.pack('<I', len(g.trig))
    for t in g.trig: out += uprop.write_struct(w, t)
    out += struct.pack('<I', len(g.ex))
    for e in g.ex: out += uprop.write_struct(w, e)
    return bytes(out)
