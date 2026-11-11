#!/bin/sh
# store_events_test.sh : runs tools/checks/store_events_test.lua (hard rule 64's rest: this game's landing STORE as a
# gate on the event package, the one-shots that change the world fired again here once it's shut, the host's and a
# joiner's; Scripts/sv_rounds_store.lua) on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/store_events"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" store_events_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
