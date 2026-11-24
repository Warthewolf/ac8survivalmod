# ULYSSES: a special round back in July 1999 (2026-11-23)

The user: "Recreate the Ulysses Event from Strangereal, I want it to be A Special Round where we go back in time for a few
rounds". Her picks: pure meteor defence (no enemy aircraft), 2 rounds, a time-shift transition, a film look, AC:I's
meteors and Stardust sounds (her exception: docs/rules/sources_and_toolchain.md), "Meteors that fly over head a high
altitude during the mission too", "directly after the Festival Night during the early morning just as the Sun is rising".
Code: Scripts/sv_ulysses.lua (CFG.specials.ulysses in sv_config_arc.lua). Assets: tools/ulysses (build.sh, prepare.py,
ue_import.py: the container SurvivalMode_Ulysses_P; sounds.py: Sounds/ulysses). Test: tools/checks/ulysses_test.sh.
Tags: [D] decoded / in code, [I] inferred, [T] needs an in-game test.

## 1. When
Never drawn (sv_spawn.lua specialFor, right after THE FESTIVAL's): the day-night arc's first dawn rounds, F + 7 +
CFG.sky.arc.night_rounds (+ dawn_offset), `rounds` (2) of them. With GONE FISHIN' in round 9 (F) and 3 night rounds:
the festival 15, night 16-18, ULYSSES 19 (the shower) and 20 (the shower and the core) [D: ulysses_test].

## 2. The round
- No fighters (`alone`, aircraft 0): only fragments. busy until every fragment is shot down or landed (and the core sent).
- Fragments: round1 50 / round2 60 (solo the same; co-op + 0.15 a player past the first, at most 90; her call: "atleast
  50 spawn in waves of 2"), 2 at a time every 5-8 s (the first 8 s in), at most 30 falling (the 48 sound voices: 30 fall
  loops, the rumble and the explosions); the SOLG's KEW unit lends 36 targets, each handed back (disarm) when its
  fragment is shot down or lands; each a 45 degree dive from the east (AC:I's), 20-24 km up, at 1250-1350 km/h
  (75-98 s down; her call: higher, "around 1300km/h"), onto anywhere in area_km (x -30..+24, y -20..+15 km: the whole
  island chain and the sea round it, land or sea, never steered onto land; her call: "vastly spread out around the comona
  island"). Without area_km: the airfield (60 %) or a town (40 %), 2.5 km spread.
- Round 2's core: o_meta (~97 m) 45 s in, a 45 degree dive from 28 km up, 1300 km/h (110 s) onto the airfield; 4000 HP
  (solo x0.7).
- Shot down (its target at its floor, MinHealth 1: read back, hard rule 63's way): blown up, paid (fragments.pay 300 /
  big.pay 6000, x specialPay), LB stat ulysses_fragment / ulysses_core. Landed: blown up where it hits; within
  airfield_m (4 km) of the airfield its damage through AF.bomb (8 a fragment, 120 the core, the core wherever it lands);
  within town_m (2.5 km) of a town a callout; the sea or open land: harmless.
- The sky's meteors (scenery), AC:I's look (her Lost Butterfly references; AC:I's o_metx is an 8 cm marker with an effect
  drawn on it): thin glowing lines, no body, no smoke: the streak's static twin (SM_SV_Ulysses_Tail) on AC8's additive
  MI_TrainingRing (hard rule 77: on the skinned streak it falls back to dark grey). Bursts of 3-7 every 0.4-1.2 s, up
  to 100, from 5-40 km east of you (+X is east: checked in game against the minimap and the dawn sun), 150 km either
  side, 28-34 km up, at 25,000-40,000 km/h on a shallow fall (dip 0.1-0.2: 6-11 degrees; her call: "zoom across the sky,
  not at 45 degree"), each appearing high and crossing over to the west, streaks ~9 km (streak_x 0.36), burnt out above
  16 km (out of any fighter's reach) or at 12 s.
- The time shift: a fade in from white and the card JULY 1999 at round 1; at round 2's end the fade, PRESENT DAY.
- The film look: a full-screen warm wash over the picture (sv_hud.lua HUD.film: an Image on Survival's HUD canvas,
  behind its text; film.overlay / overlay_a, a slight flicker), faded in / out over 2 s on os.clock. The
  PostProcessVolume of ours is still made (saturation, tint, grain, vignette) but AC8's camera manager ignores it (the
  view is the plane's, no CameraComponent): the 0.75.72 autotest showed the wash, not the volume [D].
- Lines (subtitles.ini specials.ulysses.text.say.*): COMONA CONTROL at the start, the core, home.

## 3. How a fragment is made [D in code, T in game]
- An Actor of ours (the SOLG's newActor), a SkeletalMeshComponent with SK_SV_Ulysses_<A|C|D> (one bone ROCK; a static mesh of
  ours crashed the SOLG's test T0, a skeletal one drew), painted at run time: one dynamic instance of the x40a's gear
  material with T_SV_Ulysses_Rock_D / _N / _L (as sv_solg.lua paint), a RotatingMovement spin, a ProjectileMovement at
  its velocity (no gravity: its fall needs no tick), facing its fall. Trails (cfg trails): AC8's NS_DamagedSmokeNPC001
  (smoke) and NS_DamagedSmokeFireNPC001 (fire) attached. Its streak (the user: "Don't use the Rod's Streak, come up with
  your own"): SK_SV_Ulysses_Tail, a 25 m teardrop along -X of ours (tools/ulysses/prepare.py), behind the rock, painted
  as the rock is (the x40a gear material) with its white-orange-red gradient T_SV_Ulysses_Tail_D, its light-emissive
  slots tried for a glow [T: the glow]. Landing times on the round's clock (D.now, the game's), never os.clock: the
  0.75.72 run's rocks landed late, under the ground, when the two drifted apart [D].
- Landing: a trace down at the aim point; land: AC8's air explosion and the airfield's / town's damage; the sea:
  the Tonitrus Spear's splash (NS_Mission11Splash + NS_SplashRain, the user: "tonitrus spear water impact").
- Each rock is placed and turned through K2_SetWorldTransform with a plain scale (hard rule 78: an engine-read Scale3D
  made it fail and the rocks flew backwards); the autotest reads each front back (1.00 along its way).
- The fragments' trails: the Climber's fall smoke (Mission 20's IGC, scale 3: the thick billowing column; the
  ulytrails autotest compared 8 stock trails) and the damaged-plane fire; their streak's gradient a burning head.
- Its target box: one of the SOLG's target objects (the whole actor hidden: SetActorHiddenInGame; its meshes aren't
  found by class, and Mission 4's radar tower showed under a fragment up close; its TGT box, lock and minimap mark stay) (SV_Unit_SOLG_KEW for fragments, SV_Unit_SOLG_MAG for the core:
  Mission 4's radar tower base, enemy, TGT mark) spawned at the round's start, its meshes hidden, parked, its flags off;
  attached to the rock when it falls (its lock point onto the rock), its flags on, its health set; off and parked again
  when it's done. Its boxes read "ULYSSES" / "FRAGMENT" / "ULYSSES CORE" (SV_SetText on the SOLG's keys; the SOLG's own
  put back at the round's end: the two never come together). sv_rounds.lua finishes the two units off at its end.
- Assets (tools/ulysses, from AC:I): SK/SM_SV_Ulysses_A (o_meta 96.9 x 68.1 x 53.5 m), _C (o_metc 5.8 x 6.5 x 6.4 m),
  _D (o_metd 2.9 x 3.2 x 3.2 m), 644 triangles each (the same rock at three sizes). o_metb has no mesh in AC:I (a node
  tree and cutscene clips), o_metx a one-triangle placeholder, o_metc_d1..d4 the whole rock again: none built.
- Sounds: AC:I's Stardust set (tools/ulysses/sounds.py: fall_small = OBJ_FALL_STARTDUST_SMALL, fall_big, explosion =
  Stardust_EXPL_*, encounter = Stardust_Encounter, ambient = Stardust_Ambient) through AC8's own Wwise since 0.75.102 (the
  user: "get the wwise sounds working for the meteorites"): Survival's own events Play_SV_UlyFall / _UlyFallBig / _UlyBoom /
  _UlyEncounter / _UlyAmbient (tools/wwise/spec.py -> tools/wwise/build.sh: SurvivalMode_Wwise_P, a bank each, on AC8's
  sfx bus: its effects volume, its 3D and mix). Each whistle is posted ON its rock (LiveSoundBlueprintLibrary.
  PostEventAtActorByAkEvent: Wwise's component on the rock's root follows it) and stopped with it (AkGameplayStatics.
  StopActor), an impact at its place (PostEventAtLocation), the encounter and the rumble 2D (the rumble on an actor of
  ours, stopped with it). Fades (attenuations, metres): a whistle 0 / -6 / -18 / -36 dB at 0 / 0.8 / 2.5 / 5 km, silent
  at 7; the core's at 0 / 2.5 / 7 / 14 km, silent at 20; an impact at 0 / 1.5 / 5 / 11 km, silent at 15 (written at AC8's
  10 units a metre: hard rule 79, docs/re/WWISE_BANKS.md; measured in game, 0.75.104). Paused with the game (SND.onPause ->
  ULY.wwPause: AC8's own pause never reaches the sfx bus they play on). The whistle at -10 dB (0.75.105). A sound whose
  event doesn't load plays through Survival's XAudio2 player (Sounds/ulysses) as before (sounds.wwise.enabled = false:
  all of them). Log: `ulysses: sound: Wwise's <event> loaded`, `... posted by Wwise on an actor: ok, N Wwise
  component(s) on it`, `... posted by Wwise at a place: playing id N`. Autotest ulysound (+ loudness.ps1).

- Kept between its rounds: its meshes and paints are pinned (GameInstance.ReferencedObjects) and checked by name
  before reuse: kept by Lua only, they were collected through a minute's break with no rock up, and round 2 crashed
  (the ulysses2 autotest, 0.75.83/84). Land or sea: by the mesh the trace hits (`*_Env_Sea`), not its height (the
  runway traces at ~5 m). A fragment in the sea is harmless. The sky's meteors: 24-34 km up, east to west, 300 km
  across (her calls).

## 4. Co-op
The host's (or solo): the fragments, their targets, pay and damage. Joiners see the borrowed targets (the host's units)
and draw the rest from the host's word, "ul|<kind>|..." (sv_coop.lua COOP.ulysses, sv_coop_migration.lua, ULY.fromHost),
every value checked (coop_guard_test rows):
- `r|phase` its round: the fade and JULY 1999 at phase 1; the sky's meteors run while it's on;
- `f|id|key|x|y|z|vx|vy|vz|scale100|spin|big` a fragment launched (metres, cm/s): the same rock, trails and tail here;
- `s|id` shot down (its explosion), `l|id|land` landed (the explosion, or the sea splash);
- `e|last` its end (the rocks gone; at the last, the film look and sky off, PRESENT DAY).
[T: a co-op game.]

## 5. Log lines
`ulysses: round N: phase P of 2, K fragments[, the core at +45 s]; the film look on (4 of 4 settings written)`,
`ulysses: targets: SV_Unit_SOLG_KEW up, 36 objects borrowed`, `ulysses: paint: the rock's instance made, 5 textures in`,
`ulysses: a fragment shot down X s before it would have hit (Z km up), paid N`,
`ulysses: a fragment landed (aimed: comona) at (x, y km), in the land (the land map): the airfield -8` (or `: the town`,
`: harmless`), `ulysses: the core inbound: up, lands in T s`,
`ulysses: round N over: S of T fragments shot down, A landed on the airfield, B on the town, C in the sea, E on open land`,
`ulysses: film overlay: HUD.film true true, opacity X`, `ulysses: tail paint: its instance made`,
a joiner's: `ulysses: the host's round: phase P; the film look ...`, `ulysses: the host's round over[: home again]`,
`coop: the host's ULYSSES word not read: ...` (once).
Test key: Ctrl+Q (TEST ONLY): the next round ULYSSES, phase 1; again phase 2; again off.

## 6. Test checklist (her run)
1. Ctrl+Q, the next round: the white fade, JULY 1999, the film look (washed-out, warm, grainy), Comona Control's lines.
2. Fragments: rocks visible and painted, a fire trail, falling toward the airfield / town, a target box FRAGMENT on each,
   lockable, shot down (an explosion, pay); one left alone lands (an explosion, the airfield's health down).
3. Overhead: meteors streaking high across the sky.
4. Ctrl+Q twice, the next round: phase 2, the core 45 s in (ULYSSES CORE box), shot down or landing.
5. The round's end: the fade, PRESENT DAY, the film look gone, the sky's meteors gone.
6. In a run, round 19-20 after the festival's night: it comes by itself at dawn.
