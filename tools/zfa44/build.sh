#!/bin/sh
# build.sh : the ZFA-44EL (the user's own model from their AC7 mod; tools/re/ZFA44.md "T0 build")
#            -> build/zfa44/out/SurvivalMode_ZFA44_P.utoc / .ucas / .pak
#   1. prepare.py         build/zfa44's extraction -> one skinned, life-size glTF with its socket bones, the textures
#   2. ue_import.py       in UE 5.4 (E:/UE_5.4, this tree's ue/Live): textures, MI_ZFA44_* on the x40a's gear instance
#                         (stubbed), SK_ZFA44 (+ skeleton, physics asset); build/zfa44/ue_import.log
#   3. cook               Windows, VERSIONED (hard rule 42), loose packages (ue/Live/Saved/Cooked/Windows/Live/Content);
#                         checked: every package versioned, no texture virtual, no shader map of ours
#   4. retoc to-zen       only /Game/Mods/SurvivalMode/ZFA44 (never the stubs of AC8's materials) -> the container
#   5. pad.py             hard rule 8 (tools/x02s/pad.py)
# Dev only (the user's own build): tools/build_all.sh stages the container with ZFA=1 only, tools/package_dev.sh keeps it
# with ZFA=1 only, tools/package_release.sh never ships it. Nothing built here is committed (build/ and ue/Live's
# content are git-ignored).
set -e
cd "$(dirname "$0")/../.."
ROOT=$(pwd -W 2>/dev/null || pwd)
UE=${UE:-E:/UE_5.4}
CMD="$UE/Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
PROJ="$ROOT/ue/Live/Live.uproject"
B=build/zfa44
OUT=$B/out
PY3=${PY3:-"py -3.12"}
export MSYS_NO_PATHCONV=1
[ -f "$B/mesh/uavs_SM.gltf" ] || { echo "zfa44: no extraction in $B (tools/re/ZFA44.md)"; exit 1; }
$PY3 -I tools/zfa44/prepare.py
python -I -m py_compile tools/zfa44/ue_import.py
echo "zfa44: importing in UE 5.4 (log: $B/ue_import.log)"
"$CMD" "$PROJ" -run=pythonscript -script="$ROOT/tools/zfa44/ue_import.py" -unattended -nop4 -nosplash -stdout > $B/ue_import_stdout.log 2>&1 || true
grep -q '^done$' $B/ue_import.log || { echo "zfa44: import failed ($B/ue_import.log, ue_import_stdout.log)"; tail -5 $B/ue_import.log; exit 1; }
grep -E "slots:|bounds|bone burner_0[12]|within" $B/ue_import.log
echo "zfa44: cooking (log: $B/cook.log)"
# VERSIONED, never -unversioned (hard rule 42: AC8's own 5.4 reflects other properties than stock 5.4)
rm -rf ue/Live/Saved/Cooked
"$CMD" "$PROJ" -run=cook -targetplatform=Windows -unattended -nop4 -nosplash -stdout > $B/cook.log 2>&1
grep -E "Success - [0-9]+ error|Failure - " $B/cook.log | tail -1
COOKED=ue/Live/Saved/Cooked/Windows/Live/Content/Mods/SurvivalMode/ZFA44
[ -d "$COOKED" ] || { echo "zfa44: nothing cooked at $COOKED"; exit 1; }
# the cooked packages checked before packing (FALKEN_MATERIALS.md 5.2.vi): versioned (a legacy summary's UE4 / UE5
# versions are 0 when unversioned), the textures ordinary (tools/checks/tex_info.py), the instances without a shader map
# of their own and importing the x40a's gear instance, the mesh importing MI_ZFA44_* and M_NPC_Canopy
if ! python -I - "$COOKED" > $B/cook_check.log <<'EOF'
import os, struct, subprocess, sys
root = sys.argv[1]
bad = []
for dp, _, fs in os.walk(root):
    for f in sorted(fs):
        if not f.endswith('.uasset'):
            continue
        p = os.path.join(dp, f)
        d = open(p, 'rb').read()
        tag, legacy, _, ue4, ue5 = struct.unpack_from('<Iiiii', d, 0)
        ok = tag == 0x9E2A83C1 and ue4 > 0 and ue5 > 0
        print(f'{f}: {"versioned" if ok else "UNVERSIONED"} (UE4 {ue4}, UE5 {ue5})')
        if not ok:
            bad.append(f + ' unversioned')
        x = p[:-6] + 'uexp'                         # (a legacy cook: the exports' data, platform data and shader maps there)
        info = subprocess.run([sys.executable, '-I', 'tools/checks/tex_info.py', x if os.path.exists(x) else p],
                              capture_output=True, text=True).stdout.strip()
        print('   ' + info)
        if f.startswith('T_') and 'virtual False' not in info:
            bad.append(f + ' not an ordinary texture')
        if f.startswith('MI_'):
            if 'neither a texture nor a material with a shader map' not in info:
                bad.append(f + ' has a shader map of its own')
            if b'MI_PP0016_x40a_Gear' not in d:
                bad.append(f + " doesn't import MI_PP0016_x40a_Gear")
        if f == 'SK_ZFA44.uasset':
            for n in (b'MI_ZFA44_Body', b'MI_ZFA44_Pod', b'MI_ZFA44_Fairing', b'M_NPC_Canopy', b'SKEL_ZFA44'):
                if n not in d:
                    bad.append('SK_ZFA44 names no ' + n.decode())
print('cook check: ' + ('OK' if not bad else 'FAILED: ' + '; '.join(bad)))
sys.exit(1 if bad else 0)
EOF
then tail -3 $B/cook_check.log; exit 1; fi
tail -1 $B/cook_check.log
rm -rf $B/stage "$OUT" && mkdir -p $B/stage/Live/Content/Mods/SurvivalMode "$OUT"
cp -r "$COOKED" $B/stage/Live/Content/Mods/SurvivalMode/
find $B/stage -type f | sed "s#$B/stage/#  #"
tools/bin/retoc.exe to-zen --version UE5_4 $B/stage "$OUT/SurvivalMode_ZFA44_P.utoc"
python -I tools/x02s/pad.py "$OUT/SurvivalMode_ZFA44_P.utoc"
tools/bin/retoc.exe info "$OUT/SurvivalMode_ZFA44_P.utoc" | head -12
tools/bin/retoc.exe list "$OUT/SurvivalMode_ZFA44_P.utoc" | head -30
echo "zfa44: built $OUT/SurvivalMode_ZFA44_P (dev only: ZFA=1 sh tools/build_all.sh, ZFA=1 sh tools/package_dev.sh <name>)"
