import sys
sys.path.insert(0, sys.argv[0].rsplit('/',1)[0])
from mdmp import Dump, u64
d = Dump(sys.argv[1]); n = int(sys.argv[2])
tid, code, addr, params, ctx = d.exception(); regs = d.context(ctx)
th = d.threads()[tid]; st_start, st_size, st_rva, _ = th
rsp = regs['rsp']; off = rsp - st_start
data = d.b[st_rva + off: st_rva + st_size]
print('thread stack %x..%x, rsp at +%x, %d bytes above' % (st_start, st_start+st_size, off, len(data)))
seen = 0
for i in range(0, len(data) - 7, 8):
    v = u64(data, i); m = d.mod_of(v)
    if m and not m[0].lower().startswith(('atcuf', 'bdhkm', 'antimalware')):
        print('  [rsp+0x%04x] %s+0x%x' % (i, m[0], m[1])); seen += 1
        if seen >= n: break
for a in [regs['rip']] + [int(x, 16) for x in sys.argv[3:]]:
    b = d.read(a - 32, 48)
    print('code at %x: %s' % (a, b.hex() if b else 'not in dump'))
