"""coop_edition.py <stage folder> <stage mod folder> : makes a staged build the Survival COOP build (tools/package_release.sh
with COOP=1; user, 2026-10-25: "a new 0.70.6 build called Survival COOP"). On the staged copies only, never the sources:
  - Scripts/sv_config.lua: CFG.coop.enabled = true
  - Scripts/main.lua: VERSION gets COOP_TAG (both players' builds must match: sv_coop.lua compares them)
  - config/survival.default.ini: its [coop] note says it's on
  - README.txt: release/README_COOP.txt put in after the first paragraph
"""
import os
import sys

COOP_TAG = '-coop2mp.43'


def sub(s, old, new, what):
    assert s.count(old) == 1, f'{what}: {s.count(old)} matches for {old!r}'
    return s.replace(old, new)


def main(stage, mod):
    p = os.path.join(mod, 'Scripts', 'sv_config.lua')
    s = open(p, encoding='utf-8', newline='').read()
    s = sub(s, 'coop = { enabled = false,', 'coop = { enabled = true,', 'sv_config coop')
    open(p, 'w', encoding='utf-8', newline='').write(s)
    p = os.path.join(mod, 'Scripts', 'main.lua')
    s = open(p, encoding='utf-8', newline='').read()
    i = s.index('VERSION = "') + len('VERSION = "')
    j = s.index('"', i)
    version = s[i:j] + COOP_TAG
    s = s[:i] + version + s[j:]
    open(p, 'w', encoding='utf-8', newline='').write(s)
    p = os.path.join(mod, 'config', 'survival.default.ini')
    s = open(p, encoding='utf-8', newline='').read()
    s = sub(s, 'enabled: true in the Survival COOP build.', 'enabled: true (this is the Survival COOP build).', 'ini coop')
    open(p, 'w', encoding='utf-8', newline='').write(s)
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    extra = open(os.path.join(here, 'release', 'README_COOP.txt'), encoding='utf-8').read()
    p = os.path.join(stage, 'README.txt')
    s = open(p, encoding='utf-8', newline='').read()
    s = s.replace('AC8 Survival Mode - ', 'AC8 Survival COOP - ', 1)
    k = s.find('\n\n', s.find('=====')) + 2
    s = s[:k] + extra.rstrip() + '\n\n' + s[k:]
    open(p, 'w', encoding='utf-8', newline='').write(s)
    print(f'coop: Survival COOP build (Lua {version}, co-op on)')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
