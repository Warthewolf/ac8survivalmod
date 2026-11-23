#!/bin/sh
# ulysses_test.sh : ULYSSES (Scripts/sv_ulysses.lua, 2026-11-23) on build/checks/lua.exe (tools/checks/lua_build.sh
# makes it): tools/checks/ulysses_test.lua
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
"$HERE/../../build/checks/lua.exe" ulysses_test.lua "$HERE/../../mod"
