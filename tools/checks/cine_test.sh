#!/bin/sh
# cine_test.sh : THE TANACORN's rise cinematic and its director (Scripts/sv_cine.lua, docs/re/CINEMATIC.md; the user,
# 2026-11-11) on build/checks/lua.exe (tools/checks/lua_build.sh makes it): tools/checks/cine_test.lua on a copy of the
# mod's Scripts and config (its camera file written there, never in the repo), the real sv_core, sv_config, sv_ai and
# sv_hud with the game stubbed; then a release's copy of the parts (tools/strip_test_only.py): sv_cine.lua only its header,
# sv_hud.lua's HUD.hold still in, every part still loading (lua_load_test.sh).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/cine"
SRC="$HERE/../../mod/UE4SS/AC8SurvivalMode"
rm -rf "$W" && mkdir -p "$W/mod" "$W/stripped"
cp -r "$SRC/Scripts" "$SRC/config" "$W/mod/"
rm -f "$W/mod/config/survival.ini" "$W/mod/config/rise_camera"*.txt
"$LUA" cine_test.lua "$W/mod"
echo "a release's copy (strip_test_only.py)"
cp -r "$SRC/Scripts" "$SRC/config" "$W/stripped/"
rm -f "$W/stripped/config/survival.ini" "$W/stripped/config/rise_camera"*.txt
python -X utf8 -I "$HERE/../strip_test_only.py" "$W"/stripped/Scripts/*.lua "$W"/stripped/config/survival.default.ini > /dev/null
if grep -n 'CINE = \|testKey(\|TEST_TICKS\|LEVEL_DROPS\|rise_camera' "$W/stripped/Scripts/sv_cine.lua" | grep -v '^[0-9]*:--'; then
    echo "  FAIL code of sv_cine.lua left in a release's copy (above)"; exit 1
fi
if ! head -1 "$W/stripped/Scripts/sv_cine.lua" | grep -q '^-- sv_cine.lua'; then echo "  FAIL its header gone"; exit 1; fi
if grep -vq '^--' "$W/stripped/Scripts/sv_cine.lua"; then echo "  FAIL a line that isn't a comment left in sv_cine.lua"; exit 1; fi
echo "  ok   sv_cine.lua only its header ($(wc -l < "$W/stripped/Scripts/sv_cine.lua") comment lines)"
if ! grep -q '^function HUD.hold' "$W/stripped/Scripts/sv_hud.lua"; then echo "  FAIL HUD.hold taken out of sv_hud.lua"; exit 1; fi
echo "  ok   sv_hud.lua's HUD.hold left in"
if ! OUT=$(sh lua_load_test.sh "$W/stripped" 2>&1); then echo "$OUT"; echo "  FAIL the release copy doesn't load"; exit 1; fi
echo "  ok   $(echo "$OUT" | tail -1)"
if ls "$HERE/../../build/checks/load/mod/config/rise_camera"*.txt > /dev/null 2>&1; then   # (lua_load_test.sh's own copy)
    echo "  FAIL a release's copy wrote a camera file"; exit 1
fi
echo "  ok   no camera file made by a release's copy"
echo "cine test (release copy): all passed"
