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
  One exception, at the user's request (2026-10-24): the VALKA special may use Ace Combat 7 assets (the X-02S model,
  Mihaly's railgun effects and sounds). Never AC7 voice lines. See tools/re/VALKA.md.
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
18. Survival's HUD is built at run time in Lua (tools/re/HUD_LAYOUT.md). UUserWidget is Abstract: create the base with
    WidgetBlueprintLibrary.Create on a stock widget blueprint, then StaticConstructObject concrete widgets (TextBlock,
    Image, CanvasPanel, ScaleBox, SizeBox) in its WidgetTree. The game's own HUD is not in the viewport (drawn to a
    render texture), and GetCachedGeometry reads back 0x0 from Lua, so place things from the static layout.
    Confirmed by test 13 (2026-10-22).
19. The player's ammo counts are native (the reflected FCS module AmmoCount is only the weapon definition): read and
    set them with SV_Ammo / SV_SetAmmo (runtime 0.7.0, copied from LiveSetWeaponAmmoCount, tools/re/AMMO.md), and turn
    free restock off with SV_FreeRestock(0). The airfield rearm reloads the stock full count, so caps must be
    re-enforced after it, not set once. Confirmed by test 16 (2026-10-22).
20. An AI aircraft's behaviour trees are built when the level loads, one set per world-data AI object desc, from the
    NPC row (-> DT_NPC LuaSetId) that desc names then: 127 aircraft x 15 slots = the 1915 LiveAIBehavior objects
    counted before anything spawned, and each LA_ script's Ctor ran once. SV_SetAircraft at spawn changes the airframe
    and the AI module (search radius), NOT the behaviour, so a flight's behaviour row goes into the world data at build
    time (survival_events.behaviour_row) and its DT_NPC / LuaSet rows must exist before the level loads.
    Confirmed by the test of 2026-10-22 (our probe script loaded but was never built; NLID_0400_CP never applied).
21. The game's own Lua (Lua 5.3, SingleGameluaContext) exists from the main menu, and its require() loads a
    /Game/LuaSource/<A>/<B>/<C> LuaScript from Survival's container: SV_GameLua (runtime 0.8.0) runs code in it.
    Confirmed by the same test ("packaged script via the game's require: true").
22. Don't give ordinary enemies the campaign aces' set NLID_0400_CP: LA_PursueTarget_0400 only attacks inside KDS
    phases (IsKDSP1/IsKDSP2 decorators), which they never enter, so they fly around without attacking (test of
    2026-10-22, the first build where the set really applied). Survival's fighters fly its own set NLID_SV_Fighter.

23. A Lua function (main.lua's main chunk too) may hold at most 200 locals in scope at once: past that the script
    doesn't load at all (UE4SS.log "too many local variables (limit is 200) in main function"; Lua 0.27.2 lost the menu
    entry that way). Put helper groups in `do ... end` blocks that export only what the rest calls. lua_check.py counts
    them and fails over 200. Confirmed 2026-10-22.

24. The hangar (and its wingman panel) look a mission up in the GameInstance's InformationManager_ maps
    (MissionDataMap_ by MissionID, LevelDataMap_ by level id), built from DT_LiveMissionTable at start, not in the table.
    A row added after they were built is missing there: black hangar, then a crash at sortie (AceCombat8.exe+0x79a4153,
    an empty wingman list). main.lua's infoMapsTick adds Survival's row to both. Confirmed 2026-10-22 ("info maps: ...
    was missing 9101 ... added", hangar lit).

25. The native runtime's Lua function names must be 15 characters or fewer: they're registered through a small-string
    buffer and a longer one is skipped (log "function N's name is longer than 15 characters; not registered").
    SV_SetControlInvert never registered (test of 2026-10-22), now SV_Invert. lua_check.py fails the build on one.

26. An event record's conditions are checked when its event fires, not when its delay runs out: records on a delay
    gated on a flag set later never run. Test of 2026-10-22: the shuttle's removal (delay 60 s after liftoff, gated
    on SV_ShuttleLaunched) never ran, so the shuttle and pad stayed up. Fire a remote event from Lua at the right
    time instead (RE_SV_ShuttleRemove).

27. From Lua, a straight-down KismetSystemLibrary.LineTraceSingle only finds terrain near the player: far away it hits the
    sea planes (3-4 m everywhere; the terrain's collision isn't loaded there). Map data for a feature (beaches) comes
    from traces while the player is near the spot (Ctrl+F10 marks + coast rings). Test of 2026-10-22.

28. The player-input detour (runtime BuildFlightInput hook, SV_Invert) inverts pitch / roll in game. The event focus
    camera zooms by distance: the farther its target, the tighter the shot (MINDRIPPER at ~20 km very close, 8-12 km
    wide with ms23-01). Confirmed by the tests of 2026-10-22.

29. Never read a struct field that holds a soft class / object reference from UE4SS Lua (e.g. a menu row's
    MenuWidgetReference): UE4SS copies it through its FSoftObjectPath::operator= and crashed the game at the main menu
    (access violation in FString::operator=, test of 2026-10-23). FindRow + AddRow of such a row without touching the
    field is fine (STORE pages, 20 / 21 in the game's menu list in the same test).

30. GetRowNames from UE4SS Lua may hand back plain strings, not FNames: read names through main.lua's rowList (ToString
    in a pcall, else tostring). A bare n:ToString() errored, the pcall swallowed it, and the STORE fell back to the
    shop rows although its pages were in (test of 2026-10-23).

31. A unit from another mission's world data can be copied whole into Survival's (build_survival.py port_unit: new
    names / UniqueIDs, no tags, our WorldDataName) when its AI objects have no ChildAIObjectDescs: its NPC rows come over
    with NPC_IMPORT and the spawner loads the blueprint from the DT_NPC row, no import needed (Mission 13's LCACs and
    BTR-90s, test of 2026-10-23). New AI paths (make_path, an existing path desc as the template) work for sea craft and
    for ground vehicles over Comona's terrain, and their PathFinish triggers fire, without updating the WD trailer.

32. Ported descs keep their mission's display: Mission 13's LCAC / BTR descs have no bShowHUDBox (no target box in
    Survival, test of 2026-10-23). Set bShowHUDBox and TargetMarkType (ELiveTargetMarkType 1 = TGT) on the AI objects
    (port_unit tgt=True): boxes and TGT marks showed (user, 2026-10-23).

33. Radio lines come from the level's RadioSettings (a hard import in PL_SurvivalMode): Survival's level points it at
    its own copy (DT_SV_Radio; build_radio), and a Mission 25 line played there with its voice (user, 2026-10-23).
    Speakers don't: the game instance holds its own DT_SpeakerTable (BP_LiveGameInstance imports it) and a copy for the
    level changed nothing. A speaker's enemy look is its row's ColorType / ProcessID (Enemy_Fighter_Mob): main.lua
    switches the row at run time while a run is on (CFG.allies.ally_speakers; not yet confirmed). Line IDs ending in
    digits without a leading zero are stored split (v0003_1682 = ('v0003', 1683)), as hard rule 17.

34. A desc copied from another package must not keep object references (('obj', n > 0): an export of that package).
    Mission 16's Ladon path's PathTubeData names its tube object (export 75 there); copied as a path template, the game
    stopped loading Survival at the hangar: LowLevelFatalError AsyncLoading2.cpp:1814 "WD_SurvivalMode_global: Bad
    export index 74/19" (2026-10-23). make_path writes empty tube data; build_wd_global fails on any such reference.

35. A tube path (ControlType 2) with its tube data emptied "finishes" every frame: its PathFinish trigger fired ~30
    times a second and restarted the next path (the Ladons milled about and "bombed" the airfield every second). Copies
    become ControlType 1 (make_path), and aircraft paths need smooth=True (tangents about a leg long, up banked into
    turns, pitch on climbs) or they fly flat, sharp corners. Confirmed 2026-10-23 (user: "Ladons work now").

36. Stock event records can fire a scripted sure kill: Mission 16 fires the Ladon VLS's WN_WEAPON_2
    (BP_wp_vls_certain_ladon) only at the allied F/A-18s it means to kill; aimed at the player, flares did nothing.
    WN_WEAPON_1 is the ordinary missile. Check what a copied LiveFireOneShotWeapon record was for. Confirmed 2026-10-23.

37. LiveAIRequestUniqueAction works on any AI plane, by unit (every plane of it): every unique action's tree is built
    at level start; OneShot ends by itself; Below_Return outranks evading, provoke and pursuit. The stock EnemyBehind
    trigger only fires for the player's selected target and re-fires every frame, so Survival detects "behind" in Lua
    and fires RE_SV_AceTurn / AceKulbit (tools/re/UNIQUE_ACTIONS.md). Confirmed 2026-10-23: the Reaper F-22 went into
    UniqueAction after each and fought ~2 min (26 s before). The player's current target is player+0x1ae8 -> +0x750
    (SV_PlayerTarget, confirmed the same day).

38. Online Mode parts can be mounted on a campaign aircraft: the Ladons' CIWS slots carry the Arsenal Bird's pulse
    cannon pods (class from EB_001's world data via import_from, NPC row in the Ladon's ChildNPCId, the pod's rows added
    at the main menu with the Alicorn's). Confirmed 2026-10-23.

39. Lua can't move or turn a flying AI plane: K2_SetActorLocationAndRotation / K2_SetActorRotation read back right but
    the flight model puts it back the next frame. Mission 22's LiveActorTeleportExecution (target Player, world offset
    in args 4-6, rotation 9-11 roll / pitch / yaw, Absolute) does move it, and it flies on along the new yaw: one
    remote event per spot, Lua picks which (AB.L..IN's RE_SV_GlitchBlink_*). Confirmed 2026-10-23 (25-60 m off the
    spot a tick on, flight path 0-16 deg off the player).

40. LiveFireOneShotWeapon's WN_WEAPON_<n> is fire-control slot n - 1 of the unit's NPC row (Mission 19's Rafale:
    flares, gun, missiles -> WN_WEAPON_3 fires its missiles; the Ladon VLS's WN_WEAPON_1 / _2 its two missiles), and
    it fires an AI plane's gun or ECM pod at the player on command (target Player); delay + loop on the record repeats
    it faster than Lua's 250 ms tick. Confirmed 2026-10-23: AB.L..IN's gun (WN_WEAPON_2) shot at the user in its
    frenzies, its ECM pod (WN_WEAPON_4) was up all fight.

41. An AI plane's wreck meshes (its BP's DamagedMainBodyMesh / DamagedPartsMesh) don't draw while it's alive, even
    shown: hiding the airframe for them left nothing (test of 2026-10-23). For a burnt look, put the wreck's _DAM
    materials on the airframe's own mesh.

42. Assets cooked in our own UE 5.4 (tools/x02s, project ue/Live) must be cooked VERSIONED (no -unversioned):
    AC8 runs Bandai Namco's own 5.4 build, whose reflected properties differ from stock (UTexture's do), so
    unversioned property data is read with the wrong layout and the game stops (LowLevelFatalError AsyncLoading2.cpp
    "ObjectSerializationError ... T_X02S_Valka_NO", 2026-10-24). Versioned (tagged) packages loaded fine the next test.
    New assets that use AC8's materials parent them on stubs at AC8's paths that are never packed.

## Runtime layout (Lua, from 0.66.0)
- `Scripts/main.lua` is only the controller: it holds VERSION and runs the parts `Scripts/sv_*.lua` in its MODULES
  order (tools/lua_split.py made them from the old 7.6k-line main.lua, 2026-10-24: friend's advice "split the runtime
  into modules with a smaller central controller"). Edit the parts, not main.lua. "main.lua" in older notes and hard
  rules means the runtime as a whole; find a function with grep over Scripts/*.lua.
- All parts run in this mod's one Lua state, in order: a name another part uses is a global (no `local`), a part's
  own helpers stay local. A new top-level function another part calls: drop its `local`. Order matters only for code
  that runs at load (top-level statements), as it did in one file.
- Hard rule 23's 200-local limit now counts per part (lua_check prints each part's count).
- Packaging strips test-only code and picks the edition across every part (tools/strip_test_only.py,
  tools/edition.py over Scripts/*.lua).

## Spawning (Milestone 2, 2026-10-21)
- Enemies are spawned by Survival's own spawner: the native runtime registers Lua functions (SV_Spawn, SV_SetAircraft,
  SV_UnitAlive, SV_LogUnits) that Scripts/main.lua's rounds call. Don't spawn rounds with LiveReinforcement* event nodes:
  the game never spawns a desc again while its shot-down flight is still on the phase's unit list
  (tools/re/SPAWN_SYSTEM.md has the whole pipeline, offsets and signatures).
- Round settings live in CFG (Scripts/sv_config.lua). Players edit `config/survival.ini` (made from `config/survival.default.ini` on the
  first run; main.lua's INI_ALIAS maps its sections onto CFG). An optional `Scripts/survival_config.lua` returning a table
  of CFG overrides is loaded after it, for advanced changes.
- The pool's flights must also be in tools/survival_events.py POOL (that's where they get their attack orders and the
  chase that moves their 6 km unit area onto the player every 6 s).
- No Lua interpreter on the build machine: run `python -X utf8 tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/*.lua`
  after every Lua edit (all the parts together: a global one sets is known to the others).

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
