/* logdedup_test.c (tools/checks/logdedup_test.sh): runtime/logdedup.h, the UE4SS.log copy's line filter (Saint Alessia's
 * 50-round co-op run, lag-8: her UE4SS.log was 415 MB, 98.3% one line of another mod's, and the bundle copied it whole),
 * on a made-up log: bursts of one line (each with its own time stamp, as UE4SS writes them) between other lines, fed in
 * chunks that end anywhere. The copy must be small, and say everything: expanding each "the line above N more times"
 * gives back every line's text in order; the counts and the most repeated line right; the 64 MB cap; long lines; a run
 * written when the log goes quiet. */
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

int main(void)
{
    static LdState s;
    /* 1. her flood: bursts of one line (200 at a time, ~every half second), another line now and then */
    Buf in = { 0 }, out = { 0 };
    const char* flood = "[Lua] [Some Other Mod] Event work complete; polling stopped";
    size_t floodN = 0, total = 0;
    char line[256];
    for (int sec = 0; sec < 600; ++sec) {
        for (int half = 0; half < 2; ++half) {
            for (int k = 0; k < 200; ++k) {
                snprintf(line, sizeof(line), "[19:%02d:%02d.%07d] %s\r\n", sec / 60 % 60, sec % 60, half * 5000000 + k * 20, flood);
                BufAdd(&in, line); floodN++; total++;
            }
        }
        if (sec % 3 == 0) {
            snprintf(line, sizeof(line), "[19:%02d:%02d.9000000] [Lua] [AC8SurvivalMode] tick %d\r\n", sec / 60 % 60, sec % 60, sec);
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
    check(Has(&out, "---- the line above 399 more times (from [19:00:00.0000020]) ----"),
          "a run's line: how many more and from when");
    check(out.n >= 2 && out.p[out.n - 1] == '\n', "the copy ends on a whole line");

    /* 2. a run left at the end is written when the log goes quiet (LdIdle), not lost */
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
    char l5[128];
    uint64_t fed = 0, n5 = 0;
    while (fed < (70ull << 20)) {
        int k = snprintf(l5, sizeof(l5), "[21:00:00.0000000] line %llu of a log that never repeats itself, padding padding\r\n",
                         (unsigned long long)n5++);
        LdFeed(&s, l5, (size_t)k, BufPut, &out5);
        fed += (uint64_t)k;
    }
    size_t marks = 0;
    const char* mk = "the copy of UE4SS.log stops here";
    for (size_t i = 0; i + strlen(mk) <= out5.n; ++i) if (!memcmp(out5.p + i, mk, strlen(mk))) marks++;
    check(s.outBytes <= LD_CAP + 256 && s.dropped > 0 && marks == 1 && s.lines == n5,
          "70 MB of lines: the copy stops at 64 MB, said once, the rest counted (dropped)");

    printf(fails ? "logdedup test: %d FAILED\n" : "logdedup test: all passed\n", fails);
    return fails ? 1 : 0;
}
