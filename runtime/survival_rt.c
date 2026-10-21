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

#define RT_VERSION           L"0.8.0"
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
    if (!g_spawnUnit || !g_unregisterUnit || !g_destroyActor || !ResolveLayout()) return SV_ERR_NO_GAME;
    return FindSpawner() ? 1 : SV_ERR_NOT_READY;
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
    GL.slot = (void**)(lea + 7 + *(int32_t*)(lea + 3));
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

/* SV_Version() -> "0.8.0" */
static int L_Version(void* lua)
{
    static const char v[] = "0.8.0";
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
    if (U.luaStackSize(lua) < 1 || !U.luaIsString(lua, 1)) { U.luaSetString(lua, "-4\tno code", 9); return 1; }
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

/* SV_Reset(): forget the level's spawner (Lua calls it when a level loads) */
static int L_Reset(void* lua)
{
    g_spawner = NULL; g_phase = NULL; g_wd = NULL;
    return Ret(lua, 1);
}

static void RegisterLua(void* lua)
{
    static const struct { const char* name; LuaFn fn; } kFns[] = {
        { "SV_Version", L_Version }, { "SV_Spawn", L_Spawn }, { "SV_SetAircraft", L_SetAircraft },
        { "SV_UnitAlive", L_UnitAlive }, { "SV_LogUnits", L_LogUnits }, { "SV_Reset", L_Reset },
        { "SV_Ammo", L_Ammo }, { "SV_SetAmmo", L_SetAmmo }, { "SV_FreeRestock", L_SetFreeRestock },
        { "SV_GameLua", L_GameLua }, { "SV_GameLuaState", L_GameLuaState },
    };
    if (!ResolveUE4SS()) { Log(L"Lua bridge: UE4SS exports missing; Survival's spawner is off"); return; }
    for (size_t i = 0; i < sizeof(kFns) / sizeof(kFns[0]); ++i) {
        MsvcString s; memset(&s, 0, sizeof(s));
        size_t n = 0;
        while (kFns[i].name[n]) ++n;
        memcpy(s.u.buf, kFns[i].name, n + 1);         /* every name fits the small-string buffer (<= 15) */
        s.size = n; s.cap = 15;
        LuaFn fn = kFns[i].fn;
        U.luaRegister(lua, &s, &fn);
    }
    Log(L"Lua bridge: SV_Version, SV_Spawn, SV_SetAircraft, SV_UnitAlive, SV_LogUnits, SV_Reset, SV_Ammo, SV_SetAmmo, SV_FreeRestock, SV_GameLua, SV_GameLuaState registered");
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
    static uint8_t tp[64], tm[64], xp[64], xm[64];
    HookedPattern(tp, tm, sizeof(kSigTransition), kSigTransitionTail, sizeof(kSigTransitionTail));
    HookedPattern(xp, xm, 15, kSigText + 15, sizeof(kSigText) - 15);
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
    Log(L"game functions (%d ms): base %p, main decide %p, difficulty decide %p, next %p, goto %p, set difficulty %p, transition %p, text %p",
        (int32_t)(GetTickCount64() - t0), g_fBase, g_fMainDecide, g_fDiffDecide, g_fDiffNext,
        (void*)g_gotoMenu, (void*)g_setDifficulty, g_fTransition, g_fText);
    Log(L"spawn functions: spawn unit %p, unregister unit %p, unit check %p, destroy actor %p",
        (void*)g_spawnUnit, (void*)g_unregisterUnit, g_fUnitIdSpawned, (void*)g_destroyActor);
    Log(L"ammo functions: node execute %p, flare lambda %p, weapons lambda %p, free restock %p", g_fAmmoExecute, g_fAmmoFlare, g_fAmmoWeapons, g_fFreeRestock);
    Log(L"game Lua: GetGameLuaState %p", g_fGameLuaState);
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
