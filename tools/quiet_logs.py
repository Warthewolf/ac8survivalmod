"""quiet_logs.py <stage mod folder> : the diagnostic loggers off in a friends' build (tools/package_release.sh runs it on
every release stage; the user's dev install keeps them: tools/package_dev.sh doesn't). A friend's report of 2026-10-31
("choppy" and stuttering in solo play): the enemy weapons log (Scripts/sv_weaponlog.lua) looks at every weapon object in
the world every 0.5 s, 19 ms of each 250 ms tick in the user's Spaceport rounds (half the tick); the audit
(Scripts/sv_audit.lua) samples every enemy's target. On the staged copies only, never the sources:
  - Scripts/sv_config.lua: CFG.log.weapons.enabled and CFG.log.audit.enabled false
  - config/survival.default.ini: their `;enabled = true` lines say false
A player's own survival.ini can still turn them on ([log.weapons] / [log.audit] enabled = true).
"""
import os
import sys


def sub(s, old, new, what):
    assert s.count(old) == 1, f'{what}: {s.count(old)} matches for {old!r}'
    return s.replace(old, new)


def main(mod):
    p = os.path.join(mod, 'Scripts', 'sv_config.lua')
    s = open(p, encoding='utf-8', newline='').read()
    s = sub(s, 'weapons = { enabled = true, every_s = 0.5,', 'weapons = { enabled = false, every_s = 0.5,', 'sv_config log.weapons')
    s = sub(s, 'audit = { enabled = true, sample_s = 5,', 'audit = { enabled = false, sample_s = 5,', 'sv_config log.audit')
    open(p, 'w', encoding='utf-8', newline='').write(s)
    p = os.path.join(mod, 'config', 'survival.default.ini')
    s = open(p, encoding='utf-8', newline='').read()
    for sec in ('[log.weapons]', '[log.audit]'):
        a = s.index(sec)
        b = s.find('\n[', a + 1)
        b = len(s) if b < 0 else b
        part = s[a:b]
        assert part.count(';enabled   = true') == 1, f'ini {sec}: its enabled line'
        s = s[:a] + part.replace(';enabled   = true', ';enabled   = false') + s[b:]
    open(p, 'w', encoding='utf-8', newline='').write(s)
    print(f'quiet_logs: the weapons log and the audit off in {mod}')


if __name__ == '__main__':
    main(sys.argv[1])
