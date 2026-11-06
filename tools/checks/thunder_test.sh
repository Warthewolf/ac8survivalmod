#!/bin/sh
# thunder_test.sh : runs tools/checks/thunder_test.lua (the lightning Anomaly IFF FATAL ERROR / DI..ANT TH..D..R and the
# storm test, Scripts/sv_anomalies.lua THUNDER, test builds only: tools/re/THUNDER.md) on the real parts with
# build/checks/lua.exe (tools/checks/lua_build.sh makes it), then a copy of the parts as a release has them
# (tools/strip_test_only.py): no trace of it or its keys left in any part, and every part still loads (lua_load_test.sh).
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
sh lua_build.sh
LUA="$HERE/../../build/checks/lua.exe"
W="$HERE/../../build/checks/thunder"
SRC="$HERE/../../mod/UE4SS/AC8SurvivalMode"
rm -rf "$W" && mkdir -p "$W/Scripts" "$W/config" "$W/stripped"
"$LUA" thunder_test.lua "$SRC" "$W"
echo "a release's copy (strip_test_only.py)"
cp -r "$SRC/Scripts" "$SRC/config" "$W/stripped/"
python -X utf8 -I "$HERE/../strip_test_only.py" "$W"/stripped/Scripts/*.lua > /dev/null
if grep -il 'thunder\|IFF FATAL ERROR\|DI\.\.ANT\|Lightninig\|LightningVolume\|"HOME"\|"ZERO"' "$W"/stripped/Scripts/*.lua; then
    echo "  FAIL a trace of it left in the parts above"; exit 1
fi
echo "  ok   no trace of it or its keys left in any part"
if ! OUT=$(sh lua_load_test.sh "$W/stripped" 2>&1); then echo "$OUT"; echo "  FAIL the release copy doesn't load"; exit 1; fi
echo "  ok   $(echo "$OUT" | tail -1)"
echo "thunder test (release copy): all passed"
