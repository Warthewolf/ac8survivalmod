# THE TANICORN (tools/tanicorn)

The user's Anomaly boss, built from Survival's own assets: research, decisions and milestones in docs/re/TANICORN.md.
The Tanager stand-in is Sea Power's Iowa (the user, 2026-11-09: "my install only"): its inputs and every output live in
`build/tanicorn` (git-ignored), and its container ships with TANI=1 dev builds only.

`sh tools/tanicorn/build.sh` (UE 5.4, Blender 3.3, E:/AC8LiveProject; `BLENDER=` if Blender isn't in its default
folder; `TANI_PARTS=T5,HULL` for some parts only; `TANI_STOP=export` to stop before UE):
1. `model_tanacorn.py`: the Leviathan design (`art/tanicorn/design`, in the repo) -> `build/tanicorn/model/
   Tanacorn_model.blend`, made again only when the design or its scripts changed (~2 min).
2. `export_tanacorn.py`: every part type in the frame of its hull socket -> `build/tanicorn/src_<part>` and
   `parts.json`: the four gun mounts T16, T5, CIWS, LASER (skinned glTF, Body > turret_yaw > turret_pitch, identity
   rotations, muzzle sockets SOC_Gun_NN), the VLS blocks VLSD and VLSS_L1..R4 (Body > Hatch_01..08, the animation
   Open, launch sockets SOC_Vls_NN), the Alicorn's deploying parts from the design's own rigs and keys (RAILCANNON,
   kind railcannon: Body (its bay section) > railcannon_pitch > barrel_n / barrel_p, the barrel halves being the bow's
   doors; RAILGUN_L / _R, kind railgun: Body > lift > BN_turret_yaw > BN_turret_pitch and Body > Hatch_n / Hatch_p;
   each SOC_Gun_01 and the animation Deploy, the design's sequence from the first key until every bone is out: 3.333 s
   / 4.0 s; rest = stowed), the rise rig RIG (2026-11-11, kind rig: none of the ship's geometry; BN_RiseRoot >
   BN_RiseHull / BN_RiseCam, one hidden triangle, sockets SOC_Hull and SOC_Cam, the animation Rise from RISE_HULL /
   RISE_CAM: 20 s, its end the rest pose; the hull blueprint hangs HullMesh on its SOC_Hull: docs/design/
   INVINCIBLE_FLEET_RISE_FORD.md 2.3), the hull HULL (static, its 36 Mount_* sockets; Mount_CORE has no part yet), each part's
   wreck, textures, `Tani_<part>.json` (kind, bones, sockets in UE cm with UE rotators, slots, anim). `check_export.py`
   reads every glTF back into Blender and compares it with its json (triangles, slots, bones, each lid's swing, each
   deploying part played to its end: every bone's turn and place, its meshes' box): `CHECK ALL OK`.
3. `ue_import.py` in the template project: textures, instances on AC8's gear material (stubs at AC8's paths, never
   packed), the rigged meshes, the lids' AnimSequences (AS_SV_Tani_<part>_Open) and the deploying parts'
   (AS_SV_Tani_<part>_Deploy), the hull's static mesh, the wrecks.
   Its log ends with its warnings counted, then `done`.
4. `spec.py` -> `tani.spec.json`; 5. the `TaniBuild` commandlet (tools/laser7/cpp/SurvivalFx, the shared editor
   module): the skeletons' sockets, the hull's sockets (`mesh_sockets`), stubs for stock shots, the gun mounts'
   blueprints on AC8's native classes (BP_SV_Tani_T5 / _T16 / _CIWS / _LASER: the 5-inch's fire control and the stock
   AA shell until WP1 gives each its own weapon), and BP_SV_Tani_HULL with every part drawn on its sockets at rest
   (the railcannon and the sub-railguns stowed; no blueprint or fire control of their own yet). (2026-11-11, WP2 step 2)
   BP_SV_Tani_HULLLIVE: the same hull with its 16 gun-mount sockets (T16, T5, CIWS, LASER: spec.py LIVE) carrying
   LiveChildActorComponents whose child is that mount's blueprint (`child actor Part_<socket>: <class> (template ...)` in
   tanibuild.log, one a live part: build.sh counts them); the VLS blocks, railcannon and sub-railguns drawn as on HULL. Its
   world data (each part a child desc importing the mount's blueprint) is in TANI=1 builds only (Ctrl+L in a run).
   (2026-11-12, WP1's VLS route: docs/re/TANICORN.md "VLS") the VLS blocks' blueprints (`vls_mount`): BP_SV_Tani_VLSD (the
   deck block, one blueprint for its 8 sockets) and BP_SV_Tani_VLSS_L1..L4 / R1..R4 (each side block its own mesh), on the
   gun mounts' layout but their mesh a SkeletalMeshComponent `TurretMesh` (the Mk 41's component name: its cells
   SOC_Vls_01..08, AS_SV_Tani_<part>_Open in single-node mode held shut; Lua opens the lids when a block fires), a
   LauncherCommon arm with the VLS prefix and the Mk 41's missile (a stub for BP_wp_vls_a0 on LiveVLSMissile; in game the
   row SV_FCS_TaniVLS's arm replaces it), the mounts' wreck. HULLLIVE then has all 16 VLS sockets live too: 32
   `child actor Part_...` lines (Part_VLSD_1..8, Part_VLSS_L1..R4), only the railcannon and sub-railguns drawn. The cook
   checks each block's BP_SV_Tani_<part> with its mesh, skeleton, wreck and Open. In a run: Ctrl+K (the VLSD and VLSS_L1
   test blocks 3 km ahead), Ctrl+L (all of them live on the hull).
6. Cook (VERSIONED, hard rule 42); 7. `retoc to-zen` of `/Game/Mods/SurvivalMode/Tanicorn` only; 8. `pad.py`.
The first 5-inch mount (milestone 0) came through `prepare_part.py` from `build/tanicorn/src.blend` (`bl_import.py`);
the export gives the same T5 (the same pivot and muzzles) and build.sh no longer calls them. Logs to read after a
run, all in `build/tanicorn`: `export_check.log`, `ue_import.log` (each skeleton's `bones within ... cm of the
export`, `AS_SV_..._Open: 0.5 s`, `AS_SV_Tani_RAILCANNON_Deploy: 3.333 s`, `SM_SV_Tani_HULL: ... triangles`),
`tanibuild.log` (`SM_SV_Tani_HULL: 36 sockets`, `done (0 errors)`), `cook.log`.

THE TANACORN's whole ship (docs/design/INVINCIBLE_FLEET.md WP0): `model_tanacorn.py` (Blender 3.3) takes the
Leviathan design (`art/tanicorn/design/Leviathan_animated.blend`: Sea Power's Iowa fused with the Alicorn) and adds the
parts the settled armament needs that neither ship has: 4 laser turrets (house + emitter, socket SOC_Gun_01), 8 deck
VLS blocks behind turret C and 8 side VLS blocks on the bow's flanks (SOC_Vls_01..08 along each cell's launch line),
plus a SOCKET_Mount_* empty on the hull for every part (`tanacorn_hull_sockets.json`, UE cm):

    blender -b art/tanicorn/design/Leviathan_animated.blend -P tools/tanicorn/model_tanacorn.py -- build/tanicorn/model [render] [anim]

The design files were straightened with `straighten.py` (2026-11-10: everything from the Iowa lay 0.44-0.55 deg askew
to the Alicorn's parts, and sheared; it puts the hull's plane of mirror symmetry on y = 0 and the mounts with it,
takes the shear out, keeps the deck round the bow's bay on the bay's outline (fittings there moved whole), makes the
pods' fairings again from the un-faired pods so both are mirror images seated in the hull's sides, closes the hole
the bay's cut left in the starboard bow and the forward barbette's open front; `blender -b <file> -P tools/tanicorn/straighten.py -- save` on the ORIGINAL
files, and model_tanacorn.py runs it on what it loads too: a no-op on a straight file).
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
frame on 4 cores, about an hour for all of it). **The surfacing shot** (the user's reference: a submarine breaching
against a sunset) is `surface_tanacorn.py`, run the same way: her bow comes up 35 deg nose-up until it stands 120 m
over the sea with a third of her out, comes down while the rest of her surfaces, and slams; spray from baked particle
systems (fine drops, not big blobs), foam patches, a low sun behind her; 13.5 s at 24 fps, ~8 s a frame at 960x540.
**Checking her over** (after any change to the design files or straighten.py): `audit_tanacorn.py` on the saved
model measures her from every side (rays 0.25 m apart from six sides: port against starboard, faces seen from behind;
then 36 directions round her for the inside of closed parts on show; `audit.json` and a map a view), and
`survey_tanacorn.py` photographs her area by area (37 pictures: five stretches from above and from each side, both
ends, the joints as mirrored port / starboard pairs, the underside with the sea taken away; anything seen through shows
light blue), `label_survey.py <dir>` (plain Python, PIL) writing each picture's name along its foot:

    blender -b build/tanicorn/model/Tanacorn_model.blend -P tools/tanicorn/audit_tanacorn.py -- build/tanicorn/audit
    blender -b build/tanicorn/model/Tanacorn_model.blend -P tools/tanicorn/survey_tanacorn.py -- build/tanicorn/survey

The survey the user was sent (2026-11-10, after the audit's fixes) is in `art/tanicorn/renders/survey/`.
The clips the user was sent are in `art/tanicorn/video/` (rendered BEFORE the audit: they still show the faults). The previews the user saw are in
`art/tanicorn/renders/model/`. Next: build.sh on the user's machine (above), then WP1's mount tests.

In game (test builds): Scripts/sv_tanicorn.lua, Ctrl+T in a run (Ctrl+U the other gun mounts, Ctrl+K the VLS blocks,
Ctrl+Y / Ctrl+L the hull drawn / live, Ctrl+R the rise; tools/README.md's key table).
