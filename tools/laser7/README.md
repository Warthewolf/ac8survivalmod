# AC7's LaserInterceptor in AC8 (tools/laser7)

The user, 2026-11-07: "I want the entire weapon from ACE7 to be ported over" (AGENTS.md's second AC7 exception: the
LaserInterceptor's values, swing curve, beam effects with their meshes, materials and textures, and sounds; never voice
lines). Research: docs/re/LASER_INTERCEPTOR.md (1: AC7's weapon; 9: AC8's native ALiveLaserInterceptor). Nothing of
AC7's is committed: only these scripts. Outputs go to the main tree's `build/laser7/`.

`sh tools/laser7/build.sh` (needs UE 5.4, AC7's UModel and AC7's exports from .env; the AC8 template project
`E:/AC8LiveProject`, which has AC8's own classes compiled, ALiveLaserInterceptor among them):

0. UModel exports AC7's beam meshes (SM_TLS_01, SM_TLS_projectile_root / _tip) as glTF and m_TLS_03's texture
   (T_rain_drop) to `build/ac7/laser/umodel` (once).
1. `ue_import.py` (UE Python in the template project): the meshes at AC7's own size as `SM_SV_TLS_*`, `T_SV_rain_drop`,
   and AC7's four materials rebuilt (cooked AC7 materials keep no graph: unlit, additive, two-sided, sprite and mesh
   particles, emissive = particle colour x alpha, x the texture for the sparks; `M_SV_TLS_01`, `_01_wire`, `_02`, `_03`).
2. `fxspec.py` / `spec.py`: AC7's two Cascade effects (UAssetGUI dumps in `build/ac7/laser/json`) into a build spec. AC7's
   cook baked most distributions into lookup tables; each is turned back into a constant, a uniform or a curve (a point
   an entry); the particle parameters (BeamLength, BeamLifeTime, LightLifeTime) stay. The spec also has AC7's swing
   curve (smoothstep 0 -> 1) and the weapon blueprint's values.
3. The `LaserFx` commandlet (the `SurvivalFx` editor module, `tools/laser7/cpp`, copied into the template project and
   built when its source changes; its .uproject / LiveEditor.Target.cs entries were added by hand, backups
   `*.before_survivalfx`) builds:
   - `CUR_SV_LaserInterceptorSwingRate`;
   - `FX_SV_UAV_TLS_Muzzleflash01` (6 emitters: Beam_Root, Beam_Tip, Beam_Tip_wire, omen, flash, Light_emitter) and
     `FX_SV_UAV_TLS_Muzzleflash02` (the end flash) as Cascade systems, AC7's numbers unchanged;
   - `BP_SV_LaserInterceptor`: a blueprint of AC8's `ALiveLaserInterceptor` with AC7's wp_LaserInterceptor values in
     AC8's units (RayDistance 124000, RayRadius 1500, InterceptAngle 180, SearchInterval 0.5, InterceptTime 1, the curve,
     LifeTime 6, damage 10, WID_AI_laser_interceptor); its MainLaser / EndLaser on the two effects at AC7's place
     (X -300), scaled x10 (AC7's world is ~0.1 m a unit) with AC7's particle parameters (BeamLength (12400, 1, 1),
     BeamLifeTime 6.2, LightLifeTime 5.5), EndLaser not auto-activated (AC7's blueprint lit it when the beam ended).
4. Cook, Windows, VERSIONED (hard rule 42), with the materials' shaders INSIDE their packages
   (`bShareMaterialShaderCode` off for this cook, on the command line): the four beam materials are new masters, so AC8's
   shader library has none of their shaders, and the template project's shared ShaderArchive never ships. AC8 runs DX12
   SM6 only (its paks: ShaderArchive-*-PCD3D_SM6), the template's only target. build.sh fails if a material's .uexp is
   under 60 KB (~780 KB each with the code, ~20 KB without).
5. `retoc to-zen` of `/Game/Mods/SurvivalMode/Laser7` -> `build/laser7/out/SurvivalMode_Laser7_P`, `pad.py` (hard rule 8).

`tools/build_all.sh` stages the container with ZFA=1 (it's the ZFA-44s' weapon); `package_*.sh` drop it without ZFA=1.

AC7's blueprint also ran a little script (docs/re/LASER_INTERCEPTOR.md 1d): on the beam's creation the main beam on and
the end flash off; each tick the beam's parameters; when the weapon's destroyed the beam thinning to nothing over 0.2 s;
when its life runs out the end flash. AC8's class carries the same fields natively (EndLaserTimer, EndLaserMaxTime,
LaserScale) and the two events (OnCreateWeaponEnd, OnLifeTimeExpired); Survival's Lua does that part
(Scripts/sv_escort_li.lua: the volley's beam on, its BeamLength, the end flash, the beam thinned), with AC7's fire control
(a volley of 6 s when an enemy missile is within 1.2 km, 8 s rest). The class's own search is off; Lua picks each
missile and the runtime hands it over (runtime/laser.c SV_LaserBegin: the class's BeginIntercept), the class swings and
kills (docs/re/LASER_INTERCEPTOR.md 9-10).
