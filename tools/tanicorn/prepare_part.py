"""prepare_part.py : Blender 3.3, one Tanicorn gun mount from build/tanicorn/src.blend -> glTF for UE 5.4.

  blender -b build/tanicorn/src.blend -P tools/tanicorn/prepare_part.py -- <out dir> <part name> <housing obj> <guns obj> <scale>

Writes into <out dir>:
  <part>.gltf / .bin      skinned: joints Body > turret_yaw > turret_pitch, every joint with an identity rotation (the
                          Alicorn's turret rigs: S_BA002_alcn_ram / _emls), the housing on turret_yaw, the guns on
                          turret_pitch; the mount faces +X (its guns' rest heading turned to forward), metres
  <part>_DAM.gltf / .bin  the same geometry static (the wreck the destroy system swaps in)
  T_<part>_<n>_D.png      each material's texture as the Alicorn's grey (the Iowa's own texture kept only as light and
                          shade, as the Leviathan renders), T_<part>_N.png flat normal, T_<part>_L.png blank livemap
  <part>.json             bones (UE cm, parent space), muzzle sockets on turret_pitch (UE cm), material slots
glTF is Y-up: Blender (x, y, z) -> glTF (x, z, -y); UE's glTF import takes it to UE (x fwd, y right, z up) in cm.
The Tanicorn's mounts come from the Tanager stand-in (Sea Power's Iowa): dev install only, never shipped.
"""
import bpy, bmesh, sys, os, json, math, struct
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, PART, HOUSE, GUNS, SCALE = argv[0], argv[1], argv[2], argv[3], float(argv[4])
os.makedirs(OUT, exist_ok=True)
GREY = (0.058, 0.059, 0.062)          # the Alicorn plating's mean colour (linear), as the Leviathan's upper works


def world_tris(obj, M):
    """[(material image path, [(pos, normal, uv) x3])] of an object, positions through M (4x4)."""
    me = obj.data
    me.calc_normals_split()
    uv = me.uv_layers.active.data if me.uv_layers.active else None
    out = []
    N3 = M.to_3x3().inverted().transposed()
    for poly in me.polygons:
        mat = obj.material_slots[poly.material_index].material if obj.material_slots else None
        img = None
        if mat and mat.use_nodes:
            for n in mat.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and any(l.to_socket.name == "Base Color" for l in n.outputs[0].links):
                    img = bpy.path.abspath(n.image.filepath)
                    if not os.path.exists(img):          # (moved with the blend: the Iowa's textures beside it)
                        alt = os.path.join(os.path.dirname(bpy.data.filepath), "iowa", "textures", os.path.basename(img))
                        img = alt if os.path.exists(alt) else img
        loops = list(poly.loop_indices)
        corners = []
        for li in loops:
            v = me.vertices[me.loops[li].vertex_index].co
            p = M @ v
            nrm = (N3 @ me.loops[li].normal).normalized()
            t = tuple(uv[li].uv) if uv else (0.0, 0.0)
            corners.append((p, nrm, t))
        for i in range(1, len(corners) - 1):
            out.append((img, [corners[0], corners[i], corners[i + 1]]))
    return out


house, guns = bpy.data.objects[HOUSE], bpy.data.objects[GUNS]
tp, gp = house.location.copy(), guns.location.copy()
# the guns' rest heading: their mesh's centroid from their pivot, in the horizontal plane
gv = [guns.matrix_world @ v.co for v in guns.data.vertices]
c = sum(gv, Vector()) / len(gv)
head = math.atan2(c.y - gp.y, c.x - gp.x)
R = Matrix.Rotation(-head, 4, "Z")
S = Matrix.Diagonal((SCALE, SCALE, SCALE, 1.0))
T0 = Matrix.Translation(-tp)
M_house = R @ S @ T0 @ house.matrix_world          # the mount's space: base pivot at the origin, guns along +X
M_guns = R @ S @ T0 @ guns.matrix_world
pitch_at = (R @ S @ T0 @ gp.to_4d()).to_3d()
tris = [(0, t) for t in world_tris(house, M_house)] + [(1, t) for t in world_tris(guns, M_guns)]
print("prepare_part: %s %d triangles, heading %.1f deg, pitch pivot %s" % (PART, len(tris), math.degrees(head), tuple(round(x, 2) for x in pitch_at)))

# muzzles: the guns' farthest-forward vertices on each side (twin mount: y>0 and y<0)
gw = [M_guns @ v.co for v in guns.data.vertices]
muzzles = []
for side in (1, -1):
    pts = [p for p in gw if p.y * side > 0.05]
    if not pts:
        continue
    tip = max(pts, key=lambda p: p.x)
    near = [p for p in pts if p.x > tip.x - 0.4]
    ctr = sum(near, Vector()) / len(near)
    muzzles.append(Vector((tip.x, ctr.y, ctr.z)))
muzzles.sort(key=lambda p: -p.y)          # SOC_Gun_01 port (Blender +y), _02 starboard


def to_gltf(v):
    return (v.x, v.z, -v.y)


def to_ue_cm(v):                           # Blender m -> UE cm (y flips)
    return [round(v.x * 100, 3), round(-v.y * 100, 3), round(v.z * 100, 3)]


# materials: one slot per distinct source image
imgs = []
for _, (img, _) in tris:
    if img not in imgs:
        imgs.append(img)


def grey_texture(src, dst):
    if src and os.path.exists(src):
        im = bpy.data.images.load(src)
    else:
        im = None
    w, h = (im.size[0], im.size[1]) if im else (4, 4)
    px = list(im.pixels[:]) if im else [0.5] * (w * h * 4)
    out = bpy.data.images.new(os.path.basename(dst), w, h, alpha=False)
    o = [0.0] * (w * h * 4)
    for i in range(w * h):
        r, g, b = px[i * 4], px[i * 4 + 1], px[i * 4 + 2]
        lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        k = 0.75 + (min(max(lum, 0.1), 0.7) - 0.1) / 0.6 * 0.45
        for j in range(3):
            lin = GREY[j] * k
            o[i * 4 + j] = (1.055 * lin ** (1 / 2.4) - 0.055) if lin > 0.0031308 else lin * 12.92
        o[i * 4 + 3] = 1.0
    out.pixels[:] = o
    out.filepath_raw = dst
    out.file_format = "PNG"
    out.save()


slots = []
for k, img in enumerate(imgs):
    name = "T_SV_%s_%d_D" % (PART, k)
    grey_texture(img, os.path.join(OUT, name + ".png"))
    slots.append({"slot": k, "source": os.path.basename(img) if img else None, "basecolor": name})
for name, val in (("T_SV_%s_N" % PART, (0.5, 0.5, 1.0)), ("T_SV_%s_L" % PART, (0.0, 0.0, 0.0))):
    im = bpy.data.images.new(name, 4, 4, alpha=False)
    im.pixels[:] = [*val, 1.0] * 16
    im.filepath_raw = os.path.join(OUT, name + ".png"); im.file_format = "PNG"; im.save()


def write_gltf(path, skinned):
    """One mesh, a primitive per material, unshared vertices (flat corners); joints if skinned."""
    bins = bytearray()
    views, accs, prims = [], [], []

    def add(data, fmt, count, comp, typ, target=None, minmax=None):
        while len(bins) % 4:
            bins.append(0)
        off = len(bins)
        bins.extend(data)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), **({"target": target} if target else {})})
        a = {"bufferView": len(views) - 1, "componentType": comp, "count": count, "type": typ}
        if minmax:
            a["min"], a["max"] = minmax
        accs.append(a)
        return len(accs) - 1
    for k in range(len(imgs)):
        sel = [(part, t) for part, (img, t) in tris if img == imgs[k]]
        P, Nn, UV, J, Wt = [], [], [], [], []
        for part, corners in sel:
            for p, n, t in corners:
                P.append(to_gltf(p)); Nn.append(to_gltf(n)); UV.append((t[0], 1.0 - t[1]))
                J.append((1 if part == 0 else 2, 0, 0, 0)); Wt.append((1.0, 0, 0, 0))
        n = len(P)
        mn = [min(p[i] for p in P) for i in range(3)]; mx = [max(p[i] for p in P) for i in range(3)]
        attrs = {
            "POSITION": add(b"".join(struct.pack("<3f", *p) for p in P), None, n, 5126, "VEC3", 34962, (mn, mx)),
            "NORMAL": add(b"".join(struct.pack("<3f", *p) for p in Nn), None, n, 5126, "VEC3", 34962),
            "TEXCOORD_0": add(b"".join(struct.pack("<2f", *p) for p in UV), None, n, 5126, "VEC2", 34962),
        }
        if skinned:
            attrs["JOINTS_0"] = add(b"".join(struct.pack("<4H", *j) for j in J), None, n, 5123, "VEC4", 34962)
            attrs["WEIGHTS_0"] = add(b"".join(struct.pack("<4f", *w) for w in Wt), None, n, 5126, "VEC4", 34962)
        prims.append({"attributes": attrs, "material": k})
    mats = [{"name": "M_SV_%s_%d" % (PART, k), "pbrMetallicRoughness": {"baseColorFactor": [*GREY, 1.0]}} for k in range(len(imgs))]
    nodes, skins = [], []
    if skinned:
        pw = Vector(to_gltf(pitch_at))
        nodes = [
            {"name": "Body", "children": [1]},
            {"name": "turret_yaw", "children": [2]},
            {"name": "turret_pitch", "translation": list(pw)},
            {"name": PART, "mesh": 0, "skin": 0},
        ]
        ibm = b""
        for t in ((0, 0, 0), (0, 0, 0), tuple(pw)):        # inverse bind: translation only (identity rotations)
            m = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -t[0], -t[1], -t[2], 1]
            ibm += struct.pack("<16f", *m)
        skins = [{"joints": [0, 1, 2], "skeleton": 0, "inverseBindMatrices": add(ibm, None, 3, 5126, "MAT4")}]
        scene_nodes = [0, 3]
    else:
        nodes = [{"name": PART + "_DAM", "mesh": 0}]
        scene_nodes = [0]
    doc = {"asset": {"version": "2.0", "generator": "Survival tanicorn/prepare_part.py"},
           "scene": 0, "scenes": [{"nodes": scene_nodes}], "nodes": nodes,
           "meshes": [{"name": os.path.basename(path)[:-5], "primitives": prims}], "materials": mats,
           "buffers": [{"uri": os.path.basename(path)[:-5] + ".bin", "byteLength": len(bins)}],
           "bufferViews": views, "accessors": accs}
    if skins:
        doc["skins"] = skins
    with open(path[:-5] + ".bin", "wb") as f:
        f.write(bins)
    with open(path, "w") as f:
        json.dump(doc, f, indent=1)


write_gltf(os.path.join(OUT, PART + ".gltf"), True)
write_gltf(os.path.join(OUT, PART + "_DAM.gltf"), False)
info = {"part": PART, "scale": SCALE, "heading_deg": math.degrees(head),
        "bones": {"Body": [0, 0, 0], "turret_yaw": [0, 0, 0], "turret_pitch": to_ue_cm(pitch_at)},
        "sockets": [{"name": "SOC_Gun_%02d" % (i + 1), "bone": "turret_pitch",
                     "loc": [a - b for a, b in zip(to_ue_cm(m), to_ue_cm(pitch_at))]} for i, m in enumerate(muzzles)],
        "slots": slots, "triangles": len(tris)}
with open(os.path.join(OUT, PART + ".json"), "w") as f:
    json.dump(info, f, indent=1)
print("prepare_part: wrote", PART, json.dumps({k: info[k] for k in ("bones", "sockets", "slots")}))
