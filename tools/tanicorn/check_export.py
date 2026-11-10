"""re-imports every exported glTF into an empty Blender scene and checks it against its json"""
import bpy, sys, os, json, math
from mathutils import Vector
root = sys.argv[sys.argv.index("--") + 1]
parts = json.load(open(os.path.join(root, "parts.json")))
bad = 0
def say(ok, msg):
    global bad
    if not ok: bad += 1
    print("CHECK %s %s" % ("ok  " if ok else "FAIL", msg))
for p in parts:
    info = json.load(open(os.path.join(root, "src_" + p, "Tani_%s.json" % p)))
    for suffix in ([""] + (["_DAM"] if info["wreck"] else [])):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        f = os.path.join(root, "src_" + p, "Tani_%s%s.gltf" % (p, suffix))
        bpy.ops.import_scene.gltf(filepath=f)
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
        arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
        tris = sum(sum(len(pl.vertices) - 2 for pl in o.data.polygons) for o in meshes)
        vs = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
        lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))); hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        nmat = len({s.material.name for o in meshes for s in o.material_slots if s.material})
        msg = "%-8s%-4s tris %6d (json %6d) mats %2d (json %2d) bounds x %.1f..%.1f y %.1f..%.1f z %.1f..%.1f m" % (p, suffix, tris, info["triangles"], nmat, len(info["slots"]), lo.x, hi.x, lo.y, hi.y, lo.z, hi.z)
        ok = tris == info["triangles"] and nmat == len(info["slots"])
        if suffix == "" and info["kind"] != "hull":
            bones = [b.name for b in arms[0].data.bones] if arms else []
            ok = ok and len(arms) == 1 and set(info["bones"]) == set(bones)
            # bone places (Blender m, y as Blender) against the json (UE cm, y flipped)
            worst = 0.0
            for b in arms[0].data.bones:
                w = arms[0].matrix_world @ b.head_local
                j = info["bones"][b.name]
                worst = max(worst, (Vector((j[0] / 100, -j[1] / 100, j[2] / 100)) - w).length)
            msg += " | bones %d, worst place off %.4f m" % (len(bones), worst)
            ok = ok and worst < 1e-3
            if info["kind"] == "vls":
                acts = list(bpy.data.actions)
                ok = ok and len(acts) == 1
                if acts:
                    a = acts[0]
                    arm = arms[0]
                    arm.animation_data_create(); arm.animation_data.action = a
                    sc = bpy.context.scene
                    lid = next(o for o in meshes)
                    # a lid's far edge moves when the animation plays: measure a vertex weighted to Hatch_01
                    g = lid.vertex_groups.get("Hatch_01")
                    idx = [v.index for v in lid.data.vertices if any(gr.group == g.index and gr.weight > 0.5 for gr in v.groups)]
                    def pos(frame):
                        sc.frame_set(frame)
                        dg = bpy.context.evaluated_depsgraph_get()
                        ev = lid.evaluated_get(dg)
                        me = ev.to_mesh()
                        pts = [ev.matrix_world @ me.vertices[i].co for i in idx]
                        c = sum(pts, Vector()) / len(pts)
                        ev.to_mesh_clear()
                        return c
                    a0, a1 = pos(int(a.frame_range[0])), pos(int(a.frame_range[1]))
                    msg += " | anim '%s' frames %.0f-%.0f at %d fps, Hatch_01's lid moves %.2f m (up %.2f, out %.2f)" % (a.name, a.frame_range[0], a.frame_range[1], sc.render.fps, (a1 - a0).length, a1.z - a0.z, a1.y - a0.y)
                    sc.frame_set(int(a.frame_range[0])); q0 = arm.pose.bones["Hatch_01"].matrix.to_quaternion()
                    sc.frame_set(int(a.frame_range[1])); q1 = arm.pose.bones["Hatch_01"].matrix.to_quaternion()
                    swing = math.degrees(q0.rotation_difference(q1).angle); swing = min(swing, 360.0 - swing)
                    far = max((ev_p - arm.matrix_world @ arm.data.bones["Hatch_01"].head_local).length for ev_p in [lid.matrix_world @ lid.data.vertices[i].co for i in idx])
                    msg += ", swings %.1f deg (json %.1f), lid reaches %.2f m from its hinge, %d verts" % (swing, abs(info["anim"]["open_deg"]), far, len(idx))
                    ok = ok and abs(swing - abs(info["anim"]["open_deg"])) < 0.5
        say(ok, msg)
    if info["kind"] == "turret":
        print("CHECK      %-8s pitch pivot %s cm, sockets %s, guns lie %s m from the pivot" % (p, info["bones"]["turret_pitch"], [(s["name"], s["loc"]) for s in info["sockets"]], info["guns_forward_m"]))
    if info["kind"] == "vls":
        print("CHECK      %-8s SOC_Vls_01 %s rot %s ; Hatch_01 %s" % (p, info["sockets"][0]["loc"], info["sockets"][0]["rot"], info["bones"]["Hatch_01"]))
h = json.load(open(os.path.join(root, "src_HULL", "Tani_HULL.json")))
for s in h["sockets"]:
    if s["name"] in ("Mount_T16_FWD", "Mount_T16_AFT", "Mount_CIWS_1", "Mount_VLSD_1", "Mount_VLSS_L4", "Mount_VLSS_R4", "Mount_LASER_AFT_L"):
        print("CHECK      hull socket %-18s loc %s cm rot (pitch, yaw, roll) %s" % (s["name"], s["loc"], s["rot"]))
print("CHECK %s: %d parts, %d failures" % ("ALL OK" if not bad else "FAILED", len(parts), bad))
