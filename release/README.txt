AC8 Survival Mode - test build {DATE} (Lua {LUA}, runtime {RT})
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
4. Start the game. SURVIVAL MODE is on the main menu, above QUIT GAME.


Play
----
Main menu -> SURVIVAL MODE -> pick a difficulty -> hangar -> sortie. You start over Comona Airport.
- Shoot down every enemy to clear a round; the next one starts 20 seconds later.
- Bomber raids (every 3rd round) go for the airfield. At 0 health it's down: no landing for the rest of that round
  and the next one, then it comes back at half health.
- Ammo: you take off with your difficulty's load, and landing does NOT refill it. Buy more at the airfield.
- Land at Comona Airport between rounds and pick STORE on the landing menu. It has two pages:
    SUPPLIES: MISSILES +12 / SPECIAL WEAPON +4 / FLARES +2 (loaded straight onto your aircraft, same price every
              time), REPAIR AIRCRAFT (to full health), AIRFIELD > and TAKE OFF
    AIRFIELD: REPAIR AIRFIELD, BUILD AA GUN, BUILD SAM SITE (defences that fire at enemies on their own: 5 AA guns,
              2 SAM sites; expensive), < SUPPLIES and TAKE OFF
  Each item has its icon; the bottom line says what it does and how many zollars you have. (If the STORE can't be
  added on your setup, the landing menu shows the four shop rows instead.)
- Pause menu -> Music Player picks your music.

Enemy pilots: they get better as the rounds go (Rookie, Regular, Veteran, Elite, Ace, then Mercenary, Legend, Demon,
Phantom and Reaper from round 16). Rounds 8, 15 and 22 are difficulty spikes. Better pilots sit on your tail, break,
flare, and from Mercenary up use cobra / kulbit baits and scissors.

Named aces (ace rounds: 16, 19, 22, ... - only ace squadrons, no bomber raids; the rounds between are normal): each rank flies its own squadron - F-15C, Su-35, Typhoon, Su-47, Rafale, F-22A, Su-57 and,
for the Reapers, an ADFX-02. Their leaders are named aces (Ledger, Sigrun, Mephisto, Specter, Grim, Oblivion, ...);
an "ACE INBOUND" callout names each one the first time it shows up.

Special rounds (round 5, then every 5th, in turn):
- COMONA DEFENSE: the EMBDIR Shuttle - CORRIS on the spaceport pad, with its AA guns and SAMs. Protect it through
  the ~2.5 minute countdown. Liftoff pays 3000 zollars; if it's destroyed the shop is closed through the next round.
- THE ANOMALY (round 10, 20, ...): the ace MINDRIPPER comes through a lightning portal in an F-4E, hovering in place,
  with four PHANTASM guards circling it. It's tough and very aggressive, and it carries an ECM pod (its area shows on
  the radar; your missiles miss more near it). Within 3 km of it your pitch and roll invert. Shoot it down for 4000
  zollars and your controls come back. Nothing else flies in its round.

Settings: ue4ss\Mods\AC8SurvivalMode\config\survival.ini, made the first time you play. Open it in Notepad. Every
setting is listed with its default and switched off by a ; in front of it; remove the ; to change it. Restart the
game after a change. Delete the file to get a fresh one.
- To try the later rounds straight away, find [rounds] and add the line  start_round = 10  (the Anomaly),
  16 (the named aces) or 28 (the Reapers). Take it out again for a normal run.
- Rename the aces under [aces.mercenary] ... [aces.reaper], and MINDRIPPER under [specials.anomaly].
- After an update, new settings are added at the end of your survival.ini (switched off), with their notes.


Test keys (in a Survival run)
-----------------------------
- Ctrl+F11: the next round is THE ANOMALY (between rounds it starts at once).
- Ctrl+F10: mark a beach (fly low over it): the coming amphibious-assault round will land there. Marks go into
  AC8SurvivalMode\config\coast_marks.txt - please send that file too.


If something goes wrong
-----------------------
Test shortcut: Ctrl+F8 on the main menu loads Survival's map directly, skipping the hangar. If the normal way
crashes or shows a black hangar, try this and say whether it works.

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
