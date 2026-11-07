# The STORE freeze: what LiveMiniGameManager does to AI objects, and how co-op keeps them flying

Static RE of `AceCombat8.exe` **as of the game update of 2026-11-02** (551,201,904 bytes, file time 2026-11-02 19:48,
image base 0x140000000). Every address below is that build's. Made 2026-11-02 for HOTFIX_NOTES.md open problem 1. **Nothing
here has been run in game.** [C] = read in the disassembly or the reflection data; [I] = inferred.

## Summary
When a minigame starts (the landing / supply STORE is one), `ULiveMiniGameManager` calls one function,
**DeactivateForMinigame 0x1478eb7b0**, over **every ALiveAIGameObject in the level** (`ULiveActorManager::CachedAIGameObjects`).
For each one it does two things that stop it:
1. `ILiveCinematicsSubscriber::SetCinematicMode(true)`: the object's **cinematic mode** byte (actor +0xdf8) goes to 1.
2. If it's activated and alive: **`SetActiveGameObject(false)`**: `bIsActivated` (+0x3f4) goes to 0, its actor tick, its
   controller's tick and its collision go off, its FCS, sound and search stop. Then it's added to DeactivatedListForMinigame or
   DeactivatedList2ForMinigame.

AI objects don't move from their UE actor tick: `ULiveAIGameObjectTickManager` calls each one's game tick
(`TickGame` 0x147d0b4d0) only while `bIsActivated` is 1, and `TickGame` runs the **cinematic tick** (no flight) instead of
the flight tick while cinematic mode is on. So a listed plane has two independent locks. Hotfixes 7-10 turned ticks back
on (neither lock), hotfix 11's `bMinigameAIObject` is never read by this function, and hotfix 12's
`LiveSetActiveGameObject(true)` cleared the first lock but not the second. When the STORE closes, the game's own
**RestoreForMinigame 0x1478eb640** undoes both, which is why the planes move again at once.

**Recommended fix (co-op only):** an inline hook on DeactivateForMinigame (0x1478eb7b0, `kSigMgDeactivate`, 16-byte
prologue) that returns without calling the original while a flag from Lua says co-op is linked. Nothing gets deactivated,
nothing goes into cinematic mode, the lists stay empty, and the stock restore at STORE close has nothing to undo (on an object
that was never changed it's a no-op). Solo, the flag is 0 and the original runs, so the stock freeze stays. No component is
ever switched on, so the renderer crash path of hotfixes 8-12 isn't touched. Confidence in the mechanism: high. Confidence that
skipping it has no side effect in the STORE: medium (section 6, risks).

## 1. Classes, fields and offsets [C: reflection params in the exe, UHT dump in build/liveproject]
`ULiveMiniGameManager : ULiveWorldSubsystem` (size 0x288, vtable 0x14c8497c0, StaticClass 0x146ede470; no UFUNCTIONs):

| off | field | notes |
|---|---|---|
| +0x20 | Outer (the UWorld) | every method gets the world from it |
| +0x60 | CurrentMiniGameObject (ALiveSystemObjectMinigameBase*) | set by RequestMinigame **before** StartMinigameInternal runs |
| +0x68 | DeactivatedListForMinigame (TArray<ALiveAIGameObject*>) | Data, Num +0x70, Max +0x74 |
| +0x78 | HiddenListForMinigame | dead objects (health 0): hidden + collision off |
| +0x88 | DeactivatedList2ForMinigame | |
| +0x98 | DeactivatedVFXListForMinigame (TArray<ALiveVFXActor*>) | VFXActorList entries that were active, paused (vfunc 0x738(true)) |
| +0xa8 | SubLevelSwitcher (spawned in Initialize, 0x1478eac60) | not used by the AI path |
| +0x1a0 | byte | when 0, GameObjectCategory 4 objects are skipped (third branch below) |
| +0x260 / +0x270 | IgnoreLoadLevels / IgnoreUnLoadLevels (TArray<FName>) | |

Getting it: `GetWorldSubsystem<ULiveMiniGameManager>(world)` = 0x147ee01b0 (FSubsystemCollection at UWorld+0x888).

`ULiveActorManager : ULiveWorldSubsystem` (size 0x2b0, getter 0x147208fc0(world)): CachedUnits +0x118, CachedGameObjects
+0x128, CachedPlayerPlanes +0x138, **CachedAIGameObjects +0x148**, CachedAIRootObjects +0x188, FirstPlayerPlane +0x1e0,
CachedUnitSpawner +0x1e8, VFXActorList +0x210, CachedReplaceActorList +0x270.

`ALiveGameObject : APawn` (size 0xf50; interfaces OrcaPlugHolder @+0x318, LiveHasHealth @+0x320, LiveTargetContainer @+0x328,
**LiveCinematicsSubscriber @+0x330**):

| off | field |
|---|---|
| +0x5a bit 2 | AActor bCanBeDamaged; +0x5c bit 7 bActorEnableCollision (SetActorEnableCollision 0x143fd3710) |
| +0x3ac | GameObjectCategory (enum) |
| **+0x3f4** | **bIsActivated** (reflected bool; SetBit 0x147d090b0) |
| +0x458 / +0x468 | AttackingMainWeaponArray / AttackingSpecialWeaponArray |
| +0x508 | AttachedChildGameObjects |
| +0xcc0 | bIsOptimizeGameTick |
| +0xda8 | HealthInternal (int; alive = !(+0xdb8) && HealthInternal x 0.1 > 0) |
| +0xdb9, +0xdbd | non-reflected bytes, both set at BeginPlay (0x147d13914 / 0x147d13b84), cleared at EndPlay |
| **+0xdf8** | **cinematic mode** (non-reflected; = interface+0xac8) |
| +0xdf9 | used by cinematic (= interface+0xac9) |
| +0xdfb | IGCVisibility (enum) |

`ALiveAIGameObject : ALiveGameObject` (size 0x25f0): Unit +0xfa0, FireControlSystemComponent +0xfa8, AIPathTracker +0xfc0,
SearchComponent +0x11e8, **bMinigameAIObject +0x1282** (SetBit 0x146d13f20), bAlwaysTickInTickManager +0x25d8, and the AI
object's own **tick-disabled byte +0x25d9** (its IsActorTickEnabled, vtable +0x488 = 0x147c7edb0, returns `!+0x25d9`; its
SetActorTickEnabled, vtable +0x480 = 0x147c7ed60, writes it).

`ALiveAIPlane` (size 0x4120): primary vtable **0x14c53c4e0**, its ILiveCinematicsSubscriber vtable (at +0x330) **0x14c53d428**.

`ILiveCinematicsSubscriber` (UFUNCTIONs GetSubscriberName, IsCinematicMode, IsUsedByCinematic, SetCinematicMode,
SetUsedByCinematic). Its vtable, `this` = actor+0x330 (slot names from behaviour, [I]; code [C]):

| slot | ALiveAIPlane | does |
|---|---|---|
| +0x10 | 0x147d0bbd0 | IsCinematicMode: `this+0xac8` |
| +0x18 | 0x147c7f240 | **SetCinematicMode(b)**: Unit(+0xfa0)+0x408 = b; if `this+0xac8` changes: write it, call actor vtable +0x908 (OnCinematicModeChanged: ALiveAIPlane 0x147cbcaa0 = base 0x147d0bc70 (children, ...) + its FCS +0xf8 lock flag 4). ALiveGameObject's own is 0x147d0bbe0 (no Unit write) |
| +0x20 | 0x147d0bc20 | IsUsedByCinematic: `this+0xac9` |
| +0x28 | 0x147d0bc30 | SetUsedByCinematic(b): `this+0xac9 = b` |
| +0x30 | 0x147d0bc40 | GetSubscriberName (FString at actor+0x6d8) |

## 2. What opening the STORE does, step by step [C]
1. **RequestMinigame 0x1478ead50** (mgr, ELiveMinigameType type, const params*): if CurrentMiniGameObject's
   MyMinigameType (+0xfb8) / MyMinigameIndex (+0xfbc) are the same, nothing. Else it ends the old one (0x143fd38e0), and
   unless the game mode says no (0x147ec94e0) spawns the new minigame actor (0x1478eb1d0), stores it in +0x60 and calls
2. **StartMinigameInternal 0x1478ec080** (mgr, params). Among other things (player-plane flags; in one branch the
   LiveReturnVolumes held by CachedUnitSpawner switched off, their flags saved; a network event when the minigame is a
   LiveSystemObjectHangarMinigame; `0x147391300(ActorManager, false)` after the deactivation hides and de-collides
   `CachedReplaceActorList`), if CurrentMiniGameObject+0x111b is 0 and
   `(params+0x38 && !Cur+0x14a8) || (!params+0x39 && Cur+0x14ac)` (0x1478ec821-0x1478ec84d; non-reflected minigame bytes),
   it calls (0x1478ec85d, **the only call**)
3. **DeactivateForMinigame 0x1478eb7b0** (mgr, `&ActorManager->CachedAIGameObjects`). For each object `o`:
   - `o->ILiveCinematicsSubscriber.SetCinematicMode(true)` (vtable +0x18 at o+0x330). **Every** object of the array, before
     any check.
   - AttackingMainWeaponArray / AttackingSpecialWeaponArray emptied.
   - The campaign game mode (`0x147ec9770` -> ALiveCampaignGameMode, vtable 0x14cbb1e20) picks the list: vtable +0xbe0
     (0x1471be700: IGCVisibility 2, or category 1 / 2) or +0xbe8 (0x1471be760: IGCVisibility 2, or a boss category) send it
     to **DeactivatedList**; anything else to **DeactivatedList2** (skipped if mgr+0x1a0 == 0 and category 4).
   - Skipped if `bIsActivated` is already 0.
   - Alive: **`0x147d0bd90(o, false, false, false)`** (records a replay / network event 0x12, then tail-calls
     `o->vtable[+0x8e0]` = SetActiveGameObject) and `List.Add(o)`.
   - Dead: SetActorHiddenInGame(true) (vtable +0x360), its CollisionMeshList entries switched off (vtable +0x730 on each),
     vtable +0xbd0 / +0xd08, `HiddenList.Add(o)`.
   - Nothing in this function reads `bMinigameAIObject`.
4. Back in StartMinigameInternal: every **active VFX actor** (ActorManager+0x210, vtable +0x740) gets vtable +0x738(true)
   and goes into DeactivatedVFXList; then more player / HUD setup (0x147ecede0, 0x147ecf080, the weapon pool 0x147395790,
   0x147d0f350 on FirstPlayerPlane).
5. In the same function, when Cur+0x14a8 is 0 (the first condition of step 2), **FirstPlayerPlane's bCanBeDamaged is
   cleared** (`and byte [plane+0x5a], ~4` at 0x1478ec3dd) along with its +0x13b8..+0x13be flags.

`SetActiveGameObject(false)` for an AI plane (vtable +0x8e0 = ALiveAIGameObject 0x147c7f060 -> base ALiveGameObject
0x147d0be40):
- `bIsActivated = 0`; `SetActorEnableCollision(false)` (0x143fd3710).
- vtable +0x8f8 (ALiveAIPlane 0x147ba5b80 -> ALiveAIGameObject 0x147c7e8b0 -> ALiveGameObject 0x147d0c240): FCS stopped
  (0x147bf9a70), **SetActorTickEnabled(false) on the actor and on its Controller (+0x2c8)** (vtable +0x480, i.e. +0x25d9 = 1),
  vtable +0x910 (component handling, 0x147cbc700), AISound stopped, and the AIPathTracker reset only if not in cinematic mode
  (it already is).
- The same for every AttachedChildGameObject (+0x508); a BP event by name (vtable +0x268); SearchComponent vtable +0x2d0(false).

## 3. What keeps a listed plane frozen [C, except where marked]
`ULiveAIGameObjectTickManager` (world subsystem, size 0x140, tick function at +0x30, ExecuteTick 0x147c950e0) moves the AI.
Both of its paths, the plain one **0x147c95490** (over CachedAIRootObjects, then units, then each object and its children
via 0x147c95730) and the budgeted one 0x147c97070, call an object's **TickGame 0x147d0b4d0** only when:
`bIsActivated (+0x3f4) && IsActorTickEnabled() (vtable +0x488: !+0x25d9) && vtable +0xab0 (true for planes) && +0xdb9`.

TickGame itself returns at once when `bIsActivated` is 0. Otherwise it asks **GetGameTickMode 0x147d0b360**, which answers
**3 when `+0xdbd && cinematic mode (+0xdf8)`** (5 not activated / the match not in progress, 4 a global replay state, 2 dead,
1 optimised, 0 normal), and dispatches: 0 -> vtable +0x8b8 (ALiveAIPlane 0x147cbe380: the flight tick, 0x147c7e340,
0x147cc32a0, 0x147cc5f60, 0x147cbf740 ...), 1 -> +0x8c0, 2 -> +0xb98, **3 -> +0x8c8 (ALiveAIPlane 0x147cbedf0: only the stealth
manager +0xc08 and 0x147cbd8f0)**, 4 -> +0x8d0. After the switch it also skips its movement block (0x147cdc660 on +0x910 etc.)
for modes 3 and 5 (`sub dil,3; test dil,0xfd`).

So a listed plane has **two locks**, each enough on its own:
- **Lock A: `bIsActivated` = 0** (plus +0x25d9 = 1): the tick manager and TickGame skip it.
- **Lock B: cinematic mode = 1**: even activated, it runs the cinematic tick, which doesn't fly. ([I] that the flight model is
  driven from the +0x8b8 tick's callees; [C] that the +0x8c8 tick doesn't call them.)

Not involved: the world clock, time dilation (hotfix 6 confirmed), the UE actor tick as such, the SubLevelSwitcher, the
`bMinigameAIObject` flag.

## 4. Why each earlier attempt failed
| attempt | what it did | why the planes stayed frozen |
|---|---|---|
| hotfix 7 | actor / controller tick on, CustomTimeDilation 1 | Turned +0x25d9 back to 0 (the AI object's SetActorTickEnabled is vtable +0x480), but lock A's `bIsActivated` and lock B stayed. [C] |
| hotfixes 8 / 9 | components seen ticking switched back on | Components aren't the gate; TickGame isn't reached. [C] |
| hotfix 10 | list entries "that are components" SetActive(true), the others SetActorTickEnabled(true) | The lists hold actors (ALiveAIGameObject / ALiveVFXActor), never components, so this was hotfix 7 again. [C] |
| hotfix 11 | SetMinigameAIObject(true) before the STORE | DeactivateForMinigame never reads +0x1282. The flag is read by the **IGC** deactivation in ALiveGameMode (0x1478d879f: objects with it are spared from DeactivatedListForIGC +0x620 when the current minigame's vtable +0xd90 says so) and by 0x147c84db0. [C] |
| hotfix 12 | Mission 22's LiveSetActiveGameObject(true) per flight every 2 s | Its Execute (0x1473e3ec0, class vtable 0x14c66a8a0 slot +0x2b8) calls the same `0x147d0bd90(obj, true, ...)`, per unit through 0x147db97f0 (unit+0x2d0's objects). That clears lock A, **not lock B**: SetCinematicMode isn't called, so GetGameTickMode keeps answering 3. ALiveAIGameObject::SetActiveGameObject(true) even skips the AIPathTracker restart while cinematic mode is on. [C] |
| renderer crashes | (hotfixes 8, 10, 11 runs) | Not traced here (the crash addresses are the old build's). [I] Turning on components the game's visibility optimiser (VisibleOptimizationSceneComponents, bIgnoreMeshOptimize ...) or SetActiveGameObject's +0x910 had switched off can leave render state inconsistent. The fix below never touches a component. |

## 5. What un-freezes them: the stock restore [C]
FinishMinigame 0x1478eae20 ends either with a chained minigame (0x1478ed860, e.g. Hangar -> SeamlessOut / TakeOff) or a final
end (0x1478ecae0); both run **ClearAndRestore 0x1478ebd40** (mgr):
1. **RestoreForMinigame 0x1478eb640** (mgr, `&ActorManager->CachedAIGameObjects`). For each object, in this order:
   SetUsedByCinematic(false) (interface +0x28); if it's in DeactivatedList or DeactivatedList2:
   `0x147d0bd90(o, true, false, false)`; if in HiddenList: SetActorHiddenInGame(false), 0x147c85510(o,1,1,1), vtable
   +0xd08(o, true); then **SetCinematicMode(false)** (interface +0x18). Membership is looked up in the lists; the loop is over
   all AI objects.
2. `0x147391300(ActorManager, true)`: the replace actors shown again.
3. DeactivatedList / HiddenList / DeactivatedList2 emptied (Num = 0); every VFX actor in the VFX list gets vtable +0x738(false),
   then that list is emptied too.
A chained minigame then runs RequestMinigame -> StartMinigameInternal again, and may deactivate again.

## 6. Recommended fix: skip DeactivateForMinigame in co-op
**Hook point:** DeactivateForMinigame **0x1478eb7b0**, `void (ULiveMiniGameManager* mgr, TArray<ALiveAIGameObject*>* objs)`.
One caller (0x1478ec85d), no pointer references. Prologue for `HookInline`: **16 bytes**, no RIP-relative operand
(`4C 8B DC` mov r11,rsp | `41 54` | `41 56` | `41 57` | `48 83 EC 50` | `4C 8B 3A` mov r15,[rdx]).

```c
/* sigs.h: kSigMgDeactivate (section 9); survival_rt.c: add to FindFunctions' pattern table and HookInline it */
typedef void (*MgDeactivateFn)(uint8_t* mgr, uint8_t* objs);
static MgDeactivateFn g_nextMgDeactivate;
static volatile LONG  g_storeKeepAI;          /* SV_StoreKeepAI(0/1) from Lua: co-op linked */
static uint8_t*       g_mgLast;               /* the manager and the array, for the log and fallback */
static uint8_t*       g_mgLastObjs;

static void OnMgDeactivate(uint8_t* mgr, uint8_t* objs)
{
    g_mgLast = mgr; g_mgLastObjs = objs;
    int n = objs ? *(int32_t*)(objs + 8) : -1;
    uint8_t* cur = mgr ? *(uint8_t**)(mgr + 0x60) : NULL;       /* the minigame being started */
    int type = (cur && UObjLive(cur) == 1) ? cur[0xfb8] : -1;   /* ELiveMinigameType: 5 Landing 6 SeamlessIn 7 SeamlessOut 8 Hangar */
    if (g_storeKeepAI) {
        Log(L"minigame: type %d starts; its deactivation of %d AI objects skipped (co-op): they keep flying", type, n);
        Crumb(L"minigame deactivation skipped, type %d, %d objects", type, n);
        return;
    }
    g_nextMgDeactivate(mgr, objs);
    Log(L"minigame: type %d deactivated the world's AI: %d objects, lists %d / hidden %d / %d", type, n,
        *(int32_t*)(mgr + 0x70), *(int32_t*)(mgr + 0x80), *(int32_t*)(mgr + 0x90));
}
/* install: HookInline(g_fMgDeactivate, 16, (void*)OnMgDeactivate, (void**)&g_nextMgDeactivate, L"minigame AI deactivation") */
```
Lua side (sv_coop.lua, each tick or on change): `SV_StoreKeepAI((CFG.coop.store_keep_world ~= false and (M.linkedPeers or 0) > 0) and 1 or 0)`.
14 characters (hard rule 25). Joiners can set it too: their copies then stay as they always are; on the host it's what matters.

**Telling the host's STORE apart:** nothing extra is needed. The hook runs on each game for its own minigame, i.e. on the host's
game only when the host lands / opens the STORE. CurrentMiniGameObject (+0x60) is already the new minigame when the hook
runs, so `MyMinigameType` (+0xfb8) says which (Hangar = 8). Restricting the skip to types 5-8 is possible; nothing found
needs it.

**What changes at STORE close:** RestoreForMinigame finds no list entries; it only calls SetUsedByCinematic(false) and
SetCinematicMode(false) on objects already in that state (SetCinematicMode changes nothing when the byte is the same; the AI
plane's override writes Unit+0x408 only when it differs). No SetActiveGameObject(true) is called. [C]

**Risks / side effects**
- The world runs while the host shops: enemies keep fighting the other players, bombers keep hitting the airfield's dummies,
  ground units and ships keep firing. That's the co-op design ("keep it running while others are flying"). With everyone at
  the airfield in a linked session the enemies also keep running (solo-style holds still come from the Lua: spawns, wave
  clock). If that's unwanted, set the flag only when `othersFlying()` is true when the STORE opens, and use the fallback
  below when someone takes off later.
- The host's parked plane: when the deactivation's first condition holds (Cur+0x14a8 == 0), the same StartMinigameInternal
  clears FirstPlayerPlane's bCanBeDamaged (0x1478ec3dd) [C], so it can't be hurt; under the second condition it's unknown.
  Enemies may still aim at it (their orders name "Player").
- Dead objects aren't hidden during the STORE (cosmetic; the host doesn't see the world).
- The replay / network event (0x147d0bd90's 0x12 record) isn't written for them; nothing in Survival uses it.
- VFX pausing (DeactivatedVFXList) and the replace-actor swap still happen, as stock.
- Another mod hooking the same function: HookInline chains onto it.

## 7. Fallback: undo it after the fact (no hook on the deactivation)
If the hook can't be installed (a signature miss after an update), Lua can call a native **SV_MgWake** while the host is in
the STORE. It runs the stock restore, in the stock order, on the game thread (sv_main.lua's tick is inside
`ExecuteInGameThread`):
```c
typedef void (*MgRestoreFn)(uint8_t* mgr, uint8_t* objs);   /* RestoreForMinigame 0x1478eb640, kSigMgRestore */
/* mgr: g_mgLast (or Lua's FindFirstOf("LiveMiniGameManager") address); objs: ActorManager+0x148 (FindFirstOf("LiveActorManager")) */
if (UObjLive(mgr) == 1 && UObjLive(objs - 0x148) == 1 && *(uint8_t**)(mgr + 0x60)) {
    g_mgRestore(mgr, objs);                                  /* SetUsedByCinematic(false), SetActive(true), SetCinematicMode(false) */
    *(int32_t*)(mgr + 0x70) = 0; *(int32_t*)(mgr + 0x80) = 0; *(int32_t*)(mgr + 0x90) = 0;   /* as ClearAndRestore does */
}
```
Emptying the three lists (only Num, as the game does) keeps the stock restore at close from calling SetActiveGameObject(true)
a second time: on an AI object that isn't a no-op (ALiveAIGameObject::SetActiveGameObject resets the AIPathTracker and the
search component each time). The VFX list is left alone (the game unpauses it at close). Downsides against the hook: the
planes stop for up to a tick, and their FCS, sound, search and attacker lists are reset by the deactivation first.

Per object, the same thing by hand (if calling RestoreForMinigame isn't wanted): `iface = o + 0x330; vt = *(void***)iface;`
`((char(*)(void*,char))vt[5])(iface, 0)` (SetUsedByCinematic), `0x147d0bd90(o, 1, 0, 0)` (kSigGoSetActive),
`((char(*)(void*,char))vt[3])(iface, 0)` (SetCinematicMode). Never touch components.

## 8. Probe and test checklist
The fix logs on its own; for the test, also hook RestoreForMinigame (0x1478eb640, `kSigMgRestore`, prologue **15 bytes**:
`48 89 6C 24 18` | `48 89 74 24 20` | `57` | `48 83 EC 20`) **log-only**: call the original, then log
`minigame: restore: lists were %d / %d / %d` and the three bytes below for up to 3 objects of each list (taken before the
call), each checked with UObjLive first. A per-object line, for any AI object `o`:
`active +0x3f4 = %d, cinematic +0xdf8 = %d, tick off +0x25d9 = %d, unit cine (Unit=+0xfa0)+0x408 = %d`.
Put the movement count back on the Lua side, log-only (hotfix 7's "N AI planes, M moved over 50 m in 2 s", no switch-backs),
and the host plane's reflected `bCanBeDamaged` while in the STORE.

What the next co-op test should show (host lands and opens the STORE with a joiner flying):
1. `minigame: type 8 starts; its deactivation of N AI objects skipped (co-op)` (or another type: note which).
2. While in the STORE: planes moving (moved > 0), and per object `active 1, cinematic 0, tick off 0`.
3. At close: `minigame: restore: lists were 0 / 0 / 0`, no crash, planes still moving.
4. Solo (flag 0): `minigame: type 8 deactivated the world's AI: ...` with lists > 0, then `active 0, cinematic 1, tick off 1`
   while frozen, and the restore with the same counts: the stock freeze unchanged.

## 9. Signatures (new exe; masks 1 = fixed byte)
```c
/* DeactivateForMinigame (mgr, &ActorManager->CachedAIGameObjects): the hook point (0x1478eb7b0). Wildcards: the loop's
 * jz rel32 and the float constant's RIP displacement. Ends at "lea rcx,[rbx+0x330]" (the SetCinematicMode call). */
static const uint8_t kSigMgDeactivate[92] = {
    0x4C, 0x8B, 0xDC, 0x41, 0x54, 0x41, 0x56, 0x41, 0x57, 0x48, 0x83, 0xEC,
    0x50, 0x4C, 0x8B, 0x3A, 0x4C, 0x8B, 0xF1, 0x48, 0x63, 0x42, 0x08, 0x4D,
    0x8D, 0x24, 0xC7, 0x4D, 0x3B, 0xFC, 0x0F, 0x84, 0x54, 0x05, 0x00, 0x00,
    0x49, 0x89, 0x5B, 0x08, 0x49, 0x89, 0x6B, 0x10, 0x49, 0x89, 0x73, 0x18,
    0x49, 0x89, 0x7B, 0xE0, 0x4D, 0x89, 0x6B, 0xD8, 0x45, 0x33, 0xED, 0x0F,
    0x29, 0x74, 0x24, 0x30, 0xF3, 0x0F, 0x10, 0x35, 0x24, 0x7B, 0x9A, 0x05,
    0x0F, 0x29, 0x7C, 0x24, 0x20, 0x0F, 0x57, 0xFF, 0x49, 0x8B, 0x1F, 0xB2,
    0x01, 0x48, 0x8D, 0x8B, 0x30, 0x03, 0x00, 0x00,
};
static const uint8_t kSigMgDeactivateMask[92] = {
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
};
/* RestoreForMinigame (mgr, &ActorManager->CachedAIGameObjects) (0x1478eb640): the probe / fallback */
static const uint8_t kSigMgRestore[74] = {
    0x48, 0x89, 0x6C, 0x24, 0x18, 0x48, 0x89, 0x74, 0x24, 0x20, 0x57, 0x48,
    0x83, 0xEC, 0x20, 0x48, 0x8B, 0x32, 0x48, 0x8B, 0xF9, 0x48, 0x63, 0x42,
    0x08, 0x48, 0x8D, 0x2C, 0xC6, 0x48, 0x3B, 0xF5, 0x0F, 0x84, 0x2E, 0x01,
    0x00, 0x00, 0x48, 0x89, 0x5C, 0x24, 0x30, 0x4C, 0x89, 0x74, 0x24, 0x38,
    0x48, 0x8B, 0x1E, 0x33, 0xD2, 0x48, 0x8B, 0x83, 0x30, 0x03, 0x00, 0x00,
    0x48, 0x8D, 0x8B, 0x30, 0x03, 0x00, 0x00, 0xFF, 0x50, 0x28, 0x48, 0x8B,
    0x4F, 0x68,
};
static const uint8_t kSigMgRestoreMask[74] = {
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1,
};
/* 0x147d0bd90: SetActiveGameObject wrapper (obj, bActive, b2, b3): replay event, then obj vtable +0x8e0 */
static const uint8_t kSigGoSetActive[40] = {
    0x48, 0x89, 0x5C, 0x24, 0x18, 0x56, 0x57, 0x41, 0x56, 0x48, 0x83, 0xEC,
    0x30, 0x45, 0x0F, 0xB6, 0xF1, 0x41, 0x0F, 0xB6, 0xF8, 0x0F, 0xB6, 0xF2,
    0x48, 0x8B, 0xD9, 0xE8, 0x70, 0x96, 0x2A, 0xFC, 0x48, 0x8B, 0xC8, 0xE8,
    0x18, 0xC1, 0xB3, 0xFF,
};
static const uint8_t kSigGoSetActiveMask[40] = {
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0,
};
```
Context only (each unique in this build; `python -X utf8 tools/re/mksig.py <va> <min bytes> <name>` prints the C arrays):

| function | address | signature (start) |
|---|---|---|
| ClearAndRestore (mgr) | 0x1478ebd40 | 26 bytes, no wildcards: `48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 57 48 83 EC 20 48 8B 59 20 33 ED` |
| StartMinigameInternal (mgr, params) | 0x1478ec080 | `40 53 56 57 41 54 41 56 48 81 EC B0 01 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4` |
| RequestMinigame (mgr, type, params) | 0x1478ead50 | `48 89 5C 24 10 48 89 6C 24 18 56 48 83 EC 20 48 8B D9 49 8B F0 48 8B 49 60` |
| FinishMinigame (mgr) | 0x1478eae20 | `4C 8B DC 55 53 49 8D AB 58 FF FF FF 48 81 EC 98 01 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 80 00 00 00 48 8B 41 60` |
| TickGame (obj, dt) | 0x147d0b4d0 | `40 53 48 83 EC 30 80 B9 F4 03 00 00 00 48 8B D9 0F 29 74 24 20 0F 28 F1 0F 84 ?? ?? ?? ?? 48 89 7C 24 40` |
| GetGameTickMode (obj) | 0x147d0b360 | `48 89 5C 24 08 57 48 83 EC 20 80 B9 F4 03 00 00 00 48 8B D9 0F 84 ?? ?? ?? ?? 80 B9 BD 0D 00 00 00` |
| AI tick manager, plain path | 0x147c95490 | `40 53 56 41 54 41 55 41 56 48 83 EC 40 48 8B 59 20 4C 8B E9 0F 29 74 24 30 0F 28 F1 48 85 DB 74 0C 48 8B CB E8 ?? ?? ?? ??` |
| ALiveAIPlane SetCinematicMode (iface, b) | 0x147c7f240 | 49 bytes, no wildcards: `40 53 48 83 EC 20 48 8B 81 70 0C 00 00 48 85 C0 74 0E 38 90 08 04 00 00 74 06 88 90 08 04 00 00 38 91 C8 0A 00 00 88 91 C8 0A 00 00 0F 95 C3 74 11` |
| ALiveGameObject SetCinematicMode | 0x147d0bbe0 | `40 53 48 83 EC 20 38 91 C8 0A 00 00 88 91 C8 0A 00 00 0F 95 C3 74 11 48 81 C1 D0 FC FF FF` |
| ALiveAIGameObject SetActiveGameObject | 0x147c7f060 | `48 89 5C 24 20 56 57 41 56 48 83 EC 20 45 0F B6 F1 48 89 6C 24 50 45 33 C9 41 0F B6 E8 0F B6 F2` |
| ALiveGameObject SetActiveGameObject | 0x147d0be40 | `40 55 57 41 56 48 81 EC 10 01 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 84 24 F8 00 00 00 45 0F B6 F0` |
| GetWorldSubsystem<ULiveMiniGameManager> | 0x147ee01b0 | 159 bytes, 20 wildcards (a near-copy of every subsystem getter); prefer Lua's FindFirstOf or the hook's `mgr` |
| LiveSetActiveGameObjectExecution::Execute | 0x1473e3ec0 | (not needed) |

## 10. Open
- Which minigame type does the deactivation in Survival's flow (Landing, SeamlessIn or Hangar), and whether a chained
  SeamlessOut / TakeOff deactivates again: the hook's log line answers it.
- The meaning of the non-reflected minigame bytes behind the condition (Cur+0x111b, +0x14a8, +0x14ac; params +0x38 / +0x39).
- Whether the host's plane is damageable during the STORE when the deactivation runs under the second condition.
- The sub-level side of a minigame (SubLevelSwitcher, `bKeepVisibleMiniGameSubLevels` +0x58 / `bKeepHideMiniGameSubLevels`
  +0x59 of FLiveMinigameSettings, size 0x108, at minigame+0xfc0) wasn't traced: it isn't on the path that freezes the AI.
- The IGC path in ALiveGameMode (around 0x1478d8365: DeactivatedListForIGC +0x620, HiddenListForIGC +0x630,
  VisibleListForIGC +0x640, HiddenVFXListForIGC +0x650) does the same two locks for cinematics and spares
  `bMinigameAIObject` objects. Nothing suggests the STORE runs it; a probe could log those four Nums on the campaign game mode.
- The renderer crashes of 2026-11-01 (old build's 0x142c6c1a0) weren't re-traced.

## How it was found
`tools/re/exe.py` with a private EXE_CACHE; `refl.py`-style reads of the UECodeGen params (FPropertyParamsBaseWithOffset:
offset u16 at +0x32; FBoolPropertyParams: SizeOfOuter u32 at +0x34, SetBit at +0x38; FClassParams: count bitfield at +0x38,
interfaces {ClassFunc, Offset} at +0x30). The manager from its StaticClass (the L"ULiveMiniGameManager"+2 reference) ->
constructor (0x159edbee0, vtable) -> the getter 0x147ee01b0 and its 84 callers -> functions in 0x1478e7000-0x1478f0000 using
+0x68..+0x98 -> 0x1478eb7b0 (`Add` into +0x68 / +0x78 / +0x88) and its one caller. Class names and sizes from each
`GetPrivateStaticClassBody` call; virtual slots from ALiveAIPlane's constructor 0x147cb9ac0 (vtables at +0, +0x330 ...).
