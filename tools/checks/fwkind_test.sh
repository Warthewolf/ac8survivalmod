#!/bin/sh
# fwkind_test.sh : runs tools/checks/fwkind_test.c (runtime/fwkind.h, what runtime 0.32.24 knows of the other players'
# real planes' weapons for their weapon stand-ins) outside the game. On Windows one windowless process (as uobj_test.sh:
# no console popping up over the game), elsewhere a plain one (it needs no Windows headers); its output goes to
# build/checks/fwkind_test.txt and is shown here. Needs clang (tools/llvm, or on PATH).
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) "$CLANG" -O1 -Wall -Wextra -o "$OUT/fwkind_test.exe" fwkind_test.c -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup ;;
    *) "$CLANG" -O1 -Wall -Wextra -o "$OUT/fwkind_test.exe" fwkind_test.c ;;
esac
cd "$OUT"
rc=0
./fwkind_test.exe > fwkind_test.txt 2>&1 || rc=$?
cat fwkind_test.txt
[ "$rc" = 0 ] && exit 0
echo "fwkind test: exit code $rc (see build/checks/fwkind_test.txt)"
exit 1
