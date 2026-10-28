#!/bin/sh
# stats_test.sh : runs tools/checks/stats_test.lua (the behaviour roadmap's foundations, tools/re/BEHAVIOUR_DIRECTOR.md
# unit 1: the per-plane spawn index, the measurements' maths and lines, COOP.players) on the real parts with
# build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/stats"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" stats_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
