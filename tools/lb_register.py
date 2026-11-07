"""lb_register.py: register a build's hash on the leaderboard Worker, so its runs count, with no trip to /admin.

(user, 2026-11-07: "rework the leaderboard so I don't have to continually register a new version everytime we patch")
tools/package_release.sh (online) and tools/package_dev.sh run it on every build they make; it can also be run by hand:

    python -I tools/lb_register.py <zip>.buildhash.txt ...         # the .buildhash.txt files package_release.sh writes
    python -I tools/lb_register.py --mod <version> --build <hash> [--note <text>]

It reads the Worker's address from the MAIN tree's leaderboard/submit.local (git-ignored; the runtime's build reads
URL and KEY from it: URL=https://<worker>.workers.dev/submit) and the admin key from the main tree's
leaderboard/keys.secret (git-ignored, the user's record of the Worker's secrets: an ADMIN_KEY=... line), else from an
ADMIN=... line in submit.local. With neither it says so and registers nothing (the build is then registered by hand on
/admin, as before); it never fails the packaging. The key goes in the POST body (POST /admin/builds/add, the
admin page's own call), never in the address. One try a build: the Worker locks an address out after 5 wrong keys, so a
refused key is reported, not retried. SV_LB_REGISTER=0 skips it.
"""
import json, os, re, subprocess, sys, urllib.error, urllib.request

BUILD_RE = re.compile(r'^[0-9a-f]{64}$')


def main_tree():
    """The main working tree (build/ and leaderboard/submit.local live there), from any git worktree."""
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        common = subprocess.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=here,
                                capture_output=True, text=True, check=True).stdout.strip()
        if common:
            return os.path.dirname(common)
    except Exception:
        pass
    return os.path.dirname(here)


def secret_key():
    """ADMIN_KEY from the main tree's leaderboard/keys.secret (git-ignored; the user's own record of the Worker's
    secrets, NAME=value lines: SUBMIT_KEY, ADMIN_KEY), or None."""
    path = os.environ.get('SV_LB_SECRETS') or os.path.join(main_tree(), 'leaderboard', 'keys.secret')
    if not os.path.isfile(path):
        return None
    with open(path, encoding='utf-8-sig') as f:
        for line in f:
            k, _, v = line.strip().partition('=')
            if k.strip() == 'ADMIN_KEY' and v.strip():
                return v.strip().strip('"\'')
    return None


def settings():
    """(worker base address, admin key) from leaderboard/submit.local (URL) and the admin key from
    leaderboard/keys.secret's ADMIN_KEY line (2026-11-07: where the user keeps it), else submit.local's ADMIN line;
    or (None, why)."""
    path = os.environ.get('SV_LB_LOCAL') or os.path.join(main_tree(), 'leaderboard', 'submit.local')
    if not os.path.isfile(path):
        return None, f'no {path}'
    url = key = None
    with open(path, encoding='utf-8-sig') as f:
        for line in f:
            k, _, v = line.strip().partition('=')
            if k == 'URL':
                url = v.strip()
            elif k == 'ADMIN':
                key = v.strip()
    key = secret_key() or key
    if not url or not url.startswith('https://'):
        return None, f'no URL=https://... line in {path}'
    if not key:
        return None, f'no ADMIN_KEY=... line in leaderboard/keys.secret nor ADMIN=... in {path}'
    base = re.sub(r'/submit/?$', '', url.rstrip('/'))
    return (base, key), None


def register(base, key, mod, build, note):
    body = json.dumps({'key': key, 'mod': mod, 'build': build, 'note': note[:80]}).encode()
    req = urllib.request.Request(base + '/admin/builds/add', data=body, method='POST',
                                 headers={'Content-Type': 'application/json', 'User-Agent': 'AC8SurvivalMode-packager'})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            out = json.loads(r.read().decode('utf-8', 'replace') or '{}')
    except urllib.error.HTTPError as e:
        try:
            out = json.loads(e.read().decode('utf-8', 'replace') or '{}')
        except Exception:
            out = {}
        return False, f'HTTP {e.code}: {out.get("error") or e.reason}'
    except Exception as e:
        return False, f'{type(e).__name__}: {e}'
    if out.get('ok'):
        return True, out.get('done') or 'registered'
    return False, out.get('error') or 'refused'


def from_file(path):
    mod = build = None
    zipname = os.path.basename(path)[:-len('.buildhash.txt')] if path.endswith('.buildhash.txt') else os.path.basename(path)
    with open(path, encoding='utf-8') as f:
        for line in f:
            k, _, v = line.strip().partition(' ')
            if k == 'mod':
                mod = v.strip()
            elif k == 'build':
                build = v.strip().lower()
            elif k == 'zip':
                zipname = v.strip()
    return mod, build, zipname


def main(argv):
    if os.environ.get('SV_LB_REGISTER') == '0':
        print('leaderboard: SV_LB_REGISTER=0, not registered')
        return 0
    jobs = []
    if '--build' in argv:
        a = dict(zip(argv[::2], argv[1::2]))
        jobs.append((a.get('--mod'), (a.get('--build') or '').lower(), a.get('--note') or ''))
    else:
        for p in argv:
            jobs.append(from_file(p))
    if not jobs:
        print(__doc__)
        return 2
    cfg, why = settings()
    for mod, build, note in jobs:
        if not mod or not build or not BUILD_RE.match(build):
            print(f'leaderboard: NOT registered: no mod version or 64-hex build hash ({mod!r}, {build!r})')
            continue
        if not cfg:
            print(f'leaderboard: build {build[:12]}... (mod {mod}) NOT registered automatically ({why}): '
                  f'register it on the Worker\'s /admin page')
            continue
        ok, what = register(cfg[0], cfg[1], mod, build, note)
        if ok:
            print(f'leaderboard: {what} (mod {mod}, {note})')
        else:
            print(f'leaderboard: build {build[:12]}... (mod {mod}) NOT registered: {what}; register it on /admin '
                  f'(a refused key is not tried again: 5 wrong keys lock this address out)')
            if 'HTTP 401' in what or 'HTTP 403' in what or 'HTTP 429' in what:
                break
    return 0                                            # (never fails the packaging)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
