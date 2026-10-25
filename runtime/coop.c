/* =============================================================================
 *  Survival COOP: the native half of two-player co-op (runtime 0.20.0; tools/re/COOP.md). Included by survival_rt.c.
 *
 *  Host-authoritative, after Double Trigger, the AC7 co-op mod (layer10-love/double-trigger, MIT / Unlicense): the
 *  host's game runs the rounds and the enemies, the joiner's game mirrors them. This file is the transport and the
 *  per-frame work; Scripts/sv_coop.lua decides what is mirrored.
 *
 *  Transport: Steam P2P (ISteamNetworking v006 through steam_api64's flat API: SendP2PPacket / ReadP2PPacket on a
 *  channel of our own, no callbacks: a session is accepted by sending to that user and AcceptP2PSessionWithUser), or
 *  UDP (ws2_32, loaded at run time: LAN or a VPN, the host listens on a port). Every packet starts with
 *  'S', CO_PROTO, a type and a flags byte:
 *    H hello (1 s): role, session nonce, mod version, name, time + echo of the peer's last hello (the round trip)
 *    L reliable Lua message: sender nonce, seq, length, bytes (ours: resent every 250 ms until acked, in order)
 *    K ack: sender nonce, every seq below this one arrived
 *    U unreliable Lua message
 *    P the sender's own plane (30 Hz): time, position (cm, doubles), rotation (quaternion), health, Lua's flags
 *    E the host's tracked enemies (15 Hz): time, n x {id, position (floats), rotation (int16 quaternion)}
 *  Puppets: a local AI plane bound to a stream (the peer's plane, or a host enemy on the joiner's game) is moved every
 *  frame to where the stream says it was CO_DELAY ago (snapshot interpolation, nlerp), through the AI plane's own
 *  teleport (vtable slot 315: the flight model flies on from there, hard rule 39), late in the frame (the music
 *  player's tickable, after every actor's tick), so it draws where the stream puts it.
 *  All of it runs on the game thread: the Lua calls come from Survival's ExecuteInGameThread tick, the frame work from
 *  the music player's tick (OnMusicTick).
 * ============================================================================= */

#define CO_PROTO        1
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

static struct {
    int      open, mode, role;
    uint32_t nonce;
    char     partner[96];
    double   delay;                         /* interpolation delay, seconds */
    uint16_t port;
    /* the peer */
    int      havePeer, connected;
    uint64_t peerId;
    CoSockAddr peerAddr;
    uint32_t peerNonce;
    int      peerRole;
    char     peerName[64], peerVer[32];
    double   lastRecv, lastHello, lastDiscover, lastFrame, lastPlayerSend, lastEntSend, lastStats, lastResend;
    uint64_t cand[16]; int32_t ncand;
    uint32_t helloT, helloRecvT; double helloRecvAt; double rtt;
    char     myVer[32], myName[64];
    uint64_t myId;
    /* reliable channel */
    uint32_t sendSeq, ackedBelow, recvNext;
    int      ackDue;
    CoOut    out[CO_RELIABLE]; int32_t nout;
    char*    ooo[CO_OOO]; uint16_t oooLen[CO_OOO]; uint32_t oooSeq[CO_OOO];
    /* Lua inbox */
    char*    inbox[CO_INBOX]; uint16_t inboxLen[CO_INBOX]; int32_t inHead, inCount;
    /* clock offset to the peer: local time - peer time, the smallest seen (slowly let go of) */
    double   offset; int haveOffset;
    /* streams */
    CoRef    me; uint32_t meFlags;
    CoEnt    peer;                          /* the peer's own plane */
    int32_t  peerHp; float peerMaxHp; uint32_t peerFlags; double peerT;
    CoEnt    ents[CO_MAX_ENTS];
    int32_t  nTrack;
    /* stats */
    uint32_t txPk, rxPk, txB, rxB, badPk, resent;
    int      warnedTele;
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

/* Whether obj is an AI plane with the game's own teleport in both slots (any other class: never teleported). */
static int CoCanDrive(uint8_t* obj)
{
    if (!g_fAITeleportTo || !g_fAITeleportInner || !obj) return 0;
    void** vt = *(void***)obj;
    if (!Readable(vt, 8 * (VT_TELEPORT_IN + 1))) return 0;
    return vt[VT_TELEPORT_TO] == (void*)g_fAITeleportTo && vt[VT_TELEPORT_IN] == (void*)g_fAITeleportInner;
}

typedef uint8_t (*CoTeleportFn)(void* self, const double* loc, const double* rot, uint8_t isTest, uint8_t noCheck);

/* ---- packets ---------------------------------------------------------------------------------------------------- */
static void CoRawSend(const uint8_t* data, uint32_t n)
{
    if (!CO.havePeer || n > CO_MAX_PACKET) return;
#ifdef COOP_TEST
    if (CoTestDrop()) return;                                 /* (tools/checks/coop_test.c: a lossy link) */
#endif
    int ok = 0;
    if (CO.mode == CO_MODE_STEAM && ST.state > 0) ok = ST.send(ST.net, CO.peerId, data, n, 0 /* unreliable */, CO_CHANNEL);
    else if (CO.mode == CO_MODE_UDP && WS.sock) ok = WS.sendto(WS.sock, (const char*)data, (int32_t)n, 0, &CO.peerAddr, sizeof(CO.peerAddr)) == (int32_t)n;
    if (ok) { ++CO.txPk; CO.txB += n; }
}

static uint8_t* CoHeader(uint8_t* b, uint8_t type) { b[0] = CO_MAGIC; b[1] = CO_PROTO; b[2] = type; b[3] = 0; return b + 4; }
static void CoPut32(uint8_t** p, uint32_t v) { memcpy(*p, &v, 4); *p += 4; }
static void CoPut16(uint8_t** p, uint16_t v) { memcpy(*p, &v, 2); *p += 2; }
static uint32_t CoGet32(const uint8_t* p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint16_t CoGet16(const uint8_t* p) { uint16_t v; memcpy(&v, p, 2); return v; }
static uint32_t CoMs(double t) { return (uint32_t)(uint64_t)(t * 1000.0); }

static void CoHelloTo(uint64_t steamId, const CoSockAddr* udp, double now)
{
    uint8_t b[160], *p = CoHeader(b, 'H');
    *p++ = (uint8_t)CO.role;
    CoPut32(&p, CO.nonce);
    CoPut32(&p, CoMs(now));
    CoPut32(&p, CO.helloRecvT);
    CoPut32(&p, CO.helloRecvAt > 0 ? CoMs(now - CO.helloRecvAt) : 0);
    char ver[32] = { 0 }, name[64] = { 0 };
    CoCopy(ver, sizeof(ver), CO.myVer, CoLen(CO.myVer));
    CoCopy(name, sizeof(name), CO.myName, CoLen(CO.myName));
    memcpy(p, ver, 32); p += 32;
    memcpy(p, name, 64); p += 64;
    uint32_t n = (uint32_t)(p - b);
    if (CO.mode == CO_MODE_STEAM && ST.state > 0) { if (ST.send(ST.net, steamId, b, n, 0, CO_CHANNEL)) { ++CO.txPk; CO.txB += n; } }
    else if (CO.mode == CO_MODE_UDP && WS.sock && udp) { if (WS.sendto(WS.sock, (const char*)b, (int32_t)n, 0, udp, sizeof(*udp)) == (int32_t)n) { ++CO.txPk; CO.txB += n; } }
}

static void CoInboxPush(const char* s, uint32_t n)
{
    if (CO.inCount >= CO_INBOX) { Log(L"coop: Lua inbox full; a message was dropped"); return; }
    char* m = (char*)malloc(n + 1);
    if (!m) return;
    memcpy(m, s, n); m[n] = 0;
    int32_t at = (CO.inHead + CO.inCount) % CO_INBOX;
    CO.inbox[at] = m; CO.inboxLen[at] = (uint16_t)n; ++CO.inCount;
}
static void CoSys(const char* s) { CoInboxPush(s, (uint32_t)CoLen(s)); }

static void CoResetReliable(void)
{
    for (int32_t i = 0; i < CO.nout; ++i) free(CO.out[i].data);
    CO.nout = 0;
    for (int i = 0; i < CO_OOO; ++i) { if (CO.ooo[i]) free(CO.ooo[i]); CO.ooo[i] = NULL; }
    CO.sendSeq = 1; CO.ackedBelow = 1; CO.recvNext = 1; CO.ackDue = 0;
}

/* A new peer or peer session: what came from the old one goes (snapshots, its clock); the actors stay tracked and
 * bound (the host's enemies already up are streamed to a joiner that arrives later; Lua rebinds or unbinds). */
static void CoResetStreams(void)
{
    CO.peer.ns = 0;
    for (int i = 0; i < CO_MAX_ENTS; ++i) {
        CO.ents[i].ns = 0;
        if (CO.ents[i].used && !CO.ents[i].ref.obj) memset(&CO.ents[i], 0, sizeof(CO.ents[i]));
    }
    CO.haveOffset = 0; CO.peerT = 0;
}
static void CoClearAll(void)                              /* a new level: nothing of the old one is valid */
{
    memset(&CO.peer, 0, sizeof(CO.peer));
    memset(CO.ents, 0, sizeof(CO.ents));
    CO.nTrack = 0; CO.haveOffset = 0; CO.peerT = 0;
}

static void CoSendLua(const char* s, uint32_t n, int reliable)
{
    if (n > CO_MAX_LUA) n = CO_MAX_LUA;
    if (!reliable) {
        uint8_t b[CO_MAX_PACKET], *p = CoHeader(b, 'U');
        CoPut16(&p, (uint16_t)n); memcpy(p, s, n); p += n;
        CoRawSend(b, (uint32_t)(p - b));
        return;
    }
    if (CO.nout >= CO_RELIABLE) { Log(L"coop: reliable queue full; a message was dropped"); return; }
    char* d = (char*)malloc(n ? n : 1);
    if (!d) return;
    memcpy(d, s, n);
    CO.out[CO.nout++] = (CoOut){ CO.sendSeq++, (uint16_t)n, -1.0, d };
}

static void CoFlushReliable(double now)
{
    int sent = 0;
    for (int32_t i = 0; i < CO.nout && sent < 16; ++i) {
        CoOut* o = &CO.out[i];
        if (o->sentAt >= 0 && now - o->sentAt < 0.25) continue;
        if (o->sentAt >= 0) ++CO.resent;
        uint8_t b[CO_MAX_PACKET], *p = CoHeader(b, 'L');
        CoPut32(&p, CO.nonce); CoPut32(&p, o->seq); CoPut16(&p, o->len);
        memcpy(p, o->data, o->len); p += o->len;
        CoRawSend(b, (uint32_t)(p - b));
        o->sentAt = now; ++sent;
    }
    if (CO.ackDue) {
        uint8_t b[16], *p = CoHeader(b, 'K');
        CoPut32(&p, CO.nonce); CoPut32(&p, CO.recvNext);
        CoRawSend(b, (uint32_t)(p - b));
        CO.ackDue = 0;
    }
}

static void CoOnAck(uint32_t below)
{
    int32_t k = 0;
    for (int32_t i = 0; i < CO.nout; ++i) {
        if (CO.out[i].seq < below) free(CO.out[i].data); else CO.out[k++] = CO.out[i];
    }
    CO.nout = k;
    if (below > CO.ackedBelow) CO.ackedBelow = below;
}

static void CoOnReliable(uint32_t seq, const char* d, uint16_t n)
{
    CO.ackDue = 1;
    if (seq < CO.recvNext) return;                           /* a resend of one we have */
    if (seq != CO.recvNext) {
        if (seq - CO.recvNext >= CO_OOO) return;              /* too far ahead: it comes again */
        int slot = (int)(seq % CO_OOO);
        if (!CO.ooo[slot]) {
            CO.ooo[slot] = (char*)malloc(n ? n : 1);
            if (CO.ooo[slot]) { memcpy(CO.ooo[slot], d, n); CO.oooLen[slot] = n; CO.oooSeq[slot] = seq; }
        }
        return;
    }
    CoInboxPush(d, n); ++CO.recvNext;
    for (;;) {
        int slot = (int)(CO.recvNext % CO_OOO);
        if (!CO.ooo[slot] || CO.oooSeq[slot] != CO.recvNext) break;
        CoInboxPush(CO.ooo[slot], CO.oooLen[slot]);
        free(CO.ooo[slot]); CO.ooo[slot] = NULL; ++CO.recvNext;
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

static void CoTrackOffset(double senderT, double now)
{
    double est = now - senderT;
    if (!CO.haveOffset || est < CO.offset) { CO.offset = est; CO.haveOffset = 1; }
    else CO.offset += (est - CO.offset) * 0.001;              /* let go slowly (clock drift, a slower route) */
}

/* the sender's time (ms, u32, wraps) -> seconds on the peer's clock near the newest seen */
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

static void CoSetPeer(uint64_t steamId, const CoSockAddr* udp, int role, uint32_t nonce, const char* ver, const char* name, double now)
{
    CO.havePeer = 1; CO.peerId = steamId; if (udp) CO.peerAddr = *udp;
    CO.peerRole = role; CO.peerNonce = nonce;
    CoCopy(CO.peerVer, sizeof(CO.peerVer), ver, CoLen(ver));
    CoCopy(CO.peerName, sizeof(CO.peerName), name, CoLen(name));
    CO.lastRecv = now;
    CoResetReliable();
    CoResetStreams();
    wchar_t wn[64], wv[32];
    CoWide(name, wn, 64); CoWide(ver, wv, 32);
    Log(L"coop: paired with %s (%s, mod %s)", wn, role == CO_ROLE_HOST ? L"host" : L"joiner", wv);
    CoSys("sys|paired");
}

static void CoOnHello(const uint8_t* b, uint32_t n, uint64_t steamId, const CoSockAddr* udp, double now)
{
    if (n < 4 + 1 + 16 + 32 + 64) { ++CO.badPk; return; }
    const uint8_t* p = b + 4;
    int role = p[0];
    uint32_t nonce = CoGet32(p + 1), t = CoGet32(p + 5), echo = CoGet32(p + 9), echoAge = CoGet32(p + 13);
    char ver[33], name[65];
    memcpy(ver, p + 17, 32); ver[32] = 0;
    memcpy(name, p + 49, 64); name[64] = 0;
    if (role != CO_ROLE_HOST && role != CO_ROLE_JOIN) return;
#ifdef COOP_TEST
    { static uint32_t last; if (nonce != last) { last = nonce; Log(L"test: hello from role %d nonce %x (n %u, from %x:%d)", role, nonce, n, udp ? udp->addr : 0, udp ? (int32_t)CoBE16(udp->port) : 0); } }
#endif
    if (CO.havePeer && ((CO.mode == CO_MODE_STEAM && steamId != CO.peerId) ||
                        (CO.mode == CO_MODE_UDP && udp && (udp->addr != CO.peerAddr.addr || udp->port != CO.peerAddr.port)))) return;   /* someone else */
    if (!CO.havePeer) {
        if (role == CO.role) {
            static double warned;
            if (now - warned > 10) {
                warned = now;
                wchar_t wn[64]; CoWide(name, wn, 64);
                Log(L"coop: %s is also set up as the %s; one of you must be the host and the other the joiner (config\\survival.ini [coop] role)",
                    wn, role == CO_ROLE_HOST ? L"host" : L"joiner");
                CoSys("sys|samerole");
            }
            return;
        }
        CoSetPeer(steamId, udp, role, nonce, ver, name, now);
    } else if (nonce != CO.peerNonce) {
        Log(L"coop: the peer's game started a new session (nonce %x -> %x); starting over", CO.peerNonce, nonce);
        CO.peerNonce = nonce; CO.peerRole = role;
        CoResetReliable();
        CoResetStreams();
        CoSys("sys|restart");
    }
    CO.helloRecvT = t; CO.helloRecvAt = now;
    if (echo) {
        double rtt = (double)(CoMs(now) - echo) / 1000.0 - (double)echoAge / 1000.0;
        if (rtt >= 0 && rtt < 5) CO.rtt = CO.rtt > 0 ? CO.rtt * 0.8 + rtt * 0.2 : rtt;
    }
}

static void CoOnPacket(const uint8_t* b, uint32_t n, uint64_t steamId, const CoSockAddr* udp, double now)
{
    if (n < 4 || b[0] != CO_MAGIC) { ++CO.badPk; return; }
    if (b[1] != CO_PROTO) {
        static double warned;
        if (now - warned > 10) { warned = now; Log(L"coop: the other game's co-op protocol is %d, ours %d: install the same Survival COOP build on both", (int32_t)b[1], (int32_t)CO_PROTO); CoSys("sys|protocol"); }
        return;
    }
    ++CO.rxPk; CO.rxB += n;
    if (b[2] == 'H') { CoOnHello(b, n, steamId, udp, now); return; }
    if (!CO.havePeer) return;
    if (CO.mode == CO_MODE_STEAM && steamId != CO.peerId) return;
    if (CO.mode == CO_MODE_UDP && udp && (udp->addr != CO.peerAddr.addr || udp->port != CO.peerAddr.port)) return;
    CO.lastRecv = now;
    const uint8_t* p = b + 4;
    switch (b[2]) {
    case 'L':
        if (n < 14 || CoGet32(p) != CO.peerNonce) return;
        if (10u + CoGet16(p + 8) > n - 4) { ++CO.badPk; return; }
        CoOnReliable(CoGet32(p + 4), (const char*)p + 10, CoGet16(p + 8));
        return;
    case 'K':
        if (n < 12 || CoGet32(p) != CO.peerNonce) return;
        CoOnAck(CoGet32(p + 4));
        return;
    case 'U':
        if (n < 6 || 2u + CoGet16(p) > n - 4) { ++CO.badPk; return; }
        CoInboxPush((const char*)p + 2, CoGet16(p));
        return;
    case 'P': {
        if (n < 4 + 4 + 24 + 16 + 4 + 4 + 4) { ++CO.badPk; return; }
        double t = CoPeerTime(CoGet32(p)), pos[3]; float q[4];
        memcpy(pos, p + 4, 24); memcpy(q, p + 28, 16);
        CoTrackOffset(t, now);
        CoPushSnap(&CO.peer, t, pos, q, now);
        memcpy(&CO.peerHp, p + 44, 4); memcpy(&CO.peerMaxHp, p + 48, 4); CO.peerFlags = CoGet32(p + 52); CO.peerT = now;
        return;
    }
    case 'E': {
        if (n < 10) { ++CO.badPk; return; }
        double t = CoPeerTime(CoGet32(p));
        uint32_t k = CoGet16(p + 4);
        if (10 + k * 22u > n) { ++CO.badPk; return; }
        CoTrackOffset(t, now);
        const uint8_t* e = p + 6;
        for (uint32_t i = 0; i < k; ++i, e += 22) {
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

static void CoPump(double now)
{
    uint8_t buf[CO_MAX_PACKET + 64];
    if (CO.mode == CO_MODE_STEAM && ST.state > 0) {
        uint32_t size = 0;
        for (int i = 0; i < 256 && ST.avail(ST.net, &size, CO_CHANNEL); ++i) {
            uint64_t from = 0; uint32_t got = 0;
            if (size > sizeof(buf)) {                       /* not ours: read it away */
                static uint8_t big[16384];
                ST.read(ST.net, big, sizeof(big), &got, &from, CO_CHANNEL);
                ++CO.badPk;
                continue;
            }
            if (!ST.read(ST.net, buf, sizeof(buf), &got, &from, CO_CHANNEL)) break;
            int known = CO.havePeer ? from == CO.peerId : 0;
            for (int32_t c = 0; !known && c < CO.ncand; ++c) if (CO.cand[c] == from) known = 1;
            if (!known) { ++CO.badPk; continue; }
            CoOnPacket(buf, got, from, NULL, now);
        }
    } else if (CO.mode == CO_MODE_UDP && WS.sock) {
        for (int i = 0; i < 256; ++i) {
            CoSockAddr from; int32_t fl = sizeof(from);
            int32_t got = WS.recvfrom(WS.sock, (char*)buf, (int32_t)sizeof(buf), 0, &from, &fl);
            if (got <= 0) break;
            CoOnPacket(buf, (uint32_t)got, 0, &from, now);
        }
    }
}

/* Steam: the friends to say hello to while unpaired (the partner named in the ini, or every friend in this game). */
static void CoDiscover(double now)
{
    if (CO.mode != CO_MODE_STEAM || ST.state <= 0) return;
    CO.ncand = 0;
    const char* want = CO.partner;
    uint64_t id = 0; int digits = 1;
    for (const char* s = want; *s; ++s) { if (*s < '0' || *s > '9') { digits = 0; break; } id = id * 10 + (uint64_t)(*s - '0'); }
    if (*want && digits && id > 0x0110000100000000ull) {
        CO.cand[CO.ncand++] = id;
    } else {
        int any = !*want || CoIEq(want, "auto");
        uint32_t app = ST.appId && ST.utils ? ST.appId(ST.utils) : 0;
        int32_t n = ST.friendCount(ST.friends, 4 /* k_EFriendFlagImmediate */);
        for (int32_t i = 0; i < n && CO.ncand < 16; ++i) {
            uint64_t f = ST.friendAt(ST.friends, i, 4);
            if (!f) continue;
            if (any) {
                CoFriendGame g; memset(&g, 0, sizeof(g));
                if (!ST.friendGame(ST.friends, f, &g) || !app || (uint32_t)(g.gameId & 0xFFFFFF) != app) continue;
            } else {
                const char* nm = ST.friendName(ST.friends, f);
                if (!nm || !CoIEq(nm, want)) continue;
            }
            CO.cand[CO.ncand++] = f;
        }
    }
    for (int32_t c = 0; c < CO.ncand; ++c) { ST.accept(ST.net, CO.cand[c]); CoHelloTo(CO.cand[c], NULL, now); }
    static int32_t said = -1;
    if (said != CO.ncand) {
        said = CO.ncand;
        Log(L"coop: looking for the other player: %d Steam friend(s) to try", CO.ncand);
    }
}

static void CoSendPlayer(double now)
{
    uint8_t* me = CoRefGet(&CO.me);
    double pos[3], rot[3];
    if (!me || !CoReadPose(me, pos, rot)) return;
    float q[4]; CoRotToQuat(rot, q);
    int32_t hp = CoHealth(me);
    float maxHp = g_offMaxHealth >= 0 && Readable(me + g_offMaxHealth, 4) ? *(float*)(me + g_offMaxHealth) : 0.0f;
    uint8_t b[96], *p = CoHeader(b, 'P');
    CoPut32(&p, CoMs(now));
    memcpy(p, pos, 24); p += 24;
    memcpy(p, q, 16); p += 16;
    memcpy(p, &hp, 4); p += 4;
    memcpy(p, &maxHp, 4); p += 4;
    CoPut32(&p, CO.meFlags);
    CoRawSend(b, (uint32_t)(p - b));
}

static void CoSendEnts(double now)
{
    uint8_t b[CO_MAX_PACKET], *p = NULL, *countAt = NULL;
    uint16_t k = 0;
    for (int i = 0; i < CO_MAX_ENTS; ++i) {
        CoEnt* e = &CO.ents[i];
        if (!e->used || !e->ref.obj) continue;
        uint8_t* o = CoRefGet(&e->ref);
        double pos[3], rot[3];
        if (!o || !CoReadPose(o, pos, rot)) continue;
        if (!p) { p = CoHeader(b, 'E'); CoPut32(&p, CoMs(now)); countAt = p; p += 2; k = 0; }
        float q[4]; CoRotToQuat(rot, q);
        CoPut16(&p, e->id);
        float fp[3] = { (float)pos[0], (float)pos[1], (float)pos[2] };
        memcpy(p, fp, 12); p += 12;
        for (int c = 0; c < 4; ++c) { int16_t v = (int16_t)(q[c] * 32767.0f); memcpy(p, &v, 2); p += 2; }
        ++k;
        if ((size_t)(p - b) + 22 > CO_MAX_PACKET) { memcpy(countAt, &k, 2); CoRawSend(b, (uint32_t)(p - b)); p = NULL; }
    }
    if (p && k) { memcpy(countAt, &k, 2); CoRawSend(b, (uint32_t)(p - b)); }
}

/* where the stream was at render time rt (peer clock); 0 if it has nothing yet */
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
    CoTeleportFn tp = (CoTeleportFn)(*(void***)o)[VT_TELEPORT_IN];
    if (tp(o, pos, rot, 0, 1)) ++e->drives; else ++e->fails;
}

static void CoDrive(double now)
{
    if (!CO.haveOffset) return;
    double rt = now - CO.offset - CO.delay;
    if (CO.peer.ref.obj) CoDriveOne(&CO.peer, rt);
    if (CO.role != CO_ROLE_JOIN) return;
    for (int i = 0; i < CO_MAX_ENTS; ++i) if (CO.ents[i].used && CO.ents[i].ref.obj) CoDriveOne(&CO.ents[i], rt);
}

static void CoStep(double now, int drive)
{
    CoPump(now);
    if (!CO.havePeer && now - CO.lastDiscover >= 2.0) {
        CO.lastDiscover = now;
        if (CO.mode == CO_MODE_STEAM) CoDiscover(now);
        else if (CO.mode == CO_MODE_UDP && CO.role == CO_ROLE_JOIN && CO.peerAddr.family) CoHelloTo(0, &CO.peerAddr, now);
    }
    if (CO.havePeer) {
        if (now - CO.lastHello >= 1.0) {
            CO.lastHello = now;
            if (CO.mode == CO_MODE_STEAM && ST.state > 0) ST.accept(ST.net, CO.peerId);   /* (a restarted game asks again) */
            CoHelloTo(CO.peerId, &CO.peerAddr, now);
        }
        int up = now - CO.lastRecv < CO_LOST_S;
        if (up != CO.connected) {
            CO.connected = up;
            Log(up ? L"coop: link up" : L"coop: link lost (nothing from the other player for %d s)", (int32_t)CO_LOST_S);
            CoSys(up ? "sys|up" : "sys|lost");
        }
        if (now - CO.lastPlayerSend >= 1.0 / 30.0) { CO.lastPlayerSend = now; CoSendPlayer(now); }
        if (CO.role == CO_ROLE_HOST && now - CO.lastEntSend >= 1.0 / 15.0) { CO.lastEntSend = now; CoSendEnts(now); }
        CoFlushReliable(now);
    }
    if (drive) CoDrive(now);
    if (now - CO.lastStats >= 60.0) {
        CO.lastStats = now;
        int32_t bound = 0, drives = 0, fails = 0;
        for (int i = 0; i < CO_MAX_ENTS; ++i) if (CO.ents[i].used && CO.ents[i].ref.obj) { ++bound; drives += CO.ents[i].drives; fails += CO.ents[i].fails; }
        Log(L"coop: %s, rtt %d ms; sent %u packets (%u KB), got %u (%u KB), %u bad, %u resent; %d streams bound (%d moves, %d failed), peer puppet %d moves",
            CO.connected ? L"linked" : (CO.havePeer ? L"link lost" : L"not paired"), (int32_t)(CO.rtt * 1000), CO.txPk, CO.txB / 1024,
            CO.rxPk, CO.rxB / 1024, CO.badPk, CO.resent, bound, drives, fails, CO.peer.drives);
    }
}

/* The per-frame work, from the music player's tick (OnMusicTick: once per frame for each controller; the first
 * call in a frame does it) and as a fallback from the player's flight input. */
static double g_coMusicAt;
static void CoopFrame(int fromMusic)
{
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
    CoResetReliable();
    for (int32_t i = 0; i < CO.inCount; ++i) free(CO.inbox[(CO.inHead + i) % CO_INBOX]);
    CO.inCount = 0; CO.inHead = 0;
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

/* SV_CoopOpen(mode, role, partner, port, delayMs, version) -> 1, or < 0: -1 bad args, -2 no Steam, -3 no UDP,
 * -4 bad host address. mode "steam" | "udp"; role "host" | "join"; partner: steam "auto" | a friend's name | a
 * SteamID64, udp the host's "a.b.c.d[:port]" (the joiner; the host listens on port). Opening again starts over. */
static int L_CoopOpen(void* lua)
{
    char mode[16], role[16], partner[96], ver[32];
    double port = 27777, delay = 100;
    if (!ArgBytes(lua, mode, sizeof(mode), NULL) || !ArgBytes(lua, role, sizeof(role), NULL) ||
        !ArgBytes(lua, partner, sizeof(partner), NULL)) return Ret(lua, -1);
    ArgNumber(lua, &port); ArgNumber(lua, &delay);
    if (!ArgBytes(lua, ver, sizeof(ver), NULL)) CoCopy(ver, sizeof(ver), "?", 1);
    int m = CoIEq(mode, "udp") ? CO_MODE_UDP : CoIEq(mode, "steam") ? CO_MODE_STEAM : 0;
    int r = CoIEq(role, "host") ? CO_ROLE_HOST : (CoIEq(role, "join") || CoIEq(role, "joiner") || CoIEq(role, "client")) ? CO_ROLE_JOIN : 0;
    if (!m || !r || port < 1 || port > 65535) return Ret(lua, -1);
    CoClose();
    CO.mode = m; CO.role = r;
    CO.port = (uint16_t)port;
    CO.delay = (delay < 0 ? 0 : delay > 1000 ? 1000 : delay) / 1000.0;
    CoCopy(CO.partner, sizeof(CO.partner), partner, CoLen(partner));
    CoCopy(CO.myVer, sizeof(CO.myVer), ver, CoLen(ver));
    double now = CoNow();
    CO.nonce = (uint32_t)(uint64_t)(now * 1000003.0) ^ (GetCurrentProcessId() << 16) ^ 0x5C0F;
    if (!CO.nonce) CO.nonce = 1;
    CoResetReliable();
    if (m == CO_MODE_STEAM) {
        if (!CoSteamInit()) return Ret(lua, -2);
        CO.myId = ST.myId(ST.user);
        const char* nm = ST.myName(ST.friends);
        CoCopy(CO.myName, sizeof(CO.myName), nm ? nm : "?", nm ? CoLen(nm) : 1);
    } else {
        if (!CoUdpOpen(r == CO_ROLE_HOST ? CO.port : (uint16_t)(CO.port + 1))) return Ret(lua, -3);
        if (r == CO_ROLE_JOIN && !CoParseIp(partner, &CO.peerAddr, CO.port)) { CoClose(); return Ret(lua, -4); }
        CoCopy(CO.myName, sizeof(CO.myName), "pilot", 5);
        if (ST.state >= 0 && CoSteamInit()) { const char* nm = ST.myName(ST.friends); if (nm) CoCopy(CO.myName, sizeof(CO.myName), nm, CoLen(nm)); }
    }
    CO.open = 1;
    CO.lastDiscover = -10; CO.lastStats = now;
    wchar_t wp[96], wv[32];
    CoWide(partner, wp, 96); CoWide(ver, wv, 32);
    Log(L"coop: open: %s, %s, partner \"%s\", port %d, interpolation %d ms, mod %s; teleport functions %p / %p",
        m == CO_MODE_STEAM ? L"Steam P2P" : L"UDP", r == CO_ROLE_HOST ? L"host" : L"joiner", wp, (int32_t)CO.port,
        (int32_t)(CO.delay * 1000), wv, g_fAITeleportTo, g_fAITeleportInner);
    if (!g_fAITeleportTo || !g_fAITeleportInner) Log(L"coop: the AI plane's teleport wasn't found (other game version?): planes can't be moved, the other player won't show");
    return Ret(lua, 1);
}

static int L_CoopClose(void* lua) { CoClose(); return Ret(lua, 1); }

/* SV_CoopInfo() -> "key=value;..." (open, mode, role, state, rtt, the peer's name / role / version, counters) */
static int L_CoopInfo(void* lua)
{
    double now = CoNow();
    if (CO.open && now - CO.lastFrame > 0.1) CoStep(now, 0);   /* (no frame ticks here: the menus, loading) */
    char out[600]; CoBuf b = { out, out + sizeof(out) - 1 };
    CoPutS(&b, "open="); CoPutU(&b, (uint64_t)CO.open);
    CoPutS(&b, ";mode="); CoPutS(&b, CO.mode == CO_MODE_STEAM ? "steam" : CO.mode == CO_MODE_UDP ? "udp" : "none");
    CoPutS(&b, ";role="); CoPutS(&b, CO.role == CO_ROLE_HOST ? "host" : CO.role == CO_ROLE_JOIN ? "join" : "none");
    CoPutS(&b, ";state="); CoPutS(&b, !CO.open ? "closed" : !CO.havePeer ? "searching" : CO.connected ? "linked" : "lost");
    CoPutS(&b, ";me="); CoPutU(&b, CO.myId);
    CoPutS(&b, ";cands="); CoPutI(&b, CO.ncand);
    CoPutS(&b, ";rtt="); CoPutI(&b, (int64_t)(CO.rtt * 1000));
    CoPutS(&b, ";since="); CoPutI(&b, CO.havePeer ? (int64_t)((now - CO.lastRecv) * 1000) : -1);
    CoPutS(&b, ";peerstate="); CoPutI(&b, CO.peerT > 0 ? (int64_t)((now - CO.peerT) * 1000) : -1);
    CoPutS(&b, ";bound="); { int32_t n = 0; for (int i = 0; i < CO_MAX_ENTS; ++i) if (CO.ents[i].used && CO.ents[i].ref.obj) ++n; CoPutI(&b, n); }
    CoPutS(&b, ";peerpuppet="); CoPutI(&b, CoRefGet(&CO.peer.ref) ? 1 : 0);
    CoPutS(&b, ";tele="); CoPutI(&b, g_fAITeleportTo && g_fAITeleportInner ? 1 : 0);
    CoPutS(&b, ";peerrole="); CoPutS(&b, CO.peerRole == CO_ROLE_HOST ? "host" : CO.peerRole == CO_ROLE_JOIN ? "join" : "none");
    CoPutS(&b, ";peerver="); CoPutS(&b, CO.peerVer);
    CoPutS(&b, ";peername=");                          /* last: it may hold anything but ';' is cut */
    for (const char* s = CO.peerName; *s && b.p < b.end; ++s) *b.p++ = *s == ';' ? ',' : *s;
    *b.p = 0;
    U.luaSetString(lua, out, (size_t)(b.p - out));
    return 1;
}

/* SV_CoopSend(message [, reliable]) -> 1 queued, 0 not (no peer or closed); reliable defaults to 1 */
static int L_CoopSend(void* lua)
{
    static char msg[CO_MAX_LUA + 8];
    size_t n = 0; double rel = 1;
    if (!ArgBytes(lua, msg, sizeof(msg), &n)) return Ret(lua, 0);
    ArgNumber(lua, &rel);
    if (!CO.open || !CO.havePeer) return Ret(lua, 0);
    CoSendLua(msg, (uint32_t)n, rel != 0);
    return Ret(lua, 1);
}

/* SV_CoopRecv() -> the next message from the other player (or "sys|..." from this runtime), "" when none */
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

/* SV_CoopMe(plane [, flags]) -> 1: the local player's plane (streamed to the peer), 0 = none; flags go with it */
static int L_CoopMe(void* lua)
{
    uint8_t* o = ArgObject(lua);
    double flags = 0; ArgNumber(lua, &flags);
    CO.meFlags = (uint32_t)flags;
    if (!o) { memset(&CO.me, 0, sizeof(CO.me)); return Ret(lua, 0); }
    if (CO.me.obj != o || !CoRefGet(&CO.me)) CoRefSet(&CO.me, o);
    return Ret(lua, CO.me.obj ? 1 : 0);
}

/* SV_CoopPeer(plane) -> 1 bound: that AI plane is the other player's from now on (moved every frame), -1 it isn't an
 * AI plane the runtime can move, 0 unbound (plane 0) */
static int L_CoopPeer(void* lua)
{
    uint8_t* o = ArgObject(lua);
    if (!o) { memset(&CO.peer.ref, 0, sizeof(CO.peer.ref)); return Ret(lua, 0); }
    if (!LiveObject(o) || !CoCanDrive(o)) {
        if (!CO.warnedTele) { CO.warnedTele = 1; Log(L"coop: object %p is no AI plane with the game's teleport; not bound", o); }
        return Ret(lua, -1);
    }
    CoRefSet(&CO.peer.ref, o);
    CO.peer.drives = CO.peer.fails = 0;
    Log(L"coop: the other player's plane is %p", o);
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

/* SV_CoopBind(id, plane) -> 1 (joiner: stream id moves that local copy every frame), 0 unbound, -1 not an AI plane
 * the runtime can move */
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

/* SV_CoopPeerAt() -> "x,y,z,pitch,yaw,roll,health,maxhealth,flags,age_ms" (the other player's latest state), "" none */
static int L_CoopPeerAt(void* lua)
{
    if (!CO.peer.ns) { U.luaSetString(lua, "", 0); return 1; }
    const CoSnap* s = &CO.peer.s[CO.peer.ns - 1];
    double rot[3]; CoQuatToRot(s->q, rot);
    char out[200]; CoBuf b = { out, out + sizeof(out) - 1 };
    CoPutF(&b, s->p[0], 0); CoPutS(&b, ","); CoPutF(&b, s->p[1], 0); CoPutS(&b, ","); CoPutF(&b, s->p[2], 0); CoPutS(&b, ",");
    CoPutF(&b, rot[0], 1); CoPutS(&b, ","); CoPutF(&b, rot[1], 1); CoPutS(&b, ","); CoPutF(&b, rot[2], 1); CoPutS(&b, ",");
    CoPutI(&b, CO.peerHp); CoPutS(&b, ","); CoPutF(&b, CO.peerMaxHp, 1); CoPutS(&b, ","); CoPutU(&b, CO.peerFlags); CoPutS(&b, ",");
    CoPutI(&b, (int64_t)((CoNow() - CO.peerT) * 1000));
    U.luaSetString(lua, out, (size_t)(b.p - out));
    return 1;
}

/* SV_CoopReset() -> 1: every stream, binding and the peer's puppet forgotten (a new level); the link stays */
static int L_CoopReset(void* lua)
{
    CoClearAll();
    memset(&CO.me, 0, sizeof(CO.me));
    return Ret(lua, 1);
}
