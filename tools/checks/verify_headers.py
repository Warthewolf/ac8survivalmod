# verify_headers.py <Content dir> <container_header.bin>
# For every package zenw can parse: does it round-trip, and does its import list match the container header?
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts'))
from zenw import ZenPkg; from cityhash import package_id; import chdr
S, HB = sys.argv[1], sys.argv[2]
H = chdr.CHdr(open(HB, 'rb').read())
ok = bad = fail = 0
for root, _, fs in os.walk(S):
    for f in fs:
        if not f.endswith(('.uasset', '.umap')): continue
        p = os.path.join(root, f); g = '/Game/' + os.path.relpath(p, S).replace(os.sep, '/').rsplit('.', 1)[0]
        try: z = ZenPkg(p)
        except Exception: fail += 1; continue
        k = H.ids.index(package_id(g)); same = H.imports[k] == [package_id(x) for x in z.imp_pkgs]
        rt = z.write() == z.raw
        if same and rt: ok += 1
        else: bad += 1; print('MISMATCH', g, 'imports_match', same, 'roundtrip', rt)
print('ok', ok, 'bad', bad, 'unparseable', fail, 'header roundtrip', H.write() == H._orig)
