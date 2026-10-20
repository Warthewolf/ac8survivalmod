"""pack.py [--name SurvivalMode_P] [--content mod/Content] [--out build/out]

Packs every zen package under mod/Content into a new IoStore container with retoc's pack-raw:
  - one ExportBundleData chunk per package (.uasset/.umap), .ubulk as BulkData
  - a container header listing every package and the packages it imports (Hard rule 7: derived from
    each package's own imported-package list, so new imports can't be forgotten)
  - a directory index (retoc builds it from the manifest's chunk paths)
Writes <out>/<name>.utoc/.ucas and <out>/container_header.bin.
"""
import os, sys, json, struct, shutil, subprocess, argparse
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, 'scripts'))
from zenpkg import ZenPkg, package_id
from cityhash import city64
import chdr

ap = argparse.ArgumentParser()
ap.add_argument('--name', default='SurvivalMode_P')
ap.add_argument('--content', default=os.path.join(ROOT, 'mod', 'Content'))
ap.add_argument('--out', default=os.path.join(ROOT, 'build', 'out'))
a = ap.parse_args()

# An empty UE5.4 container header: magic 'nCoI', version 3, container id (set below), no packages, and the
# five empty trailing sections (redirects, soft package references) as 20 zero bytes.
EMPTY_HEADER = (bytes.fromhex('6e436f4903000000') + bytes(8) + struct.pack('<i', 0) + struct.pack('<i', 0) + bytes(20))
RETOC = os.path.join(HERE, 'bin', 'retoc.exe')


def chunk_id(pid, typ, index=0):
    return struct.pack('<Q', pid) + struct.pack('<H', index) + b'\0' + bytes([typ])


raw = os.path.join(ROOT, 'build', 'raw_' + a.name)
shutil.rmtree(raw, ignore_errors=True); os.makedirs(os.path.join(raw, 'chunks'))
paths, ids, imports = {}, [], []
for root, _, files in os.walk(a.content):
    for f in sorted(files):
        fp = os.path.join(root, f); rel = os.path.relpath(fp, a.content).replace(os.sep, '/')
        stem, ext = os.path.splitext(rel)
        game = '/Game/' + stem; pid = package_id(game)
        if ext in ('.uasset', '.umap'):
            data = open(fp, 'rb').read(); z = ZenPkg(data=data)
            assert z.names[z.name_idx] == game, (z.names[z.name_idx], game)   # package name must match its path
            cid = chunk_id(pid, 1)
            ids.append(pid); imports.append([package_id(p) for p in z.imp_pkgs])
        elif ext == '.ubulk':
            cid = chunk_id(pid, 2)
        else:
            continue
        shutil.copyfile(fp, os.path.join(raw, 'chunks', cid.hex()))
        paths[cid.hex()] = '../../../Live/Content/' + rel
        print(f'{game}{ext}  {os.path.getsize(fp)} bytes' + (f'  imports {len(imports[-1])}' if ext != '.ubulk' else ''))

# container header
cont_id = city64(a.name.lower().encode('utf-16-le'))
H = chdr.CHdr(EMPTY_HEADER)
H.head = H.head[:8] + struct.pack('<Q', cont_id)
H.ids = ids; H.imports = imports; H.shaders = [[] for _ in ids]
hdr = H.write()
hid = chunk_id(cont_id, 6)
open(os.path.join(raw, 'chunks', hid.hex()), 'wb').write(hdr)
json.dump({'chunk_paths': paths, 'version': 'OnDemandMetaData', 'mount_point': '../../../'},
          open(os.path.join(raw, 'manifest.json'), 'w'), indent=1)

os.makedirs(a.out, exist_ok=True)
utoc = os.path.join(a.out, a.name + '.utoc')
subprocess.run([RETOC, 'pack-raw', raw, utoc], check=True)
open(os.path.join(a.out, 'container_header.bin'), 'wb').write(hdr)

# The game reads every compression block rounded up to 16 bytes (the AES block size), encrypted or not.
# pack-raw ends the .ucas right after the last block, so a last block whose size isn't a multiple of 16 is read
# past the end of the file and the whole container fails to mount ("Failed reading 576 bytes at offset ...").
# Pad the .ucas with zeros so every rounded-up read fits, then check every block against the same rule.
sys.path.insert(0, os.path.join(HERE, 'scripts'))
from utoc import Utoc
ucas = utoc[:-5] + '.ucas'
toc = Utoc(utoc)
need = max(off + ((csz + 15) & ~15) for off, csz, usz, m in toc.blocks)
have = os.path.getsize(ucas)
if need > have:
    with open(ucas, 'ab') as f: f.write(b'\0' * (need - have))
    print(f'padded {os.path.basename(ucas)} by {need - have} bytes so the last block can be read whole')
size = os.path.getsize(ucas)
for i, (off, csz, usz, m) in enumerate(toc.blocks):
    assert off + ((csz + 15) & ~15) <= size, f'block {i} at {off} (+{csz}) reads past the end of the .ucas ({size})'
print(f'checked {len(toc.blocks)} blocks: every 16-byte-aligned read fits in the {size}-byte .ucas')
info = subprocess.run([RETOC, 'info', utoc], capture_output=True, text=True).stdout
print(info)
assert f'FIoContainerId({cont_id:016x})' in info, 'retoc gave the container a different id'
assert f'packages: {len(ids)}' in info
