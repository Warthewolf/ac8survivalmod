#!/bin/sh
# defences_test.sh : runs tools/checks/defences_test.lua (0.72.1: the airfield's stronger AA guns and SAM sites and the
# STORE's CIWS; user, 2026-10-29) on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it), then
# tools/checks/defences_spots_check.py (the CIWS's fixed spots by the runway against Mission 22's airport objects).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/defences"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" defences_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
python -X utf8 -I defences_spots_check.py
