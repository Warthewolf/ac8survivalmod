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
- Its input comes from the FLiveMessageFlightEngineInput that N+0x170 points to (a TSharedPtr: the message's address at
  +0x170, its reference controller at +0x178; RemoteUpdate 0x147d6f1d1 `mov rdx, [rdi+0x170]`): +0x08 pitch, +0x0c
  yaw, +0x10 roll, +0x14 throttle, +0x18 brake, +0x1c high-G (floats), +0x20 an attribute byte (4 by default; bit 0
  zeroes the input). (Read as inline at N+0x170 until runtime 0.29.3: see T1e.)
- The plane's own flight state (MS, plane+0x2268: its speed plane+0x2318, its State plane+0x2b18) is blended toward the
  second one, and snaps to it when over 1 km off; then the plane's own engine, controls and effects run as for yours.
- With nothing received all of R is zero: that's the pull to the map's centre (COOP.md 6). State bit 9 is gear down:
  RemoteUpdate (0x147d6f989) lowers or raises the plane's gear from it every frame (T4a.2's test; until runtime 0.31.2
  it was cleared on the research's word, so a remote plane's gear never came down). Bit 20: still cleared, meaning
  unknown.

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

### T1d results (the user's solo test, 2026-10-30 17:58-18:02)
- The afterburner glow works (user: "afterburner was working"). Your afterburner amount read 0.3-1.0 while boosting;
  what the game had left on the copy before each write was always 0 (a remote plane's +0x39d0 is reset every frame),
  so the write just before the surface update is what shows it. Your State bits while boosting: 8 (also 0x10, 0x40,
  0x80 at times); the copy's own State stayed 0 although R+0x44 carried them.
- The ordered enemies attacked it (user: "enemies were attacking"): every ordered one tracked it within 5 s and kept it
  (2 of 2 for three minutes on the ADFX-02); the unordered ones never picked it (tracking it = exactly the ordered
  count), as the research said (Survival's orders name your plane). It stayed in the air (on the ground false,
  activated true) with your attack limits (4 / 6 / 4).
- Its health never changed (1200, then 1260 for three minutes under attack) though its floor was 300: either the
  enemies' shots never hit it or a hit on a role-2 plane isn't applied on this game (Online Mode applies a remote
  player's damage on their own game: FLiveMessageDamage). Next: find which (the player plane's TakeDamage 0x147d5a430
  for a role-2 plane).
- So for co-op: the host has to spread its flights' orders over the players itself (the game's own search never picks a
  remote player while an order names the local one).
- The user saw a missile explode on the copy: the hits land, their damage isn't applied (a role-2 plane's).
- Quit Mission crashed the game (18:06, after a restart of the mission in the same level kept the copy, its tick then
  off): EXCEPTION_ACCESS_VIOLATION writing 0xbf800008 in the network object's destructor (0x146f0d3b0, from garbage
  collection), which releases the TSharedPtr controller at N+0x178. T1c / T1d wrote the input inline at N+0x178..+0x190
  (N+0x170 is that shared pointer, not the message): a pitch of -1.0 (0xbf800000) over the controller. So the copy's
  input was never fed either (its control surfaces moved with its flight); and every T1c / T1d copy corrupted its
  network object. Test builds only (COOP2MP's feed; 0.72.x has none of it).

## T1e build (0.73.3-coop2mp.4, runtime 0.29.3; installed 2026-10-30, not yet run in game)
- The input through the pointer (FdMessage: *(N+0x170), +0x08.. in that message): Quit Mission shouldn't crash, and the
  copy's controls get your stick.
- The hits: the runtime hooks the player plane's damage 0x147d5a430 (sigs.h kSigPPDamage, 15 bytes) and logs it for the
  fed plane only: its first 10 hits `coop2mp: hit on the fed plane <p>: damage N (x10), kind K, from <p>, health A -> B,
  the game returned N (x10)`, then each second with hits `coop2mp: fed plane <p>: N hits this second, N damage asked, N
  taken off its health (health now N)`. No line at all while missiles explode on it: the hit doesn't reach the player
  plane's damage (look for Online Mode's hit message path next).
- Test: as T1d (Ctrl+F11, enemies ordered onto it), let missiles hit the copy, then Quit Mission (and a Restart).

### T1e results (the user's solo test, 2026-10-30 18:15-18:18)
- The copy flew beside you with your stick on its controls (user: "copy is following me").
- The hits reach the player plane's damage and are refused there: two missile hits (kind 2, 40 damage each, from the
  ordered enemy), health 1200 -> 1200, the game returned 0 both times (user: "missiles have hit it a few times now").
  So on the host a hit on another player's plane can be caught at 0x147d5a430 (damage, kind, attacker) and sent to that
  player's game, where it hits their own plane, as Online Mode does.
- Restart Mission kept the copy (its tick on, fed) and Quit Mission went back to the main menu without a crash (user:
  "quit mission worked"; no new crash report): the shared-pointer fix holds.

## T3 build: the other players as real planes (0.73.4-coop2mp.5, runtime 0.30.0, protocol 4; 2026-10-30, not yet run)
Built while step 1 of Online Mode's weapons and damage (who decides a hit) is being researched. Damage stays as 0.72's:
each game's copies of the host's enemies attack that game's own player; hits on another player's plane here are
refused (T1e) and only counted.
- **Protocol 4** (runtime/coop.c): each P packet and Q record carries a flight block (CO_FL, 13 bytes: the stick int8
  x127 (pitch, yaw, roll, throttle, brake, high-G), the afterburner amount x255 (plane+0x39d0), the speed m/s x10
  (+0x2318), the State (+0x2b18)), filled from your plane (flight.c FlFlightBlock). A Q record is 62 bytes: the host
  sends as many Q packets as it takes (19 records each). Games on protocol 3 (0.72.x) don't link.
- **Real planes** (Scripts/sv_coop.lua peerTick, `[coop] real_planes = true`): each other player is spawned as their
  airframe's player plane (SV_CoopSpawnPP's seventh argument, their slot: one per slot) where their stream says they
  are, from the airframe code in their "hi" / the host's "pi" (a new last field). Bound with SV_CoopPeer, it isn't
  teleported (coop.c CoDrive asks FlFeeds): its own update flies it, fed before each RemoteUpdate (flight.c FlNetFeed:
  the pose where CoDrive would have put it, its last 0.1 s's direction, their block's speed, State and stick); its
  afterburner glow is their block's amount (OnSurfacePP). No code in their hello (an older build) or a spawn that fails:
  the AI stand-in as before (`coop: player N's real plane (<code>) not spawned: <why>; their AI stand-in instead`).
- **The host's split hunt** (and the squad director's cover, push and a held flight's release on a joiner): with real
  planes up, a flight is ordered onto one player's real plane (COOP.huntReal: EngagementOrderOverride Normal, that
  plane, TargetFirst, fire bits 7 on each of its planes; the given player's, else the real plane the fewest flights are
  on) instead of the stock hunt (RE_SV_Hunt_NN, AIFirst: it finds no player plane). Every 5 s a flight whose target went
  (down, hidden, gone) is ordered onto another real plane, else back on the host (COOP.huntHost: PlayerOnlyNoLimit).
- **Not on real planes yet (T4)**: their missiles, gun, flares and gear (0.72.2's sync fires an AI stand-in's weapons
  and EnableLandingGear: skipped on a real plane, `coopfire: player N's plane here is their real plane: their shots
  aren't shown on it yet`). Their paint: the plane's default.
- **Test (two or more players, the same build: friends the zip, the user's own install the dev stage)**: pick
  different aircraft (one the ADFX-02). Look: each other player as their own aircraft, smooth, their control surfaces
  and afterburner moving with theirs; host flights going after the joiners; a player shot down (DOWN) hidden and back
  after a revive; the revive camera on a real plane.
- **Log** (AC8SurvivalMode_lua.log): `coop: player N's plane is their real <code> (a player plane, <addr>): flown by its
  own update from their stream`; `coop: <unit> goes after player N's real plane (K planes ordered onto it)`;
  `director: cover for player N: RE_SV_Hunt_NN: onto player N's real plane (K planes)`; `coop: <unit>'s target (player
  N) is gone: ...`. AC8SurvivalMode.log: `coop: player N's real plane is <p>`, `coop: player N's plane is <p> (a real
  player plane: its own update flies it, fed from their stream)`, `coop2mp: player N's real plane <p> fed from their
  stream: speed S m/s, flight block yes, State <x>` (`NOT YET` from a game that sends none), then once a minute
  `coop2mp: player N's real plane: F frames fed, K not ...; at most M m off where it was sent; H hits on it here
  (refused: their own game takes its hits)`.
- Checks: flight_test.sh (the flight block from P kept and put in the Q record), coop_test.sh (4 and 12 players on
  protocol 4), the Lua suites. Packaged: build/release/AC8SurvivalMode_COOP2MP_0.73.4_Online_COOP_NoValka.zip (build
  hash 9d04afb2...b66523); the dev stage (test keys) installed as the user's own.

## Online Mode's weapons and damage (research of 2026-10-30; [C] checked in the code by the main session, else the agent's)
- Hit authority: one check, CanBeDamagedBy (0x147d2afb0, a jmp into the protected section's body 0x15c915570), on
  every hit through the game object's TakeDamage 0x147d203e0 [C]. Its virtuals: +0xaa0 is a player plane, +0xab0 is AI,
  +0xc40 / +0xc48 / +0xc50 the role byte +0xed8 == 3 / 2 / 1 [C]. Refused: a role-2 player attacker; a role-2 target hit
  by AI (T1e's 40 damage); a role-1 target hit by a role-2 attacker; a role-2 target is hit only by a role-3 attacker [C].
  Roles [C]: 1 by default and every local plane offline; online your plane 3, a remote player 2, AI 3 on the AI's host
  and 2 elsewhere. So AI shots are decided on the target's own game and a player's on the shooter's.
- After the check [C, 0x147d20971]: offline the damage is applied there (0x147d20aa0); online (gm+0x1fa) a game that
  isn't the host with gm+0x739 only reports it (0x147d2b530 -> SendDamage 0x1474bcbb0).
- A player's shot elsewhere [C]: the remote plane fire 0x147d71ea0(plane, &{ExplosiveWeaponFire*, ctrl}) needs the
  plane's ULiveNetworkPlayerPlane (+0xed0) and weapon system (+0x16a8); latency = min((now - message +0x08) x 1e-7, 3)
  s, 0 when the message's time is in the future; reads the game mode's network manager 0x147ee02e0(world) unchecked
  (its +0x2e0 network-id map); skips an empty electronic-measure array (+0x30, 0x18 each); per WeaponData (+0x20, 0x50
  each: +0x08 network id, +0x10 / +0x14 target type / id, +0x18 int3 target location, +0x24 weapon number, +0x25 spawn
  slot, +0x26 ?, +0x27 seed, +0x28 lock-ons, +0x2c int3 start, +0x38 float3 rotation, +0x44 float3 velocity):
  0x147f63c00, the slot (0x147f7c300), the seed into weapons +0x534 / +0x538 / +0x540, LaunchWeapon 0x147f7a880(weapons
  +0x2e0, number, target (from the map: none offline), &projectile, &slot, 0, 0, lock-ons, ...), the projectile's +0x6b4
  seed and +0x6e8 network id, then its vf+0x8a0(&start, &rotation, &velocity, &target location, latency); a NULL ctrl
  is never touched. The shooter's side [C]: PlaneWeaponsFired 0x147d71060(plane, TArray<AActor*>*), called by the
  weapon system after each launch (0x147f58d86, 0x147f59177), offline too; only its sender 0x147d71320 needs a network
  object. The sender reads the projectile's +0x3a8 / +0x6d0 / +0x6d4 / +0x6b4 / +0x3c8 bytes, +0x6e8, +0x3f0 target,
  root (+0x1a0) +0x220 location, GetVelocity (vf+0x358) [C].
- Flares [C]: FireFlares 0x147f61d90(weapons), called by the PushFlare handler and by your own flare press
  (0x147f58009). The gun [C]: the HoldingMachineGunButton handler sets weapons +0x311 (the remote trigger) from its
  bTrigger; the weapon system's update fires on +0x30e (yours) or +0x311.
- The agent's (not re-checked): an AI's shot elsewhere goes to the AI's copy's FCS module vf+0x358 (0x147c975c0);
  Damage / DamageClient / Health / ExplosiveWeaponHit layouts and handlers (ApplyDamageResult 0x147d2b690, SetHealth
  vf+0x918 0x147d1cb80); the dispatcher 0x1475034c0 and that network objects are registered only online; the clock.

## T4a build (0.73.5-coop2mp.6, runtime 0.31.0; installed 2026-10-30 as the user's test install, not yet run)
Solo, the Ctrl+F11 copy of your own plane's class (fed as T1c-T1e): each launch of yours is read at PlaneWeaponsFired
(hooked) as the online sender reads it and replayed from the copy the next frame through the remote plane fire, its
start moved by the copy's offset from you, LaunchWeapon (hooked) given your missile's target for it (the network-id map
is empty offline); your flares (FireFlares, hooked) fired from the copy's weapons; your gun's trigger (+0x30e) put on
the copy's remote trigger (+0x311) every frame. The network manager is checked before each replay. Another airframe
replays nothing (its weapon numbers aren't yours: T4b gives each player's real plane their own loadout).
- Look: the copy launching the same missile / special as you, from itself, flying at your target (homing?); its flares
  with yours; its gun with yours. Their hits should do nothing (role 2).
- Log (AC8SurvivalMode.log): `launch weapon: hooked`, `fire flares: hooked`, `player plane weapons fired: hooked`;
  `coop: second player plane ...`, `coop2mp: plane <p> fed from <p> ...; your shots replayed: yes`; the first 6 shots
  `coop2mp: T4: your shot (weapon N, slot S, lock-ons L, seed X, target <p>) replayed on the copy: launched, its missile
  <p> (target <p>, ...), the network manager <p>`; each second with any `coop2mp: T4 this second: your launches N (M
  missiles), queued, replayed A launched / B not, C dropped; your flares, the copy's; your gun trigger frames (+30e)
  (+311), the copy's trigger set N times`. Problems: `no network manager here`, `NOT LAUNCHED`, `another airframe`.
- The friends' zip of this build (T3 + T4a's hooks, which do nothing outside the solo test):
  build/release/AC8SurvivalMode_COOP2MP_0.73.5_Online_COOP_NoValka.zip (hash 2f62ee32...0d4fff), in place of 0.73.4's.

### T4a results (the user's solo test, 2026-10-30 19:58-19:59)
- Missiles replayed and launched from the copy (3 of 3; no lock: target 0); flares (1 of 1); your gun's trigger (+0x30e
  and +0x311 both set while you fire) put on the copy's +0x311.
- The laser didn't fire on the copy (user: "laser not working on other craft, working on mine"): it isn't a
  LiveExplosiveWeapon (`your launches 1 (0 missiles)`), so T4a skipped it.
- With the input fed through its pointer (T1e), the copy's own engine now makes its afterburner amount and State
  (`left on it up to 1000`, `State bits yours 8, its 8`): the OnSurfacePP write is now only a backstop.

## Special weapons and the gear, Online Mode's way (research, 2026-10-30, checked)
PlaneWeaponsFired tells four kinds apart by class (its calls to each StaticClass): LiveExplosiveWeapon (+0x34:
ExplosiveWeaponFire), LiveAttachedInstantWeapon (+0x70: the laser, InstantWeaponFire via 0x1474d9c50),
LiveBullet (+0x146: BulletWeaponFire via 0x1474d9de0) and LiveElectronicWeaponBase (+0x1b0: ESM / ECM,
ElectronicMeasureFire via 0x1474d9f60). Their handlers (0x1474db3f0, 0x1474db6c0, 0x1474db9b0) do, on the role-2
plane: select the special (0x147d71e20(plane, weapon number): weapons +0x308 = number - 1; only these handlers call it)
and arm it (0x147d62ab0(plane, true)); a bullet special is armed and disarmed. The LandingGear handler (0x1474dca90,
message +0x20 bGearDown, +0x21 bForceCancel, +0x22 bLanding, +0x23 bCarrier) calls gear down 0x147d594c0(plane, force
cancel, landing, 0) or gear up 0x147d59730(plane, carrier) (a jmp stub into the protected section).

## T4a.2 build (0.73.6-coop2mp.7, runtime 0.31.1; installed 2026-10-30, not yet run)
- The Ctrl+F11 copy: your laser, bullet specials and ESM / ECM replayed the handlers' way (select, arm; a bullet special
  armed and disarmed): `coop2mp: T4: your laser (weapon N) replayed on the copy: selected and armed (its selected special
  now N)`; your gear mirrored (`test: your gear down: the copy's 1`).
- SV_CoopPPFx(plane, kind, value) (kind 0 flares, 1 the gun's remote trigger, 2 the gear) on another player's real
  plane; co-op's sync (sv_coop.lua peersTick) uses it for real planes from the flag bits every game already sends (16
  gear, 64 gun, 128 flares): in co-op the other players' gear, gun and flares now show on their real planes. Their
  missiles and specials in co-op: T4b (a new message with each launch).
- The friends' zip of this build: build/release/AC8SurvivalMode_COOP2MP_0.73.6_Online_COOP_NoValka.zip (hash
  fa821c65...895796), in place of 0.73.5's.

### T4a.2 results (the user's solo test, 2026-10-30 20:07-20:08)
- The laser (weapon 2) and the ESM (weapon 3) were selected and armed on the copy, Online Mode's handlers' way, but the
  laser didn't fire (user: "laser didn't fire"): the arm call (0x147d62ab0) only arms (the armed cue, the HUD), no shot.
- The gear didn't come down (user: "gear didn't go down") though the gear-down call ran: your State had bit 9 (0x200)
  with the gear down (0x40A00, then 0x40200), RemoteUpdate puts the gear up or down from bit 9 every frame, and the feed
  cleared it.

## T4a.3 build (0.73.7-coop2mp.8, runtime 0.31.2; installed 2026-10-30, not yet run)
- Bit 9 sent (FD_STATE_LOCAL: bit 20 only): the copy's gear from your State, as a remote plane's is online; co-op's
  real planes the same from the flight block.
- The laser launched from the copy's weapons after select and arm: the remote fire's own steps (0x147f63c00(weapons,
  0.0, 1), the slot 0x147f7c300, the seed, LaunchWeapon, its two lists freed through GMalloc), their addresses read from
  the remote fire's code, without its explosive-only writes (FwLaunchDirect). Log: `coop2mp: T4: your laser (weapon N)
  replayed on the copy: selected and armed (its selected special now N); launched from its weapons, launched 1 (<p>)`.
- The friends' zip: build/release/AC8SurvivalMode_COOP2MP_0.73.7_Online_COOP_NoValka.zip (hash a39fddb8...8a9465).

### T4a.3 results (the user's solo test, 2026-10-30 20:16-20:18)
- The laser fires from the copy (user: "laser is now firing"; `launched 1` each time). Missiles and the gun as before.
- The ECM / ESM still showed nothing (user: "ECM didnt show", "can't tell if ECM is working"): only selected and armed
  (`launched 0`). ElectronicMeasureEffect (0x1474dbdf0) applies the effect to the planes jammed / marked (through the
  network-id map, 0x147d27c00), not to the user's plane: what shows on it is the weapon itself, launched as the laser.
- The gear still didn't come down (user: "gear did not go down on the other aircraft"): your State 0x40A00 / 0x40210
  was sent, the copy's own State read 0x40000 / 0x40010. The plane's own update makes bits 9 and 11 from its real gear,
  and RemoteUpdate's gear check (0x147d6f982) reads that State, so the gear sent never reached it.

## T4a.4 build (0.73.8-coop2mp.9, runtime 0.31.4; installed 2026-10-30, not yet run)
- The ECM / ESM launched from the copy's weapons as the laser is (FwLaunchDirect after select and arm).
- The gear, as RemoteUpdate's check does it, after RemoteUpdate (FlGear): the flight state's gear down
  0x144d33fb0(plane+0x2268, 1) when the gear sent (State bit 9) is down and the gear flag (+0x229c bit 0x10) isn't, up
  0x144d33ea0(state, 0, 0, 0) the other way; calls, flag and offset read from RemoteUpdate's code. The Ctrl+F11 copy
  from your State, co-op's real planes from their flight block's, SV_CoopPPFx kind 2 the same. Log: `coop2mp: T4: the
  copy's gear down (your State 40a00): 1`.
- The friends' zip: build/release/AC8SurvivalMode_COOP2MP_0.73.8_Online_COOP_NoValka.zip (hash c81ef480...1477cb).

### T4a.4 results (the user's solo test, 2026-10-30 20:23-20:24)
- The ECM / ESM launched from the copy's weapons (`launched 1`); the user couldn't tell whether it showed.
- The gear still didn't come down: FlGear lowered the copy's engine gear every frame (logged 8 times in one second), so
  something raised it again each frame.

## The remote plane's second flight engine (research, 2026-10-30, checked)
RemoteUpdate loads the physics message into a SECOND flight engine at plane+0x3c60 (0x1474d8c00(network object,
plane+0x3c60): `lea rdx, [rbx+0x3c60]` at RemoteUpdate+0xa2), gives it the input (SetInput 0x144d32580) and simulates it
(0x144d326e0) every frame, then blends the plane's own engine (+0x2268) toward it and copies its State over the plane's
(+0x2b18 = +0x4510). The second engine's simulation makes State bits 9 / 11 from its own gear (up), so the gear sent
never reached RemoteUpdate's check, which then raised the plane's own engine's gear lowered by hand.

## T4a.5 build (0.73.9-coop2mp.10, runtime 0.31.5; built 2026-10-30, installed when the game is closed)
FlGear moves BOTH engines' gear (the second first) after RemoteUpdate, from the gear sent: then the second engine's
simulation keeps bit 9 and RemoteUpdate's own check agrees. Log: `coop2mp: T4: the copy's gear down (your State
40a00): 1` once per change (not every frame). Zip: build/release/AC8SurvivalMode_COOP2MP_0.73.9_Online_COOP_NoValka.zip
(hash a053fcad...335881).

### T4a.6 (0.73.10-coop2mp.11, runtime 0.31.6): the gear's real cause
T4a.5 in game (2026-10-30): the copy's gear lowered and raised again every frame, its State 0. From the code:
- RemoteUpdate's gear check (0x147d6f982) compares the plane's State bit 9 (+0x2b18, copied from the second engine)
  with the own engine's +0x34 bit 0x10, and calls gear down (0x144d33fb0) / up (0x144d33ea0) while they differ.
- Engine +0x34 is the input's flags byte (the input message +0x20; RemoteUpdate's SetInput copies it to both engines).
  BuildFlightInput (0x147d689b0) builds it at out+0x18: 0x10 = State bit 9 (gear down), 8 = plane+0x13d1 == 1,
  4 = +0x1314, 2 = +0x1313, 1 = 0x147d660f0's answer; 4 alone when the plane has no control (+0x58dc).
- The engine simulation (0x144d326e0) sets State bit 9 = gear state +0x710 != 0, bit 10 = +0x710 == 1 and gear
  position +0x754 under a limit, bit 11 = +0x710 == 2. Gear down sets +0x710 = 1; gear up sets State bit 18.
- The feed wrote the flags byte as a fixed 4, so the input always said gear up while the State said down.
T4a.6 feeds the source's recorded flags byte (FlRecordInput keeps out+0x18); a co-op real plane gets 4 | (State bit 9
<< 4). FlGear stays (a no-op once the flags agree). Log: `coop2mp: fed plane ... gear: your input flags N; its engine
flags A / B, gear state C / D (own / second)`: with your gear down expect flags with 0x10 on both and gear state > 0.
T4a.6 in game (2026-10-30, user: "gear successfully lowered"): down at 21:07:05 and up at 21:07:13, one move each;
while down both engines' flags 10, the own engine's gear state 1 -> 2 -> 3 -> 1. After raising, the second engine's
gear state stays 1 (FlGear moves it only on a flag change); harmless in this test (the plane's gear stayed up).

## T4b build: the other players' launches on their real planes (0.73.11-coop2mp.12, runtime 0.32.0; not yet run in game)
- **Out** (flight.c FnCapture, OnPlaneFired): in co-op (CO.open) each launch from your own plane (CO.me) is read as T4a
  reads the copy's source: kind (0 explosive, 1 laser, 2 bullet special, 3 ESM / ECM, by PlaneWeaponsFired's class
  checks), weapon number (+0x3a8), and for an explosive one spawn slot (+0x6d0), +0x6d4, seed (+0x6b4), lock-ons (+0x3c8),
  where it started against your plane (cm, 500 m at most), rotation, velocity and target (+0x3f0). Up to 24 queued.
  SV_CoopShots() hands them over once ("k,w,s,u,seed,lock,rx,ry,rz,pitch,yaw,roll,vx,vy,vz,target;...", rotation x10,
  velocity cm/s, target an address); sv_coop.lua syncTick names the target by its stream id and adds
  `p:<id>:0:<shot>` to the tick's "fx" (beside m / s / e for the AI stand-ins).
- **Relay and guards** (sv_coop.lua fireShots): as every fx entry (FX_MAX a message, FX_STALE_MS, a lagging shooter), plus
  P_PER_S 16 launches a second a shooter, a shot of digits, commas and minus signs only, 200 characters at most.
- **In**: on a game where the shooter's plane is their real plane, SV_CoopPPShot(their plane, the target here, shot)
  queues it (32 at most; it checks the plane is role 2 and not yours, and every field's range); after that plane's
  next RemoteUpdate (OnRemoteUpdate -> FnFlush) an explosive one goes through the remote fire (start: their plane here
  + where it left theirs; target location from the target here, else 5 s along its velocity), the laser and ESM / ECM
  are selected, armed and launched from its weapons (FwLaunchDirect), a bullet special armed and disarmed. Over 1.5 s
  queued: dropped. Nothing while your STORE is open (the game holds the planes there).
- **Loadouts**: SV_CoopLoadout() reads your plane's loadout object (its two int lists, +0x30 / +0x40, and the two
  loadout bytes, as Online Mode's remote spawn copies them; CoLoadoutSites) as "a,b/c,d/x,y"; it goes in "hi" (and the
  host's "pi") as a 7th field, resent when it changes (new weapons at the airfield). SV_CoopSpawnPP takes it as an 8th
  argument (CoParseLoadout: 64 entries a list at most, bytes 0-255) and gives the plane those lists and bytes, another
  airframe's too; a real plane up whose player's loadout changed is spawned again with it.
- **Log**: AC8SurvivalMode.log `coop: second player plane: their loadout given (N and M entries, bytes A B)`,
  `coop2mp: T4b: player N's shot (weapon W, slot S, lock-ons L) on their real plane P here: launched (proj), target T`
  (8 at most), `coop2mp: T4b: player N's laser / electronic (ESM / ECM) ... launched 1`, then once a minute `coop2mp: T4b
  this minute: your launches sent N (D dropped); theirs N queued here, R refused, L launched, F not, S specials, ...`.
  AC8SurvivalMode_lua.log `coop: player N's plane is their real <code> ...; their loadout a,b/c/x,y`, `coopfire: player
  N's first launch on their real plane here: queued`, the minute's `real planes' launches (T4b) Q queued, R refused`.
- **Test (two or more players on 0.73.11)**: each fires missiles (locked and not), a special (laser, ESM / ECM, a bullet
  special) and flares; on the other screens each shows from their real plane at the right target, the special being
  theirs (not your plane's or the airframe's default). Then one changes weapons at the airfield: their plane is spawned
  again with the new loadout.

### T4b results (the user and a friend, 2026-10-30 21:34-21:37) and 0.73.12
- Worked: `their loadout given (15 and 0 entries, bytes 33 28)`; the friend's laser (weapon 3) "selected and armed,
  launched 1", missiles (weapon 1 / 2, lock-ons 0 and 1, at the stream's targets) "launched", flares.
- Crash (the user's game, 21:37:39): the friend browsed the airfield's weapon pages (their log 19:07:35-46, Kuala Lumpur
  time), their loadout changed, their "hi" went out again and the user's game replaced their live real plane
  (SV_CoopSpawnPP destroys the slot's plane first). A frame on: EXCEPTION_ACCESS_VIOLATION reading the old plane's
  address + 8 at 0x147443726 (`mov eax, [rax+8]`: an object's flags, read from a holder's +0x28), in a vfunc +0x60 run
  in a parallel loop (0x147434e50, from 0x1474703c0). Some game system keeps a raw pointer to a player plane; never
  destroy a live real plane mid-level (the level's teardown, Restart and Quit, are fine: T1e).
- The spectator camera on the friend's real ADFX-02 showed its cockpit: SetViewTargetWithBlend on an actor takes its
  first active CameraComponent, and a player plane carries its own.
- 0.73.12: a loadout change mid-level is logged and kept for the next level's plane; while you watch a plane its other
  CameraComponents (K2_GetComponentsByClass) are deactivated, ours activated, theirs back on as the view leaves it
  (`spectate: <plane>'s own cameras: <names>; N switched off while you watch it`).
- 0.73.12 in game (21:49-21:52): no crash through 4 loadout changes; the camera still inside the plane, on the ADFX-02
  and the X-40A alike (the user's screenshot: just behind the seat, pitched down: our camera, its 30 m / 8 m offset come
  out ~100x short), and no "own cameras" line (a player plane has no other CameraComponent). A player plane's root is
  scaled down. 0.73.13-coop2mp.14: the camera's distance from the plane is measured after placing it and its offset
  scaled by what it came out as (`spectate: camera on <plane>: D m from it (wanted 31 m); its offset xK ..., now D m`).
- 0.73.13 in game (22:01): our camera measured 31.0 m behind the ADFX-02 and the view was still inside it: the view on a
  player plane takes the game's own player-plane camera, whatever is added. 0.73.14-coop2mp.15 (runtime 0.32.1): the
  replay viewer's way (the user: "make it like the Replay Actor, without the time skip"): SV_SpawnCam spawns a CameraActor
  (the world spawn, as the dummy controller), attached at the end of a SpringArmComponent added to the watched plane
  (camera and rotation lag, no collision test, level horizon); the view on the camera actor, never the plane; SV_StickNow
  reads your stick from the plane's input fields (+0xff8 pitch, +0xff0 - +0xfec yaw, +0xff4 roll, +0xfe4 throttle,
  +0xfe8 brake: before DOWN's autopilot) and swings the arm (110 deg/s), throttle / brake zoom 10-150 m. A restart while
  down puts the view back from the camera actor too. coop_revive_test covers it.
- The user's co-op run of 2026-10-30 (0.73.13, 22:02-22:08, 3 players): Alessia landed her EA-36 (22:03:50) and sat in
  the STORE; at 22:05:05 Cressendo went DOWN and the flight on him was sent onto her real plane (COOP.huntReal picked
  any shown real plane), and hit it 5 times on the runway on the host's screen (refused there) while she bought his
  revive. 0.73.15-coop2mp.16: realTarget skips a player at their airfield (state bit 4) or DOWN; the 5 s check moves a
  flight off a player who lands (`coop: <unit>'s target (player N) is landed at their airfield: onto ...`).
  coop_fire_test covers it.
