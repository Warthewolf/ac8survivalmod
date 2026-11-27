# Lua runtime (UE4SS Lua)

Rules for the Lua parts (Scripts/sv_*.lua) and what the UE4SS Lua API can and can't do.

Moved verbatim from AGENTS.md (2026-11-14). Rule numbers are unchanged: other notes cite them as "hard rule N".

9. UE4SS Lua `LoadAsset` can't load a mod's new packages (it goes through the asset registry). Use KismetSystemLibrary
   MakeSoftObjectPath -> Conv_SoftObjPathToSoftObjRef -> LoadAsset_Blocking.

10. Tables the game soft-loads (e.g. DT_LiveMenuMainTopCommands) must be loaded, edited and pinned
    (GameInstance.ReferencedObjects) before the game reads them, and watched for reloads.

11. DataTable RemoveRow + AddRow puts a row back in its old slot. To reorder, re-add both rows and check GetRowNames.

21. The game's own Lua (Lua 5.3, SingleGameluaContext) exists from the main menu, and its require() loads a
    /Game/LuaSource/<A>/<B>/<C> LuaScript from Survival's container: SV_GameLua (runtime 0.8.0) runs code in it.
    Confirmed by the same test ("packaged script via the game's require: true").

23. A Lua function (main.lua's main chunk too) may hold at most 200 locals in scope at once: past that the script
    doesn't load at all (UE4SS.log "too many local variables (limit is 200) in main function"; Lua 0.27.2 lost the menu
    entry that way). Put helper groups in `do ... end` blocks that export only what the rest calls. lua_check.py counts
    them and fails over 200. Confirmed 2026-10-22.

27. From Lua, a straight-down KismetSystemLibrary.LineTraceSingle only finds terrain near the player: far away it hits the
    sea planes (3-4 m everywhere; the terrain's collision isn't loaded there). Map data for a feature (beaches) comes
    from traces while the player is near the spot (Ctrl+F10 marks + coast rings). Test of 2026-10-22.

30. GetRowNames from UE4SS Lua may hand back plain strings, not FNames: read names through main.lua's rowList (ToString
    in a pcall, else tostring). A bare n:ToString() errored, the pcall swallowed it, and the STORE fell back to the
    shop rows although its pages were in (test of 2026-10-23).

47. In Lua, `a and f()` / `a or f()` keep only f's first value: `local ok, v = x and pcall(f)` always leaves v nil.
    VALKA's flare and paint variants 9-11 never built that way (test of 2026-10-25, "NOT up (nil)"). Write
    `if x then ok, v = pcall(f) end`; lua_check.py fails the build on the pattern.

63. GameplayStatics.ApplyDamage does nothing to AC8's Live objects, and its pcall succeeds: Saint Alessia's co-op run of
    0.74.36 (2026-11-10) "finished off" ZFA-44s 140 times (70 Helios blasts, every carrier leaving) and the same 24 lived
    to round 51 at full health; the shuttle took it and stayed "1 alive" until SV_Recycle. Finish an object with
    sv_core.lua finishUnpaid (mortal, MinHealth field 0, ModifyHealth(-(h / 10 + 1000), nil, true), read back): HealthInternal
    is health x 10, ModifyHealth takes plain health. Never count a kill without reading its health back.

71. UObject:GetPathName() isn't callable from UE4SS's Lua ("attempt to call a TrivialObject value (method 'GetPathName')"):
    read an asset's path from GetFullName ("Class /Game/.../Name.Name"). Every _DAM walk (sv_fleet.lua damFor, sv_anomalies.lua's
    dead look) failed on it inside a pcall that hid the error: the fleet's scars found 0 of 177 slots, AB.L..IN's dead look
    1 of 13. The probe of 0.74.142 (run 20261117_191507) found it; 0.74.143 scarred 131 of 177 (2026-11-17). Let a pcall
    that finds nothing say why (its error), or the next one stays hidden too. (65-70: the autotest branch's.)

72. Never index a game TArray past its end from UE4SS Lua, not even inside a pcall: `arms[i]` for i over the array's
    length reads whatever memory is there, and the game crashes (no Lua error to catch). 0.74.170 walked a railgun's
    FireControlSystemComponent.AllArms[1..4] on a two-arm array: the autotest's game crashed (access violation at 0x10) the
    moment RAILGUN_L deployed (run 20261118_012602); the same walk with `AllArms:ForEach(function(i, el) ... el:get() ...)`
    ran clean (0.74.171, run 20261118_013043, 40/40). Walk game arrays with ForEach (or read their length first).

76. A rotator (`{ Pitch, Yaw, Roll }`) handed from UE4SS Lua to an engine call loses its Pitch: Yaw and Roll arrive,
    Pitch is dropped, silently (no error). The autotest's solgpitch probe (0.75.27, run of 2026-11-22 22:35, a fresh actor's
    static mesh): K2_SetWorldRotation, K2_AddWorldRotation, K2_AddLocalRotation and K2_SetRelativeRotation with Pitch -45
    each left its forward vector level; Roll 45 turned it; K2_SetWorldTransform with the same turn as a quaternion pitched
    it 45 degrees. VALKA's SOLG flew flat through four builds for it ("its angle was still flat"). Tilt through a
    transform's quaternion (Scripts/sv_solg.lua quatOf / placeAt), or an actor's spawn transform; never trust a pitch
    set by rotator, and read a turn back (forward vector) when it matters.
78. K2_SetWorldTransform from Lua fails, silently inside a pcall, when its Scale3D is a vector read back from the engine
    (`c:GetComponentScale()`): nothing is placed or turned. ULYSSES' rocks (the autotest of 2026-11-24) kept their spawn's
    turn and flew backwards (their front -0.96 along their way) until the transform was given a plain table
    `{ X = 1, Y = 1, Z = 1 }` (then 1.00). Build every struct handed to the engine from plain Lua numbers, and read a
    turn back (forward vector) when it matters (hard rule 76).
