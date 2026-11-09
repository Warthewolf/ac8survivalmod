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
- Hull: AC8's **submarine** class. In the final round it hides under an aircraft carrier and, when the carrier is
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
