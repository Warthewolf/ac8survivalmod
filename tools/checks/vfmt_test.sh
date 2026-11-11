#!/bin/sh
# vfmt_test.sh : runs tools/checks/vfmt_test.c (runtime/vfmt.h, the runtime's Log / Crumb formatter: a line past
# the buffer is cut and the call returns; 0.32.22 looped for ever there) outside the game. One windowless process
# (no console popping up over the game).
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
# Windows: a windowless exe; elsewhere (Linux, a cloud session) a plain one
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) LINK="-Wl,/subsystem:windows -Wl,/entry:mainCRTStartup" ;;
    *) LINK="-lpthread" ;;
esac
"$CLANG" -O1 -Wall -Wextra -o "$OUT/vfmt_test.exe" vfmt_test.c $LINK
cd "$OUT"
rc=0
./vfmt_test.exe > vfmt_test.txt 2>&1 || rc=$?
cat vfmt_test.txt
[ "$rc" = 0 ] && exit 0
echo "vfmt test: exit code $rc (see build/checks/vfmt_test.txt)"
exit 1
