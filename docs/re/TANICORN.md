# TANICORN: research for a ship boss built from our own assets (2026-11-09)

The user's Anomaly boss: one ship fused from the Alicorn and the Tanager (the battleship Matias Torres survived, sunk
by Mobius 1), concept "Leviathan" (~650 m). It must be **its own model**: our own meshes, skeletons, animations and
blueprints, cooked in our UE 5.4 project, with AC8's native C++ classes as parents (unavoidable). Every moving part
must move in game, and its weapons must be selectable per mount: VLS everywhere, lasers, main guns firing railgun
shells. The Tanager stand-in is Sea Power's Iowa model: **dev install only**, never in a zip (user, 2026-11-09).

Concept art and Blender work: build/research/anomaly_tanager (Leviathan_rev4.blend, Leviathan_animated.blend).
Tags: [V] read in a file (path given), [I] inferred. Reader: `E:/ACE8AircraftBuilder/ACE8AircraftBuilder.exe dev
dump|obj|sockets|skeleton|mesh` with a usmap (the builder source embeds one: embed/mappings.usmap.gz), headers in
build/liveproject/Source/Live/Public (= E:/AC8LiveProject).

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
- Partly answered: tools/laser7's `LaserFx` commandlet (the SurvivalFx editor module in E:/AC8LiveProject) already
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


## 7. The 16-inch triples' FIRE MODE: the styles, the user's spec and their clip (2026-11-11; modelled, not yet built on the machine or seen in game)
The user: "we make them look normal, until they transform into fire mode" (their stills: a battleship turret whose
armour comes apart in angular blocks, side plates held out on arms and slabs staggered out in layers; each barrel
splitting lengthwise and opening like jaws round a glowing core, bracket rings along the open halves; green lightning
and rings as it fires). Two passes were turned down ("Surely you can do a higher quality job than this", "I don't like
this version either"); then: "give me 8 different versions of the Turret with different styles, I want it as close as
humanly possible to what those screenshots showed you and I'll pick". Then, with two manga panels of the guns opened
round coil rings, the user's own spec, built as style 9: "Split the barrels into four sections. Then split the barrels
in the middle and have them slide back and angle themselves upwards. Keep the glowing rod in the center of the barrel.
Have the back left and back right of the turret explode outwards. And have the front right and left sides also explode
outwards. Feel free to model an interior of the gun housing.", then "have the front right and left sides, along with
the front section of the roof lift up". Then an 8 s screen recording of an anime battleship's turrets transforming:
"Watch this frame by frame. I want it to look exactly like this." That is **style 10 (DEFAULT_STYLE)**. Not yet
approved. (The recording is the user's and stays out of the repository; so do the side-by-side sheets with its frames.)
- `tools/tanicorn/firemode.py` (run by model_tanacorn.py; `TANA_FM_STYLE` 1-8, 0 for the design's Iowa mount) models
  the mount from scratch on tanakit.py's clean solids, in place of the Iowa's on both turrets: the design's outline,
  size and yaw pivot, the trunnion moved back to 1.2 m behind the face (house frame (11.42, 0.10, 3.17) m), the muzzles
  where they were. The house is an armour SHELL over a dark core: 13 wall slabs and the roof, each mitred to its
  neighbours with a seam between; under every slab a style moves, a bay of dark machinery (a sunk panel, ribs, pipes;
  under the roof, heat-sink fins). The guns: bloomer boots in wells in the face, tapered barrels, a core rod in each;
  forward of its root ring each barrel is 2-4 pieces round the core, bracket rings along its bore. **Nothing inside
  glows** (the user, 2026-11-11: "Don't have the insides glow"): only the running lights outside (dim stowed, brighter
  in fire mode) and the core rods while the guns fire (firemode.FIRE).
- **The styles** (`STYLES`): 1 jaws (left / right) + side armour out on struts; 2 jaws + layered armour (the aft and
  forward side walls and the chamfers in three slanted slabs each, staggered out); 3 top / bottom jaws + struts;
  4 sliding rails (halves apart and 3 m forward) + exploded house (the roof in three blocks lifting apart, the side
  walls and rear sliding out); 5 four petals + exploded house; 6 four staves on the diagonals + layered armour;
  7 three petals + clamshell roof (its halves hinged up on their outer edges, the forward side walls hinged down);
  8 jaws + layered armour + the Fog's glowing circuit lines over the armour. 32-47k triangles a turret.
  **9** (the user's spec): each barrel a thin shell in four sections (port, top, starboard, bottom), each cut at mid
  length (X_MID): the eight pieces part, slide back (the front halves further, stacking outside the rear ones) and
  pitch up 16 deg as parallel plates (the top ones about their back end, the bottom ones about their front, the sides
  about their middle); inside, the core assembly: the glowing rod, coil rings on spokes and hubs every 1.7 m, four
  rails; the back left / right (the aft side walls in two chunks, the rear corners) and the front left / right (the
  forward side walls in two bands, the chamfers) blow outward on long arms, turning as they go; behind them the gun
  house's interior (hollows cut into the core: grated floors, frames and pipes, a shell hoist and shell racks aft,
  cabinets forward; each gun's breech, block, recoil cylinders and cradle on the guns). 54k triangles a turret (the
  core assemblies 10k of it). Before export: the house's interior posts leave a few non-manifold edges (9) and the
  core assemblies 15 degenerate faces: to clean.
  **10** (the clip, read frame by frame by a workflow of analysts and checked against its frames by two more,
  2026-11-11; the frame numbers in firemode.py): each barrel's shell is four quarters, top, bottom, port and starboard,
  their seams an X on a light-grey muzzle rim (shell 0.3 m thick, bore 0.58 m), each cut at mid length (the user's
  "split the barrels in the middle"; the clip's shells are whole, sliding about a third of the barrel back into the
  turret: with three guns close together that collides, so the halves telescope instead); the quarters step out from
  the rod together with a pale lemon flash from the seams (firemode.FLASH); each gun's ribbed sleeve drops a band out
  and down on either side like petals (PETAL; Barrel_<gun>_10 / _11); the front halves step out further and slide
  back over the rear ones in two steps (their ends at 65 % of the barrel) while the whole staves pitch up about their
  roots ("angle themselves upwards": the side quarters 10 deg, the top one 5, the bottom one level); the rod, a plain
  khaki cylinder with a paler rounded tip (r 0.24 m; its own piece, Barrel_<gun>_9), pushes 2 m forward to 88 % of
  the barrel and lights lemon as the gun charges, three cream coil rings at its root and strips along the staves'
  inner edges with it (CLIP). The armour as the clip's side shot draws it (frames 141-183): the aft side wall's seam
  runs level at about half height to 0.36 of the wall, slopes down to 0.3 H and drops to the foot; the L-shaped
  panel above it (its forward tab full height) lifts straight up 0.45 H with the roof's front section, in two halves
  either side of the centre line, each an inverted U ("the front right and left sides, along with the front section
  of the roof lift up": the far turret, frames 169-171, the superfiring one, 34-45); the lower panel slides forward
  0.47 H along the foot and 0.1 H out; the rear wall and a strip of the rear roof 0.75 H deep, one rigid L in a half
  each side of the centre line, tip aft 65 deg on the rear face's foot (yawed 6 deg out, a gap between them): the wall
  a ramp, the roof strip a leaf standing up, leaning toward the house ("the back left and back right"); the front
  corners stay. Behind the opened walls the gun house's interior, cut only where walls open (the training gear's big
  drum, the hoist, shell racks; a doorway through each rear corner). No strut arms. 36k triangles a turret; every part
  a clean solid (nothing in the interior meets another face flat on: what stands on something sinks a little into it;
  the slabs sink 0.05 m into the core, style 10's "sink").
- **Each piece** is an object `TANA_T16_<tag>_<bone>` carrying its motion (`fm_ops`: translations and turns, each over
  a stretch of the 2.5 s transform), part (`fm_part`: ARMOR or GUNS) and bone (`fm_bone`). Keyed into the model's
  timeline: deploy 110-185, stow 226-301.
- **Choosing**: `styles_firemode.py` builds one style on a model made with `TANA_FM_STYLE=0` (untextured) and renders
  it at night from four sides (from above and behind, from ahead, firing, the side; with an interior, two views into
  it; with `sequence`, the transform in five steps; with `clip`, the recording's two shots, low just ahead of the
  near-level guns' muzzles and the house's aft quarter from the deck, step by step at its frames' moments, at night
  under a cel look: the glow
  lights nothing round it; with `film`, the same two shots animated frame for frame with the recording, FILM_*);
  `style_sheet.py` lays them out, with the recording's frames (a folder of frame_NNN.png at 24 fps) beside the clip
  steps (CLIP_PAIRS). The sheets: art/tanicorn/renders/styles (1-8), art/tanicorn/renders/
  style9, art/tanicorn/renders/style10 (the model's side only).
- **Export** (export_tanacorn.py): `T16` (house on turret_yaw, boots, root rings and core rods on turret_pitch;
  SOC_Gun_01..03 at the open muzzles; its wreck the house and roots: barrels gone) plus two skinned parts riding its
  bones, each with the animation `Deploy` sampled from the model's keys (rotation and place a bone, 30 fps):
  `T16_ARMOR` (Root at turret_yaw > the style's armour pieces) and `T16_GUNS` (Root at turret_pitch >
  Barrel_<gun>_<piece>; SOC_Charge_01..03 1.5 m ahead of the muzzles, for the charge effects; style 10's shots and
  charges leave the rods' tips, out: each rod's `fm_tip`). check_export.py reads
  each back: bones in place, one action, shut at its start, its farthest bone where the export says.
- **UE** (ue_import.py kind `deploy`: SK_SV_Tani_T16_ARMOR / _GUNS + AS_SV_..._Deploy; spec.py FIRE_MODE):
  BP_SV_Tani_T16 gets `FireModeArmor` / `FireModeGuns`, SkeletalMeshComponents attached to TurretPoseableMesh at
  turret_yaw / turret_pitch, AnimationSingleNode with Deploy loaded and held shut, no collision, hidden by the destroy
  system with the turret. The FCS's ActivationTime is 3 s (longer than the transform). [?] that a component attached to
  a PoseableMesh's bone follows the bone as the fire control turns it (standard UE; not yet seen in AC8).
- **In game, still to build (WP1 / WP11)**: Lua opens a T16 when its fire control engages (`PlayAnimation(Deploy,
  false)` on both components) and shuts it a while after its last shot (`SetPlayRate(-1)`, play); the glow through the
  glow slots' material instances (`*_fm_slit` the running lights, `*_fm_core` the cores as a gun fires; AC8's gear material has
  `Ctrl_All_Emissive` and a Livemap, its emissive mask [?]); the charge and the shot with AC8's own effects at
  SOC_Charge_NN (the Alicorn's lightning `NS_alcn_LiSpark_*`, the rail cannon's discharge; hard rule 58: never our
  own compiled materials).
- Before the chosen style is built for the game: its armour pieces checked clean (the layered and exploded styles'
  slabs still have a few boolean slivers at their struts), its glTFs through check_export.
- The breach film (breach_tanacorn.py) predates the new mount: re-rendered as it is, its 16-inch salvos would leave
  from the guns' roots (it finds muzzles on LEV_G16_*.001, now only the boots, root rings and cores).
