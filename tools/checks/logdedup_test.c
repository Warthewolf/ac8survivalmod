/* logdedup_test.c (tools/checks/logdedup_test.sh): runtime/logdedup.h, the UE4SS.log copy's line filter (Saint Alessia's
 * 50-round co-op run, lag-8: her UE4SS.log was 415 MB, 98.3% one line of another mod's, and the bundle copied it whole),
 * on a made-up log: bursts of one line (each with its own time stamp, as UE4SS 3.0.1 writes them:
 * "[2026-11-10 19:01:46.9542123] ", LF only) between other lines, fed in chunks that end anywhere. The copy must be small,
 * and say everything: expanding each "the line above N more times" gives back every line's text in order; the counts and
 * the most repeated line right; the 64 MB cap, and nothing written past it but its own line and the run going on as it
 * was reached; long lines; a run written when the log goes quiet; the undated "[HH:MM:SS.fffffff] " stamp too.
 * ((2026-11-11, review) the first version of this test made its flood with undated stamps UE4SS never writes, and passed
 *  while the filter knew no real line: her real UE4SS.log collapsed 2 lines of 4.48 million.) */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "../../runtime/logdedup.h"

static int fails;
static void check(int ok, const char* what) { printf("  %s %s\n", ok ? "ok  " : "FAIL", what); if (!ok) ++fails; }

typedef struct { char* p; size_t n, cap; } Buf;
static void BufPut(void* ctx, const char* p, size_t n)
{
    Buf* b = (Buf*)ctx;
    if (b->n + n > b->cap) {
        b->cap = (b->n + n) * 2 + 1024;
        b->p = (char*)realloc(b->p, b->cap);
    }
    memcpy(b->p + b->n, p, n);
    b->n += n;
}
static void BufAdd(Buf* b, const char* s) { BufPut(b, s, strlen(s)); }
static int Has(const Buf* b, const char* t)             /* (the copy holds t: its bytes, no NUL needed) */
{
    size_t n = strlen(t);
    for (size_t i = 0; b->p && i + n <= b->n; ++i) if (!memcmp(b->p + i, t, n)) return 1;
    return 0;
}

static uint32_t rnd = 2463534242u;
static uint32_t Rand(void) { rnd ^= rnd << 13; rnd ^= rnd >> 17; rnd ^= rnd << 5; return rnd; }

/* feed `in` in chunks of 1..max bytes */
static void FeedChunks(LdState* s, const Buf* in, size_t max, Buf* out)
{
    for (size_t i = 0; i < in->n;) {
        size_t k = 1 + Rand() % max;
        if (k > in->n - i) k = in->n - i;
        LdFeed(s, in->p + i, k, BufPut, out);
        i += k;
    }
}

/* the bodies of a text's lines (after a "[...] " stamp), "the line above N more times" expanded; their count */
static size_t Bodies(const Buf* b, char*** out)
{
    size_t cap = 1024, n = 0;
    char** v = (char**)malloc(cap * sizeof(char*));
    for (size_t i = 0; i < b->n;) {
        size_t e = i;
        while (e < b->n && b->p[e] != '\n') ++e;
        size_t len = e - i;
        if (len && b->p[i + len - 1] == '\r') --len;
        size_t st = 0, bo = LdBody(b->p + i, len, &st);
        const char* body = b->p + i + bo;
        size_t bl = len - bo;
        const char* tag = "---- the line above ";
        const char* at = NULL;
        for (size_t j = 0; j + strlen(tag) <= bl && !at; ++j) if (!memcmp(body + j, tag, strlen(tag))) at = body + j;
        if (at == body && n) {
            unsigned long long rep = strtoull(at + strlen(tag), NULL, 10);
            for (unsigned long long r = 0; r < rep; ++r) {
                if (n == cap) { cap *= 2; v = (char**)realloc(v, cap * sizeof(char*)); }
                v[n] = v[n - 1]; n++;
            }
        } else if (len) {
            if (n == cap) { cap *= 2; v = (char**)realloc(v, cap * sizeof(char*)); }
            char* c = (char*)malloc(bl + 1);
            memcpy(c, body, bl); c[bl] = 0;
            v[n++] = c;
        }
        i = e + 1;
    }
    *out = v;
    return n;
}

/* the copy's lines that are the log's (not a run's "the line above N more times" or the cap's line); *meta those */
static size_t CopyLines(const Buf* b, size_t* meta)
{
    size_t n = 0, m = 0;
    const char* tag = "---- the line above ";
    const char* cap = "---- the copy of UE4SS.log stops here";
    for (size_t i = 0; i < b->n;) {
        size_t e = i;
        while (e < b->n && b->p[e] != '\n') ++e;
        size_t st = 0, bo = LdBody(b->p + i, e - i, &st);
        if ((e - i - bo >= strlen(tag) && !memcmp(b->p + i + bo, tag, strlen(tag))) ||
            (e - i >= strlen(cap) && !memcmp(b->p + i, cap, strlen(cap)))) m++;
        else n++;
        i = e + 1;
    }
    *meta = m;
    return n;
}
static size_t Count(const char* p, size_t n, const char* t)
{
    size_t k = 0, tn = strlen(t);
    for (size_t i = 0; i + tn <= n; ++i) if (!memcmp(p + i, t, tn)) k++;
    return k;
}

int main(void)
{
    static LdState s;
    /* 0. the stamp: UE4SS 3.0.1's dated one (what every line of her UE4SS.log starts with), the undated one, and none */
    {
        static const struct { const char* l; size_t stamp, body; } c[] = {
            { "[2026-11-10 19:01:46.9542123] [Lua] [AC8SurvivalMode] tick", 29, 30 },
            { "[2026-11-10 19:00:14.9631007] Console created", 29, 30 },
            { "[2026-11-10 19:01:46.9542123]", 29, 29 },
            { "[19:01:46.9542123] x", 18, 19 },
            { "[1:2:3] x", 7, 8 },
            { "[Lua] [Some Other Mod] x", 0, 0 },
            { "[ ] a list's box", 0, 0 },
            { "[-] a list's box", 0, 0 },
            { "[] x", 0, 0 },
            { "[2026-11-10 19:01:46.9542123 no end", 0, 0 },
            { "no stamp", 0, 0 },
        };
        int ok = 1;
        for (size_t i = 0; i < sizeof(c) / sizeof(c[0]); ++i) {
            size_t st = 99, bo = LdBody(c[i].l, strlen(c[i].l), &st);
            if (st != c[i].stamp || bo != c[i].body) {
                printf("    \"%s\": stamp %zu, body at %zu (wanted %zu, %zu)\n", c[i].l, st, bo, c[i].stamp, c[i].body);
                ok = 0;
            }
        }
        check(ok, "the stamp: UE4SS 3.0.1's \"[2026-11-10 19:01:46.9542123] \" and \"[19:01:46.9542123] \" taken off, \"[Lua]\", \"[ ]\" not");
    }

    /* 1. her flood: bursts of one line (200 at a time, ~every half second), another line now and then; UE4SS 3.0.1's
     *    dated stamps and LF line ends, as her UE4SS.log */
    Buf in = { 0 }, out = { 0 };
    const char* flood = "[Lua] [Some Other Mod] Event work complete; polling stopped";
    size_t floodN = 0, total = 0;
    char line[256];
    for (int sec = 0; sec < 600; ++sec) {
        for (int half = 0; half < 2; ++half) {
            for (int k = 0; k < 200; ++k) {
                snprintf(line, sizeof(line), "[2026-11-10 19:%02d:%02d.%07d] %s\n", sec / 60 % 60, sec % 60, half * 5000000 + k * 20, flood);
                BufAdd(&in, line); floodN++; total++;
            }
        }
        if (sec % 3 == 0) {
            snprintf(line, sizeof(line), "[2026-11-10 19:%02d:%02d.9000000] [Lua] [AC8SurvivalMode] tick %d\n", sec / 60 % 60, sec % 60, sec);
            BufAdd(&in, line); total++;
        }
    }
    LdInit(&s);
    FeedChunks(&s, &in, 5000, &out);
    LdIdle(&s, BufPut, &out);
    printf("  (%zu lines, %zu bytes in; %zu bytes out)\n", total, in.n, out.n);
    check(out.n * 50 < in.n, "the flood: the copy under 2% of UE4SS.log's size");
    check(s.lines == total && s.collapsed == floodN - 201 /* (each of its 201 runs: its first written) */ && s.inBytes == in.n,
          "the counts: every line read, the repeats counted as collapsed");
    char** a; char** b;
    size_t na = Bodies(&in, &a), nb = Bodies(&out, &b);
    int same = na == nb;
    for (size_t i = 0; same && i < na; ++i) same = !strcmp(a[i], b[i]);
    check(same, "expanding each 'the line above N more times' gives back every line, in order");
    check(s.topN == floodN - 201 && !strcmp(s.topText, flood), "its most repeated line: the flood's, with its count");
    check(Has(&out, "[2026-11-10 19:00:00.5003980] ---- the line above 399 more times (from [2026-11-10 19:00:00.0000020]) ----"),
          "a run's line: how many more, from when and until when (UE4SS's dated stamps)");
    check(out.n >= 2 && out.p[out.n - 1] == '\n', "the copy ends on a whole line");

    /* 2. a run left at the end is written when the log goes quiet (LdIdle), not lost (the undated stamp, CRLF) */
    Buf in2 = { 0 }, out2 = { 0 };
    LdInit(&s);
    for (int i = 0; i < 5; ++i) BufAdd(&in2, "[20:00:00.0000000] the same\r\n");
    LdFeed(&s, in2.p, in2.n, BufPut, &out2);
    check(!Has(&out2, "more times"), "a run still going: not written yet");
    LdIdle(&s, BufPut, &out2);
    check(Has(&out2, "the line above 4 more times"), "the log quiet: the run's line written (4 more)");

    /* 3. lines without a stamp, and different stamps, same text: one run; different text: no run */
    Buf in3 = { 0 }, out3 = { 0 };
    LdInit(&s);
    BufAdd(&in3, "no stamp here\nno stamp here\n[1:2:3] x\n[1:2:4] x\n[1:2:5] y\n");
    LdFeed(&s, in3.p, in3.n, BufPut, &out3);
    LdIdle(&s, BufPut, &out3);
    check(s.collapsed == 2 && s.lines == 5, "no stamp: the whole line compared; stamps apart, the text the same: a run");

    /* 4. long lines: compared past what's kept (their hash), cut in the copy */
    Buf in4 = { 0 }, out4 = { 0 };
    LdInit(&s);
    char* big = (char*)malloc(LD_LINE * 2 + 2);
    memset(big, 'a', LD_LINE * 2); big[LD_LINE * 2] = '\n'; big[LD_LINE * 2 + 1] = 0;
    BufAdd(&in4, big); BufAdd(&in4, big);
    big[LD_LINE + 10] = 'b';
    BufAdd(&in4, big);
    LdFeed(&s, in4.p, in4.n, BufPut, &out4);
    LdIdle(&s, BufPut, &out4);
    check(s.collapsed == 1, "a long line twice: collapsed; one differing past what's kept: not");
    check(out4.n < in4.n, "... cut in the copy");

    /* 5. the cap: 70 MB of different lines, the copy stops at 64 MB, says so once, counts the rest */
    Buf out5 = { 0 };
    LdInit(&s);
    char l5[160];
    uint64_t fed = 0, n5 = 0;
    while (fed < (70ull << 20)) {
        int k = snprintf(l5, sizeof(l5), "[2026-11-10 21:00:00.0000000] line %llu of a log that never repeats itself, padding padding\n",
                         (unsigned long long)n5++);
        LdFeed(&s, l5, (size_t)k, BufPut, &out5);
        fed += (uint64_t)k;
    }
    const char* mk = "the copy of UE4SS.log stops here";
    size_t marks = Count(out5.p, out5.n, mk);
    check(s.outBytes <= LD_CAP + 256 && s.dropped > 0 && marks == 1 && s.lines == n5,
          "70 MB of lines: the copy stops at 64 MB, said once, the rest counted (dropped)");

    /* 6. past the cap, nothing more is written: bursts of a line 4 times (each its first, then 3 repeats: a run each) and
     *    the log going quiet between them, then one line again and again with the log quiet after each (the review's
     *    case: the first version wrote each run's line, ~150 bytes a burst, without end) */
    {
        uint64_t out0 = s.outBytes, coll0 = s.collapsed, drop0 = s.dropped, lines0 = s.lines;
        size_t n0 = out5.n;
        const unsigned groups = 20000, again = 1000;
        for (unsigned g = 0; g < groups; ++g) {
            for (int r = 0; r < 4; ++r) {
                int k = snprintf(l5, sizeof(l5), "[2026-11-10 22:%02u:%02u.%07d] [Lua] [Some Other Mod] burst %u\n",
                                 g / 60 % 60, g % 60, r * 10, g);
                LdFeed(&s, l5, (size_t)k, BufPut, &out5);
            }
            if (g % 10 == 9) LdIdle(&s, BufPut, &out5);
        }
        const char* x = "[Lua] [Some Other Mod] Event work complete; polling stopped";
        for (unsigned i = 0; i < again; ++i) {
            int k = snprintf(l5, sizeof(l5), "[2026-11-10 23:00:%02u.%07u] %s\n", i / 10 % 60, i, x);
            LdFeed(&s, l5, (size_t)k, BufPut, &out5);
            LdIdle(&s, BufPut, &out5);
        }
        printf("  (past the cap: %llu bytes more written for %llu lines)\n", (unsigned long long)(s.outBytes - out0),
               (unsigned long long)(s.lines - lines0));
        check(s.outBytes == out0 && out5.n == n0 && s.outBytes <= LD_CAP + 256,
              "past the cap: nothing more written (no run's line), whatever repeats and however often the log goes quiet");
        check(s.collapsed == coll0 && s.dropped - drop0 == (uint64_t)groups * 4 + again && s.lines - lines0 == (uint64_t)groups * 4 + again,
              "... every line past it counted as dropped (its repeats too), none as collapsed");
        check(!strcmp(s.topText, x) && s.topN >= again - 1, "... and its repeats still counted for the most repeated line");
        size_t meta = 0, kept = CopyLines(&out5, &meta);
        check(kept + s.collapsed + s.dropped == s.lines && meta == 1,
              "every line read: in the copy, collapsed into a run's line, or dropped past the cap");
    }
    free(out5.p);

    /* 7. a run going on as the cap is reached: its line written once (it's about a line the copy holds), then nothing */
    {
        Buf out7 = { 0 };
        LdInit(&s);
        uint64_t n7 = 0;
        for (;;) {
            int k = snprintf(l5, sizeof(l5), "[2026-11-10 21:00:00.0000000] line %llu of a log that never repeats itself, padding padding\n",
                             (unsigned long long)n7);
            if (s.outBytes + 2 * (uint64_t)k >= LD_CAP) break;
            LdFeed(&s, l5, (size_t)k, BufPut, &out7);
            n7++;
        }
        static const char xr[] = "[2026-11-10 21:30:00.0000000] the line going on at the cap\n";
        for (int i = 0; i < 8; ++i) LdFeed(&s, xr, sizeof(xr) - 1, BufPut, &out7);         /* (below the cap: written, a run of 7) */
        uint64_t below = s.outBytes;
        for (int i = 0; i < 5000; ++i) {
            int k = snprintf(l5, sizeof(l5), "[2026-11-10 21:31:00.0000000] after the cap %d\n", i);
            LdFeed(&s, l5, (size_t)k, BufPut, &out7);
            if (i % 2) for (int r = 0; r < 3; ++r) LdFeed(&s, l5, (size_t)k, BufPut, &out7);
            LdIdle(&s, BufPut, &out7);
        }
        const char* m7 = "---- the line above 7 more times";
        size_t at = 0;
        for (size_t i = 0; i + strlen(m7) <= out7.n; ++i) if (!memcmp(out7.p + i, m7, strlen(m7))) { at = i; break; }
        size_t capAt = 0;
        for (size_t i = 0; i + strlen(mk) <= out7.n; ++i) if (!memcmp(out7.p + i, mk, strlen(mk))) { capAt = i; break; }
        check(below < LD_CAP && Count(out7.p, out7.n, m7) == 1 && at && capAt > at &&
              Count(out7.p, out7.n, "more times") == 1 && Count(out7.p, out7.n, mk) == 1,
              "a run going on at the cap: its line written once, before the cap's line; no run's line after it");
        check(s.outBytes <= LD_CAP + LD_LINE + 512, "... and the copy within 64 MB, the last line and those two lines");
        size_t meta = 0, kept = CopyLines(&out7, &meta);
        check(kept + s.collapsed + s.dropped == s.lines && meta == 2 && s.collapsed == 7,
              "... every line read: in the copy, collapsed (the 7), or dropped past the cap");
        free(out7.p);
    }

    printf(fails ? "logdedup test: %d FAILED\n" : "logdedup test: all passed\n", fails);
    return fails ? 1 : 0;
}
