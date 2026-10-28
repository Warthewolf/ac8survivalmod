# strip_test_only.py <file.lua> ... : takes the runtime's test-only code (-- TEST ONLY BEGIN ... -- TEST ONLY END: the
# dev keys that open the map, give zollars or pick the next special) out of copies being packed for other players
# (tools/package_test.sh, package_release.sh: Scripts/main.lua and its parts sv_*.lua, tools/lua_split.py). Fails if
# there was none in them all, or if any of it is left in any.
import re
import sys

LEFT = ('TEST ONLY', 'Key.F8', 'Key.F9', 'Key.SIX', 'Key.NINE', 'Key.ZERO', 'TEST_SPECIALS', 'forceSpecial = kind', 'openSurvival', 'addCredits(5000')
total, left = 0, []
for p in sys.argv[1:]:
    s = open(p, encoding='utf-8').read()
    n = s.count('TEST ONLY BEGIN')
    s = re.sub(r'[ \t]*-- TEST ONLY BEGIN.*?-- TEST ONLY END[^\n]*\n', '', s, flags=re.S)
    left += [f'{p}: {x}' for x in LEFT if x in s]
    open(p, 'w', encoding='utf-8', newline='').write(s)
    total += n
if not total or left:
    sys.exit('strip_test_only: ' + ('no test-only blocks found' if not total else 'test-only code left: ' + '; '.join(left)))
print(f'test-only blocks taken out: {total} (in {len(sys.argv) - 1} files)')
