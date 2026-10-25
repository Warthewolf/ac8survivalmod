SURVIVAL COOP (up to 4 players) - CO-OP TEST
-----------------------------------------------
This build plays Survival Mode with up to three friends: one of you HOSTS (their game runs the rounds and every
enemy), the others JOIN (they see the host's enemies, rounds, callouts and airfield, and fight them). Everyone sees
everyone else's plane. Each of you earns your own zollars: an enemy you hit at all pays you in full, one only your
wingmates hit pays half. Each of you lands and shops at your own airfield store. Co-op runs are not sent to the
leaderboard.

Everyone installs this same build. Then each of you opens
    ...\Win64\ue4ss\Mods\AC8SurvivalMode\config\survival.ini
(it's made the first time Survival Mode runs; if you don't have one yet, start the game once and quit) and adds at
the end:

    The host:                    Everyone who joins:
        [coop]                       [coop]
        role = host                  role = join

That's all if each joiner is a Steam friend of the host: the mod finds the friend who's playing ACE COMBAT 8 and
hosting. If several of your friends play AC8, a joiner can name the host:
    partner = <the host's Steam name>        (or their SteamID64)
On the same network or a VPN (Radmin VPN, ZeroTier, Tailscale) you can go direct instead: everyone adds
    transport = udp
and each joiner adds  partner = <the host's IP address>. The host lets UDP port 27777 through their firewall.
The host can take fewer players with  max_players = 2  (or 3).
Your name on the other players' screens ("REAPER JOINED") is your Steam name; to pick another, add under [coop]:
    name = Reaper                            (up to 20 characters; restart the game after changing it)

Playing: everyone starts SURVIVAL MODE as usual (same difficulty), the host first. A joiner's screen shows
"CO-OP: WAITING FOR THE HOST" until the games find each other, then "CO-OP LINKED"; everyone sees "<NAME> JOINED"
as players come in. Joiners get no rounds of their own: their enemies are the host's. If one of you is shot down,
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
