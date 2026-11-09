/* logbundle.c : the log bundle (runtime 0.32.32), #included by survival_rt.c after survival_rt_lua.c.
 *
 * Why: when something goes wrong a player should send ONE file. At every game start this runtime zips the PREVIOUS
 * session's logs into <mod folder>\logs\AC8Survival_<start>_<mod version>.zip, keeps the 10 newest zips (no size cap),
 * and deletes older ones. The game thread only moves the files aside (LbStashPrevious: a few renames, before OpenLog /
 * the Lua log truncate them); a background thread (LbZipThread) does the zipping.
 *
 *   <mod>\logs\prev\          the previous session's files, moved here at start (the stash)
 *   <mod>\logs\session.txt    this session's key=value lines (LbSessionAdd, Lua's SV_Session): start, start_ft, rt,
 *                             main_dll_ts, pid, build_hash, mod, role ... (a later line with the same key wins)
 *   <mod>\logs\UE4SS.session.log   UE4SS.log copied every 10 s (UE4SS empties UE4SS.log when it starts, before this mod
 *                             loads, so the previous run's copy would be gone otherwise)
 *   <mod>\logs\*.csv          moved into the stash too (reserved for network logs)
 * What the zip holds: every file of logs\prev (flat names; AC8SurvivalMode_crumbs.log is a COPY, OpenCrumbs keeps its own
 * .prev rotation), the game's Saved\Logs\*.log and the files of each Saved\Crashes\UECC-* folder that changed since the
 * previous session started (Saved is %LOCALAPPDATA%\BANDAI NAMCO Entertainment\ACE COMBAT 8\Saved, the game's own
 * folder; with no start time, only the newest of each), and a generated bundle.txt listing what went in and what was
 * skipped and why. The zip is written under a .tmp name, renamed when whole, and the stash is deleted only then; a stash
 * that survives (zip never finished) is zipped synchronously at the next start, before the new files are stashed.
 * The zip format is logzip.h's. Every function here is static, buffers are static (no stack probe is linked).        */
#include "logzip.h"

#define LB_KEEP 10
static wchar_t          g_lbDir[PATH_CAP];       /* <mod>\logs (empty: the bundle is off) */
static wchar_t          g_lbPrev[PATH_CAP];      /* <mod>\logs\prev */
static HANDLE           g_lbSess = INVALID_HANDLE_VALUE;
static volatile int32_t g_lbLock;
static uint64_t         g_lbStartFt;             /* this session's start (FILETIME, UTC) */
static int              g_lbPrevHas;             /* logs\prev holds files for the zip thread */
static char             g_lbRep[16384];          /* bundle.txt */
static size_t           g_lbRepN;

typedef struct { int files, skipped, kb; wchar_t name[120]; const wchar_t* why; } LbZipRes;

/* what the stash did, for LbReport (the log isn't open yet when it runs) */
static int        g_lbMoved, g_lbMoveFail, g_lbCopied, g_lbStashMs, g_lbSync;   /* g_lbSync: 0 none, 1 zipped, 2 failed */
static LbZipRes   g_lbSyncRes;

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

/* ---- bundle.txt -------------------------------------------------------------- */
static void LbRepAdd(const char* s) { while (*s && g_lbRepN + 2 < sizeof(g_lbRep)) g_lbRep[g_lbRepN++] = *s++; }
static void LbRepW(const wchar_t* w) { for (; *w && g_lbRepN + 2 < sizeof(g_lbRep); ++w) g_lbRep[g_lbRepN++] = (*w >= 0x20 && *w < 0x7F) ? (char)*w : '?'; }
static void LbRepNum(uint64_t v) { char t[24]; LbNum(t, v); LbRepAdd(t); }

static const char* LbWhy(int rc)
{
    switch (rc) {
    case LZ_LOCKED:  return "could not be opened (locked or gone)";
    case LZ_BIG:     return "too big for a non-ZIP64 zip";
    case LZ_READ:    return "read error";
    case LZ_FULL:    return "no room in the zip's directory, or a bad name";
    case LZ_CHANGED: return "changed while it was zipped (padded with zeros; its CRC is wrong)";
    default:         return "the zip could not be written";
    }
}

static void LbAddFile(LzZip* z, LbZipRes* r, const wchar_t* entry, const wchar_t* path, uint64_t ft)
{
    int rc = LzAddFile(z, entry, path, ft);
    if (rc == LZ_OK) {
        r->files++;
        LbRepAdd("added   "); LbRepW(entry); LbRepAdd(" ("); LbRepNum(z->lastSize); LbRepAdd(" bytes)\n");
    } else {
        r->skipped++;
        if (rc == LZ_CHANGED) r->files++;
        LbRepAdd("SKIPPED "); LbRepW(entry); LbRepAdd(": "); LbRepAdd(LbWhy(rc)); LbRepAdd("\n");
    }
}

/* ---- session.txt ----------------------------------------------------------------- */
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

/* SV_Session("key=value"): Lua adds a line to session.txt. key [a-z0-9_]{1,32}, value up to 200 printable ASCII
 * characters; 1 when written, 0 when refused */
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

static void LbSessionBegin(void)
{
    static wchar_t path[PATH_CAP];
    char v[40];
    if (!g_lbDir[0] || !LbJoin(path, g_lbDir, L"session.txt")) return;
    g_lbSess = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (g_lbSess == INVALID_HANDLE_VALUE) return;
    uint16_t st[8];
    GetLocalTime(st);
    LbStamp(v, st);
    LbSessionAdd("start", v);
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

/* ---- the zip of logs\prev ---------------------------------------------------------- */
static int LbPrevFiles(void)
{
    static wchar_t pat[PATH_CAP];
    WIN32_FIND_DATAW fd;
    int any = 0;
    if (!g_lbPrev[0] || !LbJoin(pat, g_lbPrev, L"*")) return 0;
    HANDLE f = FindFirstFileW(pat, &fd);
    if (f == INVALID_HANDLE_VALUE) return 0;
    do { if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) any = 1; } while (!any && FindNextFileW(f, &fd));
    FindClose(f);
    return any;
}

static void LbEnt(wchar_t* out, size_t cap, const wchar_t* a, const wchar_t* b, const wchar_t* c)
{
    size_t k = 0;
    for (const wchar_t* s = a; s && *s && k + 1 < cap; ++s) out[k++] = *s;
    for (const wchar_t* s = b; s && *s && k + 1 < cap; ++s) out[k++] = *s;
    for (const wchar_t* s = c; s && *s && k + 1 < cap; ++s) out[k++] = *s;
    out[k] = 0;
}

/* Zips logs\prev (+ the game's Saved logs and crash folders) into logs\AC8Survival_<start>_<mod>.zip. 1 on success (the
 * stash is then deleted); 0 with r->why. Runs on the zip thread, or on the game thread at start for an old stash. */
static int LbZipPrev(LbZipRes* r)
{
    static wchar_t tmp[PATH_CAP], fin[PATH_CAP], src[PATH_CAP], pat[PATH_CAP], saved[PATH_CAP], dpath[PATH_CAP];
    static wchar_t ent[300], nm[140];
    static char sess[4096], start[40], mod[80], sft[32], nmA[140];
    static LzZip z;
    WIN32_FIND_DATAW fd, fd2;
    r->files = r->skipped = r->kb = 0;
    r->name[0] = 0;
    r->why = NULL;
    g_lbRepN = 0;
    size_t sn = 0;
    start[0] = mod[0] = sft[0] = 0;
    if (LbJoin(src, g_lbPrev, L"session.txt")) {
        HANDLE h = CreateFileW(src, GENERIC_READ, 7u, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (h != INVALID_HANDLE_VALUE) {
            DWORD got = 0;
            if (ReadFile(h, sess, (DWORD)sizeof(sess) - 1, &got, NULL)) sn = got;
            CloseHandle(h);
        }
    }
    LbKey(sess, sn, "start", start, sizeof(start));
    if (!LbKey(sess, sn, "mod", mod, sizeof(mod))) LbKey(sess, sn, "rt", mod, sizeof(mod));
    LbKey(sess, sn, "start_ft", sft, sizeof(sft));
    uint64_t prevStart = LbParseU64(sft);
    if (!start[0] && LbJoin(src, g_lbPrev, L"AC8SurvivalMode.log")) {   /* no session.txt: the log's last write */
        HANDLE f = FindFirstFileW(src, &fd);
        if (f != INVALID_HANDLE_VALUE) {
            FindClose(f);
            uint64_t ft = LbFt(&fd), lft = 0;
            uint16_t st[8];
            if (FileTimeToLocalFileTime(&ft, &lft) && FileTimeToSystemTime(&lft, st)) LbStamp(start, st);
        }
    }
    for (char* c = start; *c; ++c) if (!((*c >= '0' && *c <= '9') || *c == '-' || *c == '_')) *c = '_';
    for (char* c = mod; *c; ++c) if (!((*c >= '0' && *c <= '9') || (*c >= 'A' && *c <= 'Z') || (*c >= 'a' && *c <= 'z') || *c == '.' || *c == '-' || *c == '_')) *c = '_';
    {
        size_t k = 0;
        const char* parts[4] = { "AC8Survival_", start[0] ? start : "unknown", "_", mod[0] ? mod : "unknown" };
        for (int p = 0; p < 4; ++p) for (const char* s = parts[p]; *s && k < 68; ++s) nmA[k++] = *s;
        nmA[k] = 0;
        for (size_t i = 0; i <= k; ++i) nm[i] = (wchar_t)nmA[i];                 /* the name without ".zip" */
    }
    {
        wchar_t t[140];
        LbEnt(t, 140, nm, L".zip.tmp", NULL);
        if (!LbJoin(tmp, g_lbDir, t)) { r->why = L"path too long"; return 0; }
    }
    if (!LzBegin(&z, tmp)) { r->why = L"could not create the zip"; return 0; }

    LbRepAdd("AC8 Survival Mode: logs of the previous session\nbundle: "); LbRepAdd(nmA);
    LbRepAdd("\nstart="); LbRepAdd(start[0] ? start : "unknown");
    LbRepAdd("\nstart_ft="); LbRepAdd(sft[0] ? sft : "unknown");
    LbRepAdd("\nsession.txt: "); LbRepAdd(sn ? "found" : "missing");
    LbRepAdd("\n(zip entry times are UTC; entries that are not listed as SKIPPED are in the zip)\n\n");

    /* 1. the stash */
    if (LbJoin(pat, g_lbPrev, L"*")) {
        HANDLE f = FindFirstFileW(pat, &fd);
        if (f != INVALID_HANDLE_VALUE) {
            do {
                if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || !LbJoin(src, g_lbPrev, fd.cFileName)) continue;
                LbAddFile(&z, r, fd.cFileName, src, LbFt(&fd));
            } while (FindNextFileW(f, &fd));
            FindClose(f);
        }
    }

    /* 2. the game's own: Saved\Logs\*.log and Saved\Crashes\UECC-* */
    DWORD en = GetEnvironmentVariableW(L"LOCALAPPDATA", dpath, PATH_CAP - 100);
    if (en && en < PATH_CAP - 100 && LbJoin(saved, dpath, L"BANDAI NAMCO Entertainment\\ACE COMBAT 8\\Saved")) {
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
                    /* a log written since this session began is this session's own (the game is writing it) */
                    if (!kind && g_lbStartFt && ft >= g_lbStartFt) continue;
                    if (prevStart && ft < prevStart) continue;
                    if (pass == 0) { if (ft > best) best = ft; continue; }
                    if (!prevStart && ft != best) continue;
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
    LbRepAdd("\nfiles in the zip: "); LbRepNum((uint64_t)r->files);
    LbRepAdd(", skipped: "); LbRepNum((uint64_t)r->skipped); LbRepAdd("\n");
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

    /* only now the stash goes */
    if (LbJoin(pat, g_lbPrev, L"*")) {
        HANDLE f = FindFirstFileW(pat, &fd);
        if (f != INVALID_HANDLE_VALUE) {
            do {
                if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && LbJoin(src, g_lbPrev, fd.cFileName)) DeleteFileW(src);
            } while (FindNextFileW(f, &fd));
            FindClose(f);
        }
    }
    RemoveDirectoryW(g_lbPrev);
    return 1;
}

/* ---- at start ------------------------------------------------------------------- */
/* dir\name -> logs\prev\name. 1 moved, 0 not there, -1 failed */
static int LbMove(const wchar_t* dir, const wchar_t* name)
{
    static wchar_t a[PATH_CAP], b[PATH_CAP];
    if (!LbJoin(a, dir, name) || !LbJoin(b, g_lbPrev, name)) return -1;
    if (GetFileAttributesW(a) == INVALID_FILE_ATTRIBUTES) return 0;
    return MoveFileExW(a, b, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED) ? 1 : -1;
}

static void LbCount(int rc) { if (rc > 0) g_lbMoved++; else if (rc < 0) g_lbMoveFail++; }

/* Game thread, before OpenLog: sets the previous session's files aside (renames only). An earlier stash that was never
 * zipped is zipped first, synchronously, so nothing is lost. */
static void LbStashPrevious(void)
{
    static wchar_t pat[PATH_CAP], sess[PATH_CAP], crumb[PATH_CAP], crumbTo[PATH_CAP];
    uint64_t t0 = GetTickCount64();
    GetSystemTimeAsFileTime(&g_lbStartFt);
    if (!g_modRoot[0]) return;
    if (!LbJoin(g_lbDir, g_modRoot, L"logs") || !LbJoin(g_lbPrev, g_lbDir, L"prev")) { g_lbDir[0] = 0; g_lbPrev[0] = 0; return; }
    CreateDirectoryW(g_lbDir, NULL);
    CreateDirectoryW(g_lbPrev, NULL);
    if (GetFileAttributesW(g_lbPrev) == INVALID_FILE_ATTRIBUTES) { g_lbDir[0] = 0; g_lbPrev[0] = 0; return; }
    if (LbJoin(sess, g_lbPrev, L"session.txt") && GetFileAttributesW(sess) != INVALID_FILE_ATTRIBUTES) {
        g_lbSync = LbZipPrev(&g_lbSyncRes) ? 1 : 2;
        CreateDirectoryW(g_lbPrev, NULL);
    }
    LbCount(LbMove(g_modRoot, L"AC8SurvivalMode.log"));
    LbCount(LbMove(g_modRoot, L"AC8SurvivalMode_lua.log"));
    LbCount(LbMove(g_lbDir, L"UE4SS.session.log"));
    LbCount(LbMove(g_lbDir, L"session.txt"));
    if (LbJoin(pat, g_lbDir, L"*.csv")) {
        WIN32_FIND_DATAW fd;
        HANDLE f = FindFirstFileW(pat, &fd);
        if (f != INVALID_HANDLE_VALUE) {
            do { if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) LbCount(LbMove(g_lbDir, fd.cFileName)); } while (FindNextFileW(f, &fd));
            FindClose(f);
        }
    }
    if (LbJoin(crumb, g_modRoot, L"AC8SurvivalMode_crumbs.log") && LbJoin(crumbTo, g_lbPrev, L"AC8SurvivalMode_crumbs.log") &&
        GetFileAttributesW(crumb) != INVALID_FILE_ATTRIBUTES) {
        if (CopyFileW(crumb, crumbTo, 0)) g_lbCopied++; else g_lbMoveFail++;
    }
    g_lbPrevHas = LbPrevFiles();
    g_lbStashMs = (int)(GetTickCount64() - t0);
}

static void LbReport(void)
{
    if (!g_lbDir[0]) { Log(L"logs: the logs folder could not be made; no log bundle this session"); return; }
    Log(L"logs: previous session's files set aside: %d moved, %d copied, %d failed (%d ms)", (int32_t)g_lbMoved, (int32_t)g_lbCopied,
        (int32_t)g_lbMoveFail, (int32_t)g_lbStashMs);
    if (g_lbSync == 1) Log(L"logs: an earlier stash was zipped first: %s (%d files, %d KB)", g_lbSyncRes.name, (int32_t)g_lbSyncRes.files, (int32_t)g_lbSyncRes.kb);
    else if (g_lbSync == 2) Log(L"logs: an earlier stash could not be zipped: %s", g_lbSyncRes.why ? g_lbSyncRes.why : L"?");
}

static DWORD WINAPI LbZipThread(void* arg)
{
    (void)arg;
    if (!g_lbDir[0]) return 0;
    if (g_lbPrevHas) {
        LbZipRes r;
        uint64_t t0 = GetTickCount64();
        if (LbZipPrev(&r)) Log(L"logs: previous session zipped: %s (%d files, %d KB, %d skipped, %d ms)", r.name, (int32_t)r.files, (int32_t)r.kb,
                               (int32_t)r.skipped, (int32_t)(GetTickCount64() - t0));
        else Log(L"logs: zipping the previous session failed: %s (the files stay in logs\\prev for the next start)", r.why ? r.why : L"?");
    }
    int gone = LzPrune(g_lbDir, L"AC8Survival_", LB_KEEP);
    if (gone) Log(L"logs: %d older zips deleted (%d kept)", (int32_t)gone, (int32_t)LB_KEEP);
    return 0;
}

/* UE4SS.log -> logs\UE4SS.session.log, what was added since the last copy, every 10 s */
static DWORD WINAPI LbUe4ssThread(void* arg)
{
    static wchar_t src[PATH_CAP], dst[PATH_CAP];
    static uint8_t buf[32768];
    (void)arg;
    if (!g_lbDir[0] || !LbJoin(dst, g_lbDir, L"UE4SS.session.log")) return 0;
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
    if (out == INVALID_HANDLE_VALUE) { Log(L"logs: UE4SS.session.log could not be created; UE4SS.log is not copied"); return 0; }
    Log(L"logs: UE4SS.log (%s) is copied to logs\\UE4SS.session.log every 10 s", src);
    int64_t off = 0;
    for (;;) {
        HANDLE in = CreateFileW(src, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (in != INVALID_HANDLE_VALUE) {
            int64_t size = 0;
            if (GetFileSizeEx(in, &size)) {
                if (size < off) {                                /* it got smaller: UE4SS started over */
                    static const char mark[] = "\r\n---- UE4SS.log started over ----\r\n";
                    DWORD put = 0;
                    WriteFile(out, mark, (DWORD)(sizeof(mark) - 1), &put, NULL);
                    off = 0;
                }
                if (size > off && SetFilePointerEx(in, off, NULL, 0)) {
                    for (;;) {
                        DWORD got = 0, put = 0;
                        if (!ReadFile(in, buf, (DWORD)sizeof(buf), &got, NULL) || !got) break;
                        if (!WriteFile(out, buf, got, &put, NULL) || put != got) break;
                        off += got;
                    }
                }
            }
            CloseHandle(in);
        }
        Sleep(10000);
    }
}
