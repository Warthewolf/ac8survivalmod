# Containers, packages and assets

Building the IoStore container, packages, cooked assets, materials.

Moved verbatim from AGENTS.md (2026-11-14). Rule numbers are unchanged: other notes cite them as "hard rule N".

7. New units need their blueprint packages added as imports AND in the container header, including the copy in the data folder.

8. Pad every .ucas so each compression block can be read rounded up to 16 bytes; otherwise the container doesn't mount
   ("Failed reading N bytes at offset ..."). tools/pack.py does it and checks every block.

31. A unit from another mission's world data can be copied whole into Survival's (build_survival.py port_unit: new
    names / UniqueIDs, no tags, our WorldDataName) when its AI objects have no ChildAIObjectDescs: its NPC rows come over
    with NPC_IMPORT and the spawner loads the blueprint from the DT_NPC row, no import needed (Mission 13's LCACs and
    BTR-90s, test of 2026-10-23). New AI paths (make_path, an existing path desc as the template) work for sea craft and
    for ground vehicles over Comona's terrain, and their PathFinish triggers fire, without updating the WD trailer.

32. Ported descs keep their mission's display: Mission 13's LCAC / BTR descs have no bShowHUDBox (no target box in
    Survival, test of 2026-10-23). Set bShowHUDBox and TargetMarkType (ELiveTargetMarkType 1 = TGT) on the AI objects
    (port_unit tgt=True): boxes and TGT marks showed (user, 2026-10-23).

34. A desc copied from another package must not keep object references (('obj', n > 0): an export of that package).
    Mission 16's Ladon path's PathTubeData names its tube object (export 75 there); copied as a path template, the game
    stopped loading Survival at the hangar: LowLevelFatalError AsyncLoading2.cpp:1814 "WD_SurvivalMode_global: Bad
    export index 74/19" (2026-10-23). make_path writes empty tube data; build_wd_global fails on any such reference.

42. Assets cooked in our own UE 5.4 (tools/x02s, project ue/Live) must be cooked VERSIONED (no -unversioned):
    AC8 runs Bandai Namco's own 5.4 build, whose reflected properties differ from stock (UTexture's do), so
    unversioned property data is read with the wrong layout and the game stops (LowLevelFatalError AsyncLoading2.cpp
    "ObjectSerializationError ... T_X02S_Valka_NO", 2026-10-24). Versioned (tagged) packages loaded fine the next test.
    New assets that use AC8's materials parent them on stubs at AC8's paths that are never packed.

44. AC8's aircraft skins (master /Game/Base/Material/Vechicle/MP/MP_Live_Vehicle_Base_UDIM) sample Basecolor / Normalmap
    / Livemap as virtual textures (every stock skin texture is a UDIM VT: docs/re/AIRCRAFT_MATERIALS.md,
    tools/checks/tex_info.py). An ordinary texture there draws pure black whatever the instance's values: VALKA's X-02S,
    tests of 2026-10-24 (paint variants 2-5 all black). AC8's general masters (MP_Live_Base_CameraDitherFade, _WPO,
    M_Live_Cha_Base) take ordinary textures on skinned meshes (from their shader maps; not yet seen in game). Don't ship
    virtual textures of our own: the 0.69 container with VALKA's paint as VTs loaded the mission in ~3.5 min and crashed
    AC8 at round 1 (GPUSortBatch, "resize TArray to an invalid size of 2147483648"); the same container with only those
    three textures ordinary loaded in ~33 s and ran a whole VALKA fight (A/B, 2026-10-25).

58. Materials we compile in our own UE 5.4 as new masters (tools/laser7's M_SV_TLS_*: AC7's Cascade beam) stop AC8's renderer
    when drawn: Alyssa's run of 0.74.30 crashed at the ZFA-44s' first volley, on the RHI thread in the Translucency pass
    (UECC AceCombat8.exe+0x34a8d68). AC8 runs Bandai's own 5.4 build, and our shaders don't bind there. Draw with AC8's own
    effects and materials instead: 0.74.31 used AC8's NS_UAVTLS_Muzzleflash01 for the same beam, and it fired and
    intercepted with no crash (2026-11-08). Hard rule 42's parent-on-a-stub route keeps AC8's shaders and stays safe.
