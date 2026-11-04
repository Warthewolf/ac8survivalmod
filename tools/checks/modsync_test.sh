#!/bin/sh
# modsync_test.sh : runs tools/checks/modsync_test.lua (0.73.80: the other players' modded planes and skins, shown where
# installed, a stock fallback where not: each game sends its plane's class path and stock base, every other game loads
# it if it's a player plane installed there, else the base / [coop.real_fallback] / [coop] real_default / the AI
# stand-in; a skin id a game hasn't is the plane's default paint there) on the real sv_config.lua and sv_coop.lua with
# build/checks/lua.exe (tools/checks/lua_build.sh makes it). One windowless process.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/modsync"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
cp ../../mod/UE4SS/AC8SurvivalMode/config/survival.default.ini "$W/config/"
"$LUA" modsync_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
