# AC8 enemy unit data (DT_NPC_*) - research for Survival Mode (2026-10-22)

BUILD_PLAN research backlog item 2. All tables pulled with `tools/get_stock.sh` into `build/stock/Datatables/AI/NPC/`
(+ `OnlineMode/DataTables/AI/NPC/`). Scratch dumps in `build/research/ai/`: `dt.py <table> <RowStruct>` (any table),
`dt_npc.tsv` (all 1379 DT_NPC rows: LuaSet, rank, provoke, KDS, AI module, FCS, boss, score, display name, tweaks),
`aircraft.tsv` (333 aircraft rows joined with their model: HP, pitch/roll speed, max speed, accel, blueprint, stealth),
`mission_npc.tsv` (all 1723 rows of the 43 campaign mission tables, joined to DT_NPC), `dt_npc_on.tsv` (online).
Behaviour sets (LuaSet / LA_* scripts / pilot rank) are in `tools/re/AI_BEHAVIOURS.md`.

## The lookup chain
```
WD FLiveAIObjectDesc.MissionNpcID (FName, +0x14)            e.g. "m29a_common"   <- SV_SetAircraft sets this
  -> ULiveWorldData.NpcMissionDataTable (+0x110)            Survival: /Game/Datatables/AI/NPC/Mission/DT_NPC_Mission022
     row LiveNpcMissionDataTable                             per-mission overrides + NpcId
  -> /Game/Datatables/AI/NPC/DT_NPC  row LiveNpcDataTable    (global, 1379 rows; 333 have a LuaSet = aircraft)
     -> Model/DT_NPC_Model        LiveModelDataTable  blueprint, base HP, flight performance, stealth
     -> LuaSet/DT_NPC_LuaSet      LiveLuaSetDataTable behaviour tree slots (AI_BEHAVIOURS.md)
     -> Provoke/DT_NPC_Provoke, KDS/DT_NPC_KDS, SurroundPursuit/..., Cloud/..., AIModule/DT_NPC_AIModule
     -> FCS/DT_NPC_FCS (x6 ids)   LiveNpcFCSDataTable -> Weapon/DT_NPC_Weapon (LiveNpcWeaponDataTable)
     -> WeaponDurability, ExplosionDurability, Airframe/DT_NPC_Airframe_Skin, Pilot/DT_NPC_Pilot (pilot mesh only)
  + Difficulty/DT_NPC_Difficulty (one row per game difficulty, applied to every NPC)
```
The row structs come from each table's `RowStruct` import (`/Script/Live.<name>`); `ue.U.schema(<name>)` lists fields.

## LiveNpcMissionDataTable (DT_NPC_Mission###, 43 campaign tables, 1723 rows, 409 aircraft)
Fields: `NpcId` (DT_NPC row), `ProvokeId`, `KDSId`, `SurroundPursuitId`, `WeaponDurabilityId`, `AssaultRecordGroupID`
(enum), `TacName` (str: named-ace callsign, e.g. M022 e18g_Named "Alienus"), `bIsPreReplaceObject`,
`PostReplaceMissionId`, `bIsForcedReplacementWithFreeMission`, **`MaxHealthDifference`** (added HP; M006 lcac +180,
M010 allies -50/-65), **`MinHealth`** (1.0 on story allies = can't die), `bOverrideEnemySearchType` + `EnemySearchType`
(ELiveTargetType), `bOverrideTargetConstantDistance/NearDistance` (+ values; 274 rows carry TargetNearDistance 30),
`bOverrideKeepMinHeight` + `KeepMinHeight`, `bOverrideInducedExplosionParam` + `FallDownProbability, GunProbability,
NormalMissileProbability, ProbabilityMap<ELiveWeaponID,float>` (how a kill plays out, not firing), `bOverrideBailoutParam`
+ `BailoutLottery`, `bOverrideFinalExplosionTime` + `FinalExplosionTime`, `bOverrideMoveDecelerationParam` + 3 floats.
Tables: DT_NPC_Mission002..030, 025day1, 025day2, _Tr003.._Tr015. Online: 18 `DT_NPC_Mission_*_ON` (C/EA/EB/FM/PvPvE/TUT)
that point at `DT_NPC_ON` (a separate 2nd global table), not at DT_NPC.

## LiveNpcDataTable (DT_NPC) - the fields that matter
`ModelId, AirframeSkinId, ProvokeId, KDSId, SurroundPursuitId, CloudId, PilotId, **LuaSetId**, WeaponDurabilityId,
ExplosionDurabilityId, NpcAIModuleId, ChildNPCId[], ChildNPCComponentNames[], GameObjectDisplayName02` (callsign text
id, e.g. `ContainerEnemyCallsign_Name_Shadow99ndUT`), `SphereCollisionRadiusCoefficient`, `MaxHealthDifference`,
`Pitch/Roll/Yaw/SpeedNormal/Max/Min/Turn/Acceleration/Deceleration` **Difference** (added) and **Coefficient**
(multiplied), `BaseScore, GameObjectSubId, SuppliesID, bIsBoss, DamageRateToParent, NpcFCSId0..5, **PilotRank**`.
Naming: `OPxxxx_<type>_01` generic, `_Named` hidden named ace (rank 5, LuaSet 0400_CP), `_Shadow_NN` / `_Shark_NN`
/ `_Ventus_NN` / `_Queen` / `_Purple` named squadrons, `_Ally*`, `_MSnn` mission tweaks, `_PV_*` cutscene planes.
Ground/sea/building rows (1047) have no LuaSet.

## LiveModelDataTable (DT_NPC_Model) - base stats
`GameObjectDisplayName01, BriefingDisplayNameID, NpcHeliId, TakeOffPatternID, BlueprintClass` (soft class ref,
e.g. `/Game/Blueprints/Vehicle/AI/Plane/OP1021_su57/CP/BP_OP1021_su57_CP_Shadow`), `MaxHealth, PitchSpeed, RollSpeed,
YawSpeed, SpeedNormal, SpeedMax, SpeedMin, SpeedTurn, Acceleration, Deceleration, DamageRateToPlayerOnCollision,
EnemySearchType, StealthLevel, bNoChangedSomeParameterDifficultyTable, GameObjectId`. A Shadow/Named row usually has
its own model (own skin blueprint) with the same stats as the generic one.

## DT_NPC_Difficulty (LiveNpcDifficultyDataTable), rows C.Story / Easy / Normal / Hard / Ace
| row | PilotRankAddition | Pitch/Roll coef | hit sphere | blackout start max/min, exec max/min | MaxHealth, damage |
|---|---|---|---|---|---|
| C.Story (Casual) | -1 | 0.8 | 1.2 | 0/-3, +4/+2 | 1.0, 1.0 |
| Easy | -1 | 0.9 | 1.1 | +1/-2, +3/+1 | 1.0, 1.0 |
| Normal | 0 | 1.0 | 1.0 | +2/-1, +2/0 | 1.0, 1.0 |
| Hard | +1 | 1.1 | 0.9 | +3/0, +1/-1 | 1.0, 1.0 |
| Ace | +1 | 1.2 | 0.8 | +4/+1, 0/-2 | 1.0, 1.0 |
All: MissileNumberLimitPlane 2, NonPlane 2. NPC health does not scale with difficulty.

## Mission 22 rows Survival uses today (CFG.aircraft) - all PilotRank 3, NPID_00, NKID_00, NSPID_00
| row | DT_NPC row | LuaSet | HP | pitch / roll | max km/h | accel | weapons (FCS) |
|---|---|---|---|---|---|---|---|
| f16c_common | OP1022_f16c_01 | 0012_CP | 55 | 50 / 150 | 1870 | 80 | Flr, Gun, Msl |
| f18e_common | OP1032_f18e_Ally_MS22 | 0000_CP | 60 | 35 / 95 | 2400 | 170 | |
| f15e_common | OP1025_f15e_01 | 0021_CP | 88 | 40 / 100 | 2600 | 170 | |
| f14d_common | OP1023_f14d_01 | 0000_CP | 60 | 30 / 90 | 2400 | 70 | |
| m21b_common | OP1027_m21b_01 | 0012_CP | 46 | 50 / 140 | 1870 | 80 | |
| m29a_common | OP1020_m29a_01 | 0000_CP | 60 | 40 / 130 | 1870 | 90 | Flr000, Gun000, Msl002 |
| m31b_common | OP1029_m31b_01 | 0040_CP | 88 | 50 / 110 | 3000 | 500 | |
| su33_common | OP1030_su33_02 | 0023_CP | 65 | 60 / 160 (x0.8) | 2400 | 300 | |
| su34_common | OP1009_su34_01 | 0021_CP | 105 | 26 / 80 | 2600 | 90 | |
Also in M022 but unused: j39e_common (0012_CP), a10c_common (0031_CP), e767_common / sstb_common (1000, large),
f16c_orange, **e18g_Named "Alienus"** (rank 5, 0400_CP), plus ships/ground. Mission 22's table has 46 rows.
M022's f16c/j39e/m21b/m29a/m31b/f14d rows have EnemySearchType AIR_ONLY stored but `bOverrideEnemySearchType` false.

## What makes an enemy harder (in order of effect)
1. **LuaSet tier**: 0400_CP (aces) >> 0003_CP / 0023_CP / 0002_CP > 0021_CP / 0012_CP / 0000_CP > 0031_CP > 1000.
2. **PilotRank** 1..5 (+ difficulty -1/0/+1): weights good moves and flares (AI_BEHAVIOURS.md). Named = 5.
3. **Provoke** NPID_02 (60 deg cone, 2 s blackout) > NPID_01 (70, 3 s) > NPID_00 (85, 4 s).
4. **Airframe**: pitch/roll/accel and Coefficients: Shadow m29a x1.2, Shadow f14d and f14d_Named x1.3; f22a/f35c/su33
   generics x0.9/x0.8 (deliberately softened). Stealth 4-6 (f22a 5, f35c 6, su57 4, fa36 5, ea36 6).
5. **Weapons**: Shadow rows carry `PlaneGun_Shadow`, `PlaneMsl400/402` and specials (f22a Shadow `Plane4AAM001`, su57 Shadow
   `PlaneQAAM000`, f14d Shadow `PlaneLAAM001 + Msl300`, typn Shadow `PlaneLAAM002`, 10 rows `Plane2AAM000`); generics carry
   `PlaneFlr000, PlaneGun000, PlaneMsl000/002`. (Fire control itself = backlog item 3.)
6. **Health**: model MaxHealth (46 MiG-21 .. 115 Su-57, 110 F-22/A-10, Ladon 1200) + MaxHealthDifference.

## Rows worth adding (all in DT_NPC already; HP / LuaSet / rank / provoke)
- Tier 2 generics: OP1004_f15c_01 (70, 0021_CP), OP1028_su35_01 (65, 0023_CP), OP1011_typn_01 (60, 0002_CP),
  OP1014_rflm_01 (60, 0012_CP), OP1005_f22a_01 (110, 0003_CP, stealth 5, x0.9), OP1021_su57_01 (115, 0003_CP, st 4),
  OP1026_su47_01 (60, 0003_CP, x0.8), OP1006_f35c_01 (70, 0003_CP, st 6), OP1018_fa36_01 / OP1019_ea36_01 (0000_CP, st 5/6).
- Ace squadrons (0400_CP, NPID_02, rank 3 - raise with the rank lever): OP1027_m29a_Shadow_162..168 (x1.2),
  OP1023_f14d_Shadow_101..109 (x1.3), OP1021_su57_Shadow_24..28 (QAAM), OP1005_f22a_Shadow_96..99 (4AAM, KDS off),
  OP1011_typn_Shadow_32..39, OP1008_j39e_Shadow_121..127, OP1017_mr2k_Shadow_181..188, OP1025_f15e_Shadow_77/78,
  OP1026_su47_Shadow_144/145, OP1030_su33_Shadow_41..49, OP1029_m31b_Shadow_51..55 (0041_CP), OP1022_f16c_Shadow_151..159
  (rank 2: the weak Shadow), OP1004_f15c_Shark_01..04 and OP1028_su35_Ventus_01/02 (NPID_01).
- Named aces (rank 5, 0400_CP; TacName from their mission row): e18g Alienus (M022, already in Survival's table),
  m21b Tessera (M002/M009), mr2k Gigas (M002), a06e Crematio (M003), f18c Raia (M004), j39e Cyclone (M005), su25 Custos
  (M006), m31b Turbo (M007, LuaSet 0040_CP), e06b Diabolus (M008), m29a Judex (M010), f15c Cratera (M011), f14d Larus
  (M012), f18f Nimbus (M013), su47 Sicarius (M014), su33 Lupus (M016), f16c Currus (M017), f04e Avus (M018), f15j Curis
  (M019), f18e Aleator (M020), su35 Periodus (M021), rflm Caligo (M023), fa36 Cantrix / a10c Fulmen (M024), su34 Sabulum
  (M025day1), ea36 Silacrum / f15e Dubia (M025day2), f02a lucidus (M026), typn Stiria (M027), f35c Harmonia (M028),
  su57 Sophos (M029), f22a Tegimen (M030).
- Specials: OP0045_ladn_01 (Ladon, 1200 HP, 0031_CP), bombers OP0008_b01b_01 (130) / OP0011_tu95_01 (150) /
  OP0012_t160_01 (1000 set), X-40 OP1016_x40a_01 (300 HP, 0091, stealth 5).

## How Survival should use this
**Getting new rows**: `MissionNpcID` must name a row of the world data's NPC mission table (hard rule 15), and that row's
`NpcId` must be a DT_NPC row. Every row above already exists in DT_NPC, so only mission rows are needed:
- Preferred: build `/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission` in tools/build_survival.py = a copy of
  DT_NPC_Mission022 (same `LiveNpcMissionDataTable` struct) plus Survival rows (`sv_f22a`, `sv_su57_shadow`, ...), and
  point WD_SurvivalMode_global's `NpcMissionDataTable` import at it (Survival's own package; no stock table touched,
  no run-time AddRow). Per-row knobs Survival can set there: `ProvokeId`, `MaxHealthDifference`, `TacName`,
  `bOverrideEnemySearchType`=1 + AIR_ONLY (so the search no longer depends on the event exec).
- Alternative without a rebuild: AddRow into the loaded DT_NPC_Mission022 from a DT_SV_ table (the menu-row pattern).
- New airframes load their blueprint through the model's soft `BlueprintClass`; test 11 only proved types Mission 22
  already lists. Test one off-mission type (su57) before relying on it (hard rule 7 may apply).

**Per-round tiers** (rank via the PilotRank lever in AI_BEHAVIOURS.md; HP via row MaxHealthDifference):
| tier | rounds | row pool | rank | HP diff | notes |
|---|---|---|---|---|---|
| T1 | 1-2 | f16c, m21b, j39e, a10c, su25-type generics | 2 | 0 | small HP (46-60) |
| T2 | 3-4 | today's CFG.aircraft (M022 commons) | 3 | 0 | |
| T3 | 6-9 | + f15c, su35, typn, rflm, f22a_01, su57_01 | 4 | +10 | stealth types appear |
| T4 | 11-14 | T3 + 1 flight in 3 from Shark/Ventus/Shadow rows | 5 | +20 | ace weapons appear |
| T5 | 15+ | Shadows mixed in, Named aces as flight leads | 5 | +20..40 | |
| special 5/10/15... | | one Shadow squadron (2 flights) + Named lead from round 10 | 4-5 | +0..20 | radio callout uses the squadron callsign |
Presets: Casual keeps T1-T2 rows longer (Casual already gets rank -1), Ace starts at T2 and moves a tier every 3 rounds.
Count (CFG.flights_*) and HP are the levers that still scale on Ace difficulty, where rank is already capped.

## Open questions
1. Does `ProvokeId` / `KDSId` / `SurroundPursuitId` in the mission row override the DT_NPC row's? (57 rows differ.)
2. Does an aircraft type that no stock Mission 22 asset references spawn (soft blueprint load), or does it need imports?
3. Does Survival's own NPC mission table load when the WD import is repointed (it is imported only by the WD)?
4. Online rows (DT_NPC_ON: `_01.._05` rank ladders, 02xx corps, `_40` aces) are in a separate global table; can a
   campaign world data reach them at all?
5. `MaxHealthDifference` on the mission row vs the DT_NPC row: are both added?
