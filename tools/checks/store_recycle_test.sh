#!/bin/sh
# store_recycle_test.sh : runs tools/checks/store_recycle_test.c (runtime 0.32.36: the recycles' unit destroys wait out
# the STORE's freeze) on the runtime's own code, cut out by store_recycle_cut.py. One windowless process (as
# pathguard_test.sh); its output goes to build/checks/store_recycle_test.txt. Needs clang (tools/llvm) and Python.
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
PY=python
command -v "$PY" >/dev/null 2>&1 || PY=python3
"$PY" -I store_recycle_cut.py "$OUT/store_recycle_cut.c"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
"$CLANG" -O1 -Wall -Wno-unused-function -o "$OUT/store_recycle_test.exe" store_recycle_test.c -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup
cd "$OUT"
rc=0
./store_recycle_test.exe > store_recycle_test.txt 2>&1 || rc=$?
cat store_recycle_test.txt
[ "$rc" = 0 ] && exit 0
echo "store recycle test: exit code $rc (see build/checks/store_recycle_test.txt)"
exit 1
