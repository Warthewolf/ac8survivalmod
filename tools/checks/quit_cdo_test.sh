#!/bin/sh
# quit_cdo_test.sh : runs tools/checks/quit_cdo_test.lua (0.73.84: Shazzy's crash on quit of 2026-11-04, TAC.reset writing
# the gun's stock damage into its class default after the level's purge had freed it; VALKA's sky and the Ladon missile's
# class default the same way) on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/quit_cdo"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" quit_cdo_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
