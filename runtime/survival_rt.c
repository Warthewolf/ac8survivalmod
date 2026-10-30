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
 * ============================================================================= */

#include "win32_min.h"
#include "sigs.h"

#define RT_VERSION           L"0.32.1"
#define RT_VERSION_A         "0.32.1"      /* SV_Version()'s: keep in step with RT_VERSION */
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

static void VFmt(wchar_t* out, size_t cap, const wchar_t* fmt, va_list ap)
{
    wchar_t* p = out; wchar_t* end = out + cap - 1;
#define PUT(ch) do { if (p < end) *p++ = (wchar_t)(ch); } while (0)
    for (; *fmt; ++fmt) {
        if (*fmt != L'%') { PUT(*fmt); continue; }
        ++fmt;
        if (!*fmt) break;
        if (*fmt == L's') {
            const wchar_t* s = va_arg(ap, const wchar_t*);
            if (!s) s = L"<null>";
            while (*s) PUT(*s++);
        } else if (*fmt == L'd' || *fmt == L'u') {      /* (%u: 0.18.0's sound log used it and crashed: unknown here,
                                                           it took no argument, so the next %s read a number) */
            int32_t d = va_arg(ap, int32_t);
            uint64_t v = *fmt == L'u' ? (uint64_t)(uint32_t)d : d < 0 ? (uint64_t)(-(int64_t)d) : (uint64_t)d;
            if (*fmt == L'd' && d < 0) PUT(L'-');
            wchar_t t[24]; int n = 0;
            do { t[n++] = (wchar_t)(L'0' + v % 10); v /= 10; } while (v);
            while (n) PUT(t[--n]);
        } else if (*fmt == L'x' || *fmt == L'p') {
            uint64_t v = *fmt == L'p' ? (uint64_t)(uintptr_t)va_arg(ap, void*) : va_arg(ap, uint32_t);
            wchar_t t[16]; int n = 0;
            do { t[n++] = L"0123456789ABCDEF"[v & 15]; v >>= 4; } while (v);
            while (n) PUT(t[--n]);
        } else {
            PUT(*fmt);
        }
    }
    *p = 0;
#undef PUT
}

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
        WriteFile(g_log, utf8, (DWORD)n, &put, NULL);
        FlushFileBuffers(g_log);
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

/* ---- Survival's spawner (Milestone 2) ------------------------------------
 * How the game spawns (tools/re/SPAWN_SYSTEM.md): LiveReinforcementExecution calls SpawnUnitByName(spawner, name,
 * world data). That collects the world data's unit descs with that name, skips every desc whose UniqueID is still on
 * the phase's unit list, spawns the rest (unit actor + one AI object per AIObjectDesc, at the descs' SpawnPoints) and
 * fires their "reinforcement appeared" events. Nothing takes a shot-down flight off that list (only a phase's end
 * does), so a destroyed flight could not come back (probe tests 3-10).
 * Survival's own spawner, called from Scripts\main.lua (Lua globals, see the bridge further down): it takes a
 * shot-down flight off the list the way a phase end does (unregister + destroy its actor), moves the desc where Lua
 * wants it, sets its aircraft type, and calls the same SpawnUnitByName. Struct and property offsets come from the
 * game's reflection data through UE4SS; the two native-only ones are read out of the game's own code.           */
typedef struct { union { wchar_t buf[8]; wchar_t* ptr; } u; size_t size; size_t cap; } MsvcWString;
_Static_assert(sizeof(MsvcWString) == 32, "std::wstring layout");
typedef struct { uint8_t* data; int32_t num; int32_t max; } TArrayRaw;
typedef struct { const char* p; size_t n; } StrView;                       /* std::string_view  */
typedef struct { const wchar_t* p; size_t n; } WStrView;                   /* std::wstring_view */
typedef struct { union { char buf[16]; char* ptr; } u; size_t size; size_t cap; } MsvcString;  /* std::string */
_Static_assert(sizeof(MsvcString) == 32, "std::string layout");
typedef int (*LuaFn)(void* lua);

#define SV_ERR_REFUSED    0     /* the game spawned nothing                                    */
#define SV_ERR_NOT_READY -1     /* no spawner / phase / world data: not in Survival's level     */
#define SV_ERR_NO_UNIT   -2     /* no unit desc (or aircraft) of that name                      */
#define SV_ERR_UP        -3     /* that flight is still up                                      */
#define SV_ERR_BAD_ARGS  -4
#define SV_ERR_NO_GAME   -5     /* game functions or offsets not found (other game version?)   */
#define SV_ERR_LOADING   -6     /* Survival's level is still loading: its spawner has no world   */
#define SV_NOT_SPAWNED   -7     /* SV_UnitAlive: the flight isn't on the phase's list           */
#define WD_NAME          L"WD_SurvivalMode_global"
#define SPAWNER_UNIT_CLASS 0x2E8 /* ALiveUnitSpawner::UnitBPClass, read by SpawnUnits (0x147e19a40) */
#define RF_NOT_LIVE      (0x10 | 0x20 | 0x8000 | 0x10000 | 0x40000000)   /* CDO, archetype, being destroyed, garbage */

typedef void*    (*SpawnUnitFn)(void* spawner, const FNameRaw* name, void* worldData);
typedef void     (*UnregisterUnitFn)(void* phase, void* unit);
typedef uint8_t  (*DestroyActorFn)(void* actor, uint8_t netForce);
static SpawnUnitFn      g_spawnUnit;
static UnregisterUnitFn g_unregisterUnit;
static DestroyActorFn   g_destroyActor;
static uint8_t*         g_fUnitIdSpawned;

/* UE4SS 3.0.1 exports, by name: a missing one only turns the spawner off. */
static struct {
    void*     (*findObject)(const wchar_t* cls, const wchar_t* name, int32_t required, int32_t banned);
    void*     (*valuePtr)(void* obj, const wchar_t* prop);
    void**    (*childProps)(void* ustruct);
    void*     (*nextField)(void* field);
    FNameRaw* (*fieldName)(void* field);
    int32_t*  (*propOffset)(void* prop);
    int32_t*  (*elemSize)(void* prop);
    int32_t   (*structSize)(void* ustruct);
    void*     (*fname)(void* self, const wchar_t* s, int32_t findType, void* fnOverride);
    void*     (*nameToString)(const FNameRaw* self, MsvcWString* out);
    void      (*luaRegister)(void* lua, const MsvcString* name, const LuaFn* fn);
    uint8_t   (*luaIsString)(void* lua, int32_t idx);
    uint8_t   (*luaIsNumber)(void* lua, int32_t idx);
    StrView*  (*luaGetString)(void* lua, StrView* out, int32_t idx);
    double    (*luaGetNumber)(void* lua, int32_t idx);
    int32_t   (*luaStackSize)(void* lua);
    void      (*luaSetInteger)(void* lua, int64_t v);
    void      (*luaSetString)(void* lua, const char* s, size_t n);
} U;
static int g_ue4ss;              /* 0 not tried, 1 found, -1 missing */

static int ResolveUE4SS(void)
{
    if (g_ue4ss) return g_ue4ss > 0;
    static const struct { size_t off; const char* name; } kExports[] = {
#define UX(f, n) { __builtin_offsetof(__typeof__(U), f), n }
        UX(findObject,   "?FindObject@UObjectGlobals@Unreal@RC@@YAPEAVUObject@23@PEB_W0HH@Z"),
        UX(valuePtr,     "?GetValuePtrByPropertyNameInChain@UObject@Unreal@RC@@QEAAPEAXPEB_W@Z"),
        UX(childProps,   "?GetChildProperties@UStruct@Unreal@RC@@QEAAAEAPEAVFField@23@XZ"),
        UX(nextField,    "?GetNextFFieldUnsafe@FField@Unreal@RC@@AEAAPEAV123@XZ"),
        UX(fieldName,    "?GetNamePrivate@FField@Unreal@RC@@AEAAAEAVFName@23@XZ"),
        UX(propOffset,   "?GetOffset_Internal@FProperty@Unreal@RC@@QEAAAEAHXZ"),
        UX(elemSize,     "?GetElementSize@FProperty@Unreal@RC@@QEAAAEAHXZ"),
        UX(structSize,   "?GetStructureSize@UStruct@Unreal@RC@@QEBAHXZ"),
        UX(fname,        "??0FName@Unreal@RC@@QEAA@PEB_WW4EFindName@12@PEAX@Z"),
        UX(nameToString, "?ToString@FName@Unreal@RC@@QEBA?BV?$basic_string@_WU?$char_traits@_W@std@@V?$allocator@_W@2@@std@@XZ"),
        UX(luaRegister,  "?register_function@Lua@LuaMadeSimple@RC@@QEBAXAEBV?$basic_string@DU?$char_traits@D@std@@V?$allocator@D@2@@std@@AEBQ6AHAEBV123@@Z@Z"),
        UX(luaIsString,  "?is_string@Lua@LuaMadeSimple@RC@@QEBA_NH@Z"),
        UX(luaIsNumber,  "?is_number@Lua@LuaMadeSimple@RC@@QEBA_NH@Z"),
        UX(luaGetString, "?get_string@Lua@LuaMadeSimple@RC@@QEBA?AV?$basic_string_view@DU?$char_traits@D@std@@@std@@H@Z"),
        UX(luaGetNumber, "?get_number@Lua@LuaMadeSimple@RC@@QEBANH@Z"),
        UX(luaStackSize, "?get_stack_size@Lua@LuaMadeSimple@RC@@QEBAHXZ"),
        UX(luaSetInteger,"?set_integer@Lua@LuaMadeSimple@RC@@QEBAX_J@Z"),
        UX(luaSetString, "?set_string@Lua@LuaMadeSimple@RC@@QEBAXPEBD_K@Z"),
#undef UX
    };
    HANDLE ue4ss = GetModuleHandleW(L"UE4SS.dll");
    g_ue4ss = ue4ss ? 1 : -1;
    for (size_t i = 0; ue4ss && i < sizeof(kExports) / sizeof(kExports[0]); ++i) {
        void* f = GetProcAddress(ue4ss, kExports[i].name);
        if (!f) { Log(L"UE4SS export missing: %d; Survival's spawner is off", (int32_t)i); g_ue4ss = -1; }
        *(void**)((uint8_t*)&U + kExports[i].off) = f;
    }
    if (ue4ss && !g_findAllOf)
        g_findAllOf = (FindAllOfFn)GetProcAddress(ue4ss,
            "?FindAllOf@UObjectGlobals@Unreal@RC@@YAXPEB_WAEAV?$vector@PEAVUObject@Unreal@RC@@V?$allocator@PEAVUObject@Unreal@RC@@@std@@@std@@@Z");
    if (!g_findAllOf) g_ue4ss = -1;
    return g_ue4ss > 0;
}

static int NameEq(const FNameRaw* a, const FNameRaw* b) { return a->index == b->index && a->number == b->number; }

/* An existing FName (FNAME_Find: never adds one). False for a name the game doesn't have. */
static int MakeName(const wchar_t* s, FNameRaw* out)
{
    uint8_t buf[16];            /* room in case UE4SS's FName is wider than the game's 8 bytes */
    memset(buf, 0, sizeof(buf));
    U.fname(buf, s, 0, NULL);
    memcpy(out, buf, sizeof(*out));
    return out->index != 0 || out->number != 0;
}

/* The name as text, into out (cap chars). */
static const wchar_t* NameText(const FNameRaw* n, wchar_t* out, size_t cap)
{
    MsvcWString s; memset(&s, 0, sizeof(s));
    out[0] = 0;
    U.nameToString(n, &s);
    const wchar_t* p = s.cap > 7 ? s.u.ptr : s.u.buf;
    size_t k = s.size < cap - 1 ? s.size : cap - 1;
    if (p) { memcpy(out, p, k * 2); out[k] = 0; }
    if (s.cap > 7 && s.u.ptr) free(s.u.ptr);
    return out;
}

/* Offset of `field` in the reflected struct `structName` (its own fields), or -1; *size = the field's size. */
static int32_t StructField(const wchar_t* structName, const wchar_t* field, int32_t* size)
{
    void* st = U.findObject(L"ScriptStruct", structName, 0, 0);
    FNameRaw want;
    if (!st || !MakeName(field, &want)) return -1;
    void** head = U.childProps(st);
    for (void* f = head ? *head : NULL; f; f = U.nextField(f)) {
        FNameRaw* n = U.fieldName(f);
        if (n && NameEq(n, &want)) { if (size) *size = *U.elemSize(f); return *U.propOffset(f); }
    }
    return -1;
}

static int32_t StructSize(const wchar_t* structName)
{
    void* st = U.findObject(L"ScriptStruct", structName, 0, 0);
    return st ? U.structSize(st) : -1;
}

static struct {
    int     state;                          /* 0 not tried, 1 ok, -1 failed                 */
    int32_t descSize, aiSize;               /* LiveUnitDesc, LiveAIObjectDesc                */
    int32_t uniqueId, name;                 /* LiveDescBase                                  */
    int32_t aiList, uPoint, uRot;           /* LiveUnitDesc                                  */
    int32_t aiPoint, aiRot, aiNpc;          /* LiveAIObjectDesc                              */
    int32_t phaseWd;                        /* LivePhase.WorldData                           */
    int32_t unitList, unitCount;            /* phase: spawned units (FLivePhase::ManipulableObjects) */
    int32_t idIface, idSlot;                /* unit -> UniqueID: interface offset, vtable slot */
} LY;

static int ResolveLayout(void)
{
    if (LY.state) return LY.state > 0;
    if (!g_scanned) return 0;                       /* the signature scan is still running: ask again later */
    LY.state = -1;
    if (!g_fUnitIdSpawned) { Log(L"spawner: the game's unit check was not found (other game version?)"); return 0; }
    /* IsUnitIdSpawned: mov rbx,[rcx+list]; ... movsxd rax,[rcx+count]; ... add rcx,iface; mov rax,[rcx]; call [rax+slot] */
    const uint8_t* f = g_fUnitIdSpawned;
    LY.unitList  = *(const int32_t*)(f + 18);
    LY.unitCount = *(const int32_t*)(f + 27);
    for (int i = 35; i < 35 + 48; ++i) {
        if (f[i] == 0x48 && f[i + 1] == 0x81 && f[i + 2] == 0xC1 && !LY.idIface) LY.idIface = *(const int32_t*)(f + i + 3);
        if (f[i] == 0xFF && f[i + 1] == 0x50 && LY.idIface && !LY.idSlot) LY.idSlot = f[i + 2];
    }
    int32_t ptSize = 0, rotSize = 0, aiPtSize = 0;
    LY.descSize = StructSize(L"LiveUnitDesc");
    LY.aiSize   = StructSize(L"LiveAIObjectDesc");
    LY.uniqueId = StructField(L"LiveDescBase", L"UniqueID", NULL);
    LY.name     = StructField(L"LiveDescBase", L"Name", NULL);
    LY.aiList   = StructField(L"LiveUnitDesc", L"AIObjectDescList", NULL);
    LY.uPoint   = StructField(L"LiveUnitDesc", L"SpawnPoint", &ptSize);
    LY.uRot     = StructField(L"LiveUnitDesc", L"Rotation", &rotSize);
    LY.aiPoint  = StructField(L"LiveAIObjectDesc", L"SpawnPoint", &aiPtSize);
    LY.aiRot    = StructField(L"LiveAIObjectDesc", L"Rotation", NULL);
    LY.aiNpc    = StructField(L"LiveAIObjectDesc", L"MissionNpcID", NULL);
    LY.phaseWd  = StructField(L"LivePhase", L"WorldData", NULL);
    int32_t reflectedList = StructField(L"LivePhase", L"ManipulableObjects", NULL);   /* the same list, by name */
    Log(L"spawner layout: unit desc %x bytes (UniqueID +%x, Name +%x, AI list +%x, point +%x, rotation +%x), "
        L"AI desc %x bytes (point +%x, rotation +%x, NPC id +%x), phase world data +%x, phase units +%x/+%x, "
        L"unit id interface +%x slot +%x, vector %d bytes, LivePhase.ManipulableObjects +%x",
        (uint32_t)LY.descSize, (uint32_t)LY.uniqueId, (uint32_t)LY.name, (uint32_t)LY.aiList, (uint32_t)LY.uPoint,
        (uint32_t)LY.uRot, (uint32_t)LY.aiSize, (uint32_t)LY.aiPoint, (uint32_t)LY.aiRot, (uint32_t)LY.aiNpc,
        (uint32_t)LY.phaseWd, (uint32_t)LY.unitList, (uint32_t)LY.unitCount, (uint32_t)LY.idIface, (uint32_t)LY.idSlot, ptSize,
        (uint32_t)reflectedList);
    if (LY.descSize <= 0 || LY.aiSize <= 0 || LY.uniqueId < 0 || LY.name < 0 || LY.aiList < 0 || LY.uPoint < 0 ||
        LY.uRot < 0 || LY.aiPoint < 0 || LY.aiRot < 0 || LY.aiNpc < 0 || LY.phaseWd < 0 || !LY.idIface || !LY.idSlot ||
        LY.unitCount != LY.unitList + 8 || reflectedList != LY.unitList) {
        Log(L"spawner: layout incomplete; Survival's spawner is off");
        return 0;
    }
    if (ptSize != 24 || rotSize != 24 || aiPtSize != 24) {
        Log(L"spawner: positions are not double vectors (%d bytes); Survival's spawner is off", ptSize);
        return 0;
    }
    LY.state = 1;
    return 1;
}

/* The level's spawner, its global phase and Survival's world data (cached until the objects change). */
static void*    g_spawner;
static void*    g_spawnerVt;
static uint8_t* g_phase;
static void*    g_wd;
static FNameRaw g_wdName;

static int LiveObject(void* o)
{
    return o && Readable(o, 0x28) && !(*(uint32_t*)((uint8_t*)o + 8) & RF_NOT_LIVE);
}

static void* PhaseWorldData(uint8_t* phase)
{
    if (!phase || !Readable(phase + LY.phaseWd, 8)) return NULL;
    void* wd = *(void**)(phase + LY.phaseWd);
    return LiveObject(wd) && NameEq((FNameRaw*)((uint8_t*)wd + 0x18), &g_wdName) ? wd : NULL;   /* UObject::NamePrivate */
}

static int FindSpawner(void)
{
    if (!g_wdName.index && !MakeName(WD_NAME, &g_wdName)) return 0;      /* Survival's world data isn't loaded */
    if (g_spawner && LiveObject(g_spawner) && *(void**)g_spawner == g_spawnerVt && PhaseWorldData(g_phase) == g_wd)
        return 1;
    g_spawner = NULL; g_phase = NULL; g_wd = NULL;
    PtrVector v = { NULL, NULL, NULL };
    g_findAllOf(L"LiveUnitSpawner", &v);
    for (void** p = v.first; p && p < v.last && !g_spawner; ++p) {
        if (!LiveObject(*p)) continue;
        uint8_t* phase = (uint8_t*)U.valuePtr(*p, L"GlobalPhase");
        void* wd = PhaseWorldData(phase);
        if (!wd) continue;
        uint8_t* cls = (uint8_t*)U.valuePtr(*p, L"UnitBPClass");
        if (cls != (uint8_t*)*p + SPAWNER_UNIT_CLASS) {
            Log(L"spawner: LiveUnitSpawner.UnitBPClass is at +%x, the game's spawn code reads +%x; not used",
                (uint32_t)(cls - (uint8_t*)*p), (uint32_t)SPAWNER_UNIT_CLASS);
            continue;
        }
        g_spawner = *p; g_spawnerVt = *(void**)*p; g_phase = phase; g_wd = wd;
    }
    FreeVector(&v);
    if (g_spawner) Log(L"spawner: LiveUnitSpawner %p, global phase %p, world data %p", g_spawner, g_phase, g_wd);
    return g_spawner != NULL;
}

static int SpawnerReady(void)
{
    if (!ResolveUE4SS()) return SV_ERR_NO_GAME;
    if (!g_scanned) return SV_ERR_NOT_READY;       /* the signature scan is still running */
    if (!g_spawnUnit || !g_unregisterUnit || !g_destroyActor || !ResolveLayout()) return SV_ERR_NO_GAME;
    if (!FindSpawner()) return SV_ERR_NOT_READY;
    /* A spawner whose level isn't in a world yet (Survival's level still loading) spawns into no world: a co-op
     * joiner spawning the host's flights as its level loaded crashed in UWorld::SpawnActor reading world+0x30 (two
     * joiners' games, 2026-10-25, runtime 0.22.7). */
    void* world = VCall(g_spawner, VF_WORLD);
    if (!world || !LiveObject(world)) {
        static uint32_t said;
        if (said++ % 20 == 0) Log(L"spawner %p: no world yet (the level is still loading); spawns wait", g_spawner);
        return SV_ERR_LOADING;
    }
    return 1;
}

static uint8_t* FindDesc(const FNameRaw* name)
{
    TArrayRaw* a = (TArrayRaw*)U.valuePtr(g_wd, L"UnitDescList");
    if (!a || !a->data || a->num < 0 || a->num > 4096) return NULL;
    for (int32_t i = 0; i < a->num; ++i) {
        uint8_t* d = a->data + (size_t)i * (size_t)LY.descSize;
        if (NameEq((FNameRaw*)(d + LY.name), name)) return d;
    }
    return NULL;
}

static uint8_t* FindDescById(uint32_t id)
{
    TArrayRaw* a = (TArrayRaw*)U.valuePtr(g_wd, L"UnitDescList");
    if (!a || !a->data || a->num < 0 || a->num > 4096) return NULL;
    for (int32_t i = 0; i < a->num; ++i) {
        uint8_t* d = a->data + (size_t)i * (size_t)LY.descSize;
        if (*(uint32_t*)(d + LY.uniqueId) == id) return d;
    }
    return NULL;
}

static TArrayRaw* PhaseUnits(void)
{
    TArrayRaw* a = (TArrayRaw*)(g_phase + LY.unitList);
    if (!Readable(a, sizeof(*a)) || a->num < 0 || a->num > 4096 || a->num > a->max) return NULL;
    if (a->num && !Readable(a->data, (size_t)a->num * 8)) return NULL;
    return a;
}

static uint32_t UnitId(uint8_t* unit)
{
    uint8_t* iface = unit + LY.idIface;
    void** vt = *(void***)iface;
    if (!Readable(vt + LY.idSlot / 8, 8)) return 0;
    return ((uint32_t (*)(void*))vt[LY.idSlot / 8])(iface);
}

static uint8_t* RegisteredUnit(uint32_t id)
{
    TArrayRaw* a = PhaseUnits();
    for (int32_t i = 0; a && i < a->num; ++i) {
        uint8_t* u = ((uint8_t**)a->data)[i];
        if (u && Readable(u, LY.idIface + 8) && UnitId(u) == id) return u;
    }
    return NULL;
}

/* Number of entries in one of the unit's reflected arrays (AliveChildAIGameObjects, ChildAIGameObjects), -1 unknown. */
static int32_t UnitArrayNum(uint8_t* unit, const wchar_t* prop)
{
    TArrayRaw* a = (TArrayRaw*)U.valuePtr(unit, prop);
    return a && Readable(a, sizeof(*a)) ? a->num : -1;
}

/* Takes the desc's last flight off the phase's list if it was shot down. 1 removed, 0 none, -1 still up. */
static int Recycle(uint8_t* desc, const wchar_t* name)
{
    uint8_t* unit = RegisteredUnit(*(uint32_t*)(desc + LY.uniqueId));
    if (!unit) return 0;
    int32_t alive = UnitArrayNum(unit, L"AliveChildAIGameObjects");
    if (alive != 0) {
        Log(L"spawn %s: its last flight is still up (%d alive); not spawned again", name, alive);
        return -1;
    }
    g_unregisterUnit(g_phase, unit);
    g_destroyActor(unit, 0);
    Log(L"spawn %s: its last flight was shot down; took it off the phase's list and removed its unit actor", name);
    return 1;
}

static double Sin(double x)
{
    const double PI = 3.14159265358979323846;
    while (x > PI) x -= 2 * PI;
    while (x < -PI) x += 2 * PI;
    if (x > PI / 2) x = PI - x; else if (x < -PI / 2) x = -PI - x;
    double x2 = x * x, t = x, s = x;
    for (int k = 1; k < 10; ++k) { t *= -x2 / (double)((2 * k) * (2 * k + 1)); s += t; }
    return s;
}
static double Cos(double x) { return Sin(x + 1.57079632679489661923); }

/* Moves a unit desc and its AI objects' formation to (x, y, z) cm, facing yaw degrees. */
static void SetPose(uint8_t* desc, const double* pose)
{
    double* u = (double*)(desc + LY.uPoint);
    double* r = (double*)(desc + LY.uRot);                 /* FRotator: pitch, yaw, roll */
    double turn = pose[3] - r[1], c = Cos(turn * 3.14159265358979323846 / 180.0), s = Sin(turn * 3.14159265358979323846 / 180.0);
    TArrayRaw* ai = (TArrayRaw*)(desc + LY.aiList);
    for (int32_t i = 0; ai->data && i < ai->num && i < 64; ++i) {
        uint8_t* a = ai->data + (size_t)i * (size_t)LY.aiSize;
        double* p = (double*)(a + LY.aiPoint);
        double* q = (double*)(a + LY.aiRot);
        double dx = p[0] - u[0], dy = p[1] - u[1], dz = p[2] - u[2];
        p[0] = pose[0] + dx * c - dy * s;
        p[1] = pose[1] + dx * s + dy * c;
        p[2] = pose[2] + dz;
        q[1] += turn;
    }
    u[0] = pose[0]; u[1] = pose[1]; u[2] = pose[2];
    r[1] = pose[3];
}

static int64_t Spawn(const wchar_t* name, const double* pose)
{
    int ready = SpawnerReady();
    if (ready != 1) return ready;
    FNameRaw fn;
    uint8_t* desc = MakeName(name, &fn) ? FindDesc(&fn) : NULL;
    if (!desc) { Log(L"spawn %s: no unit of that name in %s", name, WD_NAME); return SV_ERR_NO_UNIT; }
    if (Recycle(desc, name) < 0) return SV_ERR_UP;
    if (pose) SetPose(desc, pose);
    uint8_t* unit = (uint8_t*)g_spawnUnit(g_spawner, &fn, g_wd);
    if (!unit) { Log(L"spawn %s: the game spawned nothing", name); return SV_ERR_REFUSED; }
    int32_t n = UnitArrayNum(unit, L"ChildAIGameObjects");
    int listed = RegisteredUnit(*(uint32_t*)(desc + LY.uniqueId)) == unit;
    const double* u = (const double*)(desc + LY.uPoint);
    Log(L"spawn %s: up, %d aircraft, at (%d, %d) m, %d m high, heading %d%s", name, n, (int32_t)(u[0] / 100),
        (int32_t)(u[1] / 100), (int32_t)(u[2] / 100), (int32_t)((const double*)(desc + LY.uRot))[1],
        listed ? L"" : L" (NOT on the phase list read here: shot-down flights can't be recycled)");
    return n > 0 ? n : 1;
}

/* Sets the aircraft (NPC table row, e.g. m29a_common) of the unit desc's AI objects: all, or only `index` (0-based). */
static int64_t SetAircraft(const wchar_t* name, const wchar_t* npc, int index)
{
    int ready = SpawnerReady();
    if (ready != 1) return ready;
    FNameRaw fn, npcName;
    uint8_t* desc = MakeName(name, &fn) ? FindDesc(&fn) : NULL;
    if (!desc || !MakeName(npc, &npcName)) { Log(L"aircraft %s -> %s: unknown unit or aircraft", name, npc); return SV_ERR_NO_UNIT; }
    TArrayRaw* ai = (TArrayRaw*)(desc + LY.aiList);
    int64_t set = 0;
    for (int32_t i = 0; ai->data && i < ai->num && i < 64; ++i) {
        if (index >= 0 && i != index) continue;
        memcpy(ai->data + (size_t)i * (size_t)LY.aiSize + LY.aiNpc, &npcName, sizeof(npcName));
        ++set;
    }
    return set;
}

/* Sets the AI level (LiveAIObjectDesc.LevelId, u16 at desc +0x78: 200 = level 2, every Mission 22 object's) of the
 * unit desc's AI objects, read by the planes it spawns as their AILevel (plane +0x1048, the value behaviour trees'
 * InstanceWeightProbabilityAILevel weigh: tools/re/BEHAVIOUR_NATIVE_LOGIC.md 6). Survival's ranks 6-10 use 3-5. */
#define AI_DESC_LEVEL 0x78
#define PLANE_AI_LEVEL 0x1048
static int64_t SetLevel(const wchar_t* name, int32_t level)
{
    int ready = SpawnerReady();
    if (ready != 1) return ready;
    FNameRaw fn;
    uint8_t* desc = MakeName(name, &fn) ? FindDesc(&fn) : NULL;
    if (!desc) return SV_ERR_NO_UNIT;
    if (level < 0 || level > 65535) return SV_ERR_BAD_ARGS;
    TArrayRaw* ai = (TArrayRaw*)(desc + LY.aiList);
    int64_t set = 0;
    for (int32_t i = 0; ai->data && i < ai->num && i < 64; ++i) {
        uint8_t* a = ai->data + (size_t)i * (size_t)LY.aiSize;
        if (AI_DESC_LEVEL + 2 > LY.aiSize || !Readable(a + AI_DESC_LEVEL, 2)) break;
        *(uint16_t*)(a + AI_DESC_LEVEL) = (uint16_t)level;
        ++set;
    }
    return set;
}

static int64_t UnitAlive(const wchar_t* name)
{
    int ready = SpawnerReady();
    if (ready != 1) return ready;
    FNameRaw fn;
    uint8_t* desc = MakeName(name, &fn) ? FindDesc(&fn) : NULL;
    if (!desc) return SV_ERR_NO_UNIT;
    uint8_t* unit = RegisteredUnit(*(uint32_t*)(desc + LY.uniqueId));
    return unit ? UnitArrayNum(unit, L"AliveChildAIGameObjects") : SV_NOT_SPAWNED;
}

/* Logs the phase's unit list (what blocks or allows a spawn); returns its length. */
static int64_t LogUnits(const wchar_t* why)
{
    int ready = SpawnerReady();
    if (ready != 1) { Log(L"units (%s): spawner not ready (%d)", why, ready); return ready; }
    TArrayRaw* a = PhaseUnits();
    if (!a) { Log(L"units (%s): the phase's unit list can't be read", why); return SV_ERR_NO_GAME; }
    Log(L"units (%s): %d on the phase's list", why, a->num);
    for (int32_t i = 0; i < a->num; ++i) {
        uint8_t* unit = ((uint8_t**)a->data)[i];
        if (!unit || !Readable(unit, LY.idIface + 8)) { Log(L"  #%d: %p (unreadable)", i, unit); continue; }
        uint32_t id = UnitId(unit);
        uint8_t* desc = FindDescById(id);
        wchar_t nm[96];
        Log(L"  #%d: %s (id %x), %d of %d aircraft alive", i, desc ? NameText((FNameRaw*)(desc + LY.name), nm, 96) : L"?",
            id, UnitArrayNum(unit, L"AliveChildAIGameObjects"), UnitArrayNum(unit, L"ChildAIGameObjects"));
    }
    return a->num;
}

/* ---- player ammo (Milestone 2 ammo cap; tools/re/AMMO.md) --------------------------------------------------
 * Copied from the stock LiveSetWeaponAmmoCount node: PlayerOwner(world) -> +0x16a8 = the player's weapon object W.
 * Gun / missiles / special 1 / special 2 are W's weapon slots ([W+0x2e8]: data +0x28, count +0x30, 0xa0 bytes each,
 * max +0x8, current +0xc) and are set together by SetWeaponAmmo(W, gun, main, sp1, sp2) (-1 for a missing slot);
 * flares are [W+0x2e0]+0xc4 (max W+0x27c), followed by FlareChanged([W+0x2e0]+0xb8). Every offset is read from the
 * node's own code at run time, so a patch that moves them is followed (or refused, with a log line).              */
#define AMMO_KINDS 5                /* 0 gun, 1 missiles, 2 special 1, 3 special 2, 4 flares (the node's enum)      */
typedef void* (*PlayerOwnerFn)(void* world);
typedef void  (*SetWeaponAmmoFn)(void* weapons, int32_t gun, int32_t main, int32_t sp1, int32_t sp2);
typedef void  (*FlareChangedFn)(void* p);
static uint8_t* g_fAmmoExecute;
static uint8_t* g_fAmmoFlare;
static uint8_t* g_fAmmoWeapons;
static uint8_t* g_fFreeRestock;

static struct {
    int             state;          /* 0 not tried, 1 ok, -1 failed */
    PlayerOwnerFn   owner;
    SetWeaponAmmoFn setFour;
    FlareChangedFn  flareChanged;
    int32_t weapons;                /* owner -> W                     */
    int32_t slots, slotData, slotNum, slotCur, slotStride;
    int32_t flareObj, flareCur, flareMax, flareNotify;
    int32_t restock;                /* free-restock flag on the flare object, -1 unknown */
} AM;

static uint8_t* Rel32(uint8_t* insn) { return insn + 5 + *(int32_t*)(insn + 1); }   /* call / jmp rel32 target */

static int ResolveAmmo(void)
{
    if (AM.state) return AM.state > 0;
    if (!g_scanned) return 0;                       /* the signature scan is still running: ask again later */
    AM.state = -1;
    uint8_t *ex = g_fAmmoExecute, *fl = g_fAmmoFlare, *wl = g_fAmmoWeapons;
    if (!ex || !fl || !wl) { Log(L"ammo: the game's ammo node was not found (other game version?)"); return 0; }
    if (ex[0x52] != 0xE8 || memcmp(ex + 0x60, "\x48\x8B\x80", 3) || wl[0x5f] != 0xE8 || fl[0x11] != 0xE8 ||
        fl[0x40] != 0xE9 || memcmp(fl + 0x16, "\x8B\x8A", 2) || memcmp(fl + 0x21, "\x48\x8B\x82", 3) ||
        memcmp(fl + 0x28, "\x89\x88", 2) || memcmp(fl + 0x35, "\x48\x81\xC1", 3)) {
        Log(L"ammo: the ammo node's code is not the expected shape; ammo control is off");
        return 0;
    }
    uint8_t* h = Rel32(fl + 0x11);                              /* count helper: weapon-slot layout */
    if (!InGame(h) || memcmp(h + 0x2d, "\x48\x8B\x82", 3) || h[0x34] != 0x83 || h[0x35] != 0x78 ||
        memcmp(h + 0x3a, "\x48\x8B\x40", 3) || h[0x3e] != 0x8B || h[0x3f] != 0x48 || h[0x5d] != 0x8B || h[0x5e] != 0x88) {
        Log(L"ammo: the ammo count helper is not the expected shape; ammo control is off");
        return 0;
    }
    AM.owner        = (PlayerOwnerFn)Rel32(ex + 0x52);
    AM.weapons      = *(int32_t*)(ex + 0x63);
    AM.setFour      = (SetWeaponAmmoFn)Rel32(wl + 0x5f);
    AM.flareMax     = *(int32_t*)(fl + 0x18);
    AM.flareObj     = *(int32_t*)(fl + 0x24);
    AM.flareCur     = *(int32_t*)(fl + 0x2a);
    AM.flareNotify  = *(int32_t*)(fl + 0x38);
    AM.flareChanged = (FlareChangedFn)Rel32(fl + 0x40);
    AM.slots        = *(int32_t*)(h + 0x30);
    AM.slotNum      = h[0x36];
    AM.slotData     = h[0x3d];
    AM.slotCur      = h[0x40];
    AM.slotStride   = *(int32_t*)(h + 0x5f) - AM.slotCur;      /* slot 1's current count minus slot 0's */
    uint8_t* rs = g_fFreeRestock;                               /* optional: only SV_SetFreeRestock needs it */
    AM.restock = rs && !memcmp(rs + 0x27, "\x48\x8B\x80", 3) && *(int32_t*)(rs + 0x2a) == AM.weapons &&
                 !memcmp(rs + 0x2e, "\x48\x8B\x88", 3) && *(int32_t*)(rs + 0x31) == AM.flareObj &&
                 rs[0x3e] == 0x88 && rs[0x3f] == 0x81 ? *(int32_t*)(rs + 0x40) : -1;
    Log(L"ammo layout: owner fn %p, weapons +%x, slots +%x (data +%x, count +%x, current +%x, max +%x, %x bytes each), "
        L"flares +%x (count +%x, max +%x, notify +%x, free restock +%x), set fn %p, flare fn %p",
        (void*)AM.owner, (uint32_t)AM.weapons, (uint32_t)AM.slots, (uint32_t)AM.slotData, (uint32_t)AM.slotNum,
        (uint32_t)AM.slotCur, (uint32_t)(AM.slotCur - 4), (uint32_t)AM.slotStride, (uint32_t)AM.flareObj,
        (uint32_t)AM.flareCur, (uint32_t)AM.flareMax, (uint32_t)AM.flareNotify, (uint32_t)AM.restock, (void*)AM.setFour,
        (void*)AM.flareChanged);
    if (!InGame((void*)AM.owner) || !InGame((void*)AM.setFour) || !InGame((void*)AM.flareChanged) ||
        AM.slotStride <= 0 || AM.slotStride > 0x400 || AM.slotCur < 4) {
        Log(L"ammo: layout implausible; ammo control is off");
        return 0;
    }
    AM.state = 1;
    return 1;
}

/* The player's weapon object W, or NULL (not in Survival's level, no player aircraft yet). */
static uint8_t* PlayerWeapons(void)
{
    if (!ResolveAmmo() || SpawnerReady() != 1) return NULL;
    void* world = VCall(g_spawner, VF_WORLD);
    if (!LiveObject(world)) return NULL;
    uint8_t* owner = (uint8_t*)AM.owner(world);
    if (!owner || !Readable(owner + AM.weapons, 8)) return NULL;
    uint8_t* w = *(uint8_t**)(owner + AM.weapons);
    if (!w || !Readable(w, AM.flareMax + 8) || !Readable(w + AM.slots, 8) || !Readable(w + AM.flareObj, 8)) return NULL;
    return w;
}

/* The weapon slot array: data and count, or NULL. */
static uint8_t* AmmoSlots(uint8_t* w, int32_t* num)
{
    uint8_t* s = *(uint8_t**)(w + AM.slots);
    if (!s || !Readable(s + AM.slotData, 8) || !Readable(s + AM.slotNum, 4)) return NULL;
    *num = *(int32_t*)(s + AM.slotNum);
    uint8_t* data = *(uint8_t**)(s + AM.slotData);
    if (*num < 0 || *num > 16 || (*num && !Readable(data, (size_t)*num * (size_t)AM.slotStride))) return NULL;
    return data;
}

/* Current (wantMax 0) or maximum (1) count of one kind; SV_NOT_SPAWNED for a slot the aircraft doesn't have. */
static int64_t AmmoGet(int kind, int wantMax)
{
    if (kind < 0 || kind >= AMMO_KINDS) return SV_ERR_BAD_ARGS;
    uint8_t* w = PlayerWeapons();
    if (!w) return AM.state < 0 ? SV_ERR_NO_GAME : SV_ERR_NOT_READY;
    if (kind == 4) {
        uint8_t* f = *(uint8_t**)(w + AM.flareObj);
        if (wantMax) return *(int32_t*)(w + AM.flareMax);
        return f && Readable(f + AM.flareCur, 4) ? *(int32_t*)(f + AM.flareCur) : SV_NOT_SPAWNED;
    }
    int32_t num = 0;
    uint8_t* data = AmmoSlots(w, &num);
    if (!data || kind >= num) return SV_NOT_SPAWNED;
    return *(int32_t*)(data + (size_t)kind * AM.slotStride + AM.slotCur - (wantMax ? 4 : 0));
}

/* Sets one kind's count to min(value, max); value < 0 = full. Returns the new count or an SV_ERR code. */
static int64_t AmmoSet(int kind, int32_t value)
{
    if (kind < 0 || kind >= AMMO_KINDS) return SV_ERR_BAD_ARGS;
    uint8_t* w = PlayerWeapons();
    if (!w) return AM.state < 0 ? SV_ERR_NO_GAME : SV_ERR_NOT_READY;
    if (kind == 4) {
        uint8_t* f = *(uint8_t**)(w + AM.flareObj);
        if (!f || !Readable(f + AM.flareCur, 4) || !Readable(f + AM.flareNotify, 8)) return SV_NOT_SPAWNED;
        int32_t max = *(int32_t*)(w + AM.flareMax);
        int32_t v = value < 0 || value > max ? max : value;
        *(int32_t*)(f + AM.flareCur) = v;
        AM.flareChanged(f + AM.flareNotify);
        return v;
    }
    int32_t num = 0, v4[4] = { -1, -1, -1, -1 };
    uint8_t* data = AmmoSlots(w, &num);
    if (!data || kind >= num) return SV_NOT_SPAWNED;
    for (int i = 0; i < 4 && i < num; ++i) v4[i] = *(int32_t*)(data + (size_t)i * AM.slotStride + AM.slotCur);
    int32_t max = *(int32_t*)(data + (size_t)kind * AM.slotStride + AM.slotCur - 4);
    v4[kind] = value < 0 || value > max ? max : value;
    AM.setFour(w, v4[0], v4[1], v4[2], v4[3]);
    return *(int32_t*)(data + (size_t)kind * AM.slotStride + AM.slotCur);
}

/* Turns the missiles' free restock on (1) or off (0), as LiveSetMissileFreeRestockEnabled does; returns the old value
 * or an SV_ERR code. */
static int64_t SetFreeRestock(int on)
{
    uint8_t* w = PlayerWeapons();
    if (!w) return AM.state < 0 ? SV_ERR_NO_GAME : SV_ERR_NOT_READY;
    if (AM.restock < 0) return SV_ERR_NO_GAME;
    uint8_t* f = *(uint8_t**)(w + AM.flareObj);
    if (!f || !Readable(f + AM.restock, 1)) return SV_NOT_SPAWNED;
    int64_t old = f[AM.restock];
    f[AM.restock] = on ? 1 : 0;
    return old;
}

/* Sets one kind's maximum (its full load) to max (1..9999), for the STORE's WEAPON BAYS and FLARE PODS upgrades: kinds
 * 1-3 the weapon slot's max (the int before its current count, as AmmoGet reads it), 4 the flares' (W + flareMax, the
 * activator's reflected MaxFlareCount). A current count above it comes down to it. Returns the new max or an SV_ERR
 * code. (Runtime 0.19.0; the game reads the max for its refills and caps, nothing sizes a buffer by it.) */
static int64_t AmmoSetMax(int kind, int32_t max)
{
    if (kind < 1 || kind >= AMMO_KINDS || max < 1 || max > 9999) return SV_ERR_BAD_ARGS;
    uint8_t* w = PlayerWeapons();
    if (!w) return AM.state < 0 ? SV_ERR_NO_GAME : SV_ERR_NOT_READY;
    if (kind == 4) {
        uint8_t* f = *(uint8_t**)(w + AM.flareObj);
        *(int32_t*)(w + AM.flareMax) = max;
        if (f && Readable(f + AM.flareCur, 4) && *(int32_t*)(f + AM.flareCur) > max) AmmoSet(4, max);
        return max;
    }
    int32_t num = 0;
    uint8_t* data = AmmoSlots(w, &num);
    if (!data || kind >= num) return SV_NOT_SPAWNED;
    uint8_t* slot = data + (size_t)kind * AM.slotStride;
    *(int32_t*)(slot + AM.slotCur - 4) = max;
    if (*(int32_t*)(slot + AM.slotCur) > max) AmmoSet(kind, max);
    return max;
}

/* ---- music and remote events (tools/re/MUSIC_RADIO_CAMERA.md, HUD_NOTES.md) ------------------------------------
 * SV_PlayBGM(event [, delay]) does what LivePlayBGMExecution does: the game's BGM controller fades out the track that
 * is playing and posts the new one (a track that is already playing is left alone), so rounds can change the music
 * and the game's pause / mute / supply handling keeps working. SV_Event(name) does what LiveCallRemoteEventExecution
 * does: it fires a remote event of Survival's event package, so Lua can run any stock node placed there (radio,
 * sounds, health bars). Both are decoded from the stock nodes' Execute bytes and work only in Survival's level.     */
typedef void*     (*ClassFn)(void);
typedef uint32_t* (*BgmPlayFn)(void* bgm, uint32_t* playingId, const FNameRaw* event, float delay);
typedef void      (*ArrayGrowFn)(void* array, int32_t oldNum);
typedef void*     (*EventManagerFn)(void* world);
typedef uint8_t   (*EventCheckFn)(void* event);
typedef void      (*EventDispatchFn)(void* manager, void* event, int32_t flags);
typedef void      (*VoidFn)(void);
typedef void      (*MallocFreeFn)(void* gmalloc, void* p);
static uint8_t* g_fBgmPlay;
static uint8_t* g_fRemoteEvent;

static struct {
    int       state;                /* 0 not tried, 1 ok, -1 failed */
    int32_t   gameInstance;         /* world -> game instance        */
    ClassFn   gameInstanceClass;    /* the class the node checks it against */
    int32_t   manager, quiet;       /* game instance -> BGM manager; manager byte the node clears */
    int32_t   controller;           /* manager -> BGM controller     */
    BgmPlayFn play;
    int32_t   lastId, playingId, status;   /* controller: id of the last post, id playing, status byte */
} BG;

static uint8_t* RipRel(uint8_t* insn, int len) { return insn + len + *(int32_t*)(insn + len - 4); }

static int ResolveBgm(void)
{
    if (BG.state) return BG.state > 0;
    if (!g_scanned) return 0;                       /* the signature scan is still running: ask again later */
    BG.state = -1;
    uint8_t* e = g_fBgmPlay;
    if (!e) { Log(L"music: the game's BGM node was not found (other game version?)"); return 0; }
    if (e[0x2a] != 0xE8 || memcmp(e + 0x2f, "\x48\x8B\x53\x10\x4C\x8D\x40\x30\x48\x63\x40\x38\x3B\x42\x38\x7F", 16) ||
        memcmp(e + 0x40, "\x48\x8B\xC8\x48\x8B\x42\x30\x4C\x39\x04\xC8\x74\x02\x33\xDB", 15) ||
        memcmp(e + 0x4f, "\x48\x8B\x8B", 3) || memcmp(e + 0x64, "\xC6\x81", 2) || e[0x6a] != 0 ||
        memcmp(e + 0x6b, "\x48\x8B\x89", 3) || e[0x72] != 0xE8) {
        Log(L"music: the BGM node's code is not the expected shape; music control is off");
        return 0;
    }
    BG.gameInstance      = *(int32_t*)(e + 0x21);
    BG.gameInstanceClass = (ClassFn)Rel32(e + 0x2a);
    BG.manager           = *(int32_t*)(e + 0x52);
    BG.quiet             = *(int32_t*)(e + 0x66);
    BG.controller        = *(int32_t*)(e + 0x6e);
    BG.play              = (BgmPlayFn)Rel32(e + 0x72);
    uint8_t* p = (uint8_t*)BG.play;                       /* optional: the controller's state, for SV_BGM */
    uint8_t* in = InGame(p) && p[0x6c] == 0xE8 ? Rel32(p + 0x6c) : NULL;
    BG.lastId    = InGame(p) && !memcmp(p + 0x73, "\x89\x8B", 2) ? *(int32_t*)(p + 0x75) : -1;
    BG.status    = in && InGame(in) && !memcmp(in + 0x7a, "\x80\xBF", 2) ? *(int32_t*)(in + 0x7c) : -1;
    BG.playingId = in && InGame(in) && !memcmp(in + 0x274, "\x8B\x97", 2) ? *(int32_t*)(in + 0x276) : -1;
    Log(L"music layout: game instance +%x (class fn %p), BGM manager +%x (flag +%x), controller +%x, play %p; "
        L"controller ids +%x / +%x, status +%x", (uint32_t)BG.gameInstance, (void*)BG.gameInstanceClass,
        (uint32_t)BG.manager, (uint32_t)BG.quiet, (uint32_t)BG.controller, (void*)BG.play, (uint32_t)BG.lastId,
        (uint32_t)BG.playingId, (uint32_t)BG.status);
    if (!InGame((void*)BG.gameInstanceClass) || !InGame((void*)BG.play)) {
        Log(L"music: layout implausible; music control is off");
        return 0;
    }
    BG.state = 1;
    return 1;
}

/* The BGM controller of Survival's level, or NULL; play = 1 clears the manager byte as the node does before a post. */
static uint8_t* BgmController(int play)
{
    if (!ResolveBgm() || SpawnerReady() != 1) return NULL;
    uint8_t* world = (uint8_t*)VCall(g_spawner, VF_WORLD);
    if (!LiveObject(world) || !Readable(world + BG.gameInstance, 8)) return NULL;
    uint8_t* gi = *(uint8_t**)(world + BG.gameInstance);
    if (!gi || !Readable(gi + 0x10, 8) || !Readable(gi + BG.manager, 8)) return NULL;
    uint8_t* cls = *(uint8_t**)(gi + 0x10);                         /* the node's IsA check, as it does it */
    uint8_t* want = (uint8_t*)BG.gameInstanceClass();
    if (!cls || !want || !Readable(cls + 0x30, 0xC) || !Readable(want + 0x30, 0xC)) return NULL;
    int32_t depth = *(int32_t*)(want + 0x38);
    uint8_t** chain = *(uint8_t***)(cls + 0x30);
    if (depth < 0 || depth > *(int32_t*)(cls + 0x38) || !Readable(chain + depth, 8) || chain[depth] != want + 0x30) {
        static int logged;
        if (!logged) { logged = 1; Log(L"music: the game instance is not the class the BGM node expects"); }
        return NULL;
    }
    uint8_t* mgr = *(uint8_t**)(gi + BG.manager);
    if (!mgr || !Readable(mgr + BG.quiet, 1) || !Readable(mgr + BG.controller, 8)) return NULL;
    uint8_t* bgm = *(uint8_t**)(mgr + BG.controller);
    if (!bgm || !Readable(bgm, 0x200)) return NULL;
    if (play) mgr[BG.quiet] = 0;
    return bgm;
}

/* Posts a BGM event (e.g. AKE_Bgm_Ms24A_Play) through the game's controller; delay 0 = the game's own delay table.
 * Returns the Wwise playing id (0: refused, already playing, or queued) or an SV_ERR code. */
static int64_t PlayBgm(const wchar_t* event, float delay)
{
    if (!ResolveBgm()) return SV_ERR_NO_GAME;
    FNameRaw n;
    if (!MakeName(event, &n)) return SV_ERR_NO_UNIT;              /* no such name: not a loaded Wwise event */
    uint8_t* bgm = BgmController(1);
    if (!bgm) return SV_ERR_NOT_READY;
    uint32_t id = 0;
    BG.play(bgm, &id, &n, delay);
    Log(L"music: %s posted (playing id %d)", event, (int32_t)id);
    return id;
}

/* SV_BGM(field): 0 = playing id, 1 = status byte, 2 = id of the last post; or an SV_ERR code. */
static int64_t BgmState(int field)
{
    int32_t off = field == 0 ? BG.playingId : field == 1 ? BG.status : field == 2 ? BG.lastId : -1;
    if (!ResolveBgm()) return SV_ERR_NO_GAME;
    if (off < 0) return SV_ERR_BAD_ARGS;
    uint8_t* bgm = BgmController(0);
    if (!bgm || !Readable(bgm + off, 4)) return SV_ERR_NOT_READY;
    return field == 1 ? (int64_t)bgm[off] : (int64_t)*(uint32_t*)(bgm + off);
}

static struct {
    int             state;
    void*           vtable;         /* the remote event's vtable    */
    void*           baseVtable;     /* put back before freeing       */
    ArrayGrowFn     grow;           /* TArray<uint8> allocation      */
    uint8_t         type;           /* the event's one type byte     */
    EventManagerFn  manager;        /* world -> event manager        */
    void*           defaultCheck;   /* vtable slot that needs no call */
    int32_t         checkSlot;
    EventDispatchFn dispatch;
    void**          gmalloc;
    VoidFn          createMalloc;
    int32_t         freeSlot;
} EV;

typedef struct { void* vtable; uint8_t* data; int32_t num, max; FNameRaw name; uint8_t spare[0x20]; } RemoteEventRaw;

static int ResolveEvent(void)
{
    if (EV.state) return EV.state > 0;
    if (!g_scanned) return 0;                       /* the signature scan is still running: ask again later */
    EV.state = -1;
    uint8_t* e = g_fRemoteEvent;
    if (!e) { Log(L"events: the game's remote-event node was not found (other game version?)"); return 0; }
    if (memcmp(e + 0x19, "\x48\x8D\x05", 3) || e[0x49] != 0xE8 || memcmp(e + 0x56, "\xC6\x00", 2) ||
        memcmp(e + 0x65, "\xFF\x90\x88\x01\x00\x00", 6) || e[0x6e] != 0xE8 || memcmp(e + 0x7b, "\x48\x8D\x05", 3) ||
        memcmp(e + 0x82, "\x48\x8B\x51", 3) || e[0xaa] != 0xE8 || memcmp(e + 0xb4, "\x48\x8D\x05", 3) ||
        memcmp(e + 0xca, "\x48\x8B\x0D", 3) || e[0xd6] != 0xE8 || memcmp(e + 0xe8, "\xFF\x50", 2)) {
        Log(L"events: the remote-event node's code is not the expected shape; SV_Event is off");
        return 0;
    }
    EV.vtable       = RipRel(e + 0x19, 7);
    EV.grow         = (ArrayGrowFn)Rel32(e + 0x49);
    EV.type         = e[0x58];
    EV.manager      = (EventManagerFn)Rel32(e + 0x6e);
    EV.defaultCheck = RipRel(e + 0x7b, 7);
    EV.checkSlot    = e[0x85];
    EV.dispatch     = (EventDispatchFn)Rel32(e + 0xaa);
    EV.baseVtable   = RipRel(e + 0xb4, 7);
    EV.gmalloc      = (void**)RipRel(e + 0xca, 7);
    EV.createMalloc = (VoidFn)Rel32(e + 0xd6);
    EV.freeSlot     = e[0xea];
    Log(L"events layout: event vtable %p (type %x, check slot +%x), manager fn %p, dispatch %p, GMalloc %p (free +%x)",
        EV.vtable, (uint32_t)EV.type, (uint32_t)EV.checkSlot, (void*)EV.manager, (void*)EV.dispatch, (void*)EV.gmalloc,
        (uint32_t)EV.freeSlot);
    if (!InGame(EV.vtable) || !InGame((void*)EV.grow) || !InGame((void*)EV.manager) || !InGame((void*)EV.dispatch) ||
        !InGame(EV.gmalloc) || !Readable((void**)EV.vtable + EV.checkSlot / 8, 8)) {
        Log(L"events: layout implausible; SV_Event is off");
        return 0;
    }
    EV.state = 1;
    return 1;
}

/* Fires remote event `name` in Survival's level. 1 = dispatched (whether or not any trigger listens), or an SV_ERR. */
static int64_t FireEvent(const wchar_t* name)
{
    if (!ResolveEvent()) return SV_ERR_NO_GAME;
    FNameRaw n;
    if (!MakeName(name, &n)) return SV_ERR_NO_UNIT;              /* no trigger can have a name the game doesn't */
    if (SpawnerReady() != 1) return SV_ERR_NOT_READY;
    void* world = VCall(g_spawner, VF_WORLD);
    if (!LiveObject(world)) return SV_ERR_NOT_READY;
    void* mgr = EV.manager(world);
    if (!mgr) return SV_ERR_NOT_READY;
    RemoteEventRaw ev;
    memset(&ev, 0, sizeof(ev));
    ev.vtable = EV.vtable;
    ev.num = 1;
    EV.grow(&ev.data, 0);
    if (!ev.data) return SV_ERR_NO_GAME;
    ev.data[0] = EV.type;
    ev.name = n;
    void* check = ((void**)ev.vtable)[EV.checkSlot / 8];
    int32_t flags = check == EV.defaultCheck ? 0 : (((EventCheckFn)check)(&ev) ? 0 : 2);
    EV.dispatch(mgr, &ev, flags);
    ev.vtable = EV.baseVtable;
    void** gm = (void**)*EV.gmalloc;
    if (!gm) { EV.createMalloc(); gm = (void**)*EV.gmalloc; }
    if (gm && ev.data) ((MallocFreeFn)(*(void***)gm)[EV.freeSlot / 8])(gm, ev.data);
    return 1;
}

/* ---- the pause menu's music player (tools/re/MUSIC_RADIO_CAMERA.md section B) ----------------------------------
 * The stock pause list has free flight's Music Player row; outside free flight the game builds it with
 * {"PauseMusicPlayer"} invalid, which hides it. While Survival's mission runs, the hook passes the same list without
 * that entry and with free flight's two (restart checkpoint, select difficulty) instead (a copy: the function only
 * reads it), so the row shows and the list still fits its 6 row widgets. A grey-out call (grayout = 1) is left alone. */
typedef void (*PauseValidityFn)(void* ctx, TArrayRaw* invalid, uintptr_t grayout);
static uint8_t*        g_fPauseValidity;
static PauseValidityFn g_nextPauseValidity;
static volatile int32_t g_musicPlayer = 1;          /* SV_PauseMusicPlayer(on) */
static volatile int32_t g_musicPlayerShown;

static int InSurvivalMission(void* obj)
{
    uint8_t* ctx = Context(obj);
    return ctx && *(int32_t*)(ctx + CTX_MISSION_ID) == SURVIVAL_MISSION_ID;
}

/* ---- the music player's track clock (tools/re/MUSIC_RADIO_CAMERA.md "Track skips in Survival") -------------------
 * A ULiveMenuMusicControlObject (the music player's SoundController) times its track itself: its tickable's Tick adds the
 * real frame time to +0x58 and plays the next track once that reaches the track's length +0x5C. The engine ticks it while
 * the game is paused, when the BGM channel (and with it the track) is paused too; free flight re-posts the track at the
 * clock when its pause menu closes, other modes don't, so in Survival every pause cut the playing track short by the time
 * paused (user, 2026-10-22: "music skipped on round change"). While Survival's mission runs and LiveSoundManager's BGM
 * channel is paused, the clock is held. PlayNext is logged with its caller and the clock, to confirm it in a test.
 * Until 0.28.4 the game instance came from the controller's Outer chain (controller -> manager -> game instance) and
 * the hold never came on: every PlayNext of every test log read "clock held 0 ms", and the user's 24 s pause of
 * 2026-10-29 cut the playing track 24 s short ("song skipped randomly"). Now it's the game instance of Survival's
 * level, from the spawner Lua's calls keep found (as BgmController), and the manager PlayNext is called on. */
#define UOBJ_OUTER        0x20
#define GI_SOUND_MANAGER  0x908          /* LiveSoundManager                                                     */
#define SM_CHANNELS       0x78           /* its channel data: 8 bytes each (SFX, Voice, BGM), +7 = paused now     */
#define SM_BGM_PAUSED     0x17
#define MPM_CONTROLLER    0x100          /* ULiveMusicPlayerSoundManager.SoundController                          */
#define MPC_CLOCK         0x58           /* float seconds into the track                                          */
#define MPC_LENGTH        0x5C           /* float seconds                                                         */
typedef void (*MusicTickFn)(void* tickable, float dt);
typedef void (*MusicNextFn)(void* manager);
static uint8_t*     g_fMusicTick;
static uint8_t*     g_fMusicNext;
static MusicTickFn  g_nextMusicTick;
static MusicNextFn  g_nextMusicNext;
static volatile int32_t g_musicClockHold = 1;     /* SV_MusicClock(on) */
static volatile int32_t g_musicForceHold;         /* SV_MusicHold(on): Lua holds it (the landing store)             */
static int32_t      g_musicHeldMs;                /* clock held since the last track change                        */
static int32_t      g_musicHolding;               /* the SoundController's clock is held now                       */
static uint8_t*     g_musicMgr;                   /* the music player manager (PlayNext's, or the controller's Outer) */
static uint8_t*     g_musicGiSeen;                /* the Survival game instance last logged (once a level)          */

static uint8_t* PtrAt(uint8_t* p, size_t off)
{
    return p && Readable(p + off, 8) ? *(uint8_t**)(p + off) : NULL;
}

static int32_t Ms(float s) { return (int32_t)(s * 1000.0f); }

/* The game instance while Survival's mission runs, else NULL: its level's spawner (found and kept by Lua's SV_* calls;
 * never searched for here, every frame and in the menus too) -> world -> game instance, its context's mission ours. */
static uint8_t* MusicSurvivalGi(void)
{
    if (!g_spawner || !LiveObject(g_spawner) || *(void**)g_spawner != g_spawnerVt) return NULL;
    uint8_t* world = (uint8_t*)VCall(g_spawner, VF_WORLD);
    if (!world || !LiveObject(world)) return NULL;
    uint8_t* gi = PtrAt(world, WORLD_GAME_INSTANCE);
    uint8_t* ctx = PtrAt(gi, GI_CAMPAIGN_CONTEXT);
    if (!ctx || !Readable(ctx + CTX_MISSION_ID, 4) || *(int32_t*)(ctx + CTX_MISSION_ID) != SURVIVAL_MISSION_ID) return NULL;
    return gi;
}

static void CoopFrame(int fromMusic);            /* coop.c: Survival COOP's per-frame work */

static void OnMusicTick(void* tickable, float dt)
{
    CoopFrame(1);
    if (g_musicClockHold) {
        uint8_t* co = (uint8_t*)tickable - 0x28;
        uint8_t* outer = PtrAt(co, UOBJ_OUTER);
        if (!g_musicMgr && PtrAt(outer, MPM_CONTROLLER) == co) g_musicMgr = outer;
        static int said;
        if (!said) {                                      /* (the test of 2026-10-25 never saw this tick in a mission) */
            said = 1;
            Log(L"music player clock: ticking (controller %p, its Outer %p %s the manager)", co, outer,
                g_musicMgr == outer ? L"is" : L"isn't");
        }
        uint8_t* gi = MusicSurvivalGi();
        uint8_t* ch = PtrAt(PtrAt(gi, GI_SOUND_MANAGER), SM_CHANNELS);
        int paused = ch && Readable(ch + SM_BGM_PAUSED, 1) && ch[SM_BGM_PAUSED];
        if (gi != g_musicGiSeen) {
            g_musicGiSeen = gi;
            if (gi) Log(L"music player clock: Survival's mission (game instance %p, sound channels %p, BGM %s)", gi, ch,
                        paused ? L"paused" : L"playing");
        }
        /* (user, 2026-10-24: "music skipped": the landing store plays its own supply music without pausing the BGM
         * channel, so the track's clock ran out in the store; Lua holds it there with SV_MusicHold) */
        int hold = gi && (g_musicForceHold || paused);
        /* the SoundController (the manager's +0x100; the ambience controller is held too); before the manager is known,
         * a controller with a track that's playing */
        int track = g_musicMgr ? PtrAt(g_musicMgr, MPM_CONTROLLER) == co
                               : Readable(co + MPC_CLOCK, 0xD) && *(float*)(co + MPC_LENGTH) > 0 && !co[0x64];
        if (track && hold != g_musicHolding && Readable(co + MPC_CLOCK, 8)) {
            g_musicHolding = hold;
            Log(L"music player: BGM %s, track clock %s at %d of %d ms", hold ? (g_musicForceHold ? L"held by Survival" : L"paused") : L"playing again",
                hold ? L"held" : L"running", Ms(*(float*)(co + MPC_CLOCK)), Ms(*(float*)(co + MPC_LENGTH)));
        }
        if (hold) {
            if (track) g_musicHeldMs += Ms(dt);
            return;
        }
    }
    g_nextMusicTick(tickable, dt);
}

static void OnMusicNext(void* manager)
{
    uint8_t* ret = (uint8_t*)__builtin_return_address(0);
    g_musicMgr = (uint8_t*)manager;
    uint8_t* co = PtrAt((uint8_t*)manager, MPM_CONTROLLER);
    int32_t clock = -1, length = -1;
    if (co && Readable(co + MPC_CLOCK, 8)) { clock = Ms(*(float*)(co + MPC_CLOCK)); length = Ms(*(float*)(co + MPC_LENGTH)); }
    Log(L"music player: next track (caller %p = exe+%x; clock %d of %d ms; clock held %d ms during this track)",
        ret, (uint32_t)(ret - g_exe), clock, length, g_musicHeldMs);
    g_musicHeldMs = 0;
    g_nextMusicNext(manager);
}

/* The Anomaly's field (tools/re/SPECIAL_ROUNDS.md 13): BuildFlightInput(ALivePlayerPlane*, FPlaneInput* out) packs the
 * plane's controls into the flight engine's input every frame: out+0x0 pitch, +0x4 yaw (right rudder - left), +0x8 roll
 * (each clamped to -1..1), +0xC throttle, +0x10 brake (0..1), +0x14 the high-G turn (from throttle + brake, or brake on
 * the single-button option: left as built), +0x18 flags (disassembly of 2026-10-24). The detour runs it, then, on the
 * plane Lua named, applies the field's effects, each fading over the fade time by a factor from 1 (off) to -1 (on):
 * pitch / roll / yaw inverted (times the factor), pitch and roll swapped, throttle and brake swapped (blended
 * (1 - factor) / 2 of the way to the other). The struct is rebuilt every call, so nothing can apply twice. Then (runtime
 * 0.28.5) flight.c's FlightInputHook: while DOWN its autopilot replaces the local plane's pitch, yaw, roll, throttle and
 * brake, and SV_InputNow's record of what each plane's flight engine got. */
enum { INV_PITCH, INV_ROLL, INV_YAW, INV_SWAP_AXES, INV_SWAP_THROTTLE, INV_N };
typedef void (*BuildInputFn)(uint8_t* plane, float* out);
static uint8_t*      g_fBuildInput;
static BuildInputFn  g_nextBuildInput;
static uint8_t* volatile g_invPlane;                /* the player's plane (SV_Invert), or NULL */
static volatile int32_t  g_invWant[INV_N];          /* 1 = that effect on */
static volatile int32_t  g_invFadeMs = 1500;
static float         g_invScale[INV_N] = { 1.0f, 1.0f, 1.0f, 1.0f, 1.0f };
static uint64_t      g_invLastMs;

static void FlightInputHook(uint8_t* plane, float* out);   /* flight.c: DOWN's autopilot, SV_InputNow's record */
static void InvertInput(float* out);

static void OnBuildInput(uint8_t* plane, float* out)
{
    g_nextBuildInput(plane, out);
    CoopFrame(0);                                    /* (only when the music player's tick doesn't run) */
    if (plane && out && plane == g_invPlane) InvertInput(out);
    FlightInputHook(plane, out);                     /* (DOWN last: its autopilot is never inverted) */
}

static void InvertInput(float* out)
{
    uint64_t now = GetTickCount64();
    float step = g_invLastMs && now > g_invLastMs ? (float)(now - g_invLastMs) * 2.0f / (float)(g_invFadeMs > 0 ? g_invFadeMs : 1) : 0.0f;
    if (now - g_invLastMs > 1000) step = 0.0f;           /* first frame after a pause: no jump */
    g_invLastMs = now;
    for (int a = 0; a < INV_N; ++a) {
        float want = g_invWant[a] ? -1.0f : 1.0f, s = g_invScale[a];
        if (g_invFadeMs <= 0) s = want;
        else if (s < want) { s += step; if (s > want) s = want; }
        else if (s > want) { s -= step; if (s < want) s = want; }
        g_invScale[a] = s;
    }
    float pitch = out[0] * g_invScale[INV_PITCH], yaw = out[1] * g_invScale[INV_YAW], roll = out[2] * g_invScale[INV_ROLL];
    float u = (1.0f - g_invScale[INV_SWAP_AXES]) * 0.5f, t = (1.0f - g_invScale[INV_SWAP_THROTTLE]) * 0.5f;
    float thr = out[3], brk = out[4];
    out[0] = pitch * (1.0f - u) + roll * u;
    out[1] = yaw;
    out[2] = roll * (1.0f - u) + pitch * u;
    out[3] = thr * (1.0f - t) + brk * t;
    out[4] = brk * (1.0f - t) + thr * t;
}

static void OnPauseValidity(void* ctx, TArrayRaw* list, uintptr_t grayout)
{
    if (g_musicPlayer && !(grayout & 0xFF) && list && list->num > 0 && list->num <= 16 &&
        Readable(list->data, (size_t)list->num * sizeof(FString)) && Readable(ctx, 8) && InSurvivalMission(*(void**)ctx)) {
        static const wchar_t kMusic[] = L"PauseMusicPlayer";
        FString kept[16];
        int32_t n = 0, removed = 0;
        const FString* a = (const FString*)list->data;
        for (int32_t i = 0; i < list->num; ++i) {
            if (a[i].data && a[i].num == 17 && Readable(a[i].data, 34) && !memcmp(a[i].data, kMusic, 34)) ++removed;
            else kept[n++] = a[i];
        }
        if (removed) {
            /* The pause list has 6 row widgets: a 7th row (QUIT GAME under the music player) stays selectable but isn't
             * drawn (test of 2026-10-22). Free flight hides these two to make room; Survival has no checkpoints, and a
             * difficulty change mid-run would change its ammo preset, so it hides them too. */
            static const wchar_t kCheckpoint[] = L"PauseRestartCheckPoint", kDifficulty[] = L"PauseSelectDifficulty";
            static const FString kHide[2] = {
                { (wchar_t*)kCheckpoint, (int32_t)(sizeof(kCheckpoint) / 2), (int32_t)(sizeof(kCheckpoint) / 2) },
                { (wchar_t*)kDifficulty, (int32_t)(sizeof(kDifficulty) / 2), (int32_t)(sizeof(kDifficulty) / 2) },
            };
            for (int h = 0; h < 2 && n < 16; ++h) {
                int have = 0;
                for (int32_t i = 0; i < n; ++i)
                    if (kept[i].data && kept[i].num == kHide[h].num && Readable(kept[i].data, (size_t)kHide[h].num * 2) &&
                        !memcmp(kept[i].data, kHide[h].data, (size_t)kHide[h].num * 2)) have = 1;
                if (!have) kept[n++] = kHide[h];
            }
            TArrayRaw tmp = { (uint8_t*)kept, n, n };
            if (!g_musicPlayerShown) {
                g_musicPlayerShown = 1;
                Log(L"pause menu: the music player row shown, restart checkpoint and select difficulty hidden (Survival's mission)");
            }
            g_nextPauseValidity(ctx, &tmp, grayout);
            return;
        }
    }
    g_nextPauseValidity(ctx, list, grayout);
}

/* ---- the game's own Lua (behaviour scripts; tools/re/GAME_LUA.md) ----------------------------------------------
 * AceCombat8.exe embeds Lua 5.3 for its AI behaviour scripts and exports the whole C API by name (lua_pcallk,
 * luaL_loadbufferx, ...). Its one state lives in the plugin's SingleGameluaContext; GetGameLuaState() returns it
 * (and creates the context if it is missing, so it is never called here: the static slot is decoded and read).
 * SV_GameLua(code [, name]) runs a chunk in that state under pcall with a traceback handler and returns
 * "<status>\t<result>": status 0 = ok (result = the chunk's first return value as text), a Lua error code (2 run
 * time, 3 syntax, 4 memory, 6 handler) with the message, or -1 not ready / -5 game code not found. Errors in the
 * game's own behaviour scripts are swallowed by the plugin (its log is stripped from the shipping game), so this is
 * Survival's only window into that Lua. Runs on the game thread (main.lua's tick), never inside a game Lua call.  */
typedef int (*Lua53CFn)(void* L);
static uint8_t* g_fGameLuaState;
static struct {
    int          state;            /* 0 not tried, 1 ok, -1 failed */
    void**       slot;             /* &SingleGameluaContext*        */
    int         (*loadbufferx)(void* L, const char* buf, size_t n, const char* name, const char* mode);
    int         (*pcallk)(void* L, int nargs, int nresults, int errfunc, intptr_t ctx, void* k);
    int         (*gettop)(void* L);
    void        (*settop)(void* L, int idx);
    int         (*type)(void* L, int idx);
    const char* (*typename_)(void* L, int tp);
    const char* (*tolstring)(void* L, int idx, size_t* len);
    void        (*pushcclosure)(void* L, Lua53CFn fn, int n);
    void        (*traceback)(void* L, void* L1, const char* msg, int level);
    int         (*checkstack)(void* L, int n);
} GL;

static int ResolveGameLua(void)
{
    if (GL.state) return GL.state > 0;
    if (!g_scanned) return 0;                       /* the signature scan is still running: ask again later */
    GL.state = -1;
    HANDLE exe = (HANDLE)g_exe;
    static const struct { size_t off; const char* name; } kApi[] = {
#define GX(f, n) { __builtin_offsetof(__typeof__(GL), f), n }
        GX(loadbufferx, "luaL_loadbufferx"), GX(pcallk, "lua_pcallk"), GX(gettop, "lua_gettop"),
        GX(settop, "lua_settop"), GX(type, "lua_type"), GX(typename_, "lua_typename"),
        GX(tolstring, "lua_tolstring"), GX(pushcclosure, "lua_pushcclosure"), GX(traceback, "luaL_traceback"),
        GX(checkstack, "lua_checkstack"),
#undef GX
    };
    for (size_t i = 0; i < sizeof(kApi) / sizeof(kApi[0]); ++i) {
        void* f = exe ? (void*)GetProcAddress(exe, kApi[i].name) : NULL;
        if (!f) { Log(L"game Lua: export %d missing (other game version?); no game Lua bridge", (int32_t)i); return 0; }
        *(void**)((uint8_t*)&GL + kApi[i].off) = f;
    }
    uint8_t* g = g_fGameLuaState;
    if (!g || g[6] != 0xE8) { Log(L"game Lua: GetGameLuaState not found; no game Lua bridge"); return 0; }
    uint8_t* slotFn = Rel32(g + 6);
    uint8_t* lea = slotFn + 0x20;
    if (!InGame(lea) || lea[0] != 0x48 || lea[1] != 0x8D || lea[2] != 0x05) {
        Log(L"game Lua: context slot code changed (%p); no game Lua bridge", slotFn);
        return 0;
    }
    GL.slot = (void**)RipRel(lea, 7);
    if (!InGame(GL.slot)) { Log(L"game Lua: context slot %p outside the game; no game Lua bridge", (void*)GL.slot); return 0; }
    Log(L"game Lua: Lua 5.3 API from the game's exports (pcallk %p), context slot %p", (void*)GL.pcallk, (void*)GL.slot);
    GL.state = 1;
    return 1;
}

/* The game's lua_State, or NULL while the plugin hasn't made its context. */
static void* GameLuaState(void)
{
    if (!ResolveGameLua()) return NULL;
    void* ctx = *GL.slot;
    if (!ctx || !Readable(ctx, 8)) return NULL;
    void* L = *(void**)ctx;
    return L && Readable(L, 0x40) ? L : NULL;
}

static int GameLuaHandler(void* L)            /* message handler: the error plus a traceback */
{
    const char* msg = GL.tolstring(L, 1, NULL);
    GL.traceback(L, L, msg ? msg : "(error is not a string)", 1);
    return 1;
}

/* Runs code in the game's Lua; writes the first result (or the error) to out. Returns the status (see above). */
static int GameLuaRun(const char* code, size_t n, const char* name, char* out, size_t cap)
{
    out[0] = 0;
    if (!ResolveGameLua()) return SV_ERR_NO_GAME;
    void* L = GameLuaState();
    if (!L) return SV_ERR_NOT_READY;
    if (!GL.checkstack(L, 8)) { memcpy(out, "no stack space", 15); return 4; }
    int top = GL.gettop(L);
    GL.pushcclosure(L, GameLuaHandler, 0);
    int st = GL.loadbufferx(L, code, n, name, "t");
    if (st == 0) st = GL.pcallk(L, 0, 1, top + 1, 0, NULL);
    int t = GL.type(L, -1);
    size_t len = 0;
    const char* s = NULL;
    if (t == 3 || t == 4) s = GL.tolstring(L, -1, &len);           /* number / string */
    else { s = GL.typename_(L, t); while (s && s[len]) ++len; }
    if (!s) len = 0;
    if (len > cap - 1) len = cap - 1;
    memcpy(out, s, len);
    out[len] = 0;
    GL.settop(L, top);
    return st;
}

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

/* ---- sound: Survival's own sound effects (XAudio2) ---------------------------------------------------------------
 * AC8 plays only its own Wwise banks, so Survival's own sounds (AC7's railgun sounds for VALKA: AGENTS.md's exception,
 * tools/ac7_sfx.py) play through XAudio2 2.9 (xaudio2_9.dll, part of Windows 10 and 11), loaded at run time and called
 * through its COM vtables: no SDK, so the slots and the packed structs below are xaudio2.h's. Sounds are 16-bit PCM
 * WAVs under the mod's Sounds\ folder (a smpl chunk's first loop is the loop region); one stereo mastering voice.
 * Lua works out distance and pan and passes a gain per side.                                                      */
#pragma pack(push, 1)                              /* (xaudio2.h packs its structs to 1 byte; WAVEFORMATEX to 2)   */
typedef struct { uint16_t tag, channels; uint32_t rate, byteRate; uint16_t align, bits, extra; } SndFormat;
typedef struct {
    uint32_t flags, bytes; const uint8_t* data;
    uint32_t playBegin, playLength, loopBegin, loopLength, loopCount; void* context;
} SndXBuffer;                                      /* XAUDIO2_BUFFER       */
typedef struct { void* context; uint32_t queued; uint64_t played; } SndXState;   /* XAUDIO2_VOICE_STATE */
#pragma pack(pop)
_Static_assert(sizeof(SndFormat) == 18, "WAVEFORMATEX layout");
_Static_assert(sizeof(SndXBuffer) == 44, "XAUDIO2_BUFFER layout");
_Static_assert(sizeof(SndXState) == 20, "XAUDIO2_VOICE_STATE layout");

#define SND_VT(o, i)          (((void**)*(void**)(o))[i])
#define SND_MAX_SOUNDS        64
#define SND_MAX_VOICES        48
#define SND_END_OF_STREAM     0x40u
#define SND_LOOP_INFINITE     255u
#define SND_NO_SAMPLES_PLAYED 0x100u
#define SND_ERR_NO_AUDIO      -1                   /* XAudio2 couldn't start (no device?)                            */
#define SND_ERR_FILE          -2                   /* no such file, or it can't be read                              */
#define SND_ERR_FORMAT        -3                   /* not a 16-bit PCM WAV                                           */
#define SND_ERR_FULL          -4                   /* too many sounds loaded / voices playing                        */

typedef struct {
    char      name[64];
    uint8_t*  file;                                /* the whole file (data points into it); never freed            */
    SndFormat fmt;
    const uint8_t* data;
    uint32_t  bytes, loopBegin, loopLength;        /* loop in frames; loopLength 0 = none (the whole file loops)    */
} SndSound;
typedef struct { void* voice; uint32_t gen; int32_t sound; } SndVoice;

static struct {
    int      state;                                /* 0 not tried, 1 ok, -1 failed                                  */
    void*    xa;                                   /* IXAudio2*                                                     */
    void*    master;                               /* IXAudio2MasteringVoice*                                       */
    SndSound sounds[SND_MAX_SOUNDS];
    int32_t  nSounds;
    SndVoice voices[SND_MAX_VOICES];
} SND;

static int SndInit(void)
{
    if (SND.state) return SND.state > 0;
    SND.state = -1;
    HANDLE ole = LoadLibraryW(L"ole32.dll");
    int32_t (*coInit)(void*, DWORD) = ole ? (int32_t (*)(void*, DWORD))GetProcAddress(ole, "CoInitializeEx") : NULL;
    if (coInit) coInit(NULL, 0);                   /* (COINIT_MULTITHREADED; a thread already in COM keeps its own)  */
    HANDLE dll = LoadLibraryW(L"xaudio2_9.dll");
    if (!dll) { Log(L"sound: xaudio2_9.dll not found (error %u); no sound effects", GetLastError()); return 0; }
    int32_t (*create)(void**, uint32_t, uint32_t) = (int32_t (*)(void**, uint32_t, uint32_t))GetProcAddress(dll, "XAudio2Create");
    int32_t (*createV)(void**, uint32_t, uint32_t, uint32_t) =
        (int32_t (*)(void**, uint32_t, uint32_t, uint32_t))GetProcAddress(dll, "XAudio2CreateWithVersionInfo");
    int32_t hr = -1;
    if (createV) hr = createV(&SND.xa, 0, 1, 0x0A000005u);      /* (Processor1; NTDDI_WIN10_RS4)                     */
    else if (create) hr = create(&SND.xa, 0, 1);
    if (hr < 0 || !SND.xa) { Log(L"sound: XAudio2Create failed (0x%x); no sound effects", (uint32_t)hr); return 0; }
    /* IXAudio2::CreateMasteringVoice(this, out, channels 2, rate 0 = the device's, flags, device, effects, GameEffects) */
    hr = ((int32_t (*)(void*, void**, uint32_t, uint32_t, uint32_t, const wchar_t*, void*, uint32_t))SND_VT(SND.xa, 7))(
        SND.xa, &SND.master, 2, 0, 0, NULL, NULL, 6);
    if (hr < 0 || !SND.master) {
        Log(L"sound: no mastering voice (0x%x); no sound effects", (uint32_t)hr);
        ((uint32_t (*)(void*))SND_VT(SND.xa, 2))(SND.xa);                                   /* Release */
        SND.xa = NULL;
        return 0;
    }
    Log(L"sound: XAudio2 2.9 up (stereo mastering voice)");
    SND.state = 1;
    return 1;
}

static uint32_t SndU32(const uint8_t* p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

/* the sound named `name` (a path under Sounds\, '/' or '\'), loaded once: its index, or an SND_ERR code */
static int32_t SndLoad(const wchar_t* name)
{
    char an[64];
    size_t n = WLen(name);
    if (!n || n >= sizeof(an)) return SND_ERR_FILE;
    for (size_t i = 0; i <= n; ++i) an[i] = (char)name[i];
    for (int32_t i = 0; i < SND.nSounds; ++i) {
        const char* a = SND.sounds[i].name;
        size_t k = 0;
        while (a[k] && a[k] == an[k]) ++k;
        if (!a[k] && !an[k]) return i;
    }
    if (SND.nSounds >= SND_MAX_SOUNDS) return SND_ERR_FULL;
    wchar_t path[PATH_CAP];
    size_t root = WLen(g_modRoot);
    if (root + n + 9 >= PATH_CAP) return SND_ERR_FILE;
    memcpy(path, g_modRoot, root * 2);
    memcpy(path + root, L"\\Sounds\\", 8 * 2);
    for (size_t i = 0; i <= n; ++i) path[root + 8 + i] = name[i] == L'/' ? L'\\' : name[i];
    HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) { Log(L"sound: %s not found", path); return SND_ERR_FILE; }
    int64_t size = 0;
    uint8_t* buf = NULL;
    DWORD got = 0;
    if (GetFileSizeEx(f, &size) && size > 44 && size < 64 * 1024 * 1024) buf = (uint8_t*)malloc((size_t)size);
    BOOL ok = buf && ReadFile(f, buf, (DWORD)size, &got, NULL) && got == (DWORD)size;
    CloseHandle(f);
    if (!ok) { if (buf) free(buf); Log(L"sound: %s can't be read", path); return SND_ERR_FILE; }
    SndSound* s = &SND.sounds[SND.nSounds];
    memset(s, 0, sizeof(*s));
    if (SndU32(buf) != 0x46464952u || SndU32(buf + 8) != 0x45564157u) { free(buf); return SND_ERR_FORMAT; }   /* RIFF WAVE */
    int haveFmt = 0;
    for (size_t at = 12; at + 8 <= (size_t)size; ) {
        uint32_t id = SndU32(buf + at), len = SndU32(buf + at + 4);
        const uint8_t* c = buf + at + 8;
        if (at + 8 + (uint64_t)len > (uint64_t)size) len = (uint32_t)((size_t)size - at - 8);
        if (id == 0x20746D66u && len >= 16) {                        /* "fmt " */
            memcpy(&s->fmt, c, 16);
            s->fmt.extra = 0;
            haveFmt = 1;
        } else if (id == 0x61746164u) {                              /* "data" */
            s->data = c; s->bytes = len;
        } else if (id == 0x6C706D73u && len >= 36 + 24 && SndU32(c + 28) > 0) {   /* "smpl": its first loop */
            uint32_t b = SndU32(c + 36 + 8), e = SndU32(c + 36 + 12);
            if (e > b) { s->loopBegin = b; s->loopLength = e - b + 1; }
        }
        at += 8 + (size_t)len + (len & 1);
    }
    if (!haveFmt || !s->data || s->fmt.tag != 1 || s->fmt.bits != 16 || s->fmt.channels < 1 || s->fmt.channels > 2
        || s->fmt.align != s->fmt.channels * 2) {                 /* (align 0 would divide by zero below) */
        free(buf); Log(L"sound: %s is not a 16-bit PCM WAV", path); return SND_ERR_FORMAT;
    }
    s->bytes -= s->bytes % s->fmt.align;                          /* whole frames only (XAudio2 refuses a part one) */
    uint32_t frames = s->bytes / s->fmt.align;
    if (s->loopLength && s->loopBegin + s->loopLength > frames) s->loopLength = 0;
    s->file = buf;
    memcpy(s->name, an, n + 1);
    Log(L"sound: %s: %u Hz, %u ch, %u frames%s", path, s->fmt.rate, (uint32_t)s->fmt.channels, frames,
        s->loopLength ? L", a loop" : L"");
    return SND.nSounds++;
}

static void SndDestroy(SndVoice* v)
{
    if (!v->voice) return;
    ((int32_t (*)(void*, uint32_t, uint32_t))SND_VT(v->voice, 20))(v->voice, 0, 0);        /* Stop      */
    ((void (*)(void*))SND_VT(v->voice, 18))(v->voice);                                    /* DestroyVoice */
    v->voice = NULL;
}

/* finished voices are destroyed (never from an XAudio2 callback: there are none) */
static void SndReap(void)
{
    for (int i = 0; i < SND_MAX_VOICES; ++i) {
        SndVoice* v = &SND.voices[i];
        if (!v->voice) continue;
        SndXState st = { 0 };
        ((void (*)(void*, SndXState*, uint32_t))SND_VT(v->voice, 25))(v->voice, &st, SND_NO_SAMPLES_PLAYED);   /* GetState */
        if (st.queued == 0) SndDestroy(v);
    }
}

static SndVoice* SndHandle(int64_t h)
{
    int64_t i = (h & 0xFF) - 1;
    if (h <= 0 || i < 0 || i >= SND_MAX_VOICES) return NULL;
    SndVoice* v = &SND.voices[i];
    return v->voice && v->gen == (uint32_t)(h >> 8) ? v : NULL;
}

static void SndLevels(SndVoice* v, double left, double right, double ratio)
{
    const SndSound* s = &SND.sounds[v->sound];
    float m[4];
    uint32_t ch = s->fmt.channels;
    if (ch == 1) { m[0] = (float)left; m[1] = (float)right; }           /* mono -> L, R                          */
    else { m[0] = (float)left; m[1] = 0; m[2] = 0; m[3] = (float)right; } /* [dst * src + src]: L->L, R->R         */
    ((int32_t (*)(void*, void*, uint32_t, uint32_t, const float*, uint32_t))SND_VT(v->voice, 16))(v->voice, NULL, ch, 2, m, 0);
    if (ratio < 0.0625) ratio = 0.0625;
    if (ratio > 4.0) ratio = 4.0;
    ((int32_t (*)(void*, float, uint32_t))SND_VT(v->voice, 26))(v->voice, (float)ratio, 0);   /* SetFrequencyRatio */
}

/* SV_MemMB() -> working set MB x 100000 + commit charge (private bytes) MB, or -1: the game's memory for the log
 * (sv_main.lua memText splits it; the 0.69 X-02S container ran the game to ~21 GB during a 3.5-minute load, 2026-10-25) */
static int L_MemMB(void* lua)
{
    PROCESS_MEMORY_COUNTERS pmc;
    memset(&pmc, 0, sizeof(pmc));
    pmc.cb = sizeof(pmc);
    if (!K32GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc))) return Ret(lua, -1);
    return Ret(lua, (int64_t)(pmc.WorkingSetSize >> 20) * 100000 + (int64_t)(pmc.PagefileUsage >> 20));
}

/* SV_SndLoad(name) -> the sound's id (> 0) or an error (-1 no audio, -2 no file, -3 not 16-bit PCM, -4 too many);
 * name: a WAV under the mod's Sounds\ folder, e.g. "valka/shot_main.wav" */
static int L_SndLoad(void* lua)
{
    wchar_t name[64];
    if (!ArgName(lua, name, 64)) return Ret(lua, SV_ERR_BAD_ARGS);
    if (!SndInit()) return Ret(lua, SND_ERR_NO_AUDIO);
    int32_t i = SndLoad(name);
    return Ret(lua, i < 0 ? i : i + 1);
}

/* SV_SndPlay(id, left, right[, ratio, loop]) -> a voice handle (> 0) or an error; left / right: linear gains per side
 * (1 = as recorded), ratio: the playback rate (pitch), loop 1: loops its smpl region (or the whole sound) until stopped */
static int L_SndPlay(void* lua)
{
    double id = 0, left = 1, right = 1, ratio = 1, loop = 0;
    if (!ArgNumber(lua, &id)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &left); ArgNumber(lua, &right); ArgNumber(lua, &ratio); ArgNumber(lua, &loop);
    if (!SndInit()) return Ret(lua, SND_ERR_NO_AUDIO);
    int32_t si = (int32_t)id - 1;
    if (si < 0 || si >= SND.nSounds) return Ret(lua, SV_ERR_BAD_ARGS);
    SndReap();
    int slot = -1;
    for (int i = 0; i < SND_MAX_VOICES && slot < 0; ++i) if (!SND.voices[i].voice) slot = i;
    if (slot < 0) return Ret(lua, SND_ERR_FULL);
    SndSound* s = &SND.sounds[si];
    SndVoice* v = &SND.voices[slot];
    /* IXAudio2::CreateSourceVoice(this, out, format, flags, max ratio 4, callback, sends, effects) */
    int32_t hr = ((int32_t (*)(void*, void**, const SndFormat*, uint32_t, float, void*, void*, void*))SND_VT(SND.xa, 5))(
        SND.xa, &v->voice, &s->fmt, 0, 4.0f, NULL, NULL, NULL);
    if (hr < 0 || !v->voice) { v->voice = NULL; Log(L"sound: CreateSourceVoice failed (0x%x)", (uint32_t)hr); return Ret(lua, SND_ERR_NO_AUDIO); }
    SndXBuffer b = { 0 };
    b.flags = SND_END_OF_STREAM;
    b.bytes = s->bytes;
    b.data = s->data;
    if (loop != 0) {
        b.loopBegin = s->loopLength ? s->loopBegin : 0;
        b.loopLength = s->loopLength;                       /* (0 with LoopBegin 0: the whole sound)                  */
        b.loopCount = SND_LOOP_INFINITE;
    }
    hr = ((int32_t (*)(void*, const SndXBuffer*, void*))SND_VT(v->voice, 21))(v->voice, &b, NULL);   /* SubmitSourceBuffer */
    if (hr < 0) { SndDestroy(v); Log(L"sound: SubmitSourceBuffer failed (0x%x)", (uint32_t)hr); return Ret(lua, SND_ERR_FORMAT); }
    v->sound = si;
    v->gen = (v->gen + 1) & 0xFFFFFF;
    SndLevels(v, left, right, ratio);
    ((int32_t (*)(void*, uint32_t, uint32_t))SND_VT(v->voice, 19))(v->voice, 0, 0);          /* Start */
    return Ret(lua, ((int64_t)v->gen << 8) | (slot + 1));
}

/* SV_SndSet(handle, left, right[, ratio]) -> 1, or 0 when that voice is over */
static int L_SndSet(void* lua)
{
    double h = 0, left = 1, right = 1, ratio = 1;
    if (!ArgNumber(lua, &h)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &left); ArgNumber(lua, &right); ArgNumber(lua, &ratio);
    SndVoice* v = SND.state > 0 ? SndHandle((int64_t)h) : NULL;
    if (!v) return Ret(lua, 0);
    SndXState st = { 0 };
    ((void (*)(void*, SndXState*, uint32_t))SND_VT(v->voice, 25))(v->voice, &st, SND_NO_SAMPLES_PLAYED);   /* GetState */
    if (st.queued == 0) { SndDestroy(v); return Ret(lua, 0); }             /* (over: Lua forgets it) */
    SndLevels(v, left, right, ratio);
    return Ret(lua, 1);
}

/* SV_SndStop(handle[, tail]) -> 1, or 0 when that voice was already over; tail 1: a loop plays out to its end */
static int L_SndStop(void* lua)
{
    double h = 0, tail = 0;
    if (!ArgNumber(lua, &h)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &tail);
    SndVoice* v = SND.state > 0 ? SndHandle((int64_t)h) : NULL;
    if (!v) return Ret(lua, 0);
    if (tail != 0) ((int32_t (*)(void*, uint32_t))SND_VT(v->voice, 24))(v->voice, 0);      /* ExitLoop */
    else SndDestroy(v);
    return Ret(lua, 1);
}

/* SV_SndMaster(gain) -> 1, or -1 without audio: the linear volume of everything Survival plays */
static int L_SndMaster(void* lua)
{
    double g = 1;
    ArgNumber(lua, &g);
    if (!SndInit()) return Ret(lua, SND_ERR_NO_AUDIO);
    ((int32_t (*)(void*, float, uint32_t))SND_VT(SND.master, 12))(SND.master, (float)(g < 0 ? 0 : g), 0);   /* SetVolume */
    return Ret(lua, 1);
}

/* SV_Version() -> RT_VERSION_A (until 0.28.4 a fixed "0.27.0", whatever the build: co-op's "hi" said every player ran
 * 0.27.0, and a stale main.dll couldn't be told from a current one) */
/* SV_MenuChoice() -> the last main-menu entry picked (g_menuChoice: 0 none yet or another entry, 1 SURVIVAL MODE, 2 SP
 * OFFLINE, 3 CO-OP: HOST, 4 CO-OP: JOIN, 5 SP ONLINE, 6 Survival's pages opened) + 16 x how many were picked, so the same entry
 * picked again is seen (a retry after a failed co-op open). Lua: % 16 the entry, // 16 the picks. */
static int L_MenuChoice(void* lua) { return Ret(lua, (int64_t)g_menuChoice + 16 * (int64_t)g_menuPicks); }

static int L_Version(void* lua)
{
    static const char v[] = RT_VERSION_A;
    U.luaSetString(lua, v, sizeof(v) - 1);
    return 1;
}

/* SV_Spawn(unit [, x, y, z, yaw]) -> aircraft spawned (> 0) or an SV_ERR code; position in cm, yaw in degrees */
static int L_Spawn(void* lua)
{
    wchar_t name[96];
    double pose[4];
    if (!ArgName(lua, name, 96)) return Ret(lua, SV_ERR_BAD_ARGS);
    int n = 0;
    while (n < 4 && ArgNumber(lua, &pose[n])) ++n;
    if (n != 0 && n != 4) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, Spawn(name, n ? pose : NULL));
}

/* SV_SetLevel(unit, level) -> AI objects changed (their LevelId: 100 x the AI level) or an SV_ERR code */
static int L_SetLevel(void* lua)
{
    wchar_t name[96];
    double level = -1;
    if (!ArgName(lua, name, 96) || !ArgNumber(lua, &level)) return Ret(lua, SV_ERR_BAD_ARGS);
    if (level < 0 || level > 65535) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, SetLevel(name, (int32_t)level));
}

/* SV_PlaneLevel(address) -> a spawned plane's AILevel value (u16 at plane +0x1048), or SV_ERR_BAD_ARGS; for the log */
static int L_PlaneLevel(void* lua)
{
    double addr = 0;
    if (!ArgNumber(lua, &addr) || addr <= 0) return Ret(lua, SV_ERR_BAD_ARGS);
    uint8_t* plane = (uint8_t*)(uintptr_t)(uint64_t)addr;
    if (!LiveObject(plane) || !Readable(plane + PLANE_AI_LEVEL, 2)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, *(uint16_t*)(plane + PLANE_AI_LEVEL));
}

/* SV_PlayerTarget(plane) -> the address of the player plane's current target (the enemy it has selected, the one its
 * missiles go for), 0 for none, SV_ERR_BAD_ARGS for a bad plane. tools/re/UNIQUE_ACTIONS.md: the player tick posts
 * EnemyBehind for player+0x1ae8 -> +0x750. Confirmed in game 2026-10-23 (it named the Reaper ace the player had
 * targeted). Not used by Lua at the moment (the flight recorder that used it is gone). */
#define PLAYER_TARGET_HOLDER 0x1ae8
#define PLAYER_TARGET        0x750
static int L_PlayerTarget(void* lua)
{
    double addr = 0;
    if (!ArgNumber(lua, &addr) || addr <= 0) return Ret(lua, SV_ERR_BAD_ARGS);
    uint8_t* plane = (uint8_t*)(uintptr_t)(uint64_t)addr;
    if (!LiveObject(plane) || !Readable(plane + PLAYER_TARGET_HOLDER, 8)) return Ret(lua, SV_ERR_BAD_ARGS);
    uint8_t* holder = *(uint8_t**)(plane + PLAYER_TARGET_HOLDER);
    if (!holder || !Readable(holder + PLAYER_TARGET, 8)) return Ret(lua, 0);
    uint8_t* target = *(uint8_t**)(holder + PLAYER_TARGET);
    if (!target || !LiveObject(target)) return Ret(lua, 0);
    return Ret(lua, (int64_t)(uintptr_t)target);
}

/* SV_SetAircraft(unit, npc [, index]) -> AI objects changed or an SV_ERR code */
static int L_SetAircraft(void* lua)
{
    wchar_t name[96], npc[96];
    double idx = -1;
    if (!ArgName(lua, name, 96) || !ArgName(lua, npc, 96)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &idx);
    return Ret(lua, SetAircraft(name, npc, (int)idx));
}

/* SV_UnitAlive(unit) -> aircraft alive in its current flight, SV_NOT_SPAWNED, or an SV_ERR code */
static int L_UnitAlive(void* lua)
{
    wchar_t name[96];
    if (!ArgName(lua, name, 96)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, UnitAlive(name));
}

/* SV_LogUnits([why]) -> length of the phase's unit list (written to AC8SurvivalMode.log) */
static int L_LogUnits(void* lua)
{
    wchar_t why[64];
    if (!ArgName(lua, why, 64)) memcpy(why, L"asked by Lua", 13 * 2);
    return Ret(lua, LogUnits(why));
}

/* SV_Ammo(kind [, max]) -> the player's current (or, with max = 1, maximum) count; kind 0 gun, 1 missiles,
 * 2 special 1, 3 special 2, 4 flares. SV_NOT_SPAWNED for a slot the aircraft doesn't have, or an SV_ERR code. */
static int L_Ammo(void* lua)
{
    double kind = -1, wantMax = 0;
    if (!ArgNumber(lua, &kind)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &wantMax);
    return Ret(lua, AmmoGet((int)kind, wantMax != 0));
}

/* SV_SetAmmo(kind, count) -> the new count (capped at the weapon's maximum; count < 0 = full) or an SV_ERR code */
static int L_SetAmmo(void* lua)
{
    double kind = -1, value = 0;
    if (!ArgNumber(lua, &kind) || !ArgNumber(lua, &value)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, AmmoSet((int)kind, (int32_t)value));
}

/* SV_AmmoMax(kind, max) -> the new maximum (full load) of kind 1-4, or an SV_ERR code (see AmmoSetMax) */
static int L_AmmoMax(void* lua)
{
    double kind = -1, max = 0;
    if (!ArgNumber(lua, &kind) || !ArgNumber(lua, &max)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, AmmoSetMax((int)kind, (int32_t)max));
}

/* SV_FreeRestock(on) -> the old setting (1 on, 0 off) or an SV_ERR code; on = 0 stops missiles refilling over time */
static int L_SetFreeRestock(void* lua)
{
    double on = 0;
    if (!ArgNumber(lua, &on)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, SetFreeRestock(on != 0));
}

/* SV_GameLua(code [, chunkname]) -> "<status>\t<result>" from the game's own Lua (see "the game's own Lua") */
static int L_GameLua(void* lua)
{
    static char out[32768];
    if (U.luaStackSize(lua) < 1 || !U.luaIsString(lua, 1)) { U.luaSetString(lua, "-4\tno code", 10); return 1; }
    StrView sv = { NULL, 0 };
    U.luaGetString(lua, &sv, 1);
    char* code = (char*)malloc(sv.n + 1);
    if (!code) { U.luaSetString(lua, "4\tout of memory", 15); return 1; }
    memcpy(code, sv.p, sv.n);
    code[sv.n] = 0;
    size_t n = sv.n;
    char name[96] = "=SurvivalMode";
    if (U.luaStackSize(lua) >= 1 && U.luaIsString(lua, 1)) {
        StrView nv = { NULL, 0 };
        U.luaGetString(lua, &nv, 1);
        if (nv.p && nv.n && nv.n < sizeof(name) - 1) { name[0] = '='; memcpy(name + 1, nv.p, nv.n); name[nv.n + 1] = 0; }
    }
    int st = GameLuaRun(code, n, name, out + 8, sizeof(out) - 8);
    free(code);
    char head[8]; int h = 0, v = st < 0 ? -st : st;
    if (st < 0) head[h++] = '-';
    char t[4]; int k = 0;
    do { t[k++] = (char)('0' + v % 10); v /= 10; } while (v && k < 3);
    while (k) head[h++] = t[--k];
    head[h++] = '\t';
    char* res = out + 8 - h;                     /* the status goes right in front of the result */
    memcpy(res, head, h);
    size_t len = h;
    while (res[len]) ++len;
    U.luaSetString(lua, res, len);
    return 1;
}

/* SV_GameLuaState([create]) -> the game's lua_State address (changes if the game makes a new one), 0 while there is
 * none. create = 1 makes it the way the game does on its first AI spawn (GetGameLuaState), for Survival's level only. */
typedef void* (*GetGameLuaStateFn)(void);
static int L_GameLuaState(void* lua)
{
    double create = 0;
    ArgNumber(lua, &create);
    void* L = GameLuaState();
    if (!L && create != 0 && GL.state > 0) {
        Log(L"game Lua: no state yet; asking the plugin to make it (GetGameLuaState)");
        ((GetGameLuaStateFn)g_fGameLuaState)();
        L = GameLuaState();
        Log(L"game Lua: state now %p", L);
    }
    return Ret(lua, (int64_t)(uintptr_t)L);
}

/* SV_PlayBGM(event [, delay]) -> the Wwise playing id (0: refused, already playing, or queued by a delay) or an
 * SV_ERR code (SV_ERR_NO_UNIT: the game has no such name); see "music and remote events" */
static int L_PlayBGM(void* lua)
{
    wchar_t name[128];
    double delay = 0;
    if (!ArgName(lua, name, 128)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &delay);
    return Ret(lua, PlayBgm(name, (float)delay));
}

/* SV_BGM([field]) -> the BGM controller's playing id (0), status byte (1) or last posted id (2), or an SV_ERR code */
static int L_BGM(void* lua)
{
    double field = 0;
    ArgNumber(lua, &field);
    return Ret(lua, BgmState((int)field));
}

/* SV_BGMNames() -> "<track>|<last stop>|<last event>": the BGM controller's FNames at +0x120 (the track Play posted:
 * 0x1478bdbc0 "lea rsi,[rdi+0x120]; mov [rsi],rbx"), +0x13C (LiveStopBGMExecution: "mov [rbx+0x13c],rcx") and +0x14C
 * (LiveEventBGMExecution: "mov [rdi+0x14c],rcx"), or "" when there is no controller. For finding what interrupts the
 * pause menu's music player (user, 2026-10-22: the track skips when a kill happens). */
static int L_BGMNames(void* lua)
{
    static const int32_t kOff[3] = { 0x120, 0x13C, 0x14C };
    char out[400];
    size_t n = 0;
    uint8_t* bgm = BgmController(0);
    for (int i = 0; bgm && i < 3; ++i) {
        wchar_t w[120];
        if (!Readable(bgm + kOff[i], 8)) break;
        NameText((const FNameRaw*)(bgm + kOff[i]), w, 120);
        if (i) out[n++] = '|';
        for (size_t k = 0; w[k] && n < sizeof(out) - 2; ++k) out[n++] = w[k] < 0x80 ? (char)w[k] : '?';
    }
    out[n] = 0;
    U.luaSetString(lua, out, n);
    return 1;
}

/* SV_Event(name) -> 1 once remote event `name` is dispatched in Survival's level, or an SV_ERR code */
static int L_Event(void* lua)
{
    wchar_t name[128];
    if (!ArgName(lua, name, 128)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, FireEvent(name));
}

/* SV_MusicPlayer([on]) -> the old setting (1 shown, 0 not), or SV_ERR_NO_GAME when the pause list wasn't hooked;
 * on = 0 keeps the stock pause menu (no music player row) in Survival */
static int L_MusicPlayer(void* lua)
{
    double on = -1;
    ArgNumber(lua, &on);
    if (!g_nextPauseValidity) return Ret(lua, SV_ERR_NO_GAME);
    int64_t old = g_musicPlayer;
    if (on >= 0) g_musicPlayer = on != 0;
    return Ret(lua, old);
}

/* SV_MusicClock([on]) -> the old setting (1: the music player's track clock is held while Survival's BGM is paused,
 * 0: the stock clock), or SV_ERR_NO_GAME when the clock wasn't hooked */
/* SV_MusicHold(on) -> the hold it had: Lua holds the music player's track clock (in Survival's mission only) while the
 * landing store is open, as a paused BGM channel does */
static int L_MusicHold(void* lua)
{
    double on = -1;
    ArgNumber(lua, &on);
    if (!g_nextMusicTick) return Ret(lua, SV_ERR_NO_GAME);
    int64_t old = g_musicForceHold;
    if (on >= 0) g_musicForceHold = on != 0;
    return Ret(lua, old);
}

static int L_MusicClock(void* lua)
{
    double on = -1;
    ArgNumber(lua, &on);
    if (!g_nextMusicTick) return Ret(lua, SV_ERR_NO_GAME);
    int64_t old = g_musicClockHold;
    if (on >= 0) g_musicClockHold = on != 0;
    return Ret(lua, old);
}

/* SV_Invert(pitch, roll, fade_s, plane[, yaw, swap_axes, swap_throttle]) -> the factor pitch had (x100: 100 normal,
 * -100 inverted), or SV_ERR_NO_GAME when BuildFlightInput wasn't hooked. pitch / roll / yaw 1 = invert that axis,
 * swap_axes 1 = pitch and roll swapped, swap_throttle 1 = throttle and brake swapped, 0 = normal; the changes fade over
 * fade_s; plane = the player's ALivePlayerPlane address (only that plane's input is touched; 0 = none). Turning the
 * effects back off keeps the plane until the fade is over. */
static int L_SetControlInvert(void* lua)
{
    double pitch = 0, roll = 0, fade = 1.5, addr = 0, yaw = 0, swapAxes = 0, swapThrottle = 0;
    ArgNumber(lua, &pitch); ArgNumber(lua, &roll); ArgNumber(lua, &fade); ArgNumber(lua, &addr);
    ArgNumber(lua, &yaw); ArgNumber(lua, &swapAxes); ArgNumber(lua, &swapThrottle);
    if (!g_nextBuildInput) return Ret(lua, SV_ERR_NO_GAME);
    int64_t old = (int64_t)(g_invScale[INV_PITCH] * 100.0f);
    uint8_t* plane = (uint8_t*)(uintptr_t)(uint64_t)(addr > 0 ? addr : 0);
    if (plane && !LiveObject(plane)) return Ret(lua, SV_ERR_BAD_ARGS);
    if (plane != g_invPlane) { for (int a = 0; a < INV_N; ++a) g_invScale[a] = 1.0f; g_invLastMs = 0; }
    g_invFadeMs = (int32_t)(fade * 1000.0);
    g_invWant[INV_PITCH] = pitch != 0; g_invWant[INV_ROLL] = roll != 0; g_invWant[INV_YAW] = yaw != 0;
    g_invWant[INV_SWAP_AXES] = swapAxes != 0; g_invWant[INV_SWAP_THROTTLE] = swapThrottle != 0;
    g_invPlane = plane;
    return Ret(lua, old);
}

/* SV_SetText(key, text) -> 1, or 0 (not an SV_ key, or 64 keys already): the text the game shows for text key `key`
 * (menu rows and help lines that name it), ASCII; longer than 255 characters is cut there */
static int L_SetText(void* lua)
{
    static wchar_t text[1024];                     /* longer than a slot: SetDynText keeps the first 255 */
    wchar_t key[DYN_KEY];
    if (!ArgName(lua, key, DYN_KEY)) return Ret(lua, SV_ERR_BAD_ARGS);
    if (!ArgName(lua, text, 1024)) { text[0] = L' '; text[1] = 0; }           /* "" (or longer) is refused by ArgName */
    return Ret(lua, SetDynText(key, text));
}

/* SV_ShopRequest() -> the StringArgs of the oldest shop row picked on the landing menu and not yet taken
 * ("SV_Buy_..."), or "" when none is waiting. SV_ShopRequest(1) -> 1 if the landing menu hook is installed, else 0
 * (without the hook a shop row would reach the stock decide, which reads it as a page number). */
static int L_ShopRequest(void* lua)
{
    double query = 0;
    if (ArgNumber(lua, &query) && query != 0) return Ret(lua, g_nextHangarDecide ? 1 : 0);
    char out[32];
    size_t n = 0;
    if (g_shopCount > 0) {
        const wchar_t* q = g_shopQueue[g_shopHead];
        while (n < 31 && q[n]) { out[n] = (char)q[n]; ++n; }
        g_shopHead = (g_shopHead + 1) % SHOP_QUEUE;
        --g_shopCount;
    }
    out[n] = 0;
    U.luaSetString(lua, out, n);
    return 1;
}

/* SV_MenuPages(1 | 0): Survival's pages are (not) in the game's page list (Scripts/sv_menu.lua checked it): only then
 * does the SURVIVAL MODE row that opens them pass. -> 1 */
static int L_MenuPages(void* lua)
{
    double v = 0;
    if (!ArgNumber(lua, &v)) return Ret(lua, SV_ERR_BAD_ARGS);
    if ((v != 0) != (g_pagesOk != 0)) Log(L"main menu: Survival's pages %s", v != 0 ? L"are in the game's page list" : L"are not in the game's page list");
    g_pagesOk = v != 0;
    return Ret(lua, 1);
}

/* SV_MenuClass(n, class): Survival's page n (1-5: sv_menu.lua PAGES, kPageNames) is that widget class. -> 1 */
static int L_MenuClass(void* lua)
{
    double n = 0;
    if (!ArgNumber(lua, &n) || n < 1 || n > MENU_PAGE_N) return Ret(lua, SV_ERR_BAD_ARGS);
    uint8_t* c = ArgObject(lua);
    if (c && !Readable(c, 0x30)) return Ret(lua, SV_ERR_BAD_ARGS);
    g_pageClass[(int)n - 1] = c;
    return Ret(lua, 1);
}

/* SV_MenuSlot(manager, class, index, slot) -> 1 when the main menu manager's MenuWidgetClassList entry `index` is found:
 * kSlotIds[slot]'s (0 CampaignTraining, 1 InitialSetting_DualSence, 2 InitialSetting_Accessibility), holding that class (0: any), found by a look through
 * the manager for the list (TArray of { FString MenuIDName, UClass* MenuClass }, 0x18 bytes each); 0 not found */
#define MENU_ENTRY_SIZE 0x18
static int L_MenuSlot(void* lua)
{
    uint8_t* mgr = ArgObject(lua);
    uint8_t* stock = ArgObject(lua);
    double idx = -1, which = 0;
    ArgNumber(lua, &idx);
    ArgNumber(lua, &which);
    if (!mgr || idx < 0 || idx > 255 || which < 0 || which >= MENU_SLOT_N || which != (int)which) return Ret(lua, SV_ERR_BAD_ARGS);
    int w = (int)which;
    const wchar_t* want = kSlotIds[w];
    g_pageSlot[w] = NULL;
    for (size_t off = 0x28; off < 0x400; off += 8) {
        if (!Readable(mgr + off, 16)) break;
        uint8_t* data = *(uint8_t**)(mgr + off);
        int32_t num = *(int32_t*)(mgr + off + 8), max = *(int32_t*)(mgr + off + 12);
        if (!data || num <= (int32_t)idx || num > 256 || max < num) continue;
        uint8_t* e = data + (size_t)idx * MENU_ENTRY_SIZE;
        if (!Readable(e, MENU_ENTRY_SIZE)) continue;
        const FString* id = (const FString*)e;
        size_t n = WLen(want);
        if (!id->data || id->num != (int32_t)n + 1 || !Readable(id->data, n * 2) || memcmp(id->data, want, n * 2)) continue;
        uint8_t** slot = (uint8_t**)(e + 0x10);
        if (stock && *slot != stock) continue;
        g_pageSlot[w] = slot;
        g_slotStock[w] = *slot;
        Log(L"main menu: Survival's pages open through %s's page (entry %d, list at manager+%x)", want, (int32_t)idx, (uint32_t)off);
        return Ret(lua, 1);
    }
    Log(L"main menu: %s's entry %d not found in the main menu's page list", want, (int32_t)idx);
    return Ret(lua, 0);
}

/* SV_MenuQuick(code): the mode QUICK START plays (2 SP OFFLINE, 3 COOP HOST, 5 SP ONLINE; Lua's last one). -> 1 */
static int L_MenuQuick(void* lua)
{
    double v = 0;
    if (!ArgNumber(lua, &v) || !(v == 2 || v == 3 || v == 5)) return Ret(lua, SV_ERR_BAD_ARGS);
    g_quickMode = (int32_t)v;
    return Ret(lua, 1);
}

/* SV_MenuSetting() -> the StringArgs of the oldest settings row picked on the main menu and not yet taken
 * ("SV_Set_..."), or "" when none is waiting */
static int L_MenuSetting(void* lua)
{
    char out[32];
    size_t n = 0;
    if (g_setCount > 0) {
        const wchar_t* q = g_setQueue[g_setHead];
        while (n < 31 && q[n]) { out[n] = (char)q[n]; ++n; }
        g_setHead = (g_setHead + 1) % SET_QUEUE;
        --g_setCount;
    }
    out[n] = 0;
    U.luaSetString(lua, out, n);
    return 1;
}

/* SV_Reset(): forget the level's spawner (Lua calls it when a level loads) */
static int L_Reset(void* lua)
{
    g_spawner = NULL; g_phase = NULL; g_wd = NULL;
    g_shopHead = g_shopCount = 0;                  /* a pick made as the level ended isn't bought in the next run */
    return Ret(lua, 1);
}

/* The Offline edition (runtime/build.sh OFFLINE=1, user, 2026-10-23: "None of the Code for sending the files remains")
 * is built with SV_OFFLINE: everything from here to RegisterLua (WinHTTP, bcrypt, the address and key, the Steam name)
 * is left out, and so are its Lua functions; main.lua's leaderboard half is stripped from that edition too. */
#ifndef SV_OFFLINE
/* ---------------------------------------------------------------------------------------- leaderboard (Milestone 8)
 * SV_Post(json) -> a job number (1..8) or an SV_ERR code: sends a finished run to the leaderboard Worker
 * (leaderboard/src/index.js, POST /submit) on a thread of its own, so the game never waits on the network: HTTPS
 * through WinHTTP, the body signed with HMAC-SHA256 (bcrypt) under the build's submit key, in X-SV-Signature.
 * The Worker's host and the key come from leaderboard/submit.local through runtime/build.sh (build/runtime/
 * submit_cfg.h, never in git); a build without them answers SV_ERR_NO_SERVER. Only that host is ever contacted.
 * SV_PostResult(job) -> 0 while sending, then the HTTP status, or < 0 when it couldn't get through: minus WinHTTP's
 * error (e.g. -12007 the name didn't resolve, -12029 no connection, -12002 timed out, -12175 TLS failed), or -1 / -2
 * when Windows gave none; the job is freed once its result is read. SV_PostReply(job) -> the Worker's reply.
 * The build (runtime 0.28.6; user, 2026-10-30: "we need a way that the Leaderboards can detect if a run has been edited
 * from the stock run"): the mod's files are hashed when the game starts (build_hash.c, on a thread of its own) and again
 * for every send; the send carries that hash in X-SV-Build and is signed over "<hash>\n<body>", so the Worker counts a
 * run only from a build the user registered (leaderboard/README.md). A hash that changed since the start is logged.
 * SV_BuildHash() -> the hash (64 hex characters), "" while it's worked out or when it couldn't be (the log says why). */
#if __has_include("submit_cfg.h")
#include "submit_cfg.h"
#endif
#ifndef SV_SUBMIT_HOST
#define SV_SUBMIT_HOST L""
#define SV_SUBMIT_PATH L"/submit"
#define SV_SUBMIT_KEY  ""
#endif
#define SV_ERR_NO_SERVER -8
#define SV_ERR_BUSY      -9
#define POST_JOBS 8
#define POST_BODY 16384
typedef struct {
    volatile int32_t state;            /* 0 free, 1 sending, 2 done */
    int32_t status;
    DWORD   len, replyLen;
    char    body[POST_BODY];
    char    reply[512];
} PostJob;
static PostJob g_post[POST_JOBS];

typedef HANDLE (*HttpOpenFn)(const wchar_t*, DWORD, const wchar_t*, const wchar_t*, DWORD);
typedef HANDLE (*HttpConnectFn)(HANDLE, const wchar_t*, uint16_t, DWORD);
typedef HANDLE (*HttpOpenRequestFn)(HANDLE, const wchar_t*, const wchar_t*, const wchar_t*, const wchar_t*, const wchar_t**, DWORD);
typedef BOOL   (*HttpSendFn)(HANDLE, const wchar_t*, DWORD, void*, DWORD, DWORD, uintptr_t);
typedef BOOL   (*HttpReceiveFn)(HANDLE, void*);
typedef BOOL   (*HttpQueryFn)(HANDLE, DWORD, const wchar_t*, void*, DWORD*, DWORD*);
typedef BOOL   (*HttpReadFn)(HANDLE, void*, DWORD, DWORD*);
typedef BOOL   (*HttpCloseFn)(HANDLE);
typedef BOOL   (*HttpTimeoutsFn)(HANDLE, int, int, int, int);
#include "build_hash.c"                               /* the build hash and the HMAC (runtime 0.28.6) */

/* HMAC-SHA256 under the build's key of build + "\n" + body (build: a build hash, or NULL: the body alone, as before
 * 0.28.6), as 64 hex characters (wide, for the header); 0 if bcrypt failed */
static int SignBody(const char* build, const char* body, DWORD len, wchar_t* hex)
{
    static const char key[] = SV_SUBMIT_KEY;
    char pre[66], mac[65];
    size_t preLen = 0;
    if (build) {
        while (build[preLen] && preLen < 64) { pre[preLen] = build[preLen]; ++preLen; }
        pre[preLen++] = '\n';
    }
    if (!BhHmac(key, sizeof(key) - 1, pre, preLen, body, len, mac)) return 0;
    for (int i = 0; i <= 64; ++i) hex[i] = (wchar_t)mac[i];
    return 1;
}

/* The build hash: worked out on a thread when the game starts (BuildHashThread), then again for each send */
static char             g_buildHex[65];             /* "" until it's known */
static volatile int32_t g_buildLock;
static wchar_t          g_ioDir[PATH_CAP];          /* ...\Mods\IoStoreLoaderMod\SurvivalMode (set in start_mod) */

static void BuildHexGet(char* out)
{
    while (__sync_lock_test_and_set(&g_buildLock, 1)) Sleep(0);
    memcpy(out, g_buildHex, sizeof(g_buildHex));
    __sync_lock_release(&g_buildLock);
}

static void BuildHexSet(const char* hex)
{
    while (__sync_lock_test_and_set(&g_buildLock, 1)) Sleep(0);
    memcpy(g_buildHex, hex, sizeof(g_buildHex));
    __sync_lock_release(&g_buildLock);
}

static void WidenHex(const char* hex, wchar_t* out) { int i = 0; for (; i < 64 && hex[i]; ++i) out[i] = (wchar_t)hex[i]; out[i] = 0; }

/* The build hash now into hex (65 characters), 1; 0 (logged) when it couldn't be worked out. why: the log line's start */
static int BuildHashNow(char* hex, const wchar_t* why)
{
    BhRun r;
    memset(&r, 0, sizeof(r));
    uint64_t t0 = GetTickCount64();
    if (!g_modRoot[0] || !g_ioDir[0] || !BuildHash(g_modRoot, g_ioDir, hex, &r)) {
        Log(L"leaderboard: %s: no build hash (%s%s%s); runs go without one", why, g_modRoot[0] ? (r.why ? r.why : L"?") : L"no mod folder",
            r.whyFile[0] && g_modRoot[0] ? L": " : L"", g_modRoot[0] ? r.whyFile : L"");
        return 0;
    }
    wchar_t w[65];
    WidenHex(hex, w);
    Log(L"leaderboard: %s: build hash %s (%d scripts, %d behaviour scripts, the ini, main.dll and the container: %d files, %d KB, %d ms)",
        why, w, (int32_t)r.scripts, (int32_t)r.ai, (int32_t)r.files, (int32_t)(r.bytes / 1024), (int32_t)(GetTickCount64() - t0));
    return 1;
}

static DWORD WINAPI BuildHashThread(void* arg)
{
    (void)arg;
    char hex[65];
    if (BuildHashNow(hex, L"the game started")) BuildHexSet(hex);
    return 0;
}

static int L_BuildHash(void* lua)
{
    char hex[65];
    BuildHexGet(hex);
    size_t n = 0;
    while (n < 64 && hex[n]) ++n;
    U.luaSetString(lua, hex, n == 64 ? 64 : 0);
    return 1;
}

static DWORD WINAPI PostWorker(void* arg)
{
    PostJob* j = (PostJob*)arg;
    j->status = -1;
    HANDLE wh = LoadLibraryW(L"winhttp.dll");
    HttpOpenFn hOpen = wh ? (HttpOpenFn)GetProcAddress(wh, "WinHttpOpen") : NULL;
    HttpConnectFn hConnect = wh ? (HttpConnectFn)GetProcAddress(wh, "WinHttpConnect") : NULL;
    HttpOpenRequestFn hRequest = wh ? (HttpOpenRequestFn)GetProcAddress(wh, "WinHttpOpenRequest") : NULL;
    HttpSendFn hSend = wh ? (HttpSendFn)GetProcAddress(wh, "WinHttpSendRequest") : NULL;
    HttpReceiveFn hReceive = wh ? (HttpReceiveFn)GetProcAddress(wh, "WinHttpReceiveResponse") : NULL;
    HttpQueryFn hQuery = wh ? (HttpQueryFn)GetProcAddress(wh, "WinHttpQueryHeaders") : NULL;
    HttpReadFn hRead = wh ? (HttpReadFn)GetProcAddress(wh, "WinHttpReadData") : NULL;
    HttpCloseFn hClose = wh ? (HttpCloseFn)GetProcAddress(wh, "WinHttpCloseHandle") : NULL;
    HttpTimeoutsFn hTimeouts = wh ? (HttpTimeoutsFn)GetProcAddress(wh, "WinHttpSetTimeouts") : NULL;
    wchar_t headers[320], sig[65];
    /* the build as it is now (the files may have changed since the game started: then this one, and it's logged) */
    char build[65], was[65];
    int haveBuild = BuildHashNow(build, L"sending a run");
    if (haveBuild) {
        BuildHexGet(was);
        if (was[0] && memcmp(was, build, 64) != 0) {
            wchar_t a[65];
            WidenHex(was, a);
            Log(L"leaderboard: the mod's files changed since the game started (its build hash was %s): this run goes as the files are now", a);
        }
        BuildHexSet(build);
    }
    if (!hOpen || !hConnect || !hRequest || !hSend || !hReceive || !hQuery || !hRead || !hClose
        || !SignBody(haveBuild ? build : NULL, j->body, j->len, sig)) {
        Log(L"leaderboard: WinHTTP or bcrypt missing; run not sent");
        j->state = 2;
        return 0;
    }
    static const wchar_t head[] = L"Content-Type: application/json\r\nX-SV-Signature: ";
    static const wchar_t bhead[] = L"X-SV-Build: ";
    size_t n = 0;
    for (size_t i = 0; head[i]; ++i) headers[n++] = head[i];
    for (size_t i = 0; sig[i]; ++i) headers[n++] = sig[i];
    headers[n++] = L'\r'; headers[n++] = L'\n';
    if (haveBuild) {
        for (size_t i = 0; bhead[i]; ++i) headers[n++] = bhead[i];
        for (size_t i = 0; i < 64; ++i) headers[n++] = (wchar_t)build[i];
        headers[n++] = L'\r'; headers[n++] = L'\n';
    }
    headers[n] = 0;
    /* Each proxy mode in turn (automatic, the system's, none), with TLS 1.2 / 1.3 switched on: WinHTTP's own defaults
     * can leave TLS 1.2 off (older or tweaked Windows), which Cloudflare refuses at once (a friend's test of 2026-10-23:
     * the browser reached the Worker, the game failed in 0.25 s). */
    typedef BOOL (*HttpOptionFn)(HANDLE, DWORD, void*, DWORD);
    HttpOptionFn hOption = (HttpOptionFn)GetProcAddress(wh, "WinHttpSetOption");
    static const DWORD kAccess[] = { 4 /* automatic proxy */, 0 /* the system's (netsh winhttp) */, 1 /* none */ };
    DWORD err = 0;
    for (size_t a = 0; a < sizeof(kAccess) / sizeof(kAccess[0]) && j->status < 0; ++a) {
        err = 0;
        HANDLE ses = hOpen(L"AC8SurvivalMode", kAccess[a], NULL, NULL, 0);
        if (ses && hOption) {
            DWORD tls = 0x00000800 | 0x00002000;                   /* WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 | TLS1_3 */
            if (!hOption(ses, 84 /* WINHTTP_OPTION_SECURE_PROTOCOLS */, &tls, sizeof(tls))) {
                tls = 0x00000800;                                  /* (no TLS 1.3 before Windows 11) */
                hOption(ses, 84, &tls, sizeof(tls));
            }
        }
        HANDLE con = ses ? hConnect(ses, SV_SUBMIT_HOST, 443, 0) : NULL;
        HANDLE req = con ? hRequest(con, L"POST", SV_SUBMIT_PATH, NULL, NULL, NULL, 0x00800000 /* WINHTTP_FLAG_SECURE */) : NULL;
        if (req && hTimeouts) hTimeouts(req, 10000, 10000, 15000, 15000);
        if (!ses || !con || !req) err = GetLastError();
        j->replyLen = 0;
        if (req && hSend(req, headers, (DWORD)-1, j->body, j->len, j->len, 0)) {
            if (hReceive(req, NULL)) {
                DWORD code = 0, sz = sizeof(code);
                if (hQuery(req, 19 | 0x20000000 /* STATUS_CODE | FLAG_NUMBER */, NULL, &code, &sz, NULL)) j->status = (int32_t)code;
                DWORD got = 0;
                while (j->replyLen < sizeof(j->reply) - 1 && hRead(req, j->reply + j->replyLen, (DWORD)(sizeof(j->reply) - 1 - j->replyLen), &got) && got)
                    j->replyLen += got;
            } else {
                err = GetLastError();
            }
        } else if (req) {
            err = GetLastError();
        }
        if (j->status < 0) {
            j->status = err ? -(int32_t)err : -1;                 /* why it couldn't get through (WinHTTP's error) */
            Log(L"leaderboard: proxy mode %d: no connection (%d)", (int32_t)kAccess[a], j->status);
        }
        if (req) hClose(req);
        if (con) hClose(con);
        if (ses) hClose(ses);
    }
    j->reply[j->replyLen] = 0;
    Log(L"leaderboard: run sent, status %d", j->status);
    j->state = 2;
    return 0;
}

static int L_Post(void* lua)
{
    if (!SV_SUBMIT_HOST[0] || sizeof(SV_SUBMIT_KEY) <= 1) return Ret(lua, SV_ERR_NO_SERVER);
    if (U.luaStackSize(lua) < 1 || !U.luaIsString(lua, 1)) return Ret(lua, SV_ERR_BAD_ARGS);
    StrView sv = { NULL, 0 };
    U.luaGetString(lua, &sv, 1);
    if (!sv.p || !sv.n || sv.n >= POST_BODY) return Ret(lua, SV_ERR_BAD_ARGS);
    for (int i = 0; i < POST_JOBS; ++i) {
        PostJob* j = &g_post[i];
        if (j->state != 0) continue;
        memcpy(j->body, sv.p, sv.n);
        j->len = (DWORD)sv.n; j->replyLen = 0; j->reply[0] = 0; j->status = 0;
        j->state = 1;
        HANDLE th = CreateThread(NULL, 0, PostWorker, j, 0, NULL);
        if (!th) { j->state = 0; return Ret(lua, SV_ERR_BUSY); }
        CloseHandle(th);
        return Ret(lua, i + 1);
    }
    return Ret(lua, SV_ERR_BUSY);
}

static int L_PostResult(void* lua)
{
    double id = 0;
    if (!ArgNumber(lua, &id) || id < 1 || id > POST_JOBS) return Ret(lua, SV_ERR_BAD_ARGS);
    PostJob* j = &g_post[(int)id - 1];
    if (j->state != 2) return Ret(lua, 0);
    int32_t st = j->status;
    j->state = 0;                                   /* read: free again (its reply stays until the next send) */
    return Ret(lua, st);
}

static int L_PostReply(void* lua)
{
    double id = 0;
    if (!ArgNumber(lua, &id) || id < 1 || id > POST_JOBS) { U.luaSetString(lua, "", 0); return 1; }
    PostJob* j = &g_post[(int)id - 1];
    U.luaSetString(lua, j->reply, j->replyLen);
    return 1;
}

/* SV_SteamName() -> the player's Steam name (UTF-8), or "" when Steam isn't there: the leaderboard's default pilot
 * name (user, 2026-10-23). Read from the steam_api64.dll the game has already loaded (its flat API: SteamFriends_v017,
 * the game's Steamworks 1.57); nothing is loaded or initialised here, and only the name is read. */
typedef void* (*SteamFriendsFn)(void);
typedef const char* (*PersonaNameFn)(void* friends);
static int L_SteamName(void* lua)
{
    HANDLE st = GetModuleHandleW(L"steam_api64.dll");
    const char* name = NULL;
    if (st) {
        static const char* kFriends[] = { "SteamAPI_SteamFriends_v017", "SteamAPI_SteamFriends_v018", "SteamAPI_SteamFriends_v016" };
        PersonaNameFn persona = (PersonaNameFn)GetProcAddress(st, "SteamAPI_ISteamFriends_GetPersonaName");
        for (size_t i = 0; persona && !name && i < sizeof(kFriends) / sizeof(kFriends[0]); ++i) {
            SteamFriendsFn get = (SteamFriendsFn)GetProcAddress(st, kFriends[i]);
            void* fr = get ? get() : NULL;
            if (fr) name = persona(fr);
        }
    }
    size_t n = 0;
    while (name && name[n] && n < 128) ++n;
    U.luaSetString(lua, name ? name : "", n);
    return 1;
}

#endif /* SV_OFFLINE */

static void RegisterLua(void* lua)
{
    static const struct { const char* name; LuaFn fn; } kFns[] = {
        { "SV_Version", L_Version }, { "SV_MenuChoice", L_MenuChoice }, { "SV_Spawn", L_Spawn }, { "SV_SetAircraft", L_SetAircraft },
        { "SV_UnitAlive", L_UnitAlive }, { "SV_LogUnits", L_LogUnits }, { "SV_Reset", L_Reset },
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
        { "SV_CoopFire", L_CoopFire }, { "SV_CoopShots", L_CoopShots }, { "SV_CoopPPShot", L_CoopPPShot },
        { "SV_CoopLoadout", L_CoopLoadout }, { "SV_SpawnCam", L_SpawnCam }, { "SV_StickNow", L_StickNow }, { "SV_InputNow", L_InputNow }, { "SV_Down", L_Down }, { "SV_Respawn", L_Respawn },
        { "SV_MemMB", L_MemMB }, { "SV_SndLoad", L_SndLoad }, { "SV_SndPlay", L_SndPlay }, { "SV_SndSet", L_SndSet }, { "SV_SndStop", L_SndStop }, { "SV_SndMaster", L_SndMaster },
#ifndef SV_OFFLINE
        { "SV_Post", L_Post }, { "SV_PostResult", L_PostResult }, { "SV_PostReply", L_PostReply }, { "SV_SteamName", L_SteamName },
        { "SV_BuildHash", L_BuildHash },
#endif
    };
    if (!ResolveUE4SS()) { Log(L"Lua bridge: UE4SS exports missing; Survival's spawner is off"); return; }
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
        { kSigBase,       NULL, sizeof(kSigBase),       NULL, 0 }, { kSigMainDecide,    NULL, sizeof(kSigMainDecide),    NULL, 0 },
        { kSigDiffDecide, NULL, sizeof(kSigDiffDecide), NULL, 0 }, { kSigDiffNext,      NULL, sizeof(kSigDiffNext),      NULL, 0 },
        { kSigGotoMenu,   NULL, sizeof(kSigGotoMenu),   NULL, 0 }, { kSigSetDifficulty, NULL, sizeof(kSigSetDifficulty), NULL, 0 },
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
