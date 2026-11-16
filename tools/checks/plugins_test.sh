#!/bin/sh
# plugins_test.sh : runs tools/checks/plugins_test.lua (the add-on API, Scripts/sv_plugins.lua, and the example add-on
# examples/addons/target_practice) with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
"$LUA" plugins_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$HERE/../../examples/addons/target_practice"
