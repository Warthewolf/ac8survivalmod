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
tools/coop_edition.py COOP_TAG for every build friends get: games with different tags refuse to link).
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
is down, not counted as tries), the wave clock runs, the ALICORN's deck launches and a Wolf trap is held after its
orders; solo, or with nobody else flying, all held until the takeoff as before (user's question of 2026-10-29: Shazzy's
host log had 10-43 s holds). The shuttle's countdown still pauses while the host is down. The CO-OP row is behind the
HUD's info key (I), with a line a player when open (tools/re/COOP.md section 7, tools/re/HUD_LAYOUT.md).

## Enemy behaviour build (Lua 0.72.0, TestBranch_Behavioural; untested in game)
The Claude Docs thesis "AC8 Survival Mode: Enemy Behaviour Reference & Challenge Thesis"'s nine proposals, all built on
branch `TestBranch_Behavioural` (from tag stable-1, 2026-10-29), COOP_TAG -coop.18: fighter roles (P1: the pool split
into Duelists, Lancers, Wolf bait-and-trap pairs and Skirmishers, each its own behaviour set and airframes; 7 new
Scripts/ai scripts), the squad director (P2: cover the tailed, spring the trap, bracket salvos, top cover, pincers,
regroup; Scripts/sv_director.lua), tells (P3: a radio line and / or callout before each threat, 61 stock lines cloned
into DT_SV_Radio; Scripts/sv_tells.lua, co-op "tl"), the intensity director (P4: each player's intensity and comfort, wave
holds, pushes, the spikes as a ceiling; co-op "in"), a harder tailed plane (P5: every reaction pick moves, live provoke
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
