#!/bin/sh
# coop_guard_test.sh : runs tools/checks/coop_guard_test.lua (a hostile-message suite for co-op's Lua layer: every
# message type the host and a joiner handle, fed bad fields, cut short, padded, flooded; AGENTS.md "Guards on what other
# games send") on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it). Pure Lua: the same on
# Windows and elsewhere. Its work folder (the parts' Scripts\ and config\ as the game has them) is build/checks/coop_guard/.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/coop_guard"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
cp "$HERE/../../mod/UE4SS/AC8SurvivalMode/config/"* "$W/config/"
rm -f "$W/config/survival.ini"
"$LUA" coop_guard_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
