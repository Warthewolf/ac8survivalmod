#!/bin/sh
# subs_test.sh : runs tools/checks/subs_test.lua (config\subtitles.ini: every subtitle line in one file a person can edit,
# Scripts/sv_config_subs.lua) on the real config parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/subs"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
cp ../../mod/UE4SS/AC8SurvivalMode/config/survival.default.ini "$W/config/"
"$LUA" subs_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
