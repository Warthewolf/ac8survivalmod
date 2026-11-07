"""novalka.py <stage mod folder> : makes a staged build one without VALKA (tools/package_release.sh with NOVALKA=1;
user, 2026-10-25: "Do Not Include VALKA" in a build for a friend). On the staged copies only, never the sources:
  - Scripts/sv_config.lua (the part or its next pieces: tools/lua_parts.py): CFG.specials.valka.enabled = false,
    "valka" out of CFG.specials.rotation
  - config/survival.default.ini: valka out of the rotation and its note, the [specials.valka] section gone
Her AC7 assets (the X-02S container, the railgun sounds) are removed by package_release.sh; this checks they're gone.
"""
import os
import re
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lua_parts


def sub(s, old, new, what):
    assert s.count(old) == 1, f'{what}: {s.count(old)} matches for {old!r}'
    return s.replace(old, new)


def main(mod):
    scripts = os.path.join(mod, 'Scripts')
    lua_parts.sub(scripts, 'sv_config', 'valka    = { enabled = true,', 'valka    = { enabled = false,', 'sv_config valka')
    # (the rotation's literal grows with new specials (2026-11-06: escort): "valka" taken out wherever it sits)
    n = lua_parts.subn(scripts, 'sv_config', r'(rotation\s*=\s*\{[^}]*?), "valka"', r'\1')
    assert n == 1, f'sv_config: {n} rotations with valka'
    p = os.path.join(mod, 'config', 'survival.default.ini')
    s = open(p, encoding='utf-8', newline='').read()
    s, n = re.subn(r'(;rotation = [^\n]*?), valka\b', r'\1', s)
    assert n == 1, f'ini: {n} rotations with valka'
    s = sub(s, ' glitch (AB.L..IN), valka (VALKA), spaceport', ' glitch (AB.L..IN), spaceport', 'ini note')
    m = re.search(r'\[specials\.valka\][^\[]*', s)
    assert m, 'ini: no [specials.valka]'
    s = s[:m.start()] + s[m.end():]
    open(p, 'w', encoding='utf-8', newline='').write(s)
    # nothing of hers is left: no X-02S container, no AC7 sounds, the rotation without her
    root = os.path.dirname(os.path.dirname(mod))           # .../ue4ss/Mods
    bad = []
    for d, _, fs in os.walk(root):
        for f in fs:
            if 'Valka' in f or f.lower().endswith('.wav'):
                bad.append(os.path.join(d, f))
    assert not bad, f'VALKA files still staged: {bad}'
    lua = lua_parts.read(scripts, 'sv_config')
    assert not re.search(r'rotation\s*=\s*\{[^}]*"valka"', lua), 'sv_config: valka still in the rotation'
    print(f'novalka: VALKA switched off and out of the rotation in {mod}; no X-02S container or AC7 sounds staged')


if __name__ == '__main__':
    main(sys.argv[1])
