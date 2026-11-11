/* logbundle_test.c : runtime/logzip.h outside the game (tools/checks/logbundle_test.sh builds and runs it, windowless, and
 * logbundle_test.py checks what it wrote). Run in build/checks/logbundle:
 *   logbundle_test.exe zip <out.zip> <entry>=<path> ... @<entry>=<text> ...
 *        -> one line per argument: "added <entry> <bytes>" or "skip <entry> <code>" (LZ_*), then "end 1"
 *           (@name=text adds an in-memory entry, like the bundle.txt the runtime makes; <name=path cuts the file to half
 *           its size between logzip.h's two passes, ~name=path rewrites it with 'X's at the same size there)
 *   logbundle_test.exe prune <dir> <keep>   -> "pruned <n>" (keeps the newest <keep> of <dir>\AC8Survival_*.zip)
 *   logbundle_test.exe stamp <name>...      -> "<name> file <stamp|-> zip <stamp|->" (LzFileStamp, LzZipStamp)
 *   logbundle_test.exe pick <dir> <cur> <keep> -> "pick <stamp>" for each session to zip, then "picked <n>" (LzPick) */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static int g_change;                     /* the file being added: 0 left alone, 1 cut to half, 2 rewritten */

static void TestBetween(const wchar_t* path)
{
    if (!g_change) return;
    HANDLE h = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) { printf("between: could not open %ls\n", path); return; }
    LARGE_INTEGER size;
    GetFileSizeEx(h, &size);
    if (g_change == 1) {
        LARGE_INTEGER half;
        half.QuadPart = size.QuadPart / 2;
        SetFilePointerEx(h, half, NULL, FILE_BEGIN);
        SetEndOfFile(h);
    } else {
        static char x[4096];
        memset(x, 'X', sizeof(x));
        for (LONGLONG left = size.QuadPart; left > 0;) {
            DWORD n = left > (LONGLONG)sizeof(x) ? (DWORD)sizeof(x) : (DWORD)left, put = 0;
            if (!WriteFile(h, x, n, &put, NULL) || !put) break;
            left -= put;
        }
    }
    CloseHandle(h);
}
#define LZ_BETWEEN_PASSES(path) TestBetween(path)

#include "../../runtime/logzip.h"

int wmain(int argc, wchar_t** argv)
{
    if (argc >= 3 && !wcscmp(argv[1], L"zip")) {
        LzZip z;
        if (!LzBegin(&z, argv[2])) { printf("end 0\n"); return 1; }
        for (int i = 3; i < argc; ++i) {
            wchar_t* a = argv[i];
            int mem = (a[0] == L'@');
            g_change = a[0] == L'<' ? 1 : a[0] == L'~' ? 2 : 0;
            if (mem || g_change) ++a;
            wchar_t* eq = wcschr(a, L'=');
            if (!eq) continue;
            *eq = 0;
            int rc;
            if (mem) {
                char u[1024];
                int n = WideCharToMultiByte(CP_UTF8, 0, eq + 1, -1, u, (int)sizeof(u), NULL, NULL);
                rc = LzAddMem(&z, a, u, (uint32_t)(n > 0 ? n - 1 : 0), 132000000000000000ull);
            } else {
                rc = LzAddFile(&z, a, eq + 1, 132000000000000000ull);
            }
            if (rc == LZ_OK) printf("added %ls %llu\n", a, (unsigned long long)z.lastSize);
            else printf("skip %ls %d\n", a, rc);
        }
        int ok = LzEnd(&z);
        printf("end %d\n", ok);
        return ok ? 0 : 1;
    }
    if (argc >= 4 && !wcscmp(argv[1], L"prune")) {
        printf("pruned %d\n", LzPrune(argv[2], L"AC8Survival_", _wtoi(argv[3])));
        return 0;
    }
    if (argc >= 3 && !wcscmp(argv[1], L"stamp")) {          /* stamp <name>... -> "<name> file <stamp|-> zip <stamp|->" */
        for (int i = 2; i < argc; ++i) {
            wchar_t f[LZ_STAMP], z[LZ_STAMP];
            int hf = LzFileStamp(argv[i], f), hz = LzZipStamp(argv[i], z);
            printf("%ls file %ls zip %ls\n", argv[i], hf ? f : L"-", hz ? z : L"-");
        }
        return 0;
    }
    if (argc >= 5 && !wcscmp(argv[1], L"pick")) {           /* pick <dir> <current stamp> <keep> -> "pick <stamp>"..., "picked <n>" */
        static wchar_t out[32][LZ_STAMP];
        int n = LzPick(argv[2], argv[3], _wtoi(argv[4]), out, 32);
        for (int i = 0; i < n; ++i) printf("pick %ls\n", out[i]);
        printf("picked %d\n", n);
        return 0;
    }
    printf("usage: logbundle_test zip <out> <entry>=<path>... | prune <dir> <keep> | stamp <name>... | pick <dir> <cur> <keep>\n");
    return 2;
}
