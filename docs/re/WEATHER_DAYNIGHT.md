# Weather, sky and day/night (research, 2026-10-23)

Game build: AceCombat8.exe of 2026-09-29. Everything below was read from the local paks (`tools/get_stock.sh` into
`build/stock/`), the usmap (`tools/usmap.pkl`, via `tools/scripts/uprop.py`), `build/scan/store.txt` (reverse-import
graph) and the exe's strings / reflection data (`build/research/kills/strings.txt`, `tools/re/refl.py`).
Tags: **[V]** verified in the files or the exe, **[I]** inferred (fits the data, not proven), **[T]** needs an in-game test.

Not covered here: `Engine/Plugins/Cloudly` internals (renderer), and Online-Mode weather beyond noting that it exists.

## 0. Summary

- Sky, sun, moon, stars, atmosphere, volumetric clouds and the sky's fog all come from one native actor,
  **`LiveCloudlyActor`** (< `ACloudlyActor`, the "Cloudly" plugin, `/Script/Cloudly`). It lives in each mission's
  lighting sublevel `Maps/MapCommon/MapNN/MissionNNN/MissionNNN_Common_Lit_Cloudly01` and reads two data assets:
  a `CloudlySkyParams` (`CSP_*`: sun/moon angles, sun intensity, atmosphere, stars, cloud shading) and a
  `CloudlyVolumeComponents` (`CVC_*`: the cloud layout). **[V]**
- **Time of day is not a setting, it's which CSP and lighting sublevel the level loads.** Each lighting sublevel
  also has baked sky-light cubemaps (`BP_SkyLightController` + 5 `TC_MissionNNN_SkylightCube_*` HDRIs) and
  post-process volumes with fixed auto-exposure (day missions lock exposure at EV 13-14, the night mission uses
  0.5-9). **[V]**
- **The game does change the sky at run time in two stock ways:**
  1. Mission 25_2 streams two lighting sublevels and swaps them between phases with
     `LiveSetVisibleSubLevelExecution` (sun drops from 8 to 4 degrees). **[V]**
  2. `CloudlySequencer_ms25_TimeLaps` is a Cloudly "sequencer" asset: three key frames (t = 0, 5, 10) that blend three
     CSPs (sun 12.5 -> 23.5 -> 34.5 degrees). The Cloudly actor has `EnableCloudlySequencer` /
     `CloudlySequencerAsset` / `CloudlySequencerTime` and a `SetSequencerTime(ContextObject, Time)` UFUNCTION. **[V]**
  So the BUILD_PLAN note "time of day can't change at runtime" is wrong, or at least unproven.
- Thunderstorms that strike aircraft are **`LiveLightningVolume`** actors (`BP_LightningVolumeBase` /
  `BP_LightninigVolume_MS12`). They're spawned from world-data `LightningDescList` spheres (Missions 12 and 16) using the
  class in the PL's `WorldSettings.MissionSettings.LightningVolumeClass`. **[V]** No event node turns them on or off. **[V]**
- Rain and snow are `LiveWorldSettings` flags (`bIsWorldRain`, `bIsRainVolume`, `bIsSnow`, `RainVFXBrightness`) plus
  `BP_BoxWeatherVolume` actors (`ALiveBoxWeatherVolume`: extra cloud density, rain cancel) in VFX sublevels. Mission 30
  switches rain at run time by showing or hiding such a VFX sublevel. **[V]**
- Comona (Map17) has **no `_BuiltData` package**, so it has no baked lightmaps and all its lighting is dynamic. Moving
  the sun lights everything. **[I]** (the only BuiltData packages are Map05/Map12/Map18/Map20 airbases/cities)
- Comona already has two lighting sublevels made for it: **Mission019 (sun 26 deg, with moon)** and **Mission022 (dawn, sun
  -3.7 deg)**. Its city/airport lights (`Mission022_Env_CityLighting001`: 498 point lights, 40 spot lights, emissive light
  meshes) are already in PL_SurvivalMode. **[V]**

## 1. How the weather and sky work

### 1.1 The lighting sublevel (one per mission)

Every campaign mission streams one `*_Common_Lit_Cloudly01` sublevel (68 packages import `BP_SkyLightController`;
they are all lighting sublevels). Mission004's sublevel, which Survival uses now (`build_survival.py` LIT_NEW), holds **[V]**:

| export | class | role |
|---|---|---|
| `LiveCloudlyActor_0` | LiveCloudlyActor | sky + clouds. Props set: `CloudlySkyParamsAsset` = `/Game/Cloudly/CloudlySkyParams/Ingame/Mission004/CSP_ms04_20251218b`, `CloudlyVolumeComponentsAsset` = `CVC_ms04_20251216`, `SunLight` -> its `Directional Light Component`, `HeightFog` -> `Post HeightFog Component`, `SkyLight` -> `Sky Light Component`, `bUseSkyLight` 0, `bUseHeightFog` 0, `TargetSunLightLastSet` = the sun, `CloudlyResources` {BlueNoise, Transmittance RT, AerialPerspective LUT} |
| `Directional Light Component` | DirectionalLightComponent | the sun. intensity 120000, rotation (pitch -15, yaw -128), LightSourceAngle 1.28 |
| `Post HeightFog Component` | ExponentialHeightFogComponent | `bVisible` = 0 (Cloudly's aerial perspective is used instead) |
| `BP_SkyLightController_C_1` + `MainSkyLight` (SkyLightComponent) | BP | blends 5 baked cubemaps by camera height (`TextureBelowClouds / InLowerClouds / InTheClouds / InUpperClouds / AboveClouds`, `TransitionBottomToTopClouds`, `TransitionTopCloudsToSky`), via `SetCubemapBlend` |
| `BP_SkyLightBlendVolume_BOX_C_1` | BP | sky-light blend volume |
| `PostProcessVolume_0/1/3`, `BP_PostProcessMisssionBase_C_0` (+ `CockpitViewPostProcess`) | PostProcessVolume / BP | colour, white balance, **auto exposure** (see 1.3), mission lens flare `MI_PP_CustomLensFlare_Mission004` |

Other missions have the same layout (Mission009 adds an `ExponentialHeightFog` actor and Cloudly star/moon resources;
Mission025_2_1/2_2 add the sequencer).

**The sun direction comes from the CSP.** In every level checked, the DirectionalLight rotation is exactly
(pitch = -SunElevation, yaw = SunAzimuth - 270), and the night level's light intensity equals the CSP's SunIntensity.
The Cloudly actor also has `TargetSunLightLastSet`. So Cloudly drives the light from the sky params. **[V numbers, I mechanism]**

| lighting sublevel (map) | CSP | sun elev / az (deg) | SunIntensity | moon / stars | PL clock |
|---|---|---|---|---|---|
| Mission004 (Map05) **= Survival now** | CSP_ms04_20251218b | 15.0 / 142.0 | 120000 | - | 10:10 |
| Mission016 (Map14) | CSP_ms16_251209 | 6.4 / 158.6 | 120000 | - | 08:00 |
| Mission019 (**Map17 Comona**) | CSP_ms19_260124 | 26.2 / -93.0 | 120000 | moon 70 deg, phase 0.245 | 15:00 |
| Mission022 (**Map17 Comona**) | CSP_ms22_251208 | **-3.7** / 121.0 | 120000 | star catalog in resources | 05:30 |
| Mission009 (Map08) night | CSP_Mission009_kanno260116 | 24.0 / -122.3 | **0.234**, RGB (0.89, 0.97, 1.0) | EnableMoon 1, moon 24 deg, phase 0.14; `StarCatalog`, `MoonTexture`, `GroundEmissiveTexture` (T_Cloudly_GroundEmissive_MS09) | 23:00 |
| Mission012 (Map11) storm | CSP_ms12_260216 | 29.4 / 101.2 | - | - | 13:00 |
| Mission013 (Map12) rain | CSP_ms13_20251214 | 21.4 / -106.5 | 120000 | - | 15:20 |
| Mission025_2_1 / 2_2 (Map20) | CSP_ms25_2A / 2B | 8.0 -> 4.0 / -118.5 | 120000 | - | - |
| TimeLaps Seq1/2/3 | CSP_Mission025_Seq1..3 | 12.5 / 23.5 / 34.5 | 120000 | - | - |

So **night is faked**: Mission 9 keeps a "sun" at 24 degrees with intensity 0.234 tinted blue (moonlight), and adds the
moon, stars and a ground-emissive map (city glow on the clouds). It also has night exposure and night cubemaps
(`TC_Mission009_SkylightCube_*`), and night city lights in sublevels (`Mission009_Common_Env_CityNight*`). Dawn and dusk are
real: a sun just below the horizon (Mission 22). **[V]**

`SkyParams` (the CSP's `Data`, 200 fields) also holds: `bUseUnrealSunData`, `RealSunDate/Time/LatitudeLongitude`,
`SunMinElevationForLightSource`, `MoonElevation/Azimuth/Phase/FractionOfSunIntensity`, `StarsParams`, cloud layer heights,
`RainCloudAnim`, `AirCraftFogScale`, aerial perspective, multiple scattering. **[V]** (read with uprop. `Vector3f` needs
`NATIVE_SIZE['Vector3f'] = 12`, which uprop.py lacks)

### 1.2 World settings (PL `ChronicleWorldSettings`, struct `LiveWorldSettings`)

Weather-related fields **[V]**: `CloudDensityScale`, `CloudDensityScaleBySound`, `CloudLightSettings.CloudLightClass`
(e.g. `BP_CloudLight_Ms022_ShuttleLaunch`, a timeline that lights the clouds for an event; Survival drops it),
`ClockHour/ClockMin/ClockSec`, `bResetRealTime`, `bIsWorldRain`, `bIsRainVolume`, `bIsSnow`, `RainVFXBrightness`,
`MissionSettings.LightningVolumeClass`, `MiscDataSettings` (DataTables/DataAssets).

| PL | values |
|---|---|
| M004 | ClockHour 10:10, CloudDensityScaleBySound 1.308, bIsRainVolume 1, **bIsSnow 1** (Survival copies the clock and density but not the rain/snow flags) |
| M006 | 10:30, density 0.9, bIsRainVolume 1, bIsSnow 1 |
| M009 | 23:00, CloudLight BP_CloudLight_Ms009_FarExplosion |
| M012 | 13:00, **LightningVolumeClass = BP_LightninigVolume_MS12**, CloudLight Ms012_PodargeDead, bResetRealTime 1 |
| M013 | 15:20, density 0.9, **bIsWorldRain 1, RainVFXBrightness 10** |
| M015 | 05:30, CloudDensityScale 10 |
| M016 | 08:00, density 0.9, **LightningVolumeClass = BP_LightninigVolume_MS12** |
| M017/025/030 | bIsRainVolume 1 |
| M022 | 05:30, CloudLight ShuttleLaunch |
| M029 | 16:00, density 2.5, bIsRainVolume 1, bIsSnow 1 |

`ClockHour` doesn't drive the lighting (M009's sun is up at "23:00"), so it is probably the HUD/cockpit clock. **[I]**

### 1.3 Exposure and graphics profile (needed for any time-of-day change)

Post-process volumes in the lighting sublevel **[V]**:

| level | volume | exposure |
|---|---|---|
| M004 | PostProcessVolume_1 (prio 5, unbound) | AutoExposureMin/MaxBrightness **13 / 14**, bias 0, speed up 5 / down 2 |
| M004 | PostProcessVolume_3 (prio 30000) | min/max 13 / 14 |
| M022 | PostProcessVolume_0 / _1 | bias -3.32 / -2.0, min/max 4 / 14 |
| M009 | PostProcessVolume_3 (prio 5) | min/max **0.5 / 9**, bias 0.5; others bias 2.0 / 0.5 / -1.0, WhiteTemp 6500-8800 |

So if the sun goes down under Mission 4's volumes, exposure stays pinned at EV 13-14 and the picture goes black. Any
day/night change must also change these volumes, or swap them in with another lighting sublevel.

Per-level graphics profile **[V]**: `/Game/Datatables/Graphics/DA_PLGraphicsSettings_CP` (`LivePLGraphicsSettingsDataAsset`)
maps each persistent level's soft path (`PLDataMap`) to a `DT_Graphics_MissionNNN` table (`LivePLGraphicsSettingsDataTable`:
`MissionTime` EPLGraphicsMissionTime {Dawn, Morning, Afternoon, Night, Midnight}, `MissionWeather` EPLGraphicsMissionWeather
{Sunny, Cloudy, Rain, Raining, Snow, Snowfall}, aircraft/cockpit/landing-light emissives, VFX brightness, wind, MPC params,
`VFXSunLightVector`, ...). Mission 9's default row is MissionTime 3 (Night), VFXEmissiveEV -2, CtrlSceneEmissiveScale 10000.
The day missions leave MissionTime at 0. **`/Game/Mods/SurvivalMode/Maps/PL_SurvivalMode` is not in the map**, so Survival
gets `InGameBaseData` (`DT_Graphics_CP_InGameBase`), not Mission 22's or Mission 4's profile. **[I, T]** That matters for a
night look (cockpit and navigation-light emissives) more than for weather.
Runtime classes: `ULivePLGraphicsController` (ApplySettings), `ULiveGraphicsSettingsSubsystem`, cvar
`Live.Graphics.EnablePLGraphicsControl`, replay `PLGraphicsIndex`. No UFUNCTIONs were found on them (`refl.py class`).

### 1.4 Clouds as gameplay

- Lock-on: every weapon has `LockonReductionInCloud`. `LockonRangeReductionInCloud` is in the weapon settings table. **[V]**
- AI: `LiveAIPilotWeatherData` {CloudSearchRadiusInMeter, CloudSearchAngleInDegree, ApprochCloudChanceHightHP,
  ApproachCloudChanceLowHP, LostTargetInCloudTime, CloudReactionTimeForEvade, LostTargetInCloudRecabvaryTime}. **[V]**
- Event statement `LiveIsInCloudStatement` (M012, condition on Player). Trigger
  `LiveStatusOfChangedByWeatherTrigger` (EventType 0x49 = 73), args {Player: AnyPlayer/LocalPlayer, Status:
  ELiveStatusOfWather {EnterCloud, LockOffByCloud, BeginIcing, Icing, Lighting, AirStream}}. M012 uses EnterCloud and
  Lighting (radio `ms12_01_IntoCloud_1`, `ms12_01_Hit_Thunder_1/2`). **[V]**
- Cloudly "blast effect" (a hole punched in the clouds): `KickBlastEffectOpen(CenterInMeters, Immediate, GroupId)`,
  `KickBlastEffect`, `KickBlastEffectClose(All)`; event node `LiveKickBlastEffectOpenExecution` (M027, args MarkActor,
  bool, ELiveBlastEffectIndex). Could be used for the Anomaly portal. **[V]**
- `IsInsideRainCloudRange(WorldPositionInCm) -> int` (Cloudly). **[V]**

### 1.5 Rain, snow, fog

- Global rain: `bIsWorldRain` + `RainVFXBrightness` (M013). Rain inside volumes: `bIsRainVolume` + weather volumes.
  Snow: `bIsSnow`. **[V]**
- Weather volumes: `ALiveBoxWeatherVolume` {AdditionalCloudDensityRatio, bCancelRain, Extents} and
  `ALiveCylinderWeatherVolume` {AdditionalCloudDensityRatio, bCancelRain, Radius, HalfHeight, bEternalHeight}. Both are
  LiveVolumes (bTestPlayer, bTestEnemy, ...). BP: `/Game/Blueprints/VFX/RainVolume/BP_BoxWeatherVolume` (no imports).
  Placed in VFX sublevels: Mission004/011/006/015/017/029 `*_Common_VFX`, Mission025 `_Common_VFX`,
  `Mission030_AfterIGC300010_VFX` (about 140 boxes, ratio 1.0), Online `SL_PvPvE_004_Lit_Cloudly`. Mission004_Common_VFX has 5
  (ratio 0.2, up to 100 x 20 km) and also `NS_ms04CarrierSnow`. **[V]**
- Run-time switch precedent: M030 `RemoteEvent_SetRainVolume_AfterIGC` ->
  `LiveSetVisibleSubLevelExecution {SubLevel "Mission030_AfterIGC300010_VFX", bVisible}` (shown, then hidden 18 s later
  while `_02_VFX` is shown). **[V]**
- Aircraft surface: plane BP material params `Rain_Intensity`, `Rain_Density`, `Rain_Brightness`, `Droplets_Intensity`,
  `Ice_Blend`, `Ice_Intensity`. HUD/voice ICING alerts (`EHUDMessageType::ICING`). **[V names, I which flag drives them]**
- Fog: Cloudly's own `Post HeightFog Component` (hidden in M004), optional ExponentialHeightFog actors (M009),
  `Mission009_Common_Env_CityNightLocalfog` sublevel, `CopyCloudlyExponentialHeightFogSettingsToWorldExponentialHeightFog()`.
  Engine setters exist: `SetFogDensity`, `SetFogHeightFalloff`, `SetFogInscatteringColor`, `SetStartDistance`,
  `SetVolumetricFog`. **[V names]**
- Rain VFX for cinematics only: `NS_IGCVFX_Ms11/17/25*_Rain*`, `Hangar004_Vfx_Rain`. **[V]**

### 1.6 Thunderstorms and lightning that strikes aircraft

- Class `ALiveLightningVolume` (fields, **[V]**): `MaxStrikeInterval`, `MinStrikeInterval`, `WeightCurveName`,
  `LightinigEffect`, `LivelyLightinigEffect`, `LightinigPredictiveVoltageEffect`, `LightningPointLight`,
  `PointLightIntensityCurve`, `MinimumDistance`, `PointLightIntensityMultiplier`, `Radius`, plus the LiveVolume fields
  (bEnableCollision, bTestPlayer, bTestEnemy, bTestFutureLocation, InsideGameObjects, ...). `ULiveLightningObserver` exists.
- `BP_LightningVolumeBase` CDO: effects = `NS_ElectricDischargeM001` / `NS_ElectricEvasion001` / `NS_ElectricSign001`,
  PointLightIntensityCurve = `CR_LightningCurve`, PointLightIntensityMultiplier 700000.
  `BP_LightninigVolume_MS12` (sic) < Base: WeightCurveName = `MS_12`. The strike intervals stay at the C++ defaults.
  Weight curve table: `LightningWeightCurveTable` on the game instance (`CUR_LightningWeight` exists and no package imports
  it, so it's probably referenced from config). **[V / I]**
- Placement **[V]**: world-data `LightningDescList` (`LiveLightningVolumeDesc`: SphereVolumeClass = `/Script/...LiveSphereVolume`,
  RadiusInMeter, bEnableCollisionPlayer, bEnableCollisionNPC, bTestFutureLocation, bAINoEntryArea, SpawnPoint, Tags,
  AttachParentAIObjectName, UniqueID, Name, WorldDataName). The PL's `MissionSettings.LightningVolumeClass` names the
  actor class.
  - WD_Mission012_global: 17 spheres `DefaultLightning0..16`, radius 2-5.8 km, Z 5.7-8.5 km, player collision on.
  - WD_Mission016_global: 1 sphere `Lightning_Cloud0`, radius 5.5 km at (-379570, 1851063, 187140).
  - No other stock world data has lightning (198 WDs checked). `AirCurrentVolumeDescList` is empty in all of them.
- Visual storm (no gameplay): `NS_CloudLightning` NiagaraActor in `Mission012_Phase01_VFX` / `Mission016_VFX` sublevels. **[V]**
- Effect on the player **[V names, I/T behaviour]**: `BeginHUDDistortionLightning`, `EndHUDDistortionLightning`,
  `GetDefaultLightningStrikeDistortionInfo`, `TimeToRecoverFromLightningStrike`, `ELiveCameraShakeType::Lightning`
  (`BP_CamShake_Lightning`), `ELiveVibrationType::Lightning`, sound `AKE_GEN_PLAYER_EXP_Damaged_StruckByThunder_Play`,
  the weather trigger's `Lighting` status. Whether a strike also takes health is unknown (test T8).

### 1.7 Turbulence, wind, air currents

- Player turbulence: `BP_PlayerPlane_Base.TurbulencePlugClass` = `/Game/Blueprints/Vehicle/PLAYER/Misc/BP_Turbulence`
  (`ULiveTurbulencePlug`). Camera shakes `BP_CamShake_Turbulence(_Cockpit)`, `ELiveCameraShakeType::Turbulence`. What
  triggers it (clouds? speed?) is native. **[V names, I trigger]**
- Air currents: `ALiveAirCurrentVolume` via world-data `AirCurrentVolumeDescList` (`LiveAirCurrentVolumeDesc`: Location,
  Rotation, AirCurrentVolumeClass, Strength, TurbulenceRange, OppDirProbability, TurbulenceStableDurationMin/Max,
  TurbulenceMaxEffectDelay, TurbulenceFadeDelay, TurbulenceRotationRate, TurbulenceMaxRotationAngle,
  TurbulenceRotationDelay, Radius, MinAltitude, MaxAltitude, bAllowTurbulenceInOppDir). Reactions are
  `ALivePlayerPlane::OnAirCurrent*` and `ALiveAIPlane::OnAirCurrent*`. Status `AirStream`. No campaign WD uses it. **[V]**
- Wind is only visual (`LivePLGraphicsWindParameterBase` {WindMainPower, WindMainDirection, WindMainFrequency} in the
  graphics tables). **[V]**

### 1.8 Event nodes (stock)

There is no "set weather" or "set time" node. `node_catalog.tsv` (349 classes) and the name maps of all 198 stock EPs
were searched. **[V]** The nodes that matter:

| node | args (record ArgsInfo) | stock use |
|---|---|---|
| `LiveSetVisibleSubLevelExecution` | Str SubLevelName, Bool visible | M025_2 **lighting swap** (`Mission025_2_1/2_2_Common_Lit_Cloudly01`), M030 rain volumes, M006/M020/M029 terrain states, M025/M029 `_Lvd_SmokeCloud` |
| `LiveStatusOfChangedByWeatherTrigger` (type 73) | Player, ELiveStatusOfWather | M012 |
| `LiveIsInCloudStatement` | (Player) | M012 |
| `LiveKickBlastEffectOpenExecution` | MarkActor, bool, ELiveBlastEffectIndex | M027 |
| `LiveCallLevelBPFuncExecution` | Str function | M027 `MGFInnerLight_ON/OFF` |
| `LiveSetActiveVFXExecution` | VFXActor / tag, bool | many (VFX actors from WD VFXActorDescList) |

### 1.9 UFUNCTIONs callable from UE4SS Lua

Cloudly (`ACloudlyActor`, so callable on the `LiveCloudlyActor` instance; params read with refl.py) **[V names/params, T calls]**:

| function | params |
|---|---|
| `SetCustomSunPosition` | Object ContextObject, float ElevationInDegrees, float AzimuthInDegrees, bool ForceUseCustomSun |
| `SetUseCustomSun` / `GetUseCustomSun` | ContextObject, bool UseCustomSun / -> bool |
| `SetCustomMoonPosition` | ContextObject, float Elevation, float Azimuth, bool ForceUseCustomMoon |
| `SetCustomMoonPhase` | ContextObject, float Phase, float PhaseAngle, bool ForceUseCustomSun |
| `SetUseCustomMoon` / `GetUseCustomMoon` | ContextObject, bool |
| `SetSequencerTime` | ContextObject, float Time |
| `SetAnimationTimeOffset` | double Value |
| `RecaptureSkyLight` | Object CurrentSkyLight, Object World |
| `GetCurrentSkyLight` | World -> SkyLightComponent |
| `GetCachedCloudlyActor` | ContextObject, bool bSilent -> actor. `FindCloudlyActor(World)`, `CloudlyExists(ctx)`, `IsCloudlyLoaded(bWait)` |
| `ForceUpdate(Options)` / `ForceUpdateShadows(int FrameCount)` / `ForceUpdateAO()` / `ClearReprojectionHistory()` | after a big change |
| `SetResources()` / `SetResourcesIncludingStars()` | reload resources (stars/moon textures) |
| `GetSkyParamsFloatValue(ECloudlySkyParamsName)` | only BaseLayerStartHeightInCm, BaseLayerRainCloudStartHeightInCm |
| `IsInsideRainCloudRange(Vector WorldPositionInCm) -> int`, `KickBlastEffect*` | see 1.4 |

Writable UPROPERTYs on the actor **[V]**: `CloudlySkyParamsAsset`, `CloudlyVolumeComponentsAsset`, `EnableCloudlySequencer`,
`CloudlySequencerAsset`, `CloudlySequencerTime`, `CloudlyInterpolatedSkyParamsAsset`, `GameWorldTime`, `bUseSunLight`,
`SunLight`, `bUseSkyLight`, `bUseCloudlyEnvMap`, `SkyLight`, `bUseHeightFog`, `HeightFog`, `CloudlyResources`.
Internally there is also `CloudlySkyParamsAssetPrev` / `SkyParamsForDiff`, so changing the asset is probably detected. **[I]**

Engine (names present in the exe, standard UE5 BlueprintCallable) **[V names]**: Light `SetIntensity`,
`SetLightColor(LinearColor, bool bSRGB)`, `SetTemperature`, `SetLightSourceAngle`, `SetAtmosphereSunLight`,
`SetCastShadows`, `SetDynamicShadowCascades`, `SetVolumetricScatteringIntensity`, `SetIndirectLightingIntensity`; SceneComponent
`K2_SetWorldRotation`/`K2_SetRelativeRotation`; SkyLight `SetCubemap`, `SetCubemapBlend(Source, Destination, Fraction)`,
`RecaptureSky`; fog setters (1.5); sky atmosphere `SetRayleighScatteringScale`, `SetMieScatteringScale`,
`SetSkyLuminanceFactor`; LevelStreaming `SetShouldBeVisible`, `SetShouldBeLoaded`; GameplayStatics `GetStreamingLevel`,
`LoadStreamLevel`, `UnloadStreamLevel`, `BeginDeferredActorSpawnFromClass`, `FinishSpawningActor`; SunPosition plugin
`USunPositionFunctionLibrary::GetSunPosition` (lat/long/date -> elevation/azimuth).
The `LiveWorldSettings` / lightning / weather-volume classes have no UFUNCTIONs of their own (refl.py); their fields are
plain UPROPERTYs.

## 2. Day/night for Survival: options ranked by feasibility

Shared preconditions: Comona has no baked lightmaps **[I]**. The sky light is baked cubemaps per lighting sublevel. Exposure is
pinned per sublevel. Stock CSPs and textures are ordinary stock assets (load them normally; hard rule 9 only concerns
Survival's own packages).

### A. Several lighting sublevels, swapped between rounds (stock pattern: M025_2). Best ratio.
What it gives: day / dusk / night "rounds", each a complete hand-tuned look (sun, sky, clouds, cubemaps, exposure, lens
flare), with a hard cut, best hidden behind the airfield intermission or a fade.
Build time (`build_survival.py`, build_pl):
1. Put the candidate lighting sublevels into PL_SurvivalMode as **LevelStreamingDynamic** entries, like M025_2 does
   (today they are all LevelStreamingAlwaysLoaded copies of M022's). Candidates: Mission004 (day, current), **Mission019**
   (Comona, afternoon), **Mission022** (Comona, dawn), Mission009 (night, Map08), Mission016 (low sun 6 deg). Each needs its
   name + import in the PL and the container header (hard rule 7).
2. Only one starts visible.
3. Night extras: Comona's city/airport lights are already loaded (`Mission022_Env_CityLighting001`). Optionally copy M009's
   CityNight sublevels (not Comona-placed, so probably not).
Run time:
- EP way: survival_events records with `LiveSetVisibleSubLevelExecution {name, true}` and `{old, false}` on a remote event,
  like `EP_Mission025_2_phase03`.
- Lua way: `GameplayStatics:GetStreamingLevel(world, FName "Mission009_Common_Lit_Cloudly01"):SetShouldBeVisible(true)`,
  and the old one false.
Risks:
- Two LiveCloudlyActors visible for a frame (M025_2 shows it's survivable; Cloudly caches actors in
  `UCloudlyWorldSubsystem.CachedCloudlyActors`). **[T]**
- The M009 night sky was authored for Map08: sun/moon azimuth and the ground-emissive map won't match Comona's city. **[I]**
- Graphics profile stays InGameBase (1.3), so cockpit emissives don't go "night". **[I]**
- Memory: each lighting level holds 5 HDRI cubemaps. **[I]**

### B. Cloudly sequencer: a smooth time-lapse
What it gives: the sun really moves; sky colour, sun intensity, moon and stars blend between key CSPs (`SkyParamsBlendMode`
Linear/SmoothStep; `VolumeComponentsBlendMode` Nearest/Highest/Lowest).
Build time:
1. Copy `/Game/Cloudly/CloudlySkyParams/Ingame/Mission025/TimeLaps/CloudlySequencer_ms25_TimeLaps` (216 bytes: KeyFrames
   [{Label, SkyParams obj, VolumeComponents obj, Time}], VolumeComponentsBlendMode 1) to
   `/Game/Mods/SurvivalMode/Lighting/CSEQ_SV_DayNight`.
2. Point its keys at stock CSPs, e.g. t0 CSP_ms04 (15 deg), t1 CSP_ms16 (6.4 deg), t2 CSP_ms22 (-3.7 deg), t3 CSP_Mission009
   (night). Use one CVC (CVC_ms04_20251216) for all keys so the clouds don't jump.
3. In Survival's copy of the M004 lighting sublevel (it would have to become a Survival package), set `CloudlySequencerAsset`.
   Optionally set `EnableCloudlySequencer` = 1 (stock levels ship 0 with time 5).
4. Add StarCatalog/MoonTexture/GroundEmissive to `CloudlyResources` (as M009/M022 do) so night has stars.
Run time (Lua): `cloudly:SetSequencerTime(cloudly, t)`, or write `cloudly.EnableCloudlySequencer = true;
cloudly.CloudlySequencerTime = t`, per tick or per round. Also lerp the exposure (PostProcessVolume Settings
AutoExposureMin/MaxBrightness 13/14 -> 0.5/9, bias) and blend the sky light (`MainSkyLight:SetCubemapBlend(dayTex,
nightTex, f)` with M004 and M009 `TC_*_SkylightCube_AboveClouds`, or `RecaptureSkyLight`).
Risks:
- Unknown whether the sequencer evaluates in game, or only under a cinematic track (the CSEQ_* assets are used by
  `CLS_*_Lit` level sequences). **[T]**
- The sky light and exposure don't follow by themselves.
- Stars or moon may need `SetResourcesIncludingStars`. **[T]**
- One extra Survival package (the sequencer) plus a modified lighting sublevel.

### C. Lua drives the sun directly
What it gives: the cheapest experiment; no build change.
Run time: `cloudly = FindFirstOf("LiveCloudlyActor")`; `cloudly:SetCustomSunPosition(cloudly, elev, az, true)` over time;
`SetCustomMoonPosition`/`SetUseCustomMoon` for the moon; exposure and sky-light changes as in B; maybe
`ForceUpdateShadows(n)`.
Below about -4 deg the atmosphere gives real dusk (that is M022). But "night" would be black unless exposure drops, and there are no stars
unless the resources have them. The other SkyParams (sun intensity, colours) stay day-tuned.
Alternative: swap `cloudly.CloudlySkyParamsAsset` to another stock CSP (e.g. CSP_ms22 or CSP_Mission009) at run time.
That is a one-step look change, and test T2 checks whether Cloudly reacts.
Risks: Cloudly may overwrite the light every frame (so rotating the DirectionalLight alone is pointless) **[I]**; the cubemaps
stay day **[V]**; the custom sun may not survive a restart/phase change **[T]**.

### D. A different sky per run (pick at sortie, no change during the run). Trivial.
Same as A, but chosen once (difficulty/preset or survival.ini): Lua shows one of the streamed lighting sublevels at
mission start, or the build ships one PL per sky. This is what Survival already does with LIT_NEW, just made selectable.

### Not recommended
Rotating `Directional Light Component` by itself (Cloudly drives it; cubemaps and exposure don't follow), and
spawning new SkyAtmosphere/VolumetricCloud actors (Cloudly replaces UE's sky; `EnableAndAutoToggleUnrealSkyAndClouds`).

### Weather options for Survival (for completeness)
- **Thunderstorm round (build time, closest to stock):**
  - Add `LightningDescList` spheres to Survival's world data, copying M016's `Lightning_Cloud0` (SphereVolumeClass import
    `LiveSphereVolume`, RadiusInMeter, SpawnPoint in Comona's sky).
  - Set PL `MissionSettings.LightningVolumeClass` = `BP_LightninigVolume_MS12` (import + header, rule 7).
  - Put them in a phase WD if storms should only be live in one phase. **[I that phase WD descs are phase-scoped]**
  - React with a `LiveStatusOfChangedByWeatherTrigger {AnyPlayer, Lighting}` record (radio callout).
  - Visual storm: Survival already spawns `NS_CloudLightning` from Lua.
- **Thunderstorm at run time:** spawn `BP_LightninigVolume_MS12_C` with `BeginDeferredActorSpawnFromClass` (set `Radius`,
  `bTestPlayer`) then `FinishSpawningActor`. **[T: whether it works without the world-data/observer path]**
- **Rain:**
  - `bIsWorldRain` + `RainVFXBrightness` in the PL world settings (build time).
  - Or write `WorldSettings.bIsWorldRain` from Lua. **[T: read only at BeginPlay?]**
  - Rain areas: a VFX sublevel of `BP_BoxWeatherVolume`s shown/hidden like M030, or Lua-spawned BP_BoxWeatherVolume_C with
    `Extents`, together with `bIsRainVolume`.
  - Mission 4's own VFX sublevel isn't streamed by Survival (Map05 positions).

## 3. Open questions: small in-game tests

All of these need a debug key in main.lua and a log line; none needs a new build unless noted.

1. **T1 sun move**: `c = FindFirstOf("LiveCloudlyActor")`. Log `c.CloudlySkyParamsAsset:GetFullName()`, `c.SunLight`,
   `c.EnableCloudlySequencer`, `c:GetUseCustomSun(c)`. Then on F-key `c:SetCustomSunPosition(c, 3, 142, true)`, later
   `(c, -6, 142, true)`. Look at the sky colour, shadow direction and the sun light's rotation/intensity (log
   `c.SunLight:K2_GetComponentRotation()`). Does it stick for a minute? Does it survive a phase change?
2. **T2 CSP swap**: `c.CloudlySkyParamsAsset = <CSP_ms22_251208 or CSP_Mission009_kanno260116>`, then `c:ForceUpdate({})` /
   `ForceUpdateShadows(c, 30)`. Does the sky change without a reload?
3. **T3 sequencer**: `c.CloudlySequencerAsset = <CloudlySequencer_ms25_TimeLaps>`; `c.EnableCloudlySequencer = true`; then
   `c:SetSequencerTime(c, 0)`, `5`, `10` a few seconds apart. Does the sun climb 12.5 -> 34.5 deg?
4. **T4 exposure**: `FindAllOf("PostProcessVolume")`. Log each one's `Priority` and `Settings.AutoExposureMinBrightness/
   MaxBrightness`. Set the M004 ones to 0.5 / 9. Does the picture brighten at low sun? Does a nested struct write
   (`v.Settings.AutoExposureBias = x`) stick in UE4SS, or does the whole struct have to be copied and written back?
5. **T5 sky light**: on `BP_SkyLightController_C`'s `MainSkyLight`, call `SetCubemapBlend(TC_Mission009_SkylightCube_AboveClouds,
   TC_Mission009_SkylightCube_AboveClouds, 1)`. Does the BP's tick overwrite it at once? If so, set the BP's
   `Texture*` properties instead.
6. **T6 sublevel swap** (needs a build): add `Mission022_Common_Lit_Cloudly01` as a hidden LevelStreamingDynamic. On a key,
   make it visible and hide Mission004's (Lua `GetStreamingLevel`/`SetShouldBeVisible`, or an EP record copied from
   EP_Mission025_2_phase03). Check the switch time, any flash, and that only one sky draws.
7. **T7 rain flag**: Lua `ws = FindFirstOf("ChronicleWorldSettings")`. Log `bIsWorldRain/bIsRainVolume/bIsSnow`. Set
   `bIsWorldRain = true`, `RainVFXBrightness = 10`. Does rain start mid-flight? If not, the flag is read at load and needs a
   build.
8. **T8 lightning** (needs a build): one `LightningDescList` sphere (radius 3 km) 5 km from the runway at 1.5 km, plus
   LightningVolumeClass. Fly in and log health (SV_ health readers), HUD distortion and the
   `StatusOfChangedByWeather/Lighting` trigger. Are strikes damage or only disruption? How often (strike intervals are
   C++ defaults)? Do AI planes get struck (bEnableCollisionNPC)?
9. **T9 lightning without world data**: spawn `BP_LightninigVolume_MS12_C` with `BeginDeferredActorSpawnFromClass` at the
   player + 2 km, `Radius` 300000, then `FinishSpawningActor`. Any strikes?
10. **T10 clock**: change `ClockHour` in the PL (or from Lua) and see what changes (cockpit clock? HUD?). Nothing in the
    lighting should change.
11. **T11 graphics profile**: compare cockpit MFD/landing-light brightness in Survival vs Mission 22 free mission. If
    Survival is visibly off, add a `PLDataMap` entry for PL_SurvivalMode at run time (the DA is soft-loaded, so treat it like
    hard rule 10).

## Files and scratch

- Dumpers written for this (scratchpad, not in the repo): world-settings reader, world-data desc lister, CSP reader
  (uprop needs `Vector3f`/`Vector2f`/`Vector4f` in `NATIVE_SIZE`), reverse-import graph over `build/scan/store.txt`.
- Stock packages pulled into `build/stock/`: all `Maps/Ingame/*/PL_*`, `WD_*`, `EP_*`; lighting sublevels of
  M004/006/009/016/019/022/025_1/025_2_1/025_2_2; the VFX sublevels above; `Cloudly/CloudlySkyParams/...` CSPs and the
  TimeLaps sequencer; `Blueprints/System/Lightning/*`, `Blueprints/VFX/RainVolume/BP_BoxWeatherVolume`,
  `Lighting/Blueprints/*`, `Datatables/Graphics/DA_PLGraphicsSettings_CP` + six `DT_Graphics_MissionNNN`.
