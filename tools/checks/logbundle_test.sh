#!/bin/sh
# logbundle_test.sh : the log bundle's zip writer and pruning (runtime/logzip.h, runtime 0.32.32) built into a small
# windowless exe (tools/checks/logbundle_test.c) and checked with Python's zipfile on a made-up tree
# (tools/checks/logbundle_test.py): testzip, names (a non-ASCII one with the UTF-8 flag), contents byte for byte, an
# empty file, a 3 MB file, a missing file skipped, an in-memory entry, and prune keeping exactly the newest N.
# Output in build/checks/logbundle. Needs clang (tools/llvm) and a Windows SDK / MSVC libs, as build_hash_test.sh.
set -e
cd "$(dirname "$0")"
OUT=../../build/checks/logbundle
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
"$CLANG" -O1 -w -o "$OUT/logbundle_test.exe" logbundle_test.c -Wl,/subsystem:windows -Wl,/entry:wmainCRTStartup
python -X utf8 -I logbundle_test.py "$OUT/logbundle_test.exe" "$OUT"
