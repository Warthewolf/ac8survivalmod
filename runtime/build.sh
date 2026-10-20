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

clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-builtin -nostdlibinc \
      -fno-stack-protector -funwind-tables -Wall -Wextra -Werror \
      -c survival_rt.c -o "$OUT/survival_rt.obj"

lld-link /dll /nodefaultlib /entry:DllMain /subsystem:windows \
         /out:"$OUT/main.dll" /implib:"$OUT/main_exports.lib" \
         "$OUT/survival_rt.obj" "$OUT/kernel32.lib" "$OUT/ue4ss.lib" "$OUT/ucrtheap.lib"
echo "built $OUT/main.dll"
