#!/bin/sh
# menu_test.sh : runs tools/checks/menu_test.lua (Survival's menu pages and run setups, Scripts/sv_menu.lua, on the real
# sv_config.lua, sv_menu.lua and sv_coop.lua) with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/menu"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" menu_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
