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

#define RT_VERSION           L"0.4.0"
#define SURVIVAL_MISSION_ID  9101          /* our row in DT_LiveMissionTable (Stonehenge: 9001) */
#define SURVIVAL_ARGS        L"SurvivalMode" /* StringArgs of our main-menu row               */
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
        } else if (*fmt == L'd') {
            int32_t d = va_arg(ap, int32_t);
            uint64_t v = d < 0 ? (uint64_t)(-(int64_t)d) : (uint64_t)d;
            if (d < 0) PUT(L'-');
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
        if (!WriteMem(fn + 6, &detour, 8, 1)) return 0;
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
    int d = Difficulty(page);
    if (d) g_setDifficulty(page, (uintptr_t)(uint8_t)d);
    else Log(L"start: could not tell the chosen difficulty; keeping the game's current one");
    uint8_t* ctx = Context(page);
    if (ctx) {
        int mode = g_savedMode >= 0 ? g_savedMode : ctx[CTX_MODE];
        Log(L"start (%s): difficulty %s, context mode %d -> %d, mission %d -> %d", why,
            d ? kDiffNames[d - 1] : L"unchanged", (int32_t)ctx[CTX_MODE], (int32_t)mode,
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

/* ---- handlers ----------------------------------------------------------- */
static uintptr_t OnMainDecide(void* widget)
{
    const FString* a = SelectedArgs(widget, NULL);
    int mine = ArgsEqual(a, SURVIVAL_ARGS);
    g_chosen = mine;
    if (mine) {
        uint8_t* ctx = Context(widget);
        g_savedMode = ctx ? ctx[CTX_MODE] : -1;
        g_page = NULL;
        Log(L"main menu: Survival Mode chosen, opening the difficulty select (context mode %d)", (int32_t)g_savedMode);
    }
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
    { L"SV_Mission_Name",      L"Survival Mode", { 0 } },
    { L"SV_Mission_Subtitle",  L"Comona Island", { 0 } },
    { L"SV_Mission_Number",    L"SURVIVAL", { 0 } },
    { L"SV_Mission_Location",  L"Comona Island", { 0 } },
    { L"SV_Mission_Objective", L"Survive as many rounds as you can. Protect the airfield.", { 0 } },
    { L"SV_Mission_Briefing",  L"Enemy waves grow every round, with a special attack every fifth. "
                               L"Earn credits for kills and spend them at Comona Airport between rounds.", { 0 } },
};

static void InitText(void)
{
    for (size_t i = 0; i < sizeof(g_text) / sizeof(g_text[0]); ++i) {
        int32_t n = (int32_t)WLen(g_text[i].text) + 1;
        g_text[i].fs = (FString){ (wchar_t*)g_text[i].text, n, n };
    }
}

static uintptr_t OnText(void* table, uintptr_t flag, void* keyp, void* found)
{
    const FString* key = (const FString*)keyp;
    if (key && key->data && key->num > 4 && key->data[0] == L'S' && key->data[1] == L'V' && key->data[2] == L'_') {
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
    static uint8_t tp[64], tm[64], xp[64], xm[64];
    HookedPattern(tp, tm, sizeof(kSigTransition), kSigTransitionTail, sizeof(kSigTransitionTail));
    HookedPattern(xp, xm, 15, kSigText + 15, sizeof(kSigText) - 15);
    Pattern p[] = {
        { kSigBase,       NULL, sizeof(kSigBase),       NULL, 0 }, { kSigMainDecide,    NULL, sizeof(kSigMainDecide),    NULL, 0 },
        { kSigDiffDecide, NULL, sizeof(kSigDiffDecide), NULL, 0 }, { kSigDiffNext,      NULL, sizeof(kSigDiffNext),      NULL, 0 },
        { kSigGotoMenu,   NULL, sizeof(kSigGotoMenu),   NULL, 0 }, { kSigSetDifficulty, NULL, sizeof(kSigSetDifficulty), NULL, 0 },
        { kSigTransition, NULL, sizeof(kSigTransition), NULL, 0 }, { tp, tm, sizeof(kSigTransition) + sizeof(kSigTransitionTail), NULL, 0 },
        { kSigText,       NULL, sizeof(kSigText),       NULL, 0 }, { xp, xm, sizeof(kSigText), NULL, 0 },
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
    Log(L"game functions (%d ms): base %p, main decide %p, difficulty decide %p, next %p, goto %p, set difficulty %p, transition %p, text %p",
        (int32_t)(GetTickCount64() - t0), g_fBase, g_fMainDecide, g_fDiffDecide, g_fDiffNext,
        (void*)g_gotoMenu, (void*)g_setDifficulty, g_fTransition, g_fText);
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
typedef struct { union { wchar_t buf[8]; wchar_t* ptr; } u; size_t size; size_t cap; } MsvcWString;
_Static_assert(sizeof(MsvcWString) == 32, "std::wstring layout");

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

static void* const g_modVtable[1 + VTABLE_SLOTS] = {
    [0]                  = NULL,
    [1]                  = (void*)Mod_DeletingDtor,
    [2 ... VTABLE_SLOTS] = (void*)Mod_NoOp,
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
    SetWString((MsvcWString*)(mod + 0x60), L"Survival Mode: main menu entry and texts");
    SetWString((MsvcWString*)(mod + 0x80), L"voidcallsreaper");
    if (g_instances++ == 0) {
        OpenLog();
        Log(L"AC8 Survival Mode runtime %s", RT_VERSION);
        HANDLE th = CreateThread(NULL, 0, Worker, NULL, 0, NULL);
        if (th) CloseHandle(th); else Log(L"could not start the install thread");
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
