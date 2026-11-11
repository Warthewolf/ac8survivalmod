/* uobj.h : whether a UObject is still the engine's (runtime 0.32.8; flight.c's guards). GUObjectArray's globals are
 * set by flight.c UoFind; tools/checks/uobj_test.c runs UObjLive on a made-up array. */
#ifndef SV_UOBJ_H
#define SV_UOBJ_H

#define UO_GARBAGE (1u << 21)
static int32_t*       g_uoNum;                              /* GUObjectArray's NumElements */
static uint8_t* const* volatile* g_uoChunks;                /* its chunk table (FUObjectItem 0x18 bytes, 64K a chunk) */
static uint32_t*      g_uoGcFlag;                           /* the GC's unreachable flag (it changes) */


/* 1 live, 0 not (freed, garbage, unreachable, or its slot another object's), -1 can't tell (GUObjectArray not found).
 * Reads o+0xC: callers hold o where the game reads it anyway. Safe on any thread (reads only). */
static int UObjLive(const uint8_t* o)
{
    if (!g_uoChunks) return -1;
    if (!o || ((uintptr_t)o & 7) || (uintptr_t)o < 0x10000 || (uintptr_t)o > 0x7FFFFFFFFFFFull) return 0;
    int32_t idx = *(const int32_t*)(o + 0xC);
    if (idx < 0 || idx >= *g_uoNum) return 0;
    uint8_t* const* chunks = *g_uoChunks;
    const uint8_t* chunk = chunks ? chunks[idx >> 16] : NULL;
    if (!chunk) return 0;
    const uint8_t* item = chunk + (size_t)(idx & 0xFFFF) * 0x18;
    if (*(const uint8_t* const*)item != o) return 0;
    return !(*(const uint32_t*)(item + 8) & (*g_uoGcFlag | UO_GARBAGE));
}

/* o and every outer above it (UObjectBase::OuterPrivate, +0x20) live, up to 64 levels: 1 yes, 0 no, -1 can't tell.
 * UE4SS's GetFullName walks that chain with no checks: a STORE row's TextBlock (BP_LiveGameInstance_C ... WidgetTree
 * ... WBP_Menu_Text_Focus ... TextBlock) whose page was going away crashed a joiner's game in UE4SS's name walk, reading
 * 0xffffffffffffffff (2026-10-31, after a WEAPON BAYS purchase: the relabel's FindAllOf("TextBlock") + GetFullName). */
static int UObjChainLive(const uint8_t* o)
{
    if (!g_uoChunks) return -1;
    for (int depth = 0; o && depth < 64; ++depth) {
        if (UObjLive(o) != 1) return 0;
        o = *(const uint8_t* const*)(o + 0x20);
    }
    return o ? 0 : 1;                                     /* (deeper than 64: something's wrong) */
}

/* (runtime 0.32.21) 1 o is still an object of the engine's (its GUObjectArray slot holds it, whatever its flags: a
 * garbage or unreachable object is still allocated), 0 it isn't (freed: its slot empty or another object's), -1 can't
 * tell. The event guard's test (flight.c TcCheck): it refuses only what the game would read as freed memory, so an event
 * about an object that still exists is matched exactly as the game would. Reads o+0xC, as UObjLive. */
static int UObjAllocated(const uint8_t* o)
{
    if (!g_uoChunks) return -1;
    if (!o || ((uintptr_t)o & 7) || (uintptr_t)o < 0x10000 || (uintptr_t)o > 0x7FFFFFFFFFFFull) return 0;
    int32_t idx = *(const int32_t*)(o + 0xC);
    if (idx < 0 || idx >= *g_uoNum) return 0;
    uint8_t* const* chunks = *g_uoChunks;
    const uint8_t* chunk = chunks ? chunks[idx >> 16] : NULL;
    if (!chunk) return 0;
    return *(const uint8_t* const*)(chunk + (size_t)(idx & 0xFFFF) * 0x18) == o;
}

/* (Saint Alessia's 50-round co-op run, lag-1: the spawner's checks) 1 GUObjectArray's slot idx still holds o (o is
 * allocated: its memory can be read), 0 it doesn't (o was freed: the slot is empty or another object's), -1 can't tell
 * (GUObjectArray not found, or no index kept). Reads only the array, never o: for an object the runtime kept with the
 * index it had when it was found (the spawner, its world data and world), checked without a system call. */
static int UObjSlotHolds(const uint8_t* o, int32_t idx)
{
    if (!g_uoChunks || idx < 0) return -1;
    if (!o || idx >= *g_uoNum) return 0;
    uint8_t* const* chunks = *g_uoChunks;
    const uint8_t* chunk = chunks ? chunks[idx >> 16] : NULL;
    if (!chunk) return 0;
    return *(const uint8_t* const*)(chunk + (size_t)(idx & 0xFFFF) * 0x18) == o;
}

/* ---- which event fields a game function uses as UObjects (runtime 0.32.21; flight.c's event guard) -----------------
 * The game's events (FLive*Event: a vtable, the type at slot 1, the event's objects as raw pointers from +0x18) are
 * matched against the triggers of their type by slot 12 (+0x60), Match(event, trigger, a, b), on worker threads. An
 * event can outlive an object it names (it's queued as a shared pointer, and the GC doesn't see it): the host's crash of
 * 2026-11-01 10:24 (0.73.70) was EnemyBehind's Match calling through the vtable of its chaser (+0x20), an AI object
 * already freed, whose first 8 bytes the allocator had overwritten (rip 0). UoEventObjs finds, in a Match's code f[0, n),
 * the event fields +0x18..+0x30 it loads and then either tests as a UObject (the inline IsValid: `mov eax, [r+8];
 * shr eax, 0x1e`) or calls through (`mov rax, [r]` ... `call [rax+X]`, or an interface: `add r, imm32` first): bit
 * (offset >> 3) of the answer. The event is rcx at entry, or a callee-saved copy of it (`mov rbx|rbp|rsi|rdi|r12-r15,
 * rcx`); rcx counts only up to the first instruction that writes it or calls, a copy up to the first that writes the copy.
 * It works on bytes, not decoded instructions: a stray match can only end a register's range early (fewer fields, never
 * one that isn't loaded from the event). Call targets count only 16-aligned in [lo, hi) (the game's code).
 * Checked against every Match of the 2026-11-02 exe by hand (24 classes; tools/checks/uobj_test.c has some of them). */
static int UoCallAt(const uint8_t* p, const uint8_t* lo, const uint8_t* hi)
{
    if (p[0] == 0xE8) {
        const uint8_t* t = p + 5 + *(const int32_t*)(p + 1);
        return t >= lo && t < hi && !((uintptr_t)t & 15);
    }
    if (p[0] == 0xFF) {                                    /* call [rip+X], [r+X], [r], reg (rax..rdi) */
        uint8_t m = p[1];
        return m == 0x15 || m == 0x50 || m == 0x90 || (m >= 0x10 && m <= 0x17 && m != 0x14 && m != 0x15) || (m >= 0xD0 && m <= 0xD7);
    }
    return 0;
}

/* bytes at p look like an instruction writing register r (0-15), or, for rcx, a call */
static int UoWritesReg(const uint8_t* p, int r, const uint8_t* lo, const uint8_t* hi)
{
    uint8_t rex = p[0];
    if (rex == 0x48 || rex == 0x49 || rex == 0x4C || rex == 0x4D) {
        uint8_t op = p[1], m = p[2];
        int R = (rex & 4) << 1, B = (rex & 1) << 3, reg = ((m >> 3) & 7) | R, rm = (m & 7) | B;
        if ((op == 0x8B || op == 0x8D) && reg == r) return 1;                          /* mov / lea r, ... */
        if (op == 0x89 && (m & 0xC0) == 0xC0 && rm == r) return 1;                    /* mov r, reg */
        if (op == 0x33 && (m & 0xC0) == 0xC0 && rm == r && reg == r) return 1;        /* xor r, r */
        if ((op == 0x83 || op == 0x81) && (m & 0xC0) == 0xC0 && rm == r && (((m >> 3) & 7) == 0 || ((m >> 3) & 7) == 5))
            return 1;                                                                 /* add / sub r, imm */
    }
    if (r < 8 && p[0] == 0x33 && p[1] == (uint8_t)(0xC0 | r << 3 | r)) return 1;    /* xor r32, r32 */
    return r == 1 && UoCallAt(p, lo, hi);
}

/* f[0, n + 0x48) must be readable (the window after a load can reach past the end) */
static uint32_t UoEventObjs(const uint8_t* f, size_t n, const uint8_t* lo, const uint8_t* hi)
{
    static const uint8_t kCallee[8] = { 3, 5, 6, 7, 12, 13, 14, 15 };
    size_t rcxEnd = n, copyAt[16], copyEnd[16];
    for (int r = 0; r < 16; ++r) copyAt[r] = copyEnd[r] = 0;
    for (size_t i = 0; i < n; ++i) if (UoWritesReg(f + i, 1, lo, hi)) { rcxEnd = i; break; }
    for (size_t i = 0; i + 3 <= rcxEnd && i + 3 <= n; ++i) {               /* copies of the event: mov reg, rcx */
        uint8_t rex = f[i], op = f[i + 1], m = f[i + 2];
        int r = -1;
        if (op == 0x8B && (m & 0xC7) == 0xC1 && (rex == 0x48 || rex == 0x4C)) r = ((m >> 3) & 7) | (rex == 0x4C ? 8 : 0);
        else if (op == 0x89 && (m & 0xF8) == 0xC8 && (rex == 0x48 || rex == 0x49)) r = (m & 7) | (rex == 0x49 ? 8 : 0);
        if (r < 0 || copyAt[r]) continue;
        int callee = 0;
        for (int k = 0; k < 8; ++k) callee |= kCallee[k] == r;
        if (!callee) continue;
        copyAt[r] = i + 1;                                                   /* (+1: 0 means none) */
        copyEnd[r] = n;
        for (size_t j = i + 3; j < n; ++j) if (UoWritesReg(f + j, r, lo, hi)) { copyEnd[r] = j; break; }
    }
    uint32_t mask = 0;
    for (size_t i = 0; i < n; ++i) {
        uint8_t rex = f[i], m = f[i + 2];
        if ((rex != 0x48 && rex != 0x49 && rex != 0x4C && rex != 0x4D) || f[i + 1] != 0x8B) continue;
        if ((m & 0xC0) != 0x40 || (m & 7) == 4) continue;                  /* mov r64, [base + disp8], no SIB */
        int base = (m & 7) | ((rex & 1) << 3), d = ((m >> 3) & 7) | ((rex & 4) << 1), off = f[i + 3];
        if (base == 1) { if (i > rcxEnd || (i == rcxEnd && d != 1)) continue; }
        else if (!copyAt[base] || i < copyAt[base] || i >= copyEnd[base]) continue;
        if (off != 0x18 && off != 0x20 && off != 0x28 && off != 0x30) continue;
        if (d == 4) continue;
        const uint8_t* w = f + i + 4;
        int lo3 = d & 7, ok = 0;
        for (int k = 0; k + 7 <= 0x40 && !ok; ++k) {                         /* IsValid: [41] 8B 4x 08 C1 E8 1E */
            const uint8_t* q = w + k;
            if (d >= 8) ok = q[0] == 0x41 && q[1] == 0x8B && q[2] == (uint8_t)(0x40 | lo3) && q[3] == 0x08 && q[4] == 0xC1 && q[5] == 0xE8 && q[6] == 0x1E;
            else ok = q[0] == 0x8B && q[1] == (uint8_t)(0x40 | lo3) && q[2] == 0x08 && q[3] == 0xC1 && q[4] == 0xE8 && q[5] == 0x1E &&
                      (k == 0 || w[k - 1] != 0x41);
        }
        if (!ok && lo3 != 4 && lo3 != 5) {
            uint8_t rw = d >= 8 ? 0x49 : 0x48;
            for (int k = 0; k < 0x20 && !ok; ++k) {
                const uint8_t* q = w + k;
                if (q[0] == rw && q[1] == 0x8B && q[2] == lo3) {                 /* mov rax, [r]; [one 3-byte mov;] call */
                    ok = (q[3] == 0xFF && (q[4] == 0x50 || q[4] == 0x90)) ||
                         ((q[3] == 0x48 || q[3] == 0x49) && q[6] == 0xFF && (q[7] == 0x50 || q[7] == 0x90));
                } else if (q[0] == rw && q[1] == 0x81 && q[2] == (uint8_t)(0xC0 | lo3)) {   /* add r, imm32; mov rax, [r]; call */
                    ok = q[7] == rw && q[8] == 0x8B && q[9] == lo3 && q[10] == 0xFF && (q[11] == 0x50 || q[11] == 0x90);
                }
            }
        }
        if (ok) mask |= 1u << (off >> 3);
    }
    return mask;
}

/* An FWeakObjectPtr { int32 ObjectIndex, int32 ObjectSerialNumber } at w: 1 if it resolves to a live object, 0 if it
 * doesn't (null, freed, garbage, unreachable: what the game's FWeakObjectPtr::Get, 0x141ad7cb0, answers NULL for),
 * -1 can't tell. As the game's inlined lookup (0x147443d18): a serial of 0 is a null pointer; the item's serial
 * (+0x10) must match. */
static int UWeakLive(const uint8_t* w)
{
    if (!g_uoChunks) return -1;
    if (!w) return 0;
    int32_t idx = *(const int32_t*)w, serial = *(const int32_t*)(w + 4);
    if (!serial || idx < 0 || idx >= *g_uoNum) return 0;
    uint8_t* const* chunks = *g_uoChunks;
    const uint8_t* chunk = chunks ? chunks[idx >> 16] : NULL;
    if (!chunk) return 0;
    const uint8_t* item = chunk + (size_t)(idx & 0xFFFF) * 0x18;
    if (*(const int32_t*)(item + 0x10) != serial || !*(const uint8_t* const*)item) return 0;
    return !(*(const uint32_t*)(item + 8) & (*g_uoGcFlag | UO_GARBAGE));
}

#endif
