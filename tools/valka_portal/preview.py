"""preview.py : a picture of VALKA's black hole (make_portal.py's glTFs) put together as Survival puts it in game (the
shadow, the photon ring and the lensed arcs facing you, the disk tilted 10 degrees towards you), coloured as in game,
for a look before the cook.

  blender -b -P tools/valka_portal/preview.py -- <src folder> <out.png> [front|side|high] [red]
"""
import math
import os
import sys

import bpy

args = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT = args[0], args[1]
VIEW = args[2] if len(args) > 2 else 'front'
RED = 'red' in args[3:]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
# name: (colour, emission strength, faces you (else: the disk, tilted))
PARTS = {'SM_SV_BHShadow': ((0, 0, 0), 0.0, True), 'SM_SV_BHPhotonRing': ((1.0, 0.92, 0.8), 14.0, True),
         'SM_SV_BHHaloInner': ((1.0, 0.8, 0.55), 9.0, True), 'SM_SV_BHHaloOuter': ((1.0, 0.5, 0.18), 5.0, True),
         'SM_SV_BHDiskHot': ((1.0, 0.75, 0.45), 9.0, False), 'SM_SV_BHDiskWarm': ((0.95, 0.45, 0.12), 6.0, False),
         'SM_SV_BHDiskCool': ((0.55, 0.18, 0.04), 4.0, False), 'SM_SV_BHDiskBright': ((1.0, 0.95, 0.85), 14.0, False)}
TILT = math.radians(5)
for name, (rgb, power, faces) in PARTS.items():
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name + '.glb'))
    ob = bpy.context.selected_objects[0]
    m = bpy.data.materials.new('P_' + name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*rgb, 1)
    bsdf.inputs['Emission'].default_value = (*rgb, 1)
    bsdf.inputs['Emission Strength'].default_value = power
    if power == 0:                                  # (the shadow: no shine, as AC8's flat black in game)
        bsdf.inputs['Specular'].default_value = 0.0
        bsdf.inputs['Roughness'].default_value = 1.0
    ob.data.materials.clear()
    ob.data.materials.append(m)
    # the camera looks along +Y: facing parts turn their +Z to -Y (their +Y, the arcs' broad top, up); the disk's +Z up,
    # tipped towards the camera
    ob.rotation_mode = 'XYZ'
    ob.rotation_euler = (math.pi / 2, 0, 0) if faces else (TILT, 0, 0)
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
scene.collection.objects.link(cam)
cam.location = {'front': (0.0, -7.5, 0.0), 'side': (-5.0, -5.0, 0.6), 'high': (0.0, -6.0, 3.2)}.get(VIEW, (0, -7.5, 0))
d = (-cam.location[0], -cam.location[1], -cam.location[2])
cam.rotation_mode = 'XYZ'
cam.rotation_euler = (math.pi / 2 + math.atan2(d[2], math.hypot(d[0], d[1])), 0, math.atan2(d[1], d[0]) - math.pi / 2)
cam.data.lens = 40
scene.camera = cam
world = bpy.data.worlds.new('w')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.55, 0.18, 0.12, 1) if RED else (0.01, 0.01, 0.015, 1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.6 if RED else 1.0
scene.world = world
scene.render.engine = 'BLENDER_EEVEE'
scene.eevee.use_bloom = True
scene.eevee.bloom_intensity = 0.12
scene.eevee.bloom_radius = 5.0
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print('preview:', OUT)
