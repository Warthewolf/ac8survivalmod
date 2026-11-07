#!/bin/sh
# coop_ground_test.sh : runs tools/checks/coop_ground_test.lua (Survival COOP's ships, vehicles and parts linked between
# games: landing craft, the Alicorn and a joiner who started over) as a host, then a joiner fed what the host sent,
# with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/ground"
rm -rf "$W"
for r in host join; do mkdir -p "$W/$r/Scripts" "$W/$r/config"; cp ../../mod/UE4SS/AC8SurvivalMode/config/survival.default.ini "$W/$r/config/"; done
"$LUA" coop_ground_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W" host
"$LUA" coop_ground_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W" join
