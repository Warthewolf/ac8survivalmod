# Co-op log review, 2026-11-01 (0.73.70-coop2mp.71)

A hand-off for a later, thorough pass (UltraCode). It covers what the logs show, what's been fixed, what's
still open, and what to verify. Everything here was read from the logs by one agent in one session. Treat each
cause marked **(hypothesis)** as unconfirmed until it's checked against the code or a test.

## 1. What's in this folder

| Path | What |
|---|---|
| `logs/2026-11-01/s1_host_SaintAlessia` | Session 1 host (10:13-10:24). Crashed while DOWN and spectating (UECC minidump) |
| `logs/2026-11-01/s1_client_Shazzy` | Session 1 joiner. The `ue4ss folder logs/` subfolder is an older 0.70.6-coop.11 run (12:09), not 0.73.70 |
| `logs/2026-11-01/s2_host_SaintAlessia` | Session 2 host (10:39-11:27) |
| `logs/2026-11-01/s2_client_Shazzy` | Session 2 joiner, with `Encountered Bugs.txt` (bugs 1-6 below) |
| `logs/2026-11-01/s3_host_SaintAlessia` | Session 3 host (11:36-12:07), with `Test Notes.txt` (Ladon tests A/B, VOID WATCHER, restart) |
| `logs/2026-11-01/s3_client_Shazzy` | Session 3 joiner |
| `logs/2026-11-01/s4_host_SaintAlessia_quitcrash` | Session 4 host, 3 players (12:19-13:40). "Crashed on hitting quit mission" (UECC minidump) |
| `logs/2026-11-01/s5_client_Crash1` | Session 5 joiner, 3 players (15:09-15:19). Crashed mid-round |
| `builds/..._0.73.70_TESTER_...zip` | The user's 0.73.70 tester build. **Its `Scripts/` are the only copy of the 0.73.70 Lua**: the source isn't pushed (newest pushed is `COOP2MP` 0.73.58) |
| `builds/..._0.73.70-fix1_TESTER_...zip` | 0.73.70 with this session's Lua fixes applied (`lua.patch`), sent to testers |
| `builds/lua.patch` | The Lua diff applied to make fix1 (`patch -p4` from `ue4ss/Mods/AC8SurvivalMode`; `sv_down.lua` is CRLF, so convert it to LF first) |
| `Test Notes - Alyssa (co-op fixes).txt`, `Test Notes - Player.txt` | Tester sheets for the next run |

All sessions: Saint Alessia hosts. Shazzy joins (player 2); sessions 4-5 have a third player. Every log is
`0.73.70-coop2mp.71`, runtime 0.32.18, Online COOP NoValka.

## 2. Findings

### F1. The joiner's resync loop (the main desync) — fixed in Lua (fix1, branch `claude/coop-fixes`)
- **Chain:**
  1. `strayTick` (`sv_coop.lua`) kills a copy that hasn't been bound to a host plane 15 s after spawning,
     then sends `jn`.
  2. The host answers `rs`.
  3. The joiner's `rs` handler ran `killAllCopies` and `DOWN.reset`, treating its own resync like a new run.
  4. Every copy was taken down and spawned again.
- **How often:** s2 joiner, 12 times (14-63 copies each, up to 22 never bound); s3, 4 times; s5, at least once.
- **What it broke:**
  - Specials and allies can't come back after the wipe: "the host's X not spawned here (its last flight is still
    up)" 58 times in s2 (LadonKot / LadonMishka, MoonchildA / B, VoidWatcher, Shuttle, PadDummies,
    AA_Unit_01_Ground0). Their old copies don't die (Ladon parts "2 NOT (still up)"; VOID WATCHER "couldn't be
    finished (health 9300 after)"). Hard rule 16 means the game won't spawn them again, so the old copies fly
    on their own AI.
  - **Ladon desync** (s2, 11:13:57-58): Mishka down on both games; 1 s later the joiner had a stray, sent
    `jn`, got `rs`, and its crumbs log has "copies: all taken down" including Kot (id 102) and its parts.
    The host's Kot lived until 11:15:01.
  - **VOID WATCHER at take-off pitch, MOONCHILD/SNIPER underwater and off the map** on the joiner: their copies
    are unbound after the wipe.
  - **Revived by a resync:** "revive: back (the host's run started over)" (s2 11:26:02, s5 15:18:50).
  - **Crash1** (s5): 20 s after a 33-copy wipe, the runtime's weapon-target guard caught tens of thousands of
    faults in about a second ("skipped a gone unit's entry", "caught a fault in an entry check ... reading 898",
    past 65536), then the game crashed. The weapons' target lists still held the freed copies.
- **The fix:** an `rs` answering this game's own `jn` (within 15 s, same level) is a soft resync. The copies are
  kept; the `sp` / `bd` messages that follow re-bind them (`doSpawn` keeps a flight already up in the same
  generation); `softResyncTick` takes down flights the host didn't name, 8 s later. Logs: "copies kept, bound
  again", "soft resync done: N flights ...".
- **Still to check:** why copies go unbound in the first place. In the logs, "the host's X here: 0 of 2 planes
  bound ... the host's last ids for it: 4 for gen N" shows the ids did arrive (twice: hostPlane + hostSync). The
  "bound" count may be low because copies the joiner shot are removed from `cu.planes` before the 20 s report.
  Real strays still exist. Find out whether `logPlane` → `clientPlane` misses planes (an `inSurvival` check at
  spawn?), or whether ordinals differ between host and joiner. **(hypothesis)**

### F2. Joiners paid for phantom kills — fixed in Lua
After a resync, copies spawned for host planes that are already dead die straight away ("up 0 s, round 0, by
you", +100 each: s3 11:52:00, 11:56:50; s2 11:26:03). `bindCopy` called `killCopy(id, o)` without `torn`. It's
now torn: not paid.

### F3. No missile lock after a revive — fixed in Lua (cause partly a hypothesis)
s2 joiner bug 6. Going DOWN sets `bIsWeaponSystemDisabled true` and the attacker limits to 0. The resync revive
(on the ground, 0 m/s, then SV_Respawn) left the weapons unusable. `backInFight` restored only what was saved.
It now always turns `INPUTS` back on, and `DOWN.back`'s respawn check re-applies it ("revive: weapons after the
respawn: on / NOT on").

### F4. STORE: the AA GUN row shows BUILD SAM SITE — fixed in Lua
`shopTexts` works out every `CFG.shop.items` entry, including the old fourth row `Airfield`, which isn't on the
STORE pages. When the airfield is whole, that row offers the next defence under the DEFENCES row's exact text
("BUILD AA GUN   4000 Z"). After a build its turn moves on to the SAM site, and `relabel()` (which finds rows by
their old text, through every TextBlock after "no STORE row TextBlock ... looked for in every TextBlock") rewrote
the real AA row too. Native presses confirm the rows' StringArgs were right (`SV_Buy_SAM` at 10:45:44, 11:09:06,
11:17:15; `SV_Buy_AAGun` at 11:17:17). Text two items share is no longer relabelled.

### F5. The Ladons leave the map after one lap — fixed in the build scripts (needs a full rebuild; not in fix1)
s3 Ladon test B, host log:
- 12:00:33: route end (pass 1).
- 12:01:59: first circuit lap end (`SV_LadonRun` 2).
- After that, straight east from x 22 km to 65 km, descending from 1.4 km to 0.1 km; no more passes.

**(hypothesis)** The game ignores a path order for the path a plane is already flying: route → circuit worked,
circuit → the same circuit didn't. Fix: twin paths (`SV_Path_Ladon<Key>LoopB`, `RageB`), laps alternating
(`survival_events.py` `ladons()` / `build_ladon`, `build_survival.py`). **The heavy bombers' loops restart
into themselves the same way** (`survival_events.py` ~line 1344); not changed, nothing reported.

### F6. VOID WATCHER flies tight circles — same cause as F5; fixed in the build scripts (needs a rebuild; not in fix1)
s2 host, 10:48-10:55: 1.0-6.7 km from the airfield, mostly SW, a new heading every 30 s. The orbit (one path
restarted into itself on `SV_AwacsLap`) was never flown past lap 1. Twin `SV_Path_VoidWatcherOrbitB`; orbit 7 km
(tester's ask); the Lua backstop `lost_km` 18 → 12 (in fix1).

### F7. Crash on Quit Mission — open
- **s4 host** 13:40:38: "migration: the next hosts ...", "world: PL_MainMenu", "LiveUnitSpawner is gone", then
  an access violation reading 0x130c3b64f0 at `AceCombat8+0x187958c`. Only one game frame in the stack. Joiners
  asked for the whole picture 3 times in the 90 s before.
- **s2 joiner** "crashed on quit": host migration ("AA GUN built for the room"), a pause, then nothing.
- **s1 host:** `EXCEPTION_ACCESS_VIOLATION 0x0` while DOWN and spectating, after a routine enemy respawn.
- **To do:** symbolize the minidumps (`UEMinidump.dmp`) against the game's exe. Check what of ours runs or holds
  objects during level teardown: the runtime's `SV_CoopTrack` / `SV_CoopBind` entities (`runtime/coop.c` CoEnt
  refs: weak or not?), hooks, and the Lua ticks after "world: PL_MainMenu".

### F8. Smaller items — open
- **The Ladons' wings don't move** (s3 notes): the VariableWing parts aren't animated. Cosmetic.
- **The host's plane does a wheelie on the ground** on the joiner's screen (s2 bug 4): the stand-in's pose while
  landed. No log data.
- **Ladon pass counting:** Lua logged "pass over the airfield (2)" at 12:02:34 with the Ladons 17 km away. Check
  how passes are counted against the flag.
- **The client's "N of M bound" report** may be misleading (see F1).
- `perf` from s5: the co-op part takes 33 % of the Lua tick (5.7 ms average, 28 ms worst).

### F9. Things that worked (from the tester notes)
- Restarting after quitting to the menu (s3 test 5): no crash.
- The DOWN loiter, seen on the host's map, circled the airfield (s3 test 2). The joiner saw the downed marker
  where the plane went down.
- VOID WATCHER took off and fired its ESM (s3 test 4).
- The STORE freeze while the host is in the STORE is known and parked (RE_PLAN.md on `claude/re-plan`).

## 3. Where the code is
- **Branch `claude/coop-fixes`** (off `COOP2MP` 0.73.58, pushed): all of F1-F6 plus tests (`director_test`
  soft resync, `defences_test` 7 km orbit). Commit 57dce73, then the tester sheets and this folder.
- **fix1 zip:** F1-F4 and `lost_km` applied to 0.73.70's Lua; VERSION `0.73.70-coop2mp.71-fix1`. No native or
  package changes, so no F5 / F6.
- **Checks run:** `lua_check`; the co-op revive / migration / ground / landing / settings / fire tests; defences,
  director, audit, late rounds, profile, stats, heavy, spaceport, bosses, lua_load. All passed, on a Lua 5.4
  from `lupa` wrapped as `build/checks/lua.exe` (lua.org is blocked from the cloud container). The Python half of
  `defences_test` needs game data and didn't run. **Nothing has run in game.**

## 4. For the UltraCode pass
1. Get the 0.73.70 source pushed. Merge `claude/coop-fixes` into it, or rebase it. 0.73.70's Lua is also in
   `builds/` if the source can't be found.
2. **Re-read every log independently**, by session and by system, to check this document; don't take its causes
   as given. The sweeps worth running: coop sync (sp / bd / rs / jn / strays / torn), specials (Ladon, Alicorn,
   Spaceport), allies (VOID WATCHER, MOONCHILD, SNIPER, ships, defences), STORE and economy (pay audit lines,
   credits), DOWN / revive, crashes (the three minidumps plus the guard lines), perf.
3. **Find why copies go unbound** (F1, still to check). That's the real root; the soft resync only stops the damage.
4. **Find the quit crash** (F7).
5. **Confirm F5's hypothesis** in a test build: the Ladons should log pass 3, 4, ...; VOID WATCHER should stay
   about 7 km out. If it holds, record a hard rule in AGENTS.md and apply the twin-path fix to the heavies' loops.
6. Once a test confirms them, record as hard rules: the soft resync, the shared-label relabel trap, and the
   path-restart rule.
