#!/bin/sh
# flight_test.sh : runs tools/checks/flight_test.c (runtime 0.28.5's co-op flag bits and afterburner write, and DOWN's
# loiter autopilot, runtime/down_ctl.c, flying model planes) outside the game. One windowless process of a second or two
# (as coop_test.sh: a console program would pop up over the game while the user plays); its output goes to
# build/checks/flight_test.txt and is shown here. Needs clang (tools/llvm) and a Windows SDK / MSVC libs on Windows;
# elsewhere (Linux, a cloud session) clang or cc, with tools/checks/win32_posix.h standing in for windows.h, and then the
# same test again built with gcc -fsanitize=address,undefined,float-cast-overflow (a second or two; skipped, and said
# so, when gcc can't build with them: SAN_CC= another compiler, SANITIZE=0 to leave it out). The test's model objects
# are never freed: those leaks only are suppressed. A run fails without its "flight test: passed" line.
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) WIN=1 ;; *) WIN=0 ;; esac
if [ "$WIN" = 1 ]; then
"$CLANG" -O1 -w -Wno-incompatible-pointer-types -Wno-incompatible-function-pointer-types -o "$OUT/flight_test.exe" flight_test.c \
    -lws2_32 -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup
else
    mkdir -p "$OUT/posix_inc"
    printf '#include "%s/win32_posix.h"\n' "$(pwd)" > "$OUT/posix_inc/windows.h"
    command -v "$CLANG" > /dev/null 2>&1 || CLANG=cc
    "$CLANG" -O1 -w -I "$OUT/posix_inc" -o "$OUT/flight_test.exe" flight_test.c -lm
    SAN=0
    if [ "${SANITIZE:-1}" != 0 ]; then
        SAN_CC=${SAN_CC:-gcc}
        if "$SAN_CC" -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined,float-cast-overflow -w -I "$OUT/posix_inc" \
                -o "$OUT/flight_test_san.exe" flight_test.c -lm > "$OUT/flight_test_san_build.txt" 2>&1; then SAN=1
        else echo "flight test (sanitized): not run: $SAN_CC can't build with ASan / UBSan here ($(head -1 "$OUT/flight_test_san_build.txt"))"; fi
    fi
fi
cd "$OUT"
rc=0
./flight_test.exe > flight_test.txt 2>&1 || rc=$?
grep -vE "^  \[log\]" flight_test.txt || true
# (a run that printed nothing must not pass: glibc's streams once lost every printf after a wprintf)
if [ "$rc" = 0 ] && ! grep -q "^flight test: passed" flight_test.txt; then echo "flight test: no 'flight test: passed' line (a mute run?)"; rc=99; fi
if [ "$WIN" = 0 ] && [ "${SAN:-0}" = 1 ]; then
    printf 'leak:FlagsTest\n' > flight_lsan.supp
    src=0
    UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1" LSAN_OPTIONS="suppressions=$(pwd)/flight_lsan.supp:print_suppressions=0" \
        ASAN_OPTIONS="abort_on_error=0:detect_stack_use_after_return=1" ./flight_test_san.exe > flight_test_san.txt 2>&1 || src=$?
    if [ "$src" = 0 ] && grep -q "^flight test: passed" flight_test_san.txt && ! grep -q "ERROR: \|runtime error:" flight_test_san.txt; then
        echo "flight test (sanitized): passed, no ASan / UBSan report"
    else
        echo "flight test (sanitized): FAILED (exit code $src; see build/checks/flight_test_san.txt):"
        grep -vE "^  \[log\]" flight_test_san.txt | grep -A30 "ERROR: \|runtime error:" | head -40 || true
        [ "$rc" = 0 ] && rc=98
    fi
fi
[ "$rc" = 0 ] && exit 0
echo "flight test: exit code $rc (see build/checks/flight_test.txt)"
exit 1
