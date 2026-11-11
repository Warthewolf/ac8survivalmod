"""re-imports every exported glTF into an empty Blender scene and checks it against its json: triangles, slots, bones
and their places; a VLS block's lids swing as the json says; a deploying part (the railcannon, the sub-railguns) played to
the end of its Deploy has every bone turned and placed, and every bone's meshes where the export says (its json's anim)"""
import bpy, sys, os, json, math
from mathutils import Vector
DEPLOY = ("railcannon", "railgun")      # export_tanacorn.py deploying()
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
        msg = "%-10s%-4s tris %6d (json %6d) mats %2d (json %2d) bounds x %.1f..%.1f y %.1f..%.1f z %.1f..%.1f m" % (p, suffix, tris, info["triangles"], nmat, len(info["slots"]), lo.x, hi.x, lo.y, hi.y, lo.z, hi.z)
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
            elif info["kind"] in DEPLOY:
                an = info["anim"]
                acts = list(bpy.data.actions)
                ok = ok and len(acts) == 1
                if acts:
                    a, arm, sc = acts[0], arms[0], bpy.context.scene
                    arm.animation_data_create(); arm.animation_data.action = a
                    def go(fr):
                        sc.frame_set(int(fr), subframe=fr - int(fr))
                    first, last = a.frame_range
                    secs = (last - first) / sc.render.fps
                    go(first)
                    q0 = {b: arm.pose.bones[b].matrix.to_quaternion() for b in an["bones"]}
                    go(last)
                    dg = bpy.context.evaluated_depsgraph_get()
                    # every vertex on a bone (weight > 0.5) where the played mesh has it at the end
                    ends = {}
                    for o in meshes:
                        gi = {g.index: g.name for g in o.vertex_groups}
                        idx = {}
                        for v in o.data.vertices:
                            for g in v.groups:
                                if g.weight > 0.5:
                                    idx.setdefault(gi[g.group], []).append(v.index)
                        ev = o.evaluated_get(dg)
                        me = ev.to_mesh()
                        for b, ii in idx.items():
                            ends.setdefault(b, []).extend(ev.matrix_world @ me.vertices[i].co for i in ii)
                        ev.to_mesh_clear()
                    wt = wh = wb = 0.0
                    for b, want in an["bones"].items():
                        pb = arm.pose.bones[b]
                        sw = math.degrees(q0[b].rotation_difference(pb.matrix.to_quaternion()).angle); sw = min(sw, 360.0 - sw)
                        wt = max(wt, abs(sw - want["turns_deg"]))
                        wh = max(wh, ((arm.matrix_world @ pb.head) - Vector(want["end_head_m"])).length)
                        if "end_box_m" in want:
                            P = ends.get(b)
                            if not P:
                                wb = float("inf")
                                continue
                            lo = Vector([min(v[i] for v in P) for i in range(3)]); hi = Vector([max(v[i] for v in P) for i in range(3)])
                            wb = max(wb, (lo - Vector(want["end_box_m"][0])).length, (hi - Vector(want["end_box_m"][1])).length)
                    msg += (" | anim '%s' %.3f s (json %.3f; frames %.1f-%.1f at %d fps), at its end every bone within %.2f deg "
                            "and %.4f m of the export, its meshes' box within %.4f m" % (a.name, secs, an["length_s"], first, last,
                                                                                        sc.render.fps, wt, wh, wb))
                    ok = ok and abs(secs - an["length_s"]) < 0.02 and wt < 0.5 and wh < 0.01 and wb < 0.01
            elif info["kind"] == "rig":
                # (2026-11-11, the rise rig: export_tanacorn.py rise_rig) played back: BN_RiseHull's whole move (its pose
                # against its rest) at every frame, the bow's tip through it; its start under the sea, its end the
                # identity (the hull on its spot), the bow's top 500-600 m, the length the json's within a frame
                an = info["anim"]
                acts = list(bpy.data.actions)
                ok = ok and len(acts) == 1
                if acts:
                    a, arm, sc = acts[0], arms[0], bpy.context.scene
                    arm.animation_data_create(); arm.animation_data.action = a
                    first, last = a.frame_range
                    secs = (last - first) / sc.render.fps
                    b = arm.data.bones["BN_RiseHull"]

                    def move(fr):
                        sc.frame_set(int(fr))
                        pb = arm.pose.bones["BN_RiseHull"]
                        return arm.matrix_world @ pb.matrix @ b.matrix_local.inverted() @ arm.matrix_world.inverted()
                    m0, m1 = move(first), move(last)
                    top, top_t = -1e9, 0.0
                    for fr in range(int(first), int(last) + 1):
                        z = (move(fr) @ Vector((an["bow_x_m"], 0.0, 0.0))).z
                        if z > top:
                            top, top_t = z, (fr - first) / sc.render.fps
                    end_off = m1.translation.length
                    end_turn = math.degrees(m1.to_quaternion().angle)
                    end_turn = min(end_turn, 360.0 - end_turn)
                    msg += (" | anim '%s' %.3f s (json %.3f), the hull at the start %.1f m (json %.1f), at the end %.4f m and "
                            "%.3f deg off its rest, the bow's top %.1f m at %.2f s (json %.1f at %.2f)"
                            % (a.name, secs, an["length_s"], m0.translation.z, an["start_z_m"], end_off, end_turn, top, top_t,
                               an["bow_top_m"], an["bow_top_s"]))
                    ok = (ok and abs(secs - an["length_s"]) < 1.0 / an["fps"] + 1e-3 and m0.translation.z < -100.0
                          and end_off < 0.01 and end_turn < 0.05 and 500.0 <= top <= 600.0 and abs(top - an["bow_top_m"]) < 1.0)
        say(ok, msg)
    if info["kind"] == "turret":
        print("CHECK      %-8s pitch pivot %s cm, sockets %s, guns lie %s m from the pivot" % (p, [v for k, v in info["bones"].items() if k.endswith("turret_pitch")][0], [(s["name"], s["loc"]) for s in info["sockets"]], info["guns_forward_m"]))
    if info["kind"] == "vls":
        print("CHECK      %-8s SOC_Vls_01 %s rot %s ; Hatch_01 %s" % (p, info["sockets"][0]["loc"], info["sockets"][0]["rot"], info["bones"]["Hatch_01"]))
    if info["kind"] == "rig":
        print("CHECK      %-10s sockets %s; Rise %.1f s, %d samples, the hull's keys %s" % (
            p, [(s["name"], s["bone"]) for s in info["sockets"]], info["anim"]["length_s"], info["anim"]["samples"],
            [(k[0], k[1], k[2]) for k in info["anim"]["hull_keys"]]))
    if info["kind"] in DEPLOY:
        an, s0 = info["anim"], info["sockets"][0]
        print("CHECK      %-10s %s on %s at %s cm rot %s; Deploy %.3f s (the design's frames %d-%d; it stows at %d-%d): %s" % (
            p, s0["name"], s0["bone"], s0["loc"], s0["rot"], an["length_s"], an["design_frames"][0], an["design_frames"][1],
            an["design_stow_frames"][0], an["design_stow_frames"][1],
            ", ".join("%s %.1f deg%s" % (b, w["turns_deg"], ", %.2f m" % w["moves_m"] if w["moves_m"] else "") for b, w in an["bones"].items())))
h = json.load(open(os.path.join(root, "src_HULL", "Tani_HULL.json")))
for s in h["sockets"]:
    if s["name"] in ("Mount_T16_FWD", "Mount_T16_AFT", "Mount_CIWS_1", "Mount_VLSD_1", "Mount_VLSS_L4", "Mount_VLSS_R4", "Mount_LASER_AFT_L",
                     "Mount_RAILCANNON", "Mount_RAILGUN_L", "Mount_RAILGUN_R"):
        print("CHECK      hull socket %-18s loc %s cm rot (pitch, yaw, roll) %s" % (s["name"], s["loc"], s["rot"]))
print("CHECK %s: %d parts, %d failures" % ("ALL OK" if not bad else "FAILED", len(parts), bad))
