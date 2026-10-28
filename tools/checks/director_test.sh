#!/bin/sh
# director_test.sh : runs tools/checks/director_test.lua (the behaviour roadmap's P2, the squad director:
# tools/re/BEHAVIOUR_DIRECTOR.md unit 6; its six tactics' triggers on stubbed planes: geometry, cooldowns, budgets, tells
# first, the co-op paths and "dv" guards) on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes
# it), then the build side's names (tools/survival_events.py SALVO_SLOT against the Lua's).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/director"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" director_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
python -X utf8 -I - "$HERE/.." <<'EOF'
import re, sys
sys.path.insert(0, sys.argv[1])
import survival_events as s
fails = 0
def check(ok, what):
    global fails
    print(('  ok   ' if ok else '  FAIL ') + what)
    if not ok: fails += 1
lua = s.runtime_lua()
m = re.search(r'SALVO_FCS_SLOT\s*=\s*(\d+)', lua)
check(m and int(m.group(1)) == 2 and s.SALVO_SLOT == 'WN_WEAPON_3', 'the salvo: fire-control slot 2 = WN_WEAPON_3 on both sides')
check(all(f in lua for f in ('"RE_SV_Salvo_%02d%s"', '"RE_SV_DirHold_%02d"', '"RE_SV_DirFree_%02d"')), "the director's event names in the Lua")
coop = open(sys.argv[1] + '/../mod/UE4SS/AC8SurvivalMode/Scripts/sv_coop.lua', encoding='utf-8').read()
keep = re.search(r'local KEEP_EVENTS = \{(.*?)\n\}', coop, re.S)
check(keep and '"^RE_SV_Salvo_"' in keep.group(1) and '"^RE_SV_Dir' not in keep.group(1),
      'KEEP_EVENTS: the salvo kept, the holds forwarded')
usable = [u for u in s.POOL if u not in s.PROBE_UNITS.values()]
check(sum(s.flight_size(u) for u in usable) == 86, '86 salvo objects in the 22 usable flights; 24 flights held / freed')
print('director build: all passed' if not fails else f'director build: {fails} FAILED')
sys.exit(1 if fails else 0)
EOF
