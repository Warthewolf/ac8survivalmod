---
name: survival-build
description: Build, package and hand over an AC8 Survival Mode build: the version bump, build_all.sh, the right package command (the user's dev install, a friends' COOP2MP zip, a TESTER zip, a Nexus release), leaderboard registration, the checks and the HISTORY.md note. Use this whenever the user asks for a build, a zip, a dev install, "update it", "package it", "make a build for my friends / for <tester>", or anything that ends with a file she or her friends will install, even if she doesn't say "build".
---

# Survival build and hand-over

Every step here exists because skipping it once cost a build: 0.74.0-0.74.8 shipped without a leaderboard address,
two different builds once shared a version, a TANI build nearly shipped the Iowa. AGENTS.md is the source of truth;
this is the order to do it in. Read the scripts' header comments when something here seems out of date.

## 0. Which build?
| She asks for | Command (after build_all) | Where it lands |
|---|---|---|
| her own install / "dev build" / soak or test keys | `VALKA=1 ZFA=1 sh tools/package_dev.sh <ver>` | this checkout's `build/release/stage_dev_<ver>/` (a folder, not a zip) |
| her install with THE TANACORN | `tools/tanicorn/build.sh` to the end, then `TANI=1 ... build_all.sh`, then `TANI=1 VALKA=1 ZFA=1 sh tools/package_dev.sh <ver>` | same |
| friends' zip | `BUILD_NAME=COOP2MP COOP=1 ZFA=1 sh tools/package_release.sh online <ver>` (+ `SONG=1` if the build has it) | main tree's `build/release` |
| a named tester's zip (test keys kept) | `TESTER=1 ...package_release.sh` (with `TANI=1` only if she asked for the Tanacorn in it) | main tree's `build/release`, named `..._TANACORN` with TANI |
| a quick test zip | `sh tools/package_test.sh <name>` | main tree's `build/release` |

When it's unclear whether it's for her or for friends, ask: the two differ in what's stripped.
Never in a friends' / Nexus zip: test keys, DEV ONLY blocks, Distant Thunder, the Tanacorn / INVINCIBLE FLEET
(`tools/checks/zip_leak_test` enforces it; don't work around a refusal, find out why it refused).

## 1. Branch and worktree
Build from the branch the work is on (a worktree per branch, `.claude/worktrees/<name>`). A fresh worktree lacks the
build inputs; link or copy them from the main tree (`git rev-parse --git-common-dir` finds it):
- junctions: `build/{ac7,laser7,stock,valka_music,x02s,zfa44}`, `tools/bin`, and `tools/llvm` for the C tests
  (PowerShell: `New-Item -ItemType Junction -Path <wt>\build\stock -Target <main>\build\stock`);
- copies: `.env`, `tools/scriptobjs.pkl`, `build/checks/lua.exe`.
- LLVM's `bin` (under `tools/llvm/LLVM/bin`) on PATH for `runtime/build.sh` (llvm-dlltool).
No machine path ever goes into a file in the repo (AGENTS.md "How to work" 4).

## 2. Version
`python -I tools/bump_version.py` BEFORE build_all (`--minor` for a new feature line). It bumps main.lua's VERSION
and COOP_TAG together. One version = one build: never hand over two different builds under one number. A runtime
change also bumps `RT_VERSION` in `runtime/survival_rt.c`.

## 3. Build and checks
- `python -X utf8 tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/*.lua` after Lua edits.
- `ZFA=1 sh tools/build_all.sh` (it runs the paths, size and build checks). Run it in the background; it's long.
- The tests for what changed: `tools/checks/*_test.sh` (Lua tests need `build/checks/lua.exe`:
  `sh tools/checks/lua_build.sh`). `sh tools/checks/run_all.sh` for the lot. Skip `coop_test.sh` while she's
  playing: its console windows steal the game's focus.
- The build's log must say `leaderboard: runs go to ...`. If it doesn't, the runtime found no
  `leaderboard/submit.local` (worktree builds read the main tree's); the package scripts refuse it anyway.

## 4. Package
The command from step 0. The online / dev scripts register the build hash with the leaderboard themselves
(`tools/lb_register.py`); check its output says registered. A zip that already exists is refused: bump, don't
`REPACK=1`, unless remaking the very same build.

Check what's inside before handing over: the version strings in `Scripts/main.lua`, `RT_VERSION` in the log, the
containers expected (SurvivalMode_P, Valka, ZFA44, Laser7; Tanicorn only on TANI), test-only parts cut to their
header in a release (`sv_soak.lua`, `sv_anomalies_dev.lua`).

## 5. Hand over
- **Never install into her game until she says so.** Stage only; tell her the path.
- A note at the END of HISTORY.md: the version, the branch and commits, what changed, what's untested in game.
  Never in AGENTS.md (it's loaded every session); a lesson a test confirmed goes there as a hard rule.
- Commit (`[claude] <version>: ...`, noreply email, the attribution lines). Ask before any push or merge into `dev`.
- Tell her: version, where it is, what's in it, what passed / failed / couldn't run, what's untested in game, and
  what she should look for when she plays it.
