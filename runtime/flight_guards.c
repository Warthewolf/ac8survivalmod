/* flight_guards.c : part of flight.c, #included by it in place after flight_coop2mp.c (one translation unit with
 *  survival_rt.c; never compiled on its own). The guards on the game's own bugs: an AI unit's effect freed under
 *  it (two unit updates), whether a UObject is still the engine's (uobj.h, SV_ObjChain), whether the engine is
 *  freeing objects (SV_GcBusy), a weapon's target search reading a freed unit (safecall.h), AI path tracking
 *  reading a freed object (pathguard.h); and the STORE freeze (DeactivateForMinigame, SV_StoreKeepAI). */

/* ---- a game bug guarded: an AI unit's effect freed under it (runtime 0.32.6) -------------------------------------
 * Some AI units' per-frame update (0x147cb2850, slot 279 of their class's vtable: sigs.h kSigUnitFxFrame) moves an
 * effect component they spawned (+0x2690) to the unit every frame, checking only its garbage flag. Once that component
 * is destroyed (an effect that ends destroys itself) its memory is freed at the next garbage collection, the flag goes
 * with it, and the next move calls through a freed vtable: the co-op run of 2026-10-31, the host and two joiners
 * crashed there (0x1442c3e9b) within the same minute. The guard lets go of the component the moment it's marked
 * destroyed, before it can be freed; the game skips the move with nothing held. A live component is never touched. */
#define UFX_OFF             0x2690
#define RF_MIRRORED_GARBAGE 0x40000000u
typedef void (*UnitFxFrameFn)(uint8_t* self, float dt);
static uint8_t*      g_fUnitFxFrame;                       /* found by FindFunctions */
static UnitFxFrameFn g_nextUnitFxFrame;
static uint32_t      g_ufxLetGo;

/* ---- whether a UObject is still the engine's (runtime 0.32.8) ----------------------------------------------------
 * A garbage flag only says so until the object is freed: the co-op run of 2026-10-31 (11:57, a joiner, the round after
 * the Ladons) crashed in the effect move again past the 0.32.6 guard, its effect freed (and its memory taken by
 * something else) while the unit's update wasn't running, so the guard never saw the flag. GUObjectArray says it at any
 * time: the object's slot (its InternalIndex, +0xC) must still hold it, not marked garbage (internal flag 1 << 21) or
 * unreachable (the GC's flag of the moment). The game's own weak-pointer lookup does the same (inlined 1,429 times, all
 * on the same globals); UoFind reads them from one of those, in the target entry check (kSigTargetCheck). */
#include "uobj.h"
static uint8_t*       g_fTargetCheck;                       /* found by FindFunctions */

/* SV_ObjChain(address) -> 1 the object and every outer above it are live (GUObjectArray), 0 one isn't, -1 can't tell:
 * Scripts/sv_core.lua nameOf asks before UE4SS walks the chain for a full name (uobj.h UObjChainLive) */
static int L_ObjChain(void* lua)
{
    uint8_t* o = ArgObject(lua);
    if (!o) return Ret(lua, 0);
    /* (hotfix8) every object of the chain must be committed, readable memory before UObjLive reads it (+0xC, +0x20):
     * Lua asked about an object of a level already unloaded (the host's quit to the main menu, 2026-11-01 01:13:14),
     * its memory released, and UObjLive's first read crashed (main.dll+0x14735, reading +0xC). Not live, then. */
    const uint8_t* p = o;
    for (int depth = 0; p && depth < 64; ++depth) {
        if (((uintptr_t)p & 7) || !Readable(p, 0x28)) return Ret(lua, 0);
        p = *(const uint8_t* const*)(p + 0x20);
    }
    return Ret(lua, UObjChainLive(o));
}

/* ---- whether the engine is freeing objects (runtime 0.32.21) ------------------------------------------------------
 * UE 5.4's IsIncrementalPurgePending(): GObjIncrementalPurgeIsInProgress || GObjPurgeIsRequired, both read by
 * IncrementalPurgeGarbage's early-out (sigs.h kSigPurgeGarbage; 0x1419c8590 in the 2026-11-02 build, the flags at
 * 0x14e41bae0 / 0x14e41bae8). While either is set, objects destroyed are waiting to be freed (or being freed on the async
 * purge thread): Scripts/sv_core.lua walkHold holds its FindAllOf walks then (crash 2c of 2026-11-01: UE4SS's FindAllOf
 * reading a freed object right after mass destruction). SV_GcBusy() -> 1 busy, 0 not, -1 the flags weren't found. */
static uint8_t*          g_fPurgeGarbage;                   /* found by FindFunctions */
static volatile uint8_t* g_gcPurgeRequired;
static volatile uint8_t* g_gcPurgeInProgress;

static void GcFind(void)
{
    uint8_t* f = g_fPurgeGarbage;
    if (!f || f[0x2d] != 0x0F || f[0x2e] != 0xB6 || f[0x2f] != 0x05 || f[0x38] != 0x38 || f[0x39] != 0x05) {
        Log(L"guard: the engine's purge flags weren't found (IncrementalPurgeGarbage %p; another game build?): SV_GcBusy answers -1", f);
        return;
    }
    uint8_t* req = RipRel(f + 0x2d, 7);
    uint8_t* inProg = RipRel(f + 0x38, 6);
    if (!InGame(req) || !InGame(inProg) || !Readable(req, 1) || !Readable(inProg, 1)) {
        Log(L"guard: the engine's purge flags %p / %p aren't the game's data: SV_GcBusy answers -1", req, inProg);
        return;
    }
    g_gcPurgeRequired = req;
    g_gcPurgeInProgress = inProg;
    Log(L"guard: the engine's purge flags: purge required at %p (now %d), incremental purge in progress at %p (now %d), from "
        L"IncrementalPurgeGarbage %p: SV_GcBusy", req, (int32_t)*req, inProg, (int32_t)*inProg, f);
}

static int L_GcBusy(void* lua)
{
    if (!g_gcPurgeRequired || !g_gcPurgeInProgress) return Ret(lua, -1);
    return Ret(lua, (*g_gcPurgeRequired || *g_gcPurgeInProgress) ? 1 : 0);
}

/* (0.32.22) the same for the runtime: 1 a purge is pending or running (the teardown gate's "unreachable" test) */
static int GcPurgePending(void)
{
    return g_gcPurgeRequired && g_gcPurgeInProgress && (*g_gcPurgeRequired || *g_gcPurgeInProgress);
}

static void UoFind(void)
{
    if (!g_fTargetCheck || g_fTargetCheck[0xe0] != 0xE8) { Log(L"guard: GUObjectArray not found (another game build?): liveness by flags only"); return; }
    uint8_t* f = Rel32(g_fTargetCheck + 0xe0);              /* 0x147443cb0 */
    if (!InGame(f) || f[0x78] != 0x3B || f[0x79] != 0x05 || f[0x8d] != 0x48 || f[0x8e] != 0x8B || f[0x8f] != 0x05 ||
        f[0xa7] != 0x8B || f[0xa8] != 0x0D) {
        Log(L"guard: the target check's GUObjectArray lookup %p isn't the expected code: liveness by flags only", f);
        return;
    }
    g_uoNum    = (int32_t*)RipRel(f + 0x78, 6);
    g_uoChunks = (uint8_t* const* volatile*)RipRel(f + 0x8d, 7);
    g_uoGcFlag = (uint32_t*)RipRel(f + 0xa7, 6);
    Log(L"guard: GUObjectArray chunks at %p, count at %p (%d objects), GC flag at %p (now %x)", (void*)g_uoChunks, (void*)g_uoNum,
        *g_uoNum, (void*)g_uoGcFlag, *g_uoGcFlag);
}

static void OnUnitFxFrame(uint8_t* self, float dt)
{
    uint8_t** held = self ? (uint8_t**)(self + UFX_OFF) : NULL;
    if (held && Readable(held, 8) && *held) {
        uint8_t* c = *held;
        int gone = !Readable(c, 0x10) || (*(uint32_t*)(c + 8) & RF_MIRRORED_GARBAGE);
        if (!gone && UObjLive(c) == 0) gone = 2;           /* (freed already: its flag went with it) */
        if (gone) {
            *held = NULL;
            if (g_ufxLetGo < 64) Crumb(L"guard: an AI unit's effect %p (unit %p) let go (%s)", c, self, gone == 2 ? L"freed" : L"destroyed");
            if (g_ufxLetGo++ < 8)
                Log(L"guard: an AI unit's effect %p (unit %p, +0x2690) was %s: let go (%u so far)", c, self,
                    gone == 2 ? L"freed already (not in GUObjectArray)" : L"destroyed, before it's freed", g_ufxLetGo);
        }
    }
    g_nextUnitFxFrame(self, dt);
}

typedef struct { uint64_t want; void** slots[4]; int n; } UfxScan;
static void UfxScanRegion(uint8_t* p, size_t n, void* vctx)
{
    UfxScan* c = (UfxScan*)vctx;
    uint8_t* a = (uint8_t*)(((uintptr_t)p + 7) & ~(uintptr_t)7);
    for (; a + 8 <= p + n && c->n < 4; a += 8)
        if (*(uint64_t*)a == c->want) c->slots[c->n++] = (void**)a;
}

/* every vtable slot holding the update (data sections only), each pointed at the guard */
static void UfxInstall(void)
{
    if (!g_fUnitFxFrame) { Log(L"guard: the AI unit effect update wasn't found (another game build?): not guarded"); return; }
    UfxScan c = { (uint64_t)(uintptr_t)g_fUnitFxFrame, { 0 }, 0 };
    for (int s = 0; s < g_nsec && c.n < 4; ++s)
        if (!(g_sec[s].ch & IMAGE_SCN_MEM_EXECUTE)) ForRegions(g_sec[s].start, g_sec[s].len, UfxScanRegion, &c);
    if (!c.n) { Log(L"guard: the AI unit effect update %p is in no vtable: not guarded", g_fUnitFxFrame); return; }
    /* (the next is the update itself, set before any slot points at the guard: the slots were found holding it) */
    g_nextUnitFxFrame = (UnitFxFrameFn)g_fUnitFxFrame;
    for (int i = 0; i < c.n; ++i) {
        void* prev = NULL;
        HookSlot(c.slots[i], (void*)OnUnitFxFrame, &prev, L"guard: AI unit effect update");
    }
}

/* ---- the same bug in a second unit update (runtime 0.32.16) ------------------------------------------------------
 * sigs.h kSigUnitFx2Frame: 0x147cb86c0 (self, float dt) calls through the component held at +0x42c0 checking only its
 * garbage flag; a joiner crashed there on 2026-11-01 (a jump to 0 through a freed vtable). Let go the same way. */
#define UFX2_OFF 0x42c0
static uint8_t*      g_fUnitFx2Frame;                      /* found by FindFunctions */
static UnitFxFrameFn g_nextUnitFx2Frame;
static uint32_t      g_ufx2LetGo;

static void OnUnitFx2Frame(uint8_t* self, float dt)
{
    /* (0.32.17) +0x42c8 too: the host's crash of 2026-11-01 23:26 (a Ladon round), the next helper 0x147cba030 calling
     * through a freed component held at +0x42c8 (0x147cba299, `call [rax+0x2c8]`), past 0.32.16's +0x42c0 guard */
    static const uint32_t offs[2] = { UFX2_OFF, 0x42c8 };
    for (int i = 0; self && i < 2; ++i) {
        uint8_t** held = (uint8_t**)(self + offs[i]);
        if (!Readable(held, 8) || !*held) continue;
        uint8_t* c = *held;
        int gone = !Readable(c, 0x10) || (*(uint32_t*)(c + 8) & RF_MIRRORED_GARBAGE);
        if (!gone && UObjLive(c) == 0) gone = 2;
        if (gone) {
            *held = NULL;
            if (g_ufx2LetGo < 64) Crumb(L"guard: an AI unit's +0x%x component %p (unit %p) let go (%s)", offs[i], c, self, gone == 2 ? L"freed" : L"destroyed");
            if (g_ufx2LetGo++ < 8)
                Log(L"guard: an AI unit's component %p (unit %p, +0x%x) was %s: let go (%u so far)", c, self, offs[i],
                    gone == 2 ? L"freed already (not in GUObjectArray)" : L"destroyed, before it's freed", g_ufx2LetGo);
        }
    }
    g_nextUnitFx2Frame(self, dt);
}

static void Ufx2Install(void)
{
    if (!g_fUnitFx2Frame) { Log(L"guard: the second AI unit update wasn't found (another game build?): not guarded"); return; }
    UfxScan c = { (uint64_t)(uintptr_t)g_fUnitFx2Frame, { 0 }, 0 };
    for (int s = 0; s < g_nsec && c.n < 4; ++s)
        if (!(g_sec[s].ch & IMAGE_SCN_MEM_EXECUTE)) ForRegions(g_sec[s].start, g_sec[s].len, UfxScanRegion, &c);
    if (!c.n) { Log(L"guard: the second AI unit update %p is in no vtable: not guarded", g_fUnitFx2Frame); return; }
    g_nextUnitFx2Frame = (UnitFxFrameFn)g_fUnitFx2Frame;
    for (int i = 0; i < c.n; ++i) {
        void* prev = NULL;
        HookSlot(c.slots[i], (void*)OnUnitFx2Frame, &prev, L"guard: second AI unit update (+0x42c0)");
    }
}

/* ---- a game bug guarded: a weapon's target search reading a freed unit (runtime 0.32.8) -------------------------
 * Each unit a weapon can aim at has target entries, of a family of classes over one base (vtables sharing its slots
 * +0x00, +0x18, +0x28, +0x50); a weapon's search asks every entry, on worker threads (the ParallelFor 0x1474703c0 ->
 * 0x147434e50 -> 0x147435060: slot +0x60 (entry, query, a, b) -> bool, false: not a target). The entries keep a weak
 * pointer to their unit's actor at +0x20, and some read it without a null check. Entries left behind by a unit that's
 * gone crashed the co-op host twice on 2026-10-31: at 11:24 (the Alicorn round: class 0x14cb78378's check 0x147443690
 * reading its game object +0x18, the class gone: IsA at 0x1470d2200) and at 12:07 (round 10's start, as Survival
 * recycled the flights flown before, destroying their planes: class 0x14cb77dc8's 0x1474515a0 using the weak actor,
 * NULL, at 0x147450468); and the T4b replaced plane (+0x28, class 0x14cb78378's raw actor). The guard answers "not a
 * target" for an entry whose actor was set and is gone (UWeakLive) in a class that uses it unchecked (TcWeakUnchecked:
 * 3 of them), or, in the first class (sigs.h kSigTargetCheck), whose game object or actor isn't live (UObjLive), and
 * lets the game check the rest. */
/* Runtime 0.32.12: the classes whose check uses its unit's world unchecked too (TcWorldUnchecked: the world getter
 * 0x143fc1ca0, sigs.h kSigWorldOf, answers NULL for an object being destroyed, and some 20 checks pass that straight on:
 * Alyssa's game, 2026-10-31 00:50 on 0.73.37, crashed in class 0x147454050's, NULL + 0x898, seconds after 13 enemy copies
 * were taken down and their flights spawned again), and every guarded check runs through ScCall4 (safecall.h): a fault
 * inside it comes back as "not a target", logged, instead of taking the game down. */
/* Runtime 0.32.21: what the family is, and every event's objects. The "target entries" are the game's EVENTS
 * (FLive*Event: slot 1 answers the event type, a trigger's EventType) and slot +0x60 is their Match(event, trigger, a, b):
 * the event processor (0x147420eb0 in the 2026-11-02 build) runs a ParallelFor over the triggers of the event's type,
 * and the per-trigger check (0x1474210c0, 0x147435060 before the update: active, LifeCount, MonitorEvents, priority)
 * calls the event's Match (at 0x1474211cc); tools/re/UNIQUE_ACTIONS.md 7. The co-op host's crash of 2026-11-01 10:24
 * (0.73.70, the testers' session S1) was EnemyBehind's Match (type 0x1b; vtable 0x14cb62be8, Match 0x14742ced0 in the
 * 2026-11-02 build, 0x147440b60 before) at +0xc7, just after `call [rax+0xcb0]`: its victim (+0x18) a co-op player's
 * real plane, its chaser (+0x20) an AI game object already freed (IsA LiveAIGameObject still true, its first 8 bytes a
 * heap pointer, the allocator's free list: the "vtable" slot read 0, rip 0). Events are queued as shared pointers
 * holding raw object pointers the GC doesn't see, so one can outlive what it names. 0.32.20's scan never saw that class:
 * it overrides base slot +0x50 (its debug text). Now the family is the vtables sharing three base slots that answer an
 * event type (slot 1: `mov al, imm8; ret`; 151 in the 2026-11-02 build, each its own type), a guarded function is
 * hooked in every vtable that holds it, and a fourth kind: a Match that loads an event object (+0x18..+0x30) and tests
 * it as a UObject or calls through it (uobj.h UoEventObjs; 23 classes besides the first, EnemyBehind's +0x18 and +0x20
 * among them) answers "no match" for an event whose object is freed (UObjAllocated: not the garbage test, so an event
 * about an object that still exists is matched as the game would). Those reads are the event's own fields and
 * GUObjectArray, before the game's check runs; ScCall4 (a context capture a call) stays where 0.32.20 had it: the first
 * class, the weak-actor and the world classes, whose faults are inside the game's check. A class of event objects
 * alone calls its check straight on: its Match runs per trigger per event on the workers, EnemyBehind's every frame. */
#include "safecall.h"
typedef uint8_t (*TargetCheckFn)(uint8_t* entry, void* query, void* a, void* b);
#define TC_MAX 64                                           /* (functions guarded: 37 in the 2026-11-02 build) */
#define TC_SCAN_MAX 256                                     /* (vtables of the family looked at; the game has 152) */
#define TCK_FIRST 1                                         /* the class with the game object (+0x18) and actor (+0x28) */
#define TCK_WEAK  2                                         /* its +0x20 weak actor used unchecked */
#define TCK_WORLD 4                                         /* its unit's world passed on unchecked */
#define TCK_OBJS  8                                         /* event objects (g_tcObjs) used as UObjects */
#define TCK_CATCH (TCK_FIRST | TCK_WEAK | TCK_WORLD)        /* (these through ScCall4) */
#define TC_SAMPLE 64                                        /* (the call count: one call in about this many) */
static TargetCheckFn g_tcNext[TC_MAX];
static uint8_t       g_tcKind[TC_MAX];                      /* TCK_* bits */
static uint8_t       g_tcObjs[TC_MAX];                      /* TCK_OBJS: bit (offset >> 3) of each object field */
static int16_t       g_tcType[TC_MAX];                      /* the event type (slot 1's answer), -1 not known: the log's */
/* calls through the guard, sampled (an event and trigger pair whose address bits 4-9 are 0: about 1 in TC_SAMPLE), each
 * class on its own cache line: the workers seldom write and never to a line another class's counter shares */
typedef struct { _Alignas(64) volatile uint32_t n; } TcCount;
static TcCount       g_tcCalls[TC_MAX];
static uint8_t*      g_fWorldOf;                            /* found by FindFunctions (sigs.h kSigWorldOf) */
static int           g_scReady;
static volatile int32_t g_tgtFaults;
static int           g_tcN;
static volatile int32_t g_tgtSkipped, g_evSkipped;

static uint8_t TcCheck(int i, uint8_t* entry, void* query, void* a, void* b)
{
    if (!((((uintptr_t)entry ^ (uintptr_t)query) >> 4) & (TC_SAMPLE - 1))) g_tcCalls[i].n = g_tcCalls[i].n + 1;
    uint8_t kind = g_tcKind[i];
    const wchar_t* why = NULL;
    const uint8_t* obj = NULL;
    int off = 0;
    if (entry && (kind & TCK_FIRST)) {                     /* (its weak actor it tests itself: 0x147443cb0) */
        uint8_t* go    = *(uint8_t**)(entry + 0x18);
        uint8_t* actor = *(uint8_t**)(entry + 0x28);
        if (go && UObjLive(go) == 0) why = L"its game object isn't live";
        else if (actor && UObjLive(actor) == 0) why = L"its actor isn't live";
    } else if (entry) {
        if (kind & TCK_WEAK) {                             /* (only these hold a weak pointer at +0x20) */
            const uint8_t* w = entry + 0x20;
            if (*(const int32_t*)(w + 4) && UWeakLive(w) == 0) why = L"its actor's weak pointer resolves to nothing";
        }
        for (int s = 3; !why && s <= 6; ++s) {             /* (0.32.21) the event's objects: freed ones */
            if (!(g_tcObjs[i] & (1u << s))) continue;
            const uint8_t* o = *(const uint8_t* const*)(entry + s * 8);
            if (o && UObjAllocated(o) == 0) { why = L"freed"; off = s * 8; obj = o; }
        }
    }
    if (off) {
        int32_t n = __atomic_add_fetch(&g_evSkipped, 1, __ATOMIC_RELAXED);
        if (n <= 4 || (n < 100000 && (n & (n - 1)) == 0)) {
            Log(L"guard: an event of type %d not matched: its object at +0x%x (%p) was freed (class %d of %d, event %p; %d so far)",
                (int32_t)g_tcType[i], (uint32_t)off, (void*)obj, i + 1, g_tcN, entry, n);
            Crumb(L"guard: event type %d not matched, its +0x%x object %p freed (event %p; %d so far)", (int32_t)g_tcType[i],
                  (uint32_t)off, (void*)obj, entry, n);
        }
        return 0;
    }
    if (why) {
        int32_t n = __atomic_add_fetch(&g_tgtSkipped, 1, __ATOMIC_RELAXED);
        if (n <= 4 || (n < 100000 && (n & (n - 1)) == 0)) { /* (worker threads: Log is locked; the first few, then 8, 16, ...) */
            Log(L"guard: a weapon's target search skipped a gone unit's entry %p (class %d of %d: %s; %d so far)", entry, i + 1,
                g_tcN, why, n);
            Crumb(L"guard: target search skipped a gone unit's entry %p (class %d: %s; %d so far)", entry, i + 1, why, n);
        }
        return 0;
    }
    if (!(kind & TCK_CATCH)) return g_tcNext[i](entry, query, a, b);   /* (event objects alone: no fault catcher) */
    int faulted = 0;
    void* fa = NULL;
    uint64_t at = 0;
    uint8_t r = ScCall4((ScFn4)g_tcNext[i], entry, query, a, b, &faulted, &fa, &at);
    if (faulted) {
        int32_t n = __atomic_add_fetch(&g_tgtFaults, 1, __ATOMIC_RELAXED);
        if (n <= 4 || (n < 100000 && (n & (n - 1)) == 0)) {
            Log(L"guard: a weapon's target search caught a fault in an entry check (class %d of %d, event type %d, its check %p: "
                L"at %p reading %p): answered not a target (%d so far)", i + 1, g_tcN, (int32_t)g_tcType[i], (void*)g_tcNext[i], fa,
                (void*)(uintptr_t)at, n);
            Crumb(L"guard: target check fault caught, class %d (%p, event type %d) at %p reading %p, entry %p (%d so far)", i + 1,
                  (void*)g_tcNext[i], (int32_t)g_tcType[i], fa, (void*)(uintptr_t)at, entry, n);
        }
    }
    return r;
}
#define TC_THUNK(i) static uint8_t OnTc##i(uint8_t* e, void* q, void* a, void* b) { return TcCheck(i, e, q, a, b); }
TC_THUNK(0) TC_THUNK(1) TC_THUNK(2) TC_THUNK(3) TC_THUNK(4) TC_THUNK(5) TC_THUNK(6) TC_THUNK(7)
TC_THUNK(8) TC_THUNK(9) TC_THUNK(10) TC_THUNK(11) TC_THUNK(12) TC_THUNK(13) TC_THUNK(14) TC_THUNK(15)
TC_THUNK(16) TC_THUNK(17) TC_THUNK(18) TC_THUNK(19) TC_THUNK(20) TC_THUNK(21) TC_THUNK(22) TC_THUNK(23)
TC_THUNK(24) TC_THUNK(25) TC_THUNK(26) TC_THUNK(27) TC_THUNK(28) TC_THUNK(29) TC_THUNK(30) TC_THUNK(31)
TC_THUNK(32) TC_THUNK(33) TC_THUNK(34) TC_THUNK(35) TC_THUNK(36) TC_THUNK(37) TC_THUNK(38) TC_THUNK(39)
TC_THUNK(40) TC_THUNK(41) TC_THUNK(42) TC_THUNK(43) TC_THUNK(44) TC_THUNK(45) TC_THUNK(46) TC_THUNK(47)
TC_THUNK(48) TC_THUNK(49) TC_THUNK(50) TC_THUNK(51) TC_THUNK(52) TC_THUNK(53) TC_THUNK(54) TC_THUNK(55)
TC_THUNK(56) TC_THUNK(57) TC_THUNK(58) TC_THUNK(59) TC_THUNK(60) TC_THUNK(61) TC_THUNK(62) TC_THUNK(63)
static void* const g_tcThunk[TC_MAX] = { (void*)OnTc0, (void*)OnTc1, (void*)OnTc2, (void*)OnTc3, (void*)OnTc4,
                                         (void*)OnTc5, (void*)OnTc6, (void*)OnTc7, (void*)OnTc8, (void*)OnTc9,
                                         (void*)OnTc10, (void*)OnTc11, (void*)OnTc12, (void*)OnTc13, (void*)OnTc14,
                                         (void*)OnTc15, (void*)OnTc16, (void*)OnTc17, (void*)OnTc18, (void*)OnTc19,
                                         (void*)OnTc20, (void*)OnTc21, (void*)OnTc22, (void*)OnTc23, (void*)OnTc24,
                                         (void*)OnTc25, (void*)OnTc26, (void*)OnTc27, (void*)OnTc28, (void*)OnTc29,
                                         (void*)OnTc30, (void*)OnTc31, (void*)OnTc32, (void*)OnTc33, (void*)OnTc34,
                                         (void*)OnTc35, (void*)OnTc36, (void*)OnTc37, (void*)OnTc38, (void*)OnTc39,
                                         (void*)OnTc40, (void*)OnTc41, (void*)OnTc42, (void*)OnTc43, (void*)OnTc44,
                                         (void*)OnTc45, (void*)OnTc46, (void*)OnTc47, (void*)OnTc48, (void*)OnTc49,
                                         (void*)OnTc50, (void*)OnTc51, (void*)OnTc52, (void*)OnTc53, (void*)OnTc54,
                                         (void*)OnTc55, (void*)OnTc56, (void*)OnTc57, (void*)OnTc58, (void*)OnTc59,
                                         (void*)OnTc60, (void*)OnTc61, (void*)OnTc62, (void*)OnTc63 };

/* whether a class's check uses the entry's +0x20 weak actor unchecked: some `lea rcx, [reg+0x20]; call Get` (the game's
 * FWeakObjectPtr::Get, g_tcWeakGet) in its first 0x800 bytes with no `test rax, rax` in the 16 bytes after it and no
 * inline validity test (`bts r32, 21`, the garbage flag) in the 24 before it. Only those get the weak pointer test: a
 * class that tests the pointer handles a gone actor itself (0.32.8 tested every class reading it, and one of those,
 * 0x147447050, skipped thousands of entries it would have answered: the co-op run of 2026-10-31). */
static uint8_t* g_tcWeakGet;
static int TcWeakUnchecked(const uint8_t* f)
{
    for (const uint8_t* p = f; p + 9 <= f + 0x800 && InGame(p + 25); ++p) {
        if (!((p[0] == 0x48 || p[0] == 0x49) && p[1] == 0x8D && (p[2] & 0xF8) == 0x48 && p[2] != 0x4C && p[3] == 0x20 && p[4] == 0xE8 &&
              Rel32((uint8_t*)p + 4) == g_tcWeakGet))
            continue;
        int tested = 0;
        for (const uint8_t* q = p + 9; q + 3 <= p + 9 + 16 && !tested; ++q) tested = q[0] == 0x48 && q[1] == 0x85 && q[2] == 0xC0;
        for (const uint8_t* q = p - 24 >= f ? p - 24 : f; q + 4 <= p && !tested; ++q) tested = q[0] == 0x0F && q[1] == 0xBA && (q[2] & 0xF8) == 0xE8 && q[3] == 0x15;
        if (!tested) return 1;
    }
    return 0;
}

/* the end of the function starting at f: the exe's unwind table, else f + 0x800 */
static const uint8_t* TcFnEnd(const uint8_t* f)
{
    typedef struct { uint32_t begin, end, unwind; } RtFn;
    static RtFn* (*lookup)(uint64_t pc, uint64_t* base, void* hist);
    if (!lookup) lookup = (RtFn* (*)(uint64_t, uint64_t*, void*))GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "RtlLookupFunctionEntry");
    uint64_t base = 0;
    RtFn* rf = lookup ? lookup((uint64_t)(uintptr_t)f, &base, NULL) : NULL;
    if (rf && base && base + rf->begin == (uint64_t)(uintptr_t)f) return (const uint8_t*)(uintptr_t)(base + rf->end);
    return f + 0x800;
}

/* whether a class's check passes its unit's world on unchecked: `call <world getter>; mov rcx, rax; call` inside the
 * function (its bounds from the exe's unwind table; else its first 0x800 bytes) */
static int TcWorldUnchecked(const uint8_t* f)
{
    if (!g_fWorldOf) return 0;
    const uint8_t* end = TcFnEnd(f);
    for (const uint8_t* p = f; p + 9 <= end && InGame(p + 9); ++p)
        if (p[0] == 0xE8 && Rel32((uint8_t*)p) == g_fWorldOf && p[5] == 0x48 && p[6] == 0x8B && p[7] == 0xC8 && p[8] == 0xE8) return 1;
    return 0;
}

/* (0.32.21) the event objects a class's check uses (uobj.h UoEventObjs over its code) */
static uint8_t TcEventObjs(const uint8_t* f)
{
    const uint8_t* end = TcFnEnd(f);
    if (end <= f || !InGame(end + 0x48)) return 0;
    return (uint8_t)UoEventObjs(f, (size_t)(end - f), g_exe, g_exe + g_exeSize);
}

/* the event type a vtable's slot 1 answers (`mov al, imm8; ret`), -1 if it isn't that */
static int TcType(void** vt)
{
    const uint8_t* s1 = (const uint8_t*)vt[1];
    return InGame(s1) && s1[0] == 0xB0 && s1[2] == 0xC3 ? s1[1] : -1;
}

/* the family's vtables: the first class's (whose slot +0x60 is kSigTargetCheck), then every other with its base slots
 * (0.32.21: three, +0x00 +0x18 +0x28; EnemyBehind's +0x50 is its own) */
/* (0.32.21) a vtable is an event class's when it shares those three slots AND answers an event type (its slot 1, the
 * type getter: `mov al, imm8; ret`): 152 vtables share the slots in the 2026-11-02 build, 151 answer a type, each its
 * own; the other (0x14c577918, its +0x60 a stub) isn't looked at. A sibling class sharing the slots without a type
 * getter is never hooked. The counts go to the log: those sharing the 3 slots, those keeping +0x50 too (0.32.20's
 * rule), those with a type getter, the distinct types. */
typedef struct { uint64_t base[4]; void** vt[TC_SCAN_MAX]; int n, n3, n50, nType, nDistinct; uint32_t seen[8]; } TcScan;
static const int kTcBase[4] = { 0x00, 0x18, 0x28, 0x50 };
static void TcScanRegion(uint8_t* p, size_t n, void* vctx)
{
    TcScan* c = (TcScan*)vctx;
    uint8_t* a = (uint8_t*)(((uintptr_t)p + 7) & ~(uintptr_t)7);
    for (; a + 0x68 <= p + n && c->n < TC_SCAN_MAX; a += 8) {
        if (*(uint64_t*)a != c->base[0]) continue;
        int same = 1;
        for (int k = 1; k < 3 && same; ++k) same = *(uint64_t*)(a + kTcBase[k]) == c->base[k];
        uint8_t* f = *(uint8_t**)(a + 0x60);
        if (!same || !InGame(f)) continue;
        ++c->n3;
        if (*(uint64_t*)(a + 0x50) == c->base[3]) ++c->n50;
        int type = TcType((void**)a);
        if (type < 0) continue;                            /* (not an event class: never hooked) */
        ++c->nType;
        if (!(c->seen[type >> 5] & (1u << (type & 31)))) { c->seen[type >> 5] |= 1u << (type & 31); ++c->nDistinct; }
        c->vt[c->n++] = (void**)a;
    }
}

/* a vtable slot pointed at the guard: one aligned 8-byte store (worker threads may read it at any time) */
static int TcSetSlot(void** slot, void* fn)
{
    DWORD old = 0, ignored = 0;
    if (((uintptr_t)slot & 7) || !VirtualProtect(slot, 8, PAGE_READWRITE, &old)) return 0;
    __atomic_store_n(slot, fn, __ATOMIC_SEQ_CST);
    VirtualProtect(slot, 8, old, &ignored);
    return 1;
}

static void TcAppend(wchar_t* buf, size_t cap, const wchar_t* fmt, ...)
{
    size_t n = WLen(buf);
    if (n + 2 >= cap) return;
    va_list ap;
    va_start(ap, fmt);
    VFmt(buf + n, cap - n, fmt, ap);
    va_end(ap);
}

static void TgtInstall(void)
{
    if (!g_fTargetCheck) { Log(L"guard: the target entry check wasn't found (another game build?): not guarded"); return; }
    if (!g_uoChunks) { Log(L"guard: no GUObjectArray: the target search isn't guarded"); return; }
    g_scReady = ScInit(GetModuleHandleW(L"kernel32.dll"));
    Log(L"guard: the target search's fault catcher %s; the world getter %p", g_scReady ? L"in" : L"NOT in (kernel32's calls missing)",
        g_fWorldOf);
    UfxScan one = { (uint64_t)(uintptr_t)g_fTargetCheck, { 0 }, 0 };
    for (int s = 0; s < g_nsec && one.n < 4; ++s)
        if (!(g_sec[s].ch & IMAGE_SCN_MEM_EXECUTE)) ForRegions(g_sec[s].start, g_sec[s].len, UfxScanRegion, &one);
    if (one.n != 1) { Log(L"guard: the target entry check %p is in %d vtables (1 expected): not guarded", g_fTargetCheck, one.n); return; }
    uint8_t* vtA = (uint8_t*)one.slots[0] - 0x60;
    uint8_t* helper = g_fTargetCheck[0xe0] == 0xE8 ? Rel32(g_fTargetCheck + 0xe0) : NULL;      /* 0x147443cb0 */
    g_tcWeakGet = (helper && helper[0x38] == 0xE8) ? Rel32(helper + 0x38) : NULL;               /* 0x141ad7cb0 */
    if (!InGame(g_tcWeakGet)) { Log(L"guard: the game's weak pointer Get wasn't found: the target search isn't guarded"); return; }
    static TcScan c;                                       /* (2 KB: off the stack) */
    memset(&c, 0, sizeof(c));
    for (int k = 0; k < 4; ++k) {
        c.base[k] = *(uint64_t*)(vtA + kTcBase[k]);
        if (!InGame((void*)(uintptr_t)c.base[k])) { Log(L"guard: the target entries' vtable %p isn't the expected shape: not guarded", vtA); return; }
    }
    if (TcType((void**)vtA) < 0) { Log(L"guard: the target entries' vtable %p answers no event type: not guarded", vtA); return; }
    for (int s = 0; s < g_nsec && c.n < TC_SCAN_MAX; ++s)
        if (!(g_sec[s].ch & IMAGE_SCN_MEM_EXECUTE)) ForRegions(g_sec[s].start, g_sec[s].len, TcScanRegion, &c);
    Log(L"guard: the event family: %d vtables share its 3 base slots, %d of them its +0x50 too, %d answer an event type (%d "
        L"distinct): those %d looked at, %d not", c.n3, c.n50, c.nType, c.nDistinct, c.n, c.n3 - c.n);
    /* (0.32.21) one guard index a Match function, hooked in every vtable holding it */
    static void* fns[TC_SCAN_MAX];
    static int8_t idxOf[TC_SCAN_MAX];
    static wchar_t objsList[600];
    int nf = 0, alone = 0, slots = 0, kinds[4] = { 0, 0, 0, 0 };
    objsList[0] = 0;
    for (int i = 0; i < c.n; ++i) {
        void** slot = (void**)((uint8_t*)c.vt[i] + 0x60);
        void* fn = *slot;
        int j = 0;
        while (j < nf && fns[j] != fn) ++j;
        if (j == nf) {                                     /* a function not seen yet: which kinds it is */
            fns[nf] = fn; idxOf[nf] = -1; ++nf;
            const uint8_t* f = (const uint8_t*)fn;
            int kind = (uint8_t*)c.vt[i] == vtA ? TCK_FIRST : 0;
            uint8_t objs = 0;
            if (!kind) {
                if (TcWeakUnchecked(f)) kind |= TCK_WEAK;
                if (g_scReady && TcWorldUnchecked(f)) kind |= TCK_WORLD;
                objs = TcEventObjs(f);
                if (objs) kind |= TCK_OBJS;
            }
            if (!kind) { ++alone; continue; }
            if (g_tcN >= TC_MAX) continue;
            int k = g_tcN++;
            g_tcNext[k] = (TargetCheckFn)fn;               /* (set before any slot points at the guard) */
            g_tcKind[k] = (uint8_t)kind;
            g_tcObjs[k] = objs;
            g_tcType[k] = (int16_t)TcType(c.vt[i]);
            idxOf[j] = (int8_t)k;
            for (int b = 0; b < 4; ++b) kinds[b] += (kind >> b) & 1;
            if (objs) {
                TcAppend(objsList, 600, L"%s%d", objsList[0] ? L", " : L"", (int32_t)g_tcType[k]);
                for (int s = 3; s <= 6; ++s) if (objs & (1u << s)) TcAppend(objsList, 600, L" +0x%x", (uint32_t)(s * 8));
            }
        }
        int k = idxOf[j];
        if (k < 0) continue;
        if (TcSetSlot(slot, g_tcThunk[k])) ++slots;
        else Log(L"guard: the event check slot %p (class %d) couldn't be written: not guarded there", (void*)slot, k + 1);
    }
    int caught = 0;
    for (int k = 0; k < g_tcN; ++k) caught += (g_tcKind[k] & TCK_CATCH) != 0;
    Log(L"guard: %d target entry classes guarded in %d vtable slots (the first %d, a weak actor unchecked %d, the world unchecked %d, "
        L"event objects checked %d; %d through the fault catcher, %d called straight on; %d event vtables, %d functions, %d left "
        L"alone%s)", g_tcN, slots, kinds[0], kinds[1], kinds[2], kinds[3], caught, g_tcN - caught, c.n, nf, alone,
        c.n >= TC_SCAN_MAX ? L"; more not looked at" : (g_tcN >= TC_MAX ? L"; TC_MAX reached" : L""));
    Log(L"guard: the event types whose objects are checked (type +offsets): %s", objsList[0] ? objsList : L"none");
}

/* (0.32.21) every 5 minutes in the mission (from FlightInputHook): how busy the guarded checks were (the guard's cost) */
static void TgtLog(void)
{
    static double next;
    if (!g_tcN) return;
    double now = CoNow();
    if (next <= 0) { next = now + 300.0; return; }
    if (now < next) return;
    next = now + 300.0;
    uint32_t total = 0, top = 0;
    int topI = 0;
    for (int i = 0; i < g_tcN; ++i) {
        uint32_t n = g_tcCalls[i].n * TC_SAMPLE;           /* (sampled: about 1 call in TC_SAMPLE counted) */
        g_tcCalls[i].n = 0;
        total += n;
        if (n > top) { top = n; topI = i; }
    }
    Log(L"guard: the guarded event checks, the last 5 minutes: about %u calls (%u a second; the busiest class %d, event type %d, "
        L"about %u, %s); so far events not matched for a freed object %d, gone units' entries skipped %d, faults caught %d", total,
        total / 300u, topI + 1, (int32_t)g_tcType[topI], top, (g_tcKind[topI] & TCK_CATCH) ? L"through the fault catcher" : L"called straight on",
        g_evSkipped, g_tgtSkipped, g_tgtFaults);
}

/* ---- a game bug guarded: AI path tracking reading a freed object (runtime 0.32.22, plan F2) --------------------------
 * Shazzy's two crashes at the round 3 bomber raid (2026-11-02 16:06:37 and 18:02:16, a game worker thread, no mod code on
 * the stack) were in AC8's AI path tracking: ULiveAIPathTickerSubsystem (a world subsystem: PathTrackTickFunction,
 * PathTrackers) ticks every ULiveAIPathTracker (UObject: OwningActor +0x28, OwningAIGameObject +0x30, OwningUnit +0x38,
 * TrackingTargetAIPath +0x40, SplineComponent +0x48; a unit and each AI object hold one, ALiveUnit / ALiveAIGameObject
 * .AIPathTracker) on worker threads: FLivePathTrackTickFunction::ExecuteTick (sigs.h kSigPathTrackTick) takes the
 * subsystem's lock (+0x70) and runs a ParallelFor over PathTrackers (+0x60), each through the TFunctionRef thunk
 * 0x147de3ef0 into the body 0x147dd53f0 (captures, index). The body reads the tracker's AI object's activation (+0x3f4,
 * +0xdb8, +0xda8) and, for a tracker following a path (state +0x60 == 1), updates its native path movement (+0x1c0: a
 * TSharedFromThis class over the base vtable 0x14cbf8550, weak object pointers +0x30 / +0x38 / +0x40 it checks, a weak
 * shared state +0x48 / +0x50) with 0x147ddb3c0 -> its virtual Update (+0x40) -> 0x147ddcea0 -> 0x147ddbf40. The first crash
 * was 0x147ddbf40's `call [rax+0x48]` through a freed object's vtable (0x147ddc6a9, rip 0), the second 0x147ddb860's
 * weak-state pin `mov rbx, [rcx+0x50]` on a freed movement object (rcx garbage): the movement's objects outlive what
 * they point at, a few seconds after Survival destroyed the last bomber flight's unit actor (its trackers').
 * The guard (the target search's way): the thunk (16 bytes: the 7 of `mov edx, [rdx]; jmp body` and int3 padding) is
 * rewritten to `jmp [rip+2]` and our address in its last 8 bytes (two aligned 8-byte stores: the address first, then the
 * jump), so every tracker goes through OnPathTrackItem: a tracker that is freed, or whose objects (+0x28..+0x48) are
 * freed, is left out this frame; the rest run the body through ScCall4 (safecall.h), a fault there coming back as "left
 * out" and that tracker left out for the rest of the level (PtReset at SV_Reset). A tracker's own memory is read only
 * inside the catcher. */
#include "pathguard.h"                                      /* (PtGuarded, OnPathTrackItem, PtReset: tools/checks/pathguard_test.c) */
static uint8_t*          g_fPathTrackTick;                  /* found by FindFunctions (sigs.h kSigPathTrackTick) */
static uint8_t*          g_ptThunk;

static void PtInstall(void)
{
    uint8_t* f = g_fPathTrackTick;
    if (!f) { Log(L"guard: the AI path tracking tick wasn't found (another game build?): not guarded"); return; }
    if (f[0xba] != 0x48 || f[0xbb] != 0x8D || f[0xbc] != 0x05) { Log(L"guard: the AI path tracking tick %p isn't the expected code: not guarded", f); return; }
    uint8_t* th = RipRel(f + 0xba, 7);
    int pad = InGame(th) && InGame(th + 16) && !((uintptr_t)th & 15) && th[0] == 0x8B && th[1] == 0x12 && th[2] == 0xE9;
    for (int k = 7; pad && k < 16; ++k) pad = th[k] == 0xCC;
    if (!pad) { Log(L"guard: the AI path tracking thunk %p isn't `mov edx, [rdx]; jmp` + 9 int3 (hooked by another mod?): not guarded", th); return; }
    uint8_t* body = Rel32(th + 2);
    static const uint8_t kBody[20] = { 0x40, 0x53, 0x48, 0x83, 0xEC, 0x30, 0x48, 0x8B, 0x01, 0x4C, 0x63, 0xC2, 0x48, 0x8B, 0x50,
                                       0x60, 0x4A, 0x8B, 0x1C, 0xC2 };   /* push rbx ... mov rdx, [rax+0x60]; mov rbx, [rdx+r8*8] */
    if (!InGame(body) || memcmp(body, kBody, sizeof(kBody)) != 0) {
        Log(L"guard: the AI path tracking body %p isn't the expected code: not guarded", body);
        return;
    }
    if (g_scTls == 0xFFFFFFFFu) g_scReady = ScInit(GetModuleHandleW(L"kernel32.dll"));
    g_ptBody = (PtBodyFn)body;
    g_ptThunk = th;
    DWORD old = 0, ignored = 0;
    if (!VirtualProtect(th, 16, PAGE_EXECUTE_READWRITE, &old)) { Log(L"guard: the AI path tracking thunk %p couldn't be written: not guarded", th); return; }
    __atomic_store_n((uint64_t*)(th + 8), (uint64_t)(uintptr_t)OnPathTrackItem, __ATOMIC_SEQ_CST);   /* (never run: int3s) */
    __atomic_store_n((uint64_t*)th, 0xCCCC0000000225FFull, __ATOMIC_SEQ_CST);                       /* FF 25 02 00 00 00: jmp [rip+2] */
    VirtualProtect(th, 16, old, &ignored);
    FlushInstructionCache(GetCurrentProcess(), th, 16);
    Log(L"guard: AI path tracking guarded (tick %p, thunk %p -> body %p; trackers with freed objects left out, faults caught: %s)",
        f, th, body, g_scTls != 0xFFFFFFFFu ? L"the fault catcher in" : L"NO fault catcher (kernel32's calls missing)");
}

/* every 5 minutes in the mission (FlightInputHook): how busy the path tracker guard was */
static void PtLog(void)
{
    static double next;
    if (!g_ptThunk) return;
    double now = CoNow();
    if (next <= 0) { next = now + 300.0; return; }
    if (now < next) return;
    next = now + 300.0;
    uint32_t calls = g_ptCalls.n * PT_SAMPLE;
    g_ptCalls.n = 0;
    Log(L"guard: AI path tracking, the last 5 minutes: about %u tracker updates (%u a second); so far left out %d (freed), faults "
        L"caught %d, trackers left out for the level %d", calls, calls / 300u, g_ptSkipped, g_ptFaults,
        g_ptBadN < PT_BAD_MAX ? g_ptBadN : PT_BAD_MAX);
}

/* ---- The STORE freeze (runtime 0.32.20; tools/re/STORE_FREEZE.md) ----------------------------------------------------
 * A minigame's start (the airfield STORE) calls DeactivateForMinigame(mgr, &ActorManager->CachedAIGameObjects), which
 * puts every AI object into cinematic mode and deactivates the live ones: the world's planes stop for every player while
 * the co-op host shops (tests of 2026-11-01). While SV_StoreKeepAI(1) (Lua: co-op linked) the call is skipped, so nothing
 * is deactivated, put into cinematic mode or listed, and the stock restore at the STORE's close finds nothing to undo.
 * No component is touched (switching the minigame's components back on was the likely cause of the renderer crashes of
 * 2026-11-01). Solo (flag 0) the stock freeze stays. RestoreForMinigame is hooked log-only, for the test. */
typedef void (*MgListFn)(uint8_t* mgr, uint8_t* objs);
static uint8_t*        g_fMgDeactivate;                     /* found by FindFunctions (sigs.h kSigMgDeactivate) */
static uint8_t*        g_fMgRestore;                        /* (kSigMgRestore) */
static MgListFn        g_nextMgDeactivate;
static MgListFn        g_nextMgRestore;
static volatile int    g_storeKeepAI;                       /* SV_StoreKeepAI(0 / 1) */

static int MgType(uint8_t* mgr)                             /* the minigame starting / ending: ELiveMinigameType (8 Hangar) */
{
    uint8_t* cur = (mgr && UObjLive(mgr) == 1) ? *(uint8_t**)(mgr + 0x60) : NULL;   /* CurrentMiniGameObject */
    return (cur && UObjLive(cur) == 1) ? cur[0xfb8] : -1;                         /* MyMinigameType */
}

static int MgNum(uint8_t* arr) { return arr ? *(int32_t*)(arr + 8) : -1; }

static void MgLogObjects(const wchar_t* what, uint8_t* list)  /* the first 3 objects of one of the manager's lists */
{
    int n = MgNum(list);
    uint8_t** data = (n > 0) ? *(uint8_t***)list : NULL;
    for (int i = 0; data && i < n && i < 3; ++i) {
        uint8_t* o = data[i];
        if (!o || UObjLive(o) != 1) { Log(L"minigame:   %s[%d] %p: not live", what, i, o); continue; }
        Log(L"minigame:   %s[%d] %p: active +0x3f4 = %d, cinematic +0xdf8 = %d, tick off +0x25d9 = %d", what, i, o,
            (int)o[0x3f4], (int)o[0xdf8], (int)o[0x25d9]);
    }
}

static void OnMgDeactivate(uint8_t* mgr, uint8_t* objs)
{
    int type = MgType(mgr), n = MgNum(objs);
    if (g_storeKeepAI) {
        Log(L"minigame: type %d starts; its deactivation of %d AI objects skipped (co-op): they keep flying", type, n);
        Crumb(L"minigame deactivation skipped, type %d, %d objects", type, n);
        return;
    }
    g_nextMgDeactivate(mgr, objs);
    if (mgr && UObjLive(mgr) == 1) {
        Log(L"minigame: type %d deactivated the world's AI: %d objects; lists %d / hidden %d / %d", type, n,
            MgNum(mgr + 0x68), MgNum(mgr + 0x78), MgNum(mgr + 0x88));
        MgLogObjects(L"deactivated", mgr + 0x68);
    }
}

static void OnMgRestore(uint8_t* mgr, uint8_t* objs)
{
    if (mgr && UObjLive(mgr) == 1) {
        Log(L"minigame: type %d ends: restore of %d AI objects; lists were %d / hidden %d / %d (co-op keep %d)", MgType(mgr),
            MgNum(objs), MgNum(mgr + 0x68), MgNum(mgr + 0x78), MgNum(mgr + 0x88), (int)g_storeKeepAI);
        MgLogObjects(L"listed", mgr + 0x68);
    }
    g_nextMgRestore(mgr, objs);
}

static void MgInstall(void)
{
    if (!g_uoChunks) { Log(L"minigame: no GUObjectArray: the STORE freeze isn't hooked"); return; }
    if (g_fMgDeactivate && HookInline(g_fMgDeactivate, 16, (void*)OnMgDeactivate, (void**)&g_nextMgDeactivate,
                                      L"minigame AI deactivation")) {}
    else Log(L"minigame: the AI deactivation wasn't found (another game build?): the STORE still freezes the world in co-op");
    if (g_fMgRestore && HookInline(g_fMgRestore, 15, (void*)OnMgRestore, (void**)&g_nextMgRestore, L"minigame AI restore")) {}
    else Log(L"minigame: the AI restore wasn't found: not logged");
}

/* ---- a game bug guarded: a Spear rod's owner gone under it (runtime 0.32.25) ---------------------------------------
 * sigs.h kSigOwnerHostile: the game object check 0x147d0ba00 (game object, other) -> bool calls AActor::GetWorld on its
 * game object with no null check, and ALiveMeteoriteImpact::Tick (the Tonitrus Spear's rod, BP_RodsFromGod, a pooled
 * object) passes its owner (+0x368) as is. A joiner's game of 2026-11-07 (13:00:07, UECC 9139164E) crashed there reading
 * 0x8: THE DECOY's trap over, the round's clean-up took its Spear launchers off while a rod still ticked, the rod's owner
 * NULL. The guard answers "no" (0) for a NULL or freed game object (UObjAllocated: one being destroyed still goes to the
 * game), which skips the rod's damage step; every other call goes on unchanged. No VirtualQuery: a hot path. */
typedef uint8_t (*OwnerHostileFn)(uint8_t* obj, uint8_t* other);
static uint8_t*          g_fOwnerHostile;                   /* found by FindFunctions */
static OwnerHostileFn    g_nextOwnerHostile;
static volatile uint32_t g_ohCaught;

static uint8_t OnOwnerHostile(uint8_t* obj, uint8_t* other)
{
    int bad = !obj ? 1 : (UObjAllocated(obj) == 0 ? 2 : 0);
    if (bad) {
        uint32_t n = __atomic_add_fetch(&g_ohCaught, 1, __ATOMIC_RELAXED);
        if (n <= 64) Crumb(L"guard: a game object check on %s %p (with %p): answered no", bad == 1 ? L"NULL" : L"a freed object", obj, other);
        if (n <= 8)
            Log(L"guard: a game object check (a Spear rod's owner) on %s %p (with %p): answered no, not called (%u so far)",
                bad == 1 ? L"NULL" : L"a freed object", obj, other, n);
        return 0;
    }
    return g_nextOwnerHostile(obj, other);
}

static void OhInstall(void)
{
    if (!g_fOwnerHostile) { Log(L"guard: the game object check (a Spear rod's owner) wasn't found (another game build?): not guarded"); return; }
    if (!HookInline(g_fOwnerHostile, 15, (void*)OnOwnerHostile, (void**)&g_nextOwnerHostile, L"guard: game object check (a Spear rod's owner)"))
        Log(L"guard: the game object check %p couldn't be hooked: not guarded", g_fOwnerHostile);
}

/* SV_StoreKeepAI(on) -> the old value (0 / 1), SV_ERR_NO_GAME when the deactivation isn't hooked; no argument: ask */
static int L_StoreKeepAI(void* lua)
{
    double on = -1;
    ArgNumber(lua, &on);
    if (!g_nextMgDeactivate) return Ret(lua, SV_ERR_NO_GAME);
    int old = g_storeKeepAI;
    if (on >= 0 && (on != 0) != (old != 0)) {
        g_storeKeepAI = on != 0;                           /* (Lua ticks on the game thread, as the hook) */
        Log(L"minigame: the world's AI %s when a minigame (the STORE) starts", on != 0 ? L"keeps flying (co-op)" : L"stops (stock)");
    }
    return Ret(lua, old);
}

#include "laser.c"                                  /* (0.32.26) AC7's LaserInterceptor on AC8's class: its guard, SV_Laser* */
