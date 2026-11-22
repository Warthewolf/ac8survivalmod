# Sky, weather and VFX

Cloudly, the sky asset, lightning and the effects around them.

Moved verbatim from AGENTS.md (2026-11-14). Rule numbers are unchanged: other notes cite them as "hard rule N".

56. Cloudly draws the sky, and sets its sun light, from the level's CloudlySkyParamsAsset (Survival's: Mission 4's
    CSP_ms04_20251218b), copied every frame into the renderer's drawn copy (CloudlyRenderer .Data.SkyParamsRO, and two of
    the seven OurSkyParams) and onto the sun light (rotation, intensity, colour): writes to the renderer's copies, the
    interpolated params or the light are undone within a frame. Its custom sun API (SetCustomSunPosition /
    SetCustomMoonPosition) writes into the asset itself and stays there after the custom flags go off. The exposure (the
    post-process volumes), the level's sky light controller and the MPCs do hold. The user's sky test of 2026-11-07
    (0.74.1, Ctrl+F6: the step-3 read-back undid the copies and the light; step 2 moved the asset to -2 / -105 and gave a
    real sunset in the screenshot; a whole run of the arc on the copies showed no sun move at all and a blown-out night).
    Write the asset (sv_sky.lua v.asset) and put back every value of it: it outlives the level, and the campaign reads it.

60. A LiveLightningVolume spawned from Lua never struck the player in Survival's level: about 50 s inside one in the user's
    test of 0.74.34 (2026-11-08), nothing on the plane or the HUD. The pause menu hides the HUD, which Lua took for a strike:
    check gamePaused before reading anything as the game's own effect. Survival rolls its own strikes and calls the game's
    pieces itself (sv_anomalies_dev.lua: the HUD's BeginHUDDistortionLightning, the shake, the sounds, the damage).

61. A CHANGE of the sky asset's cloud heights (CloudStartHeightInKm, CloudLayer0-2 StartHeightInKm), rain clouds
    (CloudLayer*.RainCloud*) or rain pillar (RainPillar*) blacks the whole sky out for ~0.1 s. The user's recording of
    0.74.36 (2026-11-08) had a black sky once a second at the storm build-up's writes; the sky probe's recording of 0.74.38
    (21:40:11, Ctrl+/, each group written 3 times) dipped only at the first write of those groups and at their put-back,
    never when the same values were written again, and never for the clouds' light, density, thickness or edges (the light
    greyed the clouds' undersides). The sun, moon, stars and exposure never black it out. Ramp only the safe ones
    (buildup.sky.clouds "safe", sky.unsafe).

62. Cloudly takes another mission's cloud layout mid-level: pointing the level's Cloudly actor's CloudlyVolumeComponentsAsset
    at Mission 12's CVC_ms12_250708 brought its storm clouds in at once (grey overcast round the plane, cumulonimbus towers
    at 10 km) and pointing it back took them away, with the ~0.1 s black blink of rule 61 at each swap; ForceUpdate and
    SetResources weren't needed and blinked nothing. The user's layout-probe recording of 0.74.41 (2026-11-08 22-05-44).
    Swap it only behind a fade (sv_anomalies_dev.lua), never the sky params pointer (sv_sky.lua writes through it).

74. From Lua, a rotation's Pitch didn't take on our own spawned components or cameras, Yaw and Roll did: VALKA's portal
    (K2_SetWorldRotation, Pitch -89.9) lay flat, and every autotest picture (a CameraActor, Pitch set in its spawn
    transform and by K2_SetActorRotation) came out level (2026-11-22, the valka runs of 13:12-13:46). Stand a piece up
    with Roll and turn it with Yaw (sv_anomalies_valka.lua portalRot: { Pitch 0, Yaw yaw + 90, Roll tilt }); a Roll of -90
    turns a mesh's +Z towards the yaw and its +Y up, -5 tips its +Z up and 5 degrees towards the yaw (the runs of 14:08 and
    14:17: +90 put the arcs' top underneath, +5 showed the disk's underside). Keep cameras level with what they show.
