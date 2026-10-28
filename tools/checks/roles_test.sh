#!/bin/sh
# roles_test.sh : runs tools/checks/roles_test.lua (the behaviour roadmap's P1, fighter roles:
# tools/re/BEHAVIOUR_DIRECTOR.md unit 5; the role scripts walked through every pick, the rows at the main menu, the draw
# by role mix, each role's airframes, altitude and tells, the Wolf trap, the Skirmishers' health) on the real parts and
# Scripts/ai with build/checks/lua.exe (tools/checks/lua_build.sh makes it), then the build side's split
# (tools/survival_events.py: the groups, each Wolf object's row, the Lancers' band).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/roles"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" roles_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
python -X utf8 -I - "$HERE/.." <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import survival_events as s
fails = 0
def check(ok, what):
    global fails
    print(('  ok   ' if ok else '  FAIL ') + what)
    if not ok: fails += 1
size = {u: s.flight_size(u) for u in s.POOL}
usable = [u for u in s.POOL if u not in s.PROBE_UNITS.values()]
by = {}
for u in usable: by[s.POOL_ROLE[u]] = by.get(s.POOL_ROLE[u], 0) + size[u]
check(by == {'duelist': 24, 'lancer': 24, 'wolf': 24, 'skirm': 14}, f'the pool split by flight number: {by} (86 usable)')
check(all(s.behaviour_row(u) == s.ROLE_ROW[s.POOL_ROLE[u]] for u in usable), "each usable flight names its role's behaviour row")
check(all(s.behaviour_row(u) in s.PROBE_ROWS.values() for u in s.PROBE_UNITS.values()), 'the probe flights keep their own rows')
wolf = [u for u in usable if s.POOL_ROLE[u] == 'wolf']
check(all(s.behaviour_rows(u, k) == (s.WOLF_WING_ROW if k % 2 else s.ROLE_ROW['wolf']) for u in wolf for k in range(size[u])),
      'a Wolf flight: even objects the bait row, odd ones the trap row')
check(all(s.behaviour_rows(u, k) == s.behaviour_row(u) for u in usable if s.POOL_ROLE[u] != 'wolf' for k in range(6)),
      'every other flight: one row for all its objects')
check(sum(size[u] // 2 for u in wolf) == 12, 'the Wolf trap: 12 held objects (36 events)')
check(set(s.ROLE_NPC) == {s.ROLE_ROW[r] for r in ('lancer', 'wolf', 'skirm')} | {s.WOLF_WING_ROW}, 'the role rows the build adds')
check(s.LANCER_MAX_ALT_M == 9000.0, 'the Lancers band tops out at 9 km')
print('roles build: all passed' if not fails else f'roles build: {fails} FAILED')
sys.exit(1 if fails else 0)
EOF
