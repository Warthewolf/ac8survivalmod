#!/bin/sh
# package_release.sh online|offline [version] : a Nexus release zip of one edition (run tools/build_all.sh first).
#   build/release/AC8SurvivalMode_<version>_Online.zip  : the build as it is (the leaderboard sends each run)
#   build/release/AC8SurvivalMode_<version>_Offline.zip : no leaderboard code at all (user, 2026-10-23: "None of the
#     Code for sending the files remains"): dlls/main.dll rebuilt with SV_OFFLINE (runtime/build.sh OFFLINE=1), main.lua,
#     survival.default.ini and README.txt through tools/edition.py offline; the zip is refused if any of it still holds
#     network code (WinHTTP, bcrypt, the Worker's address, SV_Post*, SV_SteamName, the run queue or pilot files).
# Both: test-only code stripped (tools/strip_test_only.py), no player settings, logs or leaderboard files.
# Online: the release's build hash (tools/build_hash.py over the staged files, as the game's runtime works it out) is
#   printed and written next to the zip, <zip>.buildhash.txt: register it on the leaderboard Worker's /admin page
#   (leaderboard/README.md) before players send runs from this zip, or their runs are refused as an unknown build.
# COOP=1 package_release.sh ...: the Survival COOP build (user, 2026-10-25): co-op on, VERSION tagged
#   (tools/coop_edition.py), release/README_COOP.txt in the readme; the zip is named ..._COOP.
# NOVALKA=1 package_release.sh ...: a build without VALKA (user, 2026-10-25, a build for a friend): no X-02S container,
#   no AC7 railgun sounds, VALKA switched off and out of the rotation (tools/novalka.py); the zip is named ..._NoValka.
# NOSPACEPORT=1 package_release.sh ...: a build without the Spaceport Assault and its Retake (user, 2026-10-31, a build
#   for friends): both switched off, their ini sections gone (tools/nospaceport.py); the zip is named ..._NoSpaceport.
set -e
cd "$(dirname "$0")/.."
ed=$1
case "$ed" in online) Ed=Online ;; offline) Ed=Offline ;; *) echo "usage: package_release.sh online|offline [version]"; exit 2 ;; esac
lua=$(grep -m1 -E '^(local )?VERSION = ' build/install/AC8SurvivalMode/Scripts/main.lua | sed 's/.*"\(.*\)".*/\1/')
rt=$(grep -m1 '^#define RT_VERSION' runtime/survival_rt.c | sed 's/.*L"\(.*\)".*/\1/')
ver=${2:-$lua}
st=build/release/stage_$ed
mod=$st/ue4ss/Mods/AC8SurvivalMode
rm -rf "$st" && mkdir -p "$st/ue4ss/Mods/IoStoreLoaderMod"
cp -r build/install/AC8SurvivalMode "$st/ue4ss/Mods/"
cp -r build/install/SurvivalMode "$st/ue4ss/Mods/IoStoreLoaderMod/"
rm -f "$mod"/config/survival.ini* "$mod"/*.log "$mod"/config/pending_runs.txt "$mod"/config/pilot_id.txt \
      "$mod"/config/coast_*.txt "$mod"/hud_dump.txt "$mod"/flights_*.csv "$mod"/config/survival_profile.ini*
# the ZFA-44 (tools/zfa44, the user's own model): the user's dev builds only (package_dev.sh ZFA=1), never a zip, TESTER
# ones too: its container out, its test part (Scripts/sv_zfa44.lua) cut to its first line (main.lua still loads it)
rm -f "$st"/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_ZFA44_P.*
if [ -f "$mod/Scripts/sv_zfa44.lua" ]; then
    head -n 1 "$mod/Scripts/sv_zfa44.lua" > "$mod/Scripts/sv_zfa44.lua.tmp" && mv "$mod/Scripts/sv_zfa44.lua.tmp" "$mod/Scripts/sv_zfa44.lua"
fi
# TESTER=1: a tester's build (user, 2026-11-03: "give me a tester version for alyssa"): the test keys (force a special,
# zollars, ...) and the diagnostic loggers KEPT, everything else as the friends' zip; named ..._<version>_TESTER_...
# Only for the tester the user names: every other zip strips them (user, 2026-10-23: test keys out of releases).
if [ "$TESTER" = 1 ]; then
    echo "TESTER=1: test keys and the diagnostic loggers kept ($(grep -c 'TEST ONLY BEGIN' "$mod"/Scripts/*.lua | awk -F: '{s+=$2} END {print s}') test blocks)"
else
python -I tools/strip_test_only.py "$mod"/Scripts/*.lua
# the diagnostic loggers off for friends (tools/quiet_logs.py: the weapons log was half the Lua tick in big rounds; a
# friend's "choppy", 2026-10-31); the user's dev install (package_dev.sh) keeps them
python -X utf8 -I tools/quiet_logs.py "$mod"
fi
suffix=
if [ "$NOVALKA" = 1 ]; then
    rm -f "$st"/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_Valka_P.*
    rm -rf "$mod/Sounds/valka"
    rmdir "$mod/Sounds" 2>/dev/null || true
    python -X utf8 -I tools/novalka.py "$mod"
    suffix=_NoValka
fi
# SONG=1 (with VALKA): her round's song from build/valka_music (git-ignored, the user's own track; user, 2026-11-03:
# "i want them to have the song too")
if [ "$SONG" = 1 ] && [ "$NOVALKA" != 1 ]; then
    if ls build/valka_music/*.wav > /dev/null 2>&1; then mkdir -p "$mod/Sounds/valka" && cp build/valka_music/*.wav "$mod/Sounds/valka/"
    else echo "SONG=1: no song in build/valka_music"; exit 1; fi
fi
if [ "$NOSPACEPORT" = 1 ]; then
    python -X utf8 -I tools/nospaceport.py "$mod"
    suffix=${suffix}_NoSpaceport
fi
sed "s/{EDITION}/$Ed/; s/{DATE}/$(date +%Y-%m-%d)/; s/{LUA}/$lua/; s/{RT}/$rt/" release/README.txt > "$st/README.txt"
if [ "$COOP" = 1 ]; then
    python -X utf8 -I tools/coop_edition.py "$st" "$mod"
    lua=$(grep -m1 -E '^(local )?VERSION = ' "$mod/Scripts/main.lua" | sed 's/.*"\(.*\)".*/\1/')
    sed -i "s/(Lua [^,]*, runtime/(Lua $lua, runtime/" "$st/README.txt"
    suffix="_COOP$suffix"
fi
if [ "$ed" = offline ]; then
    (cd runtime && OFFLINE=1 sh build.sh > /dev/null)
    cp build/runtime/offline/main.dll "$mod/dlls/main.dll"
fi
python -I tools/edition.py "$ed" "$mod"/Scripts/*.lua "$mod/config/survival.default.ini" "$st/README.txt"
python -X utf8 -I tools/checks/lua_check.py "$mod"/Scripts/*.lua
if [ "$ed" = offline ]; then
    python -I -c "
import os, sys
st = sys.argv[1]
words = ['winhttp', 'bcrypt', 'workers.dev', 'https://', 'SV_Post', 'SV_SteamName', 'steam_api', 'SteamAPI', 'pending_runs',
         'pilot_id', 'ONLINE ONLY', 'OFFLINE:', 'SV_BuildHash', 'X-SV-Build']
bad = []
for d, _, fs in os.walk(st):
    for f in fs:
        p = os.path.join(d, f)
        if p.endswith(('.ucas', '.utoc')): continue                      # (game data, packed; no code)
        b = open(p, 'rb').read()
        for w in words:
            if w.lower().encode() in b.lower() or w.lower().encode('utf-16-le') in b.lower():
                bad.append((os.path.relpath(p, st), w))
if bad:
    for p, w in bad: print('OFFLINE CHECK FAILED:', p, 'holds', repr(w))
    sys.exit(1)
print('offline check: no network code in', st)
" "$st"
fi
# BUILD_NAME=<name>: a build line's own name in the zip's (BUILD_NAME=COOP2MP: tools/re/COOP2MP.md)
tv=$ver; [ "$TESTER" = 1 ] && tv="${ver}_TESTER"
out="build/release/AC8SurvivalMode_${BUILD_NAME:+${BUILD_NAME}_}${tv}_$Ed$suffix.zip"
python -I -c "
import os, sys, zipfile
st, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for d, _, fs in os.walk(st):
        for f in sorted(fs):
            p = os.path.join(d, f)
            z.write(p, os.path.relpath(p, st).replace(os.sep, '/'))
" "$st" "$out"
echo "packaged $out ($Ed edition, Lua $lua, runtime $rt)"
if [ "$ed" = online ]; then
    # the build hash the game will send with each run from this zip (leaderboard/README.md: register it on /admin)
    bh=$(python -X utf8 -I tools/build_hash.py "$st/ue4ss/Mods")
    mv=$(grep -m1 -E '^(local )?VERSION = ' "$mod/Scripts/main.lua" | sed 's/.*"\(.*\)".*/\1/')
    {
        echo "AC8 Survival Mode build: register it on the leaderboard before players send runs from this zip (open the"
        echo "Worker's /admin page and paste this file under 'Builds runs are taken from'). leaderboard/README.md has the rest."
        echo "mod $mv"
        echo "build $bh"
        echo "zip $(basename "$out")"
    } > "$out.buildhash.txt"
    echo "build hash: $bh (mod $mv; $out.buildhash.txt)"
fi
