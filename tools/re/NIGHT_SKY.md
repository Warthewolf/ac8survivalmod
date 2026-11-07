# Night sky: how Mission 9 does it, and what Survival's night lacks (research, 2026-11-07)

The user's ask (2026-11-07): Survival's night (round 9 of the arc) is "waaay to dark", the sea glows, and there are no
stars. Their screenshot: a very dark navy picture, the player's plane barely visible, cloud tops as dark shapes, a flat
blue-grey sea (the brightest thing on screen), no stars, no moon. This note covers the sky, the light, the exposure and
the stars. The sea's own material and the runway lights are in NIGHT_SEA_LIGHTS.md (another agent's).

Tags: **[D]** read from the data (stock packages, the exe, the user's logs), **[I]** inferred, **[T]** needs an in-game
test. Values are UE units (cm, EV100, lux) unless stated. Read-only research; nothing in Lua, the generators or the
runtime was changed.

Scratch scripts and dumps: `E:\ACE8 Survival Mode\build\research\night\sky\` (zd.py: export dumper with Vector3f;
csp_diff.py: CSP side by side; lit_scan.py: all 46 stock lighting sublevels; gfx_dt.py: graphics tables; bc6h.py: a
BC6H decoder that measures the sky-light cubemaps; natfn.py / dis.py: exe thunks and disassembly; *.txt: the outputs).

## 0. Summary

- **Why it is too dark.** Survival's night mixes a moon-level sun light (0.5) with a day exposure (min 10.5, bias -1.5,
  so EV 12 at least). Mission 9 runs its whole night at night levels: light 0.234, night sky-light cubemaps, and exposure
  0.5 / 9 / +0.5. At EV 12 the moonlight, the drawn sky, the clouds, the moon and the stars are all 12 stops or more
  below mid-grey. They come out black. **[D values, I result]**
- **Why the sea glows.** Survival's ambient light is still **Mission 4's day sky-light cubemaps**, at x0.1. Decoded, they
  average 2,000-4,400 (relative linear units). Mission 9's night cubemaps average **0.0095-0.0115**. So Survival's night
  ambient is about 20,000-45,000 times (2^14-2^15) Mission 9's, while its sun light is only 2x Mission 9's. The sea
  mirrors that bright day sky dome, so it is the brightest thing on screen. **[D numbers, I cause]** Mission 9 also turns
  the moonlight's specular down to 0.01, so the sea shows no moon glint. Survival's light keeps 1.0. **[D]**
- **Why 0.74.11 went white.** It used Mission 9's exposure (it can open up to EV 0.5) but kept the day ambient (a scene
  around EV 11). Exposure then hit its max of 9, so the scene was 2 or more stops over. The day ambient is the real fault.
  Exposure and ambient must change together. **[I]**
- **Why there are no stars and no moon.** Mission 4's Cloudly actor has **no `StarCatalog` and no `MoonTexture`** in
  `CloudlyResources`. Mission 9 has both, plus `GroundEmissiveTexture`; Mission 22 has the catalog only. Cloudly builds
  its star list only from the catalog, and skips the moon texture pass when the texture is null. **[D: the data and the
  exe]** Exposure would hide them too, even with the resources. **[I]**
- **The fix at run time (UE4SS Lua).** All of it, no build change needed:
  - Give the actor the catalog and the moon texture (`SetResourcesIncludingStars()`, or write the two fields).
  - Put Mission 9's night cubemaps into the sky-light controller, or scale the day ones by about 4e-6.
  - Use Mission 9's exposure (a little brighter: bias +1 to +1.5).
  - Set the light's specular scale to 0.01.
  - Apply Mission 9's star, moon and emissive values.
  
  Section 5 has the value-by-value set. **[I, T]**

## 1. Mission 9's lighting sublevel, side by side with Survival's (Mission 4) and Mission 22

`/Game/Maps/MapCommon/Map08/Mission009/Mission009_Common_Lit_Cloudly01` (in build/stock) **[D]**:

| export | Mission 9 (night) | Mission 4 (Survival's) | Mission 22 (Comona dawn) |
|---|---|---|---|
| LiveCloudlyActor_0 CSP / CVC | CSP_Mission009_kanno260116 / CVC_Mission009_kanno251006 | CSP_ms04_20251218b / CVC_ms04_20251216 | CSP_ms22_251208 / CVC_ms22 |
| CloudlyResources | BlueNoise, Transmittance, AP LUT, **MoonTexture `/Cloudly/Textures/StarsBackground/NasaCGIMoonKitLow`**, **StarCatalog `/Cloudly/StarCalalogs/ASCIIYaleBrightStarCatalog5`**, **GroundEmissiveTexture `/Game/Cloudly/Texture/T_Cloudly_GroundEmissive_MS09`** | BlueNoise, Transmittance, AP LUT only | + StarCatalog |
| bUseSkyLight / bUseHeightFog | 0 / 0 (Cloudly's own sky light and fog unused) | 0 / 0 | 0 / 0 |
| Directional Light Component | intensity **0.2337**, rot (-23.97, -32.26), LightSourceAngle 0.5683, **SpecularScale 0.01**, LightColor (255, 251, 242), ContactShadowLength 5000 | 120000, (-15, -128), 1.278, specular default (1.0) | 120000, (3.74, -149), 5.357 |
| BP_SkyLightController_C_1 textures | TC_Mission009_SkylightCube_BelowClouds / InLowerClouds / InClouds / InUpperClouds / AboveClouds | TC_Mission004_... | TC_Mission022_... |
| its transitions (cm) | the BP's defaults: grounds->bottom 100k-150k, bottom->top 300k-400k, top->sky 600k-700k | bottom->top 400k-800k, top->sky 800k-900k; AreaVolumeFraction 0.2527 | all 1,500,000 |
| MainSkyLight | Cubemap = BelowClouds; intensity not set (class default; read 1 in Survival [D log]) | same | same |
| sky-light blend volume | none | BP_SkyLightBlendVolume_BOX_C_1: **BlendCubemap TC_Mission004_SkylightCube_SeaArea**, at (1740868, 5289421, 45593), CubeExtents (4024882, 3439685, 62352) | one at Comona's runway, TC_Mission022_SkylightCube_LandingPoint |
| ExponentialHeightFog_0 | present but bVisible 0 (unused) | - | - |
| BP_PostProcessMisssionBase_C_0 . CockpitViewPostProcess | BP default only (priority 1000, AutoExposureLowPercent 50) | + **AutoExposureMinBrightness 11**, speeds 5 / 2.5 | + min 1.0, speeds 10 / 5 |

Post-process volumes **[D]**. Only the overridden values apply. Mission 9's PPV_1, PPV_2 and PPV_4 are disabled
(`bEnabled` 0); WEATHER_DAYNIGHT.md 1.3 lists their biases as if they were live. Mission 22's PPV_0 bias -3.32 is
not overridden, so it does nothing.

| level | volume | prio / bound | exposure (min / max / bias, speed up / down) | other overrides |
|---|---|---|---|---|
| M09 | PPV_3 | 5, unbound | **0.5 / 9 / +0.5**, 8 / 4 | bloom 2.4 (threshold -0.4), AO 1.0 / r 122, lens flare 0.0025 + MI_PP_CustomLensFlare_Mission009 |
| M09 | PPV_0 | 10, unbound | - | contrast 0.9, gain (0.91, 0.92, 0.95), gain midtones 1.28, gain shadows 0.97, gamma 0.95, gamma midtones 1.06, saturation 0.9, local exposure 1.1 / 0.95, WhiteTemp 7980, WhiteTint 0.0032 |
| M04 | PPV_1 | 5, unbound | 13 / 14 / 0, 5 / 2, method overridden (Histogram) | bloom 3, AO, lens flare M04, gamma 0.85, saturation 0.8, local exposure 0.96 / 0.95 |
| M04 | PPV_0 | 10, unbound | - | contrast 1.156, **gain shadows (0.54, 0.58, 0.64)**, gamma (1.07, 1.01, 0.96), WhiteTemp 5500, WhiteTint -0.15 |
| M04 | PPV_3 | 30000, bounded (BlendRadius 10000) at (-20880, -525365, 3412) | 13 / 14 / 0 | - |
| M22 | PPV_1 | 1, unbound | 4 / 14 / -2, 6 / 11 | bloom 3.6, AO, lens flare M22 |
| all | BP_PostProcessMisssionBase . PostProcessMisssionBase | -1 | - | AO, lens flare, FilmToe 0.25, vignette, motion blur (the shared base) |

Every other campaign lighting sublevel has a 120000 (or 60000) sun and exposure min 9-13. The one exception is Mission
22's dawn, at min 4 (lit_scan.txt). **Mission 9 is the game's only night.** Star catalogs are in Missions 9, 21, 22 and 30; moon textures in Missions 9, 20, 26 and 30.
**[D]**

## 2. CSP_Mission009_kanno260116 vs CSP_ms04_20251218b (FSkyParams fields that matter at night)

`-` = not serialized (the class default). Mission 22 is shown for the stars. **[D]** (csp_diff.txt has all 455
differing fields; most are cloud-shape fields.)

| field | M09 | M04 (Survival's asset) | M22 |
|---|---|---|---|
| SunElevation / Azimuth | 23.97 / -122.26 (the moon's spot) | 15 / 142 | -3.74 / 121 |
| SunIntensity.Factor / RGB | **0.2337** / (0.888, 0.965, 1.0) | 120000 / - | 120000 / - |
| SunDiskAngleInDegrees | 0.5683 (the moon's size) | 1.278 | 5.357 |
| EnableMoon | true | - (false) | - |
| MoonElevation / Azimuth | 24.05 / -122.29 (0.08 deg off the light) | - / 135 | 33.4 / 109.2 |
| MoonPhase / MoonPhaseAngle | 0.143 / 3.415 | - (0.15 / 0) | 0.644 / 6.096 |
| MoonFractionOfSunIntensity | **1e-5** | - (2.5e-6) | - |
| MoonDiskAngle / MoonDiskBrightness | - (0.5683 / -4) | - | - |
| StarsParams.StarsIntensity / BackgroundIntensity | **2.256 / 0.548** | - (4 / 0) | 7 / 22 |
| StarsRadius / TextureScreenFraction | 4.453 / - (0.5) | - (2 / 0.5) | 2.5 / 0.73 |
| StarsElevationMaskEnable / Start / Length | true / 0.110 / 0.716 | - (- / 0.05 / -) | true / 0.263 / - |
| StarsFadePower / ScintillationsPower | 14.77 / 0.850 | - | 14.70 / 0.326 |
| StarsMoonMaskEnable / Angle / Length | true / 0 / 0.235 | - | - |
| StarsGlobalRotation / StarsHashN | - | - | (2.578, 0, 0) / 5214 |
| MultipleScatteringScale / ScaleAP / FadeColorFactorAP | **3.0 / 3.0 / 0.450** | 1.446 / - / - | - / 0.694 / - |
| SigmaRayleigh.Scat.RGB | (0.246, 0.580, 1.0) | (0.229, 0.448, 1.0) | - |
| CloudSkyAmbientLightFadeToGray | **1.0** | 0 | 0.3 |
| CloudSkyAmbientLightOverlayColor / ReplaceColor | (0, 0.696, 1) / (1, 1, 1) | (0, 0.485, 1) / (0, 0.088, 1) | - / (1, 0.80, 0.80) |
| ShadowParams.GroundCloudShadowStrength | 0 | 0.756 | - |
| CloudGroundEmissiveIntensity / Color / Type / MipBias / HeightFalloff | 14 / (1, 0.76, 0.39) / 1 / 4.55 / 30 | - | - |
| CloudLayer2 StartHeight / Thickness | 18 km / 0.1 km | 13.1 km / 2.59 km | 14.2 / 0.25 |

What these mean:
- Night is a "sun" at the moon's spot with about 0.23 lux, tinted blue, its disc the moon's size. The moon is drawn
  with it, 0.08 deg off. **[D]**
- Mission 9's stars are tuned for its exposure, about EV 0. Mission 22's 7 / 22 are tuned for a dawn exposure of about
  EV 6 (min 4, bias -2). The gap in intensity (4.7) tracks the gap in exposure, so StarsIntensity is probably log2-like.
  **[I]**
- Swapping the whole asset to Mission 9's would also change the cloud layers (layer 2 at 18 km and 0.1 km thick,
  against 13 km and 2.6 km), so the clouds would jump. Write the night fields one by one, as the arc does. **[D/I]**
- sv_sky.lua's SP list has no entry for StarsElevationMaskEnable / Length, StarsFadePower, StarsScintillationsPower,
  StarsMoonMask*, StarsHashN, MultipleScattering*, CloudSkyAmbientLight* or GroundCloudShadowStrength. To write them,
  they need SP entries; their shipped values go in CFG.sky.arc.stock.asset so they can be put back (hard rule 56).
  Defaults the asset doesn't serialize must be read in game first (SKY.read). **[D code, T defaults]**

## 3. DT_Graphics_Mission009 vs DT_Graphics_CP_InGameBase (what Survival gets)

PL_SurvivalMode isn't in DA_PLGraphicsSettings_CP's PLDataMap, so Survival gets only the InGameBaseData row CPIN_001.
Missions layer their row over the base. **[D map, I layering]** Overridden values **[D]**:

| field (-> MPC) | InGameBase (Survival) | M09 Default_Setting_001 | M22 | M04 |
|---|---|---|---|---|
| MissionTime / MissionWeather | 0 / 0 | **Night** / Snow | - | - |
| CtrlSceneEmissiveScale (MPC_Env_Control Ctrl_Scene_EmissiveScale) | 1 | **10000** | 10000 | - |
| VFXEmissiveEV (MPC_VFX_Control) | 12 | **-2** | 5 | 11 |
| VFXBaseColorAdjust / VFXBaseColorIntensity (MPC_VFX_Control) | (1,1,1,1) / 1 | (3,3,3,1) / 6 | - | - |
| VFXAfterBurnerEmissive (MPC_VFX_Control) | - | 2 | - | 1 |
| VFXCloudlySkyAmbientLight (MPC_VFX_Control) | - | - | 0.2 | - |
| MECCockpitMFDEmissive / MECCockpitMeterEmissive (MPC_MEC_EmissiveControl) | - (1 / 1) | **0.0001 / 0.002** | 0.001 / 0.05 | 0.1 / 0 |
| MECIce_Emissive_Intensity | - | 0.0001 | - | - |
| MECNavigation / AntiCollision / Formation / LandingLight emissive | **0 / 0 / 0 / 0** | (not overridden) | - | - |
| bCanopyReflection | - | false | false | - |
| bIsSnowCovered | false | true | - | true |
| ConsoleVariables | DA_LCV_CP_InGameBase (Lumen off, OCIO clamp 0.95, Cloudly overlap) | **DA_LCV_Missioin009: r.MinScreenRadiusForLights 0.008**, GPUScene limits, VSM coarse pages 0 | - | - |
| NipcVfx (NIPC_VFX_Control) floats | none | VFXNIPCEmissiveEV 6, VFXAfterBurnerEmissive 5, VFXMissileSmokeIntensity 16, VFXSteamBrightness 25, VFXSteamBackLitIntencity 0.005, VFXSplashBrightness 0.12, VFXSplashWaveEmissive 22, VFXVaporConeEmissive 0.05, VFXNPCRibbonVaporEmissive 0.003, VFXMaingunTrailEmissive 0.0003, VFXMpbmEmissive 0.15, VFXCommonSmokeLow 1.5, VFXSignalFlareEmissive 1, VFXLCACSplashBritness 0.15, VFXRainSceneColorIntensity 0.9999, VFXRainPrismIntensity 0.002, VFXCanopyRefrectionIntensity 1, VFXWindIntensity 120 | 11 floats (EV 11, afterburner 6, ...) | 5 floats |
| NipcVfx vectors | none | VFXSunLightVector (-0.774, 0.483, 0.408) (towards the moon: (cos el cos(az-90), cos el sin(az-90), sin el)), VFXVaporBackLitColor (1.2, 1.2, 1.2), VFXWindDirection (-1, 0, 0.6) | ... | ... |

Notes:
- The night table dims the cockpit MFD to 0.0001 and the meters to 0.002. At night exposure, the stock 1.0 would blaze
  in cockpit view. **[D values, I reason]**
- The four aircraft-light emissives are 0 in the base for every mission. They are not a Mission-9-vs-Survival
  difference. Raising them at night might make planes' wing lights glow; whether they drive anything at all is open.
  **[D, T]**
- r.MinScreenRadiusForLights 0.008 lets small, far point lights draw. That matters for the city and runway lights
  (NIGHT_SEA_LIGHTS.md). **[D]**

## 4. Why there are no stars and no moon in Survival

1. **The catalog is missing [D].** Mission 4's `LiveCloudlyActor_0.CloudlyResources` has no StarCatalog (section 1).
   The renderer's star update (AceCombat8.exe 0x145c36040) reads its copy of the resources (renderer +0x3100; StarCatalog
   at +0x28).
   - When the catalog is null, the star list stays empty: the count at +0x3f00 is 0.
   - The GPU buffer "Cloudly.StarsDataBuffer" is only built when the count is above 0 (0x145c483fc).
   - The list is rebuilt whenever the catalog's SourceFile string, or one star parameter, differs from the cached one.
     It is checked on each update, so a catalog set at run time should be picked up. **[D code, I timing]**
2. **There is no background cube [D].** No stock level sets `StarsBackground`, so StarsBackgroundIntensity (Survival's 22)
   has nothing to draw. Cloudly skips that texture's pass when it is null (0x145c43078). **[D code, I effect]**
3. **The moon texture is missing [D].** The moon pass (0x145c4347d) jumps past everything when MoonTexture is null. With
   no texture there is no moon disc, however EnableMoon is set. **[D code, I effect]** The moon's brightness also differs:
   MoonFractionOfSunIntensity is 2.5e-6 in Survival's asset against Mission 9's 1e-5. **[D]** The custom moon API set
   MoonPhase to 0 in the sky test of 2026-11-07, which may be a new moon. **[D log, T meaning]**
4. **Exposure [I].** At EV 12, even catalog stars tuned for EV 0 to 6 sit 6 to 12 stops under.

**The fix, run time (UE4SS Lua) [T]:**
- `actor:SetResourcesIncludingStars()` (UFUNCTION, no parameters) on the level's LiveCloudlyActor (SKY.view's V.actor).
  - Its native code (exec 0x145bdd170 -> 0x145c2c100) StaticLoadObjects default resources into CloudlyResources:
    BlueNoise LDR_RGBA_7, RT_Transmittance, RT_AerialPerspectiveLUT, and, because it includes the stars, **MoonTexture
    NasaCGIMoonKitLow, StarsBackground NasaTychoSkymapHigh, StarCatalog ASCIIYaleBrightStarCatalog5**. Those are exactly
    Mission 9's. **[D]**
  - NasaTychoSkymapHigh is not cooked (only ...Small is), so StarsBackground stays null, with a load warning in the log.
    That is harmless. **[D chunk list, I]**
  - `SetResources()` is the same call without the last three. **[D]**
- Or write the two fields yourself:
  - `actor.CloudlyResources.StarCatalog = loadObject("/Cloudly/StarCalalogs/ASCIIYaleBrightStarCatalog5.ASCIIYaleBrightStarCatalog5")`
  - `actor.CloudlyResources.MoonTexture = loadObject("/Cloudly/Textures/StarsBackground/NasaCGIMoonKitLow.NasaCGIMoonKitLow")`
  
  Both are stock (Engine/Plugins/Cloudly/Content, pakchunk0), so loadObject's soft-path load works. Nested struct
  writes on objects hold in UE4SS: the sky test's `Settings.X` writes read back as written. **[D chunks, D log, T]**
- The actor is a level instance, so nothing outlives the level. Set both back to nil at the run's end for tidiness.
  Leave GroundEmissiveTexture alone: Mission 9's is Map08's city glow and would light Comona's clouds in the wrong
  places. **[I]**
- Build-time alternative: a Survival-owned copy of Mission 4's lighting sublevel with the two resources added (two
  imports + header, hard rule 7). The run-time write is simpler and needs no new package. **[I]**

## 5. The recommended night set (as close to Mission 9 as Comona allows)

The idea: copy Mission 9's whole night, not part of it. Then move it about one stop brighter for flying, because Comona
has no night city sublevel and no ground-emissive glow. Every value can be set at run time. "Now" = CFG.sky.night and
CFG.sky.stars in sv_config_specials.lua.

| lever (how, run time) | now | recommended | why |
|---|---|---|---|
| light: CSP SunIntensity.Factor / RGB (asset, as now) | 0.5 / (0.89, 0.96, 1.0) | **0.234 to 0.5** / (0.888, 0.965, 1.0) | Mission 9's moonlight is 0.234. 0.5 gives one stop more and is fine under the new exposure. |
| light: SunLight:SetSpecularScale (component, not driven by Cloudly [I]; put back 1.0) | 1.0 | **0.01** | Mission 9's. No moon glint path on the sea. [D value, T effect] |
| exposure: every volume with the override on (PPV_1, PPV_3, as now) | 10.5 / 14 / -1.5 | **min 0.5, max 9, bias +1.0 to +1.5**; speed up 8 / down 4 | Mission 9's 0.5 / 9 / +0.5, about one stop brighter. A night scene is about EV -2.6, so it sits at the min. Final EV is -0.5 to -1.0, so moonlit planes come out about half a stop under mid-grey. [I: estimated from the light and the cubemaps] |
| exposure: BP_PostProcessMisssionBase_C_0.CockpitViewPostProcess.Settings.AutoExposureMinBrightness (component; FindAllOf("PostProcessVolume") misses it) | 11 (untouched) | **0.5** at night, 11 after | Priority 1000. When active (cockpit view, [T]) it would hold the night at EV 11. |
| sky light, best: BP_SkyLightController_C_1.TextureBelowClouds / InLowerClouds / InTheClouds / InUpperClouds / AboveClouds = TC_Mission009_SkylightCube_* (call `ctrl:RegisterCubemapForPreCalculatation(tex)` for each first; MainSkyLight intensity 1, colour white) | day cubemaps x0.1, tint (0.55, 0.65, 1.0) | **Mission 9's five cubemaps, x1** | The night ambient at Mission 9's level (mean 0.0095-0.0115). A night capture, without the day sun's glow. [T: whether the controller takes new textures mid-run] |
| sky light, fallback: MainSkyLight Intensity (as now; writes hold [D log]) | x0.1 | **x4e-6** (4.8e-6 below the clouds, 2.4e-6 in them, 3.4e-6 above), tint about (0.85, 1.0, 1.0) | Mission 9's/Mission 4's mean, zone by zone, from the decoded cubemaps. Keeps the day cubemaps' layout but at night level. |
| sky-light blend volume: BP_SkyLightBlendVolume_BOX_C_1.BlendCubemap (then `ctrl:ResetAreaVolumeBlending()`) | TC_Mission004_SkylightCube_SeaArea (day) | **TC_Mission009_SkylightCube_BelowClouds** (registered), back at dawn | Covers Comona's southern sea (half-extents [I]: X -22.8..+57.7 km, Y +18.5..+87 km). Inside it the day sea cubemap (mean 1350) would blend in. With the fallback path the intensity scales it too. [D position, T] |
| emissive: MPC_Env_Control Ctrl_Scene_EmissiveScale (as now) | 100 | **10000** | Mission 9's and Mission 22's night value, right once the exposure is at night level. At 0.74.11 it blew out because the scene was at EV 11. |
| effects: MPC_VFX_Control VFXEmissiveEV (as now) | 7 | **-2** | Mission 9's. The effects' EV tracks the exposure EV (M04 13 -> 11, M22 about 6 -> 5, M09 about 0 -> -2). |
| effects: MPC_VFX_Control VFXBaseColorAdjust (vector) / VFXBaseColorIntensity / VFXAfterBurnerEmissive | 1 / 1 / 1 | (3, 3, 3, 1) / 6 / 2 | Mission 9's night effects. Optional. |
| cockpit: MPC_MEC_EmissiveControl Cockpit_MFD_EmissiveIntensity / Cockpit_Meter_EmissiveIntensity / Ice_Emissive_Intensity | 1 / 1 / 1 | **0.0001 / 0.002 / 0.0001** | Mission 9's. At night exposure the stock MFD glare would blind cockpit view. [T] |
| stars: CloudlyResources.StarCatalog | null | **ASCIIYaleBrightStarCatalog5** (section 4) | Without it no star is drawn. [D] |
| stars: StarsParams (asset; the new fields need SP entries) | 7 / 22 / 2.5 / 0.73 / (2.578, 0, 0) / 0.263 (Mission 22's) | **Mission 9's: intensity 2.26, background 0.55, radius 4.45, elevation mask on, start 0.110, length 0.716, fade power 14.77, scintillation 0.85, moon mask on, angle 0, length 0.235**; raise intensity by up to 1 if bias goes above +0.5 | Tuned for this exposure. Mission 22's 7 / 22 are for EV about 6 and would glare at EV 0. [I] |
| moon: CloudlyResources.MoonTexture | null | **NasaCGIMoonKitLow** | Without it no moon disc. [D] |
| moon: EnableMoon / el / az (asset, as now) | on, 35 / -130 | on, at the light's spot + about 0.1 deg (Mission 9: 24.05 / -122.29 vs the light 23.97 / -122.26) | Mission 9 draws the moon a hair off the light. |
| moon: MoonPhase / MoonPhaseAngle / MoonFractionOfSunIntensity (asset; SP has them) | not written (0.15 / 0 / 2.5e-6) | **0.143 / 3.415 / 1e-5** | Mission 9's moon. Write the phase explicitly, so a phase 0 left by the custom moon API can't hide it. [T: what phase 0 and 0.5 look like] |
| night sky: MultipleScatteringScale / ScaleAP / FadeColorFactorAP (asset, new SP) | 1.446 / - / - | 3.0 / 3.0 / 0.45 | Mission 9's. About twice the night sky's glow, so the sky is navy, not black. Optional. |
| clouds: CloudSkyAmbientLightFadeToGray / OverlayColor / ReplaceColor (asset, new SP) | 0 / (0, 0.485, 1) / (0, 0.088, 1) | 1.0 / (0, 0.696, 1) / (1, 1, 1) | Mission 9's moonlit grey clouds instead of the day's blue ambient. Optional. |
| clouds: ShadowParams.GroundCloudShadowStrength (asset, new SP) | 0.756 | 0 | Mission 9's: no cloud shadows on the ground under moonlight. Optional. |
| grading: PPV_0.Settings.ColorGainShadows / ColorContrast (struct writes) | (0.54, 0.58, 0.64) / 1.156 | (0.965, 0.968, 0.97) / 0.9 at night, back at dawn | Mission 4's day grade crushes shadows to about 55%. At night the whole frame is "shadow". [T: struct-of-vector writes from Lua] |
| VFX Niagara: NIPC_VFX_Control (NiagaraFunctionLibrary GetNiagaraParameterCollection -> SetFloatParameter / SetVectorParameter) | defaults | Mission 9's NipcVfx floats and vectors (section 3); VFXSunLightVector at Survival's moon (35 / -130 -> (-0.627, 0.527, 0.574)) | Night smoke, steam, splash and afterburner levels. Optional, last. [T] |
| cvar r.MinScreenRadiusForLights (KismetSystemLibrary ExecuteConsoleCommand) | engine default (0.03 [I]) | 0.008 at night, back after | Mission 9's: far city and runway lights still draw. [T] |

Run time vs build time:
- **Run time, all of the above** **[I, T for each new write]**:
  - the CSP asset (as now, restored per hard rule 56);
  - the actor's resources (a level instance);
  - the sky-light controller's textures and the blend volume's cubemap (level instances, gone with the level);
  - the light component's specular scale;
  - the post-process volumes and the cockpit component;
  - the three MPCs, the NIPC and the cvar.
  
  The MPCs, NIPC and cvar outlive the level: put them back in runLeft, as the MPCs are now.
- **Build time, only if a run-time write proves not to hold:**
  - a Survival copy of the Mission 4 lighting sublevel with the star and moon resources, or
  - Mission 9's lighting sublevel streamed hidden and swapped in (WEATHER_DAYNIGHT.md 2A).

  The swap is not recommended: Mission 9's CVC clouds, its Map08 ground-emissive map and its controller transitions
  would come with it, plus a second Cloudly actor. **[I]**

## 6. Risks and open questions

- **Exposure and ambient must move together [I].** Night cubemaps under the current exposure come out black. Mission 9's
  exposure with the day ambient comes out white (0.74.11). At the sunset-to-night swap, change both in the same fade
  (the arc's darkest-point swap).
- **The sky-light controller is native [D]** (ALiveSkyLightController; the Live module's thunks jump into obfuscated
  code at 0x15b...). It keeps a map of pre-calculated cubemaps (+0x528). RegisterCubemapForPreCalculatation adds one (a
  render command). Unknown **[T]**:
  - whether it re-reads TextureX every tick;
  - whether an unregistered cubemap is ignored, registered on demand, or used raw.
  
  Test: write the five textures plus registers, then watch whether the sea and plane ambient drop at once. The
  intensity fallback is known to hold (sky test step 4).
- **The cockpit PostProcessComponent [T]:** whether it is only active in cockpit view. Its min of 11 at priority 1000
  would beat everything at night.
- **Cloudly's stars at run time [T]:**
  - The resources copy from the actor to the renderer (actor +0x358, 0x40 bytes, copied at 0x145bf6b9e) looks per-frame.
    It was read from code, not seen in game.
  - Check SetResourcesIncludingStars, then look up at night. Log `actor.CloudlyResources.StarCatalog` before and after.
- **Moon phase and brightness semantics [T]:** MoonPhase 0..1 meaning, and the MoonDiskBrightness / Fraction scale.
- **Mission 9's cubemaps are Map08's [I]:** their faint directional glow (the -X face is about 2x brighter: Theve's
  side) won't match Comona's layout. Survival already uses Map05's day cubemaps on Comona, so this is no worse.
- **Planes' visibility:** moonlit at EV about -1 they should read. The base's aircraft-light emissives
  (MPC_MEC_EmissiveControl Navigation / AntiCollision / Formation) are 0 in every mission. Setting them to 1 at night is
  worth a try for seeing enemies. **[T]**
- **The sea (in passing; NIGHT_SEA_LIGHTS.md owns it) [I]:** three of its glow sources are in this note's levers:
  - the day sky-light cubemaps it mirrors;
  - the moon light's specular (1.0 vs Mission 9's 0.01);
  - the SeaArea blend volume's day cubemap south of the runway.
  
  With Mission 9's ambient (about 0.01) its reflections sit below the moonlit land, as in Mission 9. Anything the sea
  material adds by itself is the other note's.
- **Mission 4's PPV_3 [D]** (priority 30000, bounded, 16 km west of the runway) also holds exposure 13 / 14 inside it.
  sv_sky already writes it (its overrides are on); keep it in the night set.

## 7. Test plan (TEST ONLY keys, one build)

1. **Read.** Log the actor's CloudlyResources (all 8), the controller's 5 textures and CurrentTextureAreaVolume, the blend
   volume's BlendCubemap, MainSkyLight Intensity / Cubemap, the sun light's SpecularScale, every PostProcessComponent's
   bEnabled / Priority / exposure (chase view and cockpit view), and MPC_MEC_EmissiveControl's four aircraft-light values.
2. **Stars.** Call `SetResourcesIncludingStars()`, set the night CSP values and Mission 9's exposure, and look up. Do
   stars and the moon disc appear? Log the resources again.
3. **Ambient.** Register and write Mission 9's five cubemaps. Over the sea: does it go dark at once? Fly into the southern
   blend volume with and without its BlendCubemap swapped.
4. **Specular.** `SetSpecularScale(0.01)`, then look along the moon's bearing over the sea.
5. **Put back.** Everything put back: day values, resources nil, textures and cubemaps as read in step 1, specular 1,
   MPCs, cvar. Compare with step 1.
