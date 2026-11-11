/* unittab_test.c (tools/checks/unittab_test.sh): runtime/unittab.h, the spawner's id -> unit table (Saint Alessia's
 * 50-round co-op run, lag-1), on a made-up phase list, against the old walk (RegisteredUnit before the table: the first
 * entry, in the list's order, that is readable and has the id). Every answer must be the walk's, and repeated asks on a
 * list that hasn't changed must not walk it again: the old code walked every entry on every ask (the test fails it on the
 * walk counts). Covered: the spawner's own changes (gen), the game's (count, data, an entry replaced in place), an
 * address reused by another unit, an entry gone unreadable, duplicate ids, the refresh, an empty list, and random runs. */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "../../runtime/unittab.h"

typedef struct { uint32_t id; int readable; int allocated; } Fake;   /* a unit actor, as the checks see it */

static int fails;
static void check(int ok, const char* what) { printf("  %s %s\n", ok ? "ok  " : "FAIL", what); if (!ok) ++fails; }

static uint32_t g_fullChecks, g_idReads;
static int OkFn(void* ctx, uint8_t* u, int full)
{
    (void)ctx;
    const Fake* f = (const Fake*)u;
    if (full) { ++g_fullChecks; return f->readable && f->allocated; }
    return f->allocated;
}
static uint32_t IdFn(void* ctx, uint8_t* u) { (void)ctx; ++g_idReads; return ((const Fake*)u)->id; }

/* the old RegisteredUnit: a walk with a check on every entry */
static uint8_t* Walk(uint8_t* const* data, int32_t num, uint32_t id)
{
    for (int32_t i = 0; i < num; ++i) {
        const Fake* f = (const Fake*)data[i];
        if (f && f->readable && f->allocated && f->id == id) return data[i];
    }
    return NULL;
}

static UnitTab T;
static uint8_t* Find(uint8_t* const* data, int32_t num, uint32_t gen, uint64_t now, uint32_t id)
{
    return UtFind(&T, data, num, gen, now, id, OkFn, IdFn, NULL);
}

static uint32_t rnd = 12345;
static uint32_t Rand(void) { rnd = rnd * 1103515245u + 12345u; return rnd >> 8; }

int main(void)
{
    enum { N = 100 };
    static Fake units[400];
    static uint8_t* list[UT_MAX];
    for (int i = 0; i < 400; ++i) { units[i].id = 0x1000 + (uint32_t)i; units[i].readable = units[i].allocated = 1; }
    for (int i = 0; i < N; ++i) list[i] = (uint8_t*)&units[i];
    int32_t num = N;
    uint32_t gen = 1;
    uint64_t now = 1000;

    /* 1. repeated asks on an unchanged list: one walk, every answer the walk's */
    int same = 1;
    g_fullChecks = 0;
    for (int r = 0; r < 50; ++r)
        for (int i = 0; i < N; ++i) {
            uint32_t id = 0x1000 + (uint32_t)i;
            if (Find(list, num, gen, now, id) != Walk(list, num, id)) same = 0;
        }
    check(same, "5000 asks on a list of 100: every answer the walk's");
    check(T.builds == 1 && g_fullChecks == N, "... with one walk of it (the old lookup checked 500,000 entries)");
    check(Find(list, num, gen, now, 0x9999) == NULL && T.builds == 1, "a unit not on the list: none, without a walk");
    check(Find(list, 0, gen, now, 0x1000) == NULL, "an empty list: none");

    /* 2. the spawner's own changes (gen) */
    list[num++] = (uint8_t*)&units[N];
    ++gen;
    check(Find(list, num, gen, now, 0x1000 + N) == (uint8_t*)&units[N] && T.byGen == 1, "a flight spawned (gen): found");
    memmove(&list[10], &list[11], (size_t)(num - 11) * sizeof(list[0])); --num;            /* (Recycle: unit 10 off) */
    ++gen;
    check(Find(list, num, gen, now, 0x1000 + 10) == NULL, "a flight recycled (taken off the list): none");

    /* 3. the game's own changes, gen the same */
    list[num++] = (uint8_t*)&units[N + 1];
    check(Find(list, num, gen, now, 0x1000 + N + 1) == (uint8_t*)&units[N + 1] && T.byList == 1,
          "a unit the game added (the count changed): found");
    uint32_t b0 = T.builds;
    list[5] = (uint8_t*)&units[N + 2];                       /* (replaced in place: the same count) */
    check(Find(list, num, gen, now, 0x1000 + N + 2) == (uint8_t*)&units[N + 2] && T.builds == b0 + 1,
          "an entry replaced in place (the same count): its new unit found (the entries' hash changed)");
    check(Find(list, num, gen, now, 0x1000 + 5) == NULL, "... and the one it replaced: none");
    static uint8_t* list2[UT_MAX];
    memcpy(list2, list, (size_t)num * sizeof(list[0]));      /* (the array moved: the same entries elsewhere) */
    check(Find(list2, num, gen, now, 0x1000 + 20) == (uint8_t*)&units[20], "the list's array reallocated: found in it");

    /* 4. an address reused by another unit (hard rule 59): the hit is checked again */
    uint8_t* u30 = (uint8_t*)&units[30];
    check(Find(list2, num, gen, now, 0x1000 + 30) == u30, "unit 30 found");
    units[30].id = 0x7777;                                    /* (freed, its address another unit's, in the same place) */
    check(Find(list2, num, gen, now, 0x1000 + 30) == NULL && T.byMoved == 1,
          "its address reused by another unit: the old id no longer answers (the hit checked again, the table rebuilt)");
    check(Find(list2, num, gen, now, 0x7777) == u30, "... and the new unit's id finds it");
    units[30].id = 0x1000 + 30;
    ++gen;
    check(Find(list2, num, gen, now, 0x1000 + 30) == u30, "back (gen): found again");

    /* 5. an entry gone unreadable or freed: never answered */
    units[40].allocated = 0;
    check(Find(list2, num, gen, now, 0x1000 + 40) == NULL && Walk(list2, num, 0x1000 + 40) == NULL,
          "an entry freed under the table (same list): none, as the walk");
    units[40].allocated = 1; units[40].readable = 0;
    ++gen;
    check(Find(list2, num, gen, now, 0x1000 + 40) == NULL, "an unreadable entry: none (the build skips it)");
    units[40].readable = 1;

    /* 6. duplicate ids: the first in the list's order, as the walk */
    units[60].id = units[50].id;
    ++gen;
    check(Find(list2, num, gen, now, units[50].id) == (uint8_t*)&units[50], "two entries with one id: the first");
    units[60].id = 0x1000 + 60;
    ++gen;

    /* 7. the refresh: a change no key sees (an id changed in place, asked by the new id) waits UT_REFRESH_MS at most */
    check(Find(list2, num, gen, now, 0x1000 + 70) == (uint8_t*)&units[70], "unit 70 found");
    units[70].id = 0x8888;
    uint8_t* stale = Find(list2, num, gen, now + 10, 0x8888);
    check(Find(list2, num, gen, now + UT_REFRESH_MS + 10, 0x8888) == (uint8_t*)&units[70] && T.byAge >= 1,
          "an id changed in place and asked by the new one: found by the refresh at the latest");
    printf("  (before the refresh it answered %s: the case no key sees, bounded by the refresh)\n", stale ? "found" : "none");
    units[70].id = 0x1000 + 70;
    now += UT_REFRESH_MS + 10;
    ++gen;

    /* 8. random runs: spawns and recycles (gen), the game's adds, entries replaced, addresses reused, ids changed; every
     * answer the walk's, but for an id changed in place under an unchanged list asked before the refresh */
    int bad = 0, asks = 0;
    uint32_t oldChecked = 0, walked0 = T.walked;
    for (int step = 0; step < 20000; ++step) {
        uint32_t op = Rand() % 100;
        if (op < 6 && num < 390) { list2[num++] = (uint8_t*)&units[Rand() % 400]; ++gen; }
        else if (op < 12 && num > 1) {
            int32_t at = (int32_t)(Rand() % (uint32_t)num);
            memmove(&list2[at], &list2[at + 1], (size_t)(num - at - 1) * sizeof(list2[0])); --num; ++gen;
        } else if (op < 14 && num < 390) list2[num++] = (uint8_t*)&units[Rand() % 400];            /* (the game's add) */
        else if (op < 16 && num > 0) list2[Rand() % (uint32_t)num] = (uint8_t*)&units[Rand() % 400];
        else if (op < 17) {                       /* (freed under the table, no gen; a new unit there: gen) */
            Fake* f = &units[Rand() % 400];
            if (f->allocated) f->allocated = 0; else { f->allocated = 1; ++gen; }
        }
        else if (op < 18) now += 500;
        uint32_t id = 0x1000 + Rand() % 400;
        ++asks;
        if (Find(list2, num, gen, now, id) != Walk(list2, num, id)) ++bad;
        int32_t k = 0;                            /* (what the old walk checked: up to the match, else all) */
        while (k < num && Walk(list2 + k, 1, id) == NULL) ++k;
        oldChecked += (uint32_t)(k < num ? k + 1 : num);
    }
    printf("  (random: %d asks, %u builds, %u entries checked; the old walk: %u)\n", asks, T.builds, T.walked - walked0,
           oldChecked);
    check(bad == 0, "20000 random steps (a list change in 17% of them): every answer the walk's");
    check((T.walked - walked0) * 2 < oldChecked, "... with under half the entries the old walk checked");

    /* 9. SV_Reset: the table forgotten, built afresh at the next ask */
    uint32_t b1 = T.builds;
    UtForget(&T);
    check(Find(list2, num, gen, now, ((const Fake*)list2[0])->id) == Walk(list2, num, ((const Fake*)list2[0])->id) &&
          T.builds == b1 + 1, "forgotten (SV_Reset): built again at the next ask");

    printf(fails ? "unittab test: %d FAILED\n" : "unittab test: all passed\n", fails);
    return fails ? 1 : 0;
}
