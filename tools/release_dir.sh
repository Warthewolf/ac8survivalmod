#!/bin/sh
# release_dir.sh (sourced by tools/package_release.sh and tools/package_test.sh): REL = where release zips and their
# .buildhash.txt go. Always the MAIN tree's build/release, from any git worktree
# (user, 2026-11-07: all future releases go into the main tree's build/release), so a zip built in an
# agent's worktree lands with every other release. RELEASE_DIR=<folder> overrides it. The staging
# folders (build/release/stage_*) stay in the tree that builds. RELEASE_DIR may also be set in .env (tools/env.sh,
# which this loads, so every packaging script that sources this file has the .env settings too).
. tools/env.sh
if [ -n "$RELEASE_DIR" ]; then
    REL=$RELEASE_DIR
else
    common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [ -n "$common" ]; then REL="$(dirname "$common")/build/release"; else REL=build/release; fi
fi
mkdir -p "$REL"
