#!/bin/sh
# build.sh : Survival's own storm effects (tools/stormfx/README.md) -> build/stormfx/out/SurvivalMode_StormFx_P.utoc / .ucas
#   1. ue_flash.py    in the AC8 template project ($AC8_LIVE_PROJECT, UE 5.4): NS_SV_CloudFlash, through Epic's
#                     CascadeToNiagaraConverter scripting API (enabled for this run only: -EnablePlugins)
#   2. cook           Windows, VERSIONED (hard rule 42)
#   3. retoc to-zen   only /Game/Mods/SurvivalMode/StormFx -> the container, 4. pad.py (hard rule 8)
# Dev installs only (the fleet's storm, the Thunder Anomaly's): tools/build_all.sh stages it with TANI=1, no release ships it.
set -e
cd "$(dirname "$0")/../.."
. tools/env.sh
sv_need UE "Unreal Engine 5.4's folder"
sv_need AC8_LIVE_PROJECT "the AC8 template project (Live.uproject's folder)"
PROJ=$AC8_LIVE_PROJECT
MAIN=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [ -n "$MAIN" ]; then MAIN=$(dirname "$MAIN"); else MAIN=$(pwd); fi
export SV_ROOT="$MAIN"                              # (ue_flash.py reads it)
CMD="$UE/Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
OUT="$MAIN/build/stormfx"
export MSYS_NO_PATHCONV=1
mkdir -p "$OUT"
SCRIPT="$(pwd -W 2>/dev/null || pwd)/tools/stormfx/ue_flash.py"
echo "stormfx: building NS_SV_CloudFlash (log: $OUT/ue_flash.log)"
rm -f "$OUT/ue_flash.log"
"$CMD" "$PROJ/Live.uproject" -run=pythonscript -script="$SCRIPT" -EnablePlugins=CascadeToNiagaraConverter \
    -unattended -nop4 -nosplash -stdout > "$OUT/ue_flash_stdout.log" 2>&1 || true
[ "$(tail -1 "$OUT/ue_flash.log" 2>/dev/null)" = "done" ] || { echo "stormfx: the flash didn't build ($OUT/ue_flash.log, $OUT/ue_flash_stdout.log)"; exit 1; }
echo "stormfx: cooking (log: $OUT/cook.log)"
rm -rf "$PROJ/Saved/Cooked"
"$CMD" "$PROJ/Live.uproject" -run=cook -targetplatform=Windows -EnablePlugins=CascadeToNiagaraConverter \
    -unattended -nop4 -nosplash -stdout > "$OUT/cook.log" 2>&1
COOKED="$PROJ/Saved/Cooked/Windows/Live/Content/Mods/SurvivalMode/StormFx"
[ -f "$COOKED/NS_SV_CloudFlash.uasset" ] || { echo "stormfx: nothing cooked at $COOKED"; exit 1; }
rm -rf "$OUT/stage" "$OUT/out" && mkdir -p "$OUT/stage/Live/Content/Mods/SurvivalMode" "$OUT/out"
cp -r "$COOKED" "$OUT/stage/Live/Content/Mods/SurvivalMode/"
find "$OUT/stage" -type f | sed "s#$OUT/stage/#  #"
tools/bin/retoc.exe to-zen --version UE5_4 "$OUT/stage" "$OUT/out/SurvivalMode_StormFx_P.utoc"
python -I tools/x02s/pad.py "$OUT/out/SurvivalMode_StormFx_P.utoc"
tools/bin/retoc.exe list "$OUT/out/SurvivalMode_StormFx_P.utoc" | head -20
echo "stormfx: built $OUT/out/SurvivalMode_StormFx_P (staged with TANI=1 by tools/build_all.sh; dev installs only)"
