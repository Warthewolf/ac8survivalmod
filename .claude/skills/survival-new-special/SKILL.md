---
name: survival-new-special
description: Add or substantially change a special round (boss, raid, defence, event round) in AC8 Survival Mode, across the event generator, world data, the Lua part, CFG and subtitles, the rotation, co-op, tests, docs and release exclusions. Use this whenever the user describes a new special round or boss, asks to port a mission's enemy or set piece into Survival, or wants a special reworked (new phases, new weapons, new units), even when she only sketches the idea.
---

# A special round, end to end

A special touches many places, and a forgotten one shows up only in game (a unit that never spawns, a joiner who
never sees it, a test key in a friend's zip). Copy the nearest existing special rather than inventing: GONE FISHIN'
(`sv_fishing.lua`), THE DECOY (`sv_decoy.lua`), the Alicorn (`sv_alicorn.lua`), THE ESCORT (`sv_escort.lua`).
`grep -rn '"fishing"' mod/ tools/` shows every place one is wired in.

## 0. Before any code
- Branch from `dev` (`feature/<special>`), worktree per branch.
- A plan in `docs/design/<SPECIAL>_PLAN.md` (git-ignored, never cited): what the player sees, phases, units, weapons,
  win / lose, co-op behaviour, solo vs co-op scaling. Propose it to her; she decides the design.
- docs/design/MISSION_REFERENCE.md: the stock mission that already does it. Copy its event nodes.
- Asset limits: stock files only, except her named exceptions (docs/rules/sources_and_toolchain.md). Never AC7 voice lines but the Tanacorn crew's.

## 1. Build side (Python, `tools/`)
- Events: a builder in the right `survival_events_*.py` part (remote events `RE_SV_<Name>...`, records copied from the
  stock mission). Hard rules 1-7, 17, 26, 34-36, 40, 54 are about exactly this.
- Units and NPC rows: `build_survival_units.py` / `_world.py` (port_unit, make_path with smooth=True for aircraft).
  Behaviour rows exist before the level loads (hard rule 20); bShowHUDBox / TargetMarkType for targets (32).
- A `check_<special>_build()` reading the saved packages back, as `check_fishing_build`.
- Import the main module (`survival_events` / `build_survival`), never a part.

## 2. Runtime side (Lua, `Scripts/`)
- A new part `sv_<special>.lua`, added to main.lua's MODULES. Globals only for what other parts call.
- Config in `sv_config_specials.lua` / `sv_config_arc.lua` (`CFG.specials.<key> = { enabled = true, name = ..., ... }`),
  its ini section alias in `sv_config_ini.lua`, rotation / schedule in `CFG.specials`.
- Every spoken or shown line goes in `config/subtitles.ini` (`python -I tools/subtitles.py merge`), not only Lua.
- Hook into the rounds (`sv_rounds.lua` start / units, `sv_spawn.lua`), its tick in `sv_main.lua` under `timed(...)`.
- Kills through `finishUnpaid` with health read back (63); objects kept between ticks checked by name (59);
  nothing read as a game effect while `gamePaused()` (60); events that matter re-checked after the STORE (64).
- Every part that can kill the player must respect SECOND CHANCE and co-op's DOWN floor (a direct kill event
  bypasses MinHealth).
- Test keys: `testKey(...)` inside `-- TEST ONLY BEGIN/END`; anything she wants dev-only in DEV ONLY blocks.

## 3. Co-op and the leaderboard
- The host runs it; joiners get forwarded events. Each player's own effects fire on each game. New messages get a
  row in `tools/checks/coop_guard_test.lua` with hostile values.
- Settings players can change are compared against CFG_DEFAULTS by the leaderboard (`LB.edited`): a setting that's
  only cosmetic or per-player goes in its free lists.
- Health and counts: think solo vs 4 players. The review of 2026-11-14 found specials tuned for co-op unfair solo.

## 4. Checks, docs, hand-over
- A Lua test (`tools/checks/<special>_test.lua` + `.sh`, the game stubbed as the others), `lua_check.py`,
  `build_all.sh`, `run_all.sh`.
- `docs/re/<SPECIAL>.md`: the design as built, the RE, its log lines, a test checklist for her run.
- Release exclusions: if it's dev-only or uses something excluded (Distant Thunder, the Tanacorn), make sure
  `strip_test_only.py` / `dev_only.py` cut it and `zip_leak_test` covers it.
- Then the survival-build skill for the build.
