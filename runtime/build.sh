#!/bin/sh
# build.sh : builds the Survival Mode native runtime (UE4SS C++ mod) with LLVM only.
# Output: build/runtime/main.dll  (staged by tools/build_all.sh into AC8SurvivalMode/dlls/)
# OFFLINE=1 build.sh: build/runtime/offline/main.dll, compiled with SV_OFFLINE (no leaderboard code at all: no WinHTTP,
# bcrypt, address, key or Steam name). The Offline zip that shipped it was retired on 2026-11-11: nothing ships it now.
# LLVM: tools/llvm/LLVM/bin (unpacked from the LLVM Windows installer), or LLVM on PATH.
set -e
export MSYS_NO_PATHCONV=1   # Git Bash would turn /dll etc. into paths
cd "$(dirname "$0")"
OUT=../build/runtime
DEFS=
[ "$OFFLINE" = 1 ] && { OUT=../build/runtime/offline; DEFS=-DSV_OFFLINE; }
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
# ((2026-11-07) every 0.74.x runtime was built in a git worktree with no leaderboard/submit.local of its own, so not one
#  of them could send a run: players' ranked runs sat in pending_runs.txt) the file: .env's SV_LB_LOCAL, else this
#  checkout's leaderboard/submit.local, else the main working tree's (the first `git worktree list` entry). The package
#  scripts refuse an Online build without it (build/runtime/submit_cfg.h).
LBF=
if [ -n "$SV_LB_LOCAL" ] && [ -f "$SV_LB_LOCAL" ]; then LBF=$SV_LB_LOCAL
elif [ -f ../leaderboard/submit.local ]; then LBF=../leaderboard/submit.local
else
    MAIN=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
    [ -n "$MAIN" ] && [ -f "$MAIN/leaderboard/submit.local" ] && LBF="$MAIN/leaderboard/submit.local"
fi
if [ "$OFFLINE" = 1 ]; then
    echo "leaderboard: Offline edition, no leaderboard code"
elif [ -n "$LBF" ]; then
    URL=$(sed -n 's/^URL=//p' "$LBF" | tr -d '\r')
    KEY=$(sed -n 's/^KEY=//p' "$LBF" | tr -d '\r')
    HOST=$(echo "$URL" | sed -e 's#^https://##' -e 's#/.*##')
    PATHPART=/$(echo "$URL" | sed -e 's#^https://[^/]*/\{0,1\}##')
    printf '#define SV_SUBMIT_HOST L"%s"\n#define SV_SUBMIT_PATH L"%s"\n#define SV_SUBMIT_KEY "%s"\n' "$HOST" "$PATHPART" "$KEY" > "$CFG"
    echo "leaderboard: runs go to $HOST$PATHPART"
else
    echo "leaderboard: no leaderboard/submit.local (here, the main tree's or .env's SV_LB_LOCAL); the runtime can't submit runs"
fi

clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-builtin -nostdlibinc \
      -fno-stack-protector -funwind-tables -Wall -Wextra -Werror \
      $DEFS -I"$OUT" -c survival_rt.c -o "$OUT/survival_rt.obj"

# (runtime 0.32.22, plan F1c) a linker map kept per runtime build: main_<RT_VERSION>.map next to main.dll (the latest of
# that version) and main_<RT_VERSION>_<link timestamp>.map (kept: a crash report's module list gives main.dll's
# timestamp), so the runtime's addresses in a crash report (main.dll+0x...) can be named:
# python -X utf8 -I tools/checks/mdmp.py <dump> --map build/runtime/main_<v>_<ts>.map
VER=$(sed -n 's/^#define RT_VERSION_A *"\([^"]*\)".*/\1/p' survival_rt.c)
MAP="$OUT/main_${VER:-unknown}.map"
lld-link /dll /nodefaultlib /entry:DllMain /subsystem:windows \
         /out:"$OUT/main.dll" /implib:"$OUT/main_exports.lib" /map:"$MAP" \
         "$OUT/survival_rt.obj" "$OUT/kernel32.lib" "$OUT/ue4ss.lib" "$OUT/ucrtheap.lib"
TS=$(sed -n 's/^ *Timestamp is \([0-9a-fA-F]*\).*/\1/p' "$MAP" | head -1)
[ -n "$TS" ] && cp "$MAP" "$OUT/main_${VER:-unknown}_$TS.map"
echo "built $OUT/main.dll (map: $MAP, kept as main_${VER:-unknown}_$TS.map)"
