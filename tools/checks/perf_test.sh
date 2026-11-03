#!/bin/sh
# perf_test.sh : runs tools/checks/perf_test.lua (Workstream B's lag fixes, 0.73.77: the plane list pruned over a long
# run, the Ladon missiles' pool, the perf line's names, lists, walks and natives) on the real parts with
# build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/perf"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" perf_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
