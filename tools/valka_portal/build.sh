#!/bin/sh
# build.sh : VALKA's portal (docs/re/VALKA.md section 8) -> build/valka_portal/out/SurvivalMode_ValkaPortal_P.utoc / .ucas
#   1. make_portal.py  Blender 3.3: the black hole's pieces from numbers, one design (PORTAL_DESIGN, default detailed)
#                      -> build/valka_portal/src/<design>/SM_SV_BH*.glb and its manifest.json (the pieces, their colours)
#   2. ue_import.py    in the AC8 template project ($AC8_LIVE_PROJECT, UE 5.4): static meshes under
#                      /Game/Mods/SurvivalMode/ValkaPortal/Model, each on the engine's BasicShapeMaterial (AC8 has it; no
#                      material of ours: hard rule 58)
#   3. cook            Windows, VERSIONED (hard rule 42)
#   4. retoc to-zen    only /Game/Mods/SurvivalMode/ValkaPortal -> the container, 5. pad.py (hard rule 8)
# tools/build_all.sh stages it with VALKA's X-02S; package_release.sh NOVALKA and package_dev.sh without VALKA drop it.
# The game must be closed: the editor and AC8 together don't fit in memory (the autotest's runs of 2026-11-22).
set -e
cd "$(dirname "$0")/../.."
. tools/env.sh
sv_need BLENDER "Blender 3.3's blender.exe (tools/valka_portal)"
sv_need UE "Unreal Engine 5.4's folder"
sv_need AC8_LIVE_PROJECT "the AC8 template project (Live.uproject's folder)"
MAIN=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [ -n "$MAIN" ]; then MAIN=$(dirname "$MAIN"); else MAIN=$(pwd); fi
OUT="$MAIN/build/valka_portal"
PROJ=$AC8_LIVE_PROJECT
CMD="$UE/Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
export MSYS_NO_PATHCONV=1
mkdir -p "$OUT/src"
if tasklist 2>/dev/null | grep -qi "AceCombat8.exe"; then echo "valka_portal: AC8 is running: close it first (memory)"; exit 1; fi
# 1. the pieces
WIN_OUT=$(cd "$OUT" && (pwd -W 2>/dev/null || pwd))
echo "valka_portal: modelling the pieces (log: $OUT/make.log)"
DESIGN=${PORTAL_DESIGN:-detailed}
rm -rf "$OUT/src/$DESIGN"
"$BLENDER" -b -P tools/valka_portal/make_portal.py -- "$WIN_OUT/src" "$DESIGN" > "$OUT/make.log" 2>&1 || true
grep "^portal:" "$OUT/make.log" | sed 's/ -> .*//'
grep -q "^portal: done" "$OUT/make.log" || { echo "valka_portal: the model failed ($OUT/make.log)"; exit 1; }
# 2. the import
export SV_PORTAL_SRC="$WIN_OUT/src/$DESIGN" SV_PORTAL_LOG="$WIN_OUT/ue_import.log"
SCRIPT="$(pwd -W 2>/dev/null || pwd)/tools/valka_portal/ue_import.py"
echo "valka_portal: importing them (log: $OUT/ue_import.log)"
rm -f "$OUT/ue_import.log"
"$CMD" "$PROJ/Live.uproject" -run=pythonscript -script="$SCRIPT" -unattended -nop4 -nosplash -stdout > "$OUT/ue_import_stdout.log" 2>&1 || true
cat "$OUT/ue_import.log" 2>/dev/null | sed 's/^/  /'
tail -n 1 "$OUT/ue_import.log" 2>/dev/null | grep -q '^done$' || { echo "valka_portal: the import failed ($OUT/ue_import.log, $OUT/ue_import_stdout.log)"; exit 1; }
# 3. the cook (versioned: no -unversioned)
echo "valka_portal: cooking (log: $OUT/cook.log)"
rm -rf "$PROJ/Saved/Cooked"
"$CMD" "$PROJ/Live.uproject" -run=cook -targetplatform=Windows -unattended -nop4 -nosplash -stdout > "$OUT/cook.log" 2>&1 || true
COOKED="$PROJ/Saved/Cooked/Windows/Live/Content/Mods/SurvivalMode/ValkaPortal"
for n in $(python -I tools/valka_portal/parts_lua.py --names "$OUT/src/$DESIGN/manifest.json"); do
    [ -f "$COOKED/Model/$n.uasset" ] || { echo "valka_portal: $n not cooked ($OUT/cook.log)"; grep -i "error" "$OUT/cook.log" | tail -5; exit 1; }
done
cp "$OUT/src/$DESIGN/manifest.json" "$OUT/manifest.json"     # (the pieces cooked: tools/valka_portal/parts_lua.py)
# 4-5. the container: our folder only
rm -rf "$OUT/stage" "$OUT/out" && mkdir -p "$OUT/stage/Live/Content/Mods/SurvivalMode" "$OUT/out"
cp -r "$COOKED" "$OUT/stage/Live/Content/Mods/SurvivalMode/"
find "$OUT/stage" -type f | sed "s#$OUT/stage/#  #"
tools/bin/retoc.exe to-zen --version UE5_4 "$OUT/stage" "$OUT/out/SurvivalMode_ValkaPortal_P.utoc"
python -I tools/x02s/pad.py "$OUT/out/SurvivalMode_ValkaPortal_P.utoc"
tools/bin/retoc.exe list "$OUT/out/SurvivalMode_ValkaPortal_P.utoc" | head -20
echo "valka_portal: built $OUT/out/SurvivalMode_ValkaPortal_P (staged with VALKA's X-02S by tools/build_all.sh)"
