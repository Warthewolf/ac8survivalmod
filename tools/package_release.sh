#!/bin/sh
# package_release.sh online|offline [version] : a Nexus release zip of one edition (run tools/build_all.sh first).
#   build/release/AC8SurvivalMode_<version>_Online.zip  : the build as it is (the leaderboard sends each run)
#   build/release/AC8SurvivalMode_<version>_Offline.zip : no leaderboard code at all (user, 2026-10-23: "None of the
#     Code for sending the files remains"): dlls/main.dll rebuilt with SV_OFFLINE (runtime/build.sh OFFLINE=1), main.lua,
#     survival.default.ini and README.txt through tools/edition.py offline; the zip is refused if any of it still holds
#     network code (WinHTTP, bcrypt, the Worker's address, SV_Post*, SV_SteamName, the run queue or pilot files).
# Where: the zip and its .buildhash.txt always go to the main tree's build/release (E:\ACE8 Survival Mode\build\release),
#   from any worktree (tools/release_dir.sh; user, 2026-11-07); RELEASE_DIR=<folder> overrides it.
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
# ((2026-11-07) every 0.74.x zip shipped a runtime with no leaderboard address: runtime/build.sh found no submit.local
# in the worktree it ran in) an Online build only with the address in its runtime: build/runtime/submit_cfg.h is written
# only by a build that found it, and the staged main.dll must be that build's
if [ "$ed" = online ]; then
    [ -f build/runtime/submit_cfg.h ] && cmp -s build/runtime/main.dll build/install/AC8SurvivalMode/dlls/main.dll || {
        echo "package_release.sh online: the runtime has no leaderboard address (build/runtime/submit_cfg.h missing, or the staged"
        echo "  main.dll isn't build/runtime's): its runs could never be sent. Run tools/build_all.sh where runtime/build.sh finds"
        echo "  leaderboard/submit.local (this checkout's, the main tree's, or .env's SV_LB_LOCAL)."
        exit 1
    }
fi
rm -rf "$st" && mkdir -p "$st/ue4ss/Mods/IoStoreLoaderMod"
cp -r build/install/AC8SurvivalMode "$st/ue4ss/Mods/"
cp -r build/install/SurvivalMode "$st/ue4ss/Mods/IoStoreLoaderMod/"
rm -f "$mod"/config/survival.ini* "$mod"/*.log "$mod"/config/pending_runs.txt "$mod"/config/pilot_id.txt \
      "$mod"/config/coast_*.txt "$mod"/hud_dump.txt "$mod"/flights_*.csv "$mod"/config/survival_profile.ini*
# the ZFA-44 (tools/zfa44, the user's own model, AGENTS.md's exception of 2026-11-06): without ZFA=1 its container is
# out and its part (Scripts/sv_zfa44.lua) cut to its first line (main.lua still loads it; the carriers then fly their
# host airframe). ZFA=1 (user, 2026-11-07: "I want all of our stuff we built tonight in this build", Alyssa's TESTER zip
# included) keeps both: the container from build/install, else build/zfa44/out; the zip is named ..._ZFA44.
if [ "$ZFA" = 1 ]; then
    zc="$st/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode"
    if [ ! -f "$zc/SurvivalMode_ZFA44_P.utoc" ]; then
        [ -f build/zfa44/out/SurvivalMode_ZFA44_P.utoc ] || { echo "ZFA=1: no ZFA-44 container (sh tools/zfa44/build.sh)"; exit 1; }
        cp build/zfa44/out/SurvivalMode_ZFA44_P.utoc build/zfa44/out/SurvivalMode_ZFA44_P.ucas "$zc/"
        [ -f build/zfa44/out/SurvivalMode_ZFA44_P.pak ] && cp build/zfa44/out/SurvivalMode_ZFA44_P.pak "$zc/"
    fi
    echo "ZFA=1: the ZFA-44 kept (its container and Scripts/sv_zfa44.lua)"
else
rm -f "$st"/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_ZFA44_P.* "$st"/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_Laser7_P.*   # (and its weapon, AC7's LaserInterceptor)
rm -f "$st"/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_Tani_P.*   # THE TANICORN's parts: the user's install only, never shipped
if [ -f "$mod/Scripts/sv_zfa44.lua" ]; then
    head -n 1 "$mod/Scripts/sv_zfa44.lua" > "$mod/Scripts/sv_zfa44.lua.tmp" && mv "$mod/Scripts/sv_zfa44.lua.tmp" "$mod/Scripts/sv_zfa44.lua"
fi
fi
# TESTER=1: a tester's build (user, 2026-11-03: "give me a tester version for alyssa"): the test keys (force a special,
# zollars, ...) and the diagnostic loggers KEPT, everything else as the friends' zip; named ..._<version>_TESTER_...
# Only for the tester the user names: every other zip strips them (user, 2026-10-23: test keys out of releases).
if [ "$TESTER" = 1 ]; then
    echo "TESTER=1: test keys and the diagnostic loggers kept ($(grep -c 'TEST ONLY BEGIN' "$mod"/Scripts/*.lua | awk -F: '{s+=$2} END {print s}') test blocks)"
else
# (the default ini too: its test-only sections, the lightning Anomaly's, 2026-11-07; each leaves a lone ";" line)
python -I tools/strip_test_only.py "$mod"/Scripts/*.lua "$mod"/config/survival.default.ini
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
[ "$ZFA" = 1 ] && suffix=${suffix}_ZFA44
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
# BUILD_NAME=<name>: a build line's own name in the zip's (BUILD_NAME=COOP2MP: docs/re/COOP2MP.md)
tv=$ver; [ "$TESTER" = 1 ] && tv="${ver}_TESTER"
. tools/release_dir.sh
out="$REL/AC8SurvivalMode_${BUILD_NAME:+${BUILD_NAME}_}${tv}_$Ed$suffix.zip"
# ((2026-11-07) the user: "update the version number each time you hand me a new file": three different builds had all
# been 0.74.0-coop2mp.92) a zip of this name already made: refused, the version bumped first (tools/bump_version.py);
# REPACK=1 makes it again anyway (the same build, e.g. a lost zip)
if [ -f "$out" ] && [ "$REPACK" != 1 ]; then
    echo "package_release.sh: $out already exists: bump the version first (python -I tools/bump_version.py, then"
    echo "  sh tools/build_all.sh and package as the new version), or REPACK=1 to make the same build's zip again"
    exit 3
fi
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
    # ((2026-11-07) the user: "rework the leaderboard so I don't have to continually register a new version everytime
    # we patch") registered on the Worker here, with the admin key in the main tree's leaderboard/keys.secret
    # (ADMIN_KEY=...); without it, said, and the zip is registered by hand on /admin as before. SV_LB_REGISTER=0 skips it.
    python -X utf8 -I tools/lb_register.py "$out.buildhash.txt"
fi
