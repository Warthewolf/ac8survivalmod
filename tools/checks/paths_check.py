"""paths_check.py : no machine path in the repo (AGENTS.md "How to work", step 4).
A path that differs from one machine to another belongs in .env (tools/env.sh, tools/env.py), never in a tool, a doc or
a script. tools/build_all.sh runs this; it fails the build on a drive-letter path or a user's home folder.

    python -X utf8 -I tools/checks/paths_check.py

Scans the git-tracked TEXT files under tools/, runtime/, mod/ and docs/, plus the repo's top-level files (AGENTS.md,
CONTRIBUTING.md, the plans; not HISTORY.md, the build archive). A hit is `X:\\` or `X:/` (X a
letter, not part of a longer word: `https://` and `file:///` don't match), `/Users/` or `/home/`. Left alone:
- .env.example (its C:/... lines are examples); local plans (docs/design/*_PLAN.md) are git-ignored, so never scanned;
- any line carrying the marker `paths_check: ok` (a comment in the file's language), e.g. the co-op tests' hostile
  inputs ("C:/evil.uasset");
- binary files (a NUL byte in the first 8 KB: tools/usmap.pkl).
"""
import os, re, subprocess, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
SCAN = ('tools/', 'runtime/', 'mod/', 'docs/')
SKIP_TOP = {'HISTORY.md'}                           # (the build archive: old notes, left as they were)
EXEMPT = {'.env.example', 'tools/checks/paths_check.py'}   # (this file: its docstring and pattern describe paths)
MARKER = 'paths_check: ok'
HIT = re.compile(r'(?<![A-Za-z0-9])[A-Za-z]:[\\/]|/Users/|/home/')


def tracked():
    out = subprocess.run(['git', 'ls-files', '-z'], cwd=ROOT, capture_output=True, check=True).stdout
    for p in out.decode('utf-8', 'replace').split('\0'):
        if p and p not in EXEMPT and (p.startswith(SCAN) or ('/' not in p and p not in SKIP_TOP)):
            yield p


def main():
    bad = []
    for p in tracked():
        full = os.path.join(ROOT, p)
        if not os.path.isfile(full):
            continue
        with open(full, 'rb') as f:
            data = f.read()
        if b'\0' in data[:8192]:
            continue
        for n, line in enumerate(data.decode('utf-8', 'replace').splitlines(), 1):
            if MARKER not in line and HIT.search(line):
                bad.append((p, n, line.strip()))
    if bad:
        print(f'paths check: {len(bad)} machine path(s) in the repo (read them from .env: AGENTS.md "How to work", step 4):')
        for p, n, line in bad:
            print(f'  {p}:{n}: {line[:140]}')
        return 1
    print('paths check: no machine path in tools, runtime, mod, docs and the top-level files')
    return 0


if __name__ == '__main__':
    sys.exit(main())
