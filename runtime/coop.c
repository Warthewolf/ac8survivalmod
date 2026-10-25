/* =============================================================================
 *  Survival COOP: the native half of co-op for up to 4 players (runtime 0.22.0; tools/re/COOP.md). Included by
 *  survival_rt.c.
 *
 *  Host-authoritative, after Double Trigger, the AC7 co-op mod (layer10-love/double-trigger, MIT / Unlicense): the
 *  host's game runs the rounds and the enemies, the joiners' games mirror them. A star: each joiner is linked to the
 *  host only (slot 0 = the host, 1..3 the joiners, given by the host), and the host relays every player's plane to
 *  the others. This file is the transport and the per-frame work; Scripts/sv_coop.lua decides what is mirrored.
 *
 *  Transport: Steam P2P (ISteamNetworking v006 through steam_api64's flat API: SendP2PPacket / ReadP2PPacket on a
 *  channel of our own, no callbacks: a session is accepted by sending to that user and AcceptP2PSessionWithUser), or
 *  UDP (ws2_32, loaded at run time: LAN or a VPN, the host listens on a port). Every packet starts with
 *  'S', CO_PROTO, a type and a flags byte:
 *    H hello (1 s): role, session nonce, time + echo of the link's last hello (the round trip), the slot the host
 *      gives that joiner (or none yet / full), max players, mod version, name
 *    L reliable Lua message: sender nonce, seq, length, bytes (per link: resent every 250 ms until acked, in order)
 *    K ack: sender nonce, every seq below this one arrived
 *    U unreliable Lua message
 *    P a player's own plane (30 Hz): slot, time, position (cm, doubles), rotation (quaternion), health, Lua's flags;
 *      the host sends its own and relays each joiner's to the other joiners
 *    E the host's tracked enemies (15 Hz): time, n x {id, position (floats), rotation (int16 quaternion)}
 *  Puppets: a local plane bound to a stream (another player's, or a host enemy on a joiner's game) is moved every
 *  frame to where the stream says it was CO_DELAY ago on its sender's clock (snapshot interpolation, nlerp), through
 *  the plane's own teleport (vtable slot 315: the flight model flies on from there, hard rule 39), late in the frame
 *  (the music player's tickable, after every actor's tick), so it draws where the stream puts it.
 *  All of it runs on the game thread: the Lua calls come from Survival's ExecuteInGameThread tick, the frame work from
 *  the music player's tick (OnMusicTick).
 * ============================================================================= */

#define CO_PROTO        2                   /* 2: up to 4 players (runtime 0.22.0); 1: two */
#define CO_MAX_PLAYERS  4
#define CO_MAGIC        0x53                /* 'S' */
#define CO_CHANNEL      1480                /* our Steam P2P channel (the game's own use 0..7)                      */
#define CO_MAX_PACKET   1200                /* Steam's limit for an unreliable P2P packet                           */
#define CO_MAX_LUA      1100                /* longest Lua message                                                  */
#define CO_MAX_ENTS     256                 /* streamed enemies (ids 1..65535; the table holds 256 at a time)       */
#define CO_SNAPS        12                  /* snapshots kept per stream                                            */
#define CO_RELIABLE     256                 /* reliable messages in flight                                          */
#define CO_OOO          64                  /* reliable messages held out of order                                  */
#define CO_INBOX        512                 /* Lua messages waiting for SV_CoopRecv                                  */
#define CO_LOST_S       6.0                 /* silent this long: the link is lost                                   */
#define CO_ROLE_HOST    1
#define CO_ROLE_JOIN    2
#define CO_MODE_STEAM   1
#define CO_MODE_UDP     2
#define VT_TELEPORT_TO  186                 /* AActor::TeleportTo: ALiveAIPlane's records a replay teleport          */
#define VT_TELEPORT_IN  315                 /* ALiveAIPlane's teleport + flight reset (sigs.h kSigAITeleportInner)   */

static uint8_t* g_fAITeleportTo;            /* found by FindFunctions (sigs.h)                                       */
static uint8_t* g_fAITeleportInner;
static uint8_t* g_fPPTeleportTo, *g_fPPTeleportInner;              /* the same pair on ALivePlayerPlane              */
static uint8_t* g_fSpawnPlayerPlane, *g_fWorldSpawnActor;          /* a second player plane (COOP.md 6)              */
static uint8_t* g_siteRemotePossess, *g_siteRemoteNetObj, *g_siteRemoteRole, *g_siteRemoteDummyCls;
static uint8_t* g_siteRemoteLoadout, *g_siteRemoteFlags, *g_siteRemoteFinish;

/* ---- clock and math ------------------------------------------------------------------------------------------- */
static int64_t g_qpcFreq;
static double CoNow(void)                    /* seconds */
{
    int64_t c = 0;
    if (!g_qpcFreq) QueryPerformanceFrequency(&g_qpcFreq);
    QueryPerformanceCounter(&c);
    return g_qpcFreq ? (double)c / (double)g_qpcFreq : (double)GetTickCount64() / 1000.0;
}

static double CoSqrt(double x) { if (x <= 0) return 0; double r; __asm__("sqrtsd %1, %0" : "=x"(r) : "x"(x)); return r; }
static double CoAbs(double x) { return x < 0 ? -x : x; }
#define CO_PI 3.14159265358979323846
static double CoAtan(double z)               /* |z| <= 1: minimax, < 1e-5 rad */
{
    double z2 = z * z;
    return z * (0.99997726 + z2 * (-0.33262347 + z2 * (0.19354346 + z2 * (-0.11643287 + z2 * (0.05265332 + z2 * -0.01172120)))));
}
static double CoAtan2(double y, double x)
{
    if (x == 0 && y == 0) return 0;
    double ax = CoAbs(x), ay = CoAbs(y), a;
    if (ax >= ay) a = CoAtan(ay / ax); else a = CO_PI / 2 - CoAtan(ax / ay);
    if (x < 0) a = CO_PI - a;
    return y < 0 ? -a : a;
}
static double CoAsin(double x) { if (x >= 1) return CO_PI / 2; if (x <= -1) return -CO_PI / 2; return CoAtan2(x, CoSqrt(1 - x * x)); }

/* UE's FRotator (degrees: pitch, yaw, roll) <-> FQuat (x, y, z, w), as FRotator::Quaternion / FQuat::Rotator do */
static void CoRotToQuat(const double* r, float* q)
{
    const double d = CO_PI / 360.0;
    double sp = Sin(r[0] * d), cp = Cos(r[0] * d), sy = Sin(r[1] * d), cy = Cos(r[1] * d), sr = Sin(r[2] * d), cr = Cos(r[2] * d);
    q[0] = (float)(cr * sp * sy - sr * cp * cy);
    q[1] = (float)(-cr * sp * cy - sr * cp * sy);
    q[2] = (float)(cr * cp * sy - sr * sp * cy);
    q[3] = (float)(cr * cp * cy + sr * sp * sy);
}
static double CoNormAxis(double a) { while (a > 180) a -= 360; while (a < -180) a += 360; return a; }
static void CoQuatToRot(const float* qf, double* r)
{
    double x = qf[0], y = qf[1], z = qf[2], w = qf[3];
    const double rd = 180.0 / CO_PI;
    double sing = z * x - w * y, yawY = 2 * (w * z + x * y), yawX = 1 - 2 * (y * y + z * z);
    if (sing < -0.4999995) {
        r[0] = -90; r[1] = CoAtan2(yawY, yawX) * rd; r[2] = CoNormAxis(-r[1] - 2 * CoAtan2(x, w) * rd);
    } else if (sing > 0.4999995) {
        r[0] = 90; r[1] = CoAtan2(yawY, yawX) * rd; r[2] = CoNormAxis(r[1] - 2 * CoAtan2(x, w) * rd);
    } else {
        r[0] = CoAsin(2 * sing) * rd; r[1] = CoAtan2(yawY, yawX) * rd;
        r[2] = CoAtan2(-2 * (w * x + y * z), 1 - 2 * (x * x + y * y)) * rd;
    }
}
static void CoNlerp(const float* a, const float* b, double t, float* out)
{
    double d = (double)a[0] * b[0] + (double)a[1] * b[1] + (double)a[2] * b[2] + (double)a[3] * b[3];
    double s = d < 0 ? -1.0 : 1.0, n = 0;
    double o[4];
    for (int i = 0; i < 4; ++i) { o[i] = a[i] * (1 - t) + b[i] * s * t; n += o[i] * o[i]; }
    n = CoSqrt(n);
    for (int i = 0; i < 4; ++i) out[i] = (float)(n > 1e-9 ? o[i] / n : a[i]);
}

/* ---- small text helpers (no C runtime) ------------------------------------------------------------------------ */
typedef struct { char* p; char* end; } CoBuf;
static void CoPutS(CoBuf* b, const char* s) { while (s && *s && b->p < b->end) *b->p++ = *s++; }
static void CoPutU(CoBuf* b, uint64_t v)
{
    char t[24]; int n = 0;
    do { t[n++] = (char)('0' + v % 10); v /= 10; } while (v && n < 23);
    while (n && b->p < b->end) *b->p++ = t[--n];
}
static void CoPutI(CoBuf* b, int64_t v) { if (v < 0) { CoPutS(b, "-"); CoPutU(b, (uint64_t)-v); } else CoPutU(b, (uint64_t)v); }
static void CoPutF(CoBuf* b, double v, int dec)         /* fixed point */
{
    if (v < 0) { CoPutS(b, "-"); v = -v; }
    uint64_t m = 1; for (int i = 0; i < dec; ++i) m *= 10;
    uint64_t x = (uint64_t)(v * (double)m + 0.5);
    CoPutU(b, x / m);
    if (dec) {
        CoPutS(b, ".");
        uint64_t f = x % m, k = m / 10;
        for (int i = 0; i < dec; ++i) { char c = (char)('0' + (f / (k ? k : 1)) % 10); if (b->p < b->end) *b->p++ = c; if (k) k /= 10; }
    }
}
static size_t CoLen(const char* s) { size_t n = 0; while (s && s[n]) ++n; return n; }
static void CoCopy(char* dst, size_t cap, const char* src, size_t n)
{
    if (!cap) return;
    if (n >= cap) n = cap - 1;
    for (size_t i = 0; i < n; ++i) dst[i] = src[i];
    dst[n] = 0;
}
static int CoIEq(const char* a, const char* b)             /* ASCII case-insensitive */
{
    for (;; ++a, ++b) {
        char x = *a, y = *b;
        if (x >= 'A' && x <= 'Z') x = (char)(x + 32);
        if (y >= 'A' && y <= 'Z') y = (char)(y + 32);
        if (x != y) return 0;
        if (!x) return 1;
    }
}
static void CoWide(const char* s, wchar_t* out, size_t cap)  /* ASCII-safe, for the log */
{
    size_t i = 0;
    for (; s && s[i] && i + 1 < cap; ++i) out[i] = (s[i] >= 0x20 && s[i] < 0x7F) ? (wchar_t)s[i] : L'?';
    out[i] = 0;
}

/* ---- Steam (steam_api64's flat API) ----------------------------------------------------------------------------- */
typedef struct { uint64_t gameId; uint32_t ip; uint16_t port, queryPort; uint64_t lobby; } CoFriendGame;   /* FriendGameInfo_t */
_Static_assert(sizeof(CoFriendGame) == 24, "FriendGameInfo_t layout");
static struct {
    int state;                              /* 0 not tried, 1 ok, -1 missing */
    void *net, *user, *friends, *utils;
    uint8_t     (*send)(void* net, uint64_t to, const void* data, uint32_t n, int32_t type, int32_t channel);
    uint8_t     (*avail)(void* net, uint32_t* size, int32_t channel);
    uint8_t     (*read)(void* net, void* buf, uint32_t cap, uint32_t* size, uint64_t* from, int32_t channel);
    uint8_t     (*accept)(void* net, uint64_t id);
    uint64_t    (*myId)(void* user);
    const char* (*myName)(void* friends);
    int32_t     (*friendCount)(void* friends, int32_t flags);
    uint64_t    (*friendAt)(void* friends, int32_t i, int32_t flags);
    const char* (*friendName)(void* friends, uint64_t id);
    uint8_t     (*friendGame)(void* friends, uint64_t id, CoFriendGame* info);
    uint32_t    (*appId)(void* utils);
} ST;

typedef void* (*CoGetIfaceFn)(void);
static void* CoIface(HANDLE dll, const char* const* names, int n)
{
    for (int i = 0; i < n; ++i) {
        CoGetIfaceFn f = (CoGetIfaceFn)GetProcAddress(dll, names[i]);
        void* p = f ? f() : NULL;
        if (p) return p;
    }
    return NULL;
}

static int CoSteamInit(void)
{
    if (ST.state) return ST.state > 0;
    ST.state = -1;
    HANDLE dll = GetModuleHandleW(L"steam_api64.dll");
    if (!dll) { Log(L"coop: steam_api64.dll is not loaded; Steam co-op is off"); return 0; }
    static const char* const kNet[] = { "SteamAPI_SteamNetworking_v006", "SteamAPI_SteamNetworking_v005" };
    static const char* const kUser[] = { "SteamAPI_SteamUser_v023", "SteamAPI_SteamUser_v022", "SteamAPI_SteamUser_v021", "SteamAPI_SteamUser_v020" };
    static const char* const kFriends[] = { "SteamAPI_SteamFriends_v017", "SteamAPI_SteamFriends_v018", "SteamAPI_SteamFriends_v016" };
    static const char* const kUtils[] = { "SteamAPI_SteamUtils_v010", "SteamAPI_SteamUtils_v009" };
    ST.net = CoIface(dll, kNet, 2);
    ST.user = CoIface(dll, kUser, 4);
    ST.friends = CoIface(dll, kFriends, 3);
    ST.utils = CoIface(dll, kUtils, 2);
    *(void**)&ST.send        = GetProcAddress(dll, "SteamAPI_ISteamNetworking_SendP2PPacket");
    *(void**)&ST.avail       = GetProcAddress(dll, "SteamAPI_ISteamNetworking_IsP2PPacketAvailable");
    *(void**)&ST.read        = GetProcAddress(dll, "SteamAPI_ISteamNetworking_ReadP2PPacket");
    *(void**)&ST.accept      = GetProcAddress(dll, "SteamAPI_ISteamNetworking_AcceptP2PSessionWithUser");
    *(void**)&ST.myId        = GetProcAddress(dll, "SteamAPI_ISteamUser_GetSteamID");
    *(void**)&ST.myName      = GetProcAddress(dll, "SteamAPI_ISteamFriends_GetPersonaName");
    *(void**)&ST.friendCount = GetProcAddress(dll, "SteamAPI_ISteamFriends_GetFriendCount");
    *(void**)&ST.friendAt    = GetProcAddress(dll, "SteamAPI_ISteamFriends_GetFriendByIndex");
    *(void**)&ST.friendName  = GetProcAddress(dll, "SteamAPI_ISteamFriends_GetFriendPersonaName");
    *(void**)&ST.friendGame  = GetProcAddress(dll, "SteamAPI_ISteamFriends_GetFriendGamePlayed");
    *(void**)&ST.appId       = GetProcAddress(dll, "SteamAPI_ISteamUtils_GetAppID");
    if (!ST.net || !ST.user || !ST.friends || !ST.send || !ST.avail || !ST.read || !ST.accept || !ST.myId || !ST.myName ||
        !ST.friendCount || !ST.friendAt || !ST.friendName || !ST.friendGame) {
        Log(L"coop: steam_api64.dll lacks an interface or export we need (networking %p, user %p, friends %p); Steam co-op is off",
            ST.net, ST.user, ST.friends);
        return 0;
    }
    ST.state = 1;
    return 1;
}

/* ---- UDP (ws2_32, loaded at run time) --------------------------------------------------------------------------- */
typedef struct { uint16_t family, port; uint32_t addr; uint8_t zero[8]; } CoSockAddr;   /* sockaddr_in */
_Static_assert(sizeof(CoSockAddr) == 16, "sockaddr_in layout");
static struct {
    int state;                              /* 0 not tried, 1 ok, -1 failed */
    uintptr_t sock;
    int32_t   (*startup)(uint16_t version, void* data);
    uintptr_t (*socket)(int32_t af, int32_t type, int32_t proto);
    int32_t   (*bind)(uintptr_t s, const void* addr, int32_t len);
    int32_t   (*sendto)(uintptr_t s, const char* buf, int32_t len, int32_t flags, const void* to, int32_t tolen);
    int32_t   (*recvfrom)(uintptr_t s, char* buf, int32_t len, int32_t flags, void* from, int32_t* fromlen);
    int32_t   (*ioctl)(uintptr_t s, int32_t cmd, uint32_t* arg);
    int32_t   (*closesocket)(uintptr_t s);
    int32_t   (*lastError)(void);
} WS;
static uint16_t CoBE16(uint16_t v) { return (uint16_t)((v >> 8) | (v << 8)); }

static int CoUdpOpen(uint16_t port)
{
    if (WS.state < 0) return 0;
    if (!WS.state) {
        HANDLE dll = LoadLibraryW(L"ws2_32.dll");
        if (dll) {
            *(void**)&WS.startup     = GetProcAddress(dll, "WSAStartup");
            *(void**)&WS.socket      = GetProcAddress(dll, "socket");
            *(void**)&WS.bind        = GetProcAddress(dll, "bind");
            *(void**)&WS.sendto      = GetProcAddress(dll, "sendto");
            *(void**)&WS.recvfrom    = GetProcAddress(dll, "recvfrom");
            *(void**)&WS.ioctl       = GetProcAddress(dll, "ioctlsocket");
            *(void**)&WS.closesocket = GetProcAddress(dll, "closesocket");
            *(void**)&WS.lastError   = GetProcAddress(dll, "WSAGetLastError");
        }
        static uint8_t wsadata[512];
        if (!dll || !WS.startup || !WS.socket || !WS.bind || !WS.sendto || !WS.recvfrom || !WS.ioctl || !WS.closesocket ||
            WS.startup(0x0202, wsadata) != 0) {
            WS.state = -1;
            Log(L"coop: ws2_32.dll not usable; UDP co-op is off");
            return 0;
        }
        WS.state = 1;
    }
    if (WS.sock) { WS.closesocket(WS.sock); WS.sock = 0; }
    uintptr_t s = WS.socket(2 /* AF_INET */, 2 /* SOCK_DGRAM */, 17 /* IPPROTO_UDP */);
    if (s == (uintptr_t)-1 || !s) { Log(L"coop: UDP socket failed (%d)", WS.lastError ? WS.lastError() : -1); return 0; }
    uint32_t nb = 1;
    WS.ioctl(s, (int32_t)0x8004667E /* FIONBIO */, &nb);
    CoSockAddr a; memset(&a, 0, sizeof(a));
    a.family = 2; a.port = CoBE16(port);
    if (WS.bind(s, &a, sizeof(a)) != 0) {
        Log(L"coop: UDP port %d is taken (%d); trying any port", (int32_t)port, WS.lastError ? WS.lastError() : -1);
        a.port = 0;
        if (WS.bind(s, &a, sizeof(a)) != 0) { WS.closesocket(s); return 0; }
    }
    WS.sock = s;
    return 1;
}

static int CoParseIp(const char* s, CoSockAddr* out, uint16_t defPort)  /* "a.b.c.d[:port]" */
{
    uint32_t parts[4] = { 0 }; int k = 0; uint32_t v = 0; int digits = 0; uint32_t port = defPort;
    for (const char* p = s;; ++p) {
        if (*p >= '0' && *p <= '9') { v = v * 10 + (uint32_t)(*p - '0'); if (++digits > 5) return 0; continue; }
        if (!digits || v > 255 || k > 3) return 0;
        parts[k++] = v; v = 0; digits = 0;
        if (*p == '.') continue;
        if (*p == ':') {
            port = 0; ++p;
            for (; *p >= '0' && *p <= '9'; ++p) port = port * 10 + (uint32_t)(*p - '0');
            if (*p || !port || port > 65535) return 0;
        } else if (*p) return 0;
        break;
    }
    if (k != 4) return 0;
    memset(out, 0, sizeof(*out));
    out->family = 2; out->port = CoBE16((uint16_t)port);
    out->addr = parts[0] | parts[1] << 8 | parts[2] << 16 | parts[3] << 24;
    return 1;
}

/* ---- session state ---------------------------------------------------------------------------------------------- */
typedef struct { uint32_t seq; uint16_t len; double sentAt; char* data; } CoOut;
typedef struct { uint8_t* obj; void* vt; uint32_t idx; uint64_t name; } CoRef;   /* a local actor, checked before use */
typedef struct { double t; double p[3]; float q[4]; } CoSnap;
typedef struct {
    uint16_t id; uint8_t used;
    CoRef    ref;                           /* the local actor this stream drives (joiner), or the one it reads (host) */
    CoSnap   s[CO_SNAPS]; int32_t ns;
    int32_t  drives, fails;
    double   lastRecv;
} CoEnt;

/* A link to another game: the host has one per joiner (index = that joiner's slot, 1..3), a joiner one to the host
 * (index 0). Each has its own reliable channel. */
typedef struct {
    int      used, connected;
    uint64_t steamId;
    CoSockAddr addr;
    uint32_t nonce;
    int      role;
    char     name[64], ver[32];
    double   lastRecv, lastHello, helloRecvAt, rtt;
    uint32_t helloRecvT;
    uint32_t sendSeq, ackedBelow, recvNext;
    int      ackDue;
    CoOut    out[CO_RELIABLE]; int32_t nout;
    char*    ooo[CO_OOO]; uint16_t oooLen[CO_OOO]; uint32_t oooSeq[CO_OOO];
    uint32_t txPk, rxPk, txB, rxB, resent;
} CoLink;

/* A player's plane as streamed (slot 0 the host, 1..3 the joiners): its snapshots on that player's clock and the
 * local puppet they move. A joiner gets the other joiners' planes relayed by the host. */
typedef struct {
    CoEnt    plane;
    double   offset; int haveOffset;        /* local time - that player's time: the smallest seen, let go of slowly */
    int32_t  hp; float maxHp; uint32_t flags; double stateAt;
} CoPlayer;

static struct {
    int      open, mode, role, maxPlayers, mySlot;   /* mySlot: the host 0, a joiner the one the host gave it (-1 before) */
    uint32_t nonce;
    char     partner[160];
    double   delay;                         /* interpolation delay, seconds */
    uint16_t port;
    double   lastDiscover, lastFrame, lastPlayerSend, lastEntSend, lastStats;
    uint64_t cand[16]; int32_t ncand;
    char     myVer[32], myName[64];
    uint64_t myId;
    CoLink   links[CO_MAX_PLAYERS];
    CoPlayer players[CO_MAX_PLAYERS];
    char*    inbox[CO_INBOX]; uint16_t inboxLen[CO_INBOX]; int32_t inHead, inCount;
    CoRef    me; uint32_t meFlags;
    CoEnt    ents[CO_MAX_ENTS];
    uint32_t badPk;
    int      warnedTele, fullSaid;
} CO;

/* reflected offsets, resolved once from the first object that has them */
static int32_t g_offRoot = -1, g_offRelLoc = -1, g_offRelRot = -1, g_offHealth = -1, g_offMaxHealth = -1;

static int CoRefSet(CoRef* r, uint8_t* obj)
{
    memset(r, 0, sizeof(*r));
    if (!obj || !LiveObject(obj)) return 0;
    r->obj = obj; r->vt = *(void**)obj; r->idx = *(uint32_t*)(obj + 0xC); r->name = *(uint64_t*)(obj + 0x18);
    return 1;
}
static uint8_t* CoRefGet(const CoRef* r)               /* the actor if it is still the same live object */
{
    uint8_t* o = r->obj;
    if (!o || !Readable(o, 0x28) || *(void**)o != r->vt || *(uint32_t*)(o + 0xC) != r->idx || *(uint64_t*)(o + 0x18) != r->name) return NULL;
    return (*(uint32_t*)(o + 8) & RF_NOT_LIVE) ? NULL : o;
}

static int CoResolve(uint8_t* obj)
{
    if (g_offRoot >= 0 && g_offRelLoc >= 0 && g_offRelRot >= 0) return 1;
    if (!ResolveUE4SS()) return 0;
    uint8_t* v = (uint8_t*)U.valuePtr(obj, L"RootComponent");
    if (!v || v < obj || v - obj > 0x4000) return 0;
    uint8_t* root = *(uint8_t**)v;
    if (!root || !LiveObject(root)) return 0;
    uint8_t* l = (uint8_t*)U.valuePtr(root, L"RelativeLocation");
    uint8_t* r = (uint8_t*)U.valuePtr(root, L"RelativeRotation");
    if (!l || !r || l < root || r < root || l - root > 0x2000 || r - root > 0x2000) return 0;
    uint8_t* h = (uint8_t*)U.valuePtr(obj, L"HealthInternal");
    uint8_t* m = (uint8_t*)U.valuePtr(obj, L"MaxHealth");
    g_offRoot = (int32_t)(v - obj); g_offRelLoc = (int32_t)(l - root); g_offRelRot = (int32_t)(r - root);
    if (h && h > obj && h - obj < 0x4000) g_offHealth = (int32_t)(h - obj);
    if (m && m > obj && m - obj < 0x4000) g_offMaxHealth = (int32_t)(m - obj);
    Log(L"coop: offsets: RootComponent +%x, RelativeLocation +%x, RelativeRotation +%x, HealthInternal +%x, MaxHealth +%x",
        (uint32_t)g_offRoot, (uint32_t)g_offRelLoc, (uint32_t)g_offRelRot, (uint32_t)g_offHealth, (uint32_t)g_offMaxHealth);
    return 1;
}

static int CoReadPose(uint8_t* obj, double* p, double* rot)
{
    if (!CoResolve(obj) || !Readable(obj + g_offRoot, 8)) return 0;
    uint8_t* root = *(uint8_t**)(obj + g_offRoot);
    if (!root || !LiveObject(root) || !Readable(root + g_offRelLoc, 24) || !Readable(root + g_offRelRot, 24)) return 0;
    memcpy(p, root + g_offRelLoc, 24);
    memcpy(rot, root + g_offRelRot, 24);
    return 1;
}

static int32_t CoHealth(uint8_t* obj) { return g_offHealth >= 0 && Readable(obj + g_offHealth, 4) ? *(int32_t*)(obj + g_offHealth) : 1; }

/* AActor::FinishSpawning (from the remote spawn's call to it) and its bHasFinishedSpawning byte (bit 0, its first
 * test): an actor spawned deferred and never finished has no setup, and teleporting one crashed the game (a player
 * plane's weapons had no owner, test of 2026-10-25) */
static uint8_t* g_fFinishSpawning;
static int32_t  g_finishedOff = -1;
static int CoFinishSpawningFn(void)
{
    if (g_finishedOff >= 0) return g_finishedOff > 0;
    g_finishedOff = 0;
    uint8_t* s = g_siteRemoteFinish;
    if (!s || s[20] != 0xE8) return 0;
    uint8_t* f = s + 25 + *(int32_t*)(s + 21);
    if (!InGame(f) || f[0x28] != 0x0F || f[0x29] != 0xB6 || f[0x2a] != 0x41) return 0;          /* movzx eax, byte [rcx + d8] */
    g_fFinishSpawning = f; g_finishedOff = f[0x2b];
    return g_finishedOff > 0;
}

/* Whether obj is an AI plane or a player plane with the game's own teleport in both slots (anything else: never
 * teleported). */
static int CoKind(uint8_t* obj)                                         /* 1 an AI plane, 2 a player plane, 0 neither */
{
    if (!obj) return 0;
    void** vt = *(void***)obj;
    if (!Readable(vt, 8 * (VT_TELEPORT_IN + 1))) return 0;
    if (g_fAITeleportTo && g_fAITeleportInner && vt[VT_TELEPORT_TO] == (void*)g_fAITeleportTo && vt[VT_TELEPORT_IN] == (void*)g_fAITeleportInner) return 1;
    if (g_fPPTeleportTo && g_fPPTeleportInner && vt[VT_TELEPORT_TO] == (void*)g_fPPTeleportTo && vt[VT_TELEPORT_IN] == (void*)g_fPPTeleportInner) return 2;
    return 0;
}

static int CoCanDrive(uint8_t* obj)
{
    int k = CoKind(obj);
    if (k == 2 && (!CoFinishSpawningFn() || !(obj[g_finishedOff] & 1))) return 0;                /* a player plane: set up */
    return k != 0;
}

typedef uint8_t (*CoTeleportFn)(void* self, const double* loc, const double* rot, uint8_t isTest, uint8_t noCheck);
typedef void    (*CoFlightResetFn)(void* a, void* b, void* c);

/* A player plane's slot 315 is AActor::TeleportTo, then ProcessEvent(OnReposition), then on success its flight-model
 * reset 0x147d40830(plane + 0x1918, + 0x2268, + 0x1a38) and `word [plane + 0x1ad9] = 0`. Its OnReposition (vtable
 * +0x888 -> +0x9e0 = 0x147d506a0) resets the plane's look: mesh parts hidden and shown again (0x147d50710), weapons,
 * lock-ons. Every frame that made the formation copy flicker in and out (solo test of 2026-10-25, runtime 0.22.2), so a
 * player plane is moved with the same steps minus the event, all read from slot 315's own code. */
static CoTeleportFn    g_fActorTeleport;
static CoFlightResetFn g_fFlightReset;
static int32_t g_ppReset[3], g_ppResetWord = -1;
static int CoQuietSites(void)
{
    if (g_ppResetWord >= 0) return g_ppResetWord > 0;
    g_ppResetWord = 0;
    uint8_t* p = g_fPPTeleportInner;
    if (!p || p[0x1b] != 0xE8) return 0;
    uint8_t* tp = p + 0x20 + *(int32_t*)(p + 0x1c);                             /* call AActor::TeleportTo */
    uint8_t* a = g_fAITeleportInner;
    if (!InGame(tp) || !a || a[0x1b] != 0xE8 || a + 0x20 + *(int32_t*)(a + 0x1c) != tp) return 0;   /* the AI plane's too */
    if (p[0x4c] != 0x4C || p[0x4d] != 0x8D || p[0x4e] != 0x86 ||                   /* lea r8,  [rsi + d32] */
        p[0x53] != 0x48 || p[0x54] != 0x8D || p[0x55] != 0x96 ||                   /* lea rdx, [rsi + d32] */
        p[0x5a] != 0x48 || p[0x5b] != 0x8D || p[0x5c] != 0x8E ||                   /* lea rcx, [rsi + d32] */
        p[0x61] != 0xE8 || p[0x66] != 0xB0 || p[0x67] != 0x01 ||                   /* call reset; mov al, 1 */
        p[0x68] != 0x66 || p[0x69] != 0xC7 || p[0x6a] != 0x86 || p[0x6f] || p[0x70]) return 0;  /* mov word [rsi + d32], 0 */
    uint8_t* fr = p + 0x66 + *(int32_t*)(p + 0x62);
    if (!InGame(fr)) return 0;
    g_ppReset[0] = *(int32_t*)(p + 0x5d); g_ppReset[1] = *(int32_t*)(p + 0x56); g_ppReset[2] = *(int32_t*)(p + 0x4f);
    for (int i = 0; i < 3; ++i) if (g_ppReset[i] <= 0 || g_ppReset[i] >= 0x8000) return 0;
    int32_t w = *(int32_t*)(p + 0x6b);
    if (w <= 0 || w >= 0x8000) return 0;
    g_fActorTeleport = (CoTeleportFn)tp; g_fFlightReset = (CoFlightResetFn)fr; g_ppResetWord = w;
    Log(L"coop: player plane teleport without OnReposition: AActor::TeleportTo %p, flight reset %p (+%x +%x +%x), word +%x",
        tp, fr, (uint32_t)g_ppReset[0], (uint32_t)g_ppReset[1], (uint32_t)g_ppReset[2], (uint32_t)w);
    return 1;
}

/* Moves a plane CoCanDrive allowed: an AI plane through its slot 315 (as before), a player plane quietly (above) */
static uint8_t CoTeleport(uint8_t* o, const double* pos, const double* rot)
{
    if (CoKind(o) == 2 && CoQuietSites()) {
        if (!g_fActorTeleport(o, pos, rot, 0, 1)) return 0;
        g_fFlightReset(o + g_ppReset[0], o + g_ppReset[1], o + g_ppReset[2]);
        *(uint16_t*)(o + g_ppResetWord) = 0;
        return 1;
    }
    return ((CoTeleportFn)(*(void***)o)[VT_TELEPORT_IN])(o, pos, rot, 0, 1);
}

/* ---- packets ---------------------------------------------------------------------------------------------------- */
static void CoRawTo(uint64_t steamId, const CoSockAddr* udp, const uint8_t* data, uint32_t n, CoLink* L)
{
    if (n > CO_MAX_PACKET) return;
#ifdef COOP_TEST
    if (CoTestDrop()) return;                                 /* (tools/checks/coop_test.c: a lossy link) */
#endif
    int ok = 0;
    if (CO.mode == CO_MODE_STEAM && ST.state > 0) ok = ST.send(ST.net, steamId, data, n, 0 /* unreliable */, CO_CHANNEL);
    else if (CO.mode == CO_MODE_UDP && WS.sock && udp) ok = WS.sendto(WS.sock, (const char*)data, (int32_t)n, 0, udp, sizeof(*udp)) == (int32_t)n;
    if (ok && L) { ++L->txPk; L->txB += n; }
}
static void CoSendTo(int k, const uint8_t* data, uint32_t n)
{
    CoLink* L = &CO.links[k];
    if (L->used) CoRawTo(L->steamId, &L->addr, data, n, L);
}

static uint8_t* CoHeader(uint8_t* b, uint8_t type) { b[0] = CO_MAGIC; b[1] = CO_PROTO; b[2] = type; b[3] = 0; return b + 4; }
static void CoPut32(uint8_t** p, uint32_t v) { memcpy(*p, &v, 4); *p += 4; }
static void CoPut16(uint8_t** p, uint16_t v) { memcpy(*p, &v, 2); *p += 2; }
static uint32_t CoGet32(const uint8_t* p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint16_t CoGet16(const uint8_t* p) { uint16_t v; memcpy(&v, p, 2); return v; }
static uint32_t CoMs(double t) { return (uint32_t)(uint64_t)(t * 1000.0); }

#define CO_SLOT_NONE 0xFF                   /* hello's yourSlot: not given yet */
#define CO_SLOT_FULL 0xFE                   /* hello's yourSlot: the host has no room */

/* hello: role, nonce, time, echo of the link's last hello + its age, yourSlot, max players, version, name */
static void CoHelloTo(uint64_t steamId, const CoSockAddr* udp, CoLink* L, uint8_t yourSlot, double now)
{
    uint8_t b[160], *p = CoHeader(b, 'H');
    *p++ = (uint8_t)CO.role;
    CoPut32(&p, CO.nonce);
    CoPut32(&p, CoMs(now));
    CoPut32(&p, L ? L->helloRecvT : 0);
    CoPut32(&p, (L && L->helloRecvAt > 0) ? CoMs(now - L->helloRecvAt) : 0);
    *p++ = yourSlot;
    *p++ = (uint8_t)CO.maxPlayers;
    char ver[32] = { 0 }, name[64] = { 0 };
    CoCopy(ver, sizeof(ver), CO.myVer, CoLen(CO.myVer));
    CoCopy(name, sizeof(name), CO.myName, CoLen(CO.myName));
    memcpy(p, ver, 32); p += 32;
    memcpy(p, name, 64); p += 64;
    CoRawTo(steamId, udp, b, (uint32_t)(p - b), L);
}

static void CoInboxPush(int slot, const char* s, uint32_t n)
{
    if (CO.inCount >= CO_INBOX) { Log(L"coop: Lua inbox full; a message was dropped"); return; }
    char* m = (char*)malloc(n + 4);
    if (!m) return;
    m[0] = (char)('0' + (slot >= 0 && slot < 10 ? slot : 9)); m[1] = '|';  /* "<sender's slot>|<message>" */
    memcpy(m + 2, s, n); m[n + 2] = 0;
    int32_t at = (CO.inHead + CO.inCount) % CO_INBOX;
    CO.inbox[at] = m; CO.inboxLen[at] = (uint16_t)(n + 2); ++CO.inCount;
}
static void CoSys(int slot, const char* s) { CoInboxPush(slot, s, (uint32_t)CoLen(s)); }

static void CoLinkResetReliable(CoLink* L)
{
    for (int32_t i = 0; i < L->nout; ++i) free(L->out[i].data);
    L->nout = 0;
    for (int i = 0; i < CO_OOO; ++i) { if (L->ooo[i]) free(L->ooo[i]); L->ooo[i] = NULL; }
    L->sendSeq = 1; L->ackedBelow = 1; L->recvNext = 1; L->ackDue = 0;
}
static void CoLinkFree(int k)
{
    CoLinkResetReliable(&CO.links[k]);
    memset(&CO.links[k], 0, sizeof(CO.links[k]));
}

/* A player's stream starts over (a new link, a restart): its snapshots and clock go, its puppet stays bound. */
static void CoPlayerReset(int s)
{
    CO.players[s].plane.ns = 0;
    CO.players[s].haveOffset = 0;
    CO.players[s].stateAt = 0;
}
static void CoEntsReset(void)                             /* the host's enemies' streams: snapshots go, bindings stay */
{
    for (int i = 0; i < CO_MAX_ENTS; ++i) {
        CO.ents[i].ns = 0;
        if (CO.ents[i].used && !CO.ents[i].ref.obj) memset(&CO.ents[i], 0, sizeof(CO.ents[i]));
    }
}

static void CoSendLua(int k, const char* s, uint32_t n, int reliable)
{
    CoLink* L = &CO.links[k];
    if (!L->used) return;
    if (n > CO_MAX_LUA) n = CO_MAX_LUA;
    if (!reliable) {
        uint8_t b[CO_MAX_PACKET], *p = CoHeader(b, 'U');
        CoPut16(&p, (uint16_t)n); memcpy(p, s, n); p += n;
        CoSendTo(k, b, (uint32_t)(p - b));
        return;
    }
    if (L->nout >= CO_RELIABLE) { Log(L"coop: reliable queue to player %d full; a message was dropped", k); return; }
    char* d = (char*)malloc(n ? n : 1);
    if (!d) return;
    memcpy(d, s, n);
    L->out[L->nout++] = (CoOut){ L->sendSeq++, (uint16_t)n, -1.0, d };
}

static void CoFlushReliable(int k, double now)
{
    CoLink* L = &CO.links[k];
    int sent = 0;
    for (int32_t i = 0; i < L->nout && sent < 16; ++i) {
        CoOut* o = &L->out[i];
        if (o->sentAt >= 0 && now - o->sentAt < 0.25) continue;
        if (o->sentAt >= 0) ++L->resent;
        uint8_t b[CO_MAX_PACKET], *p = CoHeader(b, 'L');
        CoPut32(&p, CO.nonce); CoPut32(&p, o->seq); CoPut16(&p, o->len);
        memcpy(p, o->data, o->len); p += o->len;
        CoSendTo(k, b, (uint32_t)(p - b));
        o->sentAt = now; ++sent;
    }
    if (L->ackDue) {
        uint8_t b[16], *p = CoHeader(b, 'K');
        CoPut32(&p, CO.nonce); CoPut32(&p, L->recvNext);
        CoSendTo(k, b, (uint32_t)(p - b));
        L->ackDue = 0;
    }
}

static void CoOnAck(CoLink* L, uint32_t below)
{
    int32_t j = 0;
    for (int32_t i = 0; i < L->nout; ++i) {
        if (L->out[i].seq < below) free(L->out[i].data); else L->out[j++] = L->out[i];
    }
    L->nout = j;
    if (below > L->ackedBelow) L->ackedBelow = below;
}

static void CoOnReliable(int k, uint32_t seq, const char* d, uint16_t n)
{
    CoLink* L = &CO.links[k];
    L->ackDue = 1;
    if (seq < L->recvNext) return;                            /* a resend of one we have */
    if (seq != L->recvNext) {
        if (seq - L->recvNext >= CO_OOO) return;               /* too far ahead: it comes again */
        int slot = (int)(seq % CO_OOO);
        if (!L->ooo[slot]) {
            L->ooo[slot] = (char*)malloc(n ? n : 1);
            if (L->ooo[slot]) { memcpy(L->ooo[slot], d, n); L->oooLen[slot] = n; L->oooSeq[slot] = seq; }
        }
        return;
    }
    CoInboxPush(k, d, n); ++L->recvNext;
    for (;;) {
        int slot = (int)(L->recvNext % CO_OOO);
        if (!L->ooo[slot] || L->oooSeq[slot] != L->recvNext) break;
        CoInboxPush(k, L->ooo[slot], L->oooLen[slot]);
        free(L->ooo[slot]); L->ooo[slot] = NULL; ++L->recvNext;
    }
}

static void CoPushSnap(CoEnt* e, double t, const double* p, const float* q, double now)
{
    if (e->ns && t <= e->s[e->ns - 1].t) return;              /* old or repeated */
    if (e->ns == CO_SNAPS) { memcpy(&e->s[0], &e->s[1], sizeof(CoSnap) * (CO_SNAPS - 1)); --e->ns; }
    CoSnap* s = &e->s[e->ns++];
    s->t = t; memcpy(s->p, p, 24); memcpy(s->q, q, 16);
    e->lastRecv = now;
}

static void CoTrackOffset(CoPlayer* P, double senderT, double now)
{
    double est = now - senderT;
    if (!P->haveOffset || est < P->offset) { P->offset = est; P->haveOffset = 1; }
    else P->offset += (est - P->offset) * 0.001;              /* let go slowly (clock drift, a slower route) */
}

static double CoPeerTime(uint32_t ms) { return (double)ms / 1000.0; }

static CoEnt* CoEntById(uint16_t id, int make)
{
    CoEnt* free_ = NULL, *stale = NULL;
    double now = CoNow();
    for (int i = 0; i < CO_MAX_ENTS; ++i) {
        CoEnt* e = &CO.ents[i];
        if (e->used && e->id == id) return e;
        if (!e->used) { if (!free_) free_ = e; }
        else if (!e->ref.obj && now - e->lastRecv > 3.0 && (!stale || e->lastRecv < stale->lastRecv)) stale = e;
    }
    if (!free_) free_ = stale;                                /* (an unbound stream the host stopped sending: reused) */
    if (!make || !free_) return NULL;
    memset(free_, 0, sizeof(*free_));
    free_->used = 1; free_->id = id;
    return free_;
}

static int CoLinkOf(uint64_t steamId, const CoSockAddr* udp)
{
    for (int k = 0; k < CO_MAX_PLAYERS; ++k) {
        CoLink* L = &CO.links[k];
        if (!L->used) continue;
        if (CO.mode == CO_MODE_STEAM ? L->steamId == steamId
                                     : (udp && L->addr.addr == udp->addr && L->addr.port == udp->port)) return k;
    }
    return -1;
}

static void CoLinkOpen(int k, uint64_t steamId, const CoSockAddr* udp, int role, uint32_t nonce, const char* ver,
                       const char* name, double now)
{
    CoLink* L = &CO.links[k];
    CoLinkFree(k);
    L->used = 1; L->steamId = steamId; if (udp) L->addr = *udp;
    L->role = role; L->nonce = nonce; L->lastRecv = now;
    CoCopy(L->ver, sizeof(L->ver), ver, CoLen(ver));
    CoCopy(L->name, sizeof(L->name), name, CoLen(name));
    CoLinkResetReliable(L);
    CoPlayerReset(k);
    wchar_t wn[64], wv[32];
    CoWide(name, wn, 64); CoWide(ver, wv, 32);
    Log(L"coop: %s %s (%s, mod %s) as player %d", CO.role == CO_ROLE_HOST ? L"joined:" : L"paired with", wn,
        role == CO_ROLE_HOST ? L"host" : L"joiner", wv, k + 1);
    CoSys(k, CO.role == CO_ROLE_HOST ? "sys|joined" : "sys|paired");
}

static void CoOnHello(const uint8_t* b, uint32_t n, uint64_t steamId, const CoSockAddr* udp, double now)
{
    if (n < 4 + 1 + 16 + 2 + 32 + 64) { ++CO.badPk; return; }
    const uint8_t* p = b + 4;
    int role = p[0];
    uint32_t nonce = CoGet32(p + 1), t = CoGet32(p + 5), echo = CoGet32(p + 9), echoAge = CoGet32(p + 13);
    uint8_t yourSlot = p[17];
    char ver[33], name[65];
    memcpy(ver, p + 19, 32); ver[32] = 0;
    memcpy(name, p + 51, 64); name[64] = 0;
    if (role != CO_ROLE_HOST && role != CO_ROLE_JOIN) return;
    int k = CoLinkOf(steamId, udp);
#ifdef COOP_TEST
    { static uint32_t last; if (nonce != last) { last = nonce; Log(L"test: hello from role %d nonce %x (link %d)", role, nonce, k); } }
#endif
    if (role == CO.role) {                                    /* (joiners hear each other looking for the host: ignored) */
        static double warned;
        if (k < 0 && CO.role == CO_ROLE_HOST && now - warned > 10) {
            warned = now;
            wchar_t wn[64]; CoWide(name, wn, 64);
            Log(L"coop: %s is also set up as the %s; one of you must be the host (config\\survival.ini [coop] role)", wn,
                role == CO_ROLE_HOST ? L"host" : L"joiner");
            CoSys(0, "sys|samerole");
        }
        return;
    }
    if (CO.role == CO_ROLE_HOST) {                            /* a joiner */
        if (k < 0) {
            for (int s = 1; s < CO.maxPlayers && k < 0; ++s) if (!CO.links[s].used) k = s;
            if (k < 0) {                                       /* no room: told so */
                CoHelloTo(steamId, udp, NULL, CO_SLOT_FULL, now);
                return;
            }
            CoLinkOpen(k, steamId, udp, role, nonce, ver, name, now);
        } else if (nonce != CO.links[k].nonce) {
            Log(L"coop: player %d's game started a new session (nonce %x -> %x); starting over with it", k + 1, CO.links[k].nonce, nonce);
            CO.links[k].nonce = nonce;
            CoLinkResetReliable(&CO.links[k]);
            CoPlayerReset(k);
            CoSys(k, "sys|restart");
        }
    } else {                                                  /* the host */
        if (yourSlot == CO_SLOT_FULL) {
            if (!CO.fullSaid) { CO.fullSaid = 1; Log(L"coop: the host's game is full (%d players)", (int32_t)p[18]); CoSys(0, "sys|full"); }
            return;
        }
        if (k < 0) {
            if (CO.links[0].used) return;                      /* another host: we have ours */
            CoLinkOpen(0, steamId, udp, role, nonce, ver, name, now);
            k = 0;
        } else if (nonce != CO.links[0].nonce) {
            Log(L"coop: the host's game started a new session (nonce %x -> %x); starting over", CO.links[0].nonce, nonce);
            CO.links[0].nonce = nonce;
            CoLinkResetReliable(&CO.links[0]);
            for (int s = 0; s < CO_MAX_PLAYERS; ++s) CoPlayerReset(s);
            CoEntsReset();
            CoSys(0, "sys|restart");
        }
        if (yourSlot < CO_MAX_PLAYERS && yourSlot != CO.mySlot) {
            CO.mySlot = yourSlot;
            Log(L"coop: you are player %d", (int32_t)yourSlot + 1);
            char m[24] = "sys|slot|0"; m[9] = (char)('0' + yourSlot);
            CoSys(0, m);
        }
    }
    CoLink* L = &CO.links[k];
    L->lastRecv = now;
    L->helloRecvT = t; L->helloRecvAt = now;
    if (echo) {
        double rtt = (double)(CoMs(now) - echo) / 1000.0 - (double)echoAge / 1000.0;
        if (rtt >= 0 && rtt < 5) L->rtt = L->rtt > 0 ? L->rtt * 0.8 + rtt * 0.2 : rtt;
    }
}

static void CoOnPlayer(int src, const uint8_t* p, double now)
{
    if (src < 0 || src >= CO_MAX_PLAYERS || src == CO.mySlot) return;
    CoPlayer* P = &CO.players[src];
    double t = CoPeerTime(CoGet32(p + 4)), pos[3]; float q[4];
    memcpy(pos, p + 8, 24); memcpy(q, p + 32, 16);
    CoTrackOffset(P, t, now);
    CoPushSnap(&P->plane, t, pos, q, now);
    memcpy(&P->hp, p + 48, 4); memcpy(&P->maxHp, p + 52, 4); P->flags = CoGet32(p + 56); P->stateAt = now;
}

#define CO_P_SIZE (4 + 60)                  /* 'P': slot, 3 spare, time, position, rotation, health, max health, flags */

static void CoOnPacket(const uint8_t* b, uint32_t n, uint64_t steamId, const CoSockAddr* udp, double now)
{
    if (n < 4 || b[0] != CO_MAGIC) { ++CO.badPk; return; }
    if (b[1] != CO_PROTO) {
        static double warned;
        if (now - warned > 10) { warned = now; Log(L"coop: another game's co-op protocol is %d, ours %d: install the same Survival COOP build", (int32_t)b[1], (int32_t)CO_PROTO); CoSys(0, "sys|protocol"); }
        return;
    }
    if (b[2] == 'H') { CoOnHello(b, n, steamId, udp, now); return; }
    int k = CoLinkOf(steamId, udp);
    if (k < 0) return;
    CoLink* L = &CO.links[k];
    ++L->rxPk; L->rxB += n;
    L->lastRecv = now;
    const uint8_t* p = b + 4;
    switch (b[2]) {
    case 'L':
        if (n < 14 || CoGet32(p) != L->nonce) return;
        if (10u + CoGet16(p + 8) > n - 4) { ++CO.badPk; return; }
        CoOnReliable(k, CoGet32(p + 4), (const char*)p + 10, CoGet16(p + 8));
        return;
    case 'K':
        if (n < 12 || CoGet32(p) != L->nonce) return;
        CoOnAck(L, CoGet32(p + 4));
        return;
    case 'U':
        if (n < 6 || 2u + CoGet16(p) > n - 4) { ++CO.badPk; return; }
        CoInboxPush(k, (const char*)p + 2, CoGet16(p));
        return;
    case 'P': {
        if (n < CO_P_SIZE) { ++CO.badPk; return; }
        int src = CO.role == CO_ROLE_HOST ? k : p[0];          /* the host knows a joiner by its link; a relayed one says */
        CoOnPlayer(src, p, now);
        if (CO.role == CO_ROLE_HOST) {                         /* relayed to the other joiners, as player k */
            uint8_t r[CO_P_SIZE];
            memcpy(r, b, CO_P_SIZE); r[4] = (uint8_t)k;
            for (int j = 1; j < CO_MAX_PLAYERS; ++j) if (j != k && CO.links[j].used) CoSendTo(j, r, CO_P_SIZE);
        }
        return;
    }
    case 'E': {
        if (CO.role != CO_ROLE_JOIN || k != 0) return;
        if (n < 10) { ++CO.badPk; return; }
        double t = CoPeerTime(CoGet32(p));
        uint32_t cnt = CoGet16(p + 4);
        if (10 + cnt * 22u > n) { ++CO.badPk; return; }
        CoTrackOffset(&CO.players[0], t, now);                 /* (the host's clock) */
        const uint8_t* e = p + 6;
        for (uint32_t i = 0; i < cnt; ++i, e += 22) {
            uint16_t id = CoGet16(e);
            float fp[3]; int16_t qi[4];
            memcpy(fp, e + 2, 12); memcpy(qi, e + 14, 8);
            double pos[3] = { fp[0], fp[1], fp[2] };
            float q[4] = { qi[0] / 32767.0f, qi[1] / 32767.0f, qi[2] / 32767.0f, qi[3] / 32767.0f };
            CoEnt* en = CoEntById(id, 1);
            if (en) CoPushSnap(en, t, pos, q, now);
        }
        return;
    }
    default: ++CO.badPk; return;
    }
}

static int CoKnown(uint64_t from)                         /* a Steam sender we talk to: linked, or one we asked */
{
    if (CoLinkOf(from, NULL) >= 0) return 1;
    for (int32_t c = 0; c < CO.ncand; ++c) if (CO.cand[c] == from) return 1;
    return 0;
}

static void CoPump(double now)
{
    uint8_t buf[CO_MAX_PACKET + 64];
    if (CO.mode == CO_MODE_STEAM && ST.state > 0) {
        uint32_t size = 0;
        for (int i = 0; i < 512 && ST.avail(ST.net, &size, CO_CHANNEL); ++i) {
            uint64_t from = 0; uint32_t got = 0;
            if (size > sizeof(buf)) {                       /* not ours: read it away */
                static uint8_t big[16384];
                ST.read(ST.net, big, sizeof(big), &got, &from, CO_CHANNEL);
                ++CO.badPk;
                continue;
            }
            if (!ST.read(ST.net, buf, sizeof(buf), &got, &from, CO_CHANNEL)) break;
            if (!CoKnown(from)) { ++CO.badPk; continue; }
            CoOnPacket(buf, got, from, NULL, now);
        }
    } else if (CO.mode == CO_MODE_UDP && WS.sock) {
        for (int i = 0; i < 512; ++i) {
            CoSockAddr from; int32_t fl = sizeof(from);
            int32_t got = WS.recvfrom(WS.sock, (char*)buf, (int32_t)sizeof(buf), 0, &from, &fl);
            if (got <= 0) break;
            CoOnPacket(buf, (uint32_t)got, 0, &from, now);
        }
    }
}

/* Steam: who to say hello to while there's room (the host) or no host yet (a joiner): the partners named in the ini
 * (Steam names or SteamID64s, comma-separated), or every friend in this game ("auto"). */
static void CoDiscover(double now)
{
    if (CO.mode == CO_MODE_UDP) {
        if (CO.role == CO_ROLE_JOIN && !CO.links[0].used && CO.links[0].addr.family) CoHelloTo(0, &CO.links[0].addr, NULL, CO_SLOT_NONE, now);
        return;
    }
    if (ST.state <= 0) return;
    CO.ncand = 0;
    int any = 0;
    char names[8][64]; uint64_t ids[8]; int nn = 0;
    for (const char* s = CO.partner; *s && nn < 8; ) {     /* the partner list */
        while (*s == ' ' || *s == ',') ++s;
        const char* e = s;
        while (*e && *e != ',') ++e;
        const char* t = e;
        while (t > s && t[-1] == ' ') --t;
        if (t > s) {
            CoCopy(names[nn], 64, s, (size_t)(t - s));
            uint64_t id = 0; int digits = 1;
            for (const char* c = names[nn]; *c; ++c) { if (*c < '0' || *c > '9') { digits = 0; break; } id = id * 10 + (uint64_t)(*c - '0'); }
            ids[nn] = digits && id > 0x0110000100000000ull ? id : 0;
            if (CoIEq(names[nn], "auto")) any = 1;
            ++nn;
        }
        s = e;
    }
    if (!nn) any = 1;
    for (int i = 0; i < nn && CO.ncand < 16; ++i) if (ids[i]) CO.cand[CO.ncand++] = ids[i];
    uint32_t app = ST.appId && ST.utils ? ST.appId(ST.utils) : 0;
    int32_t fc = ST.friendCount(ST.friends, 4 /* k_EFriendFlagImmediate */);
    for (int32_t i = 0; i < fc && CO.ncand < 16; ++i) {
        uint64_t f = ST.friendAt(ST.friends, i, 4);
        if (!f) continue;
        int want = 0;
        if (any) {
            CoFriendGame g; memset(&g, 0, sizeof(g));
            want = ST.friendGame(ST.friends, f, &g) && app && (uint32_t)(g.gameId & 0xFFFFFF) == app;
        }
        if (!want) {
            const char* nm = ST.friendName(ST.friends, f);
            for (int j = 0; j < nn && nm && !want; ++j) if (!ids[j] && CoIEq(nm, names[j])) want = 1;
        }
        if (want) CO.cand[CO.ncand++] = f;
    }
    for (int32_t c = 0; c < CO.ncand; ++c) {
        if (CoLinkOf(CO.cand[c], NULL) >= 0) continue;
        ST.accept(ST.net, CO.cand[c]);
        CoHelloTo(CO.cand[c], NULL, NULL, CO_SLOT_NONE, now);
    }
    static int32_t said = -1;
    if (said != CO.ncand) { said = CO.ncand; Log(L"coop: looking for players: %d Steam friend(s) to try", CO.ncand); }
}

static void CoSendPlayer(double now)
{
    uint8_t* me = CoRefGet(&CO.me);
    double pos[3], rot[3];
    if (!me || !CoReadPose(me, pos, rot)) return;
    float q[4]; CoRotToQuat(rot, q);
    int32_t hp = CoHealth(me);
    float maxHp = g_offMaxHealth >= 0 && Readable(me + g_offMaxHealth, 4) ? *(float*)(me + g_offMaxHealth) : 0.0f;
    uint8_t b[CO_P_SIZE], *p = CoHeader(b, 'P');
    *p++ = (uint8_t)(CO.mySlot >= 0 ? CO.mySlot : CO_SLOT_NONE); *p++ = 0; *p++ = 0; *p++ = 0;
    CoPut32(&p, CoMs(now));
    memcpy(p, pos, 24); p += 24;
    memcpy(p, q, 16); p += 16;
    memcpy(p, &hp, 4); p += 4;
    memcpy(p, &maxHp, 4); p += 4;
    CoPut32(&p, CO.meFlags);
    for (int k = 0; k < CO_MAX_PLAYERS; ++k) if (CO.links[k].used) CoSendTo(k, b, CO_P_SIZE);
}

static void CoSendEnts(double now)
{
    uint8_t b[CO_MAX_PACKET], *p = NULL, *countAt = NULL;
    uint16_t cnt = 0;
    for (int i = 0; i < CO_MAX_ENTS; ++i) {
        CoEnt* e = &CO.ents[i];
        if (!e->used || !e->ref.obj) continue;
        uint8_t* o = CoRefGet(&e->ref);
        double pos[3], rot[3];
        if (!o || !CoReadPose(o, pos, rot)) continue;
        if (!p) { p = CoHeader(b, 'E'); CoPut32(&p, CoMs(now)); countAt = p; p += 2; cnt = 0; }
        float q[4]; CoRotToQuat(rot, q);
        CoPut16(&p, e->id);
        float fp[3] = { (float)pos[0], (float)pos[1], (float)pos[2] };
        memcpy(p, fp, 12); p += 12;
        for (int c = 0; c < 4; ++c) { int16_t v = (int16_t)(q[c] * 32767.0f); memcpy(p, &v, 2); p += 2; }
        ++cnt;
        if ((size_t)(p - b) + 22 > CO_MAX_PACKET) {
            memcpy(countAt, &cnt, 2);
            for (int k = 1; k < CO_MAX_PLAYERS; ++k) if (CO.links[k].used) CoSendTo(k, b, (uint32_t)(p - b));
            p = NULL;
        }
    }
    if (p && cnt) {
        memcpy(countAt, &cnt, 2);
        for (int k = 1; k < CO_MAX_PLAYERS; ++k) if (CO.links[k].used) CoSendTo(k, b, (uint32_t)(p - b));
    }
}

/* where the stream was at render time rt (its sender's clock); 0 if it has nothing yet */
static int CoSample(const CoEnt* e, double rt, double* pos, float* q)
{
    if (!e->ns) return 0;
    const CoSnap* last = &e->s[e->ns - 1];
    if (rt >= last->t) {
        double ahead = rt - last->t;
        memcpy(pos, last->p, 24); memcpy(q, last->q, 16);
        if (e->ns >= 2 && ahead < 0.5) {                      /* a little past the newest: on along its velocity */
            const CoSnap* prev = &e->s[e->ns - 2];
            double dt = last->t - prev->t;
            if (dt > 0.001) for (int c = 0; c < 3; ++c) pos[c] += (last->p[c] - prev->p[c]) / dt * ahead;
        }
        return 1;
    }
    if (rt <= e->s[0].t) { memcpy(pos, e->s[0].p, 24); memcpy(q, e->s[0].q, 16); return 1; }
    for (int32_t i = e->ns - 2; i >= 0; --i) {
        const CoSnap* a = &e->s[i], *b = &e->s[i + 1];
        if (rt >= a->t) {
            double t = (rt - a->t) / (b->t - a->t);
            for (int c = 0; c < 3; ++c) pos[c] = a->p[c] + (b->p[c] - a->p[c]) * t;
            CoNlerp(a->q, b->q, t, q);
            return 1;
        }
    }
    return 0;
}

static void CoDriveOne(CoEnt* e, double rt)
{
    uint8_t* o = CoRefGet(&e->ref);
    if (!o) { if (e->ref.obj) { e->ref.obj = NULL; Log(L"coop: a puppet's actor is gone (stream %d); unbound", (int32_t)e->id); } return; }
    if (CoHealth(o) <= 0) return;                             /* going down: let it fall */
    double pos[3], rot[3]; float q[4];
    if (!CoSample(e, rt, pos, q)) return;
    CoQuatToRot(q, rot);
    if (CoTeleport(o, pos, rot)) ++e->drives; else ++e->fails;
}

static void CoDrive(double now)
{
    for (int s = 0; s < CO_MAX_PLAYERS; ++s) {
        CoPlayer* P = &CO.players[s];
        if (s != CO.mySlot && P->plane.ref.obj && P->haveOffset) CoDriveOne(&P->plane, now - P->offset - CO.delay);
    }
    if (CO.role != CO_ROLE_JOIN || !CO.players[0].haveOffset) return;
    double rt = now - CO.players[0].offset - CO.delay;        /* the host's enemies, on the host's clock */
    for (int i = 0; i < CO_MAX_ENTS; ++i) if (CO.ents[i].used && CO.ents[i].ref.obj) CoDriveOne(&CO.ents[i], rt);
}

#define CO_DROP_S 90.0                      /* lost this long: the link is let go (the slot is free again) */

static void CoStep(double now, int drive)
{
    CoPump(now);
    int anyFree = 0;
    for (int s = 1; s < CO.maxPlayers; ++s) if (!CO.links[s].used) anyFree = 1;
    int searching = CO.role == CO_ROLE_HOST ? anyFree : !CO.links[0].used;
    if (searching && now - CO.lastDiscover >= 2.0) { CO.lastDiscover = now; CoDiscover(now); }
    for (int k = 0; k < CO_MAX_PLAYERS; ++k) {
        CoLink* L = &CO.links[k];
        if (!L->used) continue;
        if (now - L->lastHello >= 1.0) {
            L->lastHello = now;
            if (CO.mode == CO_MODE_STEAM && ST.state > 0) ST.accept(ST.net, L->steamId);   /* (a restarted game asks again) */
            CoHelloTo(L->steamId, &L->addr, L, CO.role == CO_ROLE_HOST ? (uint8_t)k : CO_SLOT_NONE, now);
        }
        int up = now - L->lastRecv < CO_LOST_S;
        if (up != L->connected) {
            L->connected = up;
            Log(up ? L"coop: player %d: link up" : L"coop: player %d: link lost (nothing for %d s)", k + 1, (int32_t)CO_LOST_S);
            CoSys(k, up ? "sys|up" : "sys|lost");
        }
        if (!up && now - L->lastRecv > CO_DROP_S) {
            Log(L"coop: player %d gone (nothing for %d s); the slot is free", k + 1, (int32_t)CO_DROP_S);
            CoSys(k, "sys|left");
            CoLinkFree(k);
            CoPlayerReset(k);
            if (CO.role == CO_ROLE_JOIN) { CO.mySlot = -1; for (int s = 0; s < CO_MAX_PLAYERS; ++s) CoPlayerReset(s); CoEntsReset(); }
            continue;
        }
        CoFlushReliable(k, now);
    }
    int linked = 0;
    for (int k = 0; k < CO_MAX_PLAYERS; ++k) if (CO.links[k].used) linked = 1;
    if (linked) {
        if (now - CO.lastPlayerSend >= 1.0 / 30.0) { CO.lastPlayerSend = now; CoSendPlayer(now); }
        if (CO.role == CO_ROLE_HOST && now - CO.lastEntSend >= 1.0 / 15.0) { CO.lastEntSend = now; CoSendEnts(now); }
    }
    if (drive) CoDrive(now);
    if (now - CO.lastStats >= 60.0) {
        CO.lastStats = now;
        int32_t bound = 0, drives = 0, fails = 0;
        for (int i = 0; i < CO_MAX_ENTS; ++i) if (CO.ents[i].used && CO.ents[i].ref.obj) { ++bound; drives += CO.ents[i].drives; fails += CO.ents[i].fails; }
        Log(L"coop: you are player %d; %d enemy streams bound (%d moves, %d failed); %u bad packets", CO.mySlot + 1, bound, drives, fails, CO.badPk);
        for (int k = 0; k < CO_MAX_PLAYERS; ++k) {
            CoLink* L = &CO.links[k];
            if (!L->used) continue;
            wchar_t wn[64]; CoWide(L->name, wn, 64);
            Log(L"coop:   player %d %s: %s, rtt %d ms; sent %u packets (%u KB), got %u (%u KB), %u resent; their plane %d moves",
                k + 1, wn, L->connected ? L"linked" : L"link lost", (int32_t)(L->rtt * 1000), L->txPk, L->txB / 1024, L->rxPk,
                L->rxB / 1024, L->resent, CO.players[k].plane.drives);
        }
    }
}

/* The per-frame work, from the music player's tick (OnMusicTick: once per frame for each controller; the first
 * call in a frame does it) and as a fallback from the player's flight input. */
static void CoFollowFrame(int fromMusic);
static double g_coMusicAt;
static void CoopFrame(int fromMusic)
{
    CoFollowFrame(fromMusic);
    if (!CO.open) return;
    double now = CoNow();
    if (fromMusic) g_coMusicAt = now;
    else if (now - g_coMusicAt < 0.05) return;                /* the music tick runs: it's the later one in a frame */
    if (now - CO.lastFrame < 0.001) return;
    CO.lastFrame = now;
    CoStep(now, 1);
}

static void CoClose(void)
{
    if (!CO.open) return;
    for (int k = 0; k < CO_MAX_PLAYERS; ++k) CoLinkResetReliable(&CO.links[k]);
    for (int32_t i = 0; i < CO.inCount; ++i) free(CO.inbox[(CO.inHead + i) % CO_INBOX]);
    if (WS.sock) { WS.closesocket(WS.sock); WS.sock = 0; }
    memset(&CO, 0, sizeof(CO));
    Log(L"coop: closed");
}

/* ---- Lua ------------------------------------------------------------------------------------------------------- */
/* the next argument as raw bytes (any characters), popped */
static int ArgBytes(void* lua, char* out, size_t cap, size_t* len)
{
    if (U.luaStackSize(lua) < 1 || !U.luaIsString(lua, 1)) return 0;
    StrView sv = { NULL, 0 };
    U.luaGetString(lua, &sv, 1);
    size_t n = sv.p ? sv.n : 0;
    if (n >= cap) n = cap - 1;
    for (size_t i = 0; i < n; ++i) out[i] = sv.p[i];
    out[n] = 0;
    if (len) *len = n;
    return 1;
}
static uint8_t* ArgObject(void* lua)                       /* an address from Lua (obj:GetAddress()); 0 = none */
{
    double a = 0;
    if (!ArgNumber(lua, &a) || a <= 0) return NULL;
    return (uint8_t*)(uintptr_t)(uint64_t)a;
}

/* SV_CoopOpen(mode, role, partner, port, delayMs, version [, maxPlayers]) -> 1, or < 0: -1 bad args, -2 no Steam,
 * -3 no UDP, -4 bad host address. mode "steam" | "udp"; role "host" | "join"; partner: steam "auto" | Steam names or
 * SteamID64s, comma-separated; udp: the joiner's host "a.b.c.d[:port]" (the host listens on port). maxPlayers 2-4
 * (the host's; default 4). Opening again starts over. */
static int L_CoopOpen(void* lua)
{
    char mode[16], role[16], partner[160], ver[32];
    double port = 27777, delay = 100, maxp = CO_MAX_PLAYERS;
    if (!ArgBytes(lua, mode, sizeof(mode), NULL) || !ArgBytes(lua, role, sizeof(role), NULL) ||
        !ArgBytes(lua, partner, sizeof(partner), NULL)) return Ret(lua, -1);
    ArgNumber(lua, &port); ArgNumber(lua, &delay);
    if (!ArgBytes(lua, ver, sizeof(ver), NULL)) CoCopy(ver, sizeof(ver), "?", 1);
    ArgNumber(lua, &maxp);
    int m = CoIEq(mode, "udp") ? CO_MODE_UDP : CoIEq(mode, "steam") ? CO_MODE_STEAM : 0;
    int r = CoIEq(role, "host") ? CO_ROLE_HOST : (CoIEq(role, "join") || CoIEq(role, "joiner") || CoIEq(role, "client")) ? CO_ROLE_JOIN : 0;
    if (!m || !r || port < 1 || port > 65535) return Ret(lua, -1);
    CoClose();
    CO.mode = m; CO.role = r;
    CO.maxPlayers = maxp < 2 ? 2 : maxp > CO_MAX_PLAYERS ? CO_MAX_PLAYERS : (int)maxp;
    CO.mySlot = r == CO_ROLE_HOST ? 0 : -1;
    CO.port = (uint16_t)port;
    CO.delay = (delay < 0 ? 0 : delay > 1000 ? 1000 : delay) / 1000.0;
    CoCopy(CO.partner, sizeof(CO.partner), partner, CoLen(partner));
    CoCopy(CO.myVer, sizeof(CO.myVer), ver, CoLen(ver));
    double now = CoNow();
    CO.nonce = (uint32_t)(uint64_t)(now * 1000003.0) ^ (GetCurrentProcessId() << 16) ^ 0x5C0F;
    if (!CO.nonce) CO.nonce = 1;
    if (m == CO_MODE_STEAM) {
        if (!CoSteamInit()) return Ret(lua, -2);
        CO.myId = ST.myId(ST.user);
        const char* nm = ST.myName(ST.friends);
        CoCopy(CO.myName, sizeof(CO.myName), nm ? nm : "?", nm ? CoLen(nm) : 1);
    } else {
        if (!CoUdpOpen(r == CO_ROLE_HOST ? CO.port : (uint16_t)(CO.port + 1))) return Ret(lua, -3);
        if (r == CO_ROLE_JOIN && !CoParseIp(partner, &CO.links[0].addr, CO.port)) { CoClose(); return Ret(lua, -4); }
        CoCopy(CO.myName, sizeof(CO.myName), "pilot", 5);
        if (ST.state >= 0 && CoSteamInit()) { const char* nm = ST.myName(ST.friends); if (nm) CoCopy(CO.myName, sizeof(CO.myName), nm, CoLen(nm)); }
    }
    CO.open = 1;
    CO.lastDiscover = -10; CO.lastStats = now;
    wchar_t wp[160], wv[32];
    CoWide(partner, wp, 160); CoWide(ver, wv, 32);
    Log(L"coop: open: %s, %s, up to %d players, partner \"%s\", port %d, interpolation %d ms, mod %s; teleport functions %p / %p",
        m == CO_MODE_STEAM ? L"Steam P2P" : L"UDP", r == CO_ROLE_HOST ? L"host" : L"joiner", CO.maxPlayers, wp, (int32_t)CO.port,
        (int32_t)(CO.delay * 1000), wv, g_fAITeleportTo, g_fAITeleportInner);
    if (!g_fAITeleportTo || !g_fAITeleportInner) Log(L"coop: the AI plane's teleport wasn't found (other game version?): planes can't be moved, the other players won't show");
    return Ret(lua, 1);
}

static int L_CoopClose(void* lua) { CoClose(); return Ret(lua, 1); }

/* SV_CoopInfo() -> "key=value;...": open, mode, role, state (closed | searching | linked | lost), slot (yours, 0 = the
 * host, -1 not given yet), players (linked, you included), max, tele; last peers=<slot>/<state>/<rtt ms>/<ms since>/
 * <name>,... (one per link) */
static int L_CoopInfo(void* lua)
{
    double now = CoNow();
    if (CO.open && now - CO.lastFrame > 0.1) CoStep(now, 0);   /* (no frame ticks here: the menus, loading) */
    int used = 0, up = 0;
    for (int k = 0; k < CO_MAX_PLAYERS; ++k) if (CO.links[k].used) { ++used; if (CO.links[k].connected) ++up; }
    char out[900]; CoBuf b = { out, out + sizeof(out) - 1 };
    CoPutS(&b, "open="); CoPutU(&b, (uint64_t)CO.open);
    CoPutS(&b, ";mode="); CoPutS(&b, CO.mode == CO_MODE_STEAM ? "steam" : CO.mode == CO_MODE_UDP ? "udp" : "none");
    CoPutS(&b, ";role="); CoPutS(&b, CO.role == CO_ROLE_HOST ? "host" : CO.role == CO_ROLE_JOIN ? "join" : "none");
    CoPutS(&b, ";state="); CoPutS(&b, !CO.open ? "closed" : !used ? "searching" : up ? "linked" : "lost");
    CoPutS(&b, ";slot="); CoPutI(&b, CO.mySlot);
    CoPutS(&b, ";players="); CoPutI(&b, up + (CO.open ? 1 : 0));
    CoPutS(&b, ";max="); CoPutI(&b, CO.maxPlayers);
    CoPutS(&b, ";me="); CoPutU(&b, CO.myId);
    CoPutS(&b, ";cands="); CoPutI(&b, CO.ncand);
    CoPutS(&b, ";tele="); CoPutI(&b, g_fAITeleportTo && g_fAITeleportInner ? 1 : 0);
    CoPutS(&b, ";peers=");
    int first = 1;
    for (int k = 0; k < CO_MAX_PLAYERS; ++k) {
        CoLink* L = &CO.links[k];
        if (!L->used) continue;
        if (!first) CoPutS(&b, ",");
        first = 0;
        CoPutI(&b, k); CoPutS(&b, "/"); CoPutS(&b, L->connected ? "linked" : "lost"); CoPutS(&b, "/");
        CoPutI(&b, (int64_t)(L->rtt * 1000)); CoPutS(&b, "/"); CoPutI(&b, (int64_t)((now - L->lastRecv) * 1000)); CoPutS(&b, "/");
        for (const char* s = L->name; *s && b.p < b.end; ++s) *b.p++ = (*s == ';' || *s == ',' || *s == '/') ? '_' : *s;
    }
    *b.p = 0;
    U.luaSetString(lua, out, (size_t)(b.p - out));
    return 1;
}

/* SV_CoopSend(message [, reliable [, to]]) -> how many games it was queued for (0: none linked). reliable defaults
 * to 1. to: a player slot, or -1 (default) every linked game (a joiner only ever sends to the host). */
static int L_CoopSend(void* lua)
{
    static char msg[CO_MAX_LUA + 8];
    size_t n = 0; double rel = 1, to = -1;
    if (!ArgBytes(lua, msg, sizeof(msg), &n)) return Ret(lua, 0);
    ArgNumber(lua, &rel); ArgNumber(lua, &to);
    if (!CO.open) return Ret(lua, 0);
    int sent = 0;
    for (int k = 0; k < CO_MAX_PLAYERS; ++k) {
        if (!CO.links[k].used || (to >= 0 && (int)to != k)) continue;
        CoSendLua(k, msg, (uint32_t)n, rel != 0);
        ++sent;
    }
    return Ret(lua, sent);
}

/* SV_CoopRecv() -> "<sender's slot>|<message>" (from another game, or "<slot>|sys|..." from this runtime about that
 * link), "" when none */
static int L_CoopRecv(void* lua)
{
    double now = CoNow();
    if (CO.open && now - CO.lastFrame > 0.1) CoStep(now, 0);
    if (!CO.inCount) { U.luaSetString(lua, "", 0); return 1; }
    char* m = CO.inbox[CO.inHead];
    uint16_t n = CO.inboxLen[CO.inHead];
    CO.inHead = (CO.inHead + 1) % CO_INBOX; --CO.inCount;
    U.luaSetString(lua, m, n);
    free(m);
    return 1;
}

/* SV_CoopMe(plane [, flags]) -> 1: the local player's plane (streamed to the others), 0 = none; flags go with it */
static int L_CoopMe(void* lua)
{
    uint8_t* o = ArgObject(lua);
    double flags = 0; ArgNumber(lua, &flags);
    CO.meFlags = (uint32_t)flags;
    if (!o) { memset(&CO.me, 0, sizeof(CO.me)); return Ret(lua, 0); }
    if (CO.me.obj != o || !CoRefGet(&CO.me)) CoRefSet(&CO.me, o);
    return Ret(lua, CO.me.obj ? 1 : 0);
}

/* SV_CoopPeer(slot, plane) -> 1 bound: that plane shows player <slot> from now on (moved every frame), -1 it isn't a
 * plane the runtime can move (or a bad slot), 0 unbound (plane 0) */
static int L_CoopPeer(void* lua)
{
    double slot = -1;
    if (!ArgNumber(lua, &slot) || slot < 0 || slot >= CO_MAX_PLAYERS) return Ret(lua, -1);
    CoPlayer* P = &CO.players[(int)slot];
    uint8_t* o = ArgObject(lua);
    if (!o) { memset(&P->plane.ref, 0, sizeof(P->plane.ref)); return Ret(lua, 0); }
    if (!LiveObject(o) || !CoCanDrive(o)) {
        if (!CO.warnedTele) { CO.warnedTele = 1; Log(L"coop: object %p is no plane with the game's teleport; not bound", o); }
        return Ret(lua, -1);
    }
    CoRefSet(&P->plane.ref, o);
    P->plane.drives = P->plane.fails = 0;
    Log(L"coop: player %d's plane is %p", (int32_t)slot + 1, o);
    return Ret(lua, 1);
}

/* SV_CoopTrack(id, plane) -> 1 (host: stream that enemy under id), 0 untracked (plane 0), -1 bad */
static int L_CoopTrack(void* lua)
{
    double id = 0;
    if (!ArgNumber(lua, &id) || id < 1 || id > 65535) return Ret(lua, -1);
    uint8_t* o = ArgObject(lua);
    CoEnt* e = CoEntById((uint16_t)id, o != NULL);
    if (!o) { if (e) memset(e, 0, sizeof(*e)); return Ret(lua, 0); }
    if (!e || !CoRefSet(&e->ref, o)) return Ret(lua, -1);
    return Ret(lua, 1);
}

/* SV_CoopBind(id, plane) -> 1 (joiner: stream id moves that local copy every frame), 0 unbound, -1 not a plane the
 * runtime can move */
static int L_CoopBind(void* lua)
{
    double id = 0;
    if (!ArgNumber(lua, &id) || id < 1 || id > 65535) return Ret(lua, -1);
    uint8_t* o = ArgObject(lua);
    CoEnt* e = CoEntById((uint16_t)id, o != NULL);
    if (!o) { if (e) memset(e, 0, sizeof(*e)); return Ret(lua, 0); }
    if (!e || !LiveObject(o) || !CoCanDrive(o)) return Ret(lua, -1);
    CoRefSet(&e->ref, o);
    e->drives = e->fails = 0;
    return Ret(lua, 1);
}

/* SV_CoopPeerAt(slot) -> "x,y,z,pitch,yaw,roll,health,maxhealth,flags,age_ms" (player <slot>'s latest state), "" none */
static int L_CoopPeerAt(void* lua)
{
    double slot = -1;
    if (!ArgNumber(lua, &slot) || slot < 0 || slot >= CO_MAX_PLAYERS) { U.luaSetString(lua, "", 0); return 1; }
    CoPlayer* P = &CO.players[(int)slot];
    if (!P->plane.ns) { U.luaSetString(lua, "", 0); return 1; }
    const CoSnap* s = &P->plane.s[P->plane.ns - 1];
    double rot[3]; CoQuatToRot(s->q, rot);
    char out[200]; CoBuf b = { out, out + sizeof(out) - 1 };
    CoPutF(&b, s->p[0], 0); CoPutS(&b, ","); CoPutF(&b, s->p[1], 0); CoPutS(&b, ","); CoPutF(&b, s->p[2], 0); CoPutS(&b, ",");
    CoPutF(&b, rot[0], 1); CoPutS(&b, ","); CoPutF(&b, rot[1], 1); CoPutS(&b, ","); CoPutF(&b, rot[2], 1); CoPutS(&b, ",");
    CoPutI(&b, P->hp); CoPutS(&b, ","); CoPutF(&b, P->maxHp, 1); CoPutS(&b, ","); CoPutU(&b, P->flags); CoPutS(&b, ",");
    CoPutI(&b, (int64_t)((CoNow() - P->stateAt) * 1000));
    U.luaSetString(lua, out, (size_t)(b.p - out));
    return 1;
}

/* SV_CoopReset() -> 1: every stream, binding and puppet forgotten (a new level); the links stay */
static int L_CoopReset(void* lua)
{
    memset(CO.players, 0, sizeof(CO.players));
    memset(CO.ents, 0, sizeof(CO.ents));
    memset(&CO.me, 0, sizeof(CO.me));
    return Ret(lua, 1);
}

/* ---- a second player plane (runtime 0.21.0; tools/re/COOP.md 6) ------------------------------------------------
 * Online Mode's remote-player spawn (0x1471cc490, Emergency Call co-op) does, in order: SpawnActor a
 * LiveNetworkDummyController (identity transform, AlwaysSpawn, transient); SpawnActor<ALivePlayerPlane> of the remote
 * player's plane class (the game's helper 0x1471e5500); controller->vtable[+0x798](plane); AController::Possess;
 * plane->vtable[+0xc60]() (creates its ULiveNetworkPlayerPlane in LiveGameObject.NetworkObject); then its loadout, name
 * and emblem from the session's player data, and `plane[+0xed8] = 2` (another player's). SV_CoopSpawnPP does the same
 * minus the session data (it has none offline). The slots and the role byte are read from that code (sigs.h), the
 * network-object function is checked before it's called. Research probe first: Ctrl+F11 (sv_main.lua, test only)
 * spawns a copy of your own plane and SV_CoopFollow keeps it in formation. */
static CoRef  g_ppPlane, g_ppCtrl, g_follow, g_followPawn;
static double g_followOff[3], g_followAt;
static int32_t g_followMoves, g_followFails;

typedef void* (*CoWorldSpawnFn)(void* world, void* cls, const double* transform, void* params);
typedef void* (*CoSpawnPlaneFn)(void* world, void* cls, const double* transform, void* a4, void* a5, uint8_t a6);
typedef void  (*CoObjObjFn)(void* self, void* other);
typedef void  (*CoSelfFn)(void* self);

typedef struct { void* data; int32_t num, max; } CoArr;                          /* TArray<int32> */
typedef void (*CoLoadoutFn)(void* plane, const CoArr* list1, const CoArr* list2);
typedef void (*CoFinishFn)(void* actor, const double* transform, uint8_t isDefault, void* cache, uint8_t scaleMethod);

/* The loadout call and its object's field (`cmp qword [plane + disp32], 0` at +0x21: it makes the object once), and the
 * two loadout bytes, from the remote spawn's code */
static int CoLoadoutSites(uint8_t** fn, int32_t* objOff, int32_t* byteOff)
{
    uint8_t* s = g_siteRemoteLoadout;
    if (!s || !g_siteRemoteFlags || s[12] != 0xE8) return 0;
    uint8_t* f = s + 17 + *(int32_t*)(s + 13);
    if (!InGame(f) || f[0x21] != 0x48 || f[0x22] != 0x83 || f[0x23] != 0xB9 || f[0x28] != 0) return 0;
    *fn = f; *objOff = *(int32_t*)(f + 0x24);
    s = g_siteRemoteFlags;
    if (s[5] != 0x44 || s[6] != 0x88 || s[7] != 0xB6 || s[15] != 0x40 || s[16] != 0x88 || s[17] != 0xBE) return 0;
    byteOff[0] = *(int32_t*)(s + 8); byteOff[1] = *(int32_t*)(s + 18);
    return *objOff > 0 && *objOff < 0x8000 && byteOff[0] > 0 && byteOff[0] < 0x8000 && byteOff[1] > 0 && byteOff[1] < 0x8000;
}

/* One of the loadout object's two lists (TArray<int32> at +0x30 / +0x40, 0x147dd4cb0 fills them), if it looks whole */
static CoArr CoLoadoutList(uint8_t* lo, int32_t off)
{
    CoArr a = { 0 };
    if (!lo || !Readable(lo + off, sizeof(CoArr))) return a;
    CoArr* src = (CoArr*)(lo + off);
    if (src->num < 0 || src->num > 64 || src->max < src->num || (src->num && !Readable(src->data, 4 * (uint32_t)src->num))) return a;
    return *src;                                                                  /* the loadout call copies it */
}

static int CoRemoteSites(int32_t* possessSlot, uint8_t** possessFn, int32_t* netSlot, int32_t* roleOff)
{
    uint8_t* s = g_siteRemotePossess;
    if (!s || !g_siteRemoteNetObj || !g_siteRemoteRole) return 0;
    if (s[12] != 0x41 || s[13] != 0xFF || s[14] != 0x90) return 0;                  /* call [r8 + disp32] */
    *possessSlot = *(int32_t*)(s + 15);
    uint8_t* c = s + 19;                                                            /* mov rdx, rsi; mov rcx, rbx; call */
    if (c[0] != 0x48 || c[1] != 0x8B || c[2] != 0xD6 || c[3] != 0x48 || c[4] != 0x8B || c[5] != 0xCB || c[6] != 0xE8) return 0;
    *possessFn = c + 11 + *(int32_t*)(c + 7);
    s = g_siteRemoteNetObj;
    if (s[14] != 0xFF || s[15] != 0x92) return 0;                                   /* call [rdx + disp32] */
    *netSlot = *(int32_t*)(s + 16);
    s = g_siteRemoteRole;
    if (s[2] != 0xC6 || s[3] != 0x86 || s[8] != 0x02) return 0;                     /* mov byte [rsi + disp32], 2 */
    *roleOff = *(int32_t*)(s + 4);
    return *possessSlot > 0 && *possessSlot < 0x2000 && *netSlot > 0 && *netSlot < 0x2000 && *roleOff > 0 && *roleOff < 0x8000 &&
           InGame(*possessFn);
}

static void CoXform(double* xf, const double* pos, double yawDeg)         /* FTransform: quat, translation, scale */
{
    memset(xf, 0, 12 * sizeof(double));
    double h = yawDeg * CO_PI / 360.0;
    xf[2] = Sin(h); xf[3] = Cos(h);                                               /* yaw only: (0, 0, sin, cos) */
    if (pos) { xf[4] = pos[0]; xf[5] = pos[1]; xf[6] = pos[2]; }
    xf[8] = xf[9] = xf[10] = 1.0;
}

/* SV_CoopSpawnPP(pawn, x, y, z, yaw) -> the new player plane's address (a copy of pawn's plane class, possessed by a
 * network dummy controller, marked as another player's), or < 0: -1 bad args, -2 game code not found, -3 no dummy
 * controller class, -4 the controller didn't spawn, -5 the plane didn't spawn, -6 its spawn didn't finish. One at a
 * time: a second call removes the first. */
static int L_CoopSpawnPP(void* lua)
{
    uint8_t* pawn = ArgObject(lua);
    double pos[3] = { 0 }, yaw = 0;
    if (!pawn || !ArgNumber(lua, &pos[0]) || !ArgNumber(lua, &pos[1]) || !ArgNumber(lua, &pos[2])) return Ret(lua, -1);
    ArgNumber(lua, &yaw);
    if (!LiveObject(pawn)) return Ret(lua, -1);
    int32_t possessSlot = 0, netSlot = 0, roleOff = 0, loObj = 0, loByte[2] = { 0, 0 };
    uint8_t* possessFn = NULL, *loadoutFn = NULL;
    if (!g_fSpawnPlayerPlane || !g_fWorldSpawnActor || !ResolveUE4SS() ||
        !CoRemoteSites(&possessSlot, &possessFn, &netSlot, &roleOff) || !CoLoadoutSites(&loadoutFn, &loObj, loByte) ||
        !CoFinishSpawningFn()) {
        Log(L"coop: second player plane: game code not found (spawn %p, world spawn %p, sites %p %p %p %p %p %p)", g_fSpawnPlayerPlane,
            g_fWorldSpawnActor, g_siteRemotePossess, g_siteRemoteNetObj, g_siteRemoteRole, g_siteRemoteLoadout, g_siteRemoteFlags,
            g_siteRemoteFinish);
        return Ret(lua, -2);
    }
    if (CoRefGet(&g_ppPlane) && g_destroyActor) g_destroyActor(g_ppPlane.obj, 0);
    if (CoRefGet(&g_ppCtrl) && g_destroyActor) g_destroyActor(g_ppCtrl.obj, 0);
    memset(&g_ppPlane, 0, sizeof(g_ppPlane)); memset(&g_ppCtrl, 0, sizeof(g_ppCtrl));
    void* cls = *(void**)(pawn + 0x10);                                             /* UObjectBase::ClassPrivate */
    void* world = VCall(pawn, VF_WORLD);
    /* the dummy controller's class: by its short name as UE4SS finds classes (the full path found nothing: test of
     * 2026-10-25), else from the remote spawn's own call to its StaticClass */
    const wchar_t* how = L"by name";
    void* dummy = U.findObject(L"Class", L"LiveNetworkDummyController", 0, 0);
    if (!LiveObject(dummy)) {
        uint8_t* s = g_siteRemoteDummyCls;
        uint8_t* sc = (s && s[0x18] == 0xE8) ? s + 0x1d + *(int32_t*)(s + 0x19) : NULL;
        typedef void* (*CoStaticClassFn)(void);
        dummy = (sc && InGame(sc)) ? ((CoStaticClassFn)sc)() : NULL;
        how = L"from its StaticClass";
    }
    if (!LiveObject(cls) || !LiveObject(world)) return Ret(lua, -1);
    if (!LiveObject(dummy)) { Log(L"coop: second player plane: the LiveNetworkDummyController class wasn't found"); return Ret(lua, -3); }
    Log(L"coop: second player plane: dummy controller class %p (%s)", dummy, how);
    double idf[12] __attribute__((aligned(16))), xf[12] __attribute__((aligned(16)));
    CoXform(idf, NULL, 0);
    CoXform(xf, pos, yaw);
    uint8_t params[0x80] __attribute__((aligned(16)));                              /* FActorSpawnParameters, as the game fills it */
    memset(params, 0, sizeof(params));
    *(uint16_t*)(params + 0x30) = 0x101;                                            /* AlwaysSpawn, MultiplyWithRoot */
    *(uint32_t*)(params + 0x34) = 0x48;                                             /* RF_Transactional | RF_Transient */
    uint8_t* ctrl = (uint8_t*)((CoWorldSpawnFn)g_fWorldSpawnActor)(world, dummy, idf, params);
    if (!LiveObject(ctrl)) { Log(L"coop: second player plane: the dummy controller didn't spawn"); return Ret(lua, -4); }
    uint8_t* plane = (uint8_t*)((CoSpawnPlaneFn)g_fSpawnPlayerPlane)(world, cls, xf, NULL, NULL, 0);
    if (!LiveObject(plane)) {
        if (g_destroyActor) g_destroyActor(ctrl, 0);
        Log(L"coop: second player plane: the plane didn't spawn");
        return Ret(lua, -5);
    }
    ((CoObjObjFn)(*(void***)ctrl)[possessSlot / 8])(ctrl, plane);
    ((CoObjObjFn)possessFn)(ctrl, plane);
    /* its network object: the function in that slot must be the one read (it creates LiveGameObject.NetworkObject) */
    uint8_t* nf = (uint8_t*)(*(void***)plane)[netSlot / 8];
    uint8_t* no = (uint8_t*)U.valuePtr(plane, L"NetworkObject");
    int32_t noOff = no ? (int32_t)(no - plane) : -1;
    int netOk = InGame(nf) && nf[0] == 0x40 && nf[1] == 0x57 && nf[2] == 0x48 && nf[3] == 0x81 && nf[4] == 0xEC &&
                nf[0x1b] == 0x48 && nf[0x1c] == 0x83 && nf[0x1d] == 0xB9 && *(int32_t*)(nf + 0x1e) == noOff;
    if (netOk) ((CoSelfFn)nf)(plane);
    else Log(L"coop: second player plane: its network-object function isn't the one checked (%p); left out", nf);
    *(uint8_t*)(plane + roleOff) = 2;
    /* The game's helper spawns the plane deferred: as the remote spawn does, give it a loadout (yours: your loadout
     * object's two lists) and the two loadout bytes, then FinishSpawning (construction and BeginPlay: the plane's own
     * setup, its weapons' owner among it). 0.22.1 left that out and the first formation teleport crashed the game
     * (its weapons had no owner, test of 2026-10-25). */
    uint8_t* lo = *(uint8_t**)(pawn + loObj);
    if (!LiveObject(lo)) lo = NULL;
    CoArr l1 = CoLoadoutList(lo, 0x30), l2 = CoLoadoutList(lo, 0x40);
    ((CoLoadoutFn)loadoutFn)(plane, &l1, &l2);
    plane[loByte[0]] = pawn[loByte[0]]; plane[loByte[1]] = pawn[loByte[1]];
    ((CoFinishFn)g_fFinishSpawning)(plane, xf, 0, NULL, 1);
    int finished = (plane[g_finishedOff] & 1) != 0;
    int32_t wOff = *(int32_t*)(g_siteRemoteLoadout + 20);                          /* mov r14, [plane + disp32] */
    uint8_t* w = (wOff > 0 && wOff < 0x8000) ? *(uint8_t**)(plane + wOff) : NULL;
    void* owner = (w && Readable(w + 0x2d0, 8)) ? *(void**)(w + 0x2d0) : NULL;   /* what crashed 0.22.1 (COOP.md 6) */
    Log(L"coop: second player plane %p (class %p) spawned, controller %p, possessed (slot +%x, Possess %p), network object %p (+%x), role byte +%x = 2 (yours %d)",
        plane, cls, ctrl, (uint32_t)possessSlot, possessFn, (netOk && noOff > 0) ? *(void**)(plane + noOff) : NULL, (uint32_t)noOff, (uint32_t)roleOff,
        (int32_t)pawn[roleOff]);
    Log(L"coop: second player plane: loadout %p (+%x; yours %p: %d and %d entries), bytes +%x +%x = %d %d, spawn finished: %s, weapons %p (+%x), their owner %p",
        *(void**)(plane + loObj), (uint32_t)loObj, lo, l1.num, l2.num, (uint32_t)loByte[0], (uint32_t)loByte[1], plane[loByte[0]],
        plane[loByte[1]], finished ? L"yes" : L"NO", w, (uint32_t)wOff, owner);
    if (!finished) {
        if (g_destroyActor) { g_destroyActor(plane, 0); g_destroyActor(ctrl, 0); }
        Log(L"coop: second player plane: its spawn didn't finish; removed");
        return Ret(lua, -6);
    }
    CoRefSet(&g_ppPlane, plane); CoRefSet(&g_ppCtrl, ctrl);
    return Ret(lua, (int64_t)(uintptr_t)plane);
}

/* SV_CoopPPRole(role) -> the second player plane's network role byte before (2 another player's, as Online Mode sets
 * it); -1 none up. A test of what keeps the copy at the map's centre (its own tick with role 2: test of 2026-10-25). */
static int L_CoopPPRole(void* lua)
{
    double role = 0;
    uint8_t* plane = CoRefGet(&g_ppPlane);
    int32_t possessSlot = 0, netSlot = 0, roleOff = 0; uint8_t* possessFn = NULL;
    if (!plane || !ArgNumber(lua, &role) || !CoRemoteSites(&possessSlot, &possessFn, &netSlot, &roleOff)) return Ret(lua, -1);
    int32_t old = plane[roleOff];
    plane[roleOff] = (uint8_t)role;
    Log(L"coop: second player plane %p: role byte +%x %d -> %d", plane, (uint32_t)roleOff, old, (int32_t)plane[roleOff]);
    return Ret(lua, old);
}

/* SV_CoopKillPP() -> 1: the second player plane and its controller removed (0: none was up) */
static int L_CoopKillPP(void* lua)
{
    int n = 0;
    if (g_follow.obj == g_ppPlane.obj) memset(&g_follow, 0, sizeof(g_follow));
    if (CoRefGet(&g_ppPlane) && g_destroyActor) { g_destroyActor(g_ppPlane.obj, 0); ++n; }
    if (CoRefGet(&g_ppCtrl) && g_destroyActor) { g_destroyActor(g_ppCtrl.obj, 0); ++n; }
    memset(&g_ppPlane, 0, sizeof(g_ppPlane)); memset(&g_ppCtrl, 0, sizeof(g_ppCtrl));
    if (n) Log(L"coop: second player plane removed");
    return Ret(lua, n ? 1 : 0);
}

/* Formation test diagnostics (runtime 0.22.4): the copy flickered in and out with either way of moving it (tests of
 * 2026-10-25, 0.22.2 and 0.22.3). Each sample (at the input build and at the music tick, twice a frame) reads where
 * the copy is against where it was put and against the last sample, and the visibility bits of its root and of the
 * three mesh components the game's own show / hide code (0x147d50710) sets: USceneComponent +0x188 (bit 5 bVisible,
 * from SetVisibility 0x1442ce610), and AActor bHidden's byte. One summary a second for 30 s after each start. */
typedef struct { int32_t off; uint8_t* comp; uint16_t last; int32_t changes; } CoVisProbe;
static int32_t    g_followMode;                    /* 0 moved at the music tick, 1 left alone (only watched), 2 moved at the input build */
static double     g_followSet[3], g_followMusicAt, g_fdLast[3], g_fdWinAt, g_fdMaxOff, g_fdMaxJump, g_fdFarPos[3];
static int        g_followHaveSet, g_fdHaveLast;
static int32_t    g_fdSamples, g_fdFar, g_fdJumps, g_fdWin, g_fdHidChanges;
/* when your plane moves within a frame (runtime 0.22.5; the copy stuttered with its tick off, test of 2026-10-25):
 * how far between the input build and the music tick, and between the music tick and the next input build */
static double     g_fdPawnAt[3], g_fdInToMus, g_fdMusToIn;
static int32_t    g_fdPawnFrom, g_fdInToMusN, g_fdMusToInN;                 /* g_fdPawnFrom: 0 none, 1 input, 2 music */
static uint8_t*   g_fdHid;
static uint8_t    g_fdHidLast;
static CoVisProbe g_fdVis[4] = { { -1, NULL, 0, 0 }, { 0x15a0, NULL, 0, 0 }, { 0x1af8, NULL, 0, 0 }, { 0x15c8, NULL, 0, 0 } };

static void CoFollowDiagStart(uint8_t* plane)
{
    CoResolve(plane);                                                             /* the root's offset */
    g_followHaveSet = g_fdHaveLast = 0;
    g_fdSamples = g_fdFar = g_fdJumps = g_fdWin = g_fdHidChanges = 0;
    g_fdMaxOff = g_fdMaxJump = 0; g_fdWinAt = CoNow();
    g_fdPawnFrom = g_fdInToMusN = g_fdMusToInN = 0; g_fdInToMus = g_fdMusToIn = 0;
    g_fdHid = (uint8_t*)U.valuePtr(plane, L"bHidden");
    g_fdHidLast = g_fdHid ? *g_fdHid : 0;
    for (int i = 0; i < 4; ++i) {
        CoVisProbe* v = &g_fdVis[i];
        int32_t off = i == 0 ? g_offRoot : v->off;
        uint8_t* c = (off > 0 && Readable(plane + off, 8)) ? *(uint8_t**)(plane + off) : NULL;
        v->comp = (c && LiveObject(c) && Readable(c + 0x188, 2)) ? c : NULL;
        v->last = v->comp ? *(uint16_t*)(v->comp + 0x188) : 0;
        v->changes = 0;
    }
    Log(L"coop: follow diagnostics: bHidden byte %p (+%x) = %x; components root %p, +15a0 %p, +1af8 %p, +15c8 %p", g_fdHid,
        g_fdHid ? (uint32_t)(g_fdHid - plane) : 0u, (uint32_t)g_fdHidLast, g_fdVis[0].comp, g_fdVis[1].comp, g_fdVis[2].comp, g_fdVis[3].comp);
}

static void CoFollowSample(uint8_t* plane, uint8_t* pawn, double now, int fromMusic)
{
    double p[3], r[3];
    if (CoReadPose(pawn, p, r)) {
        int from = fromMusic ? 2 : 1;
        if (g_fdPawnFrom && g_fdPawnFrom != from) {
            double dx = p[0] - g_fdPawnAt[0], dy = p[1] - g_fdPawnAt[1], dz = p[2] - g_fdPawnAt[2];
            double d = CoSqrt(dx * dx + dy * dy + dz * dz);
            if (fromMusic) { g_fdInToMus += d; ++g_fdInToMusN; } else { g_fdMusToIn += d; ++g_fdMusToInN; }
        }
        memcpy(g_fdPawnAt, p, 24); g_fdPawnFrom = from;
    }
    if (CoReadPose(plane, p, r)) {
        if (g_followHaveSet && g_followMode != 1) {
            double dx = p[0] - g_followSet[0], dy = p[1] - g_followSet[1], dz = p[2] - g_followSet[2];
            double d = CoSqrt(dx * dx + dy * dy + dz * dz) / 100;
            if (d > g_fdMaxOff) g_fdMaxOff = d;
            if (d > 50) { ++g_fdFar; memcpy(g_fdFarPos, p, 24); }
        }
        if (g_fdHaveLast) {
            double dx = p[0] - g_fdLast[0], dy = p[1] - g_fdLast[1], dz = p[2] - g_fdLast[2];
            double d = CoSqrt(dx * dx + dy * dy + dz * dz) / 100;
            if (d > g_fdMaxJump) g_fdMaxJump = d;
            if (d > 50) ++g_fdJumps;
        }
        memcpy(g_fdLast, p, 24); g_fdHaveLast = 1;
    }
    ++g_fdSamples;
    for (int i = 0; i < 4; ++i) {
        CoVisProbe* v = &g_fdVis[i];
        if (!v->comp || !LiveObject(v->comp)) continue;
        uint16_t b = *(uint16_t*)(v->comp + 0x188);
        if (b != v->last) { ++v->changes; v->last = b; }
    }
    if (g_fdHid && *g_fdHid != g_fdHidLast) { ++g_fdHidChanges; g_fdHidLast = *g_fdHid; }
    if (now - g_fdWinAt < 1.0 || g_fdWin >= 30) return;
    Log(L"coop: follow diag (%s): your plane moves %d cm from input build to music tick (%d), %d cm from music tick to the next input build (%d)",
        g_followMode == 1 ? L"left alone" : g_followMode == 2 ? L"moved at input" : L"moved at music",
        g_fdInToMusN ? (int32_t)(g_fdInToMus / g_fdInToMusN) : -1, g_fdInToMusN, g_fdMusToInN ? (int32_t)(g_fdMusToIn / g_fdMusToInN) : -1, g_fdMusToInN);
    g_fdInToMus = g_fdMusToIn = 0; g_fdInToMusN = g_fdMusToInN = 0;
    Log(L"coop: follow diag (%s): %d samples; off its spot >50 m: %d (max %d m, last at %d %d %d m); jumps >50 m: %d (max %d m); visibility changes: root %d (%x), +15a0 %d (%x), +1af8 %d (%x), +15c8 %d (%x), bHidden byte %d (%x)",
        g_followMode == 1 ? L"left alone" : g_followMode == 2 ? L"moved at input" : L"moved at music", g_fdSamples, g_fdFar, (int32_t)g_fdMaxOff, (int32_t)(g_fdFarPos[0] / 100),
        (int32_t)(g_fdFarPos[1] / 100), (int32_t)(g_fdFarPos[2] / 100), g_fdJumps, (int32_t)g_fdMaxJump,
        g_fdVis[0].changes, (uint32_t)g_fdVis[0].last, g_fdVis[1].changes, (uint32_t)g_fdVis[1].last, g_fdVis[2].changes,
        (uint32_t)g_fdVis[2].last, g_fdVis[3].changes, (uint32_t)g_fdVis[3].last, g_fdHidChanges, (uint32_t)g_fdHidLast);
    g_fdSamples = g_fdFar = g_fdJumps = g_fdHidChanges = 0; g_fdMaxOff = g_fdMaxJump = 0;
    for (int i = 0; i < 4; ++i) g_fdVis[i].changes = 0;
    g_fdWinAt = now; ++g_fdWin;
}

/* SV_CoopFollow(plane, pawn, forward, right, up[, mode]) -> 1: every frame plane is moved to pawn's spot + that offset
 * (metres, along pawn's heading) with pawn's rotation, at the music tick (mode 0) or at the input build (mode 2), or
 * only watched (mode 1: the diagnostics above, no moves); plane 0 stops it. A formation test of the per-frame drive. */
static int L_CoopFollow(void* lua)
{
    uint8_t* plane = ArgObject(lua);
    if (!plane) { memset(&g_follow, 0, sizeof(g_follow)); return Ret(lua, 0); }
    uint8_t* pawn = ArgObject(lua);
    double f = 0, r = 0, u = 0, mode = 0;
    ArgNumber(lua, &f); ArgNumber(lua, &r); ArgNumber(lua, &u); ArgNumber(lua, &mode);
    if (!pawn || !LiveObject(plane) || !LiveObject(pawn) || !CoCanDrive(plane)) return Ret(lua, -1);
    CoRefSet(&g_follow, plane); CoRefSet(&g_followPawn, pawn);
    g_followOff[0] = f * 100; g_followOff[1] = r * 100; g_followOff[2] = u * 100;
    g_followMoves = g_followFails = 0;
    g_followMode = mode == 1 ? 1 : mode == 2 ? 2 : 0;
    Log(L"coop: %p follows %p (%d m ahead, %d m right, %d m up), %s", plane, pawn, (int32_t)f, (int32_t)r, (int32_t)u,
        g_followMode == 1 ? L"left alone (watched only)" : g_followMode == 2 ? L"moved every frame at the input build" : L"moved every frame at the music tick");
    CoFollowDiagStart(plane);
    return Ret(lua, 1);
}

static void CoFollowFrame(int fromMusic)
{
    if (!g_follow.obj) return;
    double now = CoNow();
    uint8_t* plane = CoRefGet(&g_follow), *pawn = CoRefGet(&g_followPawn);
    if (!plane || !pawn) { memset(&g_follow, 0, sizeof(g_follow)); Log(L"coop: formation test ended (an actor is gone)"); return; }
    CoFollowSample(plane, pawn, now, fromMusic);
    /* one move a frame: at the music tick when it runs (0.22.3 and before moved at both), or at the input build (mode 2) */
    if (fromMusic) g_followMusicAt = now;
    if (g_followMode == 1 || (g_followMode == 2 && fromMusic)) return;
    if (g_followMode == 0 && !fromMusic && now - g_followMusicAt < 0.05) return;
    if (now - g_followAt < 0.001) return;
    g_followAt = now;
    double pos[3], rot[3];
    if (!CoReadPose(pawn, pos, rot)) return;
    double h = rot[1] * CO_PI / 180.0, c = Cos(h), sn = Sin(h);
    pos[0] += g_followOff[0] * c - g_followOff[1] * sn;
    pos[1] += g_followOff[0] * sn + g_followOff[1] * c;
    pos[2] += g_followOff[2];
    if (CoTeleport(plane, pos, rot)) { ++g_followMoves; memcpy(g_followSet, pos, 24); g_followHaveSet = 1; } else ++g_followFails;
    if ((g_followMoves + g_followFails) % 600 == 1)
        Log(L"coop: formation test: %d moves, %d refused", g_followMoves, g_followFails);
}

