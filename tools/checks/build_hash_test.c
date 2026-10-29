/* build_hash_test.c : runtime/build_hash.c outside the game (tools/checks/build_hash_test.sh builds and runs it, windowless,
 * and checks its answers against tools/build_hash.py's and Python's hmac). Run in build/checks/build_hash:
 *   build_hash_test.exe hash <Mods folder>          -> "hash <64 hex>" (or "hash FAILED <why> <file>")
 *   build_hash_test.exe hmac <key> <build> <body>   -> "hmac <64 hex>"  (HMAC-SHA256(key, build + "\n" + body);
 *                                                      build "-": the body alone, as before runtime 0.28.6)
 * Made-up keys only: never the leaderboard's. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "../../runtime/build_hash.c"

int main(int argc, char** argv)
{
    if (argc >= 3 && !strcmp(argv[1], "hash")) {
        wchar_t mods[BH_PATH], root[BH_PATH], io[BH_PATH];
        if (!MultiByteToWideChar(CP_UTF8, 0, argv[2], -1, mods, BH_PATH)) { printf("hash FAILED bad path\n"); return 1; }
        _snwprintf(root, BH_PATH, L"%ls\\AC8SurvivalMode", mods);
        _snwprintf(io, BH_PATH, L"%ls\\IoStoreLoaderMod\\SurvivalMode", mods);
        char hex[65];
        BhRun r;
        if (!BuildHash(root, io, hex, &r)) { printf("hash FAILED %ls %ls\n", r.why ? r.why : L"?", r.whyFile); return 0; }
        printf("hash %s\nfiles %d scripts %d ai %d bytes %llu\n", hex, r.files, r.scripts, r.ai, (unsigned long long)r.bytes);
        return 0;
    }
    if (argc >= 5 && !strcmp(argv[1], "hmac")) {
        char hex[65], pre[80];
        size_t preLen = 0;
        if (strcmp(argv[3], "-")) preLen = (size_t)snprintf(pre, sizeof(pre), "%s\n", argv[3]);
        if (!BhHmac(argv[2], strlen(argv[2]), pre, preLen, argv[4], strlen(argv[4]), hex)) { printf("hmac FAILED\n"); return 1; }
        printf("hmac %s\n", hex);
        return 0;
    }
    printf("usage: build_hash_test hash <Mods> | hmac <key> <build|-> <body>\n");
    return 2;
}
