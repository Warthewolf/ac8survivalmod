# Unique actions (LastTGT & co.), the "UniqueAction" and "EnemyBehind" triggers (static RE, 2026-10-23)

Static analysis of `AceCombat8.exe` (build of 2026-09-29, image base 0x140000000) only: **nothing here was tested in
game**. Companion to `BEHAVIOUR_NATIVE_LOGIC.md` (sections 8-9: AI state machine, RunBehavior slots),
`BEHAVIOUR_NATIVE_MOVE.md` (the PursuerTarget / ManeuverTurnAdvanced tasks LastTGT uses) and `AI_BEHAVIOURS.md`
(unique-action list). Scratch (scripts, dumps): `C:\Users\Naish\AppData\Local\Temp\claude\...\scratchpad\ua\`
(`ann.py` = annotated disassembly of one function, `strs.py` = string search; both use `tools/re/exe.py`).

Confidence: **[C]** confirmed in disassembly, **[I]** inferred (code seen, meaning is a reading), **[?]** not traced.

Enums (usmap): `ELiveAIPlaneUniqueActionTrigger` {0 Always, 1 OneShot, 2 TargetInRange, 3 SpecifiedObjectIsAttacked,
4 NoneBehavior}; `ELiveAIUniqueActionPriority` {0 Below_Return, 1 Below_Provoke, 2 Above_Provoke, 3 UseWingman};
`ELiveGameObjectUniqueType` (the trigger's selectors) {0 Any, 1 ByName, 2 AnyPlayer, 3 LocalPlayer, 4 OtherPlayer,
5 AnyNPC, 6 AllyNPC, 7 AllyNPC_OtherThanWingmen, 8 EnemyNPC, 9 Wingman}.

---------------------------------------------------------------------------------------------------------------------

## 0. Short answer

* Every row of `DT_UniqueActionListTable` is built **at level start for the whole world, independent of any plane**
  (same pass that builds the LuaSet trees). A request then only creates a small per-plane runner over the cached tree.
  So **any `ALiveAIPlane` can run LastTGT**; nothing has to be in its LuaSet. [C]
* `LiveAIRequestUniqueAction` with a **unit** argument applies to **every plane in the unit** (`ALiveUnit.
  ChildAIGameObjects`). [C]
* `LiveAIResetUniqueAction` with a **unit** argument **does nothing** (the code collects the units and throws the list
  away). Reset works by object name, or with its bool = true for **every AI plane in the world**. [C]
* The "EnemyBehind" trigger (type 0x1b) is evaluated against an event the **player posts every frame** for its
  **current target**; it fires every frame the condition holds (no cooldown) unless the mission disables it. [C]/[I]
* In that trigger, `ByName` + a **unit** argument does **not** mean "any plane of the unit": it compares the plane's
  **callsign text** (trailing digit removed) with the string. Use the **object** argument (one trigger per plane), or the
  tag arguments. [C] code path, [I] that the field is the callsign.
* An unknown action row name **crashes** the game at request time (null dereference). [C]
* With `Below_Return` the unique action outranks blackout, evasion (AttackAvoidance), cloud avoidance, escape,
  move-away, group, provoke and pursue. Only out-of-world, obstacle, range-attack avoidance, "no unit", "outside the unit
  area" and a running ReturnToUnitCircle beat it. No KDS / pilot rank / AI level / permission check anywhere. [C]

---------------------------------------------------------------------------------------------------------------------

## 1. Address index

| what | address | notes |
|---|---|---|
| `ULiveAIRequestUniqueAction` StaticClass / ctor / vtable | 0x146dee810 / 0x146dfbe40 / 0x14c67a180 | `tools/re/execvt.py` [C] |
| Request Execute (slot 87, +0x2b8) | 0x147400e80 | section 2 [C] |
| Request SetArgs (slot 88, +0x2c0) | 0x147401c60 | parses the 8 string args into fields [C] |
| `ULiveAIResetUniqueAction` vtable / Execute / SetArgs | 0x14c679e10 / 0x147401f50 / 0x1473ff0d0 | section 3 [C] |
| `ULiveAIStateComponent::RequestUniqueAction(FName row, const FLiveAIUniqueActionRequest*)` | 0x147cf22a0 | section 4 [C] |
| `ULiveAIStateComponent::EndUniqueAction()` | 0x147cf23b0 | aborts + clears [C] |
| `ULiveAIStateComponent::TryUniqueAction()` (called from UpdateAIState) | 0x147cf1ba0 | section 5 [C] |
| UpdateAIState (priority chain) | 0x147cf0640 | its unique-action points: section 5 [C] |
| set blackboard object `UniqueActionBehavior` | 0x147cf1fa0 | component vfunc +0x500 [C] |
| AI subsystem (`ULiveAILuaWorldSubsystem`) getter from a world | 0x1473be790 | world+0x888 subsystems [C] |
| level-start build of all LuaSets **and all unique actions** | 0x1473b39a0 | subsystem vtable 0x14c532b50 slot +0x318 [C] (slot meaning [I]) |
| build one unique action into the cache | 0x1473b56e0 | section 4.1 [C] |
| copy the UniqueAction DataTable row map | 0x147c89d30 | reads `LiveAIDataInstance+0x528` [C] |
| runner (`ULiveAIBehavior`) init | 0x147c69db0 | sets runner+0x58 = 1 at the end [C] |
| runner Tick (posts the 0xae event) | 0x147c6a130 | section 6 [C] |
| POST_UPDATE_AI_STATE (ExecuteFunction type 1, OnEnter) | 0x147bc3530 | clears OneShot actions [C] |
| EnemyBehind event vtable (13 slots, slot 1 returns 0x1b) | 0x14cb78448 | Match = slot 12 0x147440b60 [C] |
| EnemyBehind geometry test | 0x147441e20 | section 7.3 [C] |
| selector list builder / selector matcher / ByName matcher | 0x14743ace0 / 0x14743b790 / 0x14743b150 | section 7.2 [C] |
| player plane: posts EnemyBehind for its current target, every tick | 0x147d575d0 (called from the player tick at 0x147d56345) | [C] |
| AI plane: posts EnemyBehind for its own FCS target | in 0x147ccec0d (AI tick) | [C] |
| UniqueActionExecuted event vtable (slot 1 returns 0xae) / its Match | 0x14cb773a0 / 0x147464f60 | section 6 [C] |
| per-trigger check: active flag, LifeCount, MonitorEvents, priority, then event Match | 0x147435060 (Match call at 0x14743516c) | [C] |

### ULiveAIStateComponent fields (component = plane+0x2808)

`+0x224` active requested state (16 = none), `+0x225` state snapshot, and the reflected `UniqueActionInfo`
(`LiveAIUniqueActionRequestInfo`) plus native fields around it [C]:

| off | field | written by |
|---|---|---|
| +0x230 | u8 **unique action active** | Request = 1; End = 0; POST_UPDATE = 0 for OneShot |
| +0x238 | `UniqueActionBehavior` (the `ULiveAIBehavior` runner) | Request |
| +0x240 | u8 trigger kind (`ELiveAIPlaneUniqueActionTrigger`) | Request |
| +0x248 | `SpecifiedObject` (the exec's target object, may be null) | Request |
| +0x250 | u8 priority (`ELiveAIUniqueActionPriority`) | Request |
| +0x251 | u8 the exec's last bool | Request (read only by SpecifiedObjectIsAttacked) |

**Correction to BEHAVIOUR_NATIVE_LOGIC.md 8.2/8.3:** what that file calls the "hold flag (+0x230)" and "hold kind
(+0x250)" with check 0x147cf1ba0 at chain points 6 / 12 / 15 is this unique-action state: +0x230 = action active,
+0x250 = its priority, 0x147cf1ba0 = TryUniqueAction (section 5).

---------------------------------------------------------------------------------------------------------------------

## 2. LiveAIRequestUniqueAction

### 2.1 Arguments (SetArgs 0x147401c60) [C]
| # | EP type | stock value | field | meaning |
|---|---|---|---|---|
| 0 | 01 object | `EA_Obj_Named_0` | +0x58 FName | AI object by name |
| 1 | 02 unit | NoneSelect | +0x60 FName | unit by name |
| 2 | 0d string | "" | +0x68 FName | **unit tag** (a unit whose `Tags` contain it is selected too) |
| 3 | 0d string | `LastTGT` | +0x70 FName | row name in DT_UniqueActionListTable |
| 4 | 0e enum | Always / OneShot | +0x78 u8 | `ELiveAIPlaneUniqueActionTrigger` (parsed by name; the other 3 values would parse too [I]) |
| 5 | 0e enum | Below_Return / UseWingman | +0x79 u8 | `ELiveAIUniqueActionPriority` |
| 6 | 01 object | NoneSelect (Nightmare UAVs / M002 MiG-21s name a plane) | +0x7c FName | SpecifiedObject (target) |
| 7 | 11 bool | false (all 565 stock records) | +0x84 u8 | copied to component+0x251 |

### 2.2 Execute 0x147400e80 [C]
```
obj = FindObjectByName(ctx+0x38 object list, this+0x58)          0x14741e000 (compares the object's name, +0xf50 iface)
tgt = FindObjectByName(ctx+0x38, this+0x7c)                        0x14741e6e0
req = { active 0, runner 0, trigger = +0x78, SpecifiedObject = tgt, priority = +0x79, bool = +0x84 }
if obj IsA LiveAIPlane && obj+0x2808 (AIStateComponent):  RequestUniqueAction(component, +0x70, &req)
for unit in ctx+0x28 (the context's unit list):
    if unit.Tags (+0x1c8) contains +0x68  or  unit name (iface +0x2a0, vfunc +0x18) == +0x60:  collect
for each collected unit, for each FWeakObjectPtr in unit+0x2c0 (ChildAIGameObjects):
    if valid && IsA LiveAIPlane && +0x2808:  RequestUniqueAction(component, +0x70, &req)
```
* The object and unit paths are independent: naming both requests twice (harmless, the second replaces the first).
* Only `ALiveAIPlane`s: ground units / ships are skipped silently.
* `ctx+0x28` is the same unit list `LiveAIEngagementOrder` (Execute 0x1473f3ee0 -> 0x1473f2380) walks for its unit
  argument, which already works on Survival's pool flights; so Survival's spawned units are in it [I, strong].
  `ChildAIGameObjects` is the array the runtime's `SV_UnitAlive` counts [C offset, from SPAWN_SYSTEM.md].

---------------------------------------------------------------------------------------------------------------------

## 3. LiveAIResetUniqueAction (Execute 0x147401f50) [C]
Args: `01` object (+0x58) | `02` unit (+0x60) | `0d` tag (+0x68) | `11` bool (+0x70).
* **bool = true**: walks the world's AI plane list (`0x14721cb50(world)+0x148`) and calls `EndUniqueAction` on
  **every** LiveAIPlane, then returns (object / unit ignored).
* bool = false: object by name -> `EndUniqueAction`. Then it collects the units matching the tag / name exactly like
  the request ... and **frees the list without touching them**. A unit-only reset is a no-op.
* Stock uses object resets only: M002 MiG-21s / Tasha and M023 Barrier UAVs 3-8 s after their requests, every
  LastTGT ace 30 s (M028: 15 s) after its UniqueAction trigger.

---------------------------------------------------------------------------------------------------------------------

## 4. What a request does to the plane

### 4.1 Where the tree comes from [C]
* `LiveAIDataInstance` (`GameInstance+0x830`) has reflected `UniqueActionTable` at **+0x528** = DT_UniqueActionListTable
  (`/Game/Datatables/AI/DataInstance/Behavior/`), rows `LiveAIUniqueActionLuaTable {LuaScript, Blackboard}`.
* At level start 0x1473b39a0 first builds every LuaSet tree (0x1473b5a30 / 0x1473b46c0, hard rule 20), then copies the
  table's RowMap (0x147c89d30) and for **every row** calls 0x1473b56e0(subsystem, LuaScript, Blackboard, rowName):
  skip if a cache entry already has the same script path (case-insensitive); else `subsystem+0x88 = row.Blackboard`,
  run the script's `Ctor` (0x1473b3c30), append `{FName rowName, FString path, root = subsystem+0x70, path}` (0x30
  bytes) to **`UniqueActionCaches` (subsystem+0xb0)**, clear subsystem+0x70.
* Consequences: all 20 stock actions exist in every level, whatever planes it has; their keys resolve against the
  row's own blackboard. Two rows sharing one LuaScript: only the first gets a cache entry. A row added to the table
  **before the level loads** (AddRow at run time, hard rule 10) would be built too [I] - the way to a Survival-only
  unique action. A row added later is not built.

### 4.2 RequestUniqueAction 0x147cf22a0(component, rowName, req) [C]
```
if component+0x230: EndUniqueAction(component)          // a running action is always cut and restarted
component+0x230.. = *req (0x28 bytes);  component+0x230 = 1
entry = first UniqueActionCaches entry with key == rowName   // NOT FOUND -> rdi = 0 -> reads [0+0x18] -> CRASH
runner = NewObject<ULiveAIBehavior>;  component+0x238 = runner
runner.RootNode (+0x28) = entry.root;  runner+0x70 = rowName
runner.Init(component) 0x147c69db0                       // context, node memory, runner+0x58 = 1
blackboard "UniqueActionBehavior" = runner               // 0x147cf1fa0 -> component vfunc +0x500
```
Nothing else: no state change here. The state moves on the next UpdateAIState (section 5).

### 4.3 EndUniqueAction 0x147cf23b0 [C]
If the runner has a current task: task.OnAbort, task.OnExit, nearest composite's hook 0x2f0. Then blackboard
`UniqueActionBehavior` = null and +0x230..+0x251 cleared. Callers: the reset exec, every new request, the wingman
component (0x147eba790 / 0x147ebab40) and the special-action module below.

---------------------------------------------------------------------------------------------------------------------

## 5. How it runs: the state machine [C]

UpdateAIState (0x147cf0640) asks `TryUniqueAction` (0x147cf1ba0) at three points, by `+0x250`:

| priority | asked at | beats | is beaten by |
|---|---|---|---|
| 0 Below_Return | right after "ReturnToUnitCircle running (plane+0x2660)" | Blackout, AttackAvoidance, CloudAvoidance, EscapeFromPursuer, MoveAwayFromTarget, Group/FollowFormation, Provoke, PursueTarget, Patrol | ReturnToWorld, AvoidObstacle, AvoidRangeAttack, ReturnToUnit (no unit / outside the unit area), a running ReturnToUnitCircle |
| 2 Above_Provoke | after MoveAwayFromTarget | Group/FollowFormation, Provoke, PursueTarget, Patrol | all of the above plus Blackout, AttackAvoidance, Cloud, Escape, MoveAway |
| 1 Below_Provoke | after Provoke | PursueTarget, FollowFormation, Patrol | everything before PursueTarget |
| 3 UseWingman | **never asked** | - | on an enemy plane the action never starts (wingman component only) |

TryUniqueAction by trigger kind (+0x240):
* **0 Always / 1 OneShot**: no condition. Target = SpecifiedObject, else the plane's FCS current target (vfunc 0xcb0).
  If the active state is already 14: keep; else `RequestState(UniqueAction 14)` + blackboard `TargetActor` = target.
  Returns true, so UpdateAIState stops there.
* 2 TargetInRange: as above only while the distance to the target is below a range read from
  `0x147c03400(plane+0xfa8 + 0x1a08)` (an FCS / weapon range [I]).
* 3 SpecifiedObjectIsAttacked: SpecifiedObject has a special weapon / missile on it (+0x470 > 0 / +0x522) or a gun
  attacker (+0x27e0, LiveAIPlane), or (bool +0x251) further checks through its +0x528 / +0x530 references [?]; and it
  is alive.
No KDS phase, pilot rank, AI level, `bPermissionTo*`, engagement order or plane category is checked anywhere on this
path; only "is a LiveAIPlane with a state component".

While +0x230 is set, every other chain branch requests its own state whenever the active state differs (instead of the
usual "only if higher priority"), so a beating state (table above) takes over at once, and the next frame the action's
point requests 14 again.

The tree: `LA_AIPlane` has `StateIsUniqueAction` (BlackboardEnum, abort = true) -> `RunBehavior("UniqueActionBehavior")`
(confirmed in the stock Lua). Survival's sets (NLID_SV_Fighter, base NLID_0012_CP) keep the stock root, so the branch is
there [I]. An interruption aborts RunBehavior, whose OnExit clears the runner's CurrentNode: **the action restarts from
its first task** when it comes back.

### How it ends [C]
* **OneShot**: when the action tree's run ends, RunBehavior completes, the root tree reaches POST_UPDATE_AI_STATE
  (0x147bc3530), which clears +0x230 because +0x240 == 1. The state is reset to 16 and the plane goes back to normal.
  LastTGT once = turn (<= 5 s) + 10 s pursuit + turn + 10 s pursuit.
* **Always**: +0x230 stays set; POST resets the state to 16, the next frame TryUniqueAction requests 14 again and the
  runner restarts from its root: **the action loops until LiveAIResetUniqueAction (by object or all-planes), a new
  request, or death**. Stock LastTGT (Always) is ended by an object reset 30 s (M028: 15 s) after the plane's
  `UniqueAction_LastTGT` trigger (section 6). Since that trigger fires at every (re)start, each restart pushes the end
  back: the ace keeps at it until ~30 s after the player stopped triggering it.
* `LiveAIResetUniqueAction` = EndUniqueAction: aborts the current task and clears everything; the plane re-decides
  next frame.

---------------------------------------------------------------------------------------------------------------------

## 6. The "UniqueAction" trigger (EventType 0xae, `LiveAIUniqueActionExecuted`) [C]
* Posted by the **runner's Tick** (0x147c6a130) each time a runner whose +0x70 (row name) is set **starts a run from its
  root**: the first frame after a request, every Always loop, and every restart after an interruption. It is a
  "started", not a "finished" event. Payload: +0x18 row name, +0x20 the owning AI object (runner+0x48).
* Args: `01` object | `0d` row name. Match 0x147464f60: the row-name string must be non-empty and equal, and the object
  arg must equal the owning object's name (object by name only; no unit, no NoneSelect wildcard).
* Stock use: `UniqueAction_LastTGT` (object = the ace) -> `LiveAIResetUniqueAction` on that object 30 s later
  (M028: 15 s), and a remote event 60-90 s later (`LastTGT_Roop`, `LastShadow_Loop`) that re-activates the EnemyBehind
  triggers (M012, M028; in M002/M005/M006/M021/M024 that remote event has no records). With life "-" every restart
  fires it again, so several delayed resets can be pending.

---------------------------------------------------------------------------------------------------------------------

## 7. The "EnemyBehind" trigger (EventType 0x1b, `LiveEnemyBehindEventTrigger`)

### 7.1 Who posts the event [C]
An `FLiveEnemyBehindEvent` (vtable 0x14cb78448; +0x18 **victim**, +0x20 **behind**) is posted:
* by the **player plane every tick** (0x147d575d0 from the player tick): victim = the player's **current target**
  (`player+0x1ae8 -> +0x750`), behind = the player. No current target: nothing is posted.
* by AI planes (AI tick, 0x147ccec0d): victim = the plane's FCS current target, behind = the plane, under a flag
  (plane+0x520) and a distance check (<= 8 km to something [?]).

The event processor checks every trigger of the type against every posted event (0x147435060): trigger active
(SetActiveTrigger state), fire count < LifeCount (0 / "-" = unlimited), MonitorEvents, TriggerPriority, then the event's
Match. There is **no cooldown or edge detection**: with LifeCount "-" the trigger fires **every frame** the condition
holds [C for the checks seen; I that nothing else filters]. M028 deals with it by turning its EnemyBehind triggers off
15-30 s after they fire (`LiveSetActiveTriggerExecution false`) and back on 60 s after `UniqueAction_LastTGT`.

### 7.2 Arguments and matching (Match 0x147440b60) [C]
| # | type | stock (LastTGT) | meaning |
|---|---|---|---|
| 0 | 0e selector | ByName | which objects may be the **victim** (the plane being chased) |
| 1 | 0e selector | LocalPlayer | which objects may be the **chaser** |
| 2 / 3 | 01 object / 02 unit | ace object / NoneSelect | the victim's name list (ByName only) |
| 4 / 5 | 01 / 02 | NoneSelect | the chaser's name list (ByName only) |
| 6 | 10 float | 90.0 | max angle between the two planes' headings, degrees |
| 7 | 10 float | 1000.0 | max sideways offset of the chaser from the victim's flight line, metres |
| 8 | 10 float | 4000.0 | max distance of the chaser behind the victim, along the victim's axis, metres |
| 9 | 0a tag | NoneSelect | tag the **chaser** must carry (`AActor.Tags`, +0x1c8) |
| 10 | 0a tag | NoneSelect | tag the **victim** must carry |
| 11 | 11 bool | false | ByName victim only: if set and the victim has a parent reference (+0x518, flag +0x520 clear), use that object instead [?] |

Order of the test:
1. The chaser's target must be the victim: for a LivePlayerPlane `+0x1ae8 -> +0x750` (its current target), for an AI
   plane its FCS current target. So **the player has to have that plane selected as its target**.
2. Each side: tag (if not NoneSelect) must be in the object's Tags; then the selector:
   * ByName: the name list is built from the object/unit pair: object only -> the object's name must equal it (desc
     Name through the +0xf50 interface, case-insensitive); **unit only -> compared with the object's vfunc +0x988**,
     which for LiveAIPlane (0x147d251a0) returns the localized `CallsignId` text (+0x6e8, from +0x438) with one trailing
     digit removed; both -> both tests. No obj and no unit -> never matches.
   * AnyPlayer / LocalPlayer / OtherPlayer / AnyNPC / AllyNPC / ... / EnemyNPC / Wingman: category tests (EnemyNPC uses
     the hostility test 0x147d1c000 against the local player [I]); the object/unit arguments are **ignored** (so M028's
     `Shadows_EnemyBehind` unit argument does nothing).
3. Geometry (0x147441e20, victim A, chaser B, both from their root components):
   `d = B - A`; `fwdA . d < 0` (B behind A); `|fwdA . d| <= arg8 x 100`; `|fwdA x d| <= arg7 x 100`;
   `fwdA . fwdB >= cos(arg6)` (B flying within arg6 degrees of A's heading).

So the stock LastTGT trigger fires while **the player has the ace targeted, sits up to 4 km behind it, within 1 km of
its line, flying roughly the same way (< 90 deg)**.

---------------------------------------------------------------------------------------------------------------------

## 8. Things that stop or spoil a unique action
| cause | effect | conf |
|---|---|---|
| row name not in DT_UniqueActionListTable (typo, or added after level load) | crash in RequestUniqueAction | [C] |
| object is not an `ALiveAIPlane` / has no state component | skipped silently | [C] |
| object / unit not in the exec context's lists | skipped silently | [C] code, [I] which lists |
| UseWingman on an enemy | never starts | [C] |
| out of world, obstacle, range attack, no unit, outside its unit area, ReturnToUnitCircle running | that state runs instead; the action resumes **from its first task** afterwards | [C] |
| a new request while one runs (e.g. EnemyBehind firing every frame) | the action is cut and restarted every time: stuck in its first task while the trigger keeps firing | [C] |
| Always and no working reset | loops for the plane's whole life | [C] |
| reset with only a unit argument | no-op | [C] |
| KDS phase, pilot rank, AI level, engagement order / permissions, AttackAvoidance | no effect on starting; Below_Return even pre-empts AttackAvoidance (the plane doesn't evade during the action) | [C] |
| LastTGT's own target | its tasks use the blackboard key `LocalPlayer`, not TargetActor: it always goes for the local player | [C] Lua |

Aside [?]: `LiveAISpecialActionExecUniqueBehaviorBase` (code around 0x147c1a1c0, a special-action module with a chance
and a cooldown) also calls RequestUniqueAction; it is how planes can do unique actions on their own (FCS special-action
rows). Not traced.

---------------------------------------------------------------------------------------------------------------------

## 9. Stock usage (all EPs in build/stock)
| action | trigger kind / priority | how many | who |
|---|---|---|---|
| LastTGT | Always / Below_Return | 23 | named aces M002, M005, M006, M012 (x4), M021 (x10), M024, M028 (x5), each from its own EnemyBehind_* trigger (ByName object); reset by object 30 s (M028 15 s) after its UniqueAction trigger |
| Shadow_Kulbit | OneShot / Below_Return | 9 | M028 Shadows |
| Toprak_Kulbit, Ladon_Kulbit, Ladon_Roll | OneShot / Below_Return | 4 / 2 / 3 | M019, M028, M016 |
| Tasha_Cobra, Tasha_Roll | Always / UseWingman (+1 OneShot) | 3 | M002 wingman Tasha, reset 3 s later |
| ms02_mig21_Slalom_L/R | Always / Below_Return, target = Baxter | 4 | M002, reset 7 s later |
| NightmareUAV_ApproachAndDocking / _UnDock | OneShot / Below_Return, target = the X-40 | 24 | M029 |
| UAVCharge_PitchUp / PitchDown | Always / Below_Return | 512 | M023 Barrier UAVs, reset 8 s later |
584 requests, 61 resets. No stock record uses the unit or tag argument of a request or reset, no reset uses the bool,
and no EnemyBehind trigger uses `ByName` + unit.

---------------------------------------------------------------------------------------------------------------------

## 10. What Survival can do

Goal: a top-tier pool flight turns on the player when the player gets behind it.

**A. Event package only (works with today's tools).** Per pool **AI object** (not per unit), one EnemyBehind trigger:
`ByName | LocalPlayer | <AI object name> | NoneSelect | NoneSelect | NoneSelect | 90.0 | 1000.0 | 4000.0 | NoneSelect |
NoneSelect | false`, LifeCount "-". Under it:
* `LiveAIRequestUniqueAction`: `NoneSelect | <the flight's unit> | "" | LastTGT | OneShot | Below_Return | NoneSelect |
  false` gated on the flight's ace flag (the unit form turns the whole flight; put the object name in arg 0 and
  NoneSelect in arg 1 to turn only the plane being chased).
* `LiveSetActiveTriggerExecution(false, <this trigger>)` at once, and `(true, <this trigger>)` on a delay
  (~30-40 s) as a cooldown (M028's pattern). Without it the request repeats every frame and the plane stays in
  LastTGT's first turn while the player keeps it targeted from behind.
* OneShot ends by itself after one LastTGT pass (~25-30 s), so no reset is needed. If Always is wanted, reset by
  **object name** per plane, or with the bool = true (all planes; fine while only Survival's aces use unique actions).
  Never by unit.

The tools in the working tree on 2026-10-23 (`build_ace_moves`) put the **unit** in the EnemyBehind trigger (arg 3) and
reset by unit: per this analysis that trigger never matches (it compares the callsign) and the reset does nothing.
The request by unit is fine.

**B. Tags instead of names [I].** Selector `EnemyNPC` (any hostile NPC) with the victim tag (arg 10) = a Survival tag,
and the request by unit tag (its arg 2): one trigger per tag instead of per object. Needs the tag on the plane actors'
and unit actors' `Tags` (+0x1c8): from the world data's `Tags` [?] or added from Lua at run time [?]. Untested.

**C. Native (most control).** The runtime can call `RequestUniqueAction` 0x147cf22a0 directly:
`(plane+0x2808, FName row, &req)` with `req` = 0x28 bytes `{u8 0, ptr 0, u8 trigger, ptr SpecifiedObject, u8 priority,
u8 flag}` (+0x0, +0x8, +0x10, +0x18, +0x20, +0x21), and `EndUniqueAction` 0x147cf23b0`(plane+0x2808)`. Lua then picks
the plane, the moment (its own behind/angle test, any cooldown) and any row, with no event records. Needs signatures
(mksig) and a row-name check before calling (an unknown row crashes).

**D. Custom unique actions [I].** Rows added to DT_UniqueActionListTable at run time **before Survival's level loads**
(menu time, like the other AddRow tables) would be built with the rest, so Survival could ship its own LA_SV_ unique
scripts (each with its own LuaScript asset; the row's Blackboard decides which keys the script may use).

### Tests worth running
1. Top-tier flight + trigger A: log the flight's `AIStateComponent` (+0x224 state, +0x230) from Lua while getting
   behind it with it targeted; expect state 14 within a frame, then back to normal ~25-30 s later (OneShot).
2. Same with the unit in the trigger (current tools): expect no fire (confirms 7.2).
3. Reset by unit after an Always request: expect the action to keep looping (confirms section 3).
