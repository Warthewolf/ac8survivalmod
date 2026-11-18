#!/bin/sh
# tani_rail_test.sh : THE TANACORN's railguns and railcannon in Scripts/sv_tanicorn_rail.lua (2026-11-12, stage 4:
# docs/re/TANICORN.md "Railguns and railcannon"; the railguns' deploy and orders on Ctrl+L, the railcannon's cycle on
# Ctrl+H) on build/checks/lua.exe (tools/checks/lua_build.sh makes it): tools/checks/tani_rail_test.lua on a copy of the
# mod's Scripts, her family's pieces with the game stubbed; then a release's copy of the parts (tools/strip_test_only.py):
# sv_tanicorn_rail.lua only its header, every part still loading (lua_load_test.sh).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/tani_rail"
SRC="$HERE/../../mod/UE4SS/AC8SurvivalMode"
rm -rf "$W" && mkdir -p "$W/mod" "$W/stripped"
cp -r "$SRC/Scripts" "$W/mod/"
"$LUA" tani_rail_test.lua "$W/mod/Scripts/"
echo "a release's copy (strip_test_only.py)"
cp -r "$SRC/Scripts" "$SRC/config" "$W/stripped/"
rm -f "$W/stripped/config/survival.ini" "$W/stripped/config/rise_camera"*.txt
python -X utf8 -I "$HERE/../strip_test_only.py" "$W"/stripped/Scripts/*.lua "$W"/stripped/config/survival.default.ini > /dev/null
if grep -vq '^--' "$W/stripped/Scripts/sv_tanicorn_rail.lua"; then echo "  FAIL a line that isn't a comment left in sv_tanicorn_rail.lua"; exit 1; fi
if grep -q 'DEV ONLY\|TANI = {\|TANI\.setup\|testKey(\|TEST_TICKS' "$W/stripped/Scripts/sv_tanicorn_rail.lua"; then
    echo "  FAIL sv_tanicorn_rail.lua's header names what a zip mustn't hold"; exit 1
fi
if ! head -1 "$W/stripped/Scripts/sv_tanicorn_rail.lua" | grep -q '^-- sv_tanicorn_rail.lua'; then echo "  FAIL its header gone"; exit 1; fi
echo "  ok   sv_tanicorn_rail.lua only its header ($(wc -l < "$W/stripped/Scripts/sv_tanicorn_rail.lua") comment lines)"
if grep -n 'RE_SV_TaniRailOrder\|TANI\.rail' "$W"/stripped/Scripts/*.lua | grep -v '^[^:]*:[0-9]*:--'; then
    echo "  FAIL the railguns' or the railcannon's code left in a release's copy (above)"; exit 1
fi
echo "  ok   none of its code in any part of the release copy"
if ! OUT=$(sh lua_load_test.sh "$W/stripped" 2>&1); then echo "$OUT"; echo "  FAIL the release copy doesn't load"; exit 1; fi
echo "  ok   $(echo "$OUT" | tail -1)"
echo "tani rail test (release copy): all passed"
