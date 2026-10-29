/* build_hash.c : the build hash and the run's HMAC (Online edition only; survival_rt.c includes it inside its
 * leaderboard part, tools/checks/build_hash_test.c compiles it against <windows.h>). Plain C, nothing from a C runtime.
 *
 * The build hash (user, 2026-10-30: "we need a way that the Leaderboards can detect if a run has been edited from the
 * stock run"): SHA-256 (bcrypt) over the mod's files, so the leaderboard Worker can tell a release's files from edited
 * ones. tools/build_hash.py works out the same hash over a staged release; tools/package_release.sh prints it and writes
 * it next to the zip (<zip>.buildhash.txt), which the user registers on the Worker's /admin page.
 *
 * The stream hashed is, for each file in this order:   <name> \0 <its size in decimal> \0 <its bytes>
 * where <name> is the file's canonical name below (ASCII letters lowercased, forward slashes, UTF-8), not the folder's
 * real name on disk:
 *   ac8survivalmode/scripts/<file>       every *.lua in the mod's Scripts folder (the Lua runtime, and a
 *                                        survival_config.lua when there is one), by name: lowercased, in byte order
 *   ac8survivalmode/scripts/ai/<file>    every *.lua in Scripts\ai (Survival's behaviour scripts), the same way
 *   ac8survivalmode/config/survival.default.ini
 *   ac8survivalmode/dlls/main.dll        (this runtime)
 *   iostoreloadermod/survivalmode/survivalmode_p.utoc, then survivalmode_p.ucas  (Survival's container)
 * A required file missing or unreadable, a file shorter than its size while read, or more than BH_MAX_FILES scripts in a
 * folder: no hash. Not hashed: the player's own files (config/survival.ini, the run queue, the learnt profile), the
 * sounds, and VALKA's container (parked; a NoValka zip installed over a full one would leave it behind). */

#define BH_MAX_FILES 256
#define BH_CHUNK     65536
#define BH_PATH      1024
#define BH_NAME      (260 * 3 + 1)                 /* a file name in UTF-8 */
#ifndef FILE_SHARE_DELETE
#define FILE_SHARE_DELETE 4u
#endif
#ifndef FILE_ATTRIBUTE_DIRECTORY
#define FILE_ATTRIBUTE_DIRECTORY 0x10u
#endif

typedef int32_t (*BhOpenFn)(HANDLE*, const wchar_t*, const wchar_t*, DWORD);
typedef int32_t (*BhCreateFn)(HANDLE, HANDLE*, uint8_t*, DWORD, uint8_t*, DWORD, DWORD);
typedef int32_t (*BhDataFn)(HANDLE, uint8_t*, DWORD, DWORD);
typedef int32_t (*BhFinishFn)(HANDLE, uint8_t*, DWORD, DWORD);
typedef int32_t (*BhDestroyFn)(HANDLE);
typedef int32_t (*BhCloseFn)(HANDLE, DWORD);

typedef struct {
    BhOpenFn open; BhCreateFn create; BhDataFn data; BhFinishFn finish; BhDestroyFn destroy; BhCloseFn close;
    HANDLE alg, h;
    int ok;
} BhSha;

static size_t BhLen(const char* s) { size_t n = 0; while (s[n]) ++n; return n; }
static size_t BhWLen(const wchar_t* s) { size_t n = 0; while (s[n]) ++n; return n; }

/* A SHA-256 (hmacKey NULL) or HMAC-SHA256 (under hmacKey) begun; 0 when bcrypt isn't there */
static int BhBegin(BhSha* s, const uint8_t* hmacKey, DWORD keyLen)
{
    memset(s, 0, sizeof(*s));
    HANDLE bc = (HANDLE)LoadLibraryW(L"bcrypt.dll");
    if (!bc) return 0;
    s->open = (BhOpenFn)GetProcAddress(bc, "BCryptOpenAlgorithmProvider");
    s->create = (BhCreateFn)GetProcAddress(bc, "BCryptCreateHash");
    s->data = (BhDataFn)GetProcAddress(bc, "BCryptHashData");
    s->finish = (BhFinishFn)GetProcAddress(bc, "BCryptFinishHash");
    s->destroy = (BhDestroyFn)GetProcAddress(bc, "BCryptDestroyHash");
    s->close = (BhCloseFn)GetProcAddress(bc, "BCryptCloseAlgorithmProvider");
    if (!s->open || !s->create || !s->data || !s->finish || !s->destroy || !s->close) return 0;
    s->ok = s->open(&s->alg, L"SHA256", NULL, hmacKey ? 0x8 /* BCRYPT_ALG_HANDLE_HMAC_FLAG */ : 0) == 0
         && s->create(s->alg, &s->h, NULL, 0, (uint8_t*)hmacKey, hmacKey ? keyLen : 0, 0) == 0;
    return s->ok;
}

static void BhFeed(BhSha* s, const void* p, size_t n)
{
    const uint8_t* b = (const uint8_t*)p;
    while (s->ok && n) {
        DWORD k = n > 0x40000000u ? 0x40000000u : (DWORD)n;
        if (s->data(s->h, (uint8_t*)b, k, 0) != 0) s->ok = 0;
        b += k; n -= k;
    }
}

/* Ends it: the 32-byte digest as 64 lowercase hex characters + NUL; 0 if anything failed */
static int BhEnd(BhSha* s, char* hex)
{
    uint8_t d[32];
    int ok = s->ok && s->finish(s->h, d, 32, 0) == 0;
    if (s->h) s->destroy(s->h);
    if (s->alg) s->close(s->alg, 0);
    s->h = s->alg = NULL;
    if (!ok) { hex[0] = 0; return 0; }
    static const char digits[] = "0123456789abcdef";
    for (int i = 0; i < 32; ++i) { hex[2 * i] = digits[d[i] >> 4]; hex[2 * i + 1] = digits[d[i] & 15]; }
    hex[64] = 0;
    return 1;
}

/* HMAC-SHA256(key, pre + body) as 64 hex characters: the run's signature (pre: "<build hash>\n", or nothing) */
static int BhHmac(const char* key, size_t keyLen, const char* pre, size_t preLen, const char* body, size_t len, char* hex)
{
    BhSha s;
    if (!BhBegin(&s, (const uint8_t*)key, (DWORD)keyLen)) { BhEnd(&s, hex); return 0; }
    BhFeed(&s, pre, preLen);
    BhFeed(&s, body, len);
    return BhEnd(&s, hex);
}

typedef struct { char u8[BH_NAME]; wchar_t w[261]; } BhName;

/* The big buffers, on the heap: the runtime is built without a C runtime, so no stack frame may pass 4 KB (__chkstk) */
typedef struct {
    uint8_t buf[BH_CHUNK];
    wchar_t dir[BH_PATH], ai[BH_PATH], pat[BH_PATH], path[BH_PATH];
    char    name[BH_NAME + 64];
    BhName  tmp;
} BhScratch;

typedef struct {
    BhSha      sha;
    BhScratch* s;
    int        files, scripts, ai;
    uint64_t   bytes;
    const wchar_t* why;             /* what failed */
    wchar_t    whyFile[96];         /* (the file it was about) */
} BhRun;

static void BhFail(BhRun* r, const wchar_t* why, const wchar_t* file)
{
    if (r->why) return;
    r->why = why;
    size_t n = 0;
    if (file) {
        const wchar_t* base = file + BhWLen(file);
        while (base > file && base[-1] != L'\\' && base[-1] != L'/') --base;
        while (base[n] && n < 95) { r->whyFile[n] = base[n]; ++n; }
    }
    r->whyFile[n] = 0;
    r->sha.ok = 0;
}

static int BhJoin(wchar_t* out, const wchar_t* dir, const wchar_t* name)
{
    size_t a = BhWLen(dir), b = BhWLen(name);
    if (a + b + 2 > BH_PATH) return 0;
    memcpy(out, dir, a * 2);
    out[a] = L'\\';
    memcpy(out + a + 1, name, (b + 1) * 2);
    return 1;
}

/* One file into the stream as  name \0 size \0 bytes  (name: its canonical name, UTF-8) */
static void BhFile(BhRun* r, const char* name, const wchar_t* path)
{
    if (r->why) return;
    WIN32_FIND_DATAW fd;
    HANDLE f = FindFirstFileW(path, &fd);
    if (f == INVALID_HANDLE_VALUE) { BhFail(r, L"missing", path); return; }
    FindClose(f);
    if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) { BhFail(r, L"a folder", path); return; }
    uint64_t size = ((uint64_t)fd.nFileSizeHigh << 32) | fd.nFileSizeLow;
    HANDLE h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
                           FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) { BhFail(r, L"can't be read", path); return; }
    char num[24];
    int n = 0;
    {
        char t[24];
        uint64_t v = size;
        int k = 0;
        do { t[k++] = (char)('0' + v % 10); v /= 10; } while (v);
        while (k) num[n++] = t[--k];
        num[n] = 0;
    }
    BhFeed(&r->sha, name, BhLen(name) + 1);      /* (its NUL too) */
    BhFeed(&r->sha, num, (size_t)n + 1);
    uint64_t left = size;
    while (left && r->sha.ok) {
        DWORD want = left > BH_CHUNK ? BH_CHUNK : (DWORD)left, got = 0;
        if (!ReadFile(h, r->s->buf, want, &got, NULL) || !got) break;
        BhFeed(&r->sha, r->s->buf, got);
        left -= got;
    }
    CloseHandle(h);
    if (left) { BhFail(r, L"changed while it was read", path); return; }
    r->files++;
    r->bytes += size;
}

/* Lowercase ASCII only (the same in tools/build_hash.py: other letters stay as they are) */
static void BhLowerA(char* s) { for (; *s; ++s) if (*s >= 'A' && *s <= 'Z') *s = (char)(*s + 32); }
static int BhCmp(const char* a, const char* b)
{
    while (*a && *a == *b) { ++a; ++b; }
    return (int)(uint8_t)*a - (int)(uint8_t)*b;
}

/* Every *.lua in dir (not folders), by lowercased UTF-8 name, as prefix + name; how many, or -1 */
static int BhScripts(BhRun* r, const wchar_t* dir, const char* prefix)
{
    if (r->why) return -1;
    wchar_t* pat = r->s->pat;
    if (!BhJoin(pat, dir, L"*")) { BhFail(r, L"path too long", dir); return -1; }
    WIN32_FIND_DATAW fd;
    HANDLE f = FindFirstFileW(pat, &fd);
    if (f == INVALID_HANDLE_VALUE) return 0;                   /* (no such folder: no scripts there) */
    BhName* list = (BhName*)malloc(sizeof(BhName) * BH_MAX_FILES);
    if (!list) { FindClose(f); BhFail(r, L"out of memory", NULL); return -1; }
    int n = 0;
    do {
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        size_t len = BhWLen(fd.cFileName);
        /* ".lua" in any case: the long name's own end (a "*.lua" pattern would match 8.3 short names too) */
        if (len < 5 || len > 260) continue;
        const wchar_t* e = fd.cFileName + len - 4;
        if (!(e[0] == L'.' && (e[1] | 32) == L'l' && (e[2] | 32) == L'u' && (e[3] | 32) == L'a')) continue;
        if (n >= BH_MAX_FILES) { BhFail(r, L"too many scripts", dir); break; }
        int m = WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, (int)len, list[n].u8, BH_NAME - 1, NULL, NULL);
        if (m <= 0) { BhFail(r, L"a file name that isn't text", fd.cFileName); break; }
        list[n].u8[m] = 0;
        BhLowerA(list[n].u8);
        memcpy(list[n].w, fd.cFileName, (len + 1) * 2);
        ++n;
    } while (FindNextFileW(f, &fd));
    FindClose(f);
    BhName* t = &r->s->tmp;
    for (int i = 1; i < n; ++i) {                               /* (a few dozen: insertion sort) */
        memcpy(t, &list[i], sizeof(*t));
        int j = i - 1;
        while (j >= 0 && BhCmp(list[j].u8, t->u8) > 0) { memcpy(&list[j + 1], &list[j], sizeof(*t)); --j; }
        memcpy(&list[j + 1], t, sizeof(*t));
    }
    char* name = r->s->name;
    wchar_t* path = r->s->path;
    size_t pl = BhLen(prefix);
    for (int i = 0; i < n && !r->why; ++i) {
        size_t nl = BhLen(list[i].u8);
        if (pl + nl + 1 > sizeof(r->s->name)) { BhFail(r, L"name too long", list[i].w); break; }
        memcpy(name, prefix, pl);
        memcpy(name + pl, list[i].u8, nl + 1);
        if (!BhJoin(path, dir, list[i].w)) { BhFail(r, L"path too long", list[i].w); break; }
        BhFile(r, name, path);
    }
    free(list);
    return r->why ? -1 : n;
}

/* The build hash of the mod in modRoot (...\Mods\AC8SurvivalMode) with its container in ioDir
 * (...\Mods\IoStoreLoaderMod\SurvivalMode): 64 hex characters + NUL into hex, 1; or 0 with r->why (and r->whyFile) */
static int BuildHash(const wchar_t* modRoot, const wchar_t* ioDir, char* hex, BhRun* r)
{
    memset(r, 0, sizeof(*r));
    hex[0] = 0;
    if (!BhBegin(&r->sha, NULL, 0)) { BhEnd(&r->sha, hex); r->why = L"bcrypt isn't there"; return 0; }
    r->s = (BhScratch*)malloc(sizeof(BhScratch));
    if (!r->s) { BhEnd(&r->sha, hex); r->why = L"out of memory"; return 0; }
    wchar_t* dir = r->s->dir;
    wchar_t* path = r->s->path;
    if (BhJoin(dir, modRoot, L"Scripts")) {
        r->scripts = BhScripts(r, dir, "ac8survivalmode/scripts/");
        if (BhJoin(r->s->ai, dir, L"ai")) r->ai = BhScripts(r, r->s->ai, "ac8survivalmode/scripts/ai/");
    } else {
        BhFail(r, L"path too long", modRoot);
    }
    static const struct { const wchar_t* rel; const char* name; int io; } kFixed[] = {
        { L"config\\survival.default.ini", "ac8survivalmode/config/survival.default.ini", 0 },
        { L"dlls\\main.dll", "ac8survivalmode/dlls/main.dll", 0 },
        { L"SurvivalMode_P.utoc", "iostoreloadermod/survivalmode/survivalmode_p.utoc", 1 },
        { L"SurvivalMode_P.ucas", "iostoreloadermod/survivalmode/survivalmode_p.ucas", 1 },
    };
    for (size_t i = 0; i < sizeof(kFixed) / sizeof(kFixed[0]) && !r->why; ++i) {
        if (!BhJoin(path, kFixed[i].io ? ioDir : modRoot, kFixed[i].rel)) { BhFail(r, L"path too long", kFixed[i].rel); break; }
        BhFile(r, kFixed[i].name, path);
    }
    if (!r->scripts && !r->why) BhFail(r, L"no scripts", L"Scripts");
    free(r->s);
    r->s = NULL;
    int ok = !r->why;
    if (!BhEnd(&r->sha, hex) && ok) { r->why = L"bcrypt failed"; ok = 0; }
    if (!ok) hex[0] = 0;
    return ok;
}
