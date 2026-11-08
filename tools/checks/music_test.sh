#!/bin/sh
# music_test.sh : runs tools/checks/music_test.lua (Survival's music player, Scripts/sv_music.lua; user, 2026-11-08:
# "add all the named music into the music player") on the real part with build/checks/lua.exe
# (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
"$LUA" music_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode"
