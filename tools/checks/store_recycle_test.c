/* store_recycle_test.c : the recycles' deferred unit destroys against the STORE's freeze (runtime 0.32.36), on the
 * runtime's own code (store_recycle_cut.py cuts it out of survival_rt_game.c and flight_guards.c) with the game stubbed.
 * The crash it guards: a unit actor destroyed while the STORE's freeze had its planes listed, then the game's restore
 * walked them (Shazzy 2026-11-09, Phantom 2026-11-13: 0x147dbbf5e reading 0x3d9). */
#define _CRT_SECURE_NO_WARNINGS
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <wchar.h>

/* ---- the game and the runtime, stubbed ---- */
static uint64_t g_now = 1000000;
static uint64_t GetTickCount64(void) { return g_now; }
static volatile int32_t g_teardown;
static volatile int g_mgFrozen;
static uint32_t g_unitGen __attribute__((unused));
static uint8_t* g_phase = (uint8_t*)0x1;
static struct { int uniqueId; } LY = { 0 };

static wchar_t g_last[2048];
static int g_logs __attribute__((unused));
static void Log(const wchar_t* f, ...) { va_list a; va_start(a, f); _vsnwprintf(g_last, 2047, f, a); va_end(a); ++g_logs; }
static void Crumb(const wchar_t* f, ...) { (void)f; }
static int Readable(const void* p, size_t n) { (void)n; return p != NULL; }
static const wchar_t* ObjGoneWhy(void* o) { (void)o; return NULL; }
static int UObjLive(const void* o) { (void)o; return 0; }   /* the manager not live: the hooks log nothing */

#define UNITS 8
static uint8_t g_units[UNITS][0x40];
static int g_destroyed[UNITS];
static int g_destroyedInFreeze;
static void DestroyActor(uint8_t* u, int x)
{
    (void)x;
    for (int i = 0; i < UNITS; ++i) if (u == g_units[i]) ++g_destroyed[i];
    if (g_mgFrozen) ++g_destroyedInFreeze;
}
static void (*g_destroyActor)(uint8_t*, int) = DestroyActor;
static void Unregister(uint8_t* phase, uint8_t* u) { (void)phase; (void)u; }
static void (*g_unregisterUnit)(uint8_t*, uint8_t*) = Unregister;
static int g_alive = 2;
static uint8_t* RegisteredUnit(uint32_t id) { return id < UNITS ? g_units[id] : NULL; }
static int32_t UnitArrayNum(uint8_t* u, const wchar_t* prop) { (void)u; (void)prop; return g_alive; }

/* the game's minigame calls: whether a unit actor was destroyed under the restore's walk */
static int g_restoreRan;
static void StockDeactivate(uint8_t* mgr, uint8_t* objs) { (void)mgr; (void)objs; }
static void StockRestore(uint8_t* mgr, uint8_t* objs) { (void)mgr; (void)objs; ++g_restoreRan; }

#include "../../build/checks/store_recycle_cut.c"

static int fails, passes;
static void check(int ok, const char* what)
{
    if (ok) ++passes; else ++fails;
    printf("%s  %s\n", ok ? "PASS" : "FAIL", what);
}

static uint8_t* Desc(int i) { static uint8_t d[UNITS][8]; *(uint32_t*)d[i] = (uint32_t)i; return d[i]; }

static void Reset(void)
{
    g_rcN = 0; g_mgFrozen = 0; g_teardown = 0; g_destroyedInFreeze = 0; g_restoreRan = 0;
    memset(g_destroyed, 0, sizeof g_destroyed);
    g_rcWaitMs = 30000;
    for (int i = 0; i < UNITS; ++i) *(int32_t*)(g_units[i] + 0xC) = 100 + i;
}

int main(void)
{
    g_nextMgDeactivate = StockDeactivate;
    g_nextMgRestore = StockRestore;

    /* Phantom's: a forced recycle 10 s before the STORE, due 20 s into it */
    Reset();
    check(Recycle(Desc(0), L"ERA_Unit_01_Dep_Air0", 1) == 1 && g_rcN == 1, "a forced recycle (2 alive) is deferred");
    g_now += 10000;
    OnMgDeactivate(NULL, NULL);
    check(g_mgFrozen == 1, "the STORE's deactivation sets the freeze");
    g_now += 20000; RcDrain();
    g_now += 1000; RcDrain();
    check(g_destroyed[0] == 0 && g_rcN == 1, "due inside the STORE: held, not destroyed");
    check(wcsstr(g_last, L"waits for the STORE's close") != NULL, "the hold is logged");
    OnMgRestore(NULL, NULL);
    check(g_restoreRan == 1 && g_destroyed[0] == 0, "the restore walks with the unit actor still there");
    check(g_mgFrozen == 0, "the restore clears the freeze");
    RcDrain();
    check(g_destroyed[0] == 1 && g_rcN == 0, "destroyed at the first spawner call after the restore");
    check(wcsstr(g_last, L"held for the STORE") != NULL, "its destroy line says it was held");
    check(g_destroyedInFreeze == 0, "nothing destroyed while frozen");

    /* a recycle due before the STORE: as before */
    Reset();
    Recycle(Desc(1), L"A", 1);
    g_now += 30000; RcDrain();
    check(g_destroyed[1] == 1, "due outside a STORE: destroyed on time");

    /* force 2 (at once) and a 0 s wait during the freeze: queued for after the restore */
    Reset();
    OnMgDeactivate(NULL, NULL);
    Recycle(Desc(2), L"B", 2);
    check(g_destroyed[2] == 0 && g_rcN == 1, "force 2 inside the STORE: queued, not destroyed at once");
    g_rcWaitMs = 0;
    Recycle(Desc(3), L"C", 1);
    check(g_destroyed[3] == 0 && g_rcN == 2, "no wait set, inside the STORE: queued too");
    RcDrain();
    check(g_destroyedInFreeze == 0, "neither destroyed while frozen");
    OnMgRestore(NULL, NULL);
    RcDrain();
    check(g_destroyed[2] == 1 && g_destroyed[3] == 1, "both destroyed after the restore");
    Recycle(Desc(4), L"D", 1);
    check(g_destroyed[4] == 1, "no wait set, outside a STORE: at once, as before");
    Recycle(Desc(5), L"E", 2);
    check(g_destroyed[5] == 1, "force 2 outside a STORE: at once, as before");

    /* co-op host (the deactivation skipped): no freeze, destroys on time */
    Reset();
    g_storeKeepAI = 1;
    OnMgDeactivate(NULL, NULL);
    check(g_mgFrozen == 0, "co-op's kept AI: no freeze");
    Recycle(Desc(6), L"F", 1);
    g_now += 30000; RcDrain();
    check(g_destroyed[6] == 1, "co-op: destroyed on time in the STORE");
    g_storeKeepAI = 0;

    /* no restore hooked: never frozen (the queue would wait for ever) */
    Reset();
    g_nextMgRestore = NULL;
    OnMgDeactivate(NULL, NULL);
    check(g_mgFrozen == 0, "the restore not hooked: no freeze");
    g_nextMgRestore = StockRestore;

    /* the level torn down mid-STORE: the gate drops the queue (RcDrain does nothing), the freeze can't outlive it */
    Reset();
    OnMgDeactivate(NULL, NULL);
    Recycle(Desc(7), L"G", 1);
    g_teardown = 1;
    g_now += 40000; RcDrain();
    check(g_destroyed[7] == 0, "torn down: nothing destroyed");

    printf("\nstore_recycle_test: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
