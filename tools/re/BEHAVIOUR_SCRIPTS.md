# AC8 behaviour scripts (LA_*.lua): grammar, factories, blackboard, patterns (2026-10-22)

Survey of the 248 stock behaviour scripts (`build/research/ai/lua/Chronicle/AI/*.lua`; the 536 files = these 248 +
288 under `fw/`, of which 248 are the same scripts with other line endings and 40 are DefaultLua/DevelopmentLua)
plus `fw/DevelopmentLua/LA_FrontCrossTest.lua`. Read with AI_BEHAVIOURS.md (slots, sets, IDs, pilot rank) and
AGENTS.md rules 20-22. **Everything here comes from the scripts.** The native code behind the factories is being
disassembled separately; where this file says *inference* or *[guess]* it is a reading of usage patterns, nothing more.
Evidence tags used below: **[name]** = the stock node names say so (e.g. `PitchUp20` over `ManeuverPitch(1.0, 20.0, ...)`),
**[usage]** = a consistent pattern across scripts, **[guess]** = weak inference.

Scripts and outputs: `build/research/ai/survey/` (`python build/research/ai/survey/run_all.py` regenerates all):

| script | output | what |
|---|---|---|
| parse.py | out/parse_check.txt | parser + tree model (library for the others); checks every line parses |
| grammar.py | out/grammar.txt | parent/child rules, counts |
| factories.py + meanings.py | **factories.tsv**, out/factories.txt | per factory, per argument: types, values, CP vs non-CP, meaning |
| blackboard.py | out/blackboard.txt | decorator keys/values/ops per slot, actor keys, RunBehavior names, all enums |
| trees.py | out/trees/<script>.txt, out/trees_all.txt, out/shapes.txt | every tree indented, with the sets/slots using it |
| variation.py | out/variation_same_shape.txt, out/variation_features.txt | same slot across IDs: aligned argument diffs, feature rows |
| pursuer.py | out/pursuer_target.txt | all 59 PursuerTarget calls with their gates + co-occurrence tables |
| setcompare.py | out/set_compare.txt | NLID_0012_CP vs NLID_0400_CP slot by slot (any two sets: `setcompare.py A B`) |
| shapecheck.py | (stdout) | `python shapecheck.py my.lua`: flags any factory/argument-type or parent/child combination no stock script uses |

## 0. Key findings

- The scripts are machine-written (one statement per line, auto-numbered names like `WeightProbabilityPilotRank_11`,
  editor float artefacts like `179.899994`), so the grammar is small and strict: 249 scripts, 13 815 nodes, zero
  parse exceptions, every file in DFS pre-order, every name unique inside its script.
- A tree is built with five calls. `AddRootComposite(name, composite)` once, then `AddX(parentName, newName, factory)`.
  The parent is referenced by the **string name** given earlier. Decorators are **nodes** with exactly one child
  (599/599). `AddProbability` only ever hangs off a `RandomSelect` (1304/1304) and has one child (or none at weight 0).
- 63 of the 80 registered `Instance*` factories occur (list of the 17 unused in 1.4). Arguments are positional
  literals only: number, string, bool, `Enum.Member`, `FVector.New(x, y, z)`. Eleven factories vary in argument count:
  ten by one optional last argument (Level 7/8, TurnNormal 9/10, MoveAwayFromTarget 3/4 ...), Kulbit 2 or 7.
- Units: blackboard `PursuerDistance` is in **cm** ([name] `BlackboardFloat_Level_1000mUnder` = 100000.0).
  Maneuver durations are **seconds** ([name] `WeightProbability_Turn_3sec` over turns of duration 3.0; Blackout = 10 s level).
  Speeds: `SpdConstant` absolute 300..4000 (rookies 900-1300, aces 3000-4000), `SpdRelative` an offset from the
  reference actor's speed (-600..+3000), `SpdCruise` 15..350 (mostly 100: a percent of cruise *[guess]*).
- **PursuerTarget** (59 uses, always 17 args): arg1 = time limit s; arg2 = target key; arg3 = a 1..100 "intensity" that
  tracks tier (rookies 1-3, aces 10, scripted unique actions 100); arg4 = true in every KDS phase-1 pursuit;
  arg11+arg12+arg13 = (true, 45, 2400) marks the "tracking" pursuit, (false, 60, 3000) the default, (false, 0, 0) the
  four pursuits of online 0000, the KDS pursuits of 0200/0400/0430 and the ace move-away re-attacks; arg16 = true only in scripted pursuits of the player; arg17 = an offset in the target's frame,
  (-400, 0, 5) in 50 of 59 calls (behind the target), positive X = in front (wingman "Inviting" 1500/1800).
- **Ace pursuit (PursueTarget_0400) vs Survival's fighters (PursueTarget_0011)**: the ace script never calls
  `SetMoveAwayFromTarget`, so it never leaves the pursue state by itself; it cycles 6-8 s pursuits with arg3 = 10,
  arg5 = 1500 and the tracking tuple, then a 5 s straight and a 2-3 s break turn, and repeats. Its MoveAway slot
  (MoveAwayFromTarget_0000) is two more pursuits, not an extend. But every pursuit in 0400 is gated by
  `IsKDSP1`/`IsKDSP2`/`IsTrackingAirTarget`, which is why AGENTS rule 22 saw aces fly around without attacking outside KDS.
  0011's main pursuit is gated only by `PursuerDistance >= 2000` (20 m) and is followed by `SetMoveAwayFromTarget`.
- Designers tune by: speed (SpdConstant 1000 -> 3000), shorter durations (rookie 2-5 s, ace 0.2-2.5 s), pull/G
  (TurnNormal arg1 1.0 -> 3.5), heading change angles (+5 deg per grade inside one ID family, e.g. 0011/0012/0013),
  PilotRank weight columns, and by swapping in post-stall/flare branches. Structure changes by tier, numbers by grade.

## 1. Grammar

### 1.1 File shape (all 249 scripts)
```lua
local LA_X = Inherit(CppObjectBase)          -- local class table; the name does not have to match the file
function LA_X:Ctor()
self:GenerateBehavior()
self:AddRootComposite("<root>", self:Instance<Composite>())
self:Add<Composite|Decorator|Task|Probability>("<parent>", "<name>", self:Instance<Factory>(<literal args>))
...                                           -- one call per line, parents before children (DFS pre-order)
self:EndGenerateBehavior()
end
return LA_X
```
Two stock files use another class name (`LA_AttackAvoidance_0042_CP_gun` declares `LA_AttackAvoidance_0041_gun`;
`LA_MoveAwayFromTarget_0000` declares `aw_moveaway_000` and is used by 14 sets), so only the returned table matters.
No stock script has comments, locals, loops, conditionals or helper functions; `Ctor` is the only method.

### 1.2 The five calls

| call | args | adds | count |
|---|---|---|---|
| `AddRootComposite(name, comp)` | node name, composite factory | the root; first call after GenerateBehavior; exactly one | 249 |
| `AddComposite(parent, name, comp)` | parent name, node name, composite factory | a composite under parent | 3934 |
| `AddDecorator(parent, name, deco)` | parent name, node name, `InstanceDecorator*` | a gate node under parent; its single child is added next with `parent = name` | 599 |
| `AddTask(parent, name, task)` | parent name, node name, task factory | a leaf | 7729 |
| `AddProbability(parent, name, prob)` | RandomSelect name, node name, `InstanceWeightProbability*` | a weighted branch of a RandomSelect; its single child is added next with `parent = name` | 1304 |

Method and factory kind always agree (no AddTask with a composite etc.). The parent string must be the name of a node
added earlier in the same script; node names are free labels (the wingman root even names an AvoidRangeAttack gate
`StateIsReturnToUnitCircle_1`), unique per script, reusable across scripts; 573 nodes simply reuse the factory's name.

### 1.3 Tree rules (counted)

| rule | stock evidence |
|---|---|
| Root is a composite | LaxSequencer 144, RandomSelect 65, Sequencer 14, LaxSelector 12, Selector 10, LaxContinuation 2, Continuation 2 |
| Tasks are leaves | 0 tasks with children |
| A decorator wraps exactly one child (composite 504, task 95) | 599/599; never decorator-under-decorator (0 chains) |
| Decorator parents | RandomSelect 376, Selector 120, WeightProbability 43, LaxSequencer 31, LaxSelector 23, Sequencer 3, LaxContinuation 2, Continuation 1; never Parallel |
| Probabilities only under RandomSelect | 1304/1304 |
| A probability has one child (composite 1239, decorator 43, task 6) or none | 16 have none: all `WeightProbability_Poststall = WeightProbability(0.0)` placeholders in CP provokes (disabled branch) |
| A RandomSelect's children are either all probabilities (329) or none (775) | never mixed; without probabilities the children are composites/tasks/decorator gates (uniform pick *[guess]*) |
| Parallel children are tasks | 653/653: Pitch+Roll 577, Roll+Pitch 74, Flares+Roll+Pitch 2 |
| Selector children are mostly gates; last child may be an ungated fallback | last child: decorator 36, task 15, composite 9 |
| Empty composite allowed (at least at build) | `LaxSequencer_LR` in Provoke_0091_m has no child |
| Size | depth 1..14 (median 4), nodes 2..680 (median 39; Provoke_00x1_CP_s 680) |

Children counts per composite: Sequencer 1-6, LaxSequencer 0-7, Selector 1-15, LaxSelector 1-3, RandomSelect 1-34
(median 2), Continuation 1-5 (181 of 231 have 3: Level, RandomSelect, Level), LaxContinuation 1-3, Parallel 2-3.

### 1.4 Node kinds and factories
- **Composites (8)**: Selector, LaxSelector, Sequencer, LaxSequencer, RandomSelect, Continuation, LaxContinuation, Parallel.
- **Decorators (14 used)**: DecoratorBlackboard, DecoratorBlackboardInt, DecoratorBlackboardFloat, DecoratorBlackboardEnum,
  DecoratorIsKDSP1, DecoratorIsKDSP2, DecoratorIsTrackingAirTarget, DecoratorIsFireMissileFinished, DecoratorIsFlareActive,
  DecoratorCanCobra, DecoratorCanKulbit, DecoratorUnitAltitudeComparison, DecoratorIsDamagePercentageRatio,
  DecoratorIsAroundPlayer.
- **Probabilities (3)**: WeightProbability, WeightProbabilityPilotRank, WeightProbabilityAILevel.
- **Tasks (38 used)**: the maneuvers, PursuerTarget, MoveAwayFromTarget, state setters, RunBehavior, etc. (section 2).
- Registered but never used in a stock script (native_move/pairs.txt): UpdateAIState, PostAIState, FlyToClearAltitude,
  AutoDestruct, WingmanFollow, ManeuverAileronRoll, ManeuverCloudReaction, ManeuverTurnToPoint, ManeuverFlatSpin,
  SetWingmanState, DecoratorBlackboardString, DecoratorIsTrackingAirTargetSurround, DecoratorIsCloud, DecoratorIsThereGround,
  DecoratorWingmanUseSpecialWeapon, DecoratorWingmanFireSpecialWeaponFinished, WeightProbabilityPersonality.
  No stock argument shapes exist for these; wait for the native signatures.

### 1.5 Composite semantics (inference from usage; names follow UE/BT conventions)
- **Sequencer**: children in order, stops on a failure. The Provoke dispatchers use it so the closing
  `SetStateEscapeFromPursuer` runs only after a band was chosen.
- **LaxSequencer**: children in order, carries on past a failing child. Evidence: LA_AIPlane's root LaxSequencer runs
  `ExecuteFunction(UPDATE_AI_STATE)`, the state Selector and `ExecuteFunction(POST_UPDATE_AI_STATE)` every tick; PursueTarget
  scripts end with an unconditional `SetMoveAwayFromTarget` after the pursuit gates.
- **Selector**: the first child whose gate passes runs (state dispatch in LA_AIPlane; distance bands in the dispatchers).
- **LaxSelector**: same layout (gated children + fallback composite, e.g. PursueTarget_0011 `IsKDSP1 -> ...` then `Selector`);
  difference from Selector unknown.
- **RandomSelect**: one child at random, weighted by its WeightProbability* children; weights are relative (sums per
  RandomSelect: 100 x111, 20 x79, 10 x17, 30, 95, 70, 120 ...), PilotRank columns are per rank (sums 100,100,100,100,100
  x28; 10 x21; 101 in one column x19 = designer typo; 100/100/110/120/130 x5). A weight of 0 disables the branch.
  Gated children (UnitAltitudeComparison) inside a RandomSelect presumably make it pick among the passing ones *[guess]*.
- **Parallel**: runs its tasks at once (a rolling pull = Roll + Pitch together).
- **Continuation / LaxContinuation**: only in CP provokes/missile evasions (chains `Level, RandomSelect, Level`),
  UAV_Charge, Wingman_0000, Ap/UnDock; *[guess]* a sequence that flows from one maneuver into the next without settling.

### 1.6 Literals, globals, enums
- Numbers are written as floats (`1.0`) except two int positions: `ManeuverBarrelRoll` arg1 (+1/-1) and
  `DecoratorBlackboardInt` arg2. Lua 5.3 keeps int/float subtypes; copy the stock literal form.
- `FVector.New(x, y, z)` (DefaultLua/structutil.lua wraps the native constructor): PursuerTarget arg17, PlaySound arg2.
- Strings: actor keys `"TargetActor"` 3453, `"PursuerActor"` 3578, `"SelfActor"` 406, `"LocalPlayer"` 21,
  `"WingmanAttackActor"` 31, `"WingmanOwnerActor"` 1; blackboard keys (section 3); slot names (RunBehavior);
  AkEvents `AKE_GEN_AIR_MANEUVER_OP1016_x40a_Tewy_RapidTurn_Play` (110, X-40 sets) and `..._OP1021_su57_Toprak_Kulbit_Play` (3);
  mission triggers `Acrobat01..04`.
- Enums (all values used): `ELiveAIManeuverSpeedType.{SpdConstant 3526, SpdRelative 3408, SpdCruise 195, SpdNoAdjustment 5}`;
  `EArithmeticKeyOperation.{Equal 53, LessOrEqual 40, Greater 19, GreaterOrEqual 9, NotEqual 3, Less 3}`;
  `EBasicKeyOperation.Set 5`; `ELiveAIState.*` (15 values, see 3); `ELiveAIAlert.{Gun, Missile, SpecialWeapon}`;
  `ELiveAIWingmanState.{Arbitrary, FocusedAndForward, Follow, Support}`;
  `ELiveExecFunctionType.{UPDATE_AI_STATE, POST_UPDATE_AI_STATE}`; `ELiveWeaponNumber.{WN_WEAPON_1, WN_WEAPON_4}`.
- Stock oddities the game accepts: `ManeuverFlyStraight("TargetActor", SpdConstant, -200.0, 3.0, false, 10000.0)` x5 (CP
  provokes), Provoke_0011_s `LT_Pitch = ManeuverPitch(-1.0, 35.0, ...)` (left turn pitches down, right turn up),
  PilotRank columns summing to 101, `RigthTurnStrong`.

## 2. Factory table
Full per-argument data (types, distinct values, min/median/max, top values, CP vs non-CP, meaning) is in
`build/research/ai/survey/factories.tsv` (223 rows) and `out/factories.txt`. Summary, most used first.
Notation: `n` uses / scripts; argument list with type and the observed values.

### 2.1 Maneuver tasks (common tail)
Most maneuvers end with the same five or six arguments: **`actor, speedType, speed, duration, flag [, opt]`**.
- `actor`: the reference actor; SpdRelative speeds are relative to it [usage] (CP sets reference `"PursuerActor"`:
  480/543 Level, 762/773 TurnNormal; non-CP reference `"TargetActor"`).
- `speed`: see section 0. Node names confirm SpdConstant values: `FlyStraight_1500 -> 1500.0`, `TurnLeft2400Strong -> 2400.0` [name].
- `duration`: seconds [name].
- `flag`: always false in Level/Pitch/Roll/TurnAdvanced/TurnQuick; true only in a few (see each).
- `opt` (optional float): 500 / 1000 / 1500 / 2500 / 10000 / 15000. Present in CP, ace and later-written scripts
  (Level 664/1885, Pitch 774/1397, Roll 686/1177, TurnNormal 782/1696, FlyStraight 210/757); independent of the speed
  type; purpose unknown (it is not a speed: `SpdRelative 300` with opt 15000).

| factory | n | args (stock values) |
|---|---|---|
| ManeuverLevel | 1885 / 183 | `f 1.0 (0.5 x4), f 1.0 (0.5 x4), actor, speedType, speed (-400..4000, med 1000), dur 0.1..10 (0.5 x655, 1.0 x524), false, [opt]` |
| ManeuverTurnNormal | 1696 / 117 | `pull 0.3..3.5 (1.0 x1059; HighPitch 1.0 / LowPitch 0.5 [name]), turnDeg 15..180 (180 x753) [name TurnUp120M, LeftTurn100M], f 0.5..3 (1.0 x1430), liftDir -180..180 (0 up, +90 right, -90 left, +-180 down, +-45/+-135 diagonals) [name], actor, speedType, speed -300..4000, dur 1..9, flag (true x318: CP Provoke_l x282 with opt 15000, Provoke_0000_s/m), [opt]` |
| ManeuverPitch | 1397 / 129 | `dirRate -1..1 (+1 up, -1 down [name]; 0.2..0.9 = per-class scale in CP msl), angleDeg 5..180 [name PitchUp20], actor, speedType, speed, dur 0.5..10, false, [opt]` |
| ManeuverRoll | 1177 / 118 | `rate -1..1 (1.0 x957; sign also flips the direction), bankDeg -179..180 (+ right / - left [name]), actor, speedType, speed, dur 0.2..10, false, [opt]` |
| ManeuverFlyStraight | 757 / 170 | `actor, speedType, speed -200..4000, dur 0.1..5, flag (true x3 = the CP 0.7 s reaction delay), [opt]` |
| ManeuverBarrelRoll | 93 / 49 | `dir int +1/-1, f 0..1 (1.0/0.75), f -1..4.5 (1.0/0.75), actor, speedType, speed 100..3000, dur 1.5..6, flag (true x10), [opt]` |
| ManeuverFrontCross | 49 / 18 | `f 500..10000 (1000/2500), sideDeg +-90/0, flag, actor ("PursuerActor" 47), speedType, speed -200..3000, dur 0..4, flag, f 500..15000 (always present)` - CP provokes only |
| ManeuverTurnQuick | 37 / 11 | `pull 1.0/3.5, turnDeg 60..180, f 0.1..1.5, liftDir, f 3.0 (30.0 in 9001/9999), actor, speedType, speed 100..3000, dur 1.3..60, false, [opt 500]` - ace/online provokes |
| ManeuverTurnAdvanced | 36 / 27 | `f 1..10, f 1..10, actor, SpdConstant (always), speed 300..3500, dur 1..5, false, [opt 500]` - no direction: LastTGT uses it to turn on `"LocalPlayer"` [usage] |
| ManeuverSlalom | 6 / 3 | `f 0.5/1, f 0.5/1, angle -60..60, actor, speedType, speed, dur 0.1..1, false, [opt 500]` |
| ManeuverYaw | 1 / 1 | `1.0, 5.0, "WingmanAttackActor", SpdRelative, 600.0, 3.0, false` |
| ManeuverCobraTurn | 15 / 15 | `false` - always under DecoratorCanCobra |
| ManeuverPugachevsCobra | 15 / 15 | `false, false` - always under DecoratorCanCobra |
| ManeuverKulbit | 17 / 17 | 2-arg `false, false` (12) or 7-arg `b, b, b, "TargetActor", ELiveWeaponNumber (WN_WEAPON_1 x4 / _4 x1), 1.0, 1.5` (LA_Shadow_Kulbit `true, true, true, ...WN_WEAPON_4` fires during the move) |
| ManeuverKulbitToprak | 2 / 1 | `true, true, 80.0, 1.0, +-170.0, 24.0, +-135.0, 1.0, true, "TargetActor", WN_WEAPON_4, 1.5, 2.0` |

### 2.2 Pursuit, movement and state tasks

**InstancePursuerTarget** (59 / 27, always 17 args). Per position (all 59 listed in out/pursuer_target.txt):

| # | type | values (count) | what the scripts show |
|---|---|---|---|
| 1 | float | 12 x17, 6 x7, 8 x6, 20 x5, 60 x5, 10 x4, 5 x4, 3 x3, 8.5, 28, 13, 24 (3..60) | time limit in s [usage]: LastTGT 2 x 10 (the "2 x 10 s" chase), unique actions 60, enemies 5-28 |
| 2 | string | "TargetActor" 32, "WingmanAttackActor" 18, "LocalPlayer" 8, "WingmanOwnerActor" 1 | who to pursue; "LocalPlayer" only in scripted actions (LastTGT, BarrierCharge, UAV_Charge, Inviting) |
| 3 | float | 10 x17, 2 x13, 1 x12, 100 x7, 3 x4, 5 x4, 6.5 x2 | scales with tier [usage]: 0000/0011/0041/wingmen 1-3, aces 0400/0430 and 0091/0200/0999 10, 0201 2 (KDS1) or 10, scripted unique actions 100 |
| 4 | bool | false 38 / true 21 | true in all 8 KDS-phase-1 pursuits (incl. Provoke_0002_s), the 4 re-attacks of MoveAwayFromTarget_0000/1000, WingmanAcrobat x4, the wingman owner pursuit, BarrierCharge, Inviting/Pushing recipients, WingmanInviting |
| 5 | float | 1500 x14, 2000 x12, 500 x9, 3000 x8, 1000 x7, 2500 x7, 3500 x2 | KDS1: 2500-3000; rear pursuits 1000-2000; wingmen/scripted 500. *[guess]* approach speed or distance |
| 6 | float | 20 x29, 40 x17, 60 x6, 30 x5, 10 x2 | 20 default, 40 wingmen, 60 in KDS1 of 0011/0041/0201 and BarrierCharge. *[guess]* an angle |
| 7 | bool | false 32 / true 27 | true in KDS2/tracking pursuits of 0000, 0091, 0200, 0201, 0430 and wingmen; false in 0400, 0011 and all KDS1 |
| 8 | float | 150 x29, 120 x24, 130 x4, 6 x2 | 6 only in the 1 s re-attack `PursuerTarget1` of MoveAwayFromTarget_0000/1000 |
| 9 | float | 3 x52, 0 x4, 2 x2, 5 x1 | 0 with arg8 6 or in online KDS2 |
| 10 | float | 500 x18, 10 x12, 20 x9, 4 x6, 12 x5, ... (1..500) | 500 = wingmen/unique actions; enemies 4-20, often = arg1 (12/12, 8.5/8.5, 10/10) |
| 11 | bool | false 52 / true 7 | true only with (45, 2400) |
| 12, 13 | float, float | (60, 3000) x36, (0, 0) x13, (45, 2400) x8, (15, 1000) x2 | a pair; (45, 2400) = the "PursuerTarget3"/tracking pursuit of 0000, 0091, 0200, 0400, 0430, 0999; (0, 0) = KDS/online; (15, 1000) = UAV_Charge. *[guess]* cone angle deg + range |
| 14, 15, 16 | bool x3 | (F,F,F) 30, (T,F,F) 15, (T,F,T) 7, (F,T,F) 4, (T,T,F) 3 | arg16 true only in scripted pursuits of the player/wingman (LastTGT, BarrierCharge, Inviting/Pushing); (T,T,F) = 0011's plain pursuit and UAV_Charge; arg15 true also in 0000/0201 long pursuits |
| 17 | FVector | (-400, 0, 5) x50, (-200, 0, 0) x2 LastTGT, (-150, 0, 5) x2 UAV, (1500, 0, 5) x2 + (1800, 0, 5) Inviting, (150, 0, 5) BarrierCharge, (-300, 0, 5) Pushing | position offset in the target's frame [usage]: X < 0 behind, X > 0 ahead (Inviting = lead the player); Y always 0, Z 5 or 0. Units unknown (m *[guess]*) |

No enemy pursuit varies arg17: aggression comes from the other arguments and the tree around the task.

| factory | n | args |
|---|---|---|
| MoveAwayFromTarget | 14 / 14 | `dur 3..7.5 (5 x11) s [usage: MoveAwayFromTarget_0011 = 1 + 1.5 + 5 + 5 = 12.5 s break; LA_SV_MoveAway 1.2 proven in game], actor ("TargetActor" 8, "WingmanAttackActor" 3, "PursuerActor" 2, "SelfActor" 1), f 3000/4500/6000 [guess: distance], [bool]` (3-arg form only for the wingman) |
| MoveCenterAltitude | 6 / 6 | `dur 2.5..5, f 250/500, bool` (after MoveAway / in online escapes) |
| MoveToTarget | 4 / 4 | `"TargetActor", 5.0, 1200/1500, 200.0` |
| SetMoveAwayFromTarget | 8 / 6 | `"TargetActor" 5 / "SelfActor" 3` - only in PursueTarget scripts; sets AIState MoveAwayFromTarget. Survival's test of 2026-10-22: it is what starts the next attack run |
| SetStateEscapeFromPursuer | 45 / 44 | `"TargetActor" 42 / "PursuerActor" 3` - last child of 35 Provoke leaves (non-CP, 0041/0042_CP, 0091_l), inside 0251_s/_m, the 3 Provoke dispatchers, and the Evade dispatchers' far-gun fallback (5) |
| ActivateFlares | 213 / 59 | `"PursuerActor" 183 / "TargetActor" 30, true 203 / false 10` |
| RunBehavior | 52 / 12 | `slot name` (section 4.1) |
| ExecuteFunction | 4 / 2 | `ELiveExecFunctionType.UPDATE_AI_STATE / POST_UPDATE_AI_STATE` (root only) |
| WaitTime | 4 / 4 | `(10, 15)` Blackout_1000, `(0.5, 15)`, `(1, 600)`, `(0, 1)` *[guess: min, max s]* |
| PlaySound | 113 / 9 | `AkEvent, FVector.New(0, 0, 0)` |
| NotifyEventTrigger | 4 / 1 | `"Acrobat01".."04"` (WingmanAcrobat) |
| ReturnToUnitCircle 1.5, Patrol 200.0, OutOfWorldReaction, AvoidObstacle, AvoidRangeAttack, Group, GoFormation, LevelPlane, Shield, ApproachAndDocking("TargetActor"), UnDock("TargetActor") | 1-3 each | root / special scripts |

### 2.3 Decorators

| factory | n | args (values) | notes |
|---|---|---|---|
| DecoratorUnitAltitudeComparison | 381 / 70 | `bool (false 192 / true 189), 1000.0 (always)` | true gates every move whose first part goes down (189/189 by name: PD, DTN, LDT, RDLUN ...); false gates climbs, level moves and up-first combos [name]. *[guess]* compares own altitude against the unit/area altitude + 1000 |
| DecoratorBlackboardFloat | 70 / 23 | `"PursuerDistance" (only key), cm threshold 2000..1000000, op, bool (true 62 / false 8)` | the last bool is not an inversion (names match the plain condition); the 8 false ones sit in RandomSelect/LaxSequencer, never in a Selector |
| DecoratorBlackboardEnum | 51 / 11 | `"AIState" 32 / "AIAlert" 15 / "WingmanState" 4, enum, Equal 48 / NotEqual 3, true` | dispatchers |
| DecoratorCanCobra / CanKulbit | 26 / 13 | `true, true` | gate post-stall moves on the plane's ability (bCanManeuverPugachevsCobra / bCanManeuverKulbit) |
| DecoratorIsKDSP1 | 20 / 20 | `true, false` (Provoke_0002_s `true, true`) | arg1 = expected value (pattern of the Is* decorators) |
| DecoratorIsKDSP2 | 8 / 6 | `true, false` | |
| DecoratorIsFireMissileFinished | 7 / 7 | `false, false` (PursueTarget) / `false, true` (wingmen) | arg1 = expected value: node name `PT1_IsNotFireMissileFinished` [name] |
| DecoratorIsFlareActive | 7 / 6 | `true, true` / `false, true` | node `NotFlareActive = (false, true)` [name] |
| DecoratorIsTrackingAirTarget | 4 / 4 | `true, true` (0200, 0400, 0430) / `true, false` (0000) | |
| DecoratorBlackboardInt | 5 / 2 | `"WingmanNo" 1/2/3` / `"BarrierChargingCompleted" 0/1`, Equal, bool | |
| DecoratorBlackboard | 5 / 4 | `"WingmanAttackActor" / "IsExistKDSBack" / "IsExecutablePreDistributedAttack", EBasicKeyOperation.Set, bool` | key-is-set test |
| DecoratorIsDamagePercentageRatio | 1 | `"SelfActor", 70.0, GreaterOrEqual, true` | AttackAvoidance_0252_msl_m |
| DecoratorIsAroundPlayer | 1 | `2000.0, true, true` | MoveAwayFromTarget_0201 |

### 2.4 Probabilities

| factory | n | args |
|---|---|---|
| WeightProbability | 865 / 54 | `weight 0..95` (10 x265, 15 x110, 20 x95, 60 x74, 1 x65, 0 x60, 4 x57) |
| WeightProbabilityPilotRank | 430 / 76 | `w(rank1), w2, w3, w4, w5` - typical missile evasion Weak 100/95/85/70/55, Normal 0/5/15/25/35, Flare 0/0/1/5/10; ace Weak 50/40/30/20/10, Normal 50/60/70/80/90, Strong 0/0/10/20/30 |
| WeightProbabilityAILevel | 9 / 4 | 5 weights, only in unassigned 0001_gun / 0030_* |

## 3. Blackboard
| key | type | used as | values / thresholds | slots |
|---|---|---|---|---|
| `AIState` | ELiveAIState | root state dispatch (Equal); Provoke dispatcher `NotEqual EscapeFromPursuer` | ReturnToWorld, AvoidObstacle, AvoidRangeAttack, ReturnToUnit, Blackout, AttackAvoidance, CloudAvoidance, EscapeFromPursuer, MoveAwayFromTarget, Provoke, Group, PursueTarget, FollowFormation, UniqueAction, Patrol (+ Wingman in LA_AIWingmanPlane) | root, Provoke |
| `AIAlert` | ELiveAIAlert | Evade dispatcher | SpecialWeapon, Missile, Gun | Evade |
| `PursuerDistance` | float, cm | distance bands (the only float key) | Provoke_0000: <=10000 / <=20000; Provoke_0000_CP, 0091: <=150000 / <=1000000 / >1000000; Evade 0000/0000_CP/0400/1000: missile <=100000 near, gun <=80000 else escape; Evade 0201: <=500000 special, <=75000 near, gun <=120000; CP provoke-near inner split 120000 (0000/0011/0021_CP_s) or 50000 (0031/9001/9999); Provoke_0400_s decel turns <=5000; AttackAvoidance_0400_gun post-stall <=50000; PursueTarget_0011 >=2000; PursueTarget_0091 2500; EscapeFromPursuer_0000_CP 100000 | Provoke*, Evade*, PursueTarget, EscapeFromPursuer |
| `WingmanState` | ELiveAIWingmanState | Wingman_0000 | FocusedAndForward, Arbitrary, Support, Follow | wingman |
| `WingmanNo` | int | ArbitraryAction | 1, 2, 3 | unique |
| `BarrierChargingCompleted` | int | UnDock | 0, 1 | unique |
| `WingmanAttackActor`, `IsExistKDSBack`, `IsExecutablePreDistributedAttack` | set/unset | wingman attack scripts | Set | wingman |
| `TargetActor`, `PursuerActor`, `SelfActor`, `LocalPlayer`, `WingmanAttackActor`, `WingmanOwnerActor` | actor keys | task arguments | - | all (Survival's ai_watch reads `TargetActor` from the blackboard) |

In a PursueTarget script `"PursuerActor"` still appears (0400's break turns, 0002's maneuvers): it is the plane chasing
this one, so the ace breaks relative to whoever is on its tail. In Evade scripts it is the attacker.

## 4. Slot patterns

### 4.1 Root and RunBehavior dispatch
LA_AIPlane (all enemy planes): `LaxSequencer[ ExecuteFunction(UPDATE_AI_STATE), Selector[ 15 x (BlackboardEnum("AIState", X, Equal, true) -> task) ], ExecuteFunction(POST_UPDATE_AI_STATE) ]`.
Gate order: ReturnToWorld -> OutOfWorldReaction, AvoidObstacle -> AvoidObstacle, AvoidRangeAttack -> AvoidRangeAttack,
ReturnToUnit -> ReturnToUnitCircle(1.5), Blackout -> RunBehavior("BlackoutBehavior"), AttackAvoidance -> "EvadeBehavior",
CloudAvoidance -> "CloudAvoidanceBehavior", EscapeFromPursuer -> "EscapeFromPursuerBehavior", MoveAwayFromTarget ->
"MoveAwayFromTargetBehavior", Provoke -> "ProvokeBehavior", Group -> Group(), PursueTarget -> **"PursuerTargetBehavior"**,
FollowFormation -> GoFormation(), UniqueAction -> "UniqueActionBehavior", Patrol -> Patrol(200.0).
The native code sets AIState; the scripts only read it (and switch it with SetMoveAwayFromTarget / SetStateEscapeFromPursuer).
LA_AIWingmanPlane: same but Wingman -> "WingmanBehavior" instead of Blackout, no Group.

RunBehavior names and the LuaSet field they evidently map to (by name *[inference]*): EvadeBehavior = EvadeLua,
EvadeMissileNearBehavior / EvadeMissileFarBehavior / EvadeGunBehavior / EvadeSpecialBehavior = Evade*Lua (called from the
Evade dispatcher), BlackoutBehavior, CloudAvoidanceBehavior, EscapeFromPursuerBehavior, MoveAwayFromTargetBehavior,
ProvokeBehavior, ProvokeNear/Mid/FarBehavior (from the Provoke dispatcher), PursuerTargetBehavior = PursueTargetLua
(note the spelling), UniqueActionBehavior = the requested unique action, WingmanBehavior + WingmanForwardAttack /
DistributedAttack / PreDistributedAttack / SupportBehavior (Wingman_0000). Only these call sites exist: root -> slots,
Evade -> 4 sub-slots, Provoke -> 3 sub-slots, Wingman -> 4. A leaf calling RunBehavior is untested.

The attack cycle seen from the scripts: PursueTarget leaf ends with `SetMoveAwayFromTarget` -> MoveAwayFromTarget slot
(extend) -> native goes back to PursueTarget. Being tailed -> native Provoke -> dispatcher picks Near/Mid/Far by
PursuerDistance -> leaf -> `SetStateEscapeFromPursuer` -> EscapeFromPursuer slot. Weapon alert -> AttackAvoidance ->
Evade dispatcher by AIAlert and PursuerDistance.

### 4.2 Per slot (representative scripts in out/trees/)
- **Evade dispatcher** (5 scripts). `Selector[ AIAlert==SpecialWeapon -> EvadeSpecial, AIAlert==Missile -> Selector[<=1 km Near, >1 km Far], AIAlert==Gun -> Selector[<=800 m EvadeGun, SetStateEscapeFromPursuer("TargetActor")] ]`.
  `_0000_CP` puts `FlyStraight("SelfActor", SpdRelative, 50, 0.7, true, 500)` (0.7 s reaction delay) before each
  sub-behaviour; `_0400` (aces) drops the gun distance check (always EvadeGun) and has no delay; `_0201` uses 5 km / 750 m / 1.2 km.
- **EvadeMissileNear/Far** (msl_s / msl_m, 71 scripts). `RandomSelect[ PilotRank(Weak) -> RandomSelect[weighted turn sequences], PilotRank(Normal) -> RandomSelect[altitude-gated turns], PilotRank(Flare/Strong) -> RandomSelect[ActivateFlares + hard turns] ]`.
  Each leaf sequence = `Level 0.2-0.5 s -> Roll +-90 / TurnNormal -> Pitch -> FlyStraight`. e.g. AttackAvoidance_0011_msl_s
  (96 nodes), 0400_CP_msl_s (Parallel Roll+Pitch at 1500-2400, durations 1-3 s), 0000_CP_msl_s (160 nodes, PilotRank
  Basic 100/97/90/85/80, "Decorate" branch weight 0, "Serious" 0/3/10/15/20).
- **EvadeGun** (28). Rookie: `RandomSelect[ PilotRank Weak -> straight / 20 deg turns, PilotRank Normal -> barrel rolls ]` (0011_gun, 17 nodes).
  Post-stall sets (0000(_CP)_gun, 0051-53, 0091, 0400) add CanCobra/CanKulbit-gated CobraTurn, PugachevsCobra and Kulbit
  branches. 0400_gun: `RandomSelect[ PursuerDistance<=500 m -> RandomSelect[CanCobra->CobraTurn, CanCobra->Pugachev, CanKulbit->Kulbit], barrel rolls, 80 deg turns, Immelmann ]`, everything SpdConstant 3000, 0.1-2.5 s.
- **EvadeSpecial** (spw): rookie = `Level 0.5 s + FlyStraight 3 s` (0011_spw, 3 nodes: no evasion); ace 0400_spw = `LaxSelector[IsFlareActive -> flares + turns, NotFlareActive -> turns]`.
- **Provoke dispatcher** (4): `Sequencer[ Selector[ PursuerDistance bands -> RunBehavior Near/Mid/Far ], AIState != EscapeFromPursuer -> SetStateEscapeFromPursuer("PursuerActor") ]`.
- **ProvokeNear/Mid/Far** (69). Non-CP rookie (Provoke_0011_s, 39 nodes): `LaxSequencer[ RandomSelect[8 x (Level 0.5 s, turn/pitch 2 s, FlyStraight 2.5 s)], SetStateEscapeFromPursuer("TargetActor") ]` at SpdConstant 1000 - 3.5-6 s per reaction.
  CP (Provoke_0011_CP_s, 680 nodes): `LaxSequencer[ RandomSelect[ Turn 90 -> Selector[<=1.2 km close-range turns, >1.2 km turns], Counter 6 (FrontCross), Weak 3, Aerobatic 1 (barrel roll), Poststall 0 (empty) ] ]` with
  SpdRelative +100..+1000 to the pursuer, Continuation chains and Parallel rolls, durations 1-5 s. CP _m/_l add `IsKDSP1 -> RandomSelect[50-55 deg turns]`.
  Ace (Provoke_0400_s, 24 nodes): `LaxSequencer[ RandomSelect[ PursuerDistance<=50 m -> decel turns at 300, PitchUp/PitchDown 75 deg (altitude-gated), Roll 0.2 s + Pitch 60 deg 2.5 s right/left ] ]` all SpdConstant 3000.
  Ace _m: 8 altitude-gated break turns + 2 `TurnQuick(3.5, 180, ...)` reversals; ace _l: `Level 0.2 s, FlyStraight 1 s, TurnNormal(3.5, 180, 1.5, +-90, ..., 4000, 4 s)`.
- **EscapeFromPursuer** (10). CP (0000_CP): Level 3 s + FlyStraight 1 s (speed reference chosen by PursuerDistance 1 km) + `MoveAwayFromTarget(4.0, "SelfActor", 6000.0, false)` = ~8 s of predictable flight.
  0011: Level 0.5 s, straight 3.5-4 s, `MoveAwayFromTarget(5.0, "TargetActor", 6000.0, false)`. Ace (0400): one altitude-gated 90 deg break turn, 1.5-2 s at 3000.
- **MoveAwayFromTarget** (6). 0011: `Level 1 s at 1300, FlyStraight 1.5 s, MoveAwayFromTarget(5.0, "TargetActor", 3000.0, true), MoveCenterAltitude(5.0, 500.0, false)` = 12.5 s.
  0000 (aces, 14 sets) = `Sequencer[LaxSequencer[ PursuerTarget(6.0, ..., arg4 true, arg8 6, arg9 0, arg10 1), PursuerTarget(8.5, "TargetActor", 6.5, true, 1000, 60, ...) ]]`: no extend, straight back in.
  0201 (online): if within 2000 of the player, keep pursuing (KDS2_Pursuer), else extend 7.5 s + MoveCenterAltitude.
- **PursueTarget** (11). See 4.3. 0002/1002 (sets 0000, 0001, 1000; 186 nodes) contain **no PursuerTarget**: a
  PilotRank-weighted show of turns, barrel rolls, cobra/kulbit with weights shifting 18->34 / 82->66 by rank.
- **Blackout**: 0000 = `Level 10 s at 600`; 1000 = `LevelPlane, WaitTime(10, 15)`.

### 4.3 NLID_0012_CP (Survival's fighters) vs NLID_0400_CP (aces)
Shared: Blackout_0000, Provoke_0000_CP (bands 1.5 km / 10 km). Everything else differs (out/set_compare.txt):

| slot | 0012_CP | nodes / speed / durations | 0400_CP | nodes / speed / durations |
|---|---|---|---|---|
| Evade | AttackAvoidance_0000_CP | 0.7 s straight delay, gun > 800 m -> escape | AttackAvoidance_0400 | no delay, always EvadeGun |
| MissileNear/Far | 0002_CP_msl_s / _m | 160 / 202 nodes, SpdRel 0..1000, 0.5-5 s (med 4.75) | 0400_CP_msl_s / _m | 56, SpdConst 1500-2800, 1-3 s |
| Gun | 0000_CP_gun | 56, SpdRel 100-400, 0.5-4.3 s | 0400_gun | 32, SpdConst 3000, 0.1-2.5 s, cobra/Pugachev/kulbit <= 500 m |
| Special | 0002_CP_msl_m | | 0400_CP_spw | |
| ProvokeNear | Provoke_0011_CP_s | 680, SpdRel +100..1000, 1-5 s | Provoke_0400_s | 24, SpdConst 3000, 0.2-2.5 s |
| ProvokeMid | Provoke_0011_CP_m | 152, 1-5 s | Provoke_0400_m | 40, SpdConst 3000, 0.3-3 s, TurnQuick 3.5 G |
| ProvokeFar | Provoke_0011_CP_l | 152 | Provoke_0400_l | 9, SpdConst 4000, TurnNormal 3.5 G 180 deg |
| Escape | EscapeFromPursuer_0000_CP | ~8 s level/straight/extend | EscapeFromPursuer_0400 | one 2 s break turn |
| MoveAway | MoveAwayFromTarget_0011 | 12.5 s extend | MoveAwayFromTarget_0000 | 2 pursuits (6 + 8.5 s) |
| Pursue | PursueTarget_0011 | 12 nodes | PursueTarget_0400 | 39 nodes |

PursueTarget_0011 (annotated):
```
LaxSequencer
  ManeuverLevel(1.0, 1.0, "TargetActor", SpdConstant, 1000.0, 0.1, false)        -- 0.1 s level at 1000
  LaxSelector
    IsKDSP1(true, false) -> LaxSequencer                                          -- KDS phase 1 (head-on pass):
        PursuerTarget(5.0, "TargetActor", 2.0, true, 2500.0, 60.0, false, 120.0, 3.0, 12.0, false, 60.0, 3000.0, false, false, false, V(-400,0,5))
        ManeuverFlyStraight("TargetActor", SpdConstant, 1000.0, 5.0, false)        -- fly through 5 s
    Selector
      BlackboardFloat("PursuerDistance", 2000.0, GreaterOrEqual, true) ->          -- not closer than 20 m
        PursuerTarget(15.0, "TargetActor", 3.0, false, 2000.0, 20.0, false, 120.0, 3.0, 4.0, false, 60.0, 3000.0, true, true, false, V(-400,0,5))
      SetMoveAwayFromTarget("SelfActor")                                           -- too close: break off
  SetMoveAwayFromTarget("SelfActor")                                               -- always: end the run -> MoveAway slot
```
PursueTarget_0400 (annotated):
```
LaxSequencer "PT1"
  ManeuverLevel(1.0, 1.0, "TargetActor", SpdConstant, 2000.0, 0.2, false, 500.0)
  RandomSelect
    WeightProbability(7.0) -> Selector
        IsKDSP2(true, false) -> PursuerTarget2(8.0, "TargetActor", 10.0, false, 1500.0, 20.0, false, 130.0, 3.0, 10.0, true, 45.0, 2400.0, F, F, F, V(-400,0,5))
        IsTrackingAirTarget(true, true) -> PursuerTarget3(8.0, "TargetActor", 10.0, false, 1500.0, 20.0, false, 120.0, 2.0, 20.0, true, 45.0, 2400.0, F, F, F, V(-400,0,5))
    WeightProbability(3.0) -> IsKDSP1(true, false) -> PursuerTarget1(6.0, "TargetActor", 10.0, true, 3000.0, 20.0, false, 150.0, 3.0, 10.0, false, 0.0, 0.0, F, F, F, V(-400,0,5))
  LaxSequencer
    ManeuverFlyStraight("TargetActor", SpdConstant, 2000.0, 5.0, false, 500.0)   -- 5 s straight at 2000
    RandomSelect_2: 6 altitude-gated break turns against "PursuerActor" (SpdRelative 300):
        PitchUp/Down 80 deg 2.5 s, Left/Right Up 60/60, Left/Right Down 120 roll + 60 pitch 1.8 s
  (no SetMoveAwayFromTarget: the state stays PursueTarget and the tree runs again)
```
What makes the ace pursuit aggressive (all from the scripts):
1. It never hands over to the MoveAway slot; and when the native does, the ace MoveAway slot is itself two pursuits.
2. Short pursuit windows (6-8 s instead of 15 s) are re-chosen often, alternating KDS2 / tracking / KDS1 branches 70/30.
3. PursuerTarget arg3 = 10 (0011: 2-3), arg5 1500 (0011: 2000/2500), arg10 10-20 (0011: 4/12),
   the tracking tuple arg11-13 = (true, 45, 2400) (0011: false, 60, 3000), arg14/15 false (0011's plain pursuit true/true).
   arg17 is the same (-400, 0, 5) everywhere: the offset is not what changes.
4. Twice the speed: Level/Straight at SpdConstant 2000 (0011: 1000); the defensive sets run at 3000-4000.
5. After each window it breaks hard against whoever is behind it (PursuerActor), so it is never a steady target.
6. Rank inside the same trees (PilotRank 5 on `_Named` rows) moves weight from Weak to Normal/Strong branches in evasions.
The catch (AGENTS rule 22): with no KDS phase and no tracked air target, no 0400 branch pursues at all.

## 5. Variation analysis (how designers tuned the same slot)
Full aligned diffs: out/variation_same_shape.txt (37 groups of identical shape). Feature rows (nodes, speeds, durations,
G, flares, post-stall, KDS gates per script): out/variation_features.txt.

- **Grade inside a family (D digit) changes angles only.** 0011 -> 0012 -> 0013 msl_s: Pitch arg2 20/25/30 and 15/20/25,
  TurnNormal arg2 25/30/35 and 20/25/30; same in 0011-13_gun (20/25/30), 0031-33 msl (15/20/25), 0051-53 gun (20/25/30),
  0021-23 Provoke_m (35/40/45), 0031-33 Provoke_s/m (30/35/40), 0051-53 Provoke (35/40/45). Speeds and timing stay.
- **Airframe class inside CP sets scales rates.** 0000_CP / 0002_CP / 0003_CP msl (multirole / Typhoon / 5th gen):
  Pitch arg1 0.5/0.4/0.32 (msl_s) and 0.35/0.28/0.2 (msl_m), Roll arg1 0.75/0.65/0.6, BarrelRoll arg2 0.5/0.4/0.34;
  angles and durations unchanged. *Inference*: arg1 is a fraction of the airframe's own rate, normalised so the moves look the same.
- **0001_CP vs 0400_CP msl** (same shape): pitch angles 10 -> 20, PilotRank Weak 70/60/50/40/30 -> 50/40/30/20/10.
- **CP 0000_CP_s / 0011_CP_s / 0021_CP_s provokes** (680 nodes, same shape): Pitch/Roll durations 3 / 3 / 6 s and six weights;
  0011_CP_m/l vs 0021_CP_m/l: TurnNormal durations 1 vs 9 s, weights 30 vs 15. Heavier classes turn longer.
- **0021-0024 Provoke_s / msl_s**: 0024 runs 1050-1500 (median 1300) instead of 1000-1200 (faster class).
- **0011 vs 0041 Escape / 0041 vs 0041_CP vs 0042_CP provokes**: only speed (1000 -> 1500; 1500/1750/1550).
- **Tier (AB digits) changes structure.** Rookie/CP: big random trees, low SpdConstant (900-1300) or SpdRelative to the
  pursuer, long durations (median 2-4.75 s), reaction delay. Ace 0400/0430: small trees, SpdConstant 3000-4000,
  durations 0.2-2.5 s, TurnQuick / 3.5 G turns, post-stall, flare branches (0430_msl_s 8 flares), no extend (9-67 nodes).
  Online named 02xx: SpdConstant 1650-3500, TurnAdvanced, FrontCross-free, MoveCenterAltitude.
- **PursuerTarget across PursueTarget_*** (out/pursuer_target.txt): KDS1 windows 4-6 s with arg4 true, arg5 2500-3000;
  KDS2/tracking 6-28 s with arg5 1000-1500 and arg7 true (except 0400); arg3 1-3 (0000, 0011, 0041) vs 10 (0091, 0200, 0201, 0400, 0430).
- **CP vs non-CP** (factories.tsv columns top_CP / top_nonCP): CP maneuvers reference `"PursuerActor"` with `SpdRelative`
  (+300 / -300 / -200) and carry the optional last argument (1500/10000/15000); non-CP ones use `"TargetActor"` + `SpdConstant`.
  CP TurnNormal turns are 180 deg in 709 of 773 (else 50/55/150) with 1-9 s; non-CP 30-90 deg with 1.5-4.3 s.

## 6. Ready-made patterns (stock factories and argument shapes only)
Rules from the survey and AGENTS.md: package as `/Game/LuaSource/SurvivalMode/AI/<name>` (tools/build_survival.py
LUA_SCRIPTS), point a Survival LuaSet row's slot at it (main.lua CFG.behaviour_sets), and remember the behaviour is
built when the level loads (rule 20). Run `python tools/checks/lua_check.py <file>` and
`python build/research/ai/survey/shapecheck.py <file>` after writing (all three below pass both). None of these is tested in game.

### 6.1 Aggressive tail chase (PursueTarget slot)
0011's skeleton (its ungated pursuit is proven to attack in Survival) with the ace values, two pursuit windows
chained with a re-acquire turn as LastTGT does, and the closing `SetMoveAwayFromTarget` Survival needs (pair it with 6.3).
```lua
local LA_SV_TailChase = Inherit(CppObjectBase)
function LA_SV_TailChase:Ctor()
self:GenerateBehavior()
self:AddRootComposite("LaxSequencer", self:InstanceLaxSequencer())
self:AddTask("LaxSequencer", "ManeuverLevel", self:InstanceManeuverLevel(1.0, 1.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 2000.0, 0.2, false, 500.0))
self:AddComposite("LaxSequencer", "LaxSelector", self:InstanceLaxSelector())
self:AddDecorator("LaxSelector", "IsKDSP1", self:InstanceDecoratorIsKDSP1(true, false))
self:AddComposite("IsKDSP1", "KDS1", self:InstanceLaxSequencer())
self:AddTask("KDS1", "KDS1_Pursuer", self:InstancePursuerTarget(6.0, "TargetActor", 10.0, true, 3000.0, 20.0, false, 150.0, 3.0, 10.0, false, 0.0, 0.0, false, false, false, FVector.New(-400.0, 0.0, 5.0)))
self:AddTask("KDS1", "KDS1_Straight", self:InstanceManeuverFlyStraight("TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 2000.0, 2.0, false, 500.0))
self:AddComposite("LaxSelector", "Selector", self:InstanceSelector())
self:AddDecorator("Selector", "NotTooClose", self:InstanceDecoratorBlackboardFloat("PursuerDistance", 2000.0, EArithmeticKeyOperation.GreaterOrEqual, true))
self:AddComposite("NotTooClose", "Chase", self:InstanceLaxSequencer())
self:AddTask("Chase", "Chase1", self:InstancePursuerTarget(8.0, "TargetActor", 10.0, false, 1500.0, 20.0, false, 120.0, 2.0, 20.0, true, 45.0, 2400.0, false, false, false, FVector.New(-400.0, 0.0, 5.0)))
self:AddTask("Chase", "Reacquire", self:InstanceManeuverTurnAdvanced(3.0, 3.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 1500.0, 2.0, false, 500.0))
self:AddTask("Chase", "Chase2", self:InstancePursuerTarget(8.0, "TargetActor", 10.0, false, 1500.0, 20.0, false, 130.0, 3.0, 10.0, true, 45.0, 2400.0, false, false, false, FVector.New(-400.0, 0.0, 5.0)))
self:AddTask("Selector", "TooClose", self:InstanceSetMoveAwayFromTarget("SelfActor"))
self:AddTask("LaxSequencer", "SetMoveAwayFromTarget", self:InstanceSetMoveAwayFromTarget("SelfActor"))
self:EndGenerateBehavior()
end
return LA_SV_TailChase
```
Sources: Level from PursueTarget_0400; KDS1 pursuer = 0400 `PursuerTarget1`; Chase1 = 0400/0999 `PursuerTarget3`;
Chase2 = 0400 `PursuerTarget2`; Reacquire = LastTGT's `ManeuverTurnAdvanced(3.0, 3.0, ...)` at a fighter speed;
BlackboardFloat gate and both SetMoveAwayFromTarget = PursueTarget_0011. Knobs, in the designers' order: arg3 (2 -> 10),
arg1 window (15 -> 8), level/straight speed (1000 -> 2000). Variants: `"LocalPlayer"` in arg2 forces the player as the
target (only scripted stock uses: LastTGT, UAV_Charge); arg16 true + `FVector.New(-200.0, 0.0, 0.0)` is LastTGT's exact
"turn on the player" pursuit.

### 6.2 Quick-reaction provoke (ProvokeNear, also usable for Mid)
Provoke_0400_s with its exact shapes: first input within 0.2 s, every move <= 2.7 s, then hand to the escape slot as
the non-CP leaves do. Pair it with EscapeFromPursuer_0400 (one 2 s break) instead of 0000_CP (~8 s of predictable flight).
The provoke trigger itself (cone, 2.5 s determination time) is native data (DT_NPC_Provoke), not script.
```lua
local LA_SV_ProvokeQuick = Inherit(CppObjectBase)
function LA_SV_ProvokeQuick:Ctor()
self:GenerateBehavior()
self:AddRootComposite("LaxSequencer", self:InstanceLaxSequencer())
self:AddComposite("LaxSequencer", "RandomSelect", self:InstanceRandomSelect())
self:AddDecorator("RandomSelect", "VeryClose", self:InstanceDecoratorBlackboardFloat("PursuerDistance", 5000.0, EArithmeticKeyOperation.LessOrEqual, false))
self:AddComposite("VeryClose", "DeceleRandom", self:InstanceRandomSelect())
self:AddComposite("DeceleRandom", "DeceleRightTurn", self:InstanceSequencer())
self:AddTask("DeceleRightTurn", "DRT_Roll", self:InstanceManeuverRoll(1.0, 90.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 300.0, 0.5, false))
self:AddTask("DeceleRightTurn", "DRT_Pitch", self:InstanceManeuverPitch(1.0, 60.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 300.0, 2.0, false))
self:AddComposite("DeceleRandom", "DeceleLeftTurn", self:InstanceSequencer())
self:AddTask("DeceleLeftTurn", "DLT_Roll", self:InstanceManeuverRoll(-1.0, 90.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 300.0, 0.5, false))
self:AddTask("DeceleLeftTurn", "DLT_Pitch", self:InstanceManeuverPitch(1.0, 60.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 300.0, 2.0, false))
self:AddDecorator("RandomSelect", "PU", self:InstanceDecoratorUnitAltitudeComparison(false, 1000.0))
self:AddComposite("PU", "PitchUp", self:InstanceSequencer())
self:AddTask("PitchUp", "PU_Level", self:InstanceManeuverLevel(1.0, 1.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 0.2, false))
self:AddTask("PitchUp", "PU_Pitch", self:InstanceManeuverPitch(1.0, 75.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 2.5, false))
self:AddComposite("RandomSelect", "RightTurn", self:InstanceSequencer())
self:AddTask("RightTurn", "RT_Roll", self:InstanceManeuverRoll(1.0, 90.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 0.2, false))
self:AddTask("RightTurn", "RT_Pitch", self:InstanceManeuverPitch(1.0, 60.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 2.5, false))
self:AddComposite("RandomSelect", "LeftTurn", self:InstanceSequencer())
self:AddTask("LeftTurn", "LT_Roll", self:InstanceManeuverRoll(-1.0, 90.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 0.2, false))
self:AddTask("LeftTurn", "LT_Pitch", self:InstanceManeuverPitch(1.0, 60.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 2.5, false))
self:AddDecorator("RandomSelect", "PD", self:InstanceDecoratorUnitAltitudeComparison(true, 1000.0))
self:AddComposite("PD", "PitchDown", self:InstanceSequencer())
self:AddTask("PitchDown", "PD_Level", self:InstanceManeuverLevel(1.0, 1.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 0.2, false))
self:AddTask("PitchDown", "PD_Pitch", self:InstanceManeuverPitch(-1.0, 75.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 2.5, false))
self:AddTask("LaxSequencer", "SetEscapeFromPursuer", self:InstanceSetStateEscapeFromPursuer("TargetActor"))
self:EndGenerateBehavior()
end
return LA_SV_ProvokeQuick
```
Provoke_0400_s itself has no closing state change (its dispatcher Provoke_0000_CP sets EscapeFromPursuer afterwards);
the last line copies the non-CP leaves (NLID_0011 = Provoke_0000 dispatcher + Provoke_0011_s leaf, both calling it).
Optional stock additions: a flare branch `LaxSequencer[ActivateFlares("PursuerActor", true), turn]` as in Provoke_0430_m;
a reversal `ManeuverTurnQuick(3.5, 180.0, 1.5, 90.0, 3.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 2.0, false)`
as in Provoke_0400_m. For the dispatcher keep Provoke_0000_CP (Near <= 1.5 km) so this runs for any close tail.

### 6.3 Short extend (MoveAwayFromTarget slot)
Proven: Survival's LA_SV_MoveAway (Level 0.3 s at 1300, `MoveAwayFromTarget(1.2, "TargetActor", 1000.0, true)`, ~1.5 s).
A slightly longer one on MoveAwayFromTarget_0041's shape (Level, FlyStraight, MoveAway):
```lua
local LA_SV_ShortExtend = Inherit(CppObjectBase)
function LA_SV_ShortExtend:Ctor()
self:GenerateBehavior()
self:AddRootComposite("LaxSequencer", self:InstanceLaxSequencer())
self:AddTask("LaxSequencer", "ManeuverLevel", self:InstanceManeuverLevel(1.0, 1.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 1500.0, 0.3, false, 500.0))
self:AddTask("LaxSequencer", "ManeuverFlyStraight", self:InstanceManeuverFlyStraight("TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 1500.0, 1.0, false, 500.0))
self:AddTask("LaxSequencer", "MoveAwayFromTarget", self:InstanceMoveAwayFromTarget(1.5, "TargetActor", 1000.0, true))
self:EndGenerateBehavior()
end
return LA_SV_ShortExtend
```
(~2.8 s). The ace alternative is no extend at all: MoveAwayFromTarget_0000's two PursuerTargets.

## 7. Open questions for the native side
1. PursuerTarget args 3, 5, 6, 7, 8, 9, 10, 12/13, 14-16 and the FVector units.
2. The optional last float of the maneuvers (500..15000) and their flag (TurnNormal true x318).
3. The second bool of the Is* decorators and the last bool of DecoratorBlackboard*/Float (not an inversion).
4. TurnNormal arg3, TurnQuick arg5, TurnAdvanced args 1-2, FrontCross arg1, MoveAwayFromTarget arg3, MoveCenterAltitude arg2.
5. Composite semantics: Lax* vs plain, Continuation, RandomSelect with gated children, empty composites.
6. What IsKDSP1/2 and IsTrackingAirTarget read (rule 22: ordinary enemies never pass them with set 0400).
7. Whether RunBehavior works from a leaf and whether UniqueActionBehavior can be filled from a LuaSet.
