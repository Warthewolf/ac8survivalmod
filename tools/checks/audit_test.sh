#!/bin/sh
# audit_test.sh : runs tools/checks/audit_test.lua (the run's audits: targets, pay, sync; Scripts/sv_audit.lua)
# on the real parts with build/checks/lua.exe (tools/checks/lua_build.sh makes it).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/audit"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config"
"$LUA" audit_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode" "$W"
