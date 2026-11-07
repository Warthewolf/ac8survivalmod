"""env.py : your machine's settings for the Python tools, from the repo's .env (copy .env.example to .env and fill it
in; .env is git-ignored). The same rules as tools/env.sh: this checkout's .env, else the main git tree's (one .env
serves every worktree); a variable already set in your environment wins; an empty value is ignored.

    import env                      (a tool in tools/; tools/checks/ adds tools/ to sys.path first)
    env.load()                      .env into os.environ (once; every helper below calls it)
    env.need('AC8_DIR', 'why')      the value, or stops with a clear message
    env.paks()                      the game's Paks folder (AC8_PAKS, else AC8_DIR/Game/Content/Paks)
    env.aes_key()                   the game's AES key, '0x...' (AC8_AES_KEY, else AC8_AES_SETTINGS' "aesKey")

    python -I tools/env.py --check  every setting, where it came from, whether its path exists
    python -I tools/env.py --init   writes .env from .env.example (never over an existing one)
    python -I tools/env.py --aes-key prints the AES key (for tools/get_stock.sh)
"""
import json, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
_LOADED = None          # (the .env file read or None, {name: value it set})


def _git(*args):
    try:
        return subprocess.run(['git', *args], cwd=HERE, capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        return ''


def roots():
    """(this checkout's root, the main tree's root or None)"""
    root = _git('rev-parse', '--show-toplevel') or os.path.dirname(HERE)
    common = _git('rev-parse', '--path-format=absolute', '--git-common-dir')
    return os.path.normpath(root), (os.path.normpath(os.path.dirname(common)) if common else None)


def parse(path):
    out = {}
    with open(path, encoding='utf-8-sig') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, _, v = line.partition('=')
            k, v = k.strip(), v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in '"\'':
                v = v[1:-1]
            if k.replace('_', '').isalnum() and v:
                out[k] = v
    return out


def load():
    """.env into os.environ (a name already set wins); returns (the file read or None, {name: value it set})."""
    global _LOADED
    if _LOADED is not None:
        return _LOADED
    root, main = roots()
    path, setv = None, {}
    for cand in [os.path.join(root, '.env')] + ([os.path.join(main, '.env')] if main and main != root else []):
        if os.path.isfile(cand):
            path = cand
            for k, v in parse(cand).items():
                if k not in os.environ:
                    os.environ[k] = setv[k] = v
            break
    if not os.environ.get('AC8_PAKS') and os.environ.get('AC8_DIR'):
        os.environ['AC8_PAKS'] = setv['AC8_PAKS'] = os.path.join(os.environ['AC8_DIR'], 'Game', 'Content', 'Paks')
    if not os.environ.get('AC8_MODS') and os.environ.get('AC8_DIR'):
        os.environ['AC8_MODS'] = setv['AC8_MODS'] = os.path.join(os.environ['AC8_DIR'], 'Game', 'Binaries', 'Win64',
                                                                 'ue4ss', 'Mods')
    _LOADED = (path, setv)
    return _LOADED


def get(name, default=None):
    load()
    return os.environ.get(name) or default


def need(name, why):
    v = get(name)
    if not v:
        raise SystemExit(f"{name} isn't set ({why}). Copy .env.example to .env and set it "
                         f"(python -I tools/env.py --check shows every setting).")
    return v


def paks():
    return need('AC8_PAKS', "the game's Paks folder: set AC8_DIR, the game's install folder")


def aes_key():
    """The game's AES key as '0x...': AC8_AES_KEY, else the "aesKey" of the JSON file AC8_AES_SETTINGS names."""
    k = get('AC8_AES_KEY')
    if not k:
        s = get('AC8_AES_SETTINGS')
        if not s:
            raise SystemExit("AC8_AES_KEY isn't set (the game's AES key, to read its paks), nor AC8_AES_SETTINGS (a JSON "
                             "file with an \"aesKey\", e.g. ACE8AircraftBuilder's settings.json). Set one in .env.")
        with open(s, encoding='utf-8-sig') as f:
            k = json.load(f)['aesKey']
    k = k.strip()
    return k if k.lower().startswith('0x') else '0x' + k


# (name, what it is, required for what, is a path)
SETTINGS = [
    ('AC8_DIR', "ACE COMBAT 8's install folder (holds Game/)", 'the build: the stock packages', True),
    ('AC8_PAKS', "the game's Paks folder (default AC8_DIR/Game/Content/Paks)", 'the build', True),
    ('AC8_MODS', "the game's ue4ss/Mods folder, where builds are installed (default from AC8_DIR)", 'installing', True),
    ('AC8_AES_KEY', "the game's AES key, 0x... (or AC8_AES_SETTINGS)", 'the build', False),
    ('AC8_AES_SETTINGS', 'a JSON file with an "aesKey" (instead of AC8_AES_KEY)', 'the build', True),
    ('LLVM_BIN', "LLVM's bin folder (default tools/llvm/LLVM/bin, else LLVM on PATH)", 'the native runtime', True),
    ('RELEASE_DIR', "where release zips go (default the main tree's build/release)", 'packaging', True),
    ('UE', 'Unreal Engine 5.4 (VALKA\'s X-02S assets, tools/x02s/build.sh)', 'optional', True),
    ('UMODEL', "AC7's UModel exe (tools/x02s/build.sh)", 'optional', True),
    ('AC7', "AC7's exported assets (tools/x02s/build.sh)", 'optional', True),
    ('AC7_BNK_DIR', "AC7's sound banks folder (tools/ac7_sfx.py)", 'optional', True),
    ('AC7_SE_BNK', "AC7's game_se.bnk (tools/ac7_sfx.py)", 'optional', True),
    ('VGMSTREAM', 'vgmstream-cli.exe (tools/ac7_sfx.py)', 'optional', True),
    ('SV_LB_LOCAL', "the leaderboard's submit.local (default the main tree's leaderboard/)", 'optional', True),
    ('SV_LB_SECRETS', "the leaderboard's keys.secret (default the main tree's leaderboard/)", 'optional', True),
]


def check():
    path, setv = load()
    root, main = roots()
    print(f'.env: {path or "none found (copy .env.example to .env)"}')
    bad = 0
    for name, what, need_for, is_path in SETTINGS:
        v = os.environ.get(name)
        src = 'not set' if not v else ('.env' if name in setv else 'environment')
        state = ''
        if v and is_path:
            state = 'exists' if os.path.exists(v) else 'MISSING'
            if state == 'MISSING' and need_for != 'optional':
                bad += 1
        shown = '(set, hidden)' if name == 'AC8_AES_KEY' and v else (v or '')
        print(f'  {name:<17} {src:<12} {state:<8} {shown}')
        print(f'  {"":<17} {what}; for {need_for}')
    try:
        aes_key()
        print('  AES key: found')
    except SystemExit as e:
        print(f'  AES key: NOT found: {e}')
        bad += 1
    if not os.environ.get('AC8_DIR'):
        bad += 1
    for exe in ('clang', 'llvm-dlltool'):
        lb = os.environ.get('LLVM_BIN')
        found = (lb and os.path.exists(os.path.join(lb, exe + '.exe'))) or \
            os.path.exists(os.path.join(root, 'tools', 'llvm', 'LLVM', 'bin', exe + '.exe')) or shutil.which(exe)
        print(f'  {exe}: {"found" if found else "NOT found (set LLVM_BIN, or unpack LLVM into tools/llvm)"}')
        bad += 0 if found else 1
    for f in ('tools/bin/retoc.exe', 'tools/bin/oo2core_9_win64.dll'):
        ok = os.path.exists(os.path.join(root, f)) or (main and os.path.exists(os.path.join(main, f)))
        print(f'  {f}: {"found" if ok else "NOT found (see CONTRIBUTING.md)"}')
        bad += 0 if ok else 1
    print('ready' if bad == 0 else f'{bad} thing(s) to set up before a full build (CONTRIBUTING.md)')
    return 0 if bad == 0 else 1


def init():
    root, _ = roots()
    dst, src = os.path.join(root, '.env'), os.path.join(root, '.env.example')
    if os.path.exists(dst):
        print(f'{dst} already exists: not overwritten')
        return 0
    shutil.copyfile(src, dst)
    print(f'wrote {dst} from .env.example: open it and set AC8_DIR and the AES key')
    return 0


if __name__ == '__main__':
    a = sys.argv[1:]
    if '--init' in a:
        sys.exit(init())
    if '--aes-key' in a:
        print(aes_key())
        sys.exit(0)
    sys.exit(check())
