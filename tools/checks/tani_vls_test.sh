#!/bin/sh
# tani_vls_test.sh : THE TANACORN's VLS blocks in Scripts/sv_tanicorn.lua (2026-11-12, WP1's VLS route: docs/re/TANICORN.md
# "VLS"; Ctrl+K, the lids, their missiles, the rows) on build/checks/lua.exe (tools/checks/lua_build.sh makes it):
# tools/checks/tani_vls_test.lua on a copy of the mod's Scripts, the part alone with the game stubbed; then a release's copy
# of the parts (tools/strip_test_only.py): sv_tanicorn.lua only its header (INVINCIBLE FLEET is the user's dev install
# only), every part still loading (lua_load_test.sh).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/tani_vls"
SRC="$HERE/../../mod/UE4SS/AC8SurvivalMode"
rm -rf "$W" && mkdir -p "$W/mod" "$W/stripped"
cp -r "$SRC/Scripts" "$W/mod/"
"$LUA" tani_vls_test.lua "$W/mod/Scripts/"
echo "a release's copy (strip_test_only.py)"
cp -r "$SRC/Scripts" "$SRC/config" "$W/stripped/"
rm -f "$W/stripped/config/survival.ini" "$W/stripped/config/rise_camera"*.txt
python -X utf8 -I "$HERE/../strip_test_only.py" "$W"/stripped/Scripts/*.lua "$W"/stripped/config/survival.default.ini > /dev/null
if grep -n 'TANI\|testKey(\|TEST_TICKS\|NotifyOnNewObject' "$W/stripped/Scripts/sv_tanicorn.lua" | grep -v '^[0-9]*:--'; then
    echo "  FAIL code of sv_tanicorn.lua left in a release's copy (above)"; exit 1
fi
if grep -vq '^--' "$W/stripped/Scripts/sv_tanicorn.lua"; then echo "  FAIL a line that isn't a comment left in sv_tanicorn.lua"; exit 1; fi
echo "  ok   sv_tanicorn.lua only its header ($(wc -l < "$W/stripped/Scripts/sv_tanicorn.lua") comment lines)"
# ((2026-11-12) the hit probe's piece too)
if grep -vq '^--' "$W/stripped/Scripts/sv_tanicorn_hits.lua"; then echo "  FAIL a line that isn't a comment left in sv_tanicorn_hits.lua"; exit 1; fi
echo "  ok   sv_tanicorn_hits.lua only its header ($(wc -l < "$W/stripped/Scripts/sv_tanicorn_hits.lua") comment lines)"
if ! OUT=$(sh lua_load_test.sh "$W/stripped" 2>&1); then echo "$OUT"; echo "  FAIL the release copy doesn't load"; exit 1; fi
echo "  ok   $(echo "$OUT" | tail -1)"
echo "tani vls test (release copy): all passed"
