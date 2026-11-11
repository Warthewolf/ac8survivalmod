#!/bin/sh
# zip_guard.sh <stage folder> : the last look at a staged zip before tools/package_release.sh / package_test.sh pack it.
# Refuses (exit 1) when the stage holds anything that is the user's own install only (AGENTS.md):
#   THE TANICORN's container (SurvivalMode_Tani_P.*: the Tanager stand-in is Sea Power's Iowa; TANI=1 dev builds only,
#   tools/package_dev.sh)
# tools/checks/zip_leak_test.sh runs both packagers over a made-up build and checks this.
st=$1
[ -d "$st" ] || { echo "zip_guard.sh: no stage folder $st"; exit 2; }
bad=$(find "$st" -type f -iname 'SurvivalMode_Tani_P.*' 2>/dev/null)
# ((2026-11-12) ZIP_GUARD_TANI=1: package_release.sh TESTER=1 TANI=1, a tester's zip with THE TANACORN, the user's call)
if [ -n "$bad" ] && [ "$ZIP_GUARD_TANI" = 1 ]; then echo "zip guard: THE TANACORN's container kept (TESTER=1 TANI=1)"; bad=; fi
if [ -n "$bad" ]; then
    echo "zip_guard.sh: REFUSED: the stage holds the Tanicorn's container (the user's install only, never in a zip):"
    echo "$bad" | sed 's/^/  /'
    exit 1
fi
echo "zip guard: nothing of the user's install only in $st"
