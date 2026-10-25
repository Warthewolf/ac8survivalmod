SURVIVAL CO-OP (up to 4 players)
--------------------------------
HOW TO PLAY TOGETHER
  1. Everyone installs this same build.
  2. Everyone picks SURVIVAL CO-OP on the main menu (just under SURVIVAL MODE).
  That's all. The first one in hosts; everyone after joins them. Your Steam friends who are playing find each other by
  themselves. SURVIVAL MODE still plays alone, as before.

On screen, under AIRFIELD:
  CO-OP: LOOKING FOR A HOST...                    your game is looking for a friend who is playing
  CO-OP: YOU ARE THE HOST, WAITING FOR FRIENDS    nobody else was playing: you host, friends join you
  CO-OP 3/4: WAR (HOST)  CRESSENDO  REAPER        who is playing, the host first
Each friend's plane carries their name on its target box. "<NAME> JOINED" shows as players come in.

The host's game runs the rounds and every enemy; the others fight the same enemies, see the same rounds, callouts and
airfield, and everyone sees everyone else's plane. Each of you earns your own zollars: an enemy you hit at all pays you
in full, one only your wingmates hit pays half. Each of you lands and shops at your own airfield store. If one of you is
shot down, retry: you rejoin the same run. If the host retries, the run starts over for everyone. Co-op runs are not
sent to the leaderboard.

Optional settings (none are needed), in ...\Win64\ue4ss\Mods\AC8SurvivalMode\config\survival.ini under a [coop] line
(made the first time Survival Mode runs; edit survival.ini, not survival.default.ini; restart the game after a change):
    role = host                 always host (or  role = join  to only ever join)
    name = Reaper               your name for the others (up to 20 characters; your Steam name otherwise)
    partner = <a Steam name>    join this friend only (or their SteamID64), when several friends play AC8
    max_players = 2             the host takes fewer players (2 or 3)
    transport = udp             same network or a VPN (Radmin VPN, ZeroTier, Tailscale) instead of Steam: the joiners
                                also set  partner = <the host's IP address>; the host lets UDP port 27777 through

What to tell us after playing: did everyone link, did each of you see the others' planes (and names) flying smoothly,
did enemies attack every player, did the specials (the shuttle's countdown and launch, Nagase's radio) play for
everyone? Known: enemy missiles aimed at another player aren't shown, and the other players' planes fly in enemy colours.

After playing, EVERYONE sends these three files (from ...\Win64\ue4ss\ and its Mods\AC8SurvivalMode folder), copied
before starting the game again:
    UE4SS.log, AC8SurvivalMode.log, AC8SurvivalMode_lua.log
