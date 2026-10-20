# fn.py <dll> <disasm.txt> <rva> [<rva>...] : print the whole function (from .pdata) holding each RVA,
# with RIP-relative targets annotated (strings, IAT imports, .data globals).
import re, struct, sys
d = open(sys.argv[1], 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]; nsec = struct.unpack_from('<H', d, pe + 6)[0]
optsz = struct.unpack_from('<H', d, pe + 20)[0]; opt = pe + 24
base = struct.unpack_from('<Q', d, opt + 24)[0]; dirs = opt + 112
secs = []
for i in range(nsec):
    o = opt + optsz + 40 * i
    secs.append((d[o:o + 8].rstrip(b'\0').decode(),) + struct.unpack_from('<IIII', d, o + 8))
def off(r):
    for n, vs, va, rs, ra in secs:
        if va <= r < va + max(vs, rs): return r - va + ra
def cstr(r):
    o = off(r); return d[o:d.index(b'\0', o)].decode('latin1')
# imports
imp = {}
irva = struct.unpack_from('<I', d, dirs + 8)[0]; o = off(irva)
while True:
    ilt, _, _, name, iat = struct.unpack_from('<IIIII', d, o)
    if not name: break
    t = off(ilt or iat)
    while True:
        e = struct.unpack_from('<Q', d, t)[0]
        if not e: break
        imp[iat] = cstr((e & 0x7fffffff) + 2) if not e >> 63 else f'#{e & 0xffff}'
        t += 8; iat += 8
    o += 20
# strings
strs = {}
for m in re.finditer(rb'[\x20-\x7e]{4,}\x00', d):
    strs.setdefault(m.start(), m.group()[:-1].decode())
for m in re.finditer(rb'(?:[\x20-\x7e]\x00){3,}\x00\x00', d):
    strs[m.start()] = 'W:' + m.group()[:-2].decode('utf-16-le')
def rva2off(r): return off(r)
# pdata
prva, psz = struct.unpack_from('<II', d, dirs + 8 * 3)
funcs = []
po = off(prva)
for i in range(psz // 12):
    b, e, u = struct.unpack_from('<III', d, po + 12 * i)
    if b: funcs.append((b, e))
lines = open(sys.argv[2]).read().splitlines()
addr = {}
for i, l in enumerate(lines):
    m = re.match(r'\s*([0-9a-f]+):', l)
    if m: addr[int(m.group(1), 16) - base] = i
def note(l):
    m = re.search(r'0x([0-9a-f]{9,})', l)
    if not m: return l
    r = int(m.group(1), 16) - base
    o = off(r)
    if r in imp: return l + '    ; ' + imp[r]
    if o is not None and o in strs: return l + '    ; ' + repr(strs[o][:100])
    return l
for a in sys.argv[3:]:
    r = int(a, 16)
    f = [x for x in funcs if x[0] <= r < x[1]]
    if not f: print('no function for', a); continue
    b, e = f[0]
    print(f'==== function {b:#x}-{e:#x} (holds {a})')
    i = addr.get(b)
    while i is not None and i < len(lines):
        m = re.match(r'\s*([0-9a-f]+):', lines[i])
        if m and int(m.group(1), 16) - base >= e: break
        print(note(lines[i])); i += 1
