# VALKA's X-02S (AC7's model in AC8)

AC7 assets are allowed for VALKA only (AGENTS.md, user's exception of 2026-10-24). Nothing here is ever committed:
the inputs are the user's AC7 exports, the outputs go to `build/x02s/` and the UE project's ignored folders.

`tools/x02s/build.sh` (Git Bash; needs UE 5.4 at `E:/UE_5.4`, AC7's UModel, the AC7 export folder):

0. AC7's UModel exports `x02s_Anim` as `.psa` (`build/x02s/umodel`).
1. `prepare.py`: AC7's UModel glTF of the X-02S (skinned, 58 bones), with AC7's other X-02S meshes merged in on its
   Body bone (`x02s_GearOff_SM`, `x02s_RefuelOff_SM`, and `x02s_SWP3`, the EML housing in the belly between the
   engines, posed through its own bones: AC7 builds the aircraft from all of them, and without them she had holes),
   scaled to life size (19.6 m; AC7's models are
   about 1/9 scale, AC8's are life-size), the swing wings' keys from the `.psa`, the stock Osean skin (`00`, no emblem
   decals), a blank Livemap (all zero: AC8's neutral one), AC7 Mission 18's lens-flash textures (`T_SV_ValkaFlare_*`)
   and the portal's own generated textures (`portal_textures`: `T_SV_Portal_Disc / _Ring / _Glow`).
2. `ue_import.py` in the asset project `ue/Live` (named Live as AC8's own project, so cooked paths are
   `Live/Content` = `/Game`):
   - `MI_X02S_Valka` on AC8's own aircraft material `MP_PP0032_f18e_Decal` (Basecolor / Normalmap / Livemap), so the
     game draws it with its own shaders; AC8's materials are stubs at their own paths here and are never packed.
   - `SK_X02S_Valka` + skeleton + physics asset; AC7's sockets and the x40a's effect socket names as leaf bones
     (`burner_01` / `_02` at the nozzles, as AC8's aircraft name theirs).
   - `A_X02S_Valka_Sweep`: AC7's frames 50-100 on the `VariableWing_*` bones only (AC7 plays its parts
     rotation-only), each key turned into UE's bone frame by `ue_quat` ((x, -y, z, w): tools/re/VALKA.md 5); the log
     line "frame 0 vs rest |dot|" must read 1.0 for every bone.
   - `MI_SV_ValkaFlare_*`: one instance per lens-flash element on AC8's Mission 23 flare (`MI_ms23FarExp_Flare`,
     stubbed here), the textures as EmissiveMap / MaskMap. The portal's textures go in as they are (Lua puts them on
     AC8's own materials at run time).
   - `VIRTUAL` (top of ue_import.py) makes her paint textures virtual textures, as AC8's aircraft master needs, with
     `r.VirtualTextures` in `ue/Live/Config/DefaultEngine.ini`; off while the 0.69 crash is tested
     (tools/re/AIRCRAFT_MATERIALS.md 2).
   `ue_check.py` samples the sweep (tip sockets, every VariableWing bone) into `build/x02s/ue_check.log`.
3. Cook (Windows, VERSIONED: hard rule 42), 4. `retoc to-zen` of `/Game/Mods/SurvivalMode/Valka` only, 5. `pad.py`
   (hard rule 8) -> `build/x02s/out/SurvivalMode_Valka_P`. `tools/build_all.sh` stages it next to `SurvivalMode_P`.

In game (`Scripts/sv_anomalies.lua` `SPC.V.model`): at her reveal a SkeletalMeshComponent of ours is added to her (the
x40a's body is a static mesh: AGENTS.md hard rule 46) with `SK_X02S_Valka`, painted (`SPC.V.paint`, CFG.specials.valka
`paint`: AC8's aircraft master needs virtual textures, AC8's general masters take ordinary ones) and playing the sweep
by her speed (`sweep_kmh`, AC7's VwgMin / VwgMax 800 / 1000 km/h); the x40a's meshes are hidden, its railgun parts
gone and moved onto her, her hit spheres cut to `hit_radius_m`. Flight model and railguns stay the x40a's. The opener's
lens flash (`SPC.V.flareStart`) and her portal (`SPC.V.portalStart`) are MaterialBillboardComponents on actors Lua
spawns.
