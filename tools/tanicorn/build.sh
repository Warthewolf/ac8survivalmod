#!/bin/sh
# build.sh : THE TANICORN's parts (docs/re/TANICORN.md, README.md here) -> build/tanicorn/out/SurvivalMode_Tani_P.utoc / .ucas
#   0. bl_import.py     (once) the Alicorn (ACE8 Aircraft Builder GLBs) and the Tanager stand-in into build/tanicorn/src.blend
#   1. prepare_part.py  Blender 3.3: each mount in build/tanicorn/parts.json -> skinned glTF, wreck glTF, textures, sockets
#   2. ue_import.py     in the AC8 template project (E:/AC8LiveProject, UE 5.4, AC8's classes compiled): textures, the
#                       instances on AC8's gear material (stubs at AC8's paths), the rigged meshes, the wrecks
#   3. spec.py          the TaniBuild commandlet's spec; 4. TaniBuild (the SurvivalFx editor module, tools/laser7/cpp):
#                       muzzle sockets, the stock shot's stub, the blueprints straight on AC8's native classes
#   5. cook             Windows, VERSIONED (hard rule 42)
#   6. retoc to-zen     only /Game/Mods/SurvivalMode/Tanicorn -> the container, 7. pad.py (hard rule 8)
# The Tanager stand-in is Sea Power's Iowa (user, 2026-11-09: "my install only"): nothing built here is committed or
# shipped. tools/build_all.sh stages the container with TANI=1 only; package_release.sh never ships it.
set -e
cd "$(dirname "$0")/../.."
. tools/env.sh
sv_need UE "Unreal Engine 5.4's folder"
MAIN="E:/ACE8 Survival Mode"
PROJ=E:/AC8LiveProject
CMD="$UE/Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
BLENDER="${BLENDER:-C:/Program Files/Blender Foundation/Blender 3.3/blender.exe}"
OUT="$MAIN/build/tanicorn"
export MSYS_NO_PATHCONV=1
[ -f "$OUT/src.blend" ] || { echo "tanicorn: no $OUT/src.blend (bl_import.py: see README.md)"; exit 1; }
[ -f "$OUT/parts.json" ] || echo '["T5"]' > "$OUT/parts.json"
# 0. the editor module (both commandlets live in tools/laser7/cpp/SurvivalFx), built when its source changed
if ! diff -r --strip-trailing-cr tools/laser7/cpp/SurvivalFx "$PROJ/Source/SurvivalFx" > /dev/null 2>&1; then
    rm -rf "$PROJ/Source/SurvivalFx" && cp -r tools/laser7/cpp/SurvivalFx "$PROJ/Source/"
    powershell -NoProfile -Command "& '$UE/Engine/Build/BatchFiles/Build.bat' LiveEditor Win64 Development '-Project=$PROJ/Live.uproject' -WaitMutex" > "$OUT/survivalfx_build.log" 2>&1 \
        || { echo "tanicorn: the SurvivalFx module didn't build ($OUT/survivalfx_build.log)"; exit 1; }
fi
# 1. the mounts (part name, housing, guns, scale: the Leviathan's 1.9 for its turrets)
for p in $(python -I -c "import json; print(' '.join(json.load(open(r'$OUT/parts.json'))))"); do
    case "$p" in
        T5) house=IOWA_T5_1; guns=IOWA_G5_1 ;;
        *) echo "tanicorn: no recipe for part $p"; exit 1 ;;
    esac
    "$BLENDER" -b "$OUT/src.blend" -P tools/tanicorn/prepare_part.py -- "$OUT/src_$p" "Tani_$p" "$house" "$guns" 1.9 \
        > "$OUT/prepare_$p.log" 2>&1
    grep -q "prepare_part: wrote" "$OUT/prepare_$p.log" || { echo "tanicorn: preparing $p failed ($OUT/prepare_$p.log)"; exit 1; }
done
# 2. the import
SCRIPT="$(pwd -W 2>/dev/null || pwd)/tools/tanicorn/ue_import.py"
echo "tanicorn: importing the parts (log: $OUT/ue_import.log)"
"$CMD" "$PROJ/Live.uproject" -run=pythonscript -script="$SCRIPT" -unattended -nop4 -nosplash -stdout > "$OUT/ue_import_stdout.log" 2>&1 || true
tail -n 1 "$OUT/ue_import.log" | grep -q '^done$' || { echo "tanicorn: the import failed ($OUT/ue_import.log)"; exit 1; }
# 3-4. the blueprints
python -I -X utf8 tools/tanicorn/spec.py
rm -f "$PROJ"/Content/Mods/SurvivalMode/Tanicorn/BP_SV_*
echo "tanicorn: building the blueprints (log: $OUT/tanibuild.log)"
"$CMD" "$PROJ/Live.uproject" -run=TaniBuild -spec="$OUT/tani.spec.json" -log="$OUT/tanibuild.log" -unattended -nop4 -nosplash -stdout > "$OUT/tanibuild_stdout.log" 2>&1 \
    || { echo "tanicorn: TaniBuild failed ($OUT/tanibuild.log)"; grep ERROR "$OUT/tanibuild.log" | head; exit 1; }
grep -q "^done (0 errors)" "$OUT/tanibuild.log" || { echo "tanicorn: TaniBuild had errors ($OUT/tanibuild.log)"; exit 1; }
# 5. the cook
echo "tanicorn: cooking (log: $OUT/cook.log)"
rm -rf "$PROJ/Saved/Cooked"
"$CMD" "$PROJ/Live.uproject" -run=cook -targetplatform=Windows -unattended -nop4 -nosplash -stdout > "$OUT/cook.log" 2>&1
COOKED="$PROJ/Saved/Cooked/Windows/Live/Content/Mods/SurvivalMode/Tanicorn"
for a in BP_SV_Tani_T5 Model/SK_SV_Tani_T5 Model/SKEL_SV_Tani_T5 Model/SM_SV_Tani_T5_DAM; do
    [ -f "$COOKED/$a.uasset" ] || { echo "tanicorn: $a not cooked ($OUT/cook.log)"; exit 1; }
done
# 6-7. the container: our folder only (the stubs at AC8's paths never ship)
rm -rf "$OUT/stage" "$OUT/out" && mkdir -p "$OUT/stage/Live/Content/Mods/SurvivalMode" "$OUT/out"
cp -r "$COOKED" "$OUT/stage/Live/Content/Mods/SurvivalMode/"
find "$OUT/stage" -type f | sed "s#$OUT/stage/#  #"
tools/bin/retoc.exe to-zen --version UE5_4 "$OUT/stage" "$OUT/out/SurvivalMode_Tani_P.utoc"
python -I tools/x02s/pad.py "$OUT/out/SurvivalMode_Tani_P.utoc"
tools/bin/retoc.exe list "$OUT/out/SurvivalMode_Tani_P.utoc" | head -30
echo "tanicorn: built $OUT/out/SurvivalMode_Tani_P (staged with TANI=1 by tools/build_all.sh; dev installs only)"
