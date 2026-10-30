/* flight_test.c : runtime 0.28.5's flight pieces outside the game (tools/checks/flight_test.sh builds and runs it):
 *  1. The co-op flag bits end to end: SV_CoopMe's flags, a joiner's P packet into the host, the host's Q record out to
 *     a joiner, all 32 bits (CoSaneState never looks at them), and the afterburner bit (32) written to a bound AI
 *     stand-in's afterburner byte right after each frame's move (CoDrive, CoAbOffset), off again without it.
 *  2. DOWN's loiter autopilot (runtime/down_ctl.c) flying model planes: every pair of input signs (it has to learn them),
 *     a rate-command roll (the stick rolls the plane), a bank-angle roll (an assisted mode) and a quicker plane, from far
 *     away, from an inverted dive near the centre and from a climb beside it; called twice a frame as BuildFlightInput
 *     is, once with a pause in a probe, once with the signs known.
 *     Passes when it learned the signs and, over the last 50 s of 200, flew within 30 % of the radius and 120 m of the
 *     altitude, never past 70 deg of bank once circling.
 * The model plane is no AC8 flight model (that one isn't known): a constant 160 m/s, body rates following the inputs
 * (180 deg/s roll, 35 deg/s pitch per unit, lagged), the nose sagging in a bank and a little turn from bank alone: it
 * turns no tighter than ~1.8 km at 40 deg of bank (AC8's planes turn far tighter), so the circles asked are wider. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

/* ---- what coop.c takes from survival_rt.c (as tools/checks/coop_test.c) ---- */
#define RF_NOT_LIVE (0x10 | 0x20 | 0x8000 | 0x10000 | 0x40000000)
typedef struct { const char* p; size_t n; } StrView;
static int g_quiet;
static void Log(const wchar_t* fmt, ...)
{
    if (g_quiet) return;
    va_list ap; va_start(ap, fmt);
    wchar_t buf[1024]; _vsnwprintf(buf, 1023, fmt, ap); buf[1023] = 0;
    va_end(ap);
    wprintf(L"  [log] %ls\n", buf);
}
static int Readable(const void* p, size_t n) { (void)n; return p != NULL; }
static int LiveObject(void* o) { return o && !(*(uint32_t*)((uint8_t*)o + 8) & RF_NOT_LIVE); }
static double Sin(double x) { return sin(x); }
static double Cos(double x) { return cos(x); }

typedef struct { int n, at; int isNum[8]; double num[8]; const char* str[8]; int64_t retI; char retS[1200]; size_t retN; int retIsS; } FakeLua;
static int32_t FL_size(void* l) { FakeLua* f = l; return f->n - f->at; }
static uint8_t FL_isS(void* l, int32_t i) { FakeLua* f = l; (void)i; return f->at < f->n && !f->isNum[f->at]; }
static uint8_t FL_isN(void* l, int32_t i) { FakeLua* f = l; (void)i; return f->at < f->n && f->isNum[f->at]; }
static StrView* FL_getS(void* l, StrView* out, int32_t i) { FakeLua* f = l; (void)i; out->p = f->str[f->at]; out->n = strlen(f->str[f->at]); f->at++; return out; }
static double FL_getN(void* l, int32_t i) { FakeLua* f = l; (void)i; return f->num[f->at++]; }
static void FL_setI(void* l, int64_t v) { FakeLua* f = l; f->retI = v; f->retIsS = 0; }
static void FL_setS(void* l, const char* s, size_t n) { FakeLua* f = l; memcpy(f->retS, s, n); f->retS[n] = 0; f->retN = n; f->retIsS = 1; }
static void* FakeFindObject(const wchar_t* c, const wchar_t* n, int32_t r, int32_t b) { (void)c; (void)n; (void)r; (void)b; return NULL; }
static void* FakeValuePtr(void* obj, const wchar_t* prop) { (void)obj; (void)prop; return NULL; }
static struct {
    void* (*findObject)(const wchar_t* cls, const wchar_t* name, int32_t required, int32_t banned);
    void* (*valuePtr)(void* obj, const wchar_t* prop);
    int32_t (*luaStackSize)(void*); uint8_t (*luaIsString)(void*, int32_t); uint8_t (*luaIsNumber)(void*, int32_t);
    StrView* (*luaGetString)(void*, StrView*, int32_t); double (*luaGetNumber)(void*, int32_t);
    void (*luaSetInteger)(void*, int64_t); void (*luaSetString)(void*, const char*, size_t);
} U = { FakeFindObject, FakeValuePtr, FL_size, FL_isS, FL_isN, FL_getS, FL_getN, FL_setI, FL_setS };
static int ResolveUE4SS(void) { return 1; }
#define VF_WORLD 0x31
typedef uint8_t (*DestroyActorFn)(void* actor, uint8_t netForce);
static DestroyActorFn g_destroyActor;
static void* VCall(void* obj, int slot) { (void)obj; (void)slot; return NULL; }
static int InGame(const void* p) { (void)p; return 0; }
static int ArgNumber(void* lua, double* v) { if (U.luaStackSize(lua) < 1 || !U.luaIsNumber(lua, 1)) return 0; *v = U.luaGetNumber(lua, 1); return 1; }
static int Ret(void* lua, int64_t v) { U.luaSetInteger(lua, v); return 1; }

#include "../../runtime/coop.c"
#include "../../runtime/down_ctl.c"

static int g_fail;
#define CHECK(c, ...) do { if (!(c)) { printf("FAILED: "); printf(__VA_ARGS__); printf("\n"); g_fail = 1; } } while (0)

/* ---- 1. the flag bits ---- */
static uint8_t FakeTele(void* self, const double* loc, const double* rot, uint8_t t, uint8_t nc)
{
    (void)loc; (void)rot; (void)t; (void)nc;
    ((uint8_t*)self)[0x29b8] = 0;                     /* as the AI plane's OnReposition: EnableTakeoffAfterburner(false) */
    return 1;
}
static void* g_vt[400];

static void FlagsTest(void)
{
    FakeLua f;
    double now = CoNow();
    double pos[3] = { 100000, -200000, 300000 };
    float q[4] = { 0, 0, 0.3826834f, 0.9238795f };
    /* SV_CoopMe(0, flags): the flags kept whole */
    memset(&f, 0, sizeof(f)); f.isNum[0] = f.isNum[1] = 1; f.num[0] = 0; f.num[1] = 233; f.n = 2;
    L_CoopMe(&f);
    CHECK(CO.meFlags == 233, "SV_CoopMe's flags %u, want 233", CO.meFlags);

    /* a joiner's P into the host: slot 1's flags all 32 bits, kept in its Q record for the relay */
    memset(&CO, 0, sizeof(CO));
    CO.open = 1; CO.role = CO_ROLE_HOST; CO.mode = CO_MODE_UDP; CO.mySlot = 0; CO.maxPlayers = 4;
    CoSockAddr a1 = { 2, 0x1111, 0x0100007f, { 0 } };
    CO.links[1].used = 1; CO.links[1].addr = a1;
    uint8_t b[CO_MAX_PACKET], *p = CoHeader(b, 'P');
    *p++ = 1; *p++ = 0; *p++ = 0; *p++ = 0;
    CoPut32(&p, 5000);
    memcpy(p, pos, 24); p += 24; memcpy(p, q, 16); p += 16;
    int32_t hp = 900; float maxHp = 100; memcpy(p, &hp, 4); p += 4; memcpy(p, &maxHp, 4); p += 4;
    CoPut32(&p, 0xFFFFFFF0u);
    CoOnPacket(b, (uint32_t)(p - b), 0, &a1, now);
    CHECK(CO.players[1].flags == 0xFFFFFFF0u, "host: player 2's flags %x from P, want FFFFFFF0", CO.players[1].flags);
    uint32_t rel; memcpy(&rel, CO.players[1].rec + 45, 4);
    CHECK(CO.players[1].fresh && rel == 0xFFFFFFF0u, "host: player 2's Q record flags %x, want FFFFFFF0", rel);

    /* the host's Q into a joiner: two records, flags 0xE9 (1, 8, 32, 64, 128) and 0x3F */
    memset(&CO, 0, sizeof(CO));
    CO.open = 1; CO.role = CO_ROLE_JOIN; CO.mode = CO_MODE_UDP; CO.mySlot = 1; CO.maxPlayers = 4; CO.delay = 0.1;
    CoSockAddr a0 = { 2, 0x2222, 0x0100007f, { 0 } };
    CO.links[0].used = 1; CO.links[0].addr = a0;
    p = CoHeader(b, 'Q');
    *p++ = 2;
    CoQRec(p, 0, 7000, pos, q, 1000, 100.0f, 0xE9); p += CO_Q_REC;
    CoQRec(p, 2, 7000, pos, q, 1000, 100.0f, 0x3F); p += CO_Q_REC;
    CoOnPacket(b, (uint32_t)(p - b), 0, &a0, now);
    CHECK(CO.players[0].flags == 0xE9 && CO.players[2].flags == 0x3F, "joiner: flags %x / %x from Q, want E9 / 3F",
          CO.players[0].flags, CO.players[2].flags);
    memset(&f, 0, sizeof(f)); f.isNum[0] = 1; f.num[0] = 0; f.n = 1;
    L_CoopPeerAt(&f);
    CHECK(strstr(f.retS, ",233,") != NULL, "SV_CoopPeerAt(0) = \"%s\", want its flags 233", f.retS);
    char peerAt[200]; strcpy(peerAt, f.retS);

    /* the afterburner byte: player 1 (the host) bound to an AI stand-in; the move clears it, CoDrive sets it from bit 32 */
    static uint8_t fakeEnable[0x100];
    fakeEnable[0x82] = 0x40; fakeEnable[0x83] = 0x88; fakeEnable[0x84] = 0xBB;
    int32_t off = 0x29b8; memcpy(fakeEnable + 0x85, &off, 4);
    g_fTakeoffAB = fakeEnable; g_coAbOff = -1;
    for (int i = 0; i < 400; ++i) g_vt[i] = (void*)FakeTele;
    g_fAITeleportTo = g_fAITeleportInner = (uint8_t*)FakeTele;
    uint8_t* standIn = calloc(1, 0x6000);
    *(void***)standIn = g_vt; *(uint32_t*)(standIn + 0xC) = 77; *(uint64_t*)(standIn + 0x18) = 0x7777;
    memset(&f, 0, sizeof(f)); f.isNum[0] = f.isNum[1] = 1; f.num[0] = 0; f.num[1] = (double)(uintptr_t)standIn; f.n = 2;
    L_CoopPeer(&f);
    CHECK(f.retI == 1, "SV_CoopPeer(0, stand-in) = %lld", (long long)f.retI);
    /* (another snapshot or two, so CoSample has something at the render time) */
    for (int k = 1; k <= 3; ++k) {
        p = CoHeader(b, 'Q'); *p++ = 1;
        CoQRec(p, 0, 7000 + 33 * k, pos, q, 1000, 100.0f, 0xE9); p += CO_Q_REC;
        CoOnPacket(b, (uint32_t)(p - b), 0, &a0, now);
    }
    CoDrive(CoNow());
    CHECK(standIn[0x29b8] == 1 && CO.players[0].plane.drives > 0, "afterburner byte %d after a move with bit 32 (moves %d), want 1",
          standIn[0x29b8], CO.players[0].plane.drives);
    CO.players[0].flags = 0xC9;                        /* bit 32 off */
    CoDrive(CoNow());
    CHECK(standIn[0x29b8] == 0, "afterburner byte %d after a move without bit 32, want 0", standIn[0x29b8]);
    printf("flags: SV_CoopMe 233, P -> host FFFFFFF0 (and its Q record), Q -> joiner E9 / 3F, PeerAt \"%s\", afterburner byte %s\n",
           peerAt, g_fail ? "WRONG" : "follows bit 32");
    memset(&CO, 0, sizeof(CO));
}

/* ---- 2. DOWN's autopilot against model planes ---- */
typedef struct { double x, y, z, th, ps, ph, p, q; } Model;          /* m; deg; body rates deg/s */
static double Wrap(double a) { while (a > 180) a -= 360; while (a < -180) a += 360; return a; }
/* kind 0: rate-command roll; 1: bank-angle roll (an assisted mode); 2: a quicker, tighter-turning plane (260 m/s, 250 deg/s
 * roll, 60 deg/s pitch, more sag and turn from bank); 3: a late plane (Fly hands it its inputs 0.4 s late; 200 m/s, 70 deg/s
 * roll, 25 deg/s pitch): the user's co-op run of 2026-10-30, where AC8's plane answered the roll probe with -3 / +2 deg/s
 * and the sign read from that was wrong; the probe may read it wrong here too, the in-flight check has to put it right */
static void ModelStep(Model* m, const float* in, int sr, int sp, int kind, double dt)
{
    const double V = kind == 2 ? 260.0 : kind == 3 ? 200.0 : 160.0, D = CO_PI / 180.0, sag = kind == 2 ? 10.0 : 6.0,
                 turn = kind == 2 ? 12.0 : 6.0;
    double pc = kind == 1 ? (sr * in[2] * 75.0 - m->ph) / 0.35 : sr * in[2] * (kind == 2 ? 250.0 : kind == 3 ? 70.0 : 180.0);
    double qc = sp * in[0] * (kind == 2 ? 60.0 : kind == 3 ? 25.0 : 35.0);
    m->p += (pc - m->p) * fmin(1.0, dt / 0.1);
    m->q += (qc - m->q) * fmin(1.0, dt / 0.15);
    double ph = m->ph * D, th = m->th * D;
    double php = m->p + m->q * sin(ph) * tan(th);
    double thp = m->q * cos(ph) - sag * (1.0 - cos(ph));                 /* the nose sags in a bank */
    double psp = m->q * sin(ph) / cos(th) + turn * sin(ph);               /* and bank alone turns a little */
    m->ph = Wrap(m->ph + php * dt); m->th += thp * dt; m->ps = Wrap(m->ps + psp * dt);
    if (m->th > 85) m->th = 85;
    if (m->th < -85) m->th = -85;
    th = m->th * D;
    m->x += V * cos(th) * cos(m->ps * D) * dt; m->y += V * cos(th) * sin(m->ps * D) * dt; m->z += V * sin(th) * dt;
}

typedef struct { const char* name; double x, y, z, ps, th, ph, alt, R; } Start;

/* known: 1 the signs given (the true ones), -1 the WRONG ones given as known (a bad probe kept from an earlier DOWN) */
static int Fly(const Start* s, int sr, int sp, int kind, int known, int pauseInProbe, int quiet)
{
    DownCtl c;
    DownInit(&c, 0, 0, s->alt, s->R, known != 0, known ? known * sr : 1, known ? known * sp : 1);
    Model m = { s->x, s->y, s->z, s->th, s->ps, s->ph, 0, 0 };
    const double dt = 1.0 / 60.0;
    double t = 100.0, sumR = 0, sumH = 0, maxBank = 0, minZ = 1e9;
    int n = 0, flipsAt = -1;
    static float late[64][5];                             /* kind 3's inputs, handed over 24 frames (0.4 s) late */
    static const float none[5] = { 0, 0, 0, 0, 0 };
    for (int k = 0; k < (int)(200.0 / dt); ++k) {
        if (pauseInProbe && k == 100) t += 1.5;           /* a pause in the roll probe: the probe starts over */
        double pos[3] = { m.x * 100, m.y * 100, m.z * 100 }, rot[3] = { m.th, m.ps, m.ph };
        float out[5], again[5];
        DownStep(&c, t, pos, rot, out);
        DownStep(&c, t + 0.0004, pos, rot, again);        /* BuildFlightInput's second call in the frame */
        if (memcmp(out, again, sizeof(out))) { printf("FAILED: a second call in the frame changed the inputs\n"); g_fail = 1; return 0; }
        const float* in = out;
        if (kind == 3) { memcpy(late[k % 64], out, sizeof(out)); in = k >= 24 ? late[(k - 24) % 64] : none; }
        ModelStep(&m, in, sr, sp, kind, dt);
        if (c.flips && flipsAt < 0) flipsAt = k;
        t += dt;
        if (m.z < minZ) minZ = m.z;
        if (k * dt >= 150.0) {
            sumR += fabs(sqrt(m.x * m.x + m.y * m.y) - s->R); sumH += fabs(m.z - s->alt); ++n;
            if (fabs(m.ph) > maxBank) maxBank = fabs(m.ph);
        }
    }
    double eR = sumR / n, eH = sumH / n;
    /* (a plane that answers on time, its signs learned by the probe or given right: the in-flight check never flips one;
     * wrong signs given: flipped back within 30 s) */
    int flipsOk = kind == 3 || pauseInProbe ? 1 : known < 0 ? (c.flips >= 1 && flipsAt >= 0 && flipsAt * dt < 30.0) : c.flips == 0;
    int ok = c.phase == DN_CIRCLE && c.sRoll == sr && c.sPitch == sp && eR < 0.3 * s->R && eH < 120.0 && maxBank < 70.0 && flipsOk;
    if (!quiet || !ok)
        printf("%s %s, signs roll %+d pitch %+d%s%s: now %+d %+d (probes %.0f/%.0f, %.0f/%.0f deg/s; %d flips); last 50 s: %.0f m "
               "off the %.0f m circle, %.0f m off %.0f m, bank up to %.0f deg; lowest %.0f m: %s\n", s->name,
               kind == 1 ? "bank-angle roll" : kind == 2 ? "quick plane" : kind == 3 ? "late plane" : "rate roll", sr, sp,
               known > 0 ? ", signs known" : known < 0 ? ", WRONG signs known" : "", pauseInProbe ? ", paused in a probe" : "",
               c.sRoll, c.sPitch, c.probeRate[0], c.probeRate[1], c.probeRate[2], c.probeRate[3], c.flips,
               eR, s->R, eH, s->alt, maxBank, minZ, ok ? "ok" : "FAILED");
    if (c.flips && (!quiet || !ok)) printf("    (first flip %.1f s in)\n", flipsAt * dt);
    if (!ok) g_fail = 1;
    return ok;
}

int main(void)
{
    FlagsTest();
    g_quiet = 1;
    static const Start starts[] = {
        { "far, flying away", 9000, 0, 1200, 0, 0, 0, 2000, 2500 },
        { "near, inverted dive", 300, -200, 2500, 135, -20, 120, 1500, 2200 },
        { "beside, climbing", -2000, 2600, 800, -60, 25, -30, 3000, 4000 },
    };
    int runs = 0, good = 0;
    for (int st = 0; st < 3; ++st)
        for (int att = 0; att < 2; ++att)
            for (int sr = -1; sr <= 1; sr += 2)
                for (int sp = -1; sp <= 1; sp += 2) { ++runs; good += Fly(&starts[st], sr, sp, att, 0, 0, 0); }
    for (int st = 0; st < 2; ++st)
        for (int sr = -1; sr <= 1; sr += 2)
            for (int sp = -1; sp <= 1; sp += 2) { ++runs; good += Fly(&starts[st], sr, sp, 2, 0, 0, 0); }
    ++runs; good += Fly(&starts[0], -1, 1, 0, 0, 1, 0);     /* a pause in a probe */
    ++runs; good += Fly(&starts[1], 1, -1, 0, 1, 0, 0);     /* the signs known: circling at once */
    /* the late plane, every pair of signs from each start; and wrong signs kept as known (rate roll and the late plane) */
    for (int st = 0; st < 3; ++st)
        for (int sr = -1; sr <= 1; sr += 2)
            for (int sp = -1; sp <= 1; sp += 2) { ++runs; good += Fly(&starts[st], sr, sp, 3, 0, 0, 0); }
    for (int kind = 0; kind <= 3; kind += 3)
        for (int st = 0; st < 3; ++st)
            for (int sr = -1; sr <= 1; sr += 2) { ++runs; good += Fly(&starts[st], sr, 1, kind, -1, 0, 0); }
    printf("down: %d of %d flights ok\n", good, runs);
    printf(g_fail ? "flight test: FAILED\n" : "flight test: passed\n");
    return g_fail ? 1 : 0;
}
