#!/bin/sh
# intensity_test.sh : runs tools/checks/intensity_test.lua (the behaviour roadmap's P4, the intensity director:
# tools/re/BEHAVIOUR_DIRECTOR.md unit 7; its scores, the hold through the real roundsTick's gate, a push through the
# squad director, the spikes as a ceiling, the co-op "in" / "rnd" paths and their guards) on the real parts with
# build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/intensity"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" intensity_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
# the log report (stats_report.py) on the lines the test wrote: P4's part
python -X utf8 -I stats_report.py "$W/test_lua.log" > "$W/report.txt"
for want in "intensity lines: " "), pushes " "level eased " ", back up 2" "round  avg peak hot s comfort" "0 (spikes 1)"; do
    grep -qF "$want" "$W/report.txt" || { echo "stats_report: FAILED: '$want' not in $W/report.txt"; exit 1; }
done
echo "stats_report: the intensity lines read"
