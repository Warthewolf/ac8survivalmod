/* logbundle.c : the log bundle (runtime 0.32.32; dated names 0.32.33), #included by survival_rt.c after survival_rt_lua.c.
 *
 * Why: when something goes wrong a player should send ONE file. Every file of a session carries the session's start in
 * its name (logzip.h's stamps) and lives in <mod folder>\logs (the user, 2026-11-10), so no session overwrites another's:
 *   logs\AC8SurvivalMode_<stamp>.log          the runtime's log (OpenLog)
 *   logs\AC8SurvivalMode_lua_<stamp>.log      Lua's (sv_core.lua, the stamp from SV_LogStamp)
 *   logs\AC8SurvivalMode_crumbs_<stamp>.log   the crash breadcrumbs (OpenCrumbs)
 *   logs\session_<stamp>.txt                  key=value lines (LbSessionAdd, Lua's SV_Session): start, start_ft, rt,
 *                                             main_dll_ts, pid, build_hash, mod, role ... (a later line with the same key wins)
 *   logs\UE4SS_<stamp>.log                    UE4SS.log copied every 10 s (UE4SS empties UE4SS.log when it starts); a run
 *                                             of the same line once with its count, at most 64 MB (logdedup.h: lag-8)
 *   logs\UE4SS_stats_<stamp>.txt              that copy's counts and most repeated line (bundle.txt sums them up)
 *   logs\AC8Survival_<stamp>_<mod>.zip        a finished session, the 10 newest zips kept (no size cap)
 * At every start a background thread (LbZipThread) zips each earlier session that has no zip yet (logzip.h's LzPick):
 * its files, the game's Saved\Logs\*.log and the files of each Saved\Crashes\UECC-* folder written during it (Saved is
 * %LOCALAPPDATA%\BANDAI NAMCO Entertainment\ACE COMBAT 8\Saved, the game's own folder), and a generated bundle.txt
 * listing what went in and what didn't and why. The zip is written under a .tmp name and renamed when whole; only then
 * are the session's files that went in whole (LZ_OK) deleted. Everything else (a file that didn't, every file of a zip
 * that failed) stays in logs\ under its dated name and is never deleted by the runtime (the user, 2026-11-10: "ça se
 * verra par rapport aux fichiers .zip"). The game thread only takes the stamp at start (LbBegin) and moves the undated
 * names of runtime 0.32.32 and before into logs\, once. If logs\ can't be made, the dated files go in the mod's folder
 * and nothing is zipped. The zip format is logzip.h's. Every function here is static, buffers are static (no stack
 * probe is linked).                                                                                                    */
#include "logzip.h"
#include "logdedup.h"                       /* (lag-8: the UE4SS.log copy's filter) */

#define LB_KEEP 10
#define LB_MAXS 32                               /* sessions zipped at one start at most (the others at the next) */
static wchar_t          g_lbDir[PATH_CAP];       /* <mod>\logs (empty: nothing is zipped this session) */
static wchar_t          g_lbBase[PATH_CAP];      /* where this session's files go: logs\, else the mod's folder */
static wchar_t          g_lbStamp[LZ_STAMP];     /* this session's stamp (empty: none, so no log files) */
static char             g_lbStampA[LZ_STAMP];
static HANDLE           g_lbSess = INVALID_HANDLE_VALUE;
static volatile int32_t g_lbLock;
static uint64_t         g_lbStartFt;             /* this session's start (FILETIME, UTC) */
static char             g_lbRep[16384];          /* bundle.txt */
static size_t           g_lbRepN;
static int              g_lbOldMoved, g_lbOldFail;   /* undated files of an older runtime moved into logs\ at start */

/* left: the session's files not in the zip whole (they stay in logs\) */
typedef struct { int files, skipped, kb, left; wchar_t name[120]; const wchar_t* why; } LbZipRes;

#define LB_FILES_MAX 128                         /* a session's own files zipped (more stay in logs\) */
static wchar_t    g_lbFiles[LB_FILES_MAX][260];
static uint64_t   g_lbFilesFt[LB_FILES_MAX];
static uint8_t    g_lbFilesOk[LB_FILES_MAX];

static int LbJoin(wchar_t* out, const wchar_t* a, const wchar_t* b)
{
    size_t la = WLen(a), lb = WLen(b);
    if (!la || la + lb + 2 >= PATH_CAP) return 0;
    memcpy(out, a, la * 2);
    out[la] = L'\\';
    memcpy(out + la + 1, b, (lb + 1) * 2);
    return 1;
}

static uint64_t LbFt(const WIN32_FIND_DATAW* f) { return ((uint64_t)f->ftLastWriteTime[1] << 32) | (uint64_t)f->ftLastWriteTime[0]; }

static size_t LbNum(char* out, uint64_t v)
{
    char t[24]; size_t n = 0, k = 0;
    do { t[n++] = (char)('0' + v % 10); v /= 10; } while (v && n < 20);
    while (n) out[k++] = t[--n];
    out[k] = 0;
    return k;
}

static uint64_t LbParseU64(const char* s)
{
    uint64_t v = 0;
    while (*s >= '0' && *s <= '9') { v = v * 10 + (uint64_t)(*s - '0'); ++s; }
    return v;
}

/* st (SYSTEMTIME as 8 words) -> "YYYY-MM-DD_HH-MM-SS" (20 bytes with the NUL) */
static void LbStamp(char* out, const uint16_t* st)
{
    int v[6] = { st[0], st[1], st[3], st[4], st[5], st[6] };
    static const char sep[6] = { '-', '-', '_', '-', '-', 0 };
    size_t k = 0;
    out[k++] = (char)('0' + v[0] / 1000 % 10); out[k++] = (char)('0' + v[0] / 100 % 10);
    out[k++] = (char)('0' + v[0] / 10 % 10);   out[k++] = (char)('0' + v[0] % 10);
    out[k++] = sep[0];
    for (int i = 1; i < 6; ++i) {
        out[k++] = (char)('0' + v[i] / 10 % 10); out[k++] = (char)('0' + v[i] % 10);
        if (sep[i]) out[k++] = sep[i];
    }
    out[k] = 0;
}

/* ft (UTC) -> the stamp of its local time (char, LZ_STAMP); 0 when it can't be converted */
static int LbStampFt(uint64_t ft, char* out)
{
    uint64_t lft = 0;
    uint16_t st[8];
    if (!ft || !FileTimeToLocalFileTime(&ft, &lft) || !FileTimeToSystemTime(&lft, st)) return 0;
    LbStamp(out, st);
    return 1;
}

static void LbWide(wchar_t* out, const char* a) { size_t i = 0; for (; a[i]; ++i) out[i] = (wchar_t)(uint8_t)a[i]; out[i] = 0; }

static void LbEnt(wchar_t* out, size_t cap, const wchar_t* a, const wchar_t* b, const wchar_t* c)
{
    size_t k = 0;
    for (const wchar_t* s = a; s && *s && k + 1 < cap; ++s) out[k++] = *s;
    for (const wchar_t* s = b; s && *s && k + 1 < cap; ++s) out[k++] = *s;
    for (const wchar_t* s = c; s && *s && k + 1 < cap; ++s) out[k++] = *s;
    out[k] = 0;
}

/* <base>\<prefix>_<stamp><ext>: a file of this session. 0 when there's no stamp or the path is too long. Called by
 * OpenLog and OpenCrumbs (survival_rt.c, declared above them) once LbBegin has run. */
static int LbPath(wchar_t* out, const wchar_t* prefix, const wchar_t* ext)
{
    wchar_t t[200];
    if (!g_lbStamp[0] || !g_lbBase[0]) return 0;
    LbEnt(t, 160, prefix, L"_", g_lbStamp);
    size_t k = WLen(t);
    for (const wchar_t* s = ext; *s && k + 1 < 200; ++s) t[k++] = *s;
    t[k] = 0;
    return LbJoin(out, g_lbBase, t);
}

/* ---- bundle.txt -------------------------------------------------------------- */
static void LbRepAdd(const char* s) { while (*s && g_lbRepN + 2 < sizeof(g_lbRep)) g_lbRep[g_lbRepN++] = *s++; }
static void LbRepW(const wchar_t* w) { for (; *w && g_lbRepN + 2 < sizeof(g_lbRep); ++w) g_lbRep[g_lbRepN++] = (*w >= 0x20 && *w < 0x7F) ? (char)*w : '?'; }
static void LbRepNum(uint64_t v) { char t[24]; LbNum(t, v); LbRepAdd(t); }

static const char* LbWhy(int rc)
{
    switch (rc) {
    case LZ_LOCKED:  return "could not be opened (locked or gone)";
    case LZ_BIG:     return "too big for a non-ZIP64 zip";
    case LZ_READ:    return "read error (not in the zip)";
    case LZ_FULL:    return "no room in the zip's directory, or a bad name";
    case LZ_CHANGED: return "changed while it was zipped (the zip holds what was read, padded with zeros)";
    default:         return "the zip could not be written";
    }
}

static int LbAddFile(LzZip* z, LbZipRes* r, const wchar_t* entry, const wchar_t* path, uint64_t ft)
{
    int rc = LzAddFile(z, entry, path, ft);
    int part = (rc == LZ_CHANGED);                            /* in the zip, as far as it could be read */
    if (rc == LZ_OK) {
        r->files++;
        LbRepAdd("added   "); LbRepW(entry); LbRepAdd(" ("); LbRepNum(z->lastSize); LbRepAdd(" bytes)\n");
    } else {
        r->skipped++;
        if (part) r->files++;
        LbRepAdd(part ? "PARTIAL " : "SKIPPED "); LbRepW(entry); LbRepAdd(": "); LbRepAdd(LbWhy(rc)); LbRepAdd("\n");
    }
    return rc;
}

/* ---- session_<stamp>.txt ------------------------------------------------------------ */
/* value of the last "key=" line of b[0..n) into out (cap bytes); 1 when found */
static int LbKey(const char* b, size_t n, const char* key, char* out, size_t cap)
{
    size_t kl = 0;
    int found = 0;
    while (key[kl]) ++kl;
    size_t i = 0;
    while (i < n) {
        size_t e = i;
        while (e < n && b[e] != '\n') ++e;
        size_t le = e;
        if (le > i && b[le - 1] == '\r') --le;
        if (le - i > kl && b[i + kl] == '=' && memcmp(b + i, key, kl) == 0) {
            size_t vl = le - i - kl - 1;
            if (vl >= cap) vl = cap - 1;
            memcpy(out, b + i + kl + 1, vl);
            out[vl] = 0;
            found = 1;
        }
        i = e + 1;
    }
    return found;
}

static void LbSessionAdd(const char* key, const char* value)
{
    char line[300];
    size_t k = 0;
    if (g_lbSess == INVALID_HANDLE_VALUE) return;
    for (size_t i = 0; key[i] && k < 40; ++i) line[k++] = key[i];
    line[k++] = '=';
    for (size_t i = 0; value[i] && k < 280; ++i) line[k++] = value[i];
    line[k++] = '\n';
    while (__sync_lock_test_and_set(&g_lbLock, 1)) Sleep(0);
    DWORD put = 0;
    WriteFile(g_lbSess, line, (DWORD)k, &put, NULL);
    __sync_lock_release(&g_lbLock);
}

/* SV_Session("key=value"): Lua adds a line to session_<stamp>.txt. key [a-z0-9_]{1,32}, value up to 200 printable
 * ASCII characters; 1 when written, 0 when refused */
static int L_Session(void* lua)
{
    wchar_t w[256];
    char a[256];
    if (!ArgName(lua, w, 250)) return Ret(lua, 0);
    size_t n = WLen(w), eq = 0;
    for (size_t i = 0; i < n; ++i) a[i] = (char)w[i];
    a[n] = 0;
    while (eq < n && a[eq] != '=') ++eq;
    if (eq < 1 || eq > 32 || eq >= n || n - eq - 1 > 200) return Ret(lua, 0);
    for (size_t i = 0; i < eq; ++i) {
        char c = a[i];
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) return Ret(lua, 0);
    }
    if (g_lbSess == INVALID_HANDLE_VALUE) return Ret(lua, 0);
    a[eq] = 0;
    LbSessionAdd(a, a + eq + 1);
    return Ret(lua, 1);
}

/* SV_LogStamp() -> this session's stamp ("" when there's none): Lua's log is logs\AC8SurvivalMode_lua_<stamp>.log */
static int L_LogStamp(void* lua)
{
    size_t n = 0;
    while (g_lbStampA[n]) ++n;
    U.luaSetString(lua, g_lbStampA, n);
    return 1;
}

static void LbSessionBegin(void)
{
    static wchar_t path[PATH_CAP];
    char v[40];
    if (!LbPath(path, L"session", L".txt")) return;
    g_lbSess = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (g_lbSess == INVALID_HANDLE_VALUE) return;
    LbSessionAdd("start", g_lbStampA);
    LbNum(v, g_lbStartFt);
    LbSessionAdd("start_ft", v);
    LbSessionAdd("rt", RT_VERSION_A);
    {   /* main.dll's PE TimeDateStamp: build.sh keeps main_<version>_<stamp>.map under that stamp */
        const uint8_t* base = (const uint8_t*)g_hModule;
        if (base && Readable(base, 0x40)) {
            uint32_t pe = *(const uint32_t*)(base + 0x3C);
            if (pe < 0x1000 && Readable(base + pe, 16)) {
                uint32_t ts = *(const uint32_t*)(base + pe + 8);
                static const char hx[] = "0123456789abcdef";
                for (int i = 0; i < 8; ++i) v[i] = hx[(ts >> (28 - 4 * i)) & 15u];
                v[8] = 0;
                LbSessionAdd("main_dll_ts", v);
            }
        }
    }
    LbNum(v, GetCurrentProcessId());
    LbSessionAdd("pid", v);
}

/* ---- the zip of an earlier session ---------------------------------------------------- */
/* session_<s>.txt: its start_ft (0 when unknown), its mod version (else rt) into mod (cap) when mod is given; *found 1
 * when the file is there */
static uint64_t LbSessInfo(const wchar_t* s, char* mod, size_t cap, int* found)
{
    static wchar_t p[PATH_CAP];
    static char sess[4096];
    wchar_t t[80];
    char sft[32];
    size_t sn = 0;
    if (found) *found = 0;
    if (mod) mod[0] = 0;
    LbEnt(t, 80, L"session_", s, L".txt");
    if (!LbJoin(p, g_lbDir, t)) return 0;
    HANDLE h = CreateFileW(p, GENERIC_READ, 7u, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return 0;
    DWORD got = 0;
    if (ReadFile(h, sess, (DWORD)sizeof(sess) - 1, &got, NULL)) sn = got;
    CloseHandle(h);
    if (found) *found = 1;
    if (mod && !LbKey(sess, sn, "mod", mod, cap)) LbKey(sess, sn, "rt", mod, cap);
    sft[0] = 0;
    LbKey(sess, sn, "start_ft", sft, sizeof(sft));
    return LbParseU64(sft);
}

/* Where session s ends, for the game's own files: the next session's start (this session's when s is the last one
 * before it), else (the next session's start is unknown) s's newest file + 10 minutes. The next session is the next
 * stamp in logs\, from its files or its zip. */
static uint64_t LbSessEnd(const wchar_t* s, uint64_t newestFt)
{
    static wchar_t pat[PATH_CAP];
    wchar_t st[LZ_STAMP], next[LZ_STAMP];
    WIN32_FIND_DATAW fd;
    next[0] = 0;
    if (LbJoin(pat, g_lbDir, L"*")) {
        HANDLE f = FindFirstFileW(pat, &fd);
        if (f != INVALID_HANDLE_VALUE) {
            do {
                if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
                if (!LzFileStamp(fd.cFileName, st) && !LzZipStamp(fd.cFileName, st)) continue;
                if (LzWCmp(st, s) > 0 && (!next[0] || LzWCmp(st, next) < 0)) memcpy(next, st, sizeof(next));
            } while (FindNextFileW(f, &fd));
            FindClose(f);
        }
    }
    if (!next[0] || !LzWCmp(next, g_lbStamp)) return g_lbStartFt;
    uint64_t ft = LbSessInfo(next, NULL, 0, NULL);
    if (ft) return ft;
    return newestFt ? newestFt + 6000000000ull : g_lbStartFt;     /* (10 minutes in 100 ns) */
}

/* Zips session s (its files in logs\, the game's Saved logs and crash folders of its time) into
 * logs\AC8Survival_<s>_<mod>.zip. 1 on success (its files that went in whole are then deleted; r->left the others,
 * left in logs\); 0 with r->why (its files all left as they are). Runs on the zip thread. */
static int LbZipSession(const wchar_t* s, LbZipRes* r)
{
    static wchar_t tmp[PATH_CAP], fin[PATH_CAP], src[PATH_CAP], pat[PATH_CAP], saved[PATH_CAP], dpath[PATH_CAP];
    static wchar_t ent[300], nm[140];
    static char mod[80], nmA[140], sA[LZ_STAMP], sft[24];
    static LzZip z;
    WIN32_FIND_DATAW fd, fd2;
    wchar_t st[LZ_STAMP];
    r->files = r->skipped = r->kb = r->left = 0;
    r->name[0] = 0;
    r->why = NULL;
    g_lbRepN = 0;
    int found = 0;
    uint64_t prevStart = LbSessInfo(s, mod, sizeof(mod), &found);
    for (char* c = mod; *c; ++c) if (!((*c >= '0' && *c <= '9') || (*c >= 'A' && *c <= 'Z') || (*c >= 'a' && *c <= 'z') || *c == '.' || *c == '-' || *c == '_')) *c = '_';
    {
        size_t k = 0, i = 0;
        for (; s[i] && i + 1 < LZ_STAMP; ++i) sA[i] = (char)s[i];
        sA[i] = 0;
        const char* parts[4] = { "AC8Survival_", sA, "_", mod[0] ? mod : "unknown" };
        for (int p = 0; p < 4; ++p) for (const char* c = parts[p]; *c && k < 100; ++c) nmA[k++] = *c;
        nmA[k] = 0;
        for (size_t j = 0; j <= k; ++j) nm[j] = (wchar_t)nmA[j];                  /* the name without ".zip" */
    }

    /* 1. the session's own files: names and times first (logs\ isn't changed while it's listed) */
    int nf = 0, nbad = 0;
    uint64_t newestFt = 0;
    if (LbJoin(pat, g_lbDir, L"*")) {
        HANDLE f = FindFirstFileW(pat, &fd);
        if (f != INVALID_HANDLE_VALUE) {
            do {
                if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || !LzFileStamp(fd.cFileName, st) || LzWCmp(st, s)) continue;
                if (nf >= LB_FILES_MAX) { nbad++; continue; }
                memcpy(g_lbFiles[nf], fd.cFileName, sizeof(g_lbFiles[0]));
                g_lbFiles[nf][259] = 0;
                g_lbFilesFt[nf] = LbFt(&fd);
                if (g_lbFilesFt[nf] > newestFt) newestFt = g_lbFilesFt[nf];
                g_lbFilesOk[nf] = 0;
                nf++;
            } while (FindNextFileW(f, &fd));
            FindClose(f);
        }
    }
    if (!nf) { r->why = L"no files of that session"; return 0; }
    uint64_t end = LbSessEnd(s, newestFt);
    int newest = (end == g_lbStartFt);                    /* no session between it and this one */
    {
        wchar_t t[160];
        LbEnt(t, 160, nm, L".zip.tmp", NULL);
        if (!LbJoin(tmp, g_lbDir, t)) { r->why = L"path too long"; return 0; }
    }
    if (!LzBegin(&z, tmp)) { r->why = L"could not create the zip"; return 0; }

    LbNum(sft, prevStart);
    LbRepAdd("AC8 Survival Mode: the logs of one session\nbundle: "); LbRepAdd(nmA);
    LbRepAdd("\nsession: "); LbRepAdd(sA);
    LbRepAdd("\nstart_ft="); LbRepAdd(prevStart ? sft : "unknown");
    LbRepAdd("\nsession file: "); LbRepAdd(found ? "found" : "missing");
    LbRepAdd("\n(zip entry times are UTC; entries that are not listed as SKIPPED are in the zip)\n\n");
    for (int i = 0; i < nf; ++i) {
        if (!LbJoin(src, g_lbDir, g_lbFiles[i])) { nbad++; LbRepAdd("SKIPPED "); LbRepW(g_lbFiles[i]); LbRepAdd(": path too long\n"); continue; }
        if (LbAddFile(&z, r, g_lbFiles[i], src, g_lbFilesFt[i]) == LZ_OK) g_lbFilesOk[i] = 1; else nbad++;
    }

    /* 2. the game's own, written during the session: Saved\Logs\*.log and Saved\Crashes\UECC-* */
    DWORD en = GetEnvironmentVariableW(L"LOCALAPPDATA", dpath, PATH_CAP - 100);
    if (!prevStart && !newest) {
        LbRepAdd("the game's Saved folder: this session's start is unknown (no session file) and a later session came after it: nothing taken from it\n");
    } else if (en && en < PATH_CAP - 100 && LbJoin(saved, dpath, L"BANDAI NAMCO Entertainment\\ACE COMBAT 8\\Saved")) {
        for (int kind = 0; kind < 2; ++kind) {              /* 0: Saved\Logs\*.log, 1: Saved\Crashes\UECC-* folders */
            uint64_t best = 0;
            for (int pass = 0; pass < 2; ++pass) {
                if (!LbJoin(dpath, saved, kind ? L"Crashes\\UECC-*" : L"Logs\\*.log")) break;
                HANDLE f = FindFirstFileW(dpath, &fd);
                if (f == INVALID_HANDLE_VALUE) break;
                do {
                    int isDir = (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
                    if (isDir != kind) continue;
                    uint64_t ft = LbFt(&fd);
                    /* written after the session ended: a later session's (or this one's: the game is writing it) */
                    if (end && ft >= end) continue;
                    if (prevStart && ft < prevStart) continue;
                    if (pass == 0) { if (ft > best) best = ft; continue; }
                    if (!prevStart && ft != best) continue;     /* (start unknown: only the newest of each) */
                    if (!kind) {
                        LbEnt(src, PATH_CAP, saved, L"\\Logs\\", fd.cFileName);
                        LbEnt(ent, 300, L"Saved/Logs/", fd.cFileName, NULL);
                        LbAddFile(&z, r, ent, src, ft);
                    } else {
                        LbEnt(src, PATH_CAP, saved, L"\\Crashes\\", fd.cFileName);
                        LbEnt(dpath, PATH_CAP, src, L"\\*", NULL);
                        HANDLE g = FindFirstFileW(dpath, &fd2);
                        if (g == INVALID_HANDLE_VALUE) continue;
                        do {
                            if (fd2.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
                            LbEnt(dpath, PATH_CAP, src, L"\\", fd2.cFileName);
                            LbEnt(ent, 300, L"Crashes/", fd.cFileName, L"/");
                            if (WLen(ent) + WLen(fd2.cFileName) < 299) {
                                size_t el = WLen(ent);
                                memcpy(ent + el, fd2.cFileName, (WLen(fd2.cFileName) + 1) * 2);
                                LbAddFile(&z, r, ent, dpath, LbFt(&fd2));
                            }
                        } while (FindNextFileW(g, &fd2));
                        FindClose(g);
                        /* dpath was the enumeration pattern of this pass: put it back */
                        LbJoin(dpath, saved, L"Crashes\\UECC-*");
                    }
                } while (FindNextFileW(f, &fd));
                FindClose(f);
            }
        }
    } else {
        LbRepAdd("the game's Saved folder: LOCALAPPDATA not set, nothing taken from it\n");
    }
    /* ((2026-11-11) lag-8) the UE4SS.log copy's counts and its most repeated line (logs\UE4SS_stats_<s>.txt) */
    {
        static char sb[1200];
        static wchar_t sp[PATH_CAP];
        wchar_t t[80];
        size_t sn = 0;
        LbEnt(t, 80, L"UE4SS_stats_", s, L".txt");
        HANDLE h = LbJoin(sp, g_lbDir, t) ? CreateFileW(sp, GENERIC_READ, 7u, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL)
                                          : INVALID_HANDLE_VALUE;
        if (h != INVALID_HANDLE_VALUE) {
            DWORD got = 0;
            if (ReadFile(h, sb, (DWORD)sizeof(sb) - 1, &got, NULL)) sn = got;
            CloseHandle(h);
        }
        char v[220];
        if (sn && LbKey(sb, sn, "ue4ss_read_bytes", v, sizeof(v))) {
            LbRepAdd("\nUE4SS.log: "); LbRepNum((LbParseU64(v) + (1u << 19)) >> 20); LbRepAdd(" MB read, ");
            v[0] = 0; LbKey(sb, sn, "ue4ss_copied_bytes", v, sizeof(v));
            LbRepNum((LbParseU64(v) + (1u << 19)) >> 20); LbRepAdd(" MB copied into UE4SS_"); LbRepW(s); LbRepAdd(".log (");
            v[0] = 0; LbKey(sb, sn, "ue4ss_lines", v, sizeof(v)); LbRepNum(LbParseU64(v)); LbRepAdd(" lines, ");
            v[0] = 0; LbKey(sb, sn, "ue4ss_collapsed", v, sizeof(v)); LbRepNum(LbParseU64(v));
            LbRepAdd(" of them repeats of the line before, collapsed into one line each run, ");
            v[0] = 0; LbKey(sb, sn, "ue4ss_dropped", v, sizeof(v)); LbRepNum(LbParseU64(v)); LbRepAdd(" past the copy's 64 MB)\n");
            v[0] = 0; LbKey(sb, sn, "ue4ss_top_count", v, sizeof(v));
            if (LbParseU64(v)) {
                LbRepAdd("its most repeated line ("); LbRepNum(LbParseU64(v)); LbRepAdd(" repeats): ");
                v[0] = 0; LbKey(sb, sn, "ue4ss_top_line", v, sizeof(v)); LbRepAdd(v); LbRepAdd("\n");
            }
        } else {
            LbRepAdd("\nUE4SS.log: no counts (UE4SS_stats_ missing: an older runtime, or nothing was copied)\n");
        }
    }
    LbRepAdd("\nfiles in the zip: "); LbRepNum((uint64_t)r->files);
    LbRepAdd(", skipped or partial: "); LbRepNum((uint64_t)r->skipped); LbRepAdd("\n");
    if (nbad) {
        LbRepAdd("files of this session not in the zip whole: "); LbRepNum((uint64_t)nbad);
        LbRepAdd(" (not deleted: they stay in logs\\ under their names)\n");
    }
    if (LzAddMem(&z, L"bundle.txt", g_lbRep, (uint32_t)g_lbRepN, g_lbStartFt) != LZ_OK) { LzAbort(&z); DeleteFileW(tmp); r->why = L"bundle.txt could not be added"; return 0; }
    if (!LzEnd(&z)) { DeleteFileW(tmp); r->why = L"the zip could not be written"; return 0; }
    r->kb = (int)((z.pos + 1023u) / 1024u);

    /* the final name (_2, _3 ... when a zip of that name exists) */
    size_t nl = WLen(nm);
    int placed = 0;
    for (int i = 1; i < 100 && !placed; ++i) {
        wchar_t t[160];
        size_t k = nl;
        memcpy(t, nm, nl * 2);
        if (i > 1) { t[k++] = L'_'; if (i >= 10) t[k++] = (wchar_t)(L'0' + i / 10); t[k++] = (wchar_t)(L'0' + i % 10); }
        memcpy(t + k, L".zip", 5 * 2);
        if (LbJoin(fin, g_lbDir, t) && MoveFileExW(tmp, fin, 0)) {
            memcpy(r->name, t, (WLen(t) + 1) * 2);
            placed = 1;
        }
    }
    if (!placed) { DeleteFileW(tmp); r->why = L"could not name the zip"; return 0; }

    /* only now: the session's files that went in whole are deleted, the others stay */
    for (int i = 0; i < nf; ++i) if (g_lbFilesOk[i] && LbJoin(src, g_lbDir, g_lbFiles[i])) DeleteFileW(src);
    r->left = nbad;
    return 1;
}

/* ---- at start ------------------------------------------------------------------- */
/* dir\old -> logs\<prefix>_<st><ext>, unless that one exists */
static void LbOldMove(const wchar_t* dir, const wchar_t* old, const wchar_t* prefix, const wchar_t* ext, const wchar_t* st)
{
    static wchar_t a[PATH_CAP], b[PATH_CAP];
    wchar_t t[200];
    if (!LbJoin(a, dir, old) || GetFileAttributesW(a) == INVALID_FILE_ATTRIBUTES) return;
    LbEnt(t, 160, prefix, L"_", st);
    size_t k = WLen(t);
    for (const wchar_t* s = ext; *s && k + 1 < 200; ++s) t[k++] = *s;
    t[k] = 0;
    if (LbJoin(b, g_lbDir, t) && MoveFileExW(a, b, MOVEFILE_COPY_ALLOWED)) g_lbOldMoved++; else g_lbOldFail++;
}

/* dir\name's last write as a stamp into st; 0 when it isn't there */
static int LbOldStamp(const wchar_t* dir, const wchar_t* name, wchar_t* st)
{
    static wchar_t p[PATH_CAP];
    WIN32_FIND_DATAW fd;
    char sa[LZ_STAMP];
    if (!LbJoin(p, dir, name)) return 0;
    HANDLE f = FindFirstFileW(p, &fd);
    if (f == INVALID_HANDLE_VALUE) return 0;
    FindClose(f);
    if (!LbStampFt(LbFt(&fd), sa)) return 0;
    LbWide(st, sa);
    return 1;
}

/* Runtime 0.32.32 and before wrote undated names: AC8SurvivalMode.log, _lua.log, _crumbs.log and _crumbs.prev.log in
 * the mod's folder (and 0.32.32 logs\session.txt and logs\UE4SS.session.log). They move into logs\ once, as one
 * session under the stamp of the runtime log's last write (the Lua log's when there's none), the crumbs' .prev (an
 * older session) under its own; the zip thread then zips them like any session. 0.32.32's logs\prev is left alone. */
static void LbOldNames(void)
{
    wchar_t st[LZ_STAMP];
    if (LbOldStamp(g_modRoot, L"AC8SurvivalMode.log", st) || LbOldStamp(g_modRoot, L"AC8SurvivalMode_lua.log", st)) {
        LbOldMove(g_modRoot, L"AC8SurvivalMode.log", L"AC8SurvivalMode", L".log", st);
        LbOldMove(g_modRoot, L"AC8SurvivalMode_lua.log", L"AC8SurvivalMode_lua", L".log", st);
        LbOldMove(g_modRoot, L"AC8SurvivalMode_crumbs.log", L"AC8SurvivalMode_crumbs", L".log", st);
        LbOldMove(g_lbDir, L"session.txt", L"session", L".txt", st);
        LbOldMove(g_lbDir, L"UE4SS.session.log", L"UE4SS", L".log", st);
    }
    if (LbOldStamp(g_modRoot, L"AC8SurvivalMode_crumbs.prev.log", st))
        LbOldMove(g_modRoot, L"AC8SurvivalMode_crumbs.prev.log", L"AC8SurvivalMode_crumbs", L".log", st);
}

/* Game thread, at start, before OpenLog: this session's stamp and folder; the old undated names moved into logs\.
 * Renames only: the zipping is the zip thread's. */
static void LbBegin(void)
{
    static wchar_t probe[PATH_CAP];
    uint16_t st[8];
    GetSystemTimeAsFileTime(&g_lbStartFt);
    if (!g_modRoot[0]) return;
    if (LbJoin(g_lbDir, g_modRoot, L"logs")) {
        CreateDirectoryW(g_lbDir, NULL);
        DWORD a = GetFileAttributesW(g_lbDir);
        if (a == INVALID_FILE_ATTRIBUTES || !(a & FILE_ATTRIBUTE_DIRECTORY)) g_lbDir[0] = 0;
    }
    memcpy(g_lbBase, g_lbDir[0] ? g_lbDir : g_modRoot, sizeof(g_lbBase));
    GetLocalTime(st);
    LbStamp(g_lbStampA, st);
    for (int i = 0; i < 26; ++i) {                        /* this second's stamp taken: a letter b ... z after it */
        if (i) { g_lbStampA[19] = (char)('a' + i); g_lbStampA[20] = 0; }
        LbWide(g_lbStamp, g_lbStampA);
        if (!LbPath(probe, L"AC8SurvivalMode", L".log") || GetFileAttributesW(probe) == INVALID_FILE_ATTRIBUTES) break;
    }
    if (g_lbDir[0]) LbOldNames();
}

static void LbReport(void)
{
    if (!g_lbStamp[0]) return;                            /* (no stamp: no log file either) */
    Log(L"logs: this session's files are %s\\*_%s.* (the runtime's and Lua's logs, the crumbs, session, UE4SS)",
        g_lbDir[0] ? L"logs" : L"the mod's folder", g_lbStamp);
    if (!g_lbDir[0]) Log(L"logs: the logs folder could not be made; nothing is zipped this session");
    if (g_lbOldMoved || g_lbOldFail)
        Log(L"logs: an older runtime's undated logs moved into logs\\: %d (%d could not be)", (int32_t)g_lbOldMoved, (int32_t)g_lbOldFail);
}

static DWORD WINAPI LbZipThread(void* arg)
{
    static wchar_t picks[LB_MAXS][LZ_STAMP];
    (void)arg;
    if (!g_lbDir[0]) return 0;
    int n = LzPick(g_lbDir, g_lbStamp, LB_KEEP, picks, LB_MAXS);
    for (int i = 0; i < n; ++i) {
        LbZipRes r;
        uint64_t t0 = GetTickCount64();
        if (LbZipSession(picks[i], &r)) {
            Log(L"logs: session %s zipped: %s (%d files, %d KB, %d skipped, %d ms)", picks[i], r.name, (int32_t)r.files, (int32_t)r.kb,
                (int32_t)r.skipped, (int32_t)(GetTickCount64() - t0));
            if (r.left) Log(L"logs: %d of its files are not whole in that zip: they stay in logs\\ under their names (never deleted)", (int32_t)r.left);
        }
        else Log(L"logs: zipping session %s failed: %s (its files stay in logs\\ under their names)", picks[i], r.why ? r.why : L"?");
    }
    int gone = LzPrune(g_lbDir, L"AC8Survival_", LB_KEEP);
    if (gone) Log(L"logs: %d older zips deleted (%d kept)", (int32_t)gone, (int32_t)LB_KEEP);
    return 0;
}

/* UE4SS.log -> logs\UE4SS_<stamp>.log, what was added since the last copy, every 10 s.
 * ((2026-11-11) Saint Alessia's 50-round co-op run, lag-8: through logdedup.h, a run of lines the same after their time
 * stamp written once and counted, the copy stopped at 64 MB; her 415 MB UE4SS.log was 98.3% one line of another mod's.
 * The counts and the most repeated line in logs\UE4SS_stats_<stamp>.txt (rewritten each pass that read something, then
 * summed up in the bundle's bundle.txt), and in the runtime's log every 10 minutes: "logs: UE4SS.log's copy: ...") */
static HANDLE  g_ldOut = INVALID_HANDLE_VALUE;
static uint8_t g_ldBuf[65536];
static size_t  g_ldBufN;
static LdState g_ld;
static void LdFlushOut(void)
{
    if (!g_ldBufN) return;
    DWORD put = 0;
    WriteFile(g_ldOut, g_ldBuf, (DWORD)g_ldBufN, &put, NULL);
    g_ldBufN = 0;
}
static void LdPutOut(void* ctx, const char* p, size_t n)
{
    (void)ctx;
    while (n) {
        if (g_ldBufN == sizeof(g_ldBuf)) LdFlushOut();
        size_t k = sizeof(g_ldBuf) - g_ldBufN;
        if (k > n) k = n;
        memcpy(g_ldBuf + g_ldBufN, p, k);
        g_ldBufN += k; p += k; n -= k;
    }
}
static void LbStatsKey(char* b, size_t* k, size_t cap, const char* key, uint64_t v, const char* text)
{
    for (size_t i = 0; key[i] && *k + 2 < cap; ++i) b[(*k)++] = key[i];
    if (*k + 2 < cap) b[(*k)++] = '=';
    if (text) for (size_t i = 0; text[i] && *k + 3 < cap; ++i) b[(*k)++] = text[i];
    else if (*k + 24 < cap) *k += LbNum(b + *k, v);
    if (*k + 2 < cap) { b[(*k)++] = '\r'; b[(*k)++] = '\n'; }
}
static void LbUe4ssStats(const wchar_t* path)
{
    static char b[1024];
    size_t k = 0;
    LbStatsKey(b, &k, sizeof(b), "ue4ss_read_bytes", g_ld.inBytes, NULL);
    LbStatsKey(b, &k, sizeof(b), "ue4ss_copied_bytes", g_ld.outBytes, NULL);
    LbStatsKey(b, &k, sizeof(b), "ue4ss_lines", g_ld.lines, NULL);
    LbStatsKey(b, &k, sizeof(b), "ue4ss_collapsed", g_ld.collapsed, NULL);
    LbStatsKey(b, &k, sizeof(b), "ue4ss_dropped", g_ld.dropped, NULL);
    LbStatsKey(b, &k, sizeof(b), "ue4ss_top_count", g_ld.topN, NULL);
    LbStatsKey(b, &k, sizeof(b), "ue4ss_top_line", 0, g_ld.topText);
    HANDLE h = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return;
    DWORD put = 0;
    WriteFile(h, b, (DWORD)k, &put, NULL);
    CloseHandle(h);
}
static DWORD WINAPI LbUe4ssThread(void* arg)
{
    static wchar_t src[PATH_CAP], dst[PATH_CAP], stats[PATH_CAP];
    static uint8_t buf[32768];
    (void)arg;
    if (!LbPath(dst, L"UE4SS", L".log")) return 0;
    int haveStats = LbPath(stats, L"UE4SS_stats", L".txt");
    HANDLE m = GetModuleHandleW(L"UE4SS.dll");
    DWORD n = m ? GetModuleFileNameW(m, src, PATH_CAP) : 0;
    if (!n || n >= PATH_CAP) { Log(L"logs: UE4SS.dll not found; UE4SS.log is not copied"); return 0; }
    wchar_t* s = src + n;
    while (s > src && *s != L'\\' && *s != L'/') --s;
    *s = 0;
    {
        static wchar_t t[PATH_CAP];
        if (!LbJoin(t, src, L"UE4SS.log")) return 0;
        memcpy(src, t, (WLen(t) + 1) * 2);
    }
    HANDLE out = CreateFileW(dst, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (out == INVALID_HANDLE_VALUE) { Log(L"logs: %s could not be created; UE4SS.log is not copied", dst); return 0; }
    g_ldOut = out;
    LdInit(&g_ld);
    Log(L"logs: UE4SS.log (%s) is copied to %s every 10 s (a run of the same line once, counted; at most 64 MB: lag-8)", src, dst);
    int64_t off = 0;
    uint64_t lineAt = GetTickCount64(), saidCollapsed = 0;
    for (;;) {
        int64_t was = off;
        HANDLE in = CreateFileW(src, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (in != INVALID_HANDLE_VALUE) {
            int64_t size = 0;
            if (GetFileSizeEx(in, &size)) {
                if (size < off) {                                /* it got smaller: UE4SS started over */
                    static const char mark[] = "\r\n---- UE4SS.log started over ----\r\n";
                    LdRunEnd(&g_ld, LdPutOut, NULL);
                    g_ld.curN = g_ld.curLen = 0;
                    LdPutOut(NULL, mark, sizeof(mark) - 1);
                    off = was = 0;
                }
                if (size > off && SetFilePointerEx(in, off, NULL, 0)) {
                    for (;;) {
                        DWORD got = 0;
                        if (!ReadFile(in, buf, (DWORD)sizeof(buf), &got, NULL) || !got) break;
                        LdFeed(&g_ld, (const char*)buf, got, LdPutOut, NULL);
                        off += got;
                    }
                }
            }
            CloseHandle(in);
        }
        if (off == was) LdIdle(&g_ld, LdPutOut, NULL);       /* (nothing new: a run's count written now) */
        LdFlushOut();
        if (haveStats && off != was) LbUe4ssStats(stats);
        uint64_t now = GetTickCount64();
        if (now - lineAt >= 600000 || (g_ld.collapsed >= 1000 && !saidCollapsed)) {
            lineAt = now;
            saidCollapsed = g_ld.collapsed ? g_ld.collapsed : 1;
            Log(L"logs: UE4SS.log's copy: %u MB read, %u MB written, %u lines, %u of them repeats collapsed, %u past the "
                L"64 MB cap; its most repeated line %u times (lag-8)", (uint32_t)(g_ld.inBytes >> 20), (uint32_t)(g_ld.outBytes >> 20),
                (uint32_t)g_ld.lines, (uint32_t)g_ld.collapsed, (uint32_t)g_ld.dropped, (uint32_t)g_ld.topN);
        }
        Sleep(10000);
    }
}
