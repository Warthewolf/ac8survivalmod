/* coop_lua.c : part of coop.c (Survival COOP), #included by it in place at its end (one translation unit with
 *  survival_rt.c; tools/checks/coop_test.c and flight_test.c include coop.c and get it too). The transport's Lua
 *  functions (SV_CoopOpen .. SV_CoopReset) and a second player plane (runtime 0.21.0, tools/re/COOP.md 6): its
 *  slots swapped, loadout, paint, spawn, role, camera, name, removal, the formation test and SV_CoopFollow. */

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
    uint8_t* o = (uint8_t*)(uintptr_t)(uint64_t)a;
    /* (0.32.22, plan F1a) while the teardown gate is closed only a live object is used: one of the closing level may
     * already be freed (the main menu's own objects are live and pass) */
    if (g_teardown) {
        static uint32_t refused;
        int live = ((uintptr_t)o & 7) || !Readable(o, 0x28) ? 0 : UObjLive(o);
        if (live < 0) live = LiveObject(o);
        if (live != 1) {
            if (refused++ < 4) Log(L"teardown gate: an address from Lua refused (%p: not a live object; %u so far)", o, refused);
            return NULL;
        }
    }
    return o;
}

/* SV_CoopOpen(mode, role, partner, port, delayMs, version [, maxPlayers]) -> 1, or < 0: -1 bad args, -2 no Steam,
 * -3 no UDP, -4 bad host address. mode "steam" | "udp"; role "host" | "join"; partner: steam "auto" | Steam names or
 * SteamID64s, comma-separated; udp: the joiner's host "a.b.c.d[:port]" (the host listens on port). maxPlayers 2-24
 * (the host's; default 24). Opening again starts over. */
static int L_CoopOpen(void* lua)
{
    char mode[16], role[16], partner[640], ver[32];
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
    static char out[4096];                                     /* (23 peers of up to ~100 characters; static: no __chkstk) */
    CoBuf b = { out, out + sizeof(out) - 1 };
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

/* SV_CoopMe(plane [, flags]) -> 1: the local player's plane (streamed to the others), 0 = none; flags go with it, all 32
 * bits (CO_FLAG_* above: the other games' stand-ins for this player follow CO_FLAG_AB with their afterburner) */
static int L_CoopMe(void* lua)
{
    uint8_t* o = ArgObject(lua);
    double flags = 0; ArgNumber(lua, &flags);
    CO.meFlags = flags >= 0 && flags < 4294967296.0 ? (uint32_t)flags : 0;
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
    P->abSaid = 0; P->fed = P->fedSkip = 0; P->fedOffCm = -1;
    Log(L"coop: player %d's plane is %p (%s)", (int32_t)slot + 1, o,
        FlFeeds(o) ? L"a real player plane: its own update flies it, fed from their stream" : L"moved every frame");
    return Ret(lua, 1);
}

/* SV_CoopPeerIds() -> each linked game's "slot:steamid:rtt ms:packets sent:resent:linked" (0 / 1), comma-separated: the
 * host's joiners, a joiner's host (host migration, runtime 0.32.7: the host ranks its joiners by link quality and tells
 * everyone the order and their Steam IDs) */
static int L_CoopPeerIds(void* lua)
{
    static char out[2048];
    CoBuf b = { out, out + sizeof(out) - 1 };
    int first = 1;
    for (int k = 0; k < CO_MAX_PLAYERS; ++k) {
        CoLink* L = &CO.links[k];
        if (!L->used) continue;
        if (!first) CoPutS(&b, ",");
        first = 0;
        CoPutI(&b, k); CoPutS(&b, ":"); CoPutU(&b, L->steamId); CoPutS(&b, ":"); CoPutI(&b, (int64_t)(L->rtt * 1000));
        CoPutS(&b, ":"); CoPutU(&b, L->txPk); CoPutS(&b, ":"); CoPutU(&b, L->resent); CoPutS(&b, ":"); CoPutI(&b, L->connected ? 1 : 0);
    }
    *b.p = 0;
    U.luaSetString(lua, out, (size_t)(b.p - out));
    return 1;
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
static CoRef  g_peerPP[CO_MAX_PLAYERS], g_peerCtrl[CO_MAX_PLAYERS];    /* each player slot's real plane (COOP2MP T3) */

/* SV_CoopSwapPP(a, b) -> 1: two player slots' real planes (and their stream bindings) trade places, when a player comes
 * back in another slot (host migration, runtime 0.32.7: the plane stays theirs, never destroyed mid-level); -1 bad */
static int L_CoopSwapPP(void* lua)
{
    double a = -1, b = -1;
    if (!ArgNumber(lua, &a) || !ArgNumber(lua, &b) || a < 0 || b < 0 || a >= CO_MAX_PLAYERS || b >= CO_MAX_PLAYERS || a == b)
        return Ret(lua, -1);
    int i = (int)a, j = (int)b;
    CoRef t = g_peerPP[i]; g_peerPP[i] = g_peerPP[j]; g_peerPP[j] = t;
    t = g_peerCtrl[i]; g_peerCtrl[i] = g_peerCtrl[j]; g_peerCtrl[j] = t;
    t = CO.players[i].plane.ref; CO.players[i].plane.ref = CO.players[j].plane.ref; CO.players[j].plane.ref = t;
    Log(L"coop: player slots %d and %d's planes swapped (a player back in another slot)", i + 1, j + 1);
    return Ret(lua, 1);
}
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

/* A loadout as SV_CoopLoadout gives it, "a,b,c/d,e/x,y": the loadout object's two lists (64 at most each), then its two
 * loadout bytes (COOP2MP T4b: another player's real plane carries their weapons, so their weapon numbers mean here what
 * they mean on their game). 1 when whole */
static int CoParseLoadout(const char* s, int32_t* l1, int32_t* n1, int32_t* l2, int32_t* n2, uint8_t* bytes)
{
    int part = 0, have = 0, nb = 0;
    int64_t v = 0;
    *n1 = *n2 = 0;
    for (const char* p = s;; ++p) {
        char c = *p;
        if (c >= '0' && c <= '9') { v = v * 10 + (c - '0'); have = 1; if (v > 0x7fffffff) return 0; continue; }
        if (c != ',' && c != '/' && c != 0) return 0;
        if (have) {
            if (part == 0) { if (*n1 >= 64) return 0; l1[(*n1)++] = (int32_t)v; }
            else if (part == 1) { if (*n2 >= 64) return 0; l2[(*n2)++] = (int32_t)v; }
            else { if (nb >= 2 || v > 255) return 0; bytes[nb++] = (uint8_t)v; }
        }
        v = 0; have = 0;
        if (c == '/') { if (++part > 2) return 0; }
        if (!c) break;
    }
    return part == 2 && nb == 2;
}

/* A player plane's paint (COOP2MP T5; research of 2026-10-30, checked in code): its BeginPlay (vtable 0xA70, 0x147d4af60,
 * inside FinishSpawning) loads the skin (ULiveSkinMaterialComplition, 0x147d82100(comp, plane, plane id, skin id); -1
 * the plane's default) and the emblems (ULivePlaneEmblemSetter, 0x147de2c60(..., flags, &emblem ids)) from the plane's
 * own fields, which Online Mode's remote spawn fills before it: skin id int, emblem ids TArray<int32>, emblem flags int.
 * Their offsets and the TArray<int32> copy-assign are read from the remote spawn's own writes, at fixed distances before
 * its finish site: `mov [rsi + skin], eax` (-0x11e), `lea rcx, [rsi + emblems]` (-0x113), `call <assign>` (-0x108),
 * `mov [rsi + flags], eax` (-0xd2) */
typedef void* (*CoArrAssignFn)(void* dst, const void* src);
static int CoPaintSites(int32_t* skin, int32_t* emb, int32_t* flags, CoArrAssignFn* assign)
{
    uint8_t* s = g_siteRemoteFinish;
    if (!s) return 0;
    uint8_t* a = s - 0x11e, *b = s - 0x113, *c = s - 0x108, *d = s - 0xd2;
    if (a[0] != 0x89 || a[1] != 0x86 || b[0] != 0x48 || b[1] != 0x8D || b[2] != 0x8E || c[0] != 0xE8 || d[0] != 0x89 || d[1] != 0x86)
        return 0;
    *skin = *(int32_t*)(a + 2); *emb = *(int32_t*)(b + 3); *flags = *(int32_t*)(d + 2);
    *assign = (CoArrAssignFn)(c + 5 + *(int32_t*)(c + 1));
    return *skin > 0 && *skin < 0x8000 && *emb > 0 && *emb < 0x8000 && *flags > 0 && *flags < 0x8000 && InGame(*assign);
}
/* "skin/flags/e1,e2,..." (16 emblems at most), as SV_CoopPaint gives it; 1 when whole */
static int CoParsePaint(const char* s, int32_t* skin, int32_t* flags, int32_t* emb, int32_t* nEmb)
{
    int part = 0, neg = 0, have = 0;
    int64_t v = 0;
    *nEmb = 0;
    for (const char* p = s;; ++p) {
        char ch = *p;
        if (ch == '-' && !have && !neg && part < 2) { neg = 1; continue; }
        if (ch >= '0' && ch <= '9') { v = v * 10 + (ch - '0'); have = 1; if (v > 0x7fffffff) return 0; continue; }
        if (ch != ',' && ch != '/' && ch != 0) return 0;
        if (have) {
            int32_t x = (int32_t)(neg ? -v : v);
            if (part == 0) *skin = x;
            else if (part == 1) *flags = x;
            else { if (*nEmb >= 16) return 0; emb[(*nEmb)++] = x; }
        } else if (part < 2 && (ch == '/' || ch == 0)) return 0;
        v = 0; have = 0; neg = 0;
        if (ch == '/') { if (++part > 2) return 0; }
        if (!ch) break;
    }
    return part == 2;
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

/* SV_CoopSpawnPP(pawn, x, y, z, yaw[, class]) -> the new player plane's address (a plane of pawn's class, or of `class`
 * (a player plane blueprint's class, COOP2MP T2: tools/re/COOP2MP.md), possessed by a network dummy controller, marked
 * as another player's), or < 0: -1 bad args, -2 game code not found, -3 no dummy controller class, -4 the controller
 * didn't spawn, -5 the plane didn't spawn (a class that isn't a player plane's too), -6 its spawn didn't finish. One at
 * a time: a second call removes the first. Another class gets no loadout of yours (your weapon ids are your plane's):
 * its own default weapons. A seventh argument, a player slot 0-23 (COOP2MP T3: another player's real plane), keeps one
 * per slot instead (a second call for the slot removes that slot's). An eighth, their loadout ("a,b/c,d/x,y": SV_CoopLoadout
 * on their game, COOP2MP T4b), gives the plane their weapons, another airframe's too. */
static int L_CoopSpawnPP(void* lua)
{
    uint8_t* pawn = ArgObject(lua);
    double pos[3] = { 0 }, yaw = 0;
    if (!pawn || !ArgNumber(lua, &pos[0]) || !ArgNumber(lua, &pos[1]) || !ArgNumber(lua, &pos[2])) return Ret(lua, -1);
    ArgNumber(lua, &yaw);
    uint8_t* clsArg = ArgObject(lua);                                              /* (optional) */
    double slotArg = -1;
    ArgNumber(lua, &slotArg);
    int slot = (slotArg >= 0 && slotArg < CO_MAX_PLAYERS) ? (int)slotArg : -1;
    char loTxt[512];                                                               /* (optional: their loadout, T4b) */
    size_t loLen = 0;
    int32_t lo1[64], lo2[64], loN1 = 0, loN2 = 0;
    uint8_t loB[2] = { 0, 0 };
    int theirs = ArgBytes(lua, loTxt, sizeof(loTxt), &loLen) && loLen > 0 && CoParseLoadout(loTxt, lo1, &loN1, lo2, &loN2, loB);
    char ptTxt[256];                                                               /* (optional: their paint, T5) */
    size_t ptLen = 0;
    int32_t ptSkin = -1, ptFlags = 0, ptEmb[16], ptN = 0;
    int paint = ArgBytes(lua, ptTxt, sizeof(ptTxt), &ptLen) && ptLen > 0 && CoParsePaint(ptTxt, &ptSkin, &ptFlags, ptEmb, &ptN);
    CoRef* keepPlane = slot >= 0 ? &g_peerPP[slot] : &g_ppPlane, *keepCtrl = slot >= 0 ? &g_peerCtrl[slot] : &g_ppCtrl;
    if (!LiveObject(pawn) || (clsArg && !LiveObject(clsArg))) return Ret(lua, -1);
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
    if (CoRefGet(keepPlane) && g_destroyActor) { Crumb(L"coop: a real plane %p destroyed (replaced)", keepPlane->obj); g_destroyActor(keepPlane->obj, 0); }
    if (CoRefGet(keepCtrl) && g_destroyActor) g_destroyActor(keepCtrl->obj, 0);
    memset(keepPlane, 0, sizeof(*keepPlane)); memset(keepCtrl, 0, sizeof(*keepCtrl));
    void* cls = *(void**)(pawn + 0x10);                                             /* UObjectBase::ClassPrivate */
    int foreign = clsArg && (void*)clsArg != cls;
    if (foreign) cls = clsArg;
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
    uint8_t* lo = (foreign || theirs) ? NULL : *(uint8_t**)(pawn + loObj);
    if (!LiveObject(lo)) lo = NULL;
    CoArr l1 = CoLoadoutList(lo, 0x30), l2 = CoLoadoutList(lo, 0x40);
    if (theirs) { l1.data = lo1; l1.num = l1.max = loN1; l2.data = lo2; l2.num = l2.max = loN2; }   /* (another player's, T4b) */
    ((CoLoadoutFn)loadoutFn)(plane, &l1, &l2);
    plane[loByte[0]] = theirs ? loB[0] : foreign ? 0 : pawn[loByte[0]];
    plane[loByte[1]] = theirs ? loB[1] : foreign ? 0 : pawn[loByte[1]];
    if (theirs) Log(L"coop: second player plane: their loadout given (%d and %d entries, bytes %d %d)", loN1, loN2, loB[0], loB[1]);
    if (paint) {                                         /* (their paint: read by its BeginPlay, inside FinishSpawning) */
        int32_t oSkin = 0, oEmb = 0, oFlags = 0;
        CoArrAssignFn assign = NULL;
        if (CoPaintSites(&oSkin, &oEmb, &oFlags, &assign)) {
            *(int32_t*)(plane + oSkin) = ptSkin;
            *(int32_t*)(plane + oFlags) = ptFlags;
            struct { int32_t* data; int32_t num, max; } src = { ptEmb, ptN, ptN };
            assign(plane + oEmb, &src);
            Log(L"coop: second player plane: their paint given (skin %d, emblem flags %d, %d emblems)", ptSkin, ptFlags, ptN);
        } else Log(L"coop: second player plane: their paint not given (the remote spawn's paint writes weren't found)");
    }
    ((CoFinishFn)g_fFinishSpawning)(plane, xf, 0, NULL, 1);
    int finished = (plane[g_finishedOff] & 1) != 0;
    int32_t wOff = *(int32_t*)(g_siteRemoteLoadout + 20);                          /* mov r14, [plane + disp32] */
    uint8_t* w = (wOff > 0 && wOff < 0x8000) ? *(uint8_t**)(plane + wOff) : NULL;
    void* owner = (w && Readable(w + 0x2d0, 8)) ? *(void**)(w + 0x2d0) : NULL;   /* what crashed 0.22.1 (COOP.md 6) */
    Log(L"coop: second player plane %p (class %p, %s) spawned, controller %p, possessed (slot +%x, Possess %p), network object %p (+%x), role byte +%x = 2 (yours %d)",
        plane, cls, foreign ? L"another airframe: no loadout of yours" : L"yours", ctrl, (uint32_t)possessSlot, possessFn, (netOk && noOff > 0) ? *(void**)(plane + noOff) : NULL, (uint32_t)noOff, (uint32_t)roleOff,
        (int32_t)pawn[roleOff]);
    Log(L"coop: second player plane: loadout %p (+%x; yours %p: %d and %d entries), bytes +%x +%x = %d %d, spawn finished: %s, weapons %p (+%x), their owner %p",
        *(void**)(plane + loObj), (uint32_t)loObj, lo, l1.num, l2.num, (uint32_t)loByte[0], (uint32_t)loByte[1], plane[loByte[0]],
        plane[loByte[1]], finished ? L"yes" : L"NO", w, (uint32_t)wOff, owner);
    if (!finished) {
        if (g_destroyActor) { g_destroyActor(plane, 0); g_destroyActor(ctrl, 0); }
        Log(L"coop: second player plane: its spawn didn't finish; removed");
        return Ret(lua, -6);
    }
    CoRefSet(keepPlane, plane); CoRefSet(keepCtrl, ctrl);
    if (slot >= 0) Log(L"coop: player %d's real plane is %p", slot + 1, plane);
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

/* SV_CoopPaint() -> your plane's paint, "skin/flags/e1,e2,..." (its skin id, emblem flags and emblem ids, 16 at most:
 * what SV_CoopSpawnPP's ninth argument gives another game's real plane of yours), "" when it can't be read */
static int L_CoopPaint(void* lua)
{
    uint8_t* me = CoRefGet(&CO.me);
    int32_t oSkin = 0, oEmb = 0, oFlags = 0;
    CoArrAssignFn assign = NULL;
    if (!me || !LiveObject(me) || !CoPaintSites(&oSkin, &oEmb, &oFlags, &assign) || !Readable(me + oSkin, 4) ||
        !Readable(me + oFlags, 4) || !Readable(me + oEmb, 0x10)) { U.luaSetString(lua, "", 0); return 1; }
    int32_t* data = *(int32_t**)(me + oEmb);
    int32_t num = *(int32_t*)(me + oEmb + 8);
    if (num < 0 || num > 16 || (num && !Readable(data, 4 * (size_t)num))) num = 0;
    char s[300];
    CoBuf b = { s, s + sizeof(s) - 1 };
    CoPutI(&b, *(int32_t*)(me + oSkin)); CoPutS(&b, "/"); CoPutI(&b, *(int32_t*)(me + oFlags)); CoPutS(&b, "/");
    for (int32_t i = 0; i < num; ++i) { if (i) CoPutS(&b, ","); CoPutI(&b, data[i]); }
    *b.p = 0;
    U.luaSetString(lua, s, (size_t)(b.p - s));
    return 1;
}

/* SV_SpawnCam(x, y, z) -> a new CameraActor's address at that spot (cm), or < 0: -1 no plane of yours / no world, -2 game
 * code not found, -3 no CameraActor class, -4 it didn't spawn. Co-op's spectator camera on a player plane (COOP2MP's real
 * planes): the view on a player plane takes the game's own player-plane camera whatever cameras are added to it (the
 * user's co-op run of 2026-10-30: our camera measured 31 m behind CRESSENDO's real ADFX-02, the view inside it), so
 * sv_down.lua views a camera actor of its own, attached to the plane (K2_AttachToActor, keeping its place). */
static int L_SpawnCam(void* lua)
{
    double pos[3] = { 0, 0, 0 };
    if (!ArgNumber(lua, &pos[0]) || !ArgNumber(lua, &pos[1]) || !ArgNumber(lua, &pos[2])) return Ret(lua, -1);
    if (!g_fWorldSpawnActor || !ResolveUE4SS()) return Ret(lua, -2);
    uint8_t* me = CoRefGet(&CO.me);
    void* world = me ? VCall(me, VF_WORLD) : NULL;
    if (!LiveObject(world)) return Ret(lua, -1);
    void* cls = U.findObject(L"Class", L"CameraActor", 0, 0);
    if (!LiveObject(cls)) return Ret(lua, -3);
    double xf[12] __attribute__((aligned(16)));
    CoXform(xf, pos, 0);
    uint8_t params[0x80] __attribute__((aligned(16)));                              /* FActorSpawnParameters, as the game fills it */
    memset(params, 0, sizeof(params));
    *(uint16_t*)(params + 0x30) = 0x101;                                            /* AlwaysSpawn, MultiplyWithRoot */
    *(uint32_t*)(params + 0x34) = 0x48;                                             /* RF_Transactional | RF_Transient */
    uint8_t* cam = (uint8_t*)((CoWorldSpawnFn)g_fWorldSpawnActor)(world, cls, xf, params);
    if (!LiveObject(cam)) return Ret(lua, -4);
    Log(L"coop: spectator camera actor %p spawned", cam);
    return Ret(lua, (int64_t)(uintptr_t)cam);
}

/* SV_PPName(plane, name) -> 1: another player's real plane here shows name under ALLY in its target box; < 0: -1 bad
 * args / not such a plane, -2 game code not found. The box's callsign line, offline, is the game object's callsign FString
 * at +0x6E8 (GetCallsign's field; the HUD's builder 0x147293760 copies it in every frame; the online line, +0x2210, shows
 * only in an online game mode). The game's FString assign is the call 0x34 bytes before the remote spawn's finish site
 * (its write of the plane's +0x2200, `lea rcx, [rsi + 0x2200]; ...; call`), checked first. Not reflected: Lua can't. The
 * user, 2026-10-30: "the Player Names aren't showing underneath ALLY anymore" (AI stand-ins showed theirs) */
typedef void* (*CoFStrAssignFn)(void* dst, const void* src);
static int CoUtf8To16(const char* txt, size_t len, wchar_t* w, int cap);
static int L_PPName(void* lua)
{
    uint8_t* plane = ArgObject(lua);
    char txt[160], ac[160];
    size_t len = 0, acLen = 0;
    if (!plane || !ArgBytes(lua, txt, sizeof(txt), &len) || !len) return Ret(lua, -1);
    int haveAc = ArgBytes(lua, ac, sizeof(ac), &acLen) && acLen > 0;          /* (optional: their aircraft's name) */
    if (!LiveObject(plane) || CoKind(plane) != 2 || plane == CO.me.obj || !Readable(plane + 0x6D8, 0x20)) return Ret(lua, -1);
    uint8_t* s = g_siteRemoteFinish;
    uint8_t* c = s ? s - 0x34 : NULL, *l = s ? s - 0x46 : NULL;
    if (!c || c[0] != 0xE8 || l[0] != 0x48 || l[1] != 0x8D || l[2] != 0x8E || *(int32_t*)(l + 3) != 0x2200) return Ret(lua, -2);
    CoFStrAssignFn assign = (CoFStrAssignFn)(c + 5 + *(int32_t*)(c + 1));
    if (!InGame(assign)) return Ret(lua, -2);
    wchar_t w[40];
    int n = CoUtf8To16(txt, len, w, 40);
    if (!n) return Ret(lua, -1);
    struct { wchar_t* data; int32_t num, max; } src = { w, n + 1, n + 1 };
    assign(plane + 0x6E8, &src);
    /* the aircraft's name: ObjName +0x6D8 (GetObjName's field), which the remote spawn fills from the plane's data row
     * and the box's builder (0x147293760) reads beside the callsign; our spawn has no session data for it */
    wchar_t wa[40];
    int na = haveAc ? CoUtf8To16(ac, acLen, wa, 40) : 0;
    if (na) { struct { wchar_t* data; int32_t num, max; } sa = { wa, na + 1, na + 1 }; assign(plane + 0x6D8, &sa); }
    Log(L"coop: player plane %p's callsign (under ALLY) set: %s%s%s", plane, w, na ? L"; its aircraft: " : L"", na ? wa : L"");
    return Ret(lua, 1);
}

/* UTF-8 (len bytes) to UTF-16 in w (cap - 1 characters at most, 0-terminated): the characters written */
static int CoUtf8To16(const char* txt, size_t len, wchar_t* w, int cap)
{
    int n = 0;
    for (size_t i = 0; i < len && n < cap - 1;) {
        uint32_t u = (uint8_t)txt[i];
        int k = u < 0x80 ? 0 : (u & 0xE0) == 0xC0 ? 1 : (u & 0xF0) == 0xE0 ? 2 : (u & 0xF8) == 0xF0 ? 3 : -1;
        if (k < 0 || i + (size_t)k >= len + (k ? 0 : 1)) break;
        u = k == 0 ? u : k == 1 ? (u & 0x1F) : k == 2 ? (u & 0x0F) : (u & 0x07);
        for (int j = 1; j <= k; ++j) {
            uint8_t b = (uint8_t)txt[i + j];
            if ((b & 0xC0) != 0x80) { u = '?'; k = j - 1; break; }
            u = (u << 6) | (b & 0x3F);
        }
        i += 1 + (size_t)k;
        if (u < 0x20) continue;
        if (u >= 0x10000) { if (n >= cap - 2) break; u -= 0x10000; w[n++] = (wchar_t)(0xD800 | (u >> 10)); w[n++] = (wchar_t)(0xDC00 | (u & 0x3FF)); }
        else w[n++] = (wchar_t)u;
    }
    w[n] = 0;
    return n;
}

/* SV_CoopKillPP() -> 1: the second player plane and its controller removed (0: none was up); SV_CoopKillPP(slot): that
 * player slot's real plane (COOP2MP T3) */
static int L_CoopKillPP(void* lua)
{
    int n = 0;
    double slotArg = -1;
    if (ArgNumber(lua, &slotArg) && slotArg >= 0 && slotArg < CO_MAX_PLAYERS) {
        int s = (int)slotArg;
        if (CO.players[s].plane.ref.obj && CO.players[s].plane.ref.obj == g_peerPP[s].obj) memset(&CO.players[s].plane.ref, 0, sizeof(CoRef));
        if (CoRefGet(&g_peerPP[s]) && g_destroyActor) { Crumb(L"coop: player %d's real plane %p destroyed", s + 1, g_peerPP[s].obj); g_destroyActor(g_peerPP[s].obj, 0); ++n; }
        if (CoRefGet(&g_peerCtrl[s]) && g_destroyActor) { g_destroyActor(g_peerCtrl[s].obj, 0); ++n; }
        memset(&g_peerPP[s], 0, sizeof(CoRef)); memset(&g_peerCtrl[s], 0, sizeof(CoRef));
        if (n) Log(L"coop: player %d's real plane removed", s + 1);
        return Ret(lua, n ? 1 : 0);
    }
    if (g_follow.obj == g_ppPlane.obj) memset(&g_follow, 0, sizeof(g_follow));
    if (CoRefGet(&g_ppPlane) && g_destroyActor) { Crumb(L"coop: the second player plane %p destroyed", g_ppPlane.obj); g_destroyActor(g_ppPlane.obj, 0); ++n; }
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
static int32_t    g_scanStep;                      /* the flight-model field scan below: 0, 1, 2 done */
static double     g_scanAt;
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
    g_scanStep = 0; g_scanAt = CoNow();                                         /* left alone: scanned at 1 s and 2 s */
    return Ret(lua, 1);
}

/* Flight-model field scan (runtime 0.22.6). With role 0 and its tick on, the copy flies straight on its own and our
 * moves don't hold it (test of 2026-10-25): its flight model keeps its own position and writes it back every frame.
 * While the copy is left alone (mode 1), its object is scanned 1 s after the start and again 1 s later for triples that
 * look like its position (within 300 m of its root: doubles in cm or m, floats in cm) or a velocity (50-600 m/s:
 * doubles or floats, cm/s or m/s); the second scan logs each one's two readings beside the root's own move, so the
 * fields that move with the plane show. */
#define CO_SCAN_MAX 128
#define CO_SCAN_END 0x6000
typedef struct { int32_t off; uint8_t isFloat, kind; double v1[3]; } CoScanHit;  /* kind 1 position, 2 velocity */
static CoScanHit g_scan[CO_SCAN_MAX];
static int32_t   g_scanN;
static double    g_scanRoot[3];

static int CoScanVal(uint8_t* p, int32_t off, int isFloat, double* v)
{
    if (isFloat) { float f[3]; memcpy(f, p + off, 12); v[0] = f[0]; v[1] = f[1]; v[2] = f[2]; }
    else memcpy(v, p + off, 24);
    for (int i = 0; i < 3; ++i) if (!(v[i] == v[i]) || v[i] > 1e9 || v[i] < -1e9) return 0;        /* NaN or junk */
    return 1;
}

static void CoScanFirst(uint8_t* plane, const double* L)
{
    g_scanN = 0; memcpy(g_scanRoot, L, 24);
    for (int pass = 1; pass <= 2; ++pass)
        for (int32_t off = 0x100; off + 24 <= CO_SCAN_END && g_scanN < CO_SCAN_MAX; off += 4) {
            if (!Readable(plane + off, 24)) continue;
            for (int fl = 0; fl < 2 && g_scanN < CO_SCAN_MAX; ++fl) {
                double v[3];
                if ((!fl && (off & 7)) || !CoScanVal(plane, off, fl, v)) continue;
                int hit = 0;
                if (pass == 1) {
                    for (int u = 0; u < (fl ? 1 : 2) && !hit; ++u) {                     /* cm, or m (doubles) */
                        double k = u ? 100.0 : 1.0;
                        hit = CoAbs(v[0] * k - L[0]) < 30000 && CoAbs(v[1] * k - L[1]) < 30000 && CoAbs(v[2] * k - L[2]) < 30000;
                    }
                } else {
                    double s = CoSqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
                    hit = (s >= 5000 && s <= 60000) || (s >= 50 && s <= 600);
                    hit = hit && CoAbs(v[0]) + CoAbs(v[1]) + CoAbs(v[2]) > 0 && v[0] != v[1];
                }
                if (!hit) continue;
                CoScanHit* h = &g_scan[g_scanN++];
                h->off = off; h->isFloat = (uint8_t)fl; h->kind = (uint8_t)pass; memcpy(h->v1, v, 24);
            }
        }
    Log(L"coop: scan 1 of the copy %p: root at %d %d %d cm; %d candidates", plane, (int32_t)L[0], (int32_t)L[1], (int32_t)L[2], g_scanN);
}

static void CoScanSecond(uint8_t* plane, const double* L)
{
    double rd[3] = { L[0] - g_scanRoot[0], L[1] - g_scanRoot[1], L[2] - g_scanRoot[2] };
    Log(L"coop: scan 2 of the copy %p: root at %d %d %d cm, moved %d %d %d cm", plane, (int32_t)L[0], (int32_t)L[1], (int32_t)L[2],
        (int32_t)rd[0], (int32_t)rd[1], (int32_t)rd[2]);
    for (int32_t i = 0; i < g_scanN; ++i) {
        CoScanHit* h = &g_scan[i];
        double v[3];
        if (!CoScanVal(plane, h->off, h->isFloat, v)) continue;
        double k = (h->kind == 1 && !h->isFloat && CoAbs(h->v1[0] - g_scanRoot[0]) > 30000) ? 100.0 : 1.0;   /* m: shown in cm */
        Log(L"coop: scan +%x %s %s: %d %d %d -> %d %d %d (moved %d %d %d)", (uint32_t)h->off, h->isFloat ? L"float" : L"double",
            h->kind == 1 ? (k > 1 ? L"position (m)" : L"position") : L"velocity?", (int32_t)(h->v1[0] * k), (int32_t)(h->v1[1] * k),
            (int32_t)(h->v1[2] * k), (int32_t)(v[0] * k), (int32_t)(v[1] * k), (int32_t)(v[2] * k), (int32_t)((v[0] - h->v1[0]) * k),
            (int32_t)((v[1] - h->v1[1]) * k), (int32_t)((v[2] - h->v1[2]) * k));
    }
}

static void CoScanFrame(uint8_t* plane, double now)
{
    if (g_scanStep >= 2 || now - g_scanAt < 1.0) return;
    double L[3], R[3];
    if (!CoReadPose(plane, L, R)) return;
    if (g_scanStep == 0) CoScanFirst(plane, L); else CoScanSecond(plane, L);
    ++g_scanStep; g_scanAt = now;
}

static void CoFollowFrame(int fromMusic)
{
    if (!g_follow.obj) return;
    double now = CoNow();
    uint8_t* plane = CoRefGet(&g_follow), *pawn = CoRefGet(&g_followPawn);
    if (!plane || !pawn) { memset(&g_follow, 0, sizeof(g_follow)); Log(L"coop: formation test ended (an actor is gone)"); return; }
    CoFollowSample(plane, pawn, now, fromMusic);
    /* In a mission only the input build calls this (the music player's clock doesn't tick: test of 2026-10-25), two or
     * three times a frame (once per player plane, maybe per flight-model step). 0.22.6 moved the copy at the first call
     * of a frame only; if your plane moves a varying number of steps after it, the copy's lag varies: the stutter? So
     * every call moves it now (0.22.7). Left alone (mode 1): the flight-model scan. */
    if (fromMusic) g_followMusicAt = now;
    if (g_followMode == 1) { CoScanFrame(plane, now); return; }
    if (g_followMode == 2 && fromMusic) return;
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
