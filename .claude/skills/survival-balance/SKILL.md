---
name: survival-balance
description: Tune AC8 Survival Mode's difficulty and economy from evidence: player reviews, Nexus comments, friends' feedback and their logs, turned into CFG changes for specials, bosses, enemy scaling, prices, allies and airfield defences, solo vs co-op. Use this whenever the user shares feedback that something is too hard, too easy, unfair, overpowered, too expensive or pointless, asks to rebalance or tune a round or item, or asks what to change after a review, even if she doesn't say "balance".
---

# Survival balance

Balance changes are her design calls. The job is to turn feedback into evidence and options, then change values
only once she's picked.

## 1. Sort the feedback
Split each complaint into:
- **bugs** (something not working as written: an item that does nothing, a part untargetable but firing): not
  balance; check the code and logs (survival-log-triage) and fix them first, as they skew everything else;
- **tuning** (numbers: health, damage, counts, ranges, prices, timings);
- **design** (a mechanic the player dislikes: control inversion, teleports). Hers to keep or change; give options,
  don't change it unasked.
Note the player's setup: solo or co-op, preset (Casual / Standard / Ace / auto), rounds reached, version.

## 2. Find the numbers
- Each special's values: `CFG.specials.<key>` in `Scripts/sv_config_specials.lua` / `sv_config_arc.lua`, with the
  comments saying why each was set (often a test of hers: respect those reasons).
- Enemy scaling: `sv_ai.lua` (tiers, health, missiles), roles and the director (docs/re/BEHAVIOUR_DIRECTOR.md).
- Prices and raises: `CFG.shop`, `sv_shop.lua shopPrice`, `sv_ai.lua` raise; allies and defences in `sv_allies.lua`.
- Co-op scaling: `COOP.more`, per-player counts in each special's config.
- History: `grep -n "<special>" HISTORY.md` for past tuning and her decisions; never undo one of her calls silently.

## 3. Evidence from logs
`tools/log_report.py` over the logs gives each round's length, kind, kills and outcome. For a special, grep the Lua
log for its own lines (the hits on its parts, `stats: round N`, deaths with `STATS.death`'s cause). Compare solo and
co-op runs of the same special when there are both. Say how many runs the evidence comes from: one player's run is a
lead, not a verdict.

## 4. Propose
A short table per item: the complaint, the cause in the numbers, the change (old -> new value, or a new setting such
as solo scaling), and what it risks. Prefer:
- scaling by player count over one global cut (co-op stays as tuned);
- a setting (`enabled`, a multiplier in survival.ini) over a hard-coded change, so players can choose;
- changes in CFG values over code changes.
New ini settings go through `sv_config_ini.lua` and the leaderboard's `LB.edited` (gameplay settings mark a run edited).

## 5. After she picks
Change the values on a branch, run the special's Lua test and `lua_check.py`, note each change and its reason in the
config comment (dated, with the feedback it answers) and in HISTORY.md, then build with the survival-build skill.
