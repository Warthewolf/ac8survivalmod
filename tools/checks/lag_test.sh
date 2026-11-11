#!/bin/sh
# lag_test.sh : runs tools/checks/lag_test.lua (Saint Alessia's 50-round co-op run's lag fixes in the allies part,
# 2026-11-11: the round clear's repair and the defences' actors from the objects kept at their spawn, no walk; VOID
# WATCHER's ESM fields read a slice a tick) on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes
# it). ALIVE's time budget is in rounds_test.sh, the native unit table in unittab_test.sh.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/lag"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" lag_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
