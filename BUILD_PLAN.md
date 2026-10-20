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
- [ ] Round counter (Lua: D.round; shown on the HUD in a later milestone).
- [x] Waves: random flights per round from the pool, spawned by Survival's spawner (test 11).
- [x] Round clear when every flight of the round is down; 45 s intermission timer; next round (test 11).
- [ ] Fighters: engagement order targeting the player (event package, on appearing).
- [x] Enemy variety (user request 2026-10-20): mixed aircraft types, picked at random per flight (SV_SetAircraft;
  test 11). Types outside Mission 22's NPC table need NPC rows, added at run time (never override a shared NPC table).
- Test: 3 rounds in a row, no double spawns, stragglers despawn at about 2 min.

## Milestone 3: airfield health + bombers (CC)
- [ ] Airfield target at ComonaAirport with max health set to 100 (copy Mission 004's base + RE_BaseHP_* setup).
- [ ] Health bar on the HUD (LiveUnitHealthDisplaySwitch, Missions 006 / 025_2).
- [ ] Bombers on paths ending at the airport (copy Mission 004's BaseAttack paths).
- [ ] At 0: flag "AirfieldDown", radio callout, shop closed next round, back online at 50 after.
- Test: let bombers hit it to 0; confirm the run continues and the shop flag clears a round later.

## Milestone 4: landing + shop (CC logic, CX config)
- [ ] Landing/takeoff at the airport (Mission 022's LiveSetTakeoffAndLandingEventExecution + Supply event).
- [ ] Rearm with LiveSetWeaponAmmoCount (Mission 015); repair with LiveSetHealth.
- [ ] CX: `config/survival.ini`: prices, credits per kill, intermission length, wave tables, special rotation, with comments.
- Test: land, buy missiles, take off, ammo is full.

## Milestone 5: difficulty presets (CC + CX)
- [ ] Casual / Standard / Ace presets on top of the game's difficulty, plus the advanced config (see AGENTS.md).

## Milestone 6: specials, polish, release (CC + CX)
- [ ] Special round every 5th round (ace squadron, Ladon, Podarge drop, ECM towers, stealth wing).
- [ ] Portal spawn effect for specials (stock teleport nodes + VFX burst).
- [ ] CX: ACE8 Mod Launcher toggle, readme, credits (@voidcallsreaper), release zip.
