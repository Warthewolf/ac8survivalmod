#!/bin/sh
# package_dev.sh [name] : the user's own test install of the staged build (run tools/build_all.sh first): the Online
# COOP build without VALKA, as package_release.sh makes it, but with the test keys KEPT (no tools/strip_test_only.py):
# build/release/stage_dev_<name>/ue4ss/Mods/{AC8SurvivalMode,IoStoreLoaderMod/SurvivalMode}. Never for friends: their
# zips come from package_release.sh, which strips every TEST ONLY block (user, 2026-10-23: test keys out of releases).
# (stage_dev was made by hand this way for 0.72.2; COOP2MP's T1 / T2 need it: tools/re/COOP2MP.md)
set -e
cd "$(dirname "$0")/.."
name=${1:-dev}
st=build/release/stage_dev_$name
mod=$st/ue4ss/Mods/AC8SurvivalMode
rm -rf "$st"
mkdir -p "$st/ue4ss/Mods/IoStoreLoaderMod"
cp -r build/install/AC8SurvivalMode "$st/ue4ss/Mods/"
cp -r build/install/SurvivalMode "$st/ue4ss/Mods/IoStoreLoaderMod/"
# (what a game writes: settings, logs, the run queue, its pilot name, learnt habits, map notes, dumps)
rm -f "$mod"/config/survival.ini* "$mod"/*.log "$mod"/config/pending_runs.txt "$mod"/config/pilot_id.txt \
      "$mod"/config/coast_*.txt "$mod"/hud_dump.txt "$mod"/flights_*.csv "$mod"/config/survival_profile.ini*
# without VALKA (tools/novalka.py, as NOVALKA=1 package_release.sh)
rm -f "$st"/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_Valka_P.*
rm -rf "$mod/Sounds/valka"
rmdir "$mod/Sounds" 2>/dev/null || true
python -X utf8 -I tools/novalka.py "$mod" > /dev/null
# NOSPACEPORT=1: without the Spaceport Assault and its Retake (tools/nospaceport.py, as NOSPACEPORT=1 package_release.sh)
if [ "$NOSPACEPORT" = 1 ]; then python -X utf8 -I tools/nospaceport.py "$mod" > /dev/null; fi
cp release/README.txt "$st/README.txt"
python -X utf8 -I tools/coop_edition.py "$st" "$mod" > /dev/null
python -I tools/edition.py online "$mod"/Scripts/*.lua "$mod/config/survival.default.ini" "$st/README.txt" > /dev/null
python -X utf8 tools/checks/lua_check.py "$mod"/Scripts/*.lua | tail -1
grep -m1 -E '^(local )?VERSION = ' "$mod/Scripts/main.lua"
echo "staged $st (test keys kept: $(grep -c 'TEST ONLY BEGIN' "$mod"/Scripts/sv_main.lua) test blocks in sv_main.lua)"
