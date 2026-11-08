/* survival_rt_game.c : part of survival_rt.c (one translation unit: survival_rt.c #includes it in place; never
 *  compiled on its own). The game's systems Survival drives: its spawner (UE4SS's exports, FNames, reflected
 *  offsets), the teardown gate, recycled flights' unit actors destroyed later, the unit descs (spawn, pose,
 *  aircraft, AI level), the player's ammo, music and remote events, the pause menu's music player and its track
 *  clock, the flight input hook (the Anomaly's field) and the game's own Lua. */

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
/* 1: this level's spawner was found and has since gone (the level is being torn down): no search until SV_Reset.
 * (hotfix5: a joiner's crash of 2026-11-01 00:09:44, 0.73.37 hotfix4: the level going away after a pause, the
 * cached spawner no longer live, FindSpawner searched again and UE4SS's FindAllOf read a freed object's class in
 * GUObjectArray, an access violation at UE4SS.dll+0x2ab5bd, called from Survival's Lua tick.) */
static int      g_spawnerLost;

static int LiveObject(void* o)
{
    return o && Readable(o, 0x28) && !(*(uint32_t*)((uint8_t*)o + 8) & RF_NOT_LIVE);
}

/* ---- the teardown gate (runtime 0.32.22, plan F1a) ------------------------------------------------------------------
 * The crash on quit (Shazzy 2026-11-02 16:57:02 while DOWN, cressendo 2026-11-03 10:42:25 from flight; both 0.32.21):
 * UE4SS.dll+0x2ab5bd is the Lua UObject's property lookup (mov rcx, [GetClassPrivate(obj)] before FindProperty, in the
 * function at UE4SS+0x2aad40 with the "Tried setting member variable" / "The UObject instance is nullptr" texts): Survival's
 * Lua reading a field of an object the closing level had freed. The two main.dll "frames" (+0x1abe8, +0x68b7) are stale
 * return addresses the stack scan found: +0x1abe8 is SpawnerReady's call of ResolveUE4SS, +0x68b7 L_UnitAlive's call of
 * set_integer (named from the map of this source, whose code is byte for byte the shipped 0.32.21's), left by the
 * SV_UnitAlive levelGoing() asks in the same tick; neither runs UE4SS's property code. Both came about a second after
 * `this level's LiveUnitSpawner is gone`, which is levelGoing()'s one-second wait before it believes it: every part read
 * the level's objects for that second. The gate: closed the moment the spawner's world (kept when the spawner was found
 * live) is freed, marked garbage, being destroyed, or unreachable while the engine purges (never on a mere GC mark: a
 * pause-menu restart keeps its world, and one that makes its spawner again doesn't close it); open again at SV_Reset (the
 * next Survival level). While closed, SV_LevelGone() answers 1 (Lua holds its level work and drops its object lists:
 * sv_core.lua levelGate), the spawner answers "not ready", the deferred unit destroys are dropped (the level destroys
 * them) and an address from Lua is used only while it's a live object (ArgObject). */
static volatile int32_t g_teardown;            /* 1: closed: Survival's level is being torn down */
static void*            g_world;               /* the spawner's world, kept when it was found live (SpawnerReady) */
static int              GcPurgePending(void);  /* (flight.c: the engine's purge flags) */
static int              RcDrop(void);          /* (below: the deferred unit destroys) */

/* why o (an object kept by the runtime) is gone, or NULL while it's still the engine's live object */
static const wchar_t* ObjGoneWhy(void* o)
{
    uint8_t* p = (uint8_t*)o;
    if (!p || !Readable(p, 0x28)) return L"its memory was released";
    uint32_t rf = *(uint32_t*)(p + 8);
    if (rf & (0x8000 | 0x10000 | 0x40000000)) return L"it is being destroyed";   /* RF_BeginDestroyed, Finish, MirroredGarbage */
    if (!g_uoChunks) return LiveObject(p) ? NULL : L"its flags say it isn't live";
    if (UObjAllocated(p) == 0) return L"it was freed";
    int32_t idx = *(const int32_t*)(p + 0xC);
    const uint8_t* item = (*g_uoChunks)[idx >> 16] + (size_t)(idx & 0xFFFF) * 0x18;
    uint32_t f = *(const uint32_t*)(item + 8);
    if (f & UO_GARBAGE) return L"it was marked garbage";
    if ((f & *g_uoGcFlag) && GcPurgePending()) return L"it is unreachable and being purged";
    return NULL;
}

static void TeardownClose(const wchar_t* why)
{
    if (g_teardown) return;
    g_teardown = 1;
    int dropped = RcDrop();
    Log(L"teardown gate: closed (Survival's level is going: its world %p: %s): Lua holds its level work and drops its object "
        L"lists, the runtime touches no level object until the next Survival level (SV_Reset); %d deferred unit destroys "
        L"dropped (the level destroys them)", g_world, why, dropped);
    Crumb(L"teardown gate closed: world %p %s; %d deferred destroys dropped", g_world, why, dropped);
}

/* 1 the gate is closed (checked now: its world gone closes it) */
static int32_t  g_worldIdx;                    /* its InternalIndex and name (+0x18) when kept: a new world made in */
static uint64_t g_worldName;                   /* its memory (the main menu's, the same size) is another object */
static int TeardownCheck(void)
{
    if (g_teardown) return 1;
    if (!g_world) return 0;                            /* (no Survival level seen since SV_Reset) */
    const wchar_t* why = ObjGoneWhy(g_world);
    if (!why && (*(int32_t*)((uint8_t*)g_world + 0xC) != g_worldIdx || *(uint64_t*)((uint8_t*)g_world + 0x18) != g_worldName))
        why = L"its memory is another object's";
    if (!why) return 0;
    TeardownClose(why);
    return 1;
}

/* ---- a recycled flight's unit actor destroyed later (runtime 0.32.22, plan F2b) --------------------------------------
 * The crash at the round 3 bomber raid (Shazzy, 2026-11-02 16:06:37 and 18:02:16): a game worker in AC8's AI path
 * tracking (ULiveAIPathTickerSubsystem's FLivePathTrackTickFunction, flight.c's path tracker guard) read a freed object
 * 3-5 s after Survival destroyed the last bomber flight's unit actor (EA_Unit_01_Air0) for its respawn, 2-3 s after the
 * heavy flight's first spawn. Taking the unit off the phase's list is what lets its desc spawn again (hard rule 16); the
 * actor's destroy now waits g_rcWaitMs (Lua's CFG.recycle.destroy_after_s, SV_RecycleWait; 30 s by default, 0 the
 * 0.32.21 way: at once), done from the next spawner call after that, only while the unit is still a live object of this
 * level (a restart's or the level's own destroy came first: nothing). The gate drops the queue. */
#define RC_MAX 64
typedef struct { uint8_t* unit; int32_t idx; uint64_t due; wchar_t name[48]; } RcEntry;
static RcEntry  g_rc[RC_MAX];
static int      g_rcN;
static uint32_t g_rcWaitMs = 30000;
static uint32_t g_rcDone, g_rcSkipped;

static int RcDrop(void)
{
    int n = g_rcN;
    g_rcN = 0;
    return n;
}

/* 1 queued; 0 the queue is full (the caller destroys it at once, as before) */
static int RcDefer(uint8_t* unit, const wchar_t* name)
{
    if (!g_rcWaitMs || g_rcN >= RC_MAX || !Readable(unit, 0x10)) return 0;
    RcEntry* e = &g_rc[g_rcN++];
    e->unit = unit;
    e->idx = *(int32_t*)(unit + 0xC);
    e->due = GetTickCount64() + g_rcWaitMs;
    size_t k = 0;
    while (name && name[k] && k < 47) { e->name[k] = name[k]; ++k; }
    e->name[k] = 0;
    return 1;
}

/* the entries due: each unit actor destroyed if it's still the same live object (game thread: a spawner call) */
static void RcDrain(void)
{
    if (!g_rcN || g_teardown) return;
    uint64_t now = GetTickCount64();
    int keep = 0;
    for (int i = 0; i < g_rcN; ++i) {
        RcEntry e = g_rc[i];
        if (now < e.due) { g_rc[keep++] = e; continue; }
        const wchar_t* why = ObjGoneWhy(e.unit);
        if (!why && *(int32_t*)(e.unit + 0xC) != e.idx) why = L"its slot is another object's";
        if (why) {
            ++g_rcSkipped;
            Log(L"recycle %s: its old unit actor %p wasn't destroyed %d s on (%s: something else destroyed it)", e.name, e.unit,
                (int32_t)(g_rcWaitMs / 1000), why);
            Crumb(L"recycle %s: deferred destroy of %p skipped (%s)", e.name, e.unit, why);
            continue;
        }
        Crumb(L"recycle %s: destroying its old unit actor %p (deferred %d s)", e.name, e.unit, (int32_t)(g_rcWaitMs / 1000));
        g_destroyActor(e.unit, 0);
        ++g_rcDone;
        Crumb(L"recycle %s: destroyed", e.name);
        Log(L"recycle %s: its old unit actor %p destroyed, %d s after it was taken off the phase's list (%u so far, %u gone "
            L"before, %d waiting)", e.name, e.unit, (int32_t)(g_rcWaitMs / 1000), g_rcDone, g_rcSkipped, g_rcN - i - 1 + keep);
    }
    g_rcN = keep;
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
    if (g_spawner) {                                   /* it was found and has gone: the level is going away */
        g_spawnerLost = 1;
        Log(L"spawner: this level's LiveUnitSpawner is gone (the level is ending): no search until the next run");
        Crumb(L"spawner gone (teardown gate %s)", TeardownCheck() ? L"closed: its world is going too" : L"open: its world is still live");
    }
    g_spawner = NULL; g_phase = NULL; g_wd = NULL;
    if (g_spawnerLost) return 0;                       /* (FindAllOf over objects being freed crashed: hotfix5) */
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
    if (TeardownCheck()) return SV_ERR_NOT_READY;  /* (0.32.22: the level is being torn down) */
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
    if (world != g_world) {                            /* (0.32.22: the teardown gate watches this world) */
        Log(L"teardown gate: watching world %p (spawner %p)%s", world, g_spawner, g_world ? L"; it replaced the last one" : L"");
        g_worldIdx = *(int32_t*)((uint8_t*)world + 0xC);
        g_worldName = *(uint64_t*)((uint8_t*)world + 0x18);
        g_world = world;
    }
    RcDrain();                                         /* (0.32.22: the recycled flights' unit actors due) */
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

/* Takes the desc's last flight off the phase's list if it was shot down. 1 removed, 0 none, -1 still up.
 * force (0.32.22, SV_Recycle): 1 off the list even while it still counts aircraft alive; 2 that, its actor destroyed at
 * once (the 0.32.21 way: F2d's test). Otherwise the actor's destroy is deferred (RcDefer). */
static int Recycle(uint8_t* desc, const wchar_t* name, int force)
{
    uint8_t* unit = RegisteredUnit(*(uint32_t*)(desc + LY.uniqueId));
    if (!unit) return 0;
    int32_t alive = UnitArrayNum(unit, L"AliveChildAIGameObjects");
    if (alive != 0 && !force) {
        Log(L"spawn %s: its last flight is still up (%d alive); not spawned again", name, alive);
        return -1;
    }
    int later = force != 2 && RcDefer(unit, name);
    Crumb(L"recycle %s: unregistering its unit actor %p (%d alive)%s", name, unit, alive, later ? L", its destroy deferred" : L" and destroying it");
    g_unregisterUnit(g_phase, unit);
    if (!later) g_destroyActor(unit, 0);
    Crumb(L"recycle %s: done", name);
    if (later)
        Log(L"spawn %s: its last flight %s; took it off the phase's list, its unit actor %p destroyed %d s on (%d waiting)", name,
            alive ? L"was taken down (forced, aircraft still counted alive)" : L"was shot down", unit, (int32_t)(g_rcWaitMs / 1000), g_rcN);
    else
        Log(L"spawn %s: its last flight %s; took it off the phase's list and removed its unit actor%s", name,
            alive ? L"was taken down (forced, aircraft still counted alive)" : L"was shot down",
            force == 2 ? L" at once (forced)" : g_rcWaitMs ? L" (the deferred queue is full)" : L"");
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
    if (Recycle(desc, name, 0) < 0) return SV_ERR_UP;
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

/* (runtime 0.32.30) A track's event FString (+0x48) as text for the log, or "?" */
#define MPC_EVENT         0x48
#define MPC_STOPPED       0x64
static const wchar_t* MusicEventName(uint8_t* co)
{
    if (!co || !Readable(co + MPC_EVENT, 0x10)) return L"?";
    const wchar_t* s = *(const wchar_t**)(co + MPC_EVENT);
    int32_t n = *(int32_t*)(co + MPC_EVENT + 8);
    if (!s || n <= 1 || n > 256 || !Readable(s, (size_t)n * 2) || s[n - 1]) return L"?";
    return s;
}

/* (runtime 0.32.30; user, 2026-11-08: "add all the named music into the music player") Most of the online match tracks
 * Survival adds are Wwise "infinite" events: Play gives them the length -1 and the clock never ends them (Tick ends a
 * track only at a length >= 0: 0x147b285cc), so the player would stay on one for ever. In Survival's mission the music
 * player's own track (its manager's SoundController, not the ambience) gets SV_MusicLoop's length instead. */
static volatile int32_t g_musicLoopMs;             /* SV_MusicLoop(ms): 0 = off */
static void MusicLoopCap(uint8_t* co)
{
    if (g_musicLoopMs <= 0 || !Readable(co + MPC_CLOCK, 0x10) || *(float*)(co + MPC_LENGTH) >= 0) return;
    uint8_t* outer = PtrAt(co, UOBJ_OUTER);
    if (PtrAt(outer, MPM_CONTROLLER) != co || !MusicSurvivalGi()) return;
    *(float*)(co + MPC_LENGTH) = (float)g_musicLoopMs / 1000.0f;
    static uint32_t said;
    if (said++ < 24) Log(L"music player: %s loops for ever; it moves on after %d s", MusicEventName(co), g_musicLoopMs / 1000);
}

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
    MusicLoopCap((uint8_t*)tickable - 0x28);
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
    co = PtrAt((uint8_t*)manager, MPM_CONTROLLER);           /* (0.32.30) what plays now, for the added tracks' test */
    if (co && Readable(co + MPC_CLOCK, 0x10))
        Log(L"music player: now %s (%d ms)", MusicEventName(co), Ms(*(float*)(co + MPC_LENGTH)));
}

/* ---- the music player's track list (runtime 0.32.30; tools/re/MUSIC_BANKS.md 5) ------------------------------------
 * The list is the playlist database's (a game instance subsystem), built from DT_SoundMusicPlayerBGM by 0x147b26b50
 * each time a level's ULiveMusicPlayerSoundManager (a world subsystem) starts. A row is listed when its event is in a
 * loaded bank's database and it's unlocked (bIsEnableUnlock false, or its mission cleared); rows Lua adds afterwards
 * show only after a rebuild (SV_MusicBuild: 0x147b296f0(manager), the manager's own Initialize call). Each build also
 * grants every row it lists to the save's OwnedMusicList / NewlyOwnedMusicList, appending the names it doesn't have
 * (0x147b26f09-0x147b26f81). While Lua says Survival's rows are in (SV_MusicSave: the save object and those two arrays,
 * from reflection), the hook cuts each build's appends back off: the list shows them, the player's save never gets
 * Survival's track names or the stock tracks Survival unlocked (user's rule of 2026-10-24: nothing stock stays changed). */
typedef void (*MusicBuildFn)(void* obj);
typedef struct { uint8_t* data; int32_t num, max; } MsArray;
static uint8_t*      g_fMusicBuild;
static uint8_t*      g_fMusicRebuild;
static MusicBuildFn  g_nextMusicBuild;
static uint8_t* volatile g_msSave;                 /* LiveCampaignSaveGame Lua named, or NULL (off) */
static uint8_t* volatile g_msArr[2];               /* its OwnedMusicList, NewlyOwnedMusicList */
static int32_t       g_msBuilds, g_msCut;

static int MsArrayOk(const uint8_t* a)
{
    if (!a || ((uintptr_t)a & 7) || !Readable(a, sizeof(MsArray))) return 0;
    const MsArray* r = (const MsArray*)a;
    return r->num >= 0 && r->num <= r->max && r->max <= (1 << 16) && (r->num == 0 || Readable(r->data, (size_t)r->num * 8));
}

/* the arrays Lua named, still inside a live save object (a save loaded again makes a new one) */
static int MsSaveOk(void)
{
    uint8_t* s = g_msSave;
    if (!s) return 0;
    int live = UObjLive(s);
    if (live < 0) live = LiveObject(s);
    if (live != 1) return 0;
    for (int i = 0; i < 2; ++i) {
        uint8_t* a = g_msArr[i];
        if (!a || a < s + 0x28 || a >= s + 0x4000 || !MsArrayOk(a)) return 0;
    }
    return 1;
}

static void OnMusicBuild(void* db)
{
    int keep = MsSaveOk();
    int32_t before[2] = { 0, 0 };
    if (keep) for (int i = 0; i < 2; ++i) before[i] = ((MsArray*)g_msArr[i])->num;
    g_nextMusicBuild(db);
    ++g_msBuilds;
    int32_t cut = 0;
    if (keep && MsSaveOk()) {
        for (int i = 0; i < 2; ++i) {
            MsArray* r = (MsArray*)g_msArr[i];
            if (r->num > before[i]) { cut += r->num - before[i]; r->num = before[i]; }   /* (FNames: nothing to free) */
        }
        g_msCut += cut;
    }
    /* SoundList (+0x40): every row whose event a loaded bank has, 0x20 each at +0x28 (count +0x30); the database's own
     * playlists (+0x30, 0x20 each: key, then a TArray of those entries at +8, its count +0x10): the rows it listed */
    uint8_t* list = PtrAt((uint8_t*)db, 0x40);
    int32_t known = list && Readable(list + 0x30, 4) ? *(int32_t*)(list + 0x30) : -1;
    int32_t lists = -1, listed = 0;
    if (Readable((uint8_t*)db + 0x30, 0x10)) {
        uint8_t* ga = *(uint8_t**)((uint8_t*)db + 0x30);
        lists = *(int32_t*)((uint8_t*)db + 0x38);
        if (lists < 0 || lists > 64 || (lists && !Readable(ga, (size_t)lists * 0x20))) lists = -1;
        else for (int i = 0; i < lists; ++i) {
            int32_t n = *(int32_t*)(ga + (size_t)i * 0x20 + 0x10);
            if (n > 0 && n < 4096) listed += n;
        }
    }
    static uint32_t said;
    if (said++ < 24)
        Log(L"music player: track list built: %d tracks its banks have, %d listed (%d lists); %s %d names it granted to the save",
            known, listed, lists, keep ? L"Survival's rows are in: cut back off" : L"the game's own list: kept", keep ? cut : -1);
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
