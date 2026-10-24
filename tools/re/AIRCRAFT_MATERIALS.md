# AC8 aircraft materials and paints (research of 2026-10-24/25, for VALKA's X-02S)

[V] verified in the cooked data, [T] tested in game, [I] inferred.

## The chain
A stock skin is a chain of instances on one master material [V]:

    MI_PP0032_f18e_001_Decal          (the skin: Basecolor / Livemap / Normalmap textures, paint-layer values)
     -> MP_PP0032_f18e_Decal          (the aircraft: its number decals, static switches USE_Decal / USE_Number_Custom)
      -> MP_Aircraft_Decal            (all aircraft: ice, wet, fresnel roughness, dirt)
       -> /Game/Base/Material/Vechicle/MP/MP_Live_Vehicle_Base_UDIM   (the master)

The master's texture slots default to T_UDIM_Color / T_UDIM_Normal / T_UDIM_Mask, and it carries the damage layer
(Charred_*, Blend_Damaged_*, T_Aircraft_Dam_Level_D/N), the dirt mask, ice, wet and the per-area decal masks
(FrontBody / Wing / Tail / Add01-03 ...).

## Virtual textures
The skins' textures are **virtual textures** [V]: right after the pixel format, T_PP0032_f18e_001_C / _MRX and
T_UDIM_Color carry VT built data (tile 128 px, border 4 px); an ordinary texture carries its mip chain there
(T_Livemap, and our X-02S textures before 0.68). The stock instances' shader maps list FMaterialVirtualTextureStack.
So the master samples Basecolor / Normalmap / Livemap as virtual textures, and an ordinary texture in those slots
drew pure black [T: 0.66-0.67, every paint parameter changed nothing]. Survival's UE project now has
r.VirtualTextures=True (tile 128, border 4) and tools/x02s/ue_import.py marks the X-02S's textures virtual.

## Texture slots
- Basecolor `_C`: DXT1 sRGB, VT.
- Normalmap `_NO`: BC7 linear, VT (AC7's `_N` as it is: its blue and alpha near 1).
- Livemap `_MRX`: DXT1 linear, VT. **Not metallic / roughness**: it masks the paint layers. All zero is the neutral
  value: T_Livemap_Flat (the master's "flat" default) is all zero [V]. The layers' own colours and values are the
  instances' R_* / G_* / B_* parameters (R_ColorFade_Weight, G_Color, B_Color, *_Metallic, *_Roughness).
- DirtMask: the dirt / oil / smoke layer (Ctrl_R_ColorUnevenness / Ctrl_G_OilDirt / Ctrl_B_Smoke).

## Body meshes
AC8's NPC aircraft bodies are static meshes (the x40a's PlaneBodyMeshComponent is a StaticMeshComponent) [V]; the
master still has GPU-skin shaders (FGPUSkinVertexFactory in its shader map), so a skinned body (the X-02S) can use it.

## Effect materials Survival reuses (no shader of its own)
Dynamic instances of these, with our textures, all have local-vertex-factory shaders, so a MaterialBillboardComponent
can draw them [V]:
- `/Game/VFX/Mission/Mission023/MI_ms23FarExp_Flare` (on M_ms09FarExp_Flare): additive flare. EmissiveMap, MaskMap,
  Emissive_Intensity, EmissiveColor. VALKA's AC7 lens flash and her portal's glow and photon ring.
- `/Game/VFX/Vehicles/Weapon/UAV/Barrier/M_VFX_UAVBarrierSpriteRefraction`: sprite refraction (a ring normal map by
  default, RefractionIntensity, BaseRefraction, EdgeBlackIntensity). Her portal's lensing.
- `/Game/VFX/Vehicles/Weapon/Impact/Materials/M_Smoke01`: lit translucent smoke (BaseTexture an 8 x 8 flipbook atlas,
  LerpColor1 / 2, BrightnessIntensity). Her portal's black event horizon.
- Not reused: Lighting/LensFlares (the sun's lens flare, screen space on a background cube).

## Open
- Whether the X-02S draws right with virtual textures [to test, 0.68+].
- Whether the billboards (flare, portal) draw in AC8 [to test, 0.68 / 0.69].
