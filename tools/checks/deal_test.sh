#!/bin/sh
# deal_test.sh : THE DEAL (Scripts/sv_deal.lua, the user's dev install only) on build/checks/lua.exe
# (tools/checks/lua_build.sh makes it): tools/checks/deal_test.lua on the repo's part; then a release's copy of the parts
# (tools/strip_test_only.py) and a TESTER zip's copy (tools/dev_only.py, also with --keep-tani as a TANACORN zip's):
# THE DEAL kept whole in each (in every build since 2026-11-23), every part still loading (lua_load_test.sh).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/deal"
SRC="$HERE/../../mod/UE4SS/AC8SurvivalMode"
"$LUA" deal_test.lua "$SRC"
# ((2026-11-23) the user: "put war and haythorn into the public build. it worked") every copy keeps THE DEAL whole
kept_whole() {
    if ! grep -q '^DEAL = ' "$1/Scripts/sv_deal.lua"; then echo "  FAIL sv_deal.lua cut in this copy"; exit 1; fi
    if grep -q 'DEV ONLY' "$1/Scripts/sv_deal.lua"; then echo "  FAIL sv_deal.lua still in a DEV ONLY block"; exit 1; fi
    for f in sv_hud.lua sv_coop_migration.lua sv_main.lua sv_coop.lua; do
        grep -q 'DEAL\|DealAsk' "$1/Scripts/$f" || { echo "  FAIL THE DEAL's hook gone from $f"; exit 1; }
    done
    echo "  ok   sv_deal.lua whole ($(grep -vc '^ *--' "$1/Scripts/sv_deal.lua") lines of code), its hooks in sv_hud / sv_coop_migration / sv_main / sv_coop"
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
kept_whole "$W/stripped"
loads "$W/stripped"
for mode in tester tani; do
    echo "a TESTER zip's copy (dev_only.py$( [ $mode = tani ] && echo ' --keep-tani'))"
    cp -r "$SRC/Scripts" "$SRC/config" "$W/$mode/"
    rm -f "$W/$mode/config/survival.ini"
    if [ $mode = tani ]; then python -X utf8 -I "$HERE/../dev_only.py" --keep-tani "$W/$mode" > /dev/null
    else python -X utf8 -I "$HERE/../dev_only.py" "$W/$mode" > /dev/null; fi
    kept_whole "$W/$mode"
    loads "$W/$mode"
done
echo "deal test (release and TESTER copies): all passed"
