#!/bin/sh
# build.sh : Survival's own Wwise sounds -> build/wwise/out/SurvivalMode_Wwise_P.utoc / .ucas (staged by build_all.sh)
#   AC8 runs Wwise 2024.1.11 (SDK build paths in AceCombat8.exe; its Wwise.uplugin "2024.1.11.9010.4075"; banks v154).
#   The sound project AC8_WWISE_PROJECT (.env): AC8Sound.uproject, a blank UE 5.4 C++ project with the Wwise 2024.1.11
#   plugin (the Wwise Launcher's "integrate", its "UE 5.5" choice compiles on 5.4 as is), and its Wwise project
#   AC8WwiseProject_WwiseProject (no Init.bnk of ours ever ships: AC8's own Init is loaded).
#   1. waapi-server     WwiseConsole (WWISE, .env) with WAAPI on local HTTP; waapi_build.py makes the objects from
#                       SPEC (a json: bus "sfx" = AC8's own sfx bus by name, sounds, attenuations, events) and the bank
#                       SV_Sounds (every event in it), then generates it (Windows, JSON metadata)
#   2. reconcile        UnrealEditor-Cmd -run=WwiseReconcileCommandlet -modes=create,update: the AkAudioEvent assets under
#                       /Game/Mods/SurvivalMode/Wwise (AkSettings DefaultAssetCreationPath; RootOutputPath ../<wproj dir>/
#                       GeneratedSoundBanks, relative to Content)
#   3. cook             Windows, VERSIONED (hard rule 42); each event's bank comes inside its asset (bulk data)
#   4. retoc to-zen     only /Game/Mods/SurvivalMode/Wwise/Events -> the container, 5. pad.py (hard rule 8)
# SPEC=<spec.json> sh tools/wwise/build.sh   (the spec names the WAV sources; they stay outside the repo)
set -e
cd "$(dirname "$0")/../.."
. tools/env.sh
sv_need AC8_WWISE_PROJECT "Survival's sound project (AC8Sound.uproject with the Wwise 2024.1.11 plugin)"
sv_need WWISE "Wwise 2024.1.11's install folder"
sv_need UE "Unreal Engine 5.4"
[ -n "$SPEC" ] && [ -f "$SPEC" ] || { echo "wwise: SPEC=<spec.json> (see tools/wwise/waapi_build.py)"; exit 1; }
PROJ="$AC8_WWISE_PROJECT"
WPROJ=$(ls "$PROJ"/*_WwiseProject/*.wproj | head -1)
CMD="$UE/Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
OUT=build/wwise
PORT=${WAAPI_PORT:-8095}
mkdir -p "$OUT"
echo "wwise: WAAPI on 127.0.0.1:$PORT ($WPROJ)"
"$WWISE/Authoring/x64/Release/bin/WwiseConsole.exe" waapi-server "$WPROJ" --allow-migration --http-port "$PORT" \
    --wamp-port $((PORT + 1)) --allowed-addr 127.0.0.1 --no-source-control > "$OUT/waapi_server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
python -I tools/wwise/waapi_build.py "$PORT" "$SPEC" --wait --bank SV_Sounds
kill $SRV 2>/dev/null || true
echo "wwise: reconcile (log: $OUT/reconcile.log)"
"$CMD" "$PROJ/AC8Sound.uproject" -run=WwiseReconcileCommandlet -modes=create,update -unattended -nop4 -nosplash \
    -stdout > "$OUT/reconcile.log" 2>&1
echo "wwise: cooking (log: $OUT/cook.log)"
rm -rf "$PROJ/Saved/Cooked"
"$CMD" "$PROJ/AC8Sound.uproject" -run=cook -targetplatform=Windows -unattended -nop4 -nosplash -stdout > "$OUT/cook.log" 2>&1
COOKED="$PROJ/Saved/Cooked/Windows/AC8Sound/Content/Mods/SurvivalMode/Wwise/Events"
[ -d "$COOKED" ] || { echo "wwise: nothing cooked at $COOKED"; exit 1; }
rm -rf "$OUT/stage" "$OUT/out" && mkdir -p "$OUT/stage/Live/Content/Mods/SurvivalMode/Wwise" "$OUT/out"
cp -r "$COOKED" "$OUT/stage/Live/Content/Mods/SurvivalMode/Wwise/"
MSYS_NO_PATHCONV=1 tools/bin/retoc.exe to-zen --version UE5_4 "$OUT/stage" "$OUT/out/SurvivalMode_Wwise_P.utoc"
python -I tools/x02s/pad.py "$OUT/out/SurvivalMode_Wwise_P.utoc"
MSYS_NO_PATHCONV=1 tools/bin/retoc.exe list --path "$OUT/out/SurvivalMode_Wwise_P.utoc" | grep uasset
echo "wwise: built $OUT/out/SurvivalMode_Wwise_P"
