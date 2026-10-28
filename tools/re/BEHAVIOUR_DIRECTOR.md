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
| TELL | sv_tells.lua | `TELL.say(id, slot, a, b)` (slot nil: this game's player; TELL.ALL: every player; a number: that player, the host only, "tl"), `TELL.after(id, slot, fn, ...)` (the action lead_s after the tell, run by `TELL.tick` every 250 ms on the round clock; at once when not said; never with `need`), `TELL.leadS(id)` (0 with this game's tells off, unless it hosts co-op), `TELL.ready(id, slot)`, `TELL.play` (this game only: the joiner's "tl" and the test key end here), `TELL.known(id)`, `TELL.hunted(p)` (the hunt's trigger). Keeps hudCallout and SV_Event as they were before sv_coop.lua wraps them (the contract's exception): a tell never goes out again as the host's "co" callout or "ev" event |
| rate limiting | sv_tells.lua `classOf`, `wait` | each receiver (this game's player, each joiner the host sends to, "every joiner") on its own: an urgent tell urgent_gap_s (2.5) after the last urgent one; a tell with a queued callout gap_s (4, the banner's own time) after the last such; a radio-only one radio_gap_s (2) after any tell; each id its cooldown_s; none between rounds (a joiner plays the host's anyway: its mirrored state may lag), down at the airfield or over the run's summary. A radio line is never asked for again within line_gap_s (20 s, the cloned rows' RequeueingWaitTime) by whichever tell (`lineFree`, D.tells.evAt, set when its event fired): reversal and kulbit share their two lines, and an ace can kulbit 12 s after its reversal; a tell whose lines are all that recent shows its callout only, or isn't said (kind "line"). Refusals are logged once a round per tell and reason |
| the urgent callout | sv_hud.lua `hudCallout(text, sub, big, urgent)`, `calloutNext(now)` | an urgent callout (a tell's) goes in front of the queue, in place of a tell still waiting there (one waits at a time), a full queue (4) losing its last callout for it (logged); the next HUD tick puts it up at once, cutting the banner's callout short (put back right after the tell when more than 1.5 s of it was left, a full queue then losing its last, logged; a tell never cuts a tell), for CFG.tells.hud_s (2.5 s). Before, a callout could come up to 16 s late behind four round callouts (the brief). sv_coop's wrapper passes urgent on |
| co-op | sv_coop.lua `COOP.tell`, the joiner's "tl" handler, KEEP_EVENTS, PERSONAL | "tl" (id, a, b) from the host to a joiner's slot or to every joiner; the joiner plays it only if it knows the id (its own catalog), a / b are finite (or absent), its level is ready, [coop] callouts is on, and at most 4 came that second; dropped, never queued (a late tell misleads). `^RE_SV_Radio` is in KEEP_EVENTS (no "ev", and a joiner refuses one); `tells` is PERSONAL (each player's switches, texts and lines). CFG.tells.enabled is each game's own: a host with tells off still sends "tl" (TELL.say checks it only for its own TELL.play) and its leads stand (TELL.leadS); a joiner with tells off plays none. The host's gaps, cooldowns, leads, hunt_km and wave_from_round decide when a tell is sent |

Tells wired now (the threats that exist today):

| tell | when | where | to | shows | lead |
|---|---|---|---|---|---|
| reversal / kulbit | you on a move tier's (Reaper's) tail within 3 km / 70 deg (kulbit within 900 m) | sv_ai.lua ACE.movesTick (host / solo only) | you | "That's a sudden turn - coming straight at you!" or "He's mine!"; ACE REVERSAL / HE'S TURNING INTO YOU (ACE POST-STALL / DON'T OVERSHOOT), urgent | the move (RE_SV_AceTurn_NN / AceKulbit_NN) 1.0 s (0.5 s) after the tell (TELL.after); at once without a tell, as before |
| hunt | a hunting tier's flight (Reaper: ACE.hunt keeps its target on you) first within hunt_km 8 of you, once a flight a round | sv_ai.lua ACE.hunt -> TELL.hunted (not on a joiner) | you | "Hunt down the Wings of Theve ..." or "I see our prey."; YOU ARE BEING HUNTED / ACES CLOSING ON YOU (queued) | - |
| raid | a raid's, strike's or bombers' callout (the round's first bomber flight) | sv_spawn.lua spawnBomber | everyone | "Joker Flight, enemy aircraft approaching the eastern airfield." (Survival's airfield is Mission 22's eastern one) or two others; radio only (the round's callout stays) | - |
| jammer / jammer_down | the jammer up; shot down | sv_spawn.lua spawnFlight; sv_main.lua creditKill | everyone | "The enemy's jamming you with a powerful ECM." / "Hostile EW aircraft destroyed! Jamming has been lifted!"; radio only | - |
| wave | each later wave of a round from wave_from_round 26 (the late rounds' growth) | sv_rounds.lua roundsTick's wave branch | everyone | "New enemy aircraft detected. Look sharp!" or three others; radio only | - |
| alcn_rail_first / alcn_rail | lead_s 5 s before each railgun order (it fired without a warning before) | sv_alicorn.lua alicornTick | everyone | "Joker Flight, the railgun has been activated." the first time, then "Enemy railgun's ready to fire." / "Railguns are getting ready to fire!"; WARNING: RAILGUN / BUILD SPEED, THEN BREAK, urgent; with CFG.specials.alicorn.rail_alert the RAILGUN WARNING on (RE_SV_AlcnAlertOn) until alert_s 12 after the order, at a dive, when it sinks or when the run restarts (SPC.alicornCleanup, from sv_main.lua's level-load reset) | the order's time is unchanged; the warning comes earlier (the railgun then aims ~7 s and preps ~2 s: ALICORN.md) |
| alcn_dive / alcn_up | its dive; counted surfaced | sv_alicorn.lua | everyone | "Enemy submarine diving!" / "Submarine has surfaced. Begin attack!"; radio only (its callouts stay; not on each resurface order) | - |
| alcn_vls | its VLS volley | sv_alicorn.lua | everyone | "Missile launch from VLS!"; VLS LAUNCH / ALICORN MISSILES INBOUND, urgent | RE_SV_AlcnVolley 1.0 s after (not if it dived meanwhile) |
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
- `CFG.tells.cooldown_s` ([tells.cooldown_s]): reversal 20, kulbit 20, hunt 45, raid 30, jammer 30, jammer_down 10,
  wave 20, alcn_vls 30, ladon_vls 15 (and 0 for the ALICORN's other calls; the later units' set too).
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
   lead_s / alert_s. The VLS volley a second after its call.
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
   jammer_down, wave, TELL.tick and Ctrl+0 by their place in the source.
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
  (at once, as before). The hunt tell is the host's only (its planes hunt the host); a joiner hears none.
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
  `roles: off; every fighter flight flies the fighters' set, drawn as before`); then, before round 1,
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
  groups (the Wolf strike has its own Super; the Lancer pass and Skirmisher pass don't). P9 maps squadrons to roles.
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
   fighters' set counts) and ace squadrons in any flight keep their tier's levers; the hunt itself (TargetActor kept on
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
Host or solo only: on a co-op joiner DIR.tick does nothing of its own (P4's `DIR.clientTick` hooks in there later).
Lua, survival.default.ini and the build (tools/survival_events.py `build_director`: 134 new remote events). No COOP_TAG
or VERSION bump (the contract's single bump comes last), but the event package changed: that bump must come before any
co-op build goes out.

| tactic | when | tell first | what happens | lever | a joiner as the target |
|---|---|---|---|---|---|
| cover | a player on an enemy's tail (within cover.tail_km 3 / tail_deg 70 of its six) for tail_s 3 | `cover_ask` at ask_s 1.5 (the tailed one's radio "Someone cover me!"), then `six` (urgent: BANDIT CUTTING IN / CHECK YOUR SIX, lead 1 s) | the nearest plane of another pool flight within range_km 6 of that player turns its whole flight onto them; its next reversal no sooner than move_s 30 (D.aceMoveAt, shared with the aces' own) | RE_SV_AceTurn_NN (LastTGT by flight, confirmed 2026-10-23) | LastTGT would turn onto the host: RE_SV_Hunt_NN (AIFirst) and the flight's TargetActor kept on that player's stand-in for aim_s 20, then its orders back |
| trap | a player on a Wolf bait's tail (an even plane of a Wolf flight whose next plane is held: unit 5) for spring_s 2.5 | trap.warn (`drag`: HE'S DRAGGING YOU) at drag_s 1, then `trap` (urgent: IT'S A TRAP, lead 1 s) | that bait's own held wingman is freed and turned onto the player | WOLF.free(unit, why, true, k): RE_SV_WolfFree + RE_SV_WolfTurn_<NN><L> | freed without the turn, its TargetActor on the stand-in for aim_s |
| bracket | two enemies within bracket.range_km 4 of a player, their noses within nose_deg 60 of them, 60-120 deg apart around them (sep_deg) | `bracket` (urgent: MISSILES FROM TWO SIDES / BREAK NOW, lead 1 s) | each fires one missile at the player, in the same tick | RE_SV_Salvo_<NN><L> (new: Mission 19's LiveFireOneShotWeapon, WN_WEAPON_3 = fire-control slot 2, hard rule 40), only planes whose row has its missiles there (SR.mslSlot) | its own copies fire at it ("dv", the lead timed there) |
| top cover | a Lancer flight (top_cover.roles; roles off: any, any_without_roles) up, its orders in, hold_after_s 3 on | `dive` (urgent: BANDIT DIVING / HIGH, n O'CLOCK, lead 1 s, then the o'clock line) when it dives | held at engagement None until a player has fought another flight (within engage_km 3) for engaged_s 3 and it's been held min_s 8: then it dives on that player. Let go quietly at max_s 45, when hit, as the last flight up but held ones (any round state; not while a wave still spawns), or at the player's decoy's end (inside a decoy nothing of ours frees it) | RE_SV_DirHold_NN / RE_SV_DirFree_NN (new: the MOONCHILD hold / the appearance's orders, by flight; forwarded, so the joiners' copies hold too) | freed, then RE_SV_Hunt_NN with its TargetActor on the stand-in |
| pincer | a new wave (startRound's first, each later one) of 2+ fighter flights, not a special's or a raid's, with chance 0.6 | `pincer` (TWO GROUPS INBOUND / FROM THE x AND THE y) once both sides have a flight, to every player | its flights alternate on two compass bearings sep_deg 90-150 apart (spread_deg 10), solo around you ring_km 12-18 out (ahead: either side of your nose), in co-op around the airfield (CFG.distance_km); each nose on the centre | spawnFlight's point (spawnPoint with a centre; SV_Spawn's pose reaches the joiners in "sp") | the same for everyone: room news |
| regroup | a flight of min_size 4+ down to half its planes (this spawn's), after_s 10+ after it came up | `regroup` (BANDITS REGROUPING; "They're trying to regroup.") | breaks off (engagement None) for hold_s 7, then its orders back | RE_SV_DirHold_NN / DirFree_NN | the same (forwarded) |

"Its orders back" is RE_SV_DirFree_NN (air-only search, PlayerOnlyNoLimit, as its appearance's), plus RE_SV_Hunt_NN again
for a flight the co-op host had sent after the joiners (COOP.hunted) or one aimed at a joiner.

### What was built
| piece | where | what it does |
|---|---|---|
| the part | Scripts/sv_director.lua (`DIR`; 58 of 200 locals) | DIR.tick (4 Hz: who's on whose tail, who could bracket whom, at most one tactic started a tick; 1 Hz: aims, holds, the pincer's count, top cover's holds, regroups), DIR.roundStart, DIR.wave, DIR.spawnAt, DIR.spawned, DIR.holding, DIR.aimed, DIR.release (for P4), DIR.holds (a late joiner's replay), DIR.SALVO_FCS_SLOT 2. State in D.dir (a new level or run clears it), per plane p.dirTail (a tail episode) and p.pose |
| players | COOP.players() (sv_coop.lua; `rot` added for the others) | the targets: alive, flying, fresh; past [director] players (4) you and the others round-robin. The Offline edition (COOP nil): you from the pawn |
| perf | sv_director.lua fastTick | candidates from the 2 s sweep's p.at within near_km 6 of a player; fresh position + heading reads for at most reads 8 a tick, the planes likely tailed first (a tail episode open, the sweep's p.tailing, or its last pose against the player), then the nearest; the read kept in `p.pose`, which the tail watch (sv_stats.lua STATS.tailTick, run after it) reuses: one read a plane a tick between them. No FindAllOf, nameOf or StaticFindObject; decisions logged, never ticks |
| budgets | CFG.director.budget, cooldown_s, gap_s | per round by the band of the latest from_round reached (cover, trap and bracket each player's; top cover, pincer, regroup the room's); a tactic's cooldown; gap_s between any two the director starts (not the pincer, not top cover's hold). P6's hook: D.counter.tail (when P6's unit sets it) multiplies the cover and trap budgets and divides their cooldowns (the critic's gap fill (a)). A budget of 0 is silent |
| tells first | CFG.director.need_tell | a tactic waits until its tell can be said (TELL.ready: the tells' gaps, cooldowns, line_gap_s); this game's tells off ([tells] enabled = false), it goes without one, at once (TELL.after's own rule). The pincer's tell comes once both sides have a flight (you may be grounded as a round starts) |
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
  <plane>)`, `(its tell can't be said now)`; `director: top_cover not now (it's the only flight up (<unit>))`;
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
  / on a joiner / with no duelist in range (logged); tells off: at 3 s without a tell;
- the reads: 21 planes near you, 8 reads, the one you're likely on the tail of first; the tail watch reads nothing more;
- the trap: drag at 1 s, the trap tell at 2.5 s, its own wingman B freed and turned (D left held), no cover instead;
  nothing inside your decoy;
- the bracket: the tell, no shot in its lead, both shots 1 s on in one tick, both tagged; its budget; nothing at 30 or
  150 deg, with a nose away, a slot-3 row, a held flight, or no budget (and no log of it);
- top cover: the hold 3 s after its orders (not the duelists'), no dive under min_s, the dive with HIGH, 3 O'CLOCK and
  ClockC, DirFree after the lead, tagged; let go when hit, as the last flight, at max_s, at your decoy's end (DirFree
  then, none inside it; a dive's release inside a decoy waits for its end, DIR.release too); a held 6-ship as the wave's
  last in state "wave" let go at once (not while a wave's flight is queued); two held flights: one let go;
  no hold without budget; roles off with and without any_without_roles;
- the pincer: around you, either side of your nose; spawns alternating on the two bearings, 12-18 km out, noses on you;
  the spawn line; the tell once with both compass names; counted and 8 planes tagged once up; none for a special's wave,
  a raid's, one flight, no budget; co-op around the airfield; the zone's edge (logged, a normal spawn); one of 3 fallen
  back: 2 of 3 counted, its planes untagged; one side only: no tell, no tags, not counted, its budget back;
- regroup: nothing before after_s, the tell + DirHold at 10 s, held 7 s, DirFree; 3 of 4 left: none; the only flight
  up: none (logged);
- SR.mslSlot from the real searchSetup on fake tables (every level; a slot-3 row recorded and named in the line);
- co-op host: a joiner's bracket by "tl" + two "dv" with the 1 s lead, nothing fired here; KEEP_EVENTS; COOP.dispatch's
  refusals; a joiner's cover (the six tell to it only, RE_SV_Hunt_05, its TargetActor on the stand-in, ACE.hunt leaving
  it, its orders back after aim_s; a decoy on it ends the aim, its orders at the decoy's end); the split hunt waiting
  out a hold and going after it (COOP.hunted), a 120 s hold with max_s 600 waited out, a hunted flight's release firing
  its hunt again; a joiner linking during a hold gets RE_SV_DirHold_07 12 s later, none for one let go meanwhile;
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
