#!/bin/sh
# lb_contract_test.sh : runs tools/checks/lb_contract_test.mjs with node (no install): every special kind the Lua sends
# (LB.special) is one the leaderboard Worker keeps and scores, and main.lua's VERSION, with and without COOP_TAG, passes
# its version check. Needs Node 22+ on PATH (as leaderboard/test/worker.test.mjs).
set -e
cd "$(dirname "$0")"
command -v node > /dev/null 2>&1 || { echo "lb contract: node not found (Node 22 or newer)"; exit 1; }
node lb_contract_test.mjs "$(cd ../.. && pwd)"
