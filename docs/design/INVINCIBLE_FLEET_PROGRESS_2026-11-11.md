# INVINCIBLE FLEET: progress review, 2026-11-11

A review of docs/design/INVINCIBLE_FLEET.md's work packages after the night of 2026-11-10/11 (0.74.50-0.74.60 in
HISTORY.md, and 0.74.61 in the working tree, not yet committed or run in game). For each package: where it stands, what
tonight's lessons change in it, what can be built without the user in game, and what needs a test first; then the
order for the next three sessions. The rise and GEOFON's damage model (WP4-WP6) are researched in
docs/design/INVINCIBLE_FLEET_RISE_FORD.md; this file only summarises them.

Tags as in docs/re: [V] read in a file, a dump or seen in game (where), [I] inferred, [?] not known yet.
The user's order of work stands (INVINCIBLE_FLEET.md 2): (1) the TANICORN fully working, (2) GEOFON's damage model and
the rise out of it, (3) the rest of the fleet.

---------------------------------------------------------------------------------------------------------------------
## 1. Tonight's lessons, and where each one lands
| # | lesson (where it was learnt) | what it changes |
|---|---|---|
| L1 | A turret part aims only when its bones carry the stock names `BN_Body` > `BN_turret_yaw` > `BN_turret_pitch` (0.74.59: with `turret_yaw` the barrel stood at rest) | every mount and every aiming part of ours, the TANACORN's and any cooked fleet part (RAVEN's EW mast if it's ours: WP14 route 2) |
| L2 | A part gets its muzzles only through its NPC row's fire control row (`NpcFCSId0`), and **that row's arm replaces the blueprint's** (0.74.58-0.74.60); the copy is a stock row with SlotNum = its muzzles, its speeds and arcs (SV_FCS_TaniT5) | each part type needs a stock row whose arm blueprint drives the mesh component, bones and socket prefix the part has, or the part rigged to that arm. The blueprint's own arm is inert once a row is named. Pick the rows first (a dump job), then rig |
| L3 | `bDirectEdit` + SlotNum in the blueprint's Performance does nothing (0.74.57) | don't spend a build on blueprint arm values |
| L4 | How a mount turns is the row's arm's (the stock flak arm: 360 deg/s, DoNotWhileFiring, "jumps around"); the copy's YawSpeed / PitchSpeed fix the speed (0.74.60: 40 deg/s) | tune turn speeds in the row copies (`fcs_speed`), per type |
| L5 | The weapon class decides where shots start: the vessel AA emitter is a stream hung where it's attached (the mount's foot), the flak gun a shell a shot (0.74.53, 0.74.56) | choose shell weapons for our mounts; an emitter only on a part whose attach socket is known good |
| L6 | **Drawn is not live** (0.74.60): the 32 parts on the hull are PoseableMeshComponents, with no AI object, health, box or fire control | WP2's live parts are LiveChildActorComponents with world-data child descs, ChildNPCId / ChildNPCComponentNames pairs and each part's own rows (with L2's fire control row); a socket that gets a live part loses its drawn one |
| L7 | A static mesh with sockets of ours loads and draws in AC8: SM_SV_Tani_HULL, 125k triangles, 36 sockets, every part drawn (0.74.60; TANICORN.md 4's open proof) | WP2's first risk is gone ("a static mesh with sockets of ours won't load": the plan's risk table) |
| L8 | Multi-second joint animations of ours come through the import (AS_SV_Tani_RAILCANNON_Deploy 3.333 s, AS_SV_Tani_RAILGUN_L/R_Deploy 4.0 s; build/tanicorn/ue_import.log, 2026-11-11 00:01, 0 warnings) | WP11's moving parts, and the two rigs of WP4 / WP5 (RISE_FORD.md 2.3, 4.2) |
| L9 | From Lua, locations read right, rotators don't (GetSocketRotation / GetBoneRotationByName: no Yaw; 0.74.55) | every angle a test logs is measured from two locations (the rise's pitch from bow and stern sockets) |
| L10 | Textures: our parts sit on AC8's gear material (MI_PP0016_x40a_Gear as parent) with ordinary textures (hard rule 44); the Alicorn's sheets now at 4096 (tools/tanicorn/alcn_textures.py, new tonight); lattice cut-outs draw solid (the gear material has no opacity: 4 NOTEs in ue_import.log) | WP0's look; a masked parent if AC8 has one that fits, else the lattices stay solid |
| L11 | Research (RISE_FORD.md): the Ford's meshes are Nanite (only a 2,483-triangle fallback dumps); it has no damage stages; AC8 breaks the Alicorn's wreck as a 3-bone skeletal mesh with a 60 s animation; the submarine class isn't used by any stock blueprint | WP5 without a cooked Ford blueprint; the V-break; the rise rig; the class question decoupled from the rise |

---------------------------------------------------------------------------------------------------------------------
## 2. Package by package

### WP0. The model
- **Now:** the model done through rev 4 and its audits; the UE route runs on the machine (0.74.50: 14 parts, CHECK ALL OK,
  0 warnings, TaniBuild 0 errors, SurvivalMode_Tani_P cooked); 0.74.61 (working tree) adds RAILCANNON, RAILGUN_L / _R with
  their Deploy animations and wrecks (17 parts in build/tanicorn/parts.json), drawn stowed on the hull, and the 4096
  Alicorn textures. Rev 4's review by the user: still open.
- **Tonight changes:** WP0's deliverable "a one-piece skinned version of the whole ship with a root bone for the rise" is
  no longer needed: a 3-bone rise rig replaces it (part `RIG`), and WP5 needs a break rig (`GEOWRECK`) and a stub of the
  stock wreck mesh at its path (RISE_FORD.md 4.1, 4.2c). Every aiming part keeps L1's bone names (export_tanacorn.py TB_*).
- **Left:** the core (Mount_CORE has no part), the hull's destroyed mesh for WP11's death, the lattices' opacity.
- **Without the user:** RIG and GEOWRECK in export_tanacorn.py / check_export.py / ue_import.py, built on this machine.
  **Needs a test:** the look of every revision (the user's review).

### WP1. The mounts
- **Now:** the 5-inch T5 is solved [V: 0.74.59-0.74.60]: it tracks at 40 deg/s and fires flak from both barrels' tips,
  on the stock bone names and its own fire control row SV_FCS_TaniT5 (from NPC_FCS_FlakGun000). 0.74.61 (Ctrl+U, not yet
  run) puts the T16, CIWS and LASER test mounts on stock rows: T16 on NPC_FCS_VesselArtillery000 (artillery shells,
  30 km, **not railgun shells yet**), CIWS on NPC_FCS_VesselCIWS000, LASER on the CIWS row too (a placeholder: no stock
  arm fires a laser). Hits on our mounts haven't been seen (the T5's health stayed 400 in 0.74.51) [V].
- **Tonight changes:** L2 decides the order of work: for each remaining type, find the stock row first, then rig.
  - **T16, railgun shells:** the stock railgun arm (BP_FCS_StrafingRailgun_00, the GR036 main cannon) drives
    `PM_Cannon`'s `BN_turret_pitch_01` / `_02` (0.74.61's notes): rig the T16 to it (a PoseableMesh named PM_Cannon, the
    pitch bones named so, SlotNum 3) or find a TripleRailCannon row [?]; the minimap / RAILGUN WARNING by hard rule 45.
  - **LASER:** AC7's LaserInterceptor on ALiveLaserInterceptor attached at the mount's muzzle, driven as the ZFA-44s'
    (sv_escort_li.lua, `li_intercept_s` 0.5 since 0.74.49) [V for planes], with the mount itself on a CIWS-shaped row for
    its aim; or an arm with BP_SwingTLS_ForMSL [?].
  - **VLS (deck and side):** the Aegis Mk 41's row and its arm's mesh component and prefix (our cells are SOC_Vls_01..08,
    the Mk 41's spelling [V: TANICORN.md 3]); the lids' Open animation exists (AS_SV_Tani_VLS*_Open 0.5 s) but nothing
    plays it [?: a hatch component or LiveAISimpleAnimation]; the side blocks' canted cells (homing_delay_s).
- **Without the user:** the stock-row dumps for VLS, railgun and laser (machine), then the rigs and rows (export, spec,
  sv_tanicorn.lua's TANI.mounts). **Needs a test:** each type firing from its muzzles, hits, wrecks.

### WP2. The hull
- **Now:** its first step done [V: 0.74.60]: BP_SV_Tani_HULL on ALiveAIGroundVehicleObject, HullMesh with 36 sockets, every
  part drawn, spawned through Survival's rows (SV_Unit_TaniHull, health 5000, name TANACORN), Ctrl+Y. Another session is
  rewriting WP2's section of the plan tonight: read it before working here.
- **Tonight changes:** L6 (live parts are a different thing from drawn ones); L7 (the static-mesh risk is gone).
  Put the rise rig into the hull blueprint now (RootComponent > RiseRig > HullMesh > parts), before the live parts go
  in, so every later test runs on the final layout (its saved position is the rest pose: Ctrl+Y unchanged). The class:
  the rise no longer needs the submarine class (RISE_FORD.md 2.5); what needs testing is whether the hull **sails a
  path** on its class (one path record on SV_Unit_TaniHull), else ALiveAIVessels.
- **Without the user:** the live-part data (world-data child descs, ChildNPCId pairs, part rows) for the T5s first;
  the rig in the blueprint. **Needs a test:** live parts spawning with the hull, boxed with their own health; sailing.

### WP3. The TANACORN fights
- **Now:** not started (needs WP2's live parts).
- **Tonight changes:** every part its own order by name (the T5's test record: Normal, PlayerFirst [V]); turn speeds per
  type in the rows (L4); 128 VLS cells fire in turns (the plan's salvo note).
- **Without the user:** the order records per part (generator). **Needs a test:** a whole fight, the weapons log.

### WP4. The rise
- **Now:** researched (RISE_FORD.md): **route B2, the rise rig**: a 3-bone skeletal driver of ours in the hull blueprint,
  HullMesh on its hull socket, one 20 s AnimSequence (bow out at 3 s, ~60 deg and the bow at ~540 m at 9.5 s, the hang,
  the fall, the slam at 17.6 s, the bounce), started from Lua (VALKA's calls); the cinematic on the rig's camera socket
  (a camera actor and the view target, as co-op's spectator view); the player invincible on the loiter autopilot.
  Route A (the submarine's surface curves) is an optional probe; route C (the runtime moving it each frame) the fallback.
- **Without the user:** all of it (export, import, spec, Lua with Ctrl+R). **Needs a test:** T3.

### WP5. GEOFON's damage model
- **Now:** researched (RISE_FORD.md 1, 4.2): the stock Ford (BP_VE004_grfd_Base on ALiveAIVessels) has no damage stages;
  its death is a mesh swap, 66 effects over 69 s and an 80 s slow sinking. **Stages from Lua** on the stock Ford (AC8's
  vessel fires and smoke attached, its own _DAM instances on the live slots, a list), no cooked Ford blueprint. **The
  V-break**: two copies of the stock Nanite wreck mesh pitched +25 / -15 deg so the other half of each is under the
  opaque sea, parting to ~215 m and sinking, on a break rig of ours.
- **Without the user:** T1 / T2's Lua (Ctrl+B, Ctrl+G) in a new test-only part sv_fleet.lua; the break rig on the
  machine. **Needs a test:** T1, T2, T4.

### WP6. The rise between the halves
- **Now:** planned (RISE_FORD.md 4.3): the TANACORN spawned hidden under GEOFON at 25 % health, the rise 18 s into the
  break across the keel line, the order hidden -> visible -> firing -> targetable, the host's `tr` message, its path
  from a family built along GEOFON's lane.
- **Without the user:** the Lua sequence and its offline test (event order). **Needs a test:** T5, then co-op (two dev
  installs).

### WP7. The fleet
- **Now:** not started. The Spaceport's builder and Lua (sp_fleet, spaceport_units, SPORT.shipObjs, the per-turret
  orders, the deck) are what it generalises; the names route is proven (a model row copy with its own
  GameObjectDisplayName01: the ZFA-44, 0.74.11) [V].
- **Tonight changes:** the fleet's ships are stock blueprints on Survival's fire control row copies (SP_TURRETS'
  `<FCS>_SVA_Fleet`), which fire [V: 0.73.40-0.73.52]: L1 and L2 don't apply to them, only to parts of ours. The
  TANACORN's path after the rise needs a path family along GEOFON's lane (WP6), built with the lanes.
- **Without the user:** the builder generalisation with spaceport_test.sh passing, the names, the formation and the
  lanes (generator), the deck's random carrier jets (Lua). **Needs a test:** the fleet sailing in formation, firing,
  the frame rate.

### WP8. Damage textures at all times
- **Now:** step 1 begun tonight [V: dumps / name maps]: the Ford's live slots are MI_VE004_grfd_01..03 on
  MP_Live_Vehicle_Base, itself an instance of M_Live_Vehicle_Base overriding only Ice_* / Wet_* / Fresnel and the
  textures. **M_Live_Vehicle_Base carries the damage function**: static switches USE_DamagedFunction and Use_Charred,
  the scalar PlayerPlane_Damage, DamagedBasecolor_*, DamegedNormal_Intencity, Charred_*, Blend_Damaged_*, functions
  MF_Live_DamageCharred / MF_Live_DamegedBlend. The wreck's MI_VE004_grfd_0N_DAM sit on MP_Live_Vehicle_Base_Dameged with
  their own static permutation (the switches on) and Nornir's damage mask.
- **Tonight changes:** route M (a dynamic copy of the live slot with PlayerPlane_Damage up) works only if the live
  permutation has the damage function compiled in, which a static switch decides and a dynamic instance can't change
  [I]: the step-1 probe answers it. Route D (the _DAM instance, or a dynamic copy with Charred_Embers_Brightness and
  DamagedBasecolor_Alpha_Mul turned down for "scarred, not burning") is the likely route for the Ford; the other classes
  (Aegis, Mission 22's hulls, the boats, the container ship) still to dump.
- **Without the user:** the remaining classes' material dumps (machine), SCARS.apply in Lua with its skip list.
  **Needs a test:** the probe (one Aegis's and the Ford's slots with PlayerPlane_Damage 1, side by side with the _DAM
  route), then screenshots.

### WP9. The fleet's weapons
- **Now:** partly there [V]: fleet flak (VesselAAGun on the flak fire control), the Aegis Mk 41 and Ladon / Alicorn VLS
  with EXSAM homing and salvos (0.73.52-53); AC7's laser interceptors on the ZFA-44s at a 0.5 s swing (0.74.31, 0.74.49).
- **Tonight changes:** a laser mounted on a stock ship is the ZFA-44 route (spawned and attached at a socket) [V for
  planes, I for ships]; on the TANACORN it's WP1's laser mount.
- **Without the user:** the fleet's laser placement (Lua), RAVEN's jammer slot data. **Needs a test:** each weapon type in
  the weapons log, a survivable railgun.

### WP10. The round
- **Now:** not started. In place [V]: the two tracks' lengths in sv_music.lua (265,832 / 300,113 ms), the fixed-round
  schedule mechanism (rounds 2 / 6 / 9), the Spaceport's hooks (ready / busy / over / row), the airfield's repair.
- **Without the user:** sv_fleet.lua's round (a whole TEST ONLY part: WP12's lock 2), CFG.specials.fleet and
  survival.ini [specials.fleet], the subtitles drafts (`python -I tools/subtitles.py merge`), fleet_test.sh.
  sv_config_specials.lua is at 1,944 of size_check's 2,000 lines (and sv_escort.lua at 2,000): CFG.specials.fleet goes in a
  new piece of the sv_config family (tools/lua_split_part.py's way), not into sv_config_specials.lua.
  **Needs a test:** a whole round 30.

### WP11. Moving parts, phases, death
- **Now:** the bow railcannon's (3.333 s, the Alicorn's own length) and sub-railguns' (4.0 s) Deploy animations exported
  and drawn stowed (0.74.61); no blueprints, no fire control.
- **Tonight changes:** L8 (the animations import); playing them: the same Lua calls as the rigs (SetPosition / Play) on
  the part's mesh, or LiveAISimpleAnimationComponent + LiveAISimpleAnimationPlayExecution (Mission 25_2 / 30) [?];
  their fire control by L2.
- **Without the user:** the parts' blueprints and rows, phase logic in Lua. **Needs a test:** each part deploying and
  firing; the phases.

### WP12. Co-op, load, the STORE, release
- **Now:** lock 1 in place [V: tools/package_release.sh drops SurvivalMode_Tani_P]; locks 2 (round 30's Lua test-only)
  and 3 (round 30 only when the TANACORN's class loads) come with WP10. Co-op checks of round 30 need two dev installs.
- **Without the user:** the locks and their check in fleet_test.sh.

### WP13. The shelling
- **Now:** not started; the scripted route exists [V: AF.pending, the heavies' bomb runs, the festival's impacts].
- **Without the user:** all of the scripted route and its offline test. **Needs a test:** the gun line, the airfield bar.

### WP14. GEOFON's capture (co-op only)
- **Now:** not started.
- **Tonight changes:** GEOFON stays the stock blueprint (WP5), so the deck's landing marks are offsets from its root (its
  mesh has six sockets, none on the deck [V]); RAVEN's EW mast route 1 (the Alicorn's ECM part in a slot) is a stock part,
  L1 / L2 don't touch it.
- **Without the user:** capture_test.sh and the Lua; the native takeover in flight_test.sh. **Needs a test:** the solo pin
  test first, then two linked dev installs.

---------------------------------------------------------------------------------------------------------------------
## 3. What can be done without the user, and what can't
Three kinds of work (this session runs on the user's Windows machine, so builds can run while the game is closed;
installing over the user's install follows AGENTS.md: a new version, subtitles.py diff first, a backup):
- **Repo only** (Lua, Python, docs; the offline checks: lua_check.py, size_check.py, the *_test.sh): sv_fleet.lua as a
  TEST ONLY part (GEOFON's stages and break, WP6's sequence, later WP10's round), fleet_test.sh, CFG.specials.fleet,
  the subtitles drafts, WP13's scripted shelling, WP14's capture logic, WP7's builder generalisation (its Lua side and
  spaceport_test.sh), the plan file's status lines.
- **This machine, no user** (UE 5.4, Blender, the dumper, build_all.sh, package_dev.sh): tools/tanicorn's new parts (RIG,
  GEOWRECK) and blueprints, the stock-row dumps for WP1's mount types, WP8's material dumps, every build.
- **The user in game:** every test: Ctrl+U (0.74.61), T1-T5 (RISE_FORD.md 5), the live parts, the fight, the fleet.

---------------------------------------------------------------------------------------------------------------------
## 4. The next three sessions
**Session 1 (the user's next test window): finish the mount types' groundwork, and put the rise and the break's look in
the same build.**
1. Commit 0.74.61 (Ctrl+U's mounts, the deploying parts, the textures) once its session is done with it; the user tests
   Ctrl+U and Ctrl+Y.
2. Without the user, before the next build: dump the stock fire control rows and their arms for the VLS (the Aegis
   Mk 41's), the railgun (BP_FCS_StrafingRailgun_00's PM_Cannon and pitch bones) and any laser-capable arm, and write
   down per mount type which row and which rig (L2) in TANICORN.md.
3. Without the user: the rise rig (RISE_FORD.md 4.1: the RIG part, RiseRig in BP_SV_Tani_HULL, Ctrl+R with the
   cinematic) and T1 / T2's Lua (Ctrl+B, Ctrl+G in a new test-only sv_fleet.lua).
4. One dev build (bump_version.py first), installed when the game is closed. Tests: Ctrl+U, Ctrl+R (T3), Ctrl+B (T1),
   Ctrl+G (T2). T1-T3 cost WP1 nothing: they ride along.

**Session 2: the TANACORN fights (priority 1).**
1. WP1 from session 1's results: the T16 on the railgun arm, the laser mount, the deck and side VLS on their rows with
   their lids.
2. WP2's live parts on the rig-parented hull: the six T5s first (world-data child descs, ChildNPCId pairs, rows),
   then every type; one path record to see the hull sail.
3. WP3: each part's order; a fight against the user, the weapons log.

**Session 3: GEOFON falls and the TANACORN rises (priority 2), and the fleet starts.**
1. WP5: the break rig (GEOWRECK, the stock wreck mesh's stub) and sv_fleet.lua's stages and break from T1 / T2's answers;
   T4.
2. WP6: the pre-spawn, the rise between the halves, the cinematic on every game; T5 (and co-op with two dev installs
   when they're available).
3. In parallel (repo): WP7's builder generalised with GEOFON, RAVEN and the four Aegis named; WP8's probe in the same
   build.

---------------------------------------------------------------------------------------------------------------------
## 5. For the plan file (INVINCIBLE_FLEET.md), when its session is done with it
Status lines to take over: WP0 (rev 4 built through the cook; 17 parts; RIG and GEOWRECK to add; the skinned stand-in
dropped), WP1 (T5 solved; T16 / CIWS / LASER on stock rows in 0.74.61; the rest by L2), WP2 (first step done; rig first;
sailing test), WP4 (route B2), WP5 (Lua stages, the V-break), WP6 (pre-spawn, timeline), WP8 (step 1 begun), WP11 (Deploy
animations exported). The risk table: drop "a static mesh with sockets of ours won't load" (L7) and "the surface curves
can't overshoot" (the rise no longer uses them); add RISE_FORD.md section 6's.

Questions for the user (RISE_FORD.md 7, each with the recommended answer): the hull's class now that the rise doesn't
need the submarine class (keep the proven one, the ships' class if it won't sail: yes); GEOFON's break shown as a V of the
stock wreck mesh (yes); the rise's ~20 s shot from off the TANACORN's beam (yes, tuned after T3).
