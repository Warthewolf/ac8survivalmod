# dump_export.py <zen package> [export name substring] : print unversioned properties of matching exports.
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts'))
import ue
a = ue.ZenAsset(sys.argv[1]); z = a.z
want = sys.argv[2] if len(sys.argv) > 2 else ''
CLS = {0x7323b5204c7b6d01: 'LevelStreamingAlwaysLoaded', 0x5773a6e79ad51c6d: 'ChronicleWorldSettings',
       0x649d3d5e71510e54: 'Level', 0x7b1116829423f7c1: 'World'}
for i, e in enumerate(z.exports):
    if want not in e['name']: continue
    cls = CLS.get(e['cls']) or (sys.argv[3] if len(sys.argv) > 3 else None)
    if not cls: print(i, e['name'], 'class?', hex(e['cls'])); continue
    r = ue.Reader(z.d, a.names, z.header_size + e['off'], None, zen=True)
    sc = ue.U.schema(cls); vals = {}
    try:
        for p, zero in r.header():
            nm, t = sc[p]
            vals[nm] = 'ZERO' if zero else ue.read_value(r, t)
    except Exception as ex: vals['_err'] = str(ex)
    print(i, e['name'], cls, vals)
