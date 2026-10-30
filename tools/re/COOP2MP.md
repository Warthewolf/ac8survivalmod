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
</content>
</invoke>

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
