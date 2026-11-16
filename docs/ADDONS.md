# Add-on sorties for AC8 Survival Mode (add-on API 2.0)

An add-on adds a special round of its own to Survival: its units, its targets and pay, its callouts, radio and music.
It runs inside Survival's Lua state, in an environment of its own, through the API Survival gives it (`SVP`).
Survival needs nothing from the add-on to run: with no add-ons installed, or with one that can't run, Survival plays
as before.

The internals (the loader, the guard, the targets' watch) are in `docs/re/PLUGINS.md`. A complete small add-on is in
`examples/addons/target_practice/`.
For whoever maintains Survival itself: `docs/ADDONS_MAINTAINING.md` (the hooks in Survival's files, the internals
the framework uses, the rules).

## Install layout
```
Mods/AC8SurvivalAddons/<your_addon>/*.lua          the add-on's Lua: Survival runs every .lua directly in it, in name
                                                   order, all in the add-on's one environment
Mods/AC8SurvivalAddons/<your_addon>/natives.txt    the native functions it may call, if it has a native mod (below)
Mods/AC8SurvivalAddons/<your_addon>/<subfolder>/   its data files, if it has any (SVP.dir() .. "<subfolder>\\...")
Mods/<your C++ mod>/                               its native mod, if it needs one (optional)
<your IoStore container>                           its assets (load them with SVP.load); never in Survival's own
```
`Mods/AC8SurvivalAddons/` sits beside Survival's own folder, so an update that deletes Survival's folder keeps your
add-on. Survival ships no `AC8SurvivalAddons` folder: your add-on's installer makes it. With no such folder Survival
doesn't look for add-ons at all. Your folder's name: letters, digits, `_` and `-`, 40 at most, and not `Scripts` or
`dlls` (a UE4SS mod's own folders); one with another name is switched off, as is one with no `.lua` in it.

Survival lists the add-on folders with UE4SS's `IterateGameDirectories`. On a UE4SS without it, it reads
`Mods/AC8SurvivalAddons/addons.txt` instead, once, when the add-ons load (Survival's first tick): one line a file,
`<your_addon>\<file>.lua`, in the order they run (your installer writes it; your `natives.txt` is read from your folder
as usual). Blank lines and lines starting `#` or `;` are comments; any other line it can't use is left out with one
log line (`plugins: addons.txt: a line left out ...`).

**`AC8SurvivalAddons` must never look like a UE4SS mod:** no `Scripts/main.lua` and no `enabled.txt` directly in it,
and no `AC8SurvivalAddons` line in `Mods/mods.txt`. UE4SS runs any Mods folder that has those by itself, outside the
framework: your add-on's code would run twice, once with none of the protections below. Survival says so in its log
if it finds them (those three: UE4SS looks no deeper, so your own folder's files don't count).

Its settings come from `[specials.<kind>]` in Survival's `config/survival.ini`, over the defaults the add-on gives.

## The smallest add-on
```lua
SVP.register("practice", {                    -- the kind: letters, digits, _, 15 at most
    name = "Target practice", ver = "1.0",
    api = "2.0",                               -- the add-on API version it's written for
    cfg = { from_round = 2 },                  -- its settings' defaults: SVP.cfg("practice")
    kind = {
        sub = function() return "TARGET PRACTICE" end,
        spawn = function(now) --[[ spawn its units, SVP.target them ]] return true end,
        busy = function() return false end,     -- true holds the round
    },
})
```
A global your add-on sets is its own (its environment's), seen by all of its files and nothing else. Survival's
globals aren't there: use the API.

## Your add-on's environment
Each add-on runs in an environment of its own. What it sets stays in it; what it reads comes from it, else from this
list, and nothing else of Survival's is reachable (its globals, its settings tables, its leaderboard, the framework's
own tables):
- Lua: `assert error ipairs next pairs pcall xpcall select tonumber tostring type rawequal rawget rawlen rawset
  setmetatable print _VERSION`, and `_G` (your environment itself). `setmetatable` refuses a metatable with a `__gc`
  (an error): a finalizer runs at whatever garbage-collection step comes next, inside Survival's own code, outside
  the API's guard. `pcall` and `xpcall` don't catch the runaway limit's stop (a call still running 10 s after it
  began): it passes straight through them, and `xpcall`'s handler isn't called for it. Nor do the API's own calls
  catch it (a loop in a metamethod of yours that an SVP call reads). It's raised in your own code: when it comes due
  inside Survival's (an SVP call), that call is let finish first (5 s at most, then it's raised wherever it is), so
  what the call did is recorded and given back. A call that
  grows Lua's memory by 256 MB is stopped the same way (an allocating loop runs out of memory long before 10 s). A
  string pattern that backtracks (`("a-"):rep(12) .. "b"` on a long string) runs inside C, where nothing can stop it:
  keep patterns simple on text you didn't write. Your chunks
  are named for your add-on (`load`'s and `loadfile`'s name is put after `=<your folder>:`).
- `string`, `table`, `math`, `utf8`: copies of your own. Changing one (`string.format = nil`) changes yours only. No
  `string.dump` (`("").dump` still reaches it, through the strings' metatable Lua shares: harmless, since `load` takes
  text only), no `math.randomseed` (Survival's random sequence is its own).
- `getmetatable(t)` answers for tables only (`getmetatable("")` is nil: the string metatable leads to the real string
  library).
- `os.clock`, `os.time`, `os.date`, `os.difftime`. `io.open(path)` and `io.lines(path)` for reading only.
- `collectgarbage("count")`, nothing else of it.
- `load`, `loadfile`, `dofile`: text chunks only, run in your environment (unless you give `load` another table).
  `load` takes a string (a reader function runs in `load`'s own protected call, where the runaway limit can't reach).
- UE4SS: `FName`, `FText`, and `FindFirstOf`, `FindAllOf`, `StaticFindObject`, `NotifyOnNewObject`. The four refuse
  (nil, as a walk that found none; `NotifyOnNewObject` answers false) while the level is going and while Survival
  holds the game's object walks (a level loading). `StaticConstructObject` isn't there: a widget of your own is
  `SVP.widget`. `FindFirstOf`, `FindAllOf` and `StaticFindObject` also answer nil while the engine is freeing objects
  (a garbage collection's purge, a few frames at a time): UE4SS's `StaticFindObject` is a walk over every object too,
  and a walk then can read an object whose owner was just freed (a crash, not an error). Nil from them means "try
  again later", not "there are none"; keep what you found (checked live before each use) rather than finding it again
  every tick.
- `NotifyOnNewObject(class, fn)`: true once UE4SS has the class; false when it can't be asked (UE4SS refuses a class
  it can't find yet: your container's classes aren't loaded at the main menu, where add-ons load; one log line), and
  then nothing is kept: ask again later, at `SVP.on("runStart", ...)`. One callback an add-on a class: asking again
  replaces it. 64 classes in all, every add-on's together. The callback isn't called inside the game's construction
  of the object (UE4SS calls back on the thread that constructs it): the object is kept, and your callback gets it,
  once, at Survival's next tick, if it's still live and of that class, guarded like every other callback (an error or
  a stall switches the add-on off). Objects waiting at a tick that finds the walks held, or co-op open, are dropped;
  256 of a class wait a tick at most, the rest are dropped (said in the log). Ask for as narrow a class as you can: a
  class stays registered with UE4SS for the session, and a broad one (`Actor`, `Object`) queues every object of it.
  The callback is dropped when your add-on is switched off and at every level's teardown: ask again in the next level
  (`SVP.on("runStart", ...)`).
- `SVP`: your own copy of the API.
- Your native mod's functions: a C function whose name has a prefix of capitals and `_` (`MYADDON_Ready`), listed in
  your folder's `natives.txt` (one name a line, or a prefix ending `*`: `MYADDON_*`; `#` starts a comment) or in
  `def.requires`. Survival's own `SV_` functions aren't yours: the API calls them for you. A native is any C
  function of that name in Survival's Lua state, so pick a prefix of your own: two add-ons naming the same one share it.

Not there: the `debug` library, `coroutine` (a loop in one would escape the runaway limit), `require`, `os.execute`,
`os.remove`, `os.rename`, `os.exit`, `io.popen`, writing files, `LoopAsync`, `ExecuteInGameThread`,
`ExecuteWithDelay`, `ExecuteAsync`, `RegisterKeyBind`, `RegisterHook`, `IterateGameDirectories`. The tables Survival
hands your callbacks (a round's record `s`, your settings) are read-only: a write raises, which switches the add-on
off. What the API keeps of your tables is copied when you hand it over, raw (`rawget`, `next`: a field given through a
metatable isn't read, and that's said once in the log), as plain values: `SVP.register`'s `def` and `def.kind`, each
read once, `SVP.target`'s `opts` (`pay`, `flat`, `class`, `label`, `onDown`), `SVP.fx`'s `rot` and `floats`, and
`def.cfg`: numbers, strings, booleans and flat lists of them (anything else in it is left out, with one log line). A
change to the table afterwards changes nothing, and no metamethod of yours runs outside your callbacks.

Every actor or object you hand the API (`SVP.target`, `move`, `despawn`, `retire`, `hurt` and its causer, `pin`,
`intercept`, `liveObj`, `widget`'s class and outer, `spawn`'s class) is a UE4SS object: what `SVP.spawn`, `FindAllOf`, a `NotifyOnNewObject` callback or a property
gave you. A Lua table of your own is refused (false, nil) and never read: its methods would be your code, run by the
API outside your callbacks.

## Versions
- `SVP.api` = `{ major = 2, minor = 0 }`; `SVP.version` = 2 (the major). A minor version only adds calls; a major one
  may change them.
- `def.api = "2.0"`: the version your add-on is written for (a string or a number; each part six digits at most).
  Survival serves an add-on of its own major and a minor up to its own; anything else is refused with one log line:
  `plugin <name>: not loaded: it needs add-on API 3.0; this Survival has 2.0`. `def.api` is needed: an add-on with
  none is refused the same way.
- For a native mod, before Lua runs: line 2 of `Mods/AC8SurvivalMode/Scripts/sv_plugins.lua` is
  `-- add-on API <major>.<minor>` (no such line, or no file: no add-on framework).
- `def.requires = { "SV_Something", ... }`: native functions it needs (Survival's runtime's, or its own native mod's).
  One missing: not loaded, one line. Your own native mod's names listed there are also in your environment.
- A refused add-on, or one that errors while it loads, is switched off: none of its jobs (`SVP.every`, `SVP.on`,
  `SVP.going`, `SVP.provide`) run.

## A round's life
Every callback is optional except `spawn`. Survival calls them on its game thread. `def.kind` may hold only the fields
below (any other is left out, with one log line); a field of the wrong type refuses the kind at `register`, and an
answer Survival can't use is replaced by Survival's own value before Survival reads it.
| field | when, and what to return |
|---|---|
| `def.check()` | before every `ready`: the add-on's own readiness (its native mod up, its data found). `true`, or `false, why`: its round is skipped (Survival picks another special or plays a normal round), said once a run |
| `ready(round, forced)` | may the round come now (`forced`: a test key). `round` is always a number: the round Survival is picking, or, when its specials bag fills, the round in play (0 between runs). Survival keeps your kind out before its `from_round` itself (your `cfg`'s `from_round`, as its own specials): don't check that here, or your kind is left out of the bag until it empties. Answer no for what else rules it out now (once a run: the bag leaves it out then, as Survival's own) |
| `spawn(now)` | the round starts: spawn, target, call out. `true` = started; anything else = Survival plays a normal round instead (and what you took for the round, Survival's music and HUD, its targets, is given back) |
| `tick(now, s)` | every tick of your round, from its `spawn` to its `over` (Survival's own tick of a special starts at the round's start, before the spawn: the API holds yours till then) |
| `busy(s)` | `true` holds the round open (its targets aren't done) |
| `over(now, s)` | the round is over (`s`: its record, as `tick` gets it; nil when its run ended under it and there's no `abort`): take your actors off. Never called while the level is going (then only `abort`) |
| `abort(why)` | the run ended under the round (a new run: a restart after every player is down; the level left): the kind whose round it was, only. The RUN OVER screen itself leaves the run in place, and your round ticks on under it as Survival's own do. When `why` is `"the level is going"`, touch no game object |
| `sub` | the callout's second line: a function answering a string, or a string (a key of Survival's text table) |
| `alone`, `disguise` | `true` / `false`, or a function answering one (`alone`: no Survival fighters with it) |
| `aircraft` | a count (0 or more), or a function answering one: the round's aircraft it takes. Anything else: 0 |
| `budget(b)` | the fighters it wants from the round's budget `b`. Not a count: `b` |
| `row(s, t)` | the HUD's round row: a string, or nil |
| `hold(now, s)` | as Survival's own specials |
| `def.rotation = true` | joins the specials' rotation, unless the player wrote their own `rotation` line |

Survival's moments, for any add-on, as Survival's tick sees them: `SVP.on(event, fn)` with `"runStart"` (the first tick
a run exists), `"roundStart"` (round: the first tick the round number is new), `"roundEnd"` (round: the first tick it
has changed again, or the run is gone), `"runEnd"` (its last round: the first tick the run is gone or replaced), and
`"levelGoing"`. On the tick the level starts being torn down they come in this order: `levelGoing` (and
`SVP.going`), your round's `abort("the level is going")`, then `roundEnd` and `runEnd`. Touch no game object in any of
them: every API call that would refuses then. Survival has two signs of a teardown: another level loading (certain)
and the level's unit spawner gone a second (which can let go again, a pause-menu restart). `levelGoing` and
`SVP.going` come at the first sign of either; your round's abort, and what the API lets go of the level (its targets,
marks, pins, `NotifyOnNewObject` callbacks, what you spawned, the level's handles), only once it's certain.
`SVP.every(fn)`: `fn(now)` every Survival tick (about 250 ms), also between rounds and at the main menu before the
first run (not from a quit until the next Survival level loads: the level is going all that time). 64 jobs an
add-on of each of `SVP.every`, `SVP.on` and `SVP.going` (one more: false, one log line); a job added during a tick
first runs on the next.

## The API
| call | what |
|---|---|
| `SVP.target(actor, opts)` | an id; the actor is watched each tick of the round: gone, its address another object's now, or no health = down, paid `opts.pay` (x the round's tier, unless `opts.flat`), a ground kill (`opts.class = "air"`: air), `opts.onDown(id, why)`. Survival leaves it alone while it's your target: not counted or paid by Survival, and none of Survival's enemy settings on it (skill tier / PilotRank, post-stall manoeuvres, spikes, the tail watch). Never a player's plane (nil). Only in your own round, from its `spawn` to its `over` / `abort` (the round's tick is what watches them): anywhere else (`SVP.every`, `SVP.on`, another round) nil, said once. 256 targets an add-on at most (one more: nil, said once). Every target is dropped, unpaid, at its run's end and when the level goes |
| `SVP.untarget(id)` / `SVP.kill(id, why)` / `SVP.alive(id)` | off the watch, unpaid / down now, paid / still up. Your own targets only (another add-on's id: nothing, false). A target taken off while it's still up (untarget, your round's end, your add-on switched off) is Survival's again: its later death is counted and paid as Survival's own |
| `SVP.pay(n, why)` | credits. Pay (here and a target's) is rounded to a whole number and kept to 0..1,000,000; a value that isn't a finite number pays nothing |
| `SVP.load(path)` | an object of your container (Survival's own loader: UE4SS `LoadAsset` can't load a mod's new packages) |
| `SVP.spawn(cls, at, yaw)` / `SVP.move(a, at, yaw)` / `SVP.despawn(a)` | an actor (a class or its path) at `at` (cm), turned `yaw` degrees / teleported / taken off: a game object (an `ALiveGameObject`) by its own death, unpaid, anything else destroyed (a target: off, unpaid). What you spawn is taken off the same way if your add-on is switched off (at Survival's next tick). Not an actor another add-on spawned or targeted first (known by its address and full name, whichever handle you have of it), never a player's plane (yours, or any of the player planes' class) |
| `SVP.retire(a)` | the game kills your unit through its damage path; nothing counted or paid (a target: off, unpaid, once its death is dealt; a unit the game won't let die stays your target, and the call answers false). A unit already down when you call it keeps its kill: Survival's to count, or your target's pay |
| `SVP.hurt(a, n, causer)` | `n` damage (MaxHealth units). `causer` nil = no one's kill: counted and paid to no one (a target it kills: off, unpaid) |
| `SVP.killPlayer(why)` | the player's plane destroyed (Survival's own sure kill) |
| `SVP.playerPlane()` | `{ a, X, Y, Z, VX, VY, VZ, health, down }` or nil |
| `SVP.players()` | `{ { slot, X, Y, Z } }` |
| `SVP.pad()` / `SVP.runway()` | the spaceport's shuttle pad / Comona Airport's runway, cm |
| `SVP.clock()` / `SVP.round()` / `SVP.run()` | the rounds' clock / the round / a token of the run in progress |
| `SVP.levelGoing()` | the level is being torn down: touch nothing |
| `SVP.callout(text, sub)` / `SVP.say(who, text, secs)` / `SVP.log(msg)` | the round callout / the subtitle strip / Survival's log, your name first |
| `SVP.play2d(path, vol)` / `SVP.hold2d(path)` | a 2D sound for you alone (ok, length, its audio component) / one held ready, played with no lookup |
| `SVP.sound(path, at)` / `SVP.fx(path, at, scale, rot, floats)` | a Wwise event at a spot / a Niagara system (its component) |

These four, and `SVP.load`, start or hand out nothing while the engine is freeing objects (a garbage collection's
purge, as the finds above): false or nil, "try again". An asset you play is kept by the API only between plays in Lua,
which the engine doesn't see; one nothing plays can be condemned by a collection and still be found during the purge,
and a sound started on it then plays a freed object (a crash). An asset found or loaded that the collection has
condemned is never handed out either (nil, "condemned by the GC: try again"; logged once a path). Try again on the next
tick.

| `SVP.bgm(on)` | Survival's music off (`false`) for your own track, or back (`true`). Only in a run (false at the main menu: nothing there would give it back). One mute for every add-on: it comes back when the last one holding it gives it back, never under Survival's own song. The API gives it back by itself at your round's end, your run's end, the level going, your add-on switched off, or a round that didn't start |
| `SVP.hud(on, why)` | Survival's own HUD (its panel, the callout banner, the subtitle strip) off (`false`) for your cutscene, or back (`true`), only in a run; `why` goes in the log. It's Survival's `HUD.hold`: callouts and subtitle lines said meanwhile wait and show after. The API gives it back by itself as `SVP.bgm` does, and 60 s after you first hid it (hiding it again doesn't extend that); after that give-back it refuses to hide it again for 60 s (false, said once). One hold an add-on, named by its folder. The game's own HUD isn't touched (a stock cutscene hides it itself) |
| `SVP.widget(class, outer, name)` | a UMG widget of your own (a HUD line), made in `outer` (a live `WidgetTree` or widget you found): `class` one of UMG's concrete widgets (`TextBlock`, `RichTextBlock`, `Image`, `Border`, `CanvasPanel`, `Overlay`, `HorizontalBox`, `VerticalBox`, `SizeBox`, `ScaleBox`, `Spacer`, `ProgressBar`, `GridPanel`, `UniformGridPanel`, `WrapBox`: `StaticFindObject("/Script/UMG.TextBlock")`) or a widget blueprint's class, `name` letters, digits and `_` (made unique: `SVA_<folder>_<name>_<n>`, so asking again never replaces a widget). Add it to the tree yourself; the tree's teardown frees it. nil while the level is going, the walks are held or co-op is open, and past 256 of yours in a level |
| `SVP.liveObj(o)` | `o` is still the engine's live object (false for anything that isn't a UE4SS object). Ask it before using anything kept between ticks |
| `SVP.cfg(kind)` | the settings of one of your kinds (your first if `kind` is nil): `def.cfg` with `[specials.<kind>]` from survival.ini over it. Read-only; nil for a kind that isn't yours |
| `SVP.pc()` / `SVP.paused()` | your player controller (nil before there is one, or while the level is going) / the game is paused |
| `SVP.dir()` | your add-on's folder (ends with `\`): the place for your data files |
| `SVP.intercept(m)` | shoots down the missile `m` the game's own way: Survival's runtime calls `ALiveWeaponBase::Intercepted`, the kill an interceptor makes (AC7's anti-missile laser's: the missile is destroyed in the air, no hit and no explosion on its target). `1` shot down, `0` not (it isn't in flight: down already, or back in its pool), nil when it can't be asked (`m` not a live `LiveWeaponBase`, no `SV_Intercept` in this Survival's runtime, the level going, co-op open, your add-on switched off). Nothing is paid or counted for it |
| `SVP.pin(o, why)` | keeps the object `o` loaded (an asset you need between ticks: held in the GameInstance's `ReferencedObjects`, Survival's own way) until your add-on is switched off, your run ends or the level goes, whichever comes first; then the API lets every pin go itself. 64 pins an add-on at most (one more: false, one log line). `true` pinned (or already), `false` not An object of the level (an actor, a component, a widget: kept through a level load it would keep the old level) is refused: assets only |
| `SVP.provide(name, fn)` | give the API what your native mod has: `"hurtPlayer"` = `fn(playerAddress, -healthPoints, causerAddress)` -> 1 (the player's damage through the game's own health path). Survival's own function wins when it has one |
| `SVP.isHost()` / `SVP.inCoop()` | co-op state (2.0 is single player: see Co-op) |
| `SVP.net` | co-op's add-on channel: not in 2.0 (a stub: `SVP.net.ready` false) |

Every call that touches the game (spawn, move, despawn, hurt, retire, target, kill, pay, killPlayer, bgm, hud, sound,
fx, play2d, hold2d, callout, say, load, playerPlane, players, pc, intercept, pin) refuses while the level is going,
and the ones that change it while co-op is open or once your add-on is switched off.

## Rules (each one learned from a crash)
- `LoopAsync`, `ExecuteInGameThread`, `ExecuteWithDelay` and `RegisterKeyBind` aren't in your environment: they run Lua
  off the game thread in Survival's one Lua state, which crashes the game. Use `SVP.every`.
- A Lua reference doesn't keep a game object alive. An actor, asset or component you keep between ticks can be freed
  by the game's garbage collection, and UE4SS's `IsValid` can still say yes on freed memory. `SVP.liveObj(o)` says
  whether the address is a live object, but not whether it's still YOURS: the allocator can put a new object where a
  freed one was. So keep the path, not the asset: `SVP.load(path)` / `SVP.play2d(path)` each time (they're cached and
  check both, cheaply). For an actor you spawned, check `SVP.liveObj` and that it's the one you made (its full name).
- Touch no game object while `SVP.levelGoing()` is true.
- Never destroy a game unit (an `ALiveAIGameObject`, or any `ALiveGameObject`) yourself (`K2_DestroyActor`): its
  entry stays in the game's unit list, null after the next garbage collection, and the next unit death anywhere crashes
  AC8 (exe+0x7e0cb5a). End it by its own death: `SVP.retire`, or `SVP.despawn`, which does that for one.
- Survival's hard rules for targets and kills (its AGENTS.md), which the API keeps for you:
  - 59: a freed object's address is reused, and the address check passes for whatever lives there now. Every actor
    you hand the API (or get from `SVP.spawn`) is recorded with its full name and its level, by that handle; it's
    itself only while its address holds that name, read again in each of your calls that changes it (once a call: the
    engine frees memory only between Lua calls): else a target is taken as gone, and `SVP.move` / `despawn` / `hurt` /
    `retire` / `target` do nothing to it. A handle you kept from an earlier level is refused for good, even if an
    object of the same name now lives at its address: get a new one. A new handle for the object now at that address
    is a record of its own. Do the same for any actor you keep yourself.
  - 63: `GameplayStatics.ApplyDamage` does nothing to AC8's objects. Damage with `SVP.hurt` (ModifyHealth, health read
    back) and finish your own units with `SVP.retire` (Survival's `finishUnpaid`).
  - 64: a remote event fired while the host's landing minigames run (the STORE) runs none of its records, though
    `SV_Event` answers 1. `SVP.killPlayer` refuses then. If your add-on fires events itself, check their effect.
- Native Lua function names (a C++ mod's) are 15 characters or fewer.
- Keep a callback short. A tick over 100 ms three times running is logged; a call over 2 s is logged as a hitch, and
  three of them within 60 s switch the add-on off (a stall); more than 6 s of the game thread within 30 s switches it
  off (its time budget); a call still running 10 s after it began is stopped (a runaway loop) and switches it off.
  The stop passes straight through your own `pcall` / `xpcall`. When the loop is in another add-on's callback your
  call ran (its `hurtPlayer` provider, say), that add-on is the one switched off: your call answers as if it had
  failed, and your add-on stays on. (A loop inside a C function can't be stopped that way.)

## What Survival does to keep itself safe
- Add-ons load at Survival's first tick, after every part of Survival and its tick loop are up. Every add-on found is
  listed first (the leaderboard reads that list); then each one's files load, in its own environment, in a pcall
  with the runaway limit: a file that can't be read or doesn't compile, an error at load, a refusal (`api`,
  `requires`), a runaway loop or a switch-off during its load takes its kinds off again (the rotation's too) and
  switches it off; its later files don't run.
- An add-on can't reach Survival's globals, its settings tables, the leaderboard or the framework's own tables (its
  environment, above). It isn't a sandbox for the game, though: `FindAllOf` and `StaticFindObject` hand out any of the
  game's objects, Survival's own widgets among them, and an add-on can write their properties. The guard is there to
  catch an add-on's bugs (errors, stalls, loops), not to stop an add-on that means harm: install only what you trust.
- Every callback runs guarded: the first error, a stall, the time budget or a runaway loop switches the add-on off for
  the session. Its round ends as soon as Survival's checks allow (`busy` false), its targets come off the watch
  unpaid (Survival's again), its pins and `NotifyOnNewObject` callbacks are let go, Survival's music and HUD are given
  back, and at Survival's next tick what it spawned is taken off (a switch-off can come from inside Survival's own
  code).
- A `check`, `ready` or `spawn` that says no: Survival plays its normal round.
- A run with any add-on found in `AC8SurvivalAddons` (loaded or not) isn't ranked on the leaderboard (`LB.edited` lists
  it). An add-on can't reach that list.

## Co-op
API 2.0 is single player. While co-op is open (from the moment a host opens it, and on every joiner) no add-on's round
comes, none of its jobs (`SVP.every`, `SVP.on`, `SVP.going`) run, and every API call that changes the game refuses. A
friend without the add-on sees plain Survival. Co-op support for add-ons is planned for a later API version, in its
own change.

## Log lines to look for
`plugin <name>: kind <kind> registered (...)`, `plugin <name>: loaded (...)`, `plugin <name>: not loaded: ...`,
`plugin <name>: its round skipped: <why>`, `plugin <name>: <what>: the add-on is switched off for this session`,
`plugin <name>: Survival's music given back (...)`, `plugin <name>: <n> of its <m> pins let go (...)`, `plugins: none (...)`,
`plugins: AC8SurvivalAddons looks like a UE4SS mod (...)`, `plugin <name>: SVP.target outside its own round: refused ...`,
`plugin <name>: NotifyOnNewObject <class>: UE4SS refused it (...)`, `plugin <name>: <n> targets dropped (...)`.
