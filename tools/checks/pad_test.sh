#!/bin/sh
# pad_test.sh : runs tools/checks/pad_test.lua (the shuttle's whole pad taken off after liftoff; user, 2026-10-30:
# "spaceport did not despawn after shuttle round") on the real parts with build/checks/lua.exe
# (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/pad"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" pad_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
