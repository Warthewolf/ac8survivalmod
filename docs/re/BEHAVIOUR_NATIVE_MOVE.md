# AC8 AI behaviour tasks: native movement factories (static RE, 2026-10-22)

Companion to `AI_BEHAVIOURS.md` (what the LA_ scripts are) and AGENTS.md rules 20-22. This file covers the **native
side** of the movement / maneuver nodes the LA_ scripts build: where each `self:InstanceXxx(...)` Lua call lands, which
member each Lua argument is written to, and how the task's Enter / Tick / Update code reads it.
Everything here is from disassembly of `AceCombat8.exe` only; nothing has been tested in game.
Scratch, scripts and full disassembly dumps: `build/research/ai/native_move/` (`analyze.py`, `cls.py`, `a_*.txt`,
`all/*.txt`, `fn/*.txt`, `steer.txt`, `pt_tick.txt`, `registration.tsv`).

Confidence tags: **[C]** = confirmed in disassembly (the store and the read were both seen), **[I]** = inferred (the read
was seen but the meaning is a reading of the math / naming), **[?]** = unknown or not traced.

## 1. How the bindings work

* The names (`"InstancePursuerTarget"`, ...) at file offset ~0xcb67ae0 (VA 0x14cb67f20-0x14cb688f8) are referenced only
  from **one function, 0x1473c04f0** (the CppObjectBase method-table builder; also 0x1473c01d0 registers the `AIState` /
  slot name strings). It fills a stack array of `{const char* name, lua_CFunction fn}` pairs (16 bytes each, name first)
  and hands each to 0x144ea17e0 (registers it on the class metatable). [C]
* Each `fn` is a **Lua wrapper** (`int f(lua_State*)`): it reads the Lua arguments (self is index 1, read by
  0x144ed8d00(L, 1); args from index 2 with 0x144ea18c0 = string -> FName, 0x1450a18e0 = number -> float, inline
  integer reads for enums (Lua 5.3 integer tag 0x13), inline truthiness for bools, or a whole-tuple reader such as
  0x1473c96b0 / 0x1473c9a50), calls a **C++ factory** `UObject* Factory(CppObjectBase* self, args...)`, then pushes the
  result with 0x144ed4000. Missing trailing Lua arguments read as 0 / false / None. [C]
* Every factory does `NewObject<ULiveAITaskXxx>(outer = *0x14e431a78)` (0x141abd5c0 + StaticClass + 0x141abd340), then
  writes the arguments into the object. Blackboard-key factories (classes derived from `LiveAITaskBlackboard`) write the
  key FName into an `FBlackboardKeySelector` at **+0x70** (SelectedKeyName at **+0x80**) and resolve it against
  `self+0x88` (the tree's blackboard asset) with 0x144fcd010. [C]
* So the parameters live in **unreflected members of the task UObject** (`LiveAITaskPursuerTarget` reflects only
  Parent / ChildList). The task objects are real UObjects built once per tree (rule 20), so they exist in GUObjectArray
  and could be found by class name at run time (untested idea, see section 6).
* Task virtuals (same slot layout for every task; base = `LiveAITaskBase`, vtable 0x14c59d2c8, size 0x70):

| vtable slot | role | return value (`ELiveAINodeResult` from usmap: 0 Run, 1 Failed, 2 Complete, 3 Abort) |
|---|---|---|
| 0x2c8 | GetNodeName (writes the wide name, e.g. "PursuerTarget") | |
| 0x2d0 | OnEnter(task, runner) | 0 started, 1 failed, 2 complete at once |
| 0x2d8 | Tick(task, runner, ?, dt in xmm2) | 0 Run, 1 Failed, 2 Complete |
| 0x2e0 | OnExit | |
| 0x2e8 | OnAbort (PursuerTarget, Kulbit, Cobra...) | 3 Abort |
| 0x2f0 | maneuvers only: Update(task, ctx, dt) (called by the shared maneuver Tick 0x147bcaf30) | |
| 0x2f8 | maneuvers only: GetSpeedMemory(ctx) -> per-instance speed record | |

  `runner+0x90` = the AI plane (`ALiveAIPlane`), `runner+0x100` = node key, 0x147cf2090(runner, key) = per-node
  instance memory. [C]

### Units (important)
* Distances passed from Lua to these movement tasks are **metres**; factories (or Enter) multiply by 100 to UE cm:
  PursuerTarget a5, a13, a17 (FVector); MoveAwayFromTarget a3; MoveToTarget a3, a4; FrontCross a1; the SpdRelative
  range of every maneuver. [C] (Exception: PursuerTarget's a5 is multiplied by 100 at the call site in Tick.) [C]
* Angles are **degrees** (converted with 0.0174533) unless noted. Times are **seconds** (compared with accumulated dt). [C]
* Speeds (`ELiveAIManeuverSpeedType` = SpdConstant 0, SpdCruise 1, SpdRelative 2, SpdNoAdjustment 3; from the Lua enum
  registration 0x1473bf220 and usmap) [C]:
  * **SpdConstant**: value in **km/h** (Enter multiplies by 0.277778 -> m/s). `SpdConstant, 1000.0` = 1000 km/h. [C]
  * **SpdCruise**: **percent of the plane's own normal speed** (`plane+0x2bd4` x value x 0.01). 100 = normal speed. [C]
  * **SpdRelative**: **km/h added to the speed-reference actor's speed** (the maneuver's blackboard key, e.g.
    "PursuerActor"); the trailing float is a **range in metres**; the correction strength is (dist/range)^3 capped at 1, so
    close to the reference the AI barely adjusts. The bool before it, if true, flips the sign of the delta at random
    (`rand() & 1`). [C] (sign flip [I])
  * **SpdNoAdjustment**: no throttle change. Also used when the reference actor becomes invalid. [C]
  * Control is bang-bang on the plane's throttle (`plane+0x2a98`) / brake (`plane+0x2a9c`) inputs against the current
    speed `plane+0x2a88` (m/s). [C]

### Plane / target fields these tasks touch
| offset | owner | meaning | conf. |
|---|---|---|---|
| target+0x678 | ALiveGameObject.**PursuitPointOffset** (FVector, reflected) | aim point for pure/lag pursuit (target space) | [C] offset, [I] use |
| target+0x690 | ALiveGameObject.**LeadPointOffset** (FVector, reflected) | aim point for lead pursuit (target space) | [C] offset, [I] use |
| target+0x6c0 | ALiveGameObject.FrontViewHalfConeAngle | "am I in front of the target" cone | [C] |
| target+0xda8 | ALiveGameObject.HealthInternal (int, x0.1 = HP) | pursuit ends when the target is dead | [C] |
| plane+0x3c0 | ALiveGameObject.Speed (cm/s) | own speed for the lead-time calculation | [C] offset |
| plane+0x261c..0x2634 | ALiveAIPlane.SurroundPursuitMin/MaxRange, ParamA-C, ResetTimeMin/Max | | [C] |
| plane+0x26a8 / 0x26b0 / 0x26c8 | unreflected: surround-pursuit active flag / offset vector (cm) / reset timer | random offset from the SurroundPursuit row, cleared when the timer runs out (0x147cd2b8f, 0x147cce91c) | [C] |
| plane+0x2670 / 0x2678 | ALiveAIPlane.EscapeFromPursuerActor / MoveAwayFromTargetActor | written by the Set* tasks | [C] |
| plane+0x2a70 / 0x2a78 | pitch / roll attitude (rad) | | [C] |
| plane+0x2a88 | current speed (m/s) | | [I] |
| plane+0x2a8c / 0x2a90 / 0x2a94 | pitch / yaw / roll stick inputs (-1..1) | | [C] |
| plane+0x2a98 / 0x2a9c | throttle / brake inputs (0..1) | | [C] |
| plane+0x2b28 / 0x2b2c | pitch / yaw rotation accumulated since the maneuver started (rad) | | [C] |
| plane+0x2bd4 / 0x2bd8 / 0x2bdc / 0x2be4 / 0x2be8 | normal / max / min speed (m/s), accel / decel | | [I] |
| plane+0x3534..0x3548 | attitude-hold targets: pitch angle+rate, roll angle+rate, ... (set by 0x147cd2f90 roll-to, 0x147cd3000 / 0x147cd3080 / 0x147cd3130 / 0x147cd3180 pitch/roll-to) | | [C] |
| plane+0x6c8 | per-plane maneuver rate factor (multiplies every stick / rate command) | | [C] use, [?] source (difficulty / NPC row) |
| plane+0x35a9 | ALiveAIPlane.**bEnableKDSMode** | | [C] |
| plane+0x35b0 / 0x35b4 | FrontEntranceTimeLimit / FrontLeadTimeLimit | KDS phase timers | [C] |
| plane+0x35b9 | unreflected "KDS may start" flag (default 1; the KDS trigger 0x147d2de5b requires it) | | [C] |
| plane+0x35ba | unreflected KDS phase: 0 none, 1-2 = P1 (IsKDSP1), 3-4 = P2 (IsKDSP2), set by 0x147cd5100 | | [C] |

## 2. InstancePursuerTarget (highest priority)

Lua wrapper **0x1473c3930**, factory **0x147bbace0**, class `LiveAITaskPursuerTarget` (size 0xc8, StaticClass
0x146d6c3c0, ctor 0x146d71650, vtable 0x14c5ab040). Enter **0x147bd5a40**, Tick **0x147bd5b20**, Exit 0x147bd6990,
Abort 0x147bd6ac0. The Tick builds an aim point and calls the shared pursuit steering **0x147cd16e0**
`Steer(plane, target, &aim, a3, a5*100, dt, a6, a4, true)`.
Instance memory: +0xcc "target outside cone" timer, +0xd0 elapsed time, +0xd4 "target is a LivePlayerPlane",
+0xd5 saved KDS-allowed flag.

Example (LA_PursueTarget_0011): `InstancePursuerTarget(15.0, "TargetActor", 3.0, false, 2000.0, 20.0, false, 120.0,
3.0, 4.0, false, 60.0, 3000.0, true, true, false, FVector.New(-400.0, 0.0, 5.0))`

| # | Lua type | member | ctor default | meaning | conf. |
|---|---|---|---|---|---|
| 1 | number | +0x70 f32 | 0 | **Duration (s)**. If > 0 the task completes (2) once elapsed > a1. 0 = no time limit. | [C] |
| 2 | string | +0x74 FName | None | **Blackboard key of the target** ("TargetActor", "LocalPlayer", "WingmanAttackActor"...). Looked up each tick (0x147c99ec0); missing -> Complete, dead (HealthInternal <= 0) -> Complete. | [C] |
| 3 | number | +0x7c f32 | 1.0 | **Max lead / look-ahead time (s)** for the predictive aim: aim += targetForward x targetSpeed x min(distance / ownSpeed, a3). Bigger = cuts the corner harder, intercept-style; small = chases where the target is. 100 in LA_LastTGT / unique actions (= no cap). | [C] math, [I] wording |
| 4 | boolean | +0x80 u8 | false | **Lead pursuit**. true: aim at the target's **LeadPointOffset** point (or a17 when a16), no surround offset, and the "close" test becomes "I am within a5 in front of the target's FrontViewHalfConeAngle" (head-on). false: aim at the target's **PursuitPointOffset** point (behind), or the plane's **surround-pursuit offset** (SurroundPursuit row: random 100-300 m offset in target space, re-rolled every ResetTime) when active, with aim.z kept >= ground + 1 m; the "close" test is "distance to aim < a5". Also passed to Steer. | [C] branches, [I] lead/lag naming |
| 5 | number | +0x84 f32 | 500 | **Close-range distance (m)** (x100 in Tick). Inside it (and target within a6 of the nose) Steer stops predicting and flies a **heading blend**: within 60 m of the aim point it copies the target's own heading; farther out it blends from the target's heading toward the line of sight by the lateral offset (weight (lateral - 7 m) x 0.0005 per cm: 0 at 7 m, full at 27 m). I.e. it settles onto the target's flight path instead of pulling lead. | [C] branch, [I] interpretation |
| 6 | number | +0x88 f32 | 20 | **Nose cone (deg)**: the close-range mode needs the aim within a6 of the nose; Steer also uses a6 as the roll-error tolerance below which it adds full back stick (bank-then-pull). Smaller = pulls only when well aligned. | [C] uses, [I] wording |
| 7 | boolean | +0x8c u8 | false | **Extend-when-behind** switch. Only against **player** targets (`+0xd4` = target IsA LivePlayerPlane). | [C] |
| 8 | number | +0x90 f32 | 120 | Cone for a7: if dot(ownForward, dirToTarget) < **cosf(a8)** the "behind" timer runs. NB the code calls cosf on the raw value (no deg->rad), so 120 -> 35.5 deg off the nose, 150 -> 45.6 deg, 130 -> 106.6 deg, 6 -> 16.2 deg. Only stored when a7 is true. | [C] (the missing conversion looks like a game bug) |
| 9 | number | +0x94 f32 | 3 | Time for a7 (s): after the target has been outside the a8 cone for a9 s, the AI stops steering and flies **wings-level at its normal speed** (roll 0, pitch 0, throttle to plane+0x2bd4 at strength 0.25) until the timer reaches 2 x a9, then resets and turns again. Only stored when a7 is true. | [C] |
| 10 | number | +0x98 f32 | 4 | Ramp start (s): once elapsed > a10, writes `plane+0x2718 = min((elapsed - a10)/a10, 1)`; reset to 0 on Enter / Exit. Reader not identified (one candidate passes it as a float to a virtual on a linked object, 0x147c7deef). Wingman sets use 500 (never ramps). | [C] write, [?] effect |
| 11 | boolean | +0x9c u8 | false | **Head-on offset** switch. | [C] |
| 12 | number | +0xa0 f32 | 60 | Head-on cone (deg): active while the two headings are within a12 of exactly head-on (dot(ownFwd, targetFwd) < cos(180 - a12)) and the target is ahead. Only stored when a11. | [C] math, [I] wording |
| 13 | number | +0xa4 f32 | 3000 | Head-on range (m): full effect inside a13/2, none beyond a13. Weight w = cbrt(headOnFactor x closeness) (powf 1/3); the aim point is blended toward a sideways point of length d x tan(180 - a12) on the plane's right axis (the vector is not anchored to the plane's position in the code, so in practice it is a hard break-off). Only stored when a11. | [C] math, [I] effect |
| 14 | boolean | +0xa8 u8 | false | **Block KDS**: on Enter saves and clears plane+0x35b9 (KDS may not start), restores it on Exit / Abort. | [C] |
| 15 | boolean | +0xa9 u8 | false | **End on KDS**: Complete as soon as bEnableKDSMode and a KDS phase is running (plane+0x35ba != 0). | [C] |
| 16 | boolean | +0xaa u8 | false | **Use the fixed offset a17** instead of the target's Lead/PursuitPointOffset (and instead of the surround offset). | [C] |
| 17 | FVector | +0xb0/+0xb8/+0xc0 f64 | (-400, 0, 5) raw | **Aim offset in target space, metres** (x100 in the factory; transformed with the target's full transform: X forward, Y right, Z up). **Ignored unless a16 = true.** So the stock (-400, 0, 5) on every enemy pursuit does nothing; it is not "4 m behind" either (it would be 400 m behind, 5 m up). Used with a16 in LA_LastTGT (-200, 0, 0: 200 m behind the player), LA_BarrierCharge (150 m ahead), wingman unique actions (1500 / 1800 m ahead, -300 m behind). | [C] |

**What makes it chase harder / sit on the tail** (all from the code above):
* a4 = false + a target whose PursuitPointOffset is behind it = tail chase; a16 = true with a17 = (-X, 0, 0) forces "X m
  behind the target" regardless of the blueprint offsets (what LA_LastTGT does for aces turning on the player).
* a3 is the lead-time cap: higher = more aggressive intercept (shortcuts the target's turn); LA_LastTGT uses 100.
* a5 / a6: when inside a5 and roughly aligned (a6), the AI copies the target's heading (stays behind instead of
  overshooting). Large a5 (2000-3500 m in enemy sets) = it starts matching the target's flight path early.
* a7 / a8 / a9: with a7 = true the AI gives up turning after a9 s when the player is outside the (radian-bugged) a8 cone
  and extends; a7 = false = it keeps turning into the player indefinitely.
* a1 caps how long one pursuit node runs before the sequencer moves on (to SetMoveAwayFromTarget in most sets).
* Speed is not a parameter: Steer always matches the target's speed with a closure term
  sqrt(2 x accel x distance-ahead) (0x147cd2970, clamped to the plane's min/max speed), and drops to min speed when the
  aim point is behind it within 2 km (tighter turn). So the airframe's accel/decel/min/max speed decide how fast it
  closes. [C]
* Steer path: if `plane->vfunc[0xaf8]()` is true (large-plane / simple mode [?]) it just points the nose with
  0x147cce570. Otherwise it banks toward the aim point (roll-to-angle) and pulls when the roll error is below a6. [C]

## 3. Other requested factories

Common maneuver base `LiveAITaskManeuverFlyStraight` (size 0xb8, vtable 0x14c598950, Enter 0x147bcad20, Tick
0x147bcaf30 -> vfunc 0x2f0, Update 0x147bcafe0, Exit 0x147bcb270). Members shared by every maneuver that takes the
trailing `(key, speedType, speed, duration, bool, range)` block ("speed block" below):

| member | meaning | conf. |
|---|---|---|
| +0x70/+0x80 | blackboard key selector: the **speed-reference actor** for SpdRelative (TurnAdvanced also steers toward it, FrontCross crosses in front of it) | [C] |
| +0x98 f32 | **duration (s)**: Update returns Complete when elapsed >= duration (> 0); 0 = until the maneuver's own end condition | [C] |
| +0x9c u8 | speed type | [C] |
| +0xa0 / +0xa4 / +0xa8 | speed value for SpdConstant (km/h) / SpdCruise (% normal) / SpdRelative (km/h delta); only the one matching the type is written | [C] |
| +0xac u8 | SpdRelative random sign flip | [C] store, [I] meaning |
| +0xb0 f32 | SpdRelative range (m, x100 at Enter) | [C] |

"Rate" below = a stick / rate fraction multiplied by plane+0x6c8 and clamped to [-1, 1]. Roll / pitch "to angle" means the
attitude-hold helpers (0x147cd2f90 roll-to, 0x147cd3000 pitch-to). "Within 2 deg" end conditions are attitude checks.

### InstanceManeuverFlyStraight(key, speedType, speed, duration, bool, range)
Wrapper 0x1473c4390, factory 0x147bbbf00, class LiveAITaskManeuverFlyStraight. Just the speed block: holds speed, no
attitude change, ends at duration. [C]

### InstanceManeuverLevel(pitchRate, rollRate, + speed block)
Wrapper 0x1473c45f0, factory 0x147bbc410, LiveAITaskManeuverLevel (0xc0, vt 0x14c5ad730, Update 0x147bcf270).
a1 +0xb8 pitch rate, a2 +0xbc roll rate. Rolls wings level at a2; when |roll| <= 2 deg also pitches to 0 at a1;
Complete when |pitch| <= 2 deg (or duration). [C]

### InstanceManeuverPitch(pitchInput, angle, + speed block)
Wrapper 0x1473c46a0, factory 0x147bbc5b0, LiveAITaskManeuverPitch (vt 0x14c5adb00, Update 0x147bd0a80).
a1 +0xb8 pitch stick (sign = up/down), a2 +0xbc **total pitch rotation (deg)** (180 = half loop). Pulls a1 until the
accumulated pitch rotation reaches |a2|; ends by duration. Large-plane path: 0x147cce570. [C]

### InstanceManeuverRoll(rollRate, bankAngle, + speed block)
Wrapper 0x1473c4750, factory 0x147bbc750, LiveAITaskManeuverRoll (vt 0x14c5ac170, Update 0x147bd1bb0).
a1 +0xb8 roll rate, a2 +0xbc target bank (deg). Complete when within 2 deg. [C]

### InstanceManeuverYaw(rudderInput, angle, + speed block)
Wrapper 0x1473c48f0, factory 0x147bbd1c0, LiveAITaskManeuverYaw (vt 0x14c5a9750, Update 0x147bd3990).
a1 +0xb8 rudder (yaw stick = -a1 x rate factor), a2 +0xbc yaw rotation (deg); Complete when accumulated yaw >= |a2|. [C]

### InstanceManeuverTurnNormal(pitchInput, pitchAngle, rollRate, bankAngle, + speed block)
Wrapper 0x1473c48c0 (-> 0x1473c8990), factory 0x147bbcc50, LiveAITaskManeuverTurnNormal (0xc8, vt 0x14c5ac570,
Enter 0x147bd2be0, Update 0x147bd2cc0). a1 +0xb8 pitch stick, a2 +0xbc pitch rotation (deg), a3 +0xc0 roll rate,
a4 +0xc4 bank (deg). Phase 0: roll to a4 at a3; within 2 deg -> phase 1: pull a1 until |a2| deg of pitch rotation =
a classic bank-and-pull turn of about a2 degrees. Stock `(1.5, 75.0, 1.5, -90.0, ...)` = knife-edge left, 75 deg turn. [C]

### InstanceManeuverTurnQuick(pitchRate, pitchAngle, rollRate, bankAngle, bankTolerance, + speed block)
Wrapper 0x1473c48d0 (-> 0x1473c8bb0), factory 0x147bbce20, LiveAITaskManeuverTurnQuick (0xd0, vt 0x14c5ac900,
Update 0x147bd3010). a1 +0xb8, a2 +0xbc, a3 +0xc0, a4 +0xc4, a5 +0xc8. Rolls to a4 at a3 and, once the bank error is
within 2 deg or within a5 deg (wrapped), pitches toward attitude a2 at rate a1 (while the accumulated pitch < |a2|);
Complete when pitch within 2 deg of a2 and bank within 2 deg. I.e. roll and pull overlap (a5 = how early the pull starts). [C]

### InstanceManeuverTurnAdvanced(pitchRate, rollRate, + speed block)
Wrapper 0x1473c4810, factory 0x147bbcab0, LiveAITaskManeuverTurnAdvanced (vt 0x14c5ad390, Update 0x147bd2580).
a1 +0xb8 pitch rate, a2 +0xbc roll rate. Turns to face the **speed-block key actor**: transforms its position into
local space, rolls toward it (atan2) at a2 until within 5 deg, then pitches toward it at a1. [C] steps, [I] purpose.

### InstanceManeuverTurnToPoint(FVector point, f, + speed block)  (not used by stock scripts)
Wrapper 0x1473c48e0 (-> 0x1473c8de0), factory 0x147bbd000, LiveAITaskManeuverTurnToPoint (0xd8, vt 0x14c5a93c0,
Update 0x147bd3370). a1 FVector -> +0xb8/+0xc0/+0xc8 (doubles), a2 -> +0xd0. Same shape as TurnAdvanced toward a fixed
point. [C] stores, [I] behaviour; unit of the point not checked.

### InstanceManeuverBarrelRoll(int dir, pitchInput, rollInput, + speed block)
Wrapper 0x1473c44f0 (-> 0x1473c85a0), factory 0x147bbc070, LiveAITaskManeuverBarrelRoll (0xc8, vt 0x14c59b860,
Update 0x147bc9650). a1 int +0xb8 direction (+1/-1), a2 +0xbc pitch stick, a3 +0xc0 roll stick. Holds roll stick
-(dir x a3) and pitch stick a2 for the duration (no other end condition). [C]

### InstanceManeuverAileronRoll(f, f, f)  (not used by stock scripts)
Wrapper 0x1473c42d0, factory 0x147bbbe00, LiveAITaskManeuverAileronRoll (0x80, derives from LiveAITaskBase, vt
0x14c59c030, Enter 0x147bc8420, Tick 0x147bc84e0). a1 +0x70, a2 +0x74, a3 +0x78. [C] stores, [?] meaning.

### InstanceManeuverSlalom(yawGain, rollRate, bankAngle, + speed block)
Wrapper 0x1473c4800 (-> 0x1473c8790), factory 0x147bbc8f0, LiveAITaskManeuverSlalom (0xc8, vt 0x14c5ab380, Update
0x147bd1e10). a1 +0xb8 yaw coupling gain (adds |a1| x bank/a3 x rate to plane+0x2b34), a2 +0xbc roll rate, a3 +0xc0
bank (deg). Rolls to a3; Complete only when the duration is over AND the bank is reached. [C] stores/flow, [I] a1 name.

### InstanceManeuverFrontCross(distance, bankAngle, bool, + speed block)
Wrapper 0x1473c49a0 (-> 0x1473c8fc0), factory 0x147bbd360, LiveAITaskManeuverFrontCross (0xc8, vt 0x14c5998f0, Enter
0x147bcb3c0, Update 0x147bcb770). a1 +0xb8 distance (m, x100 in the factory), a2 +0xbc bank (deg), a3 +0xc0 bool.
Steers to a point a1 ahead of the **key actor's nose** (the pursuer), later re-aimed with 0.2 x a1 look-ahead and a
200-1000 m clamp: a defensive cross in front of the attacker. [C] a1 use, [I] a2/a3.

### InstanceManeuverCobraTurn(bool) / InstanceManeuverPugachevsCobra(bool, bool) / InstanceManeuverFlatSpin(f, f)
* Cobra: wrapper 0x1473c49b0, factory 0x147bbd520, LiveAITaskManeuverCobraTurn (0x78, base
  LiveAITaskManeuverStateUninterruptible, vt 0x14c599150, Update 0x147bca1c0). a1 -> +0x70: picks one of two
  hard-coded recovery profiles (0x147cd31d0 with 0.75/1.8/0.2/0.8). No speed block. [C] store, [I] meaning.
* Pugachev: wrapper 0x1473c4af0, factory 0x147bbd800, (vt 0x14c5ade50, Update 0x147bd0d90). a1 -> +0x70, a2 -> +0x71,
  both select branches of a fixed -110 deg / +80 deg pitch sequence. [C] stores, [I] meaning.
* FlatSpin (unused in stock): wrapper 0x1473c4a30, factory 0x147bbd5f0 (vt 0x14c598570, Update 0x147bca670).
  a1 -> +0x70, a2 -> +0x74 (a2 x 360 deg = spin amount [I]).
* These "StateUninterruptible" maneuvers check the plane's bCanManeuverPugachevsCobra (+0x28d0) / bCanManeuverKulbit
  (+0x28d1) through the CanCobra / CanKulbit decorators, not in the task. [I]

### InstanceManeuverKulbit(bool, bool, bool [, key, weapon, tMin, tMax])
Wrapper 0x1473c4ae0 (-> 0x1473c91e0), factory 0x147bbd6d0, LiveAITaskManeuverKulbit (0x88, vt 0x14c599c40, Enter
0x147bcc680, Update 0x147bcc7e0). a1 +0x70 (recovery profile select), a2 +0x71 (if set, a pre-step 0x147cd03b0 with 5.0
first [I]), a3 +0x72 **fire during the kulbit**, a4 FName +0x74 target key, a5 u8 +0x7c `ELiveWeaponNumber`
(WN_WEAPON_1..4 = 0..3), a6 +0x80 / a7 +0x84 fire-time window (Enter picks rand() in [a6, a7] s). [C] stores and the
random window, [I] the rest.

### InstanceManeuverKulbitToprak(13 args)
Wrapper 0x1473c4ba0, factory 0x147bbd8e0, LiveAITaskManeuverKulbitToprak (0xa8, vt 0x14c5994a0, Update 0x147bccda0).
Lua `(true, true, 80.0, 1.0, 170.0, 24.0, -135.0, 1.0, true, "TargetActor", WN_WEAPON_4, 1.5, 2.0)` ->
a1 +0x70 u8, a2 +0x71 u8, a3 +0x74, a4 +0x78, a5 +0x7c, a6 +0x80, a7 +0x84, a8 +0x88 (floats), a9 +0x8c u8,
a10 +0x90 FName key, a11 +0x98 u8 weapon, a12 +0x9c, a13 +0xa0. Angles 80/170/-135 look like pitch/roll stage targets
and 1.5-2.0 the fire window (as Kulbit). [C] stores, [I] meaning.

### InstanceMoveAwayFromTarget(timeout, key, distance, completeOnTimeout)
Wrapper 0x1473c3b30, factory 0x147bbb010, LiveAITaskMoveAwayFromTarget (0x88, base LiveAITaskBase, vt 0x14c5a9b00,
Enter 0x147bd3b70, Tick 0x147bd3c50).
| # | type | member | meaning | conf. |
|---|---|---|---|---|
| 1 | number | +0x70 | timeout (s); 0 = none | [C] |
| 2 | string | +0x74 FName | blackboard key of the actor to get away from | [C] |
| 3 | number | +0x7c (x100) | **extend distance (m)**: Complete when farther than this from the actor | [C] |
| 4 | boolean | +0x80 | result on timeout: true -> Complete, false -> Failed (missing arg = false) | [C] |
Flies to a point away from the actor (fly-to helper 0x147cd0480, min altitude via 0x147c93000), throttle to normal speed
at 0.25 strength. [C]

### InstanceSetMoveAwayFromTarget(key) / InstanceSetStateEscapeFromPursuer(key)
Wrappers 0x1473c4cd0 / 0x1473c4c90, factories 0x147bbdb30 / 0x147bbda70, classes LiveAITaskSetMoveAwayFromTarget /
LiveAITaskSetStateEscapeFromPursuer (0x98, vt 0x14c5aa1d0 / 0x14c5a9e80, Enter 0x147bd70d0 / 0x147bd6de0).
**The Lua argument is never read** (the wrapper only reads self), so "TargetActor", "SelfActor" and "PursuerActor" all do
the same. Enter resolves the class's own default key selector (SelectedKeyName None, filter = Actor; UE then takes the
first actor key of the blackboard asset), writes that actor to ALiveAIPlane.**MoveAwayFromTargetActor** (+0x2678) /
**EscapeFromPursuerActor** (+0x2670) and returns Complete (Failed if nothing resolves). The AIState switch itself is done
elsewhere (UpdateAIState / the state component). [C] (which key UE picks: [I])

### InstanceMoveToTarget(key, leadTime, approachDist, tooCloseDist)
Wrapper 0x1473c3a70, factory 0x147bbaf00, LiveAITaskMoveToTarget (0x88, vt 0x14c5a9040, Enter 0x147bd4c10, Tick
0x147bd4d50). a1 FName +0x70 key; a2 +0x78 max prediction time (s) (aim = target + fwd x speed x min(a2, dist/speed));
a3 +0x7c (x100) approach distance (speed blend / phase change); a4 +0x80 (x100) "too close" distance -> phase 3 (pull
away, 30 deg nose command). State machine in memory +0xe0. Stock `("TargetActor", 5.0, 1500.0, 200.0)`. [C] stores,
[I] phase meanings.

### InstanceReturnToUnitCircle(speedFactor)
Wrapper 0x1473c3700, factory 0x147bbab20, LiveAITaskManeuverReturnToUnitCircle (0x78; vtable **0x14c5abe30**, Enter
0x147bd1140, Tick 0x147bd11e0). a1 +0x70 (default 1.5) = throttle target = plane normal speed x a1 while it flies back
into its unit's area (fly-to helper 0x147cd0480). Stock 1.5 = 150 % normal speed. [C]

### InstanceActivateFlares(key, onlyVsPlayer)
Wrapper 0x1473c3ed0, factory 0x147bbb4e0, LiveAITaskActivateFlares (0xa0, base LiveAITaskBlackboard, vt 0x14c59c398,
Enter 0x147bbf360, Tick 0x147bbf4e0). a1 key +0x70/+0x80 (stored actor in memory +0x140), a2 bool +0x98.
Enter: if `bPermissionToUseFlares` (+0x10d6) or `bCanActivateFlares` (+0x1130) is false -> Complete without firing; if the
FCS has no ready flare weapon -> Failed. Tick: a2 = true fires flares (0x147c91070) **only if the key actor is a
LivePlayerPlane**; a2 = false fires always; returns Complete. So `("PursuerActor", true)` = flare only when a player is
the threat. [C]

### InstanceWaitTime(waitTime, timeout)
Wrapper 0x1473c4120, factory 0x147bbba90, LiveAITaskWaitTime (0x78, vt 0x14c5a8390, Enter 0x15c899670 (relocated),
Tick 0x147bd87e0). a1 +0x70, a2 +0x74, copied to memory +0x2e4 / +0x2e8 and counted down together: a1 > 0 and
reaches 0 -> Complete; a2 reaches 0 -> Abort (3). `(0.0, 600.0)` = wait 600 s then Abort. [C]

## 4. Full registration list (0x1473c04f0)

`lua fn` = the lua_CFunction registered under the name (`-> x` = it is a jmp thunk to x). `factory` = the C++ function it
calls. Class names come from the StaticClass call inside the factory. "-" = not a factory (tree-building method) or not
resolved by the script (the Blackboard decorator factories create their class through a helper; the decorator agent
should follow 0x147bbdcd0 / 0x147bbdda0 / 0x147bbde20 / 0x147bbdf00 by hand). BlackboardInt and BlackboardEnum are
registered with **the same function** (0x1473c4e70 = `lea rdx, 0x147bbdda0; jmp 0x1473c73a0`).

| name | lua fn | factory | class (size) |
|---|---|---|---|
| GenerateBehavior | 0x1473c2f40 | - | - |
| EndGenerateBehavior | 0x1473c2f60 | - | - |
| AddRootComposite | 0x1473c2f80 | - | - |
| AddComposite | 0x1473c2ff0 | - | - |
| AddTask | 0x1473c3080 | - | - |
| AddDecorator | 0x1473c31a0 | - | - |
| AddProbability | 0x1473c32c0 | - | - |
| InstanceSelector | 0x1473c33e0 | 0x147bba2e0 | LiveAICompositeSelector (0x50) |
| InstanceLaxSelector | 0x1473c3420 | 0x147bba3a0 | LiveAICompositeLaxSelector (0x50) |
| InstanceSequencer | 0x1473c3460 | 0x147bba460 | LiveAICompositeSequencer (0x50) |
| InstanceLaxSequencer | 0x1473c34a0 | 0x147bba520 | LiveAICompositeLaxSequencer (0x50) |
| InstanceRandomSelect | 0x1473c34e0 | 0x147bba5e0 | LiveAICompositeRandomSelect (0x50) |
| InstanceContinuation | 0x1473c3520 | 0x147bba6a0 | LiveAICompositeContinuation (0x50) |
| InstanceLaxContinuation | 0x1473c3560 | 0x147bba760 | LiveAICompositeLaxContinuation (0x50) |
| InstanceParallel | 0x1473c35a0 | 0x147bba820 | LiveAICompositeParallel (0x50) |
| InstanceRunBehavior | 0x1473c35e0 | 0x147bbbd30 | LiveAITaskCommonRunBehavior (0x78) |
| InstanceOutOfWorldReaction | 0x1473c3640 | 0x147bba8e0 | LiveAITaskManeuverOutOfWorldReaction (0x70) |
| InstanceAvoidObstacle | 0x1473c3680 | 0x147bba9a0 | LiveAITaskManeuverAvoidObstacle (0x70) |
| InstanceAvoidRangeAttack | 0x1473c36c0 | 0x147bbaa60 | LiveAITaskAvoidRangeAttack (0x70) |
| InstanceReturnToUnitCircle | 0x1473c3700 | 0x147bbab20 | LiveAITaskManeuverReturnToUnitCircle (0x78) |
| InstancePatrol | 0x1473c3790 | 0x147bbac00 | LiveAITaskManeuverPatrol (0x78) |
| InstanceUpdateAIState | 0x1473c3820 | 0x147bce6e0 | LiveAITaskCommonExecuteFunction (0x78) |
| InstancePostAIState | 0x1473c3860 | 0x147bce6e0 | LiveAITaskCommonExecuteFunction (0x78) |
| InstanceExecuteFunction | 0x1473c38a0 | 0x147bce6e0 | LiveAITaskCommonExecuteFunction (0x78) |
| InstancePursuerTarget | 0x1473c3930 | 0x147bbace0 | LiveAITaskPursuerTarget (0xc8) |
| InstanceMoveToTarget | 0x1473c3a70 | 0x147bbaf00 | LiveAITaskMoveToTarget (0x88) |
| InstanceMoveAwayFromTarget | 0x1473c3b30 | 0x147bbb010 | LiveAITaskMoveAwayFromTarget (0x88) |
| InstanceMoveCenterAltitude | 0x1473c3c40 | 0x147bbb120 | LiveAITaskMoveCenterAltitude (0x80) |
| InstanceLevelPlane | 0x1473c3d20 | 0x147bbb220 | LiveAITaskLevelPlane (0x70) |
| InstanceFlyToClearAltitude | 0x1473c3d60 | 0x147bbb2e0 | LiveAITaskFlyToClearAltitude (0x78) |
| InstanceAutoDestruct | 0x1473c3e10 | 0x147bbb3d0 | LiveAITaskAutoDestruct (0x88) |
| InstanceActivateFlares | 0x1473c3ed0 | 0x147bbb4e0 | LiveAITaskActivateFlares (0xa0) |
| InstanceGoFormation | 0x1473c3f60 | 0x147bbb5f0 | LiveAITaskGoFormation (0x70) |
| InstanceWingmanFollow | 0x1473c3fa0 | 0x147bbb6b0 | LiveAITaskFollowWingman (0x70) |
| InstanceGroup | 0x1473c3fe0 | 0x147bbb770 | LiveAITaskGroup (0x70) |
| InstanceShield | 0x1473c4020 | 0x147bbb830 | LiveAITaskShield (0x78) |
| InstanceApproachAndDocking | 0x1473c4060 | 0x147bbb8f0 | LiveAITaskApproachAndDocking (0x78) |
| InstanceUnDock | 0x1473c40c0 | 0x147bbb9c0 | LiveAITaskUnDock (0x78) |
| InstanceWaitTime | 0x1473c4120 | 0x147bbba90 | LiveAITaskWaitTime (0x78) |
| InstanceNotifyEventTrigger | 0x1473c41d0 | 0x147bbbb70 | LiveAITaskNotifyEventTrigger (0x78) |
| InstancePlaySound | 0x1473c4230 | 0x147bbbc40 | LiveAITaskPlaySound (0x90) |
| InstanceManeuverAileronRoll | 0x1473c42d0 | 0x147bbbe00 | LiveAITaskManeuverAileronRoll (0x80) |
| InstanceManeuverFlyStraight | 0x1473c4390 | 0x147bbbf00 | LiveAITaskManeuverFlyStraight (0xb8) |
| InstanceManeuverBarrelRoll | 0x1473c44f0 -> 0x1473c85a0 | 0x147bbc070 | LiveAITaskManeuverBarrelRoll (0xc8) |
| InstanceManeuverCloudReaction | 0x1473c4500 | 0x147bbc220 | LiveAITaskManeuverCloudReaction (0xd0) |
| InstanceManeuverLevel | 0x1473c45f0 | 0x147bbc410 | LiveAITaskManeuverLevel (0xc0) |
| InstanceManeuverPitch | 0x1473c46a0 | 0x147bbc5b0 | LiveAITaskManeuverPitch (0xc0) |
| InstanceManeuverRoll | 0x1473c4750 | 0x147bbc750 | LiveAITaskManeuverRoll (0xc0) |
| InstanceManeuverSlalom | 0x1473c4800 -> 0x1473c8790 | 0x147bbc8f0 | LiveAITaskManeuverSlalom (0xc8) |
| InstanceManeuverTurnAdvanced | 0x1473c4810 | 0x147bbcab0 | LiveAITaskManeuverTurnAdvanced (0xc0) |
| InstanceManeuverTurnNormal | 0x1473c48c0 -> 0x1473c8990 | 0x147bbcc50 | LiveAITaskManeuverTurnNormal (0xc8) |
| InstanceManeuverTurnQuick | 0x1473c48d0 -> 0x1473c8bb0 | 0x147bbce20 | LiveAITaskManeuverTurnQuick (0xd0) |
| InstanceManeuverTurnToPoint | 0x1473c48e0 -> 0x1473c8de0 | 0x147bbd000 | LiveAITaskManeuverTurnToPoint (0xd8) |
| InstanceManeuverYaw | 0x1473c48f0 | 0x147bbd1c0 | LiveAITaskManeuverYaw (0xc0) |
| InstanceManeuverFrontCross | 0x1473c49a0 -> 0x1473c8fc0 | 0x147bbd360 | LiveAITaskManeuverFrontCross (0xc8) |
| InstanceManeuverCobraTurn | 0x1473c49b0 | 0x147bbd520 | LiveAITaskManeuverCobraTurn (0x78) |
| InstanceManeuverFlatSpin | 0x1473c4a30 | 0x147bbd5f0 | LiveAITaskManeuverFlatSpin (0x78) |
| InstanceManeuverKulbit | 0x1473c4ae0 -> 0x1473c91e0 | 0x147bbd6d0 | LiveAITaskManeuverKulbit (0x88) |
| InstanceManeuverPugachevsCobra | 0x1473c4af0 | 0x147bbd800 | LiveAITaskManeuverPugachevsCobra (0x78) |
| InstanceManeuverKulbitToprak | 0x1473c4ba0 | 0x147bbd8e0 | LiveAITaskManeuverKulbitToprak (0xa8) |
| InstanceSetStateEscapeFromPursuer | 0x1473c4c90 | 0x147bbda70 | LiveAITaskSetStateEscapeFromPursuer (0x98) |
| InstanceSetMoveAwayFromTarget | 0x1473c4cd0 | 0x147bbdb30 | LiveAITaskSetMoveAwayFromTarget (0x98) |
| InstanceSetWingmanState | 0x1473c4d10 | 0x147bbdbf0 | LiveAITaskSetWingmanState (0xa0) |
| InstanceDecoratorBlackboard | 0x1473c4d90 | 0x147bbdcd0 | - |
| InstanceDecoratorBlackboardInt | 0x1473c4e70 | 0x147bbdda0 | - (same fn as Enum) |
| InstanceDecoratorBlackboardFloat | 0x1473c4e80 | 0x147bbde20 | - |
| InstanceDecoratorBlackboardString | 0x1473c4ef0 | 0x147bbdf00 | - |
| InstanceDecoratorBlackboardEnum | 0x1473c4e70 | 0x147bbdda0 | - (same fn as Int) |
| InstanceDecoratorIsDamagePercentageRatio | 0x1473c5040 | 0x147bbdfe0 | LiveAIDecoratorIsDamagePercentageRatio (0x88) |
| InstanceDecoratorIsKDSP1 | 0x1473c50b0 | 0x147bbe100 | LiveAIDecoratorIsKDSP1 (0x60) |
| InstanceDecoratorIsKDSP2 | 0x1473c5160 | 0x147bbe1e0 | LiveAIDecoratorIsKDSP2 (0x60) |
| InstanceDecoratorIsFireMissileFinished | 0x1473c5210 | 0x147bbe2c0 | LiveAIDecoratorIsFireMissileFinished (0x60) |
| InstanceDecoratorIsTrackingAirTarget | 0x1473c52c0 | 0x147bbe3a0 | LiveAIDecoratorIsTrackingAirTarget (0x60) |
| InstanceDecoratorIsTrackingAirTargetSurround | 0x1473c5370 | 0x147bbe480 | LiveAIDecoratorIsTrackingAirTargetSurround (0x60) |
| InstanceDecoratorIsCloud | 0x1473c5420 | 0x147bbe560 | LiveAIDecoratorIsInCloud (0x60) |
| InstanceDecoratorIsAroundPlayer | 0x1473c54d0 | 0x147bbe640 | LiveAIDecoratorIsAroundPlayer (0x68) |
| InstanceDecoratorIsFlareActive | 0x1473c55d0 | 0x147bbe730 | LiveAIDecoratorIsFlareActive (0x60) |
| InstanceDecoratorCanCobra | 0x1473c5680 | 0x147bbe810 | LiveAIDecoratorCanCobra (0x60) |
| InstanceDecoratorCanKulbit | 0x1473c5730 | 0x147bbe8f0 | LiveAIDecoratorCanKulbit (0x60) |
| InstanceDecoratorIsThereGround | 0x1473c57e0 | 0x147bbe9d0 | LiveAIDecoratorIsThereGround (0x88) |
| InstanceDecoratorUnitAltitudeComparison | 0x1473c58b0 | 0x147bbeae0 | LiveAIDecoratorIsUnitAltitudeComparison (0x68) |
| InstanceDecoratorWingmanUseSpecialWeapon | 0x1473c5980 | 0x147bbebe0 | LiveAIDecoratorWingmanUseSpecialWeapon (0x68) |
| InstanceDecoratorWingmanFireSpecialWeaponFinished | 0x1473c59e0 | 0x147bbecd0 | LiveAIDecoratorWingmanFireSpecialWeaponFinished (0x68) |
| InstanceWeightProbability | 0x1473c5a40 | 0x147bbedc0 | LiveAIWeightProbability (0x58) |
| InstanceWeightProbabilityAILevel | 0x1473c5ad0 | 0x147bbeea0 | LiveAIWeightProbabilityAILevel (0x68) |
| InstanceWeightProbabilityPersonality | 0x1473c5bd0 | 0x147bbefb0 | LiveAIWeightProbabilityPersonality (0x68) |
| InstanceWeightProbabilityPilotRank | 0x1473c5d20 | 0x147bbf0c0 | LiveAIWeightProbabilityPilotRank (0x68) |

Notes for the decorator work (seen in passing): IsKDSP1 = `bEnableKDSMode (+0x35a9) && phase (+0x35ba) in {1,2}`,
IsKDSP2 = `phase in {3,4}` (0x147bb9480 / 0x147bb9500; also the reflected getters 0x146d43ea0 / 0x146d43f10).
0x147bb96b0 (probably IsTrackingAirTargetSurround) tests the surround-pursuit flag plane+0x26a8. [C]

## 5. Helpers worth knowing (for anyone continuing)
* 0x147cd16e0 Steer (pursuit steering, 1143 lines, `build/research/ai/native_move/steer.txt`).
* 0x147cd2970 speed matching (target speed + sqrt(2 a d) closure, clamp min/max). 0x147cd2f50(plane, speed, strength)
  throttle-or-brake toward a speed.
* 0x147cd2f90 roll-to-angle(deg, rate); 0x147cd3000 pitch-to-angle; 0x147cd3080 / 0x147cd3130 / 0x147cd3180 /
  0x147cd31d0 further attitude helpers; 0x147cd2f20 set pitch stick; 0x147cce570 simple "point the nose" steering.
* 0x147cd0480 fly-to-point; 0x147c93000 ground height under a point; 0x147d23710 / 0x147d23880 target's
  PursuitPoint / LeadPoint in world space; 0x147d23b10 "point within range and inside target's front cone".
* 0x14427d6c0 USceneComponent forward vector; component transform at +0x200 (quat), +0x220 (translation), +0x240 scale.
* Imports: 0x14a8d4402 atan2, 0x14a8d4420 cosf, 0x14a8d44bc powf, 0x14a8d44e6 tanf, rand via [0x14ab1a3d8].
* Parts of the binary are relocated into `.didata` behind `jmp` thunks with obfuscated constants (e.g. several
  constructors, WaitTime Enter); `cls.dump()` follows the first jmp.

## 6. What this means for Survival (not tested)
* Arguments only matter at tree-build time (rule 20): they are copied into task UObjects when the LA_ script's Ctor runs.
  Changing pursuit behaviour therefore means **a different LA_ script / LuaSet row** (Survival's NLID_SV_Fighter), or
  **editing the task objects after the level built them**: they are UObjects of class `LiveAITaskPursuerTarget` etc.,
  so FindAllOf + a raw float write at the offsets above (e.g. +0x7c lead time, +0x84 close range, +0x8c extend switch,
  +0x70 duration) should change every tree that uses them. That second route is untested.
* To make enemies sit on the player's tail like LA_LastTGT: a4 = false, a16 = true, a17 = (-200..-400, 0, 0) (metres
  behind), a3 large (10-100), a7 = false (never extend), a1 long (10-20 s), a5 1500-2000, a6 20. To stop "fly around
  without attacking" the KDS-only branches (rule 22) are irrelevant once a14 / a15 are false and the set has no
  IsKDSP decorators.
* SpdConstant values in the scripts are km/h; SpdCruise is % of the airframe's normal speed.

## Open questions
1. Consumer of plane+0x2718 (PursuerTarget a10 ramp).
2. Default values of PursuitPointOffset / LeadPointOffset per airframe (blueprint CDOs, not in the exe).
3. Which actor key UE resolves for the Set* tasks' unset selector (first Actor key of the AI blackboard asset).
4. Exact meaning of the acrobatic bools (Cobra / Pugachev / Kulbit recovery variants) and KulbitToprak's floats.
5. plane+0x6c8 rate factor source; plane+0x370 offset vector that Steer rotates into target space in non-lead mode.
6. `plane->vfunc[0xaf8]` (switches every maneuver to the simple nose-pointing path): large plane? path following?
</content>
</invoke>
