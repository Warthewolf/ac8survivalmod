#!/bin/sh
# coop_settings_test.sh : runs tools/checks/coop_settings_test.lua (Survival COOP's settings sync, the main menu's
# settings rows, the co-op enemy scaling and the guards on what other games send, on the real Scripts/sv_config.lua
# and sv_coop.lua) as a host, a joiner and a joiner fed bad input, with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/settings"
rm -rf "$W"
for r in host join guard; do mkdir -p "$W/$r/Scripts" "$W/$r/config"; done
"$LUA" coop_settings_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W" host
"$LUA" coop_settings_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W" join
"$LUA" coop_settings_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W" guard
