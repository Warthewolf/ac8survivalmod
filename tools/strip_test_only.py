# strip_test_only.py <main.lua> : takes main.lua's test-only code (-- TEST ONLY BEGIN ... -- TEST ONLY END: the dev
# keys that open the map, give zollars or pick the next special) out of a copy being packed for other players
# (tools/package_test.sh). Fails if any of it is left.
import re
import sys

p = sys.argv[1]
s = open(p, encoding='utf-8').read()
n = s.count('TEST ONLY BEGIN')
s = re.sub(r'[ \t]*-- TEST ONLY BEGIN.*?-- TEST ONLY END[^\n]*\n', '', s, flags=re.S)
LEFT = ('TEST ONLY', 'Key.F8', 'Key.F9', 'Key.SIX', 'TEST_SPECIALS', 'forceSpecial = kind', 'openSurvival', 'addCredits(5000')
if not n or any(x in s for x in LEFT):
    sys.exit('strip_test_only: test-only code left in ' + p)
open(p, 'w', encoding='utf-8', newline='').write(s)
print(f'test-only blocks taken out: {n}')
