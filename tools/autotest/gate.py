"""gate.py: the one way an agent starts ACE COMBAT 8 for a test. A queue (one game run at a time) and a safety wrapper.

    python -I tools/autotest/gate.py run --who <id> --label "<what>" --max-minutes N --cleanup "<cmd>" -- <job cmd...>
    python -I tools/autotest/gate.py launch --who <id>      (called BY the job once its files are in)
    python -I tools/autotest/gate.py cancel --who <id>      (the only safe way to stop a run)
    python -I tools/autotest/gate.py status

`run` (start it in the background: it blocks until its turn): waits until it's first in the queue AND the game isn't
running (the user playing counts as busy); snapshots Win64 + Paks (size, mtime); backs up the saves (a copy a killed run
left IS the true pre-run state: put back first); clears this agent's stale flags; runs the job, once a second watching
for the job's launch flag (-> the safe launch), a cancel flag, anti-cheat (kill, rc 99), free commit under 3 GB (kill,
rc 97), the max time (kill, rc 124), the driver-warning dialog (answered No). Whatever happened: the --cleanup command,
the changed saves put back, the snapshot diffed (any difference = FAIL, rc 4), a new crash folder = FAIL (rc 3).
gate_log.txt in the main tree's build/autotest. The design: tools/autotest/README.md (from the user's upload of
2026-11-16; every rule there came from a real failure)."""
import argparse
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

MIN_COMMIT_RUN_GB = 3.0        # under this while the game runs: killed (rc 97)
MIN_COMMIT_LAUNCH_GB = 20.0    # the launch needs this much free commit (AC8 commits 20-30 GB loading)
LAUNCH_WAIT_S = 120
SKIP_DIRS = {'logs', 'saved', 'crashes', '__pycache__'}
SKIP_SUFFIX = ('.log', '.tmp')
SKIP_NAMES = {'ue4ss.log', 'ue4ss_stats.txt'}


def gate_log(line):
    C.log_to(os.path.join(C.state_dir(), 'gate_log.txt'), line)
    print(line, flush=True)


def flag(name):
    return os.path.join(C.state_dir('flags'), name)


# ---- the queue -------------------------------------------------------------------------------------------------------
def _pid_alive(pid):
    return any(p == pid for _, p in C.processes())


def _lock():
    path = os.path.join(C.state_dir(), 'queue.lock')
    for _ in range(200):
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            return path
        except FileExistsError:
            try:
                holder = int(open(path).read().strip() or 0)
            except (OSError, ValueError):
                holder = 0
            if holder and not _pid_alive(holder):
                try:
                    os.remove(path)
                except OSError:
                    pass
            time.sleep(0.1)
    raise SystemExit('gate: the queue lock is held (build/autotest/queue.lock)')


def _queue_edit(fn):
    lk = _lock()
    try:
        qp = os.path.join(C.state_dir(), 'queue.json')
        q = [e for e in (C.read_json(qp, []) or []) if _pid_alive(e.get('pid', 0))]
        if fn:
            q = fn(q)
        C.write_json(qp, q)
        return q
    finally:
        os.remove(lk)


def _median_minutes():
    runs = C.read_json(os.path.join(C.state_dir(), 'runs.json'), []) or []
    m = sorted(r['minutes'] for r in runs[-10:] if 'minutes' in r)
    return m[len(m) // 2] if m else None


# ---- the snapshot ----------------------------------------------------------------------------------------------------
def snapshot():
    snap = {}
    for root in (C.win64(), C.paks_dir()):
        base = os.path.basename(os.path.normpath(root))
        for d, dirs, files in os.walk(root):
            dirs[:] = [x for x in dirs if x.lower() not in SKIP_DIRS]
            for f in files:
                fl = f.lower()
                if fl in SKIP_NAMES or fl.endswith(SKIP_SUFFIX):
                    continue
                p = os.path.join(d, f)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                snap[base + '/' + os.path.relpath(p, root).replace('\\', '/')] = [st.st_size, st.st_mtime_ns]
    return snap


def diff(a, b):
    added = sorted(set(b) - set(a))
    removed = sorted(set(a) - set(b))
    changed = sorted(k for k in set(a) & set(b) if a[k] != b[k])
    return added, removed, changed


# ---- the saves -------------------------------------------------------------------------------------------------------
def save_files():
    sg = os.path.join(C.saved_dir(), 'SaveGames')
    out = []
    if os.path.isdir(sg):
        for f in os.listdir(sg):
            p = os.path.join(sg, f)
            if os.path.isfile(p):
                out.append(p)
    return sg, out


def backup_saves(who):
    bk = os.path.join(C.state_dir('saves'), who)
    man_p = os.path.join(bk, 'manifest.json')
    sg, files = save_files()
    old = C.read_json(man_p)
    if old:                                                  # a killed run's copy: the true pre-run state
        gate_log('saves: a backup from an earlier run is still there (a killed run): put back first')
        restore_saves(who, os.path.join(C.state_dir('runs'), 'stale_' + C.now_stamp()))
    os.makedirs(bk, exist_ok=True)
    man = {}
    for p in files:
        name = os.path.basename(p)
        shutil.copy2(p, os.path.join(bk, name))
        man[name] = C.sha256(p)
    C.write_json(man_p, {'dir': sg, 'files': man})
    gate_log('saves: %d files backed up from SaveGames' % len(man))


def restore_saves(who, run_dir):
    bk = os.path.join(C.state_dir('saves'), who)
    man_p = os.path.join(bk, 'manifest.json')
    man = C.read_json(man_p)
    if not man:
        return []
    sg = man['dir']
    put, moved = [], []
    for name, h in man['files'].items():
        dst = os.path.join(sg, name)
        if not os.path.isfile(dst) or C.sha256(dst) != h:
            shutil.copy2(os.path.join(bk, name), dst)
            put.append(name)
    _, now = save_files()
    for p in now:                                            # new saves the run made: kept with the run, not deleted
        if os.path.basename(p) not in man['files']:
            os.makedirs(os.path.join(run_dir, 'new_saves'), exist_ok=True)
            shutil.move(p, os.path.join(run_dir, 'new_saves', os.path.basename(p)))
            moved.append(os.path.basename(p))
    shutil.rmtree(bk, ignore_errors=True)
    if put or moved:
        gate_log('saves: put back %s%s' % (', '.join(put) or 'none',
                                            ('; new ones moved to the run folder: ' + ', '.join(moved)) if moved else ''))
    else:
        gate_log('saves: unchanged')
    return put


# ---- the safe launch -------------------------------------------------------------------------------------------------
def launch_refusal():
    if C.game_running():
        return 'the game is already running'
    ac = C.anti_cheat_running()
    if ac:
        return 'anti-cheat is running (%s)' % ', '.join(ac)
    if not C.steam_running():
        return "Steam isn't running"
    w = C.win64()
    if not (os.path.isfile(os.path.join(w, 'dwmapi.dll')) and os.path.isdir(os.path.join(w, 'ue4ss'))):
        return "UE4SS's dwmapi.dll / ue4ss\\ are missing (the launcher isn't in Modded mode)"
    fc = C.free_commit_gb()
    if fc is not None and fc < MIN_COMMIT_LAUNCH_GB:
        return 'free commit %.1f GB, under the %.0f GB AC8 needs' % (fc, MIN_COMMIT_LAUNCH_GB)
    return None


def user_environment():
    """The environment Explorer would give the game: this process's, less the agent's shell (Git Bash's MSYS / MINGW
    names, Claude Code's own), with PATH rebuilt from the registry's (the machine's, then the user's). 2026-11-16: the
    first two gated runs, started with the agent shell's environment (Git's mingw64\\bin first on PATH), hung at 9,474
    objects with no window; the user's own launches go on within a second there."""
    import winreg

    def reg(root, key, name):
        try:
            with winreg.OpenKey(root, key) as k:
                v, t = winreg.QueryValueEx(k, name)
                return winreg.ExpandEnvironmentStrings(v) if t == winreg.REG_EXPAND_SZ else v
        except OSError:
            return ''
    drop = ('CLAUDE', 'MSYS', 'MINGW', 'SV_AUTOTEST', 'NODEFAULTCURRENTDIRECTORYINEXEPATH', 'EXEPATH', 'SHELL',
            'ORIGINAL_PATH', 'ACLOCAL_PATH', 'MANPATH', 'INFOPATH', 'PKG_CONFIG_PATH', 'TERM', 'SHLVL', 'OLDPWD', 'PWD',
            'PS1', '_', 'CHERE_INVOKING', 'PLINK_PROTOCOL', 'DISPLAY', 'HOSTNAME', 'PYTHON')
    e = {k: v for k, v in os.environ.items() if not any(k.upper().startswith(d) for d in drop)}
    machine = reg(winreg.HKEY_LOCAL_MACHINE, r'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'Path')
    user = reg(winreg.HKEY_CURRENT_USER, 'Environment', 'Path')
    if machine:
        e['PATH'] = ';'.join(p for p in (machine, user) if p)
    return e


def shell_start(exe, params, cwd, environ):
    """The game started as the mod launcher's Play modded starts it: ShellExecuteExW (the launcher's Go binary imports
    it, with SteamAppId / SteamGameId 2288340 and "AceCombat8.exe -eac-nop-loaded -nosplash"), not CreateProcess with
    redirected handles. The child takes this process's environment, so it's set to `environ` around the call. 2026-11-16:
    three gated runs started with subprocess.Popen hung at 9,474 objects with no window. Returns its pid or None."""
    import ctypes
    import ctypes.wintypes as wt

    class SEI(ctypes.Structure):
        _fields_ = [('cbSize', wt.DWORD), ('fMask', ctypes.c_ulong), ('hwnd', wt.HWND), ('lpVerb', wt.LPCWSTR),
                    ('lpFile', wt.LPCWSTR), ('lpParameters', wt.LPCWSTR), ('lpDirectory', wt.LPCWSTR),
                    ('nShow', ctypes.c_int), ('hInstApp', wt.HINSTANCE), ('lpIDList', ctypes.c_void_p),
                    ('lpClass', wt.LPCWSTR), ('hkeyClass', wt.HKEY), ('dwHotKey', wt.DWORD), ('hIcon', wt.HANDLE),
                    ('hProcess', wt.HANDLE)]
    SEE_MASK_NOCLOSEPROCESS, SEE_MASK_NOASYNC, SW_SHOWNORMAL = 0x40, 0x100, 1
    old = dict(os.environ)
    try:
        os.environ.clear()
        os.environ.update(environ)
        sei = SEI()
        sei.cbSize = ctypes.sizeof(SEI)
        sei.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC
        sei.lpVerb, sei.lpFile, sei.lpParameters, sei.lpDirectory, sei.nShow = 'open', exe, params, cwd, SW_SHOWNORMAL
        if not ctypes.windll.shell32.ShellExecuteExW(ctypes.byref(sei)):
            return None
    finally:
        os.environ.clear()
        os.environ.update(old)
    k32 = ctypes.windll.kernel32
    pid = k32.GetProcessId(sei.hProcess) if sei.hProcess else None
    if sei.hProcess:
        k32.CloseHandle(sei.hProcess)
    return pid


def safe_launch(run_dir):
    """Never Steam's Play or steam://run with mods in (that path starts Easy Anti-Cheat): the exe itself with
    -eac-nop-loaded, as the mod launcher's Play modded does ("how=direct", its CHANGELOG: "the same as ac8noeac.bat"),
    with the user's environment (user_environment). Returns (pid or None, message)."""
    why = launch_refusal()
    if why:
        return None, 'refused: ' + why
    w = C.win64()
    t0 = time.time()
    pid = shell_start(os.path.join(w, C.GAME_EXE), '-eac-nop-loaded -nosplash', w,
                      dict(user_environment(), SteamAppId=C.STEAM_APP_ID, SteamGameId=C.STEAM_APP_ID))
    if not pid:
        return None, 'ShellExecuteEx failed'
    ul = C.ue4ss_log()
    while time.time() - t0 < LAUNCH_WAIT_S:
        if C.anti_cheat_running():
            C.kill_anti_cheat()
            C.kill(C.GAME_EXE)
            return None, 'anti-cheat started with the game: both killed'
        pids = C.pids_of(C.GAME_EXE)
        if pids:
            C.answer_driver_warning(pids, gate_log)
        try:
            if os.path.getmtime(ul) >= t0 - 1:
                txt = open(ul, encoding='utf-8', errors='replace').read()
                if all(m in txt for m in C.EXPECTED_MODS):
                    return pid, 'UE4SS.log names %s after %.0f s' % (' and '.join(C.EXPECTED_MODS), time.time() - t0)
        except OSError:
            pass
        if not pids and time.time() - t0 > 15:
            return None, 'the game exited at once'
        time.sleep(1)
    C.kill(C.GAME_EXE)
    if os.path.isfile(ul):
        shutil.copy2(ul, os.path.join(run_dir, 'UE4SS_launch_fail.log'))
    return None, "UE4SS.log didn't name %s within %d s: killed" % (' and '.join(C.EXPECTED_MODS), LAUNCH_WAIT_S)


# ---- run -------------------------------------------------------------------------------------------------------------
def crashes():
    d = os.path.join(C.saved_dir(), 'Crashes')
    return set(os.listdir(d)) if os.path.isdir(d) else set()


def cmd_run(a):
    who = a.who
    run_dir = C.state_dir('runs', '%s_%s' % (C.now_stamp(), who))
    me = {'who': who, 'label': a.label, 'pid': os.getpid(), 'since': time.time()}
    _queue_edit(lambda q: q + [me])
    told = False
    try:
        while True:
            q = _queue_edit(None)
            first = q and q[0].get('pid') == os.getpid()
            if first and not C.game_running():
                break
            if not told:
                med = _median_minutes()
                gate_log('QUEUED %s "%s": %s%s' % (who, a.label, 'behind %d run(s)' % (len(q) - 1) if not first
                                                   else 'waiting for the game to close (the user playing counts as busy)',
                                                   ', ~%.0f min a run lately' % med if med else ''))
                told = True
            time.sleep(5)
        rc = _run_turn(a, run_dir)
    finally:
        _queue_edit(lambda q: [e for e in q if e.get('pid') != os.getpid()])
    return rc


def _run_turn(a, run_dir):
    who, t0 = a.who, time.time()
    for n in ('launch_', 'cancel_', 'launched_'):
        p = flag(n + who + ('.json' if n == 'launched_' else ''))
        if os.path.exists(p):
            os.remove(p)
    snap0 = snapshot()
    C.write_json(os.path.join(run_dir, 'snapshot_before.json'), snap0)
    crash0 = crashes()
    backup_saves(who)
    gate_log('START %s "%s" (max %d min; run folder %s)' % (who, a.label, a.max_minutes, run_dir))
    e = dict(os.environ, SV_AUTOTEST_WHO=who, SV_AUTOTEST_RUN=run_dir)
    job = subprocess.Popen(a.job, env=e, creationflags=C.NO_WINDOW,
                           stdout=open(os.path.join(run_dir, 'job_out.txt'), 'w'), stderr=subprocess.STDOUT)
    rc, why = None, ''
    try:
        rc, why = _watch(a, job, t0, run_dir)
    except Exception as ex:                  # (2026-11-16: a typo here once skipped the cleanup: never again)
        import traceback
        open(os.path.join(run_dir, 'gate_error.txt'), 'w').write(traceback.format_exc())
        rc, why = 98, 'the gate failed while watching (%s): cleaning up' % ex
    return _finish(a, job, t0, run_dir, snap0, crash0, rc, why)


def _watch(a, job, t0, run_dir):
    who = a.who
    rc, why = None, ''
    while rc is None:
        time.sleep(1)
        r = job.poll()
        if r is not None:
            rc = r
            break
        if os.path.exists(flag('cancel_' + who)):
            why, rc = 'cancelled', 130
            break
        if time.time() - t0 > a.max_minutes * 60:
            why, rc = 'max time (%d min)' % a.max_minutes, 124
            break
        if os.path.exists(flag('launch_' + who)):
            os.remove(flag('launch_' + who))
            game_pid, msg = safe_launch(run_dir)
            gate_log('LAUNCH %s: %s' % (who, msg))
            C.write_json(flag('launched_' + who + '.json'), {'pid': game_pid, 'msg': msg, 'at': time.time()})
        pids = C.pids_of(C.GAME_EXE)
        if pids:
            if C.anti_cheat_running():
                why, rc = 'anti-cheat process seen: killed', 99
                C.kill_anti_cheat()
                break
            fc = C.free_commit_gb()
            if fc is not None and fc < MIN_COMMIT_RUN_GB:
                why, rc = 'free commit %.1f GB < %.0f GB: the game killed' % (fc, MIN_COMMIT_RUN_GB), 97
                break
            C.answer_driver_warning(pids, gate_log)
    return rc, why


def _finish(a, job, t0, run_dir, snap0, crash0, rc, why):
    who = a.who
    if job.poll() is None:
        C.kill(pid=job.pid)
    if C.game_running():
        C.kill(C.GAME_EXE)
        time.sleep(3)
    if why:
        gate_log('STOP %s: %s' % (who, why))
    # always: cleanup, saves, diff, crashes
    if a.cleanup:
        r = subprocess.run(a.cleanup, shell=True, capture_output=True, text=True, creationflags=C.NO_WINDOW,
                           env=dict(os.environ, SV_AUTOTEST_WHO=who, SV_AUTOTEST_RUN=run_dir))
        open(os.path.join(run_dir, 'cleanup_out.txt'), 'w').write(r.stdout + r.stderr)
        gate_log('cleanup: rc %d (%s)' % (r.returncode, (r.stdout + r.stderr).strip().splitlines()[-1:] or ''))
    restore_saves(who, run_dir)
    snap1 = snapshot()
    added, removed, changed = diff(snap0, snap1)
    if added or removed or changed:
        rep = os.path.join(run_dir, 'install_diff.txt')
        with open(rep, 'w', encoding='utf-8') as f:
            for k, lst in (('added', added), ('removed', removed), ('changed', changed)):
                for p in lst:
                    f.write('%s %s\n' % (k, p))
        gate_log('INSTALL NOT RESTORED (%d added, %d removed, %d changed): %s' % (len(added), len(removed), len(changed),
                                                                               rep))
        if rc == 0:
            rc = 4
    else:
        gate_log('install restored (Win64 + Paks as before)')
    new_crash = sorted(crashes() - crash0)
    if new_crash:
        gate_log('CRASH: new crash folder(s) %s' % ', '.join(new_crash))
        for c in new_crash:
            src = os.path.join(C.saved_dir(), 'Crashes', c)
            if os.path.isdir(src):
                shutil.copytree(src, os.path.join(run_dir, 'crash_' + c))
        rc = 3
    mins = (time.time() - t0) / 60
    runs_p = os.path.join(C.state_dir(), 'runs.json')
    runs = C.read_json(runs_p, []) or []
    runs.append({'who': who, 'label': a.label, 'rc': rc, 'minutes': round(mins, 1), 'dir': run_dir})
    C.write_json(runs_p, runs[-50:])
    gate_log('END %s "%s": rc %s, %.1f min' % (who, a.label, rc, mins))
    return rc


def cmd_launch(a):
    res = flag('launched_' + a.who + '.json')
    if os.path.exists(res):
        os.remove(res)
    open(flag('launch_' + a.who), 'w').write(str(time.time()))
    t0 = time.time()
    while time.time() - t0 < LAUNCH_WAIT_S + 60:
        r = C.read_json(res)
        if r:
            print(r['msg'])
            return 0 if r.get('pid') else 1
        time.sleep(1)
    print('gate: no answer to the launch (is a gate run going for %s?)' % a.who)
    return 1


def cmd_cancel(a):
    open(flag('cancel_' + a.who), 'w').write(str(time.time()))
    print('cancel asked for %s' % a.who)
    return 0


def cmd_status(_):
    q = _queue_edit(None)
    print('queue: ' + (', '.join('%s "%s"' % (e['who'], e['label']) for e in q) or 'empty'))
    print('game running: %s; free commit %.1f GB' % (C.game_running(), C.free_commit_gb() or -1))
    lp = os.path.join(C.state_dir(), 'gate_log.txt')
    if os.path.isfile(lp):
        print(''.join(open(lp, encoding='utf-8').readlines()[-12:]))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog='gate.py')
    sp = ap.add_subparsers(dest='cmd', required=True)
    r = sp.add_parser('run')
    r.add_argument('--who', required=True)
    r.add_argument('--label', required=True)
    r.add_argument('--max-minutes', type=int, required=True)
    r.add_argument('--cleanup', required=True)
    r.add_argument('job', nargs=argparse.REMAINDER)
    for n in ('launch', 'cancel'):
        p = sp.add_parser(n)
        p.add_argument('--who', required=True)
    sp.add_parser('status')
    a = ap.parse_args(argv)
    if a.cmd == 'run':
        if a.job and a.job[0] == '--':
            a.job = a.job[1:]
        if not a.job:
            ap.error('run needs a job command after --')
        return cmd_run(a)
    return {'launch': cmd_launch, 'cancel': cmd_cancel, 'status': cmd_status}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
