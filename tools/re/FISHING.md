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

## 8. Build names (built 2026-11-06 on feature/fishing; nothing run in game)
What tools/build_survival.py and tools/survival_events.py build for the build contract of 2026-11-06 (the data:
survival_events.py's "GONE FISHIN' and THE FESTIVAL" section). Lua spawns every unit (none at the level's start). Each
object sits at its unit's height (offset z 0), so `SV_Spawn(unit, x, y, z, yaw)` puts them all at z, turned by yaw less
the unit's world-data yaw. The build reads everything back from the saved packages (build_survival.py
`check_fishing_build`) and fails on any difference.

### Rows
| Row | Table | What |
|---|---|---|
| `sv_shoal` -> `SV_Shoal` | DT_SV_NpcMission (Mission 22's `dummy_common`) | the shoals' mission row |
| `SV_Shoal` | DT_SV_NpcRows: **Lua adds it to DT_NPC at the main menu** | GR000_dummy + WeaponDurabilityId `NPC_WPDur_000`, ExplosionDurabilityId `test_NPC_ExpDur_000`, GameObjectDisplayName02 `SV_Shoal_Name`, ModelId `SV_Model_Shoal`, BaseScore 0 |
| `SV_Model_Shoal` | DT_SV_ModelRows: **Lua adds it to DT_NPC_Model at the main menu** | the campaign's GR000_dummy model (BP_GR000_dummy_CP), MaxHealth 10, GameObjectDisplayName01 `SV_Shoal_Name` |
| `sv_fish_boat` -> `VE027_boat2_01` | DT_SV_NpcMission (shaped as `aegs_common`) | SAL's boat, MinHealth 1.0; the stock DT_NPC row (nothing to add) |
| `sv_fest_cm` -> `OP0039_slcmp_01` | DT_SV_NpcMission (Mission 30's `slcmp_ms30` whole) | the cruise missiles (stock DT_NPC row) |
| `sv_fest_light` -> `GR053_seli_01`, `sv_fest_beam` -> `GR053_seli_light_01` | DT_SV_NpcMission (C_011's rows whole) | the searchlight vehicle and its light |
| `GR053_seli_01`, `GR053_seli_light_01`; `GR053_seli`, `GR053_seli_light`; `NWDID_GroundNPC` | DT_SV_AlcnNpc; DT_SV_AlcnModel; DT_SV_AlcnWpDur | the searchlight's Online Mode rows (NEDID_00 was in already). `SPC.alicornSetup` adds every row of these tables to the campaign's at the main menu (hard rule 38's way): no Lua change |
| `t160_common` | (Mission 4's, in already) | the festival's Tu-160s |

Text keys Lua sets with SV_SetText: `SV_Shoal_Name` (the shoals' boxes: SHOAL) and `SV_SalBoat` (the boat's callsign: SAL).

### Units
| Unit (SV_Spawn's name) | Objects (as event args name them) | Row | Side, flags | Where (world data, cm) |
|---|---|---|---|---|
| `SV_Unit_FishA` / `B` / `C` | `SV_Obj_FishA_0` .. `_7` (B, C alike) | sv_shoal | enemy (Mission 13's E_Unit02_02_Score0), box + TGT, bIsLanding off | the unit's origin on its ground at z 700: A North Shoal (1803753, -1160858), B Lighthouse Bank (1866154, 268355), C The Deep Hole (929908, -753378); its 8 shoals 0.12-0.76 km round it, 352 / 409 / 359 m apart at least (fish_offsets: a fixed seed a ground) |
| `SV_Unit_SalBoat` | `SV_Obj_SalBoat` | sv_fish_boat | ally (Mission 28's AUnit01_Sea_0: box, callsign `SV_SalBoat` shown for an ally, attack-target exception), not invincible, invincible from AI and wingmen | (1687842, -1191916, 300), yaw 157 |
| `SV_Unit_FestN` / `W` / `S` | `SV_Obj_FestN_0` .. `_3` | t160_common | enemy (copy of the heavy flight EA_Unit_01_Air2: box, no TGT), unit area 80 km, 500-6000 m | the lead at its entry, 5 km inside the zone's edge on its bearing, 2.3 km up, facing the runway: N (1610476, -3761895) yaw 90, W (-4207336, -436142) yaw 0, S (1610476, 3238105) yaw -90; `_1` 300 m beside it (outside the racetrack), `_2` / `_3` 300 m behind |
| `SV_Unit_FestCM_<g><k>` (g N W S, k 1 2 3) | `SV_Obj_FestCM_<g><k>_0` .. `_3` | sv_fest_cm | enemy, box + TGT | its group's launch point, z 200000 (N (1610476, -2936142), W (-889524, -436142), S (1610476, 2063858)), yaw towards the runway (N 90, W 0, S -90), the four side by side 60 m apart across their way |
| `SV_Unit_FestLight_1` .. `_4` | `SV_Obj_FestLightA` .. `D`, each with its light `SV_Obj_FestLight<X>_SearchLight` (sv_fest_beam) | sv_fest_light | ally (C_011's B_Ground_0 searchlight desc: faction 3 -> 1, its rank-S flag cleared, invincible from AI as C_011 has it), unit area 3 km | z 500, yaw -23: 1 (1581839, -465256) north side by the middle; 2 (1532709, -345543) past the WSW end, south; 3 (1689452, -523971) past the ENE end, north; 4 (1677811, -423430) the ENE half, south |

The searchlight spots: 36-112 m from every building or prop box, 23-25 m from every plant, 324-433 m from Mission 22's
airport objects and the STORE's CIWS spots, 380-530 m off the runway's axis (tools/checks/festival_lights_check.py, run by
the build; its data festival_lights_data.json comes from the stock level packages: `--scan`). The light's class
(/Game/OnlineMode/.../BP_SystemObject_SearchLight_Tank) is imported from C_011's world data (retag_parts).

The festival and missile units' names end in a digit (the contract's). The build stores each as the engine turns the
string into an FName: `SV_Unit_FestLight_1` = ('SV_Unit_FestLight', 2), as stock stores B_Unit_00_MainMissile_PathMove0_0,
while `SV_Unit_FestCM_N1` stays whole (its tail isn't a number). So SV_Spawn("SV_Unit_FestLight_1") finds it (port_unit
`unit_digits`).

### Paths (smooth, ControlType 1, no tube data; shaped on Mission 16's Ladon path)
- `SV_Path_Fest_N` / `W` / `S` (the unit, `_0` and `_2`): the run in from the entry along the bearing to 22 km from the
  runway, then 15 racetrack laps in the one path (hard rule 54). Each lap: the inner turn (radius 4.5 km, apex 17.5 km
  out), the outbound leg 9 km aside (22 -> 29 km), the outer turn (out to 33.5 km), the inbound leg 29 -> 22 km on the
  bearing through the launch point (25 km, a path point each lap: 16 passes in all). 2.3 km up, 700 km/h, ~3.6 minutes a
  lap. Never nearer the runway than 18.1 km (15 km asserted), inside Scripts/sv_ai.lua ZONE (the zone less 3 km).
  367 / 375 / 368 points. N's racetrack lies west of its inbound line, W's south, S's west.
- `SV_Path_Fest_NR` / `WR` / `SR` (`_1` and `_3`): the same lane 300 m outside it (nearest 17.8 km).
- `SV_Path_FestCM_<g>A` .. `D`: one per missile of a salvo (object i on lane i), from its spawn point 2 km up down to 100 m
  by 9.5 km (2000, 1850, 1400, 800, 300, 120 m at 0, 1.5, 3.5, 5.5, 7.5, 9.5 km), then 100 m over the ground on to the
  runway's centre (25 km) and 1.5 km past it; the four 60 m apart (90 m at most off the runway's centre). Their ways are
  flat (sea 3.5 m, land 5 m: height_100m.json); the tallest things near them are ~40 m trees and the airport's buildings.

### Records (EP_SurvivalMode_global; survival_events.build_festival)
| Event | Fired by | Does |
|---|---|---|
| `SV_FestUp<g>` (g N W S) | the formation's appearance (Mission 22's reinforcement-appeared trigger on SV_Unit_Fest<g>) | 0.5 s: gear up on each Tu-160, engagement None on the unit (Mission 22's RE_Wave6_AllyFly order); 1 s, only while `SV_FestRun<g>` is 0: the unit and `_0` / `_2` onto SV_Path_Fest_<g>, `_1` / `_3` onto SV_Path_Fest_<g>R, 700 km/h (Mission 22's RE_Wave2_AreaB_PathSet unit record, Mission 16's Ladon record per aircraft); `SV_FestRun<g>` 1 at 1.5 s, 0 again at 10 s |
| `RE_SV_FestUp_<g>` | Lua, right after its SV_Spawn (a unit that appears in the landing menu fires no appearance trigger) | the same records: the path once, whichever comes first; a second within 10 s gives gear and orders only, one later starts the path again from the entry |
| `RE_SV_FestCM_<g><k>` | Lua, right after it spawns SV_Unit_FestCM_<g><k> at the launch point | 0.3 s, on each missile i: Mission 30's LiveAIPathExecution (lane i, 600 km/h, its other settings), LiveAIEngagementOrder None, LiveSetLookAheadTimeSec 0. (Mission 30's LiveReinforcementExecution is Lua's SV_Spawn; its two counters are left out.) |
| `RE_SV_FestCMHit_<g><k>_<i>` (i 0-3) | Lua, on the host, when missile i is within 400 m of the runway | Mission 22's LiveDestroyUnitExecution on SV_Obj_FestCM_<g><k>_<i> |

Int flags: `SV_FestRun<g>`. No records for the shoals, the boat or the searchlights (the light sweeps by itself, as in
C_011). 51 triggers, 216 execs.

### Stock packages the build reads (in build/stock; not on build_all.sh's get_stock list, as Mission 19's and 28's)
Maps/Ingame/Mission030/WD_ and EP_Mission030_global, Datatables/AI/NPC/Mission/DT_NPC_Mission030,
OnlineMode/Maps/CompetitiveCoop/C_011/WD_C_011_03, OnlineMode/DataTables/AI/NPC/Mission/DT_NPC_Mission_C_011_ON,
Maps/Ingame/Mission028/WD_Mission028_global; for `festival_lights_check.py --scan`, Map17's level packages.

## 9. The rounds (0.74.0 Lua, feature/fishing-lua; nothing run in game)
The real GONE FISHIN', the day-night arc and THE FESTIVAL on the build data of section 8. Every mechanism is [T] until a
test confirms it.

### Parts and where they hook in
- `Scripts/sv_subs.lua` (new): the subtitle strip and the results card, `SUB.say(speaker, text, secs)` (a queue, one line
  at a time; on a co-op host inside the rounds' logic sent as `sb` to every joiner, as a callout's `co`),
  `SUB.sayHere` (this game only), `SUB.clear`, `SUB.busy`, `SUB.left`, `SUB.card(title, lines, secs)`; built by
  sv_hud.lua's hudBuild (SUB.build), shown by its hudTick (SUB.hudTick). The strip is up only while a line is.
  CFG.hud.subs / CFG.hud.card, ini [hud.subs] / [hud.card].
- `Scripts/sv_fishing.lua` "the round": SPC.kinds.fishing (sv_anomalies.lua: ready / spawn / tick / busy / over / row).
  CFG.specials.fishing (its lines in `.text`, "S|" SAL, "C|" COMONA CONTROL: a CFG `text` table, free to edit for the
  leaderboard), ini [fishing], [fishing.catch], [fishing.kg].
- `Scripts/sv_sky.lua` "the day-night arc": SKY.arc* (SKY.arcTick from sv_main.lua probeTickB, every game), ARC; SKY.apply
  takes `{ V, quiet, shadows }` now and SKY.viewCached keeps the level's sky objects (liveObj each) between its writes.
  CFG.sky.arc, ini [sky.arc].
- `Scripts/sv_festival.lua` "the round": SPC.kinds.festival; FEST.roundIs (sv_spawn.lua specialFor: never drawn, F + 6);
  FEST.killPay (sv_main.lua creditKill); the Spaceport not ready the round before it (its retake would land on it).
  CFG.specials.festival, ini [festival].
- sv_rounds.lua: SPC.canStart(kind, forced) (ready(round, forced)), cleanUnitsOf / recycleUnitsOf / the watched units for
  both kinds (the boat and the searchlights watched, never finished off). sv_spawn.lua: kindReady(k, round).
- sv_alicorn.lua: SPC.alicornReady judges the Alicorn's own rows; THE FESTIVAL's searchlight rows (CFG.specials.festival
  .rows) go to SPC.festRows (FEST.lightsReady). A searchlight row that won't go in never turns the Alicorn round off.
- sv_coop.lua: allyUnit has SAL's boat and the searchlights; "rnd" field 15 = F (a joiner keeps it in RUN.arcF, so a
  migration keeps it); `sb`, `fh|slot|catch|kg|x|y`, `fsx|kind|state|a|b|c` (unreliable, once a second), `fw|slot|kg|hits|
  empty|best|bestKg|bigone`, `fwe|players|teamKg|allyKg|round|shoals`; COOP.payOwn (this game's own pay, never split, never
  `cr`), COOP.removeObj (one object down unpaid on every game: `dn|<id>|r`), COOP.slots.
- sv_main.lua: SKY.arcTick / FISH.clientTick / FEST.clientTick in probeTickB; SKY.arcReset and SUB.clear at a restart;
  the siren off and SUB.clear at runLeft; the festival's missiles kept stock (no tier, spike or late health).

### GONE FISHIN' (once a run, from round 7, in the random rotation)
intro (SAL's boat spawned, F = this round, ~28 s of lines) -> fishing (the three grounds spawned with spheres, 3:00,
warnings at 2:00 / 1:00 / 0:30 / 0:10) -> weigh (shoals left taken off: COOP.removeNow, SPC.cleanUp, SV_Recycle 3 s on;
SAL weighs; each player's own haul graded and paid; the card) -> done (the boat switched off; the round clears).
- The deck: the weights apportioned to the shoals (24: 7 empty, 2 junk, 5 sardines, 4 mackerel, 3 tuna, 2 swordfish,
  The Big One), shuffled; a shoal down draws the next. Killer: KILL.by (co-op: the host's attribution, "wingmate" with
  p.killer = the joiner's slot); an ally's catch is the player's solo, shared out among the players at the co-op weigh-in.
- Pay: kg x 6 + the grade's bonus (S 2,500, A 1,000, B 400, C 100), + 500 with The Big One, x (1 + 0.04 per round past 7).
  Round 7: A at 770 kg with The Big One 6,120 Z (700 kg without it 5,200), S at 1,000 kg 9,000 Z; round 17 x1.4. Co-op:
  each threshold x players ^ -1 (the share of the grounds), each player paid their own (no special split).
- SAL's boat: a health drop on this game's own copy is this game's player's hit: -25 kg (once a 4 s), "THAT IS MY BOAT!"
  on this game only; never a co-op message. Its MinHealth field kept at 1 on the host.

### The arc (every game the same sky from the round, its state, its seconds and F)
k = round - F: 0 stock; 1-5 14/160, 12/180, 10/-160, 7/-140, 4/-120 (exposure to 11/14/-0.5, stars at max); 6 sunset 1
sinking to -3 / -105 (sky light x0.5, glow 100, EV 8, exposure 9.5/14/-1); 7 night (the light at the moon 35/-130, 0.5,
bluish, the moon on, sky light x0.1 blue, glow 10000, EV -2, exposure 0.5/9/0.5); 8 dawn -4/105 (exposure 4/14/-2, sky
light x0.3, glow 10000, EV 5); 9-11 rising; 12 on midday 52.9/180 held. A fight drifts 0.75 of the step over 240 s (0.45
for a swap step), the break finishes it (a swap step: the darkest point, the light at 0.25, in the break's middle).
VALKA: not from F to F+11 (her test key forces her). Written every 2 s on the kept view, the MPCs every tick.

### THE FESTIVAL (round F + 6, at sunset)
talk (~28 s, GONE FISHIN''s haul named) -> raid: the siren over the runway (every game), the searchlights (their rows
in), the formations N / W / S (SV_Spawn(unit) alone, RE_SV_FestUp_<g> 2 s on). A formation within 3 km of its launch
point (or at first 43 / 168 / 60 s, then every 216 + 30 s) launches the next free unit's salvo (SV_Unit_FestCM_<g><k> at
the point, 2 km up, yaw N 90 / W 0 / S -90; RE_SV_FestCM_<g><k> 0.5 s on), 120 s apart at least. A missile within 400 m of
the runway (5 s after its launch at least): off the list, COOP.removeObj, RE_SV_FestCMHit_<g><k>_<i>, -8 airfield; still
up 1.5 s on: finished off here (logged: the record's i may not be the spawner's order). A salvo all down: SV_Recycle(unit,
1) 3 s on. Missiles 150 Z, Tu-160s 400 Z (x the round's kill multipliers); every bomber down and nothing in the air:
4,000 + 150 x the round (a special's: split in co-op); 900 s: what's left taken off.

### TEST ONLY keys (all stripped from a release)
| Key | Part | Does |
|---|---|---|
| Ctrl+F6 | sv_sky.lua | the sky test's five steps (section 5) |
| Ctrl+F10 | sv_fishing.lua | the shoals and the boat (section 7, tests 1-2) |
| Ctrl+F12 | sv_festival.lua | one salvo and the siren (section 7, test 4) |
| Ctrl+HOME | sv_fishing.lua | GONE FISHIN' now (in the break: 3 s; in a fight: the next round), whatever once / from_round |
| Ctrl+PAGE_UP | sv_festival.lua | THE FESTIVAL next (F set so that round is F + 6: the sky blends to sunset) |
| Ctrl+PAGE_DOWN | sv_sky.lua | the arc one round on (F one less; none: from this round, F + 1), blended in |
(Ctrl+9 is the ZFA-44's, on its own branch.)

### Log lines
- `fishing: round N, GONE FISHIN': SAL on the radio (...)`, `fishing: round N: 24 shoals on the grounds: ...; the deck: ...`,
  `fishing: shoal <unit> #i down at +N s by <side> (player N): <catch> N kg; ...`, `fishing: N s left (N shoals up)`,
  `fishing: SAL's boat hit here (a -> b): -25 kg off your haul (...)`, `fishing: round N: the weigh-in (...)`,
  `fishing: the weigh-in here: N kg (...), grade X, paid N Z (...)`, `fishing: round N over (...)`,
  `fishing: SAL's boat switched off here (...)`, `fishing: a shoal's copy here got no sphere: ...`.
- `sky: arc: GONE FISHIN' at round F (...)`, `sky: arc: the stock sky from ...; written through ...`,
  `sky: arc: round N (F+k): k, u (the fight | the break[, darkening | lightening]): sun el / az, factor, exposure, ...; N values
  written` (on a step's change, else once a minute), `sky: arc: round N: the sun swapped for the moon at the break's darkest
  point`, `sky: arc: over (...)`.
- `festival: round N, THE FESTIVAL at sunset: ...`, `festival: the air raid siren ...`, `festival: the raid: Tu-160s ...;
  searchlights ...`, `festival: the <g> formation's salvo N (<unit>, <why>): ...`, `festival: RE_SV_FestCM_<g><k>: fired`,
  `festival: missile i of <unit> within N m of the runway ...: RE_SV_FestCMHit_... fired, -8 airfield`, `festival: missile i of
  <unit> shot down ...`, `festival: <unit> off the spawner's list ...`, `festival: the <g> formation is down`,
  `festival: round N: the raid over (...)`, `festival: the host's raid: the air raid siren here: ...`.
- `special: THE FESTIVAL's searchlight rows (in the Alicorn's tables): N of 5 in`, `subs: <speaker>: <line> (N s)`,
  `subs: card <title>: ...`, `coop: the host's run has no GONE FISHIN' (rnd field 15): the arc off here`.

### In-game checklist (one build; solo first, then co-op)
1. Ctrl+HOME in a break: the intro on the strip (readable, clear of the minimap; SAL amber, CONTROL blue), the boat up.
2. The shoals: boxes on all three grounds; a missile, a gun burst and a bomb each kill one; the catch callout, the splash,
   SAL's word; the NEXT row counts down with your haul.
3. Hit SAL's boat with the gun: -25 kg (the log line), "THAT IS MY BOAT!".
4. Let the time run out: the weigh-in lines, the card (shoals, best fish, total, grade, the boat, payment), the pay in the
   log; the round clears, the boat gone. Whether the card collides with the round's callouts.
5. The sky over the next rounds: the sun lower each round (the `sky: arc:` lines), no jump mid-fight; the festival's round
   at sunset; the night's swap in the break's middle; stars; the city's lights; the HUD readable at night; dawn in the
   east; midday by F+12. Whether the renderer's copies hold (else path = custom), and the MPCs stay as written.
6. Ctrl+PAGE_UP: the talk, then the siren, the searchlights sweeping (do they track you?), the three formations; a
   salvo as each passes its point (or on its clock); the missiles boxed and shootable; one let through: the impact line,
   the airfield's damage, whether RE_SV_FestCMHit_..._<i> took that missile (else the log's "finished off here" line).
7. Every bomber down: THE FESTIVAL IS SAVED, the reward, the siren stops, the searchlights off.
8. Co-op (2 players): the strip and the callouts on the joiner; a joiner's shoal kill credited to them (`fh`), each
   player's own card and pay, the team total; the joiner's own boat penalty only on their card; the sky the same on both
   (and a late joiner blending in); the siren on both; VALKA never drawn from GONE FISHIN' to F+11.
9. Quit and restart mid-arc: the sky back to stock (`sky: ... put back`), nothing left playing.
10. The Alicorn round still comes with the searchlights' rows missing (pull one from the build to try).

## 10. Code review of 2026-11-07: fixes (branch feature/decoy; nothing run in game)
Three reviewers checked each finding against the code; these are the ones in GONE FISHIN', THE FESTIVAL, the arc and the
subtitle strip. Checks: fishing_test, festival_test, arc_rounds_test, sky_test, copy_floor_test (the co-op side).
- **A restart mid-raid** (finding 3): the siren is our own actor, not the mission's, so a pause-menu Restart left it
  looping all the next run. sv_main.lua's level-load block now also calls FEST.restart (the siren off, the searchlights
  off, a joiner's raid watch forgotten: `festival: the run starts over: the siren off (...), N searchlights off`),
  FISH.boatOff, SUB.cardOff and ESC.restart (tools/re/ESCORT.md). THE DECOY lets its locks go with the old D itself.
- **The arc's view** (finding 4): SKY.viewCached kept a view 30 s, so the arc walked again (3-5 FindAllOf, ~100-350 ms)
  every 30 s with everything live, and every tick half while no sky actor was found. Now the view is kept while every
  object of it is live, however old (maxAge only when a caller asks for one), found afresh the moment one goes, and one
  with no sky actor is looked for again at most every 10 s (SKY.NO_ACTOR_S; SKY.viewWalks() counts the walks).
- **Host migration** (finding 5): only the host set RUN.fished, so a host by migration (the arc's F from "rnd" field 15,
  no RUN.fished) could draw a second GONE FISHIN'. FISH.ready: `once` and (RUN.fished or SKY.arcF()).
- **SAL's boat in co-op** (finding 6): the host's "hp" batch carried the boat, a joiner wrote it onto its copy, and that
  joiner's boatTick took the drop as its own player's hit (every joiner -25 kg for the host's splash). The boat's unit is
  left out of the host's batch (FISH.isBoat) and a joiner never writes "hp" onto its boat copy (an older host's): each
  game's copy moves with its own player's hits only, and a hit still costs its shooter.
- **A joiner unpaid after a restart** (finding 8): FISH.cl.paidRound was only reset with the level, so after the host's
  restart (newRunHere, same level) the new run's round N weigh-in wasn't paid. It's keyed by the run now (L.paidRun = RUN).
- **What the host sends, in bounds** (finding 9): "fw": a haul at most FISH.maxShoals() (8 a ground x the units, 24) x
  FISH.maxKg() (the heaviest catch's top, 400), hits and empties at most the shoals, the best fish at most 400 kg; "fwe":
  the round at most 1000, the shoals at most 24, the team and the allies' kg at most the round's most; one weigh-in's pay
  at most FISH.PAY_MAX (1,000,000: sv_coop.lua's CREDITS_MAX), the host's own too.
- **No round without its rows** (finding 10): FISH.ready is false while FISH.rowsReady isn't true (FISH.setup at the main
  menu), but for a test key's forced round: `fishing: no GONE FISHIN' round: the shoal's rows aren't in the game's
  tables (...)`, once.
- **The festival's impact record** (finding 11): RE_SV_FestCMHit_<g><k>_<i>'s i is the spawner's order only if the build's
  desc order and the spawn's agree (unconfirmed); one naming another missile j destroyed j, which then paid as a kill.
  Now the impacting missile is finished off from Lua at once, and the salvo's other missiles still up are held unpaid
  1.5 s (FEST.IMPACT_HOLD_S: off the sweep, down and cleaned; on the host COOP.payHold, so its "dn" is a removal, "r", on
  every game); one that goes down in the hold was the record's (`festival: missile i of <unit> went down within 1.5 s of
  its salvo's impact record: the record's (its i not the spawner's order), not paid`), one still up after it is let go.
  The price: a missile you really shoot down in those 1.5 s doesn't pay either.
- **The sky's originals** (finding 12): SKY.restore forgot a value whose object it couldn't find (it stayed as the arc
  had left it). It's kept now, its original with it, and tried again every tick (SKY.retryTick from sv_main.lua's
  probeTick: on the kept view, on a fresh one 10 s on, then 20, 40, ... at most every 5 minutes) until it's put back
  (`sky: <why>: every kept value put back now (N tries)`), not while the arc writes the sky; the level torn down
  forgets it untouched (LEVEL_DROPS). The custom sun's flags as before (SKY.idleTick).
- **SAL's "your friend" line solo** (finding 17): it went by the slot (-1, the allies', only in co-op), so solo it never
  played. It goes by who it was now (not you nor a teammate); solo the catch is still credited to you (your haul, the
  card and the Big One's bonus unchanged), which was simpler and kinder than moving it to the allies' haul.
- The rotation's commented ini line and the Worker's SPECIALS (findings 14, 15): tools/re/ESCORT.md.
- rounds_test (failing on the base: 7) stubs FISH: it loads none of 0.74.0's parts and GONE FISHIN' is in the rotation.
