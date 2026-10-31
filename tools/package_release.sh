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
python -I tools/strip_test_only.py "$mod"/Scripts/*.lua
suffix=
if [ "$NOVALKA" = 1 ]; then
    rm -f "$st"/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_Valka_P.*
    rm -rf "$mod/Sounds/valka"
    rmdir "$mod/Sounds" 2>/dev/null || true
    python -X utf8 -I tools/novalka.py "$mod"
    suffix=_NoValka
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
out="build/release/AC8SurvivalMode_${BUILD_NAME:+${BUILD_NAME}_}${ver}_$Ed$suffix.zip"
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
