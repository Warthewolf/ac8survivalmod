#!/bin/sh
# capture_test.sh : GEOFON's capture (Scripts/sv_fleet_capture.lua, round 30's WP14) on build/checks/lua.exe
# (tools/checks/lua_build.sh makes it): tools/checks/capture_test.lua with the game, the clock and co-op stubbed (the picks,
# the lock and its ends, the takeover's shield, the landing, every end giving the controls back, the host's words).
# The piece's release / TESTER copies (only its header left) are fleet_test.sh's.
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
"$HERE/../../build/checks/lua.exe" capture_test.lua "$HERE/../../mod/UE4SS/AC8SurvivalMode"
