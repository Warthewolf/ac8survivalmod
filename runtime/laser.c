/* laser.c : AC7's LaserInterceptor on AC8's native ALiveLaserInterceptor (runtime 0.32.26; docs/re/LASER_INTERCEPTOR.md 9).
 * Part of survival_rt.c's one translation unit: #included at the end of flight_guards.c (uobj.h, ArgObject, HookInline
 * and the guards' helpers above it). Never compiled alone.
 *
 * The user, 2026-11-07: "I want the entire weapon from ACE7 to be ported over". Survival's BP_SV_LaserInterceptor
 * (tools/laser7: AC7's wp_LaserInterceptor values, swing curve and Cascade beams on AC8's own class) is spawned by
 * Scripts/sv_escort_li.lua, one a ZFA-44, attached at its gun, with the class's own search off (SearchInterval 1e9):
 * Lua picks each missile (enemies' only, one beam a missile) and hands it over here; the class's own swing (AC7's curve)
 * turns the beam onto it and its own kill (ALiveWeaponBase::Intercepted: the "Intercepted" effect, the missile back to its
 * pool) ends it InterceptTime on.
 *   SV_LaserBegin(li, missile) -> 1 begun, 0 refused (the missile not a live one in flight, or no shooter), SV_ERR_*
 *   SV_LaserState(li [, 0])    -> 0 searching, 1 swinging, -1 not a laser; with 0: a swing given up (no kill)
 *   SV_LaserKills()            -> the kills its swings made (counted by the tick guard), -1 the tick isn't hooked
 *   SV_Intercept(missile)      -> 1 shot down (the game's own clean kill), 0 not (down already, not in flight), SV_ERR_*
 * The tick guard (the class's WeaponTick, sigs.h kSigLaserTick, hooked inline: no stock content uses the class, 9.2) covers
 * 9.4's crashes: a laser whose owner is gone doesn't tick (crashes 1 and 5); a swing whose missile is gone, freed, back in
 * its pool, or fired again by another shooter than the one at the hand-over is given up before the game reads it (crash 3,
 * and a recycled missile of our own side). All of it runs on the game thread (the tick, and Lua's calls). */

#define LI_STATE       0x794          /* int: 0 search, 1 swing (unreflected) */
#define LI_MISSILE     0x798          /* ALiveMissile* MissileToIntercept */
#define LI_TIMER       0x7a0          /* float (unreflected) */
#define LI_END         0x7c0          /* (past the swing's start point: what is read of a laser) */
#define WB_ROOT        0x1a0          /* AActor::RootComponent */
#define WB_INUSE       0x290          /* ALiveWeaponBase: bInUse (the pool's) */
#define WB_OWNER       0x368          /* OwningGameObject */
#define WB_COLLIDED    0x418
#define WB_DESTROYED   0x65a
#define SC_WORLD_LOC   0x220          /* USceneComponent::ComponentToWorld's translation (3 doubles; the swing reads it) */
#define LI_SLOT_TICK   228
#define WB_SLOT_COLLIDE 239

typedef void (*LiTickFn)(uint8_t* li, float dt);
typedef void (*LiBeginFn)(uint8_t* li, uint8_t* missile, float dist);
typedef void (*InterceptedFn)(uint8_t* weapon);
static uint8_t*  g_fLaserTick, *g_fLaserBegin, *g_fIntercepted;   /* found by FindFunctions (sigs.h) */
static LiTickFn  g_nextLaserTick;

#define LI_HANDS 64
typedef struct { uint8_t* li; uint8_t* m; uint8_t* shooter; } LiHand;   /* each laser's last hand-over */
static LiHand            g_liHand[LI_HANDS];
static volatile uint32_t g_liKills, g_liGiveUps, g_liOwnerless, g_liIntercepts;

/* a weapon in flight: allocated, not garbage, in use (pooled weapons), not collided, not destroyed */
static int LiWeaponFlying(const uint8_t* w)
{
    if (!w || ((uintptr_t)w & 7) || (uintptr_t)w < 0x10000) return 0;
    int live = UObjLive(w);
    if (live == 0) return 0;
    if (live < 0 && !Readable(w, WB_DESTROYED + 1)) return 0;
    if (*(const uint32_t*)(w + 8) & RF_MIRRORED_GARBAGE) return 0;
    return w[WB_INUSE] != 0 && !w[WB_COLLIDED] && !w[WB_DESTROYED];
}

/* a live object whose class is ALiveLaserInterceptor (its vtable's WeaponTick is the class's: a blueprint of it shares
 * the native vtable; the inline hook leaves the slot as it was) */
static int LiIsLaser(const uint8_t* li)
{
    if (!g_fLaserTick || !li || ((uintptr_t)li & 7) || !Readable(li, LI_END)) return 0;
    if (UObjLive(li) == 0 || (*(const uint32_t*)(li + 8) & RF_MIRRORED_GARBAGE)) return 0;
    void* const* vt = *(void* const* const*)li;
    if (!vt || !Readable(vt + LI_SLOT_TICK, 8)) return 0;
    return vt[LI_SLOT_TICK] == (void*)g_fLaserTick;
}

static LiHand* LiHandOf(const uint8_t* li, int make)
{
    LiHand* spare = NULL;
    for (int i = 0; i < LI_HANDS; ++i) {
        if (g_liHand[i].li == li) return &g_liHand[i];
        if (!spare && (!g_liHand[i].li || UObjLive(g_liHand[i].li) == 0)) spare = &g_liHand[i];
    }
    if (!make) return NULL;
    if (!spare) spare = &g_liHand[(uintptr_t)li % LI_HANDS];
    spare->li = (uint8_t*)li; spare->m = NULL; spare->shooter = NULL;
    return spare;
}

static double LiDistance(const uint8_t* a, const uint8_t* b)   /* between two actors' roots (cm), -1 unread */
{
    const uint8_t* ra = *(const uint8_t* const*)(a + WB_ROOT);
    const uint8_t* rb = *(const uint8_t* const*)(b + WB_ROOT);
    if (!ra || !rb || !Readable(ra, SC_WORLD_LOC + 24) || !Readable(rb, SC_WORLD_LOC + 24)) return -1;
    const double* pa = (const double*)(ra + SC_WORLD_LOC);
    const double* pb = (const double*)(rb + SC_WORLD_LOC);
    double dx = pa[0] - pb[0], dy = pa[1] - pb[1], dz = pa[2] - pb[2], d2 = dx * dx + dy * dy + dz * dz;
    if (!(d2 >= 0) || d2 > 1e16) return -1;                /* (NaN or > 1000 km: not a place) */
    double x = d2 > 1 ? d2 / 2 : 1;                        /* (Newton's square root: no CRT here) */
    for (int i = 0; i < 64; ++i) x = 0.5 * (x + d2 / x);
    return x;
}

static void OnLaserTick(uint8_t* li, float dt)
{
    uint8_t* own = *(uint8_t**)(li + WB_OWNER);
    if (!own || UObjLive(own) == 0 || (*(const uint32_t*)(own + 8) & RF_MIRRORED_GARBAGE)) {
        uint32_t n = __atomic_add_fetch(&g_liOwnerless, 1, __ATOMIC_RELAXED);
        if (n <= 32) Crumb(L"laser: %p's owner %p gone: not ticked", li, own);
        if (n <= 4) Log(L"laser: an anti-missile laser %p with its owner %p gone: not ticked (%u ticks so far; Lua removes it)", li, own, n);
        return;
    }
    int32_t* st = (int32_t*)(li + LI_STATE);
    uint8_t* m = NULL;
    if (*st == 1) {
        m = *(uint8_t**)(li + LI_MISSILE);
        LiHand* h = LiHandOf(li, 0);
        const wchar_t* why = NULL;
        if (!m) why = L"no missile";
        else if (!LiWeaponFlying(m)) why = L"down, freed or back in its pool";
        else if (!*(uint8_t**)(m + WB_OWNER)) why = L"no shooter";
        else if (h && h->m && h->m != m) why = L"not the one handed over";
        else if (h && h->m == m && *(uint8_t**)(m + WB_OWNER) != h->shooter) why = L"fired again by another shooter";
        if (why) {
            *st = 0;
            *(float*)(li + LI_TIMER) = 0;
            if (h) h->m = NULL;
            uint32_t n = __atomic_add_fetch(&g_liGiveUps, 1, __ATOMIC_RELAXED);
            if (n <= 64) Crumb(L"laser: %p's swing on %p given up (%s)", li, m, why);
            if (n <= 8) Log(L"laser: %p's swing on %p given up: %s (%u so far)", li, m, why, n);
            m = NULL;
        }
    }
    g_nextLaserTick(li, dt);
    if (m && *st == 0 && m[WB_COLLIDED]) {                /* (its swing's end: the class's own kill) */
        uint32_t n = __atomic_add_fetch(&g_liKills, 1, __ATOMIC_RELAXED);
        LiHand* h = LiHandOf(li, 0);
        if (h && h->m == m) h->m = NULL;
        if (n <= 64) Crumb(L"laser: %p shot down %p", li, m);
    }
}

/* SV_LaserBegin(li, missile) -> 1 its swing begun (BeginIntercept: from where the beam points now, AC7's curve, the kill
 * InterceptTime on), 0 refused (the missile isn't a live one in flight, has no shooter, or the laser's owner is gone),
 * SV_ERR_BAD_ARGS (not a laser), SV_ERR_NO_GAME (not found). A laser swinging already is turned onto the new one. */
static int L_LaserBegin(void* lua)
{
    uint8_t* li = ArgObject(lua);
    uint8_t* m = ArgObject(lua);
    if (!g_fLaserBegin || !g_nextLaserTick) return Ret(lua, SV_ERR_NO_GAME);
    if (!LiIsLaser(li) || !m) return Ret(lua, SV_ERR_BAD_ARGS);
    uint8_t* own = *(uint8_t**)(li + WB_OWNER);
    if (!own || UObjLive(own) == 0) return Ret(lua, 0);
    if (!LiWeaponFlying(m) || !Readable(m, WB_OWNER + 8)) return Ret(lua, 0);
    uint8_t* shooter = *(uint8_t**)(m + WB_OWNER);
    if (!shooter) return Ret(lua, 0);
    double d = LiDistance(li, m);
    if (d < 0) return Ret(lua, 0);
    LiHand* h = LiHandOf(li, 1);
    h->m = m; h->shooter = shooter;
    ((LiBeginFn)g_fLaserBegin)(li, m, (float)d);
    static uint32_t said;
    if (said++ < 8) Log(L"laser: %p begins its swing on %p (%d m off, shooter %p)", li, m, (int32_t)(d / 100), shooter);
    return Ret(lua, 1);
}

/* SV_LaserState(li [, 0]) -> 0 searching, 1 swinging, -1 not a laser; with 0, a swing is given up (no kill: the game
 * reads no missile in state 0; MissileToIntercept itself is never cleared, 9.4) */
static int L_LaserState(void* lua)
{
    uint8_t* li = ArgObject(lua);
    double v = -1;
    ArgNumber(lua, &v);
    if (!LiIsLaser(li)) return Ret(lua, -1);
    int32_t st = *(int32_t*)(li + LI_STATE);
    if (v == 0 && st == 1) {
        *(int32_t*)(li + LI_STATE) = 0;
        *(float*)(li + LI_TIMER) = 0;
        LiHand* h = LiHandOf(li, 0);
        if (h) h->m = NULL;
    }
    return Ret(lua, st);
}

/* (0.32.28) SV_LaserOwner(li, plane) -> 1 its OwningGameObject is that plane now, 0 the plane isn't a live object,
 * SV_ERR_BAD_ARGS (not a laser). A laser Lua spawns has none (the game sets it when a plane's fire control fires one), so
 * the tick guard held it and every SV_LaserBegin was refused: the hosts' logs of 0.74.21 and 0.74.23, "owner NOT its plane",
 * and the user: "the ZFA-44's did not fire their laser". One aligned store, on the game thread (Lua's call). */
static int L_LaserOwner(void* lua)
{
    uint8_t* li = ArgObject(lua);
    uint8_t* own = ArgObject(lua);
    if (!LiIsLaser(li)) return Ret(lua, SV_ERR_BAD_ARGS);
    if (!own || ((uintptr_t)own & 7) || !Readable(own, 0x30) || UObjLive(own) == 0) return Ret(lua, 0);
    __atomic_store_n((uint8_t**)(li + WB_OWNER), own, __ATOMIC_SEQ_CST);
    static uint32_t said;
    if (said++ < 8) Log(L"laser: %p's owner set to %p", li, own);
    return Ret(lua, 1);
}

static int L_LaserKills(void* lua)
{
    return Ret(lua, g_nextLaserTick ? (int64_t)g_liKills : -1);
}

/* SV_Intercept(missile) -> 1 shot down by the game's own interceptor kill (ALiveWeaponBase::Intercepted), 0 not (not in
 * flight: down already, back in its pool), SV_ERR_BAD_ARGS (not a weapon: Lua checks IsA LiveWeaponBase first; here its
 * Collide slot must be the game's code), SV_ERR_NO_GAME */
static int L_Intercept(void* lua)
{
    uint8_t* m = ArgObject(lua);
    if (!g_fIntercepted) return Ret(lua, SV_ERR_NO_GAME);
    if (!m || ((uintptr_t)m & 7) || !Readable(m, WB_DESTROYED + 1)) return Ret(lua, SV_ERR_BAD_ARGS);
    void* const* vt = *(void* const* const*)m;
    if (!vt || !Readable(vt + WB_SLOT_COLLIDE, 8) || !InGame(vt[WB_SLOT_COLLIDE])) return Ret(lua, SV_ERR_BAD_ARGS);
    if (!LiWeaponFlying(m)) return Ret(lua, 0);
    ((InterceptedFn)g_fIntercepted)(m);
    uint32_t n = __atomic_add_fetch(&g_liIntercepts, 1, __ATOMIC_RELAXED);
    if (n <= 8) Log(L"laser: %p shot down by SV_Intercept (%u so far)", m, n);
    return Ret(lua, m[WB_COLLIDED] ? 1 : 0);
}

static void LiInstall(void)
{
    Log(L"laser: the anti-missile laser's tick %p, its swing's start %p, the interceptors' kill %p", g_fLaserTick, g_fLaserBegin,
        g_fIntercepted);
    if (!g_fLaserTick || !g_fLaserBegin) { Log(L"laser: not found (another game build?): AC7's LaserInterceptor stays off"); return; }
    if (!HookInline(g_fLaserTick, 16, (void*)OnLaserTick, (void**)&g_nextLaserTick, L"laser: anti-missile laser tick"))
        Log(L"laser: the tick %p couldn't be hooked: AC7's LaserInterceptor stays off (unguarded)", g_fLaserTick);
}
