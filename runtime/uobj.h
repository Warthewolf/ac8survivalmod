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
