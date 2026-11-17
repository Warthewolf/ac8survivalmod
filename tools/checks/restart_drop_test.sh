#!/bin/sh
# restart_drop_test.sh : a mission restart drops the parts whose objects the reload takes (sv_core.lua levelRestartDrop,
# 0.74.129), on the working copy (the dev parts) and on a release's copy (tools/strip_test_only.py): restart_drop_test.lua.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
SRC="$HERE/../../mod/UE4SS/AC8SurvivalMode"
sh lua_build.sh > /dev/null
W="$HERE/../../build/checks/restart"
rm -rf "$W" && mkdir -p "$W/dev" "$W/rel"
cp -r "$SRC/Scripts" "$SRC/config" "$W/dev/"
cp -r "$SRC/Scripts" "$SRC/config" "$W/rel/"
rm -f "$W/dev/config/survival.ini" "$W/rel/config/survival.ini"
python -I ../strip_test_only.py "$W"/rel/Scripts/*.lua > /dev/null
"$HERE/../../build/checks/lua.exe" restart_drop_test.lua "$W/dev/Scripts/" dev
"$HERE/../../build/checks/lua.exe" restart_drop_test.lua "$W/rel/Scripts/" rel
