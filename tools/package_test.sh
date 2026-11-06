#!/bin/sh
# package_test.sh [name] : a test-release zip of the staged build (run tools/build_all.sh first).
#   build/release/AC8SurvivalMode_<name>.zip = README.txt (release/README.txt, versions filled in)
#                                             + ue4ss/Mods/AC8SurvivalMode + ue4ss/Mods/IoStoreLoaderMod/SurvivalMode
# Only the default settings ship (config/survival.default.ini); a player's survival.ini is made on their first run.
# The ZFA-44 as package_release.sh has it (code review of 2026-11-07): without ZFA=1 its container out and its part
# (Scripts/sv_zfa44.lua) cut to its first line; ZFA=1 keeps both (the container from build/install, else build/zfa44/out).
set -e
cd "$(dirname "$0")/.."
name=${1:-test_$(date +%Y-%m-%d)}
st=build/release/stage
mod=$st/ue4ss/Mods/AC8SurvivalMode
lua=$(grep -m1 -E '^(local )?VERSION = ' build/install/AC8SurvivalMode/Scripts/main.lua | sed 's/.*"\(.*\)".*/\1/')
rt=$(grep -m1 '^#define RT_VERSION' runtime/survival_rt.c | sed 's/.*L"\(.*\)".*/\1/')
rm -rf "$st" && mkdir -p "$st/ue4ss/Mods/IoStoreLoaderMod"
cp -r build/install/AC8SurvivalMode "$st/ue4ss/Mods/"
cp -r build/install/SurvivalMode "$st/ue4ss/Mods/IoStoreLoaderMod/"
rm -f "$mod"/config/survival.ini* "$mod"/*.log
# (what the game writes there: the queue of unsent runs, this install's anonymous pilot name, your learnt habits, map
# notes, dumps, the flight recorder's tables)
rm -f "$mod"/config/pending_runs.txt "$mod"/config/pilot_id.txt "$mod"/config/survival_profile.ini* \
      "$mod"/config/coast_*.txt "$mod"/hud_dump.txt "$mod"/flights_*.csv
# the ZFA-44 (tools/zfa44, the user's own model, AGENTS.md's exception of 2026-11-06): package_release.sh's block
if [ "$ZFA" = 1 ]; then
    zc="$st/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode"
    if [ ! -f "$zc/SurvivalMode_ZFA44_P.utoc" ]; then
        [ -f build/zfa44/out/SurvivalMode_ZFA44_P.utoc ] || { echo "ZFA=1: no ZFA-44 container (sh tools/zfa44/build.sh)"; exit 1; }
        cp build/zfa44/out/SurvivalMode_ZFA44_P.utoc build/zfa44/out/SurvivalMode_ZFA44_P.ucas "$zc/"
        [ -f build/zfa44/out/SurvivalMode_ZFA44_P.pak ] && cp build/zfa44/out/SurvivalMode_ZFA44_P.pak "$zc/"
    fi
    echo "ZFA=1: the ZFA-44 kept (its container and Scripts/sv_zfa44.lua)"
else
rm -f "$st"/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_ZFA44_P.*
if [ -f "$mod/Scripts/sv_zfa44.lua" ]; then
    head -n 1 "$mod/Scripts/sv_zfa44.lua" > "$mod/Scripts/sv_zfa44.lua.tmp" && mv "$mod/Scripts/sv_zfa44.lua.tmp" "$mod/Scripts/sv_zfa44.lua"
fi
fi
# the test-only cheats (TEST ONLY BEGIN ... END in Scripts/*.lua: the +5000 zollars key) never ship, nor the default
# ini's test-only sections (the lightning Anomaly's, 2026-11-07; each leaves a lone ";" line)
python -I tools/strip_test_only.py "$mod"/Scripts/*.lua "$mod"/config/survival.default.ini
python -X utf8 -I tools/checks/lua_check.py "$mod"/Scripts/*.lua
sed "s/{DATE}/$(date +%Y-%m-%d)/; s/{LUA}/$lua/; s/{RT}/$rt/" release/README.txt > "$st/README.txt"
suffix=""
[ "$ZFA" = 1 ] && suffix=_ZFA44
out="build/release/AC8SurvivalMode_$name$suffix.zip"
python -I -c "
import os, sys, zipfile
st, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for d, _, fs in os.walk(st):
        for f in sorted(fs):
            p = os.path.join(d, f)
            z.write(p, os.path.relpath(p, st).replace(os.sep, '/'))
" "$st" "$out"
echo "packaged $out (Lua $lua, runtime $rt)"
