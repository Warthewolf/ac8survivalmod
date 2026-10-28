#!/bin/sh
# package_test.sh [name] : a test-release zip of the staged build (run tools/build_all.sh first).
#   build/release/AC8SurvivalMode_<name>.zip = README.txt (release/README.txt, versions filled in)
#                                             + ue4ss/Mods/AC8SurvivalMode + ue4ss/Mods/IoStoreLoaderMod/SurvivalMode
# Only the default settings ship (config/survival.default.ini); a player's survival.ini is made on their first run.
set -e
cd "$(dirname "$0")/.."
name=${1:-test_$(date +%Y-%m-%d)}
st=build/release/stage
lua=$(grep -m1 -E '^(local )?VERSION = ' build/install/AC8SurvivalMode/Scripts/main.lua | sed 's/.*"\(.*\)".*/\1/')
rt=$(grep -m1 '^#define RT_VERSION' runtime/survival_rt.c | sed 's/.*L"\(.*\)".*/\1/')
rm -rf "$st" && mkdir -p "$st/ue4ss/Mods/IoStoreLoaderMod"
cp -r build/install/AC8SurvivalMode "$st/ue4ss/Mods/"
cp -r build/install/SurvivalMode "$st/ue4ss/Mods/IoStoreLoaderMod/"
rm -f "$st"/ue4ss/Mods/AC8SurvivalMode/config/survival.ini* "$st"/ue4ss/Mods/AC8SurvivalMode/*.log
# (what the game writes there: the queue of unsent runs, this install's anonymous pilot name, your learnt habits, map
# notes, dumps)
rm -f "$st"/ue4ss/Mods/AC8SurvivalMode/config/pending_runs.txt "$st"/ue4ss/Mods/AC8SurvivalMode/config/pilot_id.txt \
      "$st"/ue4ss/Mods/AC8SurvivalMode/config/survival_profile.ini* \
      "$st"/ue4ss/Mods/AC8SurvivalMode/config/coast_*.txt "$st"/ue4ss/Mods/AC8SurvivalMode/hud_dump.txt
# the test-only cheats (TEST ONLY BEGIN ... END in Scripts/*.lua: the +5000 zollars key) never ship
python -I tools/strip_test_only.py "$st"/ue4ss/Mods/AC8SurvivalMode/Scripts/*.lua
python -X utf8 -I tools/checks/lua_check.py "$st"/ue4ss/Mods/AC8SurvivalMode/Scripts/*.lua
sed "s/{DATE}/$(date +%Y-%m-%d)/; s/{LUA}/$lua/; s/{RT}/$rt/" release/README.txt > "$st/README.txt"
out="build/release/AC8SurvivalMode_$name.zip"
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
