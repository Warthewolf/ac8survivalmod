#!/bin/sh
# build.sh : AC7's LaserInterceptor for AC8 (tools/laser7/README.md) -> build/laser7/out/SurvivalMode_Laser7_P.utoc / .ucas
#   0. UModel (AC7's)   the beam's meshes and the sparks' texture (build/ac7/laser/umodel), once
#   1. ue_import.py     in the AC8 template project ($AC8_LIVE_PROJECT, UE 5.4): meshes, texture, the four materials
#   2. spec.py          the commandlet's spec: AC7's swing curve, its two beam effects (fxspec.py), the blueprint
#   3. LaserFx          (the SurvivalFx editor module's commandlet, tools/laser7/cpp) builds them
#   4. cook             Windows, VERSIONED (hard rule 42)
#   5. retoc to-zen     only /Game/Mods/SurvivalMode/Laser7 -> the container, 6. pad.py (hard rule 8)
# AC7 assets (the user's exception of 2026-11-07, AGENTS.md): nothing of AC7's goes into git, only these scripts.
set -e
cd "$(dirname "$0")/../.."
. tools/env.sh
sv_need UE "Unreal Engine 5.4's folder"
sv_need UMODEL "AC7's UModel exe"
sv_need AC7 "AC7's exported assets"
sv_need AC8_LIVE_PROJECT "the AC8 template project (Live.uproject's folder) for tools/laser7"
PROJ=$AC8_LIVE_PROJECT
# the main git tree (build outputs live in its build/, as the release zips; as tools/release_dir.sh), else this checkout
MAIN=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [ -n "$MAIN" ]; then MAIN=$(dirname "$MAIN"); else MAIN=$(pwd); fi
export SV_ROOT="$MAIN"                              # (spec.py and ue_import.py read it)
CMD="$UE/Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
OUT="$MAIN/build/laser7"
UM="$MAIN/build/ac7/laser/umodel"
export MSYS_NO_PATHCONV=1
mkdir -p "$OUT"
if [ ! -f "$UM/Game/VFX/Vehicles/Weapon/TLS/mesh/SM_TLS_projectile_tip.gltf" ]; then
    for a in mesh/SM_TLS_01 mesh/SM_TLS_projectile_root mesh/SM_TLS_projectile_tip material/m_TLS_03; do
        "$UMODEL" -path="$AC7" -export -gltf -png -out="$UM" "Game/VFX/Vehicles/Weapon/TLS/$a.uasset" >> "$OUT/umodel.log" 2>&1
    done
fi
# the SurvivalFx module in the template project (its commandlet), built when its source changed
if ! cmp -s tools/laser7/cpp/SurvivalFx/Private/LaserFxCommandlet.cpp "$PROJ/Source/SurvivalFx/Private/LaserFxCommandlet.cpp"; then
    rm -rf "$PROJ/Source/SurvivalFx" && cp -r tools/laser7/cpp/SurvivalFx "$PROJ/Source/"
    powershell -NoProfile -Command "& '$UE/Engine/Build/BatchFiles/Build.bat' LiveEditor Win64 Development '-Project=$PROJ/Live.uproject' -WaitMutex" > "$OUT/survivalfx_build.log" 2>&1 \
        || { echo "laser7: the SurvivalFx module didn't build ($OUT/survivalfx_build.log)"; exit 1; }
fi
SCRIPT="$(pwd -W 2>/dev/null || pwd)/tools/laser7/ue_import.py"
echo "laser7: importing the beam's parts (log: $OUT/ue_import.log)"
"$CMD" "$PROJ/Live.uproject" -run=pythonscript -script="$SCRIPT" -unattended -nop4 -nosplash -stdout > "$OUT/ue_import_stdout.log" 2>&1 || true
tail -n 1 "$OUT/ue_import.log" | grep -q '^done$' || { echo "laser7: the import failed ($OUT/ue_import.log)"; exit 1; }
python -I -X utf8 tools/laser7/spec.py
rm -f "$PROJ"/Content/Mods/SurvivalMode/Laser7/CUR_SV_* "$PROJ"/Content/Mods/SurvivalMode/Laser7/FX_SV_* "$PROJ"/Content/Mods/SurvivalMode/Laser7/BP_SV_*
echo "laser7: building the curve, the beam's effects and the weapon (log: $OUT/laserfx.log)"
"$CMD" "$PROJ/Live.uproject" -run=LaserFx -spec="$OUT/laser7.spec.json" -log="$OUT/laserfx.log" -unattended -nop4 -nosplash -stdout > "$OUT/laserfx_stdout.log" 2>&1 \
    || { echo "laser7: LaserFx failed ($OUT/laserfx.log)"; cat "$OUT/laserfx.log" | grep -i error | head; exit 1; }
grep -q "^done (0 errors)" "$OUT/laserfx.log" || { echo "laser7: LaserFx had errors ($OUT/laserfx.log)"; exit 1; }
echo "laser7: cooking (log: $OUT/cook.log)"
rm -rf "$PROJ/Saved/Cooked"
# the beam's four materials are new masters: their shaders (DX12 SM6, AC8's only platform) go INTO their packages
# (bShareMaterialShaderCode off for this cook), as AC8's shader library has none of them (the template project shares
# them into a ShaderArchive that never ships, which left the 0.74.16-era cook's materials without code)
PKG='[/Script/UnrealEd.ProjectPackagingSettings]'
"$CMD" "$PROJ/Live.uproject" -run=cook -targetplatform=Windows -unattended -nop4 -nosplash -stdout \
    "-ini:Game:$PKG:bShareMaterialShaderCode=False" "-ini:Game:$PKG:bSharedMaterialNativeLibraries=False" > "$OUT/cook.log" 2>&1
COOKED="$PROJ/Saved/Cooked/Windows/Live/Content/Mods/SurvivalMode/Laser7"
[ -f "$COOKED/BP_SV_LaserInterceptor.uasset" ] || { echo "laser7: nothing cooked at $COOKED"; exit 1; }
# each material must carry its own shader code now (tens of KB of it, ~20 KB without)
for m in M_SV_TLS_01 M_SV_TLS_01_wire M_SV_TLS_02 M_SV_TLS_03; do
    sz=$(wc -c < "$COOKED/$m.uexp")
    [ "$sz" -gt 60000 ] || { echo "laser7: $m.uexp is $sz bytes: its shaders aren't inline (see $OUT/cook.log)"; exit 1; }
done
ls "$PROJ/Saved/Cooked/Windows/Live/Content/" | grep -i "ShaderArchive-Live" && echo "laser7: (a shared shader archive was still written: not shipped)" || true
rm -rf "$OUT/stage" "$OUT/out" && mkdir -p "$OUT/stage/Live/Content/Mods/SurvivalMode" "$OUT/out"
cp -r "$COOKED" "$OUT/stage/Live/Content/Mods/SurvivalMode/"
find "$OUT/stage" -type f | sed "s#$OUT/stage/#  #"
tools/bin/retoc.exe to-zen --version UE5_4 "$OUT/stage" "$OUT/out/SurvivalMode_Laser7_P.utoc"
python -I tools/x02s/pad.py "$OUT/out/SurvivalMode_Laser7_P.utoc"
tools/bin/retoc.exe list "$OUT/out/SurvivalMode_Laser7_P.utoc" | head -20
echo "laser7: built $OUT/out/SurvivalMode_Laser7_P (staged with ZFA=1 by tools/build_all.sh)"
