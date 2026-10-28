# The behaviour director: P1-P9 on TestBranch_Behavioural

The Claude Docs thesis "AC8 Survival Mode: Enemy Behaviour Reference & Challenge Thesis" proposes nine changes (P1-P9)
that make Survival's enemies ask the player new questions instead of only getting tougher: fighter roles (P1), a squad
director (P2), tells for every coordinated threat (P3), an intensity director (P4), a harder tailed plane (P5), a
learning layer (P6), boss phases (P7), late rounds (P8) and ace personalities (P9). They are built on branch
`TestBranch_Behavioural` (from tag `stable-1`) one unit at a time. Each unit adds a section here: what was built, its
CFG keys, the log lines a test should look for, and what is untested.

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
| `KILL.geom(p, you)` | sv_ai.lua | a kill's aspect, range, height and your last 6 s of shots from ONE moment (the plane's own last sample, `p.youAt`), plus the weapon kind that dropped last; the `kill:` line now comes from it |
| `creditKill` returns its side | sv_main.lua | "you", "allies", "ships", "defences", "airstrike" ("wingmate" in co-op); nil for a Ladon |
| `playerOnAirfield(you)` | sv_rounds.lua | takes a position already read (optional; callers without one are unchanged) |

### The seven metrics and where each comes from
| metric (thesis target) | measured as | log line |
|---|---|---|
| time to kill an ordinary fighter, rounds 7-12 (20-40 s) | death minus the first sweep sample within `engage_km` (also since spawn, since your first hit); only your kills of pool fighters that aren't bombers, ace squadrons (`p.ace`, else `D.aceSquad`, so a plane the sweep never saw alive too), the jammer (`p.jammer`, else an EA-18G in a flight the jammer led) or probes. A co-op joiner can't tell aces and the jammer from ordinary fighters (only the host's spawner knows), so its pool-fighter kills are "ordinary ?" and left out | `kill-time:` per kill; round line median; run line "time to kill rounds 7-12" |
| a tailed enemy's survival (8 s+ at Veteran) | AI: the first Provoke / EscapeFromPursuer sample to death (AttackAvoidance, Blackout, UniqueAction keep it open; anything else is an escape). Geometric: you within `tail_km` and `tail_deg` of its six (the reversal test) to death | `kill-time:` "tailed X (AI Provoke Y)"; round line medians with died / escaped counts; run line "Veteran+" |
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
kept) [V].

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
| the tail watch | sv_stats.lua `STATS.tailTick` (sv_main.lua probeTick, every 250 ms, timed "tail watch"), `tailEnd`, `tailCut`; sv_ai.lua's `AI_STATE` now a global | the host or solo (a joiner's enemies are the host's). The enemies with a skill tier (no bombers) within `watch_km` of you by the sweep's last sample, at most `watch_max` a tick, are read afresh: position and heading. Those you're likely behind come first (the sweep's `p.tailing`, or the sweep's last pose of the plane against your position now: plain maths, no read), then the nearest, so in a furball a plane you chase at 2.5 km isn't crowded out by four nearer ones. You within `tail_km` / `tail_deg` of a live one's six (the sweep's own test; its HealthInternal is read before an episode opens, so a wreck the 2 s sweep hasn't marked down never opens one) opens an episode (p.tw): its provoke values in force are read (Survival's write or the game's row), then every tick its AI state (Provoke / EscapeFromPursuer / AttackAvoidance / Blackout / UniqueAction / other, timed). A plane already in Provoke, EscapeFromPursuer or Blackout at the episode's first read was defending before you got there (another pursuer, or you closed from beyond `tail_km` inside its provoke cone): "already defending", kept out of "Provoke after" and "after its Provoke" (its Provoke began before t0) and counted apart. It ends when the plane dies (the watch's own check, or the sweep's death first: STATS.down), once you've been off its tail `watch_grace_s` (escaped), or when the run ends with it open (STATS.runEnd, before the last round's line: "still up"); an escape or still-up under 1 s held is a flicker at the cone's edge, dropped. Up to 16 property reads a tick at watch_max 4 (one more as an episode opens) |
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
  (none in X, already defending Y), blackouts B [8 s+]`.
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
   fixes was checked to fail its case when undone (a scratch copy with the fix reverted).

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
| the attack throttle | tools/survival_events.py `PRESSURE`, build_anomaly; sv_config.lua `TIER.pressure(round)`, `TIER.PRESSURE_PRESETS`; sv_rounds.lua `roundPressure` | four remote events RE_SV_Pressure<A..D>, each the three records attack() writes (LiveSetPlayerMaxAttackerMissiles, LiveChangePlayerMaxAttackersNumExecution, LivePlayerAttackCooldownOverrideExecution), built inside build_anomaly where attack() lives (the critic's correction): A 2 missiles / 3 attackers / 8-12-20-25 s (a lull, for P4), B = ATTACK_BASE 4 / 6 / 4-8-15-20 (the mission start's), C 6 / 8 / 2-4-8-12, D 8 / 10 / 1-2-5-8. TIER.pressure: the preset of the latest [late.pressure] from_round band the round is in, B before them, nil when [late] or [late.pressure] is off. startRound fires it (after the waves are made) when it differs from the one in force, D.pressure, and in a run's first round whatever it is (D.pressure nil: not known; a restart keeps the level and an earlier run's C or D, review issue 1), never in an Anomaly or VALKA round (TIER.PRESSURE_OWN: their records set ANOMALY_ATTACK and put ATTACK_BASE back at their end: D.pressure is set to B there, and `pressureAfterBoss` (sv_rounds.lua, every roundsTick on the host) fires the band's preset 3 s after Lua sees the boss down, the critic's "fire it again after those specials end"; or the next round does). A failed fire leaves D.pressure as it was, so the next round tries again. The build checks Lua's letters and presets against PRESSURE (build_anomaly asserts). D.pressure is the dial the intensity director (P4) would turn too |
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
  saw it down, the next round's `pressure: round 29: preset C (was B)`); a failure
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
   round 30 (never seen down: D at 31), a failed fire kept and fired the next round (a failed first round too),
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
