# AC8 textures, materials and paints (research of 2026-10-24/25, for VALKA's X-02S)

[V] verified in the cooked data, [T] tested in game, [I] inferred. Tools: `tools/get_stock.sh` (a stock zen package),
`tools/checks/imp_pkgs.py` (what a package imports), `tools/scripts/zenpkg.py` (its names), and the small readers in
this file's "How to check" section.

## 1. The aircraft paint chain
A stock skin is a chain of material instances on one master [V]:

    MI_PP0032_f18e_001_Decal          the skin: Basecolor / Livemap / Normalmap, the paint layers' R_/G_/B_ values
     -> MP_PP0032_f18e_Decal          the aircraft: its number decals; static switches USE_Decal / USE_Number_Custom
      -> MP_Aircraft_Decal            every aircraft: ice, wet, fresnel roughness, dirt, tail colours
       -> /Game/Base/Material/Vechicle/MP/MP_Live_Vehicle_Base_UDIM   the master

The master's slot defaults are T_UDIM_Color / T_UDIM_Normal / T_UDIM_Mask; it carries the damage layer (Charred_*,
Blend_Damaged_*, T_Aircraft_Dam_Level_D / _N), the dirt mask (DirtMask: Ctrl_R_ColorUnevenness / Ctrl_G_OilDirt /
Ctrl_B_Smoke), ice, wet, emissive zones and the per-area decal masks (FrontBody / Wing / WingBottom / Tail / Add01-03).
NPC aircraft reuse the player aircraft's assets (the x40a's textures are under PP0016_x40a) [V].

## 2. Virtual textures (the reason VALKA was black)
Every aircraft skin texture is a **UDIM virtual texture** [V]:

| texture | size | format | VT blocks | VT tile |
|---|---|---|---|---|
| T_PP0032_f18e_001_C / _MRX | 20480 x 4096 | DXT1 | 5 x 1 | 128 + 4 border |
| T_PP0032_f18e_110 | 10240 x 2048 | DXT1 | 5 x 1 | 128 + 4 |
| T_PP0021_su57_002_C / _MRX | 20480 x 4096 | DXT1 | 5 x 1 | 128 + 4 |
| T_PP0025_f15e_120 | 12288 x 2048 | DXT1 | 6 x 1 | 128 + 4 |
| T_PP0016_x40a_001_NO (the x40a's normal map) | 36864 x 4096 | BC7 | 9 x 1 | 128 + 4 |
| T_UDIM_Color / T_UDIM_Mask (master defaults) | 512 x 128 | DXT1 | 4 x 1 | 128 + 4 |
| cockpit textures (T_PP0025_f15e_CP_ADIM_D), T_Livemap | | DXT1 | ordinary | |

(UDIM: an aircraft's UVs run across 5-6 tiles in U, one block each.) The skin instances' shader maps list
FMaterialVirtualTextureStack, so the master samples Basecolor / Normalmap / Livemap as virtual textures. An ordinary
texture in those slots draws pure black [T: 0.66-0.67, no paint parameter changed anything].

### The cooked layout (UE 5.4 FTexturePlatformData, cooked) [V]
Before the pixel-format string: SizeX, SizeY, PackedData (int32 each). The string: FString ("PF_DXT1"). Then: SkipOffset
(int64), bIsVirtual (uint32). Virtual: FVirtualTextureBuiltData: NumLayers, (a uint32), WidthInBlocks, HeightInBlocks,
TileSize, TileBorderSize, then per-layer / per-mip tables and chunk offsets. Ordinary: NumMips, then the mips.
Survival's own virtual cook (UE 5.4.4, r.VirtualTextures on, tile 128 / border 4) writes **the same layout** as AC8's
(5.4.3 "live-SeasonA"): the same fields in the same order, 1 x 1 blocks, 128 + 4 [V]. So the data isn't malformed.

### The 0.69 crash [T]
The 0.69 X-02S container (her three paint textures virtual) made the mission load ~3.5 min, ran the game to ~21 GB and
crashed it when round 1 spawned: LowLevelFatalError "Trying to resize TArray to an invalid size of 2147483648"
(Containers/ContainerHelpers.cpp), the render thread in FRDGBuilder_Execute > GPUSortBatch. Without that container the
load and a whole VALKA fight were normal (2026-10-25). The 0.69.1 container differs from it **only** in those three
textures (all other files the same size: only cook GUIDs differ) [V], so the next test is a clean A/B on virtual
textures. Unknown: what loads them before VALKA's round (Lua loads her model only at her reveal).

### AC8's config (tools/pak_read.py: Live/Config/DefaultEngine.ini in pakchunk0-Windows.pak) [V]
- [/Script/Engine.RendererSettings]: r.VirtualTextures=True, r.VT.EnableAutoImport=False; no r.VT.TileSize /
  TileBorderSize set, so UE's defaults 128 / 4 (as every stock VT and Survival's own cook); r.RayTracing=True (with
  r.RayTracing.Geometry.SkeletalMeshes.LODBias=2), Lumen hardware ray tracing, virtual shadow maps, mesh streaming,
  r.GPUSkin.UnlimitedBoneInfluences / Support16BitBoneIndex, r.SkinCache.CompileShaders.
- [/Script/Engine.VirtualTexturePoolConfig]: a default pool of 1 MB, PF_DXT1 64 MB and PF_BC7 64 MB (size-scalable):
  VALKA's colour / Livemap (DXT1) and normal map (BC7) fall into existing pools.
- DefaultScalability: r.Streaming.PoolSize=2000. AssetManagerClassName=/Script/Live.LiveAssetManager; the asset
  manager's config only excludes editor folders (no primary-asset scans configured there).
Nothing in the config explains the 0.69 container's slow load / memory / crash.

## 3. Texture slots
- Basecolor `_C`: DXT1 sRGB.
- Normalmap `_NO`: BC7 linear (AC7's `_N` as it is: its blue and alpha near 1).
- Livemap `_MRX` (aircraft master): DXT1 linear. It masks the **paint layers**, not metallic / roughness: all zero is
  the neutral value (T_Livemap_Flat, the master's flat default, is all zero) [V]. The layers' colours / metal /
  roughness are the instance's R_* / G_* / B_* parameters (R_ColorFade_Weight, G_Color, B_Color, *_Metallic, ...).
- DirtMask: the dirt / oil / smoke layer.

## 4. Masters with ordinary textures that can paint a skinned mesh [V]
AC8's general masters have ordinary samplers, GPU-skin shaders and the same slot names (shader maps checked:
FGPUSkinVertexFactory present, no FMaterialVirtualTextureStack):

| master | notes |
|---|---|
| /Game/Base/Material/MP/MP_Live_Base_CameraDitherFade | Basecolor / Normalmap / Livemap, Basecolor_Brightness / _Hue_Shift, NormalIntensity |
| /Game/Base/Material/MP/MP_Live_Base_WPO | the same with world-position offset |
| /Game/Base/Material/Character/M_Live_Cha_Base | characters: Basecolor / Normalmap / Livemap (roughness + AO) |
| /Game/Base/Material/Vechicle/MP/M_Dam_Masked | the wrecks' material |

Their Livemap default is T_Livemap (64 x 64, ordinary): red near 0, green and blue high: as a metallic / roughness /
occlusion map that reads non-metal, rough, unoccluded [I]. VALKA's paint variants 9-11 (Lua 0.69.2) use these.

## 5. Effect materials Survival reuses (no shader of its own) [V]
All ordinary samplers, all with local-vertex-factory shaders (a MaterialBillboardComponent can draw them):
- /Game/VFX/Mission/Mission023/MI_ms23FarExp_Flare (on /Game/VFX/Mission/Mission009/AirExplosion/M_ms09FarExp_Flare):
  additive flare: EmissiveMap, MaskMap, Emissive_Intensity, Emissive_Power, EmissiveColor. VALKA's AC7 lens flash
  (MI_SV_ValkaFlare_*) and her portal's glow and photon ring.
- /Game/VFX/Vehicles/Weapon/UAV/Barrier/M_VFX_UAVBarrierSpriteRefraction: sprite refraction (a ring normal map by
  default, RefractionIntensity, BaseRefraction, EdgeBlackIntensity). Her portal's lensing.
- /Game/VFX/Vehicles/Weapon/Impact/Materials/M_Smoke01: lit translucent smoke (BaseTexture an 8 x 8 flipbook atlas,
  LerpColor1 / 2, BrightnessIntensity). Her portal's black event horizon.
- Not reusable: Lighting/LensFlares (the sun's flare, screen space on a background cube).

## 6. Routes for VALKA's paint
1. Virtual textures on the aircraft master (paint 2): AC8's own look. Blocked until the A/B says whether virtual
   textures broke the game (tools/x02s/ue_import.py VIRTUAL, ue/Live/Config/DefaultEngine.ini r.VirtualTextures).
2. Ordinary textures on a general master (paint 9-11): no rebuild needed, works with the current container [to test].

## How to check
- A material's shader map: `F...VertexFactory` names (which mesh kinds it can draw) and `FMaterialVirtualTextureStack`
  (virtual samplers) appear in its cooked package's names / bytes.
- A texture: `python -I tools/checks/tex_info.py <package>` reads the platform data after its "PF_..." string (above).
