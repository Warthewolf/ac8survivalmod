#!/bin/sh
# branch_report.sh : READ ONLY list of every branch (local and on each remote): last commit date, how many commits it
# has that dev doesn't (ahead), whether dev already contains it (merged), and whether its name follows
# <kind>/<topic> (kind: feature fix docs tools re). AGENTS.md section 2, step 9: run it at the start and the end of a
# session and tell the user about each stale branch. It changes nothing (no fetch beyond `git fetch --all --prune`
# with BR_FETCH=1; no delete). Usage: sh tools/branch_report.sh
set -e
cd "$(dirname "$0")/.."
[ "$BR_FETCH" = 1 ] && git fetch --all --prune -q
# "dev" = the furthest-ahead of local dev and the remotes' dev (a stale local dev must not make everything look open)
base=
bn=-1
for c in dev origin/dev upstream/dev; do
    git rev-parse -q --verify "$c" >/dev/null || continue
    n=$(git rev-list --count "$c")
    if [ "$n" -gt "$bn" ]; then bn=$n; base=$c; fi
done
[ -n "$base" ] || { echo "branch_report: no dev branch found"; exit 2; }
echo "Branches compared with $base ($(git rev-parse --short "$base")). OK = nothing to do."
[ "$base" = dev ] || echo "NOTE: local dev is behind $base: run 'git switch dev && git pull --ff-only' before starting work."
echo
git for-each-ref --format='%(refname:short)|%(committerdate:short)' refs/heads refs/remotes |
while IFS='|' read -r b d; do
    case "$b" in */HEAD|origin|upstream) continue ;; esac
    ahead=$(git rev-list --count "$base..$b" 2>/dev/null || echo ?)
    if git merge-base --is-ancestor "$b" "$base" 2>/dev/null; then merged=merged; else merged=NOT-merged; fi
    short=${b#*/}
    case "$b" in refs/*) short=$b ;; esac
    name=$b
    # strip the remote prefix to judge the name itself
    case "$b" in origin/*|upstream/*) name=${b#*/} ;; esac
    case "$name" in
        dev|main|archive/*|backup/*) nm=ok ;;
        feature/*|fix/*|docs/*|tools/*|re/*) nm=ok ;;
        *) nm=BAD-NAME ;;
    esac
    note=OK
    case "$name" in dev|main) ;; *)
        if [ "$b" = "$(git rev-parse --abbrev-ref HEAD)" ]; then note="the branch you are on"
        elif [ "$merged" = merged ]; then note="finished: delete it"
        elif [ "$nm" = BAD-NAME ]; then note="rename to <kind>/<topic> (what does it do?)"
        else note="open: $ahead commit(s) not in dev"; fi ;;
    esac
    printf '%-52s %s  ahead=%-3s %-10s %-8s %s\n' "$b" "$d" "$ahead" "$merged" "$nm" "$note"
done
echo
echo "Local main vs origin/main: $(git rev-list --left-right --count main...origin/main 2>/dev/null | awk '{print "local-only="$1" origin-only="$2}')"
