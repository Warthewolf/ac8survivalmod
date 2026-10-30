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
    unless bNoCheck) then `ProcessEvent(this, FindFunctionChecked(OnReposition), NULL)` (vtable +0x268 = slot 77 =
    0x143fc2c60 is AActor::ProcessEvent, not a component reset; FName OnReposition at 0x14e357ef8). The event's native
    thunk (+0x888 = 0x147d1e5c0) jumps to the class's OnReposition_Implementation (+0x9e0): ALiveAIPlane's 0x147bb5900
    resets the plane's flight engine (+0x910), its speed to normal (vfunc +0x948 with +0x2bd4) and two movement caches,
    and ends in `EnableTakeoffAfterburner(false)` (0x147ccf3f0): **every teleport puts an AI plane's afterburner out**.
    That reset is what makes the flight model fly on from the new spot. (Corrected 2026-10-30, runtime 0.28.5: until
    then this note read slot 77 as a flight-component reset; the stand-ins' missing afterburners were this.)
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
DamageHistoryMap[causer]); SetMinHealth(x) keeps an AI object above x (whole points only: the copies' SetMinHealth(0.1) below is 0 in fact, so a
joiner's copy can go down on its own game before the host's does; left so, 2026-10-30). The joiner's copies have MinHealth 0.1: their
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
### Flight sync natives (runtime 0.28.5, runtime/flight.c and coop.c, 2026-10-30; untested in game)
Section 8 is the Lua side. Addresses are this exe's; the runtime finds each by its signature (sigs.h) and checks the
code's shape before use. [V] verified by reading the code, [I] inferred, [?] a guess for the test to settle.
- **SV_CoopFire(shooter, slot, target) -> 1 or an SV_ERR code.** The game's one-shot fire `bool FireOne(AActor* shooter,
  u8 weaponNumber, AActor* target, const FVector* offset, u64 arg5)` 0x147c8fe20 (kSigFireOne, 55 bytes, unique), the
  call ULiveFireOneShotWeapon::Execute (0x1473ed1e0, vtable 0x14c683190; kSigFireExec) makes at +0x363 with the node's
  weapon number (+0x58), the resolved target, a zero offset and the node's +0x70 (8 bytes: its string argument as an
  FName, "" in the stock records HELIOS_VFX.md lists [I]: 0 here). The runtime checks that call goes to the function it found [V]. weaponNumber is ELiveWeaponNumber,
  WN_WEAPON_1..6 = 0..5 = the fire-control slot (usmap enum; hard rule 40) [V]. FireOne returns false (fires nothing)
  unless the shooter's active byte +0x3f4 is set, its dead flag +0xdb8 clear, HealthInternal +0xda8 > 0 and its
  FireControlSystemComponent +0xfa8 live [V]; then it records a replay shot, gives every weapon module the target
  (0x147c09c70) and triggers module `slot` (0x147c0aa20: `0 <= slot < module count`, else nothing) [V], and returns
  true: queued, not proof a missile left (the module's own checks, a fire permission among them, aren't traced) [?].
  The target is read as a game object (weak pointer, root component, vfuncs +0xae8 / +0xaf0 / +0x8e8, its alive
  fields), so the runtime takes only 0 or a live LiveGameObject (its class has the reflected HealthInternal at +0xda8,
  where FireOne reads it). The shooter must be live, an AI plane (coop.c CoKind 1: the AI plane's teleport in slots
  186 / 315, so never a player plane), its class with FireControlSystemComponent at +0xfa8. At most 25 calls a second a
  shooter. Codes: -4 bad args (no shooter, slot not a whole 0-5), -5 the function or its offsets not found, -10 over 25
  this second, -11 FireOne returned false, -13 not a live AI plane with a fire-control system, -14 the target isn't a
  live game object. Every offset is read from FireOne's own code (+0x2a, +0x43, +0x51, +0x71); HealthInternal's and the
  FCS's must equal the reflected ones on the shooter's (and the target's) class.
- **The flag bits** (SV_CoopMe's second argument; agreed with sv_coop.lua): 1 in Survival's level, 2 alive, 4 on the
  airfield, 8 DOWN (revive), 16 gear down, 32 afterburner, 64 gun firing, 128 flares (coop.c CO_FLAG_*). Checked end to
  end [V, tools/checks/flight_test.sh]: SV_CoopMe keeps all 32 bits (a negative or huge number gives 0), a joiner's P
  carries them (+56 of its body) into the host's CoOnPlayer, the host's Q record (+45) out to the joiners; CoSaneState
  looks at the position and rotation only. SV_CoopPeerAt shows them.
- **The stand-ins' afterburner**: the AI plane's afterburner byte is +0x29b8, read from EnableTakeoffAfterburner's
  `mov byte [rbx + disp32], dil` at +0x82 (kSigTakeoffAB, 46 bytes, unique; the UFUNCTION's exec 0x146d43350 calls it)
  [V]. Its surface component's update (0x147d333a0, `[component + 0x190]` = the plane) ramps the afterburner effect in
  while the byte is set, out while not (or on its own acceleration / speed tests) [V: the code; I: that it is the
  glow]. Each slot 315 move clears it (above), so CoDrive writes it again right after every successful move of an AI
  stand-in: 1 while that player's latest flags have bit 32, else 0 [V: flight_test.sh with a fake plane; ?: in game].
- **SV_InputNow() -> "pitch,yaw,roll,throttle,brake,highg"** (each x1000, whole numbers; "" before any) from the last
  BuildFlightInput of the local player's plane (PlayerOwner(world) of Survival's level, else SV_CoopMe's plane, else
  the plane input was last built for): its out after SV_Invert and DOWN, what the flight engine got. [V] out+0xC
  throttle = clamp(InputThrottle, 0, 1), +0x10 brake 0..1, +0x14 high-G = (throttle + brake) x k (brake alone on the
  single-button option); FlightEngine::SetInput (0x144d32580) clamps throttle to 0..1 again (and forces 1 in one of
  its modes). 0 is neutral (cruise speed in AC8), so the afterburner is a held throttle: AceFlightEnginePlayerParameter
  has AfterburnerWait / PowerAfterBurnerR / MaxSpeedAfterBurnerR; no threshold is in the input path itself [I]. The
  ab_throttle 0.9 of section 8 is a guess to calibrate from the log.
- **Log lines** (AC8SurvivalMode.log): at start `flight: one-shot fire <p> (LiveFireOneShotWeapon's Execute <p>), AI
  takeoff afterburner <p>, player plane respawn <p>` (none NULL); on the first SV_CoopFire `coop fire: one-shot fire
  <p> ...: active byte +3F4, dead flag +DB8, HealthInternal +DA8, fire-control system +FA8; at most 25 shots a second
  per shooter`; per shooter its first result `coop fire: AI plane <p>, slot N, at <p>: queued (the game's fire returned
  true)` (or `returned false ...`); each kind of refusal once `coop fire: refused (<code>): <why> ...`; once a minute
  with shots `coop fire: N shots queued, N refused by the game ..., N over 25 a second, N bad calls`; the first stand-in
  move `coop: the AI plane's afterburner byte is +29B8 (EnableTakeoffAfterburner <p>) ...`; per player once a binding
  `coop: player N's afterburner on: their stand-in <p>, byte +29B8 (flags <hex>)`.
- **What the test must confirm**: the missiles leave the stand-in and fly at the target (FireOne queues them with its
  fire permission off?); slot 1 shows the gun and slot 0 flares; `returned false` never for a live stand-in; the
  stand-in's afterburner glows on the other screens at full throttle (the byte written after each move is enough, and
  nothing else turns it out between the move and the component's tick); which SV_InputNow throttle value matches the
  afterburner.

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
- Another player's airframe [V: the bug; the fix I]: it comes in their "hi" (host) or the host's "pi" (joiners), sent
  again once their plane is up (the main menu's has none). Until 0.72.1 the stand-in spawned the moment their state
  said "in Survival's level", on whatever row was known then, so a "hi" a moment late left it the default F-16C for the
  whole run (the user's co-op run of 2026-10-29, three players: "players are flying F-16's on my side but different
  aircraft on their side"; the log's "flies " empty). Now peerTick waits up to 5 s (AIRFRAME_WAIT_S) for a row, then
  flies the default, said so: `coop: player N's plane as <row> (no airframe from them in 5 s): spawned`. A later change
  is logged (`coop: player N flies <row> (their plane here stays <row> until their next sortie)`): an AI plane that's up
  can't change airframe, and there's no despawn for a stand-in. tools/checks/coop_landing_test.sh has the cases.
- Each player's runtime: the host compares a joiner's "hi" runtime with its own (`coop: WARNING: player N runs runtime
  ...`, a CO-OP RUNTIME MISMATCH callout). Until runtime 0.28.4 SV_Version() answered a fixed "0.27.0" whatever the
  build (so the same run's "runtime 0.27.0" for both friends, and for the host, said nothing about their main.dll);
  from 0.28.4 it's the build's own (RT_VERSION_A).

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
- Tells (behaviour roadmap P3, BEHAVIOUR_DIRECTOR.md unit 4; radio lines only since the clean up of 2026-10-29, no
  HUD callout): "tl" from the host to one joiner or every joiner, a tell id and the number its line is picked by
  (the o'clock) only: `tl|<id>|<a>` (COOP.tell; it carried a second number for the callouts' texts before). The joiner
  plays it from its own CFG.tells (lines, switches: PERSONAL) if it knows the id, the number is finite, its level is
  ready, at most 4 a second, never queued; [coop] callouts (the host's banners, "co") no longer gates it. A tell's radio
  events (RE_SV_Radio*) are in KEEP_EVENTS, and sv_tells.lua plays the host's own through the unwrapped SV_Event, so a
  tell never also goes out as "ev". Untested in game.
- Fighter roles (behaviour roadmap P1, BEHAVIOUR_DIRECTOR.md unit 5): the host draws the round by role and its
  joiners' copies fly the same world-data units (their behaviour doesn't matter on a joiner: puppets). The Wolf trap's
  per-object holds and frees (RE_SV_WolfHold_<NN><L> / RE_SV_WolfFree_<NN><L>) are forwarded, so a joiner's copy of a
  held plane holds its fire too; its LastTGT turn (RE_SV_WolfTurn_<NN><L>) is in KEEP_EVENTS (onto LocalPlayer: the
  host's game). The host's split hunts (RE_SV_Hunt_NN, unit-wide) wait while a Wolf flight's trap is pending or held
  and go once it's let go (code review of 2026-10-29: they were dropped, so no Wolf flight ever split). A joiner
  who links after a hold has been fired doesn't get it again (its copies attack it until the trap is freed). A joiner's
  copies' health cut by its own late-rounds / role scaling (a Skirmisher's x0.75) moves what clientTick expects
  (COOP.copyScaled), so it never goes to the host as that player's hit ("ht"; the same review: it took the host's
  Skirmishers to x0.5). Untested.
- The squad director (behaviour roadmap P2, BEHAVIOUR_DIRECTOR.md unit 6) runs on the host only and aims each tactic at
  a player slot (COOP.players(); a joiner's entry now carries `rot`). "dv" (host -> one joiner, COOP.dispatch): one of
  the director's events (RE_SV_Salvo_<NN><L>, RE_SV_Dir*_<NN>, RE_SV_Wolf*_<NN><L>, the flight's own NN), the flight and
  a delay; the joiner fires it on its own copies after the delay (clamped 0-3 s, so the tell's lead is timed there),
  only once its level is ready, only with a live copy of that plane (or flight), at most 8 a second, dropped once 1 s
  past its time (a level that stopped being ready meanwhile; code review of 2026-10-29); "rs" clears the queue. So a bracket salvo aimed at a joiner is fired by that joiner's game (its copies'
  "Player" is the joiner); RE_SV_Salvo_* is in KEEP_EVENTS (never "ev"). A flight's hold and release
  (RE_SV_DirHold_NN / RE_SV_DirFree_NN: top cover, regroup) are forwarded, so a joiner's copies hold their fire too;
  a joiner fires a hold (a Wolf trap's too) only once that flight's copy there has been up 3 s (its own appearance
  orders, 2 s after it appears, would undo it), its release dropping one still waiting (code review of 2026-10-29).
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
  mirroredEvent's RE_SV_Glitch rule, its "glitch_allout" tell goes to every player ("tl"), and its phase-3 gun events
  (RE_SV_GlitchGun outside a frenzy) fire on the host's game alone (COOP.eventHere; code review of 2026-10-29: forwarded,
  each joiner's copy fired at that joiner on the host's geometry), a frenzy's still forwarded; the
  host stops RE_SV_GlitchEcm (forwarded) and switches its own pods off, and its "rnd" carries AB.L..IN's phase (the
  9th field: 1-3, else empty; a joiner takes only 1-3 as D.glitchPhase), so a joiner's ANOM.clientGlitch switches its
  copy's pods off too every ecm_check_s while the host's is in phase 3 (its own row would refire them every 14 s; code
  review of unit 9). The phase tells are sure ones: the host sends them through its gaps, and a joiner says them
  through its own gap and their cooldown (not with its tells off, at its airfield or within the lines' line_gap_s). A
  Ladon's RE_SV_LadonRage<Key> is forwarded (harmless: the copies follow the stream); its tell is every player's (its
  ENRAGED callout is gone: the clean up of 2026-10-29). The ALICORN's deck launches go through spawnFlight with a pose,
  which the SV_Spawn wrapper mirrors (pose, aircraft, level); its "alcn_deck" tell is every player's (no PLANES
  LAUNCHING callout now). Untested in game.
- Ace personalities (behaviour roadmap P9, BEHAVIOUR_DIRECTOR.md unit 10) run on the host only (ACE.squadTick returns on
  a joiner; the squadrons' role mix is the host's startRound, the openers its sv_main tick). A squadron flight opens on
  whichever player (COOP.players()) its planes reach first: that player's squadron tell ("tl": its id; a radio line,
  no squadron-named callout since the clean up of 2026-10-29), and what reaches them: the "high" salvo on that joiner's
  own copies ("dv", RE_SV_Salvo_<NN><L>, gap_s apart), the kulbit (RE_SV_AceKulbit_NN, kept: the planes' own move the
  stream shows), the trap freed without its turn (RE_SV_WolfFree forwarded; WolfTurn would steer to the host); a blink is
  round the host's plane only (RE_SV_WraithBlink<K><J> in KEEP_EVENTS: its "Player" is the host), so a joiner gets only
  the tell. The blink tick reads the host's player alone. A blinking lead's new place reaches joiners in the plane
  stream. The next friend build: COOP_TAG -coop.18 (new events). Untested in game.
- Joining: SURVIVAL CO-OP: HOST and SURVIVAL CO-OP: JOIN on the main menu (DT_SV_MenuRows rows with StringArgs
  SurvivalHost / SurvivalJoin; OnMainDecide sets SV_MenuChoice 3 / 4; Lua opens co-op as that role, no ini). JOIN
  never hosts by itself; TWO HOSTS says only one picks HOST.
- Names: each stand-in's AI desc shows a callsign (bShowCallSignForAlly, GameObjectDisplayNameID02 =
  SV_CoopName_<slot letter>), set to the player's name with SV_SetText. A co-op row on the HUD lists the players:
  since the code review of 2026-10-29 behind the HUD's info key (I, [hud.info]; untested in game), hidden until it's
  pressed but for a peek_s peek when a player joins, drops or is shot down, open a line a player (FLYING / AT THE
  AIRFIELD / DOWN / NOT IN THE MISSION, health; tools/re/HUD_LAYOUT.md).
- Pause: while another player is linked, the pause menu opens but the game is unpaused from Lua's 250 ms tick.
- The host's landing (user, 2026-10-29: "when the HOST is landed at the airfield that the game isn't paused for the
  other players"; Shazzy's host log of 2026-10-25: spawns held 10-43 s in rounds 3, 4, 6 and 7). Solo, spawns wait while
  you're down at the airfield (a flight that appears with the landing menu up gets no orders: test of 2026-10-22). A
  co-op host now holds only while no other player flies (sv_rounds.lua othersFlying: COOP.players() alive, fresh, not
  on the airfield): the spawns go on (`round N: spawns go on while you're down at the airfield (1 other player
  flying)`, once a round), ordersTick fires RE_SV_FlightOrders_NN orders_check_s after a spawn and every 5 s while the
  host is down, none counted as a try (whether it fires with the landing menu up is unknown; the 3 tries come after the
  takeoff as ever), the wave clock (waves.timeout_s) runs, and the ALICORN's deck launches. The Wolf trap's 30 s for
  its orders don't count the host's time on the airfield (solo too), and its hold comes hold_after_s after its orders
  while another player flies (solo, or with nobody else flying, at the host's takeoff: F5's review, round 2). The
  shuttle's countdown runs on too and the shuttle isn't made invulnerable (user, 2026-10-29: "Keep it running while
  others are flying"; `special: shuttle countdown running while you're down at the airfield (1 other player flying) at
  N s`, logged as it's held or runs, not as the count changes; whether its events take with the landing menu up is
  unknown: the first not sent then is logged, `special: shuttle countdown event RE_SV_ShuttleT_N not fired (...)
  while you're down at the airfield`, and the lift-off line says `event package` or `countdown over`); with nobody
  else flying it's held and invulnerable as solo, and can be hit again at another player's takeoff or the host's. A
  joiner's game holds nothing on the host's landing (its copies come as the host's "sp" do; it runs no countdown of
  its own, the host's RE_SV_ShuttleT_* come forwarded). Untested in game (tools/checks/coop_landing_test.sh).
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
  parts hold CFG's tables), and gets its own back when co-op closes or it hosts. Its own (sv_coop.lua PERSONAL): coop,
  hud (the info key's [hud.info] too), sound, music, leaderboard, menu, tells, profile and flares (P6's learning layer:
  each game's own habits and AI flare row), and probe, ai_watch, stats, log (the test logs; [log] verbose).
  presetName() answers the host's preset on a joiner.
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

## 8. Weapons, gear and afterburner (Lua 0.72.2, runtime 0.28.5, 2026-10-29; untested in game)
The user, playing three-player co-op on 0.72.0: "can you please work out aircraft syncing, such as missiles being fired",
"when allies land at the airfield, their gear doesn't deploy on my screen, nor do I see their afterburners or
animations". Each game watches its own plane and tells the others; their stand-in of it (SV_Unit_CoopPeer<A-X>) does
the same there. Lua: sv_coop.lua's "weapons, gear, afterburner" block; the native half (SV_CoopFire, SV_InputNow, the
stand-ins' afterburner) is the runtime's (its notes in section 2).
- **Read, each game, its own plane, every Lua tick (250 ms)**:
  - missiles: the pawn's reflected `FiredExplosiveWeapons` (TArray<UObject*>, its missiles in flight). Weapons are
    pooled (LiveWeaponBase < LiveObjectPoolItem: NotifyOnNewObject never sees a reused one), so an address that wasn't
    in the array last tick is a shot (one gone and back is a new shot; the first read after your plane changes only
    learns what's up). Its class gives the kind: `BP_plwp_msl_*` the standard missile (`m`), anything else but a
    gun / flare class a special weapon (`s`); its `TargetToHome` the target, mapped to the co-op stream id (the host: its
    own enemy, M.byId by address; a joiner: its copy, M.copies[id].addr; 0 for none or one not linked).
  - gun and flares: SV_Ammo(0) / SV_Ammo(4) dropping, read before Survival's own refill (sv_main.lua calls
    COOP.ammoRead just before ammoTick; COOP.tick keeps the counts after it), never on the airfield (a rearm).
  - gear: `pawn.LandingGearOnMesh:IsVisible()` (the gear-down mesh shown).
  - afterburner: SV_InputNow()'s throttle (x1000) at `ab_throttle` or over.
- **Sent**: state flag bits on SV_CoopMe (16 gear down, 32 afterburner, 64 gun firing: held 0.5 s after the last drop,
  128 flares: the same), and the shots as `fx` (reliable, one message a tick): shooter -> host `fx|k:id:age;...`
  (k: m missile, s special weapon, g the gun's target, sent as the gun starts or the target changes; id the target's
  stream id, 0 none; age ms), the host -> every other joiner `fx|<shooter's slot>|...` (never back to the shooter; its
  own as slot 0), each age grown by half that link's round trip (SV_CoopInfo's rtt).
- **Shown**: each shot fired from the shooter's stand-in, `SV_CoopFire(stand-in, 2, the target's actor here or 0)`; a
  peer's bit 64 fires its stand-in's gun (slot 1) every 0.2 s (each Lua tick) at its `g` target; bit 128's rising
  edge its flares (slot 0), again every second held; a flip of bit 16 the stand-in's `EnableLandingGear(down, 1.0)`
  (LiveAIPlane UFUNCTION; a new stand-in seen gear up calls nothing); bit 32 the runtime lights by itself each frame.
- **Guards** (each game, on what another sends; keep them when adding kinds): a known slot that isn't yours; at most
  12 shots a second a shooter (`g` entries not counted) and 32 entries a message; a shot older than 1.5 s (its age with
  half each leg's round trip) or from a shooter whose state is over a second old dropped; unreadable entries dropped;
  an id not known here fired with no target; no stand-in of theirs here: nothing fired (the host still relays).
  The runtime holds each shooter to 25 SV_CoopFire calls a second.
- **Never counted twice**: a stand-in flies its airframe's damage-0 row. tools/build_survival.py adds a mission row
  `<row>_svcp` (COOP_STANDIN_SUFFIX) for every row of CFG.coop.airframes and its default, NpcId `<its NpcId>_SVCP`;
  COOP.syncSetup (sv_main.lua's main-menu pass, before the level loads: hard rule 20's timing, as searchSetup's
  `_sv` rows) makes that DT_NPC row a copy of the airframe's with each fire-control slot on `<FCS>_SVCP` and its weapon
  on `<W>_SVCP`, damage and AreaOfEffectDamage 0 (read back); a slot whose weapon can't be made harmless is emptied.
  The stand-ins fly them (peerTick, M.flyRow) only in a level that loaded after they were made, and only with sync on.
  The backstop: a joiner's clientTick takes any stand-in's DamageHistoryMap growth on a copy (x10: the map is in
  health, HealthInternal is x10) out of what it sends the host as "ht". (The host has no backstop: a stand-in's hit on
  its own enemy would be real damage there if a `_SVCP` row ever weren't harmless.)
- **Settings** [coop.sync] (CFG.coop.sync, each player's own: [coop] is PERSONAL): enabled, missiles, guns, flares,
  gear, afterburner, ab_throttle (0.9). enabled = false: nothing sent or shown and the stand-ins on their own rows.
- **Log lines** (`coopfire:`): `the stand-ins' damage-0 rows: N of 21 airframes` (with `weapons left off` / `not
  made`); `coop: player N's plane as <row>_svcp: spawned`; `your weapon <class>: a missile / a special weapon / not sent`
  (once a class); `your first shot sent (...)`; `player N's first missiles / gun / flares here (their plane X, at Y):
  <SV_CoopFire's result>`; `SV_CoopFire(player N's plane, slot S) refused: <code>`; `player N's shots dropped: <n>
  <why>` (once a reason); `your gear down / up`, `player N's gear down here: EnableLandingGear done`; `your throttle
  0.950: afterburner on`; `copy N lost X, Y of it another player's stand-in's here`; the minute's tally `60 s: N shots
  sent, N received (N fired here, N refused, N dropped, ...), your gun N bursts, your flares N, ..., throttle up to N
  (ab_throttle 0.9)` (full throttle's reading, to calibrate ab_throttle). SV_CoopFire's codes read through SV_ERR
  (sv_ai.lua): -10 rate, -11 the game refused it, -13 not an AI plane with fire control, -14 a bad target.
- **Test key** (TEST ONLY, stripped from releases): Ctrl+F5 in a run with MOONCHILD or VIPER up (bought in the STORE):
  each press the next step on that plane at your current target (SV_PlayerTarget): 1 missiles (slot 2) with its fire
  permission off, 2 with it on, 3 its gun, 4 its flares, 5 gear down, 6 gear up; `coopfire: test <n>: <plane> (<unit>)
  <what> at <target>: <result>`.
- **In-game checklist**: (1) solo, Ctrl+F5 through all six: do the missiles leave the ally with permission off (decides
  whether the stand-ins, permission off, can fire at all), at your target; the gun and flares visible; the gear moves.
  (2) co-op, two players: each sees the other's missiles leave their plane and fly at the right enemy, the gun's
  tracers, flares, the gear on the runway and in the landing pattern, the afterburner's glow at full throttle; no
  enemy dies twice or to a stand-in's missile (the log's `copy N lost ... another player's stand-in's` should never
  appear; kills only by the shooter, "wingmate" on the others). (3) the tally line's dropped and refused counts near 0.
  (4) the `throttle` lines: does 0.9 match the afterburner? Calibrate ab_throttle.
- **Guesses the design relies on** (from the research, not seen in game): FiredExplosiveWeapons holds exactly your
  missiles in flight (not the gun's rounds or flares); TargetToHome is the locked target; LandingGearOnMesh shows when
  the gear is down; the throttle input is 0..1 with the afterburner at full; EnableLandingGear(bool, float) is the
  stand-in's gear; SV_CoopFire works with the stand-in's fire permission off; zeroed weapon rows deal no damage
  (damage and AreaOfEffectDamage are all the row's damage); slot 2 is the missile slot of every stand-in airframe's row
  (sv_rows.lua's director line logs which rows carry their missiles in slot 2; specials use it too for now).

## 9. Revives and the spectator camera (Lua 0.72.2, runtime 0.28.5, 2026-10-29; untested in game)
The user: "is there a revive option we could possibly add for COOP only? like say if you die, HOST or JOINER, someone
could land at the airfield and buy you back, lets say that when you die, you get put into a spectator camera and you can
switch between the players currently active". Lua: Scripts/sv_down.lua (after sv_coop in main.lua's MODULES); the
native half SV_Down (the loiter autopilot) and SV_Respawn: KILLS_HEALTH_DEATH.md 7. Co-op only: another game linked and
a run on; solo stays exactly as before (no floor, the game's death, LB.deathCheck's run end).
- **The floor**: sv_tactical.lua INS.tick sets MinHealth to the higher of SECOND CHANCE's (when held) and floor_hp (0.1
  HP: HealthInternal 1) and, while revives are on, reads it back every pass and sets it again (`insurance: your
  aircraft's floor was put back by the game`). A SECOND CHANCE held fires first (its 4 % floor), then the revives'.
  It writes the field, not SetMinHealth: the game's SetMinHealth keeps whole points only (KILLS_HEALTH_DEATH.md 1), so
  up to 0.72.3 the floor was 0 and never held (the user's run of 2026-10-30: "put back" every pass, shot down from
  40 HP in round 8, the run restarted at round 1). Fixed for the next build, not yet run in game.
- **DOWN** (HealthInternal <= floor_hp x 10, in round 1 or later, no SECOND CHANCE held): invincible, hidden, collision
  off, bEnableWeaponInput / bEnableFlareInput false, bIsWeaponSystemDisabled true, the plane's attacker limits
  (MaxPlaneAttackerMissiles, MaxPursuitAttackers, MaxNonPlaneAttackerMissiles) 0 [a guess: the enemies' throttle on
  attacking you], each value kept for the way back; `SV_Down(pawn, AIRFIELD.X, AIRFIELD.Y, alt_m, radius_m)` (again
  every 5 s: the runtime only moves the circle; the first DOWN of a session spends 3-5 s learning the input signs);
  state bit 8 and not 2; "dw"; YOU'RE DOWN; STATS.death("down"). The plane's tick is never switched off. Other games:
  bit 8 hides the stand-in (and its collision; SV_CoopPeer 0) and makes COOP.players() say down, alive false, so
  othersFlying, the squad and intensity directors, the aces' first contacts and the spawn holds count them out; the
  CO-OP rows say DOWN.
- **The host down**: its rounds go on (it's in the air, not on the airfield: nothing holds them). Its own-plane events
  aren't fired on its game (sv_coop.lua HOST_DOWN_SKIPS: RE_SV_Salvo_, RE_SV_WolfTurn, RE_SV_AceTurn_ / AceKulbit_,
  RE_SV_WraithBlink, RE_SV_GlitchBlink / GlitchTurn / GlitchGun, RE_SV_ValkaTp_, RE_SV_AnomalyPackSpring; SV_ERR[-20]);
  what's forwarded still goes to the joiners; `coop: <event> not fired here: you're down (N skipped)`.
- **The spectator camera**: COOP.watchable() (the other players' stand-ins shown, fresh, not DOWN, slot order); a
  CameraComponent added to the watched one once (AddComponentByClass, back_m behind, up_m above, pitched down at it),
  `survivalPC:SetViewTargetWithBlend(stand-in, blend_s, 0, 0, false)`; each pass GetViewTarget is checked and the view
  put back (counted) if the game took it; the next player by the key (O, [coop.revive] key / ctrl, each player's own)
  or by itself when the one watched goes down, leaves or is hidden; nobody to watch: your own plane and `DOWN: WAITING
  FOR A REVIVE`, else the NEXT row `DOWN: WATCHING <NAME>  [O] NEXT` (sv_hud.lua).
- **Revive**: the STORE's AIRFIELD page's sixth row, REVIVE (tools/build_survival.py STORE_PAGES; CFG.shop.items.Revive,
  role "revive": sv_shop.lua offer / shopBuy -> DOWN.offer / DOWN.buy): `REVIVE <NAME>` the one down longest, `(+N)`
  for more, price x raise ^ (the run's revives, the host's count); else `CO-OP ONLY.`, `NOBODY IS DOWN.`, `YOU'RE
  DOWN.`, `ASKED: WAITING FOR THE HOST.`. The host buying checks itself; a joiner pays at once, sends "rv" and is
  refunded on "rx" or after 10 s with no answer. The host's checks: both slots real and different, the target down
  (bit 8 in its fresh state, or the host itself), no revive of it in the last 15 s, the price the count's, the reviver
  on the ground at its airfield (bit 4 in its fresh state; the host: playerOnAirfield). Then "rb" to everyone: the
  downed game comes back, the others call `<NAME> BACK` / `REVIVED BY <NAME>`.
- **Back**: SV_Down(0), shown, collision on, inputs and attacker limits back (a limit only if still 0), the view on
  your plane, RE_SV_RepairAircraft and HealthInternal written full, safe_s invincible; respawn "loiter" stays where it
  was flown, "native" calls SV_Respawn 4 km out from the runway (1609574, -435747) along its heading (yaw -23), 500 m
  up, yaw -23; `revive: respawn d=<m> m` half a second on (where you are against where it was asked). A plane that
  isn't flying when revived (slower than 40 m/s, or under the sea, for 3 s while DOWN: it crashed into the ground with
  its floor held, and the loiter can't lift it) comes back "native" whatever respawn says: the user's co-op run of
  2026-10-30 (0.72.4), VERDA crashed, went DOWN, and was revived where the plane lay, on the ground (fixed for the
  next build, not yet run in game). A downed player
  keeps zollars, items, upgrades and allies, and gets round bonuses unless down_round_bonus = false (then the host's
  own and a joiner's "cr" are skipped while down).
- **Run over**: the host, every pass: every player present (you; others in the level and heard from in 5 s) not alive
  for 3 s -> "ro|<round>" to everyone and its own run over (also when the last joiner has gone with the host down). On
  "ro" each game: the view back, STATS.death("died"), LB.finish("died"), RE_SV_RunOver (tools/survival_events.py
  build_run_over: Mission 15's LiveMissionFinishExecution MissionFailed, false, true: the retry menu; kept, never "ev").
  No event: the fallback, the loiter off and the plane mortal (MinHealth 0, invincible off, the floor off). A joiner
  down with the host's link gone 10 s ends its own. sv_leaderboard.lua's death check ends nothing while revives hold
  the run (co-op, linked): only "ro" does. The host's "rs" (a new run) brings a downed joiner back and refunds an open
  revive; a new level clears everything.
- **Protocol** (reliable; guards: slots 0-23, whole numbers, text cut to 60 capitals; at most 4 a second from a joiner,
  60 from the host): joiner -> host `dw|<slot>` (its own slot only), `rv|<slot>|<price>`; host -> everyone
  `dw|<slot>|<count>[|q]` (q: a catch-up, no callout), `rb|<slot>|<count>|<by>`, `ro|<round>`; host -> one joiner
  `rx|<slot>|<why>|<count>`, and as it links (hostSync -> DOWN.syncTo) `rc|<count>` with a `dw ... q` for each one down.
- **Settings** [coop.revive] (CFG.coop.revive): enabled, floor_hp 0.1, price 5000, raise 1.5, safe_s 5, respawn loiter |
  native, key O, ctrl false, down_round_bonus true; [coop.revive.loiter] alt_m 2500, radius_m 4000;
  [coop.revive.camera] back_m 30, up_m 8, blend_s 0.5. [coop] is PERSONAL, but sv_coop.lua's SHARED_IN makes
  coop.revive the host's for everyone except OWN_IN (key, ctrl, camera).
- **Log lines**: `insurance: your aircraft's floor 0.1 HP (co-op's revives)`; `down: you're down at 0.1 HP in round N:
  hidden, no collision, ...; loiter round the airfield at 2500 m, 4000 m round: on`; `down: loiter <km> / <m> (from
  the airfield / up), <N> m/s; watching <name>` every 5 s (every 30 s after a minute); `down: your plane isn't flying (N
  m/s, N m up, N km from the airfield): a revive brings you back 4 km out from the runway, 500 m up` (once a DOWN); `spectate: view <NAME> (<why>), reverted N
  times`, `spectate: view put back on <NAME> (the game took it back N times)`; `down: player N (<NAME>) is down`;
  `revive: asked the host to revive player N for P`; `revive: player N revived player M for P (the run's revive K)`
  or `... refused: <WHY>`; `revive: back (revived by <NAME>) after N s down: repaired (event fired, health written), 5 s
  invincible, <where>` (`... (your plane wasn't flying: N m/s): done` for a crashed one); `revive: respawn d=<m> m`; `down: every player in the mission is down (N) for 3 s`; `down: run
  over in round N`; `down: the mission's end (RE_SV_RunOver, Mission 15's MissionFailed): fired`.
- **Test keys** (TEST ONLY, stripped): T1 Ctrl+F6, the floor solo on / off (`down-test: health N (floor 0.1),
  MinHealth M` once a second: let an enemy shoot you down to 0.1 HP and stay there); T2 Ctrl+END (each press: 1 DOWN
  solo, watching MOONCHILD / VIPER, else the nearest enemies, O the next; 2 back by the loiter; 3 DOWN; 4 back by
  SV_Respawn): `down-test: T2 step N`, `spectate: view ...`, `down: loiter ...`, `revive: respawn d=...`. If UE4SS has
  no END key the log says `test: T2 not bound`.
- **In-game checklist**: (1) T1: the health stops at 0.1 under fire (no death), MinHealth reads 0.1 and comes back after
  a repair. (2) T2: the plane vanishes, flies itself round the airfield (the loiter lines: ~4 km, ~2500 m after the
  sign probes), the view swings to MOONCHILD (or an enemy) from behind and above, O moves it on, it stays there (the
  revert count stays 0 or low); no enemy chases the hidden plane; back by the loiter: you fly again at full health,
  invincible 5 s; back by SV_Respawn: 4 km out along the runway at 500 m (d near 0). (3) co-op, three players: one
  shot down goes DOWN (everyone sees <NAME> DOWN, their plane gone) and watches the others; another lands, the AIRFIELD
  page shows REVIVE <NAME> 5000 Z, buying it brings them back (everyone sees <NAME> BACK); the next costs 7500; a joiner
  buying in the air is refused and refunded. (4) the host down: rounds go on for the others, no salvo or blink aimed at
  the host's empty sky. (5) everyone down: RUN OVER on every screen and the retry menu (RE_SV_RunOver), the summary.
- **Guesses the design relies on**: SetViewTargetWithBlend on an AI plane with our CameraComponent shows that camera
  (AC8's camera manager may override it: the revert count says); hiding, collision off and the attacker limits keep the
  enemies off a downed plane; bEnableWeaponInput / bEnableFlareInput / bIsWeaponSystemDisabled stop its weapons;
  MinHealth 0.1 holds against every kind of hit (KILLS_HEALTH_DEATH.md: a crash may pass it; such a plane dies as the
  game does and that player's game ends their run); the game puts MinHealth back on a restore (read back every pass
  anyway); Mission 15's MissionFailed record ends Survival's mission as a failure with the retry menu.
