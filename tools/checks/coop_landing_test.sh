#!/bin/sh
# coop_landing_test.sh : runs tools/checks/coop_landing_test.lua (the host down at the airfield in Survival COOP: the
# spawns, a flight's orders, the wave clock and the Wolf trap's clock go on while another player flies; solo as ever;
# code review F5 of 2026-10-29) on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/coop_landing"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" coop_landing_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
