"""exe.py : helpers for reverse-engineering AceCombat8.exe (or any PE64) from Python.

  from exe import Exe
  x = Exe(path)                 # sections, image base, .pdata function table (cached in build/re/exe_cache.pkl)
  x.wstr_addrs('ULiveUnit')     # VAs of UTF-16 strings equal to the text (whole string)
  x.xrefs({va, ...})            # {target_va: [instruction_va, ...]} for RIP-relative lea/mov/call/jmp in code sections
  x.func(va)                    # (start_va, end_va) of the function holding va, from .pdata
  x.u64(va), x.u32(va), x.read(va, n)
  x.disasm(start_va, end_va)    # llvm-objdump text (Intel) for that range

Command line:  python exe.py <exe> wstr <text>   |   xref <hex va>...   |   func <hex va>   |   dis <hex start> <hex end>
"""
import bisect, os, pickle, re, struct, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OBJDUMP = os.path.join(HERE, '..', 'llvm', 'LLVM', 'bin', 'llvm-objdump.exe')
DEFAULT_EXE = r'E:\SteamLibrary\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64\AceCombat8.exe'
CACHE = os.environ.get("EXE_CACHE") or os.path.join(HERE, "..", "..", "build", "re", "exe_cache.pkl")


class Exe:
    def __init__(self, path=DEFAULT_EXE):
        self.path = path
        self.d = open(path, 'rb').read()
        d = self.d
        pe = struct.unpack_from('<I', d, 0x3c)[0]
        nsec = struct.unpack_from('<H', d, pe + 6)[0]
        optsz = struct.unpack_from('<H', d, pe + 20)[0]
        opt = pe + 24
        self.base = struct.unpack_from('<Q', d, opt + 24)[0]
        dirs = opt + 112
        self.secs = []
        for i in range(nsec):
            o = opt + optsz + 40 * i
            name = d[o:o + 8].rstrip(b'\0').decode('latin1')
            vs, va, rs, ra = struct.unpack_from('<IIII', d, o + 8)
            ch = struct.unpack_from('<I', d, o + 36)[0]
            self.secs.append((name, va, vs, ra, rs, ch))
        prva, psz = struct.unpack_from('<II', d, dirs + 8 * 3)
        key = (os.path.getsize(path), os.path.getmtime(path))
        cache = None
        if os.path.exists(CACHE):
            try:
                cache = pickle.load(open(CACHE, 'rb'))
                if cache.get('key') != key: cache = None
            except Exception:
                cache = None
        if cache is None:
            po = self.off(self.base + prva)
            starts, ends = [], []
            for i in range(psz // 12):
                b, e, u = struct.unpack_from('<III', d, po + 12 * i)
                if b: starts.append(b); ends.append(e)
            order = sorted(range(len(starts)), key=lambda k: starts[k])
            cache = {'key': key, 'fs': [starts[k] for k in order], 'fe': [ends[k] for k in order]}
            os.makedirs(os.path.dirname(CACHE), exist_ok=True)
            pickle.dump(cache, open(CACHE, 'wb'))
        self.fs, self.fe = cache['fs'], cache['fe']

    # addresses ---------------------------------------------------------------------------------
    def off(self, va):
        r = va - self.base
        for name, sva, vs, ra, rs, ch in self.secs:
            if sva <= r < sva + max(vs, rs):
                return r - sva + ra if r - sva < rs else None
        return None

    def va(self, off):
        for name, sva, vs, ra, rs, ch in self.secs:
            if ra <= off < ra + rs:
                return self.base + sva + off - ra
        return None

    def read(self, va, n):
        o = self.off(va)
        return self.d[o:o + n] if o is not None else None

    def u64(self, va): return struct.unpack('<Q', self.read(va, 8))[0]
    def u32(self, va): return struct.unpack('<I', self.read(va, 4))[0]

    def code_sections(self):
        return [s for s in self.secs if s[5] & 0x20000000]

    def section_of(self, va):
        r = va - self.base
        for s in self.secs:
            if s[1] <= r < s[1] + max(s[2], s[4]): return s[0]
        return None

    # strings ------------------------------------------------------------------------------------
    def wstr_addrs(self, text):
        pat = b'\0\0' + text.encode('utf-16-le') + b'\0\0'
        return [self.va(m.start() + 2) for m in re.finditer(re.escape(pat), self.d)]

    def astr_addrs(self, text):
        pat = b'\0' + text.encode() + b'\0'
        return [self.va(m.start() + 1) for m in re.finditer(re.escape(pat), self.d)]

    # code references ----------------------------------------------------------------------------
    _RIP = re.compile(rb'(?:[\x48\x4c][\x8d\x8b\x89\x3b\x39\x85\x03\x2b\x33\x23\x0b\xc7]|\xff[\x15\x25]|\x0f\x10|\x0f\x11)', re.S)

    def xrefs(self, targets, sections=None):
        """RIP-relative references (lea/mov/cmp/... and call/jmp [rip+x]) to any of the target VAs.
        Also direct call/jmp rel32 (e8/e9)."""
        targets = set(targets)
        hits = {t: [] for t in targets}
        d = self.d
        for name, sva, vs, ra, rs, ch in (sections or self.code_sections()):
            seg = d[ra:ra + rs]
            segva = self.base + sva
            # REX.W lea/mov/... reg, [rip+disp32]: opcode bytes then modrm with mod=00 rm=101
            for m in re.finditer(rb'[\x48\x4c][\x8d\x8b\x89\x3b\x39\x85\x03\x2b\x33\x23\x0b\xc7][\x05\x0d\x15\x1d\x25\x2d\x35\x3d]', seg):
                i = m.start()
                if i + 7 > len(seg): continue
                disp = struct.unpack_from('<i', seg, i + 3)[0]
                extra = 4 if seg[i + 1] == 0xc7 else 0
                t = segva + i + 7 + extra + disp
                if t in targets: hits[t].append(segva + i)
            for m in re.finditer(rb'\xff[\x15\x25]', seg):
                i = m.start()
                if i + 6 > len(seg): continue
                t = segva + i + 6 + struct.unpack_from('<i', seg, i + 2)[0]
                if t in targets: hits[t].append(segva + i)
            for m in re.finditer(rb'[\xe8\xe9]', seg):
                i = m.start()
                if i + 5 > len(seg): continue
                t = segva + i + 5 + struct.unpack_from('<i', seg, i + 1)[0]
                if t in targets: hits[t].append(segva + i)
        return hits

    def ptr_refs(self, targets, sections=None):
        """Places in data sections that hold one of the target VAs as a 64-bit pointer (vtables, tables)."""
        targets = set(targets)
        hits = {t: [] for t in targets}
        packed = {struct.pack('<Q', t): t for t in targets}
        for name, sva, vs, ra, rs, ch in (sections or [s for s in self.secs if not s[5] & 0x20000000]):
            seg = self.d[ra:ra + rs]
            for b, t in packed.items():
                for m in re.finditer(re.escape(b), seg):
                    if m.start() % 8 == 0: hits[t].append(self.base + sva + m.start())
        return hits

    # functions ----------------------------------------------------------------------------------
    def func(self, va):
        r = va - self.base
        k = bisect.bisect_right(self.fs, r) - 1
        if k >= 0 and self.fs[k] <= r < self.fe[k]:
            return self.base + self.fs[k], self.base + self.fe[k]
        return None

    def disasm(self, start, end):
        out = subprocess.run([OBJDUMP, '-d', '-M', 'intel', '--no-show-raw-insn',
                              f'--start-address={start:#x}', f'--stop-address={end:#x}', self.path],
                             capture_output=True, text=True).stdout
        lines = [l for l in out.splitlines() if re.match(r'\s*[0-9a-f]+:', l)]
        return '\n'.join(re.sub(r'\s*<[^>]*>', '', l) for l in lines)


if __name__ == '__main__':
    x = Exe(DEFAULT_EXE)
    cmd = sys.argv[1]
    if cmd == 'wstr':
        print([hex(a) for a in x.wstr_addrs(sys.argv[2])])
    elif cmd == 'xref':
        for t, hs in x.xrefs([int(a, 16) for a in sys.argv[2:]]).items():
            print(hex(t), [hex(h) for h in hs])
    elif cmd == 'func':
        f = x.func(int(sys.argv[2], 16)); print(f and (hex(f[0]), hex(f[1])))
    elif cmd == 'dis':
        print(x.disasm(int(sys.argv[2], 16), int(sys.argv[3], 16)))
