# ZFA-44EL (the user's edited CFA-44 from Alicorn Special Raid IV): extraction and port plan (2026-11-06)

User (2026-11-06): "Alicorn Special Raid IV is my own mod and I NEED the FA44 that is within the files of the Alicorn
Special Raid as the Model inside is edited." AGENTS.md (Toolchain) records the exception: the ZFA-44's edited model,
paint, actor ex_uavs and its weapons, with the AC7 stock assets they use. Never AC7 voice lines (none are involved:
no package below imports a radio or voice asset).
Research and extraction only: nothing cooked, installed or run, no Survival code changed.

Tags: **[confirmed in data]** read from the packages, **[inferred]** reasoned from them, **[needs an in-game test]**.

Sources, read only: the user's work folder `D:\Ace Combat PAKS\unrealpak\Engine\Binaries\Win64\Alicorn_Special_Raid_IV`
(plain UE 4.18 packages) and AC7's export `E:\Ace Combat 7 Exports\Game` ("ACE7" encrypted, read through
tools/ac7_decrypt.py). UModel ran from a copy in the output folder, so nothing was written on D:.

Output (git-ignored, the build machine): `E:\ACE8 Survival Mode\build\zfa44\`

| folder | what |
|---|---|
| `mesh\` | `uavs_SM.gltf/.bin` (UModel glTF, metres = AC7 units / 100), `uavs_SM.pskx`, `uavs_SM.umodel_props.txt`, `sockets.json`, `sections.json`; `mesh\reference\` the stock meshes it was built from (fa44 skeletal, fa44_GearOff_SM, fa44_RefuelOff_SM, mrgn_SWP1_SM, w_tls_x1_SM), the stock UAV (uavs_SM_stockUAV) and its wrecks (uavs_DAM, uavs_DAM_MainBody) |
| `tex\mod\`, `tex\stock\` | every texture the materials use, PNG (the user's two, AC7's 17) |
| `materials\materials.json` | every material instance on the chains: parent, scalars, vectors, textures, static switches (read from the cooked static-parameter block) |
| `json\mod\`, `json\stock\` | UAssetGUI dumps of every package (`*.json`) and a readable property dump of each (`*.props.txt`); `json\scan_uavs_stock.tsv` = every AC7 package naming "uavs" |
| `preview\` | 512 / 1024 previews: the user's paint, the stock paint, their difference, both MREC maps |
| `raw\mod\`, `raw\stock\` | the user's packages copied, AC7's decrypted (inputs) |
| `umodel\` | UModel's raw exports; `scripts\` the readers (pkg.py, props.py, matsum.py, matchain.py, gltfinfo.py, rawimg.py, preview.ps1, assemble.py) and `extract.sh` (how it was all made) |

## 0. Units
AC7's world is about 1/10 scale (LASER_INTERCEPTOR.md 0: the F-22's mesh is 190 units long, the real one 18.9 m), so
**1 AC7 unit = about 10 cm** [inferred]. The weapons' speeds confirm the factor: each is a round km/h figure x 1/0.36
(ADMM 12222.2 = 4400 km/h, its launch 555.6 = 200 km/h, EML 111111.1 = 40000 km/h) [inferred]. AI flight tables
(`*_config`) are in km/h [inferred]. Below, distances are AC7 units with metres in brackets; AC8 centimetres = AC7 units
x 10. (VALKA.md 2 read the EML as 4000 km/h, taking units as cm; that's 10x too slow.)

## 1. What the ZFA-44EL is
In plain words: a CFA-44 Nosferatu with the Morgan's dorsal laser pod grafted on its spine, painted black / dark grey
with red-and-white fins and red roundels, flying Mihaly's evasion and attack trees on the False-Mihaly Su-47's boost
flight table, armed with an all-aspect missile salvo (AI ADMM), Mihaly's railgun (EML) and a missile-killing laser
(Laser Interceptor). In the user's mod it replaces AC7's small "uavs" drone: the Alicorn launches eight of them in DLC
mission ex03 (`alcn_uavs_L_01..04` / `R_01..04`) [confirmed in data: ex03_Global / ex_alcn names].

### 1.1 Inventory
| asset | owner | what it is | extracted to |
|---|---|---|---|
| `Blueprint/AI/Actors/Plane/ex_uavs` | user's (edits AC7's) | the actor: AIPlane_Pawn child; name "ZFA-44EL", health 120, weapons, AI trees (section 3) | json/mod/.../ex_uavs.* |
| `Vehicles/Aircraft/uavs/uavs_SM` | user's (replaces AC7's 1,244-vertex drone) | the edited static mesh (section 2) | mesh/uavs_SM.* |
| `Vehicles/Aircraft/fa44/00/fa44_00_D` | user's (replaces AC7's) | the paint: 4096 BC7 | tex/mod/fa44_00_D.png |
| `Vehicles/Aircraft/fa44/00/fa44_00xMREC` | user's (new) | MREC map: 4096 BC7, linear | tex/mod/fa44_00xMREC.png |
| `Vehicles/Aircraft/fa44/00/fa44_00_Inst` | user's (edits AC7's) | the paint instance: points at the two above + stock fa44_00_N | json/mod, materials.json |
| `Blueprint/Weapons/AI/Base/wp_admm` | user's (new; from AC7's player plwp_admm_x0) | AI ADMM | json/mod |
| `Blueprint/Weapons/AI/Base/wp_eml` | user's (edits AC7's Mihaly railgun) | EML | json/mod |
| `Blueprint/Weapons/AI/Base/wp_LaserInterceptor` | user's (edits AC7's) | anti-missile laser, beam moved onto the pod | json/mod |
| `Blueprint/Weapons/AI/Variation/wp_laser_uav_2` | user's (edits AC7's) | attack laser, beam moved the same way; **not on ex_uavs** | json/mod |
| `Blueprint/AI/Difficulty/uavs_config` | user's (edits AC7's) | flight table; **not used by the mod's ex_uavs** (section 3.2) | json/mod |
| `fa44_00_Decal_Inst` | AC7 stock | the instance on the mesh's body slots (parent: the user's fa44_00_Inst) | json/stock, materials.json |
| `fa44_00_N` | AC7 stock | normal map, 4096 BC5 | tex/stock |
| `fa44_Canopy1_Inst` + Glass_N, aircraft_CP_Glass_MREC | AC7 stock | canopy glass | json/stock, tex/stock |
| `mrgn_00_Inst` + mrgn_00_D / _MREC / _N | AC7 stock | the Morgan's paint, on the pod's fairing | json/stock, tex/stock |
| `w_tls_x1_Inst`, `w_tls_x1_Glass_Inst` + w_tls_x1_D / _MREC / _N | AC7 stock | the TLS pod's paint and lens | json/stock, tex/stock |
| aircraft_Inst, Vehicle_Inst, Basic_Diffuse_M, weapons_Inst, weapons_Glass_Inst, aircraft_Glass(_Clear)_Inst, Basic_Trans_M | AC7 stock | parents up to the masters | json/stock, materials.json |
| `uavs_DAM`, `uavs_DAM_MainBody` (+ uavs_00_Dam_Inst, uavs_DamMasked_Inst, Aircraft_Dam_*) | AC7 stock | wreck meshes: **the old drone's pieces**, not ZFA-44 shaped | mesh/reference, tex/stock |
| `uavs_FX_MapTable` | AC7 stock (`/Game/uavs_FX_MapTable`) | 2 rows: wing-tip vapour on vapor01 / vapor02 (FX_WingTipVapor_01_NPC_lit) | json/stock |
| `ex_su47_CommonBoost_config`, `Global_PilotRankModifier`, `WeaponDurabilityConfig_UAVS`, `WpnPilotRankConfig(_Missile)` | AC7 stock | flight table, rank modifiers, damage taken, weapon rank modifiers | json/stock |
| Mihai1_agt_Middle / _Short, Mihai1_evagun, Mihai1_evamis_Middle / _Short, Mihai1_evaspw, ms18_Mihai_eva, ms18Mihai_pursueTarget | AC7 stock | Mihaly's behaviour trees (Mission 18) | json/stock |
| AIPlane_Pawn, wp_plsl, plwp_admm_x0, m101_Anim, PlaneDamagedSpinParam, CUR_LaserInterceptorSwingRate | AC7 stock | the base class, a dead import, the ADMM's source, the empty skel mesh's anim, death spin, the laser's swing curve | json/stock |
| stock ex_uavs, ex_uavs_MAD_Jammer, ex_uavm, common_x02s_Mihai, ms18_x02s_Mihai, ex_su47_falseC | AC7 stock | for comparison (what the user changed, where the AI parts come from) | json/stock |

## 2. The mesh (`uavs_SM`, the user's)
- A UE 4.18 **static** mesh, 1 LOD, **26,369 vertices, 29,462 triangles, 10 sections** (section i = material slot i,
  read from the cooked section table) [confirmed in data]. Three UV channels: 0 the paint, 1 AC7's decal placement
  (body only, -3.3..4.3 / -16.4..6.2), 2 lightmap [confirmed in data].
- Size: 240.4 x 145.8 x 38.9 units (X -75.1..165.3, Y -72.9..72.9, Z -14.4..24.4) = **24.0 m long, 14.6 m span,
  3.9 m tall** at 10 cm a unit [inferred]. ExtendedBounds origin (45.05, 0, 5.0), extent (120.2, 72.9, 19.4), sphere
  120.8 [confirmed in data]. Body mass override 383.3 kg (ex_uavs) [confirmed in data].
- What it's made of (vertex positions matched against the stock meshes) [confirmed in data]:

| section | material | verts / tris | from |
|---|---|---|---|
| 0 | fa44_00_Decal_Inst | 91 / 156 | fa44 nose glass piece (stock slot aircraft_GEN_Glass_Inst, re-materialled) |
| 1 | fa44_Canopy1_Inst | 584 / 1044 | fa44 canopy |
| 2 | fa44_00_Decal_Inst | 3423 / 2681 | fa44 cockpit (stock slot fa44_00_CP_Inst; 8 of 1,620 positions differ) |
| 3 | fa44_00_Decal_Inst | 19558 / 22741 | fa44 body at rest (identical positions) |
| 4 | w_tls_x1_Inst | 1722 / 1913 | the Morgan's dorsal TLS pod (mrgn_SWP1_SM), ~10 units forward and reshaped onto the spine |
| 5 | w_tls_x1_Glass_Inst | 73 / 120 | its lens |
| 6 | mrgn_00_Inst | 567 / 433 | its fairing (Morgan paint; uses only u 0.254-0.371, v 0.877-0.997 of mrgn_00_D) |
| 7 | fa44_00_Decal_Inst | 20 / 20 | fa44_GearOff_SM glass piece (re-materialled) |
| 8 | fa44_00_Decal_Inst | 315 / 340 | fa44_GearOff_SM (closed gear doors) |
| 9 | fa44_00_Decal_Inst | 16 / 14 | fa44_RefuelOff_SM (closed refuel door) |

  So the edit = AC7's CFA-44 frozen in its rest pose (no moving surfaces), the parts AC7 keeps separate merged in (as
  tools/x02s merged the X-02S's), plus the Morgan's TLS pod; all non-glass slots on the body paint.
- UVs: the body is 0-1 on AC7's own CFA-44 layout (u 0.001-0.883, v 0.001-0.873) [confirmed in data]. Sections 0 and 7
  sample the paint at **negative U** (-0.97..-0.78): AC7's `MirrorSettings` switch is on in both instances; in AC8 a
  wrap sampler would read the wrong spot, so fold them (|u|) when converting [inferred]. Canopy and lens glass are also
  negative U (glass materials, no paint).
- Sockets (AC7 units, mesh space; AC8 cm = x10) [confirmed in data]:

| socket | location | notes |
|---|---|---|
| gun | (100.78, 8.22, 4.08) | moved from stock fa44's gun (88.6, -11.13, 2.0); the EML's likely muzzle [inferred] |
| ws1 (tag sp11) | (32.77, -0.09, 17.25) | top, at the TLS pod's lens |
| ws2 / ws3 | (-10.39, +46.37 / -46.08, -4.71) | under the wings, at the stock missile-bay bones Missile_Cover_03 / _06; the ADMM's launch points [inferred] |
| vapor01 / vapor02 | (-26.39, -72.45 / +71.60, -2.88) | wing tips, used by uavs_FX_MapTable |

  Not on the edited mesh, needed for the port (from the stock fa44 skeleton, mesh/sockets.json): **burner_01 / _02 at
  (-51.0, -/+12.35, -2.70)** (L / R_Nozzle_01 + (0, -6.31, -2.54) at rest), burner_03 / _04 (-29.0, -/+12.35, -2.7),
  cam_nose (165.25, 0, -2.16), GUNHIT01-20, VFX_Dmg_*. The Laser Interceptor's beam starts at **(30.92, 0, 16.86)**,
  the pod's lens [confirmed in data]. The user's mesh has no burner sockets and its FX table only vapour, so in AC7
  the ZFA-44EL flies with no afterburner flames [confirmed in data].
- Collision: a complex BodySetup (BlockAll, 0.95 MB) that a component added in AC8 doesn't need; hits come from the
  host's spheres. ex_uavs adds a hit Sphere of radius 68 (6.8 m), profile EnemyPawn [confirmed in data].
- Wrecks: ex_uavs keeps the old drone's uavs_DAM / uavs_DAM_MainBody (0.7-1.0 m drone pieces), so in AC7 the ZFA-44
  breaks into drone parts; unusable here, and AC8 doesn't draw wreck meshes on a live plane anyway (hard rule 41)
  [confirmed in data / hard rule].

## 3. The actor (`ex_uavs`, the user's) and its AI
### 3.1 What the user changed against AC7's ex_uavs [confirmed in data]
| property | AC7's drone | ZFA-44EL |
|---|---|---|
| ObjNameID | ContainerAircraft_Name_uavs | `ZFA-44EL` (a literal, not a text key) |
| MaxHealth / KillBountyScore | 80 / 800 | **120 / 1400** |
| bCanActivateFlares | false | **true** |
| AIParamDataTable | uavs_config | **ex_su47_CommonBoost_config** (the False Mihaly Su-47's, DLC ex02) |
| FCS Weapon1 / 2 / 3 | wp_gun / wp_msl_uav / - | **wp_admm / wp_eml / wp_LaserInterceptor** |
| Evade / EvadeMissileNear / Far / Gun / Special | UAV_eva / _evamis_Short / _Middle / _evaGun / _evamis_Middle | **ms18_Mihai_eva / Mihai1_evamis_Short / Mihai1_evamis_Middle / Mihai1_evagun / Mihai1_evaspw** |
| Provoke / Near / Mid / Far | UAV_agt / _Short / _Middle / _Middle | **ms18_Mihai_eva** / Mihai1_agt_Short / Mihai1_agt_Middle / Mihai1_agt_Middle |
| PursueTargetBT | (base) | **ms18Mihai_pursueTarget** |
| EscapeFromPursuerBT | UAV_escape | not set: the base's Fig_escape |
| NPCPassingSoundSwitch row | Uav_Normal | Uav_Small |

Unchanged: LookAheadTimeSec 4, BattleSituationRelativeLowAltitude 1000 (100 m), bDamagedRotate, the AIUAV dock
component (UndockOffsetZMax -200, DockRadiusMeters 75, DockDuration 2 s, DockFlipDelay 1.6 s: the Alicorn launch),
move sound NPC_UAV_NORMAL, WeaponDurabilityConfig_UAVS. These are the Mission 18 X-02S's trees (common_x02s_Mihai's
Mihai1_* plus ms18_x02s_Mihai's eva / pursue), with Provoke pointing at the eva tree instead of ms18_Mihai_agt.
`wp_plsl` is imported but no property uses it; `wp_laser_uav_2`, `plwp_admm_x0` and `Uav_Small`'s neighbours in the
name map are leftovers of edits [confirmed in data]. AC7's child ex_uavs_MAD_Jammer overrides only an empty FCS
subobject, so in the mod it likely flies the same weapons and look [inferred].

### 3.2 Flight [confirmed in data]
`ex_su47_CommonBoost_config` (AIPlaneConfig, rows = pilot rank 1-5), km/h and deg/s:
| rank | pitch | roll | yaw | normal | max | min | turn | accel | decel |
|---|---|---|---|---|---|---|---|---|---|
| 1-4 | 56 | 280 | 4 | 1320 | 5280 | 180 | 1280 | 310 | 1220 |
| 5 | 46 | 325 | 4 | 1800 | 6000 | 300 | 520 | 400 | 360 |

`Global_PilotRankModifier` scales pitch / roll / yaw by rank: 0.85 / 0.93 / 1 (1), 1 (2), 1.15 / 1.02 / 1.2 (3),
1.3 / 1.03 / 1.3 (4), 1.5 / 1.05 / 1.5 (5). The rank itself comes from the mission's spawn, not the actor.
The user's edited `uavs_config` (ranks 1-4: pitch 54, roll 172, yaw 10, 700 / 2600 / 400 km/h, turn 630, accel 180,
decel 260; rank 5: 49 / 160 / 6, 700 / 2600 / 490, 590, 160 / 230; AC7's: 45 / 120 / 4, 1400 / 2800 / 650, 800) is
referenced by nothing in the mod (only AC7's own ex_uavs, which the mod replaces) [confirmed in data: name scans].
`WeaponDurabilityConfig_UAVS` (damage taken per weapon category, %): 200 / 100 / 200 / 100 x4 / 50 / 100 x3 / 20 / 100
/ 147 / 100 (categories 01-15) [confirmed in data; which weapon is which category not read].

## 4. The paint
### 4.1 AC7 chain [confirmed in data]
`fa44_00_Decal_Inst` (stock: Wet_Max 0.25, decal UV params, switches ShowWingBottomDecal, use_decal, use_NoseDecal,
Use_Formation_Emissive, Wet Surface, MirrorSettings) -> **`fa44_00_Inst` (the user's**: Albedo_map fa44_00_D,
MREC_map fa44_00xMREC, Normal_map stock fa44_00_N; switches Enable_Damage, Mult_Albedo and a new MirrorSettings; the
decal UV scalars copied in; AC7's Emissive_Brightness 20 / Emissive_Color dropped, aircraft_Inst has the same) ->
`aircraft_Inst` (CloudSand, wet, emissive 20, formation light cyan) -> `Vehicle_Inst` -> master
`/Game/Materials/Core/Basic_Diffuse_M` (Albedo_map, MREC_map, Normal_map, decals, turbine, wet, AO switches).
Changing fa44_00_Inst also repaints AC7's player CFA-44 skin 00 in the user's mod [inferred].

### 4.2 The textures
| texture | size / format | notes |
|---|---|---|
| fa44_00_D (user's) | 4096 BC7 (TC_BC7, sRGB, LODGroup Character), **1 mip**, inline 16 MB | RGB the paint; A 254-255 (unused). Black / dark grey with red-white fins, emblems, red roundels: 43 % of pixels differ from AC7's grey camo (preview/) |
| fa44_00xMREC (user's) | 4096 BC7, linear (CharacterSpecular), 1 mip | R mean 81 (AC7's 101), G 106 (131), B 0 but the lights, A ~0 |
| fa44_00_N (stock) | 4096 BC5 TC_Normalmap | ordinary tangent-space |
| mrgn_00_D / _MREC / _N, w_tls_x1_D / _MREC / _N | 4096 / 2048 DXT1, DXT5, BC5 | stock |

Both of the user's textures still name `/Game/Skin3/00/...` in their name maps: authored in a skin project and moved
[confirmed in data]. MREC channels: R metallic, G roughness, B emissive, A a mask (the master's parameters Metallic /
Roughness / Emissive and AC7's default MREC (24, 99, 0) = non-metal, mid-rough, no glow) [inferred].

### 4.3 Making it draw in AC8 (hard rule 44, FALKEN_MATERIALS.md)
No virtual textures (hard rule 44). The route that works: material instances parented on the x40a's gear instance
`/Game/Vehicles/Aircraft/PP/PP0016_x40a/Materials/Common/MI_PP0016_x40a_Gear` (-> MP_Gear -> M_Live_Vehicle_Base:
ordinary samplers, GPU-skin shaders), no static switch overridden, stubs of that chain in ue/Live never packed. It drew
SOLG T0b's skeletal mesh textured (SOLG.md 8) and is VALKA's paint 16 [confirmed in game per those notes].
- **Body** (sections 0, 2, 3, 7, 8, 9): Basecolor = the user's fa44_00_D RGB, re-encoded ordinary DXT1 sRGB with full
  mips (the source has 1 mip: it would shimmer) [inferred]; Normalmap = stock fa44_00_N as BC5 TC_Normalmap, with
  `/Engine/EngineMaterials/DefaultNormal` (the Falken's choice) as the fallback variant [needs an in-game test];
  Livemap = the Falken's constant 4x4 (R 0, G 191, B 255) first, then a variant built from fa44_00xMREC (R <- R metallic,
  G <- G roughness, B 255) [inferred channels, needs an in-game test]; Ctrl_All_Emissive, Turbine_speed,
  NormalIntencity, DNormal_Strength, DamegedNormal_Intencity, PlayerPlane_Damage 0, Detail_Normal /
  Blend_Dameged_Normalmap T_FlatNormal (the Falken's set).
- **TLS pod** (4): the same parent with w_tls_x1_D / _N (2048). **Fairing** (6): mrgn_00_D cropped to its 0.117 x 0.12
  UV box (about 512 px) with its UVs remapped, or on the body texture's nearest grey [inferred].
- **Canopy and lens** (1, 5): Survival's canopy material as on VALKA (M_NPC_Canopy). AC7's canopy is gold-tinted
  (Color 0.15 / 0.084 / 0.094, Specular_Tint 0.745 / 0.579 / 0.292, StaticOpacity 0.6) [confirmed in data].
- AC7's decals (UV 1, use_*_decal) aren't carried: the user's insignia are painted into fa44_00_D [confirmed in data].

## 5. Weapons [confirmed in data unless tagged]
Each AI weapon's FCS* values are scaled by the pilot rank (WpnPilotRankConfig, rank 4: angle x0.87, activation time
x0.8, rest x0.8-0.85, activation distance x1.1).

**ADMM** (`wp_admm`, new; native VLSMissile; made from the player's plwp_admm_x0): 12 missiles (MaxLoadedCount 12,
PotentialTargets 12) fired all in one shot 0.03 s apart, up to 2 targets locked (MultipleLockOnMaxNum 2), damage 80,
life 11 s, reload 22 s; launch 200 km/h, max 4400 km/h, +350 km/h/s; homing from 1.0 s, homing angle 85 deg, turn 70
(player's: 70 / 55 / 0.75 s), omnidirectional 115 for 1.1 s; lock-on 48000 (4.8 km) in 120 deg; spawn cone 10 deg;
AI fire control: within 25000 (2.5 km) and 100 deg, 0.5 s to fire, volley 4 s at 1 s, rest 10 s; sounds
SPWP_ATA_8AAM_SHOOT / SPWP_OTH_DETACH / Missile_Fly, FX FX_ADMM_Muzzleflash_01, mesh w_mmsl_x0_SM.

**EML** (`wp_eml`, native EMLBullet_Mihai, Mihaly's railgun; user's edits in brackets against AC7's): 111111 units/s
(40000 km/h), ray radius 100 (10 m) [80], life 8 s [5], trail 8 s [4]; FCS angle 20 deg [10], 0.6 s to fire, volley
2.5 s at 1.5 s [2.5] (so two shots a volley [inferred]), rest 10 s, foresight 0.3, from 180000 (18 km) down to 10
units [1000 = 100 m]; damage is the native class default (not in data); FX FX_EML_Muzzleflash02, FX_EML_Projectile03,
hits FX_MachineGunHit_*; sounds OBJ_M18_MIHAI_SHOT, _BULLET (loop) / _BULLET_Stop, _BULLET_PASS; camera shake
EMLBulletDamage.

**Laser Interceptor** (`wp_LaserInterceptor`): AC7's values unchanged, only both beam particles moved from (-30, 0, 0)
to the pod's lens (30.92, 0, 16.86): ray 12400 (1.24 km), radius 150, damage 10, life 6 s, FCS 180 deg, 0.1 s, volley
6 s, interval 6 s, rest 8 s, foresight 0.09, within 12000 (1.2 km), swing curve CUR_LaserInterceptorSwingRate (0 -> 1
over 1 s), beam FX_UAV_TLS_Muzzleflash01 / 02. What it does and AC8's options: tools/re/LASER_INTERCEPTOR.md (not
repeated here). The ZFA-44 exception covers "its weapons, with the AC7 stock assets they use", which includes this
weapon's AC7 assets (LASER_INTERCEPTOR.md said a second exception would be needed) [inferred from AGENTS.md's text].

**Attack laser** (`wp_laser_uav_2`, not fitted): AC7's TLS-type laser (WID_tls: 20400 / 2.04 km, radius 100, 0.33 s
ticks, warm-up 0.95 s, damage 10, FCS 45 deg, 40000 / 4 km, 6 s on / 8 s rest), its beam moved to the same lens point
(from (100, 0, 0)). In AC7 it's common_uavw's and common_adf11f's weapon; the edit moves their beams too [inferred].

## 6. Port plan
### 6.1 AC8 mapping
| ZFA-44 part | AC8 route | status |
|---|---|---|
| body | **a skeletal mesh of ours** added to an AI plane (AddComponentByClass, hard rule 46), host meshes hidden, as VALKA's X-02S and SOLG T0b. Not a static mesh: SOLG T0's StaticMeshComponent of ours crashed AC8's renderer, the skeletal T0b drew (SOLG.md 8) | route [confirmed in game]; this mesh [needs an in-game test] |
| cook | ue/Live, UE 5.4, **versioned** (hard rule 42), ordinary textures (hard rule 44), retoc to-zen, pad.py (hard rule 8); its own container, e.g. `SurvivalMode_ZFA44_P` | as tools/x02s |
| host | **A (first): VALKA's x40a unit** (Mission 26's EI_Unit_01_Air0 with its parts, row sv_ace_valka_x40a_l): the railgun is already there and proven. **B (a wing of 2-4):** a fast AC8 fighter ace row per plane (Survival's ace rows; ADFX-02's model row SV_Model_adfx exists) with the EML as a part unit moved onto its gun socket every 0.5 s (SOLG T0b held parts at 0.0 m drift) | A [confirmed in game for VALKA]; B [needs an in-game test] |
| EML | the x40a's RailGun part (LiveFCSModule_LauncherTripleRailCannon), single-shot at run time as VALKA's, fired by LiveFireOneShotWeapon WN_WEAPON_1, minimap / HUD alert per hard rule 45; Mihaly's OBJ_M18_MIHAI_* sounds as VALKA ships them; cadence from AC7: within 18 km and 20 deg, 2 shots 1.5 s apart, then 10 s | [confirmed in game for VALKA] |
| ADMM | AC8's own 8AAM (no AC7 asset): Online Mode's NPC fire control **NFID_8AAM_40** (on OP1037_su30sm_L001_41; BP_FCS_8AAM_r0_00 -> BP_wp_8aam; campaign NPC BP_wp_8aam_a0 / _r0 under /Game/Blueprints/Weapons/MSL/NPC/8aam) in a free slot of the host's row (hard rule 38's Online Mode rows), fired as RE_SV_SpecFire does (hard rule 40), within 2.5 km / 100 deg, every ~14 s; AC8's 8AAM Wwise events for sound. Fallback: Survival's existing specials (4AAM-class, sv_spweapons.lua) | the row naming NFID_8AAM_40 and the 8AAM packages [confirmed in data]; which package that fire-control row points at [inferred]; firing [needs an in-game test] |
| Laser Interceptor | LASER_INTERCEPTOR.md 6: AC8's BP_SwingTLS_ForMSL arm (route 2) or the Lua emulation (route 3), beam from the lens point; keep it missiles-only | [needs an in-game test] |
| flight | the host row's speed / turn tweaks (DT_NPC tweak columns such as SpeedNormalD, PitchSpeedC, as Online Mode's rows carry) toward the boost table; 5280 km/h max is extreme, cap it [inferred] | [needs an in-game test] |
| behaviour | Survival's ace sets (P9 personalities, Duelist role), never NLID_0400_CP (hard rule 22), built at level load (hard rule 20); Mihaly's cobra / kulbit shots as LiveAIRequestUniqueAction RE_SV_AceTurn / AceKulbit (hard rule 37) | [confirmed in game] for the unique actions |
| name / health | target box "ZFA-44EL" through a Survival name key (as VOID WATCHER's); health: AC7 has it at half Mihaly's X-02S (120 vs 240) and VALKA is 2000, so ~1000 log units a plane, the ace wing's scale [inferred]; hit spheres cut to ~6.8 m (VALKA's hit_radius_m) | |
| effects | burner_01 / _02 leaf bones at the nozzles (section 2), vapor01 / 02 at the tips, as VALKA's skeleton carries AC8's socket names | [needs an in-game test] |
| death | hide our component (or swap to Aircraft_Dam materials, hard rule 41); the host's explosion plays | |
| co-op | as VALKA's: the host announces the reveal, each joiner dresses its own copy (COOP.valkaTick pattern) | pattern [needs an in-game test] for this model |

### 6.2 Steps
1. `tools/zfa44/prepare.py` (from tools/x02s/prepare.py; reads build/zfa44/mesh/uavs_SM.gltf, writes build/zfa44/out):
   a skinned glTF with one root and a `Body` bone holding every vertex, leaf bones for the sockets (burner_01 / _02,
   vapor01 / 02, gun, ws1-3, laser, cam_nose), scaled x10 (or by a `model_length_m` as VALKA's), negative body U folded,
   sections merged into 4 slots (body, canopy+lens, pod, fairing); the textures: T_ZFA44_C (fa44_00_D RGB), T_ZFA44_N
   (fa44_00_N), T_ZFA44_LM (constant and the MREC-derived one), T_ZFA44_Pod_C / _N, the fairing crop.
2. `tools/zfa44/ue_import.py` + `build.sh` (from tools/x02s): SK_ZFA44 (+ skeleton, physics asset), MI_ZFA44_* on the
   gear stub, textures VIRTUAL False; cook versioned; retoc only /Game/Mods/SurvivalMode/ZFA44; pad.py. Check before
   packing (FALKEN_MATERIALS.md 5.2.vi): no shader map of ours, MI imports MI_PP0016_x40a_Gear, no texture virtual.
3. **T0** (below).
4. World data / rows (tools/build_survival.py, survival_events.py): the host unit (A: VALKA's x40a unit copied as
   SV_Unit_ZFA44; B: an ace fighter unit per plane plus railgun part units), the 8AAM fire-control row copied from
   Online Mode's table, the ZFA-44 name key.
5. Lua (`Scripts/sv_zfa44.lua`, an SPC kind with VALKA's dress / paint / partsPlace / hit-sphere code shared): spawn,
   dress, weapon cadence (section 5's AC7 numbers), HUD name, co-op relay, death clean-up (SPC.cleanUp).
6. T1: the round (from round N, alone or as the ALICORN's deck launch, which is how the user's mod uses them).

### 6.3 Smallest first in-game test (T0)
Cook only SK_ZFA44 + its body paint into SurvivalMode_ZFA44_P. A TEST ONLY key (stripped from every zip) dresses the
nearest live enemy plane (or VALKA, Ctrl+8) as the ZFA-44: AddComponentByClass(SkeletalMeshComponent),
SetSkeletalMeshAsset(SK_ZFA44), its own meshes hidden, a dynamic instance of MI_PP0016_x40a_Gear per body slot with
T_ZFA44_C (VALKA's paint 16 path). A crumb before each step (SOLG T0's way). Look at: no crash; textured (not black,
not white); right way round and size (24 m, a third longer than an F/A-18E); the pod on the spine; canopy glass; whether
the host's afterburner moves to burner_01 / _02. Log: `zfa44: T0 ...` lines with the slots painted and bones found.

### 6.4 Risks
- The paint: the BC7 single-mip source, the MREC channel guess, AC7's normal map in AC8's gear sampler, the mirrored
  pieces [needs an in-game test]. Every route but the gear parent is closed (hard rule 44).
- Flight: the host's flight model rules (VALKA kept the x40a's); the boost table's 5280 km/h may break the AI or the
  chase (hard rule 54's fast-plane handover issue is for paths; Survival chases by area) [needs an in-game test].
- The Laser Interceptor: AC8's leftover class may not run; the AC8-native arms need bones the host lacks
  (LASER_INTERCEPTOR.md 6) [needs an in-game test].
- The ADMM as an Online Mode 8AAM row on a campaign host: the row must be added at the main menu and the host must
  keep a free slot; 12-missile salvos against the attackers cap (CFG.attackers) [needs an in-game test].
- Several ZFA-44s each with an x40a host and parts is heavy (VALKA is one plane); route B needs proving first.
- Size: about 35-45 MB of textures at 4096 (2048 normals halve it) [inferred].
- Rules: only the user's ZFA-44 assets and the AC7 stock assets they use; no voice lines; nothing of it in this repo
  (outputs stay in build/, git-ignored).

## 7. Not extracted / not determined
- The EML's damage (native EMLBullet_Mihai default; AC7's code is encrypted) and the weapon-category numbering of
  WeaponDurabilityConfig_UAVS.
- How AC7's MirrorSettings and MREC alpha are used inside Basic_Diffuse_M (expressions are stripped from cooked
  materials): section 4's readings are inferred from names and values.
- AC7's Cascade effects (FX_EML_*, FX_UAV_TLS_*, FX_ADMM_Muzzleflash_01) weren't exported: UModel doesn't export
  particle systems, and AC8 can't load Cascade from AC7 anyway; the plan uses AC8's own effects.
- The Mihaly behaviour trees were dumped (json/stock/Blueprint/AI/Maneuver) but not decoded; AC8 can't run them, so
  only their roles are mapped (section 6.1).
- The damage meshes are exported but are the old drone's; no ZFA-44 wreck exists in the mod.
