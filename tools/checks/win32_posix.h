/* win32_posix.h : the few Win32 pieces tools/checks/coop_test.c and flight_test.c (and the runtime/coop.c they #include)
 * use, on POSIX (Linux, a cloud session), so both tests build and run there with no change to a shipped file. It is
 * never used on Windows: coop_test.sh / flight_test.sh put it in front of the compiler off Windows only (a generated
 * build/checks/posix_inc/windows.h that #includes this file), and it refuses to build under _WIN32.
 *
 *   Clock    QueryPerformanceCounter / QueryPerformanceFrequency (CLOCK_MONOTONIC, ns), GetTickCount64, Sleep (ms)
 *   Modules  GetModuleHandleW / LoadLibraryW / GetProcAddress: "ws2_32.dll" is a fake module whose exports are BSD
 *            sockets behind the Winsock names and signatures coop.c calls through (WSAStartup, socket, bind, sendto,
 *            recvfrom, ioctlsocket (FIONBIO only), closesocket, WSAGetLastError); "steam_api64.dll" is not loaded (as in
 *            the Windows test), so Steam co-op stays off and only UDP is tested. Any other name: NULL.
 *            SO_REUSEADDR is never set: a joiner's bind of the host's port (27791) must FAIL so it falls back to any
 *            port (coop.c CoUdpOpen; coop_lua.c), as Winsock's default does.
 *   Text     _vsnwprintf and wprintf with the MS CRT's legacy meanings (in a wide function %s and %ls are wide strings,
 *            %hs and %S narrow), written out NARROW (UTF-8) with fputs: glibc lets a stream be wide or narrow, never
 *            both, and one real wprintf made every later printf of the test vanish (the test then "passed" mute).
 *            The tests' Log lines go through here, so nothing on Linux ever calls a wide stdio function.
 *   Process  GetCurrentProcessId
 *
 * What a POSIX build can't show (a passing Linux run is no proof of these on Windows):
 *  - wchar_t is 4 bytes here, 2 on Windows. coop.c's own wide strings are only for its log (CoWide, ASCII), but
 *    coop_lua.c builds UE FStrings (TCHAR = UTF-16) as wchar_t arrays (CoUtf8To16, the callsign's
 *    { wchar_t* data; int32 num, max } at coop_lua.c:625-670): on Linux those would be UTF-32 and the surrogate pairs
 *    meaningless. Neither test calls that path; a test of it here would pass or fail for the wrong reason.
 *  - long is 8 bytes here, 4 on Windows (LLP64): a `long` / `%ld` in the runtime would behave differently.
 *  - Winsock's error codes (WSAEADDRINUSE 10048, WSAEWOULDBLOCK 10035) differ from errno's; coop.c only logs them.
 *  - recvfrom on Windows fails with WSAECONNRESET after an ICMP port unreachable on a UDP socket; Linux doesn't report
 *    it on an unconnected socket. coop.c's loop stops on got <= 0, so on Windows one ICMP stops a frame's reads early.
 *  - the Windows build is clang with -w and the MSVC ABI (and its _vsnwprintf, which takes %.2f etc.); this file's
 *    formatter takes the runtime's specifiers and the usual flags, width, precision and length modifiers. */
#ifndef SV_WIN32_POSIX_H
#define SV_WIN32_POSIX_H
#ifdef _WIN32
#error "win32_posix.h is for POSIX builds only (Windows has windows.h)"
#endif
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <errno.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

typedef void* HANDLE;
typedef void* HMODULE;
typedef void* FARPROC;
typedef uint32_t DWORD;
typedef int BOOL;

/* ---- clock ---- */
static inline int QueryPerformanceFrequency(int64_t* f) { if (f) *f = 1000000000LL; return 1; }
static inline int QueryPerformanceCounter(int64_t* c)
{
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    if (c) *c = (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
    return 1;
}
static inline uint64_t GetTickCount64(void)
{
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}
static inline void Sleep(DWORD ms)
{
    struct timespec ts = { (time_t)(ms / 1000), (long)(ms % 1000) * 1000000L };
    while (nanosleep(&ts, &ts) != 0 && errno == EINTR) { }
}
static inline DWORD GetCurrentProcessId(void) { return (DWORD)getpid(); }

/* ---- Winsock over BSD sockets: the signatures coop.c's WS table calls through ---- */
static int32_t W32P_wsaStartup(uint16_t version, void* data) { (void)version; (void)data; return 0; }
static uintptr_t W32P_socket(int32_t af, int32_t type, int32_t proto)
{
    /* (Winsock's 2 / 2 / 17 are AF_INET / SOCK_DGRAM / IPPROTO_UDP on Linux too) */
    int s = socket(af, type, proto);
    return s < 0 ? (uintptr_t)-1 : (uintptr_t)s;        /* (INVALID_SOCKET; never SO_REUSEADDR: see the header) */
}
static int32_t W32P_bind(uintptr_t s, const void* addr, int32_t len)
{
    return bind((int)s, (const struct sockaddr*)addr, (socklen_t)len) == 0 ? 0 : -1;
}
static int32_t W32P_sendto(uintptr_t s, const char* buf, int32_t len, int32_t flags, const void* to, int32_t tolen)
{
    ssize_t n = sendto((int)s, buf, (size_t)len, flags | MSG_NOSIGNAL, (const struct sockaddr*)to, (socklen_t)tolen);
    return n < 0 ? -1 : (int32_t)n;
}
static int32_t W32P_recvfrom(uintptr_t s, char* buf, int32_t len, int32_t flags, void* from, int32_t* fromlen)
{
    socklen_t fl = fromlen ? (socklen_t)*fromlen : 0;
    ssize_t n = recvfrom((int)s, buf, (size_t)len, flags, (struct sockaddr*)from, fromlen ? &fl : NULL);
    if (fromlen) *fromlen = (int32_t)fl;
    return n < 0 ? -1 : (int32_t)n;
}
static int32_t W32P_ioctlsocket(uintptr_t s, int32_t cmd, uint32_t* arg)
{
    if ((uint32_t)cmd != 0x8004667Eu || !arg) { errno = EINVAL; return -1; }   /* FIONBIO only */
    int fl = fcntl((int)s, F_GETFL, 0);
    if (fl < 0) return -1;
    return fcntl((int)s, F_SETFL, *arg ? (fl | O_NONBLOCK) : (fl & ~O_NONBLOCK)) == 0 ? 0 : -1;
}
static int32_t W32P_closesocket(uintptr_t s) { return close((int)s) == 0 ? 0 : -1; }
static int32_t W32P_lastError(void) { return errno; }

/* ---- modules ---- */
static char W32P_ws2;                                   /* the fake ws2_32.dll's handle is its address */
static int W32P_wnameIs(const wchar_t* a, const char* b)
{
    if (!a) return 0;
    for (; *a && *b; ++a, ++b) {
        wchar_t x = *a; char y = *b;
        if (x >= L'A' && x <= L'Z') x = (wchar_t)(x - L'A' + L'a');
        if (y >= 'A' && y <= 'Z') y = (char)(y - 'A' + 'a');
        if (x != (wchar_t)(unsigned char)y) return 0;
    }
    return !*a && !*b;
}
static inline HANDLE LoadLibraryW(const wchar_t* name) { return W32P_wnameIs(name, "ws2_32.dll") ? (HANDLE)&W32P_ws2 : NULL; }
static inline HANDLE GetModuleHandleW(const wchar_t* name) { (void)name; return NULL; }   /* (no steam_api64.dll here) */
static inline FARPROC GetProcAddress(HANDLE dll, const char* name)
{
    if (dll != (HANDLE)&W32P_ws2 || !name) return NULL;
    static const struct { const char* name; void* fn; } kWs[] = {
        { "WSAStartup", (void*)W32P_wsaStartup }, { "socket", (void*)W32P_socket }, { "bind", (void*)W32P_bind },
        { "sendto", (void*)W32P_sendto }, { "recvfrom", (void*)W32P_recvfrom }, { "ioctlsocket", (void*)W32P_ioctlsocket },
        { "closesocket", (void*)W32P_closesocket }, { "WSAGetLastError", (void*)W32P_lastError },
    };
    for (size_t i = 0; i < sizeof(kWs) / sizeof(kWs[0]); ++i) if (!strcmp(kWs[i].name, name)) return kWs[i].fn;
    return NULL;
}

/* ---- MS-style wide formatting, written out narrow ---- */
/* one wide character as UTF-8 into o (room for 4); returns the bytes */
static int W32P_utf8(uint32_t u, char* o)
{
    if (u < 0x80) { o[0] = (char)u; return 1; }
    if (u < 0x800) { o[0] = (char)(0xC0 | (u >> 6)); o[1] = (char)(0x80 | (u & 0x3F)); return 2; }
    if (u < 0x10000) { o[0] = (char)(0xE0 | (u >> 12)); o[1] = (char)(0x80 | ((u >> 6) & 0x3F)); o[2] = (char)(0x80 | (u & 0x3F)); return 3; }
    if (u < 0x110000) { o[0] = (char)(0xF0 | (u >> 18)); o[1] = (char)(0x80 | ((u >> 12) & 0x3F)); o[2] = (char)(0x80 | ((u >> 6) & 0x3F)); o[3] = (char)(0x80 | (u & 0x3F)); return 4; }
    o[0] = '?'; return 1;
}
/* _vsnwprintf(buf, count, fmt, ap) as the MS CRT: at most count characters, no NUL added when it doesn't fit (the tests
 * terminate it themselves), -1 when cut. %s / %ls / %ws a wide string, %hs / %S a narrow one, %c a wide character, the
 * integer conversions with h / l / ll / I64 / z (`l` reads a C long: 8 bytes here, 4 on Windows), %f %e %g, %p, %%.
 * Width, precision, flags. */
static int _vsnwprintf(wchar_t* buf, size_t count, const wchar_t* fmt, va_list ap)
{
    size_t n = 0; int cut = 0;
#define W32P_PUT(ch) do { if (n < count) buf[n++] = (wchar_t)(ch); else cut = 1; } while (0)
    for (; *fmt; ++fmt) {
        if (*fmt != L'%') { W32P_PUT(*fmt); continue; }
        const wchar_t* start = fmt++;
        if (*fmt == L'%') { W32P_PUT(L'%'); continue; }
        char spec[32]; int k = 0; spec[k++] = '%';
        while (*fmt && wcschr(L"-+ #0", *fmt) && k < 20) spec[k++] = (char)*fmt++;
        int star = 0;
        if (*fmt == L'*') { star |= 1; spec[k++] = '*'; ++fmt; }
        while (*fmt >= L'0' && *fmt <= L'9' && k < 24) spec[k++] = (char)*fmt++;
        if (*fmt == L'.') {
            spec[k++] = '.'; ++fmt;
            if (*fmt == L'*') { star |= 2; spec[k++] = '*'; ++fmt; }
            while (*fmt >= L'0' && *fmt <= L'9' && k < 28) spec[k++] = (char)*fmt++;
        }
        int len = 0;                                     /* 0 none, 'h', 'l', 'L' (ll / I64), 'z' */
        if (*fmt == L'h') { len = 'h'; ++fmt; if (*fmt == L'h') ++fmt; }
        else if (*fmt == L'l') { len = 'l'; ++fmt; if (*fmt == L'l') { len = 'L'; ++fmt; } }
        else if (*fmt == L'I' && fmt[1] == L'6' && fmt[2] == L'4') { len = 'L'; fmt += 3; }
        else if (*fmt == L'z' || *fmt == L'I') { len = 'z'; ++fmt; }
        else if (*fmt == L'j') { len = 'L'; ++fmt; }
        wchar_t c = *fmt;
        if (!c) { fmt = start; while (*fmt) W32P_PUT(*fmt++); --fmt; break; }
        int w = 0, pr = -1;
        if (star & 1) w = va_arg(ap, int);
        if (star & 2) pr = va_arg(ap, int);
        char tmp[512]; tmp[0] = 0;
        spec[k] = 0;
        if (c == L's' || c == L'S') {
            int narrow = (c == L'S' && len != 'l') || (c == L's' && len == 'h');
            /* (re-read width / precision from the spec for strings: we pad by hand, in characters) */
            if (!(star & 1)) { const char* q = spec + 1; while (*q && strchr("-+ #0", *q)) ++q; w = atoi(q); }
            if (!(star & 2)) { const char* d = strchr(spec, '.'); if (d) pr = atoi(d + 1); }
            int left = strchr(spec, '-') != NULL;
            if (narrow) {
                const char* s = va_arg(ap, const char*); if (!s) s = "(null)";
                size_t sl = strlen(s); if (pr >= 0 && (size_t)pr < sl) sl = (size_t)pr;
                for (int i = (int)sl; !left && i < w; ++i) W32P_PUT(L' ');
                for (size_t i = 0; i < sl; ++i) W32P_PUT((unsigned char)s[i]);
                for (int i = (int)sl; left && i < w; ++i) W32P_PUT(L' ');
            } else {
                const wchar_t* s = va_arg(ap, const wchar_t*); if (!s) s = L"(null)";
                size_t sl = wcslen(s); if (pr >= 0 && (size_t)pr < sl) sl = (size_t)pr;
                for (int i = (int)sl; !left && i < w; ++i) W32P_PUT(L' ');
                for (size_t i = 0; i < sl; ++i) W32P_PUT(s[i]);
                for (int i = (int)sl; left && i < w; ++i) W32P_PUT(L' ');
            }
            continue;
        }
        if (c == L'c' || c == L'C') { W32P_PUT((wchar_t)va_arg(ap, int)); continue; }
        char conv = (char)c;
        if (strchr("diouxX", conv)) {
            char full[40]; long long v = 0; unsigned long long uv = 0;
            int sgn = conv == 'd' || conv == 'i';
            if (len == 'L') { if (sgn) v = va_arg(ap, long long); else uv = va_arg(ap, unsigned long long); }
            else if (len == 'l') { if (sgn) v = va_arg(ap, long); else uv = va_arg(ap, unsigned long); }
            else if (len == 'z') { if (sgn) v = (long long)va_arg(ap, ptrdiff_t); else uv = va_arg(ap, size_t); }
            else { if (sgn) v = va_arg(ap, int); else uv = va_arg(ap, unsigned int);
                   if (len == 'h') { if (sgn) v = (short)v; else uv = (unsigned short)uv; } }
            snprintf(full, sizeof(full), "%sll%c", spec, conv);
            if (star == 3) { if (sgn) snprintf(tmp, sizeof(tmp), full, w, pr, v); else snprintf(tmp, sizeof(tmp), full, w, pr, uv); }
            else if (star) { int a = star & 1 ? w : pr; if (sgn) snprintf(tmp, sizeof(tmp), full, a, v); else snprintf(tmp, sizeof(tmp), full, a, uv); }
            else { if (sgn) snprintf(tmp, sizeof(tmp), full, v); else snprintf(tmp, sizeof(tmp), full, uv); }
        } else if (strchr("feEgGaA", conv)) {
            char full[40]; double v = va_arg(ap, double);
            snprintf(full, sizeof(full), "%s%c", spec, conv);
            if (star == 3) snprintf(tmp, sizeof(tmp), full, w, pr, v);
            else if (star) snprintf(tmp, sizeof(tmp), full, star & 1 ? w : pr, v);
            else snprintf(tmp, sizeof(tmp), full, v);
        } else if (conv == 'p') {
            snprintf(tmp, sizeof(tmp), "%016llX", (unsigned long long)(uintptr_t)va_arg(ap, void*));   /* (MS's %p) */
        } else {                                         /* unknown: copied as written, no argument taken */
            for (const wchar_t* q = start; q <= fmt; ++q) W32P_PUT(*q);
            continue;
        }
        for (const char* q = tmp; *q; ++q) W32P_PUT((unsigned char)*q);
    }
#undef W32P_PUT
    if (n < count) buf[n] = 0;
    return cut ? -1 : (int)n;
}
/* wprintf: formatted as above, printed as UTF-8 through the NARROW stdout (never fwide(stdout, 1)) */
static int W32P_wprintf(const wchar_t* fmt, ...)
{
    wchar_t w[4096];
    va_list ap; va_start(ap, fmt);
    int r = _vsnwprintf(w, 4095, fmt, ap);
    va_end(ap);
    w[4095] = 0;
    if (r < 0) w[4095] = 0;
    char o[4096 * 4 + 1]; size_t m = 0;
    for (const wchar_t* p = w; *p && m + 4 < sizeof(o); ++p) m += (size_t)W32P_utf8((uint32_t)*p, o + m);
    o[m] = 0;
    fputs(o, stdout);
    return (int)m;
}
#define wprintf W32P_wprintf

#endif
