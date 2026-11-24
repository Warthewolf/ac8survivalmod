# Survival's own Wwise sounds (2026-11-23 / 24)

Survival plays sounds of its own through AC8's Wwise, as AC8 plays its own: on its effects bus (the game's SFX volume),
3D from the camera, mixed with the game. Before this, Survival's own sounds went through its XAudio2 player in the native
runtime (sv_sound.lua SND: no game volume, its own pause). First user: ULYSSES' meteors (docs/re/ULYSSES.md); the SOLG's
test sound (Ctrl+O, TEST ONLY) was the pipeline's first. [D] = in code, [T] = confirmed by a test in game.

## The pipeline (tools/wwise)
- AC8 runs Wwise 2024.1.11 (SDK build paths in AceCombat8.exe; Wwise.uplugin 2024.1.11.9010.4075; banks v154). The sound
  project AC8_WWISE_PROJECT (.env): a blank UE 5.4 project with the Wwise 2024.1.11 plugin and its Wwise project; Wwise's
  install WWISE (.env). Nothing of either in the repo.
- `tools/wwise/spec.py` writes build/wwise/spec.json: the sounds (WAV sources outside git), their attenuations (metres),
  2D or 3D, loops, volumes; one event Play_<sound> each. `tools/wwise/build.sh`: WwiseConsole waapi-server,
  `waapi_build.py` (WAAPI over local HTTP) makes the objects, a SoundBank EACH event (SVB_<event>), generates them;
  WwiseReconcileCommandlet makes the AkAudioEvent assets (/Game/Mods/SurvivalMode/Wwise/Events/Default_Work_Unit/); the
  cook (VERSIONED, hard rule 42); retoc -> SurvivalMode_Wwise_P (build_all.sh stages it). [D, T]
- A cooked event asset carries its WHOLE bank (bulk data): six events in one 9.4 MB bank made a 56 MB container; a bank
  each, 9.4 MB. [T: the container's sizes]
- The bus is named "sfx", as AC8's own (Init.bnk: Master Audio Bus > PreMaster > sfx, id 393239870 = FNV-1 of "sfx"):
  Wwise ids are name hashes, so ours plays on the game's sfx bus; no Init.bnk of ours ever ships. [T: heard]
- `ListenerRelativeRouting`, `3DSpatialization`, `EnableAttenuation`, the loop flags and the volume are written on every
  sound, never left to Wwise's defaults. [D]

## Distances: AC8's listener scales by 10 (hard rule 79)
AC8's Wwise units are UE centimetres (its own attenuations in AKB_GameSe_Online run 300 to 2,000,000 units), but its
`DefaultListenerScalingFactor=10` (Live/Config/DefaultGame.ini, AkSettings) scales every attenuation by 10: N units are
N x 10 cm on the ground. A metre is 10 units (spec.py UNITS_PER_M). Written in centimetres, ULYSSES' impact meant to be
silent at 15 km was as loud at 16 km as at 0.3 km (the ulysound autotest of 0.75.103; also why the SOLG test of
0.75.66 / 0.75.67 never faded). At 10 units a metre (0.75.104): the impact -5 / -17 / -35 dB at 1.5 / 5 / 11 km and
silent at 16; the whistle -4 / -16 / -34 dB at 0.8 / 2.5 / 5 km and silent at 8; the core's -18 dB at 7 km, silent at
21. [T] Wwise hears from the camera (the view target), not your plane (an impact 300 m from the plane, 41 km from the
held camera: silent). [T]

## Playing them from Lua [T]
- At a place: `AkGameplayStatics.PostEventAtLocation(event, location, rotator, worldContext)` -> a playing id (> 0).
- On an actor, following it: `LiveSoundBlueprintLibrary.PostEventAtActorByAkEvent(event, actor)` (AC8's; its
  FLiveSoundPlayingID has no fields Lua can read): Wwise's component on the actor's root follows it. Stopped with
  `AkGameplayStatics.StopActor(actor)`: silence right after (the meter).
- 2D: a sound with no positioning plays the same wherever it's posted (on an actor of ours, to stop it with it).
- The event asset is loaded (SPC.V.asset: loaded and pinned) before a post: its bank comes with it.

## The pause
AC8's pause menu posts `AKE_System_SFX_Pause_On` / `_Off` (MUSIC_RADIO_CAMERA.md: LiveSoundManager's channels). Decoded
from AKB_GameSe.bnk (tools/pak_read.py, research only): 13 actions: Pause on four buses (one a child of sfx, 2618002316;
713852036 under the master; 982781640; 4134082696) and a layer container, SetBusVolume on three buses (755369548,
3101390487, 1942239001), five actions on events. Never the sfx bus itself, so ours (on sfx) would play on through the
pause menu. Their names aren't in the game (only hashes). Survival pauses its own: SND.setPaused (the stopped game
clock, sv_main.lua) tells SND.onPause; ULYSSES' ULY.wwPause runs `UAkAudioEvent.ExecuteAction(Pause 1 / Resume 2, no
actor = every game object, 0, 100 ms, linear)` on each of its loaded events. [D; the ulysound autotest's pause step]

## Measuring what's heard
`tools/autotest/loudness.ps1` (WASAPI loopback of the default playback device, levels only, every 100 ms) beside a job,
`tools/autotest/loudness_report.py` matches its levels to a suite's "SOUND ..." lines. The ulysound suite holds a camera
over the sea 41 km west of the airfield (your plane's engine out of earshot), mutes the music, and needs round 1 held off
(its config): its first runs heard round 1's Su-47s' missiles and warnings. AC8's own explosions posted by event
(the fleet's railgun impact, a ship's death) were silent in Survival's level (their banks not loaded there).

## Log lines
`ulysses: sound: Wwise's <event> loaded` / `NOT loaded (no SurvivalMode_Wwise_P?): Survival's own player plays it`,
`ulysses: sound: <event> posted by Wwise at a place: playing id N`, `... posted by Wwise on an actor: ok, N Wwise
component(s) on it`, `ulysses: sound: Wwise's N event(s) paused / resumed`.
