/* survival_rt_lua.c : part of survival_rt.c (one translation unit: survival_rt.c #includes it in place, after
 *  coop.c and flight.c; never compiled on its own). Survival's own sounds (XAudio2), the Lua functions the bridge
 *  registers (SV_MemMB .. SV_RecycleWait; RegisterLua's table stays in survival_rt.c, where
 *  tools/checks/lua_check.py reads it) and the leaderboard with its own (SV_BuildHash, SV_Post, SV_SteamName, ...:
 *  left out of the Offline edition, SV_OFFLINE). */

/* ---- sound: Survival's own sound effects (XAudio2) ---------------------------------------------------------------
 * AC8 plays only its own Wwise banks, so Survival's own sounds (AC7's railgun sounds for VALKA: AGENTS.md's exception,
 * tools/ac7_sfx.py) play through XAudio2 2.9 (xaudio2_9.dll, part of Windows 10 and 11), loaded at run time and called
 * through its COM vtables: no SDK, so the slots and the packed structs below are xaudio2.h's. Sounds are 16-bit PCM
 * WAVs under the mod's Sounds\ folder (a smpl chunk's first loop is the loop region); one stereo mastering voice.
 * Lua works out distance and pan and passes a gain per side.                                                      */
#pragma pack(push, 1)                              /* (xaudio2.h packs its structs to 1 byte; WAVEFORMATEX to 2)   */
typedef struct { uint16_t tag, channels; uint32_t rate, byteRate; uint16_t align, bits, extra; } SndFormat;
typedef struct {
    uint32_t flags, bytes; const uint8_t* data;
    uint32_t playBegin, playLength, loopBegin, loopLength, loopCount; void* context;
} SndXBuffer;                                      /* XAUDIO2_BUFFER       */
typedef struct { void* context; uint32_t queued; uint64_t played; } SndXState;   /* XAUDIO2_VOICE_STATE */
#pragma pack(pop)
_Static_assert(sizeof(SndFormat) == 18, "WAVEFORMATEX layout");
_Static_assert(sizeof(SndXBuffer) == 44, "XAUDIO2_BUFFER layout");
_Static_assert(sizeof(SndXState) == 20, "XAUDIO2_VOICE_STATE layout");

#define SND_VT(o, i)          (((void**)*(void**)(o))[i])
#define SND_MAX_SOUNDS        64
#define SND_MAX_VOICES        48
#define SND_END_OF_STREAM     0x40u
#define SND_LOOP_INFINITE     255u
#define SND_NO_SAMPLES_PLAYED 0x100u
#define SND_ERR_NO_AUDIO      -1                   /* XAudio2 couldn't start (no device?)                            */
#define SND_ERR_FILE          -2                   /* no such file, or it can't be read                              */
#define SND_ERR_FORMAT        -3                   /* not a 16-bit PCM WAV                                           */
#define SND_ERR_FULL          -4                   /* too many sounds loaded / voices playing                        */

typedef struct {
    char      name[64];
    uint8_t*  file;                                /* the whole file (data points into it); never freed            */
    SndFormat fmt;
    const uint8_t* data;
    uint32_t  bytes, loopBegin, loopLength;        /* loop in frames; loopLength 0 = none (the whole file loops)    */
} SndSound;
typedef struct { void* voice; uint32_t gen; int32_t sound; } SndVoice;

static struct {
    int      state;                                /* 0 not tried, 1 ok, -1 failed                                  */
    void*    xa;                                   /* IXAudio2*                                                     */
    void*    master;                               /* IXAudio2MasteringVoice*                                       */
    SndSound sounds[SND_MAX_SOUNDS];
    int32_t  nSounds;
    SndVoice voices[SND_MAX_VOICES];
} SND;

static int SndInit(void)
{
    if (SND.state) return SND.state > 0;
    SND.state = -1;
    HANDLE ole = LoadLibraryW(L"ole32.dll");
    int32_t (*coInit)(void*, DWORD) = ole ? (int32_t (*)(void*, DWORD))GetProcAddress(ole, "CoInitializeEx") : NULL;
    if (coInit) coInit(NULL, 0);                   /* (COINIT_MULTITHREADED; a thread already in COM keeps its own)  */
    HANDLE dll = LoadLibraryW(L"xaudio2_9.dll");
    if (!dll) { Log(L"sound: xaudio2_9.dll not found (error %u); no sound effects", GetLastError()); return 0; }
    int32_t (*create)(void**, uint32_t, uint32_t) = (int32_t (*)(void**, uint32_t, uint32_t))GetProcAddress(dll, "XAudio2Create");
    int32_t (*createV)(void**, uint32_t, uint32_t, uint32_t) =
        (int32_t (*)(void**, uint32_t, uint32_t, uint32_t))GetProcAddress(dll, "XAudio2CreateWithVersionInfo");
    int32_t hr = -1;
    if (createV) hr = createV(&SND.xa, 0, 1, 0x0A000005u);      /* (Processor1; NTDDI_WIN10_RS4)                     */
    else if (create) hr = create(&SND.xa, 0, 1);
    if (hr < 0 || !SND.xa) { Log(L"sound: XAudio2Create failed (0x%x); no sound effects", (uint32_t)hr); return 0; }
    /* IXAudio2::CreateMasteringVoice(this, out, channels 2, rate 0 = the device's, flags, device, effects, GameEffects) */
    hr = ((int32_t (*)(void*, void**, uint32_t, uint32_t, uint32_t, const wchar_t*, void*, uint32_t))SND_VT(SND.xa, 7))(
        SND.xa, &SND.master, 2, 0, 0, NULL, NULL, 6);
    if (hr < 0 || !SND.master) {
        Log(L"sound: no mastering voice (0x%x); no sound effects", (uint32_t)hr);
        ((uint32_t (*)(void*))SND_VT(SND.xa, 2))(SND.xa);                                   /* Release */
        SND.xa = NULL;
        return 0;
    }
    Log(L"sound: XAudio2 2.9 up (stereo mastering voice)");
    SND.state = 1;
    return 1;
}

static uint32_t SndU32(const uint8_t* p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

/* the sound named `name` (a path under Sounds\, '/' or '\'), loaded once: its index, or an SND_ERR code */
static int32_t SndLoad(const wchar_t* name)
{
    char an[64];
    size_t n = WLen(name);
    if (!n || n >= sizeof(an)) return SND_ERR_FILE;
    for (size_t i = 0; i <= n; ++i) an[i] = (char)name[i];
    for (int32_t i = 0; i < SND.nSounds; ++i) {
        const char* a = SND.sounds[i].name;
        size_t k = 0;
        while (a[k] && a[k] == an[k]) ++k;
        if (!a[k] && !an[k]) return i;
    }
    if (SND.nSounds >= SND_MAX_SOUNDS) return SND_ERR_FULL;
    wchar_t path[PATH_CAP];
    size_t root = WLen(g_modRoot);
    if (root + n + 9 >= PATH_CAP) return SND_ERR_FILE;
    memcpy(path, g_modRoot, root * 2);
    memcpy(path + root, L"\\Sounds\\", 8 * 2);
    for (size_t i = 0; i <= n; ++i) path[root + 8 + i] = name[i] == L'/' ? L'\\' : name[i];
    HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) { Log(L"sound: %s not found", path); return SND_ERR_FILE; }
    int64_t size = 0;
    uint8_t* buf = NULL;
    DWORD got = 0;
    if (GetFileSizeEx(f, &size) && size > 44 && size < 64 * 1024 * 1024) buf = (uint8_t*)malloc((size_t)size);
    BOOL ok = buf && ReadFile(f, buf, (DWORD)size, &got, NULL) && got == (DWORD)size;
    CloseHandle(f);
    if (!ok) { if (buf) free(buf); Log(L"sound: %s can't be read", path); return SND_ERR_FILE; }
    SndSound* s = &SND.sounds[SND.nSounds];
    memset(s, 0, sizeof(*s));
    if (SndU32(buf) != 0x46464952u || SndU32(buf + 8) != 0x45564157u) { free(buf); return SND_ERR_FORMAT; }   /* RIFF WAVE */
    int haveFmt = 0;
    for (size_t at = 12; at + 8 <= (size_t)size; ) {
        uint32_t id = SndU32(buf + at), len = SndU32(buf + at + 4);
        const uint8_t* c = buf + at + 8;
        if (at + 8 + (uint64_t)len > (uint64_t)size) len = (uint32_t)((size_t)size - at - 8);
        if (id == 0x20746D66u && len >= 16) {                        /* "fmt " */
            memcpy(&s->fmt, c, 16);
            s->fmt.extra = 0;
            haveFmt = 1;
        } else if (id == 0x61746164u) {                              /* "data" */
            s->data = c; s->bytes = len;
        } else if (id == 0x6C706D73u && len >= 36 + 24 && SndU32(c + 28) > 0) {   /* "smpl": its first loop */
            uint32_t b = SndU32(c + 36 + 8), e = SndU32(c + 36 + 12);
            if (e > b) { s->loopBegin = b; s->loopLength = e - b + 1; }
        }
        at += 8 + (size_t)len + (len & 1);
    }
    if (!haveFmt || !s->data || s->fmt.tag != 1 || s->fmt.bits != 16 || s->fmt.channels < 1 || s->fmt.channels > 2
        || s->fmt.align != s->fmt.channels * 2) {                 /* (align 0 would divide by zero below) */
        free(buf); Log(L"sound: %s is not a 16-bit PCM WAV", path); return SND_ERR_FORMAT;
    }
    s->bytes -= s->bytes % s->fmt.align;                          /* whole frames only (XAudio2 refuses a part one) */
    uint32_t frames = s->bytes / s->fmt.align;
    if (s->loopLength && s->loopBegin + s->loopLength > frames) s->loopLength = 0;
    s->file = buf;
    memcpy(s->name, an, n + 1);
    Log(L"sound: %s: %u Hz, %u ch, %u frames%s", path, s->fmt.rate, (uint32_t)s->fmt.channels, frames,
        s->loopLength ? L", a loop" : L"");
    return SND.nSounds++;
}

static void SndDestroy(SndVoice* v)
{
    if (!v->voice) return;
    ((int32_t (*)(void*, uint32_t, uint32_t))SND_VT(v->voice, 20))(v->voice, 0, 0);        /* Stop      */
    ((void (*)(void*))SND_VT(v->voice, 18))(v->voice);                                    /* DestroyVoice */
    v->voice = NULL;
}

/* finished voices are destroyed (never from an XAudio2 callback: there are none) */
static void SndReap(void)
{
    for (int i = 0; i < SND_MAX_VOICES; ++i) {
        SndVoice* v = &SND.voices[i];
        if (!v->voice) continue;
        SndXState st = { 0 };
        ((void (*)(void*, SndXState*, uint32_t))SND_VT(v->voice, 25))(v->voice, &st, SND_NO_SAMPLES_PLAYED);   /* GetState */
        if (st.queued == 0) SndDestroy(v);
    }
}

static SndVoice* SndHandle(int64_t h)
{
    int64_t i = (h & 0xFF) - 1;
    if (h <= 0 || i < 0 || i >= SND_MAX_VOICES) return NULL;
    SndVoice* v = &SND.voices[i];
    return v->voice && v->gen == (uint32_t)(h >> 8) ? v : NULL;
}

static void SndLevels(SndVoice* v, double left, double right, double ratio)
{
    const SndSound* s = &SND.sounds[v->sound];
    float m[4];
    uint32_t ch = s->fmt.channels;
    if (ch == 1) { m[0] = (float)left; m[1] = (float)right; }           /* mono -> L, R                          */
    else { m[0] = (float)left; m[1] = 0; m[2] = 0; m[3] = (float)right; } /* [dst * src + src]: L->L, R->R         */
    ((int32_t (*)(void*, void*, uint32_t, uint32_t, const float*, uint32_t))SND_VT(v->voice, 16))(v->voice, NULL, ch, 2, m, 0);
    if (ratio < 0.0625) ratio = 0.0625;
    if (ratio > 4.0) ratio = 4.0;
    ((int32_t (*)(void*, float, uint32_t))SND_VT(v->voice, 26))(v->voice, (float)ratio, 0);   /* SetFrequencyRatio */
}

/* SV_MemMB() -> working set MB x 100000 + commit charge (private bytes) MB, or -1: the game's memory for the log
 * (sv_main.lua memText splits it; the 0.69 X-02S container ran the game to ~21 GB during a 3.5-minute load, 2026-10-25) */
static int L_MemMB(void* lua)
{
    PROCESS_MEMORY_COUNTERS pmc;
    memset(&pmc, 0, sizeof(pmc));
    pmc.cb = sizeof(pmc);
    if (!K32GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc))) return Ret(lua, -1);
    return Ret(lua, (int64_t)(pmc.WorkingSetSize >> 20) * 100000 + (int64_t)(pmc.PagefileUsage >> 20));
}

/* SV_SndLoad(name) -> the sound's id (> 0) or an error (-1 no audio, -2 no file, -3 not 16-bit PCM, -4 too many);
 * name: a WAV under the mod's Sounds\ folder, e.g. "valka/shot_main.wav" */
static int L_SndLoad(void* lua)
{
    wchar_t name[64];
    if (!ArgName(lua, name, 64)) return Ret(lua, SV_ERR_BAD_ARGS);
    if (!SndInit()) return Ret(lua, SND_ERR_NO_AUDIO);
    int32_t i = SndLoad(name);
    return Ret(lua, i < 0 ? i : i + 1);
}

/* SV_SndPlay(id, left, right[, ratio, loop]) -> a voice handle (> 0) or an error; left / right: linear gains per side
 * (1 = as recorded), ratio: the playback rate (pitch), loop 1: loops its smpl region (or the whole sound) until stopped */
static int L_SndPlay(void* lua)
{
    double id = 0, left = 1, right = 1, ratio = 1, loop = 0;
    if (!ArgNumber(lua, &id)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &left); ArgNumber(lua, &right); ArgNumber(lua, &ratio); ArgNumber(lua, &loop);
    if (!SndInit()) return Ret(lua, SND_ERR_NO_AUDIO);
    int32_t si = (int32_t)id - 1;
    if (si < 0 || si >= SND.nSounds) return Ret(lua, SV_ERR_BAD_ARGS);
    SndReap();
    int slot = -1;
    for (int i = 0; i < SND_MAX_VOICES && slot < 0; ++i) if (!SND.voices[i].voice) slot = i;
    if (slot < 0) return Ret(lua, SND_ERR_FULL);
    SndSound* s = &SND.sounds[si];
    SndVoice* v = &SND.voices[slot];
    /* IXAudio2::CreateSourceVoice(this, out, format, flags, max ratio 4, callback, sends, effects) */
    int32_t hr = ((int32_t (*)(void*, void**, const SndFormat*, uint32_t, float, void*, void*, void*))SND_VT(SND.xa, 5))(
        SND.xa, &v->voice, &s->fmt, 0, 4.0f, NULL, NULL, NULL);
    if (hr < 0 || !v->voice) { v->voice = NULL; Log(L"sound: CreateSourceVoice failed (0x%x)", (uint32_t)hr); return Ret(lua, SND_ERR_NO_AUDIO); }
    SndXBuffer b = { 0 };
    b.flags = SND_END_OF_STREAM;
    b.bytes = s->bytes;
    b.data = s->data;
    if (loop != 0) {
        b.loopBegin = s->loopLength ? s->loopBegin : 0;
        b.loopLength = s->loopLength;                       /* (0 with LoopBegin 0: the whole sound)                  */
        b.loopCount = SND_LOOP_INFINITE;
    }
    hr = ((int32_t (*)(void*, const SndXBuffer*, void*))SND_VT(v->voice, 21))(v->voice, &b, NULL);   /* SubmitSourceBuffer */
    if (hr < 0) { SndDestroy(v); Log(L"sound: SubmitSourceBuffer failed (0x%x)", (uint32_t)hr); return Ret(lua, SND_ERR_FORMAT); }
    v->sound = si;
    v->gen = (v->gen + 1) & 0xFFFFFF;
    SndLevels(v, left, right, ratio);
    ((int32_t (*)(void*, uint32_t, uint32_t))SND_VT(v->voice, 19))(v->voice, 0, 0);          /* Start */
    return Ret(lua, ((int64_t)v->gen << 8) | (slot + 1));
}

/* SV_SndSet(handle, left, right[, ratio]) -> 1, or 0 when that voice is over */
static int L_SndSet(void* lua)
{
    double h = 0, left = 1, right = 1, ratio = 1;
    if (!ArgNumber(lua, &h)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &left); ArgNumber(lua, &right); ArgNumber(lua, &ratio);
    SndVoice* v = SND.state > 0 ? SndHandle((int64_t)h) : NULL;
    if (!v) return Ret(lua, 0);
    SndXState st = { 0 };
    ((void (*)(void*, SndXState*, uint32_t))SND_VT(v->voice, 25))(v->voice, &st, SND_NO_SAMPLES_PLAYED);   /* GetState */
    if (st.queued == 0) { SndDestroy(v); return Ret(lua, 0); }             /* (over: Lua forgets it) */
    SndLevels(v, left, right, ratio);
    return Ret(lua, 1);
}

/* SV_SndStop(handle[, tail]) -> 1, or 0 when that voice was already over; tail 1: a loop plays out to its end */
static int L_SndStop(void* lua)
{
    double h = 0, tail = 0;
    if (!ArgNumber(lua, &h)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &tail);
    SndVoice* v = SND.state > 0 ? SndHandle((int64_t)h) : NULL;
    if (!v) return Ret(lua, 0);
    if (tail != 0) ((int32_t (*)(void*, uint32_t))SND_VT(v->voice, 24))(v->voice, 0);      /* ExitLoop */
    else SndDestroy(v);
    return Ret(lua, 1);
}

/* SV_SndMaster(gain) -> 1, or -1 without audio: the linear volume of everything Survival plays */
static int L_SndMaster(void* lua)
{
    double g = 1;
    ArgNumber(lua, &g);
    if (!SndInit()) return Ret(lua, SND_ERR_NO_AUDIO);
    ((int32_t (*)(void*, float, uint32_t))SND_VT(SND.master, 12))(SND.master, (float)(g < 0 ? 0 : g), 0);   /* SetVolume */
    return Ret(lua, 1);
}

/* SV_Version() -> RT_VERSION_A (until 0.28.4 a fixed "0.27.0", whatever the build: co-op's "hi" said every player ran
 * 0.27.0, and a stale main.dll couldn't be told from a current one) */
/* SV_MenuChoice() -> the last main-menu entry picked (g_menuChoice: 0 none yet or another entry, 1 SURVIVAL MODE, 2 SP
 * OFFLINE, 3 CO-OP: HOST, 4 CO-OP: JOIN, 5 SP ONLINE, 6 Survival's pages opened) + 16 x how many were picked, so the same entry
 * picked again is seen (a retry after a failed co-op open). Lua: % 16 the entry, // 16 the picks. */
static int L_MenuChoice(void* lua) { return Ret(lua, (int64_t)g_menuChoice + 16 * (int64_t)g_menuPicks); }

static int L_Version(void* lua)
{
    static const char v[] = RT_VERSION_A;
    U.luaSetString(lua, v, sizeof(v) - 1);
    return 1;
}

/* SV_Spawn(unit [, x, y, z, yaw]) -> aircraft spawned (> 0) or an SV_ERR code; position in cm, yaw in degrees */
static int L_Spawn(void* lua)
{
    wchar_t name[96];
    double pose[4];
    if (!ArgName(lua, name, 96)) return Ret(lua, SV_ERR_BAD_ARGS);
    int n = 0;
    while (n < 4 && ArgNumber(lua, &pose[n])) ++n;
    if (n != 0 && n != 4) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, Spawn(name, n ? pose : NULL));
}

/* SV_SetLevel(unit, level) -> AI objects changed (their LevelId: 100 x the AI level) or an SV_ERR code */
static int L_SetLevel(void* lua)
{
    wchar_t name[96];
    double level = -1;
    if (!ArgName(lua, name, 96) || !ArgNumber(lua, &level)) return Ret(lua, SV_ERR_BAD_ARGS);
    if (level < 0 || level > 65535) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, SetLevel(name, (int32_t)level));
}

/* SV_PlaneLevel(address) -> a spawned plane's AILevel value (u16 at plane +0x1048), or SV_ERR_BAD_ARGS; for the log */
static int L_PlaneLevel(void* lua)
{
    double addr = 0;
    if (!ArgNumber(lua, &addr) || addr <= 0) return Ret(lua, SV_ERR_BAD_ARGS);
    uint8_t* plane = (uint8_t*)(uintptr_t)(uint64_t)addr;
    if (g_teardown) return Ret(lua, SV_ERR_NOT_READY);     /* (0.32.22: the level is being torn down) */
    if (!LiveObject(plane) || !Readable(plane + PLANE_AI_LEVEL, 2)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, *(uint16_t*)(plane + PLANE_AI_LEVEL));
}

/* SV_PlayerTarget(plane) -> the address of the player plane's current target (the enemy it has selected, the one its
 * missiles go for), 0 for none, SV_ERR_BAD_ARGS for a bad plane. docs/re/UNIQUE_ACTIONS.md: the player tick posts
 * EnemyBehind for player+0x1ae8 -> +0x750. Confirmed in game 2026-10-23 (it named the Reaper ace the player had
 * targeted). Not used by Lua at the moment (the flight recorder that used it is gone). */
#define PLAYER_TARGET_HOLDER 0x1ae8
#define PLAYER_TARGET        0x750
static int L_PlayerTarget(void* lua)
{
    double addr = 0;
    if (!ArgNumber(lua, &addr) || addr <= 0) return Ret(lua, SV_ERR_BAD_ARGS);
    uint8_t* plane = (uint8_t*)(uintptr_t)(uint64_t)addr;
    if (g_teardown) return Ret(lua, SV_ERR_NOT_READY);     /* (0.32.22: the level is being torn down) */
    if (!LiveObject(plane) || !Readable(plane + PLAYER_TARGET_HOLDER, 8)) return Ret(lua, SV_ERR_BAD_ARGS);
    uint8_t* holder = *(uint8_t**)(plane + PLAYER_TARGET_HOLDER);
    if (!holder || !Readable(holder + PLAYER_TARGET, 8)) return Ret(lua, 0);
    uint8_t* target = *(uint8_t**)(holder + PLAYER_TARGET);
    if (!target || !LiveObject(target)) return Ret(lua, 0);
    return Ret(lua, (int64_t)(uintptr_t)target);
}

/* SV_SetAircraft(unit, npc [, index]) -> AI objects changed or an SV_ERR code */
static int L_SetAircraft(void* lua)
{
    wchar_t name[96], npc[96];
    double idx = -1;
    if (!ArgName(lua, name, 96) || !ArgName(lua, npc, 96)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &idx);
    return Ret(lua, SetAircraft(name, npc, (int)idx));
}

/* SV_UnitAlive(unit) -> aircraft alive in its current flight, SV_NOT_SPAWNED, or an SV_ERR code */
static int L_UnitAlive(void* lua)
{
    wchar_t name[96];
    if (!ArgName(lua, name, 96)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, UnitAlive(name));
}

/* SV_Crumb(text) -> 1: a line in the crash breadcrumbs (AC8SurvivalMode_crumbs.log), at once */
static int L_Crumb(void* lua)
{
    wchar_t text[240];
    if (!ArgName(lua, text, 240)) return Ret(lua, SV_ERR_BAD_ARGS);
    Crumb(L"lua: %s", text);
    return Ret(lua, 1);
}

/* SV_LogUnits([why]) -> length of the phase's unit list (written to AC8SurvivalMode.log) */
static int L_LogUnits(void* lua)
{
    wchar_t why[64];
    if (!ArgName(lua, why, 64)) memcpy(why, L"asked by Lua", 13 * 2);
    return Ret(lua, LogUnits(why));
}

/* SV_Ammo(kind [, max]) -> the player's current (or, with max = 1, maximum) count; kind 0 gun, 1 missiles,
 * 2 special 1, 3 special 2, 4 flares. SV_NOT_SPAWNED for a slot the aircraft doesn't have, or an SV_ERR code. */
static int L_Ammo(void* lua)
{
    double kind = -1, wantMax = 0;
    if (!ArgNumber(lua, &kind)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &wantMax);
    return Ret(lua, AmmoGet((int)kind, wantMax != 0));
}

/* SV_SetAmmo(kind, count) -> the new count (capped at the weapon's maximum; count < 0 = full) or an SV_ERR code */
static int L_SetAmmo(void* lua)
{
    double kind = -1, value = 0;
    if (!ArgNumber(lua, &kind) || !ArgNumber(lua, &value)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, AmmoSet((int)kind, (int32_t)value));
}

/* SV_AmmoMax(kind, max) -> the new maximum (full load) of kind 1-4, or an SV_ERR code (see AmmoSetMax) */
static int L_AmmoMax(void* lua)
{
    double kind = -1, max = 0;
    if (!ArgNumber(lua, &kind) || !ArgNumber(lua, &max)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, AmmoSetMax((int)kind, (int32_t)max));
}

/* SV_FreeRestock(on) -> the old setting (1 on, 0 off) or an SV_ERR code; on = 0 stops missiles refilling over time */
static int L_SetFreeRestock(void* lua)
{
    double on = 0;
    if (!ArgNumber(lua, &on)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, SetFreeRestock(on != 0));
}

/* SV_GameLua(code [, chunkname]) -> "<status>\t<result>" from the game's own Lua (see "the game's own Lua") */
static int L_GameLua(void* lua)
{
    static char out[32768];
    if (U.luaStackSize(lua) < 1 || !U.luaIsString(lua, 1)) { U.luaSetString(lua, "-4\tno code", 10); return 1; }
    StrView sv = { NULL, 0 };
    U.luaGetString(lua, &sv, 1);
    char* code = (char*)malloc(sv.n + 1);
    if (!code) { U.luaSetString(lua, "4\tout of memory", 15); return 1; }
    memcpy(code, sv.p, sv.n);
    code[sv.n] = 0;
    size_t n = sv.n;
    char name[96] = "=SurvivalMode";
    if (U.luaStackSize(lua) >= 1 && U.luaIsString(lua, 1)) {
        StrView nv = { NULL, 0 };
        U.luaGetString(lua, &nv, 1);
        if (nv.p && nv.n && nv.n < sizeof(name) - 1) { name[0] = '='; memcpy(name + 1, nv.p, nv.n); name[nv.n + 1] = 0; }
    }
    int st = GameLuaRun(code, n, name, out + 8, sizeof(out) - 8);
    free(code);
    char head[8]; int h = 0, v = st < 0 ? -st : st;
    if (st < 0) head[h++] = '-';
    char t[4]; int k = 0;
    do { t[k++] = (char)('0' + v % 10); v /= 10; } while (v && k < 3);
    while (k) head[h++] = t[--k];
    head[h++] = '\t';
    char* res = out + 8 - h;                     /* the status goes right in front of the result */
    memcpy(res, head, h);
    size_t len = h;
    while (res[len]) ++len;
    U.luaSetString(lua, res, len);
    return 1;
}

/* SV_GameLuaState([create]) -> the game's lua_State address (changes if the game makes a new one), 0 while there is
 * none. create = 1 makes it the way the game does on its first AI spawn (GetGameLuaState), for Survival's level only. */
typedef void* (*GetGameLuaStateFn)(void);
static int L_GameLuaState(void* lua)
{
    double create = 0;
    ArgNumber(lua, &create);
    void* L = GameLuaState();
    if (!L && create != 0 && GL.state > 0) {
        Log(L"game Lua: no state yet; asking the plugin to make it (GetGameLuaState)");
        ((GetGameLuaStateFn)g_fGameLuaState)();
        L = GameLuaState();
        Log(L"game Lua: state now %p", L);
    }
    return Ret(lua, (int64_t)(uintptr_t)L);
}

/* SV_PlayBGM(event [, delay]) -> the Wwise playing id (0: refused, already playing, or queued by a delay) or an
 * SV_ERR code (SV_ERR_NO_UNIT: the game has no such name); see "music and remote events" */
static int L_PlayBGM(void* lua)
{
    wchar_t name[128];
    double delay = 0;
    if (!ArgName(lua, name, 128)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &delay);
    return Ret(lua, PlayBgm(name, (float)delay));
}

/* SV_BGM([field]) -> the BGM controller's playing id (0), status byte (1) or last posted id (2), or an SV_ERR code */
static int L_BGM(void* lua)
{
    double field = 0;
    ArgNumber(lua, &field);
    return Ret(lua, BgmState((int)field));
}

/* SV_BGMNames() -> "<track>|<last stop>|<last event>": the BGM controller's FNames at +0x120 (the track Play posted:
 * 0x1478bdbc0 "lea rsi,[rdi+0x120]; mov [rsi],rbx"), +0x13C (LiveStopBGMExecution: "mov [rbx+0x13c],rcx") and +0x14C
 * (LiveEventBGMExecution: "mov [rdi+0x14c],rcx"), or "" when there is no controller. For finding what interrupts the
 * pause menu's music player (user, 2026-10-22: the track skips when a kill happens). */
static int L_BGMNames(void* lua)
{
    static const int32_t kOff[3] = { 0x120, 0x13C, 0x14C };
    char out[400];
    size_t n = 0;
    uint8_t* bgm = BgmController(0);
    for (int i = 0; bgm && i < 3; ++i) {
        wchar_t w[120];
        if (!Readable(bgm + kOff[i], 8)) break;
        NameText((const FNameRaw*)(bgm + kOff[i]), w, 120);
        if (i) out[n++] = '|';
        for (size_t k = 0; w[k] && n < sizeof(out) - 2; ++k) out[n++] = w[k] < 0x80 ? (char)w[k] : '?';
    }
    out[n] = 0;
    U.luaSetString(lua, out, n);
    return 1;
}

/* SV_Event(name) -> 1 once remote event `name` is dispatched in Survival's level, or an SV_ERR code */
static int L_Event(void* lua)
{
    wchar_t name[128];
    if (!ArgName(lua, name, 128)) return Ret(lua, SV_ERR_BAD_ARGS);
    return Ret(lua, FireEvent(name));
}

/* SV_MusicPlayer([on]) -> the old setting (1 shown, 0 not), or SV_ERR_NO_GAME when the pause list wasn't hooked;
 * on = 0 keeps the stock pause menu (no music player row) in Survival */
static int L_MusicPlayer(void* lua)
{
    double on = -1;
    ArgNumber(lua, &on);
    if (!g_nextPauseValidity) return Ret(lua, SV_ERR_NO_GAME);
    int64_t old = g_musicPlayer;
    if (on >= 0) g_musicPlayer = on != 0;
    return Ret(lua, old);
}

/* SV_MusicClock([on]) -> the old setting (1: the music player's track clock is held while Survival's BGM is paused,
 * 0: the stock clock), or SV_ERR_NO_GAME when the clock wasn't hooked */
/* SV_MusicHold(on) -> the hold it had: Lua holds the music player's track clock (in Survival's mission only) while the
 * landing store is open, as a paused BGM channel does */
static int L_MusicHold(void* lua)
{
    double on = -1;
    ArgNumber(lua, &on);
    if (!g_nextMusicTick) return Ret(lua, SV_ERR_NO_GAME);
    int64_t old = g_musicForceHold;
    if (on >= 0) g_musicForceHold = on != 0;
    return Ret(lua, old);
}

/* (runtime 0.32.30) SV_MusicBuild(manager) -> 1 rebuilt, 0 not now (a music player track is playing: the rebuild
 * replaces the list it plays from), SV_ERR_BAD_ARGS (not a live object), SV_ERR_NO_GAME (not found / not hooked).
 * manager: the level's ULiveMusicPlayerSoundManager (Lua: FindFirstOf, its world Survival's). Game thread only. */
static int L_MusicBuild(void* lua)
{
    uint8_t* mgr = ArgObject(lua);
    if (!g_fMusicRebuild || !g_nextMusicBuild) return Ret(lua, SV_ERR_NO_GAME);
    if (!mgr || ((uintptr_t)mgr & 7) || !Readable(mgr, MPM_CONTROLLER + 8)) return Ret(lua, SV_ERR_BAD_ARGS);
    int live = UObjLive(mgr);
    if (live < 0) live = LiveObject(mgr);
    if (live != 1) return Ret(lua, SV_ERR_BAD_ARGS);
    uint8_t* co = PtrAt(mgr, MPM_CONTROLLER);
    if (co && Readable(co + MPC_EVENT, 0x20) && *(int32_t*)(co + MPC_EVENT + 8) > 1 && !co[MPC_STOPPED]) return Ret(lua, 0);
    ((MusicBuildFn)g_fMusicRebuild)(mgr);
    return Ret(lua, 1);
}

/* SV_MusicSave(save, owned, newly) -> 1 named (each track list build's grants to those two arrays are cut back off),
 * 0 off (save 0), SV_ERR_BAD_ARGS (not a live save with those arrays in it: off), SV_ERR_NO_GAME (no build hook).
 * save: the LiveCampaignSaveGame; owned / newly: its CampaignSaveData.MusicPlayer.OwnedMusicList / NewlyOwnedMusicList
 * (TArray:GetArrayAddress()). */
static int L_MusicSave(void* lua)
{
    double s = 0, a = 0, b = 0;
    ArgNumber(lua, &s); ArgNumber(lua, &a); ArgNumber(lua, &b);
    if (!g_nextMusicBuild) return Ret(lua, SV_ERR_NO_GAME);
    if (s <= 0) { g_msSave = NULL; return Ret(lua, 0); }
    g_msArr[0] = (uint8_t*)(uintptr_t)(uint64_t)a;
    g_msArr[1] = (uint8_t*)(uintptr_t)(uint64_t)b;
    g_msSave = (uint8_t*)(uintptr_t)(uint64_t)s;
    if (MsSaveOk()) return Ret(lua, 1);
    g_msSave = NULL;
    return Ret(lua, SV_ERR_BAD_ARGS);
}

/* (runtime 0.32.31) SV_MusicLen(event, ms) -> how many songs have a length; event "" clears them. A looping Online Mode
 * track (MusicLoopCap) moves on after its song's own length instead of SV_MusicLoop's. */
static int L_MusicLen(void* lua)
{
    char name[72];
    size_t n = 0;
    double ms = 0;
    if (!ArgBytes(lua, name, sizeof(name), &n)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &ms);
    if (n == 0) { g_nmlen = 0; return Ret(lua, 0); }
    int i = 0;
    for (; i < g_nmlen; ++i) {                            /* (no C library here: compared by hand) */
        const char* x = g_mlen[i].name;
        size_t j = 0;
        while (j < n && x[j] == name[j]) ++j;
        if (j == n && x[n] == 0) break;
    }
    if (i == g_nmlen) {
        if (g_nmlen >= MLEN_MAX) return Ret(lua, SV_ERR_BAD_ARGS);
        memcpy(g_mlen[i].name, name, n + 1);
        ++g_nmlen;
    }
    g_mlen[i].ms = ms < 0 ? 0 : ms > 3600000 ? 3600000 : (int32_t)ms;
    return Ret(lua, g_nmlen);
}

/* SV_MusicLoop(ms) -> the old length; ms 0 = a track that loops for ever plays until skipped (SV_ERR_NO_GAME: no clock hook) */
static int L_MusicLoop(void* lua)
{
    double ms = -1;
    ArgNumber(lua, &ms);
    if (!g_nextMusicTick) return Ret(lua, SV_ERR_NO_GAME);
    int64_t old = g_musicLoopMs;
    if (ms >= 0) g_musicLoopMs = ms > 3600000 ? 3600000 : (int32_t)ms;
    return Ret(lua, old);
}

static int L_MusicClock(void* lua)
{
    double on = -1;
    ArgNumber(lua, &on);
    if (!g_nextMusicTick) return Ret(lua, SV_ERR_NO_GAME);
    int64_t old = g_musicClockHold;
    if (on >= 0) g_musicClockHold = on != 0;
    return Ret(lua, old);
}

/* SV_Invert(pitch, roll, fade_s, plane[, yaw, swap_axes, swap_throttle]) -> the factor pitch had (x100: 100 normal,
 * -100 inverted), or SV_ERR_NO_GAME when BuildFlightInput wasn't hooked. pitch / roll / yaw 1 = invert that axis,
 * swap_axes 1 = pitch and roll swapped, swap_throttle 1 = throttle and brake swapped, 0 = normal; the changes fade over
 * fade_s; plane = the player's ALivePlayerPlane address (only that plane's input is touched; 0 = none). Turning the
 * effects back off keeps the plane until the fade is over. */
static int L_SetControlInvert(void* lua)
{
    double pitch = 0, roll = 0, fade = 1.5, addr = 0, yaw = 0, swapAxes = 0, swapThrottle = 0;
    ArgNumber(lua, &pitch); ArgNumber(lua, &roll); ArgNumber(lua, &fade); ArgNumber(lua, &addr);
    ArgNumber(lua, &yaw); ArgNumber(lua, &swapAxes); ArgNumber(lua, &swapThrottle);
    if (!g_nextBuildInput) return Ret(lua, SV_ERR_NO_GAME);
    int64_t old = (int64_t)(g_invScale[INV_PITCH] * 100.0f);
    uint8_t* plane = (uint8_t*)(uintptr_t)(uint64_t)(addr > 0 ? addr : 0);
    if (plane && !LiveObject(plane)) return Ret(lua, SV_ERR_BAD_ARGS);
    if (plane != g_invPlane) { for (int a = 0; a < INV_N; ++a) g_invScale[a] = 1.0f; g_invLastMs = 0; }
    g_invFadeMs = (int32_t)(fade * 1000.0);
    g_invWant[INV_PITCH] = pitch != 0; g_invWant[INV_ROLL] = roll != 0; g_invWant[INV_YAW] = yaw != 0;
    g_invWant[INV_SWAP_AXES] = swapAxes != 0; g_invWant[INV_SWAP_THROTTLE] = swapThrottle != 0;
    g_invPlane = plane;
    return Ret(lua, old);
}

/* SV_SetText(key, text) -> 1, or 0 (not an SV_ key, or 64 keys already): the text the game shows for text key `key`
 * (menu rows and help lines that name it), ASCII; longer than 255 characters is cut there */
static int L_SetText(void* lua)
{
    static wchar_t text[1024];                     /* longer than a slot: SetDynText keeps the first 255 */
    wchar_t key[DYN_KEY];
    if (!ArgName(lua, key, DYN_KEY)) return Ret(lua, SV_ERR_BAD_ARGS);
    if (!ArgName(lua, text, 1024)) { text[0] = L' '; text[1] = 0; }           /* "" (or longer) is refused by ArgName */
    return Ret(lua, SetDynText(key, text));
}

/* SV_ShopRequest() -> the StringArgs of the oldest shop row picked on the landing menu and not yet taken
 * ("SV_Buy_..."), or "" when none is waiting. SV_ShopRequest(1) -> 1 if the landing menu hook is installed, else 0
 * (without the hook a shop row would reach the stock decide, which reads it as a page number). */
static int L_ShopRequest(void* lua)
{
    double query = 0;
    if (ArgNumber(lua, &query) && query != 0) return Ret(lua, g_nextHangarDecide ? 1 : 0);
    char out[32];
    size_t n = 0;
    if (g_shopCount > 0) {
        const wchar_t* q = g_shopQueue[g_shopHead];
        while (n < 31 && q[n]) { out[n] = (char)q[n]; ++n; }
        g_shopHead = (g_shopHead + 1) % SHOP_QUEUE;
        --g_shopCount;
    }
    out[n] = 0;
    U.luaSetString(lua, out, n);
    return 1;
}

/* SV_MenuPages(1 | 0): Survival's pages are (not) in the game's page list (Scripts/sv_menu.lua checked it): only then
 * does the SURVIVAL MODE row that opens them pass. -> 1 */
static int L_MenuPages(void* lua)
{
    double v = 0;
    if (!ArgNumber(lua, &v)) return Ret(lua, SV_ERR_BAD_ARGS);
    if ((v != 0) != (g_pagesOk != 0)) Log(L"main menu: Survival's pages %s", v != 0 ? L"are in the game's page list" : L"are not in the game's page list");
    g_pagesOk = v != 0;
    return Ret(lua, 1);
}

/* SV_MenuClass(n, class): Survival's page n (1-5: sv_menu.lua PAGES, kPageNames) is that widget class. -> 1 */
static int L_MenuClass(void* lua)
{
    double n = 0;
    if (!ArgNumber(lua, &n) || n < 1 || n > MENU_PAGE_N) return Ret(lua, SV_ERR_BAD_ARGS);
    uint8_t* c = ArgObject(lua);
    if (c && !Readable(c, 0x30)) return Ret(lua, SV_ERR_BAD_ARGS);
    g_pageClass[(int)n - 1] = c;
    return Ret(lua, 1);
}

/* SV_MenuSlot(manager, class, index, slot) -> 1 when the main menu manager's MenuWidgetClassList entry `index` is found:
 * kSlotIds[slot]'s (0 CampaignTraining, 1 InitialSetting_DualSence, 2 InitialSetting_Accessibility), holding that class (0: any), found by a look through
 * the manager for the list (TArray of { FString MenuIDName, UClass* MenuClass }, 0x18 bytes each); 0 not found */
#define MENU_ENTRY_SIZE 0x18
static int L_MenuSlot(void* lua)
{
    uint8_t* mgr = ArgObject(lua);
    uint8_t* stock = ArgObject(lua);
    double idx = -1, which = 0;
    ArgNumber(lua, &idx);
    ArgNumber(lua, &which);
    if (!mgr || idx < 0 || idx > 255 || which < 0 || which >= MENU_SLOT_N || which != (int)which) return Ret(lua, SV_ERR_BAD_ARGS);
    int w = (int)which;
    const wchar_t* want = kSlotIds[w];
    g_pageSlot[w] = NULL;
    for (size_t off = 0x28; off < 0x400; off += 8) {
        if (!Readable(mgr + off, 16)) break;
        uint8_t* data = *(uint8_t**)(mgr + off);
        int32_t num = *(int32_t*)(mgr + off + 8), max = *(int32_t*)(mgr + off + 12);
        if (!data || num <= (int32_t)idx || num > 256 || max < num) continue;
        uint8_t* e = data + (size_t)idx * MENU_ENTRY_SIZE;
        if (!Readable(e, MENU_ENTRY_SIZE)) continue;
        const FString* id = (const FString*)e;
        size_t n = WLen(want);
        if (!id->data || id->num != (int32_t)n + 1 || !Readable(id->data, n * 2) || memcmp(id->data, want, n * 2)) continue;
        uint8_t** slot = (uint8_t**)(e + 0x10);
        if (stock && *slot != stock) continue;
        g_pageSlot[w] = slot;
        g_slotStock[w] = *slot;
        Log(L"main menu: Survival's pages open through %s's page (entry %d, list at manager+%x)", want, (int32_t)idx, (uint32_t)off);
        return Ret(lua, 1);
    }
    Log(L"main menu: %s's entry %d not found in the main menu's page list", want, (int32_t)idx);
    return Ret(lua, 0);
}

/* SV_MenuQuick(code): the mode QUICK START plays (2 SP OFFLINE, 3 COOP HOST, 5 SP ONLINE; Lua's last one). -> 1 */
static int L_MenuQuick(void* lua)
{
    double v = 0;
    if (!ArgNumber(lua, &v) || !(v == 2 || v == 3 || v == 5)) return Ret(lua, SV_ERR_BAD_ARGS);
    g_quickMode = (int32_t)v;
    return Ret(lua, 1);
}

/* SV_MenuSetting() -> the StringArgs of the oldest settings row picked on the main menu and not yet taken
 * ("SV_Set_..."), or "" when none is waiting */
static int L_MenuSetting(void* lua)
{
    char out[32];
    size_t n = 0;
    if (g_setCount > 0) {
        const wchar_t* q = g_setQueue[g_setHead];
        while (n < 31 && q[n]) { out[n] = (char)q[n]; ++n; }
        g_setHead = (g_setHead + 1) % SET_QUEUE;
        --g_setCount;
    }
    out[n] = 0;
    U.luaSetString(lua, out, n);
    return 1;
}

/* SV_Reset(): forget the level's spawner (Lua calls it when a level loads) */
static int L_Reset(void* lua)
{
    g_spawner = NULL; g_phase = NULL; g_wd = NULL;
    g_spawnerLost = 0;                             /* a new run: search for its spawner again (hotfix5) */
    g_shopHead = g_shopCount = 0;                  /* a pick made as the level ended isn't bought in the next run */
    if (g_teardown) {                              /* (0.32.22) the next Survival level: the gate opens */
        Log(L"teardown gate: open (a new Survival level: SV_Reset)");
        Crumb(L"teardown gate open (SV_Reset)");
    }
    g_teardown = 0;
    g_world = NULL;                                /* (the next SpawnerReady keeps this level's; a restart's is the same one) */
    PtReset();                                     /* (the path tracker guard's skip list: flight.c) */
    return Ret(lua, 1);
}

/* (0.32.22, plan F1a) SV_LevelGone() -> 1 the teardown gate is closed (Survival's level is being torn down: no level
 * object may be touched until the next level's SV_Reset), 0 open. Lua asks at the top of each tick half (sv_core.lua
 * levelGate). Checked at the call: the world it watches gone closes it. */
static int L_LevelGone(void* lua) { return Ret(lua, TeardownCheck()); }

/* (0.32.22) SV_Recycle(unit [, force]) -> 1 taken off the phase's list (so its desc can spawn again; its unit actor
 * destroyed later, F2b), 0 nothing to do (not on the list), SV_ERR_UP (-3: aircraft still counted alive and force 0), or
 * an SV_ERR code (-1 not ready / the level going, -2 no unit, -4 bad arguments). force 1: off the list even while it
 * still counts aircraft alive (a joiner's stuck copies, a special's leftovers); 2: that, its actor destroyed at once (the
 * 0.32.21 way, for the F2d test). Behind the target and path tracker guards. Every call logged. */
static int L_Recycle(void* lua)
{
    wchar_t name[96];
    double force = 0;
    if (!ArgName(lua, name, 96)) return Ret(lua, SV_ERR_BAD_ARGS);
    ArgNumber(lua, &force);
    int f = force >= 2 ? 2 : force >= 1 ? 1 : 0;
    int64_t r = SpawnerReady();
    if (r == 1) {
        FNameRaw fn;
        uint8_t* desc = MakeName(name, &fn) ? FindDesc(&fn) : NULL;
        if (!desc) r = SV_ERR_NO_UNIT;
        else { int rc = Recycle(desc, name, f); r = rc < 0 ? SV_ERR_UP : rc; }
    }
    Log(L"recycle %s (SV_Recycle, force %d): %s (%d)", name, f, r == 1 ? L"taken off the phase's list" : r == 0 ? L"not on the "
        L"phase's list: nothing to do" : r == SV_ERR_UP ? L"still up: not forced" : L"not done", (int32_t)r);
    return Ret(lua, r);
}

/* (0.32.22) SV_RecycleWait(seconds) -> the old wait in seconds: how long a recycled flight's unit actor waits before it's
 * destroyed (0: at once, the 0.32.21 way); SV_RecycleWait(-1) destroys every one waiting now (the break between rounds);
 * no argument: ask */
static int L_RecycleWait(void* lua)
{
    double s = -2;
    ArgNumber(lua, &s);
    int64_t old = (int64_t)(g_rcWaitMs / 1000);
    if (s >= 0 && s <= 600) {
        uint32_t ms = (uint32_t)(s * 1000.0);
        if (ms != g_rcWaitMs) Log(L"recycle: a recycled flight's unit actor is destroyed %d s after it's taken off the list%s",
                                  (int32_t)s, ms ? L"" : L" (at once, as before 0.32.22)");
        g_rcWaitMs = ms;
    } else if (s == -1 && g_rcN) {
        for (int i = 0; i < g_rcN; ++i) g_rc[i].due = 0;
        if (SpawnerReady() == 1) Log(L"recycle: every recycled flight's unit actor waiting was destroyed now (asked)");
    }
    return Ret(lua, old);
}

/* The Offline edition (runtime/build.sh OFFLINE=1, user, 2026-10-23: "None of the Code for sending the files remains")
 * is built with SV_OFFLINE: everything from here to RegisterLua (WinHTTP, bcrypt, the address and key, the Steam name)
 * is left out, and so are its Lua functions; main.lua's leaderboard half is stripped from that edition too. */
#ifndef SV_OFFLINE
/* ---------------------------------------------------------------------------------------- leaderboard (Milestone 8)
 * SV_Post(json) -> a job number (1..8) or an SV_ERR code: sends a finished run to the leaderboard Worker
 * (leaderboard/src/index.js, POST /submit) on a thread of its own, so the game never waits on the network: HTTPS
 * through WinHTTP, the body signed with HMAC-SHA256 (bcrypt) under the build's submit key, in X-SV-Signature.
 * The Worker's host and the key come from leaderboard/submit.local through runtime/build.sh (build/runtime/
 * submit_cfg.h, never in git); a build without them answers SV_ERR_NO_SERVER. Only that host is ever contacted.
 * SV_PostResult(job) -> 0 while sending, then the HTTP status, or < 0 when it couldn't get through: minus WinHTTP's
 * error (e.g. -12007 the name didn't resolve, -12029 no connection, -12002 timed out, -12175 TLS failed), or -1 / -2
 * when Windows gave none; the job is freed once its result is read. SV_PostReply(job) -> the Worker's reply.
 * The build (runtime 0.28.6; user, 2026-10-30: "we need a way that the Leaderboards can detect if a run has been edited
 * from the stock run"): the mod's files are hashed when the game starts (build_hash.c, on a thread of its own) and again
 * for every send; the send carries that hash in X-SV-Build and is signed over "<hash>\n<body>", so the Worker counts a
 * run only from a build the user registered (leaderboard/README.md). A hash that changed since the start is logged.
 * SV_BuildHash() -> the hash (64 hex characters), "" while it's worked out or when it couldn't be (the log says why). */
#if __has_include("submit_cfg.h")
#include "submit_cfg.h"
#endif
#ifndef SV_SUBMIT_HOST
#define SV_SUBMIT_HOST L""
#define SV_SUBMIT_PATH L"/submit"
#define SV_SUBMIT_KEY  ""
#endif
#define SV_ERR_NO_SERVER -8
#define SV_ERR_BUSY      -9
#define POST_JOBS 8
#define POST_BODY 16384
typedef struct {
    volatile int32_t state;            /* 0 free, 1 sending, 2 done */
    int32_t status;
    DWORD   len, replyLen;
    char    body[POST_BODY];
    char    reply[512];
} PostJob;
static PostJob g_post[POST_JOBS];

typedef HANDLE (*HttpOpenFn)(const wchar_t*, DWORD, const wchar_t*, const wchar_t*, DWORD);
typedef HANDLE (*HttpConnectFn)(HANDLE, const wchar_t*, uint16_t, DWORD);
typedef HANDLE (*HttpOpenRequestFn)(HANDLE, const wchar_t*, const wchar_t*, const wchar_t*, const wchar_t*, const wchar_t**, DWORD);
typedef BOOL   (*HttpSendFn)(HANDLE, const wchar_t*, DWORD, void*, DWORD, DWORD, uintptr_t);
typedef BOOL   (*HttpReceiveFn)(HANDLE, void*);
typedef BOOL   (*HttpQueryFn)(HANDLE, DWORD, const wchar_t*, void*, DWORD*, DWORD*);
typedef BOOL   (*HttpReadFn)(HANDLE, void*, DWORD, DWORD*);
typedef BOOL   (*HttpCloseFn)(HANDLE);
typedef BOOL   (*HttpTimeoutsFn)(HANDLE, int, int, int, int);
#include "build_hash.c"                               /* the build hash and the HMAC (runtime 0.28.6) */

/* HMAC-SHA256 under the build's key of build + "\n" + body (build: a build hash, or NULL: the body alone, as before
 * 0.28.6), as 64 hex characters (wide, for the header); 0 if bcrypt failed */
static int SignBody(const char* build, const char* body, DWORD len, wchar_t* hex)
{
    static const char key[] = SV_SUBMIT_KEY;
    char pre[66], mac[65];
    size_t preLen = 0;
    if (build) {
        while (build[preLen] && preLen < 64) { pre[preLen] = build[preLen]; ++preLen; }
        pre[preLen++] = '\n';
    }
    if (!BhHmac(key, sizeof(key) - 1, pre, preLen, body, len, mac)) return 0;
    for (int i = 0; i <= 64; ++i) hex[i] = (wchar_t)mac[i];
    return 1;
}

/* The build hash: worked out on a thread when the game starts (BuildHashThread), then again for each send */
static char             g_buildHex[65];             /* "" until it's known */
static volatile int32_t g_buildLock;
static wchar_t          g_ioDir[PATH_CAP];          /* ...\Mods\IoStoreLoaderMod\SurvivalMode (set in start_mod) */

static void BuildHexGet(char* out)
{
    while (__sync_lock_test_and_set(&g_buildLock, 1)) Sleep(0);
    memcpy(out, g_buildHex, sizeof(g_buildHex));
    __sync_lock_release(&g_buildLock);
}

static void BuildHexSet(const char* hex)
{
    while (__sync_lock_test_and_set(&g_buildLock, 1)) Sleep(0);
    memcpy(g_buildHex, hex, sizeof(g_buildHex));
    __sync_lock_release(&g_buildLock);
}

static void WidenHex(const char* hex, wchar_t* out) { int i = 0; for (; i < 64 && hex[i]; ++i) out[i] = (wchar_t)hex[i]; out[i] = 0; }

/* The build hash now into hex (65 characters), 1; 0 (logged) when it couldn't be worked out. why: the log line's start */
static int BuildHashNow(char* hex, const wchar_t* why)
{
    BhRun r;
    memset(&r, 0, sizeof(r));
    uint64_t t0 = GetTickCount64();
    if (!g_modRoot[0] || !g_ioDir[0] || !BuildHash(g_modRoot, g_ioDir, hex, &r)) {
        Log(L"leaderboard: %s: no build hash (%s%s%s); runs go without one", why, g_modRoot[0] ? (r.why ? r.why : L"?") : L"no mod folder",
            r.whyFile[0] && g_modRoot[0] ? L": " : L"", g_modRoot[0] ? r.whyFile : L"");
        return 0;
    }
    wchar_t w[65];
    WidenHex(hex, w);
    Log(L"leaderboard: %s: build hash %s (%d scripts, %d behaviour scripts, the ini, main.dll and the container: %d files, %d KB, %d ms)",
        why, w, (int32_t)r.scripts, (int32_t)r.ai, (int32_t)r.files, (int32_t)(r.bytes / 1024), (int32_t)(GetTickCount64() - t0));
    return 1;
}

static DWORD WINAPI BuildHashThread(void* arg)
{
    (void)arg;
    char hex[65];
    if (BuildHashNow(hex, L"the game started")) BuildHexSet(hex);
    return 0;
}

static int L_BuildHash(void* lua)
{
    char hex[65];
    BuildHexGet(hex);
    size_t n = 0;
    while (n < 64 && hex[n]) ++n;
    U.luaSetString(lua, hex, n == 64 ? 64 : 0);
    return 1;
}

static DWORD WINAPI PostWorker(void* arg)
{
    PostJob* j = (PostJob*)arg;
    j->status = -1;
    HANDLE wh = LoadLibraryW(L"winhttp.dll");
    HttpOpenFn hOpen = wh ? (HttpOpenFn)GetProcAddress(wh, "WinHttpOpen") : NULL;
    HttpConnectFn hConnect = wh ? (HttpConnectFn)GetProcAddress(wh, "WinHttpConnect") : NULL;
    HttpOpenRequestFn hRequest = wh ? (HttpOpenRequestFn)GetProcAddress(wh, "WinHttpOpenRequest") : NULL;
    HttpSendFn hSend = wh ? (HttpSendFn)GetProcAddress(wh, "WinHttpSendRequest") : NULL;
    HttpReceiveFn hReceive = wh ? (HttpReceiveFn)GetProcAddress(wh, "WinHttpReceiveResponse") : NULL;
    HttpQueryFn hQuery = wh ? (HttpQueryFn)GetProcAddress(wh, "WinHttpQueryHeaders") : NULL;
    HttpReadFn hRead = wh ? (HttpReadFn)GetProcAddress(wh, "WinHttpReadData") : NULL;
    HttpCloseFn hClose = wh ? (HttpCloseFn)GetProcAddress(wh, "WinHttpCloseHandle") : NULL;
    HttpTimeoutsFn hTimeouts = wh ? (HttpTimeoutsFn)GetProcAddress(wh, "WinHttpSetTimeouts") : NULL;
    wchar_t headers[320], sig[65];
    /* the build as it is now (the files may have changed since the game started: then this one, and it's logged) */
    char build[65], was[65];
    int haveBuild = BuildHashNow(build, L"sending a run");
    if (haveBuild) {
        BuildHexGet(was);
        if (was[0] && memcmp(was, build, 64) != 0) {
            wchar_t a[65];
            WidenHex(was, a);
            Log(L"leaderboard: the mod's files changed since the game started (its build hash was %s): this run goes as the files are now", a);
        }
        BuildHexSet(build);
    }
    if (!hOpen || !hConnect || !hRequest || !hSend || !hReceive || !hQuery || !hRead || !hClose
        || !SignBody(haveBuild ? build : NULL, j->body, j->len, sig)) {
        Log(L"leaderboard: WinHTTP or bcrypt missing; run not sent");
        j->state = 2;
        return 0;
    }
    static const wchar_t head[] = L"Content-Type: application/json\r\nX-SV-Signature: ";
    static const wchar_t bhead[] = L"X-SV-Build: ";
    size_t n = 0;
    for (size_t i = 0; head[i]; ++i) headers[n++] = head[i];
    for (size_t i = 0; sig[i]; ++i) headers[n++] = sig[i];
    headers[n++] = L'\r'; headers[n++] = L'\n';
    if (haveBuild) {
        for (size_t i = 0; bhead[i]; ++i) headers[n++] = bhead[i];
        for (size_t i = 0; i < 64; ++i) headers[n++] = (wchar_t)build[i];
        headers[n++] = L'\r'; headers[n++] = L'\n';
    }
    headers[n] = 0;
    /* Each proxy mode in turn (automatic, the system's, none), with TLS 1.2 / 1.3 switched on: WinHTTP's own defaults
     * can leave TLS 1.2 off (older or tweaked Windows), which Cloudflare refuses at once (a friend's test of 2026-10-23:
     * the browser reached the Worker, the game failed in 0.25 s). */
    typedef BOOL (*HttpOptionFn)(HANDLE, DWORD, void*, DWORD);
    HttpOptionFn hOption = (HttpOptionFn)GetProcAddress(wh, "WinHttpSetOption");
    static const DWORD kAccess[] = { 4 /* automatic proxy */, 0 /* the system's (netsh winhttp) */, 1 /* none */ };
    DWORD err = 0;
    for (size_t a = 0; a < sizeof(kAccess) / sizeof(kAccess[0]) && j->status < 0; ++a) {
        err = 0;
        HANDLE ses = hOpen(L"AC8SurvivalMode", kAccess[a], NULL, NULL, 0);
        if (ses && hOption) {
            DWORD tls = 0x00000800 | 0x00002000;                   /* WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 | TLS1_3 */
            if (!hOption(ses, 84 /* WINHTTP_OPTION_SECURE_PROTOCOLS */, &tls, sizeof(tls))) {
                tls = 0x00000800;                                  /* (no TLS 1.3 before Windows 11) */
                hOption(ses, 84, &tls, sizeof(tls));
            }
        }
        HANDLE con = ses ? hConnect(ses, SV_SUBMIT_HOST, 443, 0) : NULL;
        HANDLE req = con ? hRequest(con, L"POST", SV_SUBMIT_PATH, NULL, NULL, NULL, 0x00800000 /* WINHTTP_FLAG_SECURE */) : NULL;
        if (req && hTimeouts) hTimeouts(req, 10000, 10000, 15000, 15000);
        if (!ses || !con || !req) err = GetLastError();
        j->replyLen = 0;
        if (req && hSend(req, headers, (DWORD)-1, j->body, j->len, j->len, 0)) {
            if (hReceive(req, NULL)) {
                DWORD code = 0, sz = sizeof(code);
                if (hQuery(req, 19 | 0x20000000 /* STATUS_CODE | FLAG_NUMBER */, NULL, &code, &sz, NULL)) j->status = (int32_t)code;
                DWORD got = 0;
                while (j->replyLen < sizeof(j->reply) - 1 && hRead(req, j->reply + j->replyLen, (DWORD)(sizeof(j->reply) - 1 - j->replyLen), &got) && got)
                    j->replyLen += got;
            } else {
                err = GetLastError();
            }
        } else if (req) {
            err = GetLastError();
        }
        if (j->status < 0) {
            j->status = err ? -(int32_t)err : -1;                 /* why it couldn't get through (WinHTTP's error) */
            Log(L"leaderboard: proxy mode %d: no connection (%d)", (int32_t)kAccess[a], j->status);
        }
        if (req) hClose(req);
        if (con) hClose(con);
        if (ses) hClose(ses);
    }
    j->reply[j->replyLen] = 0;
    Log(L"leaderboard: run sent, status %d", j->status);
    j->state = 2;
    return 0;
}

static int L_Post(void* lua)
{
    if (!SV_SUBMIT_HOST[0] || sizeof(SV_SUBMIT_KEY) <= 1) return Ret(lua, SV_ERR_NO_SERVER);
    if (U.luaStackSize(lua) < 1 || !U.luaIsString(lua, 1)) return Ret(lua, SV_ERR_BAD_ARGS);
    StrView sv = { NULL, 0 };
    U.luaGetString(lua, &sv, 1);
    if (!sv.p || !sv.n || sv.n >= POST_BODY) return Ret(lua, SV_ERR_BAD_ARGS);
    for (int i = 0; i < POST_JOBS; ++i) {
        PostJob* j = &g_post[i];
        if (j->state != 0) continue;
        memcpy(j->body, sv.p, sv.n);
        j->len = (DWORD)sv.n; j->replyLen = 0; j->reply[0] = 0; j->status = 0;
        j->state = 1;
        HANDLE th = CreateThread(NULL, 0, PostWorker, j, 0, NULL);
        if (!th) { j->state = 0; return Ret(lua, SV_ERR_BUSY); }
        CloseHandle(th);
        return Ret(lua, i + 1);
    }
    return Ret(lua, SV_ERR_BUSY);
}

static int L_PostResult(void* lua)
{
    double id = 0;
    if (!ArgNumber(lua, &id) || id < 1 || id > POST_JOBS) return Ret(lua, SV_ERR_BAD_ARGS);
    PostJob* j = &g_post[(int)id - 1];
    if (j->state != 2) return Ret(lua, 0);
    int32_t st = j->status;
    j->state = 0;                                   /* read: free again (its reply stays until the next send) */
    return Ret(lua, st);
}

static int L_PostReply(void* lua)
{
    double id = 0;
    if (!ArgNumber(lua, &id) || id < 1 || id > POST_JOBS) { U.luaSetString(lua, "", 0); return 1; }
    PostJob* j = &g_post[(int)id - 1];
    U.luaSetString(lua, j->reply, j->replyLen);
    return 1;
}

/* SV_SteamName() -> the player's Steam name (UTF-8), or "" when Steam isn't there: the leaderboard's default pilot
 * name (user, 2026-10-23). Read from the steam_api64.dll the game has already loaded (its flat API: SteamFriends_v017,
 * the game's Steamworks 1.57); nothing is loaded or initialised here, and only the name is read. */
typedef void* (*SteamFriendsFn)(void);
typedef const char* (*PersonaNameFn)(void* friends);
static int L_SteamName(void* lua)
{
    HANDLE st = GetModuleHandleW(L"steam_api64.dll");
    const char* name = NULL;
    if (st) {
        static const char* kFriends[] = { "SteamAPI_SteamFriends_v017", "SteamAPI_SteamFriends_v018", "SteamAPI_SteamFriends_v016" };
        PersonaNameFn persona = (PersonaNameFn)GetProcAddress(st, "SteamAPI_ISteamFriends_GetPersonaName");
        for (size_t i = 0; persona && !name && i < sizeof(kFriends) / sizeof(kFriends[0]); ++i) {
            SteamFriendsFn get = (SteamFriendsFn)GetProcAddress(st, kFriends[i]);
            void* fr = get ? get() : NULL;
            if (fr) name = persona(fr);
        }
    }
    size_t n = 0;
    while (name && name[n] && n < 128) ++n;
    U.luaSetString(lua, name ? name : "", n);
    return 1;
}

#endif /* SV_OFFLINE */
