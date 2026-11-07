#!/bin/sh
# tailed_test.sh : runs tools/checks/tailed_test.lua (P5, a harder tailed plane: tools/re/BEHAVIOUR_DIRECTOR.md unit 2;
# the reaction trees walked through every pick, the live provoke's merge and writes, the tail watch) on the real parts
# and Scripts/ai with build/checks/lua.exe (tools/checks/lua_build.sh makes it), then tools/checks/stats_report.py on
# the lines it logged.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/tailed"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" tailed_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
# the log parser (stats_report.py) on the lines the test wrote
python -X utf8 -I stats_report.py "$W/test_lua.log" > "$W/report.txt"
for want in "tail watch Veteran+ (4 Hz): died, tailed     3.0 s (n 3); 8.0 s after Provoke (n 1)" \
            "2 (held 2.5 s); still up 1" "1.5 s; none 4; already 1; blackouts 0" "3.0 s    0/0" "tailed lines: 6" \
            "60 deg / 1.5 s (Survival's)          6    3       3.0 s       2   1         1.5 s    4       1 0" \
            "provoke lines: 1"; do
    grep -qF "$want" "$W/report.txt" || { echo "stats_report: FAILED: '$want' not in $W/report.txt"; cat "$W/report.txt"; exit 1; }
done
echo "stats_report: the tail watch's lines read"
