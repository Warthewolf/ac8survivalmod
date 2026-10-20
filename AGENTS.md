# AC8 Survival Mode — shared notes for Codex and Claude Code

Both AI agents read this file before working. Keep it up to date.

## Project
A round-based survival mode mod for Ace Combat 8 (PC).
- Waves escalate each round. Every 5th round is a special-enemy round: ace squadron, Ladon bomber, Podarge / Land Aegis drop, ECM towers, stealth wing.
- The player can land at a friendly airfield between rounds and spend credits (earned per kill) on ammo, flares, repairs and wingmen.
- Planned: specials can arrive through a portal (VFX burst, spawn inside the flash, then close).
- Design doc: "AC8 Survival Mode: Design Thesis" (Claude Docs).

## Toolchain
- UE4SS runtime scripts own the state: round counter, credits, shop, landing detection, wave selection.
- IoStore mod loader container: arena map, airfield, spawn points, path sets.
- Config file: wave tables, prices, special rotation, intermission length. Players must be able to edit these without rebuilding.
- Survival Mode is built only from stock game files; nothing from Stonehenge Returns is used or shipped.
- Survival's own build: `tools/build_all.sh` (see tools/README.md). Packages are generated into `mod/Content`
  by `tools/build_survival.py`. Edit that script, not the binaries. The container is `SurvivalMode_P`, packages live under `/Game/Mods/SurvivalMode/`.
- Survival Mode is its own mod: never repoint or override Stonehenge Returns' (or any other mod's) files or mission slot.
- Shared stock tables (DT_LiveMissionTable, DT_LiveMenuMainTopCommands, ...) are never overridden: Survival's rows live in
  its own tables (`/Game/Mods/SurvivalMode/Data/DT_SV_*`) and the Lua runtime adds them with AddRow at run time.
- Native runtime: `runtime/survival_rt.c` (UE4SS C++ mod, plain C + LLVM). It hooks the menu like Stonehenge's main.dll
  (`tools/re/STONEHENGE_MAIN_DLL.md`) and must keep chaining onto Stonehenge's hooks, never replacing them.

## Agreed spec
SURVIVAL_SPEC.md holds the user's confirmed design (menu flow, Comona map, Mission 16 sky, airfield health, enemy roles). It overrides the design thesis where they differ.

## Stock mission reference
Before building any feature, check MISSION_REFERENCE.md. It maps each Survival Mode feature to the stock
event nodes and the mission that already uses them (e.g. LiveSetWeaponAmmoCount in M015 for rearming,
the Supply event in M022 for the shop, M006's wave chain for rounds). node_catalog.tsv lists all 349 node types.
Copy a working stock pattern before inventing a new one.

## Hard rules (learned building Stonehenge Returns)
1. PathPointReceive triggers copied from stock missions never fire. Use PathFinish triggers and exec delays.
2. A stock exit path with a different control type "finishes" instantly. Reuse the inbound path's settings and start new paths a little ahead of the aircraft.
3. Make every ported or spawn trigger one-shot, and turn path warp off. Mission 25's appearance trigger re-fires and warps.
4. Despawn on a timer (about 2 minutes), not at the end of an exit path. (Survival doesn't despawn enemies: they're chased.)
5. Keep ported events in stock order, e.g. release the carried unit before giving it its drop path.
6. The first kill of a counted target doesn't register, so event-flag counters start at 1.
7. New units need their blueprint packages added as imports AND in the container header, including the copy in the data folder.

## Hard rules (learned building Survival Mode, from 2026-10-20)
8. Pad every .ucas so each compression block can be read rounded up to 16 bytes; otherwise the container doesn't mount
   ("Failed reading N bytes at offset ..."). tools/pack.py does it and checks every block.
9. UE4SS Lua `LoadAsset` can't load a mod's new packages (it goes through the asset registry). Use KismetSystemLibrary
   MakeSoftObjectPath -> Conv_SoftObjPathToSoftObjRef -> LoadAsset_Blocking.
10. Tables the game soft-loads (e.g. DT_LiveMenuMainTopCommands) must be loaded, edited and pinned
    (GameInstance.ReferencedObjects) before the game reads them, and watched for reloads.
11. DataTable RemoveRow + AddRow puts a row back in its old slot. To reorder, re-add both rows and check GetRowNames.
12. Confirming the free-mission difficulty runs transition 7, which asks the page's GetNextMenu (vtable 0x111); that hook,
    with the page it's called on, is where Survival starts. Don't rely on the page's decide or on a FindAllOf lookup.
13. The hangar level travelled to must be 10 + the mission row's TravelHangarMap, or the hangar loads unlit.
14. A C++ mod adds Lua functions in `CppUserModBase::on_lua_start(mod_name, lua, ...)` (vtable slot 6 in UE4SS 3.0.1,
    called for every Lua mod before its main.lua runs; check the name). Confirmed by test 11 of 2026-10-21.
15. Setting a world-data AI object's MissionNpcID before spawning changes the aircraft type (any row of the world
    data's NPC table). Confirmed by test 11.
16. A shot-down flight spawns again only after it's taken off the phase's unit list (UnregisterUnit + AActor::Destroy,
    what Survival's SV_Spawn does). Confirmed by test 11, rounds 3-5.
17. Event records name flags (and events) by string, which the game turns into an FName that splits a numeric tail
    ("SV_Up_19" = SV_Up, number 20). Store the flag asset's keys the same way (survival_events.fname), as stock tables
    do, or the flag never matches. Test 11: flights 10-24 were never flagged, so never chased; fixed, confirmed by test 12.

## Spawning (Milestone 2, 2026-10-21)
- Enemies are spawned by Survival's own spawner: the native runtime registers Lua functions (SV_Spawn, SV_SetAircraft,
  SV_UnitAlive, SV_LogUnits) that Scripts/main.lua's rounds call. Don't spawn rounds with LiveReinforcement* event nodes:
  the game never spawns a desc again while its shot-down flight is still on the phase's unit list
  (tools/re/SPAWN_SYSTEM.md has the whole pipeline, offsets and signatures).
- Round settings live in main.lua's CFG. Config hook for Codex: an optional `Scripts/survival_config.lua` that returns a
  table of CFG overrides (wave sizes, intermission, aircraft list, pool); main.lua loads it if present.
- The pool's flights must also be in tools/survival_events.py POOL (that's where they get their attack orders and the
  chase that moves their 6 km unit area onto the player every 6 s).
- No Lua interpreter on the build machine: run `python tools/checks/lua_check.py <file.lua>` after every Lua edit.

## User friendliness (top priority)
- Install through ACE8 Mod Launcher, with Survival Mode as a toggle.
- Difficulty presets (Casual / Standard / Ace) plus an advanced config.
- Clear HUD (round number, credits), radio callouts for specials, an "Airfield open" prompt.
- Readme and credits in every release zip. Issue contact: @voidcallsreaper on Discord.

## How the two agents share the work
- Split by area so they never edit the same files at once. Suggested split:
  - Claude Code: UE4SS scripts and the native runtime (menu, rounds, shop, landing, credits).
  - Codex: config/wave tables, launcher integration, packaging.
- Commit with git after every working test build. Message format: `[agent] what changed`.
- Before starting, pull/read the latest commits and this file.
- Record any new lesson here under "Hard rules" once a test build confirms it.
- Never delete or overwrite game files directly. Work on copies inside this folder.
