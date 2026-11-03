# Session of 2026-11-03: hand-off

A cloud Claude Code session reviewed the co-op test logs and crash reports of 0.73.76-coop2mp.77 (runtime 0.32.21)
and wrote three plans. Nothing in them is built yet. This folder holds copies of the plans and the analysis scripts,
so a local Claude Code session can pick up the work without the Claude Docs connector.

Read AGENTS.md first, then these, in this order:

| File | What it is | Live doc (may be newer) |
| --- | --- | --- |
| `PLAN_desync_lag_compatibility.md` | The 1.0.0 plan: workstreams A-J, test sessions, order of work | https://claude.ai/artifact/7xheJLupYvrAUYCPMJnmzR |
| `ECONOMY_change_proposal.md` | Economy changes C1-C6, approved 2026-11-03 | https://claude.ai/artifact/XsRMWUcQangTtxczjbqQAB |
| `IMPROVEMENTS.md` | Gameplay suggestions, the Spaceport review (S1-S14), tester feedback | https://claude.ai/artifact/5uNoYsWXN8AZjCUm2AN2YG |

The docs' charts and roadmap widgets aren't in the Markdown copies; open the live docs for those.

## Where things stand

- **The 0.73.76 source isn't on GitHub.** Everything was reviewed against 0.73.58 (`COOP2MP`) and the 0.73.70 tester
  zips in `testing/builds`. Push 0.73.76 (e.g. to `wip/0.73.76`) and check every finding and number against it before
  changing code (the plan's Step 0).
- **Nothing is committed but this folder.** The user wants each change shown before it's committed.

## Decided on 2026-11-03

- **Economy:** approved with the recommended answers: C1 team share min(0.5, 1 / (players - 1)); C3 specials pay
  reward / sqrt(players); C4 airstrike 4,000 + 300 x round, its kills x0.25; C5 ECM burst / decoy 2,500 + 200 x round;
  C6 revive 2,000 + 150 x round, x1.25 a revive; no fourth upgrade tier yet. C1 and C2 (joiners paid for every kill,
  the Spaceport fleet paid per part) are bugs.
- **Leaderboards (Workstream H):** wait until the user has the admin key at the PC. The new economy build is
  registered as a new version.
- **Balance from a 5-player tester (plan G4-G6, Improvements "Tester feedback"):** Harvest's planes have about 10,000 HP
  each (the campaign's named-ace bodies, `CP_Named` / `CP_Shadow`, ~7,000 x1.5 late), up to 80 a round; health per
  tier instead, smaller ace rounds, Harvest every other ace round. VOID WATCHER 1 lasted 92 minutes with a 25 km ESM
  field: 3 rounds of service, rising price, 8-10 km field, a strike flight after it. Airstrikes: one per player per
  round, never on ace squadron flights, at most 4 hit, no auto call.
- **VALKA's arrival flash (plan D5):** its lens flash elements are sized in screen fractions (Glare 1.6, Ring 1.2,
  Shine 0.9, Bokeh 0.4: `CFG.specials.valka.flare.elements`), so it fills the screen at 14 km. Halve them behind a new
  `[specials.valka] flash_size_x = 0.5`. Also: none of the three VALKA fights in the 0.73.76 logs logged her
  black-hole portal opening (`special: VALKA's portal at ...`); find out why.
- **Carrier and helicopters (plan J):** the Ford's own deck flights and higher launch numbers; helicopter troops need
  research first in `build/research` (a stock helicopter unit, Mission 26's carried-unit events).
- **Not to build (asked only whether it's possible):** a rocky island from AC8 Mission 25 north of Comona. Likely
  possible by streaming that map piece in with an offset; post-1.0 at the earliest. Fort Grays (AC7) is ruled out:
  stock AC8 files only.

## Root causes found (details in the plan)

- **Invisible enemies with target boxes (A):** joiners' copies get `SetMinHealth(0.1)`, which keeps whole points only
  (0.1 -> 0), and the host's "hp" message writes health back onto copies already dead here. Proposed in `sv_coop.lua`:
  bindCopy / bindGround set the floor with `o.MinHealth = 1.0` (fall back to `SetMinHealth(1)`); the "hp" handler
  skips a copy whose own health is 0; killCopy clears `o.MinHealth = 0.0` before `SetMinHealth(0.0)`.
- **Crash on quit (F1)** and **crash at the round 3 bomber raid (F2):** minidumps analysed with `tools/mdmp.py`.
- **Leftover boss parts** (Ladon VLS, VALKA's RGCK and opener railgun, the Alicorn's VLS / AA) hurting players rounds
  later; **run over while a player loads**; **the rejoin in another aircraft** (C).

## Scripts (`tools/`)

Run with `python3 -I`; each has its usage at the top.

| Script | Does |
| --- | --- |
| `mdmp.py` | Reads a crash minidump: exception, registers, modules (`--mods`), stack scan (`--scan N`) |
| `deep.py` | Full stack scan of the faulting thread plus code bytes |
| `econ.py` | Per run: income by source, spending by item, balances, NOT ENOUGH ZOLLARS |
| `replay.py` | Replays a run's income on the proposed economy rules |
| `phantom.py` | "By you" kills where the player fired nothing |
| `planes.py`, `stuck.py` | Copies' kills and takedowns against flights that never respawned |

## Still wanted

- scaraboy13's logs and gloom's host log (never received).
- The stock-data research for J2 (helicopters) and, after 1.0, the Mission 25 island.
