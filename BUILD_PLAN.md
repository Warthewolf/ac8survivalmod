# Survival Mode: build plan

Work top to bottom. Each milestone is one test build. Commit after each one works in-game.
Owner: CC = Claude Code, CX = Codex. Never work on the same files at the same time.

## Status (2026-10-22, Lua 0.24.0 / runtime 0.12.0)
Legend: [x] confirmed in a test, [~] built and installed but not confirmed yet, [ ] not started.
- Milestone 0-1: done.
- Milestone 2 (rounds): spawner, rounds, intermission, variety, ammo caps, HUD, clock / score cleanup, pause-menu
  music player (+ QUIT GAME still shown), own fighter behaviour, player-only targeting, skill tiers, lag fix: confirmed.
  Squadrons 2/4/6 + aircraft budget, harder enemy weapons (missiles, guns, special weapons): built, untested.
  Music Player track skips: cause found (its track clock ran on through pauses), clock held while the BGM is paused
  (runtime 0.12.0): built, untested. Learning behaviour layer: not started.
- Milestone 3 (airfield + bombers): health, HUD bar, hit counting, strike flights spawning: confirmed. Raids every
  3rd round, low strike approach, Tu-95 / Tu-160 bomb runs, airfield down / reopen: built, untested.
- Difficulty spikes BUILT 2026-10-22 (Lua 0.27.0), not installed / untested: every 7 rounds (8, 15, 22; CFG.spikes)
  a level of own fire-control rows (<row>_sv<b|c|d>: faster locks / aim, more shots, tighter spread), PilotRank floor
  4 / 5 / 5, post-stall on every airframe, provoke cone 70 / 60 / 50 deg and decision 2.0 / 1.5 / 1.0 s, surround
  pursuit 80-220 / 60-160 / 50-120 m (live writes, untested), +2 / +4 / +6 aircraft a round; "DIFFICULTY UP" callout.
  Test: "spikes:" log lines (rows made at the main menu; level writes on the first enemy of a spike round).
- Review + cleanup 2026-10-22 (Lua 0.26.1, runtime 0.12.1), untested: shop presses all taken each tick and texts at
  once (the ~1 s lag looked like missed presses); economy (missiles +6 x1.35, special x1.4, flares x1.35); airfield row
  builds AA guns (4000 Z) / SAM sites (8000 Z) once the airfield is whole (Mission 22's airport defences, one unit each);
  config/survival.ini format 2 (settings listed switched off; an old file is kept as .ini.old); the run ends when the
  level is left; callouts queue; shuttle callouts on Survival's own flags; chase / music dead code removed.
- Milestone 4 (landing + shop): rearm to caps, credits (shown as ZOLLARS), shop purchases: confirmed. Landing-menu
  ammo panel showing the caps, airfield repair purchase, config/survival.ini: untested. Aircraft repair: dropped.
- Milestone 5: parked by the user (ammo presets and skill offset by difficulty exist).
- Milestone 6 (special rounds): not started. Framework, portal, event camera and ten specials listed (ace squadron,
  Ladon, Podarge, ECM towers, stealth wing, Comona Defense shuttle, amphibious assault, anomaly ace, Helios); research
  done for the shuttle, LCACs, anomaly ace and Helios.
- Milestones 7-8 (polish / release, leaderboard): not started (a friend test zip exists, no release packaging).

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
  game clock, so they and the countdown stop while paused; the HUD hides while paused. Ctrl+F7 dumps the live HUD.
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
- [x] (user 2026-10-21) AI behaviour tiers: map LA_* families in LuaSource/Chronicle/AI (Provoke, PursueTarget,
  AttackAvoidance _gun/_msl_s/_msl_m/_spw/_CP, EscapeFromPursuer, MoveAwayFromTarget, ace moves); work out what
  0000/0011/0041/0211/0400/1000 mean; escalate per round with stock tiers + LiveAIChangePilotRankExecution. Write AI_BEHAVIOURS.md.
- [x] (user 2026-10-21) Music: music stops around round 5 (mission BGM ends). Superseded 2026-10-22 (user): no
  mission-start or round music (Lua 0.17.1, survival_events.MUSIC None, CFG.music.enabled false); the pause menu's
  Music Player is the only music. Open: its track skips on kills (Lua 0.22.1 logs the BGM controller's names). Trigger music each round start;
  rotate stock combat tracks, bigger track on special rounds; In/OutSupplyBGM (M024/M026) on landing.
  BUILT 2026-10-22 (runtime 0.9.0 + Lua 0.13.0), waiting for a test: SV_PlayBGM = LivePlayBGMExecution's own call
  (the controller fades the old track out); CFG.music rotation from round 2, special list every 5th round, re-post
  after 15 s of silence (SV_BGM(0) = playing id). Log lines "music:". Supply BGM not done.
- [x] (user 2026-10-21) Pause-menu music player (as in free flight): add the entry to Survival's pause menu
  (runtime row like the main menu) or flag the mission like free flight. If the player picks music, stop round music switching.
  BUILT 2026-10-22 (runtime 0.9.0), waiting for a test: hook on the pause list's UpdateCommandValidity drops
  "PauseMusicPlayer" from the invalid list while mission 9101 runs (log "pause menu: the music player row shown");
  Lua stops round music once WBP_Menu_PauseMusicPlayer_000 exists ("music: the pause menu's music player was opened").
  Confirmed (test of 2026-10-22). The list has 6 row widgets: QUIT GAME fell off; restart checkpoint and select
  difficulty are now hidden too, as in free flight - QUIT GAME shows again (user, 2026-10-22).
- [x] (user 2026-10-22) HUD: ROUND row moved to y 312 (the game's TARGET row at 244 covered it on lock-on); the info
  stack's TIME row hidden (clock paused). Lua 0.13.0. TIME row hidden: confirmed by the user (2026-10-22).
- [x] Runtime 0.9.0 SV_Event(name): fires an EP remote event (LiveCallRemoteEventExecution's own dispatch), for radio /
  health bar / sound nodes placed in Survival's EP. Used by the airfield close / open and the heavy bomb runs.
- [x] (user 2026-10-22) Score shown without "/32000"; callout box sized to its text (Lua 0.18.x).
- [x] (user 2026-10-22) Lag: object searches cached or throttled, finished probe diagnostics removed (Lua 0.19.0).
- [x] (user 2026-10-22) Fighters attack the player only (PlayerOnlyNoLimit; with PlayerFirst they took the airfield's
  target points), own behaviour set NLID_SV_Fighter (stock pursuit + 1.5 s break-away). AI watch "ai:" lines.
- [~] (user 2026-10-22) Harder enemies (Lua 0.20.0-0.21.0): Survival fire-control copies for missiles (4 km / 60 deg,
  1.5 s lock, 5 s rest) and guns (2 km / 40 deg, 0.8 s aim, 15-round bursts, x1.5 damage, 1.5 deg spread), a special
  weapon per fighter type (QAAM / 2AAM / LAAM / HCAA), tiers one rank up. Untested.
- [~] (user 2026-10-22) Squadrons of 2, 4, 6 (Lua 0.22.0): fighter flights sized in the world data
  (survival_events.flight_size, standard formation), an aircraft budget per round (4 + 2 a round, max 24), 4-ships
  from round 4, 6-ships from round 8. Untested.

- [~] (user 2026-10-22) Custom, learning enemy behaviour: Survival's own LA_SV_* behaviour scripts + a player profile
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
  Lua 0.11.1: post-stall per model (CFG.maneuvers): every stock cobra/kulbit/Pugachev is behind DecoratorCanCobra /
  CanKulbit, i.e. the plane's reflected bCanManeuverPugachevsCobra / bCanManeuverKulbit, set on each enemy when it
  appears: on only for su33/su35/su37/su47/su57/f22a. Waiting for test ("maneuvers:" log lines).
  Test 18 (2026-10-22, Lua 0.11.1): 40 km search + NLID_0400_CP on 9/9 aircraft; enemies closed 21.8 -> 3.2 km in
  20 s. Post-stall flags read/write live: su34/m21b/m31b blueprints were already cobra false, kulbit false; su33
  cobra true, kulbit false (0.11.1 wrongly turned its kulbit on; 0.11.2 only turns flags off). Probe: NOT flown -
  StaticFindObject threw "GetPackageNameFromLongName: Name wasn't long" on the run-time package path, and that error
  also skipped saving the probe tables, so round 1's package probe never flew. 0.11.2: pcall + variants independent.
  Test 19 (0.11.2): package probe MiGs flew, no barrel roll, no Ctor marker (can't tell "not built" from "no io").
  0.11.3 reads the built tree from the game (LiveAIBehaviorDataAccessor.PursuerTarget.RootNode / CurrentNode).
  Test 20: CRASH in UE4SS.dll (read 0x23) 1 s into the hangar load, before the level: the run-time variant's
  StaticConstructObject(Package, nil, ...) returned a half-made object and was retried every second. 0.11.4: run-time
  variant off (CFG.probe.runtime = false), failed variants never retried. Don't make packages from UE4SS Lua.
  Test 21 (0.11.4): no crash; probe flew; no LiveAIBehaviorDataAccessor objects exist (tree not readable that way).
  User: "go for broke". RE (tools/re/GAME_LUA.md): the exe exports the whole Lua 5.3 C API; slot -> LuaInitializePath
  -> Ctor(classpath) -> require -> StaticLoadObject(/Game/LuaSource/...); script errors are silent in shipping.
  Runtime 0.8.0 + Lua 0.12.0: SV_GameLua / SV_GameLuaState run code in the game's Lua; main.lua logs diagnostics,
  tests the asset route, injects scripts into package.loaded, and counts builds/errors (SV_Report). Waiting for test.
- Test of 2026-10-22 (runtime 0.10.0, Lua 0.16.1), user: "enemy behaviour unchanged". Log: the game's Lua works (state
  at the main menu, our packaged script loaded by the game's require), but behaviour is built at level load per world-
  data desc (AGENTS.md hard rule 20), so neither the probe set nor NLID_0400_CP ever applied. Lua 0.17.0: behaviour
  rows in the world data (survival_events.behaviour_row), probe flights ERA_Unit_08_Dep_Air2 / Air1, heavies only on
  the large-aircraft flights EA_Unit_01_Air1 / Air2. Same test: shop picks, Special purchase (cap 14 -> 16), music
  rotation, pause music player row, tiers (rank 4 -> 2) all worked. Fixed in 0.17.0 / runtime 0.10.0: missiles
  unreadable on the landing menu (shop used the last max seen), landing menu ammo panel shows the caps, pause list
  hides restart checkpoint / select difficulty (QUIT GAME had no row widget), score shown without "/32000", TIME
  row taken from the live panel (the earlier hide found the blueprint's template).
- Test of 2026-10-22 (Lua 0.17.0): "built LA_SV_ProbePursue x1, LA_SV_ProbePursueRt x1; errors 0" - our scripts run.
  But with NLID_0400_CP really applied the fighters stopped attacking (its pursuit needs KDS phases: AGENTS.md rule 22).
  Lua 0.18.0: Survival's own set NLID_SV_Fighter (CFG.behaviour_sets) = NLID_0012_CP + LA_SV_Pursue (Mission 22's
  pursuit without the extend-away after each pass) + LA_SV_MoveAway (2.5 s break instead of 12.5 s). Waiting for a test.
- BUILT 2026-10-22 (Lua 0.16.0), waiting for a test: skill tiers on proven parts (CFG.tiers): Rookie (round 1, rank 1,
  no post-stall), Regular (4, rank 2, no post-stall), Veteran (7, 3), Elite (11, 4), Ace (15, 5); 20 % of pilots
  one tier up; difficulty adds -1 / 0 / +1. PilotRank written live on each enemy (log "tiers:"); post-stall needs
  both the model (CFG.maneuvers) and the tier. The probe's blanket rank 5 is off. Own scripts per tier: below.
- [~] (user 2026-10-22) Survival's OWN behaviour sets (step 2, after the probe proves our scripts load): first one,
  NLID_SV_Fighter, built and confirmed (Lua 0.19.x); per-tier sets and the learning layer not started.
  - Scripts: one LA_SV_<Tier>_<Slot>.lua per slot that differs, in Scripts/ai, packaged at /Game/LuaSource/SurvivalMode/AI
    (tools/build_survival.py LUA_SCRIPTS), built from the stock node factories (AI_BEHAVIOURS.md). Unchanged slots keep
    stock scripts.
  - Sets: DT_NPC_LuaSet rows NLID_SV_<Tier> added at run time (copy of NLID_0000_CP, slots repointed), like the probe.
  - Tiers (first cut): Rookie = extends away after passes, weak evasion, few flares, no post-stall; Veteran = stays
    on target, normal evasion, flares; Ace = KDS pursuit, strong evasion, post-stall only on capable models. Later: roles
    (bomber, interceptor, escort) and the learning layer picking counters per flight.
  - Selection: DT_NPC copies per aircraft x tier (<NpcId>_SV_<Tier>) + build-time mission rows <aircraft>_sv_<tier>;
    main.lua picks the tier by round (config: tier start rounds) and difficulty.

- Lua 0.19.0 (2026-10-22, user: "a bit of lag"): FindAllOf walks every object in the game, and the script ran several
  a second plus a census of ~8000 AI node objects every 10 s. Removed: behaviour census, tree reader, rank probe, the
  dead attacker read, the automatic HUD dump at 15 s (Ctrl+F7 keeps it). Cached: event containers, info panel widgets,
  player controller (searched 1/s at most), difficulty preset; landing-menu ammo panel searched only on the ground at
  the airfield; shop rows every 4 s; menu rows 1/s once in. Waiting for a test.

## Milestone 3: airfield health + bombers (CC)
- [x] Airfield target at ComonaAirport with health 100 (Mission 22's dummies + hit counter; confirmed: 100 -> 96).
- [x] Health bar on the HUD (Survival's own AIRFIELD row + bar; confirmed on screen).
- [x] Bombers attack the airport (Mission 22's strike orders instead of Mission 4's paths; Su-34 hit confirmed).
- [~] (user 2026-10-22) Bomber types: Tu-160 and Tu-95 alongside Su-34 and F-15E; bombers ONLY attack the airfield.
  Su-34 / F-15E spawning confirmed; low approach (500-900 m, Lua 0.20.1) and Tu-95 / Tu-160 bomb runs untested.
- [~] (user 2026-10-22) Bomber raids (Lua 0.22.0): every 3rd round from round 3, ~65% of the round's aircraft are
  bombers in squadrons of 2/4/6 (pool 2/2/4/4/6 incl. EB_Unit_01_Air0), the rest escort. Untested.
  Rows: copy DT_NPC_Mission004's `t160_common` (OP0012_t160_01, PlaneBomb002) and `tu95_common` (OP0011_tu95_01,
  PlaneBomb002) into DT_SV_NpcMission at build time (route A, tools/re/EVENTS_AIRCRAFT.md: no blueprint imports
  needed; the blueprints are soft-loaded from pakchunk0). Su-34 / F-15E bombers use the STOCK rows (6 km search,
  not the fighters' _sv rows). Pool: Mission 22's `ERB_Unit_01_Air2` strike desc + copies, outside POOL; on appearance
  GROUND_ONLY search + LiveAIEngagementOrder Normal on `AB_Unit_01_Ground2`, AIOnly, unit area onto AreaB_MarkActor0
  (Mission 22 records 1686/1694/2037; tools/re/AIRFIELD_SUPPLY.md section 2).
- [~] At 0: landing closed (held while the player is on the ground), HUD callout, back online at 50 after the next
  round. Untested.
- BUILT 2026-10-22 (Lua 0.14.0-0.15.0, runtime 0.10.0), waiting for a test:
  - Target AB_Unit_01_Ground2 (4 invincible dummies) spawned at mission start; SV_AirfieldHit_1..4 (Mission 22's
    MissedWeapon_AreaB_0..3, unlimited, retargeted to Dummy4..7, weapon NormalMissile) add to int flag SV_AirHits and
    light Mission 22's VFX. Lua: health = hp - hits x hit_damage - heavy bomb damage, HUD row AIRFIELD with a bar.
  - At 0: HUD callout, RE_SV_AirfieldClose (landing off) via SV_Event; reopened at repair_hp after the next round.
    Radio: not used (Mission 22's airport lines are tied to its story; subtitles unread).
  - Bomber flights: ERB_Unit_01_Air2 + EA_Unit_01_Air0..2, cut to 2 aircraft; SV_BomberUp_NN = unit area onto
    AreaB_MarkActor0, GROUND_ONLY, engagement Normal on AB_Unit_01_Ground2 AIOnly (Mission 22 1686/2037/1694).
    From round 3, one more flight every 3 rounds (max 3); aircraft su34 / f15e, + tu95 / t160 from round 5
    (rows copied from DT_NPC_Mission004 into DT_SV_NpcMission).
  - Heavies never bomb on their own (research 2026-10-22, build/research/bombers: every stock Tu-95/Tu-160 drop is a
    scripted LiveFireOneShotWeapon WN_WEAPON_4). Lua fires RE_SV_BombRun_NN (both aircraft, 6 bombs) when one is
    within 1.5 km of the runway (20 s cooldown) and takes bomb_damage off 5 s later.
  - Test: log lines "airfield:", "bombers:", "round N: bomber flight"; does MissedWeapon count the Su-34/F-15E
    missiles; do Tu-95/Tu-160 spawn from a fighter desc (their wing/turret child descs are missing); do the bombs fall.
- Test: let bombers hit it to 0; confirm the run continues and the shop flag clears a round later.

## Milestone 4: landing + shop (CC logic, CX config)
- [x] Landing/takeoff at the airport (works with Mission 22's minigame level; confirmed).
- [x] Rearm: NO free rearm since Lua 0.32.0 (user, 2026-10-22: "landing at the airfield is still refilling your ammo
regardless of buying it"): the stock rearm is put back to what the player had (spawn load - fired + bought); shop
packs are consumable, flat price (missiles 12 / 300 Z, special 4 / 400 Z, flares 2 / 150 Z). Untested.
  (Before: the stock rearm, clamped to the caps (confirmed).) Aircraft repair purchase: dropped (user, 2026-10-22).
- [x] (user 2026-10-21) Shop refills to a CAP, not a full load: Casual full load, Standard 32 msl, Ace 20. NO wingman purchase (dropped by user).
- [~] `config/survival.ini` (done by CC, user 2026-10-22: finish Milestone 4): releases ship
  `config/survival.default.ini`, the first run copies it to `survival.ini` (never overwritten by an update); Scripts/main.lua
  reads it at start, before survival_config.lua. Rounds, squadrons, zollars, shop prices, ammo presets, airfield, bombers,
  skill, enemy missiles / guns, HUD, music. Special rotation joins it with Milestone 6. Test: the "config:" log line.
- BUILT 2026-10-22 (Lua 0.15.0, runtime 0.10.0), waiting for a test: credits (CFG.credits: per kill by type, round
  bonus), CREDITS HUD row; shop = 4 rows (DT_SV_ShopRows) added to the landing menu's table
  (DT_LiveMenuIngameHangarCommands, under Yes / No) only while Survival's level is loaded; texts by SV_SetText
  (runtime text hook), picks caught by the inline hook on the landing menu's decide (StringArgs SV_Buy_*) and read by
  Lua (SV_ShopRequest). Items raise the missile / special / flare caps for the run, or repair the airfield.
  Test: "shop:" log lines; do the rows show with their texts; does a pick register; does the help line update.
  Confirmed (tests of 2026-10-22): rows and texts show, picks register, missile / special purchases raise the caps
  (30 -> 38, 14 -> 16), prices rise. Untested: the landing menu's ammo panel showing the caps (Lua 0.19.1), airfield
  repair.
- Test: land, buy missiles, take off, ammo is refilled up to the cap (not past it).

## Milestone 5: difficulty presets (CC + CX) - parked (user, 2026-10-22: "don't worry about milestone 5")
- [~] Casual / Standard / Ace presets on top of the game's difficulty, plus the advanced config (see AGENTS.md).
  Done: ammo caps by difficulty (72/56/6, 48/28/4, 30/14/3), skill tiers shifted -1/0/+1, every setting overridable in
  Scripts/survival_config.lua. Not done: a preset choice of its own, an advanced config UI.

## Milestone 6: special rounds (CC) - user requests 2026-10-20 / 21 / 22. NO allied aircraft or ships in any of them.
Every 5th round is a special round (rotation in config; a special that fails to build falls back to a normal round).
Research: tools/re/SPECIAL_ROUNDS.md (shuttle, LCACs, anomaly ace), tools/re/HELIOS_VFX.md (Helios, portal VFX),
tools/re/EVENTS_AIRCRAFT.md / NPC_DATA.md (aces, Ladon, X-40), Stonehenge's podarge_build (Podarge / Land Aegis).
- [~] Framework (built with the shuttle, untested): round type picked by Lua (every 5th round, CFG.specials.rotation), "SPECIAL ROUND" banner + its name,
  own spawn list per special, its own clear condition (e.g. boss down, shuttle launched), and fail effects (airfield /
  shop closed one round, as at airfield 0). Specials never award real progression.
- [ ] Portal spawn effect for specials: stock teleport nodes + VFX burst (HELIOS_VFX.md 4: run-time spawning from Lua).
- [ ] Event camera on special spawns: the stock camera prompt that swings the view toward an event (node still to find).
- [~] Named aces BUILT 2026-10-22 (Lua 0.30.0, runtime 0.13.1), untested: from skill tier Mercenary (round 16) on a
  fighter flight flies its tier's squadron (tools/build_survival.py ACES: Shark / Ventus F-15C and Su-35, Typhoon;
  Su-47, Savia Rafale; F-22A, Ares Su-57; Shadow Su-57 / Typhoon / Su-47; named-ace Su-57 / F-22A / Typhoon / Rafale
  with Shadow wings). Custom names (user: "build it with this line up, but custom names"): each lead / wing row is a
  DT_NPC copy whose GameObjectDisplayName02 is a Survival text key (SV_Ace_<tier>_<key>, SV_Sqn_<tier>), texts from
  main.lua CFG.aces ([aces.<tier>] in survival.ini) through SV_SetText; the lead (index 0) is the ace when that ace
  isn't up already. They keep Survival's behaviour (world data), AI module, fire control and tier, not NLID_0400_CP.
  Test: "aces:" lines; Su-57 / F-22A etc. arrive from round 16 ([rounds] start_round = 16 to test sooner); the names show on the
  target boxes; "ACE INBOUND" callout.
- [ ] Ladon: the heavy boss (OP0045_ladn_01, 1200 HP, 16 child parts = ChildAIObjectDescs; EVENTS_AIRCRAFT.md).
- [ ] Podarge drop / Land Aegis: port the drop chain the way Stonehenge's podarge_build did (from Mission 25).
- [ ] ECM towers: ground units that jam (radar noise, LiveStartHUDRaderMapNoise) until destroyed.
- [ ] Stealth wing: f22a / su57 / x40a style flight, hidden from radar until close.
- [~] Comona Defense BUILT 2026-10-22 (Lua 0.25.0), untested: round 5 (then every 5th; CFG.specials) spawns Mission 22's
  pad (AA guns, SAMs, tower: user, "you can leave the AA guns in" / "SAMs too and tower") once a run and the shuttle
  (own unit SV_Unit_Shuttle, NPC row OP0057_sstb_01_SV named "EMBDIR Shuttle - CORRIS" via SV_Shuttle_Name) in place;
  its appearance runs Mission 22's countdown radio, ignition, path and liftoff records on delays (150 s); strike
  flights (40% of the round) get the shuttle as target (SV_ShuttleRound flag), fighters the player. HUD: LAUNCH IN /
  SHUTTLE n%. Launched: +3000 zollars. Lost: shop closed through the next round. Removed 180 s after liftoff (user, 2026-10-23).
  Framework done with it: specialFor (rotation), "SPECIAL ROUND n" callout, round clear waits for the special.
  Test: "special:" lines; radio lines play; strikers attack the pad; name shows; liftoff path; next special respawns.
  Removal, 2nd report (2026-10-23, shuttle still up after liftoff): LiveDestroyUnitExecution kills through
  TakeDamage(FLT_MAX) (Execute 0x1473e22c0 -> 0x1473e2840, vfunc +0xa38), and ModifyHealthInternal clamps health at
  MinHealth, so the 1.0 set 20 s before liftoff kept it alive. Fix (untested): RE_SV_ShuttleRemove sets its MinHealth
  back to 0.0 first (as M019/M021/M026 do), then destroys it 1 s later. The pad's objects have no floor in Survival's EP.
  Report 2026-10-23: the shuttle never took damage. It's an AI plane (Blueprints/Vehicle/AI/Plane/OP0057_sstb; its
  durability row NPC_WPDur_001_MS22 takes full damage), and its strike flights got the airport strike's GROUND_ONLY
  search. Fix (Lua 0.37.2, untested): in a shuttle round they search AIR_AND_GROUND with Mission 22's own order on its
  attackers (RE_Wave02_TargetUpdate: AttackOnly, AIOnly) on SV_Unit_Shuttle; Lua logs health / hits / nearest strike
  aircraft every 10 s of the countdown ("special: shuttle N s in").
  Test 2026-10-23 (Lua 0.37.5): strike F-15Es circled 1.4-3.3 km from it for 150 s, 0 hits: Mission 22's shuttle desc
  is an attack-target exception (bIsAttackTargetsException; M22's attacks on it are scripted near misses). Fix (Lua
  0.38.0, untested): cleared on Survival's copy. Same test: liftoff paid, RE_SV_ShuttleRemove fired 182 s after it.
- [ ] (original plan) Comona Defense (shuttle launch, SPECIAL_ROUNDS.md 12a): Mission 22 already is an in-game "defend the shuttle
  launch" mission and Survival's WD / EP are its copies, so the shuttle, its launch path, VFX descs and NPC row
  (sstb_common) are already in Survival's files, switched off. Build from Mission 22's shuttle chain, dress with
  Mission 19's pad VFX. Key callouts only (countdown, pad under attack, liftoff); no allies. Fail = shuttle lost ->
  airfield / shop closed one round. (A shuttle script from another Claude session never reached this repo; 2026-10-22.)
- [~] Amphibious assault (user's pick, 2026-10-22): research done (SPECIAL_ROUNDS.md 12b: Mission 13's enemy LCAC
  chain). Beaches: Lua traces see terrain only near the player (hard rule 27), so the user marks beaches with Ctrl+F10
  (5 marks round Comona Airport, build/research/coast/), and the ground round each mark is sampled with what each trace
  hit (config/coast_rings2.txt) to find the open water. Next: LCAC units (port M13 E_Unit02_02_Ship0 descs, NPC rows
  lcac_common), lanes fleet -> beaches, landing -> troops, the round's rules.
  Failure (user, 2026-10-23): the airfield is captured for 2 rounds (SURVIVAL_SPEC.md section 7).
- [ ] (original) Amphibious assault (SPECIAL_ROUNDS.md 12b): enemy fleet offshore launching LCAC waves at Comona's beaches
  (Mission 13's enemy LCAC pattern; Mission 9's are allies on another map); new paths to Comona's shoreline.
- [~] The Anomaly BUILT 2026-10-22, TESTED (inversion, portal, kill confirmed; Lua 0.36.4, runtime 0.14.1). User's spec: MINDRIPPER in an F-4E
  (OP1003_f04e_Named skin, Survival name key), own HUD warning, mission-update beep at its start, the shuttle's focus
  camera on it. Specials rotate shuttle (5, 15, ...) / anomaly (10, 20, ...). Units SV_Unit_Anomaly (SV_Obj_Mindripper)
  and SV_Unit_AnomalyGuards (4, PHANTASM), copies of a pool flight on the F-4E rows (build_survival.py copy_unit).
  Start (event package): Mission 22's MISSION UPDATE message + focus camera, Mission 15's forced WARNING + radar noise
  (Graph.foreign_template adds their script imports). Field (Lua): within 3 km SV_Invert (BuildFlightInput
  detour) inverts pitch/roll with a 1.5 s fade, RE_SV_AnomalyFieldOn/Off = glasses effect + harder noise; HUD row
  "MINDRIPPER: n KM" / "ANOMALY FIELD: CONTROLS INVERTED". Down: +4000 Z, everything off (SV_AnomalyDown /
  RE_SV_AnomalyEnd). Death: the Celaeno's body-explosion sequence + control-unit collapse (Mission 23 sound events,
  loaded by Lua at level load). Arrival (Lua 0.34.0; user: "the zoom in camera appears, then the portal, then
  MINDRIPPER"): spawned hidden, focus camera at 0.3 s, portal open at 1 s (NS_ElectricSign001 + NS_CloudLightning
  attached, x4), burst at 2.8 s (NS_ElectricDischargeM001 + NS_ms23FarFlash + M27 CoreElectricPlasma), shown; the
  Celaeno core's electricity crackle on MINDRIPPER while it lives. Later (from the user's tests): hidden straight after
  SV_Spawn (it flashed for a tick); hovers (speed coefficients x0.06), +440 HP, turns +120/+270/+25; x5 aggression (own
  _SVX fire control, specials too, pairs of missiles, provoke 0.2 s / 30 deg, surround 20-60 m); E-18G ECM pod (radar
  area); guards on a 2 km unit area following it with a 5 km search module, loosed when it dies; the game's attack
  throttle 8 missiles / 10 attackers / cooldowns 0.5-5 s while it's up (Mission 22 wave-3 values otherwise); its
  lightning systems switched off after their time and at the kill; shuttle camera, ~20 km out (spawn_km optional).
  Ctrl+F11 = Anomaly next round (testing). Open: true orbit of the guards if the area leash isn't enough.
  Test: [rounds] start_round = 10; "special: anomaly" lines; beep, WARNING, camera; inversion inside 3 km; kill.
- [ ] (original) Anomaly ace (boss, SPECIAL_ROUNDS.md 13): floating ace with 5 orbiting guards that attack when the player is
  within ~5 km; inside ~3 km the player's pitch and roll invert (HUD warning, radar noise, glasses effect) until it dies.
  Config: on/off, pitch / roll / both. Research first: where AC8 reads flight input (native flip).
- [ ] Helios barrages on RANDOM rounds (HELIOS_VFX.md 3), targeting the player only, never the airfield. Offline only:
  never touch online services.
- [~] Bomber raids every 3rd round (Milestone 3, Lua 0.22.0): the regular raid, not a special; listed for the rotation.

## Milestone 7: polish, release (CC + CX)
- [ ] CX: ACE8 Mod Launcher toggle, readme, credits (@voidcallsreaper), release zip. (A test zip for a friend exists.)
- [ ] (user 2026-10-21) Ace intro using the user's replay-camera code (location TBD from user): slow-down, tracking shot,
  letterbox, name card, radio line.
- [ ] (user 2026-10-21) Ace learns from your fights: log how the player kills aces (missile/gun/tail/SPW/altitude), save
  across runs (save game or file), next spawn loads the matching LA_ counter variant + a radio line. Reset option in config.
- [ ] End-of-run summary (UI_SHOP_SAVE.md 7): rounds survived, kills, credits, time, best round.

## Milestone 8: Discord leaderboard (after release)
- [ ] End-of-run "Submit to leaderboard? Yes/No" (opt-in, remembered; pilot name in config). Submitted by the Survival
  mod's own native runtime (NOT the Mod Launcher). Sends to a small relay (e.g. Cloudflare Worker) which sanity-checks and
  posts to a Discord #survival-runs channel and keeps a pinned top 10 per difficulty. Offline: queue and send next launch.
  Never contacts Bandai services.

## Allies in the STORE (CC, user 2026-10-23)
"Buy Allied Aircraft from the Store from the Airfield Page ... a Docks Page ... Different Allied Ships that will cruise
around on the water ... expensive ... boost their FCS ... enemies can target these ... F-22's ... spawn in at the
Airfield, Take Off from the airfield ... Squadron ID is MOONCHILD." Built 2026-10-23 (Lua 0.38.0), untested:
- STORE pages in a ring (6 rows a page): SUPPLIES (20) > AIRFIELD (21: + MOONCHILD 15000 Z) > DOCKS (22: Freedom-class
  LCS 12000 Z, Aegis destroyer 20000 Z) > SUPPLIES. Each purchase of one x1.25.
- 0.39.0 (user, 2026-10-23: "remove the LCS Freedom and make it another Aegis, also make the Aegis Lock On faster and
  Fire Rate increase"): DOCKS sells only the Aegis, four of them (A-D, one per M22 fleet lane, the udal lanes the
  Freedoms sailed included); their weapons fly <FCS>_SVA_Aegis: allies.fcs and then arming / lock x lock_x 0.5, shot
  interval / rest x fire_x 0.5 (CFG.allies.ships.Aegis.fcs; stock x0.25 overall, twice the other allies' rate);
  0.39.1: lock-on range 2x stock (range_x 2.0, in place of the allies' 1.6).
- MOONCHILD: 2 flights of 2 F-22s (copies of M22's parked scramble F/A-18s, AB_Unit_01_Air1, not invincible), spawned
  once the player is airborne, 45 s apart; M22's own scramble chain (hold, taxi, roll, climb; PathFinish triggers);
  airborne: gear up, Normal / Default, AIR_ONLY, 40 km search module. Kept out of `planes` (no kill credit, no tiers).
- Ships: two each of M22's own allied hulls (the only ones its WD describes turret by turret; Maya / Ford would need
  their turret blueprints imported, hard rule 7), each on one of M22's enemy-fleet lanes near the airfield, the lane
  restarted at its end; not attack-target exceptions; turrets on Survival's mission rows.
- Fire control: every ally weapon on its own row <FCS>_SVA (CFG.allies.fcs: range x1.6, cone x1.5, times x0.5, gun
  spread x0.4), made at the main menu with the rows.
- Enemies: once MOONCHILD is airborne, half the fighter flights get RE_SV_Hunt_NN (Normal, AIFirst); while ships sail,
  25% of a normal round is strike flights sent at one (RE_SV_Strike<ship>_NN: AttackOnly, AIR_AND_GROUND).
- Test: "allies:" log lines (rows at the main menu, taxiing out, airborne count, losses, hunts / strikes fired).
- Aircraft repair (same build): health written directly too and read back; charged only when it reads full (test of
  2026-10-23: four repairs charged, health stayed 63%).
- Lua 0.38.1 (user, 2026-10-23, screenshots): the landing menu's ammo panel still showed the stock loads (GUN 800, MSL 144,
  FLR 4, QAAM 32): GetWidgetFromName found none of its texts, so its TextBlocks are found by full name under the panel
  and show what you take off with (A.caps); a menu beep on every STORE press (BaseResupply_Decide when bought, General
  Reject when not; PostEventByName). TEST ONLY: Ctrl+F9 +5000 zollars, out of every release zip.
- Lua 0.38.2 (user, 2026-10-23: "increase the max targets on the map to 60"): max_aircraft 60 a round, a hard
  ceiling (difficulty spikes' max_add removed: they still add aircraft_add a round below it).

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
  +0xff4; signature unique) for a native SV_Invert.

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
