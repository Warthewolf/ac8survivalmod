#!/bin/sh
# coop_revive_test.sh : runs tools/checks/coop_revive_test.lua (Survival COOP's revives and the spectator camera: the
# user's "is there a revive option we could possibly add for COOP only? ... you get put into a spectator camera and you
# can switch between the players currently active", 2026-10-29; sv_down.lua, tools/re/COOP.md 9) on the real parts with
# build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/coop_revive"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" coop_revive_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
