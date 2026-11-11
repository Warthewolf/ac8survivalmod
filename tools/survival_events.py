"""survival_events.py : Survival Mode's event graph (EP_SurvivalMode_global), built from Mission 22's own records.

Every trigger / exec here is a deep copy of a stock Mission 22 record of the same node class, with only its names,
unit/flag arguments, delays and conditions changed, so the node classes, argument layouts and TipsHashes are the
game's own. EP_SurvivalMode_global is a copy of EP_Mission022_global, so its import and name tables already hold every
node class and most names these records use. Record format: docs/re/EVENT_NOTES.md.

Rounds are run by Survival's own spawner (Scripts/main.lua + the native runtime, docs/re/SPAWN_SYSTEM.md), not
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
  RE_SV_Radio<Suffix> a tell's radio line (TELL_LINES, build_tells: one DT_SV_Radio group each), fired by
                      Scripts/sv_tells.lua (behaviour roadmap P3)
  RE_SV_WolfHold / WolfFree / WolfTurn_<NN><L>  one Wolf trap object's hold, release and LastTGT (build_wolf; P1's
                      fighter roles), fired by Scripts/sv_spawn.lua WOLF
  RE_SV_Salvo_<NN><L> one pool object's missile at the player; RE_SV_DirHold_NN / RE_SV_DirFree_NN a pool flight's
                      engagement held (None) and given back (build_director; P2's squad director, Scripts/sv_director.lua)
  RE_SV_WraithBlink<K><J>  an ace squadron flight's lead teleported to bearing J round the player (build_wraith; P9's
                      ace personalities, Scripts/sv_ai.lua ACE.squadTick)
  SV_FestUp<g> / RE_SV_FestUp_<g>  THE FESTIVAL's Tu-160 formation g (N W S) up: gear up, engagement None, once a spawn
                      its path (run in, then FEST_LAPS racetrack laps through its launch point; build_festival)
  RE_SV_FestCM_<g><k> / RE_SV_FestCMHit_<g><k>_<i>  a cruise missile salvo's paths to the runway (Mission 30's records)
                      and missile i's impact (LiveDestroyUnitExecution), fired by the festival's Lua
  RE_SV_Char<Step> / RE_SV_Esc<Name><Step>  THE ESCORT: CHARLENE's and her escorts' route, wait, final, rollout, taxi to
                      a parking slot and stop (build_escort; docs/re/ESCORT.md "Build names"); RE_SV_CargoLaunch_<s>_<n>
                      a ZFA-44 two-ship from cargo ship s's container launcher arm n
  RE_SV_Decoy*        THE DECOY: the bait's and the trap UAVs' lasers, the marks, the Spear, its impact counter
                      SV_DecoySpearHit, the sure kill and the radio (build_decoy; docs/re/DECOY.md "Build names")

The parts (2026-11-07: no source file over 2,000 lines, tools/checks/size_check.py). This file keeps the shared names
(the units, rows, slots and flags that build_survival.py, tools/checks and Scripts/*.lua read), the record helpers and
Graph, build_events, and the builders whose text the Lua tests read here (tools/checks/*_test.lua: the heavies, the
jammer, the raid pings, the Spaceport Assault, the run-over). The rest is in four parts, imported at the end of this
file with `from <part> import *`, so survival_events.<name> reaches every name of every part:
  - survival_events_specials.py: the Amphibious Assault, the Ladons, the Alicorn, the Anomaly, AB.L..IN, VALKA and the
    shuttle
  - survival_events_squads.py: the economy review's orders, ace moves, the Wolf trap, the squad director, the tells,
    Wraith's blinks, the STORE's allies and VOID WATCHER 1
  - survival_events_festival.py: GONE FISHIN' and THE FESTIVAL
  - survival_events_escort.py: THE ESCORT, the ZFA-44 cargo ships and THE DECOY
Each part begins with `from survival_events import *`, so it sees every name defined above its import line here and
every name of the parts imported before it, as when this was one file. The int flags (KEEP_AT_START, INT_FLAGS) are made
between the imports: after the specials (they read the specials' names), before the parts that add flags of their own.
build_survival.py sets ANOMALY_OBJ, GLITCH_OBJ and VALKA_OBJ on this module, so the specials' builders read them as
survival_events.<name>. Import survival_events, never a part on its own.
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
# (docs/re/AIRFIELD_SUPPLY.md 2b): its Su-34s get the airport unit as their engagement target with a ground-only search
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
# Special round "Comona Defense" (Milestone 6, docs/re/SPECIAL_ROUNDS.md 12a): Mission 22's shuttle on its pad, a
# countdown, liftoff. Mission 22's pad stays as it is (PAD_UNIT: near-miss dummies, 6 AA guns, 4 SAMs, the control
# tower; user, 2026-10-22: "you can leave the AA guns in", "SAMs too and tower"), spawned at the first special and kept;
# build_survival.py moves the shuttle into a unit of its own (SHUTTLE_UNIT, spawned every special: a unit with
# anything still alive can't be spawned again) and gives it Survival's NPC row, for its name SV_Shuttle_Name.
# Scripts/main.lua spawns both in place (SV_Spawn without a position) and runs the countdown on a clock of its own
# that stops while the player is down at the airfield (user, 2026-10-23: "Shuttle timer continues to countdown while in
# the airfield landing store"; exec delays from the shuttle's appearance couldn't stop; a co-op host's runs on while
# another player flies, user, 2026-10-29: sv_rounds.lua othersFlying): at each whole second s of it,
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
# The STORE's CIWS (0.72.1; user, 2026-10-29: "Add CIWS that can be purchased and placed around the airfield", "fixed
# spots around the runway are fine"): the game's land Phalanx, GR033_ciws (BP_AITurret_Pawn; one arms of
# LiveFCSModule_AIControlCIWS / LauncherBoneControl / ProjectileCommon on TurretPoseableMesh, all the way round). Four
# units of their own, each a copy of Survival's first AA gun unit (Mission 22's allied airport unit: faction 1, its
# tags, its ground objects' flags) on mission row DEFENCE_CIWS_ROW[0] (a copy of gepa_common's) -> DT_SV_NpcRows'
# DEFENCE_CIWS_ROW[1], a copy of DT_NPC's DEFENCE_CIWS_NPC on the game's own allied model row DEFENCE_CIWS_MODEL
# (BP_GR033_ciws_CP_Ally: BP_GR033_ciws_CP with an ally's destruction effects). Scripts/sv_config.lua
# CFG.shop.items.Airfield.defences.ciws sells them, in DEFENCE_CIWS's order (keep its units in step).
# Spots: km along Mission 22's runway axis from its centre (+ ENE) and across it (+ SSE), by its two ends, each side;
# >= 170 m from every airport object (AA guns, SAM sites, dummies, the parked F/A-18s, the scramble taxi), >= 170 m off
# the axis (the runway is 30 m wide, its approach box 98 m), >= 80 m from the amphibious troops' drives (lcac_craft),
# well inside the beaches the coast marks give (LCAC_LANES: 0.45-0.55 km off the axis by the runway's middle); on the
# ground at the airport objects' 5 m.
# Every defence unit's area (0.72.1): Mission 22's airport unit has 6 km and 500-6000 m, and turrets engage only inside
# their unit's area (the Aegis's 20 km missiles stopped at its 10 km: ALLY_SHIP_AREA_M), which would hold the SAM
# sites' 8 km lock-on and the defences' 10 km search (CFG.shop.items.Airfield.defences.fcs) in; the ships' then.
DEFENCE_AREA_M, DEFENCE_ALT_M = 30000.0, (0.0, 15000.0)   # (2026-10-31: 25 -> 30 km, the SAM sites' 20 km missiles)
DEFENCE_CIWS_ROW = ('sv_def_ciws', 'SV_Def_Ciws')
DEFENCE_CIWS_MISSION_SOURCE = 'gepa_common'
DEFENCE_CIWS_NPC = 'GR033_ciws_01'
DEFENCE_CIWS_MODEL = 'GR033_ciws_Ally'
DEFENCE_CIWS_SOURCE_UNIT = 'SV_Unit_AAGun_A'     # (DEFENCES' first unit: made by build_survival.py split_units)
DEFENCE_CIWS_Z_CM = 500.0
DEFENCE_CIWS = [  # (unit, object, km along, km across)
    ('SV_Unit_Ciws_A', 'SV_Obj_CiwsA', -0.70, -0.25),     # the WSW end, north side
    ('SV_Unit_Ciws_B', 'SV_Obj_CiwsB', -0.75, +0.25),     # the WSW end, south side
    ('SV_Unit_Ciws_C', 'SV_Obj_CiwsC', +0.80, -0.17),     # the ENE end, north side
    ('SV_Unit_Ciws_D', 'SV_Obj_CiwsD', +0.85, +0.20),     # the ENE end, south side
]


def defence_ciws():
    """[(unit, object, (x, y, z) cm, yaw deg)]: DEFENCE_CIWS on the runway (LCAC_RUNWAY: Mission 22's), facing along it."""
    import math
    (rx, ry), ryaw = LCAC_RUNWAY
    ux, uy = math.cos(math.radians(ryaw)), math.sin(math.radians(ryaw))
    return [(unit, obj, (rx + (al * ux - ac * uy) * 1e5, ry + (al * uy + ac * ux) * 1e5, DEFENCE_CIWS_Z_CM), ryaw)
            for unit, obj, al, ac in DEFENCE_CIWS]
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
# WINGMEN (economy review of 2026-10-25: "a pair of F-16s for about 5,000"): flown on MOONCHILD's units, their airframe
# set at takeoff (main.lua CFG.allies.wingmen.row); the campaign's plain enemy F-16C under their own name key
ALLY_WINGMEN_ROW = 'sv_ally_wingmen'        # DT_SV_NpcMission row -> NpcId ALLY_WINGMEN_NPC
ALLY_WINGMEN_NPC = 'SV_Ally_Wingmen'
ALLY_WINGMEN_SOURCE_NPC = 'OP1022_f16c_01'
ALLY_WINGMEN_NAME_KEY = 'SV_Wingmen'
# Squadron SNIPER (was VIPER; user, 2026-10-31: "rename VIPER to SNIPER and change their standard missiles to LAAM's",
# "I think you might need to edit the aircraft files themselves"): Survival's copy of the F-16C row (ALLY_WINGMEN_NPC in
# DT_SV_NpcRows, never the game's) has the game's AI LAAM fire control (the row the Shadow aces' LAAMs are on) where the
# stock row has its standard missile; Scripts/sv_allies.lua then boosts it as every allied weapon (<FCS>_SVA)
ALLY_WINGMEN_MISSILE = ('NPC_FCS_PlaneMsl000', 'NPC_FCS_PlaneLAAM000')
ALLY_AIR_OBJS = {}                          # unit -> [lead, wing] object names, set by build_survival.py
# VOID WATCHER 1 (user, 2026-10-31: "Take off from the airfield as a purchasable ally", "Rename it too VOID WATCHER 1",
# "give it's ESM a huge boost in range and have it orbit around the airfield"): Mission 28's E-767 AWACS Magnolia
# (OP0005_e767_MS28: flares and its ESM, MS28ESM000 -> BP_wp_esm_MS28) under Survival's name key, one AI object copied
# from MOONCHILD's lead parked at Comona Airport (its NPC row the E-767's in the world data, so it builds the large
# aircraft's behaviour set NLID_1000 at level load: hard rule 20). Its appearance runs MOONCHILD's lead's scramble
# (hold, taxi, roll, climb); airborne, gear up, no longer invincible, no fighting (engagement None) and onto its orbit
# (awacs_orbit: a lead-in from the climb-out onto a circle round the airfield, then its two arcs, each one's end starting
# the other; 0.73.73). Lua (Scripts/sv_allies.lua,
# CFG.allies.awacs) sells and spawns it, fires its ESM (RE_SV_AwacsEsm: AWACS_ESM_SLOT, as the jammer's ECM: the AI
# never switches a pod on by itself) and sets each ESM field's range. SV_AwacsAir: 1 once it's airborne.
AWACS_UNIT = 'SV_Unit_VoidWatcher'           # Scripts/sv_config.lua CFG.allies.awacs.unit
AWACS_OBJ = 'SV_Obj_VoidWatcher'
AWACS_ROW = 'sv_ally_voidwatcher'            # DT_SV_NpcMission row -> NpcId AWACS_NPC (on Mission 22's e767_common)
AWACS_ROW_TEMPLATE = 'e767_common'
AWACS_NPC = 'SV_Ally_VoidWatcher'            # DT_SV_NpcRows: AWACS_SOURCE_NPC under name key AWACS_NAME_KEY
AWACS_SOURCE_NPC = 'OP0005_e767_MS28'
AWACS_NAME_KEY = 'SV_VoidWatcher'            # its text, VOID WATCHER 1, set by Lua (SV_SetText)
# its row's fire control: NpcFCSId0 PlaneFlr100, 1 and 2 empty, NpcFCSId3 MS28ESM000, so its ESM is WN_WEAPON_4 (hard rule
# 40: slot n - 1). 0.73.33 fired WN_WEAPON_2, an empty slot: "it's being reported that ESM is not turning on at all"
AWACS_ESM_SLOT = 'WN_WEAPON_4'
# its model row: Survival's copy of Magnolia's (OP0005_e767_Ally_Magnolia: its blueprint and 01c paint) with the game's
# plain E-767 name, not ContainerAllyCallsign_Name_Magnolia ("MAGNOLIA" on its box; user, 2026-10-31: "Delete the
# MAGNOLIA tag from the EW aircraft"); DT_SV_ModelRows, added to DT_NPC_Model by Scripts/sv_allies.lua
AWACS_MODEL = 'SV_Model_VoidWatcher'
AWACS_MODEL_SOURCE = 'OP0005_e767_Ally_Magnolia'
AWACS_MODEL_NAME = 'ContainerAircraft_Name_e767'
# (0.73.73) Its orbit, a path again (SA's test of 2026-11-01: "perhaps expand their holding pattern to a circle with a
# 5-7 kilometer radius, they were flying in tight circles making them an easy target"; its unit-area orbit since 0.73.62
# ran 0.9-6.9 km from the airfield, turning tight). The orbit paths of 0.73.33-0.73.61 were never flown for the reason
# the Ladons' circuit wasn't (LADON_CIRCUIT_KM's note): the circle's start wasn't ahead of the plane along its way out of
# the climb-out. So: the lead-in (AWACS_PATH_IN) starts a step along a turn out of the climb-out's own end, on its way
# (AWACS_CLIMB_END / _DIR, Mission 22's 01_Air0_f18e_0_Path2: 0.4 km up, heading 234, climbing 30 deg; build_survival.py
# checks them on the stock path), turning the circle's way at the widest radius that meets the circle tangentially from
# inside (~2.9 km), climbing to AWACS_IN_TOP_KM, then on round the circle AWACS_IN_CIRCLE_DEG to AWACS_ALT_KM; then
# arcs B and A in turn (as the Ladons': each starts a step past the other's end, its own end half a circle away). Its
# unit area (AWACS_AREA_M) takes the circle in with room (the Ladons' 40 km area once turned them back off their
# route); Lua's backstop RE_SV_AwacsOrbit takes it off its path onto the area orbit at AWACS_FALLBACK_AREA_M
# (0.73.62-0.73.72's).
AWACS_PATH_IN = 'SV_Path_VoidWatcherIn'
AWACS_ARC_A = 'SV_Path_VoidWatcherArcA'
AWACS_ARC_B = 'SV_Path_VoidWatcherArcB'
AWACS_CLIMB_END = (15.288252, -3.91496, 0.4)  # km: TAKEOFF_LEAD[2]'s last point
AWACS_CLIMB_DIR = (-27610.5, 19978.8)          # its tangent there (cm, horizontal)
AWACS_ORBIT_KM = 6.0                         # 550 km/h round 6 km: ~22 deg of bank
AWACS_ARC_STEP_DEG = 15.0                    # its points (and each arc's start past the other's end) every N deg
AWACS_IN_STEP_DEG = 20.0                     # the lead-in turn's points every N deg (its first one N deg on)
AWACS_IN_TOP_KM = 3.5                        # the lead-in's height where it meets the circle (its area's floor)
AWACS_IN_CIRCLE_DEG = 300.0                  # then round the circle, climbing to AWACS_ALT_KM
AWACS_ALT_KM = 4.5
AWACS_SPEED = '550.0'
AWACS_IN_SPEED = '450.0'                     # the lead-in (its turn ~29 deg of bank at 450)
AWACS_ALT_BAND_M = (3500.0, 5000.0)          # its unit area's height band (build_survival.py, 0.73.68)
AWACS_AREA_M = 9000.0                        # its unit area on the airport, the orbit inside it (0.73.62: 6 km)
AWACS_FALLBACK_AREA_M = 6000.0               # Lua's backstop's area orbit (0.73.62-0.73.72's orbit)
# (0.73.78, plan G5: "3 rounds of service, rising price, 8-10 km field, a strike flight after it") Its way home. Survival
# has no landing an AI plane can fly (the stock missions' landings are the player's, LiveSetTakeoffAndLandingEventExecution;
# no stock record lands an AI plane), so it flies out and is taken off: after Lua's RE_SV_AwacsHome (SV_AwacsHome 1) the
# end of the arc it's on starts its exit instead of the other arc (the conditions are read as the PathFinish fires, after
# Lua set the flag: hard rule 26, the Ladons' rage's way), a straight leg along that arc's end tangent from a step ahead
# of it (as each arc starts: hard rule 54's handover, which VOID WATCHER takes at 550 km/h) out to AWACS_OUT_KM at the
# orbit's height (its area's band), its area AWACS_HOME_AREA_M round the airport so it isn't turned back. SV_AwacsOut 1 as
# the exit starts, 2 at its end. Lua takes it off (RE_SV_AwacsRemove, Mission 22's own despawn on its unit, then
# SV_Recycle) once it's far enough out, at the exit's end or after a time (hard rule 4).
AWACS_OUT_A = 'SV_Path_VoidWatcherOutA'      # from arc A's end
AWACS_OUT_B = 'SV_Path_VoidWatcherOutB'      # from arc B's end
AWACS_OUT_KM = 24.0                          # the exit's length from the arc's end
AWACS_OUT_STEP_KM = 3.0                      # its points every N km (its first a step of the arc ahead)
AWACS_HOME_AREA_M = 40000.0                  # its unit area round the airport on the way out (AREA_RADIUS_M's)
# Survival COOP (runtime 0.20.0; Scripts/sv_coop.lua, docs/re/COOP.md): the other player's plane in this game, a one-plane
# copy of MOONCHILD's source (allied, and invincible as Mission 22 parks it). Lua sets its airframe to the other player's,
# turns its fire, engagement and flares off, and the runtime moves it every frame to where the other player is
# (coop.c: the AI plane's own teleport). Its appearance: gear up, no engagement (its fire stays off from Lua too).
COOP_PEER_SLOTS = 'ABCDEFGHIJKLMNOPQRSTUVWX'   # one per player slot (A = player 1, the host ... X = player 24)
COOP_PEER_UNITS = [f'SV_Unit_CoopPeer{c}' for c in COOP_PEER_SLOTS]
COOP_PEER_OBJS = [f'SV_Obj_CoopPeer{c}' for c in COOP_PEER_SLOTS]
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
ALLY_SHIP_AREA_M, ALLY_SHIP_ALT_M = 45000.0, (0.0, 15000.0)   # (2026-10-31: 25 -> 45 km, the 35 km missiles' reach)


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
# Their unit area (RadiusInMeter, moved onto the airfield by SV_BomberUp_NN). With Mission 22's 6 km they circled 8-12 km
# out and never crossed the runway, so the scripted bomb run never fired (test of 2026-10-22: "TU160's didn't do anything
# when reaching the airfield"); with 1.5 km (0.20-0.72.0) they still circled 6-8 km out (the user's run of 2026-10-29:
# "tu-95's aren't attacking the base, they fly around nearby and do nothing"). So they fly paths now (HEAVY_ROUTE*), and
# their area takes in every point of them, so they never count as outside it and turn back ("ReturnToWorld").
HEAVY_AREA_RADIUS_M = 40000.0
# The heavies' routes: a Ladon's way (hard rules 1, 2, 35: smooth ControlType 1 paths, PathFinish records). Lua
# (Scripts/sv_flights.lua HEAVY.route, from spawnBomber) fires RE_SV_HeavyRoute_<NN><S> for the compass sector S its
# flight spawned in: its lead flies in from that side, over the runway and on (the route), then at its end a figure-8
# along the same line (the loop) that crosses the runway twice a lap and ends over it, each PathFinish starting it again;
# the bomb run is Lua's, within CFG.airfield.bombers.drop_km of the runway (bombTick). Only the lead flies them (its
# wingmen keep formation on it); when it's shot down Lua fires RE_SV_HeavyLoop_<NN><L><S> for the next of the flight
# (object L). The second heavy flight's tracks sit 1 km to the side and 400 m up. A sector's route starts nearer where
# the zone's edge is closer (east of the airfield), and a loop shrinks to fit.
HEAVY_SECTORS = 'ABCDEFGH'                  # compass 0, 45 ... 315 degrees from the airfield (north -y, east +x)
HEAVY_ROUTE_KM = 22.0                       # the route's first point (or nearer, inside the zone), then these shares of it
HEAVY_ROUTE_FRAC = (1.0, 0.55, 0.18)
HEAVY_PAST_KM = 4.0                         # the route's end, past the runway; the loop starts 2 km on (hard rule 2)
HEAVY_LOOP = [(6.0, 0.8), (9.0, 3.0), (11.5, 0.0), (9.0, -3.0), (5.0, -1.2), (0.0, 0.0),        # (km on, km aside)
              (-5.0, 1.2), (-9.0, 3.0), (-11.5, 0.0), (-9.0, -3.0), (-5.0, -1.2), (0.0, 0.0)]
HEAVY_ALT_KM = (2.2, 1.9, 1.7, 1.6)          # the route's heights in (the rest of it and the loop the last)
HEAVY_TRACKS = {'EA_Unit_01_Air1': (0.0, 0.0), 'EA_Unit_01_Air2': (-1.0, 0.4)}   # (km aside, km up) a heavy flight
HEAVY_SPEED = '850.0'                       # km/h (the user's Tu-95s of 2026-10-29 came in at ~830)
AIRFIELD_KM = (16.09639, -4.36414)          # Scripts/sv_core.lua AIRFIELD (cm / 100000)
ZONE_KM = ((-7.07336, -2.61895), 37.0)      # Scripts/sv_ai.lua ZONE (centre, half), its 3 km margin in it
STRIKE_BEHAVIOUR_ROW = 'su34_common'       # Mission 22's strike Su-34s (0021_CP)
HEAVY_BEHAVIOUR_ROW = 't160_common'        # Mission 4's Tu-160 (NLID_1000: large aircraft, no dogfighting)


def flight_size(unit):
    """Aircraft in a flight Survival flies (build_survival.py adds or removes AI objects), or None to leave it.
    Fighter pool: ERA_Unit_NN_Dep_Air0 2, _Air1 4, _Air2 6 (Scripts/main.lua flightSize, same rule)."""
    if unit in BOMBER_SIZES: return BOMBER_SIZES[unit]
    if unit in POOL: return {'0': 2, '1': 4, '2': 6}[unit[-1]]
    return None


# Fighter roles (behaviour roadmap P1; docs/re/BEHAVIOUR_DIRECTOR.md unit 5): the pool is split into role groups by
# flight number NN, each with its 2 / 4 / 6-ship trio (CFG.squadrons: every role can field a 2-ship from round 1). A
# role's flights name its behaviour row in the world data, so they build its behaviour set when the level loads (hard
# rule 20); the spawner (Scripts/sv_rounds.lua, sv_spawn.lua) draws flights by the round's role mix and gives each its
# role's airframes. ROLE_BY_FLIGHT is Scripts/sv_config.lua's (build_wolf checks they match). NN 08's Air1 / Air2 are the
# behaviour probe's (PROBE_UNITS: their own rows, never in a round), so the Skirmishers have NN 07 and 08's 2-ship.
ROLE_BY_FLIGHT = ['duelist', 'duelist', 'lancer', 'lancer', 'wolf', 'wolf', 'skirm', 'skirm']
POOL_ROLE = {u: ROLE_BY_FLIGHT[int(u[len('ERA_Unit_'):len('ERA_Unit_') + 2]) - 1] for u in POOL}
# The roles' behaviour rows (DT_SV_NpcMission, build_survival.py NPC_EXTRA; each names a DT_NPC row Scripts/sv_rows.lua
# rolesSetup makes at the main menu with the role's behaviour set, CFG.roles.sets): the Duelists keep the fighters' row.
# A Wolf flight is bait and trap pairs: its even objects (0, 2, 4: the lead and the pairs' leads) the bait's row, its
# odd ones the trap's (held at engagement None from their appearance until the trap springs: build_wolf, sv_spawn.lua WOLF).
ROLE_ROW = {'duelist': POOL_BEHAVIOUR_ROW, 'lancer': 'sv_role_lancer', 'wolf': 'sv_role_wolf_lead',
            'skirm': 'sv_role_skirmish'}
WOLF_WING_ROW = 'sv_role_wolf_wing'
ROLE_NPC = {'sv_role_lancer': 'SV_Role_Lancer', 'sv_role_wolf_lead': 'SV_Role_WolfLead',
            'sv_role_wolf_wing': 'SV_Role_WolfWing', 'sv_role_skirmish': 'SV_Role_Skirmish'}
# The Lancers' unit altitude band tops out here (build_survival.py build_wd_global; Mission 22's: 4-5 km), so they can
# spawn 2 km above the others (CFG.roles.lancer.alt_add_m, kept under this less 500 m) and their zoom climbs, gated on the
# band's top less 1 km (LA_SV_LancerZoom), still climb there: the critic's correction (a plane over its band's top may
# count as outside its unit area and return to it, [?]). Scripts/sv_config.lua ROLE.LANCER_TOP_M is the same.
LANCER_MAX_ALT_M = 9000.0
# Every pool flight's AI object names after sizing (event-arg form, 'Base_N-1'), filled by build_survival.py
# build_wd_global before the event package is built: the Wolf trap's per-object events need them.
POOL_OBJS = {}


def heavy_routes():
    """One dict per heavy flight and compass sector (HEAVY_*): unit, its BOMBERS index n, sector letter and bearing,
    the route's and loop's path names and points (cm), and the route's event."""
    import math
    (zx, zy), half = ZONE_KM

    def inside(p):
        return abs(p[0] - zx) < half - 1.0 and abs(p[1] - zy) < half - 1.0
    out = []
    for unit, (side, up) in HEAVY_TRACKS.items():
        n = BOMBERS.index(unit) + 1
        for k, s in enumerate(HEAVY_SECTORS):
            b = math.radians(45.0 * k)
            on, aside = (-math.sin(b), math.cos(b)), (-math.cos(b), -math.sin(b))   # (away from the sector's side)

            def at(u, v):
                return AIRFIELD_KM[0] + u * on[0] + v * aside[0], AIRFIELD_KM[1] + u * on[1] + v * aside[1]
            d = HEAVY_ROUTE_KM
            while d > 8.0 and not inside(at(-d, side)): d -= 0.5
            f = 1.0
            while f > 0.6 and not all(inside(at(u * f, v + side)) for u, v in HEAVY_LOOP): f -= 0.05
            route = [at(-d * r, side) for r in HEAVY_ROUTE_FRAC] + [at(0.0, side), at(HEAVY_PAST_KM, side)]
            loop = [at(u * f, v + side) for u, v in HEAVY_LOOP]
            assert all(inside(p) for p in route + loop), (unit, s, 'a heavy track leaves the zone')
            alts = list(HEAVY_ALT_KM) + [HEAVY_ALT_KM[-1]] * (len(route) - len(HEAVY_ALT_KM))

            def cm(pts, a):
                return [(x * 100000.0, y * 100000.0, (h + up) * 100000.0) for (x, y), h in zip(pts, a)]
            out.append(dict(unit=unit, n=n, sector=s, bearing=45 * k, route_km=d, loop_x=f,
                            path=f'SV_Path_Heavy{n}{s}', loop=f'SV_Path_Heavy{n}{s}Loop', ev=f'RE_SV_HeavyRoute_{n:02d}{s}',
                            route=cm(route, alts), circuit=cm(loop, [HEAVY_ALT_KM[-1]] * len(loop))))
    return out


def awacs_orbit():
    """VOID WATCHER 1's orbit (AWACS_*; 0.73.73), cm: {'in', 'arc_a', 'arc_b' (points), 'in_before', 'in_after',
    'a_before', 'a_after', 'b_before', 'b_after' (the points just outside each, for its tangents)} and, km / deg, the
    lead-in's turn {'rho', 'turn', 'sense'} and the circle {'centre', 'pt' (psi deg round from the lead-in's join)}. The
    lead-in turns from the climb-out's end (AWACS_CLIMB_*) to the side that gives the wider turn, on the circle of radius
    rho that touches the orbit from inside, so it meets the orbit along it; the orbit goes round the same way."""
    import math
    (zx, zy), half = ZONE_KM
    c, r = AIRFIELD_KM, AWACS_ORBIT_KM
    ex, ey, ez = AWACS_CLIMB_END
    n = math.hypot(*AWACS_CLIMB_DIR)
    hx, hy = AWACS_CLIMB_DIR[0] / n, AWACS_CLIMB_DIR[1] / n
    wx, wy = ex - c[0], ey - c[1]
    best = None
    for s in (1, -1):                                      # +1: its centre on the left, a counter-clockwise turn
        px, py = -s * hy, s * hx
        rho = (r * r - wx * wx - wy * wy) / (2.0 * (wx * px + wy * py) + 2.0 * r)
        if best is None or rho > best[0]: best = (rho, s, px, py)
    rho, s, px, py = best
    q = (ex + rho * px, ey + rho * py)                     # the lead-in turn's centre
    qd = math.hypot(q[0] - c[0], q[1] - c[1])
    assert abs(qd - (r - rho)) < 1e-6 and 2.5 <= rho <= r / 2.0 + 1e-9, ('the AWACS lead-in turn', rho, qd)
    j = (c[0] + r * (q[0] - c[0]) / qd, c[1] + r * (q[1] - c[1]) / qd)   # where it meets the orbit
    b0 = math.atan2(ey - q[1], ex - q[0])
    turn = math.degrees((math.atan2(j[1] - q[1], j[0] - q[0]) - b0) * s) % 360.0
    m = int(math.ceil(turn / AWACS_IN_STEP_DEG))
    lead = [circle_point(q, rho, b0, s, turn * k / m, ez + (AWACS_IN_TOP_KM - ez) * k / m) for k in range(1, m + 1)]
    a0 = math.atan2(j[1] - c[1], j[0] - c[0])
    pt = lambda psi, alt: circle_point(c, r, a0, s, psi, alt)
    step = AWACS_ARC_STEP_DEG
    k_in, k_arc = AWACS_IN_CIRCLE_DEG / step, 180.0 / step
    assert abs(k_in - round(k_in)) < 1e-9 and abs(k_arc - round(k_arc)) < 1e-9, 'AWACS_ARC_STEP_DEG must divide both'
    k_in, k_arc = int(round(k_in)), int(round(k_arc))
    climb = [pt(step * i, AWACS_IN_TOP_KM + (AWACS_ALT_KM - AWACS_IN_TOP_KM) * i / k_in) for i in range(1, k_in + 1)]
    pe = AWACS_IN_CIRCLE_DEG                                # the lead-in's end; arc B from a step past it, then arc A
    arc_b = [pt(pe + step * i, AWACS_ALT_KM) for i in range(1, k_arc + 1)]
    arc_a = [pt(pe + 180.0 + step * i, AWACS_ALT_KM) for i in range(1, k_arc + 1)]
    for x, y, _ in lead + climb + arc_a + arc_b:
        assert abs(x - zx) < half - 1.0 and abs(y - zy) < half - 1.0, 'the AWACS orbit leaves the zone'
    # (0.73.78, G5) its exits (AWACS_OUT_*): from each arc's end along the circle's tangent there, the first point a step
    # of the arc (its chord) ahead, then every AWACS_OUT_STEP_KM to AWACS_OUT_KM, at the orbit's height
    chord = 2.0 * r * math.sin(math.radians(step) / 2.0)

    def exit_from(psi):
        e = pt(psi, AWACS_ALT_KM)
        a = a0 + s * math.radians(psi)
        tx, ty = -s * math.sin(a), s * math.cos(a)
        ds, d = [], chord
        while d <= AWACS_OUT_KM + 1e-9:
            ds.append(d)
            d += AWACS_OUT_STEP_KM
        out = [(e[0] + tx * d, e[1] + ty * d, AWACS_ALT_KM) for d in ds]
        nxt = ds[-1] + AWACS_OUT_STEP_KM
        return e, out, (e[0] + tx * nxt, e[1] + ty * nxt, AWACS_ALT_KM)
    eb, out_b, out_b_after = exit_from(pe + 180.0)                 # arc B's end
    ea, out_a, out_a_after = exit_from(pe + 360.0)                 # arc A's end
    assert math.dist(eb[:2], arc_b[-1][:2]) < 1e-6 and math.dist(ea[:2], arc_a[-1][:2]) < 1e-6, 'the AWACS exits: not at the arcs\' ends'
    for x, y, _ in out_a + out_b:
        assert abs(x - zx) < half - 1.0 and abs(y - zy) < half - 1.0, 'an AWACS exit leaves the zone'
    cm = lambda p: (p[0] * 100000.0, p[1] * 100000.0, p[2] * 100000.0)
    return dict(rho=rho, turn=turn, sense=s, centre=c, pt=pt,
                **{'in': [cm(p) for p in lead + climb]}, arc_a=[cm(p) for p in arc_a], arc_b=[cm(p) for p in arc_b],
                in_before=cm((ex, ey, ez)), in_after=cm(arc_b[0]),
                b_before=cm(climb[-1]), b_after=cm(arc_a[0]), a_before=cm(arc_b[-1]), a_after=cm(arc_b[0]),
                out_a=[cm(p) for p in out_a], out_b=[cm(p) for p in out_b], out_a_before=cm(ea), out_b_before=cm(eb),
                out_a_after=cm(out_a_after), out_b_after=cm(out_b_after))


def wolf_held(k):
    """A Wolf flight's object k is the trap (held until sprung): the odd ones, each bait-and-trap pair's second."""
    return k % 2 == 1


def behaviour_row(unit):
    """The NPC row a flight's AI objects name in the world data (its behaviour), or None to leave Mission 22's."""
    for v, u in PROBE_UNITS.items():
        if u == unit: return PROBE_ROWS[v]
    if unit in BOMBERS: return HEAVY_BEHAVIOUR_ROW if unit in HEAVY_BOMBERS else STRIKE_BEHAVIOUR_ROW
    if unit in POOL: return ROLE_ROW[POOL_ROLE[unit]]
    return None


def behaviour_rows(unit, k):
    """The NPC row object k of a flight names: its flight's (behaviour_row), but a Wolf flight's trap objects the trap's."""
    row = behaviour_row(unit)
    if row == ROLE_ROW['wolf'] and wolf_held(k): return WOLF_WING_ROW
    return row


# ---------------------------------------------------------------- names the Lua tests read here (builders: the parts)
# (survival_events_squads.py build_director fires these two slots; tools/checks/spweapons_test.lua reads SPEC_SLOT here)
# The squad director's missile shot (behaviour roadmap P2's bracket salvo; Scripts/sv_director.lua): Mission 19's
# LiveFireOneShotWeapon, which has its Rafale fire WN_WEAPON_3 at the player. WN_WEAPON_<n> is fire-control slot n - 1
# of the plane's NPC row (hard rule 40): the fighters' missiles are slot 2 (DT_NPC: 246 of the 261 OP1xxx rows have
# their first NPC_FCS_PlaneMsl there; the rest none, scripted or part rows, or one ally's in slot 5; every row Survival
# flies is checked at the main menu, sv_rows.lua SR.mslSlot, and the director fires only planes whose row has it
# there). Never the special slot (3+): it holds a different random weapon on each co-op game.
SALVO_SLOT = 'WN_WEAPON_3'
# The enemies' special weapons (the user, 2026-10-31: "I want the Enemies to fire their Special Weapons too"; the weapons
# log: their 2AAM / HCAA carried, never fired, while the standard missiles fired every minute: their AI never picks the
# slot): Scripts/sv_spweapons.lua fires RE_SV_SpecFire_<NN><L>, one pool object's SPEC_SLOT at the player, Mission 19's
# LiveFireOneShotWeapon as the salvo. The special is in slot 3 (sv_rows.lua puts CFG.special.fcs's pick in the first free
# slot from 3: SR.spSlot); the jammer's (its ECM pod there, the special in 4) isn't fired.
SPEC_SLOT = 'WN_WEAPON_4'

# THE ESCORT's start and her escorts (the rest of THE ESCORT is survival_events_escort.py; tools/checks/escort_test.lua
# reads these two from this file)
ESC_START = (-4110000.0, 3140000.0, 300000.0)   # the contract's start: 6 km inside the SW corner, 3 km up
# her four escorts: (name, mission row, km to her right on the way in, km above her). Each one unit of one object, a copy of
# MOONCHILD's lead (ALLY_AIR_SOURCE: allied, parked at the airport; not invincible here), its callsign key SV_<Name>
ESC_ESCORTS = [('Yorke', 'sv_esc_su57', 0.6, 0.10), ('Rock', 'sv_esc_su57', -0.6, 0.10),
               ('Ali', 'sv_esc_su33', 1.2, 0.25), ('Danielle', 'sv_esc_su35', -1.2, 0.25)]


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


def runtime_lua():
    """The runtime's Lua, all of it (Scripts/main.lua is the controller, its parts are Scripts/sv_*.lua:
    tools/lua_split.py), for the checks that keep this file and main.lua's CFG in step."""
    import glob
    d = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts')
    return chr(10).join(open(f, encoding='utf-8').read() for f in sorted(glob.glob(os.path.join(d, '*.lua'))))


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
    # the minimap's alert on a raid (user, 2026-10-31: "an alert that pings the aircraft via the minimap that are
    # attacking the airfield"): RE_SV_RaidPing_NN pings bomber flight NN on the radar, Mission 22's own "look here"
    # (LiveBattleNavigationExecution {tag, unit, timing, force the battle map}: its shuttle and control-centre pings);
    # Scripts/sv_flights.lua raidPings fires it every ping.every_s while that flight is up near the airfield, not sent at
    # a ship. Forwarded in co-op: each joiner's game pings its copies.
    assert '"RE_SV_RaidPing_%02d"' in runtime_lua(), 'Scripts/sv_flights.lua never fires RE_SV_RaidPing_NN'
    t_nav = g.exec_template('LiveBattleNavigationExecution', 'Default_PreRadioEvent_28')
    assert arg_values(t_nav)[1:] == ['AA_Unit_01_Ground0', 'Quadruple', 'false'], arg_values(t_nav)
    for k, unit in enumerate(BOMBERS):
        ping = f'RE_SV_RaidPing_{k + 1:02d}'
        g.trigger('RE_Wave2_AreaB_PathSet', ping)                                  # a remote-event trigger
        g.execute(t_nav, ping, {1: unit})
    # (0.73.77, plan A7: "end the long tail") the round's last enemies pinged the same way: RE_SV_LastPing_NN on pool
    # flight NN, fired by Scripts/sv_rounds.lua tailTick when a round has had no kill for [rounds.tail] quiet_s with 1-4
    # of its aircraft left (a bomber flight's own RE_SV_RaidPing_NN); forwarded in co-op as the raid pings are
    assert '"RE_SV_LastPing_%02d"' in runtime_lua(), 'Scripts/sv_rounds.lua never fires RE_SV_LastPing_NN'
    for k, unit in enumerate(POOL):
        ping = f'RE_SV_LastPing_{k + 1:02d}'
        g.trigger('RE_Wave2_AreaB_PathSet', ping)
        g.execute(t_nav, ping, {1: unit})
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
    build_run_over(g, stock_ep)
    build_allies(g, flag, t_search, t_move, t_bsearch)
    build_amphib(g, flag, stock_ep)
    build_ladon(g, flag, stock_ep)
    build_alicorn(g, flag, stock_ep)
    build_spaceport(g, flag, stock_ep)
    build_tells(g)
    build_ace_moves(g, flag, stock_ep)
    build_review(g, stock_ep, t_search, t_engage, t_bmove)
    build_wolf(g, stock_ep, t_search, t_engage)
    build_director(g, stock_ep, t_search, t_engage)
    build_heavy(g, stock_ep)
    build_awacs(g, stock_ep)
    build_jammer(g, stock_ep)
    build_wraith(g)
    build_festival(g, flag, stock_ep)
    build_escort(g, flag, stock_ep)          # THE ESCORT and the ZFA-44 cargo ships (ESC_* / CARGO_* / ZFA_*)
    build_decoy(g, flag, stock_ep)           # THE DECOY (DECOY_*)
    build_tanicorn(g, stock_ep)              # THE TANICORN's test mount's engagement order (TANI_*)
    build_fleet(g, flag, stock_ep)           # THE INVINCIBLE FLEET's ships: orders and lanes (IF_*)
    return g


def build_heavy(g, stock_ep):
    """The heavies' routes (HEAVY_*), on Mission 16's Ladon path record and Mission 22's PathFinish trigger, as the
    Ladons': RE_SV_HeavyRoute_<NN><S> -> the lead's route; its end -> the loop; each loop's end -> the loop again;
    RE_SV_HeavyLoop_<NN><L><S> -> object L on the loop (the next lead when the one before is shot down)."""
    import re
    lua = runtime_lua()
    for fmt in ('"RE_SV_HeavyRoute_%02d%s"', '"RE_SV_HeavyLoop_%02d%s%s"'):
        assert fmt in lua, f'Scripts/sv_flights.lua never fires {fmt}'
    m = re.search(r'AIRFIELD = \{ X = ([-\d.]+), Y = ([-\d.]+) \}', lua)
    assert m and abs(float(m.group(1)) / 100000 - AIRFIELD_KM[0]) < 1e-6 and \
        abs(float(m.group(2)) / 100000 - AIRFIELD_KM[1]) < 1e-6, 'AIRFIELD_KM != Scripts/sv_core.lua AIRFIELD'
    m = re.search(r'ZONE = \{ X = ([-\d.]+), Y = ([-\d.]+), HALF = ([\d.]+) \}', lua)
    (zx, zy), half = ZONE_KM
    assert m and abs(float(m.group(1)) / 100000 - zx) < 1e-6 and abs(float(m.group(2)) / 100000 - zy) < 1e-6 and \
        abs(float(m.group(3)) / 100000 - half) < 1e-6, 'ZONE_KM != Scripts/sv_ai.lua ZONE'
    assert f'HEAVY_SECTORS = "{HEAVY_SECTORS}"' in lua, 'Scripts/sv_flights.lua HEAVY_SECTORS != HEAVY_SECTORS'
    m16 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission016', 'EP_Mission016_global.uasset')
    t_path = g.foreign_template(m16, 'LiveAIPathExecution', 'PathFinish_Ladon0_0', lambda a, e: a[0] == 'B_Obj_01_Air0_Ladon0')
    finish = '01_A_Air1_f18e_PathFinish'                   # PathFinish trigger template: {0 object, 2 path}
    objs = unit_objects(stock_ep, list(HEAVY_TRACKS))
    n = 0
    for H in heavy_routes():
        obs = objs[H['unit']][:BOMBER_SIZES[H['unit']]]
        g.trigger('RE_SpawnEnemy_kokatu_1st', H['ev'])                          # a remote event Lua fires
        g.execute(t_path, H['ev'], {0: obs[0], 2: H['path'], 4: HEAVY_SPEED})
        g.trigger(finish, f'SV_HeavyIn{H["n"]}{H["sector"]}', arg_changes={0: obs[0], 2: H['path']})
        g.execute(t_path, f'SV_HeavyIn{H["n"]}{H["sector"]}', {0: obs[0], 2: H['loop'], 4: HEAVY_SPEED})
        for j, ob in enumerate(obs):
            ev, lap = f'RE_SV_HeavyLoop_{H["n"]:02d}{chr(65 + j)}{H["sector"]}', f'SV_HeavyLap{H["n"]}{chr(65 + j)}{H["sector"]}'
            g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
            g.execute(t_path, ev, {0: ob, 2: H['loop'], 4: HEAVY_SPEED})
            g.trigger(finish, lap, arg_changes={0: ob, 2: H['loop']})
            g.execute(t_path, lap, {0: ob, 2: H['loop'], 4: HEAVY_SPEED})
        n += 1
    print(f'  heavies: {n} routes and loops ({len(HEAVY_SECTORS)} sectors x {len(HEAVY_TRACKS)} flights, '
          f'RE_SV_HeavyRoute_<NN><S> / HeavyLoop_<NN><L><S>, {HEAVY_SPEED} km/h)')


# The Spaceport Assault's map (docs/re/SPACEPORT_ASSAULT.md): the user's marks of 2026-10-31 (tools/re/spaceport/
# spaceport_marks.txt / spaceport_rings.txt: Ctrl+HOME beaches, Ctrl+PAGE_UP sea, Ctrl+PAGE_DOWN the troops' spots; hard
# rule 27), cm. The beaches' rings read sea (4 m) west and north of each, land (5 m) east and south: the craft come in
# from the west. Spaceport spots 3 and 4 were one double press (50 m apart): one kept.
SPACEPORT_BEACHES = [(-1512225, -20610, 500), (-1530847, 28330, 500), (-1557771, 95289, 500), (-1597594, 197576, 500)]
SPACEPORT_SEA = [(-2810707, 432930), (-2785643, 238488), (-2769543, 113592), (-2748663, -48395), (-2964629, -26491)]
SPACEPORT_TROOP_SPOTS = [(-1490317, 157461, 500), (-1484219, 75102, 500), (-1419829, -21557, 500)]
SPACEPORT_PAD = (-1325196, 59778)                # Mission 19's rocket 1 / Mission 22's shuttle pad

# Special round "Spaceport Assault" (docs/re/SPACEPORT_ASSAULT.md; user, 2026-10-31): an enemy fleet off the spaceport's
# west shore. Four amphibious groups on the first four sea marks (north to south), each a Wasp (Mission 28's
# AUnit01_Sea_0), two Aegis (Survival's copy of Mission 22's AC_Unit_01_Ship1) ahead of it either side of its lane and
# two missile boats (Training006's EA_UNIT_2_1) further in; and the carrier group on the fifth mark, the Gerald R. Ford
# (Mission 16's A_Unit_01_Ship0) in a ring of six Aegis: 14 Aegis in all (user: "put into the budget for 14 aegis
# ships"). Every ship is an enemy (Faction 2: no stock world data has an enemy Ford, Aegis or Wasp) on the enemy DT_NPC
# rows (SP_NPC_ROWS), boxed and TGT-marked, and holds its spot (no path). Each Wasp's lane runs from just ahead of it to
# the beach it faces (SP_WASP_BEACH: the northern-most Wasp to the northern-most beach); its landing craft (Mission 13's,
# as the airfield's assault) come in waves of two, SP_WAVES units a lane, so a wave can come every minute while the
# last ones are still on their way. Each craft that lands puts a BTR-90 ashore (invincible this round, no box) that
# drives to the troops' spot nearest its beach: Scripts/sv_spaceport.lua's capture meter counts the arrivals. After a
# captured spaceport, the retake round's garrison (SP_GARRISON: one unit of SP_GARRISON_N targetable BTR-90s a troops'
# spot) stands in for the troops.
SP_GROUPS = 'ABCD'                               # the Wasps' groups, on SPACEPORT_SEA[0..3]
SP_WASP_BEACH = {'A': 3, 'B': 2, 'C': 1, 'D': 0}  # each group's beach (SPACEPORT_BEACHES index)
SP_FORD_SEA = 4                                  # the carrier group's mark
SP_SHIP_Z = {'aegis': 300.0, 'wasp': 0.0, 'boat': 0.0, 'ford': 50.0}    # their sources' heights
SP_AEGIS_AHEAD_CM, SP_AEGIS_SIDE_CM = 150000.0, 45000.0    # a group's Aegis: ahead of the Wasp, either side of its lane
SP_BOAT_AHEAD_CM, SP_BOAT_SIDE_CM = 400000.0, 35000.0      # its missile boats
# each boat patrols its side of the lane, from SP_BOAT_AHEAD_CM to SP_BOAT_PATROL_CM ahead of the Wasp and back (the user's
# test of 2026-10-31: "the Missile Boats don't Partol Around Either"), at SP_BOAT_SPEED, on a Mission 22 ship lane's shape
SP_BOAT_PATROL_CM, SP_BOAT_SPEED, SP_BOAT_PATH_TEMPLATE = 900000.0, '90', '01_Ship1_grig_0_Path0'
SP_RING_CM, SP_RING_DEG = 180000.0, [30, 90, 150, 210, 270, 330]   # the carrier's Aegis (none dead ahead: a Wasp's there)
# (their turrets engage only inside it: 40 km round each ship, as far as their boosted search and missiles reach, SP_TURRETS)
SP_SHIP_AREA_M, SP_SHIP_ALT_M = 45000.0, (0.0, 15000.0)        # (2026-10-31: 40 -> 45 km)
SP_WAVES = 'VWXYZ'                               # a lane's craft units (letters: hard rule 17)
SP_CRAFT = 'LR'                                  # a wave's two craft, side by side
SP_CRAFT_GAP_CM = 18000.0
SP_LCAC_START_CM = 50000.0                       # the craft start this far ahead of their Wasp
SP_LCAC_SPEED = '220.0'                          # km/h (Mission 13's 180: ~12 km to the beach in about 3.3 minutes)
SP_TROOP_SPREAD_CM = 4000.0                      # the troops' spots: each arrival this far from the next
SP_GARRISON = 'ABC'                              # the retake's garrison units, one a SPACEPORT_TROOP_SPOTS spot
SP_GARRISON_N = 4
# The retake's rockets (docs/re/SPACEPORT_ASSAULT.md "Mission 19's rockets"; user, 2026-10-31: "can you please build the
# rockets this time?"): Mission 19's two rockets (E_Unit_05_Rocket_0: one on each pad, the second the shuttle's) as
# Survival's unit SV_Unit_SpRockets (objects SV_Obj_SpRocket_0 / _1, on the pads, invincible until launched), each on a
# whole copy of its Mission 19 climb (900 m up to 20.2 km: SV_Path_SpRocketA / B). Mission 19's split: the rocket's
# blueprint brings in its debris world-data objects BY THEIR EXACT NAMES (E_Obj_Rocket_Debri_Phase<N>_0 / _1) at its
# sockets when the last rocket of the unit is killed with its destroy spawner on; each stage's pieces the stage before's
# death brings in. Survival's three debris units hold them under those names (built as port_unit names a pair: base _0,
# base _1), at Mission 19's spot 500 m down, on copies of Mission 19's rows (no numeric tail: hard rule 17).
SP_ROCKET_SOURCE = ('/Game/Maps/Ingame/Mission019/WD_Mission019_global', 'E_Unit_05_Rocket_0')
SP_ROCKET_UNIT, SP_ROCKET_OBJ, SP_ROCKET_ROW = 'SV_Unit_SpRockets', 'SV_Obj_SpRocket', 'sv_sp_rocket'
SP_ROCKET_PATHS = [('E_Obj_03_Rocket_0_Path0', 'SV_Path_SpRocketA'), ('E_Obj_03_Rocket_1_Path0', 'SV_Path_SpRocketB')]
SP_ROCKET_SPEED = ('280.0', '280.0')             # its launch (Mission 19's 05_PhaseStart_2: speed, acceleration)
SP_ROCKET_AREA_M, SP_ROCKET_ALT_M = 30000.0, (0.0, 25000.0)
SP_DEBRIS = [  # (Mission 19's unit, Survival's unit, its objects' base name (exact), [(Survival's row, Mission 19's)])
    ('Rocket_Debri_Phase1_0', 'SV_Unit_SpDebriA', 'E_Obj_Rocket_Debri_Phase1',
     [('sv_sp_debri_a', 'Rocket_Debri_1_1'), ('sv_sp_debri_b', 'Rocket_Debri_1_2')]),
    ('Rocket_Debri_Phase2_0', 'SV_Unit_SpDebriB', 'E_Obj_Rocket_Debri_Phase2',
     [('sv_sp_debri_c', 'Rocket_Debri_2_1'), ('sv_sp_debri_d', 'Rocket_Debri_2_2')]),
    ('Rocket_Debri_Phase3_0', 'SV_Unit_SpDebriC', 'E_Obj_Rocket_Debri_Phase3',
     [('sv_sp_debri_e', 'Rocket_Debri_3_1'), ('sv_sp_debri_f', 'Rocket_Debri_3_2')]),
]
SP_ROCKET_ROWS = [(SP_ROCKET_ROW, 'Rocket')] + [r for d in SP_DEBRIS for r in d[3]]   # (Survival's, DT_NPC_Mission019's)
# The retake's island enemies (user, 2026-10-31: "on the spaceport retake, add more enemies around the island", their
# picks: air defences, armour, more aircraft, about 30; "do a building check so that no enemies spawn in buildings"):
# Mission 6's EXSAM site whole (its radar and four launchers in Mission 6's layout), its flak guns, Gecko SAMs and Shilka
# AA guns, Mission 7's T-90s and the BTR-90s, each unit another mission's enemy ground unit (port_unit: its first object
# for every spot, clone_first, but the site) on Survival's copy of its mission row; the spots from tools/spaceport_spots.py
# (the building check: every building and prop's box round the spaceport). Scripts/sv_spaceport.lua spawns them with the
# retake's garrison; the round holds until they're down.
M06_WD, M07_WD = '/Game/Maps/Ingame/MIssion006/WD_Mission006_global', '/Game/Maps/Ingame/Mission007/WD_Mission007_global'
SP_ISLAND_ROWS = {'/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission006': [('sv_isl_radar', 'exsamsr_common'),
                  ('sv_isl_exsam', 'exsam_MS06'), ('sv_isl_flak', 'flak_02'), ('sv_isl_sam', 'geck_common'),
                  ('sv_isl_aa', 'shil_common')],
                  '/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission007': [('sv_isl_tank', 't090_common')]}
SP_EXSAM_SITE = ((0.0, 0.0), (-9900.0, -5400.0), (5300.0, -9900.0), (-5300.0, 10000.0), (9900.0, 5200.0))   # (Mission 6's)
SP_ISLAND_AREA_M, SP_ISLAND_ALT_M = 20000.0, (0.0, 15000.0)     # (ground air defences engage only inside their unit's area)
SP_ISLAND_PADS = [(-1384043.4, -41260.8), (-1325196.1, 59777.7)]
SP_ISLAND_AD_CENTRE, SP_ISLAND_ARMOUR_CENTRE, SP_ISLAND_SITE_CENTRE = (-1354620.0, 9258.0), (-1465000.0, 70000.0), (-1440000.0, 60000.0)
SP_ISLAND_AD = ['aa', 'sam', 'flak'] * 4 + ['aa']          # the single air defences, in their spots' spread order


def sp_island():
    """The retake's island units: dict(unit, obj, kind ('ad' or 'armour'), src (world data, unit), rows, points (cm),
    yaw, clone_first), their spots picked by tools/spaceport_spots.py (the same every build)."""
    if hasattr(sp_island, 'done'): return sp_island.done
    import math
    import spaceport_spots as S
    avoid = SP_ISLAND_PADS + [p[:2] for p in SPACEPORT_TROOP_SPOTS]
    site = S.candidates(SP_ISLAND_SITE_CENTRE, 140000.0, avoid, SP_EXSAM_SITE)
    assert site, 'no clear spot for the EXSAM site'
    sx, sy = site[0]
    site_pts = [(sx + ox, sy + oy) for ox, oy in SP_EXSAM_SITE]
    ad = S.spread(S.candidates(SP_ISLAND_AD_CENTRE, 170000.0, avoid), len(SP_ISLAND_AD), 20000.0, site_pts)
    armour = S.spread(S.candidates(SP_ISLAND_ARMOUR_CENTRE, 170000.0, avoid), 12, 12000.0, site_pts + ad)
    tanks, apcs = sorted(armour[:8]), armour[8:]
    cx, cy = SP_ISLAND_AD_CENTRE
    face = lambda pts: math.degrees(math.atan2(sum(p[1] for p in pts) / len(pts) - cy, sum(p[0] for p in pts) / len(pts) - cx))
    by = lambda k: [p for p, kk in zip(ad, SP_ISLAND_AD) if kk == k]
    out = [dict(unit='SV_Unit_SpIslExsam', obj='SV_Obj_SpIslExsam', kind='ad', src=(M06_WD, 'EA_Unit_01_Ground_8'),
                rows=['sv_isl_radar'] + ['sv_isl_exsam'] * 4, points=site_pts, clone_first=False)]
    for unit, obj, kind, src, row, pts in (
            ('SV_Unit_SpIslFlak', 'SV_Obj_SpIslFlak', 'ad', (M06_WD, 'EA_Unit_01_Ground_4'), 'sv_isl_flak', by('flak')),
            ('SV_Unit_SpIslSam', 'SV_Obj_SpIslSam', 'ad', (M06_WD, 'EA_Unit_02_Ground_5'), 'sv_isl_sam', by('sam')),
            ('SV_Unit_SpIslAA', 'SV_Obj_SpIslAA', 'ad', (M06_WD, 'EA_Unit_01_Ground_6'), 'sv_isl_aa', by('aa')),
            ('SV_Unit_SpIslTankA', 'SV_Obj_SpIslTankA', 'armour', (M07_WD, 'ECUnit02_Ground_5'), 'sv_isl_tank', tanks[:4]),
            ('SV_Unit_SpIslTankB', 'SV_Obj_SpIslTankB', 'armour', (M07_WD, 'ECUnit02_Ground_5'), 'sv_isl_tank', tanks[4:]),
            ('SV_Unit_SpIslApc', 'SV_Obj_SpIslApc', 'armour', (M06_WD, 'EA_Unit_01_Ground_1'), LCAC_TROOP_ROW, apcs)):
        out.append(dict(unit=unit, obj=obj, kind=kind, src=src, rows=[row] * len(pts), points=pts, clone_first=True))
    for u in out:
        u['yaw'] = face(u['points'])
        u['points'] = S.with_z(u['points'])
        for x, y, _ in u['points']:                 # the building check, again on what's built
            c, mesh = S.clearance(x, y)
            assert c >= S.CLEAR_CM and S.on_land(x, y), (u['unit'], x, y, c, mesh)
    sp_island.done = out
    return out
SP_NPC_ROWS = [  # (DT_SV_NpcMission row, the Mission 22 row it's shaped like, the enemy DT_NPC row) - tools/build_survival.py
    ('sv_sp_wasp', 'aegs_common', 'VE023_wasp_01'),               # (no parts: the stock row as it is)
]
# The armed hulls on rows of their own (0.73.45; the user's test of 0.73.44: "im not being locked on by any of the aegis
# ships and the range updates etc we applied don't seem to be working": the Aegis VLS fired from 2.1 km, the boats' SAMs
# from 1.5 km, their stock 3 km lock-on): a ship's parts are spawned on the rows its hull's DT_NPC row names
# (ChildNPCId; hard rule 38's Ladon pods the same), not on their world data descs' rows, so the turrets flew their stock
# rows. Each hull's DT_SV_NpcRows copy names the turrets' (SP_TURRETS) in its ChildNPCId, as do the turrets' own copies
# (the Aegis's gun mount's artillery). (DT_SV_NpcMission row, DT_SV_NpcRows row, the stock DT_NPC row it copies)
SP_HULLS = [
    ('sv_fleet_aegishull', 'SV_Fleet_AegisHull', 'VE002_aegs_01'),
    ('sv_sp_boat', 'SV_Fleet_BoatHull', 'VE011_mslb_01'),
    ('sv_sp_ford', 'SV_Fleet_FordHull', 'VE004_grfd_01'),
]
# The turrets, on Survival's own rows (the user, 2026-10-31: "up the Activation Range and Targetting Range and Lifetime of
# ALL Ships currently at the Spaceport"): each turret's own DT_SV_NpcMission row (shaped as aegs_mk15) naming a
# DT_SV_NpcRows copy of its stock DT_NPC row, which Scripts/sv_allies.lua puts into DT_NPC at the main menu on fire control
# of its own as the STORE's ships' (<FCS>_SVA_Fleet, CFG.specials.spaceport.fcs: their search module, lock-on range, guns'
# reach, missiles' range and flight time); the stock rows stay as they are. Scripts/sv_spaceport.lua SPORT.FLEET_ROWS
# lists the DT_NPC rows (no digit at the end: hard rule 17).
SP_TURRETS = [  # (the part's row in its source world data, Survival's mission row, Survival's DT_NPC row, its stock DT_NPC
                # row: None for the Aegis's, which Mission 22's mission row names)
    ('aegs_mk15', 'sv_fleet_mk15aegis', 'SV_Fleet_Mk15Aegis', None),
    ('aegs_mk41', 'sv_fleet_mk41aegis', 'SV_Fleet_Mk41Aegis', None),
    ('aegs_mk45', 'sv_fleet_mk45aegis', 'SV_Fleet_Mk45Aegis', None),
    ('aegs_artillery', 'sv_fleet_artaegis', 'SV_Fleet_ArtAegis', None),
] + [(f'VE004_grfd_mk15_{p}_Ally_01', f'sv_fleet_mk15ford{p.lower()}', f'SV_Fleet_Mk15Ford{p}', f'VE004_grfd_mk15_{p}_01')
     for p in ('LB', 'RF', 'LF', 'RB')] + [
    ('VE011_mslb_sam_01', 'sv_fleet_samboat', 'SV_Fleet_SamBoat', 'VE011_mslb_sam_01')]
SP_TURRET_SHAPE = 'aegs_mk15'
SP_AEGIS_ROW = 'sv_fleet_aegishull'              # (SP_HULLS: VE002_aegs_01's copy, its turrets on SP_TURRETS' rows)
SP_WASP_SOURCE = ('/Game/Maps/Ingame/Mission028/WD_Mission028_global', 'AUnit01_Sea_0')
SP_BOAT_SOURCE = ('/Game/Maps/Ingame/Training006/WD_Training006_phase02', 'EA_UNIT_2_1')
SP_FORD_SOURCE = ('/Game/Maps/Ingame/Mission016/WD_Mission016_global', 'A_Unit_01_Ship0')
SP_AEGIS_SOURCE = 'AC_Unit_01_Ship1'             # Survival's own copy (Mission 22's)


def sp_lanes():
    """Each Wasp's lane: dict(group, sea (x, y), start (x, y), beach (x, y, z), spot (x, y, z), ux, uy, yaw, length)."""
    import math
    out = []
    for k, grp in enumerate(SP_GROUPS):
        sx, sy = SPACEPORT_SEA[k]
        bx, by, bz = SPACEPORT_BEACHES[SP_WASP_BEACH[grp]]
        dx, dy = bx - sx, by - sy
        d = math.hypot(dx, dy)
        ux, uy = dx / d, dy / d
        spot = min(SPACEPORT_TROOP_SPOTS, key=lambda p: math.hypot(p[0] - bx, p[1] - by))
        start = (sx + ux * SP_LCAC_START_CM, sy + uy * SP_LCAC_START_CM)
        out.append(dict(group=grp, sea=(sx, sy), start=start, beach=(bx, by, bz), spot=spot, ux=ux, uy=uy,
                        yaw=math.degrees(math.atan2(dy, dx)), length=math.hypot(bx - start[0], by - start[1])))
    return out


def sp_fleet():
    """Every ship of the fleet: dict(kind, key, unit, obj, point (x, y, z) cm, yaw, group), the Ford first."""
    import math
    out = []
    fx, fy = SPACEPORT_SEA[SP_FORD_SEA]
    fyaw = math.degrees(math.atan2(SPACEPORT_PAD[1] - fy, SPACEPORT_PAD[0] - fx))
    out.append(dict(kind='ford', key='', unit='SV_Unit_SpFord', obj='SV_Obj_SpFord', point=(fx, fy, SP_SHIP_Z['ford']),
                    yaw=fyaw, group='Ford'))
    aegis, boats = iter('ABCDEFGHIJKLMN'), iter('ABCDEFGH')
    for L in sp_lanes():
        (sx, sy), ux, uy = L['sea'], L['ux'], L['uy']
        out.append(dict(kind='wasp', key=L['group'], unit=f"SV_Unit_SpWasp{L['group']}", obj=f"SV_Obj_SpWasp{L['group']}",
                        point=(sx, sy, SP_SHIP_Z['wasp']), yaw=L['yaw'], group=L['group']))
        for kind, ahead, side, keys in (('aegis', SP_AEGIS_AHEAD_CM, SP_AEGIS_SIDE_CM, aegis),
                                        ('boat', SP_BOAT_AHEAD_CM, SP_BOAT_SIDE_CM, boats)):
            for sgn in (1, -1):
                key = next(keys)
                x, y = sx + ux * ahead - uy * side * sgn, sy + uy * ahead + ux * side * sgn
                name = 'Aegis' if kind == 'aegis' else 'Boat'
                s = dict(kind=kind, key=key, unit=f'SV_Unit_Sp{name}{key}', obj=f'SV_Obj_Sp{name}{key}',
                         point=(x, y, SP_SHIP_Z[kind]), yaw=L['yaw'], group=L['group'])
                if kind == 'boat':                    # its patrol, out along the lane and back
                    at = lambda d: (sx + ux * d - uy * side * sgn, sy + uy * d + ux * side * sgn, SP_SHIP_Z['boat'])
                    legs = [SP_BOAT_AHEAD_CM + (SP_BOAT_PATROL_CM - SP_BOAT_AHEAD_CM) * t for t in (0.0, 0.34, 0.67, 1.0)]
                    s.update(out_path=f'SV_Path_SpBoat{key}Out', back_path=f'SV_Path_SpBoat{key}Back',
                             out_pts=[at(d) for d in legs], back_pts=[at(d) for d in reversed(legs)])
                out.append(s)
    for deg in SP_RING_DEG:
        key = next(aegis)
        a = math.radians(fyaw + deg)
        out.append(dict(kind='aegis', key=key, unit=f'SV_Unit_SpAegis{key}', obj=f'SV_Obj_SpAegis{key}',
                        point=(fx + math.cos(a) * SP_RING_CM, fy + math.sin(a) * SP_RING_CM, SP_SHIP_Z['aegis']),
                        yaw=fyaw, group='Ford'))
    assert sum(1 for s in out if s['kind'] == 'aegis') == 14, 'the fleet has 14 Aegis'
    return out


def sp_craft():
    """One dict per landing craft (lane group g, wave w, craft c): its unit SV_Unit_SpLcac<g><w> (the wave's two
    craft), object, paths in and out, its troops' unit, drive path and flags."""
    import math
    out = []
    for L in sp_lanes():
        g, (sx, sy), (bx, by, bz), ux, uy = L['group'], L['start'], L['beach'], L['ux'], L['uy']
        tx, ty, tz = L['spot']
        for wi, w in enumerate(SP_WAVES):
            for k, c in enumerate(SP_CRAFT):
                side = (k - (len(SP_CRAFT) - 1) / 2.0) * SP_CRAFT_GAP_CM
                ox, oy = -uy * side, ux * side
                n = wi * len(SP_CRAFT) + k                    # its troops' place round the spot (a spiral: no two on one)
                a = math.radians(n * 137.5 + (ord(g) - 65) * 31.0)
                r = SP_TROOP_SPREAD_CM * math.sqrt(n + 0.5)
                out.append(dict(
                    group=g, wave=w, craft=c, k=k, unit=f'SV_Unit_SpLcac{g}{w}', obj_base=f'SV_Obj_SpLcac{g}{w}',
                    obj=f'SV_Obj_SpLcac{g}{w}_{k}', path=f'SV_Path_SpLcac{g}{w}{c}', back=f'SV_Path_SpLcac{g}{w}{c}Back',
                    troops=f'SV_Unit_SpTroops{g}{w}{c}', troop_obj=f'SV_Obj_SpTroops{g}{w}{c}',
                    flag=f'SV_SpLand{g}{w}{c}', land=f'SV_SpLanded{g}{w}{c}', up=f'SV_SpLcacUp{g}{w}',
                    drive=f'SV_Path_SpDrive{g}{w}{c}', troops_up=f'SV_SpTroopsUp{g}{w}{c}',
                    aflag=f'SV_SpAt{g}{w}{c}', at=f'SV_SpAtSpot{g}{w}{c}',
                    spot=(tx + math.cos(a) * r, ty + math.sin(a) * r, tz),
                    start=(sx + ox, sy + oy, LCAC_SEA_Z), beach=(bx + ox, by + oy, float(bz)),
                    yaw=L['yaw'], length=L['length']))
    return out


# Each ship's turrets, as the world data names them (build_survival.py retag_turrets / retag_parts / the Ford's own, and
# asserts it): a ship's parts need their own engagement orders, the hull's never reaches them (the user's first test
# of 2026-10-31: "only some of the ships are firing, none of their Anti Air is firing"; no SAM fired at all), as the
# Ladon's CIWS needed theirs (Mission 16's Default_RemoteEvent_20: Normal, PlayerFirst) and Mission 22 / 26 order each
# turret by name. The Wasps have none.
SP_AEGIS_PARTS = ['BP_VE002_aegs_mk15_Base', 'BP_VE002_aegs_mk41_Base', 'BP_VE002_aegs_mk45_Base',
                  'BP_VE002_aegs_mk45_Base_Artillery']
SP_FORD_PARTS = ['Mk15LB', 'Mk15RF', 'Mk15LF', 'Mk15RB']
SP_BOAT_PARTS = ['BP_VE011_mslb_sam']


def sp_parts(s):
    """Ship `s`'s (an sp_fleet entry) turret objects, as event args write them."""
    parts = {'aegis': SP_AEGIS_PARTS, 'ford': SP_FORD_PARTS, 'boat': SP_BOAT_PARTS}.get(s['kind'], [])
    return [f"{s['obj']}_{p}" for p in parts]


def sp_garrison():
    """The retake's garrison: (unit, object base, [points]) one a troops' spot."""
    import math
    out = []
    for key, (x, y, zz) in zip(SP_GARRISON, SPACEPORT_TROOP_SPOTS):
        pts = [(x + math.cos(math.radians(90 * k + 45)) * 6000.0, y + math.sin(math.radians(90 * k + 45)) * 6000.0, zz)
               for k in range(SP_GARRISON_N)]
        out.append((f'SV_Unit_SpGarrison{key}', f'SV_Obj_SpGarrison{key}', pts))
    return out


JAM_ECM_SLOT = 'WN_WEAPON_4'                   # the EA-18G's row: flares, gun, missiles, ECM (AB.L..IN's, hard rule 40)


def build_jammer(g, stock_ep):
    """The jammer's ECM pod (CFG.jammer.ecm; user, 2026-10-29: "the EA-18G never activated it's ECM": the AI never
    switches it on by itself, as AB.L..IN's needed RE_SV_GlitchEcm): RE_SV_JamEcm_NN fires JAM_ECM_SLOT on pool
    flight NN's lead (the jammer leads its flight), as build_director's salvos; Scripts/sv_ai.lua JAM.tick fires it
    every ecm_every_s while the jammer is up. Forwarded in co-op: each joiner's copy jams there too."""
    lua = runtime_lua()
    assert '"RE_SV_JamEcm_%02d"' in lua, 'Scripts/sv_ai.lua JAM.tick never fires RE_SV_JamEcm_NN'
    m19 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission019', 'EP_Mission019_global.uasset')
    t_fire = g.foreign_template(m19, 'LiveFireOneShotWeapon', '05_PhaseStart_4', lambda a, e: a[1] == 'E_Obj_00_Air0_rflm_0')
    probes = set(PROBE_UNITS.values())
    n = 0
    for k, unit in enumerate(POOL):
        if unit in probes: continue
        objs = POOL_OBJS.get(unit)
        assert objs, unit                                                        # (build_wd_global runs first)
        ev = f'RE_SV_JamEcm_{k + 1:02d}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_fire, ev, {0: JAM_ECM_SLOT, 1: objs[0]})
        n += 1
    print(f'  jammer: its ECM pod on {n} flights\' leads (RE_SV_JamEcm_NN, {JAM_ECM_SLOT})')


def build_spaceport(g, flag, stock_ep):
    """The Spaceport Assault (SP_*): each fleet unit's Mission 22 ship engagement order as it appears; each wave of
    landing craft as the airfield's assault (build_amphib, Mission 13's records): appearance -> each craft on its path
    in (SP_LCAC_SPEED) -> PathFinish (hard rule 1) -> SV_SpLand<g><w><c> = 1 (Scripts/sv_spaceport.lua puts its troops
    ashore) -> back out; the troops drive to their spot, its PathFinish sets SV_SpAt<g><w><c>. Remote events for Lua:
    RE_SV_SpLcacRemove<g><w>, RE_SV_SpTroopsRemove<g><w><c>, RE_SV_SpFleetRemove (every ship), RE_SV_SpGarrisonRemove."""
    m13 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission013', 'EP_Mission013_global.uasset')
    t_cpath = g.foreign_template(m13, 'LiveAIPathExecution', '02_ReinforcementAppearance',
                                 lambda a, e: a[0] == 'E_Obj02_02_Ship0_lcac_0')
    t_upath = g.foreign_template(m13, 'LiveAIPathExecution', '02_ReinforcementAppearance',
                                 lambda a, e: a[1] == 'E_Unit02_02_Ship0')
    t_exit = g.foreign_template(m13, 'LiveAIPathExitExecution', '02_LCAC_PathFinish_0')
    t_tpath = g.foreign_template(m13, 'LiveAIPathExecution', '02_Reinforce_tank_0',
                                 lambda a, e: a[0] == 'E_Obj02_02_Ground0_tank_0')
    t_tengage = g.foreign_template(m13, 'LiveAIEngagementOrder', '02_Reinforce_tank_0',
                                   lambda a, e: a[1] == 'E_Unit02_02_Ground0')
    t_remove = g.exec_template('LiveDestroyUnitExecution', 'Debug_Destroy_Shuttle')
    t_seng = g.exec_template('LiveAIEngagementOrder', 'UnitDamage_Enemy_Ship_Last1', lambda a, e: a[0].startswith('AC_Obj_01_Ship1'))
    assert arg_values(t_seng)[3] == 'Normal' and arg_values(t_tengage)[3] == 'EvadeOnly', (arg_values(t_seng), arg_values(t_tengage))
    m16 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission016', 'EP_Mission016_global.uasset')
    t_part = g.foreign_template(m16, 'LiveAIEngagementOrder', 'Default_RemoteEvent_20',
                                lambda a, e: a[0] == 'B_Obj_01_Air0_Ladon0_LCIWS')
    assert arg_values(t_part)[3] == 'Normal' and arg_values(t_part)[6] == 'PlayerFirst', arg_values(t_part)
    finish = '01_A_Air1_f18e_PathFinish'                   # PathFinish trigger template: {0 object, 2 path}
    fleet = sp_fleet()
    parts = 0
    for s in fleet:                                        # (fights whatever comes: Normal, as the STORE's ships)
        up = f"SV_SpShipUp{s['kind'].title()}{s['key']}"
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: s['unit']})
        g.execute(t_seng, up, {0: 'NoneSelect', 1: s['unit']}, delay=2.0)
        for p in sp_parts(s):                              # (and each turret its own: the Ladon's CIWS order)
            g.execute(t_part, up, {0: p}, delay=2.5)
            parts += 1
    # the missile boats' patrols (the STORE's ships' lane records, Mission 22's): out at once, back at its end, out again
    t_spath = g.exec_template('LiveAIPathExecution', 'RE_Wave01_Start', lambda a, e: a[0] == 'AC_Obj_01_Ship1_aegs_0')
    t_upath2 = g.exec_template('LiveAIPathExecution', 'RE_Wave01_Start', lambda a, e: a[1] == 'AC_Unit_01_Ship1')
    for s in fleet:
        if s['kind'] != 'boat': continue
        up = f"SV_SpShipUpBoat{s['key']}"
        g.execute(t_spath, up, {0: s['obj'], 2: s['out_path'], 4: SP_BOAT_SPEED}, delay=1.0)
        g.execute(t_upath2, up, {1: s['unit'], 2: s['out_path']}, delay=1.0)
        for ev, done, nxt in ((f"SV_SpBoatOut{s['key']}", s['out_path'], s['back_path']),
                              (f"SV_SpBoatBack{s['key']}", s['back_path'], s['out_path'])):
            g.trigger(finish, ev, arg_changes={0: s['obj'], 2: done})
            g.execute(t_spath, ev, {0: s['obj'], 2: nxt, 4: SP_BOAT_SPEED}, delay=1.0)
            g.execute(t_upath2, ev, {1: s['unit'], 2: nxt}, delay=1.0)
    # the round's fighters falling back when the spaceport is captured (Scripts/sv_spaceport.lua withdraw: the round can
    # end and the retake come; the user's test of 2026-10-31: "after the spaceport was captured, the next round didn't
    # start", six fighters still up): RE_SV_FlightOff_NN, Mission 22's own despawn on the pool flight's unit
    t_off = g.exec_template('LiveSetActiveGameObjectExecution', None, lambda a, e: a[0] != 'NoneSelect' and a[3] == 'false')
    for k, unit in enumerate(POOL):
        ev = f'RE_SV_FlightOff_{k + 1:02d}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        g.execute(t_off, ev, {0: 'NoneSelect', 1: unit, 2: 'NoneSelect', 3: 'false'})
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_SpFleetRemove')
    for s in fleet:
        g.execute(t_remove, 'RE_SV_SpFleetRemove', {0: 'NoneSelect', 1: s['unit'], 2: 'NoneSelect'})
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_SpGarrisonRemove')
    for unit, _, _ in sp_garrison():
        g.execute(t_remove, 'RE_SV_SpGarrisonRemove', {0: 'NoneSelect', 1: unit, 2: 'NoneSelect'})
    craft = sp_craft()
    waves = []
    for c in craft:
        if (c['group'], c['wave']) not in waves: waves.append((c['group'], c['wave']))
    for grp, w in waves:
        cs = [c for c in craft if c['group'] == grp and c['wave'] == w]
        up = cs[0]['up']
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: cs[0]['unit']})
        for c in cs:
            flag(up, c['flag'], 'Set', 0)
            g.execute(t_cpath, up, {0: c['obj'], 2: c['path'], 4: SP_LCAC_SPEED}, delay=0.5 + c['k'] * 1.5)
        g.execute(t_upath, up, {1: cs[0]['unit'], 2: cs[0]['path']}, delay=0.5)
        rm = f'RE_SV_SpLcacRemove{grp}{w}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', rm)
        g.execute(t_remove, rm, {0: 'NoneSelect', 1: cs[0]['unit'], 2: 'NoneSelect'})
        for c in cs:
            g.trigger(finish, c['land'], arg_changes={0: c['obj'], 2: c['path']})
            g.execute(t_exit, c['land'], {0: c['obj']})
            flag(c['land'], c['flag'], 'Set', 1)
            g.execute(t_cpath, c['land'], {0: c['obj'], 2: c['back'], 4: SP_LCAC_SPEED}, delay=LCAC_RETURN_S)
            g.trigger('01_E_AreaA_ReinforcementAppearance_0', c['troops_up'], arg_changes={0: c['troops']})
            flag(c['troops_up'], c['aflag'], 'Set', 0)
            g.execute(t_tengage, c['troops_up'], {1: c['troops']})
            g.execute(t_tpath, c['troops_up'], {0: c['troop_obj'], 2: c['drive'], 4: LCAC_TROOP_SPEED}, delay=0.5)
            g.trigger(finish, c['at'], arg_changes={0: c['troop_obj'], 2: c['drive']})
            flag(c['at'], c['aflag'], 'Set', 1)
            trm = f"RE_SV_SpTroopsRemove{grp}{w}{c['craft']}"
            g.trigger('RE_SpawnEnemy_kokatu_1st', trm)
            g.execute(t_remove, trm, {0: 'NoneSelect', 1: c['troops'], 2: 'NoneSelect'})
    # the retake's rockets (SP_ROCKET_*, SP_DEBRIS; Scripts/sv_spaceport.lua's rockets), on Mission 19's own records,
    # each fired from Lua by its remote event (Mission 19 drives them with PathPointReceive and object-destroy triggers:
    # hard rule 1, and Survival's objects carry no tags)
    m19 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission019', 'EP_Mission019_global.uasset')
    t_rpath = g.foreign_template(m19, 'LiveAIPathExecution', '05_PhaseStart_2', lambda a, e: a[0] == 'E_Obj_05_Rocket_0')
    t_rboost = g.foreign_template(m19, 'LiveAIPathExecution', '05_PathPoint_Rocket_0_0')
    t_attr = g.foreign_template(m19, 'LiveSetCommonAttribute', 'Debri_HUD', lambda a, e: a[1] == 'E_Obj_Rocket_Debri_Phase1_0')
    t_minh = g.foreign_template(m19, 'LiveSetMinHealthExecution', 'Debri_HUD')
    t_split = g.foreign_template(m19, 'LiveSetActiveOnDestroySpawnerEvent', '05_PhaseStart_1')
    assert arg_values(t_attr)[3:6] == ['true', 'false', 'TGT'], arg_values(t_attr)       # (shown, not invincible, TGT)
    assert arg_values(t_split)[1:3] == ['E_Unit_05_Rocket_0', 'false'], arg_values(t_split)
    assert arg_values(t_rpath)[2] == 'E_Obj_03_Rocket_0_Path0' and arg_values(t_rpath)[9] == 'true', arg_values(t_rpath)
    assert arg_values(t_rboost)[4] == '1000' and arg_values(t_rboost)[9] == 'false', arg_values(t_rboost)   # (on along it)
    rockets = [f'{SP_ROCKET_OBJ}_{k}' for k in range(2)]
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_SpRocketSplitOff')      # the retake's start: no split yet, the debris held
    g.execute(t_split, 'RE_SV_SpRocketSplitOff', {0: 'NoneSelect', 1: SP_ROCKET_UNIT, 2: 'false'})
    for _, _, obj, _ in SP_DEBRIS:
        for k in range(2):
            g.execute(t_minh, 'RE_SV_SpRocketSplitOff', {0: f'{obj}_{k}', 3: '1.0'})
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_SpRocketSplitOn')       # one rocket left: the last one breaks up
    g.execute(t_split, 'RE_SV_SpRocketSplitOn', {0: 'NoneSelect', 1: SP_ROCKET_UNIT, 2: 'true'})
    for (_, path), obj, L in zip(SP_ROCKET_PATHS, rockets, 'AB'):
        go = f'RE_SV_SpRocketLaunch{L}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', go)
        flag(go, f'SV_SpRocketEsc{L}', 'Set', 0)
        g.execute(t_attr, go, {0: 'NoneSelect', 1: obj, 2: 'NoneSelect', 3: 'true', 4: 'false', 5: 'TGT'})
        g.execute(t_rpath, go, {0: obj, 2: path, 4: SP_ROCKET_SPEED[0], 5: SP_ROCKET_SPEED[1]}, delay=0.5)
        boost = f'RE_SV_SpRocketBoost{L}'                                 # (Mission 19's at its first path point)
        g.trigger('RE_SpawnEnemy_kokatu_1st', boost)
        g.execute(t_rboost, boost, {0: obj, 2: path})
        esc = f'SV_SpRocketOut{L}'                                        # its climb's end: escaped
        g.trigger(finish, esc, arg_changes={0: obj, 2: path})
        flag(esc, f'SV_SpRocketEsc{L}', 'Set', 1)
        g.execute(t_attr, esc, {0: 'NoneSelect', 1: obj, 2: 'NoneSelect', 3: 'false', 4: 'true', 5: 'None'})
        g.execute(t_off, esc, {0: obj, 1: 'NoneSelect', 2: 'NoneSelect', 3: 'false'}, delay=1.0)
    for st, (_, unit, obj, _) in enumerate(SP_DEBRIS, 1):                # each stage targetable in turn
        ev = f'RE_SV_SpDebriTgt{st}'
        g.trigger('RE_SpawnEnemy_kokatu_1st', ev)
        for k in range(2):
            g.execute(t_attr, ev, {0: 'NoneSelect', 1: f'{obj}_{k}', 2: 'NoneSelect', 3: 'true', 4: 'false', 5: 'TGT'})
            g.execute(t_minh, ev, {0: f'{obj}_{k}', 3: '0.0'})
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_SpRocketRemove')
    for unit in [SP_ROCKET_UNIT] + [d[1] for d in SP_DEBRIS]:
        g.execute(t_remove, 'RE_SV_SpRocketRemove', {0: 'NoneSelect', 1: unit, 2: 'NoneSelect'})
    # the island's enemies: each unit fights as it appears (Normal, as the fleet's hulls), all of them taken off at the end
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_SpIslandRemove')
    for u in sp_island():
        up = 'SV_SpIslUp' + u['unit'][len('SV_Unit_SpIsl'):]
        g.trigger('01_E_AreaA_ReinforcementAppearance_0', up, arg_changes={0: u['unit']})
        g.execute(t_seng, up, {0: 'NoneSelect', 1: u['unit']}, delay=2.0)
        g.execute(t_remove, 'RE_SV_SpIslandRemove', {0: 'NoneSelect', 1: u['unit'], 2: 'NoneSelect'})
    lua = runtime_lua()
    for npc in [t[2] for t in SP_TURRETS] + [h[1] for h in SP_HULLS]:
        assert f'"{npc}"' in lua, f'Scripts/sv_spaceport.lua SPORT.FLEET_ROWS has no {npc}'
    for unit in [SP_ROCKET_UNIT] + [d[1] for d in SP_DEBRIS] + [u['unit'] for u in sp_island()]:
        assert f'"{unit}"' in lua, f'Scripts/sv_spaceport.lua has no {unit}'
    print(f'  spaceport assault: {len(fleet)} ships ({parts} turrets ordered: Normal, PlayerFirst), {len(waves)} landing '
          f'waves of {len(SP_CRAFT)} craft, {len(sp_garrison())} garrison units; the retake: 2 rockets, {len(SP_DEBRIS)} debris '
          f'stages, {sum(len(u["points"]) for u in sp_island())} island enemies in {len(sp_island())} units')


def survival_fname_plain(name):
    """True when name is stored whole as an FName (no numeric tail split off: hard rule 17)."""
    return fname(name) == ('name', name, 0)


def build_repair(g, stock_ep):
    """RE_SV_RepairAircraft: the player's aircraft back to full health (LiveRestorePlayerPlaneExecution, Training001's
    node: SetHealth(Max) and the armour pool refilled; docs/re/KILLS_HEALTH_DEATH.md). The airfield shop fires it."""
    tr = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Training001', 'EP_Training001_global.uasset')
    t_restore = g.foreign_template(tr, 'LiveRestorePlayerPlaneExecution')
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_RepairAircraft')
    g.execute(t_restore, 'RE_SV_RepairAircraft')


def build_run_over(g, stock_ep):
    """RE_SV_RunOver: a co-op run's end (Scripts/sv_down.lua: every player down, the host's "ro"; each game fires its
    own, Scripts/sv_coop.lua KEEP_EVENTS): Mission 15's LiveMissionFinishExecution MissionFailed, false, true (the retry
    menu, no debriefing, no save: docs/re/KILLS_HEALTH_DEATH.md 3, 4). A remote event Lua fires, no conditions."""
    m15 = os.path.join(os.path.dirname(os.path.dirname(stock_ep)), 'Mission015', 'EP_Mission015_global.uasset')
    t_fail = g.foreign_template(m15, 'LiveMissionFinishExecution', pred=lambda a, e: a[0] == 'MissionFailed')
    assert arg_values(t_fail) == ['MissionFailed', 'false', 'true'], arg_values(t_fail)
    lua = runtime_lua()
    assert '"RE_SV_RunOver"' in lua and '"^RE_SV_RunOver$"' in lua, 'Scripts/sv_down.lua never fires RE_SV_RunOver, or sv_coop.lua forwards it'
    g.trigger('RE_SpawnEnemy_kokatu_1st', 'RE_SV_RunOver')
    g.execute(t_fail, 'RE_SV_RunOver')


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


# ---------------------------------------------------------------- the parts (this file's docstring)
# Each imports every name above (from survival_events import *) and comes back here whole. A part already loaded on its
# own would come back empty: import survival_events, never a part.
for _part in ('survival_events_specials', 'survival_events_squads', 'survival_events_festival',
              'survival_events_escort', 'survival_events_fleet'):
    assert _part not in sys.modules, f'import survival_events (it loads its parts), not {_part} on its own'
del _part
from survival_events_specials import *   # noqa: E402,F401,F403  LCAC, Ladons, Alicorn, Anomaly, AB.L..IN, VALKA

# ---------------------------------------------------------------- the int flags (after the specials: their names)
KEEP_AT_START = {AIRFIELD_UNIT: None}                 # units spawned at mission start (name -> spawn point or None)
# SV_Alive / SV_Kills: diagnostics, logged by Scripts/main.lua. SV_Up_NN: 1 while pool flight NN is up (its orders
# came; main.lua's ordersTick checks it). SV_Shuttle*: Comona Defense (build_shuttle).
INT_FLAGS = (['SV_Alive', 'SV_Kills', 'SV_AirHits'] + [f'SV_Up_{k + 1:02d}' for k in range(len(POOL))]
             + ['SV_ShuttleRound', 'SV_ShuttleLaunched', 'SV_ShuttleLost', 'SV_ShuttleHits', 'SV_ShuttleNearSaid']
             + [f'SV_ShuttleDmg{c}' for c in 'ABC'] + ['SV_AnomalyUp']
             + ['SV_AllyAir' + u[-1] for u in ALLY_AIR_UNITS] + ['SV_AwacsAir']
             + [f'SV_LcacLand{lane}{c}' for lane, _, _ in LCAC_LANES for c in LCAC_CRAFT]
             + [f'SV_LcacRunway{lane}{c}' for lane, _, _ in LCAC_LANES for c in LCAC_CRAFT]
             + [f'SV_LadonRun{key}' for key, _, _ in LADONS] + ['SV_Beat', 'SV_ValkaUp']
             + [f'SV_LadonRage{key}' for key, _, _ in LADONS])
# (0.73.73) a Ladon's circuit legs flown, its appearance's once-a-spawn mark and its fires (build_ladon); VOID WATCHER
# 1's orbit legs flown (build_awacs)
INT_FLAGS += ([f'SV_Ladon{f}{key}' for f in ('Leg', 'Done', 'Seen') for key, _, _ in LADONS] + ['SV_AwacsLeg'])
# (0.73.78, G5) VOID WATCHER 1 sent home (Lua's RE_SV_AwacsHome) and its exit (1 begun, 2 flown: build_awacs)
INT_FLAGS += ['SV_AwacsHome', 'SV_AwacsOut']
# (the Spaceport Assault's: its craft's landing and arrival flags, its rockets' escapes)
INT_FLAGS += [c['flag'] for c in sp_craft()] + [c['aflag'] for c in sp_craft()]
INT_FLAGS += ['SV_SpRocketEscA', 'SV_SpRocketEscB']        # a rocket's climb finished: escaped (Scripts/sv_spaceport.lua)

from survival_events_squads import *     # noqa: E402,F401,F403  orders, ace moves, Wolf, director, tells, allies, AWACS
from survival_events_festival import *   # noqa: E402,F401,F403  GONE FISHIN', THE FESTIVAL (adds its flags)
from survival_events_escort import *     # noqa: E402,F401,F403  THE ESCORT, the cargo ships, THE DECOY (adds its flags)
from survival_events_fleet import *      # noqa: E402,F401,F403  THE INVINCIBLE FLEET's ships, names, formation, lanes
