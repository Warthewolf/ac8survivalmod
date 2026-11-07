#!/bin/sh
# resync_test.sh : runs tools/checks/resync_test.lua (0.73.73: a co-op joiner's copies through a resync; the testers' logs
# of 0.73.70: the host's kills counted as strays, every "jn" answered with a teardown, refused spawns, ghost allies,
# phantom kills and free revives) as a host, then a joiner, with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/resync"
rm -rf "$W"
for r in host join; do mkdir -p "$W/$r/Scripts" "$W/$r/config"; cp ../../mod/UE4SS/AC8SurvivalMode/config/survival.default.ini "$W/$r/config/"; done
"$LUA" resync_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W" host
"$LUA" resync_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W" join
