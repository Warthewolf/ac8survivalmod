#!/bin/sh
# stats_test.sh : runs tools/checks/stats_test.lua (the behaviour roadmap's foundations, tools/re/BEHAVIOUR_DIRECTOR.md
# unit 1: the per-plane spawn index, the measurements' maths and lines, their hooks, COOP.players) on the real parts with
# build/checks/lua.exe (tools/checks/lua_build.sh makes it), then tools/checks/stats_report.py on the lines it logged.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/stats"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" stats_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
# the log parser (stats_report.py) on the lines the test wrote
python -X utf8 -I stats_report.py "$W/test_lua.log" > "$W/report.txt"
for want in "12 s (n 3)" "25% (1/4)" "LOW" "every run: median 10 s (n 4)" "director lines: 1: cover x1" \
            "can't tell: lead and wings fly one blueprint" "co-op resync" "run 3 (the host started over), rounds 1-8"; do
    grep -qF "$want" "$W/report.txt" || { echo "stats_report: FAILED: '$want' not in $W/report.txt"; exit 1; }
done
echo "stats_report: all passed"
