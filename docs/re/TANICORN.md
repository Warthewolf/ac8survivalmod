# TANICORN: research for a ship boss built from our own assets (2026-11-09)

The user's Anomaly boss: one ship fused from the Alicorn and the Tanager (the battleship Matias Torres survived, sunk
by Mobius 1), concept "Leviathan" (~650 m). It must be **its own model**: our own meshes, skeletons, animations and
blueprints, cooked in our UE 5.4 project, with AC8's native C++ classes as parents (unavoidable). Every moving part
must move in game, and its weapons must be selectable per mount: VLS everywhere, lasers, main guns firing railgun
shells. The Tanager stand-in is Sea Power's Iowa model: **dev install only**, never in a zip (user, 2026-11-09).

Concept art and Blender work: build/research/anomaly_tanager (Leviathan_rev4.blend, Leviathan_animated.blend).
Tags: [V] read in a file (path given), [I] inferred. Reader: `<ACE8AircraftBuilder folder>/ACE8AircraftBuilder.exe dev
dump|obj|sockets|skeleton|mesh` with a usmap (the builder source embeds one: embed/mappings.usmap.gz), headers in
build/liveproject/Source/Live/Public (= $AC8_LIVE_PROJECT).

## 0. Decisions (user, 2026-11-09)
- Hull: AC8's **submarine** class. In round 30's Invincible Fleet (docs/design/INVINCIBLE_FLEET.md; the user, 2026-11-10) it hides under the fleet's aircraft carrier and, when the carrier is
  killed, rises out of the sea once and attacks; it never dives again. Fallback if ALiveAISubmarine needs
  Alicorn-style data: ALiveAIVessels with a scripted rise.
- Weapons fire **stock projectiles** (railgun shells, VLS missiles, lasers), as the Alicorn does.
- Our blueprints go **straight onto the native classes**: not on BP_AIShip_Pawn / AITurret_Pawn.

## 1. How AC8 builds a large ship [V]
- **One hull actor; every turret, hatch, launcher or core is its own actor** (an AI game object with its own HP) in
  a `LiveChildActorComponent` whose `AttachToName` is a socket of the hull's static mesh. Stock boss BPs have no BP
  script: all behaviour is native, the BPs are data.
- Native chains: `ALiveSubmarineBase (Abstract) : ALiveAIArrangementObject : ALiveAIGameObject`; `ALiveAIAlicorn :
  ALiveSubmarineBase` (ALICORN.md's "ALiveAIAlicorn : ALiveAISubmarine" is wrong); `ALiveAISubmarine :
  ALiveSubmarineBase`; `ALiveAIVessels : ALiveAIArrangementObject` (bLandible, bAnchored); `ALiveAIGrifn :
  ALiveAIArrangementObject`; turrets `ALiveAIGroundVehicleObject`; Alicorn parts `ALiveAIAlicornHatch`,
  `ALiveAIAlicornRailCannon`, `ALiveAIRailgun` (: ALiveAIGameObject).
- Alicorn hull `OnlineMode/Blueprint/AI/Actors/Submarine/alcn/BP_BA002_alcn_N000_00100` -> `Base/..._PlnBase` ->
  `Base/..._Root` -> LiveAIAlicorn. Root: BodyMesh (SM_BA002_alcn_body, profile EnemyPawnPlus, 42 sockets, 647 m),
  BridgeMesh, DestroyedBodyMesh (SK_..._DAM + A_..._DAM), OverlapCollision, LiveAIFireControlSystemComponent,
  DamagedStateComponent, InducedExplosionArrangement, PlugHolder (OrcaBasicObjectPlugHolder), AIActionEventComponent,
  AIRunwayManagerComponent + 18 spline runways, 30 part components. CDO: bIsSea, bLargeShip, MaximumSpeed 500,
  RotationSpeed 15, Under/OnWaterLocation, DamageEffects keyed by socket, MainBodyDestructionDelayTime 12,
  GameObjectId 5100, Category 7/22, bCanBeDamaged False (the core part carries bIsBoss).
- Campaign Aegis `Blueprints/Vehicle/AI/Vessels/VE002_aegs/CP/BP_VE002_aegs_CP` -> Base -> `BaseAI/BP_AIShip_Pawn`
  (3 BP functions: GetDisplayHealthRate, GetTakeoffPoint, GetWorldUILocation) -> LiveAIVessels. VesselMesh +
  hidden DamagedStaticMesh, radar on SOC_Radar spun by LiveSpinnerComponent, turrets on SOC_aegs_mk15/41/45.
  Death: LiveDefaultDestroySystemExtraEffect + BP_Vessel_BodyDestroyParam (mesh swap, sinking, FinalExplosionTime 80).
- Part class is set where it is placed: Alicorn Root leaves ChildActorClass empty and N000 sets it (+ a
  ChildActorTemplate); Aegis Base sets it directly. Parts nest (hatch -> `turretSocket` -> turret).
- **The component name ties everything together**: DT_NPC row `ChildNPCId[i]` pairs with `ChildNPCComponentNames[i]`
  (= BP component name); world data `FLiveChildAIObjectData` {MissionNpcID, ComponentFieldName, Class (hard import,
  hard rule 7), TargetMarkType, Tags, GrandChildrens}. Part HP comes from its own row -> DT_NPC_Model MaxHealth.
- No separate weak-point system: a weak point is a child object with its own HP and tags (EP ChildDamageByTag).

## 2. How parts move [V]
- **Aiming is native, no anim BP**: the part's `LiveAIFireControlSystemComponent.AllArms[]` arm has a
  `LiveFCSModule_LauncherBoneControl` (MeshComponentName = a PoseableMeshComponent, `ControlBones[]`
  FLiveFCSLauncherBoneSettings {BoneName, Axis 1 yaw / 2 pitch, Yaw/Pitch {Speed, AngleMin, AngleMax},
  rotation sounds}). Examples: Aegis mk45 `BN_turret_yaw` +-140 40 deg/s, `BN_turret_pitch` 1..65; Alicorn emls
  `turret_yaw` +-180 90 deg/s, `turret_pitch` 0..90; land battleship GR037 main cannon `BN_turret_yaw` +-120 and
  three pitch bones `BN_turret_pitch01..03`, SlotNum 3.
- Campaign turret skeletons: `BN_Body` > `BN_turret_yaw` > `BN_turret_pitch`, muzzles `SOC_Gun_01..03` on the pitch
  bone(s). Alicorn: Body > turret_yaw > turret_pitch, sockets gun / sp / ws. Muzzles are found by
  `Performance.SlotSocketPrefix` (GUN, WPN, SP, VLS, MSL, ...) + number up to SlotNum. Exact matching rule unknown:
  copy a stock spelling exactly.
- **Scripted motions are one AnimSequence each**, played by native code on a SkeletalMeshComponent in
  AnimationSingleNode mode (`AnimToPlay`): Alicorn hatches 0.5 s, rail cannon `A_BA002_alcn_emlm` 3.333 s (native
  scrubs to `AnimPositionAttack` 1.667 s; `DownAnimationAsset` emlm_DAM). Hatch pattern (campaign `ALiveAIWeaponHatch`,
  Grifn): door bones + a `turret` lift bone with `turretSocket` carrying the gun's LiveChildActorComponent;
  `bOpenOnInit`, `bAutoWeaponActivation`, or event node `LiveAIGrifnHatchOpenExecution` (Mission 30).
  General route: `ULiveAISimpleAnimationComponent` + event `LiveAISimpleAnimationPlayExecution`.
- Optional ABPs on `ULiveAIFireControlSystemAnimInstance` (K2_OnTrigger / OnFired) exist for open/close state
  machines (Ladon VLS, ldbs hatches); they have BP script: avoid unless needed.

## 3. How weapons are chosen [V]
- Mount = hull socket + part component. What sits there = world data Class + its NPC row. How it fires = the part's
  FCS arm: Launcher module (MeshComponentName, Performance {FireRate, MagazineCapacity, ReloadTime, SlotNum,
  SlotSocketPrefix}, FireControl {CaptureDistance, cone, timings, TriggerCount}) + Projectile module (WeaponClass).
- Campaign turrets also take `NpcFCSId0` -> DT_NPC_FCS (`FCSBlueprintClass`: one of ~115 arms BPs in
  /Game/Blueprints/Weapons/BP_FCS/CP/, + NpcWeaponId + numbers) -> DT_NPC_Weapon. Survival already swaps a mount's
  weapon at run time this way (ally AA -> flak, sv_allies.lua) when the arms BP's MeshComponentName/prefix exist on
  the part. Vessel turrets all use `TurretPoseableMesh` + GUN, so they swap freely.
- **VLS**: cell count = sockets on the launcher mesh up to SlotNum (Alicorn vls1..vls8 SlotNum 8; Aegis Mk41
  SOC_Vls_01..08). Salvo = TriggerCount / MagazineCapacity; missile = WeaponClass + NpcWeaponId.
- **Railgun shells from a triple turret**: GR036 land battleship `BP_GR036_ldbs1_MainCannon_Normal` =
  `LiveFCSModule_LauncherTripleRailCannon` on PM_Cannon, SlotNum 3, TriggerCount 3, Reload 12, 15 km, weapon
  `BP_wp_eml_ldbs01` (ALiveEMLBullet_BattleShip). Ready arms BP `BP_FCS_StrafingRailgun_00` (SlotNum 2, PM_Cannon).
  HUD/minimap warning: hard rule 45.
- **Lasers**: `BP_SwingTLS_ForMSL` (anti-missile, AIControlCIWS bSearchMissileOnly), `BP_SwingTLS_ForPlane`,
  `BP_wp_tls_x0`, pulse `BP_wp_plsl_BaseClass` / Arsenal Bird pulse pods. None is in a stock arms BP: our own arms.

## 4. What we author / what stays native
- Ours: meshes, skeletons (bone names the FCS module names), sockets, anim sequences, every component layout and
  property value, table rows (DT_NPC_Model BlueprintClass -> our BP, DT_NPC, DT_SV_NpcMission; added at run time),
  world data, EP orders (a hull's order doesn't reach its turrets: engage each part).
- Native only: every ALive* class and FCS module (aim solving, firing, search), dive/surface, phases, action events,
  destroy systems, the spawner.
- Cook route today (tools/x02s, tools/zfa44): skeletal meshes, skeletons, physics assets, anim sequences, textures,
  material instances on stubs, versioned (hard rules 42, 58); own container per feature. **Not yet done: a cooked
  blueprint or a static mesh with sockets of ours loading in AC8.** That is the first thing to prove.

## Open questions
- Partly answered: tools/laser7's `LaserFx` commandlet (the SurvivalFx editor module in $AC8_LIVE_PROJECT) already
  builds a blueprint of a native class (`BP_SV_LaserInterceptor` on ALiveLaserInterceptor, CDO + component values
  from a JSON spec), cooked versioned; it spawned, fired and intercepted in game (0.74.31, hard rule 58). Still
  untested: a BP with instanced FCS subobjects (arms / launcher / projectile modules), our own skeletal mesh on a
  PoseableMeshComponent, and a unit spawned from world data through DT_NPC_Model.BlueprintClass (milestone 0).
- Socket-name matching for SlotSocketPrefix; one pitch bone with three muzzles vs three pitch bones.
- Does ALiveAIAlicornRailCannon work on a hull that isn't ALiveAIAlicorn? Fallback: TripleRailCannon on a pitch bone
  + LiveAISimpleAnimationComponent for the deploy and split.
- BP_AIShip_Pawn's three functions: needed on a hull subclassed straight from ALiveAIVessels?
- MaxHealth BP vs model row; how NpcFCSId merges with BP FCS modules.

## 5. Milestone 0: built in 0.74.43 (2026-11-09), not yet run in game
- `BP_SV_Tani_T5` (tools/tanicorn, README.md there): the Iowa's 5-inch twin mount at 1.9, our skeleton (Body >
  turret_yaw > turret_pitch, identity bones; pitch pivot (147.5, 2.6, 414.8) cm), sockets SOC_Gun_01/_02 at (859.6,
  -/+203.7, 0.8) cm on turret_pitch, on AC8's native ALiveAIGroundVehicleObject as the Aegis Mk45 (dev obj of
  BP_VE002_aegs_mk45_Base / BP_AITurret_Pawn): yaw +-180 40 deg/s, pitch 0..80 40 deg/s, AIR_ONLY, 6 km, 10 rounds a
  burst of 20, the vessel AA shell (stub at /Game/Blueprints/Weapons/AAGUN/BP_wp_aagun_vessel on LiveBulletEmitter).
- The cooked blueprint's exports match the Mk45's layout (FCS component > arms > three modules; DamagedState > ChangeMesh;
  PlugHolder; RootComponent; our three SCS components). No InducedExplosionArrangement override: the dumped classes don't
  create it, the game's native class does.
- In game: Ctrl+T (sv_tanicorn.lua). Log lines to read: `tanicorn: rows: SV_Model_TaniMount in DT_NPC_Model,
  SV_Npc_TaniMount in DT_NPC`, `tanicorn: Ctrl+T, SV_Unit_TaniTest at ... : 1 up`, `tanicorn: mount ... up: class
  BP_SV_Tani_T5_C, fire control arms 1`, then every 2 s `... yaw <y/p> pitch <y/p>`: the yaw bone's angle changing as you
  fly round it is AC8's fire control aiming our bones. Pass: it draws (grey 5-inch mount on the sea), tracks, fires flak,
  takes hits and swaps to its wreck. If it doesn't spawn: the class didn't load (container not mounted, or the blueprint
  refused); if it spawns but never turns: the bone control (names / prefix / sockets).

## 6. The whole ship's parts for UE: prepared 2026-11-10, not yet built on the machine
- `sh tools/tanicorn/build.sh` now starts from the model (tools/tanicorn/README.md): `export_tanacorn.py` writes T16, T5,
  CIWS, LASER (turret rigs as milestone 0's), VLSD and VLSS_L1..R4 (Body > Hatch_01..08, AnimSequence Open 0.5 s,
  SOC_Vls_01..08 with rotations: +X each cell's launch line), and HULL (static mesh, 36 `Mount_<part>` sockets, +X the
  part's forward). The T5 is milestone 0's to the millimetre (pivot (147.5, 2.6, 414.8) cm, muzzles (859.6, -/+203.7,
  0.8)), so BP_SV_Tani_T5 and the Ctrl+T test are unchanged.
- New in the pipeline, each a first: a static mesh with sockets of ours (TaniBuild `mesh_sockets`: section 4's open
  proof, WP2's first test), UE's glTF import of a joint animation (the lids), a 125k-triangle static mesh with 17
  slots and complex-as-simple collision, blueprints BP_SV_Tani_T16 / _CIWS / _LASER on the T5's layout (SlotNum 3 / 1 /
  1; the stock AA shell until WP1).
- First run: read `build/tanicorn/ue_import.log` (warnings counted before `done`), `tanibuild.log`, `cook.log`; the
  list of what to look for is in docs/design/INVINCIBLE_FLEET.md, WP0 handover, "for UE".

## WP1: the stock fire control rows per mount type (2026-11-11)
A read-only dump job, no game run. Sources: the rows from build/stock's DT_NPC_FCS + DT_NPC_FCS_ON, DT_NPC_Weapon(_ON)
and DT_NPC(_ON) through `build_survival.npc_fcs_tables()` and dtx (330 fire control rows, 142 weapon rows); the arms
and parts from `dev dump` / `dev obj` of every export of the legacy packages (163 BP_FCS arms, 74 + 18 + 8 + 2 part,
weapon, mesh and skeleton packages); headers in build/liveproject/Source/Live/Public. Commands at the end. [V] unless
tagged. Arm values are the arm's own; a row's values replace them (L2-L4). Row distances are in m, an arm's in cm [I]
(NPC_FCS_StrafingRailgun000 CaptureDistance 6000 against its arm's 600000).

### What decides the routes
- `FCSBlueprintClass` is `TSoftClassPtr<ULiveFireControlSystemBase>` (LiveNpcFCSDataTable.h:20). A row can name any
  arms class, not only the BP_FCS ones.
- An arms class is a blueprint on `LiveFireControlSystemArms` with AIModule / LauncherModule / ProjectileModule on its
  CDO. Outside BP_FCS there are more of them, named by no row: `BP_GR036_ldbs1_MainCannon_Normal`,
  `BP_GR037_ldbs2_MainCannon_Normal` (+ `_Beast1`, `_Beast2-A`, `_Beast2-B`), `BP_GR036_ldbs1_Gun_FCSArms`,
  `BP_GR031_mfrg_Arms` and `Weapons/LdbsMainGun/BP_GR036_ldbs1_MainCannon_LongRange_ms06_*`. Their part blueprints
  hold an instance in `AllArms`. An arm built inline in a part blueprint can't be named.
- The 163 BP_FCS arms have 62 LauncherBoneControl, 93 LauncherCommon, 4 LauncherFlare, 2 LauncherTripleRailCannon
  and 2 LauncherVirtualJoint launchers. None of their 163 projectile modules fires a laser.
- `ULiveFCSModule_LauncherTripleRailCannon : ULiveFCSModule_LauncherBoneControl`. It has the same MeshComponentName,
  ControlBones and Performance, plus HUDControl, IsDispRadarMap, ForceAlertDisp, the charge, laser-pointer and electric
  VFX, the charge sounds and FixAngleYaw / FixAnglePitch (LiveFCSModule_LauncherTripleRailCannon.h).
- `SlotSocketPrefix` (ELiveFCSLauncherSocketPrefix): GUN 0, WPN, SP, SWP_1-3, FLR, VLS, UAV, MUDR, MSL, SWDCT. The
  dumper prints GUN as `0`. The stock spellings are `SOC_Gun_01` (GR035, GR036), `SOC_Vls_01` (Mk 41) and `vls1`
  (the Alicorn's SM_BA002_alcn_vls_L_01), and the GR036 arm's own VFX name `SOC_gun_01`. So the matcher wants the
  prefix and the number, whatever the case, the `SOC_` or the zero padding [I].
- **Correction to 0.74.61's notes** (sv_tanicorn.lua 43-44, survival_events_festival.py 83, INVINCIBLE_FLEET_PROGRESS
  WP1): `BP_FCS_StrafingRailgun_00` is the GR035 land *destroyer's* main cannon (BP_GR035_ldds_MainCannon_Base has the
  same launcher, mesh SK_GR035_ldds_MainCanon), not the GR036's. Its weapon `BP_wp_eml_strafing_BaseClass` is
  `ALiveEMLStrafing : ALiveAttachedWeapon`, a sweeping beam and not a shell. Its rows NPC_FCS_StrafingRailgun000 / _MS24
  are named by no DT_NPC row. The railgun **shells** are `ALiveEMLBullet_BattleShip` (`BP_wp_eml_ldbs01-04`,
  `_Beast2-B`), and only the GR036 / GR037 main cannon arms fire them. BP_wp_eml_ldbs_BaseClass: SpeedInitial
  1,111,111 cm/s, LifeTime 10 s, damage 200, FCSActivationDist 18 km. The dumper can't read BP_wp_eml_ldbs01's own CDO
  (its class isn't in the usmap).
- **Correction to the brief:** `BP_FCS_SV_ZfaTLS` isn't tools/laser7's (LaserFx built BP_SV_LaserInterceptor). It is
  build_survival_world.py `build_zfa_laser`: a zen copy of BP_FCS_Vessel_CIWS_00 with its weapon import repointed, its
  launcher class swapped to LauncherCommon and its props rewritten. Its row SV_FCS_ZfaTLS is built in DT_SV_NpcFCS with
  FCSBlueprintClass set at build time, and sv_escort_laser.lua adds it to DT_NPC_FCS at the main menu. It fired and
  intercepted in game in 0.74.15 (HISTORY.md, 0.74.16). That is the proven way to name an arm no stock row names.
  FCSBlueprintClass is a soft class reference, so Lua must never read or write it (hard rule 29). The row is built,
  and Lua copies it whole (`cloneRow` / AddRow).

### The working mounts (reference; 0.74.61 run)
| mount | row | arm blueprint | launcher | MeshComponentName | ControlBones (axis; arm's arc @ deg/s) | prefix / sockets | direction | aiming | WeaponClass | Performance (arm; row) |
|---|---|---|---|---|---|---|---|---|---|---|
| T5 | NPC_FCS_FlakGun000 | BP_FCS_FlakGun_00 | BoneControl | TurretPoseableMesh | BN_turret_yaw (1; ±180 @360), BN_turret_pitch (2; 0..90 @360) | GUN / ours SOC_Gun_01-02 | SlotSocket | DoNotWhileFiring | BP_wp_flakgun | FireRate 12, Mag 1, Reload 1, capture 15 km; row SlotNum 1, Mag 10, FireRate 200, 15 km, yaw/pitch 360 ±180 / ..90, weapon FlakGun_000 |
| T16 (artillery) | NPC_FCS_VesselArtillery000 | BP_FCS_Vessel_Artillery_00 | BoneControl | TurretPoseableMesh | BN_turret_yaw (1; ±120 @37.5), BN_turret_pitch (2; 1..60 @30) | GUN / ours SOC_Gun_01-03 | SlotSocket | default (not in the dump) | BP_wp_artillery_vesselgun | FireRate 60, Mag 1, Reload 6, capture 2.2 km; row SlotNum 1, 30 km, cone 15, yaw 30 ±110, pitch 30 -5..45, weapon Artillery_Vessel_000 (ballistic, 4000 km/h, damage 40) |
| CIWS (and LASER for now) | NPC_FCS_VesselCIWS000 | BP_FCS_Vessel_CIWS_00 | BoneControl | TurretPoseableMesh | BN_turret_yaw (1; ±60 @37.5), BN_turret_pitch (2; 1..60 @30) | GUN / ours SOC_Gun_01 | SlotSocket | default | BP_wp_ciws_vessel | FireRate 10, Mag 1, Reload 3, capture 8 km; row SlotNum 1, 2.5 km, cone 30, yaw 37.5 ±60, pitch 30 1..60, weapon CIWS_Vessel_000 (interceptor, 2.5 km) |

### T16 with railgun shells
| row | arm | launcher | MeshComponentName | ControlBones | prefix / sockets (skeleton) | direction | aiming | WeaponClass | Performance |
|---|---|---|---|---|---|---|---|---|---|
| NPC_FCS_StrafingRailgun000 (/_MS24: arm _01, weapon BP_wp_eml_strafing_MS24); no NpcWeaponId, no AI module | BP_FCS_StrafingRailgun_00 (GR035 ldds) | TripleRailCannon | PM_Cannon | BN_turret_yaw (1; ±120 @50), BN_turret_pitch_01 / _02 (2; 0..60 @45) | GUN / SOC_Gun_01 on BN_turret_pitch_01, SOC_Gun_02 on _02 (S_GR035_ldds_Canon: BN_Body > BN_turret_yaw > the two pitch bones, siblings) | SlotSocket | DoNotWhileFiring | BP_wp_eml_strafing_BaseClass (beam) | FireRate 6, Mag 1, Reload 4, SlotNum 2, spin-up 3 s, capture 6 km (min 500 m); HUD DiffusionRailGun; laser pointer PM_Cannon SOC_VFX_Laser; row SlotNum 2, Mag 10, spin-up 3, 6 km, cone 15, triggering 10 s |
| none (arms class, nameable) | BP_GR036_ldbs1_MainCannon_Normal | TripleRailCannon | PM_Cannon | BN_turret_yaw (1; ±120 @50), BN_turret_pitch01 / 02 / 03 (2; 5..58 @45) | GUN / SOC_Gun_01-03 on BN_turret_pitch01-03; SOC_VFX_Body (BN_Body), SOC_VFX_Laser (BN_Laser on yaw), SOC_turret_* (S_GR036_ldbs1_MainCanon: three pitch bones, siblings) | SlotSocket | DoNotWhileFiring | **BP_wp_eml_ldbs01** (shell) | FireRate 60, Mag 1 per slot (bHasMagazinePerSlot), Reload 12, SlotNum 3, spin-up 5 s, capture 15 km (min 55 m), cone 6, TriggerCount 3, interval 1 s, resting 12 s; HUDControl not in the dump (the class default; RailGun is 0 [I]); charge VFX on PM_Cannon SOC_VFX_Body and SOC_gun_01-03; electric VFX between StaticMeshComponents SM_turret_pitch_01-03 (sockets SOC_VFX_01Left_1, _02Center_1, _03Right_1); GR036 charge sounds |
| none (arms class) | BP_GR037_ldbs2_MainCannon_Normal (+ Beast1 / 2-A / 2-B) | TripleRailCannon | SK_Cannon | as the GR036's (BN_turret_pitch01-03) | GUN (its VFX on SOC_gun_01-03; skeleton not dumped) | SlotSocket | DoNotWhileFiring | BP_wp_eml_ldbs02 (Beast2-B: _ldbs_Beast2-B) | as the GR036's (SlotNum 3, TriggerCount 3, 15 km) |
| inline, not nameable | BP_OP1016_x40a_RG_Base (+ RGCK / RGPF CP), BP_VE022_Grifn_RailGun_Base, BP_GR031_mfrg_Arms (LauncherMGFCannon) | TripleRailCannon (mfrg: MGFCannon) | TurretPoseableMesh (x40a), TurretMesh (Grifn), SM_Cannon (mfrg) | **BN_turret_yaw (1), BN_turret_pitch (2)** | MSL (x40a), GUN (Grifn, mfrg) | SlotSocket | x40a default, Grifn / mfrg DoNotWhileFiring | Nightmare EML, strafing, mfrg EML | x40a capture 15 km, TriggerCount 5 |

- No nameable arm drives `BN_turret_yaw` / `BN_turret_pitch` on TurretPoseableMesh *and* fires a railgun shell. The
  x40a's RailGun is the only stock TripleRailCannon on our exact rig. It's inline in its part blueprint, but it proves
  the launcher works on one pitch bone (VALKA fired it, hard rule 45).
- **Recommended route (A): rig the T16 to the GR036 arm and name that arm from a built row.**
  - Row: `SV_FCS_TaniT16Rail` in DT_SV_NpcFCS (build_rows_table, as SV_FCS_ZfaTLS). Copy NPC_FCS_StrafingRailgun000,
    which has no NpcWeaponId and no AI module, so the shell keeps its own values; the artillery row's
    Artillery_Vessel_000 would bring a ballistic 4000 km/h weapon row. Set FCSBlueprintClass to
    `/Game/Blueprints/Vehicle/AI/GroundVehicle/GR036_ldbs1/BP_GR036_ldbs1_MainCannon_Normal.BP_GR036_ldbs1_MainCannon_Normal_C`,
    SlotNum 3, MagazineCapacity ≥ 3, TriggerCount 3, spin-up 5 s and capture 15-18 km. Lua adds it at the main menu
    (sv_escort_laser.lua's way), and TANI.mounts T16 takes it as fcs_src for fcsRow's speeds and arcs. The arm is stock,
    so no arm package of ours is needed.
  - Rig (T16 only; export_tanacorn.py, spec.py, the TaniBuild layout):
    - Name the PoseableMeshComponent **`PM_Cannon`**, and use the same name in spec.py's MeshComponentName and
      DestroyHideMeshNameList.
    - Replace BN_turret_pitch with three sibling bones under BN_turret_yaw: **`BN_turret_pitch01`, `BN_turret_pitch02`,
      `BN_turret_pitch03`**. This is the GR036's spelling, with no underscore before the number (L1: the names the
      arm's ControlBones give). Skin one barrel to each, pivoting on its trunnion.
    - Put `SOC_Gun_01-03` on those bones.
    - Add `SOC_VFX_Body` on BN_Body and a `BN_Laser` bone carrying `SOC_VFX_Laser`, for the charge glow, the firing
      shock and the search laser.
    - The electric VFX names StaticMeshComponents `SM_turret_pitch_01-03`, which ours lacks. Whether a missing one is
      harmless is unknown [?]. If it isn't, add three empty StaticMeshComponents of those names carrying the three
      `SOC_VFX_*_1` sockets, or take route B.
  - Hard rule 45: the arm is a TripleRailCannon, so the minimap line and HUD alert need IsDispRadarMap /
    ForceAlertDisp true and HUDControl 1 set on the instance at run time. The RAILGUN WARNING is Mission 18's
    LiveSetRailgunAlertEnable record.
  - Why A: it is the only route with a stock arm, no cooked or copied arm, the real shell, the charge, the spin-up and
    rule 45's fields. It costs one re-export of the T16.
- Fallback (B): an arm of ours, made build_zfa_laser's way. Take a zen copy of BP_GR036_ldbs1_MainCannon_Normal under
  /Game/Mods/SurvivalMode/Tanicorn. Rewrite its launcher's MeshComponentName to TurretPoseableMesh and its ControlBones
  to [BN_turret_yaw 1, BN_turret_pitch 2], and empty or retarget its VFX names. This keeps today's rig, but it needs an
  array-of-structs rewrite that build_zfa_laser doesn't do yet. A TaniBuild-cooked arm would be a first (no cooked FCS
  subobjects proven: section "Open questions").
- Zero-build probe (C) [I]: keep today's artillery row and clear its NpcWeaponId in fcsRow. At spawn, set the
  instance's ProjectileModule.WeaponClass and WeaponCDO to BP_wp_eml_ldbs01, as sv_anomalies.lua `SPC.V.emlWeapon`
  does for VALKA. That gives shells from today's barrels but no charge, spin-up or railgun HUD, because a BoneControl
  launcher has none of rule 45's fields. Whether VALKA's swap took effect in game was never logged as confirmed [?].

### VLS (deck VLSD and side VLSS_L1-R4)
| who | row | arm | launcher | MeshComponentName (type) | ControlBones | prefix / sockets | direction | WeaponClass | Performance (arm; row) |
|---|---|---|---|---|---|---|---|---|---|
| Aegis Mk 41 (VE002_aegs_mk41_01, and every Ally / MS row; Survival's SV_Fleet_Mk41Aegis runs on its `_SVA_Fleet` copy) | NPC_FCS_VesselVLSmk41 (_Ally: arm the same, AI Turret000_MS26, weapon VLS_Vessel_MS26_000, 30 km) | BP_FCS_Vessel_VLS_VE002_mk41 | LauncherCommon | TurretMesh (StaticMeshComponent, SM_VE002_aegs_mk41) | none | VLS / **SOC_Vls_01-08** on the static mesh, rotation (90, 0, 0) | SlotSocket | BP_wp_vls_a0 (LiveVLSMovementComponent) | FireRate 12, Mag 1, Reload 10, capture 3 km, cone 180; row SlotNum **1**, Mag 10, FireRate 200, 3 km, triggering 5 s, resting 10 s, AI NPC_AIModule_Turret000, weapon VLS_Vessel_000 (9 s, 3000 km/h max, homing after 1.5 s) |
| Norn (OP0044_norn_VLS_L1 / R1) | NPC_FCS_NornVLS000 | BP_FCS_Norn_VLS_00 | LauncherCommon | TurretMesh | none | VLS | not set (default) | BP_wp_vls_norn | FireRate 12, Mag 1, Reload 15 |
| Alicorn (alcn_vlsL/R_01/02, DT_NPC_ON) | **none**: the blueprint's own arms | inline in BP_BA002_alcn_vlsL1_Base etc. (AITurret_Pawn ON) | LauncherCommon | TurretMesh (StaticMeshComponent, SM_BA002_alcn_vls_L_01) | none | VLS / `vls1`-`vls8`, rotation (90, 0, 0) | SlotSocket | BP_wp_vls_BaseClass (from BP_BA002_alcn_vls_Base) | FireRate 20, Mag 1, Reload 7, SlotNum 8, capture 10.8 km; a second arm without a mesh |
| Ladon (OP0045_ladn_VLS_L / R) | **none**: own arms | inline in BP_OP0045_ladn_VLS_Base (ALiveAILadonWeaponObject), three arms | LauncherCommon | HatchAnimSK (**SkeletalMeshComponent**, SK_OP0045_ladn_L_VLS) | none | VLS | SlotSocket | BP_wp_vls_certain_ladon (arm 1), BP_wp_vls_ladon (arms 2, 3) | SlotNum 2 (arm 1), capture 5 km |
| others | VesselVLS3r14 / s300fm / sam (TurretMesh, **MSL**), VesselVLSmaya_Ally (VesselMesh, VLS), VehicleVLS000/001 (VehicleMesh, VLS), NFID_Vessel_VLS_00 (ON, TurretMesh, MSL) | | LauncherCommon | | none | | SlotSocket | vls_a0 / vls_r0 / vls_mslb / vls_BaseClass | |

- Survival's fleet copies these rows at run time. SP_TURRETS' `aegs_mk41` becomes SV_Fleet_Mk41Aegis on fire control
  NPC_FCS_VesselVLSmk41_SVA_Fleet (sv_allies.lua allyFcs). The Ladon's and the Alicorn's volleys are fired from Lua
  through LiveFireOneShotWeapon (RE_SV_LadonVolley*, RE_SV_AlcnVolley; hard rules 36 and 40), not through a row.
- **Lids:** no launcher setting opens a lid. The stock ways to animate one:
  1. The Ladon's: `ABP_OP0045_ladn_L_VLS` on `ULiveAIFireControlSystemAnimInstance`. Its `K2_OnTrigger` override
     drives an Open / Close state machine (A_OP0045_ladn_L_VLS_Open / _Close). It needs an AnimBP with script: a first
     for us.
  2. `ULiveAISimpleAnimationComponent` (Datas[].TargetMeshName) played by the event node
     `LiveAISimpleAnimationPlayExecution` (Mission 25_2, Mission 30: docs/design/node_catalog.tsv).
  3. `FLiveUniqueStateMachine_PlaySimpleAnimation` {ComponentName, Animation, bLoop, bReverse}.
  4. `ALiveAIWeaponHatch` / `ALiveAIAlicornHatch`: a separate hatch part with bOpenOnInit that holds its weapon part.
- **Recommended route: clone NPC_FCS_VesselVLSmk41 for both block types.** Use the `_SVA_Fleet` copy if the fleet's
  ranges are wanted.
  - Row: SlotNum 8, MagazineCapacity ≥ 8, a longer CaptureDistance (the stock 3 km is short), and TriggerCount /
    interval per salvo. LauncherCommon has no bones, so the yaw / pitch fields are left alone [I].
  - Rig: the bones (Body > Hatch_01-08) and the sockets `SOC_Vls_01-08` stay as they are; the sockets are already the
    Mk 41's spelling. The VLS blueprint names its mesh component **`TurretMesh`** and makes it a
    **SkeletalMeshComponent**, so it can play AS_SV_Tani_VLS*_Open. A LauncherCommon reading its sockets off a
    SkeletalMeshComponent is stock: the Ladon's HatchAnimSK.
  - No cooked arm is needed.
  - The lids: play Open from the volley's remote event, by way 2 or by Lua calling the component's PlayAnimation [I].
    Or open them once at the rise. Way 1 only if a lid must follow every trigger.
  - Side blocks: their sockets lean with the hull, and LauncherDirection SlotSocket launches along each socket's +X
    [I]. Whether BP_wp_vls_a0's LiveVLSMovementComponent keeps that line or climbs straight up first is unknown [?].
- **Built on this route (2026-11-12, not yet built in UE or run in game).** tools/tanicorn/spec.py `vls_mount`:
  BP_SV_Tani_VLSD (the deck block, one blueprint for VLSD_1..8) and BP_SV_Tani_VLSS_L1..R4 (each side block its own mesh)
  on ALiveAIGroundVehicleObject: TurretMesh a SkeletalMeshComponent (both mesh fields, AS_SV_Tani_<part>_Open in
  single-node mode held at 0, shut), the mounts' wreck and damage state, a hit sphere round the cells, and an arm of its
  own as the row's (LauncherCommon on TurretMesh, SlotSocket, prefix VLS, SlotNum 8; ProjectileCommon on a stub of
  BP_wp_vls_a0, whose BP_wp_vls_BaseClass is a LiveVLSMissile [V: its script imports]). The row: SV_FCS_TaniVLS,
  NPC_FCS_VesselVLSmk41 cloned at the main menu by sv_tanicorn.lua (TANI.vls_fcs: SlotNum 8, magazine 8, reload 15 s,
  7 km down to 600 m, cone 180, a ripple of 4 0.4 s apart over 1.6 s, 10 s rest; the stock row's 3 km, one shot every 5 s
  and the AI module / weapon row kept). Each block type its own mission, DT_NPC and model row (survival_events.TANI_VLS);
  VLSD and VLSS_L1 also a unit each (Ctrl+K). On BP_SV_Tani_HULLLIVE all 16 VLS sockets are live parts (32 with the gun
  mounts). The lids: route "Lua calling the component" (SetAnimationMode / SetAnimation / SetPlayRate / Play, as the rise's
  rig), opened on a launch (a pooled LiveVLSMissile shown with its OwningGameObject a block: sv_weaponlog.lua's launch
  rule) and shut 6 s after; if a launch's owner is an actor of ours that isn't a block, by your range instead.
  tools/checks/tani_vls_test.sh. Open: whether the row's arm takes our skinned TurretMesh's sockets (`asset finds
  SOC_Vls_01 true`, then the missile lines' nearest cell), whose OwningGameObject a part's missile names, and the side
  blocks' launch line.

### LASER
- No BP_FCS arm fires a laser [V: 163 arms]. Decided by the user, 2026-11-11: the LASER mounts carry AC7's
  LaserInterceptor (BP_SV_LaserInterceptor, as the ZFA-44s), and the user is building it. Not researched further.

### Commands (re-run from the repo root; `$S` = a scratch folder, `$AB` = a copy of ACE8AircraftBuilder.exe + oo2core_9_win64.dll)
- Rows: `python -I -X utf8` with `sys.path.insert(0, "<repo>/tools"); import build_survival as bs; fcs, wpn =
  bs.npc_fcs_tables()` (row -> {property: value}). For DT_NPC / DT_NPC_ON / DT_NPC_Model(_ON), use
  `dtx.parse(uprop.Ctx(bytes(ZenPkg(bs.stock(path)).payloads[0]), z.names), 0, 'LiveNpcDataTable' | 'LiveModelDataTable')`.
  In this session these were scratch scripts fcs_rows.py / npc_rows.py, written to $S/tables.
- Packages, one run per set (several `-f` in one run work):
  `. tools/env.sh && KEY=$(python -I tools/env.py --aes-key) && MSYS_NO_PATHCONV=1 tools/bin/retoc.exe -a "$KEY" to-legacy
  --no-shaders --version UE5_4 -f <filter> [-f <filter> ...] "$AC8_PAKS" $S/legacy`. The filters used were:
  - `BP_FCS_` (163 arms).
  - `BP_wp_eml_`, `GR035_ldds_MainCan`, `S_GR035_ldds_Canon`, `BP_GR036_ldbs1_MainCannon`, `BP_GR037_ldbs2_MainCan`,
    `BP_VE002_aegs_mk41`, `VE002_aegs_mk41`, `BP_OP0045_ladn_VLS`, `ABP_OP0045_ladn_L_VLS`, `BP_BA002_alcn_vls`,
    `BP_OP0044_norn_VLS`, `BP_wp_vls_a0`, `BP_GR036_ldbs1_VLSM`, `BP_VE022_Grifn_VLS`.
  - `SK_GR036_ldbs1_MainCanon`, `S_GR036_ldbs1_MainCanon`, `SM_VE002_aegs_mk41`, `SK_OP0045_ladn_VLS`, `A_OP0045_ladn`.
  - `BP_VE022_Grifn_RailGun`, `BP_VE022_grifn_RailGun`, `BP_GR031_mfrg_Arms`, `BP_OP1016_x40a_RG`,
    `BP_GR036_ldbs1_Gun_FCSArms`.
  - `SM_BA002_alcn_vls_L_01`.
- Dumps: `export USMAP="<repo>/build/tanicorn/alcn/mappings.usmap" MSYS_NO_PATHCONV=1; $AB/ACE8AircraftBuilder.exe dev dump
  <pkg without .uasset>`, then `dev obj <pkg> <n>` for every export n from 2 to the count in the dump. For skeletons and
  meshes, use `dev skeleton <S_...>` and `dev sockets <SM_/SK_...>`; a skeletal mesh's sockets are on its skeleton
  (`dev obj` of S_...: SkeletalMeshSocket exports). Every launcher / projectile module was then tabled from the
  `dev obj` JSON (MeshComponentName, ControlBones[].BoneName / Axis, Performance, FireControl, AimingMethod, HUDControl,
  WeaponClass).
- Package lists come from build/scan/all_chunks.txt (grep the paths).


## Damage: like the Alicorn (2026-11-12)
A tester on 0.74.65's ..._TANACORN zip: "the alicorns armaments aren't working on the tanacorn" and "if the Tanacorn is hit,
everything immediately dies". The user's decision: damage **like the Alicorn**: her hull can't be damaged, every gun, VLS
block and railgun is shot down on its own, she sinks only when her core is destroyed (WP11's three phases,
docs/design/INVINCIBLE_FLEET.md). Research of 2026-11-12 (a workflow, each report checked by a skeptic):
- Not the hull's health [V]: SV_Model_TaniHullLive MaxHealth 5000 (HealthInternal 50000), durability NPC_WPDur_000 /
  test_NPC_ExpDur_000 (100 % everywhere, the stock Aegis's rows); the test mounts took their rows' health in game (0.74.64).
- The parts were paper [V]: 30-80 health (about one standard missile each), 14-23 m apart, and the player's missile has
  splash (ALiveExplosiveWeapon ExplosionRadius / AreaOfEffectDamage).
- Every part and hull kept AC8's native induced explosion on death [V: LiveInducedExplosionSystemBase.cpp HitDistance 20,
  ExplosionRadius 100, damage 100; Arrangement bIsExplosionDamageParentOnly false]: one part's death kills its neighbours.
  The stock Aegis turrets defuse it (BP_VE002_aegs_mk45/mk15/mk41_Base: ExplosionRadius 0, HitDistance 0, parent-only,
  damage 20); the Alicorn's parts keep the default on 500-3,125 health.
- The chain can't sink a 5000 hull alone (32 x 100), but a hull's death takes its child actors with it [I]. The parent-damage
  channels are off by default [V: DamageRateToParent 0, bIsReflectionDamageToParent false].
- Ctrl+Y's hull (and Ctrl+R's when none is up) is one actor with every part a PoseableMeshComponent: nothing on it fires.
- The Alicorn's hull: model HP 10, bCanBeDamaged False; its core part (alcn_core_01, bIsBoss) carries the boss's life.
- Flags on our objects (headers): ALiveGameObject bIsInvincible / SetIsInvincible, bIsInvincibleInducedExplosion,
  bIsNonTargetInducedExplosionTarget, MinHealth; ALiveAIGameObject bCauseExplosionOnDeath; AActor bCanBeDamaged;
  ULiveDamagedStateComponent.InducedExplosionSystem (ULiveInducedExplosionSystemBase: HitDistance, ExplosionRadius, damage;
  Arrangement: bIsExplosionDamageParentOnly, ExplosionSpawnDelay, bOverrideAttacker).
- The Alicorn's railcannon and sub-railguns: drawn meshes on both hulls (no blueprint, fire control, rows or Lua). The stock
  ones are driven by ALiveAIAlicorn itself (RailgunManager, CachedRailCannon, its action events); the stock railcannon
  (BP_BA002_alcn_emlm_Base) has no weapon at all; the sub-railgun's arm is LauncherAlicornRailgun with BP_wp_emls_alcn
  (damage 200, 18 km). Route (WP11 M3): live mounts on the T16 pattern with a row of ours with no NpcWeaponId (the
  StrafingRailgun's way), their Deploy and the railcannon's charge and shot scripted in Lua.

What 0.74.66 does (Lua and data, no re-cook; sv_tanicorn.lua TANI.armour, sv_tanicorn_hits.lua): her hull SetIsInvincible,
bIsInvincible, bCanBeDamaged false at its spawn (Ctrl+Y / Ctrl+R / Ctrl+L); each live part, at the watch's first tick,
bCauseExplosionOnDeath false, bIsInvincibleInducedExplosion true, its InducedExplosionSystem written to the Aegis turrets'
values; the parts' rows x5 (T5 200, CIWS 150, LASER 150, VLS 200, T16 400); a hit probe (`tanicorn hits: ...`). Untested in
game: whether these writes after spawn take (the probe's start lines read them back), whether bCanBeDamaged False is
honoured on an AI hull of ours. Next: the same cooked into the blueprints (spec.py), then her core and the Alicorn's weapons.
