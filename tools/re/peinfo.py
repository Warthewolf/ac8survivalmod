# peinfo.py <dll> : sections, imports (dll!name) and exports of a PE64 file.
import struct, sys
d = open(sys.argv[1], 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]; nsec = struct.unpack_from('<H', d, pe + 6)[0]
optsz = struct.unpack_from('<H', d, pe + 20)[0]; opt = pe + 24
base = struct.unpack_from('<Q', d, opt + 24)[0]
dirs = opt + 112
secs = []
for i in range(nsec):
    o = opt + optsz + 40 * i
    name = d[o:o + 8].rstrip(b'\0').decode(); vs, va, rs, ra = struct.unpack_from('<IIII', d, o + 8)
    secs.append((name, va, vs, ra, rs)); print(f'section {name:8} va={va:#x} vsize={vs:#x} raw={ra:#x}')
def off(rva):
    for n, va, vs, ra, rs in secs:
        if va <= rva < va + max(vs, rs): return rva - va + ra
def cstr(rva):
    o = off(rva); return d[o:d.index(b'\0', o)].decode()
print('image base', hex(base))
erva, esz = struct.unpack_from('<II', d, dirs)
if erva:
    o = off(erva); n = struct.unpack_from('<I', d, o + 24)[0]; fn, nm, ordn = struct.unpack_from('<III', d, o + 28)
    for i in range(n):
        print('export', cstr(struct.unpack_from('<I', d, off(nm) + 4 * i)[0]))
irva = struct.unpack_from('<I', d, dirs + 8)[0]; o = off(irva)
while True:
    ilt, _, _, name, iat = struct.unpack_from('<IIIII', d, o)
    if not name: break
    dll = cstr(name); t = off(ilt or iat)
    while True:
        e = struct.unpack_from('<Q', d, t)[0]
        if not e: break
        print(f'import {dll}!' + (f'#{e & 0xffff}' if e >> 63 else cstr((e & 0x7fffffff) + 2)), f'iat={iat:#x}')
        t += 8; iat += 8
    o += 20
