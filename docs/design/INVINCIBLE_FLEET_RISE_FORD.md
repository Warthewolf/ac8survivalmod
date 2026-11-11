# INVINCIBLE FLEET: the rise (WP4), GEOFON's damage model and break-up (WP5), the rise between the halves (WP6)

Research and plan, written 2026-11-11 (night of 2026-11-10/11) for the sessions that build WP4-WP6 of
docs/design/INVINCIBLE_FLEET.md. Nothing here is built. It doesn't change the plan file; where it departs from the plan's
WP4 / WP5 text it says so, and section 7 lists what the plan file should take over.

Tags as in docs/re: [V] read in a file, a dump or seen in game (where), [I] inferred, [?] not known yet.
Dumps made tonight (scratch, not kept in the repo): `<a session scratchpad>/agentE`
(`legacy/` the stock packages converted with retoc; `grfd_base.txt` / `grfd_objs.txt` / `grfd_extra.txt` the Ford's
blueprint, `vbdp.txt` BP_Vessel_BodyDestroyParam, `CUR_*.txt` the Alicorn's surface / dive curves, `mesh_grfd` the Ford's
mesh as glTF, `grifn_base.txt` the Grifn). Re-made in minutes with the commands in section A.

---------------------------------------------------------------------------------------------------------------------
## 0. In short
- **The rise: route B2, "the rise rig"** (new tonight; replaces the plan's route B, which needed the whole ship as one
  skinned mesh). The hull blueprint gets one more component: a tiny skeletal mesh of ours ("RiseRig": bones root >
  hull, root > cam) playing one AnimSequence of ours (`AS_SV_Tani_RIG_Rise`, ~20 s). HullMesh (the 650 m static mesh)
  hangs on the rig's hull socket, every part hangs on HullMesh as now, so the whole ship rides the animated bone:
  under the sea, bow out, ~60 deg up with the bow at ~540 m, the hang, the fall, the slam and the bounce, all native
  animation (hard rule 39), on whatever class the hull is. Every piece is proven but one: our cooked animations play in
  AC8 (VALKA's wing sweep, 0.67.1), Lua starts and scrubs them (sv_anomalies_valka.lua), our hull draws its 32 parts on
  sockets (0.74.60), a 3.3-4 s joint animation imported tonight (AS_SV_Tani_RAILCANNON_Deploy, _RAILGUN_*_Deploy). The
  one new thing: components following an animated bone of an otherwise empty skeletal mesh (UE does it; section 2.3).
- **GEOFON's damage stages: Lua on the stock Ford, no cooked Ford blueprint.** The stock Ford has no damage stages at
  all [V: its DamagedStateComponent lists only a death effect list and the body destroy]. Survival adds them at health
  thresholds: AC8's own vessel fires and smoke attached to its hull, its own `_DAM` material instances (or dimmed
  dynamic copies of them) on the live hull's slots (hard rule 41's way), and a list (a few degrees of roll on
  VesselMesh). All of it is calls Survival already makes elsewhere.
- **GEOFON's break-up: "the V-break".** No stock destroy system splits a static hull, and the Ford's full geometry is
  Nanite pages nobody here can read (only a 2,483-triangle fallback dumps), so no wreck halves of our own. Instead two
  copies of the stock Nanite wreck mesh SM_VE004_grfd_DAM, one pitched bow-up 25 deg and one stern-up 15 deg, each
  lowered so the other half of that copy is under the opaque sea: from above it is a carrier broken at midships, both
  halves rearing out of the water in a V, and the torn ends never show. They part along the keel to a ~215 m gap and
  sink, on a "break rig" of ours (a 4-bone skeletal driver with their sockets and one 65 s AnimSequence): AC8's own
  pattern, as the Alicorn's wreck is a 3-bone skeletal mesh (Body > A, B) with a 60 s animation [V: dumped tonight].
  A look test needs no cook at all (section 5, T1).
- **The cinematic:** a camera actor (SV_SpawnCam, runtime 0.32.1) attached to the rise rig's cam socket, so the shot is
  keyed with the rise; the view on it with SetViewTargetWithBlend from Lua (both proven in co-op's spectator view,
  0.73.15); the player's plane invincible (SetIsInvincible, as DOWN) and flown by the runtime's loiter autopilot
  (SV_Down) for the ~20 s, attackers held off as DOWN does. Every game cuts on the host's message.
- **The Tanicorn under GEOFON:** spawned hidden when GEOFON falls under `pre_hp` (25 %), held under it, so the spawn's
  hitch (the Alicorn's: 1.3 s, HISTORY 0.73.79) never lands on the break.
- **The class question stays open, and the rise no longer decides it** (section 2.5): the user chose the submarine
  class (TANICORN.md 0); route B2 works on any class. What decides the class now is whether the hull sails a path.

---------------------------------------------------------------------------------------------------------------------
## 1. The Ford in Survival today

### 1.1 The unit, its rows and its round [V: code]
- Unit `SV_Unit_SpFord` / object `SV_Obj_SpFord`: Mission 16's allied Grindylow `A_Unit_01_Ship0` ported whole
  (tools/build_survival_world.py spaceport_units, `port_unit(..., 'sv_sp_ford', ..., tgt=True)`), made an enemy
  (`enemy_unit`: Faction 2), bIsLanding / bShowCallSignForAlly / bIsEscortedUnit off, unit area 45 km, 0-15 km
  (survival_events.SP_SHIP_AREA_M / _ALT_M), at the fifth sea mark (-29.65, -0.26) km, z 50 cm, facing the spaceport pad.
- Its four Mk 15 parts renamed by place: `SV_Obj_SpFord_Mk15LB / RF / LF / RB` (the source's components end in
  `_01.._04`), rows `sv_fleet_mk15ford<pos>` -> `SV_Fleet_Mk15Ford<pos>` (copies of `VE004_grfd_mk15_<pos>_01` on Survival's
  fleet fire control), classes Mission 16's `BP_VE004_grfd_mk15_0N_CP_Ally` by import_from (an ally class on an enemy:
  it fought, 0.73.40+).
- Hull row `sv_sp_ford` -> `SV_Fleet_FordHull` (DT_SV_NpcRows copy of `VE004_grfd_01`, its ChildNPCId naming the four
  parts' rows: survival_events.SP_HULLS; the 0.73.45 lesson: parts spawn on the rows their hull's row names).
- Orders: each Mk 15 its own Normal / PlayerFirst order 2.5 s after the ship appears (0.73.40: a hull's order never
  reaches its turrets).
- Lua (sv_spaceport.lua): `SPORT.fordActor` (the first LiveAIGameObject made while `spawningUnit == FORD`, for the deck),
  `SPORT.shipObjs[unit]` (every object the spawn makes), `findHull` (the object whose class isn't a turret's),
  `shipsTick` (sunk when the hull is gone or at 0: pay once, CARRIER SUNK once, its turrets still up finished off),
  `deck` (a free pool 2-ship every 50 s, 600 m off its bow, 1,100 m up, while `afloat`). It sank and paid in the user's
  test of 0.73.39 (SPACEPORT_ASSAULT.md).

### 1.2 The stock blueprint [V: dump of BP_VE004_grfd_Base, scratch grfd_base.txt / grfd_objs.txt]
`/Game/Blueprints/Vehicle/AI/Vessels/VE004_grfd/CP/BP_VE004_grfd_CP` -> `Base/BP_VE004_grfd_Base` ->
`/Game/Blueprints/Vehicle/AI/BaseAI/BP_AIShip_Pawn` -> ALiveAIVessels (TANICORN.md 1). The Base's components:
- `VesselMesh` (StaticMeshComponent, SM_VE004_grfd, EnemyPawnPlus), `DamagedStaticMesh` (SM_VE004_grfd_DAM, bVisible
  false), `SM_VE004_grfd_antenna_01` / `_02`, `LiveSpinner` (the radar);
- four LiveChildActorComponents `BP_VE004_grfd_mk15_01..04` (class BP_VE004_grfd_mk15_Base_C);
- two wave spawners (BP_LiveWaveSpawner_Wake_Large, BP_LiveWaveSpawner_Wave_Midium: the wake), a
  LiveDeathDeactivateNiagaraComponent;
- `DamagedStateComponent`: `DefaultDestroySystemList` = [`LiveDefaultDestroySystemExtraEffect_0`,
  `BP_Vessel_BodyDestroyParam_C_0` (no overrides: its class defaults)], `InducedExplosionSystem` =
  InducedExplosionArrangement, `bIsDisableChildDamageSound` true. **No DamageProgress system, no damage stages: nothing
  changes on the hull between full health and death.**
- The Mk 15 (BP_VE004_grfd_mk15_Base): TurretPoseableMesh, DamagedStaticMesh, DamagedCollision; on death ChangeMesh
  (hide the turret, show its wreck), ScatterParts (one ScatterPartsData, all defaults) and two SpawnDecal.

### 1.3 Its death [V: dumps]
- `BP_Vessel_BodyDestroyParam` (a ULiveDefaultDestroySystemBodyDestroy): AliveBodyMeshName `VesselMesh`,
  DestroyBodyMeshName `DamagedStaticMesh`; DefaultFallParam: FallSpeed 0.03, FallSpeedTime 10, AirResistance 0.7,
  PitchTime 60, MaxAngleSpeed (-0.05, -0.05, -0.02) + random (0.1, 0.1, 0.04), AngleDamping 0.87, FinalExplosionTime 80.
  The whole actor sinks slowly with a little drift of angle for 80 s, then the final explosion.
- `LiveDefaultDestroySystemExtraEffect_0`: 66 effects from 0 to 69 s (ExtraEffectAttachMeshName "DestroyedStaticMesh", a
  name no component has: [I] they attach to the root), all AC8's campaign vessel effects under
  /Game/VFX/Vehicles/Vessels/FX_Vessels_Explosion/: NS_VesselsSonicL001 and NS_VesselsExplosionXL001 (with a
  GroundExplosionL shake) at 0 s, NS_VesselsPillarL001 at +-47 m across, NS_VesselsFireL001 (+16 m up, 55 s) and
  NS_VesselsSmokeS001 (55 s), NS_VesselsWaveFoamXL001 at nine spots from -130 to +130 m along the keel, a
  NS_VesselsWaveSplashL001 every 8 s from the stern to the bow (5-69 s), secondary NS_VesselsExplosionS/M/L001 with
  NS_VesselsSplashM001 at 5-54 s; the sound AKE_GEN_EXP_SEA_VE004_grfd_Body_Killed_Secondary_Play on each.

### 1.4 Its meshes and materials [V: dumper `dev mesh / sockets`, scratch mesh_grfd; bulk headers]
- SM_VE004_grfd: bounds x -163.9..+167.6 m, y -45.1..+40.8 m, z -10.8..+61.3 m (333 m long, 86 m across the flight
  deck). Flight deck at ~21 m above its origin; the island at x -110..-70 m (top 61.3 m); something 34.8 m high at
  x +50..+90 m (scratch glb_deck.py). Bow = +X [I: the island aft of midships, as the real Ford's, and the deck launch's
  "off its bow" is the actor's forward].
- 6 sockets: SOC_grfd_mk15_01 (100.8, -23.4, 15.0) m, _02 (95.5, 25.7, 16.9), _03 (-152.4, -30.6, 17.5), _04
  (-152.6, 32.1, 17.5), SOC_grfd_AN_SPS_73_01 / _02 (-89.6, 34.8 / 25.6, 49.3). No deck marks (WP14's touchdown spot will be
  an offset from the root).
- **Nanite**: its .ubulk starts with `NF` (Nanite pages, as Comona's terrain: COMONA_MAP.md); the mesh that dumps is the
  fallback: 4,716 vertices, 2,485 triangles. SM_VE004_grfd_DAM: the same bounds and sockets, Nanite too, fallback
  2,483 triangles. **A wreck of our own cut from it would be the fallback's detail, far below the stock ship's.**
- Materials: SM_VE004_grfd's three slots MI_VE004_grfd_01..03 on `/Game/Base/Material/MP/MP_Live_Vehicle_Base` (ordinary
  textures _D / _MROS / _N; the instance sets no damage parameter). The wreck's MI_VE004_grfd_0N_DAM on a different
  master, `/Game/Base/Material/Character/MP/MP_Live_Vehicle_Base_Dameged`: Charred_* (embers at
  Charred_Embers_Brightness 650000), Blend_Damaged_* with Nornir's damage mask T_OP0044_norn_DamageMasked_02_D /
  _MROS, DNormal_Strength 0.25, Detail_Map T_Dam_MREC. (For WP8 too: progress review 2.)

### 1.5 What could break it in two
| route | what it is | verdict |
|---|---|---|
| a stock destroy system that splits | BodyDestroy moves the one actor; ChangeMesh swaps whole meshes; ScatterParts throws a skeletal mesh's bones (planes, the Mk 15) [V: headers, the Mk 15 dump] | none splits a static hull |
| SpawnFromWD (Mission 19's rocket split) | at a dying piece's final explosion, world-data objects by exact name appear at its sockets (SPACEPORT_ASSAULT.md) | two AI units for scenery, at the final explosion (80 s on, unless a blueprint of ours changes it), on the phase's unit list (hard rule 16): rejected |
| the Alicorn's way | ALiveAIAlicorn's own `DestroyedBodyMeshComponent`: SK_BA002_alcn_DAM, a 38,584-triangle skeletal mesh with 3 bones (Body > A, B, both at the origin) and A_BA002_alcn_DAM, 60 s, no notifies [V: dumped tonight] | the right pattern (two bones, one long animation), but the field is ALiveAIAlicorn's only, and skinning the Ford needs its geometry (Nanite) |
| our own two-half wreck (Blender) | cut the dumped mesh at midships, torn edges, a skeletal mesh | the fallback's 2,483 triangles: poor up close. Fallback only (F2) |
| **the V-break (recommended)** | two copies of the stock Nanite SM_VE004_grfd_DAM on the two bones of a driver skeleton of ours, each pitched so the other half of that copy is under the sea | stock detail, stock materials, no torn edges to make (they're under water), AC8's two-bone pattern; section 4.2 |

The V's numbers (deck 21 m, island 61.3 m at x -90, the 34.8 m structure at x +50, keel -10.8; the sea opaque:
NIGHT_SEA_LIGHTS.md, M_Ocean opaque Subsurface [V]):
- bow copy pitched **+25 deg** (bow up), lowered **21 m**: everything aft of x = +4.7 m is under (the island at
  -90 m: 17.6 - 21 < 0); the bow's tip stands 69 m out of the water, its forefoot ~45 m. At 10 deg the island would need
  47 m of lowering and the bow would drown: the bow copy must rear 20 deg or more.
- stern copy pitched **-15 deg** (stern up), lowered **23 m**: everything forward of x = -10.4 m is under; the island
  stands 60 m out, the stern 40 m, its screws ~9 m.
- at the break the waterline ends are 15 m apart; parted 100 m each way, the gap at the waterline is ~215 m. The
  TANACORN's beam with its pods is 148 m (its hull export: z +-74.1 m), so it lands in the gap across the keel line.

---------------------------------------------------------------------------------------------------------------------
## 2. The rise: what the game offers

### 2.1 Route A: the submarine's own surfacing [V: headers, dumps, sv_alicorn.lua]
- `ALiveSubmarineBase` (Abstract, : ALiveAIArrangementObject): UnderWaterLocation, DiveTransCurve, DiveRotCurve,
  DiveSoundEvent, OnWaterLocation, SurfaceTransCurve, SurfaceRotCurve, SurfaceSoundEvent (all UCurveVector), DiveEffects /
  SurfaceEffects (FLiveSubmarineSeaVFXInfo: socket, sea check, Niagara, scale, duration...), TrailParticles, and
  `BodyMeshComponent` (Instanced, Transient: set by native code, not by the blueprint). `ALiveAISubmarine` adds
  WeaponsName, SkeletalBodyMesh (Instanced, Transient), Weapons. (build/liveproject/Source/Live/Public/LiveSubmarineBase.h,
  LiveAISubmarine.h.)
- **No stock blueprint uses ALiveAISubmarine.** The only /Submarine/ folders are the Alicorn's (ALiveAIAlicorn :
  ALiveSubmarineBase) and the Grifn's (ALiveAIGrifn : ALiveAIArrangementObject) [V: build/scan/all_chunks.txt].
- The Alicorn's curves, dumped tonight (keys as time s: value; FRichCurveKey):
  - CUR_SurfaceLocationCurve: Z only, 0: -5000 (linear), 8: -350, 9: -100, 10: 0 (cubic). **Centimetres**, 10 s.
  - CUR_SurfaceRotationCurve: Y only, 0: 0, 1.74: 3.28, 3: 4.0, 6.99: 2.23, 10: 0. **Degrees** (pitch nose up [I]).
  - CUR_DiveLocationCurve: Z 0 -> -5000 linear over 10 s; CUR_DiveRotationCurve flat.
  The values are real units, not an alpha [V]; how native code applies them (added to OnWaterLocation? onto
  BodyMeshComponent? the curve's own time range as the duration?) and whether it clamps them [?].
- Survival has dived and surfaced the Alicorn many times with `LiveSubmarineOperation` (RE_SV_AlcnDive /
  RE_SV_AlcnSurface; its parts go down with it: sv_alicorn.lua reads a part's depth), but **the surface order doesn't
  always take**: sv_alicorn.lua sends it again up to 4 times when the hull isn't rising after 8 s (a friend's 0.62.1 run
  had it "surfaced" with no hit landing for 40 s to 2 min) [V: sv_alicorn.lua 409-450].
- What moving our hull onto ALiveAISubmarine needs: a hull BP on it (TaniBuild's parent `LiveAISubmarine`), the hull
  mesh possibly named `BodyMesh` (the Alicorn root's name: the transient field must be found somehow) [?], Under / On
  WaterLocation, our own UCurveVector assets (TaniBuild makes none yet [?]), the surface record (LiveSubmarineOperation:
  a foreign template from EP_EB_002, as RE_SV_AlcnSurface), and a dive first (the class has no "start dived": the
  Grifn's component has bStartDived, the submarine base doesn't [V]). Unknown whether ALiveAISubmarine wants anything
  else (weapons by name, a skeletal body) [?].

### 2.2 The Grifn's way [V: headers, dumps] (rejected)
Mission 30's Grifn dives and surfaces through `ULiveAIGrifnDivingControlComponent` (AnimMeshComponentName,
DiveAnimSocketName, ApplyAnimationXValueRate, bStartDived): its root follows a socket of an animated skeletal dummy (skeleton
/Game/Gadgets/G9980/S_G9980; A_VE022_gifn_surface 11.67 s with a sound notify), driven by `ABP_Grifn_Diving`, an anim
blueprint with a state machine and script (15 exports, ExecuteUbergraph) on ULiveAIGrifnDivingAnimInstance, whose owner
must be an ALiveAIGrifn. An ABP of ours means blueprint script and a Grifn hull: TANICORN.md 2 says avoid it, and route B2
gets the same "follow an animated bone" without either.

### 2.3 Route B2: the rise rig (recommended)
The plan's route B was a one-piece skinned Tanicorn (WP0's "one-piece skinned version of the whole ship") swapped in for
the rise. Its own better form: don't skin the ship; drive it.
- `RiseRig`: a SkeletalMeshComponent of ours on the hull's RootComponent; skeleton `BN_RiseRoot` > `BN_RiseHull`,
  `BN_RiseRoot` > `BN_RiseCam`; the mesh one 1 cm triangle on BN_RiseHull (a skeletal mesh needs one); sockets
  `SOC_Hull` (on BN_RiseHull at its origin) and `SOC_Cam`. AnimationMode AnimationSingleNode, AnimToPlay
  `AS_SV_Tani_RIG_Rise`, not playing, its saved position at the animation's END (the rest pose: the hull on the water,
  so Ctrl+Y and every WP2 test see the ship as now).
- `HullMesh` moves under it: parent RiseRig, socket SOC_Hull. Every part (the 32 drawn Part_* today, the live
  LiveChildActorComponents of WP2 later) stays on HullMesh's Mount_* sockets and rides along.
- The rise: Lua `SetPosition(0, false)` (the hull drops under the sea in one frame), then `Play(false)` when it starts;
  `SetPlayRate` retimes it (CFG). These are the calls VALKA's sweep makes on her X-02S (sv_anomalies_valka.lua:
  SetAnimationMode(1), SetAnimation, SetPlayRate, Play, SetPosition) [V: code; her cooked sweep posed her bones in game,
  wrongly at first: VALKA.md 5, 0.67.1].
- Why it's better than A: the motion is entirely ours (any height, 60 deg, a hang, a bounce), it doesn't depend on
  native surfacing code nobody has read or on a class no stock content uses, it starts on a Lua call (no record, no
  250 ms step, no "surface again"), and it works on whatever class WP2 settles on.
- What is proven [V]: our cooked skeletal meshes, skeletons, sockets and AnimSequences load and pose in AC8 (VALKA);
  multi-second joint animations come through tools/tanicorn's import (tonight's AS_SV_Tani_RAILCANNON_Deploy 3.333 s,
  AS_SV_Tani_RAILGUN_L/R_Deploy 4.0 s, build/tanicorn/ue_import.log 2026-11-11 00:01); TaniBuild attaches an SCS node to
  any parent node's socket (TaniBuildCommandlet.cpp: `parent` an SCS name, `socket` -> AttachToName) and sets any
  template property by ImportText; our hull with its parts on sockets draws (0.74.60).
- What isn't [I]: components following a bone of a skeletal mesh that draws nothing. UE refreshes bones (and moves what's
  attached) of an unrendered skinned mesh only with `VisibilityBasedAnimTickOption = AlwaysTickPoseAndRefreshBones`; set
  it, and `bEnableUpdateRateOptimizations = False` so distance never slows the bone. Also whether AC8's own optimisations
  skip a far object's transforms: the Alicorn's world-data desc sets `bIgnoreMeshOptimize` and
  `bIgnoreSetAutoSkipUpdateTransform` (ALICORN.md 5.4); set both on the TANACORN's desc.

The rise's keys (draft for the first test; the hull's origin is midships at the waterline, x +-325 m, keel -25.5 m, top
+81 m: build/tanicorn/src_HULL/Tani_HULL.gltf bounds). BN_RiseHull relative to the actor (z m, pitch deg nose up):

| t s | z | pitch | what shows |
|---|---|---|---|
| 0.0 | -130 | 0 | nothing (the top at -49 m) |
| 1.5 | -130 | 8 | nothing: the cut to the camera blends in (1 s) |
| 3.0 | -100 | 22 | the bow breaks the surface (spray here) |
| 4.0 | -60 | 35 | bow tip +138 m |
| 7.0 | +120 | 55 | bow +395 m |
| 9.5 | +250 | 60 | bow +539 m; the stern 31 m under (keel 44 m) |
| 11.0 | +255 | 61 | the hang |
| 12.5 | +230 | 58 | it topples |
| 16.0 | +60 | 25 | falling |
| 17.6 | -6 | -1.5 | the slam (6 m under its waterline; spray, shock ring, shake here) |
| 18.6 | +2 | 0.5 | the bounce |
| 20.0 | 0 | 0 | still: the rest pose, the animation's end |

The fall from the apex (11 -> 17.6 s) is ~1.6x faster than a free fall of the bow's 540 m (10.5 s): kept for pace,
tuned in the test with the play rate or new keys. BN_RiseCam (draft): from (200, -1900, 90) m yaw +90 pitch +2 at 0 s
to (150, -1800, 140) m pitch +12 at the apex, (100, -1650, 110) m pitch +1 at the slam, (100, -1600, 100) m pitch 0 at
20 s; FOV 55 (the CameraActor's, from Lua). The rise's y axis is the Ford's keel line (the TANACORN yawed 90 deg off the
wreck), so a camera straight off its beam looks through the gap past one half: start the test there, then offset
(+x) as the shot needs.

### 2.4 Route C: the runtime moving it every frame (fallback only)
The runtime already moves player planes on every input-build call (coop.c CoTeleport: TeleportTo + the flight reset,
smooth on a plane whose actor tick is off: hard rules 51, 53). A generic native mover (an actor along keys, per frame)
would do the rise and the halves with no cooked animation. Not chosen: new native code, an AI object's own movement may
fight it (hard rule 39 is the planes'), and B2 needs none of it. Keep it for the case where attached components don't
follow the rig.

### 2.5 The class question
| class | spawns and draws | sails a path | the rise |
|---|---|---|---|
| ALiveAIGroundVehicleObject (0.74.60's) | [V] Ctrl+Y | [?] no test yet (bIsSea, bKeepOnGround off) | B2 |
| ALiveAIVessels (the Ford, the Aegis) | [I] (stock ships do; BP_AIShip_Pawn's three BP functions: needed? TANICORN.md open question) | [V] the Spaceport's boats patrol, the STORE's ships sail | B2 |
| ALiveAISubmarine (the user's choice, TANICORN.md 0) | [?] | [I] (the Alicorn sails on its base class) | B2, or A |

The rise doesn't decide the class any more. What does: the TANACORN must sail from where it lands to the gun line
(WP7). Test that on the current hull first (one path record on SV_Unit_TaniHull, WP2); if it won't sail, ALiveAIVessels.
Route A is worth one probe only if the user wants the submarine class for its own sake (section 7, question 1).

---------------------------------------------------------------------------------------------------------------------
## 3. The cinematic: what exists [V unless tagged]
- **Event focus camera** (`LiveEventFocusCameraExecution`, Mission 22's RE_ShuttleFocusCamera pair; MUSIC_RADIO_CAMERA.md D):
  Survival uses it for the Anomaly's arrival (RE_SV_AnomalyCam_<n>, survival_events_specials.py) and the shuttle; the
  player keeps control; the farther the target the tighter the shot (hard rule 28). Fallback 2.
- **In-game camera node** (`LivePlayInGameCameraExecution`, ImpactCamera_Common / _Random / _Front / _Back / _Side in
  BP_InGameCameraParameter; used in 11 missions, node_catalog.tsv): never used by Survival, its class import must come
  from Mission 04's EP (hard rule 7); how long it holds and whether it frames 650 m [?]. It may handle the HUD natively
  [I]. Fallback 1.
- **A view of our own:** sv_down.lua's spectator view: a camera actor of ours (`SV_SpawnCam(x, y, z)` -> a CameraActor's
  address, runtime 0.32.1), attached with `K2_AttachToComponent(comp, FName(socket), 2, 2, 1, false)`, the view on it with
  `survivalPC:SetViewTargetWithBlend(target, blend, 0, 0, false)`, re-applied whenever the game takes it back (St.reverts).
  In game since 0.73.15 (COOP2MP.md: "the replay-style camera came up on the ADFX-02 and the X-40A"). Lesson kept: view a
  camera ACTOR, never an actor that has cameras of its own (a player plane's own camera wins).
- **Invulnerable and flown:** `pawn:SetIsInvincible(true/false)` (sv_down.lua DOWN, the revive's safe_s, parked_safe);
  `SV_Down(plane, cx_cm, cy_cm, alt_m, radius_m)` / `SV_Down(0)`: the runtime flies the local plane round a point, the
  stick ignored (flight.c, down_ctl.c); DOWN also holds the enemies' attacks (sv_down.lua ATTACKERS:
  MaxPlaneAttackerMissiles, MaxPursuitAttackers, MaxNonPlaneAttackerMissiles). The autopilot's turn is loose (COOP2MP.md:
  AC8's planes don't turn from bank alone): a 20 s circle of 3-4 km is within what it did.
- **The HUD** over the shot: Survival's own widgets can be hidden (sv_hud.lua); the game's own HUD draws to a render
  texture (hard rule 18) and how to hide it from Lua [?] (the pause menu hides it: hard rule 60).
- **Cameras of the cutscenes** (LS_IGC_* level sequences, LiveCinematicsLevelPreloadEventExecution in M10 / M12 / M28):
  a level sequence of ours would be a new cooked asset type: not needed.

**Recommended:** the camera actor on the rise rig's `SOC_Cam`: the shot is keyed in the same animation as the rise,
so it can't drift off the ship, and it uses only proven Lua. Order on each game: autopilot on (round its current spot,
altitude at least 1,500 m) -> invincible -> attackers held -> view blends to the rise camera (1 s) -> the rise plays ->
view blends back (1 s) -> attackers, invincible and autopilot back as they were. A player who is DOWN keeps DOWN's view;
one at the airfield or in the STORE isn't cut.

---------------------------------------------------------------------------------------------------------------------
## 4. The plan: changes per file

### 4.1 WP4, the rise rig (tools/tanicorn; machine build, then a test)
1. `tools/tanicorn/export_tanacorn.py`: a new part `RIG` (kind `rig`): the three bones, the 1 cm triangle on BN_RiseHull
   (any of the hull's materials), sockets SOC_Hull / SOC_Cam, the animation `Rise` keyed from a table at the top of the
   script (`RISE_KEYS`: t, hull z / pitch, cam x / y / z / pitch / yaw; section 2.3), 30 fps, eased (Bezier) keys;
   `Tani_RIG.json` {kind 'rig', bones, sockets, anim: {name, length_s, frames}}. The model's design files aren't touched.
2. `tools/tanicorn/check_export.py`: the rig has the three bones and two sockets; the animation's length matches
   RISE_KEYS' last time within a frame; BN_RiseHull's last key is the identity (the hull back on its spot) and its first
   below -10,000 cm; its highest bow point (the hull's +325 m point through the keys) 500-600 m.
3. `tools/tanicorn/ue_import.py`: kind `rig` imported as `vls` is (skeletal mesh, skeleton, its animation):
   `AS_SV_Tani_RIG_Rise: 20.0 s (export 20.0 s)` in ue_import.log.
4. `tools/tanicorn/spec.py` hull_bp: a first SCS node `RiseRig` (SkeletalMeshComponent, parent RootComponent; props
   SkeletalMesh and SkinnedAsset SK_SV_Tani_RIG (both, as every mount since 0.74.52), `AnimationMode`
   `AnimationSingleNode`, `AnimationData` `(AnimToPlay=<AS_SV_Tani_RIG_Rise>,bSavedLooping=False,bSavedPlaying=False,
   SavedPosition=20.0,SavedPlayRate=1.0)`, `VisibilityBasedAnimTickOption` `AlwaysTickPoseAndRefreshBones`,
   `bEnableUpdateRateOptimizations` `False`, `BodyInstance` `(CollisionEnabled=NoCollision)`); HullMesh's parent
   `RiseRig`, socket `SOC_Hull`. The docstring says why.
5. `tools/tanicorn/build.sh`: SK_SV_Tani_RIG and AS_SV_Tani_RIG_Rise in the cooked-file check; `tools/tanicorn/README.md`:
   the part.
6. `tools/build_survival_world.py` (where SV_Unit_TaniHull is ported, after `port_unit(... se.TANI_HULL_UNIT ...)`): the
   hull's AI object desc gets bIgnoreMeshOptimize and bIgnoreSetAutoSkipUpdateTransform true (as the Alicorn's) [I].
7. `Scripts/sv_tanicorn.lua` (test only): **Ctrl+R** (free: only T, U, Y are bound with Ctrl among the letters, and no
   part binds R: testKey / Key.* grep tonight): the hull as Ctrl+Y spawns it, 5 km ahead, broadside; switched off as
   sv_escort.lua's offObj but visible (no box, no lock-on, invincible, no collision); RiseRig found (SPC.V.comps,
   SkeletalMeshComponent named RiseRig), `SetPosition(0, false)`, after `hold_s` `Play(false)`; with `cinematic` the view
   sequence of section 3. Every 0.5 s: two hull points read as locations (rotators from Lua read no Yaw: 0.74.55's
   lesson), `HullMesh:GetSocketLocation(FName("Mount_RAILCANNON"))` (x +125.9 m) and `"Mount_VLSD_8"` (x -264 m), the pitch
   from them, and one part's place (Part_T16_FWD). At the end onObj-style flags back on (boxes, lock-on).
   Settings in CFG.specials.fleet.rise, set in sv_fleet.lua itself while it's a test-only part (sv_config_specials.lua is
   at 1,944 lines tonight, size_check's limit 2,000: the fleet's settings later need a piece of their own in the
   sv_config family, AGENTS.md "Runtime layout"): `{ hold_s = 1.5, rate = 1.0,
   length_s = 20, slam_s = 17.6, breach_s = 3.0, cinematic = true, blend_s = 1.0, cam_fov = 55, autopilot_alt_m = 1500,
   autopilot_radius_m = 3500, splash = { ... }, shake = <BP_CamShake path> }`.
8. Effects at the times (Lua, as sv_decoy.lua / sv_escort_dive.lua spawn AC8's Niagara): at breach_s the Alicorn's
   surfacing plume (NS_ex03_alcn_surfacing0x, /Game/OnlineMode/VFX/Vehicles/Boss/BA002_alcn/Niagara/: pakchunk20, loads
   in Survival as the Alicorn's own effects do) at the bow's breach point and AKE_BA002_alcn_Surface_Play (pakchunk0); at
   slam_s NS_VesselsWaveFoamXL001 and NS_VesselsWaveSplashL001 at 13 spots along the hull (the Ford's death list's
   effects), a camera shake (CFG already names BP_CamShake_BombImpactHelios), the Alicorn's sinking or final sound.
   AnimNotifies in the animation are not needed.

### 4.2 WP5, GEOFON's stages and break-up
**(a) The stages (Lua only, no cook).** A new part `Scripts/sv_fleet.lua`, the whole part one TEST ONLY block (as
sv_anomalies_dev.lua: WP12's second lock), in main.lua's MODULES right after sv_spaceport (it reuses SPORT's capture).
It starts with GEOFON's pieces (GEO); WP10's round grows in it later:
- `GEO.capture(o)` as the Ford's objects are made (NotifyOnNewObject with `spawningUnit`, as SPORT.shipObjs): its
  components by name (VesselMesh, DamagedStaticMesh, SM_VE004_grfd_antenna_01 / _02, from SPC.V.comps), its parts, its
  health at spawn as its maximum; with `break.enabled` its DamagedStaticMesh emptied at once (`SetStaticMesh(nil)`, so the
  stock death shows nothing there) [I: first SetStaticMesh from Lua; else hide it every tick after the death].
- `GEO.tick` (every tick while it's afloat; the hull checked still the object captured: hard rule 59): its health
  share against `stages` = { { at = 0.66, ... }, { at = 0.33, ... } }. A stage: fires NS_VesselsFireL001 and smoke
  NS_VesselsSmokeS001 attached to VesselMesh at offsets on the deck and the island (`SpawnSystemAttached`, as
  sv_anomalies.lua / sv_escort_laser.lua), a list `roll_deg` ramped over `list_s` (VesselMesh's relative roll, 0.1 deg a
  tick: no visible step), its sound (AKE_GEN_EXP_SEA_VE004_grfd_Body_Killed_Secondary_Play), and at stage 2 the hull's
  slots on its own `_DAM` instances (`SetMaterial(i, MI_VE004_grfd_0N_DAM)`), or dynamic copies of them with
  `Charred_Embers_Brightness` scaled by `embers` (CreateDynamicMaterialInstance + SetScalarParameterValue, as
  sv_zfa44.lua) so it smoulders before it dies. WP8's always-on scars stay under these.
- Logged: `geofon: up: <unit> <name>, health H, components: VesselMesh, DamagedStaticMesh, ...; N parts`,
  `geofon: stage 1 at 66 %: F fires, S smoke, list R deg over T s, M material slots (<route>)`, `geofon: down at +T s
  (<why>)`.
**(b) The break look test (Lua only, no cook): Ctrl+B** (test only). The Ford alone (`SV_Spawn("SV_Unit_SpFord", ...)`
3-4 km ahead, broadside, invincible), then its own two meshes posed as the V: DamagedStaticMesh shown, relative
pitch +25 deg and -21 m at +X (the bow copy); VesselMesh pitch -15 deg and -23 m (the stern copy) with its three slots
on the _DAM instances; its parts and antennas hidden. With `move` the two step apart (`part_m` 100 each way over
`part_s` 25) and down, from Lua (4 steps a second: whether a step shows from 2-5 km is part of the test). Logged:
`geofon: break look: bow copy (DamagedStaticMesh) pitch +25 down 21 m, stern copy (VesselMesh, 3 slots _DAM) pitch -15
down 23 m; 4 parts, 2 antennas hidden` and every 2 s `geofon: break look +T s: bow (x, y, z) m, stern (x, y, z) m,
gap G m`.
**(c) The break rig (tools/tanicorn; machine build).** A part `GEOWRECK` (kind `rig`) in export_tanacorn.py (no
Tanicorn geometry: bones `BN_Root` > `BN_Bow`, `BN_Stern`, `BN_Cam`, a 1 cm triangle; sockets SOC_Bow, SOC_Stern,
SOC_Cam; animation `Break` from `BREAK_KEYS`), and a blueprint `BP_SV_GeofonWreck` (spec.py) on `Actor`: `Rig`
(SkeletalMeshComponent, as RiseRig: single node, AS_SV_Tani_GEOWRECK_Break, playing from spawn,
AlwaysTickPoseAndRefreshBones), `BowHalf` / `SternHalf` (StaticMeshComponents, parent Rig, sockets SOC_Bow / SOC_Stern,
StaticMesh the stock `/Game/Vehicles/Vessels/VE004_gfrd/Model/SM_VE004_grfd_DAM`, NoCollision). The stock mesh through a
stub at its own path: ue_import.py imports the dumped fallback glb there (`dev mesh <SM_VE004_grfd_DAM> <out>`; build.sh
packs only /Game/Mods/SurvivalMode/Tanicorn, so the stub never ships, as the class and material stubs don't) and the game
loads its own Nanite mesh by path [I: the stub route is proven for blueprint classes (BP_wp_flakgun, 0.74.53+) and
materials, not yet for a static mesh]. Fallback: the components left empty and the mesh set from Lua at spawn.
It goes in SurvivalMode_Tani_P (dev builds only, like all of round 30).
`BREAK_KEYS` (draft, the halves' bones in the wreck's frame; x along the Ford's keel, m, deg):

| t s | bow (x, y, z), pitch, yaw | stern (x, y, z), pitch, yaw |
|---|---|---|
| 0 | (0, 0, -21), +25, 0 | (0, 0, -23), -15, 0 |
| 2 | (8, 0, -21), +26, 0 | (-8, 0, -23), -16, 0 |
| 25 | (100, 8, -25), +28, +4 | (-100, -8, -26), -18, -3 |
| 45 | (110, 10, -60), +36, +5 | (-110, -10, -55), -26, -4 |
| 60 | (115, 10, -135), +40, +5 | (-115, -10, -110), -32, -4 (both under) |
| 65 | the same (the actor taken off by Lua) | |

**(d) The break itself (sv_fleet.lua).** At GEOFON's death (its hull at 0 or gone: shipsTick's test, but every tick
from `watch_hp` 15 % down, so the gap is at most a tick): its meshes hidden (VesselMesh, DamagedStaticMesh, antennas:
SetVisibility false), its parts hidden (SetActorHiddenInGame on each, after shipsTick finishes them off), the ACTOR left
shown so its own 66 death effects play over the halves; BP_SV_GeofonWreck spawned at the Ford's pose
(`BeginDeferredActorSpawnFromClass` + FinishSpawningActor, as sv_escort_li.lua spawns BP_SV_LaserInterceptor), or the
one pre-spawned under it at `watch_hp` shown and played; taken off (K2_DestroyActor) at `remove_s` 65. Logged:
`geofon: broken: the wreck rig at (x, y) facing Y (pre-spawned | spawned), its meshes hidden (n), its parts hidden (n);
the TANACORN rises at +R s`, every 5 s `geofon: wreck +T s: bow (x, y, z) m, stern (x, y, z) m, gap G m`,
`geofon: wreck taken off at +T s`.
Settings: CFG.specials.fleet.geofon = { stages = {...}, watch_hp = 0.15, break = { enabled = true, prespawn = true,
remove_s = 65, rate = 1.0 } }.

### 4.3 WP6, the rise between the halves (sv_fleet.lua)
| when | what (Lua, a remote event where a record is needed: hard rule 26) |
|---|---|
| GEOFON under `pre_hp` (25 %) | the TANACORN spawned (SV_Spawn, spawningUnit set: mirrored to joiners) under GEOFON, switched off and hidden (offObj), its rig at position 0 (the hull 130 m down); held at GEOFON's place, yaw + 90, every tick while hidden [I: a hidden, tick-off AI object stays where it's put; else spawn at the death and take the hitch] |
| the death (t = 0) | the break (4.2 d); the music turns (WP10: the INFINITY Remix, sv_music.lua's lengths) |
| t = `rise_at_s` (18: the gap ~150 m) | the host sends `tr|<seq>|<x>|<y>|<yaw>` (a reliable message; code checked unused in sv_coop.lua's dispatcher first); every game: its copy placed at (x, y) yaw, shown, still untargetable (no box, no lock-on, invincible, no collision), its parts shown but not ordered (turrets don't fire without an order: 0.73.39), the rig played, the cinematic (section 3) |
| t + `slam_s` | slam effects and shake; collision on |
| + 1 s | the hull and parts active, each part's order (by name, as the Spaceport's 0.73.40 records) "fire first" |
| + 3 s | boxes, TGT marks, lock-on, mortal (onObj); the boss bar `TANACORN`; callout `THE TANACORN RISES` |
| + 4 s | its path (WP7): the nearest of a path family `SV_Path_TaniGo_<k>` built along GEOFON's lane, each from lane point k through the gun line into the station's laps (hard rules 2, 35, 54), started ahead of where it lies; it turns onto it at its RotationSpeed (set low: 3 deg/s, a 650 m hull pivoting 90 deg in 30 s) |

Co-op: the host decides the moments (the death, `tr`); a joiner's copy of GEOFON breaks on the host's forwarded death
(its own wreck rig, local, nothing streamed); each game plays its own rise, cut and slam; a joiner who links mid-rise
sees the TANACORN already on the water. The pause and the STORE freeze: nothing to do (the rise is 20 s of animation).

---------------------------------------------------------------------------------------------------------------------
## 5. The first in-game tests
Each one: a dev build (`VALKA=1 ZFA=1 TANI=1 sh tools/package_dev.sh <version>`, a new version: tools/bump_version.py),
the key, what to look at, the log lines, the pass line. T1 and T2 need no UE cook and can go in the next build at no
cost to WP1-WP3.

**T1. The V-break look (Lua only).** Ctrl+B in a run (round 1 is fine).
Look: from 2-5 km, and once close: do the two read as one carrier broken at midships, both halves rearing; does
anything of the drowned halves show through the sea (near the waterline, in the wake, in the waves' troughs); does the
Nanite wreck draw pitched (no holes, no flicker); with `move` on, does the 4-a-second step show.
Log: the `geofon: break look:` lines above. Pass: the V reads right from every side at 2 km and more, nothing under the
sea shows; the step's answer recorded either way (the rig removes it).

**T2. GEOFON's stages (Lua only).** Ctrl+G: GEOFON alone 4 km ahead, broadside (the Spaceport's unit), its deck off;
each further Ctrl+G takes 20 % off its health (ModifyHealth, as finishParts). Look: at 66 % fires and smoke on its deck
and island that stay on the ship as it moves, a list; at 33 % more fire and the scorched hull; the Mk 15s still firing.
Log: `geofon: up`, `geofon: stage 1 at 66 %: ...`, `geofon: stage 2 at 33 %: ...`, `geofon: down`. Pass: both stages
show and follow the ship, nothing hitches (the perf line), and the round goes on normally after it sinks (and a STORE
visit after: 0.74.48's rule).

**T3. The rise rig (cooked).** Ctrl+R. Look: the hull gone at first, the bow out at ~3 s, the climb to ~60 deg with
the bow far up (~540 m), the hang, the fall, the slam, the bounce, every part on its socket throughout; the view on the
rise camera, back after; your plane flying itself, untouched.
Log: ue_import `AS_SV_Tani_RIG_Rise: 20.0 s`; tanibuild `component RiseRig (SkeletalMeshComponent) on RootComponent`,
`component HullMesh (StaticMeshComponent) on RiseRig`; in game `tanicorn: Ctrl+R, SV_Unit_TaniHull at (x, y, z) facing F:
1 up; RiseRig found (AS_SV_Tani_RIG_Rise, 20.0 s)`, `tanicorn: rise +T s: bow (x, y, z) m, stern (x, y, z) m, pitch P,
Part_T16_FWD (x, y, z) m` every 0.5 s, `tanicorn: rise cinematic: view on the rise camera (blend 1.0 s); your plane
invincible, the autopilot round (x, y) at A m`, `tanicorn: rise cinematic over: view back on your plane (N reverts),
autopilot off, invincible off`. Pass: the bow's highest z 500-600 m near 9.5-11 s, pitch 55-62 there, at the end bow and
stern back within 3 m of their spawn heights and pitch within 0.5 deg; the part's z rising with the hull; no hitch; the
view comes back.
If the hull doesn't move at all while the log shows the rig playing: the bone doesn't move its children (2.3's [I]):
check VisibilityBasedAnimTickOption took (log the property), then give the rig a visible small triangle; last, route C.

**T4. The break rig (cooked).** Ctrl+G, then kill it (Ctrl+G to 0). Look: the halves appear at once in the explosion,
part to ~215 m in ~25 s, sink by ~60 s, smoothly. Log: the `geofon: broken:` and `geofon: wreck +T s:` lines. Pass:
gap 200-230 m at 25 s, both halves' z under -100 m at 60 s, no step, the wreck taken off at 65 s, a STORE visit after.

**T5. The two together (WP6).** Ctrl+G, kill it: the break, at +18 s the cut, the TANACORN up between the halves across
the keel line, the slam beside the sinking halves (never on them), its guns firing a second later, its boxes after.
Log: T3's and T4's lines, `fleet: the TANACORN spawned under GEOFON at 25 % (hidden; hitch N ms)`, `fleet: rise at +18 s
at (x, y) facing Y`, `fleet: the TANACORN fires (parts ordered: N)`, `fleet: the TANACORN is targetable`. Pass: as the
plan's WP6 pass line, and no part of the TANACORN inside a half above the water. Co-op (two dev installs: WP12): both
views cut within a second of each other.

(Optional) **TA. The submarine-class probe:** only if section 7 question 1 is answered "the submarine class": a
BP_SV_Tani_HULLSUB on LiveAISubmarine with the Alicorn's own CUR_Surface* by path (stubs at their OnlineMode paths) and
the records RE_SV_TaniSubDive / RE_SV_TaniSubSurface from EP_EB_002's LiveSubmarineOperation; log the hull's z every
0.5 s. Pass: it dives ~56 m and surfaces in ~10 s with its parts. Then our own curves.

---------------------------------------------------------------------------------------------------------------------
## 6. Risks and fallbacks
| risk | what answers it | fallback |
|---|---|---|
| components don't follow an undrawn rig's bones | T3 | a visible tiny triangle on the rig; then route C (the runtime moves the hull every frame) |
| AC8's optimisations freeze a far object's transforms | T3 from 3-8 km | bIgnoreMeshOptimize / bIgnoreSetAutoSkipUpdateTransform on the desc; the rig's URO off |
| offObj's SetActive(false) / tick off stops the rig | T3 (the hull switched off while it plays) | keep the hull active during the rise with its parts unordered (they don't fire without orders) |
| the sea shows the drowned halves of the V | T1 | steeper angles, deeper; else F2 (our own halves from the fallback mesh) |
| the stock mesh through a stub at its path doesn't load | T4's tanibuild / the first spawn | the halves' meshes set from Lua at spawn |
| the 4-a-second Lua steps show (T1's move) | T1 | the break rig (T4), which T1 only previews |
| the hitch of the TANACORN's spawn lands on the break | T5's `hitch N ms` | the pre-spawn at `pre_hp`; earlier (round start, hidden) |
| a hidden AI hull drifts or snaps back when moved from Lua | T5 | spawn at the death (the hitch inside the explosion) |
| the view reverts during the shot | T3's revert count | re-applied each tick (sv_down.lua's way) |
| the autopilot wanders or descends | T3 | a bigger circle, higher; else the focus camera (the player keeps control) |
| the game's HUD over the shot looks wrong | T3 | the in-game camera node (LivePlayInGameCameraExecution) if it hides the HUD; else accepted |
| the hull doesn't sail a path on its class | WP2's path test | ALiveAIVessels |
| the TANACORN falls on a half | T5 | rise_at_s later (a wider gap), the halves' sink earlier |

---------------------------------------------------------------------------------------------------------------------
## 7. For the plan file and the user
For docs/design/INVINCIBLE_FLEET.md (not edited tonight: another session is in WP2):
- WP0: drop "a one-piece skinned version of the whole ship with a root bone for the rise"; add the rise rig (RIG part)
  and, for WP5, the break rig (GEOWRECK part) and the stock wreck mesh's stub.
- WP4: route B2 as the main route, route A as an optional probe, route C as the fallback; the cinematic route 2
  (Lua's view target) moves to first, on the rig's camera socket.
- WP5: the stages from Lua on the stock Ford (no BP_SV_grfd); the break-up as the V-break on a break rig; "made in
  Blender from the Ford's own mesh" only as fallback F2 (the mesh is Nanite: 2,483 fallback triangles). WP14's deck marks
  are offsets from the root (the mesh has no deck sockets).
- WP6: the pre-spawn at `pre_hp`, rise_at_s 18, the TANACORN's path family from GEOFON's lane.
- Risks: replace "the surface curves can't overshoot" and "cooked AnimNotifies don't play" with section 6's.

Questions for the user (with the agent's recommended answer):
1. The hull's class: you chose AC8's submarine class (2026-11-09). The rise no longer needs it. Keep the hull on the class
   that is proven to spawn and draw it (today's), move to the ships' class only if it won't sail, and try the submarine
   class only if you want it for its own sake? Recommended: yes.
2. GEOFON's break as a V: the bow half rearing ~25 deg and the stern ~15 deg, parting along the keel and sinking over a
   minute. Recommended: yes (it's how the stock wreck mesh can be shown broken without a lower-detail model).
3. The rise's shot: from off the TANACORN's beam, ~1.8 km out, framing the bow's climb; ~20 s including the slam.
   Recommended: yes, tuned after T3.

---------------------------------------------------------------------------------------------------------------------
## A. How tonight's facts were read
- Packages: `cd "/e/ACE8 Survival Mode" && . tools/env.sh && KEY=$(python -I tools/env.py --aes-key) &&
  MSYS_NO_PATHCONV=1 tools/bin/retoc.exe -a "$KEY" to-legacy --no-shaders --version UE5_4 -f <filter> "$AC8_PAKS" <scratch>/legacy`
  with the filters VE004_grfd, BP_Vessel_BodyDestroyParam, BP_AIShip_Pawn, CUR_SurfaceLocationCurve,
  CUR_SurfaceRotationCurve, CUR_DiveLocationCurve, CUR_DiveRotationCurve, BP_BA002_alcn_Root, BP_BA002_alcn_PlnBase,
  A_BA002_alcn_DAM, SK_BA002_alcn_DAM, S_BA002_alcn_DAM, A_VE022_gifn_dive, A_VE022_gifn_surface, ABP_Grifn_Diving,
  BP_VE022_grifn_Base.
- Dumper: `USMAP="<repo>/build/tanicorn/alcn/mappings.usmap" MSYS_NO_PATHCONV=1 ACE8AircraftBuilder.exe dev
  dump|obj|mesh|sockets|skeleton <path without .uasset> [<export index, 1-based>]` (a copy in the scratch dir). `dev obj`
  of the Ford's CDO (export 4) fails: the usmap doesn't know LiveAirCurrent's newer fields; its components read fine.
  Run the exe only with a `dev` command: with no arguments it opens its window.
- Nanite: the first bytes of SM_VE004_grfd.ubulk are `NF`. The deck profile: scratch glb_deck.py over the exported glb.
