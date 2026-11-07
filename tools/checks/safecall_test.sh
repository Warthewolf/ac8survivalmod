#!/bin/sh
# safecall_test.sh : runs tools/checks/safecall_test.c (runtime/safecall.h, the target search guard's fault catcher)
# outside the game. One windowless process (as flight_test.sh: no console popping up over the game);
# its output goes to build/checks/safecall_test.txt and is shown here. Needs clang (tools/llvm) and the MSVC / SDK libs.
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
"$CLANG" -O1 -Wall -Wextra -o "$OUT/safecall_test.exe" safecall_test.c -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup
cd "$OUT"
rc=0
./safecall_test.exe > safecall_test.txt 2>&1 || rc=$?
cat safecall_test.txt
[ "$rc" = 0 ] && exit 0
echo "uobj test: exit code $rc (see build/checks/safecall_test.txt)"
exit 1
