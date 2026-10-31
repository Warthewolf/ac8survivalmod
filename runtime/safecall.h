/* safecall.h : a call into game code that comes back from an access violation (runtime 0.32.12; flight.c's target
 * search guard). A weapon's target search asks every target entry, on worker threads, through each entry class's check
 * (slot +0x60); some 20 of those classes use their unit's world (0x143fc1ca0, NULL once the unit is being destroyed)
 * with no test, and Alyssa's game crashed in one (2026-10-31 00:50, 0.73.37: class 0x147454050's NULL + 0x898, seconds
 * after 13 enemy copies were taken down and their flights spawned again, as the 12:07 crash). ScCall4 runs such a check
 * with a frame armed on its thread; an access violation inside it comes back to ScCall4 (a vectored exception handler
 * puts the thread back where ScCall4 captured it) and the call answers 0: "not a target". Nothing else is touched: an
 * exception on a thread with no frame armed, or of another kind, goes on to the game's own handling.
 * ScInit resolves its kernel32 calls by name (the runtime links only what win32_min.h declares).
 * tools/checks/safecall_test.c runs it on a made-up fault. */
#ifndef SV_SAFECALL_H
#define SV_SAFECALL_H

typedef struct { uint32_t code, flags; void* rec; void* addr; uint32_t n, pad; uint64_t info[15]; } ScExRec;
typedef struct { ScExRec* rec; uint8_t* ctx; } ScExPtrs;
#define SC_CTX_SIZE 0x4D0                                  /* (x64 CONTEXT: 1232 bytes, 16-aligned) */
typedef struct { _Alignas(16) uint8_t ctx[SC_CTX_SIZE]; volatile int32_t armed, faulted; void* volatile addr;
                 volatile uint64_t at; } ScFrame;
typedef uint8_t (*ScFn4)(void* a, void* b, void* c, void* d);

static uint32_t g_scTls = 0xFFFFFFFFu;
static void*   (*g_scTlsGet)(uint32_t);
static int32_t (*g_scTlsSet)(uint32_t, void*);
static void    (*g_scCapture)(void* ctx);

static int32_t ScVeh(ScExPtrs* e)
{
    if (!e || !e->rec || !e->ctx || e->rec->code != 0xC0000005u || g_scTls == 0xFFFFFFFFu) return 0;   /* (search on) */
    ScFrame* f = (ScFrame*)g_scTlsGet(g_scTls);
    if (!f || !f->armed) return 0;
    f->armed = 0;
    f->faulted = 1;
    f->addr = e->rec->addr;
    f->at = e->rec->n >= 2 ? e->rec->info[1] : 0;
    for (int i = 0; i < SC_CTX_SIZE; ++i) e->ctx[i] = f->ctx[i];     /* (back where ScCall4 captured it) */
    return -1;                                                        /* EXCEPTION_CONTINUE_EXECUTION */
}

/* 1 ready, 0 not (no kernel32 calls, no TLS slot, no handler): ScCall4 then calls straight through */
static int ScInit(void* k32)
{
    void* (*getProc)(void*, const char*) = (void* (*)(void*, const char*))(void*)GetProcAddress;
    if (!k32) return 0;
    uint32_t (*tlsAlloc)(void) = (uint32_t (*)(void))getProc(k32, "TlsAlloc");
    void* (*addVeh)(uint32_t, void*) = (void* (*)(uint32_t, void*))getProc(k32, "AddVectoredExceptionHandler");
    g_scTlsGet = (void* (*)(uint32_t))getProc(k32, "TlsGetValue");
    g_scTlsSet = (int32_t (*)(uint32_t, void*))getProc(k32, "TlsSetValue");
    g_scCapture = (void (*)(void*))getProc(k32, "RtlCaptureContext");
    if (!tlsAlloc || !addVeh || !g_scTlsGet || !g_scTlsSet || !g_scCapture) return 0;
    uint32_t slot = tlsAlloc();
    if (slot == 0xFFFFFFFFu) return 0;
    if (!addVeh(1, (void*)ScVeh)) return 0;
    g_scTls = slot;
    return 1;
}

/* fn(a, b, c, d); 0 with *faulted = 1 (and where: *addr, the address read *at) if it hit an access violation */
static __attribute__((noinline)) uint8_t ScCall4(ScFn4 fn, void* a, void* b, void* c, void* d, int* faulted, void** addr,
                                                 uint64_t* at)
{
    *faulted = 0;
    if (g_scTls == 0xFFFFFFFFu) return fn(a, b, c, d);
    ScFrame fr;
    fr.armed = 0;
    fr.faulted = 0;
    void* prev = g_scTlsGet(g_scTls);
    g_scCapture(fr.ctx);
    if (fr.faulted) {                                     /* (back from the handler) */
        g_scTlsSet(g_scTls, prev);
        *faulted = 1;
        if (addr) *addr = fr.addr;
        if (at) *at = fr.at;
        return 0;
    }
    g_scTlsSet(g_scTls, &fr);
    fr.armed = 1;
    uint8_t r = fn(a, b, c, d);
    fr.armed = 0;
    g_scTlsSet(g_scTls, prev);
    return r;
}

#endif
