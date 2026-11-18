# no_test_keys.py <mod folder> : a staged copy's test keys switched off (tools/package_release.sh FRIENDS=1 TANI=1).
# The user, 2026-11-18: "Everyone gets the invincible fleet level", "But only alyssa has the keys that activate it for
# everyone". Round 30's INVINCIBLE FLEET is test-only code, so a friends' zip with it is staged as a tester's (every test-only
# block kept: round 30 and what it needs in the other parts) and then has its keys taken off here:
#   sv_main.lua: its test keys' block (the forced specials Ctrl+1-0, zollars, ...) cut whole;
#   sv_core.lua: testKey() binds nothing (every part's test key goes through it), its own Ctrl+F11 not bound.
# Then checked: no test-only block left that binds a key another way. Exit 1 on anything left (no zip is made).
# Round 30 still comes by itself at a run's round 30 (sv_fleet_round.lua specialFor); a tester's zip of the same build (same
# version) links in co-op and its host's keys work for everyone.
import os
import re
import sys

BLOCK = re.compile(r'[ \t]*-- TEST ONLY BEGIN[^\n]*\n.*?-- TEST ONLY END[^\n]*\n', re.S)
KEYS_ANCHOR = 'local TEST_SPECIALS = {'
TESTKEY = 'function testKey(name, who, fn)\n'
TESTKEY_OFF = TESTKEY + '    do return false end                                   -- (no test keys in this zip: tools/no_test_keys.py)\n'
F11 = 'if type(RegisterKeyBind) == "function" and Key and Key.F11 then\n'
F11_OFF = 'if false then                                             -- (no test keys in this zip: tools/no_test_keys.py)\n'


def read(p):
    return open(p, encoding='utf-8', newline='').read().replace('\r\n', '\n')


def main(mod):
    scripts = os.path.join(mod, 'Scripts')
    bad = []
    p = os.path.join(scripts, 'sv_main.lua')
    s = read(p)
    hits = [m for m in BLOCK.finditer(s) if KEYS_ANCHOR in m.group(0)]
    if len(hits) != 1:
        bad.append(f'sv_main.lua: {len(hits)} test-only blocks with its test keys (one expected)')
    else:
        m = hits[0]
        s = s[:m.start()] + s[m.end():]
        open(p, 'w', encoding='utf-8', newline='').write(s)
        print('no_test_keys: sv_main.lua: its test keys\' block cut')
    p = os.path.join(scripts, 'sv_core.lua')
    s = read(p)
    for o, n_, what in ((TESTKEY, TESTKEY_OFF, 'testKey() binds nothing'), (F11, F11_OFF, 'its Ctrl+F11 not bound')):
        if s.count(o) != 1:
            bad.append(f'sv_core.lua: no single "{o.strip()}" ({what} NOT done)')
        else:
            s = s.replace(o, n_)
            print(f'no_test_keys: sv_core.lua: {what}')
    open(p, 'w', encoding='utf-8', newline='').write(s)
    # what's left: a test-only block binding a key itself (not through testKey) anywhere but sv_core's dead ones
    for name in sorted(os.listdir(scripts)):
        if not name.endswith('.lua'):
            continue
        t = read(os.path.join(scripts, name))
        if name == 'sv_core.lua':                         # (its two: switched off by the exact replacements above)
            continue
        for m in BLOCK.finditer(t):
            b = m.group(0)
            if re.search(r'pcall\(RegisterKeyBind|RegisterKeyBind\(', b):
                bad.append(f'{name}:{t.count(chr(10), 0, m.start()) + 1}: a test-only block still binds a key')
    if bad:
        sys.exit('no_test_keys: test keys NOT all off:\n  ' + '\n  '.join(bad))
    print('no_test_keys: every test key off (round 30 still comes at a run\'s round 30)')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('usage: no_test_keys.py <mod folder (holding Scripts/)>')
    main(sys.argv[1])
