"""tools/autotest/common.py: what the gate, the kit and the jobs share: the game's folders (from .env, tools/env.py), the
autotest state folder (the main tree's build/autotest: one queue for every worktree), and the Windows helpers (processes,
free commit, the driver-warning dialog). Python 3.8, standard library only. tools/autotest/README.md has the design."""
import ctypes
import ctypes.wintypes as wt
import csv
import hashlib
import io
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))          # tools/ (env.py)
import env  # noqa: E402

GAME_EXE = 'AceCombat8.exe'
STEAM_APP_ID = '2288340'
ANTI_CHEAT = ('easyanticheat', 'start_protected_game', 'eac_launcher')
EXPECTED_MODS = ('IoStoreLoaderMod', 'AC8SurvivalMode')     # UE4SS.log names both when everything loaded


def repo_root():
    return env.roots()[0]


def main_root():
    this, main = env.roots()
    return main or this


def state_dir(*parts):
    d = os.path.join(main_root(), 'build', 'autotest', *parts)
    os.makedirs(d, exist_ok=True)
    return d


def game_dir():
    return env.need('AC8_DIR', "ACE COMBAT 8's install folder (the one that holds Game/)")


def win64():
    return os.path.join(game_dir(), 'Game', 'Binaries', 'Win64')


def paks_dir():
    return env.paks()


def mods_dir():
    return env.need('AC8_MODS', "the game's ue4ss/Mods folder (default from AC8_DIR)")


def saved_dir():
    """The game's Saved folder (saves, crashes): AC8_SAVED, else %LOCALAPPDATA%'s."""
    v = env.get('AC8_SAVED')
    if v:
        return v
    la = os.environ.get('LOCALAPPDATA')
    if not la:
        raise SystemExit("AC8_SAVED isn't set and there's no LOCALAPPDATA: set AC8_SAVED in .env (the game's Saved folder)")
    return os.path.join(la, 'BANDAI NAMCO Entertainment', 'ACE COMBAT 8', 'Saved')


def ue4ss_log():
    return os.path.join(win64(), 'ue4ss', 'UE4SS.log')


def now_stamp():
    return time.strftime('%Y%m%d_%H%M%S')


def log_to(path, line):
    with open(path, 'a', encoding='utf-8') as f:
        f.write(time.strftime('%Y-%m-%d %H:%M:%S ') + line + '\n')


def sha256(path, bufsize=1 << 20):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while True:
            b = f.read(bufsize)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def read_json(path, default=None):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, obj):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


# ---- processes -------------------------------------------------------------------------------------------------------
NO_WINDOW = 0x08000000      # CREATE_NO_WINDOW: never a console window over the game (no-popups-while-playing)


def processes():
    """[(image name, pid)] of every running process (tasklist, no window)."""
    try:
        out = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], capture_output=True, text=True,
                             creationflags=NO_WINDOW, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    rows = []
    for r in csv.reader(io.StringIO(out)):
        if len(r) >= 2 and r[1].isdigit():
            rows.append((r[0], int(r[1])))
    return rows


def pids_of(image):
    image = image.lower()
    return [p for n, p in processes() if n.lower() == image]


def game_running():
    return bool(pids_of(GAME_EXE))


def anti_cheat_running():
    return [n for n, _ in processes() if any(a in n.lower() for a in ANTI_CHEAT)]


def steam_running():
    return bool(pids_of('steam.exe'))


def kill(image=None, pid=None):
    args = ['taskkill', '/F', '/T'] + (['/PID', str(pid)] if pid else ['/IM', image])
    subprocess.run(args, capture_output=True, creationflags=NO_WINDOW, timeout=60)


def kill_anti_cheat():
    for n, p in processes():
        if any(a in n.lower() for a in ANTI_CHEAT):
            kill(pid=p)


# ---- memory ----------------------------------------------------------------------------------------------------------
class _MemStatus(ctypes.Structure):
    _fields_ = [('dwLength', wt.DWORD), ('dwMemoryLoad', wt.DWORD), ('ullTotalPhys', ctypes.c_ulonglong),
                ('ullAvailPhys', ctypes.c_ulonglong), ('ullTotalPageFile', ctypes.c_ulonglong),
                ('ullAvailPageFile', ctypes.c_ulonglong), ('ullTotalVirtual', ctypes.c_ulonglong),
                ('ullAvailVirtual', ctypes.c_ulonglong), ('ullAvailExtendedVirtual', ctypes.c_ulonglong)]


def free_commit_gb():
    """The PC's free commit (GlobalMemoryStatusEx.ullAvailPageFile) in GB: what a load can still commit. Not free RAM:
    AC8's boot dips RAM to ~2 GB harmlessly, and it commits 20-30 GB while loading."""
    m = _MemStatus()
    m.dwLength = ctypes.sizeof(_MemStatus)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m)):
        return None
    return m.ullAvailPageFile / float(1 << 30)


# ---- the driver-warning dialog ---------------------------------------------------------------------------------------
_user32 = ctypes.windll.user32
_EnumProc = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
BM_CLICK = 0x00F5


def _text(hwnd):
    n = _user32.GetWindowTextLengthW(hwnd)
    buf = ctypes.create_unicode_buffer(n + 1)
    _user32.GetWindowTextW(hwnd, buf, n + 1)
    return buf.value


def _cls(hwnd):
    buf = ctypes.create_unicode_buffer(256)
    _user32.GetClassNameW(hwnd, buf, 256)
    return buf.value


def _pid(hwnd):
    p = wt.DWORD()
    _user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
    return p.value


def _children(hwnd):
    out = []

    def cb(h, _):
        out.append(h)
        return True
    _user32.EnumChildWindows(hwnd, _EnumProc(cb), 0)
    return out


def game_dialogs(game_pids):
    """[(hwnd, title, all its texts)] of the #32770 dialogs the game's processes own."""
    found = []

    def cb(h, _):
        if _user32.IsWindowVisible(h) and _cls(h) == '#32770' and _pid(h) in game_pids:
            texts = [_text(h)] + [_text(c) for c in _children(h)]
            found.append((h, _text(h), ' | '.join(t for t in texts if t)))
        return True
    _user32.EnumWindows(_EnumProc(cb), 0)
    return found


WM_GETTEXT, WM_GETTEXTLENGTH, WM_COMMAND, WM_NULL, BN_CLICKED = 0x000D, 0x000E, 0x0111, 0x0000, 0


def _text_msg(hwnd):
    """A control's text by WM_GETTEXT (a message box's message is a Static; GetWindowText of another process's control
    can come back empty)."""
    n = _user32.SendMessageW(hwnd, WM_GETTEXTLENGTH, 0, 0)
    if n <= 0:
        return ''
    buf = ctypes.create_unicode_buffer(n + 1)
    _user32.SendMessageW(hwnd, WM_GETTEXT, n + 1, buf)
    return buf.value


def dialog_dump(h):
    return ' | '.join('%s:%r' % (_cls(c), _text_msg(c) or _text(c)) for c in _children(h))


# Which button answers the "Known issues with graphics driver" box: always No. Its text (an Edit control, logged by
# dialog_dump; the user's PC, 2026-11-16): "The installed version of the NVIDIA graphics driver has known issues in
# D3D12. ... Would you like to visit the following URL to download the driver? https://www.nvidia.com/download/..."
# Yes opens the user's browser on that page: never. (The second gated run answered Yes to test a guess and did that.)
DRIVER_ANSWER = 'no'


def answer_driver_warning(game_pids, log):
    """The "Known issues with graphics driver" box (a #32770 the game owns, mentioning "driver") blocks the start until
    answered: its DRIVER_ANSWER button gets BM_CLICK (no mouse, no focus); every control's text logged first. Any other
    dialog of the game's is logged once, never clicked. Returns the number answered."""
    n = 0
    for h, title, texts in game_dialogs(set(game_pids)):
        if 'driver' in texts.lower():
            if h in _ANSWERED:
                continue                                  # (answered: the game hasn't taken it down yet)
            _ANSWERED.add(h)
            log('dialog: the driver warning: %s' % dialog_dump(h)[:1500])
            for c in _children(h):
                if _cls(c) == 'Button' and _text(c).replace('&', '').strip().lower() == DRIVER_ANSWER:
                    # POSTED, never sent: the game runs this box in its own GetMessageW loop (stackprobe.py, 2026-11-16:
                    # its main thread in GetMessageW from AceCombat8.exe+1884555, through Steam's overlay hook). A sent
                    # BM_CLICK is handled inside GetMessageW, the box goes, and GetMessageW waits on for a queued
                    # message that never comes: five gated runs hung at 9,474 objects that way. A queued WM_COMMAND
                    # (as a real click's) returns from GetMessageW and the loop sees its answer; a WM_NULL to the
                    # box's thread after it wakes the loop if it's still waiting.
                    tid = _user32.GetWindowThreadProcessId(h, None)
                    cid = _user32.GetDlgCtrlID(c)
                    _user32.PostMessageW(h, WM_COMMAND, (BN_CLICKED << 16) | (cid & 0xFFFF), c)
                    time.sleep(0.5)
                    _user32.PostThreadMessageW(tid, WM_NULL, 0, 0)
                    log('dialog: the driver warning answered %s (WM_COMMAND %d posted, then a WM_NULL to its thread %d)'
                        % (DRIVER_ANSWER.title(), cid, tid))
                    n += 1
                    break
            else:
                log('dialog: a driver warning without a %s button, left alone: %s' % (DRIVER_ANSWER.title(), texts[:200]))
        else:
            key = (h, texts)
            if key not in _SEEN_DIALOGS:
                _SEEN_DIALOGS.add(key)
                log('dialog: the game shows a dialog, not clicked: %s' % texts[:300])
    return n


_SEEN_DIALOGS = set()
_ANSWERED = set()
