# THE TANACORN's textures: why they look low quality, and the fixes (research of 2026-11-11)

The user's runs of 0.74.60 ("the textures look terrible": flat, blurred, near black on the shaded side) and 0.74.61
("the textures were still low quality", after the flat livemap and the 4096 px Alicorn sheets of HISTORY.md 0.74.61).
Read-only research: nothing was built, cooked or run, and no repo file but this one was written.
Tags: **[V]** seen in a file or a dump (which one is said), **[I]** inferred, **[?]** unknown.

## 0. In short
The 4096 px sheets are in our cook, and no texture group cuts them. What the user sees comes from four things, in
order of how much of the ship they cover:
1. **The Iowa surfaces are one flat grey.** export_tanacorn.py `grey()` clamps the source's linear luminance to
   0.1..0.7, and 30-86 % of the Iowa's texels are under 0.1. Every Iowa-derived base colour comes out with a
   luminance standard deviation of 1-3 levels out of 255, against 24-36 in Sea Power's files. That is 22 % of the
   hull's surface (51,300 m2, the whole main deck included) and the T16, T5 and CIWS mounts. [V]
2. **Nothing has a real livemap.** Every slot shares one 4 x 4 constant (0, 0.75, 1.0): non-metal, rough, no
   occlusion. The stock Alicorn's own MREC sheets give it metallic 0.52-0.56 and roughness 0.21-0.38, with variation.
   The stock Ford's MROS gives roughness variation and a strong baked occlusion. So ours reads as matte grey
   plastic. [V]
3. **The user plays at Texture Quality 1 (Medium).** AC8's Windows scalability sets `r.Streaming.MipBias=2` there,
   and its Windows device profile sets `r.Streaming.UsePerTextureBias=0`. So every streamed texture shows two mips
   down: a 4096 sheet at 1024, a 1024 Iowa texture at 256. This applies to stock assets too. [V settings; I that AC8's
   streaming code works like UE 5.4's]
4. **The Iowa's texel density is low.** At full resolution the main deck has 4.1 texels/m and the superstructure
   9.3 (10 % of it under 1). The Alicorn sheets have 10.2, the same as the stock Alicorn, and the stock Ford has
   17.5. At Medium, divide everything by 4. [V]

These are not causes: the texture-group caps (World and Character are both 16384 in AC8) [V], the cook (the 4096 top
mip is there) [V], and `TextureLODType` (every stock ship checked leaves it at the native default, as ours does)
[V/I].

The fixes, ranked (section 6):
1. Draw the Alicorn surfaces (78 % of the hull's area, plus the railcannon and the sub-railguns) with the stock
   Alicorn's own instances, by path. This also takes 168 MB off the container.
2. Keep the Iowa's light and shade in `grey()`.
3. Give each Iowa slot its own livemap, made from Sea Power's _spec maps.
4. Set NeverStream on our textures of 1024 px and under.
5. Match the stock LOD groups.
6-8. Experiments: a detail normal, TextureLODType, the deck's UVs.

A free diagnostic comes first: one look at the highest Texture Quality.

## 1. The game's texture settings

### 1.1 Texture groups [V: `tools/pak_read.py get` of the config in pakchunk0-Windows.pak]
| group | MinLODSize | MaxLODSize | LODBias | where |
|---|---|---|---|---|
| World, WorldNormalMap, WorldSpecular | 1 | 16384 | 0 | Engine/Config/BaseDeviceProfiles.ini `[GlobalDefaults DeviceProfile]` |
| Character, CharacterNormalMap, CharacterSpecular | 1 | 16384 | 0 | the same |
| Vehicle, VehicleNormalMap, VehicleSpecular | 1 | 16384 | 0 | the same |
| PlayerPlane, -NormalMap, -Specular | 1 | 8192 | 0 | Live/Config/DefaultDeviceProfiles.ini (MipLoadOptions AllMips, HighPriorityLoad) |
| VehicleLarge* (the Ford's textures) | | 4096 [I] | 0 [I] | in no ini: UE 5.4's FTextureLODGroup default (TextureLODSettings.h) |

- AC8's DefaultDeviceProfiles.ini adds only its own groups: PlayerPlane*, TerrainHi*, Effects*, Cloudly / Ocean,
  Avatar*, UI_Stream, *_StreamBias and Cinematic_NeverStream. It never touches World, Character or Vehicle.
  `[Windows DeviceProfile]` (Live/Config/Windows/WindowsDeviceProfiles.ini) adds `r.Streaming.UsePerTextureBias=0`.
  `[WindowsEditor]` sets `r.Streaming.PoolSize=2000`. [V]
- AC8's `TextureGroup` enum is its own: 0 World, 3 Character, 9 PlayerPlane, 15-20 VehicleMed / VehicleLarge,
  21 Vehicle, 84 HierarchicalLOD, 102 Cinematic_NeverStream (`dev enum TextureGroup` on the usmap). Our packages are
  versioned, so a texture's LODGroup goes in by name. World, WorldNormalMap, Character, CharacterNormalMap and
  CharacterSpecular exist in both enums, at the same indices (0, 1, 3, 4, 5). VehicleLarge and PlayerPlane have no
  stock UE 5.4 name, so our editor can't write them. [V]
- **Our 4096 textures in World are not cut down**, not by the game (16384) and not at cook (section 2). In a cooked
  game, `UTextureLODSettings::CalculateLODBias` doesn't add the group's LODBias again; the cook strips those mips
  (UE 5.4 TextureLODSettings.cpp). [V source]

### 1.2 Streaming and Texture Quality [V: the inis; UE 5.4 source]
| sg.TextureQuality | r.Streaming.MipBias | PoolSize (MB) | r.MaxAnisotropy |
|---|---|---|---|
| 0 | 2 | 1300 | 0 |
| **1 (the user's)** | **2** | **1300** | 2 |
| 2 | 1 | 3000 | 4 |
| 3 | 0 | 4000 | 8 |
MipBias and PoolSize come from Live/Config/Windows/WindowsScalability.ini, which wins over BaseScalability.
MaxAnisotropy comes from Engine/Config/BaseScalability.ini, since AC8's Windows file doesn't set it.

- The user's AC8 GameUserSettings.ini (%LOCALAPPDATA%/BANDAI NAMCO Entertainment/ACE COMBAT 8/Saved/Config/Windows,
  read only, saved at her run this morning, 2026-11-11 05:40): `sg.TextureQuality=1` [V].
- Her Survival logs in build/backup, line `render settings: ... r.Streaming.PoolSize=...`:
  - up to 2026-10-30: 4000, which is TextureQuality 3;
  - every one from 2026-10-31 (0.73.0-coop2mp) to 0.74.61: 1300 [V].

  Only TextureQuality 0 or 1 gives 1300, and both set MipBias 2. **She lowered Texture Quality around 2026-10-31**,
  before THE TANACORN existed.
- UE 5.4: `FRenderAssetStreamingSettings::Update` sets `GlobalMipBias = floor(r.Streaming.MipBias)`
  (TextureStreamingHelpers.cpp:313). `FStreamingRenderAsset::UpdateDynamicData` adds it to the LODBias of every
  streamed texture when `bUsePerTextureBias` is 0 (StreamingTexture.cpp:195). It skips only terrain textures,
  TEXTUREGROUP_HierarchicalLOD, and textures that aren't streamed at all (NeverStream: every cooked mip is resident).
  So at her setting, **any streamed texture's top two mips never load**: 4096 -> 1024, 1024 -> 256, stock textures
  too. [V source; I that Bandai's 5.4 fork is the same]
- AC8 adds four cvars of its own, which stock UE doesn't have: r.CinematicNeverStreamTextureLODBias,
  r.TerrainTextureLODBias, r.EffectTextureLODBias and r.UITextureLODBias. Their help texts are in AceCombat8.exe's
  strings (read only). None of them touches our groups. [V]
- The Falken add-on's body skins are single-mip and NeverStream (FALKEN_MATERIALS.md 2.3), which keeps them out of
  this bias [I as its reason].

### 1.3 TextureLODType (AC8's per-object texture LOD management)
- `ALiveAIGameObject::TextureLODType` (ELiveTextureLODType: PlayerHangar, PlayerInGame, OnlinePlayerInGame,
  WingmanInGame, AIObjectLarge, AIObjectMedium, AIObjectSmall, AIObjectTiny, NotManaged, ForceBias). Next to it are
  bIgnoreAllOptimize, bIgnoreMeshOptimize, bIgnoreCollisionOptimize and bIgnoreVisibleDistance
  (build/liveproject/Source/Live/Public/LiveAIGameObject.h:195). **Native default: AIObjectSmall**
  (Private/LiveAIGameObject.cpp:54, the header dump's constructor). No native subclass changes it: no other .cpp sets
  it. [V dump; I that the dump's constructor is the game's CDO]
- Stock CDOs, with every serialized property listed from the unversioned header (method under "How to check"):

| blueprint | TextureLODType | other optimize flags |
|---|---|---|
| BP_BA002_alcn_Root (the Alicorn; class LiveAIAlicorn, 70 BP variables) | not set | bIgnoreVisibleDistance set [I true]; bLargeShip set |
| BP_BA002_alcn_PlnBase (its subclass) | not set | none |
| BP_BA002_alcn_vlsR2_Base | not set (full decode) | none |
| BP_AIShip_Pawn, BP_AIGroundVehicle_Pawn, BP_AIPlane_Pawn | not set | none |
| BP_VE004_grfd_Base (Ford), _VE006_norn_, _VE001_gors_ | not set (header) | none |
| BP_VE002_aegs_Base (Aegis) | not set (full decode) | none |
| BP_VE022_grifn_Base (Grifn) | not set (full decode) | bIgnoreAllOptimize, bIgnoreMeshOptimize, bIgnoreVisibleDistance, bDisableFCSTickOptimization true |
| ours: BP_SV_Tani_HULL, _T5, _T16, _CIWS, _LASER (cooked, versioned) | not set (no `TextureLODType` name in the package) | none |

- So every stock ship and boss checked, and ours, run as AIObjectSmall. What each type does isn't in any config, DataTable or
  reflected struct; the exe has only the enum's names [?]. **Not a difference from stock.** As an A/B only:
  fix 7.

## 2. What the cook holds [V: E:/AC8LiveProject/Saved/Cooked/.../Tanicorn/Textures, read from the bytes after the PF_ string]
| texture | size | format | mips | in .ubulk | LODGroup | NeverStream |
|---|---|---|---|---|---|---|
| T_SV_Tani_HULL_10_D (ALC_a) | 4096 | DXT1 | 13 (first 0) | mips 0-5, 11,182,080 B = 4096..128 exactly | World (default) | no |
| T_SV_Tani_HULL_10_N | 4096 | BC5 | 13 | mips 0-5, 22,364,160 B | WorldNormalMap | no |
| T_SV_Tani_HULL_0_D (Iowa deck) | 1024 | DXT1 | 11 | mips 0-3 | World | no |
| T_SV_Tani_HULL_8_D (underside) | 64 | DXT1 | 7 | none (all inline) | World | no |
| T_SV_Tani_HULL_L (livemap) | 4 | B8G8R8A8 | 1 | none | World | yes, TF_Nearest |
| stock T_BA002_alcn_a_D | 4096 | **DXT5** | 13 | mips 0-5, 22,364,160 B | **Character** | no |
| stock T_BA002_alcn_a_N / _MREC | 4096 | BC5 / DXT1 | 13 | mips 0-5 | CharacterNormalMap / CharacterSpecular | no |

- **The 4096 top mip is in our cook; nothing was dropped.** Our project's own DefaultDeviceProfiles.ini groups with
  AC8 names are "invalid value" warnings in our UE 5.4 (cook.log), so the cook falls back to BaseDeviceProfiles:
  World = 16384. [V]
- Our ALC base colours are DXT1: export_tanacorn.py `save_png` writes alpha 1, and `texture()` sets
  `compression_no_alpha`. The stock a_D's alpha is a cut-out mask (section 3). That's harmless on our opaque gear
  material.
- Container: 243 MB (SurvivalMode_Tani_P.ucas). Its ten 4096 textures (hull 10/11 D+N, RAILCANNON D+N,
  RAILGUN 0/1 D+N) are 167.8 MB of it; the other 41 textures are 6.1 MB.

## 3. The stock Alicorn's materials against ours [V: dumper `dev dump -v`; tex_info.py]
- `SM_BA002_alcn` / `_body` / `_bridge` / the parts use `MI_BA002_alcn_a_Inst` and `_b_Inst`. The chain is
  `/Game/OnlineMode/Vehicles/Boss/BA002_alcn/Materials/MI_BA002_alcn_a_Inst` -> `/Game/OnlineMode/Vehicles/Vessels/
  Common/Materials/vessels_Inst` -> `/Game/OnlineMode/Materials/MI_Vehicle` (static switch Mult_Albedo true) ->
  `/Game/OnlineMode/Materials/Core/M_Basic_Diffuse`, the OnlineMode "vehicle" master. It isn't MP_Gear.
- `MI_BA002_alcn_a_Inst`:
  - textures **Albedo_map** = T_BA002_alcn_a_D, **MREC_map** = T_BA002_alcn_a_MREC and **Normal_map** =
    T_BA002_alcn_a_N, all on UV 0 at sampling scale 1;
  - scalars Base Normal 0, Diffuse Mult 0, Flood Level 0, Puddle Diffuse Mult 1, Specular Intensity 1, wet_clouds 0,
    Wet_Max 0.35, Wet_Percentage 0;
  - static switches Use Puddles false, Wet Surface true;
  - **BLEND_Masked**, clip 0.3333; PhysMaterial PM_06_Boss;
  - its own shader map, with vertex factories **GPUSkin, InstancedStaticMesh and Local** and no virtual textures.
    It can draw both our static hull and our skeletal parts.
  - `_b_Inst` is the same, on the b sheets.
- **No detail map.** M_Basic_Diffuse's 252 names have Albedo / MREC / Normal / AO maps, decals, wet, damage and UV
  scale/offset/rotate parameters, but no detail normal or detail tiling. The Alicorn's close-up detail is only its
  three 4096 sheets.
- The sheets' channels, measured on their mip 1 (alcn/tex/*_2048.png):

  | sheet | channels | mean | std |
  |---|---|---|---|
  | a_MREC | R / G / B / A | 132.6 / 98.2 / 0 / 255 | 74 / 60 |
  | b_MREC | R / G / B / A | 141.9 / 52.9 / 0 / 255 | 33 / 48 |
  | a_D | A | | 2.9 % of texels under 85 |
  | b_D | A | all 255 | |

  - Read as metallic / roughness, the MREC sheets are a semi-metallic, fairly glossy skin. B is 0 everywhere (emissive
    [I]).
  - a_D's cut-outs (alpha under 85) all lie in u 0.50-0.75, v 0.84-1.0. **Neither our UVs nor the stock hull's land
    there**: 0.00 % of ALC_a's area on our hull, RAILCANNON, RAILGUN_L, SM_BA002_alcn and _body (alpha_hits.py).
- Ours: `MI_SV_Tani_*` -> `MI_PP0016_x40a_Gear` -> `MP_Gear` -> `/Game/Base/Material/M_Live_Vehicle_Base`, all on
  the 4 x 4 livemap (0, 0.75, 1.0) and flat Detail_Normal / damage normals, with DNormal_Strength 0. MP_Gear's
  overrides are Use_Wet, USE_AOForSpecularMap and USE_EmissiveFunction true. MI_PP0016_x40a_Gear sets
  Ctrl_All_Emissive 1 and Turbine_speed 0.4, which ue_import's SCALARS zero.
- AC8's own ships, the Ford for example: `MI_VE004_grfd_01` is on `/Game/Base/Material/MP/MP_Live_Vehicle_Base`, a
  MIC with no shader map, so it draws with M_Live_Vehicle_Base's.
  - Textures: Basecolor _D, **Livemap _MROS** (TC_Masks, DXT1) and Normalmap _N, all 4096 in TEXTUREGROUP_VehicleLarge*;
    EmissiveZone T_Black.
  - _MROS on mip 1: metallic 0.01-0.03, roughness 0.57-0.68 (std 0.10-0.13), occlusion 0.41-0.80 (std 0.29-0.32), a
    strongly baked AO. Base colour luminance std is 22.
- M_Live_Vehicle_Base has the names **Detail_Map, Detail_Normal, Detail_Tile_U/V (+ _Offset), DNormal_Strength,
  DNormal_Tile_U/V**. The Ford sets none of them. Whether MP_Gear's permutation samples them is [?].
- Stock tiling normals for a detail-normal test:

  | texture | size | look |
  |---|---|---|
  | `/Game/Base/Texture/Common/T_Base_Tile_Normal` | 2048 BC5, WorldNormalMap | scratched, brushed metal with cracks (preview decoded) |
  | `/Game/Environments/Carrier/Base/Texture/T_LP_CRR_Panel002_I14_N` | 4096 | nearly flat |
  | `/Game/Character/Common/Texture/Cloth/Tiling/T_Metal01_N` | 128 | |

## 4. Texel density [V: scratch texel.py over the export's glTF and the dumper's glb, area-weighted]
Texels per metre at mip 0, for the texture's own size. At the user's Medium setting, divide by 4.
| surface | area m2 | texture | texels/m p10 / p50 / p90 |
|---|---|---|---|
| hull ALC_b (slot 13) | 148,708 | 4096 | 6.5 / 9.7 / 10.2 |
| hull ALC_a (slot 12) | 29,947 | 4096 | 9.2 / 10.2 / 10.3 |
| hull Iowa main tx (slots 14 + 7) | 17,183 + 608 | 1024 | 0.9 / 9.3 / 11.2 |
| **hull Iowa deck (slot 0: the main deck end to end, 95 % facing up)** | 10,932 | 1024 | 4.1 / 4.1 / 4.1 |
| hull trans / lattice (slot 4) | 6,643 | 256 x 1024 | 14 / 19 / 24 (area-equivalent) |
| hull underside (slot 8: undersides of the upper works) | 6,118 | 64, tiled | 7.2 |
| hull mk143 (slots 3 + 11) | 5,515 | 128, tiled | 0.9 / 6.2 / 9.8 |
| hull parts / boats (slots 9, 10) | 3,001 | 512 / 256 | 4.3 / 8.7 / 16.5 |
| T16 mount: deck tx | 525 | 1024 | 5.4 / 5.4 / 5.4 |
| T16 mount: main tx | 1,973 | 1024 | 0.8 / 7.7 / 11.3 |
| T5 mount | 491 | **128** | 1.2 / 9.6 / 16.4 |
| CIWS | 90 | 512 | 3.4 / 15.7 / 21.8 |
| LASER, VLSD, VLSS (our own art) | 50-233 | 256-1024 | 47-68 |
| RAILCANNON, RAILGUN (ALC) | 10,208 / 1,067 | 4096 | 10.1-11.4 |
| **stock Alicorn** (SM_BA002_alcn, _body, _bridge, emlm, vls) | 368,000 | 4096 | 9.8 / 10.2 / 10.3 |
| **stock Ford** (SM_VE004_grfd, its fallback mesh) | 54,408 + 16,065 | 4096 | 15-18 / 17.5-19.8 / 20-27 |

- The Alicorn surfaces have the stock Alicorn's density: hull_uv.py took its UVs, and the hulls are the same size
  (SM_BA002_alcn is 647 m long). Texel density isn't their problem.
- What looks soft for density alone:
  - the main deck: 24 cm a texel at full resolution, ~1 m at Medium;
  - the Iowa superstructure's worst tenth (under 1 texel/m);
  - the tiled 128 px mk143 and T5 textures, and the T16's sides (p10 0.8).
- The contrast that grey() leaves: luminance std out of 255, Sea Power's file -> ours.

  | texture | source | ours |
  |---|---|---|
  | usn_bb_iowa_tx | 36.1 | 1.6 |
  | usn_bb_iowa_deck_tx | 36.4 | 1.1 |
  | usn_parts_tx | 35.9 | 2.9 |
  | underside | 27.2 | 1.3 |
  | usn_mk143_tx | 24.5 | 1.7 |
  | every other Iowa-derived _D (T16, T5, CIWS too) | | 1.0-6.5 |

  For comparison: ALC a_D 38.4, ALC b_D 13.3, our VLS / LASER art 13-39, the Ford's _D 22.3. Share of each Iowa
  texture's texels under grey()'s 0.1 clamp: iowa_tx 57 %, deck 86 %, parts 30 %, mk28 39 %. [V]

## 5. The causes, ranked
1. **Iowa surfaces flat** (grey(); 22 % of the hull's area, including the whole main deck as seen from the air, and the
   T16 / T5 / CIWS). [V]
2. **No livemap detail anywhere**: the ALC sheets lose their MREC, and the Iowa slots have no roughness or AO
   variation. [V]
3. **Medium Texture Quality**: two mips gone on every streamed texture, stock included. Anisotropy 2 blurs long
   decks seen at a grazing angle. [V settings; I code]
4. **Iowa texel density**: the deck 4.1 texels/m, and parts of the superstructure under 1. [V]
Not causes: group caps, the cook, TextureLODType (all [V], the last as far as stock is concerned).

## 6. Fixes, ranked
Every fix keeps AC8's own shaders (hard rules 42 and 58) and ordinary textures (hard rule 44).

**D0. Diagnostic, free, before any build.** Ask the user for one look at the stock Alicorn and the Tanacorn with AC8's
Texture Quality at its highest (sg.TextureQuality 3: MipBias 0, anisotropy 8). That was her setting until 2026-10-31
(section 1.2), so she may want to know it changed. This separates her setting (cause 3) from our assets (causes 1, 2
and 4). Don't change her settings for her.

**1. The Alicorn surfaces on the stock Alicorn instances, by path** (ue_import.py; hull slots 12 / 13, RAILCANNON
slot 0, RAILGUN_L / _R slots 0 / 1).
- Add to ue_import.py:
  ```python
  ALC_MI = {'ALC_a': '/Game/OnlineMode/Vehicles/Boss/BA002_alcn/Materials/MI_BA002_alcn_a_Inst',
            'ALC_b': '/Game/OnlineMode/Vehicles/Boss/BA002_alcn/Materials/MI_BA002_alcn_b_Inst'}
  M_BASIC_DIFFUSE = '/Game/OnlineMode/Materials/Core/M_Basic_Diffuse'
  ALC_TEX = ['Albedo_map', 'MREC_map', 'Normal_map']
  ```
- In `main()`: `alc = {k: stub_instance(p, stub_material(M_BASIC_DIFFUSE, ALC_TEX)) for k, p in ALC_MI.items()}`.
  These are stubs at AC8's paths, never packed: build.sh packs only /Game/Mods/SurvivalMode/Tanicorn, as for
  MI_PP0016_x40a_Gear today. `stub_material` already sets `used_with_skeletal_mesh`.
- Pass `alc` through `part()` into `materials()`. At the top of its slot loop:
  `if s['material'] in alc: mats.append(alc[s['material']]); continue`. The json's `material` is 'ALC_a' / 'ALC_b'
  for exactly these slots.
- The ALC PNGs are then no longer imported. export_tanacorn.py may stop writing them; alcn_textures.py stays for the
  Blender model.
- **On screen**: those surfaces become the stock Alicorn's own look: its MREC (semi-metal, glossy, varied), its normal
  maps, its wet sheen, its hit material. They match its sharpness at any Texture Quality, because they are the same
  streamed textures. It covers 78 % of the hull's area. The container drops by ~168 MB (243 -> ~75 MB).
- **Risk: low.** The instance's shader map has Local and GPUSkin [V]. Its mask region is unused by our UVs [V].
  OnlineMode's packages load in Survival's level (the ALICORN special) [I]. Masked blend on a 125k-triangle hull costs
  what the stock Alicorn's does. If the path doesn't resolve, the slots draw the default material: check with
  `python -I tools/checks/imp_pkgs.py` that the cooked SM_SV_Tani_HULL imports both paths.
- **1b, only if the user wants it sharper than the stock Alicorn at Medium**: a MIC of ours parented on the stub
  (no static switch, no base-property override, as MI_SV_* do on the gear today), with Albedo_map / MREC_map /
  Normal_map set to our own copies, those set `never_stream = True`. That's ~100 MB more VRAM, resident for good.
  It's the user's call.

**2. Keep the Iowa's light and shade** (export_tanacorn.py `grey()`). Replace the fixed clamp with a contrast relative
to each image's median, normalised to keep the Alicorn grey's mean:
```python
lum = c @ np.array([0.2126, 0.7152, 0.0722], np.float32)        # (linear, as now)
k = np.clip(np.sqrt(lum / max(float(np.median(lum)), 1e-4)), 0.5, 1.6)
k = k / float(k.mean())
lin = k[:, :, None] * np.array(GREY, np.float32)
```
- Measured on the sources, before the mean normalisation: luminance std 14.5 (iowa_tx), 16.3 (deck), 10.6 (parts),
  9.7 (mk28), against 1.0-2.9 now. That's the Alicorn b sheet's 13.3.
- **On screen**: planking, panel lines, hatches, portholes and baked shadows come back on the deck, the upper works,
  the T16, the T5 and the CIWS, still Alicorn grey.
- **Risk: low**, export only. Check the tone where the Iowa meets the Alicorn plating, and tune the 0.5 / 1.6 bounds.

**3. A livemap per Iowa slot** (export_tanacorn.py `slots_for`; ue_import.py `materials()`).
- Sea Power ships a `<name>_spec.jpg` beside each `<name>_tx.jpg` (build/tanicorn/iowa/textures: bb_iowa, deck,
  parts, mk143, mk28, mk37, sps_49, sps_67, boats, trans, crew, aircraft_numbers), but none for the flags or the
  underside.
- Write `T_SV_Tani_<part>_<n>_L` beside each _D, with:
  - R = 0 (metallic, as the Ford);
  - G = roughness = 0.85 - 0.5 x spec (spec read as 0..1 grey);
  - B = occlusion = clip(sqrt(lum / median), 0.4, 1.0), from the same lum as fix 2.
- Put it in the slot's json as `livemap`.
- In `materials()`: `lm_s = tex_once(src, s['livemap'], False, TCS.TC_MASKS) if s.get('livemap') else lm`, and
  `('Livemap', lm_s)` in the instance. TC_MASKS gives DXT1, linear, as the stock _MROS / _MRO.
- **On screen**: wet-looking highlights and darker crevices where Sea Power's art has them; no longer one matte value.
  The Ford's livemap is the model (roughness std ~0.1, AO 0.4-0.8).
- **Risk: low.** The channel meaning (M, R, O) is [I] from the names _MRO / _MROS and FALKEN_MATERIALS.md 2.4.
  0.74.61's fix proved B must not be 0.
- Without fix 1, the ALC slots need the same: `(MREC.R, MREC.G, 255)`. Never MREC as it is: its B is 0, which would
  black them out again.

**4. NeverStream on our textures of 1024 px and under** (ue_import.py `texture()`). After the import:
`if max(tex.blueprint_get_size_x(), tex.blueprint_get_size_y()) <= 1024: tex.set_editor_property('never_stream', True)`.
- **On screen**: every texture of ours that stays (Iowa, VLS, LASER, T16 / T5 / CIWS, livemaps) shows its full size at
  any Texture Quality: 4x the linear resolution at the user's Medium.
- **Risk: very low**: ~6 MB of VRAM, resident while the ship is loaded, and the mips cooked inline.
- Not for 4096s unless the user accepts the VRAM (fix 1b).

**5. LOD groups as the stock Alicorn's** (ue_import.py `texture()`):
- base colours: `lod_group` = `unreal.TextureGroup.TEXTUREGROUP_CHARACTER`;
- normals: `unreal.TextureGroup.TEXTUREGROUP_CHARACTER_NORMAL_MAP` (instead of WORLD_NORMAL_MAP);
- livemaps: `unreal.TextureGroup.TEXTUREGROUP_CHARACTER_SPECULAR`.

**On screen**: nothing expected, since the caps are the same [V]. It removes the one unknown, whether AC8's code treats
groups differently (section 1.3). **Risk: none**: the names exist in AC8's enum.

**6. Experiment: a detail normal on the gear instances** (ue_import.py).
- Set `('Detail_Normal', <stub at /Game/Base/Texture/Common/T_Base_Tile_Normal>)` (any normal PNG imported at that
  path, never packed) instead of DefaultNormal.
- SCALARS: `'DNormal_Strength': 0.25, 'DNormal_Tile_U': 32.0, 'DNormal_Tile_V': 32.0`.
- Add `DNormal_Tile_U` and `DNormal_Tile_V` to GEAR_SCALARS so the stub has them.
- **On screen** [?]: if MP_Gear's permutation samples the base's detail normal, fine scratches and brushed metal
  across the Iowa parts. If not, no change. The tile parameters' meaning (repeats across UV 0-1) is [?].
- **Risk: low**: stock texture, stock shaders.

**7. Experiment: TextureLODType** (spec.py hull_bp CDO, and the mounts'): `'TextureLODType': 'NotManaged'`, and for
parity with the stock Alicorn `'bIgnoreVisibleDistance': True`.
- Every stock ship checked runs as AIObjectSmall, so do this only as an A/B after fixes 1-4, so that any change can be
  told apart. **Risk: unknown** (what the manager does is [?]); revert if nothing changes.

**8. The main deck's density** (hull_uv.py / the design, not textures). Slot 0 is the Iowa's deck sheet stretched
along 650 m (4.1 texels/m). Put the main deck on the Alicorn's own deck plating, as hull_uv.py already does where the
Alicorn has flat deck, or tile a plank region of the sheet. **On screen**: a sharper deck from the air. **Risk:
medium**: UV work, a new survey and audit.

## 7. Not determined
- What each ELiveTextureLODType does in AC8's code (no config, no reflected settings; the exe only names the enum).
- Whether Bandai's 5.4 fork applies r.Streaming.MipBias as stock UE 5.4 does. If it does, the stock Alicorn is
  just as soft at Medium, and D0 shows it.
- Whether M_Live_Vehicle_Base's detail normal is live in MP_Gear's permutation (fix 6).
- MREC's B / A meaning (B is 0 everywhere, A 255): emissive and a mask are [I].
- Nothing here was run in game.

## How to check (the commands used)
`<scratch>` is a scratch folder. Run every Python over game files with `python -I`, and never print the AES key.
- Config from the classic pak:
  `python -I tools/pak_read.py list 'Config/'`, then
  `python -I tools/pak_read.py get '(DeviceProfiles|Scalability|Engine)\.ini$' <scratch>/pakcfg`.
  Never DefaultGame.ini: it holds third-party credentials (pak_read.py's note).
- Packages: `. tools/env.sh && KEY=$(python -I tools/env.py --aes-key) && MSYS_NO_PATHCONV=1 tools/bin/retoc.exe -a
  "$KEY" to-legacy --no-shaders --version UE5_4 -f <filter> [-f ...] "$AC8_PAKS" <scratch>/legacy`, with the filters
  MI_BA002_alcn_, Vessels/Common/Materials/vessel, OnlineMode/Materials/MI_Vehicle, Materials/Core/M_Basic_Diffuse,
  BP_BA002_alcn_Root / _PlnBase / _vlsR2_Base, BP_VE00{1,2,4,6}_*_Base, BP_VE022_grifn_Base, BaseAI/BP_AIShip_Pawn /
  BP_AIGround / BP_AIPlane, Vessels/VE004_gfrd/{Textures,Materials/01/MI_VE004_grfd_0,Model/SM_VE004_grfd.uasset},
  Common/Material/MP/MP_Gear, Base/Material/M_Live_Vehicle_Base., Base/Material/MP/MP_Live_Vehicle_Base.,
  MI_PP0016_x40a_Gear, T_Base_Tile_Normal, T_LP_CRR_Panel002_I14_N and T_Metal01_N. Last night's T_BA002_alcn_* were
  reused.
- Dumper (ACE8 Aircraft Builder, only ever with `dev`):
  - `USMAP=build/tanicorn/alcn/mappings.usmap MSYS_NO_PATHCONV=1 ACE8AircraftBuilder.exe dev dump <pkg> -v`;
  - `dev flat <Class>` (the flattened property list: a class's own properties first, then its super's);
  - `dev enum TextureGroup|ELiveTextureLODType`;
  - `dev hex <pkg> <export>` (an export's bytes);
  - `dev smglb <SM pkg> <out.glb>` (the Ford's mesh);
  - `dev find TextureLOD|Optimiz`.
- Unversioned CDO headers, where the dumper stops on an out-of-date struct: parse `dev hex`'s first bytes as UE's
  FUnversionedHeader:
  - 16-bit fragments: skip = bits 0-6, has-zeroes = bit 7, last = bit 8, value count = bits 9-15;
  - then the zero mask: 1 byte if 8 bits or fewer, 2 if 16 or fewer, else 32-bit words.
  - The BP's own property count N = last index - OnEndPlay's index in the parent's `dev flat`, checked on
    RootComponent and PlugHolder. A property is set if `N + its flat index` is in the list.
  - Scratch uvhdr.py does this. It's worth moving into tools/checks with tex_info.py.
- Cooked textures: `python -I tools/checks/tex_info.py <.uexp>`. Then the int32 pair after the PF_ string: the first
  mip, then the mip count; then each mip as (data-resource index, SizeX, SizeY, SizeZ). Name maps (which properties
  were serialized): the strings of the .uasset.
- Texel density: scratch texel.py `<gltf|glb> [material=size ...]` (area-weighted texels/m from POSITION and
  TEXCOORD_0, with node transforms). Mask hits: alpha_hits.py `<alpha png> <gltf|glb> <material>`. Contrast:
  PIL ImageStat over src_*/T_SV_Tani_*_D.png and build/tanicorn/iowa/textures.
- The user's settings: `grep render build/backup/install_before_*/AC8SurvivalMode/AC8SurvivalMode_lua.log`, and
  `[ScalabilityGroups]` in AC8's GameUserSettings.ini, read only.
- UE 5.4 source (E:/UE_5.4):
  - Engine/Source/Runtime/Engine/Private/Streaming/TextureStreamingHelpers.cpp:313;
  - StreamingTexture.h:165 (IsMaxResolutionAffectedByGlobalBias), StreamingTexture.cpp:195, and
    AsyncTextureStreaming.cpp:360 (the per-texture mode AC8 turns off);
  - Engine/Classes/Engine/TextureLODSettings.h (the group defaults);
  - Private/TextureLODSettings.cpp:153 (cooked LODBias).
