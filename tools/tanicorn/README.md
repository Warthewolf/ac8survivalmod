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

    blender -b art/tanicorn/design/Leviathan_animated.blend -P tools/tanicorn/model_tanacorn.py -- build/tanicorn/model [render]

It writes `Tanacorn_model.blend` (the design file is never changed) and, with `render`, previews (Cycles on the CPU;
TANA_SAMPLES, TANA_SHOTS=02_aft_vls,... pick the quality and the views). The previews the user saw are in
`art/tanicorn/renders/model/`. Next: each part through prepare_part.py's route (a recipe each in build.sh), the hull
as a static mesh with these sockets.

In game (test builds): Scripts/sv_tanicorn.lua, Ctrl+T in a run.
