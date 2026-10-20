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
- [ ] Round counter flag (FlagInt, starts at 1, see Hard rule 6).
- [ ] Wave spawn from Mission 006's Wave2..Wave6 appear chain, driven by delays/PathFinish only.
- [ ] Round clear when the counted targets reach zero; 45 s intermission timer; next round.
- [ ] Fighters: engagement order targeting the player.
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
