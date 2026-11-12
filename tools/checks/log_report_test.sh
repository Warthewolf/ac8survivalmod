#!/bin/sh
# log_report_test.sh : tools/log_report.py (one Markdown page from Survival log bundles) on the made-up bundles in
# tools/checks/fixtures/log_report: a host's folder (the old layout, its clock over midnight) and a joiner's session
# zip (runtime 0.32.32+'s layout, its clock 3:00:07 ahead), alone and together; a solo run, a pair with long and
# non-ASCII names (two players' folders in one bundle), a fork, a joiner that became the host, damaged zips, 0.74.66's
# STOREQ on a host and a joiner (storeq/; the host's without a STORE window too) with its rows, errors and bold agreeing;
# each page's key lines, the clocks aligned, the games' disagreements, every table well formed whatever the logs hold, a
# 200,000-line UE4SS.log streamed, and the checklist's lines (0.74.52's, 0.74.66's) still in the code
# (tools/checks/log_report_test.py). Python only (Windows Git Bash and Linux). Pages in build/checks/log_report.
set -e
cd "$(dirname "$0")"
PY=python
command -v "$PY" > /dev/null 2>&1 || PY=python3
"$PY" -X utf8 -I log_report_test.py
