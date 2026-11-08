# IFF FATAL ERROR / DI..ANT TH..D..R: the lightning Anomaly, and the storm test (0.74.0, test builds only)

The user, 2026-11-06: "another Anomaly, one that uses Lightning Against you", "The Aircraft is an A-10 and the name of the
Anomaly is IFF FATAL ERROR / DI..ANT TH..D..R", "Strikes should only black out and disorient you", "Make it so that it can
only be spawned with the test key".

Everything is TEST ONLY: `Scripts/sv_anomalies.lua`'s last block (`THUNDER`), `CFG.specials.thunder` and its `INI_ALIAS`
entries (`sv_config.lua`), and the `[thunder*]` sections of `config/survival.default.ini`, each between `TEST ONLY BEGIN` /
`END` marks. `tools/strip_test_only.py` takes the Lua out of a release (friends' zips); TESTER builds and the dev install keep
it. It is never in `CFG.specials.rotation`. Not yet run in game.

Release caveat: `package_release.sh` strips only `Scripts/*.lua`, so a release's `survival.default.ini` still carries the
`[thunder]`, `[thunder.storm]`, `[thunder.fx]` and `[thunder.test]` sections (the loader logs `no section [thunder...]`
for them). Their marks are `strip_test_only.py`'s own (`; -- TEST ONLY BEGIN` ... `; -- TEST ONLY END`, a blank line after),
so adding `"$mod/config/survival.default.ini"` to that script's call in `package_release.sh` removes them cleanly (checked:
`ini_check.py` passes on the stripped pair).

Research: `build/research/lightning/LIGHTNING.md` (what a strike does: no damage; the HUD hidden 2 s, electronic noise 6-10 s,
the stall flag `LS_StallTime` 0.7 s, a camera shake, a bolt; player planes only, about one strike every 10 s inside a storm).

## The keys

| Key | Where | What |
|---|---|---|
| Ctrl+, (comma) | any game, in a run | The storm test (LIGHTNING.md 7). 1st press: the stock storm (`BP_LightninigVolume_MS12_C`, spawned deferred, `Radius` = `[thunder.test] radius_m` x 100 set before it begins play) on you for `seconds` (60), moved onto you every tick. 2nd press: your plane's `LS_StallTime` = `stall_s` (3.0) and another 60 s. 3rd press: off, `LS_StallTime` put back. |
| Ctrl+. (period) | host or solo, in a run | The next round is IFF FATAL ERROR's (in the break: it starts in 3 s), as Ctrl+1-8 force the other specials. A joiner is refused. |

Both go through `testKey` (sv_core.lua): the run is unranked; a clash logs `test: Ctrl+<key> is bound twice`.

## The Anomaly

- **Unit:** `SV_Unit_Anomaly` (MINDRIPPER's), with `SV_SetAircraft(unit, "a10c_common")` = the plain campaign A-10
  (`OP1001_a10c_01`; never `OP1001_a10c_Named`, whose `NLID_0400_CP` set never attacks: hard rule 22). Why this unit: it is
  a one-aircraft unit built for a boss, it is already spawned with `SV_SetAircraft` for MINDRIPPER, its behaviour is
  Survival's fighters' set built at level load from MINDRIPPER's row (hard rule 20: SV_SetAircraft changes the airframe and
  AI module, not the behaviour), and its stock records give the A-10 at its appearance the pool's orders (search, engage
  `PlayerOnlyNoLimit`), the MISSION UPDATE banner and beep, the forced WARNING, the radar noise, the Anomaly's attack
  throttle and the Celaeno core's crackle, and at its death the Celaeno's death sounds and the throttle back. No build data.
  The two never meet: one special a round, and `ready()` refuses while the unit has anything up.
- **Spawn:** `spawn_km` (8-12 km) from you, the pool's heights, AI level `ai_level` (5), the top skill tier; its round flies
  alone (`alone`, one aircraft). Its box's callsign line is `DI..ANT TH..D..R`: the plane's `CallsignId` set to `SV_Thunder_Name`
  (its text set with `SV_SetText`) before its box is made, put back at its end; its type line stays the A-10's
  (`ObjNameID` is only logged: it may be the name the event records find it by). Its warning: `WARNING: IFF FATAL ERROR /
  DI..ANT TH..D..R: ITS STORM BLINDS YOU`, MINDRIPPER's focus camera (`RE_SV_AnomalyCam_E`), and
  `AKE_GEN_ENV_AMB_ThunderCloud_Outside_DistantThunder_Play` (its `_Stop` at its death).
- **Health and pay:** `health` (1000 HP) x (1 + `health_per_round` a round after `specials.first`, at most `health_max_x`),
  written once on the host (`MaxHealth`, `HealthInternal` x 10); `reward` + `reward_per_round` a round, a special's pay
  (co-op: split as every special's).
- **Its storm:** the same stock volume, `[thunder.storm] radius_m` (3 km) round it, moved onto it every tick. The game's
  lightning observer rolls the strikes (every 3-5 s, the `MS_12` curve; `CUR_LightningWeight` is loaded and pinned so it is
  found): no damage, player planes only. The storm comes off at its death, at its round's end, while you're DOWN, on a
  restart (the tick sees no hunt) and is forgotten untouched when the level goes (`LEVEL_DROPS`).
- **Removal is never a plain destroy:** the observer reads the first storm a plane entered through a weak pointer and
  doesn't check it (0x147ed60c0: a destroyed one is read at NULL + 0x340). A storm being taken off is shrunk to 1 cm where it
  is and destroyed only after its `InsideGameObjects` has been empty twice; otherwise it stays parked.
- **Its look:** the game's `NS_CloudLightning` at it every `[thunder.fx] every_s` (2.5 s), switched off `life_s` on.
- **Co-op:** the host spawns it (the spawn mirrored with its SV_SetAircraft, as every flight's); `"rnd"` field 12 carries
  `thunder:hunt`; each joiner keeps its own storm on its live copy (`ANOM.liveCopy`), names the copy's box, sets its
  `MaxHealth` (its health is the host's `"hp"`), takes it off while DOWN and when the host's is over; every game rolls its
  own strikes. The host's `RE_SV_AnomalyCam_*` and `RE_SV_AnomalyEnd` are forwarded as MINDRIPPER's are.

## Log lines

- `thunder: Ctrl+. (period), round N is IFF FATAL ERROR / DI..ANT TH..D..R (starting in 3 s | after this round)`
- `thunder: IFF FATAL ERROR / DI..ANT TH..D..R as a10c_common on SV_Unit_Anomaly (1 set), X km from you at bearing B, Y km up: 1 aircraft up`
- `thunder: its box (<plane>): CallsignId '<was>' -> 'SV_Thunder_Name' (reads back '...', GetCallsign() '...'; ...), ObjNameID '...'`
- `thunder: its warning; its camera LookAt_Event_Camera_ms22-01 (1); its sound ...: posted`
- `thunder: DI..ANT TH..D..R's health xH for round N: HP HP (MaxHealth a -> b, HealthInternal c -> d)`
- `thunder: storm up for the <test|boss|copy> at (x, y, z), R km round it (radius, curve): reads back Radius ... cm, strike rolls every 3.0-5.0 s, curve MS_12, bEnableCollision true, bTestPlayer true, bTestEnemy false, its flash light there (...)`
- `thunder: the HUD's BeginHUDDistortionLightning hooked, EndHUDDistortionLightning hooked (...)`
- `thunder: the camera shake manager found (...)` / `NOT found (looked for 3 times a storm, 10 s apart)`
- `<label>: strike N at +T s (seen by <signals>); your health H, S km/h, pitch P deg; K AI planes inside the storm`
  (label `storm test` or `thunder`; signals: `the HUD's BeginHUDDistortionLightning (noise X s)`, `a lightning camera shake
  (<class>)`, `the HUD hidden (visibility v, opacity o, bShowHUD b)`)
- `<label>: strike N, 3.5 s on: ...; your health A -> B (unchanged | MOVED); S0 -> S1 km/h, pitch P0 -> P1 deg; the HUD hidden X s; K AI planes were inside: ...`
- `<label>: the HUD back after X s`, `<label>: a flash (its point light I) at +T s` (always for the test, verbose log for the Anomaly)
- `storm test: Ctrl+, (comma), the storm on you for 60 s, 3.0 km round you; your plane (...): LS_MinDebuffTime 6.0, LS_MaxDebuffTime 10.0, LS_StallTime 0.7; health ..., MaxHealth ...`
- `storm test: +N s: health h h h h; S km/h; K strikes, F flashes; A AI planes inside` (a line a second; health read every tick)
- `storm test: your health moved A -> B at +T s (...)`, `storm test: Ctrl+, (comma) again: your plane's LS_StallTime 0.7 -> 3.0 (written; ...)`
- `storm test: over (<why>) after N s: K strikes seen (<signal> xN, ...), F flashes; your health lo..hi over N samples (it never moved | it MOVED); LS_StallTime back to 0.7`
- `thunder: the <owner>'s storm off (<why>) after N s: ...; shrunk to 1 cm, destroyed once nothing's inside it`,
  `thunder: the <owner>'s storm destroyed X s after it was taken off (nothing inside it)`,
  `thunder: the <owner>'s storm kept (1 cm) 30 s after it was taken off: InsideGameObjects ...`
- `thunder: round N, DI..ANT TH..D..R shot down T s after it appeared; RE_SV_AnomalyEnd fired, its sound's stop posted`
- `coop: thunder: the host's DI..ANT TH..D..R here: its copy's MaxHealth a -> b (its health comes from the host)`

## What Lua can see of a strike

The strike path calls the HUD's `BeginHUDDistortionLightning` directly from C++ (0x147d4f8ac -> 0x1472419f0), so a UE4SS hook
on that UFUNCTION most likely never fires; it is hooked anyway and logged. The other signals, read every tick while a storm is
up: a `BP_CamShake_Lightning` shake in the camera shake manager's `ActiveShakeList` (`LiveCameraShakeManager`, found by one
walk, at most 3 a storm), the HUD widget's visibility / opacity and `bShowHUD` against their values at the storm's start, and
the volume's `LightningPointLight.Intensity` (its flash: maybe misses too, so counted apart). Which of these work is what the
first test finds out.

## Test checklist (first in-game test, a TESTER or dev build)

1. Ctrl+, (comma) in a run: `thunder: storm up for the test ... reads back Radius 300000 cm`. Fly 60 s: strikes in the log
   (about 6), each with the HUD hidden ~2 s, noise, a shake, a bolt; your health line never changes (`it never moved`).
   Note which signals the strike lines name; none at all means the volume doesn't strike when spawned from Lua.
2. Ctrl+, (comma) again: `LS_StallTime 0.7 -> 3.0`; watch the next strikes' follow-up lines (speed and pitch over 3.5 s) and what
   the plane does for 3 s.
3. Let an enemy flight follow you inside: the follow-ups' `AI planes were inside` (no bolts on them).
4. Ctrl+, (comma) a third time: `storm test: over`, then `the test's storm destroyed`. The thunder ambience stops.
5. Ctrl+. (period) in the break: the next round is SPECIAL / IFF FATAL ERROR; an A-10 boxed `DI..ANT TH..D..R` (or the `its box` line
   says what `CallsignId` holds), the MISSION UPDATE beep, the WARNING, the camera, the distant thunder; its storm 3 km round
   it (strikes once you're close); its NEXT row `DI..ANT TH..D..R: X KM` / `IN ITS STORM`. Shoot it down: its pay, the storm
   off and destroyed, the WARNING off.
6. Co-op (2 players): the joiner sees the A-10 with the name, gets strikes near their copy of it, nothing after it's down.
7. Quit Mission with a storm up: no crash; `thunder: the level is going ...` or the level gate's drop.

Checks without the game: `sh tools/checks/thunder_test.sh` (its Lua on the real parts, and a release's copy: no trace, loads).

## The first test, and Survival's own strikes (2026-11-08, 0.74.34 -> 0.74.35)
- The user's storm test of 0.74.34 (Ctrl+, twice, about 50 s inside a 3 km storm on her plane): **no strike**. "I saw nothing
  happen to my aircraft with the storm", "my hud was not effected either". The one "strike" the test logged (20:28:53, the
  HUD's opacity 0 for 11.5 s, the speed frozen) was the pause menu (`hud: hidden (paused)`, the BGM paused, the same
  seconds). Why the stock volume doesn't strike here isn't known: no observer in this level (Missions 12 / 16 name a
  LightningVolumeClass in their world settings, Survival's level doesn't), or the spawned volume never takes the player in.
  Hard rule 60.
- The user's design the same day: the storm gathers over 3 rounds into a typhoon; strikes every build-up round, small and
  rare cells first; the typhoon's storm bigger (7 km), faster strikes, longer effects, 10% of your health a strike; test
  key only for now.
- **0.74.35: Survival rolls the strikes itself** (`[thunder.strike]`, CFG.specials.thunder.strike): no stock volume
  (stock = false; true spawns it as before). While your plane is inside the storm's sphere (THUNDER.storm: centre, radius;
  not DOWN, never while paused: the game clock), a roll every roll_s (1.5-2.5 s), chance[k] for the k-th roll since the
  last strike (0.35, 0.5, 0.65, 0.8). A strike: the HUD's own `BeginHUDDistortionLightning(static_s, info)` (HideHUDTime
  blackout_s 3.5, the distortion 0.3-1.0, static_s 10-16 s, then `EndHUDDistortionLightning`), the struck and lightning
  damage sounds on your plane, the static's noise (`AKE_Ms12_UI_HUD_Thunder_ElectronicNoise_Play` / `_Stop`), the lightning
  camera shake (BP_CamShake_Lightning x shake_scale 1.5), the electric discharge on your plane (NS_ElectricDischargeM001),
  damage_pct 10 of your MaxHealth (DECOY.hurtMe: HealthInternal written; a lethal one THE DECOY's kill record), your
  controls upset upset_s 1.5 (SV_Invert: roll inverted, throttle and brake swapped; in place of the stall flag, which only
  the game's own strike sets; never over MINDRIPPER's field). A miss: NS_ElectricEvasion001 400-550 m ahead and
  NS_ElectricSign001 on you. Inside: `AKE_GEN_ENV_AMB_ThunderCloud_Inside_Ambience_Play` / `_Stop`, each roll's
  `..._Inside_Lightning_Play`. Each game strikes its own player (co-op). Log: `lightning: you're inside <owner>'s storm`,
  `lightning: strike N on you (...): HUD out 3.5 s, static N s; shake on; bolt on you; -N HP ...; upset on`,
  `lightning: the static over`, `lightning: you're out of <owner>'s storm`. thunder_test.
- Next: the 3-round build-up (the sky toward CSP_ms12_260216, distant thunder, flashes closing in, small cells with
  strikes from N-3, rain and the air-current volumes if they work), its own test key.

## The storm's build-up (2026-11-08, 0.74.36; not yet run in game)
The user's design: "have the storm gather for 3 rounds slowly building up until it's literally a typhoon to deal with
inside"; strikes every build-up round, small and rare cells first; test key only. CFG.specials.thunder.buildup,
sv_anomalies_dev.lua (BU), thunder_test.
- **Keys:** Ctrl+] (host or solo) starts it: Distant Thunder at round N = the next round + 3 (in a break) or this one + 3
  (in a fight); stages 1-3 are rounds N-3 .. N-1 (stage 1 at once), 4 is round N (`D.forceSpecial = "thunder"` from round
  N-1). Pressed again: the storm clears. Ctrl+' steps the stages by hand (1, 2, 3, 4, then clear) in any round.
- **Sky:** Survival's sky asset (Mission 4's CSP) blended toward Mission 12's storm sky (CSP_ms12_260216, loaded at run
  time): every candidate cloud field (13 of FSkyParams', 21 of each of the 3 cloud layers') the two differ in, read from
  both and logged (`storm build-up: N of 76 sky fields differ from Mission 12's storm sky (...): <path> a -> b, ...`);
  fraction 0.3 / 0.6 / 0.85 / 1.0 of the way, at most 1/300 of the way a second; bools at half way. Written through
  SKY.writeKey (SKY.addField registers each as asset|sv_storm_<i>): each original kept and put back at the run's end
  (hard rule 56); the clearing writes the base back over 90 s. Not yet seen in game: which fields make it look stormy.
- **Rain pillar (stage 4):** CloudLayer0.RainPillarCenterOverride / RainPillarCenterInKm (the A-10's storm centre, world
  cm / 100000) / RainPillarRadiusOverride / RainPillarRadiusInKm 6, every second; put back as it clears. Whether Cloudly's
  km are world km (and the pillar draws at all) is the test's.
- **Cells:** 2 / 4 / 6 / 6 of 2 / 3 / 4 / 4.5 km, columns up to 7 km, 6-28 km from the airfield, from the seed (the same on
  every game), drifting with one wind at 15 m/s, blown back in past 35 km; each flashes NS_CloudLightning at 2.5 km up every
  6-10 / 3-6 / 2-4 / 1.5-3 s, `AKE_Environment_Thunder_Play` within 12 km. Inside one, [thunder.strike]'s strikes at
  6-9 / 4-6.5 / 2.5-4.5 / 2-3.5 s rolls, chance x0.6 / 0.8 / 1 / 1 (`lightning: you're inside storm cell k (stage s)`);
  the typhoon (the A-10's 7 km storm) first where both.
- **Turbulence:** inside a cell or the typhoon from stage 2, BP_CamShake_Turbulence every 1.5-3 s x 0.5 / 0.9 / 1.4.
- **Rain (stage 3):** the world settings' (ChronicleWorldSettings, found by a walk) bIsWorldRain true, RainVFXBrightness
  10 (Mission 13's), put back as it clears: `rain bIsWorldRain written (read back ...)`. Whether the rain shows when set
  after the level's start is the test's.
- **Sound:** `AKE_Ms12_ENV_AMB_DistantThunder_Play` from stage 1, `_Stop` once cleared. Callouts at each stage.
- **Co-op:** the host's "tb" (stage, seed, clearing) on a change and every 10 s (sv_coop_migration.lua, test builds only);
  a joiner builds the same cells from the seed; stage 0 ends it.
- Checks for the first test: the sky's change (and its log's field list), the cells' flashes and thunder, a strike in a
  cell, the turbulence, the rain, the pillar on the A-10, the clearing; perf (the cells' flashes are Niagara spawns).
