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
# ((2026-11-07) the dev installs had no leaderboard address either, and the user hosts ranked co-op runs, which only the
# host sends) the same check as package_release.sh's Online one; LB_OPTIONAL=1 stages it without
if [ "$LB_OPTIONAL" != 1 ]; then
    [ -f build/runtime/submit_cfg.h ] && cmp -s build/runtime/main.dll build/install/AC8SurvivalMode/dlls/main.dll || {
        echo "package_dev.sh: the runtime has no leaderboard address (build/runtime/submit_cfg.h missing, or the staged main.dll"
        echo "  isn't build/runtime's): your hosted runs could never be sent. Run tools/build_all.sh where runtime/build.sh finds"
        echo "  leaderboard/submit.local (this checkout's, the main tree's, or .env's SV_LB_LOCAL); LB_OPTIONAL=1 to stage anyway."
        exit 1
    }
fi
rm -rf "$st"
mkdir -p "$st/ue4ss/Mods/IoStoreLoaderMod"
cp -r build/install/AC8SurvivalMode "$st/ue4ss/Mods/"
cp -r build/install/SurvivalMode "$st/ue4ss/Mods/IoStoreLoaderMod/"
# (what a game writes: settings, logs, the run queue, its pilot name, learnt habits, map notes, dumps)
rm -f "$mod"/config/survival.ini* "$mod"/*.log "$mod"/config/pending_runs.txt "$mod"/config/pilot_id.txt \
      "$mod"/config/coast_*.txt "$mod"/hud_dump.txt "$mod"/flights_*.csv "$mod"/config/survival_profile.ini*
# without VALKA (tools/novalka.py, as NOVALKA=1 package_release.sh); VALKA=1 keeps her (the user's own build only:
# her X-02S and AC7 sounds are never in a friends' zip; user, 2026-11-02: "add her to a special build for me only")
if [ "$VALKA" != 1 ]; then
rm -f "$st"/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_Valka_P.*
rm -rf "$mod/Sounds/valka"
rmdir "$mod/Sounds" 2>/dev/null || true
python -X utf8 -I tools/novalka.py "$mod" > /dev/null
else
# (her round's song, the user's own track: build/valka_music, git-ignored, never in a friends' zip)
if ls build/valka_music/*.wav > /dev/null 2>&1; then mkdir -p "$mod/Sounds/valka" && cp build/valka_music/*.wav "$mod/Sounds/valka/"; fi
fi
# ZFA=1 keeps the ZFA-44 (tools/zfa44: the user's own model; test T0's Ctrl+9, Scripts/sv_zfa44.lua), from build/install
# or else build/zfa44/out; without it, none. The user's builds only: package_release.sh drops it whatever is set.
if [ "$ZFA" = 1 ]; then
    if [ ! -f "$st/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_ZFA44_P.utoc" ]; then
        [ -f build/zfa44/out/SurvivalMode_ZFA44_P.utoc ] || { echo "ZFA=1: no ZFA-44 container (sh tools/zfa44/build.sh)"; exit 1; }
        cp build/zfa44/out/SurvivalMode_ZFA44_P.utoc build/zfa44/out/SurvivalMode_ZFA44_P.ucas "$st/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/"
    fi
    echo "ZFA=1: the ZFA-44's container staged (Ctrl+9 in a run: test T0)"
else
    rm -f "$st"/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_ZFA44_P.* "$st"/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_Laser7_P.*
fi
# NOSPACEPORT=1: without the Spaceport Assault and its Retake (tools/nospaceport.py, as NOSPACEPORT=1 package_release.sh)
if [ "$NOSPACEPORT" = 1 ]; then python -X utf8 -I tools/nospaceport.py "$mod" > /dev/null; fi
cp release/README.txt "$st/README.txt"
python -X utf8 -I tools/coop_edition.py "$st" "$mod" > /dev/null
python -I tools/edition.py online "$mod"/Scripts/*.lua "$mod/config/survival.default.ini" "$st/README.txt" > /dev/null
python -X utf8 tools/checks/lua_check.py "$mod"/Scripts/*.lua | tail -1
grep -m1 -E '^(local )?VERSION = ' "$mod/Scripts/main.lua"
echo "staged $st (test keys kept: $(grep -c 'TEST ONLY BEGIN' "$mod"/Scripts/sv_main.lua) test blocks in sv_main.lua)"
# ((2026-11-07) the installed build's hash registered on the leaderboard by itself: tools/lb_register.py, the admin key
# in the main tree's leaderboard/keys.secret (ADMIN_KEY=...); SV_LB_REGISTER=0 skips it)
bh=$(python -X utf8 -I tools/build_hash.py "$st/ue4ss/Mods")
mv=$(grep -m1 -E '^(local )?VERSION = ' "$mod/Scripts/main.lua" | sed 's/.*"\(.*\)".*/\1/')
echo "build hash: $bh (mod $mv)"
python -X utf8 -I tools/lb_register.py --mod "$mv" --build "$bh" --note "dev $(basename "$st")"
