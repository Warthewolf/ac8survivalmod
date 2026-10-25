SURVIVAL COOP (two players) - FIRST CO-OP TEST
-----------------------------------------------
This build plays Survival Mode with a friend: one of you HOSTS (their game runs the rounds and every enemy), the other
JOINS (sees the host's enemies, rounds, callouts and airfield, and fights them). Each of you sees the other's plane.
Each of you earns your own zollars: an enemy you hit at all pays you in full, one only your wingmate hit pays half.
Each of you lands and shops at your own airfield store. Co-op runs are not sent to the leaderboard.

Both of you install this same build. Then each of you opens
    ...\Win64\ue4ss\Mods\AC8SurvivalMode\config\survival.ini
(it's made the first time Survival Mode runs; if you don't have one yet, start the game once and quit) and adds at
the end:

    The host:                    The joiner:
        [coop]                       [coop]
        role = host                  role = join

That's all if you're Steam friends: the mod finds the friend who's playing ACE COMBAT 8 too. Otherwise add
    partner = <your friend's Steam name>        (or their SteamID64)
On the same network or a VPN (Radmin VPN, ZeroTier, Tailscale) you can go direct instead: both add
    transport = udp
and the joiner adds  partner = <the host's IP address>. The host lets UDP port 27777 through their firewall.

Playing: both start SURVIVAL MODE as usual (same difficulty), the host first. The joiner's screen shows
"CO-OP: WAITING FOR THE HOST" until the two games find each other, then "CO-OP LINKED". The joiner gets no rounds of
their own: their enemies are the host's. If one of you is shot down, retry: you rejoin the same run.

What this first test should tell us (please note what you see):
- Do the games link ("CO-OP LINKED")? Does each of you see the other's plane, where they really are, flying smoothly?
- Joiner: do the host's enemies show up and fly? Do your missiles and gun hits shoot them down (on both screens)?
  Do enemies attack you?
- Host: do enemies go after the joiner's plane too?
- Do round numbers, the NEXT ROUND timer, callouts and the airfield health match?
Known for this test: special rounds run on the host only (the joiner sees their aircraft, not all of their
effects), enemy missiles aimed at the other player aren't shown, and the other player's plane flies an enemy paint.

After playing, BOTH of you send these three files (from ...\Win64\ue4ss\ and its Mods\AC8SurvivalMode folder):
    UE4SS.log, AC8SurvivalMode.log, AC8SurvivalMode_lua.log
