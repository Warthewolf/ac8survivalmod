# THE DEAL: WAR & HAYTHORN's offers between rounds (the user's dev install only; not yet run in game)

The user's design (2026-11-23; it replaced the first draft of 2026-11-12, a vote on raising a special's stakes).
Code: `mod/UE4SS/AC8SurvivalMode/Scripts/sv_deal.lua` (one DEV ONLY block: cut from every release and TESTER zip by
`tools/strip_test_only.py` / `tools/dev_only.py`), its events in `tools/survival_events_deal.py`, its units in
`tools/build_survival_world.py` (the Hornet) and `tools/build_survival_units.py` `deal_units` (the targets). War's anger
uses THE DECOY's trap (`sv_decoy.lua` `DECOY.angerStart`). Test: `tools/checks/deal_test.sh`.

Characters: War (back seat, does the talking, the main character) and Haythorn (flies). Subtitles only, no voice.

## 1. How a deal runs
1. **The offer.** In a break between rounds (`D.state == "wait"`), `offer_after_s` in, never while you're in the
   STORE, a roll against `chance` (0.35; the user: 35 %). Once a break. Not while a deal's target is still to come.
2. **The Hornet.** `SV_Unit_DealHornet` (an allied F/A-18F: the escort fighters' pattern, MOONCHILD's unit copied, its
   DT_NPC row `SV_Deal_F18f` a copy of `OP1024_f18f_01` on the allied model `OP1024_f18f_Ally`, callsign key
   `SV_DealHornet` = WAR & HAYTHORN) is spawned 1.5 km ahead and 0.7 km right of you, 150 m up (700 m when you're on
   the ground). A second on, the event zoom: `RE_SV_DealCam` (Mission 22's shuttle focus camera,
   `LookAt_Event_Camera_ms22-01`, onto `SV_Obj_DealHornet`, off after 4 s).
3. **The question.** War's introduction, then the vote: AC8's own Yes / No (Mission 8's
   `LiveActivateYesNoExecution` and its three `YesNoEvent` triggers, cloned: `RE_SV_DealAsk` opens it on each game, the
   answer in the int flag `SV_DealAns`: 1 YES (Left), 2 NO (Right), 3 silence (TimeOut)). Ctrl+A / Ctrl+X still vote.
   `vote_s` 30 s. The most votes win; a tie is NO; nobody voting is silence.
4. **The break is held** while the deal's on (`hold_break`): the next round's start (`D.at`) is pushed back to the
   vote's end and the result.
5. **The result**, then the Hornet turns away (`RE_SV_DealLeave`: the path `SV_Path_DealHornetOut`, far north east) and
   is recycled `hornet.leave_s` (25 s) later.

## 2. The deals (one offered each time, by `deals` weights; their target comes in the NEXT round)
| deal | units | built from | pay (`targets.*`) |
| --- | --- | --- | --- |
| podarge | `SV_Unit_DealPodarge` (`SV_Obj_DealPodarge`), route `SV_Path_DealPodarge` west to east ~9 km south of the runway, 2.8 km up, 450 km/h | Mission 12's Norn `EAUnit01_Norn0` (AC8's Podarge: Mission 25 day 2's "It's a Podarge!") with its 16 parts (its Cargo1 slot left out); its rows Mission 12's (`norn_01` as `sv_deal_podarge`, the parts' under their own names) | 6000 + 300 x round |
| cargo | `SV_Unit_DealCargo` (`SV_Obj_DealCargo_0..2`), three lanes `SV_Path_DealCargoA/B/C` north to south east of the runway, 2.2 km up, 420 km/h | a copy of the heavy flight `EA_Unit_01_Air2` on `sv_deal_cargo` (Mission 4's `t160_common`, NpcId `OP0054_c130_01`) | 2000 + 100 x round each |
| fleet | the Spaceport round's ships, its first 2 groups (a Wasp, 2 Aegis, 2 boats each), where they sit | `sv_spaceport.lua` `SPORT.fleet`; only when `ALLY.fleetReady` (their turrets' rows); never in the Spaceport round itself (it waits a round) | 1200 + 60 x round each |
The target comes `targets_after_s` (15 s) into its round, with a callout and War's line, and `RE_SV_DealPodargeGo` /
`RE_SV_DealCargoGo` put it onto its route. Each target down pays (`SV_UnitAlive` watched every 2 s); all of them
down adds `pay.all_bonus` (3000 + 150 x round), THE DEAL PAID. One still up at the round's end or `targets_s` (420 s)
on is taken off unpaid: TARGET ESCAPED. The pay is the host's `addCredits` (shared in co-op as every special's).

## 3. War's anger
- NO (or a tie): `anger.no_chance` (0.20): 5 Marker Drones in the next round.
- Nobody answering: 7 Marker Drones, a new flight in each of the next 2 rounds.
- The drones come `anger.after_s` (20 s) into the round: `DECOY.angerStart(n)`, THE DECOY's trap alone (its Spear UAVs
  lock the nearest player; 8 s to shoot one down before its Tonitrus Spear; `DECOY.cap` the count; unpaid). Never in
  THE DECOY's own round, nor while the last drones are up (both wait a round). WAR IS ANGRY.

## 4. Co-op (host-authoritative)
- `dl|id|kind|secs left|yes|no` (the open vote), `vt|id|1/0` (a joiner's answer), `dr|id|yes|no|taken` (the result).
- `RE_SV_DealAsk` is each game's own (`sv_coop.lua` KEEP_EVENTS, a DEV ONLY line); the camera, the leave path and the
  targets' routes are the host's, forwarded. The Hornet, the targets and the drones reach the joiners as the host's
  spawns do; War's lines as its subtitles, the callouts as "co".

## 5. Log lines
`deal: the break after round R: no offer (rolled ...)`, `deal: offered in the break after round R (<kind>, ...): its
target in round N`, `deal: the Hornet: ... up`, `deal: the event zoom onto the Hornet (RE_SV_DealCam fired)`,
`deal: AC8's Yes / No asked for vote N`, `deal: you answered YES|NO`, `deal: vote N closed (<why>): YES y, NO n: ...`,
`deal: the break held for the deal`, `deal: War's anger (...): n Marker Drones in round(s) ...`, `deal: round R: <kind>
up (n): ...`, `deal: <kind> onto its route`, `deal: <kind>: n down`, `deal: <kind> over (<why>): d of t down, l left`,
`decoy: War's anger (...)`, `deal: the Hornet turns away`, `deal: the Hornet taken off`.

## 6. Test checklist (dev install; Ctrl+H offers one now)
1. The Hornet appears beside you with the zoom onto it; WAR & HAYTHORN on its box; it doesn't attack you.
2. AC8's Yes / No shows; Left = YES, Right = NO; letting it run out = silence.
3. The next round waits for the vote.
4. YES on each deal: the Podarge (its parts, its turrets and VLS fire?), the C-130s (three lanes), the fleet off the
   spaceport; each pays as it goes down; the leftovers vanish at the round's end.
5. NO a few times: sometimes 5 drones next round; silence: 7 drones in each of the next 2 rounds.
6. The Hornet flies off north east and disappears.
7. Co-op: each player gets the prompt; the vote counts both; the joiner sees the Hornet, the targets and the drones.
