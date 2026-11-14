# Plugins: other mods' special rounds (sv_plugins.lua, add-on API 2.0)

For add-on authors: `docs/ADDONS.md` (the API, versions, the rules) and `examples/addons/target_practice/`. This page
is the loader's and the guard's internals. For Survival's maintainers (what Survival must keep for add-ons):
`docs/ADDONS_MAINTAINING.md`.

UE4SS gives every Lua mod its own Lua state, so another mod can't reach Survival's SPC.kinds from its own main.lua.
An add-on is a folder the other mod installs into `Mods/AC8SurvivalAddons/<name>/` (beside Survival's own folder;
Survival's zip has no such folder; its assets stay in the other mod's own container, never in Survival). Survival runs
each add-on's `.lua` files, in name order, in its own Lua state at its first tick (sv_plugins.lua and its pieces
sv_plugins_api.lua and sv_plugins_env.lua are the last entries of main.lua's MODULES; sv_main.lua's tick job calls
`PLUGINS.tick`, which loads them the first time), each add-on in an environment of its own (`envFor`). A level
change no tick saw going (sv_core.lua `levelDrop` between two ticks) is caught by `LEVEL_DROPS["add-ons"]`.

## Loading
- `io.open` on `Mods\AC8SurvivalAddons` first: the C runtime answers EACCES for a folder that's there and ENOENT for
  none. No folder: `plugins: none (no AC8SurvivalAddons folder)`, nothing else is done.
- Then UE4SS's `IterateGameDirectories()`, walked down to the Mods folder by SCRIPT_DIR's names; each folder in
  `AC8SurvivalAddons` is an add-on (its `.lua` files and its `natives.txt`). Without it, `AC8SurvivalAddons\addons.txt`
  lists them (a line `<name>\<file>.lua` each).
- `Scripts\main.lua`, `enabled.txt` in `AC8SurvivalAddons`, or an `AC8SurvivalAddons` line in `Mods\mods.txt`: logged
  (`looks like a UE4SS mod`): UE4SS would run it by itself, outside the framework. An add-on folder named `Scripts`
  or `dlls` is refused.
- Every add-on found goes into `PLUGINS.loaded` before any add-on runs (LB.edited: the run is unranked, loaded or
  not; no add-on can reach that list). A folder name that isn't letters, digits, `_`, `-` (40 at most), or a folder
  with no `.lua`: switched off. Each file then runs in the add-on's environment, in a pcall with the runaway hook. A
  file that can't be read or doesn't compile, an error at load, a runaway loop, a refusal (`def.api`, `def.requires`)
  or a switch-off during its load (`loadFailed`): logged, the kinds it registered taken off again (`SPC.kinds`,
  `CFG.specials`, the rotation entries it added: `p.addedRot`), the add-on switched off, its later files not run.
- While a file runs, `SVP` is there; it registers its kinds with `SVP.register`.

## An add-on's environment (`envFor`)
- Its own table: writes stay there, reads fall to the allow-list (docs/ADDONS.md, "Your add-on's environment"), then to
  its native mod's C functions (named in its `natives.txt` or `def.requires`; a capitals prefix and `_`, never `SV_`;
  `debug.getinfo(f, "S").what == "C"`, asked by the framework). `__metatable` false.
- `setmetatable` refuses a metatable holding `__gc` (Lua 5.4 marks a table for finalization only when its metatable has
  `__gc` at `setmetatable`; a finalizer would run with hooks off, inside whatever Survival code the GC step lands in).
  `pcall` / `xpcall` re-raise `frames.runaway` (the runaway hook's stop) at once, and `xpcall`'s handler is skipped for
  it. A call with no add-on attached (`PLUGINS.running` / `current` both nil) is refused (`refused(nil)`).
- The runaway hook (`hooked`): one `debug.sethook` count hook for every guarded call in progress (`frames`, outermost
  first); a nested guarded call keeps it, so the count isn't restarted and the outermost deadline governs (and its
  Lua heap at its start: `RUNAWAY_KB` more stops it too). Run out, an inner call passes the stop on (`passOn`, raised
  again by `guard`) to the outermost, which switches off the culprit (below), not necessarily its own add-on. A Lua
  hook that was there before (a profiler's, the test's watchdog) is still called from it. A call inside another of the
  same add-on's counts toward neither its stalls nor its budget (the outer one's time holds it).
- Copies of `string` (no `dump`), `table`, `math` (no `randomseed`), `utf8`; `getmetatable` for tables only;
  `collectgarbage("count")` only; `io.open` / `io.lines` reading only; `load` / `loadfile` / `dofile` text only, in the
  add-on's environment, their chunks named `=<folder>:<name>`; no `debug`, no `coroutine`, no `require`, no
  `StaticConstructObject` (`SVP.widget`).
- Handles: every SVP call taking an actor or object takes a UE4SS object only (`isHandle`: userdata), never a table of
  the add-on's (its methods would run outside the guard).
- Where the stop lands (`runawayHook`): past the outermost's deadline (or its memory limit) it raises in the add-on's
  own code only (inside Survival's, `survivalCode`: its Scripts folder,
  `PLUGINS.ownSrc`, it comes back after `RUNAWAY_SOON` instructions, `RUNAWAY_GRACE_S` at most), so no step of
  Survival's is cut from its flag. The culprit: the innermost frame that has itself run `RUNAWAY_S / 2` (for the
  memory limit: grown the heap by half of it), else the outermost. The framework's own `pcall` (`PLUGINS.pcall`, handed to the pieces) raises a stop on.
- `FindFirstOf` / `FindAllOf` / `StaticFindObject` refuse while `levelGoing()`, `walkHold()` or `walkBusy()` holds
  (`PLUGINS.walksBusy`).
  `NotifyOnNewObject`: false when UE4SS refuses the class (nothing kept); one callback an add-on a class (asked again:
  replaced); 64 classes in all. One UE4SS registration a class, Survival's. UE4SS calls it on the constructing thread, inside the
  game's construction, so it only queues the object (`notifyQ`, `NOTIFY_MAX` 256 a class, the rest dropped and said); `PLUGINS.notifyTick` (in `PLUGINS.tick`, the game thread,
  the queue dropped while the walks are held or co-op is open) hands each one, once, still `liveObj` and of its class
  (`IsA`, the class from `StaticFindObject`; no class found: nothing) to each add-on's callback, guarded (`guard`: pcall, the stall timing). Dropped at its switch-off
  and, with the queue, for every add-on at the level's teardown (`PLUGINS.dropNotify`).
- A switch-off (`PLUGINS.switchOff`) sets `off`, takes its targets off, gives back the music, HUD and pins and drops its
  callbacks at once; what it spawned is taken off at the next `PLUGINS.tick` (`takeOffTick`; not while the level goes),
  since a switch-off can come from inside Survival's own code (a HUD row, a bag fill).
- The tables Survival hands a kind's callbacks (`D.special`, `CFG.specials[kind]` through `SVP.cfg`) are read-only views
  (`readOnly`): a write raises (the guard switches the add-on off).

## SVP (every name 15 characters or fewer, hard rule 25's limit kept for the Lua side too)
| call | what |
|---|---|
| `SVP.version` / `SVP.api` | 2 / `{ major = 2, minor = 0 }` (an add-on's `def.api`: its major, a minor up to this one; none: refused) |
| `SVP.register(kind, def)` | `true` or `false, why`. `kind`: letters, digits, `_`, at most 15, not taken, not a name in `CFG.specials`. `def.kind`: the SPC.kinds entry (`spawn` needed; the other fields and their types: `FIELDS`, docs/ADDONS.md). `def.cfg`: its settings' defaults, becomes `CFG.specials[kind]` with `[specials.<kind>]` from survival.ini read over it (each value takes its default's type; `enabled = false` switches it off). `def.rotation = true`: joins the rotation, unless the player wrote their own `rotation` (read once, before any add-on joins). `def.name`, `def.ver`: the log and the leaderboard. |
| `SVP.target(actor, opts)` | an id, only in the add-on's own round (`p.liveRun` / `p.liveKind`, set at its spawn, cleared at its over), 256 an add-on (`TARGET_MAX`), every one dropped unpaid at its run's end and the hard going (`dropAllTargets`); refused for a handle whose object is another now, or a player's plane (`isMine`): `opts` copied raw (`targetOpts`); the actor (kept by its address and full name) is watched on every tick of the add-on's round; gone, reused or no health = down: `opts.pay` x the round's tier (as the Spaceport's ships; `opts.flat` = as given; a whole number, 0..1,000,000), a ground stat (`opts.class = "air"`: air), `opts.onDown(id, why)`. Marked for Survival's plane sweep: while it's up, `PLUGINS.owned` (asked every sweep; the sweep and the tail watch leave it alone: no tier, manoeuvres, spike, stats); seen down, `PLUGINS.owns` (used once: not counted, not paid). A mark is honoured only with its name and the plane record's. Off unpaid on retire, despawn, or a kill of no one's (the mark kept: nobody's); off at its round's end, a refused spawn, the add-on's switch-off, its run's end or `SVP.untarget` with its mark dropped (`dropTarget`: Survival's again), unless another target is at that address. |
| `SVP.untarget(id)` / `SVP.kill(id, why)` / `SVP.alive(id)` | off the watch (no pay) / down now, paid / still up; the calling add-on's own targets only (`ownTarget`) |
| `SVP.pay(n, why)` | zollars: a whole number, 0..1,000,000; not a finite number: nothing |
| `SVP.load(path)` | an object of the add-on's container (`loadObject`, hard rule 9) |
| `SVP.spawn(cls, at, yaw)` | an actor of a class (or its path) at `at` (cm), `yaw` deg; Survival's deferred spawn. Kept by address and full name; taken off if the add-on is switched off |
| `SVP.move(a, at, yaw)` / `SVP.despawn(a)` | teleport / take off: a game object (`isUnit`: an `ALiveGameObject`, `ALiveAIGameObject`'s parent) by its own death (finishUnpaid, unpaid; left with a line if the game won't let it die), never `K2_DestroyActor` (a unit destroyed by hand crashes AC8 at the next unit death, exe+0x7e0cb5a); anything else destroyed. Both refused for an actor whose address is another object's now, one another add-on recorded first (`othersActor`), and (despawn, retire) your plane (`isMine`) |
| `SVP.retire(a)` / `SVP.hurt(a, n, causer)` | finishUnpaid, nobody's (marked only when it dealt the death: a unit already at 0 keeps its kill, a target of it is paid) / ModifyHealth; a kill of no one's is marked once its health reads 0 |
| `SVP.players()` | `{ {slot, X, Y, Z} }` (you) |
| `SVP.pad()` / `SVP.runway()` | Mission 22's shuttle pad / Comona Airport's runway (AIRFIELD), cm |
| `SVP.clock()` / `SVP.round()` | the rounds' clock (D.now) / the round |
| `SVP.levelGoing()` | the level is going away: touch nothing (the API's calls refuse) |
| `SVP.callout(text, sub)` / `SVP.say(who, text, secs)` / `SVP.log(msg)` | round callout / subtitle / log |
| `SVP.isHost()` / `SVP.inCoop()` | 2.0 is single player: while co-op is open nothing of an add-on's runs |
| `SVP.on(event, fn)` | runStart, roundStart, roundEnd, runEnd (as the tick sees D and D.round change), levelGoing. On the teardown tick: SVP.going's jobs, then `runCheck` (a round's abort), then `eventsTick`. `JOBS_MAX` 64 an add-on each of every / on / going; a pass runs the jobs there as it began (`pruneJobs` drops a switched-off add-on's) |
| `SVP.widget(class, outer, name)` | UE4SS's `StaticConstructObject` for UMG's concrete widgets (`WIDGET_OK`) or a widget blueprint's class, in a live `WidgetTree` / widget, named `SVA_<folder>_<name>_<n>` (`PLUGINS.widgetSeq`: never a name already in the outer); refused while the walks are held or co-op is open, 256 an add-on a level |
| `SVP.provide` / `SVP.liveObj` / `SVP.bgm` / `SVP.hud` | see docs/ADDONS.md; one music mute for every add-on (`PLUGINS.bgmHeld`, also asked by sv_sound.lua's song end and unmuteTick) (`SVP.hud` is Survival's `HUD.hold`, one holder an add-on: `add-on <folder>`; `HUD_MAX_S` from the first hide, not re-armed). A switched-off add-on's provider is taken over by the next one |
| `SVP.cfg(kind)` / `SVP.pc()` / `SVP.paused()` / `SVP.dir()` | its kind's `CFG.specials[kind]`, a `readOnly` view (nil for a kind not its own) / `survivalPC` (nil while the level goes) / `gamePaused(survivalPC)` / its folder |
| `SVP.intercept(m)` | `SV_Intercept(m)` (runtime/laser.c: `ALiveWeaponBase::Intercepted`, the interceptor's clean kill) after `m:IsA(/Script/Live.LiveWeaponBase)`: 1 shot down, 0 not in flight, nil refused (not a weapon, no SV_Intercept, `refused`) |
| `SVP.pin(o, why)` | `o` in the GameInstance's `ReferencedObjects` (a let-go slot first: it holds `Default__GameplayStatics`, a class default object). `PIN_MAX` 64 an add-on. `PLUGINS.unpinAll(p, why)` at its switch-off, its run's end, the level going: a slot is put back only while it still holds that object (its address: `sameSlot`) Assets only: an object that is, or whose outers reach, a `World` / `Level` is refused (`inWorld`) |
| `SVP.net` | co-op's add-on channel: not in 2.0 (a stub) |

## Safety
- Every callback of an add-on runs in a pcall with a count hook: its first error, a stall (3 calls over 2 s within
  60 s), its time budget (6 s of the game thread within 30 s) or a runaway loop (a call still running after 10 s) is
  logged and switches the add-on off for the session (busy false, ready false, its targets off the watch, its spawned
  actors taken off as SVP.despawn does at the next tick, Survival's music and HUD back), so its round ends as soon as
  Survival's checks allow. An error value whose tostring raises is printed as a placeholder, and a table with a
  metatable isn't asked at all (`str`: an add-on's `__tostring` would run outside its guard).
- What the framework keeps of an add-on's tables is a raw copy taken at the call: `targetOpts`, `rawCopy(def)` and
  `rawCopy(def.kind)`, `SVP.fx`'s `rot` / `floats`, the positions (`posOf`: spawn, move, sound),
  `plainCfg(def.cfg)` (numbers, strings, booleans, flat lists; the rest left out, said). Read-only views are cached per
  add-on (`roCaches`): a `rawset` on one shadows a value for that add-on only.
- Hard rule 59: `PLUGINS.ids` is weak-keyed on the actor handle (`newIds`), each record with its level
  (`PLUGINS.level`, up at the hard going sign: a handle of an older level is refused for good); `itself(a, true)`
  reads the full name once in each add-on call that changes the game (`PLUGINS.calls`, counted at the outermost
  guarded call), `itself(a)` at most once a second (the targets' watch); a handle not seen before is recorded at its
  first call. Owners (`PLUGINS.owners`) by address and full name, so another add-on's handle of the object is known.
- The level's teardown: `levelGoing()`'s first sign stops every job and call; the one-way steps (level up, targets,
  marks, owners, pins, notify callbacks dropped, the spawned list forgotten) only at the hard sign (`levelHard`:
  `LEAVE.hard`, another level loading), never at the soft one (the unit spawner gone a second), which can let go.
- The calling add-on: `PLUGINS.running or PLUGINS.current` (the innermost guarded call's, then the loading one's).
- An add-on's `FindAllOf` / `FindFirstOf` / `StaticFindObject` all wait while the engine frees objects (sv_core.lua
  `walkBusy`: `SV_GcBusy`): UE4SS's Lua `StaticFindObject` goes `UObjectGlobals::FindObject` -> `ForEachUObject`,
  reading each object's Outer, and a mod's crash on this line faulted there in `UObject::GetOutermost` on an Outer
  freed during a purge (20261113-101700-5e40ab6). The API's own finds (its classes, the default objects it calls, an
  add-on's asset before it's loaded) go through `PLUGINS.find` (sv_plugins_api.lua): a kept hit (`kept`), else nil
  while `PLUGINS.walksBusy()`, else `StaticFindObject`; an asset not found is loaded by its path (`loadObject`).
- `SVP.play2d` / `hold2d` / `sound` / `fx` start nothing while `PLUGINS.walksBusy()` (`startsWait`): the assets they play
  are kept only in Lua (`assetHit`, `held2d`), so one nothing plays is unreferenced, a GC condemns it, and during the
  incremental purge `kept()` still passes; a sound started on it then had its USoundBase freed under the active sound
  (a mod's run on this line, 20261113-151013-f108042: the audio task's virtual-loop test, IsLooping, on the freed sound).
- `SVP.load` and plAsset hand out a found or loaded asset only if `liveObj` passes (SV_ObjChain: its slot, not garbage,
  not the GC's unreachable flag): UE4SS's `StaticFindObject` walk doesn't skip a condemned object, and sv_core.lua
  `loadObject` finds first too. A condemned one is not used and not loaded (`PLUGINS.condemned`: nil, one log line a
  path); `SVP.load` also answers nil while `PLUGINS.walksBusy()`.
- A kind's answers are checked before Survival reads them (`FIELDS`): a count for `aircraft` / `budget`, a string or
  nil for `sub` / `row`, a boolean for `alone` / `disguise`.
- 2.0: while co-op is open (COOP.open) an add-on's round never comes, its jobs don't run, its game-changing calls
  refuse.
- A run with any add-on found isn't ranked (LB.edited: "plugin <name>").

## Log lines
`plugin <name>: kind <kind> registered (...)`, `plugin <name>: loaded (...)`, `plugin <name>: target <id> (<label>)
down (<why>; +<pay>)`, `plugin <name>: <what>: the add-on is switched off for this session`, `plugins: none (...)`,
`plugin <name>: SVP.target outside its own round: refused ...`, `plugin <name>: NotifyOnNewObject <class>: UE4SS refused
it (...)`, `plugin <name>: <n> targets dropped (...)`, `plugin <name>: SVP.widget: 256 this level ...`,
`plugin <name>: SVP.pin: an object of the level ... refused`.
