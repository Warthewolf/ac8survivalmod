#!/bin/sh
# flight_test.sh : runs tools/checks/flight_test.c (runtime 0.28.5's co-op flag bits and afterburner write, and DOWN's
# loiter autopilot, runtime/down_ctl.c, flying model planes) outside the game. One windowless process of a second or two
# (as coop_test.sh: a console program would pop up over the game while the user plays); its output goes to
# build/checks/flight_test.txt and is shown here. Needs clang (tools/llvm) and a Windows SDK / MSVC libs.
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
"$CLANG" -O1 -w -Wno-incompatible-pointer-types -Wno-incompatible-function-pointer-types -o "$OUT/flight_test.exe" flight_test.c \
    -lws2_32 -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup
cd "$OUT"
rc=0
./flight_test.exe > flight_test.txt 2>&1 || rc=$?
grep -vE "^  \[log\]" flight_test.txt || true
[ "$rc" = 0 ] && exit 0
echo "flight test: exit code $rc (see build/checks/flight_test.txt)"
exit 1
