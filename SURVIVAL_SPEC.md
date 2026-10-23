# Survival Mode: confirmed spec (from the user, 2026-10-20)

Both agents: this is the agreed design. Build to this. Stock references come from MISSION_REFERENCE.md.

## 1. Menu flow
Main Menu -> "SURVIVAL MODE" entry -> difficulty select -> hangar (aircraft/weapon select) -> sortie.
- Main menu widget: /Game/NUI/Main/WBP_Menu_Main_000 (class LiveNUIMenuMainWidget). Entries are built from
  WBP_Menu_Common_Parts_BtnList_000 + ListCategory_000 + Description_000; preview panel uses PreviewMode_000.
- Add one entry with a description line, styled like the other entries.
- Difficulty: reuse the game's own difficulty setting so stock nodes respond to it
  (LiveIsAchievedDifficultyConditionStatement is in every mission).
- UNKNOWN: whether a new menu entry can be added by data alone, or needs a UE4SS hook on LiveNUIMenuMainWidget.
  Prototype this first and on its own. Fallback: an entry in Free Mission that launches the survival map.

## 2. Map and home base: Comona Island
- Comona = Map17. Home base = Map17_Env_ComonaAirport, the airstrip Mission 22 uses as its home base.
- Base the survival persistent level on PL_Mission022's sublevel list (Map17 terrain, sea, city, foliage, airport),
  minus Mission 22's own mission content.
- Mission 22 already has takeoff/landing (LiveSetTakeoffAndLandingEventExecution) and the Supply event at this
  airstrip. That is the base for landing and rearming.

## 3. Sky and clouds: Mission 4 (user, 2026-10-22; was Mission 16)
- Replace Mission022_Common_Lit_Cloudly01 with /Game/Maps/MapCommon/Map05/Mission004/Mission004_Common_Lit_Cloudly01
  (sky light, sun, height fog, post process and the LiveCloudlyActor cloud layer), with PL_Mission004's clock 10:10
  and CloudDensityScaleBySound 1.308.
- RISK: that lighting level was authored for Map05. Check sun direction, fog height and sea colour over Comona.
  If the clouds sit wrong, copy only the Cloudly sky/cloud actor into a new Map17 lighting level.

## 4. Airfield health bar
- A health bar above the airfield, starting at 100. The run ends (or round fails) at 0.
- Stock references:
  - Mission 4: a base the enemy attacks, with base HP set by difficulty (RE_BaseHP_Easy, RE_BaseHP_Norml) and
    bomber attack paths (01_MB_BaseAttackAssist_*). Closest match. Study first.
  - LiveUnitHealthDisplaySwitch (Mission 6, Mission 25_2): shows a unit's health on the HUD.
  - LiveSetMaxHealthExecution / LiveSetHealth: set the base to 100 at start; refill on a repair purchase if wanted.
  - Mission 13: Call_BeforeTakeoff_BaseMinHealth (base minimum health before takeoff).
- Show the bar as 0–100 regardless of the real HP value underneath.
- Airfield HP carries over from round to round until it's repaired (user, 2026-10-23); repairs are bought at the STORE.
- At 0 it's down: landing (and so the STORE) closes, and after the next round it comes back on its own at 50 HP
  (user, 2026-10-23: keep). Losing it doesn't end the run.

## 5. Enemy roles
- Bombers attack the airfield: spawn on paths that end at Comona Airport and drop on it (Mission 4 base-attack paths;
  Mission 28 has a Wave10_Bomber).
- Fighters engage the player directly: LiveAIEngagementOrder / LiveAIChangeEnemySearchType set to target the player.
- Radio callout when bombers appear, so the player knows to defend.

## 6. Round HUD (user request 2026-10-21)
- The round number is always on the HUD.
- Round countdown timer: it starts only once a round is complete and shows how long until the next round starts
  (the intermission). Nothing counts down while a round is being fought.
- "Round Complete" callout when a round is cleared.
- A callout just as a round is about to start.
- No timed despawn of enemies that drag on: they're chased and have to be shot down.

## 7. Amphibious assault special round (user, 2026-10-23)
- Enemy LCACs land troops on Comona's beaches by the airport (Mission 13's enemy LCAC pattern).
- Failure: "the airfield being captured and it lasts for 2 rounds" (it is taken while troops get ashore; it is back
  after two rounds).
- (Superseded: captured when landed troops were still alive ~30 s after reaching the beach.) Now (user, 2026-10-23):
  the troops drive from the beach to the runway; each one that reaches it adds to a capture percentage on the HUD
  (25 % each), and at 100 % the airfield is captured. More landing craft: four per lane.
- Once captured, destroying every landed troop vehicle frees it early; otherwise it's back after two rounds.
- Captured = landing and the STORE closed, "AIRFIELD CAPTURED" and the rounds left on the HUD (proposed, as when the
  airfield is down).
- The round still has its enemy fighters, with a chance of a bomber raid too (user, 2026-10-23: "when an LCAC round
  spawns, enemy aircraft still spawn also, with a chance for bombers to also spawn").
- Start points on the water: the user marks them with Ctrl+F10 (marks after the five beach marks in
  config/coast_marks.txt are start points).

## 8. Allies (user, 2026-10-23)
- Enemies shot down by bought allies (MOONCHILD, the DOCKS ships) pay the player as if the player had shot them down
  ("allied kills should still pay me yeah"). Every enemy aircraft that goes down pays, whoever downed it.

## Open decisions
