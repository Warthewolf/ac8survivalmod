# dev_only.py <mod folder> : the user's dev install's own Lua parts cut out of a TESTER zip's staged copy
# (tools/package_release.sh TESTER=1, which keeps every other part's test-only code: the test keys and loggers a tester
# uses). Round 30's INVINCIBLE FLEET and its boss THE TANICORN are the user's dev install only (AGENTS.md; the user,
# 2026-11-10: "Keep it dev install only"): their Lua is test-only, never in a release or TESTER zip. Their units and rows
# are in every build's world data and tables, so a part left whole would spawn them (Ctrl+N: the whole fleet; the review
# of 8ca3195, finding 2). Each part here is cut to its release text (strip_test_only.py's cut: only its header comment is
# left; main.lua still loads it), then the whole staged Scripts folder is checked: none of their globals or keys left in
# any part, and nothing but comments in theirs. Exit 1 on anything left (the zip isn't made).
import os
import re
import sys

DEV_ONLY = ('sv_tanicorn.lua', 'sv_fleet.lua', 'sv_cine.lua')   # (main.lua MODULES: THE TANICORN, the fleet, the rise's cinematic)
GLOBALS = ('TANI', 'GEO', 'IFLEET', 'CINE')                     # (what they define; other parts only test them for nil)
BLOCK = re.compile(r'[ \t]*-- (TEST|DEV) ONLY BEGIN.*?-- \1 ONLY END[^\n]*\n', re.S)   # (DEV ONLY: the cloud line's markers)


def main(mod):
    scripts = os.path.join(mod, 'Scripts')
    bad = []
    for name in DEV_ONLY:
        p = os.path.join(scripts, name)
        if not os.path.exists(p):
            bad.append(f'{name}: not in the staged copy (main.lua loads it: a missing part stops the runtime)')
            continue
        s = open(p, encoding='utf-8').read()
        n = s.count('TEST ONLY BEGIN') + s.count('DEV ONLY BEGIN')
        if not n:
            bad.append(f'{name}: no TEST ONLY block (the part changed shape: cut it by hand and fix this tool)')
            continue
        s = BLOCK.sub('', s)
        code = [ln for ln in s.splitlines() if ln.strip() and not ln.strip().startswith('--')]
        if code:
            bad.append(f'{name}: code outside its test-only blocks: {code[0][:80]!r}')
        open(p, 'w', encoding='utf-8', newline='').write(s)
        print(f'dev_only: {name} cut to its header ({n} test-only block{"s" if n > 1 else ""} out, {len(s.splitlines())} lines left)')
    assign = re.compile(r'^\s*(' + '|'.join(GLOBALS) + r')\s*=(?!=)', re.M)
    for name in sorted(os.listdir(scripts)):
        if not name.endswith('.lua'): continue
        s = open(os.path.join(scripts, name), encoding='utf-8').read()
        for m in assign.finditer(s):
            bad.append(f'{name}: {m.group(1)} still defined (line {s.count(chr(10), 0, m.start()) + 1})')
        if 'CFG.specials.fleet =' in s:
            bad.append(f'{name}: CFG.specials.fleet still set')
        if name in DEV_ONLY and ('testKey(' in s or 'TEST_TICKS' in s):
            bad.append(f'{name}: a test key or tick left')
    if bad:
        sys.exit('dev_only: the dev install\'s parts NOT out of the copy:\n  ' + '\n  '.join(bad))
    print(f'dev_only: none of {", ".join(GLOBALS)} left in any part of {scripts}')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('usage: dev_only.py <mod folder (holding Scripts/)>')
    main(sys.argv[1])
