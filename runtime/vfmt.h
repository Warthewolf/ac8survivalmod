/* VFmt: the runtime's printf for Log and Crumb (runtime/survival_rt.c). It understands only %s (a wide string), %d, %u,
 * %x and %p (hard rule 43: anything else takes no argument, so a later %s would read a number as a string). The output is
 * cut at cap - 1 characters and always ends in a NUL. The includer has wchar_t, size_t, int32_t, uint32_t, uint64_t,
 * uintptr_t and va_list. tools/checks/vfmt_test.sh runs it. */
#ifndef SV_VFMT_H
#define SV_VFMT_H
static void VFmt(wchar_t* out, size_t cap, const wchar_t* fmt, va_list ap)
{
    wchar_t* p = out; wchar_t* end = out + cap - 1;
    /* (0.32.23) ch is read whether or not it fits: `while (*s) PUT(*s++)` and `while (n) PUT(t[--n])` advance through it,
     * so a line past the buffer used to loop for ever holding the log lock. 0.32.22's three new Lua functions made the
     * "Lua bridge: ... registered" line 1,031 characters: its thread (UE4SS's Lua start) never returned, Survival's Lua
     * never started and every later Log waited (the user's launches of 2026-11-03 23:33 and 23:48) */
#define PUT(ch) do { wchar_t c_ = (wchar_t)(ch); if (p < end) *p++ = c_; } while (0)
    for (; *fmt; ++fmt) {
        if (*fmt != L'%') { PUT(*fmt); continue; }
        ++fmt;
        if (!*fmt) break;
        if (*fmt == L's') {
            const wchar_t* s = va_arg(ap, const wchar_t*);
            if (!s) s = L"<null>";
            while (*s) PUT(*s++);
        } else if (*fmt == L'd' || *fmt == L'u') {      /* (%u: 0.18.0's sound log used it and crashed: unknown here,
                                                           it took no argument, so the next %s read a number) */
            int32_t d = va_arg(ap, int32_t);
            uint64_t v = *fmt == L'u' ? (uint64_t)(uint32_t)d : d < 0 ? (uint64_t)(-(int64_t)d) : (uint64_t)d;
            if (*fmt == L'd' && d < 0) PUT(L'-');
            wchar_t t[24]; int n = 0;
            do { t[n++] = (wchar_t)(L'0' + v % 10); v /= 10; } while (v);
            while (n) PUT(t[--n]);
        } else if (*fmt == L'x' || *fmt == L'p') {
            uint64_t v = *fmt == L'p' ? (uint64_t)(uintptr_t)va_arg(ap, void*) : va_arg(ap, uint32_t);
            wchar_t t[16]; int n = 0;
            do { t[n++] = L"0123456789ABCDEF"[v & 15]; v >>= 4; } while (v);
            while (n) PUT(t[--n]);
        } else {
            PUT(*fmt);
        }
    }
    *p = 0;
#undef PUT
}
#endif
