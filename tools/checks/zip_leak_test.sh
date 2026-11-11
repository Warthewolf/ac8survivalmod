#!/bin/sh
# zip_leak_test.sh : tools/package_release.sh and tools/package_test.sh over a made-up build, no game needed: what each
# kind of zip carries of the containers that aren't for everyone (AGENTS.md):
#   THE TANICORN's (SurvivalMode_Tani_P: Sea Power's Iowa, the user's install only): in no zip, ZFA=1 / TESTER=1 / COOP=1
#     included (until 2026-11-11 a ZFA=1 release zip and every package_test.sh zip after a TANI=1 build kept it);
#   the ZFA-44's and its laser's (SurvivalMode_ZFA44_P, SurvivalMode_Laser7_P): only with ZFA=1;
#   tools/zip_guard.sh refuses a stage that still holds the Tanicorn's;
#   no zip's Lua holds a DEV ONLY block (the Tanicorn's test: the user, 2026-11-11, not in TESTER zips either).
# Everything happens in a temporary folder outside the repo: a copy of the packaging tools, the real Lua parts as the
# made-up build/install, empty stand-ins for the containers and main.dll, RELEASE_DIR there too, nothing registered
# (SV_LB_REGISTER=0). Your build/, build/release and .env are never touched.
set -e
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
T=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/sv_zip_leak_$$")
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
F="$T/root"
mkdir -p "$F/tools/checks" "$F/runtime" "$F/release" "$F/build/runtime" "$F/build/install/SurvivalMode" "$F/out"
for f in package_release.sh package_test.sh release_dir.sh env.sh zip_guard.sh strip_test_only.py quiet_logs.py edition.py \
         coop_edition.py novalka.py nospaceport.py build_hash.py lb_register.py lua_parts.py; do
    cp "tools/$f" "$F/tools/"
done
cp tools/checks/lua_check.py "$F/tools/checks/"
cp runtime/survival_rt.c "$F/runtime/"
cp release/README.txt release/README_COOP.txt "$F/release/"
cp -r mod/UE4SS/AC8SurvivalMode "$F/build/install/"
mkdir -p "$F/build/install/AC8SurvivalMode/dlls"
echo "made-up main.dll" > "$F/build/install/AC8SurvivalMode/dlls/main.dll"
cp "$F/build/install/AC8SurvivalMode/dlls/main.dll" "$F/build/runtime/main.dll"
echo "/* made up */" > "$F/build/runtime/submit_cfg.h"
for c in SurvivalMode_P SurvivalMode_ZFA44_P SurvivalMode_Laser7_P SurvivalMode_Tani_P SurvivalMode_Valka_P; do
    for x in utoc ucas; do echo "$c.$x" > "$F/build/install/SurvivalMode/$c.$x"; done
done

fails=0
check() { if [ "$1" = 0 ]; then echo "  ok   $2"; else echo "  FAIL $2"; fails=$((fails + 1)); fi; }
# devfree <zip>: 0 when no Lua in the zip has the user's dev install only code (a DEV ONLY block, THE TANICORN's test:
# its TANI table, sv_main.lua's TANI.setup), the user's answer of 2026-11-11: never in a TESTER zip either
devfree() { python -I -c "
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
bad = [n for n in z.namelist() if n.endswith('.lua') and any(w in z.read(n).decode('utf-8', 'replace') for w in ('DEV ONLY', 'TANI = {', 'TANI.setup'))]
sys.exit(1 if bad else 0)" "$1"; }
# holds <zip> <container>: 0 when the zip carries that container's .utoc
holds() { python -I -c "import sys, zipfile; n = zipfile.ZipFile(sys.argv[1]).namelist(); sys.exit(0 if any(x.endswith('/' + sys.argv[2] + '.utoc') for x in n) else 1)" "$1" "$2"; }
# one <label> <zip glob> <zfa: 1 kept / 0 out> <command...>: packs one zip, then what it carries
one() {
    label=$1 glob=$2 zfa=$3; shift 3
    rm -f "$F/out"/*.zip
    if (cd "$F" && env RELEASE_DIR="$F/out" SV_LB_REGISTER=0 "$@") > "$T/$label.txt" 2>&1; then
        z=$(ls "$F/out"/$glob 2>/dev/null | head -n 1)
        if [ -z "$z" ]; then check 1 "$label: a zip made ($glob)"; return; fi
        holds "$z" SurvivalMode_Tani_P && r=1 || r=0
        check $r "$label: no Tanicorn container"
        devfree "$z" && r=0 || r=1
        check $r "$label: no dev-install-only Lua (DEV ONLY blocks, the Tanicorn's test)"
        holds "$z" SurvivalMode_P && r=0 || r=1
        check $r "$label: Survival's own container in it"
        if [ "$zfa" = 1 ]; then
            holds "$z" SurvivalMode_ZFA44_P && holds "$z" SurvivalMode_Laser7_P && r=0 || r=1
            check $r "$label: the ZFA-44's and its laser's containers kept (ZFA=1)"
        else
            holds "$z" SurvivalMode_ZFA44_P || holds "$z" SurvivalMode_Laser7_P && r=1 || r=0
            check $r "$label: no ZFA-44 or laser container (no ZFA=1)"
        fi
    else
        check 1 "$label: packaged (see below)"; tail -n 8 "$T/$label.txt"
    fi
}

echo "release zips (package_release.sh online)"
one "release" "*_Online.zip" 0 sh tools/package_release.sh online 9.9.1
one "release ZFA=1" "*_Online_ZFA44.zip" 1 env ZFA=1 sh tools/package_release.sh online 9.9.2
one "release ZFA=1 TESTER=1" "*_TESTER_Online_ZFA44.zip" 1 env ZFA=1 TESTER=1 sh tools/package_release.sh online 9.9.3
one "friends' COOP2MP ZFA=1" "AC8SurvivalMode_COOP2MP_*_Online_COOP_ZFA44.zip" 1 \
    env BUILD_NAME=COOP2MP COOP=1 ZFA=1 sh tools/package_release.sh online 9.9.4
echo "test zips (package_test.sh)"
one "test zip" "AC8SurvivalMode_leak.zip" 0 sh tools/package_test.sh leak
one "test zip ZFA=1" "AC8SurvivalMode_leak_ZFA44.zip" 1 env ZFA=1 sh tools/package_test.sh leak
echo "zip_guard.sh"
mkdir -p "$T/stage/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode"
echo x > "$T/stage/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_P.utoc"
sh tools/zip_guard.sh "$T/stage" > /dev/null && r=0 || r=1
check $r "a stage without it passes"
echo x > "$T/stage/ue4ss/Mods/IoStoreLoaderMod/SurvivalMode/SurvivalMode_Tani_P.ucas"
sh tools/zip_guard.sh "$T/stage" > /dev/null && r=1 || r=0
check $r "a stage with the Tanicorn's container refused"

[ "$fails" = 0 ] && { echo "zip_leak_test: all passed"; exit 0; }
echo "zip_leak_test: $fails FAILED"
exit 1
