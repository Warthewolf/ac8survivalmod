"""preview.py : pictures of the SOLG's rig (tools/solg/prepare.py's SK_SV_SOLG.gltf) at moments of its spin animation,
for a look before the cook (the rings turning the opposite ways, the arms on their axes).

  blender -b -P tools/solg/preview.py -- <build/solg folder> <out prefix> [seconds ...]

Grey shaded (the glTF carries no textures: the game paints them). Writes <out prefix>_<s>s.png for each moment.
"""
import math
import os
import sys

import bpy

args = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT = args[0], args[1]
SECS = [float(x) for x in args[2:]] or [0.0, 5.0, 10.0]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, 'SK_SV_SOLG.gltf'))
fps = scene.render.fps
for ob in scene.objects:
    if ob.type == 'MESH':
        m = bpy.data.materials.new('grey')
        m.use_nodes = True
        m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.6, 0.6, 0.62, 1)
        ob.data.materials.clear()
        ob.data.materials.append(m)
for ob in scene.objects:                                # (the wreck bones' meshes hidden: their bones scaled to 0)
    if ob.type == 'ARMATURE':
        for pb in ob.pose.bones:
            if pb.name.endswith('_W'):
                pb.scale = (0.001, 0.001, 0.001)
                pb.keyframe_insert('scale', frame=0)
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN'))
sun.data.energy = 4
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
scene.collection.objects.link(sun)
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
scene.collection.objects.link(cam)
# the SOLG lies along glTF +X (Blender +X after import): a camera off its nose end, up and to the side
cam.location = (1900.0, -1500.0, 700.0)
d = (550.0 - cam.location[0], 0.0 - cam.location[1], 0.0 - cam.location[2])
cam.rotation_mode = 'XYZ'
cam.rotation_euler = (math.pi / 2 + math.atan2(d[2], math.hypot(d[0], d[1])), 0, math.atan2(d[1], d[0]) - math.pi / 2)
cam.data.lens = 35
cam.data.clip_end = 20000
scene.camera = cam
world = bpy.data.worlds.new('w')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.25, 0.32, 0.45, 1)
scene.world = world
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
for s in SECS:
    scene.frame_set(int(round(s * fps)))
    scene.render.filepath = '%s_%02ds.png' % (OUT, int(s))
    bpy.ops.render.render(write_still=True)
    print('preview:', scene.render.filepath)
