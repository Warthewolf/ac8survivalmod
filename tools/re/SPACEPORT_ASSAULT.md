# Spaceport Assault and Retake (special rounds, design of 2026-10-31; round 1 built in 0.73.38, untested)

The user's idea (2026-10-31): a defence-style special at the Comona spaceport. If the defence fails, the next round
is a second special, an offensive one to retake the spaceport while Mission 19's ("Moonlight and Shadows") two rockets
launch; if the defence succeeds (every enemy destroyed), that follow-up never happens and the next round is a normal
one. Their choices (the questions of the same day, all the recommended answers):
- the defence fails on a **capture meter**, as the airfield's beach assault: each troop vehicle that reaches the
  spaceport adds a share on the HUD, at 100 % the spaceport is captured;
- a rocket that **escapes** (reaches space) in the retake round: no round bonus and a zollar penalty for each, the run
  goes on;
- the **Gerald R. Ford carrier launches fighters** from its deck while it's afloat (as the Alicorn's deck launches);
- the enemy **ships still afloat carry over** into the retake round and must be destroyed too; the Wasps send no more
  LCACs once the spaceport is taken.

## Round 1: Spaceport Defence
- An enemy fleet WEST of the spaceport (the pad at x -13.25 km, y +0.60 km: tools/re/SPECIAL_ROUNDS.md 1), sizeable
  (user, 2026-10-31: "I want more Aegis Ships, I want the fleet to be sizeable, put into the budget for 14 aegis
  ships"). Counts, each a setting: a carrier group (1 Ford, 6 Aegis) and four amphibious groups (each 1 Wasp, 2 Aegis,
  2 missile boats): 27 ships, 14 of them Aegis, about 100 AI objects with their turret parts, and LCACs at 8 a minute.
  The most of any special so far: the build checks the frame rate and the Lua tick with the whole fleet up, and co-op's
  load (ships and parts are linked by key, never moved every frame).
- Each Wasp puts 2 LCACs on the water beside it every minute until it's sunk (no stock mission launches LCACs from a
  ship: they spawn on the water, tools/re/SPECIAL_ROUNDS.md 3); the missile boats escort them in. Each LCAC that reaches
  the spaceport's shore puts its troops ashore (the beach assault's BTR-90s, Mission 13's), who drive to the spaceport.
- The troops can't be destroyed in this round (invincible, no lock-on, no target box).
- Success: every enemy destroyed (the fleet, the LCACs, the round's aircraft) before the meter reaches 100 % -> the
  next round is normal. Failure: 100 % -> "SPACEPORT CAPTURED", the next round is the retake.

## Round 2: Spaceport Retake (only after a failed defence)
- The troops at the spaceport become targets (killable, boxed, TGT); the surviving ships stay (no more LCACs).
- Mission 19's two rockets (OP0058_crkt_01, unit E_Unit_05_Rocket: two objects on two pads, one of them the shuttle's
  pad) launch; the players chase them and shoot them down, and their debris (six units: OP0058_crkt_ABR_p1 / L_p1,
  BR_p2 / A_p2, R_p3 / B_p3; Mission 19's 03_Split_Debli splits a destroyed rocket, its debris then fall: the
  05_Freefalling_* volumes, Debri_HUD).
- A rocket that escapes: no round bonus, a zollar penalty each; the run goes on.
- The round ends when everything is destroyed (troops, rockets, debris, ships, aircraft).

## The ships (research of 2026-10-31, a survey of every stock WD; scratch script build/... scratchpad ships.py)
No campaign world data has an ENEMY Ford, Aegis or Wasp: every one is Faction 1 (allied) in Missions 4, 11, 16, 22,
25_2, 26, 27, 28, 30 (the "enemy users" below were wrong). DT_NPC has enemy (non-Ally) rows for each: VE004_grfd_01,
VE002_aegs_01, VE023_wasp_01, VE011_mslb_01 (models BP_VE004_grfd_CP, BP_VE002_aegs_CP, BP_VE023_wasp_CP,
BP_VE011_mslb_CP). So each enemy ship is an allied (or training) desc with Faction set to 2 (`('enum','ELiveFaction',
('raw','Byte',b''))`; no build helper sets it yet) on Survival rows naming the enemy DT_NPC rows. No desc of the four
references another export (hard rule 34: scanned).
- **Aegis**: flip Survival's own copy of Mission 22's AC_Unit_01_Ship1 (hull AC_Obj_01_Ship1_aegs_0, aegs_common ->
  VE002_aegs_01; parts BP_VE002_aegs_mk15_Base (aegs_mk15 -> VE002_aegs_mk15_01, class BP_VE002_aegs_mk15_01_CP),
  BP_VE002_aegs_mk41_Base (aegs_mk41 -> VE002_aegs_mk41_01, BP_VE002_aegs_mk41_CP), BP_VE002_aegs_mk45_Base (aegs_mk45 ->
  VE002_aegs_mk45_aagun_01, BP_VE002_aegs_mk45_CP) and its grandchild Artillery (aegs_artillery ->
  VE002_aegs_mk45_artillery_01, BP_VE002_artillery_CP); all four classes already imports of Survival's WD). ally_units'
  ship branch as it is plus Faction 2, Tags [] (unit and object), TargetMarkType 1, and rows that are NOT the allies'
  (sv_allies.lua boosts SV_Ally_Aegis / SV_Turret_*_Ally): Mission 22's stock rows or enemy copies. copy_unit keeps at
  most the source's one object: 14 Aegis = 14 units (or a helper growing the object list). The desc names no paths
  (Mission 22 sails ships by events): lanes from make_path. (Online Mode's FM_001 Aegis: DT_NPC_ON rows whose key
  VE002_aegs_01 collides with the campaign's: avoid.)
- **Ford**: only Mission 16's A_Unit_01_Ship0 / A_Obj_01_Ship0_grfd_0 (row VE004_grfd_Ally_01 -> VE004_grfd_Ally_MS16,
  the named ally Grindylow), four parts BP_VE004_grfd_mk15_01..04 (LB, RF, LF, RB; rows VE004_grfd_mk15_<pos>_Ally_01,
  classes .../VE004_grfd/CP/Ally/BP_VE004_grfd_mk15_0N_CP_Ally, imports -50..-53; DT_NPC pairs 01 with LF and 03 with LB,
  the WD the other way). Enemy rows VE004_grfd_01 with children VE004_grfd_mk15_{RF,LF,RB,LB}_01 (fire control
  VesselAAGun001_*), named by no stock mission row: Survival rows needed (POOL_EXTRA style; NPC_EXTRA rejects an NpcId
  ending in a digit). The enemy part classes BP_VE004_grfd_mk15_0N_CP are imported by no stock WD: a new helper adds the
  import (hash export_hash(short + '_C'), checked against Mission 16's four), or keep the _CP_Ally classes via import_from
  (an ally class on an enemy: unverified). port_unit(tgt=True) then retag_parts as the Ladon; the retag helpers assert no
  `_<digits>` tail and these parts end _01.._04: rename them (`<owner>_mk15_LF`) or relax the assert for leading-zero
  tails. Also Faction 2, bIsLanding / bShowCallSignForAlly / unit bIsEscortedUnit false. Area 5000 m, 500-12000 m.
  Deck-launch lead: Mission 16's path A_Obj_01_Ship0_grfd_0_Takeoff0 (two points at 24 m, ~620 m, AttachParentAIObjectName
  the Ford; an F/A-18 sent along it at 240 / 100): a copy needs the attach name changed. Survival's own deck launch
  (sv_alicorn.lua SPC.alicornDeck: a pool flight spawned with a pose off the hull's bow) is the simpler start.
- **Wasp**: no parts anywhere (VE023_wasp_01: no children, no fire control). Mission 28's AUnit01_Sea_0 /
  AObj01_Sea_0_0 (one object, no tags, wasp_Ally -> VE023_wasp_Ally_MS26_Dauntless; bIsInvincible and
  bIsAttackTargetsException set): port_unit as it is (hard rule 31) plus Faction 2, both flags false, a Survival row on
  VE023_wasp_01. Area 6000 m.
- **Missile boat**: only Training006's WD_Training006_phase02 EA_UNIT_2_1 (already Faction 2: EA_UNIT_2_1obj_0..2 on
  VE011_mslb_01, TargetMarkType 1; still, its events order EvadeOnly then Normal and fire the SAM, WN_WEAPON_1, at the
  Player), one part each BP_VE011_mslb_sam (row VE011_mslb_sam_01, class .../VE011_mslb/CP/BP_VE011_mslb_sam_CP,
  imported only by that phase package): port_unit + retag_parts with that package, as the Ladon's; rows by NPC_IMPORT
  (DT_NPC_Mission024 mslb_common / mslb_sam_common, or DT_NPC_Mission_Tr006); each copied object its own retag_parts.
  Area 12000 m, ceiling 9000 m. (Mission 24 has only the rows, no unit.)
- Not verified: what bIsLanding does; whether EnemySearchType matters; whether a part's WD row or DT_NPC ChildNPCId wins
  at spawn; an _Ally class on an enemy; that the BP_VE004_grfd_mk15_0N_CP packages exist (not extracted).

## Mission 19's rockets (research of 2026-10-31; blueprints pulled to the session scratchpad's bp/)
- **The split is the blueprints', not the events'**: each rocket / debris blueprint has a destroy system
  (LiveDefaultDestroySystemSpawnFromWD) that, at its final explosion, brings in world-data objects BY THEIR EXACT NAMES at
  the dying piece's socket and hides the parent. So Survival's WD keeps those names:
  rocket -> E_Obj_Rocket_Debri_Phase1_0 (ABR_p1, SOC_B) + _Phase1_1 (L_p1, SOC_L); ABR death -> _Phase2_0 (BR_p2, SOC_B)
  + _Phase2_1 (A_p2, SOC_A); BR death -> _Phase3_0 (R_p3, SOC_B) + _Phase3_1 (B_p3, SOC_R). L_p1 destroys itself 3 s on
  (a 1000-damage self timer). Debris (class LiveAIRocketWreck, inferred) fall by themselves, no paths, with per-difficulty
  fall settings, aimed at marks by name (ABR_p1 -> RocketDebri_FirstMark_0_*, BR_p2 / R_p3 -> LastMark_0_*, A_p2 / B_p3 ->
  LastMark_1_*, the base -> DefaultMarkActor0 at (-1358362, 6514, 6000), only in WD_Mission019_phase05); 25
  LiveSetFallTargetExecution records (RocketDebri_PhaseN_M_Volume_K) re-aim each piece mark ring by mark ring as it falls
  through the RocketDebri_Fall_Target volumes.
- The rocket blueprint sets bUseHandShakeInUnit: the two rockets share ONE debris set, so (inferred) only the last
  rocket killed splits. Survival spawns the debris units itself, so both rockets can split if the set is spawned again
  (old one taken off: hard rule 16) before the second dies, or the rockets launch staggered.
- Units (WD_Mission019_global): E_Unit_05_Rocket_0 (faction 2, tag Unit_Rocket_All), E_Obj_05_Rocket_0 at
  (-1384043.4, -41260.8, 7642.7) and _1 at (-1325196.1, 59777.7, 7676.2) (the shuttle's pad); rotation (90, 0, 180), TGT,
  HUD box, invincible, tags Obj_Rocket / Obj_04_HUD_OFF; row Rocket -> OP0058_crkt_01 -> BP_OP0058_crkt_CP, MaxHealth
  160. Rocket_Debri_Phase1_0 / 2_0 / 3_0: one unit a stage, two objects, at z -500 m, spawned at level start, tags
  Unit_Rocket_All / Unit_Rocket_Debri, objects Obj_Rocket_Debri (+ _Phase02 / _Phase03), no mark or box, MaxHealth 20.
- Launch: paths E_Obj_03_Rocket_0/_1_Path0 (ControlType 1, empty tube data) straight up from 900 / 750 m through 1.8, 6,
  14 and 20.2 km; Mission 19 starts them after its cutscene and speeds them up at path points (1000 km/h, accel 2.8 then
  1.7 / 1.8): PathPointReceive (hard rule 1). Survival: its own legs from the pad (the shuttle's proven launch records,
  or legs chained by PathFinish, ControlType 1, each started a little ahead: hard rule 2, one-shot: hard rule 3); the top
  leg's PathFinish (~14 km: the radio counts down to ~13 km) is the escape. Climb 1.8 -> 14 km ~70-110 s (to measure).
- Damage window: health 100 at start, MinHealth 75 and the missiles' homing offset until a player is within 8 km
  (Default_CheckDistanceEvent_6: MinHealth 0, homing back); the survivor of the first kill held at MinHealth 5 under
  6 km (05_ObjectDestroy_Rocket_*), 0 inside Rocket_Destructible_Volume0 (r 800 m, 6-16 km). The destroy spawner is off
  at phase start and on once the unit's last rocket is at 0 (LiveSetActiveOnDestroySpawnerEvent). Debris: Phase1 held at
  MinHealth 1 until Debri_HUD (33 s after the kill) gives it TGT and MinHealth 0; each stage's death gives the next its TGT
  and MinHealth 0 2.6-2.8 s on (05_ObjectDestroy_Debri_1 / _2). Counting: type 72 unit-count triggers (Survival's own
  UnitDamage_Ship_Destroy_0 is one); success = Unit_Rocket_All at 0.
- Failure in Mission 19: escape (F_PathPointReceive), debris reaching the ground (F_ObjectCrashedDestroy_0, type 71) or a
  rocket killed on the pad (00_Rocket_Failed_Volume0 -> VFX_BigExplosionN). Survival's: an escape is the penalty; debris
  on the ground just counts as destroyed (the user's design has no fail there).
- Copy list: the rocket unit (Survival's names fine), the three debris units under their exact object names (port_unit's
  digit-tail assert relaxed for these, tags kept or named in records), new pad paths (make_path),
  Rocket_Destructible_Volume0, the Fall_Target volumes, every RocketDebri_*Mark_* and DefaultMarkActor0 by name (volume
  classes are script imports: import_from), optionally the Rise / Down volumes and VFX_05_RocketSmoke0/1 /
  VFX_BigExplosion0/1 (BP_MO102 / BP_MO103 imports + container header: hard rule 7); seven DT_SV_NpcMission rows
  (Rocket, Rocket_Debri_1_1 .. 3_2). Events: the destroy spawner on / off, the MinHealth gating, Debri_HUD's TGT and
  MinHealth (from Lua, not a fixed 33 s), 05_ObjectDestroy_Debri_1 / _2, the 25 fall-target records, type 70 / 71
  triggers. Can't use: cutscene triggers (27, 28), PathPointReceive (2e), phase starts (4c), Mission 19's cameras /
  mission finish / radio (unless cloned into DT_SV_Radio).
- To test: one split per handshake; the booster flames without the cutscene; debris safe at -500 m; an escaped rocket
  destroyed with the spawner on would spawn debris at 14 km (switch it off first, or move it to Rocket_Delete0 as
  Mission 19's 04_05_Change); Debug_Rocket_PhaseStart_5 jumps a rocket 7500 along its path (for testing); whether volumes
  and marks need the WD trailer updated (only paths are proven not to).

## What the game has (research of 2026-10-31)
- Ships: see "The ships" above (VE014_lcac: the beach assault's, Mission 13's enemy ones).
- Rockets: Mission 19 (EP_Mission019_global: build/research/special/EP_Mission019_global.txt); its liftoff is a cutscene
  (IGC_Ms190020) then a path accelerated at a PathPointReceive (hard rule 1: never fires for us), so Survival launches
  them on its own paths (PathFinish chains, as the heavies').
- Shore data: Survival's coast marks are all by the airport (x 11-16 km); none at the spaceport, and hard rule 27 says
  a beach can only be traced with a player near it. The coast-mark test key is gone from the current runtime: it comes
  back (test only) for the user to mark the spaceport's shore.

## Build plan
1. Research (no build): each ship's world-data desc in its mission (child parts, turret blueprints to import: hard rule
   7, hard rule 31's port_unit only takes units without ChildAIObjectDescs); Mission 19's rocket chain (launch,
   split, debris, escape volumes) mapped onto Survival's events; the Alicorn deck launch for the Ford's.
2. The spaceport shore: a test-only mark key; the user flies the spaceport's coast and marks landing spots.
3. Round 1: the fleet units and lanes, the LCAC spawns per Wasp per minute, troops invincible, the capture meter, the
   success / failure branch, the Ford's deck launches.
4. Round 2: troops targetable, the rockets' launch, chase, split and debris, escape and penalty, ships carried over.
5. Co-op (the ships and parts linked as the Alicorn's and the landing craft's are; events forwarded), tests, build.

## Build 0.73.38-coop2mp.39 (round 1 and a first retake; built 2026-10-31, not yet run in game)
Steps 3 and part of 4 of the plan. Not in the special rotation yet (CFG.specials.rotation, the ini's): a dev install
forces it with **Ctrl+END** (the next round is the Spaceport Assault) and **Ctrl+INS** (a retake with test_troops 8 and
no ships); add `spaceport` to the rotation once a test has run it.
- The fleet (tools/survival_events.py sp_fleet, tools/build_survival.py spaceport_units): 27 one-ship units, every one
  an enemy (Faction 2, no tags, TGT and a box), holding its spot (no path), its unit area 25 km / 0-15 km (as the STORE's
  ships), Mission 22's Normal ship engagement order 2 s after it appears (SV_SpShipUp*):
  - the Ford SV_Unit_SpFord at the fifth sea mark (-29.65, -0.26) km facing the pad (3 deg): Mission 16's
    A_Unit_01_Ship0 on sv_sp_ford (VE004_grfd_01), its four Mk 15s SV_Obj_SpFord_Mk15<LB|RF|LF|RB> on
    sv_sp_ford_<lb|rf|lf|rb> (VE004_grfd_mk15_<pos>_01) with Mission 16's _CP_Ally part classes (import_from: an ally
    class on an enemy, unverified); bIsLanding, the callsign and bIsEscortedUnit off;
  - the Wasps SV_Unit_SpWasp<A-D> on the first four marks (north to south): Mission 28's AUnit01_Sea_0 on sv_sp_wasp
    (VE023_wasp_01), not invincible, not an attack-target exception;
  - 14 Aegis SV_Unit_SpAegis<A-N>: Survival's copy of Mission 22's AC_Unit_01_Ship1 on its own rows (aegs_common and its
    turrets' aegs_mk15 / mk41 / mk45 / artillery: VE002_*, the enemy rows), A-H 1.5 km ahead of each Wasp 450 m either
    side of its lane, I-N in a 1.8 km ring round the Ford (30, 90 ... 330 deg off its heading);
  - 8 missile boats SV_Unit_SpBoat<A-H>: Training006's EA_UNIT_2_1 (its first boat) on sv_sp_boat (VE011_mslb_01), its
    SAM part on sv_sp_boat_sam (VE011_mslb_sam_01), 4 km ahead of each Wasp 350 m either side.
- The landing craft: each Wasp's lane from 500 m ahead of it to the beach it faces (SP_WASP_BEACH), five waves V-Z of two
  craft (SV_Unit_SpLcac<g><w>, Mission 13's LCACs at 220 km/h, ~11.9 km); each craft its path in and out, its troops
  SV_Unit_SpTroops<g><w><c> (a BTR-90, invincible, an attack-target exception, no box) and their drive to the troops'
  spot nearest the beach (a spiral of spots 40 m apart round it). Records as the airfield's assault (build_spaceport).
- Lua (Scripts/sv_spaceport.lua, SPORT; CFG.specials.spaceport, survival.ini [specials.spaceport], .ships, .pay, .deck,
  .retake): the fleet spawned 3 ships every 0.5 s; each Wasp afloat sends its next free wave first_wave_s 20 after the
  fleet appears and every wave_every_s 60; a landing puts its troops ashore, their arrival adds capture_per_troop 5 %,
  they go in troop_stay_s 30 later (taken off: a wave's troops can come again), or are taken off troop_timeout_s 420
  after landing if they never arrive; a wave is taken off remove_after_s 60 after its first landing. 100 %: SPACEPORT
  CAPTURED, the craft out recalled, no more landings, the round ends with its aircraft (the ships stay afloat) and the
  next round is the retake (RUN.sport, sv_spawn.lua specialFor). Every ship sunk with nothing coming in: SPACEPORT
  HELD, reward 10000 + 300 x the round. Pay a ship by kind (Ford 3000, Wasp 1200, Aegis 800, boat 300) and 150 a craft.
  The round's fighters: fighter_share 0.5 of its aircraft (SPC.kinds budget). From round from_round 8.
- The Ford's deck (deck, as the Alicorn's): first_s 45 on, a free pool 2-ship every every_s 50 ahead_m 600 off its bow,
  alt_m 1100 up, flights 3 + 0.15 x the round (at most 8), max_up 2, none while you're down at the airfield (but in
  co-op while another player flies). The hull's position from its actor (checked valid each read), else ford_cm.
- The retake (kind "retake", only after a capture; .retake): the garrison (SV_Unit_SpGarrison<A-C>, 4 targetable
  BTR-90s each on a troops' spot, one unit per per_unit 4 troops that got in, 3 at most) and every ship still afloat from
  the assault (its deck too); the round ends when they and its aircraft are down: reward 12000 + 300 x the round,
  garrison_pay 300 a vehicle. **Mission 19's rockets are not in it yet** (step 4's chase, split, debris and escape).
- The rounds: SPC.kinds' new ready / busy / over / row hooks (sv_rounds.lua startRound and the fighting state, sv_hud.lua's
  NEXT row: FLEET: n SHIPS  LANDING CRAFT: n  SPACEPORT CAPTURE: n %), a special's from_round in specialFor's random picks.
- Co-op: every spawn goes through SV_Spawn with spawningUnit set (mirrored, ships and parts linked by key), the RE_SV_Sp*
  removals are forwarded to the joiners like every special's.
- Log lines: `special: round N, the Spaceport Assault: 27 ships coming in west of the spaceport`, `special: spaceport
  fleet: <kind> <unit>: 1 up` (27 of them), `special: the Wasp of group G sends landing craft SV_Unit_SpLcac<g><w>: 2 up`,
  `special: SV_Unit_SpLcac<g><w> craft <c> on the beach; troops ...: 1 up`, `special: troops ... reached the spaceport;
  N% captured`, `special: troops ... gone in; taken off`, `special: ... are away; taken off`, `special: spaceport fleet:
  <kind> <unit> sunk`, `special: round N, the spaceport is captured ...` / `... the spaceport held ...`, `special: the
  Ford's deck launch N: ...`, the retake's `special: the spaceport's garrison ...` and `special: round N, the Spaceport
  Retake: ...`.
- Test checklist (dev install, Ctrl+END in a run): the 27 ships appear west of the spaceport, red (enemy) with boxes and
  TGT marks, and fire at you; the Ford's four guns and the boats' SAMs fire; the craft leave the Wasps, land on the four
  beaches, their troops drive to the spaceport and the meter climbs; a sunk Wasp sends no more; fighters launch off the
  Ford's bow; sink the fleet -> SPACEPORT HELD; let it fall -> SPACEPORT LOST, the next round's garrison and the ships
  left; the frame rate and the perf line's Lua tick with the whole fleet up; in co-op the same on a joiner.
- Not known yet: whether the enemy Faction flip turns Mission 28's Wasp / Mission 16's Ford hostile (the HUD's colour, the
  turrets' fire); whether the Ford's _CP_Ally part classes fight for the enemy; whether ships with no path stay put;
  whether 1211 triggers (from 819) load; the frame rate with ~110 ship objects.

### 0.73.39 in game (the user's solo test, 2026-10-31 17:51-17:56, Ctrl+END in round 1)
- The fleet came up whole (27 ships: the Ford 5 objects, Aegis 5, boats 2, Wasps 1), the Wasps' waves left every 60 s
  on all four lanes, craft landed on the beaches 3.9 min after leaving (troops ashore), ships were sunk and paid.
- The user: "the enemy fleet doesn't seem to target the players very much, only some of the ships are firing, none of
  their Anti Air is firing either". The weapons log saw no launch by any ship in 5 minutes (5 weapon objects in all the
  pools: the fighters' missiles): no turret ever fired a missile.
- Cause: only each ship's hull had an order (Mission 22's unit-level Normal), and a hull's order doesn't reach its
  turrets: stock missions order every turret by name (Mission 22's AC_Obj_01_Ship2_aegs_0_BP_VE002_aegs_mk45_Base_
  Artillery, Mission 26's ..._aegs_mk41_Base), as the Ladon's CIWS needed theirs (code review of 2026-10-23).
- 0.73.40-coop2mp.41: every turret its own order 2.5 s after its ship appears (Mission 16's Default_RemoteEvent_20, the
  Ladon CIWS's: Normal, PlayerFirst): 68 (each Aegis's mk15, mk41, mk45 and its Artillery, the Ford's four Mk 15s, each
  boat's SAM; tools/survival_events.py sp_parts, the build asserts the names against the world data).
- The same log's fighters: their special weapons carried (2AAM, HCAA on the Su-33 / Su-47 / F-15E) but never fired in
  5 minutes while their standard missiles fired 21 times: the user's hunch about the enemies' specials (see AGENTS.md).
- The same test, the capture (17:59:29, 20 troop vehicles in): the craft were recalled, but the round never ended (user:
  "after the spaceport was captured, the next round didn't start"): six fighters were still up (the round's Su-47 pair
  and two pairs off the Ford's deck), and a round ends only with its aircraft down. And "the Missile Boats don't Partol
  Around Either": they held their spots by design.
- 0.73.41-coop2mp.42: at the capture the round's fighters fall back (sv_spaceport.lua withdraw: every pool flight up
  despawned by RE_SV_FlightOff_NN, Mission 22's LiveSetActiveGameObjectExecution false on its unit; off D.up, since a
  despawned unit can still read alive (the shuttle's read 1 once); its planes marked down, no pay; the round's queue,
  spares and later waves dropped; no more deck launches): `special: the round's fighters fall back with the capture: N
  flights (M aircraft) taken off: ...`; the round ends, its break, then the retake. Each missile boat patrols its side of
  its lane, 4 km to 9 km ahead of its Wasp and back (SV_Path_SpBoat<K>Out / Back on a Mission 22 ship lane's shape, the
  STORE ships' path records at 90 km/h, PathFinish to the other leg).
