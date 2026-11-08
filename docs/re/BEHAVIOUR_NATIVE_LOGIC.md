# AC8 AI behaviour trees: native builder, composites, decorators, blackboard, AI state, KDS (static RE, 2026-10-22)

Companion to `AI_BEHAVIOURS.md` (what the LA_ scripts are), `GAME_LUA.md` (how a LuaSet slot becomes a Ctor call) and
`BEHAVIOUR_NATIVE_MOVE.md` (movement / maneuver / PursuerTarget tasks and the full binding registration list, section 4).
This file is the **logic side**: tree building, execution, composites, decorators, probabilities, the blackboard, the AI
state machine that drives the slots, and KDS. Static analysis of `AceCombat8.exe` only; **nothing here was tested in
game**. Scratch (scripts, disassembly dumps): `build/research/ai/native_logic/` (`reg.asm`, `pairs.txt`, `glue.txt`,
`builder.asm`, `behx.asm`, `kds.asm`, `cls.py`, `vt.py`).

Confidence: **[C]** confirmed in disassembly (store and read both seen), **[I]** inferred (code seen, meaning is a
reading), **[?]** not traced. Enum names from usmap: `ELiveAIBehaviorNodeType` {0 Root, 1 Composite, 2 Task,
3 Decorator, 4 Probability, 5 None}, `ELiveAINodeResult` {0 Run, 1 Failed, 2 Complete, 3 Abort}, `ELiveKDSPhase`
{0 None, 1 FrontEntrance, 2 FrontLead, 3 BackEntrance, 4 BackChase}, `ELiveEngagement` {0 Normal, 1 AttackOnly,
2 ProvokeEvadeOnly, 3 EvadeOnly, 4 TransitAttackOnly, 5 TransitAttackAndEvade, 6 AttackAndEvade, 7 None}.

---------------------------------------------------------------------------------------------------------------------

## 0. The picture in one paragraph

A behaviour script's `self` is the world's **`ULiveAILuaWorldSubsystem`**, not the plane. The `Add*` calls only
**record** entries; `EndGenerateBehavior` links them into a node tree under a hidden root node named `"Root"`. The
built tree is cached per module (and shared by every plane and every slot that names the same module). Each plane's
`ULiveAIStateComponent` owns one `ULiveAIBehavior` runner per slot. Every frame the component (1) runs a **native C++
state decision** (`UpdateAIState`, section 8) that writes the blackboard key `AIState`, then (2) ticks the root runner,
whose `LA_AIPlane` tree switches on `AIState` and runs the slot behaviour with `RunBehavior`. Composites have an unusual
**stack machine**: a child's result is seen by its composite only; when a composite is done, its parent simply
continues with its next child (results do not propagate upward). Decorators with the trailing "abort" flag are
re-checked every frame for every task below them and abort the running task when they turn false. KDS phases are
handed out by the **target's** `ULiveKeyDogfightSystem` (the player owns one): at most **one front and one back
attacker per target** at any time.

---------------------------------------------------------------------------------------------------------------------

## 1. Where things live

| what | address / offset | notes |
|---|---|---|
| binding table builder | 0x1473c04f0 | 87 `{name, lua_CFunction}` pairs, `pairs.txt` [C] |
| Lua `self` for Add*/Instance* | `ULiveAILuaWorldSubsystem` | glue reads it with 0x144ed8d00(L, 1) [C] |
| subsystem+0x60 | `GenerateNodeDatas` TArray, 0x28-byte entries | `{node, resolvedParent, FName parentName, FName name, u8 kind}` [C] |
| subsystem+0x70 | `GeneratedRootNode` (the hidden root, class LiveAICompositeBase, name `"Root"`, kind 0) | [C] |
| subsystem+0x78 | build cache, 0x30-byte entries `{TArray<int>, FString LuaInitializePath, root, u8 slot}` | [C] |
| subsystem+0x88 | blackboard asset used to resolve keys while building = `plane.AIStateComponent(+0x2808).BlackboardAsset(+0x108)` of the plane that triggered the build (0x1473b473f) | [C] |
| Ctor call | 0x1473b3c30 `Ctor(LuaInitializePath, subsystem)` | errors are swallowed (GAME_LUA.md) |
| build / cache lookup | 0x1473b47eb (and 3 siblings) | same path + same slot -> reuse; same path, other slot -> reuse root (no Ctor); else build [C] |
| node layout (`ULiveAINodeBase`) | +0x28 FName NodeName, +0x30 Parent, +0x38 ChildList (TArray), +0x48 u8 kind, +0x50 u8 (decorator abort flag) | kind = 5 (None) until linked [C] |
| task | +0x58 `AbortsDecoratorNode` TArray, +0x70.. args (blackboard tasks: key selector +0x70) | [C] |
| runner `ULiveAIBehavior` | +0x28 RootNode, +0x30 CurrentNode, +0x40 node stack, +0x50 context, +0x60 TaskPendingList (16-byte `{task, bool}`) | [C] |
| context passed to tasks / decorators | the plane's `ULiveAIStateComponent`: +0xf0 Owner plane, +0x100 BlackboardComponent, +0x108 BlackboardAsset, +0x210/214/218 AIPersonality, +0x120 LuaAssets | [C] offsets, names from reflection order [I] |
| node stack (runner+0x40) | +0x0 TArray<FWeakObjectPtr> composites, +0x10 weak runner, +0x18 weak owner, +0x20 TMap<FName,int> next-child index | [C] |

---------------------------------------------------------------------------------------------------------------------

## 2. The builder API

All Lua wrappers read FNames with 0x144ea18c0 and the node argument as either a userdata or a table whose `[1]` is the
userdata (what `CppObjectBase:NewOn` stores) [C]. Return values: none.

| Lua call | wrapper | native | entry written |
|---|---|---|---|
| `GenerateBehavior()` | 0x1473c2f40 | 0x1473b3db0 | if subsystem+0x70 is null: empty the entry list, `NewObject<LiveAICompositeBase>` as root. If a root already exists it does **nothing** [C] |
| `AddRootComposite(name, node)` | 0x1473c2f80 | 0x1473b3ec0 | `{node, -, parent="Root", name, kind 1}` [C] |
| `AddComposite(parent, name, node)` | 0x1473c2ff0 | 0x1473b4010 | kind 1 (Composite) [C] |
| `AddTask(parent, name, node)` | 0x1473c3080 | 0x1473b40c0 | kind 2 (Task) [C] |
| `AddDecorator(parent, name, node)` | 0x1473c31a0 | 0x1473b4170 | kind 3 (Decorator) [C] |
| `AddProbability(parent, name, node)` | 0x1473c32c0 | 0x1473b4220 | kind 4 (Probability) [C] |
| `EndGenerateBehavior()` | 0x1473c2f60 | 0x1473b42d0 | links, registers aborts, empties the list [C] |

### 2.1 How EndGenerateBehavior links (0x1473b42d0) [C]
1. Root gets NodeName `"Root"`, Parent null, kind 0.
2. Entries are processed **in call order**. For each: `parent = FindByName(root, parentName)` (0x147bb9fd0: depth-first,
   pre-order, children in insertion order, **first match wins**, FName compare). Then `node.NodeName = name`,
   `node.Parent = parent`, `node.kind = entry.kind`, `parent.ChildList.Add(node)`.
3. The loop **stops for good** (every later entry is silently dropped, never linked) when:
   * the parent name is not found (typo, or the parent is added later in the script than its child);
   * an entry's kind is 0 or its parentName is None (cannot happen through Lua);
   * after appending, the parent is the Root or a **Decorator** and now has **more than one child** (the 2nd child *is*
     appended, then the rest is dropped). Probability, Task and Composite parents are never checked.
4. Abort registration (0x1473b4520): for every entry node that IsA `LiveAIDecoratorBase` with its abort byte (+0x50) set,
   collect all descendants (0x147bba090, whole subtree) whose **kind byte** is 2 and add the decorator to each one's
   `AbortsDecoratorNode` (+0x58). A kind-2 descendant that is not really a `LiveAITaskBase` -> null pointer -> **crash**.
5. No type checks against the node's class: the kind comes from which `Add*` was called.

### 2.2 What each mistake does

| mistake | effect | silent? |
|---|---|---|
| unknown / misspelled parent name, or parent added after its child | that entry and **every entry after it** are never linked; the tree is cut off there | yes [C] |
| decorator given 2+ children | 2nd child linked, everything after dropped; at run time only `ChildList[0]` is used anyway | yes [C] |
| two `AddRootComposite` | same as above for the root; only the first root runs | yes [C] |
| duplicate node names (FName compare: case-insensitive, `"Seq"` == `"seq"`) | later children attach to the **first** node with that name (DFS order); also composites with the same name share one child-index slot in the runner (section 3.3) and iterate wrongly | yes [C] |
| naming a node `"Root"` | `FindByName("Root")` hits the hidden root first -> its children go under the root -> 2 root children -> cut | yes [C] |
| `AddProbability` under a non-RandomSelect | links fine; at run time the walker returns null on a Probability node -> the whole tick ends there, every frame (tree stalls) | yes [C] |
| `AddDecorator` whose decorator has **no** child | when it passes, the walker gets a null child and the whole tick ends (tree stalls on that branch while it passes) | yes [C] |
| `AddTask` with a composite / decorator object, `AddComposite` with a task, etc. | node virtuals called with the wrong meaning; garbage or crash at run time; a fake task under an aborting decorator crashes in EndGenerateBehavior | no (crash) [I] |
| `nil` node (e.g. a local variable typo) | entry with node 0; `EndGenerateBehavior` writes `[0+0x28]` -> **crash** while the level loads | no [I] |
| misspelled factory (`self:InstanceSelectr()`) | Lua error, Ctor aborts before `EndGenerateBehavior`; the cache stores the half-built root with **no children**: a slot tree that does nothing and "completes" every frame; for the root (LA_AIPlane) the plane gets no behaviour | yes [C]/[I] |
| misspelled enum (`ELiveAIState.PursueTargte` = nil) | read as 0 (`ReturnToWorld`, `Equal`, `UPDATE_AI_STATE`, `SpdConstant`...) | yes [C] (wrappers read nil as 0/false/None) |
| blackboard decorator with a key not in the blackboard asset | the factory dereferences a null key type (`[0+0x110]`) -> **crash** during the build | no [I] (UE `ResolveSelectedKey` leaves the type null; the null read is [C]) |
| script whose class has no own `Ctor` (inherited only) | DefaultLua `Ctor()` looks it up with `rawget`; nothing is built; slot root null; `RunBehavior` on it fails | yes [I] |
| `GenerateBehavior` called twice in one Ctor | second call is a no-op | harmless [C] |

The built tree is **shared**: one set of node objects per module per world, used by every plane and slot naming that
module (cache 0x1473b47eb). Per-plane state lives in the runner (stack, index map, current node) and in per-node
memory on the component (0x147cf2090), never in the nodes [C].

---------------------------------------------------------------------------------------------------------------------

## 3. How a tree runs (ULiveAIBehavior)

### 3.1 Tick (0x147c6a130) [C]
* If `CurrentNode` is null: clear the stack and the child-index map (0x147c6ab80) and `CurrentNode = Enter(RootNode)`.
* `CurrentNode = Step(CurrentNode, dt)`. A non-null result is the task that is still running; it resumes next frame.
  Null = this run is over; **next frame starts again from the root** with fresh indices.
* Called by the state component's behaviour tick (0x147cef500, `RootBehavior` at component+0xf8) and by `RunBehavior`
  for slot trees.

### 3.2 Step (0x147c6a4f0) - the walker [C]
Loop on the node's kind byte:
* **Composite** -> `Enter(node)` (below), continue with its result.
* **Task** -> `RunTask(task, dt)` and return what it returns.
* **Decorator** -> `ok = decorator.Evaluate(context)` (vtable 0x2d0). If ok: continue with `ChildList[0]` (null if none
  -> tick ends). If not: `Finish(Failed, decorator)`.
* **Probability / Root / other** -> return null (tick ends).

`Enter(node)` (0x147c6a2d0): Root -> `ChildList[0]`; Composite -> `SelectChild` (vtable 0x2d0). If that gives null
(composite exhausted) -> pop the top composite off the stack and `Enter` it instead (= the parent continues). A task
returned here is flagged "pending start".

`RunTask` (0x147c6a610):
1. If the task is pending start: `r = task.OnEnter(ctx)` (0x2d0); call the nearest composite's `OnChildStarted` hook
   (0x2e0, only Parallel implements it); clear the pending flag.
2. **Abort check**: for each decorator in `task.AbortsDecoratorNode`: if `!decorator.Evaluate(ctx)` -> abort:
   `r = task.OnAbort(ctx)` (0x2e8; base returns 3 Abort, MoveAwayFromTarget returns 1 Failed), `task.OnExit` (0x2e0),
   composite hook 0x2f0, then `Finish(r, <the decorator>)` - the result goes to the **decorator's** nearest composite.
3. If OnEnter already returned non-zero: finish with it. Else `r = task.Tick(ctx, dt)` (0x2d8) and composite hook 0x2e8;
   `r == 0` (Run) -> return the task (still running).
4. Finish: `task.OnExit`, composite hook 0x2f0, `Finish(r, task)`.

`Finish(r, node)` (0x147c6a9b0): find the nearest **Composite** ancestor (walks Parent through decorators and
probabilities, 0x147bba060; stops at Root) and return `composite.OnChildFinished(stack, r)` (vtable 0x2d8); no
composite -> null.

### 3.3 The composite stack [C]
* Ordinary composites (Selector, LaxSelector, Sequencer, LaxSequencer, Continuation, LaxContinuation) share
  `SelectChild` 0x147bb7ce0: read this composite's next index from the runner's TMap **keyed by the composite's
  NodeName**, return `ChildList[index]`, push the composite on the stack and store index+1. Index past the end -> null.
* **RandomSelect and Parallel do not push themselves and keep no index.**
* `OnChildFinished` returns one of: `this` (keep going inside this composite), null (end the tick), or one of two
  helpers:
  * **next** (0x147bb7b00): pop the top composite and `Enter` it -> it selects its next child (it was the top: itself).
  * **leave** (0x147bb7c30): pop the top, then do **next** on the new top -> the parent continues with its next child.
* So results never travel more than one level: when a composite finishes (by "leave" or by running out of children),
  its parent just continues with its next child, **whatever the parent's type and whatever the result**.

---------------------------------------------------------------------------------------------------------------------

## 4. Composites

`OnChildFinished(result)` per class (all [C]; LaxSelector's body sits behind an obfuscation thunk at 0x15c869840 and
was read there):

| factory (wrapper / factory / class) | Failed (1) | Complete (2) | Abort (3) | meaning |
|---|---|---|---|---|
| `InstanceSelector()` 0x1473c33e0 / 0x147bba2e0 / LiveAICompositeSelector (vt 0x14c4fc738) | next child | leave | **end tick** | first child that completes wins |
| `InstanceLaxSelector()` 0x1473c3420 / 0x147bba3a0 / LaxSelector (vt 0x14c4fd128) | next | leave | next | an aborted child counts as a failure |
| `InstanceSequencer()` 0x1473c3460 / 0x147bba460 / Sequencer (vt 0x14c4f8b68) | leave | next | end tick | stop at the first failure |
| `InstanceLaxSequencer()` 0x1473c34a0 / 0x147bba520 / LaxSequencer (vt 0x14c4fd498) | leave | next | next | an aborted child counts as a success |
| `InstanceContinuation()` 0x1473c3520 / 0x147bba6a0 / Continuation (vt 0x14c4fca58) | next | next | end tick | run every child in order regardless of result |
| `InstanceLaxContinuation()` 0x1473c3560 / 0x147bba760 / LaxContinuation (vt 0x14c4fcdb8) | next | next | next | same, aborts too |
| `InstanceRandomSelect()` 0x1473c34e0 / 0x147bba5e0 / RandomSelect (vt 0x14c4fc3c8) | parent continues | parent continues | parent continues | pick **one** child by weight, run it once (section 6) |
| `InstanceParallel()` 0x1473c35a0 / 0x147bba820 / Parallel (vt 0x14c4fbf80) | see below | see below | end tick | main task + background tasks |

"end tick" = `Step` returns null: the runner's current run ends and it restarts from the root next frame. In the root
tree this means the frame's `POST_UPDATE_AI_STATE` is skipped; for a slot tree, `RunBehavior` sees the sub-tree finish
and reports Complete.

**Parallel** [C]: `SelectChild` always returns `ChildList[0]` (the main child, should be a task). Its hooks run only for
that main task: when it starts, `OnEnter` every other child; while it runs, `Tick` every other child (their results
ignored, no abort checks on them); when it ends, `OnExit` every other child. Every other child **must be a task**
(non-task -> null call -> crash). Main result Failed/Complete -> **leave**; but since Parallel never pushed itself,
"leave" pops its **parent** too: the composite that contains the Parallel ends and *its* parent continues. [I] from the
stack discipline, not tested: in the stock pattern `LaxContinuation[Parallel(Pitch, Roll), FlyStraight]`
(AttackAvoidance_*_msl_m) the trailing FlyStraight would then never run. Treat Parallel as "last thing in its parent".

Lax semantics in one line: Lax composites treat **Abort like the "keep going" result** (LaxSelector: like Failed,
LaxSequencer: like Complete, LaxContinuation: like everything else) instead of ending the tick.

---------------------------------------------------------------------------------------------------------------------

## 5. Decorators

### 5.1 Evaluation and aborts [C]
* Every decorator has `+0x50 abort` (the **last bool** of the factory for blackboard decorators, the **2nd bool** for the
  "IsEqual" family). If set, it is registered on every task in its subtree (2.1 step 4) and re-evaluated **every frame
  while any of those tasks runs** (and on the frame it starts). When it evaluates false the running task is aborted
  (OnAbort result, normally Abort) and the result is reported to the decorator's composite. Without the flag a decorator
  is only evaluated when the walker reaches it. There is no "abort lower priority" mode: a decorator can only abort its
  own subtree.
* Trap [I]: the abort result goes to the decorator's composite but the stack is not unwound to it. If inner composites
  sit between the decorator and the task (decorator -> Sequencer -> tasks), "next" acts on the innermost composite
  (top of the stack), not on the decorator's composite. With Selector/Sequencer parents (Abort = end tick) this is
  harmless; with Lax / Continuation parents the inner composite carries on. Put aborting decorators directly over the
  task, or use non-Lax parents.
* "IsEqual" family (`LiveAIDecoratorIsEqual` subclasses): Evaluate 0x147bb9450 = `expected(+0x58) ? raw : !raw`, raw =
  vtable 0x2d8 [C]. The constructor defaults `expected = true`.
* Blackboard family: one class for all four factories, `LiveAIDecoratorBlackboardComparison` (vt 0x14c4f39d0),
  Evaluate 0x147bb8900 -> 0x147bb89e0 = UE's `EvaluateOnBlackboard`: the comparison is chosen by the **key's type**
  (basic / arithmetic / text), not by which factory was used [C]. Fields: +0x58 `FBlackboardKeySelector` (+0x68 name,
  +0x70 type, +0x78 key id), +0x80 basic op, +0x84 arithmetic op, +0x88 text op, +0x8c int value, +0x90 float value,
  +0x98 FString value [C]. Keys are resolved at build time against subsystem+0x88; values read at run time from the
  plane's BlackboardComponent by key id. No context blackboard -> false.

### 5.2 Table

`plane` = context+0xf0. Arg numbering = Lua arguments after self.

| factory (wrapper / factory / class, condition fn) | args | raw condition | conf |
|---|---|---|---|
| `InstanceDecoratorBlackboard` 0x1473c4d90 / 0x147bbdcd0 | 1 key (FName), 2 `EBasicKeyOperation` (Set/NotSet), 3 abort | key is set / not set | [C] |
| `InstanceDecoratorBlackboardInt` 0x1473c4e70 / 0x147bbdda0 | 1 key, 2 int value, 3 `EArithmeticKeyOperation`, 4 abort | `key op value` | [C] |
| `InstanceDecoratorBlackboardEnum` | **same wrapper and factory as Int** | enum compared as int | [C] |
| `InstanceDecoratorBlackboardFloat` 0x1473c4e80 / 0x147bbde20 | 1 key, 2 float, 3 op, 4 abort | `key op value` (PursuerDistance is cm) | [C] |
| `InstanceDecoratorBlackboardString` 0x1473c4ef0 / 0x147bbdf00 | 1 key, 2 string, 3 `ETextKeyOperation` (Equal, NotEqual, Contain, NotContain), 4 abort | text compare | [C] |
| `InstanceDecoratorIsKDSP1` 0x1473c50b0 / 0x147bbe100 / IsKDSP1, cond 0x147bb9480 | 1 expected, 2 abort | `plane.bEnableKDSMode(+0x35a9) && KDSPhase(+0x35ba) in {FrontEntrance, FrontLead}` | [C] |
| `InstanceDecoratorIsKDSP2` 0x1473c5160 / 0x147bbe1e0, cond 0x147bb9500 | 1 expected, 2 abort | same, phase in {BackEntrance, BackChase} | [C] |
| `InstanceDecoratorIsFireMissileFinished` 0x1473c5210 / 0x147bbe2c0, cond 0x147bb9580 | 1 expected, 2 abort | `plane+0x2980 >= 1`: at least one missile fired since the last `UPDATE_AI_STATE` (which zeroes it, plane vfunc 0xd60) | [C] counter meaning [I] |
| `InstanceDecoratorIsTrackingAirTarget` 0x1473c52c0 / 0x147bbe3a0, cond 0x147bb9610 | 1 expected, 2 abort | FCS current target (plane vfunc 0xcb0 = FCS(+0xfa8) target) exists and `target.vfunc 0xae8` (IsAir; AI objects read +0x10db) | [C] / IsAir [I] |
| `InstanceDecoratorIsTrackingAirTargetSurround` 0x1473c5370 / 0x147bbe480, cond 0x147bb96b0 | 1 expected, 2 abort | as above and `plane+0x26a8` (surround-pursuit active) | [C] / name [I] |
| `InstanceDecoratorIsCloud` 0x1473c5420 / 0x147bbe560 / class IsInCloud, cond 0x147bb9780 | 1 expected, 2 abort | `plane+0x2720` (cloud component) `+0x64` in-cloud byte | [C] |
| `InstanceDecoratorIsAroundPlayer` 0x1473c54d0 / 0x147bbe640, cond 0x147bb9800 | 1 distance (m, x100), 2 expected, 3 abort | distance from the plane to the first non-null entry of `plane.Unit(+0xfa0)+0x320` **greater** than arg 1 (no entry -> false) | [C] math, list meaning [I] |
| `InstanceDecoratorIsFlareActive` 0x1473c55d0 / 0x147bbe730, cond 0x147bb99b0 | 1 expected, 2 abort | FCS weapon slot of type 2 found (0x147c0ac10) and its vfunc 0x330 | [C] / "flares deployed" [I] |
| `InstanceDecoratorCanCobra` 0x1473c5680 / 0x147bbe810, cond 0x147bb9a90 | 1 expected, 2 abort | `plane.bCanManeuverPugachevsCobra` (+0x28d0) | [C] |
| `InstanceDecoratorCanKulbit` 0x1473c5730 / 0x147bbe8f0, cond 0x147bb9b00 | 1 expected, 2 abort | `plane.bCanManeuverKulbit` (+0x28d1) | [C] |
| `InstanceDecoratorIsThereGround` 0x1473c57e0 / 0x147bbe9d0, cond 0x147bb92d0 | 1 key (actor), 2 / 3 bools (expected at +0x80, abort at +0x50; order [I]) | key's object is a valid LiveGameObject and 0x147c92d50(obj) (ground check) | [C] cond / [I] meaning |
| `InstanceDecoratorUnitAltitudeComparison` 0x1473c58b0 / 0x147bbeae0 / IsUnitAltitudeComparison, cond 0x147bb9be0 | 1 bool `above`, 2 margin, (3 abort, unused by stock = false) | above: `z > Unit.min(+0x348) + margin`; else `z < Unit.max(+0x34c) - margin` (z = plane location, cm) | [C] / field names [I] |
| `InstanceDecoratorIsDamagePercentageRatio` 0x1473c5040 / 0x147bbdfe0, cond 0x147bb9090 | 1 key (actor), 2 percent, 3 `EArithmeticKeyOperation`, 4 abort | `damage% op percent`, damage% = `(1 - clamp(health/MaxHealth)) x 100` (0x147d1cc60; health = int(+0xda8) x 0.1, MaxHealth +0x3b4) | [C] |
| `InstanceDecoratorWingmanUseSpecialWeapon` 0x1473c5980 / 0x147bbebe0, cond 0x147bb9cf0 | (mode, expected, abort) via reader 0x1473c9d60 | owner must be `LiveAIWingmanPlane`; mode 0: 0x147ed46b0 != 0, 1: FCS slot 3 count, else slot 4 | [C] / args [I] |
| `InstanceDecoratorWingmanFireSpecialWeaponFinished` 0x1473c59e0 / 0x147bbecd0, cond 0x147bb9e40 | same reader | wingman counters +0x4220 >= +0x4144 and +0x4224 >= +0x4148 (mode-dependent) | [C] / [I] |

---------------------------------------------------------------------------------------------------------------------

## 6. Probabilities

* `AddProbability(parent, name, node)` only records kind 4. Pairing happens at run time in **RandomSelect's
  SelectChild** (0x147bb8430) [C]:
  * for each child: if it IsA `LiveAIWeightProbabilityBase`, `weight = child.GetWeight(owner)` (vtable 0x2d0, owner =
    the runner's owner object) and the candidate is **the probability's `ChildList[0]`** (null if none; extra children
    ignored); any other child gets **weight 10.0** and is its own candidate;
  * `r = (rand() & 0x7fff) / 32767 x sum(weights)`; walk the list subtracting weights; the first child with weight > 0
    that brings `r <= 0` is returned. Weights <= 0 are never picked. Nothing picked (all zero) -> null -> the
    RandomSelect is skipped (its parent continues).
  * The pick happens every time the RandomSelect is entered; it does not retry another branch when the picked one fails
    (parent continues, section 4).
* Weights are **relative**, not percentages, and plain children of a RandomSelect count as 10 each.
* A probability node reached any other way (under a Selector, Sequencer, decorator...) ends the tick (section 2.2).

| factory (wrapper / factory / GetWeight) | args -> fields | weight | source fields | conf |
|---|---|---|---|---|
| `InstanceWeightProbability(w)` 0x1473c5a40 / 0x147bbedc0 / 0x147bd89b0 | w -> +0x50 | w | - | [C] |
| `InstanceWeightProbabilityPilotRank(w1..w5)` 0x1473c5d20 / 0x147bbf0c0 / 0x147bd8cc0 | +0x50..+0x60 | `w[clamp(rank, 1, 5)]` | `ALiveAIGameObject.PilotRank` = plane+0x252c, **read every time** (a run-time write is picked up by the next pick); rank <= 1 -> w1, >= 5 -> w5 | [C] read; field = reflected PilotRank [I] |
| `InstanceWeightProbabilityAILevel(w1..w5)` 0x1473c5ad0 / 0x147bbeea0 / 0x147bd8a30 | +0x50..+0x60 | `w[clamp(level / 100, 1, 5)]` | u16 at plane+0x1048 (0-199 -> w1, 200-299 -> w2, ... >= 500 -> w5); most likely `LiveAIObjectDesc.LevelId` (UInt16) | [C] read / [I] source |
| `InstanceWeightProbabilityPersonality(w1, w2, w3, threshold, geq)` 0x1473c5bd0 / 0x147bbefb0 / 0x147bd8b70 | w1..w3 +0x50/54/58, int threshold +0x5c, bool +0x60 | `10 + sum(w_i where P_i >= threshold)` (geq true) or `P_i < threshold` (false) | `ULiveAIStateComponent.AIPersonality` Personality1..3 at component+0x210/0x214/0x218 | [C] |

Note the Personality weight starts at **10**, so it is never 0.

---------------------------------------------------------------------------------------------------------------------

## 7. Blackboard

The asset is the plane's `ULiveAIStateComponent.BlackboardAsset` (component+0x108), a content asset (not in the exe).
`RunBehavior` slot names are keys too, so a custom script **cannot invent new keys or slots**. Keys seen in code or
stock scripts:

| key | type | written by | when / units | conf |
|---|---|---|---|---|
| `AIState` | enum `ELiveAIState` | `RequestState` 0x147cf0e70 | every state change (section 8); old value copied to `AIStatePrev` first | [C] |
| `AIStatePrev` | enum | `RequestState` | previous AIState | [C] |
| `AIAlert` | enum `ELiveAIAlert` (0 None, 1 Gun, 2 Missile, 3 SpecialWeapon) | 0x147cf1800 | set with AttackAvoidance requests; reset to None by `POST_UPDATE_AI_STATE` | [C] |
| `TargetActor` | object | 0x147cf16d0 | set with PursueTarget / MoveAwayFromTarget requests; cleared by POST when the plane has no pending escape/move-away actor | [C] |
| `PursuerActor` | object | `SetPursuer` 0x147cf1160 -> 0x147cf1187 | set with Blackout / EscapeFromPursuer / Provoke / AttackAvoidance requests | [C] |
| `PursuerDistance` | float, **cm** | same function, right after PursuerActor | distance to the pursuer **at the moment the state was requested**; not refreshed while the state persists (requests for the active state are gated out) | [C] write / [I] staleness |
| `IsPursuerWingman` | bool | same | pursuer is a wingman | [C] |
| `PursuerWingmanState` | enum `ELiveAIWingmanState` | same | | [C] |
| `GroupLeadActor` | object | 0x147cf1930 | set with the Group request (`plane+0x3598`); cleared by POST | [C] |
| `SelfActor` | object | init 0x147cf0bb0 (FName in global 0x14e357780) | the plane itself | [I] |
| `LocalPlayer` | object | init 0x147cf0bb0 | the local player plane | [C] |
| `CurrentAltitudeMeter` | float | 0x147cf0150 (component tick) | plane altitude x 0.01 (m) | [C] |
| `PlayerToDotProduct` | float | 0x147cf0150 | dot product plane -> (plane+0x2668 actor) direction | [C] write / [I] meaning |
| `EvadeBehavior`, `EvadeGunBehavior`, `EvadeMissileNearBehavior`, `EvadeMissileFarBehavior`, `EvadeSpecialBehavior`, `BlackoutBehavior`, `CloudAvoidanceBehavior`, `ProvokeBehavior`, `ProvokeNear/Mid/FarBehavior`, `EscapeFromPursuerBehavior`, `MoveAwayFromTargetBehavior`, `PursuerTargetBehavior`, `UniqueActionBehavior`, `Wingman*Behavior` | object (a `ULiveAIBehavior` runner) | 0x147cf0d90 at setup | the slot runners `RunBehavior` looks up by name | [C] lookup / names from scripts |
| `WingmanState`, `PreWingmanState`, `WingmanNo`, `WingmanAttackActor`, `WingmanOwnerActor`, `IsExecutablePreDistributedAttack`, `IsExistKDSBack`, `BarrierChargingCompleted` | wingman / unique-action keys | 0x147eb8xxx (wingman), 0x147e7b1b0 | | names [C] |

`ELiveAIState` (blackboard enum): 0 ReturnToWorld, 1 AvoidObstacle, 2 AvoidRangeAttack, 3 Wingman, 4 ReturnToUnit,
5 AttackAvoidance, 6 EscapeFromPursuer, 7 Blackout, 8 Provoke, 9 MoveAwayFromTarget, 10 PursueTarget,
11 FollowFormation, 12 Group, 13 Patrol, 14 UniqueAction, 15 CloudAvoidance, 16 Idle. **Lower value = higher
priority** in the state machine.

---------------------------------------------------------------------------------------------------------------------

## 8. The AI state machine (what moves AIState)

### 8.1 Per frame (component tick 0x147cef530) [C]
1. 0x147cf0150: write `CurrentAltitudeMeter`, `PlayerToDotProduct`.
2. 0x147cf2530 (provoke-determination update [?]).
3. Blackout timer: while the state seen at the last UPDATE is Provoke (8), +0x270 += dt; reaching +0x268
   (BlackoutStartTime, DT_NPC_Provoke) sets "blackout due" (+0x265). While in Blackout (7) +0x270 += dt until +0x26c
   (blackout exec time) clears it. Leaving Provoke counts the timer back down.
4. **`UpdateAIState`** (component vtable 0x4f0 = 0x147cf0640): the decision below. **Every frame**, independent of the
   tree.
5. Periodic plane checks: 0x147c92480 every `CheckOutOfWorldFrequency` (+0x118), 0x147ccf490 every
   `CheckAvoidObstacleFrequency` (+0x11c).
The behaviour runner is ticked separately (0x147cef500).

### 8.2 UpdateAIState priority chain (0x147cf0640) [C]
First matching line requests its state and returns. The order, offsets and requested states are [C]; the plain-English
meaning of each plane field is [I] (read from the state it triggers and the reflected property order).

| # | condition | state requested | extra keys |
|---|---|---|---|
| 1 | `plane+0x10ea` (out of world) | ReturnToWorld (0) | |
| 2 | `plane+0x29c9` (obstacle ahead) | AvoidObstacle (1) | |
| 3 | `plane+0x35a8` (range attack incoming) | AvoidRangeAttack (2) | |
| 4 | no Unit (`plane+0xfa0` null) | ReturnToUnit (4) | |
| 5 | outside the unit area (0x147dcae00, factor 1.0): unit formation flags (+0x388 and +0x389) -> FollowFormation (11), else ReturnToUnit (4) | | |
| 6 | `plane+0x2660` set (a ReturnToUnitCircle run in progress), or hold rule (8.3) | keep current | |
| 7 | blackout due (+0x264, +0x265, +0x227 clear) | Blackout (7) | PursuerActor = plane+0x2668 |
| 8 | `bPermissionToEvade` (plane+0x10d8) and a threat: special weapon list (+0x470) / missile flag (+0x522) / gun attacker (+0x27e0) | AttackAvoidance (5) | PursuerActor = threat owner, AIAlert = SpecialWeapon / Missile / Gun |
| 9 | not blackout-locked and cloud density (`plane+0x2730`+0x60) >= `CloudAvoidanceDensity` (+0x26e0) | CloudAvoidance (15) | |
| 10 | `EscapeFromPursuerActor` (+0x2670) set | EscapeFromPursuer (6) | PursuerActor = it; **the field is cleared** (one-shot) |
| 11 | `MoveAwayFromTargetActor` (+0x2678) set | MoveAwayFromTarget (9) | TargetActor = it; cleared (one-shot) |
| 12 | hold rule (8.3, kind 2) | keep current | |
| 13 | group lead (+0x3598) set, not grouped already (+0x3590, +0x3592), **not in KDS front phase** | FollowFormation (11) if the unit has formation flags, else Group (12) | GroupLeadActor |
| 14 | provoke candidate `plane+0x2668`, game-mode check (GameMode vfunc 0x8d8), `bPermissionToProvoke` (+0x10d7), provoke condition met (+0x25c) | Provoke (8) | PursuerActor = it |
| 15 | hold rule (8.3, kind 1) | keep current | |
| 16 | FCS current target (plane vfunc 0xcb0) and `bPermissionToEngage` (+0x10d4) | PursueTarget (10) | TargetActor = target |
| 17 | activated (+0x3f4) and unit formation flags | FollowFormation (11) | |
| 18 | otherwise | Patrol (13) | |

Permission bytes (written by the engagement order, 8.5): +0x10d4 Engage, +0x10d5 Fire, +0x10d6 UseFlares,
+0x10d7 Provoke, +0x10d8 Evade [C offsets, I names].

### 8.3 Request gating (0x147cf0e70 and wrappers 0x147cf1a60 / 0x147cf1ac0 / 0x147cf1b40) [C]
* `component+0x224` = the state requested and still active (16 = none). Normally a request for S is accepted only if
  none is active or the active one has a **larger** value (S has higher priority). An equal or higher-priority active
  state is kept, so a plane in PursueTarget is not moved to Patrol, but is moved to Provoke / AttackAvoidance / any
  lower number at once.
* With the hold flag (`+0x230`) set, any *different* state is accepted; the hold kind `+0x250` plus check 0x147cf1ba0
  freezes the decision at chain points 6 / 12 / 15 [I].
* `RequestState`: `AIStatePrev := AIState; AIState := S; +0x224 := S`.
* `POST_UPDATE_AI_STATE` (end of the root tree run) resets `+0x224` to 16 (and clears TargetActor / PursuerActor unless
  an escape / move-away actor is pending, plus GroupLeadActor and AIAlert) when the state did not change during the
  run. So a state normally lasts until **its slot tree finishes** or a higher-priority state appears. [C] code / [I]
  reading of the "unchanged" test (+0x225 vs +0x224).

### 8.4 How the tree reacts
* `LA_AIPlane` = LaxSequencer[ `ExecuteFunction(UPDATE_AI_STATE)`, Selector[ one `StateIs<X>` BlackboardEnum decorator
  per state, **all with abort = true**, each over one task ], `ExecuteFunction(POST_UPDATE_AI_STATE)` ].
* When AIState changes while a slot runs, that `StateIs` decorator fails the abort check, `RunBehavior` is aborted
  (Abort), the Selector ends the tick and the tree restarts next frame on the new state. [C]
* `UPDATE_AI_STATE` itself does **not** decide anything: it snapshots AIState into component+0x225 and calls plane vfunc
  0xd60, which zeroes the missile-fired counter (+0x2980) used by `IsFireMissileFinished`. [C]
* States 3 Wingman, 14 UniqueAction and 16 Idle are never requested by this chain (wingman component / unique-action
  request / initial value).

### 8.5 The Set* tasks and the engagement order
* `InstanceSetStateEscapeFromPursuer(key)` (0x1473c4c90 / 0x147bbda70, OnEnter 0x147bd6de0): reads the actor in `key`
  (must be a LiveGameObject), stores it in `plane.EscapeFromPursuerActor` (+0x2670), returns Complete; no actor ->
  Failed. The state changes on the **next** UpdateAIState, subject to 8.2/8.3 (an active AttackAvoidance, value 5,
  outranks EscapeFromPursuer, 6, so the request waits until the evade tree ends). [C]
* `InstanceSetMoveAwayFromTarget(key)` (0x1473c4cd0 / 0x147bbdb30, OnEnter 0x147bd70d0): same into
  `MoveAwayFromTargetActor` (+0x2678) -> MoveAwayFromTarget. [C]
* `InstanceUpdateAIState()` / `InstancePostAIState()` are `InstanceExecuteFunction(0)` / `(1)`: same class
  `LiveAITaskCommonExecuteFunction` (factory 0x147bce6e0, type byte +0x70, OnEnter 0x147bc3530, returns Complete; type 2
  `POST_UPDATE_WINGMAN_STATE` returns Failed on this class). [C]
* Engagement order (`SetEngagement` 0x147c8f9e0, e.g. LiveAIEngagementOrder events): sets the five permission bytes per
  `ELiveEngagement` and calls plane virtual 0xca0 (LiveAIPlane override 0x147ccd1c0), which also sets
  **`bEnableKDSMode = (engagement != AttackOnly)`**. [C]

---------------------------------------------------------------------------------------------------------------------

## 9. Slot dispatch: InstanceRunBehavior

`InstanceRunBehavior("SlotName")` (0x1473c35e0 / 0x147bbbd30 / `LiveAITaskCommonRunBehavior`, vt 0x14c59adb0) [C]:
* slot name -> task+0x70 (FName). At run time (0x147bc38e0) the name is looked up as a **blackboard key** of the
  component's BlackboardAsset and the key's object value is the slot's `ULiveAIBehavior` runner.
* OnEnter 0x147bc3700: no runner, or runner+0x58 clear -> **Failed**; else continue.
* Tick 0x147bc3730: `runner.Tick(dt)`; runner's CurrentNode null afterwards -> **Complete**, else Run. The slot tree's
  own results are lost: RunBehavior is Complete whenever the slot tree's run ends.
* OnAbort 0x147bc3860: aborts the slot tree's running task, returns Abort. OnExit 0x147bc3780: exits the slot task and
  clears the slot runner's CurrentNode (it restarts from its root next time).
* The slot runners are filled per plane from `LiveLuaAssets` (component+0x120) at setup. Root tree slot -> state map
  (`LA_AIPlane`): Blackout -> `BlackoutBehavior`, AttackAvoidance -> `EvadeBehavior`, CloudAvoidance ->
  `CloudAvoidanceBehavior`, EscapeFromPursuer -> `EscapeFromPursuerBehavior`, MoveAwayFromTarget ->
  `MoveAwayFromTargetBehavior`, Provoke -> `ProvokeBehavior`, PursueTarget -> `PursuerTargetBehavior`, UniqueAction ->
  `UniqueActionBehavior`; the other states run a native task directly (8.2 table, section 11). Second-level slots
  (`EvadeMissileNearBehavior`, `ProvokeNearBehavior`, ...) are chosen inside the Evade / Provoke dispatcher scripts with
  `AIAlert` / `PursuerDistance` decorators.

---------------------------------------------------------------------------------------------------------------------

## 10. KDS ("Key Dogfight System", class `ULiveKeyDogfightSystem`)

### 10.1 Per-plane flag `bEnableKDSMode` (plane+0x35a9) [C]
* Spawn setup (0x147ccd14f): copied from the plane's KDS row (`DT_NPC.KDSId` / mission override -> `DT_NPC_KDS`:
  `bEnableKDSMode` -> +0x35a9, `SelectionTimeLimit` -> +0x35ac, `FrontEntranceTimeLimit` -> +0x35b0,
  `FrontLeadTimeLimit` -> +0x35b4); a copy is kept at +0x35b8.
* Reset / (re)activation (0x147ccce30): restored from +0x35b8, `+0x35b9 = 1` (selectable), then **forced off unless
  `GameObjectSubCategory` (+0x3ad) is Fighter (1), Attacker (2), Multirole (3) or UAV (10)**. Bombers, large planes etc.
  never do KDS.
* Engagement order: `= (ELiveEngagement != AttackOnly)` (8.5), overriding the row.
* A native setter 0x146d45980 forces it on (virtual, caller not found).

### 10.2 Who gets a phase [C]
Phases are not chosen by the plane. A `ULiveKeyDogfightSystem` (reflected: `OwnerPlane`, `Enemies`, `KDSFront`,
`KDSBack`) belongs to the **target**: the player plane (+0x3c08, ticked in 0x147d55a3a), wingmen (+0x4160,
0x147ed25d0) and online bot planes (+0x41c0, 0x147bb55a0). Its tick (0x147d2e550):
* every 2.0 s rebuilds `Enemies` (0x147d2e860): every AI plane of a unit hostile to the owner **whose unit area contains
  the owner** (0x147dcae00) and that passes `CanDoKDS` (0x147d2e2f0, no range check);
* `CanDoKDS`: FCS mode byte != 2, game-mode check, `bEnableKDSMode`, alive (+0xdb8 clear, health > 0), activated
  (+0x3f4), `bPermissionToEngage` (+0x10d4), +0x2804 clear; with the range check also "owner within the plane's unit
  radius (+0x350) plus FCS reach";
* selection (0x147d2dd30) scores candidates by distance and angle to the owner's front (front slot) or back (back slot)
  and needs +0xdba, +0xdbc and +0x35b9 set; **one `KDSFront` and one `KDSBack` per target**; a chosen plane is kept at
  least `SelectionTimeLimit` (NKID_00: 1.5 s) and re-checked with `CanDoKDS`;
* the chosen plane's phase (`KDSPhase` +0x35ba, timer +0x35bc) is driven by 0x147cd5100 / 0x147cd52f0: FrontEntrance
  (FrontEntranceTimeLimit, NKID_00 24 s) <-> FrontLead (FrontLeadTimeLimit, 12 s) by target check vfunc 0xb68;
  BackEntrance <-> BackChase (no time limit) by vfunc 0xb70; timer out or deselection -> None (FCS reset). Base AI
  planes return false for 0xb68/0xb70 (overridden on player / wingman / bot classes).
* `+0x35b9` (selectable) is saved and cleared while a PursuerTarget task with its flag at task+0xa8 runs (OnEnter
  0x147bd5a40, restored on exit / abort) and while ReturnToUnitCircle runs (0x147bd2200). PursuerTarget's Tick also
  returns Complete as soon as a KDS phase starts when its flag at task+0xa9 is set (0x147bd6933) [I], so the pursue tree
  is re-walked and can enter the KDS branch. (Argument numbers are in BEHAVIOUR_NATIVE_MOVE.md.)

### 10.3 What it means (rule 22)
* With N enemies on the player, **at most two are in a KDS phase at once** (one front, one back), and only planes that
  are fighters / attackers / multirole / UAV with a KDS-enabled row, engage permission, the player inside their unit
  area, and not in a "no KDS" task.
* `LA_PursueTarget_0400`: RandomSelect 7 : 3. Weight 3 -> `IsKDSP1(true,false)` -> attack; otherwise the RandomSelect is
  skipped and the plane flies the non-attacking LaxSequencer (straight 5 s + random turns). Weight 7 -> Selector
  [`IsKDSP2` -> attack, `IsTrackingAirTarget(true,true)` -> attack]. So outside KDS an ace attacks only while its FCS
  has a current air target; if that also fails, it never attacks. Survival's own set (NLID_SV_Fighter) avoids the KDS
  dependency; keep any attack branch free of `IsKDSP1/2` unless you want at most two attackers.

---------------------------------------------------------------------------------------------------------------------

## 11. Other utility tasks

| factory (wrapper / factory / class, vtable) | args | does | conf |
|---|---|---|---|
| `InstanceExecuteFunction(type)` 0x1473c38a0 / 0x147bce6e0 / CommonExecuteFunction (vt 0x14c59aa98) | `ELiveExecFunctionType` -> +0x70 | 8.4 / 8.5 | [C] |
| `InstanceNotifyEventTrigger(name)` 0x1473c41d0 / 0x147bbbb70 / NotifyEventTrigger (vt 0x14c5aa998, OnEnter 0x147bd5780) | FName -> +0x70 | builds an event record (name, plane) and posts it to the mission event system (0x1470d2460 -> 0x147bf13e0), returns Complete; stock: WingmanAcrobat `"Acrobat01".."04"` | [C] post / event type [I] |
| `InstancePlaySound(event, FVector)` 0x1473c4230 / 0x147bbbc40 / PlaySound (vt 0x14c5aacf8, OnEnter 0x147bd5910) | FName (Wwise event) -> +0x70, FVector offset -> +0x78 | plays the event on the plane through the world sound manager; returns Complete | [C] |
| `InstanceGroup()` 0x1473c3fe0 / 0x147bbb770 / LiveAITaskGroup (OnEnter 0x147bc7a90, Tick 0x147bc7c50, Exit 0x147bc8040) | none | reads `GroupLeadActor` from the blackboard, keeps formation with it (steering 0x147cd16e0 / speed 0x147cd2970); lead dead or missing -> Complete / Failed | [C] key, [I] details |
| `InstanceAvoidObstacle()` 0x1473c3680 / 0x147bba9a0 / ManeuverAvoidObstacle (vt 0x14c59b4d0) | none | obstacle avoidance for state 1 | [C] class |
| `InstanceAvoidRangeAttack()` 0x1473c36c0 / 0x147bbaa60 / AvoidRangeAttack (vt 0x14c59de70) | none | dodge for state 2 (uses plane+0x35a8) | [C] class |
| `InstanceOutOfWorldReaction()` 0x1473c3640 / 0x147bba8e0 / ManeuverOutOfWorldReaction (vt 0x14c5ae290) | none | turn back into the world, state 0 | [C] class |
| `InstancePatrol(f)` 0x1473c3790 / 0x147bbac00 / ManeuverPatrol (vt 0x14c5ae5d0) | float -> +0x70 (stock 200.0) | patrol in the unit area, state 13 | [C] store, [?] meaning |
| `InstanceReturnToUnitCircle(f)` 0x1473c3700 / 0x147bbab20 | float -> +0x70 (stock 1.5) | see BEHAVIOUR_NATIVE_MOVE.md; clears KDS selectable while running | [C] |
| `InstanceSetWingmanState(int)` 0x1473c4d10 / 0x147bbdbf0 (OnEnter 0x147bd7220) | wingman state | wingman tree only | [?] |

The movement tasks (PursuerTarget, MoveAwayFromTarget, Maneuver*, ActivateFlares, WaitTime, ...) are in
BEHAVIOUR_NATIVE_MOVE.md.

---------------------------------------------------------------------------------------------------------------------

## 12. Checklist for writing a custom behaviour

1. Add parents before children, spell every parent name exactly, never reuse a node name (case-insensitive), never name
   a node `Root`. A typo silently cuts the tree from that line on.
2. One child per decorator; one child per probability; probabilities only directly under a RandomSelect.
3. Every task that should stop when a condition changes needs the decorator's abort flag; put that decorator directly
   above the task (or above composites whose parents are Selector / Sequencer).
4. Results do not propagate: a failing Sequencer inside a Sequencer does **not** fail the outer one; the outer one just
   moves on. Build "if A fails, skip B" with a decorator on B, not by nesting.
5. A Selector / Sequencer / Continuation whose child is aborted ends the whole run (restart next frame); Lax variants
   carry on.
6. Weights are relative; bare RandomSelect children weigh 10; Personality weights start at 10.
7. Blackboard keys and RunBehavior slot names must exist in the plane's blackboard asset (unknown blackboard key in a
   decorator = likely crash at level load; unknown slot = Failed).
8. `PursuerDistance` is the distance when the state was entered, in cm; `CurrentAltitudeMeter` is metres; maneuver
   distances are metres (BEHAVIOUR_NATIVE_MOVE.md).
9. AIState is decided natively every frame; a script can only influence it through `SetStateEscapeFromPursuer` /
   `SetMoveAwayFromTarget` (one-shot, gated by priority) or by finishing its slot tree (which lets the state machine
   re-decide).
10. The tree is built once per module per world and shared; any Lua-side state in the module is shared by every plane.
11. Avoid `Parallel` anywhere except as the last child of its parent (section 4, untested).

---------------------------------------------------------------------------------------------------------------------

## 13. Address index (other functions)

| what | address |
|---|---|
| FindByName | 0x147bb9fd0 |
| collect descendants / tasks | 0x147bba090 / 0x147bba1a0 |
| nearest composite ancestor | 0x147bba060 |
| LiveAIBehavior::Tick / Step / Enter / RunTask / Finish / MarkPending | 0x147c6a130 / 0x147c6a4f0 / 0x147c6a2d0 / 0x147c6a610 / 0x147c6a9b0 / 0x147c6aa50 |
| stack reset, index get / set | 0x147c6ab80, 0x147c6ac40 / 0x147c6adc0 |
| composite SelectChild (shared), next, leave | 0x147bb7ce0, 0x147bb7b00, 0x147bb7c30 |
| OnChildFinished: Selector, Sequencer, LaxSequencer, Continuation, LaxContinuation, RandomSelect, Parallel, LaxSelector | 0x147bb8720, 0x147bb8750, 0x147bb8080, 0x147bb7f00, 0x147bb7f90, 0x147bb8710, 0x147bb8130, 0x147bb8000 -> 0x15c869840 |
| RandomSelect SelectChild, Parallel SelectChild / hooks | 0x147bb8430, 0x147bb8110 / 0x147bb8150, 0x147bb8220, 0x147bb8300 |
| IsEqual Evaluate, BB Evaluate | 0x147bb9450, 0x147bb8900 |
| component tick, behaviour tick, UpdateAIState, RequestState | 0x147cef530, 0x147cef500, 0x147cf0640, 0x147cf0e70 |
| KDS manager tick / refresh / select / CanDoKDS; plane SetPhase / UpdatePhase | 0x147d2e550 / 0x147d2e860 / 0x147d2dd30 / 0x147d2e2f0; 0x147cd5100 / 0x147cd52f0 |
| SetEngagement, LiveAIPlane override (KDS toggle) | 0x147c8f9e0, 0x147ccd1c0 (vtable slot 0xca0) |
| UFUNCTIONs `IsInKDSP1` / `IsInKDSP2` (BP-callable, same test as the decorators) | 0x146d43ee0 / 0x146d43f50 (exec 0x146d43ea0 / 0x146d43f10) |

---------------------------------------------------------------------------------------------------------------------

## 14. Open questions and tests worth running
1. Parallel "leave pops the parent" (section 4): log `LiveAIBehavior.CurrentNode` names (UE4SS) during an evade with a
   `LaxContinuation[Parallel, FlyStraight]` branch; does FlyStraight ever become current?
2. Does a run-time write of `PilotRank` change PilotRank-weighted picks immediately (it should, 6), and is the reflected
   PilotRank really plane+0x252c?
3. IsTrackingAirTarget on Survival flights: is the FCS current target set to the player, and does the player's vfunc
   0xae8 report air? This decides whether NLID_0400-style trees attack outside KDS.
4. Meaning of plane+0xdba / +0xdbc (KDS selection gates), +0x2804, and the FCS mode byte (+0xbd/+0xbe == 2).
5. Hold mode (+0x230 / +0x250, 0x147cf1ba0) and the exact POST_UPDATE "unchanged" test.
6. NotifyEventTrigger's event type (which ELiveEventTriggerType a mission listens to for it).
</content>
</invoke>
