/* logdedup.h : the UE4SS.log copy's line filter (Saint Alessia's 50-round co-op run, lag-8). runtime/logbundle.c's copy
 * thread feeds it what UE4SS.log gained; tools/checks/logdedup_test.c runs it on a made-up flood.
 *
 * Her UE4SS.log was 415 MB, 98.3% of it one line of another mod's ("[Lua] [<a mod>] Event work complete; polling
 * stopped", 4.4 million times, in bursts of up to 209 a half second), and the log bundle copied it whole: a ~415 MB copy,
 * a ~415 MB zip at the next start, far past what a player can send. Now a run of lines that are the same after their
 * time stamp (UE4SS 3.0.1's "[2026-11-10 19:01:46.9542123] "; an undated "[HH:MM:SS.fffffff] " too) is written once,
 * then one line saying how many more there were and until when; the copy stops taking lines past LD_CAP bytes (counted,
 * a line says so once); the counts and the most repeated line go to the bundle's bundle.txt (logbundle.c). Pure C: the
 * writer is the caller's function.
 * ((2026-11-11, review) the first version knew only the undated stamp, never what UE4SS writes: on her real log it
 *  collapsed 2 lines of 4.48 million and stopped at 64 MB, 3.5 hours short. Fed the same log now: ~9 MB, nothing
 *  dropped. And past the cap it still wrote each run's line (~100 bytes a short run, unbounded): now nothing is written
 *  there but the cap's own line, once, and the line of a run already going when the cap was reached.) */
#ifndef SV_LOGDEDUP_H
#define SV_LOGDEDUP_H

#define LD_LINE  4096                 /* a line's body kept to compare (a longer one: its hash and length too) */
#define LD_STAMP 40
#define LD_TOP   64                   /* the most repeated lines tracked (by their hash) */
#define LD_CAP   (64ull << 20)        /* the copy's size at most (bytes written) */

typedef void (*LdPutFn)(void* ctx, const char* p, size_t n);

typedef struct {
    /* the line being read (a chunk can end in the middle of one) */
    char     cur[LD_LINE];
    size_t   curN, curLen;            /* bytes kept, the whole line's length */
    uint64_t curHash;
    /* the last line written, and the run of the same after it */
    char     prev[LD_LINE];
    size_t   prevN, prevLen;
    uint64_t prevHash;
    int      havePrev;
    uint64_t run;                     /* lines like it since, not written */
    char     runFirst[LD_STAMP], runLast[LD_STAMP];
    int      capSaid;
    /* counts */
    uint64_t inBytes, outBytes, lines, collapsed, dropped, runs;
    struct { uint64_t hash, n; } top[LD_TOP];
    char     topText[208];
    uint64_t topN, topHash;
} LdState;

static uint64_t LdHash(uint64_t h, const char* p, size_t n)
{
    for (size_t i = 0; i < n; ++i) { h ^= (uint8_t)p[i]; h *= 1099511628211ull; }
    return h;
}

/* the body's start: past a leading "[...] " time stamp of up to LD_STAMP - 2 characters, digits (one at least), '-',
 * ':', '.' and spaces inside: UE4SS 3.0.1's "[2026-11-10 19:01:46.9542123] ", or "[19:01:46.9542123] "; *stampN its
 * length (0 none). Not a stamp: "[Lua] ...", "[ ] ...", "[] ...". */
static size_t LdBody(const char* l, size_t n, size_t* stampN)
{
    *stampN = 0;
    if (!n || l[0] != '[') return 0;
    int digits = 0;
    for (size_t i = 1; i < n && i < LD_STAMP - 2; ++i) {
        char c = l[i];
        if (c == ']') {
            if (!digits) return 0;
            *stampN = i + 1;
            return (i + 1 < n && l[i + 1] == ' ') ? i + 2 : i + 1;
        }
        if (c >= '0' && c <= '9') digits = 1;
        else if (c != ':' && c != '.' && c != '-' && c != ' ') return 0;
    }
    return 0;
}

static void LdOut(LdState* s, LdPutFn put, void* ctx, const char* p, size_t n)
{
    put(ctx, p, n);
    s->outBytes += n;
}

static size_t LdNum(char* o, uint64_t v)
{
    char t[24]; size_t n = 0, k = 0;
    do { t[n++] = (char)('0' + v % 10); v /= 10; } while (v && n < 20);
    while (n) o[k++] = t[--n];
    return k;
}

/* the run's line: "[<last stamp>] ---- the line above 1234 more times (from [<first>]) ----" */
static void LdRunEnd(LdState* s, LdPutFn put, void* ctx)
{
    if (!s->run) return;
    char b[200];
    size_t k = 0;
    const char* a = s->runLast;
    for (size_t i = 0; a[i] && k < 60; ++i) b[k++] = a[i];
    if (k) b[k++] = ' ';
    static const char t1[] = "---- the line above ";
    for (size_t i = 0; t1[i]; ++i) b[k++] = t1[i];
    k += LdNum(b + k, s->run);
    static const char t2[] = " more times";
    for (size_t i = 0; t2[i]; ++i) b[k++] = t2[i];
    if (s->runFirst[0]) {
        static const char t3[] = " (from ";
        for (size_t i = 0; t3[i]; ++i) b[k++] = t3[i];
        for (size_t i = 0; s->runFirst[i] && k < 170; ++i) b[k++] = s->runFirst[i];
        b[k++] = ')';
    }
    static const char t4[] = " ----\r\n";
    for (size_t i = 0; t4[i]; ++i) b[k++] = t4[i];
    LdOut(s, put, ctx, b, k);
    s->runs++;
    s->run = 0;
}

/* the most repeated lines: a body's hash counted once more (the space-saving way: a full table's smallest replaced) */
static void LdTop(LdState* s)
{
    int at = -1, low = 0;
    for (int i = 0; i < LD_TOP; ++i) {
        if (s->top[i].n && s->top[i].hash == s->prevHash) { at = i; break; }
        if (s->top[i].n < s->top[low].n) low = i;
    }
    if (at < 0) { at = low; s->top[at].hash = s->prevHash; }
    s->top[at].n++;
    if (s->top[at].n > s->topN) {
        s->topN = s->top[at].n;
        if (s->topHash != s->prevHash) {
            s->topHash = s->prevHash;
            size_t k = 0;
            for (size_t i = 0; i < s->prevN && k < sizeof(s->topText) - 1; ++i) {
                char c = s->prev[i];
                if (c == '\r' || c == '\n') break;
                s->topText[k++] = (c >= 0x20 && c < 0x7F) ? c : '?';
            }
            s->topText[k] = 0;
        }
    }
}

/* one whole line (cur, without its "\n"): written, or counted in the run of the line before it */
static void LdLine(LdState* s, LdPutFn put, void* ctx)
{
    size_t stampN = 0, b = LdBody(s->cur, s->curN, &stampN);
    size_t bodyN = s->curN - b, bodyLen = s->curLen - b;
    if (bodyN && s->cur[b + bodyN - 1] == '\r') { --bodyN; --bodyLen; }
    uint64_t h = LdHash(LdHash(1469598103934665603ull, s->cur + b, bodyN), (const char*)&bodyLen, sizeof(bodyLen));
    if (s->curLen > s->curN) h ^= s->curHash;          /* (a line longer than kept: the rest's hash too) */
    s->lines++;
    int same = s->havePrev && h == s->prevHash && bodyLen == s->prevLen && bodyN == s->prevN &&
               !memcmp(s->cur + b, s->prev, bodyN);
    /* (a run starts only below LD_CAP, and nothing is written while it goes on: its line, written as it ends, is the only
     *  one past the cap, once, and it is about a line the copy holds) */
    if (same && (s->run || s->outBytes < LD_CAP)) {
        char* dst = s->run ? s->runLast : s->runFirst;
        size_t k = stampN < LD_STAMP - 1 ? stampN : LD_STAMP - 1;
        memcpy(dst, s->cur, k); dst[k] = 0;
        if (!s->run) { memcpy(s->runLast, s->runFirst, LD_STAMP); }
        s->run++;
        s->collapsed++;
        LdTop(s);
        return;
    }
    LdRunEnd(s, put, ctx);
    if (s->outBytes >= LD_CAP) {                       /* past the cap: counted (dropped), its line not written */
        if (!s->capSaid) {
            static const char m[] = "---- the copy of UE4SS.log stops here: 64 MB (the lines after are counted in bundle.txt) ----\r\n";
            LdOut(s, put, ctx, m, sizeof(m) - 1);
            s->capSaid = 1;
        }
        s->dropped++;
        if (same) { LdTop(s); return; }                 /* (a repeat: still counted for the most repeated line) */
    } else {
        LdOut(s, put, ctx, s->cur, s->curN);
        if (s->curLen > s->curN) {
            static const char cut[] = " ...(cut)";
            LdOut(s, put, ctx, cut, sizeof(cut) - 1);
        }
        LdOut(s, put, ctx, "\n", 1);
    }
    memcpy(s->prev, s->cur + b, bodyN);
    s->prevN = bodyN; s->prevLen = bodyLen; s->prevHash = h; s->havePrev = 1;
}

/* what the file gained: n bytes */
static void LdFeed(LdState* s, const char* in, size_t n, LdPutFn put, void* ctx)
{
    s->inBytes += n;
    for (size_t i = 0; i < n; ++i) {
        char c = in[i];
        if (c == '\n') {
            LdLine(s, put, ctx);
            s->curN = s->curLen = 0; s->curHash = 1469598103934665603ull;
            continue;
        }
        if (s->curN < LD_LINE) s->cur[s->curN++] = c;
        else s->curHash = LdHash(s->curHash, &c, 1);
        s->curLen++;
    }
}

/* nothing new for a while (the copy's pass): a run's line written now, not lost if the game stops (a run only goes on
 * below LD_CAP: past it, this writes nothing) */
static void LdIdle(LdState* s, LdPutFn put, void* ctx) { LdRunEnd(s, put, ctx); }

static void LdInit(LdState* s) { memset(s, 0, sizeof(*s)); s->curHash = 1469598103934665603ull; }

#endif
