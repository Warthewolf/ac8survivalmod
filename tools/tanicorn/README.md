# THE TANICORN (tools/tanicorn)

The user's Anomaly boss, built from Survival's own assets: research, decisions and milestones in docs/re/TANICORN.md.
The Tanager stand-in is Sea Power's Iowa (the user, 2026-11-09: "my install only"): its inputs and every output live in
`build/tanicorn` (git-ignored), and its container ships with TANI=1 dev builds only.

`sh tools/tanicorn/build.sh` (UE 5.4 = `$UE`, Blender 3.3 = `$BLENDER`, `$AC8_LIVE_PROJECT`):
0. `bl_import.py` (once, by hand): the Alicorn's GLBs (ACE8 Aircraft Builder `dev mesh`) and the Iowa OBJ into
   `build/tanicorn/src.blend` (turrets split into housing and guns, each with its pivot).
1. `prepare_part.py`: each part in `build/tanicorn/parts.json` -> skinned glTF (Body > turret_yaw > turret_pitch,
   identity rotations), its wreck, Alicorn-grey textures, `<part>.json` (bones, muzzle sockets, slots).
2. `ue_import.py` in the template project: textures, instances on AC8's gear material (stubs at AC8's paths, never
   packed), the rigged mesh and wreck.
3. `spec.py` -> `tani.spec.json`; 4. the `TaniBuild` commandlet (tools/laser7/cpp/SurvivalFx, the shared editor module):
   muzzle sockets, stubs for stock shots, the blueprints on AC8's native classes.
5. Cook (VERSIONED, hard rule 42); 6. `retoc to-zen` of `/Game/Mods/SurvivalMode/Tanicorn` only; 7. `pad.py`.

In game (test builds): Scripts/sv_tanicorn.lua, Ctrl+T in a run.
