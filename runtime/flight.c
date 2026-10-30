/* =============================================================================
 *  Flight sync and the DOWN state (runtime 0.28.5; tools/re/COOP.md 8, tools/re/KILLS_HEALTH_DEATH.md 7). Included by
 *  survival_rt.c after coop.c (it uses coop.c's plane checks, pose reader and clock).
 *    SV_CoopFire(shooter, slot, target)  an AI plane fires its fire-control slot `slot` at `target` through the game's
 *                                        own one-shot fire (what LiveFireOneShotWeapon runs): another player's shots
 *                                        on their stand-in, the host's enemies' shots on a joiner's copies
 *    SV_InputNow()                       the local plane's last flight input (BuildFlightInput's out)
 *    SV_Down(plane, cx, cy, alt, radius) DOWN: the local plane circles a point on its own (down_ctl.c), the player's
 *                                        stick, throttle and brake ignored; SV_Down(0) gives them back
 *    SV_Respawn(plane, x, y, z, p, y, r) the player plane's own respawn (Online Mode's) at that pose
 *  All of it runs on the game thread: the Lua calls from Survival's game-thread tick, the input hook from the plane's
 *  update (OnBuildInput).
 * ============================================================================= */

#include "down_ctl.c"

#define SV_ERR_RATE      -10    /* SV_CoopFire: FIRE_PER_S calls this second for that shooter already: refused        */
#define SV_ERR_FIRE_NO   -11    /* SV_CoopFire: the game's fire returned false (the shooter inactive, dead, or without
                                   a live fire-control system)                                                        */
#define SV_ERR_NOT_LOCAL -12    /* SV_Down / SV_Respawn: not the local player's plane                                 */
#define SV_ERR_SHOOTER   -13    /* SV_CoopFire: the shooter isn't a live AI plane with a fire-control system           */
#define SV_ERR_TARGET    -14    /* SV_CoopFire: the target isn't 0 or a live game object (a LiveGameObject)            */

static uint8_t* g_fFireOne, *g_fFireExec, *g_fPPRespawn;   /* found by FindFunctions (sigs.h) */

/* The local player's plane: PlayerOwner(world) (the ammo node's, AMMO.md) of Survival's level, from the spawner that
 * Lua's calls keep found (never searched for here: cheap enough for every Lua tick). NULL outside the mission. */
static uint8_t* FlLocalCached(void)
{
    if (!ResolveAmmo() || !g_spawner || !LiveObject(g_spawner) || *(void**)g_spawner != g_spawnerVt) return NULL;
    void* world = VCall(g_spawner, VF_WORLD);
    if (!world || !LiveObject(world)) return NULL;
    uint8_t* o = (uint8_t*)AM.owner(world);
    return o && LiveObject(o) && CoKind(o) == 2 ? o : NULL;
}

/* The same, finding the spawner if need be (for Lua's rare calls); NULL with *err an SV_ERR code */
static uint8_t* FlLocal(int64_t* err)
{
    if (!ResolveAmmo()) { *err = AM.state < 0 ? SV_ERR_NO_GAME : SV_ERR_NOT_READY; return NULL; }
    int r = SpawnerReady();
    if (r != 1) { *err = r; return NULL; }
    uint8_t* o = FlLocalCached();
    if (!o) *err = SV_ERR_NOT_READY;
    return o;
}

/* ---- SV_CoopFire ------------------------------------------------------------------------------------------------
 * FireOne(shooter, slot, target, &zero offset, 0) is exactly the call LiveFireOneShotWeapon's Execute makes (+0x363):
 * ELiveWeaponNumber WN_WEAPON_1..6 = 0..5 = the fire-control slot (hard rule 40). Its own checks (active, alive, a live
 * FCS) make it answer false rather than fire; a slot past the shooter's modules does nothing (0x147c0aa20 checks the
 * count). True means the shot was queued: the weapon module may still hold it (e.g. a fire permission off). The target
 * is read as a game object (its weak pointer, root component, virtual +0xae8 / +0xaf0 / +0x8e8, its alive fields), so
 * it must be a LiveGameObject: checked by its class having the reflected HealthInternal at the offset FireOne reads. */
typedef uint8_t (*FireOneFn)(void* shooter, uint8_t weapon, void* target, const double* offset, uint64_t arg5);
#define FIRE_PER_S 25
static struct {
    int state;                              /* 0 not tried, 1 ok, -1 not found */
    FireOneFn fn;
    int32_t active, dead, health, fcs;      /* offsets FireOne reads */
    uint32_t fired, refusedByGame, refusedRate, refusedArgs;
    double lastSummary;
    int said[8];                            /* refusals logged once per kind */
} FI;

static int FireResolve(void)
{
    if (FI.state) return FI.state > 0;
    if (!g_scanned) return 0;
    FI.state = -1;
    uint8_t* f = g_fFireOne, *ex = g_fFireExec;
    if (!f) { Log(L"coop fire: the game's one-shot fire wasn't found (other game version?); SV_CoopFire is off"); return 0; }
    if (ex && (ex[0x363] != 0xE8 || Rel32(ex + 0x363) != f)) {
        Log(L"coop fire: LiveFireOneShotWeapon's Execute %p doesn't call %p at +363; SV_CoopFire is off", ex, f);
        return 0;
    }
    if (f[0x28] != 0x80 || f[0x29] != 0xB9 || f[0x2e] != 0x00 ||                               /* cmp byte [rcx+d32], 0 */
        f[0x40] != 0x40 || f[0x41] != 0x38 || f[0x42] != 0xB1 ||                               /* cmp byte [rcx+d32], sil */
        f[0x4d] != 0x66 || f[0x4e] != 0x0F || f[0x4f] != 0x6E || f[0x50] != 0x81 ||            /* movd xmm0, [rcx+d32] */
        f[0x6e] != 0x48 || f[0x6f] != 0x8B || f[0x70] != 0x81) {                               /* mov rax, [rcx+d32] */
        Log(L"coop fire: the one-shot fire %p isn't the expected shape; SV_CoopFire is off", f);
        return 0;
    }
    FI.active = *(int32_t*)(f + 0x2a); FI.dead = *(int32_t*)(f + 0x43);
    FI.health = *(int32_t*)(f + 0x51); FI.fcs = *(int32_t*)(f + 0x71);
    if (FI.active <= 0 || FI.active > 0x8000 || FI.dead <= 0 || FI.dead > 0x8000 || FI.health <= 0 || FI.health > 0x8000 ||
        FI.fcs <= 0 || FI.fcs > 0x8000) {
        Log(L"coop fire: the one-shot fire's offsets are implausible; SV_CoopFire is off");
        return 0;
    }
    FI.fn = (FireOneFn)f;
    FI.state = 1;
    Log(L"coop fire: one-shot fire %p (LiveFireOneShotWeapon's Execute %p calls it): active byte +%x, dead flag +%x, "
        L"HealthInternal +%x, fire-control system +%x; at most %d shots a second per shooter", f, ex, (uint32_t)FI.active,
        (uint32_t)FI.dead, (uint32_t)FI.health, (uint32_t)FI.fcs, (int32_t)FIRE_PER_S);
    if (!ex) Log(L"coop fire: (LiveFireOneShotWeapon's Execute wasn't found to confirm it)");
    return 1;
}

/* Per class: whether it's a LiveGameObject (reflected HealthInternal where FireOne reads it) and has a fire-control
 * system where FireOne reads it (LiveAIGameObject.FireControlSystemComponent). Looked up once per class. */
typedef struct { void* cls; int8_t lgo, fcs; } FlClassInfo;
static FlClassInfo g_flCls[48];
static int32_t     g_flClsN, g_flClsNext;
static const FlClassInfo* FlClass(uint8_t* obj)
{
    void* cls = *(void**)(obj + 0x10);                                  /* UObjectBase::ClassPrivate */
    for (int32_t i = 0; i < g_flClsN; ++i) if (g_flCls[i].cls == cls) return &g_flCls[i];
    FlClassInfo* c = &g_flCls[g_flClsN < 48 ? g_flClsN++ : (g_flClsNext++ % 48)];
    uint8_t* h = (uint8_t*)U.valuePtr(obj, L"HealthInternal");
    uint8_t* f = (uint8_t*)U.valuePtr(obj, L"FireControlSystemComponent");
    c->cls = cls;
    c->lgo = h && h == obj + FI.health;
    c->fcs = f && f == obj + FI.fcs;
    return c;
}

/* The per-shooter rate window */
typedef struct { uint8_t* obj; double at; int32_t n; int said; } FlRate;
static FlRate g_flRate[64];
static FlRate* FireRate(uint8_t* shooter, double now)
{
    FlRate* oldest = &g_flRate[0];
    for (int i = 0; i < 64; ++i) {
        FlRate* r = &g_flRate[i];
        if (r->obj == shooter) {
            if (now - r->at >= 1.0) { r->at = now; r->n = 0; }
            return r;
        }
        if (!r->obj || r->at < oldest->at) oldest = r;
        if (!r->obj) break;
    }
    oldest->obj = shooter; oldest->at = now; oldest->n = 0; oldest->said = 0;
    return oldest;
}

static int FireRefuse(void* lua, int kind, int64_t code, const wchar_t* why, void* shooter, int32_t slot, void* target)
{
    if (kind == 1) ++FI.refusedRate; else ++FI.refusedArgs;
    if (kind >= 0 && kind < 8 && !FI.said[kind]) {
        FI.said[kind] = 1;
        Log(L"coop fire: refused (%d): %s (shooter %p, slot %d, target %p); further refusals of this kind are only counted",
            (int32_t)code, why, shooter, slot, target);
    }
    return Ret(lua, code);
}

static void FireSummary(double now)
{
    if (now - FI.lastSummary < 60.0) return;
    if (FI.lastSummary > 0)
        Log(L"coop fire: %u shots queued, %u refused by the game (returned false), %u over %d a second, %u bad calls",
            FI.fired, FI.refusedByGame, FI.refusedRate, (int32_t)FIRE_PER_S, FI.refusedArgs);
    FI.lastSummary = now;
}

/* SV_CoopFire(shooter, slot, target) -> 1 (the game's fire queued the shot), or SV_ERR_BAD_ARGS (slot not 0-5, no
 * shooter), SV_ERR_NO_GAME, SV_ERR_SHOOTER, SV_ERR_TARGET, SV_ERR_RATE, SV_ERR_FIRE_NO (the game's fire said no).
 * shooter / target: addresses (obj:GetAddress()); target 0 = none. */
static int L_CoopFire(void* lua)
{
    uint8_t* shooter = ArgObject(lua);
    double slot = -1;
    int haveSlot = ArgNumber(lua, &slot);
    uint8_t* target = ArgObject(lua);
    int32_t si = haveSlot && slot >= 0 && slot <= 5 ? (int32_t)slot : -1;
    double now = CoNow();
    FireSummary(now);
    if (!FireResolve() || !ResolveUE4SS()) return Ret(lua, SV_ERR_NO_GAME);
    if (!shooter || si < 0 || (double)si != slot) return FireRefuse(lua, 0, SV_ERR_BAD_ARGS, L"no shooter, or the slot isn't 0-5", shooter, si, target);
    if (!LiveObject(shooter) || CoKind(shooter) != 1 || shooter == CO.me.obj)
        return FireRefuse(lua, 2, SV_ERR_SHOOTER, L"the shooter isn't a live AI plane", shooter, si, target);
    const FlClassInfo* sc = FlClass(shooter);
    if (!sc->lgo || !sc->fcs) return FireRefuse(lua, 3, SV_ERR_SHOOTER, L"the shooter's class has no fire-control system where the game's fire reads it", shooter, si, target);
    if (target && (!LiveObject(target) || !FlClass(target)->lgo))
        return FireRefuse(lua, 4, SV_ERR_TARGET, L"the target isn't a live game object", shooter, si, target);
    FlRate* r = FireRate(shooter, now);
    if (r->n >= FIRE_PER_S) return FireRefuse(lua, 1, SV_ERR_RATE, L"more than the shots a second allowed for one shooter", shooter, si, target);
    ++r->n;
    double offset[3] = { 0.0, 0.0, 0.0 };
    uint8_t ok = FI.fn(shooter, (uint8_t)si, target, offset, 0);
    if (ok) ++FI.fired; else ++FI.refusedByGame;
    if (!r->said) {
        r->said = 1;
        Log(L"coop fire: AI plane %p, slot %d, at %p: %s", shooter, si, target,
            ok ? L"queued (the game's fire returned true)"
               : L"the game's fire returned false (inactive, dead or no live fire-control system)");
    }
    return Ret(lua, ok ? 1 : SV_ERR_FIRE_NO);
}

/* ---- SV_InputNow -------------------------------------------------------------------------------------------------
 * The flight input each player plane last sent to its flight engine (BuildFlightInput's out after SV_Invert and DOWN):
 * +0x0 pitch, +0x4 yaw, +0x8 roll (-1..1), +0xC throttle, +0x10 brake, +0x14 high-G (0..1). Throttle is the
 * accelerate input: 0 is neutral (cruise speed), 1 a held accelerate (the flight engine clamps it to 0..1 and
 * AceFlightEnginePlayerParameter has AfterburnerWait / PowerAfterBurnerR / MaxSpeedAfterBurnerR: the afterburner comes
 * from holding it; no threshold in the input path itself). */
/* flags: the input's flags byte (out +0x18), as BuildFlightInput (0x147d689b0) builds it: 0x10 State bit 9 (gear down),
 * 8 plane+0x13d1 == 1, 4 +0x1314, 2 +0x1313, the low bit 0x147d660f0's. A remote plane's engines take it as their
 * +0x34 (the input message +0x20), and RemoteUpdate's gear check reads its 0x10 against the State's bit 9 (T4a.5) */
typedef struct { uint8_t* plane; double at; float v[6]; uint8_t flags; } FlInput;
static FlInput g_flIn[4];

static void FlRecordInput(uint8_t* plane, const float* out)
{
    FlInput* slot = &g_flIn[0];
    for (int i = 0; i < 4; ++i) {
        if (g_flIn[i].plane == plane) { slot = &g_flIn[i]; break; }
        if (g_flIn[i].at < slot->at) slot = &g_flIn[i];
    }
    slot->plane = plane; slot->at = CoNow();
    for (int k = 0; k < 6; ++k) slot->v[k] = out[k];
    slot->flags = ((const uint8_t*)out)[0x18];
}

/* SV_InputNow() -> "pitch,yaw,roll,throttle,brake,highg" (each x1000, whole numbers) from the last BuildFlightInput of
 * the local player's plane (or, outside Survival's level, of the plane input was last built for), "" if none yet */
static int L_InputNow(void* lua)
{
    uint8_t* me = FlLocalCached();
    if (!me) me = CoRefGet(&CO.me);
    const FlInput* best = NULL;
    for (int i = 0; i < 4; ++i) {
        const FlInput* f = &g_flIn[i];
        if (!f->plane) continue;
        if (me ? f->plane == me : (!best || f->at > best->at)) best = f;
    }
    if (!best) { U.luaSetString(lua, "", 0); return 1; }
    char s[96];
    CoBuf b = { s, s + sizeof(s) - 1 };
    for (int k = 0; k < 6; ++k) {
        float v = best->v[k];
        if (!(v > -100.0f && v < 100.0f)) v = 0.0f;                        /* (NaN, junk) */
        if (k) CoPutS(&b, ",");
        CoPutI(&b, (int64_t)(v * 1000.0f + (v < 0 ? -0.5f : 0.5f)));
    }
    *b.p = 0;
    U.luaSetString(lua, s, (size_t)(b.p - s));
    return 1;
}

/* ---- SV_Down -----------------------------------------------------------------------------------------------------
 * While it's on, OnBuildInput hands the plane's pitch, yaw, roll, throttle and brake (and high-G 0) to DownStep: the
 * plane circles (cx, cy) at alt on its own while its pilot waits for a revive. Its pose is read natively every frame
 * (coop.c CoReadPose: the root component's world location and rotation; velocity and rates from their changes). */
static struct {
    int on, okBits, said;                                /* said: the in-flight check's confirmations logged (bits) */
    CoRef ref;
    DownCtl c;
    double lastLog, startAt;
} DN;
static int g_dnKnown, g_dnSRoll = 1, g_dnSPitch = 1;     /* the input signs learned (kept for the next DOWN) */
static const wchar_t* const kDnPhase[] = { L"starting", L"settling", L"roll probe", L"levelling", L"pitch probe", L"circling" };

static void DownLog(const wchar_t* why)
{
    const DownCtl* c = &DN.c;
    int32_t ph = c->phase >= 0 && c->phase <= DN_CIRCLE ? c->phase : 0;
    Log(L"down: %s (%s, %d s): %d m from the centre (radius %d), %d m high (want %d), heading error %d deg, bank %d "
        L"(want %d), climb %d deg; inputs pitch %d, roll %d (x1000); input signs roll %d, pitch %d (rates along the "
        L"inputs roll %d, pitch %d deg/s; %d flips)", why, kDnPhase[ph],
        (int32_t)(CoNow() - DN.startAt), (int32_t)c->dist, (int32_t)c->radius, (int32_t)(c->p[2] / 100.0), (int32_t)c->alt,
        (int32_t)c->headErr, (int32_t)c->r[2], (int32_t)c->bankWant, (int32_t)c->gamma, (int32_t)(c->oP * 1000.0),
        (int32_t)(c->oR * 1000.0), c->sRoll, c->sPitch, (int32_t)c->resp[0], (int32_t)c->resp[1], c->flips);
}

static void DownApply(uint8_t* plane, float* out)
{
    double p[3], r[3];
    if (!CoReadPose(plane, p, r)) return;                  /* (no pose: the player's own input this frame) */
    float o[5];
    double now = CoNow();
    DownStep(&DN.c, now, p, r, o);
    out[0] = o[0]; out[1] = o[1]; out[2] = o[2]; out[3] = o[3]; out[4] = o[4]; out[5] = 0.0f;
    int l = DN.c.learned;
    if (l) {
        DN.c.learned = 0;
        if (l & (DN_LEARNED_ROLL | DN_VAGUE_ROLL))
            Log(L"down: roll probe: body roll rate %d deg/s at input +0.3, %d at -0.3: %s %d", (int32_t)DN.c.probeRate[0],
                (int32_t)DN.c.probeRate[1], (l & DN_LEARNED_ROLL) ? L"roll input sign" : L"inconclusive, roll input sign kept",
                DN.c.sRoll);
        if (l & (DN_LEARNED_PITCH | DN_VAGUE_PITCH))
            Log(L"down: pitch probe: body pitch rate %d deg/s at input +0.3, %d at -0.3: %s %d", (int32_t)DN.c.probeRate[2],
                (int32_t)DN.c.probeRate[3], (l & DN_LEARNED_PITCH) ? L"pitch input sign" : L"inconclusive, pitch input sign kept",
                DN.c.sPitch);
        /* the in-flight check (DnCheck): a sign flipped, each time; a sign confirmed, once a DOWN */
        if (l & DN_FLIPPED_ROLL)
            Log(L"down: roll input sign flipped to %d: the plane rolled against the inputs (%d deg/s along them); %d flips",
                DN.c.sRoll, (int32_t)DN.c.resp[0], DN.c.flips);
        if (l & DN_FLIPPED_DIVE)
            Log(L"down: pitch input sign flipped to %d: a dive steeper than 40 deg for 10 s didn't pull out; %d flips",
                DN.c.sPitch, DN.c.flips);
        else if (l & DN_FLIPPED_PITCH)
            Log(L"down: pitch input sign flipped to %d: the plane pitched against the inputs (%d deg/s along them); %d flips",
                DN.c.sPitch, (int32_t)DN.c.resp[1], DN.c.flips);
        if ((l & DN_CONFIRMED_ROLL) && !(DN.said & 1)) {
            DN.said |= 1;
            Log(L"down: roll input sign %d confirmed in flight (%d deg/s along the inputs)", DN.c.sRoll, (int32_t)DN.c.resp[0]);
        }
        if ((l & DN_CONFIRMED_PITCH) && !(DN.said & 2)) {
            DN.said |= 2;
            Log(L"down: pitch input sign %d confirmed in flight (%d deg/s along the inputs)", DN.c.sPitch, (int32_t)DN.c.resp[1]);
        }
        DN.okBits |= ((l & (DN_LEARNED_ROLL | DN_FLIPPED_ROLL | DN_CONFIRMED_ROLL)) ? DN_LEARNED_ROLL : 0) |
                     ((l & (DN_LEARNED_PITCH | DN_FLIPPED_PITCH | DN_CONFIRMED_PITCH)) ? DN_LEARNED_PITCH : 0);
        if (DN.okBits == (DN_LEARNED_ROLL | DN_LEARNED_PITCH) &&
            (!g_dnKnown || g_dnSRoll != DN.c.sRoll || g_dnSPitch != DN.c.sPitch)) {
            g_dnKnown = 1; g_dnSRoll = DN.c.sRoll; g_dnSPitch = DN.c.sPitch;
            Log(L"down: input signs kept for the next DOWN (roll %d, pitch %d): it circles at once", g_dnSRoll, g_dnSPitch);
        }
    }
    if (now - DN.lastLog >= 10.0) { DN.lastLog = now; DownLog(L"autopilot"); }
}

static void DownStop(const wchar_t* why)
{
    if (!DN.on) return;
    DownLog(why);
    DN.on = 0;
    memset(&DN.ref, 0, sizeof(DN.ref));
}

static void FdLog(void);                                /* COOP2MP's fed plane (below) */
static void FlNetLog(void);                             /* and the other players' real planes (T3) */

/* From OnBuildInput (survival_rt.c), after the game's BuildFlightInput and SV_Invert: DOWN, then the input record. */
static void FlightInputHook(uint8_t* plane, float* out)
{
    if (!plane || !out) return;
    if (DN.on) {
        uint8_t* o = CoRefGet(&DN.ref);
        if (!o) DownStop(L"autopilot off: the plane is gone");
        else if (o == plane) DownApply(o, out);
    }
    FlRecordInput(plane, out);
    FdLog();
    FlNetLog();
}

/* SV_Down(plane, cx_cm, cy_cm, alt_m, radius_m) -> 1 (on, or its circle changed when it's on for that plane already: the
 * autopilot keeps its state), SV_ERR_BAD_ARGS, SV_ERR_NO_GAME (BuildFlightInput not hooked), SV_ERR_NOT_READY (not in
 * Survival's level), SV_ERR_NOT_LOCAL. SV_Down(0) -> 1: off, the player flies again. */
static int L_Down(void* lua)
{
    uint8_t* plane = ArgObject(lua);
    if (!plane) { DownStop(L"autopilot off (Lua)"); return Ret(lua, 1); }
    double cx = 0, cy = 0, alt = 0, rad = 0;
    if (!ArgNumber(lua, &cx) || !ArgNumber(lua, &cy) || !ArgNumber(lua, &alt) || !ArgNumber(lua, &rad)) return Ret(lua, SV_ERR_BAD_ARGS);
    if (!(cx > -1e9 && cx < 1e9 && cy > -1e9 && cy < 1e9 && alt >= 50 && alt <= 15000 && rad >= 200 && rad <= 30000)) {
        Log(L"down: refused: centre (%d, %d) m, altitude %d m, radius %d m (altitude 50-15000, radius 200-30000)",
            (int32_t)(cx / 100), (int32_t)(cy / 100), (int32_t)alt, (int32_t)rad);
        return Ret(lua, SV_ERR_BAD_ARGS);
    }
    if (!g_nextBuildInput) return Ret(lua, SV_ERR_NO_GAME);
    if (!LiveObject(plane) || CoKind(plane) != 2) { Log(L"down: refused: %p isn't a player plane", plane); return Ret(lua, SV_ERR_BAD_ARGS); }
    if (DN.on && CoRefGet(&DN.ref) == plane) {                 /* on already: a new circle, the same flight */
        DN.c.cx = cx; DN.c.cy = cy; DN.c.alt = alt; DN.c.radius = rad;
        return Ret(lua, 1);
    }
    int64_t err = 0;
    uint8_t* me = FlLocal(&err);
    if (!me) return Ret(lua, err);
    if (me != plane) { Log(L"down: refused: %p isn't the local player's plane (%p)", plane, me); return Ret(lua, SV_ERR_NOT_LOCAL); }
    DownInit(&DN.c, cx, cy, alt, rad, g_dnKnown, g_dnSRoll, g_dnSPitch);
    CoRefSet(&DN.ref, plane);
    DN.on = 1; DN.okBits = g_dnKnown ? (DN_LEARNED_ROLL | DN_LEARNED_PITCH) : 0; DN.said = 0;
    DN.startAt = DN.lastLog = CoNow();
    double p[3] = { 0, 0, 0 }, r[3] = { 0, 0, 0 };
    CoReadPose(plane, p, r);
    Log(L"down: autopilot on plane %p: circling (%d, %d) m at %d m, radius %d m; the plane at (%d, %d) m, %d m high, heading %d, "
        L"bank %d; %s", plane, (int32_t)(cx / 100), (int32_t)(cy / 100), (int32_t)alt, (int32_t)rad, (int32_t)(p[0] / 100),
        (int32_t)(p[1] / 100), (int32_t)(p[2] / 100), (int32_t)r[1], (int32_t)r[2],
        g_dnKnown ? L"input signs known (checked again in flight)" : L"learning the input signs first (about 5 s of small roll and pitch inputs)");
    return Ret(lua, 1);
}

/* ---- SV_Respawn --------------------------------------------------------------------------------------------------
 * The player plane's own respawn, vtable +0xbf8 (sigs.h kSigPPRespawn; Online Mode's, from 0x147d29220 with a respawn
 * point's spot): (plane, &location, &rotation, skipMove false). It moves the plane (slot 186, as LiveActorTeleport), sets
 * it active, fires OnRestored, gives its movement input back and posts RespawnedPlayer. Health is the caller's (Lua's)
 * business: the respawn doesn't touch it. */
typedef void (*RespawnFn)(void* plane, const double* location, const double* rotation, uint8_t skipMove);
#define PP_RESPAWN_SLOT (0xbf8 / 8)

static int RespawnShape(void)
{
    static int ok = -1;
    if (ok >= 0) return ok;
    uint8_t* f = g_fPPRespawn;
    ok = f && !memcmp(f + 0x133, "\xC6\x87\xFD\x0D\x00\x00\x00", 7) &&      /* mov byte [rdi + 0xdfd], 0 */
         !memcmp(f + 0x13a, "\x45\x84\xF6\x75", 4) &&                       /* test r14b, r14b; jne (skipMove) */
         !memcmp(f + 0x157, "\xFF\x90\xD0\x05\x00\x00", 6);                 /* call [rax + 0x5d0]: TeleportTo */
    Log(ok ? L"respawn: the player plane's respawn %p (vtable +bf8)" : L"respawn: the player plane's respawn wasn't found (%p); SV_Respawn is off", f);
    return ok;
}

/* SV_Respawn(plane, x, y, z, pitch, yaw, roll) -> 1, or SV_ERR_BAD_ARGS (a pose not finite or outside the map: |x|, |y|
 * under 1,000 km, z -500 m to 30 km, pitch -90..90, yaw and roll -360..360), SV_ERR_NO_GAME, SV_ERR_NOT_READY,
 * SV_ERR_NOT_LOCAL. Position in cm, rotation in degrees (UE's FRotator). Turns DOWN off for that plane. */
static int L_Respawn(void* lua)
{
    uint8_t* plane = ArgObject(lua);
    double v[6];
    for (int i = 0; i < 6; ++i) if (!ArgNumber(lua, &v[i])) return Ret(lua, SV_ERR_BAD_ARGS);
    if (!plane) return Ret(lua, SV_ERR_BAD_ARGS);
    if (!(v[0] > -1e8 && v[0] < 1e8 && v[1] > -1e8 && v[1] < 1e8 && v[2] > -50000 && v[2] < 3e6 &&
          v[3] >= -90 && v[3] <= 90 && v[4] >= -360 && v[4] <= 360 && v[5] >= -360 && v[5] <= 360)) {
        Log(L"respawn: refused: pose (%d, %d, %d) m, pitch %d yaw %d roll %d isn't inside the map", (int32_t)(v[0] / 100),
            (int32_t)(v[1] / 100), (int32_t)(v[2] / 100), (int32_t)v[3], (int32_t)v[4], (int32_t)v[5]);
        return Ret(lua, SV_ERR_BAD_ARGS);
    }
    if (!RespawnShape()) return Ret(lua, SV_ERR_NO_GAME);
    if (!LiveObject(plane) || CoKind(plane) != 2) { Log(L"respawn: refused: %p isn't a player plane", plane); return Ret(lua, SV_ERR_BAD_ARGS); }
    int64_t err = 0;
    uint8_t* me = FlLocal(&err);
    if (!me) return Ret(lua, err);
    if (me != plane) { Log(L"respawn: refused: %p isn't the local player's plane (%p)", plane, me); return Ret(lua, SV_ERR_NOT_LOCAL); }
    void** vt = *(void***)plane;
    if (!Readable(vt + PP_RESPAWN_SLOT, 8) || vt[PP_RESPAWN_SLOT] != (void*)g_fPPRespawn) {
        Log(L"respawn: refused: plane %p's vtable +bf8 is %p, not the respawn %p", plane,
            Readable(vt + PP_RESPAWN_SLOT, 8) ? vt[PP_RESPAWN_SLOT] : NULL, g_fPPRespawn);
        return Ret(lua, SV_ERR_NO_GAME);
    }
    if (DN.on && DN.ref.obj == plane) DownStop(L"autopilot off (respawn)");
    double was[3] = { 0, 0, 0 }, wr[3] = { 0, 0, 0 }, now[3] = { 0, 0, 0 }, nr[3] = { 0, 0, 0 };
    CoReadPose(plane, was, wr);
    double loc[3] = { v[0], v[1], v[2] }, rot[3] = { v[3], v[4], v[5] };
    ((RespawnFn)g_fPPRespawn)(plane, loc, rot, 0);
    CoReadPose(plane, now, nr);
    double dx = now[0] - loc[0], dy = now[1] - loc[1], dz = now[2] - loc[2];
    int fi = FireResolve() && Readable(plane + FI.dead, 1) && Readable(plane + FI.active, 1);
    int32_t maxHp = g_offMaxHealth >= 0 && Readable(plane + g_offMaxHealth, 4) ? (int32_t)(*(float*)(plane + g_offMaxHealth) * 10.0f) : -1;
    Log(L"respawn: plane %p respawned at (%d, %d) m, %d m high, pitch %d yaw %d roll %d (it was at (%d, %d) m, %d m high); "
        L"now %d m off that spot, heading %d; health %d of %d (x10), dead flag %d, active %d", plane, (int32_t)(v[0] / 100),
        (int32_t)(v[1] / 100), (int32_t)(v[2] / 100), (int32_t)v[3], (int32_t)v[4], (int32_t)v[5], (int32_t)(was[0] / 100),
        (int32_t)(was[1] / 100), (int32_t)(was[2] / 100), (int32_t)(CoSqrt(dx * dx + dy * dy + dz * dz) / 100), (int32_t)nr[1],
        CoHealth(plane), maxHp, fi ? (int32_t)plane[FI.dead] : -1, fi ? (int32_t)plane[FI.active] : -1);
    return Ret(lua, 1);
}

/* ---- COOP2MP: a remote player plane fed (runtime 0.29.1; tools/re/COOP2MP.md T1c) ------------------------------------
 * A role-2 (another player's) player plane flies itself: its FrameUpdate calls RemoteUpdate(plane, dt) (hooked here,
 * sigs.h kSigRemoteUpdate), which sets the plane's second flight state from its network object's (plane +
 * NetworkObject) FLiveMessageFlightEnginePhysics (*(N+0x98)) and its input from *(N+0x170), blends the plane's own flight
 * state toward it (a snap when over 1 km off) and runs its own engine and controls. With nothing received all of it is
 * zero, so its tick pulled it to the map's centre (COOP.md 6), and T1 kept its tick off: no animations, afterburner,
 * HUD box or enemy attacks. Here, just before RemoteUpdate runs for the fed plane, its message gets a pose and its
 * input: Direction (+0x20, 3 floats, a unit vector), Location (+0x2c, 3 int32, cm), Rotation (+0x38, 3 floats, deg:
 * pitch, yaw, roll), State (+0x44, int32: the source's plane+0x2b18 less bit 20), SpeedLocal (+0x48, float m/s);
 * the input message's +0x08..+0x1c: pitch, yaw, roll, throttle, brake, high-G (the source's last BuildFlightInput),
 * +0x20 the attribute byte (4; bit 0 zeroes the input). TriggerTimeMs (+0x08) and the queues (+0x58, +0x68, +0x78
 * counts) are left alone. T1c's source: your own plane, with a formation offset (forward, right, up).
 * N+0x170 is a TSharedPtr (the message's address, then its reference controller at +0x178), as RemoteUpdate reads it
 * (0x147d6f1d1 `mov rdx, [rdi+0x170]`, then [rdx+0x8]..). Until runtime 0.29.3 the input went to N+0x178.. itself: over
 * that controller, which the network object's destructor (0x146f0d3b0) releases, so Quit Mission crashed the game
 * (EXCEPTION_ACCESS_VIOLATION writing 0xbf800008: a pitch of -1.0 as a pointer; the user's test of 2026-10-30). */
typedef uint64_t (*RemoteUpdateFn)(uint8_t* plane, float dt);
static uint8_t*       g_fRemoteUpdate;                  /* found by FindFunctions (sigs.h kSigRemoteUpdate) */
static RemoteUpdateFn g_nextRemoteUpdate;
#define FD_R        0x98       /* N's FLiveMessageFlightEnginePhysics pointer */
#define FD_IN       0x170      /* N's FLiveMessageFlightEngineInput (a TSharedPtr: the message's address) */
#define FD_SPEED    0x2318     /* the plane's flight state (+0x2268) speed, m/s (float) */
#define FD_STATE    0x2b18     /* its State (int32) */
/* State bits not sent to a remote plane: bit 20 (the research's, its meaning unknown). Bit 9 is gear down: RemoteUpdate
 * (0x147d6f989) puts the plane's gear down or up from it every frame; until runtime 0.31.2 it was cleared too, so the
 * copy's gear never came down (T4a.2's test, 2026-10-30: your State 0x40A00 / 0x40200 with the gear down). */
#define FD_STATE_LOCAL (1u << 20)
static struct {
    int on, said;
    int32_t noOff;
    CoRef plane, src;
    double off[3];                                      /* cm: forward, right, up */
    uint32_t calls, fed, skipped, abWrites;
    double lastLog, lastCallAt, srcPos[3], srcAt, spd, tgt[3];
    float abSrc, abFound;                               /* this second's most: the source's afterburner, what was left on it */
    uint32_t stateOr;                                   /* this second's source State bits (before the mask) */
    uint32_t hits, hitsSaid;                            /* calls of the player plane's damage on it (T1e) */
    double hitDmg, hitApplied;                          /* this second's damage asked, and taken off its health */
} FD;
static void* g_fdNetCls;
#define FD_AB       0x39d0     /* a player plane's afterburner amount (float, 0..1): OnSurfacePP below */

static uint8_t* FdMessage(uint8_t* plane, uint8_t** in)  /* the plane's physics message, its input in *in; NULL: none */
{
    if (!FD.noOff) {                                     /* (every player plane's: LiveGameObject.NetworkObject) */
        uint8_t* no = (uint8_t*)U.valuePtr(plane, L"NetworkObject");
        FD.noOff = no ? (int32_t)(no - plane) : -1;
        if (!g_fdNetCls) g_fdNetCls = U.findObject(L"Class", L"LiveNetworkPlayerPlane", 0, 0);
    }
    if (FD.noOff <= 0 || !Readable(plane + FD.noOff, 8)) return NULL;
    uint8_t* n = *(uint8_t**)(plane + FD.noOff);
    if (!n || !LiveObject(n) || (g_fdNetCls && *(void**)(n + 0x10) != g_fdNetCls) || !Readable(n + FD_IN, 8) ||
        !Readable(n + FD_R, 8)) return NULL;
    uint8_t* r = *(uint8_t**)(n + FD_R), *i = *(uint8_t**)(n + FD_IN);
    if (!r || !Readable(r, 0x80) || !i || !Readable(i, 0x28)) return NULL;
    *in = i;
    return r;
}

static void FdFeed(uint8_t* plane)
{
    uint8_t* src = CoRefGet(&FD.src), *in = NULL;
    uint8_t* r = FdMessage(plane, &in);
    double p[3], rot[3], now = CoNow();
    if (!src || !r || !CoReadPose(src, p, rot)) { ++FD.skipped; return; }
    /* speed: the source's own (m/s), else from its moves; direction: along its moves, else its nose */
    double dt = now - FD.srcAt, d[3] = { 0, 0, 0 }, dl = 0;
    if (FD.srcAt > 0 && dt > 0.004 && dt < 0.5) {
        for (int k = 0; k < 3; ++k) d[k] = p[k] - FD.srcPos[k];
        dl = CoSqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
        double v = dl / dt / 100.0;
        FD.spd = FD.spd > 0 ? FD.spd + (v - FD.spd) * 0.2 : v;
    }
    if (FD.srcAt <= 0 || dt > 0.004) { memcpy(FD.srcPos, p, sizeof(p)); FD.srcAt = now; }
    float own = Readable(src + FD_SPEED, 4) ? *(float*)(src + FD_SPEED) : -1.0f;
    float speed = (own > 1.0f && own < 2000.0f) ? own : (float)FD.spd;
    double cp = Cos(rot[0] * CO_PI / 180.0), sp = Sin(rot[0] * CO_PI / 180.0);
    double cy = Cos(rot[1] * CO_PI / 180.0), sy = Sin(rot[1] * CO_PI / 180.0);
    float dir[3];
    if (dl > 1.0) { dir[0] = (float)(d[0] / dl); dir[1] = (float)(d[1] / dl); dir[2] = (float)(d[2] / dl); }
    else { dir[0] = (float)(cp * cy); dir[1] = (float)(cp * sy); dir[2] = (float)sp; }
    p[0] += FD.off[0] * cy - FD.off[1] * sy;
    p[1] += FD.off[0] * sy + FD.off[1] * cy;
    p[2] += FD.off[2];
    memcpy(FD.tgt, p, sizeof(p));
    int32_t loc[3];
    for (int k = 0; k < 3; ++k) loc[k] = (int32_t)(p[k] + (p[k] < 0 ? -0.5 : 0.5));
    float frot[3] = { (float)rot[0], (float)rot[1], (float)rot[2] };
    int32_t state = Readable(src + FD_STATE, 4) ? *(int32_t*)(src + FD_STATE) : 0;
    FD.stateOr |= (uint32_t)state;
    state &= ~FD_STATE_LOCAL;
    memcpy(r + 0x20, dir, 12); memcpy(r + 0x2c, loc, 12); memcpy(r + 0x38, frot, 12);
    memcpy(r + 0x44, &state, 4); memcpy(r + 0x48, &speed, 4);
    const FlInput* rec = NULL;                          /* the source's last BuildFlightInput (FlRecordInput) */
    for (int i = 0; i < 4; ++i) if (g_flIn[i].plane == src) rec = &g_flIn[i];
    if (rec) { memcpy(in + 0x08, rec->v, sizeof(rec->v)); in[0x20] = rec->flags; }
    ++FD.fed;
    if (!FD.said) {
        FD.said = 1;
        Log(L"coop2mp: fed plane %p first: message %p, input %p (%s); speed %d m/s (the source's field %d), state %x, queues %d %d %d",
            plane, r, in, rec ? L"the source's" : L"NO INPUT RECORD", (int32_t)speed, (int32_t)own, (uint32_t)state,
            *(int32_t*)(r + 0x58), *(int32_t*)(r + 0x68), *(int32_t*)(r + 0x78));
    }
}

/* ---- COOP2MP T3: the other players' real planes (runtime 0.30.0; tools/re/COOP2MP.md T3) ---------------------------
 * A player slot's bound puppet (SV_CoopPeer) that is a player plane (sv_coop.lua spawns one of their airframe with
 * SV_CoopSpawnPP's slot) isn't teleported (coop.c CoDrive asks FlFeeds): its own update flies it, as T1e's copy, fed
 * just before its RemoteUpdate from their stream: the pose where CoDrive would have put it (their snapshots a delay ago,
 * CoSample), the direction and speed of its last 0.1 s, and their flight block (coop.c CO_FL: stick, afterburner amount,
 * speed, State) as their game sent it. Each game sends its own plane's block with its state (FlFlightBlock). */
static int FlFeeds(uint8_t* plane) { return plane && g_nextRemoteUpdate && CoKind(plane) == 2; }

static void FlFlightBlock(uint8_t* plane, uint8_t* out)
{
    memset(out, 0, CO_FL);
    if (!plane) return;
    const FlInput* rec = NULL;                           /* its last BuildFlightInput (FlRecordInput) */
    for (int i = 0; i < 4; ++i) if (g_flIn[i].plane == plane) rec = &g_flIn[i];
    if (rec) for (int i = 0; i < 6; ++i) {
        float v = rec->v[i];
        v = (v == v) ? (v < -1.0f ? -1.0f : v > 1.0f ? 1.0f : v) : 0.0f;
        out[i] = (uint8_t)(int8_t)(v * 127.0f + (v < 0 ? -0.5f : 0.5f));
    }
    float ab = Readable(plane + FD_AB, 4) ? *(float*)(plane + FD_AB) : 0.0f;
    ab = (ab == ab) ? (ab < 0.0f ? 0.0f : ab > 1.0f ? 1.0f : ab) : 0.0f;
    out[6] = (uint8_t)(ab * 255.0f + 0.5f);
    float sp = Readable(plane + FD_SPEED, 4) ? *(float*)(plane + FD_SPEED) : 0.0f;
    sp = (sp == sp) ? (sp < 0.0f ? 0.0f : sp > 6500.0f ? 6500.0f : sp) : 0.0f;
    uint16_t spd = (uint16_t)(sp * 10.0f + 0.5f);
    memcpy(out + 7, &spd, 2);
    uint32_t st = Readable(plane + FD_STATE, 4) ? *(uint32_t*)(plane + FD_STATE) : 0;
    memcpy(out + 9, &st, 4);
}

static int FlNetSlot(uint8_t* plane)                     /* the player slot whose bound puppet this is, else -1 */
{
    if (!CO.open || !plane) return -1;
    for (int s = 0; s < CO_MAX_PLAYERS; ++s) if (s != CO.mySlot && CO.players[s].plane.ref.obj == plane) return s;
    return -1;
}

static uint32_t g_netHits[CO_MAX_PLAYERS];               /* hits on a real plane here (refused: their game takes its own) */
static void FlNetFeed(int s, uint8_t* plane)
{
    CoPlayer* P = &CO.players[s];
    uint8_t* in = NULL;
    uint8_t* r = CoRefGet(&P->plane.ref) ? FdMessage(plane, &in) : NULL;
    double pos[3], p0[3], rot[3], at[3], atRot[3];
    float q[4], q0[4];
    if (!r || !P->haveOffset) { ++P->fedSkip; return; }
    double rt = CoNow() - P->offset - CoRenderDelay(P);
    if (!CoSample(&P->plane, rt, pos, q)) { ++P->fedSkip; return; }
    CoQuatToRot(q, rot);
    double d[3] = { 0, 0, 0 }, dl = 0;
    if (CoSample(&P->plane, rt - 0.1, p0, q0)) {
        for (int k = 0; k < 3; ++k) d[k] = pos[k] - p0[k];
        dl = CoSqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
    }
    uint16_t spd = 0;
    if (P->hasFl) memcpy(&spd, P->fl + 7, 2);
    float speed = spd >= 10 ? spd / 10.0f : (float)(dl / 0.1 / 100.0);
    float dir[3];
    if (dl > 1.0) { dir[0] = (float)(d[0] / dl); dir[1] = (float)(d[1] / dl); dir[2] = (float)(d[2] / dl); }
    else {
        double cp = Cos(rot[0] * CO_PI / 180.0), sp = Sin(rot[0] * CO_PI / 180.0);
        double cy = Cos(rot[1] * CO_PI / 180.0), sy = Sin(rot[1] * CO_PI / 180.0);
        dir[0] = (float)(cp * cy); dir[1] = (float)(cp * sy); dir[2] = (float)sp;
    }
    int32_t loc[3];
    for (int k = 0; k < 3; ++k) loc[k] = (int32_t)(pos[k] + (pos[k] < 0 ? -0.5 : 0.5));
    float frot[3] = { (float)rot[0], (float)rot[1], (float)rot[2] };
    int32_t state = 0;
    if (P->hasFl) memcpy(&state, P->fl + 9, 4);
    state &= ~FD_STATE_LOCAL;
    memcpy(r + 0x20, dir, 12); memcpy(r + 0x2c, loc, 12); memcpy(r + 0x38, frot, 12);
    memcpy(r + 0x44, &state, 4); memcpy(r + 0x48, &speed, 4);
    if (P->hasFl) {
        float v[6];
        for (int i = 0; i < 6; ++i) v[i] = (int8_t)P->fl[i] / 127.0f;
        memcpy(in + 0x08, v, sizeof(v)); in[0x20] = (uint8_t)(4 | (((uint32_t)state >> 9) & 1) << 4);   /* (gear: FlInput) */
    }
    if (CoReadPose(plane, at, atRot)) {                  /* (where it is against where it was sent: the minute's most) */
        double ex = at[0] - pos[0], ey = at[1] - pos[1], ez = at[2] - pos[2], off = CoSqrt(ex * ex + ey * ey + ez * ez);
        if (off > P->fedOffCm) P->fedOffCm = off;
    }
    if (!P->fed) Log(L"coop2mp: player %d's real plane %p fed from their stream: speed %d m/s, flight block %s, State %x", s + 1,
        plane, (int32_t)speed, P->hasFl ? L"yes" : L"NOT YET (their game sends none: an older build?)", (uint32_t)state);
    ++P->fed;
}

/* once a minute (from FlightInputHook): each real plane fed here */
static double g_netLogAt;
static void FlNetLog(void)
{
    double now = CoNow();
    if (!CO.open || now - g_netLogAt < 60.0) return;
    g_netLogAt = now;
    for (int s = 0; s < CO_MAX_PLAYERS; ++s) {
        CoPlayer* P = &CO.players[s];
        if (s == CO.mySlot || !(P->fed || P->fedSkip)) continue;
        Log(L"coop2mp: player %d's real plane: %u frames fed, %u not (no stream yet / no message) this minute; at most %d m off "
            L"where it was sent; %u hits on it here (refused: their own game takes its hits)", s + 1, P->fed, P->fedSkip,
            P->fedOffCm >= 0 ? (int32_t)(P->fedOffCm / 100.0) : -1, g_netHits[s]);
        P->fed = P->fedSkip = 0; P->fedOffCm = -1; g_netHits[s] = 0;
    }
}

/* ---- COOP2MP T4: your weapons on your real plane elsewhere, Online Mode's way (runtime 0.31.0; COOP2MP.md T4) -------
 * Online Mode shows another player's shot by launching the same weapon from their plane's own weapon system: the remote
 * plane fire 0x147d71ea0(plane, &{ExplosiveWeaponFire*, ctrl}) takes each WeaponData (0x50 bytes, at message+0x20) and
 * LaunchWeapon(weapons+0x2e0, weapon number, target, ...) with its random seed, then sets the missile off from the
 * shooter's start (its vf+0x8a0: location, rotation, velocity, target location, latency). A role-2 plane's weapons do no
 * damage anywhere (CanBeDamagedBy, hard rule 53's research): what shows is all it does; each shooter's own game counts
 * their hits. The message's time is the send time; one in the future gives no latency (a 0 would be 3 s late). Its
 * target comes from the online network-id map (empty offline), so for our replays LaunchWeapon gets the target itself
 * (OnLaunchWeapon). The network manager it reads unchecked is checked here first.
 * T4a (solo, the Ctrl+F11 copy of your own plane's class): each of your launches (PlaneWeaponsFired, called by the
 * weapon system after each one) is read as the online sender reads it (missile +0x3a8 weapon number, +0x6d0 spawn slot,
 * +0x6d4, +0x6b4 seed, +0x3c8 lock-ons, +0x3f0 target; root +0x220 location, GetVelocity vf+0x358) and replayed from
 * the copy the next frame (its offset from you added); your flares (FireFlares) too, and your gun's trigger (weapons
 * +0x30e, yours; +0x311 the remote trigger the gun message sets) mirrored. Another airframe's weapon numbers aren't
 * yours: nothing replayed on it (T4b: each player's own loadout on their real plane). */
typedef struct {
    void* vt; uint64_t netId;
    uint8_t tgtType, pad0[3]; uint32_t tgtId; int32_t tgtLoc[3];
    uint8_t weapon, slot, unk26, seed, lockon, pad1[3];
    int32_t initLoc[3]; float initRot[3], initVel[3];
} FwData;
_Static_assert(sizeof(FwData) == 0x50, "WeaponData is 0x50 bytes");
typedef struct {
    void* vt; uint64_t triggerTime; uint8_t typeId, pad0[3]; uint32_t netId; uint64_t pad1;
    FwData* wd; int32_t wdNum, wdMax; void* em; int32_t emNum, emMax;
} FwMsg;
_Static_assert(__builtin_offsetof(FwMsg, wd) == 0x20 && __builtin_offsetof(FwMsg, em) == 0x30, "ExplosiveWeaponFire's arrays");
typedef void     (*PlaneFiredFn)(uint8_t* plane, CoArr* projs);
typedef uint64_t (*RemoteFireFn)(uint8_t* plane, void** msgPair);
typedef uint64_t (*LaunchFn)(void* ws, uint64_t weapon, void* target, void** outProj, void* slot, uint64_t a6, uint64_t a7,
                             uint64_t lockon, void* arrA, void* arrB);
typedef uint64_t (*FireFlaresFn)(uint8_t* w);
typedef uint8_t* (*NetMgrFn)(void* world);
typedef double*  (*GetVelFn)(void* self, double* out);
typedef uint8_t* (*StaticClassFn)(void);
static uint8_t*     g_fPlaneFired, *g_fRemoteFire, *g_fLaunchWeapon, *g_fFireFlares, *g_fNetManager;
static uint8_t*     g_fSelectSpecial, *g_fArmSpecial, *g_fGearSite;  /* (a special weapon's select / arm; the gear's site) */
typedef void (*SelectSpecialFn)(uint8_t* plane, uint64_t weapon);
typedef void (*ArmSpecialFn)(uint8_t* plane, uint64_t arm);
typedef void (*GearDownFn)(uint8_t* plane, uint64_t forceCancel, uint64_t landing, uint64_t a4);
typedef void (*GearUpFn)(uint8_t* plane, uint64_t carrier);
/* the kinds PlaneWeaponsFired tells apart (each its own message online): the call to each class's StaticClass in it */
#define FW_EXPLOSIVE   0x34    /* LiveExplosiveWeapon: ExplosiveWeaponFire */
#define FW_INSTANT     0x70    /* LiveAttachedInstantWeapon (the laser): InstantWeaponFire */
#define FW_BULLET      0x146   /* LiveBullet: BulletWeaponFire */
#define FW_ELECTRONIC  0x1b0   /* LiveElectronicWeaponBase (ESM / ECM): ElectronicMeasureFire */
static const wchar_t* const kFwKind[] = { L"?", L"laser", L"bullet special", L"electronic (ESM / ECM)" };
#define FS_Q        8
static struct { uint8_t kind, weapon; } g_fsQ[FS_Q];
static int g_fsN;
static PlaneFiredFn g_nextPlaneFired;
static LaunchFn     g_nextLaunchWeapon;
static FireFlaresFn g_nextFireFlares;
#define FW_W        0x16a8     /* a player plane's weapon system */
#define FW_Q        16
static struct { FwData d; CoRef target; } g_fwQ[FW_Q];
static int g_fwN, g_fwFlares;
static struct {
    uint32_t seen, explosive, queued, dropped, launched, failed, flares, flaresOk, gunYours30e, gunYours311, gunSet;
    uint32_t special, unknown, specialDone; int saidSpecial;
    uint64_t nextId; int said, saidNoNm, saidOther, saidW;
    uint8_t* inTarget; int in; uint64_t ret; uint8_t* proj;      /* (one replay: LaunchWeapon's target, what it gave) */
} FW;

/* T4a.3: a laser on the copy. Online Mode's InstantWeaponFire handler only selects and arms it (0x147d62ab0 arms: the
 * armed cue and the HUD, no shot), and T4a.2's test showed no beam; your own laser is spawned by LaunchWeapon as your
 * missiles are. The remote fire can't take it (after LaunchWeapon it writes an explosive weapon's +0x6b4 / +0x6e8 and
 * calls its vf+0x8a0 on whatever was launched), so its own steps are done here without those: 0x147f63c00(weapons,
 * 0.0, 1), the slot 0x147f7c300(launcher, weapon, spawn slot), the seed, LaunchWeapon, and the two lists it fills
 * freed (GMalloc, as the remote fire frees them). The calls' addresses are read from the remote fire's own code. */
typedef void    (*WsPrepFn)(uint8_t* w, float a, uint64_t b);
typedef int32_t (*WsSlotFn)(void* ws, uint64_t weapon, uint64_t spawnSlot);
typedef struct { void* p; int32_t n, m; } FwArr;
static int FwLaunchDirect(uint8_t* copy, uint8_t weapon, uint8_t* target, uint8_t** outProj)
{
    uint8_t* f = g_fRemoteFire, *c1 = f ? f + 0x4f4 : NULL, *c2 = f ? f + 0x50b : NULL, *gm = f ? f + 0x77d : NULL;
    if (!f || !g_nextLaunchWeapon || c1[0] != 0xE8 || c2[0] != 0xE8 || gm[0] != 0x48 || gm[1] != 0x8B || gm[2] != 0x0D) return -2;
    WsPrepFn prep = (WsPrepFn)(c1 + 5 + *(int32_t*)(c1 + 1));
    WsSlotFn slotFn = (WsSlotFn)(c2 + 5 + *(int32_t*)(c2 + 1));
    void** gmalloc = (void**)(gm + 7 + *(int32_t*)(gm + 3));
    if (!InGame(prep) || !InGame(slotFn) || !Readable(gmalloc, 8)) return -2;
    uint8_t* w = *(uint8_t**)(copy + FW_W);
    void* ws = (w && Readable(w + 0x2e0, 8)) ? *(void**)(w + 0x2e0) : NULL;
    if (!ws || !Readable(w + 0x534, 0x10)) return -1;
    prep(w, 0.0f, 1);
    int32_t slot = slotFn(ws, weapon, 0);
    *(uint32_t*)(w + 0x53c) = *(uint32_t*)(w + 0x540);
    *(uint32_t*)(w + 0x540) = *(uint32_t*)(w + 0x534) = *(uint32_t*)(w + 0x538) = 0;
    FwArr a = { 0 }, b = { 0 };
    void* proj = NULL;
    uint64_t r = g_nextLaunchWeapon(ws, weapon, target, &proj, &slot, 0, 0, 0, &a, &b);
    void* m = *gmalloc;
    typedef void (*FreeFn)(void* self, void* p);
    if (m && a.p) ((FreeFn)(*(void***)m)[0x48 / 8])(m, a.p);
    if (m && b.p) ((FreeFn)(*(void***)m)[0x48 / 8])(m, b.p);
    *outProj = (uint8_t*)proj;
    return (uint8_t)r == 1 ? 1 : 0;
}

static int FwIsA(uint8_t* proj, int32_t at)              /* IsA the class PlaneWeaponsFired asks for at that call */
{
    uint8_t* site = g_fPlaneFired + at;                   /* call <its StaticClass> */
    if (site[0] != 0xE8) return 0;
    uint8_t* sc = site + 5 + *(int32_t*)(site + 1);
    if (!InGame(sc)) return 0;
    uint8_t* cls = ((StaticClassFn)sc)(), *pc = *(uint8_t**)(proj + 0x10);
    if (!cls || !pc || !Readable(cls + 0x30, 0x10) || !Readable(pc + 0x30, 0x10)) return 0;
    int32_t d = *(int32_t*)(cls + 0x38);
    if (d < 0 || d > *(int32_t*)(pc + 0x38)) return 0;
    uint8_t** chain = *(uint8_t***)(pc + 0x30);
    return Readable(chain + d, 8) && chain[d] == cls + 0x30;
}

static void FwCapture(uint8_t* src, CoArr* projs)
{
    uint8_t* copy = CoRefGet(&FD.plane);
    double sp[3], sr[3], cp[3], cr[3];
    if (!copy || !CoReadPose(src, sp, sr) || !CoReadPose(copy, cp, cr)) return;
    int32_t n = projs->num < 0 ? 0 : projs->num > 8 ? 8 : projs->num;
    if (!n || !Readable(projs->data, 8 * (size_t)n)) return;
    for (int32_t i = 0; i < n; ++i) {
        uint8_t* pj = ((uint8_t**)projs->data)[i];
        ++FW.seen;
        if (!pj || !LiveObject(pj) || !Readable(pj, 0x6f0)) continue;
        if (!FwIsA(pj, FW_EXPLOSIVE)) {                   /* a special of another kind: select and arm it there */
            int kind = FwIsA(pj, FW_INSTANT) ? 1 : FwIsA(pj, FW_BULLET) ? 2 : FwIsA(pj, FW_ELECTRONIC) ? 3 : 0;
            if (kind && g_fsN < FS_Q) { g_fsQ[g_fsN].kind = (uint8_t)kind; g_fsQ[g_fsN].weapon = pj[0x3a8]; ++g_fsN; ++FW.special; }
            else if (!kind) ++FW.unknown;
            continue;
        }
        ++FW.explosive;
        if (g_fwN >= FW_Q) { ++FW.dropped; continue; }
        uint8_t* root = *(uint8_t**)(pj + 0x1a0);
        if (!root || !Readable(root + 0x220, 24)) continue;
        double loc[3], rot[3], vel[3] = { 0, 0, 0 }, pl[3];
        memcpy(loc, root + 0x220, 24);
        if (!CoReadPose(pj, pl, rot)) { rot[0] = rot[1] = rot[2] = 0; }
        double* v = ((GetVelFn)(*(void***)pj)[0x358 / 8])(pj, vel);
        if (v && v != vel && Readable(v, 24)) memcpy(vel, v, 24);
        FwData* d = &g_fwQ[g_fwN].d;
        memset(d, 0, sizeof(*d));
        d->netId = 0xC000000000000000ull | ++FW.nextId;
        d->weapon = pj[0x3a8]; d->slot = pj[0x6d0]; d->unk26 = pj[0x6d4]; d->seed = pj[0x6b4]; d->lockon = pj[0x3c8];
        uint8_t* tg = *(uint8_t**)(pj + 0x3f0);
        if (tg && !LiveObject(tg)) tg = NULL;
        uint8_t* troot = tg ? *(uint8_t**)(tg + 0x1a0) : NULL;
        double tl[3];
        if (troot && Readable(troot + 0x220, 24)) memcpy(tl, troot + 0x220, 24);
        else for (int k = 0; k < 3; ++k) tl[k] = loc[k] + vel[k] * 5.0;
        for (int k = 0; k < 3; ++k) {
            double at = loc[k] + (cp[k] - sp[k]);              /* from the copy: your offset from it */
            d->initLoc[k] = (int32_t)(at + (at < 0 ? -0.5 : 0.5));
            d->tgtLoc[k] = (int32_t)(tl[k] + (tl[k] < 0 ? -0.5 : 0.5));
            d->initRot[k] = (float)rot[k]; d->initVel[k] = (float)vel[k];
        }
        memset(&g_fwQ[g_fwN].target, 0, sizeof(CoRef));
        if (tg) CoRefSet(&g_fwQ[g_fwN].target, tg);
        ++g_fwN; ++FW.queued;
    }
}

static void OnPlaneFired(uint8_t* plane, CoArr* projs)
{
    g_nextPlaneFired(plane, projs);
    if (FD.on && plane && plane == FD.src.obj && CoRefGet(&FD.src) && projs && Readable(projs, sizeof(CoArr))) FwCapture(plane, projs);
}

static uint64_t OnLaunchWeapon(void* ws, uint64_t weapon, void* target, void** outProj, void* slot, uint64_t a6, uint64_t a7,
                               uint64_t lockon, void* arrA, void* arrB)
{
    if (FW.in && !target && FW.inTarget) target = FW.inTarget;      /* (our replay: the shooter's target, here) */
    uint64_t r = g_nextLaunchWeapon(ws, weapon, target, outProj, slot, a6, a7, lockon, arrA, arrB);
    if (FW.in) { FW.ret = r; FW.proj = (outProj && Readable(outProj, 8)) ? (uint8_t*)*outProj : NULL; }
    return r;
}

static uint64_t OnFireFlares(uint8_t* w)
{
    uint64_t r = g_nextFireFlares(w);
    uint8_t* src = FD.on ? CoRefGet(&FD.src) : NULL;
    if (src && (uint8_t)r && Readable(src + FW_W, 8) && w == *(uint8_t**)(src + FW_W)) { ++g_fwFlares; ++FW.flares; }
    return r;
}

/* the queued shots and flares from the copy, after its update (OnRemoteUpdate); the gun's trigger mirrored */
static void FwFlush(uint8_t* copy)
{
    uint8_t* src = CoRefGet(&FD.src);
    uint8_t* w = Readable(copy + FW_W, 8) ? *(uint8_t**)(copy + FW_W) : NULL;
    uint8_t* sw = (src && Readable(src + FW_W, 8)) ? *(uint8_t**)(src + FW_W) : NULL;
    if (w && sw && Readable(w + 0x30e, 8) && Readable(sw + 0x30e, 8)) {
        uint8_t on = sw[0x30e] ? 1 : 0;
        FW.gunYours30e += sw[0x30e] != 0; FW.gunYours311 += sw[0x311] != 0;
        if (w[0x311] != on) { w[0x311] = on; ++FW.gunSet; }
    }
    if (!g_fwN && !g_fwFlares && !g_fsN) return;
    int n = g_fwN, fl = g_fwFlares, ns = g_fsN;
    g_fwN = g_fwFlares = g_fsN = 0;
    if (!w || !src) { if (!FW.saidW++) Log(L"coop2mp: T4: the copy (or you) has no weapon system; %d shots not replayed", n); FW.dropped += n; return; }
    if (*(void**)(copy + 0x10) != *(void**)(src + 0x10)) {
        if (!FW.saidOther++) Log(L"coop2mp: T4: the copy is another airframe (its weapon numbers aren't yours): your shots aren't replayed on it");
        FW.dropped += n; return;
    }
    for (int k = 0; k < fl; ++k) if ((uint8_t)g_nextFireFlares(w)) ++FW.flaresOk;
    for (int k = 0; k < ns && g_fSelectSpecial && g_fArmSpecial; ++k) {
        /* (as the InstantWeaponFire / ElectronicMeasureFire handlers: select, arm; BulletWeaponFire's: armed and disarmed) */
        ((SelectSpecialFn)g_fSelectSpecial)(copy, g_fsQ[k].weapon);
        ((ArmSpecialFn)g_fArmSpecial)(copy, 1);
        if (g_fsQ[k].kind == 2) ((ArmSpecialFn)g_fArmSpecial)(copy, 0);
        int lr = 0;
        uint8_t* lp = NULL;
        /* (the laser, T4a.3; the ECM / ESM too, T4a.4: armed alone it showed nothing; the effect on the planes it jams or
         * marks is the ElectronicMeasureEffect message's, 0x1474dbdf0, applied to those planes, not to the user's) */
        if (g_fsQ[k].kind == 1 || g_fsQ[k].kind == 3) lr = FwLaunchDirect(copy, g_fsQ[k].weapon, NULL, &lp);
        ++FW.specialDone;
        if (FW.saidSpecial < 6) {
            ++FW.saidSpecial;
            Log(L"coop2mp: T4: your %s (weapon %d) replayed on the copy: selected and armed%s (its selected special now %d)%s, "
                L"launched %d (%p)", kFwKind[g_fsQ[k].kind], (int32_t)g_fsQ[k].weapon, g_fsQ[k].kind == 2 ? L", then disarmed" : L"",
                Readable(w + 0x308, 4) ? *(int32_t*)(w + 0x308) + 1 : -1, g_fsQ[k].kind != 2 ? L"; launched from its weapons" : L"",
                lr, lp);
        }
    }
    if (!n) return;
    void* world = VCall(copy, VF_WORLD);
    uint8_t* nm = (world && g_fNetManager) ? ((NetMgrFn)g_fNetManager)(world) : NULL;
    if (!nm || !Readable(nm + 0x2e0, 0x58) || !g_fRemoteFire || !g_nextLaunchWeapon) {
        if (!FW.saidNoNm++) Log(L"coop2mp: T4: no network manager here (%p, world %p) or no remote fire (%p): %d shots not replayed", nm,
            world, g_fRemoteFire, n);
        FW.dropped += n; return;
    }
    for (int i = 0; i < n; ++i) {
        FwMsg m;
        memset(&m, 0, sizeof(m));
        m.triggerTime = ~0ull;                              /* (in the future: no latency) */
        m.wd = &g_fwQ[i].d; m.wdNum = m.wdMax = 1;
        void* pair[2] = { &m, NULL };
        FW.inTarget = CoRefGet(&g_fwQ[i].target); FW.in = 1; FW.ret = 0; FW.proj = NULL;
        ((RemoteFireFn)g_fRemoteFire)(copy, pair);
        FW.in = 0;
        int ok = (uint8_t)FW.ret == 1 && FW.proj;
        if (ok) ++FW.launched; else ++FW.failed;
        if (FW.said < 6) {
            ++FW.said;
            uint8_t* pt = (FW.proj && Readable(FW.proj + 0x3f0, 8)) ? *(uint8_t**)(FW.proj + 0x3f0) : NULL;
            Log(L"coop2mp: T4: your shot (weapon %d, slot %d, lock-ons %d, seed %d, target %p) replayed on the copy: %s, its missile %p "
                L"(target %p, network id %x), the network manager %p", (int32_t)g_fwQ[i].d.weapon, (int32_t)g_fwQ[i].d.slot,
                (int32_t)g_fwQ[i].d.lockon, (int32_t)g_fwQ[i].d.seed, FW.inTarget, ok ? L"launched" : L"NOT LAUNCHED", FW.proj, pt,
                (uint32_t)g_fwQ[i].d.netId, nm);
        }
    }
}

/* T4a.4 / T4a.5: the gear. A remote plane runs two flight engines: its own (+0x2268) and a second one (+0x3c60) that
 * RemoteUpdate loads from the physics message (0x1474d8c00(network object, second)), gives the input (SetInput
 * 0x144d32580) and simulates (0x144d326e0) every frame, then copies its State over the plane's (+0x2b18 = +0x4510).
 * RemoteUpdate's gear check (0x147d6f982) lowers the plane's own engine's gear (0x144d33fb0(engine, 1)) when that State
 * has bit 9 and the gear flag (engine +0x34 bit 0x10, +0x229c) isn't set, and raises it (0x144d33ea0(engine, 0, 0, 0))
 * the other way. But the second engine's simulation makes bits 9 and 11 from its own gear, still up: the gear sent never
 * survived it (T4a.3: `yours 40A00, its 40000`), and the plane's gear lowered by hand was raised again the next frame
 * (T4a.4: lowered every frame, never down). So both engines' gear is moved here, after RemoteUpdate, the second's first:
 * then its simulation keeps bit 9 and RemoteUpdate's own check agrees. The calls, the flag and both engines' offsets
 * are read from RemoteUpdate's code. */
typedef void (*MsGearUpFn)(uint8_t* ms, uint64_t a, uint64_t b, uint64_t c);
typedef void (*MsGearDownFn)(uint8_t* ms, uint64_t down);
static int FlGear(uint8_t* plane, int down)              /* 1 moved (either engine), 0 already so, < 0 not found */
{
    uint8_t* f = g_fRemoteUpdate;
    if (!f) return -2;
    uint8_t* l2 = f + 0xa2, *chk = f + 0x8c2, *lu = f + 0x8fb, *cu = f + 0x907, *ld = f + 0x912, *cd = f + 0x91b;
    if (l2[0] != 0x48 || l2[1] != 0x8D || l2[2] != 0x93 || chk[0] != 0x0F || chk[1] != 0xB6 || chk[2] != 0x93 ||
        lu[0] != 0x48 || lu[1] != 0x8D || lu[2] != 0x8B || ld[0] != 0x48 || ld[1] != 0x8D || ld[2] != 0x8B ||
        cu[0] != 0xE8 || cd[0] != 0xE8) return -2;
    int32_t flag = *(int32_t*)(chk + 3), ms = *(int32_t*)(lu + 3), ms2 = *(int32_t*)(l2 + 3), rel = flag - ms;
    if (ms <= 0 || ms >= 0x8000 || ms2 <= 0 || ms2 >= 0x8000 || rel <= 0 || rel >= 0x1000 || ms != *(int32_t*)(ld + 3)) return -2;
    MsGearDownFn gd = (MsGearDownFn)(cd + 5 + *(int32_t*)(cd + 1));
    MsGearUpFn gu = (MsGearUpFn)(cu + 5 + *(int32_t*)(cu + 1));
    int32_t eng[2] = { ms2, ms };
    int moved = 0;
    for (int k = 0; k < 2; ++k) {
        uint8_t* e = plane + eng[k];
        if (!Readable(e + rel, 1)) continue;
        int have = (e[rel] & 0x10) != 0;
        if (!!down == have) continue;
        if (down) gd(e, 1); else gu(e, 0, 0, 0);
        moved = 1;
    }
    return moved;
}
static int32_t g_fgSaid;

static uint64_t OnRemoteUpdate(uint8_t* plane, float dt)
{
    int test = 0, ns = -1;
    if (plane) {
        if (FD.on && plane == FD.plane.obj && CoRefGet(&FD.plane)) {
            ++FD.calls; FD.lastCallAt = CoNow();
            FdFeed(plane);
            test = 1;
        } else {
            ns = FlNetSlot(plane);
            if (ns >= 0) FlNetFeed(ns, plane);
        }
    }
    uint64_t r = g_nextRemoteUpdate(plane, dt);
    if (test) {
        FwFlush(plane);
        uint8_t* src = CoRefGet(&FD.src);
        uint32_t st = (src && Readable(src + FD_STATE, 4)) ? *(uint32_t*)(src + FD_STATE) : 0;
        int g = src ? FlGear(plane, (st >> 9) & 1) : 0;
        if (g && g_fgSaid < 8) { ++g_fgSaid; Log(L"coop2mp: T4: the copy's gear %s (your State %x): %d", (st >> 9) & 1 ? L"down" : L"up", st, g); }
    } else if (ns >= 0 && CO.players[ns].hasFl) {
        uint32_t st;
        memcpy(&st, CO.players[ns].fl + 9, 4);
        FlGear(plane, (st >> 9) & 1);
    }
    return r;
}

/* The afterburner's glow (T1c's test, 2026-10-30: the fed plane flew and its control surfaces moved, but no glow). A
 * player plane's surface component update (0x147d32b00, sigs.h kSigSurfacePP) takes its afterburner alpha from the
 * plane's afterburner amount plane+0x39d0. Your own plane's comes from its movement update (0x14731e7e0 writes the
 * block plane+0x39c0.. from its flight engine at +0x3088); nothing writes a remote plane's. So the fed plane gets the
 * source's, written just before the component reads it; a real plane of another player's (T3) their game's own. */
typedef uint64_t (*SurfacePPFn)(uint8_t* comp, float dt);
static uint8_t*    g_fSurfacePP;                        /* found by FindFunctions (sigs.h kSigSurfacePP) */
static SurfacePPFn g_nextSurfacePP;

static uint64_t OnSurfacePP(uint8_t* comp, float dt)
{
    uint8_t* pl = (comp && Readable(comp + 0x188, 8)) ? *(uint8_t**)(comp + 0x188) : NULL;
    int ns = (pl && !(FD.on && pl == FD.plane.obj)) ? FlNetSlot(pl) : -1;
    if (ns >= 0 && CO.players[ns].hasFl && CoRefGet(&CO.players[ns].plane.ref))
        *(float*)(pl + FD_AB) = CO.players[ns].fl[6] / 255.0f;
    if (FD.on && comp && Readable(comp + 0x188, 8)) {
        uint8_t* plane = *(uint8_t**)(comp + 0x188);
        uint8_t* src = (plane && plane == FD.plane.obj && CoRefGet(&FD.plane)) ? CoRefGet(&FD.src) : NULL;
        if (src) {
            float found = *(float*)(plane + FD_AB), ab = *(float*)(src + FD_AB);
            if (!(ab >= 0.0f && ab <= 4.0f)) ab = 0.0f;
            if (found > FD.abFound) FD.abFound = found;
            if (ab > FD.abSrc) FD.abSrc = ab;
            *(float*)(plane + FD_AB) = ab;
            ++FD.abWrites;
        }
    }
    return g_nextSurfacePP(comp, dt);
}

/* T1e: the hits on the fed plane (T1d's test: enemies ordered onto it fired, a missile exploded on it, its health never
 * moved). A player plane's damage 0x147d5a430 (sigs.h kSigPPDamage): float (plane, float damage, event (+0x18 its kind),
 * instigator, a fifth), returning what it took; it ends in the game object's 0x147d203e0. Logged for the fed plane only
 * (its first 10 one by one, then a second's sum): is it called, and does its health move. In co-op this is where a hit
 * on another player's plane would be sent to their game (Online Mode applies a remote player's damage there). */
typedef float (*PPDamageFn)(uint8_t* plane, float dmg, uint8_t* evt, uint8_t* inst, void* a5);
static uint8_t*   g_fPPDamage;                          /* found by FindFunctions (sigs.h kSigPPDamage) */
static PPDamageFn g_nextPPDamage;

static float OnPPDamage(uint8_t* plane, float dmg, uint8_t* evt, uint8_t* inst, void* a5)
{
    if (!(FD.on && plane && plane == FD.plane.obj && CoRefGet(&FD.plane))) {
        int s = FlNetSlot(plane);                         /* (T3: another player's real plane; counted, FlNetLog) */
        if (s >= 0 && !g_netHits[s]++)
            Log(L"coop2mp: a hit on player %d's real plane here: %d damage (x10), from %p (refused here: their own game takes their "
                L"hits; counted once a minute)", s + 1, (int32_t)(dmg * 10), inst);
        return g_nextPPDamage(plane, dmg, evt, inst, a5);
    }
    int32_t before = CoHealth(plane);
    float took = g_nextPPDamage(plane, dmg, evt, inst, a5);
    int32_t after = CoHealth(plane);
    ++FD.hits;
    if (dmg > 0 && dmg < 1e7f) FD.hitDmg += dmg;
    FD.hitApplied += before - after;
    if (FD.hitsSaid < 10) {
        ++FD.hitsSaid;
        int32_t kind = (evt && Readable(evt + 0x18, 1)) ? (int32_t)evt[0x18] : -1;
        Log(L"coop2mp: hit on the fed plane %p: damage %d (x10), kind %d, from %p, health %d -> %d, the game returned %d (x10)",
            plane, (int32_t)(dmg * 10), kind, inst, before, after, (int32_t)(took * 10));
    }
    return took;
}

/* once a second while feeding (from FlightInputHook): how far the plane is from where it was sent */
static void FdLog(void)
{
    if (!FD.on) return;
    double now = CoNow();
    if (now - FD.lastLog < 1.0) return;
    FD.lastLog = now;
    uint8_t* plane = CoRefGet(&FD.plane);
    if (!plane) { FD.on = 0; Log(L"coop2mp: the fed plane is gone; feeding off"); return; }
    double p[3], rot[3];
    int32_t off = -1;
    if (CoReadPose(plane, p, rot)) {
        double dx = p[0] - FD.tgt[0], dy = p[1] - FD.tgt[1], dz = p[2] - FD.tgt[2];
        off = (int32_t)(CoSqrt(dx * dx + dy * dy + dz * dz) / 100.0);
    }
    float spd = Readable(plane + FD_SPEED, 4) ? *(float*)(plane + FD_SPEED) : -1.0f;
    uint32_t its = Readable(plane + FD_STATE, 4) ? *(uint32_t*)(plane + FD_STATE) : 0;
    Log(L"coop2mp: fed plane %p: %u updates, %u fed, %u skipped; %d m off where it was sent, its speed %d m/s; afterburner x1000 "
        L"yours up to %d, left on it up to %d, %u written; State bits yours %x, its %x%s", plane, FD.calls, FD.fed, FD.skipped, off,
        (int32_t)spd, (int32_t)(FD.abSrc * 1000), (int32_t)(FD.abFound * 1000), FD.abWrites, FD.stateOr, its,
        (now - FD.lastCallAt > 2.0) ? L"; ITS REMOTE UPDATE ISN'T RUNNING (tick off? not alive?)" : L"");
    if (FD.hits)
        Log(L"coop2mp: fed plane %p: %u hits this second, %d damage asked, %d taken off its health (health now %d)", plane, FD.hits,
            (int32_t)FD.hitDmg, (int32_t)FD.hitApplied, CoHealth(plane));
    {                                                    /* (its gear: both engines' input flags +0x34 and gear state +0x710) */
        const uint8_t* e1 = plane + 0x2268, *e2 = plane + 0x3c60;
        int r1 = Readable(e1 + 0x34, 1) && Readable(e1 + 0x710, 1), r2 = Readable(e2 + 0x34, 1) && Readable(e2 + 0x710, 1);
        uint8_t* src = CoRefGet(&FD.src);
        int sf = -1;
        for (int i = 0; i < 4; ++i) if (src && g_flIn[i].plane == src) sf = g_flIn[i].flags;
        Log(L"coop2mp: fed plane %p gear: your input flags %x; its engine flags %x / %x, gear state %d / %d (own / second)", plane, sf,
            r1 ? e1[0x34] : 0xff, r2 ? e2[0x34] : 0xff, r1 ? e1[0x710] : -1, r2 ? e2[0x710] : -1);
    }
    if (FW.seen || FW.flares || FW.gunYours30e || FW.gunYours311 || FW.dropped)
        Log(L"coop2mp: T4 this second: your launches %u (%u missiles, %u specials, %u unknown), queued %u, replayed %u launched / %u not, "
            L"%u specials, %u dropped; your flares %u, the copy's %u; your gun trigger frames %u (+30e) %u (+311), the copy's trigger "
            L"set %u times", FW.seen, FW.explosive, FW.special, FW.unknown, FW.queued, FW.launched, FW.failed, FW.specialDone, FW.dropped,
            FW.flares, FW.flaresOk, FW.gunYours30e, FW.gunYours311, FW.gunSet);
    FW.seen = FW.explosive = FW.queued = FW.launched = FW.failed = FW.dropped = FW.flares = FW.flaresOk = 0;
    FW.special = FW.unknown = FW.specialDone = 0;
    FW.gunYours30e = FW.gunYours311 = FW.gunSet = 0;
    FD.abSrc = FD.abFound = 0; FD.abWrites = 0; FD.stateOr = 0; FD.hits = 0; FD.hitDmg = FD.hitApplied = 0;
}

/* SV_CoopFeed(plane, source, forward_m, right_m, up_m) -> 1: a remote player plane (role 2, its tick on) flown by its own
 * update toward source's pose + that offset, with source's inputs (COOP2MP T1c); SV_CoopFeed(0) -> 1: off. < 0: -1 bad
 * args, -2 RemoteUpdate not hooked, -3 no network message on it. A plane fed isn't moved by SV_CoopFollow. */
static int L_CoopFeed(void* lua)
{
    uint8_t* plane = ArgObject(lua);
    if (!plane) { if (FD.on) Log(L"coop2mp: feeding off (Lua)"); FD.on = 0; return Ret(lua, 1); }
    uint8_t* src = ArgObject(lua);
    double f = 0, rt = 0, up = 0;
    ArgNumber(lua, &f); ArgNumber(lua, &rt); ArgNumber(lua, &up);
    if (!src || !LiveObject(plane) || !LiveObject(src) || CoKind(plane) != 2 || CoKind(src) != 2) return Ret(lua, -1);
    if (!(f > -5000 && f < 5000 && rt > -5000 && rt < 5000 && up > -5000 && up < 5000)) return Ret(lua, -1);
    if (!g_nextRemoteUpdate) return Ret(lua, -2);
    FD.on = 0;
    uint8_t* in = NULL;
    uint8_t* r = FdMessage(plane, &in);
    if (!r) {
        Log(L"coop2mp: plane %p has no network message to feed (NetworkObject +%x, class %p)", plane, (uint32_t)FD.noOff, g_fdNetCls);
        return Ret(lua, -3);
    }
    if (g_follow.obj == plane) memset(&g_follow, 0, sizeof(g_follow));
    memset(&FD.plane, 0, sizeof(FD.plane)); memset(&FD.src, 0, sizeof(FD.src));
    CoRefSet(&FD.plane, plane); CoRefSet(&FD.src, src);
    FD.off[0] = f * 100; FD.off[1] = rt * 100; FD.off[2] = up * 100;
    FD.calls = FD.fed = FD.skipped = FD.abWrites = 0; FD.hits = FD.hitsSaid = 0; FD.hitDmg = FD.hitApplied = 0;
    FD.said = 0; FD.srcAt = 0; FD.spd = 0; FD.abSrc = FD.abFound = 0; FD.stateOr = 0;
    FD.lastLog = FD.lastCallAt = CoNow();
    FD.on = 1;
    Log(L"coop2mp: plane %p fed from %p (%d m ahead, %d m right, %d m up): its own update flies it (message %p, NetworkObject +%x); "
        L"its afterburner from yours: %s; input message %p; hits logged: %s; your shots replayed: %s", plane, src, (int32_t)f, (int32_t)rt,
        (int32_t)up, r, (uint32_t)FD.noOff, g_nextSurfacePP ? L"yes" : L"NO (surface update not hooked)", in,
        g_nextPPDamage ? L"yes" : L"NO (not hooked)", (g_nextPlaneFired && g_nextLaunchWeapon && g_fRemoteFire && g_fNetManager)
        ? (*(void**)(plane + 0x10) == *(void**)(src + 0x10) ? L"yes" : L"no (another airframe)") : L"NO (game code not found)");
    g_fwN = g_fwFlares = g_fsN = 0;
    return Ret(lua, 1);
}

/* SV_CoopPPFx(plane, kind, value) -> 1: on another player's real plane here (a player plane of role 2, never yours): kind
 * 0 its flares (FireFlares on its weapon system, as Online Mode's PushFlare), 1 its gun's remote trigger (weapons +0x311 =
 * value, as HoldingMachineGunButton), 2 its landing gear (value 1 down, 0 up: the LandingGear handler's own calls).
 * < 0: -1 bad args / not such a plane, -2 that game code not found, -3 the flares didn't fire (none ready). COOP2MP T4:
 * sv_coop.lua's sync for real planes (the flag bits every game sends), and the Ctrl+F11 test's gear. */
static int L_CoopPPFx(void* lua)
{
    uint8_t* plane = ArgObject(lua);
    double kind = -1, value = 0;
    ArgNumber(lua, &kind); ArgNumber(lua, &value);
    if (!plane || !LiveObject(plane) || CoKind(plane) != 2 || plane == CO.me.obj || (FD.src.obj && plane == FD.src.obj) ||
        !Readable(plane + FW_W, 8)) return Ret(lua, -1);
    uint8_t* w = *(uint8_t**)(plane + FW_W);
    if (!w || !Readable(w + 0x311, 1)) return Ret(lua, -1);
    if (kind == 0) {
        FireFlaresFn ff = g_nextFireFlares ? g_nextFireFlares : (FireFlaresFn)g_fFireFlares;
        if (!ff) return Ret(lua, -2);
        return Ret(lua, (uint8_t)ff(w) ? 1 : -3);
    }
    if (kind == 1) { w[0x311] = value != 0 ? 1 : 0; return Ret(lua, 1); }
    if (kind == 2) {                                      /* (as RemoteUpdate's check: FlGear; T4a.4) */
        int g = FlGear(plane, value != 0);
        return Ret(lua, g < 0 ? g : 1);
    }
    return Ret(lua, -1);
}
