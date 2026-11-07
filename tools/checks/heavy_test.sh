#!/bin/sh
# heavy_test.sh : runs tools/checks/heavy_test.lua (the heavy bombers' routes over the runway and the jammer's ECM pod,
# 0.72.1: "tu-95's aren't attacking the base", "the EA-18G never activated it's ECM") on the real parts with
# build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/heavy"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" heavy_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
