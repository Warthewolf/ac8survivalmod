#!/bin/sh
# alicorn_test.sh : runs tools/checks/alicorn_test.lua (the Alicorn in co-op after Saint Alessia's 50-round run: its core's
# health on every game's row and in callouts, its size by the players flying as it opens, its hits and the joiners' logged, a rejoiner's copy at the host's hull on the
# right leg, a joiner's surfacing check, the host's health for copies bound late, the replay held for its copy) on the real
# parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it). The build's half (the legs' paths, the lane in step
# with the Lua) is tools/checks/bosses_build_check.py's, which bosses_test.sh runs.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/alicorn"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" alicorn_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
