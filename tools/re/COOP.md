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

## 6. A second player plane (research of 2026-10-25, runtimes 0.21.0-0.22.2; probe partly run)
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
   IsA(ALivePlayerPlane::StaticClass 0x14708b2f0)). **Deferred** (it sets bDeferConstruction, flag byte `| 4`): no
   construction or BeginPlay until step 6's FinishSpawning.
3. `ctrl->vtable[+0x798](plane)`, then `AController::Possess(ctrl, plane)` (0x144354890; the Possess UFUNCTION's thunk
   0x144352da0 calls it).
4. `plane->vtable[+0xc60]()` = 0x147d6ed30: creates its ULiveNetworkPlayerPlane (StaticClass 0x146f0d260) in
   LiveGameObject.NetworkObject (+0xed0) if there is none.
5. From the session's player data (0x147ee0460 / 0x147ee01c0 -> 0x1474a5ae0, 0x1474c5080 by player index): `plane+0x53b8`
   = an id, NetworkObject+0x28 = id | 0x200000000000000, **`plane+0xed8 = 2`** (the network role; 0x1471cbbb7 turns 2
   into 3; the AC7 net plane's "ownership 2" is the same idea), the loadout 0x147d4ad20(plane, arrays), bytes +0xfa0
   / +0xfa1, name strings (+0x6d8), emblem and avatar data. Few places read +0xed8: "another player's" is mostly
   decided by the controller (a dummy controller is never locally controlled).
   The loadout `0x147d4ad20(plane, TArray<int32>* list1, TArray<int32>* list2)` makes the loadout object at plane+0x1328
   once (NewObject) and fills it (0x147dd4cb0: list1's ids >= 0 into object+0x30, list2's rows from GameInstance+0x878
   (0x147363300) into object+0x40). list1 is from the session data (0x1474a61a0) or else `0x147ee04c0(world)+0x8258+0x20`;
   list2 from 0x1474a62b0.
6. `AActor::FinishSpawning(plane, &transform, false, NULL, 1)` (0x143fdc360; bHasFinishedSpawning = byte +0x5c bit 0,
   its first test). That runs the construction and BeginPlay: ALiveUnit's BeginPlay (0x147d23f00, vtable slot 114) calls
   vtable +0xa80 = ALivePlayerPlane 0x147d4ccf0, which sets up the weapons `W = plane+0x16a8`: 0x147f55f40(W, plane,
   plane+0x1ae8) stores W+0x2d0 = the plane, reads its +0xfa0 / +0xfa1, and the loadout object (+0x1328) if there is one.
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
SV_CoopSpawnPP(pawn, x, y, z, yaw) does steps 1-6 with a copy of the pawn's own plane class (the slots, Possess, the
role offset, the loadout call and its bytes and FinishSpawning read from the remote spawn's code: sigs.h kSigRemote*;
the network-object function checked by its bytes and the reflected NetworkObject offset before it's called). The
loadout is the pawn's own: its loadout object's two lists and its two bytes.
Solo tests of 2026-10-25: 0.21.0 found no dummy controller class (`/Script/Live.LiveNetworkDummyController`: UE4SS
FindObject wants the short name `LiveNetworkDummyController`; 0.22.1 also falls back to the StaticClass call in the
remote spawn). 0.22.1 spawned and possessed it (your pawn stayed yours, two LivePlayerPlanes) but skipped steps 5's
loadout and 6: the first formation teleport crashed the game (access violation reading 0xfa0 at 0x147d4f419,
weapons + 0x2d0 = NULL, from slot 315's component reset -> 0x147d509ad -> 0x147d4f3e0, the weapons' visibility
update). 0.22.2 does both and won't drive a player plane whose spawn isn't finished (CoCanDrive). It ran: spawn
finished, weapons' owner = the plane, ~3600 formation moves (one a frame) and none refused, your pawn stayed yours; the
copy came in its default paint and flickered in and out (screenshots). Cause: slot 315 fires the BlueprintNativeEvent
OnReposition (ProcessEvent of FindFunctionChecked("OnReposition"); FNames at 0x14e357ef8 OnReposition, 0x14e357f00
OnRestored), whose implementation (vtable +0x888 -> +0x9e0) for a player plane is 0x147d506a0: it resets the plane's
look (0x147d54160, 0x147d4f980 -> 0x147d50710 hides and shows mesh parts, weapons, lock-ons) every call. AI planes'
+0x9e0 differ by class (0x147c8e780, 0x147c66730, 0x147bb5900, base 0x147d1e5d0). 0.22.3 moves a player plane with
slot 315's other steps only (AActor::TeleportTo 0x143fc1e10, flight reset 0x147d40830, word +0x1ad9 = 0; CoTeleport);
AI planes still go through slot 315.
0.22.3 still flickered. 0.22.4's diagnostics (one line a second: where the copy is against where it was put, its
visibility bits) and Ctrl+F11 steps found it (test of 2026-10-25): A (moved, its tick on) the copy sat at the map's
centre (4, 0, 0 m) in ~98% of samples, 12-13 km off its spot, so its own tick puts it there every frame and our move put
it back: the flicker; no visibility bit ever changed. C (left alone, tick on) it jumped there and stayed exactly still,
no flight. B (`SetActorTickEnabled(false)`, moved) it held its spot every sample, solid, with an ALLY tag, but the user
saw it stutter. So with role 2 (another player's) and no network data, its tick holds it at a zero position. Open:
which code does it (not the network object, a 0x180-byte UObject with no own tick; role checks are the vtable
+0xc38..+0xc50 helpers 0x146dc5800..: IsLocal = role != 2, role 3, role 2, role 1), and the stutter. 0.22.5 tests: A tick
off + moved at the music tick, B tick off + moved at the input build, C role 0 + tick on + moved, D role 0 left alone;
and logs how far your plane moves between the input build and the music tick (whether the copy lags a frame).
0.22.5 results (screenshots: a real second Su-57 in default paint, the game's own ALLY tag and W wingman box): tick off,
it holds its spot but stutters; role 0 with its tick on, it flies straight on its own at ~155 m/s and our moves don't
hold it (2 of 3 samples a frame off its spot, its own path steady), so its flight model keeps its own position and
writes it back; the flight reset 0x147d40830 only turns six vectors at +0x1a38 by +0x2268's rotation (+0x2b38),
never the position. B never moved (survival_rt.c's input-build hook runs CoopFrame only when the music tick doesn't)
and the music tick runs 2-3 times within a millisecond each frame, so the timing log learned nothing. 0.22.6: test B
leaves the copy flying (role 0, tick on) and scans its object at 1 s and 2 s for position / velocity triples.
0.22.7 (test of 2026-10-25, user: "test A did not stutter any more"): in a mission the music player's clock never ticks;
every per-frame call comes from the input build (BuildFlightInput, once per player plane, 2-3 a frame), and moving the
copy on every call (not the first of a frame) took the stutter away. So a smooth, solid stand-in is: role 2 (ALLY tag,
W box), its actor tick off (`SetActorTickEnabled(false)`), moved on every input-build call (AActor::TeleportTo + the
flight reset). The scan (copy flying on its own, role 0) found, in the plane object:
- +0x850 FVector location (cm, = the root), +0x868 FRotator (yaw -23 = its heading), +0x880 velocity (cm/s: 15343,
  -6512, 0 = the 1 s move exactly), +0x898 the last frame's move (cm): a unit-level movement cache (AI / missiles?);
  +0xc50 and +0x12f0 hold the previous frame's location.
- +0x19a8 the flight model's (+0x1918) location in cm; +0x19c0..+0x1a20 six points around the plane (cm, world), and
  +0x1a38..+0x1ab0 the same six a frame earlier (what the flight reset writes).
- +0x2b38: the flight state the reset reads (+0x2268 + 0x8d0): two doubles, then the position in metres with Y up
  (+0x2b48 = -Y, +0x2b50 = Z, +0x2b58 = X), in six 0x28-byte entries (+0x2b38, +0x2b60, ... all equal).
With the tick off these go stale (the cache at +0x850 keeps the spawn spot): a stand-in should have them written too. SV_CoopFollow(plane, pawn,
forward, right, up) moves it every frame in formation through slot 315. sv_main.lua Ctrl+F11 / Ctrl+F12 (TEST ONLY).
What the probe should tell: does the spawn survive offline (no session data), does the local camera / HUD / control
stay the local player's, does it look like the player's plane (paint: default?), does it fly in formation smoothly,
do enemies target it (TargetingPlayerPlanes / NearestPlayerPlane), and anything the log or the screen shows wrong.
Log lines: `coop: player plane: spawn ..., remote spawn sites: ...` (all found), `coop: second player plane ...
spawned, controller ..., network object ...`, `coop: second player plane: loadout ..., spawn finished: yes, weapons
..., their owner <the plane>`, `test: Ctrl+F11 after the spawn: your pawn is still yours`,
`coop: formation test: N moves, 0 refused`.

## 7. Since coop.4 (coop.5-coop.11, runtimes 0.23.0-0.26.0, 2026-10-26; untested in game)
- Events: the host forwards every RE_SV_* event it fires ("ev") but each player's own (sv_coop.lua KEEP_EVENTS); a
  joiner fires them once its level is ready. (Nagase's radio and the shuttle never ran on the joiners in coop.4.)
- Tells (behaviour roadmap P3, BEHAVIOUR_DIRECTOR.md unit 4): "tl" from the host to one joiner or every joiner, a
  tell id and up to two numbers only (COOP.tell). The joiner plays it from its own CFG.tells (lines, texts, switches:
  PERSONAL) if it knows the id, the numbers are finite, its level is ready ([coop] callouts on), at most 4 a second,
  never queued. A tell's radio events (RE_SV_Radio*) are in KEEP_EVENTS, and sv_tells.lua plays the host's own
  through the unwrapped hudCallout / SV_Event, so a tell never also goes out as "co" or "ev". Untested in game.
- Fighter roles (behaviour roadmap P1, BEHAVIOUR_DIRECTOR.md unit 5): the host draws the round by role and its
  joiners' copies fly the same world-data units (their behaviour doesn't matter on a joiner: puppets). The Wolf trap's
  per-object holds and frees (RE_SV_WolfHold_<NN><L> / RE_SV_WolfFree_<NN><L>) are forwarded, so a joiner's copy of a
  held plane holds its fire too; its LastTGT turn (RE_SV_WolfTurn_<NN><L>) is in KEEP_EVENTS (onto LocalPlayer: the
  host's game). The host's split hunts (RE_SV_Hunt_NN, unit-wide) skip a Wolf flight while its trap is held. A joiner
  who links after a hold has been fired doesn't get it again (its copies attack it until the trap is freed). Untested.
- The squad director (behaviour roadmap P2, BEHAVIOUR_DIRECTOR.md unit 6) runs on the host only and aims each tactic at
  a player slot (COOP.players(); a joiner's entry now carries `rot`). "dv" (host -> one joiner, COOP.dispatch): one of
  the director's events (RE_SV_Salvo_<NN><L>, RE_SV_Dir*_<NN>, RE_SV_Wolf*_<NN><L>, the flight's own NN), the flight and
  a delay; the joiner fires it on its own copies after the delay (clamped 0-3 s, so the tell's lead is timed there),
  only once its level is ready, only with a live copy of that plane (or flight), at most 8 a second, never queued past
  its delay; "rs" clears the queue. So a bracket salvo aimed at a joiner is fired by that joiner's game (its copies'
  "Player" is the joiner); RE_SV_Salvo_* is in KEEP_EVENTS (never "ev"). A flight's hold and release
  (RE_SV_DirHold_NN / RE_SV_DirFree_NN: top cover, regroup) are forwarded, so a joiner's copies hold their fire too.
  LastTGT steers to the host, so a cover or a dive aimed at a joiner sends the flight hunting (RE_SV_Hunt_NN) with its
  TargetActor kept on that joiner's stand-in for aim_s. The host's split hunt waits while the director holds a flight
  (the hunt's order would free it; as long as the hold lasts, at most top_cover.max_s + 120 s) and goes after; a
  split-hunt flight (COOP.hunted) gets its hunt back when the director lets it go. A joiner who links during a hold gets
  the holds then in force (DIR.holds, RE_SV_DirHold_NN by "ev") 12 s after its hostSync, once its copies are up (the
  Wolf trap's held planes have no such replay). The host's DECOY: nothing of the director's frees a decoyed flight; at
  the decoy's end the director fires RE_SV_DirFree_NN (forwarded), since the kept RE_SV_DecoyEnd_NN never reaches the
  joiners' copies. A joiner's own decoy can still be cut short by a forwarded DirFree. Untested in game.
- The intensity director (behaviour roadmap P4, BEHAVIOUR_DIRECTOR.md unit 7): each game scores its own player once a
  second (intensity, comfort); a joiner sends its scores to the host as "in" (joiner -> host, unreliable, 1 Hz:
  intensity and comfort 0-100, health %, missiles on it; COOP.sendIntensity). The host keeps each joiner's last
  (COOP.intensityOf, at most 3 s old; a bad or non-finite number, its own slot or a slot past 24 dropped, values clamped,
  more than ~4 a second from one player dropped) and decides for the room: the next wave held on the room's highest
  intensity (named after that player in the log), a push on the most comfortable player (a joiner's: the six tell by
  "tl", a hunt with its TargetActor on their stand-in, as a cover), the spike level eased for the room. "rnd" carries
  the level as an 8th field (a whole 0-3, else ignored; an older host's "rnd" has none): a joiner's copies fly it
  (levelFor: rank_min, post-stall, provoke at their first sweep; the enemies up written again when it changes); their
  fire-control rows already come with the host's "sp". Untested in game.
- Boss phases (behaviour roadmap P7, BEHAVIOUR_DIRECTOR.md unit 9) run on the host only (the specials' ticks are
  roundsTick's). MINDRIPPER's pack springs on the host's field alone: RE_SV_AnomalyPackSpring / Hold are in
  KEEP_EVENTS (its LastTGT steers to LocalPlayer; the guards are puppets on a joiner), and the "pack" tell is the
  host's own; a joiner's own field (ANOM.clientTick) never springs it. AB.L..IN's phase 2 blinks are around the host
  (RE_SV_GlitchBlink_*, kept), its "glitch_six" tell the host's; its phase 3 LastTGT (RE_SV_GlitchTurn) is kept by
  mirroredEvent's RE_SV_Glitch rule, its "glitch_allout" tell goes to every player ("tl"), and its gun events
  (RE_SV_GlitchGun, forwarded) fire on each joiner's copy at that joiner while the host is close in front of it; the
  host stops RE_SV_GlitchEcm (forwarded, so a joiner's copy's pod lapses too; its own row refires it at most once a
  minute there) and switches its own pods off (the joiners' aren't). A Ladon's RE_SV_LadonRage<Key> is forwarded
  (harmless: the copies follow the stream); its callout is the round's ("co"), its tell every player's. The ALICORN's
  deck launches go through spawnFlight with a pose, which the SV_Spawn wrapper mirrors (pose, aircraft, level); its
  callout is the round's, its "alcn_deck" tell every player's. Untested in game.
- Joining: SURVIVAL CO-OP: HOST and SURVIVAL CO-OP: JOIN on the main menu (DT_SV_MenuRows rows with StringArgs
  SurvivalHost / SurvivalJoin; OnMainDecide sets SV_MenuChoice 3 / 4; Lua opens co-op as that role, no ini). JOIN
  never hosts by itself; TWO HOSTS says only one picks HOST.
- Names: each stand-in's AI desc shows a callsign (bShowCallSignForAlly, GameObjectDisplayNameID02 =
  SV_CoopName_<slot letter>), set to the player's name with SV_SetText. A co-op row on the HUD lists the players.
- Pause: while another player is linked, the pause menu opens but the game is unpaused from Lua's 250 ms tick.
- Protocol 3, up to 24 players: a joiner sends its own plane to the host (P, 30 Hz); the host sends each joiner one Q
  packet of every other player's latest state (49-byte records: 23 fit in 1132 bytes), at 30 Hz up to 6 players and
  20 Hz past that (relaying every P to every joiner was n x n packets: ~16,000 a second at 24). Message slots are
  decimal ("12|..."). The offline test runs 4 and 12 players: 0.6 m worst off the true path at 20 % loss.
  Bandwidth, the host's upload: ~25 KB/s of planes per joiner at 24 players, plus the enemy stream (22 bytes an enemy,
  15 Hz).
- More players, more enemies: CFG.coop.aircraft_per_player (0.15) more of a round's and a wave's aircraft for each
  player past the first, up to coop.max_aircraft (60) / coop.max_up (30) (COOP.more, sv_rounds.lua startRound). From
  CFG.late.aircraft_from_round (26) the round's 60 grows as one player's cap does, up to late.coop_max_aircraft (80 by
  round 32; TIER.coopCap, BEHAVIOUR_DIRECTOR.md unit 3).
- The host's settings for everyone: on a joiner's first hello the host sends "cf" chunks of its CFG's differences from
  CFG_DEFAULTS (the shipped CFG, copied before survival.ini and survival_config.lua apply), as data only (a small
  token format, no code). The joiner puts every shared section back to CFG_DEFAULTS and applies them, in place (other
  parts hold CFG's tables), and gets its own back when co-op closes or it hosts. Its own: coop, hud, sound, music,
  leaderboard, tells (and probe, ai_watch, stats). presetName() answers the host's preset on a joiner.
- Settings rows under JOIN: CO-OP ROOM, CO-OP ENEMIES, START AT ROUND, BREAK BETWEEN ROUNDS (StringArgs SV_Set_<what>).
  main.dll's OnMainDecide queues the pick and doesn't call the stock decide (as the landing menu's SV_Buy_ rows), Lua
  (SV_MenuSetting) steps the value, saves it with iniSet and relabels the row's live TextBlock. A run that started past
  round 1 isn't sent to the leaderboard.
- Code review and security review of coop.11: the Anomaly's field is each player's own (the host's field events aren't
  forwarded; a joiner runs ANOM.clientTick on its distance to its copy); events that arrive while a joiner's level
  loads are held and fired when it's ready; any other main-menu entry closes co-op and the same entry picked again
  retries (SV_MenuChoice = entry + 16 x picks); the online pause counts live links only; the host's preset comes with
  its difficulty number. Guards on what other games send: coop.c CoSaneState (finite positions within 100,000 km, unit
  rotations), sv_coop.lua knownRow / standInRow / slotOk / short / finite, the settings sync's fits (same type and
  size as the shipped setting; build data such as unit lists never synced). tools/checks/coop_settings_test.sh's
  "guard" role and coop_test.sh's guard line test them.
