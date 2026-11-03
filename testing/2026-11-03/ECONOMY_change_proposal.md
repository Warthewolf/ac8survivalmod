# Survival COOP: Economy Change Proposal

Nov 3, 2026 · @War

Fix two money bugs, split special rewards between players, and price tactical items by the round. Replayed on the logs, that cuts a long co-op run's income by about 40% (Shake Shack's 46 rounds: 1.04M to 0.65M for the host, 1.14M to 0.68M for mobi118), mostly from the round 13 Spaceport windfall and from kills joiners were paid for but didn't make, and it brings the host and the joiners level. Shorter runs change by 13-27%, and solo play only through the late-round prices (C4-C6). Approved on 3 November with the recommended answers (Decisions, below). It gets built once the 0.73.76 source is pushed.

## What the logs show

Every log sent in this conversation, split into runs: 11 player logs, 13 runs, rounds 1 to 46. Money comes from kills, round bonuses (250 x the round) and special rewards, times the host's pay setting (Pay %: 100 in Shake Shack's runs, 125 in Saint Alessia's, 200 in gloom's).

| Player (role) | Rounds | Players | Pay | Earned | Spent | Peak balance | End balance | Tactical share of spending |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mobi118 (joiner) | 5-46 | 3-5 | 100% | 1,137,260 | 902,460 | 445,930 | 245,950 | 62% |
| Shake Shack (host) | 1-46 | 2-5 | 100% | 1,043,950 | 986,020 | 192,900 | 58,930 | 56% |
| dukka (joiner) | 6-28 | 2 | 200% | 577,740 | 403,110 | 222,870 | 174,630 | 46% |
| Saint Alessia (host) | 1-18 | 2-4 | 125% | 243,978 | 197,440 | 82,357 | 51,538 | 0% |
| liljojofett (joiner) | 41-46 | 3-5 | 100% | 219,350 | 108,510 | 111,840 | 111,840 | 6% |
| cressendo (joiner) | 1-12 | 3-4 | 125% | 106,563 | 108,890 | 33,619 | 2,673 | 11% |
| Saint Alessia (host) | 1-7 | 2-3 | 125% | 39,315 | 16,700 | 22,615 | 22,615 | 0% |
| Shazzy (joiner) | 1-7 | 2-3 | 125% | 33,047 | 31,930 | 14,601 | 1,117 | 0% |

The short runs (rounds 1-6) behave: players are short of money, spend most of it on ammo, a first upgrade or an ally, and hit "NOT ENOUGH ZOLLARS" now and then. Saint Alessia's 18-round run is the healthiest long one: her balance never passed 82k and she kept buying defences, upgrades and revives. The 46-round run is where it breaks: from round 13 every player had more money than the STORE could use, and the top spend was tactical items. Across all runs the most bought items were airstrikes (95, 570,000 Z), rearms (80, 457,270 Z), SECOND CHANCE (7, 350,000 Z) and ECM bursts (61, 244,000 Z).

## The problems

Two are bugs, two are design. In order of how much money they put into a run:

1. **Joiners are paid full price for every kill (bug).** The design says a teammate's kill pays you half (`ally_x` 0.5). The host gets that right. But on a joiner's game a kill only counts as a teammate's when the damage came from an AI stand-in, and in COOP2MP every player flies a real plane, so every kill a joiner sees is paid as their own. mobi118: 1,473 kills paid as his, 0 as a teammate's, and in half of them (229,330 Z) he had fired nothing in the 6 s before. Same for dukka (0 teammate kills) and liljojofett (0). It only worked in Saint Alessia's runs, where her modded Falken flew as an AI stand-in. The more players, the more each joiner earns, and joiners outearn their host.
2. **The Spaceport fleet pays per part, not per ship (bug).** `sv_spaceport.lua` pays a ship's price times the drop in its unit's live objects, and an Aegis's unit holds the hull and its turrets. Aegis sinkings paid 2,400 to 12,000 each (11 of 17 paid the 12,000 maximum), and the Ford 18,000 and 27,000. The fleet paid each player about 242,000, about four times its price list; round 13 alone gave the host 269k and mobi118 263k, as much as 15-20 ordinary rounds.
3. **Every special pays its whole reward to every player (design).** VALKA's 16,500, MINDRIPPER's 19,100, the Alicorn's 28,800 and the Spaceport's rewards went to each of up to 5 players in full. In co-op, a special puts N times its reward into the run.
4. **Late rounds have nothing to spend on but flat-priced tactical items (design).** All four upgrades together cost 76,000, and the long-run players had all 11 tiers by round 15-16 (mobi118, dukka) or 27 (Shake Shack). After that, airstrikes (6,000, each up to 6 kills that pay half back), ECM bursts and decoys (4,000) stay the same price at round 45 as at round 5. They took 46-62% of the long runs' spending and made late rounds short; meanwhile mobi118 sat on 250-445k from round 13 to the end.

What isn't a problem: the early rounds (tight, with real choices), the escalating prices of allies, defences and revives (x1.12 to x1.25 a purchase), round bonuses, and SECOND CHANCE at 50,000, which works as the late sink it was meant to be (7 bought). The host's Pay % (100 to 200) and starting zollars (0 to 5,000) are the host's choice and stay that way.

## The changes

C1 and C2 fix the bugs and come first; C3 to C6 are the balance changes. Every number is a config value players can still change in `survival.ini`.

| # | What | Now | Proposed | Why |
| --- | --- | --- | --- | --- |
| C1 | A teammate's kill, on every game | Host: x0.5. Joiners: x1 (bug) | The host names the killer in each kill message; every game pays its own kills x1 and a teammate's x min(0.5, 1 / (players - 1)): 0.5 with 2-3 players, 0.33 with 4, 0.25 with 5, 0.2 with 6 | The design's rule, made true on joiners; your teammates' kills add at most about one more "you" however many there are |
| C2 | Spaceport fleet pay | Price x the ship's live parts lost (up to 5x) | Price once per ship, when its hull goes; a turret shot off alone pays the landing-craft rate (150) | The price list as written: about 64,000 for the whole fleet at round 13 instead of 242,000 |
| C3 | Special rewards in co-op | Each player gets the full reward | Each player gets reward / sqrt(players): 71% with 2, 58% with 3, 50% with 4, 45% with 5 | A boss is still the biggest payday of its round, but the run's total grows with the square root of the players, not with their number |
| C4 | Airstrike | 6,000 flat; its kills pay x0.5 | 4,000 + 300 x the round (5,500 at round 5, 10,000 at 20, 17,500 at 45); its kills pay x0.25 | It stays a good buy early and a real choice late; it stops paying for itself |
| C5 | ECM burst, decoy | 4,000 flat | 2,500 + 200 x the round (3,500 at 5, 6,500 at 20, 11,500 at 45) | Same as airstrikes |
| C6 | Revive | 2,500, x1.25 per revive in the run | 2,000 + 150 x the round, x1.25 per revive in the run (first revive 3,500 at round 10, 6,500 at 30) | Late revives were 3-5% of a balance; this keeps them a decision |

Not changed: kill pay by tier and round, round bonuses, special\_x 2.0, upgrade, ally and defence prices, SECOND CHANCE, ammo, repairs, the host's Pay % and starting zollars. A fourth upgrade tier waits for the test (Decisions, below).

## What the change does to a run

&#91;embedded content: Shake Shack's and mobi118's AC8SurvivalMode\_lua.log, 2026-11-02 · income replayed on the proposed rules (C1-C3)\]

Replayed on the same logs (income only; players would spend differently on new prices):

| Player (role) | Rounds | Pay | Income now | Proposed | Change | Biggest cut |
| --- | --- | --- | --- | --- | --- | --- |
| mobi118 (joiner) | 5-46 | 100% | 1,137,260 | 678,687 | -40% | Specials 372,860 to 96,890; kills he didn't make 229,330 to 60,726 |
| Shake Shack (host) | 1-46 | 100% | 1,043,950 | 653,631 | -37% | Specials 385,940 to 102,739; teammates' kills 212,620 to 118,306 |
| cressendo (joiner) | 1-12 | 125% | 106,563 | 77,933 | -27% | Specials 36,750 to 18,375 |
| liljojofett (joiner) | 41-46 | 100% | 219,350 | 178,400 | -19% | Teammates' kills 36,000 to 13,600 |
| Saint Alessia (host) | 1-18 | 125% | 243,978 | 197,021 | -19% | Specials 88,750 to 48,397 |
| dukka (joiner) | 6-28 | 200% | 577,740 | 504,278 | -13% | Specials 134,660 to 95,218 |

Your own kills and the round bonuses don't change for anyone, so solo play and the early rounds are untouched. The host and the joiners end up level (654k and 679k in the long run, where mobi118 outearned his host before). On C4 and C5, the airstrikes, ECM bursts and decoys Shake Shack bought in that run would have cost 975,000 instead of 456,000, more than his new income: he'd have bought about half as many, which is the point. An airstrike at round 30 costs 13,000, a bit under one round's income there.

## How we check it in game

One co-op session of 3-4 players to round 25 or later, with the pay audit on, then the same report run over every player's log (the scripts used for this proposal go into `tools/checks` as `economy_report.py`).

| Check | Target | Where it shows |
| --- | --- | --- |
| Joiners paid for their own kills only | 90% or more of a joiner's "by you" kills had a shot of theirs in the 6 s before | `kill:` and `credits:` lines; new `by player N` credits |
| Host and joiners level | Each player's income within 20% of the host's | the report's income per player |
| The Spaceport fleet | One `sunk` line per ship, an Aegis 2,400 at round 13; the round pays each player under about 50,000 with 4 players | `credits: ... the spaceport's fleet` |
| Specials split | Each reward x 1 / sqrt(players) | `credits: ... VALKA down` and the others |
| Balances | Under 150,000 through round 30 (Saint Alessia's 18-round run peaked at 82,000) | the report's peak balance |
| Tactical items | Under 40% of spending (46-62% in the long runs now) | the report's spending by kind |
| Money still matters | At least one NOT ENOUGH ZOLLARS per player in rounds 20-30 | `shop: ...: NOT ENOUGH ZOLLARS` |

## Decisions (3 November)

1. **The team share (C1): min(0.5, 1 / (players - 1)).** Half a kill with 2-3 players, then less, so teammates' kills add about one more "you" however big the room is.
2. **Special rewards (C3): the reward / sqrt(players) each.** A boss stays its round's biggest payday. Full rewards for everyone would have left the long run 17-19% richer.
3. **No fourth upgrade tier for now.** It adds power. It's reconsidered after the test only if balances still pile up past round 30 (the balances check above).
4. **Airstrike payback (C4): x0.25.** It stays an attack that pays a little back, not a panic button that pays nothing.
5. **Solo and the leaderboard.** C1-C3 only touch co-op; C4-C6 make late solo rounds dearer too, so the build that carries them is registered on the leaderboard as a new version. That waits until the admin key is at hand.
6. **0.73.76's own numbers.** This proposal uses the config from 0.73.58 on GitHub plus the prices 0.73.76 logged (they agree on every price seen). Every value gets checked against 0.73.76's `sv_config.lua` once it's pushed, before anything changes.
