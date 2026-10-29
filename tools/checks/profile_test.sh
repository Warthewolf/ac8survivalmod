#!/bin/sh
# profile_test.sh : runs tools/checks/profile_test.lua (the behaviour roadmap's P6, the learning layer:
# tools/re/BEHAVIOUR_DIRECTOR.md unit 8; your habits from your kills and flying, the counters they turn and where each
# acts, the AI's flare row from the saved profile, config/survival_profile.ini written and read back, a checkpoint learnt
# from after a crash, broken files, min_samples, the real sweep's samples; the code review of 2026-10-29: each kill
# share on its own count, a co-op joiner's head start, the file never lost) on the real parts with build/checks/lua.exe
# (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/profile"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" profile_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
# the log parser (stats_report.py) on the lines the test wrote
python -X utf8 -I stats_report.py "$W/test_lua.log" > "$W/report.txt"
for want in "learning lines: " "runs over 17 (learnt from 12)" "0.95*  0.60*  0.94*  0.80*    0.70*" \
            "learning: the AI's flares refilled this session (your saved missile share 0.95"; do
    grep -qF "$want" "$W/report.txt" || { echo "stats_report: FAILED: '$want' not in $W/report.txt"; exit 1; }
done
echo "stats_report: the learning lines read"
