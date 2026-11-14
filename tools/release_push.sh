#!/bin/sh
# release_push.sh <version> : publish a built release. Run it AFTER tools/package_release.sh <...> <version> passed.
# AGENTS.md section 6: "make a release" = the user's permission for this one push. It puts dev's tip on origin's main
# (fast-forward only, never a force), tags it v<version> and pushes the tag and dev. That is how players get an update.
# It refuses unless: you are on dev, the tree is clean, dev is not behind origin/dev, origin/main is already inside dev
# (nothing would be lost), the zip for <version> exists in the release folder, and the tag is new.
# DRY_RUN=1 sh tools/release_push.sh <version> : checks everything and says what it would push, pushes nothing.
# REMOTE=<name> to push somewhere else than origin (default origin). Needs no machine path: the zip folder comes from
# tools/release_dir.sh (the main tree's build/release, or RELEASE_DIR in .env).
set -e
cd "$(dirname "$0")/.."
ver=$1
[ -n "$ver" ] || { echo "usage: release_push.sh <version>   (e.g. 0.74.70)"; exit 2; }
remote=${REMOTE:-origin}
fail() { echo "release_push: REFUSED: $1"; exit 1; }

[ "$(git rev-parse --abbrev-ref HEAD)" = dev ] || fail "not on dev (switch to dev, finish and merge your branches first)"
[ -z "$(git status --porcelain)" ] || fail "uncommitted changes: commit or discard them first"
git remote get-url "$remote" >/dev/null 2>&1 || fail "no remote called $remote"
git fetch "$remote" --tags -q || fail "cannot reach $remote (network? login?)"

# dev must contain everything already on the remote's dev, and the remote's main must be inside dev
if git rev-parse -q --verify "refs/remotes/$remote/dev" >/dev/null; then
    git merge-base --is-ancestor "$remote/dev" dev || fail "dev is behind or has diverged from $remote/dev: git pull --ff-only first"
fi
if git rev-parse -q --verify "refs/remotes/$remote/main" >/dev/null; then
    git merge-base --is-ancestor "$remote/main" dev || fail "$remote/main has commits dev does not: ask the user before going on (nothing was pushed)"
    newc=$(git rev-list --count "$remote/main..dev")
else
    newc=$(git rev-list --count dev)
fi
[ "$newc" -gt 0 ] || fail "main already has everything in dev: nothing to release"

# the built version must be the one asked, and its zip must exist
lua=$(grep -m1 -E '^(local )?VERSION = ' mod/UE4SS/AC8SurvivalMode/Scripts/main.lua | sed 's/.*"\(.*\)".*/\1/')
case "$lua" in "$ver"*) ;; *) fail "main.lua's VERSION is $lua, not $ver: bump and build first" ;; esac
. tools/release_dir.sh
ls "$REL"/AC8SurvivalMode_*"$ver"*.zip >/dev/null 2>&1 || fail "no zip for $ver in the release folder: run tools/package_release.sh first"
tag="v$ver"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && fail "tag $tag already exists: a new build needs a new version (tools/bump_version.py)"

echo "release_push: $newc commit(s) go to $remote/main as $tag; zip(s):"
ls "$REL"/AC8SurvivalMode_*"$ver"*.zip
if [ "$DRY_RUN" = 1 ]; then echo "release_push: DRY RUN, nothing pushed."; exit 0; fi

git tag -a "$tag" -m "Release $ver"
git push "$remote" dev
git push "$remote" dev:main        # fast-forward only: the remote refuses anything else
git push "$remote" "$tag"
# bring the local main branch up to date when git lets us (it may be checked out in another worktree)
git fetch "$remote" main:main -q 2>/dev/null || echo "release_push: (local main not moved: it is checked out elsewhere; $remote/main is up to date)"
echo "release_push: DONE. $remote/main is at $(git rev-parse --short dev), tagged $tag."
