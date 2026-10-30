# COOP2MP: the other players as real player planes (branch COOP2MP, from 0.72.7-coop.25)

The user, 2026-10-30: "we should probably begin testing on how to get a similar result from Ace Combat 8's multiplayer
working in this coop mode so that everyone is using their player aircraft and not an AI stand in", "Start a new build
called COOP2MP". Builds: VERSION 0.73.x, COOP_TAG -coop2mp.N (tools/coop_edition.py), zips
`BUILD_NAME=COOP2MP COOP=1 NOVALKA=1 sh tools/package_release.sh online <version>` ->
build/release/AC8SurvivalMode_COOP2MP_<version>_Online_COOP_NoValka.zip. A COOP2MP game and a 0.72.x co-op game warn
on linking (different versions); don't mix them in one room.

## Why
Co-op 0.72 shows each other player as an allied AI plane (SV_Unit_CoopPeerA-X) on an AI row of their airframe
(CFG.coop.airframes). That can't show a plane with no AI version (the ADFX-02), shows AI paint, and the player's own
weapons can only be faked with the AI row's fire control: an ESM needs an ECM pod added (0.72.7), special weapons fire
as ordinary missiles, and nothing of the player's look, loadout or effects comes across. AC8's Online Mode shows every
player as a real player plane (ALivePlayerPlane) and drives it from network messages, its weapons too.

## What AC8's Online Mode does (research, 2026-10-30; exe strings and class names, no reflected fields)
- Each remote player: a real `ALivePlayerPlane` of their plane class, possessed by an `ALiveNetworkDummyController`,
  network role `+0xed8 = 2` (another player's), its `ULiveNetworkPlayerPlane` network object, the player's loadout
  (0x147d4ad20), spawned deferred and finished (COOP.md 6: the remote spawn 0x1471cc490, its steps).
- Online Mode runs on Strix (LiveStrixManager, LiveStrixMessenger). Each event is its own message
  (`jp.co.soft_gear.strix.server.ext.message.game.FLiveMessage*`; FLiveMessageBase: NetworkTypeId, NetworkId,
  TriggerTimeMs):
  | message | fields (as the exe names them) |
  |---|---|
  | ExplosiveWeaponFire | WeaponData = FLiveMessageWeaponData: WeaponNumber, WeaponNetworkId, SpawnSlotIndex, InitialLocation, InitialRotation, InitialVelocity, TargetNetworkId, TargetNetworkTypeId, LockonNum, RandSeed |
  | ExplosiveWeaponHit | ComponentOwnerNetworkId, ... |
  | BulletWeaponFire, HoldingMachineGunButton | bTrigger, LoadedSlotIndex; BulletsFired, SpecialWeaponArmedIndex |
  | InstantWeaponFire | (instant-hit weapons) |
  | ElectronicMeasureFire / Data / Effect | ElectronicMeasureType (ELiveNetworkElectronicMeasureType ESM / ECM), bEffectOn |
  | SpecialWeaponArmed, LockedTarget, SelectedTarget, SelectedEmlTarget | bLockOn, ... |
  | PushFlare, EscapeByFlare | EscapeNum, PlayerMissileEscapeNum, DoubleLockonEscapeNum |
  | LandingGear | bGearDown, bForceCancel, bLanding, bCarrier |
  | FlightEngineInput, AirCurrentStates, Physics, PostStallManeuver, FlightEngineHighGTurn | Throttle, EngineBrake, Brake, HighGTurn, InputMoment, Accele; CurrentRot, CurrentMove, CombinedState, SpeedLocal |
  | Damage, DamageClient, Health | AttackerNetworkId, AttackerNetworkTypeId, WeaponId, Health, Killed |
  | Respawn*, RespawnRescueTry / Result | Online Mode's own rescue: Rescue / Rescued NetworkIds |
  The AI's have their own (FLiveMessageAIExplosiveWeaponFire ...). `ELiveWeaponNetworkId` numbers a plane's weapons;
  `RemotePlaneMissileIgnitionEventName` names a remote plane's missile ignition effect; ELiveNetworkCheatType checks a
  client's weapon_ammo / cooltime / location / id.
- In the exe (code section `.ecode`): every one of these message names (UTF-16) is referenced from one function,
  0x1452a5010..0x1452a8b5c, most likely where the message types are registered. Next: the receive handlers (what a
  received ExplosiveWeaponFire calls on the remote plane: its weapon system W = plane+0x16a8 firing weapon number N with
  the given pose and target).

## The plan, test by test
Each test is a COOP2MP build; solo tests use the test keys (TEST ONLY, never in friends' zips).
1. **T1 solo: a real player plane beside you.** The probe that's already in (COOP.md 6: SV_CoopSpawnPP, SV_CoopFollow,
   SV_CoopPPRole, SV_CoopKillPP; Ctrl+F11 / Ctrl+F12 in sv_main.lua) spawns a copy of your own plane in formation,
   role 2, tick off, moved on every input build: in 0.22.7 it flew solid and smooth, ALLY-tagged, in default paint.
   Check again on 0.73: does it still hold up, do the enemies target it, does your HUD / camera / lock-on stay right.
2. **T2 solo: any airframe.** Spawn a chosen plane class (the PlayerPlaneDataTable row's `Reference`, row +0x38, as the
   remote spawn 0x1471cd2d0 does): the ADFX-02, the FA-36. Its paint (open: where the skin ID is applied).
3. **T3 co-op: the stand-in as a real player plane.** The co-op state stream (P / Q, coop.c CoDrive) drives a player
   plane as it drives the AI stand-in (CoKind 2 and CoCanDrive are in). Each player's own airframe class from their
   "hi" (the plane code, not an AI row). Keep the AI stand-in as the fallback.
4. **T4: weapons Online Mode's way.** Find the receive side of ExplosiveWeaponFire / BulletWeaponFire /
   ElectronicMeasureFire / PushFlare / LandingGear and call it natively on the remote plane with our own data
   ("fx" grows the fields WeaponData has). Then the player's real missiles, specials, ESM, gun and flares show.
5. **T5: the rest.** Enemies targeting the other players (Online Mode's OtherPlayer faction), damage shown, the DOWN and
   revive on a player plane, up to 24 of them (frame cost).

## T1 / T2 build (0.73.0-coop2mp.1, runtime 0.29.0; installed 2026-10-30 as the user's test install)
`sh tools/package_dev.sh COOP2MP_T1` (the test keys kept; never for friends), installed over 0.72.7 (backed up in
build/backup/install_before_coop2mp_t1). SV_CoopSpawnPP takes an optional plane class (another airframe: no loadout of
yours, its own default weapons). In a solo run, Ctrl+F11 each press the next airframe 150 m off your right wing: your
own plane's class, the ADFX-02 (BP_PlayerPlane_PP0038_adfx02), the FA-36 (PP0018_fa36); Ctrl+F12 removes it.
- Look: does it show, solid and smooth, in what paint; its gear, afterburner glow and control surfaces (its own tick is
  off: what of its look still runs?); the ALLY tag / W box; your camera, HUD, target cycling and lock-on stay yours.
- Fight near it: do enemies go for it (their missiles at it, it taking hits).
- Log: `test: Ctrl+F11 spawning <name> (<class>)`, `coop: second player plane <p> (class <p>, yours | another
  airframe: no loadout of yours) spawned ...`, `... spawn finished: yes, weapons <p> ..., their owner <p>`,
  `test: Ctrl+F11 after the spawn: your pawn is still yours; formation 1`, and every 5 s `test: second plane <name>:
  <d> m from you, health <h>, its tick false; of N enemies up, A have it as their nearest player plane, B you`;
  `test: Ctrl+F11 <name>: its class didn't load (...)` if a class path is wrong.

### T1 / T2 results (the user's solo test, 2026-10-30 15:38-15:40)
- Your own plane's class and the FA-36 spawned (spawn finished, weapons' owner set, your pawn stayed yours) and held
  150 m off your wing for over a minute: 1,200 moves, none refused, none over 50 m off (moved at the music tick).
- With its tick off: no animations (control surfaces), no afterburner, NO HUD box or ALLY tag (0.22.5's screenshots had
  them: its tick may have run then), and the enemies never attacked it (health 1200 throughout; the user: "I didn't see
  the enemies targetting it"), though 2-4 of 4 had it as their NearestPlayerPlane at times.
- The ADFX-02 didn't load: its blueprint is PP0038_adfx02_L001/BP_PlayerPlane_PP0038_adfx02_L001 (fixed: 93d9d08,
  COOP.planeClassPath with every player plane's path).
- So a frozen plane teleported every frame can't be a real MP-style plane: its tick has to run, fed the network data
  Online Mode feeds a remote plane (its movement sync and flight inputs). Research on that path: next section.

## How a remote player plane flies itself (research, 2026-10-30; verified in the exe)
- ALivePlayerPlane's FrameUpdate calls RemoteUpdate 0x147d6f0c0 (plane, float dt) at 0x147d646dc for a plane of network
  role 2. It checks plane+0xed0 (the network object N, a ULiveNetworkPlayerPlane), then 0x1474d8c00 reads N's
  FLiveMessageFlightEnginePhysics R = *(N+0x98) into the plane's second flight state: Direction R+0x20 (3 floats),
  Location R+0x2c (3 int32, cm), Rotation R+0x38 (3 floats, deg: pitch, yaw, roll), State R+0x44 (int32), SpeedLocal
  R+0x48 (float, m/s). R+0x08 is TriggerTimeMs (left alone); R+0x58 / +0x68 / +0x78 count queued messages (keep 0).
- Its input comes from N+0x170 (FLiveMessageFlightEngineInput): +0x08 pitch, +0x0c yaw, +0x10 roll, +0x14 throttle,
  +0x18 brake, +0x1c high-G (floats), +0x20 an attribute byte (4 by default; bit 0 zeroes the input).
- The plane's own flight state (MS, plane+0x2268: its speed plane+0x2318, its State plane+0x2b18) is blended toward the
  second one, and snaps to it when over 1 km off; then the plane's own engine, controls and effects run as for yours.
- With nothing received all of R is zero: that's the pull to the map's centre (COOP.md 6). A local plane's State has bits
  20 and 9 that a remote one mustn't get (cleared when copied).

## T1c build (0.73.1-coop2mp.2, runtime 0.29.1; the user's test install, 2026-10-30)
The runtime hooks RemoteUpdate (sigs.h kSigRemoteUpdate, 18 bytes) and, for the one plane SV_CoopFeed names, writes the
source's pose (plus a formation offset), speed, State and last BuildFlightInput into R and N+0x170 just before the
game's update reads them (runtime/flight.c, FD). Ctrl+F11 now leaves the copy's tick ON and feeds it from your plane,
150 m off your right wing (T1's tick-off way if SV_CoopFeed is missing or refuses). Same three airframes; Ctrl+F12 ends it.
- Look: does it stay beside you (not at the map's centre, not stuttering); its control surfaces, gear and afterburner
  following yours; an ALLY tag / HUD box; the ADFX-02 loading (93d9d08's path); enemies going for it, it taking hits.
- Log: `remote player plane update` hooked at load; `test: Ctrl+F11 the copy's own tick stays on, fed (SV_CoopFeed 1)`;
  `coop2mp: plane <p> fed from <p> (0 m ahead, 150 m right, 0 m up) ...`; once, `coop2mp: fed plane <p> first: message
  <p>, input <p> (the source's | NO INPUT RECORD); speed N m/s ..., state <x>, queues 0 0 0`; then every second
  `coop2mp: fed plane <p>: N updates, N fed, N skipped; N m off where it was sent, its speed N m/s` (`ITS REMOTE UPDATE
  ISN'T RUNNING` if the game stops calling it); the 5 s `test: second plane ...` line as before ("its tick true").
- If it sits at the map's centre anyway, or N m off keeps growing: something else writes R after us (a received
  message's queue) or the update reads another field; the log's queue counts and "skipped" tell which.

### T1c results (the user's solo test, 2026-10-30 16:57-17:00)
- All three airframes (your own, the ADFX-02 now loading, the FA-36) flew fed with their tick on: 0 skipped, 1-20 m
  off where they were sent (89 m once) from 60 to 638 m/s; control surfaces and the rest worked (user: "didn't see an
  afterburner but everything else worked").
- No afterburner glow. No enemy attacked it (user: "enemies don't target the other aircraft"): health 1200 / 1260
  throughout, though 0-4 of 4 enemies had it as their NearestPlayerPlane.

## The afterburner's glow (research, 2026-10-30; verified in the exe)
A plane's surface component tick 0x147d320e0 calls, for a player plane (component+0x188 set), 0x147d32b00, which sets
the afterburner alpha component+0x2a4 = plane+0x39d0 (0 when dead); 0x147d33dcc puts it in the "Afterburner_Alpha" /
"AfterBurnerSize" / "AfterBurnerLightSize" parameters. (An AI plane's, 0x147d333a0 via component+0x190, ramps on its
byte +0x29b8, its acceleration or its speed.) plane+0x39d0 is the player plane's afterburner amount (getter
0x147d65ed0), written with the block plane+0x39c0.. by its movement update 0x14731e7e0 (from 0x14731e590) out of its
flight engine at +0x3088. A fed remote plane never gets one. In the network messages the input's Accele is the
throttle (FLiveMessage... flight state: Direction 0, Location 24, Rotation 48, MomentSpeed 64, State 72, SpeedLocal 76,
InputMoment 88, Accele 112, EngineBrake 116); nothing carries the afterburner amount itself.

## Why enemies didn't attack it (research, 2026-10-30; [V] in the exe unless marked)
- NearestPlayerPlane (AI plane+0x2668, the nearest of LiveActorManager.CachedPlayerPlanes) only feeds the provoke and
  blackout reactions. An AI attacks its fire control's current target (vfunc +0xcb0; Lua GetTrackingTarget()).
- The search (LiveFCSModule_AIControlLegacy slot +0x300, 0x147bf34a0) takes hostile, alive, activated (+0x3f4) planes
  near its unit area out of LiveActorManager.ObjectMapper, sorts them into flags (0x147bf74a0: 2 player plane, 0x10 not
  locally controlled, 8 the order's target, 0x20 pursuit quota full) and keeps those its filter (0x147c0bb30: target
  type, search priority, order target) allows. The copy is 0x12, exactly an Online Mode remote player, and passes
  Survival's PlayerOnlyNoLimit; air only needs its State bit 17 (on the ground [I]) clear.
- Survival's orders name "Player": FirstPlayerPlane (LiveActorManager+0x1e0), set by RegisterGameObject (0x1473a1a80)
  for a locally controlled plane only, so your plane is every order's target (flag 8) and the copy never is.
- The mission's attack limits (LiveSetPlayerMaxAttackerMissiles 0x1473f9ba0) are written to the planes then in
  CachedPlayerPlanes: a copy spawned later keeps the defaults. Fire gate 0x147c047b0: the target's attackers / missiles
  against its limits and cooldowns (counted down in its TickGame).
- EngagementOrderOverride(Order, TargetEnemy, SearchPriority, SearchPriorityExtension, IgnoreAttackQuota,
  bCanFireWeaponBit, PropogateToChild) is a UFUNCTION on every AI object (exec 0x146d24730 -> SetEngagement 0x147c8f9e0,
  the event node's path). ELiveEngagement Normal 0; ELiveEnemySearchPriority Default 0, AIFirst 1, AIOnly 2, AINonTGT 3,
  AINonTGTFirst 4, PlayerFirst 5, PlayerOnly 6, PlayerFirstNoLimit 7, PlayerOnlyNoLimit 8, TargetFirst 9 (the order's
  target alone), TargetOrNearbyPlayer 10, None 11; fire bits 7 (the stock order's three true, three false).
- Not traced: whether a hit on a role-2 plane applies on this game (player TakeDamage 0x147d5a430 has no role check at
  its head).

## T1d build (0.73.2-coop2mp.3, runtime 0.29.2; staged 2026-10-30, not yet run in game)
- The afterburner: the runtime hooks 0x147d32b00 (sigs.h kSigSurfacePP, 18 bytes) and, for the fed plane, writes the
  source's plane+0x39d0 there just before the component reads it.
- The enemies: Ctrl+F11's copy gets a floor of 300 HP (MinHealth: never shot down in the test) and your attack limits;
  every 5 s every other enemy up that isn't tracking it is ordered onto it (EngagementOrderOverride Normal, the copy,
  TargetFirst, fire bits 7), the rest left to pick; Ctrl+F12 and the next Ctrl+F11 put the ordered ones back on you
  (PlayerOnlyNoLimit).
- Look: the copy's afterburner glow when you boost; enemies going for it (missiles at it, its health dropping to 300 and
  holding); whether the unordered half ever pick it.
- Log: at load `player plane surface update: hooked at <p>`; `coop2mp: plane <p> fed ... its afterburner from yours: yes`;
  every second `coop2mp: fed plane ...; afterburner x1000 yours up to N, left on it up to N, N written; State bits yours
  <x>, its <x>` (left on it = what the game had there before the write: 0 means nothing else keeps it); `test: Ctrl+F11
  the copy's floor 300 HP: set; MaxPlaneAttackerMissiles ...`; `test: N enemies ordered onto the second plane
  (TargetFirst)`; every 5 s `test: second plane ...: health H, ..., on the ground false, activated true; ... tracking: A
  it, B you, C other, D none, E unread; ordered onto it N (M tracking it)`.
