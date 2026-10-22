# Alicorn (Online Mode boss BA002_alcn): research, 2026-10-23

Research only: nothing under mod/, tools/*.py or runtime/ was changed. Packages were pulled with `tools/get_stock.sh`
into `build/stock/OnlineMode/...` (every alcn blueprint, action-event BP, EB_002 map package, NPC/model/durability
table). Scratch scripts and dumps are in `build/research/alicorn/` (git-ignored):
- `s/deps.py fwd|imp|rev` is the package graph from `build/scan/store.txt`. Run it with `MSYS_NO_PATHCONV=1` in Git Bash,
  or `/Game/...` arguments get mangled.
- `s/cls.py` lists exports with class / super / template.
- `s/cdo3.py <pkg> <native class> <export>` reads a blueprint CDO by trying schema shifts for the BP's own variables.
- `s/rows.py <dt> <struct> <regex>` gives compact data-table rows.
- `s/vtscan2.py` finds event-node vtables and their Execute functions.
- Dumps: `ep_eb002_s.txt` (EP, compact), `wd_boss.txt` (the Boss world-data unit), `wd_all.txt`.

Tags: **[V]** verified from data or disassembly, **[I]** inferred, **[T]** needs an in-game test.
Addresses are for AceCombat8.exe of 2026-09-29 (image base 0x140000000). Units are cm unless stated otherwise.

---------------------------------------------------------------------------------------------------------------------
## 0. Summary
- **The Alicorn is native code plus data-only blueprints.** [V]
  - Every alcn BP has no `Function` exports (no Blueprint script).
  - Behaviour comes from these native classes in `/Script/Live`, the same module as the campaign classes:
    `ALiveAIAlicorn : ALiveAISubmarine : ALiveSubmarineBase`, `ALiveAIAlicornHatch`, `ALiveAIAlicornRailCannon`,
    `ALiveAIRailgun`, `ALiveAIBarrierDrone`, `ALiveAIArrangementObject` (aircraft pools), and the action objects
    `ULiveAIActionEvent_Alicorn*`.
  - The campaign build ships all of them. None of them is an online-only module.
- **One mission uses it:** Emergency Call boss battle **EB_002** (`/Game/OnlineMode/Maps/EmergencyCall/EB_002/`:
  PL/WD/EP/MC/EF_EB_002) on the Online ocean map. [V]
  - Only `WD_EB_002` references the alcn BPs. The other references are the IGC sequences `LS_IGC_*_EB_002_*`.
- **Driven from three places:**
  1. the EP records: `LiveSubmarineOperation` (dive/surface), `LiveAIActionEventExecution` (named actions),
     `LiveFireOneShotWeapon` and `LiveAIPathExecution`;
  2. its `PhaseList` (weapons active per phase);
  3. turrets aiming by themselves through their fire-control systems (FCS).
- **Offline looks feasible.** No hard blocker was found statically:
  - the network object is created natively and null-checked;
  - the action-event manager is created lazily by the base `ALiveGameMode`, which the campaign mode derives from;
  - `LiveSubmarineOperation::Execute` has no network code;
  - the only game-mode-specific node (`LiveFinishBossBattleExecution`) is a no-op outside the boss-battle mode.
- **The cost is data.** About 35 model rows, about 35 NPC rows, NPC-mission rows, durability rows, a large world-data
  desc (1 hull + 30 parts + 195 pooled aircraft/drones) with about 45 blueprint imports, and new EP records.
  Several online-only IDs must be copied or remapped.

---------------------------------------------------------------------------------------------------------------------
## 1. Anatomy

### 1.1 Class chain [V] (`s/cls.py`, super of each `*_C` export)
| BP | parent chain |
|---|---|
| `alcn/BP_BA002_alcn_N000_00100` (the model's BlueprintClass) | `Base/BP_BA002_alcn_PlnBase` -> `Base/BP_BA002_alcn_Root` -> **`LiveAIAlicorn`** |
| `alcn/BP_BA002_alcn_emlm_Base` (rail cannon) | **`LiveAIAlicornRailCannon`** |
| `Hatch/BP_BA002_alcn_hatch{L,R}{1..6}_Base`, `hatch_emls_{L,R}_Base` | `/Game/OnlineMode/Blueprint/AI/Pawn/BP_BA002_alcn_HatchPawn` -> **`LiveAIAlicornHatch`** |
| `Hatch/Weapon/BP_BA002_alcn_emls_Base` (railgun) | **`LiveAIRailgun`** |
| `Hatch/BP_BA002_alcn_btank{fl,fr,rl,rr}_Base`, `Hatch/BP_BA002_alcn_ecm_Base`, `Weapon/aagun`, `ram`, `vls` | `/Game/OnlineMode/Blueprint/AI/Pawn/AITurret_Pawn` -> `LiveAIGroundVehicleObject` |
| `Weapon/BP_BA002_alcn_ciws_Base` / `ciwsp5_Base` | `aagun_Base` / `ciws_Base` (-> AITurret_Pawn) |
| `Hatch/BP_BA002_alcn_vls{L,R}{1,2}_Base` | `Weapon/BP_BA002_alcn_vls_Base` (-> AITurret_Pawn) |
| `Child/BP_BA002_alcn_uavr_Base` (barrier drone) | **`LiveAIBarrierDrone`** |
| `Child/ChildPool/BP_BA002_alcn_{rflmpool_0..2,uavrpool,uavspool}_Base` | **`LiveAIArrangementObject`** |
| `Others/BP_MP028_dummy_emlmcore_Base` (the core) | `BP_MP075_dummy_Base` -> `OnlineMode/.../AIDummy_Pawn` -> `LiveAIGroundDummy` |
| `Effect/BarrierDrone/BP_alcn_BarrierEffect` | `LiveAlicornBarrierDroneBarrierEffect` |
| `Component/BP_AIActionEventComponent` | `LiveAIActionEventComponent` (`DT_ActionEvent` = `/Game/OnlineMode/DataTables/AI/Action/DT_AIActionEvent`) |
| `Component/BP_AIRunwayManagerComponent`, `Path/BP_AIRunwayPath` | `LiveAIPathRunwayManagerComponent`, `LiveAIRunwayPath` |
| `Weapons/BP_wp_emls_alcn`, `BP_wp_alcn_BarrierDroneBarrier`, `BP_wp_aagun_emitter_Boss_ON`, `BP_wp_ecm_ON` | `LiveEMLBullet_BattleShip`, `LiveRectennaBarrier`, `LiveBulletEmitter`, campaign `BP_wp_ecm_BaseClass` |
| child fighters `BP_OP1014_rflm_ON`, `BP_OP1024_f18f_ON`; SLUAV `BP_OP0074_uavm_ON` | campaign `BP_OP1014_rflm_Base` / `BP_OP1024_f18f_Base`; `BP_OP0074_uavm_Base` -> online `AIPlane_Pawn` -> `LiveAIPlane` |

- The online pawn bases (`OnlineMode/Blueprint/AI/Pawn/AITurret_Pawn`, `AIPlane_Pawn`, `AIDummy_Pawn`,
  `BP_BA002_alcn_HatchPawn`) hold only the usual campaign components:
  `LiveAIFireControlSystemComponent`, `LiveDamagedStateComponent`, `OrcaBasicObjectPlugHolder`, meshes.
  There are no network or replication components in any BP. [V]
- Weapons reused from the campaign: `BP_wp_sam_a0` (ram), `BP_wp_ciws_vessel`, `BP_wp_vls_BaseClass`,
  `BP_wp_ecm_BaseClass`, `LiveEMLBullet_BattleShip` (the class of Mission 10's rail-gun battleship). [V]

### 1.2 Parts, rows and HP [V]
Sources: `DT_NPC_ON` rows -> `DT_NPC_Model_ON` models. HP is the model `MaxHealth`. Component names are in
`alcn_01.ChildNPCComponentNames`.

| component (hull BP) | NPC row -> model | BP | HP | BaseScore | role |
|---|---|---|---|---|---|
| (hull) | `alcn_01` -> `alcn` | N000_00100 | 10, `bCanBeDamaged=False` | - | the submarine. The body cannot be damaged; damage goes to the parts. GameObjectId 5100 |
| `core` | `alcn_core_01` -> `alcn_core` | MP028_dummy_emlmcore | **3125** | 10000 | **`bIsBoss=True`**: destroying it wins (`Core_Destroy`) |
| `railcannon` | `alcn_emlm_01` -> `alcn_emlm` | emlm_Base | 10 | - | main rail cannon (EML). Charge 15 s, extract 5 s, broken motion 5 s |
| `railgun_L/R` | `alcn_emls_02/03` -> `alcn_emls_L/R` (hatch) + child `emls` = `alcn_emls_01` | hatch_emls + emls_Base | 2000 + 2000 | 7500 | twin railguns. Aim 7 s, fire prep 2 s, `BP_wp_emls_alcn` |
| `btank_Front_L/R`, `btank_Rear_L/R` | `alcn_btank_04/03/02/01` -> `alcn_btankfl/fr/rl/rr` | btank*_Base | 1875 each | 5500 | ballast tanks. No weapon; phase-1 objective |
| `ecm` | `alcn_ecm_01` -> `alcn_ecm` | ecm_Base | 500 | 2250 | jammer (`BP_wp_ecm_ON`), phase 3 |
| `vls_L_1/2`, `vls_R_1/2` | `alcn_vls{L,R}_0{1,2}` | vls*_Base | 800 | 2000 | VLS (`BP_wp_vls_BaseClass`). Fires the opening salvo |
| `WP_*_1`, `WP_*_6` (4) | `alcn_hatch{L,R}_0{1,6}` (800) + child `ram` = `alcn_rams_01` | hatch + ram_Base | 800 + 800 | 2000 | SAM launchers (`BP_wp_sam_a0`) |
| `WP_*_2`, `WP_*_5` (4) | `alcn_hatch{L,R}_0{2,5}` + child `aagun` = `alcn_aagun_01` | hatch + aagun_Base | 800 + 800 | 2000 | AA guns (`BP_wp_aagun_emitter_Boss_ON`) |
| `WP_*_3` (2) | `alcn_hatch{L,R}_03` + child `ciws` = **`alsn_ciws_02`** (sic) -> `alsn_ciwssp5` | hatch + ciwsp5_Base | 800 + 450 | 280 | CIWS (p5 variant) |
| `WP_*_4` (2) | `alcn_hatch{L,R}_04` + child `ciws` = `alcn_ciws_01` | hatch + ciws_Base | 800 + 800 | 2000 | CIWS (`BP_wp_ciws_vessel`) |
| `airs0/1/2` | `alcn_rflmpool_01/02/03` -> `alcn_rflmpool0..2` | rflmpool_*_Base | 10 | - | aircraft pools: 4 rflm + 4 f18f / 7 + 2 / 8 rflm (`OP1014_rflm_03`, `OP1024_f18f_03`) |
| `BarrierDrones` | `alcn_uavrpool_01` (50 x `alcn_uav_01` -> `alcn_uav`) | uavrpool + uavr_Base | 6 each | 100 | barrier drones (`LiveAIBarrierDrone` + `LiveRectennaBarrier`) |
| `SLUAVs` | `alcn_uavspool_01` (106 x `OP0074_uavm_01`) | uavspool + `BP_OP0074_uavm_ON` | 6 each | 90 | submarine-launched UAVs (`NLID_0003`) |

- Durability IDs, all Online-only:
  - `NWDID_SubMarine`, `NWDID_SubMarineMainArm` (VLS, railguns), `NWDID_SubMarineCiws`, `NWDID_SubMarineECM`,
    `NWDID_UAV`, `NWDID_Plane`;
  - explosion `NEDID_10` / `NEDID_00`.
- The parts have **no `LuaSetId`** (no behaviour trees) and **no `NpcFCSId`**. Their weapons are set in the BPs
  (`LiveFCSModule_AIControlLegacy`, `LauncherCommon`, `ProjectileCommon`, `LauncherBoneControl`). [V]
- The HP values are tuned for an online co-op squad. Expect to scale them for one player. [I]

### 1.3 Hull data [V] (CDOs of Root / PlnBase / N000)
- **PhaseList** (`ActiveWeapons` per internal phase; `ALCN_AdvancePhase` moves to the next):
  - phase 0: `WP_L/R_2` (AA), `btank_*` x4, `WP_L/R_3` (CIWS), `railgun_L/R`, `vls_L/R_2`, `WP_L/R_6` (SAM)
  - phase 1: `WP_L/R_1` (SAM), `vls_L/R_1`, `WP_L/R_5` (AA)
  - phase 2: `WP_L/R_4` (CIWS), `ecm`
- `TankList` = the 4 btanks. `DiveActionEventName` = `ALCN_Dive`, `SurfaceActionEventName` = `ALCN_Surface`.
- Launch runways (spline child actors on the hull):
  - `AirRunwaySplineNames` = `Runway_Air_L/R_AIPath`;
  - `DroneRunwaySplineNames` = `Runway_Drone_{L,R}{1..4}_AIPath`;
  - `SLUAVRunwaySplineNames` = `Runway_UAV_{L,R}{1..4}_AIPath`.
- `BarrierDronePlacementInfoList` (N000 overrides PlnBase): 10 points around the hull at 70-360 m height.
  Lerp 0.5, HUD delay 2 s, **deploy delay 3 s, barrier lasts 20 s**.
- Diving:
  - underwater offset (0,0,-5600) = **56 m down**; on-water offset (0,0,-78);
  - dive/surface curves `CUR_Dive{Location,Rotation}Curve`, `CUR_Surface*`;
  - sounds `AKE_BA002_alcn_Dive_Play` / `_Surface_Play`; VFX `NS_ex03_alcn_descent0x` / `surfacing0x`.
- Movement:
  - `bIsSea`, `bLargeShip`;
  - `MaximumSpeed` 500, `Acceleration` 200, `RotationSpeed` 15, `MaxGroundRotateAngle` 15;
  - wake trails `NS_alcn_watertrail03_*` (speed 91-150);
  - engine sound row `AKE_BA002_alcn_Sail_Play`.
- Death:
  - `MainBodyDestructionDelayTime` 12 s;
  - DamageEffects / ExtraDamageEffects / PartsDamageEffects (Niagara on sockets `alcn_tank_*`, `alcn_Railgun_*`, ...);
  - destroyed mesh `SK_BA002_alcn_DAM`; `TimeToDeactivateAfterDeath` 120 s.
- Ids:
  - `GameObjectId` 5100-5112, Category 7 / SubCategory 22 (`SubCategory_Alicorn`) / BossCategory 2;
  - `ObjNameID` `ContainerGround_Name_alcn`.
- **The campaign `DT_GameObjectTable` already has rows 5100-5112.** [V] So the alcn models can keep their
  GameObjectIds, unlike ADFX, which uses GameObjectId 1.
- Action templates on the hull's `AIActionEventComponent`: `AlicornLaunchDrone` (`LaunchNum` 10) and
  `AlicornShotRailCannon` (`DelaySec` 12).

### 1.4 Action events (`DT_AIActionEvent`, a `LiveIndexSavedDataTable`, rows -> class) [V]
| row (as named by the EP) | class | setting |
|---|---|---|
| `ALCN_Dive` / `ALCN_Surface` | `BP_AIAE_Alcn_Dive` / `_Surface` : `AlicornDiveSurface` | Operation 0 / 1 |
| `ALCN_LaunchAir_0/1/2` | `BP_AIAE_Alcn_LaunchAir_n` : `AlicornLaunchAir` | LaunchNum 8, PoolSlot 0/1/2 |
| `ALCN_LaunchSLUAV_0/1/2`, `_Dive` | `BP_AIAE_Alcn_LaunchSLUAV_*` : `AlicornLaunchSLUAV` | LaunchNum 8 / 8 / 12 / 8 |
| `ALCN_LaunchDrone` | native `AlicornLaunchDrone` | hull template LaunchNum 10 |
| `ALCN_ShotRailgun_Distributed` / `_Focus` | `BP_AlcnShotRalgun_*` : `AlicornShotRailgun` | TargetMode 1 / 0 |
| `ALCN_ShotRailCannon` | native `AlicornShotRailCannon` | DelaySec 12 |
| `ALCN_AdvancePhase`, `ALCN_OpenCore`, `ALCN_RailCannonDown` | native `AlicornAdvanceInternalPhase` / `OpenCore` / `RailCannonDown` | - |

Names with a numeric tail are FNames with a number (hard rule 17): `ALCN_LaunchAir_0` = `ALCN_LaunchAir` #1.

### 1.5 Assets
- Meshes: `/Game/OnlineMode/Vehicles/Boss/BA002_alcn/`: `SM_BA002_alcn` (+ `_body`, `_bridge`), part meshes
  (tank, vls, ecm, ram, aagun, emls, emlm), DAM variants, 12 hatch skeletons and animations.
- VFX: `/Game/OnlineMode/VFX/Vehicles/Boss/BA002_alcn/Niagara/` (about 50 systems):
  - barrier `NS_uavr_barrier01_omen/02_loop/03_reverb_ON`;
  - lightning `NS_alcn_LiSpark_*`;
  - rail cannon / railgun discharge;
  - wakes, splashes, dive and surface plumes, explosions.
- Sounds: `/Game/WwiseAssets/BA002_alcn/AKE_BA002_alcn_{Dive,Surface}_Play`, `Cannon/*Charge*`,
  `Explosion/*Final*`, `.../SE_Weapon_Online/BA002_alcn/Explosion/*Sinking*`.
  - These Wwise event assets are in **pakchunk0** (base game). [V]
- Everything else is in **pakchunk20** (Online content, about 33k packages). [V]
  It is mounted from the same Paks folder; loading it offline is untested [T]. The ADFX test answers this too.
- The full dependency list (1607 packages, 504 under OnlineMode) is in `build/research/alicorn/fwd_main.txt`.

---------------------------------------------------------------------------------------------------------------------
## 2. Behaviour and what drives it

### 2.1 Who decides what
| behaviour | driver | evidence |
|---|---|---|
| sailing the course | EP `LiveAIPathExecution` on AI paths `Path_Boss0_ALCN_0_0..3` (sea level, ~5.5 km legs, ControlType 1). Native `ALiveSubmarineBase` movement | [V] EP / WD |
| dive / surface | EP `LiveSubmarineOperation(Boss_0_ALCN_0, Diving / Surface)` -> `Execute` 0x1473fa3e0 -> vfunc slot 429 (dive) / 430 (surface) | [V] disassembly |
| launches, railgun, phases, core | EP `LiveAIActionEventExecution(Boss_0_ALCN_0, <row>)` -> `ULiveAIActionEventManager` -> the row's `ULiveAIActionEvent_*` | [V] data, [I] dispatch |
| which turrets may fire | native `PhaseList`, advanced by `ALCN_AdvancePhase` | [V] data, [I] effect |
| turret aim and fire (AA, CIWS, SAM, VLS, ECM) | each part's FCS (`LiveFCSModule_AIControlLegacy`): native auto-targeting like campaign ships | [I] |
| scripted VLS salvos | EP `LiveFireOneShotWeapon(WN_WEAPON_1, Boss_0_ALCN_0_vls_R_1, target)` | [V] EP |
| barrier drones / barrier | `ALCN_LaunchDrone` -> drones fly to `BarrierDronePlacementInfoList` points; `LiveRectennaBarrier` raises after 3 s for 20 s. Native trigger `BossCommon:Alcn_AllDroneDestroyBeforeLaunchBarrier` when all are shot first | [V] data, [I] the barrier's effect |
| railgun lock warning | native `BossCommon:Alcn_LocalPlayerLockedOnByRailgun`; HUD trajectory line `IconTexturePredictedWeaponTrajectoryAlcn*` | [V] strings, [I] |
| part HP events | EP triggers of type **0x56 = ChildDamageByTag** (unit, component tag, Number/HPPercent, value, attacker) on the tags `alcn_btank`, `alcn_btank_FL..RR`, `alcn_core`, `alcn_emls`, `alcn_ram`, `alcn_aagun`, `alcn_ciws`, `alcn_vls`, `alcn_ecm`, `alcn_exc_core`, `ChildAir0/1` | [V] EP |
| dive counter | EP trigger type **0x96 = AlicornDive** (Value = nth dive) | [V] EP |

### 2.2 The EB_002 timeline (EP_EB_002, quoted from `ep_eb002_s.txt`) [V]
```
MissionStart  LiveAIPathExecution  Boss_0_ALCN_0 | NoneSelect | Path_Boss0_ALCN_0_0 | NoneSelect | 120.0 | 0.0 | 2.0 | ObjectSetting | 0.0 | 1 | 0 | true | 5.0 | 0 | 0 | false
MissionStart  LiveSetPlayerMaxAttackerMissiles NONPLANE_MISSILE | 4 ; PLANE_MISSILE | 4 ; LiveChangePlayerMaxAttackersNumExecution 6
MissionStart  LiveSetDisplayProgressGaugeExecution 1 | Gauge_alcn          (online boss HUD gauge)
ElapsedTime_5s  LiveFireOneShotWeapon WN_WEAPON_1 | Boss_0_ALCN_0_vls_{L,R}_{1,2} | Alpha_A_Sea_0_AEGIS_0 / _DESTROYER_0..2 / Alpha_A_Air_0_P1_0..1   (delays 0.2-0.6 s)
Default_MissionStart  LiveDestroyUnitExecution ... (delay 10-11.5 s)   -> the scripted loss of the allied fleet
ElapsedTime_Railgun_1..8 (55,130,155,230,260,330,360,430 s)  LiveCallRemoteEventExecution ShootRailgun
ShootRailgun  LiveAIActionEventExecution Boss_0_ALCN_0 | ALCN_ShotRailgun_Distributed
ElapsedTime_Diving_1..4 (75,175,280,380 s)  LiveSubmarineOperation Boss_0_ALCN_0 | Diving
AlicornDive_1st..4th (type 0x96)  LiveAIActionEventExecution ALCN_LaunchSLUAV_Dive ;
                                   LiveAIPathExitExecution (10 s) ; LiveAIPathExecution Path_Boss0_ALCN_0_n (12 s) ;
                                   LiveSubmarineOperation Surface (33 s, 33 s, 28 s, 28 s) ; respawn points moved
PathFinish_1..3  LiveAIPathExecution  next Path_Boss0_ALCN_0_n
btank_all_hp_75%   ALCN_LaunchSLUAV_0 (1 s)
Btank_all_hp_50%   ALCN_LaunchAir_0 ; ALCN_AdvancePhase (1 s)
btank_all_hp_25%   ALCN_LaunchSLUAV_1 (1 s)
btank_all_destroy  ALCN_LaunchAir_1 ; ALCN_AdvancePhase (1 s) ; ALCN_LaunchSLUAV_1 ; ALCN_OpenCore (5 s)
btank_all_destroy_0  ShootRailgun every 30 s (loop) from now
Radio_core_appear (after radio p2_eb002_reinforcement_aircraft_second)  BarrierDroneLaunch_1st ; ..._2ndOrLater every 70 s (loop)
BarrierDroneLaunch_*  ALCN_LaunchDrone
Core_hp_70%  ALCN_LaunchSLUAV_2 (12 UAVs) ;  Core_hp_30%  ALCN_LaunchSLUAV_0
railgun_destroy_all  ShootRailgun trigger off
Core_Destroy  LiveFinishBossBattleExecution SwitchPhase | GameFinish | 1 ; ALCN_RailCannonDown ; drones and railgun off
RemainingTime_6m/4m/2m/1m/0s ... Timeup -> LiveFinishBossBattleExecution | GameFinish | false ; MISSION_FAILED
Debug_* triggers: ALCN_OpenCore, ALCN_LaunchDrone, ALCN_ShotRailCannon, ALCN_AdvancePhase, Dive, Surface, ALCN_LaunchSLUAV_0, ALCN_LaunchAir_0, ALCN_ShotRailgun
```

The fight in short:
1. Phase 0: the sub sails its course and dives about every 100 s (56 m down for 28-33 s, launching 8 UAVs, then
   surfacing on the next path). Its railguns fire on a timer. Its 4 ballast tanks are the objective.
2. At 50 % tank HP it launches 8 fighters and moves to phase 1.
3. With all tanks dead: more fighters, phase 2, the core opens 5 s later, and the railguns fire every 30 s.
   Barrier-drone waves come every 70 s.
4. Destroying the core (3125 HP) wins. Then the rail cannon drops.

`ALCN_ShotRailCannon` is only fired by a debug trigger. The rail cannon's charge/shot is probably part of `OpenCore` /
the hull's template (DelaySec 12) natively [I].

### 2.3 World data (WD_EB_002) [V]
- **Unit `Boss_0`**:
  - faction 2, `bIsSpawnFromStart` true, spawn point (138117, 10907, 150000);
  - area radius 6000 m, altitude 100-3000 m.
- **Its one AI object `Boss_0_ALCN_0`**:
  - `MissionNpcID alcn_01`, `AIObjectClass None` (the class comes from the NPC row's model);
  - SpawnPoint (145356, 16423, **0**), so it sits at sea level;
  - `bUseCoordinateSync`, `bIsInvincibleFromAI`, `bIsLanding`, `bIgnoreMeshOptimize`, LevelId 200.
- **`ChildAIObjectDescs`**: one per component (30), each with `ComponentFieldName` and `Class = obj(import)`.
  The pools carry `GrandChildrens` (`Air0..`, `Drone0..49`, `SLUAV0..105`). 225 ComponentFieldName entries in total.
- 4 alcn paths `Path_Boss0_ALCN_0_0..3` plus 4 unit paths `Path_Boss0_0..3`. Player starts, respawn points, allied
  fleet `Alpha_A_Sea` / `Alpha_A_Air`.
- Imports: the 41 alcn/child BPs, plus the allied ship BPs and the campaign damage params.
- NPC table: `/Game/OnlineMode/DataTables/AI/NPC/Mission/DT_NPC_Mission_EB_002_ON`. Its rows `alcn_01`, all alcn part
  rows, `alsn_ciws_02`, `OP0074_uavm_01`, `OP1014_rflm_03`, `OP1024_f18f_03`, ... are plain NpcId rows.
- The online WD parses with the campaign `LiveWorldData` schema, so the struct is the same. [V]
- Map `PL_EB_002` = `ENV_FreeFlight_Nimbus/Ocean/OCE_ENV_Terrain` + sky `SL_EB_002_Lit_Cloudly`. Game mode
  `BP_EmergencyCallBossBattleGameMode`, spawner `OnlineMode/.../BP_DefaultUnitSpawner`.

---------------------------------------------------------------------------------------------------------------------
## 3. Offline feasibility

### 3.1 Native checks
- **`LiveSubmarineOperation::Execute` 0x1473fa3e0** (vtable 0x14c67d530): [V]
  - finds the unit by name in the event context, checks IsA `ALiveSubmarineBase` (StaticClass 0x146d096c0),
    then calls vfunc +0xD68 (Diving) or +0xD70 (Surface);
  - **no network or game-mode checks**.
- **Action-event manager**: [V]
  - getter 0x1471d4e60 = `ALiveGameMode::GetAIActionEventManager`: lazy `NewObject<ULiveAIActionEventManager>`
    stored at GameMode+0x730, no mode check;
  - `AIActionEventManager` is a property of the base `LiveGameMode`, so `LiveCampaignGameMode` /
    `LiveOfflineGameMode` have it (usmap);
  - the component init 0x147c59d60 requires only `World->AuthorityGameMode IsA ALiveGameMode` (0x146de0b50);
    then it caches the manager (+0xF8) and registers the owner `ALiveAIGameObject`, passing the owner's network
    object id (owner+0xED0 -> +0x28) when there is one.
- **Network object**: [V]
  - 0x147e3a2a0 creates the Alicorn's `ULiveNetworkAIAlicorn` (fallback class 0x146f0a410) at +0xED0 when it is null,
    unconditionally, as campaign AIs do with their `ULiveNetworkAI*` objects;
  - the dive action (0x147e35190) calls the send helper 0x1474a85d0 after a null/IsA check;
  - whether that helper is harmless offline is [T]. Helios had the same shape and works offline.
- **`LiveFinishBossBattleExecution`** (Execute 0x1473e9050, vtable 0x14c6895a0): acts only when the authority game
  mode IsA `ALiveEmergencyCallBossBattleGameMode` (0x146e209f0); otherwise it does nothing. Do not use it. [V]
- Not found statically: `LiveAIActionEventExecution::Execute`.
  - Its vtable does not match the event-node pattern used by `vtscan2.py`.
  - Some constructors in this exe jump into protected code (0x146dfb5b0 -> 0x158db7e10), so constructor-based vtable
    lookup fails for some classes. [V]
- No campaign EP (198 pulled) uses ChildDamageByTag (0x56), AlicornDive (0x96), BossCommon (0x97),
  `LiveAIActionEventExecution` or `LiveSubmarineOperation`. They have never been exercised offline. [V]

### 3.2 Blockers and risks
| # | issue | severity | handling |
|---|---|---|---|
| 1 | pakchunk20 (`/Game/OnlineMode/...`) loadable in an offline session | must check [T] | the ADFX test answers it. Probe: `LoadAsset_Blocking` (hard rule 9) on `BP_BA002_alcn_N000_00100` |
| 2 | NPC rows are in `DT_NPC_ON` / `DT_NPC_Model_ON`; the campaign spawner reads `DT_NPC` / `DT_NPC_Model` | data | copy rows into Survival's DT_SV_NpcRows / DT_SV_ModelRows; `main.lua` AddRows them at the main menu (the ADFX path), **before the level loads** (hard rule 20) |
| 3 | online-only IDs: `NWDID_*`, `NEDID_10` (durability), and for the child fighters `NFID_*` FCS, `NLID_0003` (uavm LuaSet) | data | AddRow the `DT_NPC_WeaponDurability_ON` / `DT_NPC_ExplosionDurability_ON` rows into the campaign tables (same row structs `LiveWeaponDurabilityDataTable` / `LiveExplosionDurabilityDataTable` [V]), **or** remap to campaign IDs (`LargeShip_WPDur_000`, `test_NPC_ExpDur_000`). Point the pools' `ChildNPCId` at Survival's own fighter rows (campaign FCS, `NLID_SV_Fighter`, hard rule 22) |
| 4 | `OP1014_rflm_03`, `OP1024_f18f_03`, `OP0074_uavm_01`, `alcn_*`, `alsn_ciws_02` do not exist in campaign `DT_NPC` | data | as row 2. `NLID_0012/0022` exist offline; `NLID_0003` does not [V] |
| 5 | the world-data desc: 1 hull + 30 parts + 195 pooled children, `Class` imports of about 45 BP packages | build | copy the `Boss_0` UnitDesc from `WD_EB_002` into `WD_SurvivalMode_global`: imports and container header (hard rule 7), set LevelId to Survival's, `bIsSpawnFromStart` false, new SpawnPoint in Comona's open sea |
| 6 | 195 pooled aircraft/drones are spawned with the hull (Arrangement pools) | perf | test it. A first test can drop `BarrierDrones` / `SLUAVs` / `Airs*` from the child list (and from `alcn_01.ChildNPCId`) [I] |
| 7 | ChildDamageByTag / AlicornDive / BossCommon triggers offline | [T] | not needed: Survival's Lua can poll part health/alive state and fire `SV_Event` remote events |
| 8 | the network send on dive (0x1474a85d0) offline | low [T] | first test: dive/surface |
| 9 | HP tuned for an online squad (tanks 4 x 1875, core 3125, railguns 2 x 2000) | balance | scale the model `MaxHealth` in Survival's copies, or `MaxHealthDifference` / coefficients in the NPC rows |
| 10 | sea area: the hull is about 300+ m long, dives 56 m, and needs about 6 km straight legs of open water | map | Comona has sea (Mission 22's enemy fleet sits offshore at about +5..7 km x). Keep the paths away from the island and shallows [I] |
| 11 | online HUD gauge (`LiveSetDisplayProgressGaugeExecution`), boss-battle end, IGC cutscenes (`BP_IGCAIBoss_BA002_Alcn`), radio `DT_Rdo_EB_002` | n/a | skip them. Survival has its own HUD and callouts |
| 12 | event names with numeric tails (`ALCN_LaunchAir_0`, `Path_Boss0_ALCN_0_1`, `Boss_0_ALCN_0`) | build | store them with `survival_events.fname` (hard rule 17) |

### 3.3 What Survival must copy or add
1. **Model rows** (DT_SV_ModelRows; `main.lua` adds them to `DT_NPC_Model`): every `alcn*` / `alsn_ciwssp5` row of
   `DT_NPC_Model_ON` (35), unchanged: their soft BlueprintClass paths stay in `/Game/OnlineMode`, and their
   GameObjectIds exist in the campaign `DT_GameObjectTable`. Plus `OP0074_uavm` if the SLUAVs are kept.
2. **NPC rows** (DT_SV_NpcRows -> `DT_NPC`): the `alcn_*` rows (about 33) plus `alsn_ciws_02` and the child aircraft
   rows (or remaps), with durability IDs fixed as in 3.2 row 3.
3. **Durability rows** (if not remapped): `NWDID_SubMarine`, `NWDID_SubMarineMainArm`, `NWDID_SubMarineCiws`,
   `NWDID_SubMarineECM`, `NWDID_UAV` and `NEDID_10` into the campaign durability tables at run time.
   These are shared stock tables: AddRow only, never override.
4. **NPC-mission rows** (`DT_SV_NpcMission`, built by `build_npc_table`): copies of `DT_NPC_Mission_EB_002_ON`'s
   rows, plain values with no object references, like `NPC_IMPORT`.
5. **World data**: the `Boss_0` UnitDesc + `Boss_0_ALCN_0` desc tree, renamed (e.g. `SV_Alcn` / `SV_Alcn_ALCN_0`).
   Also at least one sea path copied from `Path_Boss0_ALCN_0_0` and moved to Comona, and the about 45 BP imports
   (WD_EB_002 import entries -3..-41 and their duplicates) in the WD and the container header.
6. **EP records** (survival_events.py), each fired by a remote event `RE_SV_Alcn*` that `main.lua` calls with
   `SV_Event`:
   - `LiveAIPathExecution` (copy of the MissionStart record), `LiveAIPathExitExecution`;
   - `LiveSubmarineOperation` Diving / Surface;
   - `LiveAIActionEventExecution` for `ALCN_LaunchAir_0/1/2`, `ALCN_LaunchSLUAV_0/1/2/Dive`, `ALCN_LaunchDrone`,
     `ALCN_ShotRailgun_Distributed` / `_Focus`, `ALCN_AdvancePhase`, `ALCN_OpenCore`, `ALCN_ShotRailCannon`,
     `ALCN_RailCannonDown`;
   - optional VLS salvos: `LiveFireOneShotWeapon WN_WEAPON_1 | SV_Alcn_ALCN_0_vls_R_1 | <target>`.
   New exec classes need their script-class imports in the EP (an import-map entry only, AIRFIELD_SUPPLY.md).

---------------------------------------------------------------------------------------------------------------------
## 4. Plan

### 4.1 Safe first in-game spawn test (one build, no round logic)
1. **Probe (Lua only, before any build change):** at the main menu,
   - load `/Game/OnlineMode/Blueprint/AI/Actors/Submarine/alcn/BP_BA002_alcn_N000_00100` and
     `/Game/OnlineMode/DataTables/AI/NPC/DT_NPC_Model_ON` with the hard-rule-9 path, and log success.
     This answers blocker 1.
   - In Survival's level, log `FindFirstOf("LiveCampaignGameMode")` (or the mode class Survival actually runs) and
     its `AIActionEventManager` (normally null until a component registers).
2. **Data rows** (as in 3.3, items 1-4), cut down for the test:
   - copy the `alcn_*` model and NPC rows;
   - remap durability to `LargeShip_WPDur_000` / `test_NPC_ExpDur_000` (fewer moving parts);
   - remove the three pool families from `alcn_01.ChildNPCId` / `ChildNPCComponentNames` (keep hull, core, rail
     cannon, railguns, tanks, ecm, VLS, hatches).
3. **World data:**
   - add `SV_Alcn` (from `Boss_0`) with only the 27 kept child descs, `bIsSpawnFromStart` false, faction 2;
   - SpawnPoint in open sea about 15 km off the airfield (Mission 22 enemy-fleet waters), Z 0;
   - add the BP imports and container-header entries; verify with `tools/checks/verify_headers.py`.
4. **Spawn:** a debug key in `main.lua` calls `SV_Spawn("SV_Alcn", x, y, 0, yaw)` then `SV_LogUnits`.
   Pass criteria:
   - no crash, and the hull appears on the water with its wake;
   - parts show as targets, turrets/SAMs/CIWS engage the player in range, part kills register;
   - the hull stays invulnerable.
   Log the hull's `+0xED0` network object (expected: present but inert).
5. **Second build (EP):** add `RE_SV_AlcnPath`, `RE_SV_AlcnDive`, `RE_SV_AlcnSurface`, `RE_SV_AlcnRailgun`,
   `RE_SV_AlcnPhase` records and test each from a debug key. Watch UE4SS.log for crashes on dive (blocker 8) and on
   the first ActionEvent (manager creation).
6. Only then add the pools back (`Airs*` first, then `SLUAVs`, then `BarrierDrones`) and test launches
   (`ALCN_LaunchAir_0`, `ALCN_LaunchSLUAV_0`, `ALCN_LaunchDrone`), watching frame time at spawn.

### 4.2 Full special round (after 4.1 passes)
- A round state machine in `main.lua` reproduces EB_002, shortened for one player:
  - spawn it through the portal or offshore;
  - `RE_SV_AlcnPath` on spawn;
  - railgun (`ALCN_ShotRailgun_Distributed`) every about 60-75 s;
  - dive every about 100 s: `Dive` -> `ALCN_LaunchSLUAV_Dive` -> path exit, then next path 12 s later -> `Surface` 30 s
    later.
- Tank-HP thresholds come from Lua polling (sum of the 4 btank HP):
  - 75 %: `LaunchSLUAV_0`;
  - 50 %: `LaunchAir_0` + `AdvancePhase`;
  - 25 %: `LaunchSLUAV_1`;
  - 0: `LaunchAir_1` + `AdvancePhase` + `OpenCore` (5 s), railgun every 30 s, `LaunchDrone` every 70 s.
- Core thresholds: 70 %: `LaunchSLUAV_2`; 30 %: `LaunchSLUAV_0`. Core dead: `RailCannonDown`, round won, credits.
- Survival's own HUD shows tank/core HP and the railgun warning. Radio callouts can reuse the `DT_Rdo_EB_002` keys
  if their audio plays offline [T].
- Balance: scale part HP (start at about 30-40 % of online values) and fighter counts with difficulty presets.

### 4.3 Open questions
- Does `LiveAIActionEventExecution` resolve its unit and action offline? (Find its Execute: trace a
  `ULiveAIActionEventManager` call from the component, or hook it at run time.)
- Does the rail cannon fire by itself after `OpenCore`, or only on `ALCN_ShotRailCannon`?
- Does the Arrangement pool spawn its 50/106 children at once or on launch?
- Does the `LiveRectennaBarrier` make the hull or core immune while it is up?
