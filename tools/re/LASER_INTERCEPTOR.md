# AC7's LaserInterceptor: research for a later port (2026-11-06)

User (2026-11-06): "I want you to take a look at the LaserInterceptor Weapon in Ace Combat 7, I want to use that later."
Research only: nothing built, nothing installed, no game run.
Tags: **[D]** confirmed in data, **[I]** inferred, **[T]** needs an in-game test.

Project rule first: Survival ships only AC8's own files. The one AC7 exception is VALKA's (X-02S, Mihaly's railgun
effects and sounds, see VALKA.md). Using AC7's beam effects or sounds for this weapon would be a **second exception**, and
only the user can grant it. AC8 has its own missile-killing laser (section 5), and that route needs no AC7 assets.

Scratch outputs (git-ignored, on the build machine): `E:\ACE8 Survival Mode\build\ac7\laser\`: `dec\` (decrypted AC7
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
AC7's exe (F:\Steam\steamapps\common\ACE COMBAT 7\Ace7Game.exe) has readable reflection data. Its code is
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
