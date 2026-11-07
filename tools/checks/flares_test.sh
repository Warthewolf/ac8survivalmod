#!/bin/sh
# flares_test.sh : runs tools/checks/flares_test.lua (2026-11-07: FLARE PODS and the flares bought past the stock load,
# put back after the game's take-off reload, never taken for shots; sv_flights.lua ammoTick, sv_tactical.lua UP.apply) on
# the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/flares"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" flares_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
