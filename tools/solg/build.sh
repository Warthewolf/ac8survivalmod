#!/bin/sh
# build.sh : AC:I's SOLG (tools/re/SOLG.md) -> build/solg/out/SurvivalMode_SOLG_P.utoc / .ucas / .pak
#   1. prepare.py         AC:I's SOLG (the user's AC:I install + Inveigh's kit) -> glTF meshes, textures, layout.json
#   2. ue_import.py       in UE 5.4 (.env UE, project ue/Live): textures, instances on M_Live_Base (stubbed), the
#                         static meshes, the body's part sockets
#   3. cook               Windows, VERSIONED (hard rule 42), loose packages (ue/Live/Saved/Cooked/Windows/Live/Content)
#   4. retoc to-zen       only /Game/Mods/SurvivalMode/SOLG (never the stub of AC8's M_Live_Base) -> the container
#   5. pad.py             hard rule 8 (tools/x02s/pad.py)
# AC:I assets are allowed for the SOLG round only (the user, 2026-11-03). Nothing built here is committed.
# (2026-11-22: kept from the parked SOLG; step 2 of docs/design SOLG plan rewrites it: no stubbed material, hard rule 58)
set -e
cd "$(dirname "$0")/../.."
. tools/env.sh
sv_need UE "Unreal Engine 5.4's folder"
sv_need ACI "the user's Ace Combat Infinity folder (tools/solg)"
ROOT=$(pwd -W 2>/dev/null || pwd)
CMD="$UE/Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
PROJ="$ROOT/ue/Live/Live.uproject"
OUT=build/solg/out
export MSYS_NO_PATHCONV=1
PY3=${PY3:-"py -3.12"}
$PY3 -I tools/solg/prepare.py
python -I -m py_compile tools/solg/ue_import.py
echo "solg: importing in UE 5.4 (log: build/solg/ue_import.log)"
"$CMD" "$PROJ" -run=pythonscript -script="$ROOT/tools/solg/ue_import.py" -unattended -nop4 -nosplash -stdout > build/solg/ue_import_stdout.log 2>&1 || true
grep -q '^done$' build/solg/ue_import.log || { echo "solg: import failed (build/solg/ue_import.log, ue_import_stdout.log)"; tail -5 build/solg/ue_import.log; exit 1; }
grep -E "axis probe|sockets on|SM_SV_SOLG_Body:" build/solg/ue_import.log
echo "solg: cooking (log: build/solg/cook.log)"
# VERSIONED, never -unversioned (hard rule 42: AC8's own 5.4 reflects other properties than stock 5.4)
rm -rf ue/Live/Saved/Cooked
"$CMD" "$PROJ" -run=cook -targetplatform=Windows -unattended -nop4 -nosplash -stdout > build/solg/cook.log 2>&1
COOKED=ue/Live/Saved/Cooked/Windows/Live/Content/Mods/SurvivalMode/SOLG
[ -d "$COOKED" ] || { echo "solg: nothing cooked at $COOKED"; exit 1; }
rm -rf build/solg/stage "$OUT" && mkdir -p build/solg/stage/Live/Content/Mods/SurvivalMode "$OUT"
cp -r "$COOKED" build/solg/stage/Live/Content/Mods/SurvivalMode/
find build/solg/stage -type f | sed 's#build/solg/stage/#  #'
tools/bin/retoc.exe to-zen --version UE5_4 build/solg/stage "$OUT/SurvivalMode_SOLG_P.utoc"
python -I tools/x02s/pad.py "$OUT/SurvivalMode_SOLG_P.utoc"
tools/bin/retoc.exe info "$OUT/SurvivalMode_SOLG_P.utoc" | head -12
echo "solg: built $OUT/SurvivalMode_SOLG_P (stage it with tools/build_all.sh)"
