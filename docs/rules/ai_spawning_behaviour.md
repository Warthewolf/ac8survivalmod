# AI, spawning, events and behaviour

Event records, paths, spawning, AI behaviour trees and unique actions, kills and damage.

Moved verbatim from AGENTS.md (2026-11-14). Rule numbers are unchanged: other notes cite them as "hard rule N".

1. PathPointReceive triggers copied from stock missions never fire. Use PathFinish triggers and exec delays.

2. A stock exit path with a different control type "finishes" instantly. Reuse the inbound path's settings and start new paths a little ahead of the aircraft.

3. Make every ported or spawn trigger one-shot, and turn path warp off. Mission 25's appearance trigger re-fires and warps.

4. Despawn on a timer (about 2 minutes), not at the end of an exit path. (Survival doesn't despawn enemies: they're chased.)

5. Keep ported events in stock order, e.g. release the carried unit before giving it its drop path.

6. The first kill of a counted target doesn't register, so event-flag counters start at 1.

15. Setting a world-data AI object's MissionNpcID before spawning changes the aircraft type (any row of the world
    data's NPC table). Confirmed by test 11.

16. A shot-down flight spawns again only after it's taken off the phase's unit list (UnregisterUnit + AActor::Destroy,
    what Survival's SV_Spawn does). Confirmed by test 11, rounds 3-5.

17. Event records name flags (and events) by string, which the game turns into an FName that splits a numeric tail
    ("SV_Up_19" = SV_Up, number 20). Store the flag asset's keys the same way (survival_events.fname), as stock tables
    do, or the flag never matches. Test 11: flights 10-24 were never flagged, so never chased; fixed, confirmed by test 12.

20. An AI aircraft's behaviour trees are built when the level loads, one set per world-data AI object desc, from the
    NPC row (-> DT_NPC LuaSetId) that desc names then: 127 aircraft x 15 slots = the 1915 LiveAIBehavior objects
    counted before anything spawned, and each LA_ script's Ctor ran once. SV_SetAircraft at spawn changes the airframe
    and the AI module (search radius), NOT the behaviour, so a flight's behaviour row goes into the world data at build
    time (survival_events.behaviour_row) and its DT_NPC / LuaSet rows must exist before the level loads.
    Confirmed by the test of 2026-10-22 (our probe script loaded but was never built; NLID_0400_CP never applied).

22. Don't give ordinary enemies the campaign aces' set NLID_0400_CP: LA_PursueTarget_0400 only attacks inside KDS
    phases (IsKDSP1/IsKDSP2 decorators), which they never enter, so they fly around without attacking (test of
    2026-10-22, the first build where the set really applied). Survival's fighters fly its own set NLID_SV_Fighter.

26. An event record's conditions are checked when its event fires, not when its delay runs out: records on a delay
    gated on a flag set later never run. Test of 2026-10-22: the shuttle's removal (delay 60 s after liftoff, gated
    on SV_ShuttleLaunched) never ran, so the shuttle and pad stayed up. Fire a remote event from Lua at the right
    time instead (RE_SV_ShuttleRemove).

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

45. An AI aircraft's railgun shows on the minimap and HUD like a stock one when its LiveFCSModule_LauncherTripleRailCannon
    gets IsDispRadarMap / ForceAlertDisp true and HUDControl 1 (LongRangeRailGun) at run time; Mission 18's
    LiveSetRailgunAlertEnable (true / false) shows / hides the RAILGUN WARNING. Confirmed by screenshots 2026-10-24.

46. A component added at run time draws on an AI aircraft: AActor::AddComponentByClass(SkeletalMeshComponent) +
    SetSkeletalMeshAsset put VALKA's X-02S on the x40a, whose own body is a StaticMeshComponent (AC8's NPC bodies are
    static; the only skeletal meshes on it were the wreck's, which never draw: hard rule 41). Confirmed 2026-10-24.

54. A fast AI plane (the Ladons at 2500 km/h) doesn't take a new path handed over at its last path's PathFinish, even
    one started 2.5 km ahead along its way: it holds the old path's end tangent (0.73.73, the user's test of 2026-11-02
    23:16: legs 0, down to 0.2 km 29 km out), while a slow one does (VOID WATCHER at 450-550 km/h took its climb-out ->
    lead-in handover). Put everything such a plane must fly into the path started at its appearance: the Ladons' route
    carries 15 laps of their circuit (survival_events.LADON_LAPS), and they looped the airfield 4 passes until shot down
    (0.73.75, the test of 23:31-23:39). Confirmed 2026-11-02.

59. The game reuses a freed object's address, and liveAddr (SV_ObjChain) passes for whatever lives there now. In the user's
    test of 0.74.34 (2026-11-08) a special's F-15E and Su-47 took dead ZFA-44s' addresses and were fitted with AC7's laser
    (sv_escort_li.lua checked the address alone). An object kept between ticks must still have the name it was captured
    with (ESC.same, sv_escort_laser.lua) before anything is done to it, above all before it's damaged or finished off.

64. A remote event fired while the host's landing minigames run (Landing, Hangar = the STORE, SeamlessOut) runs none of its
    records, though SV_Event answers 1: Saint Alessia's host of 0.74.36 (2026-11-10), STORE 18:47:27-18:48:06: the
    shuttle's T-4 and T (SV_ShuttleLaunched never set) and a flight's appearance orders were lost; events after it took
    with her still on the runway. A one-shot host event that matters is checked by its effect and fired again once the
    STORE is shut (sv_rounds_shuttle.lua SPC.storeShut: the shuttle's liftoff, its removal, the Spaceport's launch).

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
