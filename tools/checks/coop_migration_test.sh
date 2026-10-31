#!/bin/sh
# coop_migration_test.sh : runs tools/checks/coop_migration_test.lua (Survival COOP's host migration: the host's line of
# succession, the first in line taking over, the others following) on the real sv_config.lua and sv_coop.lua with
# build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/migration"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
cp ../../mod/UE4SS/AC8SurvivalMode/config/survival.default.ini "$W/config/"
"$LUA" coop_migration_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
