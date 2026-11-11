/* unittab.h : the spawner's id -> unit table (Saint Alessia's 50-round co-op run, lag-1). survival_rt_game.c's
 * RegisteredUnit finds a flight's unit actor on the phase's unit list through it (SV_UnitAlive, Spawn, Recycle);
 * tools/checks/unittab_test.c runs it on a made-up list, against the old walk.
 *
 * The old lookup walked the whole list on every ask, with two VirtualQuery memory checks an entry (one on the entry's
 * vtable, inside the game's 551 MB image): 0.53 ms a call at round 2, ~6 ms from round 22, 9.4-9.9 ms at rounds 49-50
 * (the list ~100 long; ~0.1 ms an entry), 28-50% of the host's Lua tick. The table holds each entry's id and place,
 * built by one walk and used until the list changes: its data, its count, its entries (a hash of their pointers, in
 * order: an entry replaced in place changes it), the spawner's own changes to it (gen: Spawn, Recycle, the deferred
 * destroys, SV_Reset) or UT_REFRESH_MS on. A hit is checked again before it's answered (still a unit, still that id: an
 * address the game reused, hard rule 59); one that fails rebuilds the table and is looked up again. A miss on a current
 * table is the walk's answer (the same entries, each with the id it had: nothing but the game's own unregister and a new
 * unit at the same address and place, between two asks, could change it, and the refresh bounds even that).
 * Pure C, no Windows: the caller's two checks come in as functions. */
#ifndef SV_UNITTAB_H
#define SV_UNITTAB_H

#define UT_MAX        4096          /* (PhaseUnits refuses a longer list) */
#define UT_REFRESH_MS 2000

/* full 1: the build's check of an entry (its memory readable, a UObject still allocated); 0: a hit's quick one */
typedef int      (*UtOkFn)(void* ctx, uint8_t* u, int full);
typedef uint32_t (*UtIdFn)(void* ctx, uint8_t* u);

typedef struct {
    int             built;
    uint8_t* const* data;           /* the list it was built from */
    int32_t         num;
    uint64_t        fp;
    uint32_t        gen;
    uint64_t        at;             /* ms */
    int32_t         n;
    uint32_t        id[UT_MAX];
    int32_t         pos[UT_MAX];
    /* counts (the runtime's minute line) */
    uint32_t        builds, byGen, byList, byAge, byMoved, hits, misses, moved, skipped, walked;
} UnitTab;

static uint64_t UtPrint(uint8_t* const* data, int32_t num)
{
    uint64_t h = 1469598103934665603ull ^ (uint64_t)(uint32_t)num;
    for (int32_t i = 0; i < num; ++i) { h ^= (uint64_t)(uintptr_t)data[i]; h *= 1099511628211ull; }
    return h;
}

static void UtBuild(UnitTab* t, uint8_t* const* data, int32_t num, uint64_t fp, uint32_t gen, uint64_t now,
                    UtOkFn ok, UtIdFn idOf, void* ctx)
{
    t->n = 0;
    for (int32_t i = 0; i < num && t->n < UT_MAX; ++i) {
        uint8_t* u = data[i];
        ++t->walked;
        if (!u || !ok(ctx, u, 1)) { ++t->skipped; continue; }
        t->id[t->n] = idOf(ctx, u);
        t->pos[t->n] = i;
        ++t->n;
    }
    t->built = 1; t->data = data; t->num = num; t->fp = fp; t->gen = gen; t->at = now;
    ++t->builds;
}

/* the first entry with that id, -1 none (the walk's order: the list's) */
static int32_t UtIndex(const UnitTab* t, uint32_t id)
{
    for (int32_t k = 0; k < t->n; ++k) if (t->id[k] == id) return k;
    return -1;
}

/* the unit of `id` on the list (data, num), or NULL: what a walk of the list would answer now */
static uint8_t* UtFind(UnitTab* t, uint8_t* const* data, int32_t num, uint32_t gen, uint64_t now, uint32_t id,
                       UtOkFn ok, UtIdFn idOf, void* ctx)
{
    if (!data || num <= 0) { ++t->misses; return NULL; }
    uint64_t fp = UtPrint(data, num);
    int fresh = 0;
    if (!t->built || t->data != data || t->num != num || t->fp != fp || t->gen != gen || now < t->at ||
        now - t->at >= UT_REFRESH_MS) {
        if (t->built) {
            if (t->gen != gen) ++t->byGen;
            else if (t->data != data || t->num != num || t->fp != fp) ++t->byList;
            else ++t->byAge;
        }
        UtBuild(t, data, num, fp, gen, now, ok, idOf, ctx);
        fresh = 1;
    }
    int32_t k = UtIndex(t, id);
    if (k < 0) { ++t->misses; return NULL; }
    uint8_t* u = data[t->pos[k]];
    if (fresh || (ok(ctx, u, 0) && idOf(ctx, u) == id)) { ++t->hits; return u; }
    ++t->moved;                                    /* (changed in place under the same key: looked up afresh) */
    ++t->byMoved;
    UtBuild(t, data, num, fp, gen, now, ok, idOf, ctx);
    k = UtIndex(t, id);
    if (k < 0) { ++t->misses; return NULL; }
    ++t->hits;
    return data[t->pos[k]];
}

/* forget the table (a new level, a new spawner) */
static void UtForget(UnitTab* t) { t->built = 0; t->n = 0; t->data = NULL; t->num = 0; }

#endif
