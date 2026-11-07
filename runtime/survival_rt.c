/* =============================================================================
 *  AC8 Survival Mode -- native runtime (UE4SS C++ mod, dlls\main.dll)
 *
 *  Gives Survival Mode its own main-menu entry without taking over any other
 *  mod's files or mission slot:
 *    - The menu row (StringArgs "SurvivalMode", MenuID CampaignFreeMissionDifficulty)
 *      and the mission row (MissionID SURVIVAL_MISSION_ID) are added to the game's
 *      tables at run time by the Lua half of this mod (Scripts\main.lua).
 *    - This DLL does what the game can't be told from data: when that entry was
 *      picked, the difficulty page starts Survival's mission instead of the
 *      free-mission flow, then goes to the hangar.
 *    - SV_* text keys (menu title, help line, mission name) are answered here.
 *
 *  The hooks are the ones AC8 Stonehenge Returns uses (see
 *  tools/re/STONEHENGE_MAIN_DLL.md). Both mods can be installed together:
 *  this one waits until Stonehenge has hooked the game, then chains onto its
 *  hooks instead of replacing them. Every handler here only acts after the
 *  Survival entry was chosen and otherwise calls the next one in the chain.
 *
 *  Plain C, no C runtime, builds with LLVM alone (see build.sh).
 *  One translation unit: survival_rt_game.c, coop.c (coop_lua.c), flight.c (flight_coop2mp.c,
 *  flight_guards.c) and survival_rt_lua.c are #included in place, in that order.
 * ============================================================================= */

#include "win32_min.h"
#include "sigs.h"
#include "uobj.h"                /* (0.32.22: up here for the teardown gate; flight.c's include is then a no-op) */

#define RT_VERSION           L"0.32.24"
#define RT_VERSION_A         "0.32.24"      /* SV_Version()'s: keep in step with RT_VERSION */
#define SURVIVAL_MISSION_ID  9101          /* our row in DT_LiveMissionTable (Stonehenge: 9001) */
#define SURVIVAL_ARGS        L"SurvivalMode" /* StringArgs of our main-menu row               */
#define SURVIVAL_HOST_ARGS   L"SurvivalHost" /* StringArgs of the SURVIVAL CO-OP: HOST row    */
#define SURVIVAL_JOIN_ARGS   L"SurvivalJoin" /* StringArgs of the SURVIVAL CO-OP: JOIN row    */
#define SURVIVAL_MENU_ARGS   L"SurvivalMenu" /* StringArgs of the SURVIVAL MODE row that opens Survival's pages */
/* Hangar level to travel to (ELiveLevelID; 0x0C..0x10 = PL_Hangar001..005). It must be the hangar the mission row's
 * lighting and sublevels belong to, i.e. 10 + the row's TravelHangarMap: Survival's row is Mission 22's, which uses
 * Hangar 04 (TravelHangarMap 5). Hangar 02 with Hangar 004's lighting loads black (test 5).
 * tools/build_survival.py checks the row against this value.                                                     */
#define HANGAR_MENU_ID       0x0F
#define HOLD_MS              5000          /* page transitions swallowed after the start     */
#define STONEHENGE_WAIT_MS   120000        /* longest wait for Stonehenge's hooks            */
#define PATH_CAP             1024
#define EXPORT __declspec(dllexport)

/* vtable slots and object offsets (from Stonehenge's main.dll, same game build) */
#define VT_BASE_SLOT         0xDF
#define VT_DECIDE_SLOT       0xEE
#define VT_NEXT_SLOT         0x111
#define VF_SELECTED_CMD      0xF4          /* widget -> selected command row                 */
#define VF_LIST_POS          0xF3          /* widget -> selected list position (int16)      */
#define VF_WORLD             0x31          /* UObject::GetWorld                              */
#define CMD_STRING_ARGS      0x130         /* FString StringArgs in LiveMenuCommandsDataTable */
#define CMD_STORED_DIFF      0x160         /* byte                                          */
#define WORLD_GAME_INSTANCE  0x1D8
#define GI_CAMPAIGN_CONTEXT  0x8E0
#define CTX_MISSION_ID       0xF38
#define CTX_MODE             0xF60

/* ---- freestanding helpers ---------------------------------------------- */
int   _fltused = 0;              /* the linker wants this marker when floating point is used without a C runtime */
void* memset(void* dst, int c, size_t n);
void* memcpy(void* dst, const void* src, size_t n);
int   memcmp(const void* a, const void* b, size_t n);
void* memset(void* dst, int c, size_t n) { uint8_t* d = dst; while (n--) *d++ = (uint8_t)c; return dst; }
void* memcpy(void* dst, const void* src, size_t n) { uint8_t* d = dst; const uint8_t* s = src; while (n--) *d++ = *s++; return dst; }
int memcmp(const void* a, const void* b, size_t n)
{
    const uint8_t *x = a, *y = b;
    for (; n; --n, ++x, ++y) if (*x != *y) return *x < *y ? -1 : 1;
    return 0;
}

static size_t WLen(const wchar_t* s) { size_t n = 0; while (s[n]) ++n; return n; }

typedef struct { wchar_t* data; int32_t num; int32_t max; } FString;   /* num counts the NUL */

/* ---- log: <mod folder>\AC8SurvivalMode.log ------------------------------ */
static HANDLE           g_hModule;
static HANDLE           g_log = INVALID_HANDLE_VALUE;
static volatile int32_t g_logLock;
static wchar_t          g_modRoot[PATH_CAP];       /* folder that holds dlls\       */
static wchar_t          g_modsDir[PATH_CAP];       /* ue4ss\Mods                    */

#include "vfmt.h"             /* VFmt: Log's and Crumb's formatter (0.32.23: its own header, for tools/checks/vfmt_test) */

static void Log(const wchar_t* fmt, ...)
{
    static wchar_t wide[1024];
    static char    utf8[1024 * 3 + 32];
    if (g_log == INVALID_HANDLE_VALUE) return;
    while (__sync_lock_test_and_set(&g_logLock, 1)) Sleep(0);
    uint16_t st[8];
    GetLocalTime(st);
    wchar_t stamp[32];
    {
        wchar_t* s = stamp;
        int v[3] = { st[4], st[5], st[6] };
        for (int i = 0; i < 3; ++i) { *s++ = (wchar_t)(L'0' + v[i] / 10); *s++ = (wchar_t)(L'0' + v[i] % 10); *s++ = i < 2 ? L':' : L' '; }
        *s = 0;
    }
    va_list ap;
    va_start(ap, fmt);
    VFmt(wide, 1024, fmt, ap);
    va_end(ap);
    int n = WideCharToMultiByte(CP_UTF8, 0, stamp, (int)WLen(stamp), utf8, 32, NULL, NULL);
    int m = WideCharToMultiByte(CP_UTF8, 0, wide, (int)WLen(wide), utf8 + n, (int)sizeof(utf8) - n - 2, NULL, NULL);
    if (m > 0) {
        n += m;
        utf8[n++] = '\r'; utf8[n++] = '\n';
        DWORD put = 0;
        /* (0.32.24, the lag audit of 2026-11-04: testing/2026-11-03/PERF_PLAN.md item 2) no FlushFileBuffers per line: it
         * waited for the disk on the game thread, ~2 ms a line on a tester's SSD (10-30 ms on a hard disk), 50-110 ms at
         * each round start and clear. WriteFile hands the line to Windows' file cache, which keeps it through a crash of
         * the game; only a crash of Windows itself (or a power cut) can lose the last lines. Crumb never flushed. */
        WriteFile(g_log, utf8, (DWORD)n, &put, NULL);
    }
    __sync_lock_release(&g_logLock);
}

static void OpenLog(void)
{
    wchar_t path[PATH_CAP];
    DWORD n = GetModuleFileNameW(g_hModule, g_modRoot, PATH_CAP);
    if (!n || n >= PATH_CAP) return;
    /* ...\Mods\AC8SurvivalMode\dlls\main.dll -> ...\Mods\AC8SurvivalMode */
    for (int cut = 0; cut < 2; ++cut) {
        wchar_t* s = g_modRoot + WLen(g_modRoot);
        while (s > g_modRoot && *s != L'\\' && *s != L'/') --s;
        *s = 0;
    }
    memcpy(g_modsDir, g_modRoot, sizeof(g_modsDir));
    {
        wchar_t* s = g_modsDir + WLen(g_modsDir);
        while (s > g_modsDir && *s != L'\\' && *s != L'/') --s;
        *s = 0;
    }
    size_t k = WLen(g_modRoot);
    if (k + 24 >= PATH_CAP) return;
    memcpy(path, g_modRoot, k * 2);
    memcpy(path + k, L"\\AC8SurvivalMode.log", 21 * 2);
    g_log = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
}

/* ---- crash breadcrumbs: <mod folder>\AC8SurvivalMode_crumbs.log (runtime 0.32.13) -----------------------------------
 * The user, 2026-10-31 (Alyssa's crash could only be traced from its minidump): a short line for each risky thing the
 * runtime and Survival's Lua do (a spawn, a flight recycled and its unit actor destroyed, a player plane destroyed,
 * copies taken down, a removal event, a guard's catch), written to a file of its own at once (WriteFile: the system
 * keeps what was written when the game crashes a moment later), with milliseconds and the thread. The session before is
 * kept as AC8SurvivalMode_crumbs.prev.log (the crashed one, after the restart); CRUMB_MAX lines a session at most. */
#define CRUMB_MAX 20000
static HANDLE           g_crumb = INVALID_HANDLE_VALUE;
static volatile int32_t g_crumbLock;
static int32_t          g_crumbN;

static void OpenCrumbs(void)
{
    static wchar_t path[PATH_CAP], prev[PATH_CAP];           /* (once, at load: off the stack, no stack probe) */
    size_t k = WLen(g_modRoot);
    if (!k || k + 32 >= PATH_CAP) return;
    memcpy(path, g_modRoot, k * 2);
    memcpy(path + k, L"\\AC8SurvivalMode_crumbs.log", 28 * 2);
    memcpy(prev, g_modRoot, k * 2);
    memcpy(prev + k, L"\\AC8SurvivalMode_crumbs.prev.log", 33 * 2);
    BOOL (*moveEx)(const wchar_t*, const wchar_t*, DWORD) =
        (BOOL (*)(const wchar_t*, const wchar_t*, DWORD))GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "MoveFileExW");
    if (moveEx) moveEx(path, prev, 1);                    /* (MOVEFILE_REPLACE_EXISTING; none there: nothing) */
    g_crumb = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
}

static void Crumb(const wchar_t* fmt, ...)
{
    static wchar_t wide[512];
    static char    utf8[512 * 3 + 64];
    if (g_crumb == INVALID_HANDLE_VALUE || g_crumbN >= CRUMB_MAX) return;
    while (__sync_lock_test_and_set(&g_crumbLock, 1)) Sleep(0);
    uint16_t st[8];
    GetLocalTime(st);
    wchar_t stamp[48];
    {
        wchar_t* s = stamp;
        int v[3] = { st[4], st[5], st[6] };
        for (int i = 0; i < 3; ++i) { *s++ = (wchar_t)(L'0' + v[i] / 10); *s++ = (wchar_t)(L'0' + v[i] % 10); *s++ = i < 2 ? L':' : L'.'; }
        *s++ = (wchar_t)(L'0' + st[7] / 100); *s++ = (wchar_t)(L'0' + st[7] / 10 % 10); *s++ = (wchar_t)(L'0' + st[7] % 10);
        *s++ = L' '; *s++ = L't';
        DWORD tid = GetCurrentThreadId();
        wchar_t digits[12]; int nd = 0;
        do { digits[nd++] = (wchar_t)(L'0' + tid % 10); tid /= 10; } while (tid && nd < 11);
        while (nd) *s++ = digits[--nd];
        *s++ = L' ';
        *s = 0;
    }
    va_list ap;
    va_start(ap, fmt);
    VFmt(wide, 512, fmt, ap);
    va_end(ap);
    int n = WideCharToMultiByte(CP_UTF8, 0, stamp, (int)WLen(stamp), utf8, 64, NULL, NULL);
    int m = WideCharToMultiByte(CP_UTF8, 0, wide, (int)WLen(wide), utf8 + n, (int)sizeof(utf8) - n - 2, NULL, NULL);
    if (m > 0) {
        n += m;
        utf8[n++] = '\r'; utf8[n++] = '\n';
        DWORD put = 0;
        WriteFile(g_crumb, utf8, (DWORD)n, &put, NULL);
        if (++g_crumbN == CRUMB_MAX) {
            static const char full[] = "(20000 lines: no more this session)\r\n";
            WriteFile(g_crumb, full, (DWORD)(sizeof(full) - 1), &put, NULL);
        }
    }
    __sync_lock_release(&g_crumbLock);
}

static int FileExists(const wchar_t* dir, const wchar_t* rel)
{
    wchar_t p[PATH_CAP];
    size_t a = WLen(dir), b = WLen(rel);
    if (a + b + 2 >= PATH_CAP) return 0;
    memcpy(p, dir, a * 2); p[a] = L'\\'; memcpy(p + a + 1, rel, (b + 1) * 2);
    return GetFileAttributesW(p) != INVALID_FILE_ATTRIBUTES;
}

/* ---- memory checks ------------------------------------------------------ */
static int Readable(const void* p, size_t n)
{
    MEMORY_BASIC_INFORMATION mi;
    if (!p || !VirtualQuery(p, &mi, sizeof(mi))) return 0;
    if (mi.State != MEM_COMMIT || (mi.Protect & (PAGE_NOACCESS | PAGE_GUARD))) return 0;
    return (const uint8_t*)p + n <= (const uint8_t*)mi.BaseAddress + mi.RegionSize;
}

/* ... and writable (a game function about to write there: flight.c FwWeaponOk) */
static int Writable(const void* p, size_t n)
{
    MEMORY_BASIC_INFORMATION mi;
    if (!p || !VirtualQuery(p, &mi, sizeof(mi))) return 0;
    if (mi.State != MEM_COMMIT || (mi.Protect & (PAGE_NOACCESS | PAGE_GUARD))) return 0;
    if (!(mi.Protect & (PAGE_READWRITE | 0x08 | PAGE_EXECUTE_READWRITE | 0x80))) return 0;   /* (0x08 PAGE_WRITECOPY, 0x80 PAGE_EXECUTE_WRITECOPY) */
    return (const uint8_t*)p + n <= (const uint8_t*)mi.BaseAddress + mi.RegionSize;
}

static uint8_t* g_exe;            /* game image */
static volatile int32_t g_scanned; /* FindFunctions (Worker thread) has set every g_f* pointer */
static size_t   g_exeSize;

static int InGame(const void* p)
{
    return (const uint8_t*)p >= g_exe && (const uint8_t*)p < g_exe + g_exeSize;
}

/* ---- game image sections ----------------------------------------------- */
typedef struct { uint8_t* start; size_t len; uint32_t ch; } Section;
static Section g_sec[64];
static int     g_nsec;

static int ReadImage(void)
{
    g_exe = (uint8_t*)GetModuleHandleW(NULL);
    if (!g_exe) return 0;
    uint32_t pe = *(uint32_t*)(g_exe + 0x3C);
    uint16_t nsec = *(uint16_t*)(g_exe + pe + 6), optsz = *(uint16_t*)(g_exe + pe + 20);
    g_exeSize = *(uint32_t*)(g_exe + pe + 24 + 56);
    uint8_t* sh = g_exe + pe + 24 + optsz;
    for (int i = 0; i < nsec && g_nsec < 64; ++i, sh += 40) {
        uint32_t vsize = *(uint32_t*)(sh + 8), va = *(uint32_t*)(sh + 12), ch = *(uint32_t*)(sh + 36);
        g_sec[g_nsec++] = (Section){ g_exe + va, vsize, ch };
    }
    return 1;
}

/* Walk the committed, readable regions of [start, start+len). */
typedef void (*RegionFn)(uint8_t* p, size_t n, void* ctx);
static void ForRegions(uint8_t* start, size_t len, RegionFn fn, void* ctx)
{
    uint8_t* end = start + len;
    for (uint8_t* p = start; p < end; ) {
        MEMORY_BASIC_INFORMATION mi;
        if (!VirtualQuery(p, &mi, sizeof(mi))) return;
        uint8_t* rend = (uint8_t*)mi.BaseAddress + mi.RegionSize;
        if (rend > end) rend = end;
        if (rend <= p) return;
        if (mi.State == MEM_COMMIT && !(mi.Protect & (PAGE_NOACCESS | PAGE_GUARD))) fn(p, (size_t)(rend - p), ctx);
        p = rend;
    }
}

/* A byte pattern; mask[i] == 0 is a wildcard. A pattern only counts when it occurs exactly once. */
typedef struct { const uint8_t* b; const uint8_t* mask; size_t n; uint8_t* hit; int count; } Pattern;
typedef struct { Pattern* pats; int npat; } ScanCtx;

static void ScanRegion(uint8_t* p, size_t n, void* vctx)
{
    ScanCtx* c = (ScanCtx*)vctx;
    uint8_t* end = p + n;
    for (; p < end; ++p) {
        for (int k = 0; k < c->npat; ++k) {
            Pattern* t = &c->pats[k];
            if (p + t->n > end || p[0] != t->b[0] || p[1] != t->b[1]) continue;
            size_t i = 2;
            for (; i < t->n; ++i) if ((!t->mask || t->mask[i]) && p[i] != t->b[i]) break;
            if (i == t->n) { if (!t->hit) t->hit = p; ++t->count; }
        }
    }
}

/* One pass over the game's executable sections for every pattern. */
static void ScanCode(Pattern* pats, int npat)
{
    ScanCtx c = { pats, npat };
    for (int k = 0; k < npat; ++k) { pats[k].hit = NULL; pats[k].count = 0; }
    for (int s = 0; s < g_nsec; ++s)
        if (g_sec[s].ch & IMAGE_SCN_MEM_EXECUTE) ForRegions(g_sec[s].start, g_sec[s].len, ScanRegion, &c);
    for (int k = 0; k < npat; ++k) if (pats[k].count != 1) pats[k].hit = NULL;
}

/* A prologue that another mod replaced with "jmp [rip+0]; dq target; nop..." followed by the original
 * bytes after it. The first two bytes are fixed, as ScanRegion requires.                                */
static void HookedPattern(uint8_t* pat, uint8_t* mask, size_t prologue, const uint8_t* tail, size_t tailLen)
{
    memset(mask, 1, prologue + tailLen);
    pat[0] = 0xFF; pat[1] = 0x25; pat[2] = pat[3] = pat[4] = pat[5] = 0;
    for (int i = 6; i < 14; ++i) { pat[i] = 0; mask[i] = 0; }
    for (size_t i = 14; i < prologue; ++i) pat[i] = 0x90;
    memcpy(pat + prologue, tail, tailLen);
}

static int IsJump(const uint8_t* f)
{
    return f && f[0] == 0xFF && f[1] == 0x25 && !f[2] && !f[3] && !f[4] && !f[5];
}

/* ---- code patching (other threads held off the patched bytes) ------------ */
#define MAX_THREADS 1024
static HANDLE s_threads[MAX_THREADS];
static int    s_threadCount;

static void Thaw(void)
{
    for (int i = 0; i < s_threadCount; ++i) { ResumeThread(s_threads[i]); CloseHandle(s_threads[i]); }
    s_threadCount = 0;
}

static int Freeze(const uint8_t* lo, size_t len)
{
    static DWORD ids[MAX_THREADS];
    DWORD pid = GetCurrentProcessId(), tid = GetCurrentThreadId();
    for (int attempt = 0; attempt < 100; ++attempt) {
        int count = 0;
        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
        if (snap == INVALID_HANDLE_VALUE) return 0;
        THREADENTRY32 te; memset(&te, 0, sizeof(te)); te.dwSize = sizeof(te);
        if (Thread32First(snap, &te)) {
            do {
                if (te.th32OwnerProcessID == pid && te.th32ThreadID != tid && count < MAX_THREADS)
                    ids[count++] = te.th32ThreadID;
                te.dwSize = sizeof(te);
            } while (Thread32Next(snap, &te));
        }
        CloseHandle(snap);
        s_threadCount = 0;
        for (int i = 0; i < count; ++i) {
            HANDLE th = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, 0, ids[i]);
            if (!th) continue;
            if (SuspendThread(th) == 0xFFFFFFFFu) { CloseHandle(th); continue; }
            s_threads[s_threadCount++] = th;
        }
        int busy = 0;
        for (int i = 0; i < s_threadCount; ++i) {
            CONTEXT64 c; c.ContextFlags = CONTEXT_CONTROL; c.Rip = 0;
            if (GetThreadContext(s_threads[i], &c)) {
                const uint8_t* rip = (const uint8_t*)(uintptr_t)c.Rip;
                if (rip >= lo && rip < lo + len) busy = 1;
            }
        }
        if (!busy) return 1;
        Thaw();
        Sleep(1);
    }
    return 0;
}

static int WriteMem(void* addr, const void* bytes, size_t len, int freeze)
{
    DWORD old = 0, ignored = 0; int ok = 0;
    if (freeze && !Freeze(addr, len)) return 0;
    if (VirtualProtect(addr, len, PAGE_EXECUTE_READWRITE, &old)) {
        memcpy(addr, bytes, len);
        VirtualProtect(addr, len, old, &ignored);
        FlushInstructionCache(GetCurrentProcess(), addr, len);
        ok = 1;
    }
    if (freeze) Thaw();
    return ok;
}

static void PutAbsJump(uint8_t* at, const void* target)    /* 14 bytes */
{
    uint64_t t = (uint64_t)(uintptr_t)target;
    at[0] = 0xFF; at[1] = 0x25; at[2] = at[3] = at[4] = at[5] = 0;
    memcpy(at + 6, &t, 8);
}

/* Inline hook. If the function already starts with another mod's "jmp [rip+0]", chain onto it:
 * our detour goes into that jump and the previous target becomes our "original".               */
static int HookInline(uint8_t* fn, size_t prologue, void* detour, void** orig, const wchar_t* what)
{
    if (IsJump(fn)) {
        void* prev; memcpy(&prev, fn + 6, 8);
        *orig = prev;
        if (!WriteMem(fn + 6, &detour, 8, 1)) { *orig = NULL; return 0; }
        Log(L"%s: chained onto another mod's hook at %p (next: %p)", what, fn, prev);
        return 1;
    }
    uint8_t* tramp = (uint8_t*)VirtualAlloc(NULL, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!tramp) return 0;
    memcpy(tramp, fn, prologue);
    PutAbsJump(tramp + prologue, fn + prologue);
    DWORD ignored;
    VirtualProtect(tramp, 64, PAGE_EXECUTE_READ, &ignored);
    FlushInstructionCache(GetCurrentProcess(), tramp, 64);
    *orig = tramp;
    uint8_t patch[32];
    PutAbsJump(patch, detour);
    for (size_t i = 14; i < prologue; ++i) patch[i] = 0x90;
    if (!WriteMem(fn, patch, prologue, 1)) { *orig = NULL; return 0; }
    Log(L"%s: hooked at %p", what, fn);
    return 1;
}

static int HookSlot(void** slot, void* detour, void** orig, const wchar_t* what)
{
    *orig = *slot;
    if (!WriteMem(slot, &detour, 8, 0)) { *orig = NULL; return 0; }
    Log(L"%s: vtable slot %p, next %p%s", what, slot, *orig, InGame(*orig) ? L"" : L" (another mod's handler)");
    return 1;
}

/* ---- game functions and state ------------------------------------------ */
typedef uintptr_t (*Fn1)(void* self);
typedef uintptr_t (*Fn2)(void* self, uintptr_t a);
typedef uintptr_t (*Fn4)(void* a, uintptr_t b, void* c, void* d);

static uint8_t* g_fBase;
static uint8_t* g_fMainDecide;
static uint8_t* g_fDiffDecide;
static uint8_t* g_fDiffNext;
static Fn2      g_gotoMenu;
static Fn2      g_setDifficulty;
static uint8_t* g_fTransition;
static uint8_t* g_fText;

static void**   g_vtA;                 /* main menu widget        */
static void**   g_vtB;                 /* difficulty page         */

static Fn1      g_nextMainDecide;
static Fn1      g_nextDiffDecide;
static Fn2      g_nextDiffNext;
static Fn2      g_nextTransition;
static Fn4      g_nextText;

static volatile int32_t  g_chosen;     /* the Survival entry was picked on the main menu */
static volatile int32_t  g_savedMode = -1;
static volatile int32_t  g_menuChoice;  /* the last main-menu entry picked: 0 none yet or another entry, 1 SURVIVAL MODE,
                                          * 2 SP OFFLINE, 3 CO-OP: HOST, 4 CO-OP: JOIN, 5 SP ONLINE, 6 Survival's pages
                                          * opened (settings and page rows leave it) */
static volatile int32_t  g_pagesOk;     /* Lua found Survival's pages in the game's page list (SV_MenuPages)   */
/* Survival's pages open through CAMPAIGN TRAINING's page (user, 2026-10-29: "feel free to use the Campaign Training and
 * replace it completely"): the main menu opens a row's page by ELiveMenuMainIDs, the game's fixed list of its pages
 * (GameTitle ... CampaignTraining), so pages of our own names never opened (test of 2026-10-29: SURVIVAL MODE pressed 25
 * times, nothing). Survival's page rows name CampaignTraining; Lua hands over the pages' classes (SV_MenuClass) and that
 * page's entry in the main menu manager's MenuWidgetClassList (SV_MenuSlot), and OnMainDecide points the entry at the
 * page each press opens. The game doesn't open the page it's on (test of 2026-10-29, runtime 0.28.0: SP OFFLINE / ONLINE /
 * COOP HOST on the modes page, all CampaignTraining, did nothing), so the setup pages go through a second page the
 * game never shows on PC, the PS5 DualSense first-start setup (InitialSetting_DualSence), whose own class comes back
 * as soon as any other main-menu entry is picked: modes and MORE RULES on slot 0, the setup pages on slot 1.
 * A page already open under the one shown isn't opened again either: the game goes back to it (test of 2026-10-29,
 * 0.28.1: MORE RULES, on CampaignTraining under the modes page, went back there), so MORE RULES has a third, the
 * first-start Accessibility setup (InitialSetting_Accessibility, put back as slot 1's is). */
#define MENU_PAGE_N 5
static const wchar_t* const kPageNames[MENU_PAGE_N] = { L"Modes", L"Offline", L"Online", L"Host", L"Rules" };  /* sv_menu.lua PAGES */
#define MENU_SLOT_N 3
static const int kPageSlotOf[MENU_PAGE_N] = { 0, 1, 1, 1, 2 };   /* tools/build_survival.py page_menu_id */
static const wchar_t* const kSlotIds[MENU_SLOT_N] = { L"CampaignTraining", L"InitialSetting_DualSence", L"InitialSetting_Accessibility" };
static uint8_t* volatile  g_pageClass[MENU_PAGE_N];
static uint8_t** volatile g_pageSlot[MENU_SLOT_N];   /* &MenuWidgetClassList[kSlotIds[n]].MenuClass              */
static uint8_t* volatile  g_slotStock[MENU_SLOT_N];  /* what each held (slots 1 and 2 go back after Survival's pages) */
static volatile int32_t  g_quickMode = 2; /* the mode QUICK START plays (SV_MenuQuick): 2, 3 or 5              */
static volatile int32_t  g_menuPicks;   /* how many main-menu entries were picked: Lua sees the same entry picked again */
static void* volatile    g_page;       /* difficulty page seen while chosen               */
static void* volatile    g_holdPage;
static volatile uint64_t g_holdUntil;

static void* VCall(void* obj, int slot)
{
    if (!Readable(obj, 8)) return NULL;
    void** vt = *(void***)obj;
    if (!Readable(vt + slot, 8)) return NULL;
    return (void*)((Fn1)vt[slot])(obj);
}

static int IsPage(void* obj)
{
    return g_vtB && Readable(obj, 8) && *(void***)obj == g_vtB;
}

/* UE4SS: void UObjectGlobals::FindAllOf(const wchar_t* class_name, std::vector<UObject*>& out) */
typedef struct { void** first; void** last; void** end; } PtrVector;       /* MSVC std::vector<T*> */
typedef void (*FindAllOfFn)(const wchar_t* className, PtrVector* out);
static FindAllOfFn g_findAllOf;

static void FreeVector(PtrVector* v)
{
    if (!v->first) return;
    size_t bytes = (size_t)((uint8_t*)v->end - (uint8_t*)v->first);
    void* block = v->first;
    if (bytes >= 4096) block = ((void**)v->first)[-1];   /* MSVC's big-allocation alignment */
    free(block);
    v->first = v->last = v->end = NULL;
}

/* The live difficulty page: `obj` itself, or the one instance of the page class that uses its vtable
 * (the class default object skipped), found the way Stonehenge finds it. */
static void* FindPage(void* obj)
{
    if (IsPage(obj)) return obj;
    if (!g_findAllOf) {
        HANDLE ue4ss = GetModuleHandleW(L"UE4SS.dll");
        if (ue4ss) g_findAllOf = (FindAllOfFn)GetProcAddress(ue4ss,
            "?FindAllOf@UObjectGlobals@Unreal@RC@@YAXPEB_WAEAV?$vector@PEAVUObject@Unreal@RC@@V?$allocator@PEAVUObject@Unreal@RC@@@std@@@std@@@Z");
        if (!g_findAllOf) { Log(L"UE4SS FindAllOf not found; the difficulty page can't be looked up"); return NULL; }
    }
    static const wchar_t* const kPageClasses[] = { L"LiveMenuCampaignFreeMissionDifficultyWidget", L"WBP_Menu_FreeMissionDifficulty_000_C" };
    void* page = NULL;
    for (size_t c = 0; c < 2 && !page; ++c) {
        PtrVector v = { NULL, NULL, NULL };
        g_findAllOf(kPageClasses[c], &v);
        for (void** p = v.first; p && p < v.last; ++p) {
            uint8_t* o = (uint8_t*)*p;
            if (!IsPage(o) || !Readable(o + 8, 4)) continue;
            if (*(uint32_t*)(o + 8) & 0x10) continue;          /* RF_ClassDefaultObject */
            page = o;
            break;
        }
        FreeVector(&v);
    }
    return page;
}

static const FString* SelectedArgs(void* widget, void** cmdOut)
{
    void* cmd = VCall(widget, VF_SELECTED_CMD);
    if (cmdOut) *cmdOut = cmd;
    if (!cmd || !Readable((uint8_t*)cmd + CMD_STRING_ARGS, sizeof(FString))) return NULL;
    const FString* s = (const FString*)((uint8_t*)cmd + CMD_STRING_ARGS);
    if (!s->data || s->num < 1 || !Readable(s->data, (size_t)s->num * 2)) return NULL;
    return s;
}

static int ArgsEqual(const FString* s, const wchar_t* text)
{
    size_t n = WLen(text);
    return s && (size_t)s->num == n + 1 && memcmp(s->data, text, n * 2) == 0;
}

static uint8_t* Context(void* obj)
{
    uint8_t* world = (uint8_t*)VCall(obj, VF_WORLD);
    if (!world || !Readable(world + WORLD_GAME_INSTANCE, 8)) return NULL;
    uint8_t* gi = *(uint8_t**)(world + WORLD_GAME_INSTANCE);
    if (!gi || !Readable(gi + GI_CAMPAIGN_CONTEXT, 8)) return NULL;
    uint8_t* ctx = *(uint8_t**)(gi + GI_CAMPAIGN_CONTEXT);
    if (!ctx || !Readable(ctx + CTX_MISSION_ID, 4) || !Readable(ctx + CTX_MODE, 1)) return NULL;
    return ctx;
}

static const wchar_t* const kDiffNames[5] = { L"Casual", L"Easy", L"Normal", L"Hard", L"Ace" };

/* 1..5, or 0 if it can't be told (same three ways Stonehenge uses). */
static int Difficulty(void* page)
{
    void* cmd = NULL;
    const FString* a = SelectedArgs(page, &cmd);
    for (int i = 0; i < 5; ++i) if (ArgsEqual(a, kDiffNames[i])) return i + 1;
    if (cmd && Readable((uint8_t*)cmd + CMD_STORED_DIFF, 1)) {
        int v = *((uint8_t*)cmd + CMD_STORED_DIFF);
        if (v >= 1 && v <= 5) return v;
    }
    int pos = (int16_t)(uintptr_t)VCall(page, VF_LIST_POS);
    return pos >= 0 && pos <= 4 ? pos + 1 : 0;
}

/* page: the difficulty page; from: the object whose transitions are held back for HOLD_MS afterwards */
static int StartSurvival(void* page, void* from, const wchar_t* why)
{
    g_chosen = 0;
    /* The game's difficulty page applies the chosen difficulty itself when it's confirmed. Only a difficulty read
     * from the selected entry's own name is trusted to set it again: the stored-byte and list-position fallbacks
     * read Casual by the time the next-menu hook runs, and forcing that turned every run into Rookie (test M2). */
    int d = 0;
    {
        const FString* a = SelectedArgs(page, NULL);
        for (int i = 0; i < 5; ++i) if (ArgsEqual(a, kDiffNames[i])) d = i + 1;
    }
    if (d) g_setDifficulty(page, (uintptr_t)(uint8_t)d);
    else Log(L"start: keeping the difficulty the game's page applied (fallback reading would be %s)",
             Difficulty(page) ? kDiffNames[Difficulty(page) - 1] : L"none");
    uint8_t* ctx = Context(page);
    if (ctx) {
        int mode = g_savedMode >= 0 ? g_savedMode : ctx[CTX_MODE];
        Log(L"start (%s): difficulty set %s, context mode %d -> %d, mission %d -> %d", why,
            d ? kDiffNames[d - 1] : L"by the game (unchanged)", (int32_t)ctx[CTX_MODE], (int32_t)mode,
            *(int32_t*)(ctx + CTX_MISSION_ID), (int32_t)SURVIVAL_MISSION_ID);
        ctx[CTX_MODE] = (uint8_t)mode;
        *(int32_t*)(ctx + CTX_MISSION_ID) = SURVIVAL_MISSION_ID;
    } else {
        Log(L"start (%s): campaign context not found; the game's mission choice is unchanged", why);
    }
    g_gotoMenu(page, HANGAR_MENU_ID);
    g_holdPage  = from;
    g_holdUntil = GetTickCount64() + HOLD_MS;
    Log(L"start: going to the hangar (menu %x)", (uint32_t)HANGAR_MENU_ID);
    return 1;
}

/* Survival's own main-menu pages (Scripts/sv_menu.lua, tools/build_survival.py MENU_PAGES; runtime 0.27.0) are copies of
 * the game's main-menu page, so their rows come through OnMainDecide too. Their StringArgs:
 *   SurvivalMenu     the main menu's SURVIVAL MODE: its MenuID opens the modes page, once Lua found Survival's pages in
 *                    the game's page list (SV_MenuPages); before that it's refused, never a page that isn't there
 *   SV_Mode_<mode>   a mode on the modes page: Offline / Online / Host open their setup page (the row's MenuID); Join
 *                    opens the difficulty page, which starts Survival as SURVIVAL MODE always has
 *   SV_Go_<mode>     a setup page's START RUN: the difficulty page, then Survival
 *   SV_Quick         QUICK START: the same, with the mode Lua named (SV_MenuQuick)
 *   SV_Page_<page>   a row that opens another of Survival's pages (MORE RULES)
 *   SV_Set_<what>    a setting (below)                                                                              */
static const struct { const wchar_t* name; int32_t code; } kModes[] = {
    { L"Offline", 2 }, { L"Host", 3 }, { L"Join", 4 }, { L"Online", 5 },
};
static const wchar_t* ModeName(int32_t code)
{
    switch (code) {
    case 1: return L"Survival Mode"; case 2: return L"SP Offline"; case 3: return L"Co-op: Host";
    case 4: return L"Co-op: Join";   case 5: return L"SP Online";  case 6: return L"Survival's pages";
    default: return L"?";
    }
}

/* the number of characters of `prefix` when s starts with it (and has more after it), else 0 */
static size_t ArgsPrefix(const FString* s, const wchar_t* prefix)
{
    size_t n = WLen(prefix);
    return s && s->data && (size_t)s->num > n + 1 && !memcmp(s->data, prefix, n * 2) ? n : 0;
}

/* the mode named after `skip` characters of s (kModes), or 0 */
static int32_t ModeCode(const FString* s, size_t skip)
{
    for (size_t i = 0; i < sizeof(kModes) / sizeof(kModes[0]); ++i) {
        size_t n = WLen(kModes[i].name);
        if ((size_t)s->num == skip + n + 1 && !memcmp(s->data + skip, kModes[i].name, n * 2)) return kModes[i].code;
    }
    return 0;
}

/* The main menu's settings rows (StringArgs "SV_Set_<what>", Survival COOP's build; Scripts/sv_coop.lua): a pick waits
 * for Lua (SV_MenuSetting), which changes the setting and the row's text; the decide is taken here, so the menu stays
 * where it is (as the landing menu's shop rows, OnHangarDecide). */
#define SET_QUEUE 8
static wchar_t  g_setQueue[SET_QUEUE][32];          /* both ends run on the game thread */
static int32_t  g_setHead, g_setCount;

/* ---- handlers ----------------------------------------------------------- */
static uintptr_t OnMainDecide(void* widget)
{
    const FString* a = SelectedArgs(widget, NULL);
    /* Survival's own settings rows only: taken here, not passed on (the stock decide would open their page). Every
     * other row still goes down the chain (Stonehenge's hooks too), as the landing menu's SV_Buy_ rows do. */
    if (a && a->data && a->num > 8 && a->num <= 32 && !memcmp(a->data, L"SV_Set_", 7 * 2)) {
        g_chosen = 0;                                  /* (not a start: should the menu move on anyway, no Survival) */
        if (g_setCount < SET_QUEUE) {
            wchar_t* q = g_setQueue[(g_setHead + g_setCount++) % SET_QUEUE];
            memcpy(q, a->data, (size_t)a->num * 2);
            q[a->num - 1] = 0;
            Log(L"main menu: setting %s picked", q);
        }
        return 1;
    }
    /* Survival's pages: which mode, and whether this row starts the run (the difficulty page it opens starts Survival) */
    int32_t code = 0, start = 0;
    int page = 0;                                      /* a row of Survival's pages (or the one that opens them) */
    size_t k;
    if (ArgsEqual(a, SURVIVAL_MENU_ARGS)) {
        if (!g_pagesOk) {
            Log(L"main menu: SURVIVAL MODE (pages) picked, but Survival's pages aren't in the game's page list; refused");
            return 1;
        }
        page = 1, code = 6;
    } else if ((k = ArgsPrefix(a, L"SV_Mode_")) != 0) {
        page = 1, code = ModeCode(a, k), start = code == 4;
    } else if ((k = ArgsPrefix(a, L"SV_Go_")) != 0) {
        page = 1, code = ModeCode(a, k), start = code != 0;
    } else if (ArgsEqual(a, L"SV_Quick")) {
        page = 1, code = g_quickMode, start = 1;
    } else if (ArgsPrefix(a, L"SV_Page_") || ArgsEqual(a, L"SV_Back")) {
        page = 1;                                      /* (another of Survival's pages, or BACK to the one under it) */
    }
    if (page) {
        /* the page this press opens: SURVIVAL MODE the modes, SV_Mode_<mode> its setup (not Join: a start), SV_Page_<page> */
        int target = -1;
        if (ArgsEqual(a, SURVIVAL_MENU_ARGS)) target = 0;
        else if (ArgsPrefix(a, L"SV_Mode_")) target = code == 2 ? 1 : code == 5 ? 2 : code == 3 ? 3 : -1;
        else if ((k = ArgsPrefix(a, L"SV_Page_")) != 0) {
            for (int i = 0; i < MENU_PAGE_N; ++i) {
                size_t n = WLen(kPageNames[i]);
                if ((size_t)a->num == k + n + 1 && !memcmp(a->data + k, kPageNames[i], n * 2)) target = i;
            }
        }
        if (target >= 0) {
            uint8_t** slot = g_pageSlot[kPageSlotOf[target]];
            uint8_t* cls = g_pageClass[target];
            if (!slot || !cls || !Readable(slot, 8)) {
                Log(L"main menu: Survival's page row '%s': its page (%s) can't open (no %s entry or class); refused",
                    a->data, kPageNames[target], kSlotIds[kPageSlotOf[target]]);
                return 1;
            }
            *slot = cls;
        }
        g_chosen = start;
        if (start) {
            uint8_t* ctx = Context(widget);
            g_savedMode = ctx ? ctx[CTX_MODE] : -1;
            g_page = NULL;
        }
        if (code) { g_menuChoice = code; ++g_menuPicks; }
        Log(L"main menu: Survival's page row '%s': %s%s", a->data, code ? ModeName(code) : L"no mode",
            start ? L", opening the difficulty select to start" : L"");
        return g_nextMainDecide(widget);
    }
    for (int i = 1; i < MENU_SLOT_N; ++i) {            /* (not one of Survival's pages: the borrowed first-start pages back) */
        uint8_t** slot = g_pageSlot[i];
        if (slot && g_slotStock[i] && Readable(slot, 8) && *slot != g_slotStock[i]) *slot = g_slotStock[i];
    }
    int coop = ArgsEqual(a, SURVIVAL_HOST_ARGS) ? 3 : ArgsEqual(a, SURVIVAL_JOIN_ARGS) ? 4 : 0;
    int mine = coop || ArgsEqual(a, SURVIVAL_ARGS);
    g_chosen = mine;
    if (mine) {
        uint8_t* ctx = Context(widget);
        g_savedMode = ctx ? ctx[CTX_MODE] : -1;
        g_page = NULL;
        g_menuChoice = coop ? coop : 1;
        Log(L"main menu: %s chosen, opening the difficulty select (context mode %d)",
            coop == 3 ? L"Survival Co-op: Host" : coop == 4 ? L"Survival Co-op: Join" : L"Survival Mode", (int32_t)g_savedMode);
    } else {
        g_menuChoice = 0;                               /* another entry: co-op closes (code review of 2026-10-26: it
                                                         * stayed open into stock missions) */
    }
    ++g_menuPicks;
    return g_nextMainDecide(widget);
}

static uintptr_t OnDiffDecide(void* page)
{
    if (g_chosen && Difficulty(page) && StartSurvival(page, page, L"decide")) return 1;
    return g_nextDiffDecide(page);
}

/* vtable B slot 0x111: FName* GetNextMenu(page, FName* out). Confirming a difficulty runs menu transition 7, which
 * asks the page for its next menu; the stock page answers "CampaignFreeMission" (test 3/4: that's the fall-through).
 * When Survival was chosen this is where it starts: `page` is the difficulty page itself, so nothing has to be
 * looked up. The answer is an empty name, so the menu stays put while the hangar level loads instead of opening the
 * Free Mission list on top of it.                                                                                   */
typedef struct { uint32_t index; uint32_t number; } FNameRaw;

static uintptr_t OnDiffNext(void* page, uintptr_t arg)
{
    if (!g_chosen) return g_nextDiffNext(page, arg);
    Log(L"difficulty page: next menu asked while Survival is chosen: going to the hangar instead of Free Mission");
    g_page = page;
    StartSurvival(page, page, L"next menu");
    FNameRaw* out = (FNameRaw*)arg;
    if (out && Readable(out, sizeof(*out))) { out->index = 0; out->number = 0; }   /* NAME_None */
    return arg;
}

static uintptr_t OnTransition(void* obj, uintptr_t id)
{
    int32_t t = (int32_t)id;
    /* Confirming a difficulty arrives here as transition 7 from another menu object (the page's own decide
     * doesn't run), or as 10 from the page itself; Stonehenge treats both the same way. */
    if (g_chosen && (t == 7 || (t == 10 && IsPage(obj)))) {
        void* page = FindPage(obj);
        if (!page && IsPage(g_page)) page = g_page;
        if (page) {
            Log(L"menu transition %d (%s): starting Survival from the difficulty page %p", t,
                page == obj ? L"from the page" : L"from another menu object", page);
            StartSurvival(page, obj, L"transition");
            return 0;
        }
        Log(L"menu transition %d while Survival is chosen, but no difficulty page was found; passed on", t);
    }
    if (obj && obj == g_holdPage && GetTickCount64() < g_holdUntil) {
        Log(L"menu transition %d held back while the mission loads", t);
        return 0;
    }
    return g_nextTransition(obj, id);
}

/* text */
typedef struct { const wchar_t* key; const wchar_t* text; FString fs; } TextRow;
static TextRow g_text[] = {
    { L"SV_Menu_Title",        L"SURVIVAL MODE", { 0 } },
    { L"SV_Menu_Help",         L"Hold Comona Island against endless waves. Land between rounds to rearm and repair.", { 0 } },
    { L"SV_Menu_CoopHostTitle", L"SURVIVAL CO-OP: HOST", { 0 } },
    { L"SV_Menu_CoopHostHelp",  L"Host Survival Mode for your Steam friends (CO-OP ROOM: how many). They pick "
                                L"SURVIVAL CO-OP: JOIN and fly with you.", { 0 } },
    { L"SV_Menu_CoopJoinTitle", L"SURVIVAL CO-OP: JOIN", { 0 } },
    { L"SV_Menu_CoopJoinHelp",  L"Join a Steam friend who picked SURVIVAL CO-OP: HOST, and fly their run with them.", { 0 } },
    /* Survival's pages (Scripts/sv_menu.lua sets them all, with the settings' values; these show without Lua) */
    { L"SV_Pg_Modes_Title",    L"SURVIVAL MODE", { 0 } },
    { L"SV_Pg_Modes_Offline",  L"SURVIVAL MODE SP OFFLINE", { 0 } },
    { L"SV_Pg_Modes_Online",   L"SURVIVAL MODE SP ONLINE", { 0 } },
    { L"SV_Pg_Modes_Host",     L"SURVIVAL MODE COOP HOST", { 0 } },
    { L"SV_Pg_Modes_Join",     L"SURVIVAL MODE COOP JOIN", { 0 } },
    { L"SV_Pg_Modes_Quick",    L"QUICK START", { 0 } },
    { L"SV_Pg_Offline_Title",  L"SURVIVAL MODE SP OFFLINE", { 0 } },
    { L"SV_Pg_Online_Title",   L"SURVIVAL MODE SP ONLINE", { 0 } },
    { L"SV_Pg_Host_Title",     L"SURVIVAL MODE COOP HOST", { 0 } },
    { L"SV_Pg_Rules_Title",    L"MORE RULES", { 0 } },
    { L"SV_Pg_Offline_Go",     L"START RUN", { 0 } },
    { L"SV_Pg_Online_Go",      L"START RUN", { 0 } },
    { L"SV_Pg_Host_Go",        L"START RUN", { 0 } },
    { L"SV_Pg_Offline_Rules",  L"MORE RULES", { 0 } },
    { L"SV_Pg_Online_Rules",   L"MORE RULES", { 0 } },
    { L"SV_Pg_Host_Rules",     L"MORE RULES", { 0 } },
    { L"SV_Mission_Name",      L"Survival Mode", { 0 } },
    { L"SV_Mission_Subtitle",  L"Comona Island", { 0 } },
    { L"SV_Mission_Number",    L"SURVIVAL", { 0 } },
    { L"SV_Mission_Location",  L"Comona Island", { 0 } },
    { L"SV_Mission_Objective", L"Survive as many rounds as you can. Protect the airfield.", { 0 } },
    { L"SV_Mission_Briefing",  L"Enemy waves grow every round, with a special attack every fifth. "
                               L"Earn zollars for kills and spend them at Comona Airport between rounds.", { 0 } },
};

static void InitText(void)
{
    for (size_t i = 0; i < sizeof(g_text) / sizeof(g_text[0]); ++i) {
        int32_t n = (int32_t)WLen(g_text[i].text) + 1;
        g_text[i].fs = (FString){ (wchar_t*)g_text[i].text, n, n };
    }
}

/* Texts Lua sets at run time (SV_SetText: the shop's rows and prices, the shuttle's and the aces' names). Fixed
 * buffers, rewritten in place on the game thread, so an FString the game was handed never points at freed memory. */
#define DYN_TEXTS 320          /* used (0.70.0): the STORE ~65 (21 items, its 5 pages, 4 landing rows), shuttle 1, aces and squadrons ~23, allies 4; co-op names 24 (0.24.0); Survival's pages 65 (0.27.0) */
#define DYN_KEY   48
#define DYN_CAP   256
static struct { wchar_t key[DYN_KEY]; wchar_t text[DYN_CAP]; FString fs; } g_dyn[DYN_TEXTS];
static int g_ndyn;

/* 1 = set; 0 = not an SV_ key, or the table is full */
static int SetDynText(const wchar_t* key, const wchar_t* text)
{
    size_t kn = WLen(key), tn = WLen(text);
    if (kn < 4 || kn >= DYN_KEY || key[0] != L'S' || key[1] != L'V' || key[2] != L'_') return 0;
    if (tn >= DYN_CAP) tn = DYN_CAP - 1;
    int i = 0;
    while (i < g_ndyn && !(WLen(g_dyn[i].key) == kn && !memcmp(g_dyn[i].key, key, kn * 2))) ++i;
    if (i == g_ndyn) {
        if (g_ndyn == DYN_TEXTS) return 0;
        memcpy(g_dyn[i].key, key, (kn + 1) * 2);
        ++g_ndyn;
    }
    memcpy(g_dyn[i].text, text, tn * 2);
    g_dyn[i].text[tn] = 0;
    g_dyn[i].fs = (FString){ g_dyn[i].text, (int32_t)tn + 1, DYN_CAP };
    return 1;
}

static uintptr_t OnText(void* table, uintptr_t flag, void* keyp, void* found)
{
    const FString* key = (const FString*)keyp;
    if (key && key->data && key->num > 4 && key->data[0] == L'S' && key->data[1] == L'V' && key->data[2] == L'_') {
        /* Lua's first (0.27.0: Survival's pages have built-in texts here that Lua's replace), then the built-in ones */
        for (int i = 0; i < g_ndyn; ++i) {
            size_t n = WLen(g_dyn[i].key);
            if ((size_t)key->num == n + 1 && memcmp(key->data, g_dyn[i].key, n * 2) == 0) {
                if (found) *(uint8_t*)found = 1;
                return (uintptr_t)&g_dyn[i].fs;
            }
        }
        for (size_t i = 0; i < sizeof(g_text) / sizeof(g_text[0]); ++i) {
            size_t n = WLen(g_text[i].key);
            if ((size_t)key->num == n + 1 && memcmp(key->data, g_text[i].key, n * 2) == 0) {
                if (found) *(uint8_t*)found = 1;
                return (uintptr_t)&g_text[i].fs;
            }
        }
    }
    return g_nextText(table, flag, keyp, found);
}

/* The landing menu (in-game hangar, LiveMenuIngameHangarWidget): Survival adds its shop rows to the page's command
 * table at run time (Scripts/main.lua), with StringArgs "SV_Buy_<item>". The stock decide would read those as page 0
 * (_wtoi), so the hook takes them: the request waits for Lua (SV_ShopRequest) and the page stays where it is. */
#define SHOP_QUEUE 8
static uint8_t* g_fHangarDecide;
static Fn1      g_nextHangarDecide;
static wchar_t  g_shopQueue[SHOP_QUEUE][32];        /* picks waiting for Lua; both ends run on the game thread */
static int32_t  g_shopHead, g_shopCount;

static uintptr_t OnHangarDecide(void* page)
{
    const FString* a = SelectedArgs(page, NULL);
    /* every press on the landing menu (test of 2026-10-22: a second landing's shop picks never showed up) */
    Log(L"landing menu: decide on %p, row '%s'", page, a && a->data && a->num > 0 ? a->data : L"?");
    if (a && a->num > 8 && a->num <= 32 && !memcmp(a->data, L"SV_Buy_", 7 * 2)) {
        if (g_shopCount < SHOP_QUEUE) {
            wchar_t* q = g_shopQueue[(g_shopHead + g_shopCount++) % SHOP_QUEUE];
            memcpy(q, a->data, (size_t)a->num * 2);
            q[a->num - 1] = 0;
            Log(L"shop: %s picked on the landing menu", q);
        } else {
            Log(L"shop: %d picks already waiting; this one is dropped", (int32_t)SHOP_QUEUE);
        }
        return 1;
    }
    return g_nextHangarDecide(page);
}

#include "survival_rt_game.c"                       /* spawner, teardown gate, units, ammo, music, events, game Lua */

/* ---- Lua bridge -----------------------------------------------------------
 * UE4SS calls a C++ mod's on_lua_start(mod_name, lua, ...) whenever a Lua mod starts, before its main.lua runs. In
 * UE4SS 3.0.1 that is vtable slot 6 (slot 8 is its deprecated twin; 5 and 7 are the no-name overloads, only for a Lua
 * mod of the same name), traced in UE4SS.dll at 0x180301b60. Rather than trust a slot number, every slot of the mod
 * object is a small probe: when a call's first argument is a std::wstring_view naming this mod, the second is its
 * LuaMadeSimple::Lua, and the spawner's functions are registered on it as Lua globals (SV_*). Lua runs them on the
 * game thread (ExecuteInGameThread), which is where the game's spawn code has to run.                           */
/* Pops the next argument (always stack index 1: UE4SS's getters remove what they read). */
static int ArgName(void* lua, wchar_t* out, size_t cap)
{
    if (U.luaStackSize(lua) < 1 || !U.luaIsString(lua, 1)) return 0;
    StrView sv = { NULL, 0 };
    U.luaGetString(lua, &sv, 1);
    if (!sv.p || !sv.n || sv.n >= cap) return 0;
    for (size_t i = 0; i < sv.n; ++i) {
        if (sv.p[i] < 0x20 || sv.p[i] > 0x7E) return 0;
        out[i] = (wchar_t)sv.p[i];
    }
    out[sv.n] = 0;
    return 1;
}

static int ArgNumber(void* lua, double* v)
{
    if (U.luaStackSize(lua) < 1 || !U.luaIsNumber(lua, 1)) return 0;
    *v = U.luaGetNumber(lua, 1);
    return 1;
}

static int Ret(void* lua, int64_t v) { U.luaSetInteger(lua, v); return 1; }

#define SV_FLIGHT_FEED 1                            /* (coop.c: flight.c's flight block and real planes) */
#include "coop.c"                                   /* Survival COOP (runtime 0.20.0) */
#include "flight.c"                                 /* flight sync and DOWN (runtime 0.28.5) */

#include "survival_rt_lua.c"                        /* sound, the SV_* Lua functions, the leaderboard */

static void RegisterLua(void* lua)
{
    static const struct { const char* name; LuaFn fn; } kFns[] = {
        { "SV_Version", L_Version }, { "SV_MenuChoice", L_MenuChoice }, { "SV_Spawn", L_Spawn }, { "SV_SetAircraft", L_SetAircraft },
        { "SV_UnitAlive", L_UnitAlive }, { "SV_LogUnits", L_LogUnits }, { "SV_Reset", L_Reset }, { "SV_Crumb", L_Crumb },
        { "SV_LevelGone", L_LevelGone }, { "SV_Recycle", L_Recycle }, { "SV_RecycleWait", L_RecycleWait },   /* (0.32.22) */
        { "SV_Ammo", L_Ammo }, { "SV_SetAmmo", L_SetAmmo }, { "SV_AmmoMax", L_AmmoMax }, { "SV_FreeRestock", L_SetFreeRestock },
        { "SV_GameLua", L_GameLua }, { "SV_GameLuaState", L_GameLuaState },
        { "SV_PlayBGM", L_PlayBGM }, { "SV_BGM", L_BGM }, { "SV_Event", L_Event }, { "SV_MusicPlayer", L_MusicPlayer }, { "SV_MusicClock", L_MusicClock }, { "SV_MusicHold", L_MusicHold }, { "SV_SetLevel", L_SetLevel }, { "SV_PlaneLevel", L_PlaneLevel }, { "SV_Invert", L_SetControlInvert }, { "SV_PlayerTarget", L_PlayerTarget },
        { "SV_SetText", L_SetText }, { "SV_ShopRequest", L_ShopRequest }, { "SV_MenuSetting", L_MenuSetting },
        { "SV_MenuPages", L_MenuPages }, { "SV_MenuClass", L_MenuClass }, { "SV_MenuSlot", L_MenuSlot }, { "SV_MenuQuick", L_MenuQuick }, { "SV_BGMNames", L_BGMNames },
        { "SV_CoopOpen", L_CoopOpen }, { "SV_CoopClose", L_CoopClose }, { "SV_CoopInfo", L_CoopInfo }, { "SV_CoopSend", L_CoopSend },
        { "SV_CoopRecv", L_CoopRecv }, { "SV_CoopMe", L_CoopMe }, { "SV_CoopPeer", L_CoopPeer }, { "SV_CoopTrack", L_CoopTrack },
        { "SV_CoopBind", L_CoopBind }, { "SV_CoopPeerAt", L_CoopPeerAt }, { "SV_CoopReset", L_CoopReset },
        { "SV_CoopSpawnPP", L_CoopSpawnPP }, { "SV_CoopKillPP", L_CoopKillPP }, { "SV_CoopFollow", L_CoopFollow },
        { "SV_CoopPPRole", L_CoopPPRole }, { "SV_CoopFeed", L_CoopFeed }, { "SV_CoopPPFx", L_CoopPPFx },
        { "SV_CoopFire", L_CoopFire }, { "SV_CoopShots", L_CoopShots }, { "SV_CoopPPShot", L_CoopPPShot }, { "SV_PPWeapons", L_PPWeapons }, { "SV_CoopPeerIds", L_CoopPeerIds }, { "SV_CoopSwapPP", L_CoopSwapPP }, { "SV_ObjChain", L_ObjChain }, { "SV_StoreKeepAI", L_StoreKeepAI }, { "SV_GcBusy", L_GcBusy },
        { "SV_CoopLoadout", L_CoopLoadout }, { "SV_SpawnCam", L_SpawnCam }, { "SV_StickNow", L_StickNow }, { "SV_PPName", L_PPName }, { "SV_CoopPaint", L_CoopPaint }, { "SV_InputNow", L_InputNow }, { "SV_Down", L_Down }, { "SV_Respawn", L_Respawn },
        { "SV_MemMB", L_MemMB }, { "SV_SndLoad", L_SndLoad }, { "SV_SndPlay", L_SndPlay }, { "SV_SndSet", L_SndSet }, { "SV_SndStop", L_SndStop }, { "SV_SndMaster", L_SndMaster },
#ifndef SV_OFFLINE
        { "SV_Post", L_Post }, { "SV_PostResult", L_PostResult }, { "SV_PostReply", L_PostReply }, { "SV_SteamName", L_SteamName },
        { "SV_BuildHash", L_BuildHash },
#endif
    };
    if (!ResolveUE4SS()) { Log(L"Lua bridge: UE4SS exports missing; Survival's spawner is off"); return; }
    /* (0.32.23) a line before the loop and a crumb after it: the stall of 2026-11-03 (VFmt, below) was found this way */
    Log(L"Lua bridge: registering %d functions", (int32_t)(sizeof(kFns) / sizeof(kFns[0])));
    static wchar_t list[1024];                                    /* the names registered, for the log */
    size_t used = 0;
    for (size_t i = 0; i < sizeof(kFns) / sizeof(kFns[0]); ++i) {
        MsvcString s; memset(&s, 0, sizeof(s));
        size_t n = 0;
        while (kFns[i].name[n]) ++n;
        if (n > 15) { Log(L"Lua bridge: function %d's name is longer than 15 characters; not registered", (int32_t)i); continue; }
        memcpy(s.u.buf, kFns[i].name, n + 1);         /* fits the small-string buffer (<= 15 characters) */
        s.size = n; s.cap = 15;
        LuaFn fn = kFns[i].fn;
        U.luaRegister(lua, &s, &fn);
        for (size_t c = 0; c < n && used + 3 < sizeof(list) / sizeof(list[0]); ++c) list[used++] = (wchar_t)kFns[i].name[c];
        if (used + 3 < sizeof(list) / sizeof(list[0])) { list[used++] = L','; list[used++] = L' '; }
    }
    if (used >= 2) used -= 2;                                    /* the last ", " */
    list[used] = 0;
    Crumb(L"lua bridge: all registered");
    Log(L"Lua bridge: %s registered", list);                     /* the ones that were, not a fixed list */
}

#define MOD_SLOTS 16
static int32_t g_slotCalls[MOD_SLOTS];

static void ModSlot(int slot, uintptr_t a, uintptr_t b)
{
    int32_t n = g_slotCalls[slot];
    if (n > 2000) return;                     /* called every frame: not a mod-start slot */
    g_slotCalls[slot] = n + 1;
    if (n == 0) Log(L"UE4SS calls mod slot %d", slot);
    const WStrView* v = (const WStrView*)a;
    if (!Readable(v, sizeof(*v)) || !v->p || !v->n || v->n > 64 || !Readable(v->p, v->n * 2)) return;
    static const wchar_t kMe[] = L"AC8SurvivalMode";
    if (v->n != sizeof(kMe) / 2 - 1 || memcmp(v->p, kMe, sizeof(kMe) - 2) != 0) return;
    if (!Readable((void*)b, 8)) return;
    Log(L"UE4SS: Lua mod AC8SurvivalMode started (mod slot %d)", slot);
    RegisterLua((void*)b);
}

/* ---- install ------------------------------------------------------------ */
typedef struct { uint8_t* decide; int wantNext; void** exact; int nExact; void** chained; int nChained; } VtCtx;

static void VtRegion(uint8_t* p, size_t n, void* vctx)
{
    VtCtx* c = (VtCtx*)vctx;
    uint8_t* end = p + n;
    p = (uint8_t*)(((uintptr_t)p + 7) & ~(uintptr_t)7);
    for (; p + 8 * (VT_NEXT_SLOT + 1) <= end; p += 8) {
        void** v = (void**)p;
        if (v[VT_BASE_SLOT] != g_fBase) continue;
        void* dec = v[VT_DECIDE_SLOT];
        void* nxt = v[VT_NEXT_SLOT];
        int nextIsPage = nxt == g_fDiffNext || (nxt && !InGame(nxt));
        if (nextIsPage != c->wantNext) continue;
        if (dec == c->decide) { c->exact = v; ++c->nExact; }
        else if (dec && !InGame(dec)) { c->chained = v; ++c->nChained; }
    }
}

/* The vtable whose [0xDF] is the base function and whose [0xEE] is `decide`, or another mod's handler in
 * front of it. wantNext: its [0x111] is the difficulty page's next-menu function (or another mod's handler). */
static void** FindVtable(uint8_t* decide, int wantNext)
{
    VtCtx c = { decide, wantNext, NULL, 0, NULL, 0 };
    for (int s = 0; s < g_nsec; ++s)
        if (!(g_sec[s].ch & IMAGE_SCN_MEM_EXECUTE)) ForRegions(g_sec[s].start, g_sec[s].len, VtRegion, &c);
    if (c.nExact == 1) return c.exact;
    if (c.nExact == 0 && c.nChained == 1) return c.chained;
    Log(L"vtable search: %d exact, %d through another mod", c.nExact, c.nChained);
    return NULL;
}

/* One pass over the game's code for every signature (as shipped, or behind another mod's jump). */
static void FindFunctions(void)
{
    static uint8_t tp[64], tm[64], xp[64], xm[64], vp[64], vm[64], hp[64], hm[64], ip[64], im[64];
    HookedPattern(tp, tm, sizeof(kSigTransition), kSigTransitionTail, sizeof(kSigTransitionTail));
    HookedPattern(xp, xm, 15, kSigText + 15, sizeof(kSigText) - 15);
    HookedPattern(vp, vm, 15, kSigPauseValidity + 15, sizeof(kSigPauseValidity) - 15);
    HookedPattern(hp, hm, 15, kSigHangarDecide + 15, sizeof(kSigHangarDecide) - 15);
    HookedPattern(ip, im, 16, kSigBuildInput + 16, sizeof(kSigBuildInput) - 16);
    Pattern p[] = {
        { kSigBase,       NULL, sizeof(kSigBase),       NULL, 0 }, { kSigMainDecide, kSigMainDecideMask, sizeof(kSigMainDecide), NULL, 0 },
        { kSigDiffDecide, NULL, sizeof(kSigDiffDecide), NULL, 0 }, { kSigDiffNext,      NULL, sizeof(kSigDiffNext),      NULL, 0 },
        { kSigGotoMenu,   NULL, sizeof(kSigGotoMenu),   NULL, 0 }, { kSigSetDifficulty, kSigSetDifficultyMask, sizeof(kSigSetDifficulty), NULL, 0 },
        { kSigTransition, NULL, sizeof(kSigTransition), NULL, 0 }, { tp, tm, sizeof(kSigTransition) + sizeof(kSigTransitionTail), NULL, 0 },
        { kSigText,       NULL, sizeof(kSigText),       NULL, 0 }, { xp, xm, sizeof(kSigText), NULL, 0 },
        { kSigSpawnUnit,      kSigSpawnUnitMask,      sizeof(kSigSpawnUnit),      NULL, 0 },
        { kSigUnregisterUnit, kSigUnregisterUnitMask, sizeof(kSigUnregisterUnit), NULL, 0 },
        { kSigUnitIdSpawned,  NULL, sizeof(kSigUnitIdSpawned), NULL, 0 },
        { kSigDestroyActor,   NULL, sizeof(kSigDestroyActor),  NULL, 0 },
        { kSigAmmoExecute,    kSigAmmoExecuteMask, sizeof(kSigAmmoExecute), NULL, 0 },
        { kSigAmmoFlare,      kSigAmmoFlareMask,   sizeof(kSigAmmoFlare),   NULL, 0 },
        { kSigAmmoWeapons,    NULL, sizeof(kSigAmmoWeapons),   NULL, 0 },
        { kSigFreeRestock,    kSigFreeRestockMask, sizeof(kSigFreeRestock), NULL, 0 },
        { kSigGameLuaState,   kSigGameLuaStateMask, sizeof(kSigGameLuaState), NULL, 0 },
        { kSigBgmPlay,        kSigBgmPlayMask,     sizeof(kSigBgmPlay),     NULL, 0 },
        { kSigRemoteEvent,    kSigRemoteEventMask, sizeof(kSigRemoteEvent), NULL, 0 },
        { kSigPauseValidity,  NULL, sizeof(kSigPauseValidity), NULL, 0 }, { vp, vm, sizeof(kSigPauseValidity), NULL, 0 },
        { kSigHangarDecide,   NULL, sizeof(kSigHangarDecide),  NULL, 0 }, { hp, hm, sizeof(kSigHangarDecide),  NULL, 0 },
        { kSigMusicTick,      NULL, sizeof(kSigMusicTick),     NULL, 0 }, { kSigMusicNext, NULL, sizeof(kSigMusicNext), NULL, 0 },
        { kSigBuildInput,     NULL, sizeof(kSigBuildInput),    NULL, 0 }, { ip, im, sizeof(kSigBuildInput), NULL, 0 },
        { kSigAITeleportTo,   NULL, sizeof(kSigAITeleportTo),  NULL, 0 },
        { kSigAITeleportInner, kSigAITeleportInnerMask, sizeof(kSigAITeleportInner), NULL, 0 },
        { kSigSpawnPlayerPlane, kSigSpawnPlayerPlaneMask, sizeof(kSigSpawnPlayerPlane), NULL, 0 },
        { kSigWorldSpawnActor,  kSigWorldSpawnActorMask,  sizeof(kSigWorldSpawnActor),  NULL, 0 },
        { kSigPPTeleportTo,     NULL, sizeof(kSigPPTeleportTo), NULL, 0 },
        { kSigPPTeleportInner,  kSigPPTeleportInnerMask, sizeof(kSigPPTeleportInner), NULL, 0 },
        { kSigRemotePossess,    NULL, sizeof(kSigRemotePossess), NULL, 0 },
        { kSigRemoteNetObj,     NULL, sizeof(kSigRemoteNetObj),  NULL, 0 },
        { kSigRemoteRole,       NULL, sizeof(kSigRemoteRole),    NULL, 0 },
        { kSigRemoteDummyClass, NULL, sizeof(kSigRemoteDummyClass), NULL, 0 },
        { kSigRemoteLoadout,    kSigRemoteLoadoutMask, sizeof(kSigRemoteLoadout), NULL, 0 },
        { kSigRemoteFlags,      NULL, sizeof(kSigRemoteFlags),  NULL, 0 },
        { kSigRemoteFinish,     NULL, sizeof(kSigRemoteFinish), NULL, 0 },
        { kSigFireOne,          kSigFireOneMask,   sizeof(kSigFireOne),   NULL, 0 },
        { kSigFireExec,         NULL,              sizeof(kSigFireExec),  NULL, 0 },
        { kSigTakeoffAB,        kSigTakeoffABMask, sizeof(kSigTakeoffAB), NULL, 0 },
        { kSigPPRespawn,        NULL,              sizeof(kSigPPRespawn), NULL, 0 },
        { kSigRemoteUpdate,     kSigRemoteUpdateMask, sizeof(kSigRemoteUpdate), NULL, 0 },
        { kSigSurfacePP,        kSigSurfacePPMask, sizeof(kSigSurfacePP), NULL, 0 },
        { kSigPPDamage,         NULL,              sizeof(kSigPPDamage),  NULL, 0 },
        { kSigPlaneFired,       kSigPlaneFiredMask, sizeof(kSigPlaneFired), NULL, 0 },
        { kSigRemoteFire,       NULL,              sizeof(kSigRemoteFire), NULL, 0 },
        { kSigLaunchWeapon,     NULL,              sizeof(kSigLaunchWeapon), NULL, 0 },
        { kSigFireFlares,       NULL,              sizeof(kSigFireFlares), NULL, 0 },
        { kSigNetManager,       kSigNetManagerMask, sizeof(kSigNetManager), NULL, 0 },
        { kSigSelectSpecial,    NULL,              sizeof(kSigSelectSpecial), NULL, 0 },
        { kSigArmSpecial,       kSigArmSpecialMask, sizeof(kSigArmSpecial), NULL, 0 },
        { kSigGearApply,        kSigGearApplyMask, sizeof(kSigGearApply), NULL, 0 },
        { kSigUnitFxFrame,      kSigUnitFxFrameMask, sizeof(kSigUnitFxFrame), NULL, 0 },
        { kSigTargetCheck,      kSigTargetCheckMask, sizeof(kSigTargetCheck), NULL, 0 },
        { kSigPlaneEw,          NULL,              sizeof(kSigPlaneEw), NULL, 0 },
        { kSigWorldOf,          NULL,              sizeof(kSigWorldOf), NULL, 0 },
        { kSigUnitFx2Frame,     kSigUnitFx2FrameMask, sizeof(kSigUnitFx2Frame), NULL, 0 },
        { kSigMgDeactivate,     kSigMgDeactivateMask, sizeof(kSigMgDeactivate), NULL, 0 },
        { kSigMgRestore,        kSigMgRestoreMask, sizeof(kSigMgRestore), NULL, 0 },
        { kSigPurgeGarbage,     kSigPurgeGarbageMask, sizeof(kSigPurgeGarbage), NULL, 0 },
        { kSigPathTrackTick,    kSigPathTrackTickMask, sizeof(kSigPathTrackTick), NULL, 0 },
    };
    uint64_t t0 = GetTickCount64();
    ScanCode(p, (int)(sizeof(p) / sizeof(p[0])));
    g_fBase         = p[0].hit;
    g_fMainDecide   = p[1].hit;
    g_fDiffDecide   = p[2].hit;
    g_fDiffNext     = p[3].hit;
    g_gotoMenu      = (Fn2)p[4].hit;
    g_setDifficulty = (Fn2)p[5].hit;
    g_fTransition   = p[6].hit ? p[6].hit : p[7].hit;
    g_fText         = p[8].hit ? p[8].hit : p[9].hit;
    g_spawnUnit      = (SpawnUnitFn)p[10].hit;
    g_unregisterUnit = (UnregisterUnitFn)p[11].hit;
    g_fUnitIdSpawned = p[12].hit;
    g_destroyActor   = (DestroyActorFn)p[13].hit;
    g_fAmmoExecute   = p[14].hit;
    g_fAmmoFlare     = p[15].hit;
    g_fAmmoWeapons   = p[16].hit;
    g_fFreeRestock   = p[17].hit;
    g_fGameLuaState  = p[18].hit;
    g_fBgmPlay       = p[19].hit;
    g_fRemoteEvent   = p[20].hit;
    g_fPauseValidity = p[21].hit ? p[21].hit : p[22].hit;
    g_fHangarDecide  = p[23].hit ? p[23].hit : p[24].hit;
    g_fMusicTick     = p[25].hit;
    g_fMusicNext     = p[26].hit;
    g_fBuildInput    = p[27].hit ? p[27].hit : p[28].hit;
    g_fAITeleportTo    = p[29].hit;
    g_fAITeleportInner = p[30].hit;
    g_fSpawnPlayerPlane = p[31].hit;
    g_fWorldSpawnActor  = p[32].hit;
    g_fPPTeleportTo     = p[33].hit;
    g_fPPTeleportInner  = p[34].hit;
    g_siteRemotePossess = p[35].hit;
    g_siteRemoteNetObj  = p[36].hit;
    g_siteRemoteRole    = p[37].hit;
    g_siteRemoteDummyCls = p[38].hit;
    g_siteRemoteLoadout = p[39].hit;
    g_siteRemoteFlags   = p[40].hit;
    g_siteRemoteFinish  = p[41].hit;
    g_fFireOne          = p[42].hit;
    g_fFireExec         = p[43].hit;
    g_fTakeoffAB        = p[44].hit;
    g_fPPRespawn        = p[45].hit;
    g_fRemoteUpdate     = p[46].hit;
    g_fSurfacePP        = p[47].hit;
    g_fPPDamage         = p[48].hit;
    g_fPlaneFired       = p[49].hit;
    g_fRemoteFire       = p[50].hit;
    g_fLaunchWeapon     = p[51].hit;
    g_fFireFlares       = p[52].hit;
    g_fNetManager       = p[53].hit;
    g_fSelectSpecial    = p[54].hit;
    g_fArmSpecial       = p[55].hit;
    g_fGearSite         = p[56].hit;
    g_fUnitFxFrame      = p[57].hit;
    g_fTargetCheck      = p[58].hit;
    g_fPlaneEw          = p[59].hit;
    g_fWorldOf          = p[60].hit;
    g_fUnitFx2Frame     = p[61].hit;
    g_fMgDeactivate     = p[62].hit;                    /* (the STORE freeze: flight.c) */
    g_fMgRestore        = p[63].hit;
    g_fPurgeGarbage     = p[64].hit;                    /* (runtime 0.32.21: SV_GcBusy, flight.c) */
    g_fPathTrackTick    = p[65].hit;                    /* (runtime 0.32.22: the path tracker guard, flight.c) */
    Log(L"game functions (%d ms): base %p, main decide %p, difficulty decide %p, next %p, goto %p, set difficulty %p, transition %p, text %p",
        (int32_t)(GetTickCount64() - t0), g_fBase, g_fMainDecide, g_fDiffDecide, g_fDiffNext,
        (void*)g_gotoMenu, (void*)g_setDifficulty, g_fTransition, g_fText);
    Log(L"spawn functions: spawn unit %p, unregister unit %p, unit check %p, destroy actor %p",
        (void*)g_spawnUnit, (void*)g_unregisterUnit, g_fUnitIdSpawned, (void*)g_destroyActor);
    Log(L"ammo functions: node execute %p, flare lambda %p, weapons lambda %p, free restock %p", g_fAmmoExecute, g_fAmmoFlare, g_fAmmoWeapons, g_fFreeRestock);
    Log(L"game Lua: GetGameLuaState %p", g_fGameLuaState);
    Log(L"music and events: BGM node %p, remote-event node %p, pause list %p, landing menu decide %p", g_fBgmPlay, g_fRemoteEvent,
        g_fPauseValidity, g_fHangarDecide);
    Log(L"music player: track clock tick %p, next track %p", g_fMusicTick, g_fMusicNext);
    Log(L"flight input: BuildFlightInput %p", g_fBuildInput);
    Log(L"coop: AI plane teleport %p, inner %p", g_fAITeleportTo, g_fAITeleportInner);
    Log(L"coop: player plane: spawn %p, world spawn %p, teleport %p, inner %p; remote spawn sites: possess %p, network object %p, role %p, dummy class %p, loadout %p, loadout bytes %p, finish %p",
        g_fSpawnPlayerPlane, g_fWorldSpawnActor, g_fPPTeleportTo, g_fPPTeleportInner, g_siteRemotePossess, g_siteRemoteNetObj, g_siteRemoteRole,
        g_siteRemoteDummyCls, g_siteRemoteLoadout, g_siteRemoteFlags, g_siteRemoteFinish);
    Log(L"flight: one-shot fire %p (LiveFireOneShotWeapon's Execute %p), AI takeoff afterburner %p, player plane respawn %p, remote update %p, surface update %p, player plane damage %p",
        g_fFireOne, g_fFireExec, g_fTakeoffAB, g_fPPRespawn, g_fRemoteUpdate, g_fSurfacePP, g_fPPDamage);
    Log(L"coop2mp: weapons fired %p, remote plane fire %p, launch weapon %p, flares %p, network manager %p, select special %p, arm "
        L"special %p, gear site %p", g_fPlaneFired, g_fRemoteFire, g_fLaunchWeapon, g_fFireFlares, g_fNetManager, g_fSelectSpecial,
        g_fArmSpecial, g_fGearSite);
    Log(L"guard: AI unit effect update %p, a second unit update %p, target entry check %p; coop2mp: plane electronic update %p",
        g_fUnitFxFrame, g_fUnitFx2Frame, g_fTargetCheck, g_fPlaneEw);
    __atomic_store_n(&g_scanned, 1, __ATOMIC_RELEASE);
}

static int StonehengeInstalled(void)
{
    return FileExists(g_modsDir, L"AC8Stonehenge\\enabled.txt") && FileExists(g_modsDir, L"AC8Stonehenge\\dlls\\main.dll");
}

static int Install(void)
{
    InitText();
    if (g_fText && HookInline(g_fText, 15, (void*)OnText, (void**)&g_nextText, L"text lookup")) {}
    else Log(L"text lookup not found; the menu entry shows its text key instead of its name");
    if (g_fPauseValidity && HookInline(g_fPauseValidity, 15, (void*)OnPauseValidity, (void**)&g_nextPauseValidity, L"pause menu list")) {}
    else Log(L"pause menu list not found; no music player in Survival's pause menu");
    if (g_fHangarDecide && HookInline(g_fHangarDecide, 15, (void*)OnHangarDecide, (void**)&g_nextHangarDecide, L"landing menu decide")) {}
    else Log(L"landing menu decide not found; the airfield shop rows do nothing");
    if (g_fMusicTick && HookInline(g_fMusicTick, 15, (void*)OnMusicTick, (void**)&g_nextMusicTick, L"music player clock")) {}
    else Log(L"music player clock not found; its tracks can still end early after a pause");
    if (g_fMusicNext && HookInline(g_fMusicNext, 16, (void*)OnMusicNext, (void**)&g_nextMusicNext, L"music player next track")) {}
    else Log(L"music player next track not found (log only)");
    if (g_fBuildInput && HookInline(g_fBuildInput, 16, (void*)OnBuildInput, (void**)&g_nextBuildInput, L"flight input")) {}
    else Log(L"flight input not found; the Anomaly's field can't invert the controls");
    if (g_fRemoteUpdate && HookInline(g_fRemoteUpdate, 18, (void*)OnRemoteUpdate, (void**)&g_nextRemoteUpdate, L"remote player plane update")) {}
    else Log(L"remote player plane update not found; SV_CoopFeed does nothing (COOP2MP)");
    UoFind();                                              /* (GUObjectArray, for the guards' liveness check: flight.c) */
    GcFind();                                              /* (the engine's purge flags, SV_GcBusy: flight.c) */
    UfxInstall();                                          /* (the AI unit effect guard: flight.c) */
    Ufx2Install();                                         /* (its second update's, +0x42c0: flight.c) */
    TgtInstall();                                          /* (the target search guard: flight.c) */
    PtInstall();                                           /* (0.32.22: the AI path tracking guard: flight.c) */
    MgInstall();                                           /* (the STORE freeze: flight.c) */
    if (g_fPlaneEw && HookInline(g_fPlaneEw, 15, (void*)OnPlaneEw, (void**)&g_nextPlaneEw, L"plane electronic update")) {}
    else Log(L"coop2mp: the plane electronic update wasn't found: other players' ESM / ECM fields help no one here");
    if (g_fSurfacePP && HookInline(g_fSurfacePP, 18, (void*)OnSurfacePP, (void**)&g_nextSurfacePP, L"player plane surface update")) {}
    else Log(L"player plane surface update not found; a fed plane shows no afterburner (COOP2MP)");
    if (g_fPPDamage && HookInline(g_fPPDamage, 15, (void*)OnPPDamage, (void**)&g_nextPPDamage, L"player plane damage")) {}
    else Log(L"player plane damage not found; hits on a fed plane aren't logged (COOP2MP)");
    if (g_fPlaneFired && g_fRemoteFire && g_fNetManager && g_fLaunchWeapon && g_fFireFlares &&
        HookInline(g_fPlaneFired, 15, (void*)OnPlaneFired, (void**)&g_nextPlaneFired, L"player plane weapons fired") &&
        HookInline(g_fLaunchWeapon, 21, (void*)OnLaunchWeapon, (void**)&g_nextLaunchWeapon, L"launch weapon") &&
        HookInline(g_fFireFlares, 18, (void*)OnFireFlares, (void**)&g_nextFireFlares, L"fire flares")) {}
    else Log(L"COOP2MP T4's game code not all found (or not hooked); your shots aren't replayed");

    if (!g_fBase || !g_fMainDecide || !g_fDiffDecide || !g_fDiffNext || !g_gotoMenu || !g_setDifficulty || !g_fTransition) {
        Log(L"menu: game functions not found (different game version?); the Survival entry opens the free-mission difficulty page only");
        return 0;
    }
    g_vtA = FindVtable(g_fMainDecide, 0);
    g_vtB = FindVtable(g_fDiffDecide, 1);
    Log(L"menu tables: main menu %p, difficulty page %p", (void*)g_vtA, (void*)g_vtB);
    if (!g_vtA || !g_vtB) { Log(L"menu: tables not found; the Survival entry opens the free-mission difficulty page only"); return 0; }

    int ok = HookInline(g_fTransition, sizeof(kSigTransition), (void*)OnTransition, (void**)&g_nextTransition, L"menu transition");
    ok = ok && HookSlot(&g_vtA[VT_DECIDE_SLOT], (void*)OnMainDecide, (void**)&g_nextMainDecide, L"main menu decide");
    ok = ok && HookSlot(&g_vtB[VT_DECIDE_SLOT], (void*)OnDiffDecide, (void**)&g_nextDiffDecide, L"difficulty decide");
    ok = ok && HookSlot(&g_vtB[VT_NEXT_SLOT], (void*)OnDiffNext, (void**)&g_nextDiffNext, L"difficulty next menu");
    Log(ok ? L"menu hooks installed (mission %d, hangar menu %x)" : L"menu: could not install every hook",
        (int32_t)SURVIVAL_MISSION_ID, (uint32_t)HANGAR_MENU_ID);
    return ok;
}

static DWORD WINAPI Worker(void* arg)
{
    (void)arg;
    if (!ReadImage()) { Log(L"game image not found"); return 0; }
    FindFunctions();
    if (StonehengeInstalled() && g_fText && g_fTransition) {
        /* Stonehenge finds these two by their original bytes, so it has to hook them before we do. */
        Log(L"AC8 Stonehenge Returns is installed: waiting for its hooks so both mods work");
        uint64_t until = GetTickCount64() + STONEHENGE_WAIT_MS;
        while (!(IsJump(g_fText) && IsJump(g_fTransition)) && GetTickCount64() < until) Sleep(250);
        Log(IsJump(g_fText) && IsJump(g_fTransition) ? L"Stonehenge's hooks are in place"
                                                      : L"Stonehenge's hooks did not appear; installing anyway");
        Sleep(500);   /* the transition hook is its last patch; give it a moment to finish logging */
    }
    Install();
    return 0;
}

/* ---- the UE4SS mod object (same layout as the AC8 Mod Loader's) ---------- */

static void SetWString(MsvcWString* s, const wchar_t* text)
{
    size_t n = WLen(text);
    if (n <= 7) { memcpy(s->u.buf, text, (n + 1) * 2); s->size = n; s->cap = 7; return; }
    size_t cap = n | 7;
    wchar_t* p = (wchar_t*)malloc((cap + 1) * 2);
    if (!p) return;
    memcpy(p, text, (n + 1) * 2);
    s->u.ptr = p; s->size = n; s->cap = cap;
}

#define MOD_OBJECT_SIZE 0x200
#define VTABLE_SLOTS    40
static int g_instances;

static void* WINAPI Mod_DeletingDtor(void* self, uint32_t flags)
{
    if (g_instances > 0) --g_instances;
    UE4SS_ModBase_Dtor(self);
    if (flags & 1) free(self);
    return self;
}

static void* WINAPI Mod_NoOp(void) { return NULL; }

/* Slots 1..15 of CppUserModBase (on_update, on_unreal_init, ..., on_lua_start x4, ...): each one probes its
 * arguments for this mod's Lua start (ModSlot). */
#define MOD_SLOT(n) static void* WINAPI Mod_Slot##n(void* self, uintptr_t a, uintptr_t b) { (void)self; ModSlot(n, a, b); return NULL; }
MOD_SLOT(1)  MOD_SLOT(2)  MOD_SLOT(3)  MOD_SLOT(4)  MOD_SLOT(5)  MOD_SLOT(6)  MOD_SLOT(7)  MOD_SLOT(8)
MOD_SLOT(9)  MOD_SLOT(10) MOD_SLOT(11) MOD_SLOT(12) MOD_SLOT(13) MOD_SLOT(14) MOD_SLOT(15)
#undef MOD_SLOT

static void* const g_modVtable[1 + VTABLE_SLOTS] = {
    [0]                   = NULL,
    [1]                   = (void*)Mod_DeletingDtor,
    [2]  = (void*)Mod_Slot1,  [3]  = (void*)Mod_Slot2,  [4]  = (void*)Mod_Slot3,  [5]  = (void*)Mod_Slot4,
    [6]  = (void*)Mod_Slot5,  [7]  = (void*)Mod_Slot6,  [8]  = (void*)Mod_Slot7,  [9]  = (void*)Mod_Slot8,
    [10] = (void*)Mod_Slot9,  [11] = (void*)Mod_Slot10, [12] = (void*)Mod_Slot11, [13] = (void*)Mod_Slot12,
    [14] = (void*)Mod_Slot13, [15] = (void*)Mod_Slot14, [16] = (void*)Mod_Slot15,
    [17 ... VTABLE_SLOTS] = (void*)Mod_NoOp,
};

EXPORT void* start_mod(void)
{
    uint8_t* mod = (uint8_t*)malloc(MOD_OBJECT_SIZE);
    if (!mod) return NULL;
    memset(mod, 0, MOD_OBJECT_SIZE);
    UE4SS_ModBase_Ctor(mod);
    *(void* const**)mod = &g_modVtable[1];
    SetWString((MsvcWString*)(mod + 0x20), L"AC8SurvivalMode");
    SetWString((MsvcWString*)(mod + 0x40), RT_VERSION);
    SetWString((MsvcWString*)(mod + 0x60), L"Survival Mode: main menu entry, texts and spawner");
    SetWString((MsvcWString*)(mod + 0x80), L"voidcallsreaper");
    if (g_instances++ == 0) {
        OpenLog();
        OpenCrumbs();
        Log(L"AC8 Survival Mode runtime %s", RT_VERSION);
        HANDLE th = CreateThread(NULL, 0, Worker, NULL, 0, NULL);
        if (th) CloseHandle(th); else Log(L"could not start the install thread");
#ifndef SV_OFFLINE
        /* the build hash (the leaderboard's), off the game's thread: the files are read once, a few MB */
        static const wchar_t kIo[] = L"\\IoStoreLoaderMod\\SurvivalMode";
        size_t k = WLen(g_modsDir);
        if (k && k + sizeof(kIo) / 2 < PATH_CAP) { memcpy(g_ioDir, g_modsDir, k * 2); memcpy(g_ioDir + k, kIo, sizeof(kIo)); }
        HANDLE bt = CreateThread(NULL, 0, BuildHashThread, NULL, 0, NULL);
        if (bt) CloseHandle(bt); else Log(L"leaderboard: could not start the build hash thread");
#endif
    }
    return mod;
}

EXPORT void uninstall_mod(void* mod)
{
    typedef void* (WINAPI *DeletingDtor)(void*, uint32_t);
    if (mod) ((DeletingDtor)(**(void***)mod))(mod, 1);
}

BOOL WINAPI DllMain(HANDLE module, DWORD reason, void* reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) { g_hModule = module; DisableThreadLibraryCalls(module); }
    return 1;
}
