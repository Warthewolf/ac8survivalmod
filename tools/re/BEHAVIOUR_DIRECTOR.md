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
| the spawn index's check | sv_core.lua leadCheck, sv_spawn.lua `D.leadRow` | a flight whose lead got its own row (an ace's, the jammer's EA-18G) logs once which airframe k 0 and k 1 fly and whether k 0 is the lead |
| `COOP.players()`, `COOP.me()`, `COOP.slotOfAddr(addr)` | sv_coop.lua | the players for the director: `{ slot, obj, addr, at, hpPct, alive, onAirfield, fresh }`, you first (pawn position read once a tick, keyed on D.now; health from HIT.h, full health every 5 s), then each other player from what peerTick already keeps of SV_CoopPeerAt (no new native call; non-finite states left out). Solo: only you, slot 0. slotOfAddr: your pawn or a stand-in to its slot |
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
| time to kill an ordinary fighter, rounds 7-12 (20-40 s) | death minus the first sweep sample within `engage_km` (also since spawn, since your first hit); only your kills of pool fighters that aren't bombers, ace squadrons, the jammer or probes | `kill-time:` per kill; round line median; run line "time to kill rounds 7-12" |
| a tailed enemy's survival (8 s+ at Veteran) | AI: the first Provoke / EscapeFromPursuer sample to death (AttackAvoidance, Blackout, UniqueAction keep it open; anything else is an escape). Geometric: you within `tail_km` and `tail_deg` of its six (the reversal test) to death | `kill-time:` "tailed X (AI Provoke Y)"; round line medians with died / escaped counts; run line "Veteran+" |
| special round length (5-8 min) | the round's length on the game clock (and time down at the airfield), next to the special's own LB.special seconds | round line "(<tier>, <kind> S s)" and "length"; run line "specials", "special rounds" |
| missiles left at death (under 40) | A.caps[1] (the count held), else the last ammo read | `death:`; run line "missiles left at the end" |
| damage sources at death (varied) | each drop of your HealthInternal classed at the tick it happens: "missile" (an enemy missile within 800 m seen in the last 0.6 s, the HIT log's test; one homing on someone else skipped), "gun/close" (no missile, an enemy within `gun_km`), "unknown"; a bracket = missiles of two shooters within `bracket_km` in the last second | `death:` (last `death_window_s`: shares, hits, shooters, brackets, top shooters); round line "you took"; run line "damage taken" |
| director tactics per round (3-6, each with a callout) | STATS.tactic's count per round, callouts counted | `director:` per tactic; round line "director tactics"; run line "per round avg" |
| share of kills from behind (under 70 %) | your kills whose aspect is at least 180 - `tail_deg` off the enemy's nose within `tail_km` | round line "kills from behind b/k"; run line |

Fired counts (missiles, specials, flares from the capped counts' drops in the air; the gun from its count's drops
between the 2 s refills) go into the round, death and run lines.

### CFG keys (CFG.stats; `[stats]` in survival.ini; PERSONAL in co-op, so a host never changes a joiner's)
`enabled` (true), `kill_lines` (true: the per-kill line), `engage_km` 5.0, `tail_km` 3.0, `tail_deg` 70, `close_km` 1.2,
`bracket_km` 1.5, `gun_km` 1.5, `death_window_s` 30, `ttk_from_round` 7, `ttk_to_round` 12.
STATS.tactic tags planes whether or not `enabled` is on (later units' kill bonus reads the tag).

### Log lines to look for in a test
- `round probe: AI aircraft created #N: BP_OP..._su47_... (ERA_Unit_03_Dep_Air1, k 2) at ...`: every pool / bomber plane
  has its k.
- `spawn index: ERA_Unit_03_Dep_Air1, lead row e18g_common_sv (e18g): k 0 is a e18g, k 1 a su47; k 0 is the lead:
  creation order = desc order`. This is THE check for `p.k`: look for it on a jammer flight (round 8+, its lead is an
  EA-18G, unlike its wingmen) or an ace squadron. "k 0 is NOT the lead" means the per-plane events of later units would
  hit the wrong plane; "can't tell" comes when lead and wing fly the same type (ace squadrons often do).
- `kill-time: BP_OP... (ERA_Unit_.., Veteran, round 8, k 1, ordinary): up 61 s, engaged 23 s (within 5 km), since your
  first hit 9 s, tailed 6 s (AI Provoke 4 s); 172 deg off its nose at 0.9 km, +0.2 km; by you[, director <tactic> N s before]`
- `stats: round 8 (Veteran, normal, 1 player): length 312 s (24 s at the airfield), 2 waves; aircraft down ...` a few
  seconds after `round 8 clear` (the sweep sees the last kills up to 2 s after the spawner does). A run that ends mid
  round logs it "(cut short: died)".
- `death: round 23 (died), 140 s into the round: last 30 s -260 HP: missiles 70% (5 hits from 3 shooters, 1 brackets),
  gun/close 20%, unknown 10%; top: ...; missiles left 148 (fired ...), specials a/b, flares c`; "(saved by SECOND CHANCE)"
  when the floor caught you.
- `stats: run over (died): rounds 1-23; time to kill rounds 7-12 median ... [target 20-40 s]; ...` once per run, before
  the `leaderboard: run over` line.
- `director: round 8 +95 s: <tactic> on <unit> (2 planes)[, player N] (<why>); callout "..."` (from unit 2 on).
- `perf: ... parts avg/worst ms: planes x/y, moves x/y, ...`.

### Offline test
`sh tools/checks/stats_test.sh` (tools/checks/stats_test.lua) runs the real sv_core, sv_config, sv_ai, sv_spawn,
sv_stats and sv_coop with the game stubbed: spawnFlight's planes get k 0..n in creation order and the check names the
jammer's EA-18G at k 0 (and catches a spawner that makes the lead last); a round of planes with known engage / hit / tail
/ Provoke times gives the expected kill-time line, round line (with a kill seen after the clear), death line and run
line; STATS.tactic's tag and count; COOP.players solo, as a host (another player's state, a stale one, a broken one) and
COOP.slotOfAddr; ACE.movesTick fires solo and not on a joiner; a joiner's rounds from the host's round messages [V].

### Untested / known limits
- [I] creation order = AIObjectDesc order (`p.k` 0 = desc 0, where SV_SetAircraft(unit, row, 0) puts the lead): the
  `spawn index:` line in the first test with a jammer or ace flight confirms or refutes it.
- Every time is good to about +/- 2 s (each plane is seen every 2 s; deaths are seen up to 2 s late). Provokes shorter
  than 2 s can be missed. AI Provoke is not measured on co-op joiners (their copies' AI isn't theirs); the geometric tail
  is.
- Damage is HealthInternal only: the player's armour pool (KILLS_HEALTH_DEATH.md) drains first and isn't seen. A gun,
  the Ladons' pulse cannons and a collision within `gun_km` all read "gun/close"; a SAM blast or the railgun "unknown".
  Allied missiles homing on someone else are skipped only while they still exist (one that hit is gone).
- "Weapons" are your shots in the last 6 s at anything, not at that plane; the weapon is the kind that dropped last.
- A game crash logs no run line (LB.finish never runs). A joiner's round kind is "?" (the host's special isn't sent).
- COOP.players' other players come from SV_CoopPeerAt as peerTick reads it (up to a tick old); `fresh` is under 1 s.
