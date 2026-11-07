/* fwkind_test.c (tools/checks/fwkind_test.sh): runtime/fwkind.h, what runtime 0.32.24 knows of the other players' real
 * planes' weapons (their weapon stand-ins: sv_coop.lua M.weaponFor), outside the game, on made-up launcher tables (0xa0-
 * byte entries), classes (a UStruct's base chain: chain[depth] is the class's own +0x30) and a made-up GUObjectArray:
 *   the scan for where an entry keeps its weapon's class: found as a class or as an object of one; never a field whose
 *     entry 1 (the standard missile) isn't an explosive weapon, one every entry shares, one holding something that isn't
 *     a live class (a freed one, a plain object, ammo counts, a wild pointer); at most 8 tries 5 s apart, then given up;
 *   the table's kinds: each entry's; none when this table's entry 1 isn't read as an explosive weapon;
 *   the kinds seen launched: kept per player slot, forgotten for another plane (address, object index or name, class
 *     or table: a new plane made where a freed one was, as coop.c CoRef), checked
 *     against the table's (agreeing counted, one that disagrees turns the table's kinds off for the session);
 *   nothing read that isn't checked first (Readable: only the made-up memory below is readable).
 * Log is counted, its format strings kept (not written). No Windows headers: it runs on the build machine and anywhere
 * with a C compiler. */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#pragma clang diagnostic ignored "-Wunused-function"      /* (uobj.h's other checks) */
#include "../../runtime/uobj.h"

#define CO_MAX_PLAYERS 24
/* readable memory: the blocks made here only (a wild pointer, an ammo count read as one, must never be read) */
static struct { uint8_t* p; size_t n; } g_mem[256];
static int g_memN;
static uint8_t* Block(size_t n)
{
    uint8_t* p = calloc(1, (n + 15) & ~(size_t)15);
    g_mem[g_memN].p = p; g_mem[g_memN].n = n; ++g_memN;
    return p;
}
static int Readable(const void* p, size_t n)
{
    const uint8_t* q = (const uint8_t*)p;
    for (int i = 0; i < g_memN; ++i) if (q >= g_mem[i].p && q + n <= g_mem[i].p + g_mem[i].n) return 1;
    return 0;
}
static double g_now = 100.0;
static double CoNow(void) { return g_now; }
static int g_logs;
static const wchar_t* g_lastLog;
static void Log(const wchar_t* fmt, ...) { ++g_logs; g_lastLog = fmt; }

/* GUObjectArray, made up: one chunk */
static uint8_t* g_chunk;
static uint8_t* g_chunkP[1];
static uint8_t** g_chunkTab = g_chunkP;                  /* (GUObjectArray's chunk table, as the game's: a pointer to it) */
static int32_t g_num = 65536;
static uint32_t g_gcFlag = 1u << 29;
static int32_t g_nextIdx = 1;
static uint8_t* Obj(uint8_t* cls)                        /* a live object of class cls (0x100 bytes) */
{
    uint8_t* o = Block(0x100);
    int32_t idx = g_nextIdx++;
    *(int32_t*)(o + 0xC) = idx;
    *(uint8_t**)(o + 0x10) = cls;
    uint8_t* item = g_chunk + (size_t)idx * 0x18;
    *(uint8_t**)item = o;
    return o;
}
static void Free(uint8_t* o) { *(uint8_t**)(g_chunk + (size_t)*(int32_t*)(o + 0xC) * 0x18) = NULL; }

/* classes, made up: a UStruct whose base chain (+0x30, depth +0x38) ends with itself; its kind by the table below (the
 * test's FwKindOfClass: the runtime's asks the game's StaticClass of each kind) */
static uint8_t* g_classClass;                             /* (UClass's own class: the classes' +0x10) */
static uint8_t* Class(void)
{
    uint8_t* c = Obj(g_classClass);
    uint8_t** chain = (uint8_t**)Block(8 * 4);
    chain[2] = c + 0x30;
    *(uint8_t***)(c + 0x30) = chain;
    *(int32_t*)(c + 0x38) = 2;
    return c;
}
static uint8_t* g_kindOf[64];
static int g_kindK[64], g_kindN;
static uint8_t* KindClass(int k) { uint8_t* c = Class(); g_kindOf[g_kindN] = c; g_kindK[g_kindN++] = k; return c; }
static int FwKindOfClass(uint8_t* pc)
{
    for (int i = 0; i < g_kindN; ++i) if (g_kindOf[i] == pc) return g_kindK[i];
    return 4;
}
#include "../../runtime/fwkind.h"

static int fails;
static void check(int ok, const char* what) { printf("  %s %s\n", ok ? "ok  " : "FAIL", what); if (!ok) ++fails; }
static int logged(const wchar_t* part) { return g_lastLog && wcsstr(g_lastLog, part) != NULL; }

/* a launcher table of n entries (0xa0 bytes each), the ammo counts and slot arrays as the game's (not objects) */
static uint8_t* Table(int n)
{
    uint8_t* t = Block((size_t)n * 0xa0);
    for (int i = 0; i < n; ++i) {
        uint8_t* e = t + (size_t)i * 0xa0;
        *(uint64_t*)(e + 0x08) = 0x0000003700000034ull;   /* (max / current ammo: no pointer) */
        *(uint8_t**)(e + 0x58) = Block(0x80);             /* (the spawn slots: memory, not an object) */
        *(int32_t*)(e + 0x60) = 1;
        *(uint8_t**)(e + 0x78) = Block(4);
    }
    return t;
}
static void Put(uint8_t* t, int i, int off, void* v) { *(void**)(t + (size_t)i * 0xa0 + off) = v; }
static void ScanFresh(void) { memset(&g_fwk, 0, sizeof(g_fwk)); }

int main(void)
{
    g_chunk = calloc(65536, 0x18);
    g_chunkP[0] = g_chunk;
    g_uoNum = &g_num; g_uoGcFlag = &g_gcFlag; g_uoChunks = (uint8_t* const* volatile*)&g_chunkTab;
    g_classClass = Obj(NULL);
    *(uint8_t**)(g_classClass + 0x10) = g_classClass;
    uint8_t* gun = KindClass(4), *msl = KindClass(0), *saam = KindClass(0), *laser = KindClass(1), *esm = KindClass(3),
           *bullet = KindClass(2);
    uint8_t* plain = Class();                             /* (a class of none of the four kinds) */
    uint8_t* sysObj = Obj(plain);                         /* (a plain object: the weapon system, say) */
    int gotN;

    printf("the scan: where a table entry keeps its weapon's class\n");
    uint8_t* t = Table(4);
    uint8_t* shared = Obj(msl);                           /* (one object every entry holds, the explosive kind's: not theirs) */
    Put(t, 0, 0x00, shared); Put(t, 1, 0x00, shared); Put(t, 2, 0x00, shared); Put(t, 3, 0x00, shared);
    Put(t, 0, 0x10, sysObj); Put(t, 1, 0x10, sysObj); Put(t, 2, 0x10, sysObj); Put(t, 3, 0x10, sysObj);   /* (not explosive) */
    Put(t, 0, 0x18, gun); Put(t, 1, 0x18, msl); Put(t, 2, 0x18, saam); Put(t, 3, 0x18, laser);
    FwkScan(t, 4);
    check(g_fwk.found == 1 && g_fwk.off == 0x18 && g_fwk.inst == 0 && logged(L"weapon %s at +0x%x"),
          "the classes at +0x18 found (not the object every entry shares at +0x00, not the ammo counts at +0x08, not a plain "
          "object at +0x10), logged");
    check(FwTabKind(t, 4, 0) == 4 && FwTabKind(t, 4, 1) == 0 && FwTabKind(t, 4, 2) == 0 && FwTabKind(t, 4, 3) == 1,
          "the table's kinds: the gun another kind, the standard missile and the special explosive, the laser a laser");
    check(FwTabKind(t, 4, 4) == -1 && FwTabKind(t, 4, -1) == -1, "a number past the table: not known");
    uint8_t* t2 = Table(3);
    Put(t2, 0, 0x18, gun); Put(t2, 1, 0x18, laser); Put(t2, 2, 0x18, msl);
    check(FwTabKind(t2, 3, 2) == -1 && FwTabKind(t2, 3, 1) == -1, "a table whose entry 1 isn't an explosive weapon: not trusted (none)");
    uint8_t* t3 = Table(3);
    Put(t3, 0, 0x18, gun); Put(t3, 1, 0x18, msl);         /* (entry 2's class empty) */
    check(FwTabKind(t3, 3, 2) == -1 && FwTabKind(t3, 3, 1) == 0, "an empty field: not known");

    printf("as an object of the class; fields that aren't the class\n");
    ScanFresh();
    uint8_t* t4 = Table(3);
    Put(t4, 0, 0x10, msl); Put(t4, 1, 0x10, msl); Put(t4, 2, 0x10, msl);       /* (every entry the same class: no) */
    uint8_t* gone = Class();
    Put(t4, 0, 0x18, gun); Put(t4, 1, 0x18, msl); Put(t4, 2, 0x18, gone);      /* (a freed class in entry 2: no) */
    Free(gone);
    Put(t4, 0, 0x20, gun); Put(t4, 1, 0x20, msl); Put(t4, 2, 0x20, (void*)(uintptr_t)0x0000003700000038ull);   /* (a wild one) */
    Put(t4, 0, 0x28, gun); Put(t4, 1, 0x28, msl); Put(t4, 2, 0x28, sysObj);    /* (a plain object, not a class: no) */
    Put(t4, 0, 0x30, Obj(gun)); Put(t4, 1, 0x30, Obj(msl)); Put(t4, 2, 0x30, Obj(esm));
    FwkScan(t4, 3);
    check(g_fwk.found == 1 && g_fwk.off == 0x30 && g_fwk.inst == 1,
          "objects of the classes at +0x30 found (as objects; not a shared class, a freed one, a wild pointer, a plain object)");
    check(FwTabKind(t4, 3, 2) == 3 && FwTabKind(t4, 3, 0) == 4, "the ESM's object read as an electronic weapon, the gun's another kind");

    printf("nothing found: 8 tries 5 s apart, then given up\n");
    ScanFresh();
    uint8_t* t5 = Table(3);
    Put(t5, 1, 0x18, laser);
    int logs0 = g_logs;
    FwkScan(t5, 3);
    check(g_fwk.found == 0 && g_fwk.tries == 1 && g_logs == logs0 + 1 && logged(L"try 1 of 8"), "try 1: not found, logged");
    FwkScan(t5, 3);
    check(g_fwk.tries == 1, "again at once: not tried (5 s apart)");
    for (int k = 0; k < 7; ++k) { g_now += 5.1; FwkScan(t5, 3); }
    check(g_fwk.found == -1 && g_fwk.tries == 8 && logged(L"in 8 tries"), "8 tries: given up, logged");
    g_now += 5.1;
    FwkScan(t5, 3);
    check(g_fwk.tries == 8 && FwTabKind(t, 4, 1) == -1, "never tried again; no table kinds");
    ScanFresh();
    FwkScan(t5, 1);
    FwkScan(NULL, 4);
    check(g_fwk.tries == 0, "a table of one entry, or none: not scanned");

    printf("kinds seen launched, against the table's\n");
    ScanFresh();
    FwkScan(t, 4);                                        /* (found: +0x18) */
    uint8_t* planeA = Obj(plain), *planeB = Obj(plain);
    FwNoteKind(4, planeA, t, 4, 2, 0);
    int8_t* seen = FwSeenOf(4, planeA, t);
    check(seen && seen[2] == 0 && seen[1] == -1 && g_fwk.agree == 1 && g_fwk.disagree == 0, "weapon 2 seen an explosive weapon, as its table says: agreed");
    FwNoteKind(4, planeA, t, 4, 2, 0);
    check(g_fwk.agree == 1, "the same again: counted once");
    FwNoteKind(4, planeA, t, 4, 20, 1);
    FwNoteKind(30, planeA, t, 4, 1, 0);
    FwNoteKind(4, planeA, t, 4, 1, 7);
    seen = FwSeenOf(4, planeA, t);
    check(seen[1] == -1 && g_fwk.agree == 1, "a weapon past 15, a slot past 23, a kind past 4: left out");
    check(FwSeenOf(4, planeB, t)[2] == -1, "another plane in the slot: what was seen forgotten");
    FwNoteKind(4, planeB, t, 4, 2, 0);
    *(uint8_t**)(planeB + 0x10) = gun;                   /* (another class at that address: another plane) */
    check(FwSeenOf(4, planeB, t)[2] == -1, "another class at the same address: forgotten");
    FwNoteKind(4, planeB, t, 4, 2, 0);
    check(FwSeenOf(4, planeB, t)[2] == 0 && FwSeenOf(4, planeB, t2)[2] == -1, "another table: forgotten");
    FwNoteKind(4, planeB, t, 4, 2, 0);
    check(FwSeenOf(4, planeB, t)[2] == 0, "seen again on its own table: kept");
    *(int32_t*)(planeB + 0xC) += 1000;                   /* (freed, another plane made at that address: same class, same table) */
    check(FwSeenOf(4, planeB, t)[2] == -1, "another object at the same address, class and table: forgotten");
    *(int32_t*)(planeB + 0xC) -= 1000;
    FwNoteKind(4, planeB, t, 4, 2, 0);
    check(FwSeenOf(4, planeB, t)[2] == 0, "its own index again, seen again: kept");
    *(uint64_t*)(planeB + 0x18) = 77;
    check(FwSeenOf(4, planeB, t)[2] == -1, "another name at the same address, index, class and table: forgotten");
    *(uint64_t*)(planeB + 0x18) = 0;
    check(FwSeenOf(-1, planeB, t) == NULL && FwSeenOf(24, planeB, t) == NULL, "no slot: nothing kept");
    FwNoteKind(5, planeA, t, 4, 3, 0);                   /* (its table says a laser) */
    check(g_fwk.bad == 1 && g_fwk.disagree == 1 && FwTabKind(t, 4, 1) == -1, "a launch the table got wrong: its kinds off for the session");
    check(FwSeenOf(5, planeA, t)[3] == 0, "the launch's kind kept");
    g_now += 100;
    FwkScan(t, 4);
    check(FwTabKind(t, 4, 3) == -1, "never trusted again");

    printf("weapons of every kind\n");
    ScanFresh();
    uint8_t* t6 = Table(5);
    Put(t6, 0, 0x40, gun); Put(t6, 1, 0x40, msl); Put(t6, 2, 0x40, bullet); Put(t6, 3, 0x40, esm); Put(t6, 4, 0x40, laser);
    FwkScan(t6, 5);
    gotN = 0;
    for (int i = 0; i < 5; ++i) gotN = gotN * 10 + FwTabKind(t6, 5, i);
    check(g_fwk.off == 0x40 && gotN == 40231, "gun 4, missile 0, bullet special 2, ESM 3, laser 1");

    if (fails) printf("fwkind test: %d FAILED\n", fails);
    else printf("fwkind test: all passed\n");
    return fails ? 1 : 0;
}
