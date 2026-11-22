"""preview.py : a picture of VALKA's black hole (make_portal.py's glTFs, one design) put together as Survival puts it in
game (the shadow, the photon ring and the arch facing you, the disk tipped towards you), coloured from its manifest.json
as in game: `ring` pieces (AC8's MI_TrainingRing) a see-through glow of their colour, `glow` pieces (MI_TrainingRingGlow)
bright where you see them edge-on (fresnel), the shadow flat black. For a look before the cook.

  blender -b -P tools/valka_portal/preview.py -- <design folder> <out.png> [front|close|side|high]
  (env: BH_TILT the disk's tilt, 9; BH_ROLL the camera's roll, 0; BH_GAIN the glow, 1; BH_RING=solid: `ring` pieces
  drawn solid, as MI_TrainingRing draws if its Opacity does nothing; `haze` pieces: see-through, as `glow` without fresnel)
"""
import json
import math
import os
import sys

import bpy

args = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT = args[0], args[1]
VIEW = args[2] if len(args) > 2 else 'front'
TILT = math.radians(float(os.environ.get('BH_TILT', '9')))
ROLL = math.radians(float(os.environ.get('BH_ROLL', '0')))
GAIN = float(os.environ.get('BH_GAIN', '1'))
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
with open(os.path.join(SRC, 'manifest.json'), encoding='utf-8') as fh:
    pieces = json.load(fh)['pieces']
for p in pieces:
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, p['name'] + '.glb'))
    ob = bpy.context.selected_objects[0]
    if p['kind'] == 'shadow':
        ob.pass_index = 1
    m = bpy.data.materials.new('P_' + p['name'])
    m.use_nodes = True
    nt = m.node_tree
    out = nt.nodes['Material Output']
    for nd in list(nt.nodes):
        if nd != out:
            nt.nodes.remove(nd)
    em = nt.nodes.new('ShaderNodeEmission')
    if p['kind'] == 'ring' and os.environ.get('BH_RING') == 'solid':   # (MI_TrainingRing drawn solid: no see-through)
        em.inputs['Color'].default_value = (*p['rgb'], 1)
        em.inputs['Strength'].default_value = 1.15 * GAIN
        nt.links.new(em.outputs[0], out.inputs[0])
    elif p['kind'] == 'shadow':
        em.inputs['Color'].default_value = (0, 0, 0, 1)
        nt.links.new(em.outputs[0], out.inputs[0])
    else:
        em.inputs['Color'].default_value = (*p['rgb'], 1)
        tr = nt.nodes.new('ShaderNodeBsdfTransparent')
        add = nt.nodes.new('ShaderNodeAddShader')
        if p['kind'] == 'glow':                      # (bright edge-on: 1 - facing, to a power)
            lw = nt.nodes.new('ShaderNodeLayerWeight')
            lw.inputs['Blend'].default_value = 0.5
            pw = nt.nodes.new('ShaderNodeMath')
            pw.operation = 'POWER'
            pw.inputs[1].default_value = 1.5
            mul = nt.nodes.new('ShaderNodeMath')
            mul.operation = 'MULTIPLY'
            mul.inputs[1].default_value = 2.2 * p['opacity'] * GAIN
            nt.links.new(lw.outputs['Facing'], pw.inputs[0])
            nt.links.new(pw.outputs[0], mul.inputs[0])
            nt.links.new(mul.outputs[0], em.inputs['Strength'])
            nt.links.new(em.outputs[0], add.inputs[0])
            nt.links.new(tr.outputs[0], add.inputs[1])
            nt.links.new(add.outputs[0], out.inputs[0])
        else:                                        # (the game blends them over what's behind: opacity, not added light)
            em.inputs['Strength'].default_value = 1.25 * GAIN
            mix = nt.nodes.new('ShaderNodeMixShader')
            mix.inputs['Fac'].default_value = p['opacity']
            nt.links.new(tr.outputs[0], mix.inputs[1])
            nt.links.new(em.outputs[0], mix.inputs[2])
            nt.links.new(mix.outputs[0], out.inputs[0])
        m.blend_method = 'BLEND'
        m.shadow_method = 'NONE'
        m.use_backface_culling = False
        m.show_transparent_back = True
    ob.data.materials.clear()
    ob.data.materials.append(m)
    # the camera looks along +Y: facing pieces turn their +Z to -Y (their +Y, the arch's top, up); the disk's +Z up,
    # tipped towards the camera
    ob.rotation_mode = 'XYZ'
    ob.rotation_euler = (math.pi / 2, 0, 0) if p['faces'] else (TILT, 0, 0)
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
scene.collection.objects.link(cam)
cam.location = {'front': (0.0, -7.5, 0.0), 'close': (0.0, -4.6, 0.0), 'side': (-5.0, -5.0, 0.6),
                'high': (0.0, -6.0, 3.2)}.get(VIEW, (0, -7.5, 0))
d = (-cam.location[0], -cam.location[1], -cam.location[2])
cam.rotation_mode = 'XYZ'
cam.rotation_euler = (math.pi / 2 + math.atan2(d[2], math.hypot(d[0], d[1])), ROLL, math.atan2(d[1], d[0]) - math.pi / 2)
cam.data.lens = 40
scene.camera = cam
world = bpy.data.worlds.new('w')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.01, 0.01, 0.015, 1)
scene.world = world
scene.render.engine = 'BLENDER_EEVEE'
scene.eevee.use_bloom = True
scene.eevee.bloom_intensity = float(os.environ.get('BH_BLOOM', '0.05'))
scene.eevee.bloom_radius = 3.0
scene.view_settings.view_transform = 'Standard'    # (as the game's colours: no filmic wash)
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print('preview:', OUT)
