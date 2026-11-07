# Contributing to AC8 Survival Mode

Thanks for helping. This page gets a new machine from a fresh clone to a working build and tests. Read
[AGENTS.md](AGENTS.md) before changing anything: it holds the project's rules and the hard-won lessons ("hard rules")
that every change, by a person or an AI agent, must keep.

## What you need

| What | Why | Where it comes from |
| --- | --- | --- |
| Windows, ACE COMBAT 8 (Steam) | The mod and the stock files the build copies from | Your own copy of the game |
| UE4SS 3.0.1 and IoStoreLoaderMod in the game | They load the mod | The game's modding setup |
| Git for Windows (Git Bash) | Every `.sh` tool runs in `sh` | git-scm.com |
| Python 3.8 or later on PATH as `python` | The build tools and the checks | python.org (`pip install cryptography` only for `tools/pak_read.py`) |
| LLVM (clang, lld-link, llvm-dlltool) | The native runtime, `runtime/build.sh` | Unpack the LLVM Windows installer into `tools/llvm` (`msiexec /a LLVM-<ver>-win64.msi /qn TARGETDIR=<repo>\tools\llvm`), or any LLVM on PATH, or set `LLVM_BIN` |
| `tools/bin/retoc.exe`, `tools/bin/oo2core_9_win64.dll` | Reading and packing the game's IoStore containers | ACE8AircraftBuilder's folder (not in git) |
| The game's AES key | Reading its paks | Ask the maintainer, or ACE8AircraftBuilder's `settings.json`; never commit it |

Optional, for the maintainer's VALKA build only: Unreal Engine 5.4, AC7's UModel and exported assets
(`tools/x02s/README.md`). Nobody else needs them.

## Set up your machine

```sh
python -I tools/env.py --init     # copies .env.example to .env (git-ignored)
# open .env and set AC8_DIR (the game's install folder) and AC8_AES_KEY (or AC8_AES_SETTINGS)
python -I tools/env.py --check    # every setting, where it came from, whether it exists; it ends with "ready"
```

`.env` holds your machine's paths: the game, its key, LLVM, where releases go, and the optional tools. Every tool reads
it (`tools/env.sh` for the shell tools, `tools/env.py` for the Python ones). A variable already set in your
environment wins over it. One `.env` in the main git tree also serves every `git worktree` made from it. Nothing in it
is ever committed.

## Build and test

```sh
sh tools/checks/lua_build.sh                       # once: builds Lua 5.4.6 (UE4SS's) into build/checks for the tests
python -X utf8 tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/*.lua   # after every Lua edit
for t in tools/checks/*_test.sh; do sh "$t" > /dev/null 2>&1 || echo "FAILED: $t"; done   # the test suites
sh tools/build_all.sh                              # the full build: build/install (the mod, ready to install)
sh tools/package_dev.sh <name>                     # your own test install, test keys kept: build/release/stage_dev_<name>
```

`tools/checks/coop_test.sh` opens a dozen console windows (it runs a whole co-op room); run it when nobody is playing.

To install a build, close the game first and back up what's there. Then copy `stage_dev_<name>/ue4ss/Mods/*` into the
game's `ue4ss/Mods` folder (`AC8_MODS`). Never change the game's own files.

## The rules that matter most

- **Only stock game files.** Survival is built from ACE COMBAT 8's own assets. No other mod's files, tables, values or
  text go into the build, the tools, the docs or a release (AGENTS.md, "Toolchain").
- **No secrets in git:** `.env`, the AES key, `leaderboard/*.secret` and `leaderboard/submit.local` stay on your
  machine. Game assets never go in either (`build/`, `mod/Content/` and `source/` are git-ignored).
- **Keep files small.** No source file over 2,000 lines (`python -I tools/checks/size_check.py`, which the build
  runs). When a file grows past it, split it at a topic boundary, as `tools/lua_split.py` does for the Lua parts.
- **Lua parts share one state.** `Scripts/main.lua` runs the `sv_*.lua` parts in its `MODULES` order. A name another
  part uses is a global; a part's own helpers stay `local`. A part's main chunk may hold at most 200 locals
  (`lua_check.py` checks it).
- **Every build handed to someone gets a new version** (`python -I tools/bump_version.py` before `build_all.sh`).
  Co-op refuses to link games on different builds.
- **Test keys never ship.** Code between `-- TEST ONLY BEGIN` and `-- TEST ONLY END` is stripped from every release zip.
- **Commits** say what changed and why, starting with who made them: `[name] what changed`.

## Where things are

| Path | What |
| --- | --- |
| `mod/UE4SS/AC8SurvivalMode/Scripts/` | The Lua runtime: `main.lua` (the controller) and its `sv_*.lua` parts |
| `mod/UE4SS/AC8SurvivalMode/config/` | `survival.default.ini`, every player setting |
| `runtime/` | The native runtime (plain C, built with LLVM): `main.dll` |
| `tools/` | The build: `build_all.sh`, `build_survival.py` and `survival_events.py` (the generated content), packaging |
| `tools/checks/` | The test suites and checkers |
| `tools/re/` | Reverse-engineering notes, one file per system or feature |
| `leaderboard/` | The leaderboard's Cloudflare Worker |

## Reporting a bug

Send these files with what happened, the round, the time, and your build's version. The files are in
`ACE COMBAT 8\Game\Binaries\Win64\ue4ss\Mods\AC8SurvivalMode\`, plus `ue4ss\UE4SS.log`:

- `AC8SurvivalMode_lua.log` and `AC8SurvivalMode.log`.
- `AC8SurvivalMode_crumbs.log`, and after a crash `AC8SurvivalMode_crumbs.prev.log` too.
- After a crash, the newest `UECC-Windows-...` folder from
  `%LOCALAPPDATA%\BANDAI NAMCO Entertainment\ACE COMBAT 8\Saved\Crashes\`.

Your PC's RAM and page file size and your rough location help with crashes and lag. Name the archive
`Bug_Report_<your name>_<version>.zip`.
