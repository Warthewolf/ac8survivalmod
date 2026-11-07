#!/bin/sh
# copy_floor_test.sh : runs tools/checks/copy_floor_test.lua (0.73.77: the enemy copy desync, plan Workstream A1-A3, A6,
# A9, and the joiners' kill pay, economy C1; the logs of 0.73.76, 2026-11-02) as a host, then a joiner, with
# build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/copy_floor"
rm -rf "$W"
for r in host join; do mkdir -p "$W/$r/Scripts" "$W/$r/config"; cp ../../mod/UE4SS/AC8SurvivalMode/config/survival.default.ini "$W/$r/config/"; done
"$LUA" copy_floor_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W" host
"$LUA" copy_floor_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W" join
