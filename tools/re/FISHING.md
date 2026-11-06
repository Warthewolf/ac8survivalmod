# GONE FISHIN', the day-night arc and THE FESTIVAL: research (2026-11-06)

The design is FISHING_ROUND_PLAN.md (section 0 has the user's decisions). This file holds what research found for it.
Nothing here is built or tested in game. Tags: [D] confirmed in data, [I] inferred, [T] needs an in-game test.
Scratch output (git-ignored): `build/research/festival/`, `build/research/comona/`, and the session scratchpad's
`sky/` and `py/` scripts (re-runnable). The map: COMONA_MAP.md. AC7's laser: LASER_INTERCEPTOR.md. The ZFA-44: ZFA44.md.

## 1. The shoals
Recommended: a Survival copy of the stock invisible turret pawn `GR000_dummy`, with a hit sphere added at spawn.
- `dummy_common` -> NpcId `GR000_dummy` -> `/Game/Blueprints/Vehicle/AI/Turret/GR000_dummy/CP/BP_GR000_dummy_CP` ->
  BP_GR000_dummy_Base -> BP_AITurret_Pawn -> ALiveAIGroundVehicleObject (the AA guns' class). No mesh: a root,
  OverlapCollision, damaged state, destroy systems; no wake, wreck or children [D]. (SPECIAL_ROUNDS.md 243-245 maps it
  to BP_AI_Dummy_Ground, a LiveAIGroundDummy with a NoCollision debug mesh: that's wrong; don't use that one.)
- Stock missions use it as a scored, killable enemy: Mission 13's `E_Obj02_02_Score0-7` (row Dummy_btr9_common ->
  GR000_dummy_MS13_btr9, the same blueprint), faction 2, not invincible, z -20, BaseScore 100, destroyed by its
  `02_LCAC_ObjectDestroy_N` records [D]. Mission 17's `A_Obj_01_dummy_container0` and Mission 28's `AObj01_Dummy_0_0`
  carry bShowHUDBox with a mark [D].
- The gap: no hit primitive. The AA gun has `DamagedCollision` (sphere 640 cm, profile EnemyPawn, CollisionEnabled 3),
  the LCAC `DamagedCollsion` (box 14 x 8 x 3 m) [D]; the dummy's DT_NPC row has empty WeaponDurabilityId /
  ExplosionDurabilityId (vessels: NPC_WPDur_000 / test_NPC_ExpDur_000) [D]. Missiles fuse by distance
  (LiveMissile.ProximityFuseRadiusSquared) and explosions damage by radius [I]; the gun sweeps against collision
  (LiveBullet.RayCastRadius) and likely misses without the sphere [I].
- Build: row `SV_Shoal` (copy of GR000_dummy with those two durability ids, GameObjectDisplayName02 "SHOAL", BaseScore
  0); model `SV_Model_Shoal`, MaxHealth ~10 (above co-op's 1 HP copy floor; one missile or one bomb), added to
  DT_NPC_Model at the main menu as VOID WATCHER's; NPC_EXTRA `('sv_shoal', 'dummy_common', 'SV_Shoal')`
  (build_survival.py ~2233), build_npc_rows (~1957), build_model_rows (~2100). Units by `port_unit(...,
  src=desc_named(stock_wd(M13 WD), 'UnitDescList', 'E_Unit02_02_Score0'), 'SV_Unit_FishA/B/C', 'SV_Obj_FishA/B/C',
  'sv_shoal', points, yaw, top_number, tgt=True)`; the scatter per spawn from SetPose (survival_rt.c ~1435); presets
  20 / 24 / 28 need units of those sizes (SV_Spawn spawns every object of a unit). No EP records needed.
- At spawn, every game: AddComponentByClass(SphereComponent) ~8 m, SetCollisionProfileName("EnemyPawn"), and/or
  SetSphereRadius on OverlapCollision [T] (AddComponentByClass: hard rule 46, sv_anomalies.lua ~1778; SetSphereRadius
  sv_anomalies.lua ~1873).
- Height z 600-800 cm: the sea's collision plane is at 3.5 m (COMONA_MAP.md), so a lower point target puts missiles
  into the water first [I].
- Fallback: Mission 13's LCAC (lcac_common, ported, unarmed, boxes / TGT / kills confirmed in game: hard rule 32) hidden
  with SetActorHiddenInGame (a hidden actor keeps its box and lock: sv_anomalies.lua ~288); its two child wave-spawner
  actors hidden too [T]; its death pillar NS_VesselsPillarLCAC001 may hide with it [T]. Switch to it if the first test
  shows the dummy can't be locked, or a hit doesn't move its health even with the sphere.
- Splash: `/Game/VFX/Environment/Common/Explosion/GroundExplosion/groundExplosionA001/NS_groundExplosionASmallSea003`
  (the system in BP_MO102_SeaExplosionS and BP_MO105_SplashS; Mission 3's esse_BomberNoHit0-3 place it at z 0) [D];
  bigger `_ASmallSea_L` for The Big One. From Lua: NiagaraFunctionLibrary SpawnSystemAtLocation as `fxAt`
  (sv_anomalies.lua ~187, local: copy it) with the asset loaded the hard-rule-9 way; each game plays its own.

## 2. Kill attribution (co-op: each player's own haul)
- Exists: host spawns through the SV_Spawn wrapper name `spawningUnit` (co-op ids for ground objects: sv_coop.lua
  ~314-330, 467-470, hostGround); joiners' copies sit at the 1 HP floor and send hits as `ht` (hostHit adds e.by,
  ~927); hostKiller (~584) picks the killer from the host's DamageHistoryMap + e.by, else the side; `dn|id||slot`
  (~687), joiners keep M.killer (~5099) [D].
- The round: keep the shoal actors as sv_amphib.lua's AMPH.actors (~19-30); at health 0 (liveAddr first)
  KILL.by({obj, addr}) -> "you" (COOP.slot or 0) / "wingmate" (p.killer) / "allies"; solo KILL.read(p) first
  (sv_ai.lua ~807 / 840). Reading health sidesteps hard rule 6.
- New: a catch message (e.g. `fh|slot|catch|kg`) and a per-player weigh-in; the `cr` relay splits pay by
  special_split, which doesn't fit per-player pay. hostKiller falls back to the host when nothing is recorded: watch
  it. Leftovers: COOP.removeNow(unit) then SV_Recycle(unit, 1).

## 3. SAL's boat
The user (2026-11-06): "SAL boat can just be an ally, dont worry about it too much." Build it as an ordinary allied
boat; the friendly-fire switch, the Faction 2 fallback and a co-op hit message below are not to be pursued. A kg
penalty only where this game's own copy shows a hit.
- Row `VE027_boat2_01` (model VE027_boat2, blueprint `/Game/Blueprints/Vehicle/AI/Vessels/VE028_boat2/CP/VE028_boat2_CP`,
  mesh SM_VEC_Ship003P01_I10): 13.6 x 5.6 x 8.8 m, wooden hatches, blue nets aft, a red hull band with lifebuoys, a
  white wheelhouse; no children, no fire control, no AI module, MaxHealth 20, BaseScore 0; parent BP_AIShip_Pawn (as
  the LCACs); no stock mission uses boat1-5; the same mesh set is moored in Comona's marinas [D]. Runner-up
  VE027_boat3_01 (33 m workboat), last resort the LCAC.
- Allied: `port_unit` on Mission 28's Wasp desc (SP_WASP_SOURCE, AUnit01_Sea_0: Faction 1, no children, box, callsign,
  attack-target exception) [D]; then clear bIsInvincible, set bIsInvincibleFromAI / bIsInvincibleFromWingman; callsign
  as VOID WATCHER's (GameObjectDisplayNameID02 'SV_SalBoat').
- Afloat: MinHealth 1.0 on its mission row (stock allied ships: M003 edrne_Ally, M024 wasp_Ally / free_Ally) [D]; that
  SV_Spawn applies it [I], so also the MinHealth FIELD from Lua (never SetMinHealth: whole points only) and HealthInternal
  topped up each tick (both work on co-op copies [D: 0.73.78]).
- Main risk: players' weapons on an allied unit. LiveGameObject has bCanBeDamagedByAlly and EnableFriendlyFireDamage(bool)
  [I: class dump]; no stock asset sets them. Lock-on on an ally: expect none [I]. Fallback: Faction 2 with
  bIsNotLockonTarget, bIsNotFCSTargets, bIsAttackTargetsException (takes damage for sure; its box red).
- Attribution: on each game, health lost on that game's own copy is that game's own player's hit (other players' real
  planes are role 2 and the game refuses damage from a role-2 player: COOP2MP.md; stand-ins fly damage-0 rows) [D].
  The host watches its boat; a joiner finds its copy in M.cunits[unit]. Allied copies send no hits: a new reliable
  message to the host; the unit goes into allyUnit()'s set. Health loss first, DamageHistoryMap only as a log check.
- Wake: TrailNiagara sits 116 m off the bow in the blueprint: may need hiding [T]. Home port for the story: Comona's
  largest marina at (20.13, -5.26) km, 4.1 km east of the runway (64 yachts) (COMONA_MAP.md).

## 4. The grounds (UE cm; north -Y, east +X; from the runway centre (1610476, -436142))
| Ground | X | Y | Z | km | Bearing | Clear to land |
|---|---|---|---|---|---|---|
| North Shoal | 1803753 | -1160858 | 350 | 7.5 | 015 | 4.9 km |
| Lighthouse Bank | 1866154 | 268355 | 350 | 7.5 | 160 | 5.6 km |
| The Deep Hole | 929908 | -753378 | 350 | 7.5 | 295 | 4.7 km |
| SAL's boat | 1687842 | -1191916 | 300 | 7.6 | 006 | 5.7 km |
Checked twice [D]: against every terrain tile's collision mesh and the sea tiles (the boat agent), and against
COMONA_MAP's 20 m land mask (the clear-to-land column). Hops 14.3 / 13.9 / 9.6 km. East (050-080) and south-west
(230-260) are land or shallows. The sea near the airport is ~20 m deep everywhere; the reefs are painted only.

## 5. The day-night arc
- The level's clock (ALiveWorldSettings ClockHour/Min/Sec, 10:10 written by build_survival.py) doesn't move the sun:
  Mission 4's sun is fixed in CSP_ms04_20251218b (elevation 15, azimuth 142, bUseUnrealSunData off) [D]; probably a
  display only [I].
- The sun = FSkyParams.SunElevationAngleInDegrees / SunAzimuthAngleInDegrees (UCloudlySkyParams.Data) +
  SunIntensity.Factor / .RGB + the SunLight directional light (intensity = Factor; rotation pitch = -elevation, yaw =
  azimuth + 90) [D: all 30 lighting levels]; the actor's TargetSunLightLastSet points at the light [I: Cloudly drives it].
- Run-time API (build/liveproject Source/Cloudly/Public/CloudlyActor.h) [D: header]: ACloudlyActor statics
  SetCustomSunPosition(ctx, elevation, azimuth, ForceUseCustomSun), SetCustomMoonPosition, SetCustomMoonPhase,
  SetUseCustomSun / GetUseCustomSun, ForceUpdateShadows(frames), ForceUpdateAO, RecaptureSkyLight,
  GetCachedCloudlyActor; via `/Script/Cloudly.Default__CloudlyActor` [T]. Stock time-lapse fallback: Mission 25_2's
  CloudlySequencer_ms25_TimeLaps.
- VALKA's red sky half-landed: Mission 4's lighting has the Cloudly SkyLight and HeightFog off (bVisible false,
  bUseSkyLight / bUseHeightFog off) [D]; her red came from the sun colour and sky params. The real ambient light is
  BP_SkyLightController_C_1.MainSkyLight (blends Mission 4's cubemaps by altitude: turn down at night). Exposure:
  PostProcessVolume_1 / _3 AutoExposureMin / Max / Bias (13 / 14 / 0, overrides set). City and effects glow: material
  parameter collections MPC_Env_Control Ctrl_Scene_EmissiveScale, MPC_VFX_Control VFXEmissiveEV /
  VFXCloudlySkyAmbientLight (they outlive the level: restore before it goes).
- Stars: FSkyParams.StarsParams (StarsIntensity, log-like; StarsBackgroundIntensity, StarsRadius, elevation mask,
  EnableStars). "Maximum" = the stock maximum, Mission 22 (Comona dawn): intensity 7.0, background 22.0, radius 2.5,
  screen fraction 0.73, rotation (2.578, 0, 0), elevation mask start 0.263 [D]. Moon: EnableMoon, elevation / azimuth,
  MoonPhase 0-1, MoonPhaseAngle, MoonDiskAngleInDegrees, MoonDiskBrightness.
- East is +X: Cloudly azimuth is a compass bearing (90 = UE yaw 0 = +X); 27 of 29 missions agree; both Comona missions
  (05:30 sun at 121, 15:00 at -93); PL_Mission022's NORTH / EAST labels (COMONA_MAP.md) [D]. Sunrise ~105, sunset ~255.

| Mission | Clock | Sun el / az | Factor | Stars int / bg | Exposure min / max / bias | Emissive / VFX EV |
|---|---|---|---|---|---|---|
| 4 (Survival's) | 10:10 | 15 / 142 | 120000 | default | 13 / 14 / 0 | 1 / 11 |
| 19 Comona | 15:00 | 26.2 / -93 | 120000 | - | 12 / 14 / 0 | 1 / 10.5 |
| 22 Comona dawn | 05:30 | -3.7 / 121 | 120000 | 7 / 22 | 4 / 14 / -2 | 10000 / 5 |
| 15 dawn | 05:30 | 3.4 / 85 | 120000 | - | 9.5 / 10 / -2.2 | - |
| 30 evening | 17:00 | 2.0 / -102 | 120000 | - | 10.5 / 14 / -0.6 | - |
| 9 night | 23:00 | 24 / -122 (the moon) | 0.234 bluish | 2.3 / 0.55 | 0.5 / 9 / +0.5 | 10000 / -2 |
Stock night swaps the sun for the moon: the light at the moon's spot, ~0.23 lux, sun disc 0.57 deg, moon on.

Schedule (values at each round's start; the user's sunrise over 4 rounds, a setting):
| Round | Sun el / az | Factor | Exposure | Other |
|---|---|---|---|---|
| <= F | 15 / 142 | 120000 | 13 / 14 / 0 | |
| F+1 .. F+5 | 14 / 160, 12 / 180, 10 / -160, 7 / -140, 4 / -120 | 120000 | to 11 / 14 / -0.5 | stars at maximum from F+1 |
| F+6 sunset | 1 sinking to -3 / -105 | 120000 | 9.5 / 14 / -1 | sky light x0.5 |
| F+7 night | light at the moon 35 / -130 | 0.5, RGB 0.89 / 0.96 / 1 | 0.5 / 9 / +0.5 | moon on, sun disc 0.57, sky light x0.1 blue, city glow 10000, VFX EV -2 |
| F+8 .. F+11 | -4 / 105 rising to 52.9 / 180 by the end of F+11 | 120000 | 4 / 14 / -2 to 13 / 14 / 0 | |
| after | 52.9 / 180 (the highest stock in-flight sun) | 120000 | 13 / 14 / 0 | held |
Drift within a round toward the next round's values, finished in the break (~20 s), brightness in log space; the
sun<->moon swaps only at the darkest point of a break.
- Co-op: "rnd" field 15 = F (0 = no arc); each game computes the same sky from round, state, seconds and F; a late
  joiner blends in over 5 s; joiners keep F (M.rnd) for a migration.
- Safety: never write CSP_ms04 itself (Mission 4's campaign would inherit a sunset if the level tears down mid-arc):
  the renderer copies + the custom-sun override, or a run-time copy pointed to by CloudlySkyParamsAsset [T]. Level
  objects through liveObj, a LEVEL_DROPS entry; the MPCs restored in runLeft; the airfield STORE (a minigame) may switch
  the graphics row: re-apply the MPC values each tick. Night readability: the HUD shouldn't follow exposure [I]; the
  player's plane lights by Mission 26's LivePlayerEmissiveLight. VALKA can't come during the arc (user), so her red
  sky only meets it on her test key.
- Test (TEST ONLY key, Ctrl+F6 is free on COOP2MP): 1 read only (log every value); 2 SetCustomSunPosition(-2, -105,
  true), check params / light follow; 3 renderer copies + light rotation only, read back 5 s on (kept / overwritten);
  4 the night set, read back, which MPC values the game re-applies; 5 restore, "N of N values match the originals".

## 6. THE FESTIVAL
- Mission 30's cruise missiles. Two kinds [D]:
  - SLCMs from the Grifn submarine's hatch (B_Obj_00_Ship0_Grifn_0_SlcmHatch_SLCM, row VE022_grifn_SLCM): fire control
    in BP_VE022_grifn_SLCM_Base, AllArms two LiveFireControlSystemSpawner arms (LauncherSpawner_Grifn +
    ProjectileSpawnerFromWorldData naming a world-data unit): WN_WEAPON_1 -> B_Unit_00_MainMissile0 (pool 40), _2 ->
    MainMissile1 (80) (hard rule 40). Fire record RemoteEvent_FIre_Slcm: LiveFireOneShotWeapon {WN_WEAPON_1/2, the hatch,
    target A_Obj_00_Ship0_edrne_0, NoneSelect, false, "", false}, delay 1.5 s, one in flight at a time, 45 s timer,
    radio at 20 / 10 s. Each missile an AI object (slcm_ms30 -> OP0036_slcm_01, ALiveAIGrifnMainMissile: sea-skims,
    homes at the end), MaxHealth 25, score 1180, "SLCM", bShowHUDBox, no TGT mark, tag 00_slcm_obj. A hit on the ship:
    HitInducedExplosion_Slcm_To_Edrne (trigger 0x8d on the tag); shot down: ObjectDestroy triggers (LocalPlayer,
    Wingman, SystemObject).
  - Path-flown: units B_Unit_00_MainMissile_PathMove*, one object each, slcmp_ms30 -> OP0039_slcmp_01, NLID_1000, an
    ordinary AI plane (BP_AIPlane_Pawn), health 25, boxed; launched by five records (LiveReinforcementExecution,
    LiveAIPathExecution 600 km/h, LiveAIEngagementOrder None, LiveSetLookAheadTimeSec 0, LiveFlagOperation counters);
    its hit on the Aegis: CheckDistanceEvent 50 m -> LiveDestroyUnitExecution on both.
  - A Tu-160 can't carry them: no BP_FCS_* has a spawner module [D]; DT_NPC_FCS rows only name BP_FCS_* classes and the
    Tu-160 blueprint has no child-NPC slots [I]. OP0012_t160_MS26's PlaneLASM001 fires LASM projectiles (40 damage),
    not lockable [I].
  - Survival's: the path-flown kind. slcmp_ms30 into NPC_IMPORT under a name with no digit tail (rule 17); port_unit of
    the PathMove unit (no children, rule 31) tgt=True (rule 32); 3+ missile units, one object per bomber at the
    formation's offsets; one make_path each (smooth, ControlType 1: rule 35), launch point to the runway, no handover
    (rule 54); the five records copied with foreign_template; Lua SV_Spawn(unit, lead x / y, alt - 100 m, lead yaw)
    then the path event. Impact decided on the host: within ~400 m of its aim point -> LiveDestroyUnitExecution + the
    SV_AirfieldHit effect, AF.bomb += dmg as sv_ladon.lua; only missiles shot down pay. Risks: the row's KeepMinHeight
    100 may stop the dive; a sea-launch effect component on the blueprint; whether SV_Spawn's yaw turns the offsets.
- Air raid siren: `AKE_GEN_ENV_OBJ_AirRaid_Map17_Comona_Play` (AKB_GameSe, HDR_Env_AirRaid_Ally_loop.wav, loops; no
  Comona _Stop) [D]; a BP_SoundAmbientActor_C in Map17_SND_AmbientActor (streamed by PL_Mission022) at (-13.3, 0.6) km,
  ~30 km west of the airfield. Stock: Mission 17 / 27 LiveSoundVolumeActorExecution {event, a placed actor,
  PostEvent / Play / Stop}; Mission 13's placed Sound_Sairen_01. Survival: ULiveSoundBlueprintLibrary
  PostEventAtActorByName on an airfield actor (SHOP.sound posts by name); stop with that actor's AkComponent:Stop() (as
  sv_alicorn's silence()) [T].
- Searchlights: none in the campaign. Online Mode's ALiveSystemObjectSearchLight (SystemObject_SearchLight): spotlight
  500,000, 1.5 km reach, 3 deg cone, a beam mesh, SearchMoveMode (Yaw / Pitch / Stop), SearchingRotateSpeedNew,
  SearchWaitTime, TargetPriority (All / Player / Ally), TurnOn / TurnOff, TrackingTarget; DT_SearchLight starting pitch
  50-120 deg [D]; a child of GR053_seli_01 (searchlight vehicle) or MP039_WASAIRWatchtower_01, only in Online Mode's
  C_011, no event record drives it (sweeps by itself) [I]. Survival: the ON rows added at the main menu (hard rule 38's
  way), the unit copied with its child desc (retag_turrets / retag_parts), allied, along LCAC_RUNWAY as defence_ciws.
  Risk: it may track players.
- The Tu-160s: copy_unit from EA_Unit_01_Air2 -> SV_Unit_FestN / W / S (4 each, t160_common); 6-8 a formation with
  port_unit (copy_unit can't extend past the source). Not in BOMBERS (SV_BomberUp gives the airfield engagement order):
  their own appearance record, engagement None. Stand off: one path each, in to ~25 km, then racetrack laps in the same
  path (LADON_LAPS, rule 54), a launch each pass. Missile units: one per formation per salvo + spares (rule 16).
- Escorts for reference: Mission 30 has no bombers; Tu-160 missions: M013 (Su-25s, Su-33s, a named F/A-18F, C-130 Rapid
  Dragons with boxed cruise missiles), M026 (a LASM Tu-160 with fighters and Su-57 aces), M004 (Tu-95s and fighters).
- Night at the airfield: Survival's level has Mission 22's night lighting: within 3 km of the runway 138 lights (36
  apron floodlights ~27 m up) and ~1,050 runway / approach light meshes; whether they light under Survival's sky [T]
  (COMONA_MAP.md).

## 7. First tests (all TEST ONLY keys, one full build)
1. Shoals: SV_Unit_FishA's 8 near the airfield: boxes, lock-on; one missile, a gun burst, one bomb, with and without the
   sphere, health and DamageHistoryMap logged per shoal; z 300 vs 700; leftovers (a scorch decal on the water); the
   splash at 2-5 km. Co-op: a joiner kills one, the host log's `dn` names the joiner's slot.
2. SAL's boat at North Shoal: floats upright, its wake; gun it with EnableFriendlyFireDamage off then on (HealthInternal,
   MinHealth, DamageHistoryMap logged); a missile 150 m off (splash); try to lock it; MinHealth read right after spawn.
3. The sky: the five steps of section 5.
4. One path-flown cruise missile 15 km north at 2 km up, to the runway: distance and height each second; box and TGT,
   lock-on, one missile kills it, how low it gets, its path's end. The siren posted at an airfield actor, stopped 20 s on.
