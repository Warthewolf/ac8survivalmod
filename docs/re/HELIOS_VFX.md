# Helios barrage and spawn VFX (research backlog 9 and 10, 2026-10-22)

Game build: AceCombat8.exe of 2026-09-29. Addresses are for that build (use them only to find signatures).
Scratch dumps: `build/research/helios/` (EP dumps of every online-mode EP in `onep/`, of M010/013/018/020/030 in
`ep/`, disassembly in `firehelios_exec.txt`, `helios_funcs.txt`). Nothing here touches online services: everything is
read from the local paks (pakchunk20 holds OnlineMode and ships with the game, mounted at startup like the others).

## 1. What Helios is

Helios is not a missile launcher. It is an area-bombardment "system object" from Online Mode: one event node
fires a timed chain of huge heat-bomb (thermobaric) blasts. The first blast lands where the target was when it fired.
Each later blast lands 4.4-8.8 km from the one before. A warning shows (emergency alert sound + minimap curve)
before each blast hits.

| piece | asset / class | notes |
|---|---|---|
| event node | `ULiveFireHelios` (ULiveCustomEventExecution, Execute = vtable slot 87 = 0x1473fabe0) | no UPROPERTY args: args are read natively from the record (see 1.1) |
| launcher unit | `ALiveSystemObjectHeliosArea` < ALiveAIArrangementObject < ALiveAIGameObject. BP `/Game/OnlineMode/Blueprint/AI/Pawn/SystemObject_HeliosArea` (`SystemObject_HeliosArea_C`) | a spawnable world-data AI object, invincible ground "gimmick" |
| its CDO | ChildClass = `wp_HeatBombExplosion_C`, DivLine (default), MinDistance 440000, MaxDistance 880000 (cm), DelayTime 0.1 s, GameObjectCategory 9 = ObjectCategory_Helios, KillCamera 10 = Gimmick_Helios, ObjNameID `Container_Ground_Helios_Name`, OverlapCollision sphere 32000 cm | ctor sets count (+0x27c0) = 6 |
| blast | `/Game/OnlineMode/Blueprint/Weapons/Explosion/wp_HeatBombExplosion` (ALiveHeatBombExplosion < ALiveExplosion < ALiveWeaponBase), parent BP `/Game/Blueprints/Weapons/BOMB/HEATBOMB/BP_HeatBombExplosion_BaseClass` (offline, Mission 9 cloud bomb sound `OBJ_M09_CLOUDBOMB_EXP`) | imports `NS_ms17supsExplosion01_ON` (Niagara), `HUD_ALERT_Emergency_SE_Play/Stop` (Wwise), `/Game/Blueprints/Weapons/Explosion/Data/CUR_EmergencyMiniMap` |
| native fields | LiveHeatBombExplosion: ImpactTimer, ImpactPointLight, ActionPhaseCurve, HeliosImpactSound, HeliosALERTPlay/Stop, AvoidRangeType. LiveExplosion: DamageRadiusUUSquared, bDamageToAir/Ground, DamageDuration/Interval, shockwave camera shake | damage values come from the weapon tables (not resolved, see open questions) |
| feedback assets (offline, pakchunk0) | `Blueprints/Vehicle/PLAYER/Camera/CameraShake/BP_CamShake_{BombImpactHelios[Loop][_Cockpit], DamageHelios[_Cockpit]}`, `CUR_CamShake_HeliosExplosionDistanceScale`, `Blueprints/Vibration/Curve/CUR_VibrationHelios{Damage,BombImpactLoop}`, kill cam `Blueprints/InGameCamera/OnlineMode/CameraAnim/KillCamera/CAS_Killer_G_Helios` | enums ELiveCameraShakeType::BombImpactHelios*, ELiveVibrationType::Helios* |
| network twins (online only) | `ULiveNetworkAIHelios` (< LiveNetworkSubmarineBase), message `FLiveMessageSystemObjectHelios` (Strix `jp.co.soft_gear.strix...`) | only used to replicate to other players, see 1.3 |
| lead, not followed | `ALiveBeaconTrackingMissile` (< LiveMissile) has HeliosRadioForeWarnTime / FadeTime / MaxWaitTime, FirstTarget, SpawnWeaponClass: probably a weapon that calls Helios down on a beacon | no asset found by name |

NPC rows (all in Online-Mode tables only, none in the offline ones):
- `DT_NPC_Mission_EB_001_ON` / `DT_NPC_Mission_PvPvE_002_ON` (LiveNpcMissionDataTable): row `helios_01`, NpcId `helios_01`.
- `/Game/OnlineMode/DataTables/AI/NPC/DT_NPC_ON` (LiveNpcDataTable): `helios_01` -> ModelId `helios`,
  ExplosionDurabilityId `NEDID_00`, GameObjectSubId 2.
- `/Game/OnlineMode/DataTables/AI/NPC/DT_NPC_Model_ON` (LiveModelDataTable): `helios` -> BlueprintClass soft
  `/Game/OnlineMode/Blueprint/AI/Pawn/SystemObject_HeliosArea.SystemObject_HeliosArea_C`, MaxHealth 10,
  GameObjectId 528, name `ContainerGround_Name_Helios`.
- Offline `/Game/Datatables/AI/NPC/DT_NPC` and `Model/DT_NPC_Model` have no helios row.

### 1.1 Stock uses (the only two)
`OnlineMode/Maps/EmergencyCall/EB_001` (boss AIAS) and `OnlineMode/Maps/PvPvE/PvPvE_002`.

World data: a unit with one AI object, MissionNpcID `helios_01`, Faction 9 (Other), bIsInvincibleFromAI, bIsLanding,
bIsSpawnFromStart. EB_001: `B_Helios` (AI object `B_Helios_0`) at (2793853, -56639, 2580), area 100 m. PvPvE_002:
`Helios0` (AI object `Helios1`) at (2291631, -2355485, 0), area 4000 m. The launcher's position doesn't matter.
Blasts are placed around the target, with no projectile flight.

Event records (ep_dump):
```
EB_001   TRIG Elapsed_13s  type=20 (elapsed time) {0f: 13}  life=1
         EXEC Elapsed_13s  LiveFireHelios  delay=6  {10: 10.0} | {0e: None} | {09: Mark_Helios_0} | {0f: 9}
         EXEC Elapsed_13s  LiveDestroyUnitExecution delay=30 {0a: NoneSelect} | {02: B_Helios_0} | {01: NoneSelect} | {10: 0} | {10: 0} | {11: false}
         TRIG FiringHelios type=2f mon=[Elapsed_13s] -> radio p1_eb001_helios_launch (0 s), _Impact_1 (10 s), _explosion/_after (21 s)
PvPvE_002 TRIG ElapsedTime_Helios1st type=20 {0f: 165}
         EXEC ElapsedTime_Helios1st LiveFireHelios {10: 10.0} | {0e: HeightThreatLevelPlayer} | {09: CenterMiddle0} | {0f: 6}
         EXEC ElapsedTime_Helios2nd LiveFireHelios {10: 10.0} | {0e: None} | {09: CenterMiddle0} | {0f: 6}
         radio pvpve_002_helios_start / _approach / _again, _explosion 10 s after each fire
```
Args, in order (Execute reads them from exec+0x58/0x5c/0x60/0x68):
1. float (type 10): time to impact in seconds (10.0). It is stored at helios+0x2890.
2. enum ELiveHeliosTargetType (type 0e): `None` = aim at the marker, `HeightThreatLevelPlayer` = aim at a player.
3. marker name (type 09, MarkActorDescList). Used when the target type is None.
4. int (type 0f): number of blasts (6 or 9). It is stored at helios+0x27c0.

### 1.2 How it fires (disassembly)
- `LiveFireHelios::Execute` 0x1473fabe0 walks an actor list of the event context (r9+0x38) to find the first actor that
  IsA ALiveSystemObjectHeliosArea (StaticClass 0x14701c9e0). If none is spawned, nothing happens.
  It calls `Setup(helios, count, time)` 0x147d99920. Then it picks the target:
  - HeightThreatLevelPlayer: 0x1473fb3a0 takes the player list (manager+0x138), sorts it by "height threat level"
    (0x147d296a0), and picks a random player among the top level. With one player, that is always the player.
  - otherwise the marker actor, looked up by name in the context's map at +0xa8.

  Then it calls `SetTarget(helios, actor)` 0x147d98f70.
- Setup: shuffles DivLine sector indices, keeps `count`, and gives each a random distance in [Min, Max]Distance.
- SetTarget: the centre is the target's root location at that moment, so it is a snapshot and does not track.
  A null target uses the combat-zone box centre. Point 0 is the centre. Point i = point i-1 + (sector angle
  360/DivLine x index) x distance. It sets the armed flag (+0x27e0).
- Tick (vtable slot 279, 0x147d98e60): while armed, it fires one blast every DelayTime (0.1 s) with
  `FireShot(helios, i)` 0x147d99410, which spawns ChildClass at point i. When all blasts are done, it disarms.
  Slot 334 (0x147d98e30) resets the object.

### 1.3 Does it work offline?
Very likely yes:
- Execute, Setup, Tick and FireShot contain no network checks.
- The only online code is at the end of SetTarget. It reads `GameInstance+0x928`, a network manager:
  - If the state from 0x1474ca370 is 0xC8, it skips the send.
  - Otherwise it calls 0x147d99c80, but only if this machine is the session master.
  - That is the replication send (FLiveMessageSystemObjectHelios). The local arm happens either way.
- Risk: SetTarget dereferences `GameInstance+0x928` without a null check. If that manager doesn't exist offline, it
  crashes. Survival's runtime can read the pointer before the first barrage. It is almost certainly created at boot,
  because the lobby needs it.
- All the assets are local (pakchunk20 / pakchunk0).

## 2. Offline launchers (M010, M013, M018, M020, M030)
None of the offline missions use LiveFireHelios, LiveStaurosShot or LiveStaurosALCMShot. Stauros (cruise missiles against
cities, `ALiveAIStauros`, `ALiveAICruiseMissile`) appears only in the Chandelier boss's action events (online).
Offline barrages are all `LiveFireOneShotWeapon` / `LiveSpinUpWeapon` aimed at a unit, a dummy, or `Player`.
Args: `{0e: WN_WEAPON_n} | {01: firing AI object} | {0b: target AI object or Player} | {0a: target group} | {11: false} | {0d: ""} | {11: false}`.

| mission | launcher | target | portable? |
|---|---|---|---|
| M030 | Grifn's micro-missile hatch `B_Obj_00_Ship0_Grifn_0_MmslctHatch`, WN_WEAPON_1/2 -> `Player` (RemoteEvent_Fire_Mmslct, Fire_Mmslct_Multiple; canisters `B_Unit_00_MicroMissileCanister0`, NPC `mmslct_ms30[_First]`) | player | no, it is a child of the Grifn boss and its FCS (LiveFCSModule_LauncherSpawner_Grifn) |
| M020 | land battleship `B_Obj_01_ldbs2_0_SubCannon_{L1,L2,R1,R2}` -> `Player` (Boss_AllAttack), EXSAM -> AttackDummy_N | player | needs the whole ldbs2 boss unit |
| M010 | `rikusen0_MainCannon2/3` (GR036) -> aircraft / dummies; `A_Obj_00_Ground_5_m109_N` (howitzers) -> DefaultAIObjectN | aircraft / ground | the howitzers are ground fire only |
| M013 | C-130 Rapid Dragon pallets `E_Obj03_0x_Air0_c130_0_Rpdn01` (WN_WEAPON_1), cruise missiles NPC `lacm_01/02`, `rpdnb/rpdnc_0x`; `LiveAIRpdnMissileSetTargetExecution {01: ..._Rpdn01_Missile0} | {01: E_Obj03_ALCM_Finish0_0}` | ground dummies only (AI-object target) | slow land-attack missiles, not air |
| **M018** | "SuperLongCannon": dummy unit with AI objects `E_Obj_00_Dummy0_DummyCannon_{SpinUp,ForPlayer,ForDummy,ForPlayer_OverAltitude}`, NPC `ldbs3_MainCannon_LongRange_ms18_ForPlayer` / `_ForDummy` (BP `/Game/Blueprints/Weapons/LdbsMainGun/BP_GR038_ldbs3_MainCannon_LongRange_ms18_ForDummy`), fires WN_WEAPON_1/2 bursts (delay 0/1/2 s) at `A_Obj_00_Dummy_Player_Formation_Follower_0`, a relative dummy (`Adummy_relative_rotation_ms18_01`) that follows the player; warning `LiveSetRailgunAlertEnable` | the player's position | the best offline-only alternative (offline NPC rows exist) |

## 3. Recommendation: Helios barrage on random rounds

**Port the real Helios** (route A). It is the actual feature, and it is a small, self-contained object. It needs 4
pieces, all following existing Survival patterns:
1. **World data** (`build_survival.py`): add a unit desc `SV_Helios` to WD_SurvivalMode_global.
   - Copy it from WD_PvPvE_002 `Helios0`: 1 AI object, MissionNpcID `helios_01`, Faction Other,
     bIsInvincibleFromAI, bIsSpawnFromStart **explicit 0** (README note).
   - Put it far from the airfield, e.g. 30 km out.
   - Imports: the blueprint is reached through the model table's soft path, so no hard import is needed.
     EB_001's WD imports none (check with a test).
2. **NPC rows at run time** (shared tables are never overridden): three rows, copied from the `_ON` tables into
   `DT_SV_*` tables and added with AddRow (pinned, hard rule 10):
   - `helios_01` into M22's mission NPC table (the world data's NpcMissionDataTable)
   - `helios_01` into `/Game/Datatables/AI/NPC/DT_NPC`
   - `helios` into `/Game/Datatables/AI/NPC/Model/DT_NPC_Model`
3. **Event package** (`survival_events.py`): give `SV_Helios` an "appeared" trigger (type 23, like SV_FlightUp_NN) that
   runs:
   - `LiveFireHelios {10: 10.0} | {0e: HeightThreatLevelPlayer} | {09: NoneSelect} | {0f: 6..9}`, delay ~3 s.
     The exec record and its `/Script/Live.LiveFireHelios` class import must be copied from EP_PvPvE_002, because
     Mission 22 has no template.
   - Optionally camera shake / radio, and a flag so Lua knows it fired.
   - `LiveDestroyUnitExecution SV_Helios_0` 30 s later (as EB_001 does). Or let SV_Spawn recycle it, but it is
     invincible, so it needs an explicit destroy or the SV_Spawn -3 path will refuse.
4. **Lua** (`main.lua`): on a random round (config: chance, count, min round, Casual off), call
   `SV_Spawn('SV_Helios', x, y, 0, 0)` mid-round. Spawning it fires the barrage.

   Guard against targeting the airfield indirectly:
   - Don't fire while the player is within ~10 km of Comona Airport.
   - Don't fire while the player is landed or in the shop. HeightThreatLevelPlayer always targets the player,
     but a blast near the airfield could still hit ground units if bDamageToGround is set.

Fallback if test 1 crashes or nothing fires:
- Route A2: native `SV_Helios(count, time)`. Find the spawned HeliosArea (FindFirstOf), then call
  Setup 0x147d99920(helios, count, time) and SetTarget 0x147d98f70(helios, playerPawn) by signature. This skips the
  event node but runs the same code.
- If the network-manager dereference is the problem, call Setup only and set the target fields by hand. Not worth
  doing before a test.

Offline-only alternative (route B): Mission 18's SuperLongCannon. A dummy cannon AI object
(`ldbs3_MainCannon_LongRange_ms18_ForPlayer`) fires bursts at a relative dummy that Survival keeps on the player.
Survival already teleports `Unit_dummyN0` onto the player every 6 s, so that dummy can be the target. Add
`LiveSetRailgunAlertEnable` for the warning. It uses offline rows and BPs only, but it is a railgun, not a bombardment.

## 4. VFX: portal burst for specials (and Helios)

### 4.1 How stock events show VFX
- World data `VFXActorDescList` (LiveVFXActorDesc): Name, Location, Rotation, bPlayFromStart, VFXActorClass
  (a `BP_MO*` actor BP), Tags, AttachParentAIObjectName.
- Node `LiveSetActiveVFXExecution {05: VFX actor name} | {0a: tag group} | {11: true/false}`. Examples:
  - M010 `PreRadio_01_approach_Lastpoint_1`: `{05: BlastingFailure_VFXActor_0} | {0a: NoneSelect} | {11: true}`, delays 1-4 s.
  - M010 `PostIGCImmediately_Ms100020`: `{05: NoneSelect} | {0a: DownSmoke_VFX} | {11: true}` (by tag).
  - It is used in 17 missions, Mission 22 included (`VFX_AreaB_Dummy`, `VFX_ControlRoomDummy0`), so a Survival
    template exists.
- The stock teleport nodes (`LiveActorTeleportExecution`, `LiveAIPathTeleportBy{Point,Distance}Execution`) only move
  actors. They have no built-in effect, and none teleports a VFX actor (arg type 04 is always NoneSelect in stock).
  So a stock "portal" = teleport/spawn + a separate VFX actor at that spot.
- `ALiveSystemObjectVFX` (VFXTemplate, Decal, PostProcess, LensEffectActor, SoundEvent, bAutoEnable) is a spawnable
  VFX "unit" class. No stock BP or NPC row uses it, so a new BP would be needed. Not recommended.
- Event camera (Milestone 6 item): `LiveEventFocusCameraExecution {01: focus AI object} | {0a} | {01} | {0a} | {0d: camera setting, e.g. LookAt_Event_Camera_ms10-03} | {11: false} | {11: false}`
  (M010 `EventFocusCamera_1`: focus `rikusen0_Thruster_L1`, then the same with NoneSelect 10 s later to release). It is used in
  18 missions.

### 4.2 Run-time spawning from Lua (recommended for the portal)
- `UNiagaraFunctionLibrary::SpawnSystemAtLocation(WorldContextObject, SystemTemplate, Location, Rotation, Scale,
  bAutoDestroy, bAutoActivate, PoolingMethod, bPreCullCheck) -> UNiagaraComponent` is a reflected UFUNCTION
  (refl.py: params at 0x14dd22450). So are `SpawnSystemAttached` and `...WithParams`.
- Cascade: `GameplayStatics::SpawnEmitterAtLocation`.
- Actor BPs: `GameplayStatics::BeginDeferredActorSpawnFromClass` + `FinishSpawningActor`.
- Wwise sound: `AkGameplayStatics::PostEventAtLocation(AkEvent, Location, Orientation, WorldContextObject)`.
  UE `PlaySoundAtLocation` won't play the game's Wwise events.
- Lua: load the NS with MakeSoftObjectPath -> Conv_SoftObjPathToSoftObjRef -> LoadAsset_Blocking (hard rule 9).
  Then call it on `StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")`, from the game thread,
  with the same x, y, z that SV_Spawn gets. This needs no build-time changes, works anywhere the special spawns,
  and can fire 0.3-0.5 s before SV_Spawn so the special appears inside the flash.

Candidate systems (all local; size = zen package bytes):

| asset | look (from name / source) | user params |
|---|---|---|
| `/Game/VFX/Vehicles/Weapon/UAV/Barrier/NS_UAVBarrierOneshot` | M23 Barrier UAV shield burst (sphere) | `User.BarrierDamageRadiusMeters` |
| `/Game/VFX/Vehicles/Weapon/UAV/Barrier/NS_UAV_BarrierLost0001` | barrier collapse | `User.BarrierDamageRadiusMeters`, `User.ScaleRGBMultiply` |
| `/Game/OnlineMode/VFX/Vehicles/Boss/BA002_alcn/Niagara/NS_uavr_barrier01_omen_ON` / `02_loop_ON` / `03_reverb_ON` | Alicorn barrier: omen -> loop -> reverb, a natural open / hold / close portal sequence | none |
| `/Game/VFX/Mission/Mission023/NS_ms23FarFlash` (actor `/Game/Blueprints/VFX/MapObj/MO102_Explosion/BP_MO102_ms23RODFlash`) | M23 orbital-rod far flash | none |
| `/Game/VFX/Mission/Mission009/AirExplosion/NS_ms09FarFlash` (actor `BP_MO102_ms09FarFlash`) | far flash | `User.CamOff`, `User.ExpVelocityMin/Max`, `User.SystemLocation_Offset` |
| `/Game/OnlineMode/VFX/Vehicles/Boss/BA004_chnd/Niagara/NS_BA004_chnd_Shockwave_ON` | Chandelier shockwave | RandomSeed |
| `/Game/VFX/Mission/Mission027/CoreDestroy/NS_MGF_CoreDest1st_CoreElectricPlasma` (+ `...PlasmaImpact`) | electric plasma (587 KB, heavy) | RandomSeed |
| IGC shockwaves `/Game/VFX/IGC/Ms25/Ms250010/NS_IGCVFX_Ms250010_ShockWave001/002`, `Ms29/Ms290030/NS_IGCVFX_Ms290030_ShockWave001/002` | cinematic shockwave rings | (not checked) |
| Helios: `/Game/OnlineMode/VFX/Vehicles/Boss/BA001_aias/Niagara/NS_ms17supsExplosion01_ON` | the Helios blast itself | none |

No stock asset is named warp/teleport/portal/wormhole/EMP. Suggested portal: barrier `omen` (open) + `NS_ms23FarFlash`
at spawn + `reverb` (close), scaled up (Scale 5-20; these are sized for drones). Pick by eye in test.

## 5. Open questions / tests
1. **Helios offline test** (highest value): spawn `SV_Helios` and fire LiveFireHelios (HeightThreatLevelPlayer, 6 blasts).
   Check: no crash in SetTarget (GameInstance+0x928), warning HUD/minimap/alert appear, blasts damage the player,
   the airfield isn't hit, and the event context list (r9+0x38) contains an SV_Spawn-spawned unit.
2. Damage: the blast's radius and damage come from the weapon tables (WeaponSettingsId_ON / _CSTORY, not decoded;
   wp_HeatBombExplosion's CDO didn't parse: BP variables shift its property indices). Read them at run time or
   measure in the test. Is bDamageToGround set? (Airfield safety.)
3. Does a world-data AI object with `AIObjectClass` set directly skip the NPC/model rows? If so, only the mission-table
   row is needed.
4. Is the Helios warning HUD part of HeatBombExplosion itself (HeliosALERTPlay strings, CUR_EmergencyMiniMap), or
   does it need an online HUD widget? The radio lines (`p1_eb001_helios_*`, `pvpve_002_helios_*`) are online radio
   rows. Survival should use its own radio or none.
5. Niagara from Lua: do the barrier systems need their owning actor or user params to look right? Does
   PoolingMethod (enum ENCPoolMethod, 0 = None) pass correctly through UE4SS 3.0.1?
6. `ALiveBeaconTrackingMissile` (Helios beacon?) wasn't traced to an asset.
