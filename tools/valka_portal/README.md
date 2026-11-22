# tools/valka_portal: VALKA's portal, a black hole (3D)

`sh tools/valka_portal/build.sh` (Blender 3.3, UE 5.4 and the AC8 template project from `.env`; AC8 closed) ->
`build/valka_portal/out/SurvivalMode_ValkaPortal_P.utoc / .ucas`, staged by `tools/build_all.sh` with VALKA's X-02S.

- `make_portal.py`: the pieces, modelled from numbers (no source art): SM_SV_BHShadow, SM_SV_BHPhotonRing,
  SM_SV_BHHaloInner / Outer, SM_SV_BHDiskHot / Warm / Cool / Bright. 1 unit = the shadow's diameter; +Z its axis.
- `preview.py`: a Blender render of them as the game holds them (`-- <src> <out.png> [front|side|high] [red]`).
- `ue_import.py`: into /Game/Mods/SurvivalMode/ValkaPortal/Model, each slot on the engine's BasicShapeMaterial.

No material of ours (hard rule 58): Survival colours the pieces in game with AC8's own glow materials
(Scripts/sv_config_specials.lua CFG.specials.valka.portal). docs/re/VALKA.md section 8; hard rule 74 for the rolls.
