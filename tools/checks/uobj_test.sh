#!/bin/sh
# uobj_test.sh : runs tools/checks/uobj_test.c (runtime/uobj.h's UObjLive, the guards' liveness check, on a made-up
# GUObjectArray) outside the game. One windowless process (as flight_test.sh: no console popping up over the game);
# its output goes to build/checks/uobj_test.txt and is shown here. Needs clang (tools/llvm) and the MSVC / SDK libs.
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
"$CLANG" -O1 -Wall -Wextra -o "$OUT/uobj_test.exe" uobj_test.c -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup
cd "$OUT"
rc=0
./uobj_test.exe > uobj_test.txt 2>&1 || rc=$?
cat uobj_test.txt
[ "$rc" = 0 ] && exit 0
echo "uobj test: exit code $rc (see build/checks/uobj_test.txt)"
exit 1
