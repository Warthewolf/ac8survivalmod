"""size_check.py : no source file over MAX_LINES (2,000) lines, so a person or an AI can read and edit one without
wading through thousands of lines (a contributor's feedback, 2026-11-07: "almost 6k for sv_coop.lua and many over 2k
not maintainable for human or AI"). tools/build_all.sh runs it; it fails the build on a file over the limit.

    python -I tools/checks/size_check.py            the files over the limit (exit 1), else the five longest
    python -I tools/checks/size_check.py --all      every source file's line count, longest first

Source = the Lua runtime and the test suites (*.lua), the tools (*.py, *.sh), the native runtime (*.c, *.h) and the
leaderboard Worker (*.js). Data and generated files (build/, tools/data/, mod/Content/, *.json) aren't counted.
"""
import os, sys

MAX_LINES = 2000
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
DIRS = ['mod/UE4SS/AC8SurvivalMode/Scripts', 'tools', 'runtime', 'leaderboard/src']
EXTS = ('.lua', '.py', '.sh', '.c', '.h', '.js')
SKIP = {'build', 'data', 'llvm', 'bin', '__pycache__', 'node_modules', 'Content', 'x02s_assets'}


def files():
    for d in DIRS:
        top = os.path.join(ROOT, d)
        for root, dirs, fs in os.walk(top):
            dirs[:] = [x for x in dirs if x not in SKIP]
            for f in fs:
                if f.endswith(EXTS):
                    p = os.path.join(root, f)
                    with open(p, 'rb') as fh:
                        yield os.path.relpath(p, ROOT).replace('\\', '/'), fh.read().count(b'\n') + 1


def main(argv):
    counts = sorted(files(), key=lambda x: -x[1])
    over = [(p, n) for p, n in counts if n > MAX_LINES]
    if '--all' in argv:
        for p, n in counts:
            print(f'{n:6d}  {p}')
    if over:
        print(f'size check: {len(over)} file(s) over {MAX_LINES} lines (split them at a topic boundary: CONTRIBUTING.md):')
        for p, n in over:
            print(f'  {n:6d}  {p}')
        return 1
    print(f'size check: {len(counts)} source files, none over {MAX_LINES} lines; the longest: '
          + ', '.join(f'{p} {n}' for p, n in counts[:5]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
