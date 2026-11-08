#!/bin/sh
# dive_test.sh : runs tools/checks/dive_test.lua (the VAMPIRES' final dive, Scripts/sv_escort_dive.lua; user, 2026-11-08:
# "these ZFA-44's will last 3 rounds before they fly towards the nearest enemy aircraft and explode") on the real part
# with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
"$LUA" dive_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode"
