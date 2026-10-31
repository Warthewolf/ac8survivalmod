/* safecall_test.c (tools/checks/safecall_test.sh): runtime/safecall.h's ScCall4 outside the game. A call that returns
 * normally gives its answer; one that reads NULL + 0x898 deep in its callees (as Alyssa's crash of 2026-10-31 did, in
 * a target entry check) comes back as 0 with the fault and its address told; calls go on working after one (the
 * handler leaves nothing armed), nested ones too, on another thread too (each thread its own frame). */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include "../../runtime/safecall.h"

static int fails;
static void check(int ok, const char* what) { printf("  %s %s\n", ok ? "ok  " : "FAIL", what); if (!ok) ++fails; }

static uint8_t ok4(void* a, void* b, void* c, void* d) { (void)b; (void)c; (void)d; return (uint8_t)((uintptr_t)a + 1); }
static __attribute__((noinline)) uint8_t deep(volatile uint64_t* p, int n)
{
    if (n > 0) return (uint8_t)(deep(p, n - 1) + 1);
    return (uint8_t)*p;
}
static uint8_t bad4(void* a, void* b, void* c, void* d)
{
    (void)b; (void)c; (void)d;
    return deep((volatile uint64_t*)((uintptr_t)a + 0x898), 5);
}
static uint8_t nested4(void* a, void* b, void* c, void* d)
{
    int f = 0; void* ad = NULL; uint64_t at = 0;
    uint8_t r = ScCall4(bad4, a, b, c, d, &f, &ad, &at);            /* (an inner fault: the inner call's) */
    return (uint8_t)(f ? 7 : r + 100);
}

static DWORD WINAPI worker(void* p)
{
    int* out = (int*)p;
    int f = 0; void* ad = NULL; uint64_t at = 0;
    uint8_t r = ScCall4(bad4, NULL, NULL, NULL, NULL, &f, &ad, &at);
    int f2 = 0;
    uint8_t r2 = ScCall4(ok4, (void*)(uintptr_t)9, NULL, NULL, NULL, &f2, NULL, NULL);
    out[0] = r == 0 && f == 1 && at == 0x898 && r2 == 10 && f2 == 0;
    return 0;
}

int main(void)
{
    check(ScInit(GetModuleHandleW(L"kernel32.dll")) == 1, "ScInit: kernel32's calls and the handler in");
    int f = 0; void* ad = NULL; uint64_t at = 0;
    check(ScCall4(ok4, (void*)(uintptr_t)41, NULL, NULL, NULL, &f, &ad, &at) == 42 && f == 0, "a normal call: its answer");
    volatile int keep = 1234;                              /* (a local of ours across the fault) */
    uint8_t r = ScCall4(bad4, NULL, NULL, NULL, NULL, &f, &ad, &at);
    check(r == 0 && f == 1, "NULL + 0x898 read 6 calls down: 0, faulted");
    check(at == 0x898, "the address it read told (0x898)");
    check(keep == 1234, "the caller's locals as they were");
    f = 1;
    check(ScCall4(ok4, (void*)(uintptr_t)1, NULL, NULL, NULL, &f, NULL, NULL) == 2 && f == 0, "after a fault: calls work");
    int bad = 0;
    for (int i = 0; i < 2000; ++i) {
        int fi = 0;
        if (ScCall4(bad4, NULL, NULL, NULL, NULL, &fi, NULL, NULL) != 0 || !fi) ++bad;
        if (ScCall4(ok4, (void*)(uintptr_t)(i & 0x7f), NULL, NULL, NULL, &fi, NULL, NULL) != (uint8_t)((i & 0x7f) + 1) || fi) ++bad;
    }
    check(bad == 0, "2000 faults and 2000 normal calls, one after another");
    f = 0;
    check(ScCall4(nested4, NULL, NULL, NULL, NULL, &f, NULL, NULL) == 7 && f == 0, "nested: the inner call's fault is the inner's");
    int out[1] = { 0 };
    HANDLE t = CreateThread(NULL, 0, worker, out, 0, NULL);
    WaitForSingleObject(t, 10000);
    CloseHandle(t);
    check(out[0] == 1, "on another thread: its own frame");
    printf(fails ? "safecall test: %d FAILED\n" : "safecall test: all passed\n", fails);
    return fails ? 1 : 0;
}
