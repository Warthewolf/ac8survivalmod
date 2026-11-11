#!/bin/sh
# run_all.sh : every check that needs no game files, in one go, with a table at the end: the build's own checks (as
# tools/build_all.sh runs them), every tools/checks/*_test.sh suite and the leaderboard Worker's tests (node, no install).
# Each suite's output goes to build/checks/run_all/<name>.txt. Off Windows (Linux, a cloud session) the C suites that need
# windows.h / Win32 itself are skipped and say so; everything else runs the same there.
#   sh tools/checks/run_all.sh            all of them
#   sh tools/checks/run_all.sh escort sky  only the suites whose names hold one of these words
#   sh tools/checks/run_all.sh coop_test   co-op's transport test, which opens a dozen console windows (Windows only):
#                                          never run unless named so, whole
# Exit code 1 when anything failed (a skip is not a failure).
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT="$ROOT/build/checks/run_all"
rm -rf "$OUT" && mkdir -p "$OUT"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WIN=1 ;; *) WIN=0 ;; esac
# C suites that need windows.h and Win32 at run time (a vectored exception handler, Winsock / Steam lookups, bcrypt,
# FindFirstFileW): only on Windows
WIN_ONLY=" safecall_test pathguard_test flight_test coop_test build_hash_test "
TO=""
command -v timeout > /dev/null 2>&1 && TO="timeout 600"
FILTER="$*"
TABLE="$OUT/table.txt"
: > "$TABLE"
NPASS=0 NFAIL=0 NSKIP=0

wanted() {
    [ -z "$FILTER" ] && return 0
    for w in $FILTER; do case "$1" in *"$w"*) return 0 ;; esac; done
    return 1
}
# run <name> <command...>
run() {
    name=$1; shift
    wanted "$name" || return 0
    t0=$(date +%s)
    $TO "$@" > "$OUT/$name.txt" 2>&1
    rc=$?
    dt=$(( $(date +%s) - t0 ))
    if [ "$rc" = 0 ]; then
        NPASS=$((NPASS + 1)); printf '%-22s pass  %3ss\n' "$name" "$dt" >> "$TABLE"
    else
        NFAIL=$((NFAIL + 1)); printf '%-22s FAIL  %3ss  rc=%s: %s\n' "$name" "$dt" "$rc" \
            "$(grep -m1 -E 'FAIL|Error|ERROR|error' "$OUT/$name.txt" | cut -c1-100)" >> "$TABLE"
    fi
    printf '.'
}
skip() {
    wanted "$1" || return 0
    NSKIP=$((NSKIP + 1)); printf '%-22s skip         %s\n' "$1" "$2" >> "$TABLE"
}

sh tools/checks/lua_build.sh > "$OUT/lua_build.txt" 2>&1 || { cat "$OUT/lua_build.txt"; echo "run_all: no Lua (tools/checks/lua_build.sh)"; exit 1; }

# the build's own checks (tools/build_all.sh)
run lua_check      python -X utf8 -I tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/*.lua
run lua_check_ai   python -X utf8 -I tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/ai/*.lua
run ini_check      python -X utf8 -I tools/checks/ini_check.py
run subtitles      python -X utf8 -I tools/subtitles.py check
run size_check     python -X utf8 -I tools/checks/size_check.py
run menu_pages     python -X utf8 -I tools/checks/menu_pages_test.py
# hard rule 43 over the native runtime (not in build_all.sh yet)
run rt_format      python -X utf8 -I tools/checks/rt_format_check.py
# the suites
for f in tools/checks/*_test.sh; do
    name=$(basename "$f" .sh)
    if [ "$WIN" = 0 ]; then
        case "$WIN_ONLY" in *" $name "*) skip "$name" "needs Windows (windows.h, Win32 at run time)"; continue ;; esac
    fi
    # (coop_test opens a dozen console windows and takes the focus: CONTRIBUTING.md) only when named whole
    if [ "$name" = coop_test ] && ! printf ' %s ' "$FILTER" | grep -q ' coop_test '; then
        skip coop_test "opens a dozen windows: sh tools/checks/run_all.sh coop_test"; continue
    fi
    run "$name" sh "$f"
done
# the leaderboard Worker (Node 22+, no npm install: it imports only node: built-ins and ../src/index.js)
if command -v node > /dev/null 2>&1; then
    run worker_test sh -c 'cd leaderboard && node test/worker.test.mjs'
else
    skip worker_test "no node on PATH"
fi

echo
cat "$TABLE"
echo "run_all: $NPASS passed, $NFAIL failed, $NSKIP skipped (outputs in build/checks/run_all)"
[ "$NFAIL" = 0 ]
