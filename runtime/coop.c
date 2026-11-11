/* =============================================================================
 *  Survival COOP: the native half of co-op for up to 24 players (runtime 0.24.0; docs/re/COOP.md). Included by
 *  survival_rt.c.
 *
 *  Host-authoritative, after Double Trigger, the AC7 co-op mod (layer10-love/double-trigger, MIT / Unlicense): the
 *  host's game runs the rounds and the enemies, the joiners' games mirror them. A star: each joiner is linked to the
 *  host only (slot 0 = the host, 1..23 the joiners, given by the host), and the host relays every player's plane to
 *  the others. This file is the transport and the per-frame work; Scripts/sv_coop.lua decides what is mirrored.
 *  (Its Lua functions and the second player plane are in coop_lua.c, #included at the end.)
 *
 *  Transport: Steam P2P (ISteamNetworking v006 through steam_api64's flat API: SendP2PPacket / ReadP2PPacket on a
 *  channel of our own, no callbacks: a session is accepted by sending to that user and AcceptP2PSessionWithUser), or
 *  UDP (ws2_32, loaded at run time: LAN or a VPN, the host listens on a port). Every packet starts with
 *  'S', CO_PROTO, a type and a flags byte:
 *    H hello (1 s): role, session nonce, time + echo of the link's last hello (the round trip), the slot the host
 *      gives that joiner (or none yet / full), max players, mod version, name
 *    L reliable Lua message: sender nonce, seq, length, bytes (per link, in order: resent once its ack is a round trip
 *      overdue, backing off; a lost link gets only its oldest, CoFlushReliable)
 *    K ack: sender nonce, every seq below this one arrived
 *    U unreliable Lua message
 *    P a joiner's own plane, to the host (30 Hz): slot, time, position (cm, doubles), rotation (quaternion), health,
 *      Lua's flags, the flight block (protocol 4, COOP2MP: CO_FL)
 *    Q the host's batch of planes, to each joiner (30 Hz; 20 Hz past CO_FAST_UPTO players): n x {slot, time on that
 *      player's clock, position (doubles), rotation (int16 quaternion), health, max health, flags, flight block}, as
 *      many packets as it takes (protocol 4: 19 records fit one), every player's
 *      latest but the receiver's own (protocol 3: up to 24 players. Relaying each joiner's P to every other joiner
 *      was n x n packets 30 times a second, about 16,000 a second from the host at 24)
 *    E the host's tracked enemies (15 Hz): time, n x {id, position (floats), rotation (int16 quaternion)}
 *  The host streams Q and E only to a joiner whose own plane is in Survival's level (CoWantsState), and nothing but
 *  hellos and its oldest reliable message to a lost link.
 *  Puppets: a local plane bound to a stream (another player's, or a host enemy on a joiner's game) is moved every
 *  frame to where the stream says it was a delay ago on its sender's clock (snapshot interpolation, nlerp; the delay
 *  follows how late that sender's states come, CoTrackOffset / CoRenderDelay: CO.delay to CO_DELAY_MAX), through
 *  the plane's own teleport (vtable slot 315: the flight model flies on from there, hard rule 39), late in the frame
 *  (the music player's tickable, after every actor's tick), so it draws where the stream puts it.
 *  All of it runs on the game thread: the Lua calls come from Survival's ExecuteInGameThread tick, the frame work from
 *  the music player's tick (OnMusicTick).
 * ============================================================================= */

#define CO_PROTO        4                   /* 4: the flight block (COOP2MP, runtime 0.30.0); 3: up to 24, the host's Q
                                               batches (runtime 0.24.0); 2: up to 4; 1: two */
#define CO_MAX_PLAYERS  24
#define CO_FAST_UPTO    6                   /* players (you included) up to which the host sends Q at 30 Hz, else 20  */
#define CO_MAX_CAND     64                  /* Steam friends tried at once                                          */
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
/* Lua's state flags (SV_CoopMe's second argument; each P and Q carries them whole, 32 bits, CoSaneState never looks at
 * them). Agreed with Scripts/sv_coop.lua for runtime 0.28.5; the runtime itself acts on CO_FLAG_AB only (CoDrive). */
#define CO_FLAG_LEVEL     1                 /* in Survival's level                                                  */
#define CO_FLAG_ALIVE     2
#define CO_FLAG_AIRFIELD  4                 /* on the airfield                                                      */
#define CO_FLAG_DOWN      8                 /* DOWN, waiting for a revive (SV_Down's autopilot flies the plane)     */
#define CO_FLAG_GEAR      16                /* gear down                                                            */
#define CO_FLAG_AB        32                /* afterburner: the stand-in's afterburner byte follows it every frame   */
#define CO_FLAG_GUN       64                /* gun firing                                                           */
#define CO_FLAG_FLARES    128               /* flares                                                               */
/* The flight block (protocol 4, COOP2MP's real player planes: docs/re/COOP2MP.md T3): what another game feeds a player's
 * real plane with (hard rule 53) beyond its pose: [0..5] the stick, int8 x127 (pitch, yaw, roll, throttle, brake,
 * high-G: the last BuildFlightInput), [6] the afterburner amount x255 (plane+0x39d0), [7..8] the speed, m/s x10
 * (plane+0x2318), [9..12] the flight State (plane+0x2b18). flight.c fills it (FlFlightBlock) and feeds it (FlFeeds). */
#define CO_FL             13

static uint8_t* g_fAITeleportTo;            /* found by FindFunctions (sigs.h)                                       */
static uint8_t* g_fAITeleportInner;
static uint8_t* g_fPPTeleportTo, *g_fPPTeleportInner;              /* the same pair on ALivePlayerPlane              */
static uint8_t* g_fSpawnPlayerPlane, *g_fWorldSpawnActor;          /* a second player plane (COOP.md 6)              */
static uint8_t* g_siteRemotePossess, *g_siteRemoteNetObj, *g_siteRemoteRole, *g_siteRemoteDummyCls;
static uint8_t* g_siteRemoteLoadout, *g_siteRemoteFlags, *g_siteRemoteFinish;
static uint8_t* g_fTakeoffAB;               /* ALiveAIPlane::EnableTakeoffAfterburner (sigs.h kSigTakeoffAB), read only */

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
typedef struct { uint32_t seq; uint16_t len; double sentAt; char* data; uint8_t tries; } CoOut;
typedef struct { uint8_t* obj; void* vt; uint32_t idx; uint64_t name; } CoRef;   /* a local actor, checked before use */
typedef struct { double t; double p[3]; float q[4]; } CoSnap;
typedef struct {
    uint16_t id; uint8_t used;
    CoRef    ref;                           /* the local actor this stream drives (joiner), or the one it reads (host) */
    CoSnap   s[CO_SNAPS]; int32_t ns;
    int32_t  drives, fails;
    int32_t  ahead, held, mark;             /* since the last minute's report: moves past its newest snapshot (on along
                                               its velocity), past 0.5 s (held); mark = drives at that report          */
    double   lastRecv;
} CoEnt;

/* A link to another game: the host has one per joiner (index = that joiner's slot, 1..23), a joiner one to the host
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

#define CO_Q_REC (49 + CO_FL)               /* a Q record: slot, time, position, int16 quaternion, health, max, flags,
                                               the flight block */

/* A player's plane as streamed (slot 0 the host, 1..23 the joiners): its snapshots on that player's clock and the
 * local puppet they move. A joiner gets the other joiners' planes from the host's Q batches; the host keeps each
 * player's latest as a Q record (rec) until the next batch has gone. */
typedef struct {
    CoEnt    plane;
    double   offset; int haveOffset;        /* local time - that player's time: the smallest seen, let go of slowly */
    double   jit, dly;                      /* how late its states come past that (up fast, down slowly); the delay its
                                               puppets are drawn behind it (CoRenderDelay), s                          */
    int32_t  hp; float maxHp; uint32_t flags; double stateAt;
    uint8_t  rec[CO_Q_REC]; int fresh;
    int      abSaid;                        /* its stand-in's afterburner was logged on (once per binding)          */
    uint8_t  fl[CO_FL]; int hasFl;          /* its latest flight block (protocol 4)                                 */
    uint32_t fed, fedSkip; double fedOffCm; /* its real plane here: frames fed, frames not, the last miss (flight.c) */
} CoPlayer;

static struct {
    int      open, mode, role, maxPlayers, mySlot;   /* mySlot: the host 0, a joiner the one the host gave it (-1 before) */
    uint32_t nonce;
    char     partner[640];                 /* (24 SteamID64s and "auto": host migration, runtime 0.32.7) */
    double   delay;                         /* interpolation delay, seconds */
    uint16_t port;
    double   lastDiscover, lastFrame, lastPlayerSend, lastEntSend, lastStats;
    double   prevStep, frameGap;            /* the last CoStep and the gap before this one (a hitch: > 0.1 s)       */
    uint64_t cand[CO_MAX_CAND]; int32_t ncand;
    char     myVer[32], myName[64];
    uint64_t myId;
    CoLink   links[CO_MAX_PLAYERS];
    CoPlayer players[CO_MAX_PLAYERS];
    char*    inbox[CO_INBOX]; uint16_t inboxLen[CO_INBOX]; int32_t inHead, inCount;
    CoRef    me; uint32_t meFlags;
    CoEnt    ents[CO_MAX_ENTS];
    uint32_t badPk;
    int      warnedTele, fullSaid, badVerSaid;
    struct { uint64_t id; double at; } refused[8];   /* (the host: joiners turned away for another build, logged once a minute) */
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

/* The AI plane's afterburner byte (+0x29b8), from EnableTakeoffAfterburner's `mov byte [rbx + disp32], dil` at +0x82
 * (runtime 0.28.5). Slot 315's teleport runs the AI plane's OnReposition (0x147bb5900), which ends in
 * EnableTakeoffAfterburner(false): every frame's move put a stand-in's afterburner out (the user's co-op run of
 * 2026-10-29: "nor do I see their afterburners"), so CoDrive writes it again right after each move. 0 if not found. */
static int32_t g_coAbOff = -1;
static int32_t CoAbOffset(void)
{
    if (g_coAbOff >= 0) return g_coAbOff;
    g_coAbOff = 0;
    uint8_t* f = g_fTakeoffAB;
    if (!f || !Readable(f + 0x82, 7) || f[0x82] != 0x40 || f[0x83] != 0x88 || f[0x84] != 0xBB) {
        Log(L"coop: the AI plane's afterburner byte wasn't found (EnableTakeoffAfterburner %p); stand-ins show no afterburner", f);
        return 0;
    }
    int32_t off = *(int32_t*)(f + 0x85);
    if (off < 0x1000 || off >= 0x8000) { Log(L"coop: the AI plane's afterburner byte +%x is implausible; not used", (uint32_t)off); return 0; }
    g_coAbOff = off;
    Log(L"coop: the AI plane's afterburner byte is +%x (EnableTakeoffAfterburner %p): stand-ins follow their player's afterburner flag (%d)",
        (uint32_t)off, f, (int32_t)CO_FLAG_AB);
    return off;
}

/* ---- the flight block (flight.c: COOP2MP's real player planes) ------------------------------------------------- */
#ifdef SV_FLIGHT_FEED
static void FlFlightBlock(uint8_t* plane, uint8_t* out);   /* your plane's flight block, into out[CO_FL]            */
static int  FlFeeds(uint8_t* plane);                       /* a bound puppet the remote update feeds (not moved here) */
#else
static void FlFlightBlock(uint8_t* plane, uint8_t* out) { (void)plane; memset(out, 0, CO_FL); }
static int  FlFeeds(uint8_t* plane) { (void)plane; return 0; }
#endif

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
#define CO_SLOT_BADVER 0xFD                 /* ... the host runs another build of Survival (runtime 0.32.6) */

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
    char* m = (char*)malloc(n + 5);
    if (!m) return;
    int sl = slot < 0 ? 0 : slot > 99 ? 99 : slot, h = 0;      /* "<sender's slot>|<message>", the slot in decimal */
    if (sl >= 10) m[h++] = (char)('0' + sl / 10);
    m[h++] = (char)('0' + sl % 10); m[h++] = '|';
    memcpy(m + h, s, n); m[n + h] = 0;
    int32_t at = (CO.inHead + CO.inCount) % CO_INBOX;
    CO.inbox[at] = m; CO.inboxLen[at] = (uint16_t)(n + h); ++CO.inCount;
}
static void CoSys(int slot, const char* s) { CoInboxPush(slot, s, (uint32_t)CoLen(s)); }
/* (2026-11-11) A message from another game, into the Lua inbox. One that starts "sys" ("sys" alone or "sys|...") is
 * refused: it has the form of this runtime's own notices (CoSys), and Lua's onMessage takes any "sys|..." as one, so a
 * joiner's "sys|slot|25" moved the host's own slot (tools/checks/coop_guard_test.lua, coop_test.c). No Lua part sends one.
 * On the reliable channel it still counts as received (its sequence moves on), or the channel would stall behind it. */
static void CoNetPush(int k, const char* d, uint32_t n)
{
    static int32_t refused;
    if (n >= 3 && d[0] == 's' && d[1] == 'y' && d[2] == 's' && (n == 3 || d[3] == '|')) {
        ++refused;
        if (refused <= 3 || refused % 100 == 0)
            Log(L"coop: player %d sent a message with the form of this runtime's own (sys|...): refused (%d so far)",
                (int32_t)k + 1, refused);
        return;
    }
    CoInboxPush(k, d, n);
}

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
    CO.players[s].jit = CO.players[s].dly = 0;
    CO.players[s].stateAt = 0;
    CO.players[s].fresh = 0;
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
    L->out[L->nout++] = (CoOut){ L->sendSeq++, (uint16_t)n, -1.0, d, 0 };
}

/* How long a reliable message waits for its ack before it goes again: the link's round trip x 1.5 + 100 ms (at least
 * 250 ms; 500 ms before the first round trip is known), doubled for each try after the first, up to 4 s. A fixed 250 ms
 * sent every message twice on links slower than that: the co-op run of 2026-10-30 resent 4-7 % on the 290-470 ms links,
 * 0-1 % on the 220-260 ms ones. */
static double CoRto(const CoLink* L, int tries)
{
    double r = L->rtt > 0 ? L->rtt * 1.5 + 0.1 : 0.5;
    if (r < 0.25) r = 0.25;
    for (int i = 1; i < tries && r < 4.0; ++i) r *= 2.0;
    return r > 4.0 ? 4.0 : r;
}

/* The reliable messages due (new, or their ack overdue: CoRto), up to 16 a call. A lost link gets its oldest one only,
 * as a probe, so a dead link isn't flooded: the same run sent Shazzy's lost link 20,892 resends in a minute (every
 * message every 250 ms, 16 a frame). */
static void CoFlushReliable(int k, double now)
{
    CoLink* L = &CO.links[k];
    int sent = 0, most = L->connected ? 16 : 1;
    for (int32_t i = 0; i < L->nout && sent < most; ++i) {
        CoOut* o = &L->out[i];
        if (o->sentAt >= 0 && now - o->sentAt < CoRto(L, o->tries)) { if (!L->connected) break; continue; }
        if (o->sentAt >= 0) ++L->resent;
        if (o->tries < 255) ++o->tries;
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
    if (below > L->ackedBelow) {                              /* the link answers: what's left waits one round trip again */
        L->ackedBelow = below;
        for (int32_t i = 0; i < L->nout; ++i) if (L->out[i].tries > 1) L->out[i].tries = 1;
    }
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
    CoNetPush(k, d, n); ++L->recvNext;
    for (;;) {
        int slot = (int)(L->recvNext % CO_OOO);
        if (!L->ooo[slot] || L->oooSeq[slot] != L->recvNext) break;
        CoNetPush(k, L->ooo[slot], L->oooLen[slot]);
        free(L->ooo[slot]); L->ooo[slot] = NULL; ++L->recvNext;
    }
}

/* A state from another game, before it may move anything (security review of 2026-10-26): a position that isn't a
 * finite number within 100,000 km, or a rotation that isn't about a unit quaternion, from a broken or hostile game,
 * would go straight to the plane's teleport. */
static int CoSaneState(const double* p, const float* q)
{
    for (int c = 0; c < 3; ++c) if (!(p[c] > -1e10 && p[c] < 1e10)) return 0;    /* (false for NaN too) */
    double n = 0;
    for (int c = 0; c < 4; ++c) { if (!(q[c] >= -1.01f && q[c] <= 1.01f)) return 0; n += (double)q[c] * q[c]; }
    return n > 0.5 && n < 1.5;
}

static void CoPushSnap(CoEnt* e, double t, const double* p, const float* q, double now)
{
    if (!CoSaneState(p, q)) { ++CO.badPk; return; }
    if (e->ns && t <= e->s[e->ns - 1].t) return;              /* old or repeated */
    if (e->ns == CO_SNAPS) { memcpy(&e->s[0], &e->s[1], sizeof(CoSnap) * (CO_SNAPS - 1)); --e->ns; }
    CoSnap* s = &e->s[e->ns++];
    s->t = t; memcpy(s->p, p, 24); memcpy(s->q, q, 16);
    e->lastRecv = now;
}

/* The interpolation delay adapts to each sender's lateness (how much later than its fastest a state comes): the co-op
 * run of 2026-10-30 ran on Steam relays with 220-800 ms round trips, and a fixed CO.delay (120 ms) drew a plane past its
 * newest state whenever one came later than that. The delay follows the lateness + 30 ms, from CO.delay up to
 * CO_DELAY_MAX, moving at most 0.1 s a second so nothing jumps. A hitch on this game (a frame over 0.1 s) isn't counted:
 * what came during it is read late but drawn in time. */
#define CO_DELAY_MAX 0.30
static void CoTrackOffset(CoPlayer* P, double senderT, double now)
{
    double est = now - senderT;
    if (!P->haveOffset || est < P->offset) { P->offset = est; P->haveOffset = 1; }
    else P->offset += (est - P->offset) * 0.001;              /* let go slowly (clock drift, a slower route) */
    double late = est - P->offset;
    if (CO.frameGap > 0.1 || !(late >= 0 && late < 2.0)) return;
    P->jit += (late - P->jit) * (late > P->jit ? 0.3 : 0.005);
}
static double CoRenderDelay(const CoPlayer* P) { return P->dly > 0 ? P->dly : CO.delay; }
static void CoAdaptDelay(CoPlayer* P, double dt)
{
    double want = P->jit + 0.03, step = (dt > 0.1 ? 0.1 : dt) * 0.1;
    if (want < CO.delay) want = CO.delay;
    if (want > CO_DELAY_MAX) want = CO_DELAY_MAX > CO.delay ? CO_DELAY_MAX : CO.delay;
    double d = CoRenderDelay(P);
    d += want > d + step ? step : want < d - step ? -step : want - d;
    P->dly = d;
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

/* The joiner's build is this game's (their mod version, as each game's SV_CoopOpen gave it: Survival's VERSION with the
 * co-op tag). Another build is turned away (the user, 2026-10-31: "add the refuse mismatched builds"; two players on
 * 0.73.26 had joined a 0.73.27 host, whose crash fix their games lacked). A host with no version given takes anyone. */
static int CoSameVer(const char* ver)
{
    if (!CO.myVer[0]) return 1;
    for (int i = 0; i < 32; ++i) {
        if (ver[i] != CO.myVer[i]) return 0;
        if (!ver[i]) return 1;
    }
    return 1;
}
/* (the host) a joiner of another build turned away: logged, and told to Lua ("sys|refused|<name>|<their build>"), once a
 * minute per player (their hellos come every second) */
static void CoRefusedSay(uint64_t steamId, const CoSockAddr* udp, const char* name, const char* ver, double now)
{
    uint64_t id = steamId ? steamId : (udp ? ((uint64_t)udp->addr << 16 | udp->port) : 0);
    int slot = -1, old = 0;
    for (int i = 0; i < 8; ++i) {
        if (CO.refused[i].id == id) { slot = i; break; }
        if (CO.refused[i].at < CO.refused[old].at) old = i;
    }
    if (slot >= 0 && now - CO.refused[slot].at < 60.0) return;
    if (slot < 0) slot = old;
    CO.refused[slot].id = id; CO.refused[slot].at = now;
    wchar_t wn[64], wv[33], wm[33];
    CoWide(name, wn, 64); CoWide(ver, wv, 33); CoWide(CO.myVer, wm, 33);
    Log(L"coop: refused %s: their Survival is %s, this game's %s (another build doesn't link)", wn, wv, wm);
    char m[128] = "sys|refused|", *d = m + 12;
    for (const char* c = name; *c && d < m + 12 + 40; ++c) *d++ = (*c == '|' || (unsigned char)*c < 0x20) ? '?' : *c;
    *d++ = '|';
    for (const char* c = ver; *c && d < m + sizeof(m) - 1; ++c) *d++ = (*c == '|' || (unsigned char)*c < 0x20) ? '?' : *c;
    *d = 0;
    CoSys(0, m);
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
            Log(L"coop: %s is also the %s; only one of you picks SURVIVAL CO-OP: HOST, the others JOIN", wn,
                role == CO_ROLE_HOST ? L"host" : L"joiner");
            CoSys(0, "sys|samerole");
        }
        return;
    }
    if (CO.role == CO_ROLE_HOST) {                            /* a joiner */
        if (k < 0 && !CoSameVer(ver)) {                       /* another build: turned away, told the host's */
            CoHelloTo(steamId, udp, NULL, CO_SLOT_BADVER, now);
            CoRefusedSay(steamId, udp, name, ver, now);
            return;
        }
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
        if (yourSlot == CO_SLOT_BADVER || (k < 0 && !CoSameVer(ver))) {   /* (an older host doesn't refuse: this game does) */
            if (!CO.badVerSaid) {
                CO.badVerSaid = 1;
                char m[64] = "sys|badver|";
                CoCopy(m + 11, sizeof(m) - 11, ver, CoLen(ver));
                for (char* c = m + 11; *c; ++c) if (*c == '|' || (unsigned char)*c < 0x20) *c = '?';
                wchar_t wv[33], wm[33];
                CoWide(ver, wv, 33); CoWide(CO.myVer, wm, 33);
                Log(L"coop: the host runs Survival %s and this game %s: it won't link with another build (update to the host's)", wv, wm);
                CoSys(0, m);
            }
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
            char m[24] = "sys|slot|", *d = m + 9;
            if (yourSlot >= 10) *d++ = (char)('0' + yourSlot / 10);
            *d++ = (char)('0' + yourSlot % 10); *d = 0;
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

static void CoQRec(uint8_t* r, int slot, uint32_t ms, const double* pos, const float* q, int32_t hp, float maxHp, uint32_t flags,
                   const uint8_t* fl)
{
    r[0] = (uint8_t)slot;
    memcpy(r + 1, &ms, 4); memcpy(r + 5, pos, 24);
    for (int c = 0; c < 4; ++c) {
        float v = q[c] < -1 ? -1 : q[c] > 1 ? 1 : q[c];
        int16_t i = (int16_t)(v * 32767.0f); memcpy(r + 29 + c * 2, &i, 2);
    }
    memcpy(r + 37, &hp, 4); memcpy(r + 41, &maxHp, 4); memcpy(r + 45, &flags, 4);
    if (fl) memcpy(r + 49, fl, CO_FL); else memset(r + 49, 0, CO_FL);
}

static void CoOnPlayer(int src, uint32_t ms, const double* pos, const float* q, int32_t hp, float maxHp, uint32_t flags,
                       const uint8_t* fl, double now)
{
    if (src < 0 || src >= CO_MAX_PLAYERS || src == CO.mySlot) return;
    if (!CoSaneState(pos, q)) { ++CO.badPk; return; }          /* (not kept, not relayed) */
    if (!(maxHp >= 0 && maxHp < 1e9f)) maxHp = 0;
    CoPlayer* P = &CO.players[src];
    double t = CoPeerTime(ms);
    CoTrackOffset(P, t, now);
    CoPushSnap(&P->plane, t, pos, q, now);
    P->hp = hp; P->maxHp = maxHp; P->flags = flags; P->stateAt = now;
    if (fl) { memcpy(P->fl, fl, CO_FL); P->hasFl = 1; }
    if (CO.role == CO_ROLE_HOST) { CoQRec(P->rec, src, ms, pos, q, hp, maxHp, flags, fl); P->fresh = 1; }
}

#define CO_P_SIZE (4 + 60 + CO_FL)          /* 'P': slot, 3 spare, time, position, rotation, health, max health, flags,
                                               the flight block */

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
        CoNetPush(k, (const char*)p + 2, CoGet16(p));
        return;
    case 'P': {                                                /* a joiner's own plane (the host knows it by its link) */
        if (CO.role != CO_ROLE_HOST) return;
        if (n < CO_P_SIZE) { ++CO.badPk; return; }
        double pos[3]; float q[4]; int32_t hp; float maxHp;
        memcpy(pos, p + 8, 24); memcpy(q, p + 32, 16); memcpy(&hp, p + 48, 4); memcpy(&maxHp, p + 52, 4);
        CoOnPlayer(k, CoGet32(p + 4), pos, q, hp, maxHp, CoGet32(p + 56), p + 60, now);
        return;
    }
    case 'Q': {                                                /* the host's batch: everyone else's planes */
        if (CO.role != CO_ROLE_JOIN || k != 0) return;
        if (n < 5 || 5u + p[0] * (uint32_t)CO_Q_REC > n) { ++CO.badPk; return; }
        const uint8_t* r = p + 1;
        for (uint32_t i = 0; i < p[0]; ++i, r += CO_Q_REC) {
            double pos[3]; float q[4]; int32_t hp; float maxHp;
            memcpy(pos, r + 5, 24);
            for (int c = 0; c < 4; ++c) { int16_t v; memcpy(&v, r + 29 + c * 2, 2); q[c] = v / 32767.0f; }
            memcpy(&hp, r + 37, 4); memcpy(&maxHp, r + 41, 4);
            CoOnPlayer(r[0], CoGet32(r + 1), pos, q, hp, maxHp, CoGet32(r + 45), r + 49, now);
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
    char names[24][64]; uint64_t ids[24]; int nn = 0;
    for (const char* s = CO.partner; *s && nn < 24; ) {    /* the partner list (24: every player of a session, host migration) */
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
    for (int i = 0; i < nn && CO.ncand < CO_MAX_CAND; ++i) if (ids[i]) CO.cand[CO.ncand++] = ids[i];
    uint32_t app = ST.appId && ST.utils ? ST.appId(ST.utils) : 0;
    int32_t fc = ST.friendCount(ST.friends, 4 /* k_EFriendFlagImmediate */);
    for (int32_t i = 0; i < fc && CO.ncand < CO_MAX_CAND; ++i) {
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
    uint8_t fl[CO_FL];
    FlFlightBlock(me, fl);
    if (CO.role == CO_ROLE_HOST) { CoQRec(CO.players[0].rec, 0, CoMs(now), pos, q, hp, maxHp, CO.meFlags, fl); CO.players[0].fresh = 1; return; }
    uint8_t b[CO_P_SIZE], *p = CoHeader(b, 'P');
    *p++ = (uint8_t)(CO.mySlot >= 0 ? CO.mySlot : CO_SLOT_NONE); *p++ = 0; *p++ = 0; *p++ = 0;
    CoPut32(&p, CoMs(now));
    memcpy(p, pos, 24); p += 24;
    memcpy(p, q, 16); p += 16;
    memcpy(p, &hp, 4); p += 4;
    memcpy(p, &maxHp, 4); p += 4;
    CoPut32(&p, CO.meFlags);
    memcpy(p, fl, CO_FL); p += CO_FL;
    for (int k = 0; k < CO_MAX_PLAYERS; ++k) if (CO.links[k].used && CO.links[k].connected) CoSendTo(k, b, CO_P_SIZE);
}

/* (the host) whether joiner j gets the planes and the enemies: its link answers and its own plane came in the last 3 s,
 * in Survival's level. A joiner in the menus, loading or on another build sends no plane and drew nothing of them: the
 * co-op run of 2026-10-30 sent 500-880 KB a minute for 14 minutes to a player on the old build at the main menu, and
 * ~590 KB a minute to cressendo through a 2.3-minute load. The reliable messages and hellos go on as ever. */
static int CoWantsState(int j, double now)
{
    const CoPlayer* P = &CO.players[j];
    return CO.links[j].used && CO.links[j].connected && P->stateAt > 0 && now - P->stateAt < 3.0 && (P->flags & CO_FLAG_LEVEL);
}

/* the host: Q to each joiner with every player's state since the last batch, the joiner's own left out (as many
 * packets as it takes: 19 records of 62 bytes fit one, protocol 4) */
static void CoSendPlanes(double now)
{
    for (int j = 1; j < CO_MAX_PLAYERS; ++j) {
        if (!CoWantsState(j, now)) continue;
        uint8_t b[CO_MAX_PACKET], *p = CoHeader(b, 'Q'), *cnt = p++;
        *cnt = 0;
        for (int s = 0; s < CO_MAX_PLAYERS; ++s) {
            if (s == j || !CO.players[s].fresh || (s && !CO.links[s].used)) continue;
            if ((size_t)(p - b) + CO_Q_REC > CO_MAX_PACKET) {
                CoSendTo(j, b, (uint32_t)(p - b));
                p = CoHeader(b, 'Q'); cnt = p++; *cnt = 0;
            }
            memcpy(p, CO.players[s].rec, CO_Q_REC); p += CO_Q_REC; ++*cnt;
        }
        if (*cnt) CoSendTo(j, b, (uint32_t)(p - b));
    }
    for (int s = 0; s < CO_MAX_PLAYERS; ++s) CO.players[s].fresh = 0;
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
            for (int k = 1; k < CO_MAX_PLAYERS; ++k) if (CoWantsState(k, now)) CoSendTo(k, b, (uint32_t)(p - b));
            p = NULL;
        }
    }
    if (p && cnt) {
        memcpy(countAt, &cnt, 2);
        for (int k = 1; k < CO_MAX_PLAYERS; ++k) if (CoWantsState(k, now)) CoSendTo(k, b, (uint32_t)(p - b));
    }
}

/* where the stream was at render time rt (its sender's clock); 0 if it has nothing yet */
/* (1 between two snapshots or before the first, 2 past the newest: on along its velocity, 3 over 0.5 s past it: held) */
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
        return ahead >= 0.5 ? 3 : ahead > 0.001 ? 2 : 1;
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

/* Moves one puppet to where its stream was at rt; the actor if it was moved, else NULL. */
static uint8_t* CoDriveOne(CoEnt* e, double rt)
{
    uint8_t* o = CoRefGet(&e->ref);
    if (!o) { if (e->ref.obj) { e->ref.obj = NULL; Log(L"coop: a puppet's actor is gone (stream %d); unbound", (int32_t)e->id); } return NULL; }
    if (CoHealth(o) <= 0) return NULL;                        /* going down: let it fall */
    double pos[3], rot[3]; float q[4];
    int how = CoSample(e, rt, pos, q);
    if (!how) return NULL;
    CoQuatToRot(q, rot);
    if (CoTeleport(o, pos, rot)) { ++e->drives; e->ahead += how >= 2; e->held += how == 3; return o; }
    ++e->fails;
    return NULL;
}

static void CoDrive(double now)
{
    for (int s = 0; s < CO_MAX_PLAYERS; ++s) {
        CoPlayer* P = &CO.players[s];
        if (s == CO.mySlot || !P->plane.ref.obj || !P->haveOffset) continue;
        CoAdaptDelay(P, CO.frameGap);
        if (FlFeeds(CoRefGet(&P->plane.ref))) continue;       /* a real player plane: its own update flies it (flight.c) */
        uint8_t* o = CoDriveOne(&P->plane, now - P->offset - CoRenderDelay(P));
        /* the move turned an AI stand-in's afterburner off (CoAbOffset): set from that player's latest flags */
        if (!o || CoKind(o) != 1) continue;
        int32_t ab = CoAbOffset();
        if (ab <= 0 || !Readable(o + ab, 1)) continue;
        uint8_t on = (P->flags & CO_FLAG_AB) ? 1 : 0;
        o[ab] = on;
        if (on && !P->abSaid) { P->abSaid = 1; Log(L"coop: player %d's afterburner on: their stand-in %p, byte +%x (flags %x)", s + 1, o, (uint32_t)ab, P->flags); }
    }
    if (CO.role != CO_ROLE_JOIN || !CO.players[0].haveOffset) return;
    if (!CO.players[0].plane.ref.obj) CoAdaptDelay(&CO.players[0], CO.frameGap);   /* (else done above, once a frame) */
    double rt = now - CO.players[0].offset - CoRenderDelay(&CO.players[0]);   /* the host's enemies, on the host's clock */
    for (int i = 0; i < CO_MAX_ENTS; ++i) if (CO.ents[i].used && CO.ents[i].ref.obj) CoDriveOne(&CO.ents[i], rt);
}

#define CO_DROP_S 90.0                      /* lost this long: the link is let go (the slot is free again) */

static void CoStep(double now, int drive)
{
    CO.frameGap = CO.prevStep > 0 ? now - CO.prevStep : 0;    /* (before the pump: CoTrackOffset skips a hitch's states) */
    CO.prevStep = now;
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
    for (int k = 0; k < CO_MAX_PLAYERS; ++k) if (CO.links[k].used) ++linked;
    if (linked) {
        double hz = CO.role == CO_ROLE_HOST && linked + 1 > CO_FAST_UPTO ? 20.0 : 30.0;
        if (now - CO.lastPlayerSend >= 1.0 / hz) {
            CO.lastPlayerSend = now;
            CoSendPlayer(now);
            if (CO.role == CO_ROLE_HOST) CoSendPlanes(now);
        }
        if (CO.role == CO_ROLE_HOST && now - CO.lastEntSend >= 1.0 / 15.0) { CO.lastEntSend = now; CoSendEnts(now); }
    }
    if (drive) CoDrive(now);
    if (now - CO.lastStats >= 60.0) {
        CO.lastStats = now;
        int32_t bound = 0, drives = 0, fails = 0, minute = 0, ahead = 0, held = 0;
        for (int i = 0; i < CO_MAX_ENTS; ++i) {
            CoEnt* e = &CO.ents[i];
            if (!e->used || !e->ref.obj) continue;
            ++bound; drives += e->drives; fails += e->fails;
            minute += e->drives - e->mark; ahead += e->ahead; held += e->held;
            e->mark = e->drives; e->ahead = e->held = 0;
        }
        const CoPlayer* H = &CO.players[0];
        Log(L"coop: you are player %d; %d enemy streams bound (%d moves, %d failed); %u bad packets; enemies drawn %d ms behind "
            L"the host (lateness %d ms); the last minute's %d enemy moves: %d past their newest state, %d held", CO.mySlot + 1,
            bound, drives, fails, CO.badPk, (int32_t)(CoRenderDelay(H) * 1000), (int32_t)(H->jit * 1000), minute, ahead, held);
        for (int k = 0; k < CO_MAX_PLAYERS; ++k) {
            CoLink* L = &CO.links[k];
            if (!L->used) continue;
            wchar_t wn[64]; CoWide(L->name, wn, 64);
            Log(L"coop:   player %d %s: %s, rtt %d ms; sent %u packets (%u KB), got %u (%u KB), %u resent; their plane %d moves",
                k + 1, wn, L->connected ? L"linked" : L"link lost", (int32_t)(L->rtt * 1000), L->txPk, L->txB / 1024, L->rxPk,
                L->rxB / 1024, L->resent, CO.players[k].plane.drives);
        }
        /* each other player's plane here: drawn how far behind, how late their states came, the last minute's moves past
         * their newest state of all its moves */
        char line[480]; CoBuf b = { line, line + sizeof(line) - 1 };
        int any = 0;
        for (int s = 0; s < CO_MAX_PLAYERS; ++s) {
            CoPlayer* P = &CO.players[s];
            if (s == CO.mySlot || !P->plane.ref.obj || !P->haveOffset) continue;
            CoEnt* e = &P->plane;
            if (any) CoPutS(&b, "; ");
            CoPutI(&b, s + 1); CoPutS(&b, " "); CoPutI(&b, (int64_t)(CoRenderDelay(P) * 1000)); CoPutS(&b, "/");
            CoPutI(&b, (int64_t)(P->jit * 1000)); CoPutS(&b, " ms "); CoPutI(&b, e->ahead); CoPutS(&b, "/"); CoPutI(&b, e->drives - e->mark);
            e->mark = e->drives; e->ahead = e->held = 0;
            any = 1;
        }
        *b.p = 0;
        if (any) {
            wchar_t wl[480]; CoWide(line, wl, 480);
            Log(L"coop: planes here (player drawn-behind/lateness ms past/moves, the last minute): %s", wl);
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

#include "coop_lua.c"                               /* co-op's Lua functions and the second player plane */
