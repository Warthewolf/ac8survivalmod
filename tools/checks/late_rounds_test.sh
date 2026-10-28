#!/bin/sh
# late_rounds_test.sh : runs tools/checks/late_rounds_test.lua (the behaviour roadmap's P8, late rounds:
# tools/re/BEHAVIOUR_DIRECTOR.md unit 3; the thesis' table, startRound's budgets and waves, the attack throttle, the
# director kill bonus) on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/late"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" late_rounds_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
