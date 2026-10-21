# Survival Mode: build plan

Work top to bottom. Each milestone is one test build. Commit after each one works in-game.
Owner: CC = Claude Code, CX = Codex. Never work on the same files at the same time.

## Milestone 0: setup (CC)
- [x] Unzip the Stonehenge Returns source into `source/stonehenge/` and read its Tools notes.
- [x] Confirm the build script repacks an unchanged copy of Stonehenge Returns and it still loads in-game.
  (The repack check is done; its Stonehenge-only tools were removed 2026-10-20 when Survival became fully independent.)
- [x] Create `mod/` for Survival Mode's own files. Never edit files under the game install or E:\AceComba8EXPORTS.

## Milestone 1: main menu entry + fly at Comona (CC) - DONE 2026-10-20
Goal: pick "SURVIVAL MODE" on the main menu, choose a difficulty, go through the hangar, sortie and spawn in the air
over Comona with the Mission 16 sky. No enemies yet.
User decisions 2026-10-20: Survival Mode is its own mod and must NOT take over Stonehenge's (or any other mod's)
mission slot or files. The menu entry is part of this milestone (moved up from the old Milestone 5).
- [x] New persistent level `PL_SurvivalMode` from PL_Mission022's sublevel list (Map17 terrain, sea, city, foliage, ComonaAirport).
  Mission022_MiniGame stays loaded: it is the airport's landing/takeoff set (control tower, landing areas,
  gear-down volumes, catapult points) that Milestone 4 needs. Nothing triggers it while the EPs are empty.
- [x] Swap the lighting sublevel to Map14/Mission016/Mission016_Common_Lit_Cloudly01.
  Also from PL_Mission016's world settings: clock 08:00 (M22 is 05:30) and CloudDensityScale 0.9.
  Mission 22's shuttle-launch cloud light setting is removed.
- [x] Minimal EP/WD/EF/MC files: one player start over the airport, no objectives.
  Start: 6 km out on the runway approach, 1500 m up, heading -23 (at the airport). Time limit 60 min.
- [x] Mission row: Survival's own table DT_SV_MissionRows (Mission022's row: MissionID 9101,
  LevelId 70 = the unused Test02 slot, MapReference -> PL_SurvivalMode, SV_* text keys). Scripts/main.lua copies it into
  DT_LiveMissionTable at run time (FindRow/AddRow, as LadonHelper does on DT_Skin). Stonehenge uses 9001 / 69.
- [x] Menu row: DT_SV_MenuRows ("Campaign" row: CommandID Main_Top_SurvivalMode, MenuID
  CampaignFreeMissionDifficulty, StringArgs SurvivalMode, SV_Menu_Title / SV_Menu_Help), added to
  DT_LiveMenuMainTopCommands the same way, placed above QuitGame.
- [x] Button: native runtime `runtime/survival_rt.c` -> AC8SurvivalMode/dlls/main.dll, reverse-engineered
  from Stonehenge's main.dll (tools/re/STONEHENGE_MAIN_DLL.md). Main menu decide sees StringArgs SurvivalMode;
  the difficulty page's next-menu hook then sets the chosen difficulty (the game's own), writes MissionID 9101 into the
  campaign context and travels to Hangar 04 (Mission 22's hangar, matching the row's lighting) -> sortie. SV_* texts come from its text-lookup hook.
  Coexists with Stonehenge: waits for Stonehenge's hooks, then chains onto them. Log: AC8SurvivalMode\AC8SurvivalMode.log.
- Why runtime rows: Stonehenge adds its rows by overriding those same stock tables (row struct LiveLevelTable), and its
  main.dll routes its button. Overriding them too would make the last-mounted mod win and drop the other's row.
- Dev shortcut (until the button works): Ctrl+F8 on the main menu opens PL_SurvivalMode directly (GameplayStatics.OpenLevel).
- Test 1 (2026-10-20, TEST_RESULT_2026-10-20.md): SurvivalMode_P failed to mount (last .ucas block read rounded up to
  16 bytes, 4 bytes past the end) -> no rows, no entry; Ctrl+F8 opened the missing map and crashed. Native runtime found
  and hooked everything. Fixed: pack.py pads/checks the .ucas; Lua checks the container before Ctrl+F8 and the menu row.
- Test 2: container mounted (6 of 6, 11 packages registered) and the runtime hooked everything, but Lua's LoadAsset
  can't load mod packages (asset-registry lookup), so no rows. Fixed: load via LoadAsset_Blocking (Lua 0.2.2).
- Test 2b: rows added (mission 20:24:00, menu 20:24:39) but the menu never showed the entry, even after rebuilding it.
  The row matches Stonehenge's field for field (only names/texts differ). Cause: the menu reads DT_LiveMenuMainTopCommands
  through a soft reference (DA_LiveMenuMainTopPageSettings), so the table loads with the menu page and can be reloaded
  fresh later; the row was added after the list was built and the watch had stopped. Fix (Lua 0.3.0): load + pin both
  tables at start (GameInstance.ReferencedObjects), add rows at once, keep watching for reloads; logs every table copy
  and the entries each command list shows.
- Test 3: SURVIVAL MODE shows (below QUIT GAME) and is recognised, but confirming a difficulty arrives as menu
  transition 7 from another menu object; the page's own decide never runs, so it fell through to Free Mission.
  Fix (runtime 0.2.0): look the page up with UE4SS FindAllOf like Stonehenge, start from transition 7, hold back
  the sender's transitions. Order fix (Lua 0.3.1): a removed row's slot is reused by the next AddRow, so both rows
  are re-added and the order is checked.
- Test 4: FindAllOf found no difficulty page at transition 7; it fell through again. The 'next menu' slot is
  FName* GetNextMenu(page, FName* out) and the stock page answers "CampaignFreeMission". Fix (runtime 0.3.0):
  when Survival is chosen, start from that hook with the page it's called on (no lookup) and answer NAME_None.
- Test 5: redirect works (difficulty -> hangar -> sortie, aircraft taxis out), but the hangar was black: the runtime
  travelled to Hangar 02 while the row (Mission 22's) carries Hangar 004's lighting and sublevels. Fix (runtime 0.4.0):
  travel to Hangar 04 (level 0x0F = 10 + the row's TravelHangarMap 5); build_survival.py checks the two match.
  Lua 0.3.2 only logs command lists that show entries.
- Test 5 follow-up: hangar lighting confirmed fixed with runtime 0.4.0 (Hangar 04); the Mission 16 sky over Comona and
  landing at Comona airport confirmed by the user.
- Test 6: minimap offset from the world. Survival's global world data had no combat zone (the minimap frames itself on
  it). Fixed and confirmed in-game: WD_SurvivalMode_global gets Mission 22's CombatZone0 (centre -707336, -261895; 80 x 80 km,
  40 km high).
- [x] Milestone 1 done (2026-10-20): menu -> difficulty -> lit hangar -> sortie -> Comona with the Mission 16 sky,
  landing at the airport and the minimap all confirmed in-game. Still open: Stonehenge's and Survival's entries working
  together (Stonehenge has to be reinstalled for that test).
  Build: `tools/build_all.sh`, then copy `build/install/SurvivalMode` into `ue4ss\Mods\IoStoreLoaderMod\`
  and `build/install/AC8SurvivalMode` into `ue4ss\Mods\`. UE4SS.log lines start with [AC8SurvivalMode].

## Milestone 2: rounds (CC)
- Research (tools/re/EVENT_NOTES.md): EP records are LiveCustomEventTriggerTable / LiveCustomEventExecutionTable
  structs (tools/checks/ep_dump.py reads any stock EP exactly). Enemy pool = Mission 22's own Comona units.
- Round probe (built, untested): WD_SurvivalMode_global = Mission 22's global world data with no unit spawning at
  start; EF gets SV_Round / SV_Alive; tools/survival_events.py writes the round graph from Mission 22's own records
  (spawn 2 flights 25 km from the player -> count flights destroyed -> 45 s -> round 2 respawns them + 2 more).
  Open question it answers: can a destroyed flight be spawned again (decides how endless rounds are built)?
  Lua 0.4.0 logs every AI aircraft created and the alive count ("round probe:" lines in UE4SS.log).
- Probe test 1: all 71 units spawned at start (removing bIsSpawnFromStart = class default true). Fixed: explicit zero.
- Probe test 2 (22:02-22:05): round 1 spawned 2 flights (2 x F-16C, 2 x Su-33), round cleared on the last kill, and
  45 s later round 2 SPAWNED THE SAME FLIGHTS AGAIN -> destroyed flights can be respawned: endless rounds can reuse a
  fixed pool. The first kill counted (hard rule 6 didn't apply). But round 2's extra flights (if SV_Round >= 2) didn't
  appear. Lua 0.4.1 logs the SV_* flags on change to tell whether SV_Round reached 2 or the spawns failed.
- Probe test 3 (22:12-22:19): SV_Round reached 2 and the conditional Alive += 2 ran (conditions work), but group 2's
  spawns created no aircraft, so Alive stuck at 2 and no round 3. Group 2 used the same spawn bearings as group 1
  (-45/-50 deg, 25 km): likely refused as occupied. Fix: one bearing per flight; Alive now counts flights that actually
  appeared ("reinforcement appeared" trigger), so a failed spawn can't block the clear.
- Probe test 4 (22:29-22:33): separate bearings didn't help: round 2 again spawned only group 1 (Alive = 2 now matches
  the flights that appeared). So it's the condition on the spawn exec: conditional flag operations and calls work,
  conditional spawns don't. Fix: Mission 22's pattern - each group spawns unconditionally in its own remote event
  (RE_SV_SpawnGroupN), and round start calls those events with the round condition.
- Probe test 5 (22:37-22:43): still only group 1 in round 2; round 2 cleared, SV_Round -> 3, but round 3 spawned
  nothing. Diagnostic build: counters SV_Starts (round starts) and SV_SpawnG1/G2 (group spawn calls), logged by the
  Lua probe, plus group 2 called 4 s after group 1 (Mission 22 never spawns two groups at the same moment).
- Probe test 6 (22:47-22:51): the chain runs end to end (SV_Starts 3, SpawnG1 3, SpawnG2 2) but spawns are refused:
  group 2 always, group 1 in round 3. Likely cause: 25 km from the player often lands outside Mission 22's combat zone
  (centre x -7 km, 80 km wide; the airport is at x +16 km). Fix (untested): spawns relative to an anchor over Comona
  Airport (Mission 22's dummy unit EA_Unit_SpawnDummyPoint0, moved there, 2 km up), 15 km out, a bearing per flight.
  Lua 0.4.2 logs each aircraft's spawn position and distance from the airfield.
- User report: spawned flights idle near their spawn until the player is within ~4.5/3 km: a unit only works inside its
  area (RadiusInMeter 6000, PatrolRadiusRatio 0.5 -> 3 km patrol). Fix (untested): chase loop RE_SV_Chase every 6 s -
  teleport Mission 22's dummy Unit_dummyN0 / A_Obj_01_dummyN0 onto the player and LiveUnitMoveActor every flight's area
  onto it (Mission 22 moves its waves' areas the same way; the player-dummy pattern is from Missions 006/023).
- User report: difficulty always Rookie at mission start. The runtime's next-menu start read the "selected" difficulty
  through its fallbacks (stored byte / list position), always got Casual there, and set it - overwriting the choice
  the game's page had already applied. Fix (runtime 0.5.0, untested): set it only when read from the selected entry's
  name, otherwise keep the game's; Lua 0.4.3 logs LiveDifficultyManager.CurrentDifficulty at mission start and 10 s in.
- Music (user request): Mission 8's AKE_Bgm_Ms08A_Play at mission start (LivePlayBGMExecution, cloned from Mission 22's
  own music call). Both missions' music is in the shared campaign BGM bank (DA_SoundDB_AKB_BGM_Campaign). Confirmed in-game.
- Probe test 7 (23:02-23:06): difficulty Ace kept (fixed). Spawns landed 15 km around the MAP ORIGIN: the anchor's AI
  object has its own SpawnPoint (still 0,0). By bearing, round 2 was group 2's first spawn and group 1 did NOT respawn;
  round 3 spawned nothing. New since the respawns worked: the chase loop moved destroyed flights every 6 s. Fix: chase
  only flights that are up (SV_UpX flag set on appear, cleared on destroy; conditional call per flight), and the
  anchor's object SpawnPoint set to the airfield too.
- Crash on the menu (23:10, Windows report c0000374 heap corruption in ntdll; minidump stack: UE4SS.dll's Lua and
  ucrtbase heap only, not our DLL). Likely UE4SS 3.0.1 Lua thread-safety: the script ran an ExecuteWithDelay timer per
  menu widget next to two LoopAsync loops. Lua 0.5.0: no ExecuteWithDelay, menu-list diagnostics removed, one
  LoopAsync that queues one game-thread job; object notifications only record. tools/re/minidump_stack.py reads dumps.
- Probe test 8 (23:14-23:18, still Lua 0.4.3): anchor works (every spawn 14.9-15.1 km from the airfield), Ace kept.
  Round 2 again only 4 aircraft: group 1 (chased while alive) didn't respawn, group 2 spawned for the first time; round 3
  nothing. Every round 2 so far brought exactly 2 flights (tests 2-6: group 1 again, group 2 missing; tests 7-8: group 2,
  group 1 missing). Either two causes (group 2 out of the combat zone while spawns were player-relative; group 1 unable
  to respawn after LiveUnitMoveActor) or a game limit on reinforcement spawns. Next build decides: chase loop OFF
  (nothing is ever moved), pooled flights get an 80 km unit area instead (RadiusInMeter) so they still come for the
  player. 8 aircraft in round 2 = two causes; 4 = a limit.
- Probe test 9 (23:24-23:27, Lua 0.5.0, no crash; pin array grows correctly 0 -> 4): no chase, nothing ever moved, and
  group 1 STILL didn't respawn in round 2 (group 2's first spawn worked). So moving wasn't the cause. What differs from
  tests 2-6 (respawns worked): spawns around a FIXED anchor put a flight's second spawn on exactly its first spot.
  Theory: a flight isn't spawned again where it last spawned. Probe: 3 position variants per group (+40 deg per round:
  round 1 base, round 2 +40, round 3+ +80), each in its own spawn event called by round condition. Rounds 2 and 3 should
  then bring every flight; round 4 repeats round 3's spots, so it would fail again (random bearings come next).
- Probe test 10 (23:24-23:28, the 3-variant build): round 2 called group 1's spawn (SV_SpawnG1 = 2) but neither of its
  flights came up (SV_UpA/B = 0) while group 2 spawned for the first time. Position variants didn't help: theory wrong.
- Reverse-engineered the game's spawning (user request 2026-10-20: "reverse engineer the entire spawning system ...
  make something completely custom"), tools/re/SPAWN_SYSTEM.md: LiveReinforcementExecution -> SpawnUnitByName ->
  SpawnUnits, which skips every world-data desc whose UniqueID is still on the phase's unit list
  (FLivePhase::ManipulableObjects). The game only takes units off that list when a phase ends, so a shot-down flight
  can never be spawned again by any event node. (Tests 2-6 respawning isn't explained; tests 7-10 match exactly.)
- Survival's own spawner (runtime 0.6.0 + Lua 0.6.0): the native runtime registers Lua functions through
  UE4SS (SV_Spawn, SV_SetAircraft, SV_UnitAlive, SV_LogUnits); SV_Spawn takes a shot-down flight off the list the way
  a phase end does (unregister + destroy its unit actor), moves the desc where Lua says and calls the game's own
  SpawnUnitByName. Rounds now run in Scripts/main.lua: random flights from Mission 22's 24 two-ship flights, a random
  aircraft type each (9 types), 18-25 km from the airport on a random bearing inside the combat zone, round clear when
  every flight it spawned is down, 45 s, next round one flight more (2, 3, ... up to 8). The event package gives each
  flight its orders on appearing (air-only search, engage the player), counts SV_Alive / SV_Kills, and runs the chase
  again (user request 2026-10-21: without it enemies only came for the player once the player was close; the moves were
  wrongly blamed for the failed respawns): every 6 s the dummy Unit_dummyN0 is teleported onto the player and every
  flight that is up (SV_Up_NN) gets its area moved onto it; pool areas are back to Mission 22's 6 km. The airfield
  anchor is gone; only the chase dummy spawns at start. Settings: CFG in main.lua, overridable by an optional
  Scripts/survival_config.lua (for Codex's config). tools/checks/lua_check.py checks main.lua's syntax at build time.
  Test: fly 3+ rounds. AC8SurvivalMode.log should show "UE4SS: Lua mod AC8SurvivalMode started (mod slot N)",
  "spawner layout: ...", "spawn ERA_...: up, 2 aircraft ..." and, from round 2, "... was shot down; took it off the
  phase's list"; UE4SS.log the "round N:" lines. Send both logs.
- Test 11 (05:04-05:10, runtime 0.6.0 + Lua 0.6.0): THE SPAWNER WORKS. UE4SS called on_lua_start (slot 6, and its
  deprecated twin slot 8, so the functions were registered twice, harmless); the phase pointer is right (spawned flights
  appear on its list); every flight came up with 2 aircraft 20-23 km from the airport on its random bearing, as the type
  Lua picked (MiG-29A, F-14D, Su-33 and Su-34 blueprints spawned: SV_SetAircraft works). Round 1 cleared, round 2
  brought 3 flights. Not exercised yet: recycling (round 2 drew 3 flights that hadn't flown). User report: enemies
  didn't chase. Cause: SV_Up_NN was only ever set for flights 01-09. The event records name a flag by string, which the
  game turns into an FName that splits a numeric tail ("SV_Up_19" -> SV_Up, number 20), but the build wrote the flag
  table's keys unsplit (SV_Up_19, number 0), so flights 10-24's flags didn't exist: never flagged up, never chased.
  Round 1's flights were 19 and 23. Stock tables store such names split (Mission 22: Bool_IsAlive_f15e_0 is
  Bool_IsAlive_f15e, number 1). Also seen: in round 2 one flight lost both aircraft ~6 s after appearing 22 km out.
  Same run, rounds 3-5 (05:12-05:18): RECYCLING WORKS. Round 3 drew two shot-down flights (07_Air2, 08_Air1): "its last
  flight was shot down; took it off the phase's list and removed its unit actor", then both came up with 2 aircraft;
  round 5 recycled four. Rounds 1-5 brought 2, 3, 4, 5, 6 flights and each cleared. The flags match the diagnosis
  exactly: only pool flights 01-09 were ever counted up (round 4: flights 6, 8, 5 flagged; 22 and 10 not).
- Chase fix (Lua 0.6.1): the flag asset's keys are stored split like the engine's FNames (the build asserts
  every flag the records use is declared that way); rounds reuse shot-down flights first and send a spare if a spawn
  fails; the name table is written in sorted order, so the same build gives the same bytes. Lua 0.6.1 logs every 10 s
  "chase: nearest enemy N km from you; X of Y flights up are flagged for the chase" (X must equal Y now) and, per
  aircraft lost, its last altitude and distance from the player ("... down, last seen ...").
- Test 12 (05:23-05:29, runtime 0.6.0 + Lua 0.6.1): THE CHASE WORKS. Every flight up was flagged (1 of 1 ... 4 of 4),
  and the enemies came for the player: round 1's nearest went 20.6 -> 15.1 -> 3.9 -> 0.6 km in 30 s, round 2's
  23.9 -> 13.5 -> 1.6 km in 20 s. Every aircraft lost went down 0.2-5.3 km from the player (shot down, not crashed).
  Rounds 2 and 3 recycled the flights that had flown first, so the game's unit list stayed at 3-4 entries.
- [x] Round HUD (user request 2026-10-21, SURVIVAL_SPEC.md section 6): round number always shown; countdown to the
  next round only after a round is complete; "Round Complete" callout on clear; callout just before a round starts.
  WORKS in Lua 0.7.0 (test 13, 2026-10-22: built with the HUD font, ROUND 1 callout 3 s before spawning, ROUND 1
  COMPLETE on clear, hidden while paused, rounds on the game clock). Open: the rows used the fixed y 470 because the
  mission info stack's height can't be read through cached geometry (see HUD_LAYOUT.md). The game's HUD layout was reverse-engineered
  (tools/re/HUD_LAYOUT.md, tools/re/hud_layout.py; user request: "make our own custom one that starts at runtime"):
  Survival builds its own HUD layer at run time on the game's 3840x2160 design canvas. ROUND: n and NEXT ROUND: m:ss
  sit under the game's TIME/SCORE stack in its style; callouts copy the MISSILE ALERT banner. Rounds now run on the
  game clock, so they and the countdown stop while paused; the HUD hides while paused. Ctrl+F9 dumps the live HUD.
  Test 13 checks: HUD built (UE4SS.log "hud: built"), rows placed below the stack, callouts, pause stops the
  countdown, hud_dump.txt written. Same layer later carries credits and airfield health.
- [x] Waves: random flights per round from the pool, spawned by Survival's spawner (test 11).
- [x] Round clear when every flight of the round is down; 45 s intermission timer; next round (test 11).
- [x] Fighters: engagement order targeting the player, and the chase that brings them to the player (test 12).
- [x] Enemy variety (user request 2026-10-20): mixed aircraft types, picked at random per flight (SV_SetAircraft;
  test 11). Types outside Mission 22's NPC table need NPC rows, added at run time (never override a shared NPC table).
- Test: 3 rounds in a row, no double spawns (done: tests 11-12, 5 rounds).
- No timed despawn of enemies that drag on (user decision 2026-10-21): with the chase every enemy comes for the player
  and has to be shot down. Add a safety net only if a test shows a round that can't be finished.

- [x] (user 2026-10-21) Ammo cap at spawn: set player ammo right after spawn (LiveSetWeaponAmmoCount, M015;
  fallback: Lua on player plane spawn). Casual 24 msl / 8 SPW / 6 flr; Standard 16/4/4; Ace 10/2/3. Gun unlimited. Values in config.
  Test 14 (Lua 0.8.0): the reflected FCS module AmmoCount has no live instances (weapon definitions only), no cap.
  (2026-10-22: user raised the presets to Ace 30/14/3, Standard 48/28/4, Casual 72/56/6, scaled by the old ratios.)
  BUILT in runtime 0.7.0 + Lua 0.8.1 (2026-10-22), waiting for test 15: native SV_Ammo / SV_SetAmmo copied from the
  stock node's own code (tools/re/AMMO.md); CFG.ammo presets by difficulty, gun kept full.
  Test 16 (2026-10-22, Lua 0.9.0, Ace): caps WORK (144/32/4 -> 10/2/3, no free restock, gun full). But landing at the
  airfield rearmed to the stock full load (144/32/4). Fixed in Lua 0.9.1, waiting for a test: any count above its cap is
  put back to the cap every 0.5 s (log "ammo: refilled above the ... caps"), so a rearm fills up to the cap.
  Test 17 (2026-10-22): landing rearm refills to the caps - WORKS (user).
  (Test 15 never ran: main.lua had an invalid "\m" escape and didn't load; lua_check.py now rejects bad escapes.)
- [ ] (user 2026-10-21) AI behaviour tiers: map LA_* families in LuaSource/Chronicle/AI (Provoke, PursueTarget,
  AttackAvoidance _gun/_msl_s/_msl_m/_spw/_CP, EscapeFromPursuer, MoveAwayFromTarget, ace moves); work out what
  0000/0011/0041/0211/0400/1000 mean; escalate per round with stock tiers + LiveAIChangePilotRankExecution. Write AI_BEHAVIOURS.md.
- [ ] (user 2026-10-21) Music: music stops around round 5 (mission BGM ends). Trigger music each round start;
  rotate stock combat tracks, bigger track on special rounds; In/OutSupplyBGM (M024/M026) on landing.
- [ ] (user 2026-10-21) Pause-menu music player (as in free flight): add the entry to Survival's pause menu
  (runtime row like the main menu) or flag the mission like free flight. If the player picks music, stop round music switching.

- [ ] (user 2026-10-22) Custom, learning enemy behaviour: Survival's own LA_SV_* behaviour scripts + a player profile
  (how you kill / evade / fly) that picks counters per flight and adjusts PilotRank; memory across runs in Survival's
  own file. Step 1 = behaviour probe, BUILT in Lua 0.9.0 (2026-10-22), waiting for test 16: (1) each round's first
  flight flies a MiG-29 copy whose pursue slot is LA_SV_ProbePursue (barrel rolls each attack run; odd rounds the
  packaged script /Game/Mods/SurvivalMode/AI/LA_SV_ProbePursue, even rounds a LuaScript made at run time), rows added
  at run time to DT_NPC_LuaSet / DT_NPC / DT_NPC_Mission022; (2) PilotRank written live on every enemy (5) and re-read;
  (3) "probe kill:" log lines with last attacker, aspect, altitude and the player's ammo spent.
  Test 16 (2026-10-22): both probe rows were ready at level load and spawned (round 1 package script, round 2
  run-time script); every aircraft spawns through DT_SV_NpcMission; PilotRank 4 -> 5 sticks (re-read 10 s later);
  probe kill lines logged, but "last hit by ?" (K2_GetLastDamagedByAttacker gives nothing; use the native damage
  history from KILLS_HEALTH_DEATH.md). Barrel rolls: not seen (user).
  Test 17 (2026-10-22, Lua 0.10.1): the script's Ctor marker was never written, so the game never ran our script.
  Cause (RE): the game's require("A.B.C") StaticLoadObject's /Game/LuaSource/A/B/C (exe 0x144eb8c00); ours was at
  /Game/Mods/SurvivalMode/AI. Lua 0.10.2: packaged script moved to /Game/LuaSource/SurvivalMode/AI/, run-time script
  put in an in-memory package at the same path; also the barrel roll's 9th arg (a 5 m gate) dropped. Waiting for test.
  Test 17 also: 25 km search set up for 9/9 aircraft; enemies closed from 18 km to 9 km in 10 s (they come for you).
  Lua 0.11.0 (user: more aggressive, 40 km): search + unit area 40 km; the fighters' _SV rows fly the aces' set
  NLID_0400_CP (keeps pursuing after a pass instead of MoveAwayFromTarget_0011's ~13 s extend-away). Waiting for test.

## Milestone 3: airfield health + bombers (CC)
- [ ] Airfield target at ComonaAirport with max health set to 100 (copy Mission 004's base + RE_BaseHP_* setup).
- [ ] Health bar on the HUD (LiveUnitHealthDisplaySwitch, Missions 006 / 025_2).
- [ ] Bombers on paths ending at the airport (copy Mission 004's BaseAttack paths).
- [ ] (user 2026-10-22) Bomber types: Tu-160 and Tu-95 alongside Su-34 and F-15E; bombers ONLY attack the airfield.
  Rows: copy DT_NPC_Mission004's `t160_common` (OP0012_t160_01, PlaneBomb002) and `tu95_common` (OP0011_tu95_01,
  PlaneBomb002) into DT_SV_NpcMission at build time (route A, tools/re/EVENTS_AIRCRAFT.md: no blueprint imports
  needed; the blueprints are soft-loaded from pakchunk0). Su-34 / F-15E bombers use the STOCK rows (6 km search,
  not the fighters' _sv rows). Pool: Mission 22's `ERB_Unit_01_Air2` strike desc + copies, outside POOL; on appearance
  GROUND_ONLY search + LiveAIEngagementOrder Normal on `AB_Unit_01_Ground2`, AIOnly, unit area onto AreaB_MarkActor0
  (Mission 22 records 1686/1694/2037; tools/re/AIRFIELD_SUPPLY.md section 2).
- [ ] At 0: flag "AirfieldDown", radio callout, shop closed next round, back online at 50 after.
- Test: let bombers hit it to 0; confirm the run continues and the shop flag clears a round later.

## Milestone 4: landing + shop (CC logic, CX config)
- [ ] Landing/takeoff at the airport (Mission 022's LiveSetTakeoffAndLandingEventExecution + Supply event).
- [ ] Rearm with LiveSetWeaponAmmoCount (Mission 015); repair with LiveSetHealth.
- [ ] (user 2026-10-21) Shop refills to a CAP, not a full load: Casual full load, Standard 32 msl, Ace 20. NO wingman purchase (dropped by user).
- [ ] CX: `config/survival.ini`: prices, credits per kill, intermission length, wave tables, special rotation, with comments.
- Test: land, buy missiles, take off, ammo is refilled up to the cap (not past it).

## Milestone 5: difficulty presets (CC + CX)
- [ ] Casual / Standard / Ace presets on top of the game's difficulty, plus the advanced config (see AGENTS.md).

## Milestone 6: specials, polish, release (CC + CX)
- [ ] Special round every 5th round (ace squadron, Ladon, Podarge drop, ECM towers, stealth wing).
- [ ] Portal spawn effect for specials (stock teleport nodes + VFX burst).
- [ ] CX: ACE8 Mod Launcher toggle, readme, credits (@voidcallsreaper), release zip.
- [ ] (user 2026-10-21) Event camera: the stock camera prompt that swings the view toward an event; find the node.
  Use for ace/boss spawns, the shuttle launch and Helios barrages.
- [ ] (user 2026-10-21) Ace intro using the user's replay-camera code (location TBD from user): slow-down, tracking shot,
  letterbox, name card, radio line.
- [ ] (user 2026-10-21) Ace learns from your fights: log how the player kills aces (missile/gun/tail/SPW/altitude), save
  across runs (save game or file), next spawn loads the matching LA_ counter variant + a radio line. Reset option in config.

## Milestone 7: new special rounds (CC) - user requests 2026-10-21. NO allied aircraft or ships in any of them.
- [ ] Comona Defense: port Mission 19's IN-GAME shuttle launch (shuttle, pad, launch event, ms19 smoke/explosion VFX)
  + enemy waves at the spaceport. Player watches the launch live while flying. Strip all dialogue except key callouts
  (countdown, pad under attack, liftoff). Strip M19 allies (ally ships/wingmen, wingman HUD/radio).
  Fail = shuttle lost -> airfield/shop closed for ONE round (same rule as airfield at 0).
- [ ] Amphibious assault: enemy fleet offshore launches LCAC waves (Mission 9 Lcac_*_Landing units/behaviour) at Comona's
  beaches. M9 is a different map: draw NEW paths to Comona's shoreline. No M9 allies.
- [ ] Anomaly ace (boss special round): floating ace (tiny slow path or Lua position pin; check LiveAIGroundDummy M011/019/030).
  5 guards orbit it in a sphere (start from Mission 23's drone formation / Barrier UAV; else Lua positions them on a rotating sphere).
  Player gets close (~5 km) -> guards switch to engagement order and attack (portal burst + radio line).
  Inside the ace's radius (~3 km) the player's PITCH AND ROLL invert (fade in ~2 s, HUD warning, radar noise
  LiveStartHUDRaderMapNoise + LiveActivateGlassesEffect from M015) until the ace dies. Config: on/off, pitch/roll/both (default both).
  Research first: where AC8 reads flight input, so UE4SS/native can flip it.
- [ ] Helios missile barrages on RANDOM rounds, targeting the PLAYER only (not the airfield). Find Helios in Content/OnlineMode;
  check it works offline; else rebuild from offline launchers (M010/M020/M030). Never touch online services.

## Milestone 8: Discord leaderboard (after release)
- [ ] End-of-run "Submit to leaderboard? Yes/No" (opt-in, remembered; pilot name in config). Submitted by the Survival
  mod's own native runtime (NOT the Mod Launcher). Sends to a small relay (e.g. Cloudflare Worker) which sanity-checks and
  posts to a Discord #survival-runs channel and keeps a pinned top 10 per difficulty. Offline: queue and send next launch.
  Never contacts Bandai services.

## Research backlog (user 2026-10-21), in order
1. AI behaviour tiers (above)  2. Enemy unit data DT_NPC_Mission##  3. Fire control / weapon data  4. Store UI (NUI/Shop) for the
airfield shop  5. HUD widgets (round/credits/airfield HP/banners)  6. Radio tables  7. Debriefing screen  8. Save game
(ace memory, best runs)  9. OnlineMode (Helios)  10. VFX (portal, Helios)  11. Unlock tables  12. M19 launch + M9 LCACs
13. M23 drone formation + flight-input path  14. Pause-menu music player + event-camera node.

Research pass 2026-10-22 (all 14 items researched from game files and the exe; nothing below is tested in game yet
unless it says so). Notes in tools/re/:
- 1, 2 AI tiers + NPC data -> AI_BEHAVIOURS.md, NPC_DATA.md. Behaviour = plain-Lua LuaScript trees (LA_*) picked per
  aircraft by its NPC row's LuaSet (15 slots); 0000 base fighter, 0011 light, 0041 Shadow, 0400 aces, 1000 large
  aircraft; PilotRank 1-5 weights every script; difficulty -1/0/+1. Plan: Survival's own NPC table, rank 2->5 by
  round, Shadow sets on special rounds, Named aces later. User idea 2026-10-22: custom learning enemy behaviour
  (own LA_SV_* scripts + a player profile that picks counters); first a probe build (own script loads? live PilotRank
  write? kill details?).
- 3 Fire control / ammo -> AMMO.md. Live counts are native; runtime 0.7.0 SV_Ammo / SV_SetAmmo / SV_FreeRestock.
- 4, 7, 8, 11 Shop UI, debriefing, saves, unlocks -> UI_SHOP_SAVE.md. NUI/Shop is the online store (don't use); build
  the shop and the end-of-run summary at run time like the HUD; menu input from the game's INP_Menu* actions.
  Never fire a mission clear (a clear writes the mission into Campaign.sav for good: Stonehenge's 9001 is there,
  Survival's 9101 is not); own data file in %LOCALAPPDATA%\AC8SurvivalMode\; award nothing to real progression.
- 5 HUD -> HUD_LAYOUT.md (done, tests 13/13b).
- 6, 14 Radio, music, pause music player, event camera -> MUSIC_RADIO_CAMERA.md. BGM nodes are in M22's EP; per-round
  track switch through remote events (needs a native SV_Event); pause music row exists hidden (hook its validity
  check); LiveEventFocusCameraExecution (M22 RE_ShuttleFocusCamera) for ace/boss spawns.
- 9, 10 Helios + VFX -> HELIOS_VFX.md. Helios = online-mode bombardment object (LiveFireHelios, 6-9 heat-bomb blasts
  walking from the target); offline code paths look clean (one unchecked manager pointer). Portal: Lua
  NiagaraFunctionLibrary.SpawnSystemAtLocation with the Alicorn barrier set (omen/loop/reverb).
- 12, 13 Special rounds -> SPECIAL_ROUNDS.md. Comona Defense = Mission 22's own live shuttle launch (already in
  Survival's world data). Amphibious: copy M13's enemy LCAC pattern (M9's LCACs are allies), beaches still to be
  mapped. Anomaly ace: M26 x40a formation for the guards; flight input hook at 0x147d689b0 (pitch +0xff8, roll
  +0xff4; signature unique) for a native SV_SetControlInvert.

Research pass 2 (2026-10-22, user: "reverse engineer anything else you think you might need"):
- Kills, score, health, death -> KILLS_HEALTH_DEATH.md. Health on LiveGameObject (HealthInternal = HP x 10, MaxHealth,
  GetDamagePercentage); repair = copy LiveRestorePlayerPlaneExecution natively (SetHealth vfunc + armour pool); the
  game keeps the last damage causer + damage type + DamageHistoryMap (kill attribution); death = MissionFinishReason
  2/3 + LiveCampaignPlaneDeathMissionEndSequence; end a run with LiveMissionFinishExecution MissionFailed (M015),
  never MissionClear. Credits from the NPC row's BaseScore, not the game's score.
- Airfield, bombers, landing -> AIRFIELD_SUPPLY.md. Template = Mission 22's own Su-34 strike on Comona Airport
  (4 invincible dummies, MissedWeapon triggers) counted into an SV_AirfieldDmg flag; bombers via SV_Spawn, out of the
  chase pool; landing is on by default, closed/opened with LiveSetTakeoffAndLandingEventExecution; re-apply the ammo
  cap after FinishInGameHangar.
- SV_Event + more aircraft -> EVENTS_AIRCRAFT.md. Remote-event layout/lifetime verified, one signature; aircraft
  outside Mission 22's table need rows in Survival's own NPC table (DT_SV_NpcMission, built since Lua 0.9.0 /
  2026-10-22) because the spawner caches the table's aircraft at level start.

## Dropped by the user
Weather/night rounds, sky selection (time of day can't change at runtime), buying a wingman in the shop.
