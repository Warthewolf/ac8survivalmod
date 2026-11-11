# THE TANACORN's rise cinematic and its director

The user, 2026-11-11: "if there's a way for you to make a directors thing, maybe so i can visualise where I want to put
the cinematic camera, also look into turning the HUD off during the cinematic too".

Code: `Scripts/sv_cine.lua` (test builds only: the whole part is one test-only block, which tools/strip_test_only.py takes
out of every zip but a TESTER=1 one, leaving only its header), `Scripts/sv_hud.lua` `HUD.hold` (ships, does nothing until
something holds it). A TESTER=1 zip keeps the whole director: Ctrl+D / E / V / W work there, and the camera file is made
in the tester's config at the director's first use or the first rise, never at start. If the director must never reach a
tester, package_release.sh would cut sv_cine.lua to its header under TESTER=1, as it does sv_zfa44.lua without ZFA=1 (the
main session's call; not done). Test: `sh tools/checks/cine_test.sh`. The rise itself is `Scripts/sv_tanicorn.lua`
(`TANI.rise`, Ctrl+R; section 5 has the hook).

## 1. How to place the cameras

1. In a Survival run (TANI=1 build), **Ctrl+Y** (THE TANACORN's hull 5 km ahead of you, broadside) or **Ctrl+L** (the
   live hull): the director works on either.
2. **Ctrl+D**: director mode on (callout `DIRECTOR MODE ON`). Every 2 s a bright flash marks where each camera key's
   camera stands (AC8's Mission 23 far flash, the orbital rod's, at 3x). The log has a line a key: where it stands, what it
   looks at, its FOV and roll, how far it is from you.
3. **Ctrl+R**: she rises where she is, at 0.35x speed (`director_speed`), with no cinematic: you keep flying.
4. Fly round her. At each moment you want a camera, line up the shot and press **Ctrl+E**: a camera key at her time in
   the rise, from your view (callout `CAMERA KEY n AT t S`). It keeps the view's place, its direction (the point looked
   at is 500 m along it), its bank (roll: the callout says `ROLL n DEG`; the log says `roll NOT read: recorded level` if the
   camera's up couldn't be read) and its FOV. It's saved at once.
   - A key within 0.25 s of another replaces it (`REPLACED THE ONE THERE`), so pressing again at the same moment fixes a
     bad one.
   - In her 1.5 s hold, before she moves, the key is at 0 s (the log says `her hold: 0 s`).
   - With no rise playing, it's at the last key recorded + 1 s (the log says so).
   - If you edited the file since it was read, Ctrl+E reads it again first: your edit stays, with the new key added.
5. **Ctrl+V** to check them: each press puts your view on the next key's camera, the HUD off but its callout
   (`KEY n OF m AT t S`, under it `CTRL+D: BACK TO YOUR PLANE`). After the last, Ctrl+V once more gives you your plane
   back. **Ctrl+D** or **Ctrl+E** ends the preview at once, and so do 20 s with no press, your plane changing or going
   (shot down, respawned) and being down in co-op (the spectator's view). Not while you're down. Your plane flies on
   while you look, so preview while flying straight and high.
6. **Ctrl+D** again: director mode off.
7. **Ctrl+R** (Ctrl+R twice if one is still up): the rise at full speed with the cinematic. As her 1.5 s hold starts, the
   view blends over 1 s from your plane to key 1's camera (`enter_blend`, as today's rise camera does). As she rises it
   moves along one smooth path through every key (`blend = smooth`, section 3), getting to each at its time, without
   stopping; a `cut` key cuts to it. Both HUDs and the target boxes are off until it's over, Survival's callouts and
   subtitles still shown (`callouts = on`).
8. Not happy? Edit the file (below), or **Ctrl+W** for a new take: your keys are kept in their own file,
   `rise_camera.take_<date>_<time>.txt` (named in the callout and the log; nothing ever writes it again), and today's
   camera comes back.

Ctrl+D, E, V and W refuse outside a run and on a co-op joiner. Director mode goes off at a new run. UE4SS doesn't take a
key from the game, so the letter reaches the game too (a tap of D, E or W on the flight controls).

## 2. The file: `config\rise_camera.txt`

In the mod's folder (`...\Mods\AC8SurvivalMode\config\`, next to `survival.ini`). While it's missing the keys are today's
camera; the file is made with them at the first Ctrl+D / E / V / W or the first rise, never when the game starts. It's
read again at every rise, Ctrl+D and the first Ctrl+V of a preview, and at Ctrl+E when it was changed since it was read,
so an edit counts without a restart.

```
director_speed = 0.35
blend = smooth
enter_blend = 1
callouts = on
boxes = hide
hud = distortion widgets cheat showhud

;  t      at_f     at_s     at_u     look_f   look_s   look_u   fov      (roll)   (cut)
0        700      -650     12       300      0        40       55
5        680      -660     14       200      0        70       55
9        640      -700     16       80       0        15       55
15       600      -720     18       40       0        10       55
```

One key a line, 8 numbers (spaces or commas), then two you may add:

| column | meaning |
| --- | --- |
| `t` | seconds into the rise: 0 her bow still under, out at 0.8, standing 120 m up at 5, the slam at 9, at rest at 15 |
| `at_f at_s at_u` | where the camera stands, metres from her rest midships at the waterline: forward (+ to her bow), starboard (+ her right side, - her left / port side), up |
| `look_f look_s look_u` | the point it looks at, the same way |
| `fov` | its field of view in degrees (55: today's) |
| `roll` | (may be left out: level) its bank in degrees, -180 to 180 (+ its right side down); Ctrl+E writes it when the view was banked |
| `cut` | (may be left out, always last) the word `cut`: the view cuts to this key at its time instead of moving there |

Her rest frame is the hull actor's place and forward. The rise moves her about that place, so a key's spot is the same
place in the world for the whole rise. The four keys above are today's camera (the rig's `SOC_Cam`,
`tools/tanicorn/export_tanacorn.py` `RISE_CAM`: UE's x / y / z there are forward / starboard / up here), FOV 55.

A line that isn't a key is skipped and named in the log (`cine: config\rise_camera.txt line N skipped: ...`). A key within
0.25 s of a line above it replaces that line, and the log names both (`line N replaces line M (within 0.25 s of it): line
M not taken`): two keys can't stand a moment apart, so a sudden change is a `cut`, not two close keys. A file with no
good key gives today's camera (and is left as it is). At most 32 keys.

Settings:

| setting | values | what |
| --- | --- | --- |
| `director_speed` | 0.05 to 4 | the rise's speed in director mode |
| `blend` | `smooth` (default), `linear`, `cubic`, `easein`, `easeout`, `easeinout` | `smooth`: one smooth path through every key (section 3); the others: one blend a key, UE's EViewTargetBlendFunction (ease exponent 2). `cubic` and the eases slow almost to a stop at each key (each blend starts and ends at rest) |
| `enter_blend` | 0 to 10 s (default 1) | from your plane to the first key; 0 a cut (so is a first key marked `cut`) |
| `callouts` | `on` (default), `off` | Survival's callouts and subtitles shown over the cinematic, or the whole HUD off (they then wait until it's over) |
| `boxes` | `hide` (default), `hers`, `keep` | the target boxes: all off, only hers, or left (section 4) |
| `hud` | `distortion widgets cheat showhud` (default), any of them in any order, or `none` | how the game's HUD is hidden: tried in order until one takes (section 4) |

The files next to it:

- `rise_camera.prev.txt`: the file as it was before the last save (one save's undo; every save writes it again).
- `rise_camera.edited.txt`: a hand edit a save would have written over. Ctrl+E reads an edited file again before it
  saves, and Ctrl+W keeps the file as it is on disk in its take, so this happens only after a failed save (the keys in
  memory are then the newer, so the file isn't read again).
- `rise_camera.take_<date>_<time>.txt`: each Ctrl+W's take, never written again.

Nothing packs these files: only a test build's sv_cine.lua writes them.

## 3. The cinematic

`CINE.play(R[, hooks])` as her hold starts (sv_tanicorn.lua's rise `R`: hull `R.o` / `R.name`, rest place
`R.x / R.y / R.z`, rig `R.rig`):

- **The path** (`CINE.path`). With `blend = smooth`, each run of keys (a `cut` key starts a new run) is put on monotone
  cubics, every column on its own (place, look point, FOV, roll unwrapped the shorter way round): Fritsch-Carlson, flat
  at both ends, the same `pchip()` as `export_tanacorn.py` bakes `RISE_CAM` into the rig, so today's keys play as today's
  camera moves (it keeps moving through 5 s and 9 s; the look point at about -24 m/s and -11 m/s there). A camera stands
  on that curve about every 0.5 s of the rise (`sample_s`), each key one of them; at most 64 cameras in all, spaced
  further apart on a long path. Today's four keys make 31 cameras. With another `blend` the cameras are the keys.
- **The cameras**: one `CameraActor` a camera (BeginDeferredActorSpawnFromClass + FinishSpawningActor, as the rise's own
  camera is spawned), at its spot, turned onto its look point with its roll (the spawn transform's quaternion,
  FRotator::Quaternion, and `K2_SetActorRotation` with the rotator: written from Lua, never read back as a rotator; its
  forward is read back as a vector and logged as `read back N deg off`), its FOV on its `CameraComponent`
  (`bConstrainAspectRatio` off).
- **The way in**: the view on camera 1 over `enter_blend` s from your plane (cubic; the outgoing view not locked, so it
  starts from your plane as it flies), in her hold.
- **The moves**, on her clock: the blend to each next camera starts once the view is within `lead_s` (0.35 s real time,
  more than one 250 ms Lua tick) of the camera it's heading to, and lasts the time left to the new camera at her rate
  (`left / rate`), so the view never stops at a camera on the way. `smooth`: linear blends between the cameras (the curve
  is in where they stand). Another blend: that function a key. A `cut` key: the view cuts to its camera at its time (to
  half a lead); the run before it ends on its last key, and the view waits there until the cut.
- **The outgoing camera locked** (`bLockOutgoing` true) on every blend between cameras. SetViewTarget takes the last
  frame's view (APlayerCameraManager GetLastFrameCameraCacheView) as a blend's start; unlocked, DoUpdateCamera runs
  UpdateViewTarget on the old view target every frame while the blend is pending, and that's still the camera before
  the last one, so a blend that cut into another would start from a camera behind: a jump back, then a glide. Locked,
  an interrupted blend really starts from the view on screen. The cameras don't move, so nothing is lost. The one blend
  left unlocked is one started in the same tick as a cut: the cut (blend 0) has made its camera the view target at once,
  but the last frame's view is still the one before the cut, so that blend starts from the cut's camera only unlocked.
- **Her clock**: `hooks.clock()` if given (seconds into the rise, nil before she plays), else her rig's own
  `GetPosition` while `R.playing`, else `(os.clock() - R.t1) * rate`. Nothing is read once `R.back` is set, her hull is
  gone (its address and name, hard rule 59) or her rig isn't live: never a call on a freed rig. The rate is
  `hooks.rate` (a number or a function), else `R.rate`, else `TANI.rise.rate`.
- the view given back (blend 0) if the game takes it (`GetViewTarget` names the camera a blend is heading to), not
  while paused;
- Survival's HUD held (`HUD.hold(true, "the rise's cinematic", { callouts = <the file's callouts> })`), the game's
  hidden and the target boxes off (section 4).

In director mode `CINE.play` makes no camera: it only keeps the rise's frame and clock, for Ctrl+E (-> false,
"director"). The frame is let go at the next tick once the rise is over or her hull is gone.

`CINE.stop(why)`: the view back on your plane over 1 s (cubic) with the outgoing camera locked (the camera can go while
the view leaves it), both HUDs and the boxes back, the cameras destroyed 1.5 s later. Every stop path ends there:
sv_tanicorn's `riseBack` (a second Ctrl+R, the rise's end, the hull gone, the run's end, nothing to rise), and on its own:
the rise over (`R.back`), a new run (`D` changed), a camera gone, 180 s up, and being down in co-op (the spectator then
has the view: it's left to it). The level:

- left (`CINE.leave(why)`, from sv_main.lua `runLeft` beside `SKY.restore`, where no tick of the run follows): what can
  outlive the level is put back at once (the game's HUD widgets: the flight HUD's outer is the game instance; with them
  every other route and box change whose object is still alive), the view and the cameras left to the level;
- torn down (`LEVEL_DROPS.cine`; `CINE.leave` and `CINE.stop` while `levelTorn()`): everything forgotten untouched; the
  game's HUD widgets still alive next run are put back at its first tick.

## 4. The HUD off

### Survival's HUD: `HUD.hold(on, why[, opts])` (sv_hud.lua)

Off while anything holds it, back when the last holder lets go. A holder is its `why`: holding twice is one hold and
letting go twice is nothing, so two holders can't undo each other. `opts.callouts`: the callout banner and the subtitles
(sv_subs.lua's strip) still show (the preview's `KEY n OF m`, the rise's own callout and radio): while every holder
allows that, only the rest is off (each of the canvas's other widgets at render opacity 0, its own put back after). A
hold belongs to the run it was made in: a new run drops it (`hud: <why>'s hold dropped (its run is over)`). The run's
summary is never held. Callouts and subtitles wait while it's all off and show after. sv_hud.lua takes `AHUD.bShowHUD`
false for the game's HUD off and hides all of Survival's with it, except while sv_cine's route `showhud` turned it off
(`CINE.GH.show`): the hold says what of Survival's is off then. Log: `hud: held (<why>)`, `hud: hidden (held: <whys>)`,
`hud: <why> let go`.

### The game's HUD: what was found

- The flight HUD (`WBP_HUD_Chronicle_MainFlight_000`, outer the game instance) is never in the viewport: it's drawn into
  `HUDWidgetRenderTexture` / `HUDWidgetNonGlowRenderTexture` and composited with a glow (HUD_LAYOUT.md, hard rule 18).
  `ALiveHUDBase` keeps the roots it hands to its widget-to-texture converter: `GlowWidgetPtr`, `NonGlowFrontWidgetPtr`,
  `NonGlowBackWidgetPtr`; `ALiveHUD` has `NonGlowWidget`, `HUDMessageWidget`, the canvases (`ConditionallyVisibleCanvas`,
  `AlwaysVisibleCanvas`, `WorldToScreenDrawCanvas`, `LowestPriorityCanvas`) and `OnHUDEnabled` / `OnHUDDisabled`
  delegates.
- **The game's own HUD blackout is reflected** (LiveHUD.h, LiveHUDDirationStartInfo.h): `ALiveHUD::BeginHUDDistortion(
  FLiveHUDDirationStartInfo)`, `BeginHUDDistortionLightning(float, Info)`, `BeginHUDDistortionOnlyRaderMap`,
  `BeginHUDDistortionOnlyCommunicationWindow`, undone by `EndHUDDistortion` / `EndHUDDistortionLightning` /
  `ResetHUDDistortion`. The struct has `NeedUpdateDistortion`, `MinDistortionScale`, `MaxDistortionScale`,
  `HideContainerTime`, `ShowContainerTime`, `UseHideHUD`, `BeginHideHUDTime`, `HideHUDTime` and `DistortionMask`:
  `UseHideHUD` with `HideHUDTime` is the game's own native hide (a lightning strike's blackout: sv_anomalies_dev.lua's
  strike passes `UseHideHUD = true, HideHUDTime = 3.5` and logs `HUD out 3.5 s`), and the container times are probably
  the target containers'. This is the route most likely to hide the render-texture HUD cleanly, with no frozen frame.
  (The first version of this note said no reflected function hides the HUD: wrong.)
- The game also switches its HUD natively by mode: `ELiveHUDMode` (Default, DefaultDisabled, EverythingDisabled,
  RestoreToDefault, Pause, MultiPause, Camera, Respawn, IGC, KillCamera, IngameHangar); its cinematics do it
  (`FLiveCinematicsPlayContext.bSkipChangeHUDModeDefault`, `FLiveCinematicsSequenceDataTable.bDisableHUDRestore`). The
  modes' reflected way in is `ULiveCheatManager::ChangeHUDType(ELiveHUDMode)` and `SetShowHUDAll(bool)`, Exec cheats: a
  shipping game makes no cheat manager (and their bodies may be compiled out). `LivePlayerController`,
  `LivePlayerCameraManager`, `LiveCinematicsWorldSubsystem` and `LiveViewportOverlaySubsystem` have nothing for it; no
  event node does it (node_catalog.tsv's HUD nodes are the tutorial window, the radar noise and the wingman displays).
- The pause menu hides it (hard rule 60).
- **The target boxes are not widgets**: they're 3D billboard actors, `ALiveTargetContainerActor` (BP
  `ChronicleTargetContainerActorBP_C`: MaterialBillboardComponents and TextRenderComponents), pooled by
  `ULiveTargetContainerManager` (`ALiveHUD.TargetContainerManager`: `TargetContainers`, TMap<AActor*,
  ALiveTargetContainerActor*>, a target to its box; `ContainerPool`, TArray, the spares; MINIMAP_MARKERS.md 1d). THE
  TANACORN's hull is ported with `tgt=True` (build_survival_world.py: `bShowHUDBox` and a TGT mark), so her box, name and
  TGT label would draw over her through the whole cinematic with every HUD widget hidden. No widget route reaches them.

### The routes (`hud = ...` in the file, tried in order until one takes)

| route | what | put back | the risk |
| --- | --- | --- | --- |
| `distortion` (first) | the HUD actor's `BeginHUDDistortion` with `UseHideHUD = true`, `BeginHideHUDTime = 0`, `HideHUDTime` = the time it's wanted + 2 s (the cinematic: her hold + the way in + the keys' span at her rate + the way out; the preview: 20 s), no distortion (scales 0, `NeedUpdateDistortion` false, mask 0), container times 0; renewed for 5 + 2 s while still held near its end, and at each Ctrl+V | `EndHUDDistortion`, else `ResetHUDDistortion` | untested: whether `HideHUDTime` is a duration, whether a second call renews it, whether it hides the whole HUD (it "takes" whenever the call doesn't fail: nothing to read back) |
| `widgets` | the HUD actor's root widgets above and the live flight HUD and message layer roots (`WBP_HUD_Chronicle_MainFlight_000_C`, `WBP_HUD_SubWidgets_Message_000_C`; never a blueprint's template copy, never Survival's own) `SetVisibility(Hidden)`, read back; hidden again each tick if the game shows them | each one's own visibility, only where it's still Hidden | the converter may keep the texture's last frame instead of drawing it empty |
| `cheat` | `ChangeHUDType(EverythingDisabled)` on the controller's `CheatManager`, only when one exists (never made here) | `ChangeHUDType(RestoreToDefault)` | none expected in a shipping game |
| `showhud` | the HUD actor's `bShowHUD` false (AHUD's canvas drawing); Survival's HUD isn't hidden with it (above) | its value, only if still false | may only stop the texture updating (a frozen HUD) |

### The target boxes (`boxes = ...`)

- `hide` (default): her own box off (her hull's `bShowHUDBox` false: ALiveAIGameObject's, reflected, as sv_alicorn.lua
  and sv_anomalies.lua write it), and every live box `SetActorHiddenInGame(true)`: the manager's `TargetContainers` and
  `ContainerPool` (only when the manager can't be read, the boxes found by class, once), each box's own `bHidden` kept
  first. While held, a box the game shows again is hidden again, and so is a new target's (a spare taken). Put back
  after: each box still ours and hidden is shown, except one that's a spare again (the pool keeps its spares hidden),
  and her `bShowHUDBox` back on only if it's still false.
- `hers`: only her `bShowHUDBox`.
- `keep`: neither.

Logged: `cine: the game's HUD hidden by <route> (<what took>)[; before it <route>: <why not>]`, or
`cine: the game's HUD NOT hidden (...)`; `cine: the game showed its <widget> again (visibility N): hidden again` (the
first time); `cine: the HUD's blackout renewed for N s (...)` (the first time); `cine: her target box off (...)`;
`cine: the target boxes: N hidden of M (the HUD's TargetContainerManager | found by class ...; S spares, H of them hidden
already)`; `cine: the game showed a target box again (...)`; `cine: the game's HUD back (<why>; N of M widgets back,
the blackout over (EndHUDDistortion, renewed N times), her box back, N of M target boxes back, ...; hidden again N times
while held)`.

## 5. The hook in sv_tanicorn.lua (the main session adds it)

```lua
-- 1. the "tanicorn rise" tick, where the rig is found (replacing `if C.cinematic then riseCine(R) end`):
            R.state, R.t0 = "hold", now
            riseLook(R, 0)
            local dir = CINE and CINE.director and CINE.director()
            R.rate = dir and dir.speed or C.rate                  -- (director mode: slower, no cinematic: sv_cine.lua)
            if dir then pcall(CINE.play, R, { rate = R.rate })    -- (only her frame and clock kept, for Ctrl+E)
            elseif C.cinematic then riseCine(R) end

-- 2. riseCine, right after `R.cine = true` (before its own camera's spawn; that SOC_Cam camera stays as the fallback):
    if CINE and CINE.play then                            -- (sv_cine.lua: the keyed cameras, both HUDs and the boxes off)
        local okP, okC, whyC = pcall(CINE.play, R, { rate = R.rate or C.rate })
        if okP and okC then
            log(string.format("tanicorn: rise cinematic: sv_cine.lua's keyed cameras; your plane invincible, the autopilot "
                .. "round (%.0f, %.0f) at %.0f m: %s", me and me.X or 0, me and me.Y or 0, alt,
                okD and tostring(rD) or ("error " .. tostring(rD))))
            return
        end
        log("tanicorn: rise cinematic: sv_cine.lua's cameras not made (" .. tostring(okP and whyC or ("error " .. tostring(okC)))
            .. "): the rig's SOC_Cam camera")
    end

-- 3. riseBack, right after `R.back = true` (before its own view call: UE then finds the blend to your plane going and
--    keeps CINE.stop's, the outgoing camera locked):
    if CINE and CINE.stop then pcall(CINE.stop, why) end  -- (sv_cine.lua: its cameras, the view, both HUDs, the boxes)

-- 4. her rate (the director's): `R.rig:SetPlayRate(R.rate or C.rate)` at "playing at rate" (and its log line),
--    riseHere's clock fallback `* (R.rate or TANI.rise.rate)`, and the end's `C.length_s / math.max(0.05, R.rate or C.rate)`.
```

No `hooks.clock` is needed: without it CINE reads her clock as `riseHere` does (`R.playing`, then `R.rig:GetPosition()`,
else `(os.clock() - R.t1) * rate`), behind its own liveness checks. With riseCine's early return `R.cam` stays nil, so
sv_tanicorn's own view keep (`if R.cine and R.cam`) never fights CINE's; riseBack still ends the autopilot, the
invincibility and the attack limits.

sv_main.lua `runLeft` already calls `CINE.leave(why)` beside `SKY.restore` (nil in a release: no sv_cine there).

## 6. Test keys

| Key | What |
| --- | --- |
| Ctrl+D | the rise's director mode on / off: markers at the camera keys' spots, the next Ctrl+R slow (0.35x) and without the cinematic; in a preview, the preview over |
| Ctrl+E | a camera key from your view (place, direction, roll, FOV) at her time in the rise, saved to config\rise_camera.txt; in a preview, the preview over |
| Ctrl+V | the camera keys previewed, one a press; after the last, back on your plane (and so after 20 s with no press, your plane changed or gone, or you down) |
| Ctrl+W | a new take: the keys kept in rise_camera.take_<date>_<time>.txt, today's camera back |

(Free on 2026-11-12 against tools/README.md's Ctrl keys, sv_main.lua's test keys and Ctrl+L / K / N, taken that night.)

## 7. What the game must still answer

1. **Which HUD route hides the game's HUD on screen.** `distortion` first: does `BeginHUDDistortion` with `UseHideHUD`
   hide the whole HUD (no frozen frame), is `HideHUDTime` a duration from `BeginHideHUDTime` (the cinematic asks
   20.5 s), does a second call renew it (`the HUD's blackout renewed`), and does `EndHUDDistortion` bring it back at once?
   Do the container times (0 here) hide or show the target boxes? If the HUD stays or freezes through a cinematic or a
   Ctrl+V, set `hud = widgets cheat showhud` and try again (no restart: the next Ctrl+R / Ctrl+V reads the file). The log
   names the route and what it hid.
2. **The target boxes** (`boxes = hide`): are her box and the other targets' boxes gone on screen, and back after? Does
   the game fight the hidden flag (`N shown again by the game` in `cine: the game's HUD back`)? A box shown again at the
   put-back for a target the game wouldn't show now (off screen, out of range): does the game hide it again itself?
3. **The smooth path**: does it play without a stop or a jerk at each camera (`held at a camera 0 times` in
   `cine: cinematic over`), FOV and roll and all, and is the way in over 1 s from your plane smooth? Does the game take
   the view back (`the view taken back by the game N times`)?
4. **Ctrl+E's view**: does the camera manager's actor follow the view and carry its bank (Ctrl+E's line says `the camera
   manager's forward` and a roll; otherwise `GetForwardVector(GetCameraRotation())`, or `roll NOT read: recorded level`)?
   Does Ctrl+V on a recorded key, banked or not, show the shot you recorded?
5. Each camera's `read back N deg off` near 0 (the rotation written from Lua took).
6. The far flash readable at a kilometre at 3x (`marker_scale`), and the rig's clock right at 0.35x.
7. Callouts with `callouts = on`, in the preview and the cinematic: the banner and the subtitles shown while the rest of
   Survival's HUD is at opacity 0.
8. The preview's ways out: Ctrl+D and Ctrl+E at once, 20 s with no press, a respawn; your plane flown meanwhile.
