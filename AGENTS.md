# AC8 Survival Mode — instructions for Codex and Claude Code

Both AI agents read this file at the start of every session. It is short on purpose: the details are in `docs/rules/`
and `docs/re/` and are read only when the task needs them. Keep this file under 200 lines.

## 0. Who you work for
The person running this repo may not know git or programming. **You do the repository work for them**: branches,
commits, merges, cleanup, releases. Never ask them to type a git command or to choose a branch name; make the choice
by the rules below. Talk to them in plain words, short: what you did, what is left, what they need to decide.
Never use jargon without saying what it means. If something fails, say so with the error, and what you will try.
The repo has two long-lived branches: `dev` (everything that works) and `main` (what players get = the last release).

## 1. Project (what this is)
A round-based survival mode mod for Ace Combat 8 (PC). Waves escalate each round; every 5th round is a special enemy
round (aces, Ladon bombers, ...). Between rounds the player lands at an airfield and spends credits (kills) on ammo,
flares, repairs and wingmen. Players install it through ACE8 Mod Launcher (a toggle) and edit `config/survival.ini`.
The user's confirmed design: `docs/design/SURVIVAL_SPEC.md` (overrides the old design thesis). Before building any game
feature read `docs/design/MISSION_REFERENCE.md` (which stock mission already does it: copy a working stock pattern
before inventing one). Issue contact: @voidcallsreaper on Discord.

## 2. Every task, in this order
**Step 1: Start clean and name the branch** (you, not the user)
1. `git status` must be clean. If not, tell the user what is unsaved and stop.
2. `git fetch --all --prune`, `git switch dev`, `git pull --ff-only` (bring `dev` up to date with `origin`).
3. `git switch -c <kind>/<topic>`. The name says what the task does, so anyone reading the branch list understands it:
   - kind: `feature` (new thing), `fix` (bug), `docs`, `tools` (build / scripts), `re` (reverse engineering notes);
   - topic: 2-4 words, lowercase, dashes: `feature/escort-coop-scaling`, `fix/store-freeze-guard`, `docs/agents-slim`;
   - **never** a generated name (`claude/...`, `new-session-...`, `worktree-...`). If the session started on one,
     rename it first: `git branch -m <kind>/<topic>`.
   - One topic per branch. Never work on `main`. Never work on `dev` itself (only a tiny fix the user asks for there).
4. The branch's first commit message says what the branch is for (one sentence).

**Step 2: Read** only what the task needs: this file; the plan in `docs/design/`; the rules file(s) for the area
(section 4); the matching `docs/re/*.md`. `HISTORY.md` only through grep, never whole.

**Step 3: Plan** a task of more than one step in `docs/design/<TOPIC>_PLAN.md`, show it to the user before any code,
keep it current as they decide. Plans are local notes (git-ignored): never commit one, never cite one from code, docs
or HISTORY.md. A problem found on the way goes into the plan or a note to the user, never into a silent fix.

**Step 4: Code** where the code lives (section 3). Follow the rules file of the area. No machine path in the repo
(section 5).

**Step 5: Check.** Lua edit: `python -X utf8 tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/*.lua` (all
parts together). Then `sh tools/build_all.sh` (runs the checks), then the `tools/checks/` tests for what changed.
Report what passed, what failed, what could not be run. A failing check is never hidden or skipped.

**Step 6: Hand over a build.** `python -I tools/bump_version.py` BEFORE `build_all.sh` (a new version for every build
the user gets; never two builds under one version). Notes about the build go at the END of `HISTORY.md`. A lesson a
test confirmed goes into the right `docs/rules/` file as a numbered hard rule (never here).

**Step 7: Save the work.** Commit on the task branch with `[agent] what changed` (agent = claude or codex), in small
logical commits. Commit at the end of every working step, so nothing is lost. A commit message is the `[agent]` line,
a blank line and, if useful, a short body: nothing else. **No `Claude-Session:` line, no claude.ai link, no session
id** (a cloud session adds one by itself: delete it from the message before the commit; it points to a private page and
only adds noise to the public history). Never rewrite published commits to remove one.

**Step 8: Close the branch** (do not leave it open). When the user says the task is done or the build is good:
1. `git switch dev`, `git pull --ff-only`, `git merge --no-ff <branch>` (a merge commit naming the branch).
2. `git push origin dev`.
3. Delete the branch, local and remote: `git branch -d <branch>` and `git push origin --delete <branch>` (skip the
   second if it was never pushed). A branch that is not merged is never force-deleted without the user's yes.
4. Tell the user: "<topic> is in dev, branch closed."
If the user drops the task: ask, then delete it, or tag it `archive/<topic>` first if the work might come back.

**Step 9: Keep the tree clean.** At the start and the end of every session run `sh tools/branch_report.sh` (read
only). It lists every branch with its date, whether it is merged into `dev`, and flags bad names. Tell the user, in
plain words, about each stale branch (what it is, merged or not) and propose the cleanup. Never delete one unasked.

## 3. Where code lives (edit the source, never the output)
| what | where |
|---|---|
| game logic (rounds, shop, HUD, menu, co-op) | `mod/UE4SS/AC8SurvivalMode/Scripts/sv_*.lua` (never `main.lua`: it only runs the parts; each part under 2,000 lines) |
| native runtime (hooks, spawner, sound, co-op transport) | `runtime/*.c` (built by `runtime/build.sh`) |
| packages, tables, world data, events | `tools/build_survival*.py`, `tools/survival_events*.py` (never edit `mod/Content`: generated) |
| settings players edit | `config/survival.default.ini`; subtitles: `config/subtitles.ini` |
| checks and tests | `tools/checks/` |
| design / reverse engineering | `docs/design/`, `docs/re/` |
| build and release scripts | `tools/*.sh` (`tools/README.md`) |

## 4. Which rules file to read (each task: read the ones for its area)
Hard rules are numbered lessons from real tests; old notes cite them as "hard rule N", so numbers never change.
| area | file | hard rules |
|---|---|---|
| packages, containers, materials, ported units | `docs/rules/containers_assets.md` | 7 8 31 32 34 42 44 58 |
| Lua code and UE4SS Lua limits | `docs/rules/lua_runtime.md` | 9 10 11 21 23 27 30 47 63 |
| native C runtime | `docs/rules/native_runtime.md` | 14 19 25 28 43 55 |
| spawning, events, paths, AI, damage | `docs/rules/ai_spawning_behaviour.md` | 1-6 15 16 17 20 22 26 35-41 45 46 54 59 64 |
| menus, HUD, radio, music | `docs/rules/ui_menu_hud.md` | 12 13 18 24 29 33 52 57 |
| co-op | `docs/rules/coop.md` | 48-51 53 |
| sky, clouds, lightning, VFX | `docs/rules/sky_weather_vfx.md` | 56 60-62 |
| leaderboard | `docs/rules/leaderboard.md` | |
| source layout, how files are split, subtitles | `docs/rules/layout.md` | |
| allowed sources, release exclusions, toolchain | `docs/rules/sources_and_toolchain.md` | |
Each feature's design, reverse engineering, log lines and tests: `docs/re/*.md` (index in `docs/README.md`). Every
build's notes: `HISTORY.md` (grep it).

## 5. Rules that apply to every task
- **Stock files only.** Survival is built from stock game files. Other mods' files, assets, values or text never go in
  the build, `mod/`, `tools/`, this repo (docs and commit messages included) or a zip, and nothing credits another
  mod as the source of an enemy change. The exceptions the user granted are listed in
  `docs/rules/sources_and_toolchain.md`: read it before using any outside asset. Other people's pull requests need the
  user's yes, each one. Never AC7 voice lines.
- **Release builds exclude** everything of DISTANT THUNDER and THE TANACORN (and her INVINCIBLE FLEET): their Lua stays
  in `TEST ONLY` / `DEV ONLY` blocks, their assets in their own containers (`tools/checks/zip_leak_test.sh` fails a zip
  that leaks them). Test keys never ship.
- **No machine path in the repo.** A path that differs per machine (game, UE, AC7 exports, work folder, tool exe, main
  tree) is never written into a tool, script, doc or this file. Tools read it from `.env` (from `.env.example`; shell:
  `. tools/env.sh` then `sv_need NAME "what"`; Python: `env.need('NAME', 'what')`); paths inside the repo come from git
  (`git rev-parse --show-toplevel`; `--git-common-dir` for the main tree); a new setting goes into `.env.example` and
  `tools/env.py --check`; docs write `build/...`, `<repo>` or `$UE` / `$AC7` / `$AC8_DIR`. `tools/checks/paths_check.py`
  fails the build on one.
- **No source file over 2,000 lines** (`tools/checks/size_check.py`): split at a topic boundary (`docs/rules/layout.md`).
- Lua: at most 200 locals per part; native Lua function names at most 15 characters (`lua_check.py` fails both).
- Shared stock tables (DT_LiveMissionTable, ...) are never overridden: Survival's rows live in its own `DT_SV_*` tables.
  Survival is its own mod: never repoint another mod's files or mission slot (Stonehenge Returns included).
- Never delete or overwrite game files. Work on copies inside the repo folder.
- Edit the generators (`tools/build_survival.py` ...), never the generated binaries.
- AGENTS.md keeps rules only. No build notes, no dates of tests, no version numbers here: they go to `HISTORY.md`,
  `docs/rules/` or `docs/re/`. If this file passes 200 lines, move something out.

## 6. Release (what "make a release" means)
When the user says "release", "publish", "make the zip" or "ship it", do all of this, in order, without asking again:
1. On `dev`, everything merged, `git status` clean (finish Step 8 for any open branch first).
2. `python -I tools/bump_version.py`, then `sh tools/build_all.sh` (must pass).
3. `sh tools/package_release.sh online <version>` (friends' co-op zip: `BUILD_NAME=COOP2MP COOP=1 ...`, with `ZFA=1`
   `SONG=1` as the build has them; the user's own install: `sh tools/package_dev.sh <version>`, which never pushes).
   The zip goes to the main tree's `build/release`; `<zip>.buildhash.txt` is registered on the leaderboard by the script.
   Say clearly if the registration was skipped.
4. **Push to `main`: `sh tools/release_push.sh <version>`.** It refuses unless the tree is clean, you are on `dev`, the
   zip exists and the version is new; then it merges `dev` into `main`, tags `v<version>`, and pushes `main`, `dev` and
   the tag to `origin`. This is how players get the update: a release that is built but not pushed is not released.
   The user's request for a release is the permission for this one push; nothing else pushes to `main`.
5. Tell the user in plain words: version, where the zip is, that `main` is updated (or what failed).
Never push to `main` any other way, never force-push, never rewrite history. Only `origin` is pushed to.

## 7. Working with two agents
Claude Code: Lua runtime, native runtime, menus, rounds, shop. Codex: config and wave tables, launcher, packaging.
They never edit the same files at once: each task has its own branch. Before starting, pull and read the latest
commits. A confirmed lesson goes into the right `docs/rules/` file, a build's notes into `HISTORY.md`.
