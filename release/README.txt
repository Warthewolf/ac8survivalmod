AC8 Survival Mode - {EDITION} edition, test build {DATE} (Lua {LUA}, runtime {RT})
======================================================================

A round-based survival mode for Ace Combat 8 (PC, game version 1.1.2.0). Waves of enemy fighters get bigger and
sharper every round, bombers raid Comona Airport every 3rd round, and every 5th round is a special round. Land at
Comona Airport between rounds to spend the zollars you earn on missiles, special weapons, flares, airfield repairs,
and AA guns / SAM sites around the airport.

This is a TEST build: things may break. Please send logs (see below).


Needs
-----
- UE4SS for Ace Combat 8 (dwmapi.dll next to AceCombat8.exe and a "ue4ss" folder).
- AC8 Mod Loader 1.3.1 or newer (the IoStoreLoaderMod folder under ue4ss\Mods).


Install
-------
1. Close the game.
2. If you had an older Survival Mode test, delete these two folders first:
       ...\Win64\ue4ss\Mods\AC8SurvivalMode
       ...\Win64\ue4ss\Mods\IoStoreLoaderMod\SurvivalMode
   (Keep a copy of AC8SurvivalMode\config\survival.ini if you changed settings in it.)
3. Copy the "ue4ss" folder from this zip into
       ...\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64\
   and let Windows merge the folders.
4. Start the game. SURVIVAL MODE is on the main menu, above QUIT GAME. (If its pages can't be added on your setup,
   SURVIVAL MODE goes straight to the difficulty select, with the default rules; please send the logs.)


Play
----
Main menu -> SURVIVAL MODE -> pick how you play:
  SURVIVAL MODE SP OFFLINE   alone, with your own rules; nothing is sent anywhere
ONLINE ONLY BEGIN
  SURVIVAL MODE SP ONLINE    alone, for the Discord leaderboard (custom rules make a run unranked)
ONLINE ONLY END
  SURVIVAL MODE COOP HOST    host a run for your Steam friends (Survival COOP build)
  SURVIVAL MODE COOP JOIN    join a friend who hosts (straight to the difficulty: you play the host's rules)
  QUICK START                the last mode you played, with its rules, straight to the difficulty
Each mode but JOIN opens its RUN SETUP page. Press a row to change it; every mode remembers its own (survival.ini
[setup.offline] / [setup.host], and [setup.online] in the Online edition):
  START RUN                  next: the difficulty, then the hangar
ONLINE ONLY BEGIN
                             (on SP ONLINE it says RANKED or UNRANKED: only ranked runs go to the leaderboard)
ONLINE ONLY END
  PRESET                     AUTO (follows the difficulty), CASUAL, STANDARD or ACE: your ammo caps, enemy skill and
                             how many enemies fly at once
  STARTING ZOLLARS           0 to 25,000
  ENEMY AIRCRAFT             50 % to 200 % of each round's enemies
  COOP HOST also has         LOBBY (who has joined so far), CO-OP ROOM (how many players) and CO-OP ENEMIES
  MORE RULES >               START AT ROUND, BREAK BETWEEN ROUNDS, SPECIAL ROUNDS (normal / more / fewer / off),
                             AIRFIELD HEALTH, ZOLLAR INCOME, ENEMY SKILL, RESET TO DEFAULTS
The bottom line of the menu explains the row you're on, with numbers (how many enemies round 10 brings, what a kill
pays ...). Then: pick a difficulty -> hangar -> sortie. You start over Comona Airport.
- Shoot down every enemy to clear a round; the next one starts after the break (20 seconds, or your BREAK BETWEEN
  ROUNDS).
- Big rounds come in WAVES (at most 14 / 18 / 22 aircraft up at once on Casual / Standard / Ace): the next wave comes
  once the last one is down to a few. The ROUND row shows WAVE 2/3. After round 15 rounds stop growing and the
  enemies get tougher instead.
- Bomber raids (every 3rd round) go for the airfield, all from one direction: the callout and the HUD say which
  ("BOMBER RAID FROM THE NORTH-EAST"). Half the fighters escort them over the airfield. At 0 health the airfield is
  down: no landing for the rest of that round and the next one, then it comes back at half health.
- From round 8 a round may bring an ENEMY JAMMER: an EA-18G that makes every pilot near it sharper. Shoot it down
  first; it pays triple.
- Ammo: you take off with your difficulty's load, and landing does NOT refill it. Buy more at the airfield.
- Land at Comona Airport between rounds: the landing menu has four STORE rows (SUPPLIES, UPGRADES, TACTICAL,
  AIRFIELD & ALLIES), each opening its page; the pages also link in a ring and each has TAKE OFF.
    SUPPLIES: FULL REARM (everything back to full load in one press), MISSILES +12, SPECIAL WEAPON +4 (shows what you
              carry, e.g. (4/4, 8/8)), FLARES +2
    UPGRADES: for the rest of the run, in tiers: AIRFRAME (+25 % health a tier), WEAPON BAYS (+50 % missiles and
              special weapons), GUN (+15 % damage), FLARE PODS (+2 flares). Buy the extra ammo after.
    TACTICAL: items you carry until you use them (up to 2 each):
              AIRSTRIKE  (Ctrl+F1) destroys the biggest enemy flight near you
              ECM BURST  (Ctrl+F2) breaks every missile lock on you for 10 seconds
              DECOY      (Ctrl+F3) the nearest enemy flight breaks off for 30 seconds
              Each also goes off by itself when it's needed (8 enemies close, 2 missiles closing in, a big flight
              on you). SECOND CHANCE: survive one shoot-down (not a crash into the ground).
    AIRFIELD: REPAIR AIRCRAFT, REPAIR AIRFIELD (repairs its AA guns and SAM sites too), BUILD AA GUN, BUILD SAM SITE
    ALLIES:   WINGMEN (two F-16Cs, cheap), MOONCHILD (two F-22s), AEGIS DESTROYER, and ALLY ORDERS: HUNT (anywhere),
              COVER (stay with you) or DEFEND (the airfield). Ctrl+F4 changes the order in flight.
  Allies, ships and airfield defences still up are repaired between rounds. The ALLIES row on the HUD shows what's
  up and what they've shot down; their kills pay you half. Each item has its icon; the bottom line says what it does
  and how many zollars you have. (If the STORE can't be added on your setup, the landing menu shows the four shop
  rows instead.)
- The ITEMS row on the HUD shows the tactical items you carry and the SECOND CHANCE.
- Pause menu -> Music Player picks your music.

Enemy pilots: they get better as the rounds go (Rookie, Regular, Veteran, Elite, Ace, then Mercenary, Legend, Demon,
Phantom and Reaper from round 16). Rounds 8, 15 and 22 are difficulty spikes. Better pilots sit on your tail, break,
flare, and from Mercenary up use cobra / kulbit baits and scissors.

More aircraft types join the enemy as the rounds go (F-2A, F-15C, Gripen, F-35C, Su-35, Rafale, Typhoon, Su-57,
F-22A), and from the Mercenary rank pilots often fly their rank's own types.

Named aces (ace rounds: 16, 19, 22, ... - only ace squadrons, no bomber raids; the rounds between are normal): each rank flies its own squadron - F-15C, Su-35, Typhoon, Su-47, Rafale, F-22A, Su-57 and,
for the Reapers, an ADFX-02. Their leaders are named aces (Ledger, Sigrun, Mephisto, Specter, Grim, Oblivion, ...);
an "ACE INBOUND" callout names each one the first time it shows up.

Special rounds: in rounds 2-6 only Comona Defense can come (about 1 in 3 each); from round 7 on, any round can be
any special (about 1 in 3, never two in a row). Each special comes at most once every 10 rounds. They get harder
the later they come, and from round 12 the Ladons, the Alicorn and AB.L..IN bring escorts.
- COMONA DEFENSE: the EMBDIR Shuttle - CORRIS on the spaceport pad, with its AA guns and SAMs. Protect it through
  the ~2.5 minute countdown. If it's destroyed the shop is closed through the next round.
- THE ANOMALY: the ace MINDRIPPER comes through a lightning portal in an F-4E, hovering in place, with four PHANTASM
  guards. Within 3 km of it your pitch and roll invert. Nothing else flies in its round.
- AMPHIBIOUS ASSAULT: 16 landing craft head for the beaches by the airport; every one that lands puts a BTR ashore,
  which drives for the runway. Each BTR that reaches it captures 25 % of the airfield; at 100 % the airfield is taken
  (no landing, no STORE) until you destroy them or two rounds pass. Fighters (and maybe bombers) come too.
- THE LADONS: KOT and MISHKA come in from the far west and bomb the airfield on every pass until both are down
  (escorted from round 12).
- THE ALICORN: the submarine carrier sails the west sea, diving and surfacing, firing its railgun and missiles.
  Destroy its four ballast tanks to open its core, then the core.
- AB.L..IN (IFF: FATAL ERROR): a lone EA-18G with its jammer always on. Every time you hit it, it vanishes in
  smoke and blinks around you for 6 seconds, nose on you, gun firing. Before round 12 nothing else flies with it.

ONLINE ONLY BEGIN
Leaderboard (Discord)
---------------------
Every run you finish (shot down, restarted, or left) is submitted to the Survival leaderboard on Discord, and a summary
shows how it went: round, score, kills, specials beaten, time. You appear under your Steam name; to use another, set
pilot = Your Name  under [leaderboard] in survival.ini. If you're offline the run is kept and sent next time. Only the
leaderboard's own server is contacted; nothing about your PC is sent besides the run.
If the summary always says NO CONNECTION while your internet works, a firewall or antivirus is blocking the game:
allow AceCombat8.exe outbound access. Runs kept until then are sent automatically afterwards.
Score: 1000 a round reached, 100 an aircraft, 50 a ground or sea target, 3000 a special round beaten, x0.75 Casual,
x1 Standard, x1.5 Ace.

ONLINE ONLY END
OFFLINE: Offline edition
OFFLINE: ---------------
OFFLINE: This edition never connects to the internet: it has no leaderboard code at all. When a run ends (shot down,
OFFLINE: restarted, or left) a summary shows how it went: round, score, kills, specials beaten, time. The Online edition
OFFLINE: submits runs to the Discord leaderboard as well.
OFFLINE: Score: 1000 a round reached, 100 an aircraft, 50 a ground or sea target, 3000 a special round beaten, x0.75 Casual,
OFFLINE: x1 Standard, x1.5 Ace.
OFFLINE:
Settings: ue4ss\Mods\AC8SurvivalMode\config\survival.ini, made the first time you play. Open it in Notepad. Every
setting is listed with its default and switched off by a ; in front of it; remove the ; to change it. Restart the
game after a change. Delete the file to get a fresh one.
- To try the later rounds straight away, find [rounds] and add the line  start_round = 10  (the Anomaly),
  16 (the named aces) or 28 (the Reapers). Take it out again for a normal run.
- Rename the aces under [aces.mercenary] ... [aces.reaper], and MINDRIPPER under [specials.anomaly].
- After an update, new settings are added at the end of your survival.ini (switched off), with their notes.


If something goes wrong
-----------------------
Please send these (and say what you saw, and which AC8 Mod Loader version you have: the first line of
AC8IoStoreLoader.log):
- ...\Win64\ue4ss\UE4SS.log
- ...\Win64\ue4ss\Mods\AC8SurvivalMode\AC8SurvivalMode.log
- ...\Win64\ue4ss\Mods\AC8SurvivalMode\AC8SurvivalMode_lua.log  (kept even when the game crashes)
- ...\Win64\ue4ss\Mods\IoStoreLoaderMod\AC8IoStoreLoader.log
- after a crash: the newest folder in %LOCALAPPDATA%\BANDAI NAMCO Entertainment\ACE COMBAT 8\Saved\Crashes\
  (paste that path into the File Explorer address bar)
Copy the logs right after you close the game (they're rewritten every time it starts).

To uninstall, delete the two folders listed in Install step 2.


Credits
-------
AC8 Survival Mode by voidcallsreaper. Contact: @voidcallsreaper on Discord.
Built only from the game's own files; it doesn't change or replace any other mod's files or missions.
Runs on UE4SS and the AC8 Mod Loader, by their authors.
