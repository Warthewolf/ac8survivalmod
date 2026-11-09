/* logzip.h : a "stored" (method 0) zip writer and the log-zip pruning, with no Win32 declarations of its own, so the
 * runtime (win32_min.h) and tools/checks/logbundle_test.c (windows.h) both include it. It calls CreateFileW, ReadFile,
 * WriteFile, CloseHandle, WideCharToMultiByte, FindFirstFileW, FindNextFileW, FindClose and DeleteFileW, and uses
 * HANDLE, DWORD, BOOL, WIN32_FIND_DATAW (only dwFileAttributes and cFileName), wchar_t and the stdint types.
 *
 * No ZIP64: an entry of 0xFFFFFFFF bytes or more (or one that would push the archive's offsets there) is skipped and
 * reported. Names are UTF-8 (general purpose bit 11). Times are the file's last-write time in UTC (the DOS fields have
 * no zone). Each file is read twice instead of seeking: a first pass for its CRC-32 and size, a second that copies
 * exactly that many bytes (a file that grew keeps its first bytes; one that shrank is padded with zeros and reported
 * LZ_CHANGED, its CRC then wrong). One zip at a time (the buffers are static).                                        */
#ifndef LOGZIP_H
#define LOGZIP_H

#define LZ_OK       0
#define LZ_LOCKED   1      /* could not be opened */
#define LZ_BIG      2      /* too big for a non-ZIP64 zip */
#define LZ_READ     3      /* read error */
#define LZ_FULL     4      /* the central directory buffer or the entry count is full, or a bad name */
#define LZ_CHANGED  5      /* shrank while it was copied (padded with zeros) */
#define LZ_WRITE    6      /* the zip itself could not be written */

typedef struct {
    HANDLE   h;
    uint64_t pos;          /* bytes written */
    uint32_t n;            /* entries */
    uint32_t cdLen;        /* bytes in lz_cd */
    int      err;
    uint64_t lastSize;     /* the last LzAddFile / LzAddMem entry's size */
} LzZip;

static uint8_t  lz_buf[65536];
static uint8_t  lz_cd[131072];
static uint32_t lz_crcT[256];
static int      lz_crcInit;

static size_t LzWLen(const wchar_t* s) { size_t n = 0; while (s[n]) ++n; return n; }

static void LzCrcInit(void)
{
    for (uint32_t i = 0; i < 256; ++i) {
        uint32_t c = i;
        for (int k = 0; k < 8; ++k) c = (c & 1u) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
        lz_crcT[i] = c;
    }
    lz_crcInit = 1;
}

/* running state: start at 0xFFFFFFFF, finish with ^ 0xFFFFFFFF */
static uint32_t LzCrc(uint32_t crc, const uint8_t* p, uint32_t n)
{
    if (!lz_crcInit) LzCrcInit();
    for (uint32_t i = 0; i < n; ++i) crc = lz_crcT[(crc ^ p[i]) & 0xFFu] ^ (crc >> 8);
    return crc;
}

static void LzPut(LzZip* z, const void* p, uint32_t n)
{
    if (z->err || !n) return;
    DWORD put = 0;
    if (!WriteFile(z->h, p, n, &put, NULL) || put != n) { z->err = 1; return; }
    z->pos += n;
}

static void LzW16(uint8_t* p, uint32_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static void LzW32(uint8_t* p, uint32_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }

/* FILETIME (100 ns since 1601, UTC) -> MS-DOS time and date; 0 or out of range -> 1980-01-01 */
static void LzDos(uint64_t ft, uint32_t* tm, uint32_t* dt)
{
    *tm = 0; *dt = (1u << 5) | 1u;
    if (!ft) return;
    int64_t secs = (int64_t)(ft / 10000000ull);
    int64_t days = secs / 86400 - 134774;               /* since 1970-01-01 */
    int64_t rem = secs % 86400;
    int64_t z = days + 719468;
    int64_t era = (z >= 0 ? z : z - 146096) / 146097;
    int64_t doe = z - era * 146097;
    int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t y = yoe + era * 400;
    int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    int64_t mp = (5 * doy + 2) / 153;
    int64_t d = doy - (153 * mp + 2) / 5 + 1;
    int64_t m = mp < 10 ? mp + 3 : mp - 9;
    if (m <= 2) ++y;
    if (y < 1980 || y > 2107) return;
    *tm = (uint32_t)(((rem / 3600) << 11) | (((rem / 60) % 60) << 5) | ((rem % 60) / 2));
    *dt = (uint32_t)(((y - 1980) << 9) | (m << 5) | d);
}

static int LzBegin(LzZip* z, const wchar_t* path)
{
    z->pos = 0; z->n = 0; z->cdLen = 0; z->err = 0; z->lastSize = 0;
    z->h = CreateFileW(path, 0x40000000u, 1u, NULL, 2u, 0x80u, NULL);   /* GENERIC_WRITE, share read, CREATE_ALWAYS */
    return z->h != INVALID_HANDLE_VALUE;
}

static void LzAbort(LzZip* z)
{
    if (z->h != INVALID_HANDLE_VALUE) CloseHandle(z->h);
    z->h = INVALID_HANDLE_VALUE;
}

/* Writes the local header of an entry whose data (size bytes) the caller writes next; records its central entry.
 * LZ_OK, or LZ_FULL / LZ_BIG (nothing written). */
static int LzBeginEntry(LzZip* z, const wchar_t* name, uint32_t crc, uint32_t size, uint64_t ft)
{
    uint8_t hdr[1100];
    char u[1000];
    int nl = WideCharToMultiByte(65001u, 0, name, -1, u, (int)sizeof(u), NULL, NULL);
    if (nl <= 1) return LZ_FULL;
    nl -= 1;                                              /* without the NUL */
    for (int i = 0; i < nl; ++i) if (u[i] == '\\') u[i] = '/';
    if (z->n >= 60000u || z->cdLen + 46u + (uint32_t)nl > sizeof(lz_cd)) return LZ_FULL;
    if (z->pos + 30u + (uint64_t)nl + size + z->cdLen + 46u + (uint64_t)nl + 22u + 64u > 0xFFFFFFF0ull) return LZ_BIG;
    uint32_t tm, dt;
    LzDos(ft, &tm, &dt);
    LzW32(hdr, 0x04034b50u); LzW16(hdr + 4, 20); LzW16(hdr + 6, 0x0800); LzW16(hdr + 8, 0);
    LzW16(hdr + 10, tm); LzW16(hdr + 12, dt); LzW32(hdr + 14, crc); LzW32(hdr + 18, size); LzW32(hdr + 22, size);
    LzW16(hdr + 26, (uint32_t)nl); LzW16(hdr + 28, 0);
    for (int i = 0; i < nl; ++i) hdr[30 + i] = (uint8_t)u[i];
    uint8_t* c = lz_cd + z->cdLen;
    LzW32(c, 0x02014b50u); LzW16(c + 4, 20); LzW16(c + 6, 20); LzW16(c + 8, 0x0800); LzW16(c + 10, 0);
    LzW16(c + 12, tm); LzW16(c + 14, dt); LzW32(c + 16, crc); LzW32(c + 20, size); LzW32(c + 24, size);
    LzW16(c + 28, (uint32_t)nl); LzW16(c + 30, 0); LzW16(c + 32, 0); LzW16(c + 34, 0); LzW16(c + 36, 0);
    LzW32(c + 38, 0); LzW32(c + 42, (uint32_t)z->pos);
    for (int i = 0; i < nl; ++i) c[46 + i] = (uint8_t)u[i];
    z->cdLen += 46u + (uint32_t)nl;
    z->n += 1;
    LzPut(z, hdr, 30u + (uint32_t)nl);
    return LZ_OK;
}

static void LzPad(LzZip* z, uint64_t n)
{
    for (uint32_t i = 0; i < sizeof(lz_buf); ++i) lz_buf[i] = 0;
    while (n && !z->err) {
        uint32_t k = n > sizeof(lz_buf) ? (uint32_t)sizeof(lz_buf) : (uint32_t)n;
        LzPut(z, lz_buf, k);
        n -= k;
    }
}

static int LzAddMem(LzZip* z, const wchar_t* name, const void* data, uint32_t len, uint64_t ft)
{
    uint32_t crc = LzCrc(0xFFFFFFFFu, (const uint8_t*)data, len) ^ 0xFFFFFFFFu;
    int rc = LzBeginEntry(z, name, crc, len, ft);
    if (rc != LZ_OK) return rc;
    LzPut(z, data, len);
    z->lastSize = len;
    return z->err ? LZ_WRITE : LZ_OK;
}

static int LzAddFile(LzZip* z, const wchar_t* name, const wchar_t* path, uint64_t ft)
{
    HANDLE h = CreateFileW(path, 0x80000000u, 7u, NULL, 3u, 0x80u, NULL);   /* read; share all; OPEN_EXISTING */
    if (h == INVALID_HANDLE_VALUE) return LZ_LOCKED;
    uint32_t crc = 0xFFFFFFFFu;
    uint64_t size = 0;
    int rc = LZ_OK;
    for (;;) {
        DWORD got = 0;
        if (!ReadFile(h, lz_buf, (DWORD)sizeof(lz_buf), &got, NULL)) { rc = LZ_READ; break; }
        if (!got) break;
        crc = LzCrc(crc, lz_buf, got);
        size += got;
        if (size > 0xFFFFFFFEull) { rc = LZ_BIG; break; }
    }
    CloseHandle(h);
    if (rc != LZ_OK) return rc;
    crc ^= 0xFFFFFFFFu;
    rc = LzBeginEntry(z, name, crc, (uint32_t)size, ft);
    if (rc != LZ_OK) return rc;
    z->lastSize = size;
    if (size) {
        uint64_t left = size;
        h = CreateFileW(path, 0x80000000u, 7u, NULL, 3u, 0x80u, NULL);
        if (h == INVALID_HANDLE_VALUE) { LzPad(z, left); return z->err ? LZ_WRITE : LZ_CHANGED; }
        while (left && !z->err) {
            DWORD want = left > sizeof(lz_buf) ? (DWORD)sizeof(lz_buf) : (DWORD)left;
            DWORD got = 0;
            if (!ReadFile(h, lz_buf, want, &got, NULL)) { rc = LZ_READ; break; }
            if (!got) { rc = LZ_CHANGED; break; }
            LzPut(z, lz_buf, got);
            left -= got;
        }
        CloseHandle(h);
        if (left && !z->err) LzPad(z, left);
    }
    return z->err ? LZ_WRITE : rc;
}

/* central directory + end record, then closes the file; 1 when the whole zip was written */
static int LzEnd(LzZip* z)
{
    uint8_t e[22];
    uint32_t cdOff = (uint32_t)z->pos;
    uint32_t cdLen = z->cdLen;
    uint32_t n = z->n;
    LzPut(z, lz_cd, cdLen);
    LzW32(e, 0x06054b50u); LzW16(e + 4, 0); LzW16(e + 6, 0); LzW16(e + 8, n); LzW16(e + 10, n);
    LzW32(e + 12, cdLen); LzW32(e + 16, cdOff); LzW16(e + 20, 0);
    LzPut(z, e, 22);
    int ok = !z->err;
    LzAbort(z);
    return ok;
}

static int LzWCmp(const wchar_t* a, const wchar_t* b)
{
    while (*a && *a == *b) { ++a; ++b; }
    return (int)*a - (int)*b;
}

/* Keeps the `keep` newest <dir>\<prefix>*.zip (the name's timestamp sorts) and deletes the others; returns how many
 * it deleted. */
static int LzPrune(const wchar_t* dir, const wchar_t* prefix, int keep)
{
    static wchar_t names[256][80];
    static wchar_t pat[1024];
    int n = 0, gone = 0;
    size_t dl = LzWLen(dir), pl = LzWLen(prefix);
    if (!dl || dl + pl + 90 >= 1024 || keep < 0) return 0;
    for (size_t i = 0; i < dl; ++i) pat[i] = dir[i];
    pat[dl] = L'\\';
    for (size_t i = 0; i < pl; ++i) pat[dl + 1 + i] = prefix[i];
    pat[dl + 1 + pl] = L'*'; pat[dl + 2 + pl] = 0;
    WIN32_FIND_DATAW fd;
    HANDLE f = FindFirstFileW(pat, &fd);
    if (f == INVALID_HANDLE_VALUE) return 0;
    do {
        size_t l = LzWLen(fd.cFileName);
        if ((fd.dwFileAttributes & 0x10u) || l < 5 || l >= 79 || n >= 256) continue;
        const wchar_t* t = fd.cFileName + l - 4;
        if (t[0] != L'.' || t[1] != L'z' || t[2] != L'i' || t[3] != L'p') continue;
        for (size_t i = 0; i <= l; ++i) names[n][i] = fd.cFileName[i];
        ++n;
    } while (FindNextFileW(f, &fd));
    FindClose(f);
    for (int i = 1; i < n; ++i) {                          /* insertion sort, oldest first */
        wchar_t tmp[80];
        for (int k = 0; k < 80; ++k) tmp[k] = names[i][k];
        int j = i - 1;
        while (j >= 0 && LzWCmp(names[j], tmp) > 0) { for (int k = 0; k < 80; ++k) names[j + 1][k] = names[j][k]; --j; }
        for (int k = 0; k < 80; ++k) names[j + 1][k] = tmp[k];
    }
    for (int i = 0; i < n - keep; ++i) {
        size_t l = LzWLen(names[i]);
        for (size_t k = 0; k <= l; ++k) pat[dl + 1 + k] = names[i][k];
        if (DeleteFileW(pat)) ++gone;
    }
    return gone;
}

#endif /* LOGZIP_H */
