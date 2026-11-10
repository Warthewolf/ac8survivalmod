# THE TANICORN (tools/tanicorn)

The user's Anomaly boss, built from Survival's own assets: research, decisions and milestones in docs/re/TANICORN.md.
The Tanager stand-in is Sea Power's Iowa (the user, 2026-11-09: "my install only"): its inputs and every output live in
`build/tanicorn` (git-ignored), and its container ships with TANI=1 dev builds only.

`sh tools/tanicorn/build.sh` (UE 5.4, Blender 3.3, E:/AC8LiveProject):
0. `bl_import.py` (once, by hand): the Alicorn's GLBs (ACE8 Aircraft Builder `dev mesh`) and the Iowa OBJ into
   `build/tanicorn/src.blend` (turrets split into housing and guns, each with its pivot).
1. `prepare_part.py`: each part in `build/tanicorn/parts.json` -> skinned glTF (Body > turret_yaw > turret_pitch,
   identity rotations), its wreck, Alicorn-grey textures, `<part>.json` (bones, muzzle sockets, slots).
2. `ue_import.py` in the template project: textures, instances on AC8's gear material (stubs at AC8's paths, never
   packed), the rigged mesh and wreck.
3. `spec.py` -> `tani.spec.json`; 4. the `TaniBuild` commandlet (tools/laser7/cpp/SurvivalFx, the shared editor module):
   muzzle sockets, stubs for stock shots, the blueprints on AC8's native classes.
5. Cook (VERSIONED, hard rule 42); 6. `retoc to-zen` of `/Game/Mods/SurvivalMode/Tanicorn` only; 7. `pad.py`.

THE TANACORN's whole ship (docs/design/INVINCIBLE_FLEET.md WP0): `model_tanacorn.py` (Blender 3.3) takes the
Leviathan design (`art/tanicorn/design/Leviathan_animated.blend`: Sea Power's Iowa fused with the Alicorn) and adds the
parts the settled armament needs that neither ship has: 4 laser turrets (house + emitter, socket SOC_Gun_01), 8 deck
VLS blocks behind turret C and 8 side VLS blocks on the bow's flanks (SOC_Vls_01..08 along each cell's launch line),
plus a SOCKET_Mount_* empty on the hull for every part (`tanacorn_hull_sockets.json`, UE cm):

    blender -b art/tanicorn/design/Leviathan_animated.blend -P tools/tanicorn/model_tanacorn.py -- build/tanicorn/model [render] [anim]

It also removes the Iowa's crew figures, builds the laser as a beam director (the user's photos), gives every VLS lid a
hinge, bends each side VLS block onto the hull's flare (its face 2 cm off the skin), makes the hull's UV map again
from scratch (`hull_uv.py`: the sides in the Alicorn's own side skin taken from the source mesh ALC_HULL, rail, slots
and draft marks straight along the hull; the decks on the Alicorn's own top-down deck layout where it has flat deck
and plain plating elsewhere; under the water one continuous strip of plating a side; the rest box-mapped; the copied
map it replaces was 4,245 islands of saw teeth) and checks every part's topology (tanacorn_model_check.json: all must pass). Status and the next steps:
docs/design/INVINCIBLE_FLEET.md WP0 ("WP0 handover").
It writes `Tanacorn_model.blend` (the design file is never changed) and, with `render`, previews (Cycles on the CPU;
TANA_SAMPLES, TANA_SHOTS=02_aft_vls,... pick the quality and the views). Every VLS hatch is keyed in the .blend's
1-360 sequence (open at 150-165, shut at 290-305: 0.5 s each at 30 fps). With `anim` (alone or after `render`) it renders
the hatches opening, held and shutting from 5 views into renders/anim/*.mp4 (ffmpeg; TANA_ANIM_SAMPLES,
TANA_ANIM_VIEWS=aft_deck,aft_deck_close,bow_L,bow_L_close,bow_R). The four laser turrets are keyed too (slewing out
at 60-100, back at 200-240). **The film** of every moving part, the design's own deploy sequence included (the bow's
doors, the railcannon, the turrets training and their guns lifting), is `film_tanacorn.py`, run on the saved model:

    blender -b build/tanicorn/model/Tanacorn_model.blend -P tools/tanicorn/film_tanacorn.py -- build/tanicorn/film [shot ...]

It renders an orbit right round the ship over the whole sequence and five close-ups (aft_vls, side_vls, bow, laser,
aft_turret) to mp4, the sun going round with the camera (TANA_FILM_SAMPLES, TANA_FILM_RES, TANA_FILM_STEP; ~5-8 s a
frame on 4 cores, about an hour for all of it). The previews the user saw are in
`art/tanicorn/renders/model/`. Next: each part through prepare_part.py's route (a recipe each in build.sh), the hull
as a static mesh with these sockets.

In game (test builds): Scripts/sv_tanicorn.lua, Ctrl+T in a run.
