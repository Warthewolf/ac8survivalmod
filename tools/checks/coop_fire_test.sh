#!/bin/sh
# coop_fire_test.sh : runs tools/checks/coop_fire_test.lua (Survival COOP's weapon, gear and afterburner sync: the user's
# "work out aircraft syncing, such as missiles being fired" and "their gear doesn't deploy on my screen, nor do I see
# their afterburners", 2026-10-29; sv_coop.lua's sync, tools/re/COOP.md 8) on the real parts with build/checks/lua.exe
# (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/coop_fire"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" coop_fire_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
