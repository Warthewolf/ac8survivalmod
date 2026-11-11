#!/bin/sh
# unittab_test.sh : runs tools/checks/unittab_test.c (runtime/unittab.h, the spawner's id -> unit table behind
# SV_UnitAlive, Saint Alessia's 50-round run's lag-1) outside the game, against the old walk. On Windows one windowless
# process (as uobj_test.sh), elsewhere a plain one (no Windows headers); its output goes to build/checks/unittab_test.txt
# and is shown here. Needs clang (tools/llvm, or on PATH).
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) "$CLANG" -O1 -Wall -Wextra -o "$OUT/unittab_test.exe" unittab_test.c -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup ;;
    *) "$CLANG" -O1 -Wall -Wextra -o "$OUT/unittab_test.exe" unittab_test.c ;;
esac
cd "$OUT"
rc=0
./unittab_test.exe > unittab_test.txt 2>&1 || rc=$?
cat unittab_test.txt
[ "$rc" = 0 ] && exit 0
echo "unittab test: exit code $rc (see build/checks/unittab_test.txt)"
exit 1
