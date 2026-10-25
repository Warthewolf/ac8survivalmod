/* coop_test.c : runtime/coop.c (Survival COOP's transport, reliable channel, streams and interpolation) run outside the
 * game, as two processes over localhost UDP with 20 % of the packets dropped:
 *     coop_test host   &   coop_test join
 * The host flies a fake plane in a circle (its own stream), tracks a fake enemy flying a line, and sends 120 numbered
 * reliable messages; the joiner drives its fake puppets with them. The joiner checks every message arrived once, in
 * order, and how far its puppets sit from the true paths at their render time. Built by tools/checks/coop_test.sh. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

/* ---- what coop.c takes from survival_rt.c ---- */
#define RF_NOT_LIVE (0x10 | 0x20 | 0x8000 | 0x10000 | 0x40000000)
typedef struct { const char* p; size_t n; } StrView;
static int g_drop = 20;
static int CoTestDrop(void) { return (rand() % 100) < g_drop; }
static void Log(const wchar_t* fmt, ...)
{
    va_list ap; va_start(ap, fmt);
    wchar_t buf[1024]; _vsnwprintf(buf, 1023, fmt, ap); buf[1023] = 0;
    va_end(ap);
    wprintf(L"  [log] %ls\n", buf);
}
static int Readable(const void* p, size_t n) { (void)n; return p != NULL; }
static int LiveObject(void* o) { return o && !(*(uint32_t*)((uint8_t*)o + 8) & RF_NOT_LIVE); }
static double Sin(double x) { return sin(x); }
static double Cos(double x) { return cos(x); }

/* a fake Lua stack: arguments popped from the front, the last return kept */
typedef struct { int n, at; int isNum[8]; double num[8]; const char* str[8]; int64_t retI; char retS[1200]; size_t retN; int retIsS; } FakeLua;
static int32_t FL_size(void* l) { FakeLua* f = l; return f->n - f->at; }
static uint8_t FL_isS(void* l, int32_t i) { FakeLua* f = l; (void)i; return f->at < f->n && !f->isNum[f->at]; }
static uint8_t FL_isN(void* l, int32_t i) { FakeLua* f = l; (void)i; return f->at < f->n && f->isNum[f->at]; }
static StrView* FL_getS(void* l, StrView* out, int32_t i) { FakeLua* f = l; (void)i; out->p = f->str[f->at]; out->n = strlen(f->str[f->at]); f->at++; return out; }
static double FL_getN(void* l, int32_t i) { FakeLua* f = l; (void)i; return f->num[f->at++]; }
static void FL_setI(void* l, int64_t v) { FakeLua* f = l; f->retI = v; f->retIsS = 0; }
static void FL_setS(void* l, const char* s, size_t n) { FakeLua* f = l; memcpy(f->retS, s, n); f->retS[n] = 0; f->retN = n; f->retIsS = 1; }

/* fake objects: 0x1000 bytes, vtable +0, flags +8, index +0xC, name +0x18; the plane's RootComponent pointer +0x1a0, the
 * root's RelativeLocation +0x120 / RelativeRotation +0x138, HealthInternal +0xda8, MaxHealth +0x3b4 */
static void* FakeFindObject(const wchar_t* c, const wchar_t* n, int32_t r, int32_t b) { (void)c; (void)n; (void)r; (void)b; return NULL; }
static void* FakeValuePtr(void* obj, const wchar_t* prop)
{
    uint8_t* o = obj;
    if (!wcscmp(prop, L"RootComponent")) return o + 0x1a0;
    if (!wcscmp(prop, L"RelativeLocation")) return o + 0x120;
    if (!wcscmp(prop, L"RelativeRotation")) return o + 0x138;
    if (!wcscmp(prop, L"HealthInternal")) return o + 0xda8;
    if (!wcscmp(prop, L"MaxHealth")) return o + 0x3b4;
    return NULL;
}
static struct {
    void* (*findObject)(const wchar_t* cls, const wchar_t* name, int32_t required, int32_t banned);
    void* (*valuePtr)(void* obj, const wchar_t* prop);
    int32_t (*luaStackSize)(void*); uint8_t (*luaIsString)(void*, int32_t); uint8_t (*luaIsNumber)(void*, int32_t);
    StrView* (*luaGetString)(void*, StrView*, int32_t); double (*luaGetNumber)(void*, int32_t);
    void (*luaSetInteger)(void*, int64_t); void (*luaSetString)(void*, const char*, size_t);
} U = { FakeFindObject, FakeValuePtr, FL_size, FL_isS, FL_isN, FL_getS, FL_getN, FL_setI, FL_setS };
static int ResolveUE4SS(void) { return 1; }
/* (the second-player-plane probe's: never called here) */
#define VF_WORLD 0x31
typedef uint8_t (*DestroyActorFn)(void* actor, uint8_t netForce);
static DestroyActorFn g_destroyActor;
static void* VCall(void* obj, int slot) { (void)obj; (void)slot; return NULL; }
static int InGame(const void* p) { (void)p; return 0; }
static int ArgNumber(void* lua, double* v) { if (U.luaStackSize(lua) < 1 || !U.luaIsNumber(lua, 1)) return 0; *v = U.luaGetNumber(lua, 1); return 1; }
static int Ret(void* lua, int64_t v) { U.luaSetInteger(lua, v); return 1; }

#define COOP_TEST 1
#include "../../runtime/coop.c"

/* ---- the fakes ---- */
static uint8_t* NewObj(uint32_t idx)
{
    uint8_t* o = calloc(1, 0x1000), *root = calloc(1, 0x1000);
    *(uint32_t*)(o + 0xC) = idx; *(uint64_t*)(o + 0x18) = 0x1000 + idx; *(uint32_t*)(root + 0xC) = idx + 100;
    *(uint8_t**)(o + 0x1a0) = root;
    *(int32_t*)(o + 0xda8) = 1000; *(float*)(o + 0x3b4) = 100.0f;
    return o;
}
static void SetPose(uint8_t* o, const double* p, const double* r)
{
    uint8_t* root = *(uint8_t**)(o + 0x1a0);
    memcpy(root + 0x120, p, 24); memcpy(root + 0x138, r, 24);
}
static void GetPose(uint8_t* o, double* p, double* r)
{
    uint8_t* root = *(uint8_t**)(o + 0x1a0);
    memcpy(p, root + 0x120, 24); memcpy(r, root + 0x138, 24);
}
static int g_teleports;
static uint8_t FakeTeleIn(void* self, const double* loc, const double* rot, uint8_t t, uint8_t nc)
{
    (void)t; (void)nc; ++g_teleports; SetPose(self, loc, rot); return 1;
}
static uint8_t FakeTeleTo(void* self, const double* loc, const double* rot, uint8_t t, uint8_t nc) { return FakeTeleIn(self, loc, rot, t, nc); }
static void* g_vt[400];

static int64_t CallI(int (*fn)(void*), FakeLua* f) { f->at = 0; fn(f); return f->retI; }
static void Args(FakeLua* f) { memset(f, 0, sizeof(*f)); }
static void ArgS(FakeLua* f, const char* s) { f->isNum[f->n] = 0; f->str[f->n++] = s; }
static void ArgN(FakeLua* f, double v) { f->isNum[f->n] = 1; f->num[f->n++] = v; }

/* the true paths: player <slot>'s plane on a 3 km circle at 200 m/s, a quarter turn apart and 100 m apart in height;
 * the host's enemy on a line at 250 m/s (cm, seconds, the shared clock) */
static void PlayerPath(int slot, double t, double* p, double* r)
{
    double w = 20000.0 / 300000.0, a = w * t + slot * CO_PI / 2;
    p[0] = 300000.0 * cos(a); p[1] = 300000.0 * sin(a); p[2] = 400000.0 + slot * 10000.0;
    r[0] = 5.0; r[1] = fmod(a * 180.0 / CO_PI + 90.0 + 540.0, 360.0) - 180.0; r[2] = 30.0;
}
static void EnemyPath(double t, double* p, double* r) { p[0] = 2500000.0 * sin(t * 0.01); p[1] = -100000.0; p[2] = 300000.0; r[0] = 0; r[1] = 0; r[2] = 0; }
static double Dist(const double* a, const double* b) { return sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]) + (a[2] - b[2]) * (a[2] - b[2])) / 100.0; }

int main(int argc, char** argv)
{
    int host = argc > 1 && !strcmp(argv[1], "host");
    double runFor = argc > 2 ? atof(argv[2]) : 14.0;
    srand(host ? 11 : (unsigned)GetCurrentProcessId());
    for (int i = 0; i < 400; ++i) g_vt[i] = (void*)FakeTeleIn;
    g_vt[VT_TELEPORT_TO] = (void*)FakeTeleTo; g_vt[VT_TELEPORT_IN] = (void*)FakeTeleIn;
    g_fAITeleportTo = (uint8_t*)FakeTeleTo; g_fAITeleportInner = (uint8_t*)FakeTeleIn;
    FakeLua f;
    Args(&f); ArgS(&f, "udp"); ArgS(&f, host ? "host" : "join"); ArgS(&f, host ? "auto" : "127.0.0.1:27791");
    ArgN(&f, 27791); ArgN(&f, 100); ArgS(&f, "test"); ArgN(&f, 4);
    int64_t r = CallI(L_CoopOpen, &f);
    const char* who = host ? "host" : "join";
    printf("%s: open %lld, nonce %08x\n", who, (long long)r, CO.nonce);
    if (r != 1) return 1;
    uint8_t* me = NewObj(1), *enemy = NewObj(2), *copy = NewObj(4), *pup[CO_MAX_PLAYERS];
    for (int s = 0; s < CO_MAX_PLAYERS; ++s) { pup[s] = NewObj(10 + s); *(void***)pup[s] = g_vt; }
    *(void***)copy = g_vt;
    double t0 = CoNow(), p[3], rot[3];
    int sentRel = 0, order = 1, gotRel = 0, bound = 0, frames = 0, sentUp = 0, fromJoin[CO_MAX_PLAYERS] = { 0 };
    double eSum[CO_MAX_PLAYERS] = { 0 }, eMax[CO_MAX_PLAYERS] = { 0 }, enSum = 0, enMax = 0;
    int eN[CO_MAX_PLAYERS] = { 0 }, enN = 0;
    while (CoNow() - t0 < runFor) {
        double t = CoNow();
        if (CO.mySlot >= 0) {                                 /* (a joiner flies its path once it knows its slot) */
            PlayerPath(CO.mySlot, t, p, rot); SetPose(me, p, rot);
            Args(&f); ArgN(&f, (double)(uintptr_t)me); ArgN(&f, 3); CallI(L_CoopMe, &f);
        }
        EnemyPath(t, p, rot); SetPose(enemy, p, rot);
        int linked = 0;
        for (int k = 0; k < CO_MAX_PLAYERS; ++k) if (CO.links[k].used) ++linked;
        if (host) {
            if (frames == 10) { Args(&f); ArgN(&f, 7); ArgN(&f, (double)(uintptr_t)enemy); CallI(L_CoopTrack, &f); }
            if (linked == 3 && sentRel < 120) {               /* (once all three are in) */
                char m[32]; sprintf(m, "m|%d", ++sentRel);
                Args(&f); ArgS(&f, m); ArgN(&f, 1); ArgN(&f, -1); CallI(L_CoopSend, &f);
            }
        } else {
            if (CO.mySlot >= 0 && !bound) {
                for (int s = 0; s < CO_MAX_PLAYERS; ++s) if (s != CO.mySlot) { Args(&f); ArgN(&f, s); ArgN(&f, (double)(uintptr_t)pup[s]); CallI(L_CoopPeer, &f); }
                Args(&f); ArgN(&f, 7); ArgN(&f, (double)(uintptr_t)copy); CallI(L_CoopBind, &f);
                printf("join: I am player %d; bound the other three and the enemy\n", CO.mySlot + 1); bound = 1;
            }
            if (bound && sentUp < 40 && frames % 2 == 0) {     /* (40 messages up to the host) */
                char m[32]; sprintf(m, "j|%d", ++sentUp);
                Args(&f); ArgS(&f, m); ArgN(&f, 1); CallI(L_CoopSend, &f);
            }
        }
        CoopFrame(1);
        for (;;) {
            Args(&f); f.at = 0; L_CoopRecv(&f);
            if (!f.retN) break;
            int from = f.retS[0] - '0';
            const char* m = f.retS + 2;
            if (!strncmp(m, "m|", 2)) { int k = atoi(m + 2); ++gotRel; if (k != order) printf("join: OUT OF ORDER: got %d, wanted %d\n", k, order); order = k + 1; }
            else if (!strncmp(m, "j|", 2)) { if (from >= 0 && from < CO_MAX_PLAYERS) ++fromJoin[from]; }
            else printf("%s: %s\n", who, f.retS);
        }
        if (!host && bound && t - t0 > 3.0 && CoNow() - CO.players[0].plane.lastRecv < 0.2) {
            for (int s = 0; s < CO_MAX_PLAYERS; ++s) {
                CoPlayer* P = &CO.players[s];
                if (s == CO.mySlot || !P->haveOffset || P->plane.ns < 4 || CoNow() - P->plane.lastRecv > 0.2) continue;
                double want[3], wr[3], got[3], gr[3];
                PlayerPath(s, CoNow() - P->offset - CO.delay, want, wr); GetPose(pup[s], got, gr);
                double e = Dist(want, got);
                eSum[s] += e; if (e > eMax[s]) eMax[s] = e; ++eN[s];
            }
            CoEnt* en = CoEntById(7, 0);
            if (!en || en->ns < 4) { ++frames; Sleep(16); continue; }   /* (its stream hasn't started yet) */
            double want[3], wr[3], got[3], gr[3];
            EnemyPath(CoNow() - CO.players[0].offset - CO.delay, want, wr); GetPose(copy, got, gr);
            want[2] = got[2];
            double e = Dist(want, got); enSum += e; if (e > enMax) enMax = e; ++enN;
        }
        ++frames;
        Sleep(16);
    }
    Args(&f); f.at = 0; L_CoopInfo(&f);
    printf("%s: info %s\n", who, f.retS);
    if (host) {
        int ok = 1;
        for (int k = 1; k < CO_MAX_PLAYERS; ++k) { printf("host: from player %d: %d of 40 messages\n", k + 1, fromJoin[k]); if (fromJoin[k] != 40) ok = 0; }
        return ok ? 0 : 2;
    }
    int ok = gotRel == 120 && order == 121 && enN > 0 && enSum / enN < 5.0;
    printf("join %d: reliable %d of 120 from the host, in order: %s\n", CO.mySlot + 1, gotRel, order == 121 ? "yes" : "NO");
    for (int s = 0; s < CO_MAX_PLAYERS; ++s) {
        if (s == CO.mySlot) continue;
        printf("join %d: player %d's plane%s: mean %.2f m, worst %.2f m off its true path (%d samples)\n", CO.mySlot + 1, s + 1,
               s == 0 ? " (the host)" : " (relayed)", eN[s] ? eSum[s] / eN[s] : -1.0, eMax[s], eN[s]);
        if (!eN[s] || eSum[s] / eN[s] > 5.0) ok = 0;
    }
    printf("join %d: the enemy copy: mean %.2f m, worst %.2f m\n", CO.mySlot + 1, enN ? enSum / enN : -1.0, enMax);
    return ok ? 0 : 2;
}
