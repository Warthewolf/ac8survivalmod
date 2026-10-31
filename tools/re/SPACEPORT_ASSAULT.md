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

## What the game has (research of 2026-10-31)
- Ships: VE004_grfd Gerald R. Ford (Missions 11, 16; mk15 turrets as child parts), VE002_aegs Aegis (Mission 22's are
  allied, Survival's ALLY ships copy them; enemy ones in Missions 4, 11, 16, 26, 27, 30), VE023_wasp Wasp (Missions 11,
  24, 26, 27, 28; no turret parts), VE011_mslb missile boat (Mission 24 and training; a SAM child part), VE014_lcac (the
  beach assault's, Mission 13's enemy ones).
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
