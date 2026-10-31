#!/bin/sh
# spweapons_test.sh : runs tools/checks/spweapons_test.lua (the enemies' special weapons fired, Scripts/sv_spweapons.lua)
# on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/spweapons"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" spweapons_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
