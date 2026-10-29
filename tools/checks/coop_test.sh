#!/bin/sh
# coop_test.sh : runs tools/checks/coop_test.c (runtime/coop.c outside the game: a host and its joiners as processes
# over localhost UDP, 20 % of the packets dropped): 4 players, then 12 (the host's 20 Hz batches past 6 players and
# two-digit slots, protocol 3). Needs clang (tools/llvm) and a Windows SDK / MSVC libs.
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
# (a windowless program: up to 13 of them run at once for ~40 s, and as console programs they popped up over the
# game and took its focus while the user played, 2026-10-29: "coop.exe continually opens ... and alt tabs the game";
# their output still goes to the redirected files)
"$CLANG" -O1 -w -Wno-incompatible-pointer-types -Wno-incompatible-function-pointer-types -o "$OUT/coop_test.exe" coop_test.c -lws2_32 -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup
cd "$OUT"
./coop_test.exe join 1 > /dev/null 2>&1 || true      # (a fresh exe's first start can be slow: warm it up)
result=0
for joiners in 3 11; do
    rm -f ./*.rc ./join*.txt
    export COOP_TEST_JOINERS=$joiners
    (./coop_test.exe host 16 > host.txt 2>&1; echo $? > host.rc) &
    sleep 0.3
    j=1
    while [ $j -le $joiners ]; do
        (./coop_test.exe join > join$j.txt 2>&1; echo $? > join$j.rc) &
        j=$((j + 1))
    done
    sleep 19
    grep -vh "\[log\]" host.txt join*.txt | grep -E "player|reliable|enemy|OUT OF|full|samerole|guard" | grep -vE "mean 0\.|of 40 messages" || true
    fail=0
    [ -f host.rc ] && [ "$(cat host.rc)" = 0 ] || fail=1
    j=1
    while [ $j -le $joiners ]; do [ -f join$j.rc ] && [ "$(cat join$j.rc)" = 0 ] || fail=1; j=$((j + 1)); done
    if [ "$fail" = 0 ]; then echo "coop test ($((joiners + 1)) players): passed"
    else echo "coop test ($((joiners + 1)) players): FAILED (see build/checks/*.txt)"; result=1; fi
done
exit $result
