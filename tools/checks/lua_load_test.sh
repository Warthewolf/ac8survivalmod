#!/bin/sh
# lua_load_test.sh [mod folder] : loads the Lua runtime (main.lua and its parts) outside the game, on a copy of the mod
# folder (its survival.ini and log are written there), with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
# Default: the working copy, mod/UE4SS/AC8SurvivalMode; package_release.sh can point it at a release's.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
SRC="${1:-$HERE/../../mod/UE4SS/AC8SurvivalMode}"
sh lua_build.sh
W="$HERE/../../build/checks/load"
rm -rf "$W" && mkdir -p "$W/mod"
cp -r "$SRC/Scripts" "$SRC/config" "$W/mod/"
rm -f "$W/mod/config/survival.ini"
"$HERE/../../build/checks/lua.exe" lua_load_test.lua "$W/mod/Scripts/"
