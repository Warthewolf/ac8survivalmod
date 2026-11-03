/* pathguard_test.c (tools/checks/pathguard_test.sh): runtime/pathguard.h, the AI path tracking guard of runtime 0.32.22
 * (plan F2), outside the game, on a made-up GUObjectArray and a made-up ULiveAIPathTickerSubsystem (PathTrackers at
 * +0x60, Num +0x68) whose trackers the guard is called on as the game's ParallelFor calls its thunk: (captures, &index),
 * the captures' first pointer the subsystem. A live tracker runs the body (with the same captures and index); a freed
 * tracker, or one holding a freed object at +0x28..+0x48, is left out and the body never runs; a body that faults
 * (reads NULL + 0x48, as the first crash's call through a freed vtable) comes back, is counted, and that tracker is left
 * out from then on (also on another thread); one that took its slot over (another InternalIndex) runs again; PtReset
 * forgets the list. Log / Crumb are counted, not written. */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#pragma clang diagnostic ignored "-Wunused-function"      /* (uobj.h's other checks) */
#include "../../runtime/uobj.h"
#include "../../runtime/safecall.h"

static int logs, crumbs;
static void Log(const wchar_t* fmt, ...) { (void)fmt; ++logs; }
static void Crumb(const wchar_t* fmt, ...) { (void)fmt; ++crumbs; }
#include "../../runtime/pathguard.h"

static int fails;
static void check(int ok, const char* what) { printf("  %s %s\n", ok ? "ok  " : "FAIL", what); if (!ok) ++fails; }

/* the game's body, made up: counts its calls per index; index 3 faults (its tracker's movement freed) while armed */
static volatile int ran[8], lastIndex = -1, faultOn = 1;
static void* lastCap;
static __attribute__((noinline)) uint8_t deep(volatile uint64_t* p, int n) { return n > 0 ? (uint8_t)(deep(p, n - 1) + 1) : (uint8_t)*p; }
static void Body(void* cap, intptr_t index)
{
    int32_t i = (int32_t)index;                            /* (the game's body reads edx: the low 32 bits) */
    lastCap = cap; lastIndex = i;
    if (i == 3 && faultOn) deep((volatile uint64_t*)(uintptr_t)0x48, 4);
    if (i >= 0 && i < 8) ++ran[i];
}

static uint8_t* table[4];
static uint8_t* MakeObj(int32_t idx)                       /* a live object at that GUObjectArray index */
{
    uint8_t* o = _aligned_malloc(0x200, 16);
    memset(o, 0, 0x200);
    *(int32_t*)(o + 0xC) = idx;
    uint8_t* item = table[idx >> 16] + (size_t)(idx & 0xFFFF) * 0x18;
    *(uint8_t**)item = o;
    *(uint32_t*)(item + 8) = 1u;
    return o;
}
static void FreeSlot(int32_t idx) { *(uint8_t**)(table[idx >> 16] + (size_t)(idx & 0xFFFF) * 0x18) = NULL; }

static uint8_t* g_sub;
static void* g_caps[2];
static void Call(int32_t i) { OnPathTrackItem(g_caps, &i); }

static DWORD WINAPI Worker(void* p)
{
    (void)p;
    for (int k = 0; k < 4; ++k) Call(3);                   /* (the faulted tracker, from another thread: left out) */
    Call(0);
    return 0;
}

int main(void)
{
    if (!ScInit(GetModuleHandleW(L"kernel32.dll"))) { printf("  FAIL the fault catcher couldn't be set up\n"); return 1; }
    static int32_t num = 65536 * 2;
    static uint32_t gcFlag = 2;
    table[0] = calloc(65536, 0x18); table[1] = calloc(65536, 0x18);
    uint8_t* const* tableP = table;
    g_uoNum = &num; g_uoGcFlag = &gcFlag; g_uoChunks = (uint8_t* const* volatile*)&tableP;
    g_ptBody = Body;

    /* the subsystem and 6 trackers: 0 plain live, 1 whose unit (+0x38) is freed, 2 itself freed, 3 whose body faults,
     * 4 live with every field set to live objects, 5 a null slot in the array */
    g_sub = MakeObj(100);
    uint8_t* tr[6] = { NULL };
    for (int i = 0; i < 5; ++i) tr[i] = MakeObj(200 + i);
    uint8_t* unit = MakeObj(300);
    *(uint8_t**)(tr[1] + 0x38) = unit;
    for (int f = 0x28; f <= 0x48; f += 8) *(uint8_t**)(tr[4] + f) = MakeObj(400 + f);
    uint8_t** arr = calloc(8, sizeof(uint8_t*));
    for (int i = 0; i < 5; ++i) arr[i] = tr[i];
    *(uint8_t***)(g_sub + PT_TRACKERS) = arr;
    *(int32_t*)(g_sub + PT_TRACKERS + 8) = 6;
    g_caps[0] = g_sub; g_caps[1] = NULL;

    Call(0);
    check(ran[0] == 1 && lastCap == g_caps && lastIndex == 0, "a live tracker: the body runs with the same captures and index");
    Call(4);
    check(ran[4] == 1, "a tracker whose objects are all live: runs");
    Call(5);
    check(lastIndex == 5, "a null slot in the array: the body runs (the game's own null test)");
    FreeSlot(300);
    Call(1);
    check(ran[1] == 0 && g_ptSkipped == 1, "its unit freed (+0x38): left out, counted");
    FreeSlot(202);
    Call(2);
    check(ran[2] == 0 && g_ptSkipped == 2, "the tracker itself freed: left out");
    Call(3);
    check(ran[3] == 0 && g_ptFaults == 1 && g_ptBadN == 1, "its body faults (NULL + 0x48): caught, counted, listed");
    Call(0);
    check(ran[0] == 2, "calls go on after a fault");
    Call(3);
    check(g_ptFaults == 1 && g_ptSkipped == 3, "the faulted tracker: left out from then on (no second fault)");
    HANDLE th = CreateThread(NULL, 0, Worker, NULL, 0, NULL);
    WaitForSingleObject(th, 5000);
    check(g_ptFaults == 1 && g_ptSkipped == 7 && ran[0] == 3, "the same on another thread (the ParallelFor's workers)");
    *(int32_t*)(tr[3] + 0xC) = 203 + 1000;                 /* (its memory now another object's, at another index) */
    *(uint8_t**)(table[0] + (size_t)1203 * 0x18) = tr[3];
    faultOn = 0;
    Call(3);
    check(ran[3] == 1, "another object at the faulted tracker's address (another index): runs");
    *(int32_t*)(tr[3] + 0xC) = 203;
    faultOn = 1;
    PtReset();
    Call(3);
    check(g_ptFaults == 2 && g_ptBadN == 1, "PtReset (a new level): the list forgotten, the fault caught again");
    *(int32_t*)(g_sub + PT_TRACKERS + 8) = 2;
    Call(4);
    check(lastIndex == 4 && ran[4] == 2, "an index past Num: the body runs as the game's would (no tracker read)");
    check(logs > 0 && crumbs > 0, "logged and crumbed");
    printf("pathguard test: %s (%d left out, %d faults caught)\n", fails ? "FAILED" : "passed", g_ptSkipped, g_ptFaults);
    return fails ? 1 : 0;
}
