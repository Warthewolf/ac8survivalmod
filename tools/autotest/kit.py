"""kit.py: puts a staged Survival build into the game for one test run, and takes it out again exactly.

    python -I tools/autotest/kit.py install <stage dir> --suite <name> [--max-s N]
    python -I tools/autotest/kit.py restore
    python -I tools/autotest/kit.py status

<stage dir>: a package_dev.sh stage (build/release/stage_dev_<ver>, holding ue4ss/Mods/AC8SurvivalMode and
ue4ss/Mods/IoStoreLoaderMod/SurvivalMode). install: the user's own Survival folders (Mods/AC8SurvivalMode,
Mods/IoStoreLoaderMod/SurvivalMode) are MOVED aside into the main tree's build/autotest/aside (a rename on the same drive:
never copied over, never deleted), the stage is copied in with a sha256 manifest and a marker in each folder, enabled.txt,
and the self-test overlay (test runs only, never in a build): sv_selftest_keys.lua first in MODULES (records every key
bind: a test "presses" Ctrl+<key> without input), sv_selftest.lua last, selftest.txt (the suite), survival_config.lua
(the suite's CFG overrides: a run with one is never ranked), the INSTALLED main.lua's MODULES patched (the copy only).
restore: Survival's logs copied to the run folder, our two folders removed (only when their marker is ours), the user's
moved back. The user's yes (2026-11-16): her Survival moved aside for each gated run, put back after."""
import argparse
import os
import shutil
import sys
import time
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

MARKER = '.sv_autotest_install'
LUA = os.path.join(C.HERE, 'lua')


def targets():
    m = C.mods_dir()
    return [('AC8SurvivalMode', os.path.join(m, 'AC8SurvivalMode'), ('ue4ss', 'Mods', 'AC8SurvivalMode')),
            ('IoStoreLoaderMod__SurvivalMode', os.path.join(m, 'IoStoreLoaderMod', 'SurvivalMode'),
             ('ue4ss', 'Mods', 'IoStoreLoaderMod', 'SurvivalMode'))]


def state_path():
    return os.path.join(C.state_dir(), 'kit_state.json')


def save_state(st):
    C.write_json(state_path(), st)


def same_drive(a, b):
    return os.path.splitdrive(os.path.abspath(a))[0].lower() == os.path.splitdrive(os.path.abspath(b))[0].lower()


def patch_main(path):
    src = open(path, encoding='utf-8', newline='').read()
    head = 'local MODULES = {'
    tail_re = '    "sv_main",'
    if src.count(head) != 1 or src.count(tail_re) != 1:
        raise SystemExit('kit: the installed main.lua has no single MODULES list to patch (%s)' % path)
    nl = '\r\n' if '\r\n' in src else '\n'
    src = src.replace(head, head + nl + '    "sv_selftest_keys",            -- (tools/autotest/kit.py: test runs only)', 1)
    src = src.replace(tail_re, tail_re + nl + '    "sv_selftest",                 -- (tools/autotest/kit.py: test runs only)', 1)
    open(path, 'w', encoding='utf-8', newline='').write(src)


def manifest(root):
    out = {}
    for d, _, files in os.walk(root):
        for f in files:
            p = os.path.join(d, f)
            out[os.path.relpath(p, root).replace('\\', '/')] = C.sha256(p)
    return out


def load_order_path():
    return os.path.join(C.mods_dir(), 'IoStoreLoaderMod', 'loadorder.txt')


def load_order_on(st):
    """The Mod Loader skips a folder its loadorder.txt (the mod launcher's: "+Name = on, -Name = off") has off: the
    user's had every mod off on 2026-11-16, -SurvivalMode too, and the first run that got to the main menu had Survival's
    tables unloaded ("SurvivalMode_P did not mount"). For the run: "-SurvivalMode" made "+SurvivalMode", the file's
    bytes and times kept in the aside folder and put back exactly by restore (the gate's snapshot checks its mtime)."""
    p = load_order_path()
    if not os.path.isfile(p):
        return
    raw = open(p, 'rb').read()
    lines = raw.split(b'\n')
    hit = [i for i, l in enumerate(lines) if l.strip().lower() == b'-survivalmode']
    if not hit:
        return
    keep = os.path.join(C.state_dir('aside'), 'loadorder.txt')
    shutil.copy2(p, keep)
    stt = os.stat(p)
    st['load_order'] = {'path': p, 'copy': keep, 'atime_ns': stt.st_atime_ns, 'mtime_ns': stt.st_mtime_ns}
    save_state(st)
    for i in hit:
        lines[i] = lines[i].replace(b'-', b'+', 1)
    open(p, 'wb').write(b'\n'.join(lines))
    print('kit: the Mod Loader\'s loadorder.txt: SurvivalMode on for the run (the user\'s copy kept)')


def load_order_back(st):
    lo = st.get('load_order')
    if not lo:
        return 0
    if not os.path.isfile(lo['copy']):
        print('kit: the user\'s loadorder.txt copy is missing (%s): NOT put back (look at it)' % lo['copy'])
        return 1
    shutil.copyfile(lo['copy'], lo['path'])
    os.utime(lo['path'], ns=(lo['atime_ns'], lo['mtime_ns']))
    os.remove(lo['copy'])
    print('kit: the user\'s loadorder.txt put back')
    return 0


LOADER_FILES = (('dlls', 'main.dll'), ('enabled.txt',))


def loader_in(st):
    """((2026-11-22) the user's game had no Mod Loader in it: her IoStoreLoaderMod moved out on 2026-11-21 while she worked
    on another mod, and the first valka run's SurvivalMode_P never mounted ("Survival Mode's tables could not be
    loaded"), so the OpenLevel crashed the game.) With no Mods/IoStoreLoaderMod/dlls/main.dll, the loader in .env's
    AUTOTEST_LOADER (a folder holding dlls/main.dll) is copied in for the run, each file and folder it adds recorded and
    taken out again by restore (loader_out), so the game ends as it was."""
    root = os.path.join(C.mods_dir(), 'IoStoreLoaderMod')
    if os.path.isfile(os.path.join(root, 'dlls', 'main.dll')):
        return
    src = C.env.get('AUTOTEST_LOADER')
    if not (src and os.path.isfile(os.path.join(src, 'dlls', 'main.dll'))):
        raise SystemExit('kit: the game has no Mod Loader (Mods/IoStoreLoaderMod/dlls/main.dll) and .env has no '
                         'AUTOTEST_LOADER (a folder holding dlls/main.dll): Survival\'s containers could never mount')
    added = {'files': [], 'dirs': []}
    for d in (root, os.path.join(root, 'dlls')):
        if not os.path.isdir(d):
            os.makedirs(d)
            added['dirs'].append(d)
    for rel in LOADER_FILES:
        s, t = os.path.join(src, *rel), os.path.join(root, *rel)
        if os.path.exists(t):
            continue
        if os.path.isfile(s):
            shutil.copy2(s, t)
        else:
            open(t, 'w').close()
        added['files'].append({'path': t, 'sha256': C.sha256(t)})
    st['loader'] = added
    save_state(st)
    print('kit: the game had no Mod Loader: %s copied in for the run (%d files, taken out again by restore)' % (
        src, len(added['files'])))


def loader_out(st):
    added = st.get('loader')
    if not added:
        return 0
    bad = 0
    for f in added['files']:
        if not os.path.isfile(f['path']):
            continue
        if C.sha256(f['path']) != f['sha256']:
            print('kit: %s changed during the run: LEFT ALONE (look at it)' % f['path'])
            bad += 1
            continue
        os.remove(f['path'])
    for d in reversed(added['dirs']):
        if os.path.isdir(d) and not os.listdir(d):
            os.rmdir(d)
    print('kit: the Mod Loader copied in for the run taken out' + (' (%d problem(s))' % bad if bad else ''))
    return bad


def cmd_install(a):
    if C.game_running():
        raise SystemExit('kit: the game is running: nothing installed')
    if os.path.exists(state_path()):
        raise SystemExit('kit: an earlier install is still in (build/autotest/kit_state.json): run `kit.py restore` first')
    stage = os.path.abspath(a.stage)
    aside = C.state_dir('aside')
    if os.listdir(aside):
        raise SystemExit('kit: build/autotest/aside is not empty (an earlier run left the user\'s folders there?): '
                         'look at it before anything else')
    token = uuid.uuid4().hex
    st = {'token': token, 'stage': stage, 'suite': a.suite, 'at': time.time(), 'moved': [], 'installed': [],
          'phase': 'checking'}
    plan = []
    for name, tgt, rel in targets():
        src = os.path.join(stage, *rel)
        if not os.path.isdir(src):
            raise SystemExit('kit: the stage has no %s' % '/'.join(rel))
        if os.path.exists(tgt) and not same_drive(tgt, aside):
            raise SystemExit('kit: %s is on another drive than build/autotest: moving it aside would be a copy' % tgt)
        plan.append((name, tgt, src))
    save_state(st)
    loader_in(st)
    for name, tgt, src in plan:                       # the user's folders aside first (each move recorded at once)
        if os.path.exists(tgt):
            if os.path.exists(os.path.join(tgt, MARKER)):
                raise SystemExit('kit: %s is a test install (its marker): run `kit.py restore`' % tgt)
            os.rename(tgt, os.path.join(aside, name))
            st['moved'].append({'name': name, 'target': tgt})
            st['phase'] = 'moved ' + name
            save_state(st)
            print('kit: the user\'s %s moved aside' % name)
    for name, tgt, src in plan:
        st['installed'].append({'name': name, 'target': tgt})
        st['phase'] = 'copying ' + name
        save_state(st)
        os.makedirs(tgt)                              # the marker first: a copy cut short is still ours to remove
        open(os.path.join(tgt, MARKER), 'w').write(token)
        shutil.copytree(src, tgt, dirs_exist_ok=True)
    load_order_on(st)
    sv = plan[0][1]
    scripts = os.path.join(sv, 'Scripts')
    if not os.path.isfile(os.path.join(sv, 'enabled.txt')):
        open(os.path.join(sv, 'enabled.txt'), 'w').close()
    off = os.path.join(sv, 'enabled.off')
    if os.path.exists(off):
        os.remove(off)
    for f in ('sv_selftest_keys.lua', 'sv_selftest.lua'):
        shutil.copy2(os.path.join(LUA, f), os.path.join(scripts, f))
    cfg = os.path.join(LUA, 'config_%s.lua' % a.suite)
    shutil.copy2(cfg if os.path.isfile(cfg) else os.path.join(LUA, 'config_default.lua'),
                 os.path.join(scripts, 'survival_config.lua'))
    with open(os.path.join(scripts, 'selftest.txt'), 'w', encoding='utf-8') as f:
        f.write('suite=%s\nmax_s=%d\nmenu_wait_s=%d\n' % (a.suite, a.max_s, a.menu_wait_s))
        for kv in a.conf or []:                       # (extra self-test settings: plane=floor ...)
            f.write(kv.strip() + '\n')
    patch_main(os.path.join(scripts, 'main.lua'))
    st['manifest'] = {i['name']: manifest(i['target']) for i in st['installed']}
    st['phase'] = 'installed'
    save_state(st)
    ver = '?'
    for line in open(os.path.join(scripts, 'main.lua'), encoding='utf-8'):
        if line.startswith('VERSION = '):
            ver = line.split('"')[1]
            break
    print('kit: installed %s (Survival %s, suite %s)' % (stage, ver, a.suite))
    return 0


def cmd_restore(_):
    st = C.read_json(state_path())
    if not st:
        print('kit: nothing installed')
        return 0
    if C.game_running():
        raise SystemExit('kit: the game is running: nothing restored (close it, then restore)')
    run_dir = os.environ.get('SV_AUTOTEST_RUN') or C.state_dir('runs', 'kit_' + C.now_stamp())
    os.makedirs(run_dir, exist_ok=True)
    bad = 0
    for i in st.get('installed', []):
        tgt = i['target']
        if not os.path.exists(tgt):
            continue
        mk = os.path.join(tgt, MARKER)
        if not (os.path.isfile(mk) and open(mk).read().strip() == st['token']):
            print('kit: %s has no marker of this install: LEFT ALONE (look at it)' % tgt)
            bad += 1
            continue
        if i['name'] == 'AC8SurvivalMode':
            for sub in ('logs', 'config'):
                s = os.path.join(tgt, sub)
                if os.path.isdir(s):
                    shutil.copytree(s, os.path.join(run_dir, 'survival_' + sub), dirs_exist_ok=True)
        before = st.get('manifest', {}).get(i['name'], {})
        changed = [p for p, h in before.items()
                   if os.path.isfile(os.path.join(tgt, p)) and C.sha256(os.path.join(tgt, p)) != h]
        if changed:
            print('kit: %s: %d installed file(s) changed during the run: %s' % (i['name'], len(changed),
                                                                                ', '.join(changed[:8])))
        shutil.rmtree(tgt)
        print('kit: the test %s removed' % i['name'])
    bad += load_order_back(st)
    bad += loader_out(st)
    aside = C.state_dir('aside')
    for m in reversed(st.get('moved', [])):
        src = os.path.join(aside, m['name'])
        if os.path.exists(m['target']):
            print('kit: %s is in the way of the user\'s %s: NOT moved back (look at it)' % (m['target'], m['name']))
            bad += 1
            continue
        os.rename(src, m['target'])
        print('kit: the user\'s %s moved back' % m['name'])
    if bad:
        print('kit: restore incomplete (%d problem(s)); kit_state.json kept' % bad)
        return 2
    os.remove(state_path())
    print('kit: restored')
    return 0


def cmd_status(_):
    st = C.read_json(state_path())
    if not st:
        print('kit: nothing installed')
    else:
        print('kit: %s (suite %s, phase %s, at %s); moved aside: %s' % (
            st['stage'], st['suite'], st['phase'], time.ctime(st['at']), ', '.join(m['name'] for m in st['moved']) or '-'))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog='kit.py')
    sp = ap.add_subparsers(dest='cmd', required=True)
    i = sp.add_parser('install')
    i.add_argument('stage')
    i.add_argument('--suite', default='smoke')
    i.add_argument('--max-s', type=int, default=600)
    i.add_argument('--menu-wait-s', type=int, default=25)
    i.add_argument('--conf', action='append', help='name=value for selftest.txt (plane=floor: shootable, never down)')
    sp.add_parser('restore')
    sp.add_parser('status')
    a = ap.parse_args(argv)
    return {'install': cmd_install, 'restore': cmd_restore, 'status': cmd_status}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
