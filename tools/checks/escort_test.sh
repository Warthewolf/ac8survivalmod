#!/bin/sh
# escort_test.sh : runs tools/checks/escort_test.lua (THE ESCORT and the ZFA-44 carriers, 2026-11-06: Scripts/sv_escort.lua,
# the STORE's ZfaCarrier, sv_zfa44.lua's production dressing) on the real parts with build/checks/lua.exe
# (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/escort"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" escort_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
