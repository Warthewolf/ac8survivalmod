#!/bin/sh
# build_hash_test.sh : the leaderboard's build hash and the run's HMAC (runtime/build_hash.c, runtime 0.28.6) built into a
# small windowless exe (tools/checks/build_hash_test.c; a console program would pop up over the game while the user
# plays), checked against tools/build_hash.py and Python's hmac on a made-up mod tree (tools/checks/build_hash_test.py).
# Output in build/checks/build_hash. Needs clang (tools/llvm) and a Windows SDK / MSVC libs, as flight_test.sh.
set -e
cd "$(dirname "$0")"
OUT=../../build/checks/build_hash
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
"$CLANG" -O1 -w -o "$OUT/build_hash_test.exe" build_hash_test.c -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup
python -X utf8 -I build_hash_test.py "$OUT/build_hash_test.exe" "$OUT"
