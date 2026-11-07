/* runtime/vfmt.h, the runtime's Log / Crumb formatter: lines past the buffer are cut and the call returns. Until runtime
 * 0.32.23 its PUT skipped reading the character once the buffer was full, so `while (*s) PUT(*s++)` (a %s) and
 * `while (n) PUT(t[--n])` (a number) never moved on: 0.32.22's 1,031-character "Lua bridge: ... registered" line hung
 * UE4SS's Lua start for good (the user's launches of 2026-11-03). Each case runs on its own thread with a time limit.
 * Build and run: tools/checks/vfmt_test.sh */
#include <windows.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <wchar.h>

#include "../../runtime/vfmt.h"

static int g_fail;
static void check(int ok, const char* what) { printf("  %s %s\n", ok ? "ok  " : "FAIL", what); if (!ok) ++g_fail; }

static wchar_t        g_out[64];
static size_t         g_cap;
static const wchar_t* g_fmt;
static const wchar_t* g_s;
static int32_t        g_d;

static void Fmt(wchar_t* out, size_t cap, const wchar_t* fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    VFmt(out, cap, fmt, ap);
    va_end(ap);
}
static DWORD WINAPI RunS(void* a) { (void)a; Fmt(g_out, g_cap, g_fmt, g_s); return 0; }
static DWORD WINAPI RunSD(void* a) { (void)a; Fmt(g_out, g_cap, g_fmt, g_s, g_d); return 0; }

/* runs fn on a thread; 1 when it returned within 2 s */
static int Returns(LPTHREAD_START_ROUTINE fn)
{
    HANDLE th = CreateThread(NULL, 0, fn, NULL, 0, NULL);
    if (!th) return 0;
    DWORD r = WaitForSingleObject(th, 2000);
    if (r != WAIT_OBJECT_0) { TerminateThread(th, 1); CloseHandle(th); return 0; }
    CloseHandle(th);
    return 1;
}

int main(void)
{
    static wchar_t longs[200];
    for (int i = 0; i < 199; ++i) longs[i] = (wchar_t)(L'a' + i % 26);
    longs[199] = 0;

    printf("vfmt: lines past the buffer are cut and the call returns\n");
    g_cap = 16; g_fmt = L"bridge: %s registered"; g_s = longs;
    check(Returns(RunS) && wcslen(g_out) == 15 && wcsncmp(g_out, L"bridge: abcdefg", 15) == 0,
          "a %s longer than the buffer: cut at cap - 1, returns (0.32.22 hung here)");
    g_cap = 16; g_fmt = L"0123456789%s%d"; g_s = L"ab"; g_d = 123456789;
    check(Returns(RunSD) && wcscmp(g_out, L"0123456789ab123") == 0,
          "a number past the buffer: cut, returns (its digit loop used to stop moving)");

    printf("vfmt: the ordinary cases\n");
    g_cap = 64; g_fmt = L"runtime %s, %d planes"; g_s = L"0.32.23"; g_d = -12;
    check(Returns(RunSD) && wcscmp(g_out, L"runtime 0.32.23, -12 planes") == 0, "%s and a negative %d");
    g_cap = 64; g_fmt = L"%s"; g_s = NULL;
    check(Returns(RunS) && wcscmp(g_out, L"<null>") == 0, "a NULL %s");
    g_cap = 8; g_fmt = L"%s"; g_s = L"1234567";
    check(Returns(RunS) && wcscmp(g_out, L"1234567") == 0, "exactly cap - 1 characters: all of them");

    if (g_fail) { printf("vfmt test: %d FAILED\n", g_fail); return 1; }
    printf("vfmt test: all passed\n");
    return 0;
}
