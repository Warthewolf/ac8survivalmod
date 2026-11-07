#!/bin/sh
# economy_test.sh : runs tools/checks/economy_test.lua (0.73.78: the economy proposal's C3-C6, approved 2026-11-03, and
# the airstrike's limits, plan G6) on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
# The revives' price by the round (C6) is in coop_revive_test.sh, the settings' leaderboard check in leaderboard_test.sh.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/economy"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" economy_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
