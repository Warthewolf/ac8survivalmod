SURVIVAL COOP (up to 4 players) - CO-OP TEST
-----------------------------------------------
This build plays Survival Mode with up to three friends: one of you HOSTS (their game runs the rounds and every
enemy), the others JOIN (they see the host's enemies, rounds, callouts and airfield, and fight them). Everyone sees
everyone else's plane. Each of you earns your own zollars: an enemy you hit at all pays you in full, one only your
wingmates hit pays half. Each of you lands and shops at your own airfield store. Co-op runs are not sent to the
leaderboard.

Everyone installs this same build. Nobody has to set anything: each game looks for a host among your Steam friends
playing ACE COMBAT 8, joins the one it finds, and hosts itself if it finds none within 20-40 seconds. So the one who
should host just starts first (or, to be sure, adds  role = host  under [coop] in their survival.ini, below).

Settings go in
    ...\Win64\ue4ss\Mods\AC8SurvivalMode\config\survival.ini
(it's made the first time Survival Mode runs; edit survival.ini, not survival.default.ini) under a [coop] line:

    The host (optional):         Everyone who joins (optional):
        [coop]                       [coop]
        role = host                  role = join

If several of your friends play AC8, a joiner can name the host:
    partner = <the host's Steam name>        (or their SteamID64)
On the same network or a VPN (Radmin VPN, ZeroTier, Tailscale) you can go direct instead: everyone adds
    transport = udp
and each joiner adds  partner = <the host's IP address>. The host lets UDP port 27777 through their firewall.
The host can take fewer players with  max_players = 2  (or 3).
Your name on the other players' screens ("REAPER JOINED") is your Steam name; to pick another, add under [coop]:
    name = Reaper                            (up to 20 characters; restart the game after changing it)

Playing: everyone starts SURVIVAL MODE as usual (same difficulty), the host first. The host's screen shows
"CO-OP: YOU ARE THE HOST"; a joiner's shows "CO-OP: LOOKING FOR A HOST" until the games find each other, then
"CO-OP LINKED"; everyone sees "<NAME> JOINED" as players come in. Joiners get no rounds of their own: their enemies are the host's. If one of you is shot down,
retry: you rejoin the same run. If the host retries, the run starts over for everyone.

What this test should tell us (please note what you see):
- Do all the games link? Does each of you see every other player's plane, where they really are, flying smoothly?
- Joiners: do the host's enemies show up and fly? Do your missiles and gun hits shoot them down (on every screen)?
  Do enemies attack you?
- Host: do enemies go after the joiners' planes too?
- Do round numbers, the NEXT ROUND timer, callouts and the airfield health match?
Known for this test: special rounds run on the host only (joiners see their aircraft, not all of their effects),
enemy missiles aimed at another player aren't shown, and the other players' planes fly in enemy colours.

After playing, EVERYONE sends these three files (from ...\Win64\ue4ss\ and its Mods\AC8SurvivalMode folder):
    UE4SS.log, AC8SurvivalMode.log, AC8SurvivalMode_lua.log
