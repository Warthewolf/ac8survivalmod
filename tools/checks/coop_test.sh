#!/bin/sh
# coop_test.sh : runs tools/checks/coop_test.c (runtime/coop.c outside the game: a host and its joiners as processes
# over localhost UDP, 20 % of the packets dropped): 4 players, then 12 (the host's 20 Hz batches past 6 players and
# two-digit slots, protocol 3). Needs clang (tools/llvm) and a Windows SDK / MSVC libs on Windows; elsewhere (Linux, a
# cloud session) clang or cc, with tools/checks/win32_posix.h standing in for windows.h (BSD sockets behind the Winsock
# names, the monotonic clock behind QueryPerformanceCounter: its header says what a Linux run can't show).
#   SANITIZE=1 sh tools/checks/coop_test.sh   (not Windows) then the same two rooms again built with gcc
#       -fsanitize=address,undefined,float-cast-overflow (SAN_CC= another compiler with ASan's runtime). Opt-in: it
#       doubles the ~40 s. It first shows the one known finding unsuppressed (memcpy-param-overlap in CoPushSnap,
#       coop.c:775: told KNOWN, not a failure), then runs the rooms with only that report suppressed (an ASan
#       suppression on CoPushSnap's memcpy calls) and fails on any other sanitizer report.
# A run fails when a process's exit code isn't 0 or its summary line is missing (a mute run is a failure: glibc's
# streams once lost every printf after a wprintf, and the test "passed" with nothing said).
set -e
cd "$(dirname "$0")"
OUT=../../build/checks
mkdir -p "$OUT"
CLANG=../llvm/LLVM/bin/clang.exe
[ -x "$CLANG" ] || CLANG=clang
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) WIN=1 ;; *) WIN=0 ;; esac
if [ "$WIN" = 1 ]; then
# (a windowless program: up to 13 of them run at once for ~40 s, and as console programs they popped up over the
# game and took its focus while the user played, 2026-10-29: "coop.exe continually opens ... and alt tabs the game";
# their output still goes to the redirected files)
"$CLANG" -O1 -w -Wno-incompatible-pointer-types -Wno-incompatible-function-pointer-types -o "$OUT/coop_test.exe" coop_test.c -lws2_32 -Wl,/subsystem:windows -Wl,/entry:mainCRTStartup
else
    # (win32_posix.h through a generated windows.h, so coop_test.c's own #include <windows.h> finds it)
    mkdir -p "$OUT/posix_inc"
    printf '#include "%s/win32_posix.h"\n' "$(pwd)" > "$OUT/posix_inc/windows.h"
    command -v "$CLANG" > /dev/null 2>&1 || CLANG=cc
    "$CLANG" -O1 -w -I "$OUT/posix_inc" -o "$OUT/coop_test.exe" coop_test.c -lm
    exec < /dev/null        # (fd 0 open: coop.c takes a socket numbered 0 as a failed one)
fi
cd "$OUT"

# room <exe> <label>: the 4- and 12-player rooms with <exe>; 1 when one failed
room() {
    exe=$1; label=$2; bad=0
    "$exe" join 1 > /dev/null 2>&1 || true      # (a fresh exe's first start can be slow: warm it up)
    for joiners in 3 11; do
        rm -f ./*.rc ./join*.txt host.txt
        export COOP_TEST_JOINERS=$joiners
        (set +e; "$exe" host 16 > host.txt 2>&1; echo $? > host.rc) &
        sleep 0.3
        j=1
        while [ $j -le $joiners ]; do
            (set +e; "$exe" join > join$j.txt 2>&1; echo $? > join$j.rc) &
            j=$((j + 1))
        done
        # (and in the 4-player run, one of another build: refused, told the host's, never a slot; the others unaffected)
        if [ $joiners = 3 ]; then rm -f badver.rc badver.txt; (set +e; COOP_TEST_VER=other "$exe" join > badver.txt 2>&1; echo $? > badver.rc) & fi
        sleep 19
        # (off Windows, up to 20 s more for every exit code: a sanitized build is slower)
        if [ "$WIN" = 0 ]; then
            k=0
            while [ $k -lt 40 ]; do
                n=0; [ -f host.rc ] || n=1
                j=1; while [ $j -le $joiners ]; do [ -f join$j.rc ] || n=1; j=$((j + 1)); done
                if [ $joiners = 3 ] && [ ! -f badver.rc ]; then n=1; fi
                [ $n = 0 ] && break
                sleep 0.5; k=$((k + 1))
            done
            # (anything still running now is a hang: name it, take its stack if gdb is here, and stop it, so it can't
            # hold the port or write into the next room's files)
            left=$(pgrep -f "$(basename "$exe") (host|join)" 2>/dev/null || true)
            for p in $left; do
                echo "coop test$label: process $p ($(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)) still running 39 s on"
                if command -v gdb > /dev/null 2>&1; then
                    gdb -p "$p" -batch -ex "thread apply all bt" 2>/dev/null | grep -E "^#" | head -12 | sed 's/^/    /' || true
                fi
                kill "$p" 2>/dev/null || true
            done
        fi
        grep -vh "\[log\]" host.txt join*.txt | grep -E "player|reliable|enemy|OUT OF|full|samerole|guard" | grep -vE "mean 0\.|of 40 messages" || true
        if [ $joiners = 3 ]; then grep -h "another build\|refused" badver.txt host.txt | head -3 || true; fi
        fail=0; why=""
        [ -f host.rc ] && [ "$(cat host.rc)" = 0 ] || { fail=1; why="$why host's exit code $(cat host.rc 2>/dev/null || echo none);"; }
        j=1
        while [ $j -le $joiners ]; do
            [ -f join$j.rc ] && [ "$(cat join$j.rc)" = 0 ] || { fail=1; why="$why joiner $j's exit code $(cat join$j.rc 2>/dev/null || echo none);"; }
            j=$((j + 1))
        done
        if [ $joiners = 3 ]; then [ -f badver.rc ] && [ "$(cat badver.rc)" = 0 ] || { fail=1; why="$why the other build's exit code $(cat badver.rc 2>/dev/null || echo none);"; }; fi
        # (the summary lines: a run that printed nothing must not pass)
        grep -q "^host: guard: bad states dropped, a good one kept" host.txt || { fail=1; why="$why no host guard line;"; }
        k=2
        while [ $k -le $((joiners + 1)) ]; do
            grep -q "^host: from player $k: 40 of 40 messages" host.txt || { fail=1; why="$why no 'host: from player $k: 40 of 40' line;"; }
            k=$((k + 1))
        done
        j=1
        while [ $j -le $joiners ]; do
            grep -q "^join [0-9]*: reliable 120 of 120 from the host, in order: yes" join$j.txt || { fail=1; why="$why joiner $j has no 'reliable 120 of 120 ... yes' line;"; }
            grep -q "^join [0-9]*: the enemy copy: mean" join$j.txt || { fail=1; why="$why joiner $j has no enemy copy line;"; }
            j=$((j + 1))
        done
        if [ $joiners = 3 ]; then grep -q "^join: another build (other): refused, told the host's" badver.txt || { fail=1; why="$why no refused line from the other build;"; }; fi
        # (a sanitized build: any report but the suppressed one fails)
        if grep -l "ERROR: AddressSanitizer\|ERROR: LeakSanitizer\|runtime error:" host.txt join*.txt badver.txt > /dev/null 2>&1; then
            fail=1; why="$why sanitizer reports:"
            for f in host.txt join*.txt badver.txt; do
                [ -f "$f" ] || continue
                grep -q "ERROR: AddressSanitizer\|ERROR: LeakSanitizer\|runtime error:" "$f" || continue
                why="$why $f"; echo "---- $f:"; grep -v "\[log\]" "$f" | grep -A30 "ERROR: \|runtime error:" | head -40
            done
        fi
        if [ "$fail" = 0 ]; then echo "coop test$label ($((joiners + 1)) players): passed"
        else
            keep="failed_room_$((joiners + 1))${label:+_san}"
            rm -rf "$keep"; mkdir -p "$keep"; cp host.txt join*.txt ./*.rc "$keep"/ 2>/dev/null || true; [ $joiners = 3 ] && cp badver.txt "$keep"/ 2>/dev/null || true
            echo "coop test$label ($((joiners + 1)) players): FAILED:$why (see build/checks/$keep)"; bad=1
        fi
    done
    return $bad
}

result=0
room ./coop_test.exe "" || result=1

if [ "${SANITIZE:-0}" = 1 ]; then
    if [ "$WIN" = 1 ]; then echo "coop test: SANITIZE=1 is for Linux (gcc's ASan / UBSan); not run"; exit $result; fi
    SAN_CC=${SAN_CC:-gcc}
    SANF="-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined,float-cast-overflow"
    # (no -w: gcc's -Wrestrict names the same overlap at compile time)
    if ! (cd ../../tools/checks && "$SAN_CC" $SANF -Wno-unused-function -Wno-unknown-pragmas -I "$OUT/posix_inc" \
            -o "$OUT/coop_test_san.exe" coop_test.c -lm); then
        echo "coop test (sanitized): FAILED to build with $SAN_CC (its ASan / UBSan runtime missing?)"; exit 1
    fi
    # (the tests never free their fake objects: those leaks only, by the functions that make them)
    printf 'leak:NewObj\n' > lsan.supp
    printf 'interceptor_via_fun:CoPushSnap\n' > asan.supp
    export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1"
    export LSAN_OPTIONS="suppressions=$(pwd)/lsan.supp:print_suppressions=0"
    # 1. the known finding, unsuppressed: a host and one joiner for up to 6 s (a stream's 13th snapshot shows it)
    export ASAN_OPTIONS="abort_on_error=0"
    rm -f known_host.txt known_join.txt
    COOP_TEST_JOINERS=1 ./coop_test_san.exe host 6 > known_host.txt 2>&1 &
    sleep 0.3
    COOP_TEST_JOINERS=1 ./coop_test_san.exe join 5 > known_join.txt 2>&1 || true
    wait || true
    if grep -q "memcpy-param-overlap" known_host.txt known_join.txt && grep -q "in CoPushSnap .*coop.c:775" known_host.txt known_join.txt; then
        echo "coop test (sanitized): KNOWN DEFECT reproduced, not counted: memcpy-param-overlap in CoPushSnap (runtime/coop.c:775,"
        echo "    a stream's 13th snapshot shifts its 12 with memcpy over itself; memmove is the call). Its stack:"
        grep -h -A6 "memcpy-param-overlap" known_host.txt known_join.txt | head -8 | sed 's/^/    /'
    else
        echo "coop test (sanitized): the known memcpy-param-overlap in CoPushSnap (coop.c:775) wasn't reported this time:"
        echo "    fixed? then drop asan.supp's line from coop_test.sh"
        grep -h -A8 "ERROR: AddressSanitizer" known_host.txt known_join.txt | head -10 | sed 's/^/    /' || true
    fi
    # 2. the rooms, with only that report suppressed
    export ASAN_OPTIONS="suppressions=$(pwd)/asan.supp:abort_on_error=0:detect_stack_use_after_return=1"
    room ./coop_test_san.exe " (sanitized)" || result=1
fi
exit $result
