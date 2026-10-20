# imp_pkgs.py <zen package> : list imported package names and import map (tolerates wide names).
import sys, os, struct
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts'))
from zen import Zen
z = Zen(sys.argv[1]); d = z.d
ipn = struct.unpack_from('<i', d, 0x30)[0]
n, nb = struct.unpack_from('<II', d, ipn)
o = ipn + 16 + 8 * n; lens = [struct.unpack_from('>H', d, o + 2 * i)[0] for i in range(n)]; o += 2 * n
pk = []
for L in lens: pk.append(d[o:o + L].decode()); o += L
nums = [struct.unpack_from('<I', d, o + 4 * i)[0] for i in range(n)]
for i, p in enumerate(pk): print('pkg', i, p, nums[i])
for i, x in enumerate(z.imports):
    if x >> 62 == 2: print('imp', i, 'pkg', (x >> 32) & 0x3fffffff, 'hash#', x & 0xffffffff, hex(z.imp_hashes[x & 0xffffffff]))
