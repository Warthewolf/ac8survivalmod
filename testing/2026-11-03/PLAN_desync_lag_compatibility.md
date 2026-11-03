# Survival COOP: Desync, Lag and Compatibility Plan

Nov 3, 2026 · @War

The co-op runs on 0.73.76 (gloom's to round 28, Shake Shack's to round 46, Saint Alessia's two with Shazzy) show seven problems that need fixes: enemy copies dying early on joiners, Lua lag that grows over a long run, a rejoining player's old aircraft staying on everyone else's screen, a run that ends while a player is still loading in, two crashes tied to Survival (one on quit, one at the round 3 bomber raid), one-shot deaths from a scripted missile, and leaderboards that take no run from the co-op builds. Each fix below is Lua-first, comes with the log line that proves it, and is checked in a test session before the next phase starts. Mod compatibility, skin mods first, is researched alongside. The goal is 1.0.0 with no major crashes or bugs; the release bar below says what that means.

## The 1.0.0 release bar

The goal is a 1.0.0 release with no major crashes or bugs. It ships when a release candidate passes three co-op sessions of 2 hours or more with 3 or more players, no crash, and every row below holding. From the first release candidate the build is frozen to fixes only; new features (round modifiers and the rest of the Improvements doc) come after 1.0.0.

| Area | 1.0.0 needs | Where it stands (logs of 2026-11-02/03) |
| --- | --- | --- |
| Crashes | No crash in the three sessions; the quit crash (F1) and the bomber-raid crash (F2) fixed and not seen again | Both repeat: two PCs for F1, twice on one PC for F2 |
| Enemy copies | No invisible or unhittable enemies; no `not spawned here` lines on any joiner | Up to 26 refused spawns in one long run |
| Fair deaths | No one-shot from a scripted weapon; no boss part left behind after its round | 3 one-shots; leftovers in every long run |
| Round flow | No round waits more than 2 min on its last enemy; the run never ends with a player loading in | Waits up to 9 min; one wrong run-over |
| Performance | Host Lua tick 25 ms or less on average, no half-tick over 100 ms, through round 30 with 4 players | 35-95 ms, freezes up to 1.65 s |
| Economy | The agreed changes in; joiners paid only for their kills; the Spaceport paid per ship | Two money bugs |
| Leaderboards | Solo and co-op runs from the release build reach Discord, co-op on its own boards | Co-op runs never sent; every COOP2MP run refused |
| Specials | Every special played on the release candidate, the Spaceport capture and retake included | Retake never played |
| Mods | The compatibility list in the readme; a warning when players' mod sets differ | Not started |
| Release | Source tagged `v1.0.0` on GitHub; the build registered on the leaderboard; readme with "after a crash, send this"; version `1.0.0` everywhere (the mod, the co-op version check, the leaderboard) | 0.73.59-0.73.76 not on GitHub |

## Where we are

One cause, the enemy copy desync, explains most of what players reported; the lag and the rejoin problem are separate. All numbers below come from the logs of 2026-11-02 (gloom hosting dukka; Shake Shack hosting liljojofett, mobi118, Amia and Jimmy the Brown; Saint Alessia hosting Shazzy and scaraboy13), plus Shazzy's two crash reports.

| Problem | What players saw | Log evidence | Likely cause | How sure |
| --- | --- | --- | --- | --- |
| Enemy copies die early on joiners | Invisible enemies that keep a target box and can't be hit; the host has to kill them | dukka: about 60 flights with a plane shot down by the ships' copies before the host's kill, up to 700 s early. mobi118: 116. Both: `a copy here couldn't be finished (health N after)` | `SetMinHealth(0.1)` drops to 0, so copies have no floor; the host's `hp` update then writes health back onto a dead copy | High: the project's own notes record the 0.1 to 0 truncation; every stuck flight had an early local kill |
| Enemies missing on joiners | Round 28 "no enemies" for dukka; fewer enemies than the host | dukka: 22 refused spawns over 7 flights; 14 of wave 2's 20 aircraft never appeared. mobi118: 26 refused, one flight missing from round 22 to the end | The dead wreck still counts as alive, so the game refuses that flight's next spawn (hard rule 16) | High: 128 of 128 flights with no early kill spawned fine (437 of 437 for mobi118) |
| Rounds that hang | Rounds 20-something and 27 kept going after every enemy on screen was down | Round 25 ran 19 min: a Typhoon died on dukka's side at 11:16:45, the host's kill came at 11:28:25 | Host planes that joiners can't see or hit, so the host hunts them alone | Medium: needs the host's log of that run |
| Lag that grows over a run | Stutter late in long runs | Host Lua tick 15 ms at round 1, 80-85 ms at round 46, worst half-tick 782 ms. mobi118 26 to 70 ms, worst halves 440 ms median | Lists of game objects that grow all run (allies part 0.5 to 10 ms, untimed rest 6 to 36 ms) | Medium: the growth is measured, the list isn't found yet |
| Old aircraft after a rejoin | liljojofett left in a Su-47, came back in another plane, still a Su-47 to everyone | Host 01:59:00: `player 2's loadout changed: their real plane here keeps the one it was spawned with` | Built in on purpose since the 0.73.11 crash: a live player plane is never replaced mid-level | High: the log says it |
| VALKA's sky and song on joiners | No red sky or song for dukka in gloom's run | Shake Shack's run: mobi118 logged `the host's VALKA mood on`; gloom's run: no such line | The mood is forwarded from one of VALKA's start paths only (hypothesis) | Low: the code isn't on GitHub |
| Run ends while a player is loading in | VALKA downed Saint Alessia and Shazzy; scaraboy13, who had just joined, fought her alone and killed her on his screen only, while the others still saw her flying | Host 16:54:15: "every player in the mission is down (2)"; scaraboy13's plane arrived at 16:54:24; one of his hits reached the host (VALKA 22400 to 22100) | The run-over counts only players with a plane; a player whose link drops while loading misses the run-over message | High for the run-over; why only one hit arrived needs scaraboy13's logs |
| Crash on quit | Shazzy's game crashed as he quit while DOWN and spectating; cressendo's crashed the same way quitting from flight | Crash report, 16:57:02: game thread, UE4SS reading freed memory, called from Survival's Lua through main.dll; "LiveUnitSpawner is gone" one second before | Survival's Lua tick touches an object the closing level already freed, most likely the DOWN spectator's watched plane or its cameras | High: the identical crash on a second PC (cressendo, 2026-11-03), from flight, no antivirus |
| Crash on runway attack | Shazzy's game crashed twice as the round 3 bomber raid spawned | Crash report, 16:06:37: a worker thread called a null function pointer in game code (AceCombat8.exe+0x7ddc6ac); no mod code on the stack | A game worker task still holding the previous bomber flight's unit, which Survival destroyed 3-5 s earlier for its respawn (not the runway: Shazzy was airborne the first time) | Medium: the same spawns 2-3 s before both crashes; the object needs reverse engineering |
| One-shot deaths | cressendo one-shot twice in round 6 right after buying airframe upgrades; "the FA-36 upgrade doesn't work" | Hits of exactly his whole health (150, 150) from BP\_MSL\_certain\_kill\_a0 fired by F/A-18Es; liljojofett the same in round 41 (114) | Survival's F/A-18E rows carry Mission 22's scripted sure-kill missile in slot 5, and their AI fires it | High: the weapons log lists it on those rows only |
| Leaderboards don't work | No co-op run ever reached the leaderboard | Every co-op log: "leaderboard: a co-op run; not sent (CFG.coop.leaderboard)"; the server's version check takes -coop.N but not -coop2mp.N | Co-op sending switched off, and the server would refuse COOP2MP builds' runs (solo ones too) as "bad mod version" | High: both are in the code |

What worked: no crash and no guard fault on any of the three Shake Shack logs, 7 revives, Amia dropping and rejoining about 10 times, VOID WATCHER 1's 6 km orbit, and every special in the rotation.

## Step 0: the 0.73.76 source on GitHub

Nothing below can be built until the source of the build players are running is in the repository. The newest code on GitHub is `COOP2MP` at 0.73.58 plus `claude/coop-fixes`; 0.73.59 to 0.73.76 exist only on the build machine. The build zip is now over the upload limit, so it can't come that way.

1. On the build machine, commit 0.73.76 as it stands and push it to a new branch, `wip/0.73.76`.
2. Push the build tools changed since 0.73.58 too (`tools/`, `runtime/`), so a build can be made from the branch.
3. Fallback if a push isn't possible: send only the `Scripts` folder of the installed mod, zipped. Workstreams A, C and D need only `sv_coop.lua`; B needs `sv_main.lua`, `sv_allies.lua` and `sv_shop.lua` as well.
4. Merge `claude/coop-fixes` (the soft resync and pay fixes of 2026-11-01) into it, or check those changes are already in 0.73.76.

- [ ] 0.73.76 pushed to `wip/0.73.76`
- [ ] `claude/coop-fixes` merged or confirmed already in

## Workstream A: the enemy copy desync

Goal: an enemy copy on a joiner's game goes down only when the host's plane does, and no flight ever stays blocked. A1 and A2 remove the cause; A3 cleans up if a wreck still slips through; A4 to A7 check the side effects and help players find the last enemies. A8 to A10 fix the run-over and VALKA problems from Saint Alessia's run.

| Fix | Where | Change | Proof in the logs |
| --- | --- | --- | --- |
| A1 A real health floor | `sv_coop.lua` bindCopy, bindGround, killCopy | Write the `MinHealth` field to 1.0 (fallback `SetMinHealth(1)`), as the revive floor and real planes already do. killCopy writes it back to 0 before the kill | Joiners: almost no `went down to the ships` lines for enemy copies; no `couldn't be finished` |
| A2 No reviving dead copies | `sv_coop.lua`, the `hp` handler | Skip any copy whose health is already 0 or below; count the skips | New line in the sync report: `hp for N dead copies skipped` (should stay near 0 once A1 is in) |
| A3 Clear a stuck flight | `sv_coop.lua` doSpawn; runtime if needed | When a flight counts as alive but nothing of it is tracked, also take down its planes marked down that still exist. If it is still alive after 6 tries, a new native call (`SV_Recycle(unit, 1)`) takes the unit off the list anyway | `coop: <unit> unstuck: ...`; no `not spawned here (its last flight is still up)` |
| A4 Local allies' fire | `sv_coop.lua` clientTick | Check that damage the joiner's copies of allied ships and defences do to enemy copies is still taken off what goes to the host (the 0.73.23 backstop) | `coopfire: copy N lost X, Y of it ...` lines on joiners with ships up |
| A5 Allies for show only (option) | `sv_allies.lua`, row setup | If A4 shows double damage, give joiners' ally copies damage-0 rows, as the player stand-ins already fly (`_svcp`) | Decided after test session 1 |
| A6 Sync report | `sv_coop.lua` COOP.syncReport | Each minute: copies held at the floor waiting for the host, the longest wait, flights refused | One line a minute on every joiner |
| A7 Last enemies on the map | `sv_rounds.lua` (host) | When a round has had no kill for 90 s, ping its last 1 to 4 enemies on the minimap (Mission 22's LiveBattleNavigationExecution, as the raid pings do) | `round: last N enemies pinged ...`; rounds stop hanging |
| A8 Hold the run-over for a player loading in | sv\_down.lua, the run-over check (host) | Don't end the run while a player who linked in the last 90 s has no plane yet: they can still fly to the airfield and revive the others | down: run over held: player N still loading in |
| A9 Run-over for late joiners | sv\_coop.lua (host) | A player who links, or links back, after the run-over gets it again, and the resync a joining player receives carries it | Every joiner logs the run-over, including one who was loading |
| A10 VALKA leaves a down player alone | VALKA's anomaly field | No control scrambling (SV\_Invert) while that player is DOWN: it scrambled the host's spectator camera | No ANOMALY FIELD callout on a player who is DOWN |

A1 changes when a joiner's own kill is paid: the copy now waits at 1 HP for the host's kill, one round trip later (about 300 ms for the far players in Shake Shack's run). The kill and its credit stay the joiner's.

## Workstream B: lag that grows over a long run

Goal: at round 40 with 5 players, a Lua tick of 25 ms or less on average and no half-tick over 100 ms, flat from round 1 to the end. Today Shake Shack's host went from 15 ms to 80-85 ms over 46 rounds, and Saint Alessia's (4 players) from 35 ms to 95 ms by round 13, with one 1.65 s freeze; and the cost grows with time played, not with enemy count: rounds 1-8 and 45-46 created about the same number of enemies (24-26).

&#91;embedded content: Shake Shack's AC8SurvivalMode\_lua.log, 2026-11-02 · 49 perf lines, rounds 1-46\]

The allies part and the untimed rest grow steadily with time played; the co-op part doubles once, around round 18, then holds.

Measure first, because the biggest share (the untimed rest) can't be traced yet:

1. **B1 Time everything.** Wrap every call the tick makes in the perf timer so the untimed rest gets names. Add the size of every long-lived list to the perf line: `planes`, the co-op copies and flights, torn copies, the allies' and defences' actors, ESM fields, stats tables. First suspect: `planes` keeps every aircraft of the run (the host's run had 1,941 air kills) and some parts loop over all of it every tick.
2. **B2 Prune.** Drop down or gone entries from every list a few seconds after they go (stats keep a summary). This is the rule kept since 0.73.29: a game object kept between ticks is dropped the first time it's invalid.
3. **B3 Spread the allies part.** Visit a share of the allies and defences each tick, as the plane sweep visits an eighth of the planes.
4. **B4 STORE work only in the STORE.** Shop texts, labels and the ammo panel only while the STORE is open, and labels only when they change. mobi118's shop part averaged 12.5 ms with a 488 ms worst.
5. **B5 Ladon rounds.** The hits part jumped to 7.5 ms (27% of the tick) in gloom's Ladon round: cap or spread what it scans per missile.
6. **B6 Native guard rate.** liljojofett's game ran the target-search guard 170,000-416,000 times a second, against about 30,000 on the host. Find out why (busiest class 17, event type 27) and whether it costs frame time; it isn't in the Lua tick.
7. **B7 A solo soak test.** A solo run to round 20 with allies bought every few rounds, comparing perf lines, so each change is checked without five players.

## Workstream C: a player who rejoins in a different aircraft

Goal: when a player leaves and comes back in another aircraft, everyone sees the new one within a few seconds, without the crash that replacing a live player plane caused in 0.73.11.

In Shake Shack's run liljojofett left at 01:56:53 in a Su-47 and rejoined at 01:57:11. His own log shows the Rafale M (`BP_PlayerPlane_PP0014_rflm`) afterwards, not an F-4. Everyone kept seeing the Su-47 until the level ended.

1. **C1 Tell a rejoin from a loadout change.** Mark a player who left (`sys|left`) and joined again. A loadout or airframe change from someone who never left keeps today's rule: it applies next level.
2. **C2 Set the old plane aside, never destroy it.** Hide it, turn its collision and tick off and move it out of the way, as host migration already does with the old host's plane.
3. **C3 Spawn the new one.** Spawn a real plane of the new airframe and loadout the way a player joining mid-run gets one, then bind their stream to it.
4. **C4 AI stand-ins.** A stand-in AI plane can't change airframe once up. On a rejoin, use a free stand-in slot of the new airframe instead.

Proof: `coop: player N rejoined in <new> (was <old>): old plane set aside, new one spawned`, and the other players see the new aircraft. Open question: confirm with liljojofett which aircraft he picked; the log says Rafale M.

## Workstream D: VALKA's mood on every joiner, and her railgun removed

It already works on one of VALKA's start paths: in Shake Shack's run (round 25, "decoys down, VALKA attacks") mobi118 logged `the host's VALKA mood on: the sky red and her song here too` and the mood went off after her fight. In gloom's run she came mid-round 16 after `CATASTROPHIC LEVEL ANOMALY`, and dukka's game logged no mood at all and no music change for the whole run.

1. **D1** List every way VALKA starts (her own round, a mid-round anomaly, a forced start) and send the mood from one place that all of them pass through.
2. **D2** Send the mood again to a player who joins or resyncs while she is up, and send "off" to everyone when she goes down or the run ends.
3. **D3** Check the special-round music of the other specials reaches joiners the same way; dukka's music never changed after 09:46.
4. **D4 Her opener railgun really removed.** Saint Alessia, 2026-11-03: "Valka left her railgun in the sky, it kept trying to shoot me near the base from her round onwards." Her opener's dummy railgun (`SV_Unit_ValkaEml`) is removed with `RE_SV_ValkaEmlRemove` (`LiveDestroyUnitExecution`); the event fires, but the runtime's unit list still shows the unit `1 of 1 aircraft alive` to the end of the run (round 9 to 18 here, round 25 to 46 in Shake Shack's run). Remove it another way (its object `LiveSetActiveGameObject` false, as the flights' `RE_SV_FlightOff` does, or the runtime's recycle), then check `SV_UnitAlive` 2 s later and log `special: VALKA's opener railgun removed` or `NOT removed (N alive)`. Do the same on joiners' copies.
5. **D5 A smaller arrival flash.** The user, 2026-11-03, with a screenshot: VALKA's flash when she arrives covers most of the screen. It's her opener's lens flash (AC7 Mission 18's, `SPC.V.flareStart`), whose four elements are sized as a share of the screen, not in metres (`CFG.specials.valka.flare.elements`: Glare 1.6, Ring 1.2, Shine 0.9, Bokeh 0.4). So it's as big 14 km away as close up. Halve them through a new `[specials.valka]` setting, `flash_size_x = 0.5`, so it can be tuned without editing Lua; log the sizes used on the `VALKA's flare` line. The burst at her shot (Mission 23's flash, `flash_scale` 12, 4 layers) stays unless it's still too big; put its size in the ini beside the new setting so both can be tuned. Also find out why none of the three VALKA fights in the 0.73.76 logs logged her black-hole portal (`special: VALKA's portal at ...`), which should open 3 s before the shot.

Proof: `the host's VALKA mood on` on every joiner in every VALKA appearance, and `off` after it.

## Workstream E: mod compatibility research

Goal: know which mods players run alongside Survival, which work solo and in co-op, which must match across players, and which break it, then tell players in the readme and in game. Skin mods come first because they're the most common.

What the logs already show:

- Shake Shack (host) ran HangarModelFix, SimpleFreecam, SkinSlotText, SkinStudioSaveBackup and SkyLive; mobi118 ran SkinSlotText and SkinStudioSaveBackup; liljojofett none. No crash or fault in that run points at them.
- 2026-10-31: Twelve's SPWeaponCustomizer 2.3 and AC8WeaponSwap 1.1.0 crashed the host. His plane fired weapons the stock plane on other games doesn't have. Runtime 0.32.5 now drops such shots, but the games still disagree.
- Co-op sends each player's paint as an id (`26005001/255/94003`); each game draws it from its own files.
- UE4SS's log lists Lua and C++ mods only. Pak-only mods in `~mods` (most skin mods) are invisible to us today.
- Saint Alessia (host) ran falken-us4ss, AC8TLSHoming, AC8CockpitFreedom, AC8ModSettings, AC8UltrawideHUD, FovMod, SkinSlotText and SkinStudioSaveBackup. Her Falken (`PP9001_falken`) comes from falken-us4ss, so Shazzy's game had no such plane and showed her as an AI F-16 stand-in. AC8TLSHoming changes the laser's homing on her game only.
- Shazzy's PC also loads another native mod, PWMkINative, and VIPRE antivirus injects into the game. Neither is on his crash stacks.

| Kind of mod | Examples | Risk for Survival | Co-op question |
| --- | --- | --- | --- |
| Skin and texture paks | Aircraft skin replacements | Virtual-texture skins (hard rule 44: our own VTs crashed loading); a skin of the X-40A gear material (`MI_PP0016_x40a_Gear`) changes VALKA's paint | Does a player without the mod see stock paint, the wrong paint, or a crash? |
| Skin tools | SkinSlotText, SkinStudioSaveBackup | Custom skins kept in save data, extra skin slots | What does another game draw for a custom skin id it doesn't have? |
| Sky and lighting | SkyLive | Fights VALKA's red sky and the Mission 16 sky (both edit the sky at run time) | Does each game's sky stay its own? |
| Gameplay values | SPWeaponCustomizer, AC8WeaponSwap, AC8UnitHealth, AC8WeaponValues | Weapons, ammo or health differ between games: desync; leaderboard runs count as edited | Must every player match, or must it be off in co-op? |
| Camera and UI | HangarModelFix, SimpleFreecam, SkipIntro | Menu and camera hooks next to Survival's menu pages (hard rule 52) and spectator camera | Low risk; check the menus and DOWN spectating |
| Native DLLs | Stonehenge Returns' main.dll, ac8weaponlib | Hooks on the same game functions; Survival must chain onto them | Same as solo |
| Whole-table overrides | Mods replacing DT\_NPC, DT\_NPC\_Model, DT\_SpeakerTable | Survival adds rows at run time; a table loaded later could drop them | Same as solo |
| Modded player planes | falken-us4ss (the Falken as PP9001) | Other games have no blueprint for it, so they show a default AI F-16 stand-in | Show the closest AI airframe instead (E7) |

Research steps:

- [ ] E1 Inventory: the most used AC8 mods (Nexus, the Discord) and every tester's `~mods`, `LogicMods` and `ue4ss/Mods` folder listing
- [ ] E2 A mod list in our log: the runtime logs every pak / utoc and enabled UE4SS mod at start, with sizes and a fingerprint
- [ ] E3 Solo matrix: each mod alone with Survival (menu, a run to round 6, a forced VALKA, the STORE, a DOWN spectate)
- [ ] E4 Co-op matrix: one player with the mod, one without; what each sees, and any desync lines
- [ ] E5 Skin cases: a stock-skin replacement pak; a virtual-texture skin; a Skin Studio custom skin in co-op; an X-40A skin while VALKA flies
- [ ] E6 Write `tools/re/MOD_COMPAT.md`: each mod rated Compatible / Cosmetic, own screen only / Must match in co-op / Incompatible
- [ ] E7 The Falken's stand-in as an ADFX-02: Survival already builds an AI ADFX-02 for its Reaper aces (`SV_Model_adfx`); map `falken` and other modded planes to their closest AI airframe in `CFG.coop.airframes`

What we ship from it: the compatibility list in every release zip's readme; each player's mod fingerprint in the co-op hello, with a host callout like `MOD SETS DIFFER: <mod>` for gameplay mods (a warning, not a refusal); gameplay mods marking a leaderboard run as edited.

## Workstream F: the crashes

Goal: no crash on Quit Mission, and the runway crash identified and guarded. Both crash reports are Shazzy's: their times and the game's uptime match his two sessions to the second.

### F1 Crash on quit (Shazzy 2026-11-02 16:57:02, cressendo 2026-11-03 10:42:25)

The same crash on two different PCs: the same UE4SS instruction (`UE4SS.dll+0x2ab5bd`, reading freed memory), the same path through our runtime (`main.dll+0x1abe8`, `+0x68b7`), the same register values. Both times the player paused, quit, and the game crashed on the game thread about one second after our runtime logged `this level's LiveUnitSpawner is gone (the level is ending)`. Shazzy was DOWN and spectating; cressendo was flying, fresh out of the STORE. cressendo's PC has no antivirus hooks and no other native mod, so neither of those is the cause. On 2026-11-01 one host crashed on Quit Mission too. It's ours and repeatable: Survival's Lua tick (run on the game thread through UE4SS's `ExecuteInGameThread`) is still calling into game objects in the first second of the level's teardown.

1. **F1a A teardown gate the runtime sets.** The runtime already notices the level ending first (`LiveUnitSpawner is gone`). It sets a flag there that Lua reads at the top of every tick half; while it's set, no Lua part calls into a game object, and the runtime's own Lua functions refuse to touch objects, until a new Survival level is up.
2. **F1b Drop, don't walk.** On that flag, every list of game objects Lua keeps (planes, copies, allies, the DOWN spectator's watched plane and cameras) is dropped, never walked or restored.
3. **F1c Name the runtime's frames.** Build `main.dll` with a map or PDB file kept per build, so the runtime frames in a crash report can be named.

Proof: Quit Mission ten times in a row from flight, the STORE and DOWN spectating, no crash; the crumbs show the gate closing before the level goes.

### F2 Crash at the round 3 bomber raid (Shazzy, 2026-11-02 16:06:37 and 18:02:16)

Twice on Shazzy's PC, a game worker thread crashed in the same game system (`AceCombat8.exe+0x7dd5000` to `+0x7dde000`, callers `+0x7ddcedd`, `+0x7ddd93d`, `+0x7ddd664`, `+0x7ddb570`, `+0x7dd54ed`). No Survival, UE4SS or antivirus code is on the stack, and it isn't the weapon target-search code the runtime already guards. The second dump holds the crashing code: the function at `+0x7ddb860` pins a weak pointer kept at `+0x50` of an object (`mov rbx,[rcx+50]`, then the reference count at `[rbx+8]`), and that object had already been freed (the pointer was garbage). The first crash, a call through a null function pointer, fits the same freed object.

Both times, in round 3 as the bomber raid started:

|  | First crash | Second crash |
| --- | --- | --- |
| The last bomber flight's unit destroyed for its respawn (`EA_Unit_01_Air0`) | 16:06:31 | 18:02:11 |
| The 6-plane heavy flight's first spawn (`EA_Unit_01_Air1`) | 16:06:34 | 18:02:14 |
| Crash | about 16:06:36 | about 18:02:16 |
| Shazzy | airborne; the host on the runway | at the airfield |

So it isn't the runway or the stand-in: the common factor is the raid's spawns, right after Survival destroyed the previous bomber flight's unit. Other joiners got through the same spawn dozens of times (mobi118 11, dukka 4, cressendo 4, Shazzy's own second session 2), so it's a race: a worker task still holds something of the destroyed unit when the memory is reused.

1. **F2a Identify it.** On the build machine, find what object the function at `0x7ddb860` and its callers walk (the first crash's object class table is `AceCombat8.exe+0xcbf8550`), and which list keeps the destroyed unit or its planes.
2. **F2b Destroy later.** Don't destroy a recycled flight's old unit actor at the moment of the next spawn. Recycle shot-down flights in the break between rounds, or unregister at once and destroy the actor 30 s or more later, once worker tasks have let go. Check hard rule 16 still holds (the flight spawns again).
3. **F2c Guard it.** If F2a finds a check the runtime can wrap, put it behind the runtime's fault catcher as the target search is.
4. **F2d Reproduce it solo.** A test key that runs a bomber raid's spawns right after recycling the last raid, 20 times.

Proof: F2d's 20 runs clean, and no repeat in the test sessions on Shazzy's PC.

### F3 Crash data from players

The readme gets a short "after a crash, send this" note: the newest `UECC-...` folder from the game's `Saved\Crashes` (`UEMinidump.dmp`, `CrashContext.runtime-xml`), the Survival logs including `AC8SurvivalMode_crumbs.prev.log`, the round, and what you were doing. The minidump reader used for these two crashes goes into `tools/checks` so any crash report can be read without the game's symbols.

## Workstream G: balance and player-facing fixes

Goal: no death a player can't play around, and upgrades that show what they bought.

1. **G1 No certain-kill missiles on enemies.** Survival's F/A-18E rows (`f18e_common_sv`, `_svb`) are copies of Mission 22's allied F/A-18E, whose fire-control slot 5 is `BP_MSL_certain_kill_a0`: a scripted sure kill that takes all of a player's health whatever their upgrades (hard rule 36). The director's salvos already refuse that airframe, but its own AI fires it: cressendo twice in round 6 (150 HP each), liljojofett in round 41 (114 HP). Put a plain missile in that slot (or empty it) on Survival's copies, and make the build fail if any enemy row carries a `certain_kill` weapon.
2. **G2 Upgrades survive the airfield.** Every airfield stop, the game puts max health back to the airframe's stock (120 on the FA-36) and Survival restores the upgrade about a second later. The hit log records each reset as damage (`-30 HP`, `-60 HP`, "health now 100% (120 HP)"), and a player who looks then sees stock health, so cressendo thought the FA-36 upgrade didn't work. Restore it in the same tick the game resets it, and don't count the reset as a hit.
3. **G3 The economy.** The changes in the separate proposal, Survival COOP: Economy Change Proposal, agreed on 3 November with its recommended answers: C1-C6 as written, no fourth upgrade tier until the test says it's needed.
4. **G4 Harvest's health and size.** A tester of the 5-player run: "it took us 30+ missiles ... to down a single aircraft and there were over twenty of them per wave". Harvest's planes fly the campaign's named-ace bodies, about 7,000 HP each, 9,900-10,725 HP from round 28 with the late x1.5 (Inferno's Su-57: 1,564), up to 80 a round, 30 at once; its rounds ran 8-15 minutes. Set each tier's ace health from the tier, not the airframe's row (Reaper wingmen about 1,800, the named lead about 3x); ace rounds 12-24 squadron planes, 6-10 up at once; Harvest every other ace round from round 28. Details: the Improvements doc, "Tester feedback".
5. **G5 VOID WATCHER 1's limits.** Its ESM field covers the whole fight all the time (25 km, refired every 20 s) and one lasted 92 minutes, from round 16 to 34. It serves 3 rounds then lands, its price rises x1.25 a purchase, its field 8-10 km, and a strike flight goes after it each round it's up.
6. **G6 Airstrike limits,** on top of the economy's C4: one per player per round, never on an ace squadron's flights, at most 4 planes hit, no automatic call.

Proof: no `certain_kill` in any hit or weapons line, the build check passing, and no airfield "hits" in a run with upgrades bought.

## Workstream H: leaderboards with a co-op section

Goal: every finished stock run, solo or co-op, reaches the leaderboard, and co-op runs have boards of their own. Today nothing from the friends' builds gets there, for three reasons:

1. **Co-op runs are never sent.** `[coop] leaderboard` is `false` by default; every co-op log ends with `leaderboard: a co-op run; not sent (CFG.coop.leaderboard)`.
2. **The server refuses every COOP2MP build, solo runs included.** It takes versions like `0.72.2` or `0.72.2-coop.20` (`MOD_RE` in `leaderboard/src/index.js`); COOP2MP builds send `0.73.76-coop2mp.77`, so a run comes back "bad mod version".
3. **The server has no teams.** Its limits and boards are per pilot (for example at most 70 air kills a round), so a 5-player run would also be refused as "too many air kills".

The fix:

1. **H1 Accept every build tag** (server only; can ship first): versions `1.0.0`, `0.73.76`, `0.73.76-coop.20`, `0.73.76-coop2mp.77`. Register each build players get on the admin page (its hash), as the README says.
2. **H2 One team run per co-op run, sent by the host.** Today's run plus `players` (2-24) and a `squad`: each player's pilot name, aircraft, kills and revives given. Joiners don't send; if the host left, the player who took over by host migration sends it. The run id is the host's, so a run is never counted twice. The room's rules are checked as today (`LB.edited(true)` already covers co-op), and co-op runs go on by default.
3. **H3 The server takes team runs:** stored with their squad, limits scaled by players (air kills up to 70 a round x players), the same score formula and difficulty multiplier as solo.
4. **H4 A CO-OP section on Discord:** a third pinned message with the top 10 by round and by score for 2 players, 3-4 and 5+; co-op records (longest run, most specials beaten, most revives); this week's co-op best. `/leaderboard coop [size]`; each co-op run's post in #survival-runs lists the squad; a pilot's `/pilot` includes their co-op runs.
5. **H5 Tests:** the Lua leaderboard test and `worker.test.mjs` cover a team run, one refused for too many kills for its players, a duplicate, a COOP2MP version and a solo run from a COOP2MP build.

Proof: the next co-op session's run appears once in #survival-runs with its squad and on the CO-OP board; a solo run from the same build appears on the solo boards.

## Workstream I: the Spaceport round

Goal: the assault, the capture and the retake all play through and end cleanly, solo and in co-op. The evidence for each item (S1-S14) is in the Improvements doc's Spaceport section; the round was played once, and nothing after a capture has ever been played.

1. **I1 Count ships by their hull** (S1, S2, S5): pay and call out a ship once when its hull goes, finish off its turrets with it, and treat it as afloat only while the hull lives.
2. **I2 Co-op money** (S3, S9): reword the landing craft's and troop vehicles' pay reasons so joiners get them (they get none today: the host had 28 craft payouts, mobi118 0), and send the escape penalty to every game.
3. **I3 Never strand the fleet** (S4): remove it when no retake can follow, and let a later Spaceport remove leftovers instead of refusing to start.
4. **I4 Withdrawn flights destroyed, not just deactivated** (S6), so the pool doesn't shrink after a capture.
5. **I5 Rockets and debris that always end** (S7, S8): a rocket timeout, an escape accepted only after a real climb, debris only after a split, debris counts stored at spawn.
6. **I6 Clocks that pause while a solo player is landed** (S10), as the shuttle's countdown does.
7. **I7 Safe settings and migration** (S11, S12): round the capture per troop; carry the pending retake through host migration and show it on joiners' NEXT row.
8. **I8 A fair fight** (S13): reserve the Ford's deck flights when the round is planned.
9. **I9 Play the rest of it:** a session that forces the assault until a capture happens, then the retake, the rockets and the island enemies, before 1.0.0.

Proof: one session where the spaceport is captured and retaken; each ship paid once; joiners paid for craft; the round never waits on a lone turret or rocket; a later Spaceport starts.

## Workstream J: a busier carrier and helicopter troops for the Spaceport

Goal (user, 2026-11-03): more launches off the Ford, and helicopters that land troops at the spaceport, so the assault threatens the capture. Both are new features: they go in before the first release candidate (the feature freeze).

**J1 The Ford's own deck flights.** Today the deck takes a free 2-ship from the round's pool (`deckFlight`), and in round 13 the round's 22 fighters had taken them all: 2 launches of 8 planned ("no free 2-ship to launch"). Raising the numbers alone changes nothing.

1. Give the Ford dedicated deck units in the world data (8 two-ships, `SV_Unit_SpDeck_A`-`H`, carrier airframes: F-35C, Rafale M, Su-33, and the F/A-18E once G1 removes its certain-kill missile), with attack orders and the chase as the pool's flights have (`survival_events.py` POOL), never picked for a round.
2. Launch harder: first 15 s after the fleet appears (now 20), every 20 s (now 25), up to 6 flights up at once (now 4), 6 + 0.35 a round in a round (now 5 + 0.3; 10 at round 13), at most 16 (now 14). Every launch keeps coming until the Ford sinks, so sinking it first becomes the play.
3. A radio line when the deck launches, and "CARRIER SUNK" once (I1).

**J2 Helicopter troops.** Each Wasp already sends landing craft that put a troop vehicle ashore. The helicopters land troops at the spaceport itself, closer and faster than the beach.

1. **Research first (on the build machine, from the stock data dumps):** whether AC8 has a helicopter unit (its DT\_NPC row, blueprint, and whether its AI can fly a slow path down to a hover or a landing), and how a stock mission lands troops by air (Mission 26's `LiveChangeCarrierContainer`, and the carried-unit release of hard rule 5). Nothing in the repo answers this yet. If there's no helicopter, the fallback is a transport aircraft that drops its troops (the Land Aegis drop pattern).
2. **Waves:** from +60 s, every second Wasp wave, each Wasp afloat sends 2 transport helicopters (with 2 escort gunships if a gunship exists) along a low path to a landing zone at the spaceport. The landing zones come from the building check already built for the island enemies (`tools/spaceport_spots.py`: 20 m or more from every building).
3. **Landing:** on the path's finish (PathFinish triggers fire, hard rule 1), Lua spawns a troop vehicle at the landing zone, which drives into the capture as the landing craft's troops do (`capture_per_troop`), and the helicopter flies back out and despawns. A helicopter shot down before it lands takes its troops with it.
4. **Pay and callouts:** a helicopter pays as a landing craft (and reaches joiners, I2); "HELICOPTERS INBOUND: TROOPS FOR THE SPACEPORT" on the first wave; the wave summary line counts helicopters with the craft.
5. **Co-op:** spawned with SV\_Spawn, so joiners get copies as they do every unit; their troops and capture are the host's.
6. **Test keys:** one that sends a helicopter wave at once, for solo tests before a co-op session.

Proof: a Spaceport round where the Ford launches every planned flight, and a helicopter lands its troops and moves the capture meter; one where helicopters shot down early land nothing.

## Test sessions

Each phase ends with one co-op session: a host and at least 2 joiners, played to round 25 or later, with allied ships and defences bought. Before that, every change gets the Lua checks (`lua_check`, `lua_load_test`, the co-op tests) and a solo run.

What to play on purpose:

1. Buy allied ships and defences early (by round 8), so the ships shoot at enemies near the joiners.
2. One player leaves mid-run and rejoins in a different aircraft.
3. Play through a VALKA appearance (or force one) and a Ladon round.
4. One player runs a skin mod (session 2: the mods from E3-E5).
5. A third player joins in the middle of a fight, ideally during a special.
6. A player who is DOWN and spectating quits with Quit Mission; the host lands while a bomber raid comes in.
7. Note the round and the time of anything odd (an invisible enemy, a hung round, a stutter).

What every player sends, as one zip each, with the host named: `AC8SurvivalMode_lua.log`, `AC8SurvivalMode.log`, `AC8SurvivalMode_crumbs.log`, `AC8SurvivalMode_crumbs.prev.log` and `UE4SS.log`. After a crash, the `crumbs.prev` file and the crash report folder matter most.

| Check | Pass when | Where to look |
| --- | --- | --- |
| A1 floor | Joiners: enemy copies killed early by the ships drop from about 116 a run to near 0; no `couldn't be finished` | Joiners' lua logs, `kills: ... went down to the ships` |
| A2 no revive | `hp for N dead copies skipped` stays near 0 | Joiners' sync report |
| A3 no stuck flights | No `not spawned here (its last flight is still up)`; any `unstuck` line clears its flight | Joiners' lua logs |
| A7 hung rounds | No round over 10 min that isn't an ace-squadron round | Host's round callouts |
| B lag | Host tick 25 ms or less at round 25 and later; no half-tick over 100 ms; flat over the run | `perf:` lines, every player |
| C rejoin | The others see the new aircraft within 10 s | Host and joiners' `rejoined in` lines; players' report |
| D VALKA mood | `the host's VALKA mood on` and `off` on every joiner | Joiners' lua logs |
| E mods | Each tested mod rated; no crash with the cosmetic ones | E3-E5 notes, `MOD_COMPAT.md` |
| A8-A9 run-over | A player loading in keeps the run alive until their plane is in; every joiner, late ones too, gets the run-over | Host's "run over held" line; every joiner's run-over line |
| F1 quit crash | Quit Mission while DOWN and spectating, five times, no crash | Crash reports (none expected); crumbs |
| F2 runway crash | No repeat; F2c's solo test runs clean | Crash reports, crumbs.prev |
| G1 certain kills | No one-shot from an F/A-18E; the build fails on any enemy row with a certain-kill weapon | hit lines ("certain\_kill"), the build output |
| G2 upgrades | Upgraded health stays through every airfield stop; no airfield "hits" | upgrades: and hit: lines at each landing |
| H leaderboards | The co-op run appears once in #survival-runs with its squad and on the CO-OP board; a solo run from the same build on the solo boards | Discord; the host's "leaderboard:" lines; the admin page's builds list |
| I Spaceport | Captured and retaken in one session; one sunk line and one payout per ship; joiners paid for landing craft; a later Spaceport starts | "special:" and "credits:" lines, host and joiners |

## Order of work

&#91;embedded content: order of work · 5 phases to 1.0.0, 3 test gates\]

Phase 1 comes first because it removes the desync's cause and makes the lag measurable; each later phase starts only once the gate before it passes, and the last gate is the 1.0.0 release bar.

## Risks and open questions

- **A1 may hide a desync the other way.** If a joiner's hits stop reaching the host, its copies now sit at 1 HP forever instead of dying. The sync report's "longest wait at the floor" (A6) catches it.
- **The forced recycle (A3) could crash.** Taking a unit off with planes still counted alive may leave them in weapons' target lists, as in the crash of 2026-11-01. It ships only after a solo test, behind the target guards, and only as the last resort.
- **Set-aside planes (C2) pile up.** One hidden plane per rejoin stays in the level until it ends. Fine for a few rejoins; watch memory in long runs.
- **The lag source may be native.** If timing the untimed rest (B1) doesn't find it in Lua, the next place to look is the runtime's per-frame work (B6) and the game itself under five players.
- **Hung rounds need the host's log.** Rounds 20-something and 27 of gloom's run can only be confirmed from gloom's `AC8SurvivalMode_lua.log`.
- **Which aircraft did liljojofett rejoin in?** The log says Rafale M; the report said F-4.
- **Mod research needs testers' folders.** Pak-only mods don't show in any log until E2 ships.
- **Why did only one of scaraboy13's hits reach the host?** His copy of VALKA died on his screen while the host's kept 22,100 of 22,400. Needs scaraboy13's logs from that session.
- **The runway crash needs the game's code.** F2a can only be done on the build machine with the game's executable; until then any fix is a guess.

## Ideas from testers (not planned yet)

Round modifiers (Saint Alessia, 2026-11-03), a twist laid over an ordinary round. Each would start from the stock mission that already does it (MISSION\_REFERENCE.md):

- **Railgun bombardment,** as in Retaking Theve 1.
- **Tonitrus spear strikes,** as in Over the Rainband.
- **Random allies joining for the round,** as in Mission 28.
