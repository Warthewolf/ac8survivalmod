#!/bin/sh
# spaceport_test.sh : runs tools/checks/spaceport_test.lua (the Spaceport Assault and its retake, Scripts/sv_spaceport.lua)
# on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/spaceport"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" spaceport_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
