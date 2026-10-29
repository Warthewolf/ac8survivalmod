# The behaviour director: P1-P9 on TestBranch_Behavioural

The Claude Docs thesis "AC8 Survival Mode: Enemy Behaviour Reference & Challenge Thesis" proposes nine changes (P1-P9)
that make Survival's enemies ask the player new questions instead of only getting tougher: fighter roles (P1), a squad
director (P2), tells for every coordinated threat (P3), an intensity director (P4), a harder tailed plane (P5), a
learning layer (P6), boss phases (P7), late rounds (P8) and ace personalities (P9). They are built on branch
`TestBranch_Behavioural` (from tag `stable-1`) one unit at a time. Each unit adds a section here: what was built, its
CFG keys, the log lines a test should look for, and what is untested. The branch ends at Lua 0.72.0 / COOP_TAG
-coop.18 (unit 10), and the last section, "Test checklist: every unit (P1-P9), in game", is the one list for a
playtest of all of it.

Labels as in the other RE notes: [V] verified (read in the code or the cooked data, or by an offline test under
tools/checks), [T] tested in game, [I] inferred. Nothing on this branch has run in game yet: every mechanism here is
[V] at most until a test says otherwise, and each can be switched off in survival.ini.

Shared contract every unit follows (the integration contract of the build):
- New Lua parts: `sv_stats.lua` (measurements; P6's profile), `sv_tells.lua` (P3), `sv_director.lua` (P2, P4), loaded in
  that order after `sv_tactical` and before `sv_menu`, `sv_coop`, `sv_main` (main.lua MODULES).
- A plane's index in its flight is `p.k` (0 = the lead, desc 0). A director tag on a plane is
  `p.dirTag = { tactic = <name>, at = D.now }`, never a bare string. The players are `COOP.players()`.
- The director runs on the host only; joiners see its effect through the plane stream, forwarded events and the
  co-op channels "tl" (tells), "dv" (host-ordered events on one joiner's copies) and "in" (a joiner's intensity).
- Offline checks for every unit: lua_check (Scripts/*.lua and Scripts/ai/*.lua), lua_load_test, menu_test,
  coop_settings_test, coop_ground_test, ini_check, menu_pages_test, plus each unit's own test (stats_test for unit 1).

## Unit 1: foundations and measurements (Lua only; nothing built, no new events)

### What was built
| piece | where | what it does |
|---|---|---|
| per-plane spawn index `p.k` | sv_core.lua (LiveAIPlane callback, logPlane), sv_spawn.lua (spawnFlight, spawnBomber), sv_coop.lua (doSpawn, the logPlane wrapper) | `spawningIdx` is 0 around a pool or bomber flight's SV_Spawn (and a joiner's copy of one) and counts up in the NotifyOnNewObject callback, so each plane's record carries its creation index; other spawns (allies, specials, stand-ins) get none. The host's co-op `ord` (hostPlane) is the same order, so k = ord - 1 on both games [V] |
| the spawn index's check | sv_core.lua leadCheck, sv_spawn.lua `D.leadRow` | a flight whose lead got its own row (an ace's, the jammer's EA-18G) logs once which blueprint k 0 and k 1 fly and whether k 0 is the lead. It compares whole blueprints (`BP_OP1021_su57_CP_Named`), not only the airframe code, so Harvest's Named leads over Shadow wings can tell too |
| `COOP.players()`, `COOP.me()`, `COOP.slotOfAddr(addr)` | sv_coop.lua | the players for the director: `{ slot, obj, addr, at, hpPct, alive, onAirfield, fresh }`, you first (pawn position read once a tick, keyed on D.now; health from HIT.h, full health every 5 s), then each other player from what peerTick already keeps of SV_CoopPeerAt (no new native call; non-finite states left out). Solo: only you, slot 0. slotOfAddr: your pawn or a stand-in to its slot |
| `p.aiState`, `p.aiTarget`, `p.aiTargetAddr` | sv_ai.lua aiWatch | the blackboard's AIState and TargetActor, read on every sweep visit whatever CFG.ai_watch says (coop-perf step 10): the state's name, the object it's after (check `valid()` before using it) and its address (for `COOP.slotOfAddr`); nil for none. nameOf only for the `ai:` log line |
| ACE.movesTick guards | sv_ai.lua | returns at once on a co-op joiner (its copies' reversals are the host's) and while the round clock is nil (was an error: "aces: moves error"); `me` comes from COOP.me() |
| timed parts | sv_main.lua | the per-plane sweep is `planeSweep`, timed as "planes"; ACE.movesTick timed as "moves": both show in the `perf:` line's worst four |
| the measurements | sv_stats.lua (new), hooks in sv_main, sv_ai, sv_flights, sv_ladon, sv_leaderboard, sv_tactical, sv_rounds, sv_coop | the thesis' seven test metrics (below), logged only; nothing sent |
| `STATS.tactic(name, unit, slot, why, callout)` | sv_stats.lua | the one entry point later units call for a director tactic: a `director:` line, counted per round (callouts too), and the unit's live planes tagged `p.dirTag = { tactic, at }`. ACE.movesTick's reversals come in as "reversal": counted apart ("ace reversals"), never tagged |
| `KILL.geom(p, you)` | sv_ai.lua | a kill's aspect, range, height and your last 6 s of shots from ONE moment (the plane's own last sample, `p.youAt`), plus the weapon kind that dropped last; the `kill:` line now comes from it. STATS.track keeps `p.youAt` at every sweep visit with `[stats] enabled = false` too: P6's kill aspects, its tail samples and P4's tail read it (code review of 2026-10-29: with the measurements off they took your position 2 s on against the plane's older one) |
| `hookErr(what, pcall(...))`, `logOnce(key, msg)` | sv_core.lua (code review of 2026-10-29) | the hooks one part calls in another (the sweep's STATS.track / STATS.down, probeTick's STATS.sample, STATS' calls to PROF, spawnFlight's ROLE.spawned / DIR.spawned / ACE.squadUp) log their first error once a session, `<what> error <message> (its first: not logged again)`, instead of a bare pcall that made a failing hook read as one that never ran |
| `creditKill` returns its side | sv_main.lua | "you", "allies", "ships", "defences", "airstrike" ("wingmate" in co-op); nil for a Ladon |
| `playerOnAirfield(you)` | sv_rounds.lua | takes a position already read (optional; callers without one are unchanged) |

### The seven metrics and where each comes from
| metric (thesis target) | measured as | log line |
|---|---|---|
| time to kill an ordinary fighter, rounds 7-12 (20-40 s) | death minus the first sweep sample within `engage_km` (also since spawn, since your first hit); only your kills of pool fighters that aren't bombers, ace squadrons (`p.ace`, else `D.aceSquad`, so a plane the sweep never saw alive too), the jammer (`p.jammer`, else an EA-18G in a flight the jammer led) or probes. A co-op joiner can't tell aces and the jammer from ordinary fighters (only the host's spawner knows), so its pool-fighter kills are "ordinary ?" and left out | `kill-time:` per kill; round line median; run line "time to kill rounds 7-12" |
| a tailed enemy's survival (8 s+ at Veteran) | AI: the first Provoke / EscapeFromPursuer sample to death (AttackAvoidance, Blackout, UniqueAction keep it open; anything else is an escape). Geometric: you within `tail_km` and `tail_deg` of its six (the reversal test) to death | `kill-time:` "tailed X (AI Provoke Y)"; round line medians with died / escaped counts; run line "Veteran+" (not a special's or its guards' kills: their top tier is given, not a skill band; code review of 2026-10-29) |
| special round length (5-8 min) | the round's length on the game clock (and time down at the airfield), next to the special's own LB.special seconds | round line "(<tier>, <kind> S s)" and "length"; run line "specials", "special rounds" |
| missiles left at death (under 40) | A.caps[1] (the count held), else the last ammo read | `death:`; run line "missiles left at the end" |
| damage sources at death (varied) | each drop of your HealthInternal classed at the tick it happens: "missile" (an enemy missile within 800 m seen in the last 0.6 s, the HIT log's test; one homing on someone else skipped), "gun/close" (no missile, an enemy within `gun_km`), "unknown"; a bracket = missiles of two shooters within `bracket_km` in the last second. At death also your aircraft's own DamageHistoryMap (`pawn_history`, metrics brief step 6.3): each attacker's damage since it took off, the armour's share too, read as KILL.read reads an enemy's | `death:` (last `death_window_s`: shares, hits, shooters, brackets, top shooters; "; record: N attackers, <flight or name> <damage>, ..." or "; record: not read"); round line "you took"; run line "damage taken" |
| director tactics per round (3-6, each with a callout) | STATS.tactic's count per round, callouts counted | `director:` per tactic; round line "director tactics"; run line "per round avg" |
| share of kills from behind (under 70 %) | your kills whose aspect is at least 180 - `tail_deg` off the enemy's nose within `tail_km` | round line "kills from behind b/k"; run line |

Fired counts (missiles, specials, flares from the capped counts' drops in the air; the gun from its count's drops
between the 2 s refills) go into the round, death and run lines.

### CFG keys (CFG.stats; `[stats]` in survival.ini; PERSONAL in co-op, so a host never changes a joiner's)
`enabled` (true), `kill_lines` (true: the per-kill line), `engage_km` 5.0, `tail_km` 3.0, `tail_deg` 70, `close_km` 1.2,
`bracket_km` 1.5, `gun_km` 1.5, `death_window_s` 30, `ttk_from_round` 7, `ttk_to_round` 12, `pawn_history` (true: the
death line's damage record; false leaves the read out).
STATS.tactic tags planes whether or not `enabled` is on (later units' kill bonus reads the tag).

### Log lines to look for in a test
- `round probe: AI aircraft created #N: BP_OP..._su47_... (ERA_Unit_03_Dep_Air1, k 2) at ...`: every pool / bomber plane
  has its k.
- `spawn index: ERA_Unit_03_Dep_Air1, lead row e18g_common_sv (e18g): k 0 is a BP_OP1010_e18g_CP, k 1 a
  BP_OP1026_su47_CP; k 0 is the lead: creation order = desc order`. This is THE check for `p.k`. "k 0 is NOT the lead"
  means the per-plane events of later units would hit the wrong plane. Only two kinds of flight can give a verdict,
  because only their lead flies another blueprint than its wings (tools/build_survival.py ACES):
  - a jammer flight: an EA-18G leading pool fighters, from round 8 in a normal round, with `chance` 0.5;
  - a Harvest flight (the reaper tier, from round 28, ace rounds): a `_CP_Named` Su-57, F-22A or Typhoon over
    `_CP_Shadow` wings, or the Rafale over Typhoons. Its ADFX-02 flies one row for both: "can't tell".
  Every other ace squadron (Bounty, Valkyrie, Inferno, Wraith) flies one blueprint for lead and wings and always logs
  "can't tell: lead and wings fly one blueprint". A flight whose ace is already up has no lead row and no line.
  Test checklist: reach a jammer round. To make sure of one, set `[jammer] chance = 1.0` (and, for a short test,
  `from_round = 2`) in survival.ini, then put them back. In a test build, Ctrl+6 (TEST ONLY) spawns the top tier's
  squadron with its ace leading: a Harvest flight, which tells four times in five.
- `kill-time: BP_OP... (ERA_Unit_.., Veteran, round 8, k 1, ordinary): up 61 s, engaged 23 s (within 5 km), since your
  first hit 9 s, tailed 6 s (AI Provoke 4 s); 172 deg off its nose at 0.9 km, +0.2 km; by you[, director <tactic> N s before]`.
  On a co-op joiner a pool fighter reads "ordinary ?".
- `stats: round 8 (Veteran, normal, 1 player): length 312 s (24 s at the airfield), 2 waves; aircraft down ...` a few
  seconds after `round 8 clear` (the sweep sees the last kills up to 2 s after the spawner does). A run that ends mid
  round logs it "(cut short: died)". On a co-op joiner the time to kill reads "ordinary fighters ? (a joiner can't tell
  aces; N pool fighters down)", and a round that the host's "rs" ends is "(cut short: the host started over)" or "(cut
  short: co-op resync)" (the answer to this game's own "jn": its level loaded or its link came back).
- `death: round 23 (died), 140 s into the round: last 30 s -260 HP: missiles 70% (5 hits from 3 shooters, 1 brackets),
  gun/close 20%, unknown 10%; top: ...; missiles left 148 (fired ...), specials a/b, flares c`; "(saved by SECOND CHANCE)"
  when the floor caught you.
- `stats: run over (died): rounds 1-23; time to kill rounds 7-12 median ... [target 20-40 s]; ...` once per run, before
  the `leaderboard: run over` line. A joiner also logs `stats: run over (the host started over)` when the host starts a
  new run (the joiner's level and leaderboard run go on; its measurements start afresh), and its time to kill says
  "(n 0; N of your kills left out: a co-op joiner can't tell aces)".
- `director: round 8 +95 s: <tactic> on <unit> (2 planes)[, player N] (<why>); callout "..."` (from unit 2 on).
- `perf: ... parts avg/worst ms: planes x/y, moves x/y, ...`.
- A hook that throws (should be none): `stats: STATS.track error <message> (its first: not logged again)`, likewise
  `stats: STATS.down`, `stats: STATS.sample`, `learning: PROF.kill` / `PROF.sample` / `PROF.checkpoint` /
  `PROF.roundStart` / `PROF.fold` / `PROF.newRun`, `roles: ROLE.spawned`, `director: DIR.spawned`, `aces: ACE.squadUp`.

### Offline test and the log report
`sh tools/checks/stats_test.sh` (tools/checks/stats_test.lua) runs the real sv_core, sv_config, sv_ai, sv_spawn,
sv_stats and sv_coop with the game stubbed: spawnFlight's planes get k 0..n in creation order and the check names the
jammer's EA-18G at k 0 (and catches a spawner that makes the lead last), Harvest's Named lead over Shadow wings and the
Rafale over Typhoons tell, a one-blueprint squadron can't; a round of planes with known engage / hit / tail / Provoke
times gives the expected kill-time line, round line (with a kill seen after the clear), death line and run line;
STATS.tactic's tag and count. Then the hooks, on the other parts' real code: sv_main.lua's creditKill .. planeSweep (a
live plane tracked and timed "planes", aiWatch's state and target; its death through KILL.geom and creditKill's side to
the kill-time line; an untracked ace's and the jammer's kills not ordinary), sv_ladon.lua's HIT.tick (STATS.hit),
sv_flights.lua's ammoTick (a missile and gun rounds to STATS.fired), sv_leaderboard.lua's LB.deathCheck and LB.finish
(the death line with a damage record, the run line); the calls in startRound, the clear, SECOND CHANCE and probeTick by
their place in the source. Then co-op: COOP.players solo, as a host (another player's state, a stale one, a broken one)
and COOP.slotOfAddr; ACE.movesTick fires solo and not on a joiner; a joiner's rounds from the host's round messages, its
kills "ordinary ?", the host's restart (round cut short, run line, records afresh) and a resync (round cut short, run
kept) [V]. The code review of 2026-10-29 added: a special's guard (top tier, tailed 17 s) kept out of the run line's
Veteran+ figures; [stats] off: the real sweep keeps p.youAt and a kill from 500 m behind reads 180 deg at 0.5 km (P6
counts it from behind); a hook that throws (PROF.kill under STATS.down, STATS.track under the sweep) logged once; the
hookErr calls by their place in the source; a joiner's round and run lines saying the tail watch isn't measured there.
Each fails on the code before the fix.

The test's log lines then go through `tools/checks/stats_report.py` (metrics brief step 10.5). It reads any test log
(`python -X utf8 -I tools/checks/stats_report.py <AC8SurvivalMode_lua.log>`, read only): each run's seven metrics as a
table against the thesis' targets, a row per round, the time to kill over every run's `kill-time:` lines, the `death:`
lines, the `director:` tactics counted and the `spawn index:` lines.

### Untested / known limits
- [I] creation order = AIObjectDesc order (`p.k` 0 = desc 0, where SV_SetAircraft(unit, row, 0) puts the lead): the
  `spawn index:` line of the first jammer flight (round 8+) or Harvest flight confirms or refutes it. A test that ends
  before round 8 without Ctrl+6 gets no verdict.
- [I] the player pawn's DamageHistoryMap (`pawn_history`): confirmed on AI planes (KILL.read, coop.4), never read on
  the player's aircraft. The death line shows "; record: not read" if the read fails; what the values are (HP or tenths)
  and whether the map survives a SECOND CHANCE repair are open.
- [I] `p.aiTarget` holds a UObject between sweeps: later units must check `valid()` first.
- Every time is good to about +/- 2 s (each plane is seen every 2 s; deaths are seen up to 2 s late). Provokes shorter
  than 2 s can be missed. AI Provoke is not measured on co-op joiners (their copies' AI isn't theirs); the geometric tail
  is.
- Damage is HealthInternal only: the player's armour pool (KILLS_HEALTH_DEATH.md) drains first and isn't seen. A gun,
  the Ladons' pulse cannons and a collision within `gun_km` all read "gun/close"; a SAM blast or the railgun "unknown".
  Allied missiles homing on someone else are skipped only while they still exist (one that hit is gone).
- "Weapons" are your shots in the last 6 s at anything, not at that plane; the weapon is the kind that dropped last.
- A game crash logs no run line (LB.finish never runs). A joiner's round kind is "?" (the host's special isn't sent).
- A joiner tells the host's restart from a resync by its own "jn" of the last 15 s; a restart within 15 s of a resync
  would be taken for a resync (its run line then waits for the joiner's own run end).
- On the host, a plane's ace flag comes from `D.aceSquad` at its death if the sweep never tracked it: a flight recycled
  before its last plane was seen down could be read with the new flight's flag (rare: planes are seen down within 2 s).
- COOP.players' other players come from SV_CoopPeerAt as peerTick reads it (up to a tick old); `fresh` is under 1 s.

## Unit 2: a harder tailed plane (P5)

The thesis' P5: "being behind an enemy is an advantage you must work to keep, not a free kill". Three parts: the reaction
scripts never waste a pick, Veteran and up notice a tailer sooner (the live provoke), and a 4 Hz tail watch measures the
P5 gate ("a tailed enemy lasts 8 s+ at Veteran"). Behaviour scripts (rebuilt into the container by build_all.sh) and
Lua; no new events, rows, flags or world data, so no COOP_TAG bump of its own (the contract's single bump comes last).

### How a tree runs, and why the fixes look as they do
From BEHAVIOUR_NATIVE_LOGIC.md 3-6 ([C] code reads): a RandomSelect picks ONE child by weight and never retries it, so a
gate (decorator) straight under it that fails is a pick that does nothing (the Provoke dispatcher then goes straight to
EscapeFromPursuer). A result travels one level only: when a composite under a Selector / LaxSelector finishes, that
selector goes on to its NEXT child whatever happened. So `Selector[ gate -> Decel, Break ]` (the critic's sketch) would
fly the decel AND the break when the gate passes (5.2 s); with the opposite gate over the fallback exactly one runs.
6 s in Provoke sets the stock blackout (10 s of level flight: a free kill), so each Provoke pick stays under 5 s.
The shapes are all in the stock grammar (shapecheck: "stock grammar ok" for all three scripts): LaxSelector under a
PilotRank weight (9 stock uses; a Selector there has none), LaxSelector -> BlackboardFloat (AttackAvoidance_0430_msl_s),
LaxSelector -> CanCobra / CanKulbit (Provoke_0002_s's own cobra fallback). Altitude gates (UnitAltitudeComparison) sit
only under a RandomSelect or a WeightProbability in 381 stock uses and have no "expected" argument, so they can't get an
exclusive fallback; Escape's sharp break puts its turn after them instead.

### What was built
| piece | where | what it does |
|---|---|---|
| decel gate | Scripts/ai/LA_SV_ProvokeNear.lua (DecelW) | the brake-and-turn overshoot (300 km/h) only with the pursuer within 50 m when Provoke began (PursuerDistance <= 5000.0 cm, stock Provoke_0400_s's value; the critic's correction of the brief's 50000); farther out the same pick breaks hard at 3000 (DecelBreak). LaxSelector[ PursuerDistance <= 5000 -> Decel, PursuerDistance > 5000 -> DecelBreak ]. At Veteran (rank 4, AI level 2) this pick was 43 % of the reactions, almost always a 300 km/h turn in front of your guns |
| flare break | LA_SV_ProvokeNear.lua (FlareW) | ActivateFlares fails when no flare is ready (the stock pod reloads 25 s after a salvo) and a failure ended its LaxSequencer before the break; the flare now has a LaxSequencer of its own (FlareShot), so the break always follows |
| cobra / kulbit fallbacks | LA_SV_ProvokeNear.lua (CobraW, KulbitW) | LaxSelector[ CanCobra(true, true) -> the cobra, CanCobra(false, false) -> a break right ] (kulbit: CanKulbit, a break left). Before, half those picks did nothing on a plane without post-stall |
| sharp escape | Scripts/ai/LA_SV_Escape.lua (Sharp) | LaxSequencer[ the six altitude-gated EscapeFromPursuer_0400 moves (unchanged), then a 2 s level turn either way ]. Before, within 1 km of the unit band's top (above 3 km for most pool flights, which spawn at 2-4.5 km) or floor 3 of 8 picks did nothing. Now 2-4 s of breaking (Escape isn't Provoke: no blackout timer runs). The plain run (low ranks, stock EscapeFromPursuer_0000_CP) is unchanged: with the pursuer 1 km+ away its level / straight legs are skipped (the first gate's failure ends their LaxSequencer, as in stock) and its 4 s run away always comes |
| TailChase review | Scripts/ai/LA_SV_TailChase.lua (unchanged) | no pick without a move: the KDS front branch sits under a LaxSelector with the skill pick after it, the skill RandomSelect's four branches (Super, Tail, Tight, Stock) are ungated, and Stock's Selector falls back to SetMoveAwayFromTarget |
| live provoke, tiers | sv_config.lua CFG.tiers.list | Veteran, Elite, Ace, Mercenary, Legend, Demon: `provoke_cone_deg = 60, provoke_time_s = 1.5` (the doc's 60 deg / 1.5 s; Phantom 50 / 1.0 and Reaper 45 / 0.8 / 40-100 m as before). The game's own rows: 85 deg / 2.5 s (NPID_00) |
| the merge | sv_rows.lua `provokeWant(round, tier[, level])` | the stricter of the tier's and the round's spike's (narrower cone, quicker decision, closer surround min / max), field by field. Before, the tier's simply replaced the spike's (withLevel), so with these tier fields a Demon at rounds 22-24 would have dropped from spike 3's 50 / 1.0 to 60 / 1.5. A special's own values (MINDRIPPER's unit) go through the same merge, whatever `tier_provoke` says. `level`: another spike level than the round's, for a later part |
| the writes | sv_rows.lua `enemyProvoke(p, want)`, `enemySpike(p, round, tier)` | enemyProvoke writes ProvokeConditionConeAngle, ProvokeDeterminationTime, SurroundPursuitMin/MaxRange (cm) where they differ from its last write (`p.provokeSet`; `p.provokeWant` = what it should fly) and returns the fields written and before / after texts: the hook for the intensity director (P4) to rewrite a live plane (runtime-ai step 10's "DIR.plane writes again"). enemySpike (the sweep, once per plane: `p.spiked`) = provokeWant + enemyProvoke, and a `provoke:` line once per tier and spike level with the values read back (it replaces the old `spikes: level N on ...` line) |
| the tail watch | sv_stats.lua `STATS.tailTick` (sv_main.lua probeTick, every 250 ms, timed "tail watch"), `tailEnd`, `tailCut`; sv_ai.lua's `AI_STATE` now a global | the host or solo (a joiner's enemies are the host's). Pool flights' enemies with a skill tier (no bombers; no special or its guards: MINDRIPPER's, AB.L..IN's and VALKA's top tier is given, not a skill band, so they skewed the Veteran+ figures; code review of 2026-10-29) within `watch_km` of you by the sweep's last sample, at most `watch_max` a tick, are read afresh: position and heading (one without an episode open checked alive first: a wreck is never read). Those you're likely behind come first (the sweep's `p.tailing`, or the sweep's last pose of the plane against your position now: plain maths, no read), then the nearest, so in a furball a plane you chase at 2.5 km isn't crowded out by four nearer ones. You within `tail_km` / `tail_deg` of a live one's six (the sweep's own test; its HealthInternal is read before an episode opens, so a wreck the 2 s sweep hasn't marked down never opens one) opens an episode (p.tw): its provoke values in force are read (Survival's write or the game's row), then every tick its AI state (Provoke / EscapeFromPursuer / AttackAvoidance / Blackout / UniqueAction / other, timed). A plane already in Provoke, EscapeFromPursuer or Blackout at the episode's first read was defending before you got there (another pursuer, or you closed from beyond `tail_km` inside its provoke cone): "already defending", kept out of "Provoke after" and "after its Provoke" (its Provoke began before t0) and counted apart. It ends when the plane dies (the watch's own check, or the sweep's death first: STATS.down), once you've been off its tail `watch_grace_s` (escaped), or when the run ends with it open (STATS.runEnd, before the last round's line: "still up"); an escape or still-up under 1 s held is a flicker at the cone's edge, dropped. Up to 16 property reads a tick at watch_max 4 (one more as an episode opens) |
| the lines | sv_stats.lua | a `tailed:` line per episode; the round line ends "; tail watch: ..." and the run line "; tail watch Veteran+: ... [8 s+]" (U1's 2 s "AI Provoke" and geometric figures stay) |
| the report | tools/checks/stats_report.py | the run table's tail watch rows (verdict on "died while tailed" against 8 s+), a "watch" column per round, the `tailed:` episodes by tier and by the provoke values in force (the A/B), the `provoke:` writes |
| offline test | tools/checks/tailed_test.sh / tailed_test.lua | below |

### CFG keys
- `CFG.ai` ([ai] in survival.ini; the host's goes to joiners, where it does nothing: their enemies are the host's):
  `tier_provoke` (true: the tiers' provoke values are written; false: only the spikes' and the specials', so a round-7
  Veteran keeps the game's 85 / 2.5), `provoke_stricter` (true; false: the tier's over the spike's, as before),
  `provoke_cone_deg` (0) / `provoke_time_s` (0.0): above 0, an A/B test value for every tier that has its own. The
  reaction scripts are switched with `reactions` as before (false: the stock 0012_CP slots).
- `CFG.tiers.list[*].provoke_cone_deg / provoke_time_s` (Veteran-Demon 60 / 1.5): survival_config.lua only (the ini can't
  reach a list of tables).
- `CFG.stats` ([stats], each player's own in co-op): `tail_watch` (true), `watch_km` 4.5, `watch_max` 4,
  `watch_grace_s` 2.0.

What a pilot flies now (default settings; the surround is the spike's until Reaper):
| rounds (spike level) | tier | before P5 | P5 |
|---|---|---|---|
| 1-6 (0) | Rookie, Regular | the game's 85 / 2.5 | the same (a Regular promoted to Veteran: 60 / 1.5) |
| 7 (0) | Veteran | 85 / 2.5 | 60 / 1.5 |
| 8-14 (1) | Veteran, Elite, Ace | spike 1's 70 / 2.0 / 80-220 m | 60 / 1.5 / 80-220 m |
| 15-21 (2) | Ace, Mercenary, Legend | 60 / 1.5 / 60-160 m | the same |
| 22-24 (3) | Demon | 50 / 1.0 / 50-120 m | the same (the stricter merge keeps spike 3's) |
| 25+ (3) | Phantom; Reaper from 28 | 50 / 1.0; 45 / 0.8 / 40-100 m | the same |

### Log lines to look for in a test
- Main menu, unchanged: `behaviour: set NLID_SV_Fighter in (NLID_0012_CP with EscapeFromPursuerLua = LA_SV_Escape, ...
  ProvokeNearLua = LA_SV_ProvokeNear, ...)` and `game Lua: stock SurvivalMode.AI.LA_SV_ProvokeNear: true ...`. In the
  level before round 1: `game Lua: built ... LA_SV_Escape x1, ... LA_SV_ProvokeNear x1 ...; errors 0` (a Ctor error in
  the changed scripts shows here: both are in GAME_LUA_STOCK).
- `provoke: round 7, spike level 0, Veteran (BP_...): was ProvokeConditionConeAngle 85.0, ProvokeDeterminationTime 2.5;
  now ProvokeConditionConeAngle 60, ProvokeDeterminationTime 1.5; reads back 60.0, 1.5 (Veteran 60 deg / 1.5 s)`; from
  round 8 with the spike's part and ": the stricter".
- `tailed: BP_... (ERA_Unit_03_Dep_Air1, Veteran, k 1, rank 4, AI level 2): provoke 60 deg / 1.5 s (Survival's); you on
  its tail at 1.0 km, 12 deg off its six; Provoke after 1.8 s; Provoke 1.5 s, EscapeFromPursuer 2.0 s, AttackAvoidance
  0.5 s, other 1.0 s; died 9.5 s after (7.7 s after its Provoke)` or `...; no Provoke; ...; escaped after 3.0 s`, or
  `...; already in Provoke when you got behind it; ...; died 3.0 s after` (defending before t0: no reaction time), or
  `...; still up when the run ended (died), 4.5 s on its tail`.
- The round line's end: `; tail watch: 6 episodes (Veteran+ 6): died after median 3.0 s (n 3), 8.0 s after its Provoke
  (n 1), escaped 2 (held median 2.5 s), still up at the end 1, Provoke after median 1.5 s (none in 4, already defending
  1), blackouts 0` ("Provoke after" and "none" are the fresh episodes only); the run line's:
  `; tail watch Veteran+: died after median ... on your tail (n N), ..., still up at the end U, Provoke after median ...
  (none in X, already defending Y), blackouts B [8 s+]`. On a co-op joiner (the watch doesn't run there) the round
  line ends `; tail watch: not measured on a co-op joiner (its enemies are the host's)` and a run of its rounds `; tail
  watch Veteran+: not measured on a co-op joiner` (code review of 2026-10-29: it logged 0 episodes as if it had).
- `perf: ... tail watch x/y` among the worst parts only if it costs.
- `stats_report.py <log>`: "tailed lines: N" with a table by tier and one by "provoke in force" (e.g. `60 deg / 1.5 s
  (Survival's)` against `85 deg / 2.5 s (the game's)`): n, died, died after, escaped, up (still up at the run's end),
  Provoke after (fresh episodes only), none (fresh episodes without a Provoke), already (already defending), blackouts.

Test checklist:
1. The build lines above (main menu, level).
2. Round 7 (Veteran, before the first spike): sit on enemies' tails. `tailed:` lines with "(Survival's)" and the
   reaction ("Provoke after"). Then the A/B: `[ai] tier_provoke = false` (restart the game: rows and CFG are read at
   start), round 7 again: "(the game's)" 85 / 2.5. Compare stats_report's "Provoke after" column between the two
   "provoke in force" rows: it is the fresh reactions only (episodes already defending when you got behind the plane
   are counted under "already" and left out, so a Provoke begun before the episode can't pull both arms to 0). Get
   behind planes that aren't defending yet (close in from their six rather than chasing one that's already breaking);
   if "already" is most of an arm, its median says little. If "Provoke after" doesn't move (about 1.5 s against 2.5 s+)
   the live write does nothing, and runtime-ai step 11 (per-row DT_NPC_Provoke copies) is the way. A stronger signal:
   `provoke_cone_deg = 30`, `provoke_time_s = 0.5`.
3. The P5 gate: the run line's "tail watch Veteran+: died after median ... [8 s+]" (stats_report verdict). Watch
   "blackouts" (a Blackout state in an episode: 10 s of level flight) and the state times.
4. Close in under 50 m behind one (hard): the decel overshoot should show (a sudden slow-down); farther out no enemy
   should slow to 300 km/h when you get behind it.
5. With `[spikes] enabled = false` and a Mercenary+ round (AI level 3+) on an airframe outside CFG.maneuvers.post_stall:
   the cobra / kulbit picks should break instead of flying straight (by default spike 2's post_stall_all lets every
   airframe post-stall from round 15, so this fallback rarely runs).

### Offline test
`sh tools/checks/tailed_test.sh` (tools/checks/tailed_test.lua):
1. The trees: the three scripts' Ctor on a recording `self`, then a model of the game's runner (the composite stack and
   indices, each composite's answer to Failed / Complete / Abort, a RandomSelect's single pick, decorators, PilotRank /
   AILevel weights; ActivateFlares fails with no flare ready) walks every pick of every RandomSelect in 4800 situations
   (rank 1-5, AI level 1-5, the pursuer 30 m / 50 m / 500 m / 1.5 km away, cobra / kulbit allowed or not, a flare ready
   or not, mid-band / near the top / near the floor, a KDS front phase or not). ProvokeNear (29760 walks): every pick
   flies one move, at most 4.7 s; the decel only within 50 m and never with its break; the cobra / kulbit only when
   allowed and never with their fallback; a flare pick always breaks. Escape (49920): every pick moves; the sharp one
   always turns; near the band's top no climb. TailChase (11520): every pick pursues or breaks away. The model first
   finds the old faults on fixtures: the cobra no-op, the flare that ended its break, and a Selector going on after a
   composite child [V against the model; the model is BEHAVIOUR_NATIVE_LOGIC.md's [C] reads].
2. The live provoke: provokeWant per tier and round (7, 8, 22, 28, 1, 5; stricter / replace; tier_provoke off; the
   test values; a special's own; spikes off), enemyProvoke's four writes and rewrites of only what changed, enemySpike
   once per plane with one `provoke:` line per tier and level, a Regular before a spike untouched; sv_main.lua's calls.
3. The tail watch on stubbed planes: a Provoke 1.5 s after t0, its states, death at 9.5 s (8.0 s after Provoke), an
   escape held 3.0 s with no Provoke, a 0.25 s flicker dropped, a bomber left out, only the nearest four read, the
   sweep's death ending an episode, nothing on a co-op joiner or with tail_watch off; no episode on a wreck the sweep
   hasn't marked down (and none when the sweep then finds it); a plane already in Provoke: "already defending", no
   reaction time, nothing "after its Provoke"; two planes you're behind (one by the sweep's p.tailing, one by its cached
   pose) read before four nearer ones beside you; an episode still open when the run ends (shot down) ending as "still
   up" in the round line (cut short) and the run line; then stats_report.py on its log. Each of the review's three
   fixes was checked to fail its case when undone (a scratch copy with the fix reverted). The code review of
   2026-10-29 added: a special's guard on your guns beside a pool fighter never watched (no episode, no read); a wreck
   not even read (alive checked before the read); both fail on the code before.

### Untested / known limits
- [I] Everything in game. The trees' "always one move" is [V] against the runner model only; the model follows
  BEHAVIOUR_NATIVE_LOGIC.md, whose walker, composites and RandomSelect are [C] code reads, not tests.
- [I] `CanCobra(false, ...)` / `CanKulbit(false, ...)` as "can't": the IsEqual family's first argument is `expected`
  ([C] for the family; IsFlareActive(false, true) is stock), but stock never passes false to these two. If it read as
  true, a plane without post-stall would do nothing on that pick (as before) and one with it would still fly only the
  cobra / kulbit.
- [I] Whether the game's provoke decision reads the live fields at all (the writes read back: 0.70.2; the native read
  0x147cf2530 is [?]). The tail watch's A/B (checklist 2) answers it. runtime-ai step 11 (per-row DT_NPC_Provoke copies
  set as each _sv row's ProvokeId at the main menu) is the fallback and is not built.
- [I] SurroundPursuit only applies to a non-lead PursuerTarget with the surround offset; LA_SV_TailChase's own-offset
  branches (Tail / Tight / Super) may ignore it.
- [I] ActivateFlares' Failed with no flare ready (BEHAVIOUR_NATIVE_MOVE.md [C]) and the pod's 25 s reload (the FCS
  row) are what made the old flare pick a no-op; how often it happened is unmeasured.
- The decel overshoot now needs you within 50 m when Provoke begins (stock's gate): rare in practice, so most former
  decel picks are breaks. The sharp escape is 2-4 s instead of 1.5-2 s, and out of Provoke the blackout timer counts
  down [C], so a long run of reactions should blackout less; watch "blackouts" in the lines.
- The cobra / kulbit picks need AI level 3 / 4 (round 16 / 19 on), where spike 2's post_stall_all already lets every
  airframe post-stall: their fallback runs only with spikes off or a special that turns post-stall off.
- The tail watch: the host or solo only, your own tails only (not a joiner's stand-in on the host's game: U1's 2 s
  geometric metric covers each joiner on its own game); 250 ms resolution; the AI state is read only while an episode
  is open, so a plane defending at its first read is "already defending" (no reaction time; it can also be one that
  went into Provoke in the same 250 ms you crossed into the cone, rare); a plane beyond `watch_km` at the sweep's last
  visit (up to 2 s old) isn't watched until the next one; "likely behind" uses the sweep's pose of the plane (up to 2 s
  old), so a tail you've just started can wait a sweep for its slot when watch_max planes are both nearer and likely.
  "Died after" counts only deaths: an escaped or still-up episode is a survival at least that long (censored), listed
  apart, not folded into the median. Its reads are on the game thread with the rest of the tick (timed "tail watch").
- Not built (optional in the briefs): a shorter Survival BlackoutLua (behaviour-pipeline (d)); per-row provoke
  (runtime-ai step 11).

### Review fixes (after unit 2's review; not yet run in game)
The trees, the live provoke and its merge passed the review unchanged (a hand trace against BEHAVIOUR_NATIVE_LOGIC.md
agreed with the opposite gates). The tail watch, the P5 gate's measurement, got four fixes so its figures aren't
biased: (1) an episode opens only on a live plane (HealthInternal read first): a wreck the 2 s sweep hadn't marked down
used to open one and close it the next tick as "died" after about 0.25 s, pulling the "died after" median down;
(2) a plane already defending at the episode's first read ("already defending") no longer counts as "Provoke after
0.0 s": those zeros diluted both arms of checklist 2's A/B and could read as "the live write does nothing";
(3) the planes you're likely behind are read before nearer ones; (4) episodes still open when the run ends get a line
and count as "still up" instead of vanishing. tools/build_all.sh now lints Scripts/ai/*.lua too (lua_check, the
packed behaviour scripts; the critic's note). stats_report.py reads the new parts (and still reads the older lines).
Not done: runtime-ai step 11 (per-row provoke) waits for the A/B; the joiners' tails stay unwatched (above).

## Unit 3: late rounds (P8)

The thesis' P8: "smarter to round 25, then more planes". Rounds 15-25 keep the 30-aircraft cap with enemy health capped
at x1.5; from round 26 a round grows by 3 aircraft up to 60 by round 35, and the most up at once by 1 a round up to a
ceiling per preset, so the extra planes come as more waves, not a bigger wall. With it: the critic's P8 x P4 gap fill
(the game's player-attack throttle grows with the sky: RE_SV_Pressure<A..D>) and the kill bonus for director-tagged
kills. Lua, survival.default.ini and four new remote events (tools/survival_events.py; rebuilt into the container by
build_all.sh). No new rows, flags or world data. No COOP_TAG bump of its own (the contract's single bump comes last), but
the four events are new: that bump must come before any co-op build goes out, or an older joiner logs
"coop: the host's event RE_SV_PressureC not fired here".

### What was built
| piece | where | what it does |
|---|---|---|
| the round's cap and budget | sv_config.lua `TIER.growRounds(round)`, `TIER.roundCap(round)`, `TIER.roundBudget(round)` | growRounds: rounds into the growth (0 before CFG.late.aircraft_from_round, 1 in it; 0 with [late] off or aircraft_from_round 0). roundCap: CFG.max_aircraft, then + aircraft_per_round a round up to late.max_aircraft (never below CFG.max_aircraft). roundBudget: aircraft_round1 + aircraft_per_round a round + the spike's aircraft_add, within roundCap (the thesis' "spikes still add their aircraft_add on top, within the cap": past round 13 the base is already over 30, so a spike adds nothing late, as before). Pure maths of CFG, no new globals or main-chunk locals |
| the most up at once | sv_config.lua `TIER.maxUp(round, preset)` | CFG.waves.max_up_by_preset[preset] (or max_up), then + late.max_up_per_round a round up to late.max_up_cap[preset] (never below the preset's own; a preset without a cap doesn't grow) |
| startRound | sv_rounds.lua `startRound`, `waveCap(round)` | the budget is TIER.roundBudget; an amphibious round's extra is capped at TIER.roundCap; then the menu's ENEMY AIRCRAFT %; then COOP.more up to the room's cap TIER.coopCap(round) (review fix). The % used to come before the amphibious extra, whose re-cap at 30 cut an amphibious round above 100 % back to 30 (a bug the brief found; 45 at 150 % now). waveCap(round) = TIER.maxUp(round, presetName()) x the %, then COOP.more(..., "max_up"). The round's start line gains "; cap C, up to U at once", and a "pool short" line when the pool can't fill the fighters by 2 or more. The wave state is unchanged; its gate carries a comment for P4's hold (`and not hold`) |
| health | sv_config.lua CFG.late | health_max_x 1.5 (was 2.0) and health_per_round 0.045 (was 0.04): x1.495 at round 25, x1.5 from 26, as the numbers start growing (the thesis: "health stops climbing once numbers do"). enemyLate / scaleHealth are unchanged |
| co-op caps | sv_config.lua `TIER.coopCap(round)`, CFG.coop, CFG.late.coop_max_aircraft; sv_coop.lua `COOP.more(n, capKey, cap)` | the room's most aircraft in a round: CFG.coop.max_aircraft (60, as before), grown by as many as one player's round cap has grown (TIER.roundCap - CFG.max_aircraft), up to late.coop_max_aircraft 80: 60 in rounds 1-25 whatever the room's size (the thesis' "rounds 15-25 keep today's cap"), 63 at 26, 69 at 28, 78 at 31, 80 from 32. COOP.more takes it as an optional third argument (else CFG.coop[capKey], as before; never fewer than one player gets). max_up stays 30 (the Ace preset's late ceiling and the frame-time limit). The first build raised coop.max_aircraft to a flat 80, which also took rooms of 8 or more past 60 before round 26 (8 players from round 13, 12 from round 10, 24 from round 6; review issue 2) |
| the attack throttle | tools/survival_events.py `PRESSURE`, build_anomaly; sv_config.lua `TIER.pressure(round)`, `TIER.PRESSURE_PRESETS`; sv_rounds.lua `roundPressure` | four remote events RE_SV_Pressure<A..D>, each the three records attack() writes (LiveSetPlayerMaxAttackerMissiles, LiveChangePlayerMaxAttackersNumExecution, LivePlayerAttackCooldownOverrideExecution), built inside build_anomaly where attack() lives (the critic's correction): A 2 missiles / 3 attackers / 8-12-20-25 s (a lull, for P4), B = ATTACK_BASE 4 / 6 / 4-8-15-20 (the mission start's), C 6 / 8 / 2-4-8-12, D 8 / 10 / 1-2-5-8. TIER.pressure: the preset of the latest [late.pressure] from_round band the round is in, B before them, nil when [late] or [late.pressure] is off. startRound fires it (after the waves are made) when it differs from the one in force, D.pressure, and in a run's first round whatever it is (D.pressure nil: not known; a restart keeps the level and an earlier run's C or D, review issue 1), never in an Anomaly or VALKA round (TIER.PRESSURE_OWN: their records set ANOMALY_ATTACK and put ATTACK_BASE back at their end: D.pressure is set to B there, and `pressureAfterBoss` (sv_rounds.lua, every roundsTick on the host) fires the band's preset 3 s after Lua sees the boss down, the critic's "fire it again after those specials end"; or the next round does; a boss that can't come, its spawn refused, `pressureNoBoss` puts back the preset in force before the round, D.pressureWas, and fires the band's at once: code review of 2026-10-29). A failed fire leaves D.pressure as it was, so the next round tries again. The build checks Lua's letters and presets against PRESSURE (build_anomaly asserts). D.pressure is the dial the intensity director (P4) would turn too |
| co-op for the throttle | sv_coop.lua `hostSync` | the contract's table makes RE_SV_Pressure* forwarded (not in KEEP_EVENTS; the runtime-ai brief wanted it kept, the contract wins): each game's throttle limits the attacks on its own player, and a joiner's copies attack the joiner (hard rule 48), so the host's preset belongs on every game. A joiner who links (or starts over) later missed the fire, so hostSync sends the preset in force ("ev", queued like the other events until its level is ready), B too (a joiner's level kept from an earlier run may still be on its C or D), but not while an Anomaly or VALKA is up (their own throttle; the band's preset after the boss is forwarded) nor with [late.pressure] off. The host's restart reaches joiners through round 1's fire (forwarded), since their "rs" handler resets their round, not their level |
| the kill bonus | sv_main.lua `creditKill`; CFG.late.director_pay | your kill (KILL.by "you") of a plane whose p.dirTag = { tactic, at } (STATS.tactic, unit 1) is at most tag_s old pays x `x` (1.5), in the TIER.pay base with the other multipliers; the credits line gains ", director <tactic> x1.5". Nothing is tagged until the squad director (P2) calls STATS.tactic; ACE reversals aren't tagged (unit 1). Pays in any round, [late] on or off (the thesis: "so fighting smart pays at any count") |
| the menu's help | sv_menu.lua `roundN` | ENEMY AIRCRAFT's help reads TIER.roundBudget: "round 1 has 4, round 10 has 24, round 35 has 60" at 100 % (round 10 said 22: it left out the round-8 spike's +2), never above the fighters the pool can field (`TIER.poolMost`, 86: CFG.pool less the probes): at 150 % and 200 % round 35 says 86, not 90 / 120 (review issue 3) |

What a run brings now (default settings, solo, a normal round without bombers; the test's Monte Carlo of the real
startRound, 300 runs a cell):

| round | aircraft (picked) | most up Casual / Standard / Ace | waves Casual / Standard / Ace | throttle | health |
|---|---|---|---|---|---|
| 25 | 30 (30) | 14 / 18 / 22 | 3 / 2 / 2 | B | x1.495 |
| 28 | 39 (38) | 17 / 21 / 25 | 3 / 2 (3 in 1 of 6) / 2 | C | x1.5 |
| 31 | 48 (48) | 20 / 24 / 28 | 3 / 2 or 3 (half each) / 2 | D | x1.5 |
| 35+ | 60 (60) | 20 / 26 / 30 | 3 or 4 (4 in 2 of 3) / 3 / 2 or 3 (3 in 2 of 5) | D | x1.5 |

The thesis' table (30 / 39 / 48 / 60; 14-22, 17-25, 20-28, 20-30; about 2 / 2 / 2 / 3 waves at Standard) is matched.
Rounds 1-25 are as before (budget and most up, checked round by round). "Picked" is the usual case: flights are whole 2 /
4 / 6-ships, so an odd budget (39) flies one short; in 1-9 % of runs (most at round 35) the pool's eight 2-ships run out
first and a round flies 2-4 short ("pool short").

With the menu's ENEMY AIRCRAFT % (applied after the caps, as before) and co-op (COOP.more after the %), Standard:
round 35 at 50 % asks 30 (13 up at once), at 150 % 90 (the pool gives 86; 39 up), at 200 % 120 (86; 52 up); four players
at round 25 get 44 (26 up), at round 35 80 (30 up: max_up), Ace at round 35 80 (30), Casual at round 31 70 (29); 12
players at round 20 get 60 (the room's cap to round 25; the first build's flat 80 gave 80) and at round 28 69, 24
players at round 25 60 and at round 35 80.

### CFG keys
- `CFG.late` ([late] in survival.ini): `health_per_round` 0.045 (was 0.04), `health_max_x` 1.5 (was 2.0), `grow`
  true (the growth's switch), `aircraft_from_round` 26 (0: no growth), `aircraft_per_round` 3, `max_aircraft` 60,
  `max_up_per_round` 1, `coop_max_aircraft` 80 (the co-op room's ceiling, TIER.coopCap).
- `CFG.late.max_up_cap` ([late.max_up_cap]): casual 20, standard 26, ace 30.
- `CFG.late.pressure` ([late.pressure]): `enabled` true, `from_round` 26, 31, `preset` C, D (any case; letters of
  TIER.PRESSURE_PRESETS / PRESSURE only, others skipped). Needs [late] on.
- `CFG.late.director_pay` ([late.director_pay]; [zollars] points there): `enabled` true, `x` 1.5, `tag_s` 20 (the sweep
  sees a kill up to 2 s late). In CFG.late by the contract ("CFG.late (P8 additions)"); the brief had it in CFG.credits.
- `CFG.coop.max_aircraft` 60 (unchanged; the first build's 80 is back to 60, the growth is TIER.coopCap's).
- Switches: [late] enabled = false turns off health, promotion, growth and the throttle together (not the kill bonus);
  [late] grow = false (or aircraft_from_round = 0) only the growth (a round's aircraft, the most up at once and the
  co-op room's cap); [late.pressure] enabled = false only the throttle (the game stays on B);
  [late.director_pay] enabled = false only the bonus. A co-op host's [late] reaches the joiners (M.sendSettings).

### Log lines to look for in a test
- `round 30: 44 aircraft: 44 fighters in 11 squadrons, 2 waves (22 + 22 aircraft); cap 45, up to 23 at once` (Standard;
  the numbers vary; cap = TIER.roundCap, "up to" = the wave cap after the % and co-op).
- `round 35: pool short: 58 of 60 fighters (0 spare 2-ships)` (the pool ran out of the sizes left; at 100 % rare).
- Unchanged: `round N: wave k of n (m aircraft) with j of the last wave's left`, `late: round N enemies' health x1.50
  (...)` (at most x1.50 now).
- `pressure: round 1: preset B (was not known: the run's first round)` (every run's first round, START AT ROUND's
  too), `pressure: round 26: preset C (was B)`, `pressure: round 31: preset D (was C)`; in an Anomaly or VALKA round
  `pressure: round 28 is the anomaly's: its own throttle, then preset B; preset C again once it's down`, then about 3 s
  after `special: MINDRIPPER down ...` `pressure: round 28: preset C (was B, the anomaly is down)` (or, if Lua never
  saw it down, the next round's `pressure: round 29: preset C (was B)`); its boss refused at its spawn (`round 31: no
  anomaly; ...`): `pressure: round 31: preset D (was C, no anomaly this round)` at once (none when the band's is the one
  in force before the round); a failure
  `..., RE_SV_PressureC not fired: <reason>`; `pressure: error ...`.
- Co-op joiner: nothing when it works; `coop: the host's event RE_SV_PressureC not fired here (...)` when it doesn't.
- `credits: +280 (f16c down (fighter, Veteran x1.25, round x1.50, director bracket x1.5)), now ...` (once P2 tags).
- `perf: tick avg X ms, worst Y ms ...` with 26-30 up: the thesis' gate before shipping the Ace ceiling.

### Test checklist (in game)
1. Reach the late rounds: START AT ROUND 30 on the menu, or `[rounds] start_round = 35` in survival.ini. Each preset
   (Casual / Standard / Ace). The start lines: the budget (45 at 30, 60 at 35), "cap", "up to", the waves; the wave
   lines as each wave comes in at 4 left.
2. Frame time with 26-30 up (Ace, round 35): the `perf:` lines (the true peak is the wave cap + next_at 4 = 34).
3. The throttle A/B: rounds 26-30 with `[late.pressure] enabled = true` and `= false`. Compare the kill-time lines
   (time to kill), the death line (damage at death, its record) and the stats round line; in the ai: lines, how many
   planes attack at once. It is the strongest dial on how many may attack you at once, and its effect was never measured.
4. Health: `late:` lines x1.50 from round 26 (x1.49-1.50 at 25).
5. The kill bonus: only once P2 tags planes (`director:` lines), then ", director <tactic> x1.5" on the credits line
   of your kill within 20 s.
6. Co-op (2+ players, round 26 on): no "not fired" for RE_SV_Pressure* on the joiner; a joiner who links mid-run gets
   the preset in force (it's in the host's "coop: sent player N the run" batch). Then the host restarts from the pause
   menu past round 31: the new run's round 1 logs `pressure: round 1: preset B (was not known ...)` and the joiners'
   rounds 1-25 feel like B again. Eight or more players before round 26: a round's start line stays at most 60.
7. An Anomaly round from round 26 (Ctrl+1 in a test build, or START AT ROUND 30): the `... again once it's down` line,
   then `pressure: round N: preset C (was B, the anomaly is down)` about 3 s after MINDRIPPER goes down.

### Offline test
`sh tools/checks/late_rounds_test.sh` (tools/checks/late_rounds_test.lua), on the real sv_core, sv_config, sv_ai,
sv_spawn, sv_rounds (startRound exposed), sv_stats, sv_coop (hostSync, mirroredEvent exposed) and sv_main's creditKill:
1. survival.ini: [late.pressure] from_round / preset (lower case), [late.max_up_cap], [late.director_pay] and [late]
   aircraft_from_round set live are read, every line used.
2. The thesis' table from the helpers: rounds 25 / 28 / 31 / 35 (30 / 39 / 48 / 60, most up 14-22 ... 20-30), 26 / 33 /
   40, the ceilings; rounds 1-25 against the old formula round by round; [late] off; aircraft_from_round 0; the health
   curve; the pressure bands, a letter the build lacks, the throttle off.
3. startRound, 300 times a round and preset: D.budget, the start line's wave cap, no wave over it, the aircraft picked,
   the waves (Standard: always 2 at 25, about 2 at 28 and 31, always 3 at 35); 50 / 150 / 200 %; the "pool short" line;
   an amphibious round at 150 % (45, not 30) and at round 30; four co-op players (44 / 26, 80 / 30, 80 / 30, 70 / 29), 12
   and 24 players (60 at rounds 20 and 25, 69 at 28, 80 at 35: TIER.coopCap, 60 to round 25 and 80 from 32) and the
   host alone; [late] grow = false; TIER.poolMost's 86.
4. The throttle through startRound, rounds 25-35: B at 25 (a run's first round), nothing at 25 again, C at 26, nothing
   at 27, none in the Anomaly round 28 (B after it), C 3 s after its boss is down (pressureAfterBoss: not before, once),
   nothing at 29 then, a boss round in band B (nothing after it), a Ladon round (not its business), none in the VALKA
   round 30 (never seen down: D at 31), a failed fire kept and fired the next round (a failed first round too), an
   Anomaly refused at its spawn through the real roundsTick (D at once against the C before it; C in force: none, C
   known again, not B),
   nothing with it off; forwarded (mirroredEvent), the host's fire sent to every joiner, hostSync's re-send (B too;
   nothing while the Anomaly is up or with it off); the review's repro: a host on D after round 31 starts a new run,
   round 1 fires B once and every joiner gets it.
5. creditKill: 190 untagged (round 30, Veteran), 280 tagged 5 s and 20 s before, 190 at 25 s, 90 for an ally's kill
   of a tagged plane, a bare string tag ignored, off, on with [late] off; then end to end: STATS.tactic tags a unit's
   plane and its kill 12 s later pays the bonus.
6. The hooks in the source: startRound's helpers, co-op (TIER.coopCap), the throttle, roundsTick's pressureAfterBoss;
   the menu help's numbers (its roundN run: 60 at 100 %, 86 at 150 % and 200 %).
coop_settings_test.sh checks COOP.more's cap argument (60 flat, 73 under 80, round 35's 80, round 25's 60);
coop_ground_test.sh's hostSync case now sends the throttle at once (the Alicorn's events still 12 s later).

### Untested / known limits
- [I] Everything in game. [V] the maths, the budgets and waves on the real startRound, the throttle's firing logic and
  the built records (ep_dump: RE_SV_PressureA-D, life -, the three records each, like MissionStart's).
- [I] Whether the throttle limits ordinary fighters at all (runtime-ai: never measured). C and D are guesses scaled to
  keep the attackers at once about a third of the most up (Standard: B 6 of 18; C, rounds 26-30, 8 of 19-23; D, from 31,
  10 of 24-26).
- [I] Frame time with 26-30 up at once (the Ace ceiling) and 3-4 waves of 19-30: never run. A friend's round 23 (54
  aircraft, 13 flights up) is the most that ran (0.6x, an older build). Co-op: 30 puppets moved every frame on each
  joiner and 60-80 aircraft rounds: never run (co-op played to round 5).
- In an Anomaly or VALKA round the band's preset stays in force until MINDRIPPER appears / VALKA reveals; after the
  boss is down the fighters left fly B for about 3 s, then the band's preset again. [I] that its down / end records
  have run 3 s after Lua sees SV_UnitAlive 0 (they fire on the game's destroy trigger; Lua's RE_SV_AnomalyEnd /
  RE_SV_ValkaEnd at the same moment).
- [I] Whether a pause-menu restart re-runs MissionStart's ATTACK_BASE: moot now (round 1 fires its preset).
- Ace rounds (28, 31, 34 ...) take the same budget: a round-34 ace round is about 57 squadron aircraft (Reaper tier
  from 28 anyway). The thesis says nothing; an `ace_round_x` (or ace rounds kept at 30) is the user's call.
- ENEMY AIRCRAFT above 100 % keeps today's meaning (% after the caps): 200 % at round 35 asks 120 and gets the pool's
  86, up to 52 at once (Standard). A hard ceiling on the wave cap would also change rounds 1-25 above 100 %: the
  user's call. waves.enabled = false brings late rounds all at once (up to 60).
- pickFlights is unchanged: it picks sizes at random, so in a few % of late rounds the 2-ships run out and a round
  flies 2-4 short (logged). D.budget is the asked number, not the flown one.
- Economy: kill pay stops growing at round 26 (round_x_max 1.5), late kills double (60 against 30) and round_bonus is
  250 x the round; the ammo caps (Standard 48 missiles / 28 special) against 60 enemies at x1.5 health need a balance
  pass (the "missiles left at death" metric, unit 1's death line).
- The kill bonus: a co-op joiner's copies carry no tag (the director runs on the host), so a joiner's kills of them
  pay no bonus; that would need a guarded message (P2's call).
- The role mix (P1) will split the pool: a 60-aircraft round can run one role dry; check the role mix and the late
  budgets together then.

### Review fixes (after unit 3's review; not yet run in game)
1. A run's first round fires its throttle preset whatever it is (D.pressure nil = not known), B too: a restart keeps the
   level, so the host and every joiner (whose "rs" handler resets only their round and copies) stayed on the earlier
   run's C or D for all of the new run's rounds 1-25 (the reviewer's offline repro; now a case in late_rounds_test).
   hostSync sends the preset in force, B included, except while an Anomaly or VALKA is up or with [late.pressure] off.
2. The co-op room's cap grows with the round instead of a flat 80: CFG.coop.max_aircraft is 60 again, and
   TIER.coopCap(round) adds as many as one player's cap has grown, up to the new CFG.late.coop_max_aircraft 80 (60 to
   round 25, 80 from round 32). With the flat 80 a room of 8 got more than 60 from round 13, of 12 from round 10,
   of 24 from round 6, against the thesis' "rounds 15-25 keep today's cap". COOP.more takes the cap as a third argument.
3. The ENEMY AIRCRAFT help never names more than the fighter pool can field (TIER.poolMost, 86).
4. Scope gaps: the band's preset is fired again 3 s after an Anomaly / VALKA is down (pressureAfterBoss), not only the
   next round (the critic's wording); the growth got its own switch, [late] grow (the contract's "every feature has a
   switch"; aircraft_from_round = 0 still works).
Still open for the user (unchanged): ace rounds at the full late budget, ENEMY AIRCRAFT above 100 % applied after the
caps, economy and ammo not re-tuned for 60 enemies, the single COOP_TAG / VERSION bump (the four RE_SV_Pressure events
are new: it must come before any co-op build goes to friends).

## Unit 4: tells (P3)

The thesis' P3: "a radio line (DT_SV_Radio, hard rule 33) or HUD callout before each director action ... add a 1 s
callout lead. This turns cheap-feeling deaths into readable ones." Built: the tells' catalog and machinery (a new part,
`Scripts/sv_tells.lua`, global TELL), 59 stock AC8 radio lines cloned into DT_SV_Radio with a remote event each, an
urgent path in the HUD's callout queue, the co-op channel "tl", and tells wired to the threats that exist today. The
squad director (P2) and the specials (P7) say their own tells through the same API later; their lines are in the
catalog already (said by nothing yet). Lua, survival.default.ini and the build (tools/survival_events.py,
tools/build_survival.py: 61 new remote events, 59 new radio rows; no new flags, world data or imports). No COOP_TAG
bump of its own (the contract's single bump comes last), but the events and rows are new: that bump must come before
any co-op build goes out, or an older joiner hears nothing ("not fired" in its tell lines).

### What was built
| piece | where | what it does |
|---|---|---|
| the radio lines | tools/survival_events.py `TELL_LINES`, `tell_event`; tools/build_survival.py `build_radio` | (group, TextID, SpeakerID, options) for every line: one DT_SV_Radio row each, a group of its own (`SV_Radio_<letters>`, hard rule 17), cloned from Mission 22's AWACS row 382 with only its group, line and speaker changed (the confirmed RADIO_REPLACE route, hard rule 33), LimitPlayCount 0. 'now' lines (the ones an action follows by a short lead: reversal, dive, trap, six, bracket) get StartDelay 0.1 s (the template's 0.6) and Channel InterruptMain (6, Mission 3's row 233). Enemy lines of a named campaign unit speak as a Sotoan fighter (Common_Enemy_Fighter_*), so no squadron's name shows; wingmen's lines (Kate, Coster, Baxter) are left out. The build checks: groups unique and not Mission 22's, letters only, every `<TextID>_Play` in the voice bank (DA_SoundDB_AKB_Voice, now pulled by build_all.sh), row 382 still the template, the table parses back (`radio: 719 rows (7 dropped, 1 replaced, 59 tell lines)`) |
| the remote events | survival_events.py `build_tells` | RE_SV_Radio<Suffix> for each group: Mission 22's LiveRadioPlayExecution (the shuttle countdown's template), no conditions (hard rule 26). Checked both ways against the Lua runtime: every RE_SV_Radio* Lua names is built, every built one is named in CFG.tells (`events: 592 triggers, 1312 execs`) |
| the ALICORN's RAILGUN WARNING | survival_events.py `build_alicorn` | RE_SV_AlcnAlertOn / Off: Mission 18's LiveSetRailgunAlertEnable true / false (as VALKA's, hard rule 45), under the Alicorn's own names; forwarded in co-op (each game shows its own) |
| the catalog | sv_config.lua `CFG.tells` | each tell: its radio events (`radio`: one at random, never the same twice running, or the a-th with pick "a"; `chain`: another tell's line after it), its callout (`hud`, a key of `text`, %s / %d filled from the tell's numbers with `args` "compass" or "clock"), `urgent` (cuts in), its cooldown_s and lead_s. PERSONAL in co-op |
| TELL | sv_tells.lua | `TELL.say(id, slot, a, b)` (slot nil: this game's player; TELL.ALL: every player; a number: that player, the host only, "tl"; not said: why and a kind, and with TELL.ALL on a host with tells off the send's, so a caller can wait out the joiners' gap: F4's review), `TELL.after(id, slot, fn, ...)` (the action lead_s after the tell, run by `TELL.tick` every 250 ms on the round clock; at once when not said; never with `need`), `TELL.leadS(id)` (0 with this game's tells off, unless it hosts co-op), `TELL.ready(id, slot)`, `TELL.play` (this game only: the joiner's "tl" and the test key end here), `TELL.known(id)`, `TELL.hunted(p)` (the hunt's trigger). Keeps hudCallout and SV_Event as they were before sv_coop.lua wraps them (the contract's exception): a tell never goes out again as the host's "co" callout or "ev" event |
| rate limiting | sv_tells.lua `classOf`, `wait` | each receiver (this game's player, each joiner the host sends to, "every joiner") on its own: an urgent tell urgent_gap_s (2.5) after the last urgent one; a tell with a queued callout gap_s (4, the banner's own time) after the last such; a radio-only one radio_gap_s (2) after any tell; each id its cooldown_s; none between rounds (a joiner plays the host's anyway: its mirrored state may lag), down at the airfield or over the run's summary. A radio line is never asked for again within line_gap_s (20 s, the cloned rows' RequeueingWaitTime) by whichever tell (`lineFree`, D.tells.evAt, set when its event fired): reversal and kulbit share their two lines, and an ace can kulbit 12 s after its reversal; a tell whose lines are all that recent shows its callout only, or isn't said (kind "line"). Refusals are logged once a round per tell and reason |
| the urgent callout | sv_hud.lua `hudCallout(text, sub, big, urgent)`, `calloutNext(now)` | an urgent callout (a tell's) goes in front of the queue, in place of a tell still waiting there (one waits at a time), a full queue (4) losing its last callout for it (logged); the next HUD tick puts it up at once, cutting the banner's callout short (put back right after the tell when more than 1.5 s of it was left, a full queue then losing its last, logged; a tell never cuts a tell), for CFG.tells.hud_s (2.5 s). Before, a callout could come up to 16 s late behind four round callouts (the brief). sv_coop's wrapper passes urgent on |
| co-op | sv_coop.lua `COOP.tell`, the joiner's "tl" handler, KEEP_EVENTS, PERSONAL | "tl" (id, a, b) from the host to a joiner's slot or to every joiner; the joiner plays it only if it knows the id (its own catalog), a / b are finite (or absent), its level is ready, [coop] callouts is on, and at most 4 came that second; dropped, never queued (a late tell misleads). `^RE_SV_Radio` is in KEEP_EVENTS (no "ev", and a joiner refuses one); `tells` is PERSONAL (each player's switches, texts and lines). CFG.tells.enabled is each game's own: a host with tells off still sends "tl" (TELL.say checks it only for its own TELL.play) and its leads stand (TELL.leadS); a joiner with tells off plays none. The host's gaps, cooldowns, leads, hunt_km and wave_from_round decide when a tell is sent |

Tells wired now (the threats that exist today):

| tell | when | where | to | shows | lead |
|---|---|---|---|---|---|
| reversal / kulbit | you on a move tier's (Reaper's) tail within 3 km / 70 deg (kulbit within 900 m) | sv_ai.lua ACE.movesTick (host / solo only) | you | "That's a sudden turn - coming straight at you!" or "He's mine!"; ACE REVERSAL / HE'S TURNING INTO YOU (ACE POST-STALL / DON'T OVERSHOOT), urgent; a repeat kulbit (lead_s + 12 s on) told too: cooldown_s kulbit 12 (code review of 2026-10-29: at 20 every other one came untold) | the move (RE_SV_AceTurn_NN / AceKulbit_NN) 1.0 s (0.5 s) after the tell (TELL.after); at once without a tell, as before |
| hunt | a hunting tier's flight (Reaper: ACE.hunt keeps its target on you) first within hunt_km 8 of you, once a flight a round (the sweep's p.dist of that visit: code review of 2026-10-29, it read the last sweep's, 2 s late) | sv_ai.lua ACE.hunt -> TELL.hunted (not on a joiner) | you | "Hunt down the Wings of Theve ..." or "I see our prey."; YOU ARE BEING HUNTED / ACES CLOSING ON YOU (queued) | - |
| raid | a raid's, strike's or bombers' callout (the round's first bomber flight) | sv_spawn.lua spawnBomber | everyone | "Joker Flight, enemy aircraft approaching the eastern airfield." (Survival's airfield is Mission 22's eastern one) or two others; radio only (the round's callout stays) | - |
| jammer / jammer_down | the jammer up; shot down | sv_spawn.lua spawnFlight; sv_main.lua creditKill | everyone | "The enemy's jamming you with a powerful ECM." / "Hostile EW aircraft destroyed! Jamming has been lifted!"; radio only | - |
| wave | each later wave of a round from wave_from_round 26 (the late rounds' growth) | sv_rounds.lua roundsTick's wave branch | everyone | "New enemy aircraft detected. Look sharp!" or three others; radio only | - |
| alcn_rail_first / alcn_rail | lead_s 5 s before each railgun order (it fired without a warning before) | sv_alicorn.lua alicornTick | everyone | "Joker Flight, the railgun has been activated." the first time, then "Enemy railgun's ready to fire." / "Railguns are getting ready to fire!"; WARNING: RAILGUN / BUILD SPEED, THEN BREAK, urgent; with CFG.specials.alicorn.rail_alert the RAILGUN WARNING on (RE_SV_AlcnAlertOn) until alert_s 12 after the order, at a dive, when it sinks or when the run restarts (SPC.alicornCleanup, from sv_main.lua's level-load reset). None once both railguns are down (the 2 s parts pass, `ARMS`: a kind seen up and none up now, or gone; looked for again first, `armsLook`, so one found a pass after its siblings isn't silenced with them: F4's review): the warning off at once, no more calls, warnings or orders (code review of 2026-10-29: they came every minute after the player had shot them) | the order's time is unchanged (after a surfacing: below); the warning comes earlier (the railgun then aims ~7 s and preps ~2 s: ALICORN.md) |
| alcn_dive / alcn_up | its dive; counted surfaced | sv_alicorn.lua | everyone | "Enemy submarine diving!" / "Submarine has surfaced. Begin attack!"; radio only (its callouts stay; not on each resurface order) | alcn_up said: the railgun's warning no sooner than radio_gap_s 2 after it, its order lead_s after the warning (code review of 2026-10-29: with an order due under water both lines went out in the same second); nothing said: the order 5 s on, as before |
| alcn_vls | its VLS volley, until every VLS is down (as the railguns) | sv_alicorn.lua | everyone | "Missile launch from VLS!"; VLS LAUNCH / ALICORN MISSILES INBOUND, urgent | RE_SV_AlcnVolley 1.0 s after (not if it dived, or its VLS went down, meanwhile) |
| ladon_vls | a Ladon's VLS volley | sv_ladon.lua ladonTick | everyone (the volley's forwarded: each game's copy fires at its own player) | "Large aircraft has launched missile." / "The bomber has launched a missile!"; VLS LAUNCH / LADON MISSILES INBOUND, urgent | 0 (with it: the hatch opens first) |

Catalogued for later units (lines, events and texts in, said by nothing yet): pincer (4 AWACS lines; TWO GROUPS INBOUND /
FROM THE %s AND THE %s by compass), split (HUD only), dive (4 lines, urgent, then the o'clock: `chain` clock, 12 lines
"Bandit at N o'clock!" picked by a; BANDIT DIVING / HIGH, %d O'CLOCK), drag, lure (2 enemy lines), trap (AWACS and enemy,
urgent), cover_ask (3 "cover me" enemy lines), six (4 lines, urgent), bracket (3 lines, urgent), regroup, lancer and
skirm (HUD only), alcn_deck (P7). Their lead_s are set (dive, trap, six, bracket 1.0); the bracket salvo's 1 s should
still be the event package's delay on its salvo records, timed with TELL.leadS("bracket") (frame accurate: hard rule 40).

### CFG keys
- `CFG.tells` ([tells] in survival.ini; PERSONAL in co-op): `enabled` true (false: no tells here, every action of
  this game's own tells at once as before; a co-op host still sends its joiners theirs), `radio` true, `hud` true,
  `hud_s` 2.5, `gap_s` 4.0, `urgent_gap_s` 2.5, `radio_gap_s` 2.0, `line_gap_s` 20 (0: a line may come again at once),
  `hunt_km` 8.0, `wave_from_round` 26 (0: never).
- `CFG.tells.cooldown_s` ([tells.cooldown_s]): reversal 20, kulbit 12 (was 20: ACE.movesTick's kulbit gap is lead_s +
  12 s), hunt 45, raid 30, jammer 30, jammer_down 10, wave 20, alcn_vls 30, ladon_vls 15 (and 0 for the ALICORN's other
  calls; the later units' set too).
- `CFG.tells.lead_s` ([tells.lead_s]): reversal 1.0, kulbit 0.5, alcn_rail 5.0, alcn_vls 1.0, ladon_vls 0.0 (dive,
  trap, six, bracket 1.0 for P2).
- `CFG.tells.list`, `CFG.tells.text`: the catalog and its texts (build data and wording; not in the ini).
- `CFG.specials.alicorn.rail_alert` ([specials.alicorn.rail_alert]): `enabled` true, `alert_s` 12.

### Log lines to look for in a test
- `tell: reversal: RE_SV_RadioTurnA (fired), tell callout 'ACE REVERSAL'`, then about a second later the unchanged
  `aces: <plane> has you 1500 m behind it, 3 deg off its tail: RE_SV_AceTurn_13 (1), 1 so far`.
- `tell: raid: RE_SV_RadioRaidB (fired)` and in co-op `tell: raid to every joiner ("tl")`; on the joiner
  `tell: raid (the host's): RE_SV_RadioRaidB (fired)`.
- `tell: alcn_rail_first: RE_SV_RadioAlcnRailFirst (fired), tell callout 'WARNING: RAILGUN'` with
  `special: the Alicorn's railgun in 5 s: warned`; a radio event that didn't fire: `... (not fired: <SV_ERR>)`.
- Refusals, once a round each: `tell: kulbit not said (1.0 s after reversal, its gap 2.5 s)`, `tell: hunt not said
  (its cooldown, 45 s)`, `tell: bracket not said (down at the airfield)`, `... (between rounds)`,
  `... (nothing to show: its radio or HUD half is off)`, `... (each of its lines played within line_gap_s 20 s)`.
- A tell whose lines were all asked for within line_gap_s: `tell: kulbit: no line (each played within line_gap_s),
  tell callout 'ACE POST-STALL'`.
- The HUD: `hud: tell 'ACE REVERSAL' / 'HE'S TURNING INTO YOU'`, and `hud: callout '<text>' dropped for a tell (the queue
  was full)` when four callouts were waiting, `hud: callout '<text>' dropped (a tell cut in)` when the callout a tell
  cut short went back into a full queue.
- A restart with the ALICORN's RAILGUN WARNING up: `special: the Alicorn's RAILGUN WARNING off with the run`.
- Its railguns or VLS shot down (code review of 2026-10-29), once each: `special: the Alicorn's railguns are down (2
  found, none up): its RAILGUN WARNING off, no more railgun warnings or orders`, `special: the Alicorn's VLS are down (4
  found, none up): no more VLS calls or volleys` (`0 found` when their actors went). When first kept: `special: the
  Alicorn's railguns found: 2 (kept; looked for again before they count as down)` (`VLS found: 4`); one found late, as
  the others go down: `special: the Alicorn's railguns: 1 more found (2 in all, 1 up)` (F4's review).
- `perf: ...` shows `tells x/y` only when it's among the four worst parts (it does almost nothing).
- Errors: `tell: <id>'s action failed: ...`, `tell: tick error ...`, `coop: tell error ...`.

### Test checklist (in game)
1. Every line: Ctrl+0 (test builds) says the catalog's next line, every radio line of every tell in turn, then the
   HUD-only ones, past the gaps: voice, subtitle and speaker name each (AWACS, or a Sotoan fighter / commander in enemy
   colours); `test: Ctrl+0, tell line N of 64: <id> <event> (said)`.
2. Repeats: the same tell twice within 20 s and again a round later (LimitPlayCount 0, RequeueingWaitTime 20 s on the
   template row: does a group asked again within 20 s play?).
3. A 'now' line (reversal, six) over a playing line (the MOONCHILD takeoff, the shuttle's countdown): does InterruptMain
   cut in, and does StartDelay 0.1 bring the voice inside the 1 s lead?
4. An ace reversal (Reaper, round 28+, or Ctrl+6): the call and ACE REVERSAL, the turn about a second later; the HUD
   banner cut short and the round's callout back after the tell.
5. The ALICORN (Ctrl+5): the first call 5 s before the first order, the RAILGUN WARNING on until about 12 s after it, off
   at a dive and when it sinks; then log the seconds from RE_SV_AlcnRailgun to the first hit (HIT.tick) and tune
   lead_s / alert_s. The VLS volley a second after its call. After a surfacing "submarine has surfaced" first, the
   railgun's call 2 s later (not over it). Shoot both railguns (4 missiles each): the RAILGUN WARNING off at once and
   no WARNING: RAILGUN or call again; every VLS: no more VLS LAUNCH (the `are down` lines).
6. A Ladon round (Ctrl+4): the volley's call with each volley.
7. A raid (round 3, 6, ...), the jammer ([jammer] chance = 1.0, from_round = 2), a late wave ([rounds] start_round = 26).
8. Whether the game's own play-by-play "Joker 1! Check your six!" already plays in Survival; if so, the six tell (P2)
   doubles it.
9. Co-op: a TELL.ALL tell on every game (each from its own catalog), nothing on a joiner while its level loads; no `ev`
   lines for RE_SV_Radio* in a joiner's log; a host with [tells] enabled = false: its joiners still hear theirs, a
   joiner with it false hears none. (A slot's own tell comes with P2.)
10. The ALICORN's RAILGUN WARNING on, then a pause-menu restart: the warning gone in the new run.

### Offline test
`sh tools/checks/tells_test.sh` (tools/checks/tells_test.lua, then tools/checks/tells_lines_check.py), on the real
sv_core, sv_config, sv_ai, sv_hud, sv_spawn, sv_stats, sv_tells, sv_alicorn, sv_ladon and sv_coop (M, mirroredEvent
exposed):
1. The catalog: every tell's events RE_SV_Radio<letters>, texts present, chains / args / keys known, the twelve o'clock
   lines; MODULES order.
2. The HUD: a tell in front of the queue, replacing a waiting tell, a full queue losing its last (logged); calloutNext
   cutting a callout short and putting it back (3 s left; into a full queue: its last dropped, logged), not (1 s left),
   never cutting a tell; hudTick uses it.
3. Saying: a line at random then the other, the gaps by class (urgent after urgent, radio after any, urgent right after
   a radio-only one, queued callouts 4 s apart), cooldowns, pick a, the dive's chained o'clock, compass and o'clock texts,
   a failed event logged, between rounds / at the airfield / over the summary, radio, hud and all off, TELL.ready, the
   forced line; line_gap_s: the kulbit takes the line its reversal didn't, the reversal its own again 21 s on, both lines
   recent: the callout only (logged), with hud off not said (kind "line"), a line that didn't fire not counted, pick a,
   0 = no limit.
4. The lead: an action 1 s after its tell (not at 0.75 s), at once unsaid, never with need, lead 0, a failing action
   logged, tells off, dropped with D.
5. The wiring: ACE.movesTick's reversal (tell, then RE_SV_AceTurn_13 1 s later) and kulbit (0.5 s), at once with tells
   off; ACE.hunt's tell within 8 km once a flight a round, a second flight in the cooldown marked done, none on a joiner;
   the ALICORN second by second (call and warning at 95 for the order at 100, warning off at 112, the volley's call at
   130 and the volley at 131, the next call at 155, a dive at 157 turning it off, no order while dived, the sink turning
   it off, rail_alert off, tells off: the warning with the order, SPC.alicornCleanup turning it off once and the
   level-load reset calling it); a Ladon's volley after its call; raid, jammer,
   jammer_down, wave, TELL.tick and Ctrl+0 by their place in the source. The code review of 2026-10-29 added: the
   Reaper's next kulbit 12.5 s on told too, cooldown_s kulbit within ACE.movesTick's 12 s gap; stats_test: the sweep's
   ACE.hunt reading that visit's p.dist; bosses_test: the railguns' and VLS' tells and orders stopping once they're
   down, and the calls after a surfacing kept apart (unit 9's offline list).
6. Co-op: a host's tell inside its mirrored rounds sends no "co" / "ev" (a round callout and the railgun warning still
   do); TELL.ALL plays here and sends "tl" to every joiner; a slot's tell goes to that slot only, with its own gaps;
   with the host's tells off both still go, its lead stands (alcn_vls' action 1 s on) and nothing plays on the host;
   numbers sent, a NaN not; COOP.tell refuses bad slots and ids; the wrapper passes urgent on; the joiner drops a tell
   while loading, plays the host's from its own catalog, drops unknown or long ids and huge numbers, at most 4 a second,
   none with [coop] callouts off or its own tells off, plays one while its mirrored state still says "wait", and tells
   no one else.
7. tells_lines_check.py: TELL_LINES' groups letters only and whole FNames, TextIDs and speakers well formed, every event
   named by the Lua catalog and back (the build checks the same, plus every voice in the bank).
The earlier units' tests still pass: stats_test's ACE.movesTick case loads no sv_tells (TELL nil: the move at once).

### Untested / known limits
- [I] Everything in game. [V] the catalog, the rows and events as built (DT_SV_Radio parsed back: SV_Radio_TurnA =
  ('v0001', 1929) = v0001_1928, Channel 6, StartDelay 0.1, LimitPlayCount 0; ep_dump: RE_SV_RadioTurnA ->
  LiveRadioPlayExecution SV_Radio_TurnA, RE_SV_AlcnAlertOn / Off -> LiveSetRailgunAlertEnable true / false), the Lua.
- [I] Only one cross-mission TextID swap is confirmed (v2501_0054, hard rule 33). Lines from the play-by-play table
  (PByP_CP: the six, bracket, o'clock and enemy chatter lines) cloned onto an ms022 Scenario row are untested; so are
  the speaker overrides (Common_Enemy_Fighter_* for named units' lines).
- [I] LimitPlayCount 0 = any number of times (the play-by-play rows' value); RequeueingWaitTime stays 20 s (the
  template's). Its effect is unknown; Lua never asks for the same line within line_gap_s 20 s (by any tell: the
  per-tell cooldowns alone didn't cover reversal and kulbit, which share their lines). If checklist item 2 shows a group
  asked for again inside 20 s plays, line_gap_s can go to 0.
- [I] InterruptMain and StartDelay 0.1 on the 'now' lines.
- [I] There is no radio feedback: SV_Event's 1 says the remote event fired, not that the line played.
- [I] The railgun's order-to-shot time (~9 s from ALICORN.md's data, never measured): lead_s 5 and alert_s 12 are guesses
  until checklist item 5.
- The lead runs on Lua's 250 ms tick (0-250 ms late); a frame-accurate lead is an event-package delay (TELL.leadS).
- Several Reaper flights: the reversal's 20 s cooldown means a second flight's reversal within it comes without a tell
  (at once, as before); so does another flight's kulbit within the kulbit's 12 s (one flight's own repeats are told).
  The hunt tell is the host's only (its planes hunt the host); a joiner hears none.
- A tell that can't be said is dropped, not queued (e.g. a raid's call within 2 s of another tell).
- The RAILGUN WARNING of a joiner who links mid-warning stays off until the next one (hostSync doesn't replay it).
  A run left from the level doesn't fire RE_SV_AlcnAlertOff (the level and its HUD go with it); a restart does.

### Review fixes (after unit 4's review; not yet run in game)
1. CFG.tells.enabled is each game's own, as the ini always said (tells are PERSONAL): a co-op host with tells off no
   longer silences its joiners. TELL.say checks the switch only for this game's own TELL.play; the host still sends
   "tl" (to a slot or every joiner), TELL.leadS keeps its leads on a host, TELL.after waits its lead whenever the tell
   went to anyone, and TELL.ready answers for a joiner's slot by the host's gaps only. A joiner with tells off plays none.
2. Radio lines shared by two tells (reversal and kulbit: RE_SV_RadioTurnA / B) could be asked for again within the
   cloned rows' 20 s RequeueingWaitTime (an ace kulbits 12 s after its reversal), and the game might skip them silently.
   Each line's last fired time is kept (D.tells.evAt) and a line isn't picked again within the new line_gap_s (20,
   [tells] line_gap_s; 0 turns it off): the other line, else the callout only, else not said (kind "line"). The doc's
   claim that cooldowns kept repeats 20 s apart is corrected (above).
3. A callout put back into a full queue by a tell's cut-in is logged when the queue's last makes room
   (`hud: callout '<text>' dropped (a tell cut in)`).
4. The ALICORN's RAILGUN WARNING goes off when a run restarts with it up (SPC.alicornCleanup, beside SPC.V.cleanup in
   sv_main.lua's level-load reset): alicornTick stops with the run, so its alert_s timer never came.
Still open (unchanged): the single COOP_TAG / VERSION bump (61 events, 59 rows: before any co-op build goes to friends);
COOP.peerPlanes() not exported (P2 uses COOP.players()); the P1 / P2 / P7 tells catalogued but not said, and the
bracket salvo's frame-accurate lead (P2); no hostSync replay of the RAILGUN WARNING; everything in game.

## Unit 5: fighter roles (P1)

The thesis' P1, "four behaviour sets instead of one": the 24 pool flights are split into role groups at build time,
each group's world-data descs naming its role's behaviour row, so the behaviour is in place when the level loads (hard
rule 20); the spawner draws a round's flights by a role mix and gives each its role's airframes. Built with the
behaviour-pipeline brief's recipes (a) and (b) and the critic's corrections and gap fills (role airframes and fallbacks,
the Lancers' altitude band, the Skirmishers' health and LAAM, the Wolf trap's per-object hold, the jammer's roles, the
Lancer / Skirmisher tells). Lua, Scripts/ai (7 new behaviour scripts), survival.default.ini and the build
(tools/survival_events.py, tools/build_survival.py: 4 new DT_SV_NpcMission rows, per-object behaviour rows and a raised
altitude band in the world data, 36 new remote events). No COOP_TAG bump of its own (the contract's single bump comes
last), but the world data, rows and events changed: that bump must come before any co-op build goes out.

| role | the question | behaviour (set) | airframes |
|---|---|---|---|
| duelist | can you out-turn me? | today's NLID_SV_Fighter (LA_SV_TailChase, LA_SV_ProvokeNear, LA_SV_Escape, LA_SV_MoveAway) | Su-33, Su-47; Su-35 (10), Rafale, Typhoon (12), Su-57 (16), F-22A (18) |
| lancer | can you dodge from above? | NLID_SV_Lancer: spawns 2 km above the others; one slashing pass (LA_SV_LancerPass), a zoom back up (LA_SV_LancerZoom); tailed it runs and reverses (LA_SV_LancerBreak, near, mid and far): never turns with you | F-15E, F-14D, Su-34; F-15C (6) |
| wolf | will you take the bait? | bait and trap pairs: the even planes (NLID_SV_WolfLead) attack and, tailed, drag you straight (LA_SV_WolfDrag, then the stock 8 s run); the odd ones (NLID_SV_WolfWing: LA_SV_WolfStrike, a close gunfighter) are held at engagement None until sprung; their guns lead you 0.5 s | F-16C, MiG-29, F/A-18E, MiG-21 |
| skirm | can you finish a fight before the next one starts? | NLID_SV_Skirmisher: in for one shot, breaking off the moment it fires (LA_SV_SkirmPass), a long extend (LA_SV_SkirmExtend); tailed, the stock rookie defence; health x0.75; its special a LAAM copy from 7 km, never inside 2.5 km | F-2A (4), Gripen (7), F-35C (9); before round 4 the Wolf airframes |

(The MiG-31 the thesis names for the Lancer is out of the pool: user, 2026-10-23.)

### What was built
| piece | where | what it does |
|---|---|---|
| the pool split | tools/survival_events.py `ROLE_BY_FLIGHT`, `POOL_ROLE`, `ROLE_ROW`, `behaviour_row`, `behaviour_rows`; Scripts/sv_config.lua `ROLE_BY_FLIGHT`, `ROLE` | by flight number NN, each role a whole 2 / 4 / 6-ship trio (CFG.squadrons: every role can field a 2-ship from round 1): duelist NN 01-02 (24 aircraft), lancer 03-04 (24), wolf 05-06 (24), skirm 07 and 08's 2-ship (14; 08's Air1 / Air2 are the retired behaviour probe's, never in a round, so the usable pool stays 86). The build checks Lua's list is the same (build_wolf) |
| the behaviour rows | tools/build_survival.py `NPC_EXTRA` (+ `survival_events.ROLE_NPC`), `build_wd_global` | DT_SV_NpcMission rows sv_role_lancer / sv_role_wolf_lead / sv_role_wolf_wing / sv_role_skirmish (copies of Mission 22's f16c_common, NpcId SV_Role_Lancer / WolfLead / WolfWing / Skirmish). The world data's rows are now set per object after sizing: a Wolf flight's even objects the bait's row, its odd ones the trap's (set_flight_size copies objects 0 / 1, so the parity held before it too; now it's explicit). Build line: `behaviour rows (flights): {... 'f16c_common_sv': 6, 'sv_role_lancer': 6, 'sv_role_wolf_lead+sv_role_wolf_wing': 6, 'sv_role_skirmish': 4, ...}` |
| the Lancers' band | build_survival.py `build_wd_global`, `survival_events.LANCER_MAX_ALT_M` | MaxAltitudeInMeter 9000 on the six Lancer units (the critic: Mission 22's 4-5 km band would stop their zoom's climb and, above it, maybe send them back into the area, [?]); `6 Lancer flights up to 9000 m` |
| the scripts | Scripts/ai/LA_SV_LancerPass, LancerZoom, LancerBreak, WolfDrag, WolfStrike, SkirmPass, SkirmExtend; `LUA_SCRIPTS`; `GAME_LUA_STOCK` | every one "stock grammar ok" (shapecheck.py) and walked by roles_test's model of the tree runner (below); packed at /Game/LuaSource/SurvivalMode/AI/<name>; the build checks every script a set names is packed. tools/re/BEHAVIOUR_GUIDE.md 6 has what each does |
| the sets | sv_config.lua `CFG.behaviour_sets` | NLID_SV_Lancer, NLID_SV_WolfLead, NLID_SV_WolfWing, NLID_SV_Skirmisher, each NLID_0012_CP with its slots (setsSetup, unchanged: `behaviour: set NLID_SV_Lancer in (NLID_0012_CP with ...)`) |
| the role rows | sv_rows.lua `rolesSetup` (RS), called from sv_main.lua after searchSetup | at the main menu, a DT_NPC row per role (copied from f16c_common's, Survival's search module, the role's set: ROLE.SETS); a set that couldn't be made: the fighters' set (or fallback_luaset); roles off: the fighters' set for every role row (today's behaviour). Made in Lua so a missing set falls back instead of naming a LuaSet row that isn't there (the brief) |
| the level's roles | sv_spawn.lua `ROLE.levelLoad` (sv_main.lua's level-load block), `ROLE.flight(unit)` | what was in before the level loaded (the behaviour build and the spawner only know those): a role is live (its set), drawn as a duelist (its row flies the fighters' set) or sits out (no row: an older container; ROLE.sitsOut keeps it out of the role-blind picks too: spares, a special's refill, Ctrl+6, as the brief asks: what its desc would build is unknown); roles off: ROLE.live nil and every flight is drawn, armed and paid as before roles |
| the draw | sv_config.lua `ROLE.mixFor`, `ROLE.quotas`; sv_spawn.lua `ROLE.pickRound`, `ROLE.groups`; sv_rounds.lua `startRound` | the round's fighters by CFG.roles.mix (the band of the latest from_round reached; an ace round by ace_mix: the squadrons keep the duelists' set and its Super branch), each role's share of the round in whole 2-ships (the pairs left drawn by what's left of each share, so round 1's two 2-ships are 60 / 20 / 20 % over many rounds), from its own flights (exactFlights: the free flights whose sizes add up to the share exactly, flown ones first, so a group of six flights doesn't strand a remainder; then startRound's pick takes them); a group short is filled from the rest; the list shuffled so each wave mixes roles. Spares, a special's refill and Ctrl+6 stay role-blind (a flight's role is its unit's anyway) |
| airframes | sv_spawn.lua `pickAircraft(tier, role)` | the role's own airframes (CFG.roles.aircraft) of what's unlocked (CFG.aircraft + variety.late by round + SR.usable); a signature type only when it's the role's; none yet (the Skirmishers before round 4): the fallback role's (CFG.roles.fallback skirm = wolf), else the whole list; logged once a round. Ace squadrons keep their own rows; the jammer its EA-18G on object 0 |
| altitude | sv_spawn.lua `spawnFlight` | a Lancer flight spawns CFG.roles.lancer.alt_add_m (2000) higher, at most ROLE.LANCER_TOP_M - 500 (8.5 km) |
| tells | sv_spawn.lua `ROLE.spawned` | the round's first Lancer and first Skirmisher flight: TELL.say("lancer" / "skirm", TELL.ALL) (P3's HUD-only tells: BANDITS HIGH / THEY WON'T TURN WITH YOU, LONG-RANGE SHOOTERS / CLOSE THE DISTANCE), once a round each, never for an ace squadron; inside roundsTick, so they reach the joiners as "tl" |
| the jammer | sv_spawn.lua `ROLE.jammerOk`; sv_rounds.lua | the round's jammer leads only a CFG.roles.jammer flight (duelist, skirm): its EA-18G on object 0 never takes a Wolf bait's drag set (the critic) or a Lancer's |
| escorts | sv_rounds.lua | a raid's escorts are never Wolf flights (the escort order would free the trap); the escorts still come first in the queue |
| the Wolf trap | survival_events.py `build_wolf`; sv_spawn.lua `WOLF` (WOLF.spawned, WOLF.tick from roundsTick, WOLF.free, WOLF.holding) | per-object remote events on each Wolf flight's odd objects (12 in the 6 flights): RE_SV_WolfHold_<NN><L> (engagement None on that object: Mission 22's MOONCHILD hold, the stock by-object form), RE_SV_WolfFree_<NN><L> (air-only search + PlayerOnlyNoLimit on it), RE_SV_WolfTurn_<NN><L> (LastTGT on it, Mission 6's by-object request). The hold comes hold_after_s (3) after the flight's SV_Up_NN is seen set (its appearance orders, 2 s after it spawns, would undo an earlier one: hard rule 26), never while you're down at the airfield. Freed: at hold_max_s (60), a held plane hit by you or a joiner (that one), its own bait (the plane before it, k - 1) down (that one; the flight's lead, object 0, down: all), or by the squad director's spring (P2, unit 6: `WOLF.free(unit, why, true)` adds the turn). A held plane shot down is dropped (nothing fired). Nothing is freed or sprung while your DECOY stands the flight down (the releases come after it; `WOLF.free` answers 0). Held again rehold_s (1) after your DECOY's end (its RE_SV_DecoyEnd_NN frees the whole flight). Escorts, ALLY.tick's hunts and the co-op host's split hunts leave a holding flight alone (WOLF.holding). Build line: `wolf trap: 12 held objects in 6 Wolf flights`; `events: 628 triggers, 1360 execs` (was 592 / 1312) |
| the Wolf guns | sv_rows.lua searchSetup's gun branch (`wolfGun`) | the Wolf airframes' gun rows at every spike level lead you by CFG.roles.wolf.gun_lead_s (rows NPC_FCS_PlaneGun000_SV<level>_WOLF; "guns lead on" can't be switched live: PredictionOffsetTime is on the row). Every plane of those airframes gets it (bait and trap; the Skirmishers' rounds 1-3 fallback too). Only with roles on at the main menu |
| the Skirmishers' LAAM | sv_rows.lua (`skirmLaam`) | their airframes' special slot (slot 3 on all three) a copy of NPC_FCS_PlaneLAAM000 (NPC_FCS_PlaneLAAM000_SV_SKIRM): lock within 7 km / 45 deg, never inside 2.5 km, 2 s lock, 4 s between, 8 s rest (the stock AI LAAM: 1.5-4 km, what Survival's own missiles already reach). Needs CFG.special on; only with roles on |
| health | sv_ai.lua `enemyLate`, `scaleHealth` | x CFG.roles.health_x[role] on top of the late rounds' (skirm 0.75; not an ace squadron's): MaxHealth lowered with it so a cut-down plane doesn't read as damaged (the critic; raising it is confirmed, lowering untested). Runs on every game: a joiner's copies by its own ROLE.live |
| co-op | sv_coop.lua `KEEP_EVENTS`, the host's hunts | `^RE_SV_WolfTurn` kept (LastTGT steers to the host); WolfHold / WolfFree forwarded (a joiner's copy holds its fire too); a hunt queued for a holding Wolf flight is dropped. CFG.roles goes to joiners with the host's settings (data); the role sets and rows are each game's own from the main menu, the same names in every build |

### CFG keys (CFG.roles; `[roles]` and its sections in survival.ini; the host's for the room)
- `enabled` true (false: today's single set for every flight, drawn and armed as before; rows and sets are made at the
  main menu, so a change needs a game restart), `tells` true, `jammer` = duelist, skirm.
- `mix` ([roles.mix]): `from_round` 1, 4, 10; `duelist` 0.6, 0.4, 0.3; `lancer` 0.2, 0.2, 0.25; `wolf` 0.2, 0.2,
  0.25; `skirm` 0.0, 0.2, 0.2 (each role's share at the band in the same place).
- `ace_mix` ([roles.ace_mix]): duelist 1.0, the others 0.0 (P9 maps squadrons to roles here).
- `aircraft` ([roles.aircraft]): each role's airframe rows (above); `fallback` ([roles.fallback]): skirm = wolf.
- `health_x` ([roles.health_x]): duelist / lancer / wolf 1.0, skirm 0.75.
- `lancer` ([roles.lancer]): `alt_add_m` 2000.
- `wolf` ([roles.wolf]): `hold` true, `hold_after_s` 3.0, `hold_max_s` 60, `free_on_hit` true, `free_on_bait_down`
  true, `rehold_s` 1.0, `gun_lead_s` 0.5.
- `skirm` ([roles.skirm]): `laam` true, `laam_m` 7000, `laam_min_m` 2500, `laam_angle_deg` 45, `laam_lock_s` 2.0,
  `laam_interval_s` 4.0, `laam_rest_s` 8.0.
- Build data outside CFG (not in the ini): `ROLE_BY_FLIGHT`, `ROLE.ROWS`, `ROLE.SETS`, `ROLE.LANCER_TOP_M` (9000;
  the build checks it against survival_events.LANCER_MAX_ALT_M).

### Log lines to look for in a test
- Main menu: `behaviour: set NLID_SV_Lancer in (NLID_0012_CP with EscapeFromPursuerLua = LA_SV_Escape,
  MoveAwayFromTargetLua = LA_SV_LancerZoom, ProvokeFarLua = LA_SV_LancerBreak, ProvokeMidLua = LA_SV_LancerBreak,
  ProvokeNearLua = LA_SV_LancerBreak, PursueTargetLua = LA_SV_LancerPass)` and the same for NLID_SV_WolfLead / WolfWing / Skirmisher;
  `game Lua: stock SurvivalMode.AI.LA_SV_LancerPass: true ...` for each new script;
  `roles: behaviour rows lancer sv_role_lancer -> SV_Role_Lancer flies NLID_SV_Lancer; wolf ...; wolf_wing ...; skirm ...`
  (a set not made: `... flies NLID_SV_Fighter (wanted NLID_SV_WolfLead: not made)`; an older container:
  `lancer NOT made (no mission row sv_role_lancer in DT_SV_NpcMission ...)`);
  `weapons: NPC_FCS_PlaneGun000 -> NPC_FCS_PlaneGun000_SV_WOLF (the Wolf airframes' gun: ..., leads 0.50 s)`,
  `weapons: NPC_FCS_PlaneLAAM000 -> NPC_FCS_PlaneLAAM000_SV_SKIRM (the Skirmishers' LAAM: lock within 7000 m / 45 deg,
  never inside 2500 m, ...)`, `weapons: OP1002_f02a_01_SV carries NPC_FCS_PlaneLAAM000_SV_SKIRM (slot 3)`.
- Level load: `roles: at level load lancer NLID_SV_Lancer, wolf NLID_SV_WolfLead, skirm NLID_SV_Skirmisher` (or
  `roles: off; every fighter flight flies the fighters' set, drawn as before (the Lancer units keep their 9 km band)`);
  then, before round 1,
  `game Lua: built ... LA_SV_LancerPass x1, ... LA_SV_WolfDrag x1, LA_SV_WolfStrike x1, ... LA_SV_SkirmPass x1 ...;
  errors 0` (each built once a desc's row names its set: the proof the per-object Wolf rows work is WolfDrag AND
  WolfStrike both built).
- Each round: `roles: round 10 (the mix from round 10: duelist 0.30, lancer 0.25, wolf 0.25, skirm 0.20): 24 of 24
  aircraft: duelist 8, lancer 6, wolf 6, skirm 4` (`; short: wolf 24 of 26; filled from skirm 2` when a group runs
  short; `an ace round's mix` in an ace round); each spawn `round 10: ERA_Unit_03_Dep_Air1 [lancer] as f15c_common_svb
  (lancer, ...), 21 km out at bearing 140, 5.3 km up: 4 aircraft up`; `roles: no skirm airframe yet in round 2; its
  flights fly wolf's`.
- Tells: sv_tells.lua's `tell: lancer: ... tell callout 'BANDITS HIGH'` and `tell: skirm: ...`, once a round each.
- The Wolf trap: `roles: ERA_Unit_05_Dep_Air1 (wolf) trap 3 s after its orders: held B, D`, then one of
  `roles: ... trap freed (you hit it): B`, `... freed (its bait C is down): D`, `... freed (its lead, bait A, is down): B, D`,
  `... freed (held 60 s): B, D`, `... trap: B down while held`, `... trap again after your decoy: held D`; inside your
  decoy `... trap kept (<why>): your decoy stands its flight down for 25 s more[; not sprung]` (once a decoy); the director's spring (unit 6) `... freed (<why>): B, D, turned onto the
  player`. Not fired: `... none held (not fired: RE_SV_WolfHold_14B <why>)`; `roles: <unit> (wolf) never got its orders`.
  Co-op host: `coop: <unit> holds its Wolf trap; it doesn't go after the joiners`.
- Health: `late: round 5 enemies' health x0.75 (skirm x0.75) (<plane>: 600 -> 450)` (once a round per role).
- `ai:` lines by role: a Lancer's short PursueTarget then a long MoveAwayFromTarget; a Skirmisher's MoveAwayFromTarget
  right after a launch; a held Wolf wing in FollowFormation (or Patrol) until freed, then PursueTarget. Errors:
  `roles: setup error`, `roles: level load error ... roles off this level`, `roles: wolf error ...`.

### Test checklist (in game)
1. The pipeline: the main-menu lines above, then at level load all seven new modules `built ... x1; errors 0` (with
   WolfDrag and WolfStrike both built, the per-object rows of one desc work: the brief's open question).
2. A Lancer flight ([roles.mix] lancer = 1, 1, 1, the others 0): spawns ~2 km above the rest; slashes through once
   (ai: short PursueTarget) and climbs away (MoveAwayFromTarget ~10 s); no `ReturnToUnit` right after spawning high or
   at the top of a zoom (the critic's [?] for the raised band); on its tail it runs and reverses, never turns with you.
3. A Wolf flight ([roles.mix] wolf = 1, 1, 1): the held odd planes stop attacking ~3 s after their orders and follow
   their lead (FollowFormation [I]); the bait drags when tailed (straight / lazy jinks, then the 8 s run). Shoot a held
   one: it's freed and attacks. Shoot bait C of a 4-ship down: D alone freed; the lead (A): all freed. Wait 60 s: all
   freed. A DECOY on a Wolf flight: nothing freed inside it (shoot a held one then: freed when the decoy ends), held
   again a second after it ends. Its guns lead you (gun hits while you jink).
4. A Skirmisher flight ([roles.mix] skirm = 1, 1, 1, round 9+): a LAAM from 5-7 km, the break-off as it launches (ai:
   MoveAwayFromTarget right after), back ~12 s later; never closes inside ~3 km; dies quicker (x0.75).
5. Mixed rounds 1, 4, 10, 20: the `roles: round N` line's shares; the first Lancer / Skirmisher callout once a round;
   the jammer ([jammer] chance = 1.0, from_round = 2) only on a duelist or Skirmisher flight; a raid's escorts never
   Wolf flights.
6. Roles off ([roles] enabled = false, restart): every role row `flies NLID_SV_Fighter`, `roles: off`, no `roles:
   round` lines: the old game.
7. Co-op: a joiner's copies of a held Wolf plane don't shoot it; `RE_SV_WolfTurn` never in a joiner's "ev" lines.

### Offline test
`sh tools/checks/roles_test.sh` (tools/checks/roles_test.lua on the real parts and Scripts/ai, Lua 5.4.6; then a Python
check of survival_events' split):
- the 7 scripts built as the game builds them (one root, parents first, unique names, one child per decorator /
  probability, probabilities under a RandomSelect) and walked through every pick of every RandomSelect by tailed_test's
  runner model (extended with IsFireMissileFinished and an abort mid-task) in 600 situations (rank 1-5, AI level 1-5,
  mid / top / floor of the band, a missile counted or not, an abort or not, post-stall or not): the Lancer's pass always
  the slashing one (lead pursuit, a7 extend, a11 head-on break, KDS blocked) into its zoom; the zoom climbs only below
  the band's top and always extends (at most 9.8 s); the Lancer break and the Wolf drag each one move under the 6 s
  blackout (4.7 / 3.5 s), the drag never a hard break; the Wolf strike always pursues close, its Super only at AI 5; the
  Skirmisher's pass breaks off when its counter trips at entry or mid-pursuit; a fixture shows the model finds the fault
  of the gate straight in the root (no break-off), the reason for its own LaxSequencer;
- the rows at the main menu on the real setsSetup / searchSetup / rolesSetup with fake DT_NPC_LuaSet, DT_NPC,
  DT_SV_NpcMission, DT_NPC_FCS and DT_NPC_Weapon tables: the four sets (their slots, the rest stock), the role rows
  naming them with Survival's search module, a set not made (its role row on NLID_SV_Fighter, ROLE.levelLoad drawing
  those flights as duelists), roles off (every role row NLID_SV_Fighter, no Wolf gun lead, no Skirmisher LAAM), no role
  row (the group sits out); the Wolf airframes' leading gun at every spike level, the Skirmishers' LAAM copy at every
  level, a duelist's random special;
- the draw on the real startRound (200 rounds each at rounds 1, 6 and 15): each role's share of the aircraft within
  0.12 of the mix; round 35's 60 drawn whole by role in every one of 60 rounds (pickFlights alone came up 2-4 short in
  1 round of 5: the reason for exactFlights); a group too small for its share filled from the rest; an ace round's 24 duelists first; the jammer
  only on duelist or Skirmisher flights (150 rounds); a raid's escorts never Wolf flights (100 rounds); roles off as
  before; the probes never; a role sitting out never drawn nor a spare;
- spawnFlight: each role's airframes at round 10, the Skirmishers' Wolf airframes at round 2 (logged) and their own at
  round 9, the Lancers 4.0-6.5 km up and 8.5 km at most, the tells once a round each (and none with [roles] tells off),
  a Wolf 6-ship's trap objects 1, 3, 5;
- WOLF.tick: no hold before the flight's orders, before hold_after_s or while grounded; held B, D; a hit frees one; a
  decoy's end holds the rest again once; the lead down frees the rest; hold_max_s frees all; the spring frees and turns;
  the flight down or a hold event the container hasn't got drops it; hold off; co-op forwards hold / free, keeps turn;
  (review fixes) bait C down frees D alone; a held plane shot down is dropped, nothing fired; a recycled flight's earlier
  planes free nothing; inside a decoy (the real sv_tactical TAC.decoyed) a hit, the lead down and hold_max_s free
  nothing and the spring answers 0 (logged once), after it the hit one is freed, the rest held again, then the timer;
- a tier's levers (ACE.hunt, ACE.movesTick on stubbed planes, the Reaper tier): a duelist reverses and loses its
  provoke as before; a Lancer, Wolf and Skirmisher flight does neither (logged); an ace squadron in a Lancer flight does;
  roles off as before;
- enemyLate: a Skirmisher x0.75 with MaxHealth lowered, x0.75 on top of the late rounds', not an ace squadron's,
  nothing with roles off;
- the build's split (Python): 24 / 24 / 24 / 14, each flight's row, the Wolf objects' rows by parity, 12 trap objects.
build_all.sh: `events: 628 triggers, 1360 execs`; the WD's rows and the Lancers' 9 km band read back from the built
WD_SurvivalMode_global (every Wolf flight `sv_role_wolf_lead, sv_role_wolf_wing, ...`; ep_dump shows
RE_SV_WolfHold_14B as LiveAIEngagementOrder None on ERA_Obj_01_Air11_su33_7 alone).

### Untested / known limits
- Everything in game [V at most]. In particular:
- Different rows on the AI objects of one desc (the Wolf bait / trap): every unit had one row so far (the brief's
  risk). If WolfStrike never shows as built, the trap flies the bait's set; the hold still works (it's an engagement
  order, not a behaviour).
- A per-object LiveAIEngagementOrder / LiveAIRequestUniqueAction on a pool plane (the stock form, never used by
  Survival); what a later unit-wide order does to a per-object None (every engagement order rewrites the five
  permission bytes: BEHAVIOUR_NATIVE_LOGIC 8.5, so a hunt, escort or DecoyEnd frees the trap: handled for those three);
  where a held plane flies (FollowFormation with its lead, or Patrol in its 40 km area [I]); whether None also stops
  its evasion and flares [I] (a held plane may be a free kill: free_on_hit frees it at the first hit).
- The Lancers above Mission 22's band: whether 9 km max changes anything else of their unit [?]; whether the zoom's
  50 deg climb, then FlyStraight (no attitude change: it keeps climbing) and MoveAwayFromTarget leave it too high or too
  slow for the next pass.
- IsFireMissileFinished's counter (zeroed by UPDATE_AI_STATE, [I]): if it only resets on a state change, a Skirmisher
  that fired in its previous pursuit still breaks off at once (the break-off comes either way: its own LaxSequencer).
- IsAroundPlayer wasn't used (its direction is ambiguous in the notes), so "never inside 3 km" rests on the head-on
  break (a11-a13, 3 km), the extend when you leave its nose cone and the LAAM copy's 2.5 km minimum.
- Lowering MaxHealth live (raising it is confirmed: AB.L..IN). SpdRelative 300 with range 1500 on the drag (copied
  from the stock escape's form; its exact meaning [I]).
- Role picks run on the host; a joiner's copies fly the same units. A joiner who links after a hold doesn't get it.
  A joiner can't tell an ace squadron (D.aceSquad is the host's), so its copy of an ace in a Skirmisher flight is cut
  to x0.75 there too (the host's plane isn't; the host decides the kill).
- The Wolf airframes' gun lead also arms the Skirmishers' rounds 1-3 fallback flights.
- Ace squadrons: ace_mix puts them in duelist flights first (they keep the Super pursuit); overflow lands in other
  groups (the Wolf strike has its own Super; the Lancer pass and Skirmisher pass don't). P9 maps squadrons to roles;
  since the code review of 2026-10-29 a duelists' squadron's overflow takes the Wolf pairs first.
- No COOP_TAG / VERSION bump yet (the contract's single bump at the end): 36 new events, 4 new mission rows, new world
  data. A joiner on an older build would spawn the role units with rows it hasn't got.

### Review fixes (after unit 5's review; not yet run in game)
1. Your DECOY now wins over the Wolf trap's releases. A decoy (RE_SV_Decoy_NN, unit-wide engagement None for decoy_s)
   on a Wolf flight while its trap was held: shooting the bait down, a hit or hold_max_s ending inside it fired
   RE_SV_WolfFree_<NN><L> (PlayerOnlyNoLimit on that object), and the trap planes came back while the item should keep
   the flight stood down (forwarded to the joiners' copies too). Now WOLF.tick releases nothing inside a decoy
   (TAC.decoyed): the reasons are states (the timer, a plane down, its damage), so the releases come at its end, and the
   rest are held again rehold_s later, as before. `WOLF.free` (U6's spring) answers 0 inside one, fires nothing (no
   free, no turn) and logs `roles: <unit> (wolf) trap kept (<why>): your decoy stands its flight down for N s more; not
   sprung` once a decoy: call it again after. Its optional 5th argument is the round clock (D.now when nil).
2. The trap releases by pair: each held plane (odd k) is freed when its own bait, the plane before it (k - 1), goes
   down (`... freed (its bait C is down): D`); the flight's lead (object 0) down still frees them all (`... (its lead,
   bait A, is down)`). In a 4- or 6-ship, bait C or E down left D or F held for up to 60 s before. A held plane shot
   down is dropped without an event (`... trap: B down while held`), so a flight whose held planes are all down stops
   counting as holding (WOLF.holding: the hunts skipped it until hold_max_s). Only this spawn's planes count (p.born at
   or after its WOLF.spawned): a recycled flight's earlier planes stay on the list, down, until the round's end.
3. A skill tier's no_provoke and moves (CFG.aces.flight; the Reaper's, which every ordinary flight is from round 28:
   TIER.pick) no longer apply to Lancer, Wolf or Skirmisher flights (ROLE.ownSet, sv_spawn.lua; ACE.hunt and
   ACE.movesTick, sv_ai.lua): no_provoke switched bPermissionToProvoke off every 2 s, so LA_SV_LancerBreak, LA_SV_WolfDrag
   and the Skirmishers' defence never ran, and the reversal (RE_SV_AceTurn_NN, LastTGT on every plane of the flight)
   turned Lancers with you and the held Wolf trap onto you: late rounds lost the roles. Duelists (a role flying the
   fighters' set counts) and ace squadrons in any flight keep their tier's levers (since the code review of 2026-10-29:
   a squadron's role flight keeps them only where its tier has them, Harvest's; Bounty's Lancers and Valkyrie's Wolf
   pairs are their roles' own, for the squad director's cover and push too); the hunt itself (TargetActor kept on
   you, its tell) stays on every flight of the tier; roles off, as before. Logged once a flight a round: `aces: <unit>
   (lancer) keeps its role's own provoke and pursuit (the Reaper tier's no_provoke / moves are for duelists and ace
   squadrons)`.
4. NLID_SV_Lancer's ProvokeFarLua is LA_SV_LancerBreak too (the brief's near / mid / far): far it kept NLID_0012_CP's
   Provoke_0011_CP_l, TurnNormal turns of up to 180 deg against the pursuer, so a Lancer tailed from far turned with
   you. The set's main-menu line now lists ProvokeFarLua.
Still open (unchanged): the single COOP_TAG / VERSION bump; the Wolf events through the plain "ev" forward (no "dv"
timing guard against a joiner's own appearance orders) and no hostSync replay of a hold to a joiner who links late; the
spring itself (U6: it must pick the bait it watches by pair and goes through WOLF.free, which now waits out a decoy); the
Wolf bait's ProvokeMid / Far stay stock 0012_CP turns (the drag only when tailed close); ace rounds' overflow into role
flights until P9; everything in game.

## Unit 6: the squad director (P2)

The thesis' P2, "one Lua part that watches the whole sky and fires remote events on the right plane": a new part,
Scripts/sv_director.lua (global `DIR`), loaded after sv_tells and before sv_menu / sv_coop (main.lua MODULES), ticked
every 250 ms from sv_main.lua's probeTick right after ACE.movesTick (timed "director" in the `perf:` line). Six tactics,
each built only on levers already proven or on the same stock records: each is said first (unit 4's tells: the action
its `lead_s` later through TELL.after), has a cooldown and a budget a round, and is counted by STATS.tactic (unit 1:
a `director:` line, the planes involved tagged `p.dirTag = { tactic, at }`, which unit 3's kill bonus pays x1.5 on).
Host or solo only: on a co-op joiner DIR.tick does nothing of its own (P4's `DIR.clientTick` runs there: unit 7).
Lua, survival.default.ini and the build (tools/survival_events.py `build_director`: 134 new remote events). No COOP_TAG
or VERSION bump (the contract's single bump comes last), but the event package changed: that bump must come before any
co-op build goes out.

| tactic | when | tell first | what happens | lever | a joiner as the target |
|---|---|---|---|---|---|
| cover | a player on an enemy's tail (within cover.tail_km 3 / tail_deg 70 of its six) for tail_s 3 | `cover_ask` at ask_s 1.5 (the tailed one's radio "Someone cover me!"), then `six` (urgent: BANDIT CUTTING IN / CHECK YOUR SIX, lead 1 s) | the nearest plane of another pool flight within range_km 6 of that player that may turn (a duelist's, or an ace squadron's whose tier has the reversals, Harvest's; never a Lancer, Wolf or Skirmisher flight, Bounty's and Valkyrie's included: ROLE.ownSet) turns its whole flight onto them; its next reversal no sooner than move_s 30 (D.aceMoveAt, shared with the aces' own) | RE_SV_AceTurn_NN (LastTGT by flight, confirmed 2026-10-23) | LastTGT would turn onto the host: RE_SV_Hunt_NN (AIFirst) and the flight's TargetActor kept on that player's stand-in for aim_s 20, then its orders back |
| trap | a player on a Wolf bait's tail (an even plane of a Wolf flight whose next plane is held: unit 5) for spring_s 2.5 | trap.warn (`drag`: HE'S DRAGGING YOU) at drag_s 1, then `trap` (urgent: IT'S A TRAP, lead 1 s) | that bait's own held wingman is freed and turned onto the player | WOLF.free(unit, why, true, k): RE_SV_WolfFree + RE_SV_WolfTurn_<NN><L> | freed without the turn, its TargetActor on the stand-in for aim_s |
| bracket | two enemies within bracket.range_km 4 of a player, their noses within nose_deg 60 of them, 60-120 deg apart around them (sep_deg) | `bracket` (urgent: MISSILES FROM TWO SIDES / BREAK NOW, lead 1 s) | each fires one missile at the player, in the same tick | RE_SV_Salvo_<NN><L> (new: Mission 19's LiveFireOneShotWeapon, WN_WEAPON_3 = fire-control slot 2, hard rule 40), only planes whose row has its missiles there (SR.mslSlot) | its own copies fire at it ("dv", the lead timed there) |
| top cover | a Lancer flight (top_cover.roles; roles off: any, any_without_roles) up, its orders in, hold_after_s 3 on | `dive` (urgent: BANDIT DIVING / HIGH, n O'CLOCK, lead 1 s, then the o'clock line) when it dives | held at engagement None until a player has fought another flight (within engage_km 3) for engaged_s 3 and it's been held min_s 8: then it dives on that player. Let go quietly at max_s 45, when hit, as the last flight up but held ones (any round state; not while a wave still spawns; inside P4's intensity hold at its end, 30 s at most: unit 7), or at the player's decoy's end (inside a decoy nothing of ours frees it). A wave's first flight up, more of it to spawn: asked again each second until another's up (TOP_WAIT_S 30 s at most), refused only once the wave's out with nothing else up | RE_SV_DirHold_NN / RE_SV_DirFree_NN (new: the MOONCHILD hold / the appearance's orders, by flight; forwarded, so the joiners' copies hold too) | freed, then RE_SV_Hunt_NN with its TargetActor on the stand-in |
| pincer | a new wave (startRound's first, each later one) of 2+ fighter flights, not a special's or a raid's, with chance 0.6 | `pincer` (TWO GROUPS INBOUND / FROM THE x AND THE y) once both sides have a flight up (SV_Spawn's word: DIR.spawned), to every player | its flights alternate on two compass bearings sep_deg 90-150 apart (spread_deg 10), solo around you ring_km 12-18 out (ahead: either side of your nose), in co-op around the airfield (CFG.distance_km); each nose on the centre | spawnFlight's point (spawnPoint with a centre; SV_Spawn's pose reaches the joiners in "sp") | the same for everyone: room news |
| regroup | a flight of min_size 4+ down to half its planes (this spawn's), after_s 10+ after it came up | `regroup` (BANDITS REGROUPING; "They're trying to regroup.") | breaks off (engagement None) for hold_s 7, then its orders back | RE_SV_DirHold_NN / DirFree_NN | the same (forwarded) |

"Its orders back" is RE_SV_DirFree_NN (air-only search, PlayerOnlyNoLimit, as its appearance's), plus RE_SV_Hunt_NN again
for a flight the co-op host had sent after the joiners (COOP.hunted) or one aimed at a joiner.

### What was built
| piece | where | what it does |
|---|---|---|
| the part | Scripts/sv_director.lua (`DIR`; 58 of 200 locals) | DIR.tick (4 Hz: who's on whose tail, who could bracket whom, at most one tactic started a tick; 1 Hz: aims, holds, the pincer's count, top cover's holds, regroups), DIR.roundStart, DIR.wave, DIR.spawnAt, DIR.spawned, DIR.holding, DIR.aimed, DIR.release (for P4), DIR.holds (a late joiner's replay), DIR.SALVO_FCS_SLOT 2. State in D.dir (a new level or run clears it), per plane p.dirTail (a tail episode) and p.pose |
| players | COOP.players() (sv_coop.lua; `rot` added for the others) | the targets: alive, flying, fresh; past [director] players (4) you and the others round-robin. A tail episode is judged only on a tick its player is looked at: one not looked at keeps it while they fly within near_km of its plane (D.dir.flying, the sweep's positions), and nobody else's starts on it meanwhile; it ends after two looks off its tail TAIL_GRACE_S 1 s after the last on it (solo and up to 4 players: every tick, as before). Code review of 2026-10-29: it ended on every tick they weren't picked, so cover and the trap never came for a joiner with 5+ players up. The Offline edition (COOP nil): you from the pawn |
| perf | sv_director.lua fastTick | candidates from the 2 s sweep's p.at within near_km 6 of a player; fresh position + heading reads for at most reads 8 a tick, the planes likely tailed first (a tail episode open, the sweep's p.tailing, or its last pose against the player), then the nearest; the read kept in `p.pose`, which the tail watch (sv_stats.lua STATS.tailTick, run after it) reuses: one read a plane a tick between them. No FindAllOf, nameOf or StaticFindObject; decisions logged, never ticks |
| budgets | CFG.director.budget, cooldown_s, gap_s | per round by the band of the latest from_round reached (cover, trap and bracket each player's; top cover, pincer, regroup the room's); a tactic's cooldown; gap_s between any two the director starts (not the pincer, not top cover's hold). P6's hook: D.counter.tail (when P6's unit sets it) multiplies the cover and trap budgets and divides their cooldowns (the critic's gap fill (a)). A budget of 0 is silent |
| tells first | CFG.director.need_tell | a tactic waits until its tell can be said (TELL.ready: the tells' gaps, cooldowns, line_gap_s); this game's tells off ([tells] enabled = false), it goes without one, at once (TELL.after's own rule). The pincer's tell comes once both sides have a flight up (you may be grounded as a round starts) |
| the salvo | tools/survival_events.py `SALVO_SLOT`, `build_director`; sv_rows.lua searchSetup (`SR.mslSlot`); sv_spawn.lua (`D.flightRow`) | RE_SV_Salvo_<NN><L> on the 86 objects of the 22 usable pool flights (POOL_OBJS, the probe flights left out), WN_WEAPON_3, target Player. Static check of DT_NPC: 246 of the 261 OP1xxx rows have their first missile slot at 2. At the main menu every row Survival flies has its first missile slot recorded (all levels); the director fires a plane only when its row's (the lead's own row for k 0, D.leadRow, else its flight's, D.flightRow) is 2. Never the special slot: it differs between co-op games |
| holds | `build_director`; sv_director.lua hold / release | RE_SV_DirHold_NN (engagement None by flight) and RE_SV_DirFree_NN for all 24 pool flights. RE_SV_Decoy_NN couldn't be reused: it's each player's own (KEEP_EVENTS), so a joiner's copies would have gone on shooting (the critic) |
| what a hold changes elsewhere | sv_allies.lua ALLY.tick's hunts, sv_coop.lua's split hunts, sv_ai.lua ACE.movesTick | a held flight isn't sent hunting the allies; the co-op host's split hunt waits (every 2 s, as long as the hold lasts, at most top_cover.max_s + 120 s) and goes after the hold, so the hunt doesn't free it; the aces' reversals skip it |
| aims | sv_director.lua aim / aimsTick; sv_ai.lua ACE.hunt | a flight sent after a joiner: blackboard TargetActor = that player's stand-in, written once a second for aim_s; ACE.hunt leaves an aimed plane's TargetActor alone (DIR.aimed) |
| the pincer | sv_spawn.lua spawnPoint (a centre, a 5th value: on the bearing or not), spawnFlight (DIR.spawnAt; the yaw towards the centre); sv_rounds.lua (DIR.wave at startRound's end and in the "wave" branch) | a side over the zone's edge falls back to the normal spawn (logged; that flight isn't part of the pincer); the flights that came up on a side tagged and the tactic counted once all are placed (1.5 s after the last, or 60 s after the first); one side only: no pincer, its budget back |
| co-op "dv" | sv_coop.lua COOP.dispatch, the joiner's "dv" handler and queue (clientRounds) | host -> one joiner: an event, its flight, a delay. Only `RE_SV_Salvo_<NN><L>`, `RE_SV_Dir<a>_<NN>`, `RE_SV_Wolf<a>_<NN><L>` (NN the flight's own pool index), delay clamped 0-3 s; the joiner drops it while its level loads, when it has no live copy of that plane (by letter; any copy for a flight's event), when the delay isn't finite, past 8 a second; never queued past its delay; "rs" clears it. KEEP_EVENTS += `^RE_SV_Salvo_` (RE_SV_DirHold / DirFree forwarded) |
| COOP.hunted(unit) | sv_coop.lua | a flight the host sent after the joiners this spawn (its hunt's M.units gen) |

### CFG keys (CFG.director; `[director]` and its sections in survival.ini; the host's for the room)
- `enabled` true, `need_tell` true, `gap_s` 5.0, `near_km` 6.0, `reads` 8, `players` 4,
  `skip_specials` = anomaly, glitch, valka, ladon, alicorn (their own scripts run those fights: nothing new starts).
- `budget` ([director.budget]): `from_round` 1, 5, 10, 20; `cover` 1, 1, 2, 2; `trap` 1, 1, 2, 2; `bracket` 0, 1, 1, 2;
  `top_cover` 0, 1, 1, 2; `pincer` 0, 1, 1, 1; `regroup` 0, 0, 1, 1 (the thesis' "3-6 a round" is the target, these the
  most: what comes depends on the chances the sky gives).
- `cooldown_s` ([director.cooldown_s]): cover 30, trap 20, bracket 25, top_cover 30, pincer 0, regroup 30.
- `cover`: `enabled`, `tail_km` 3.0, `tail_deg` 70, `ask_s` 1.5, `tail_s` 3.0, `range_km` 6.0, `move_s` 30, `aim_s` 20.
- `trap`: `enabled`, `warn` drag (a tell id; lure is the enemy's "I'll lure him into your sights!"), `drag_s` 1.0,
  `spring_s` 2.5, `aim_s` 20.
- `bracket`: `enabled`, `range_km` 4.0, `nose_deg` 60, `sep_deg` 60, 120.
- `top_cover`: `enabled`, `roles` = lancer, `any_without_roles` true, `hold_after_s` 3.0, `min_s` 8, `max_s` 45,
  `engage_km` 3.0, `engaged_s` 3.0, `aim_s` 20.
- `pincer`: `enabled`, `chance` 0.6, `sep_deg` 90, 150, `spread_deg` 10, `ring_km` 12, 18, `ahead` true.
- `regroup`: `enabled`, `min_size` 4, `after_s` 10, `hold_s` 7.
- Build data outside CFG: `DIR.SALVO_FCS_SLOT` 2 (the build checks it against survival_events.SALVO_SLOT
  'WN_WEAPON_3').

### Log lines to look for in a test
- Main menu: `director: N rows carry their missiles in fire-control slot 2 (WN_WEAPON_3: the salvo)[; not: <row> <slot>, ...]`
  (a row listed there never fires the salvo).
- Each round: `director: round 12's budgets (from round 10): cover 2, trap 2, bracket 1, top_cover 1, pincer 1, regroup 1`
  (`; cover and trap x1.50 (your tail chasing)` once P6 sets its counter).
- Each tactic: STATS.tactic's `director: round R +T s: <tactic> on <unit> (n planes)[, player N] (<why>); callout "<tell>"`
  (bracket and pincer `on the round`, the planes named in the why), then its action:
  `director: cover: RE_SV_AceTurn_05 fired` (a joiner: `director: cover for player 2: RE_SV_Hunt_05 fired`),
  `roles: <unit> (wolf) trap freed (the director's spring: you chased bait A): B, turned onto the player`,
  `director: bracket: RE_SV_Salvo_02A fired, RE_SV_Salvo_04B fired` (a joiner: `director: bracket on player 2's copies in
  1.0 s ("dv"): RE_SV_Salvo_02A sent, ...`), `director: top cover: <unit> held at engagement None until you're in a fight
  (RE_SV_DirHold_07 fired)`, `director: regroup: <unit> breaks off for 7 s (RE_SV_DirHold_02 fired)`,
  `director: <unit> back in the fight (<why>): RE_SV_DirFree_07 fired[, RE_SV_Hunt_07 fired]`,
  `director: pincer: wave 1's 3 fighter flights from two sides, bearings 29 and 151 (122 deg apart) around you`, the
  spawn lines' `... at bearing 35 (compass) from you, a pincer side`, `director: <unit>'s TargetActor kept on player 2's
  plane for 20 s (4 planes; cover)`, `director: <unit> down while held (top cover)`, `director: <unit> back in the fight (top cover,
  freed by your decoy's end): RE_SV_DirFree_07 fired`, `director: <unit> stays down with your decoy (<why>): let go at its
  end` / `...: its orders back at the decoy's end`, then `director: <unit> back in the fight (<why>, after your decoy): ...`,
  `director: pincer: wave N's flights didn't come from two sides (...): no pincer, not counted`, `coop: player N brought
  up to date: RE_SV_DirHold_07` (a joiner who linked during a hold).
- The tells, unit 4's: `tell: cover_ask: RE_SV_RadioEnCoverA (fired)`, `tell: six: ..., tell callout 'BANDIT CUTTING IN'`,
  `hud: tell 'BANDIT DIVING' / 'HIGH, 3 O'CLOCK'`, `tell: dive: RE_SV_RadioDiveB (fired), then RE_SV_RadioClockC (fired)`, ...
- Held back (once a round per tactic, player and kind of reason): `director: cover not now (its budget, 1 of 1 this
  round)`, `(its cooldown, 12 s more)`, `(the director's gap, 2.0 s after its last)`, `(no flight within 6 km to cover
  <plane>)`, `(its tell can't be said now)`; `director: top cover: <unit> waits for another flight up (the only one; 2
  more of wave 1 to come)` (once), then its hold or `director: top_cover not now (it's the only flight up (<unit>))`;
  `director: pincer: <unit> fell back to a random point (the zone's edge at bearing 151): not part of it`.
- Co-op: the host's `tell: bracket to player 2 ("tl")`; a joiner's `coop: director RE_SV_Salvo_02A fired here
  (ERA_Unit_01_Dep_Air1): fired` or `coop: the host's director event ... dropped (<why>)` (once per reason).
- The perf line's `director` part (its avg and worst ms). Errors: `director: error ...`, `director: round start error`,
  `director: wave error`, `director: pincer error`.

### Test checklist (in game)
1. Round 3+: get on a fighter's tail and stay there 3 s with another duelist flight within 6 km: "Someone cover me!",
   then BANDIT CUTTING IN, and a second later that flight turns in (`ai:` lines: UniqueAction). Its kill pays
   `director cover x1.5` within 20 s.
2. Wolf flights ([roles.mix] wolf = 1, 1, 1): chase a bait 2.5 s: HE'S DRAGGING YOU at 1 s, IT'S A TRAP at 2.5 s, its
   own wingman (held: FollowFormation) turns onto you a second later (`ai:` PursueTarget / UniqueAction).
3. Round 5+: two fighters coming at you from about 90 deg apart within 4 km: MISSILES FROM TWO SIDES, two missile
   alerts a second later. Check the main-menu salvo line first; whether a forced shot needs a lock is the open question.
4. Lancers ([roles.mix] lancer = 0.5): a Lancer flight holds (no attack; `ai:` FollowFormation / Patrol) until you've
   fought another flight ~3 s (it's held 8 s+), then BANDIT DIVING / HIGH, n O'CLOCK (the o'clock right?) and it
   attacks. Shoot one while it waits: it comes at once, no tell.
5. Round 5+ waves ([director.pincer] chance = 1.0): TWO GROUPS INBOUND / FROM THE x AND THE y, contacts from two sides
   12-18 km out (the minimap), none from behind with ahead = true.
6. Round 10+: shoot two of a 4-ship: BANDITS REGROUPING, they break off ~7 s, then come back.
7. Perf: the `perf:` line's director worst under ~3 ms with 26+ planes up.
8. Co-op (a host and a joiner): the joiner tails a fighter: the tell on the joiner only, a hunt (`ai:` target = the
   joiner's stand-in); a bracket around the joiner: its own copies fire (`coop: director RE_SV_Salvo_... fired here`),
   no RE_SV_Salvo in the joiner's `ev` lines; top cover's copies hold their fire on the joiner while held.
9. Off: [director] enabled = false: no `director:` lines but STATS' "ace reversals".

### Offline test
`sh tools/checks/director_test.sh` (tools/checks/director_test.lua on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud,
sv_spawn, sv_rounds, sv_tactical, sv_stats, sv_tells, sv_director and sv_coop, Lua 5.4.6; planes stubbed as objects with a
position and a heading; then a Python check of the build side's names):
- [director] sections read from a survival.ini; every tactic's switch on as shipped; the budgets by band (round 3, 12)
  and P6's factor;
- cover: nothing before 1.5 s, the call for help at 1.5 s, the six tell at 3 s and the duelist flight's AceTurn 1 s
  later (not a nearer Lancer's, not an escort's), the tag on the covering plane only, D.aceMoveAt, the budget (once,
  logged once), the cooldown in round 12 then the second, the gap, nothing grounded / in an Anomaly round / switched off
  / on a joiner / with no duelist in range (logged); tells off: at 3 s without a tell; an ace round's squadrons in Lancer
  flights (the code review of 2026-10-29): Bounty's never the cover nor P4's push, Harvest's (the Reaper tier's moves) may be;
- the reads: 21 planes near you, 8 reads, the one you're likely on the tail of first; the tail watch reads nothing more;
- the trap: drag at 1 s, the trap tell at 2.5 s, its own wingman B freed and turned (D left held), no cover instead;
  nothing inside your decoy;
- the bracket: the tell, no shot in its lead, both shots 1 s on in one tick, both tagged; its budget; nothing at 30 or
  150 deg, with a nose away, a slot-3 row, a held flight, or no budget (and no log of it);
- top cover: the hold 3 s after its orders (not the duelists'), no dive under min_s, the dive with HIGH, 3 O'CLOCK and
  ClockC, DirFree after the lead, tagged; let go when hit, as the last flight, at max_s, at your decoy's end (DirFree
  then, none inside it; a dive's release inside a decoy waits for its end, DIR.release too); a held 6-ship as the wave's
  last in state "wave" let go at once (not while a wave's flight is queued); two held flights: one let go; a wave's
  first flight up with one more to spawn not refused (it waits, logged once), held once the next is up, refused once the
  wave's out with nothing else up; no hold without budget; roles off with and without any_without_roles;
- the pincer: around you, either side of your nose; spawns alternating on the two bearings, 12-18 km out, noses on you;
  the spawn line; the tell once with both compass names; counted and 8 planes tagged once up; none for a special's wave,
  a raid's, one flight, no budget; co-op around the airfield; the zone's edge (logged, a normal spawn); one of 3 fallen
  back: 2 of 3 counted, its planes untagged; one side only: no tell, no tags, not counted, its budget back; both sides
  placed but side 2's flight refused by SV_Spawn: no tell;
- regroup: nothing before after_s, the tell + DirHold at 10 s, held 7 s, DirFree; 3 of 4 left: none; the only flight
  up: none (logged);
- SR.mslSlot from the real searchSetup on fake tables (every level; a slot-3 row recorded and named in the line);
- co-op host: a joiner's bracket by "tl" + two "dv" with the 1 s lead, nothing fired here; KEEP_EVENTS; COOP.dispatch's
  refusals; a joiner's cover (the six tell to it only, RE_SV_Hunt_05, its TargetActor on the stand-in, ACE.hunt leaving
  it, its orders back after aim_s; a decoy on it ends the aim, its orders at the decoy's end); the split hunt waiting
  out a hold and going after it (COOP.hunted), a 120 s hold with max_s 600 waited out, a hunted flight's release firing
  its hunt again; a joiner linking during a hold gets RE_SV_DirHold_07 12 s later, none for one let go meanwhile;
  5 and 24 players up (players 4): player 2's tail episode kept on the ticks it isn't looked at, the six tell to it and
  RE_SV_Hunt_05 (far from everyone, or on a plane 3 km from you); over at once when it lands or flies 9 km off; solo's
  episode still ends 1.25 s after the last tick on its tail;
- co-op joiner "dv": dropped while loading (logged), queued and fired after its delay, dropped for a name not the
  director's, another flight's number, a plane it hasn't got, a bad delay, a lower-case letter, a long name, a copy
  already down; a flight's event queued with its delay cut to 3 s; 8 a second; "rs"; DIR.tick doing nothing there;
- the aces' own reversal: its flight's next move lead_s + cover.move_s 30 on (the kulbit's lead_s + 12);
- the hooks by their place in the source (MODULES order, the tick order in probeTick, startRound / the wave branch,
  spawnFlight, the hunts' and moves' skips, no SV_Event / hudCallout kept at load).
A mutation check (the salvo's row test or the split hunt's wait removed on a scratch copy) fails 3 of its checks.
build_all.sh: `director: 86 salvo objects in 22 flights (RE_SV_Salvo_<NN><L>, WN_WEAPON_3), 24 flights held / freed`,
`events: 762 triggers, 1518 execs` (was 628 / 1360); ep_dump: RE_SV_Salvo_02A = LiveFireOneShotWeapon {WN_WEAPON_3,
ERA_Obj_01_Air9_su33_0, Player}, RE_SV_DirHold_07 = LiveAIEngagementOrder None on ERA_Unit_03_Dep_Air0, RE_SV_DirFree_07
= AIR_ONLY + Normal / PlayerOnlyNoLimit on it.

### Untested / known limits
- Everything in game [V at most]. In particular:
- A pool fighter's missile forced by LiveFireOneShotWeapon (only AB.L..IN's gun and ECM and the Ladons' VLS are
  confirmed): whether it needs a lock or a cone, whether it counts against the player-attack throttle (ATTACK_BASE's 4,
  unit 3's presets) or the magazine. If nothing comes, the tell still says "missiles from two sides" (the salvo line
  says "fired": SV_Event's 1 is the record running, not a missile).
- LastTGT on duelists that aren't aces (the same request path as the Reaper's, no rank check in it [V static]); one
  flight turning by unit, every plane of it.
- Engagement None by flight on pool flights (RE_SV_DirHold) and whether it also stops their evasion and flares [I] (a
  held flight may be a free kill: hit, it's let go at once); where a held flight flies (FollowFormation or Patrol in its
  40 km area [I]: not "above the fight", the brief's v1 limit; the Lancers do spawn 2 km higher).
- Co-op: TargetActor written to a stand-in under Normal / AIFirst (the hunt's own pick is confirmed, a chosen joiner
  isn't); a forwarded hold on a joiner's copies (the Wolf trap's is the same, also untested); "dv" end to end.
- Regroup is the brief's v1 (break off, close up, come back): rejoining another flight (an area move onto its lead) is
  left out: putting the 40 km area back afterwards needs NearPlayer moves on pool flights, untested, and an area that
  doesn't cover the plane sends it back (ReturnToUnit beats everything).
- p.k <-> the AI object (unit 1's [I], checked by the `spawn index:` line): a salvo or a spring on the wrong plane if
  creation order isn't desc order.
- A player's own DECOY ends with its flight's unit-wide orders (RE_SV_DecoyEnd_NN): a held flight is let go by it, and
  the director's RE_SV_DirFree_NN follows (the same orders here; forwarded, it frees the joiners' copies, which the kept
  DecoyEnd never reached). A joiner's own decoy can still be cut short by a forwarded DirFree (the brief's known
  interaction, coop-perf step 9: a joiner's decoy isn't the host's TAC.decoyed).
- ALLY.tick's hunt and a flight the director holds afterwards: the release gives back PlayerOnlyNoLimit, not the allies'
  hunt.
- The pincer's bearings are from the host's player solo and from the airfield in co-op (for every player the same).
- Budgets and the 3-6-a-round target: what a round gets depends on chances (tails, two noses at once, a Lancer flight up,
  a 4-ship halved); tune [director.budget] / chance after a test's `stats:` lines ("director tactics N").
- No COOP_TAG / VERSION bump yet (the contract's single bump at the end): 134 new events, a new message kind ("dv").

### Review fixes (after unit 6's review; not yet run in game)
1. A held flight is let go as the round's last flight whenever no flight the director doesn't hold is up, in any round
   state (heldTick; `othersUp` skips held flights). Before, only in state "fighting", and held flights counted each other:
   a held 6-ship Lancer top cover whose wave-mates were down in state "wave" (6 alive > waves.next_at 4, timeout_s 0) kept
   the next wave from coming, and two held flights (top cover's budget 2 from round 20) kept each other back, both until
   max_s 45 (an empty sky). Not while a wave's flights are still queued in "spawning" (the next comes spawn_gap_s on).
   The log says the state: `back in the fight (the round's last flight (wave))`. Top cover and regroup no longer start
   on a flight whose only company is held (`it's the only flight up`).
2. Nothing the director fires frees a flight inside the player's DECOY (TAC.decoyed): RE_SV_DirFree_NN is unit-wide and
   forwarded, so it ended the paid item early here and on the joiners' copies. `release` keeps a held flight held inside
   a decoy (the dive's queued release, DIR.release, which returns false then): heldTick lets it go at the decoy's end
   with RE_SV_DirFree_NN. `orders` (an aim's restore after a joiner's cover or dive) puts its orders off to the decoy's
   end (D.dir.after; afterTick), and a decoy on an aimed flight ends the aim. At a decoy's end the director now fires
   RE_SV_DirFree_NN too: RE_SV_DecoyEnd_NN is kept (each game's own), so a joiner's copies held by the forwarded hold
   stayed at None until something else ordered them.
3. ACE.movesTick (sv_ai.lua): a reversal's next move on its flight comes no sooner than its tell's lead_s +
   CFG.director.cover.move_s (30) from the move, not 20 s from the tell, so neither the next reversal nor the director's
   cover (the same D.aceMoveAt) cuts a running LastTGT (~25-30 s; runtime-ai step 1). A kulbit: lead_s + 12 s.
4. The pincer counts and tags only flights that came up on a side: DIR.spawnAt places a flight (pend), DIR.spawned
   counts it once SV_Spawn has it up; one that the zone's edge sent to a normal point is left out (pc.fell: no tag, no
   x1.5 kill bonus, not in "N of M flights"). The sides alternate by the flights placed. The tell comes once both sides
   have a flight; with one side only there's no pincer: no tell, no tags, not counted, its budget back. Its 60 s limit
   runs from its first flight's placing (a wave held while you're down at the airfield keeps its pincer).
5. The co-op host's split hunt waits out a director's hold as long as it lasts (DIR.holding), at most top_cover.max_s +
   120 s (synced, tunable), not a fixed 60 s: a longer hold had RE_SV_Hunt_NN free the host's planes mid-hold while the
   joiners' copies stayed held.
6. A joiner who links during a hold (hostSync) gets RE_SV_DirHold_NN of every flight held when its copies are up (12 s
   on, the specials' replay; DIR.holds read then, so none for a flight let go meanwhile): before, its copies of a held
   top cover or regroup attacked it until the release. The Wolf trap's held planes still have no such replay.
7. A refusal for a tactic with no budget this round band is no longer logged when it names its flight (`top_cover not
   now (off (<unit>))`).
director_test.sh covers each (146 checks); reverting any one of the fixes on a scratch copy of the mod (held flights
counted as up, the "fighting"-only release, either decoy guard, the decoy's-end DirFree, the pincer's two-side test or
its fallback count, the 60 s hunt cap, the replay read at link time, the aces' 20 s) fails 1-2 of them.

Still open (unchanged): regroup v2 (rejoining another flight: an area move onto its lead, then the 40 km area put back)
and top cover v2 (EvadeOnly plus a NearPlayer cover area above the fight) need levers untested on pool flights (area
moves off Mission 22's mark, NearPlayer, EvadeOnly by unit); P4's DIR.clientTick / "in" / holds; coop-perf step 9 (a
joiner's own decoy); the dv guard cases live in director_test.lua, not coop_settings_test.lua; the single COOP_TAG /
VERSION bump (134 new events, "dv"); everything in game.

## Unit 7: the intensity director (P4)

The thesis' P4: "Track a 0-100 intensity score from damage taken in the last 30 s, missiles inbound, enemies within 5 km
and health. Track a comfort score from time spent on an enemy's tail, kills per minute and health above 70 %. When
comfort is high and intensity low for 20 s, the director spends a tactic or releases a held flight. When intensity stays
above 80, it holds the next wave and the top cover back for 15-20 s. Tiers stay as the floor; spikes become the
director's ceiling." Built in Scripts/sv_director.lua as its own `do ... end` block after the squad director's (the part
is at 60 of 200 locals), with hooks in sv_rounds, sv_config, sv_ai, sv_rows, sv_spawn and sv_coop (runtime-ai steps 7-9,
coop-perf step 6). Lua and survival.default.ini only: no build change, no new event, row or behaviour script. No
COOP_TAG / VERSION bump (the contract's single bump comes last): one new co-op message ("in") and an 8th "rnd" field,
both ignored by older builds. Every lever has its own switch in `[intensity]`; nothing here has run in game.

| lever | when | what happens | where |
|---|---|---|---|
| scores | every game, once a second on the round clock (not in a pause) | your intensity and comfort, 0-100 (formulas below); a co-op joiner sends its own to the host ("in") | P4 block: `sample` |
| hold | the host: a player's intensity above `high` 80 for hold.after_s 3 s, in a fight, not a boss round of skip_specials | two holds, each hold.secs 15-20 s (a random time; 30 s hard limit), never made longer, the next of its kind no sooner than hold.gap_s 20 after the last ended. **The wave hold** starts only when a wave is due (roundsTick asks: the wave gate open, the last wave down to waves.next_at or its timeout; or a later wave's next flight up), so a player hot long before the gate opens still gets it then; at most hold.per_wave 1 a wave. **The top cover's** starts (once a second) while the squad director holds a top cover: its dive and its max_s wait. Neither counts for the other's gap or per_wave. Never a round's first wave or a special's entry; nothing due to keep back: no hold. A held top cover hit still goes (P2's rules); as the round's last flight up it waits for the hold's end too, at most LAST_HOLD_S 30 s from when it was the last, whatever the hold's settings (never a stall; code review of 2026-10-29: it went onto a player under heavy pressure at once). While a player's that hot, a wave's flights also come hold.spawn_gap_add_s 3 s further apart | `waveHold` / `DIR.holdWave` (sv_rounds.lua roundsTick: the wave gate and the spawning branch), `holdTick` / `DIR.holdOn` (heldTick), `DIR.gap` (the spawning branch) |
| hold.tactics | a player's intensity above `high` now | the squad director starts no cover, trap or bracket aimed at that player (`director: cover not now (under pressure: intensity 84)`) | `DIR.hot` in P2's blockedBy |
| push | the host: a player comfortable (comfort comfort.high 60+ and intensity `low` 35 or under) for calm_s 20 s of a fight, from push.from_round 3 | "spends a tactic or releases a held flight": a held top cover (the one nearest them; not while the hold is on, not inside a DECOY) dives on them after its dive tell; else the nearest flight that may turn (cover's choice: a duelist's, or an ace squadron's whose tier has the reversals, within push.range_km 8) turns onto them after "check your six" (RE_SV_AceTurn_NN; a joiner: RE_SV_Hunt_NN with its TargetActor on their stand-in for cover.aim_s). push.per_round 2 each player a round, push.cooldown_s 40 apart, the squad director's gap_s and need_tell apply; [director] off: none. Counted and tagged by STATS.tactic as `push` (the dive as `top_cover`), so its kills pay the director bonus | `pushTick`, `DIR.push` (P2 block) |
| level | the host: the room's intensity (its highest player) above `high` for level.down_after_s 30 s of fighting | the spikes become a ceiling: enemies that come from then fly one spike level lower (fire-control rows at spawn, rank_min, post_stall_all, provoke, the next round's aircraft_add), at most level.max_drop 1 under the round's spike (never under 0; the skill tiers stay the floor: their rank, post_stall and fcs); the enemies up get their provoke and PilotRank written again for it (the jammer's boost kept; a level with no provoke for a plane's tier, 0, puts back the game's own values it had). The game's attack throttle (U3's RE_SV_Pressure presets, CFG.late.pressure) goes a letter gentler too (level.pressure: D to C, C to B; never under level.pressure_min B), fired when the ease changes. Below level.up_below 50 for level.up_after_s 60 s of fighting: a level back up (and the band's preset). level.gap_s 45 between two changes. Rounds 1-7 (no spike yet): nothing to ease | `easeTick`, `DIR.level`, `reapply`, `DIR.pressure`; sv_config.lua `levelFor`; sv_rounds.lua `roundPressure`, `pressureNow` |

The scores (CFG.intensity.score / comfort; each part capped at its full mark):

    intensity (raw) = 40 x min(1, damage % of your health taken in window_s 30 / (dmg_full 0.4 x 100))
                    + 25 x min(1, enemy missiles homing on you within msl_km 4 / msl_full 2)
                    + 20 x min(1, enemies within near_km 5 / near_full 4)
                    + 15 x (1 - health % / 100)
    intensity       = intensity + smooth_x 0.35 x (raw - intensity), once a second (a first sample: raw)
    comfort         = 40 x min(1, seconds on an enemy's tail in window_s / (window_s x tail_full 0.5))
                    + 35 x min(1, your kills a minute over kills_window_s 60 / kpm_full 2)
                    + 25 x (health above hp_pct 70 %)

So 80 means really pressed: two missiles on you, four enemies within 5 km and 40 % of your health gone in 30 s at 40 %
health is 94; a quiet pass at 80 % health is 3. Comfortable is health above 70 % plus on a tail half the time (65), or
plus two kills a minute (60).

### What was built
| piece | where | what it does |
|---|---|---|
| the scores | sv_director.lua P4 block: `healthTick`, `mine`, `missilesOn`, `onTail`, `sample` | every tick your health's drops (HIT.h, HP x 10; a repair is no damage, a new aircraft, HIT.pawn, starts over); once a second: the drops of the last window_s as % of MaxHealth (read every 5 s), HIT.msl's missiles seen in the last second within msl_km whose TargetToHome is your pawn (one within 1 km whose target can't be read counts), the sweep's p.dist (2 s old at most), on an enemy's tail (each plane's last pose against where you were at that sample, p.youAt from sv_stats.lua, else where you are now; comfort.tail_km 3 / tail_deg 70), RUN.kills.you's rises, health. Kept in D.int (a new level or run clears it) |
| the room | `decide` (the host, solo) | each player flying (COOP.players(): alive, fresh, not down at the airfield; a joiner's last "in" under 3 s old): hot time (intensity above high) and calm time (comfortable), counted only in fights (spawning, wave, fighting): a pause holds them, a break between rounds, a boss round of skip_specials or the airfield starts that player's over. The room's value is its highest intensity; the level's room timers run in fights only and are kept over a break |
| hold | `waveHold` / `DIR.holdWave(now, what)` (D.int.hold), `holdTick` / `DIR.holdOn(now)` (D.int.cover), `DIR.gap(now)`; sv_rounds.lua roundsTick (the "wave" gate: `(alive <= w.next_at or timedOut) and not DIR.holdWave(now, "wave")`, asked only once the first half is true; the "spawning" branch for D.wave > 1, a plain flight next, after the airfield check; `D.at = now + CFG.spawn_gap_s + gapAdd`); sv_director.lua heldTick (a top cover: its dive and max_s wait while DIR.holdOn) | as the table above; each hold ends by itself (its time), with the round, or when there's no fight |
| push | `pushTick`; `DIR.push(slot, why, rangeKm)` in the P2 block (reuses `coverer` with a range, `dive`, `aim`, `tellAfter`) | as the table above; the calm players most comfortable first, the first one that can have one (one used up, on its cooldown or with nothing to send doesn't keep the next waiting); nothing to send (no flight in range, a tell not sayable, the director's gap): tried again 5 s on, logged once a round per reason. One push a second at most |
| hold.tactics | `DIR.hot(slot)` in P2's `blockedBy` | per-player tactics wait while that player is above high |
| level | `easeTick`, `DIR.level(round)`, `reapply`; sv_config.lua `levelFor(round)` (DIR.level, else spikeLevel) and `TIER.roundBudget(round, level)`; sv_ai.lua enemyTier (rank_min on levelFor; `p.rankBase`, the rank before it) and enemyManeuvers (post_stall_all); sv_rows.lua provokeWant's default level and enemySpike's `p.spiked`; sv_spawn.lua spawnBomber / spawnFlight (fcsLevel = max(levelFor, tier.fcs)); sv_rounds.lua startRound (`TIER.roundBudget(D.round, levelFor(D.round))`) and the spike callout (on levelFor; its log names the spikes' level when eased) | the ease (0 to max_drop) carries over the run's rounds; DIR.level = max(0, spikeLevel - ease). The FCS rows of every level exist from the main menu, so a lower level only picks another row at spawn |
| co-op | sv_coop.lua `COOP.sendIntensity`, `COOP.intensityOf`, the host's "in" handler, "rnd"'s 8th field (DIR.level of the round), the joiner's `D.intLevel` (clientRounds); sv_director.lua `DIR.clientTick` | a joiner samples its own player and sends "in" once a second; the host keeps each joiner's last; a joiner's copies fly the host's level (levelFor reads D.intLevel there) and the enemies up get it written again when it changes. Room-wide: the host decides; a push on a joiner is a hunt (LastTGT turns onto the host) |
| lines | `scoreLine`, `roundLine`; tools/checks/stats_report.py `intensity_lines` | the scores every log_s 10 s of a fight; a round line at its end (every game: yours; the host: its holds and pushes); stats_report.py prints a row per round and the decisions' counts |
| perf | the director's timed "director" part | every tick a number compare (your health); once a second two passes over `planes` (cached fields only), the missile list with a TargetToHome read for each missile within msl_km seen that second, MaxHealth every 5 s, and the room's decisions. No FindAllOf, nameOf or StaticFindObject; decisions logged, scores every log_s |

### CFG keys (CFG.intensity; `[intensity]` and its sections in survival.ini; the host's for the room)
- `enabled` true, `window_s` 30, `smooth_x` 0.35, `high` 80, `low` 35, `calm_s` 20, `log_s` 10 (0: decisions only),
  `skip_specials` = anomaly, glitch, valka, ladon, alicorn (their own scripts run those fights).
- `score` ([intensity.score]): `damage` 40, `missiles` 25, `near` 20, `health` 15, `dmg_full` 0.4, `msl_km` 4.0,
  `msl_full` 2, `near_km` 5.0, `near_full` 4.
- `comfort` ([intensity.comfort]): `tail` 40, `kills` 35, `healthy` 25, `high` 60, `tail_km` 3.0, `tail_deg` 70,
  `tail_full` 0.5, `kpm_full` 2.0, `kills_window_s` 60, `hp_pct` 70.
- `push` ([intensity.push]): `enabled`, `from_round` 3, `per_round` 2, `cooldown_s` 40, `range_km` 8.0.
- `hold` ([intensity.hold]): `enabled`, `after_s` 3, `secs` 15, 20, `gap_s` 20, `per_wave` 1, `tactics` true,
  `spawn_gap_add_s` 3 (0: none).
- `level` ([intensity.level]): `enabled`, `max_drop` 1, `down_after_s` 30, `up_below` 50, `up_after_s` 60, `gap_s` 45,
  `pressure` true, `pressure_min` B (A gentlest, B the game's own; not a preset letter: B).
- Not PERSONAL in co-op: a joiner's scores are weighed with the host's settings (they arrive with the host's "cf").

### Log lines to look for in a test
- Every log_s 10 s of a fight (each game): `intensity: round 12: you 34 (damage 12% of your health in 30 s, 1 missile on
  you, 3 enemies within 5 km, health 81%), comfort 55 (on a tail 8 s of 30, 2.0 kills a minute)`; the host adds
  `; player 2 71, comfort 20`, `; holding wave 3 (12 s more)`, `; level 1 (the spikes' 2)`.
- The hold: `intensity: round 12: held 17 s (player 2 at intensity 86, above 80 for 24 s): wave 3 wait; the room: you
  45, player 2 86` (what it holds: `wave N` at its gate, `the rest of wave N` at its next flight, `the top cover
  (<units>)` on its own), then `round 12: wave 3 waits for the intensity hold (17 s more)` / `round 12: the rest of wave
  2 waits for the intensity hold (...)` / `director: <unit> (top cover) waits for the intensity hold (...)` (the
  round's last flight up: `director: <unit> (top cover), the round's last flight up, waits for the intensity hold too
  (12 s at most)`, then `back in the fight (the round's last flight (fighting))` at its end), and
  `intensity: hold over after 17 s (wave 3)` (`: the round's over`, `: no fight to hold`). The `held` line comes with
  the kill that opened the wave's gate, its `wave N of M` line 15-20 s later. Held back, once a round per wave and kind:
  `intensity: hold not now (you at intensity 88; the last ended 6 s ago, hold.gap_s 20): wave 3 comes` / `(...; wave 3
  had its 1): wave 3 comes` / `(...; the top cover's last ended 2 s ago, hold.gap_s 20)`. The spawn gap: `intensity:
  round 12: wave 2's flights 3 s further apart (you at intensity 88)` (once a wave).
- hold.tactics: `director: cover not now (under pressure: intensity 84)` (trap, bracket the same).
- A push: `intensity: you comfortable 20 s (comfort 60, intensity 3): ERA_Unit_02_Dep_Air1 turns onto you (7.0 km off)`
  or `...: held ERA_Unit_03_Dep_Air0 dives on you (10.2 km off)`; STATS' `director: round 6 +40 s: push on
  ERA_Unit_02_Dep_Air1 (2 planes) (the intensity director: you comfortable 20 s (...); ... turns in); callout "six"`;
  `director: push: RE_SV_AceTurn_05 fired` (a joiner: `director: push on player 2: RE_SV_Hunt_05 fired` and the
  TargetActor line). Held back: `intensity: you comfortable ...: no push (its cooldown, 20 s more)` / `(its 2 this
  round)`, `...: nothing sent (no flight within 8 km may turn onto you)` / `(the squad director is off ([director]
  enabled))` / `(the director's gap, ...)` / `(its tell can't be said now)`.
- The level: `intensity: round 15: the room above 80 for 30 s of fighting (you at 92): enemies from now fly difficulty
  level 1 (the spikes' 2, at most 1 under)`, `intensity: level 1 on the enemies up (eased): provoke written again on 9 of
  11, PilotRank on 7`, `intensity: round 16: enemies fly difficulty level 1 (the spikes' 2, eased for the room's
  pressure)`, `spikes: round 22, difficulty level 2 (the spikes' 3, eased by the intensity director)`, `intensity: round
  17: the room below 50 for 60 s of fighting: enemies from now fly difficulty level 2 (the spikes' 2)`; the spawn lines'
  rows show it (`..._svb` level 1, `_svc` 2, `_svd` 3). A joiner: `intensity: the host's difficulty level for round 15:
  1 (the spikes' 2)`, then its `level 1 on the enemies up (the host's level)`. The throttle: `pressure: round 28: preset
  B (was C, the intensity director's level down; the band's C, a letter gentler)` and back `pressure: round 28: preset C
  (was B, the intensity director's level back up)`; inside an Anomaly / VALKA fight `pressure: round N: the anomaly's own
  throttle is up: the preset after it (...)`.
- Each round's end: `intensity: round 12: you avg 41, peak 88, above 80 for 14 s; comfort avg 37; held 1 (17 s),
  pushes 2; level 1 (the spikes' 2)` (a joiner: no holds / pushes; `, the host's`).
- Errors: `intensity: error ...` (once a run). The perf line's `director` part includes P4.
- `python tools/checks/stats_report.py AC8SurvivalMode_lua.log`: `intensity lines: N: holds H (not now n), pushes P
  (held back n), level eased D, back up U` and a row per round (avg, peak, hot s, comfort, held, held s, pushes, level).

### Test checklist (in game)
1. The scores: fly a normal round 8+ and read the 10 s lines against what happened: damage % after a hit, `N missiles on
   you` while the missile alert sounds (this checks the TargetToHome read; 0 throughout means it can't be read: then only
   missiles within 1 km count), enemies within 5 km, comfort rising while you sit on a tail with kills.
2. The hold (waves on, round 8+): let a wave press you (two missiles, health dropping) and stay pressed while you kill
   the rest down to 4: the `held N s ... wave 2 wait` line comes at that kill (not before, however long you were hot),
   with `waits for the intensity hold`; wave 2 only after the hold (its `wave 2 of N` line 15-20 s after the `held`
   line). Not again within 20 s (`hold not now ... wave 3 comes`). While pressed, a wave's flights ~6 s apart, not 3.
3. A push: round 3+, health above 70 %, kill steadily or sit on a tail: after ~20 s BANDIT CUTTING IN and a flight turns
   onto you (`ai:` UniqueAction); its kill pays `director push x1.5`. With Lancers held ([roles.mix] lancer = 0.5): the
   top cover dives instead (BANDIT DIVING / HIGH, n O'CLOCK).
4. The level: round 15+ ([spikes] on), stay under heavy pressure 30 s: `the room above 80 ... level 1`, the next flights'
   rows `_svb` instead of `_svc`, the `level 1 on the enemies up` line; ease off for 60 s: back to 2. Round 26+: the
   `pressure: ... preset B (was C, ...)` line with it, and fewer enemies pressing you at once.
5. hold.tactics: while pressed, tail a plane 3 s: no BANDIT CUTTING IN (`cover not now (under pressure ...)`).
6. Co-op (a host and a joiner): the host's score lines list `player 2 N, comfort C` (the joiner's "in"); a hold named
   after player 2; a push on player 2 (the tell on the joiner only, `ai:` target = their stand-in); the joiner's `the
   host's difficulty level` line once the host eases.
7. Off: [intensity] enabled = false (or each lever's): no `intensity:` lines, the waves and spikes as before.
8. Tuning after a test: the round lines' avg / peak / hot s say whether 80 / 35 / 60 sit right; move `high`, `low`,
   `comfort.high` or the weights in survival.ini.

### Offline test
`sh tools/checks/intensity_test.sh` (tools/checks/intensity_test.lua on the real sv_core, sv_config, sv_rows, sv_ai,
sv_hud, sv_spawn, sv_rounds, sv_tactical, sv_stats, sv_tells, sv_director and sv_coop, Lua 5.4.6; HIT's health and
missiles as tables, planes as objects with a position and heading; then stats_report.py on its log):
- [intensity] sections read from a survival.ini; every lever's switch on as shipped; the weights add up to 100;
- the scores: health only (3, comfort 25), near (2 of 3 planes within 5 km), missiles (one on you, one unreadable within
  1 km; not one on an ally, one unreadable 1.5 km off, one 5 km off, one gone), damage (40 HP in two drops between
  samples: 40 + 9, smoothed 3 -> 19.1; the window's 30 s; a repair and a new aircraft no damage), smooth_x 1, comfort
  (15 s on a tail 65, two kills 100, a minute later 25; p.youAt over where you are now), MaxHealth read once in 10 s;
- the hold through the real roundsTick: above 80 for 20 s+ while wave 2's gate is shut, no hold (nothing due; the
  review's case); the gate opens, wave 2 held 15-20 s from then, the gate shut while it's on (logged once), never made
  longer, wave 2 after it (no second for it: per_wave 1, logged), wave 3 due within gap_s comes at once (logged), the
  spawn gap 3 s longer while hot (logged), the round's line (held 1, and the level eased); gap_s 0: per_wave alone keeps
  wave 2's second away; the rest of wave 2 held at its next flight (none before one's due; its spawns wait, then come),
  wave 1 never held; spawn_gap_add_s 0: spawn_gap_s only; the top cover's own hold (held past its max_s inside it, let go
  at its end; the round's last flight up inside it kept to its end, logged; a hold that never ends: let go 30 s after
  it was the last), a wave due during it held on its own, the top cover not held again within gap_s (DIR.holdOn
  false), a wave due just after it held all the same; nothing to hold, an Anomaly round, the lever off (no spawn gap
  either), [intensity] off: none;
- hold.tactics: the squad director's cover refused at intensity 84 (logged), given with tactics off or calm;
- a push: nothing before 20 s, the six tell and RE_SV_AceTurn_05 a lead later, STATS' push line and tag, its next move
  31 s on, the cooldown (logged), a second after it, no third (per_round 2), a held top cover's dive instead
  (RE_SV_DirFree_07, counted as top_cover), a flight instead while its hold is on, none in round 2, none with [director]
  off (logged), nothing in range (logged once, tried again 5 s on and sent once in range), the lever off, a Ladon round;
- the level: round 15 at 2 (a Veteran's provoke 60-160 m, PilotRank 5), 1 after 30 s above 80 (logged; the enemies up
  written again: surround 80-220 m, PilotRank 4, a Rookie near the jammer 4 + its boost), a new Veteran's PilotRank 4, a
  round's aircraft_add on the level, no lower with max_drop 1 past gap_s, 0 with max_drop 2, back up after 60 s below
  50, nothing to ease in round 5, the lever off (the spikes' level, its ease dropped, logged), [intensity] off; round 10
  eased to 0: a Rookie's provoke back to the game's own values (90 deg / 3 s / 100-300 m, logged 1 of 1); the throttle:
  round 28 eased C to B (RE_SV_PressureB, logged), back to C; round 15 B stays (none fired); DIR.pressure's letters
  (pressure_min B, a, x; ease 2; pressure false); none fired in an Anomaly fight (logged);
- co-op joiner: "in" once a second (`in|3.0|25.0|80.0|0.0`), the host's "rnd" level taken (a live copy written again,
  logged), levels 7, 1.5, nan, -1 and x and an older host's "rnd" not taken, no event of its own;
- co-op host: "in" kept, a second within 0.25 s dropped, values clamped, NaN / 1e999 / a word / its own slot / slot 30 /
  no numbers dropped, stale after 3 s, a host sends none; player 2 above 80 for 3 s holds the room's next wave (named,
  the room listed); its "rnd" carries its level; player 2 comfortable 20 s: the six tell by "tl" to them only, then
  RE_SV_Hunt_05 with the flight's TargetActor on their stand-in; you and player 2 calm (60 each), nothing in range of
  you: player 2's push the same second; player 2 more comfortable but its 2 used: yours instead;
- the hooks by their place in the source (the wave gate and the spawning branch, startRound and the spike callout on
  levelFor, sv_ai's two, sv_rows', sv_spawn's two, sv_coop's "in" / "rnd" / D.intLevel, DIR.tick's order, heldTick and
  blockedBy, nothing of SV_Event / hudCallout kept at load, levelFor and roundBudget's level in sv_config).
A mutation check (each on a scratch copy of the mod: the wave gate's hold, the gap, the "in" slot guard, the top cover's
wait, the level's ease, the hot refusal, the joiner's D.intLevel; after the review: the wave hold never started at its
gate, the push loop stopping at the first calm player, the provoke not put back, DIR.pressure off, the spawn gap's add
off, one gap for both holds, DIR.holdOn on the wave's hold) fails 1-11 of its checks each. The other units' tests
pass unchanged but one source check in late_rounds_test.lua (startRound's `TIER.roundBudget(D.round, levelFor(D.round))`).

### Untested / known limits
- Everything in game [V at most]. In particular:
- HIT.msl's TargetToHome read [V static: sv_tactical's ECM and the stats use it, both untested in game]: if it can't be
  read, only missiles within 1 km count as "on you".
- Damage is HealthInternal's drops only: the player's native armour pool (+0x1400, KILLS_HEALTH_DEATH.md) drains first,
  so some hits may not show (runtime-ai's measurement gap) [I].
- The weights and marks are a first guess (80 = two missiles, four close, 30-40 % health gone in 30 s); the round lines
  are there to tune them.
- The push's turn is the squad director's cover lever (LastTGT by flight on a duelist: confirmed only on the Reaper's,
  hard rule 37); a joiner's is a hunt with its TargetActor on the stand-in (untested, unit 6).
- The level: fire-control rows are set at spawn, so a change reaches only flights that come after it (and the next
  round's aircraft_add); the enemies up get provoke (its effect untested, unit 2) and PilotRank (live writes confirmed,
  test 16) written again; post-stall stays as each plane spawned (set once by enemyManeuvers): spike levels 1-3 all have
  post_stall_all, so only an ease from 1 to 0 changes it, and then only for planes that come after (those up keep it).
  The director only eases under the spikes and back; it never goes above them. The ease carries over the run's rounds
  (no reset at a round's start).
- The throttle's ease (level.pressure) is unmeasured, like U3's presets themselves: whether a gentler preset lets a
  pressed player breathe is for the round lines and the deaths' damage to say. With pressure_min B it acts only from
  round 26 (the C / D bands); pressure_min A lets it ease B to A too.
- The spawn gap's add (3 s) only spreads a wave that's spawning: the hold keeps the rest of a later wave back first; it
  matters for a round's first wave and for a wave whose hold is used up.
- Co-op: the host's level reaches a joiner with its next "rnd" (1 s, unreliable); copies already up then are written
  again, their tier still re-rolled locally (as before). The hold is the room's (the waves are); a joiner's "in" older
  than 3 s leaves them out of the room's decisions.
- The hold also keeps the top cover past its max_s (at most the hold's length, 30 s). It never keeps back a round's
  first wave, a special's entry or a raid that's already up.
- No COOP_TAG / VERSION bump yet (the contract's single bump at the end): "in" and the "rnd" level field are new.
- Not built: runtime-ai step 8(c)'s separate director rank add (one applyRank): the level's rank_min is that lever,
  between the tier's rank (the floor) and the spike's rank_min (the ceiling), and reapply writes it live with the
  jammer's boost kept on top (JAM.tick goes back to the p.rankSet reapply sets), so the two never overwrite each other;
  a rank add under the tier's would break "tiers stay the floor". Step 9's "replace the break callout with the
  director's own escalation tells": the stock spike callout stays, said only when the (eased) level rises; no tell names
  a held wave (tells-radio marks those lines optional, and a callout to the pressed player would only add to the
  pressure).

### Review fixes (after unit 7's review; not yet run in game)
- **The wave hold held nothing (blocking).** It started the first time a player had been above 80 for 3 s, usually
  right after a wave arrived with many enemies up, and counted against per_wave; thinning the wave to next_at took
  longer than its 15-20 s, so it had run out when the gate opened, and the next was refused for gap_s or per_wave. Now
  the wave hold starts only when a wave is due: roundsTick asks DIR.holdWave only once the gate is open (or at a later
  wave's next flight), and DIR.holdWave starts it there when a player has been above 80 for after_s and gap_s /
  per_wave allow. The top cover's hold is its own (D.int.cover, started once a second while a top cover is held), and
  neither counts for the other's gap or per_wave, so a hold that kept no wave back costs the wave nothing. The spawning
  branch now asks after the airfield check (a hold doesn't run down while spawns wait for you on the ground).
- **A push for the next calm player (minor).** pushTick went only to the single most comfortable calm player; now it
  goes through the calm players most comfortable first and pushes the first one whose budget, cooldown and DIR.push
  allow.
- **The 1-to-0 ease (minor).** At spike level 0 provokeWant has nothing for a tier without its own provoke, so the
  planes up kept spike 1's. enemyProvoke now keeps each field's value before its first write (p.provokeStock) and
  reapply writes those back (provokeStockWant) when a level has nothing to write. The comment and this note no longer
  say post-stall is every spike level's (level 0 has no post_stall_all; planes up keep theirs).
- **Scope: the pressure presets (runtime-ai 8d).** The level's ease now also steps U3's attack throttle preset a letter
  gentler (DIR.pressure in roundPressure; pressureNow when the ease changes; never under pressure_min B; none inside an
  Anomaly / VALKA fight, whose boss-down refire picks up the eased one).
- **Scope: the spawn gap (runtime-ai 8a).** `D.at = now + CFG.spawn_gap_s + DIR.gap(now)`: spawn_gap_add_s 3 s more
  between a wave's flights while a player has been above 80 for after_s.
- Step 8(c) and step 9's tells: see "Not built" above.

## Unit 8: the learning layer (P6)

The thesis' P6: "The kill log already records aspect, altitude and weapons used for every kill. Build a per-run profile
and counter it with live levers [...] Across runs, save the profile to config and pick the next run's role mix from it
at level load." Built in Scripts/sv_stats.lua as PROF (its own `do ... end` block at the end of the part; the part is
at 64 of 200 locals), from the measurements' own hooks (unit 1), with the levers in sv_rounds, sv_ai, sv_spawn, sv_rows
and sv_main (the metrics brief's steps 11-13, coop-perf step 8, the critic's flare row and squad-director hook). Lua,
survival.default.ini, stats_report.py and the packaging rm lists only: no build change, no new event, row or behaviour
script, no co-op message (the profile is each game's own; contract: never synced). No COOP_TAG / VERSION bump (the
contract's single bump comes last). Every habit has its own switch; nothing here has run in game.

| habit | measured (your kills of fighters: KILL.by "you" only, a pool flight's plane, not a bomber's, a Ladon's or a special's; your flying: every 2 s of a fight in the air) | countered by (its strength s, 0-1) | where it acts |
|---|---|---|---|
| missile-heavy | kills with a missile or a special spent in the 6 s before and the gun not (KILL.geom's `used`), of your kills with a weapon seen | the jammer more often: its chance x (1 + jammer_x 1.0 x s), at most jammer_max 0.9; PilotRank +rank_add 1 from tier rank_from Veteran (more flare and strong-evasion picks in Survival's sets); the AI's flares refilled (the critic's lever: a copy of NPC_FCS_PlaneFlr000 holding 20 and reloading in 8 s on every fighter's flare slot; chosen at the main menu from the saved profile, so from the next game session) | startRound's jammer pick; enemyTier; searchSetup's slot loop (PROF.menu decides) |
| gun / close fights | the bigger of: kills with the gun spent, of your kills with a weapon seen; kills within CFG.stats close_km 1.2, of your kills with an aspect | post-stall (cobra, kulbit) on every airframe from tier post_stall_from Regular (as a spike's post_stall_all does); Duelists x (1 + 1.0 s) and Wolf pairs x (1 + 0.5 s) in the round's role mix | enemyManeuvers; ROLE.pickRound |
| tail-chaser | 0.6 x kills from behind (CFG.stats tail_km 3 / tail_deg 70: the kill-time line's test) + 0.4 x time on an enemy's tail (an enemy within tail_km with you within tail_deg of its six, from where you were at its sample, p.youAt), full at tail.time_full 0.3 of your time | the squad director's cover-the-tailed and trap: budgets x (1 + budget_x 1.0 x s), their cooldowns as much shorter (the critic's hook: D.counter.tail in DIR.roundStart); Wolf pairs x (1 + 1.0 s) | DIR.roundStart; ROLE.pickRound |
| stays high | time high.over_m 1000 above the mean height of the enemy fighters within high.near_km 15 (none near: above high.alone_m 5000) | Lancers x (1 + 1.5 s) in the mix, and they come in above_m 1000 over your usual height (the median of your heights; within their band, at most 8.5 km; only when that's above their own 4-6.5 km), so the top cover (P2 holds Lancers) sits above you; the squad director's top cover: its budget x (1 + top_cover_x 1.0 x s), its cooldown as much shorter (with roles off too, where it holds any flight) | ROLE.pickRound; spawnFlight; DIR.roundStart |
| hugs the airfield / AA | time within airfield.km 8 of the runway, of the time the airfield didn't need you there (SaN: no bomber or Ladon up, skip_raids; not in the after_takeoff_s 45 after you were on the ground; a landing takes back the before_landing_s 45 of airfield samples before it, the approach) | the airfield's strike package more often: its chance x (1 + strike_x 1.0 x s), at most strike_max 0.9; Skirmishers x (1 + 1.5 s) (they stand off) | startRound's strike pick; ROLE.pickRound |

The maths (CFG.profile; every share 0-1):

    the run's shares   missile = Km / Kw, gun = max(Kg / Kw, Kc / Kgeo), behind = Kb / Kgeo,
                       tail_time = min(1, (St / S) / tail.time_full), high = Sh / S, airfield = Sa / SaN
                       (Kf your kills of fighters, Kw of them with a weapon seen, Kgeo with an aspect; S samples of
                       2 s, SaN of them the airfield's: no raid up, not just after a takeoff, not a landing's approach)
    tail               0.6 x behind + 0.4 x tail_time
    in force           this run's share once its own count has live_kills 5 kills (missile Kw, behind Kgeo, gun its
                       half's: a half on fewer is left out of its max) or live_samples 30 samples for the time shares,
                       weighed against the saved profile's as if that were prior_kills 20 kills (prior_samples 150
                       samples): (prior x p + n x r) / (prior + n), n that count; before that the profile's alone;
                       neither: none (code review of 2026-10-29: every kill share used to rest on Kf, so one missile
                       kill seen among 5 kills of fighters stood as a missile share of 1.0)
    strength           0 at or under the habit's threshold (missile 0.8, gun 0.35, tail 0.7, high 0.5, airfield 0.4),
                       (share - threshold) / (1 - threshold) over it: 1 at a share of 1.0
    a run learnt from  each saved share = (1 - a) x saved + a x the run's, a = n / (n + fold_kills 30) for the kill
                       shares (n = the share's own count, as in force: Kw, Kgeo, the gun's half's; a tie between the
                       gun's halves goes to the one on more kills), n / (n + fold_samples 300) for the time shares and
                       your height (n = S; SaN for the airfield's), at most run_weight_max 0.5; a share the profile has
                       none of yet (the first run learnt from: all of them): the run's own. Only a run with min_kills 8
                       of your kills of fighters that started at round 1 (START AT ROUND > 1, a head start, is counted,
                       not learnt from; a co-op joiner's run starts at the first host round it sees start, PROF.roundStart:
                       one that links at round 20 is a head start, though its own D.startRound is 1); its time shares
                       and height only with min_samples 60 samples (2 minutes)
    role weights       each role's share of the round's mix x (1 + the sum of its habits' gain x strength); a role the
                       band has no share for stays out (rounds 1-3 have no Skirmishers); never an ace round's ace_mix

The missile threshold is 0.8, not the metrics brief's 0.7: Ace Combat is a missile game, and 0.7 would flag nearly every
player. The thresholds and gains are a first guess; the round lines log the raw shares to tune them.

### What was built
| piece | where | what it does |
|---|---|---|
| your kills | `PROF.kill(p, g, by)` from STATS.down (the sweep's death branch, every game; before the measurements' own switch, so [stats] off still learns) | yours only (by "you": a co-op partner's are "wingmate", an ally's "allies", a Ladon's nil), K all of them; the shares from your kills of fighters only (Kf: p.unit a pool flight's, not a bomber's; a Ladon or a special has no pool flight); the weapon from g.used (the gun's shots in the 6 s before, else a missile's or a special's; nothing seen: no weapon), close and behind from its aspect (p.youAt's, unit 1; kept by the sweep with [stats] off too since the code review of 2026-10-29) |
| your flying | `PROF.sample(now, you)` from STATS.sample (every 2 s, the sweep's summaries) | a fight's sample (D.state spawning / wave / fighting, not on the ground: playerOnAirfield): your height into a 250 m histogram, high, near the airfield, on a tail; a landing (in the air, then on the ground) counted. The airfield's own count (SaN) leaves out the time while a bomber or a Ladon is up, the after_takeoff_s after you were on the ground, and a landing's before_landing_s approach (taken back). Not twice within 1.5 s of the round clock (a pause). Cached fields only (p.at, p.fwd, p.dist, p.youAt); where you are from the sweep, else STATS.sample reads it (one read every 2 s: the sweep's slot 0 visits only the 8th, 16th ... plane) |
| the counters | `PROF.weights(round)` from startRound (the host or solo), before its strike, jammer and fighter picks; `D.counter` | each habit's share in force, its strength, and what that turns on (`jammerX`, `rank` / `rankFrom`, `postStallFrom`, `tail`, `lancerAlt`, `strikeX`, `roleW`); one "learning: round N" line a round with every share next to every decision |
| the levers | `PROF.chance` (sv_rounds.lua startRound: the strike's and the jammer's `math.random() <` chance), `PROF.rankAdd` (sv_ai.lua enemyTier, before p.rankBase: P4's live rewrite and the jammer's boost keep it), `PROF.postStall` (enemyManeuvers' `all`), `PROF.roleW` (sv_spawn.lua ROLE.pickRound: the mix's weights; its "roles:" line says "weighed by your habits"), `PROF.lancerAlt` (spawnFlight's Lancer height), D.counter.tail (sv_director.lua DIR.roundStart, unit 6's hook: "cover and trap xN (your tail chasing)"), D.counter.top (DIR.roundStart: the top cover's budget and cooldown, "top cover xN (you stay high)") | each a pcall'd read of D.counter; on a co-op joiner each gives the base / 0 / false / nil (its enemies are the host's copies) |
| the AI's flares | `PROF.menu()` from sv_main.lua's main-menu block, once a session, before setsSetup / searchSetup; sv_rows.lua searchSetup's slot loop (`aiFlares`) | the profile read; with the saved missile habit (strength > 0) or `[flares] always`: PROF.flareWant = { magazine, reload_s }, and every fighter row's NPC_FCS_PlaneFlr* slot (aces' too; not MINDRIPPER's, AB.L..IN's or VALKA's) onto `<row>_SV_FLR` (one row for every spike level). Rows are made once a session (cloneRow keeps a row), so a new habit shows from the next game start |
| the file | `PROF.load` (the main menu; `PROF.levelLoad` at each level load: sv_main.lua after RUN's reset), `PROF.roundStart` (STATS.roundStart: the round the run began in), `PROF.checkpoint` (STATS.roundEnd: the clear on the host, a joiner's round change), `PROF.fold(how)` (STATS.runEnd from LB.finish: died, restart, left), `PROF.newRun` (STATS.hostReset: a co-op host's new run while this game's level goes on) | config/survival_profile.ini, written at a run's end and, with `checkpoint`, at each round's end with the run so far in [run]; a [run] found at the next start (the game closed mid-run) is learnt from first, once a session (its id). Read with io, never run as code: known keys only, every value a number clamped to its range. A write that didn't land (the folder can't be written) leaves this session's profile in force: PROF.load keeps it until a write lands. Never lost (code review of 2026-10-29; the old write ignored write / close failures, removed the file before the rename and never read its `.tmp`, and a read that failed was followed by a neutral profile written over the file at round 1's clear): written whole to `.tmp` (its last line `; end of the profile`; write and close checked, a failure removes the .tmp and leaves the file as it was), the old file moved aside to `.bak` (Windows' rename never replaces a file), the `.tmp` moved in (the .bak put back if that fails), then the .bak removed (one it can't remove, another program holding it: logged, left, removed by the next write). No file: a whole `.tmp` (it has its end line), else the `.bak` a write the game didn't finish left is read and moved back in, only with a `.tmp` beside it (F3 round 2: a write stopped between the move aside and the move in leaves both; a `.bak` alone is a finished write's it couldn't remove, older than the file a player deleted to start over, and is passed over). A file that's there but can't be opened now (another program holds it; errno other than 2): no profile this session (PROF.saved nil: each run on its own), nothing written until a load reads it. A file that isn't a profile of this version (broken, another format): neutral, and the first write moves it aside as `.old` (kept; one) and says so. PROF.saved is set only once a load has gone through, and checkpoint / fold never write without one, so a level load error (sv_main.lua leaves PROF.saved nil) never has a neutral profile written over the file. Each failure logged once a load |
| packaging | tools/package_release.sh, tools/package_test.sh, .gitignore | a dev's survival_profile.ini never ships or goes into git |
| report | tools/checks/stats_report.py `learning_lines` | a row per round (each habit's share, * where countered, the counters), each run's end and the profile lines |

The file (made by the game; a player may delete it to start over):

    ; AC8 Survival Mode: how you fly, learnt from your runs (the learning layer: [profile] in survival.ini).
    ; Written by the game at each run's end; delete this file (and any .tmp / .bak beside it) to start over.
    ; Yours only: never sent, never shared in co-op.
    [profile]
    version = 1
    runs = 2            (runs counted: something flown)
    learnt = 2          (runs learnt from)
    kills = 50          (your kills, every run)
    missile = 0.7250    (the six shares; tail is worked out from behind and tail_time)
    gun = 0.5500
    behind = 0.9500
    tail_time = 1.0000
    high = 0.4000
    airfield = 0.3500
    alt_m = 4625        (your usual height)
    ; habits: missile 0.72, gun 0.55, tail 0.97, high 0.40, airfield 0.35
    [run]               (only while a run is on: its counts at its last round's end)
    id = ...
    round = 3 ... alt_m = 2625
    ; end of the profile  (the last line: a .tmp with it was written whole)

### CFG keys (CFG.profile, CFG.flares; `[profile]`, `[profile.<habit>]`, `[flares]` in survival.ini; PERSONAL in co-op)
- `profile`: `enabled` true, `save` true, `checkpoint` true, `min_kills` 8 (of fighters), `min_samples` 60, `live_kills` 5, `live_samples` 30,
  `prior_kills` 20, `prior_samples` 150, `fold_kills` 30, `fold_samples` 300, `run_weight_max` 0.5.
- `profile.missile`: `enabled`, `threshold` 0.8, `jammer_x` 1.0, `jammer_max` 0.9, `rank_add` 1, `rank_from` Veteran
  (a CFG.tiers.list name, any case).
- `profile.gun`: `enabled`, `threshold` 0.35, `post_stall_from` Regular, `duelist` 1.0, `wolf` 0.5.
- `profile.tail`: `enabled`, `threshold` 0.7, `time_full` 0.3, `budget_x` 1.0, `wolf` 1.0.
- `profile.high`: `enabled`, `threshold` 0.5, `over_m` 1000, `alone_m` 5000, `near_km` 15.0, `lancer` 1.5, `above_m` 1000,
  `top_cover_x` 1.0.
- `profile.airfield`: `enabled`, `threshold` 0.4, `km` 8.0, `skip_raids` true, `after_takeoff_s` 45, `before_landing_s` 45,
  `strike_x` 1.0, `strike_max` 0.9, `skirm` 1.5.
- `flares`: `enabled` true, `always` false (every session: a test), `magazine` 20 (stock 10), `reload_s` 8.0 (stock 25).
- Both sections are PERSONAL (sv_coop.lua): a host's settings never change a joiner's learning or its flare row, and
  the file is not CFG at all (M.sendSettings never sees it). Only the host's counters reach the room (its startRound
  picks, its spawns, its planes' ranks); a joiner learns from its own kills into its own file for its own runs.

### Log lines to look for in a test
- Each round's start (the host or solo): `learning: round 12: habits missile 0.95 (over 0.80, strength 0.75), gun 0.60
  (over 0.35, strength 0.38), tail 0.94 (...), high 0.80 (...), airfield 0.70 (...) (this run 20 of your kills, 20 of
  fighters, 200 s flown; the profile 1 runs, 1 learnt from) -> the jammer's chance 0.50 -> 0.87, PilotRank +1 from
  Veteran, the AI's flares refilled (this session's), post-stall on every airframe from Regular, cover and trap x1.80,
  Lancers from 7.1 km up (your usual 6.1 km), top cover x1.60, the strike's chance 0.35 -> 0.52, role mix duelist
  x1.38, lancer x1.90, wolf x1.99, skirm x1.75` (`-` for a share not known yet; `-> nothing to counter`; `(roles off:
  no effect)` with roles off).
- What it turns on: `roles: round 12 (the mix from round 10, weighed by your habits: duelist 0.42, lancer 0.48, ...)`,
  `director: round 12's budgets (...); cover and trap x1.80 (your tail chasing); top cover x1.60 (you stay high)`,
  `round 12: the jammer flies with ...`, `round 12: a strike package (...) goes for the airfield`, `tiers: round 12
  Veteran (...): PilotRank 2 -> 5`, `maneuvers: f16c (...) post-stall allowed: ...`, the Lancers' spawn lines `..., 7.1
  km up`.
- The main menu: `learning: profile at the main menu from config\survival_profile.ini: 2 runs (2 learnt from), 50 of
  your kills; missile 0.72, gun 0.55, tail 0.97, high 0.40, airfield 0.35, your usual height 4.6 km`, then `learning:
  the AI's flares refilled this session (your saved missile share 0.85, over 0.80): 20 in the magazine, 8.0 s to reload`
  and `weapons: NPC_FCS_PlaneFlr000 -> NPC_FCS_PlaneFlr000_SV_FLR (the AI's flares, against your missiles: ...)`, or
  `learning: the AI's flares stay stock this session (your saved missile share 0.72; its threshold 0.80)`.
- Each level load: `learning: profile at level load ...` (`none yet (...made at your first run's end)`, with `;
  survival_profile.ini.bak passed over: an older one a write that went in left, removed at the next write` for a .bak
  alone; `... is format 2, not 1: starting from a neutral profile`; `; N lines skipped`; `; the run the game closed in
  (round 3, 9 of your kills) learnt from[, not its tail_time, high, airfield, height (40 samples, ...; min_samples 60)]
  first`; after a failed write: `learning: profile at level load: this session's kept (config\survival_profile.ini
  couldn't be written: the file's older): ...`). Since the code review of 2026-10-29: `... is format 2, not 1: starting
  from a neutral profile (the file's kept as survival_profile.ini.old once a new one is written)` (`has no version
  line`, `not readable`), then at the first write `learning: config\survival_profile.ini (has no version line at its
  load) kept as survival_profile.ini.old; a new profile written`; `learning: profile at level load from
  config\survival_profile.ini.bak (a write the game didn't finish left it; moved back in): ...` (`.tmp`; `...; <file>
  couldn't be moved back in (...): the file not written this session`); `learning: profile at level load:
  config\survival_profile.ini couldn't be read (<error>): no profile this session (each run learns on its own), the file
  not written until a load reads it`.
- A write that fails (each once a load; the file as it was): `learning: can't write config\survival_profile.ini
  (<error>); the profile stays this session's`, `learning: config\survival_profile.ini not written (No space left on
  device): the old one kept; ...`, `... not replaced: it couldn't be moved aside (...), it's kept; ...`, `... not moved
  in (...): the old one put back; ...` (or `the new one left as survival_profile.ini.tmp, read at the next start`); a
  write that went in but couldn't remove the old one: `learning: config\survival_profile.ini.bak (the profile before
  this one) couldn't be removed (Permission denied): left beside the new one, never read back without a .tmp; the next
  write removes it`; nothing written: `learning: config\survival_profile.ini not written: no profile was loaded (left as
  it is)` (a level load error or an unreadable file), `... not written: survival_profile.ini.bak couldn't be moved back
  in (...) (left as it is)`.
- A run's end: `learning: run over (died): 23 of your kills (21 of fighters: missiles 15, gun 5, of 20 with a weapon
  seen; close 3, from behind 12, of 21 with an aspect), 812 s flown (high 30%, near the airfield 5% of 640 s it didn't
  need you, on a tail 20%, usually 3.9 km up), 2 landings: missile 0.75, gun 0.25, tail 0.43, high 0.30, airfield
  0.05; learnt from; the profile now 8 runs (6 learnt from), ...; saved to config\survival_profile.ini` (`learnt from;
  not its tail_time, high, airfield, height (24 samples, 20 of them for the airfield; min_samples 60)`; `counted, not
  learnt from (only 5 of your kills of fighters, min_kills 8)` / `(a head start at round 16)` (a co-op joiner linked at
  the host's round 20: `(a head start at round 20)`); `, NOT saved (<why>)` with a failed write's line; `; not saved
  ([profile] save off)`; `; not learnt from or saved (no profile was loaded: config\survival_profile.ini left as it
  is)`).
- Errors: `learning: error ...` (startRound), `learning: profile error ...` (the main menu), `learning: level load error
  ...`, `learning: PROF.<hook> error ... (its first: not logged again)` (STATS' calls, hookErr).
- `python tools/checks/stats_report.py AC8SurvivalMode_lua.log`: `learning lines: N: rounds countered C of R, runs over
  n (learnt from l)` and a row per round.

### Test checklist (in game)
1. First start: `learning: profile at the main menu: none yet`, `the AI's flares stay stock`; play a run past 8 kills
   and die: the run-over line with plausible counts (missiles vs gun against what you did), config\survival_profile.ini
   made; restart: `profile at level load from ...` with the same shares, and round 1's line already countered from it.
2. Missile habit (kill only with missiles, 10+ kills): the round lines' missile share over 0.80, the jammer more often
   from round 8, `tiers:` Veteran PilotRank 5; restart the game: `the AI's flares refilled this session` and the
   `_SV_FLR` weapons line; do the enemies drop flares more often against your missiles? (whether the copy applies is
   untested).
3. Gun habit (gun kills, close): post-stall on Regulars (`maneuvers: ... post-stall allowed` on models not in
   CFG.maneuvers), more duelists and Wolf pairs in the `roles:` lines.
4. Tail habit (sit on tails): `cover and trap x1.xx (your tail chasing)` in the director's budget line, more `cover` /
   `trap` director lines a round than without.
5. High habit (fly 2 km over the fight): more Lancers, and their spawn lines' height about 1 km over yours; `top cover
   xN (you stay high)` in the director's budget line, more `top_cover` director lines a round (with roles off too).
6. Airfield habit (stay over the runway with its AA): the strike package more often (rounds 6+), more Skirmishers. Then
   defend the airfield against a raid and land to rearm: the run-over line's "near the airfield N% of M s it didn't
   need you" should not grow from that (M less than the time flown).
6a. Rounds 1-2 (4 and 6 enemies): the round lines' "N s flown" grows every round (the samples no longer need an 8th
   plane up).
7. A crash mid-run (close the game after a round's clear): the next start's `the run the game closed in ... learnt from
   first`, once.
8. Co-op: each game's own file from its own kills (a joiner's run-over line has only its kills); only the host logs
   `learning: round` lines (a joiner has none); a joiner's own flare row from its own file.
9. Off: [profile] enabled = false: no `learning:` lines but the main menu's flare line; save = false: no file.
10. Tuning: from friends' logs, stats_report's per-round shares say where the thresholds sit; move them in survival.ini.
11. The file (code review of 2026-10-29): after a few runs config holds survival_profile.ini only (no .tmp or .bak
    left), its last line `; end of the profile`. Write some junk into it, start a run: `... has no version line: starting
    from a neutral profile (the file's kept as survival_profile.ini.old ...)`; at round 1's clear `... kept as
    survival_profile.ini.old; a new profile written`, and the .old holds the junk. Co-op: join a room past round 1 and
    die: the joiner's run-over line says `(a head start at round N)`.

### Offline test
`sh tools/checks/profile_test.sh` (tools/checks/profile_test.lua on the real sv_core, sv_config, sv_rows, sv_ai, sv_hud,
sv_spawn, sv_rounds, sv_leaderboard, sv_tactical, sv_stats, sv_tells, sv_director and sv_coop, Lua 5.4.6; then
stats_report.py on its log), 119 checks:
- survival.ini's [profile] sections and [flares] read (an integer stays one, a tier name in any case); every switch on
  as shipped;
- the classification: 12 of your kills of fighters by weapon (missiles, a special, the gun, gun and a missile: the
  gun's, nothing seen) and aspect (behind, head on, close; none read), a partner's / an ally's / a Ladon's not counted;
  your kills of a raid's bomber, a Ladon, a special and a plane with no flight counted as kills, not in the shares;
  twelve samples (high over the enemies near, not high, high alone, not high alone, near the airfield, on a tail from
  p.youAt while you're 60 km off; over the airfield 14 s and 54 s after a takeoff, with a bomber up, with a Ladon up,
  skip_raids off, away from it), a pause, the ground (a landing, its approach taken back), between rounds; the shares,
  tail's 0.6 / 0.4, the strengths at, under and over their thresholds; this run's shares only from live_kills /
  live_samples, the saved profile alone until then, weighed as prior_kills / prior_samples after, a profile learnt from
  no run not weighed; the real sweep (sv_main.lua planeSweep's slot 0, then STATS.sample as probeTick calls it) with 4
  planes up: the sweep reads nothing, STATS.sample reads where you are, every sample counted;
- the counters: every habit at once (strengths 0.75 / 0.38 / 0.80 / 0.60 / 0.50): the jammer's and the strike's
  chances (capped, never lowered), PilotRank from Veteran, post-stall from Regular, cover and trap, the role weights, the
  Lancers' height, the top cover's factor, the round's line word for word; each habit's switch, [profile] off, no habits ("nothing to
  counter"), a co-op joiner (no counters; a counter left in D read as none; its own kills counted, a partner's not);
- the levers on the real code: enemyTier (a Veteran 4 + 1 = 5, rankBase too; a Regular 3) and enemyManeuvers (a
  Regular's F-16C cobra and kulbit) with and without a counter; spawnFlight's Lancer at your usual height + 1 km, capped
  at 8.5 km, a duelist's own; startRound at round 10 with math.random fixed at 0.5: no strike and no jammer without
  habits, both with them, the role mix weighed and the director's cover and trap x1.80 and top cover x1.60 (its budget
  that much higher; DIR.roundStart); searchSetup on
  fake tables: the flare row made and on every fighter row at every spike level (the stock one untouched) after
  PROF.menu read a missile-heavy file, stock under the threshold, [flares] always and off;
- the file: none (neutral, logged); a run's end written and read back the same (the round trip) and its line; a run
  learnt from once; the next run's first round countered from the file alone; a second run blended (0.725 / 0.400); 5
  kills of fighters (of 9) and a head start counted only; nothing flown not a run; a round's checkpoint ([run], Kf and
  SaN in it) learnt from at the next start (its 40 samples not: min_samples) and gone from the file, never twice in a
  session; another format, no version line, broken values (clamped, skipped, a bad [run] id never learnt from), a
  binary file: neutral, never an error; a folder that can't be written (logged once, the profile kept for the session,
  and kept at the next level load over the older file; read from the file again once a write lands); save off (no
  profile, no file); LB.finish -> STATS.runEnd -> PROF.fold with [stats] off; a co-op host's new run
  (STATS.hostReset: learnt from, the next one empty) and a resync (goes on); min_samples: a run of 10 samples learnt
  from for its kills only (its time shares and height left out, said in its line), the next run's 100 samples its own;
- the code review of 2026-10-29: each kill share on its own count (3 kills with a weapon seen and 2 with an aspect of
  20: none in force; the gun's weapon half in force while its thin range half is left out; folded at 3 / 33 for the
  missile share, not Kf's 20 / 50); a co-op joiner linked at the host's round 20 (its D.startRound 1): [run] from = 20,
  counted, not learnt from; one from round 1 learnt from; the file never lost: written whole (its end line, no .tmp or
  .bak left), a full disk at the .tmp's write and at its close and a refused move in leave the old file byte for byte
  (logged; the run-over line `NOT saved (<why>)`), no file but its .bak (a cut-off .tmp passed over) or a whole .tmp
  read and moved back in, the next write removing the .bak left over, a .bak a finished write couldn't remove (logged)
  passed over once the player deletes the file (a neutral profile, the next write removing it; F3 round 2: it used to
  come back as a write the game didn't finish), a junk file neutral and kept as .old by the first write (logged; a later
  write keeps the .old), a file that can't be opened now (errno 13) and a level load error never written over (the run's
  line says not learnt from or saved), read again once a load can. Each case fails on the code before the fix;
- the hooks by their place in the source, and no math.random draw in PROF (the rounds' odds and the other units'
  seeded tests untouched), no FindAllOf or nameOf.
The other units' tests pass unchanged (their startRound now also logs a `learning: round N ... nothing to counter` line).

### Untested / known limits
- Everything in game [V at most]. In particular:
- The AI flare row [V static, I in game]: the missile and gun FCS copies are confirmed, the flare one isn't; its
  TriggerCount 10 is kept (a release of 10), so a magazine of 20 is two releases instead of one, and 8 s instead of 25 s
  to the next. Whether Survival's ActivateFlares picks (PilotRank-weighted, LA_SV_ProvokeNear) or the game's own fire
  control use it is untested. It follows the profile saved at the game's start, not the run on now.
- PilotRank +1 only reaches Veterans (4 -> 5): Elite and up are 5 already (the game clamps 1-5); with the menu's ENEMY
  SKILL or the Ace preset Veterans are 5 already too, and the counter adds nothing.
- Post-stall from Regular: LA_SV_ProvokeNear's cobra / kulbit branches weigh AI level 3+ (stock 2 for Regulars and
  Veterans), so on a Regular it mostly opens the stock sets' own post-stall picks [I].
- "Weapons used" is your shots in the last 6 s at anything (unit 1's KILL.geom), not at that plane: a missile at one
  plane and a gun kill on another within 6 s count as a gun kill. In co-op a partner's kills are never yours.
- The aspect and the samples are up to 2 s old (the sweep); a kill read after its plane's last visit uses that visit.
- The high habit's height counter only moves Lancers: every other pool flight's world-data band tops out at 4-5 km (the
  critic), so spawning them higher would pull them back down (ReturnToUnit). With roles off there are no Lancers: the
  high habit then gives the squad director more top cover (its budget, any flight held) but can't put it above you.
- The tail habit doesn't give non-ace tiers the aces' reversals (the metrics brief's optional lever): the squad
  director's cover-the-tailed (unit 6) is that lever now, and it's what the counter scales.
- The role weights only move shares the round band has: Skirmishers start in round 4's band, so the airfield habit
  can't bring them earlier; an ace round's ace_mix is never weighed.
- Co-op: only the host's habits pick the room's counters (contract). A joiner's habits aren't sent (a "pf" summary is
  out of scope); its copies' PilotRank comes from its own re-rolled enemyTier, without the host's rank counter
  (coop-perf: "live rank and flare counters don't reach joiners' copies"); its flare row is its own profile's. That
  part is per player as it should be: a joiner's missiles are decoyed by its own game's copies, so a missile-heavy
  joiner meets refilled flares from its own file whatever the host's says.
- The airfield habit's exclusions are judged from the planes list (any bomber or Ladon not down, wherever it is) and
  your ground contacts; a raid's escorts alone (bombers down) count again. A landing takes back only the airfield
  samples of its last before_landing_s, not a longer loiter before it.
- A game that closes before a round's clear loses that round's counts (the checkpoint is at each clear). Runs with the
  test-only keys aren't flagged: a test run is learnt from like any other; delete the file after testing.
- The file's safety [V offline on Windows, I in game]: the failures were made by stubbing io.open / os.rename in Lua
  5.4.6 (clang, the Windows CRT); "no such file" is io.open's errno 2 (ENOENT), anything else (13, a file held open
  without sharing) counts as there. A file another program holds while the game reads it means no profile that
  session (its runs learn on their own and aren't saved). A crash between the move aside and the move in leaves only
  the .bak and the .tmp: the next start reads the .tmp if its end line is there, else the .bak; a .bak with no .tmp
  beside it is never read (a write that went in left it). Only one .old is kept.
- The thresholds and gains are guesses; the shares are logged every round to tune them.
- No COOP_TAG / VERSION bump yet (the contract's single bump at the end): nothing new crosses the link.

### Review fixes (after unit 8's review; not yet run in game)
- **The samples stopped with fewer than 8 planes up (blocking).** PROF.sample needs where you are, and the 2 s
  summaries passed only the sweep's read: the sweep reads you when it visits a plane, and the summaries run on its slot
  0 (planes 8, 16, ...). Rounds 1-2 (4 and 6 enemies) gave no samples at all, later rounds none once their 8th plane was
  down, so the time habits, your usual height and the landings came from a biased few. STATS.sample now reads you
  itself when the sweep didn't (`if not you then you = playerLocation() end`: one read every 2 s, shared with the
  airfield time it already read for). The offline test drives the real planeSweep with 4 planes up.
- **min_samples (minor).** foldInto took a first run's time shares and height outright however few samples it had,
  and current() then weighed them as prior_samples 150 for runs to come. Now a run's time shares and height go into
  the profile only with min_samples 60 samples (SaN for the airfield's), its line says which were left out ("learnt
  from; not its tail_time, high, airfield, height (10 samples, ...)"), and a share the profile has none of yet takes
  the next run's own. The first run learnt from clears any older shares first (a hand-edited file).
- **Fighters only in the kill shares (minor).** PROF.kill counted every kill of yours: a raid's or a strike package's
  bombers (straight and level, shot from behind with missiles), Ladons and specials made anyone missile-heavy and a
  tail chaser. The shares now come from your kills of fighters (Kf: p.unit a pool flight's, not a bomber's), as the
  high habit's enemies near already did; min_kills counts them and they're the kill shares' evidence (live_kills,
  fold_kills). K stays all your kills (the profile's total). Kf goes into [run].
- **The airfield habit's feedback loop (minor).** Time near the runway included defending it against the raids and
  strike packages its own counter sends, and every rearm's climb-out and approach. It's now the share of the time the
  airfield didn't need you (SaN): not while a bomber or a Ladon is up (skip_raids), not in after_takeoff_s 45 after you
  were on the ground, and a landing takes back the airfield samples of its before_landing_s 45 (the approach). SaN goes
  into [run].
- **A failed write lost the session's profile (minor).** PROF.load at the next level load replaced PROF.saved with the
  older file (or a neutral profile). A write that doesn't land now sets wrote.failed, and PROF.load keeps this
  session's profile ("profile at level load: this session's kept (... couldn't be written: the file's older)") until a
  write lands.
- **Scope: top cover above you with roles off too.** The high habit now also scales the squad director's top cover:
  D.counter.top = top_cover_x 1.0 x strength, DIR.roundStart's top_cover budget x (1 + top) and its cooldown divided by
  it ("; top cover x1.60 (you stay high)" in the budget line). With roles on the top cover is the Lancers, which come
  in above your usual height; with roles off it holds any flight (not above you, their bands top out at 4-5 km).
- Not changed: the tail habit's non-ace reversals (unit spec: the squad director's cover is the lever), sending
  joiners' habits to the host (contract: the host's profile picks the room's mix), weighing the profile by its own
  evidence in current() (prior_kills / prior_samples stay fixed weights; min_kills / min_samples are the guards).

## Unit 9: boss phases (P7)

The thesis' P7: "Give each boss two or three phases with a different counter each, and pair it with a role squad
instead of raw health: MINDRIPPER: PHANTASM guards fly as a Wolf pack that springs while your controls are scrambled.
AB.L..IN: after two frenzies it starts blinking behind you, not just around you; a third phase drops ECM and goes all-out
guns. Ladons: escorts fly top cover; after one Ladon dies the other changes route and volleys faster. ALICORN: surfaced
phase spawns Skirmishers from its deck; the railgun is telegraphed with a radio call." Built from the specials brief's
plans with the critic's corrections. **The Ladons stay alone** (user, 2026-10-25: "during a ladon round, only the
ladon's spawn, no other aircraft should"): no escorts, no top cover; only the rage. The ALICORN's railgun tell is unit
4's (the call and RAILGUN WARNING lead_s before the order, off alert_s after it, at a dive and the sink): this unit adds
only its deck. VALKA is parked and shipped off: untouched. Lua, survival.default.ini and the build (survival_events.py,
build_survival.py): new remote events, two flags, a path per Ladon and two radio lines, so the next friend build needs
the contract's single COOP_TAG bump (it comes last). Every piece has its own `enabled`; nothing here has run in game.

| boss | phase / squad | what happens | the counter | where |
|---|---|---|---|---|
| MINDRIPPER | its field (as before) | within field_km 3.2 your controls scramble | fight it from outside 3.2 km | sv_anomalies.lua ANOM.tick |
| | the PHANTASM pack (pack) | the guards fly the Wolf trap's close gunfighter (NLID_SV_WolfWing: a hard turn, then 200 m behind you with a leading gun; half its runs the "Super" pursuit at AI level 5). spring_delay_s 1.5 after the field scrambles you, its tell first ("pack": THE PACK SPRINGS / GET OUT OF THE FIELD, an ambush line), then RE_SV_AnomalyPackSpring: you only anywhere, their area over the whole zone, every guard LastTGT onto you. Once you've been out of the field hold_after_s 4, and at least min_s 12 after the spring, RE_SV_AnomalyPackHold (back round it: PlayerOnly, the 2 km following area); cooldown_s 20 before the next | get out of the field when the call comes; don't dogfight it inside 3.2 km | `ANOM.packTick`, `ANOM.packHeld`; sv_rows.lua searchSetup (the guard row's LuaSetId); sv_ai.lua ACE.hunt (hunt_only_sprung) |
| AB.L..IN | phase 1 (as before) | each hit outside a frenzy: 6 s of blinks round you, its gun firing | keep turning, hit it again after | `ANOM.glitchTick`, `glitchFrenzy` |
| | phase 2 (two frenzies over) | behind_share 0.5 of its blinks at the spot nearest your six (your heading from your velocity, SPC.V.heading; the nearest 30-degree spot, at most 15 deg off dead six, either ring; the last blink's bearing no bar; ground clearance as before); its tell "glitch_six" (IT'S ON YOUR SIX, a check-your-six line) | never fly straight through a frenzy | `blinkSpot`, `glitchPhase` |
| | phase 3 (at allout_hp 35 % of its health as it appeared) | no more frenzies or blinks; its ECM down (no RE_SV_GlitchEcm; its pods up switched off every ecm_check_s 2, ecm_pods_off, on a co-op joiner's copy too; optional, off by default: its own pod row refires at most once a minute, ecm_row); its gun at you whenever you're within allout_range_km 1.5 and allout_cone_deg 20 of its nose (RE_SV_GlitchGun every allout_gun_s 0.5 and the led shots each tick); LastTGT onto you (RE_SV_GlitchTurn) every allout_turn_s 10, and at once (allout_behind_s 3 apart) with you behind it within allout_behind_km 3; its tell "glitch_allout" to every player (ITS ECM IS DOWN / MISSILES WORK: STAY OFF ITS NOSE, "it's not jamming anymore") | missiles work now: stay off its nose and shoot from range | `glitchPhase`, `glitchPodsOff`; sv_rows.lua `glitchEcm`; sv_hud.lua's row (glitch_row_allout) |
| KOT / MISHKA | the rage (one shot down) | the other, still up: RE_SV_LadonRage<Key> (its flag), its callout (`<NAME> ENRAGED` / NEW HEADING, FASTER VOLLEYS) and tell ("ladon_rage": "the hostile's changed course"), volleys every rage.volley_every_s 25 (was 45; the next first_s 5 after the rage, once you're in range, the other's volley_gap_s no longer holding it; still one launcher a volley); from its next pass over the airfield it flies the rage circuit (LADON_RAGE: ~35 km, ~42 s a lap at 3000 km/h, so each pass still bombs under the 30 s debounce) | finish the second one fast, or keep it off the airfield | sv_ladon.lua `SPC.ladonRage`; survival_events.py LADON_RAGE, build_ladon; build_survival.py ladon_units |
| ALICORN | its deck (while surfaced) | a free pool flight of size 2 (a Skirmisher's own with the roles on; any role's when none is free; any with roles off) off its bow: ahead_m 800 along its heading (its core's forward; towards you when it can't be read), alt_m 1200 over the sea (never under 1100: the pool's 2-ship units fly 1000 m and up); never one of the round's own flights (D.taken), a spare it takes no spare any more; first_s 25 after it appears, every every_s 35, and after_surface_s 6 after each surfacing; warn_s 3 before each its callout (PLANES LAUNCHING / FIGHTERS OFF THE ALICORN'S DECK) and tell ("alcn_deck": "planes launching from the carrier"), only once nothing holds the launch (a held one is told again warn_s before it goes); at most max_up 2 of its flights up, never while you're down at the airfield (tried each second), none while dived. A round's launches (D.deckLeft): flights 2 + flights_per_round 0.15 x the round, at most max_flights 6; from specials.escort_from 12 its escorts come off the deck too (their aircraft in flights of 2; escorts true), none from a spawn point | kill the deck flights, or sink it before the next launch | sv_alicorn.lua `SPC.alicornDeck`, `deckFlight`, `partAt`; sv_spawn.lua spawnFlight's `pose`; sv_rounds.lua startRound (D.deckLeft) |

### What was built
| piece | where | what it does |
|---|---|---|
| the pack's events | survival_events.py build_anomaly | RE_SV_AnomalyPackSpring: t_engage {guards, PlayerOnlyNoLimit}, t_move {guards, AREA_RADIUS_M} (the down records' "loose"), Mission 6's LiveAIRequestUniqueAction {NoneSelect, guards, LastTGT, OneShot, Below_Return} (hard rule 37). RE_SV_AnomalyPackHold: t_engage {guards, PlayerOnly}, t_move {guards, on MINDRIPPER's object, 2000 m, follow} (the appearance's). No flags, conditions or delays (hard rule 26). The build checks that Lua fires both and keeps ^RE_SV_AnomalyPack |
| the pack's tick | sv_anomalies.lua `ANOM.packTick(now, s, c)`, called at the end of ANOM.tick (the host's; never ANOM.clientTick or setField, which joiners run) | s.pack nil (held) -> "armed" (the field on, its cooldown over: the tell, s.packAt) -> "sprung" (s.packSince; the field off before the spring: held again, nothing fired) -> nil (called back, s.packCool). s.fieldOffAt from ANOM.on. No guard alive: nothing. MINDRIPPER down: ANOM.tick returns before it (the down records loose the guards) |
| the guards' set | sv_rows.lua searchSetup (the slot loop's LuaSetId) | the Anomaly's wing row (ACE.row("anomaly", "f04e", "w"), every spike level: the world data names the level-0 one, hard rule 20) gets pack.guard_luaset (NLID_SV_WolfWing; only one of CFG.behaviour_sets that setsSetup made, never NLID_0400_CP: hard rule 22); "" or a set that isn't in: the fighters'. At the main menu: a game restart to change |
| hunt_only_sprung | `ANOM.packHeld(p)`; sv_ai.lua ACE.hunt (after no_provoke) | off by default (the brief's): on, a guard's TargetActor isn't forced onto you (the top tier's hunt) until the pack springs; false on a joiner (no D.special there) and outside MINDRIPPER's round |
| AB.L..IN's phase state | sv_anomalies.lua glitchTick (its arrival: s.phase 1, s.hp0 = its health after the round's scaling), `glitchPhase(c, s, n, now, why)` | 1 -> 2 in the frenzy-over branch once frenzies >= behind_after; -> 3 when its health <= hp0 x allout_hp (from 1 or 2; mid-blink it comes back first: frenzyUntil cut to now, the vanished branch brings it back, the next tick ends the frenzy). Each change logged and told |
| the frenzy | `glitchFrenzy(c, s, o, at, you, now)` (the old frenzy body, moved out so phase 3's guns run without a frenzy) | as before: the blink check a tick on, vanish / back at a blink spot / frenzy over |
| the behind blinks | `blinkSpot` | in phase 2, a draw under behind_share: the wanted bearing your heading + 180, the jitter and the last-blink penalty dropped for that pick; returns behind and the heading for the log (the first three, then every 10th) |
| phase 3's ECM | glitchTick (no RE_SV_GlitchEcm in phase 3); `glitchPodsOff` (FindAllOf("BP_wp_ecm_a0_C") every ecm_check_s, only pods whose owner or instigator is AB.L..IN: bJammingEnable / bSupportEnable false, the before / after logged once, and once when none of the pods up is its own (code review of 2026-10-29: a tester greps "ECM pods off"); never destroyed); a joiner's copy: `ANOM.clientGlitch` (below); sv_rows.lua `glitchEcm` (ecm_row, off by default: row NPC_FCS_ECM000_SVE, anomEcm's values with 60 s between shots and 60 s rest; MINDRIPPER keeps anomEcm's _SVX) | phases 1-2 keep the pod up by its event every ecm_every_s 14 and anomEcm's 14 s row, together (hard rule 40's confirmed "up all fight"); phase 3 drops it by the pods-off write alone: the row's next pod (every 14 s) jams until the next check, at most ecm_check_s 2. ecm_row true takes the row's refire away too (at most a pod a minute), at the risk of phases 1-2's continuity |
| phase 3's guns and turns | glitchTick: offNose (its forward against you, as VALKA's), `hot3`, `gunsHot`; RE_SV_GlitchTurn (survival_events.py GLITCH_POST_STALL gains ('Turn', 'LastTGT'); never one of the random post_stall_moves: the build checks) | gunsHot = in a frenzy and not gone, or phase 3 with you close in front of it; the event's cadence allout_gun_s outside a frenzy. A LastTGT pushes the post-stalls 3 s on (VALKA's pattern) |
| the rage | sv_ladon.lua `SPC.ladonRage(now, s, downKey)` (from the kill branch), the volley block (L.rage: rage.volley_every_s / volley_warn_s) | once a round, only when the other Ladon is still up (both down in one second: none); its pass lines say "(enraged N s ago)" |
| the rage circuit | survival_events.py LADON_RAGE (from LADON_LOOP[0], just past the airfield, to LADON_AIRFIELD: hard rule 2), LADON_RAGE_SPEED '3000.0', ladons()' rage / rage_lap / rage_flag / rage_ev, INT_FLAGS SV_LadonRage<Key>; build_ladon: the appearance clears the flag, RE_SV_LadonRage<Key> sets it, and each PathFinish (the route's, the circuit's and the rage circuit's own, SV_LadonRageLap<Key>) adds its bombing pass and starts the circuit when the flag is 0, the rage circuit when it's 1 (two flag-gated executions, no delay); build_survival.py ladon_units: the path (make_path smooth: ControlType 1, no tube data, hard rules 34 / 35), its points inside the area's 0.9 | the switch at its next pass over the airfield, never mid-path (whether a replaced path fires its old PathFinish is unknown) |
| the deck | sv_alicorn.lua `SPC.alicornDeck(now, s, c)` (alicornTick, each second while it sails), `deckFlight(dk)`, `partAt(o)`; the surfacing branch sets s.deckNext; sv_spawn.lua `spawnFlight(unit, maxLevel, pose)` (pose { x, y, z, yaw, why }: no spawn point, no pincer, no Lancer offset; logged "at the Alicorn's deck"); sv_rounds.lua startRound | the flight is an ordinary round flight: its tier, airframes (pickAircraft by its role), orders (ordersTick), D.up (the round waits for it after the sink), kill pay. Its call held a second by another tell's gap (kind "gap"), twice at most, then the launch goes with its callout alone: after a surfacing the railgun's warning now comes radio_gap_s after "submarine has surfaced", a second before the deck's after_surface_s call (code review of 2026-10-29); a co-op host with its own tells off is held by its joiners' gap the same way (TELL.say returns the send's refusal there; F4's review: the call to them was dropped) |
| the radio | survival_events.py TELL_LINES: SV_Radio_GlitchEcm (v0001_2693 "It's not jamming anymore!", ST_ms023 02_Jamming_Off), SV_Radio_LadonRage (v0001_3110 "The hostile's changed course.", ST_ms026 03_Nightmare_Assault), both LIVE_AWACS; the pack reuses Trap / EnTrap, phase 2 the Six lines, the deck AlcnDeck (unit 4's) | radio: 721 rows (61 tell lines); events: 771 triggers, 1540 execs (were 762 / 1518) |
| co-op | sv_coop.lua KEEP_EVENTS gains ^RE_SV_AnomalyPack; the host's "rnd" gains AB.L..IN's phase (its 9th field: 1-3, else empty; a joiner keeps it as D.glitchPhase); `ANOM.clientGlitch(now)` (clientRounds, after ANOM.clientTick) switches the joiner's copy's pods off every ecm_check_s while the host's is in phase 3 | tools/re/COOP.md's boss phases bullet |
| sure tells | sv_tells.lua TELL.play (`sureHud`), `send`; CFG.tells.list's `sure` on pack, glitch_six, glitch_allout | a sure tell not said (tells off, a gap, its cooldown, its lines) shows its callout anyway (raw, no radio; TELL.play's 4th value true), never between rounds, at the airfield or over the summary (with tells off too: play() returned "tells off" before it looked at the state, so TELL.play checks it again for a sure tell; code review of 2026-10-29); a host sends one to its joiners through its gaps, and each joiner's own TELL.play does the same |

### CFG keys (CFG.specials.<boss>; `[specials.<boss>.<part>]` in survival.ini; the host's for the room)
- `anomaly.pack` ([specials.anomaly.pack]): `enabled` true, `spring_delay_s` 1.5, `min_s` 12, `hold_after_s` 4,
  `cooldown_s` 20, `hunt_only_sprung` false, `guard_luaset` "NLID_SV_WolfWing" (main menu; "" the fighters').
- `glitch.phases` ([specials.glitch.phases]): `enabled` true, `behind_after` 2, `behind_share` 0.5, `allout_hp` 0.35,
  `allout_range_km` 1.5, `allout_cone_deg` 20, `allout_gun_s` 0.5, `allout_turn_s` 10, `allout_behind_s` 3,
  `allout_behind_km` 3, `ecm_row` false (main menu), `ecm_pods_off` true, `ecm_check_s` 2. (No key ends in gun_every_s:
  build_glitch's regex takes the first one.)
- `ladon.rage` ([specials.ladon.rage]): `enabled` true, `volley_every_s` 25, `volley_warn_s` 0, `first_s` 5.
- `alicorn.deck` ([specials.alicorn.deck]): `enabled` true, `first_s` 25, `every_s` 35, `after_surface_s` 6, `warn_s` 3,
  `size` 2, `max_up` 2, `flights` 2, `flights_per_round` 0.15, `max_flights` 6, `escorts` true, `alt_m` 1200 (1100 at
  least), `ahead_m` 800.
- CFG.tells: `pack`, `glitch_six`, `glitch_allout`, `ladon_rage` (cooldowns 20 / 0 / 0 / 0) and their texts, the first
  three `sure`; `alcn_deck` (unit 4's) now said. CFG.hud.text: `ladon_rage` / `_sub`, `alicorn_deck` / `_sub`, `glitch_row_allout`.

### Log lines to look for in a test
- `special: the Anomaly's guards (SV_Ace_anomaly_f04e_W_SV) fly NLID_SV_WolfWing (its pack)` (main menu), or `... keep
  NLID_SV_Fighter (their set NLID_SV_WolfWing isn't in)`
- `special: MINDRIPPER's pack: your controls scrambled 2.5 km from it; PHANTASM springs in 1.5 s (told)` and the tell's
  `tell: pack: RE_SV_RadioTrap (fired), tell callout 'THE PACK SPRINGS'`; or `(its callout only: <why>)` with
  `tell: pack not said (<why>): a sure tell, its callout 'THE PACK SPRINGS' shown anyway`
- `special: MINDRIPPER's pack not sprung (its event not fired); armed again in 20 s` (after `special:
  RE_SV_AnomalyPackSpring not fired: ...`)
- `special: MINDRIPPER's pack sprung (N): PHANTASM loose on you (LastTGT), 4 of 4 guards up, ...`; then the guards'
  `ai:` lines (CFG.ai_watch) should show them leave the 2 km area and go UniqueAction
- `special: MINDRIPPER's pack held: back round MINDRIPPER N s after it sprang (N s out of the field)`,
  `special: MINDRIPPER's pack: you left the field first; not sprung`, `... every guard down (N springs)`
- `special: round R, MINDRIPPER shot down N s after it appeared (its pack sprang N times)`
- `weapons: NPC_FCS_ECM000 -> NPC_FCS_ECM000_SVX (ECM pod (MINDRIPPER's, AB.L..IN's): always up ...)` (main menu; with
  ecm_row `NPC_FCS_ECM000_SVE (ECM pod (AB.L..IN's, its phases): ...)`)
- `special: AB.L..IN phase 2 (from 1): 2 frenzies over; 50 % of its blinks behind you`
- `special: AB.L..IN blink N behind you (M behind so far): your heading H -> spot D (RE_SV_GlitchBlink_XG, 500 m)`,
  then the usual `special: AB.L..IN blink N (...): a tick on it's ... m from you, ..., flight path X deg off you`
- `special: AB.L..IN phase 3 (from 2): at 34 % of its health (h of hp0); no more frenzies, its ECM down (its pods switched
  off every 2 s), its gun at you within 1.5 km and 20 deg of its nose every 0.5 s, LastTGT every 10 s`
- a co-op joiner: `coop: AB.L..IN in its phase 3 on the host: its copy's ECM pods switched off here every 2 s`, then its
  own `special: AB.L..IN's ECM pods off: 1 of 1 (...)`
- `special: AB.L..IN's ECM pods off: 1 of 1 (jamming/support true/true -> false/false)`; none its own (once, then the
  line above when one is): `special: AB.L..IN's ECM pods off: none of its own found (N BP_wp_ecm_a0 up, none its own by
  owner or instigator); looked for again every ecm_check_s`
- tells off, a sure tell at the airfield / between rounds / over the summary: `tell: glitch_allout not said (down at the
  airfield)` (no callout)
- `special: AB.L..IN's guns all out: you 1.0 km off its nose (6 deg)`, `special: AB.L..IN LastTGT N (1), you behind it, ...`
- `special: round R, AB.L..IN shot down ... (F frenzies, B blinks; phase 3, N blinks behind you, T LastTGT)`
- `special: Ladon MISHKA enraged (KOT down): volleys every 25 s, the rage circuit from its next pass (RE_SV_LadonRageMishka fired)`
- `special: Ladon MISHKA fires a launcher at you (...), enraged`, `special: Ladon MISHKA's pass over the airfield (N): -D (enraged S s ago)`
- `round R: the Alicorn's deck launches up to N flights of 2[ (E of them its escorts)]`
- `tell: alcn_deck: RE_SV_RadioAlcnDeck (fired)` (after a surfacing a second later than before, after `tell: alcn_deck
  not said (1.0 s after alcn_rail_first, its gap 2.0 s)` when the railgun was warned 2 s after it surfaced; a host with
  tells off: `tell: alcn_deck not said (every joiner: 1.0 s after alcn_rail_first, ...)`, then `tell: alcn_deck to every
  joiner ("tl")`);
  `round R: ERA_Unit_07_Dep_Air0 [skirm] as f02a_common (...), ..., at the Alicorn's deck, 1.2 km up: 2 aircraft up`; `special: the Alicorn's deck launch N: <unit> (skirm), 2 aircraft at 1200 m,
  L launches left this round` (`at 1100 m (alt_m under the pool's floor)` with a lower alt_m); `special: the Alicorn's
  deck waits: 2 of its flights up`; `special: the Alicorn's deck: <unit> didn't launch (...); again in 8 s, told first`
- `special: round R, the Alicorn sunk ... (core down, hull H; N deck launches)`
- Errors: `special: pack error ...`, `special: the Alicorn's deck: error ...`, `special: RE_SV_AnomalyPackSpring not fired: ...`

### Test checklist (in game)
1. MINDRIPPER (a test build's Anomaly key, or a run to an Anomaly round): fly into its field and stay: the ambush call
   and THE PACK SPRINGS, then 1.5 s later the guards break off it and come at you (ai: UniqueAction, then
   PursueTarget); leave the field for 4 s+ (12 s+ after the spring): they go back round it. Are the guards gunfighters
   near you on the Wolf trap's set (their guns lead 0.85 s)? Too much while scrambled: raise spring_delay_s, or lower
   hold_after_s.
2. AB.L..IN (a glitch round): hit it twice, let both frenzies run out: IT'S ON YOUR SIX, and the next frenzy's blinks
   come in behind you (the blink check line: 500 / 800 m behind, flight path toward you). Fair? behind_share.
3. ... first, phases 1-2's ECM: its jamming ring up the whole time before 35 % (as hard rule 40's test; ecm_row is off,
   so this is the confirmed row and event). Then bring it under 35 %: ITS ECM IS DOWN, the radar's jamming ring gone
   within ~2 s and not back (a flicker every 14 s, at most ecm_check_s long, is the row's next pod before the check),
   your missiles track; in front of it within 1.5 km its gun fires, beside or behind it it doesn't, and it reverses onto
   you (LastTGT) every 10 s and when you get behind it. The ring back for good means the pods-off write didn't take
   ("ECM pods off: ... -> true/true"): send the line; ecm_row = true (a game restart) is the other lever.
4. A Ladon round: shoot one down: <NAME> ENRAGED, "the hostile's changed course", its volleys 25 s apart; at its next
   pass over the airfield it flies the tighter circuit (minimap) and keeps bombing once a lap, not every second (hard
   rule 35's symptom), and doesn't turn back west (its area holds the circuit).
5. An ALICORN round: 22 s in "planes launching from the carrier" and PLANES LAUNCHING, 25 s in a 2-ship appears off
   its bow at ~1200 m and gets its orders (no "never got its orders"); a Skirmisher's LAAM from 7 km. No more than two of
   its flights up at once, and with two up no PLANES LAUNCHING until one is down (then the call, 3 s later the launch);
   none while it's dived; one 6 s after it surfaces. They don't hit the hull or the sea, and don't turn away to climb
   or go back to their unit area right after the launch (AvoidObstacle / ReturnToWorld / ReturnToUnit in the ai: lines
   would say so; alt_m, ahead_m).
6. Co-op (a host and a joiner): the joiner alone in MINDRIPPER's field doesn't spring the pack; the host's spring turns
   the guards onto the host only; AB.L..IN's phase 3 ECM drop shows on the joiner's radar too (the joiner's log: "coop:
   AB.L..IN in its phase 3 on the host ..."); the deck flights appear on the joiner's game.
7. Tells off (survival.ini [tells] enabled = false): THE PACK SPRINGS, IT'S ON YOUR SIX and ITS ECM IS DOWN still show
   (callouts only, no radio), but not while you're down at the airfield, between rounds or over the summary.
8. An ALICORN round (code review of 2026-10-29): destroy both railguns (and every VLS): no more railgun warnings, RAILGUN
   WARNING, VLS LAUNCH or volleys. Does a destroyed railgun or VLS read HealthInternal 0, or go (`0 found`)? Either
   counts as down; one that stays above 0 while wrecked would keep its tells (the `are down` line never comes). The
   `found:` lines should say 2 railguns and 4 VLS; fewer, or a `more found` line, means some appear after the
   first parts pass (looked for again before a kind counts as down).

### Offline test
`sh tools/checks/bosses_test.sh` (real parts, the game stubbed; in tools/README.md's checks row): survival.ini's four
new sections read; the pack's whole cycle on the real ANOM.tick (armed with its tell, the spring at spring_delay_s, the
hold only after min_s and hold_after_s, the cooldown, leaving the field before the spring, every guard down, pack off),
hunt_only_sprung through the real ACE.hunt; AB.L..IN on the real glitchTick (phase 2 after two frenzies with its tell;
every blink at your six with behind_share 1, following your heading; behind_share 0 as before; phase 3 at 34 % with its
tell, no more ECM events, only its own pod switched off, no frenzy on a hit, LastTGT every 3 s behind it and every 10 s
off its tail, its gun only within 1.5 km in front of it; phase 3 mid-blink; phases off); the rage on the real ladonTick
(its event, callout, tell, 25 s volleys, the enraged pass line; both down in one second; rage off); the deck on the real
alicornTick (the warning 3 s before, a Skirmisher 2-ship 800 m off the bow at 1200 m along its heading, every 35 s,
max_up and the airfield with no tell while held and the tell warn_s before the launch that comes, D.deckLeft to 0,
dived and surfaced, roles off, alt_m 600 floored at 1100, deck off); startRound's D.deckLeft (rounds 8 / 14 / 40,
escorts folded in or not, deck off, another special) and the deck never launching one of the round's own flights (the
spare it takes taken out of D.spare); the guards' set on every level and AB.L..IN's ECM row (anomEcm's by default, its
own with ecm_row; MINDRIPPER's kept) from the real searchSetup on fake tables; the sure tells (tells off, a cooldown, a
joiner's "tl", a host's to its joiners through the gap; nothing between rounds; reversal as before); the pack's spring
not fired; an enraged Ladon's volley through the other's gap, its first first_s after the rage; "rnd"'s AB.L..IN
phase and a joiner's copy's pods (ANOM.clientGlitch); co-op's keep list; the hooks. Then
bosses_build_check.py on survival_events.py: the rage circuit (start / end, area, a 42 s lap, its speed, letters,
flags), GLITCH_POST_STALL's Turn, the radio lines, the Lua names the build checks. Three mutants (the ECM event still
fired in phase 3, a rage with both Ladons down, a launch while you're at the airfield) each fail it; so do the review
fixes' five (the deck taking a round's flight, the rage under the gap, no sure callout, a joiner's pods off in phase 2,
the deck told while you're at the airfield). The code review of 2026-10-29 added (each fails on aa96bc1's parts): the
ALICORN's railguns and VLS (both railguns shot inside a warning: the RAILGUN WARNING off at once, no order, call or
warning for 135 s while its VLS go on; every VLS down: no call, callout or volley; a VLS down in its call's lead: no
volley; railguns gone: down; regression guards: one of two down, railguns never read up or unreadable, warned and fired
as before), the calls after a surfacing (alcn_up at 31, the railgun's warning at 33 and its order at 38, the deck's call
held to 35 by that gap and launched at 38; a gap that won't end: held twice, its callout alone at 36, the launch at 39;
tells off: the order at 36 as before), F4's second round (each fails on 9fc9874's parts: a railgun and two VLS found a
parts pass after their siblings, the first ones shot down: looked for again, their orders and volleys go on, then down
with one more FindAllOf; one found at 0 as the others go down gets a pass of its own; the `found:` counts; a co-op
host with tells off: the joiners' deck call held by their gap and sent at 35), a sure tell with tells off at the
airfield, between rounds and over the summary (none; a joiner's from the host between rounds still shows), and
AB.L..IN's pods-off line when none is its own.

### Untested / known limits
- [I] Nothing here has run in game. The mechanisms are confirmed ones (unique actions by unit, hard rule 37; the blink
  teleports, 39; WN_WEAPON slots, 40; flag-gated records checked when their event fires, 26; spawnFlight's pose through
  SV_Spawn as ANOM.spawn uses it), but each use here is new.
- [I] The guards on NLID_SV_WolfWing: their behaviour changes from the fighters' set (the confirmed guarding);
  guard_luaset "" puts it back. Set at the main menu: a game restart to change.
- [I] The pack keys on the host's field only (a joiner's own field never springs it; its LastTGT would turn the guards
  onto the host anyway). The spring's LastTGT on the guard unit (not a pool flight) is the stock form, untested here.
- [T] The ECM drop: the pods-off write (bJammingEnable / bSupportEnable on BP_wp_ecm_a0) is untested, and with
  ecm_row off (the default) it's phase 3's only drop: if it doesn't take, phase 3's ECM stays up under ITS ECM IS DOWN.
  ecm_row true (its own row, at most a pod a minute) is untested too and leaves phases 1-2's ECM to the event alone. A
  joiner's copy gets the host's phase through "rnd" (1 s, unreliable: up to a second or two late) and switches its own
  pods off.
- [I] Phase 2's "behind" is your heading in the horizontal plane at your height: a steep climb or dive isn't behind in
  3D; the spot is up to 15 deg off dead six plus your turn in the 250 ms tick. Its smoke there is out of view, so the
  tell and behind_share are the fairness levers.
- [I] Phase 3's guns fire RE_SV_GlitchGun (forwarded) on the host's geometry: a joiner's copy fires at the joiner
  while the host is close in front of it, wherever the joiner is (as the frenzy's gun always has).
- [I] The rage circuit: its heights follow the old circuit's nearest points (1.25-2.0 km); the terrain under it isn't
  checked. The switch waits for the survivor's next pass (~42-72 s on the circuit, ~3 min if it's still inbound). The
  Ladon may not reach 3000 km/h (its row's top speed); a slower lap is longer, never shorter.
- [I] The deck: spawned 1200 m over the sea next to a big hull (above the pool units' 1000 m floor, read from the built
  world data; whether a spawn under the floor would have made them climb or go back to their area first is unknown),
  AvoidObstacle or the sea are risks; s.depthPart is nil
  until the first parts pass (2 s), so the first launch (25 s) has it. The hull's forward is read from its core part
  (attached, so the hull's), else "towards you". D.deckLeft doesn't grow with co-op's player count except through its
  folded escorts (COOP.more scales those).
- [I] The ALICORN's railguns / VLS down (code review of 2026-10-29): read from BP_BA002_alcn_emls_Base_C (LiveAIRailgun)
  and the vls*_Base_C parts' HealthInternal in the 2 s parts pass (FindAllOf until some are found, then those kept, and
  once more before a kind counts as down), so the warning may stand up to 2 s after the last is shot (4 s when the
  look finds a new part at 0). Whether a destroyed part reads 0 or goes (no longer valid) is unknown (both count); a
  kind never read above 0 is never counted down. A part that appears only after its kind was counted down isn't
  tracked (whether all appear in the first pass is unknown: the `found:` lines show it).
  Whether the game drops one of two radio lines asked for in the same frame is unknown too: after a surfacing they're
  now radio_gap_s apart (the order 2 s later than before when it was due under water).
- Not built: the Ladons' top cover (against the user's 2026-10-25 instruction; the brief's step 6 off by default would
  still have changed that rule, so it's left out), MINDRIPPER's optional third phase (a wider field under 40 % health: a
  joiner's own field couldn't follow it without a new "rnd" field), a closer blink ring.

### Review fixes (after unit 9's review; not yet run in game)
- **The deck told before a launch that couldn't go (minor).** alicornDeck said its tell (alcn_deck and PLANES
  LAUNCHING) at deckNext - warn_s, before the checks that hold the launch (max_up up, you at the airfield, no part read,
  no free 2-ship); a held launch only slid deckNext on with s.deckWarned left true, so with two of its flights up the
  call came and the launch could follow minutes later untold. Now the checks run from warn_s before the launch to the
  launch, the tell only once none holds it, and a hold (or a failed spawn) clears the tell so it comes again warn_s
  before the launch that goes.
- **Deck flights under their band (minor).** Deck flights are 2-ships (the ERA_Unit_NN_Dep_Air0 units), whose areas in
  the built world data start at MinAltitudeInMeter 1000; alt_m 600 put them 400 m under it. alt_m is now 1200, and
  never under DECK_FLOOR_M 1100 (a lower alt_m is floored and logged). Item 5 of the test checklist watches for
  ReturnToUnit right after a launch.
- **AB.L..IN's phases 1-2 ECM (minor; a confirmed behaviour at risk).** ecm_row (its own 60 s row) was on by default, so
  every AB.L..IN round's phases 1-2 relied on RE_SV_GlitchEcm alone, while hard rule 40's "up all fight" was confirmed
  with anomEcm's 14 s row and the event together. ecm_row is now off by default: phases 1-2 are as confirmed, phase 3
  drops the ECM by ecm_pods_off alone (ecm_check_s 3 -> 2, so the row's next pod jams at most 2 s of its 14).
- **The pack (and AB.L..IN's phases) told only through TELL (minor).** With tells off, or the tell refused by its gap or
  cooldown, the pack sprang with no warning. The tells pack, glitch_six and glitch_allout are now `sure`: TELL.play shows
  a sure tell's callout when it isn't said (raw, never mirrored; no radio; never between rounds, at the airfield or
  over the summary), a joiner's "tl" does the same on its game, and a host sends a sure tell to its joiners through its
  gaps. The pack's line says "told", "its callout only: <why>" or "not told: <why>".
- **An enraged Ladon under the shared gap (minor).** The survivor still waited volley_gap_s 22 after the dead one's last
  volley: a rage volley_every_s under 22 was floored and its first could wait 22 s. Enraged, the gap is 0. Its first
  rage volley is now first_s 5 after the rage itself (with the gap gone it could come in the rage's own second, on top
  of its callout and line).
- **The deck taking a queued flight (minor, escorts false).** deckFlight's free() checked D.up and SV_UnitAlive only, so
  it could launch a flight queued for a later wave, whose turn then rewrote the live flight's tier, role and orders.
  startRound keeps its picks as D.taken; the deck never takes one, and a spare it launches leaves D.spare.
- **The spring logged when it didn't fire (minor).** A failed RE_SV_AnomalyPackSpring now logs "pack not sprung (its
  event not fired); armed again in N s" and no "sprung" line.
- **Scope: AB.L..IN's phase 3 on a joiner.** The ECM drop ran on the host's plane only while ITS ECM IS DOWN went to
  every player. The host's "rnd" now carries AB.L..IN's phase (its 9th field, 1-3 or empty; a joiner takes only 1-3),
  kept as D.glitchPhase, and ANOM.clientGlitch switches the joiner's copy's pods off every ecm_check_s in phase 3 (the
  same glitchPodsOff). A joiner on an older build ignores the field; the next friend build's COOP_TAG bump covers it.
- Not changed: the pack on a joiner's own field (LastTGT steers to the host: documented above; a joiner's copies of the
  guards are puppets, so the sprung engagement and area records under the kept event don't matter there),
  MINDRIPPER's optional third phase, the Ladons' top cover (the user's "Ladons alone"), RE_SV_GlitchTurn's name (the
  contract's "never RE_SV_Glitch" guards against an event kept on the host by accident; GlitchTurn, a LastTGT onto the
  host, is meant to be kept, and mirroredEvent's RE_SV_Glitch rule does that; the test checks it), and the COOP_TAG /
  VERSION bump (the contract's last unit).

## Unit 10: ace personalities (P9), and the branch's wrap-up

The thesis' P9: "Give each named squadron its own set built from the stock ace scripts (minus the KDS gates): Bounty
fights as Lancers, Valkyrie as a Wolf pack, Inferno as Duelists with post-stall, Wraith blinks like a lesser AB.L..IN,
Harvest combines all of them. Each squadron should be recognisable within 10 seconds." Built as the behaviour
pipeline's recipe c1 (the cheap first build; c2, one set per squadron on new descs, only if c1's squadrons don't feel
distinct) with the critic's gap fills: a squadron flies the behaviour set of the role flights its ace round draws (a
tree is its world-data desc's, hard rule 20; the squadrons spawn into pool flights), and its identity is what Lua
fires on it: a one-shot **opener** per flight at first contact, after its squadron's **tell**, and Wraith's (and
Harvest's) lead **blinking** off your six (Mission 22's teleport, hard rule 39, as AB.L..IN's). A squadron's flights
only (D.aceSquad: never its tier's ordinary flights between ace rounds); the host's or solo. Lua (sv_ai.lua's new block,
hooks in sv_spawn, sv_rounds, sv_rows, sv_anomalies, sv_director, sv_stats, sv_tells, sv_coop, sv_main),
survival.default.ini and the build (tools/survival_events.py: 48 new remote events). Every piece has its own switch;
nothing here has run in game.

| squadron (tier, ace rounds) | flies (its ace round's roles) | opener at first contact (its km) | the rest |
|---|---|---|---|
| Bounty (Mercenary, 16+) | the Lancers' flights (NLID_SV_Lancer: slash and zoom, never turns with you; 2 km higher) | **high** (5 km): BOUNTY: FROM ABOVE and a dive line; 1 s on, a missile from each of up to 2 of its planes within 5 km, 0.6 s apart (RE_SV_Salvo_<NN><L>, P2's) | a Bounty flight filled from another group spawns 2 km higher too (up to 4.5 km: the pool's band) |
| Valkyrie (Legend, 19+) | the Wolf pairs' flights (NLID_SV_WolfLead baits, NLID_SV_WolfWing traps) | **trap** (4 km): VALKYRIE: THE PACK and a lure line; its trap (every second plane, held at engagement None since its appearance, as P1's) springs 8 s later after IT'S A TRAP: free and LastTGT onto you (WOLF.free with the turn) | a Valkyrie flight off the Wolf pairs: the pack turns on you instead (RE_SV_AceTurn_NN); P2's spring tactic can spring it sooner |
| Inferno (Demon, 22+) | the duelists' (NLID_SV_Fighter: LA_SV_TailChase's AI-level-5 Super pursuit) | **kulbit** (2.5 km): INFERNO: POST-STALL ACES and a reversal line; 0.5 s on, every plane of the flight kulbits as one, firing its special (RE_SV_AceKulbit_NN, the Shadows') | post-stall on, as its tier's (F-22A / Su-57 in CFG.maneuvers.post_stall: no change needed) |
| Wraith (Phantom, 25+) | the duelists' | **blink** (4 km): WRAITH: THEY BLINK and a check-your-six line; 0.5 s on, its lead blinks to 1 km behind and beside you (your heading +-135 deg; over high ground dead six, then abeam; ground_clear_m), smoke where it left and came out | its lead blinks again whenever you sit within 2.5 km and 70 deg of its six, or you hit it, at most every 20 s (IT BLINKED, 0.5 s before; a hit while it can't blink, inside those 20 s, an opener or a blink on its way, your decoy or a director hold, is no reason for a later one) |
| Harvest (Reaper, 28+) | the duelists' (Super pursuit, with its own airframe boosts) | in turn per flight: **kulbit**, **blink**, **high** (a blink only on a duelist flight's lead) | its lead blinks off your six (every 30 s, not on a hit); its reversals (moves), hunt and no_provoke as before; a blink holds its flight's reversal 10 s (move_gap_s), so tailing its lead gets a blink, its wingman a reversal |

The critic's caveat on the Super branch: LA_SV_TailChase's AI-level-5 "Super" pursuit is only in the duelists' set, and
only Demon, Phantom and Reaper fly at AI level 5 (Mercenary 3, Legend 4: Bounty and Valkyrie never had it). So Inferno,
Wraith and Harvest stay on the duelists' flights, and Harvest "combines" the others through its openers and blinks
rather than their sets (no AI-level branch was added to the Lancer / Wolf pursuits: ordinary AI-level-5 flights fly
those too, and the Lancer must never turn with you).

### What was built
| piece | where | what it does |
|---|---|---|
| the role mix | sv_config.lua `ROLE.mixFor(round, ace)` (ace now true or the round's tier key), CFG.aces.flight <tier>.roles; sv_rounds.lua startRound passes the key; sv_spawn.lua ROLE.pickRound's line | an ace round draws its squadron's roles (band "ace:<tier>": `the Bounty squadron's roles`); all 0 or personality off: CFG.roles.ace_mix as before. A group of 24 aircraft fills the rest of a 30 round from the others (logged "filled from"); a squadron on the duelists' set alone (Inferno, Wraith, Harvest, ace_mix's) from the Wolf pairs first, whose pursuits (LA_SV_TailChase, LA_SV_WolfStrike) keep the Super branch, then the rest (`; filled from wolf 6 (the Wolf pairs first: they keep the Super pursuit)`; the code review of 2026-10-29) |
| the opener | sv_ai.lua `ACE.pickOpener(unit, tk, role)` (spawnFlight, before the spawn; `ace.opener`) | the tier's `openers` in turn (D.openerNext); a blink only where the lead has blink events (ACE.blinkEvent); none fits: kulbit (logged once a round) |
| high's altitude | `ACE.highAlt(alt)`; spawnFlight's altitude branch | off a Lancer flight: + alt_add_m 2000, at most top_m 4500 (the pool's band; a Lancer flight already flies 2 km up in its raised band) |
| Valkyrie's trap | sv_spawn.lua ROLE.spawned, WOLF.spawned(unit, n, now, untilContact), WOLF.contact | an ace flight in a Wolf flight whose opener is the trap holds its trap as P1's Wolf flights do, but until its first contact: roles.wolf's hold_max_s runs from the contact (or the hold, the later), and a trap nobody meets is let go openers.trap hold_max_s after the hold (U10's review); any other ace flight still neither calls out nor holds |
| the squadron | `ACE.squadUp(unit, ace, role, n)` (spawnFlight, every flight up: a non-squadron clears a recycled one) | D.squad[unit] = { tk, ti, op, ... }; its line: `aces: <unit> (<Squadron> squadron, <role>) opens with <op> at first contact (within N km)[; its lead blinks off your six (every N s at most)]` |
| first contact, the openers, the blinks | `ACE.squadTick(now, D, paused)` (sv_main.lua, timed "squads", before ACE.movesTick); its local `open`, `act`, `high`, `trap`, `springTick`, `free`, `kulbit`, `turn`, `blinkNow`, `blinkCheck` | every 0.5 s a not-yet-met flight's planes (the sweep's p.at) against every flying player (COOP.players()); the first in its opener's km: the tell (the squadron's `<tier>_in` the first time this round that player meets it, its name from a = the tier's index; later flights the opener's own: dive, drag, kulbit, blink), the opener its lead_s later (the catalog's lead_s, said or not). A blink reads the lead and you afresh only when the sweep had it within tailed_km + 1.5 (the contract's read budget). Your DECOY (or a director hold) on the flight: the opener isn't shown, no blink |
| the blink spots | sv_config.lua `ACE.BLINK = { STEP_DEG = 45, RING_M = 1000, ROLE = "duelist" }`, `ACE.blinkEvent(unit, j)`; survival_events.py WRAITH_BLINK_*, `wraith_blinks()`, `build_wraith(g)` (end of build_events) | RE_SV_WraithBlink<K><J>: K the flight's pool letter (A = ERA_Unit_01_Dep_Air0 ... F = 02_Air2), J the bearing (A = 0 deg, world +X; every 45), 1000 m from the player at their height, facing them: AB.L..IN's record (Mission 22's LiveActorTeleportExecution, {1 object 0 of the flight (POOL_OBJS), 2 Player, 4-6 offset, 11 yaw, 13 Absolute}). 6 duelist flights x 8 = 48. The build checks ACE.BLINK, that the Lua fires the name and that co-op keeps it |
| the ground and the smoke | sv_anomalies.lua `ANOM.groundAt` (its groundAt), `ANOM.smokeAt(at)` (AB.L..IN's smoke) | the spot's clearance: ground_clear_m 150, or 80 % of your own height when you fly lower (AB.L..IN's rule) |
| the dive's o'clock | sv_director.lua `DIR.oclock` (its oclock, exported) | a later Bounty flight's "dive" tell names its o'clock |
| tells | CFG.tells.list `mercenary_in`, `legend_in`, `demon_in`, `phantom_in`, `reaper_in` (urgent, sure: their callout even when the tell can't be said), `blink` (urgent); args "squadron" (sv_tells.lua fill: the tier's squadron name from this game's CFG.aces; ACE SQUADRON off the list) | other tells' radio lines (Dive, EnLure, Turn, Six, Hunt; no new rows); text e.g. `BOUNTY: FROM ABOVE / THEY STRIKE AND CLIMB: DON'T FOLLOW THEM UP` |
| counts | sv_stats.lua NOT_DIRECTOR gains opener and blink (counted apart, never tagged: no director kill bonus); the round line's `, squadron openers N, blinks M` after "ace reversals" (only when there were any); stats_report.py `squad_lines` | |
| co-op | sv_coop.lua KEEP_EVENTS gains ^RE_SV_WraithBlink; ACE.squadTick returns on a joiner | a joiner first met: its tell ("tl"), the salvo on its copies ("dv"), the kulbit, the trap freed without the turn; no blink round it (tools/re/COOP.md) |
| the searchSetup guard | sv_rows.lua (a squadron's airframe boost only for an entry with turn_add) | every tier now has a CFG.aces.flight entry (roles, openers); only Reaper's flies beyond stock |

Build: events 819 triggers, 1588 execs (were 771 / 1540); radio unchanged (721 rows, 61 tell lines). ep_dump of the
built package shows RE_SV_WraithBlinkAA .. FH as Mission 22's teleport on the flights' object 0 (the salvo records'
objects), offsets 1000 m round, yaw facing back.

### CFG keys (CFG.aces.personality, CFG.aces.flight.<tier>; in survival.ini; the host's for the room)
- `personality` ([aces.personality]): `enabled` true, `tells` true, `ground_clear_m` 150, `smoke` true; `openers`
  ([aces.personality.openers.<op>]): `high` { km 5.0, alt_add_m 2000, top_m 4500, salvo 2, gap_s 0.6, range_km 5.0 },
  `trap` { km 4.0, spring_s 8, wait_s 15, hold_max_s 300 (the trap held till first contact at most this long from
  its hold; 0: as any Wolf flight's, roles.wolf hold_max_s from the hold) }, `kulbit` { km 2.5 }, `blink` { km 4.0 }.
- `flight.<tier>` ([aces.flight.<tier>], [aces.flight.<tier>.roles], [aces.flight.<tier>.blink]): `roles` (duelist /
  lancer / wolf / skirm weights: mercenary lancer 1, legend wolf 1, demon / phantom / reaper duelist 1), `openers`
  (mercenary high, legend trap, demon kulbit, phantom blink, reaper kulbit, blink, high; "none": its tell alone, at
  4 km), `blink` (phantom: enabled
  true, every_s 20, tailed_km 2.5, tail_deg 70, on_hit true, move_gap_s 10; reaper: every_s 30, on_hit false). Reaper's
  turn_add / speed_x / cruise_x / health_add / post_stall / hunt / no_provoke / moves unchanged.
- CFG.tells: the six tells above, cooldown_s (the `_in` ones 0, blink 10), lead_s (mercenary_in 1.0, legend_in 0,
  demon_in / phantom_in / reaper_in / blink 0.5), texts. [tells.cooldown_s] and [tells.lead_s] list them.
- Build data outside CFG: `ACE.BLINK` (survival_events.py WRAITH_BLINK_*; the build checks them).

### Log lines to look for in a test
- `roles: round 16 (the Bounty squadron's roles: duelist 0.00, lancer 1.00, wolf 0.00, skirm 0.00): 30 of 30 aircraft:
  duelist 4, lancer 24, wolf 2, skirm 0; short: lancer 24 of 30; filled from duelist 4, wolf 2`
- `round 16: ERA_Unit_03_Dep_Air1 [lancer] as sv_ace_mercenary_f15c_w (ace squadron, ...), ..., 4.3 km up: 4 aircraft up`
- `aces: ERA_Unit_03_Dep_Air1 (Bounty squadron, lancer) opens with high at first contact (within 5.0 km)`;
  `aces: ERA_Unit_02_Dep_Air1 (Wraith squadron, duelist) opens with blink at first contact (within 4.0 km); its lead
  blinks off your six (every 20 s at most)`; `aces: <unit> (Wraith squadron, lancer) can't show blink (a blink needs a
  duelist flight's lead): it opens with a kulbit`
- `aces: <unit> (Inferno squadron) meets you 2.2 km off (BP_...): told (demon_in); its kulbit in 0.5 s` (or `demon_in's
  callout only: <why>`, `... meets player 2 ...`), with `tell: demon_in: RE_SV_RadioTurnA (fired), tell callout
  'INFERNO: POST-STALL ACES'`
- `aces: <unit> (Inferno squadron) kulbits as one: RE_SV_AceKulbit_NN fired`
- `aces: <unit>'s opening salvo: RE_SV_Salvo_08A fired` then `... RE_SV_Salvo_08B fired`; `... on player 2's copies
  ("dv"): RE_SV_Salvo_08A sent, ...`; `... none of its planes can fire at you (range, missile slot)`
- `aces: <unit> (Valkyrie squadron): its trap springs in 8 s`, `... its trap springs on you in 1.0 s (told (trap))`, then
  `roles: <unit> (wolf) trap freed (Valkyrie's trap springs): B, D, F, turned onto the player`; `... its trap isn't held
  any more (sprung, freed or down); nothing to spring`; `aces: <unit> (Valkyrie squadron) has no trap held: its pack
  turns on you: RE_SV_AceTurn_NN fired`
- `aces: <unit>'s lead BP_... blinks (its opener): your heading 12 -> spot 135 deg, 1000 m (RE_SV_WraithBlinkBD fired)`;
  `... blinks (you 1500 m on its six, 4 deg off its tail; told (blink)): ...`; `... blinks (you hit it; ...)`;
  `aces: <unit>'s lead didn't blink (<why>): no spot clear of the ground round you` / `its lead is down`
- `aces: <unit>'s blink is round the host's plane only: none for player 2 (its tell only)`; `aces: <unit>'s kulbit not
  shown: your decoy (or the director) stands it down`
- A Valkyrie trap met late: `roles: <unit> (wolf) trap N s after its orders: held B, D, F`, no `trap freed (held 60 s)`
  before its `meets you` line; one never met: `trap freed (held 300 s, nobody met it)`; a spring that never came (your
  decoy): `trap freed (held 60 s, N s since it met you)`.
- `aces: <unit>'s kulbit waits N s: a move of the flight is in flight (a reversal, the director's turn)` (the opener
  after a reversal from before the contact); `aces: <unit>'s blink opener not shown: its lead blinked already`.
- The round line: `...; ace reversals N, squadron openers N, blinks M; tail watch: ...`; `perf: ... squads x/y` only
  when it costs; errors `aces: squadron error ...`, `aces: opener error ...`, `aces: trap error ...`.
- stats_report.py: `squadron lines: N first contacts, M blinks, K openers / blinks not shown`, a row per squadron
  (`Wraith met 4 times (told 4): blink x4`), `blinks: on its six xN, the opener xN, you hit it xN`.

### Test checklist (in game)
In the all-units checklist below (P9).

### Offline test
`sh tools/checks/aces_test.sh` (real parts, the game stubbed; in tools/README.md's checks row): survival.ini's new
sections; ACE.BLINK and ACE.blinkEvent (a duelist flight's lead only, letters); each squadron's mix (ROLE.mixFor; the
real startRound at rounds 16 / 19 / 22: 24 of its group's aircraft, the rest filled; personality off: ace_mix's line);
spawnFlight's opener (Bounty high on a Lancer flight and 2 km higher off one, at most 4.5 km; Valkyrie's trap held on a
Wolf 6-ship; Inferno filled into a Wolf flight: no hold; Harvest's openers in turn, a blink skipped on a Lancer flight;
Wraith off the duelists: a kulbit, logged; an ordinary flight clearing the entry; personality off; openers none: its
tell alone); first contact
(not before the opener's km; the squadron tell with its name, then its opener lead_s later; once a flight; the round's
second flight with the opener's own tell); Bounty's salvo (the two nearest able planes, gap_s apart; none with the
missiles in another slot); Valkyrie's trap (sprung spring_s later after IT'S A TRAP, free + turn on B, D, F; waiting
while pending; the pack's reversal off a Wolf flight); Wraith's blink opener (135 / 225 deg, smoke, its cooldowns; the
ground: dead six, or none); the blink tick (not 90 deg off its tail, on its six, every_s, a hit; Harvest: the blink
first, its reversal held move_gap_s, then the reversal; no blink on a hit); your decoy; personality off; the round
line's counts; co-op (the keep list; a joiner meeting Bounty: mercenary_in by "tl" with the tier's index, the salvo by
"dv"; a joiner meeting Wraith: its tell, no blink; a joiner's game: nothing); the tells' squadron text (a renamed
squadron, a tier off the list); the hooks by their place. Then stats_report.py on its log (its squadron lines) and the
build's half (WRAITH_BLINK_* against ACE.BLINK, 48 names on the 6 duelist flights in letters, each once, the pool
letters as Lua's poolIndex, the Lua and the keep list naming them, COOP_TAG -coop.18). Mutants that each fail it: no
move_gap after a blink, Valkyrie's trap not held, the blink not kept in co-op, the squadron tell on every flight, no
ground clearance, the tailed blink without its cone. tells_test (args "squadron") and roles_test (an ace round: the
Bounty squadron's Lancers; personality off: ace_mix's duelists) were updated for it. After the review (WOLF.tick
running): a Valkyrie trap still held 87 s on without a contact and sprung when met at 190 s; let go 60 s after the
contact (or the hold, the later) when its spring never comes (your decoy); let go hold_max_s after the hold when nobody
meets it; hold_max_s 0 as before. Wraith's lead hit from 6 km before it's met: no blink, then one (the opener's) at
contact and none for that hit after every_s. Harvest met with you 2.4 km behind a wingman: no reversal in that tick,
the kulbit, the reversal only after its 12 s; a reversal in flight till 120 s: the kulbit waits, then goes. Mutants that
each fail it: hold_max_s from the hold for an ace trap, no WOLF.contact, no opener hold on the reversals, blinks before
the contact, no wait for a move in flight, the hit from before the contact not seeded. After the code review of
2026-10-29: Inferno's round 22 filled from the Wolf pairs only, a Harvest round of 56 (the duelists' 24, the Wolf
pairs' 24, the last 8 from the rest), Bounty's fill as before; Wraith's lead hit 5 s after a blink: no blink for it
when every_s is over, one for a hit after it (each fails on the code before the review).

### Untested / known limits
- [I] Nothing here has run in game. The mechanisms are confirmed ones (unique actions by unit, hard rule 37; the
  teleport, 39; a forced shot on WN_WEAPON_3, 40; per-object engagement, P1's [I]), each used in a new place.
- [I] Teleporting a pool flight's plane (confirmed on AB.L..IN's own unit only; the critic's open risk), and that object
  0 of the desc is the plane the sweep calls k 0 (unit 1's "spawn index" line: Harvest flights give the verdict).
- [I] Bounty's opening salvo: whether a forced LiveFireOneShotWeapon at 4-5 km needs a lock (the director's bracket has
  the same question; P2's checklist item 3).
- [I] The kulbit at 2.5 km (the Shadows' OneShot: a short straight, a kulbit, its special fired): whether a whole flight
  doing it at once reads as "Inferno" or as noise; tune `kulbit.km`.
- [I] The squadron tell is said to the player a flight meets first; another player meeting a different flight of the
  same squadron later gets it then (D.squadSaid per player), but one who meets an already-opened flight gets nothing.
- [I] Blinks round the host only (the teleport's "Player"); a joiner sees the lead jump in the plane stream.
- [I] Ace rounds of 30 draw 24 aircraft from a squadron's group (each group holds 24); the other 6 come from the rest and
  show whatever opener fits there (a Wraith off the duelists kulbits). In co-op (up to 60-80) most of a squadron is
  then off its group.
- [I] A Valkyrie trap held at engagement None for minutes, until first contact (P1's per-object hold was planned for
  under 60 s): whether its held planes keep with their formation that long, and what a unit-wide order in between (the
  chase's area move is not one; a director hold or your decoy is) does to it. Hunts leave a held trap alone (WOLF.holding)
  for that longer time too: the allies' hunt comes after the release, and a co-op hunt after a joiner ordered while it's
  held is dropped (`coop: <unit> holds its Wolf trap; it doesn't go after the joiners`, as P1's Wolf flights inside
  their 60 s), so in co-op a Valkyrie flight usually meets the host first.
- Not built: recipe c2 (one set per squadron on new descs: ~15 descs, load cost untested), AI-level ace branches in the
  role scripts, a closer blink ring.

### Review fixes (after unit 10's review; not yet run in game)
- **Valkyrie's trap freed before it was met (minor).** An ace Wolf flight's hold went through the ordinary WOLF.tick,
  which let it go roles.wolf's hold_max_s (60 s) after the hold, about 5 s after the spawn. Flights spawn 18-25 km out
  and meet you at 4 km, often more than a minute later, so the trap opener found nothing held and fell back to the
  pack's reversal while VALKYRIE: THE PACK said the ones hanging back were the trap. Now ROLE.spawned passes
  openers.trap's new `hold_max_s` (300) to WOLF.spawned as `untilContact`: until its first contact (WOLF.contact, from
  ACE.squadTick's open) WOLF.tick lets the trap go only that long after the hold; after it, roles.wolf's hold_max_s runs
  from the contact (or the hold, the later). Its other releases (a hit, its bait down, your decoy's rules) stand.
- **An opener and a reversal cutting each other (minor).** open() only scheduled the opener, so ACE.movesTick (after
  the squads in the same tick) could fire a Harvest reversal as the kulbit was told, and the kulbit 0.5 s later cut it.
  open() now holds the flight's reversals and the director's cover turn (D.aceMoveAt) until the opener's gone
  (sq.holdTo: its action + 1 s, a salvo's last shot on top). A move already in flight at the contact (a reversal from
  before it, at 3 km where the kulbit's km is 2.5) is waited out by a kulbit, or a trap's turn with none held, once
  (`... waits N s`).
- **A blink before the squadron was met (minor).** The blink tick ran from the spawn, so a Wraith lead hit from beyond
  4 km blinked behind you with IT BLINKED before WRAITH: THEY BLINK, then blinked again as its opener ~1 s later. The
  blink tick now runs only once the flight has met someone, open() takes the lead's damage so far as seen (a hit from
  before the contact never makes a blink), and the blink opener is skipped if its lead blinked already.
- **The squadron tell's cooldown comment (minor).** survival.default.ini said cooldown_s 0 repeats a squadron's call for
  every flight; the call is said once a round per player, for the first of its flights they meet (later ones call their
  opener). The comment says so now.
- Not changed (the review's scope notes): Harvest still flies the duelists' flights only (the critic's Super-branch
  caveat: a Lancer must never turn with you and the Wolf / Lancer sets have no ace branch), combining the others through
  its openers (kulbit, blink, high) and its lead's blinks; recipe c2 and AI-level ace branches not built; co-op blinks
  round the host only, and no squadron tell for a player meeting an already-opened flight (all above, [I]).

### The branch's wrap-up (unit 10)
- main.lua VERSION 0.72.0; tools/coop_edition.py COOP_TAG -coop.18 (units 5, 7, 9 and 10 changed the world data, rows,
  events and messages: games with an older tag refuse to link).
- AGENTS.md: "Enemy behaviour build (Lua 0.72.0, TestBranch_Behavioural; untested in game)".
- The test checklist for the whole branch below.

## Test checklist: every unit (P1-P9), in game

One list for a playtest of TestBranch_Behavioural (Lua 0.72.0, COOP_TAG -coop.18), by proposal: what to look at, and
the log lines (AC8SurvivalMode_lua.log, or UE4SS.log behind its tag) that prove it. Run
`python -X utf8 -I tools/checks/stats_report.py <log>` on the log afterwards: it tabulates most of them. Each item's
switch is in survival.ini (a restart where a row or set is made at the main menu). Each unit's own section above has
the details.

**0. The build and the measurements (unit 1)**
- Main menu: every `behaviour: set NLID_SV_<X> in (...)` (Fighter, Lancer, WolfLead, WolfWing, Skirmisher) and `game Lua:
  stock SurvivalMode.AI.LA_SV_<X>: true`; level load: `game Lua: built ... ; errors 0` with all eleven LA_SV_ modules,
  `roles: at level load lancer NLID_SV_Lancer, wolf ..., skirm ...`; `[AC8SurvivalMode] loaded, version 0.72.0`.
- `round probe: AI aircraft created #N: ... (<unit>, k N)`; a jammer or Harvest flight's `spawn index: ... k 0 is the
  lead: creation order = desc order` (THE check for every per-plane event: salvos, Wolf traps, blinks).
- Each round's `stats: round N (...)` a few seconds after its clear, `kill-time:` lines, `death:` at death, `stats: run
  over (...)` at the end; the seven metrics against their targets in stats_report's run table.

**P1 fighter roles (unit 5)**
- `roles: round N (the mix from round X: ...)`; spawn lines with `[lancer]` / `[wolf]` / `[skirm]`.
- Lancers ~2 km above the rest, one slashing pass then a zoom (`ai:` short PursueTarget, ~10 s MoveAwayFromTarget), no
  ReturnToUnit after spawning high; tailed they run and reverse, never turn with you. BANDITS HIGH once a round.
- Wolf flights: the odd planes hold (`roles: <unit> (wolf) trap N s after its orders: held B, D`), follow their lead; the
  bait drags you when tailed; a held plane you hit, or whose bait goes down, is freed (`trap freed (...)`); their guns
  lead you.
- Skirmishers: a LAAM from 5-7 km, `ai:` MoveAwayFromTarget right after the shot; LONG-RANGE SHOOTERS once a round;
  x0.75 health (`late: ... (skirm x0.75)`).
- `weapons: ... _SV_WOLF (... leads 0.50 s)`, `... NPC_FCS_PlaneLAAM000_SV_SKIRM ...` at the main menu.

**P2 squad director (unit 6)**
- `director: round N's budgets (from round X): ...`; each tactic's `director: round R +T s: <tactic> on <unit> ...;
  callout "..."` and its action line: cover (`director: cover: RE_SV_AceTurn_NN fired` after "Someone cover me!" / BANDIT
  CUTTING IN), trap (IT'S A TRAP, `roles: ... trap freed (the director's spring ...), turned onto the player`), bracket
  (MISSILES FROM TWO SIDES, `director: bracket: RE_SV_Salvo_..A fired, ...`, two missile alerts), top cover (`... held at
  engagement None ...`, then BANDIT DIVING / HIGH, n O'CLOCK and `back in the fight`), pincer (TWO GROUPS INBOUND, `director:
  pincer: wave N's K fighter flights from two sides ...`), regroup (BANDITS REGROUPING, `breaks off for 7 s`).
- The kill bonus: `credits: ... director <tactic> x1.5` on your kill of a tagged plane within 20 s.
- The round line's `director tactics N (...; M callouts)`: the thesis' 3-6 a round, each with a callout.
- `perf: ...` director worst under ~3 ms with 26+ up.

**P3 tells (unit 4)**
- `tell: <id>: RE_SV_Radio<X> (fired), tell callout '<TEXT>'` before each told threat: an ace's reversal / kulbit
  (ACE REVERSAL a second before the turn), the Reaper hunt, raids, the jammer, late waves (26+), the ALICORN's railgun
  (5 s early, RAILGUN WARNING, off ~12 s after), its dive / surfacing / VLS, a Ladon's volley, and every P1 / P2 / P7 /
  P9 tell. A test build's Ctrl+0 walks every catalog line (`test: Ctrl+0, tell line N of M: ...`).
- Refusals are logged once a round: `tell: <id> not said (<why>)`. Repeats within 20 s skipped? (line_gap_s).
- Co-op: a joiner hears its own copy ("tl"), never an RE_SV_Radio in its `ev` lines.

**P4 intensity director (unit 7)**
- `intensity: round N: you I (damage ..., N missiles on you, N enemies within 5 km, health ...), comfort C (...)` every
  10 s; does it match what happened (the missile count while the alert sounds)?
- Pressed down to the wave gate: `intensity: round N: held S s (...): wave W waits` and `round N: wave W waits for the
  intensity hold`, the wave 15-20 s later; never twice within 20 s.
- Comfortable 20 s: `intensity: you comfortable 20 s ...: <unit> turns onto you` (or a held top cover dives), its kill
  `director push x1.5`.
- Pressed 30 s from round 15: `the room above 80 for 30 s ...: enemies from now fly difficulty level L`, `level L on the
  enemies up`, and back after 60 s calm; from round 26 with it `pressure: ... preset B (was C, the intensity director's
  level down ...)`.

**P5 a harder tailed plane (unit 2)**
- `provoke: round 7, spike level 0, Veteran (...): was ... 85.0 ... 2.5; now ... 60 ... 1.5; reads back 60.0, 1.5`.
- `tailed: ... Provoke after X s ...; died Y s after` episodes; the round line's `tail watch: ...`; the run line's
  `tail watch Veteran+: died after median ... [8 s+]` (the P5 gate).
- The A/B: round 7 with `[ai] tier_provoke = false` (restart) against the default: stats_report's "Provoke after" by the
  provoke in force (fresh episodes only).
- Under 50 m behind one: the decel overshoot; farther out, a break, never a 300 km/h crawl.

**P6 the learning layer (unit 8)**
- `learning: profile at the main menu: ...` / `at level load ...`; each round's `learning: round N: habits ... ->
  <counters>`; `learning: run over (...): ...; learnt from` and config\survival_profile.ini written.
- Fly to a habit (missiles only, guns close, tails, high, the airfield) and see its counter: the jammer and PilotRank
  (`tiers:`), `the AI's flares refilled this session` (next game start), post-stall on Regulars, the director's `cover
  and trap x1.xx` / `top cover x1.xx`, more Lancers above you, the strike package and Skirmishers.

**P7 boss phases (unit 9)**
- MINDRIPPER: in its field THE PACK SPRINGS, then `special: MINDRIPPER's pack sprung (N): PHANTASM loose on you`; out
  of the field `... pack held ...`.
- AB.L..IN: after two frenzies IT'S ON YOUR SIX and `blink N behind you`; at 35 % ITS ECM IS DOWN, `ECM pods off`, `guns
  all out`, `LastTGT`.
- Ladons: one down: `<NAME> ENRAGED`, `special: Ladon X enraged (Y down): volleys every 25 s, the rage circuit from its
  next pass`, the tighter circuit on the minimap.
- ALICORN: PLANES LAUNCHING, `special: the Alicorn's deck launch N: <unit> (skirm), 2 aircraft at 1200 m`.
- The round line's special length against the thesis' 5-8 min.

**P8 late rounds (unit 3)**
- START AT ROUND 30 / 35: `round 35: 60 aircraft: ... ; cap 60, up to 26 at once` (Standard), the waves at 4 left; `late:
  ... health x1.50`; `pressure: round 26: preset C (was B)`, `round 31: preset D`; a boss round's `... again once it's
  down`.
- Frame time with 26-30 up: the `perf:` lines; the throttle A/B ([late.pressure] enabled = false) by time to kill and
  damage at death.

**P9 ace personalities (unit 10)**
- Ace rounds (16, 19, 22, 25, 28, ...; START AT ROUND, or a test build's Ctrl+6 for a Harvest flight): `roles: round N
  (the <Squadron> squadron's roles: ...)` and each squadron flight's `aces: <unit> (<Squadron> squadron, <role>) opens
  with <op> at first contact (within N km)`.
- Recognisable within 10 s of meeting each one (the thesis' gate), its tell first:
  - Bounty: BOUNTY: FROM ABOVE and "right above you!", then two missiles from above (`opening salvo: RE_SV_Salvo_..
    fired`, two missile alerts); Lancers' slash and zoom after.
  - Valkyrie: VALKYRIE: THE PACK and a lure line; half the pack hangs back (`trap ... held B, D, F`), 8 s on IT'S A TRAP
    and they turn in on you (`trap freed (Valkyrie's trap springs): ..., turned onto the player`). Held until it meets
    you however long that takes (no `trap freed (held 60 s)` first); do its held planes keep formation that long?
  - Inferno: INFERNO: POST-STALL ACES at 2.5 km, then the whole flight kulbits (`kulbits as one: RE_SV_AceKulbit_NN
    fired`; `ai:` UniqueAction).
  - Wraith: WRAITH: THEY BLINK, then its lead appears 1 km behind and beside you in smoke (`blinks (its opener): your
    heading H -> spot D deg`); sit on that lead's tail: IT BLINKED and it jumps again (`blinks (you N m on its six ...)`),
    not more than every 20 s; hit it: again.
  - Harvest: THE HARVEST, then its flights open with a kulbit, a blink or a missile pair in turn; tail its lead: a blink,
    tail a wingman: a reversal. No reversal in the same second as an opener (`ace reversal` lines only after it).
- The blink lands near the spot (`special:`-style check by eye: 1 km off, behind your wing), never into terrain at low
  level (`didn't blink ... no spot clear of the ground`), and the lead keeps fighting after it (no ReturnToUnit).
- The round line's `squadron openers N, blinks M`; stats_report's `squadron lines`.
- Co-op: a joiner who meets a squadron first gets its tell (`tell: mercenary_in (the host's)...` on the joiner) and a
  Bounty salvo from its own copies (`coop: director RE_SV_Salvo_.. fired here`); no blink round the joiner (`... blink is
  round the host's plane only`).
- Off: [aces.personality] enabled = false: no `opens with` lines, `roles: round 16 (an ace round's mix ...)`.

**Co-op, every unit (COOP_TAG -coop.18 on every game)**
- Every game on the same tag, linked; a joiner's `ev` lines never carry a kept event (RE_SV_Radio, RE_SV_Salvo_,
  RE_SV_WolfTurn, RE_SV_AnomalyPack, RE_SV_WraithBlink); its "tl" / "dv" lines arrive with the host's tells and salvos;
  the host's `intensity:` lines list each joiner's "in"; "rnd" carries the level and AB.L..IN's phase.
