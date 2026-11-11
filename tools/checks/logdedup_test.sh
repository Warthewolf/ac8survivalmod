#!/bin/sh
# logdedup_test.sh : runs tools/checks/logdedup_test.c (runtime/logdedup.h, the log bundle's UE4SS.log copy filter:
# a run of the same line written once and counted, the copy stopped at 64 MB; Saint Alessia's 50-round run's lag-8) outside
# the game. On Windows one windowless process (as uobj_test.sh), elsewhere a plain one (no Windows headers); its output goes
# to build/checks/logdedup_test.txt and is shown here. Needs clang (tools/llvm, or on PATH).
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) "$CLANG" -O1 -Wall -Wextra -o "$OUT/logdedup_test.exe" logdedup_test.c -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup ;;
    *) "$CLANG" -O1 -Wall -Wextra -o "$OUT/logdedup_test.exe" logdedup_test.c ;;
esac
cd "$OUT"
rc=0
./logdedup_test.exe > logdedup_test.txt 2>&1 || rc=$?
cat logdedup_test.txt
[ "$rc" = 0 ] && exit 0
echo "logdedup test: exit code $rc (see build/checks/logdedup_test.txt)"
exit 1
