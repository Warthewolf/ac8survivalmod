#!/bin/sh
# decoy_test.sh : runs tools/checks/decoy_test.lua (THE DECOY, Scripts/sv_decoy.lua: the bait, the trap's spawns, the
# closest player, the 8 s and its cancels, the Spear and its lead, the end, co-op's "dk" and KEEP_EVENTS) on the real
# parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/decoy"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" decoy_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
