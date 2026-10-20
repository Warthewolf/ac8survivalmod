# sigfind.py <exe> <hex bytes, ?? = wildcard> [<context bytes>] : RVAs of every match in the exe's sections.
import re, struct, sys
d = open(sys.argv[1], 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]; nsec = struct.unpack_from('<H', d, pe + 6)[0]
optsz = struct.unpack_from('<H', d, pe + 20)[0]; opt = pe + 24
secs = []
for i in range(nsec):
    o = opt + optsz + 40 * i
    secs.append((d[o:o + 8].rstrip(b'\0').decode(),) + struct.unpack_from('<IIII', d, o + 8))
def rva(off):
    for n, vs, va, rs, ra in secs:
        if ra <= off < ra + rs: return va + off - ra, n
pat = b''.join(b'.' if t == '??' else re.escape(bytes([int(t, 16)])) for t in sys.argv[2].split())
ctx = int(sys.argv[3]) if len(sys.argv) > 3 else 0
for m in re.finditer(pat, d, re.S):
    r = rva(m.start()); print(hex(r[0]), r[1], d[m.start():m.end() + ctx].hex(' '))
