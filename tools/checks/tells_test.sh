#!/bin/sh
# tells_test.sh : runs tools/checks/tells_test.lua (the behaviour roadmap's P3, tells: tools/re/BEHAVIOUR_DIRECTOR.md
# unit 4; the catalog, no HUD warnings, TELL's gap, sure tells, leads and wiring, co-op's "tl") on the real parts with
# build/checks/lua.exe (tools/checks/lua_build.sh makes it), and checks the tells' radio lines against the Lua catalog
# with tools/survival_events.py (TELL_LINES; the build checks it again, with the game's voice bank).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/tells"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" tells_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
python -X utf8 -I tells_lines_check.py
