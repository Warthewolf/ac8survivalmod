/* logbundle_test.c : runtime/logzip.h outside the game (tools/checks/logbundle_test.sh builds and runs it, windowless, and
 * logbundle_test.py checks what it wrote). Run in build/checks/logbundle:
 *   logbundle_test.exe zip <out.zip> <entry>=<path> ... @<entry>=<text> ...
 *        -> one line per argument: "added <entry> <bytes>" or "skip <entry> <code>" (LZ_*), then "end 1"
 *           (@name=text adds an in-memory entry, like the bundle.txt the runtime makes)
 *   logbundle_test.exe prune <dir> <keep>   -> "pruned <n>" (keeps the newest <keep> of <dir>\AC8Survival_*.zip)  */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "../../runtime/logzip.h"

int wmain(int argc, wchar_t** argv)
{
    if (argc >= 3 && !wcscmp(argv[1], L"zip")) {
        LzZip z;
        if (!LzBegin(&z, argv[2])) { printf("end 0\n"); return 1; }
        for (int i = 3; i < argc; ++i) {
            wchar_t* a = argv[i];
            int mem = (a[0] == L'@');
            if (mem) ++a;
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
    printf("usage: logbundle_test zip <out> <entry>=<path>... | prune <dir> <keep>\n");
    return 2;
}
