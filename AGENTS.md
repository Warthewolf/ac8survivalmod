# AC8 Survival Mode — shared notes for Codex and Claude Code

Both AI agents read this file before working. Keep it up to date.

## How to work (every task, both agents; user, 2026-11-09)
Start every task with these steps, in this order, instead of starting wherever the task seems to be.
1. **Branch.** `dev` is the working branch. Every task starts from an up-to-date `dev`, on a branch of its own:
   `git switch dev`, then `git switch -c <kind>/<topic>` (kind: `feature`, `fix`, `docs`, `tools`, `re`; topic short,
   kebab-case: `feature/log-bundle`, `tools/env-paths`). One topic per branch.
   - Never work on `main`: it only takes `dev` when the user says a build is good.
   - Never work directly on `dev`, except for a small fix the user asks for there.
   - Don't branch off another topic branch unless the work needs it; then say so in the branch's first commit message.
   - A finished branch is merged back into `dev` (when the user asks), then deleted. A worktree per branch is fine,
     named after the branch.
2. **Read** before changing anything: `git status` and the last commits of the branch; this file; the task's plan in
   `docs/design/`; `docs/design/MISSION_REFERENCE.md` for a game feature; the matching `docs/re/*.md`; HISTORY.md only
   through grep.
3. **Plan first.** A task of more than one step gets a plan in `docs/design/<TOPIC>_PLAN.md` (write it if there is none),
   proposed to the user before any code, and kept up to date as the user decides things. Plans are local working notes
   (git-ignored): never commit one, and never cite one from code, docs or HISTORY.md. Stay inside the task: a problem
   found on the way goes into the plan or a note for the user, not into a silent fix.
4. **No machine path in the repo.** A path that differs from one machine to another (the game, UE, AC7's exports, a
   work folder, a tool's exe, the main tree) is never written into a tool, a script, a doc or this file:
   - tools read it from `.env` (from `.env.example`; shell: `. tools/env.sh` then `sv_need NAME "what it is"`; Python:
     `env.need('NAME', 'what it is')`), with no fallback to anyone's drive;
   - paths inside the repo come from git (this checkout: `git rev-parse --show-toplevel`; the main tree:
     `git rev-parse --git-common-dir`, as `tools/release_dir.sh`);
   - a new setting goes into `.env.example` (commented, with what it is) and `tools/env.py --check`;
   - docs write `build/...`, `<repo>`, or the `.env` name (`$UE`, `$AC7`, `$AC8_DIR`).
   `tools/checks/paths_check.py` (run by `build_all.sh`) fails the build on one.
5. **Check:** `lua_check.py` after every Lua edit, `build_all.sh` (it runs the checks), and the `tools/checks/` tests
   for what changed. Report what passed, what failed and what couldn't be run.
6. **Hand over:** a new version for every build the user gets, the build's notes at the end of HISTORY.md, a lesson a
   test confirms as a hard rule here (see "How the two agents share the work").

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
  Mihaly's railgun effects and sounds). Never AC7 voice lines. See docs/re/VALKA.md.
  A second, at the user's request (2026-11-07: "I want the entire weapon from ACE7 to be ported over"): AC7's
  LaserInterceptor (wp_LaserInterceptor: its values, its swing curve CUR_LaserInterceptorSwingRate, its beam effects
  FX_UAV_TLS_Muzzleflash01/02 with their meshes, materials and textures, and its sounds) for the ZFA-44s' anti-missile
  laser, on AC8's native ALiveLaserInterceptor. Never AC7 voice lines. See docs/re/LASER_INTERCEPTOR.md.
- No other mod's files, assets, tables, values or text go into Survival's build, mod/, tools/, this repo (docs and
  commit messages included) or a release zip, and nothing here names or credits another mod as the source of an enemy
  change (user, 2026-11-06). Survival's enemy changes are its own: designed from AC8's tables and tuned in Survival's
  own tests.
  One exception, the user's own work (2026-11-06: "Alicorn Special Raid IV is my own mod and I NEED the FA44 that is
  within the files of the Alicorn Special Raid as the Model inside is edited"): the ZFA-44 from the user's AC7 mod
  Alicorn Special Raid IV may be used for a Survival special round: its edited model (the mod's
  Vehicles/Aircraft/uavs/uavs_SM, a CFA-44-based static mesh), its paint (fa44_00_D, fa44_00xMREC, fa44_00_Inst), its
  actor ex_uavs and its weapons, with the AC7 stock assets they use. Source: the user's work folder of
  that mod, Alicorn_Special_Raid_IV (unencrypted; on the user's machine, not in this repo). Never AC7 voice lines.
  The same exception (2026-11-07: "Check this mod out, we fixed the Clouds in this one", "in a previous mod we built,
  this happened and we were able to fix it"): the user's own AC8 mod Orbital Tonitrus Spear Strike (RoGLaser) and its
  cloud fix for the Spear's rods (each rod's blast at the clouds' height, the sky's ExplosionEffect as Mission 30's big
  one, a little wider: Scripts/sv_decoy.lua's clouds). Read only, from the user's upload; none of its files ship.
- THE TANICORN (docs/re/TANICORN.md): the user's Anomaly boss fused from AC8's Alicorn and Sea Power's Iowa (standing in
  for the Tanager). Its model and art are in art/tanicorn at the user's request (2026-11-10: "you are allowed to push the
  model"); its cooked container still ships in TANI=1 dev builds only (package_release.sh drops it). Round 30's
  INVINCIBLE FLEET, whose boss it is (docs/design/INVINCIBLE_FLEET.md), is the user's dev install only too (user,
  2026-11-10: "Keep it dev install only"): its Lua in DEV ONLY blocks, never in a release or TESTER zip
  (tools/strip_test_only.py takes them out of every zip; package_dev.sh keeps them; THE TANICORN's test mount too).
- Release zips always go to the main tree's build/release (git's main working tree), from any worktree (user,
  2026-11-07): tools/package_release.sh and package_test.sh find it through tools/release_dir.sh (`RELEASE_DIR` in
  `.env` overrides it).
- The runtime's leaderboard address and key come from the main tree's leaderboard/submit.local from any worktree
  (runtime/build.sh: .env's SV_LB_LOCAL, this checkout's, else the main tree's). Every 0.74.0-0.74.8 build was made in a
  worktree without it and could send no run; package_release.sh online and package_dev.sh now refuse a runtime without
  it (build/runtime/submit_cfg.h). A build's log must say "leaderboard: runs go to ...".
- Survival's own build: `tools/build_all.sh` (see tools/README.md). Packages are generated into `mod/Content`
  by `tools/build_survival.py`. Edit that script, not the binaries. The container is `SurvivalMode_P`, packages live under `/Game/Mods/SurvivalMode/`.
- Survival Mode is its own mod: never repoint or override Stonehenge Returns' (or any other mod's) files or mission slot.
- Shared stock tables (DT_LiveMissionTable, DT_LiveMenuMainTopCommands, ...) are never overridden: Survival's rows live in
  its own tables (`/Game/Mods/SurvivalMode/Data/DT_SV_*`) and the Lua runtime adds them with AddRow at run time.
- Native runtime: `runtime/survival_rt.c` (UE4SS C++ mod, plain C + LLVM). It hooks the menu like Stonehenge's main.dll
  (`docs/re/STONEHENGE_MAIN_DLL.md`) and must keep chaining onto Stonehenge's hooks, never replacing them.

## Agreed spec
docs/design/SURVIVAL_SPEC.md holds the user's confirmed design (menu flow, Comona map, Mission 16 sky, airfield health, enemy roles). It overrides the design thesis where they differ.

## Stock mission reference
Before building any feature, check docs/design/MISSION_REFERENCE.md. It maps each Survival Mode feature to the stock
event nodes and the mission that already uses them (e.g. LiveSetWeaponAmmoCount in M015 for rearming,
the Supply event in M022 for the shop, M006's wave chain for rounds). docs/design/node_catalog.tsv lists all 349 node types.
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
18. Survival's HUD is built at run time in Lua (docs/re/HUD_LAYOUT.md). UUserWidget is Abstract: create the base with
    WidgetBlueprintLibrary.Create on a stock widget blueprint, then StaticConstructObject concrete widgets (TextBlock,
    Image, CanvasPanel, ScaleBox, SizeBox) in its WidgetTree. The game's own HUD is not in the viewport (drawn to a
    render texture), and GetCachedGeometry reads back 0x0 from Lua, so place things from the static layout.
    Confirmed by test 13 (2026-10-22).
19. The player's ammo counts are native (the reflected FCS module AmmoCount is only the weapon definition): read and
    set them with SV_Ammo / SV_SetAmmo (runtime 0.7.0, copied from LiveSetWeaponAmmoCount, docs/re/AMMO.md), and turn
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
    and fires RE_SV_AceTurn / AceKulbit (docs/re/UNIQUE_ACTIONS.md). Confirmed 2026-10-23: the Reaper F-22 went into
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

43. The native runtime's Log / VFmt understands only %s %d %u %x %p (%u from runtime 0.18.1). An unknown specifier takes
    no argument, so the next %s reads a number as a string pointer and the game crashes: 0.18.0's sound log used %u
    and crashed AC8 on VALKA's first sound (test of 2026-10-24); after the fix the same path ran clean.

44. AC8's aircraft skins (master /Game/Base/Material/Vechicle/MP/MP_Live_Vehicle_Base_UDIM) sample Basecolor / Normalmap
    / Livemap as virtual textures (every stock skin texture is a UDIM VT: docs/re/AIRCRAFT_MATERIALS.md,
    tools/checks/tex_info.py). An ordinary texture there draws pure black whatever the instance's values: VALKA's X-02S,
    tests of 2026-10-24 (paint variants 2-5 all black). AC8's general masters (MP_Live_Base_CameraDitherFade, _WPO,
    M_Live_Cha_Base) take ordinary textures on skinned meshes (from their shader maps; not yet seen in game). Don't ship
    virtual textures of our own: the 0.69 container with VALKA's paint as VTs loaded the mission in ~3.5 min and crashed
    AC8 at round 1 (GPUSortBatch, "resize TArray to an invalid size of 2147483648"); the same container with only those
    three textures ordinary loaded in ~33 s and ran a whole VALKA fight (A/B, 2026-10-25).


45. An AI aircraft's railgun shows on the minimap and HUD like a stock one when its LiveFCSModule_LauncherTripleRailCannon
    gets IsDispRadarMap / ForceAlertDisp true and HUDControl 1 (LongRangeRailGun) at run time; Mission 18's
    LiveSetRailgunAlertEnable (true / false) shows / hides the RAILGUN WARNING. Confirmed by screenshots 2026-10-24.

46. A component added at run time draws on an AI aircraft: AActor::AddComponentByClass(SkeletalMeshComponent) +
    SetSkeletalMeshAsset put VALKA's X-02S on the x40a, whose own body is a StaticMeshComponent (AC8's NPC bodies are
    static; the only skeletal meshes on it were the wreck's, which never draw: hard rule 41). Confirmed 2026-10-24.

47. In Lua, `a and f()` / `a or f()` keep only f's first value: `local ok, v = x and pcall(f)` always leaves v nil.
    VALKA's flare and paint variants 9-11 never built that way (test of 2026-10-25, "NOT up (nil)"). Write
    `if x then ok, v = pcall(f) end`; lua_check.py fails the build on the pattern.

48. Survival COOP works over Steam P2P with up to 4 players (test of 2026-10-25, coop.4: host + 3 joiners to round 5):
    joiners' copies of the host's enemies, moved every frame through the AI plane's vtable slot 315 (TeleportTo +
    OnReposition), flew with 0 failed moves and attacked the joiners (user: "Enemies attacked them yes"); joiners' hits
    reached the host (16 of its 28 kills "by wingmate"); rounds, callouts, the airfield and the shop ran on every game.

49. A joiner must not spawn while its Survival level is still loading: the level's LiveUnitSpawner has no world yet and
    the game's spawn ends in UWorld::SpawnActor(NULL) (access violation reading +0x30): two joiners crashed the moment
    the host's first flights arrived (coop.3). SpawnerReady answers SV_ERR_LOADING (-6) while GetWorld is null, and a
    joiner holds the host's spawns until its own plane is in the level + 3 s (coop.4, confirmed the same night).

50. A setting players must write into survival.ini can fail silently (a hand-made file, the default ini edited, a
    restart forgotten): three friends set role = join and still hosted (coop.2). Make co-op need no setting: role auto
    (look for a host, host after 20-40 s, step back on meeting one) linked all three at once (coop.3 and coop.4).

51. A second ALivePlayerPlane (Online Mode's remote-player spawn, docs/re/COOP.md 6) is spawned DEFERRED: give it a
    loadout and call AActor::FinishSpawning, or its weapons have no owner and the first teleport crashes. With role 2
    (another player's) and no network data its own tick holds it at the map's centre; with its actor tick off and moved
    on EVERY input-build call (2-3 a frame, not the first only) it flies solid and smooth beside you, ALLY-tagged.
    Its slot 315 fires OnReposition, which resets a player plane's look: move it with AActor::TeleportTo + the flight
    reset only. Confirmed solo 2026-10-25 (runtimes 0.22.2-0.22.7); not yet the co-op stand-in.

52. The main menu opens a row's page (its MenuID) through ELiveMenuMainIDs, the game's FIXED enum of its pages
    (GameTitle ... CampaignTraining, MAX): a page of a new name never opens, whatever the page list holds (25 presses,
    nothing). New pages borrow a stock id instead: main.dll points that id's MenuWidgetClassList entry (manager+0x118,
    { FString, UClass* } 0x18 each) at the page's class just before the press goes on (SV_MenuClass / SV_MenuSlot).
    The game ignores a request for the page shown, and goes BACK to a page already open under it rather than open it
    again: consecutive pages need different ids (Survival: CampaignTraining, InitialSetting_DualSence,
    InitialSetting_Accessibility), and a BACK row naming the page under it is a working way back. Copies of the main
    menu's top page have no cancel. Confirmed by the tests of 2026-10-29 (runtimes 0.27.0-0.28.3).

53. A remote player plane (role 2) flies itself when its network object's messages are fed each frame before its
    RemoteUpdate (0x147d6f0c0): the physics message *(N+0x98) and the input message *(N+0x170), both pointers (N+0x170
    is a TSharedPtr: writing at N+0x178 hit its reference controller and Quit Mission crashed, test of 2026-10-30). Its
    afterburner glow is plane+0x39d0, reset every frame on a remote plane, so it's written just before the surface
    update (0x147d32b00) reads it. Enemies attack one only when an order names it (Survival's name "Player": your plane),
    and hits on it reach the player plane's damage (0x147d5a430) but are never applied. Confirmed by T1c-T1e
    (docs/re/COOP2MP.md, 2026-10-30).

54. A fast AI plane (the Ladons at 2500 km/h) doesn't take a new path handed over at its last path's PathFinish, even
    one started 2.5 km ahead along its way: it holds the old path's end tangent (0.73.73, the user's test of 2026-11-02
    23:16: legs 0, down to 0.2 km 29 km out), while a slow one does (VOID WATCHER at 450-550 km/h took its climb-out ->
    lead-in handover). Put everything such a plane must fly into the path started at its appearance: the Ladons' route
    carries 15 laps of their circuit (survival_events.LADON_LAPS), and they looped the airfield 4 passes until shot down
    (0.73.75, the test of 23:31-23:39). Confirmed 2026-11-02.

55. The runtime's formatter (runtime/vfmt.h, Log's and Crumb's) must keep reading its input when the line is full: until
    0.32.23 its PUT skipped `*s++` / `t[--n]` past the buffer, so a line over 1,023 characters looped for ever holding the
    log lock. 0.32.22's three new Lua functions made RegisterLua's "Lua bridge: ... registered" line 1,031 characters: UE4SS's
    Lua start never returned, Survival's Lua never ran (no SURVIVAL MODE on the menu) and every later Log waited (the user's
    launches of 2026-11-03 23:33 and 23:48; a crumb before each registration found it). Fixed in 0.32.23, confirmed at 23:54
    (tools/checks/vfmt_test.sh fails on the old macro). A bounded writer must still consume what it's given.

56. Cloudly draws the sky, and sets its sun light, from the level's CloudlySkyParamsAsset (Survival's: Mission 4's
    CSP_ms04_20251218b), copied every frame into the renderer's drawn copy (CloudlyRenderer .Data.SkyParamsRO, and two of
    the seven OurSkyParams) and onto the sun light (rotation, intensity, colour): writes to the renderer's copies, the
    interpolated params or the light are undone within a frame. Its custom sun API (SetCustomSunPosition /
    SetCustomMoonPosition) writes into the asset itself and stays there after the custom flags go off. The exposure (the
    post-process volumes), the level's sky light controller and the MPCs do hold. The user's sky test of 2026-11-07
    (0.74.1, Ctrl+F6: the step-3 read-back undid the copies and the light; step 2 moved the asset to -2 / -105 and gave a
    real sunset in the screenshot; a whole run of the arc on the copies showed no sun move at all and a blown-out night).
    Write the asset (sv_sky.lua v.asset) and put back every value of it: it outlives the level, and the campaign reads it.

57. AC8's music player list shows 120 tracks at most (its scroll list's row limit). With more, the cursor runs on over rows
    that aren't drawn, and a press there reads past the list and crashes the game. The user's run of 0.74.29 (235 tracks)
    saw "Megalith" (row 120) last and crashed at row 231 (UECC AceCombat8.exe+0x7a8dc81), 2026-11-08. The list is also
    built only as a level starts (a world subsystem's Initialize), and each build writes what it lists into the save's
    OwnedMusicList. Survival rebuilds it (SV_MusicBuild) and keeps every list within player_max = 120 (sv_music.lua). The
    runtime cuts those save grants back off (SV_MusicSave). docs/re/MUSIC_BANKS.md.
    Only 2D events can be heard through it: the lobby jukebox's AKE_Bgm_JukeBox_* are 3D (MaxAttenuation 600, 6 m from the
    lobby's prop) and were silent in Alyssa's run of 0.74.30. Online Mode's versions (AKE_Bgm_Online_ACE7_* ...) played in
    0.74.31; build_music_rows refuses a 3D event. A looping event is given 60 s, not -1 (0.74.31: "Hush just abruptly ends").

58. Materials we compile in our own UE 5.4 as new masters (tools/laser7's M_SV_TLS_*: AC7's Cascade beam) stop AC8's renderer
    when drawn: Alyssa's run of 0.74.30 crashed at the ZFA-44s' first volley, on the RHI thread in the Translucency pass
    (UECC AceCombat8.exe+0x34a8d68). AC8 runs Bandai's own 5.4 build, and our shaders don't bind there. Draw with AC8's own
    effects and materials instead: 0.74.31 used AC8's NS_UAVTLS_Muzzleflash01 for the same beam, and it fired and
    intercepted with no crash (2026-11-08). Hard rule 42's parent-on-a-stub route keeps AC8's shaders and stays safe.

59. The game reuses a freed object's address, and liveAddr (SV_ObjChain) passes for whatever lives there now. In the user's
    test of 0.74.34 (2026-11-08) a special's F-15E and Su-47 took dead ZFA-44s' addresses and were fitted with AC7's laser
    (sv_escort_li.lua checked the address alone). An object kept between ticks must still have the name it was captured
    with (ESC.same, sv_escort_laser.lua) before anything is done to it, above all before it's damaged or finished off.

60. A LiveLightningVolume spawned from Lua never struck the player in Survival's level: about 50 s inside one in the user's
    test of 0.74.34 (2026-11-08), nothing on the plane or the HUD. The pause menu hides the HUD, which Lua took for a strike:
    check gamePaused before reading anything as the game's own effect. Survival rolls its own strikes and calls the game's
    pieces itself (sv_anomalies_dev.lua: the HUD's BeginHUDDistortionLightning, the shake, the sounds, the damage).

61. A CHANGE of the sky asset's cloud heights (CloudStartHeightInKm, CloudLayer0-2 StartHeightInKm), rain clouds
    (CloudLayer*.RainCloud*) or rain pillar (RainPillar*) blacks the whole sky out for ~0.1 s. The user's recording of
    0.74.36 (2026-11-08) had a black sky once a second at the storm build-up's writes; the sky probe's recording of 0.74.38
    (21:40:11, Ctrl+/, each group written 3 times) dipped only at the first write of those groups and at their put-back,
    never when the same values were written again, and never for the clouds' light, density, thickness or edges (the light
    greyed the clouds' undersides). The sun, moon, stars and exposure never black it out. Ramp only the safe ones
    (buildup.sky.clouds "safe", sky.unsafe).

62. Cloudly takes another mission's cloud layout mid-level: pointing the level's Cloudly actor's CloudlyVolumeComponentsAsset
    at Mission 12's CVC_ms12_250708 brought its storm clouds in at once (grey overcast round the plane, cumulonimbus towers
    at 10 km) and pointing it back took them away, with the ~0.1 s black blink of rule 61 at each swap; ForceUpdate and
    SetResources weren't needed and blinked nothing. The user's layout-probe recording of 0.74.41 (2026-11-08 22-05-44).
    Swap it only behind a fade (sv_anomalies_dev.lua), never the sky params pointer (sv_sky.lua writes through it).

63. GameplayStatics.ApplyDamage does nothing to AC8's Live objects, and its pcall succeeds: Saint Alessia's co-op run of
    0.74.36 (2026-11-10) "finished off" ZFA-44s 140 times (70 Helios blasts, every carrier leaving) and the same 24 lived
    to round 51 at full health; the shuttle took it and stayed "1 alive" until SV_Recycle. Finish an object with
    sv_core.lua finishUnpaid (mortal, MinHealth field 0, ModifyHealth(-(h / 10 + 1000), nil, true), read back): HealthInternal
    is health x 10, ModifyHealth takes plain health. Never count a kill without reading its health back.

64. A remote event fired while the host's landing minigames run (Landing, Hangar = the STORE, SeamlessOut) runs none of its
    records, though SV_Event answers 1: Saint Alessia's host of 0.74.36 (2026-11-10), STORE 18:47:27-18:48:06: the
    shuttle's T-4 and T (SV_ShuttleLaunched never set) and a flight's appearance orders were lost; events after it took
    with her still on the runway. A one-shot host event that matters is checked by its effect and fired again once the
    STORE is shut (sv_rounds_shuttle.lua SPC.storeShut: the shuttle's liftoff, its removal, the Spaceport's launch).

## Survival's menu pages (Lua 0.71.5, runtime 0.28.3; working in game 2026-10-29)
SURVIVAL MODE opens Survival's own pages (user, 2026-10-27): SP OFFLINE / SP ONLINE / COOP HOST / COOP JOIN / QUICK START,
each but JOIN with a setup page (PRESET, STARTING ZOLLARS, ENEMY AIRCRAFT, ...) and MORE RULES, and a BACK row on every
page. The pages are copies of the game's main-menu page (tools/build_survival.py MENU_PAGES; tools/menu_stock.py finds the
stock), so their presses reach OnMainDecide; they open through borrowed stock page ids (hard rule 52; the user gave
CAMPAIGN TRAINING over completely, 2026-10-29, and its row stays hidden; the two first-start pages get their own class
back when any other main-menu entry is picked). Scripts/sv_menu.lua keeps one run setup per mode (CFG.setup,
survival.ini [setup.*]) that the rounds, store and leaderboard read through SETUP.*. Without the pages ([menu] pages =
false) the main menu has the flat rows. Confirmed 2026-10-29: the pages open, settings step in place and save, BACK
works all the way out. Not yet: B / Esc on the pages (no cancel), a whole run started from a setup page with its rules.
docs/re/MENU_PAGES.md has the design and log lines. Lua tests: tools/checks/menu_test.sh (and coop_settings_test.sh),
the build's: tools/checks/menu_pages_test.py (build_all.sh runs it).

## Survival COOP (Lua 0.70.6-coop.11, runtime 0.26.0, 2026-10-26; played up to coop.4: hard rules 48-51)
Up to 24 players (protocol 3), host-authoritative (after Double Trigger, the AC7 co-op mod), first built on branch
`feature/survival-coop` (merged; the branch deleted in the cleanup of 2026-11-08). docs/re/COOP.md has the RE (AC8's AI plane teleport: vtable slot 315, called every frame on a
puppet; Steam P2P without callbacks; a real second player plane, section 6), the protocol and the test checklist.
Native half runtime/coop.c (SV_Coop*), Lua half Scripts/sv_coop.lua, world-data units SV_Unit_CoopPeerA-X (each other
player's stand-in, an allied AI plane of their airframe: CFG.coop.airframes), name keys SV_CoopName_A-X.
Untested in game since coop.4 (coop.5-coop.11): every RE_SV_* event forwarded to the joiners but each player's own;
SURVIVAL CO-OP: HOST / JOIN on the main menu (OnMainDecide, SV_MenuChoice); names on the stand-ins' target boxes; an
online-style pause; the host's Q batches for up to 24 players; more enemies per player (COOP.more); the host's settings
for everyone (M.sendSettings: CFG's differences from CFG_DEFAULTS, data only); the main menu's settings rows (SV_Set_*,
SV_MenuSetting, iniSet). Build: `COOP=1 NOVALKA=1 sh tools/package_release.sh online <version>` (bump
tools/coop_edition.py COOP_TAG for every build friends get: from runtime 0.32.6 games with different builds refuse to link (coop.c CoSameVer, both ways); before it they linked with a CO-OP VERSION MISMATCH callout, only a different CO_PROTO refusing: two players on 0.73.26 joined a 0.73.27 host, 2026-10-31).
Guards on what other games send (security review of 2026-10-26; keep them when adding messages): coop.c drops any
state with a non-finite or far-off position or a non-unit rotation before it can reach a teleport (CoSaneState), and
refuses another game's message shaped like its own notices to Lua, "sys" / "sys|..." (CoNetPush, runtime 0.32.34);
sv_coop.lua cuts texts, checks slots, zollars, damage and poses, sets only NPC rows this game's DT_SV_NpcMission has
(knownRow) and stand-in rows of CFG.coop.airframes, and takes a host's settings only where the shipped CFG has that
setting with a value of the same type and size (fits; build data and each player's own sections never); a host's
round state ("rnd") only with whole numbers in range (RND_MAX; a huge wave count froze joiners). New messages: give them a
row in tools/checks/coop_guard_test.lua (hostile values in every field, on a host and a joiner). The main menu:
any entry but HOST / JOIN closes co-op; picking one again retries a failed open (SV_MenuChoice counts the picks).
Checks without the game: `sh tools/checks/coop_test.sh` (the transport, 4 and 12 players over lossy UDP; Linux too),
`sh tools/checks/coop_settings_test.sh` (the settings sync, rows and scaling on the real parts) and
`sh tools/checks/lua_load_test.sh [mod folder]` (every part of main.lua loads). The last two run on a real Lua 5.4.6
that tools/checks/lua_build.sh builds into build/checks (there's no Lua on the build machine otherwise).
Player guide: Claude Docs "Survival COOP: Player Guide".
Since the behaviour branch's code review (2026-10-29, TestBranch_Behavioural; untested in game, not a hard rule): the
host down at the airfield no longer holds the room while another player flies (sv_rounds.lua othersFlying: alive,
fresh, not on the airfield). The spawns go on, a flight's orders fire (RE_SV_FlightOrders_NN every 5 s while the host
is down, not counted as tries), the wave clock runs, the ALICORN's deck launches, a Wolf trap is held after its orders
and the shuttle's countdown runs, the shuttle not invulnerable then (user, 2026-10-29: "Keep it running while others
are flying"); solo, or with nobody else flying, all held until the takeoff as before (user's question of 2026-10-29:
Shazzy's host log had 10-43 s holds). The CO-OP row is behind the HUD's info key (I), with a line a player when open
(docs/re/COOP.md section 7, docs/re/HUD_LAYOUT.md).

## Leaderboard
leaderboard/README.md has the deploy steps (paste src/index.js; the Worker makes its new tables itself). The Worker takes
co-op versions (0.72.2-coop.20), has an admin page for the user only (GET /admin; ADMIN_KEY in the POST body, 5 wrong
keys lock an address out: reset (archived, undoable), restore, builds, verification), and counts a run only from a
registered build: the runtime hashes the mod's files (runtime/build_hash.c, the same as tools/build_hash.py:
tools/checks/build_hash_test.sh) and sends X-SV-Build, signed with the run; package_release.sh online writes
<zip>.buildhash.txt to register. Register every zip given out before players send runs from it. The game doesn't send
an edited run (LB.edited: gameplay settings against CFG_DEFAULTS, a survival_config.lua, test keys;
tools/checks/leaderboard_test.sh): a new setting that's only on screen or each player's own goes in its free lists.
The Worker is deployed with the co-op boards; packaging registers every build itself (tools/lb_register.py, the
admin key from the main tree's leaderboard/keys.secret). leaderboard/README.md has the rest.

## Runtime layout (Lua parts from 0.66.0; families and the native parts from 2026-11-07)
- `Scripts/main.lua` is only the controller: it holds VERSION and runs the parts `Scripts/sv_*.lua` in its MODULES
  order (tools/lua_split.py made them from the old 7.6k-line main.lua, 2026-10-24: friend's advice "split the runtime
  into modules with a smaller central controller"; confirmed in game the same day, 0.66.0: a full
  VALKA round ran). Edit the parts, not main.lua. "main.lua" in older notes and hard
  rules means the runtime as a whole; find a function with grep over Scripts/*.lua.
- All parts run in this mod's one Lua state, in order: a name another part uses is a global (no `local`), a part's
  own helpers stay local. A new top-level function another part calls: drop its `local`. Order matters only for code
  that runs at load (top-level statements), as it did in one file.
- Hard rule 23's 200-local limit now counts per part (lua_check prints each part's count).
- Packaging strips test-only code and picks the edition across every part (tools/strip_test_only.py,
  tools/edition.py over Scripts/*.lua).
- No source file over 2,000 lines (a contributor, 2026-11-07: "not maintainable for human or AI";
  tools/checks/size_check.py fails build_all.sh on one). tools/lua_split_part.py split sv_coop.lua (+ _joiner,
  _planes, _sync, _migration), sv_config.lua (+ _specials: CFG.specials / sky / music / hud as `CFG.<key> = {...}`
  statements; + _ini: CFG_DEFAULTS, survival.ini, TIER / ROLE / ACE / GLS) and sv_anomalies.lua (+ _valka; + _dev,
  the test-only lightning Anomaly, only its header left in a release). A part's family is the part and the MODULES
  entries right after it named <part>_<topic>. Tools that read or patch a part's text go through tools/lua_parts.py,
  the Lua tests through tools/checks/parts.lua (PARTS.load / read / dofile; each source edit applied in the piece that
  holds it). A local one piece uses from another is a global (check no other part has that name). sv_coop's M stays
  local, handed on as COOP.M (`local M = COOP.M` atop each later piece), because sv_flights' music state is the global
  M. To split again: a PLANS entry in lua_split_part.py, the analysis first, every TEST ONLY / ONLINE ONLY block whole
  in one piece.
- The native runtime (2026-11-07, runtime 0.32.24, no code change): runtime/build.sh still compiles survival_rt.c alone
  as ONE translation unit, but the files over 2,000 lines were cut at section boundaries into parts #included in place,
  so statics and code order are unchanged (the split built the same main.dll but for its link timestamp, and the same
  map). survival_rt.c is the spine: helpers, log, crumbs, patching, menu handlers, the Lua bridge's argument helpers,
  RegisterLua's table (lua_check.py reads it there), install and the mod object; RT_VERSION stays in it for build.sh and
  the package scripts. In order it includes survival_rt_game.c (spawner, teardown gate, recycles, unit descs, ammo,
  music, remote events, the game's Lua), coop.c (+ coop_lua.c: co-op's Lua functions and the second player plane),
  flight.c (+ flight_coop2mp.c: the real planes and their weapons; + flight_guards.c: the game-bug guards and the STORE
  freeze) and survival_rt_lua.c (sound, the SV_* Lua functions, the leaderboard). Edit the part, never compile one on
  its own, and add an #include where the code belongs to keep a file under 2,000 lines.
- The Python generators (2026-11-07; output byte-identical to the single files: 67 packages, sv_menu_stock.lua,
  stdout, the importing checks): tools/survival_events.py keeps the shared names, the record helpers and Graph,
  build_events, write_records and the builders the Lua tests read as text (heavies, jammer, raid pings, Spaceport
  Assault, run-over); its parts survival_events_specials.py (LCAC, Ladons, Alicorn, Anomaly, AB.L..IN, VALKA, shuttle),
  _squads.py (review orders, ace moves, Wolf, director, tells, Wraith, allies, VOID WATCHER), _festival.py and
  _escort.py are imported at its end with `from <part> import *`, each starting with `from survival_events import *`.
  tools/build_survival.py keeps the folders and package helpers, shop rows, menu pages, NPC rows and table, behaviour
  scripts, read-back checks, main and every function reading STOCK / OUT / ROOT / MENU_STOCK* / AI_SRC
  (menu_pages_test.py sets them on build_survival); its parts build_survival_rows.py, _units.py and _world.py work the
  same way (run as a script it registers itself as build_survival first). survival_events.X / build_survival.X still
  name everything: import the main module, never a part (a guard asserts it). A part's functions see the main module's
  names above the part's import, and earlier parts' names only. The Lua tests grep the two main modules' text
  (coop_fire, coop_revive, defences, escort, heavy, roles, spaceport, spweapons), so their anchors stay there.

## Subtitles file (0.74.24)
Every subtitle line ("SPEAKER|text" in CFG.specials.*) and the speaker names live in `config/subtitles.ini`, the file the
user and her friends edit (user, 2026-11-08: "I want my friend to be able to edit all these subtitles easily").
Scripts/sv_config_subs.lua reads it over CFG's own lines before CFG_DEFAULTS is taken (no leaderboard or co-op difference;
not in the build hash) and changes only subtitle lines and the speaker names. The repo's file is what ships and wins over
the Lua: change a shipped line in the file, not in sv_config_specials.lua. A new list of lines in Lua:
`python -I tools/subtitles.py merge`. The user's or a friend's edited install: `python -I tools/subtitles.py pull`; run
`diff` before installing a build over her install, or her edits are lost. build_all.sh runs `tools/subtitles.py check`;
tools/checks/subs_test.sh tests the part. The file is made from a release's copy of the parts (no test-only lines).

## Spawning (Milestone 2, 2026-10-21)
- Enemies are spawned by Survival's own spawner: the native runtime registers Lua functions (SV_Spawn, SV_SetAircraft,
  SV_UnitAlive, SV_LogUnits) that Scripts/main.lua's rounds call. Don't spawn rounds with LiveReinforcement* event nodes:
  the game never spawns a desc again while its shot-down flight is still on the phase's unit list
  (docs/re/SPAWN_SYSTEM.md has the whole pipeline, offsets and signatures).
- Round settings live in CFG (Scripts/sv_config.lua). Players edit `config/survival.ini` (made from `config/survival.default.ini` on the
  first run; main.lua's INI_ALIAS maps its sections onto CFG). An optional `Scripts/survival_config.lua` returning a table
  of CFG overrides is loaded after it, for advanced changes.
- The pool's flights must also be in tools/survival_events.py POOL (that's where they get their attack orders and the
  chase that moves their 6 km unit area onto the player every 6 s).
- No Lua interpreter on the build machine: run `python -X utf8 tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/*.lua`
  after every Lua edit (all the parts together: a global one sets is known to the others). To run Lua code,
  `sh tools/checks/lua_build.sh` builds a Lua 5.4.6 (UE4SS's) from lua.org's source into build/checks/lua.exe;
  `sh tools/checks/lua_load_test.sh` then loads every part outside the game, with the game's API stubbed.

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
- Every build the user is handed gets its own version (user, 2026-11-07: "update the version number each time you
  hand me a new file"): `python -I tools/bump_version.py` (main.lua VERSION's last number + COOP_TAG, together;
  --minor for a new feature line) BEFORE build_all.sh; package_release.sh refuses a zip name that already exists
  (REPACK=1 only to remake the same build's zip). Never two different builds under one version.
- Before starting, pull/read the latest commits and this file.
- Record any new lesson here under "Hard rules" once a test build confirms it.
- Never delete or overwrite game files directly. Work on copies inside this folder.
- Record each build's notes at the END of HISTORY.md, never here: AGENTS.md keeps only the rules, the layout and the
  how-tos, because every session loads it whole. A lesson a test confirms goes here as a hard rule.
- No source file over 2,000 lines (tools/checks/size_check.py, run by build_all.sh): split a growing file at a topic
  boundary (Runtime layout, below).
- Your machine's paths and keys are in .env (from .env.example; tools/env.sh, tools/env.py), never in a tool, a doc or
  git ("How to work", step 4). CONTRIBUTING.md has the whole setup.

## Build history and feature notes
Every build's notes are in HISTORY.md, oldest first: the economy review (0.70), the enemy behaviour layer (0.72),
COOP2MP's T1-T4 and every build since, through the newest. It isn't loaded into sessions (it was most of this file's
~190 KB): grep it for a version, a feature or a log line, and read only the entry you need. Each feature's design,
reverse engineering, log lines and test checklist are in docs/re/*.md (COOP.md, COOP2MP.md, BEHAVIOUR_DIRECTOR.md,
ESCORT.md, FISHING.md, DECOY.md, SPACEPORT_ASSAULT.md, ZFA44.md, THUNDER.md, VALKA.md, ...).
- (Git) From 2026-11-09 `dev` is the working branch and every task gets its own branch from it ("How to work", step 1);
  `main` takes `dev` when the user says a build is good. The 2026-11-08 cleanup merged the old branches or kept them as
  `archive/*` tags. COOP2MP is the build line's name (COOP_TAG, BUILD_NAME), no longer a branch.
- COOP2MP is the working main since 2026-10-30: the other players fly as real player planes (ALivePlayerPlane fed from
  their stream, their weapons replayed from their own plane), the AI stand-ins only as a fallback. VERSION 0.7x.y with
  COOP_TAG -coop2mp.N (tools/coop_edition.py); friends' zips: BUILD_NAME=COOP2MP COOP=1 sh tools/package_release.sh online
  <version> (ZFA=1, SONG=1 as the build has them); the user's own install: VALKA=1 ZFA=1 sh tools/package_dev.sh <version>.
- The enemy behaviour layer: fighter roles, the squad director, tells, intensity, learning, boss phases, late rounds
  (docs/re/BEHAVIOUR_DIRECTOR.md); each mechanism has its own `enabled` in survival.ini.
