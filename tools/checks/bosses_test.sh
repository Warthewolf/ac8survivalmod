#!/bin/sh
# bosses_test.sh : runs tools/checks/bosses_test.lua (the behaviour roadmap's P7, boss phases: tools/re/BEHAVIOUR_DIRECTOR.md
# unit 9; MINDRIPPER's pack, AB.L..IN's three phases, a Ladon's rage, the ALICORN's deck launches, the main-menu rows,
# co-op's keep list) on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it), then checks the
# build's half of it without the game (tools/checks/bosses_build_check.py: the rage circuit, flags, events, radio lines).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/bosses"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" bosses_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
python -X utf8 -I bosses_build_check.py
