#!/bin/sh
# tani_container_test.sh : tools/tani_container.py, THE TANACORN's container checked against what a TANI=1 world data imports
# (the weapons reviews of 2026-11-12), on made-up containers and on the real one when tools/tanicorn/build.sh has made it:
# tools/checks/tani_container_test.py. No game, UE or cook needed.
set -e
cd "$(dirname "$0")/../.."
python -X utf8 -I tools/checks/tani_container_test.py
