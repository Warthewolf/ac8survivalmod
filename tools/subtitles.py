"""subtitles.py : Survival's subtitles file, config/subtitles.ini (every subtitle line in one file a person can edit;
Scripts/sv_config_subs.lua reads it over CFG's own lines at start). The file in the repo is the one every release ships.

  python -I tools/subtitles.py check [file]   the file (default: the repo's) against the game's lists: its mistakes
                                              (exit 1 on any) and the lists it leaves out (they keep CFG's own lines)
  python -I tools/subtitles.py gen [--force]  the repo's file written from CFG's own lines (refused if it's there:
                                              --force overwrites it, and every edit in it)
  python -I tools/subtitles.py merge          the lists CFG has and the repo's file doesn't (a new special's lines)
                                              added at its end, from CFG's own lines
  python -I tools/subtitles.py pull           the installed game's file (.env AC8_DIR, ue4ss/Mods/AC8SurvivalMode/
                                              config/subtitles.ini: the user's or a friend's edits) checked, then copied
                                              over the repo's (the old one kept in build/backup/subtitles/)
  python -I tools/subtitles.py diff           whether the installed file differs from the repo's

Runs tools/checks/subs_tool.lua on build/checks/lua.exe (tools/checks/lua_build.sh makes it).
"""
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
MOD = os.path.join(ROOT, 'mod', 'UE4SS', 'AC8SurvivalMode')
REPO_FILE = os.path.join(MOD, 'config', 'subtitles.ini')
CHECKS = os.path.join(HERE, 'checks')
LUA = os.path.join(ROOT, 'build', 'checks', 'lua.exe')
WORK = os.path.join(ROOT, 'build', 'checks', 'subtitles')


def lua(*args):
    """subs_tool.lua on a release's copy of the parts (tools/strip_test_only.py: no test-only special's lines in the file)"""
    if not os.path.isfile(LUA):
        subprocess.run(['sh', 'lua_build.sh'], cwd=CHECKS, check=True, stdout=subprocess.DEVNULL)
    rel = os.path.join(WORK, 'mod')
    shutil.rmtree(rel, ignore_errors=True)
    shutil.copytree(os.path.join(MOD, 'Scripts'), os.path.join(rel, 'Scripts'))
    os.makedirs(os.path.join(rel, 'config'), exist_ok=True)
    shutil.copy(os.path.join(MOD, 'config', 'survival.default.ini'), os.path.join(rel, 'config'))
    parts = sorted(os.path.join(rel, 'Scripts', n) for n in os.listdir(os.path.join(rel, 'Scripts')) if n.endswith('.lua'))
    subprocess.run([sys.executable, '-X', 'utf8', '-I', os.path.join(HERE, 'strip_test_only.py')] + parts, check=True,
                   stdout=subprocess.DEVNULL)
    os.makedirs(os.path.join(WORK, 'Scripts'), exist_ok=True)
    os.makedirs(os.path.join(WORK, 'config'), exist_ok=True)
    shutil.copy(os.path.join(MOD, 'config', 'survival.default.ini'), os.path.join(WORK, 'config'))
    r = subprocess.run([LUA, 'subs_tool.lua', rel.replace('\\', '/'), WORK.replace('\\', '/')] + list(args), cwd=CHECKS,
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    return r.returncode, r.stdout + r.stderr


def own_text():
    code, out = lua('gen')
    if code != 0:
        raise SystemExit('subtitles: CFG\'s own lines could not be written:\n' + out)
    with open(os.path.join(WORK, 'config', 'subtitles.ini'), 'rb') as f:
        return f.read().decode('utf-8')


def check(path):
    code, out = lua('check', os.path.abspath(path).replace('\\', '/'))
    bad = [l for l in out.splitlines() if l.startswith('bad: ')]
    missing = [l[len('missing: '):] for l in out.splitlines() if l.startswith('missing: ')]
    head = [l for l in out.splitlines() if l.startswith('lists ')]
    print(f'subtitles: {os.path.relpath(path, ROOT) if path.startswith(ROOT) else path}: ' + (head[0] if head else out.strip()))
    for l in bad:
        print('  ' + l)
    if missing:
        print(f'  {len(missing)} lists not in it (they keep the game\'s own lines; `merge` adds them): ' + ', '.join(missing[:8])
              + (' ...' if len(missing) > 8 else ''))
    return code, bad, missing


def blocks(text):
    """{ path: block text } for each [section] of a file: its notes just above it, the header, its lines"""
    out, cur, notes = {}, None, []
    for line in text.replace('\r\n', '\n').split('\n'):
        s = line.strip()
        if not s:
            cur, notes = None, []
        elif s.startswith('[') and s.endswith(']'):
            cur = s[1:-1].strip()
            out[cur] = notes + [line]
            notes = []
        elif s.startswith(';'):
            if cur is None and not s.startswith('; ='):
                notes.append(line)
        elif cur is not None:
            out[cur].append(line)
    return {k: '\r\n'.join(v) for k, v in out.items()}


def installed():
    import env
    return os.path.join(env.need('AC8_DIR', 'the installed game\'s subtitles file'), 'Game', 'Binaries', 'Win64', 'ue4ss',
                        'Mods', 'AC8SurvivalMode', 'config', 'subtitles.ini')


def main(argv):
    cmd = argv[1] if len(argv) > 1 else 'check'
    if cmd == 'check':
        path = argv[2] if len(argv) > 2 else REPO_FILE
        code, _, _ = check(path)
        return 1 if code else 0
    if cmd == 'gen':
        if os.path.exists(REPO_FILE) and '--force' not in argv:
            print(f'subtitles: {REPO_FILE} is there already (its edits would be lost): --force to overwrite it')
            return 1
        text = own_text()
        with open(REPO_FILE, 'wb') as f:
            f.write(text.encode('utf-8'))
        print(f'subtitles: wrote {os.path.relpath(REPO_FILE, ROOT)} from CFG\'s own lines')
        return check(REPO_FILE)[0]
    if cmd == 'merge':
        with open(REPO_FILE, 'rb') as f:
            text = f.read().decode('utf-8')
        own = blocks(own_text())
        have = blocks(text)
        new = [p for p in own if p not in have]
        if not new:
            print('subtitles: nothing to merge: the file has every list')
            return 0
        add = '\r\n; ' + '-' * 116 + f'\r\n; new lists, added by tools/subtitles.py merge ({time.strftime("%Y-%m-%d")})\r\n; ' \
              + '-' * 116 + '\r\n\r\n' + '\r\n\r\n'.join(own[p] for p in new) + '\r\n'
        with open(REPO_FILE, 'wb') as f:
            f.write((text.rstrip('\r\n') + '\r\n' + add).encode('utf-8'))
        print(f'subtitles: {len(new)} lists added: ' + ', '.join(new))
        return check(REPO_FILE)[0]
    if cmd in ('pull', 'diff'):
        src = installed()
        if not os.path.isfile(src):
            print(f'subtitles: no file installed at {src}')
            return 1
        with open(src, 'rb') as f:
            a = f.read()
        with open(REPO_FILE, 'rb') as f:
            b = f.read()
        if a == b:
            print('subtitles: the installed file is the repo\'s')
            return 0
        if cmd == 'diff':
            print('subtitles: the installed file differs from the repo\'s (`pull` takes it)')
            return 2
        code, bad, _ = check(src)
        if code:
            print('subtitles: not pulled: fix those lines first (the game skips them)')
            return 1
        bk = os.path.join(ROOT, 'build', 'backup', 'subtitles')
        os.makedirs(bk, exist_ok=True)
        keep = os.path.join(bk, time.strftime('subtitles_%Y%m%d_%H%M%S.ini'))
        shutil.copy(REPO_FILE, keep)
        shutil.copy(src, REPO_FILE)
        print(f'subtitles: pulled the installed file into the repo (the old one: {os.path.relpath(keep, ROOT)})')
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
