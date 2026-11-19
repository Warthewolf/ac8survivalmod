#!/bin/sh
# plugins_coop_test.sh : runs tools/checks/plugins_coop_test.lua (the add-on API's co-op, API 2.1: Scripts/sv_plugins.lua
# and its pieces in two to four simulated games on one star network) with build/checks/lua.exe (tools/checks/lua_build.sh
# makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
"$LUA" plugins_coop_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode"
