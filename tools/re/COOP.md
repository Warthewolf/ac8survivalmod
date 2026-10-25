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

## 6. A second player plane (research of 2026-10-25, runtime 0.21.0; probe not yet run)
Goal (user, 2026-10-25): the other player as a real player plane, their own aircraft and paint, targeted by the
enemies as a player, instead of an allied AI stand-in.
### What AC8 has for it (Online Mode's Emergency Call co-op, reflected classes with no reflected properties)
`ULiveNetworkPlayerPlane < LiveNetworkGameObject < LiveNetworkBaseObject` (a player plane's network object),
`ALiveNetworkDummyController < AController` (drives another player's plane), `LiveNetworkCoopGameMode`,
`LiveNetworkP2P`, `StrixNetworkFacade` (Online Mode runs on Strix), `ELivePlayerRemoteTypeParam` {None, Both,
LocalPlayer, OtherPlayer}, `ELiveGameObjectUniqueType::OtherPlayer`, `ELiveObjectTriggerFactionType` {AnyPlayer,
LocalPlayer, OtherPlayer, AllyPlayer, AllyOtherPlayer, ...}: the game's AI and events know several players.
`LiveAIBotPlane < LiveAIPlane` + `LiveAIBotConfig` (AIBotPlaneClass, AIBotPlayerPlaneID, AIBotAILevel, bAIBotInvincible):
Online Mode's AI bots fly player aircraft (the fallback if a real second player plane can't work offline).
### Online Mode's remote-player spawn: 0x1471cc490 (owner, int playerIndex, UClass* planeClass)
Called from 0x1471cd2d0, which resolves the class from a plane ID: GameInstance +0x958 / +0x928 / +0x878 ->
0x147360970(+0x878 object, planeId) -> a PlayerPlaneDataTable row; `Reference` (its plane blueprint, a soft class) at
row +0x38, loaded synchronously. In order:
1. `world = GetWorld(owner)`; `ctrl = UWorld::SpawnActor(world, ALiveNetworkDummyController, identity, params)` (0x14465a120;
   params: AlwaysSpawn, MultiplyWithRoot, ObjectFlags 0x48).
2. `plane = SpawnActor<ALivePlayerPlane>(world, planeClass, identity, -, -, 0)` (0x1471e5500: UWorld::SpawnActor +
   IsA(ALivePlayerPlane::StaticClass 0x14708b2f0)). Not deferred: its BeginPlay runs here, unpossessed.
3. `ctrl->vtable[+0x798](plane)`, then `AController::Possess(ctrl, plane)` (0x144354890; the Possess UFUNCTION's thunk
   0x144352da0 calls it).
4. `plane->vtable[+0xc60]()` = 0x147d6ed30: creates its ULiveNetworkPlayerPlane (StaticClass 0x146f0d260) in
   LiveGameObject.NetworkObject (+0xed0) if there is none.
5. From the session's player data (0x147ee0460 / 0x147ee01c0 -> 0x1474a5ae0, 0x1474c5080 by player index): `plane+0x53b8`
   = an id, NetworkObject+0x28 = id | 0x200000000000000, **`plane+0xed8 = 2`** (the network role; 0x1471cbbb7 turns 2
   into 3; the AC7 net plane's "ownership 2" is the same idea), the loadout 0x147d4ad20(plane, arrays), bytes +0xfa0
   / +0xfa1, name strings (+0x6d8), emblem and avatar data. Few places read +0xed8: "another player's" is mostly
   decided by the controller (a dummy controller is never locally controlled).
### Moving it
ALivePlayerPlane vtable 0x14cc01cc8: slot 186 = 0x147d4f6b0 (keeps byte +0x3c04 around the game object's TeleportTo
0x147d1e390), slot 315 = 0x147d4f6f0 (AActor::TeleportTo, the component reset, then on success the player's flight
model reset 0x147d40830(+0x1918, +0x2268, +0x1a38)). Same signature as the AI plane's: coop.c drives either.
### Paint
LivePlayerPlane has PlaneTypeID (reflected) but no reflected skin field or skin UFUNCTION; LiveSkinDataTable rows
(SkinID -> DecalMaterialRef, the skin decal) and LiveAirframeSkinDataTable (materials) hold the paints; the remote
spawn applies the loadout natively from the session data (0x147d4ad20). Open: where the local player's skin ID lives
(campaign context ForceSelectedSkinID / the hangar's selection) and which function applies it to a spawned plane.
### The probe (runtime 0.21.0, test only)
SV_CoopSpawnPP(pawn, x, y, z, yaw) does steps 1-4 and the role byte with a copy of the pawn's own plane class (the
slots, Possess and the role offset read from the remote spawn's code: sigs.h kSigRemote*; the network-object
function checked by its bytes and the reflected NetworkObject offset before it's called). SV_CoopFollow(plane, pawn,
forward, right, up) moves it every frame in formation through slot 315. sv_main.lua Ctrl+F11 / Ctrl+F12 (TEST ONLY).
What the probe should tell: does the spawn survive offline (no session data), does the local camera / HUD / control
stay the local player's, does it look like the player's plane (paint: default?), does it fly in formation smoothly,
do enemies target it (TargetingPlayerPlanes / NearestPlayerPlane), and anything the log or the screen shows wrong.
Log lines: `coop: player plane: spawn ..., remote spawn sites: ...` (all found), `coop: second player plane ...
spawned, controller ..., network object ...`, `test: Ctrl+F11 after the spawn: your pawn is still yours`,
`coop: formation test: N moves, 0 refused`.
