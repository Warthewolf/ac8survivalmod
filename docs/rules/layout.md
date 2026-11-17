# Source layout and subtitles

Moved verbatim from AGENTS.md (2026-11-14): how the Lua, native and Python sources are split, and the subtitles file.

## Runtime layout (Lua parts from 0.66.0; families and the native parts from 2026-11-07)
- `Scripts/main.lua` is only the controller: it holds VERSION and runs the parts `Scripts/sv_*.lua` in its MODULES
  order (tools/lua_split.py made them from the old 7.6k-line main.lua, 2026-10-24: friend's advice "split the runtime
  into modules with a smaller central controller"; confirmed in game the same day, 0.66.0: a full
  VALKA round ran). Edit the parts, not main.lua. "main.lua" in older notes and hard
  rules means the runtime as a whole; find a function with grep over Scripts/*.lua.
- All parts run in this mod's one Lua state, in order: a name another part uses is a global (no `local`), a part's
  own helpers stay local. A new top-level function another part calls: drop its `local`. Order matters only for code
  that runs at load (top-level statements), as it did in one file.
- Hard rule 23's 200-local limit now counts per part (lua_check prints each part's count).
- Packaging strips test-only code and picks the edition across every part (tools/strip_test_only.py,
  tools/edition.py over Scripts/*.lua).
- No source file over 2,000 lines (a contributor, 2026-11-07: "not maintainable for human or AI";
  tools/checks/size_check.py fails build_all.sh on one). tools/lua_split_part.py split sv_coop.lua (+ _joiner,
  _planes, _sync, _migration), sv_config.lua (+ _specials: CFG.specials up to the Alicorn's as `CFG.<key> = {...}`
  statements; + _arc: CFG.specials from GONE FISHIN' on, CFG.sky / music / hud, as `CFG.specials.<key> = ...` and
  `CFG.<key> = {...}`; + _subs; + _ini: CFG_DEFAULTS, survival.ini, TIER / ROLE / ACE / GLS), sv_escort.lua (+ _carriers,
  2026-11-11) and sv_anomalies.lua (+ _valka; + _dev, the test-only lightning Anomaly, only its header left in a
  release). A part's family is the part and the MODULES
  entries right after it named <part>_<topic>. Tools that read or patch a part's text go through tools/lua_parts.py,
  the Lua tests through tools/checks/parts.lua (PARTS.load / read / dofile; each source edit applied in the piece that
  holds it). A local one piece uses from another is a global (check no other part has that name). sv_coop's M stays
  local, handed on as COOP.M (`local M = COOP.M` atop each later piece), because sv_flights' music state is the global
  M. To split again: a PLANS entry in lua_split_part.py, the analysis first, every TEST ONLY / ONLINE ONLY block whole
  in one piece.
- The native runtime (2026-11-07, runtime 0.32.24, no code change): runtime/build.sh still compiles survival_rt.c alone
  as ONE translation unit, but the files over 2,000 lines were cut at section boundaries into parts #included in place,
  so statics and code order are unchanged (the split built the same main.dll but for its link timestamp, and the same
  map). survival_rt.c is the spine: helpers, log, crumbs, patching, menu handlers, the Lua bridge's argument helpers,
  RegisterLua's table (lua_check.py reads it there), install and the mod object; RT_VERSION stays in it for build.sh and
  the package scripts. In order it includes survival_rt_game.c (spawner, teardown gate, recycles, unit descs, ammo,
  music, remote events, the game's Lua), coop.c (+ coop_lua.c: co-op's Lua functions and the second player plane),
  flight.c (+ flight_coop2mp.c: the real planes and their weapons; + flight_guards.c: the game-bug guards and the STORE
  freeze) and survival_rt_lua.c (sound, the SV_* Lua functions, the leaderboard). Edit the part, never compile one on
  its own, and add an #include where the code belongs to keep a file under 2,000 lines.
- The Python generators (2026-11-07; output byte-identical to the single files: 67 packages, sv_menu_stock.lua,
  stdout, the importing checks): tools/survival_events.py keeps the shared names, the record helpers and Graph,
  build_events, write_records and the builders the Lua tests read as text (heavies, jammer, raid pings, Spaceport
  Assault, run-over); its parts survival_events_specials.py (LCAC, Ladons, Alicorn, Anomaly, AB.L..IN, VALKA, shuttle),
  _squads.py (review orders, ace moves, Wolf, director, tells, Wraith, allies, VOID WATCHER), _festival.py,
  _escort.py and _fleet.py (INVINCIBLE FLEET's ships, 2026-11-12) are imported at its end with `from <part> import *`,
  each starting with `from survival_events import *`.
  tools/build_survival.py keeps the folders and package helpers, shop rows, menu pages, NPC rows and table, behaviour
  scripts, read-back checks, main and every function reading STOCK / OUT / ROOT / MENU_STOCK* / AI_SRC
  (menu_pages_test.py sets them on build_survival); its parts build_survival_rows.py, _units.py, _world.py and _fleet.py
  work the same way (run as a script it registers itself as build_survival first). survival_events.X / build_survival.X
  still name everything: import the main module, never a part (a guard asserts it). A part's functions see the main
  module's names above the part's import, and earlier parts' names only (an earlier part calls a later one's through
  the main module: `import build_survival` in the function, as build_wd_global calls fleet_units). The Lua tests grep the two main modules' text
  (coop_fire, coop_revive, defences, escort, heavy, roles, spaceport, spweapons), so their anchors stay there.

## Subtitles file (0.74.24)
Every subtitle line ("SPEAKER|text" in CFG.specials.*) and the speaker names live in `config/subtitles.ini`, the file the
user and her friends edit (user, 2026-11-08: "I want my friend to be able to edit all these subtitles easily").
Scripts/sv_config_subs.lua reads it over CFG's own lines before CFG_DEFAULTS is taken (no leaderboard or co-op difference;
not in the build hash) and changes only subtitle lines and the speaker names. The repo's file is what ships and wins over
the Lua: change a shipped line in the file, not in sv_config_specials.lua / sv_config_arc.lua. A new list of lines in Lua:
`python -I tools/subtitles.py merge`. The user's or a friend's edited install: `python -I tools/subtitles.py pull`; run
`diff` before installing a build over her install, or her edits are lost. build_all.sh runs `tools/subtitles.py check`;
tools/checks/subs_test.sh tests the part. The file is made from a release's copy of the parts (no test-only lines).

## Build lines and git history notes

Moved verbatim from AGENTS.md (2026-11-14). The git flow itself is now AGENTS.md sections 2 and 6.

## Build history and feature notes
Every build's notes are in HISTORY.md, oldest first: the economy review (0.70), the enemy behaviour layer (0.72),
COOP2MP's T1-T4 and every build since, through the newest. It isn't loaded into sessions (it was most of this file's
~190 KB): grep it for a version, a feature or a log line, and read only the entry you need. Each feature's design,
reverse engineering, log lines and test checklist are in docs/re/*.md (COOP.md, COOP2MP.md, BEHAVIOUR_DIRECTOR.md,
ESCORT.md, FISHING.md, DECOY.md, SPACEPORT_ASSAULT.md, ZFA44.md, THUNDER.md, VALKA.md, ...).
- (Git) From 2026-11-09 `dev` is the working branch and every task gets its own branch from it ("How to work", step 1);
  `main` takes `dev` when the user says a build is good. The 2026-11-08 cleanup merged the old branches or kept them as
  `archive/*` tags. COOP2MP is the build line's name (COOP_TAG, BUILD_NAME), no longer a branch.
- COOP2MP is the working main since 2026-10-30: the other players fly as real player planes (ALivePlayerPlane fed from
  their stream, their weapons replayed from their own plane), the AI stand-ins only as a fallback. VERSION 0.7x.y with
  COOP_TAG -coop2mp.N (tools/coop_edition.py); friends' zips: BUILD_NAME=COOP2MP COOP=1 sh tools/package_release.sh online
  <version> (ZFA=1, SONG=1 as the build has them); the user's own install: VALKA=1 ZFA=1 sh tools/package_dev.sh <version>.
- The enemy behaviour layer: fighter roles, the squad director, tells, intensity, learning, boss phases, late rounds
  (docs/re/BEHAVIOUR_DIRECTOR.md); each mechanism has its own `enabled` in survival.ini.
