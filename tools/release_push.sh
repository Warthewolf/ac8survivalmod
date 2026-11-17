#!/bin/sh
# release_push.sh <version> : publish a built release. Run it AFTER tools/package_release.sh <...> <version> passed.
# AGENTS.md section 6: "make a release" = the user's permission for this one push. It puts dev's tip on origin's main
# (fast-forward only, never a force), tags it v<version> and pushes the tag and dev. That is how players get an update.
# It refuses unless: you are on dev, the tree is clean, dev is not behind origin/dev, origin/main is already inside dev
# (nothing would be lost), main.lua's VERSION is exactly <version>, the PUBLIC zip AC8SurvivalMode_<version>_Online.zip
# exists in the release folder (a friends' or tester zip does not count), and the tag is new. All of it before any push.
# DRY_RUN=1 sh tools/release_push.sh <version> : checks everything and says what it would push, pushes nothing.
# Then it creates the GitHub Release v<version> (the Releases section) with `gh`: title, the release notes and the PUBLIC
# zip only (AC8SurvivalMode_<version>_Online.zip = the Nexus build; the friends' / tester variants are never attached).
# The notes are a plain description of what changed, written BEFORE running this (AGENTS.md section 6) into
# <release folder>/RELEASE_NOTES_<version>.md; the script refuses without them. No gh, or not logged in: the push still
# happens and the script prints the one gh command to run later (gh auth login once).
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

# the built version must be exactly the one asked (0.74.7 must not pass for 0.74.70), and its PUBLIC zip must exist
lua=$(grep -m1 -E '^(local )?VERSION = ' mod/UE4SS/AC8SurvivalMode/Scripts/main.lua | sed 's/.*"\(.*\)".*/\1/')
[ "$lua" = "$ver" ] || fail "main.lua's VERSION is $lua, not $ver: give the exact version (or bump and build first)"
. tools/release_dir.sh
pub="$REL/AC8SurvivalMode_${ver}_Online.zip"
[ -f "$pub" ] || fail "no public zip $pub: run tools/package_release.sh online $ver first (a friends' or tester zip is never released)"
notes="$REL/RELEASE_NOTES_$ver.md"
[ -s "$notes" ] || fail "no release notes: write what changed (plain words) in $notes first (AGENTS.md section 6)"
if grep -n -i -e 'thunder' -e 'tanicorn' -e 'tanacorn' -e 'invincible fleet' "$notes"; then
    fail "the notes name Distant Thunder / Tanacorn / the Fleet: they are never in a release (AGENTS.md section 5); take them out"
fi
tag="v$ver"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && fail "tag $tag already exists: a new build needs a new version (tools/bump_version.py)"

echo "release_push: $newc commit(s) go to $remote/main as $tag; public zip: $pub"
if [ "$DRY_RUN" = 1 ]; then echo "release_push: DRY RUN, nothing pushed."; exit 0; fi

git tag -a "$tag" -m "Release $ver"
git push "$remote" dev
git push "$remote" dev:main        # fast-forward only: the remote refuses anything else
git push "$remote" "$tag"
# bring the local main branch up to date when git lets us (it may be checked out in another worktree)
git fetch "$remote" main:main -q 2>/dev/null || echo "release_push: (local main not moved: it is checked out elsewhere; $remote/main is up to date)"
# the GitHub Release (Releases section): notes + the public zip (checked above, before any push)
if command -v gh >/dev/null 2>&1; then
    repo=$(git remote get-url "$remote")
    if gh release create "$tag" --repo "$repo" --title "Survival Mode $ver" --notes-file "$notes" --target main "$pub"; then
        echo "release_push: GitHub Release $tag created."
    else echo "release_push: the push worked but the GitHub Release failed (gh auth login? then: gh release create $tag --repo $repo --title \"Survival Mode $ver\" --notes-file $notes $pub)"; fi
else
    echo "release_push: gh is not installed: no GitHub Release. Later: gh release create $tag --title \"Survival Mode $ver\" --notes-file $notes ${pub}"
fi
echo "release_push: DONE. $remote/main is at $(git rev-parse --short dev), tagged $tag."
