#!/bin/sh
# aces_test.sh : runs tools/checks/aces_test.lua (the behaviour roadmap's P9, ace personalities: tools/re/BEHAVIOUR_DIRECTOR.md
# unit 10; each squadron's role mix, openers at first contact after its tell, Wraith's and Harvest's blinks, co-op) on the
# real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it), then the build side's blink events
# (tools/survival_events.py WRAITH_BLINK_* and wraith_blinks against the Lua's ACE.BLINK) without the game.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/aces"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" aces_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
# the log report reads the squadrons' lines (tools/checks/stats_report.py squad_lines)
python -X utf8 -I stats_report.py "$W/test_lua.log" > "$W/report.txt"
if grep -q "squadron lines: .* first contacts, .* blinks" "$W/report.txt" && grep -q "Wraith .* blink x" "$W/report.txt" &&
   grep -q "blinks: on its six x" "$W/report.txt"; then
    echo "aces report: all passed"
else
    echo "aces report: FAILED"; exit 1
fi
python -X utf8 -I - "$HERE/.." <<'PY'
import re, sys
sys.path.insert(0, sys.argv[1])
import survival_events as s
fails = 0
def check(ok, what):
    global fails
    print(('  ok   ' if ok else '  FAIL ') + what)
    if not ok: fails += 1
lua = s.runtime_lua()
m = re.search(r'BLINK = \{ STEP_DEG = (\d+), RING_M = (\d+), ROLE = "(\w+)" \}', lua)
check(m and (int(m.group(1)), int(m.group(2)), m.group(3)) == (s.WRAITH_BLINK_STEP_DEG, s.WRAITH_BLINK_RING_M, s.WRAITH_BLINK_ROLE),
      'ACE.BLINK (Lua) = WRAITH_BLINK_* (45 deg, 1000 m, the duelists)')
b = s.wraith_blinks()
units = sorted({u for u, _, _ in b})
check(len(b) == 48 and units == [f'ERA_Unit_0{n}_Dep_Air{k}' for n in (1, 2) for k in range(3)],
      f'48 blink events: 8 spots for each of the 6 duelist flights\' leads ({len(b)}, {len(units)} flights)')
check(all(re.fullmatch(r'RE_SV_WraithBlink[A-X][A-H]', e) for _, e, _ in b) and len({e for _, e, _ in b}) == len(b),
      'their names: letters only (hard rule 17), each once')
check(all(e[len('RE_SV_WraithBlink')] == chr(65 + s.POOL.index(u)) for u, e, _ in b), "K: the flight's pool index as a letter (Lua's poolIndex)")
check(sorted({d for _, _, d in b}) == list(range(0, 360, 45)), 'J: 0, 45 ... 315 deg (world, 0 = +X)')
check('"RE_SV_WraithBlink%s%s"' in lua and '"^RE_SV_WraithBlink"' in lua, 'the Lua fires them and co-op keeps them (KEEP_EVENTS)')
check(not any(u in s.PROBE_UNITS.values() for u in units), "none on the probe flights")
coop = open(sys.argv[1] + '/coop_edition.py', encoding='utf-8').read()
check("COOP_TAG = '-coop2mp.31'" in coop, 'tools/coop_edition.py COOP_TAG -coop2mp.31 (0.73.30: host migration, runtime 0.32.7)')
print('aces build: all passed' if not fails else f'aces build: {fails} FAILED')
sys.exit(1 if fails else 0)
PY
