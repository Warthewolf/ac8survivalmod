#!/bin/sh
# bays_swap_test.sh : runs tools/checks/bays_swap_test.lua (2026-11-14: WEAPON BAYS after a special weapon swapped in the
# hangar, NotMexi's log of 0.74.36; sv_flights.lua ammoTick, sv_tactical.lua UP.apply) on
# the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/bays_swap"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" bays_swap_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
