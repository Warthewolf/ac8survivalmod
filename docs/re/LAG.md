# The host's lag over a long run (Saint Alessia's 50-round co-op run, 2026-11-11)

Her logs (0.74.36-coop2mp.128, host, 10 players, rounds 1-51, 19:00-00:34) and Delta's (a joiner) were read for "lag
during Ace waves". Nothing in Survival's Lua costs more in an ace round (the 'squads' part, 2-5 ms a tick, moves the work
into the tick's second half); what grows is the whole run's cost: the Lua tick went 8-17 ms (rounds 1-9) -> 26-39 ms
(16-48) -> 83-99 ms (49-50). Every Lua tick runs on the game thread (sv_main.lua ExecuteInGameThread), so its cost is
frame time. The fixes below, each with the log line that shows it in the next test.

## lag-1: SV_UnitAlive walked the phase's unit list with system calls (runtime 0.32.35)
`SV_UnitAlive` (and Spawn, Recycle, SetAircraft, SetLevel) ran `SpawnerReady`'s six `VirtualQuery` checks of objects it
had found already, then `RegisteredUnit`'s walk of the phase's unit list with two `VirtualQuery`s an entry (one on the
entry's vtable, inside the game's 551 MB image). The list keeps every flight shot down and not spawned again, so the
cost grew with the run: 0.53 ms a call at round 2, ~6 ms from round 22, 9.4-9.9 ms at rounds 49-50 (~0.1 ms an entry,
~100 entries), 28-50% of the tick.

Now (runtime/survival_rt_game.c, runtime/unittab.h, runtime/uobj.h `UObjSlotHolds`):
- the spawner, its world data and the world are kept with the GUObjectArray index they had when found, and checked at
  that slot (no system call: the slot still holding the object means it's allocated), their flags read then;
- a vtable slot inside the game's image is read without a check (`InGame`, the image is always mapped); anything else
  with `Readable` as before;
- the list's memory is checked when its data, count or capacity change; the unit descs found by name are kept (a slot
  per name, checked again on use); the units' `AliveChildAIGameObjects` offset is kept per class;
- the list's ids are in an id -> unit table, rebuilt when the list's data, count or entries (a hash of its pointers)
  change, at the spawner's own changes (`g_unitGen`: Spawn, Recycle, the deferred destroys, SV_Reset) or every 2 s; a hit
  is checked again (still allocated, still that id: hard rule 59) and a failed one rebuilds; the build's walk checks each
  entry readable (one query per allocator region) and still allocated. tools/checks/unittab_test.sh (run by
  build_all.sh, with uobj_test.sh) runs the table against the old walk, 20,000 random list changes included.

Log lines:
- `spawner: LiveUnitSpawner ..., world data ...; checked through GUObjectArray: yes` (no: every check the old query)
- every minute while asked: `units: the last minute: N SV_UnitAlive asks, X us each on average (worst Y us); the phase's
  list up to L long; its id table built B times (... for the spawner's own changes, ... the list's, ... on its 2 s
  refresh, ... a hit moved), E entries read, S skipped; kept objects checked through GUObjectArray: yes`. Expect tens of
  microseconds, not milliseconds, at any round.

## lag-2: ALIVE's budget counted asks, not time (sv_spawn.lua)
At rounds 49-50 the Spaceport's 41-52 units kept ALIVE near its 32 asks a second at ~9.5 ms an ask (69-71 ms a tick of
'rounds'), and an answer 3 s old was asked again whatever the budget. Now the tick's native asks are timed (`os.clock`):
past 4 ms of them no refresh runs, an answer is used up to 3 s old once the tick's count or time is spent, and past 3 s
it's asked again only while the time lasts, else used up to about 10 s old (one older asked a tick: no burst). The
asks that always run (a unit never asked, a plane of it seen down, `ALIVE.fresh`) count against both. RATE_MAX stays
32: with the native ask in microseconds and the time budget for a slow one, a lower count only read the Spaceport's
kills later (spaceport_test's pays within 2-3 s). Tests: rounds_test.sh (52 units at 9.5 ms an ask: ~1.2 asks a tick,
worst 19 ms, against 8 and 85 ms before).

Log lines: the run's `alive: (0.73.80) ... (lag-2) at most 4 ms of native asks a tick (then answers kept, up to about
10 s: one older asked a tick)`; each round's `alive: round N: ... (lag-2) the asks took X ms in all, Y ms in a tick at
most (its budget 4 ms): C refreshes cut by it, H answers kept past 3 s` (C and H stay 0 when the native asks are fast).

## lag-3: the round clear's repair walked every object seven times (sv_allies.lua, sv_shop.lua)
`ALLY.repairAll` walked SHIP_CLASSES' four classes with ships at sea and DEF_CLASSES' three with defences up, over every
object (`FindAllOf`: this game's object hash tables aren't found, ~41 ms a walk late in her run), in one tick: 120-320 ms
frozen at every clear from round 8, for 0-3 objects repaired. Now the allied ships' and the defences' objects are kept
as `SV_Spawn` makes them (`spawningUnit` names their unit: `ALLY.buy`, the STORE's defences through sv_shop.lua's
`spawnDefence`, a joiner's copies), `ALLY.parts[unit]`, their names read the tick after; the repair heals those (each
live and still that name), the same classes as before. A unit up with none kept is walked for one class a tick at a
round clear (at once for the STORE's airfield repair, as before). The defences' actors for their health (re-found every
120 s, at a loss or a new one: three walks of 41-48 ms) come from the same kept objects. Tests: lag_test.sh.

Log lines: `allies: repaired between rounds: A aircraft, S ship parts, D airfield defences` (with `(a walk left for ...:
a class a tick)` when one wasn't kept, then `allies: the repair's walk for ... done, a class a tick: N more repaired`);
`allies: the airfield defences' actors from their objects kept at their spawn: N for M up, no walk (lag-3)`.

## lag-5: VOID WATCHER's ESM fields read every tick, for ever (sv_allies.lua)
In her run each ESM launch made a new field (none was launched again, against 0.73.73's two pooled fields), and every
field ever seen was kept and read every tick with its name, VOID WATCHER up or not: 5 -> 163 fields, ~4 ms a tick, ~330
SV_ObjChain calls a tick. Now a tick reads the fields set in the last life_s + 5 s and a slice of the rest (all of them
every 3 s), only while VOID WATCHER is airborne here or a field was set in the last 90 s; a field's name is compared
before it's set again, not every tick; the newest 32 are kept. Log line: `allies: VOID WATCHER 1's ESM fields: the
newest 32 kept, the oldest let go (lag-5)`; the perf line's `ESM fields` size stays at 32 or less.

## lag-8: the log bundle copied another mod's flood whole (runtime/logbundle.c, runtime/logdedup.h; runtime 0.32.35)
Her UE4SS.log was 415 MB, 98.3% one line of another mod's (4.4 million times, in bursts of up to 209 a half second);
the bundle would have copied and zipped it whole. Now the copy writes a run of lines that are the same after their time
stamp once, then `[stamp] ---- the line above N more times (from [stamp]) ----`; it stops at 64 MB (said once, the rest
counted). The stamp is UE4SS 3.0.1's dated one, `[2026-11-10 19:01:46.9542123] ` (an undated `[19:01:46.9542123] ` is
taken too; `[Lua]`, `[ ]` are not stamps). Past the cap nothing more is written but the cap's line, once, and the line of
a run already going as it was reached: every line after it counts as dropped, its repeats too (they still count for the
most repeated line). `logs\UE4SS_stats_<stamp>.txt` holds the counts and the most repeated line, and the bundle's
bundle.txt sums them up (`UE4SS.log: X MB read, Y MB copied into ...; its most repeated line (N repeats): ...`). The
runtime's log says `logs: UE4SS.log's copy: X MB read, Y MB written, L lines, C of them repeats collapsed, D past the
64 MB cap; its most repeated line N times (lag-8)` once 1,000 repeats are collapsed, then every 10 minutes. Her own
UE4SS.log fed through it (in 32 KB reads, as the copy thread reads it): 396 MB in, ~9 MB out, 4,427,860 lines collapsed
into 12,456 run lines, none dropped; the first version knew only the undated stamp, never what UE4SS writes, and
collapsed 2 of its 4.48 million lines, stopping at 64 MB 3.5 hours short (the review of 2026-11-11). Test:
logdedup_test.sh, run by build_all.sh (a made-up flood with UE4SS 3.0.1's stamps fed in chunks that end anywhere: the
copy under 2% of it, every line given back by expanding the counts; the stamp forms; nothing written past the cap,
however the lines repeat and the log goes quiet; every line read in the copy, collapsed or dropped).

## joiner-4: no frame time on any game (runtime 0.32.35)
Neither game's logs had a frame time, so "lag in ace rounds" could only be guessed from a proxy (the other players' real
planes' frames fed: ~30 fps on the host whatever the round, 16-23 in rounds 47-50; ~50 on Delta's). Now every game logs,
once a minute while a plane flies, `frames: the last minute: N frames while a plane flew (F fps), A ms on average, 95%
under P ms, worst W ms; X over 50 ms, Y over 100 ms; Z gaps over 2 s not counted (a pause, a load) (joiner-4)`: the
flight input build (runtime/survival_rt_game.c OnBuildInput) marks the frames, a call 3 ms or more after the one before
starting a new one. The round's kind is in the Lua log at the same time.

## Not changed here (other strands, or the user's)
- The ZFA-44s left behind and the escort part's ~2.5 ms a tick for them (sv_escort*.lua, the ZFA-44 strand); the
  escort's `aliveOf` and ACE.squadTick's `alive()` still ask SV_UnitAlive directly (sv_escort.lua, sv_ai.lua: other
  strands' files), now microseconds an ask.
- The Retake's start and the Spaceport units' answer ages (sv_spaceport.lua: the rockets strand).
- Falken_RedGloss's pollers themselves (another mod; the player can turn it off for long runs).
