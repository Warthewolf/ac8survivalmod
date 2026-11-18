#!/bin/sh
# solo_test.sh : the solo nerf of 2026-11-18 (sv_core.lua soloVal; THE ESCORT's and the INVINCIBLE FLEET's solo values)
# on build/checks/lua.exe (tools/checks/lua_build.sh makes it): tools/checks/solo_test.lua
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
"$HERE/../../build/checks/lua.exe" solo_test.lua "$HERE/../../mod"
