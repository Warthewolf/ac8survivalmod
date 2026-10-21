# Special rounds research (Milestone 7, backlog items 12 and 13), 2026-10-22

Sources: stock packages pulled with `tools/get_stock.sh` into `build/stock/`, EP dumps from `tools/checks/ep_dump.py`.
Scratch (not part of the build): `build/research/special/`: EP dumps `EP_Mission019_global.txt`,
`EP_Mission009_Global.txt`, chains `m22_shuttle_chain.txt`, `m19_p5.txt`, and helper scripts in `scripts/`:
`wddesc.py <WD> <list re> <name re>` (prints a whole world-data desc), `epchain.py <ep_dump txt> <trigger re> [depth]`
(a trigger, its execs in stock order, followed through remote calls / composite monitors), `formda.py <DA>` (formation
data asset, metres), `propoff.py <prop>...` (reflected property offsets from the exe), `dispscan.py <hex disp>`
(code that uses `[reg+disp]`), `imps.py <pkg>` (imported packages; the `obj(-n)` -> package mapping is approximate).
Addresses are for AceCombat8.exe of 2026-09-29 (image base 0x140000000). Units: cm, unless stated.

## Key findings in one place
1. **Mission 19 and Mission 22 are both on Comona (Map17)** and launch from the **same spaceport pad** at
   x -13.25 km, y +0.60 km. The pad, tower, gantry and assembly building meshes (`SM_UNI_ShuttleBase001_I22`,
   `SM_UNI_ShuttleTower_I22`, `SM_UNI_ShuttleGantryCrane_I21`, `SM_UNI_RocketLift_I21`, `SM_UNI_VehicleAssembly_I21`)
   are placed in `Map17_Env_CityMap001`, which PL_SurvivalMode already streams. Nothing map-specific has to move.
2. **Mission 22 already is a "defend the shuttle launch" mission**, fully in-game (no cutscene), and Survival's
   WD/EP are copies of Mission 22's: the shuttle unit, its launch path, VFX descs, NPC row (`sstb_common`) and every
   event record needed are already in Survival's templates. Mission 19's rocket is an *enemy* ICBM-like rocket that the
   player must shoot down, and its liftoff plays as a cutscene (IGC_Ms190015/IGC_Ms190020); only its VFX are worth taking.
   **Recommendation: build Comona Defense from Mission 22's shuttle chain, dress it with Mission 19's pad VFX.**
3. Mission 9's LCACs are **allies** (`lcac_Ally`). Enemy LCACs with the same behaviour are in **Mission 13**
   (`lcac_common`, faction 2, spawned at sea in pairs, PathFinish -> landing troops). No mission launches LCACs from a
   ship: they spawn on the water. Mission 22's WD (= Survival's) already has an **enemy fleet** offshore
   (`EA_Unit_01_Ship0..3`: udaloy, grigorovich, gorshkov, kirov) that can be the "fleet".
4. Formations: a leader's blueprint carries a `LiveAIFormationComponent` {FormationDataAsset, FormationUnit = the WD unit
   name of its followers}; `LiveApplyFormationEvent(leader object, formation ID, bool, float)` switches layouts.
   **Mission 26's x40a ace (`OP1016_x40a`) has one built in with 4 escort UAVs** ("Normal" = 4 guards around it in 3D).
   That is the best stock start for the anomaly ace (Mission 23's Barrier UAVs need the Celaeno airship as leader).
5. Flight input: `ALivePlayerPlane` holds the reflected floats `InputPitch` (+0xFF8) / `InputRoll` (+0xFF4); every frame
   the plane packs them into the flight-engine input in **`BuildFlightInput` 0x147d689b0** and hands that to the flight
   engine. A native detour of that function that negates out->Pitch / out->Roll is the clean place to invert controls.
   The game only has a pitch-axis invert option, no roll invert and no "inverted controls" status effect.

---------------------------------------------------------------------------------------------------------------------
## 12a. Comona Defense (shuttle launch)

### Levels
- `PL_Mission019`: Map17 sublevels (Terrain001, CityMap001, CityHda001_Baked, CityTraffic001, ComonaAirport,
  Foliage_Baked, MassAI, Sea) + `Mission019_Common_Env_CityMap001` (empty), `Mission019_Common_Lit_Cloudly01`
  (lighting, don't use), `Mission019_Common_VFX`, `/Game/Maps/Ingame/Mission011/SL_Mission011` (28 static meshes),
  and the cutscene levels `IGC_Ms190010/15/20` (+ `_Lighting`, `_VFX`, `_Sequence`).
- `Mission019_Common_VFX` holds 8 placed Niagara actors: `NS_IGCVFX_Ms130030_BoostMainCenterVelocityFireSmoke001` x2,
  `NS_IGCVFX_Ms130030_BoostSideEachVelocityFireSmoke001` x2, `NS_OP0057_BoostSparksJustStartGroundSmoke` x4 (pad
  launch smoke). Optional: add the sublevel to PL_SurvivalMode only if they turn out to be event-activated, not always on
  (untested; their auto-activate flag wasn't checked).
- PL_SurvivalMode (from PL_Mission022) already loads everything the launch needs. The IGC levels are not portable as
  "in-game" content (they are cutscene sequences) and are not needed.

### The shuttle (Mission 22, already in WD_SurvivalMode_global)
`AA_Unit_01_Ground0` (faction 1 = ally, SpawnPoint (-1325361, 61515, 6453), RadiusInMeter 6000) holds 21 AI objects:
`AA_Obj_01_Ground0_AAGUN_0..5` (gepa_common), `..._SAM0..3` (avng_common), **`AA_Obj_01_Ground0_Shuttle_0`**
(`sstb_common` -> `OP0057_sstb_01` -> BP_OP0057_sstb_CP; at (-1324937, 59740, 6343), Rotation (90,0,0) = upright,
TargetMarkType 3, bIsAttackTargetsException, tags TAG_Shuttle_Obj / TAG_Ground_Obj / TAG_Def_Obj /
TAG_Shuttle_Obj_True / SND_EscortTarget), `..._Shuttle_Dummy_Point0` and `..._Shuttle_Dummy_0..4` (dummy_common,
invincible: near-miss smoke points), `AA_Obj_01_Ground0_Tower_0` (ControlCenter_common, the control room) +
`..._Tower_Dummy0..2`. `AA_Unit_01_Ground2` sits at the same point (not inspected).
Spawning it gives the player allied AA guns/SAMs too. "No allies" => either spawn it and destroy the gun/SAM objects
(LiveDestroyUnitExecution), or (cleaner) add a Survival-only desc at build time with just the shuttle + its dummies
(copy the AI-object entries out of AA_Unit_01_Ground0; same NPC table, no new imports).
SV_Spawn moves a desc to the given point, so for the shuttle pass the desc's own SpawnPoint (or add a "spawn in place"
variant), the AI objects carry their own world positions.

- Launch path `01_Ground0_shuttle_0_Path0` (ControlType 1): begin (-1324937, 59740, 6343) -> z 51343 -> z 166343 ->
  (-1319477, -2315094, 2999890) -> (-1319477, -6475314, 4346900): straight up 1.6 km, then pitches over to the south.
- VFX descs (WD): `VFX_Shuttle_Boost0` (BP_MO113_ms20RocketBooster) at (-1324924, 59756, 3393) = pad ignition plume;
  `VFX_ShuttleDummy0..2` (BP_MO103_GroundSmokeM) = smoke where enemy missiles hit near the pad.
- Volume `Cylinder_Shuttle_Warning` at the pad (enemy-near warning).

### Mission 22 event chain (EP_Mission022_global; exact args, stock order). Survival's EP is a copy of this EP, so these
records can be deep-copied by `survival_events.py` exactly as the round records are.
Mission start:
- `MissionStart` -> `LiveSetMaxHealthExecution` {01 AA_Obj_01_Ground0_Shuttle_0, 02 NoneSelect, 0a NoneSelect,
  10 175.0, 11 false}; `LiveSoundGeneralPostEventExecution` {AKE_Ms22_ARMS_SKY_OP0057_sstb_Body_Ignition_Stop, 0b shuttle}.
Countdown (Mission 22 drives it off the mission timer, type 22 "RemainingTime" triggers + radio post events; Survival
must use its own timer: LiveStartTimerExecution + timer triggers, or plain exec delays):
- radio keys in order: `01_Wave5_Countdown_Start`, `01_Countdown_Shuttle33`..`31`, `..23`..`19`, `01_Ready_Ignistion`,
  `01_Countdown_Shuttle8`, `..7`, `01_Countdown_Ignistion`, `01_Countdown_mainEngine`, `01_Iactive_Ignistion`,
  `01_Countdown_Shuttle2and1`. Sound flags: `AKE_FLAG_Ms22_ARMS_SKY_OP0057_sstb_Countdown_33sec_Set`, `_23sec_`, `_08sec_`,
  `_02sec_`, `_Interrupted_Set` (on failure). `CompositeEvent_CountDown_1` also runs `LiveDisplayRemainingExecution`.
- 60 s before launch (`Default_CompositeEvent_110`): `LiveSetMinHealthExecution` {0b shuttle, 02 NoneSelect,
  0a NoneSelect, 10 1.0} (shuttle can no longer die), same for the Tower.
Ignition / liftoff (remote events, keep this order):
1. `RE_Shuttle_Boost_On`: `LiveSetActiveVFXExecution` {05 VFX_Shuttle_Boost0, 0a NoneSelect, 11 1}
   (+ in Mission 22 with it: sound `AKE_Ms22_ARMS_SKY_OP0057_sstb_Body_Ignition_Play` on the shuttle).
2. `RE_Shuttle_Fire_On` (delay 0.1): `LiveAIPathExecution` {01 shuttle, 02 NoneSelect, 04 01_Ground0_shuttle_0_Path0,
   0a NoneSelect, 10 0.0001, 10 0.0, 10 0.0, 0e ObjectSetting, 10 0, 11 true, 11 false, 11 false, 10 0, 11 false, 10 0,
   11 false} (puts it on its path at ~0 speed: engines lit, not moving).
3. `RE_Shuttle_Launch`: `LiveAIPathExecution` same args with 10 4000.0, 10 15.0, 10 1.0; `LiveCallRemoteEventExecution`
   RE_Wave5_Enemy_PathExit, RE_Kokatu_Finish (Mission 22 wave cleanup: drop); `LiveAIPathExecution` delay 13 with
   5000.0, 30.0, 1.0; sounds `..._sstb_Body_Ignition_Stop` and `..._sstb_Body_LiftOff_Play` (0b shuttle).
4. `RE_Shuttle_Boost_Off`: `LiveSetActiveVFXExecution` delay 30 {05 VFX_Shuttle_Boost0, 0a NoneSelect, 11 false}.
Mission 22's own debug test chain gives the timing to copy: `RE_TestShuttle` = Boost_On at 0 s, Fire_On at 10 s,
Launch at 14 s, Boost_Off at 14 s (+30 s inside).
Damage / under attack (keep: key callouts):
- `ObjectDamage_Shuttle` (type 6f, victim AA_Obj_01_Ground0_Shuttle_0): `LiveFlagOperation_IntExecution`
  Int_Shuttle_HitCount Add 1; damage stages by `LiveIsLowHealthStatement` 61 / 31 / 16 % with flags
  Bool_Shuttle_Damage_Phase01..03 -> RE_Shuttle_Damage_Phase1..3 -> radio `01_All_Wave_Durability50_Shuttle`,
  `01_All_Wave_Durability30_Shuttle`, `01_All_Wave_Durability_Limit_Shuttle` (+ `LiveBattleNavigationExecution`
  {0a NoneSelect, 02 AA_Unit_01_Ground0, 0e Triple, 11 true} = HUD navigation arrow); RE_Radio_Hit_Shuttle ->
  `01_All_Wave_Hit_Shuttle_First` / `01_All_Wave_Hit_Shuttle`; sound `AKE_Ms22_EXP_SKY_OP0057_sstb_Body_Killed_Blaze_Play`.
- `VolumeEvent_Shuttle_Near_1st` / `VolumeEvent_Shuttle_Near` (type 3f, Cylinder_Shuttle_Warning_0 Enter EnemyNPC):
  radio `01_All_Wave_Close_Shuttle_First` / `01_All_Wave_Close_Shuttle` ("pad under attack").
- Near misses: `MissedWeapon_Shuttle_Dummy_0..5` (type 10) -> `LiveSetActiveVFXExecution` VFX_ShuttleDummy0..2.
- Enemy targeting: waves get `LiveAIEngagementOrder` {01 NoneSelect, 02 <wave unit>, 0a NoneSelect, 0e Normal,
  0b NoneSelect, 02 AA_Unit_01_Ground0, 0e Default|PlayerFirst, 0e None, 11 true x3, ...} (target unit = the shuttle site).
  For Survival: give 1-2 bomber/striker flights this order instead of the chase.
Failure:
- `CompositeEvent_Destroy_Shuttle` (life 1, monitors `ObjectDestroy` / `ObjectDestroy_1` = type 70 destroy of
  AA_Obj_01_Ground0_Shuttle_0) -> RE_MissionFail_Destroy_Shuttle -> radio `01_Mission_Failure_Destroy_Shuttle`,
  sound flag `..._Countdown_Interrupted_Set`. Mission 22 then ends the mission (`LiveMissionFinishExecution` MissionFailed):
  **drop that**; Survival sets its flag (shop closed for one round) instead.
Strip (allies/dialogue): Ohayashi/AWACS/wingman radio (`01_Ohayasi_*`, `Active_Ohayashi_*`, YesNo events), wingman
join/leave, LiveSetRadioMuteOptions sets, Debug_* triggers, score/"superiority" branches (Bool_ScoreClear...).
Event camera on the shuttle (backlog: "event camera" node): `RE_ShuttleFocusCamera` -> `LiveEventFocusCameraExecution`
{01 shuttle, 0a NoneSelect, 01 NoneSelect, 0a NoneSelect, 0d LookAt_Event_Camera_ms22-01, 11 false, 11 false}, and
the same with empty values after 9 s to release. Usable for the liftoff.

### Mission 19 pieces worth copying (VFX only)
Mission 19's rocket (`E_Unit_05_Rocket`: two `Rocket` NPC objects -> OP0058_crkt, both invincible, enemy) stands on
two pads: (-1384043, -41261) and (-1325196, 59778). The second pad = Mission 22's shuttle pad.
- `VFX_BigExplosion0/1` = `BP_MO102_ms19ShuttleBaseExplosion` at (-1384864, -41315, 5000) / (-1325369, 59625, 5000):
  pad explosion. Stock use: `Failed_Roceket_ObjectDestroy_N` -> `LiveSetActiveVFXExecution` {05 VFX_BigExplosionN,
  0a NoneSelect, 11 1}, conditioned on `LiveIsInVolumeStatement` (Victim in `00_Rocket_Failed_Volume0`).
  => Comona Defense failure: fire VFX_BigExplosion1 when the shuttle dies on the pad.
- `VFX_05_RocketSmoke0/1` = `BP_MO103_ms19_AfterLaunchSmoke01/02` at the pads (tag VFX_05_RocketSmoke). Stock use after
  the IGC: `LiveSetActiveVFXExecution` {05 NoneSelect, 0a VFX_05_RocketSmoke, 11 1} => after-launch smoke cloud.
- Niagara: `/Game/VFX/Mission/Mission019/NS_IGCVFX_AfterLaunchSmoke001/002`, `NS_OP0058_*` (rocket trails/explosions,
  tied to the OP0058 rocket), `MI_RocketBigGasExplosion*`, `MI_CrashGroundSmoke*`. Sound events
  `AKE_Ms19_ARMS_SKY_OP0058_crkt_*` (rocket only).
- Liftoff in Mission 19 is the IGC (`05_PostIGCEventImmediately_2`, type 27 "IGC_Ms190020"): after it the rockets are
  put on `E_Obj_03_Rocket_N_Path0` at speed 0 and accelerate at path point 1 (speed 1000, accel 2.8) — PathPointReceive,
  which hard rule 1 says never fires for us. Not reusable as an in-game launch.

### What Survival copies (build list)
1. WD (already present in Survival's copy of WD_Mission022_global): shuttle desc (or a trimmed Survival desc),
   `01_Ground0_shuttle_0_Path0`, `VFX_Shuttle_Boost0`, `VFX_ShuttleDummy0..2`, `Cylinder_Shuttle_Warning`.
2. Add from WD_Mission019_global: VFXActorDescs `VFX_BigExplosion1` and `VFX_05_RocketSmoke1` (+ blueprint imports
   BP_MO102_ms19ShuttleBaseExplosion, BP_MO103_ms19_AfterLaunchSmoke02 in the WD and container header: hard rule 7).
3. EP: deep copies of the records listed above (same node classes; set life 1 on spawn/launch triggers: hard rule 3),
   driven from Lua: spawn the shuttle with SV_Spawn at the special round's start, run the countdown on exec delays,
   fail flag on destroy. Lua -> EP bridge already proven: a spawn fires the unit's "reinforcement appeared" trigger
   (type 23), so the shuttle's appearance can start the whole chain.
4. Radio: the keys above are Mission 22's; Survival's MC is Mission 22's, so they should resolve (verify in a test).
5. Shuttle health: MissionStart sets 175; Survival sets it on appearance; LiveSetMinHealth 1.0 for the last 60 s.

---------------------------------------------------------------------------------------------------------------------
## 12b. Amphibious assault (LCACs)

### Mission 9 (ally LCACs; Map08, so its coordinates are useless on Comona)
- Units `A01_Unit_LCAC_A` / `_B` (faction 1, bIsEscortedUnit, RadiusInMeter 4000): 4 AI objects each,
  `A01_LCAC_A_0_lcac_0..3`, NPC `lcac_Ally` (DT_NPC_Mission009; VE014_lcac_Ally_01 -> BP_VE014_lcac_CP_Ally), z 50.
- Paths: one per craft, `01_AIPath_LCAC_A_0_0..3` (+ `01_AIPath_Unit_LCAC_A` for the unit area), ControlType 1, 4-5
  points from the sea onto land (PointType 1/4, z 500 -> 6000 inland).
- Chain (stock order): `Phase01_Start` -> `Phase01_Start_LCAC_R` / `_L` (remote, life 1): per craft
  `LiveAIPathExecution` {01 A01_LCAC_B_0_lcac_N, 02 NoneSelect, 04 01_AIPath_LCAC_B_0_N, 0a NoneSelect, 10 150.0,
  10 0.0, 10 30.0, 0e ObjectSetting, 10 100.0, 11 1, 11 0, 11 1, 10 0, 11 false, 10 0, 11 false}; also `LiveUnitMovePath`
  {02 A01_Unit_LCAC_B_1, 04 01_AIPath_LCAC_B_0_0, 10 150.0, 10 0, 10 30.0, 0e ObjectSetting, 10 100.0, ...} (moves the
  unit area along), `LiveSetMinHealthExecution` 10.0 on lcac_0, `LiveSetHealth` by difficulty.
  40 s later `Phase01_Start_LCAC_R_SpeedUp`: the same paths at 235 (accel 20). Landing: `Default_PathFinish_25`
  (type 2d, lcac_N, path, Finish) -> `Lcac_A_N_Landing` -> 41 s later `LiveReinforcementExecution` of the landed ground
  unit (e.g. AA_Unit_02_Ground_13).
### Mission 13 (ENEMY LCACs: the pattern to copy)
- Units `E_Unit02_02_Ship0..3` (faction 2, RadiusInMeter 7000, tags Wave02 / Wave02_LCAC_Unit): 2 AI objects each
  `E_Obj02_02_ShipN_lcac_0/1`, NPC `lcac_common` (DT_NPC_Mission013, child VE014_lcac_01 -> BP_VE014_lcac_CP), at sea
  (z -20), tags Wave02_LCAC_Obj, Obj_All_Enemy. Also `lcac_Destroyed` (wreck) and `BP_BPD_lcac_DAM01` rows.
- Paths `02_shipN_lcac_M_Path0` (4-5 points at z -20 ending on the beach), `02_ship0_lcac_0_Return_Path0..7`.
- Chain: spawn (LiveReinforcementExecution, tag Wave02) -> `02_ReinforcementAppearance` (type 23, tag Wave02) ->
  per craft `LiveAIPathExecution` {01 E_Obj02_02_ShipN_lcac_M, 02 NoneSelect, 04 path, 0a NoneSelect, 10 180, 10 30,
  10 50, 0e ObjectSetting, 10 1, 11 true, 11 false, ...} (2nd craft of some pairs delay 2) and per unit
  `LiveAIPathExecution` {01 NoneSelect, 02 E_Unit02_02_ShipN, 04 <lead path>, ..., 10 30.0, ...} ->
  `02_LCAC_PathFinish_N` (type 2d Finish) -> `LiveAIPathExitExecution` {01 craft, 02 NoneSelect},
  `LiveReinforcementExecution` {0a NoneSelect, 02 E_Unit02_02_Ground0, 11 false, 11 false} (btr9 troops at the beach),
  flag LCAC_PathFinish_N, 20 s later the return path (speed 30, accel 2). Destroy counters: `02_LCACDestroy_Landing_N`.
  Landing check: `02_02_Volume_LCAC_Landing_N` (type 3f, box `02_LCAC_LandingVolume`).
- Order matters (hard rule 5): unit spawn -> appearance -> craft path + unit path -> PathFinish -> path exit -> troops.
### The "ship that launches them"
None in stock: Missions 9, 13 and 24 spawn LCACs on the water. For Survival: spawn the LCAC pairs next to Mission 22's
enemy fleet (`EA_Unit_01_Ship0` (683432, 473608, 300): udaloy + 2 grigorovich; `_Ship1` (502524, -860430);
`_Ship2` (684655, 559433): gorshkov + 2 grigorovich; `_Ship3` (494936, -945672): kirov + grigorovich; all faction 2,
already in WD_SurvivalMode_global), so they look launched from it; a splash VFX (`NS_IGCVFX_lcac_splash001..3`) can hide
the pop-in.
### What a Comona version needs
- WD (build time): new AIPathDescs (`AIPathDescList` entries: BeginPointDesc {Pos, tan, Up, PointType, PathPointRotation,
  UniqueID, Name DefaultPathPoint} + PathPointDescList [{Pos, tan, Up, PointType 1 or 4, PathPointRotation, UniqueID,
  Name}] + ControlType + UniqueID + Name), z -20 on water, last point on the sand. 2-4 lanes from the fleet to Comona's
  beaches. New UnitDescs copied from M13's `E_Unit02_02_Ship0` (+ a ground troop desc like `E_Unit02_02_Ground0`).
- NPC rows: `lcac_common` / `VE014_lcac_01` are not in DT_NPC_Mission022: add them at run time (AddRow from Survival's
  own DT_SV_* copy of M13's rows), and add `BP_VE014_lcac_CP` (+ its Base) as imports in the WD and container header
  (hard rule 7). Alternative: set `AIObjectClass` directly (Mission 30/11 do that for dummies) - untested for vehicles.
- The WD trailer after the properties is an editor-style folder tree (`tools/scripts/wdtrail.py` parses/writes it:
  "Unit/Wave1..", "Path/..", "Marker", "Volume"). Adding descs without updating it worked so far for spawns; keep in
  mind if a new desc is "not found".
- Beach coordinates: unknown from data (no Comona landing paths in any mission). Get them in game: fly the shoreline
  and log the player position (Lua), or sample Map17 terrain heights. Open.

---------------------------------------------------------------------------------------------------------------------
## 13. Anomaly ace boss

### Formations (stock)
- Class `LiveAIFormationDataAsset` {bDirectEdit, Descs[], NativeClass}; `LiveAIFormationDesc` {ID (name), Settings
  {bAdsorbEnable, AdsorbDistanceMeter, AdsorbRate}, Formation[] of {Locations[] (vectors, leader space: x fwd,
  y right, z up)}}. `Formation[k]` is the layout with k followers lost (16 slots, 15, 14, ...).
- `LiveAIFormationComponent` {FormationDataAsset, FormationUnit {Name_WD}} lives in the **leader's blueprint**; the
  follower unit name is fixed in the BP.
- `LiveApplyFormationEvent` exec {01 leader AI object, 0d formation ID, 11 bool, 10 float} switches the layout.
- Mission 23 (Barrier UAVs): `E_Unit_Barrier_Air0..2` = 16 x `sv11w_common` (OP0025_sv11w) each; launched from the
  Celaeno airship (`B_Obj_01_Air0_Celaeno0`, OP0044/OP0049 cleo, `DA_Formation_cleo`: 16formation, _wide, _Wall,
  _Close, _SideGuard, _Wall_Up, _Wall_3rd, Right/Left_Wall, *Side_3rd, *Side_Near_3rd, _Charge).
  `Barrier_UAV_Spawn`: `LiveActorTeleportExecution` (UAV unit to the airship), `LiveFireOneShotWeapon` {0e WN_WEAPON_2,
  01 B_Obj_01_Air0_Celaeno0_UAVHatch_R1, ...} (hatch launch), `LiveAIEngagementOrder` {..., 02 E_Unit_Barrier_Air0,
  0e None, ...}, `LiveUnitMoveActor` (area onto the airship, 100000), `LiveApplyFormationEvent`
  {01 B_Obj_01_Air0_Celaeno0, 0d 16formation_Wall, 11 true, 10 0.0}; barrier on: each UAV `LiveFireOneShotWeapon`
  {0e WN_WEAPON_4, 01 E_Obj_01_Air0_Barrier_uav_N, ...}. Tied to the airship BP: not portable to a fighter.
- **Mission 26 (best fit)**: ace `EI_Unit_01_Air0` / `EI_Obj_01_Air0_x40a_0` (NPC `x40a_ms26`, OP1016_x40a, faction 2,
  RadiusInMeter 8000). `BP_OP1016_x40a_Base` has `LiveAIFormationComponent` {DA_Formation_x40a, FormationUnit
  "EUnit00_NightmareUAV0"}. `DA_Formation_x40a`: **Normal** = (40,0,-20) (-80,40,-20) (-80,-40,-20) (-10,0,40) m
  (4 guards boxing the ace in 3D), **HeadOn** = 4 slots 45 m ahead. Followers: `EUnit00_NightmareUAV0` = 4 x `uavn_ms26`
  (OP0024_uavn). Chain `Start_WaveI_UAV_Setting` (type 23 appear of EUnit00_NightmareUAV0, count 4), stock order:
  `LiveApplyFormationEvent` {01 EI_Obj_01_Air0_x40a_0, 0d Normal, 11 false, 10 0.0}; `LiveUnitMoveActor`
  {02 EUnit00_NightmareUAV0, 01 EI_Obj_01_Air0_x40a_0, 02 NoneSelect, 09 NoneSelect, 10 0, 10 9000.0, ...};
  `LiveSetActiveExecutionEventExecution` {0d uavn_container, 11 false}; `LiveAIEngagementOrder`
  {..., 02 EUnit00_NightmareUAV0, ..., 0e TransitAttackOnly, ...}; `LiveFireOneShotWeapon` {0e WN_WEAPON_5,
  01 NightmareUAV0..3, ...}.
- Mission 18 shows a **dummy as leader**: `A_Unit_00_Dummy_Player_Formation_Leader0` (NPC
  `Adummy_relative_rotation_ms18_01` -> `BP_DummyRelative_WithRotation_MS18_01`, class LiveAIRelativeLocateDummy
  {bEnableLocation, bEnableRotation}), `DA_Formation_Dummy_ms18` (Far, Far_Left/Right, Near, Near_Easy, Player),
  follower unit `A_Unit_00_Dummy_Player_Formation_Follower0`.
- Recommendation: ace = x40a desc copied from Mission 26 with its follower unit renamed exactly `EUnit00_NightmareUAV0`
  (the BP looks it up by that WD name). 4 guards, not 5; slots are fixed in the ace's frame (they turn with it, they don't
  orbit). For 5 guards on a rotating sphere: (a) a Survival copy of BP_DummyRelative_WithRotation_MS18_01 + own DA with
  5 slots, rotated by Lua; or (b) Lua/native positions on a rotating sphere (teleport each guard each frame). Guard
  attack when the player is within 5 km: `LiveCheckDistanceEvent` trigger (type 5a) {11 true (player), 01 NoneSelect,
  01 <ace object>, 0a NoneSelect, 0e AND, 10 5000.0, 11 false, ...} (distance in metres, cf. Mission 22's 10000/1500)
  -> `LiveAIEngagementOrder` on the guard unit.
### LiveAIGroundDummy (Missions 11, 19, 30)
`LiveAIGroundDummy` < `LiveAIArrangementObject` < LiveAIGameObject: the invisible path-follower behind
`BP_AI_Dummy_Ground` (NPC rows GR000_dummy / AI_Dummy_Ground; e.g. Mission 19's `N_Unit_01_BanTarget0` on
`N_Unit_01_BanTarget0_Path0`). Arrangement-object knobs: bKeepOnGround, RootHeight, MaximumSpeed, Acceleration,
RotationSpeed, ReachDistance, ArriveDistance. It has no aircraft mesh/flight model, so it can be the ace's **anchor**
(slow path in the air with bKeepOnGround off), not the ace itself. Related: LiveAIMinimalDummy,
LiveAIRelativeLocateDummy (BP_AI_Dummy_Relative_Air, Missions 11/30: AIObjectClass set directly, no NPC row),
LiveAIPlaneDummy (BP_AI_Dummy_Plane).
Floating ace options: (1) AI plane on a small loop path at its minimum speed (AceFlightEngineNpcParameterDataTable has
SpeedMin, so it can't truly hover); (2) native pin: SetActorLocation every frame (simple, may jitter against its AI);
(3) AI-object `AttachParentAIObjectName` to a slow dummy (the field exists on every AI object desc; stock attaches
volumes/paths to aircraft and children to airships; attaching a whole aircraft is untested). Try (3) then (2).

### Flight input path (the inverted pitch/roll)
Classes: `ALivePlayerPlane` (< LiveGameObject < Pawn; BP_PlayerPlane_Base_C), `ALivePlayerController`
(VibrationManager, InputComponentForIGC, AdaptiveTrigger), `ULiveFlightStickSubsystem` (DirectInput sticks, "StickPitch",
"StickRoll"). No Enhanced Input assets in the content (no IA_/IMC_). BP_PlayerPlane_Base has no input events.
Reflected properties on ALivePlayerPlane (offsets from the exe's codegen params, `propoff.py`):

| property | offset | note |
|---|---|---|
| InputThrottle / InputBrake / InputLeftYaw / InputRightYaw | 0xFE4 / 0xFE8 / 0xFEC / 0xFF0 | float |
| **InputRoll / InputPitch** | **0xFF4 / 0xFF8** | float, -1..1 |
| bEnableMovmentInput | 0x1309 (byte bool) | also UFUNCTION SetEnableMovementInput |
| bIsPitchAxisReversed / bIsTrottleYawReversed | 0x1311 / 0x1312 | the player's option (native code never reads 0x1311 directly; only the constructor writes it) |
| bIsHighGTurnSingleButton / bIsABMaxSingleButton | 0x1313 / 0x1314 | read by BuildFlightInput |
| JammingEffectFadePerSeconds / LocalUserSettings | 0x11BC / 0x1B40 | |

**BuildFlightInput 0x147d689b0** `void(ALivePlayerPlane* plane, FPlaneInput* out)`, unique 16-byte signature
`40 53 48 83 EC 20 80 B9 DC 58 00 00 00 4C 8B DA` (push rbx; sub rsp,20h; cmp byte [rcx+58DCh],0; mov r11,rdx: no
RIP-relative code in the first 16 bytes, instruction boundaries 0/2/6/13/16, so an inline trampoline is easy):
- if `plane+0x58DC` (input blocked): out = zeros, flags 4.
- out+0x0 Pitch = clamp(InputPitch * plane[+0x6C8], -1, 1); out+0x4 Yaw = clamp((InputRightYaw - InputLeftYaw) * k);
  out+0x8 **Roll** = clamp(InputRoll * k); out+0xC Throttle; out+0x10 Brake; out+0x14 combined; out+0x18 flag byte.
  `plane+0x6C8` is a control-authority factor clamped to 0..1, recomputed every tick (0x147d5bdb7): it can't be set
  negative.
- Callers: the plane update 0x147d63bfb (BuildFlightInput -> `FlightEngine::SetInput` 0x144d32580 on plane+0x2268 ->
  `FlightEngine::Update` 0x144d326e0(dt)), 0x147d7f743 (plane), 0x1479f35c0, 0x1470a46d8, 0x1471929c9 (other users,
  e.g. replay/network). SetInput (sig `48 83 EC 38 F6 42 18 01 0F 57 C9 F3 0F 10 05 ?? ?? ?? ??`) negates pitch/yaw/roll
  itself (engine convention) and zeroes all when flag bit 0 is set.
**Recommended hook (native runtime):** inline-detour BuildFlightInput; call the original, then if the anomaly field is
active and `plane` is the local player plane: `out->Pitch *= s; out->Roll *= s` with s going 1 -> -1 over ~2 s
(s = 1 - 2t). Config pitch/roll/both picks which. Expose `SV_SetControlInvert(pitch, roll, fade_s)` to Lua like the
spawner functions; Lua decides when (distance to the ace < 3 km, ace alive). Advantages: the out struct is rebuilt every
call (no double-flip), clamps already applied, and replays record the same values the engine used.
Alternatives (weaker):
- Lua writing `plane.InputPitch = -plane.InputPitch`: the per-frame writer of these fields wasn't found (no direct
  float store to +0xFF8 by player-input code; values may arrive through a pointer registered at 0x147daf270 ->
  0x1478fb5e0 with &plane+0xFF8). From a LoopAsync it races the game thread and can double-flip. Not recommended.
- `UPlayerInput::InvertAxis(FName)` / `InvertAxisKey(FKey)` (reflected exec UFUNCTIONs) flip legacy axis mappings, but
  the game's axis names live in Config/DefaultInput.ini inside the encrypted .pak (not read), and it may not use them
  for flight at all. A Lua probe could dump `PlayerInput.AxisMappings` at run time.
- Game options: `LiveKeyConfigSaveData.bIsLeftStickReversed / bIsRightStickReversed` (save data) and the plane's
  bIsPitchAxisReversed: pitch only, persistent settings; no roll invert option exists.
- No stock "inverted controls" effect: Mission 15's `LiveActivateGlassesEffectExecution` / `LiveDeactivate...` (no args)
  and `LiveStartHUDRaderMapNoiseExecution` {10 a, 10 b, 10 c} (stock: 4/3/6, 5/5/8, 3/5/10, 50/10/15) +
  `LiveStopHUDRaderMapNoiseExecution` are visual only; use them as the anomaly-field presentation. ECM jamming
  (`LiveElectronicJamming`, `LiveTargetSelectionComponent.bIsJammed`) affects lock-on, not controls.
- Reflected `LivePlayerPlane::FrameUpdate(float DeltaSeconds)` is a possible UE4SS RegisterHook point if it turns out to
  run through ProcessEvent every frame (unverified); still the field-race problem above.

---------------------------------------------------------------------------------------------------------------------
## Open questions
1. Do `Mission019_Common_VFX`'s 8 Niagara actors auto-activate? (If yes, never add that sublevel.)
2. Mission 22's radio lines (countdown, liftoff, "pad under attack") playing in Survival: radio table comes from
   Survival's MC (Mission 22's) - confirm in a test; also whether they name Mission 22 characters (Baxter etc.).
3. SV_Spawn of `AA_Unit_01_Ground0` "in place" (desc position) and destroying its allied guns, vs a trimmed desc.
4. LiveAIPathExecution / LiveApplyFormationEvent arg semantics are known by value only (speed, accel, ...; the formation
   bool/float may be warp/blend). Copy stock values.
5. Enemy LCAC NPC rows at run time (DT_NPC_Mission022 AddRow) vs direct AIObjectClass; whether BP_VE014_lcac_CP needs
   its Base/wake BPs (BP_LiveWaveSpawner_Wake_LCAC) imported too.
6. Comona beach coordinates for LCAC lanes and landing volumes (in-game sampling).
7. x40a guards = 4 fixed slots; 5 orbiting guards need a Survival formation asset + leader BP copy or Lua positioning.
8. Attaching an aircraft AI object to a moving dummy (`AttachParentAIObjectName`) for the floating ace.
9. BuildFlightInput detour: verify `plane` is the local player (callers at 0x1479f35c0 / 0x1470a46d8 / 0x1471929c9 may
   pass replay/network planes) - compare against the player pawn before flipping.
