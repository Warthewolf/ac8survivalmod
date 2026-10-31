/* uobj_test.c (tools/checks/uobj_test.sh): runtime/uobj.h's UObjLive on a made-up GUObjectArray, as the game lays it
 * out (a chunk table of 64K FUObjectItems of 0x18 bytes: the object, its internal flags, ...; an object's InternalIndex
 * at +0xC). A live object must always pass (flight.c's guards skip what fails: a live unit failing would vanish from
 * every weapon's target search); a freed one, one whose slot another object took, a garbage or unreachable one, a
 * wild pointer must fail; with no array found it can't tell (-1). */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "../../runtime/uobj.h"

static int fails;
static void check(int ok, const char* what) { printf("  %s %s\n", ok ? "ok  " : "FAIL", what); if (!ok) ++fails; }

int main(void)
{
    check(UObjLive((const uint8_t*)0x10000000) == -1, "no GUObjectArray found: can't tell (-1)");
    static int32_t num;
    static uint32_t gcFlag = 2;                            /* (ReachabilityFlag1, the game's value at start) */
    uint8_t* chunk0 = calloc(65536, 0x18), * chunk1 = calloc(65536, 0x18);
    uint8_t* table[4] = { chunk0, chunk1, NULL, NULL };
    uint8_t* const* tableP = table;
    g_uoNum = &num; g_uoGcFlag = &gcFlag; g_uoChunks = (uint8_t* const* volatile*)&tableP;
    num = 65536 + 100;
    uint8_t* objs[6];
    int32_t idx[6] = { 5, 65536 + 7, 65535, 12, 13, 14 };
    for (int i = 0; i < 6; ++i) {
        objs[i] = _aligned_malloc(0x40, 16); memset(objs[i], 0, 0x40);
        *(int32_t*)(objs[i] + 0xC) = idx[i];
        uint8_t* item = table[idx[i] >> 16] + (size_t)(idx[i] & 0xFFFF) * 0x18;
        *(uint8_t**)item = objs[i];
        *(uint32_t*)(item + 8) = 1u << 0;                  /* (another reachability flag: live) */
    }
    check(UObjLive(objs[0]) == 1, "a live object in chunk 0");
    check(UObjLive(objs[1]) == 1, "a live object in chunk 1 (index 65543)");
    check(UObjLive(objs[2]) == 1, "a live object at a chunk's last slot");
    *(uint32_t*)(table[0] + 12 * 0x18 + 8) |= UO_GARBAGE;
    check(UObjLive(objs[3]) == 0, "marked garbage: not live");
    *(uint32_t*)(table[0] + 13 * 0x18 + 8) |= 2;
    check(UObjLive(objs[4]) == 0, "carrying the GC's unreachable flag (2): not live");
    gcFlag = 4;
    check(UObjLive(objs[4]) == 1, "the GC's flag moved on (4): the same object live again");
    gcFlag = 2;
    *(uint8_t**)(table[0] + 14 * 0x18) = NULL;
    check(UObjLive(objs[5]) == 0, "its slot freed (no object): not live");
    *(uint8_t**)(table[0] + 14 * 0x18) = objs[0];
    check(UObjLive(objs[5]) == 0, "its slot another object's: not live");
    *(int32_t*)(objs[5] + 0xC) = 0;                        /* (freed memory zeroed: index 0, the slot of another) */
    check(UObjLive(objs[5]) == 0, "freed and zeroed (index 0, another object's slot): not live");
    *(int32_t*)(objs[5] + 0xC) = -1;
    check(UObjLive(objs[5]) == 0, "index -1: not live");
    *(int32_t*)(objs[5] + 0xC) = num;
    check(UObjLive(objs[5]) == 0, "index past the count: not live");
    *(int32_t*)(objs[5] + 0xC) = 3 * 65536;
    num = 4 * 65536;
    check(UObjLive(objs[5]) == 0, "index in a chunk not made yet: not live");
    check(UObjLive(NULL) == 0, "null: not live");
    check(UObjLive((const uint8_t*)(objs[0] + 4)) == 0, "a misaligned pointer: not live");
    check(UObjLive((const uint8_t*)0x400000002ull + 0x7FFFFFFFFFFFull) == 0, "past user space: not live");
    check(UObjLive(objs[0]) == 1 && UObjLive(objs[1]) == 1, "the live ones still live");
    /* weak pointers { index, serial } */
    *(int32_t*)(table[0] + 5 * 0x18 + 0x10) = 77;          /* (objs[0]'s serial) */
    *(int32_t*)(table[1] + 7 * 0x18 + 0x10) = 78;          /* (objs[1]'s) */
    int32_t w[2];
    w[0] = 5; w[1] = 77;           check(UWeakLive((const uint8_t*)w) == 1, "a weak pointer to a live object");
    w[0] = 65536 + 7; w[1] = 78;   check(UWeakLive((const uint8_t*)w) == 1, "a weak pointer into chunk 1");
    w[0] = 5; w[1] = 76;           check(UWeakLive((const uint8_t*)w) == 0, "its serial changed (the slot reused): gone");
    w[0] = 5; w[1] = 0;            check(UWeakLive((const uint8_t*)w) == 0, "serial 0 (a null weak pointer): gone");
    w[0] = 12; w[1] = 0;
    *(int32_t*)(table[0] + 12 * 0x18 + 0x10) = 9; w[1] = 9;
    check(UWeakLive((const uint8_t*)w) == 0, "to a garbage object (an actor just destroyed): gone");
    w[0] = 14; w[1] = 5;
    *(int32_t*)(table[0] + 14 * 0x18 + 0x10) = 5; *(uint8_t**)(table[0] + 14 * 0x18) = NULL;
    check(UWeakLive((const uint8_t*)w) == 0, "its slot freed: gone");
    w[0] = -1; w[1] = 3;           check(UWeakLive((const uint8_t*)w) == 0, "index -1: gone");
    check(UWeakLive(NULL) == 0, "no pointer: gone");
    printf(fails ? "uobj test: %d FAILED\n" : "uobj test: all passed\n", fails);
    return fails ? 1 : 0;
}
