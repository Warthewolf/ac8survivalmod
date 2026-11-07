#!/bin/sh
# pathguard_test.sh : runs tools/checks/pathguard_test.c (runtime/pathguard.h, the AI path tracking guard of runtime
# 0.32.22) outside the game. One windowless process (as uobj_test.sh: no console popping up over the game); its output
# goes to build/checks/pathguard_test.txt and is shown here. Needs clang (tools/llvm) and the MSVC / SDK libs.
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
"$CLANG" -O1 -Wall -Wextra -o "$OUT/pathguard_test.exe" pathguard_test.c -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup
cd "$OUT"
rc=0
./pathguard_test.exe > pathguard_test.txt 2>&1 || rc=$?
cat pathguard_test.txt
[ "$rc" = 0 ] && exit 0
echo "pathguard test: exit code $rc (see build/checks/pathguard_test.txt)"
exit 1
