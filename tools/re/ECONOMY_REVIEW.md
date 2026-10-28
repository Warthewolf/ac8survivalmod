# The economy review build (Lua 0.70.0, runtime 0.19.0; 2026-10-25)

Every proposal of the Claude Docs review "Survival Mode: Economy, Enemies & Allies Review" (a friend's 0.58.0 run to
round 23, 3 h, shot down under 54 aircraft with 148 missiles left), built in one go on branch
`feature/economy-review`. NOTHING here has been tested in game yet: the first test is the friend's. Each piece logs
what it does (the lines to look for are below), and each can be switched off in survival.ini.

The friend's zip is the Online edition without VALKA: `NOVALKA=1 sh tools/package_release.sh online 0.70.0` (no X-02S
container, no AC7 railgun sounds, VALKA switched off and out of the rotation: tools/novalka.py).

## Economy (Scripts/sv_shop.lua, sv_tactical.lua, sv_config.lua CFG.shop / credits)
| change | how | log lines |
|---|---|---|
| round bonus 250 x round (was 100), kill pay x(1 + 2 %/round), at most x1.5 | creditKill, TIER.roundX | `credits: +... (..., round x1.24)` |
| FULL REARM: everything missing, 25 / 100 / 75 a missile / special round / flare | offer role "rearm" | `shop: Rearm: REARMED for ...` |
| SPECIAL WEAPON shows both slots' counts, FULL with a pointer to WEAPON BAYS; each slot filled to its own load (it used to add the first slot's gain to both) | offer / shopBuy "ammo" | `shop: Special: ...` |
| UPGRADES: AIRFRAME (MaxHealth +25 %/tier), WEAPON BAYS (missile and special full load +50 %/tier: native SV_AmmoMax), GUN (+15 %/tier on the gun class default's `damage`: experimental), FLARE PODS (+2 MaxFlareCount/tier) | UP.apply every 2 s and on purchase | `upgrades: ...` |
| TACTICAL: AIRSTRIKE / ECM BURST / DECOY (Ctrl+F1/F2/F3, or by themselves), SECOND CHANCE | TAC.use / TAC.tick, INS.tick | `tactical: ...`, `insurance: ...` |
| AA gun / SAM price climb 1.12 (was 1.25) | CFG | |

Mechanisms to confirm:
- AIRFRAME writes the player's `MaxHealth` (AI planes took it: AB.L..IN), FLARE PODS the reflected
  `LivePlayerWeaponActivator.MaxFlareCount` (+0x27c, the native ammo code's flare max: tools/re/AMMO.md).
- WEAPON BAYS: runtime 0.19.0 `SV_AmmoMax(kind, max)` writes the weapon slot's max (the int before its current count).
  Does the HUD's missile count and the hangar's panel cope with a count above the stock load?
- GUN: `MachineGunClass:GetCDO().damage`. Player weapons are their own classes (`BP_plwp_*`), so enemies shouldn't feel
  it; restored at every level load. If it does nothing, `[upgrades] gun_experimental = false` takes it out of the STORE.
- SECOND CHANCE: `pawn:SetMinHealth(floor x MaxHealth)` (Missions 19 / 21 / 26 hold the player the same way); at the
  floor: RE_SV_RepairAircraft, health written, `SetIsInvincible` for 3 s. Not a crash into the ground.
- AIRSTRIKE: `ModifyHealth(-1e6, your aircraft, true)` on each plane of the target flight (works on AI objects:
  KILLS_HEALTH_DEATH.md 1). ECM: each enemy missile homing on you (`TargetToHome` = your aircraft) gets
  `bIsHoming = false`; within 500 m it's `K2_DestroyActor`ed. DECOY: RE_SV_Decoy_NN (engagement None) then
  RE_SV_DecoyEnd_NN 30 s later.

## Enemies (sv_rounds.lua, sv_spawn.lua, sv_ai.lua)
| change | how | log lines |
|---|---|---|
| waves: at most 14 / 18 / 22 aircraft up (Casual / Standard / Ace), next wave at 4 left or 150 s; from round 26 +1 a round up to 20 / 26 / 30 (behaviour roadmap P8, BEHAVIOUR_DIRECTOR.md unit 3) | makeWaves, roundsTick state "wave", TIER.maxUp | `round N: ... N waves (18 + 12 aircraft); cap C, up to U at once`, `round N: wave 2 of 2` |
| max_aircraft 30 (was 60), from round 26 +3 a round up to 60 by round 35 (P8: TIER.roundCap / roundBudget, the attack throttle's preset C from 26, D from 31); from round 15 enemy health x(1 + 4.5 %/round) <= x1.5 (P8; was 4 % and x2), promotion +3 %/round <= 60 % | enemyLate / scaleHealth, TIER.promoteChance, startRound's roundPressure | `late: round N enemies' health x...`, `pressure: round N: preset C (was B)` |
| raids: max 12 bombers, 50 % share, one direction (callout + HUD row) | raidBearing / spawnPoint(compass) | `bomber raid: ... from the NORTH-EAST (bearing 41)` |
| escorts: half a raid's fighter flights hold over the airfield (area 8 km, air-only, PlayerFirst) | RE_SV_Escort_NN | `events: RE_SV_Escort_NN (...) fired` |
| strike package: from round 6, 35 % of normal rounds, a 2-ship at the airfield | startRound | `a strike package (...) goes for the airfield` |
| hunters: at least one flight a round on the allied aircraft while they fly | ALLY.tick | `hunts the allied aircraft` |
| jammer: from round 8, 50 % of normal rounds, an EA-18G leads a flight; enemies within 6 km +1 PilotRank; pays x3 | JAM.tick | `jammer: ...` |
| more airframes from their round: F-2A 4, F-15C 6, Gripen 7, F-35C 9, Su-35 10, Rafale / Typhoon 12, Su-57 16, F-22A 18; unseen weighting; signature types from Mercenary | pickAircraft (POOL_EXTRA rows) | `round N: ERA_... as f15c_common_sv (pool, ...)` |
| specials: Ladons / Alicorn / AB.L..IN bring escorts from round 12; more health a round (MINDRIPPER's new) | startRound, ANOM.tick | `the alicorn brings N escorts` |
| airfield: hit_damage 3, bomb_damage 10 (were 4, 12) | CFG | |

Compass: north is -Y, east +X (Mission 22's dummyN0 / dummyS0); unconfirmed. If the callout's direction is mirrored
on the radar, flip it in spawnPoint / raidBearing.

## Allies (sv_allies.lua, sv_ai.lua KILL)
| change | how | log lines |
|---|---|---|
| kills by side: each enemy's DamageHistoryMap (reflected TMap attacker -> damage) read every 2 s and as it goes down; yours if you hit it at all or fired at it in its last 15 s (LastFiredWeaponTarget); allies' / ships' / defences' kills pay 50 % | KILL.read / KILL.by / KILL.markTarget | `kills: ... went down to the allies (damage: ...)`, `kills: round N: you ...` |
| HUD rows ALLIES (what's up, AA / SAM with health, kills, order) and ITEMS; round-clear KILLS callout; run summary line | sv_hud stack rows | |
| WINGMEN: two F-16Cs for 5000 on MOONCHILD's units (SV_SetAircraft sv_ally_wingmen before takeoff) | ALLY.buy / tick | `allies: VIPER (...) taxiing out ... (airframe set 2)` |
| orders HUNT / COVER / DEFEND (STORE row, Ctrl+F4): RE_SV_AllyHunt/Cover/Defend<X>: unit area onto the airfield 40 km / near you 5 km (every 6 s) / airfield 8 km (Mission 6's LiveChangeUnitRadius) | ALLY.nextOrder | `allies: ... ordered to cover` |
| repairs between rounds (planes to their scaled full health; Aegis hull and turrets and AA / SAM actors found by class); defences repaired with every airfield repair; lost warnings | ALLY.repairAll / repairDefences | `allies: repaired between rounds: ...` |
| Aegis hull +300 HP (MaxHealthDifference), strikes on ships 15 % every 2nd round (were 25 % every round), the nearest lanes sold first | ALLY.setup, startRound | `allies: DDG AEGIS's hull +300 HP` |
| allied weapons never run dry (MagazineCapacity >= 999) | allyFcs | |

## Performance
- Downed aircraft come off the plane list each round (it reached 538 entries in the friend's run).
- The STORE's texts are rebuilt at most every 5 s in flight (every kill used to rebuild all of them).
- The event containers are looked up again every 120 s, not 30 (each walk was a 22-29 ms hitch).
- Waves keep fewer aircraft up, which the per-plane work scales with.

## Build pieces
- tools/build_survival.py: STORE_PAGES (SUPPLIES 20, AIRFIELD 21, ALLIES 22, UPGRADES 23, TACTICAL 24), STORE_ROWS (4
  landing rows), POOL_EXTRA / SEARCH_AIRCRAFT (the new airframes and the EA-18G), the WINGMEN rows.
- tools/survival_events.py build_review: the escort, decoy and ally-order events.
- runtime/survival_rt.c: SV_AmmoMax, DYN_TEXTS 160 (the STORE alone sets ~65 texts now).
- tools/checks/ini_check.py: every survival.default.ini setting is a CFG field of its kind (no Lua on the build machine).
