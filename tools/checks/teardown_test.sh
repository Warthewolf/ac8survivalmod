#!/bin/sh
# teardown_test.sh : runs tools/checks/teardown_test.lua (0.73.73: the level going away, the testers' logs of 0.73.70:
# kills paid as a quit to the main menu destroyed the planes, and the crashes in UE4SS's FindAllOf over freed objects;
# sv_core.lua levelGoing / walkHold, sv_main.lua's sweep and run's end) on the real parts with build/checks/lua.exe
# (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/teardown"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" teardown_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
