# AC8 AI behaviour sets (LA_* scripts) - research for Survival Mode (2026-10-22)

BUILD_PLAN research backlog item 1. Sources: the 248 packages in `/Game/LuaSource/Chronicle/AI`, the tables in
`/Game/Datatables/AI/NPC` (+ `OnlineMode/DataTables/AI/NPC`), the stock event packages. Not tested in game yet.
Scratch output (regenerate with the scripts in the same folder): `build/research/ai/` -
`lua/Chronicle/AI/*.lua` (all 248 scripts as text), `luaset.txt` / `luaset_on.txt` (LuaSet rows resolved),
`features.txt` (maneuver counts per script), `ep_rank.txt` (every PilotRank / EnemySearchType exec in 14 missions).

## What the LA_ packages are
Each is a `LuaScript` asset (class `/Script/LuaPluginRuntime.LuaScript`) holding plain Lua **source** (not bytecode),
from `AssetWork/LuaSource/Chronicle/AI/LA_x.lua`, module `Chronicle.AI.LA_x`. Payload = 4 zero bytes, 6 header bytes,
then the source as a length-prefixed string (`build/research/ai/extract_lua.py` pulls it out). Every script builds a
behaviour tree through the native `CppObjectBase` API:
`AddRootComposite / AddComposite / AddDecorator / AddTask / AddProbability` with node factories such as
`InstanceSelector, InstanceSequencer, InstanceLaxSequencer, InstanceRandomSelect, InstanceWeightProbability(w),
InstanceWeightProbabilityPilotRank(w1..w5), InstanceDecoratorBlackboardFloat/Enum("PursuerDistance"|"AIState"|"AIAlert",...),
InstanceRunBehavior("<slot>"), InstanceManeuver{Level,Pitch,Roll,TurnNormal,TurnQuick,TurnAdvanced,FlyStraight,
BarrelRoll,FrontCross,CobraTurn,Kulbit,PugachevsCobra,Slalom}, InstanceActivateFlares, InstancePursuerTarget(...),
InstanceMoveAwayFromTarget, InstanceSetStateEscapeFromPursuer, InstanceDecoratorIsKDSP1/2, InstanceDecoratorCanCobra/CanKulbit`.
Distances are UE cm (100000 = 1 km).

### Root tree (LA_AIPlane) and the behaviour slots
`LA_AIPlane` is the root of every enemy plane (wingmen use `LA_AIWingmanPlane`). It switches on the blackboard
`AIState` (enum `ELiveAIState`: 0 ReturnToWorld, 1 AvoidObstacle, 2 AvoidRangeAttack, 3 Wingman, 4 ReturnToUnit,
5 AttackAvoidance, 6 EscapeFromPursuer, 7 Blackout, 8 Provoke, 9 MoveAwayFromTarget, 10 PursueTarget,
11 FollowFormation, 12 Group, 13 Patrol, 14 UniqueAction, 15 CloudAvoidance, 16 Idle). States 5-10, 14, 15 run a
named slot with `InstanceRunBehavior`; the slot is filled per aircraft from its **LuaSet** row
(`DT_NPC_LuaSet`, row struct `LiveLuaSetDataTable { LuaAsetts: LiveLuaAssets }`, 15 `LiveLuaAsset{LuaScript}` fields):

| LiveLuaAssets field | slot / when it runs | LA_ family used |
|---|---|---|
| RootLua | root | LA_AIPlane |
| EvadeLua | AttackAvoidance dispatcher: on AIAlert SpecialWeapon -> EvadeSpecial; Missile -> Near (<=1 km) / Far; Gun <=800 m -> EvadeGun, else SetEscapeFromPursuer | AttackAvoidance_0000 / _0000_CP / _0400 / _1000 |
| EvadeMissileNearLua | missile inside 1 km | AttackAvoidance_xxxx_msl_s |
| EvadeMissileFarLua | missile beyond 1 km | AttackAvoidance_xxxx_msl_m |
| EvadeGunLua | being gunned | AttackAvoidance_xxxx_gun |
| EvadeSpecialLua | special weapon (SPW) inbound | AttackAvoidance_xxxx_spw (or a msl_m) |
| BlackoutLua | Blackout state (G-LOC pause after hard turns; DT_NPC_Provoke) | Blackout_0000 (fly level 10 s) / Blackout_1000 |
| CloudAvoidanceLua | unused (always None) | CloudAvoidance_0000 exists |
| ProvokeLua | "Provoke" = a pursuer sits in the rear cone: picks Near/Mid/Far by PursuerDistance | Provoke_0000 / _0000_CP / _0091 / _1000 |
| ProvokeNear/Mid/FarLua | defensive moves when tailed (CP sets: <=1.5 km / <=10 km / beyond) | Provoke_xxxx_s / _m / _l |
| EscapeFromPursuerLua | break away from a pursuer | EscapeFromPursuer_xxxx |
| MoveAwayFromTargetLua | extend away after an attack pass, then re-engage | MoveAwayFromTarget_xxxx |
| PursueTargetLua | attacking: pursue the target into gun/missile position | PursueTarget_xxxx |

Suffixes: `_s/_m/_l` = short/mid/long (Provoke distance band; `msl_s`/`msl_m` = missile near/far), `_gun`, `_spw`.
`_CP` = the campaign-tuned variant (the dispatcher adds a 0.7 s straight-line "reaction delay" before each evasion,
the provoke bands are 1.5 km / 10 km instead of 100 m / 200 m). Online sets have no `_CP` and no Blackout.

## Families and variants (248 scripts)
AttackAvoidance 117, Provoke 74, PursueTarget 11, EscapeFromPursuer 10, MoveAwayFromTarget 6, Blackout 2,
CloudAvoidance 1, plus wingman (`AIWingmanPlane, Wingman_0000, WingmanAcrobat/DistributedAttack/ForwardAttack/Support,
WingmanUniqueActionInviting/Pushing, UniqueAction*Recipient`) and one-off **unique actions** (below).
Behaviour-ID numbers present: AttackAvoidance 0000-0004, 0010, 0011-0013, 0021-0024, 0030-0033, 0041-0042,
0051-0053, 0091, 0201, 0210-0211, 0221, 0251-0252, 0400, 0430, 0999, 1000; Provoke adds 0014, 0200, 9001, 9999.

## The 4-digit behaviour ID (decoded from which rows use which set)
`NLID_ABCD` in DT_NPC_LuaSet; the scripts carry the same number. Reading: **AB = tier, C = role class, D = grade**.

| ID | who uses it (DT_NPC campaign rows) | character |
|---|---|---|
| 0000(_CP) | multirole/carrier fighters: f02a, f18c/f/e, e18g, fa36, ea36, m29a, f14d, e06b; 602nd (rank 1) | baseline. Missile evade: weak 100/97/90/85/80 %, flare branch 0/3/10/15/20 % by rank |
| 0001(_CP) | drones/UAVs (mq9b, sv11, uavc/s/n...) | evade 70->30 % weak, 30->40 % normal |
| 0002_CP | Typhoon | like 0000_CP with its own msl near/far |
| 0003_CP | 5th gen: f22a, f35c, su57, su47 (_01 rows) | own msl near/far |
| 001D | light fighters: mr2k (0011), j39e/rflm/f16c/m21b (0012), 0013 unused in campaign; 0014 = AV-8B (Harrier) | grade D raises maneuver pitch angles: 0011 20/15 deg, 0012 25/20, 0013 30/25 |
| 002D | heavy fighters/strike: f04e, f15c, su34, f15j, f15e (0021), su35/su33 (0023) | 4 flare branches in msl evasion, no barrel rolls |
| 003D | attackers: a10c, su25, Ladon (0031) | flare-heavy, slow |
| 004D | interceptor: m31b (0040_CP), m31b Shadow squadron (0041_CP) | few branches, straight-line speed |
| 005D | not used in campaign; online f22a bots (0053) | gun evasion with cobra/kulbit/Pugachev |
| 0091-0093 | X-40 "Selene" boss (0091 rank 2, NPID_91 = no blackout) | custom weights 20/79/1 -> 35/60/5 |
| 02CD | online named corps (Astro, Reptile, Celestial, Hydra, Marionette): 0201/0210/0211/0220/0221/0250-0252 | AttackAvoidance_0201 dispatcher; not in the campaign LuaSet table |
| 0400(_CP) | **aces**: every `_Named` row (rank 5) and every Shadow / Shark / Ventus / Queen squadron | evade weak 50->10 %, strong 50->90 %, flares 0->30 %; gun evasion with cobra/kulbit; pursue with KDS phases |
| 0430 / 0460 | online variants of 0400 (0430: 8 flares in msl_s) | |
| 1000 | large aircraft: bombers, tankers, AWACS, transports, airships, cruise missiles | Blackout_1000, no real evasion |
| 0999, 0010, 0030, 0004, 9001/9999 | leftovers / test sets (0010/0030: 11 and 7 flare branches; 9999 Provoke = stage-boss tests) | not referenced by any row |

The numbers asked about: **0000** baseline fighter, **0011** light fighter grade 1, **0041** Shadow-squadron interceptor
(m31b), **0211** online named corps light (Astro-type f02a/j39e/m29a/f16c bots), **0400** ace, **1000** large/no-evasion.

## Pilot rank (the skill axis inside every set)
- `InstanceWeightProbabilityPilotRank(r1, r2, r3, r4, r5)` (430 uses) weights a branch by the pilot's rank 1..5.
  Typical missile evasion (0011..0051 msl_s): Weak 100/95/85/70/55, Normal 0/5/15/25/35, Flares 0/0/1/5/10.
  Ace set (0400_CP msl_s): Weak 50/40/30/20/10, Normal 50/60/70/80/90, Flares 0/0/10/20/30.
  So rank changes *how often* a pilot picks good moves; the LuaSet decides *which* moves exist.
- `DT_NPC.PilotRank` (int): 3 for almost every row (1316 of 1379); 5 for all 31 `_Named` aces; 1 for a06e, mr2k,
  602nd fa36 (weak); 2 for x40a and f16c Shadow-150; 4 for uavn. Online has `_01.._05` rows = ranks 1..5.
- `DT_NPC_Difficulty` adds `PilotRankAddition` per game difficulty: Casual -1, Easy -1, Normal 0, Hard +1, Ace +1
  (also pitch/roll x0.8..x1.2, hit sphere x1.2..x0.8, blackout timing; MaxHealth/damage 1.0 everywhere).
- Runtime: `ALiveAIGameObject.PilotRank` is a reflected `int` property (index 50 in usmap), so UE4SS Lua can read and
  write it on a spawned plane. Whether a write is picked up live is untested (the event node below does it in-mission).

### LiveAIChangePilotRankExecution (stock use: M002, M006, M007, M009, M019, M021, M024, M025_2, M028, M029)
Args (ep_dump types): `01` AI object | `02` unit | `0a` tag (one of the three, others `NoneSelect`) | `0f` int rank |
`11` bool relative. Examples:
- M009 Shadows: `Shadows_Attack_Start` sets 2 (absolute) on `E03_Unit_Ace_Air_1..4`, `Default_PostRadioEvent_19`
  sets 5, `Shadows_AI_Level_Down` -1 relative once 9 aces are down (flag `Phase03_Ace_Destroy >= 9` false branch).
- M021: `f14d_start` +100 relative (max out) then `Default_UnitDamage_50` -100 relative when the ace is hurt.
- M025_2: Shadows typhoon/su47/rafale 4 or 5 absolute on appearance; M028 `Appearance_Shadow_0` +1 relative.
- M002 / M006: rank 1-2 absolute only when `LiveIsAchievedDifficultyConditionStatement(Normal, Leq)` (easier on low difficulty).
Ranks 0 and +-100 appear, so the game clamps (range presumably 1..5; 0 = weakest; open question).

### LiveAIChangeEnemySearchType (M004, M006, M009, M010, M020, M022, M024, M025_2)
Args `01` object | `02` unit | `0a` tag | `0e` `ELiveTargetType` = AIR_AND_GROUND / AIR_ONLY / GROUND_ONLY / SPECIAL_ONLY.
Mission 22 sets AIR_ONLY on every `ERA_Unit_*_Dep_Air*` flight on appearance; Survival already copies that exec
(tools/survival_events.py `t_search`). Mission rows can also force it (`bOverrideEnemySearchType` + `EnemySearchType`).

## Other per-plane AI data
- **Provoke** (`DT_NPC_Provoke`, `LiveProvokeDataTable`): `NPID_00` cone 85 deg, blackout exec 4 s; `NPID_01` 70 deg / 3 s
  (named squadrons, allies); `NPID_02` 60 deg / 2 s (Shadow squadrons); `NPID_91` 60 deg, no blackout (X-40).
  All: DeterminationTime 2.5 s, BlackoutStartTime 6 s. Narrower cone + shorter blackout = harder to pin and keep pinned.
- **KDS** (`DT_NPC_KDS`, `LiveKDSDataTable`): `NKID_00` enabled (SelectionTimeLimit 1.5, FrontEntrance 24, FrontLead 12);
  `NKID_99` disabled (only the M21 f22a Shadows). PursueTarget scripts branch on `IsKDSP1/IsKDSP2` (KDS phases).
- **SurroundPursuit** `NSPID_00` 100-300 m, reset 8-20 s; **AIModule** `NPC_AIModule_Plane000` search radius 6000,
  loses targets in cloud (0.5 s / 0.8 s); Plane001 30000 without cloud loss; Plane002 12000.
- Reflected per-plane fields UE4SS can poke after spawn (all untested at run time): `ALiveAIGameObject.PilotRank,
  bPermissionToEngage/Fire/UseFlares/Provoke/Evade, bCanActivateFlares, MaxHealth`; `ALiveAIPlane.ProvokeConditionConeAngle,
  ProvokeDeterminationTime, SurroundPursuitMin/MaxRange, bCanManeuverPugachevsCobra, bCanManeuverKulbit,
  bEnableKDSMode, KDSSelectionTimeLimit, OverrideMaxSpeed, OverrideNormalSpeed`.

## Unique actions ("ace moves")
`DT_UniqueActionListTable` (`/Game/Datatables/AI/DataInstance/Behavior/`, row `LiveAIUniqueActionLuaTable`), 20 rows:
AIAS, BarrierCharge, Ladon_Kulbit, Ladon_Roll, LastTGT, ms02_mig21_Slalom_L/R, NightmareUAV_ApproachAndDocking/_UnDock,
Recipient_Inviting/Pushing, Shadow_Kulbit, Tasha_Cobra, Tasha_Roll, Toprak_Kulbit, UAVCharge_PitchDown/Up,
Wingman_DisturbAcrobat/Inviting/Pushing. Run by **LiveAIRequestUniqueAction** (12 missions), stopped by
**LiveAIResetUniqueAction**. Request args: `01` object | `02` unit | `0d` "" | `0d` action row | `0e` Always/OneShot |
`0e` Below_Return/UseWingman | `01` target | `11` bool. Reset args: object | unit | `0d` "" | `11` bool.
Stock patterns: M002/M006 `EnemyBehind_LastTGT` (named ace turns on the player and pursues it for 2 x 10 s, reset after
30 s); M028 `03_Shadow_N_Kulbit_0` (Shadow su57 kulbit, OneShot); M019/M028 `Toprak_Kulbit` on a missed weapon;
M016 Ladon_Kulbit / Ladon_Roll from volume events. `LA_Shadow_Kulbit` = 0.5 s straight, sound, kulbit firing WN_WEAPON_4.

## How Survival should use this
Three independent levers, cheapest first:
1. **Which row (= which LuaSet + rank + Provoke + weapons)**: `SV_SetAircraft` already picks the row before spawning.
   Behaviour tier follows the row (NPC_DATA.md lists rows per tier). No new code, only new rows in Survival's NPC table.
2. **Pilot rank per flight**: Lua writes `PilotRank` on each AI object after `SV_Spawn` (needs a test that it sticks and
   changes behaviour), fallback the stock node: clone M009's `LiveAIChangePilotRankExecution` into survival_events.py
   (args unit=`ERA_Unit_NN_Dep_AirK`, `0f`=rank, `11`=false) and fire it from `SV_Up_NN` with a per-round rank flag,
   or one exec per rank value gated by `LiveInequality_FlagIntStatement` on a round-tier int flag.
3. **Ace moves on special rounds**: `LiveAIRequestUniqueAction` LastTGT on the ace when the player gets behind it
   (copy M006 `EnemyBehind_LastTGT` + its reset), Shadow_Kulbit / Toprak_Kulbit on su57 aces.

Proposed escalation (rank values are before the game's difficulty addition; Ace difficulty already adds +1, so the
preset presets should also scale count/health, see NPC_DATA.md):

| rounds | rows (see NPC_DATA.md) | PilotRank | Provoke | extra |
|---|---|---|---|---|
| 1-2 | light/attack only: f16c, m21b, j39e, a10c, su25 (0012_CP / 0031_CP) | 2 | NPID_00 | |
| 3-4 | full Mission 22 mix (CFG.aircraft today) | 3 (stock) | NPID_00 | |
| 5 (special) | ace squadron: 4 x one Shadow type (e.g. m29a Shadow-160, 0400_CP, coef 1.2, Msl400) | 3 | NPID_02 | LastTGT on the leader |
| 6-9 | + f15c, su35, typn, rflm, f22a/su57 `_01` (0021/0023/0002/0012/0003_CP) | 4 | NPID_00 -> 01 | +10 HP rows |
| 10 (special) | Shadow squadron with specials (f14d Shadow-100 coef 1.3 / su57 Shadow QAAM) + 1 Named lead | 4, lead 5 | NPID_02 | Shadow_Kulbit |
| 11-14 | 1 flight in 3 from ace rows (f15c Shark, su35 Ventus, Shadow rows) | 5 | NPID_01/02 | +20 HP rows |
| 15+ | ace rows mixed in every round; specials = Named aces (rank 5) + Shadows | 5 | NPID_02 | rank +1 relative for the last flight alive |

"Ace learns from your fights" (Milestone 6): pick counters by giving the ace a custom LuaSet row: missile-heavy player
-> flare-heavy msl sets (AttackAvoidance_0010/0030 msl_*: 11 / 7 flare branches, 0430_msl_s 8); gun-heavy player
-> gun sets with cobra/kulbit/Pugachev (0051-0053_gun, 0091_gun, 0400_gun, 0000_CP_gun); tail-chaser -> Provoke_0430_m
(7 flare branches) and NPID_02. A new LuaSet row + DT_NPC row have to be added at run time (AddRow into the loaded
stock tables, never a file override) - see open questions.

## Open questions
1. Does a Lua write to `PilotRank` (or ProvokeConditionConeAngle etc.) on a live plane change its choices? Test: spawn a
   flight, log PilotRank, set 5, watch flare use. The event node is the proven path.
2. Exact clamp of rank (0..5? 1..5?) and whether DT_NPC_Difficulty's PilotRankAddition is added before the clamp.
3. Is the mission row's ProvokeId/KDSId/SurroundPursuitId an override of the DT_NPC row's? (57 mission rows differ,
   e.g. M004 m29a_Shadows mission NPID_00 vs DT_NPC NPID_02.)
4. Can rows added at run time to DT_NPC_LuaSet / DT_NPC (AddRow) be used, or does the AI cache the tables at load?
   Online-only sets (02xx, 0430, 0460 in DT_NPC_LuaSet_ON) would need that.
5. KDS: what the two KDS phases are in play (likely a front-approach / lead-pursuit dogfight mode); NKID_99 turns it off.
6. `InstanceWeightProbabilityAILevel` (9 uses, only in unassigned sets 0001_gun, 0030_*): which level it reads.
7. LiveAIChangePilotRankExecution's Execute was not located with tools/re/execvt.py ("not found").
