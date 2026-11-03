/* pathguard.h : the AI path tracking guard's per-tracker part (runtime 0.32.22, plan F2; flight.c PtInstall puts it on the
 * game's thunk). The includer has uobj.h, safecall.h, and Log / Crumb (wide printf-style, %s %d %u %x %p only: hard rule
 * 43). tools/checks/pathguard_test.c runs it on made-up trackers. Every tracker of ULiveAIPathTickerSubsystem's
 * PathTrackers (+0x60, Num +0x68) comes through OnPathTrackItem(captures, &index) on the ParallelFor's worker threads: a
 * tracker that is freed, or whose objects (+0x28 OwningActor, +0x30 OwningAIGameObject, +0x38 OwningUnit, +0x40
 * TrackingTargetAIPath, +0x48 SplineComponent) are freed, is left out this frame; the rest run the game's body through
 * ScCall4, a fault there coming back as "left out" and that tracker left out for the rest of the level (PtReset). The
 * tracker's own memory is read only inside the catcher. */
#ifndef SV_PATHGUARD_H
#define SV_PATHGUARD_H

#define PT_TRACKERS 0x60                                    /* ULiveAIPathTickerSubsystem.PathTrackers: Data, Num +0x68 */
#define PT_BAD_MAX  64
#define PT_SAMPLE   64                                      /* (the call count: one call in about this many) */
typedef void (*PtBodyFn)(void* cap, intptr_t index);
typedef struct { uint8_t* tracker; int32_t idx, off; const wchar_t* why; } PtCall;
typedef struct { _Alignas(64) volatile uint32_t n; } PtCount;
static PtBodyFn          g_ptBody;                          /* the game's body 0x147dd53f0 (captures, index) */
static PtCount           g_ptCalls;                         /* (sampled: about 1 in PT_SAMPLE) */
static volatile int32_t  g_ptSkipped, g_ptFaults, g_ptBadN;
static uint8_t* volatile g_ptBad[PT_BAD_MAX];               /* trackers whose update faulted: left out this level */
static volatile int32_t  g_ptBadIdx[PT_BAD_MAX];

static void PtReset(void) { g_ptBadN = 0; }

/* (under ScCall4) the checks, then the game's body; 1 left out (o->why), 0 run */
static uint8_t PtGuarded(void* cap, void* iv, void* ov, void* unused)
{
    (void)unused;
    PtCall* o = (PtCall*)ov;
    int32_t i = (int32_t)(intptr_t)iv;
    uint8_t* sub = cap ? *(uint8_t**)cap : NULL;
    uint8_t** data = sub ? *(uint8_t***)(sub + PT_TRACKERS) : NULL;
    int32_t n = sub ? *(int32_t*)(sub + PT_TRACKERS + 8) : 0;
    uint8_t* t = (data && i >= 0 && i < n) ? data[i] : NULL;
    o->tracker = t;
    if (t) {
        if (UObjAllocated(t) == 0) { o->why = L"the tracker itself was freed"; return 1; }
        o->idx = *(const int32_t*)(t + 0xC);
        for (int32_t k = 0, nb = g_ptBadN < PT_BAD_MAX ? g_ptBadN : PT_BAD_MAX; k < nb; ++k)
            if (g_ptBad[k] == t && g_ptBadIdx[k] == o->idx) { o->why = L"its update faulted before"; return 1; }
        for (int f = 0x28; f <= 0x48; f += 8) {
            const uint8_t* x = *(const uint8_t* const*)(t + f);
            if (x && UObjAllocated(x) == 0) { o->why = L"an object it holds was freed"; o->off = f; return 1; }
        }
    }
    g_ptBody(cap, (intptr_t)i);
    return 0;
}

/* the thunk's replacement: (the ParallelFor's captures, &index) */
static void OnPathTrackItem(void* cap, const int32_t* pidx)
{
    int32_t i = pidx ? *pidx : -1;
    if (!((((uintptr_t)cap >> 4) ^ (uint32_t)i) & (PT_SAMPLE - 1))) g_ptCalls.n = g_ptCalls.n + 1;
    PtCall c = { NULL, -1, 0, NULL };
    int faulted = 0;
    void* fa = NULL;
    uint64_t at = 0;
    uint8_t left = ScCall4(PtGuarded, cap, (void*)(intptr_t)i, &c, NULL, &faulted, &fa, &at);
    if (faulted) {
        int32_t n = __atomic_add_fetch(&g_ptFaults, 1, __ATOMIC_RELAXED);
        int32_t b = c.tracker ? __atomic_fetch_add(&g_ptBadN, 1, __ATOMIC_RELAXED) : PT_BAD_MAX;
        if (b < PT_BAD_MAX) { g_ptBadIdx[b] = c.idx; g_ptBad[b] = c.tracker; }
        if (n <= 4 || (n < 100000 && (n & (n - 1)) == 0)) {
            Log(L"guard: AI path tracking caught a fault in tracker %p's update (index %d: at %p reading %p): left out for the rest "
                L"of this level (%d so far)", c.tracker, i, fa, (void*)(uintptr_t)at, n);
            Crumb(L"guard: path tracker %p update fault caught at %p reading %p (%d so far)", c.tracker, fa, (void*)(uintptr_t)at, n);
        }
    } else if (left) {
        int32_t n = __atomic_add_fetch(&g_ptSkipped, 1, __ATOMIC_RELAXED);
        if (n <= 4 || (n < 100000 && (n & (n - 1)) == 0)) {
            Log(L"guard: AI path tracking left out tracker %p this frame (%s%s; %d so far)", c.tracker, c.why ? c.why : L"?",
                c.off == 0x28 ? L": its owning actor" : c.off == 0x30 ? L": its AI object" : c.off == 0x38 ? L": its unit" :
                c.off == 0x40 ? L": its path" : c.off == 0x48 ? L": its spline" : L"", n);
            Crumb(L"guard: path tracker %p left out (%s, +0x%x; %d so far)", c.tracker, c.why ? c.why : L"?", (uint32_t)c.off, n);
        }
    }
}

#endif
