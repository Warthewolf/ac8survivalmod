# Enemy missiles and the other levers left (research 2026-11-06)

What still keeps Survival's enemies easier than they need to be, from AC8's own tables. Static analysis of the stock
tables in `build/stock/Datatables/AI/NPC` (read with `build/research/ai/dt.py`) and of Survival's Lua; nothing here is
tested in game yet. Proposed values are Survival's own, anchored on AC8's rows, to be tuned in play.

## 1. Where an enemy missile's behaviour lives
```
DT_NPC row (NpcFCSId0..5) -> DT_NPC_FCS row        when it fires: lock range / cone, arm, lock, shots, rest
                              -> NpcWeaponId -> DT_NPC_Weapon row   how the missile flies: lead, homing cone, turn rate,
                                                                    life, speed, cloud loss, damage
```
What Survival edits today (Scripts/sv_rows.lua):
| what | fire control (DT_NPC_FCS) | weapon (DT_NPC_Weapon) |
|---|---|---|
| fighters' missiles (CFG.missiles, CFG.spikes, MINDRIPPER) | copied and edited (`<row>_SV<level>`) | **never: every copy still points at the stock missile** |
| fighters' guns (CFG.guns, aces' gun lead) | copied and edited | copied: damage, spread, life |
| specials (CFG.special.fcs) | stock rows | stock rows |
| ship and defence missiles (sv_allies.lua allyFcs) | copied and edited | copied: life, speed, accel, turn_x, homing_from |

So every fighter's missile, aces' included, flies exactly like the stock one, however fast it's fired.

## 2. The stock enemy air-to-air missiles (DT_NPC_Weapon)
Lead = `HomingForesightAmount` (0: flies at where you are; higher: at where you'll be). Homing cone = `MaxHomingAngle`,
turn = `MaxRotationAngle` (deg/s), cloud = `HomingReductionInCloud`.

| weapon row | used by (FCS rows; enemy rows) | damage | life s | lead | homing cone | turn | top km/h | cloud |
|---|---|---|---|---|---|---|---|---|
| Missile_000 | PlaneMsl000-005 and the aces' PlaneMsl400-405, Shadows50, Toplak (~280 rows) | 40 | 7.3 | 0 | 60 | 30 | 3000 | 0.5 |
| Missile_050 | PlaneMsl050-055 (5 rows) | 40 | 7.3 | 0.2 | 100 | 75 | 3000 | 0.5 |
| Missile_000_Wingman | your wingmen | 40 | 7.3 | 0 | 75 | 40 | 3000 | 0.5 |
| Missile_050_Wingman | your wingmen | 80 | 7.3 | 0.7 | 120 | 120 | 3000 | 0.5 |
| MS19QAAM_000 | PlaneQAAM000 (a Survival special) | **15** | 13 | 0.45 | 75 | 60 | 4200 | 0 |
| MS092AAM_000 | Plane2AAM000 (a Survival special) | 30 | 20 | 0 | 90 | 50 | 4800 | 0 |
| MS12LAAM_000 | PlaneLAAM000 (a Survival special) | 40 | 25 | 0 | 60 | **10** | 4500 | 0 |
| MS04HCAA_000 | PlaneHCAA000 (a Survival special) | 30 | 9 | 0 | 75 | 50 | 4200 | 0 |
| MS21LAAM_000 | PlaneLAAM001 | 40 | 25 | 0 | 60 | 30 | 4500 | 0 |
| MS214AAM_000 | Plane4AAM001 | 40 | 20 | 0 | 65 | 45 | 4800 | 0 |

Two things stand out:
- The game's own allied-wingman missile (`Missile_050_Wingman`) turns 4x as hard as the enemy's, leads its target and
  has a 120 deg homing cone. AC8 already has the "strong AI missile" in its data; enemies just never get it.
- Survival's special weapons are weak as missiles: its QAAM does 15 damage (less than a standard missile) and its LAAM
  turns 10 deg/s, so it can only hit a plane flying straight.

## 3. Proposal A: enemy missile flight by level (the biggest gap)
Copy the missile's weapon row with each fire-control copy, the way `gunRow` already does for gun rounds
(`copy(wpn, r.NpcWeaponId:ToString(), edit, what, suffix)`, then `r.NpcWeaponId = FName(copy)`), keyed the same way
as the fire control (spike level, ace tier), so no new row families are needed. Load DT_NPC_Weapon when
`CFG.missiles.flight` is on (today `wpn` only loads with `CFG.guns.enabled`).

Starting values (Survival's own, between AC8's enemy and wingman rows; damage stays 40 at every level: health, attack
caps and numbers already scale):
| level | rounds | lead | homing cone | turn | life s | cloud | anchor |
|---|---|---|---|---|---|---|---|
| 0 | 1-7 | 0 | 60 | 30 | 7.3 | 0.5 | stock (no copy) |
| 1 | 8-14 | 0.2 | 100 | 75 | 7.3 | 0.5 | AC8's Missile_050 |
| 2 | 15-21 | 0.4 | 110 | 95 | 9 | 0.35 | between |
| 3 | 22+ | 0.6 | 120 | 110 | 10 | 0.25 | just under AC8's wingman missile |
| ace tiers | 16+ | one level above the round's, at most 3 | | | | | |

Config (user friendliness: players tune it without rebuilding): `[missiles.flight]` enabled, and per level
`lead`, `cone_deg`, `turn_dps`, `life_s`, `cloud`; `[missiles.flight.preset]` casual / standard / ace as a multiplier
on lead and turn (e.g. 0.75 / 1.0 / 1.15). Log line in the weapons style:
`weapons: Missile_000 -> Missile_000_SVB (flight: lead 0.20, cone 100, turn 75, life 7.3 s, cloud 0.50)`.

## 4. Proposal B: special weapons worth fearing
Survival's copies of the special rows (`<weapon>_SVS`), made with the fighters' rows:
- QAAM: damage 15 -> 40 (a standard missile's), lead 0.45 kept.
- LAAM: turn 10 -> 30 (as MS21LAAM_000), lead 0.2.
- 2AAM, HCAA: damage 30 -> 40.
Config `[special.weapons]` with each row's damage / turn / lead.

## 5. Proposal C: flares by tier, not only against missile-heavy players
Stock fighters carry `NPC_FCS_PlaneFlr000`: 10 flares, 25 s reload (Flr001 5, Flr002 15, Flr003 20). `[flares]` today
raises them (20 / 8 s) only when the saved profile is missile-heavy. Proposal: from Veteran 15 flares / 15 s, from Ace
20 / 10 s, for everyone; the missile-heavy profile adds its own on top.

## 6. Proposal D: un-soften the generic fighters
Some generic rows in the fighter pool fly below their airframe (DT_NPC Coefficients, NPC_DATA.md 4):
| row | coefficients |
|---|---|
| OP1005_f22a_01, OP1006_f35c_01 | pitch / roll / yaw / accel / decel x0.9 |
| OP1030_su33_01 / _02 (Survival's su33_common) | pitch / roll / yaw / accel / decel x0.8 |
| OP1026_su47_01 | everything x0.8, speeds too |
Proposal: Survival's `<NpcId>_SV` copies set these to 1.0 from the Veteran tier (or from spike level 1); stock below.

## 7. Already in Survival (no work needed)
Attack throttle (`[attackers]` 6 / 40 / 12, `[late.pressure]` presets), player-first search (40 km, no cloud loss,
engagement orders), short break-aways and tail chase (LA_SV_MoveAway, LA_SV_TailChase, LA_SV_Escape), pilot rank 2->5
and AI level 3-5 by tier, post-stall moves, provoke cones, faster missile and gun fire control by spike level, gun lead
for the aces, special weapons fired by Lua, late-round health x1.5.

## 8. Test checklist
1. Build with Proposal A only. Play rounds 1-7, then force a spike level (round 8+): the log's `weapons:` lines show
   the flight copies; the weapons log's missile outcomes at you (hit / decoyed / missed by weapon) give the hit rate
   per level. Compare against a run with `[missiles.flight] enabled = false`.
2. Check flares still beat level 3 missiles when used well (a missile you can't escape isn't fun).
3. Then B, C, D one at a time, the same way.

## Open questions
1. Does a weapon row copied at the main menu reach a fighter's missiles the same way gun rounds do? (Same pattern;
   the rows must exist before the level loads.)
2. How does AC8 apply `HomingForesightAmount` (fraction of a lead point, or seconds)? Watch level 1 vs 3 shots.
3. Is there an NPC-side post-stall shake-off for missiles (the player's weapons have `bIsReactiveToPSM`)? Not in
   DT_NPC_Weapon's row struct.
