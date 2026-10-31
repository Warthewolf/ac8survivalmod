/* recorder.c : the flight recorder (SV_FlightRec), for the GRU pilot project (warthewolf/ac8-gru-pilot: its sim is
 * calibrated from these files). DEV BUILDS ONLY: survival_rt.c includes this file only when compiled with SV_DEV
 * (runtime/build.sh DEV=1 -> build/runtime/dev/main.dll, which tools/package_dev.sh puts in the user's own test install).
 * The DLL in friends' zips (package_release.sh / package_test.sh) is built without SV_DEV, so it has no recorder, no
 * SV_FlightRec and none of its strings; package_release.sh fails a zip whose main.dll holds them (user, 2026-10-31:
 * "none of this research is allowed to cross over to friends games at all").
 *
 * Ported from feature/flight-recorder's a440b49 (runtime 0.20.0, never run in game) onto COOP2MP's runtime 0.32.11:
 * the RootComponent and HealthInternal offsets now come from co-op's reflected lookup (coop.c CoResolve, confirmed in
 * game), not a scan of the plane for a pointer Lua passed.
 *
 * The BuildFlightInput detour runs on the game thread for the player's plane (and for co-op's real planes); while
 * recording, each frame of the recorded plane writes one CSV row for it and one for the plane it has targeted
 * (player+0x1ae8 -> +0x750, as SV_PlayerTarget) to <mod>\recordings\flight_<date>_<time>.csv:
 *   t (s, QueryPerformanceCounter), who (P player / T target), id (the actor's address, so a new target shows),
 *   x y z (cm) and qx qy qz qw: the root component's ComponentToWorld (rotation +0x200, translation +0x220: FTransform
 *   is doubles in UE5, tools/re/BEHAVIOUR_NATIVE_MOVE.md 5; not yet confirmed: the log's first line compares the
 *   translation with RelativeLocation, which co-op reads in game), speed (ALiveGameObject.Speed +0x3c0, cm/s),
 *   hp (HealthInternal / 10), then the inputs:
 *   P: pitch yaw roll throttle brake highg = the out struct the flight engine gets (+0x0..+0x14), flags = out+0x18;
 *   T: pitch yaw roll throttle brake = ALiveAIPlane +0x2a8c..+0x2a9c (what its behaviour tree commands), ai_speed
 *   +0x2a88 (m/s), cobra_ok / kulbit_ok = bCanManeuverPugachevsCobra +0x28d0 / bCanManeuverKulbit +0x28d1
 *   (BEHAVIOUR_NATIVE_MOVE.md 1, BEHAVIOUR_NATIVE_LOGIC.md); ai = 1 when the target's vtable is ALiveAIPlane's
 *   (exe+0xc551db0, KILLS_HEALTH_DEATH.md); its input columns mean nothing on anything else (the first target
 *   vtables are logged to learn them).
 * Nothing in the game is written. Rows less than REC_MIN_GAP_US after the last are skipped (the detour can run more
 * than once a frame). Columns are those of a440b49, so the GRU pilot's recording.py reads both. */
#ifdef SV_DEV

IMPORT BOOL WINAPI CreateDirectoryW(const wchar_t* path, void* sec);

#define REC_COMP_ROTATION   0x200              /* FQuat4d x, y, z, w */
#define REC_COMP_TRANSLATION 0x220             /* FVector3d x, y, z (cm) */
#define REC_OBJ_SPEED       0x3c0              /* ALiveGameObject.Speed, float cm/s */
#define REC_HEALTH_DEFAULT  0xda8              /* HealthInternal, int x10, when CoResolve hasn't found it */
#define REC_AIP_SPEED       0x2a88
#define REC_AIP_STICK       0x2a8c             /* pitch, yaw, roll, throttle, brake (5 floats) */
#define REC_AIP_CAN_COBRA   0x28d0
#define REC_AIP_CAN_KULBIT  0x28d1
#define REC_VT_AI_PLANE_RVA 0xc551db0
#define REC_MIN_GAP_US      3000
static volatile int32_t g_recLock;
static HANDLE   g_recFile = INVALID_HANDLE_VALUE;
static uint8_t* g_recPlane;
static int32_t  g_recHealthOff;
static int64_t  g_recT0, g_recFreq, g_recFlushAt, g_recLast;
static int64_t  g_recRows;
static char     g_recBuf[65536];
static size_t   g_recLen;
static uint8_t* g_recTarget;                   /* the last target seen (logged when it changes) */
static uint32_t g_recVts[8];                   /* target vtables already logged */
static int      g_recQuatWarned, g_recChecked;

static void RecPut(const char* s) { while (*s && g_recLen < sizeof(g_recBuf) - 1) g_recBuf[g_recLen++] = *s++; }

static void RecInt(int64_t v)
{
    char t[24]; int n = 0;
    uint64_t u = v < 0 ? (uint64_t)(-v) : (uint64_t)v;
    do { t[n++] = (char)('0' + u % 10); u /= 10; } while (u);
    if (v < 0) t[n++] = '-';
    while (n && g_recLen < sizeof(g_recBuf) - 1) g_recBuf[g_recLen++] = t[--n];
}

static void RecF(double v, int dec)            /* fixed point; "nan" for NaN / out of range */
{
    if (v != v || v > 9e15 || v < -9e15) { RecPut("nan"); return; }
    int64_t scale = 1;
    for (int i = 0; i < dec; ++i) scale *= 10;
    int64_t q = (int64_t)(v * (double)scale + (v < 0 ? -0.5 : 0.5));
    if (q < 0) { RecPut("-"); q = -q; }
    RecInt(q / scale);
    if (dec) {
        char t[20]; int64_t r = q % scale;
        for (int i = dec - 1; i >= 0; --i) { t[i] = (char)('0' + r % 10); r /= 10; }
        t[dec] = 0;
        RecPut("."); RecPut(t);
    }
}

static void RecFlush(void)
{
    if (g_recFile != INVALID_HANDLE_VALUE && g_recLen) {
        DWORD put = 0;
        WriteFile(g_recFile, g_recBuf, (DWORD)g_recLen, &put, NULL);
    }
    g_recLen = 0;
}

/* One row's start: the actor's transform, speed and health (the caller adds the input columns). */
static int RecActor(double t, char who, uint8_t* actor)
{
    if (!actor || g_offRoot < 0 || !Readable(actor + g_offRoot, 8)) return 0;
    uint8_t* comp = *(uint8_t**)(actor + g_offRoot);
    if (!comp || !LiveObject(comp) || !Readable(comp + REC_COMP_ROTATION, 0x40) || !Readable(actor + REC_OBJ_SPEED, 4) ||
        !Readable(actor + g_recHealthOff, 4)) return 0;
    const double* q = (const double*)(comp + REC_COMP_ROTATION);
    const double* p = (const double*)(comp + REC_COMP_TRANSLATION);
    double n2 = q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3];
    if ((n2 < 0.9 || n2 > 1.1) && !g_recQuatWarned) {
        g_recQuatWarned = 1;
        Log(L"flight recorder: %s's rotation isn't a unit quaternion (|q|^2 x1000 = %d): the component layout differs",
            who == 'P' ? L"the player" : L"the target", (int32_t)(n2 * 1000.0));
    }
    if (who == 'P' && !g_recChecked) {                    /* the transform read against co-op's RelativeLocation */
        double rl[3], rr[3];
        g_recChecked = 1;
        if (CoReadPose(actor, rl, rr))
            Log(L"flight recorder: check: ComponentToWorld at %d %d %d cm, RelativeLocation %d %d %d cm (the same when "
                L"the read is right)", (int32_t)p[0], (int32_t)p[1], (int32_t)p[2], (int32_t)rl[0], (int32_t)rl[1], (int32_t)rl[2]);
    }
    char w[2] = { who, 0 };
    RecF(t, 4); RecPut(","); RecPut(w); RecPut(",");
    {
        char h[20]; int k = 0; uint64_t a = (uint64_t)(uintptr_t)actor;
        do { h[k++] = "0123456789ABCDEF"[a & 15]; a >>= 4; } while (a);
        while (k && g_recLen < sizeof(g_recBuf) - 1) g_recBuf[g_recLen++] = h[--k];
    }
    for (int i = 0; i < 3; ++i) { RecPut(","); RecF(p[i], 1); }
    for (int i = 0; i < 4; ++i) { RecPut(","); RecF(q[i], 6); }
    RecPut(","); RecF(*(float*)(actor + REC_OBJ_SPEED), 1);
    RecPut(","); RecF(*(int32_t*)(actor + g_recHealthOff) * 0.1, 1);
    return 1;
}

/* (OnBuildInput, after the game built the input and before Survival changes it: the stick as the player gave it) */
static void RecSample(uint8_t* plane, const float* out)
{
    if (g_recFile == INVALID_HANDLE_VALUE || !plane || plane != g_recPlane || !out) return;
    if (__sync_lock_test_and_set(&g_recLock, 1)) return;          /* SV_FlightRec is opening / closing: skip a frame */
    if (g_recFile != INVALID_HANDLE_VALUE && plane == g_recPlane && LiveObject(plane)) {
        int64_t now = 0;
        QueryPerformanceCounter(&now);
        if (!g_recLast || (now - g_recLast) * 1000000 / g_recFreq >= REC_MIN_GAP_US) {
            g_recLast = now;
            double t = (double)(now - g_recT0) / (double)g_recFreq;
            if (RecActor(t, 'P', plane)) {                        /* the player: the out struct as the engine gets it */
                for (int i = 0; i < 6; ++i) { RecPut(","); RecF(out[i], 4); }
                RecPut(","); RecInt(((const uint8_t*)out)[0x18]);
                RecPut(",,,,\r\n");                               /* ai, ai_speed, cobra_ok, kulbit_ok */
                ++g_recRows;
            }
            uint8_t* target = NULL;                               /* its target, when it has one */
            if (Readable(plane + PLAYER_TARGET_HOLDER, 8)) {
                uint8_t* holder = *(uint8_t**)(plane + PLAYER_TARGET_HOLDER);
                if (holder && Readable(holder + PLAYER_TARGET, 8)) target = *(uint8_t**)(holder + PLAYER_TARGET);
            }
            if (target && LiveObject(target)) {
                uint32_t vt = (uint32_t)((uint8_t*)*(void**)target - g_exe);
                if (target != g_recTarget) {
                    g_recTarget = target;
                    int known = 0, slot = -1;
                    for (int i = 0; i < 8; ++i) { if (g_recVts[i] == vt) known = 1; if (!g_recVts[i] && slot < 0) slot = i; }
                    if (!known && slot >= 0) {
                        g_recVts[slot] = vt;
                        Log(L"flight recorder: target %p, vtable exe+%x%s", target, vt,
                            vt == REC_VT_AI_PLANE_RVA ? L" (ALiveAIPlane)" : L"");
                    }
                }
                if (RecActor(t, 'T', target)) {
                    int ai = vt == REC_VT_AI_PLANE_RVA;
                    if (ai && Readable(target + REC_AIP_CAN_COBRA, REC_AIP_STICK + 20 - REC_AIP_CAN_COBRA)) {
                        const float* st = (const float*)(target + REC_AIP_STICK);
                        for (int i = 0; i < 5; ++i) { RecPut(","); RecF(st[i], 4); }
                        RecPut(",,,"); RecInt(ai);                /* highg, flags: player only */
                        RecPut(","); RecF(*(float*)(target + REC_AIP_SPEED), 2);
                        RecPut(","); RecInt(target[REC_AIP_CAN_COBRA]); RecPut(","); RecInt(target[REC_AIP_CAN_KULBIT]);
                    } else {
                        RecPut(",,,,,,,,"); RecInt(ai); RecPut(",,,");
                    }
                    RecPut("\r\n");
                    ++g_recRows;
                }
            }
        }
        if (g_recLen > sizeof(g_recBuf) - 1024 || now >= g_recFlushAt) {      /* every 2 s: a crash loses little */
            RecFlush();
            g_recFlushAt = now + 2 * g_recFreq;
        }
    }
    __sync_lock_release(&g_recLock);
}

static void RecClose(void)
{
    if (g_recFile == INVALID_HANDLE_VALUE) return;
    RecFlush();
    CloseHandle(g_recFile);
    g_recFile = INVALID_HANDLE_VALUE;
    g_recPlane = NULL;
}

/* SV_FlightRec(on, plane) -> on = 1: starts recording plane (the player's ALivePlayerPlane address) to a new
 * <mod>\recordings\flight_<date>_<time>.csv and returns 1, or SV_ERR_BAD_ARGS (not a live object) / SV_ERR_NO_GAME
 * (BuildFlightInput not hooked, or its RootComponent not found) / SV_ERR_REFUSED (the file can't be made). Already
 * recording: restarts in a new file. on = 0: stops and returns the rows written (0 when it wasn't recording). */
static int L_FlightRec(void* lua)
{
    double on = 0, addr = 0;
    ArgNumber(lua, &on); ArgNumber(lua, &addr);
    while (__sync_lock_test_and_set(&g_recLock, 1)) Sleep(0);
    int64_t rows = g_recRows;
    int had = g_recFile != INVALID_HANDLE_VALUE;
    RecClose();
    if (had) Log(L"flight recorder: stopped, %d rows", (int32_t)rows);
    int64_t ret = had ? rows : 0;
    if (on != 0) {
        uint8_t* plane = (uint8_t*)(uintptr_t)(uint64_t)(addr > 0 ? addr : 0);
        if (!g_nextBuildInput) ret = SV_ERR_NO_GAME;
        else if (!plane || !LiveObject(plane)) ret = SV_ERR_BAD_ARGS;
        else if (!CoResolve(plane) || g_offRoot < 0) ret = SV_ERR_NO_GAME;
        else ret = 1;
        if (ret == 1) {
            wchar_t path[PATH_CAP], name[48];
            uint16_t st[8];
            GetLocalTime(st);
            size_t k = WLen(g_modRoot);
            if (k + 64 < PATH_CAP) {
                memcpy(path, g_modRoot, k * 2);
                memcpy(path + k, L"\\recordings", 12 * 2);
                CreateDirectoryW(path, NULL);                       /* fails harmlessly when it's there */
                int v[6] = { st[0], st[1], st[3], st[4], st[5], st[6] }, w[6] = { 4, 2, 2, 2, 2, 2 }, n = 0;
                const wchar_t* pre = L"\\flight_";
                while (*pre) name[n++] = *pre++;
                for (int i = 0; i < 6; ++i) {
                    if (i == 3) name[n++] = L'_';
                    for (int d = w[i] - 1, x = v[i]; d >= 0; --d, x /= 10) name[n + d] = (wchar_t)(L'0' + x % 10);
                    n += w[i];
                }
                memcpy(name + n, L".csv", 5 * 2);
                memcpy(path + k + 11, name, (WLen(name) + 1) * 2);
                g_recFile = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
            }
            if (g_recFile == INVALID_HANDLE_VALUE) { ret = SV_ERR_REFUSED; Log(L"flight recorder: can't make the file"); }
            else {
                QueryPerformanceFrequency(&g_recFreq);
                if (g_recFreq <= 0) g_recFreq = 1;
                QueryPerformanceCounter(&g_recT0);
                g_recFlushAt = g_recT0 + 2 * g_recFreq;
                g_recRows = 0; g_recLen = 0; g_recLast = 0; g_recTarget = NULL; g_recQuatWarned = 0; g_recChecked = 0;
                g_recHealthOff = g_offHealth >= 0 ? g_offHealth : REC_HEALTH_DEFAULT;
                g_recPlane = plane;
                RecPut("t,who,id,x,y,z,qx,qy,qz,qw,speed,hp,pitch,yaw,roll,throttle,brake,highg,flags,ai,ai_speed,cobra_ok,kulbit_ok\r\n");
                Log(L"flight recorder: plane %p (RootComponent +%x, HealthInternal +%x) -> %s", plane, (uint32_t)g_offRoot,
                    (uint32_t)g_recHealthOff, path);
            }
        } else {
            Log(L"flight recorder: not started (%d)", (int32_t)ret);
        }
    }
    __sync_lock_release(&g_recLock);
    return Ret(lua, ret);
}

#endif /* SV_DEV */
