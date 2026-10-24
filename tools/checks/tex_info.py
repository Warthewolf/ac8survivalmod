"""tex_info.py <zen package> ... : what a cooked texture or material package is, for AC8's texture questions
(tools/re/AIRCRAFT_MATERIALS.md).

  texture:  size, pixel format, virtual or ordinary; virtual: layers, blocks (UDIM tiles), VT tile size and border
  material: which vertex factories its shader map covers (Local = static meshes / billboards, GPUSkin = skeletal
            meshes, Niagara... = particles) and whether it samples virtual textures (FMaterialVirtualTextureStack)

A path can be a stock package under build/stock (tools/get_stock.sh fetches one) or an unpacked container's file
(retoc unpack). Reads only.
    python -I tools/checks/tex_info.py build/stock/Base/Texture/Common/T_UDIM_Color.uasset
"""
import re
import struct
import sys

PF = re.compile(rb'(?P<len>[\x05-\x20])\x00\x00\x00(?P<name>PF_[A-Za-z0-9_]+)\x00')


def texture(d):
    """The first cooked platform data in the package, or None."""
    for m in PF.finditer(d):
        if len(m.group('name')) + 1 != m.group('len')[0]:
            continue                                   # (a name-table entry, not an FString)
        e = m.end()
        if m.start() < 12 or e + 12 > len(d):
            continue
        sx, sy, packed = struct.unpack_from('<iii', d, m.start() - 12)
        skip, virtual = struct.unpack_from('<qI', d, e)
        if not (0 < sx <= 65536 and 0 < sy <= 65536) or virtual not in (0, 1):
            continue
        out = {'size': f'{sx} x {sy}', 'format': m.group('name').decode(), 'virtual': bool(virtual)}
        if virtual and e + 36 <= len(d):
            layers, _, wb, hb, tile, border = struct.unpack_from('<6I', d, e + 12)
            out.update(layers=layers, blocks=f'{wb} x {hb}', tile=f'{tile} + {border}')
        return out
    return None


def material(d):
    vf = sorted(set(m.decode() for m in re.findall(rb'F([A-Za-z]+)VertexFactoryShaderParameters', d)))
    if not vf:
        return None
    return {'vertex factories': ', '.join(vf), 'virtual textures': b'FMaterialVirtualTextureStack' in d}


def main(paths):
    for p in paths:
        try:
            d = open(p, 'rb').read()
        except OSError as e:
            print(f'{p}: {e}')
            continue
        info = texture(d) or material(d)
        name = p.replace('\\', '/').rsplit('/', 1)[-1]
        print(f'{name}: ' + (', '.join(f'{k} {v}' for k, v in info.items()) if info else 'neither a texture nor a material with a shader map'))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
