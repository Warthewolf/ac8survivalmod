#!/bin/sh
# hud_info_test.sh : runs tools/checks/hud_info_test.lua (the HUD's info key, CFG.hud.info: the user's request of
# 2026-10-29, code review F6) with build/checks/lua.exe (tools/checks/lua_build.sh makes it) on a copy of the parts as a
# release ships them: tools/strip_test_only.py takes the test-only code out first, so the key is checked to survive it.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/hud_info"
SRC="$HERE/../../mod/UE4SS/AC8SurvivalMode"
rm -rf "$W" && mkdir -p "$W"
cp -r "$SRC/Scripts" "$SRC/config" "$W/"
rm -f "$W/config/survival.ini"
python -X utf8 -I "$HERE/../strip_test_only.py" "$W"/Scripts/*.lua
"$LUA" hud_info_test.lua "$W"
