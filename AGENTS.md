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

43. The native runtime's Log / VFmt understands only %s %d %u %x %p (%u from runtime 0.18.1). An unknown specifier takes
    no argument, so the next %s reads a number as a string pointer and the game crashes: 0.18.0's sound log used %u
    and crashed AC8 on VALKA's first sound (test of 2026-10-24); after the fix the same path ran clean.

44. AC8's aircraft skins (master /Game/Base/Material/Vechicle/MP/MP_Live_Vehicle_Base_UDIM) sample Basecolor / Normalmap
    / Livemap as virtual textures (every stock skin texture is a UDIM VT: tools/re/AIRCRAFT_MATERIALS.md,
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

51. A second ALivePlayerPlane (Online Mode's remote-player spawn, tools/re/COOP.md 6) is spawned DEFERRED: give it a
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
    (tools/re/COOP2MP.md, 2026-10-30).

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
tools/re/MENU_PAGES.md has the design and log lines. Lua tests: tools/checks/menu_test.sh (and coop_settings_test.sh),
the build's: tools/checks/menu_pages_test.py (build_all.sh runs it).

## Economy review build (Lua 0.70.x, runtime 0.19.0, 2026-10-25; untested in game)
The Claude Docs "Economy, Enemies & Allies Review"'s proposals, all built on branch `feature/economy-review`: waves,
late-round scaling, raids from one direction with escorts, the jammer, more airframes, kill attribution by side
(DamageHistoryMap), WINGMEN, ally orders, repairs between rounds, FULL REARM, upgrades, tactical items, SECOND CHANCE,
a 5-page STORE. tools/re/ECONOMY_REVIEW.md lists every mechanism and the log lines to check. None of it is a hard rule
until a test confirms it. A build without VALKA: `NOVALKA=1 sh tools/package_release.sh online <version>`.
`python -X utf8 -I tools/checks/ini_check.py` checks survival.default.ini against CFG (build_all.sh runs it).

## Survival COOP (Lua 0.70.6-coop.11, runtime 0.26.0, 2026-10-26; played up to coop.4: hard rules 48-51)
Up to 24 players (protocol 3), host-authoritative (after Double Trigger, the AC7 co-op mod), on branch
`feature/survival-coop`. tools/re/COOP.md has the RE (AC8's AI plane teleport: vtable slot 315, called every frame on a
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
state with a non-finite or far-off position or a non-unit rotation before it can reach a teleport (CoSaneState);
sv_coop.lua cuts texts, checks slots, zollars, damage and poses, sets only NPC rows this game's DT_SV_NpcMission has
(knownRow) and stand-in rows of CFG.coop.airframes, and takes a host's settings only where the shipped CFG has that
setting with a value of the same type and size (fits; build data and each player's own sections never). The main menu:
any entry but HOST / JOIN closes co-op; picking one again retries a failed open (SV_MenuChoice counts the picks).
Checks without the game: `sh tools/checks/coop_test.sh` (the transport, 4 and 12 players over lossy UDP),
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
(tools/re/COOP.md section 7, tools/re/HUD_LAYOUT.md).

## Enemy behaviour build (Lua 0.72.0, TestBranch_Behavioural; untested in game)
The Claude Docs thesis "AC8 Survival Mode: Enemy Behaviour Reference & Challenge Thesis"'s nine proposals, all built on
branch `TestBranch_Behavioural` (from tag stable-1, 2026-10-29), COOP_TAG -coop.18: fighter roles (P1: the pool split
into Duelists, Lancers, Wolf bait-and-trap pairs and Skirmishers, each its own behaviour set and airframes; 7 new
Scripts/ai scripts), the squad director (P2: cover the tailed, spring the trap, bracket salvos, top cover, pincers,
regroup; Scripts/sv_director.lua), tells (P3: a radio line before each threat, 61 stock lines cloned into DT_SV_Radio,
no HUD callout since the clean up below; Scripts/sv_tells.lua, co-op "tl"), the intensity director (P4: each player's
intensity and comfort, wave holds, pushes, the spikes as a ceiling; co-op "in"), a harder tailed plane (P5: every reaction pick moves, live provoke
60 deg / 1.5 s from Veteran, a 4 Hz tail watch), the learning layer (P6: your habits countered, kept in
config/survival_profile.ini, each game's own), boss phases (P7: MINDRIPPER's pack, AB.L..IN's three phases, a Ladon's
rage, the ALICORN's deck launches), late rounds (P8: +3 aircraft a round from 26 to 60 by 35 in more waves, health
capped at x1.5, the attack throttle's presets) and ace personalities (P9: each squadron's own roles, an opener at first
contact after its tell, Wraith's and Harvest's lead blinking off your six), plus the roadmap's seven measurements
(Scripts/sv_stats.lua: `stats:`, `kill-time:`, `death:`, `tailed:` lines). Every mechanism has its own `enabled` in
survival.ini but two that are build data: P5's reworked reaction trees (LA_SV_ProvokeNear / LA_SV_Escape are packaged
and built at level load, hard rule 20; `[ai] reactions = false` gives the stock 0012_CP ones, not stable-1's; P5's live
provoke has its own, `[ai] tier_provoke`, `provoke_stricter`, `provoke_cone_deg` / `provoke_time_s`) and P1's Lancer
band (the six Lancer units' 9 km in the world data, kept with `[roles] enabled = false`).
tools/re/BEHAVIOUR_DIRECTOR.md has each unit's build, CFG keys, log lines and untested pieces, and one
test checklist for the whole branch (per proposal: what to look at in game, which log lines prove it);
`python -X utf8 -I tools/checks/stats_report.py <log>` tabulates a test log. None of it is a hard rule until a test
confirms it. Checks without the game: the contract's (lua_check on Scripts/*.lua and Scripts/ai/*.lua, shapecheck on
changed behaviour scripts, lua_load_test, menu_test, coop_settings_test, coop_ground_test, ini_check, menu_pages_test),
each unit's own (stats_test, tailed_test, late_rounds_test, tells_test, roles_test, director_test, intensity_test,
profile_test, bosses_test, aces_test, and the code review's coop_landing_test, hud_info_test: tools/README.md's checks
row), coop_test, and a full `sh tools/build_all.sh` (819 triggers, 1588 execs, 721 radio rows). shapecheck isn't in
the repo: `python shapecheck.py <file>` from build/research/ai/survey/ (research output on the build machine with the
stock LA_ scripts it reads, gitignored with build/); build_all.sh doesn't run it.
Code review of 2026-10-29 (fix units F1-F7 on the same branch, no VERSION / COOP_TAG bump; untested in game;
BEHAVIOUR_DIRECTOR.md's last section has each fix, its log lines and what stays open): Bounty's Lancers and Valkyrie's
Wolf pairs are never turned by the director's cover or P4's push (ROLE.ownSet: only Harvest's tier keeps its levers on
a role flight); the ALICORN's railgun and VLS tells, warning, orders and volleys stop once those parts are destroyed;
a joiner's Skirmisher cut is no longer sent to the host as a hit; the learning profile's file is written whole and never
lost (.tmp / .bak / .old); cover and the trap work for joiners past [director] players 4; a host down at the airfield no
longer holds the room while another player flies (the co-op section above); and, at the user's request, the HUD info
key: I ([hud.info]) keeps the CO-OP, ALLIES and ITEMS rows hidden until pressed, each shown peek_s 5 when its news
changes, open the CO-OP row has a line a player (tools/re/HUD_LAYOUT.md; a release key, not a test key; keyboard only).
Clean up of 2026-10-29 for the next build (user, playing 0.72.0: "remove the hud warnings that we added, it's too much,
keep the Voice lines though", "keep the bomber direction warnings"; not yet run in game; BEHAVIOUR_DIRECTOR.md's "Clean
up of 2026-10-29" section): every tell is a radio line only (CFG.tells' hud / urgent / text and the HUD's urgent path
gone, the HUD-only lancer / skirm / split tells and [roles] tells too, the ALICORN's deck and a Ladon's rage callouts),
one gap (radio_gap_s) between any two tells, a `sure` tell (a boss's phase, a squadron's first call) said through the
gap and its cooldown; "tl" carries one number. stable-1's callouts stay (ROUND, the specials', BOMBER RAID FROM THE
<DIRECTION> and the NEXT row's raid line), as do the stock RAILGUN WARNING and the I key. Quieter logs: `[log] verbose =
false` (CFG.log, logVerbose()) keeps out the `ai:` lines, the flags line on every counter's change, the enemies alive /
nearest and the intensity scores every 10 s; `ammo: now` comes at most once a minute, `perf:` every 5 minutes; true
brings them all back.

0.72.1-coop.19 (runtime 0.28.4; the user's requests while playing 0.72.0, 2026-10-29; none of it run in game yet): that
clean up; the music player's pause hold from Survival's spawner's game instance (it never engaged before: every log's
"clock held 0 ms"; tools/re/MUSIC_RADIO_CAMERA.md); SV_Version() the build's own version (was a fixed "0.27.0"); the
heavy bombers' routes over the runway and figure-8s across it (tools/re/AIRFIELD_SUPPLY.md 2); the jammer's ECM pod
fired every 14 s (RE_SV_JamEcm_NN); the Ladons' VLS missiles 10 damage, half the turn rate, also on pooled ones in
flight; co-op stand-ins wait up to 5 s for their player's airframe (COOP.md 5); stronger AA guns / SAM sites and a STORE
CIWS at four spots by the runway on a new DEFENCES page (AIRFIELD_SUPPLY.md 4). Planned next (researched, not built):
co-op weapon / gear / afterburner sync and a co-op revive with a spectator camera.
0.72.2 (runtime 0.28.5; the user's co-op requests of 2026-10-29; not yet run in game): each player's missiles, gun,
flares, gear and afterburner shown on their stand-in on the other games (tools/re/COOP.md 8: "fx" shots relayed by the
host, state bits 16 / 32 / 64 / 128, SV_CoopFire / SV_InputNow; the stand-ins fly damage-0 `<row>_svcp` rows, a
joiner's "ht" backstop; [coop.sync]; tools/checks/coop_fire_test.sh); co-op revives (Scripts/sv_down.lua, COOP.md 9):
held at a 0.1 HP floor, a shot-down player is DOWN (hidden, flown round the airfield by SV_Down, watching another
player's plane through a camera added to it, O the next), any other player at their airfield buys them back from the
STORE's AIRFIELD page (REVIVE <NAME>, 5000 x 1.5 a revive (2500 x 1.25 since the user's "lower the cost for reviving", 2026-10-30), checked by the host: dw / rv / rb / rx / ro / rc), everyone
down ends the run (RE_SV_RunOver, Mission 15's MissionFailed); [coop.revive]; tools/checks/coop_revive_test.sh.
After 0.72.3 (the user's co-op run of 2026-10-30, not yet a build): the revives' floor never held, because the game's
SetMinHealth keeps whole health points only (0.1 -> 0; tools/re/KILLS_HEALTH_DEATH.md 1): the host was shot down from
40 HP in round 8 and the run restarted at round 1. INS.tick now writes the MinHealth field. The shuttle's whole pad
is taken off after liftoff (its objects recorded as spawned; the 1.5 km sweep missed the control centre).
0.72.4 in game (the user's co-op run of 2026-10-30, 13 players): the floor held and revives worked (VERDA DOWN at
13:38:56, revived by the host from the STORE at 13:41:22), but VERDA had crashed into the ground, so the loiter never
lifted the plane and respawn loiter brought them back where it lay. Since then (not yet a build): a DOWN plane slower
than 40 m/s (or under the sea) for 3 s comes back the native way (SV_Respawn 4 km out from the runway, 500 m up).
The same run, the host DOWN in round 6 (runtime 0.28.6): the loiter flew the plane upside down at 15 m over the sea out
of the combat zone (its roll probe read -3 / +2 deg/s as a sign: wrong), the mission failed and restarted in round 7 in
the same level with the SAME plane, which stayed hidden (no third-person view) with its weapons off. Runtime 0.28.7 (not
yet run in game): longer probes, DN_MIN_DIFF 10, an in-flight sign check (rates against the inputs flip a sign) and a
dive backstop (tools/checks/flight_test.c's late plane and wrong-signs runs); sv_down.lua puts the plane and view back
after a restart while down (restoreAfter), remembers your own view as you go down, and puts a DOWN plane 8 km from the
combat zone's edge back over the airfield (edgeGuard, SV_Respawn).
The same run's logs (the host and 7 joiners, 0.72.4-coop.22 / runtime 0.28.6; report: Claude Docs "AC8 Survival Mode:
Co-op Play Session Report, 30 Oct 2026"): enemy copies never failed a move; Shazzy's DOWN probe read -2 / +1 deg/s as a
roll sign too (inverted); reliable resends tracked the round trip (fixed 250 ms timer: 4-7 % resent past 290 ms); a lost
link was flooded (20,892 resends a minute); the host streamed planes and enemies to players in menus or loading (one on
Stable 1 for 14 minutes); joiners kept their money and upgrades through the host's restart; 1,093 of 1,094 refused
remote shots came while that player was in the STORE; the Lua tick averaged 9-30 ms (worst 86-493 ms), "shop" / "icons"
/ "ammo panel" walking every object down at the airfield. Changed since (not yet a build, not yet run in game): runtime
0.28.7's coop.c (CoRto: resend after the round trip x 1.5 + 100 ms, backing off; a lost link gets its oldest reliable
message only; CoWantsState: Q and E only to a joiner whose plane is in the level; CoTrackOffset / CoRenderDelay: each
sender's interpolation delay follows its lateness, CO.delay to 300 ms; new log lines `enemies drawn N ms behind the host
(lateness N ms)` and `coop: planes here ...`), sv_coop.lua (a joiner's run starts over on the host's new run:
newRunHere; others' shots not asked of the game while your STORE is open; the afterburner flip logged once),
sv_core / sv_shop / sv_main (landingWindows once a tick; the relabel reads the STORE rows' TextBlocks only, at once after
a press, else every 2 s; shop texts every 0.5 s at the airfield; an ammo panel looked for 3 times at most; the perf line
names every part by its share and the untimed rest).
0.72.5-coop.23 (runtime 0.28.7; the user, 2026-10-30, after that run: "EA-18G player used his ESM and it didn't show up
for any of us"): an ESM / jamming pod fires no projectile, so the weapon sync never saw it; now a special weapon's count
dropping with nothing new in flight is sent as `e` and fires the stand-in's ECM pod (tools/re/COOP.md 8). Not yet run.
0.72.6-coop.24: a new DOWN clears the last revive's 15 s guard (a player down again within 15 s of a revive was refused
"ALREADY BEING REVIVED"); the revive test now has a joiner reviving the host (never run in game: in the run of
2026-10-30 nobody bought the host back).
Since 0.72.6 (not yet a build or run): the user, "someone who was flying the FA-36 was registering as flying the F-16"
(it was gloom, and xX_spagooterpoop_Xx): 12 of AC8's 34 player planes (BP_PlayerPlane_PPnnnn_<code>, build/research)
weren't in CFG.coop.airframes, so their stand-ins flew the default F-16C. Now all but the ADFX-02 (no AI plane): 10 new
stand-in rows from the plain campaign enemy rows (build_survival.py POOL_EXTRA: OP1018_fa36_01 ...), the F-14A on the
F-14D; an unlisted plane is logged; a hello sent with no plane is followed by the airframe (sendHi keeps M.myRow).
The plain EA-18G row (OP1010_e18g_01) has NO ECM pod (only the named aces' rows carry NPC_FCS_ECM000): the stand-ins'
copies of the EA-18G / EA-36 / E-6B get it in their first free slot (the ESM display), and the enemy jammer's rows get
the held-up pod in slot 3, which RE_SV_JamEcm fires (it fired the random special weapon there before).
0.72.7-coop.25 (runtime 0.28.7) = all of the above: built, packaged (build hash 73655d02...4c760f) and INSTALLED
2026-10-30 (0.72.4 backed up in build/backup/install_before_coop25_0727). Not yet run in game.
AC8's Online Mode syncs player weapons with Strix messages (exe strings, jp.co.soft_gear.strix...game.FLiveMessage*):
ExplosiveWeaponFire (WeaponData: WeaponNumber, WeaponNetworkId, SpawnSlotIndex, InitialLocation / Rotation / Velocity,
TargetNetworkId, LockonNum, RandSeed), BulletWeaponFire, HoldingMachineGunButton, InstantWeaponFire,
ElectronicMeasureFire / Effect (ESM / ECM), SpecialWeaponArmed, LockedTarget, PushFlare, EscapeByFlare, LandingGear,
FlightEngineInput, Damage, RespawnRescueTry / Result; the remote player is a real ALivePlayerPlane firing its own
weapons (COOP.md 6). Every message name is referenced from one function, 0x1452a5010 (likely their registration). Research
only, nothing built on it.

## COOP2MP (branch COOP2MP, from 0.72.7-coop.25, 2026-10-30; nothing new run in game)
The user: "everyone is using their player aircraft and not an AI stand in", "Start a new build called COOP2MP". The
other players as real player planes (ALivePlayerPlane, as AC8's Online Mode shows them) with their own weapons, instead
of AI stand-ins. VERSION 0.73.x, COOP_TAG -coop2mp.N, zips `BUILD_NAME=COOP2MP COOP=1 NOVALKA=1 sh
tools/package_release.sh online <version>`. tools/re/COOP2MP.md has Online Mode's research (its Strix weapon messages)
and the tests T1-T5. T1 / T2 (0.73.0, test of 2026-10-30): a role-2 player plane with its tick off and moved every
frame holds formation but has no animations, afterburner, HUD box or enemy attacks. T1c (0.73.1-coop2mp.2, runtime
0.29.1; not yet run in game): its tick left on and its own RemoteUpdate (0x147d6f0c0, kSigRemoteUpdate) fed each frame:
SV_CoopFeed writes a pose, speed, State and stick into its network object's physics message and input (COOP2MP.md). T1c in game
(2026-10-30): it flew beside you on all three airframes, control surfaces working, but no afterburner glow and no enemy
attacks. T1d (0.73.2-coop2mp.3, runtime 0.29.2; not yet run): the glow from your plane's afterburner amount
(plane+0x39d0, written before the surface update reads it) and half the enemies ordered onto the copy
(EngagementOrderOverride TargetFirst; Survival's orders name "Player", which is your plane only). T1d in game: the
glow and the ordered attacks worked (a missile exploded on the copy) but its health never moved, and Quit Mission
crashed: N+0x170 is a TSharedPtr to the input message, and the feed wrote the stick over its controller. T1e
(0.73.3-coop2mp.4, runtime 0.29.3; not yet run): the input through the pointer, and the hits on the copy logged at the
player plane's damage (0x147d5a430). T1e in game: the copy took your stick, the hits reached the
damage and were refused (40 asked, 0 taken), Restart and Quit Mission ran clean (hard rule 53). T3 (0.73.4-coop2mp.5,
runtime 0.30.0, co-op protocol 4; not yet run in game): the other players as their real planes in co-op ([coop]
real_planes, the AI stand-in as the fallback), fed from their stream with a flight block (stick, afterburner, speed,
State); the host's split hunt and the director's joiner tactics order flights onto a real plane (COOP.huntReal); their
weapons and gear on real planes wait for T4; damage as 0.72 (each game's own). COOP2MP.md "T3 build". Online Mode's
weapons research (COOP2MP.md): AI shots are decided on the target's game, a player's on the shooter's (CanBeDamagedBy);
a player's shot is shown elsewhere by the remote plane fire 0x147d71ea0 launching it from their plane's own weapons.
T4a (0.73.5-coop2mp.6, runtime 0.31.0; not yet run): solo, the Ctrl+F11 copy replays your launches, flares and gun that
way; the friends' zip 0.73.5 replaces 0.73.4. T4a in game: missiles, flares and gun replayed, the laser not (not
an explosive weapon). T4a.2 (0.73.6-coop2mp.7, runtime 0.31.1; not yet run): specials (laser, bullet, ESM / ECM) the
handlers' way (select, arm), the gear; SV_CoopPPFx gives co-op's real planes their gear, gun and flares from the flag
bits; zip 0.73.6 replaces 0.73.5. T4a.2 in game: the laser armed but didn't fire, the gear didn't come down
(State bit 9 is gear down, and the feed cleared it). T4a.3 (0.73.7-coop2mp.8, runtime 0.31.2; not yet run): bit 9 sent,
the laser launched from the copy's own weapons; zip 0.73.7. T4a.3 in game: the laser fires from the copy; the ECM / ESM and the gear
not. T4a.4 (0.73.8-coop2mp.9, runtime 0.31.4; not yet run): the ECM / ESM launched as the laser; the gear moved as
RemoteUpdate's own check does (FlGear: the copy's own State never keeps the gear bit sent); zip 0.73.8. T4a.4 in game: the
ECM launched (not seen), the gear raised again every frame: a remote plane's second flight engine (+0x3c60, loaded from
the message and simulated) makes the State's gear bits from its own gear. T4a.5 (0.73.9-coop2mp.10, runtime 0.31.5):
both engines' gear moved; zip 0.73.9. T4a.5 in game: the gear still lowered and raised again every frame. The
check's flag (engine +0x34 bit 0x10) is the input's flags byte (input message +0x20 = BuildFlightInput's out+0x18:
0x10 = State bit 9), and the feed wrote it as a fixed 4; State bit 9 is the engine's gear state +0x710 != 0. T4a.6
(0.73.10-coop2mp.11, runtime 0.31.6): your input's flags byte fed (co-op's real planes: 4 | gear from State bit 9),
a log line a second with both engines' flags and gear state; zip 0.73.10. T4a.6 in game (2026-10-30): the copy's gear
came down and went up again, each moved once (flags 0x10 on both engines while down; own engine's gear state 1-3, then
0); the solo copy (T4a) now replays missiles, flares, gun, laser and gear. ECM / ESM still not seen on it.
T4b (0.73.11-coop2mp.12, runtime 0.32.0; not yet run in game): the other players' launches on their real planes in
co-op. Each game's own launches (PlaneWeaponsFired on its plane while co-op is open: kind, weapon number, spawn slot,
seed, lock-ons, start against the plane, rotation, velocity, target) come out of SV_CoopShots and go in "fx" as
`p:<target id>:<age>:<shot>`, relayed by the host; a game replays them from that player's real plane (SV_CoopPPShot:
the remote fire for missiles, FwLaunchDirect for the laser and ESM / ECM, a bullet special armed), the AI stand-ins
keep m / s / e. Each player's loadout (SV_CoopLoadout, "a,b/c/x,y") rides in hi / pi (a 7th field) and their real
plane is spawned with it (SV_CoopSpawnPP's 8th argument), again when it changes; so their weapon numbers mean the
same weapons here. tools/checks/coop_fire_test.sh covers the Lua side; zip 0.73.11.
T4b in game (2026-10-30, the user and a friend, 2 players): it worked (the ADFX-02's loadout given, its laser, missiles
locked and not, and flares from its real plane). Two problems: (1) the friend changed specials at the airfield, their
loadout changed, and the user's game replaced their live real plane: it crashed a frame on (access violation reading
the destroyed plane +8, in game code 0x147443726 that checks a held object's flags; the crash report's call stack runs
through 0x1474703c0 / 0x147434e50 / vfunc +0x60). Never destroy a live real plane mid-level. (2) The spectator camera
on a real plane showed its cockpit: a player plane carries cameras of its own and the view takes the first active one.
0.73.12-coop2mp.13 (runtime 0.32.0; not yet run in game): a changed loadout is kept for the next level's plane (logged,
no respawn); the watched plane's own cameras are switched off while you watch it and back on after (sv_down.lua hush,
logged once a plane; tools/checks/coop_revive_test.sh); zip 0.73.12.
0.73.22-coop2mp.23 (runtime 0.32.4; built and installed 2026-10-31, not yet run in game; zip 0.73.22, hash b7d19c51...0590e0):
the co-op run of 2026-10-30 on 0.73.20, round 8: both Ladons shot down (their bodies "down") but the round never ended
("it still says both LADONs are alive"): SV_UnitAlive counts the unit's AliveChildAIGameObjects (body + 24 parts) and
the parts lived on; MISHKA's VLS fired on after its body was gone (four players down 0-4 s after it, the host from 100 HP
in one hit, all of it from BP_OP0045_ladn_VLS_L_Base: a sure kill, never toned since its own fire control fires it
pooled, outside Survival's volleys). Now (sv_ladon.lua) each Ladon's parts are recorded as SV_Spawn makes them
(LADON_PARTS, spawningUnit: host and joiners' copies), finished off when its body goes down (ladonPartsDown, from the
round probe: `special: <unit>'s body down: N of its M parts still up finished off`), the round counts a Ladon down when
its body is (`special: Ladon X's body is down, N of its unit still up (its parts): counted down`), and while a Ladon is
up (+40 s) every Ladon missile is toned every 0.5 s (`hits: a Ladon's sure-kill missile caught at damage N`).
tools/checks/bosses_test.sh covers it. Not yet known why the parts lived (a kill with no attacker since 0.73.20?).
0.73.23-coop2mp.24 (runtime 0.32.4; built and installed 2026-10-31, not yet run in game; zip 0.73.23, hash 6bc1a200...6d28bc;
replaces 0.73.22): the joiners' STORE allies and defences (user, 2026-10-31: "some people spawned AI aircraft in from
the shop, as well as Anti Air etc at the airfield and none of it was syncing with the other players"; the logs: a
joiner's WINGMEN, MOONCHILD, AEGIS, AA guns, SAM sites and CIWS only ever in their own game, since only the host's
SV_Spawn is mirrored, and a joiner could take a unit name the host built later). Now (sv_shop.lua, sv_coop.lua,
sv_allies.lua) a joiner's purchase of an allied flight or ship or a defence goes to the host ("ab|id|item|price|kind"),
paid on their game at once; the host builds it (shopBuildFor: the unit picked there, nothing charged there; its spawn
goes to every game as its enemies' do) and answers "ak" or "ax" (refunded), "ar" later for a flight that never took off
(refunded to that player); no answer in 30 s: refunded. A joiner's flight takes off once that player is airborne
(COOP.airborne), else 90 s on. The allies' orders are the room's: a joiner's change goes to the host ("ao"), the host's
to everyone ("ag"). On a joiner's game the host's allies' copies (ALLY.unit and the defences' units, c.ally at bind time)
send no hits: what they take isn't sent, and their hits on enemy copies are taken off what is (the stand-ins'
backstop), so the host's allies' fight is dealt once, on the host. Log lines: `shop: player N's <item> (<price>): built:
...` / `refused: ...` (host), `shop: asked the host to build ...`, `shop: the host built your ...`, `... refunded`
(joiner). Not yet: a joiner's HUD ALLIES row shows the defences but not the room's flights and ships; COVER still
covers the host. tools/checks/defences_test.sh and coop_ground_test.sh cover it.
0.73.23 in game (2026-10-31, gloom hosting dukka, Kalash and Saint Alessia, to round 15; report: Claude Docs "AC8
Survival Mode: Co-op Session Report, 31 Oct 2026"): the joiners' purchases built by the host (12 of 12) and the aircraft
names on the boxes worked; no Ladon round. Three joiners crashed, the same stack each time (access violation in UE4SS's
UObject property lookup, UStruct::FindProperty -> FField::GetClass, from a Lua read), each 4-9 s after a resync ("rs")
took every copy down and the host's defences were spawned again at the same count: sv_allies.lua defenceHealth kept its
cached defence actors (rebuilt every 30 s or on a count change) and read HealthInternal / MaxHealth every 2 s with no
valid(), so freed actors were read. Also: the host answered 71 "jn" in 63 minutes (strays -> jn -> rs tears everything
down -> re-spawned flights often unbound -> the next strays; 57 partly bound flights on one joiner), and each teardown
paid the joiner for the copies it took down itself (5-14 kills, 750-2,230 zollars). 0.73.24-coop2mp.25 (runtime 0.32.4;
built and installed 2026-10-31, not yet run in game; zip 0.73.24, hash 6a5ca5dd...63eb54; replaces 0.73.23): the defence
list checked and pruned (valid, health > 0; ALLY.forgetActors on a joiner's teardown); copies a joiner takes down itself
(killCopy's torn: rs, strays, a flight's last copies) not paid (COOP.tornDown, `round probe: ... taken down here (co-op,
not a kill ...)`); the "planes bound" line names the generation spawned and the host's last ids for it (why the binds go
missing after a resync is still open); a joiner's ALLIES row shows the room's flights and ships (ALLY.roomCode, "rnd"
field 10: "m<n>w<n>s<n>"); COVER on a joiner's flight guards that joiner while their real plane flies (its area the
hunt's, each plane onto the enemies nearest them, COOP.coverFor; else the host as before). Untested in game: whether
EngagementOrderOverride works on an allied plane onto an enemy. Lesson (not yet a hard rule, unconfirmed): any Lua list
of game objects kept between ticks must check valid() before each read and drop what's gone at once; a pcall doesn't
catch a freed object's access violation.
0.73.25-coop2mp.26 (runtime 0.32.4; built and installed 2026-10-31, not yet run in game; zip 0.73.25, hash
98a359a9...ecd30d4; replaces 0.73.24): the info wall (user, 2026-10-31: "an information wall that appears in the center of
the screen on a button press and hides on a button press. Similar to how the end of round information screen works";
with more than 3 players the corner's CO-OP lines had no room). The I key opens and shuts a centred panel styled as the
run's summary: every co-op player (name, HOST / YOU / LOST, aircraft, FLYING / AT THE AIRFIELD / DOWN / NOT IN THE
MISSION, health; two columns from 9, all 24 fit), then ALLIES, ITEMS and the run's kills (sv_hud.lua wallBuild /
wallRows / wallTick, sv_coop.lua COOP.wallInfo, CFG.hud.wall, CFG.hud.text.wall_*). The corner keeps NEXT always and
ALLIES / ITEMS / CO-OP as peeks (no player lines any more), hidden while the wall is open; each level starts with it shut
(start_open: open). tools/re/HUD_LAYOUT.md has the layout, log lines and checklist; hud_info_test.sh 79 checks.
0.73.25 in game (2026-10-31, the user hosting dukka, Shazzy, Saint Alessia): Shazzy's link was lost, the host dropped
them at 90 s ("po" to everyone, which Shazzy's game, cut off, never got) and their link came back 29 s later as a "link
back" on their side, not a new pairing; their game still listed itself on the host's roster so never said hello again,
the host had their plane's stream and no hello, and after AIRFRAME_WAIT_S spawned the default F-16C AI stand-in, which
stays for the level (an AI plane up can't change airframe; nothing is replaced mid-level). Since (not yet a build or run):
the host asks a player whose plane streams with no hello for one every 3 s ("hq"; `coop: player N's plane streams here
but no hello from them: asked for it (hq)`), the default waits HELLO_WAIT_S (30) with no hello at all (5 with an empty
one, as before), and a joiner says hello on "hq" (once a second at most) and whenever its link comes back.
coop_landing_test.sh covers it. Built as 0.73.26-coop2mp.27 (runtime 0.32.4; installed 2026-10-31, not yet run in game;
zip 0.73.26, hash 294ad410...d428122; replaces 0.73.25).
0.73.26 in game (2026-10-31, five players): the host crashed 400 s in (09:22:24), access violation reading -1 at
0x147f7c340, the stack RemoteUpdate's call (0x147d646dc) -> main.dll's detour -> the remote fire 0x147d71ea0 (+0x50b) ->
the spawn slot's lookup 0x147f7c300, replaying a joiner's launch on their real plane (player 5's first, an FA-36 that had
joined 35 s before). 0x147f7c300(launcher, weapon, spawn slot) indexes the launcher's weapon table ([launcher +0xb0]
+0x28, 0xa0-byte entries, count +0x30: the game's loop at 0x147f7bbc4) by the weapon number with no bounds check and
reads the entry's slot list +0x78: a weapon number that plane hasn't read garbage. Runtime 0.32.5 (0.73.27-coop2mp.28;
built and installed 2026-10-31, not yet run in game; zip 0.73.27, hash f0c27640...69feba0; replaces 0.73.26): every
replayed weapon (T4b's FnFlush, T4a's copy, FwLaunchDirect) is checked first (flight.c FwWeaponOk); one not on the plane
is dropped and logged (`coop2mp: T4b: player N's shot (weapon W) NOT replayed on their real plane ... here: it has M
weapons`, and the minute line's `not a weapon of their plane here`). The cause (user, 2026-10-31; their logs): that player
(Twelve) ran SPWeaponCustomizer 2.3 (UseHighestCapacity=1, the FA-36 given special slots 19, 21 and 27) and AC8WeaponSwap
1.1.0 (a native library, ac8weaponlib_011.dll); their first shot, a SAAM (BP_plwp_saam_a0_C), went as weapon 2, which
the stock FA-36 spawned from their loadout (specials 23, 21) hasn't. Their other mods (AC8UnitHealth, AC8WeaponValues,
HangarModelFix, SkipIntro) only display or skip menus.
0.73.27 in game (2026-10-31, 8 players): at 10:01 the host and at least five joiners went down within 30 s. The host's,
dukka's and player 5's crash reports are one stack, all game code: an AI unit's per-frame update (0x147cb2850, slot 279
of its class's vtable 0x14c51df10; the class's constructor 0x147cb2430 makes a MainMesh beside the fire control and the
damage state, over a parent shared by 36 classes, so not an AI plane) moving an effect component it holds at +0x2690
(spawned on a sea-plane test, 0x147cb3a23) and checking only its garbage flag; the component had been freed, and the
call through its vtable (0x1442c3e9b) faulted. Which unit isn't known (two AEGIS ships had just been bought; MISHKA had
left one part alive, `1 NOT (still up)`). Shazzy's report (09:43) was the replay again: 0x147f7c300 writes the spawn slot
through the entry's list pointer (+0x78) even when its count is 0, and 0.32.5's FwWeaponOk only checked the list when it
had entries. Runtime 0.32.6 (0.73.28-coop2mp.29; built and installed 2026-10-31, not yet run in game; zip 0.73.28, hash
9b2b218f...abe00e73; replaces 0.73.27): FwWeaponOk checks the list writable and the slot array (+0x58, count +0x60)
whatever the counts; flight.c OnUnitFxFrame hooks that vtable slot (sigs.h kSigUnitFxFrame) and lets go of a +0x2690
component the moment it's marked destroyed (`guard: an AI unit's effect ... let go before it's freed`); and another
build is refused (the user: "add the refuse mismatched builds"): the host's hello answers a joiner of another version
with yourSlot 0xFD and no link (`coop: refused <name>: their Survival is <v>`, Lua "sys|refused" -> REFUSED <NAME>
callout), a joiner on another build than the host's links to nothing and says so ("sys|badver" -> CO-OP: THE HOST HAS
<v>), both ways (an older host doesn't refuse, the newer joiner does). coop_test.sh's 4-player run has a joiner of
another build (refused, never a slot); coop_landing_test covers the Lua side.
0.73.28 in game (2026-10-31, 7 players): the host crashed at 10:44:43, in UE4SS's UObject::ProcessEvent called from Lua
(a method on a freed object), right after every joiner asked for the whole picture at once and a plane of a flight the
director kept aimed died: sv_stats.lua's tail watch KEPT each plane's blackboard (p.bb) between its 4 Hz reads, and the
director's aimsTick wrote TargetActor through p.obj.AIStateComponent.BlackboardComponent with only the plane checked.
0.73.29-coop2mp.30 (runtime 0.32.6; built and installed 2026-10-31, not yet run in game; zip 0.73.29, hash
1dfccdea...0ab2f; replaces 0.73.28): sv_ai.lua aiBlackboard(p) reads the blackboard fresh, valid() at each step (the
plane, its AIStateComponent, the blackboard), none for a plane at 0 health, never kept; aiWatch, ACE.hunt, the
director's aims and the tail watch all go through it (tailed_test covers it). Rule kept since: a game object a Lua part
keeps between ticks is dropped the first time it's invalid, and a component reached through it is checked too. Players on other mods can
make the games disagree elsewhere too: a session should run the same mod set.
0.73.30-coop2mp.31 (runtime 0.32.7; built 2026-10-31, NOT yet installed (AC8 was running), not yet run in game; zip
0.73.30, hash 88faf384...bd23cd; replaces 0.73.29): host migration (user, 2026-10-31: "if the Host does leave, it
automatically tries to find the next best host"; their choices: the round in play starts again, the allies and defences
are built again, the best connection takes over). sv_coop.lua's "host migration" block, [coop.migration] (enabled,
after_s 30, link_s 20, wait_s 60, break_s 15; Steam only). The host ranks its joiners by link (round trip + 2000 x the
share resent, +10000 out of the mission; SV_CoopPeerIds: each link's slot, Steam ID, rtt, sent, resent) and sends the
line with each Steam ID ("sq|<host sid>|slot:sid,..."), the allies and defences up ("al|item:buyer sid,..."), and "hl|120"
before its level reloads at a run's end (DOWN.runOver); "pi" carries each player's Steam ID last. A joiner whose host is
silent after_s (or the host's "hl" time) goes down the line: the first in line reopens as host looking for everyone's
Steam ID (SV_CoopOpen's partner list, now 640 chars / 24 names), takes the copies down (torn, not paid), sets the old
host's plane aside (hidden, never destroyed), starts the round in play again break_s on (a new D; between rounds the
next), holds it while the others aren't back (joinWaiting, wait_s), and builds the allies and defences again 5 s on
(shopBuildFor, free, retried every 3 s up to 10); the others join it, the next after link_s, the old host again when
nobody answers. A host by migration that nobody joined and hears another host joins it again (samerole, migStepBack).
Each real plane carries its owner's Steam ID (P.sid): one back in another slot moves with them (M.slotFix,
SV_CoopSwapPP swaps the native plane refs), one in a slot that's another player's is set aside, one left in this game's
own slot is hidden at once and set aside 10 s on (AI stand-ins stay their slot's unit). Log lines `coop: migration: ...`.
tools/checks/coop_migration_test.sh covers it (the host's line, the takeover, the others, slots, hl, off). Open: whether
Steam P2P links a new host fast enough, the new host's run state beyond D (RUN, AF, specials mid-fight), stand-ins.
0.73.30 in game (2026-10-31, 6-7 players, the user hosting): the user's game crashed at 12:07 and host migration took
over (user: "host migrate worked", "reset the round they were on, allies stayed"): the first in line hosted, round 10
started again, the allies were back. The same session's crashes (none of Survival's own code on the stacks):
- 11:24 (the host, 0.73.29, the Alicorn round) and 12:07 (the host, 0.73.30, round 10's start while Survival recycled
  the flights flown before, destroying their planes): worker threads in a weapon's target search (ParallelFor
  0x1474703c0 -> 0x147434e50 -> 0x147435060, slot +0x60 (obj, query, a, b) -> bool on a family of 151 classes over one
  base): 11:24 in class 0x14cb78378's 0x147443690 (IsA on its +0x18 game object, freed: class NULL), 12:07 in class
  0x14cb77dc8's 0x1474515a0 (its +0x20 weak actor NULL, used unchecked at 0x147450468); the T4b replaced-plane crash was
  the first class too (+0x28).
- 11:57 (gloom, after the Ladon round) and 12:03 (another joiner, round 9's Tu-95 raid): the AI unit effect move
  (+0x2690) past 0.32.6's guard: the effect freed (and its memory reused) while the unit's update wasn't running, so its
  garbage flag was never seen.
0.73.31-coop2mp.32 (runtime 0.32.8; built and installed 2026-10-31, zip 0.73.31, hash 2d0260bd...727735;
replaces 0.73.30): runtime/uobj.h UObjLive / UWeakLive answer from GUObjectArray as the game's own
weak-pointer lookup does (found in 0x147443cb0, which kSigTargetCheck's function calls; tools/checks/uobj_test.sh); the
effect guard lets go of a component no longer in GUObjectArray; flight.c TgtInstall hooks slot +0x60 of the first class
(kSigTargetCheck: +0x18 / +0x28 live) and of every class of the family whose check reads +0x20 through the game's
FWeakObjectPtr::Get (11 of them), answering "not a target" when that weak actor was set and is gone. Log lines:
`guard: GUObjectArray chunks at ...`, `guard: N target entry classes guarded (...)`, `guard: a weapon's target search
skipped a gone unit's entry ...`, `guard: an AI unit's effect ... was freed already (not in GUObjectArray): let go`.
Not yet run in game; watch that targets stay selectable (a wrong "gone" would hide them).
0.73.31 in game (2026-10-31, the user hosting 5 players to an Alicorn round): no crash; the guards loaded on every game
(GUObjectArray found, 10 classes); every skip (14 lines on the host, 4096+ entries in 5 minutes) was one class,
0x147447050, which tests its weak actor itself, so 0.32.8 changed its answers for nothing. Two joiners couldn't target
the Alicorn at all (user: "players go reported the alicorn as untargettable"): on a joiner the Alicorn's 131 parked
pools (put away invincible) were counted as its copies though the host gives them no ids (hostPlane skips
SPC.alcnPool; clientPlane didn't), so 15 s on they were "strays", couldn't be finished ("health 1000 after"), the "jn"
resync's teardown took the Alicorn's tanks and core down there, and the host's fresh one was refused (the old unit
still up: "its last flight is still up (212 alive)"), leaving a hull with no live parts.
0.73.32-coop2mp.33 (runtime 0.32.9; built and installed 2026-10-31, zip 0.73.32, hash dc54b9e5...3fdc5; replaces
0.73.31): clientPlane skips the parked pools (as hostPlane, so the ordinals agree); a
joiner's doSpawn takes a stuck Alicorn copy off whole (RE_SV_AlcnRemove, once) before the host's fresh one
(`coop: the Alicorn's last copy here is still up (N alive): taken off whole for the host's`; coop_ground_test); the
target guard tests the weak actor only in classes that use it unchecked (TcWeakUnchecked: no `test rax, rax` after
the Get, no inline `bts r32, 21` before it: 0x1474515a0, 0x147439690, 0x14743a4c0) and, in the first class, only its
raw +0x18 / +0x28 (it tests the weak itself): 4 classes. Not yet run in game.
0.73.33-coop2mp.34 (runtime 0.32.9; built and installed 2026-10-31, zip 0.73.33, hash 864bda51...712225; not yet run in
game): VOID WATCHER 1 and SNIPER (user, 2026-10-31: Mission 28's AWACS
"Take off from the airfield as a purchasable ally", "Rename it too VOID WATCHER 1", "give it's ESM a huge boost in range
and have it orbit around the airfield"; "rename VIPER to SNIPER and change their standard missiles to LAAM's", "I want
the stock aircraft files touched but for Survival Mode"). VOID WATCHER 1: the E-767 Magnolia (OP0005_e767_MS28: flares,
MS28ESM000 -> BP_FCS_ESM_MS28 -> BP_wp_esm_MS28, class LiveElectronicSupportMeasures) as Survival's row SV_Ally_VoidWatcher
(DT_SV_NpcRows, name key SV_VoidWatcher) on its own world-data unit SV_Unit_VoidWatcher (one AI object copied from
MOONCHILD's lead at Comona Airport, its desc naming sv_ally_voidwatcher on Mission 22's e767_common, so its NLID_1000
behaviour is built at level load; callsign on its box), MOONCHILD's lead's scramble (hold, taxi, roll, climb), airborne:
gear up, not invincible, engagement None, SV_AwacsAir 1, then SV_Path_VoidWatcherOrbit (12 points, 7 km round the
airfield, 4.5 km up, 650 km/h; each lap's end starts it again; tools/survival_events.py AWACS_*, build_awacs). Lua
(sv_allies.lua ALLY.awacsTick, CFG.allies.awacs): the STORE's DEFENCES page row VoidWatcher (12000 Z, one at a time),
takeoff once you're airborne (a joiner's purchase built by the host), its ESM fired every esm.every_s 20 while airborne
(RE_SV_AwacsEsm: WN_WEAPON_2 by Mission 19's LiveFireOneShotWeapon, forwarded in co-op), its ESM fire control
(MS28ESM000_SVA) reaching capture_m 60 km and ready again in 0.5 s, and each new ESM field of class BP_wp_esm_MS28_C
(NotifyOnNewObject LiveElectronicSupportMeasures; an instance, never the class) set to SupportEffectRangeMeter /
EffectRangeMeter range_m 25000 (stock 3200), LifeTime life_s 24; the ALLIES row by name, co-op room code "v<n>",
migration's rebuild item VoidWatcher. SNIPER (was VIPER): name in CFG; its row (Survival's copy of OP1022_f16c_01)
carries NPC_FCS_PlaneLAAM000 where the stock row has NPC_FCS_PlaneMsl000, written at build time
(survival_events.ALLY_WINGMEN_MISSILE, build_npc_rows; the stock row as shipped), then boosted as every ally weapon.
Log lines: `allies: VOID WATCHER 1's ESM on <row>: within N m`, `... taxiing out`, `... ESM fired`, `... ESM field <name>:
support range A -> B m, range A -> B m, life A -> B s`, `... lost N s after it spawned`. Not yet known in game: whether an
E-767 follows the fighter scramble's taxi / roll / climb paths (it's invincible until airborne), whether its ESM fires on
command (as the jammer's ECM does) and whether the field's range takes from an instance set at construction.
tools/checks/defences_test.sh's "VOID WATCHER 1 and SNIPER" and coop_ground_test's room code cover the Lua.
A joiner's crash of 2026-10-31 16:08 (0.73.33, round 11, right after buying WEAPON BAYS' last tier; the machine of
the 12:03 crash): an access violation reading 0xffffffffffffffff inside UE4SS, a recursion of its own (an outer-chain
walk, "...ameInstance_C" and "...etText" on the stack) from Survival's Lua tick: a STORE press relabels the rows at once
(sv_shop.lua relabel: FindAllOf("TextBlock"), nameOf -> GetFullName on each), and a TextBlock whose page was going away
had a freed outer; valid() (UE4SS's IsValid) checks only the object, and a pcall doesn't catch it. 0.73.34-coop2mp.35
(runtime 0.32.10; built and installed 2026-10-31, zip 0.73.34, hash 305a5df9...778a85): uobj.h UObjChainLive (the object and every outer, +0x20, live in GUObjectArray, 64 levels at most;
uobj_test), SV_ObjChain(address) for Lua, and sv_core.lua nameOf answers "?" without asking UE4SS when the chain isn't
live (every name read goes through it; the shore marker's trace-hit name too). Not yet run in game. Lesson (not a hard
rule yet): UE4SS's GetFullName on a FindAllOf result isn't safe in a frame where widgets are being torn down.
0.73.35-coop2mp.36 (runtime 0.32.10; built and installed 2026-10-31, zip 0.73.35, hash 4e9083c3...dbda76; not yet
run in game): (1) raid pings (user, 2026-10-31: "an alert that pings the
aircraft via the minimap that are attacking the airfield"): RE_SV_RaidPing_NN, Mission 22's own LiveBattleNavigationExecution
(its shuttle / control-centre "look here", template Default_PreRadioEvent_28: {tag, unit, Quadruple, false}) on bomber
flight NN's unit; sv_flights.lua raidPings (from bombTick, once a second, the host's or solo: forwarded) fires it every
[bombers.ping] every_s 12 while a flight up and not sent at an allied ship has an aircraft within within_km 40 of the
airfield (`bombers: <unit> pinged on the minimap ...` once a flight; heavy_test). (2) VOID WATCHER 1's ESM never came on
(reported by players on 0.73.33): OP0005_e767_MS28's fire control is NpcFCSId0 PlaneFlr100, 1 and 2 empty, NpcFCSId3
MS28ESM000 (the compact research table had dropped the empty slots), so the ESM is WN_WEAPON_4, not 0.73.33's
WN_WEAPON_2. (3) its box read MAGNOLIA (user: "Delete the MAGNOLIA tag from the EW aircraft"): the model row
OP0005_e767_Ally_Magnolia's GameObjectDisplayName01 is ContainerAllyCallsign_Name_Magnolia; Survival's copy
SV_Model_VoidWatcher (DT_SV_ModelRows, from the campaign's DT_NPC_Model) keeps its blueprint and paint under
ContainerAircraft_Name_e767, the NPC row names it, and sv_allies.lua adds it to DT_NPC_Model at the main menu (not
sold without it). defences_test covers both.
0.73.36-coop2mp.37 (runtime 0.32.10; built and installed 2026-10-31, zip 0.73.36, hash 98898b0f...0defa0; not yet
run in game): VOID WATCHER 1 "just seems to not loiter around the
airfield space" (user, 2026-10-31; no log yet): its orbit was 7 km at 650 km/h (~25 deg of bank all the way round, more
than an E-767 holds), now 12 km at 550 km/h (~12 deg) on 16 points; and its orbit started only at the end of the
fighters' climb-out path, which a big E-767 may never reach (no orbit, no SV_AwacsAir, so no ESM either): Lua's backstop
(ALLY.awacsTick, CFG.allies.awacs.orbit) fires RE_SV_AwacsOrbit (gear up, not invincible, engagement None, SV_AwacsAir 1,
the orbit path) when the climb-out hasn't ended climb_s 60 after takeoff, and again when it's lost_km 18 or more off
(`allies: VOID WATCHER 1 put on its orbit (<why>)`; defences_test). Players' own ESM / ECM affecting only their own game
in co-op (user, the same day): research under way (Online Mode's ElectronicMeasureEffect fills the sender plane's
+0xd88 enemies / +0xd98 allies lists of {weak ptr, flag} through 0x147d27c00; nothing sends those in Survival).
0.73.37-coop2mp.38 (runtime 0.32.11; built and installed 2026-10-31, zip 0.73.37, hash 4ef765fd...f30d98; not yet run in
game): the other players' ESM / ECM fields count on every game. Each plane pulls its electronic effects every tick
(0x147d27d50, sigs.h kSigPlaneEw) from every electronic weapon in the world but skips one whose owner is a remote plane
(role byte +0xED8 == 2, at 0x147d27f34), which co-op's real planes are; flight.c OnPlaneEw sets every OTHER live real plane
to role 1 around that call and back to 2 after, so the stock range / team / time rules apply (`coop2mp: the other
players' ESM / ECM fields count on this game ...`, once). tools/re/COOP2MP.md "ESM / ECM effects across games".
0.73.38-coop2mp.39 (runtime 0.32.11; built 2026-10-31, never installed (0.73.39 has it all), not yet run in game; zip
0.73.38, hash e52b0e3a...e9d3ec): the Spaceport Assault, round 1 (user's special of 2026-10-31; tools/re/SPACEPORT_ASSAULT.md
"Build 0.73.38"): an enemy fleet of 27 one-ship units west of the spaceport (the Ford, 4 Wasps, 14 Aegis, 8 missile boats:
allied descs flipped to Faction 2 on the enemy DT_NPC rows, tools/build_survival.py spaceport_units / enemy_unit), each
Wasp's waves of two LCACs to its beach, their invincible troops driving to the spaceport's capture meter, the Ford's deck
launches, SPACEPORT HELD / CAPTURED, and a first retake (the garrison and the ships left; Mission 19's rockets not yet).
Scripts/sv_spaceport.lua (SPORT), CFG.specials.spaceport, [specials.spaceport*]; SPC.kinds gained ready / busy / over /
row (sv_rounds.lua, sv_hud.lua) and specialFor a special's from_round. Not in the rotation until tested: Ctrl+END /
Ctrl+INS force it (test only). 1211 triggers, 2262 execs. tools/checks/spaceport_test.sh.
0.73.39-coop2mp.40 (runtime 0.32.11; built and installed 2026-10-31, zip 0.73.39, hash 7135b5db...4be518; not yet run in
game) = 0.73.38 + the enemy weapons log (user, 2026-10-31: "a logger that checks what enemy missiles are being fired, I
have a feeling that none of the special weapons we gave the enemies are working"): Scripts/sv_weaponlog.lua (WLOG,
CFG.log.weapons, [log.weapons], on by default). The native LaunchWeapon hook can't see them (0x147f7a880's three callers
are the player weapon system and Online Mode's remote fire) and FiredExplosiveWeapons is LivePlayerPlane's alone, so Lua
reads each enemy plane's FireControlSystemComponent.AllArms 2 s after it's created (each system's name and its projectile
module's WeaponClass(es), `weapons: <unit> (<row>, <airframe>) carries: ...`, once an airframe and loadout) and every
0.5 s every LiveExplosiveWeapon / LiveAttachedInstantWeapon / LiveElectronicWeaponBase: pooled, so a launch is one shown
(bHidden false) that was hidden the look before, or shown with a new OwningGameObject (the first look only primes);
`weapons: first launch of <weapon> by <airframe> (<unit>, <row>) at <target>` once each, and every 60 s `weapons: last
N s: <weapon> xN (<shooters>) ...; carried by enemies but never fired this run: ...`. Guns and flares are listed, not
watched. tools/checks/weaponlog_test.sh. Unverified: that idle pool items are hidden (logged if bHidden can't be read).
0.73.39 in game (the user's solo Spaceport test, 2026-10-31 17:51): the fleet, waves and landings worked, but "only some
of the ships are firing, none of their Anti Air": no ship launched anything in 5 minutes (the weapons log). A hull's
engagement order doesn't reach its turrets (stock missions order each by name; the Ladon's CIWS needed theirs).
0.73.40-coop2mp.41 (built and installed 2026-10-31, zip 0.73.40, hash a3f8e7c2...477dec; not yet run in game): each of the
fleet's 68 turrets its own order (Mission 16's Default_RemoteEvent_20: Normal, PlayerFirst; survival_events.sp_parts,
asserted against the world data). The STORE's allied Aegis (ally_units / build_allies) still have the hull's order only:
likely why they "didn't seem to fire all that much" (2026-10-23). The same log: the fighters carried their specials
(2AAM, HCAA) and never fired one in 5 minutes, their standard missiles 21 times.
0.73.41-coop2mp.42 (built 2026-10-31, zip 0.73.41, hash d268bffd...e5ef4d; installed when AC8 was closed; not yet run in
game): the same test's capture never ended the round (six fighters still up: a round ends only with its aircraft
down): the capture now despawns the round's pool flights (RE_SV_FlightOff_NN, Mission 22's LiveSetActiveGameObject false,
and off D.up: a despawned unit can still read alive) and drops its queue and later waves, so the break and the retake
follow; the missile boats patrol their lanes (4-9 km ahead of their Wasp and back, Mission 22 ship lane shape, 90 km/h).
0.73.40 in game (the user's solo test, 2026-10-31 18:04): the turrets fired (the weapons log: the Aegis mk41 VLS 6 a
minute, the boats' SAMs 4), so a turret's own order is what they needed.
0.73.42-coop2mp.43 (runtime 0.32.12; built 2026-10-31, not yet run in game):
- The fleet's weapons (user: "up the Activation Range and Targetting Range and Lifetime of ALL Ships currently at the
  Spaceport"): each turret on Survival's own mission row and DT_NPC copy (tools/survival_events.py SP_TURRETS:
  sv_fleet_* -> SV_Fleet_*, copies of the stock VE002 / VE004 / VE011 rows; sv_spaceport.lua SPORT.FLEET_ROWS), which
  sv_allies.lua ALLY.setup puts into DT_NPC at the main menu on fire control of its own as the STORE ships' (key
  "Fleet", CFG.specials.spaceport.fcs: search module 25 km, lock-on x2, guns' rounds out to it, homing missiles 20 km /
  30 s; their stock rate of fire); `allies: the Spaceport fleet's turrets: 9 of 9 rows in DT_NPC ...`; without them no
  Spaceport Assault (SPORT.ready, ALLY.fleetReady). Each ship's unit area 40 km. The LCAC waves every 3 minutes (user).
- The enemies' special weapons (user: "I want the Enemies to fire their Special Weapons too"; the weapons log: carried,
  never fired): Scripts/sv_spweapons.lua (SPW, CFG.special.fire, [special.fire]) fires RE_SV_SpecFire_<NN><L> (Mission 19's
  LiveFireOneShotWeapon, WN_WEAPON_4 = slot 3: survival_events.SPEC_SLOT) for an enemy whose row has its special there
  (sv_rows.lua SR.spSlot / spWeapon) with you inside 35 deg of its nose at that weapon's range (QAAM 1-4.5 km, HCAA 2-7,
  2AAM 1.5-6, LAAM 4-12), 10 s after it appears, every 25 s at most, 8 a minute across the sky, not a held Wolf trap;
  the host's (KEEP_EVENTS ^RE_SV_SpecFire_). `specials: <unit> <L> (<row>) fires its <weapon> at you ...`; the weapons
  log's `first launch of` says it launched. tools/checks/spweapons_test.sh.
- Alyssa's crash (a joiner on 0.73.37, 2026-10-31 00:50; tools/re/COOP2MP.md "A weapon's target search and a destroyed
  unit's world"): AceCombat8+0x374cb08 reading NULL + 0x898 on a worker thread, in the weapons' target search: entry
  class 0x147454050's check passes the world getter's answer (0x143fc1ca0: NULL for an object being destroyed) on
  unchecked, seconds after her game took 13 copies down and their flights spawned again (the native Recycle destroys
  a flight's old unit actor). 13 checks of the family do so. runtime/safecall.h (ScCall4: a vectored exception handler
  armed only inside the call puts the thread back, the call answers 0) wraps every guarded check, and TgtInstall guards
  the world-unchecked classes too (sigs.h kSigWorldOf, TcWorldUnchecked; the weak-pointer test only on its own kind):
  `guard: the target search's fault catcher in ...`, `guard: N target entry classes guarded (the first 1, a weak actor
  unchecked 3, the world unchecked M ...)`, `guard: a weapon's target search caught a fault in an entry check ...`.
  tools/checks/safecall_test.sh. Also from her log: the teardown on the host's restart paid her for the copies (290 Z
  "by you"): not yet fixed.
- Lesson (the load test): a new global table is `X = {}`, never `X = X or {}` (the load test's stub answers every
  global, and sv_allies.lua iterated SPORT.FLEET_ROWS at load: lua_load_test hung).
0.73.43-coop2mp.44 (runtime 0.32.12; built 2026-10-31, not yet run in game): the enemies' specials at every player (user:
"it's paramount that Special Weapons target all, HOST and JOINERS"; 0.73.42 fired only on the host, at the host): every
game runs sv_spweapons.lua on its own planes at its own player (the host its enemies, each joiner its copies of them,
as their standard missiles already go: an AI's shots are decided on its target's game), each with its own cap; a joiner
learns each flight's rows from the host's spawn (sv_coop.lua doSpawn -> SPW.noteRows: the flight's row, idx -1, and its
lead's own, idx 0); none while that player is DOWN; RE_SV_SpecFire_ still never forwarded. spweapons_test covers it.
0.73.44-coop2mp.45 (runtime 0.32.13; built and installed 2026-10-31, zip 0.73.44, hash 2ea9dfa9...a433c; not yet run in game): seven loggers (user: "What other loggers
could we add?" ... "All of them"), in the log only:
- crash breadcrumbs: <mod folder>\AC8SurvivalMode_crumbs.log (the session before: AC8SurvivalMode_crumbs.prev.log),
  written at once with milliseconds and the thread: the native runtime's flight recycles (unregister + unit actor
  destroyed), real / second player planes destroyed, the target guard's skips and caught faults, the effect guard's
  let-gos; Lua's (sv_core.lua crumb() -> SV_Crumb) every SV_Spawn, every removal-type event (Remove / Off_ / RunOver /
  Destroy), each copy taken down, teardowns, a joiner's copies of the host's spawns, a joiner's asks answered. After a
  crash, read the crumbs.prev file first.
- targets (sv_audit.lua): every 5 s whom the enemy aircraft aim at (TargetActor: you, each co-op player by name, the
  allies, others, nothing) and each player's damage (health drops), `targets: last 60 s ...` a minute.
- missile outcomes (sv_weaponlog.lua): each enemy missile at you followed to its end (hit: within hit_m 150 m as your
  health dropped; decoyed: it went after a flare; missed), `missiles at you: last 60 s: <weapon> n (h hit, d decoyed,
  m missed; from X km on average); this run: ...`.
- fleet turrets (sv_weaponlog.lua, sv_spaceport.lua SPORT.turrets): per turret class each minute how many fired (their
  missiles; their guns: any of their LiveBullets shown, looked at every turret_s 5), your range at fire, and how many
  stayed silent with you inside their 25 km reach: `fleet: last 60 s: <class>: a of n fired ...`.
- pay audit (sv_audit.lua, wrapping addCredits): `pay audit: last 60 s: +N Z in M pays: kills / round bonuses /
  specials / other`, and on a joiner each kill paid within suspect_s 5 of a teardown here flagged at once (COOP.tornRecently).
- sync health (sv_coop.lua COOP.syncReport, each minute): a joiner's copies (bound to the host's ids or not), strays
  taken down, its asks (jn) and the answers (rs), copies torn down and teardowns; the host's asks answered.
- the Spaceport waves (sv_spaceport.lua): `special: wave <unit>: n craft, x shot down, y landed, z troop vehicles ashore`
  as each is done, and the round's `the Spaceport Assault's waves (...): ... the capture: 5% at +4:10, ...`.
CFG.log.weapons (hit_m, turret_s) and CFG.log.audit ([log.audit]). Tests: audit_test, weaponlog_test, spaceport_test.

## Leaderboard: admin page and stock runs only (2026-10-30; Worker not yet deployed, not yet run in game)
leaderboard/README.md has the deploy steps (paste src/index.js; the Worker makes its new tables itself). The Worker takes
co-op versions (0.72.2-coop.20), has an admin page for the user only (GET /admin; ADMIN_KEY in the POST body, 5 wrong
keys lock an address out: reset (archived, undoable), restore, builds, verification), and counts a run only from a
registered build: the runtime hashes the mod's files (runtime/build_hash.c, the same as tools/build_hash.py:
tools/checks/build_hash_test.sh) and sends X-SV-Build, signed with the run; package_release.sh online writes
<zip>.buildhash.txt to register. Register every zip given out before players send runs from it. The game doesn't send
an edited run (LB.edited: gameplay settings against CFG_DEFAULTS, a survival_config.lua, test keys;
tools/checks/leaderboard_test.sh): a new setting that's only on screen or each player's own goes in its free lists.

## Runtime layout (Lua, from 0.66.0)
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
- Before starting, pull/read the latest commits and this file.
- Record any new lesson here under "Hard rules" once a test build confirms it.
- Never delete or overwrite game files directly. Work on copies inside this folder.
