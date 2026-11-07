#!/bin/sh
# arc_rounds_test.sh : runs tools/checks/arc_rounds_test.lua (0.74.0: GONE FISHIN', the day-night arc and THE FESTIVAL in
# the real rounds and in co-op: the dice, the festival's round, VALKA's gate, startRound, the Alicorn's rows, the co-op
# messages) on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/arc_rounds"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" arc_rounds_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
