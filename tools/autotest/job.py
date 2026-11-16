"""job.py: one Survival self-test run, started BY the gate (never on its own: it asks the gate to launch the game).

    python -I tools/autotest/gate.py run --who <id> --label "<what>" --max-minutes 25 \
        --cleanup "python -I tools/autotest/kit.py restore" -- \
        python -I tools/autotest/job.py --stage build/release/stage_dev_<ver> --suite tanacorn --max-s 900

Order: the game not running; kit.py install (the stage + the self-test, the user's Survival aside); provenance (the
stage's VERSION and each container's sha256, this tool's git HEAD and dirty state) in the run folder; the gate's launch;
then Survival's Lua log (Mods/AC8SurvivalMode/logs/AC8SurvivalMode_lua_<stamp>.log) followed: every `selftest:` line
copied to the verdict, no new line for 120 s = the watchdog (the game closed). On `selftest: RESULT n/m` the game is
closed (taskkill: the fast path must not run into QuitGame) and kit.py restore copies the logs out. verdict.txt in the
run folder; rc 0 all passed, 1 a check failed, 2 no RESULT (watchdog, the game gone, a refused launch)."""
import argparse
import glob
import shutil
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

WATCHDOG_S = 120
PY = [sys.executable, '-I']


def git(*args):
    try:
        return subprocess.run(['git', *args], cwd=C.repo_root(), capture_output=True, text=True,
                              creationflags=C.NO_WINDOW).stdout.strip()
    except OSError:
        return '?'


def provenance(stage, out):
    lines = ['stage %s' % stage]
    main_lua = os.path.join(stage, 'ue4ss', 'Mods', 'AC8SurvivalMode', 'Scripts', 'main.lua')
    for line in open(main_lua, encoding='utf-8'):
        if line.startswith('VERSION = '):
            lines.append('Survival ' + line.split('"')[1])
            break
    for p in sorted(glob.glob(os.path.join(stage, 'ue4ss', 'Mods', 'IoStoreLoaderMod', 'SurvivalMode', '*'))):
        st = os.stat(p)
        lines.append('container %s %d bytes, %s, sha256 %s' % (os.path.basename(p), st.st_size,
                                                               time.ctime(st.st_mtime), C.sha256(p)[:16]))
    dll = os.path.join(stage, 'ue4ss', 'Mods', 'AC8SurvivalMode', 'dlls', 'main.dll')
    if os.path.isfile(dll):
        lines.append('runtime main.dll sha256 %s' % C.sha256(dll)[:16])
    lines.append('autotest tools: git %s (%s)' % (git('rev-parse', '--short', 'HEAD'),
                                                  'dirty' if git('status', '--porcelain', '--', 'tools/autotest') else 'clean'))
    lines.append('path: the fast path (Ctrl+F8 from the main menu, no input), test-only overlay (kit.py)')
    open(out, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
    return lines


def newest_lua_log(after):
    d = os.path.join(C.mods_dir(), 'AC8SurvivalMode', 'logs')
    best = None
    for p in glob.glob(os.path.join(d, 'AC8SurvivalMode_lua_*.log')):
        m = os.path.getmtime(p)
        if os.path.getctime(p) >= after - 5 and (best is None or m > best[0]):
            best = (m, p)
    return best[1] if best else None


SHOTS = {'n': 0}


def shoot(line, note):
    """a `selftest: SHOT <name> ...` line: the game's window captured to the run folder's shots/NN_<name>.png (the
    self-test's own HighResShot files are collected after the run: collect_shots)"""
    import re
    m = re.search(r'selftest: SHOT (\S+)', line)
    if not m:
        return
    SHOTS['n'] += 1
    d = os.path.join(os.environ['SV_AUTOTEST_RUN'], 'shots')
    os.makedirs(d, exist_ok=True)
    out = os.path.join(d, '%02d_%s.png' % (SHOTS['n'], m.group(1)))
    try:
        hw = C.game_window(set(C.pids_of(C.GAME_EXE)))
        size = C.capture_window(hw, out) if hw else None
        note('job: picture %s: %s' % (m.group(1), ('%dx%d %s' % (size[0], size[1], os.path.basename(out))) if size
                                       else 'the window not captured'))
    except Exception as ex:                          # (only a picture: never in the way of the run)
        note('job: picture %s failed: %s' % (m.group(1), ex))


def collect_shots(t_launch, run_dir, note):
    """the game's own screenshots (HighResShot: its Saved/Screenshots) made since the launch, moved to shots/"""
    src = os.path.join(C.saved_dir(), 'Screenshots')
    moved = []
    for d, _, files in os.walk(src):
        for f in files:
            p = os.path.join(d, f)
            if os.path.getmtime(p) >= t_launch - 5:
                os.makedirs(os.path.join(run_dir, 'shots'), exist_ok=True)
                dst = os.path.join(run_dir, 'shots', 'game_' + f)
                shutil.move(p, dst)
                moved.append(f)
    note('job: the game\'s own screenshots: %s' % (', '.join(moved) if moved else 'none (HighResShot made none)'))


def stalled_start():
    """UE4SS.log's last 30 lines all "Still waiting for object construction, N objects" with one N (a line every ~2.3 s:
    over a minute without a new object). The first two gated runs (2026-11-16) sat at 9,474 for minutes."""
    try:
        tail = open(C.ue4ss_log(), encoding='utf-8', errors='replace').read().splitlines()[-30:]
    except OSError:
        return False
    counts = {l.rsplit(',', 1)[-1].strip() for l in tail if 'Still waiting for object construction' in l}
    return len(tail) == 30 and all('Still waiting for object construction' in l for l in tail) and len(counts) == 1


def main(argv):
    ap = argparse.ArgumentParser(prog='job.py')
    ap.add_argument('--stage', required=True)
    ap.add_argument('--suite', default='smoke')
    ap.add_argument('--max-s', type=int, default=600)
    ap.add_argument('--conf', action='append', default=[], help='name=value for the self-test (selftest.txt)')
    a = ap.parse_args(argv)
    who = os.environ.get('SV_AUTOTEST_WHO')
    run_dir = os.environ.get('SV_AUTOTEST_RUN')
    if not (who and run_dir):
        print('job: run me through gate.py run (it sets SV_AUTOTEST_WHO / SV_AUTOTEST_RUN)')
        return 2
    verdict = os.path.join(run_dir, 'verdict.txt')

    def note(line):
        C.log_to(verdict, line)
        print(line, flush=True)
    if C.game_running():
        note('job: the game is running: nothing done')
        return 2
    stage = os.path.abspath(a.stage)
    r = subprocess.run(PY + [os.path.join(C.HERE, 'kit.py'), 'install', stage, '--suite', a.suite, '--max-s', str(a.max_s)] + [x for kv in a.conf for x in ('--conf', kv)],
                       capture_output=True, text=True, creationflags=C.NO_WINDOW)
    note((r.stdout + r.stderr).strip())
    if r.returncode != 0:
        note('job: the install failed: no launch')
        return 2
    for line in provenance(stage, os.path.join(run_dir, 'provenance.txt')):
        note('provenance: ' + line)
    t_launch = time.time()
    r = subprocess.run(PY + [os.path.join(C.HERE, 'gate.py'), 'launch', '--who', who], capture_output=True, text=True,
                       creationflags=C.NO_WINDOW)
    note('launch: ' + (r.stdout + r.stderr).strip())
    rc = 2
    if r.returncode == 0:
        rc = follow(t_launch, a, note)
    if C.game_running():
        C.kill(C.GAME_EXE)
        time.sleep(4)
    try:
        collect_shots(t_launch, run_dir, note)
    except Exception as ex:
        note('job: the game\'s screenshots not collected: %s' % ex)
    r = subprocess.run(PY + [os.path.join(C.HERE, 'kit.py'), 'restore'], capture_output=True, text=True,
                       creationflags=C.NO_WINDOW, env=dict(os.environ, SV_AUTOTEST_RUN=run_dir))
    note((r.stdout + r.stderr).strip())
    note('job: rc %d' % rc)
    return rc


def follow(t_launch, a, note):
    log_p, pos, last_new, result, fails = None, 0, time.time(), None, 0
    deadline = t_launch + a.max_s + 300
    while time.time() < deadline:
        time.sleep(1)
        if not C.game_running():
            note('job: the game is gone (closed or crashed) before a RESULT')
            return 2
        if not log_p:
            log_p = newest_lua_log(t_launch)
            if not log_p:
                if time.time() - t_launch > 75 and stalled_start():
                    note('job: the game stalled at its start (UE4SS.log: "Still waiting for object construction" with '
                         'the count unchanged for over a minute); its threads:')
                    try:
                        import stackprobe
                        pid = (C.pids_of(C.GAME_EXE) or [0])[0]
                        for line in stackprobe.probe(pid, all_threads=True, show=16):
                            note('  ' + line)
                    except Exception as ex:   # (only a look: never in the way of the cleanup)
                        note('  the stack probe failed: %s' % ex)
                    return 2
                if time.time() - t_launch > 180:
                    note("job: no Survival Lua log 180 s after the launch (Survival didn't load?)")
                    return 2
                continue
            note('job: following ' + os.path.basename(log_p))
            last_new = time.time()
        with open(log_p, 'rb') as f:
            f.seek(pos)
            chunk = f.read()
        if chunk:
            nl = chunk.rfind(b'\n')
            if nl >= 0:
                pos += nl + 1
                last_new = time.time()
                for raw in chunk[:nl].splitlines():
                    line = raw.decode('utf-8', 'replace')
                    if 'selftest: SHOT ' in line:
                        shoot(line, note)
                    if 'selftest: ' in line:
                        note(line.strip())
                        if 'selftest: FAIL' in line:
                            fails += 1
                        if 'selftest: RESULT' in line:
                            result = line
        if result:
            time.sleep(2)
            return 0 if fails == 0 and '/0 ' not in result else 1
        if time.time() - last_new > WATCHDOG_S:
            note('job: the watchdog: no new Survival log line for %d s' % WATCHDOG_S)
            return 2
    note('job: no RESULT by the job deadline')
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
