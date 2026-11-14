# Leaderboard

Moved verbatim from AGENTS.md (2026-11-14).

## Leaderboard
leaderboard/README.md has the deploy steps (paste src/index.js; the Worker makes its new tables itself). The Worker takes
co-op versions (0.72.2-coop.20), has an admin page for the user only (GET /admin; ADMIN_KEY in the POST body, 5 wrong
keys lock an address out: reset (archived, undoable), restore, builds, verification), and counts a run only from a
registered build: the runtime hashes the mod's files (runtime/build_hash.c, the same as tools/build_hash.py:
tools/checks/build_hash_test.sh) and sends X-SV-Build, signed with the run; package_release.sh online writes
<zip>.buildhash.txt to register. Register every zip given out before players send runs from it. The game doesn't send
an edited run (LB.edited: gameplay settings against CFG_DEFAULTS, a survival_config.lua, test keys;
tools/checks/leaderboard_test.sh): a new setting that's only on screen or each player's own goes in its free lists.
The Worker is deployed with the co-op boards; packaging registers every build itself (tools/lb_register.py, the
admin key from the main tree's leaderboard/keys.secret). leaderboard/README.md has the rest.
