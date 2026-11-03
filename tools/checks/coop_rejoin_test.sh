#!/bin/sh
# coop_rejoin_test.sh : runs tools/checks/coop_rejoin_test.lua (0.73.77, plan workstreams C and D: a player who left and
# comes back in another aircraft gets a new plane on every game, the old one set aside, never destroyed; VALKA's mood on
# every joiner from every way she starts and ends, again for one who resyncs; a joiner's special-round music the host's)
# on the real sv_config.lua and sv_coop.lua (and sv_anomalies.lua's mood functions) with build/checks/lua.exe
# (tools/checks/lua_build.sh makes it). One windowless process.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/rejoin"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
cp ../../mod/UE4SS/AC8SurvivalMode/config/survival.default.ini "$W/config/"
"$LUA" coop_rejoin_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
