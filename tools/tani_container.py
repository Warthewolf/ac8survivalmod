"""tani_container.py : THE TANACORN's container (tools/tanicorn/build.sh's SurvivalMode_Tani_P) checked against what a TANI=1
world data needs from it. Both weapons reviews of 2026-11-12 found that nothing checked it: a world data importing
blueprints the container lacks must never be packaged (AGENTS.md, THE TANICORN), and build/install had once held a
2026-11-11 container (no HULLLIVE, no VLS blocks) beside a world data importing 13 of its packages.

    python -I tools/tani_container.py default                       the container tools/build_all.sh stages with TANI=1
    python -I tools/tani_container.py verify <utoc> <tani_wd.txt>   a staged container against the build's marker

tools/build_survival.py check_tanicorn_build (TANI=1) checks the container build_all.sh is about to stage (default_path)
and writes what it checked into build/out/tani_wd.txt (marker_lines): the container's sha256 (.utoc then .ucas), every class
the world data imports from it (its package and public export hash), BP_SV_Tani_HULLLIVE's class (the model row's
BlueprintClass, Lua's Ctrl+L class_path), and the live parts' blueprints the hull's cooked package must import (its child
actor templates: a spec newer than the cook gives a hull without them). tools/build_all.sh (the copy it staged),
tools/package_dev.sh TANI=1 and tools/package_release.sh TESTER=1 TANI=1 verify the container they ship against it: the
same bytes and the same needs, or they stop.

Reads uncompressed containers only (build.sh's retoc to-zen writes none compressed; a compressed block is a problem, not a
pass). A package's export hashes and imported packages come from its zen summary's offsets, which are absolute, so a
versioned package (hard rule 42: every blueprint we cook) reads as well as an unversioned one.
tools/checks/tani_container_test.sh tests it on made-up containers (make_container) and on the real one when it's there.
"""
import hashlib, os, struct, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
for _p in (HERE, os.path.join(HERE, 'scripts')):
    if _p not in sys.path:
        sys.path.insert(0, _p)
from utoc import Utoc                                   # noqa: E402  (tools/scripts/utoc.py)
from zenpkg import NameBatch, package_id                # noqa: E402

NAME = 'SurvivalMode_Tani_P'
CHUNK_EXPORT_BUNDLE = 1        # EIoChunkType::ExportBundleData: a package's header and its exports
EXPORT_ENTRY = 72              # FExportMapEntry (UE 5.4); its PublicExportHash at +56
REBUILD = 'run sh tools/tanicorn/build.sh to the end, then ZFA=1 TANI=1 sh tools/build_all.sh'


def default_path():
    """The container tools/build_all.sh stages with TANI=1: the main tree's build/tanicorn/out (where tools/tanicorn/build.sh
    writes it from any worktree), else this checkout's (build_all.sh's TA, the same rule)."""
    try:
        common = subprocess.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=HERE,
                                capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        common = ''
    root = os.path.dirname(common) if common else os.path.dirname(HERE)
    return os.path.normpath(os.path.join(root, 'build', 'tanicorn', 'out', NAME + '.utoc'))


def ucas_of(utoc):
    return os.path.splitext(utoc)[0] + '.ucas'


def digest(utoc):
    """sha256 of the container's .utoc, then its .ucas"""
    h = hashlib.sha256()
    for p in (utoc, ucas_of(utoc)):
        with open(p, 'rb') as f:
            for b in iter(lambda: f.read(1 << 20), b''):
                h.update(b)
    return h.hexdigest()


class Container:
    """An IoStore container's packages, read by package path (their export bundle chunks), uncompressed only."""

    def __init__(self, utoc):
        self.path, self.ucas = utoc, ucas_of(utoc)
        self.toc = t = Utoc(utoc)
        if t.partcount != 1:
            raise ValueError(f'{utoc}: {t.partcount} partitions (one .ucas only)')
        self.by_id = {}
        for k, cid in enumerate(t.ids):
            if cid[11] == CHUNK_EXPORT_BUNDLE:
                self.by_id[struct.unpack_from('<Q', cid, 0)[0]] = k

    def read(self, pkg):
        """the package's bytes, None when the container hasn't it"""
        k = self.by_id.get(package_id(pkg))
        if k is None:
            return None
        t = self.toc
        off, ln = t.offlen[k]
        if ln <= 0:
            raise ValueError(f'{pkg}: an empty chunk')
        a, b = off // t.cbs, (off + ln - 1) // t.cbs
        if b >= len(t.blocks):
            raise ValueError(f'{pkg}: its chunk runs past the container\'s blocks')
        out = bytearray()
        with open(self.ucas, 'rb') as f:
            for i in range(a, b + 1):
                bo, _cs, us, m = t.blocks[i]
                if m != 0:
                    raise ValueError(f'{pkg}: block {i} compressed ({t.cms}): tani_container.py reads uncompressed '
                                     f'containers only (tools/tanicorn/build.sh writes none compressed)')
                f.seek(bo)
                blk = f.read(us)
                if len(blk) != us:
                    raise ValueError(f'{pkg}: block {i} cut short in {self.ucas}')
                out += blk
        s = off - a * t.cbs
        return bytes(out[s:s + ln])


def package_info(d):
    """(its public export hashes, the packages it imports) of a zen package: UE 5.4's FZenPackageSummary, whose offsets are
    absolute (a versioned package's versioning info and names only push them on)"""
    if len(d) < 0x34:
        raise ValueError('shorter than a zen package summary')
    (_hasver, hsize, _ni, _nn, _fl, _ch, ih, im, ex, bu, dh, de, ipn) = struct.unpack_from('<IIIIIIiiiiiii', d, 0)
    if not (0x34 <= ih <= im <= ex <= bu <= dh <= de <= ipn < hsize <= len(d)) or (bu - ex) % EXPORT_ENTRY:
        raise ValueError('not a zen package summary (its offsets are out of order)')
    hashes = {struct.unpack_from('<Q', d, x + 56)[0] for x in range(ex, bu, EXPORT_ENTRY)}
    hashes.discard(0)                                    # (exports nobody can import)
    return hashes, NameBatch.read(d, ipn)[0].names


def check(utoc, exports, hull_imports=()):
    """The problems (strings; none: the container serves the world data). exports: [(package, public export hash)], each a
    package of the container with an export of that hash; hull_imports: [(package, [packages it must import])]."""
    if not os.path.exists(utoc):
        return [f'no container {utoc}']
    if not os.path.exists(ucas_of(utoc)):
        return [f'no {ucas_of(utoc)} beside {utoc}']
    try:
        c = Container(utoc)
    except Exception as e:                               # (a broken .utoc is a problem to report, never a pass)
        return [f'{utoc} unreadable: {e}']
    probs, info = [], {}

    def look(pkg):
        if pkg not in info:
            try:
                d = c.read(pkg)
                info[pkg] = ('missing', None) if d is None else ('ok', package_info(d))
            except Exception as e:
                info[pkg] = ('bad', str(e))
        return info[pkg]

    said = set()

    def gone(pkg, kind, why):
        if pkg not in said:
            said.add(pkg)
            probs.append(f'{pkg}: not in the container' if kind == 'missing' else f'{pkg}: unreadable: {why}')

    for pkg, h in exports:
        kind, v = look(pkg)
        if kind != 'ok':
            gone(pkg, kind, v)
        elif h not in v[0]:
            probs.append(f'{pkg}: no export of hash {h:016x} (the class the world data imports: cooked under another name?)')
    for pkg, need in hull_imports:
        kind, v = look(pkg)
        if kind != 'ok':
            gone(pkg, kind, v)
            continue
        miss = [n for n in need if n not in v[1]]
        if miss:
            probs.append(f'{pkg} imports none of {", ".join(m.rsplit("/", 1)[-1] for m in miss)} (its child actors: a '
                         f'spec newer than the cook?)')
    return probs


def marker_lines(sha, exports, hull_imports):
    """What check_tanicorn_build checked, for the marker: `container sha256 <hex>`, `export <package> <hash>` a class,
    `imports <package> <package>...` a hull"""
    out = [f'container sha256 {sha}\n']
    out += [f'export {p} {h:016x}\n' for p, h in exports]
    out += [f'imports {p} {" ".join(need)}\n' for p, need in hull_imports]
    return out


def parse_marker(text):
    """(sha256 or None, exports, hull_imports) from a marker's text (marker_lines'; every other line is the build's notes)"""
    sha, exports, hulls = None, [], []
    for line in text.splitlines():
        w = line.split()
        if len(w) == 3 and w[:2] == ['container', 'sha256']:
            sha = w[2].lower()
        elif len(w) == 3 and w[0] == 'export':
            exports.append((w[1], int(w[2], 16)))
        elif len(w) >= 3 and w[0] == 'imports':
            hulls.append((w[1], w[2:]))
    return sha, exports, hulls


def verify(utoc, marker):
    """The problems of a staged container against a build's marker (none: it's the container the build checked, and it
    serves the world data)"""
    try:
        text = open(marker, encoding='utf-8').read()
    except OSError as e:
        return [f'no marker {marker} ({e})']
    sha, exports, hulls = parse_marker(text)
    if not sha or not exports:
        return [f'{marker} names no checked container (a build from before tools/tani_container.py): rerun ZFA=1 TANI=1 '
                f'sh tools/build_all.sh']
    probs = check(utoc, exports, hulls)
    if os.path.exists(utoc) and os.path.exists(ucas_of(utoc)):
        got = digest(utoc)
        if got != sha:
            probs.insert(0, f'{utoc} is not the container this build checked (sha256 {got[:12]}..., the build\'s '
                            f'{sha[:12]}...): staged from elsewhere, or rebuilt since: rerun ZFA=1 TANI=1 sh tools/build_all.sh')
    return probs


def main(argv):
    if argv[:1] == ['default'] and len(argv) == 1:
        print(default_path())
        return 0
    if argv[:1] == ['verify'] and len(argv) == 3:
        utoc, marker = argv[1], argv[2]
        probs = verify(utoc, marker)
        if probs:
            print(f'tani_container: REFUSED: {utoc} against {marker}:')
            for p in probs:
                print('  ' + p)
            print(f'  ({REBUILD})')
            return 1
        sha, exports, hulls = parse_marker(open(marker, encoding='utf-8').read())
        hs = ', '.join('%s importing its %d parts' % (p.rsplit('/', 1)[-1], len(n)) for p, n in hulls) or 'no hull'
        print(f'tani_container: {os.path.basename(utoc)} is the container the build checked (sha256 {sha[:12]}...): all '
              f'{len(exports)} classes it needs, and {hs}')
        return 0
    print('usage: tani_container.py default | verify <utoc> <tani_wd.txt>')
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
