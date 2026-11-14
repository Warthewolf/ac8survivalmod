# The add-on framework: notes for whoever maintains Survival

For the agents (Codex, Claude Code) and people who change Survival itself. Add-on authors read `docs/ADDONS.md`; the
loader and guard internals are in `docs/re/PLUGINS.md`. This page is the contract between Survival and its add-ons:
what Survival must keep so that an update doesn't silently break every add-on.

## What it is
- `Scripts/sv_plugins.lua` and its pieces `sv_plugins_api.lua` (the `SVP` calls) and `sv_plugins_env.lua` (each
  add-on's environment and the loader), one family split by `tools/lua_split_part.py` (PLANS `sv_plugins`; AGENTS.md
  "Runtime layout"; tools read it through `tools/lua_parts.py`, the Lua tests through `tools/checks/parts.lua`). At
  Survival's first tick it loads every add-on folder in
  `Mods/AC8SurvivalAddons/` (each one's `.lua` files in name order), inside Survival's own Lua state but each add-on
  in an environment of its own (an allow-list: `docs/ADDONS.md`, "Your add-on's environment"), and gives each the
  `SVP` API (special rounds, targets and pay, callouts, music and HUD hand-off). With no `AC8SurvivalAddons` folder it
  doesn't even look (one `io.open`), and Survival plays exactly as before.
- Line 2 of `sv_plugins.lua` is `-- add-on API <major>.<minor>` (now `2.0`). Native mods read it before Lua runs.
  Keep that form on line 2.
- Survival's zip has no `AC8SurvivalAddons` folder; an add-on's installer makes it (beside Survival's own folder, so
  an update that deletes Survival's folder keeps the add-ons). It must never look like a UE4SS mod (no
  `Scripts\main.lua`, no `enabled.txt`, no `mods.txt` line), or UE4SS runs it by itself outside the framework; the
  loader says so in the log. An add-on's assets live in its own IoStore container, never in Survival's.
- Tests: `tools/checks/plugins_test.lua` (+ `.sh`; `tools/checks/run_all.sh` runs it with every other suite), the
  example add-on `examples/addons/target_practice/`.

## The hooks in Survival's own files (keep them when you edit these files)
| file | hook | why |
|---|---|---|
| `main.lua` | `"sv_plugins"` and its pieces (`"sv_plugins_api"`, `"sv_plugins_env"`) are the LAST entries of `MODULES`, in that order | it needs every other part loaded first (SPC, CFG, TIER, LB, HUD...) |
| `sv_main.lua` `tickJob()` | `if PLUGINS and PLUGINS.tick then timed("plugins", PLUGINS.tick) end`, after `probeTickB` | loads the add-ons at the first tick, then runs their `SVP.every` jobs and events on Survival's 250 ms game-thread tick, in a pcall, timed in the run's perf line |
| `sv_main.lua` `planeSweep()` | `if up and PLUGINS.owned(p)` BEFORE the `elseif up` branch | an add-on's live target is left alone entirely: no tier (PilotRank), no manoeuvres (cobra / kulbit), no spike, no late, no hunt, no stats. Its exclusions by unit name don't reach an add-on's units, which have no unit name of Survival's |
| `sv_main.lua` `planeSweep()` | the `PLUGINS.owns(p)` branch BEFORE the `elseif dead` branch | an add-on's target (the API pays it) or retired unit (nobody's) seen down: no kill counted, nothing paid here. A mark is honoured once, only with the plane's name, only in the run it was made |
| `sv_stats.lua` `STATS.tailTick()` | `PLUGINS.owned(p)` first in its planes loop | the tail watch never watches an add-on's target (an open episode on one is dropped) |
| `sv_leaderboard.lua` `LB.edited()` | lists `"plugin <name>"` for each add-on found (`PLUGINS.loaded`, filled before any add-on runs; no add-on can reach it) | a run with any add-on found, loaded or not, is never ranked |

If one of these moves in a refactor, move the hook with it. `plugins_test` checks that all of them are present (and in
those places) and goes red if one goes missing. The squad director needs no hook: poolPlane takes only ERA_Unit_NN
units, and an add-on's aren't.

## Survival internals the framework uses (renaming or changing one breaks add-ons)
`sv_plugins.lua` (with its pieces) is the only adapter: when you change something in this list, update it in the same
change and run `plugins_test`. Add-ons themselves only call `SVP` (and the allow-list): none of these is in their
environment.
- **Specials:** `SPC.kinds[kind]` and how Survival reads an entry's fields (`spawn`, `sub`, `alone`, `disguise`,
  `aircraft` through `SPC.kindValue`, `budget(b)`, `ready(round, forced)`, `tick`, `busy`, `over`, `row(s, t)`, `hold`:
  `FIELDS` in `sv_plugins.lua` checks each one's type and answer; a field Survival starts reading needs a line
  there), `CFG.specials[kind]` (an add-on can't take a name already there), `CFG.specials.rotation`,
  `CFG_DEFAULTS.specials`.
- **Round and pay:** `D.round`, `D.now`, `TIER.pay`, `TIER.specialX`, `TIER.index`, `addCredits(n, why)` (gets whole
  numbers only, 1..1,000,000 a call), `LB.stat`.
- **HUD and voice:** `HUD.hold(on, why)` (sv_hud.lua; `SVP.hud` holds it as `"add-on <name>"`), `hudCallout`,
  `SUB.say(who, text, secs)`.
- **Music:** the native `SV_PlayBGM("AKE_System_BGM_Mute_On" / "..._Off")` and `SND.unmuteDue / unmuteAt /
  unmuteTries` (the give-back after an add-on's own track).
- **Player and co-op:** `DOWN.me()`, `playerLocation`, `survivalPC` (your plane: `SVP.playerPlane`, `SVP.hurt`,
  `SVP.pc`), `gamePaused` (`SVP.paused`), `COOP.open`, `COOP.client()`.
- **Natives:** `SV_Intercept` (`SVP.intercept`: ALiveWeaponBase::Intercepted, runtime/laser.c), and
  `gameInstance()` with its `ReferencedObjects` (`SVP.pin`, as sv_core.lua's own pins: a let-go slot holds a class
  default object).
- **The walks' hold:** `walkHold()` (sv_core.lua) and `levelGoing()`: the add-ons' `FindFirstOf` / `FindAllOf` /
  `StaticFindObject` / `NotifyOnNewObject`, and `SVP.widget` (UE4SS's `StaticConstructObject`, widget classes in a
  widget tree only; also refused with co-op open), refuse while either holds. The add-ons' `FindFirstOf` / `FindAllOf` /
  `StaticFindObject` and the API's own finds (`PLUGINS.find`) also wait on `walkBusy()` (the runtime's `SV_GcBusy`):
  if a new runtime loses `SV_GcBusy`, those walks are no longer held during a purge.
- **UMG:** `SVP.widget` takes UMG's concrete widget classes by name (`WIDGET_OK`) or a widget blueprint's (its parents
  reaching `Class /Script/UMG.UserWidget`), in an outer whose class reaches `Class /Script/UMG.WidgetTree` (or a widget).
  If UMG's classes are renamed, change it with them.
- **Music:** sv_sound.lua's song end asks `PLUGINS.bgmHeld()` and leaves the game's music muted while an add-on's
  track holds it; `LEVEL_DROPS["add-ons"]` (sv_core.lua `levelDrop`) flags a level change no tick saw going.
- **The stock sure kill:** `SV_Event("RE_SV_DecoyKill")`, THE DECOY's event in Survival's world data
  (`SVP.killPlayer`). If that event is renamed or removed, change `SVP.killPlayer` with it.
- **Objects:** `loadObject` (Survival's loader: UE4SS `LoadAsset` can't load a mod's new packages), `addrOf`,
  `liveAddr`, `liveObj`, `valid`, `levelGoing`, `log`, `crumb`, and `finishUnpaid` (`SVP.retire`, hard rule 63). An
  actor handle the API is given or spawns is kept with its object's full name (hard rule 59). The class
  `/Script/Live.LiveGameObject` (`ALiveAIGameObject`'s parent) tells a game object (`SVP.despawn` and the switch-off
  clean-up end one by its own death).
- **The STORE's gate:** `STOREQ.gate(now)` (sv_rounds_store.lua), asked with the rounds' clock `D.now` as Survival
  does: `SVP.killPlayer` fires nothing while it's shut (hard rule 64).
- **Places:** `AIRFIELD` (`SVP.runway()`), and a COPY of the spaceport's shuttle pad in `sv_plugins.lua`
  (`SHUTTLE_PAD = { X = -1324937.0, Y = 59740.0, Z = 6343.0 }`, `SVP.pad()`): if the pad moves, change it there too.
- **Optional native:** `SV_HurtPlayer` (an add-on can `SVP.provide("hurtPlayer", fn)` when Survival's runtime lacks it;
  Survival's own wins when present).
- **Loading:** `SCRIPT_DIR`, then `io.open` on `..\\..\\AC8SurvivalAddons` (a folder answers EACCES, none ENOENT: no
  folder, no walk), UE4SS's `IterateGameDirectories()` to list it (fallback: `AC8SurvivalAddons\addons.txt`, a line
  `<name>\<file>.lua` each).
- **Settings:** the framework reads `config/survival.ini` itself (`SCRIPT_DIR .. "..\\config\\survival.ini"`) for an
  add-on kind's `[specials.<kind>]` section, after Survival's own config has loaded. If the file moves or its section
  syntax changes, update `iniOver` in `sv_plugins.lua`.

## Rules (each came from a crash or a broken run)
1. Add-on code runs only on Survival's game-thread tick. Never `LoopAsync`, `ExecuteInGameThread`,
   `ExecuteWithDelay` or `RegisterKeyBind` in the framework or an add-on: in Survival's one Lua state they crash the game.
   They aren't in an add-on's environment; keep them out.
2. Every add-on call, at load too, runs in a pcall with a count hook (`debug.sethook`): the first error, a stall (one
   call over 2 s is a logged hitch; three within 60 s is a stall), more than 6 s of the game thread within 30 s, or a
   call still running after 10 s switches that add-on off for the session: its round ends, its targets come off
   unpaid, what it spawned is taken off, Survival's music and HUD are given back. Survival carries on. Keep it that
   way: an add-on must never be able to take Survival down.
3. A Lua reference doesn't keep a game object alive, and UE4SS's `IsValid` can say yes on freed memory. A cached asset
   or audio component is reused only while it's live AND still has the same full name it had when cached (the GC frees
   it and the allocator can put a new object at the same address). Keep that check in `SVP.load` / `SVP.play2d`.
4. Anything the framework takes away (Survival's music, its HUD) is always given back: at the round's end, a round that
   didn't start, the run's end (with or without a round), the level going, the add-on switched off, and a 60 s cap for
   the HUD. An add-on's pins (`SVP.pin`, 64 at most) are let go at its switch-off, its run's end and the level going;
   its `NotifyOnNewObject` callbacks are dropped at its switch-off and at every level's teardown.
5. Touch no game object while `levelGoing()` is true (`runEnd` and `levelGoing` events can fire during teardown). The
   API's calls refuse then, and a round whose level goes gets only `abort("the level is going")`.
6. Native Lua function names (a C++ mod's) are 15 characters or fewer.
7. A `check`, `ready` or `spawn` that says no means Survival plays its normal round (or another special). An add-on
   never leaves a round half-started.
8. A game unit (an `ALiveGameObject`, `ALiveAIGameObject` among them) is never destroyed by hand, in the framework or an add-on: `K2_DestroyActor`
   leaves its entry in the game's unit list, null after the next garbage collection, and the next unit death anywhere
   reads null+0xf50 (AC8 crashed there, exe+0x7e0cb5a). `SVP.despawn` and the switch-off clean-up end a unit by its
   own death (finishUnpaid, unpaid), or leave it with a log line when the game won't let it die.
9. Survival gets only what it can use from an add-on: pay as a whole number (0..1,000,000), a kind's answers checked
   (`FIELDS`), a kind name that isn't one of Survival's settings.
10. An add-on reaches nothing of Survival's except through `SVP` and its environment's allow-list (`envFor` in
    `sv_plugins_env.lua`). Never add the `debug` library (getupvalue / setupvalue / getregistry reach Survival's locals and
    LB), a shared library table (each add-on gets copies of string / table / math / utf8), a getmetatable that answers
    for strings (the string metatable leads to the real string library), `collectgarbage` beyond `"count"`, or one of
    Survival's tables writable (`readOnly`). The framework itself still uses `debug.sethook` for its guard (rule 2).

## Versions
- `SVP.api = { major = 2, minor = 0 }`. Add a call: bump the minor. Change or remove one: bump the major.
- An add-on declares `def.api = "2.0"`. Survival serves its own major and a minor up to its own; anything else, and
  an add-on with no `def.api`, is refused with one log line.
- `def.requires = { "SV_Something", ... }`: native functions it needs; one missing means not loaded, one line.
- Update `docs/ADDONS.md` and line 2 of `sv_plugins.lua` with every API change.

## Co-op
- 2.0 is single player. While `COOP.open` is true (as soon as the host opens co-op, before anyone joins, and on every
  joiner) an add-on's round never comes (its `ready` and its `spawn` refuse), none of its jobs run, and every API call
  that changes the game refuses. `plugins_test` checks it. A friend on plain Survival sees plain Survival.
- Co-op for add-ons comes later, as its own change.

## Leaderboard
A run with any add-on found in `AC8SurvivalAddons` is unranked (`LB.edited`). Don't change that without the
leaderboard's owner. The list is made before any add-on runs, and no add-on can reach it: an edited run is never sent.

## Before releasing a Survival update
1. `sh tools/checks/plugins_test.sh` (or `sh tools/checks/run_all.sh`, which runs it with every suite; `build_all.sh`
   runs the syntax and size checks but not this one).
2. If you touched anything in "Survival internals the framework uses": update `sv_plugins.lua`, and the docs if the
   API changed.
3. Optional but best: one round with the example add-on (`examples/addons/target_practice`, stock assets only) in
   game: its round comes, three targets pay, the next round comes.
4. No `AC8SurvivalAddons` folder in the zip, and `sv_plugins.lua` line 2 in its form.
