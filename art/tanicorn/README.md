# THE TANICORN: model and art

The Anomaly boss: one ship fused from AC8's Alicorn and the battleship Tanager (Sea Power's USS Iowa stands in for the
Tanager). Design, research and build plan: docs/re/TANICORN.md; the build pipeline: tools/tanicorn.

- `design/Leviathan_rev4.blend`: the chosen design (Leviathan, revision 4): the Iowa at the Alicorn's 650 m, hull in the
  Alicorn's texture, upper works Alicorn grey, the Alicorn's railcannon flush in the bow in its own teal bay, the
  Alicorn's sponsons faired to the hull. Collections for the railcannon stowed and raised.
- In both design files (2026-11-10, Blender 3.3): the ship's two 16-inch turrets are `LEV_T16_FWD` / `LEV_T16_AFT` (guns
  `LEV_G16_FWD` / `LEV_G16_AFT`); the SRC collection (the Iowa's and the Alicorn's source parts, the Iowa's original three
  turrets among them) and REF Alicorn are excluded from the view layer and never exported; each file's TANACORN_README
  text says what's what.
- `design/Leviathan_animated.blend`: the same rigged: railcannon pitch and barrel split, sub-railgun hatches / lift /
  train / elevate, the 16-inch, 5-inch and CIWS mounts training and elevating (12 s, 30 fps). Blender 3.3.
- `renders/concepts/design_1..7.png`: the seven fusion concepts; `renders/leviathan/`: revision 4; `video/`: the animation.
- `ingame/src.blend`: both source ships prepared for the pipeline (tools/tanicorn/bl_import.py); `ingame/src_T5/`: the
  5-inch mount as prepared (glTF, textures, bones / sockets); `ingame/container/SurvivalMode_Tani_P`: milestone 0's cooked
  container (BP_SV_Tani_T5 and its assets), 0.74.47's.

- `renders/styles/`: the 16-inch triples' fire mode in eight styles for the user's pick (tools/tanicorn/firemode.py,
  styles_firemode.py, style_sheet.py; 2026-11-11): each style from above, ahead, firing and the side, at night.
- `renders/style9/`: style 9, the user's own spec (four-section barrels split mid-length, sliding back and angled up
  round the glowing core; the quarters blown out; the gun house's interior), with its transform step by step.
- `renders/style10/`: style 10, the default, after the user's screen recording, on the design's own turret (closed it
  looks as it always did but for the barrels; the user, 2026-11-11): barrels in top / bottom / side quarters that step
  out and slide back along a khaki rod that pushes out and lights; the rear wall and its roof strip tip aft,
  then the roof's front halves lift with the upper side panels and the lower panels slide forward: its views,
  its transform step by step and the recording's two shots as the model does them, stills and a film
  (`video/tanacorn_firemode_style10.mp4`, frame for frame with the recording; the recording itself stays out of the
  repository).

Sources: the Alicorn is AC8's (exported with ACE8 Aircraft Builder's `dev mesh`); the Iowa is Sea Power's model.
Pushed to this repository at the user's request (2026-11-10).
