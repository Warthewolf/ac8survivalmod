# Airfield health, bombers, landing + resupply (research for Milestones 3 and 4, 2026-10-22)

Sources: stock EPs dumped with `tools/checks/ep_dump.py` into `build/research/airfield/EP_*.txt` (line numbers below
are lines of those dumps = stock record order), world data with `build/research/airfield/wddesc.py <WD> <list re>
<name re>` (full desc dump, a scratch helper next to the dumps), enums from `tools/usmap.pkl`, UFUNCTIONs with
`tools/re/refl.py`. Arg lists: `Type` byte then value; TipsHashes left out (copy whole records, never retype them).
Names written `X_0` in EP args are FNames (X, number 1): hard rule 17.

## Summary
- **Mission 004's "base HP" isn't health.** It's an int flag counting enemy missiles that reach invincible dummy
  targets at the base (`MissedWeapon_V2` trigger, `Flag_Wave2_WhiteValleyAirbase_DamageCount`). RE_BaseHP_Norml/Easy
  only arm the threshold triggers (Normal 8/16/24/32, Easy 10/20/30/40). At the last one the mission fails.
- **Mission 022 already has a Comona Airport strike built the same way**: 4 Su-34s (`ERB_Unit_01_Air2`) are given the
  airport unit `AB_Unit_01_Ground0` as their target (search type GROUND_ONLY). They fire at its 4 invincible dummies
  (`TAG_AreaB_Dummy_Obj`), and `MissedWeapon_AreaB_0..3` play an explosion VFX on each one. Everything is already in
  Survival's world data, and every node class is in Survival's EP imports. **This is the pattern to copy, not M004's
  scripted paths.**
- Real health also works: Mission 013's runway base (`A_Unit01_MotherBase0`, escorted unit, NPC row `Runway`) uses
  `LiveSetMaxHealthExecution`, `LiveTakeDamageUnitHealth`, and `UnitDamage` triggers with `HPPercent`. Lua can also
  read and set any object's health through reflection: `LiveGameObject.HealthInternal/MaxHealth/MinHealth`,
  `GetHealth()`, `GetMaxHealth()`, `ModifyHealth(InValue, DamageCauser, bCauseDamageEvent)`.
- The stock health bar node `LiveUnitHealthDisplaySwitch(unit, All|HUDOnly|UIOnly, show, bool)` is only used for real
  in M025_2 (M006's use is a debug event that never fires). Mission 22's imports don't include it.
- Landing works in Survival already (test 5): Mission 22 never enables takeoff/landing, because it's on by default
  with `Mission022_MiniGame` loaded. Mission 22 only turns it off (`LiveSetTakeoffAndLandingEventExecution false, 0`).
  The supply chain is built on `FinishInGameHangar` (0x9d), `ReturnFromHangar` (0x99) and `MiniGameEnding` (0x9a).
  None of these records are in `EP_SurvivalMode_global` yet (it has only MissionStart, SV_FlightUp/Down and the chase).

---------------------------------------------------------------------------------------------------------------------
## 1. Airfield health

### 1a. Mission 004's base (White Valley Airbase), world data `WD_Mission004_global`
| desc | contents |
|---|---|
| `AB_Unit_01_ground0` (Faction 1, r 6000 m, at (1000, -624343, 0)) | 1 object `AB_Obj_01_ground0_CtrlTower` (`RadarTower01_common`, bIsInvincibleFromAI, bIsAttackTargetsException, tag SND_EscortTarget) at (930, -560940, 8410). It's only the BattleNavigation ping anchor. |
| `AB_Unit_01_ground1` (Faction 1, unit tag `TAG_Obj_Base_AttackPoint_Dummy`, at (983, -624343, 6000)) | **3 attack-point dummies** `AB_Obj_01_ground1_Dummy0/1/2` (`dummy_common`, **bIsInvincible**, bIsLanding, tag `TAG_Obj_Base_AttackPoint_Dummy`) at (-1813, -615278, 8307), (4493, -562663, 8220), (-351, -586912, 8235); plus 3 PPM dummies, 6 `gepa_common` AA guns, 2 `avng_common` SAMs |
| `VFXActor_BaseDamage_Phase1/2/3` (3 each) | damage fires, tags `TAG_VFX_BaseDamage_Phase01..03` |
| paths `01_MB_BaseAttack_{0..3}_Path{0,1}`, `01_MB_BaseAttackAssist_{0..2}_Path{0,1}` | attack-run loops (below) |
Flags (EF_Mission004_global): int `Flag_Wave2_WhiteValleyAirbase_DamageCount` (0), bool `Flag_Bool_Base_Navi_CoolTime`,
timer `Flag_Timer_Base_Navi_CoolTimer` (LimitTime 8.0).

### 1b. How damage is counted: EP records, stock order
Triggers:
```
 363 FlagInt_Phase05_R_101   life1 6b(FlagInt) {0c DamageCount} {0f 1} {0e Geq}
 364 FlagInt_Phase05_R_103   life- 6b {0c DamageCount} {0f 8}  {0e Geq}      Normal 1st   (armed by RE_BaseHP_Norml)
 365 FlagInt_Phase05_R_999   life- 6b ... {0f 32} {0e Geq}                    Normal fail
 366 FlagInt_Phase05_R_105   life- 6b ... {0f 16} {0e Geq}                    Normal 2nd
 367 FlagInt_Phase05_R_107   life- 6b ... {0f 24} {0e Geq}                    Normal 3rd
 747 Default_MissedWeapon_V2 life- 10(MissedWeapon_V2) {0e EnemyNPC} {0e Any} {0e None} {0e Any} {01 NoneSelect}
                             {0a TAG_Obj_Base_AttackPoint_Dummy} {0e NormalMissile} {0e NoCheck} {11 false}
1271 RE_BaseDamageVFX_Update life- 4f      1273 MissionStart_A life- 01
1672 RE_BaseHP_Norml life- 4f            1673 RE_BaseHP_Easy life- 4f
1674 FlagInt_Phase05_R_104   ... {0f 10} Geq   1675 _1000 {0f 40} Geq   1676 _106 {0f 20} Geq   1677 _108 {0f 30} Geq  (Easy)
1849 RE_BaseNavi life- 4f
1862 FlagTimer_Radar0_Cooltimer_0 life- 6e(FlagTimer) {0c Flag_Timer_Base_Navi_CoolTimer} {10 0} {0e Leq}
1863 Default_MissionStart_7 life- 01
1941 CompositeEvent_Phase05_R_101 life1 2f mon=[FlagInt_Phase05_R_101]
1942 CompositeEvent_Phase05_R_103 life- 2f mon=[FlagInt_Phase05_R_103 op01, FlagInt_Phase05_R_104 op01]   (Normal|Easy)
1943 CompositeEvent_Phase05_R_999 mon=[_999, _1000]   1944 _105 mon=[_105, _106]   1945 _107 mon=[_107, _108]
```
(1835-1842 `FlagInt_Phase05_R_109..114/1001/1002` are `Equ` twins with no execs: dead.)
Execs:
```
2817 CompositeEvent_Phase05_R_101  LiveRadioPlayExecution {0d 01_Base_Damage_Count_1} {02 NoneSelect} {0a NoneSelect} {10 0} {11 false}x3
2818 .._R_103 Radio 01_Base_Damage_Count_2 | 2819 .._R_105 ..._3 | 2820 .._R_107 ..._4 | 2821 .._R_999 ..._Game_Over
2822 .._R_101 LiveBattleNavigationExecution {0a NoneSelect} {02 AB_Unit_01_ground0} {0e Single} {11 true}
2823 .._R_103 ... Single | 2824 .._R_105 ... Double | 2825 .._R_107 ... Triple   (ELiveRadarPingTimingType)
3034 .._R_999 LiveCallRemoteEventExecution {0d RE_Phase5_BaseDestroy}
3035 RE_Phase5_BaseDestroy LiveMissionFinishExecution {0e MissionFailed} {11 false} {11 false}
3473 Default_MissedWeapon_V2 LiveFlagOperation_IntExecution {0c Flag_Wave2_WhiteValleyAirbase_DamageCount} {0e Add} {0f 1}
4093 .._R_107 LiveSetActiveVFXExecution {05 NoneSelect} {0a TAG_VFX_BaseDamage_Phase03} {11 1}   (4094 _105 -> Phase02, 4095 _103 -> Phase01)
4723-4730 Default_CompositeEvent_137 (checkpoint restart): DamageCount Set 9 if >9 (Normal) / 5522 Set 12 if >12 (Easy);
          RE_BaseDamageVFX_Update re-lights the VFX per threshold (4724-4729, 5523-5528, conditional on count + difficulty)
5182.. MissionStart_A LiveSetMaxHealthExecution (other units, not the base)
5520 MissionStart_A LiveCallRemoteEventExecution {0d RE_BaseHP_Norml}  cond LiveIsAchievedDifficultyCondition(Normal, Geq) State_True
5521 MissionStart_A LiveCallRemoteEventExecution {0d RE_BaseHP_Easy}   cond same, State_False
5903 .._R_999 LiveBattleNavigationExecution ... Quadruple
5904-5906 .._R_105/_107/_999 LiveSetRadioMuteOptionsExecution {11 true} {0e None} {0d <previous Base_Damage_Count line>} {0d ""}
5910-5917 each CompositeEvent_Phase05_R_N  LiveSetActiveTriggerExecution {11 false} {08 <its two FlagInt triggers>}
5927-5934 RE_BaseNavi LiveBattleNavigationExecution, ping count by DamageCount band (Leq 15/23 Normal, 19/29 Easy)
5991 Default_MissedWeapon_V2 LiveCallRemoteEventExecution {0d RE_BaseNavi}   cond Flag_Bool_Base_Navi_CoolTime State_False
5992 FlagTimer_Radar0_Cooltimer_0 LiveFlagOperation_BoolExecution {0c Flag_Bool_Base_Navi_CoolTime} {0e Set} {11 false}
5993 FlagTimer_Radar0_Cooltimer_0 LiveStopTimerExecution {0c Flag_Timer_Base_Navi_CoolTimer}
5994 Default_MissedWeapon_V2 LiveFlagOperation_BoolExecution {0c Flag_Bool_Base_Navi_CoolTime} {0e Set} {11 true}  (same cond)
5995 Default_MissedWeapon_V2 LiveStartTimerExecution {0c Flag_Timer_Base_Navi_CoolTimer} {11 true} {11 false}  (same cond)
5996 Default_MissionStart_7 LiveFlagOperation_BoolExecution {0c Flag_Bool_Base_Navi_CoolTime} {0e Set} {11 false}
6093-6096 RE_BaseHP_Norml LiveSetActiveTriggerExecution {11 true} {08 FlagInt_Phase05_R_103 / _105 / _107 / _999}
6097-6100 RE_BaseHP_Easy  LiveSetActiveTriggerExecution {11 true} {08 FlagInt_Phase05_R_104 / _106 / _108 / _1000}
```
Damage sources: every `MissedWeapon_V2` event = +1 (a missile an enemy fired at a dummy ended: the dummies are
invincible, so "missed" also covers hits), plus scripted `+3` (`Default_CompositeEvent_31/25`, delays 5 s / 11 s).
The `bomb` variant `Default_MissedWeapon_V_3` (weapon `WID_ugb`, object `AB_Obj_01_ground0_CtrlTower_0`) only prints
a debug string.

### 1c. Comona Airport: what Mission 22 (and so Survival's world data) already has
Coordinates (cm, `WD_Mission022_global`, all copied into `WD_SurvivalMode_global`):
| desc | where | notes |
|---|---|---|
| `VolumeBox_LandingArea0` | (1609574, -435747, 0), yaw -23, extents 895 x 15 x 30 m | runway (build_survival's RUNWAY) |
| `VolumeBox_LandingArea1` | same centre, 1073 x 48.9 x 50 m | approach box |
| `AreaB_MarkActor0` (MarkActorDesc) | (1609640, -436414, 501) | airport anchor; M22 moves attacker areas here |
| `AB_Unit_01_Ground0` (Faction 1, tags TAG_Ground, TAG_GroundAlly, r 6000 m) | unit (1609688, -436384, 500) | `AB_Obj_01_Dummy0..3` (`dummy_common`, bIsInvincible, bIsLanding, tag `TAG_AreaB_Dummy_Obj`, Dummy0 also `TAG_AreaB_Dummy_Random`) at (1562045, -419713), (1589350, -416394), (1646052, -444739), (1619127, -446083), z 501; + 5 `gepa_common` AA guns `AB_Obj_01_Ground0_AAGUN_0..4`, 2 `avng_common` SAMs `..SAM0/1` |
| `AB_Unit_01_Ground2` (same faction/tags) | same point | **only the 4 dummies**, `AB_Obj_01_Dummy4..7`, same positions and tags. M22's landing-time attacker target |
| `AB_Unit_01_Ground1` (Faction 2) | (1610850, -434704, 1247) | one invincible dummy, AI-invincible, attack-target exception (not a target) |
| `VFX_AreaB_Dummy` x4 (VFXActorDesc) | on the 4 dummies | EP names `VFX_AreaB_Dummy_0..3` |
| `Cylinder_AreaB_Notify_rityaku0` | (1602782, -432457, 500), r 10 km, half-height 3 km | player-only; M22 `Default_VolumeEvent_3` runs `LiveSetVolumeAttributeException` on it |
| `VolumeBox_AreaB_TargetPlayer` | same centre, 6000 x 2929.5 x 1500 m, yaw -22 | |
In Survival all of these units have `bIsSpawnFromStart` off (build_survival.py). Spawn them with `KEEP_AT_START`
(own position) or with `SV_Spawn` at their own point.

M22's airport records (EP_Mission022_global), stock order:
```
 378-381 MissedWeapon_AreaB_0..3 life1 10 {0e EnemyNPC} {0e AllyNPC} {0e None} {0e Any} {01 AB_Obj_01_Dummy0..3}
                                         {0a NoneSelect} {0e NormalMissile} {0e NoCheck} {11 false}
2015-2018 MissedWeapon_AreaB_N LiveSetActiveVFXExecution {05 VFX_AreaB_Dummy_N} {0a NoneSelect} {11 1}
```

### 1d. Real health instead of a counter (Mission 013 / M022 shuttle / reflection)
- M013 `A_Unit01_MotherBase0`: escorted unit (`bIsEscortedUnit` true, Faction 1, r 7000 m), one object
  `A_Obj01_MotherBase0_Dummy0` (NPC row `Runway` -> NpcId `MS13Runway_01`, MaxHealthDifference 600, TargetMarkType 3,
  tag SND_EscortTarget). `Phase02_Start_Base`: `LiveSetMaxHealthExecution {01 obj} {02 NoneSelect} {0a NoneSelect}
  {10 2200.0} {11 false}` (+ `LiveSetMinHealthExecution {0b obj} {02 NoneSelect} {0a NoneSelect} {10 2200.0}` before
  takeoff). Scripted damage: `LiveTakeDamageUnitHealth {02 A_Unit01_MotherBase0} {0a NoneSelect} {10 10.0}`. Thresholds:
  `UnitDamage` (0x72) `{02 unit} {0a NoneSelect} {0e None} {0e HPPercent} {0f 50} {0e Any} {0a NoneSelect} {11 false}{11 false}`
  (`ELiveUnitDamageCalcOption`: Number, NumberPercent, HPPercent, FirstAttack). Fail at HPPercent 0. Display name:
  `LiveSetGameObjectDisplayName ... {0e DISPLAYNAME_01} {0d ContainerGround_Name_Airbase}`.
- M22 itself: shuttle `AA_Obj_01_Ground0_Shuttle_0` (`sstb_common`) `LiveSetMaxHealthExecution ... {10 175.0}`, kept alive
  with `LiveSetMinHealthExecution ... {10 1.0}`; `ControlCenter_common` (`AA_Obj_01_Ground0_Tower_0`) is a damageable
  building row in DT_NPC_Mission022 (but that's the spaceport, -1325361 / 61516, not the airport).
- **Lua / native, at run time** (reflection, AceCombat8.exe of 2026-09-29): `LiveGameObject` (Pawn) has properties
  `MaxHealth`, `MinHealth`, `HealthInternal`, `bIsInvincible`, and UFUNCTIONs `GetHealth()->float`,
  `GetMaxHealth()`, `GetMinHealth()`, `GetDamagePercentage()`, `ModifyHealth(float InValue, UObject DamageCauser,
  bool bCauseDamageEvent)->float`, `SetMinHealth(float)`, `SetIsInvincible(bool)`, `IsAlive()`, `GetUnitName()->FString`,
  `GetObjName()->FString`. So Lua can find the airfield object (FindAllOf("LiveAIGameObject"), match GetObjName()),
  read its health for the HUD and repair it with ModifyHealth (+). Prefer ModifyHealth over writing HealthInternal:
  it probably fires damage/death events. Lua already reads EP int flags (main.lua `flagLine`:
  `LiveEventContainer.FlagData.IntegerFiled`), so a counter can drive Survival's own HUD bar as well.

### 1e. The stock health bar
`LiveUnitHealthDisplaySwitch`, `ELiveDisplayUnitHealthType {All, HUDOnly, UIOnly}`. Only real use:
`EP_Mission025_2_global` 5163, `Default_PhaseStart_5` (PhaseStart Phase01): `{02 AA_Unit_01_Ground01_0} {0e All}
{11 true} {11 false}` on an ally tank unit (5 M1A2s, health set back to 100 by `LiveSetHealth {02 NoneSelect}
{0a NoneSelect} {01 obj} {10 100.0}` per phase). M006 1343-1344 (`Debug_LCAC_DisplayHealth_0`, a composite with no
monitors) never fires. HUD side: `LiveHUD.UnitHealthList`, `WBP_HUD_UnitLife_List_000` / `_Item_000`
(`LiveUnitLifeItem`: UnitNameText, UnitHealthBar), world-space `BP_UnitLifeActor`. FLiveUnitDesc also has
`bDrawUnitHealth` and `bIsEscortedUnit` (M009/M010/M011/M013/M019 escort targets; no stock desc sets bDrawUnitHealth).
**Survival's EP has no import for it**. It's a script import (`/Script/...LiveUnitHealthDisplaySwitch`,
scriptobjs hash 0x4fb3f7e60e910abc), so adding it is an import-map entry only, with no package or container-header
dependency. Same for `LiveTakeDamageUnitHealth` (0x7f38ef7e7fa10eb0) and `LiveSetWeaponAmmoCount` (0x72fecafd8e325215).
These three are the only node classes below that are missing from M22's imports.

### What Survival should add (airfield)
1. **Target**: spawn `AB_Unit_01_Ground2` (4 invincible dummies, no AA) at mission start (`KEEP_AT_START`, own
   position). Optional flavour: `AB_Unit_01_Ground0` adds 5 AA guns + 2 SAMs that shoot at bombers (they can be
   destroyed and aren't respawned).
2. **Damage counter (recommended, stock-proven)**: one trigger from template `MissedWeapon_AreaB_0`, made
   unlimited (`life` cleared) and retargeted to the tag: arg4 `{01 NoneSelect}`, arg5 `{0a TAG_AreaB_Dummy_Obj}` (M004
   uses the tag form). Execs: `LiveFlagOperation_IntExecution SV_AirfieldDmg Add <n>` (+ the M22 VFX on the hit
   dummy if per-dummy triggers are kept). Keep the counter in an int flag (`INT_FLAGS`, hard rule 17 keys). Lua maps it to
   0-100 for the HUD (100 - dmg*step, `CFG.airfield.hit_damage`), handles AirfieldDown at <= 0 and repairs by
   writing the flag (writing `IntegerFiled` values from Lua is untested; fallback: an `RE_SV_AirfieldRepair` remote
   event that sets the flag, called from the EP by a timer or a Lua-set trigger flag).
   Hard rule 6 may apply (first counted event dropped): check in test.
3. **Or real health**: same dummies but read health from Lua; needs a non-invincible object (drop `bIsInvincible`
   from one dummy, `LiveSetMaxHealthExecution 100` at MissionStart from M22's shuttle record), and `UnitDamage
   HPPercent` triggers (template M22 `01_A_AreaA_UnitDamage`, arg3 -> `HPPercent`). Risk: dummy_common may have no hit
   collision; M013 used the dedicated `Runway` row (not in DT_NPC_Mission022: AddRow per NPC_DATA.md).
4. **Health bar**: Survival's own HUD layer (HUD_LAYOUT.md), fed by the counter or GetHealth(). That works with
   no new imports and always shows 0-100. `LiveUnitHealthDisplaySwitch` is the stock alternative (add the script
   import; arg0 = unit FName, e.g. `AB_Unit_01_Ground2`).
5. **AirfieldDown**: Lua sets it at 0 and plays a radio callout. M004's lines `01_Base_Damage_Count_1..4/_Game_Over`
   live in DT_Rdo_ST_ms004, so clone them into DT_SV_Radio (MUSIC_RADIO_CAMERA.md). Also play
   `LiveBattleNavigationExecution {0a NoneSelect} {02 AB_Unit_01_Ground2} {0e Single..Quadruple} {11 true}` (M22 has
   the class) as hits come in, with M004's 8 s cooldown (`RE_BaseNavi` pattern). Close the airfield with
   `LiveSetTakeoffAndLandingEventExecution {11 false} {0f 0}` and reopen with `{11 true} {0f 0}` (records `RE_SV_AirfieldClose/Open`,
   template M22 `Default_Campaign_ExterminationBattleSuccess`). Back online at 50: Lua resets the counter.

---------------------------------------------------------------------------------------------------------------------
## 2. Bombers

**The heavies' routes (0.72.1) [I].** With their unit area over the runway (Mission 22's 6 km, then 1.5 km from 0.20)
the Tu-95s / Tu-160s never came within drop_km: they circled 8-12 km out (test of 2026-10-22) and then 6-8 km out (the
user's run of 2026-10-29, Lua 0.72.0: "tu-95's aren't attacking the base, they fly around nearby and do nothing"; the
log's closest 6.3 km in 4 minutes). They fly paths now, as the Ladons do (hard rules 1, 2, 35): tools/survival_events.py
HEAVY_* / heavy_routes (8 compass sectors x the 2 heavy flights: a route in over the runway and a figure-8 crossing it
twice a lap, 54 km, ~4 min at 850 km/h), build_survival.py heavy_paths, build_heavy (RE_SV_HeavyRoute_<NN><S> on the
lead, PathFinish -> the loop, each loop's end -> the loop again; RE_SV_HeavyLoop_<NN><L><S> for the next lead), and
Scripts/sv_flights.lua HEAVY (the sector from the spawn point, the handover from bombTick). Their area is 40 km now
(HEAVY_AREA_RADIUS_M), so no point of a route is outside it. Lines to look for: `events: RE_SV_HeavyRoute_NNS (... route
in from bearing B) fired`, `bombers: ... over the airfield`, `bombers: ... bomb run (RE_SV_BombRun_NN): fired`, `bombers:
UNIT's lead down: object N takes the loop`. Not known yet: whether the wingmen keep formation on a pathed lead, and
whether the airfield order (Normal on AB_Unit_01_Ground0) pulls a pathed heavy off its path. tools/checks/heavy_test.sh.

### 2a. Mission 004 base attackers
Units (`WD_Mission004_global`, all r 6000 m): `EB_Unit_02_Air3` (1x `a06e_common`), `EB_Unit_01_Air3` (1x `mr2k_common`),
`EB_Unit_03_Air0/Air2` (4x `a06e_common`), `EB_Unit_03_Air1/Air3` (4x `mr2k_common`), plus `m21b`/`mr2k` escorts.
`a06e_common` and `mr2k_common` are only in DT_NPC_Mission004.
Chain for `EB_Obj_02_Air3_a06e_0`:
```
2017 TRIG CompositeEvent_Phase04_Attacker_Entry life1 2f mon=[VolumeEvent_Phase04_E_2, Default_AreaBoundaryForAI_1]
2783 EXEC  ... LiveAIEngagementOrder {01 NoneSelect} {02 EB_Unit_02_Air3} {0a NoneSelect} {0e None} {0b NoneSelect}
           {02 NoneSelect} {0e Default} {0e None} {11 true}x3 {11 false}x4 {10 0}         (no engagement while on the run)
3423 EXEC  ... LiveCallRemoteEventExecution {0d RE_Phase04_BaseAttackEnemy_a06e_0}
3638 EXEC RE_Phase04_BaseAttackEnemy_a06e_0 LiveAIPathExecution {01 EB_Obj_02_Air3_a06e_0} {02 NoneSelect}
           {04 04_Air3_a06e_0_Path0} {0a NoneSelect} {10 1200.0} {10 20.0} {10 19.0} {0e ObjectSetting} {10 0}
           {11 false} {11 true} {11 false} {10 0} {11 false} {10 0} {11 false}   (1800 / 0.0 if Phase04 shotdown >= 2)
3641/3642  Flag_Int_Enemy_MoveState_Wave2_0 = 1, start Flag_Timer_Enemy_MoveState_Wave2_0 (path watchdog, 10 s)
1282 TRIG Default_PathFinish_57 (04_Air3_a06e_0_Path0 Finish) -> 3639 LiveAIPathExecution 01_MB_BaseAttack_2_Path0
           (delay 0.1, {10 800} {10 20} {10 15} ObjectSetting), MoveState = 2, LiveAIPathExitExecution first
 602/603 TRIG PathFinish_Phase04_BaseAttack_0/_1: Path0 -> Path1 -> Path0 ... (3201/3202, {10 800.0} {10 20.0} {10 15.0})
 604/605 TRIG PathPointReceive_Phase04_BaseAttack_0/_1 {01 obj} ... {04 01_MB_BaseAttack_2_Path0/1} ... {0f 1}  (point 1)
3205/3206  -> LiveCallRemoteEventExecution {0d RE_Wave2_Attac_a06e_0}
3203..3212 RE_Wave2_Attac_a06e_0 LiveFireOneShotWeapon {0e WN_WEAPON_3} {01 EB_Obj_02_Air3_a06e_0} {0b NoneSelect}
           {0a TAG_Obj_Base_AttackPoint_Dummy | TAG_PPMn_Obj} {11 false} {0d ""} {11 false}
           (target picked by Flag_Wave2_AttackTargetNo / Flag_Bool_IsPPMTarget; RE_AttackNoUpdate cycles it)
4894..     + LiveSetActiveVFXExecution VFXActor_A06E_UGB0.. delay 3 (bomb blast VFX)
```
Paths: `01_MB_BaseAttack_2_Path0` = begin (126621, -776793, 70580) -> (39242, -649149, 32016) -> (-66974, -447852,
24770) -> (-276469, -658088, 111330) -> (-48209, -751714, 40610); `_Path1` loops back. ControlType 2, PathTubeData
with MovementPattern sub-objects (exports `LiveAIPathTubeMovePattern*` of the WD). So **M004's attack runs are
scripted**: the missile is forced by `LiveFireOneShotWeapon` at path point 1, which needs PathPointReceive (hard rule
1: it never fires in our mods).

### 2b. Mission 022's Comona Airport strike (copy this one)
`ERB_Unit_01_Air2`: 4x `su34_common` (`ERB_Obj_01_Air2_su34_0..3`), spawn (3341774, -3037105, 60000) yaw 133.8,
about 31 km SSE of the runway at 600 m. Paths `R_01_Air2_su34_1_AIPath0..3` (ControlType 1, 2 points, ending about 3 km SE of the
airport at 600 m, e.g. (1827048, -664463, 60000)). Records, stock order:
```
 217 TRIG 01_E_Wave02_ReinforcementAppearance_1 life- 23 {02 ERB_Unit_01_Air2} {0a NoneSelect} {0f 0}
 218 TRIG RE_Wave2_AreaB_PathSet life- 4f
 219 TRIG Default_PathFinish_11 life- 2d {01 NoneSelect} {02 ERB_Unit_01_Air2} {04 R_01_Air2_su34_1_AIPath0} {0a NoneSelect} {0e Finish}
 220 TRIG Default_AreaBoundary_11 life- 0c {0e LocalPlayer} {0e Enter} {0e DontFind} {0e SubCategory_None} {02 ERB_Unit_01_Air2} {0e None}
 221/222 TRIG AreaBoundary_AreaB_Mult_Exit / _Entry (same, Exit / Enter)
 941 TRIG Default_CompositeEvent_19 life1 2f mon=[Default_PathFinish_11, Default_AreaBoundary_11]
1044 TRIG Default_CompositeEvent_98 life- 2f mon=[01_E_Wave02_ReinforcementAppearance_1, Default_MissionRestart_15]
1680-1689 RE_Wave2_AreaB_PathSet LiveAIPathExecution unit + each su34 -> R_01_Air2_su34_1_AIPath0..3, {10 2000.0} {10 0} {10 0}
          {0e ObjectSetting} {10 0} {11 false}x3 {10 0} {11 false} {10 0} {11 false}
1683-1691 Default_CompositeEvent_19 LiveAIPathExitExecution (unit + each object), then
1686      LiveUnitMoveActor {02 ERB_Unit_01_Air2} {01 NoneSelect} {02 NoneSelect} {09 AreaB_MarkActor0} {10 0} {10 2000.0}
          {10 0}x4 {11 false} {11 false} {0e None} {11 false}x4                (unit area onto the airport)
1687 01_E_Wave02_ReinforcementAppearance_1 LiveCallRemoteEventExecution {0d RE_Wave2_AreaB_PathSet}
1692 AreaBoundary_AreaB_Mult_Exit  LiveAIEngagementOrder {01 NoneSelect} {02 ERB_Unit_01_Air2} {0a NoneSelect} {0e EvadeOnly} {0b NoneSelect} {02 NoneSelect} {0e Default} {0e None} {11 true}x3 {11 false}x4 {10 0}
1693 AreaBoundary_AreaB_Mult_Entry LiveAIEngagementOrder ... {0e Normal} ... {02 NoneSelect} {0e Default} ...
1694 Default_CompositeEvent_98 LiveAIEngagementOrder {01 NoneSelect} {02 ERB_Unit_01_Air2} {0a NoneSelect} {0e Normal}
          {0b NoneSelect} {02 AB_Unit_01_Ground0} {0e AIOnly} {0e None} {11 true}x3 {11 false}x4 {10 0}
2037 Default_CompositeEvent_98 LiveAIChangeEnemySearchType {01 NoneSelect} {02 ERB_Unit_01_Air2} {0a NoneSelect} {0e GROUND_ONLY}
```
The AI does the bombing itself (engagement target = the airport unit, ground-only search). Its missiles end on the
invincible dummies, so `MissedWeapon_AreaB_*` fire. No PathPointReceive and no LiveFireOneShotWeapon are needed. M22 also
sends `EB_Unit_01_Air0` at `AB_Unit_01_Ground2` when the player lands (`01_BoxVolumeEvent_6`, 2633) and at the player
on takeoff (`01_BoxVolumeEvent_5`, 2191 `AttackOnly`, `{0b Player}`, `PlayerOnly`).

### What Survival should add (bombers)
- A bomber pool next to the fighter pool: `ERB_Unit_01_Air2` (4 Su-34) plus 1-2 more descs copied from it (new
  Name/UniqueID, objects renamed). Aircraft by `SV_SetAircraft`: rows already in DT_NPC_Mission022 that suit the role:
  `su34_common`, `f15e_common`, `a10c_common` (`a06e`/`mr2k`/`su25`/`t160` would need AddRow + blueprint imports).
- Spawn with `SV_Spawn` 20-30 km out (no paths, so hard rule 2 doesn't apply), then on its `SV_BomberUp_N` (0x23)
  trigger: `LiveUnitMoveActor` unit -> `AreaB_MarkActor0` (r 2000, M22 1686), `LiveAIChangeEnemySearchType GROUND_ONLY`,
  `LiveAIEngagementOrder Normal` target unit `AB_Unit_01_Ground2`, `AIOnly` (M22 1694). Keep bombers **out of the
  chase** (RE_SV_Chase moves areas onto the player) and out of `POOL`. Use a separate `BOMBERS` list in
  survival_events.py with its own up/down flags.
- Radio callout on appearance (spec 5): RE_SV_Radio_Bombers. Optional fighter escort ordered `AttackOnly` on the player.
- If the AI doesn't commit to the dummies (test), fall back to M004's forced shot: a `VolumeEvent` (0x3f, template M22
  `Default_VolumeEvent_3`) on `Cylinder_AreaB_Notify_rityaku0` with `{0e EnemyNPC}` + unit, firing
  `LiveFireOneShotWeapon {0e WN_WEAPON_n} {01 obj} {0b NoneSelect} {0a TAG_AreaB_Dummy_Obj} ...` (M22 has 70 of these;
  the weapon slot per aircraft must be checked).
- New WD paths, if wanted later: deep-copy an M22 AIPathDesc with empty `MoveData` (most of M22's 145 paths are
  like that, so no new tube sub-object exports are needed): BeginPointDesc + PathPointDescList {Pos, tan, Up, PointType,
  PathPointRotation, UniqueID, Name}. The WD trailer (`tools/scripts/wdtrail.py`: outliner tree + desc index list)
  should get the new nodes. Stonehenge's podarge_build shows how. Adding descs without it has worked so far.

---------------------------------------------------------------------------------------------------------------------
## 3. Landing + resupply (Mission 022)

### 3a. Flow and triggers
`ELiveMinigameType`: Launch, TakeOff, TakeOff_Tunnel, LandingOnShip, Landing, SeamlessIn, SeamlessOut, Hangar,
AerialRefueling. Exe classes: `ALiveSystemObjectLandingMinigame`, `...SeamlessInMinigame`, `...HangarMinigame`,
`...SeamlessOutMinigame`, `...TakeOffMinigame`. `LivePlayerTakeoffAndLandingComponent` (LandingControlTower,
TakeoffControlTower) sits on `BP_ControlTower_AirPort_Mission022_C` in `Mission022_MiniGame` (with 70
`BP_MinigameAreaLanding_C` / 11 `BP_MinigameAerialControlVolume_C`). Sequence: land in the runway box ->
`MiniGameEnding` (0x9a) arg SeamlessIn -> in-game hangar (`ELiveHUDMode::IngameHangar`, UI_SHOP_SAVE.md) ->
`FinishInGameHangar` (0x9d) -> `ReturnFromHangar` (0x99) arg SeamlessOut or TakeOff -> takeoff roll leaves
`VolumeBox_LandingArea0`.
```
 149 TRIG RemainingBullets_50      life- 11 {0e NormalMissile} {0e Percent} {0f 50}
 182 TRIG RemainingBullets_20      life- 11 {0e NormalMissile} {0e Percent} {0f 15}
 183 TRIG RemainingBullets_0       life- 11 {0e NormalMissile} {0e Number}  {0f 0}
 194 TRIG Default_FinishInGameHangar life- 9d (no args)
 319 TRIG RemainingBullets_30_sp   life- 11 {0e SpecialWeapon1} {0e Percent} {0f 30}
 320 TRIG RemainingBullets_30_normal life- 11 {0e NormalMissile} {0e Percent} {0f 30}
 341 TRIG 01_BoxVolumeEvent_5      life- 40 {06 VolumeBox_LandingArea0} {0a NoneSelect} {0e Exit}  {0e LocalPlayer} {01 NoneSelect} {02 NoneSelect} {0a NoneSelect} {0e NoneSelect}
 371 TRIG RemainingBullets_30_sp_0 life- 11 {0e SpecialWeapon2} {0e Percent} {0f 30}
 683 TRIG 01_BoxVolumeEvent_6      life- 40 {06 VolumeBox_LandingArea1} ... {0e Enter} {0e LocalPlayer} ...
 836 TRIG RE_BaseSupplyMute        life- 4f
 907 TRIG Default_ReturnFromHangar   life- 99 {0e SeamlessOut} {0f 0}
 908 TRIG Default_ReturnFromHangar_1 life- 99 {0e TakeOff} {0f 0}
 910 TRIG Default_MiniGameEnding     life- 9a {0e SeamlessIn} {11 false} {0f 0} {11 false}
 960 TRIG Default_CompositeEvent_18 life- 2f mon=[RemainingBullets_30_normal, _30_sp, _30_sp_0]
```
Execs, stock order:
```
1392 01_BoxVolumeEvent_5 LiveRadioPlayExecution {0d 00_take_off_completion} {02 NoneSelect} {0a NoneSelect} {10 0} {11 false}x3   cond Bool_IsLanding True
1524-1526 RE_Bullet_50/20/0 LiveRadioPlayExecution ms22_Ammo_50 / ms22_Ammo_20 / ms22_Ammo_None; 1531-1533 deactivate their trigger
1527 01_Wave01_CheckDistanceEvent_AreaB LiveRadioPlayExecution {0d ms22_Supplypoint_1st} ...   (player within 12 km of the airport, once)
1528-1530 Default_FinishInGameHangar LiveSetActiveTriggerExecution {11 true} {08 RemainingBullets_50 / _20 / _0}
1534-1536 RemainingBullets_50/20/0 LiveCallRemoteEventExecution {0d RE_Bullet_50 / _20 / _0}
1879 Default_CompositeEvent_18 LiveCallRemoteEventExecution {0d RE_Bullet_30}  cond LiveInequality_FlagTimerStatement(Timer_supply_Interval Leq 0)
1880 RE_Bullet_30 LiveRadioPlayExecution {0d 00_Explanation_Seamless_3}   ("land to resupply" hint); 1881/1882/2006 deactivate the 30% triggers
1883/1884 Default_FinishInGameHangar LiveSetActiveTriggerExecution {11 true} {08 RemainingBullets_30_sp / _30_normal}
1941 Default_FinishInGameHangar LiveFlagOperation_BoolExecution {0c Bool_IsLanding} {0e Set} {11 true}
1942 01_BoxVolumeEvent_5 LiveFlagOperation_BoolExecution {0c Bool_IsLanding} {0e Set} {11 false}   cond Bool_IsLanding True
1943 Default_FinishInGameHangar LiveRadioPlayExecution {0d 00_permission_take_off} {02 NoneSelect} {0a NoneSelect} {10 0} {11 false}x3
2191 01_BoxVolumeEvent_5 LiveAIEngagementOrder EB_Unit_01_Air0 AttackOnly {0b Player} ... {0e PlayerOnly}
2192 Default_FinishInGameHangar LiveAIEngagementOrder EB_Unit_01_Air0 Normal, target {02 AB_Unit_01_Ground2}
2515 Default_FinishInGameHangar LiveStartTimerExecution {0c Timer_supply_Interval} {11 true} {11 false}   (LimitTime 150 s)
2633 01_BoxVolumeEvent_6 LiveAIEngagementOrder EB_Unit_01_Air0 Normal, target {02 AB_Unit_01_Ground2}
2735 Default_FinishInGameHangar LiveCallRemoteEventExecution {0d RE_Supply_WingmanMove}  cond Bool_WingmanRemove False  (wingmen: skip)
2737 01_BoxVolumeEvent_5 LiveCallRemoteEventExecution {0d RE_Supply_WingmanMove_Exit} cond (skip)
2957 Default_FinishInGameHangar LiveCallRemoteEventExecution {0d RE_BaseSupplyMute}
2958 RE_BaseSupplyMute LiveSetRadioMuteOptionsExecution {11 true} {0e None} {0d ms22_Supplypoint_1st} {0d ""}
2959-2962 RE_BaseSupplyMute LiveClearRadioQueueExecution {0e None} {0d ms22_Ammo_None / 00_Explanation_Seamless_3 / ms22_Ammo_20 / ms22_Ammo_50}
3166 Default_ReturnFromHangar LivePlayBGMWithPositionExecution {0d AKE_Bgm_Ms22A_TimeRestart_Play} {11 true} {10 0}  (loop -)
3167 Default_ReturnFromHangar LiveStopBGMExecution {0d AKE_Bgm_Ms22A_SupplyOut_Stop}
3174 Default_MiniGameEnding LiveEventBGMExecution {0d AKE_Bgm_Ms22A_SupplyIn_State}  (loop -)
(Default_ReturnFromHangar_1 / TakeOff has no execs.)
2099 Default_Campaign_ExterminationBattleSuccess (0x38) LiveSetTakeoffAndLandingEventExecution {11 false} {0f 0}
2786 RemainingTime_PlayByRadioStop (0x22, 73 s left)   LiveSetTakeoffAndLandingEventExecution {11 false} {0f 0}
```
M004 does the same toggling per phase (`_PhaseNNStart_MissionManager` false, `Default_PreRadioEvent_4` /
`_Phase08Start_MissionManager` true) and its `Default_MiniGameEnding` uses `{0e SeamlessOut} {11 true} {0f 1} {11 false}`.

### 3b. Does the stock flow refill or repair?
Not proven from data. Signs that it fully reloads: M22 turns its "ammo 50/20/0/30%" warnings off once they fire and
turns them back on at `FinishInGameHangar`, which only makes sense if the counts went back up. The hangar's Weapon1/2
pages re-pick special weapons, and the exe has `AKE_GEN_UI_INGAME_BaseResupply_*` / `AKE_GEN_UI_HUD_Notice_ResupplyMissiles_Play`.
Repair is unknown. So **apply Survival's ammo cap after `FinishInGameHangar`**: Lua watches HUD mode leaving
IngameHangar, or an EP `FinishInGameHangar` record sets an SV flag that Lua polls, then calls `SV_SetAmmo`
(AMMO.md). Test: log `SV_Ammo(k)` and the player's `GetHealth()` before landing and after takeoff.
`LiveSetWeaponAmmoCount` (M015) is a script import away (hash above) if an EP-side refill is preferred.

### 3c. Prompts available
- `LiveMessageExecution {0e <EHUDMessageType>}` (M22 has it: MISSION_ACCOMPLISHED / MISSION_FAILED). Useful values:
  `REQUEST_LANDING` (14), `CLEARED_FOR_TAKEOFF` (12), `LANDING_SUCCESSFUL` (15), `RETURN_TO_BASE` (39), `WARNING` (2),
  `DAMAGE` (35), `MISSION_UPDATE` (7), `WAVE_UPDATE` (8). "Airfield open" = REQUEST_LANDING or RETURN_TO_BASE at
  round clear, and WARNING when it closes.
- Radio (M22's table, already playable): `ms22_Supplypoint_1st`, `00_permission_take_off`, `00_take_off_completion`,
  `00_Explanation_Seamless_3`, `ms22_Ammo_50/_20/_None`.
- Radar ping on the airport: `LiveBattleNavigationExecution` (above).

### What Survival should add (landing + shop)
None of section 3's records are in `EP_SurvivalMode_global` (its 74 triggers / 221 execs are MissionStart,
SV_FlightUp/Down_NN, RE_SV_Chase*). Add, all from M22 templates (no new imports):
1. `Default_FinishInGameHangar` (0x9d) -> `SV_Landed` flag Set 1 (Lua: re-apply the cap / open the shop, then clear
   it), radio `00_permission_take_off`, `RE_BaseSupplyMute`-style queue clear.
2. `Default_MiniGameEnding` (SeamlessIn) and `Default_ReturnFromHangar` (SeamlessOut) + `_1` (TakeOff): supply music
   (BUILD_PLAN music item; M22 uses its own Ms22A states, so pick tracks to match Survival's music) and flags for Lua.
3. `01_BoxVolumeEvent_5` (exit LandingArea0) -> `00_take_off_completion` (guarded by an `SV_IsLanding` bool, as M22 does).
   Needs the bool flag type in build_ef (only int flags are written now), or an int flag with `LiveInequality_FlagIntStatement`.
4. `RE_SV_AirfieldClose/Open` (LiveSetTakeoffAndLandingEventExecution false/true) for AirfieldDown, called by Lua
   through a flag trigger (0x6b FlagInt, template M22's FlagInt triggers) since Lua can't fire remote events.
5. Optional `RemainingBullets` warnings with ms22_Ammo_* radio, re-armed on FinishInGameHangar (M22 1528-1536).

---------------------------------------------------------------------------------------------------------------------
## 4. Stronger defences and the CIWS (0.72.1)
User, 2026-10-29: "make Allied SAMs and Anti Air Guns more effective, increase their lock on range, also increase the
lifetime of the missile they fire, increase their abilities and Add CIWS that can be purchased and placed around the
airfield" ("fixed spots around the runway are fine"). Branch TestBranch_Behavioural, VERSION unchanged. **None of it has
run in game [I].** Offline: `sh tools/checks/defences_test.sh` (ALLY.setup on stub tables with the stock rows' numbers,
the STORE, the ALLIES row, losses, repairs, kill credit; then `defences_spots_check.py` on the spots).

### 4a. The AA guns and SAM sites (Scripts/sv_allies.lua ALLY.setup, CFG.shop.items.Airfield.defences.fcs)
Their weapons already had fire control of their own (`<FCS>_SVA_Defence` in DT_NPC_FCS, made at the main menu, set on
Survival's rows SV_Def_Gepa / SV_Def_Avng only, never on a stock row). The ships' mechanism (CFG.allies.ships.Aegis.fcs)
now runs for the key "Defence" too. Stock numbers from build/stock's DT_NPC_FCS / DT_NPC_Weapon / DT_NPC_AIModule:

| | stock | 0.72.0 | 0.72.1 (CFG key) |
|---|---|---|---|
| AA gun lock-on (NPC_FCS_VehicleAAGun000 CaptureDistance) | 2200 m | 3520 m (the allies' x1.6) | 4400 m (`range_x` 2.0) |
| AA gun flak: AAGUN_Ground_000 is an emitter whose damage is a cylinder `DamageAreaLengthMeters` x `DamageAreaRadiusMeters` (its LifeTime 3 s is the burst, not a reach) | 2000 x 20 m | the same: locked at 3.5 km, hurt only inside 2 km | 4400 x 30 m (`round_reach`, `round_width_x` 1.5) |
| SAM lock-on (NPC_FCS_VehicleSAM001) | 3000 m | 4800 m | 8000 m (`missile.range_m`) |
| SAM missile (SAM_Ground_000) | 7.3 s from 500 km/h, +300 km/h a second to 3000, turn 15, cloud 0.5: ~3.2 km straight | the same: shots past 3.2 km fell short | 14 s, +600 to 3600, turn 22.5, no cloud loss: ~11.8 km straight (`missile.life_s`, `accel_x`, `speed_max_kmph`, `turn_x`) |
| search (the FCS row's AI module, and the SV_Def_* rows') | GroundVehicle000 / Turret000: 6000 m, lost in cloud | the same | NPC_AIModule_SV_Defence (a Turret000 copy): 10000 m, not lost in cloud (`search_m`) |
| turret slew (YawSpeed / PitchSpeed) | 30 / 30 deg/s | the same | 60 / 60 (`slew_x` 2.0) |
| health (DT_NPC_Model MaxHealth 20; the row's MaxHealthDifference) | 20 | 20 | 60 (`aa.health_add`, `sam.health_add` 40; an enemy missile's damage is 40) |
| fire rate (arm, lock, between, rest; x0.5 x `lock_x` 0.75 / `fire_x` 0.5) | AA 0.5 / 2 / 2 / 1 s, SAM 2 / 5 / 5 / 10 s | AA 0.19 / 0.75 / 0.5 / 0.25, SAM 0.75 / 1.88 / 1.25 / 2.5 | kept |
| unit area (WD; turrets engage only inside it: the Aegis's 20 km missiles stopped at its 10 km) | 6 km, 500-6000 m | the same | 25 km, 0-15000 m (survival_events.DEFENCE_AREA_M / DEFENCE_ALT_M, build) |

`yaw_full` puts every defence's fire control all the way round (the AA guns' and SAM sites' already are; the CIWS's is
a ship mount's). The allies' cone (x1.5), spread (x0.4) and AA lead (x1.5: 0.8 -> 1.2 s) stay as they were. The Aegis's
own clones are unchanged (its `fcs` has no slew_x / yaw_full / round_reach); its log line now shows before -> after too.

### 4b. The CIWS
- **The model.** The game's land Phalanx, GR033_ciws: BP_GR033_ciws_Base (BP_AITurret_Pawn) carries one arms,
  LiveFCSModule_AIControlCIWS + LauncherBoneControl (TurretPoseableMesh, BN_turret_yaw -180..180 at 180 deg/s,
  BN_turret_pitch to 60) + ProjectileCommon (BP_wp_ciws_turret), with its own fire control in the bone control (2500 m,
  30 deg, arm 0.5 s, lock 2 s, 2-round bursts, 1 s between, rest 1 s). DT_NPC GR033_ciws_01 / _Megafloat name no
  NpcFCSId (Online Mode's GR033_ciws_01 and its Aegis Ashore CIWS neither). The game's DT_NPC_Model has a row
  **GR033_ciws_Ally** whose blueprint is BP_GR033_ciws_CP_Ally (no DT_NPC row of the game uses it): BP_GR033_ciws_CP with
  an ally's destruction (no extra effect, no induced explosion), as GR002_gepa_Ally is the Gepard's. Allied or not is the
  unit's Faction: Mission 22's own allied AA guns, SAM sites and Aegis turrets fly the plain blueprints with faction 1.
- **Where Mission 27 has it.** WD_Mission027_global EA_Unit_01_Ground_Ciws0 / EE_Unit_01_Ground_Ciws0: two AI objects
  each (not one), GR033_ciws_Megafloat (BP_GR033_ciws_CP_MS27, its own weapon BP_wp_ciws_Megafloat), on the Megafloat's
  deck 120 m up, Faction 2, tags Obj_NoLockOn / Obj_CiwsDestory. Not ported: an AI object desc carries nothing a land
  CIWS needs that Mission 22's allied airport objects lack (AIObjectClass none, no children, LevelId 200, the same cone),
  so Survival's are copies of its own allied AA gun unit.
- **Build** (tools/survival_events.py DEFENCE_CIWS*, build_survival.py ciws_units / build_npc_rows / build_npc_table):
  units SV_Unit_Ciws_A-D, objects SV_Obj_CiwsA-D, copies of SV_Unit_AAGun_A (move_object's copy of AB_Unit_01_Ground0:
  faction 1, TAG_Ground / TAG_GroundAlly, bIsLanding, a target box, the defences' area), on mission row sv_def_ciws (a
  copy of Mission 22's gepa_common) -> DT_SV_NpcRows SV_Def_Ciws, a copy of DT_NPC GR033_ciws_01 with ModelId
  GR033_ciws_Ally (the build checks that model row's blueprint in build/stock's DT_NPC_Model, now pulled by
  build_all.sh). AIObjectClass none, no children: the spawner loads the blueprint from the model row (hard rule 31).
- **Spots** (km along Mission 22's runway axis from its centre, + ENE; across it, + SSE; z 5 m like every airport
  object; facing along the runway, yaw -23):

  | unit | along, across | map (x, y) km | nearest airport object | off the axis | troops' drives |
  |---|---|---|---|---|---|
  | SV_Unit_Ciws_A (WSW end, north) | -0.70, -0.25 | 15.354, -4.314 | 291 m (dummy 0) | 250 m | 87 m |
  | SV_Unit_Ciws_B (WSW end, south) | -0.75, +0.25 | 15.503, -3.834 | 336 m (SAM site 0) | 250 m | 84 m |
  | SV_Unit_Ciws_C (ENE end, north) | +0.80, -0.17 | 16.766, -4.827 | 209 m (AA gun 2) | 170 m | 147 m |
  | SV_Unit_Ciws_D (ENE end, south) | +0.85, +0.20 | 16.956, -4.505 | 171 m (AA gun 3) | 200 m | 212 m |

  All 0.74-0.87 km from the airfield, 184 m or more from the scramble jets' taxi, inside the beaches the coast marks
  give (0.45-0.55 km off the axis by the runway's middle). The runway is 1.79 x 0.03 km (VolumeBox_LandingArea0), its
  approach box 98 m wide. The amphibious troops' drives (survival_events.lcac_craft) sweep both sides of the WSW half,
  so the WSW spots sit 250 m out. The terrain there was never traced [I].
- **Fire control: NpcFCSId0 = NPC_FCS_VesselCIWS000 (the ships' Mk 15's), boosted as the AA guns'.** Set at the main
  menu on Survival's SV_Def_Ciws (ALLY.setup, `ciws.fcs_row`; only when DT_NPC_FCS has the row), then cloned to
  NPC_FCS_VesselCIWS000_SVA_Defence by the same code. Why: GR033's arms is the Mk 15 blueprint's module trio
  (AIControlCIWS + LauncherBoneControl + ProjectileCommon), and the row's FCSBlueprintClass, BP_FCS_Vessel_CIWS_00, drives
  a TurretPoseableMesh's BN_turret_yaw / BN_turret_pitch, the very names GR033's base blueprint has; Survival's Aegis
  already fires its Mk 15 on a clone of this row; and only a row can be boosted and logged (the blueprint's own numbers
  live in its bone control). The row is a ship mount's (+-60 deg at 37.5 deg/s), so `yaw_full` / `slew_x` give the
  clone -180..180 at 75 deg/s. Its weapon CIWS_Vessel_000 is an interceptor too (InterceptDistance 2500 m, SearchType 1):
  it may shoot at missiles near it [I]. `fcs_row = none` leaves the blueprint's own (2500 m, not boosted) for an A/B.
  Numbers: lock-on 2500 -> 5000 m, rounds 3.0 -> 6.0 s of flight (x the range's growth), arm 0.5 -> 0.19 s, lock 3 ->
  1.12 s, 3 -> 0.75 s between, rest 1 -> 0.25 s, lead 0.8 -> 1.2 s, search 10 km, health 20 -> 60 (`ciws.health_add`).
- **STORE.** The AIRFIELD page had no row left, so the AA gun, SAM site and CIWS rows have a page of their own,
  **DEFENCES** (in-game menu 25: WBP_SV_StoreDefences / DA_SV_StoreDefencesSettings / DT_SV_StoreDefencesCommands; Lua
  SHOP.menuRows' sixth row SVStoreDefences): BUILD AA GUN, BUILD SAM SITE, BUILD CIWS, ALLIES >, TAKE OFF. AIRFIELD (21):
  REPAIR AIRCRAFT, REPAIR AIRFIELD, DEFENCES > ("25"), ALLIES >, TAKE OFF. CFG.shop.items.Ciws (role "ciws") ->
  Airfield.defences.ciws: 6000 Z, raise 1.12 (6000, 6720, 7530, 8430), its units built in order, ALL BUILT; NOT
  AVAILABLE while SV_Def_Ciws isn't in DT_NPC (ALLY.ciwsReady false). The old fourth row's turn order (no STORE pages)
  has the CIWS 4th, 8th, 10th and 11th. Icons: T_HUD_w_mgp_a0 (the CIWS), T_Icon_Radar_Gnd_000 (DEFENCES >).
- **The rest, as the AA guns and SAM sites:** the ALLIES row ("AA n  SAM n  CIWS n (hp %)", CIWS only once one is
  up), "CIWS LOST" when one goes, repairs between rounds and with the airfield (class BP_GR033_ciws_CP_Ally_C), kill
  credit "defences" (KILL.side: "GR033_ciws", never the ALICORN's alcn_ciws). Co-op: nothing of its own, as theirs
  (the host's SV_Spawn of a unit is mirrored to the joiners; each player's own STORE).

### 4c. Log lines to look for (a test's AC8SurvivalMode_lua.log)
- Main menu: `allies: the airfield defences' turrets search 10000 m (NPC_AIModule_SV_Defence, was 6000 m), not lost in
  cloud`; `allies: the CIWS's gun on NPC_FCS_VesselCIWS000: set (boosted below)`; `allies: the airfield's AA GUN +40 HP
  (SV_Def_Gepa's MaxHealthDifference now 40)` (SAM SITE, CIWS the same); `allies: the ships' and the airfield's own fire
  control: NPC_FCS_VesselCIWS000_SVA_Defence (within 2500 -> 5000 m, ..., yaw -60..60 at 37.5 -> -180..180 at 75.0
  deg/s, rounds CIWS_Vessel_000_SVA_Defence: 3.0 -> 6.0 s of flight), NPC_FCS_VehicleAAGun000_SVA_Defence (within 2200
  -> 4400 m, ..., rounds AAGUN_Ground_000_SVA_Defence: hurt out to 2000 -> 4400 m, 20 -> 30 m round),
  NPC_FCS_VehicleSAM001_SVA_Defence (within 3000 -> 8000 m, ..., missile SAM_Ground_000_SVA_Defence: 7.3 -> 14 s, up to
  3000 -> 3600 km/h, +300 -> +600 km/h a second, turns 15.0 -> 22.5)`; `allies: 8 of 8 rows in DT_NPC, WINGMEN in, CIWS
  in, ...`; `shop: store page SVStoreDefences: ...` and `shop: the store's pages in the in-game menu table: ...,
  SVStoreDefences at 25 (want 25)`.
- In a run: `shop: Ciws: CIWS BUILT for 6000 (SV_Unit_Ciws_A).`; `allies: CIWS (SV_Unit_Ciws_B) lost in round N`;
  `allies: N airfield defences repaired with the airfield`; `kills: ... went down to the defences (damage: ...
  defences N)`.

### 4d. Untested [I] (everything in game), what to look at
1. The DEFENCES page opens from AIRFIELD's DEFENCES > and its rows buy; the AIRFIELD page's 5 rows.
2. A CIWS spawns at each spot on the ground (not floating, not buried, not in the sea), allied (an ally's target
   box), and fires at enemy aircraft all the way round out to ~5 km; whether NpcFCSId0 on GR033 is honoured at all
   (else `fcs_row = none` for its own); whether it shoots down enemy missiles.
3. AA guns reach 4.4 km (flak bursts on targets out there, kills credited "defences"); SAM sites launch at 8 km and the
   missiles arrive; the 25 km unit area doesn't change what they pick.
4. 60 HP: a defence lasts two enemy missiles; the ALLIES row's % and the repairs read the new health right.
5. MOONCHILD's taxi and takeoff and the amphibious troops' drives go past the CIWS (A and B 84-87 m off two drives).
1. Does `MissedWeapon_V2` count hits on invincible dummies as well as misses? (M004 and M22 assume yes.) Does the first
   event get dropped (hard rule 6)?
2. Does the M22 strike AI (engagement target `AB_Unit_01_Ground2`, GROUND_ONLY) fire at the dummies when spawned by
   SV_Spawn far off-path, and does the chase leave it alone? Log MissedWeapon counts per round.
3. Can Lua write `LiveEventContainer.FlagData.IntegerFiled` values (repair / reset), or must a flag trigger do it?
4. Stock refill/repair amounts on landing (3b), and whether the hangar opens in Survival (UI_SHOP_SAVE.md).
5. `LiveUnitHealthDisplaySwitch` arg 4 (bool) meaning. It shows a whole unit's health: with invincible dummies the bar
   would never move, so it only fits the real-health option.
6. Can `dummy_common` take damage with `bIsInvincible` cleared (collision)? If not, use M013's `Runway` row (AddRow) or
   M22's `ControlCenter_common` (a visible building).
