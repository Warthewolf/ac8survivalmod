#!/bin/sh
# build.sh : builds the Survival Mode native runtime (UE4SS C++ mod) with LLVM only.
# Output: build/runtime/main.dll  (staged by tools/build_all.sh into AC8SurvivalMode/dlls/)
# LLVM: tools/llvm/LLVM/bin (unpacked from the LLVM Windows installer), or LLVM on PATH.
set -e
export MSYS_NO_PATHCONV=1   # Git Bash would turn /dll etc. into paths
cd "$(dirname "$0")"
OUT=../build/runtime
mkdir -p "$OUT"
BIN=../tools/llvm/LLVM/bin
[ -x "$BIN/clang.exe" ] && PATH="$BIN:$PATH"

for lib in kernel32 ue4ss ucrtheap; do
    llvm-dlltool -m i386:x86-64 -d $lib.def -l "$OUT/$lib.lib"
done

# The leaderboard's address and submit key (leaderboard/README.md), from leaderboard/submit.local (never in git):
#   URL=https://<worker>.workers.dev/submit
#   KEY=<the Worker's SUBMIT_KEY>
# Without the file the runtime is built without them (SV_Post answers "no server").
CFG="$OUT/submit_cfg.h"
rm -f "$CFG"
if [ -f ../leaderboard/submit.local ]; then
    URL=$(sed -n 's/^URL=//p' ../leaderboard/submit.local | tr -d '\r')
    KEY=$(sed -n 's/^KEY=//p' ../leaderboard/submit.local | tr -d '\r')
    HOST=$(echo "$URL" | sed -e 's#^https://##' -e 's#/.*##')
    PATHPART=/$(echo "$URL" | sed -e 's#^https://[^/]*/\{0,1\}##')
    printf '#define SV_SUBMIT_HOST L"%s"\n#define SV_SUBMIT_PATH L"%s"\n#define SV_SUBMIT_KEY "%s"\n' "$HOST" "$PATHPART" "$KEY" > "$CFG"
    echo "leaderboard: runs go to $HOST$PATHPART"
else
    echo "leaderboard: no leaderboard/submit.local; the runtime can't submit runs"
fi

clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-builtin -nostdlibinc \
      -fno-stack-protector -funwind-tables -Wall -Wextra -Werror \
      -I"$OUT" -c survival_rt.c -o "$OUT/survival_rt.obj"

lld-link /dll /nodefaultlib /entry:DllMain /subsystem:windows \
         /out:"$OUT/main.dll" /implib:"$OUT/main_exports.lib" \
         "$OUT/survival_rt.obj" "$OUT/kernel32.lib" "$OUT/ue4ss.lib" "$OUT/ucrtheap.lib"
echo "built $OUT/main.dll"
