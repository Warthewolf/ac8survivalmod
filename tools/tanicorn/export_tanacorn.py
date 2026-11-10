"""export_tanacorn.py : Blender 3.3, THE TANACORN's parts and hull out of the model for UE 5.4 (docs/design/
INVINCIBLE_FLEET.md WP0, the step after the model: "prepare us for Unreal Engine").

  blender -b <model dir>/Tanacorn_model.blend -P tools/tanicorn/export_tanacorn.py -- <out dir>

Run on the file model_tanacorn.py saves. For every part type it writes <out dir>/src_<PART>/ as tools/tanicorn's
ue_import.py reads it (the route prepare_part.py proved with the first 5-inch mount), each part in the frame of the hull
socket it sits on (SOCKET_Mount_<name>: its base at the origin, +X its forward), in metres, glTF Y-up:
  turrets  T16 (the 16-inch triple), T5 (the 5-inch twin), CIWS, LASER (the beam director):
           Tani_<P>.gltf skinned BN_Body > BN_turret_yaw > BN_turret_pitch (the stock turrets' names, 0.74.59), every joint
           with an identity rotation, the house on BN_turret_yaw, the guns on BN_turret_pitch (its place the guns' trunnion);
           muzzle sockets SOC_Gun_NN on BN_turret_pitch
  VLS      VLSD (the aft deck's block; one mesh for all 8) and VLSS_L1..L4 / VLSS_R1..R4 (the bow's side blocks, each
           bent onto its own stretch of the hull): Tani_<P>.gltf skinned Body > Hatch_01..08, each lid's joint on its
           hinge, and the animation "Open" (0.5 s: every lid swings open about its hinge); sockets SOC_Vls_01..08 on
           Body with their launch direction
  deploying (the Alicorn's moving parts, the design's own rigs and keys; rest = stowed, frame 1; identity rotations):
           RAILCANNON (kind railcannon): Body (the bay section + RC_body) > railcannon_pitch > barrel_n / barrel_p (the
           barrel halves, the bow's doors), SOC_Gun_01 at the barrels' mouth on railcannon_pitch;
           RAILGUN_L / RAILGUN_R (kind railgun): Body > lift > BN_turret_yaw > BN_turret_pitch, Body > Hatch_n / Hatch_p,
           SOC_Gun_01 at the rails' tip on BN_turret_pitch; each with the animation "Deploy" (the design's sequence
           sampled every frame from the part's first key until every bone is out: a rotation, and the lift's
           translation; frames and length in the json's "anim")
  the hull HULL: Tani_HULL.gltf static (the fused hull and the two pods), and every mount's socket in its json
  each     Tani_<P>_DAM.gltf (the same geometry static: the wreck the destroy system swaps in; not the hull), its
           textures as ordinary PNGs (the Iowa's as the Alicorn's grey with their own light and shade: the design's
           _ALCPAINT materials baked in; the model's own baked ones and the Alicorn's two sheets as they are; the eight
           side blocks share one set, T_SV_Tani_VLSS_*), a flat normal and a blank livemap, and Tani_<P>.json: kind, bones and sockets in UE cm (y flipped) with UE rotators (pitch,
           yaw, roll), material slots, the hull sockets it sits on
and <out dir>/parts.json (the list ue_import.py and spec.py go through) and tanacorn_parts.json (the whole manifest).
The hull is exported without the deploying parts (their sockets' parts close its bay and wells); Mount_CORE has no
part yet (WP11: the phase-3 core).
The Iowa's parts are Sea Power's: the user's dev install only, never shipped.
"""
import bpy, sys, os, json, math, struct
import numpy as np
from mathutils import Vector, Matrix, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("build/tanicorn")
os.makedirs(OUT, exist_ok=True)
GREY = (0.058, 0.059, 0.062)          # the Alicorn plating's mean colour (linear), as the Leviathan's upper works
bpy.context.scene.frame_set(1)        # everything at rest (the deploy sequence starts later)
OPEN_FRAME = 170                      # every VLS lid is open here (model_tanacorn.py HATCH_KEYS: open 165-290)
D = bpy.data.objects


# ---------------------------------------------------------------------------------------------------- frames
def ue_cm(v):                          # Blender m -> UE cm (y flips)
    return [round(v[0] * 100.0, 3), round(-v[1] * 100.0, 3), round(v[2] * 100.0, 3)]


def ue_rot(M):
    """a Blender rotation as UE's FRotator (pitch, yaw, roll) in degrees: UE's axes are (x, -y, z), so its matrix is
    F R F with F = diag(1, -1, 1); checked by building UE's own matrix back from the angles"""
    R = np.array(M.to_3x3().normalized())
    F = np.diag([1.0, -1.0, 1.0])
    U = F @ R @ F
    X, Y, Z = U[:, 0], U[:, 1], U[:, 2]
    pitch, yaw = math.asin(max(-1.0, min(1.0, X[2]))), math.atan2(X[1], X[0])
    roll = math.atan2(-Y[2], Z[2])
    sp, cp, sy, cy, sr, cr = math.sin(pitch), math.cos(pitch), math.sin(yaw), math.cos(yaw), math.sin(roll), math.cos(roll)
    B = np.array([[cp * cy, cp * sy, sp], [sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp],
                  [-(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp]]).T
    assert np.abs(B - U).max() < 1e-4, "rotator does not rebuild its matrix"
    return [round(math.degrees(a), 4) for a in (pitch, yaw, roll)]


def gl(a):                             # Blender (x, y, z) -> glTF (x, z, -y), rows of an array
    a = np.asarray(a, dtype=np.float32)
    return np.stack([a[..., 0], a[..., 2], -a[..., 1]], axis=-1)


# ---------------------------------------------------------------------------------------------------- geometry
def geom(obj, M):
    """the object's triangles through M: per corner position, normal, uv; per triangle its material's name"""
    me = obj.data
    me.calc_loop_triangles()
    me.calc_normals_split()
    nv, nl, nt = len(me.vertices), len(me.loops), len(me.loop_triangles)
    co = np.empty(nv * 3, np.float32)
    me.vertices.foreach_get("co", co)
    lv = np.empty(nl, np.int32)
    me.loops.foreach_get("vertex_index", lv)
    ln = np.empty(nl * 3, np.float32)
    me.loops.foreach_get("normal", ln)
    uv = np.zeros(nl * 2, np.float32)
    if me.uv_layers.active:
        me.uv_layers.active.data.foreach_get("uv", uv)
    tl = np.empty(nt * 3, np.int32)
    me.loop_triangles.foreach_get("loops", tl)
    tm = np.empty(nt, np.int32)
    me.loop_triangles.foreach_get("material_index", tm)
    M3, t = np.array(M.to_3x3()), np.array(M.translation)
    P = co.reshape(nv, 3)[lv] @ M3.T + t
    N = ln.reshape(nl, 3) @ np.array(M.to_3x3().inverted().transposed()).T
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
    tl = tl.reshape(nt, 3)
    names = [s.material.name if s.material else "" for s in obj.material_slots] or [""]
    return P[tl], N[tl], uv.reshape(nl, 2)[tl], [names[min(i, len(names) - 1)] for i in tm]


class Mesh:
    """triangles by material, each corner on a joint"""

    def __init__(self):
        self.by = {}

    def add(self, obj, M, joint=0):
        P, N, UV, mats = geom(obj, M)
        mats = np.array(mats)
        for m in sorted(set(mats)):
            k = mats == m
            self.by.setdefault(m, []).append((P[k].reshape(-1, 3), N[k].reshape(-1, 3), UV[k].reshape(-1, 2),
                                              np.full(int(k.sum()) * 3, joint, np.int32)))

    def prims(self):
        out = []
        for m, parts in self.by.items():
            P, N, UV, J = (np.concatenate([p[i] for p in parts]) for i in range(4))
            rows = np.round(np.concatenate([P, N, UV, J[:, None].astype(np.float32)], axis=1), 5)
            _, first, inv = np.unique(rows, axis=0, return_index=True, return_inverse=True)   # corners shared: an index buffer
            t = inv.reshape(-1, 3)                          # (a triangle with two corners the same draws nothing, and
            t = t[(t[:, 0] != t[:, 1]) & (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])]   # every importer drops it)
            out.append((m, P[first], N[first], UV[first], J[first], t.reshape(-1).astype(np.uint32)))
        return out


def write_gltf(path, name, prims, slots, joints=None, anim=None):
    """joints: [(name, parent index or -1, world place in the part's frame)] with identity rotations; anim: (name,
    times, [(joint index, [quaternions (x, y, z, w) in the part's Blender frame] or None[, [the joint's translations
    from its parent, Blender frame]])]): a rotation channel, a translation channel, or both"""
    bins = bytearray()
    views, accs = [], []

    def add(arr, comp, typ, target=None, minmax=False):
        while len(bins) % 4:
            bins.append(0)
        data = arr.tobytes()
        views.append({"buffer": 0, "byteOffset": len(bins), "byteLength": len(data), **({"target": target} if target else {})})
        bins.extend(data)
        a = {"bufferView": len(views) - 1, "componentType": comp, "count": len(arr), "type": typ}
        if minmax:
            a["min"], a["max"] = [float(x) for x in arr.min(axis=0)], [float(x) for x in arr.max(axis=0)]
        accs.append(a)
        return len(accs) - 1
    order = [s["material"] for s in slots]
    gprims = []
    for m, P, N, UV, J, idx in sorted(prims, key=lambda p: order.index(p[0])):
        attrs = {"POSITION": add(gl(P), 5126, "VEC3", 34962, True), "NORMAL": add(gl(N), 5126, "VEC3", 34962),
                 "TEXCOORD_0": add(np.stack([UV[:, 0], 1.0 - UV[:, 1]], axis=1).astype(np.float32), 5126, "VEC2", 34962)}
        if joints:
            j4 = np.zeros((len(J), 4), np.uint16)
            j4[:, 0] = J
            w4 = np.zeros((len(J), 4), np.float32)
            w4[:, 0] = 1.0
            attrs["JOINTS_0"], attrs["WEIGHTS_0"] = add(j4, 5123, "VEC4", 34962), add(w4, 5126, "VEC4", 34962)
        gprims.append({"attributes": attrs, "indices": add(idx, 5125, "SCALAR", 34963), "material": order.index(m)})
    doc = {"asset": {"version": "2.0", "generator": "Survival tanicorn/export_tanacorn.py"}, "scene": 0,
           "materials": [{"name": "M_SV_%s_%d" % (name, s["slot"]), "pbrMetallicRoughness": {"baseColorFactor": [*GREY, 1.0]}}
                         for s in slots],
           "meshes": [{"name": os.path.basename(path)[:-5], "primitives": gprims}]}
    if joints:
        world = [Vector(j[2]) for j in joints]
        nodes = []
        for i, (jn, parent, at) in enumerate(joints):
            rel = world[i] - (world[parent] if parent >= 0 else Vector())
            n = {"name": jn, "translation": [float(x) for x in gl(np.array(rel))]}
            kids = [k for k, j in enumerate(joints) if j[1] == i]
            if kids:
                n["children"] = kids
            nodes.append(n)
        ibm = np.zeros((len(joints), 16), np.float32)
        for i, w in enumerate(world):
            g = gl(np.array(w))
            ibm[i] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -g[0], -g[1], -g[2], 1]
        nodes.append({"name": name, "mesh": 0, "skin": 0})
        doc["skins"] = [{"joints": list(range(len(joints))), "skeleton": 0, "inverseBindMatrices": add(ibm, 5126, "MAT4")}]
        doc["nodes"], doc["scenes"] = nodes, [{"nodes": [0, len(joints)]}]
        if anim:
            aname, times, chans = anim
            t_acc = add(np.array(times, np.float32).reshape(-1, 1), 5126, "SCALAR", None, True)
            samplers, channels = [], []
            for ch in chans:
                j, quats, trans = ch[0], ch[1], (ch[2] if len(ch) > 2 else None)
                if quats is not None:
                    q = np.array(quats, np.float32)                    # (x, y, z, w) -> glTF axes (x, z, -y, w)
                    q = np.stack([q[:, 0], q[:, 2], -q[:, 1], q[:, 3]], axis=1)
                    samplers.append({"input": t_acc, "output": add(q, 5126, "VEC4"), "interpolation": "LINEAR"})
                    channels.append({"sampler": len(samplers) - 1, "target": {"node": j, "path": "rotation"}})
                if trans is not None:                                  # (a node's whole translation from its parent)
                    samplers.append({"input": t_acc, "output": add(gl(np.array(trans)), 5126, "VEC3"), "interpolation": "LINEAR"})
                    channels.append({"sampler": len(samplers) - 1, "target": {"node": j, "path": "translation"}})
            doc["animations"] = [{"name": aname, "samplers": samplers, "channels": channels}]
    else:
        doc["nodes"], doc["scenes"] = [{"name": name, "mesh": 0}], [{"nodes": [0]}]
    doc["buffers"] = [{"uri": os.path.basename(path)[:-5] + ".bin", "byteLength": len(bins)}]
    doc["bufferViews"], doc["accessors"] = views, accs
    with open(path[:-5] + ".bin", "wb") as f:
        f.write(bins)
    with open(path, "w") as f:
        json.dump(doc, f, indent=1)


# ---------------------------------------------------------------------------------------------------- textures
def base_image(mat, socket="Base Color"):
    if not mat or not mat.use_nodes:
        return None
    bsdf = next((n for n in mat.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
    seen, todo = set(), [bsdf.inputs[socket]] if bsdf else []
    while todo:
        for l in todo.pop().links:
            n = l.from_node
            if n not in seen:
                seen.add(n)
                if n.bl_idname == "ShaderNodeTexImage" and n.image:
                    return n.image
                todo += list(n.inputs)
    return None


def pixels(img):
    w, h = img.size
    a = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(h, w, 4)


def save_png(px, path):
    h, w = px.shape[:2]
    im = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
    out = np.ones((h, w, 4), np.float32)
    out[:, :, :3] = px[:, :, :3]
    im.pixels.foreach_set(out.ravel())
    im.filepath_raw, im.file_format = path, "PNG"
    im.save()
    bpy.data.images.remove(im)


def grey(px):
    """the design's _ALCPAINT materials baked into the texture: the Alicorn's grey times the source's light and shade
    (its brightness, 0.1..0.7 -> 0.75..1.2). The brightness is the LINEAR one, as Blender's RGB to BW node takes it
    (an image's pixels here are the file's sRGB values)"""
    c = px[:, :, :3]
    c = np.where(c <= 0.04045, c / 12.92, np.power((c + 0.055) / 1.055, 2.4))
    lum = c @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    k = 0.75 + (np.clip(lum, 0.1, 0.7) - 0.1) / 0.6 * 0.45
    lin = k[:, :, None] * np.array(GREY, np.float32)
    out = px.copy()
    out[:, :, :3] = np.where(lin > 0.0031308, 1.055 * np.power(lin, 1 / 2.4) - 0.055, lin * 12.92)
    return out


def slots_for(part, folder, mats):
    """a material slot per material in use: its base colour written as T_SV_Tani_<part>_<n>_D (one file per source
    image), the Alicorn's sheets with their normal maps. `part` is the textures' owner: the eight side VLS blocks
    share one set (VLSS)"""
    slots, done = [], {}
    for k, m in enumerate(mats):
        mat = bpy.data.materials.get(m)
        img = base_image(mat)
        own = m.startswith(("TANA_", "ALC_"))
        key = (img.name if img else None, own)
        if key not in done:
            name = "T_SV_Tani_%s_%d_D" % (part, len(done))
            px = pixels(img) if img else np.full((4, 4, 4), 0.5, np.float32)
            save_png(px if own else grey(px), os.path.join(folder, name + ".png"))
            nrm = None
            if m.startswith("ALC_"):
                ni = base_image(mat, "Normal")
                if ni:
                    nrm = "T_SV_Tani_%s_%d_N" % (part, len(done))
                    save_png(pixels(ni), os.path.join(folder, nrm + ".png"))
            done[key] = (name, nrm)
        cut = base_image(mat, "Alpha")
        slots.append({"slot": k, "material": m, "source": img.name if img else None, "basecolor": done[key][0],
                      "normal": done[key][1], **({"cutout": cut.name} if cut else {})})
    # (0.74.61) the livemap on AC8's gear material (MP_Gear) is metallic / roughness / occlusion (docs/re/FALKEN_MATERIALS.md
    # 2.4: the Falken's constant (0, 0.75, 1.0)); all black read as a mirror in full shadow: the user's screenshots of 0.74.60,
    # "the textures look terrible", the whole ship near black on its shaded side
    for name, val in (("T_SV_Tani_%s_N" % part, (0.5, 0.5, 1.0)), ("T_SV_Tani_%s_L" % part, (0.0, 0.75, 1.0))):
        save_png(np.tile(np.array([*val, 1.0], np.float32), (4, 4, 1)), os.path.join(folder, name + ".png"))
    return slots


# ---------------------------------------------------------------------------------------------------- the parts
MANIFEST = {}


def finish(part, mesh, info, joints=None, anim=None, wreck=True, tex=None):
    folder = os.path.join(OUT, "src_" + part)
    os.makedirs(folder, exist_ok=True)
    name = "Tani_" + part
    prims = mesh.prims()
    tex = tex or part
    slots = slots_for(tex, folder, [p[0] for p in prims])
    info.update({"flat_normal": "T_SV_Tani_%s_N" % tex, "livemap": "T_SV_Tani_%s_L" % tex})
    write_gltf(os.path.join(folder, name + ".gltf"), name, prims, slots, joints, anim)
    if wreck:
        write_gltf(os.path.join(folder, name + "_DAM.gltf"), name + "_DAM", prims, slots)
    info.update({"part": name, "slots": slots, "triangles": int(sum(len(p[5]) for p in prims)) // 3, "vertices": int(sum(len(p[1]) for p in prims)),
                 "wreck": wreck})
    with open(os.path.join(folder, name + ".json"), "w") as f:
        json.dump(info, f, indent=1)
    MANIFEST[part] = {k: info[k] for k in ("kind", "on", "triangles", "vertices") if k in info}
    print("export: %-10s %-10s %6d triangles, %6d vertices, %d slots, %d bones, %d sockets, on %s"
          % (part, info["kind"], info["triangles"], info["vertices"], len(slots), len(info.get("bones", {})),
             len(info.get("sockets", [])), ", ".join(info.get("on", [])) or "-"))


def socket_of(name):
    return D["SOCKET_Mount_" + name].matrix_world.copy()


TB_ROOT, TB_YAW, TB_PITCH = "BN_Body", "BN_turret_yaw", "BN_turret_pitch"   # a gun mount's bones (the stock turrets')


def turret(part, on, house, guns, pivot, muzzle=None):
    """a gun mount in the frame of its first hull socket: the house on turret_yaw, the guns on turret_pitch"""
    Mi = socket_of(on[0]).inverted()
    mesh = Mesh()
    mesh.add(D[house], Mi @ D[house].matrix_world, 1)
    mesh.add(D[guns], Mi @ D[guns].matrix_world, 2)
    at = Mi @ pivot
    gw = np.array([Mi @ D[guns].matrix_world @ v.co for v in D[guns].data.vertices])
    c = gw.mean(axis=0)
    if muzzle is not None:
        tips = [Mi @ muzzle]
    else:                                                  # the barrels' mouths: the farthest-forward vertices, by barrel
        front = gw[gw[:, 0] > gw[:, 0].max() - 0.6]
        front = front[np.argsort(-front[:, 1])]            # port first (Blender +y), as the stock SOC_Gun_01..
        gaps = front[:-1, 1] - front[1:, 1]                # (a barrel's own rim has gaps too: only the wide ones part barrels)
        wide = max(0.5, 0.3 * float(gaps.max())) if len(gaps) else 0.5
        cuts = [0] + [i + 1 for i in range(len(front) - 1) if gaps[i] > wide] + [len(front)]
        tips = [Vector((front[a:b, 0].max(), front[a:b, 1].mean(), front[a:b, 2].mean())) for a, b in zip(cuts, cuts[1:])]
    # (0.74.59) the stock turrets' bone names (BN_Body > BN_turret_yaw > BN_turret_pitch: the Mk45's, the GR023 flak gun's):
    # a stock fire control row (NpcFCSId0) puts its own arm on the mount, driving the BN_ bones (0.74.58: ours, named
    # turret_yaw / turret_pitch, stood still under NPC_FCS_FlakGun000's arm), and only the row's path gives it its muzzle
    info = {"kind": "turret", "on": on,
            "bones": {TB_ROOT: [0, 0, 0], TB_YAW: [0, 0, 0], TB_PITCH: ue_cm(at)},
            "sockets": [{"name": "SOC_Gun_%02d" % (i + 1), "bone": TB_PITCH, "loc": ue_cm(t - at), "rot": [0, 0, 0]}
                        for i, t in enumerate(tips)],
            "guns_forward_m": [round(float(x), 2) for x in c - np.array(at)]}
    finish(part, mesh, info, [(TB_ROOT, -1, (0, 0, 0)), (TB_YAW, 0, (0, 0, 0)), (TB_PITCH, 1, tuple(at))])


def vls(part, on, body, axis, deg, tex=None):
    """a VLS block in its own frame (its hull socket's): Body, a joint a lid on its hinge, the lids' opening"""
    B = D[body]
    Mi = socket_of(on[0]).inverted()
    mesh = Mesh()
    mesh.add(B, Mi @ B.matrix_world, 0)
    lids = sorted((c for c in B.children if "_Hatch_" in c.name), key=lambda o: o.name)
    cells = sorted((c for c in B.children if "_SOC_Vls_" in c.name), key=lambda o: o.name)
    joints, bones = [("Body", -1, (0, 0, 0))], {"Body": [0, 0, 0]}
    for k, lid in enumerate(lids, 1):
        M = Mi @ lid.matrix_world
        mesh.add(lid, M, k)
        joints.append(("Hatch_%02d" % k, 0, tuple(M.translation)))
        bones["Hatch_%02d" % k] = ue_cm(M.translation)
    n, times, quats = 15, [], []
    ax = Vector((1, 0, 0)) if axis == "X" else Vector((0, 1, 0))
    # the swing written here against the model's own keys (model_tanacorn.py HATCH_KEYS: every lid open at OPEN_FRAME):
    # each lid's corners turned about its joint by the whole angle must land where the model's open lid is
    rest = [(lid, Mi @ lid.matrix_world) for lid in lids]
    bpy.context.scene.frame_set(OPEN_FRAME)
    worst = 0.0
    full = Quaternion(ax, math.radians(deg)).to_matrix().to_4x4()
    for lid, M in rest:
        h = Matrix.Translation(M.translation)
        mine, hers = h @ full @ h.inverted() @ M, Mi @ lid.matrix_world
        worst = max(worst, max(((mine @ Vector(c)) - (hers @ Vector(c))).length for c in lid.bound_box))
    bpy.context.scene.frame_set(1)
    assert worst < 0.005, "%s: the exported swing ends %.3f m from the model's open lids" % (part, worst)
    for i in range(n + 1):                                  # 0.5 s at 30 fps, eased in and out
        f = i / n
        q = Quaternion(ax, math.radians(deg) * f * f * (3 - 2 * f))
        times.append(i / 30.0)
        quats.append((q.x, q.y, q.z, q.w))
    info = {"kind": "vls", "on": on, "bones": bones,
            "sockets": [{"name": "SOC_Vls_%02d" % k, "bone": "Body", "loc": ue_cm((Mi @ c.matrix_world).translation),
                         "rot": ue_rot(Mi @ c.matrix_world)} for k, c in enumerate(cells, 1)],
            "anim": {"name": "Open", "length_s": 0.5, "hinge_axis": axis, "open_deg": deg, "off_the_model_m": round(worst, 5),
                     "note": "every Hatch_NN turns about its own %s axis (the part's frame) by open_deg" % axis}}
    finish(part, mesh, info, joints, ("Open", times, [(k, quats) for k in range(1, len(lids) + 1)]), tex=tex)


DEPLOY_FPS = 30                        # the design's deploy sequence (frames 1-360)


def frame_in(Mi, name):
    """an empty's place and turn in a part's frame, its scale taken out (the railcannon's bay is the design's at 0.9)"""
    loc, rot, _ = (Mi @ D[name].matrix_world).decompose()
    return Matrix.Translation(loc) @ rot.to_matrix().to_4x4()


def deploying(part, kind, on, rig, muzzle, tex=None, note=None):
    """an Alicorn part that deploys (the bow's railcannon, a sub-railgun) in the frame of its hull socket. rig: [(bone,
    parent index or -1, the design's empty that moves it)], every mesh child of an empty on that empty's bone; muzzle:
    (the socket's bone index, [bone indices whose meshes make the muzzle], nose m): SOC_Gun_01 at the middle of those
    meshes' front (the vertices within `nose` m of it), along the socket bone's +X. The rest pose is the stowed one
    (frame 1) and every joint has an identity rotation (the bones only carry places, as the turrets'); "Deploy" is the
    design's own keys sampled a frame at a time, from the part's first key to the frame by which every bone is out
    (each one's second key: out, held, back), a rotation and, where it moves (the railgun's lift), a translation for
    each moving joint. Played backwards it stows (the design's own stow, keys 3-4, takes the same poses)."""
    sc = bpy.context.scene
    Mi = socket_of(on[0]).inverted()
    sc.frame_set(1)
    rest = [frame_in(Mi, e) for _, _, e in rig]
    at = [r.translation.copy() for r in rest]
    meshes = [(c.name, j) for j, (_, _, e) in enumerate(rig) for c in sorted(D[e].children, key=lambda o: o.name) if c.type == "MESH"]
    under, todo = set(), [D[rig[0][2]]]                     # everything the design hangs under the part's root
    while todo:
        o = todo.pop()
        for c in o.children:
            under.add(c)
            todo.append(c)
    assert {o.name for o in under if o.type == "MESH"} == {n for n, _ in meshes}, "%s: a mesh not on a bone" % part
    assert {o.name for o in under if o.type == "EMPTY"} == {e for _, _, e in rig[1:]}, "%s: an empty not in the rig" % part
    mesh = Mesh()
    for n, j in meshes:
        mesh.add(D[n], Mi @ D[n].matrix_world, j)
    keys = {}
    for j, (b, _, e) in enumerate(rig):
        ad = D[e].animation_data
        if ad and ad.action:
            ks = sorted({int(round(k.co[0])) for fc in ad.action.fcurves for k in fc.keyframe_points})
            assert len(ks) == 4, "%s: %s's keys %s (out, held, back: 4 expected)" % (part, e, ks)
            keys[j] = ks
    f0, f1 = min(k[0] for k in keys.values()), max(k[1] for k in keys.values())

    def pose(f):                                            # each joint's whole move at frame f, in the part's frame
        sc.frame_set(f)
        return [frame_in(Mi, e) @ rest[j].inverted() @ Matrix.Translation(at[j]) for j, (_, _, e) in enumerate(rig)]
    corners = [(n, j, [Vector(c) for c in D[n].bound_box], Mi @ D[n].matrix_world) for n, j in meshes]
    times, rot, loc, worst = [], {j: [] for j in keys}, {j: [] for j in keys}, 0.0
    for f in range(f0, f1 + 1):
        G = pose(f)
        times.append((f - f0) / DEPLOY_FPS)
        for j in keys:
            p = rig[j][1]
            t, q, _ = (G[p].inverted() @ G[j]).decompose()
            if rot[j] and Quaternion(rot[j][-1][3:] + rot[j][-1][:3]).dot(q) < 0:   # (one hemisphere: no flip between samples)
                q.negate()
            rot[j].append((q.x, q.y, q.z, q.w))
            loc[j].append(tuple(t))
        # every mesh where the design has it at this frame: each must ride its own bone
        for n, j, cs, M1 in corners:
            Mf, mine = Mi @ D[n].matrix_world, G[j] @ Matrix.Translation(-at[j]) @ M1
            worst = max(worst, max(((Mf @ c) - (mine @ c)).length for c in cs))
    end = pose(f1)
    sc.frame_set(1)
    assert worst < 0.005, "%s: the exported deploy ends %.3f m from the model's" % (part, worst)
    chans = []
    for j in keys:
        moves = max((Vector(v) - Vector(loc[j][0])).length for v in loc[j]) > 1e-4
        turns = max(Quaternion((q[3], q[0], q[1], q[2])).rotation_difference(Quaternion()).angle for q in rot[j]) > 1e-5
        chans.append((j, rot[j] if turns or not moves else None, *([loc[j]] if moves else [])))
    # each moving bone at the end: how far it turned and went, where its head and its meshes' box are (Blender m, the
    # part's frame: check_export.py reads the glTF back, plays it to its end and compares)
    by = {}
    for P, _, _, J in (x for parts in mesh.by.values() for x in parts):
        for j in set(J.tolist()):
            by.setdefault(j, []).append(P[J == j])
    out = {}
    for j in keys:
        out[rig[j][0]] = {"design": rig[j][2], "keys": keys[j],
                          "turns_deg": round(math.degrees(end[j].to_quaternion().angle), 3),
                          "moves_m": round((end[j].translation - at[j]).length, 4),
                          "end_head_m": [round(float(x), 4) for x in end[j].translation]}
        if j in by:                                         # (a bone with meshes of its own)
            E = end[j] @ Matrix.Translation(-at[j])
            moved = np.concatenate(by[j]) @ np.array(E.to_3x3()).T + np.array(E.translation)
            out[rig[j][0]]["end_box_m"] = [[round(float(x), 4) for x in moved.min(axis=0)],
                                           [round(float(x), 4) for x in moved.max(axis=0)]]
    # the muzzle: the middle of the front of those meshes' vertices, in the socket bone's own axes (its empty's)
    jm, mj, nose = muzzle
    E = rest[jm]
    pts = np.array([E.inverted() @ Mi @ D[n].matrix_world @ v.co for n, j in meshes if j in mj for v in D[n].data.vertices])
    front = pts[pts[:, 0] > pts[:, 0].max() - nose]
    tip = E @ Vector((float(pts[:, 0].max()), float(front[:, 1].min() + front[:, 1].max()) / 2,
                      float(front[:, 2].min() + front[:, 2].max()) / 2))
    s1, s2 = min(k[2] for k in keys.values()), max(k[3] for k in keys.values())
    info = {"kind": kind, "on": on,
            "bones": {b: ue_cm(at[j]) for j, (b, _, _) in enumerate(rig)},
            "parents": {b: (rig[p][0] if p >= 0 else None) for b, p, _ in rig},
            "sockets": [{"name": "SOC_Gun_01", "bone": rig[jm][0], "loc": ue_cm(tip - at[jm]), "rot": ue_rot(E)}],
            "anim": {"name": "Deploy", "length_s": round((f1 - f0) / DEPLOY_FPS, 4), "fps": DEPLOY_FPS,
                     "design_frames": [f0, f1], "design_stow_frames": [s1, s2], "samples": len(times),
                     "off_the_model_m": round(worst, 5), "bones": out,
                     "note": "the design's deploy from its first key to every bone out (rest = stowed = frame 1); played "
                             "backwards it stows"},
            **({"note": note} if note else {})}
    joints = [(b, p, tuple(at[j])) for j, (b, p, _) in enumerate(rig)]
    finish(part, mesh, info, joints, ("Deploy", times, chans), tex=tex)


turret("T16", ["T16_FWD", "T16_AFT"], "LEV_T16_FWD.001", "LEV_G16_FWD.001", D["LEV_G16_FWD_trunnion"].matrix_world.translation)
turret("T5", ["T5_%d" % k for k in range(1, 7)], "LEV_IOWA_T5_1.001", "LEV_IOWA_G5_1.001",
       D["LEV_IOWA_G5_1_trunnion"].matrix_world.translation)
turret("CIWS", ["CIWS_%d" % k for k in range(1, 5)], "LEV_IOWA_CIWS_1.001", "LEV_IOWA_CG_1.001",
       D["LEV_IOWA_CG_1_trunnion"].matrix_world.translation)
turret("LASER", ["LASER_FWD_L", "LASER_FWD_R", "LASER_AFT_L", "LASER_AFT_R"], "TANA_LASER_FWD_L_house",
       "TANA_LASER_FWD_L_gun", D["TANA_LASER_FWD_L_gun"].matrix_world.translation,
       D["TANA_LASER_FWD_L_SOC_Gun_01"].matrix_world.translation)
vls("VLSD", ["VLSD_%d" % k for k in range(1, 9)], "TANA_VLSD_1", "Y", -100.0)
for side in "LR":
    for k in range(1, 5):
        vls("VLSS_%s%d" % (side, k), ["VLSS_%s%d" % (side, k)], "TANA_VLSS_%s%d" % (side, k), "X", 115.0, tex="VLSS")
# the Alicorn's moving parts (the design's own rigs and keys): the bow's railcannon, its bay section (the trough under it,
# fixed) on Body; its two barrel halves are the bow's "doors": flush with the deck when stowed, they lift with the cannon
# (12 deg) and part about its long axis (14 deg each)
deploying("RAILCANNON", "railcannon", ["RAILCANNON"],
          [("Body", -1, "railcannon_bay"), ("railcannon_pitch", 0, "railcannon_pitch"),
           ("barrel_n", 1, "railcannon_barrel_n"), ("barrel_p", 1, "railcannon_barrel_p")],
          (1, (2, 3), 12.0),       # (the nose, 12 m: its cross-section's middle is the bore's line, 3.15 m over the trunnion)
          note="the bay section and RC_body on Body; the barrel halves (the bow's doors) on barrel_n / barrel_p")
# the sub-railguns: the same geometry in both sockets' frames (within 1 mm, measured 2026-11-10), but each trains
# outboard as it deploys (yaw +35 deg port, -35 starboard): a part each, one set of textures
for side in "LR":
    deploying("RAILGUN_" + side, "railgun", ["RAILGUN_" + side],
              [("Body", -1, "railgun_" + side), ("lift", 0, "railgun_%s_lift" % side), (TB_YAW, 1, "railgun_%s_yaw" % side),
               (TB_PITCH, 2, "railgun_%s_pitch" % side), ("Hatch_n", 0, "hatch_%s_door_n" % side),
               ("Hatch_p", 0, "hatch_%s_door_p" % side)],
              (3, (3,), 0.6), tex="RAILGUN",
              note="pedestal on lift (6 m down when stowed), house on BN_turret_yaw, rails on BN_turret_pitch (the stock "
                   "turrets' names: a stock fire control row can drive them), the hatch doors on Hatch_n / Hatch_p")

# the hull: the fused hull and the pods, in the ship's own frame (x forward, z up, the waterline at z = 0)
hull = Mesh()
for n in ("LEV_HULL.001", "CUT_ALC_SPONSON_L_FAIR.001", "CUT_ALC_SPONSON_R_FAIR.001"):
    hull.add(D[n], D[n].matrix_world, 0)
mounts = sorted((o for o in D if o.name.startswith("SOCKET_Mount_")), key=lambda o: o.name)
finish("HULL", hull, {"kind": "hull", "on": [],
                      "sockets": [{"name": o.name[len("SOCKET_"):], "loc": ue_cm(o.matrix_world.translation),
                                   "rot": ue_rot(o.matrix_world)} for o in mounts],
                      "not_included": ["the bow railcannon with its bay section and doors: part RAILCANNON on Mount_RAILCANNON",
                                       "the two sub-railguns with their hatches: parts RAILGUN_L / RAILGUN_R",
                                       "the phase-3 core: Mount_CORE, no part yet (WP11)"]},
       wreck=False)
used = sorted(n for p in MANIFEST.values() for n in p.get("on", []))
free = [o.name[len("SOCKET_Mount_"):] for o in mounts if o.name[len("SOCKET_Mount_"):] not in used]
with open(os.path.join(OUT, "parts.json"), "w") as f:
    json.dump(list(MANIFEST), f)
with open(os.path.join(OUT, "tanacorn_parts.json"), "w") as f:
    json.dump({"parts": MANIFEST, "hull_sockets": len(mounts), "sockets_without_a_part_yet": free}, f, indent=1)
print("export: %d parts; %d hull sockets, %d with a part, without one yet: %s" % (len(MANIFEST), len(mounts), len(used), free))
