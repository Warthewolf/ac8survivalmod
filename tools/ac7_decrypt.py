"""Decrypt Ace Combat 7 assets ("ACE7" header) into plain UE 4.18 .uasset/.umap + .uexp, for reading only.

    python -I tools/ac7_decrypt.py <export root> <out root> [path regex]

The scheme is UAssetAPI's AC7Decrypt (atenfyr, MIT): a byte stream XORed with AC7Key.bin[pk1 * 1024 + pk2] ^ 0x77,
pk1 / pk2 seeded from the upper-cased file name, the .uexp continuing the .uasset's stream. The key table
(217 x 1024 bytes, UAssetAPI/Resources/AC7Key.bin) lives in build/ac7/ and is never committed or shipped.
"""
import os, re, sys

KEY = open(os.path.join(os.path.dirname(__file__), '..', 'build', 'ac7', 'AC7Key.bin'), 'rb').read()
assert len(KEY) == 217 * 1024
MAGIC = b'\xc1\x83\x2a\x9e'


def name_key(fname):
    n = 0
    for ch in fname.upper().encode('latin-1'):
        n = (n ^ ch) & 0xffffffff
        m = (~((n * 8) ^ n)) & 0xffffffff
        n = ((m >> 7) & 1) | ((n + n) & 0xffffffff)
    return n


def pkeys(nkey, off=4):
    num = ((nkey * 7) & 0xffffffff) + off
    q = (5440514381186227205 * num) >> 70
    pk1 = (num - q * 217) & 0xffffffff
    pk2 = (((nkey * 11) & 0xffffffff) + off) & 0x3ff
    return pk1, pk2


def stream(pk1, pk2, n):
    """n key bytes from (pk1, pk2), and the state after them."""
    out = bytearray(n)
    for i in range(n):
        out[i] = KEY[pk1 * 1024 + pk2] ^ 0x77
        pk1 = pk1 + 1 if pk1 < 216 else 0
        pk2 = pk2 + 1 if pk2 < 1023 else 0
    return out, pk1, pk2


def xor(data, ks):
    return (int.from_bytes(data, 'little') ^ int.from_bytes(ks, 'little')).to_bytes(len(data), 'little')


def decrypt(src, dst):
    stem = os.path.splitext(os.path.basename(src))[0]
    pk1, pk2 = pkeys(name_key(stem))
    a = open(src, 'rb').read()
    if a[:4] != b'ACE7':
        return False
    ks, pk1, pk2 = stream(pk1, pk2, len(a) - 4)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    open(dst, 'wb').write(MAGIC + xor(a[4:], ks))
    ue = os.path.splitext(src)[0] + '.uexp'
    if os.path.exists(ue):
        e = open(ue, 'rb').read()
        ks, _, _ = stream(pk1, pk2, len(e))
        open(os.path.splitext(dst)[0] + '.uexp', 'wb').write(xor(e, ks)[:-4] + MAGIC)
    return True


if __name__ == '__main__':
    root, out = sys.argv[1], sys.argv[2]
    pat = re.compile(sys.argv[3], re.I) if len(sys.argv) > 3 else None
    n = 0
    for dp, _, fs in os.walk(root):
        for f in fs:
            if not f.endswith(('.uasset', '.umap')):
                continue
            rel = os.path.relpath(os.path.join(dp, f), root).replace('\\', '/')
            if pat and not pat.search(rel):
                continue
            if decrypt(os.path.join(dp, f), os.path.join(out, rel)):
                n += 1
    print('decrypted', n)
