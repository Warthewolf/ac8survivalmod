# Survival Mode: Improvements

Nov 3, 2026 · @War

The three changes that would improve Survival most: clean up every special when it ends (boss parts left behind killed players up to 36 rounds later), scale bosses and late rounds to the number of players (bosses die in under a minute with 4-5 players), and tell players what hit them (40-74% of the damage in the logs has no source a player could see). Everything here comes from the logs of 11 players over 13 runs (rounds 1-46) plus the code on GitHub; the bug fixes are in the Desync, Lag and Compatibility Plan and the money in the Economy Change Proposal, so this doc is about making the mode better to play.

## At a glance

&#91;embedded content: the suggestions in this doc, by impact and effort (zones, not exact positions)\]

Each suggestion is explained in its section below; the bug fixes behind several of them are in the plan.

## Pacing and rounds

Ordinary rounds have a good length: a median of about 4 minutes (236 s in Shake Shack's run, 239 s in Saint Alessia's). The outliers are the bosses, which end too fast, and a few rounds that drag.

| What | In the logs | Target |
| --- | --- | --- |
| Ordinary round | 236-239 s median | 3-5 min (fine) |
| VALKA's fight | 33-52 s from showing to down | 2-4 min |
| AB.L..IN, the Anomaly | 47-60 s | 2-4 min |
| Ladons | 115-153 s | 3-5 min |
| Alicorn, Spaceport | 262-439 s | 5-8 min (fine) |
| Harvest ace-squadron rounds | 8-15 min (rounds 28, 31, 34, 40, 43) | 5-8 min |
| Waiting on the last enemy | 2-3 min in rounds 4 and 13; 9 min 11 s in Saint Alessia's round 5 | under 1 min |
| An enemy with you on its tail survives | 4-6 s median | 8 s or more (the stats' own target) |
| Missiles left when the run ends | 177-295 | under 40 (the stats' own target) |

Suggestions:

1. **Scale bosses with the room.** VALKA had 2,240 HP with 3 players and 2,400 with 4 (x1.12-x1.20). Give bosses health x (1 + 0.5 x (players - 1)): about x2.5 with 4 players, so a fight lasts long enough for her phases, blinks and railgun to happen.
2. **End the long tail.** When a round has 1-2 enemies left for 60 s: release any held flight (Wolf traps, top cover), send them at the nearest player, and ping them on the minimap. Round 13's last 3 minutes were one held Wolf-trap flight.
3. **Cap the Harvest rounds.** After 6 minutes, the squadron's remaining aces break off and escape (pay what's been shot down). The fight stays memorable without being a slog.
4. **Make missiles count again.** Players finish with 200-300 missiles: weapon bays double the load and rearms refill it. Either a smaller bays upgrade (+25% a tier, not +50%) or rearm prices that rise with the round.
5. **Harder tailed enemies late.** From round 15, more defensive reversals and break turns for Veteran and up (the stats measure it already: 4-6 s against a target of 8 s+).

## Co-op experience

The core works: up to 5 players held together for 4 hours, revives were used 13 times across the runs, players dropped and came back (Amia about 10 times) without breaking anything. What players feel is at the edges.

- **Late joiners start broke.** liljojofett rejoined at round 41 with the setup's 1,000 Z, while the host had about 24,000 and mobi118 336,000. Nothing in the STORE at round 41 costs 1,000.
- **Some players spend a third of every round in the STORE.** Shake Shack and mobi118 were at the airfield 28-30% of round time (invincible while on the ground), everyone else 10-14%. In co-op the world keeps running, so their teammates carried those minutes.
- **Modded planes look like F-16s.** Saint Alessia's Falken (a mod) showed as an AI F-16 to everyone else.
- **The room waits silently.** "WAITING FOR PLAYERS" came up 9 times in Shake Shack's run, with no hint of who or how long.
- **Co-op runs leave no record.** Co-op runs aren't sent to the leaderboard, so a 4-hour, 46-round run by five players is invisible.

Suggestions:

1. **A catch-up purse for late joiners:** a player joining after round 5 starts with half the room's median balance (capped at 250 x the round squared, so 40,000 at round 40).
2. **A one-press STORE restock.** One row that rearms, repairs and refills tactical items as you had them last time, priced as the sum. Most stops would take seconds.
3. **A co-op leaderboard:** its own board, by player count (2, 3-4, 5+), with every player's name on the entry. Now planned for 1.0.0: Workstream H of the plan, which also fixes why no co-op build's run reaches the leaderboard today.
4. **Show who the room is waiting for**, with their state (loading 45 s, link lost), and drop the wait after 60 s.
5. **Closest-match stand-ins for modded planes:** the Falken as Survival's AI ADFX-02 (it already exists for the Reaper aces), others by airframe class.
6. **A teammate marker on the HUD** for DOWN players and players at the airfield, so others know who's out of the fight.

## Specials and variety

Every special in the rotation was played at least once, and testers reported most of them working without issue. Two things hold them back: bosses that leave parts behind, and bosses that die too fast in a full room.

| Special | Fight length | What happened |
| --- | --- | --- |
| Shuttle defence | 150-171 s | Fine; came twice in Shake Shack's 46 rounds |
| Ladons | 115-153 s | Their VLS launchers outlived them: they hit mobi118 in rounds 39, 41 and 46 (Ladons in round 10), and dukka in round 28 (Ladons in round 21) |
| Spaceport Assault | 439 s | See its own section: pay bug, the capture never threatened, the retake never played |
| Landing craft | 246 s | Fine |
| VALKA | 33-52 s | Her opener railgun stayed up for the rest of every run; her sure-kill railgun part (RGCK) hit dukka in rounds 26 and 28 (VALKA in round 16) |
| AB.L..IN, the Anomaly | 47-60 s | Over before their phases show |
| Alicorn | 262-419 s | Its VLS and AA guns hit Shake Shack and liljojofett in rounds 43 and 46 (Alicorn in round 42) |

Suggestions:

1. **One clean-up for every special.** When a special ends, take down everything it spawned (parts, dummies, turrets, drop units), then check the unit list 2 s later and log anything still alive. Leftovers are the worst kind of death: invisible, far away, and sometimes a scripted sure kill.
2. **Boss health by player count** (Pacing, suggestion 1).
3. **Round modifiers** (Saint Alessia): a twist on an ordinary round, one in four rounds from round 8. Her three, each built from the stock mission that does it: railgun bombardment (Retaking Theve 1), Tonitrus spear strikes (Over the Rainband), allies joining for the round (Mission 28). More in the same spirit: a night or storm round, an ECM-jammed round (no minimap), a round where the airfield is closed, an all-aces round with fewer planes.
4. **A fairer rotation.** In 46 rounds the shuttle came twice while the Spaceport retake never came. Pick the next special from those seen least this run, as the airframes already are.
5. **Let the boss fights breathe.** With boss health scaled, VALKA's three phases, AB.L..IN's frenzies and the Anomaly's field all get time on screen; today players saw one phase of each.

## The Spaceport round

It was played once, round 13 of Shake Shack's run: the fleet came in, all 27 ships and all 12 landing craft went down, the spaceport was held, and the joiners' copies of the fleet behaved. Everything after a capture (the retake, Mission 19's rockets, the island enemies) has never been played in any log. Below: what the logs show, then what a review of the code on GitHub (0.73.58) found; players run 0.73.76, so the code findings need checking against it.

| # | Bug | Evidence | Sure | Fix |
| --- | --- | --- | --- | --- |
| S1 | Ships pay per part: price x the hull and turrets lost | Aegis paid 2,400-12,000 each; the fleet \~242k instead of \~64k | Certain (log + code) | Pay once per ship when its hull goes (Economy C2) |
| S2 | "Sunk" fires per part | CARRIER SUNK twice for one Ford; Aegis F, L, N sunk twice | Certain (log) | Same as S1 |
| S3 | Joiners are never paid for landing craft | Host 28 craft payouts, mobi118 0: the reason "landing craft down (" matches the co-op filter for plane kills (sv\_coop.lua addCredits) | Certain | Reword to "landing craft sunk" (and the landing craft special's "troop vehicle down (") |
| S4 | A fleet left after a capture is never removed, and every later Spaceport is refused | `ready()` refuses while a ship is up; the clean-up in `SPORT.spawn` sits behind it. Same when the retake round is skipped | Certain (code) | Remove the fleet when no retake can follow, and in `ready()` remove instead of refuse |
| S5 | A ship counts as afloat while any part lives | The round, the retake and later Spaceports can hold on one surviving turret; the Ford's deck keeps launching | Possible (Ladon parts did this before) | Count the hull; finish off its parts when it sinks |
| S6 | Fighter flights withdrawn at a capture can't spawn again that level | Deactivated, not destroyed: the native recycle refuses "still up"; they stay first in line every round | Likely (code) | Destroy them, or skip units still alive when picking flights |
| S7 | The rockets can hold the retake forever, or "escape" 12 s after launch | No overall timeout; the boost re-issues the path, which may count as finished | Possible | A rocket timeout; accept an escape only after a minimum climb |
| S8 | Debris assumes a split happened | Both rockets down in one tick: no split, debris underground marked as targets for 120 s; a debris unit that failed to spawn pays twice | Possible | Start debris only after the split fired; store each debris unit's count at spawn |
| S9 | The escape penalty only hits the host | -5,000 comes off the host's money, but the callout goes to everyone | Certain (code) | Send the debit to every game |
| S10 | Waves and rocket launches run while a solo player is landed | Landing early can lose the spaceport or a rocket | Likely unintended | Pause them as the shuttle's countdown pauses |
| S11 | A non-whole `capture_per_troop` in survival.ini stops the rounds | `%d` on a fraction throws every tick | Possible | Round it |
| S12 | Host migration between capture and retake loses the retake; joiners get no NEXT row for it | `RUN.sport` is the host's only | Possible | Carry it in the migration's state |
| S13 | The Ford launched 2 of its 8 planned flights | "no free 2-ship to launch": the round's fighters used every pool flight | Certain (log) | Reserve deck flights when the round is planned |
| S14 | The round waited 3 min 19 s on one held Wolf-trap flight after the fleet was gone | Round 13's last minutes | Certain (log) | Plan A7, and release holds when 1-2 enemies are left |

As a round, it also never got dangerous: 0 of 12 landing craft landed, so the capture meter never moved. With 5 players and allied ships, the craft need more escort or more of them per wave. The retake needs a session of its own (the test keys force both the assault and the retake) before 1.0.0.

## Player feedback and clarity

Players often don't know why they died or whether what they bought worked.

- **Damage with no visible source:** 53% of Shake Shack's damage, 74% of dukka's, 40% of Saint Alessia's was "unknown" to the hit tracker (no missile seen near). Of the 10 times a player went down, 5 were "unknown 100%": boss leftovers, VALKA's railgun parts, the Alicorn's guns.
- **One-shots:** three deaths to the F/A-18E's scripted certain-kill missile, each taking a whole health bar.
- **Upgrades that look broken:** every airfield stop shows stock health for about a second (the game's reset, then Survival's restore), so cressendo thought the FA-36's airframe upgrade didn't work.
- **Possibly friendly fire:** in rounds 43 and 46 Shake Shack's own STORE-bought Aegis destroyers appear among what damaged him (53 HP at his last death; no enemy fleet was alive then), and dukka took small hits with allied VLS missiles 230-600 m away. The boosted allied missiles and flak may hurt players near their targets: worth a test with an allied Aegis firing at an enemy close to a player.
- **A chatty radio:** 1,285 radio tells in Shake Shack's 4 h 12 min (about 5 a minute), and the squad director ran 7-10 tactics a round against its own target of 3-6. Callouts are fine at about 2 a minute.

Suggestions:

1. **"Hit by" and a death recap.** A short callout on a big hit ("HIT: LADON VLS", "HIT: RAILGUN") and, when you go down, one line: what did the damage in your last 30 s, from where, how far. The hit tracker already knows most of it.
2. **Show upgrades as numbers.** The STORE row and the info wall show "AIRFRAME 2: 180 HP", and health is restored the moment the game resets it.
3. **A radio budget.** At most one tell every 12 s per player, and the director's tactics capped at its target of 6 a round; the important calls (specials, raids, a teammate down) always get through.
4. **A run summary at the end** (from the stats lines that already exist): rounds, kills, money earned and spent, specials beaten, best round, revives given, on the RUN OVER screen and in a text file players can share.

## Tester feedback: a 5-player run, rounds 20-40

A tester who flew rounds 20-40 of the 5-player, 46-round run (Shake Shack's log, 2026-11-02) liked the concept a lot ("get a bunch of friends together and just kill things without needing to worry about competing scores") and likes missile hell, but had three complaints and two suggestions. The logs back every complaint.

1. **Harvest has too much health, too many planes, too often.** Logs: every ace round from round 28 is Harvest by design (the ace round flies the round's tier's squadron, and the Reaper tier lasts from round 28 to the end). Harvest's planes fly the campaign's named-ace bodies (`CP_Named`, `CP_Shadow`), about 7,000 HP each before the late-round x1.5: 9,900 to 10,725 HP a plane. Inferno's Su-57 had 1,564 and Valkyrie's Rafale 735. Rounds 40 and 43 sent 80 of them, up to 30 at once, and Harvest rounds ran 8-15 minutes. That jump almost certainly isn't intended: the Reaper tier's own setting adds 600 HP, which only makes sense on a normal fighter's 1,000-1,500. Suggest: set each tier's ace health from the tier (wingmen about 1,800 at Reaper, the named lead about three times that), not from the airframe's row, and check Wraith's Shadow Su-57 for the same; make ace rounds smaller and meaner (12-24 squadron planes, 6-10 up at once, their missiles at once kept high), which is what the tester enjoyed most ("ace fights when there was only 6-10 of them while my entire screen was filled with missile alerts"); from round 28, fly Harvest every other ace round and the earlier squadrons at Reaper skill between. The 6-minute cap above stays as a backstop.
2. **VOID WATCHER 1 wins the fight for you.** Logs: its ESM field reaches 25 km (stock 3.2 km) and is fired every 20 s for 24 s, so it covers the whole fight all the time. The one bought in round 16 lasted 92 minutes, until round 34. Suggest: it serves 3 rounds and then lands (buy it again, at a price that rises x1.25 a purchase, as the other allies'); its field 8-10 km, over the airfield and not the whole map; and each round it's up, a strike flight goes after it, as strike flights go after the STORE's ships.
3. **Airstrikes end furballs in 5 seconds.** Logs: the host bought 40 in the run; in round 43 (Harvest) two players called 14 of them. Many were the only practical answer to 10,000-HP planes, so fixing Harvest removes part of the reason. The economy proposal already makes them cost more as the rounds go up and pay a quarter back (C4). Suggest also: one per player per round; never on an ace squadron's flights (today only a flight an ace leads is spared, so Harvest's wing flights are fair game); at most 4 planes hit; and no automatic call, so it's always a choice.
4. **More ground threats.** There's a reason to carry anti-ground weapons only in the amphibious round, the Alicorn and the Spaceport. Suggest a ground push in ordinary rounds from about round 8: alongside the aircraft, an armour column (T-90s, BTR-90s) lands on a beach and drives towards the airfield, with mobile SAMs and AA guns (Gecko, Shilka) stopping on the hills along the way. A column that reaches the airfield shells it. The round ends only when the column is down too, and each vehicle pays. All the parts exist: the amphibious round's beach landings, the Spaceport island's ported ground units, and ground paths over Comona that already work (hard rule 31). Their spots come from offline data, as the Spaceport's building check does.
5. **More mission-style objectives.** Suggest new round types in the special rotation, each from a pattern we already have: escort (an allied transport flies in from the edge of the map to land at the airfield, and enemies go for it), protect (a radar site or a convoy of allied ships on the coast for a set time), strike (a radar station that scrambles the minimap, as the Anomaly does, until it's destroyed; or artillery shelling the airfield), and hold (the Spaceport's capture meter turned around). They fit Saint Alessia's round-modifier idea under Player feedback.

## Stability, performance and release process

The fixes themselves (the copy desync, the two crashes, the lag growth, the rejoin aircraft) are in the Desync, Lag and Compatibility Plan. What would make the next ones faster to find:

1. **One log report for every test.** The scripts used for these docs (money, deaths, copies, perf, Spaceport) as one command in `tools/checks` that reads every player's zip and writes a page. This review was done by hand, log by log; the next one should take minutes.
2. **Crash reports collected by the mod.** On start, if the last session crashed, Survival copies the newest crash folder and the crumbs into one zip next to its logs and says so on the main menu. Players sent crash reports only when asked.
3. **A symbol map per runtime build,** so `main.dll` frames in a crash report have names.
4. **Push the source of every build players get.** 0.73.59 to 0.73.76 aren't on GitHub, which blocked every fix in this review.
5. **A short soak test before each friends' build:** a solo run to round 20 with a test key that runs every special once (catches leftovers, lag growth and payouts without five players).

## Suggested order

1. **The plan's fixes first** (phases 0 and 1 of the Desync, Lag and Compatibility Plan): every suggestion here is easier to judge once the copies, crashes and one-shots are gone.
2. **One build with the four "do first" items** (clean-up of specials, boss health by players, the long tail, the late-joiner purse), the economy changes once agreed, and the log report tool, since its scripts already exist.
3. **The quick polish** in the next build: radio budget, missiles, the Harvest cap, the rotation, upgrades as numbers. Mostly config.
4. **A Spaceport session:** force the Spaceport with its test key until the capture and the retake have both been played, with the fixes from its section in.
5. **Then the bigger features:** "hit by" and the death recap, the STORE restock, and one round modifier as a prototype (allies joining for the round is the cheapest: VOID WATCHER and SNIPER already exist).
6. **Later:** the run summary, harder tailed enemies. (The co-op leaderboard moved into the plan for 1.0.0.)
