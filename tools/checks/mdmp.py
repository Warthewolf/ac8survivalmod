"""mdmp.py : a crash report's minidump read without the game's symbols (plan F3, from the cloud session of 2026-11-03,
testing/2026-11-03/tools/mdmp.py; the reader the quit crash F1 and the bomber raid crash F2 were read with).

  python -X utf8 -I tools/checks/mdmp.py <UEMinidump.dmp> [--scan N] [--mods] [--map <main_<v>_<ts>.map>]

Prints the exception (code, where, an access violation's read / write / execute address), the faulting thread's
registers (each one inside a module named module+offset), the modules with --mods (with each one's link timestamp: pick
main.dll's map by it, build/runtime/main_<RT_VERSION>_<timestamp>.map, runtime/build.sh), and a scan of N words up the
faulting thread's stack (default 160) for values inside a module.
A scan is not an unwind: a value it finds can be a stale return address left by a call that already returned (the quit
crash's main.dll+0x1abe8 and +0x68b7 were: SpawnerReady's and L_UnitAlive's, from an SV_UnitAlive earlier in the same
Lua tick; the fault itself was in UE4SS's Lua property lookup). With --map, main.dll's values are named from the
runtime's linker map (function+offset); check the instruction before such an address is a call before reading it as a
frame (tools/llvm/LLVM/bin/llvm-objdump -d on the shipped main.dll). For the whole stack and the code bytes round given
addresses: tools/checks/deep.py.
"""
import re
import struct
import sys


def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]
def u64(b, o): return struct.unpack_from('<Q', b, o)[0]


class Dump:
    def __init__(self, path):
        self.b = open(path, 'rb').read()
        b = self.b
        assert b[:4] == b'MDMP', 'not a minidump'
        n, rva = u32(b, 8), u32(b, 12)
        self.streams = {}
        for i in range(n):
            t, size, loc = struct.unpack_from('<III', b, rva + i * 12)
            self.streams.setdefault(t, []).append((size, loc))
        self.mods = self._modules()
        self.mem = self._memory()
        self.syms = {}                                    # module name (lower case) -> sorted [(offset, symbol)]

    def _str(self, rva):
        n = u32(self.b, rva)
        return self.b[rva + 4: rva + 4 + n].decode('utf-16-le', 'replace')

    def _modules(self):
        out = []
        for size, loc in self.streams.get(4, []):
            n = u32(self.b, loc)
            for i in range(n):
                o = loc + 4 + i * 108
                base, sz = u64(self.b, o), u32(self.b, o + 8)
                ts = u32(self.b, o + 16)
                name = self._str(u32(self.b, o + 20))
                out.append((base, sz, name, ts))
        return sorted(out)

    def _memory(self):
        rng = []
        for size, loc in self.streams.get(9, []):      # Memory64List
            n, base_rva = u64(self.b, loc), u64(self.b, loc + 8)
            off = base_rva
            for i in range(n):
                start, sz = struct.unpack_from('<QQ', self.b, loc + 16 + i * 16)
                rng.append((start, sz, off))
                off += sz
        for size, loc in self.streams.get(5, []):      # MemoryList
            n = u32(self.b, loc)
            for i in range(n):
                start, dsz, drva = struct.unpack_from('<QII', self.b, loc + 4 + i * 16)
                rng.append((start, dsz, drva))
        return sorted(rng)

    def load_map(self, path, module='main.dll'):
        """an lld-link /map file: every text symbol's offset in the module (its Rva+Base less the preferred base)"""
        base, rows = 0x180000000, []
        for line in open(path, encoding='utf-8', errors='replace'):
            m = re.match(r'\s*Preferred load address is ([0-9a-fA-F]+)', line)
            if m: base = int(m.group(1), 16)
            m = re.match(r'\s*0001:[0-9a-fA-F]+\s+(\S+)\s+([0-9a-fA-F]{16})\b', line)
            if m: rows.append((int(m.group(2), 16) - base, m.group(1)))
        self.syms[module.lower()] = sorted(rows)
        return len(rows)

    def read(self, addr, n):
        for start, sz, off in self.mem:
            if start <= addr and addr + n <= start + sz:
                return self.b[off + addr - start: off + addr - start + n]
        return None

    def mod_of(self, addr):
        for base, sz, name, ts in self.mods:
            if base <= addr < base + sz:
                return name.split('\\')[-1], addr - base, base
        return None

    def sym(self, mod, off):
        rows = self.syms.get(mod.lower())
        if not rows: return ''
        best = None
        for o, s in rows:
            if o <= off: best = (o, s)
            else: break
        return ' (%s+0x%x)' % (best[1], off - best[0]) if best else ''

    def where(self, addr):
        m = self.mod_of(addr)
        return '%s+0x%x%s' % (m[0], m[1], self.sym(m[0], m[1])) if m else '?'

    def exception(self):
        for size, loc in self.streams.get(6, []):
            tid = u32(self.b, loc)
            rec = loc + 8
            code, flags = u32(self.b, rec), u32(self.b, rec + 4)
            addr = u64(self.b, rec + 16)
            nparams = u32(self.b, rec + 24)
            params = [u64(self.b, rec + 32 + 8 * i) for i in range(min(nparams, 15))]
            ctx_size, ctx_rva = u32(self.b, loc + 8 + 152), u32(self.b, loc + 8 + 156)
            return tid, code, addr, params, ctx_rva
        return None

    def context(self, rva):
        b = self.b
        names = ['rax', 'rcx', 'rdx', 'rbx', 'rsp', 'rbp', 'rsi', 'rdi', 'r8', 'r9', 'r10', 'r11', 'r12', 'r13', 'r14', 'r15']
        regs = {n: u64(b, rva + 0x78 + 8 * i) for i, n in enumerate(names)}
        regs['rip'] = u64(b, rva + 0xF8)
        return regs

    def threads(self):
        out = {}
        for size, loc in self.streams.get(3, []):
            n = u32(self.b, loc)
            for i in range(n):
                o = loc + 4 + i * 48
                tid = u32(self.b, o)
                st_start, st_size, st_rva = struct.unpack_from('<QII', self.b, o + 24)
                ctx_size, ctx_rva = u32(self.b, o + 40), u32(self.b, o + 44)
                out[tid] = (st_start, st_size, st_rva, ctx_rva)
        return out

    def thread_names(self):
        out = {}
        for size, loc in self.streams.get(24, []):     # ThreadNamesStream
            n = u32(self.b, loc)
            for i in range(n):
                tid, rva = struct.unpack_from('<IQ', self.b, loc + 4 + i * 12)
                out[tid] = self._str(rva)
        return out


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print(__doc__)
        return
    d = Dump(sys.argv[1])
    scan = 160
    if '--scan' in sys.argv:
        scan = int(sys.argv[sys.argv.index('--scan') + 1])
    if '--map' in sys.argv:
        path = sys.argv[sys.argv.index('--map') + 1]
        print('map %s: %d main.dll symbols' % (path, d.load_map(path)))
    ex = d.exception()
    if not ex:
        print('no exception stream in this dump')
        return
    tid, code, addr, params, ctx_rva = ex
    regs = d.context(ctx_rva)
    names = d.thread_names()
    print('exception 0x%08x at %s (0x%x), thread %d %s' % (code, d.where(addr), addr, tid, names.get(tid, '')))
    if code == 0xC0000005 and len(params) >= 2:
        print('  access violation: %s 0x%x' % (['read', 'write', '?', '?', '?', '?', '?', '?', 'execute'][params[0]] if params[0] < 9 else params[0], params[1]))
    for k in ['rip', 'rsp', 'rbp', 'rax', 'rbx', 'rcx', 'rdx', 'rsi', 'rdi', 'r8', 'r9', 'r10', 'r11', 'r12', 'r13', 'r14', 'r15']:
        v = regs[k]
        print('  %-3s %016x %s' % (k, v, d.where(v) if d.mod_of(v) else ''))
    if '--mods' in sys.argv:
        print('modules (base, size, link timestamp, name):')
        for base, sz, name, ts in d.mods:
            print('  %016x %8x %08x %s' % (base, sz, ts, name))
    print('stack scan (values inside a module, from rsp up: return-address candidates, not an unwind):')
    rsp = regs['rsp']
    data = d.read(rsp, scan * 8)
    if data is None:
        th = d.threads().get(tid)
        if th:
            st_start, st_size, st_rva, _ = th
            off = rsp - st_start
            data = d.b[st_rva + max(off, 0): st_rva + st_size]
    if data:
        for i in range(0, min(len(data), scan * 8) - 7, 8):
            v = u64(data, i)
            if d.mod_of(v):
                print('  [rsp+0x%03x] %016x %s' % (i, v, d.where(v)))
    else:
        print('  (stack memory not in the dump)')


if __name__ == '__main__':
    main()
