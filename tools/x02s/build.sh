#!/bin/sh
# build.sh : VALKA's X-02S (tools/x02s/README.md) -> build/x02s/out/SurvivalMode_Valka_P.utoc / .ucas / .pak
#   0. UModel (AC7's)     x02s_Anim -> build/x02s/umodel/.../x02s_Anim.psa (the swing wings' motion)
#   1. prepare.py         AC7's UModel glTF export -> a skinned, life-size glTF, the sweep keys, the textures
#   2. ue_import.py       in UE 5.4 (E:/UE_5.4, project ue/Live): textures, the material instance, the skinned mesh
#                         with its sockets, the sweep animation (ue_check.py samples it: build/x02s/ue_check.log)
#   3. cook               Windows, versioned (see the cook), loose packages (ue/Live/Saved/Cooked/Windows/Live/Content)
#   4. retoc to-zen       only /Game/Mods/SurvivalMode/Valka (never the stubs of AC8's materials) -> the container
#   5. pad.py             hard rule 8
# tools/build_all.sh stages the container next to SurvivalMode_P when build/x02s/out has one (no UE needed there).
set -e
cd "$(dirname "$0")/../.."
ROOT=$(pwd -W 2>/dev/null || pwd)
UE=${UE:-E:/UE_5.4}
CMD="$UE/Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
PROJ="$ROOT/ue/Live/Live.uproject"
OUT=build/x02s/out
export MSYS_NO_PATHCONV=1
UMODEL=${UMODEL:-"D:/Ace Combat PAKS/AC7UMODELnew/umodel_ace_combat_7_PC.exe"}
AC7=${AC7:-"E:/Ace Combat 7 Exports"}
"$UMODEL" -path="$AC7" -export -out="$ROOT/build/x02s/umodel" Game/Vehicles/Aircraft/x02s/x02s_Anim.uasset > build/x02s/umodel.log 2>&1
python -I tools/x02s/prepare.py
python -I -m py_compile tools/x02s/ue_import.py
echo "x02s: importing in UE 5.4 (log: build/x02s/ue_import.log)"
"$CMD" "$PROJ" -run=pythonscript -script="$ROOT/tools/x02s/ue_import.py" -unattended -nop4 -nosplash -stdout > build/x02s/ue_import_stdout.log 2>&1 || true
grep -q '^done$' build/x02s/ue_import.log || { echo "x02s: import failed (build/x02s/ue_import.log, ue_import_stdout.log)"; exit 1; }
"$CMD" "$PROJ" -run=pythonscript -script="$ROOT/tools/x02s/ue_check.py" -unattended -nop4 -nosplash -stdout > /dev/null 2>&1 || true
grep -E "vapor0|burner_01" build/x02s/ue_check.log
echo "x02s: cooking (log: build/x02s/cook.log)"
# VERSIONED (property tags by name), never -unversioned: AC8's engine (Bandai Namco's 5.4, "live-SeasonA") reflects
# other properties than stock 5.4 (UTexture's differ), so unversioned data is read by the wrong layout and the game
# stops ("ObjectSerializationError ... T_X02S_Valka_NO", crash of 2026-10-24); tagged properties load by name
rm -rf ue/Live/Saved/Cooked
"$CMD" "$PROJ" -run=cook -targetplatform=Windows -unattended -nop4 -nosplash -stdout > build/x02s/cook.log 2>&1
COOKED=ue/Live/Saved/Cooked/Windows/Live/Content/Mods/SurvivalMode/Valka
[ -d "$COOKED" ] || { echo "x02s: nothing cooked at $COOKED"; exit 1; }
rm -rf build/x02s/stage "$OUT" && mkdir -p build/x02s/stage/Live/Content/Mods/SurvivalMode "$OUT"
cp -r "$COOKED" build/x02s/stage/Live/Content/Mods/SurvivalMode/
find build/x02s/stage -type f | sed 's#build/x02s/stage/#  #'
tools/bin/retoc.exe to-zen --version UE5_4 build/x02s/stage "$OUT/SurvivalMode_Valka_P.utoc"
python -I tools/x02s/pad.py "$OUT/SurvivalMode_Valka_P.utoc"
tools/bin/retoc.exe info "$OUT/SurvivalMode_Valka_P.utoc" | head -12
tools/bin/retoc.exe list "$OUT/SurvivalMode_Valka_P.utoc" | head -20
echo "x02s: built $OUT/SurvivalMode_Valka_P (stage it with tools/build_all.sh)"
