#!/bin/sh
# build.sh : THE TANACORN's parts (docs/re/TANICORN.md, README.md here) -> build/tanicorn/out/SurvivalMode_Tani_P.utoc / .ucas
#   1. model_tanacorn.py   Blender 3.3: the Leviathan design (art/tanicorn/design, in the repo) -> build/tanicorn/model/
#                          Tanacorn_model.blend (made again only when the design or the scripts changed; ~2 min)
#   2. export_tanacorn.py  every part type out of it -> build/tanicorn/src_<part> (glTF, wreck, textures, json) and
#                          parts.json; check_export.py reads every glTF back and compares it with its json
#   3. ue_import.py        in the AC8 template project (E:/AC8LiveProject, UE 5.4, AC8's classes compiled): textures, the
#                          instances on AC8's gear material (stubs at AC8's paths), the rigged meshes, the VLS blocks'
#                          Open animations, the hull's static mesh, the wrecks
#   4. spec.py             the TaniBuild commandlet's spec; 5. TaniBuild (the SurvivalFx editor module, tools/laser7/cpp):
#                          the parts' sockets, the hull's 36 Mount_* sockets, the stock shot's stub, the gun mounts'
#                          blueprints straight on AC8's native classes
#   6. cook                Windows, VERSIONED (hard rule 42)
#   7. retoc to-zen        only /Game/Mods/SurvivalMode/Tanicorn -> the container, 8. pad.py (hard rule 8)
# TANI_PARTS=T5,HULL builds only those parts (the import, the spec, the cook's checks). TANI_STOP=export stops after
# step 2 (no UE needed: the parts on disk and their check).
# The Tanager stand-in is Sea Power's Iowa (user, 2026-11-09: "my install only"): nothing built here is
# shipped. tools/build_all.sh stages the container with TANI=1 only; package_release.sh never ships it.
set -e
cd "$(dirname "$0")/../.."
. tools/env.sh
MAIN="E:/ACE8 Survival Mode"
PROJ=E:/AC8LiveProject
CMD="$UE/Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
BLENDER="${BLENDER:-C:/Program Files/Blender Foundation/Blender 3.3/blender.exe}"
OUT="$MAIN/build/tanicorn"
export MSYS_NO_PATHCONV=1
mkdir -p "$OUT"
export TANI_BUILD="$OUT"
# 1. the model, when the design or a script that makes it is newer than it
MODEL="$OUT/model/Tanacorn_model.blend"
DESIGN=art/tanicorn/design/Leviathan_animated.blend
stale=0
[ -f "$MODEL" ] || stale=1
for f in "$DESIGN" tools/tanicorn/model_tanacorn.py tools/tanicorn/hull_uv.py tools/tanicorn/straighten.py; do
    [ "$stale" = 1 ] || [ "$f" -nt "$MODEL" ] && stale=1
done
if [ "$stale" = 1 ]; then
    echo "tanicorn: building the model (log: $OUT/model.log; about 2 minutes)"
    "$BLENDER" -b "$DESIGN" -P tools/tanicorn/model_tanacorn.py -- "$OUT/model" > "$OUT/model.log" 2>&1 || true
    grep -q "^model: every part clean: True" "$OUT/model.log" && grep -q "^model: saved" "$OUT/model.log" \
        || { echo "tanicorn: the model didn't build clean ($OUT/model.log)"; grep -i "error\|assert" "$OUT/model.log" | head; exit 1; }
fi
# 2. the parts, and each read back
rm -rf "$OUT"/src_* "$OUT/parts.json"
"$BLENDER" -b "$MODEL" -P tools/tanicorn/export_tanacorn.py -- "$OUT" > "$OUT/export.log" 2>&1 || true
grep "^export:" "$OUT/export.log" || true
grep -q "^export: [0-9]* parts;" "$OUT/export.log" || { echo "tanicorn: the export failed ($OUT/export.log)"; exit 1; }
"$BLENDER" -b -P tools/tanicorn/check_export.py -- "$OUT" > "$OUT/export_check.log" 2>&1 || true
grep -q "^CHECK ALL OK" "$OUT/export_check.log" \
    || { echo "tanicorn: an exported part doesn't read back right ($OUT/export_check.log)"; grep "CHECK FAIL" "$OUT/export_check.log"; exit 1; }
grep "^CHECK ALL OK" "$OUT/export_check.log"
[ "$TANI_STOP" = export ] && { echo "tanicorn: stopped after the export (TANI_STOP=export): $OUT/src_*"; exit 0; }
sv_need UE "Unreal Engine 5.4's folder"
# the editor module (both commandlets live in tools/laser7/cpp/SurvivalFx), built when its source changed
if ! diff -r --strip-trailing-cr tools/laser7/cpp/SurvivalFx "$PROJ/Source/SurvivalFx" > /dev/null 2>&1; then
    rm -rf "$PROJ/Source/SurvivalFx" && cp -r tools/laser7/cpp/SurvivalFx "$PROJ/Source/"
    powershell -NoProfile -Command "& '$UE/Engine/Build/BatchFiles/Build.bat' LiveEditor Win64 Development '-Project=$PROJ/Live.uproject' -WaitMutex" > "$OUT/survivalfx_build.log" 2>&1 \
        || { echo "tanicorn: the SurvivalFx module didn't build ($OUT/survivalfx_build.log)"; grep -i " error " "$OUT/survivalfx_build.log" | head; exit 1; }
fi
# 3. the import
SCRIPT="$(pwd -W 2>/dev/null || pwd)/tools/tanicorn/ue_import.py"
echo "tanicorn: importing the parts (log: $OUT/ue_import.log; the hull and 13 parts: several minutes)"
rm -f "$OUT/ue_import.log"
"$CMD" "$PROJ/Live.uproject" -run=pythonscript -script="$SCRIPT" -unattended -nop4 -nosplash -stdout > "$OUT/ue_import_stdout.log" 2>&1 || true
tail -n 1 "$OUT/ue_import.log" | grep -q '^done$' || { echo "tanicorn: the import failed ($OUT/ue_import.log)"; grep "FAILED" "$OUT/ue_import.log"; exit 1; }
grep "WARNING\|NOTE\|warnings$" "$OUT/ue_import.log" || true
# 4-5. the sockets and the blueprints
python -I -X utf8 tools/tanicorn/spec.py
rm -f "$PROJ"/Content/Mods/SurvivalMode/Tanicorn/BP_SV_*
echo "tanicorn: building the blueprints (log: $OUT/tanibuild.log)"
"$CMD" "$PROJ/Live.uproject" -run=TaniBuild -spec="$OUT/tani.spec.json" -log="$OUT/tanibuild.log" -unattended -nop4 -nosplash -stdout > "$OUT/tanibuild_stdout.log" 2>&1 \
    || { echo "tanicorn: TaniBuild failed ($OUT/tanibuild.log)"; grep ERROR "$OUT/tanibuild.log" | head; exit 1; }
grep -q "^done (0 errors)" "$OUT/tanibuild.log" || { echo "tanicorn: TaniBuild had errors ($OUT/tanibuild.log)"; exit 1; }
# 6. the cook
echo "tanicorn: cooking (log: $OUT/cook.log)"
rm -rf "$PROJ/Saved/Cooked"
"$CMD" "$PROJ/Live.uproject" -run=cook -targetplatform=Windows -unattended -nop4 -nosplash -stdout > "$OUT/cook.log" 2>&1
COOKED="$PROJ/Saved/Cooked/Windows/Live/Content/Mods/SurvivalMode/Tanicorn"
# (what must be there: by each part's kind, from the export's json)
for a in $(python -I -c "
import json, os
out = r'$OUT'
only = [x for x in os.environ.get('TANI_PARTS', '').split(',') if x]
for p in json.load(open(os.path.join(out, 'parts.json'))):
    if only and p not in only:
        continue
    k = json.load(open(os.path.join(out, 'src_' + p, 'Tani_%s.json' % p))).get('kind', 'turret')
    n = 'Tani_' + p
    deploy = ['Model/SK_SV_' + n, 'Model/SKEL_SV_' + n, 'Model/SM_SV_%s_DAM' % n, 'Model/AS_SV_%s_Deploy' % n]
    print(' '.join({'hull': ['Model/SM_SV_' + n, 'BP_SV_' + n],
                    'vls': ['Model/SK_SV_' + n, 'Model/SKEL_SV_' + n, 'Model/SM_SV_%s_DAM' % n, 'Model/AS_SV_%s_Open' % n],
                    'railcannon': deploy, 'railgun': deploy,       # (no blueprint of their own yet: the hull's draws them)
                    'rig': ['Model/SK_SV_' + n, 'Model/SKEL_SV_' + n, 'Model/AS_SV_%s_Rise' % n],   # (2026-11-11: the rise rig)
                    'turret': ['BP_SV_' + n, 'Model/SK_SV_' + n, 'Model/SKEL_SV_' + n, 'Model/SM_SV_%s_DAM' % n]}[k]))
" | tr -d '\r'); do                 # (Windows' Python ends its lines in CR LF: the CR stuck to each line's last name)
    [ -f "$COOKED/$a.uasset" ] || { echo "tanicorn: $a not cooked ($OUT/cook.log)"; exit 1; }
done
# 7-8. the container: our folder only (the stubs at AC8's paths never ship)
rm -rf "$OUT/stage" "$OUT/out" && mkdir -p "$OUT/stage/Live/Content/Mods/SurvivalMode" "$OUT/out"
cp -r "$COOKED" "$OUT/stage/Live/Content/Mods/SurvivalMode/"
find "$OUT/stage" -type f | sed "s#$OUT/stage/#  #"
tools/bin/retoc.exe to-zen --version UE5_4 "$OUT/stage" "$OUT/out/SurvivalMode_Tani_P.utoc"
python -I tools/x02s/pad.py "$OUT/out/SurvivalMode_Tani_P.utoc"
tools/bin/retoc.exe list "$OUT/out/SurvivalMode_Tani_P.utoc" | head -60
echo "tanicorn: built $OUT/out/SurvivalMode_Tani_P (staged with TANI=1 by tools/build_all.sh; dev installs only)"
