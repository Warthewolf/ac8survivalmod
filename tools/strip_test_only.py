# strip_test_only.py <main.lua> : takes main.lua's test-only code (-- TEST ONLY BEGIN ... -- TEST ONLY END, e.g. the
# +5000 zollars key) out of a copy being packed for other players (tools/package_test.sh). Fails if any is left.
import re
import sys

p = sys.argv[1]
s = open(p, encoding='utf-8').read()
n = s.count('TEST ONLY BEGIN')
s = re.sub(r'[ \t]*-- TEST ONLY BEGIN.*?-- TEST ONLY END[^\n]*\n', '', s, flags=re.S)
if not n or 'TEST ONLY' in s or 'Ctrl+F9' in s:
    sys.exit('strip_test_only: test-only code left in ' + p)
open(p, 'w', encoding='utf-8', newline='').write(s)
print(f'test-only blocks taken out: {n}')
