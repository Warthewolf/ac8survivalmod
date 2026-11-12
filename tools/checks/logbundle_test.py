"""logbundle_test.py <exe> <work dir>: checks runtime/logzip.h's zip writer and pruning through logbundle_test.exe."""
import os, subprocess, sys, zipfile, shutil

EXE, WORK = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
fails = []


def check(cond, what):
    print(('ok   ' if cond else 'FAIL ') + what)
    if not cond:
        fails.append(what)


def run(*args):
    # ((2026-11-12) errors='replace': on Windows the exe prints its %ls through the ANSI code page, not UTF-8; the names
    # are checked in the zip itself, never in these lines)
    r = subprocess.run([EXE, *args], capture_output=True, text=True, encoding='utf-8', errors='replace')
    return r.returncode, r.stdout.splitlines()


tree = os.path.join(WORK, 'tree')
shutil.rmtree(tree, ignore_errors=True)
os.makedirs(tree)
files = {
    'AC8SurvivalMode.log': b'12:00:00 hello\r\n' * 200,
    'session.txt': b'start=2026-11-10_12-00-00\nmod=0.74.43\n',
    'empty.log': b'',
    'big.bin': bytes((i * 7 + (i >> 8)) & 0xFF for i in range(3 * 1024 * 1024)),
    'café ログ.log': 'accents and kana éロ\n'.encode('utf-8'),
}
args = []
for name, data in files.items():
    with open(os.path.join(tree, name), 'wb') as f:
        f.write(data)
    args.append(f'{name}={os.path.join(tree, name)}')
args.append('Saved/Logs/x.log=' + os.path.join(tree, 'AC8SurvivalMode.log'))
args.append('Crashes/UECC-1/a.txt=' + os.path.join(tree, 'session.txt'))
args.append('missing.log=' + os.path.join(tree, 'does_not_exist.log'))
# changed between logzip.h's two passes: cut to half (100,000 bytes, two read blocks), rewritten at the same size
shrink = bytes((i * 13 + 5) & 0xFF for i in range(100000))
with open(os.path.join(tree, 'shrink.log'), 'wb') as f:
    f.write(shrink)
with open(os.path.join(tree, 'rewrite.log'), 'wb') as f:
    f.write(b'a' * 5000)
args.append('<shrink.log=' + os.path.join(tree, 'shrink.log'))
args.append('~rewrite.log=' + os.path.join(tree, 'rewrite.log'))
args.append('@bundle.txt=listing é of the bundle')

out = os.path.join(WORK, 'out.zip')
rc, lines = run('zip', out, *args)
check(rc == 0 and lines and lines[-1] == 'end 1', 'the exe wrote the zip (' + (lines[-1] if lines else '?') + ')')
check(any(l.startswith('skip missing.log 1') for l in lines), 'the missing file was skipped (LZ_LOCKED)')
check('skip shrink.log 5' in lines and 'skip rewrite.log 5' in lines, 'the two changed files are reported LZ_CHANGED')

with zipfile.ZipFile(out) as z:
    check(z.testzip() is None, 'zipfile.testzip() finds no bad entry')
    names = z.namelist()
    want = list(files) + ['Saved/Logs/x.log', 'Crashes/UECC-1/a.txt', 'shrink.log', 'rewrite.log', 'bundle.txt']
    check(names == want, f'entry names and order: {names}')
    for name, data in files.items():
        check(z.read(name) == data, f'contents equal: {name} ({len(data)} bytes)')
    check(z.read('Saved/Logs/x.log') == files['AC8SurvivalMode.log'], 'contents equal: Saved/Logs/x.log')
    check(z.read('bundle.txt').decode('utf-8') == 'listing é of the bundle', 'the in-memory entry')
    info = z.getinfo('café ログ.log')
    check(bool(info.flag_bits & 0x800), 'the non-ASCII name carries the UTF-8 flag')
    check(all(i.compress_type == zipfile.ZIP_STORED for i in z.infolist()), 'every entry is stored')
    check(z.getinfo('big.bin').file_size == 3 * 1024 * 1024, 'the 3 MB file has its size')
    check(z.read('shrink.log') == shrink[:50000] + bytes(50000), 'a file cut between the passes: what was read + zeros')
    check(z.read('rewrite.log') == b'X' * 5000, 'a file rewritten between the passes: what was read')
    raw = open(out, 'rb').read()
    check(all(raw[i.header_offset + 14:i.header_offset + 18] == i.CRC.to_bytes(4, 'little') for i in z.infolist()),
          "every local header's CRC equals its central entry's")
    check(z.getinfo('AC8SurvivalMode.log').date_time[0] == 2020 or z.getinfo('AC8SurvivalMode.log').date_time[0] >= 2000, 'a sane DOS date')

# prune
pd = os.path.join(WORK, 'prune')
shutil.rmtree(pd, ignore_errors=True)
os.makedirs(pd)
for d in range(1, 8):
    open(os.path.join(pd, f'AC8Survival_2026-01-0{d}_12-00-00_0.1.{d}.zip'), 'wb').write(b'zip')
open(os.path.join(pd, 'other.zip'), 'wb').write(b'x')
open(os.path.join(pd, 'AC8Survival_2026-01-09_00-00-00_x.zip.tmp'), 'wb').write(b'x')
rc, lines = run('prune', pd, '3')
left = sorted(os.listdir(pd))
newest = [f'AC8Survival_2026-01-0{d}_12-00-00_0.1.{d}.zip' for d in (5, 6, 7)]
check(lines == ['pruned 4'], f'prune reported 4 ({lines})')
check(left == sorted(newest + ['other.zip', 'AC8Survival_2026-01-09_00-00-00_x.zip.tmp']), f'prune kept the newest 3 and left other files: {left}')
rc, lines = run('prune', pd, '3')
check(lines == ['pruned 0'], 'a second prune deletes nothing')

# session stamps (runtime 0.32.33): which names are a session's files, which are zips
S = '2026-11-10_14-02-11'
stamps = {
    f'AC8SurvivalMode_{S}.log': (S, '-'),
    f'AC8SurvivalMode_lua_{S}b.log': (S + 'b', '-'),
    f'AC8SurvivalMode_crumbs_{S}.log': (S, '-'),
    f'session_{S}.txt': (S, '-'),
    f'UE4SS_{S}.log': (S, '-'),
    f'AC8Survival_{S}_0.74.48.zip': ('-', S),
    f'AC8Survival_{S}_0.74.48_2.zip': ('-', S),
    f'AC8Survival_{S}b_0.74.48.zip': ('-', S + 'b'),
    f'AC8Survival_{S}_0.74.48.zip.tmp': ('-', '-'),
    'AC8SurvivalMode.log': ('-', '-'),
    'AC8SurvivalMode_2026-11-10_14-02-1.log': ('-', '-'),
    f'AC8SurvivalMode{S}.log': ('-', '-'),
}
rc, lines = run('stamp', *stamps)
for name, (fs, zs) in stamps.items():
    check(f'{name} file {fs} zip {zs}' in lines, f'stamps of {name}: file {fs}, zip {zs}')

# which sessions are zipped (LzPick)
pk = os.path.join(WORK, 'pick')
shutil.rmtree(pk, ignore_errors=True)
os.makedirs(os.path.join(pk, 'prev'))
for n in ['AC8SurvivalMode_2026-11-01_10-00-00.log', 'session_2026-11-01_10-00-00.txt',      # no zip: picked
          'AC8SurvivalMode_2026-11-02_10-00-00.log', 'AC8Survival_2026-11-02_10-00-00_0.74.48.zip',  # zipped already
          'AC8SurvivalMode_lua_2026-11-03_10-00-00b.log',                                     # picked: the zip below is
          'AC8Survival_2026-11-03_10-00-00_0.74.48.zip',                                      # ... the stamp without b
          'AC8SurvivalMode_2026-11-04_10-00-00.log', 'session_2026-11-04_10-00-00.txt',      # this session
          'other.txt', 'AC8Survival_2026-11-05_10-00-00_x.zip.tmp']:
    open(os.path.join(pk, n), 'wb').write(b'x')
rc, lines = run('pick', pk, '2026-11-04_10-00-00', '10')
check(lines == ['pick 2026-11-01_10-00-00', 'pick 2026-11-03_10-00-00b', 'picked 2'],
      f'pick: the sessions with no zip, oldest first, not this one ({lines})')
rc, lines = run('pick', pk, '2026-11-04_10-00-00', '2')
check(lines == ['pick 2026-11-03_10-00-00b', 'picked 1'],
      f'pick with 2 zips of 2 kept: none older than the oldest zip ({lines})')

print('\n%d failure(s)' % len(fails))
sys.exit(1 if fails else 0)
