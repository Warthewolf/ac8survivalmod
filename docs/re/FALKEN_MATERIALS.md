# The Falken add-on's materials, and what VALKA's X-02S should copy (research of 2026-11-02)

Source: "Falken Add On 1.0.0" (ADF-01B FALKEN as a player aircraft for AC8; AC7's model and textures), the zip in
your downloads folder, read only. Nothing of it was copied into this repo. Tags as in AIRCRAFT_MATERIALS.md: **[V]** verified
in the packages, **[I]** inferred, **[T]** in game. Stock packages for comparison were pulled with retoc
(build/scan/all_chunks.txt ids) into the research scratchpad.

## 0. In short
- The Falken draws because every painted surface is an instance of a **non-virtual-texture aircraft material**: the
  ADFX-02's landing-gear instance `MI_PP0038_adfx02_Gear` -> `MP_Gear` -> `/Game/Base/Material/M_Live_Vehicle_Base`.
  That chain's compiled shaders (GPU skin included) sample Basecolor / Livemap / Normalmap as ordinary textures, so
  AC7's ordinary 4K textures on AC7's 0-1 UVs show as they are. No virtual textures, no UDIM, no master or shader of
  their own. [V]
- VALKA's X-02S drew black because `MI_X02S_Valka` is an instance of `MP_PP0032_f18e_Decal` -> `MP_Aircraft_Decal` ->
  `MP_Live_Vehicle_Base_UDIM`, whose shaders sample those slots as virtual textures (hard rule 44). The mesh, its UVs
  and the textures are comparable to the Falken's (both AC7, both single-tile). Only the parent is wrong. [V/T]
- Cooking isn't the difference: theirs is unversioned with AC8's property layout, ours versioned; both load (hard rule
  42). [V/T]
- Fix: parent VALKA's paint on the x40a's own gear instance `MI_PP0016_x40a_Gear` (the same shaders), with the gear
  master's parameters set as the Falken sets them (section 6).

## 1. What the add-on ships [V]
Container `Falken_Dev_P` (IoStoreLoaderMod): **unencrypted, uncompressed** (no AES key needed; compression methods
none), 85 packages, 98 chunks: only ExportBundleData, BulkData and the container header, so **no shader code**. All 85
paths are new (none of the 89,362 stock package paths is overridden): the aircraft is `PP9001_falken`, the player
blueprint `PP9001_falken_L001`, the add-on's own data under `/Game/Mods/Falken`.

| kind | packages |
|---|---|
| skeletal meshes | `SK_PP9001_falken` (body: 12,029 vertices, 1 LOD, 1 UV channel, 2 sections: surface + sensor glass), `_CP` (cockpit, 16,659), `_GearOn` (6,883), `_SWP1` (laser bay interior, 2,223) |
| static meshes | `SM_PP9001_falken_GearOff / RefuelOff / RefuelOn / SWP2 / SWP3 / CanopyWeather / Hangar_4AAM / Hangar_FAEB` (the last two are SWP2's geometry); `/Game/Mods/Falken`: TLS preview and rack, `SM_Replay_SocketSet_Falken` (59 camera sockets) |
| skeletons, physics, anims | 4 skeletons, 4 physics assets, 4 anim sequences + a cockpit camera anim; 4 anim blueprints |
| material instances | 13 MaterialInstanceConstants, **no UMaterial** (section 2) |
| textures | 29 Texture2D, all ordinary (section 2.3) |
| blueprints | `BP_PlayerPlane_PP9001_falken_L001` (a clone of the ADFX-02's: it still names `DT_PP0038_adfx02_L001_FX_MapTable`, the ADFX-02's engine sounds, `SM_PP0038_adfx02_SWP1/4/5/6`, `DPP1/2`, `A_PP0038_adfx02_Cockpit_Camera`), `BP_DisplayPlane_PP9001_falken_L001` (shipped, but the Lua uses the stock ADFX-02 display class), `BP_Falken_TLS`, `BP_Falken_FAEB` |
| DataTables | `DT_PlayerParameter_PP9001_falken_L001`, `DT_FlightEnginePartsAnimationConfig_PP9001_falken_L001` (stock folders, new names); `/Game/Mods/Falken/Data`: `DT_FalkenAircraft` (an aircraft table importing every stock `DT_PlayerParameter_*`), `DT_FalkenHangar`, `DT_FalkenSkins`, `DT_FalkenWingman`, `DT_FalkenBodyBoneConfig` |
| UI | 8 textures, 256 x 256 B8G8R8A8 (skin previews, tree / HUD icons) |

The meshes are AC7's geometry on a renamed rig: the body skeleton uses AC8's `BN_` bone names (14 shared with the
ADFX-02's, e.g. `BN_Body`, `BN_L_Aileron_01`; its own `BN_Canard_01`, `BN_Missile_Cover_*`, `BN_SWPCover1_*`,
`BN_Adf11_Rudder`), where AC7 names bones without a prefix (our X-02S: `Body`, `L_Nozzle`, `VariableWing_*`). Their
static meshes carry UE's generated lightmap UV channels (UV1 / UV2 at 0.008-0.99), so they went through a UE editor
import. [V; "renamed" I]

## 2. How its materials work

### 2.1 The parents [V]
| instance | parent | used for |
|---|---|---|
| `zoef_00_Decal_Inst` | `/Game/Vehicles/Aircraft/PP/PP0038_adfx02/Materials/Common/MI_PP0038_adfx02_Gear` | body slot 0 (the mesh's default), gear, refuel parts, Wardog skin's `DecalMaterialRef` |
| `zoef_00_Inst`, `aircraft_GEN_Glass_Inst` | the same | copies of the above (their name maps still hold `zoef_00_Decal_Inst`'s name and path) |
| `MI_Falken_Skin_03 / 04 / 05` | the same | the Mage / Spare / Strider skins' `DecalMaterialRef` |
| `w_tls_x2_Inst` | the same | the laser bay interior |
| `zoef_CP_Inst` | `/Game/Vehicles/Aircraft/Common/Material/MP/MP_Gear` | cockpit. **Byte copy** of the stock `MI_PP0038_adfx02_Gear` export (23,767 bytes, 3 differ: its three texture imports), its 23,146-byte static-permutation shader map included |
| `zoef_CP_Holo_Trans_Inst` | `/Game/Vehicles/Aircraft/Common/Material/MP/M_HUD_Inside` | cockpit HUD glass. Export **byte-identical** to stock `MI_PP0038_adfx02_HUD_Inside` |
| `zoef_Canopy1_Inst`, `M_Canopy_Layered_Inst01` | `MP_Canopy_Outside` | canopy / sensor glass (body slot 1) |
| `zoef_CP_Glass_Inst` | `MP_CP_Canopy_Inside` | |
| `zoef_Instr_Glass_Inst` | `MI_Glass_Fresnel` | |
| `MI_Falken_TLS_Rack` | `/Game/Vehicles/Ground/Common/Material/MPL_Common_Live_Vehicle_Specular0_5_Base` | the TLS rack |

The stock chain under the body: `MI_PP0038_adfx02_Gear` (USE_Decal overridden, `bHasStaticPermutationResource`, its
own shader map) -> `MP_Gear` (imports `M_Live_Vehicle_Base`, `T_SRGBcolor`, `T_Livemap`, `EmissiveLightMap`,
`T_FlatNormal`) -> `/Game/Base/Material/M_Live_Vehicle_Base`.

### 2.2 Shader maps [V]
| material | vertex factories | virtual textures | platform |
|---|---|---|---|
| `MI_PP0038_adfx02_Gear`, `MI_PP0016_x40a_Gear`, `MP_Gear`, `M_Live_Vehicle_Base` | GPUSkin, Local, InstancedStaticMesh, GeometryCollection | **none** | PCD3D_SM6 |
| `MP_Live_Vehicle_Base_UDIM`, `MP_Aircraft_Decal`, `MP_PP0038_adfx02_Decal` | the same | **FMaterialVirtualTextureStack** | PCD3D_SM6 |
| `M_Live_Cha_Base` (for comparison) | GPUSkin, Local, InstancedStaticMesh | none | |

- The add-on has no master of its own. Its body instances have no static parameters (no `StaticParametersRuntime`, no
  `bHasStaticPermutationResource`), so they draw with their parent's static permutation, `MI_PP0038_adfx02_Gear`'s.
- Its only two shader maps are the byte copies above. With no shader code in the container, they draw with code AC8's
  own shader library already has. [V that none ships; the lookup by hash I]
- Every stock player aircraft has an instance like this: `MI_PPnnnn_<code>_Gear` (~25 KB, on `MP_Gear`). The x40a's
  `MI_PP0016_x40a_Gear` has the same parent, the same USE_Decal override, the same 23,146-byte shader-map tail and the
  same vertex factories as the ADFX-02's.

### 2.3 Textures [V]
Nothing is virtual, nothing is UDIM, and no texture of AC8's skins is reused (no re-authoring onto AC8's UV layouts).
| texture | size / format | mips | properties set (AC8 indices) |
|---|---|---|---|
| `T_Falken_Red_D` (Wardog), `T_Falken_Skin_03/04/05_D` | 4096 x 4096 DXT1 | **1**, inline (8 MB in the export) | ImportedSize, LightingGuid, **NeverStream** (sRGB default, no LODGroup, no compression setting) |
| `T_Falken_SurfaceMask` (body Livemap) | **4 x 4** B8G8R8A8 | 1 | CompressionSettings TC_VectorDisplacementmap (uncompressed), sRGB off, NeverStream; every texel R 0, G 191, B 255, A 255 |
| `zoef_00_D` / `zoef_CP_D` | 4096 DXT1 / DXT5 | 13, mips 0-5 in .ubulk | ImportedSize, LightingGuid |
| `zoef_00_MREC` / `zoef_CP_MREC`, `w_tls_x2_MREC`, `aircraft_CP_Glass_MREC` | 4096 DXT5 / DXT1, 2048 DXT1 | 12-13 | TC_Masks, sRGB off |
| `zoef_00_N`, `zoef_CP_N`, `w_tls_x2_N`, `Glass_N` | 4096 / 2048 **BC5** | 12-13 | TC_Normalmap, LODGroup WorldNormalMap, sRGB off |
| `T_Falken_TLS_Rack_D / _MROS / _N` | 2048 / 1024 DXT1, BC5 | 1 | NeverStream (+ TC_Masks / TC_Normalmap) |
| stock `T_PP0038_adfx02_Gear_C / _MRO / _N` (compare) | 4096 DXT1 / DXT1 / BC5 | 13 | LODGroup TEXTUREGROUP_PlayerPlane / ..Specular / ..NormalMap, TC_Masks / TC_Normalmap |
| stock `T_PP0038_adfx02_001_C` (the ADFX-02's skin) | 28672 x 4096 DXT1 | virtual, 7 x 1 blocks | VirtualTextureStreaming |

No LODBias anywhere. The streamed ones have the stock cook's mip layout (the stock gear textures': 13 mips, mips 0-5 in
bulk, the tail inline). The body's skin textures alone are single-mip and NeverStream; the cockpit's streamed 13-mip
textures work, so streaming from a mod container isn't the problem [I].

**UVs** (cooked vertex buffers, read directly): Falken body U 0.002-0.998, V 0.003-0.996, one channel; cockpit, gear
and bay the same. **VALKA's `SK_X02S_Valka`: U 0.001-0.999, V 0.001-0.998, one channel.** Stock `SK_PP0038_adfx02`: U
-2.65 to 6.997 (UDIM, 7 tiles, matching its 7-block VT), two channels, 4 LODs. [V]

### 2.4 The body's parameters [V] (why each is set: [I])
`zoef_00_Decal_Inst` (and the skins, which change Basecolor only):
- Textures: **Basecolor** = `T_Falken_Red_D`; **Livemap** = `T_Falken_SurfaceMask`; **Normalmap** =
  `/Engine/EngineMaterials/DefaultNormal`; **Detail_Normal** and **Blend_Dameged_Normalmap** =
  `/Game/Base/Texture/Common/T_FlatNormal`.
- Scalars, all 0: **Ctrl_All_Emissive** (the gear instance has 1), **Turbine_speed** (gear 0.4), **NormalIntencity**,
  **DNormal_Strength**, **DamegedNormal_Intencity**, **PlayerPlane_Damage**.
- No static switches. No vectors.

What they do:
- On `MP_Gear` the Livemap slot holds the gear's `_MRO` map (`T_PP0038_adfx02_Gear_MRO`: TC_Masks, linear) and
  defaults to `T_Livemap`. Read as metallic / roughness / occlusion, the Falken's constant (0, 0.75, 1.0) is
  non-metal, fairly rough and unoccluded. [I from the names and the default]
- The gear master samples `EmissiveLightMap` on UV channel 1 (`TextureStreamingData` UVChannelIndex 1). The Falken has
  one UV channel, which is likely why Ctrl_All_Emissive is 0.
- The `Detail_Normal` / damage-normal names exist in `M_Live_Vehicle_Base` (not in `MP_Gear` or the gear instance):
  zeroing them switches off the base's detail and damage normals.
- AC7's `zoef_00_N` and `zoef_00_MREC` ship but no body instance uses them (the body is flat-normal, constant
  Livemap). The cockpit uses its `_D / _MREC / _N` as they are on `MP_Gear`.

### 2.5 The history in the name maps [I]
The body instances' name maps begin with a sorted block that holds `MP_PP0038_adfx02_Decal`, `T_PP0038_adfx02_001_C /
_NO / _MRX` (the ADFX-02 skin chain's defaults), `Default_000_D` and `T_Black01_M` (`M_Live_Vehicle_Base`'s defaults),
`TextureStreamingData` and `zoef_00_D / _MREC / _N`; their imports still list those ADFX-02 skin packages, now
unreferenced. After the block come appended names: `MI_PP0038_adfx02_Gear`, `T_Falken_Red_D`,
`T_Falken_SurfaceMask`, `DefaultNormal`, `Ctrl_All_Emissive`, `Turbine_speed`, and then a second group,
`T_FlatNormal`, `Blend_Dameged_Normalmap`, `DNormal_Strength`, `DamegedNormal_Intencity`, `Detail_Normal`,
`NormalIntencity`, `PlayerPlane_Damage`. So the body instance was first cooked **on the ADFX-02's UDIM skin parent
with AC7's textures**, which is VALKA's set-up, and then patched twice: once re-parented onto the gear instance with a
new Basecolor, a constant Livemap and a flat normal, then with the base's damage and detail normals switched off.

### 2.6 At run time (falken-us4ss/Scripts/main.lua) [V]
- Registers the aircraft with `AddRow` into `DT_LiveAircraft`, `DT_HangarAircraft`, `DT_Skin`, the aircraft tree,
  `DT_WingmanAircraft` and the cinematics socket table, copying from its own tables and ADFX-02 donor rows
  (`OriginalPlaneStringID = PP0038_adfx02_L001`). Assets are loaded with `MakeSoftObjectPath` ->
  `LoadAsset_Blocking` and pinned in an `ObjectReferencer` (as our hard rules 9 / 10).
- Skins: `DT_FalkenSkins` rows set `DecalMaterialRef` to `zoef_00_Decal_Inst` / `MI_Falken_Skin_0n`, so the game's own
  skin system loads the gear-chain instances where a stock aircraft's row names its UDIM `_Decal` instance.
- Hangar: uses the stock ADFX-02 display class and swaps in the Falken's meshes (`SetSkeletalMeshAsset`,
  `SetAnimClass`), then sets materials by hand: `OverrideMaterials:Empty()`, `SetMaterial(i, zoef_00_Decal_Inst)` on
  every slot of the body, gear and refuel parts, and slot 1 to the sensor glass. Flight: its own player blueprint, the
  same `SetMaterial` pass re-applied (log: "Flight build with static red materials").
- Paint: on `LiveSkinMaterialComplition:OnCompleteLoadDecal` and every few updates, for each slot whose chain holds
  one of its instances: `CreateDynamicMaterialInstance(slot, material, 'FalkenSkin')` then
  `SetTextureParameterValue('Basecolor', <the skin's texture>)`.
- The laser bay: `AddComponentByClass(SkeletalMeshComponent)` on the plane, the SWP1 mesh, `w_tls_x2_Inst` on it: the
  same technique as our hard rule 46.

## 3. How it was cooked
- **All 85 packages are unversioned** zen packages, package flags 0x80002200 (FilterEditorOnly | Cooked |
  UnversionedProperties), like AC8's stock. Ours: versioned (zen versioning info ue4 522, ue5 1012, licensee 0;
  flags 0x80000200). [V]
- **AC8's UTexture has one runtime property that stock UE 5.4 doesn't: `ForceStreamedMips` (int32), index 8**, between
  LODBias and CompressionSettings. [V: AC8's usmap against $UE's Texture.h / Texture2D.h /
  StreamableRenderAsset.h] Unversioned properties are written by index, so:

  | property | stock UE 5.4 | AC8 |
  |---|---|---|
  | ImportedSize / LightingGuid / LevelIndex / LODBias | 4 / 5 / 6 / 7 | 4 / 5 / 6 / 7 |
  | ForceStreamedMips | (none) | 8 |
  | CompressionSettings | 8 | 9 |
  | LODGroup | 13 | 14 |
  | SRGB | 17 | 18 |
  | VirtualTextureStreaming | 19 | 20 |
  | NeverStream (UStreamableRenderAsset) | 28 | 29 |

  A stock-5.4 unversioned texture with any non-default property from CompressionSettings on is misread in AC8: its
  one-byte CompressionSettings at 8 is read as the int32 ForceStreamedMips. That is the likely mechanism behind hard
  rule 42's `ObjectSerializationError ... T_X02S_Valka_NO` (BC7: a non-default CompressionSettings) [I]. **The
  add-on's textures are written with AC8's indices** (CompressionSettings 9, LODGroup 14, SRGB 18, NeverStream 29,
  values that make sense for each texture, as stock's do) [V]. So whatever cooked them had AC8's layout: either a UE
  5.4 with that property added, or a usmap-driven re-serialisation [I; which one isn't knowable from the bytes].
- Signs of a package-editing pass after the cook [V facts, I conclusion]: many name maps carry what neither AC8's
  stock zen packages nor UE's IoStore writer put there: property names (`ParameterInfo`, `TextureStreamingData`, the
  SkeletalMesh build settings), ExpressionGUIDs as strings (`{808BD934-424A-60BA-7CC1-65A12822039B}` is Basecolor's)
  and import-table names (`/Script/Engine`, `Class`, `Default__MaterialInstanceConstant`, `Package`). Cloned packages
  keep their source's names (section 2.1). This looks like a zen -> legacy -> edit with AC8's usmap -> zen round trip
  (retoc to-legacy / a UAssetGUI-style editor / retoc to-zen). The texture properties are UE importer defaults (normal
  maps auto-set to TC_Normalmap / WorldNormalMap / sRGB off, fresh LightingGuids), and the meshes have generated
  lightmap UVs: they were imported and cooked in a UE editor first.
- No engine, tool, project or user-path strings in any package. The only names: the container `Falken_Dev_P` and
  the folder `/Game/Mods/Falken`. [V]
- **For us: unversioned isn't what makes theirs work.** Our versioned packages load (hard rule 42, tested); the
  material parent is the difference.

## 4. The comparison
| | Falken (works) | VALKA's X-02S (black) |
|---|---|---|
| source | AC7 ADF-01B | AC7 X-02S |
| mesh | skeletal, AC7 geometry, rig renamed to AC8 `BN_` bones, 1 LOD | skeletal, AC7 geometry with GearOff / RefuelOff / SWP3 merged, AC7 bone names + socket bones, 1 LOD |
| UVs | 1 channel, 0-1 | 1 channel, 0-1 |
| on the plane | its own player blueprint + Lua `SetMaterial` | a SkeletalMeshComponent added to an AI x40a (hard rule 46) + Lua paint |
| body instance's parent | `MI_PP0038_adfx02_Gear` -> `MP_Gear` -> `M_Live_Vehicle_Base` | `MP_PP0032_f18e_Decal` -> `MP_Aircraft_Decal` -> `MP_Live_Vehicle_Base_UDIM` |
| parent's samplers | ordinary | **virtual** (FMaterialVirtualTextureStack) |
| shader map shipped | none of its own (2 byte copies of stock instances) | none |
| static switches on the body | none | none |
| Basecolor | 4096 DXT1, ordinary (1 mip, NeverStream) | 4096 DXT1 sRGB, ordinary, 13 mips |
| Normalmap | engine `DefaultNormal` (AC7's BC5 shipped, unused) | 4096 **BC7**, linear |
| Livemap | 4 x 4 constant (0, 0.75, 1.0) | 256 x 256 DXT5, **all zero** (the UDIM master's neutral) |
| emissive / turbine / damage | Ctrl_All_Emissive 0, Turbine_speed 0, detail / damage normals off | not set (not on that master) |
| cook | unversioned, AC8 layout, edited after | versioned (stock 5.4 editor, `ue/Live`), retoc to-zen |
| VT | none | none since 0.69.1 (our own VTs crashed: hard rule 44) |

**Why theirs draws:** its body samples ordinary textures through compiled GPU-skin shaders that AC8 already ships (the
ADFX-02's gear permutation). **Why ours was black:** our ordinary textures went into a master whose shaders sample
those slots as virtual textures; that draws black whatever the values (hard rule 44). Our VT attempt crashed the game
(0.69). The Falken simply never uses the UDIM master.

## 5. Recipe for VALKA's X-02S
Step 1 needs no rebuild and should come first.

1. **Lua-only test on the current container** (it already holds ordinary `T_X02S_Valka_C / _NO / _LM`). Add a paint
   variant to `sv_anomalies.lua` `SPC.V.paint`:
   - Load the stock `/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear.MI_PP0016_x40a_Gear`
     (the x40a's own gear instance; `MI_PP0038_adfx02_Gear`, the Falken's parent, is the same permutation) by
     `MakeSoftObjectPath` -> `LoadAsset_Blocking`, and pin it.
   - On each body / cockpit slot of her added component (not the canopy / glass slots), call
     `CreateDynamicMaterialInstance(slot, gear, FName('SV_ValkaPaint'))`. A dynamic instance is a run-time instance,
     so the stock material is unchanged (memory note "no stock changes in game").
   - Textures: Basecolor = `T_X02S_Valka_C`; Livemap = `/Game/Base/Texture/Common/T_Livemap`, MP_Gear's own neutral
     default. **Not** `T_X02S_Valka_LM`: all zero reads as metallic 0, roughness 0, occlusion 0 on this master [I].
     Normalmap = `T_X02S_Valka_NO`, with a second variant on `/Engine/EngineMaterials/DefaultNormal` (the Falken's
     choice) in case the BC7 normal reads wrong in the gear's normal sampler.
   - Scalars: `Ctrl_All_Emissive` 0, `Turbine_speed` 0, and, as the Falken does, `NormalIntencity`,
     `DNormal_Strength`, `DamegedNormal_Intencity`, `PlayerPlane_Damage` 0 plus `Detail_Normal` /
     `Blend_Dameged_Normalmap` = `/Game/Base/Texture/Common/T_FlatNormal`.
   - Log each MID's parent chain and the textures read back.
2. **The cooked instance** (tools/x02s/ue_import.py), once step 1 paints her:
   1. `BODY_PARENT = '/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear'`.
   2. Stub that chain at its real paths: `stub_material('/Game/Vehicles/Aircraft/Common/Material/MP/MP_Gear',
      ['Basecolor', 'Livemap', 'Normalmap', 'Detail_Normal', 'Blend_Dameged_Normalmap'], ['Ctrl_All_Emissive',
      'Turbine_speed', 'NormalIntencity', 'DNormal_Strength', 'DamegedNormal_Intencity', 'PlayerPlane_Damage'])`, and a
      MaterialInstanceConstant stub at `MI_PP0016_x40a_Gear`'s path parented on it, with **no static switch** (a stub
      UMaterial at that path would likely do too: a zen import is a package id + export hash, not a class [I]). The
      instance's flat-normal textures, if set at build time, need stubs too, at `/Game/Base/Texture/Common/T_FlatNormal`
      (and `T_Livemap` if used). build.sh already packs only `/Game/Mods/SurvivalMode/Valka`, so no stub ships.
   3. In `material()`: Basecolor C, Normalmap NO, Livemap (step iv's), plus the scalars and the two flat-normal
      textures of step 1 (the same `TextureParameterValues` / `ScalarParameterValues` structs the script already
      writes). **Don't override any static switch**: `MI_X02S_Valka` must stay without `bHasStaticPermutationResource`,
      so it draws with `MI_PP0016_x40a_Gear`'s shaders.
   4. Textures: `VIRTUAL` stays False. `T_X02S_Valka_NO` as `TC_NORMALMAP` (BC5, linear), like every stock aircraft and
      Falken normal map, not `TC_BC7`. `T_X02S_Valka_LM` becomes an MRO map in prepare.py: R metallic 0, G roughness
      ~191, B occlusion 255 (the Falken's constant), or AC7's x02s `_MREC` remapped once its channel order is checked.
      Keep 13 streamed mips (the Falken's cockpit streams fine); NeverStream isn't needed.
   5. Cook **versioned** as now (hard rule 42; our engine is stock 5.4, AC8's UTexture layout differs: section 3).
      `retoc to-zen` and `pad.py` unchanged.
   6. Check before packing: `python -I tools/checks/tex_info.py` on the cooked `MI_X02S_Valka` must say "neither a
      texture nor a material with a shader map" (no shader map of ours); `imp_pkgs.py` on it must list
      `.../PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear` and no `MP_PP0032_f18e_Decal`; `tex_info.py` on the three
      textures: virtual False, `_NO` PF_BC5.
3. **Lua**: the paint variant puts the cooked `MI_X02S_Valka` on the body slots (`M_NPC_Canopy` on the glass, as
   now); make it `CFG.specials.valka.paint`'s default once seen in game. Keep step 1's runtime variant as the fallback.
4. **In game, check**: paint visible from all sides at 1-15 km; no glowing patches (else Ctrl_All_Emissive isn't 0);
   no mirror-like or very dark shading (the Livemap); the normal map's bumps the right way up (else DefaultNormal).
   Then record it as a hard rule and add `MP_Gear` / the `_Gear` instances to AIRCRAFT_MATERIALS.md section 4.

## 6. Not determined
- Which tool made the add-on's unversioned packages: a UE 5.4 with AC8's extra UTexture property, or a usmap-driven
  re-serialisation of a stock cook. Only the result (AC8's indices) and a later package-editing pass are visible.
- The Livemap channels on `MP_Gear` (metallic / roughness / occlusion) are inferred from the `_MRO` names, the
  `T_Livemap` default and the Falken's constant. The shader wasn't decompiled.
- Why the Falken's body dropped AC7's normal map and `_MREC` (shipped, unused), and why its skin textures are
  single-mip. Its packages don't say.
- Whether our BC7 `_NO` reads correctly in the gear's normal sampler (step 1 tests it), and whether a stub at an MIC's
  path cooks an import the game resolves (step 2.ii; expected yes).
- Nothing here has been run in game. The Falken is a player plane; VALKA is an AI x40a with an added
  SkeletalMeshComponent. `MP_Gear`'s shaders cover the GPU-skin vertex factory, so it should draw there too [I].

## How to check (scratch scripts, research scratchpad `falken/work/`; not in the repo)
- `zhdr.py <zen pkg>`: versioned or not, versioning info and custom versions, package flags, name map, imported
  packages.
- `props.py <zen pkg> [class]`: an unversioned instance's parent, parameters and static switches, imports named by
  package (AC8's usmap through tools/scripts/uprop.py).
- `texprops.py <zen pkg>`: a cooked texture's properties by AC8's indices, its size, format and mip count.
- `uvscan.py <cooked mesh>`: each LOD's vertex count and UV ranges (UDIM or 0-1), from the cooked position and
  static-mesh vertex buffers (5.4: a 2-byte strip-flags word before the second).
- `getstock.py <out> <path>...`: tools/get_stock.sh into another folder (the key read at run time).
Worth moving into tools/checks if this route is taken.
