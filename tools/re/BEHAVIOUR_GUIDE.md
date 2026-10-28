# Writing custom enemy behaviours (2026-10-22)

How to make Survival's own AI behaviours. Everything here is static analysis of the game (exe and its 248 stock
behaviour scripts) unless it says "confirmed". The detail behind each section:
- `BEHAVIOUR_SCRIPTS.md`: every stock script surveyed: grammar, every factory's argument usage, slot patterns, how the
  designers tuned rookie vs ace sets, ready-made patterns. Data: `build/research/ai/survey/` (`factories.tsv`, trees).
- `BEHAVIOUR_NATIVE_MOVE.md`: the native side of the movement / pursuit / manoeuvre factories: each argument's
  member, unit and meaning; the full registration list (0x1473c04f0).
- `BEHAVIOUR_NATIVE_LOGIC.md`: the builder, how a tree runs, composites, decorators, probabilities, blackboard, the AI
  state machine, slot dispatch, KDS.
- `AI_BEHAVIOURS.md`: the behaviour sets (DT_NPC_LuaSet), pilot rank, per-plane AI data (Provoke, KDS, SurroundPursuit).

## 1. The pieces
- A **behaviour set** (DT_NPC_LuaSet row) names one script per **slot**: PursueTargetLua, MoveAwayFromTargetLua,
  EscapeFromPursuerLua, ProvokeLua (+ Near/Mid/Far), EvadeLua (+ MissileNear/Far, Gun, Special), BlackoutLua. The root
  tree LA_AIPlane switches on the plane's **AIState** and runs the slot's tree.
- The **native state machine** picks AIState every frame by a fixed priority (LOGIC.md 8): ReturnToWorld >
  AvoidObstacle > AvoidRangeAttack > ReturnToUnit / FollowFormation > Blackout > AttackAvoidance > CloudAvoidance >
  EscapeFromPursuer / MoveAwayFromTarget > Group > Provoke > PursueTarget > FollowFormation > Patrol. A script can't add
  states or slots; it shapes what the plane does *inside* one, and hands over with `InstanceSetMoveAwayFromTarget` /
  `InstanceSetStateEscapeFromPursuer` (one-shot requests the state machine takes up on its next decision).
- A **script** is a LuaScript asset with Lua source, run in the game's Lua 5.3 when the level loads (hard rules 20/21:
  a flight's behaviour is fixed at level load). Its tree is built once per module and shared by every plane using it.

## 2. Survival's pipeline (confirmed for LA_SV_MoveAway)
1. Write `mod/UE4SS/AC8SurvivalMode/Scripts/ai/LA_SV_<Name>.lua` (class name = file name, `return` it).
2. Add `LA_SV_<Name>` to `tools/build_survival.py LUA_SCRIPTS`: packaged as `/Game/LuaSource/SurvivalMode/AI/<name>`
   (the path the game's require() loads module `SurvivalMode.AI.<name>` from).
3. Name it in a slot of a set in main.lua `CFG.behaviour_sets` (made at the main menu by copying `base`'s row).
   Add the module to `GAME_LUA_STOCK` so the game-Lua helper counts its builds and errors (log: "game Lua: built ...").
4. Checks before a build: `python tools/checks/lua_check.py <file>` (syntax, 200-local limit) and, from
   `build/research/ai/survey/`, `python shapecheck.py <file>` (every node / argument shape must occur in a stock script).

## 3. Writing the tree (BEHAVIOUR_SCRIPTS.md 1, LOGIC.md 2-6)
- One `AddRootComposite(name, composite)` first; then `AddComposite / AddDecorator / AddTask / AddProbability(parent,
  name, self:InstanceX(...))`, every parent before its children, **unique names** (case-insensitive; never "Root").
- Decorators have exactly one child. Probabilities only directly under a RandomSelect, one child each; weights are
  relative. `InstanceWeightProbabilityPilotRank(w1..w5)` reads the plane's PilotRank (plane+0x252c) **every time**, so
  live rank writes (Survival's tiers and spikes) change the odds at once.
- Results only go up one level: a finished composite lets its parent move on. Selector / Sequencer / Continuation end
  the tick on an Abort (tree restarts next frame); the Lax variants carry on. A decorator's trailing bool = abort: it is
  re-checked every frame and aborts its subtree when it turns false.
- Silent failures (the game swallows Lua errors, rule 21): a misspelt parent or factory, a child added before its
  parent, two children under a decorator, a probability outside a RandomSelect, a misspelt enum (reads as 0). Likely
  crashes at level load: a nil node, a blackboard key the plane's blackboard doesn't have.
- Units: distances in **metres** (PursuerDistance blackboard: cm), durations seconds, SpdConstant / SpdRelative km/h,
  SpdCruise % of normal speed.

## 4. PursuerTarget, the attack task (MOVE.md 2)
`InstancePursuerTarget(duration, key, maxLead, leadMode, closeRange, noseCone, extend, extendCone, extendTime, rampTime,
headOnBreak, headOnCone, headOnRange, blockKDS, endOnKDS, useOffset, offset)`:
- `duration` s (0 = no limit); `key` the target ("TargetActor"); `maxLead` s of lead the aim uses (rookie 1-3, ace 10).
- `leadMode` true: aim at the target's LeadPointOffset; false: its PursuitPointOffset (or the SurroundPursuit offset).
- inside `closeRange` m and `noseCone` deg it stops predicting and matches the target's heading (settles behind).
- `extend*`: against the player only: outside the cone for `extendTime` s -> flies level that long.
- `headOnBreak/Cone/Range`: break off a head-on pass (true, 45, 2400 = the "tracking" pursuit).
- `blockKDS` keeps KDS from starting during the task; `endOnKDS` ends it when a KDS phase starts.
- **`useOffset` + `offset`**: aim at `offset` in the target's frame, metres (X forward). Ignored unless `useOffset` is
  true, so stock's `(-400, 0, 5)` does nothing; `(-250, 0, 5)` with `useOffset` = sit 250 m behind and 5 m above.
Speed is not an argument: it matches the target's speed plus a closing term, and slows to turn when the aim point is
behind within 2 km.

## 5. KDS (LOGIC.md 10)
Ace pursuits (PursueTarget_0400) only attack inside KDS phases or while tracking an air target (rule 22). A plane's
`bEnableKDSMode` comes from its DT_NPC_KDS row (on for fighters / attackers / multirole / UAVs); the *target* hands out
phases: at most one front and one back plane per target. So with many enemies at most two are ever in KDS: don't build
on KDS for ordinary enemies; Survival's pursuits block it (`blockKDS`).

## 6. Survival's behaviours
| script | slot (set NLID_SV_Fighter) | what | status |
|---|---|---|---|
| LA_SV_MoveAway | MoveAwayFromTargetLua | ~1.5 s break after an attack pass (stock 12.5 s) | confirmed in game |
| LA_SV_TailChase | PursueTargetLua | the stock fighter pursuit (PursueTarget_0011) plus a tail-chase branch: two 10 s pursuits 250 m behind the target (`useOffset`, ace lead 10, head-on break, KDS blocked) joined by a re-acquire turn; weighted by pilot rank (1: never, 2: 10 %, 3: 30 %, 4: 70 %, 5: always), so it grows with Survival's skill tiers and difficulty spikes. CFG.ai.tail_chase | built, untested |
| LA_SV_ProvokeNear | ProvokeNearLua | player close behind: break turn (all), brake-and-turn overshoot (rank 2+; only with the pursuer within 50 m, else a break), flare break (rank 3+; the break comes with no flare ready too), cobra bait (AI level 3+, CanCobra; else a break right), kulbit bait (AI level 4+, CanKulbit; else a break left) and scissors (AI level 4+): every pick moves, one move under 5 s (P5, tools/re/BEHAVIOUR_DIRECTOR.md unit 2). CFG.ai.reactions | built, untested |
| LA_SV_Escape | EscapeFromPursuerLua | rank-weighted: the stock 8 s level-and-straight run (rookies) or the aces' 2 s break up / down / sideways by altitude (EscapeFromPursuer_0400), then a 2 s level turn (P5: an altitude-gated pick that fails near the band's top or floor still turns). CFG.ai.reactions | built, untested |

The fighter roles' scripts (P1, tools/re/BEHAVIOUR_DIRECTOR.md unit 5; each set is NLID_0012_CP with these slots, the
rest stock; the role groups' world-data descs name them through their own behaviour rows):
| script | set and slot | what | status |
|---|---|---|---|
| LA_SV_LancerPass | NLID_SV_Lancer PursueTargetLua | one slashing pass: 6 s lead pursuit that extends when the target leaves its nose cone for 2 s and breaks off a head-on merge within 2.4 km, KDS blocked; 2 s through at full speed; SetMoveAwayFromTarget | built, untested |
| LA_SV_LancerZoom | NLID_SV_Lancer MoveAwayFromTargetLua | wings level, a 50 deg pull-up held 3 s (only below its unit band's top less 1 km: UnitAltitudeComparison), then a 4 km / 4 s extend; ~10 s | built, untested |
| LA_SV_LancerBreak | NLID_SV_Lancer ProvokeNearLua, ProvokeMidLua | tailed: level, 1 s straight at full power, a 3.5 G 180 deg reversal either side (Provoke_0400_l shortened, 4.7 s): never turns with you | built, untested |
| LA_SV_WolfDrag | NLID_SV_WolfLead ProvokeNearLua (the Wolf bait) | tailed: drags you straight or with a lazy jink, a little faster than you (SpdRelative to the pursuer), 3.5 s; its escape is the stock 8 s run | built, untested |
| LA_SV_WolfStrike | NLID_SV_WolfWing PursueTargetLua (the Wolf trap) | a gunfighter: a hard turn, then twice 12 s 200 m behind the target (own offset, never giving up, KDS blocked); at AI level 5 half its runs TailChase's "Super" | built, untested |
| LA_SV_SkirmPass | NLID_SV_Skirmisher PursueTargetLua | an 8 s pursuit under IsFireMissileFinished(false, abort): the first missile it fires aborts it; extends when the target leaves its cone, breaks a head-on merge within 3 km; the gate in a LaxSequencer of its own so the break-off always comes | built, untested |
| LA_SV_SkirmExtend | NLID_SV_Skirmisher MoveAwayFromTargetLua | MoveAwayFromTarget_0201's extend: out to 4.5 km (7.5 s), then MoveCenterAltitude 5 s | built, untested |

The AI level (AILevel, `InstanceWeightProbabilityAILevel`) is the flight's world-data LevelId / 100 (stock 200 = 2),
written by `SV_SetLevel(unit, level)` before Survival spawns it; Survival's ranks 6-10 (Mercenary, Legend, Demon,
Phantom, Reaper: main.lua CFG.tiers) use 3-5, so every AI-level-weighted branch above is off for ranks 1-5.

Patterns ready to adapt (BEHAVIOUR_SCRIPTS.md 6): quick-reaction provoke (Provoke_0400_s layout, pair with
EscapeFromPursuer_0400), short extend.

## 7. Ideas not tried yet
- Task objects are real UObjects built at level load (MOVE.md 6): writing new values at the task offsets after a
  FindAllOf could retune a running behaviour without a new set (e.g. per difficulty spike).
- Per-difficulty-spike behaviour: branch on pilot rank (as LA_SV_TailChase does), the only live input a tree reads
  that Survival already sets.
