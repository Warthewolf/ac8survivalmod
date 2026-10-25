#!/bin/sh
# coop_test.sh : runs tools/checks/coop_test.c (runtime/coop.c outside the game: two processes over localhost UDP, 20 %
# loss): a host and a joiner, then a joiner restart. Needs clang (tools/llvm) and a Windows SDK / MSVC libraries.
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
"$CLANG" -O1 -w -Wno-incompatible-pointer-types -Wno-incompatible-function-pointer-types -o "$OUT/coop_test.exe" coop_test.c -lws2_32
cd "$OUT"
./coop_test.exe join 1 > /dev/null 2>&1 || true      # (a fresh exe's first start can be slow: warm it up)
(./coop_test.exe host > host.txt 2>&1 &)
sleep 0.3
./coop_test.exe join > join.txt 2>&1 && ok=1 || ok=0
sleep 1
grep -vh "\[log\]" join.txt
[ "$ok" = 1 ] && echo "coop test: passed" || { echo "coop test: FAILED (see build/checks/host.txt, join.txt)"; exit 1; }
