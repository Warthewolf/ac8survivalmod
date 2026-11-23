#!/bin/sh
# build.sh : AC:I's meteors for the ULYSSES special -> build/ulysses/out/SurvivalMode_Ulysses_P.utoc / .ucas / .pak
#   1. prepare.py         the user's AC:I install (.env ACI) + its kit -> glTF meshes (static and one-bone skeletal),
#                         the rock textures, layout.json (tools/solg/prepare.py's readers)
#   2. ue_import.py       in UE 5.4 (.env UE, project ue/Live): textures, MI_SV_Ulysses_Rock on M_Live_Base (stubbed,
#                         never packed), SM_SV_Ulysses_<K> and SK_SV_Ulysses_<K> (K = A, C, D)
#   3. cook               Windows, VERSIONED (hard rule 42), loose packages (ue/Live/Saved/Cooked/Windows/Live/Content)
#   4. retoc to-zen       only /Game/Mods/SurvivalMode/Ulysses (never the stub of AC8's M_Live_Base) -> the container
#   5. pad.py             hard rule 8 (tools/x02s/pad.py)
# AC:I's meteors are allowed for the ULYSSES special (the user, 2026-11-23; docs/rules/sources_and_toolchain.md).
# Nothing built here is committed.
set -e
cd "$(dirname "$0")/../.."
. tools/env.sh
sv_need UE "Unreal Engine 5.4's folder"
sv_need ACI "the user's Ace Combat Infinity folder (tools/solg, tools/ulysses)"
ROOT=$(pwd -W 2>/dev/null || pwd)
CMD="$UE/Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
PROJ="$ROOT/ue/Live/Live.uproject"
OUT=build/ulysses/out
export MSYS_NO_PATHCONV=1
PY3=${PY3:-"py -3.12"}
$PY3 -I tools/ulysses/prepare.py
python -I -m py_compile tools/ulysses/ue_import.py
echo "ulysses: importing in UE 5.4 (log: build/ulysses/ue_import.log)"
"$CMD" "$PROJ" -run=pythonscript -script="$ROOT/tools/ulysses/ue_import.py" -unattended -nop4 -nosplash -stdout > build/ulysses/ue_import_stdout.log 2>&1 || true
grep -q '^done$' build/ulysses/ue_import.log || { echo "ulysses: import failed (build/ulysses/ue_import.log, ue_import_stdout.log)"; tail -5 build/ulysses/ue_import.log; exit 1; }
grep -E "^SM_|^SK_" build/ulysses/ue_import.log
echo "ulysses: cooking (log: build/ulysses/cook.log)"
# VERSIONED, never -unversioned (hard rule 42: AC8's own 5.4 reflects other properties than stock 5.4)
rm -rf ue/Live/Saved/Cooked
"$CMD" "$PROJ" -run=cook -targetplatform=Windows -cookdir="$ROOT/ue/Live/Content/Mods/SurvivalMode/Ulysses" -unattended -nop4 -nosplash -stdout > build/ulysses/cook.log 2>&1
COOKED=ue/Live/Saved/Cooked/Windows/Live/Content/Mods/SurvivalMode/Ulysses
[ -d "$COOKED" ] || { echo "ulysses: nothing cooked at $COOKED"; exit 1; }
rm -rf build/ulysses/stage "$OUT" && mkdir -p build/ulysses/stage/Live/Content/Mods/SurvivalMode "$OUT"
cp -r "$COOKED" build/ulysses/stage/Live/Content/Mods/SurvivalMode/
find build/ulysses/stage -type f | sed 's#build/ulysses/stage/#  #'
tools/bin/retoc.exe to-zen --version UE5_4 build/ulysses/stage "$OUT/SurvivalMode_Ulysses_P.utoc"
python -I tools/x02s/pad.py "$OUT/SurvivalMode_Ulysses_P.utoc"
tools/bin/retoc.exe info "$OUT/SurvivalMode_Ulysses_P.utoc" | head -12
echo "ulysses: built $OUT/SurvivalMode_Ulysses_P (stage it with tools/build_all.sh)"
