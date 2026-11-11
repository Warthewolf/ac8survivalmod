# strip_test_only.py [--dev-only] <file.lua> ... : takes the runtime's test-only code out of copies being packed for
# other players (tools/package_test.sh, package_release.sh: Scripts/main.lua and its parts sv_*.lua, tools/lua_split.py;
# the default ini's test-only sections too):
#   -- TEST ONLY BEGIN ... -- TEST ONLY END   the dev keys that open the map, give zollars or pick the next special:
#                                             out of every zip but a TESTER=1 one
#   -- DEV ONLY BEGIN ... -- DEV ONLY END     the user's own dev install only (tools/package_dev.sh keeps it): out of
#                                             EVERY zip, a TESTER=1 one included (the user, 2026-11-11: THE TANICORN's
#                                             test mount; round 30's INVINCIBLE FLEET, AGENTS.md: "never in a release or
#                                             TESTER zip"). A DEV ONLY block may use the test keys and ticks (testKey,
#                                             TEST_TICKS): every build that keeps it keeps those.
# Default: both kinds out; fails if there was no TEST ONLY block in them all, or if any of either is left in any.
# --dev-only (package_release.sh with TESTER=1): only the DEV ONLY blocks out; fails if any is left.
import re
import sys

args = sys.argv[1:]
dev_only = '--dev-only' in args
files = [a for a in args if a != '--dev-only']
LEFT = ('TEST ONLY', 'Key.F8', 'Key.F9', 'Key.SIX', 'Key.NINE', 'Key.ZERO', 'TEST_SPECIALS', 'forceSpecial = kind', 'openSurvival', 'addCredits(5000')
DEV_LEFT = ('DEV ONLY',)
total, dev, left = 0, 0, []
for p in files:
    s = open(p, encoding='utf-8').read()
    dev += s.count('DEV ONLY BEGIN')
    s = re.sub(r'[ \t]*-- DEV ONLY BEGIN.*?-- DEV ONLY END[^\n]*\n', '', s, flags=re.S)
    left += [f'{p}: {x}' for x in DEV_LEFT if x in s]
    if not dev_only:
        total += s.count('TEST ONLY BEGIN')
        s = re.sub(r'[ \t]*-- TEST ONLY BEGIN.*?-- TEST ONLY END[^\n]*\n', '', s, flags=re.S)
        left += [f'{p}: {x}' for x in LEFT if x in s]
    open(p, 'w', encoding='utf-8', newline='').write(s)
if left or (not dev_only and not total):
    sys.exit('strip_test_only: ' + ('test-only code left: ' + '; '.join(left) if left else 'no test-only blocks found'))
if dev_only:
    print(f'dev-only blocks taken out: {dev} (in {len(files)} files; the TEST ONLY ones kept)')
else:
    print(f'test-only blocks taken out: {total}, dev-only {dev} (in {len(files)} files)')
