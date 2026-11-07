"""nospaceport.py <stage mod folder> : makes a staged build one without the Spaceport specials (tools/package_release.sh
and tools/package_dev.sh with NOSPACEPORT=1; user, 2026-10-31: "build a version for my friends that DOES NOT include the
spaceport retake", "or Spaceport Defense"). On the staged copies only, never the sources:
  - Scripts/sv_config.lua (the part or its next pieces: tools/lua_parts.py): CFG.specials.spaceport.enabled = false
    (SPORT.ready: no Spaceport Assault, forced or not) and its retake's enabled = false (specialFor, the retake kind's
    ready: no Spaceport Retake)
  - config/survival.default.ini: the Spaceport out of the rotation's note, every [specials.spaceport*] section gone
The world data's fleet, landing craft and garrison units stay in the container (nothing spawns them).
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
    lua_parts.sub(scripts, 'sv_config', 'spaceport = { enabled = true, from_round = 8,', 'spaceport = { enabled = false, from_round = 8,', 'sv_config spaceport')
    lua_parts.sub(scripts, 'sv_config', 'retake = { enabled = true, per_unit = 4,', 'retake = { enabled = false, per_unit = 4,', 'sv_config retake')
    n = lua_parts.subn(scripts, 'sv_config', r'(rotation\s*=\s*\{[^}]*?), "spaceport"', r'\1')     # (in the rotation from 0.73.73)
    assert n == 1, f'sv_config: {n} rotations with the spaceport'
    assert not re.search(r'rotation\s*=\s*\{[^}]*"spaceport"', lua_parts.read(scripts, 'sv_config')), 'sv_config: spaceport in the rotation'

    p = os.path.join(mod, 'config', 'survival.default.ini')
    s = open(p, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    note = re.compile(r', spaceport \(the Spaceport' + re.escape(nl) + r'; Assault, from round 8; its retake '
                      r'comes only after a lost one\)')
    assert len(note.findall(s)) == 1, 'ini: the rotation note'
    s = note.sub('', s)
    out, drop, gone = [], False, 0
    for line in s.split(nl):
        m = re.match(r'\[([^\]]+)\]', line)
        if m:
            drop = m.group(1).lower().startswith('specials.spaceport')
            gone += 1 if drop else 0
        if not drop:
            out.append(line)
    assert gone >= 2, f'ini: {gone} [specials.spaceport*] sections'
    s = nl.join(out)
    assert 'specials.spaceport' not in s, 'ini: a [specials.spaceport*] line left'
    s, n = re.subn(r'^(;?rotation\s*=.*?), spaceport', r'\1', s, flags=re.M)
    assert n == 1, f'ini: {n} rotations with the spaceport'
    assert not re.search(r'^;?rotation\s*=.*spaceport', s, re.M), 'ini: spaceport in the rotation'
    open(p, 'w', encoding='utf-8', newline='').write(s)
    lua = lua_parts.read(scripts, 'sv_config')
    assert 'spaceport = { enabled = false,' in lua and 'retake = { enabled = false,' in lua
    print(f'nospaceport: the Spaceport Assault and its Retake switched off in {mod}; {gone} ini sections gone')


if __name__ == '__main__':
    main(sys.argv[1])
