# THE TANACORN's rise cinematic and its director

The user, 2026-11-11: "if there's a way for you to make a directors thing, maybe so i can visualise where I want to put
the cinematic camera, also look into turning the HUD off during the cinematic too".

Code: `Scripts/sv_cine.lua` (test builds only: the whole part is one test-only block, so a release or tester zip has only
its header), `Scripts/sv_hud.lua` `HUD.hold` (ships, does nothing until something holds it). Test:
`sh tools/checks/cine_test.sh`. The rise itself is `Scripts/sv_tanicorn.lua` (`TANI.rise`, Ctrl+R; section 5 has the hook).

## 1. How to place the cameras

1. In a Survival run (TANI=1 build), **Ctrl+Y**: THE TANACORN's hull 5 km ahead of you, broadside.
2. **Ctrl+D**: director mode on (callout `DIRECTOR MODE ON`). Every 2 s a bright flash marks where each camera key's
   camera stands (AC8's Mission 23 far flash, the orbital rod's, at 3x). The log has a line a key: where it stands, what it
   looks at, its FOV, how far it is from you.
3. **Ctrl+R**: she rises where she is, at 0.35x speed (`director_speed`), with no cinematic: you keep flying.
4. Fly round her. At each moment you want a camera, line up the shot (the view you see is what the camera will see) and
   press **Ctrl+E**: a camera key at her time in the rise, from your view (callout `CAMERA KEY n AT t S`). It's saved
   at once. A key within 0.25 s of another replaces it, so pressing again at the same moment fixes a bad one.
   With no rise playing, Ctrl+E records at the last key recorded + 1 s (the log says so).
5. **Ctrl+V** to check them: each press puts your view on the next key's camera (callout `KEY n OF m AT t S`, the HUD
   off). After the last, Ctrl+V once more gives you your plane back. Your plane flies on while you look, so preview
   while flying straight and high.
6. **Ctrl+D** again: director mode off.
7. **Ctrl+R** (Ctrl+R twice if one is still up): the rise at full speed with the cinematic: the view cuts to key 1's
   camera, then glides to each next key, arriving at its time; both HUDs off until it's over.
8. Not happy? Edit the file (below), or **Ctrl+W** for a new take: your keys are kept in `rise_camera.prev.txt` and
   today's camera comes back.

Ctrl+D, E, V and W refuse outside a run and on a co-op joiner. UE4SS doesn't take a key from the game, so the letter
reaches the game too (a tap of D, E or W on the flight controls).

## 2. The file: `config\rise_camera.txt`

In the mod's folder (`...\Mods\AC8SurvivalMode\config\`, next to `survival.ini`). Made with today's camera the first time a
test build starts without one; read again at every Ctrl+R, Ctrl+D and the first Ctrl+V, so an edit counts without a
restart. Every save keeps the file before as `rise_camera.prev.txt`.

```
director_speed = 0.35
blend = cubic
hud = widgets cheat showhud

;  t      at_f     at_s     at_u     look_f   look_s   look_u   fov
0        700      -650     12       300      0        40       55
5        680      -660     14       200      0        70       55
9        640      -700     16       80       0        15       55
15       600      -720     18       40       0        10       55
```

One key a line, 8 numbers (spaces or commas):

| column | meaning |
| --- | --- |
| `t` | seconds into the rise: 0 her bow still under, out at 0.8, standing 120 m up at 5, the slam at 9, at rest at 15 |
| `at_f at_s at_u` | where the camera stands, metres from her rest midships at the waterline: forward (+ to her bow), starboard (+ her right side, - her left / port side), up |
| `look_f look_s look_u` | the point it looks at, the same way |
| `fov` | its field of view in degrees (55: today's) |

Her rest frame is the hull actor's place and forward. The rise moves her about that place, so a key's spot is the same
place in the world for the whole rise. The four keys above are today's camera (the rig's `SOC_Cam`,
`tools/tanicorn/export_tanacorn.py` `RISE_CAM`: UE's x / y / z there are forward / starboard / up here), FOV 55.

Settings: `director_speed` (0.05 to 4: the rise's speed in director mode), `blend` (`linear`, `cubic`, `easein`,
`easeout`, `easeinout`: UE's EViewTargetBlendFunction; ease exponent 2), `hud` (the game's HUD routes, section 4, tried in
order until one takes; `none` leaves it). A bad line is skipped and named in the log (`cine: config\rise_camera.txt line N
skipped: ...`); a file with no good key gives today's camera (and is left as it is).

Nothing packs this file: a release never has sv_cine.lua, so it never writes one.

## 3. The cinematic

`CINE.play(R[, hooks])` at the rise's start (sv_tanicorn.lua's rise `R`: hull `R.o`, rest place `R.x / R.y / R.z`):

- one `CameraActor` a key (BeginDeferredActorSpawnFromClass + FinishSpawningActor, as the rise's own camera is spawned),
  at the key's spot, turned onto its look point (the spawn transform's quaternion and `K2_SetActorRotation` with the
  rotator: written from Lua, never read back as a rotator; its forward is read back as a vector and logged as `read back
  N deg off`), its FOV on its `CameraComponent` (`bConstrainAspectRatio` off);
- the view on key 1 at once (`SetViewTargetWithBlend`, blend 0);
- at each key's time a blend to the next, lasting the time left to that key at her rate (`left / rate`): on her clock,
  which is the rig's own `GetPosition` (or `hooks.clock()`; the clock since she started playing if neither reads). Lua
  ticks 4 times a second; UE blends every frame. A blend started while another runs starts from the last frame's view
  (APlayerCameraManager::SetViewTarget), so a late tick costs at most 250 ms at a key, never a jump;
- the view given back (blend 0) if the game takes it (`GetViewTarget` names the camera a blend is heading to), not while
  paused;
- Survival's HUD held (`HUD.hold(true, "the rise's cinematic")`) and the game's hidden (section 4).

`CINE.stop(why)`: the view back on your plane over 1 s with the outgoing camera locked (bLockOutgoing: the camera can
go while the view leaves it), both HUDs back, the cameras destroyed 1.5 s later. Every stop path ends there:
sv_tanicorn's `riseBack` (a second Ctrl+R, the rise's end, the hull gone, the run's end, nothing to rise), and on its own:
the rise over (`R.back`), a new run (`D` changed), a key's camera gone, 180 s up. The level torn down
(`LEVEL_DROPS.cine`): everything forgotten untouched; the game's HUD widgets still alive next run are put back then.

## 4. The HUD off

### Survival's HUD: `HUD.hold(on, why[, opts])` (sv_hud.lua)

Off while anything holds it, back when the last holder lets go. A holder is its `why`: holding twice is one hold and
letting go twice is nothing, so two holders can't undo each other. `opts.callouts`: the callout banner still shows (the
preview's `KEY n OF m`): while every holder allows that, only the rest is off (each of the canvas's other widgets at
render opacity 0, its own put back after). A hold belongs to the run it was made in: a new run drops it
(`hud: <why>'s hold dropped (its run is over)`). The run's summary is never held. Callouts wait while it's all off and
show after. Log: `hud: held (<why>)`, `hud: hidden (held: <whys>)`, `hud: <why> let go`.

### The game's HUD: what was found

- The flight HUD (`WBP_HUD_Chronicle_MainFlight_000`, outer the game instance) is never in the viewport: it's drawn into
  `HUDWidgetRenderTexture` / `HUDWidgetNonGlowRenderTexture` and composited with a glow (HUD_LAYOUT.md, hard rule 18).
  `ALiveHUDBase` keeps the roots it hands to its widget-to-texture converter: `GlowWidgetPtr`, `NonGlowFrontWidgetPtr`,
  `NonGlowBackWidgetPtr`; `ALiveHUD` has `NonGlowWidget`, `HUDMessageWidget`, the canvases (`ConditionallyVisibleCanvas`,
  `AlwaysVisibleCanvas`, `WorldToScreenDrawCanvas`, `LowestPriorityCanvas`) and `OnHUDEnabled` / `OnHUDDisabled`
  delegates, but no reflected function to hide it (`SetShouldHideHUDDiration` is the distortion's).
- The game switches its HUD natively by mode: `ELiveHUDMode` (Default, DefaultDisabled, EverythingDisabled,
  RestoreToDefault, Pause, MultiPause, Camera, Respawn, IGC, KillCamera, IngameHangar); its cinematics do it
  (`FLiveCinematicsPlayContext.bSkipChangeHUDModeDefault`, `FLiveCinematicsSequenceDataTable.bDisableHUDRestore`). The only
  reflected way in is `ULiveCheatManager::ChangeHUDType(ELiveHUDMode)` and `SetShowHUDAll(bool)`, Exec cheats: a shipping
  game makes no cheat manager (and its bodies may be compiled out). `LivePlayerController`, `LivePlayerCameraManager`,
  `LiveCinematicsWorldSubsystem` and `LiveViewportOverlaySubsystem` have nothing for it; no event node does it
  (node_catalog.tsv's HUD nodes are the tutorial window, the radar noise and the wingman displays).
- The pause menu hides it (hard rule 60), and sv_hud.lua already treats `AHUD.bShowHUD` false as "game HUD off".

### The routes (`hud = ...` in the file, tried in order until one takes)

| route | what | put back | the risk |
| --- | --- | --- | --- |
| `widgets` (first) | the HUD actor's root widgets above and the live flight HUD and message layer roots (`WBP_HUD_Chronicle_MainFlight_000_C`, `WBP_HUD_SubWidgets_Message_000_C`; never a blueprint's template copy, never Survival's own) `SetVisibility(Hidden)`, read back; hidden again each tick if the game shows them | each one's own visibility, only where it's still Hidden | the converter may keep the texture's last frame instead of drawing it empty |
| `cheat` | `ChangeHUDType(EverythingDisabled)` on the controller's `CheatManager`, only when one exists (never made here) | `ChangeHUDType(RestoreToDefault)` | none expected in a shipping game |
| `showhud` | the HUD actor's `bShowHUD` false (AHUD's canvas drawing; sv_hud hides Survival's with it) | its value, only if still false | may only stop the texture updating (a frozen HUD) |

Logged: `cine: the game's HUD hidden by <route> (<what took>)[; before it <route>: <why not>]`, or
`cine: the game's HUD NOT hidden (...)`; `cine: the game showed its <widget> again (visibility N): hidden again` (the
first time); `cine: the game's HUD back (<why>; N of M widgets back, ...; hidden again N times while held)`.

## 5. The hook in sv_tanicorn.lua (the main session adds it)

```lua
-- 1. the "tanicorn rise" tick, where the rig is found (replacing `if C.cinematic then riseCine(R) end`):
            R.state, R.t0 = "hold", now
            riseLook(R, 0)
            local dir = CINE and CINE.director and CINE.director()
            R.rate = dir and dir.speed or C.rate                  -- (director mode: slower, no cinematic: sv_cine.lua)
            if dir then CINE.play(R, { rate = R.rate })           -- (only her frame and clock kept, for Ctrl+E)
            elseif C.cinematic then riseCine(R) end

-- 2. riseCine, right after `R.cine = true` (its own SOC_Cam camera stays as the fallback):
    if CINE and CINE.play then                            -- (sv_cine.lua: the keyed cameras, both HUDs off)
        local okC, whyC = CINE.play(R, { rate = R.rate or C.rate })
        if okC then
            log(string.format("tanicorn: rise cinematic: sv_cine.lua's keyed cameras; your plane invincible, the autopilot "
                .. "round (%.0f, %.0f) at %.0f m: %s", me and me.X or 0, me and me.Y or 0, alt,
                okD and tostring(rD) or ("error " .. tostring(rD))))
            return
        end
        log("tanicorn: rise cinematic: sv_cine.lua's cameras not made (" .. tostring(whyC) .. "): the rig's SOC_Cam camera")
    end

-- 3. riseBack, right after `R.back = true` (before its own view call: that one then finds the blend to your plane going):
    if CINE and CINE.stop then CINE.stop(why) end         -- (sv_cine.lua: its cameras, the view and both HUDs back)

-- 4. her rate (the director's): `R.rig:SetPlayRate(R.rate or C.rate)` at "playing at rate", riseHere's clock fallback
--    `* (R.rate or TANI.rise.rate)`, and the end's `C.length_s / math.max(0.05, R.rate or C.rate)`.
```

CINE.play with no `hooks.clock` reads the rise's clock as `riseHere` does (`R.playing`, then `R.rig:GetPosition()`, else
`(os.clock() - R.t1) * rate`); `hooks.clock = function() return R.playing and riseHere(R) or nil end` does the same.

## 6. Test keys

| Key | What |
| --- | --- |
| Ctrl+D | the rise's director mode on / off: markers at the camera keys' spots, the next Ctrl+R slow (0.35x) and without the cinematic |
| Ctrl+E | a camera key from your view at her time in the rise, saved to config\rise_camera.txt |
| Ctrl+V | the camera keys previewed, one a press; after the last, back on your plane |
| Ctrl+W | a new take: the keys to rise_camera.prev.txt, today's camera back |

(Free on 2026-11-12 against tools/README.md's Ctrl keys, sv_main.lua's test keys and Ctrl+L / K / N, taken that night.)

## 7. What the game must still answer

1. **Which HUD route hides the game's HUD on screen.** `widgets` first: if the HUD stays (or freezes) through a
   cinematic or a Ctrl+V, set `hud = showhud` and try again (no restart: the next Ctrl+R / Ctrl+V reads the file). The
   log names the route and every widget it hid.
2. Do the blends between Lua-spawned cameras play smoothly (cubic), FOV and all, and does the game take the view back
   (`the view taken back by the game N times` in `cine: cinematic over`)?
3. Does the camera manager's actor follow the view (Ctrl+E's line says `the camera manager's forward`; otherwise
   `GetForwardVector(GetCameraRotation())`): Ctrl+V on a recorded key shows the shot you recorded?
4. Each camera's `read back N deg off` near 0 (the rotation written from Lua took).
5. The far flash readable at a kilometre at 3x (`marker_scale`), and the rig's clock right at 0.35x.
6. Callouts in the preview: the banner shown while the rest of Survival's HUD is at opacity 0.
