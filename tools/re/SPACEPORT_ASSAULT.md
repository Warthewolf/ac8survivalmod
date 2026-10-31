# Spaceport Assault and Retake (special rounds, design of 2026-10-31; nothing built yet)

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
