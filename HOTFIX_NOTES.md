# 0.73.37 hotfixes (branch hotfix/0.73.37, from f8ef550 = COOP2MP 0.73.37-coop2mp.38, runtime 0.32.11)

Made in a cloud session on 2026-10-31 / 11-01 from players' logs. Shipped to testers as Lua-patched copies of the
0.73.37 Online COOP NoValka zip (`AC8SurvivalMode_COOP2MP_0.73.37-hotfixN_Online_COOP_NoValka.zip`, VERSION
`0.73.37-coop2mp.38-hotfixN`); this branch carries the same changes as source. Source VERSION is `0.73.37-hotfix10`
(a COOP package adds `-coop2mp.38` to it, so a rebuild reads `0.73.37-hotfix10-coop2mp.38`, not the testers' string:
co-op refuses mismatched versions, so everyone takes the same build). Runtime is 0.32.11.2.
None of this is merged into COOP2MP (now 0.73.58) or main.

## What each hotfix did
| # | Change | Where | Status |
|---|---|---|---|
| ladon1 / 2 | Ladon VLS volleys stop after its first pass (`CFG.specials.ladon.volley_after_pass = false`); its pass count re-syncs when the flag resets; its position logged every `pos_log_s` 15 s | sv_ladon.lua, sv_config.lua | Confirmed (host run of 2026-10-31 17:38): no resets, circuit held |
| 2 | `liveAddr(o)`: an object's address only when SV_ObjChain says it and its outers are live; replaces valid() before reads of objects kept between ticks (co-op's weapons in flight and their TargetToHome, HIT.msl missiles in director / stats / tactical / ladon, missiles caught by NotifyOnNewObject) | sv_core.lua + callers | One clean run; the crash it targets (UE4SS.dll+0x3e3732, reading [garbage+0x20] a second after `coopfire: your weapon BP_plwp_hpaa_a0_C`) not seen since |
| 3 | The enraged Ladon keeps its own circuit (`rage.circuit = false`: RE_SV_LadonRage<Key> not fired) | sv_ladon.lua, sv_config.lua | Untested |
| 4 | Ladon rounds and VOID WATCHER off (`specials.ladon.enabled = false`, `allies.awacs.enabled = false`) | sv_config.lua | In effect |
| 5 | Runtime: once this run's LiveUnitSpawner was found and has gone (the level unloading), FindSpawner answers "not ready" and doesn't search again until SV_Reset (the next run) | runtime/survival_rt.c | Confirmed (log `spawner: this level's LiveUnitSpawner is gone ...`, no crash). Fixed a joiner's crash in UE4SS's FindAllOf (UE4SS.dll+0x2ab5bd) on quitting |
| 6 | Co-op: world time dilation held at 1 while players are linked; the world clock watched | sv_coop.lua | The clock never stopped: not the cause of the freeze (kept as a check) |
| 7 | Co-op host at the airfield: each AI plane's CustomTimeDilation / tick / controller tick checked every 2 s and undone; planes that moved counted | sv_coop.lua | Found: the STORE turns every AI plane's tick off; turning it on doesn't make them move |
| 8 | Runtime: SV_ObjChain checks each object of the chain is committed memory (Readable) before UObjLive reads it; `svLevelOn` (Survival's level loaded) guards the airfield check; components seen ticking before the STORE switched on again if it turns them off | runtime/flight.c, sv_config.lua, sv_coop.lua | Fixed the host's crash on quitting to the main menu (main.dll+0x14735, UObjLive reading +0xC of a freed object): caused by hotfix7's check |
| 9 | `svLevelOn` not turned off by the TransitionMap (the seamless travel makes one after Survival's level loads) | sv_config.lua | Check ran: no component switched off, planes still frozen |
| 10 | The LiveMiniGameManager's lists (DeactivatedListForMinigame, DeactivatedList2ForMinigame, HiddenListForMinigame, DeactivatedVFXListForMinigame) read while the host is at the airfield; entries that are an AI plane's switched on again (component SetActive(true) + tick, actor tick); a plane's bMinigameAIObject logged | sv_coop.lua | Not yet run |

## Open problems
1. **Enemies freeze for everyone while the co-op host is in the landing STORE.** Not a pause (hotfix6: world clock
   runs, time dilation 1). On opening the STORE every AI plane's actor tick goes off (hotfix7); switching it back on
   leaves them frozen (hotfix9). Lead: the in-game hangar is the game's "minigame"; LiveMiniGameManager (a world
   subsystem) keeps lists of what it deactivated, and the level has a `Mission022_MiniGame` sublevel. Hotfix10 logs
   `coop: the minigame manager ...`. If the planes aren't in its lists, look at how the minigame starts
   (LiveSystemObjectMinigameBase, LiveMinigameSettings, bMinigameAIObject) in the exe. Solo the freeze is fine (the
   stock design); only co-op needs the world to keep running.
2. **Paths that are ignored.** VOID WATCHER's orbit (SV_Path_VoidWatcherOrbit, 550 km/h) and the enraged Ladon's rage
   circuit (SV_Path_Ladon<Key>Rage, 3000 km/h): the AI flies straight (VOID WATCHER to 163 km, 2026-10-31 17:25-17:46;
   MISHKA 87 km east and below sea level, 17:43-17:46) though RE_SV_AwacsOrbit fires. Their path descs in
   WD_SurvivalMode_global match the working circuit's (ControlType 1, same fields, unique ids and names, empty tube
   data) and the EP names them; next: decode the EP records (tools/checks/ep_dump.py needs tools/scriptobjs.pkl) and
   compare the orbit / rage exec records with the circuit's, then the speeds. Fallback: Mission 22's teleport record
   (hard rule 39) to turn VOID WATCHER back.
3. **Ladon appearance re-fire.** A Ladon's own VLS volley after its first pass re-fired its appearance trigger
   (SV_LadonRun<Key> reset to 0, the inbound route restarted from (-42, 4): "the Ladon left the map"). Hotfix 2 stops
   the volleys after the first pass; the build fix is to gate the appearance records (tools/survival_events.py
   build_ladon, also SV_AwacsUp) so they run once per spawn (a flag Lua sets just before SV_Spawn, cleared by the
   appearance), then `volley_after_pass` can go back to true.
4. A host crash at 2026-11-01 01:29:10 (hotfix8) inside UE4SS's Lua VM (UE4SS.dll+0xc640d8, reading -1) from a game
   callback, 4 s after `[FovMod] Disabled`; not traced to Survival's code. If it comes back, test with the other Lua
   mods (FovMod, AC8CockpitFreedom, AC8UltrawideHUD, SkinSlotText) off.
5. A joiner leaving was paid for its own enemy copies as kills (2026-10-31 15:47:06-08, +100 each).
6. `+Y` is south on Comona (the minimap confirms `awacs_orbit()`'s note); the Ladon notes saying +y north are wrong.

## Lessons (candidates for AGENTS.md hard rules once confirmed again)
- A Lua check over a level's objects must stop as soon as that level is going away: on quitting, Lua ticks once or
  twice with the old objects freed (two crashes). `svLevelOn` + the runtime's memory check cover it now.
- `valid()` (UE4SS IsValid) can pass on a freed object; ask `liveAddr()` before reading anything kept between ticks.
- In Lua, a multi-value call (`s:gsub(...)`) inside string.format's arguments shifts them (as hard rule 47's `and`/`or`):
  wrap it in parentheses.
