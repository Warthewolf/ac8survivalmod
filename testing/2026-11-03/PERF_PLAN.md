# Survival Mode: lag and stutter plan

## Where it comes from
The lag comes in two kinds, and both run on the game thread.
- **Steady cost.** Saint Alessia, 0.73.78 solo round 1: 24.3 ms a tick (first half 19.8, second 4.5); 61 ms in the Alicorn round. A half over ~10 ms misses a 60 fps frame, so the first half misses one four times a second.
  - Root cause: UE4SS can't find FUObjectHashTables (`object lookups use GUObjectArray`). Every StaticFindObject is then a ~3 ms scan, and `clock` is two of them (6.3 ms, 26%).
  - Native calls that VirtualQuery every pointer add more (SV_UnitAlive costs 0.75 ms a call).
- **Hitches.**
  - Each FindAllOf is 35-49 ms. The `walks:` line prints totals, so "2x 71 ms" is 35 ms each.
  - The native Log flushes to disk on every line: 50-110 ms at round starts and clears.
  - HUD build: 416 ms. VALKA's walk bursts: 210-340 ms. Ladon walk pairs: 70 ms every 10 s.

Gameplay is unchanged for every item unless it is marked **Caveat**.

## Tier 1: quick, safe, big wins
1. **Cache native lookups.**
   - Fixes: `clock` 6.3/15, host `coop` ~10 ms, HUD labels, and the 87 lookups in each HUD build.
   - Change: in sv_core.lua, a StaticFindObject wrapper that caches `/Script/` hits, checked with liveObj on reuse. It never caches misses or `/Game/` paths. Route newWidget and the raw `/Script/` lookups through it. COOP.tick reuses roundClock's D.now and paused answer.
   - Saves: ~6 ms/tick solo, 6-9 ms more in linked co-op, ~300 ms per HUD build.
   - Risk: very low.
2. **Native Log without a per-line flush.**
   - Fixes: `rounds` worst 107-310 ms on co-op hosts (29 lines at a round clear cost 60 ms), and ~4 ms per SV_Spawn.
   - Change: delete FlushFileBuffers at survival_rt.c:111. Crumb already writes without one.
   - Lua stopgap that can ship now: call SV_LogUnits (sv_rounds.lua:1068/1414) only with logVerbose().
   - Saves: ~2 ms a line.
   - Risk: only a BSOD or power cut loses the last lines.
3. **Menu tables idle during a run.**
   - Fixes: `rows watch` 3.5/18, `info maps` 0.9/9, `shop rows`.
   - Change: in sv_main.lua, while `D and svLevelOn ~= false and not LEAVE.why`, run rows watch every 30 s and info maps every 60 s.
     - watchRows keeps t.obj (checked with liveObj) and reads names only when the address changes.
     - infoMapsTick checks has() before FindRow.
     - shopRowsTick returns early once the rows are in (table checked with liveObj, same verified player controller).
   - Saves: ~5 ms/tick.
   - Risk: if another mod edits the main menu mid-run, the repair comes up to 30 s later.
4. **Main menu off during a run.**
   - Fixes: `menu` 0.7/18.
   - Change: in sv_menu.lua MENU.tick, run pagesTick and the lobby texts only when `not D`. When D clears, push the texts once with onScreen false (no TextBlock walk).
   - Saves: 0.3-0.7 ms/tick.
5. **Leave probe every 0.5 s.**
   - Fixes: `leave check` 1.1/3.
   - Change: sv_core.lua levelGoing: `every = LEAVE.why and 1 or 0.5`.
   - Saves: ~0.9 ms/tick.
   - Risk: the soft backstop latches up to 0.4 s later; the teardown gate closes first anyway.
6. **Ladon missile walks once a level.**
   - Fixes: two walks (70 ms) every 10 s.
   - Change in sv_ladon.lua:
     - Walk at the first sweep, after a queue overflow (HIT.newDropped), or while the hook hasn't delivered anything. Otherwise walk every 60 s, one class per sweep.
     - Tone from HIT.base, read once a level. Write only on a mismatch, after the name check.
   - Saves: the hitches, and ~60% of each sweep.
7. **Smaller trims.**
   - playerLocation memoised per tick half (return copies; clear after SV_Respawn and teleports): 0.2-0.6 ms/tick.
   - PlayerController via GetPlayerController(gameInstance(), 0) + inSurvival before walking: 1-2 walks fewer at each level load.
   - WOLF.tick: alive check every tick only for `pending` entries; drop `free` entries. Saves 0.75 ms/tick per Wolf flight (4.5-7.5 ms in Legend rounds).
   - Bosses: call SV_UnitAlive only when the boss plane is gone or at 0 HP, otherwise once a second: 0.6-1.2 ms/tick.
   - airUp via ALLY.alive: 1.5-4.5 ms/s with allies. **Caveat:** the ALLIES counts can be up to 2.5 s old.
   - ALLY.repairAll: skip the DEF_CLASSES walk when no defence is bought, and heal SHUTTLE.pad's objects directly: 105-150 ms off every round clear.
   - Shuttle take-off walks LiveAIGameObject only: 70-100 ms off a one-time hitch.
   - A difficultyManager() getter: removes an 8-14 ms walk about every 30 s.
   - SND.preload VALKA's sounds, one file a tick, in the break before her round. This moves the ~106 ms and ~98 ms stalls out of the fight.

## Tier 2: medium changes
8. **Feed objects instead of walking.**
   - Change: NotifyOnNewObject into a capped queue (the callback only records). The tick filters with liveObj and the name, LEVEL_DROPS clears it, and the walk stays as a logged fallback.
   - Apply it to:
     - landing windows (35-70 ms every 0.5 s on the airfield)
     - LiveEventContainer (61 ms every 120 s)
     - spawnReal/rigOn (one walk per real plane per level)
     - VALKA's railgun rounds (~15 walks per shot)
     - AB.L..IN's ECM pods (a walk every 2 s in phase 3; re-check the owners each pass)
     - the weapon activator
9. **VALKA and Alicorn.**
   - VALKA: one cached railgun launcher list, refreshed only at the opener's start, its shot and her reveal. 210-340 ms bursts become ~40 ms.
   - Alicorn silence(): K2_GetComponentsByClass on each pooled plane instead of walking every AkComponent. Removes ~15 walks a fight.
   - parts(): index the spawn record once. 50-150 ms off the first check.
   - groundTick: read each object's name once. ~30 ms off the spawn hitch, on every game.
10. **HUD build.** Build the info wall in steps and the summary when it is first shown. Drop line 36's SetText, use one SetFont, and set ZOrder 1 on the banner and summary slots. Saves ~40 ms more off the build.
11. **Natives without syscalls.**
    - Change in survival_rt.c:
      - Cache property offsets per class, and keep a hit-only FName cache.
      - Use InGame() for vtable checks.
      - Check the kept spawner, world data and world by their GUObjectArray slot. Never refuse "unreachable", or g_spawnerLost latches.
      - Add SV_AmmoAll.
      - L_ObjChain checks memory on the first object only.
      - OnMusicTick caches its pointers per world.
    - Saves: ~3-5 ms/tick in round 1, likely 6-15 ms in late rounds.
    - Risk: medium, because a false "gone" ends rounds. Fall back when GUObjectArray isn't found, and log old vs new for one session.
12. **Co-op Lua.**
    - Health polls go through SV_ObjChain on the kept addresses.
    - ammoRead is gated; the airfield test comes from COOP.me().
    - strayTick checks bound[] first.
    - Peer liveness is checked once a tick.
    - Loadout and paint are read every 4th tick.
    - Saves: ~3-5 ms/tick on a late-round host.
13. **Spaceport.** shipsTick spreads the ships over the 4 ticks, each still checked once a second. A 25-40 ms burst becomes 10 ms or less.

## Tier 3: larger or riskier
14. **Co-op per-frame natives** (coop.c CoRefGet/CoKind/CoReadPose, flight.c feeds).
    - Change: slot checks and InGame() instead of ~270 VirtualQuery a frame on a joiner.
    - Saves: an estimated 4-11 ms a frame.
    - Add QPC timing first to measure it.
15. **UE4SS hash-table AOB** (UE4SS_Signatures/GUObjectHashTables.lua). Research only:
    - A wrong AOB crashes every UE4SS mod.
    - It needs re-checking after each AC8 patch.
    - Shipping it is your call.

## Tier 4: tester/dev builds only
- Weapons log: walk one base per look at the run's start, then only after a queue overflow. Removes 105 ms every 30 s (`weapons log 0.9/112`).
- Fleet LiveBullet walk every 15-30 s, behind `turret_guns`. Keep it available: whether the ships' flak fires is still unconfirmed.
- Target audit from aiWatch's p.aiTargetAddr: saves 2-6 ms every 5 s.

## Not recommended (changes gameplay)
- Walking for VALKA's rounds only 0-0.5 s after a shot: they appear 3-4 s later, so the opener round would keep its damage.
- Checking Ladon toning on two sentinel fields: a relaunch resets damage to 750.
- Comparing ammoTick's pawn by address only: the caps miss a respawn at the same address.
- Co-op:
  - Asking IsGamePaused only when D.now stalls: everyone unpauses a tick late.
  - An unjoined host skipping SV_CoopMe: a new joiner sees no host plane for up to 5 s.
  - Capping groundTick at 40 objects a tick: joiners' hits on unbound parts are lost.
- Polling Spaceport turrets every 3 s: their pay comes late.
- Queuing retakeSpawn: the retake falls back to a normal round.
- playerMissileDamage from the pawn's own missile: Alicorn parts get different health.
- Repairing ships from spawn records: stops healing the enemy fleet's Aegis hulls.

Also skip:
- The ScCall4 rewrite (no gain).
- A buffered Lua log (it loses the tail on a crash).

Not a cause: the pause-menu music walk never runs, because music is off by default.

## Order of work and next test
1. Lua only: items 1, 3-7 and the SV_LogUnits gate. Then move rows watch, info maps and MENU.tick to the second half.
2. Runtime 0.32.24: item 2 with the L_ObjChain and OnMusicTick changes. Bump COOP_TAG and re-register the hashes.
3. Tier 2, then item 14 with timing. Tier 4 goes into tester zips at any point.

What to check in the next test:
- `perf:`
  - first half under ~8 ms in solo round 1
  - `clock` under 0.5, `rows watch` ~0.1, `leave check` ~0.3
- `perf: lists:`
  - no repeated walks of LiveEventContainer, PlayerController, the landing windows, the Ladon VLS missiles, AkComponent or LiveFCSModule
  - a new `finds:` count
  - SV_UnitAlive calls and ms
- UE4SS.log: under 5 ms from `credits: +N (round N cleared)` to `ROUND N COMPLETE`.
- Quit Mission: still logs `level gate: closed` and pays no kills.
- Co-op host: `coop` under ~4 ms.