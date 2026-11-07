# Night: the sea and the runway lights (research, 2026-11-08)

The user, 2026-11-07, after round 9 of the arc's night: "this night is waaay to dark, but we need a way to make is so the
sea doesn't glow so badly, also theres no visible stars" and "is it possible for you to add runway lights to the comona
airfield". This note covers two things: why Comona's sea glows at Survival's night and how to stop it (A), and runway /
airport lights at night (B). The sky itself (Mission 9's lighting, CSP, exposure, stars) is in
[NIGHT_SKY.md](NIGHT_SKY.md). Read only: nothing in Survival changed.

Tags: **[D]** read from the game's data (the package is named), **[I]** inferred, **[T]** needs an in-game test.

Scripts and decoded data: `E:\ACE8 Survival Mode\build\research\night\sea\` (git-ignored). `nd.py` dumps a package's
exports, `micmp.py` puts material instances side by side, `chain.py` walks a material instance up to its master,
`bc6h.py` decodes AC8's BC6H sky-light cubemaps and prints their radiance, `cubepng.py` renders one as a PNG
(`cube_m004_below.png`, `cube_m009_below.png`, `cube_m022_below.png`, `cube_m004_seaarea.png`), `lvl.py` surveys a level,
`gfx.py` compares DT_Graphics rows, `emscan.py` lists the emissive materials on Comona's placed meshes (`emscan.txt`).

## 0. Summary

- **Why the sea glows.** Survival's sea is an opaque, reflective material (Mission 22's ocean). At night it reflects the
  level's sky light. That sky light still blends **Mission 4's daytime cubemaps** (a sunlit sea photograph), cut to
  x0.1 and tinted blue. Their horizon band is about 5,300 (cd/m²-like units); Mission 9's night cubemaps are about
  0.015 there. So the sea mirrors a sky about **23,000-36,000 times brighter** than a stock night sky (with and without
  the blue tint) [D values, I product]. NIGHT_SKY.md measures the same gap on the averages. The moon (0.5 lux)
  is a thousand times weaker than that sky light, so it lights nothing that shows. The land gets only the sky light's
  diffuse part, while the sea gets its mirror part at grazing angles. The result is a sea 2-5 times brighter than the
  land [I, from the numbers in 2.4]. In Mission 9 it is the other way round: the sea is about half as bright as the
  moonlit land.
- **Nothing else feeds the glow.** In game, Lumen is off. No reflection capture is placed in any of Survival's
  sublevels. The sea has no emissive or cubemap input of its own, and it doesn't read MPC_Env_Control (Survival's
  "city glow" scale) [D].
- **Levers, best first:**
  1. Night cubemaps in the sky light (Mission 9's `TC_Mission009_SkylightCube_*`, five slots of the level's
     `ALiveSkyLightController`, plus Mission 4's sea-area blend volume). This fixes the sea, the land and the planes'
     ambient light together, but only with an exposure near Mission 9's. That part belongs to NIGHT_SKY.md.
  2. A sea-only fix, if the sky light keeps its day cubemaps: run-time dynamic instances (MIDs) of the sea's own 129
     material instances, with the layer's `Specular` 0.2 -> 0, or Mission 9's values. Alternatively, the sky light's
     `bAffectReflection` turned off at night.
  3. Whatever exposure is chosen, keep the moon light's `SpecularScale` at Mission 9's 0.01 when the exposure drops,
     or the moon draws a white glitter path on the sea.
- **Runway lights already exist.** Survival loads Comona Airport's full lighting: 1,049 additive glow billboards
  along the runway edges, centre line, touchdown zone, approach, end bars, taxiways and apron, plus 855 centre-line
  fixtures, 99 edge-light fixtures, PAPIs, approach structures and two beacons [D]. They are invisible now because
  their glow is about 0.3 x `Ctrl_Scene_EmissiveScale`, Survival's night writes that scale as 100 (the stock night is
  10,000), and the night exposure is held at EV 10.5. At that exposure the glow comes out about 300 times too dim [I].
  - (a) With a Mission 9-like exposure, the stock 10,000 lights them as Mission 22 does.
  - (b) At a high exposure, give the airport its own MIDs (about 14, on about 2,000 components) with a raised
    `EmissiveIntensity`.
  - (c) Or spawn about 120 screen-space glow sprites at run time from Lua, as VALKA's lens flash does: a
    MaterialBillboardComponent on an instance of AC8's Mission 23 flare.
- **Risks.**
  - `Ctrl_Scene_EmissiveScale` also drives the walls and windows of about 14,600 town placements (section 9). Don't
    raise it for the runway alone.
  - Never lower the exposure while the day cubemaps are still in the sky light: that is the 0.74.10 white-out.
  - 1,500-2,000 SetMaterial calls in one tick hitch the game. Spread them out.
  - MIDs must be put back, the level overrides included (the sea draws `_I26` instances, not the meshes' `_I04`).

## A. The sea

### 1. What draws Comona's sea in Survival [D]

`PL_SurvivalMode` streams `Mission022_Common_Env_Sea` (Survival's built level, read from
`mod/Content/Mods/SurvivalMode/Maps/PL_SurvivalMode.umap`). Its components:

| Components | Mesh | Material on the component (level override) |
|---:|---|---|
| 1,430 | SM_TER_Map17_Loop_Sea_I04 (4.43 km planes, z 350) | MI_TER_Map17_Loop_Sea_I26 |
| 128 | SM_TER_Map17_<tile>_Sea_I04 | MI_TER_Map17_<tile>_Sea_I26 (one per tile) |
| 1 | SM_SeaBaseMesh (scale 50, z -10 m) | MI_TER_Map17_Loop_Sea_I26 |
| 1 | SM_TER_Map07_Seabed001_I04 | the mesh's own |
| 1 | SM_TER_SeaCollision_I04 | hidden (collision only) |

All 1,559 visible sea planes have `CastShadow` false. Correction to COMONA_MAP.md: the meshes' own `_I04` materials
(parent Mission 19's TilemeshBase) are **not** drawn. Mission 22's level overrides them with `_I26`, which are parented
to Mission 22's.

The material chain:

| Level | Package | What it sets |
|---|---|---|
| tile | `/Game/Environments/Terrain/Ground/Map17/Material/Sea/MI_TER_Map17_<tile>_Sea_I26` | SatelliteMap = the tile's `T_TER_Map17_<tile>_I04_D` (the loop: A01's) |
| base | `/Game/Sea/Mission022_Sea/MI_OceanH00_Mission022_TilemeshBase` | static permutation (its own shader map, 180 KB); layer stack = `MLI_Ocean_Mission022`; FoamMap, FoamHeightMap, OceanAttributeTexture `T_SeaAttribute_Map017` |
| | `/Game/Sea/Mission022_Sea/MI_Ocean_022` | ShadingModel override Subsurface |
| master | `/Game/Sea/Material/M_Ocean` | **opaque**, ShadingModel **Subsurface** (2), material attributes + layers, `bScreenSpaceReflections`, used with water / Nanite |
| layer | `/Game/Sea/Mission022_Sea/MLI_Ocean_Mission022` (parent `MLI_Ocean` -> `ML_Ocean`) | every look value (table below) |

- Collections the sea reads (the cooked material's imports): `MPC_VFX_Control` and `MPC_LiveOceanPrd` only. Not
  `MPC_Env_Control`. The likely use of `MPC_VFX_Control` is `VFXOceanScrollTextureSize` (default 9,000,000, next to
  the static switch `Use_CinemaOceanScrollTestureSize`) [I]. `MPC_LiveOceanPrd` holds the wave controller's values
  (SplashIntensity, DistortionStrength, WaveViewDistance, WaterPlaneLocation, WaveViewLocation) [D].
- Textures in the chain: foam, water height and normal maps, satellite colour, depth map, attribute map, noise, T_Gray,
  T_White. **No cubemap or reflection texture** [D].
- Parameter names: `Specular`, `Roughness`, `RoughnessFresnelScale`, `FarRoughness`, `BaseColor`, `General Color`,
  `Ocean Deep Color`, `SubsurfaceColor`, `SubsurfaceOpacity`, `ExtinctionColor`, `ScatteringIntensity`,
  `SunlightScatterBoost`, `ReflectedScatterBoost`, `Bubble Scatter Boost`, `OverallBoost`, `FoamColor`,
  `FoamIntensity`, `SatelliteIntensity`, `ShallowColorHueShift / ValueChange`, ... There is no `Emissive` parameter
  [D]. The scattering function (`MF_OceanWater_Scattering_InGame`, from the InnotechOceanWater plugin) is stripped in
  the cooked build. Whether its output is lit or added like an emissive is unknown [I].
- In the material, these are **layer parameters**. The tile instances store them as `{Name, Association =
  LayerParameter (0), Index = 0}`, so a MID must set them "by info" with that association (4.2) [D].

Layer values that matter (`micmp.py`):

| Parameter | Mission 22 (Survival's sea) | Mission 19 (Comona) | Mission 9 (night, Map08) | Terrain water layer (`MLI_Ocean_Env`) |
|---|---|---|---|---|
| Specular | 0.2 | 0.1 | **1.0** | 0.2 |
| Roughness / FarRoughness | 0.225 / 0.2 | 0.225 / 0.3 | **0.0 / 0.1** | 0.2 / - |
| RoughnessFresnelScale | 0.7 | 0.7 | 0.7 | 0.5 |
| BaseColor | (0.0092, 0.0256, 0.0417) | same | **(0.001, 0.007, 0.010)** | - |
| General Color / Ocean Deep Color | (0.0099, 0.0885, 0.0730) / (0.0057, 0.0298, 0.0417) | same | not set (MLI_Ocean's) | (0.005, 0.047, 0.039) / 0 |
| SubsurfaceColor / SubsurfaceOpacity | default / 0.03 | same | **(0.045, 0.065, 0.12)** / 0.1 | 0 / 0.03 |
| ScatteringIntensity | 1 | 1 | **0** | 1 |
| SunlightScatterBoost / Bubble Scatter Boost / OverallBoost | 0.1 / 15 / 0.025 | same | not set | 0.1 / 0 / 0.5 |
| FarBegin | 200,000 | 200,000 | 25,000 | - |
| FoamColor / FoamIntensity | (0.45, 0.51, 0.51) / 1 | same | (1.4, 2, 2) / 3.5 | - |
| SatelliteIntensity (loop sea) | 1 (tile A01's colour) | - | **0.048** (T_Gray) | - |

The terrain's coastal water: 16 terrain tiles (`MI_TER_Map17_<tile>_I04`, `USE_LayerWater`) blend the layer
`MLI_Ocean_Map17_Env` (parent `MLI_Ocean_Env`) into `MP_TER_Map17_I04` -> `M_TerrainBase_Dev`. The terrain's shading
model is "from material expression" (land DefaultLit, water Subsurface). It reflects like the sea (Specular 0.2) [D].

Other water parts:
- `BP_LiveWaveController` (WaveViewDistance 89,250) only drives the wake / wave render target and MPC_LiveOceanPrd [D].
- The `WaterZone` with its `WaterMeshComponent` in Map17_Env_CityMap001 has no water bodies anywhere on the map. It
  draws nothing [I].

### 2. What lights it

**2.1 The renderer in game [D].**
- `DA_LCV_CP_InGameBase` (the graphics row Survival gets, WEATHER_DAYNIGHT 1.3) sets `Live.Lumen.Enable 0` and
  `r.SSR.ExcludeTranslucency 1`. So in game there is no Lumen GI or Lumen reflection, although DefaultEngine.ini
  defaults to Lumen.
- Reflections are therefore screen-space reflections (Mission 4's volume: ScreenSpaceReflectionMaxRoughness 0.85),
  falling back to the reflection environment. The reflection environment is the **sky light alone**:
  `level_classes.json` and the lighting sublevel list no ReflectionCapture or PlanarReflection actor in any of
  Survival's 13 sublevels.
- Out to sea, SSR finds nothing on screen to reflect except the sky, which is a miss. **What the sea shows is the sky
  light's cubemap** [I].

**2.2 The sky light [D].** Mission 4's lighting sublevel (`Mission004_Common_Lit_Cloudly01`, Survival's) has:
- `BP_SkyLightController_C_1`, a Blueprint on the native `ALiveSkyLightController`. Its `MainSkyLight` (a
  SkyLightComponent, `Cubemap` TC_Mission004_SkylightCube_BelowClouds) blends five cubemaps by camera height:
  `TextureBelowClouds / InLowerClouds / InTheClouds / InUpperClouds / AboveClouds`, with transitions 4-8 km and 8-9 km.
  It does this through `SetCubemapBlend`, plus this game's extra `BlendDestinationCubemap` / `BlendAdditionalCubemap`.
- The native class has the BlueprintCallable functions `RegisterCubemapForPreCalculatation(UTextureCube*)`,
  `NotifyVolumeIn / NotifyVolumeOut(volume, blend s)`, `ResetAreaVolumeBlending()` and `SetIGCMode` (header
  `build/liveproject/Source/Live/Public/LiveSkyLightController.h`).
- `BP_SkyLightBlendVolume_BOX_C_1` with `BlendCubemap` = `TC_Mission004_SkylightCube_SeaArea`. It sits at Map05's
  coordinates (1740868, 5289421, 45593), with extents 40.2 x 34.4 x 0.62 km. On Comona that box covers the open sea
  south of the island, x -22.8..57.6 km, y 18.5..87.3 km, below about 1.08 km altitude. Flying low there blends in
  another **day** cubemap [D placement, I behaviour].
- Mission 22's lighting (not loaded by Survival) has its own blend volume over Comona's runway
  (`TC_Mission022_SkylightCube_LandingPoint`, extents 2.28 x 0.27 x 0.11 km, yaw -23.3) [D].

The cubemaps, decoded (`bc6h.py`; 256 x 256 x 6, BC6H, one mip). Values are the texel-solid-angle-weighted mean
luminance:

| Cubemap | Horizon band 0-15 deg | Upper hemisphere | All directions | Zenith > 60 deg |
|---|---:|---:|---:|---:|
| TC_Mission004_SkylightCube_BelowClouds (Survival, day) | 5,316 | 2,751 | 1,954 | 652 |
| TC_Mission004_SkylightCube_InLowerClouds | 4,915 | 2,171 | 2,021 | 516 |
| TC_Mission004_SkylightCube_AboveClouds | 2,121 | 850 | 3,402 | 215 |
| TC_Mission004_SkylightCube_SeaArea (blend volume) | 2,761 | 2,225 | 1,364 | 1,174 |
| TC_Mission022_SkylightCube_BelowClouds (Comona, dawn) | 19.8 | 9.1 | 5.9 | 2.9 |
| TC_Mission009_SkylightCube_BelowClouds (night) | 0.0149 | 0.0136 | 0.0094 | 0.0054 |
| TC_Mission009_SkylightCube_InLowerClouds | 0.0173 | 0.0109 | 0.0093 | 0.0047 |
| TC_Mission009_SkylightCube_AboveClouds | 0.0191 | 0.0107 | 0.0114 | 0.0037 |

The previews show what each one is. Mission 4's is a photograph of a sunlit sea with mountains and a blue sky.
Mission 22's was captured on Comona at dawn (the long bridge is in its lower face). Mission 9's is a dark cloudy night
sky over the sea [D, previews].

**2.3 Survival's night (CFG.sky.night, sv_sky.lua).** The sky light runs at x0.1 of its intensity, tinted (0.55, 0.65,
1.0), a luminance factor of about 0.65. Its horizon band is then about 5,316 x 0.1 x 0.65 = **350**, against Mission 9's
0.015: about **23,000 times** a stock night sky [D values, I product]. The "moon" is the sun light at 0.5 lux, with
`SpecularScale` 1.

**2.4 The balance between sea and land** [I: UE's split-sum reflectance approximation, land albedo 0.15]

The sea's mirror reflectance at grazing angles (EnvBRDF, roughness about 0.2), seen from 2.5 km up:

| Specular (F0 = 0.08 x Specular) | ~4 km out (60 deg) | ~10 km out (76 deg) | ~24 km out (84 deg) |
|---|---:|---:|---:|
| 0 | 0 | 0 | 0 |
| 0.05 | 0.011 | 0.039 | 0.090 |
| 0.2 (Survival's sea) | 0.043 | 0.156 | 0.359 |
| 1.0 (Mission 9, roughness 0-0.1) | 0.12 | 0.26-0.29 | 0.53-0.59 |

Specular 0 removes the reflection completely: UE scales the grazing term by saturate(50 x F0) [I].

| Night | Sky light on land | Moon on land | Land luminance | Far sea (reflection) | Sea : land |
|---|---:|---:|---:|---:|---:|
| Survival now | ~565 lux (day cubemap x0.1) | 0.5 lux | ~27 | 54-125 | **2 - 4.6** |
| Mission 9 | ~0.043 lux (night cubemap) | 0.234 lux | ~0.013 | 0.004-0.009 | **0.4 - 0.7** |

On screen, with UE's exposure scale 2^bias / (1.2 x 2^EV100) [I], Survival's night (EV clamped at 10.5, bias -1.5,
scale about 2.0e-4) gives:
- the land about 0.0055 (sRGB about 15/255),
- the sea 0.011-0.026 (sRGB about 26-45/255),
- the night sky near black.

That is the user's screenshot: a dark navy picture whose brightest thing is a flat blue-grey sea.

**2.5 The moon's glint.** Mission 9's moon light has `SpecularScale` **0.01** and intensity 0.2337 [D]. At Survival's
EV 10.5 the 0.5 lux moon's highlight is invisible. At a Mission 9-like exposure (scale about 0.8), a full `SpecularScale`
moon on a 0.2-rough sea peaks at about 1-2 display units: a white glitter path [I].

**2.6 What doesn't light the sea** [D, I where marked]
- `MPC_Env_Control` (`Ctrl_Scene_EmissiveScale`, `Ctrl_Env_MissionEmissiveCondition`): the sea doesn't import it.
  Survival's city-glow write (100) doesn't touch the sea.
- `MPC_VFX_Control`: imported, but most likely only for the scroll texture size [I]. `VFXEmissiveEV` and
  `VFXCloudlySkyAmbientLight` are untested on the sea [T, test S4].
- Reflection captures: none. Lumen: off. WaterZone: inert. Wave controller: waves only.

### 3. How a stock dark mission keeps its sea right [D]

Mission 9 (`PL_Mission009`, Map08, clock 23:00) streams `Mission009_Common_Env_Sea`: 41 sea planes with
`MI_OceanH00_Mission009_*` (24 of them `_LoopSea01`), a level Blueprint and a wave controller. Mission 9 gets its night
from four things together:

1. **Night cubemaps** in its sky light controller (TC_Mission009_SkylightCube_*, 2.2). `MainSkyLight` is at default
   intensity, so the sea mirrors a sky of about 0.015.
2. **A real moon light**: 0.2337 lux, colour (242, 251, 255), `SpecularScale` 0.01, `LightSourceAngle` 0.568. It, not
   the sky, is what lights the land.
3. **Exposure for that light**: PostProcessVolume_3 (priority 5) AutoExposure min / max **0.5 / 9**, bias +0.5, speed
   up 8 / down 4; BloomIntensity 2.4, threshold -0.4. Volumes _1, _2 and _4 are disabled; _0 grades only.
4. **A mirror sea in a dark colour**: MLI_Ocean_Mission009 has Specular 1, Roughness 0, ScatteringIntensity 0,
   BaseColor (0.001, 0.007, 0.010), SubsurfaceColor (0.045, 0.065, 0.12). The far sea's satellite tint is cut to
   0.048. The city lights' reflections (SSR) are what show on it.

Its graphics row (`DT_Graphics_Mission009`, Default_Setting_001, `gfx.py`):
- MissionTime 3 (Night), Weather 4,
- **CtrlSceneEmissiveScale 10,000**, MissionEmissiveCondition 1,
- VFXEmissiveEV -2, VFXBaseColorIntensity 6, VFXBaseColorAdjust (3, 3, 3),
- MECCockpitMFDEmissive 0.0001, MECCockpitMeterEmissive 0.002, bCanopyReflection off,
- console variables `DA_LCV_Missioin009`: r.MinScreenRadiusForLights 0.008, r.GPUScene..., r.Shadow.Virtual.MarkCoarsePagesDirectional 0.

Mission 22 (Comona at dawn, the same sea as Survival) has:
- its own Comona dawn cubemaps (2.2) and a runway blend volume,
- exposure min / max 4 / 14 with bias -2 and -3.32,
- graphics row CtrlSceneEmissiveScale 10,000, VFXEmissiveEV 5, **VFXCloudlySkyAmbientLight 0.2**, cockpit MFD 0.001,
- `r.MinScreenRadiusForLights 0.006`.

Survival's `DT_Graphics_CP_InGameBase` row has CtrlSceneEmissiveScale 1, VFXEmissiveEV 12, and doesn't set
MissionEmissiveCondition (so the collection's default of 1 applies). Mission 4's own row sets MissionEmissiveCondition 0
("lights off by day"), but Survival doesn't use that row [I, WEATHER_DAYNIGHT 1.3].

### 4. Levers to stop the sea glowing

| # | Lever | Night value | Effect on the sea | When / how | Tag |
|---|---|---|---|---|---|
| 1 | Sky light cubemaps: the controller's five `Texture*` slots | Mission 9's five (`/Game/Lighting/Texture/HDRI/Mission009/TC_Mission009_SkylightCube_*`), each registered with `RegisterCubemapForPreCalculatation`; day ones back at sunrise | Reflection about 23,000x dimmer; the land ambient too. Needs an exposure near Mission 9's | run time: BlueprintReadWrite properties and UFUNCTIONs on the live controller | [D] API, [T] |
| 1b | The sea-area blend volume (`BP_SkyLightBlendVolume_BOX_C_1`) | its `BlendCubemap` -> a night cubemap, or `NotifyVolumeOut` + `ResetAreaVolumeBlending` | stops the day "SeaArea" cubemap coming back low over the south sea | run time | [I/T] |
| 1c | Instead of 1: the sky light's intensity with the day cubemaps | x0.1 -> about x3e-6 (Mission 9's level) | same brightness as 1, but the day photo's look stays (a bright horizon band, mountains) | run time (`SetIntensity`, already written by sv_sky) | [I] |
| 2 | `MainSkyLight.bAffectReflection` | false at night | the sky light leaves every reflection: sea, canopy and paint. The sea keeps its diffuse / subsurface part only | run time: write the property, then make the proxy rebuild (SetVisibility false / true over two ticks; `SetIntensity` only updates the existing proxy) | [I/T] |
| 3 | Sea MIDs: layer-0 `Specular` | 0.2 -> 0 (no reflection) or 0.05 (a quarter, 2.4) | sea : land drops from 2-4.6 to about 0.15 (diffuse only) | run time, 129 MIDs (4.2) | [I/T] |
| 3b | Sea MIDs: Mission 9's look | Specular 1, Roughness 0, ScatteringIntensity 0, BaseColor (0.001, 0.007, 0.01), SubsurfaceColor (0.045, 0.065, 0.12) | a dark mirror. **Only together with lever 1**; with the day cubemaps it glows more | run time | [I/T] |
| 4 | The moon light's `SpecularScale` | 1 -> 0.01 (Mission 9) | no glitter path once the exposure is low | run time: ULightComponent::SetSpecularScale. Cloudly drives rotation, intensity and colour (hard rule 56), not this [I] | [I/T] |
| 5 | "Day for night" instead of 1 | moon (CSP SunIntensity.Factor) about 1,000-2,000 lux bluish; sky light day x0.005-0.01; exposure kept near 10.5 | land about 74 (display 0.015) and lit by the moon; far sea 4-9 plus a glint: sea : land about 0.1 | run time, all existing writes (NIGHT_SKY.md decides) | [I/T] |

Not levers: `MPC_Env_Control` (not read by the sea), `MPC_LiveOceanPrd` (waves), reflection captures (none),
SatelliteIntensity (shallows colour only) [D/I].

**4.1 Recommended order.**
1. Lever 1 with the sky agent's exposure, plus lever 4. This is the stock night.
2. If the night must stay at a high exposure: lever 5, or lever 2 / 3 on top of today's sky.
3. Lever 3 alone is the smallest change that stops the glow. It leaves the rest of the night as dark as now.

**4.2 Sea MIDs, how [I/T].** Survival already makes MIDs at run time:
`kml:CreateDynamicMaterialInstance(survivalPC, mi, FName("None"), 0)` and `comp:SetMaterial(i, mid)` (sv_zfa44.lua,
sv_anomalies_valka.lua). For the sea:
- **Find the components.** FindAllOf("StaticMeshComponent"), keeping those whose full name holds
  `Mission022_Common_Env_Sea` and whose `GetMaterial(0)` name ends `_Sea_I26` (1,559 components). Remember each one's
  original material.
- **Make the MIDs.** One per distinct original: 129 (128 tiles, which each need their own satellite map, plus the loop
  material, shared by 1,431 components).
- **Set the values.** The look values are layer parameters. `SetScalarParameterValue(FName("Specular"))` targets a
  *global* parameter and would miss them. Use `SetScalarParameterValueByInfo({ Name = FName("Specular"), Association =
  0 --[[LayerParameter]], Index = 0 }, v)`, and `SetVectorParameterValueByInfo` for the colours. Read one back with
  `GetScalarParameterValueByInfo` [I: UE 5.4 API; T: works from UE4SS].
- **Swap at the break's darkest point.** That is where the arc already swaps sun for moon. Spread the SetMaterial calls
  over a few ticks (for example 200 a tick). Each call rebuilds a primitive's render state.
- **Afterwards.** The values can then fade with the arc: 129 writes a step. Put the originals back at sunrise, run end
  and teardown (a LEVEL_DROPS entry, like the sky's).
- MIDs are run-time instances, so the stock materials stay untouched (memory: no stock changes in game).

The terrain's coastal water would need the same treatment on its 16 terrain-tile materials (layer 0 there too) [I].

## B. Runway and airport lights

### 5. What Survival's level already holds [D]

`Map17_Env_ComonaAirport` (streamed by PL_SurvivalMode) places these. Positions use the runway frame from COMONA_MAP.md:
t m along, s m to the side, s > 0 = south (`placements_Map17_Env_ComonaAirport.json`).

| Kind | Mesh | Count | Where (t / s m) | Material -> master | Emissive value |
|---|---|---:|---|---|---|
| Runway glow (warm white-orange, tint 1 / 0.30 / 0) | SM_AirportLightsP04_Emissive_I05 | 420 | edges s ±15: 129 along -742..758; centre line: 51; touchdown rows s 3-10: 150; approach t -1186..-742 and 758..1164: 90 | MI_UNI_Map08_StreetLight001P04_I05 (AirForceBase folder) -> MP_Env_EmissiveBillboardBase_AFB -> M_Env_EmissiveBillboardBase | EmissiveIntensity 0.3 |
| Taxiway centre glow (green 0.38 / 1 / 0.30) | SM_AirportLights_P01_Emissive_I05 (+97 P02 meshes using the green material) | 359 | taxiway s 45-70: 289; apron; threshold bars | ...P01_I05 | 0.3 |
| Taxiway edge glow (blue 0 / 0.12 / 1) | SM_AirportLightsP05_Emissive_I05 | 146 | taxiway edges, t -759..1178 | ...P05_I05 | 0.3 |
| Apron glow (amber 1 / 0.76 / 0.16) | SM_AirportLightsP02_Emissive_I05 (+19 P01 meshes) | 102 | apron s 70-160 | ...P02_I05 | 0.15 |
| Red (end bars, obstacles) | SM_AirportLightsP03_Emissive_I05 | 22 | runway ends t ±883; 8 at s 22-45; up to z 38 m | ...P03_I05 | 0.15 |
| Centre-line / taxiway fixtures (flush) | SM_AFB_RunwayCenterlineLight001_I24 | 855 | runway and taxiways | MI_AFB_RunwayCenterlineLights001P001-P005_I24 -> M_Env_Base_Emissive | 01All_EmissiveIntencityScale 300 x 01EmissiveIntencity 1 |
| Edge fixtures | SM_AFB_Runwaylights_I27 | 99 | s ±15, t -742..758 | MI_AFB_RunwaylightsP002_I27 -> M_Env_Base_Emissive | 1 x 0.1 |
| Approach structures | SM_AFB_ApproachLights001_I07 | 18 | beyond both ends | ...P002_I07, ignores the mission condition | 1 x 1 |
| PAPI | SM_AFB_Papi001_I07 | 8 | by each threshold | MI_AFB_Papi001A_I07 | 40 x 1 |
| Distance boards | SM_AFB_RunwayDistanceLight001-009_I07 | 18 | s 22-45 | ignores the mission condition | 5 x 1 |
| Apron light masts | SM_AFB_ApronLighting001/002_I07 | 33 | apron | MI_AFB_ApronLighting001Light001_I24 -> MP_Env_Base_EmissiveMaskMap, ignores the condition | 0.1 |
| Rotating beacons | SM_AFB_AirfieldLighthouse001_I24 | 2 | (15.05, -3.75), (17.01, -4.85) km | MI_AFB_AirfieldLighthouse001P001_I24 | 40 x 1 |
| Obstacle lights (blinking red) | SM_UNI_Map17_AirportLightsP01_Emissive_I05 | 4 | in Mission022_Env_CityLighting001 | MI_VEC_AviationObstacleLights_I18, `200Ctrl_IgnoreMissionEmissiveCondition` 1, animated | 4 x 0.2 |

So the airport already has a complete night pattern: edges, centre line, touchdown zone, approach, red ends, taxiways,
apron, PAPI and beacons. Nothing needs placing for a first try.

**How the glow billboards draw [D: material data; I: the formula].**
- `M_Env_EmissiveBillboardBase` is additive, unlit, and camera-facing (`Is_ShowAsBillboard`).
- The quad is 13 m in the mesh (ExtendedBounds 0 x 650 x 650), placed at scale 0.1: about 1.3 m.
- The parent `_AFB` sets ShowDistance_Start 28,000, ShowDistance_Clamp 1.1, Near_ShowDistance_Start 1,000,
  CameraOffset 100 and OpaIntensity 0.5, with opacity mask `T_AviationObstacleLightsEmiMask01_I05_M`.
- Compare Mission 9's city glows (`MI_UNI_Map08_StreetLight001P0x_I05`, City folder): EmissiveIntensity 0.005,
  ShowDistance_Start 0, ShowDistance_Clamp 6,000. That looks like a billboard grown with distance; the airport's clamp
  of 1.1 hardly grows [I].
- The master reads `MPC_Env_Control`. Its emissive function has `Ctrl_ReciveEmissiveCondition`,
  `Ctrl_ForceEmissiveCondition`, `EmissiveIntensity_Bias` and the switch `200Ctrl_IgnoreMissionEmissiveCondition`.
- The collection's `Ctrl_Scene_EmissiveScale` is set per mission: day 1, Missions 9 and 22 10,000, Survival's night
  100. `Ctrl_Env_MissionEmissiveCondition` is 1, except Mission 4's row, which sets 0.
- So the glow is most likely EmissiveIntensity x TextureTint x mask x OpaIntensity x `Ctrl_Scene_EmissiveScale`,
  gated by the condition [I]. The fixture master `M_Env_Base_Emissive` reads the same collection, but its "x 300"
  values suggest a different scale path [I].

### 6. How Mission 9 lights its city at night [D]

| Sublevel | What it holds |
|---|---|
| Mission009_Common_Env_CityNightPointlight | 277 PointLights: intensity 0.25-10 (median 5, unitless, exponent falloff 2-5), radius 50-300 m, **SpecularScale 0**, no shadows, **InverseExposureBlend 0.5-0.6**, mostly warm sodium (RGB 255, 185, 134) |
| Mission009_Common_Env_CityNightBillboard | 549 glow billboards, the **same airport meshes**: P05 273, P02 141, P04 30, P03 27, P01 16, plus SM_LightsEmi_I05 41 and SM_AviationObstacleLightsEmitest_I05 21; 1 point light, 2 decals |
| ..._CityNightBillboard_Baked | 3 instanced components (SM_LightsEmi_I05 x2 with MI_UNI_Map08_StreetLight001_I05, obstacle lights) |
| ..._CityNightLocalfog | 6 LocalFogVolumes, warm `FogEmissive` (1, 0.67, 0.42): the city's glow haze |
| ..._CityNightDecal | 4 large emissive decals (MI_Decal_Emissive01_I05): glow painted on the ground |
| ..._CityNightEtc | empty |
| Cloudly | `GroundEmissiveTexture` T_Cloudly_GroundEmissive_MS09: the city lighting the clouds from below |

Its glows are bright because of CtrlSceneEmissiveScale 10,000 at an exposure of EV 0.5-9. A glow of 0.3 x 10,000 x 0.5
= 1,500 against an exposure scale of about 0.8 sits about a thousand times over white, so even a sub-pixel billboard
blooms into a visible light [I].

Comona's own night lights are already in Survival's level (`Mission022_Env_CityLighting001`) [D]:
- 498 PointLights: intensity 0.4-10 unitless, radius 4-200 m, SpecularScale 0, no shadows, **InverseExposureBlend 1**
  (their brightness on screen ignores exposure), mostly cool white (RGB 211, 216, 255).
- 40 SpotLights: 36 apron floodlights at 50,000 cd (`IntensityUnits` Candelas), 27 m up, 60 deg cones; 4 at the shuttle
  pad in EV units.
- 236 city glow billboards (`SM_Map17_LightsEmissive01-03_I05`, MI_UNI_Map17_Light001_I05, EmissiveIntensity 0.05) and
  8 bridge billboards.

Two things hide them at Survival's night:
- The floodlights are physical. About 69 lux on the apron gives about 3 cd/m², invisible at EV 10.5 [I].
- Small point lights are culled by `r.MinScreenRadiusForLights`. Mission 22 sets it to 0.006 and Mission 9 to 0.008.
  Survival's InGameBase cvars don't set it, so it stays at the engine default (0.03) or whatever the last mission left.
  At 0.03 a 32 m light drops out beyond about 1 km [I].

### 7. Making runway lights visible at Survival's night

Brightness on screen of the airport glow, at full pixel coverage (glow 0.3 x scale x 0.5, times the exposure scale) [I]:

| Exposure | Ctrl_Scene_EmissiveScale 100 (now) | 1,000 | 10,000 (stock night) | 100,000 |
|---|---:|---:|---:|---:|
| EV 10.5, bias -1.5 (Survival now, scale 2.0e-4) | 0.003 (invisible) | 0.03 | 0.3 | 3 |
| EV 4, bias -2 (Mission 22 dawn floor, ~0.013) | 0.2 | 2 | 20 | 200 |
| EV 0.5, bias +0.5 (Mission 9, ~0.83) | 12 | 125 | 1,250 | - |

A 1.3 m billboard is about 0.3 px wide at 5 km (1080p, about 50 deg vertical field of view). A light seen from a
distance needs roughly 10-30 x the value above to read as a dot; stock nights get that from their huge overshoot and
the bloom [I].

**(a) The stock route.** Use the sky agent's night with an exposure near Mission 9's or Mission 22's, and
`Ctrl_Scene_EmissiveScale` at the stock 10,000, or even 1,000 at Mission 9's exposure. The airport's 1,049 glows, the
855 centre-line fixtures, the PAPIs and the beacons then light as in Mission 22. Also set `r.MinScreenRadiusForLights
0.006` at night (`KismetSystemLibrary.ExecuteConsoleCommand`, as sv_main.lua's "open"), and put the old value back by
day. That brings back Comona's 498 exposure-proof point-light pools from altitude. Cost: none to build. Risk: the city's
windows and signs share the scale (section 8).

**(b) The airport's own brightness, at any exposure.** MIDs for the airport's light materials only. That is the five
AFB billboard instances (P01-P05), the five centre-line variants (P001-P005), and the edge, approach, PAPI and beacon
instances: about 14 MIDs, set on the about 2,000 components in `Map17_Env_ComonaAirport` whose mesh is a light (5).
Then:
- `EmissiveIntensity` x N, a global parameter on these masters, so plain `SetScalarParameterValue` works. N is about
  300 at today's 100 / EV 10.5 for the 0.3 level, and x10-30 more for distance.
- `ShowDistance_Clamp` 1.1 -> a few hundred, so the billboards grow with distance as Mission 9's city glows do (6,000).
- One scalar write a MID fades them in with the sunset and out at sunrise.

This leaves the city at its own scale. [I/T]: which parameter controls the growth (test L3).

**(c) Survival's own glow sprites at run time.** If (b) can't keep them visible from afar: about 120 screen-space dots.
- An actor spawned with MaterialBillboardComponents, one per light, as `SPC.V.billboard` does for VALKA's lens flash
  (sv_anomalies.lua).
- Each has one sprite element with `bSizeIsInScreenSpace` true and a size of about 0.003-0.006 of the screen.
- The material is an instance of AC8's Mission 23 flare: `/Game/VFX/Mission/Mission023/MI_ms23FarExp_Flare` on
  `M_ms09FarExp_Flare`, additive and drawable on a billboard (AIRCRAFT_MATERIALS.md 5). It reads `MPC_VFX_Control`, so
  it likely follows `VFXEmissiveEV`, which tracks the exposure [I]. Its parameters are EmissiveColor, Emissive_Intensity
  and Emissive_Power.
- Colours as the stock billboards: warm white edges and centre line, green thresholds, red ends, blue taxiway edges.
- Positions come from the runway formula. For example: edges every 60 m both sides (t -742..758, s ±15): 52. Centre
  line every 60 m: 26. Approach bars t -1186..-800 and 800..1164 every 60 m: 14. Threshold greens and end reds, 6 each
  at both ends: 24. That is about 116 components.
- New MIs of the flare would be built by tools/build_survival.py, as MI_SV_ValkaFlare_* are. Or a MID of the stock MI
  at run time, with no build change.

For pools of light on the runway when landing, add 20-40 PointLights with `InverseExposureBlend` 1 (Comona's own way),
intensity about 3-5 unitless, radius 40-60 m, SpecularScale 0, every 100 m along both edges. Spawn them at run time
(`AddComponentByClass` PointLightComponent, hard rule 46's way) or place them in a Survival-built sublevel. With
`r.MinScreenRadiusForLights` 0.006 [I/T].

Optional and atmospheric, Mission 9's way: one LocalFogVolume over the airport with a warm `FogEmissive` for a lit
haze. Spawn it at run time (a `LocalFogVolume` actor); `r.LocalFogVolume.ApplyOnTranslucent` is on in this game [I/T].

### 8. Risks
- `Ctrl_Scene_EmissiveScale` is one value for every `M_Env_*` emissive on the map. That is the airport and city
  glows, and also about 8,900 building placements with a town-glow wall emissive and about 5,700 with lit windows
  (section 9). Raising it for the runway raises them all. In 0.74.10 the value 10,000 came together with exposure min
  0.5 and day cubemaps. The white-out was that exposure applied to day light, plus every wall and window at 10,000 [I].
- The day cubemaps and a low exposure must never meet. Switch the cubemaps (or the sky light's intensity) **before**
  the exposure starts to drop, and back **after** it has risen.
- MIDs replace level-assigned overrides (`_I26` for the sea, the P002-P005 centre-line variants, the P01 / P02 swaps on
  116 billboards), not the meshes' own materials. Restore each component's own original.
- 1,559 sea components plus about 2,000 airport components each rebuild their render state on SetMaterial. Spread the
  calls over ticks at the break's darkest point. FindAllOf("StaticMeshComponent") over about 10,000 components is a
  one-off cost of the order of a second from Lua [I]: cache it with the sky's view.
- The STORE minigame may switch the graphics row (FISHING.md 5). Survival already re-applies the MPCs every tick. MIDs
  and cvars aren't touched by the row [I].
- Co-op: all of this is per game and cosmetic, like the arc. Each game applies it to its own level.

### 9. Emissive materials on Comona's placed meshes

`emscan.py` walked the materials of the 435 distinct meshes placed in Map17_Env_ComonaAirport, _CityMap001,
_CityTraffic001, _CityHda001_Baked and Mission022_Env_CityLighting001. Every master below imports `MPC_Env_Control`
[D]. Placements are counted per placed mesh that carries the master:

| Master | Placements (airport / city / traffic / houses / lighting) | Emissive values (instances) |
|---|---|---|
| M_Env_Building_Base | 72 / 2,738 / 631 / 5,438 / - (about 8,900: every house, warehouse, hangar, pole) | GroundEmissiveIntensity **7** with the world colour texture `T_Emissivewc01_I05_Ev4_D`: the town's light painted onto walls |
| M_Env_Building_Window | 62 / 1,348 / - / 4,326 / - (about 5,700) | All_Emissive_Inteinsity 1-2; **All_Emissive_Intensity_MissionEmissiveCondition 300**, light noise brightness 113: lit rooms when the mission condition is on |
| M_Env_SimpleEmissive | - / 237 / 602 / - / - (street-lamp heads) | EmissivePower 0.015 |
| M_Env_RoadBase | 2 / - / 9 / - / - | EmissiveWorldColor_Intensity 2 (road glow) |
| M_Env_EmissiveBillboardBase | 1,049 / - / - / - / 849 | 0.05-0.3 (airport and city glows; 4.0 x 0.2 obstacle lights) |
| M_Env_Base_Emissive | 1,038 / 1 / 16 / - / - | 0.1-300 (section 5) |

So `Ctrl_Scene_EmissiveScale` reaches about 14,600 building and window placements across the town, not just the
lights. Any value that lights the runway at a high exposure lights the whole town's walls and windows by the same
factor. That is the reason to give the airport its own MIDs (7b) or sprites (7c) rather than raising the scale [I].
The "Ev4" in the town's glow texture name, and Mission 22's exposure floor of EV 4, suggest Comona's night emissives were
tuned for an exposure near EV 4 with the scale at 10,000 [I].

### 10. Tests [T] (TEST ONLY keys; each logs the before and after values)
- **S1:** read back one sea component's `GetMaterial(0)`. Expect MI_TER_Map17_<tile>_Sea_I26.
- **S2:** at night, `MainSkyLight.bAffectReflection` = false, then SetVisibility false / true over two ticks. Does the
  sea darken, and do the planes lose their sheen?
- **S3:** one MID on the loop sea (1,431 components): layer-0 `Specular` 0, then 0.05, then back. Log
  GetScalarParameterValueByInfo.
- **S4:** `MPC_VFX_Control` `VFXCloudlySkyAmbientLight` 0 and `VFXEmissiveEV` -10 at night. Expect the sea unchanged.
- **S5:** swap the controller's five textures to Mission 9's, with RegisterCubemapForPreCalculatation, and read
  MainSkyLight.Cubemap / BlendDestinationCubemap back. Belongs with NIGHT_SKY.md's exposure test.
- **L1:** at today's exposure, `Ctrl_Scene_EmissiveScale` 100 -> 1,000 -> 10,000 -> 100,000, 20 s each. Take
  screenshots over the airport from 2.5 km, 5 km out, and on final approach, plus one over the town. Which value shows
  the runway, and what blows out?
- **L2:** the same at the sky agent's night exposure.
- **L3:** one MID per AFB billboard material: EmissiveIntensity x10 / x100 / x1,000; ShowDistance_Clamp 1.1 -> 100 ->
  1,000; ShowDistance_Start 28,000 -> 0.
- **L4:** `r.MinScreenRadiusForLights 0.006` at night (read the old value first with
  `KismetSystemLibrary.GetConsoleVariableFloatValue`).
- **L5:** one MaterialBillboardComponent dot on the runway centre (MI_ms23FarExp_Flare MID, screen size 0.004). Is it
  visible from 10 km?

### 11. Side findings for the night (outside this note's scope; for the main session)
- **Aircraft lights.** InGameBase sets `MECLandingLight / MECFormation / MECNavigation / MECAntiCollision_Emissive_Intensity`
  to 0 with overrides on, so planes carry no navigation lights in Survival. Mission 9's row doesn't override them, so
  its planes keep the collection's default of 1 (`MPC_MEC_EmissiveControl` Navigation_ / AntiCollision_ /
  FormationEmissive_Intensity) [D/I]. Writing 1 at night would mark the planes the user "can barely see". [T]
- **Cockpit at night.** Mission 9 / 22 cut `Cockpit_MFD_EmissiveIntensity` to 0.0001 / 0.001 and
  `Cockpit_Meter_EmissiveIntensity` to 0.002 / 0.05. At a low exposure the cockpit screens would otherwise glare [D].
- **Stars.** Mission 4's Cloudly actor has no `StarCatalog` or `MoonTexture` in its `CloudlyResources`. Missions 9 and
  22 have them (`ASCIIYaleBrightStarCatalog5`, `NasaCGIMoonKitLow`) [D]. This is likely why no stars show; it belongs to
  NIGHT_SKY.md.
