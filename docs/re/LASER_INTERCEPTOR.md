# AC7's LaserInterceptor: research for a later port (2026-11-06)

User (2026-11-06): "I want you to take a look at the LaserInterceptor Weapon in Ace Combat 7, I want to use that later."
Research only: nothing built, nothing installed, no game run.
Tags: **[D]** confirmed in data, **[I]** inferred, **[T]** needs an in-game test.

Project rule first: Survival ships only AC8's own files. The one AC7 exception is VALKA's (X-02S, Mihaly's railgun
effects and sounds, see VALKA.md). Using AC7's beam effects or sounds for this weapon would be a **second exception**, and
only the user can grant it. AC8 has its own missile-killing laser (section 5), and that route needs no AC7 assets.

Scratch outputs (git-ignored, on the build machine): `build\ac7\laser\` (the main tree): `dec\` (decrypted AC7
packages), `json\` (UAssetGUI dumps, `*.dump.txt` property dumps, `*.k.txt` Kismet, `*.sum.txt` particle summaries),
`ac8\` (AC8 stock packages pulled with retoc), `sfx\` (AC7 sounds from ac7_sfx.py), `scripts\` (scan.py: in-memory
search of the encrypted AC7 export; pdump.py, psys.py, dtdump.py, ac7exe.py, ac8cdo.py, ac8imp.py), `scan_*.tsv`.

## 0. AC7 units
AC7's world is at 1/10 scale: the F-22's mesh (f22a_SM) is 190 units long, and the real aircraft is 18.9 m. That makes
**1 AC7 unit about 0.1 m** [I] (the same reason VALKA.md says "never convert AC7 distances as cm"). AI speeds in the
`*_config` tables are km/h [I]. Every distance below is shown as AC7 units, with metres from that scale in brackets.

## 1. What it is
- `/Game/Blueprint/Weapons/AI/Base/wp_LaserInterceptor` (class `wp_LaserInterceptor_C`) derives from the native
  `/Script/Nimbus.LaserInterceptor` (ALaserInterceptor). WeaponID `EWeaponID::WID_AI_laser_interceptor` [D].
- It's an AI **anti-missile laser**: a beam that swings onto an incoming missile and destroys it. The evidence:
  - the native class's own properties: InterceptAngle, InterceptTime, SearchInterval, a swing curve [D];
  - AC8 carries the same class over (section 5) with a `ALiveMissile* MissileToIntercept` field [D];
  - Mission 20 binds the mission event `MissionEventObjectInterceptWeapon(Causer, Weapon, InterceptedShooter,
    InterceptedWeapon)` and casts the Weapon to `wp_LaserInterceptor_C` (section 3) [D].
- Its beam does NOT damage aircraft, only missiles (the user, from playing AC7, 2026-11-06), although the blueprint
  carries Damage 10. A port must keep it missiles-only.

### 1a. Class defaults (wp_LaserInterceptor CDO) [D]
| property | value | note |
|---|---|---|
| RayDistance (native) | 12400 (~1.24 km) | beam length; also feeds the beam particle's BeamLength.X |
| RayRadius (native) | 150 (~15 m) | the ray's sweep radius [I: a sphere sweep along the beam] |
| SwingRateCurve (native) | CUR_LaserInterceptorSwingRate | see 1c |
| Damage | 10 | |
| LifeTime | 6.0 s | how long one beam lasts |
| TrailTime | 2.0 | |
| FCSAngleLimit | 180 deg | fires in any direction |
| FCSActivationDist | 12000 (~1.2 km) | [I] the FCS target's range at which it fires |
| FCSActivationTime | 0.1 s | |
| FCSVolleyTime / FCSVolleyFireInterval | 6.0 / 6.0 s | one 6 s beam a volley |
| FCSVolleyRestInterval | 8.0 s | so one beam about every 14 s [I] |
| FCSForesightAmount | 0.09 | |
| bShouldResetTimer | false | |
| bIsBaseAttached | true | stays on its carrier |
| hangar mesh / rack | w_tls_x0_SM (the TLS pod), WeaponRack_w_mop | for display only |
| HUD icons | w_qaa_a0, w_qaa_a0_inside | |
| impact FX | FX_ConcreteImpact_M01, FX_WaterImpact_M03, FX_GroundImpact_M01, FX_IcebergImpact_M01; decals bullet_*_decal_Inst (64 x 16 x 16) | |

There's **no `LevelModifiersDataTable`** on it, while the UAV's attack laser wp_laser_uav_2 sets WpnPilotRankConfig [D].
So the interceptor most likely isn't scaled by pilot rank [I].

### 1b. Native properties the blueprint leaves at the C++ defaults
AC7's exe (<AC7 install>\Ace7Game.exe) has readable reflection data. Its code is
SteamStub-encrypted (a `.bind` section, `.text` disassembles to garbage), so its constructor can't be read [D]. Layout from
the reflection params (sizeof 0x698) [D]:

| offset | property | AC7 BP sets | default (from AC8's copy of the class, section 5) |
|---|---|---|---|
| 0x650 | RayDistance | 12400 | 0 |
| 0x654 | RayRadius | 150 | 0 |
| 0x658 | InterceptAngle | - | 180 deg [I for AC7] |
| 0x65c | SearchInterval | - | 0.5 s [I for AC7] |
| 0x660 | InterceptTime | - | 1.0 s [I for AC7] |
| 0x668 | InertiaTime | - | 1.0 s [I for AC7] |
| bit field | bInertia | - | false [I for AC7] |
| 0x670 | SwingRateCurve | the curve | null |

RayRadius and RayDistance are BlueprintReadOnly. The other properties are edit-only (property flags 0x...14 vs 0x...01) [D].
The defaults are AC8's (its UE4SS header dump reads them off the CDO). AC7's own constructor can't be read, so they're
only probably the same [I].

How it works, inferred from the names [I]: every SearchInterval (0.5 s) it looks for a missile within InterceptAngle
(180 deg). It swings the beam onto the missile over InterceptTime (1 s), with the curve shaping the swing. A missile
inside the ray (RayDistance x RayRadius) is destroyed, and the weapon raises OnObjectInterceptWeapon. With bInertia
off, InertiaTime does nothing. No hit chance exists in AC7's data (AC8's swing TLS has one, 0.3). [T] for all of it.

### 1c. CUR_LaserInterceptorSwingRate [D]
Two keys: (t 0, v 0, cubic, auto tangents, both tangents 0) and (t 1, v 1, linear). The segment between them is a
smoothstep, 3t^2 - 2t^3: the swing starts slowly, speeds up, and settles on the target. t is most likely the share of
InterceptTime that has passed [I].

### 1d. The blueprint's own script (ExecuteUbergraph, kdec.py) [D]
- OnCreateWeaponEnd: `EndLaser.SetActive(false)`, `MainLaser.SetActive(true, reset)`, `MainLaser.SetVisibility(true)`,
  `EndLaserTimer = 0.2`, `EndLaserMaxTime = EndLaserTimer` (0.2), `LaserScale = 1`.
- Every tick: MainLaser vector parameter `BeamLength = (RayDistance, LaserScale, LaserScale)`, float
  `BeamLifeTime = GetLifeTime() + EndLaserMaxTime` (6.2 s), and `LightLifeTime = GetLifeTime() - 0.5` (5.5 s). Once
  `IsDestroyed()`: `EndLaserTimer -= dt`, `LaserScale = clamp(EndLaserTimer / EndLaserMaxTime, 0, 1)`, so the beam
  thins to nothing over 0.2 s.
- OnLifeTimeExpired: `EndLaser.SetActive(true, reset)`, `EndLaser.SetVisibility(true)` (the closing flash).
- The components: `MainLaser` (ParticleSystemComponent FX_UAV_TLS_Muzzleflash01, at X -30, instance params BeamLength,
  BeamLifeTime) and `EndLaser` (FX_UAV_TLS_Muzzleflash02, at X -30), both attached to the native `Static Mesh` root.

## 2. Data rows
- **No AC7 table row holds this weapon** [D]. A scan of all 24,681 packages of the export (decrypted in memory) finds
  `WID_AI_laser_interceptor` / `LaserInterceptor` in only three places: the weapon, its curve, and Mission 20's
  ms20_Phase_01. AC7 keeps weapon values on the weapon blueprint's CDO (section 1a).
- Rank and difficulty: `Blueprint/AI/Difficulty/WpnConfig/WpnPilotRankConfig` holds per-pilot-rank multipliers (rows
  1-5 = Rookie, Normal, Veteran, Ace, Rival) on Damage, LifeTime and the FCS* values. Rank 5 for example: FCSActivationDist
  x1.2, rest x0.85, LifeTime x1.25. Only weapons that name the table use it, and this one doesn't (1a) [D].
- The carrier's flight table `uavw_config` is the same for all 5 rows: PitchSpeed 90, RollSpeed 240, YawSpeed 4,
  SpeedNormal 600, SpeedMax 2600, SpeedMin 300, SpeedTurn 800, Acceleration / Deceleration 300 [D].

## 3. Who carries it in AC7 [D]
- **Only `Blueprint/AI/Actors/Plane/common_uavw`**, the "weapon UAV": an AIPlane_Pawn_C on the w_uav_x0 mesh (about
  5.3 m long), MaxHealth 40, KillBountyScore 500, ObjNameID ContainerAircraft_Name_uavw, SubCategory UAV, no flares.
  Its AIFireControlSystem has **Weapon1 = wp_laser_uav_2** (an attack laser: WID_tls, DamageDistance 20400, radius 100,
  damage every 0.33 s, warm-up 0.95 s, life 6 s, FCS 40000 / 45 deg, volley 6 s, rest 8 s, rank-scaled) and
  **Weapon2 = wp_LaserInterceptor**. Its evade, provoke and escape behaviour trees are UAV ones (UAV_evamis_Short_adv, ...).
- **Only Mission 20 uses it** (ms20_Phase_01). There are four weapon UAVs: 01_en_weaponUAV_1_1 / _1_2 (unit
  01_en_weaponUAV_1, radius 60000) and 01_en_weaponUAV_2_1 / _2_2. Each pair escorts one ADF-11F: 01_en_ultimateUAV_1_1
  is ms20_adf11f_Hugin_C, _2_1 is ms20_adf11f_Munin_C, both AILevel 3. The mission:
  - launches them from their ADF-11F: `ActivateUnit(weaponUAV_N, ..., 0.5, 3, ..., ultimateUAV_N_1)`;
  - keeps them 3000 units (~300 m) behind it: `MoveToActor(weaponUAV_N, ultimateUAV_N_1, ..., 3000, 15, (-3000, 0, 0))`.
    The move tasks are labelled "レーザー攻撃" (laser attack), "レーザーミサイル破..." (laser missile kill) and "ミサイル破壊"
    (missile kill). It also sets them to 2400 speed, plays `RequestSpecialAction(UavDefence_N)`, and gives them
    `EngagementOrder(2, player, ...)`;
  - **never fires the interceptor itself**: the UAV's own FCS fires it;
  - reacts to it in two places. On `MissionEventObjectFireWeapon` where the weapon is either laser,
    `weaponUAV_FireLaser(causer)` starts a 6.2 s timer (the beam's 6 s + 0.2 s), and when it runs out that UAV's
    `EngagementOrderOverride` goes back to attacking the player (mode 2) or to mode 5. On
    `MissionEventObjectInterceptWeapon` with Weapon = wp_LaserInterceptor, InterceptedShooter of object type 1 (the
    player) and InterceptedWeapon of weapon type 7, while fewer than 2 UAVs are down, it plays the radio lines
    `01_wuav_intercept_1` / `_2`. Those are voice lines, so **never use them**.
- AC7's other interceptor is a different class: the CIWS, `AttachedInterceptorWeapon` (wp_ciws:
  InterceptDistanceSquared 210250000 (~1.45 km), InterceptAngle 180, InterceptFireDuration 1.3 s, FCSActivationDist
  80000; wp_ex02_ciws_AegisAshore: SearchType All, bPrediction, BulletSpeedKmphForPrediction 2300, MissileRefCountLimit 3) [D].

## 4. Looks and sound (AC7)
### Beam: FX_UAV_TLS_Muzzleflash01 (Cascade, `/Game/VFX/Vehicles/Weapon/TLS/`) [D]
Every emitter is local-space, colour (100, 21.5, 22.8) HDR (a hot red) with alpha 1. The materials are m_TLS_01,
m_TLS_01_wire, m_TLS_02 and m_TLS_03: all Unlit Translucent, used with mesh and sprite particles. m_TLS_02 has
AngleFadePower and FadeNear/FarCamera_Distance parameters; m_TLS_03 uses T_rain_drop.
| emitter | what | timing |
|---|---|---|
| omen | sparks along a cylinder 0-4100 units long (~410 m), radius 0.4-0.05, size 0.3 x 1-5, velocity -100 X, 0.05 s each | bursts of 2/4/8/16/30/60/70/80 at 0, 0.075, 0.35, 0.40, 0.55, 0.645, 0.66, 0.675 s (the charge-up) |
| flash | mesh SM_TLS_01 (m_TLS_02), size 0.3, colour over life, light | 0.2 s from 0.8 s |
| Beam_Root | mesh SM_TLS_projectile_root, size (1, 0.6, 0.6), Y/Z scaled by BeamLength (LaserScale), spins 100 | from 0.9 s, life = BeamLifeTime |
| Beam_Tip / Beam_Tip_wire | mesh SM_TLS_projectile_tip (25.7 units long) at X size 0.04 x BeamLength.X, so about 1.03 x RayDistance long; m_TLS_01 / m_TLS_01_wire | from 0.9 s, life = BeamLifeTime |
| Light_emitter | mesh + a particle light, radius scale 90, colour scale (0.9, 0.8, 1), no inverse-square falloff | from 0.9 s, life = LightLifeTime |
Fixed bounds X 20..1,000,000, Y/Z +-40. The beam's core is about 2.2 units (~0.2 m) thick; the HDR colour and bloom
carry the look.

### End: FX_UAV_TLS_Muzzleflash02 [D]
- Beam_Tip: X stretched 100 x 20, collapsing to 0 over 0.2 s.
- "end": sparks, bursts of 80+ on a 1000-unit cylinder, from 0.15 s.
- Beam_Root: a 0.2 s light flash.

### Sound
The interceptor's package names **no sound** [D]. Any sound it makes comes from native code (can't be read, 1b), or
there is none [T]. AC7's exe holds these laser event names as strings: SPWP_OTH_TLS_HIT, SPWP_OTH_TLS_PASS and
SPWP_OTH_TLS_PASS_Stop. The player TLS uses SPWP_OTH_TLS_SHOOT / _Stop. Extracted with
`tools/ac7_sfx.py --alt "" --out build/ac7/laser/sfx` from the stock game_se.bnk [D]:
- SHOOT: two layers, both looping; 0.96 s and 1.0 s; +10 / +5 dB.
- HIT: a switch container of three 2.2-3.3 s variants.
- PASS: three loops of 1.2-3.4 s.
- Attenuation 20000 units for SHOOT. Each event's TREE.txt sits next to its WAVs.

## 5. AC8's equivalents [D unless tagged]
- **AC8 still has the class:** `ALiveLaserInterceptor : ALiveAttachedWeapon` (build/liveproject
  Live/Public/LiveLaserInterceptor.h). It has the same properties plus `ALiveMissile* MissileToIntercept`, and
  MainLaser / EndLaser are still *Cascade* ParticleSystemComponents. `ELiveWeaponID::WID_AI_laser_interceptor` is there
  too. The CDO defaults are in 1b. Its script object hash is 0x4924eb83c12a0e05 (CDO 0x673669ad763cd056). No stock AC8
  package is named for it, so it's likely a leftover nothing uses [I]. Whether its native tick still works in AC8 is
  unknown [T].
- **AC8's own missile-killing laser: `ALiveTLSSwingforMissile`**, used as
  `/Game/Blueprints/Weapons/Laser/Tls/UAVN/BP_SwingTLS_ForMSL`. CDO:
  - InterceptAngle 45 deg; InterceptDistanceSquared 9e10 (3 km); **InterceptPercentage 0.3**;
  - SwingLifeTime 2 s; ShotInterval 1 s;
  - DamageDistance 1,000,000 (10 km); DamageRadius 1000 (10 m); SlipDamage 1; DamageInterval 0.2;
  - yaw range +-90; damage 3; LifeTime 8; LoadTime 1; WeaponID WID_tls;
  - beam Niagara `/Game/VFX/Vehicles/Weapon/TLS/NS_NPC_TLS_Muzleflash01` (User.BeamLength);
  - sounds `AKE_GEN_ARMS_SKY_OP0024_uavn_PulseLaser_Fire_Play` / `_Stop`, hit `/Game/WwiseAssets/Events/SFX/SPWP_OTH_TLS_HIT`
    (AC8's own asset under AC7's name).
  Its sibling BP_SwingTLS_ForPlane (`ALiveTLSSwingforPlane`) is the attack sweep: bHomingSwing, SwingSpeed 41667,
  PredictionOffsetTime 5, MoveStartTime 2, LifeTime 7.
- **Who carries them:** the Nightmare UAV, `BP_OP0024_uavn_CP` (DT_NPC_Model OP0024_uavn / OP0024_uavn_MS26, 60 HP;
  DT_NPC OP0024_uavn_01 / _MS26, rank 4, LuaSet NLID_0001_CP, no NpcFCSIds). Its fire control is in the blueprint
  (AllArms):
  - slot 0 "TLSforPlane": BoneControl capture only 100 (1 m), so it fires on command only [I];
  - **slot 1 "TLSforMSL"**: `LiveFCSModule_AIControlCIWS { bSearchMissileOnly = true }`, LauncherBoneControl on
    BN_turret_yaw (360 deg/s, +-180) / BN_turret_pitch (+-90), CaptureDistance 300000 (3 km), CaptureAngleRange 30,
    ActivationTime 0.1, TriggeringTime / ShotIntervalTime 8 s, RestingTime 1 s, ReloadTime 1 s, weapon BP_SwingTLS_ForMSL;
  - slot 4: overrides the base's arm; the base imports the pulse laser BP_wp_plsl_BaseClass and the barrier.
  The base, BP_OP0024_uavn_Base, has dock and barrier state machines and the blackboard BB_AINightmareUAVBehavior.
  Mission 26 uses NightmareUAV0-3 (docked to the X-40A; it fires their WN_WEAPON_5, triggers BarrierVanished / Docked).
  Nothing in the mission fires the TLSforMSL: the arm's own CIWS AI does [I].
- **CIWS interceptors:** `ALiveAttachedInterceptorWeapon` (InterceptAngle, InterceptFireDuration, InterceptPercentage,
  SearchType, InterceptDistanceSquared, MissileToIntercept). In DT_NPC_Weapon: CIWS_Vessel_000 / TrainingCIWS_Vessel_000
  (InterceptAngle 120, 1.2 s, SearchType 1 (All), 2500 m). DT_NPC_Weapon rows carry the interceptor fields (bPrediction,
  MissileRefCountLimit, bIgnorePlayerMissileHomingToOneself, InterceptDistanceInMeters, ...). Survival's airfield CIWS
  already fires on CIWS_Vessel_000 (AIRFIELD_SUPPLY.md 4b).
- **An event for each interception:** trigger `WeaponIntercept` (ELiveEventTriggerType, FLiveWeaponInterceptTrigger
  { InterceptedWeaponOwner, FiredWeaponOwner }). Mission 16 has 8 of them (type 0x65) on the Ladons' LCIWS parts
  (`Default_WeaponIntercept*`). It's AC8's counterpart of AC7's MissionEventObjectInterceptWeapon.
- Other AC8 lasers, none of which intercept [I]:
  - the TLS: BP_wp_tls_BaseClass, NPC BP_wp_tls_x0, player BP_plwp_tls_x0, UAV BP_uavwp_tls;
  - laser pods: OP0034_aship / OP0038_ep40 / OP1016_x40a LaserPod (NS_SearchLaser), GR044_lass;
  - OP0033_uavst_laser;
  - pulse lasers: BP_wp_plsl_BaseClass, barrier pulses.

## 6. Port routes (recommendation first)
1. **AC8's BP_SwingTLS_ForMSL on AC8's Nightmare UAV (no AC7 assets).**
   - How: a Survival flight on DT_NPC row OP0024_uavn_01, ported from Mission 26's world data (hard rules 15, 20, 31).
     Its slot 1 kills player missiles on its own: within 3 km, 30 deg capture, 45 deg intercept cone, a 30 % chance
     per shot, a 2 s swing, 8 s on and 1 s rest.
   - Risks [T]:
     - the dock and barrier state machines and the Nightmare UAV blackboard may expect the X-40A (Mission 26 docks
       them), so it may not fly or fight alone;
     - its behaviour set is built at level load (hard rule 20);
     - a 60 HP drone is a "shield" the player must kill first;
     - whether the intercept fires the WeaponIntercept trigger.
   - Count interceptions with a WeaponIntercept trigger copied from Mission 16.
2. **The same weapon on another carrier.** Survival generates a BP_FCS-style package (or a world-data / NPC row
   change) that clones the TLSforMSL arm: AIControlCIWS bSearchMissileOnly + launcher + ProjectileCommon
   BP_SwingTLS_ForMSL_C.
   - Risks: the arm aims with LauncherBoneControl on BN_turret_yaw / BN_turret_pitch, the UAVN's TurretSkelMesh
     bones, so a carrier without them needs a LauncherCommon arm [T]; no stock DT_NPC_FCS row exists to copy; and
     whether AIControlCIWS runs on an AI plane outside this blueprint is unknown [T].
   - Hard rule 38 (parts mounted through ChildNPCId) is the model for a part-based mount.
3. **Lua emulation.**
   - How: Survival's Lua already finds missiles (sv_weaponlog.lua's LiveExplosiveWeapon pool watch; sv_ladon.lua edits
     live missiles). Every 0.5 s, per carrier: find player missiles within ~1.2-3 km and the cone, roll the chance, and
     after a 1 s swing kill the missile. Draw the beam by spawning NS_NPC_TLS_Muzleflash01 with User.BeamLength aimed at
     it, and post the pulse-laser and TLS_HIT sounds.
   - Risks: AC8 has no reflected "intercept or explode" call on ALiveMissile / ALiveWeaponBase (only IsDestroyed and
     getters), so killing a pooled missile cleanly from Lua is unproven [T]. Destroying pooled actors is dangerous: see
     the co-op crash notes on freed objects.
   - In co-op this runs on each game: a missile's outcome is decided on its target's game.
4. **AC7's own class and look in AC8 (needs the user's AC7-asset exception).**
   - How: a blueprint of AC8's ALiveLaserInterceptor (1a values, the curve), cooked VERSIONED in ue/Live (hard rule 42),
     with AC7's Cascade beam (meshes SM_TLS_*, materials m_TLS_*) rebuilt in UE 5.4.
   - Risks: whether AC8 still runs that class's native logic [T]; which fire control fires it (AC8 fires weapons
     through FCS arms, not AC7's AIFireControlSystem Weapon1/2); Cascade material compatibility.

## 7. Not determined
- AC7's native defaults (1b) and the exact intercept test: AC7's code is encrypted. The AC8 dump's defaults are a stand-in.
- Whether "FCSActivationDist" measures the distance to the player or to the missile. (Aircraft damage is settled: none,
  missiles only; the user, 2026-11-06.)
- What EngagementOrderOverride mode 5 and the special action UavDefence_N do in Mission 20.
- Whether any AC8 package uses ALiveLaserInterceptor. Scan the import maps for 0x4924eb83c12a0e05 to find out; the
  package names show none.
- The colour of NS_NPC_TLS_Muzleflash01, and AC8's own SPWP_OTH_TLS_* sounds (not compared with AC7's).

## 8. Built (2026-11-07): route 2 on the VAMPIRES' ZFA-44s (built and checked, NOT yet run in game)
The ZFA-44 carriers' planes (the Su-47 host, DT_NPC SV_Zfa_Ally) carry AC8's own BP_SwingTLS_ForMSL (stock, unchanged)
in fire-control slot 3 (the Su-47's AllArms: Flare, Gun, Msl, then 3-5 free). No AC7 asset. Names:
tools/survival_events_escort.py ZFA_TLS_*.
- **The arm**, `/Game/Mods/SurvivalMode/Weapons/BP_FCS_SV_ZfaTLS` (tools/build_survival_world.py build_zfa_laser): a copy
  of BP_FCS_Vessel_CIWS_00. Its objects keep their names (class BP_FCS_Vessel_CIWS_00_C), as the menu pages' copies do.
  - Its 8 imports of BP_wp_ciws_vessel point at BP_SwingTLS_ForMSL's 7 public exports by role: the class, the CDO,
    WeaponCollisionEffectModule, BulletVFX NS / CS -> MainLaser / EndLaser Niagara, DefaultSceneRoot_GEN_VARIABLE and
    Static Mesh. The CIWS's ParticleUpdateHandler is a null import with its hash dropped: no dependency and no property
    value refers to it (the build checks), and the Nightmare UAV imports these same 7.
  - Its launcher is a LauncherCommon (BP_FCS_ECM_00's class ids) on PlaneBodyMesh, slot sockets GUN (the Su-47's
    SOC_Gun_01, as its own gun arm). It takes the UAVN's numbers (FireRate 8, reload 1 s, 3 km, 0.1 / 8 / 8 / 1 s), but
    with CaptureAngleRange 180 (no turret).
  - Its AIControlCIWS has bSearchMissileOnly, lock / loss radius 3 / 3.3 km.
- **Rows.** DT_SV_NpcFCS has SV_FCS_ZfaTLS: NPC_FCS_VesselCIWS000's row with FCSBlueprintClass the arm, no weapon or AI
  module row, 3000 m, 180 deg, 8 / 1 / 0.1 / 8 / 8 / 1, yaw and pitch all round. DT_SV_NpcRows has SV_Zfa_AllyTLS,
  SV_Zfa_Ally with NpcFCSId3 = SV_FCS_ZfaTLS (build_survival.py build_npc_rows).
- **Lua**: Scripts/sv_escort_laser.lua (ZLAS; sv_escort's family). The setting is CFG.allies.carrier.zfa.laser (true;
  survival.default.ini [allies.carrier.zfa] laser; read at the main menu). ESC.setup adds SV_FCS_ZfaTLS to DT_NPC_FCS
  (FindRow + AddRow from DT_SV_NpcFCS, never read: hard rule 29), then DT_NPC's SV_Zfa_Ally from SV_Zfa_AllyTLS's struct.
  If either can't be done, or the laser is off, the plain SV_Zfa_Ally goes in.
- **The count**: trigger SV_ZfaTLSHit (Mission 29's WeaponIntercept_UAV_TLS without its 'uav' tag: WID_tls, NoneSelect,
  NoneSelect, NoneSelect, true, Mission 27's CIWS shape) -> SV_ZfaTLSHits + 1. Only the ZFA-44s fire a WID_tls intercept
  in Survival.
- **Checks**: build_survival.py check_zfa_laser_build covers the package, the rows, the trigger and the Lua names.
  tools/checks/escort_test.lua covers the row choice (on, off, no row, no DT_NPC_FCS; the FCS row passed on unread), the
  arms line and the count.

Log lines (AC8SurvivalMode_lua.log):
- `escort: the escorts' and the ZFA-44's rows: ..., SV_Zfa_Ally in DT_NPC (with the anti-missile laser: SV_Zfa_AllyTLS's
  struct, its slot 3 SV_FCS_ZfaTLS, that row in DT_NPC_FCS)`. Otherwise `(laser off: the plain host)`,
  `(no laser: <why>)` or `(laser error: ...)`.
- `zfa laser: <unit> plane <addr> fire control: 0 <system> <weapon>; ...; 3 BP_FCS_CIWS BP_SwingTLS_ForMSL (Survival's
  arm) -> the laser in slot 3`. This comes once a plane, at most CFG...zfa.laser_arms_log (40) a run, settle_s after the
  plane is seen. It ends `-> NO laser arm` when armed and the arm wasn't there, or reads `no fire control read`.
- `carrier: the ZFA-44s' lasers have shot down N missiles (+d)`.

In-game test checklist:
1. The main menu's row line says "with the anti-missile laser".
2. With a carrier's ZFA-44s up, their `zfa laser:` lines show slot 3 as Survival's arm with BP_SwingTLS_ForMSL. If not,
   the row didn't take; next try K2_DynamicSystemOverride(3, the arm's class) at the dress.
3. No crash at their spawn: the arm loads by its soft path, null import and all.
4. Enemy missiles near the ZFA-44s: is there a beam (NS_NPC_TLS_Muzleflash01, from the gun socket)? Are missiles shot
   down, and does the count line go up? Does it take missiles aimed at others and from behind (a fixed launcher, the
   TLS's own 45 deg InterceptAngle, its ±90 sweep, a 30 % chance a shot)?
5. Never at you or your missiles. Does its beam (damage 3) hurt enemy planes?
6. Is Normal engagement enough? (Mission 29 orders TransitAttackOnly for its intercept mode.)
7. Co-op: a joiner's own ZFA-44s too, each game counting its own.
8. laser = false: the plain host, no arm in slot 3.
If it never fires on its own: Lua could fire slot 3 with LiveFireOneShotWeapon WN_WEAPON_4 (no target) when an enemy
missile is within 3 km.

## 9. AC8's native ALiveLaserInterceptor (reverse engineered 2026-11-07)
Read-only RE of the installed AceCombat8.exe (as of 2026-11-07). Nothing built, nothing installed, no game run. AC7's exe was
not touched. Scratch: `build/re/laser/` in the worktree (`scripts/` cls.py, ctor.py, vt.py, props.py, dis.py; the
disassembly dumps `li_*.txt`, `tm_*.txt`, `wm_*.txt`, `proj_module.txt`, `ciws_module.txt`; `vtables.txt`; `sigs.txt`).
Method: class registry -> StaticClass -> InternalConstructor -> real constructor -> vtable (the constructors run through
protector thunks in `.sbss`, e.g. 0x146e905c0 -> 0x15990dfc0, but every function below is plain `.text`); property
offsets from the compiled-in FPropertyParams; slots compared against the parent vtables.
Verdict: **the class is complete, working native code** (search, swing, kill, beam parameters, online replication),
not a stub. No stock content is known to use it [I], and it has bugs and missing guards that matter for a port
(9.4). It needs values that its defaults don't have.

### 9.1 Class, constructor, vtable [D]
| what | address |
|---|---|
| StaticClass / Z_Construct / ClassParams | 0x146e8e170 / 0x146e8e280 / 0x14c78d1d0 |
| class flags | 0x8000a4 (Native, Config, MatchedSerializers, HasInstancedReference): **not Abstract**, spawnable; 2 functions, 14 properties |
| constructor | 0x147ef5870 (InternalConstructor 0x146e905c0 -> thunk 0x15990dfc0) |
| vtable | **0x14c78d230**, 279 slots: 0-227 AActor's, 228-278 ALiveWeaponBase's own virtuals |
| parents' vtables | ALiveAttachedWeapon 0x14c5acc10, ALiveWeaponBase 0x14cae2170, AActor 0x14bbe1040 |
| siblings | ALiveTLSSwing 0x14ca85330, ALiveTLSSwingforMissile 0x14ca868e8, ALiveTLSSwingforPlane 0x14ca86020, ALiveMissile 0x14c84e670 |

Field offsets (reflection, and the constructor for the unreflected ones):
- ALiveWeaponBase: RootComponent +0x1a0, bInUse +0x290 (set only by the weapon pool), WeaponID +0x2b1 (u8),
  OwningGameObject +0x368, OwnerWeapon +0x370, StaticMesh +0x380, WeaponMovement +0x3a0, TargetToHome +0x3f0,
  bCollided +0x418, LifeTime +0x420, LoadTime +0x424, bDestroyed +0x65a, lifespan timer +0x6d8.
- ALiveAttachedWeapon: bIsBaseAttached +0x738 (byte), AttachedComponent +0x740, AttachedSocketName +0x748.
- ALiveLaserInterceptor: RayDistance +0x750, RayRadius +0x754, InterceptAngle +0x758, SearchInterval +0x75c,
  InterceptTime +0x760, bInertia +0x764, InertiaTime +0x768, SwingRateCurve +0x770, MainLaser +0x778, EndLaser +0x780,
  EndLaserTimer +0x788, EndLaserMaxTime +0x78c, LaserScale +0x790, **state +0x794** (int, unreflected: 0 search,
  1 swing), MissileToIntercept +0x798, **timer +0x7a0** (unreflected), **swing start point +0x7a8/+0x7b0/+0x7b8**
  (FVector, doubles, unreflected).

Constructor defaults: InterceptAngle 180, SearchInterval 0.5, InterceptTime 1.0, InertiaTime 1.0; **RayDistance 0,
RayRadius 0, LifeTime 0, bIsBaseAttached false, WeaponID 0 (WID_NONE; WID_AI_laser_interceptor is 158)**, curve null.
MainLaser and EndLaser are CreateDefaultSubobject<UParticleSystemComponent> ("MainLaser", "EndLaser"), both
SetupAttachment(RootComponent), so they always exist. bCanEverTick comes from ALiveWeaponBase's constructor, and
bStartWithTickEnabled from AActor's (AActor::InitializeDefaults 0x143fb4930).

Slots it overrides (vs ALiveAttachedWeapon):
| slot (offset) | function | what |
|---|---|---|
| 0 | 0x146e8e2b0 | destructor |
| 228 (0x720) | **0x147ef5ce0** | WeaponTick(dt): the whole interceptor (9.2) |
| 229 (0x728) | 0x147ef3f60 | `jmp` ALiveWeaponBase's 0x147f5e9b0 (WeaponBeginPlay): no change |
| 230 (0x730) | **0x147ef61e0** | Activate(owner): base 0x147f5ead0, then the AC7 blueprint's OnCreateWeaponEnd work, now native: EndLaser.SetActive(false), MainLaser.SetActive(true, reset) + SetVisibility(true), timer = 0, EndLaserTimer = EndLaserMaxTime = 0.2, LaserScale = 1, ProcessEvent(OnCreateWeaponEnd) |
| 233 (0x748) | 0x147ef62d0 | OnLifeTimeExpired: DestroyWeapon (slot 237) or Deactivate (slot 247), ProcessEvent(OnLifeTimeExpired), EndLaser.SetActive(true, reset) + SetVisibility(true) |
| 235 (0x758) | 0x1417558e0 | returns 4 (the TLS family's value; the base returns 1) |

How the virtuals are reached (ALiveWeaponBase's AActor overrides) [D]:
- Tick, slot 159 = 0x147396280: AActor::Tick (0x143fb6ff0), then `jmp [vt+0x720]` (slot 228).
- BeginPlay, slot 114 = 0x147f5e990: AActor::BeginPlay, then slot 229.
- SetOwner, slot 156 = 0x147f5fd70: AActor::SetOwner, then **OwningGameObject = the owner if it IsA
  ALiveGameObject** (else the owner weapon's OwningGameObject). The UFUNCTION AActor.SetOwner and SpawnActor's Owner
  both land here.
- SetLifeSpan, slot 127 = 0x147f5fe70 (its own timer at +0x6d8). LifeSpanExpired, slot 149 = 0x147f601b0: it calls
  slot 233 instead of Destroy.

The other ALiveWeaponBase virtuals named here:
| slot | function | what |
|---|---|---|
| 231 | 0x147f5f000 | post-spawn params |
| 237 | 0x147f63230 | DestroyWeapon |
| 239 | 0x147f61b40 | Collide(hitActor, &loc, &rot, ELivePhysicalMaterialType): a no-op once bCollided is set |
| 247 | 0x147f5f640 | Deactivate / back to the pool: SetLifeSpan(0), hide, SetActorTickEnabled(false), pool release when bInUse. ALiveAttachedWeapon's 0x147eee7c0 detaches first |
| 266 | 0x147f602e0 | Launch: SetLifeSpan(LifeTime), OnInitialized |

### 9.2 The per-tick logic [D]
WeaponTick 0x147ef5ce0:
1. It runs ALiveAttachedWeapon's tick (0x147eee640: the base tick 0x147f5f8b0). When bIsBaseAttached and bInUse are set
   and the owner is dead, that tick calls LifeSpanExpired.
2. It sets the beam parameters, with **no null check on either component**:
   - MainLaser: SetFloatParameter("BeamLifeTime", LifeTime + EndLaserMaxTime) and ("LightLifeTime", LifeTime - 0.5);
   - **EndLaser** (not MainLaser, as AC7's blueprint did): SetVectorParameter("BeamLength", (RayDistance, LaserScale,
     LaserScale)).
3. Once bDestroyed or bCollided is set: EndLaserTimer -= dt, and LaserScale = clamp(EndLaserTimer / EndLaserMaxTime, 0, 1).
4. timer += dt, then state 0 -> Search, state 1 -> Swing.

**Search** 0x147ef64a0(this). It does nothing until timer >= SearchInterval, then sets timer = 0.
- The list: every registered missile, from WeaponManager = 0x147208fc0(world)+0x1a8, via 0x14728b230(mgr, &TArray).
  TLSSwingforMissile and the CIWS AI module use the same list.
- Each missile m must pass, in this order:
  - m != null and m->IsActorTickEnabled() (slot 145);
  - not bDestroyed and not bCollided;
  - **IsEnemy(m.OwningGameObject, this.OwningGameObject)** (0x147d0ba00 -> ALiveGameObject slot 283 = 0x147d0ba90:
    team byte +0x3b2, the game state's alliance table, special cases for players);
  - |m - this root| <= RayDistance;
  - **the angle between the OWNER's root forward** (the carrier's nose, 0x144270df0) and the direction to m <=
    InterceptAngle (acos of the clamped dot, x 57.2958).
- **The first missile that passes is taken, in list order, not the nearest.** The "best distance" local is never
  updated. When online it sends net message 0x63 (0x14783c8b0, only if 0x14783c830 says online), then calls
  **BeginIntercept** 0x147ef6350(this, m, dist): state = 1, start = this location + this root's forward x dist,
  MissileToIntercept = m, timer = 0.

**Swing** (state 1, in the tick). m = MissileToIntercept, read with **no null or IsValid check**.
- If m is bDestroyed or bCollided, state = 0.
- Otherwise alpha = SwingRateCurve ? FloatCurve.Eval(timer, 0) (0x144361d30, **timer in seconds, not
  timer / InterceptTime**) : timer / InterceptTime. **A null curve is checked and safe: the swing is then linear.**
  alpha = min(alpha, 1).
- P = start + (m's location - start) x alpha. The weapon's root is turned onto P: MoveComponent(zero delta,
  (P - location).Rotation(), bSweep) (0x1442c11a0, 0x1417cce00).
- When timer > InterceptTime: state = 0, **Intercepted(m) 0x147f5f500**, timer = 0.

There's **no ray, sweep or overlap test**. RayRadius, bInertia and InertiaTime are never read by the class's code (only
the constructor writes them). RayDistance is only the search range and the beam particle's length. Once a swing starts,
the kill is certain if the missile is still alive after InterceptTime: no chance roll, no range re-check, no
line-of-sight test. That's one missile per InterceptTime + up to SearchInterval (about 1-1.5 s), from any direction
the cone allows.

What it does NOT do:
- **No WeaponIntercept trigger / OnObjectInterceptWeapon.** The intercept event's constructor (0x147415660) is called
  only by TLSSwingforMissile, and its dispatch (0x147f1c5c0) only by the CIWS, the TLS and two other interceptors
  (0x147f01896, 0x147f03c0c). Survival's SV_ZfaTLSHit count will not see its kills.
- No sound call at all.

The online half: message 0x63's receiver is 0x147845b94. At 0x147846206 it checks IsA LiveLaserInterceptor, looks the
missile up by net id (0x147838d30), and calls BeginIntercept, passing **null** if the missile isn't found (online only).

### 9.3 The clean missile kill (for a native SV_ call) [D]
`void ALiveWeaponBase::Intercepted(ALiveWeaponBase* w)` = **0x147f5f500**, MS x64: rcx = the missile (any
ALiveWeaponBase), no other argument, no return value. kSigWeaponIntercepted, unique, no wildcards:
`48 89 5C 24 08 57 48 81 EC C0 00 00 00 48 8B 81 A0 01 00 00 48 8B D9 48 85 C0` (`build/re/laser/sigs.txt`).

What it does:
1. loc = w's root location.
2. A replication message (0x147847ed0(world) -> 0x14786bfa0; it sends only when online).
3. w->Collide(null, &loc, &FRotator::ZeroRotator, ELivePhysicalMaterialType::Intercepted = 102) (slot 239). That
   function returns at once if bCollided is already set, so a second call is harmless. Otherwise it sets bCollided,
   spawns the "Intercepted" collision effect (slot 240) and ends in DestroyWeapon (slot 237), which hands the missile
   back to its pool.
4. A transform record (slot 278, 0x147f653f0).

It is the same function every interceptor uses:
- ALiveLaserInterceptor (0x147ef6194);
- TLSSwingforMissile (0x147efde91);
- the CIWS ALiveAttachedInterceptorWeapon (0x147eede41);
- 7 other call sites.

TLSSwingforMissile's path, for comparison:
- Its search 0x147efd3d0 (its state is at +0x9b8) checks a lot more than the LI's: it null-checks **both owners**,
  skips its IgnoneMissiles set (+0x968), compares the distance squared with InterceptDistanceSquared (+0x9fc) and the
  angle with InterceptAngle (+0x9f8), and rolls InterceptPercentage (+0xa00, rand() & 0x7fff / 32768). On a pick it
  increments missile+0xb70 and calls SetState(1, m) 0x147efc500.
- Its state-1 handler 0x147efd8f0 checks **IsValid(MissileToIntercept +0x960)** (null and RF_MirroredGarbage, bit 30
  of ObjectFlags at +0x8), then that the missile is still alive, then the distance from its beam end (+0x9c0) to the
  missile.
- Then it **raises WeaponIntercept** before the kill:
  - the event object: constructor 0x147415660, vtable 0x14cb632f8, trigger type 0x65;
  - its fields: +0x18 own WeaponID (u8), +0x20 own OwningGameObject (only if IsA ALiveAIGameObject),
    +0x28 the missile's WeaponID, +0x30 the missile's OwningGameObject;
  - the dispatch: 0x147f1c5c0(0x1470bdef0(world), &event, 0);
  - then Intercepted(m), then the event's destructor 0x14710e6b0.
- The CIWS (0x147eedd49) runs the same sequence. Signatures for the event's constructor and destructor are in sigs.txt.
  0x147f1c5c0 has no unique signature: take it from the CIWS call site.

Guards for an SV_ call, all on the game thread:
- w != null, and IsA ALiveWeaponBase (ALiveMissile);
- `(*(u32*)(w+8) & 0x40000000) == 0`;
- bInUse (+0x290) == 1, bCollided (+0x418) == 0 and bDestroyed (+0x65a) == 0.
Then call it, and raise the event first if Survival should count the kill through a trigger.

### 9.4 What it needs, and what crashes it
A missing value doesn't crash, it disables:
- RayDistance 0 means it never finds a missile;
- LifeTime 0 means SetLifeSpan(0): an FCS-fired one never expires;
- bIsBaseAttached false means the FCS attach (0x147eee800) is skipped: it stays where it was spawned while the plane
  flies on (the search measures from **its own** root). The owner-death auto-expiry is also off then;
- WeaponID 0 only labels it.

Null or dangling pointers crash it [D unless tagged]:
1. **OwningGameObject null.** In IsEnemy the interceptor's owner is dereferenced (`mov rax,[rdi]`), so the game
   crashes on the first search with any live missile in the world. Then `owner->RootComponent` is dereferenced too.
   Set it with the Owner at spawn or with SetOwner (9.1).
2. **A missile with a null OwningGameObject.** GetWorld(null) inside 0x147d0ba00 crashes. TLSSwingforMissile skips such
   missiles, the LI doesn't. Whether live missiles without an owner exist in Survival is [T].
3. **MissileToIntercept null or freed while state = 1.** Read every tick with no check. A missile actor destroyed
   mid-swing (GC nulls the UPROPERTY, or the pointer dangles) crashes it. Missiles are pooled, so this is mostly a
   level-teardown risk [I]. **Never write nil into MissileToIntercept from Lua during a swing.** A valid missile written
   during a swing does retarget it: it kills whatever +0x798 holds when the swing ends, with **no team check in state
   1**. Writing it while state = 0 does nothing (the search overwrites it).
4. **The pool reuse bug.** Neither Activate (slot 230) nor OnLifeTimeExpired resets state (+0x794) or MissileToIntercept.
   An LI that expires mid-swing goes back to the pool still in state 1 with the old pointer. When the FCS reuses it, its
   first tick resumes that swing and kills the old pointer's missile, which may by then be a recycled missile of either
   team, or a freed one (a crash). This only happens through the FCS pool, route (a).
5. **The carrier destroyed before the LI** (a Lua-spawned LI). The pool's owner-death expiry needs bInUse (+0x290),
   which only the pool sets, so the LI outlives its plane. Its OwningGameObject is then nulled by GC or dangles,
   which is case 1.

These don't need guarding [D]:
- WeaponManager (0x147208fc0(world)) is non-null in a mission world;
- MainLaser and EndLaser with no Cascade template: SetFloatParameter / SetVectorParameter / SetActive on an empty
  UParticleSystemComponent are safe [I], and the components always exist;
- a null RootComponent is handled (the zero vector, MoveComponent skipped).

**Route (a): an FCS arm whose ProjectileCommon WeaponClass is /Script/Live.LiveLaserInterceptor.**
- Mechanically it works:
  - ProjectileCommon::Initialize (slot 87, 0x147bee3a0) only checks IsChildOf(ALiveWeaponBase) and caches the CDO
    (+0x60);
  - the class's script import exists (hash 0x4924eb83c12a0e05, CDO 0x673669ad763cd056, section 5);
  - the arm's other imports (the TLS blueprint's subobject templates) would be dropped [I].
- **With the native defaults it does nothing useful:** no kills, an LI leaked on every shot, and none attached.
- It needs the values either from **a blueprint subclass** (cooked VERSIONED in ue/Live, hard rule 42, parent
  /Script/Live.LiveLaserInterceptor: RayDistance, InterceptAngle, InterceptTime, SearchInterval, LifeTime 6,
  bIsBaseAttached true, WeaponID 158; no graph needed, the C++ does the AC7 blueprint's work), or from a run-time edit
  of `Default__LiveLaserInterceptor` before the level loads. No stock content uses the class: no package by name, and
  its StaticClass is referenced only by its registration and the net handler.
- It also carries bug 4.

**Route (b): spawned from UE4SS Lua.** GameplayStatics.BeginDeferredActorSpawnFromClass(class, transform,
AlwaysSpawn, **Owner = the ZFA-44 plane**), then the instance's values, then FinishSpawningActor.
- The values to set on the instance: RayDistance, InterceptAngle, SearchInterval, InterceptTime, WeaponID 158,
  bIsBaseAttached true, LifeTime left 0.
- Then attach it: K2_AttachToComponent(the plane's body, "SOC_Gun_01", SnapToTarget), or the native
  AttachTo 0x147eee800(w, comp, socket), which needs bIsBaseAttached.
- It ticks from BeginPlay [I: bStartWithTickEnabled default, nothing in WeaponBeginPlay disables it], and SpawnActor's
  Owner sets OwningGameObject [I: through PostSpawnInitialize's SetOwner]. Call AActor.SetOwner(plane) after
  FinishSpawningActor as well, and read OwningGameObject back before trusting it. It already searches and kills with no
  Activate call.
- Activate (vt+0x730, rdx = owner) is optional: it only turns MainLaser on (there's no template) and fires
  OnCreateWeaponEnd.
- No pool, so no bug 4. But Lua owns its lifetime: destroy it (K2_DestroyActor) before or with its plane, on a plane
  recycle, at the run's end and before teardown (case 5). It's a permanent shield unless Lua rests it (e.g. RayDistance 0).
- **Route (b) is the viable and safer one.** It needs no package, no CDO edit and no pool, and every value is on
  Survival's own instance.

### 9.5 How AC8's FCS spawns an attached weapon [D]
The whole chain:
1. ProjectileWeapon::Fire (slot 92) 0x147bed3a0:
   - the launcher component's socket transform (component vfunc 0x4d0);
   - &WeaponClass (slot 99 = 0x1416f81e0, `lea rax,[rcx+0x50]`);
   - the owner, only if it IsA ALiveAIGameObject;
   - the spawn params 0x147bf4600, with +0x48 = the launcher component and +0x50 = the socket.
2. SpawnWeapon 0x147bf47a0 -> WeaponManager::Spawn 0x147393cf0 -> the local spawn 0x147394b10. It reuses a pooled
   weapon of that class that isn't in use, or calls **0x14464d110** (UWorld::SpawnActor [I]: world, class, &loc,
   &rot, params; not deferred, so BeginPlay runs inside).
3. weapon+0x2b0 = a flag; **Activate(owner)** (slot 230); slot 231 (the post-spawn params); bInUse = 1.
4. 0x147bf5290:
   - an ALiveAttachedWeapon gets **AttachTo(launcher component, socket)** 0x147eee800. This only works with
     bIsBaseAttached: it sets AttachedComponent / AttachedSocketName and calls root vfunc 0x4b8 with the snap rules;
   - then 0x147f60360, then **Launch** (slot 266): SetLifeSpan(LifeTime).
5. The lifespan ends -> slot 149 -> OnLifeTimeExpired (slot 233) -> Deactivate -> back to the pool.

**The AIControlCIWS target never reaches the weapon.** The module (vtable 0x14c6e7608, functions 0x147be2260-0x147be4400)
reads the same missile list (0x14728b230 at 0x147be2317 / 0x147be2514) only to decide when to fire. It never writes a
weapon's MissileToIntercept: each weapon searches on its own.

So the arm package can point its weapon import at the native class, but only with the values from 9.4 route (a). For
the ZFA-44s, route (b) or the existing TLS arm (section 8) is simpler.

### 9.6 Curve, effects, sound [D unless tagged]
- **AC8 does not ship CUR_LaserInterceptorSwingRate, nor AC7's Cascade FX_UAV_TLS_Muzzleflash01 / 02.**
  `build/scan/pkgs.txt` (all 88k stock packages) has no LaserInterceptor, SwingRate or FX_UAV package.
- A null SwingRateCurve is safe: the swing is then linear (9.2). No stock 0-1 curve was checked as a stand-in.
  A smoothstep needs Survival's own UCurveFloat asset [I]: Lua can't add keys to one.
- What AC8 does have of the TLS:
  - Niagara beams `/Game/VFX/Vehicles/Weapon/TLS/NS_UAVTLS_Muzzleflash01`, `NS_UAVTLS_EndLaser001` and
    `NS_NPC_TLS_Muzleflash01` (User.BeamLength), plus NS_TLS_* for the player and wingmen;
  - leftover Cascade materials and meshes in `/Game/VFX/Vehicles/Weapon/TLS/Cascade/` (m_TLS_01_Beam,
    MI_UAVTLSBeamWire, SM_UAVTLSBullet_IE01, ...), but no Cascade ParticleSystem for them;
  - the sounds `SPWP_OTH_TLS_HIT`, `_PASS`, `_PASS_Stop` (AC8's own Wwise events).
- MainLaser / EndLaser are Cascade components, so they can't take a Niagara template.
- For a beam: attach a Niagara component (one of AC8's TLS systems) to the LI's root. **The root itself swings onto
  the missile**, so a beam along +X follows the swing with no extra code [I]. Set User.BeamLength from Lua.
- AC7's own Cascade look needs AC7 assets: that's a **new AC7-asset exception only the user can grant** (AGENTS.md
  records VALKA's only).
- The class plays no sound (9.2).

### 9.7 Recommended route and in-game test
1. **Native support in runtime/survival_rt_lua.c.** Find 0x147f5f500 (kSigWeaponIntercepted) and BeginIntercept
   0x147ef6350 (kSigLaserBeginIntercept). Read the LI vtable from its CDO (`*(void**)CDO`). Add:
   - `SV_Intercept(missile)`: 9.3's guards, then Intercepted. It's a clean, guaranteed kill, useful to the existing TLS
     path too;
   - **vtable guards on the LI's own vtable**, which only Survival's instances use, chaining as main.dll does for the
     menu:
     - slot 228 at 0x14c78d950: skip the tick if OwningGameObject is null or garbage. In state 1, if
       MissileToIntercept is null, garbage or bCollided, set state 0 and skip the original;
     - optionally, run the search in the detour with the TLS's null checks: give the instance SearchInterval 1e9 so
       the native search never runs, then call BeginIntercept itself. That also closes crash 2;
     - slot 230 at 0x14c78d960: zero +0x794 / +0x798 / +0x7a0 before the original. That closes bug 4 if route (a) is
       ever used;
     - count kills in the detour (a state 1 -> 0 change with the kill call), as WeaponIntercept doesn't fire.
2. **Lua** (sv_escort_laser.lua, CFG.allies.carrier.zfa): route (b), as in 9.4, per ZFA-44 after its dress.
   - Values: RayDistance 124000 (AC7's 1.24 km in AC8's cm) or 300000 (the TLS's 3 km), InterceptAngle 180,
     InterceptTime 1.0, SearchInterval 0.5, WeaponID 158, bIsBaseAttached true.
   - Remove it before the plane: on its death, a recycle, the run's end, and before teardown.
   - The beam: a Niagara TLS beam attached to its root, with the TLS_HIT sound on each kill.
   - A dev test key first (TEST ONLY).
3. Test [T]:
   - it spawns, attaches and ticks with no crash;
   - enemy missiles near a ZFA-44 die 1-1.5 s after it picks them;
   - never the player's or allies' missiles;
   - no crash when a ZFA-44 is shot down or recycled, at the run's end, or at Quit Mission;
   - the log counts kills;
   - in co-op, each game runs its own (the online message path stays off).

Risks:
- crashes 1-3 without the guards;
- balance: a sure kill of any enemy missile in range, about one a second per ZFA-44;
- no WeaponIntercept event;
- no visible beam or sound unless Survival adds them;
- AC7's exact look needs the user's asset exception.

## 10. The port built (2026-11-07, Lua 0.74.17, runtime 0.32.26; not yet run in game)
The user: "I want the entire weapon from ACE7 to be ported over" (AGENTS.md's exception). Route (b) of 9.4, on AC7's own
weapon rebuilt by tools/laser7 (BP_SV_LaserInterceptor on ALiveLaserInterceptor, in SurvivalMode_Laser7_P, staged with
ZFA=1):
- The assets (tools/laser7/README.md): AC7's swing curve, its two Cascade effects (9 emitters, AC7's numbers), the beam's
  3 meshes, 4 rebuilt materials (their SM6 shaders inside their packages: the template project's shared shader archive
  never ships) and its texture; the blueprint with AC7's values in AC8's units (RayDistance 124000, LifeTime 6,
  InterceptTime 1, InterceptAngle 180, SearchInterval 0.5, the curve), MainLaser / EndLaser on AC7's effects at AC7's
  place, scaled x10.
- The rows (tools/survival_events_escort.py ZFA_LI_*, build_survival.py): SV_Zfa_AllyLI / SV_Zfa_DroneLI, the ZFA-44
  hosts without the gun's slot (NpcFCSId1 gone): no gun, and no arm of AC8's swing laser firing beside AC7's. Lua
  (sv_escort_li.lua ZLI.rows) adds them under the hosts' names at the main menu when AC7's laser is on (CFG ...zfa.li,
  the runtime's SV_LaserBegin, the class loaded); else AC8's laser as before (section 8).
- The runtime (runtime/laser.c, sigs.h kSigLaserTick / kSigLaserBeginIntercept / kSigWeaponIntercepted):
  - the class's WeaponTick hooked inline (16-byte prologue): a laser whose OwningGameObject is NULL or not live isn't
    ticked (crashes 1 and 5); in a swing, a missile that's NULL, freed, back in its pool, collided, without a shooter,
    not the one handed over or fired again by another shooter (+0x368 changed since the hand-over) gives the swing up
    (state 0, timer 0) before the game reads it (crash 3, and a recycled missile of our own side); a swing's end with
    its missile collided counts a kill;
  - SV_LaserBegin(li, missile): the class's BeginIntercept(li, m, |m - li| as float) after the checks (a laser by its
    vtable's slot 228; its owner live; the missile in flight with a shooter); the hand-over remembered (laser, missile,
    shooter);
  - SV_LaserState(li [, 0]): 0 / 1 / -1; 0 gives a swing up (MissileToIntercept itself never cleared, 9.4);
  - SV_LaserKills(); SV_Intercept(missile): ALiveWeaponBase::Intercepted after 9.3's checks (and its Collide slot in the
    game's code), the backstop.
  The missile owner crash (9.4 case 2) is the existing guard on 0x147d0ba00 (runtime 0.32.25, flight_guards.c); the
  native search never runs anyway (SearchInterval 1e9 on each instance).
- Lua (Scripts/sv_escort_li.lua, CFG.allies.carrier.zfa li_*), every game, the ZFA-44s up (not parked):
  - one laser a plane: BeginDeferredActorSpawnFromClass(class, at the plane, AlwaysSpawn, owner the plane), its values on
    the instance (SearchInterval 1e9, InterceptTime li_intercept_s, InterceptAngle, RayDistance li_range_m x 100,
    LifeTime li_volley_s, bIsBaseAttached), MainLaser / EndLaser not auto-activated, FinishSpawningActor, SetOwner,
    K2_AttachToComponent(PlaneBodyMesh, SOC_Gun_01, snap, snap, keep world scale); OwningGameObject read back (logged);
  - AC7's fire control: an enemy missile within li_activation_m 1200 of the plane starts a volley of li_volley_s 6
    (the root turned back to the gun's line, EndLaser off, MainLaser's BeamLength (li_range_m x 10, 1, 1) in AC7's
    units, MainLaser shown and SetActive(true, reset): AC7's charge-up, flash and beam); li_rest_s 8 after its end;
  - each li_search_s 0.5 of a volley, the laser in state 0 takes the nearest enemy missile (sv_escort_laser.lua's enemy
    test) within li_range_m 1240 in li_angle of the plane's nose that no other laser is on: SV_LaserBegin. The class
    swings onto it (AC7's curve over li_intercept_s 1) and kills it (the game's "Intercepted" effect); Lua plays the
    TLS hit sound and logs it; one still up li_sure_s 0.6 after its swing's end, by the same shooter: SV_Intercept;
  - the volley's end: a swing on given up (SV_LaserState(li, 0)), EndLaser shown and SetActive(true, reset) (AC7's end
    flash), BeamLength's Y / Z 0.5, then 0 and MainLaser off li_end_s 0.2 on (AC7's LaserScale thinning);
  - its plane gone: K2_DestroyActor; the run's end: every laser removed; the level going: forgotten, nothing called.
  - A missile shot down and fired again from its pool (bCollided false again) is a new one (its faction asked again).
  - Logs: `zfa li: <plane> (<unit>) carries AC7's LaserInterceptor: owner its plane, search every 1e9 s (off), at
    SOC_Gun_01`, `... fires a volley (<missile> d m off; n so far)`, `... swings onto <missile> d m off (from <shooter>)`,
    `...'s laser shot down <missile> (...)`, `<missile> still up ... SV_Intercept -> 1`, the round's summary `AC7's
    lasers: v volleys, s swings, k missiles shot down ...`; runtime `laser: ... begins its swing on ...`,
    `laser: ... given up: ...`, crumbs `laser: ... shot down ...`.
  - Test key (TEST ONLY): Ctrl+[ (OEM_FOUR) a volley now on every ZFA-44's laser, their state logged; Ctrl+DEL sends a
    carrier (ESC.testCarrier).
- Tests: escort_test (the rows, the spawn's values and attach, the volley, the hand-over, one swing at a time, the kill
  and its sound, SV_Intercept, never one out of reach or an ally's, AC8's route quiet, the end flash and thinning, the
  rest, the next volley, removal).

In game [T]: the laser spawns and attaches with no crash; its beam draws (AC7's Cascade look: red beam, charge-up
sparks, the flash, the end flash); the swing follows the missile; the missile dies about li_intercept_s after its hand-
over; never the player's or allies' missiles; no crash when a ZFA-44 is shot down, at the run's end or at Quit Mission.
Balance and reach: AC7's 1.24 km reach and 1.2 km activation are short next to AC8's missiles (the ZFA-44s escort the
player within 3 km): li_range_m / li_activation_m raise both (the beam's length follows li_range_m).

## 11. A faster swing (0.74.49, 2026-11-10; not yet run in game)
The user: "We need to up the swing speed for the laser interceptors", 0.5 s for the ZFA-44s' and round 30's fleet's
alike (one setting). `li_intercept_s` 1.0 -> 0.5 (CFG.allies.carrier.zfa, survival.ini [allies.carrier.zfa]): the
missile's kill comes at InterceptTime (section 9.2's Swing: timer > InterceptTime), so a laser takes one missile about
every 0.5-1.0 s (the swing plus up to li_search_s), twice AC7's rate.
- The catch [D, section 9.2]: the class evaluates SwingRateCurve at the timer **in seconds**, not at timer /
  InterceptTime. AC7's curve (0 -> 1 over 1 s, a smoothstep: 1c) is only 0.5 at 0.5 s, so with a 0.5 s swing the beam
  would be half way to its missile at the kill. sv_escort_li.lua `curveFit`: at the spawn, the laser's curve is kept if
  it reads 0.98 or more at InterceptTime (GetFloatValue), else cleared (SwingRateCurve = nil): the class checks a null
  curve and swings straight, alpha = timer / InterceptTime (9.2). Any li_intercept_s a player sets lands the beam on its
  missile that way.
- tools/laser7/spec.py now cooks AC7's smoothstep over 0.5 s (keys t 0 and 0.5), so after the next laser7 build
  (`sh tools/laser7/build.sh`, the user's machine) the curve fits 0.5 and is kept: the eased swing back. Until then the
  installed container's 1 s curve is cleared at each spawn (the straight swing).
- Log: the `zfa li: ... carries AC7's LaserInterceptor: ...` line ends `a swing 0.50 s, its swing curve kept (1.00 at
  0.50 s)` / `cleared (0.50 at 0.50 s): a straight swing` / `NOT cleared (...): the beam is short of its missile at the
  kill` (UE4SS refused the nil write: the kill still comes at 0.5 s).
- In game [T]: the beam snaps onto each missile in about half a second and stays on it to the kill; more missiles shot
  down per volley (the `zfa li:` kill counts against 0.74.48's).
