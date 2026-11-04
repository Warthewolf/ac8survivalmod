/* fwkind.h : the other players' weapons by kind, for their weapon stand-ins (runtime 0.32.24; flight.c FnFlush and
 * SV_PPWeapons, sv_coop.lua M.weaponFor). The includer has uobj.h, Readable(p, n), FwKindOfClass(class) (0 an explosive
 * weapon, 1 the laser, 2 a bullet special, 3 an electronic one: ESM / ECM, 4 none of those), CoNow(), Log (wide printf-
 * style: %s %d %u %x %p only, hard rule 43), memset and CO_MAX_PLAYERS. tools/checks/fwkind_test.c runs it on made-up
 * weapon tables.
 * A player on a weapon mod (SPWeaponCustomizer's extra special slots, AC8WeaponSwap) or in a modded plane shown here on
 * a stock fallback (0.73.80) fires weapon numbers their real plane here hasn't, or has as another kind of weapon. Lua
 * shows such a shot as the nearest weapon of the same kind the plane has, from what SV_PPWeapons tells of it:
 *  - each weapon's kind as seen launched here (every replay: the remote fire's missile, FwLaunchDirect's laser or ESM /
 *    ECM; flight.c FwLearn), kept for each player slot and plane (g_fwSeen, FwNoteKind);
 *  - the kind of the weapon class its launcher table entry (0xa0 bytes: [[weapons +0x2e0] +0xb0] +0x28, FwTableOf)
 *    holds, at an offset found once by a scan (FwkScan: the first qword of entry 1, the standard missile, that is a live
 *    class, or an object of one, of the explosive kind; the same field of every other entry empty or a live class, never
 *    entry 1's own). Not verified in the exe (where the entry keeps its class isn't known): observed and checked against
 *    every launch seen (one that disagrees turns them off for the session), and used only when Lua asks ([coop.sync]
 *    standin_table: SV_PPWeapons' second argument, g_fwk.use).
 * Reads only: every pointer is checked (Readable, UObjLive) before it's read. */
#ifndef SV_FWKIND_H
#define SV_FWKIND_H

static const wchar_t* const kFwKindName[] = { L"an explosive weapon", L"a laser", L"a bullet special", L"an electronic weapon (ESM / ECM)",
                                               L"another weapon (none of the four kinds)" };
#define FW_SEEN     16                                      /* (weapon numbers whose kinds are kept: 0-15) */
static struct { uint8_t* plane; uint8_t* cls; uint8_t* tab; int8_t k[FW_SEEN]; } g_fwSeen[CO_MAX_PLAYERS];
/* (found: 0 not yet, 1 at off, -1 given up; inst: the field holds an object of the weapon's class, not the class) */
static struct { int32_t off, tries; int found, inst, use, bad, said; double at; uint32_t agree, disagree; } g_fwk;

/* q is a UStruct (a class): the last entry of its own base chain is itself (FwIsAClass's chain, from its side) */
static int FwIsStruct(uint8_t* q)
{
    if (!q || !Readable(q + 0x30, 0x10)) return 0;
    int32_t d = *(int32_t*)(q + 0x38);
    uint8_t** chain = *(uint8_t***)(q + 0x30);
    return d >= 0 && d < 64 && chain && Readable(chain + d, 8) && chain[d] == q + 0x30;
}

/* the weapon kind of class q (inst 0) or of object q's class (inst 1); -1 when q isn't a live object, or that isn't a class */
static int FwObjKind(uint8_t* q, int inst)
{
    if (!q || ((uintptr_t)q & 7) || !Readable(q, 0x40) || UObjLive(q) != 1) return -1;
    if (inst) {
        q = *(uint8_t**)(q + 0x10);
        if (!q || ((uintptr_t)q & 7) || !Readable(q, 0x40) || UObjLive(q) != 1) return -1;
    }
    return FwIsStruct(q) ? FwKindOfClass(q) : -1;
}

/* the kinds seen launched from player slot's real plane (tab: its table), forgotten for another plane (its address, class
 * or table); NULL for no slot */
static int8_t* FwSeenOf(int slot, uint8_t* plane, uint8_t* tab)
{
    if (slot < 0 || slot >= CO_MAX_PLAYERS || !plane || !Readable(plane + 0x10, 8)) return NULL;
    uint8_t* cls = *(uint8_t**)(plane + 0x10);
    if (g_fwSeen[slot].plane != plane || g_fwSeen[slot].cls != cls || g_fwSeen[slot].tab != tab) {
        g_fwSeen[slot].plane = plane; g_fwSeen[slot].cls = cls; g_fwSeen[slot].tab = tab;
        memset(g_fwSeen[slot].k, -1, sizeof(g_fwSeen[slot].k));
    }
    return g_fwSeen[slot].k;
}

/* where a table entry keeps its weapon's class, looked for in the table tab (num entries); 8 tries 5 s apart at most */
static void FwkScan(uint8_t* tab, int32_t num)
{
    double now = CoNow();
    if (g_fwk.found || g_fwk.tries >= 8 || now < g_fwk.at || !tab || num < 2 || num > 64) return;
    if (!Readable(tab, (size_t)num * 0xa0)) return;
    ++g_fwk.tries; g_fwk.at = now + 5.0;
    uint8_t* e1 = tab + 0xa0;
    for (int32_t off = 0; off < 0xa0; off += 8) {
        for (int inst = 0; inst < 2; ++inst) {
            uint8_t* v1 = *(uint8_t**)(e1 + off);
            if (FwObjKind(v1, inst) != 0) continue;
            int ok = 1;
            for (int32_t i = 0; i < num && ok; ++i) {
                if (i == 1) continue;
                uint8_t* v = *(uint8_t**)(tab + (size_t)i * 0xa0 + off);
                if (v && (v == v1 || FwObjKind(v, inst) < 0)) ok = 0;
            }
            if (!ok) continue;
            g_fwk.off = off; g_fwk.inst = inst; g_fwk.found = 1;
            Log(L"coop2mp: weapon kinds: a weapon table entry's weapon %s at +0x%x (entry 1, the standard missile, an explosive "
                L"weapon; found on try %d, %d entries): checked against every launch seen here, used only with [coop.sync] "
                L"standin_table", inst ? L"object" : L"class", (uint32_t)off, g_fwk.tries, num);
            return;
        }
    }
    if (g_fwk.tries == 1)
        Log(L"coop2mp: weapon kinds: no weapon class found in a weapon table entry (try 1 of 8, %d entries): the other players' "
            L"weapons known by their launches here only for now", num);
    if (g_fwk.tries >= 8) {
        g_fwk.found = -1;
        Log(L"coop2mp: weapon kinds: no weapon class found in a weapon table entry in 8 tries: the other players' weapons known by "
            L"their launches here only");
    }
}

/* the kind entry i of table tab gives, 0-4; -1 not known (no offset found, the table's kinds off, or this table's entry 1
 * not read as an explosive weapon: not trusted) */
static int FwTabKind(uint8_t* tab, int32_t num, int32_t i)
{
    if (g_fwk.found != 1 || g_fwk.bad || !tab || num < 2 || num > 64 || i < 0 || i >= num || !Readable(tab, (size_t)num * 0xa0)) return -1;
    if (FwObjKind(*(uint8_t**)(tab + 0xa0 + g_fwk.off), g_fwk.inst) != 0) return -1;
    uint8_t* v = *(uint8_t**)(tab + (size_t)i * 0xa0 + g_fwk.off);
    return v ? FwObjKind(v, g_fwk.inst) : -1;
}

/* player slot's real plane (its table tab, num entries) launched a weapon of kind k (0-4) as its weapon `weapon`: kept
 * (FwSeenOf), and checked against its table entry's kind: one that disagrees turns the table's kinds off for the session */
static void FwNoteKind(int slot, uint8_t* plane, uint8_t* tab, int32_t num, uint8_t weapon, int k)
{
    if (weapon >= FW_SEEN || k < 0 || k > 4) return;
    int8_t* seen = FwSeenOf(slot, plane, tab);
    if (!seen || seen[weapon] == k) return;
    int was = seen[weapon], t = FwTabKind(tab, num, weapon);
    seen[weapon] = (int8_t)k;
    if (t >= 0 && t == k) ++g_fwk.agree;
    else if (t >= 0) {
        ++g_fwk.disagree;
        if (!g_fwk.bad) {
            g_fwk.bad = 1;
            Log(L"coop2mp: weapon kinds: player %d's weapon %d launched %s, its table entry said %s: the table's kinds OFF for this "
                L"session (the launches' kept)", slot + 1, (int32_t)weapon, kFwKindName[k], kFwKindName[t]);
        }
    }
    if (g_fwk.said < 16) {
        ++g_fwk.said;
        Log(L"coop2mp: weapon kinds: player %d's real plane %p here: its weapon %d is %s (seen launched%s%s%s)", slot + 1, plane,
            (int32_t)weapon, kFwKindName[k], was >= 0 ? L"; it was another before" : L"", t >= 0 ? L"; its table entry said " : L"",
            t >= 0 ? kFwKindName[t] : L"");
    }
}

#endif
