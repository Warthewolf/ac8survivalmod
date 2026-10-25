# Survival COOP (research and build of 2026-10-25; Lua 0.70.6-coop.1, runtime 0.20.0)

Two-player co-op for Survival Mode (user, 2026-10-25: "a new 0.70.6 build called Survival COOP ... study these ACE7
coop files ... start fully working on a COOP mod"). **Nothing here has been tested in game yet**: the transport and
interpolation were tested outside the game (tools/checks/coop_test.sh), the game-side RE statically.

## 1. What we learned from Double Trigger (AC7)
`Source_Code_3796_0.3.1` = Double Trigger 0.3.1 (layer10-love/double-trigger, MIT / Unlicense, C++ dinput8 proxy):
- Host-authoritative: the host's game runs the mission; the client mirrors it. Its AI planes on the client are
  "puppets": AGameObject::Tick runs with IsReplaying() answered true (the replay path: no AI, no flight model), and
  the host's state is applied before and after the tick (sync/puppet.cpp, sync.cpp).
- It rides on AC7's own multiplayer stack: the session and the two player planes are AC7's SNL / net planes
  (APlayerPlane + a network dummy controller, SpawnRemotePlane), its own messages go as Steam P2P packets
  (ISteamNetworking SendP2PPacket / ReadP2PPacket on a channel of its own, net/steam.cpp) next to SNL's.
- Everything else is per-system sync: missiles, damage, triggers, mission vars, cutscenes, pause, supply, score.
What Survival took: host authority, puppets, Steam P2P on our own channel without callbacks, the AI split between
players by distance and load. What it didn't: AC8's online stack (Bandai's servers, the game's own sessions: not
needed, and the game's online mode must stay untouched).

## 2. AC8 side (AceCombat8.exe of 2026-09-29)
### Moving an AI plane (the puppet)
Hard rule 39: K2_SetActorLocation is undone by the flight model the next frame; Mission 22's
LiveActorTeleportExecution works. Its Execute (vtable slot 87) = 0x1473eb200; per target it calls the lambda
0x1473eb970, which ends in `call [actor->vtable + 0x5d0]` (slot 186 = AActor::TeleportTo) with
(actor, &FVector loc, &FRotator rot, bIsATest 0, bNoCheck 0).
- ALiveAIPlane vtable 0x14c551db0 (ALiveAIWingmanPlane 0x14c5bbc00 has the same two functions):
  - slot 186 = 0x147d1e390 `ALiveAIPlane::TeleportTo`: if a replay is recording, records a teleport (event 0x1b),
    then calls slot 315.
  - slot 315 (+0x9d8) = 0x147d1e560: `AActor::TeleportTo` (0x143fc1e10: moves RootComponent +0x1a0, encroachment test
    unless bNoCheck) then `this->vtable[0x268](GetComponentByClass(flight component), false)` (slot 77 = 0x143fc2c60):
    the reset that makes the flight model fly on from the new spot.
- Survival COOP calls slot 315 every frame on a puppet with bNoCheck = 1 (no replay record each frame). Before binding,
  the runtime checks the object's vtable holds exactly these two functions (sigs.h kSigAITeleportTo /
  kSigAITeleportInner, found by FindFunctions); anything else is never teleported.
- C++ subclasses of LiveAIPlane (usmap): LiveAIAiasClassPlane (Aias, Celaeno, Ladon, Norn, Podarge), LiveAIBotPlane,
  LiveAIWingmanPlane, LiveAINightmarePlane, LiveAIPlaneDummy, ... The Ladon's vtable wasn't found statically: if it
  overrides teleport, its copies aren't bound (the runtime logs it) and fly their world-data path.
### Where things are read
Reflected, through UE4SS GetValuePtrByPropertyNameInChain once: AActor.RootComponent (+0x1a0), USceneComponent
RelativeLocation / RelativeRotation (root unattached: = world), LiveGameObject.HealthInternal / MaxHealth.
### The per-frame hook
The music player's track clock tick (OnMusicTick, an FTickableGameObject: ticked after every actor's tick group) runs
the co-op frame first thing; BuildFlightInput (the player's input, early in the frame) is the fallback when it hasn't
run for 50 ms. Teleporting late in the frame means the puppet draws where the stream puts it.
### Making a puppet harmless (reflected, LiveAIGameObject / LiveGameObject)
bPermissionToFire, bPermissionToEngage, bPermissionToUseFlares, bPermissionToProvoke, bPermissionToEvade false;
bIsNotLockonTarget true (you can't lock your wingmate); SetIsInvincible(true); bCanBeDamagedByAlly false.
### Damage and deaths
KILLS_HEALTH_DEATH.md: `ModifyHealth(-damage, causer, true)` deals real damage to AI objects (TakeDamage, death, and
DamageHistoryMap[causer]); SetMinHealth(x) keeps an AI object above x. The joiner's copies have MinHealth 0.1: their
health loss is measured and sent to the host, which deals it with the joiner's plane (the host's puppet) as the
cause; the host's deaths come back and the copy is finished with ModifyHealth (the cause the host's puppet), so it
dies as an AI plane does (wreck, explosion) and each game's kill credit follows its own DamageHistoryMap.
### Steam
AC8 ships steam_api64 1.57 (Engine/Binaries/ThirdParty/Steamworks/Steamv157): SteamAPI_SteamNetworking_v006 with
ISteamNetworking SendP2PPacket / IsP2PPacketAvailable / ReadP2PPacket / AcceptP2PSessionWithUser, SteamUser_v021,
SteamFriends_v017 (GetFriendCount / ByIndex / PersonaName / GetFriendGamePlayed), SteamUtils_v010 GetAppID. No
callbacks needed: a session is accepted by sending to that user and by AcceptP2PSessionWithUser (every hello).
Channel 1480. Also ISteamNetworkingMessages_v002 is there (not used).
### Not used (yet)
AC8's own online objects (LiveGameObject.NetworkObject, TargetingPlayerPlanes, LiveAIPlane.NearestPlayerPlane): AC8's
AI already knows several player planes (Online Mode). A real second ALivePlayerPlane for the other player would make
enemies split between players natively; for the first build the other player is an allied AI plane.

## 3. The build
- runtime/coop.c (included in survival_rt.c; runtime 0.20.0): transport (Steam P2P or UDP), hello / reliable / ack /
  unreliable / player state / enemy batch packets (header at the top of coop.c), snapshot interpolation (nlerp,
  120 ms behind by default, extrapolation up to 0.5 s), the per-frame drive. Lua: SV_CoopOpen / Close / Info / Send /
  Recv / Me / Peer / Track / Bind / PeerAt / Reset.
- Scripts/sv_coop.lua: the mirror (see its header): the host wraps SV_Spawn / SV_SetAircraft / SV_SetLevel,
  logPlane, hudCallout, addCredits (inside the rounds only), KILL.side ("wingmate"), LB.send (co-op runs not sent); the
  joiner replaces roundsTick / airfieldTick / bombTick with the host's. Messages: hi, rnd, af, co, cr, sp, bd, hp,
  dn, rs (host), jn, ht (joiner).
- World data: SV_Unit_CoopPeer (one plane of MOONCHILD's source AB_Unit_01_Air1, allied, invincible kept), events
  SV_CoopPeerUp (gear up, no engagement). build_survival.py ally_units, survival_events.py build_allies.
- Packaging: `COOP=1 NOVALKA=1 sh tools/package_release.sh online` (tools/coop_edition.py: CFG.coop.enabled, VERSION
  tag -coop.1, release/README_COOP.txt).
- Offline test: `sh tools/checks/coop_test.sh` (host + joiner over localhost UDP, 20 % loss, then a joiner restart):
  120/120 reliable in order; puppets 0.1 m mean / 0.5 m worst off the true path at render time (200-250 m/s).

## 4. What the first test should check (log lines)
- `coop: open: Steam P2P, host ...` / `coop: looking for the other player: N Steam friend(s)` / `coop: paired with`.
- `coop: offsets: RootComponent +1a0, ...` (reflection read), `coop: AI plane teleport <p>, inner <p>` (both found).
- `coop: the other player's plane is up (..., moved every frame)` - else `NOT moved: -1` (the vtable check refused it).
- Joiner: `coop: a copy couldn't be bound` (should never appear), spawns `the host's X not spawned here` (should be rare).
- The 60 s stats line: `coop: linked, rtt N ms; sent ..., N streams bound (N moves, N failed), peer puppet N moves`.
- In game: smooth wingmate plane where they are; the joiner's hits shoot the host's enemies down on both screens;
  enemies attack the joiner (their copies fire locally on the joiner's game: the open question).

## 5. Known gaps (by design for the first test)
Special rounds' scripted parts (Ladon volleys, the Alicorn's dives and railgun, the shuttle's events, AB.L..IN's
blinks) run on the host only; the joiner sees their aircraft. Ground and sea units (LCACs, BTRs, ships) are spawned on
the joiner too but not streamed or synced. Missiles fired at the other player aren't shown. The other player's
plane flies the enemy NPC row of its airframe (an enemy paint). Allies a joiner buys exist only on their side.
