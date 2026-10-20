# wd_find.py <WD zen package> <name regex> : print location/rotation/extent of world-data descs whose Name matches.
import sys, os, re, struct
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts'))
import uprop
from zen import Zen
z = Zen(sys.argv[1]); c = uprop.Ctx(z.d, z.names); pat = re.compile(sys.argv[2])
main = [e for e in z.exports if e['name'] == z.pkgname.rsplit('/', 1)[1]][0]
v, o = uprop.read_struct(c, z.header_size + main['off'], 'LiveWorldData')
def dec(x):
    if x and x[0] == 'native' and x[1] in ('Vector', 'Rotator'): return tuple(round(a, 1) for a in struct.unpack('<3d', x[2]))
    if x and x[0] == 'name': return x[1]
    if x and x[0] == 'raw' and x[1] == 'Double': return struct.unpack('<d', x[2])[0]
    return None
for idx, lname, z_, arr in v[2]:
    if not arr or arr[0] != 'arr': continue
    for el in arr[1]:
        if el[0] != 'struct': continue
        f = {p[1]: p[3] for p in el[2]}
        nm = f.get('Name')
        if nm and nm[0] == 'name' and pat.search(nm[1]):
            print(lname, nm[1], {k: dec(val) for k, val in f.items() if dec(val) is not None and k != 'Name'})
