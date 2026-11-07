#!/bin/sh
# tick_loop_test.sh : runs tools/checks/tick_loop_test.lua (0.73.82: the tick loop's async function and the key presses
# do no Lua work off the game thread; a lost tick queued again with a back-off; Saint Alessia's crash on launch of
# 2026-11-04) on the real sv_main.lua and sv_core.lua with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
"$LUA" tick_loop_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode"
