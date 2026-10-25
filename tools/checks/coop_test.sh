#!/bin/sh
# coop_test.sh : runs tools/checks/coop_test.c (runtime/coop.c outside the game: a host and three joiners as four
# processes over localhost UDP, 20 % of the packets dropped). Needs clang (tools/llvm) and a Windows SDK / MSVC libs.
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
"$CLANG" -O1 -w -Wno-incompatible-pointer-types -Wno-incompatible-function-pointer-types -o "$OUT/coop_test.exe" coop_test.c -lws2_32
cd "$OUT"
rm -f ./*.rc
./coop_test.exe join 1 > /dev/null 2>&1 || true      # (a fresh exe's first start can be slow: warm it up)
(./coop_test.exe host 16 > host.txt 2>&1; echo $? > host.rc) &
sleep 0.3
(./coop_test.exe join > join1.txt 2>&1; echo $? > join1.rc) &
(./coop_test.exe join > join2.txt 2>&1; echo $? > join2.rc) &
(./coop_test.exe join > join3.txt 2>&1; echo $? > join3.rc) &
sleep 19
grep -vh "\[log\]" host.txt join1.txt join2.txt join3.txt | grep -E "player|reliable|enemy|OUT OF|full|samerole" || true
fail=0
for f in host join1 join2 join3; do [ -f $f.rc ] && [ "$(cat $f.rc)" = 0 ] || fail=1; done
if [ "$fail" = 0 ]; then echo "coop test (4 players): passed"; else echo "coop test (4 players): FAILED (see build/checks/*.txt)"; exit 1; fi
