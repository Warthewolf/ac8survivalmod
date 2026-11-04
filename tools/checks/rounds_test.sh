#!/bin/sh
# rounds_test.sh : runs tools/checks/rounds_test.lua (0.73.80: the units' alive answers spread over the ticks, the
# shuttle's unit off the spawner's list, the specials' pacing; Scripts/sv_spawn.lua, sv_rounds.lua) on the real parts
# with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/rounds"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" rounds_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
