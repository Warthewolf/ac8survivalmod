"""ue_check.py : run inside UE 5.4 after ue_import.py: where A_X02S_Valka_Sweep puts the wings (tip sockets and
every VariableWing bone, component space) unswept (0 s) and swept (1 s), so a bad sweep shows before a cook."""
import os
import unreal

SRC = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'build', 'x02s'))
seq = unreal.load_asset('/Game/Mods/SurvivalMode/Valka/Model/A_X02S_Valka_Sweep')
opt = unreal.AnimPoseEvaluationOptions()
out = []
for t in (0.0, 0.5, 1.0):
    pose = unreal.AnimPoseExtensions.get_anim_pose_at_time(seq, t, opt)
    for b in ('vapor01', 'vapor02', 'VariableWing_01', 'VariableWing_02', 'VariableWing_19', 'VariableWing_20',
              'VariableWing_11', 'VariableWing_12', 'burner_01'):
        p = unreal.AnimPoseExtensions.get_bone_pose(pose, b, unreal.AnimPoseSpaces.WORLD).translation
        out.append(f't {t:.1f} {b:16s} x {p.x:8.1f} y {p.y:8.1f} z {p.z:7.1f}')
open(os.path.join(SRC, 'ue_check.log'), 'w').write('\n'.join(out) + '\n')
