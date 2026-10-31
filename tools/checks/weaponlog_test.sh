#!/bin/sh
# weaponlog_test.sh : runs tools/checks/weaponlog_test.lua (the enemy weapons log, Scripts/sv_weaponlog.lua)
# on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/weaponlog"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" weaponlog_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
