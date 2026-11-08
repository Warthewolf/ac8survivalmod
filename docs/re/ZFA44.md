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
- **TLS pod** (4): the same parent with w_tls_x1_D / _N (2048), and (2026-11-07, the user: "make sure that the textures
  for the TLS on the ZFA-44 were ported over from ACE7 too") a Livemap from w_tls_x1_MREC as the body's (paint 4). **Fairing** (6): mrgn_00_D cropped to its 0.117 x 0.12
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

## 8. T0 build (2026-11-06, branch feature/zfa44, worktree `E:\ACE8 SM zfa44`; built, not yet run in game)
Test T0 of section 6.3: the ZFA-44 cooked for AC8 and put on a live enemy aircraft by a test key. Nothing of the mod or
AC7 is committed: only `tools/zfa44/` (the scripts) and `Scripts/sv_zfa44.lua`.

### 8.1 What was made
`sh tools/zfa44/build.sh` (UE 5.4 at `E:/UE_5.4`, this tree's own `ue/Live` project as tools/solg used it, `py -3.12`
with numpy and Pillow). Its outputs are git-ignored, in `build/zfa44/` (the main tree's, through the junction): `prep/`
(SK_ZFA44.gltf / .bin, the textures as PNG, layout.json), `ue_import.log`, `ue_import_stdout.log`, `cook.log`,
`cook_check.log`, `build.log`, `stage/`, and **`out/SurvivalMode_ZFA44_P.utoc / .ucas / .pak`** (29.5 MB, 14 packages,
22 chunks, padded: 468 blocks checked, hard rule 8). The editor's first run wrote AndroidFileServer settings into the
tracked `ue/Live/Config/DefaultEngine.ini`: reverted, not committed.

| step | what |
|---|---|
| `prepare.py` | UModel's glTF of uavs_SM (metres = units / 100, UE's (X, Z, Y)) x10: **24.04 m long, 14.58 m span, 3.89 m tall**. One skinned mesh: bone Root -> Body (every vertex) -> 58 leaf bones. 10 sections on 4 slots: **0 Body** (sections 0, 2, 3, 7, 8, 9), **1 Canopy** (1 and the pod's lens 5), **2 Pod** (4), **3 Fairing** (6). Sections 0 and 7: 91 + 20 UVs folded (u -> -u), their tangents turned. The fairing's UVs onto a 512 px crop of mrgn_00_D / _N (u 0.25-0.375, v 0.875-1.0). COLOR_0 white, TEXCOORD_1 = TEXCOORD_0 |
| bones | the edited mesh's gun / TEMP_muzzleFlash (1007.8, 82.2, 40.8) cm, ws1-3, vapor01 (-263.9, -724.5, -28.8) / vapor02 (-263.9, 716.0, -28.8); **burner_01 / _02 (-510.0, -/+123.5, -27.0)**, X axis aft (yaw 180, as the stock burner_03 / _04); burner_03 / _04; laser (309.2, 0, 168.6) (the TLS lens); the stock body sockets cam_nose (1652.5, 0, -21.6), cam_pilot, cam_tailL / R, cam_thrusters, pitchup_body_01 / 02, pitchup_frtFlap_01 / 02, VFX_Dmg_Body / WingL / WingR / Engine, GUNHIT01-20; and VALKA's x40a aliases core01 / cone01 / fakeLight01 / SOC_EF_Burner_01 (= burner_01), core02 / cone02 / fakeLight02 / SOC_EF_Burner_02 / SOC_R_EF_Burner (= burner_02), ShoulderVaporL / R, WingOverVaporL / R. UE's reference pose matches prepare.py's places to 0.00 cm (ue_import.log) |
| textures (ordinary, hard rule 44) | **T_ZFA44_C** 4096 DXT1 sRGB (the user's fa44_00_D, alpha dropped); **T_ZFA44_N** 2048 BC5 (stock fa44_00_N, capped at 2048); **T_ZFA44_LM** 4 x 4 B8G8R8A8 (0 / 191 / 255: the Falken's constant; no mips, never streamed); **T_ZFA44_LM_MREC** 2048 DXT1 linear (the user's fa44_00xMREC: R metallic, G roughness, B 255); **T_ZFA44_Pod_C / _N** 2048 DXT1 / BC5 (w_tls_x1); **T_ZFA44_Pod_LM_MREC** 2048 DXT1 linear (w_tls_x1_MREC: R metallic, G roughness, B 255; 2026-11-07); **T_ZFA44_Fair_C / _N** 512 DXT1 / BC5 (the mrgn_00 crop); **T_ZFA44_Fair_LM_MREC** 512 DXT1 linear (mrgn_00_MREC, the same crop) |
| `ue_import.py` | **MI_ZFA44_Body / _Pod / _Fairing**: instances of `MI_PP0016_x40a_Gear` (FALKEN_MATERIALS.md's route), no static parameter; Basecolor / Normalmap / Livemap (T_ZFA44_LM) ours, Detail_Normal and Blend_Dameged_Normalmap `/Engine/EngineMaterials/DefaultNormal`, Ctrl_All_Emissive, Turbine_speed, DNormal_Strength, DamegedNormal_Intencity, PlayerPlane_Damage 0, NormalIntencity left at the parent's (ours is a real normal map). Stubs, never packed: `MP_Gear` (a Material with those parameters, normal samplers for the normals), `MI_PP0016_x40a_Gear` (an instance of it), `M_NPC_Canopy`. **SK_ZFA44** (+ SKEL_ZFA44, PA_ZFA44, the importer's), slots as above, the canopy on AC8's `M_NPC_Canopy` (as VALKA's). Bounds origin (450.5, 0, 50.0) cm, extent (1202, 729, 194), sphere 1419 |
| cook | Windows, **versioned** (hard rule 42): every package UE4 522 / UE5 1012; `Success - 0 error(s), 0 warning(s)`. `cook_check.log`: every texture `virtual False`, the three instances "neither a texture nor a material with a shader map" and importing only MI_PP0016_x40a_Gear, our textures and DefaultNormal; SK_ZFA44 imports MI_ZFA44_* and M_NPC_Canopy by path (the game's own) |
| container | `retoc to-zen` of `/Game/Mods/SurvivalMode/ZFA44` only, `tools/x02s/pad.py` |

### 8.2 Packaging (the user's dev builds only)
- `ZFA=1 sh tools/build_all.sh` stages the container into `build/install/SurvivalMode` (without ZFA=1 it isn't staged).
- `ZFA=1 sh tools/package_dev.sh <name>` keeps it (from build/install, else from build/zfa44/out); without ZFA=1 it's
  taken out. E.g. `ZFA=1 VALKA=1 sh tools/package_dev.sh zfa44t0` after a build_all, for the user's VALKA install.
- `tools/package_release.sh` always takes it out and cuts `Scripts/sv_zfa44.lua` to its first line (a comment: main.lua
  still loads the part), TESTER zips included. The friends' zips never carry the ZFA-44.

### 8.3 The key (`Scripts/sv_zfa44.lua`, test code only)
**Ctrl+9** in a run (free since VALKA's paint cycle went; `Key.NINE` is in strip_test_only.py's leftover list, so a
release with it left fails). Bound with sv_main.lua's test keys (a clash logs `test: Ctrl+9 is bound twice`; a press
makes the run unranked); the part is in MODULES before sv_main and is one TEST ONLY block.
- First press: **VALKA's x40a** when her round is up (Ctrl+8 forces it), else **the nearest live enemy aircraft** (the
  core's `planes`; not the Ladons, the Alicorn, co-op stand-ins, VALKA's opener railgun or the SOLG). It's dressed as
  SPC.V.model dresses VALKA: a SkeletalMeshComponent added (collision off, `bComponentUseFixedSkelBounds` so it culls
  by the mesh's own bounds), SK_ZFA44 (loaded the hard-rule-9 way) on it, placed on the host's PlaneBody* mesh, painted,
  every other mesh of the host hidden (again every 2 s). On VALKA her X-02S is hidden and her state points at ours while
  it's on (her model tick keeps ours shown, no sweep on it).
- Second press: undone (the component destroyed, the host's meshes shown again; VALKA gets her X-02S back).
- **Each dressing takes the next paint variant**: 1 COOKED (MI_ZFA44_* as built), 2 GEAR, ITS NORMALS (run-time
  instances of the game's MI_PP0016_x40a_Gear with our textures: VALKA's paint 15 / SOLG T0b's way), 3 GEAR, FLAT NORMAL
  (DefaultNormal, NormalIntencity 0: the Falken's, VALKA's 16), 4 GEAR, MREC LIVEMAP, CANOPY TINTED (T_ZFA44_LM_MREC, the
  canopy a dark tinted gear instance instead of M_NPC_Canopy). The HUD says which (`TEST: ZFA-44 T0`, `PAINT n: ...`).
- Every step is a crash breadcrumb first (`zfa44: T0 loading SK_ZFA44`, `... adding a SkeletalMeshComponent to <host>`,
  `... setting SK_ZFA44 on it`, `... placing it`, `... painting it: <variant>`, `... hiding the host's meshes`, `... dressed`,
  `... undoing on <host>` in AC8SurvivalMode_crumbs.log).

### 8.4 Log lines (AC8SurvivalMode_lua.log)
- `zfa44: T0: <host> (<VALKA's x40a | the nearest live enemy aircraft, N km off, <unit>>) dressed as the ZFA-44: a
  SkeletalMeshComponent added (collision off, fixed bounds on), <mesh path> on it, placed on PlaneBody... (its rotation
  against the actor p / y / r deg; ...); paint n <variant>: <what it set>; N of its meshes hidden (<names>)`
- `zfa44: T0: 4 slots: 0 Body: MI_ZFA44_Body (parent /Game/Vehicles/Aircraft/PP/PP0016_x40a/.../MI_PP0016_x40a_Gear...);
  1 Canopy: M_NPC_Canopy (...); 2 Pod: ...; 3 Fairing: ...` (paint 1: the parent must be the game's gear instance, not
  "none"; paints 2-4: MaterialInstanceDynamic on it), again at +2 s
- `zfa44: T0 at once / +2 s / +10 s / +30 s / at its death: on <host> at N km/h, the ZFA-44 visible, sphere 14.2 m, box
  24.0 x 14.6 x 3.9 m (the host's body ... sphere / box); nose (f, r, u) m, left wing tip (...) m`
- `zfa44: T0 ...: burner_01 (f, r, u) m vs the host's <burner_01 | SOC_EF_Burner_01 | core01> (...) m on <its mesh>: N m
  apart; burner_02 ...; the host's nozzle sockets <names | none found>; its effects <Niagara / particle component>@<socket>
  (f, r, u) m, ...` (metres in the host's frame: forward, right, up; where the host's flames really are)
- `zfa44: T0: N of <host>'s meshes came back on and were hidden again (+N s)`, `zfa44: T0: <host> is down: its ZFA-44
  left on it ...`, `zfa44: T0: <host> is gone N s after it was dressed`, `zfa44: T0: undone on <host> (Ctrl+9 again)
  after N s: the ZFA-44 destroyed, N of its meshes shown again`
- Failures: `zfa44: T0: /Game/Mods/SurvivalMode/ZFA44/Model/SK_ZFA44 not loaded (...): is SurvivalMode_ZFA44_P installed`
  (HUD `TEST: ZFA-44 NOT INSTALLED`), `zfa44: T0: Ctrl+9: no live enemy aircraft to dress`, `zfa44: T0: AddComponentByClass
  ...`, `zfa44: T0 tick error ...`, `zfa44: T0: Ctrl+9 error ...`.

### 8.5 What T0 should show
1. No crash on Ctrl+9 (else the crumbs' last `zfa44: T0 ...` step says where: SOLG T0's static mesh crashed the
   renderer, a skeletal one has drawn twice).
2. Painted, not black or white: the user's black / dark grey with red-and-white fins and red roundels. Paint 1 tests the
   cooked instances (never tried before: the stub-at-an-instance's-path route, FALKEN_MATERIALS.md 5.2.ii); if it's
   wrong, Ctrl+9 twice moves to the next variant on the same or the next nearest plane.
3. The right way round and size: nose ahead, 24 m long, a third longer than an F/A-18E (18.3 m); the TLS pod on the
   spine with the Morgan's grey fairing; canopy glass.
4. The afterburner: the host's flames stay at the host's nozzles (they hang on its own mesh's sockets, not on ours);
   the `burner_01 ... N m apart` and effects lines measure how far that is from the ZFA-44's nozzles (the next step
   moves our component or the effects).
5. Undo: the host looks as before. VALKA (Ctrl+8, then Ctrl+9 when she's up): the ZFA-44 on her, then her X-02S back.

### 8.6 Risks for the look
- The cooked instances' parent: our MI_ZFA44_* import `MI_PP0016_x40a_Gear` by path from a stub instance of a stub
  material. If the game doesn't resolve it (the slots line shows parent "none") the mesh draws with the default
  material; paints 2-4 build the same at run time from the game's own instance (proven by VALKA 15 / 16, SOLG T0b).
- The canopy: AC8's `M_NPC_Canopy` (an instance, 779 bytes) on a skinned mesh: whether its shaders cover the GPU-skin
  vertex factory isn't known (VALKA's canopy used it, never checked); paint 4 replaces it with a tinted gear instance.
- The normal map: AC7's fa44_00_N (BC5) in the gear's normal sampler, with the folded pieces' tangents turned: bumps
  could read inverted (paint 3 is flat). The MREC Livemap's channels (R metal, G roughness, B occlusion) are inferred
  (paint 4).
- Placement: on the host's body mesh's pivot; AC7's mesh origin is 4.5 m behind its middle (X -75..165 units), so the
  ZFA-44 may sit forward of the host's centre and its spheres (hits come from the host's own spheres). ZFA.C.yaw /
  offset_cm / scale in sv_zfa44.lua move it (no rebuild).
- The host's afterburner, vapour and damage effects stay on its own (hidden) mesh's sockets, so they won't line up with
  the ZFA-44's nozzles and wing tips (item 4 measures it).
- No wreck: the ZFA-44 stays whole on a shot-down host (hard rule 41: the host's own wreck meshes don't draw while it's
  alive); its fall shows the ZFA-44 falling.
- Mipmaps are generated from the source (the user's paint had 1 mip), 4096 colour; streaming from our container as the
  Falken's cockpit and VALKA's textures do.

## 9. The production dressing (2026-11-06, branch feature/zfa44; not yet run in game)
`Scripts/sv_zfa44.lua` now has the dressing outside its test block, for the escort's carriers (tools/re/ESCORT.md):
`ZFA.dress(plane, { paint = k, label = text, hide_s = s })` (true and what it did, or false and why; each plane once, by
its address), `ZFA.undress(plane)`, `ZFA.prodTick()` (from sv_escort.lua's tick: at most two dressed planes a tick get the
host's meshes hidden again every hide_s; a gone one dropped), `ZFA.build` / `ZFA.strip` (the component, mesh, place and
paint; shared with T0). The carriers' flights are dressed with CFG.allies.carrier.zfa.paint, default **3, GEAR, FLAT
NORMAL** (the Falken's exactly, VALKA's paint 16: the only variant here proven to draw; T0 hasn't been run, so 1 COOKED
is untried). Without SK_ZFA44 nothing is dressed (`zfa44: NOT dressed: ... the ZFA-44s fly as their host airframe`, once;
tried again after missing_again_s). T0 (Ctrl+9, ZFA.press / ZFA.t0Dress / ZFA.tick) is unchanged and stays in the test block.
Packaging still cuts the file to its first line in every zip (no ZFA-44 container there), which takes the production
dressing out with it: a zip that ships the container needs package_release.sh to strip only the test block instead.


## 10. Code review of 2026-11-07 (branch feature/decoy; nothing run in game)
- **Co-op** (finding 1): a joiner's copy of a carrier launches ZFA-44s of its own from the host's forwarded launch
  records; they're kept for the look and their fight is nobody's: sv_escort.lua ESC.localZfa() puts them in sv_coop.lua's
  stand-in set (their hits on an enemy copy never sent as that player's), each forwarded launch takes its arm's unit off
  the joiner's list first, and a carrier the host no longer has ("es" field 10) takes them off there. tools/re/ESCORT.md's
  "Code review of 2026-11-07" has the log lines.
- **Packaging** (finding 16): tools/package_test.sh now has package_release.sh's ZFA block (without ZFA=1 the container
  out and Scripts/sv_zfa44.lua cut to its first line; ZFA=1 keeps both and names the zip ..._ZFA44), strips the default
  ini's test-only sections with the Scripts, and leaves out flights_*.csv.

## 11. The final dive (2026-11-08, 0.74.34; not yet run in game)
The user: "these ZFA-44's will last 3 rounds before they fly towards the nearest enemy aircraft and explode on the
aircraft they were targetting with an Helios Explosion"; her answers: at the start of the 4th round, the target and the
enemies near it, players and allies untouched. Scripts/sv_escort_dive.lua (ZDIVE), CFG.allies.carrier.dive.
- A carrier leaving after its service (sv_escort.lua, the host's or solo): ZDIVE.take(C) keeps its ZFA-44s up (out of
  their container, alive) instead of flightOff (switched off); parkedOff still finishes the parked ones. None up, or
  dive.enabled false: flightOff as before.
- Through the break nothing; as the next round's enemy aircraft come (D.round > the leaving round, spawning / wave /
  fighting), each held plane is ordered onto the nearest enemy aircraft (EngagementOrderOverride Normal, TargetFirst,
  again every reorder_s), one each while there are enough. Within detonate_m (800 m) of it: the blast centred on the
  target; dive_s (40 s, extended to 2.5x on a retarget) on: centred where the ZFA-44 is.
- The blast (host or solo): every enemy aircraft of `planes` within blast_m (1 km) down by ModifyHealth(-1e6, your
  pawn, true), as the airstrike's hits (you're paid); an ace squadron's or a special's (not pool, bomber, DECOY UAV or
  FESTIVAL missile) takes boss_pct (30%) of its health. Players and allies aren't in `planes`: untouched. The ZFA-44
  finished off unpaid (GameplayStatics ApplyDamage, no instigator: parkedOff's way). Effects on every game: Online
  Mode's Helios burst NS_ms17supsExplosion01_ON (BA001_aias), OBJ_M09_CLOUDBOMB_EXP, BP_CamShake_BombImpactHelios within
  shake_km (6 km, scaled by distance, 0.2 at least). The asset paths are from the stock files; not yet seen in game.
- A round with no enemy aircraft: at the next round's start they're finished off unpaid, no blast. A new run (another D):
  the old run's held ones finished off.
- Co-op: the host sends "zd" h <ship> <round> (before the "es" mask drops the ship), v <count>, b <x> <y> <z> <down so
  far>, e. A joiner's own ZFA-44s of that ship (the container launch spawns each game's own) are kept at ESC.localOff
  instead of switched off (ZDIVE.holdLocal, only after "zd h"), ordered onto the nearest enemy copy at "v", and at each
  "b" the one nearest the blast is finished off with the effects there (no kill of its own: the host's come as "dn");
  "e" the rest. Bound copies of the host's pose flight go with the host's kills.
- Log: `carrier: <name> leaving: N ZFA-44s stay up for their final dive as round R's enemies come`, `dive: round R's
  enemies up: N held ZFA-44s dive at the nearest enemy aircraft`, `dive: Helios blast k (on its target | its dive's
  time up) at (x, y) km z m: N enemy aircraft down, M aces' or specials' hurt (T down so far)`, `dive: over: ...`;
  a joiner's `dive: the host's carrier i left for its final dive: N of this game's own ZFA-44s of it kept up with it`.
- Checks for the first test: the burst and its size (fx_scale), the sound, the shake; the ZFA-44s really closing to
  800 m (AI pursuit may hold off: then the 40 s blast where it is still reaches 1 km); the kills paid; a joiner's view.
  tools/checks/dive_test.sh.
