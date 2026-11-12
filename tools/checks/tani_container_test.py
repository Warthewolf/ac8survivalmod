"""tani_container_test.py : tools/tani_container.py (THE TANACORN's container against what a TANI=1 world data needs from it;
the weapons reviews of 2026-11-12) on made-up IoStore containers, and on the real one when it's there.

    python -X utf8 -I tools/checks/tani_container_test.py            the checks (tani_container_test.sh)
    python -X utf8 -I tools/checks/tani_container_test.py --make <dir> <marker>
                                      a made-up container of THE TANACORN's real package names in <dir> and the marker a
                                      TANI=1 build writes for it (tools/checks/zip_leak_test.sh's TESTER=1 TANI=1 zips)

The made-up containers are what tools/scripts/utoc.py reads (header, chunk ids, offsets, blocks, metas; no directory
index) with one zen package a blueprint: a summary, its export map (public export hashes) and its imported package names,
versioned (as every blueprint we cook: hard rule 42) or not. No game, UE or cook needed: Linux and cloud sessions too.
"""
import os, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path[:0] = [TOOLS, os.path.join(TOOLS, 'scripts')]
import tani_container as tc                               # noqa: E402
from zenpkg import NameBatch, export_hash, name_hash, package_id   # noqa: E402
import survival_events as se                              # noqa: E402

CBS = 0x10000


def make_package(hashes, imports, versioned=True, payload=200):
    """a zen package: its summary, (versioned: a stand-in versioning block), an export map of these public hashes and these
    imported package names"""
    pre = 24 if versioned else 0
    ih = 0x34 + pre
    ex = ih
    exports = b''.join(b'\0' * 56 + struct.pack('<Q', h) + b'\0' * 8 for h in hashes)
    bu = ex + len(exports)
    nb = NameBatch(list(imports), [struct.pack('<Q', name_hash(n)) for n in imports], b'\0\0\x64\xc1\0\0\0\0').write()
    ipn = bu
    end = ipn + len(nb) + 4 * len(imports)
    head = struct.pack('<IIIIIIiiiiiii', 1 if versioned else 0, end, 0, 0, 0, end, ih, ih, ex, bu, bu, bu, ipn)
    body = head + b'\0' * pre + exports + nb + b''.join(struct.pack('<I', 0) for _ in imports)
    assert len(body) == end
    return body + bytes((i * 7) & 0xFF for i in range(payload))


def make_container(utoc, packages, compressed=False):
    """an IoStore container (.utoc + .ucas) of these packages {path: bytes}, each chunk on its own blocks"""
    ids, offlen, blocks, ucas, virt = [], [], [], bytearray(), 0
    for path, data in packages.items():
        ids.append(struct.pack('<Q', package_id(path)) + b'\0\0\0' + bytes([tc.CHUNK_EXPORT_BUNDLE]))
        offlen.append(virt.to_bytes(5, 'big') + len(data).to_bytes(5, 'big'))
        for s in range(0, len(data), CBS):
            blk = data[s:s + CBS]
            blocks.append(len(ucas).to_bytes(5, 'little') + len(blk).to_bytes(3, 'little') + len(blk).to_bytes(3, 'little')
                          + bytes([1 if compressed else 0]))
            ucas += blk
        virt += -(-len(data) // CBS) * CBS
    cms = [b'Oodle'.ljust(32, b'\0')] if compressed else []
    n = len(ids)
    hdr = b'-==--==--==--==-' + struct.pack('<BBHIIIIIIIII', 6, 0, 0, 144, n, len(blocks), 12, len(cms), 32, CBS, 0, 1)
    hdr += struct.pack('<Q', 0) + b'\0' * 16 + b'\0' * 4 + struct.pack('<I', 0) + struct.pack('<Q', (1 << 64) - 1) + struct.pack('<I', 0)
    hdr = hdr.ljust(144, b'\0')
    toc = hdr + b''.join(ids) + b''.join(offlen) + b''.join(blocks) + b''.join(cms) + b'\0' * (33 * n)
    with open(utoc, 'wb') as f:
        f.write(toc)
    with open(tc.ucas_of(utoc), 'wb') as f:
        f.write(ucas)


def tani_packages(drop=(), wrong_class=(), hull_skips=(), versioned=True):
    """THE TANACORN's blueprints as a TANI=1 world data needs them: each live part's (its class and its default object
    exported), the live hull's (its class, every part's blueprint imported); drop / wrong_class / hull_skips spoil some"""
    parts = {p['bp']: p['bp_class'] for p in se.TANI_LIVE}
    out = {}
    for bp, cls in sorted(parts.items()):
        if bp in drop:
            continue
        c = cls.replace('_C', 'X_C') if bp in wrong_class else cls
        out[bp] = make_package([export_hash(c), export_hash('Default__' + c)], [bp.rsplit('/', 1)[0] + '/Model/SK_' + c],
                               versioned=versioned)
    if se.TANI_HULL_LIVE_BP not in drop:
        out[se.TANI_HULL_LIVE_BP] = make_package([export_hash(se.TANI_HULL_LIVE_BP_CLASS)],
                                                 [p for p in sorted(parts) if p not in hull_skips], versioned=versioned)
    return out


def needs():
    """what check_tanicorn_build asks of the container (each part's class import, the hull's class; the hull's imports)"""
    need = sorted({(p['bp'], export_hash(p['bp_class'])) for p in se.TANI_LIVE}
                  | {(se.TANI_HULL_LIVE_BP, export_hash(se.TANI_HULL_LIVE_BP_CLASS))})
    return need, [(se.TANI_HULL_LIVE_BP, sorted({p['bp'] for p in se.TANI_LIVE}))]


def write_marker(path, utoc):
    need, hulls = needs()
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('THE TANACORN: a made-up TANI=1 build (tools/checks/tani_container_test.py)\n'
                + ''.join(f'{p}\n' for p in sorted({p for p, _ in need}))
                + ''.join(tc.marker_lines(tc.digest(utoc), need, hulls)))


fails = []


def check(cond, what):
    print(('  ok   ' if cond else '  FAIL ') + what)
    if not cond:
        fails.append(what)


def has(probs, text):
    return any(text in p for p in probs)


def cli(*args):
    r = subprocess.run([sys.executable, '-X', 'utf8', '-I', os.path.join(TOOLS, 'tani_container.py'), *args],
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    return r.returncode, r.stdout


def main():
    need, hulls = needs()
    print(f'tani_container: {len(need)} classes, {len(hulls[0][1])} hull imports (survival_events.TANI_LIVE)')
    with tempfile.TemporaryDirectory() as T:
        u = os.path.join(T, tc.NAME + '.utoc')
        mk = os.path.join(T, 'tani_wd.txt')
        print('a container that serves the world data')
        for versioned in (True, False):
            make_container(u, tani_packages(versioned=versioned))
            check(tc.check(u, need, hulls) == [], f'every class and the hull\'s imports found ({"versioned" if versioned else "unversioned"} packages)')
        write_marker(mk, u)
        check(tc.verify(u, mk) == [], 'verify: the container the marker names')
        rc, out = cli('verify', u, mk)
        check(rc == 0 and 'is the container the build checked' in out, f'the CLI passes it ({out.strip()[:90]})')
        sha, ex, hu = tc.parse_marker(open(mk, encoding='utf-8').read())
        check(sha == tc.digest(u) and ex == need and hu == hulls, 'the marker reads back as written')

        print('what must stop a build or a package')
        vls = sorted({p['bp'] for p in se.TANI_LIVE if 'VLS' in p['bp']})
        make_container(u, tani_packages(drop=vls))                       # (the 2026-11-11 container: no VLS blocks)
        p = tc.check(u, need, hulls)
        check(len(p) == len(vls) and all(has(p, v + ': not in the container') for v in vls),
              f'the {len(vls)} VLS blueprints missing: each named once ({len(p)} problems)')
        make_container(u, tani_packages(drop=[se.TANI_HULL_LIVE_BP]))
        p = tc.check(u, need, hulls)
        check(p == [se.TANI_HULL_LIVE_BP + ': not in the container'], f'no BP_SV_Tani_HULLLIVE: said once ({p})')
        t5 = [x['bp'] for x in se.TANI_LIVE if x['bp'].endswith('BP_SV_Tani_T5')][0]
        make_container(u, tani_packages(wrong_class=[t5]))
        p = tc.check(u, need, hulls)
        check(len(p) == 1 and has(p, t5 + ': no export of hash'), f'the T5 cooked under another class name ({p})')
        make_container(u, tani_packages(hull_skips=vls))                 # (a new spec beside an old cook)
        p = tc.check(u, need, hulls)
        check(len(p) == 1 and has(p, 'BP_SV_Tani_HULLLIVE imports none of BP_SV_Tani_VLSD'),
              f'an old hull without the VLS children ({p[0][:100] if p else p})')
        make_container(u, tani_packages(), compressed=True)
        p = tc.check(u, need, hulls)
        check(p and all('compressed' in x for x in p), f'a compressed container is a problem, not a pass ({len(p)})')
        os.remove(tc.ucas_of(u))
        check(has(tc.check(u, need, hulls), 'no ') , 'no .ucas beside the .utoc')
        open(u, 'wb').write(b'-==--==--==--==-' + b'\0' * 20)
        open(tc.ucas_of(u), 'wb').write(b'')
        check(has(tc.check(u, need, hulls), 'unreadable'), 'a cut .utoc: unreadable')
        check(has(tc.check(os.path.join(T, 'nope.utoc'), need, hulls), 'no container'), 'no container at all')

        print('the marker: the container the build checked, and no other')
        make_container(u, tani_packages())
        write_marker(mk, u)
        make_container(u, {**tani_packages(), '/Game/Mods/SurvivalMode/Tanicorn/BP_SV_Tani_EXTRA': make_package([1], [])})
        p = tc.verify(u, mk)
        check(len(p) == 1 and 'is not the container this build checked' in p[0], f'a container rebuilt since: refused ({p})')
        rc, out = cli('verify', u, mk)
        check(rc == 1 and 'REFUSED' in out, 'the CLI refuses it (exit 1)')
        old = ('THE TANACORN: this build\'s world data imports the Tanicorn container (TANI=1; tools/build_survival.py '
               'check_tanicorn_build).\n' + ''.join(f'{x}\n' for x in sorted({p for p, _ in need})))
        open(mk, 'w', encoding='utf-8').write(old)                       # (0.74.65's marker: package lines only)
        p = tc.verify(u, mk)
        check(len(p) == 1 and 'names no checked container' in p[0], 'a marker from before the check (0.74.65\'s): refused')
        check(has(tc.verify(u, os.path.join(T, 'none.txt')), 'no marker'), 'no marker: refused')
        rc, out = cli('default')
        check(rc == 0 and out.strip().replace('\\', '/').endswith('build/tanicorn/out/' + tc.NAME + '.utoc'),
              f'default: the main tree\'s build/tanicorn/out ({out.strip()})')

    real = tc.default_path()
    print('the real container (' + real + ')')
    if not os.path.exists(real):
        print('  skip: not built here (sh tools/tanicorn/build.sh)')
    else:
        p = tc.check(real, need, hulls)
        check(not any('unreadable' in x for x in p), 'every package read (versioned, uncompressed)')
        print('  ' + ('it serves a TANI=1 world data' if not p else
                      'note: ' + '; '.join(p)[:300] + ' (not a test failure: run sh tools/tanicorn/build.sh)'))
    print('tani_container_test: ' + ('all passed' if not fails else f'{len(fails)} FAILED'))
    return 1 if fails else 0


if __name__ == '__main__':
    if sys.argv[1:2] == ['--make'] and len(sys.argv) == 4:
        d, m = sys.argv[2], sys.argv[3]
        os.makedirs(d, exist_ok=True)
        make_container(os.path.join(d, tc.NAME + '.utoc'), tani_packages())
        write_marker(m, os.path.join(d, tc.NAME + '.utoc'))
        print(f'made a TANI=1 container in {d} and its marker {m}')
        sys.exit(0)
    sys.exit(main())
