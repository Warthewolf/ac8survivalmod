#!/bin/sh
# fishing_test.sh : runs tools/checks/fishing_test.lua (GONE FISHIN''s shoals and SAL's boat, Scripts/sv_fishing.lua, and
# its test key) on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it), and on a copy of the parts
# as a release has them (tools/strip_test_only.py first).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/fishing"
SRC="$HERE/../../mod/UE4SS/AC8SurvivalMode"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config" "$W/stripped"
cp -r "$SRC/Scripts" "$SRC/config" "$W/stripped/"
python -X utf8 -I "$HERE/../strip_test_only.py" "$W"/stripped/Scripts/*.lua > /dev/null
"$LUA" fishing_test.lua "$SRC" "$W" "$W/stripped"
