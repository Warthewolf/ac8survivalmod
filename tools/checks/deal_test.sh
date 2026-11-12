#!/bin/sh
# deal_test.sh : THE DEAL (Scripts/sv_deal.lua, the user's dev install only) on build/checks/lua.exe
# (tools/checks/lua_build.sh makes it): tools/checks/deal_test.lua on the repo's part; then a release's copy of the parts
# (tools/strip_test_only.py) and a TESTER zip's copy (tools/dev_only.py, also with --keep-tani as a TANACORN zip's):
# sv_deal.lua only its header, its DEV ONLY blocks out of sv_hud.lua and sv_coop_migration.lua (a release's), no DEAL
# left in any part, every part still loading (lua_load_test.sh).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/deal"
SRC="$HERE/../../mod/UE4SS/AC8SurvivalMode"
"$LUA" deal_test.lua "$SRC"
header_only() {   # <copy>: sv_deal.lua only its header comments
    if grep -vq '^--' "$1/Scripts/sv_deal.lua"; then echo "  FAIL a line that isn't a comment left in sv_deal.lua"; exit 1; fi
    if ! head -1 "$1/Scripts/sv_deal.lua" | grep -q '^-- sv_deal.lua'; then echo "  FAIL its header gone"; exit 1; fi
    if grep -n '^ *DEAL *=[^=]\|CFG.specials.deal *=' "$1"/Scripts/*.lua; then echo "  FAIL DEAL still defined (above)"; exit 1; fi
    echo "  ok   sv_deal.lua only its header ($(wc -l < "$1/Scripts/sv_deal.lua") comment lines), DEAL defined nowhere"
}
loads() {
    if ! OUT=$(sh lua_load_test.sh "$1" 2>&1); then echo "$OUT"; echo "  FAIL the copy doesn't load"; exit 1; fi
    echo "  ok   $(echo "$OUT" | tail -1)"
}
echo "a release's copy (strip_test_only.py)"
rm -rf "$W" && mkdir -p "$W/stripped" "$W/tester" "$W/tani"
cp -r "$SRC/Scripts" "$SRC/config" "$W/stripped/"
rm -f "$W/stripped/config/survival.ini"
python -X utf8 -I "$HERE/../strip_test_only.py" "$W"/stripped/Scripts/*.lua "$W"/stripped/config/survival.default.ini > /dev/null
header_only "$W/stripped"
if grep -n 'DEAL' "$W/stripped/Scripts/sv_hud.lua" "$W/stripped/Scripts/sv_coop_migration.lua"; then
    echo "  FAIL THE DEAL's hooks left in a release's copy (above)"; exit 1
fi
echo "  ok   its hooks out of sv_hud.lua and sv_coop_migration.lua"
loads "$W/stripped"
for mode in tester tani; do
    echo "a TESTER zip's copy (dev_only.py$( [ $mode = tani ] && echo ' --keep-tani'))"
    cp -r "$SRC/Scripts" "$SRC/config" "$W/$mode/"
    rm -f "$W/$mode/config/survival.ini"
    if [ $mode = tani ]; then python -X utf8 -I "$HERE/../dev_only.py" --keep-tani "$W/$mode" > /dev/null
    else python -X utf8 -I "$HERE/../dev_only.py" "$W/$mode" > /dev/null; fi
    header_only "$W/$mode"
    loads "$W/$mode"
done
echo "deal test (release and TESTER copies): all passed"
