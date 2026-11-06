#!/bin/sh
# leaderboard_test.sh : runs tools/checks/leaderboard_test.lua (the leaderboard's edited-run check, LB.edited, and what a
# run sends, on the real sv_core / sv_config / sv_leaderboard / sv_menu / sv_coop) with build/checks/lua.exe
# (tools/checks/lua_build.sh makes it): once as a plain install, then with a Scripts/survival_config.lua that returns a
# table, then with one that fails, then (code review of 2026-11-07) with the shipped rotation line uncommented.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/leaderboard"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
for mode in plain override override_error rotation; do
    "$LUA" leaderboard_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W" $mode
done
# (0.73.77, plan H5) every run body the plain run sent, co-op runs too, through the Worker's own checkRun
if command -v node > /dev/null 2>&1; then
    node leaderboard_bodies.mjs "$W/bodies.txt"
else
    echo "leaderboard bodies: node not found; the Worker's checkRun not run on them"
fi
