"""bump_version.py [--minor] [--dry-run]: a new version for every build the user is handed (user, 2026-11-07: "update
the version number each time you hand me a new file"; that day three different builds all read 0.74.0-coop2mp.92).

Bumps, together:
  mod/UE4SS/AC8SurvivalMode/Scripts/main.lua  VERSION "a.b.c" -> "a.b.(c+1)" (--minor: "a.(b+1).0")
  tools/coop_edition.py                       COOP_TAG '-coop2mp.N' -> '-coop2mp.(N+1)' (games of different builds refuse
                                              to link in co-op, so each build's own tag)
and prints the new version (VERSION + COOP_TAG, what the game, its log and the leaderboard show). Then: build_all.sh and
the package scripts with the new version (package_release.sh refuses a zip name that already exists).
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.join(ROOT, 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts', 'main.lua')
COOP = os.path.join(ROOT, 'tools', 'coop_edition.py')
VER_RE = re.compile(rb'^((?:local )?VERSION = ")(\d+)\.(\d+)\.(\d+)(")', re.M)
TAG_RE = re.compile(rb"^(COOP_TAG = '-coop2mp\.)(\d+)(')", re.M)


def main(argv):
    minor, dry = '--minor' in argv, '--dry-run' in argv
    m_src, c_src = open(MAIN, 'rb').read(), open(COOP, 'rb').read()
    mv, mt = VER_RE.search(m_src), TAG_RE.search(c_src)
    if not mv or not mt:
        print('bump_version: VERSION or COOP_TAG not found', file=sys.stderr)
        return 1
    a, b, c = int(mv.group(2)), int(mv.group(3)), int(mv.group(4))
    old = f'{a}.{b}.{c}-coop2mp.{int(mt.group(2))}'
    a2, b2, c2 = (a, b + 1, 0) if minor else (a, b, c + 1)
    n2 = int(mt.group(2)) + 1
    new = f'{a2}.{b2}.{c2}-coop2mp.{n2}'
    if not dry:
        m_src = VER_RE.sub(lambda m: m.group(1) + f'{a2}.{b2}.{c2}'.encode() + m.group(5), m_src, count=1)
        c_src = TAG_RE.sub(lambda m: m.group(1) + str(n2).encode() + m.group(3), c_src, count=1)
        open(MAIN, 'wb').write(m_src)
        open(COOP, 'wb').write(c_src)
    print(f'version: {old} -> {new}{" (dry run)" if dry else ""}')
    print(f'package as: {a2}.{b2}.{c2}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
